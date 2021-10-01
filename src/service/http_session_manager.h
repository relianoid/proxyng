/*
 *    Zevenet zproxy Load Balancer Software License
 *    This file is part of the Zevenet zproxy Load Balancer software package.
 *
 *    Copyright (C) 2019-today ZEVENET SL, Sevilla (Spain)
 *
 *    This program is free software: you can redistribute it and/or modify
 *    it under the terms of the GNU Affero General Public License as
 *    published by the Free Software Foundation, either version 3 of the
 *    License, or any later version.
 *
 *    This program is distributed in the hope that it will be useful,
 *    but WITHOUT ANY WARRANTY; without even the implied warranty of
 *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *    GNU Affero General Public License for more details.
 *
 *    You should have received a copy of the GNU Affero General Public License
 *    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */
#pragma once
#include <string>
#include <unordered_map>
#include "../http/http_request.h"
#include "../json/json_data_value.h"
#include "backend.h"

namespace sessions
{
struct Data {
	std::string key;
	std::string backend_ip;
	int backend_port;
	time_t last_seen;
};

struct DataSet {
	int listener_id;
	std::string service_name;
	SESS_TYPE type{ SESS_TYPE::SESS_NONE };
	std::vector<Data> session_list;
	DataSet *next{ nullptr };
	DataSet(int listener, std::string service, SESS_TYPE s_type)
	{
		listener_id = listener;
		service_name = service;
		type = s_type;
	}
	~DataSet()
	{
		session_list.clear();
	}
};

struct SessionInfo {
	SessionInfo() : assigned_backend(nullptr)
	{
		last_seen = Time::getTimeSec();
	}

	// last_seen is used to calculate if the session has expired.
	// If it has the value 0 means that the session does not expired, it is permanent
	time_t last_seen;
	Backend *assigned_backend{ nullptr };

	bool isStatic()
	{
		return last_seen == 0 ? true : false;
	}

	bool hasExpired(unsigned int ttl)
	{
		// check if has not reached ttl
		if (this->isStatic())
			return false;
		return Time::getTimeSec() - last_seen > ttl;
	}
	void update()
	{
		if (!this->isStatic())
			last_seen = Time::getTimeSec();
	}
	long getTimeStamp()
	{
		return last_seen;
	}
	void setTimeStamp(long seconds_since_epoch_count)
	{
		std::chrono::seconds dur(seconds_since_epoch_count);
		std::chrono::time_point<std::chrono::system_clock> dt(dur);
		last_seen = dt.time_since_epoch().count();
	}
};

class HttpSessionManager {
	std::recursive_mutex lock_mtx;

    public:
	std::unordered_map<std::string, SessionInfo *>
		sessions_set; // key can be anything, depending on the session type
	SESS_TYPE session_type;
	std::string sess_id; /* id to construct the pattern */
	regex_t sess_start{}; /* pattern to identify the session data */
	regex_t sess_pat{}; /* pattern to match the session data */
	unsigned int ttl{};

	HttpSessionManager();
	virtual ~HttpSessionManager();

	bool addSession(std::string key, long last_seen, Backend *bck_ptr,
			bool copy_lastseen = false);
	bool addSession(std::string key, int backend_id, long last_seen,
			std::vector<Backend *> backend_set);
	bool addSession(JsonObject *json_object,
			std::vector<Backend *> backend_set);
	SessionInfo *addSession(Connection &source, HttpRequest &request,
				Backend &backend_to_assign);
	bool updateSession(Connection &source, HttpRequest &request,
			   const std::string &new_session_id,
			   Backend &backend_to_assign);
	bool deleteSessionByKey(const std::string &key);
	bool deleteSession(const JsonObject &json_object);
	void deleteSession(Connection &source, HttpRequest &request);
	// return the assigned backend or nullptr if no session is found or sesssion
	// has expired
	SessionInfo *getSession(Connection &source, HttpRequest &request,
				bool update_if_exist = false);
	std::unique_ptr<json::JsonArray> getSessionsJson();
	void deleteBackendSessions(int backend_id);
	void flushSessions();
	void doMaintenance();

    private:
	static std::string getQueryParameter(const std::string &url,
					     const std::string &sess_id);
	static std::string getCookieValue(std::string_view cookie_header_value,
					  std::string_view sess_id);
	static std::string getUrlParameter(const std::string &url);
	std::string getSessionKey(Connection &source, HttpRequest &request);
};
} // namespace sessions
