//
// Created by abdess on 4/5/18.
//

#include "StreamManager.h"
#include "../handlers/HttpsManager.h"
#include "../handlers/zlib_util.h"
#include "../util/Network.h"
#include "../util/common.h"
#include "../util/string_view.h"
#include "../util/utils.h"
#include <cstdio>
#include <functional>
#if HELLO_WORLD_SERVER
void StreamManager::HandleEvent(int fd, EVENT_TYPE event_type,
                                EVENT_GROUP event_group) {
  switch (event_type) {
  case READ_ONESHOT: {
    HttpStream *stream = streams_set[fd];
    if (stream == nullptr) {
      stream = new HttpStream();
      stream->client_connection.setFileDescriptor(fd);
      streams_set[fd] = stream;
    }
    auto connection = stream->getConnection(fd);
    connection->read();
    connection->buffer_size = 1; // reset buffer size to avoid buffer
                                 // overflow due to not consuming buffer
                                 // data.
    updateFd(fd, EVENT_TYPE::WRITE, EVENT_GROUP::CLIENT);
    break;
  }

  case READ: {
    HttpStream *stream = streams_set[fd];
    if (stream == nullptr) {
      stream = new HttpStream();
      stream->client_connection.setFileDescriptor(fd);
      streams_set[fd] = stream;
    }
    auto connection = stream->getConnection(fd);
    connection->read();
    connection->buffer_size = 1;
    updateFd(fd, EVENT_TYPE::WRITE, EVENT_GROUP::CLIENT);
  }

  case WRITE: {
    auto stream = streams_set[fd];
    if (stream == nullptr) {
      Debug::LogInfo("Connection closed prematurely" + std::to_string(fd));
      return;
    }
    auto io_result = stream->client_connection.write(this->e200.c_str(),
                                                     this->e200.length());
    switch (io_result) {
    case IO::ERROR:
    case IO::FD_CLOSED:
    case IO::FULL_BUFFER:
      Debug::LogInfo("Something happend sentid e200", LOG_DEBUG);
      break;
    case IO::SUCCESS:
    case IO::DONE_TRY_AGAIN:
      updateFd(fd, READ, EVENT_GROUP::CLIENT);
      break;
    }

    break;
  }
  case CONNECT: {
    int new_fd;
    //      do {
    new_fd = listener_connection.doAccept();
    if (new_fd > 0) {
      addStream(new_fd);
    }
    //      } while (new_fd > 0);
    return;
  }
  case ACCEPT:
    break;
  case DISCONNECT: {
    auto stream = streams_set[fd];
    if (stream == nullptr) {
      Debug::LogInfo("Stream doesn't exist for " + std::to_string(fd));
      deleteFd(fd);
      ::close(fd);
      return;
    }
    /*      streams_set.erase(fd);
    delete stream*/
    ;
    clearStream(stream);
    break;
  }
  }
}
#else
void StreamManager::HandleEvent(int fd, EVENT_TYPE event_type,
                                EVENT_GROUP event_group) {
  switch (event_type) {
#if SM_HANDLE_ACCEPT
  case CONNECT: {
    int new_fd;
    //      do {
    new_fd = listener_connection.doAccept();
    if (new_fd > 0) {
      addStream(new_fd);
    }
    //      } while (new_fd > 0);
    return;
  }
#endif
  case READ:
  case READ_ONESHOT: {
    switch (event_group) {
    case EVENT_GROUP::ACCEPTOR:
      break;
    case EVENT_GROUP::SERVER:
      onResponseEvent(fd);
      break;
    case EVENT_GROUP::CLIENT:
      onRequestEvent(fd);
      break;
    case EVENT_GROUP::CONNECT_TIMEOUT:
      onConnectTimeoutEvent(fd);
      break;
    case EVENT_GROUP::REQUEST_TIMEOUT:
      onRequestTimeoutEvent(fd);
      break;
    case EVENT_GROUP::RESPONSE_TIMEOUT:
      onResponseTimeoutEvent(fd);
      break;
    case EVENT_GROUP::SIGNAL:
      onSignalEvent(fd);
      break;
    case EVENT_GROUP::MAINTENANCE:
      break;
    default:
      deleteFd(fd);
      close(fd);
      break;
    }
    return;
  }
  case WRITE: {
    auto stream = streams_set[fd];
    if (stream == nullptr) {
      switch (event_group) {
      case EVENT_GROUP::ACCEPTOR:
        break;
      case EVENT_GROUP::SERVER:
        Debug::LogInfo("SERVER_WRITE : Stream doesn't exist for " +
                       std::to_string(fd));
        break;
      case EVENT_GROUP::CLIENT:
        Debug::LogInfo("CLIENT_WRITE : Stream doesn't exist for " +
                       std::to_string(fd));
        break;
      default:
        break;
      }
      deleteFd(fd);
      ::close(fd);
      return;
    }

    switch (event_group) {
    case EVENT_GROUP::ACCEPTOR:
      break;
    case EVENT_GROUP::SERVER: {
      onServerWriteEvent(stream);
      break;
    }
    case EVENT_GROUP::CLIENT: {
      onClientWriteEvent(stream);
      break;
    }
    default: {
      deleteFd(fd);
      ::close(fd);
    }
    }

    return;
  }
  case DISCONNECT: {
    auto stream = streams_set[fd];
    if (stream == nullptr) {
      Debug::LogInfo("Remote host closed connection prematurely ", LOG_INFO);
      deleteFd(fd);
      ::close(fd);
      return;
    }
    switch (event_group) {
    case EVENT_GROUP::SERVER: {
        // FIXME: Why is it entering here when there is a conn refused
        //      if (!stream->backend_connection.isConnected()) {
        //        auto response =
        //            HttpStatus::getHttpResponse(HttpStatus::Code::RequestTimeout);
        //        stream->client_connection.write(response.c_str(), response.length());
        //        Debug::LogInfo("Backend closed connection", LOG_DEBUG);
        //      }
        //      break;
        return;
    }
    case EVENT_GROUP::CLIENT: {
      Debug::LogInfo("Client closed connection", LOG_DEBUG);
      break;
    }
    default:
      Debug::LogInfo("Why this happends!!", LOG_DEBUG);
      break;
    }
    clearStream(stream);
    break;
  }
  default:
    Debug::LogInfo("Unexpected  event type", LOG_DEBUG);
    deleteFd(fd);
    ::close(fd);
  }
}
#endif

