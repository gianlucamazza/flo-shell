/*
 * flo-sessiond: background app freezer (cgroup v2 cgroup.freeze).
 *
 * One client (the shell) owns the policy and names the foreground app
 * cgroups. Every other freezable app cgroup directly below freezer_root is
 * frozen once it has been in the background for freezer_grace_ms.
 *
 * Fail-open rules: anything we froze is thawed when the owner disconnects,
 * when the policy is switched off, when the screen locks, when the daemon
 * exits or crashes, and once more at the next start.
 *
 * Every cgroup access goes through the root directory fd, one component at
 * a time with O_NOFOLLOW, so nothing outside freezer_root can be reached.
 *
 * SPDX-License-Identifier: MIT
 */
#include "sessiond.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <unistd.h>

struct app {
	bool used, seen, frozen;
	int64_t bg_since; /* 0 = not eligible right now */
	char name[NAME_LEN];
};

struct inhibit {
	bool used;
	uint64_t client;
	unsigned token;
	char name[NAME_LEN];
	char reason[REASON_LEN];
};

static struct app apps[MAX_APPS];
static struct inhibit inhibits[MAX_INHIBITS];
static char fg[MAX_FG][NAME_LEN];
static int nfg;
static bool policy_on, locked;
static uint64_t owner;
static unsigned next_token = 1;
static int rootfd = -1, tfd = -1, ino_fd = -1, ino_wd = -1;
static uint64_t n_freezes, n_thaws;

/*
 * Write "0"/"1" to <root>/<name>/cgroup.freeze. name is a single path
 * component. Async-signal-safe (openat/write/close only).
 */
