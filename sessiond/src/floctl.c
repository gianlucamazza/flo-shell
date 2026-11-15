/*
 * floctl: command line client for flo-sessiond.
 * SPDX-License-Identifier: MIT
 */
#include "common.h"

#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

static void usage(FILE *f)
{
	fprintf(f,
		"usage: floctl [-s SOCKET] COMMAND [ARG...]\n"
		"       floctl [-s SOCKET] inhibit PATH REASON... [-- PROGRAM [ARG...]]\n"
		"       floctl [-s SOCKET] -i\n"
		"\n"
		"commands: status, version, ping, boost [MS], freeze-policy on|off,\n"
		"          foreground PATH...|-, lock on|off, thaw PATH, thaw-all,\n"
		"          inhibit PATH REASON, uninhibit TOKEN\n"
		"\n"
		"  -s SOCKET  control socket (default $FLO_SESSIOND_SOCKET or\n"
		"             " FLO_DEFAULT_SOCKET ")\n"
		"  -i         interactive: commands from standard input, one per line,\n"
		"             on a single connection (claims last until end of input)\n"
		"\n"
		"\"inhibit\" keeps the app thawed until PROGRAM exits or, without a\n"
		"program, until floctl is interrupted: the inhibit lives with the connection.\n"
		"exit status: 0 OK, 1 the daemon answered ERR, 2 usage or connection error\n");
}

static int send_line(int fd, const char *line)
{
	size_t len = strlen(line);
	if (len + 1 > MAX_LINE) {
		fprintf(stderr, "floctl: command too long\n");
		return -1;
	}
	char buf[MAX_LINE + 1];
	memcpy(buf, line, len);
	buf[len++] = '\n';
	for (size_t off = 0; off < len;) {
		ssize_t n = send(fd, buf + off, len - off, MSG_NOSIGNAL);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			perror("floctl: send");
			return -1;
		}
		off += (size_t)n;
	}
	return 0;
}

/*
 * Copy the reply to stdout up to and including its OK/ERR line.
 * Returns 0 for OK, 1 for ERR, 2 if the connection broke. The text after
 * "OK " is stored in result when given.
 */
static int read_reply(int fd, char *result, size_t rsize)
{
	static char buf[4096];
	static size_t len;
	for (;;) {
		char *nl;
		while ((nl = memchr(buf, '\n', len))) {
			size_t n = (size_t)(nl - buf) + 1;
			fwrite(buf, 1, n, stdout);
			int verdict = -1;
			if (n >= 3 && !memcmp(buf, "OK", 2) && (buf[2] == '\n' || buf[2] == ' '))
				verdict = 0;
			else if (n >= 4 && !memcmp(buf, "ERR", 3) && (buf[3] == '\n' || buf[3] == ' '))
				verdict = 1;
			if (verdict == 0 && result && rsize) {
				size_t m = n > 4 ? n - 4 : 0;
				if (m >= rsize)
					m = rsize - 1;
				memcpy(result, buf + 3, m);
				result[m] = '\0';
			}
			memmove(buf, buf + n, len - n);
			len -= n;
			if (verdict >= 0) {
				fflush(stdout);
				return verdict;
			}
		}
		if (len == sizeof buf) { /* absurdly long line: pass it through */
			fwrite(buf, 1, len, stdout);
			len = 0;
		}
		ssize_t n = recv(fd, buf + len, sizeof buf - len, 0);
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0) {
			fflush(stdout);
			fprintf(stderr, "floctl: connection closed by the daemon\n");
			return 2;
		}
		len += (size_t)n;
	}
}

static void on_signal(int sig)
{
	(void)sig;
}

int main(int argc, char **argv)
{
	const char *path = getenv("FLO_SESSIOND_SOCKET");
	bool interactive = false;
	if (!path || !*path)
		path = FLO_DEFAULT_SOCKET;

	int opt;
	while ((opt = getopt(argc, argv, "+s:ih")) != -1) {
		switch (opt) {
		case 's':
			path = optarg;
			break;
		case 'i':
			interactive = true;
			break;
		case 'h':
			usage(stdout);
			return 0;
		default:
			usage(stderr);
			return 2;
		}
	}
	if (interactive ? optind != argc : optind >= argc) {
		usage(stderr);
		return 2;
	}

	struct sockaddr_un sa = { .sun_family = AF_UNIX };
	if (strlen(path) >= sizeof sa.sun_path) {
		fprintf(stderr, "floctl: socket path too long\n");
		return 2;
	}
	strcpy(sa.sun_path, path);
	int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0 || connect(fd, (struct sockaddr *)&sa, sizeof sa) < 0) {
		fprintf(stderr, "floctl: %s: %s\n", path, strerror(errno));
		return 2;
	}

	if (interactive) {
		char line[MAX_LINE + 2];
		int worst = 0;
		while (fgets(line, sizeof line, stdin)) {
			line[strcspn(line, "\n")] = '\0';
			if (line[0] == '\0')
				continue;
			if (send_line(fd, line) < 0)
				return 2;
			int r = read_reply(fd, NULL, 0);
			if (r == 2)
				return 2;
			if (r > worst)
				worst = r;
		}
		return worst;
	}

	/* Join the words into one line; "--" ends an inhibit command. */
	bool inhibit = strcmp(argv[optind], "inhibit") == 0;
	char line[MAX_LINE + 1];
	size_t len = 0;
	int i = optind;
	for (; i < argc; i++) {
		if (inhibit && strcmp(argv[i], "--") == 0)
			break;
		size_t n = strlen(argv[i]);
		if (len + n + 2 > sizeof line) {
			fprintf(stderr, "floctl: command too long\n");
			return 2;
		}
		if (len)
			line[len++] = ' ';
		memcpy(line + len, argv[i], n);
		len += n;
	}
	line[len] = '\0';
	char **prog = (i < argc - 1) ? &argv[i + 1] : NULL;

	if (send_line(fd, line) < 0)
		return 2;
	int r = read_reply(fd, NULL, 0);
	if (r != 0 || !inhibit)
		return r;

	/* The inhibit is held for as long as this connection stays open. */
	if (prog) {
		pid_t pid = fork();
		if (pid < 0) {
			perror("floctl: fork");
			return 2;
		}
		if (pid == 0) {
			execvp(prog[0], prog);
			fprintf(stderr, "floctl: %s: %s\n", prog[0], strerror(errno));
			_exit(127);
		}
		int status = 0;
		while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
			;
		return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
	}
	struct sigaction act = { 0 };
	act.sa_handler = on_signal;
	sigaction(SIGINT, &act, NULL);
	sigaction(SIGTERM, &act, NULL);
	struct pollfd pfd = { .fd = fd, .events = POLLIN };
	poll(&pfd, 1, -1); /* until a signal, or the daemon goes away */
	return 0;
}