void StreamManager::stop() { is_running = false; }

void StreamManager::start(int thread_id_) {
  is_running = true;
  worker_id = thread_id_;
  this->worker = std::thread([this] { doWork(); });
  if (worker_id >= 0) {
    //    helper::ThreadHelper::setThreadAffinity(worker_id,
    //    worker.native_handle());
    helper::ThreadHelper::setThreadName("WORKER_" + std::to_string(worker_id),
                                        worker.native_handle());
  }
#if SM_HANDLE_ACCEPT
  handleAccept(listener_connection.getFileDescriptor());
#endif
}

StreamManager::StreamManager()
    : is_https_listener(false){
          // TODO:: do attach for config changes
      };

StreamManager::~StreamManager() {
  stop();
  if (worker.joinable())
    worker.join();
  for (auto &key_pair : streams_set) {
    delete key_pair.second;
  }
}
void StreamManager::doWork() {
  while (is_running) {
    if (loopOnce() <= 0) {
      // something bad happend
      //      Debug::LogInfo("No events !!");
    }
    // if(needMainatance)
    //    doMaintenance();
  }
}

void StreamManager::addStream(int fd) {
  DEBUG_COUNTER_HIT(debug__::on_client_connect);
#if SM_HANDLE_ACCEPT
  HttpStream *stream = streams_set[fd];
  if (UNLIKELY(stream != nullptr)) {
    clearStream(stream);
  }
  stream = new HttpStream();
  stream->client_connection.setFileDescriptor(fd);
  streams_set[fd] = stream;
  stream->timer_fd.set(listener_config_.to * 1000);
  addFd(stream->timer_fd.getFileDescriptor(), TIMEOUT,
        EVENT_GROUP::REQUEST_TIMEOUT);
  timers_set[stream->timer_fd.getFileDescriptor()] = stream;
  stream->client_connection.enableEvents(this, READ, EVENT_GROUP::CLIENT);

  // set extra header to forward to the backends
  stream->request.addHeader(http::HTTP_HEADER_NAME::X_FORWARDED_FOR,
                            stream->client_connection.getPeerAddress(), true);
  if (listener_config_.add_head != NULL) {
    stream->request.addHeader(listener_config_.add_head, true);
  }
  if (this->is_https_listener) {
    stream->client_connection.ssl_conn_status = ssl::SSL_STATUS::NEED_HANDSHAKE;
  }
// configurar
#else
  if (!this->addFd(fd, READ, EVENT_GROUP::CLIENT)) {
    Debug::LogInfo("Error adding to epoll manager", LOG_NOTICE);
  }
#endif
}

int StreamManager::getWorkerId() { return worker_id; }