static int cg_write_freeze(int root, const char *name, const char *val)
{
	if (root < 0)
		return -ENOENT;
	int d = openat(root, name, O_PATH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
	if (d < 0)
		return -errno;
	int r = write_small_at(d, "cgroup.freeze", val);
	close(d);
	return r;
}

static bool cg_is_frozen(int root, const char *name)
{
	int d = openat(root, name, O_PATH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
	if (d < 0)
		return false;
	char buf[8];
	ssize_t n = read_small_at(d, "cgroup.freeze", buf, sizeof buf);
	close(d);
	return n == 1 && buf[0] == '1';
}

/* Is this directory entry an app cgroup we are allowed to freeze? */
static bool freezable(int root, const struct dirent *e)
{
	const char *name = e->d_name;
	if (name[0] == '.' || strlen(name) >= NAME_LEN)
		return false;
	if (e->d_type == DT_UNKNOWN) {
		struct stat st;
		if (fstatat(root, name, &st, AT_SYMLINK_NOFOLLOW) < 0 || !S_ISDIR(st.st_mode))
			return false;
	} else if (e->d_type != DT_DIR) {
		return false; /* in particular: never a symlink */
	}
	if (!globlist_match(&cfg.freezer_match, name))
		return false;
	char id[NAME_LEN];
	bool has_id = unit_desktop_id(name, id, sizeof id);
	if (globlist_match(&cfg.freezer_deny, name) ||
	    (has_id && globlist_match(&cfg.freezer_deny, id)))
		return false;
	if (cfg.freezer_allow.n > 0 && !globlist_match(&cfg.freezer_allow, name) &&
	    !(has_id && globlist_match(&cfg.freezer_allow, id)))
		return false;
	return true;
}

static DIR *root_opendir(int root)
{
	int fd = openat(root, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
	if (fd < 0)
		return NULL;
	DIR *d = fdopendir(fd);
	if (!d)
		close(fd);
	return d;
}

/* Thaw every matching cgroup that reads back frozen, tracked or not. */
static int thaw_scan(int root)
{
	int count = 0;
	DIR *d = root < 0 ? NULL : root_opendir(root);
	if (!d)
		return 0;
	struct dirent *e;
	while ((e = readdir(d))) {
		if (e->d_type != DT_DIR && e->d_type != DT_UNKNOWN)
			continue;
		if (e->d_name[0] == '.' || !globlist_match(&cfg.freezer_match, e->d_name))
			continue;
		if (cg_is_frozen(root, e->d_name) && cg_write_freeze(root, e->d_name, "0") == 0) {
			count++;
			n_thaws++;
			log_msg(LOG_INFO, "freezer: thawed %s", e->d_name);
		}
	}
	closedir(d);
	return count;
}

static bool is_fg(const char *name)
{
	for (int i = 0; i < nfg; i++)
		if (strcmp(fg[i], name) == 0)
			return true;
	return false;
}

static bool is_inhibited(const char *name)
{
	for (int i = 0; i < MAX_INHIBITS; i++)
		if (inhibits[i].used && strcmp(inhibits[i].name, name) == 0)
			return true;
	return false;
}

static void app_thaw(struct app *a)
{
	if (!a->frozen)
		return;
	int r = cg_write_freeze(rootfd, a->name, "0");
	n_thaws++;
	if (r == 0 || r == -ENOENT || r == -ENODEV) {
		a->frozen = false;
		log_msg(LOG_DEBUG, "freezer: thawed %s", a->name);
	} else {
		log_msg(LOG_ERR, "freezer: cannot thaw %s: %s", a->name, strerror(-r));
	}
}

/* Apply the policy to the tracked apps and schedule the next freeze. */
static void eval(int64_t now)
{
	int64_t next = INT64_MAX;
	int64_t grace = (int64_t)cfg.freezer_grace_ms * 1000000;
	for (int i = 0; i < MAX_APPS; i++) {
		struct app *a = &apps[i];
		if (!a->used)
			continue;
		bool eligible = policy_on && !locked && !is_fg(a->name) && !is_inhibited(a->name);
		if (!eligible) {
			app_thaw(a);
			a->bg_since = 0;
			continue;
		}
		if (!a->bg_since)
			a->bg_since = now;
		if (a->frozen)
			continue;
		if (now < a->bg_since + grace) {
			if (a->bg_since + grace < next)
				next = a->bg_since + grace;
			continue;
		}
		int r = cg_write_freeze(rootfd, a->name, "1");
		if (r == 0) {
			a->frozen = true;
			n_freezes++;
			log_msg(LOG_DEBUG, "freezer: froze %s", a->name);
		} else if (r == -ENOENT) {
			a->used = false;
		} else {
			/* Not retried until the next foreground change or rescan. */
			log_msg(LOG_WARNING, "freezer: cannot freeze %s: %s", a->name,
				strerror(-r));
		}
	}
	if (tfd < 0)
		return;
	if (next == INT64_MAX)
		timer_disarm(tfd);
	else
		timer_arm(tfd, next);
}

/* Re-read the root: pick up new app cgroups, forget the ones that exited. */
static void rescan(int64_t now)
{
	if (!policy_on)
		return;
	/* Reopen every time: app.slice is removed when the last app exits and
	 * a stale directory fd would silently see nothing. */
	int nfd = open(cfg.freezer_root, O_PATH | O_DIRECTORY | O_CLOEXEC);
	if (nfd >= 0) {
		int old = rootfd;
		rootfd = nfd;
		if (old >= 0)
			close(old);
		if (ino_fd >= 0)
			ino_wd = inotify_add_watch(ino_fd, cfg.freezer_root,
						   IN_CREATE | IN_DELETE | IN_MOVED_TO |
							   IN_MOVED_FROM | IN_ONLYDIR);
	}
	DIR *d = nfd >= 0 ? root_opendir(rootfd) : NULL;
	for (int i = 0; i < MAX_APPS; i++)
		apps[i].seen = false;
	struct dirent *e;
	while (d && (e = readdir(d))) {
		if (!freezable(rootfd, e))
			continue;
		struct app *slot = NULL, *found = NULL;
		for (int i = 0; i < MAX_APPS; i++) {
			if (apps[i].used && strcmp(apps[i].name, e->d_name) == 0) {
				found = &apps[i];
				break;
			}
			if (!apps[i].used && !slot)
				slot = &apps[i];
		}
		if (!found && slot) {
			found = slot;
			memset(found, 0, sizeof *found);
			strcpy(found->name, e->d_name);
			found->used = true;
		}
		/* Table full: the app is simply never frozen. */
		if (found)
			found->seen = true;
	}
	if (d)
		closedir(d);
	for (int i = 0; i < MAX_APPS; i++)
		if (apps[i].used && !apps[i].seen)
			apps[i].used = false;
	eval(now);
}

static void policy_off(void)
{
	for (int i = 0; i < MAX_APPS; i++) {
		if (apps[i].used)
			app_thaw(&apps[i]);
		apps[i].used = false;
	}
	policy_on = false;
	locked = false;
	owner = 0;
	nfg = 0;
	if (tfd >= 0)
		timer_disarm(tfd);
	if (ino_fd >= 0 && ino_wd >= 0) {
		inotify_rm_watch(ino_fd, ino_wd);
		ino_wd = -1;
	}
	if (rootfd >= 0) {
		close(rootfd);
		rootfd = -1;
	}
}

int freezer_set_policy(uint64_t client, bool on)
{
	if (!cfg.freezer_enabled)
		return -ENOTSUP;
	if (!on) {
		/* Thawing is allowed to anyone: it is the safe direction. */
		if (policy_on)
			log_msg(LOG_INFO, "freezer: policy off");
		policy_off();
		return 0;
	}
	if (policy_on && owner != client)
		return -EBUSY;
	if (!policy_on) {
		policy_on = true;
		owner = client;
		log_msg(LOG_INFO, "freezer: policy on");
	}
	rescan(now_ns());
	return 0;
}

int freezer_set_foreground(uint64_t client, const char *const *paths, int n)
{
	if (!cfg.freezer_enabled)
		return -ENOTSUP;
	if (!policy_on || owner != client)
		return -EPERM;
	if (n > MAX_FG)
		return -E2BIG;
	for (int i = 0; i < n; i++)
		if (!rel_path_valid(paths[i]))
			return -EINVAL;
	for (int i = 0; i < n; i++)
		rel_path_first(paths[i], fg[i]);
	nfg = n;
	int64_t now = now_ns();
	eval(now);   /* thaw the new foreground first: this is the urgent part */
	rescan(now); /* then catch up with apps that appeared or exited */
	return 0;
}

int freezer_set_locked(uint64_t client, bool on)
{
	if (!cfg.freezer_enabled)
		return -ENOTSUP;
	if (!policy_on || owner != client)
		return -EPERM;
	locked = on;
	rescan(now_ns());
	return 0;
}

int freezer_inhibit(uint64_t client, const char *path, const char *reason, unsigned *token)
{
	if (!cfg.freezer_enabled)
		return -ENOTSUP;
	if (!rel_path_valid(path))
		return -EINVAL;
	int mine = 0;
	struct inhibit *slot = NULL;
	for (int i = 0; i < MAX_INHIBITS; i++) {
		if (inhibits[i].used)
			mine += inhibits[i].client == client;
		else if (!slot)
			slot = &inhibits[i];
	}
	if (!slot || mine >= MAX_INHIBITS_PER_CLIENT)
		return -ENOSPC;
	memset(slot, 0, sizeof *slot);
	slot->client = client;
	slot->token = next_token++;
	if (next_token > 0x7fffffffu)
		next_token = 1;
	rel_path_first(path, slot->name);
	snprintf(slot->reason, sizeof slot->reason, "%s", reason);
	slot->used = true;
	*token = slot->token;
	eval(now_ns());
	return 0;
}

/* Tokens are only valid on the connection that obtained them. */
int freezer_uninhibit(uint64_t client, unsigned token)
{
	for (int i = 0; i < MAX_INHIBITS; i++) {
		if (inhibits[i].used && inhibits[i].client == client &&
		    inhibits[i].token == token) {
			inhibits[i].used = false;
			eval(now_ns());
			return 0;
		}
	}
	return -ENOENT;
}

/* Thaw one app now; its grace period starts over. */
int freezer_thaw(const char *path)
{
	if (!cfg.freezer_enabled)
		return -ENOTSUP;
	if (!rel_path_valid(path))
		return -EINVAL;
	char name[NAME_LEN];
	rel_path_first(path, name);
	if (!globlist_match(&cfg.freezer_match, name))
		return -EINVAL;
	for (int i = 0; i < MAX_APPS; i++) {
		if (apps[i].used && strcmp(apps[i].name, name) == 0) {
			app_thaw(&apps[i]);
			apps[i].bg_since = 0;
			eval(now_ns());
			return 0;
		}
	}
	int root = open(cfg.freezer_root, O_PATH | O_DIRECTORY | O_CLOEXEC);
	if (root < 0)
		return -ENOENT;
	int r = cg_write_freeze(root, name, "0");
	close(root);
	return r == 0 ? 0 : -ENOENT;
}

/* Thaw everything now; grace periods start over. Returns how many thawed. */
int freezer_thaw_all(void)
{
	if (!cfg.freezer_enabled)
		return -ENOTSUP;
	int count = 0;
	for (int i = 0; i < MAX_APPS; i++) {
		if (!apps[i].used)
			continue;
		if (apps[i].frozen) {
			app_thaw(&apps[i]);
			count += !apps[i].frozen;
		}
		apps[i].bg_since = 0;
	}
	int root = open(cfg.freezer_root, O_PATH | O_DIRECTORY | O_CLOEXEC);
	if (root >= 0) {
		count += thaw_scan(root);
		close(root);
	}
	eval(now_ns());
	return count;
}

bool freezer_client_has_state(uint64_t client)
{
	if (policy_on && owner == client)
		return true;
	for (int i = 0; i < MAX_INHIBITS; i++)
		if (inhibits[i].used && inhibits[i].client == client)
			return true;
	return false;
}

void freezer_client_gone(uint64_t client)
{
	bool changed = false;
	for (int i = 0; i < MAX_INHIBITS; i++) {
		if (inhibits[i].used && inhibits[i].client == client) {
			inhibits[i].used = false;
			changed = true;
		}
	}
	if (policy_on && owner == client) {
		log_msg(LOG_INFO, "freezer: policy owner disconnected, thawing everything");
		policy_off();
	} else if (changed) {
		eval(now_ns());
	}
}

void freezer_on_timer(void)
{
	timer_ack(tfd);
	eval(now_ns());
}

void freezer_on_inotify(void)
{
	inotify_drain(ino_fd);
	rescan(now_ns());
}

int freezer_init(void)
{
	if (!cfg.freezer_enabled)
		return 0;
	tfd = timer_new(TAG_FREEZE_TIMER);
	if (tfd < 0)
		return -1;
	ino_fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
	if (ino_fd < 0 || ep_add(ino_fd, EPOLLIN, TAG_FREEZE_INOTIFY, 0) < 0)
		log_msg(LOG_WARNING, "freezer: inotify unavailable");
	/* A previous instance may have died with apps frozen. */
	int root = open(cfg.freezer_root, O_PATH | O_DIRECTORY | O_CLOEXEC);
	if (root >= 0) {
		thaw_scan(root);
		close(root);
	}
	return 0;
}

void freezer_shutdown(void)
{
	if (!cfg.freezer_enabled)
		return;
	policy_off();
	int root = open(cfg.freezer_root, O_PATH | O_DIRECTORY | O_CLOEXEC);
	if (root >= 0) {
		thaw_scan(root);
		close(root);
	}
}

/* Crash path: async-signal-safe, touches only static tables. */
void freezer_emergency(void)
{
	for (int i = 0; i < MAX_APPS; i++)
		if (apps[i].used && apps[i].frozen)
			cg_write_freeze(rootfd, apps[i].name, "0");
}

void freezer_status(struct sbuf *sb)
{
	int64_t now = now_ns();
	sb_printf(sb, "freezer.enabled=%d\n", cfg.freezer_enabled);
	sb_printf(sb, "freezer.policy=%s\n", policy_on ? "on" : "off");
	sb_printf(sb, "freezer.owner=%llu\n", (unsigned long long)owner);
	sb_printf(sb, "freezer.locked=%d\n", locked);
	sb_printf(sb, "freezer.freezes=%llu\nfreezer.thaws=%llu\n", (unsigned long long)n_freezes,
		  (unsigned long long)n_thaws);
	for (int i = 0; i < nfg; i++)
		sb_printf(sb, "foreground=%s\n", fg[i]);
	for (int i = 0; i < MAX_APPS; i++) {
		const struct app *a = &apps[i];
		if (!a->used)
			continue;
		if (a->frozen)
			sb_printf(sb, "app=%s frozen\n", a->name);
		else if (a->bg_since)
			sb_printf(sb, "app=%s grace %lldms\n", a->name,
				  (long long)((now - a->bg_since) / 1000000));
		else
			sb_printf(sb, "app=%s running\n", a->name);
	}
	for (int i = 0; i < MAX_INHIBITS; i++)
		if (inhibits[i].used)
			sb_printf(sb, "inhibit=%u client=%llu app=%s reason=%s\n",
				  inhibits[i].token, (unsigned long long)inhibits[i].client,
				  inhibits[i].name, inhibits[i].reason);
}
