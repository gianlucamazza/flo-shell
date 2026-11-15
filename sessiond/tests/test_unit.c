/* Unit tests for the pure helpers. SPDX-License-Identifier: MIT */
#include "../src/common.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int failures, checks;

#define CHECK(c) \
	do { \
		checks++; \
		if (!(c)) { \
			fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); \
			failures++; \
		} \
	} while (0)

static bool id_is(const char *unit, const char *want)
{
	char id[NAME_LEN];
	if (!unit_desktop_id(unit, id, sizeof id))
		return want == NULL;
	return want && strcmp(id, want) == 0;
}

static void test_paths(void)
{
	CHECK(rel_path_valid("app-org.foo.A-1.scope"));
	CHECK(rel_path_valid("app-a.slice/app-a-1.scope"));
	CHECK(rel_path_valid("app-wvkbd\\x2dmobintl-7.scope"));
	CHECK(rel_path_valid("a/b/c/d"));
	CHECK(rel_path_valid("..."));
	CHECK(rel_path_valid(".hidden"));
	CHECK(!rel_path_valid(""));
	CHECK(!rel_path_valid("/"));
	CHECK(!rel_path_valid("/abs"));
	CHECK(!rel_path_valid("."));
	CHECK(!rel_path_valid(".."));
	CHECK(!rel_path_valid("../x"));
	CHECK(!rel_path_valid("a/.."));
	CHECK(!rel_path_valid("a/../b"));
	CHECK(!rel_path_valid("a/./b"));
	CHECK(!rel_path_valid("a//b"));
	CHECK(!rel_path_valid("a/"));
	CHECK(!rel_path_valid("a b"));
	CHECK(!rel_path_valid("a\tb"));
	CHECK(!rel_path_valid("a\x7f"));
	CHECK(!rel_path_valid("caf\xc3\xa9"));
	CHECK(!rel_path_valid("a/b/c/d/e"));
	char longname[400];
	memset(longname, 'a', sizeof longname);
	longname[255] = '\0';
	CHECK(rel_path_valid(longname));
	longname[255] = 'a';
	longname[256] = '\0';
	CHECK(!rel_path_valid(longname));

	char first[NAME_LEN];
	rel_path_first("app-a.slice/app-a-1.scope", first);
	CHECK(!strcmp(first, "app-a.slice"));
	rel_path_first("single", first);
	CHECK(!strcmp(first, "single"));
}

static void test_desktop_id(void)
{
	CHECK(id_is("app-org.gnome.Calculator-12345.scope", "org.gnome.Calculator"));
	CHECK(id_is("app-firefox-a1b2c3.scope", "firefox"));
	CHECK(id_is("app-gnome-org.gnome.Maps-99.scope", "gnome-org.gnome.Maps"));
	CHECK(id_is("app-org.foo.Bar@1.service", "org.foo.Bar"));
	CHECK(id_is("app-org.foo.Bar.service", "org.foo.Bar"));
	CHECK(id_is("app-org.foo.Bar.slice", "org.foo.Bar"));
	CHECK(id_is("app-wvkbd\\x2dmobintl-7.scope", "wvkbd-mobintl"));
	CHECK(id_is("app-a\\x2", "a\\x2") || id_is("app-a\\x2", NULL));
	CHECK(id_is("app-a\\xzz-1.scope", "a\\xzz"));
	CHECK(id_is("app-a\\x00b-1.scope", "a\\x00b")); /* NUL is never decoded */
	CHECK(id_is("app-solo.scope", "solo"));
	CHECK(id_is("pipewire.service", NULL));
	CHECK(id_is("app-.scope", NULL));
	CHECK(id_is("app-x.mount", NULL));
	CHECK(id_is("app-noext", NULL));
	CHECK(id_is("app--1.scope", NULL));
	char tiny[4];
	CHECK(!unit_desktop_id("app-toolong-1.scope", tiny, sizeof tiny));
}

