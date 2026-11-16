/*
 * Integration tests: the real flo-sessiond binary against fake cpufreq and
 * cgroup trees and a FIFO in place of the evdev node. No root, no real
 * sysfs. Usage: test_integration <flo-sessiond> <floctl> <test-name>
 * SPDX-License-Identifier: MIT
 */
#include "harness.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#define A "app-org.foo.A-1111.scope"
#define B "app-org.foo.B-2222.scope"
#define C "app-org.bar.C@3.service"
#define SHELL "app-flo-shell-9.scope"
#define KBD "app-wvkbd\\x2dmobintl-7.scope"
#define PW "pipewire.service"

static struct env e;

static void apps_default(void)
{
	app_add(&e, A);
	app_add(&e, B);
	app_add(&e, C);
	app_add(&e, SHELL);
	app_add(&e, KBD);
	app_add(&e, PW);
}

static bool pol_is(int n, const char *want)
{
	char p[P];
	policy_path(&e, n, p);
	return is(p, want);
}

static int pol_wait(int n, const char *want, int timeout_ms)
{
	char p[P];
	policy_path(&e, n, p);
	return wait_is(p, want, timeout_ms);
}

static bool state_empty(void)
{
	struct stat st;
	return stat(e.state, &st) == 0 && st.st_size == 0;
}

/* ------------------------------------------------------------- boost */

static void t_boost_first_touch(void)
{
	char p[P];
	policy_path(&e, 3, p);
	wr(p, "1200000\n"); /* a floor already above the boost must be left alone */
	REQUIRE(mkfifo(e.fifo, 0600) == 0);
	daemon_start(&e, NULL);
	int w = fifo_writer(&e), c = cl_connect(&e);
	CHECK(status_num(c, "boost.knobs") == 4);

	int64_t t0 = ms_now();
	touch_frame(w);
	CHECK(pol_wait(0, "1026000", 2000) >= 0);
	CHECK(pol_wait(1, "1026000", 2000) >= 0);
	CHECK(pol_wait(2, "1026000", 2000) >= 0);
	CHECK(pol_is(3, "1200000"));
	CHECK(status_num(c, "boost.active") == 1);
	CHECK(!state_empty());

	CHECK(pol_wait(0, "384000", 3000) >= 0);
	CHECK(ms_now() - t0 >= 200); /* never released before the hold time */
	CHECK(pol_wait(1, "384000", 1000) >= 0);
	CHECK(pol_wait(2, "384000", 1000) >= 0);
	CHECK(pol_is(3, "1200000"));
	CHECK(status_num(c, "boost.active") == 0);
	CHECK(status_num(c, "boost.count") == 1);
	CHECK(status_num(c, "boost.writes") == 6); /* 3 raised + 3 restored */
	CHECK(state_empty());
	path_join(p, e.cpufreq, "boost", NULL);
	CHECK(is(p, "decoy"));
	close(w);
	close(c);
}

/* 100 Hz of events for 0.6 s must cost one input wakeup and one sysfs write
 * per policy, not sixty. */
static void t_boost_streaming(void)
{
	char p[P];
	REQUIRE(mkfifo(e.fifo, 0600) == 0);
	daemon_start(&e, "boost_hold_ms=300", NULL);
	int w = fifo_writer(&e), c = cl_connect(&e);
	policy_path(&e, 0, p);
	int ino = ino_watch(p);

	int64_t t0 = ms_now();
	for (int i = 0; i < 60; i++) {
		touch_frame(w);
		ms_sleep(10);
	}
	int64_t stream_ms = ms_now() - t0;
	CHECK(pol_is(0, "1026000"));
	CHECK(ino_count(ino) == 1);
	CHECK(status_num(c, "boost.input_wakeups") == 1);
	CHECK(status_num(c, "boost.count") == 1);
	long timers = status_num(c, "boost.timer_wakeups");
	fprintf(stderr, "stream %lld ms: 60 frames (240 events), 1 input wakeup, %ld timer wakeups\n",
		(long long)stream_ms, timers);
	CHECK(timers >= 1 && timers <= stream_ms / 300 + 1);

	CHECK(pol_wait(0, "384000", 3000) >= 0);
	CHECK(ms_now() - t0 >= stream_ms + 290 - 10); /* held ~300 ms past the last frame */
	ms_sleep(50);
	CHECK(ino_count(ino) == 1); /* exactly one more: the restore */
	CHECK(status_num(c, "boost.writes") == 8);
	CHECK(status_num(c, "boost.input_wakeups") == 1);

	/* A new touch boosts again. */
	touch_frame(w);
	CHECK(pol_wait(0, "1026000", 2000) >= 0);
	CHECK(pol_wait(0, "384000", 3000) >= 0);
	CHECK(status_num(c, "boost.count") == 2);
	close(ino);
	close(w);
	close(c);
}

/* With event timestamps the hold counts from the last event, not from the
 * moment the daemon noticed it. */
static void t_boost_timestamps(void)
{
	REQUIRE(mkfifo(e.fifo, 0600) == 0);
	daemon_start(&e, "boost_hold_ms=1000", "input_timestamps=trust", NULL);
	int w = fifo_writer(&e), c = cl_connect(&e);
	char v[64];
	touch_frame(w);
	CHECK(pol_wait(0, "1026000", 2000) >= 0);
	CHECK(status_str(c, "input.timestamps", v, sizeof v) && !strcmp(v, "event"));
	ms_sleep(200);
	int64_t t1 = ms_now();
	touch_frame(w); /* swallowed while boosted, seen when the timer fires */
	CHECK(pol_wait(0, "384000", 5000) >= 0);
	int64_t dt = ms_now() - t1;
	fprintf(stderr, "released %lld ms after the last event (hold 1000)\n", (long long)dt);
	CHECK(dt >= 1000);
	/* Arrival-time accounting would give ~1800 ms here. */
	CHECK((double)dt < 1500 * slow);
	close(w);
	close(c);
}

