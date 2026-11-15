/*
 * flo-sessiond: touch boost.
 *
 * State machine:
 *   idle     input fd armed for EPOLLIN, no timer.
 *   boosted  entered on the first readable event: the floor is raised, the
 *            input fd is muted (event mask 0, so only hang-up is reported)
 *            and one timerfd is armed for the hold time. While a finger
 *            stays down the daemon therefore wakes once per hold period,
 *            not once per 100 Hz frame: the timer handler drains the evdev
 *            queue and, if anything arrived, pushes the deadline forward.
 *            Only when a whole hold period passes with no events is the
 *            floor restored and the input fd re-armed.
 *
 * SPDX-License-Identifier: MIT
 */
#include "sessiond.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <fnmatch.h>
#include <linux/input.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/inotify.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

enum kstate {
	K_IDLE,    /* not touched by us */
	K_BOOSTED, /* we wrote the boost value, orig holds what to put back */
	K_PENDING, /* boost over, but writing orig back failed: retry later */
};

struct knob {
	bool used, is_freq, seen;
	enum kstate st;
	char path[PATH_LEN];
	char orig[VALUE_LEN];
};

static struct knob knobs[MAX_KNOBS];
static char freq_str[VALUE_LEN];
static bool active;
static int64_t deadline;
static int boost_tfd = -1, retry_tfd = -1, state_fd = -1;
static int retry_backoff_ms;

static int in_fd = -1, ino_fd = -1, ino_wd = -1;
static bool in_trusted, in_got_data;
static uint64_t in_gen; /* tells events of a closed fd from the current one */
static char in_path[PATH_LEN];

static uint64_t n_boosts, n_writes, n_input_wakeups, n_timer_wakeups, n_restore_failures;

#define RETRY_MIN_MS 1000
#define RETRY_MAX_MS 64000

/* ---------------------------------------------------------------- knobs */

static const char *knob_want(const struct knob *k)
{
	return k->is_freq ? freq_str : cfg.uclamp_min;
}

static struct knob *knob_find(const char *path)
{
	for (int i = 0; i < MAX_KNOBS; i++)
		if (knobs[i].used && strcmp(knobs[i].path, path) == 0)
			return &knobs[i];
	return NULL;
}

static struct knob *knob_add(const char *path, bool is_freq)
{
	struct knob *k = knob_find(path);
	if (k)
		return k;
	if (strlen(path) >= PATH_LEN)
		return NULL;
	for (int i = 0; i < MAX_KNOBS; i++) {
		if (knobs[i].used)
			continue;
		k = &knobs[i];
		memset(k, 0, sizeof *k);
		strcpy(k->path, path);
		k->is_freq = is_freq;
		k->st = K_IDLE;
		k->used = true;
		return k;
	}
	return NULL;
}

static bool policy_name(const char *name)
{
	if (strncmp(name, "policy", 6) != 0 || name[6] == '\0')
		return false;
	for (const char *p = name + 6; *p; p++)
		if (*p < '0' || *p > '9')
			return false;
	return true;
}

/*
 * (Re)enumerate cpufreq policies. Called at start and after every release,
 * never on the latency-critical boost path. A policy that vanished is
 * forgotten only if we hold nothing to restore on it.
 */
static void scan_policies(void)
{
	if (!(cfg.boost_mode & BOOST_MODE_FREQ))
		return;
	DIR *d = opendir(cfg.cpufreq_root);
	if (!d)
		return;
	for (int i = 0; i < MAX_KNOBS; i++)
		knobs[i].seen = false;
	struct dirent *e;
	while ((e = readdir(d))) {
		if (!policy_name(e->d_name))
			continue;
		char path[PATH_LEN];
		int n = snprintf(path, sizeof path, "%s/%s/scaling_min_freq", cfg.cpufreq_root,
				 e->d_name);
		if (n < 0 || (size_t)n >= sizeof path)
			continue;
		struct knob *k = knob_add(path, true);
		if (k)
			k->seen = true;
	}
	closedir(d);
	for (int i = 0; i < MAX_KNOBS; i++)
		if (knobs[i].used && knobs[i].is_freq && !knobs[i].seen && knobs[i].st == K_IDLE)
			knobs[i].used = false;
}