static void test_numbers(void)
{
	long v = -1;
	CHECK(parse_long("0", 0, 10, &v) && v == 0);
	CHECK(parse_long("1026000", 1, 100000000, &v) && v == 1026000);
	CHECK(!parse_long("", 0, 10, &v));
	CHECK(!parse_long("-1", -5, 10, &v));
	CHECK(!parse_long("+1", 0, 10, &v));
	CHECK(!parse_long(" 1", 0, 10, &v));
	CHECK(!parse_long("1 ", 0, 10, &v));
	CHECK(!parse_long("0x10", 0, 100, &v));
	CHECK(!parse_long("11", 0, 10, &v));
	CHECK(!parse_long("99999999999", 0, 2147483647L, &v));
	CHECK(parse_long("2147483647", 0, 2147483647L, &v) && v == 2147483647L);

	CHECK(pct_parse("0") == 0);
	CHECK(pct_parse("0.00") == 0);
	CHECK(pct_parse("68") == 6800);
	CHECK(pct_parse("68.5") == 6850);
	CHECK(pct_parse("68.05") == 6805);
	CHECK(pct_parse("100.00") == 10000);
	CHECK(pct_parse("max") == 10000);
	CHECK(pct_parse("100.01") == -1);
	CHECK(pct_parse("1000") == -1);
	CHECK(pct_parse("") == -1);
	CHECK(pct_parse(".5") == -1);
	CHECK(pct_parse("5.") == -1);
	CHECK(pct_parse("5.123") == -1);
	CHECK(pct_parse("-5") == -1);
	CHECK(pct_parse("5%") == -1);
	CHECK(freq_value_sane("384000"));
	CHECK(!freq_value_sane("384000 kHz"));
	CHECK(!freq_value_sane("<unsupported>"));
}

static void test_globs(void)
{
	struct globlist g;
	CHECK(globlist_set(&g, "  app-*.scope\tapp-*.service , x? "));
	CHECK(g.n == 3);
	CHECK(globlist_match(&g, "app-foo-1.scope"));
	CHECK(globlist_match(&g, "app-foo@1.service"));
	CHECK(globlist_match(&g, "xy"));
	CHECK(!globlist_match(&g, "pipewire.service"));
	CHECK(!globlist_match(&g, "xyz"));
	CHECK(globlist_set(&g, ""));
	CHECK(g.n == 0 && !globlist_match(&g, "anything"));
	char many[600] = "";
	for (int i = 0; i < MAX_GLOBS + 1; i++)
		strcat(many, "p ");
	CHECK(!globlist_set(&g, many)); /* too many patterns */
	memset(many, 'a', sizeof many - 1);
	many[sizeof many - 1] = '\0';
	CHECK(!globlist_set(&g, many)); /* too long */
}

