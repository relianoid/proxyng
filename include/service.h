/*
 * Copyright (C) RELIANOID <devel@relianoid.com>
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

#ifndef _ZPROXY_SERVICE_H_
#define _ZPROXY_SERVICE_H_

#include "config.h"
#include "http_request.h"
#include "state.h"
#include <sys/socket.h>
#include <string>

struct zproxy_cfg;

int zproxy_service_state_init(struct zproxy_cfg *cfg);
int zproxy_service_state_refresh(struct zproxy_cfg *cfg);
void zproxy_service_state_fini(void);

const struct zproxy_backend_cfg *
zproxy_service_schedule(const struct zproxy_service_cfg *service_config,
			struct zproxy_http_state *http_state);

struct zproxy_backend_cfg *
zproxy_service_backend_session(struct zproxy_service_cfg *service_config,
			       const struct sockaddr_in *bck_addr,
			       struct zproxy_http_state *http_state);

bool zproxy_service_select(const HttpRequest *request,
			   const struct zproxy_service_cfg *service_config);

struct zproxy_backend_cfg *
zproxy_service_select_backend(struct zproxy_service_cfg *service_config,
			      HttpRequest &request, const char *client_addr,
			      struct zproxy_sessions *sessions,
			      struct zproxy_http_state *http_state);

#endif