void StreamManager::onRequestEvent(int fd) {
  DEBUG_COUNTER_HIT(debug__::on_request);
  HttpStream *stream = streams_set[fd];
  if (stream != nullptr) {
    if (stream->client_connection.isCancelled()) {
      clearStream(stream);
      return;
    }
    if (UNLIKELY(fd != stream->client_connection.getFileDescriptor())) {
      Debug::LogInfo("FOUND:: Aqui ha pasado algo raro!!", LOG_REMOVE);
    }
  } else {
#if !SM_HANDLE_ACCEPT
    stream = new HttpStream();
    stream->client_connection.setFileDescriptor(fd);
    streams_set[fd] = stream;
    if (fd != stream->client_connection.getFileDescriptor()) {
      Debug::LogInfo("FOUND:: Aqui ha pasado algo raro!!", LOG_DEBUG);
    }
#endif
    deleteFd(fd);
    ::close(fd);
    return;
  }
  //    StreamWatcher watcher(*stream);
  IO::IO_RESULT result = IO::IO_RESULT::ERROR;
  if (this->is_https_listener) {
    result = this->ssl_manager->handleDataRead(stream->client_connection);
  } else {
    result = stream->client_connection.read();
  }

  switch (result) {
  case IO::IO_RESULT::SSL_HANDSHAKE_ERROR:
  case IO::IO_RESULT::SSL_NEED_HANDSHAKE: {

    if (!this->ssl_manager->handleHandshake(stream->client_connection)) {
      if ((ERR_GET_REASON(ERR_peek_error()) == SSL_R_HTTP_REQUEST) &&
          (ERR_GET_LIB(ERR_peek_error()) == ERR_LIB_SSL)) {
        /* the client speaks plain HTTP on our HTTPS port */
        Debug::logmsg(LOG_NOTICE,
                      "Client %s sent a plain HTTP message to an SSL port",
                      stream->client_connection.getPeerAddress().c_str());
        if (listener_config_.nossl_redir > 0) {
          Debug::logmsg(LOG_NOTICE,
                        "(%lx) errNoSsl from %s redirecting to \"%s\"",
                        pthread_self(),
                        stream->client_connection.getPeerAddress().c_str(),
                        listener_config_.nossl_url);
          stream->replyRedirect(listener_config_.nossl_redir,
                                listener_config_.nossl_url);
        } else {
          Debug::logmsg(LOG_NOTICE, "(%lx) errNoSsl from %s sending error",
                        pthread_self(),
                        stream->client_connection.getPeerAddress().c_str());
          stream->replyError(
              HttpStatus::Code::BadRequest,
              HttpStatus::reasonPhrase(HttpStatus::Code::BadRequest).c_str(),
              listener_config_.errnossl, this->listener_config_,
              *this->ssl_manager);
        }
      } else {
        Debug::logmsg(LOG_INFO, "Handshake error with %s ",
                      stream->client_connection.getPeerAddress().c_str());
      }
      clearStream(stream);
      return;
    }
    if (stream->client_connection.ssl_connected) {
      httpsHeaders(stream, ssl_manager, listener_config_.clnt_check);
      DEBUG_COUNTER_HIT(debug__::on_handshake);
    }
    return;
  }
  case IO::IO_RESULT::SUCCESS:
  case IO::IO_RESULT::DONE_TRY_AGAIN:
  case IO::IO_RESULT::FULL_BUFFER:
    break;
  case IO::IO_RESULT::ZERO_DATA:
    return;
  case IO::IO_RESULT::FD_CLOSED:
    break;
  case IO::IO_RESULT::ERROR:
  case IO::IO_RESULT::CANCELLED:
  default: {
    Debug::LogInfo("Error reading request ", LOG_DEBUG);
    clearStream(stream);
    return;
  }
  }

  if (stream->upgrade.pinned_connection ||
      stream->request.message_bytes_left > 0) {
    // TODO:: maybe quick response
    Debug::logmsg(
        LOG_REMOVE, "\nREQUEST DATA IN\n\t\t buffer size: %lu \n\t\t Content "
                    "length: %lu \n\t\t message bytes left: %lu",
        stream->client_connection.buffer_size, stream->request.content_length,
        stream->request.message_bytes_left);
    stream->backend_connection.enableWriteEvent();
    return;
  }

  /* Check if chunked transfer encoding is enabled. */
  if (http_manager::transferChunked(stream)) {
    stream->backend_connection.enableWriteEvent();
    return;
  }

  size_t parsed = 0;
  http_parser::PARSE_RESULT parse_result;
  // do {
  parse_result = stream->request.parseRequest(
      stream->client_connection.buffer, stream->client_connection.buffer_size,
      &parsed); // parsing http data as response structured

  switch (parse_result) {
  case http_parser::PARSE_RESULT::SUCCESS: {
    auto valid =
        http_manager::validateRequest(stream->request, listener_config_);
    if (UNLIKELY(validation::REQUEST_RESULT::OK != valid)) {
      stream->replyError(HttpStatus::Code::NotImplemented,
                         validation::request_result_reason.at(valid).c_str(),
                         listener_config_.err501, this->listener_config_,
                         *this->ssl_manager);
      this->clearStream(stream);
      return;
    }
    stream->timer_fd.unset();
    deleteFd(stream->timer_fd.getFileDescriptor());
    timers_set[stream->timer_fd.getFileDescriptor()] = nullptr;
    auto service = service_manager->getService(stream->request);
    if (service == nullptr) {
      stream->replyError(HttpStatus::Code::ServiceUnavailable,
                         validation::request_result_reason
                             .at(validation::REQUEST_RESULT::SERVICE_NOT_FOUND)
                             .c_str(),
                         listener_config_.err503, this->listener_config_,
                         *this->ssl_manager);
      this->clearStream(stream);
      return;
    }

    stream->request.setService(service);

    auto bck = service->getBackend(*stream);
    if (bck == nullptr) {
      // No backend available
      stream->replyError(HttpStatus::Code::ServiceUnavailable,
                         validation::request_result_reason
                             .at(validation::REQUEST_RESULT::BACKEND_NOT_FOUND)
                             .c_str(),
                         listener_config_.err503, this->listener_config_,
                         *this->ssl_manager);
      this->clearStream(stream);
      return;
    } else {
      IO::IO_OP op_state = IO::IO_OP::OP_ERROR;
      Debug::logmsg(
          LOG_DEBUG, "[%s] %.*s [%s (%d) -> %s (%d)]", service->name.c_str(),
          stream->request.getRequestLine().length() - 2,
          stream->request.getRequestLine().c_str(),
          stream->client_connection.getPeerAddress().c_str(),
          stream->client_connection.getFileDescriptor(), bck->address.c_str(),
          stream->backend_connection.getFileDescriptor());
      switch (bck->backend_type) {
      case BACKEND_TYPE::REMOTE: {
        if (stream->backend_connection.getBackend() == nullptr ||
            !stream->backend_connection.isConnected()) {
          // null
          if (stream->backend_connection.getFileDescriptor() > 0) { //

            deleteFd(stream->backend_connection
                         .getFileDescriptor()); // Client cannot
            // be connected to more
            // than one backend at
            // time
            streams_set.erase(stream->backend_connection.getFileDescriptor());
            stream->backend_connection.closeConnection();
            if (stream->backend_connection.isConnected())
              stream->backend_connection.getBackend()->decreaseConnection();
          }
          stream->backend_connection.setBackend(bck);
          stream->backend_connection.time_start =
              std::chrono::steady_clock::now();
          op_state = stream->backend_connection.doConnect(*bck->address_info,
                                                          bck->conn_timeout);
          switch (op_state) {
          case IO::IO_OP::OP_ERROR: {
            auto response = HttpStatus::getHttpResponse(
                HttpStatus::Code::ServiceUnavailable);
            stream->client_connection.write(response.c_str(),
                                            response.length());
            Debug::LogInfo("Error connecting to backend " + bck->address,
                           LOG_NOTICE);

            stream->backend_connection.getBackend()->status =
                BACKEND_STATUS::BACKEND_DOWN;
            stream->backend_connection.closeConnection();
            clearStream(stream);
            return;
          }

          case IO::IO_OP::OP_IN_PROGRESS: {
            stream->timer_fd.set(bck->conn_timeout * 1000);
            stream->backend_connection.getBackend()->increaseConnTimeoutAlive();
            timers_set[stream->timer_fd.getFileDescriptor()] = stream;
            addFd(stream->timer_fd.getFileDescriptor(), EVENT_TYPE::READ,
                  EVENT_GROUP::CONNECT_TIMEOUT);
            if (stream->backend_connection.getBackend()->nf_mark > 0)
              Network::setSOMarkOption(
                  stream->backend_connection.getFileDescriptor(),
                  stream->backend_connection.getBackend()->nf_mark);
          }
          case IO::IO_OP::OP_SUCCESS: {
            DEBUG_COUNTER_HIT(debug__::on_backend_connect);
            stream->backend_connection.getBackend()->increaseConnection();
            streams_set[stream->backend_connection.getFileDescriptor()] =
                stream;
            /*
                        if
               (stream->backend_connection.getBackend()->backend_config.ctx !=
               nullptr)
                          ssl_manager->init(stream->backend_connection.getBackend()->backend_config);
            */
            stream->backend_connection.enableEvents(this, EVENT_TYPE::WRITE,
                                                    EVENT_GROUP::SERVER);
            break;
          }
          }
        }

        // Rewrite destination
        if (stream->request.add_destination_header) {
          std::string header_value = "http://";
          header_value += stream->backend_connection.getPeerAddress();
          header_value += ':';
          header_value += stream->request.path;
          stream->request.addHeader(http::HTTP_HEADER_NAME::DESTINATION,
                                    header_value);
        }
        if (!stream->request.host_header_found) {
          std::string header_value = "";
          header_value += stream->backend_connection.getPeerAddress();
          header_value += ':';
          header_value +=
              std::to_string(stream->backend_connection.getBackend()->port);
          stream->request.addHeader(http::HTTP_HEADER_NAME::HOST, header_value);
        }
        /* After setting the backend and the service in the first request,
         * pin the connection if the PinnedConnection service config parameter
         * is true. Note: The first request must be HTTP. */
        if (service->service_config.pinned_connection) {
          stream->upgrade.pinned_connection = true;
        }

        stream->backend_connection.enableWriteEvent();
        break;
      }
      case BACKEND_TYPE::EMERGENCY_SERVER:

        break;
      case BACKEND_TYPE::REDIRECT: {
        /*Check redirect request type ::> 0 - redirect is absolute, 1 -
         * the redirect should include the request path, or 2 if it should
         * use perl dynamic replacement */
        //              switch (bck->backend_config.redir_req) {
        //                case 1:
        //
        //                  break;
        //                case 2: break;
        //                case 0:
        //                default: break;
        //              }
        stream->replyRedirect(bck->backend_config);
        clearStream(stream);
        return;
      }
      case BACKEND_TYPE::CACHE_SYSTEM:
        break;
      }
    }
    break;
  }
  case http_parser::PARSE_RESULT::TOOLONG:
    Debug::LogInfo("Parser TOOLONG", LOG_DEBUG);
  case http_parser::PARSE_RESULT::FAILED:
    stream->replyError(
        HttpStatus::Code::BadRequest,
        HttpStatus::reasonPhrase(HttpStatus::Code::BadRequest).c_str(),
        listener_config_.err501, this->listener_config_, *this->ssl_manager);
    this->clearStream(stream);
    return;
  case http_parser::PARSE_RESULT::INCOMPLETE:
    Debug::LogInfo("Parser INCOMPLETE", LOG_DEBUG);
    stream->client_connection.enableReadEvent();
    return;
  }

  /*if ((stream->client_connection.buffer_size - parsed) > 0) {
    Debug::LogInfo("Buffer size: left size: " +
        std::to_string(stream->client_connection.buffer_size),
                   LOG_DEBUG);
    Debug::LogInfo("Current request buffer: \n " +
        std::string(stream->client_connection.buffer,
                    stream->client_connection.buffer_size),
                   LOG_DEBUG);
    Debug::LogInfo("Parsed data size: " + std::to_string(parsed), LOG_DEBUG);
  }
*/
  //} while (stream->client_connection.buffer_size > parsed &&
  //  parse_result ==
  //     http_parser::PARSE_RESULT::SUCCESS);

  stream->client_connection.enableReadEvent();
}

