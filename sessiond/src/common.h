/* flo-sessiond: shared definitions. SPDX-License-Identifier: MIT */
#ifndef FLO_COMMON_H
#define FLO_COMMON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#define FLO_VERSION "0.1.0"
#define FLO_PROTOCOL 1
#define FLO_DEFAULT_CONFIG "/etc/flo-sessiond.conf"
#define FLO_DEFAULT_SOCKET "/run/flo-sessiond.sock"

/* Every table in the daemon is statically sized: no unbounded allocation. */
#define MAX_LINE 512     /* longest accepted protocol line, newline included */
#define MAX_CLIENTS 16
#define MAX_KNOBS 33     /* 32 cpufreq policies + one uclamp cgroup */
#define MAX_APPS 64
#define MAX_FG 4
#define MAX_INHIBITS 32
#define MAX_INHIBITS_PER_CLIENT 8
#define MAX_GLOBS 32
#define NAME_LEN 256     /* NAME_MAX + 1 */
#define PATH_LEN 384
#define REASON_LEN 64
#define VALUE_LEN 24

#define LOG_ERR 3
#define LOG_WARNING 4
#define LOG_INFO 6
#define LOG_DEBUG 7

#define BOOST_MODE_FREQ 1
#define BOOST_MODE_UCLAMP 2

enum input_ts { INPUT_TS_AUTO, INPUT_TS_TRUST, INPUT_TS_IGNORE };

struct globlist {
	char store[512];
	const char *pat[MAX_GLOBS];
	int n;
};

struct config {
	char socket_path[PATH_LEN];
	char socket_group[64];
	unsigned socket_mode;
	char state_file[PATH_LEN];
	int log_level;

	bool boost_enabled;
	int boost_mode;
	long boost_freq_khz;
	int boost_hold_ms;
	int boost_request_max_ms;
	char cpufreq_root[PATH_LEN];
	char uclamp_cgroup[PATH_LEN];
	char uclamp_min[VALUE_LEN];
	char input_device[PATH_LEN];
	char input_dir[PATH_LEN];
	char input_name[128];
	enum input_ts input_timestamps;

	bool freezer_enabled;
	char freezer_root[PATH_LEN];
	int freezer_grace_ms;
	struct globlist freezer_match;
	struct globlist freezer_allow;
	struct globlist freezer_deny;
};

/* util.c */
extern int log_level;
void log_msg(int prio, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
int64_t now_ns(void);
ssize_t read_small_at(int dirfd, const char *path, char *buf, size_t size);
int write_small_at(int dirfd, const char *path, const char *val);
bool parse_long(const char *s, long min, long max, long *out);
int pct_parse(const char *s);
bool freq_value_sane(const char *s);
bool globlist_set(struct globlist *g, const char *value);
bool globlist_match(const struct globlist *g, const char *s);
bool rel_path_valid(const char *p);
void rel_path_first(const char *p, char out[NAME_LEN]);
bool unit_desktop_id(const char *unit, char *out, size_t size);

struct sbuf {
	char *buf;
	size_t len, cap;
	bool truncated;
};
void sb_printf(struct sbuf *sb, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

/* config.c */
void config_defaults(struct config *c);
int config_set(struct config *c, const char *key, const char *value, char *err, size_t errlen);
int config_load(struct config *c, const char *path, char *err, size_t errlen);
int config_validate(const struct config *c, char *err, size_t errlen);
void config_dump(const struct config *c, struct sbuf *sb);

#endif
