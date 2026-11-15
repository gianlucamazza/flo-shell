/* flo-sessiond: key=value configuration. SPDX-License-Identifier: MIT */
#include "common.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>

#define DEFAULT_DENY \
	"flo-shell* quickshell* *Hyprland* hyprland* *portal* pipewire* wireplumber* " \
	"*keyboard* wvkbd* squeekboard* dbus* *polkit* *keyring* xdg-*"

void config_defaults(struct config *c)
{
	memset(c, 0, sizeof *c);
	strcpy(c->socket_path, FLO_DEFAULT_SOCKET);
	strcpy(c->socket_group, "flo-session");
	c->socket_mode = 0660;
	strcpy(c->state_file, "/run/flo-sessiond/state");
	c->log_level = LOG_INFO;

	c->boost_enabled = true;
	c->boost_mode = BOOST_MODE_FREQ;
	c->boost_freq_khz = 1026000;
	c->boost_hold_ms = 150;
	c->boost_request_max_ms = 3000;
	strcpy(c->cpufreq_root, "/sys/devices/system/cpu/cpufreq");
	strcpy(c->uclamp_min, "68");
	strcpy(c->input_device, "auto");
	strcpy(c->input_dir, "/dev/input");
	strcpy(c->input_name, "Elan Touchscreen");
	c->input_timestamps = INPUT_TS_AUTO;

	c->freezer_enabled = true;
	strcpy(c->freezer_root,
	       "/sys/fs/cgroup/user.slice/user-10000.slice/user@10000.service/app.slice");
	c->freezer_grace_ms = 10000;
	globlist_set(&c->freezer_match, "app-*.scope app-*.service");
	globlist_set(&c->freezer_allow, "");
	globlist_set(&c->freezer_deny, DEFAULT_DENY);
}

static int fail(char *err, size_t errlen, const char *key, const char *why)
{
	snprintf(err, errlen, "%s: %s", key, why);
	return -1;
}

static int set_str(char *dst, size_t size, const char *value)
{
	if (strlen(value) >= size)
		return -1;
	strcpy(dst, value);
	return 0;
}

static int set_bool(bool *dst, const char *value)
{
	if (!strcmp(value, "yes") || !strcmp(value, "true") || !strcmp(value, "1") ||
	    !strcmp(value, "on"))
		*dst = true;
	else if (!strcmp(value, "no") || !strcmp(value, "false") || !strcmp(value, "0") ||
		 !strcmp(value, "off"))
		*dst = false;
	else
		return -1;
	return 0;
}

static int set_int(int *dst, const char *value, long min, long max)
{
	long v;
	if (!parse_long(value, min, max, &v))
		return -1;
	*dst = (int)v;
	return 0;
}