/*
 * Crash-recovery record: "<path> <original value>" for every knob we hold.
 * Rewritten in place (pwrite + ftruncate) when a boost starts and emptied
 * when it ends, so a SIGKILL while boosted is undone by the next start.
 */
static void state_save(void)
{
	if (state_fd < 0)
		return;
	char buf[4096];
	size_t len = 0;
	for (int i = 0; i < MAX_KNOBS; i++) {
		const struct knob *k = &knobs[i];
		if (!k->used || k->st == K_IDLE)
			continue;
		int n = snprintf(buf + len, sizeof buf - len, "%s %s\n", k->path, k->orig);
		if (n < 0 || (size_t)n >= sizeof buf - len)
			break;
		len += (size_t)n;
	}
	if (len > 0 && pwrite(state_fd, buf, len, 0) != (ssize_t)len)
		log_msg(LOG_WARNING, "boost: cannot write state file: %s", strerror(errno));
	if (ftruncate(state_fd, (off_t)len) < 0)
		log_msg(LOG_WARNING, "boost: cannot truncate state file: %s", strerror(errno));
}

static void retry_arm(void)
{
	retry_backoff_ms = retry_backoff_ms ? retry_backoff_ms * 2 : RETRY_MIN_MS;
	if (retry_backoff_ms > RETRY_MAX_MS)
		retry_backoff_ms = RETRY_MAX_MS;
	timer_arm(retry_tfd, now_ns() + (int64_t)retry_backoff_ms * 1000000);
}