void StreamManager::onResponseEvent(int fd) {
  DEBUG_COUNTER_HIT(debug__::on_response);
  HttpStream *stream = streams_set[fd];
  if (stream == nullptr) {
    Debug::LogInfo("Backend Connection, Stream closed", LOG_DEBUG);
    deleteFd(fd);
    ::close(fd);
    return;
  }
  if (UNLIKELY(stream->client_connection
                   .isCancelled())) { // check if client is still active
    clearStream(stream);
    return;
  }
  if (stream->backend_connection.buffer_size > 0)
    return;
  Debug::logmsg(
      LOG_REMOVE, "\nRESPONSE DATA IN\n\t\t buffer size: %lu \n\t\t Content "
                  "length: %lu \n\t\t message bytes left: %lu",
      stream->backend_connection.buffer_size, stream->response.content_length,
      stream->response.message_bytes_left);
  //    StreamWatcher watcher(*stream);
  // disable response timeout timerfd
  if (stream->backend_connection.getBackend()->response_timeout > 0) {
    stream->timer_fd.unset();
    events::EpollManager::deleteFd(stream->timer_fd.getFileDescriptor());
  }

  IO::IO_RESULT result;

  if (stream->backend_connection.getBackend()->isHttps()) {
    result =
        stream->backend_connection.getBackend()->ssl_manager.handleDataRead(
            stream->backend_connection);
  } else {
#if ENABLE_ZERO_COPY
    if (stream->response.message_bytes_left > 0 &&
        !stream->backend_connection.getBackend()->isHttps() &&
        !this->is_https_listener
        /*&& stream->response.transfer_encoding_header*/) {
      result = stream->backend_connection.zeroRead();
      if (result == IO::IO_RESULT::ERROR) {
        Debug::LogInfo("Error reading response ", LOG_DEBUG);
        clearStream(stream);
        return;
      }
// TODO::Evaluar
#ifdef ENABLE_QUICK_RESPONSE
      result = stream->backend_connection.zeroWrite(
          stream->client_connection.getFileDescriptor(), stream->response);
      switch (result) {
      case IO::IO_RESULT::FD_CLOSED:
      case IO::IO_RESULT::ERROR: {
        Debug::LogInfo("Error Writing response ", LOG_NOTICE);
        clearStream(stream);
        return;
      }
      case IO::IO_RESULT::SUCCESS:
        return;
      case IO::IO_RESULT::DONE_TRY_AGAIN:
        stream->client_connection.enableWriteEvent();
        return;
      case IO::IO_RESULT::FULL_BUFFER:
        break;
      }
#endif
    } else
#endif
      result = stream->backend_connection.read();
  }
  Debug::logmsg(LOG_REMOVE, "IO RESULT: %s",
                IO::getResultString(result).data());
  switch (result) {
  case IO::IO_RESULT::SSL_HANDSHAKE_ERROR:
  case IO::IO_RESULT::SSL_NEED_HANDSHAKE: {
    if (!stream->backend_connection.getBackend()->ssl_manager.handleHandshake(
            stream->backend_connection, true)) {
      Debug::logmsg(LOG_INFO, "Backend handshake error with %s ",
                    stream->backend_connection.address_str.c_str());
      stream->replyError(
          HttpStatus::Code::ServiceUnavailable,
          HttpStatus::reasonPhrase(HttpStatus::Code::ServiceUnavailable)
              .c_str(),
          listener_config_.err503, this->listener_config_, *this->ssl_manager);
      clearStream(stream);
    }
    if (stream->backend_connection.ssl_connected) {
      stream->backend_connection.enableWriteEvent();
    }
    return;
  }
  case IO::IO_RESULT::SUCCESS:
    break;
  case IO::IO_RESULT::DONE_TRY_AGAIN: {
    if (stream->backend_connection.buffer_size == 0) {
      if (stream->response.message_bytes_left > 0 ||
          stream->upgrade.pinned_connection)
        stream->backend_connection.enableReadEvent();
      return;
    }
    break;
  }
  case IO::IO_RESULT::FULL_BUFFER:
  case IO::IO_RESULT::ZERO_DATA:
  case IO::IO_RESULT::FD_CLOSED:
    break;
  case IO::IO_RESULT::ERROR:
  case IO::IO_RESULT::CANCELLED:
  default: {
    Debug::LogInfo("Error reading response ", LOG_DEBUG);
    clearStream(stream);
    return;
  }
  }

  // TODO::FERNANDO::REPASAR, toma de muestras de tiempo, solo se debe de
  // tomar muestra si se la lectura ha sido success.
  stream->backend_connection.getBackend()->calculateLatency(
      std::chrono::duration_cast<std::chrono::duration<double>>(
          std::chrono::steady_clock::now() -
          stream->backend_connection.time_start)
          .count());
  //  stream->backend_stadistics.update();

  if (stream->upgrade.pinned_connection ||
      stream->response.message_bytes_left > 0 ||
      stream->response.transfer_encoding_header) {
    // if chunked get chunk size
    if (stream->response.transfer_encoding_header) {
      stream->response.message_bytes_left =
          stream->backend_connection.buffer_size;
      stream->response.transfer_encoding_header =
          stream->backend_connection.buffer_size == 0;
      //            http_manager::getChunkSize(
      //                    std::string(stream->backend_connection.buffer,
      //                    stream->backend_connection.buffer_size));
    }

    stream->client_connection.enableWriteEvent();
    // TODO:: maybe quick response
    Debug::logmsg(
        LOG_REMOVE, "\nRESPONSE DATA IN\n\t\t buffer size: %lu \n\t\t Content "
                    "length: %lu \n\t\t message bytes left: %lu",
        stream->backend_connection.buffer_size, stream->response.content_length,
        stream->response.message_bytes_left);
    return;
  }

  size_t parsed = 0;
  auto ret = stream->response.parseResponse(
      stream->backend_connection.buffer, stream->backend_connection.buffer_size,
      &parsed);

  if (ret != http_parser::PARSE_RESULT::SUCCESS) {
    Debug::logmsg(LOG_REMOVE, "PARSE FAILED \nRESPONSE DATA IN\n\t\t buffer "
                              "size: %lu \n\t\t Content length: %lu \n\t\t "
                              "message bytes left: %lu\n%.*s",
                  stream->backend_connection.buffer_size,
                  stream->response.content_length,
                  stream->response.message_bytes_left,
                  stream->backend_connection.buffer_size,
                  stream->backend_connection.buffer);
    return;
    clearStream(stream);
    return;
  }

  static int retries;
  retries++;
  Debug::logmsg(
      LOG_DEBUG, " %d [%s] %.*s [%s (%d) <- %s (%d)]", retries,
      static_cast<Service *>(stream->request.getService())->name.c_str(),
      stream->response.http_message_length - 2, stream->response.http_message,
      stream->client_connection.getPeerAddress().c_str(),
      stream->client_connection.getFileDescriptor(),
      stream->backend_connection.getBackend()->address.c_str(),
      stream->backend_connection.getFileDescriptor());

  stream->backend_connection.getBackend()->setAvgTransferTime(
      std::chrono::duration_cast<std::chrono::duration<double>>(
          std::chrono::steady_clock::now() -
          stream->backend_connection.time_start)
          .count());

  if (http_manager::validateResponse(*stream, listener_config_) !=
      validation::REQUEST_RESULT::OK) {
    Debug::logmsg(LOG_NOTICE,
                  "(%lx) backend %s response validation error\n %.*s",
                  std::this_thread::get_id(),
                  stream->backend_connection.getBackend()->address.c_str(),
                  stream->backend_connection.buffer_size,
                  stream->backend_connection.buffer);
    stream->replyError(
        HttpStatus::Code::ServiceUnavailable,
        HttpStatus::reasonPhrase(HttpStatus::Code::ServiceUnavailable).c_str(),
        listener_config_.err503, this->listener_config_, *this->ssl_manager);
    this->clearStream(stream);
    return;
  }

  auto service = static_cast<Service *>(stream->request.getService());
  http_manager::setBackendCookie(service, stream);
  setStrictTransportSecurity(service, stream);
  if (!this->is_https_listener) {
    http_manager::applyCompression(service, stream);
  }

  stream->client_connection.enableWriteEvent();
}