static void t_boost_sigterm(void)
{
	REQUIRE(mkfifo(e.fifo, 0600) == 0);
	daemon_start(&e, "boost_hold_ms=8000", NULL);
	int w = fifo_writer(&e);
	touch_frame(w);
	for (int i = 0; i < 4; i++)
		CHECK(pol_wait(i, "1026000", 2000) >= 0);
	int st = daemon_stop(&e, SIGTERM);
	CHECK(WIFEXITED(st) && WEXITSTATUS(st) == 0);
	for (int i = 0; i < 4; i++)
		CHECK(pol_is(i, "384000"));
	CHECK(state_empty());
	CHECK(access(e.sock, F_OK) != 0); /* socket removed */
	close(w);
}

/* A fatal signal still puts the floors back and thaws frozen apps. */
static void t_crash_restore(void)
{
	apps_default();
	REQUIRE(mkfifo(e.fifo, 0600) == 0);
	daemon_start(&e, "boost_hold_ms=8000", "freezer_grace_ms=50", NULL);
	int w = fifo_writer(&e), c = cl_connect(&e);
	CHECK(cl_ok(c, "freeze-policy on"));
	CHECK(cl_ok(c, "foreground " A));
	CHECK(app_wait(&e, B, "1", 3000) >= 0);
	touch_frame(w);
	for (int i = 0; i < 4; i++)
		CHECK(pol_wait(i, "1026000", 2000) >= 0);
	int st = daemon_stop(&e, SIGSEGV);
	CHECK(WIFSIGNALED(st) && WTERMSIG(st) == SIGSEGV);
	for (int i = 0; i < 4; i++)
		CHECK(pol_is(i, "384000"));
	CHECK(app_is(&e, B, "0"));
	CHECK(app_is(&e, C, "0"));
	close(w);
	close(c);
}

/* SIGKILL cannot be caught: the next start undoes it from the state file and
 * thaws whatever was left frozen. */
static void t_kill_recovery(void)
{
	char p[P], line[2 * P];
	apps_default();
	REQUIRE(mkfifo(e.fifo, 0600) == 0);
	daemon_start(&e, "boost_hold_ms=8000", "freezer_grace_ms=50", NULL);
	int w = fifo_writer(&e), c = cl_connect(&e);
	CHECK(cl_ok(c, "freeze-policy on"));
	CHECK(cl_ok(c, "foreground " A));
	CHECK(app_wait(&e, B, "1", 3000) >= 0);
	touch_frame(w);
	for (int i = 0; i < 4; i++)
		CHECK(pol_wait(i, "1026000", 2000) >= 0);
	int st = daemon_stop(&e, SIGKILL);
	CHECK(WIFSIGNALED(st) && WTERMSIG(st) == SIGKILL);
	close(w);
	close(c);
	for (int i = 0; i < 4; i++)
		CHECK(pol_is(i, "1026000")); /* left boosted */
	CHECK(app_is(&e, B, "1"));   /* left frozen */
	CHECK(!state_empty());

	/* A forged entry for a path the daemon does not manage must be ignored. */
	path_join(p, e.outside, "victim", NULL);
	wr(p, "untouched\n");
	snprintf(line, sizeof line, "%s 384000\n", p);
	int fd = open(e.state, O_WRONLY | O_APPEND);
	REQUIRE(fd >= 0 && write(fd, line, strlen(line)) > 0);
	close(fd);

	daemon_start(&e, NULL);
	for (int i = 0; i < 4; i++)
		CHECK(pol_is(i, "384000"));
	CHECK(app_is(&e, B, "0"));
	CHECK(state_empty());
	CHECK(is(p, "untouched"));
}

static bool input_present(int c)
{
	char v[P];
	return status_str(c, "input.device", v, sizeof v) && strcmp(v, "-") != 0;
}

static bool wait_input(int c, bool present)
{
	int64_t t0 = ms_now();
	while (input_present(c) != present) {
		if (ms_now() - t0 > (int64_t)(3000 * slow))
			return false;
		ms_sleep(5);
	}
	return true;
}

static void t_device_hotplug(void)
{
	daemon_start(&e, NULL); /* no device node at all yet */
	int c = cl_connect(&e);
	CHECK(!input_present(c));
	long w0 = status_num(c, "loop.wakeups");

	REQUIRE(mkfifo(e.fifo, 0600) == 0); /* the device appears */
	CHECK(wait_input(c, true));
	(void)w0;
	int w = fifo_writer(&e);
	touch_frame(w);
	CHECK(pol_wait(0, "1026000", 2000) >= 0);

	/* It disappears in the middle of a boost. */
	REQUIRE(unlink(e.fifo) == 0); /* before the close: no window to reopen it */
	close(w);
	CHECK(pol_wait(0, "384000", 3000) >= 0);
	CHECK(wait_input(c, false));
	CHECK(status_num(c, "boost.active") == 0);

	/* And comes back. */
	REQUIRE(mkfifo(e.fifo, 0600) == 0);
	CHECK(wait_input(c, true));
	w = fifo_writer(&e);
	touch_frame(w);
	CHECK(pol_wait(0, "1026000", 2000) >= 0);
	CHECK(pol_wait(0, "384000", 3000) >= 0);
	CHECK(status_num(c, "boost.count") == 2);

	/* Disappearing while idle is noticed too. */
	REQUIRE(unlink(e.fifo) == 0); /* before the close: no window to reopen it */
	close(w);
	CHECK(wait_input(c, false));
	CHECK(cl_ok(c, "ping"));
	close(c);
}

/* A policy whose floor cannot be written back (CPU went offline: EBUSY on a
 * real kernel, EACCES here) is retried; a policy directory that vanishes and
 * returns is picked up again. */
