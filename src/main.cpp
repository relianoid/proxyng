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

#include <csetjmp>
#include <csignal>
#include "config/config.h"
#include "config/global.h"
#include "ctl/control_manager.h"
#include "stream/listener_manager.h"
#include "util/system.h"
#include "../zcutils/zcutils.h"
#include <sys/wait.h>

static jmp_buf jmpbuf;

std::shared_ptr<SystemInfo> SystemInfo::instance = nullptr;
std::once_flag terminate_flag;
void cleanExit()
{
	closelog();
}

void handleInterrupt(int sig)
{
	zcu_log_print(LOG_ERR, "[%s] received", ::strsignal(sig));
	switch (sig) {
	case SIGQUIT:
	case SIGTERM:
		::_exit(EXIT_SUCCESS);
		return;
	case SIGINT:
	case SIGHUP: {
		auto cm = ctl::ControlManager::getInstance();
		cm->stop();
		::_exit(EXIT_SUCCESS);
		break;
	}
	case SIGABRT:
		zcu_bt_print_symbols();
		zcu_bt_print();
		::_exit(EXIT_FAILURE);
	case SIGSEGV: {
		zcu_bt_print_symbols();
		zcu_bt_print();
		::_exit(EXIT_FAILURE);
	}
	case SIGUSR1: // Release free heap memory
		::malloc_trim(0);
		break;
	case SIGUSR2: {
		auto cm = ctl::ControlManager::getInstance();
		cm->sendCtlCommand(ctl::CTL_COMMAND::UPDATE,
				   ctl::CTL_HANDLER_TYPE::LISTENER_MANAGER,
				   ctl::CTL_SUBJECT::CONFIG);
	}
	default: {
		//  ::longjmp(jmpbuf, 1);
	}
	}
}

int main(int argc, char *argv[])
{
	/* worker pid */
	static pid_t son = 0;
	int parent_pid;

	//  debug::EnableBacktraceOnTerminate();
	Time::updateTime();
	static ListenerManager listener;
	auto control_manager = ctl::ControlManager::getInstance();
	if (setjmp(jmpbuf)) {
		// we are in signal context here
		control_manager->stop();
		listener.stop();
		exit(EXIT_SUCCESS);
	}

	zcu_log_print(LOG_NOTICE, "zproxy starting...");

	Config config(true);
	auto start_options =
		global::StartOptions::parsePoundOption(argc, argv, true);
	if (start_options == nullptr)
		std::exit(EXIT_FAILURE);
	auto parse_result = config.init(*start_options);
	if (!parse_result) {
		fprintf(stderr, "error parsing configuration file %s",
			start_options->conf_file_name.data());
		std::exit(EXIT_FAILURE);
	}

	if (start_options->check_only) {
		std::exit(EXIT_SUCCESS);
	}

	zcu_log_set_level(config.listeners->log_level);

	config.setAsCurrent();

	// Syslog initialization
	if (config.daemonize) {
		if (!Environment::daemonize()) {
			fprintf(stderr, "error: daemonize failed");
			closelog();
			return EXIT_FAILURE;
		}
	}

	//  /* block all signals. we take signals synchronously via signalfd */
	//  sigset_t all;
	//  sigfillset(&all);
	//  sigprocmask(SIG_SETMASK,&all,NULL);

	::signal(SIGPIPE, SIG_IGN);
	::signal(SIGINT, handleInterrupt);
	::signal(SIGTERM, handleInterrupt);
	::signal(SIGABRT, handleInterrupt);
	::signal(SIGHUP, handleInterrupt);
	::signal(SIGSEGV, handleInterrupt);
	::signal(SIGUSR1, handleInterrupt);
	::signal(SIGUSR2, handleInterrupt);
	::signal(SIGQUIT, handleInterrupt);
	::umask(077);
	::srandom(static_cast<unsigned int>(::getpid()));
	Environment::setUlimitData();

	/* record pid in file */
	if (!config.pid_name.empty()) {
		parent_pid = ::getpid();
		Environment::createPidFile(config.pid_name, parent_pid, -1);
	}
	/* chroot if necessary */
	if (!config.root_jail.empty()) {
		Environment::setChrootRoot(config.root_jail);
	}

	/*Set process user and group */
	if (!config.user.empty()) {
		Environment::setUid(std::string(config.user));
	}

	if (!config.group.empty()) {
		Environment::setGid(std::string(config.group));
	}

	for (;;) {
		if (config.daemonize) {
			if ((son = fork()) > 0) {
				// add pid to the file
				if (!config.pid_name.empty()) {
					Environment::createPidFile(
						config.pid_name, parent_pid,
						son);
				}

				int status;
				wait(&status);
				if (WIFEXITED(status)) {
					zcu_log_print(
						LOG_ERR,
						"MONITOR: worker exited %d, restarting...",
						WEXITSTATUS(status));
					// force reload to get the latest changes of the config file
					listener.reloadConfigFile();
				}
			}
		}
		if (son == 0) {
			if (!config.ctrl_name.empty() ||
			    !config.ctrl_ip.empty()) {
				control_manager->init(config);
				control_manager->start();
			}
			zcu_log_print(LOG_DEBUG, "initializing listeners");
			for (auto listener_conf = config.listeners;
			     listener_conf != nullptr;
			     listener_conf = listener_conf->next) {
				if (!listener.addListener(listener_conf)) {
					zcu_log_print(
						LOG_ERR,
						"error initializing listener socket");
					return EXIT_FAILURE;
				}
			}
			listener.start();
			// execute the loop once if it is not working in daemonize mode
			if (!config.daemonize)
				break;
		}
	}

	listener.stop();
	control_manager->stop();
	cleanExit();
	std::exit(EXIT_SUCCESS);
	//return EXIT_SUCCESS;
}