void StreamManager::onConnectTimeoutEvent(int fd) {
  DEBUG_COUNTER_HIT(debug__::on_backend_connect_timeout);
  HttpStream *stream = timers_set[fd];
  if (stream == nullptr) {
    Debug::LogInfo("Stream null pointer", LOG_REMOVE);
    deleteFd(fd);
    ::close(fd);
  } else if (stream->timer_fd.isTriggered()) {
    stream->backend_connection.getBackend()->status =
        BACKEND_STATUS::BACKEND_DOWN;
    Debug::logmsg(LOG_NOTICE, "(%lx) backend %s connection timeout after %d",
                  std::this_thread::get_id(),
                  stream->backend_connection.getBackend()->address.c_str(),
                  stream->backend_connection.getBackend()->conn_timeout);
    stream->replyError(
        HttpStatus::Code::ServiceUnavailable,
        HttpStatus::reasonPhrase(HttpStatus::Code::ServiceUnavailable).c_str(),
        listener_config_.err503, this->listener_config_, *this->ssl_manager);
    this->clearStream(stream);
  }
}

void StreamManager::onRequestTimeoutEvent(int fd) {
  DEBUG_COUNTER_HIT(debug__::on_request_timeout);
  HttpStream *stream = timers_set[fd];
  if (stream == nullptr) {
    Debug::LogInfo("Stream null pointer", LOG_REMOVE);
    deleteFd(fd);
    ::close(fd);
  } else if (stream->timer_fd.isTriggered()) {
    clearStream(stream); // FIXME::
  }
}