static void t_cpu_offline(void)
{
	char p2[P], gone[P], back[P];
	if (geteuid() == 0)
		exit(77); /* root ignores file modes: cannot simulate the failure */
	REQUIRE(mkfifo(e.fifo, 0600) == 0);
	daemon_start(&e, NULL);
	int w = fifo_writer(&e), c = cl_connect(&e);
	policy_path(&e, 2, p2);

	touch_frame(w);
	CHECK(pol_wait(2, "1026000", 2000) >= 0);
	REQUIRE(chmod(p2, 0444) == 0);
	CHECK(pol_wait(0, "384000", 3000) >= 0);
	CHECK(pol_wait(3, "384000", 1000) >= 0);
	CHECK(pol_is(2, "1026000"));
	CHECK(status_num(c, "boost.knobs_pending") == 1);
	CHECK(status_num(c, "boost.restore_failures") == 1);
	CHECK(!state_empty()); /* still recorded for crash recovery */
	REQUIRE(chmod(p2, 0644) == 0);
	CHECK(pol_wait(2, "384000", 4000) >= 0); /* first retry after 1 s */
	CHECK(status_num(c, "boost.knobs_pending") == 0);
	CHECK(state_empty());

	/* Policy directory removed while boosted. */
	path_join(gone, e.cpufreq, "policy1", NULL);
	path_join(back, e.dir, "policy1.offline", NULL);
	touch_frame(w);
	CHECK(pol_wait(1, "1026000", 2000) >= 0);
	REQUIRE(rename(gone, back) == 0);
	CHECK(pol_wait(0, "384000", 3000) >= 0);
	CHECK(status_num(c, "boost.knobs") == 3);
	CHECK(status_num(c, "boost.knobs_pending") == 0);
	path_join(gone, back, "scaling_min_freq", NULL);
	wr(gone, "384000\n");
	path_join(gone, e.cpufreq, "policy1", NULL);
	REQUIRE(rename(back, gone) == 0);
	/* Rediscovered at the end of the next boost, used by the one after. */
	touch_frame(w);
	CHECK(pol_wait(0, "1026000", 2000) >= 0);
	CHECK(pol_wait(0, "384000", 3000) >= 0);
	CHECK(status_num(c, "boost.knobs") == 4);
	touch_frame(w);
	CHECK(pol_wait(1, "1026000", 2000) >= 0);
	CHECK(pol_wait(1, "384000", 3000) >= 0);
	close(w);
	close(c);
}

static void t_boost_command(void)
{
	char reply[256];
	daemon_start(&e, "boost_request_max_ms=300", NULL);
	int c = cl_connect(&e);
	int64_t t0 = ms_now();
	CHECK(cl_cmd(c, "boost 250", reply, sizeof reply) == 0 && !strcmp(reply, "OK 250\n"));
	CHECK(pol_is(0, "1026000")); /* applied before the reply */
	CHECK(pol_wait(0, "384000", 3000) >= 0);
	CHECK(ms_now() - t0 >= 250);
	CHECK(cl_cmd(c, "boost 60000", reply, sizeof reply) == 0 && !strcmp(reply, "OK 300\n"));
	CHECK(pol_wait(0, "384000", 3000) >= 0);
	CHECK(cl_cmd(c, "boost", reply, sizeof reply) == 0 && !strcmp(reply, "OK 200\n"));
	CHECK(pol_wait(0, "384000", 3000) >= 0);
	CHECK(cl_err(c, "boost abc", "syntax"));
	CHECK(cl_err(c, "boost 0", "syntax"));
	CHECK(cl_err(c, "boost -5", "syntax"));
	CHECK(cl_err(c, "boost 99999999999", "syntax"));
	CHECK(cl_err(c, "boost 1 2", "syntax"));
	close(c);
	daemon_stop(&e, SIGTERM);

	daemon_start(&e, "boost_enabled=no", NULL);
	c = cl_connect(&e);
	CHECK(cl_err(c, "boost 100", "disabled"));
	CHECK(pol_is(0, "384000"));
	close(c);
}

static void t_boost_uclamp(void)
{
	char p[P];
	path_join(p, e.cgroot, "cpu.uclamp.min", NULL);
	REQUIRE(mkfifo(e.fifo, 0600) == 0);
	daemon_start(&e, "boost_mode=uclamp", "uclamp_min=68.50", NULL);
	int w = fifo_writer(&e), c = cl_connect(&e);
	CHECK(status_num(c, "boost.knobs") == 1);
	touch_frame(w);
	CHECK(wait_is(p, "68.50", 2000) >= 0);
	CHECK(pol_is(0, "384000")); /* frequency floors untouched in this mode */
	CHECK(wait_is(p, "0.00", 3000) >= 0);
	close(w);
	close(c);
	daemon_stop(&e, SIGTERM);

	daemon_start(&e, "boost_mode=both", NULL);
	w = fifo_writer(&e);
	touch_frame(w);
	CHECK(wait_is(p, "68", 2000) >= 0);
	CHECK(pol_wait(0, "1026000", 2000) >= 0);
	CHECK(wait_is(p, "0.00", 3000) >= 0);
	CHECK(pol_wait(0, "384000", 2000) >= 0);
	close(w);
}

/* Nothing to do means nothing done: no wakeups at all between two queries. */
static void t_idle(void)
{
	REQUIRE(mkfifo(e.fifo, 0600) == 0);
	apps_default();
	daemon_start(&e, NULL);
	int c = cl_connect(&e);
	CHECK(cl_ok(c, "freeze-policy on"));
	CHECK(cl_ok(c, "foreground " A " " B " " C)); /* nothing left to freeze */
	long w1 = status_num(c, "loop.wakeups");
	ms_sleep(700);
	long w2 = status_num(c, "loop.wakeups");
	CHECK(w1 > 0 && w2 == w1 + 1); /* only the second query itself */
	close(c);
}

/* ----------------------------------------------------------- freezer */

static void t_freezer_grace(void)
{
	apps_default();
	daemon_start(&e, NULL);
	int c = cl_connect(&e);
	CHECK(cl_err(c, "foreground " A, "not-owner"));
	/* Grace periods start when the policy is switched on (background apps
	 * are already background then), so measure from before that command;
	 * under emulation the next round trip can take a sizeable part of the
	 * 400 ms grace. */
	int64_t t0 = ms_now();
	CHECK(cl_ok(c, "freeze-policy on"));
	CHECK(cl_ok(c, "foreground " A));
	CHECK(app_is(&e, B, "0")); /* grace period: not frozen yet */
	CHECK(app_wait(&e, B, "1", 4000) >= 0);
	CHECK(ms_now() - t0 >= 400);
	CHECK(app_wait(&e, C, "1", 2000) >= 0);
	CHECK(app_is(&e, A, "0"));
	/* Deny list (shell, keyboard) and non-app units (pipewire) stay thawed. */
	CHECK(app_is(&e, SHELL, "0"));
	CHECK(app_is(&e, KBD, "0"));
	CHECK(app_is(&e, PW, "0"));

	/* Foreground change: the reply arrives after the thaw. */
	t0 = ms_now();
	CHECK(cl_ok(c, "foreground " B));
	CHECK(app_is(&e, B, "0"));
	CHECK(app_is(&e, C, "1"));
	CHECK(app_wait(&e, A, "1", 4000) >= 0);
	CHECK(ms_now() - t0 >= 400);

	CHECK(cl_ok(c, "foreground " A " " C)); /* split screen */
	CHECK(app_is(&e, A, "0") && app_is(&e, C, "0"));
	CHECK(app_wait(&e, B, "1", 4000) >= 0);

	CHECK(cl_ok(c, "foreground -")); /* home screen: nothing in front */
	CHECK(app_wait(&e, A, "1", 4000) >= 0);
	CHECK(app_wait(&e, C, "1", 4000) >= 0);
	CHECK(app_is(&e, SHELL, "0") && app_is(&e, KBD, "0") && app_is(&e, PW, "0"));

	/* A foreground name whose cgroup does not exist yet is accepted. */
	CHECK(cl_ok(c, "foreground app-org.new.D-1.scope"));
	app_add(&e, "app-org.new.D-1.scope");
	ms_sleep(700);
	CHECK(app_is(&e, "app-org.new.D-1.scope", "0"));
	close(c);
}

