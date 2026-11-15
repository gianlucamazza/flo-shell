/* flo-sessiond: small helpers. SPDX-License-Identifier: MIT */
#include "common.h"

#include <errno.h>
#include <fcntl.h>
#include <fnmatch.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int log_level = LOG_INFO;

/* One write(2) per message, with the "<N>" prefix the journal understands. */
void log_msg(int prio, const char *fmt, ...)
{
	if (prio > log_level)
		return;
	char buf[640];
	int off = snprintf(buf, sizeof buf, "<%d>", prio);
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(buf + off, sizeof buf - (size_t)off - 1, fmt, ap);
	va_end(ap);
	if (n < 0)
		return;
	size_t len = (size_t)off + (size_t)n;
	if (len > sizeof buf - 2)
		len = sizeof buf - 2;
	buf[len++] = '\n';
	ssize_t r = write(STDERR_FILENO, buf, len);
	(void)r;
}

int64_t now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

/*
 * Read a short attribute file. Trailing whitespace is stripped.
 * Returns the length (>= 0) or -errno. The path must not be a symlink.
 */
ssize_t read_small_at(int dirfd, const char *path, char *buf, size_t size)
{
	int fd = openat(dirfd, path, O_RDONLY | O_CLOEXEC | O_NOCTTY | O_NOFOLLOW | O_NONBLOCK);
	if (fd < 0)
		return -errno;
	ssize_t n;
	do {
		n = read(fd, buf, size - 1);
	} while (n < 0 && errno == EINTR);
	int e = errno;
	close(fd);
	if (n < 0)
		return -e;
	while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == ' ' || buf[n - 1] == '\r'))
		n--;
	buf[n] = '\0';
	return n;
}

/*
 * Write a short value to an existing attribute file (never creates one, never
 * follows a symlink in the last component). Returns 0 or -errno.
 * Async-signal-safe: only open/write/close, so the crash handler can use it.
 */
int write_small_at(int dirfd, const char *path, const char *val)
{
	int fd = openat(dirfd, path,
			O_WRONLY | O_TRUNC | O_CLOEXEC | O_NOCTTY | O_NOFOLLOW | O_NONBLOCK);
	if (fd < 0)
		return -errno;
	size_t len = 0;
	while (val[len])
		len++;
	ssize_t n;
	do {
		n = write(fd, val, len);
	} while (n < 0 && errno == EINTR);
	int e = errno;
	close(fd);
	if (n < 0)
		return -e;
	return (size_t)n == len ? 0 : -EIO;
}

/* Strict decimal parser: digits only, no sign, no whitespace, at most 10 digits. */
bool parse_long(const char *s, long min, long max, long *out)
{
	size_t len = strlen(s);
	if (len == 0 || len > 10)
		return false;
	long long v = 0;
	for (size_t i = 0; i < len; i++) {
		if (s[i] < '0' || s[i] > '9')
			return false;
		v = v * 10 + (s[i] - '0');
	}
	if (v < min || v > max)
		return false;
	*out = (long)v;
	return true;
}

/*
 * Parse a cpu.uclamp value: "max" or a percentage with up to two decimals.
 * Returns hundredths of a percent (0..10000) or -1.
 */
int pct_parse(const char *s)
{
	if (strcmp(s, "max") == 0)
		return 10000;
	int whole = 0, frac = 0, nd = 0, nf = 0;
	const char *p = s;
	for (; *p >= '0' && *p <= '9'; p++, nd++) {
		if (nd >= 3)
			return -1;
		whole = whole * 10 + (*p - '0');
	}
	if (nd == 0)
		return -1;
	if (*p == '.') {
		for (p++; *p >= '0' && *p <= '9'; p++, nf++) {
			if (nf >= 2)
				return -1;
			frac = frac * 10 + (*p - '0');
		}
		if (nf == 0)
			return -1;
		if (nf == 1)
			frac *= 10;
	}
	if (*p != '\0')
		return -1;
	int v = whole * 100 + frac;
	return v > 10000 ? -1 : v;
}

bool freq_value_sane(const char *s)
{
	long v;
	return parse_long(s, 0, 100000000L, &v);
}

