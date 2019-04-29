#!/usr/bin/perl
###############################################################################
#
#    Zevenet Software License
#    This file is part of the Zevenet Load Balancer software package.
#
#    Copyright (C) 2014-today ZEVENET SL, Sevilla (Spain)
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

use strict;
use warnings;

my $configdir = &getGlobalConfiguration( 'configdir' );

=begin nd
Function: loadL4FarmModules

	Load L4farm system modules and conntrack

Parameters:
	none

Returns:
	Integer - 0 on success or any other value on failure

=cut

sub loadL4FarmModules
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $modprobe_bin = &getGlobalConfiguration( "modprobe" );
	my $cmd          = "$modprobe_bin nf_conntrack enable_hooks=1";
	my $error        = 0;

	$error += system ( "$cmd >/dev/null 2>&1" );

	return $error;
}

1;
