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

#include "zcu_backtrace.h"
#include <execinfo.h>
#include "zcu_common.h"
#include "zcu_log.h"

void zcu_bt_print_symbols()
{
    void *buffer[255];
    char **str;
    int i;
    const int calls = backtrace(buffer, sizeof(buffer) / sizeof(void *));

    backtrace_symbols_fd(buffer, calls, 1);

    str = backtrace_symbols(buffer, calls);
    if (!str) {
        zcu_log_print(LOG_ERR, "No backtrace strings found!");
        exit(EXIT_FAILURE);
    }

    for (i = 0; i < calls; i++)
        zcu_log_print(LOG_ERR, "Backtrace_symbol: %s", str[i]);

    free(str);
}
