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

#include <string.h>
#include "zcu_log.h"
#include "proxy.h"
#include "http_parser.h"
#include "http_protocol.h"

http_parser::HttpData::HttpData()
{
	resetParser();
}

void http_parser::HttpData::resetParser()
{
	http_message_str = "";
	extra_headers.clear();
	permanent_extra_headers.clear();
	num_headers = 0;
	last_length = 0;
	minor_version = -1;
	message_length = 0;
	message_bytes_left = 0;
	message_total_bytes = 0;
	content_length = 0;
	message_undefined = false;
	headers_sent = false;
	header_length_new = 0;
	partial_last_chunk = 0;
	chunked_status = CHUNKED_STATUS::CHUNKED_DISABLED;
	extra_headers.clear();
	http_message_str.clear();
	connection_close_pending = false;
	connection_keep_alive = false;
	connection_header_upgrade = false;
	upgrade_header = false;
	x_forwarded_for_header = "";
}

void http_parser::HttpData::setBuffer(char *ext_buffer, size_t ext_buffer_size)
{
	buffer = ext_buffer;
	buffer_size = ext_buffer_size;
}

void http_parser::HttpData::setHeaderXForwardedFor(const std::string &cl_addr)
{
	if (!x_forwarded_for_header.empty())
		x_forwarded_for_header += ", ";
	x_forwarded_for_header += cl_addr;
	addHeader(http::HTTP_HEADER_NAME::X_FORWARDED_FOR, x_forwarded_for_header);
}

size_t http_parser::HttpData::getBufferRewritedLength(void) const
{
	// don't know yet
	uint64_t len = UINT64_MAX;

	if (message_undefined)
		return len;

	// no body expected
	if (content_length == 0 && chunked_status ==
			http::CHUNKED_STATUS::CHUNKED_DISABLED)
		len = header_length_new;

	// content-length header
	else if (content_length)
		len = header_length_new + content_length;

	// finished chunked encode
	else if (chunked_status == http::CHUNKED_STATUS::CHUNKED_LAST_CHUNK)
		len = message_total_bytes;

	return len;
}

size_t http_parser::HttpData::prepareToSend(char **buf, bool trim_parm)
{
	size_t buf_size = ZPROXY_BUFSIZ;
	size_t buf_len = 0;
	std::string ret = "";
	if (!getHeaderSent()) {
		if (trim_parm) {
			const size_t start = http_message_str.find(';');
			const size_t end = http_message_str.find(' ', start);

			http_message_str.replace(start, end - start, "");
		}
		ret.append(http_message_str);
		ret.append(http::CRLF);

		for (size_t i = 0; i != num_headers; i++) {
			if (headers[i].header_off)
				continue; // skip unwanted headers
			ret.append(headers[i].name, headers[i].line_size);
		}

		for (const auto & header : extra_headers) { // header must be always  used as reference,
			ret.append(header);		}

		for (const auto & header : permanent_extra_headers) { // header must be always  used as reference,
			ret.append(header);		}

		for (const auto & header : volatile_headers) { // header must be always  used as reference,
			ret.append(header);		}

		ret.append(http::CRLF);
		setHeaderSent(true, ret.length());
	}

	buf_len = ret.length() + message_length;

	// This is required by the transport layer, buf_size should be ZPROXY_BUF as minimum
	if(buf_len > buf_size)
		buf_size = buf_len;
	*buf = (char *)calloc(1, sizeof(char)*(buf_size));
	if (*buf == nullptr) {
		// SUGG: change "space" to "memory space" to be a bit more specific
		zcu_log_print_th(LOG_ERR, "Not enough space to prepare the http frame");
		return 0;
	}

	strncpy(*buf, ret.data(), ret.length());
	memcpy((*buf)+ret.length(), message, message_length);

	return buf_len;
}

void http_parser::HttpData::addHeader(http::HTTP_HEADER_NAME header_name,
				const std::string & header_value,
				bool permanent)
{
	std::string newh;
	newh.reserve(
		http::http_info::headers_names_strings.at(header_name).size() +
		http::CRLF_LEN + header_value.size() + http::CRLF_LEN);
	newh += http::http_info::headers_names_strings.at(header_name);
	newh += ": ";
	newh += header_value;
	newh += http::CRLF;
	!permanent ? extra_headers.push_back(std::move(newh)) :
			   permanent_extra_headers.push_back(std::move(newh));
}

