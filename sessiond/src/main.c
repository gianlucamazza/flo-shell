/*
 * flo-sessiond: touch boost and background app freezer for flo-shell.
 * Single-threaded epoll loop; blocks with no timeout when there is nothing
 * to do. SPDX-License-Identifier: MIT
 */
#include "sessiond.h"

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/resource.h>
#include <sys/signalfd.h>
#include <sys/socket.h>
#include <sys/timerfd.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

/* 3 stdio + epoll, signalfd, listener, 3 timers, 2 inotify, input, state
 * file, cgroup root, MAX_CLIENTS clients and a few transient ones. */
#define MIN_NOFILE (MAX_CLIENTS + 32)

struct config cfg;
uint64_t loop_wakeups;
static int epfd = -1;

static uint64_t ep_data(enum ep_tag tag, uint64_t id)
{
	return ((uint64_t)tag << 56) | (id & 0x00ffffffffffffffULL);
}

int ep_add(int fd, uint32_t events, enum ep_tag tag, uint64_t id)
{
	struct epoll_event ev = { .events = events, .data.u64 = ep_data(tag, id) };
	return epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev);
}

int ep_mod(int fd, uint32_t events, enum ep_tag tag, uint64_t id)
{
	struct epoll_event ev = { .events = events, .data.u64 = ep_data(tag, id) };
	return epoll_ctl(epfd, EPOLL_CTL_MOD, fd, &ev);
}

void ep_del(int fd)
{
	epoll_ctl(epfd, EPOLL_CTL_DEL, fd, NULL);
}

int timer_new(enum ep_tag tag)
{
	int fd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC);
	if (fd < 0)
		return -1;
	if (ep_add(fd, EPOLLIN, tag, 0) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

/* One-shot, absolute CLOCK_MONOTONIC. A deadline in the past fires at once. */
void timer_arm(int tfd, int64_t deadline_ns)
{
	if (deadline_ns < 1)
		deadline_ns = 1;
	struct itimerspec its = { 0 };
	its.it_value.tv_sec = (time_t)(deadline_ns / 1000000000LL);
	its.it_value.tv_nsec = (long)(deadline_ns % 1000000000LL);
	timerfd_settime(tfd, TFD_TIMER_ABSTIME, &its, NULL);
}

void timer_disarm(int tfd)
{
	struct itimerspec its = { 0 };
	timerfd_settime(tfd, 0, &its, NULL);
}

void timer_ack(int tfd)
{
	uint64_t n;
	ssize_t r = read(tfd, &n, sizeof n);
	(void)r;
}

void inotify_drain(int fd)
{
	char buf[2048];
	for (int i = 0; i < 16; i++)
		if (read(fd, buf, sizeof buf) <= 0)
			break;
}

/* sd_notify(3) by hand: one datagram to $NOTIFY_SOCKET. */
static void notify(const char *msg)
{
	const char *path = getenv("NOTIFY_SOCKET");
	struct sockaddr_un sa = { .sun_family = AF_UNIX };
	if (!path || (path[0] != '/' && path[0] != '@') || strlen(path) >= sizeof sa.sun_path)
		return;
	size_t plen = strlen(path);
	memcpy(sa.sun_path, path, plen);
	if (path[0] == '@')
		sa.sun_path[0] = '\0'; /* abstract namespace */
	int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return;
	socklen_t len = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + plen);
	ssize_t r = sendto(fd, msg, strlen(msg), MSG_NOSIGNAL, (struct sockaddr *)&sa, len);
	(void)r;
	close(fd);
}

/*
 * Fatal signal: put the frequency floors back and thaw what we froze, then
 * die with the original signal so the core dump and exit status are intact.
 * Only async-signal-safe calls on static tables.
 */
static void crash_handler(int sig)
{
	boost_emergency();
	freezer_emergency();
	/* SA_RESETHAND restored the default action; the signal is blocked while
	 * we are here and is delivered as soon as we return. */
	raise(sig);
}

static char crash_stack[64 * 1024];

static void crash_handlers_install(void)
{
	stack_t ss = { .ss_sp = crash_stack, .ss_size = sizeof crash_stack };
	sigaltstack(&ss, NULL);
	struct sigaction sa = { 0 };
	sa.sa_handler = crash_handler;
	sa.sa_flags = SA_RESETHAND | SA_ONSTACK;
	sigemptyset(&sa.sa_mask);
	static const int sigs[] = { SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGABRT };
	for (size_t i = 0; i < sizeof sigs / sizeof sigs[0]; i++)
		sigaction(sigs[i], &sa, NULL);
}

static void usage(FILE *f)
{
	fprintf(f,
		"usage: flo-sessiond [-c FILE] [-o key=value]... [-t]\n"
		"  -c FILE       configuration file (default " FLO_DEFAULT_CONFIG ",\n"
		"                which may be missing)\n"
		"  -o key=value  override one setting (repeatable, applied after the file)\n"
		"  -t            check the configuration, print it and exit\n"
		"  -V            print the version\n");
}