static void t_freezer_allowlist(void)
{
	apps_default();
	daemon_start(&e, "freezer_allow=org.foo.*", NULL);
	int c = cl_connect(&e);
	CHECK(cl_ok(c, "freeze-policy on"));
	CHECK(cl_ok(c, "foreground -"));
	CHECK(app_wait(&e, A, "1", 4000) >= 0);
	CHECK(app_wait(&e, B, "1", 4000) >= 0);
	ms_sleep(300);
	CHECK(app_is(&e, C, "0")); /* org.bar.C is not on the allow list */
	CHECK(app_is(&e, SHELL, "0"));
	close(c);
	daemon_stop(&e, SIGTERM);

	/* Deny wins over allow; a custom deny entry by desktop id. */
	daemon_start(&e, "freezer_allow=org.*", "freezer_deny=org.foo.B", NULL);
	c = cl_connect(&e);
	CHECK(cl_ok(c, "freeze-policy on"));
	CHECK(cl_ok(c, "foreground -"));
	CHECK(app_wait(&e, A, "1", 4000) >= 0);
	CHECK(app_wait(&e, C, "1", 4000) >= 0);
	ms_sleep(300);
	CHECK(app_is(&e, B, "0"));
	close(c);
	daemon_stop(&e, SIGTERM);

	daemon_start(&e, "freezer_enabled=no", NULL);
	c = cl_connect(&e);
	CHECK(cl_err(c, "freeze-policy on", "disabled"));
	CHECK(cl_err(c, "inhibit " A " x", "disabled"));
	close(c);
}

static void t_freezer_inhibit(void)
{
	char reply[256], cmd[128];
	apps_default();
	daemon_start(&e, NULL);
	int c1 = cl_connect(&e), c2 = cl_connect(&e);
	CHECK(cl_ok(c1, "freeze-policy on"));
	CHECK(cl_ok(c1, "foreground " A));
	REQUIRE(cl_cmd(c2, "inhibit " B " playing music", reply, sizeof reply) == 0);
	unsigned tok_b = (unsigned)atoi(reply + 3);
	CHECK(tok_b > 0);
	CHECK(app_wait(&e, C, "1", 4000) >= 0);
	CHECK(app_is(&e, B, "0")); /* inhibited: grace expired for C, B stays */
	char v[128];
	CHECK(status_str(c1, "freezer.policy", v, sizeof v) && !strcmp(v, "on"));

	/* Inhibiting an already frozen app thaws it before the reply. */
	REQUIRE(cl_cmd(c2, "inhibit " C " download", reply, sizeof reply) == 0);
	unsigned tok_c = (unsigned)atoi(reply + 3);
	CHECK(tok_c > 0 && tok_c != tok_b);
	CHECK(app_is(&e, C, "0"));

	CHECK(cl_err(c2, "uninhibit 99999", "no-such-token"));
	snprintf(cmd, sizeof cmd, "uninhibit %u", tok_c);
	CHECK(cl_err(c1, cmd, "no-such-token")); /* token of another connection */
	CHECK(cl_err(c2, "uninhibit x", "syntax"));
	CHECK(cl_err(c2, "inhibit " B, "syntax")); /* a reason is mandatory */

	int64_t t0 = ms_now();
	CHECK(cl_ok(c2, cmd));
	CHECK(app_wait(&e, C, "1", 4000) >= 0);
	CHECK(ms_now() - t0 >= 400); /* a fresh grace period after the release */
	CHECK(app_is(&e, B, "0"));

	/* Per-connection limit. */
	for (int i = 0; i < 7; i++)
		CHECK(cl_ok(c2, "inhibit " A " filler"));
	CHECK(cl_err(c2, "inhibit " A " one too many", "limit"));

	/* Disconnect releases everything the client held. */
	t0 = ms_now();
	close(c2);
	CHECK(app_wait(&e, B, "1", 4000) >= 0);
	CHECK(ms_now() - t0 >= 400);
	CHECK(app_is(&e, A, "0"));
	close(c1);
}

/* The shell owns the policy: if it goes away, everything thaws. */
static void t_freezer_fail_open(void)
{
	char v[64];
	apps_default();
	daemon_start(&e, NULL);
	int c1 = cl_connect(&e);
	CHECK(cl_ok(c1, "freeze-policy on"));
	CHECK(cl_ok(c1, "foreground " A));
	CHECK(app_wait(&e, B, "1", 4000) >= 0);
	CHECK(app_wait(&e, C, "1", 4000) >= 0);
	shutdown(c1, SHUT_RDWR);
	close(c1);
	CHECK(app_wait(&e, B, "0", 2000) >= 0);
	CHECK(app_wait(&e, C, "0", 2000) >= 0);
	int c2 = cl_connect(&e);
	CHECK(status_str(c2, "freezer.policy", v, sizeof v) && !strcmp(v, "off"));
	ms_sleep(600);
	CHECK(app_is(&e, B, "0") && app_is(&e, C, "0")); /* and stays thawed */
	CHECK(cl_ok(c2, "freeze-policy on")); /* a restarted shell takes over */
	CHECK(cl_ok(c2, "foreground " A));
	CHECK(app_wait(&e, B, "1", 4000) >= 0);
	close(c2);
	CHECK(app_wait(&e, B, "0", 2000) >= 0);
}

