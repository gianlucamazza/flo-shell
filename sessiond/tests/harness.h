/* Test harness for flo-sessiond: fake sysfs/cgroup trees in a temp dir, a
 * FIFO standing in for the evdev node, the real daemon as a child process.
 * SPDX-License-Identifier: MIT */
#ifndef FLO_HARNESS_H
#define FLO_HARNESS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#define P 512

struct env {
	char dir[P], cpufreq[P], cgroot[P], approot[P], devdir[P], fifo[P];
	char sock[P], state[P], conf[P], notify[P], outside[P];
	pid_t pid;
	int notify_fd;
};

extern int failures;
extern const char *daemon_bin, *floctl_bin;
extern double slow; /* timeout multiplier (FLO_TEST_SLOW) */

#define CHECK(c) \
	do { \
		if (!(c)) { \
			fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); \
			failures++; \
		} \
	} while (0)
#define REQUIRE(c) \
	do { \
		if (!(c)) { \
			fprintf(stderr, "FATAL %s:%d: %s\n", __FILE__, __LINE__, #c); \
			exit(1); \
		} \
	} while (0)

int64_t ms_now(void);
void ms_sleep(int ms);
void env_init(struct env *e);
void path_join(char *out, const char *a, const char *b, const char *c);
void wr(const char *path, const char *text);
bool rd(const char *path, char *buf, size_t size);
bool is(const char *path, const char *want);
/* Poll until the file reads `want`; returns elapsed ms since the call or -1. */
int wait_is(const char *path, const char *want, int timeout_ms);
void policy_path(const struct env *e, int n, char *out);
void app_add(const struct env *e, const char *name);
void app_freeze_path(const struct env *e, const char *name, char *out);
bool app_is(const struct env *e, const char *name, const char *want);
int app_wait(const struct env *e, const char *name, const char *want, int timeout_ms);

/* Start the daemon with the env config plus NULL-terminated "key=value" overrides. */
void daemon_start(struct env *e, ...);
pid_t daemon_spawn(struct env *e, bool want_ready, int listen_fd, const char *const *over);
/* Signal the daemon and reap it; returns the wait status. */
int daemon_stop(struct env *e, int sig);
int reap(pid_t pid, int timeout_ms);

int cl_connect(const struct env *e);
/* Send one command, collect the whole reply. 0 = OK, 1 = ERR, -1 = closed. */
int cl_cmd(int fd, const char *cmd, char *reply, size_t size);
int cl_ok(int fd, const char *cmd);
bool cl_err(int fd, const char *cmd, const char *code);
bool cl_closed(int fd, int timeout_ms);
long status_num(int fd, const char *key);
bool status_str(int fd, const char *key, char *out, size_t size);

int fifo_writer(const struct env *e);
void touch_frame(int fd);
int ino_watch(const char *path);
int ino_count(int fd);
int run(const char *const *argv, const char *input, char *out, size_t size);

#endif
