//
// Created by abdess on 4/9/18.
//
#pragma once

#include <netdb.h>
#include <atomic>
#include "../config/pound_struct.h"
#include "../ctl/ControlManager.h"
#include "../ctl/ctl.h"
#include "../ctl/observer.h"
#include "../debug/Debug.h"
#include "../util/utils.h"
#include "../stats/backend_stats.h"
#include "../json/JsonDataValue.h"
#include "../json/JsonDataValueTypes.h"
#include "../json/jsonparser.h"
#include "../ssl/SSLConnectionManager.h"

/** The enum Backend::BACKEND_STATUS defines the status of the Backend. */
enum class BACKEND_STATUS {
  /** There is no Backend, used for first assigned backends. */
  NO_BACKEND = -1,
  /** The Backend is up. */
  BACKEND_UP = 0,
  /** The Backend is down. */
  BACKEND_DOWN,
  /** The Backend is disabled. */
  BACKEND_DISABLED
};

/** The enum Backend::BACKEND_TYPE defines the type of the Backend. */
enum class BACKEND_TYPE {
  /** Remote backend. */
  REMOTE,
  /** Emergency backend. */
  EMERGENCY_SERVER,
  /** Redirect backend. */
  REDIRECT,
  /** Backend used for the cache system. */
  CACHE_SYSTEM,
};
using namespace Statistics;
using namespace json;
using namespace ssl;

/**
 * @class Backend backend.h "src/service/backend.h"
 *
 * @brief The Backend class contains the configuration parameters set in the
 * backend section of the configuration file.
 */
class Backend : public CtlObserver<ctl::CtlTask, std::string>, public BackendInfo{
public:
  Backend();
  ~Backend();
  /** Backend status using the Backend::BACKEND_STATUS enum. */
  std::atomic<BACKEND_STATUS> status;
  /** Backend type using the Backend::BACKEND_TYPE enum. */
  BACKEND_TYPE backend_type;
  /** BackendConfig parameters from the backend section. */
  BackendConfig backend_config;
  /** Backend Address as a addrinfo type. */
  addrinfo *address_info{};
  /** Backend id. */
  int backend_id;
  /** Backend name. */
  std::string name;
  /** Backend weight, used for the balancing algorithms. */
  int weight;
  /** Backend Address as a std::string type. */
  std::string address;
  /** Backend port. */
  int port;
  /** Backend key if set in the configuration. */
  std::string bekey;
  /** Connection timeout time parameter. */
  int conn_timeout{};
  /** Response timeout time parameter. */
  int response_timeout{};
  /** SSL_CTX if the Backend is HTTPS. */
  SSL_CTX *ctx;
  bool cut;
  /** SSLConnectionManager used by the backend to manage all the HTTPS
   * connections. */
  SSLConnectionManager ssl_manager;
  //  bool disabled;

  /**
   * @brief Checks if the Backend still alive.
   */
  void doMaintenance();

  /**
   * @brief This function handles the @p tasks received with the API format.
   *
   * It calls the needed functions depending on the @p task received. The task
   * must be a API formatted request.
   *
   * @param task to check.
   * @return json formatted string with the result of the operation.
   */
  std::string handleTask(ctl::CtlTask &task) override;

  /**
   * @brief Checks if the Backend should handle the @p task.
   *
   * @param task to check.
   * @return true if should handle the task, false if not.
   */
  bool isHandler(ctl::CtlTask &task) override;

  /**
   * @brief Generates a JsonObject with all the Backend information.
   * @return JsonObject with the Backend information.
   */
  std::unique_ptr<JsonObject> getBackendJson();
  int nf_mark;
};
