/*
 * Copyright (C) 2023  Zevenet S.L. <support@zevenet.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef _ZPROXY_STATE_H_
#define _ZPROXY_STATE_H_

#include "config.h"
#include "list.h"
#include "session.h"
#include "zcu_log.h"
#include <sys/time.h>
#include <ev.h>
// when switching to C use the second include
#include <atomic>
//#include <stdatomic.h>

#define TIMEOUT_SESSIONS 1
#define COUNTER_SESSIONS 10000

struct zproxy_backend_state;
struct zproxy_service_state;

struct zproxy_stats {
	/// Total number of 2xx responses since initialization.
	std::atomic_int http_2xx_hits;
	/// Total number of 3xx responses since initialization.
	std::atomic_int http_3xx_hits;
	/// Total number of 4xx responses since initialization.
	std::atomic_int http_4xx_hits;
	/// Total number of 5xx responses since initialization.
	std::atomic_int http_5xx_hits;
	/// Total number of waf responses since initialization.
	std::atomic_int http_waf_hits;
	/// Number of connections established at the moment.
	std::atomic_int conn_established;
	/// Number of connections pending at the moment.
	std::atomic_int conn_pending;
};

struct zproxy_http_state {
	struct list_head       list;
	uint32_t	proxy_id;
	uint32_t	refcnt;
	struct ev_timer			timer;
	struct zproxy_stats listener_stats;
	struct list_head       services;
};

/**
 * Dump the numbers from stats to the log.
 *
 * @param stats Statistics associated with a given connection.
 */
inline void zproxy_stats_dump(const struct zproxy_stats *stats)
{
	zcu_log_print(LOG_INFO,
			"HTTP 2XX hits: %u; "
			"HTTP 3XX hits: %u; "
			"HTTP 4XX hits: %u; "
			"HTTP 5XX hits: %u; "
			"HTTP WAF hits: %u; "
			"Connections established: %u; "
			"Connections pending: %u; ",
			stats->http_2xx_hits.load(),
			stats->http_3xx_hits.load(),
			stats->http_4xx_hits.load(),
			stats->http_5xx_hits.load(),
			stats->http_waf_hits.load(),
			stats->conn_established.load(),
			stats->conn_pending.load());
}

struct zproxy_stats *
zproxy_stats_backend_get(const struct zproxy_http_state *http_state,
			 const struct zproxy_backend_cfg *backend_cfg);
int zproxy_state_backend_add(const struct zproxy_http_state *http_state,
			      const struct zproxy_backend_cfg *backend);
/**
 * Increment the backend stat for a given HTTP code.
 *
 * @param http_state HTTP state object that contains the backend stats.
 * @param backend_cfg Configuration for the backend.
 * @param code The HTTP code to increment.
 *
 * @return If the HTTP code is valid it will return 1. Return is -1 the HTTP
 * code is invalid.
 */
int zproxy_stats_backend_inc_code(const struct zproxy_http_state *http_state,
				  const struct zproxy_backend_cfg *backend_cfg,
				  const int code);
/**
 * Increment the connections established statistics for a given backend.
 *
 * @param http_state State object for the target listener.
 * @param backend_cfg Configuration of the the backend to increment for.
 */
void zproxy_stats_backend_inc_conn_established(const struct zproxy_http_state *http_state,
					       const struct zproxy_backend_cfg *backend_cfg);
/**
 * Decrement the connections established statistics for a given backend.
 *
 * @param http_state State object for the target listener.
 * @param backend_cfg Configuration of the the backend to increment for.
 */
void zproxy_stats_backend_dec_conn_established(const struct zproxy_http_state *http_state,
					       const struct zproxy_backend_cfg *backend_cfg);
/**
 * Increment the connections pending statistics for a given backend.
 *
 * @param http_state State object for the target listener.
 * @param backend_cfg Configuration of the the backend to increment for.
 */
int zproxy_stats_backend_inc_conn_pending(const struct zproxy_http_state *http_state,
					  const struct zproxy_backend_cfg *backend_cfg);
/**
 * Decrement the connections pending statistics for a given backend.
 *
 * @param http_state State object for the target listener.
 * @param backend_cfg Configuration of the the backend to increment for.
 */
int zproxy_stats_backend_dec_conn_pending(const struct zproxy_http_state *http_state,
					  const struct zproxy_backend_cfg *backend_cfg);
int zproxy_stats_backend_get_pending(const struct zproxy_http_state *http_state,
				     const struct zproxy_backend_cfg *backend_cfg);
int zproxy_stats_backend_get_established(const struct zproxy_http_state *http_state,
					 const struct zproxy_backend_cfg *backend_cfg);

struct zproxy_sessions *
zproxy_state_get_service_sessions(const char *service,
				  const struct list_head *service_list);

/**
 * Increment the listener stat for a given HTTP code.
 *
 * @param http_state HTTP state object that contains the listener stats.
 * @param code The HTTP code to increment.
 *
 * @return If the HTTP code is valid it will return 1. Return is -1 the HTTP
 * code is invalid.
 */
inline int zproxy_stats_listener_inc_code(struct zproxy_http_state *http_state,
					  const int code)
{
	if(code >= 500)
		http_state->listener_stats.http_5xx_hits++;
	else if(code >= 400)
		http_state->listener_stats.http_4xx_hits++;
	else if(code >= 300)
		http_state->listener_stats.http_3xx_hits++;
	else if(code >= 200)
		http_state->listener_stats.http_2xx_hits++;
	else
		return -1;
	return 1;
}
/**
 * Increment the listener stat for WAF hits.
 *
 * @param http_state HTTP state object that contains the listener stats.
 */
inline void zproxy_stats_listener_inc_waf(struct zproxy_http_state *http_state)
{
	http_state->listener_stats.http_waf_hits++;
}
inline void zproxy_stats_listener_inc_conn_established(struct zproxy_http_state *http_state)
{
	http_state->listener_stats.conn_established++;
}
inline void zproxy_stats_listener_dec_conn_established(struct zproxy_http_state *http_state)
{
	http_state->listener_stats.conn_established--;
}
inline void zproxy_stats_listener_inc_conn_pending(struct zproxy_http_state *http_state)
{
	http_state->listener_stats.conn_pending++;
}
inline void zproxy_stats_listener_dec_conn_pending(struct zproxy_http_state *http_state)
{
	http_state->listener_stats.conn_pending--;
}
struct zproxy_http_state *
zproxy_state_init(const struct zproxy_proxy_cfg *proxy);
void zproxy_state_purge(uint32_t proxy_id);
struct zproxy_http_state *zproxy_state_lookup(uint32_t proxy_id);
struct zproxy_http_state *
zproxy_state_getref(struct zproxy_http_state *http_state);
void zproxy_state_free(struct zproxy_http_state **http_state);
void zproxy_states_lock(void);
void zproxy_states_unlock(void);
void zproxy_state_cfg_update(struct zproxy_cfg *cfg);

#endif