static void t_freezer_controls(void)
{
	char reply[256];
	apps_default();
	daemon_start(&e, NULL);
	int c1 = cl_connect(&e), c2 = cl_connect(&e);
	CHECK(cl_ok(c1, "freeze-policy on"));
	CHECK(cl_ok(c1, "foreground " A));
	CHECK(app_wait(&e, B, "1", 4000) >= 0);
	CHECK(app_wait(&e, C, "1", 4000) >= 0);

	/* Only the owner drives the policy. */
	CHECK(cl_err(c2, "freeze-policy on", "busy"));
	CHECK(cl_err(c2, "foreground " B, "not-owner"));
	CHECK(cl_err(c2, "lock on", "not-owner"));
	CHECK(app_is(&e, B, "1"));

	/* Screen lock: thaw now, freeze nothing while locked. */
	CHECK(cl_ok(c1, "lock on"));
	CHECK(app_is(&e, B, "0") && app_is(&e, C, "0"));
	ms_sleep(600);
	CHECK(app_is(&e, B, "0") && app_is(&e, C, "0"));
	int64_t t0 = ms_now();
	CHECK(cl_ok(c1, "lock off"));
	CHECK(app_wait(&e, B, "1", 4000) >= 0);
	CHECK(ms_now() - t0 >= 400);
	CHECK(app_wait(&e, C, "1", 4000) >= 0);

	/* thaw-all is open to any client and restarts the grace periods. */
	t0 = ms_now();
	CHECK(cl_cmd(c2, "thaw-all", reply, sizeof reply) == 0 && !strcmp(reply, "OK 2\n"));
	CHECK(app_is(&e, B, "0") && app_is(&e, C, "0"));
	CHECK(app_wait(&e, B, "1", 4000) >= 0);
	CHECK(ms_now() - t0 >= 400);
	CHECK(app_wait(&e, C, "1", 4000) >= 0);

	/* thaw of one app. */
	t0 = ms_now();
	CHECK(cl_ok(c2, "thaw " B));
	CHECK(app_is(&e, B, "0") && app_is(&e, C, "1"));
	CHECK(app_wait(&e, B, "1", 4000) >= 0);
	CHECK(ms_now() - t0 >= 400);
	CHECK(cl_err(c2, "thaw " PW, "invalid-path")); /* not an app unit */
	CHECK(cl_err(c2, "thaw app-nothere-1.scope", "not-found"));

	/* Anyone may switch the policy off (fail-open direction). */
	CHECK(cl_ok(c2, "freeze-policy off"));
	CHECK(app_is(&e, B, "0") && app_is(&e, C, "0"));
	CHECK(cl_err(c1, "foreground " A, "not-owner"));
	ms_sleep(600);
	CHECK(app_is(&e, B, "0") && app_is(&e, C, "0"));
	close(c1);
	close(c2);
}

static void t_freezer_exit(void)
{
	apps_default();
	daemon_start(&e, "freezer_grace_ms=50", NULL);
	int c = cl_connect(&e);
	CHECK(cl_ok(c, "freeze-policy on"));
	CHECK(cl_ok(c, "foreground " A));
	CHECK(app_wait(&e, B, "1", 3000) >= 0);
	CHECK(app_wait(&e, C, "1", 3000) >= 0);
	int st = daemon_stop(&e, SIGTERM);
	CHECK(WIFEXITED(st) && WEXITSTATUS(st) == 0);
	CHECK(app_is(&e, B, "0") && app_is(&e, C, "0"));
	close(c);
}

/* App cgroups created and removed while the policy is on. */
static void t_freezer_new_app(void)
{
	char p[P];
	apps_default();
	daemon_start(&e, NULL);
	int c = cl_connect(&e);
	CHECK(cl_ok(c, "freeze-policy on"));
	CHECK(cl_ok(c, "foreground " A));
	CHECK(app_wait(&e, B, "1", 4000) >= 0);
	int64_t t0 = ms_now();
	app_add(&e, "app-org.late.D-5.scope");
	CHECK(app_wait(&e, "app-org.late.D-5.scope", "1", 4000) >= 0); /* via inotify */
	CHECK(ms_now() - t0 >= 400);

	app_freeze_path(&e, C, p);
	REQUIRE(unlink(p) == 0);
	path_join(p, e.approot, C, NULL);
	REQUIRE(rmdir(p) == 0);
	ms_sleep(100);
	char big[8192];
	REQUIRE(cl_cmd(c, "status", big, sizeof big) == 0);
	CHECK(!strstr(big, "app=" C));
	CHECK(strstr(big, "app=" B " frozen"));
	CHECK(strstr(big, "app=" A " running"));
	CHECK(strstr(big, "foreground=" A));

	/* The whole root disappears (last app exited, systemd removed app.slice). */
	const char *names[] = { A, B, SHELL, KBD, PW, "app-org.late.D-5.scope" };
	for (size_t i = 0; i < sizeof names / sizeof names[0]; i++) {
		app_freeze_path(&e, names[i], p);
		REQUIRE(unlink(p) == 0);
		path_join(p, e.approot, names[i], NULL);
		REQUIRE(rmdir(p) == 0);
	}
	REQUIRE(rmdir(e.approot) == 0);
	CHECK(cl_ok(c, "foreground -"));
	REQUIRE(mkdir(e.approot, 0755) == 0);
	app_add(&e, B);
	CHECK(cl_ok(c, "foreground " A));
	CHECK(app_wait(&e, B, "1", 4000) >= 0);
	close(c);
}

/* ---------------------------------------------------------- protocol */

/* Read until the peer closes; false if it does not within 2 s. */
static bool read_all(int fd, char *buf, size_t size)
{
	size_t len = 0;
	int64_t t0 = ms_now();
	buf[0] = '\0';
	for (;;) {
		ssize_t n = recv(fd, buf + len, size - 1 - len, MSG_DONTWAIT);
		if (n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR))
			return true;
		if (n > 0) {
			len += (size_t)n;
			buf[len] = '\0';
		}
		if (ms_now() - t0 > (int64_t)(2000 * slow) || len >= size - 1)
			return false;
		ms_sleep(2);
	}
}