/* Undo what a previous instance left behind (it was killed while boosted). */
static void state_recover(void)
{
	char buf[4096];
	ssize_t n = pread(state_fd, buf, sizeof buf - 1, 0);
	if (n <= 0)
		return;
	buf[n] = '\0';
	bool pending = false;
	char *save = NULL;
	for (char *line = strtok_r(buf, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
		char *sp = strchr(line, ' ');
		if (!sp)
			continue;
		*sp = '\0';
		const char *val = sp + 1;
		/* Only paths this configuration manages; only well-formed values. */
		struct knob *k = knob_find(line);
		if (!k || strlen(val) >= VALUE_LEN ||
		    !(k->is_freq ? freq_value_sane(val) : pct_parse(val) >= 0)) {
			log_msg(LOG_WARNING, "boost: ignoring stale state entry %s", line);
			continue;
		}
		strcpy(k->orig, val);
		int r = write_small_at(AT_FDCWD, k->path, k->orig);
		n_writes++;
		if (r == 0) {
			log_msg(LOG_INFO, "boost: recovered %s -> %s", k->path, k->orig);
		} else if (r != -ENOENT) {
			k->st = K_PENDING;
			pending = true;
		}
	}
	state_save();
	if (pending)
		retry_arm();
}

/*
 * Boosting is done in two passes with the state file written in between:
 * first decide which knobs to raise and remember their current values, then
 * record that, and only then write. Being killed at any point therefore
 * leaves a record of everything that may have been changed.
 */
static bool knob_prepare(struct knob *k)
{
	if (k->st == K_BOOSTED)
		return false;
	if (k->st == K_PENDING)
		return true; /* orig is already the value to go back to */
	const char *want = knob_want(k);
	char cur[VALUE_LEN];
	if (read_small_at(AT_FDCWD, k->path, cur, sizeof cur) <= 0)
		return false; /* CPU offline or policy gone */
	if (k->is_freq) {
		long v;
		if (!parse_long(cur, 0, 100000000L, &v) || v >= cfg.boost_freq_khz)
			return false; /* floor already at or above the boost */
	} else {
		int v = pct_parse(cur);
		if (v < 0 || v >= pct_parse(want))
			return false;
	}
	strcpy(k->orig, cur);
	return true;
}

static void knobs_apply(void)
{
	bool todo[MAX_KNOBS];
	enum kstate prev[MAX_KNOBS];
	for (int i = 0; i < MAX_KNOBS; i++) {
		struct knob *k = &knobs[i];
		prev[i] = k->st;
		todo[i] = k->used && knob_prepare(k);
		if (todo[i])
			k->st = K_BOOSTED;
	}
	state_save();
	for (int i = 0; i < MAX_KNOBS; i++) {
		struct knob *k = &knobs[i];
		if (!todo[i])
			continue;
		int r = write_small_at(AT_FDCWD, k->path, knob_want(k));
		n_writes++;
		if (r < 0) {
			k->st = prev[i];
			log_msg(LOG_DEBUG, "boost: %s: %s", k->path, strerror(-r));
		}
	}
}

/* Returns true if some knob could not be restored. */
static bool knobs_restore(void)
{
	bool pending = false;
	for (int i = 0; i < MAX_KNOBS; i++) {
		struct knob *k = &knobs[i];
		if (!k->used || k->st == K_IDLE)
			continue;
		int r = write_small_at(AT_FDCWD, k->path, k->orig);
		n_writes++;
		if (r == 0 || r == -ENOENT || r == -ENOTDIR) {
			/* Gone means nothing is left to restore. */
			k->st = K_IDLE;
		} else {
			/* Typically EBUSY: the CPU went offline while boosted and the
			 * kernel keeps our floor for when it returns. */
			if (k->st != K_PENDING) {
				n_restore_failures++;
				log_msg(LOG_WARNING, "boost: cannot restore %s: %s (will retry)",
					k->path, strerror(-r));
			}
			k->st = K_PENDING;
			pending = true;
		}
	}
	return pending;
}

/* ---------------------------------------------------------------- input */

static void input_mute(bool mute)
{
	if (in_fd >= 0)
		ep_mod(in_fd, mute ? 0 : EPOLLIN, TAG_INPUT, in_gen);
}

static void input_close(void)
{
	if (in_fd < 0)
		return;
	ep_del(in_fd);
	close(in_fd);
	in_fd = -1;
}

/* Open one candidate node. With check_name it must be an evdev device whose
 * name matches input_name. */
static int input_try(const char *path, bool check_name)
{
	int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOCTTY);
	if (fd < 0)
		return -1;
	struct stat st;
	if (fstat(fd, &st) < 0 ||
	    !(S_ISCHR(st.st_mode) || S_ISFIFO(st.st_mode) || S_ISSOCK(st.st_mode))) {
		close(fd);
		return -1;
	}
	if (check_name) {
		char name[128] = "";
		if (ioctl(fd, EVIOCGNAME(sizeof name - 1), name) < 0 ||
		    fnmatch(cfg.input_name, name, 0) != 0) {
			close(fd);
			return -1;
		}
	}
	/* Ask for CLOCK_MONOTONIC timestamps so the hold time can be counted
	 * from the last event itself rather than from when we noticed it. */
	int clk = CLOCK_MONOTONIC;
	bool mono = ioctl(fd, EVIOCSCLOCKID, &clk) == 0;
	in_trusted = cfg.input_timestamps == INPUT_TS_TRUST ||
		     (cfg.input_timestamps == INPUT_TS_AUTO && mono);
	if (ep_add(fd, active ? 0 : EPOLLIN, TAG_INPUT, ++in_gen) < 0) {
		close(fd);
		return -1;
	}
	in_fd = fd;
	in_got_data = false;
	snprintf(in_path, sizeof in_path, "%s", path);
	log_msg(LOG_INFO, "input: using %s (%s timestamps)", path,
		in_trusted ? "event" : "arrival");
	return 0;
}

static void input_watch_dir(char *out, size_t size)
{
	if (strcmp(cfg.input_device, "auto") == 0) {
		snprintf(out, size, "%s", cfg.input_dir);
		return;
	}
	snprintf(out, size, "%s", cfg.input_device);
	char *slash = strrchr(out, '/');
	if (slash == out)
		out[1] = '\0';
	else if (slash)
		*slash = '\0';
}

static void input_scan(void)
{
	if (strcmp(cfg.input_device, "auto") != 0) {
		input_try(cfg.input_device, false);
		return;
	}
	DIR *d = opendir(cfg.input_dir);
	if (!d)
		return;
	struct dirent *e;
	while (in_fd < 0 && (e = readdir(d))) {
		if (strncmp(e->d_name, "event", 5) != 0)
			continue;
		char path[PATH_LEN];
		int n = snprintf(path, sizeof path, "%s/%s", cfg.input_dir, e->d_name);
		if (n > 0 && (size_t)n < sizeof path)
			input_try(path, true);
	}
	closedir(d);
}

