/* flo-sessiond: daemon-internal interfaces. SPDX-License-Identifier: MIT */
#ifndef FLO_SESSIOND_H
#define FLO_SESSIOND_H

#include "common.h"

enum ep_tag {
	TAG_SIGNAL = 1,
	TAG_LISTEN,
	TAG_INPUT,
	TAG_INPUT_INOTIFY,
	TAG_BOOST_TIMER,
	TAG_RETRY_TIMER,
	TAG_FREEZE_TIMER,
	TAG_FREEZE_INOTIFY,
	TAG_CLIENT,
};

/* main.c */
extern struct config cfg;
extern uint64_t loop_wakeups;
int ep_add(int fd, uint32_t events, enum ep_tag tag, uint64_t id);
int ep_mod(int fd, uint32_t events, enum ep_tag tag, uint64_t id);
void ep_del(int fd);
int timer_new(enum ep_tag tag);
void timer_arm(int tfd, int64_t deadline_ns);
void timer_disarm(int tfd);
void timer_ack(int tfd);
void inotify_drain(int fd);

/* boost.c */
int boost_init(void);
void boost_shutdown(void);
void boost_emergency(void);
void boost_on_input(uint32_t events, uint64_t gen);
void boost_on_input_inotify(void);
void boost_on_timer(void);
void boost_on_retry(void);
int boost_request(int ms);
void boost_status(struct sbuf *sb);

/* freezer.c */
int freezer_init(void);
void freezer_shutdown(void);
void freezer_emergency(void);
void freezer_on_timer(void);
void freezer_on_inotify(void);
void freezer_client_gone(uint64_t client);
/* All return 0 or a negative errno-style code mapped by server.c. */
int freezer_set_policy(uint64_t client, bool on);
int freezer_set_foreground(uint64_t client, const char *const *paths, int n);
int freezer_set_locked(uint64_t client, bool locked);
int freezer_inhibit(uint64_t client, const char *path, const char *reason, unsigned *token);
int freezer_uninhibit(uint64_t client, unsigned token);
int freezer_thaw(const char *path);
int freezer_thaw_all(void);
bool freezer_client_has_state(uint64_t client);
void freezer_status(struct sbuf *sb);

/* server.c */
int server_init(void);
void server_shutdown(void);
void server_on_listen(void);
void server_on_client(uint64_t id, uint32_t events);

#endif