void http_parser::HttpData::addHeader(const std::string & header_value,
				bool permanent)
{
	std::string newh;
	newh.reserve(header_value.size() + http::CRLF_LEN);
	newh += header_value;
	newh += http::CRLF;
	!permanent ? extra_headers.push_back(newh) :
			   permanent_extra_headers.push_back(std::move(newh));
}

void http_parser::HttpData::removeHeader(http::HTTP_HEADER_NAME header_name)
{
	auto header_to_remove =
		http::http_info::headers_names_strings.at(header_name);
	extra_headers.erase(
		std::remove_if(extra_headers.begin(), extra_headers.end(),
				   [header_to_remove](const std::string & header) {
						return header.find(header_to_remove) !=
						  std::string::npos;
				   }),
		extra_headers.end());
}

char *http_parser::HttpData::getBuffer() const
{
	return buffer;
}

bool http_parser::HttpData::getHeaderSent() const
{
	return headers_sent;
}

void http_parser::HttpData::setHeaderSent(bool value, size_t len)
{
	headers_sent = value;
	header_length_new = len;
}

bool http_parser::HttpData::getHeaderValue(const http::HTTP_HEADER_NAME header_name,
					   std::string & out_key) const
{
	for (size_t i = 0; i != num_headers; ++i) {
		std::string header(headers[i].name, headers[i].name_len);
		std::string header_value(headers[i].value, headers[i].value_len);
		if (http_info::headers_names.find(header) !=
			http_info::headers_names.end()) {
			auto header_name_ = http_info::headers_names.at(header);

			if (header_name_ == header_name) {
				out_key = header_value;
				return true;
			}
		}
	}
	return false;
}

bool http_parser::HttpData::getHeaderValue(const std::string &header_name,
					   std::string & out_key) const
{
	for (size_t i = 0; i != num_headers; ++i) {
		std::string_view header(headers[i].name, headers[i].name_len);

		if (header_name == header) {
			out_key = std::string(headers[i].value,
						  headers[i].value_len);
			return true;
		}
	}
	out_key = "";
	return false;
}

bool http_parser::HttpData::hasPendingData() const
{
	return headers_sent &&
		   // New request/response is processed over the same connection,
		   // so HTTP parsing is needed.
		   (message_bytes_left > 0 ||
		chunked_status == http::CHUNKED_STATUS::CHUNKED_ENABLED);
}

std::string http_parser::HttpData::getHttpVersion() const
{
	return http::http_info::http_version_strings.at(http_version);
}

void http_parser::HttpData::updateMessageBuffer()
{
	message = buffer;
	message_length = buffer_size;
}

void http_parser::HttpData::updateMessageLeft()
{
	if (content_length > 0)
		message_bytes_left -= message_length;
}

void http_parser::HttpData::updateMessageTotalBytes(size_t bytes)
{
	message_total_bytes += bytes;
}

void http_parser::HttpData::setHeaderTransferEncoding(std::string header_value)
{
	std::transform(header_value.begin(), header_value.end(), header_value.begin(), ::tolower);

	if (header_value.find(
			http::http_info::compression_types_strings
				.at(http::TRANSFER_ENCODING_TYPE::CHUNKED)) !=
			std::string::npos) {
		chunked_status = http::CHUNKED_STATUS::CHUNKED_ENABLED;
		transfer_encoding_type = TRANSFER_ENCODING_TYPE::CHUNKED;
	}
	if (header_value.find(
			http::http_info::compression_types_strings
				.at(http::TRANSFER_ENCODING_TYPE::COMPRESS)) !=
			std::string::npos)
		transfer_encoding_type = TRANSFER_ENCODING_TYPE::COMPRESS;
	if (header_value.find(
			http::http_info::compression_types_strings
				.at(http::TRANSFER_ENCODING_TYPE::DEFLATE)) !=
			std::string::npos)
		transfer_encoding_type = TRANSFER_ENCODING_TYPE::DEFLATE;
	if (header_value.find(
			http::http_info::compression_types_strings
				.at(http::TRANSFER_ENCODING_TYPE::GZIP)) !=
			std::string::npos)
		transfer_encoding_type = TRANSFER_ENCODING_TYPE::GZIP;
	if (header_value.find(
			http::http_info::compression_types_strings
				.at(http::TRANSFER_ENCODING_TYPE::IDENTITY)) !=
			std::string::npos)
		transfer_encoding_type = TRANSFER_ENCODING_TYPE::IDENTITY;

}