/* Whitespace-separated list of fnmatch(3) patterns. */
bool globlist_set(struct globlist *g, const char *value)
{
	if (strlen(value) >= sizeof g->store)
		return false;
	memset(g, 0, sizeof *g);
	strcpy(g->store, value);
	char *p = g->store;
	while (*p) {
		while (*p == ' ' || *p == '\t' || *p == ',')
			*p++ = '\0';
		if (!*p)
			break;
		if (g->n >= MAX_GLOBS)
			return false;
		g->pat[g->n++] = p;
		while (*p && *p != ' ' && *p != '\t' && *p != ',')
			p++;
	}
	return true;
}

bool globlist_match(const struct globlist *g, const char *s)
{
	for (int i = 0; i < g->n; i++)
		if (fnmatch(g->pat[i], s, 0) == 0)
			return true;
	return false;
}

/*
 * A client-supplied cgroup path: relative, printable ASCII without spaces,
 * no empty, "." or ".." component, at most 4 components of at most
 * NAME_LEN-1 bytes. This is only the syntactic gate: every access is then
 * done component by component with O_NOFOLLOW below the root directory fd.
 */
bool rel_path_valid(const char *p)
{
	size_t len = strlen(p);
	if (len == 0 || len >= NAME_LEN || p[0] == '/')
		return false;
	int comps = 0;
	const char *c = p;
	for (;;) {
		const char *end = strchr(c, '/');
		size_t n = end ? (size_t)(end - c) : strlen(c);
		if (n == 0)
			return false;
		if (n == 1 && c[0] == '.')
			return false;
		if (n == 2 && c[0] == '.' && c[1] == '.')
			return false;
		for (size_t i = 0; i < n; i++)
			if (c[i] < 0x21 || c[i] > 0x7e)
				return false;
		if (++comps > 4)
			return false;
		if (!end)
			break;
		c = end + 1;
	}
	return true;
}

/* First component of a validated relative path: the app unit it belongs to. */
void rel_path_first(const char *p, char out[NAME_LEN])
{
	size_t n = strcspn(p, "/");
	if (n >= NAME_LEN)
		n = NAME_LEN - 1;
	memcpy(out, p, n);
	out[n] = '\0';
}

static int hexval(char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

/*
 * Extract the desktop id from a systemd app unit name
 * (https://systemd.io/DESKTOP_ENVIRONMENTS/):
 *   app-<id>-<random>.scope, app-<id>@<instance>.service, app-<id>.service,
 *   app-<id>.slice
 * "\xHH" escapes are decoded. Returns false if the name is not an app unit.
 */
bool unit_desktop_id(const char *unit, char *out, size_t size)
{
	if (strncmp(unit, "app-", 4) != 0)
		return false;
	const char *body = unit + 4;
	const char *dot = strrchr(body, '.');
	if (!dot || dot == body)
		return false;
	size_t n = (size_t)(dot - body);
	if (strcmp(dot, ".scope") == 0) {
		for (size_t i = n; i > 0; i--)
			if (body[i - 1] == '-') {
				n = i - 1;
				break;
			}
	} else if (strcmp(dot, ".service") == 0) {
		for (size_t i = n; i > 0; i--)
			if (body[i - 1] == '@') {
				n = i - 1;
				break;
			}
	} else if (strcmp(dot, ".slice") != 0) {
		return false;
	}
	if (n == 0)
		return false;
	size_t o = 0;
	for (size_t i = 0; i < n; i++) {
		char ch = body[i];
		if (ch == '\\' && i + 3 < n && body[i + 1] == 'x') {
			int hi = i + 2 < n ? hexval(body[i + 2]) : -1;
			int lo = i + 3 < n ? hexval(body[i + 3]) : -1;
			if (hi >= 0 && lo >= 0 && (hi || lo)) {
				ch = (char)(hi * 16 + lo);
				i += 3;
			}
		}
		if (o + 1 >= size)
			return false;
		out[o++] = ch;
	}
	out[o] = '\0';
	return true;
}

/* Append to a fixed buffer; a line that does not fit is dropped whole. */
void sb_printf(struct sbuf *sb, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	size_t room = sb->cap - sb->len;
	int n = vsnprintf(sb->buf + sb->len, room, fmt, ap);
	va_end(ap);
	if (n < 0 || (size_t)n >= room) {
		sb->buf[sb->len] = '\0';
		sb->truncated = true;
		return;
	}
	sb->len += (size_t)n;
}