static int raw_send(int fd, const void *buf, size_t len)
{
	return send(fd, buf, len, MSG_NOSIGNAL) == (ssize_t)len;
}

static void t_proto_negative(void)
{
	char reply[2048], cmd[1024], target[P], link_[P], victim[P];
	apps_default();

	/* A symlinked "cgroup" pointing outside the root, and a real app whose
	 * cgroup.freeze is itself a symlink to an outside file. */
	path_join(victim, e.outside, "cgroup.freeze", NULL);
	wr(victim, "1\n");
	path_join(link_, e.approot, "app-evil-1.scope", NULL);
	REQUIRE(symlink(e.outside, link_) == 0);
	path_join(target, e.outside, "target", NULL);
	wr(target, "0\n");
	path_join(link_, e.approot, "app-link-1.scope", NULL);
	REQUIRE(mkdir(link_, 0755) == 0);
	path_join(link_, e.approot, "app-link-1.scope", "cgroup.freeze");
	REQUIRE(symlink(target, link_) == 0);

	daemon_start(&e, "freezer_grace_ms=50", NULL);
	int c = cl_connect(&e);
	CHECK(cl_ok(c, "freeze-policy on"));

	static const char *const bad[] = {
		"../x", "/abs", "/", "a/../b", "a//b", ".", "..", "a/./b", "a/..", "../../etc",
		"a/b/c/d/e", "a/", "/sys/fs/cgroup/user.slice", "~/../x", "a/b/..",
	};
	for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
		snprintf(cmd, sizeof cmd, "foreground %s", bad[i]);
		CHECK(cl_err(c, cmd, "invalid-path"));
		snprintf(cmd, sizeof cmd, "inhibit %s reason", bad[i]);
		CHECK(cl_err(c, cmd, "invalid-path"));
		snprintf(cmd, sizeof cmd, "thaw %s", bad[i]);
		CHECK(cl_cmd(c, cmd, reply, sizeof reply) == 1);
	}
	/* A component longer than NAME_MAX. */
	memset(cmd, 0, sizeof cmd);
	strcpy(cmd, "foreground ");
	memset(cmd + strlen(cmd), 'a', 300);
	CHECK(cl_err(c, cmd, "invalid-path"));

	/* Symlinks are never followed out of the root. */
	CHECK(cl_ok(c, "foreground " A));
	CHECK(app_wait(&e, B, "1", 3000) >= 0);
	ms_sleep(200);
	CHECK(is(target, "0"));                         /* not frozen through the link */
	CHECK(cl_cmd(c, "thaw app-evil-1.scope", reply, sizeof reply) == 1);
	CHECK(cl_cmd(c, "thaw app-evil-1.scope/x", reply, sizeof reply) == 1);
	CHECK(cl_cmd(c, "thaw-all", reply, sizeof reply) == 0);
	CHECK(is(victim, "1"));                         /* not thawed through the link */
	CHECK(cl_ok(c, "foreground app-evil-1.scope")); /* a name, never dereferenced */
	CHECK(cl_ok(c, "inhibit app-evil-1.scope x"));
	CHECK(is(victim, "1"));

	/* Malformed commands. */
	CHECK(cl_err(c, "", "syntax"));
	CHECK(cl_err(c, "   ", "syntax"));
	CHECK(cl_err(c, "frobnicate", "unknown-command"));
	CHECK(cl_err(c, "STATUS", "unknown-command"));
	CHECK(cl_err(c, "status now", "syntax"));
	CHECK(cl_err(c, "foreground", "syntax"));
	CHECK(cl_err(c, "foreground a b c d e", "syntax"));
	CHECK(cl_err(c, "foreground a b c d e f g h", "syntax"));
	CHECK(cl_err(c, "freeze-policy maybe", "syntax"));
	CHECK(cl_err(c, "freeze-policy", "syntax"));
	CHECK(cl_err(c, "lock", "syntax"));
	CHECK(cl_err(c, "thaw", "syntax"));
	CHECK(cl_err(c, "thaw-all now", "syntax"));
	CHECK(cl_err(c, "uninhibit", "syntax"));
	CHECK(cl_err(c, "uninhibit -1", "syntax"));
	CHECK(cl_err(c, "uninhibit 0", "syntax"));
	CHECK(cl_err(c, "inhibit", "syntax"));

	/* Split and pipelined writes are fine. */
	REQUIRE(raw_send(c, "pi", 2));
	ms_sleep(30);
	REQUIRE(raw_send(c, "ng\n", 3));
	CHECK(recv(c, reply, sizeof reply, 0) == 3 && !memcmp(reply, "OK\n", 3));
	REQUIRE(raw_send(c, "ping\nping\nfrob\n", 15));
	size_t got = 0;
	while (got < 26) {
		ssize_t n = recv(c, reply + got, sizeof reply - got, 0);
		REQUIRE(n > 0);
		got += (size_t)n;
	}
	CHECK(got == 26 && !memcmp(reply, "OK\nOK\nERR unknown-command\n", 26));

	/* The longest legal line is accepted... */
	memset(cmd, ' ', 512);
	memcpy(cmd, "ping", 4);
	cmd[511] = '\n';
	REQUIRE(raw_send(c, cmd, 512));
	CHECK(recv(c, reply, sizeof reply, 0) == 3 && !memcmp(reply, "OK\n", 3));
	CHECK(cl_ok(c, "ping")); /* this connection is still the owner */

	/* ...one byte more is refused and the connection dropped. */
	int d = cl_connect(&e);
	cmd[511] = ' ';
	cmd[512] = '\n';
	REQUIRE(raw_send(d, cmd, 513));
	CHECK(read_all(d, reply, sizeof reply) && strstr(reply, "ERR line-too-long"));
	close(d);

	/* An endless line. */
	d = cl_connect(&e);
	memset(cmd, 'A', sizeof cmd);
	for (int i = 0; i < 64; i++)
		if (!raw_send(d, cmd, sizeof cmd))
			break;
	CHECK(cl_closed(d, 2000));
	close(d);

	/* NUL and other control bytes. */
	d = cl_connect(&e);
	REQUIRE(raw_send(d, "ping\0ping\n", 10));
	CHECK(cl_closed(d, 2000));
	close(d);
	d = cl_connect(&e);
	REQUIRE(raw_send(d, "foreground a\tb\n", 15));
	CHECK(cl_closed(d, 2000));
	close(d);
	d = cl_connect(&e);
	REQUIRE(raw_send(d, "ping\r\n", 6));
	CHECK(cl_closed(d, 2000));
	close(d);
	d = cl_connect(&e);
	REQUIRE(raw_send(d, "foreground \xc3\xa0pp\n", 16));
	CHECK(cl_closed(d, 2000));
	close(d);

	/* Pseudo-random garbage on many connections. */
	unsigned seed = 12345;
	for (int round = 0; round < 50; round++) {
		d = cl_connect(&e);
		unsigned char junk[700];
		size_t len = 1 + (size_t)(rand_r(&seed) % (int)sizeof junk);
		for (size_t i = 0; i < len; i++) {
			int r = rand_r(&seed);
			/* mostly printable so that some lines reach the parser */
			junk[i] = (unsigned char)(r % 11 == 0 ? '\n' : r % 17 == 0 ? ' ' :
						  r % 23 == 0 ? r & 0xff : 0x21 + r % 94);
		}
		raw_send(d, junk, len);
		close(d);
	}

	/* None of it hurt: the owner connection and its policy are intact. */
	CHECK(kill(e.pid, 0) == 0);
	CHECK(cl_ok(c, "ping"));
	char v[64];
	CHECK(status_str(c, "freezer.policy", v, sizeof v) && !strcmp(v, "on"));
	CHECK(is(victim, "1") && is(target, "0"));
	close(c);
	int st = daemon_stop(&e, SIGTERM);
	CHECK(WIFEXITED(st) && WEXITSTATUS(st) == 0);
	CHECK(is(victim, "1") && is(target, "0"));
}