void http_parser::HttpData::setHeaderUpgrade(std::string header_value)
{
	std::transform(header_value.begin(), header_value.end(), header_value.begin(), ::tolower);
	if (header_value.find(
			http::http_info::upgrade_protocols_strings
				.at(http::UPGRADE_PROTOCOLS::WEBSOCKET)) !=
				std::string::npos)
		upgrade_header = true;
}

void http_parser::HttpData::setHeaderConnection(std::string header_value)
{
	std::transform(header_value.begin(), header_value.end(), header_value.begin(), ::tolower);
	if (header_value.find(
			http::http_info::connection_values_strings
				.at(http::CONNECTION_VALUES::
					UPGRADE)) !=
		std::string::npos)
		connection_header_upgrade = true;
	else if (header_value.find(
			 http::http_info::connection_values_strings
				 .at(http::CONNECTION_VALUES::
						 CLOSE)) !=
		 std::string::npos)
		connection_close_pending = true;
	else if (header_value.find(
			 http::http_info::connection_values_strings
				 .at(http::CONNECTION_VALUES::
						 KEEP_ALIVE)) !=
		 std::string::npos) {
		connection_keep_alive = true;
	}
}

void http_parser::HttpData::setHeaderContentLength(std::string &header_value)
{
	content_length = static_cast<size_t>(
					strtol(header_value.data(),
						   nullptr, 10));
	message_bytes_left = content_length;
}

/** If the StrictTransportSecurity is set then adds the header. */
void http_parser::HttpData::setHeaderStrictTransportSecurity(int sts)
{
	std::string sts_header_value = "max-age=";
	sts_header_value += std::to_string(sts);
	addHeader(
		http::HTTP_HEADER_NAME::STRICT_TRANSPORT_SECURITY,
		sts_header_value);
}

static int naive_search(const char *stack, int stack_size,
                        const char *needle, int needle_len, int *partial)
{
	int i = 0, j = *partial;

	while (i < stack_size) {

		/* matching, keep looking ahead. */
		if (stack[i] == needle[j]) {
			j++;
			i++;

			/* full match! */
			if (j == needle_len)
				break;

			continue;
		}
		/* backtrack */
		if (j > 0) {
			i -= j;
			j = 0;
		}

		if (i < 0)
			i = 0;
		else
			i++;
	}

	/* full match! */
	if (j == needle_len)
		return j;

	*partial = j;

	return -1;
}

static const char chunk_trailer[] = "\r\n0\r\n\r\n";
#define CHUNK_TRAILER_SIZE	7

static bool http_last_chunk(const char *data, size_t data_size, int *partial)
{
	int match;

	match = naive_search(data, data_size, chunk_trailer, CHUNK_TRAILER_SIZE, partial);
	if (match == CHUNK_TRAILER_SIZE) {
		zcu_log_print_th(LOG_DEBUG, "%s():%d: last chunk",
				 __FUNCTION__, __LINE__);
		return true;
	}
	zcu_log_print_th(LOG_DEBUG, "last chunk not yet seen");

	return false;
}

ssize_t http_parser::HttpData::handleChunkedData(void)
{
	if (!http_last_chunk(message, message_length, &partial_last_chunk))
		return -1;

	chunked_status = CHUNKED_STATUS::CHUNKED_LAST_CHUNK;

	return 0;
}

void http_parser::HttpData::manageBody(const char *buf, int buf_len)
{
	message_length = buf_len;
	message = (char *)buf;

	updateMessageTotalBytes(buf_len);

	if (chunked_status == CHUNKED_STATUS::CHUNKED_ENABLED)
		handleChunkedData();
	else
		updateMessageLeft();
}

bool http_parser::HttpData::expectBody(void) const
{
	return (message_undefined
		|| chunked_status == http::CHUNKED_STATUS::CHUNKED_ENABLED
		|| message_bytes_left > 0) ?
			   true :
				 false;
}
