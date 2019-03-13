//
// Created by abdess on 1/18/19.
//

#include "SSLConnectionManager.h"
#include "../util/common.h"
#include <openssl/err.h>

using namespace ssl;

bool SSLConnectionManager::init(SSLContext &context) {
  // TODO:: not impelemented
  return false;
}

bool SSLConnectionManager::init(const ListenerConfig &listener_config) {
//  CRYPTO_set_mem_debug(1);
//  CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_ON);
  if (listener_config.ctx != nullptr) {
    if (ssl_context != nullptr)
      delete ssl_context;
    ssl_context = new SSLContext();
    if (!listener_config.ssl_config_file.empty()) {
      if (!ssl_context->loadOpensslConfig(listener_config.ssl_config_file, listener_config.ctx->ctx))
        exit(EXIT_FAILURE);
    }
    return ssl_context->init(listener_config);
  }
  return false;
}

bool SSLConnectionManager::initSslConnection(Connection &ssl_connection,
                                             bool client_mode) {
  if (ssl_connection.ssl != nullptr) {
    SSL_shutdown(ssl_connection.ssl);
    SSL_free(ssl_connection.ssl);
  }
  ssl_connection.ssl = SSL_new(ssl_context->ssl_ctx);
  if (ssl_connection.ssl == nullptr) {
    Debug::logmsg(LOG_ERR, "SSL_new failed");
    return false;
  }
  int r = SSL_set_fd(ssl_connection.ssl, ssl_connection.getFileDescriptor());
  if (!r) {
    Debug::logmsg(LOG_ERR, "SSL_set_fd failed");
    return false;
  }
  /*
   * SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER :
   *   This flags allows us to retry the write
   *   operation with different parameters, i.e., a different buffer and size,
   *so long as the original data is still contained in the new buffer.
   *SSL_MODE_ENABLE_PARTIAL_WRITE:
   *   Allow partially complete writes to count as successes.
   */
  //  SSL_set_mode(ssl_connection.ssl, SSL_MODE_ENABLE_PARTIAL_WRITE |
  //                                       SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);

  Debug::logmsg(LOG_DEBUG, "SSL_HANDSHAKE: SSL_set_accept_state for fd %d",
                ssl_connection.getFileDescriptor());
  // let the SSL object know it should act as server
  !client_mode ? SSL_set_accept_state(ssl_connection.ssl)
               : SSL_set_connect_state(ssl_connection.ssl);
  return true;
}

bool SSLConnectionManager::initSslConnection_BIO(Connection &ssl_connection,
                                                 bool client_mode) {
  if (ssl_connection.ssl != nullptr) {
    SSL_shutdown(ssl_connection.ssl);
    SSL_free(ssl_connection.ssl);
  }
  ssl_connection.ssl = SSL_new(ssl_context->ssl_ctx);
  if (ssl_connection.ssl == nullptr) {
    Debug::logmsg(LOG_ERR, "SSL_new failed");
    return false;
  }
//  SSL_set_mode( ssl_connection.ssl,
 //     SSL_MODE_ENABLE_PARTIAL_WRITE | // enablle return if not all buffer has
          // been writen to the underlying socket,
          // need to check for sizes after writes
//          SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);
  ssl_connection.sbio =
      BIO_new_socket(ssl_connection.getFileDescriptor(), BIO_CLOSE);
  BIO_set_nbio(ssl_connection.sbio, 1);
  SSL_set_bio(ssl_connection.ssl, ssl_connection.sbio, ssl_connection.sbio);
  ssl_connection.io = BIO_new(BIO_f_buffer());
  ssl_connection.ssl_bio = BIO_new(BIO_f_ssl());
  BIO_set_nbio( ssl_connection.io, 1);
  BIO_set_nbio(ssl_connection.ssl_bio, 1); //set BIO non blocking
  BIO_set_ssl(ssl_connection.ssl_bio, ssl_connection.ssl, BIO_CLOSE);
  BIO_push(ssl_connection.io, ssl_connection.ssl_bio);
  Debug::logmsg(LOG_DEBUG, "SSL_HANDSHAKE: SSL_set_accept_state for fd %d",
                ssl_connection.getFileDescriptor());
  // let the SSL object know it should act as server
  !client_mode ? SSL_set_accept_state(ssl_connection.ssl)
               : SSL_set_connect_state(ssl_connection.ssl);
  return true;
}

void SSLConnectionManager::setSslInfoCallback(Connection &ssl_connection,
                                              SslInfoCallback callback) {
  // TODO::SSL implement
  // SSL_set_info_callback(ssl_connection.ssl_context, callback);
}