void StreamManager::onResponseTimeoutEvent(int fd) {
  DEBUG_COUNTER_HIT(debug__::on_response_timeout);
  HttpStream *stream = timers_set[fd];
  if (stream == nullptr) {
    Debug::LogInfo("Stream null pointer", LOG_REMOVE);
    deleteFd(fd);
    ::close(fd);
  } else if (stream->timer_fd.isTriggered()) {
    char caddr[50];
    if (UNLIKELY(Network::getPeerAddress(
                     stream->client_connection.getFileDescriptor(), caddr,
                     50) == nullptr)) {
      Debug::LogInfo("Error getting peer address", LOG_DEBUG);
    } else {
      Debug::logmsg(LOG_NOTICE, "(%lx) e%d %s %s from %s",
                    std::this_thread::get_id(),
                    static_cast<int>(HttpStatus::Code::GatewayTimeout),
                    validation::request_result_reason
                        .at(validation::REQUEST_RESULT::BACKEND_TIMEOUT)
                        .c_str(),
                    stream->client_connection.buffer, caddr);
    }
    stream->replyError(
        HttpStatus::Code::GatewayTimeout,
        HttpStatus::reasonPhrase(HttpStatus::Code::GatewayTimeout).c_str(),
        HttpStatus::reasonPhrase(HttpStatus::Code::GatewayTimeout).c_str(),
        this->listener_config_, *this->ssl_manager);
    this->clearStream(stream);
  }
}
void StreamManager::onSignalEvent(int fd) {
  // TODO::IMPLEMENET
}

void StreamManager::onServerWriteEvent(HttpStream *stream) {
  DEBUG_COUNTER_HIT(debug__::on_send_request);
  if (UNLIKELY(stream->backend_connection.isCancelled())) {
    clearStream(stream);
    return;
  }
  // StreamWatcher watcher(*stream);
  int fd = stream->backend_connection.getFileDescriptor();
  // Send client request to backend server
  if (stream->backend_connection.getBackend()->conn_timeout > 0 &&
      Network::isConnected(fd) && stream->timer_fd.is_set) {
    stream->timer_fd.unset();
    stream->backend_connection.getBackend()->decreaseConnTimeoutAlive();

    stream->backend_connection.getBackend()->setAvgConnTime(
        std::chrono::duration_cast<std::chrono::duration<double>>(
            std::chrono::steady_clock::now() -
            stream->backend_connection.time_start)
            .count());
    this->deleteFd(stream->timer_fd.getFileDescriptor());
  }

  /* If the connection is pinned, then we need to write the buffer
   * content without applying any kind of modification. */
  if (stream->client_connection.buffer_size == 0 &&
      !(stream->backend_connection.getBackend()->isHttps() &&
        !stream->backend_connection.ssl_connected)) {
    stream->client_connection.enableReadEvent();
    stream->backend_connection.enableReadEvent();
    return;
  }
  /* If the connection is pinned or we have content length remaining to send
   * , then we need to write the buffer content without
   * applying any kind of modification. */
  IO::IO_RESULT result = IO::IO_RESULT::ERROR;
  if (stream->upgrade.pinned_connection ||
      stream->request.message_bytes_left > 0 ||
      stream->chunked_status != http::CHUNKED_STATUS::CHUNKED_DISABLED) {
    size_t written;

    if (stream->backend_connection.getBackend()->isHttps()) {
      result = stream->backend_connection.getBackend()->ssl_manager.handleWrite(
          stream->backend_connection, stream->client_connection.buffer,
          stream->client_connection.buffer_size, written);
    }

    else {
      if (stream->client_connection.buffer_size > 0)
        stream->client_connection.writeTo(
            stream->backend_connection.getFileDescriptor(), written);
#if ENABLE_ZERO_COPY
      else if (stream->client_connection.splice_pipe.bytes > 0)
        result = stream->client_connection.zeroWrite(
            stream->backend_connection.getFileDescriptor(), stream->request);
#endif
    }
    switch (result) {
    case IO::IO_RESULT::SSL_HANDSHAKE_ERROR:
    case IO::IO_RESULT::SSL_NEED_HANDSHAKE: {
      if (!stream->backend_connection.getBackend()->ssl_manager.handleHandshake(
              stream->backend_connection, true)) {
        Debug::logmsg(LOG_INFO, "Handshake error with %s ",
                      stream->backend_connection.getBackend()->address.data());
        stream->replyError(
            HttpStatus::Code::ServiceUnavailable,
            HttpStatus::reasonPhrase(HttpStatus::Code::ServiceUnavailable)
                .c_str(),
            listener_config_.err503, this->listener_config_,
            *this->ssl_manager);
        clearStream(stream);
      }
      if (!stream->backend_connection.ssl_connected) {
        stream->backend_connection.enableReadEvent();
      }
      return;
    }
    case IO::IO_RESULT::FD_CLOSED:
    case IO::IO_RESULT::CANCELLED:
    case IO::IO_RESULT::FULL_BUFFER:
    case IO::IO_RESULT::ERROR:
      Debug::LogInfo("Error sending request ", LOG_DEBUG);
      clearStream(stream);
      return;
    case IO::IO_RESULT::SUCCESS:
    case IO::IO_RESULT::DONE_TRY_AGAIN:
      break;
    }
    Debug::logmsg(
        LOG_DEBUG, "\nDATA out\n\t\t buffer size: %d \n\t\t Content length: %d "
                   "\n\t\t message bytes left: %d \n\t\t written: %d",
        stream->client_connection.buffer_size, stream->request.content_length,
        stream->request.message_bytes_left, written);
    if (stream->client_connection.buffer_size > 0)
      stream->client_connection.buffer_size -= written;
    if (stream->response.message_bytes_left > 0) {
      stream->request.message_bytes_left -= written;
    }
    /* Check if chunked transfer encoding is enabled. update status*/
    if (stream->chunked_status != http::CHUNKED_STATUS::CHUNKED_DISABLED) {
      stream->chunked_status =
          stream->chunked_status == http::CHUNKED_STATUS::CHUNKED_LAST_CHUNK
              ? http::CHUNKED_STATUS::CHUNKED_DISABLED
              : http::CHUNKED_STATUS::CHUNKED_ENABLED;
    }
    stream->client_connection.enableReadEvent();
    stream->backend_connection.enableReadEvent();
    stream->backend_connection.enableWriteEvent();
    return;
  }

  /*Check if the buffer has data to be send */
  if (stream->client_connection.buffer_size == 0)
    return;

  if (stream->backend_connection.getBackend()->isHttps()) {
    result =
        stream->backend_connection.getBackend()->ssl_manager.handleDataWrite(
            stream->backend_connection, stream->client_connection,
            stream->request);
  } else {
    result = stream->client_connection.writeTo(stream->backend_connection,
                                               stream->request);
  }

  switch (result) {
  case IO::IO_RESULT::SSL_HANDSHAKE_ERROR:
  case IO::IO_RESULT::SSL_NEED_HANDSHAKE: {
    if (!stream->backend_connection.getBackend()->ssl_manager.handleHandshake(
            stream->backend_connection, true)) {
      Debug::logmsg(LOG_INFO, "Handshake error with %s ",
                    stream->backend_connection.address_str.data());
      clearStream(stream);
    }
    if (!stream->backend_connection.ssl_connected) {
      stream->backend_connection.enableReadEvent();
      return;
    } else {
      stream->backend_connection.enableWriteEvent();
    }
    return;
  }
  case IO::IO_RESULT::FD_CLOSED:
  case IO::IO_RESULT::CANCELLED:
  case IO::IO_RESULT::FULL_BUFFER:
  case IO::IO_RESULT::ERROR:
    Debug::LogInfo("Error sending request to backend ", LOG_DEBUG);
    clearStream(stream);
    return;
  case IO::IO_RESULT::SUCCESS:
    break;
  case IO::IO_RESULT::DONE_TRY_AGAIN:
    stream->backend_connection.enableWriteEvent();
    break;
  default:
    Debug::LogInfo("Error sending data to backend server", LOG_DEBUG);
    clearStream(stream);
    return;
  }

  stream->timer_fd.set(
      stream->backend_connection.getBackend()->response_timeout * 1000);
  timers_set[stream->timer_fd.getFileDescriptor()] = stream;
  addFd(stream->timer_fd.getFileDescriptor(), EVENT_TYPE::READ,
        EVENT_GROUP::RESPONSE_TIMEOUT);
  stream->backend_connection.enableReadEvent();
  stream->backend_connection.time_start = std::chrono::steady_clock::now();
}

