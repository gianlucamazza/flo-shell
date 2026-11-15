/*
 * flo-sessiond: control socket.
 *
 * Line protocol over a unix stream socket: one command per line, printable
 * ASCII only, at most MAX_LINE bytes. Every command is answered by zero or
 * more data lines followed by exactly one line starting with "OK" or "ERR".
 * Claims (policy ownership, inhibits) belong to the connection and die with it.
 *
 * SPDX-License-Identifier: MIT
 */
#include "sessiond.h"

#include <errno.h>
#include <grp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

struct client {
	bool used, dead;
	int fd;
	uint64_t id;
	uid_t uid;
	pid_t pid;
	size_t len;
	char buf[MAX_LINE];
};

static struct client clients[MAX_CLIENTS];
static int listen_fd = -1;
static bool own_socket;
static uint64_t next_id = 1;
static uint64_t n_accepted, n_rejected;

static void reply(struct client *c, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

static void send_all(struct client *c, const char *buf, size_t len)
{
	if (c->dead)
		return;
	/* No output queue: a peer that does not read its replies is dropped. */
	ssize_t n = send(c->fd, buf, len, MSG_NOSIGNAL | MSG_DONTWAIT);
	if (n < 0 || (size_t)n != len)
		c->dead = true;
}

static void reply(struct client *c, const char *fmt, ...)
{
	char buf[MAX_LINE];
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(buf, sizeof buf - 1, fmt, ap);
	va_end(ap);
	if (n < 0)
		return;
	if ((size_t)n > sizeof buf - 2)
		n = (int)sizeof buf - 2;
	buf[n++] = '\n';
	send_all(c, buf, (size_t)n);
}

static void reply_errno(struct client *c, int r)
{
	switch (r) {
	case -EINVAL:
		reply(c, "ERR invalid-path path rejected");
		break;
	case -EPERM:
		reply(c, "ERR not-owner send \"freeze-policy on\" first");
		break;
	case -EBUSY:
		reply(c, "ERR busy another client owns the freeze policy");
		break;
	case -ENOTSUP:
		reply(c, "ERR disabled feature disabled in the configuration");
		break;
	case -ENOSPC:
	case -E2BIG:
		reply(c, "ERR limit too many");
		break;
	case -ENOENT:
		reply(c, "ERR not-found no such object");
		break;
	default:
		reply(c, "ERR failed %s", strerror(-r));
	}
}

static void cmd_status(struct client *c)
{
	static char text[24 * 1024];
	struct sbuf sb = { text, 0, sizeof text, false };
	int nclients = 0;
	for (int i = 0; i < MAX_CLIENTS; i++)
		nclients += clients[i].used;
	sb_printf(&sb, "version=%s\nprotocol=%d\n", FLO_VERSION, FLO_PROTOCOL);
	sb_printf(&sb, "loop.wakeups=%llu\n", (unsigned long long)loop_wakeups);
	sb_printf(&sb, "clients=%d\nclient.id=%llu\n", nclients, (unsigned long long)c->id);
	sb_printf(&sb, "clients.accepted=%llu\nclients.rejected=%llu\n",
		  (unsigned long long)n_accepted, (unsigned long long)n_rejected);
	boost_status(&sb);
	freezer_status(&sb);
	if (sb.truncated)
		sb_printf(&sb, "truncated=1\n");
	send_all(c, sb.buf, sb.len);
	reply(c, "OK");
}

static bool on_off(const char *s, bool *out)
{
	if (strcmp(s, "on") == 0)
		*out = true;
	else if (strcmp(s, "off") == 0)
		*out = false;
	else
		return false;
	return true;
}

#define MAX_ARGS 6

static void handle_line(struct client *c, char *line)
{
	/* Printable ASCII only. This also rejects NUL, tabs and CR. */
	for (const char *p = line; *p; p++) {
		if (*p < 0x20 || *p > 0x7e) {
			reply(c, "ERR invalid-input non-printable byte");
			c->dead = true;
			return;
		}
	}
	char *argv[MAX_ARGS];
	int argc = 0;
	char *rest = line;
	const char *tail = NULL; /* inhibit only: the reason, kept as typed */
	while (argc < MAX_ARGS) {
		while (*rest == ' ')
			rest++;
		if (!*rest)
			break;
		if (argc == 2 && !strcmp(argv[0], "inhibit")) {
			tail = rest;
			break;
		}
		argv[argc++] = rest;
		while (*rest && *rest != ' ')
			rest++;
		if (*rest)
			*rest++ = '\0';
	}
	while (!tail && *rest == ' ')
		rest++;
	bool overflow = !tail && *rest != '\0';
	if (argc == 0) {
		reply(c, "ERR syntax empty command");
		return;
	}
	const char *cmd = argv[0];
	bool flag;
	long num;
	int r;

	if (!strcmp(cmd, "inhibit")) {
		/* inhibit <path> <reason, free text to the end of the line> */
		if (!tail) {
			reply(c, "ERR syntax inhibit <path> <reason>");
			return;
		}
		unsigned token;
		r = freezer_inhibit(c->id, argv[1], tail, &token);
		if (r < 0)
			reply_errno(c, r);
		else
			reply(c, "OK %u", token);
		return;
	}
	if (overflow) {
		reply(c, "ERR syntax too many arguments");
		return;
	}
	if (!strcmp(cmd, "ping") && argc == 1) {
		reply(c, "OK");
	} else if (!strcmp(cmd, "version") && argc == 1) {
		reply(c, "OK flo-sessiond %s protocol %d", FLO_VERSION, FLO_PROTOCOL);
	} else if (!strcmp(cmd, "status") && argc == 1) {
		cmd_status(c);
	} else if (!strcmp(cmd, "boost") && argc <= 2) {
		num = cfg.boost_hold_ms;
		if (argc == 2 && !parse_long(argv[1], 1, 3600000, &num)) {
			reply(c, "ERR syntax boost [<milliseconds>]");
			return;
		}
		r = boost_request((int)num);
		if (r < 0)
			reply_errno(c, r);
		else
			reply(c, "OK %d", r);
	} else if (!strcmp(cmd, "freeze-policy") && argc == 2 && on_off(argv[1], &flag)) {
		r = freezer_set_policy(c->id, flag);
		if (r < 0)
			reply_errno(c, r);
		else
			reply(c, "OK");
	} else if (!strcmp(cmd, "lock") && argc == 2 && on_off(argv[1], &flag)) {
		r = freezer_set_locked(c->id, flag);
		if (r < 0)
			reply_errno(c, r);
		else
			reply(c, "OK");
	} else if (!strcmp(cmd, "foreground") && argc >= 2 && argc <= 1 + MAX_FG) {
		int n = argc - 1;
		if (n == 1 && !strcmp(argv[1], "-"))
			n = 0;
		r = freezer_set_foreground(c->id, (const char *const *)&argv[1], n);
		if (r < 0)
			reply_errno(c, r);
		else
			reply(c, "OK");
	} else if (!strcmp(cmd, "uninhibit") && argc == 2) {
		if (!parse_long(argv[1], 1, 2147483647L, &num)) {
			reply(c, "ERR syntax uninhibit <token>");
			return;
		}
		r = freezer_uninhibit(c->id, (unsigned)num);
		if (r < 0)
			reply(c, "ERR no-such-token not an inhibit of this connection");
		else
			reply(c, "OK");
	} else if (!strcmp(cmd, "thaw") && argc == 2) {
		r = freezer_thaw(argv[1]);
		if (r < 0)
			reply_errno(c, r);
		else
			reply(c, "OK");
	} else if (!strcmp(cmd, "thaw-all") && argc == 1) {
		r = freezer_thaw_all();
		if (r < 0)
			reply_errno(c, r);
		else
			reply(c, "OK %d", r);
	} else if (!strcmp(cmd, "ping") || !strcmp(cmd, "version") || !strcmp(cmd, "status") ||
		   !strcmp(cmd, "boost") || !strcmp(cmd, "freeze-policy") || !strcmp(cmd, "lock") ||
		   !strcmp(cmd, "foreground") || !strcmp(cmd, "uninhibit") || !strcmp(cmd, "thaw") ||
		   !strcmp(cmd, "thaw-all")) {
		reply(c, "ERR syntax bad arguments for %s", cmd);
	} else {
		reply(c, "ERR unknown-command");
	}
}

static void client_close(struct client *c)
{
	if (!c->used)
		return;
	ep_del(c->fd);
	close(c->fd);
	c->used = false;
	freezer_client_gone(c->id);
}

static struct client *client_by_id(uint64_t id)
{
	for (int i = 0; i < MAX_CLIENTS; i++)
		if (clients[i].used && clients[i].id == id)
			return &clients[i];
	return NULL;
}

void server_on_client(uint64_t id, uint32_t events)
{
	struct client *c = client_by_id(id);
	if (!c)
		return; /* closed earlier in this batch of events */
	(void)events;
	ssize_t n = recv(c->fd, c->buf + c->len, sizeof c->buf - c->len, MSG_DONTWAIT);
	if (n < 0 && (errno == EAGAIN || errno == EINTR))
		return;
	if (n <= 0) {
		client_close(c);
		return;
	}
	if (memchr(c->buf + c->len, '\0', (size_t)n)) {
		reply(c, "ERR invalid-input NUL byte");
		client_close(c);
		return;
	}
	c->len += (size_t)n;
	size_t start = 0;
	while (!c->dead) {
		char *nl = memchr(c->buf + start, '\n', c->len - start);
		if (!nl)
			break;
		*nl = '\0';
		handle_line(c, c->buf + start);
		start = (size_t)(nl - c->buf) + 1;
	}
	if (!c->dead && start == 0 && c->len == sizeof c->buf) {
		/* A full buffer without a newline: longer than MAX_LINE. */
		reply(c, "ERR line-too-long limit is %d bytes", MAX_LINE);
		c->dead = true;
	}
	if (c->dead) {
		client_close(c);
		return;
	}
	memmove(c->buf, c->buf + start, c->len - start);
	c->len -= start;
}

void server_on_listen(void)
{
	int fd = accept4(listen_fd, NULL, NULL, SOCK_CLOEXEC | SOCK_NONBLOCK);
	if (fd < 0)
		return;
	struct client *c = NULL;
	for (int i = 0; i < MAX_CLIENTS && !c; i++)
		if (!clients[i].used)
			c = &clients[i];
	if (!c) {
		/* Full: make room by dropping the oldest connection that holds no
		 * claim, so idle connections cannot lock the shell out. */
		for (int i = 0; i < MAX_CLIENTS; i++) {
			if (freezer_client_has_state(clients[i].id))
				continue;
			if (!c || clients[i].id < c->id)
				c = &clients[i];
		}
		if (c)
			client_close(c);
	}
	if (!c) {
		static const char msg[] = "ERR busy too many connections\n";
		ssize_t r = send(fd, msg, sizeof msg - 1, MSG_NOSIGNAL | MSG_DONTWAIT);
		(void)r;
		close(fd);
		n_rejected++;
		return;
	}
	memset(c, 0, sizeof *c);
	c->fd = fd;
	c->id = next_id++;
	struct ucred cred;
	socklen_t len = sizeof cred;
	if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) == 0) {
		c->uid = cred.uid;
		c->pid = cred.pid;
	}
	if (ep_add(fd, EPOLLIN, TAG_CLIENT, c->id) < 0) {
		close(fd);
		return;
	}
	c->used = true;
	n_accepted++;
	log_msg(LOG_DEBUG, "client %llu connected (uid %u pid %d)", (unsigned long long)c->id,
		(unsigned)c->uid, (int)c->pid);
}