IO::IO_RESULT SSLConnectionManager::handleDataRead(Connection &ssl_connection) {
  if (!ssl_connection.ssl_connected) {
    return IO::IO_RESULT::SSL_NEED_HANDSHAKE;
  }
  Debug::logmsg(LOG_DEBUG, "> handleRead");
  int rc = -1;
  int bytes_read = 0;
  for (;;) {
    rc = BIO_read(ssl_connection.io,
                  ssl_connection.buffer + ssl_connection.buffer_size,
                  static_cast<int>(MAX_DATA_SIZE - ssl_connection.buffer_size));
    Debug::logmsg(LOG_DEBUG, "BIO_read return code %d buffer size %d", rc,
                  ssl_connection.buffer_size);
    if (rc == 0) {
      if (bytes_read > 0)
        return IO::IO_RESULT::SUCCESS;
      else {
        return IO::IO_RESULT::ZERO_DATA;
      }
    }else
    if (rc < 0) {
      if (BIO_should_retry(ssl_connection.io)) {
        return IO::IO_RESULT::DONE_TRY_AGAIN;
      }
      return IO::IO_RESULT::ERROR;
    }
    bytes_read += rc;
    ssl_connection.buffer_size += static_cast<size_t>(rc);
    return IO::IO_RESULT::SUCCESS;
  }
}

IO::IO_RESULT SSLConnectionManager::handleWrite(Connection &ssl_connection,
                                                const char *data,
                                                size_t data_size,
                                                size_t &written) {
  if (!ssl_connection.ssl_connected) {
    return IO::IO_RESULT::SSL_NEED_HANDSHAKE;
  }
  if (data_size == 0)
    return IO::IO_RESULT::ZERO_DATA;
  IO::IO_RESULT result;
  int rc = -1;
  //  // FIXME: Buggy, used just for test
  Debug::logmsg(LOG_DEBUG, "### IN handleWrite data size %d", data_size);
  written = 0;
  for (;;) {
    rc = BIO_write(ssl_connection.io, data + written, static_cast<int>(data_size - written));
    Debug::logmsg(LOG_DEBUG, "BIO_write return code %d writen %d", rc, written);
    if (rc == 0) {
      result = IO::IO_RESULT::DONE_TRY_AGAIN;
      break;
    } else if (rc < 0) {
      if (BIO_should_retry(ssl_connection.io)) {
        {
          result = IO::IO_RESULT::DONE_TRY_AGAIN;
          break;
        }
      } else {
        {
          result = IO::IO_RESULT::ERROR;
          break;
        }
      }
    } else {
      written += rc;
      if ((data_size - written) == 0) {
        result = IO::IO_RESULT::SUCCESS;
        break;
      };
    }
  }
  BIO_flush(ssl_connection.io);

  Debug::logmsg(LOG_DEBUG, "### IN handleWrite data write: %d ssl error: %s",
                data_size, IO::getResultString(result).c_str());
  return result;
}

bool SSLConnectionManager::handleHandshake(Connection &ssl_connection) {
  if (ssl_connection.ssl == nullptr) {
    if (!initSslConnection_BIO(ssl_connection)) {
      return false;
    }
  }
  int r = SSL_do_handshake(ssl_connection.ssl); //TODO:: Memory leak!! check heaptrack
  if (r == 1) {
    ssl_connection.ssl_connected = true;
    Debug::logmsg(LOG_DEBUG, "SSL_HANDSHAKE: ssl connected fd %d",
                  ssl_connection.getFileDescriptor());
    ssl_connection.enableReadEvent();
    return true;
  }
  int err = SSL_get_error(ssl_connection.ssl, r);
  if (err == SSL_ERROR_WANT_WRITE) {
    Debug::logmsg(LOG_DEBUG, "SSL_HANDSHAKE: return want write set events %d",
                  ssl_connection.getFileDescriptor());
    ssl_connection.enableWriteEvent();

  } else if (err == SSL_ERROR_WANT_READ) {
    Debug::logmsg(LOG_DEBUG, "SSL_HANDSHAKE: Want read, fd %d",
                  ssl_connection.getFileDescriptor());
    ssl_connection.enableReadEvent();

  } else {
    Debug::logmsg(LOG_ERR,
                  "SSL_do_handshake return %d error %d errno %d msg %s", r, err,
                  errno, strerror(errno));
    //ERR_print_errors(ssl_context->error_bio);
    return false;
  }
  return true;
}
SSLConnectionManager::~SSLConnectionManager() {
  if (ssl_context != nullptr) {
    delete ssl_context;
  }
}

SSLConnectionManager::SSLConnectionManager() : ssl_context(nullptr) {}