static void test_config(void)
{
	struct config c;
	char err[256];
	config_defaults(&c);
	CHECK(config_validate(&c, err, sizeof err) == 0);
	CHECK(c.boost_freq_khz == 1026000 && c.boost_hold_ms == 150);
	CHECK(c.freezer_grace_ms == 10000 && c.socket_mode == 0660);
	CHECK(!strcmp(c.socket_path, "/run/flo-sessiond.sock"));
	/* The defaults protect the session's own pieces. */
	static const char *const never[] = { "flo-shell", "quickshell", "hyprland", "Hyprland",
		"xdg-desktop-portal", "xdg-desktop-portal-gtk", "pipewire", "pipewire-pulse",
		"wireplumber", "wvkbd-mobintl", "squeekboard", "org.example.keyboard",
		"dbus-:1.2-org.a.b", "polkit-agent" };
	for (size_t i = 0; i < sizeof never / sizeof never[0]; i++)
		CHECK(globlist_match(&c.freezer_deny, never[i]));
	CHECK(!globlist_match(&c.freezer_deny, "org.mozilla.firefox"));

	CHECK(config_set(&c, "boost_hold_ms", "80", err, sizeof err) == 0 && c.boost_hold_ms == 80);
	CHECK(config_set(&c, "boost_hold_ms", "5", err, sizeof err) < 0);
	CHECK(config_set(&c, "boost_hold_ms", "80ms", err, sizeof err) < 0);
	CHECK(config_set(&c, "boost_mode", "both", err, sizeof err) == 0 && c.boost_mode == 3);
	CHECK(config_validate(&c, err, sizeof err) < 0); /* uclamp needs a cgroup */
	CHECK(config_set(&c, "uclamp_cgroup", "/sys/fs/cgroup/user.slice", err, sizeof err) == 0);
	CHECK(config_validate(&c, err, sizeof err) == 0);
	CHECK(config_set(&c, "boost_mode", "turbo", err, sizeof err) < 0);
	CHECK(config_set(&c, "socket_mode", "0600", err, sizeof err) == 0 && c.socket_mode == 0600);
	CHECK(config_set(&c, "socket_mode", "888", err, sizeof err) < 0);
	CHECK(config_set(&c, "socket_mode", "rw", err, sizeof err) < 0);
	CHECK(config_set(&c, "uclamp_min", "101", err, sizeof err) < 0);
	CHECK(config_set(&c, "freezer_enabled", "maybe", err, sizeof err) < 0);
	CHECK(config_set(&c, "nonsense", "1", err, sizeof err) < 0 && strstr(err, "unknown key"));
	CHECK(config_set(&c, "freezer_root", "relative", err, sizeof err) == 0);
	CHECK(config_validate(&c, err, sizeof err) < 0);
	CHECK(config_set(&c, "freezer_root", "/a/../b", err, sizeof err) == 0);
	CHECK(config_validate(&c, err, sizeof err) < 0);
	CHECK(config_set(&c, "freezer_root", "/sys/fs/cgroup/x", err, sizeof err) == 0);
	CHECK(config_set(&c, "freezer_match", "", err, sizeof err) == 0);
	CHECK(config_validate(&c, err, sizeof err) < 0);

	const char *tmp = getenv("TMPDIR");
	char buf[512];
	snprintf(buf, sizeof buf, "%s/flo-unit-XXXXXX", tmp && *tmp ? tmp : "/tmp");
	int fd = mkstemp(buf);
	CHECK(fd >= 0);
	if (fd < 0)
		return;
	const char *text = "# comment\n\n  boost_hold_ms = 90  \nfreezer_deny = a* b*\n"
			   "input_name=Some Touch Panel\nsocket_group =\n";
	CHECK(write(fd, text, strlen(text)) == (ssize_t)strlen(text));
	config_defaults(&c);
	CHECK(config_load(&c, buf, err, sizeof err) == 0);
	CHECK(c.boost_hold_ms == 90 && c.freezer_deny.n == 2);
	CHECK(!strcmp(c.input_name, "Some Touch Panel") && c.socket_group[0] == '\0');
	text = "this line has no equals sign\n";
	CHECK(write(fd, text, strlen(text)) == (ssize_t)strlen(text));
	CHECK(config_load(&c, buf, err, sizeof err) < 0 && strstr(err, ":7:"));
	close(fd);
	unlink(buf);
	CHECK(config_load(&c, "/nonexistent/flo.conf", err, sizeof err) < 0);
}

static void test_sbuf(void)
{
	char buf[16];
	struct sbuf sb = { buf, 0, sizeof buf, false };
	sb_printf(&sb, "%s", "0123456789");
	CHECK(sb.len == 10 && !sb.truncated);
	sb_printf(&sb, "%s", "abcdefgh"); /* does not fit: dropped whole */
	CHECK(sb.len == 10 && sb.truncated && !strcmp(buf, "0123456789"));
	sb_printf(&sb, "%s", "abcde");
	CHECK(sb.len == 15 && !strcmp(buf, "0123456789abcde"));
}

int main(void)
{
	test_paths();
	test_desktop_id();
	test_numbers();
	test_globs();
	test_config();
	test_sbuf();
	printf("%d checks, %d failed\n", checks, failures);
	return failures ? 1 : 0;
}