void StreamManager::onClientWriteEvent(HttpStream *stream) {
  DEBUG_COUNTER_HIT(debug__::on_send_response);
  if (UNLIKELY(stream->client_connection.isCancelled())) {
    clearStream(stream);
    return;
  }
  Debug::logmsg(LOG_REMOVE, "\nClient write in\n\t\t buffer size: %d \n\t\t "
                            "Content length: %d \n\t\t message bytes left: %d",
                stream->backend_connection.buffer_size,
                stream->response.content_length,
                stream->response.message_bytes_left);
  //  StreamWatcher watcher(*stream);
  IO::IO_RESULT result = IO::IO_RESULT::ERROR;
  /* If the connection is pinned, then we need to write the buffer
   * content without applying any kind of modification. */
  if (stream->response.headers_sent &&
      (stream->upgrade.pinned_connection ||
       stream->response.message_bytes_left > 0 ||
       stream->chunked_status != http::CHUNKED_STATUS::CHUNKED_DISABLED)) {
    size_t written = 0;
    Debug::logmsg(LOG_DEBUG, "\nClient write in\n\t\t buffer size: %d \n\t\t "
                             "Content length: %d \n\t\t message bytes left: %d "
                             "\n\t\t written: %d",
                  stream->backend_connection.buffer_size,
                  stream->response.content_length,
                  stream->response.message_bytes_left, written);
    if (this->is_https_listener) {
      result = this->ssl_manager->handleWrite(
          stream->client_connection, stream->backend_connection.buffer,
          stream->backend_connection.buffer_size, written);

    } else {
      if (stream->backend_connection.buffer_size > 0)
        result = stream->backend_connection.writeTo(
            stream->client_connection.getFileDescriptor(), written);
#if ENABLE_ZERO_COPY
      else if (stream->backend_connection.splice_pipe.bytes > 0)
        result = stream->backend_connection.zeroWrite(
            stream->client_connection.getFileDescriptor(), stream->response);
#endif
    }
    switch (result) {
    case IO::IO_RESULT::SSL_HANDSHAKE_ERROR:
    case IO::IO_RESULT::SSL_NEED_HANDSHAKE: {
      if (!this->ssl_manager->handleHandshake(stream->client_connection)) {
        Debug::logmsg(LOG_INFO, "Handshake error with %s ",
                      stream->client_connection.getPeerAddress().c_str());
        clearStream(stream);
      }
      return;
    }
    case IO::IO_RESULT::FD_CLOSED:
    case IO::IO_RESULT::CANCELLED:
    case IO::IO_RESULT::FULL_BUFFER:
    case IO::IO_RESULT::ERROR:
      Debug::LogInfo("Error sending response ", LOG_DEBUG);
      clearStream(stream);
      return;
    case IO::IO_RESULT::SUCCESS: // TODO:: set request
    case IO::IO_RESULT::DONE_TRY_AGAIN:
      break;
    }
    if (this->is_https_listener)
      stream->backend_connection.buffer_size -= written;
    if (stream->response.message_bytes_left > 0) {
      stream->response.message_bytes_left -= written;
    }
    Debug::logmsg(LOG_DEBUG, "\nClient write out\n\t\t buffer size: %d \n\t\t "
                             "Content length: %d \n\t\t message bytes left: %d "
                             "\n\t\t written: %d",
                  stream->backend_connection.buffer_size,
                  stream->response.content_length,
                  stream->response.message_bytes_left, written);
    stream->backend_connection.enableReadEvent();
    stream->client_connection.enableReadEvent();
    return;
  }

  if (stream->backend_connection.buffer_size == 0)
    return;

  if (this->is_https_listener) {
    result = ssl_manager->handleDataWrite(stream->client_connection,
                                          stream->backend_connection,
                                          stream->response);
  } else {
    result = stream->backend_connection.writeTo(stream->client_connection,
                                                stream->response);
  }
  switch (result) {
  case IO::IO_RESULT::SSL_HANDSHAKE_ERROR:
  case IO::IO_RESULT::SSL_NEED_HANDSHAKE: {
    if (!this->ssl_manager->handleHandshake(stream->client_connection)) {
      Debug::logmsg(LOG_INFO, "Handshake error with %s ",
                    stream->client_connection.getPeerAddress().c_str());
      clearStream(stream);
    }
    stream->client_connection.enableReadEvent();
    return;
  }
  case IO::IO_RESULT::FD_CLOSED:
  case IO::IO_RESULT::CANCELLED:
  case IO::IO_RESULT::FULL_BUFFER:
  case IO::IO_RESULT::ERROR:
    Debug::LogInfo("Error sending response ", LOG_DEBUG);
    clearStream(stream);
    return;
  case IO::IO_RESULT::SUCCESS:
  case IO::IO_RESULT::DONE_TRY_AGAIN:
    stream->response.headers_sent = true;
    break;

  default:
    Debug::LogInfo("Error sending data to client", LOG_DEBUG);
    clearStream(stream);
    return;
  }
  Debug::logmsg(LOG_DEBUG, "\nClient write out\n\t\t buffer size: %d \n\t\t "
                           "Content length: %d \n\t\t message bytes left: %d ",
                stream->backend_connection.buffer_size,
                stream->response.content_length,
                stream->response.message_bytes_left);
  if (stream->request.upgrade_header &&
      stream->request.connection_header_upgrade &&
      stream->response.http_status_code == 101) {
    stream->upgrade.pinned_connection = true;
    std::string upgrade_header_value;
    stream->request.getHeaderValue(http::HTTP_HEADER_NAME::UPGRADE,
                                   upgrade_header_value);
    if (http_info::upgrade_protocols.count(upgrade_header_value) > 0)
      stream->upgrade.protocol =
          http_info::upgrade_protocols.at(upgrade_header_value);
  }

  if (stream->backend_connection.buffer_size > 0)
    stream->client_connection.enableWriteEvent();
  else {
    stream->backend_connection.enableReadEvent();
    stream->client_connection.enableReadEvent();
  }
}