int config_set(struct config *c, const char *key, const char *value, char *err, size_t errlen)
{
	int r = 0;
	long v;

	if (!strcmp(key, "socket_path"))
		r = set_str(c->socket_path, sizeof c->socket_path, value);
	else if (!strcmp(key, "socket_group"))
		r = set_str(c->socket_group, sizeof c->socket_group, value);
	else if (!strcmp(key, "socket_mode")) {
		unsigned m = 0;
		size_t len = strlen(value);
		if (len < 3 || len > 4)
			r = -1;
		for (size_t i = 0; i < len && !r; i++) {
			if (value[i] < '0' || value[i] > '7')
				r = -1;
			m = m * 8 + (unsigned)(value[i] - '0');
		}
		if (!r)
			c->socket_mode = m & 0777;
	} else if (!strcmp(key, "state_file"))
		r = set_str(c->state_file, sizeof c->state_file, value);
	else if (!strcmp(key, "log_level")) {
		if (!strcmp(value, "error"))
			c->log_level = LOG_ERR;
		else if (!strcmp(value, "warning"))
			c->log_level = LOG_WARNING;
		else if (!strcmp(value, "info"))
			c->log_level = LOG_INFO;
		else if (!strcmp(value, "debug"))
			c->log_level = LOG_DEBUG;
		else
			r = -1;
	} else if (!strcmp(key, "boost_enabled"))
		r = set_bool(&c->boost_enabled, value);
	else if (!strcmp(key, "boost_mode")) {
		if (!strcmp(value, "freq"))
			c->boost_mode = BOOST_MODE_FREQ;
		else if (!strcmp(value, "uclamp"))
			c->boost_mode = BOOST_MODE_UCLAMP;
		else if (!strcmp(value, "both"))
			c->boost_mode = BOOST_MODE_FREQ | BOOST_MODE_UCLAMP;
		else
			r = -1;
	} else if (!strcmp(key, "boost_freq_khz")) {
		if (parse_long(value, 1, 100000000L, &v))
			c->boost_freq_khz = v;
		else
			r = -1;
	} else if (!strcmp(key, "boost_hold_ms"))
		r = set_int(&c->boost_hold_ms, value, 10, 10000);
	else if (!strcmp(key, "boost_request_max_ms"))
		r = set_int(&c->boost_request_max_ms, value, 0, 60000);
	else if (!strcmp(key, "cpufreq_root"))
		r = set_str(c->cpufreq_root, sizeof c->cpufreq_root, value);
	else if (!strcmp(key, "uclamp_cgroup"))
		r = set_str(c->uclamp_cgroup, sizeof c->uclamp_cgroup, value);
	else if (!strcmp(key, "uclamp_min")) {
		if (pct_parse(value) < 0)
			r = -1;
		else
			r = set_str(c->uclamp_min, sizeof c->uclamp_min, value);
	} else if (!strcmp(key, "input_device"))
		r = set_str(c->input_device, sizeof c->input_device, value);
	else if (!strcmp(key, "input_dir"))
		r = set_str(c->input_dir, sizeof c->input_dir, value);
	else if (!strcmp(key, "input_name"))
		r = set_str(c->input_name, sizeof c->input_name, value);
	else if (!strcmp(key, "input_timestamps")) {
		if (!strcmp(value, "auto"))
			c->input_timestamps = INPUT_TS_AUTO;
		else if (!strcmp(value, "trust"))
			c->input_timestamps = INPUT_TS_TRUST;
		else if (!strcmp(value, "ignore"))
			c->input_timestamps = INPUT_TS_IGNORE;
		else
			r = -1;
	} else if (!strcmp(key, "freezer_enabled"))
		r = set_bool(&c->freezer_enabled, value);
	else if (!strcmp(key, "freezer_root"))
		r = set_str(c->freezer_root, sizeof c->freezer_root, value);
	else if (!strcmp(key, "freezer_grace_ms"))
		r = set_int(&c->freezer_grace_ms, value, 0, 3600000);
	else if (!strcmp(key, "freezer_match"))
		r = globlist_set(&c->freezer_match, value) ? 0 : -1;
	else if (!strcmp(key, "freezer_allow"))
		r = globlist_set(&c->freezer_allow, value) ? 0 : -1;
	else if (!strcmp(key, "freezer_deny"))
		r = globlist_set(&c->freezer_deny, value) ? 0 : -1;
	else
		return fail(err, errlen, key, "unknown key");

	if (r)
		return fail(err, errlen, key, "invalid value");
	return 0;
}

static char *trim(char *s)
{
	while (*s == ' ' || *s == '\t')
		s++;
	size_t n = strlen(s);
	while (n > 0 && (s[n - 1] == ' ' || s[n - 1] == '\t' || s[n - 1] == '\n' ||
			 s[n - 1] == '\r'))
		s[--n] = '\0';
	return s;
}

int config_load(struct config *c, const char *path, char *err, size_t errlen)
{
	FILE *f = fopen(path, "re");
	if (!f) {
		snprintf(err, errlen, "%s: %s", path, strerror(errno));
		return -1;
	}
	char line[1024], sub[256];
	int lineno = 0, rc = 0;
	while (fgets(line, sizeof line, f)) {
		lineno++;
		if (!strchr(line, '\n') && !feof(f)) {
			snprintf(err, errlen, "%s:%d: line too long", path, lineno);
			rc = -1;
			break;
		}
		char *s = trim(line);
		if (*s == '\0' || *s == '#')
			continue;
		char *eq = strchr(s, '=');
		if (!eq) {
			snprintf(err, errlen, "%s:%d: expected key=value", path, lineno);
			rc = -1;
			break;
		}
		*eq = '\0';
		if (config_set(c, trim(s), trim(eq + 1), sub, sizeof sub) < 0) {
			snprintf(err, errlen, "%s:%d: %s", path, lineno, sub);
			rc = -1;
			break;
		}
	}
	fclose(f);
	return rc;
}