/* A socket passed by systemd (.socket unit): fd 3, already bound. */
static int listen_from_systemd(void)
{
	const char *pid = getenv("LISTEN_PID"), *fds = getenv("LISTEN_FDS");
	long v;
	if (!pid || !fds || !parse_long(pid, 1, 2147483647L, &v) || v != (long)getpid())
		return -1;
	if (!parse_long(fds, 1, 1, &v))
		return -1;
	int fd = 3, type = 0, acc = 0;
	socklen_t len = sizeof type;
	struct sockaddr_un sa;
	socklen_t salen = sizeof sa;
	if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &len) < 0 || type != SOCK_STREAM)
		return -1;
	len = sizeof acc;
	if (getsockopt(fd, SOL_SOCKET, SO_ACCEPTCONN, &acc, &len) < 0 || !acc)
		return -1;
	if (getsockname(fd, (struct sockaddr *)&sa, &salen) < 0 || sa.sun_family != AF_UNIX)
		return -1;
	unsetenv("LISTEN_PID");
	unsetenv("LISTEN_FDS");
	unsetenv("LISTEN_FDNAMES");
	return fd;
}

static int listen_bind(void)
{
	struct sockaddr_un sa = { .sun_family = AF_UNIX };
	if (strlen(cfg.socket_path) >= sizeof sa.sun_path) {
		log_msg(LOG_ERR, "socket_path too long");
		return -1;
	}
	strcpy(sa.sun_path, cfg.socket_path);
	int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
	if (fd < 0)
		return -1;
	struct stat st;
	if (lstat(cfg.socket_path, &st) == 0) {
		if (!S_ISSOCK(st.st_mode)) {
			log_msg(LOG_ERR, "%s exists and is not a socket", cfg.socket_path);
			goto fail;
		}
		if (connect(fd, (struct sockaddr *)&sa, sizeof sa) == 0) {
			log_msg(LOG_ERR, "another instance is listening on %s", cfg.socket_path);
			goto fail;
		}
		unlink(cfg.socket_path);
	}
	/* Created 0600, opened up only after the group is set. */
	mode_t old = umask(0177);
	int r = bind(fd, (struct sockaddr *)&sa, sizeof sa);
	umask(old);
	if (r < 0) {
		log_msg(LOG_ERR, "bind %s: %s", cfg.socket_path, strerror(errno));
		goto fail;
	}
	own_socket = true;
	if (cfg.socket_group[0]) {
		long gid;
		if (!parse_long(cfg.socket_group, 0, 2147483647L, &gid)) {
			struct group *g = getgrnam(cfg.socket_group);
			if (!g) {
				log_msg(LOG_ERR, "socket_group %s does not exist", cfg.socket_group);
				goto fail;
			}
			gid = (long)g->gr_gid;
		}
		if (chown(cfg.socket_path, (uid_t)-1, (gid_t)gid) < 0) {
			log_msg(LOG_ERR, "chown %s: %s", cfg.socket_path, strerror(errno));
			goto fail;
		}
	}
	if (chmod(cfg.socket_path, cfg.socket_mode) < 0 || listen(fd, 8) < 0) {
		log_msg(LOG_ERR, "socket setup: %s", strerror(errno));
		goto fail;
	}
	return fd;
fail:
	if (own_socket)
		unlink(cfg.socket_path);
	own_socket = false;
	close(fd);
	return -1;
}

int server_init(void)
{
	listen_fd = listen_from_systemd();
	if (listen_fd >= 0)
		log_msg(LOG_INFO, "control socket inherited from systemd");
	else
		listen_fd = listen_bind();
	if (listen_fd < 0)
		return -1;
	return ep_add(listen_fd, EPOLLIN, TAG_LISTEN, 0);
}

void server_shutdown(void)
{
	for (int i = 0; i < MAX_CLIENTS; i++)
		client_close(&clients[i]);
	if (listen_fd >= 0)
		close(listen_fd);
	listen_fd = -1;
	if (own_socket)
		unlink(cfg.socket_path);
}