bool StreamManager::init(ListenerConfig &listener_config) {
  listener_config_ = listener_config;
  service_manager = ServiceManager::getInstance(listener_config);
  //  for (auto service_config = listener_config.services;
  //  for (auto service_config = listener_config.services;
  //       service_config != nullptr; service_config = service_config->next) {
  //    if (!service_config->disabled) {
  //      service_manager->addService(*service_config);
  //    } else {
  //      Debug::LogInfo("Backend " + std::string(service_config->name) +
  //                     " disabled in config file",
  //                 LOG_NOTICE);
  //    }
  //  }
  if (listener_config.ctx != nullptr ||
      !listener_config.ssl_config_file.empty()) {
    this->is_https_listener = true;
    ssl_manager = new ssl::SSLConnectionManager();
    this->is_https_listener = ssl_manager->init(listener_config);
  }
  return true;
}

/** Clears the HttpStream. It deletes all the timers and events. Finally,
 * deletes the HttpStream.
 */
void StreamManager::clearStream(HttpStream *stream) {

  // TODO:: add connection closing reason for logging purpose
  if (stream == nullptr) {
    return;
  }
  Debug::logmsg(LOG_DEBUG, "Clearing stream ");

  if (stream->backend_connection.buffer_size > 0
#if ENABLE_ZERO_COPY
      || stream->backend_connection.splice_pipe.bytes > 0
#endif
      ) {
    // TODO:: remove and create enum with READY_TO_SEND_RESPONSE
    stream->backend_connection.disableEvents();
    return;
  }
  logSslErrorStack();
  if (stream->timer_fd.getFileDescriptor() > 0) {
    deleteFd(stream->timer_fd.getFileDescriptor());
    stream->timer_fd.unset();
    timers_set[stream->timer_fd.getFileDescriptor()] = nullptr;
    timers_set.erase(stream->timer_fd.getFileDescriptor());
  }
  if (stream->client_connection.getFileDescriptor() > 0) {
    deleteFd(stream->client_connection.getFileDescriptor());
    streams_set[stream->client_connection.getFileDescriptor()] = nullptr;
    streams_set.erase(stream->client_connection.getFileDescriptor());
    DEBUG_COUNTER_HIT(debug__::on_client_disconnect);
  }
  if (stream->backend_connection.getFileDescriptor() > 0) {
    if (stream->backend_connection.isConnected())
      stream->backend_connection.getBackend()->decreaseConnection();
    deleteFd(stream->backend_connection.getFileDescriptor());
    streams_set[stream->backend_connection.getFileDescriptor()] = nullptr;
    streams_set.erase(stream->backend_connection.getFileDescriptor());
    DEBUG_COUNTER_HIT(debug__::on_backend_disconnect);
  }
  delete stream;
}

void StreamManager::setListenSocket(int fd) {
  listener_connection.setFileDescriptor(fd);
}