static bool abs_path(const char *p)
{
	return p[0] == '/' && !strstr(p, "/../") && strcmp(p, "/") != 0;
}

int config_validate(const struct config *c, char *err, size_t errlen)
{
	if (!abs_path(c->socket_path))
		return fail(err, errlen, "socket_path", "must be an absolute path");
	if (c->state_file[0] && !abs_path(c->state_file))
		return fail(err, errlen, "state_file", "must be empty or an absolute path");
	if (!abs_path(c->cpufreq_root))
		return fail(err, errlen, "cpufreq_root", "must be an absolute path");
	if (!abs_path(c->freezer_root))
		return fail(err, errlen, "freezer_root", "must be an absolute path");
	if (!abs_path(c->input_dir))
		return fail(err, errlen, "input_dir", "must be an absolute path");
	if (strcmp(c->input_device, "auto") != 0 && !abs_path(c->input_device))
		return fail(err, errlen, "input_device", "must be \"auto\" or an absolute path");
	if (c->uclamp_cgroup[0] && !abs_path(c->uclamp_cgroup))
		return fail(err, errlen, "uclamp_cgroup", "must be empty or an absolute path");
	if ((c->boost_mode & BOOST_MODE_UCLAMP) && c->boost_enabled && !c->uclamp_cgroup[0])
		return fail(err, errlen, "uclamp_cgroup", "required by boost_mode");
	if (c->freezer_match.n == 0)
		return fail(err, errlen, "freezer_match", "must not be empty");
	return 0;
}

static void dump_globs(struct sbuf *sb, const char *key, const struct globlist *g)
{
	sb_printf(sb, "%s=", key);
	for (int i = 0; i < g->n; i++)
		sb_printf(sb, "%s%s", i ? " " : "", g->pat[i]);
	sb_printf(sb, "\n");
}

void config_dump(const struct config *c, struct sbuf *sb)
{
	static const char *const ts[] = { "auto", "trust", "ignore" };
	static const char *const mode[] = { "", "freq", "uclamp", "both" };
	sb_printf(sb, "socket_path=%s\nsocket_group=%s\nsocket_mode=%04o\nstate_file=%s\n",
		  c->socket_path, c->socket_group, c->socket_mode, c->state_file);
	sb_printf(sb, "log_level=%s\n",
		  c->log_level >= LOG_DEBUG ? "debug" :
		  c->log_level >= LOG_INFO ? "info" :
		  c->log_level >= LOG_WARNING ? "warning" : "error");
	sb_printf(sb, "boost_enabled=%s\nboost_mode=%s\nboost_freq_khz=%ld\nboost_hold_ms=%d\n",
		  c->boost_enabled ? "yes" : "no", mode[c->boost_mode & 3], c->boost_freq_khz,
		  c->boost_hold_ms);
	sb_printf(sb, "boost_request_max_ms=%d\ncpufreq_root=%s\nuclamp_cgroup=%s\nuclamp_min=%s\n",
		  c->boost_request_max_ms, c->cpufreq_root, c->uclamp_cgroup, c->uclamp_min);
	sb_printf(sb, "input_device=%s\ninput_dir=%s\ninput_name=%s\ninput_timestamps=%s\n",
		  c->input_device, c->input_dir, c->input_name, ts[c->input_timestamps]);
	sb_printf(sb, "freezer_enabled=%s\nfreezer_root=%s\nfreezer_grace_ms=%d\n",
		  c->freezer_enabled ? "yes" : "no", c->freezer_root, c->freezer_grace_ms);
	dump_globs(sb, "freezer_match", &c->freezer_match);
	dump_globs(sb, "freezer_allow", &c->freezer_allow);
	dump_globs(sb, "freezer_deny", &c->freezer_deny);
}