/*
 * Find the device. While it is missing, an inotify watch on its directory
 * wakes us when a node shows up; once found the watch is dropped again, so a
 * present device costs no directory wakeups at all.
 */
static void input_watch(void)
{
	if (ino_wd >= 0 || ino_fd < 0)
		return;
	char dir[PATH_LEN];
	input_watch_dir(dir, sizeof dir);
	ino_wd = inotify_add_watch(ino_fd, dir, IN_CREATE | IN_MOVED_TO | IN_ATTRIB | IN_ONLYDIR);
	if (ino_wd < 0)
		log_msg(LOG_WARNING, "input: cannot watch %s: %s", dir, strerror(errno));
}

static void input_open(void)
{
	if (in_fd >= 0 || !cfg.boost_enabled)
		return;
	input_scan();
	if (in_fd < 0 && ino_wd < 0) {
		/* Watch, then look again: a node created in between is not missed. */
		input_watch();
		input_scan();
	}
	if (in_fd >= 0 && ino_wd >= 0) {
		inotify_rm_watch(ino_fd, ino_wd);
		ino_wd = -1;
	}
}

static void input_gone(void)
{
	bool retry_now = in_got_data;
	log_msg(LOG_INFO, "input: %s went away", in_path);
	input_close();
	/* Reopen at once only if the old fd had delivered data; otherwise wait
	 * for inotify, so a node that hangs up on open cannot make us spin. */
	if (retry_now)
		input_open();
	else
		input_watch();
}

struct drained {
	bool activity, gone;
	int64_t last_ns;
};

/* Empty the evdev queue. Bounded: at most 32 reads of 64 events. */
static struct drained input_drain(int64_t now)
{
	struct drained d = { false, false, now };
	struct input_event ev[64];
	for (int i = 0; i < 32; i++) {
		ssize_t n = read(in_fd, ev, sizeof ev);
		if (n > 0) {
			d.activity = true;
			size_t cnt = (size_t)n / sizeof ev[0];
			if (in_trusted && cnt > 0) {
				/* input_event_sec/usec hide the 32-bit time64 layout. */
				const struct input_event *l = &ev[cnt - 1];
				int64_t ts = (int64_t)l->input_event_sec * 1000000000LL +
					     (int64_t)l->input_event_usec * 1000LL;
				/* Believe it only if plausible. */
				if (ts <= now && ts > now - 10000000000LL)
					d.last_ns = ts;
				else
					d.last_ns = now;
			}
			if ((size_t)n < sizeof ev)
				break;
			continue;
		}
		if (n == 0) {
			d.gone = true;
			break;
		}
		if (errno == EINTR)
			continue;
		if (errno != EAGAIN)
			d.gone = true;
		break;
	}
	return d;
}

/* ---------------------------------------------------------------- boost */

static void boost_start(int64_t dl)
{
	if (active) {
		/* The armed timer fires at the old deadline and re-arms itself:
		 * extending costs no syscall here. */
		if (dl > deadline)
			deadline = dl;
		return;
	}
	knobs_apply();
	active = true;
	deadline = dl;
	n_boosts++;
	timer_arm(boost_tfd, deadline);
	input_mute(true);
}

static void boost_release(void)
{
	bool pending = knobs_restore();
	active = false;
	state_save();
	if (pending)
		retry_arm();
	else
		retry_backoff_ms = 0;
	input_mute(false);
	scan_policies();
}

void boost_on_input(uint32_t events, uint64_t gen)
{
	if (in_fd < 0 || gen != in_gen)
		return;
	n_input_wakeups++;
	int64_t now = now_ns();
	struct drained d = input_drain(now);
	if (d.activity) {
		in_got_data = true;
		boost_start(d.last_ns + (int64_t)cfg.boost_hold_ms * 1000000);
	}
	if (d.gone || (!d.activity && (events & (EPOLLHUP | EPOLLERR))))
		input_gone();
}

void boost_on_timer(void)
{
	timer_ack(boost_tfd);
	n_timer_wakeups++;
	if (!active)
		return;
	int64_t now = now_ns();
	if (in_fd >= 0) {
		struct drained d = input_drain(now);
		if (d.activity) {
			in_got_data = true;
			int64_t dl = d.last_ns + (int64_t)cfg.boost_hold_ms * 1000000;
			if (dl > deadline)
				deadline = dl;
		}
		if (d.gone)
			input_gone();
	}
	if (now >= deadline)
		boost_release();
	else
		timer_arm(boost_tfd, deadline);
}