IO::IO_RESULT
SSLConnectionManager::getSslErrorResult(SSL *ssl_connection_context, int &rc) {
  rc = SSL_get_error(ssl_connection_context, rc);
  switch (rc) {
  case SSL_ERROR_NONE:return IO::IO_RESULT::SUCCESS;
  case SSL_ERROR_WANT_READ: /* We need more data to finish the frame. */
    return IO::IO_RESULT::DONE_TRY_AGAIN;
  case SSL_ERROR_WANT_WRITE: {
    // Warning - Renegotiation is not possible in a TLSv1.3 connection!!!!
    // handle renegotiation, after a want write ssl
    // error,
    Debug::logmsg(LOG_NOTICE,
                  "Renegotiation of SSL connection requested by peer");
    return IO::IO_RESULT::SSL_WANT_RENEGOTIATION;
  }
  case SSL_ERROR_SSL:Debug::logmsg(LOG_ERR, "corrupted data detected while reading");
    logSslErrorStack();
  case SSL_ERROR_ZERO_RETURN: /* Received a SSL close_notify alert.The operation
failed due to the SSL session being closed. The
underlying connection medium may still be open.  */
  default:
    Debug::logmsg(LOG_ERR, "SSL_read failed with error %s.",
                  getErrorString(rc));
    return IO::IO_RESULT::ERROR;
  }
}
IO::IO_RESULT SSLConnectionManager::sslRead(Connection &ssl_connection) {

  if (!ssl_connection.ssl_connected) {
    return IO::IO_RESULT::SSL_NEED_HANDSHAKE;
  }
  Debug::logmsg(LOG_DEBUG, "> handleRead");
  IO::IO_RESULT result = IO::IO_RESULT::ERROR;
  int rc = -1;
  do {
    rc = BIO_read(ssl_connection.io,
                  ssl_connection.buffer + ssl_connection.buffer_size,
                  static_cast<int>(MAX_DATA_SIZE -
                      ssl_connection.buffer_size));
    if (rc > 0) {
      ssl_connection.buffer_size += static_cast<size_t>(rc);
      result = IO::IO_RESULT::SUCCESS;
    } else if (BIO_should_retry(ssl_connection.io))
      result = IO::IO_RESULT::DONE_TRY_AGAIN;
  } while (rc > 0);

  int ssle = SSL_get_error(ssl_connection.ssl, rc);
  if (rc < 0 && ssle != SSL_ERROR_WANT_READ) {
    Debug::logmsg(LOG_DEBUG, "SSL_read return %d error %d errno %d msg %s",
                  rc,
                  ssle, errno, strerror(errno));
    result = IO::IO_RESULT::DONE_TRY_AGAIN; // TODO::  check want read
  }
  if (rc == 0) {
    if (ssle == SSL_ERROR_ZERO_RETURN)
      Debug::logmsg(LOG_NOTICE, "SSL has been shutdown.");
    else
      Debug::logmsg(LOG_NOTICE, "Connection has been aborted.");
    result = IO::IO_RESULT::FD_CLOSED;
  }
  return result;
}
IO::IO_RESULT SSLConnectionManager::sslWrite(Connection &ssl_connection,
                                             const char *data,
                                             size_t data_size,
                                             size_t &written) {
  if (!ssl_connection.ssl_connected) {
    return IO::IO_RESULT::SSL_NEED_HANDSHAKE;
  }
  if (data_size == 0)
    return IO::IO_RESULT::ZERO_DATA;
  IO::IO_RESULT result;
  int sent = 0;
  int rc = -1;
  //  // FIXME: Buggy, used just for test
 // Debug::logmsg(LOG_DEBUG, "### IN handleWrite data size %d", data_size);
  do {
    rc = SSL_write(ssl_connection.ssl, data + sent,
                   static_cast<int>(data_size - sent)); //, &written);
    if (rc > 0)
      sent += rc;
    //Debug::logmsg(LOG_DEBUG, "BIO_write return code %d sent %d", rc, sent);
  } while (rc > 0 && rc < (data_size - sent));

  if (sent > 0) {
    written = static_cast<size_t>(sent);
    return IO::IO_RESULT::SUCCESS;
  }
  int ssle = SSL_get_error(ssl_connection.ssl, rc);
  if (rc < 0 && ssle != SSL_ERROR_WANT_WRITE) {
    // Renegotiation is not possible in a TLSv1.3 connection
    Debug::logmsg(LOG_DEBUG, "SSL_read return %d error %d errno %d msg %s",
                  rc,
                  ssle, errno, strerror(errno));
    return IO::IO_RESULT::DONE_TRY_AGAIN;
  }
  if (rc == 0) {
    if (ssle == SSL_ERROR_ZERO_RETURN)
      Debug::logmsg(LOG_NOTICE, "SSL connection has been shutdown.");
    else
      Debug::logmsg(LOG_NOTICE, "Connection has been aborted.");
    return IO::IO_RESULT::FD_CLOSED;
  }
  return IO::IO_RESULT::ERROR;;
}
/*
bool SSLConnectionManager::handleBioHandshake(Connection &ssl_connection) {
  if (ssl_connection.ssl == nullptr) {
    if (!initSslConnection_BIO(ssl_connection)) {
      return false;
    }
  }
  int res =BIO_do_handshake(ssl_connection.io);
  if(res <= 0) {
   return BIO_should_retry(ssl_connection.io) ? true : false;
  } else {
    if((ssl_connection.x509 = SSL_get_peer_certificate(ssl_connection.ssl)) != NULL && ssl_context->listener_config.clnt_check < 3
        && SSL_get_verify_result(ssl_connection.ssl) != X509_V_OK) {
      logmsg(LOG_NOTICE, "Bad certificate from %s", ssl_connection.getPeerAddress().c_str());
      return false;
    }
  }
}
*/