int main(int argc, char **argv)
{
	const char *conf = NULL;
	bool check = false;
	char err[512];
	const char *overrides[64];
	int nover = 0;

	int opt;
	while ((opt = getopt(argc, argv, "c:o:tVh")) != -1) {
		switch (opt) {
		case 'c':
			conf = optarg;
			break;
		case 'o':
			if (nover < 64)
				overrides[nover++] = optarg;
			break;
		case 't':
			check = true;
			break;
		case 'V':
			puts("flo-sessiond " FLO_VERSION);
			return 0;
		case 'h':
			usage(stdout);
			return 0;
		default:
			usage(stderr);
			return 2;
		}
	}
	if (optind != argc) {
		usage(stderr);
		return 2;
	}

	config_defaults(&cfg);
	if (conf || access(FLO_DEFAULT_CONFIG, F_OK) == 0) {
		if (config_load(&cfg, conf ? conf : FLO_DEFAULT_CONFIG, err, sizeof err) < 0) {
			fprintf(stderr, "flo-sessiond: %s\n", err);
			return 2;
		}
	}
	for (int i = 0; i < nover; i++) {
		char kv[1024];
		snprintf(kv, sizeof kv, "%s", overrides[i]);
		char *eq = strchr(kv, '=');
		if (!eq) {
			fprintf(stderr, "flo-sessiond: -o expects key=value\n");
			return 2;
		}
		*eq = '\0';
		if (config_set(&cfg, kv, eq + 1, err, sizeof err) < 0) {
			fprintf(stderr, "flo-sessiond: %s\n", err);
			return 2;
		}
	}
	if (config_validate(&cfg, err, sizeof err) < 0) {
		fprintf(stderr, "flo-sessiond: %s\n", err);
		return 2;
	}
	if (check) {
		static char text[4096];
		struct sbuf sb = { text, 0, sizeof text, false };
		config_dump(&cfg, &sb);
		fputs(text, stdout);
		return 0;
	}
	log_level = cfg.log_level;

	/* Termination signals are taken synchronously through a signalfd. */
	sigset_t mask;
	sigemptyset(&mask);
	sigaddset(&mask, SIGTERM);
	sigaddset(&mask, SIGINT);
	sigaddset(&mask, SIGHUP);
	sigprocmask(SIG_BLOCK, &mask, NULL);
	signal(SIGPIPE, SIG_IGN);

	/* accept(2) failing with EMFILE on a level-triggered listener would
	 * spin: make sure the fixed-size tables can never exhaust the limit. */
	struct rlimit rl;
	if (getrlimit(RLIMIT_NOFILE, &rl) == 0 && rl.rlim_cur < MIN_NOFILE) {
		rl.rlim_cur = MIN_NOFILE;
		if (rl.rlim_max < MIN_NOFILE || setrlimit(RLIMIT_NOFILE, &rl) < 0) {
			log_msg(LOG_ERR, "RLIMIT_NOFILE below %d", MIN_NOFILE);
			return 1;
		}
	}

	epfd = epoll_create1(EPOLL_CLOEXEC);
	int sfd = signalfd(-1, &mask, SFD_NONBLOCK | SFD_CLOEXEC);
	if (epfd < 0 || sfd < 0 || ep_add(sfd, EPOLLIN, TAG_SIGNAL, 0) < 0) {
		log_msg(LOG_ERR, "event loop setup failed: %s", strerror(errno));
		return 1;
	}
	crash_handlers_install();

	int rc = 1;
	/* The socket comes first: binding it is also what tells a second
	 * instance to go away before it touches any state. */
	if (server_init() < 0) {
		log_msg(LOG_ERR, "cannot set up the control socket");
		return 1;
	}
	if (boost_init() < 0 || freezer_init() < 0) {
		log_msg(LOG_ERR, "initialisation failed: %s", strerror(errno));
		goto out;
	}
	log_msg(LOG_INFO, "flo-sessiond %s ready", FLO_VERSION);
	notify("READY=1");

	bool running = true;
	while (running) {
		struct epoll_event evs[16];
		int n = epoll_wait(epfd, evs, 16, -1);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			log_msg(LOG_ERR, "epoll_wait: %s", strerror(errno));
			break;
		}
		loop_wakeups++;
		for (int i = 0; i < n; i++) {
			enum ep_tag tag = (enum ep_tag)(evs[i].data.u64 >> 56);
			uint64_t id = evs[i].data.u64 & 0x00ffffffffffffffULL;
			switch (tag) {
			case TAG_SIGNAL: {
				struct signalfd_siginfo si;
				while (read(sfd, &si, sizeof si) == (ssize_t)sizeof si) {
					if (si.ssi_signo == SIGHUP) {
						log_msg(LOG_INFO, "SIGHUP ignored: restart to reload");
						continue;
					}
					running = false;
					rc = 0;
				}
				break;
			}
			case TAG_LISTEN:
				server_on_listen();
				break;
			case TAG_INPUT:
				boost_on_input(evs[i].events, id);
				break;
			case TAG_INPUT_INOTIFY:
				boost_on_input_inotify();
				break;
			case TAG_BOOST_TIMER:
				boost_on_timer();
				break;
			case TAG_RETRY_TIMER:
				boost_on_retry();
				break;
			case TAG_FREEZE_TIMER:
				freezer_on_timer();
				break;
			case TAG_FREEZE_INOTIFY:
				freezer_on_inotify();
				break;
			case TAG_CLIENT:
				server_on_client(id, evs[i].events);
				break;
			}
		}
	}
out:
	notify("STOPPING=1");
	server_shutdown();
	freezer_shutdown();
	boost_shutdown();
	log_msg(LOG_INFO, "flo-sessiond stopped");
	return rc;
}