static void t_many_clients(void)
{
	char reply[256];
	apps_default();
	daemon_start(&e, NULL);
	int owner = cl_connect(&e);
	CHECK(cl_ok(owner, "freeze-policy on"));
	/* Idle connections cannot lock the owner out: the oldest idle one goes. */
	int idle[40];
	for (int i = 0; i < 40; i++) {
		idle[i] = cl_connect(&e);
		CHECK(cl_ok(idle[i], "ping"));
	}
	CHECK(cl_ok(owner, "ping"));
	CHECK(status_num(owner, "clients") == 16);
	CHECK(cl_closed(idle[0], 1000));
	for (int i = 0; i < 40; i++)
		close(idle[i]);

	/* Connections that hold a claim are never evicted; when all slots hold
	 * one, a newcomer is turned away. */
	int held[15];
	for (int i = 0; i < 15; i++) {
		held[i] = cl_connect(&e);
		CHECK(cl_ok(held[i], "inhibit " B " hold"));
	}
	int extra = cl_connect(&e);
	ssize_t n = recv(extra, reply, sizeof reply - 1, 0);
	CHECK(n > 0 && !strncmp(reply, "ERR busy", 8));
	CHECK(cl_closed(extra, 1000));
	close(extra);
	for (int i = 0; i < 15; i++)
		CHECK(cl_ok(held[i], "ping"));
	CHECK(cl_ok(owner, "ping"));
	CHECK(status_num(owner, "clients.rejected") == 1);
	for (int i = 0; i < 15; i++)
		close(held[i]);
	close(owner);
}

static void t_socket(void)
{
	struct stat st;
	daemon_start(&e, NULL);
	REQUIRE(stat(e.sock, &st) == 0);
	CHECK(S_ISSOCK(st.st_mode));
	CHECK((st.st_mode & 0777) == 0660);

	/* A second instance refuses to steal the socket. */
	pid_t second = daemon_spawn(&e, false, -1, NULL);
	int status = reap(second, 10000);
	CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 1);
	int c = cl_connect(&e);
	CHECK(cl_ok(c, "ping"));
	close(c);
	daemon_stop(&e, SIGTERM);

	/* A stale socket file from a dead instance is replaced. */
	daemon_start(&e, "socket_mode=0600", NULL);
	REQUIRE(stat(e.sock, &st) == 0);
	CHECK((st.st_mode & 0777) == 0600);
	daemon_stop(&e, SIGKILL);
	CHECK(access(e.sock, F_OK) == 0);
	daemon_start(&e, NULL);
	c = cl_connect(&e);
	CHECK(cl_ok(c, "ping"));
	close(c);
	daemon_stop(&e, SIGTERM);

	/* Unknown group: fail closed, no world-reachable socket left behind. */
	const char *over[] = { "socket_group=no-such-group-flo", NULL };
	pid_t bad = daemon_spawn(&e, false, -1, over);
	status = reap(bad, 10000);
	CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 1);
	CHECK(access(e.sock, F_OK) != 0);

	/* Something that is not a socket is never unlinked. */
	wr(e.sock, "precious\n");
	bad = daemon_spawn(&e, false, -1, NULL);
	status = reap(bad, 10000);
	CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 1);
	CHECK(is(e.sock, "precious"));
}

/* systemd socket activation: the listening socket arrives as fd 3. */
static void t_socket_activation(void)
{
	struct sockaddr_un sa = { .sun_family = AF_UNIX };
	strcpy(sa.sun_path, e.sock);
	int l = socket(AF_UNIX, SOCK_STREAM, 0);
	REQUIRE(l >= 0 && bind(l, (struct sockaddr *)&sa, sizeof sa) == 0 && listen(l, 8) == 0);
	daemon_spawn(&e, true, l, NULL);
	close(l);
	int c = cl_connect(&e);
	CHECK(cl_ok(c, "ping"));
	close(c);
	int st = daemon_stop(&e, SIGTERM);
	CHECK(WIFEXITED(st) && WEXITSTATUS(st) == 0);
	CHECK(access(e.sock, F_OK) == 0); /* systemd's socket: not ours to remove */
}