void boost_on_retry(void)
{
	timer_ack(retry_tfd);
	if (active)
		return; /* the release at the end of this boost tries again */
	if (knobs_restore()) {
		retry_arm();
	} else {
		retry_backoff_ms = 0;
		state_save();
	}
}

void boost_on_input_inotify(void)
{
	inotify_drain(ino_fd);
	input_open();
}

/* Explicit boost asked by a client (e.g. the shell at app launch). */
int boost_request(int ms)
{
	if (!cfg.boost_enabled)
		return -ENOTSUP;
	if (ms > cfg.boost_request_max_ms)
		ms = cfg.boost_request_max_ms;
	if (ms > 0)
		boost_start(now_ns() + (int64_t)ms * 1000000);
	return ms;
}

int boost_init(void)
{
	if (!cfg.boost_enabled)
		return 0;
	snprintf(freq_str, sizeof freq_str, "%ld", cfg.boost_freq_khz);
	boost_tfd = timer_new(TAG_BOOST_TIMER);
	retry_tfd = timer_new(TAG_RETRY_TIMER);
	if (boost_tfd < 0 || retry_tfd < 0)
		return -1;
	if (cfg.boost_mode & BOOST_MODE_UCLAMP) {
		char path[PATH_LEN + 16];
		snprintf(path, sizeof path, "%s/cpu.uclamp.min", cfg.uclamp_cgroup);
		if (!knob_add(path, false))
			log_msg(LOG_WARNING, "boost: uclamp path too long");
	}
	scan_policies();
	if (cfg.state_file[0]) {
		state_fd = open(cfg.state_file, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
		if (state_fd < 0)
			log_msg(LOG_WARNING, "boost: state file %s: %s (no crash recovery)",
				cfg.state_file, strerror(errno));
		else
			state_recover();
	}
	ino_fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
	if (ino_fd < 0 || ep_add(ino_fd, EPOLLIN, TAG_INPUT_INOTIFY, 0) < 0)
		log_msg(LOG_WARNING, "input: inotify unavailable, no hotplug");
	input_open();
	if (in_fd < 0)
		log_msg(LOG_INFO, "input: no touch device yet, waiting");
	return 0;
}

void boost_shutdown(void)
{
	if (!cfg.boost_enabled)
		return;
	knobs_restore();
	active = false;
	state_save();
	input_close();
}

/* Crash path: async-signal-safe, touches only static tables. */
void boost_emergency(void)
{
	for (int i = 0; i < MAX_KNOBS; i++)
		if (knobs[i].used && knobs[i].st != K_IDLE)
			write_small_at(AT_FDCWD, knobs[i].path, knobs[i].orig);
}

void boost_status(struct sbuf *sb)
{
	int nk = 0, held = 0, pending = 0;
	for (int i = 0; i < MAX_KNOBS; i++) {
		if (!knobs[i].used)
			continue;
		nk++;
		held += knobs[i].st == K_BOOSTED;
		pending += knobs[i].st == K_PENDING;
	}
	sb_printf(sb, "boost.enabled=%d\n", cfg.boost_enabled);
	sb_printf(sb, "boost.active=%d\n", active);
	sb_printf(sb, "boost.knobs=%d\nboost.knobs_held=%d\nboost.knobs_pending=%d\n", nk, held,
		  pending);
	sb_printf(sb, "boost.count=%llu\nboost.writes=%llu\n", (unsigned long long)n_boosts,
		  (unsigned long long)n_writes);
	sb_printf(sb, "boost.input_wakeups=%llu\nboost.timer_wakeups=%llu\n",
		  (unsigned long long)n_input_wakeups, (unsigned long long)n_timer_wakeups);
	sb_printf(sb, "boost.restore_failures=%llu\n", (unsigned long long)n_restore_failures);
	sb_printf(sb, "input.device=%s\n", in_fd >= 0 ? in_path : "-");
	sb_printf(sb, "input.timestamps=%s\n", in_trusted ? "event" : "arrival");
}