static void t_floctl(void)
{
	char out[8192];
	apps_default();
	daemon_start(&e, NULL);
	const char *v[] = { floctl_bin, "-s", e.sock, "version", NULL };
	CHECK(run(v, NULL, out, sizeof out) == 0);
	CHECK(!strncmp(out, "OK flo-sessiond ", 16));
	const char *s[] = { floctl_bin, "-s", e.sock, "status", NULL };
	CHECK(run(s, NULL, out, sizeof out) == 0);
	CHECK(strstr(out, "freezer.policy=off\n") && strstr(out, "\nOK\n"));
	const char *b[] = { floctl_bin, "-s", e.sock, "bogus", NULL };
	CHECK(run(b, NULL, out, sizeof out) == 1);
	CHECK(!strncmp(out, "ERR unknown-command", 19));
	const char *n[] = { floctl_bin, "-s", "/nonexistent/flo.sock", "ping", NULL };
	CHECK(run(n, NULL, out, sizeof out) == 2);
	const char *u[] = { floctl_bin, NULL };
	CHECK(run(u, NULL, out, sizeof out) == 2);
	const char *bo[] = { floctl_bin, "-s", e.sock, "boost", "50", NULL };
	CHECK(run(bo, NULL, out, sizeof out) == 0 && !strcmp(out, "OK 50\n"));

	/* Socket path from the environment. */
	setenv("FLO_SESSIOND_SOCKET", e.sock, 1);
	const char *p[] = { floctl_bin, "ping", NULL };
	CHECK(run(p, NULL, out, sizeof out) == 0);
	unsetenv("FLO_SESSIOND_SOCKET");

	/* Interactive mode keeps one connection, so it can own the policy. */
	const char *i[] = { floctl_bin, "-s", e.sock, "-i", NULL };
	CHECK(run(i, "freeze-policy on\nforeground " A "\nstatus\n", out, sizeof out) == 0);
	CHECK(strstr(out, "freezer.policy=on\n") && strstr(out, "foreground=" A "\n"));
	CHECK(run(i, "ping\nnope\n", out, sizeof out) == 1);

	/* inhibit -- PROGRAM holds the inhibit for the life of the program and
	 * passes its exit status through. */
	const char *ih[] = { floctl_bin, "-s", e.sock, "inhibit", B, "test", "run",
			     "--", "/bin/sh", "-c", "exit 7", NULL };
	CHECK(run(ih, NULL, out, sizeof out) == 7);
	CHECK(!strncmp(out, "OK ", 3));
	int c = cl_connect(&e);
	REQUIRE(cl_cmd(c, "status", out, sizeof out) == 0);
	CHECK(!strstr(out, "inhibit=")); /* released when floctl exited */
	close(c);
}

static void t_config(void)
{
	char out[8192], bad[P];
	const char *t[] = { daemon_bin, "-c", e.conf, "-t", NULL };
	CHECK(run(t, NULL, out, sizeof out) == 0);
	CHECK(strstr(out, "boost_hold_ms=200\n") && strstr(out, "freezer_grace_ms=400\n"));
	CHECK(strstr(out, "boost_freq_khz=1026000\n"));
	const char *o[] = { daemon_bin, "-c", e.conf, "-o", "boost_hold_ms=abc", "-t", NULL };
	CHECK(run(o, NULL, out, sizeof out) == 2);
	const char *r[] = { daemon_bin, "-c", e.conf, "-o", "freezer_root=relative/path", "-t", NULL };
	CHECK(run(r, NULL, out, sizeof out) == 2);
	const char *m[] = { daemon_bin, "-c", "/nonexistent/flo.conf", "-t", NULL };
	CHECK(run(m, NULL, out, sizeof out) == 2);
	path_join(bad, e.dir, "bad.conf", NULL);
	wr(bad, "boost_hold_ms = 100\nno_such_key = 1\n");
	const char *k[] = { daemon_bin, "-c", bad, "-t", NULL };
	CHECK(run(k, NULL, out, sizeof out) == 2);
	const char *x[] = { daemon_bin, "-c", e.conf, "stray", NULL };
	CHECK(run(x, NULL, out, sizeof out) == 2);
}

static const struct {
	const char *name;
	void (*fn)(void);
} tests[] = {
	{ "boost_first_touch", t_boost_first_touch },
	{ "boost_streaming", t_boost_streaming },
	{ "boost_timestamps", t_boost_timestamps },
	{ "boost_sigterm", t_boost_sigterm },
	{ "boost_command", t_boost_command },
	{ "boost_uclamp", t_boost_uclamp },
	{ "crash_restore", t_crash_restore },
	{ "kill_recovery", t_kill_recovery },
	{ "device_hotplug", t_device_hotplug },
	{ "cpu_offline", t_cpu_offline },
	{ "idle", t_idle },
	{ "freezer_grace", t_freezer_grace },
	{ "freezer_allowlist", t_freezer_allowlist },
	{ "freezer_inhibit", t_freezer_inhibit },
	{ "freezer_fail_open", t_freezer_fail_open },
	{ "freezer_controls", t_freezer_controls },
	{ "freezer_exit", t_freezer_exit },
	{ "freezer_new_app", t_freezer_new_app },
	{ "proto_negative", t_proto_negative },
	{ "many_clients", t_many_clients },
	{ "socket", t_socket },
	{ "socket_activation", t_socket_activation },
	{ "floctl", t_floctl },
	{ "config", t_config },
};

int main(int argc, char **argv)
{
	if (argc == 2 && !strcmp(argv[1], "--list")) {
		for (size_t i = 0; i < sizeof tests / sizeof tests[0]; i++)
			puts(tests[i].name);
		return 0;
	}
	if (argc != 4) {
		fprintf(stderr, "usage: %s <flo-sessiond> <floctl> <test>\n", argv[0]);
		return 2;
	}
	daemon_bin = argv[1];
	floctl_bin = argv[2];
	const char *s = getenv("FLO_TEST_SLOW");
	if (s && atof(s) >= 1.0)
		slow = atof(s);
	signal(SIGPIPE, SIG_IGN);
	for (size_t i = 0; i < sizeof tests / sizeof tests[0]; i++) {
		if (strcmp(tests[i].name, argv[3]) != 0)
			continue;
		env_init(&e);
		tests[i].fn();
		if (e.pid > 0) {
			/* Every test must leave a daemon that still shuts down cleanly. */
			int st = daemon_stop(&e, SIGTERM);
			CHECK(WIFEXITED(st) && WEXITSTATUS(st) == 0);
		}
		if (failures)
			fprintf(stderr, "%s: %d check(s) failed\n", argv[3], failures);
		return failures ? 1 : 0;
	}
	fprintf(stderr, "unknown test %s\n", argv[3]);
	return 2;
}
