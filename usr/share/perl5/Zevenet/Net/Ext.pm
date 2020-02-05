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
require Zevenet::Log;

# POST /interfaces/virtual Create a new virtual network interface
sub reloadNetplug    # ( $json_obj )
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $netplugd_srv = &getGlobalConfiguration( 'netplugd_srv' );

	my $err = &logAndRun( "$netplugd_srv force-reload" );

	return $err;
}

sub isManagementIP
{
	my $ip  = shift;
	my $out = "";

	include 'Zevenet::System::HTTP';
	include 'Zevenet::System::SSH';

	my $ssh  = ( &getSsh()->{ listen } eq $ip ) ? 1 : 0;
	my $http = ( &getHttpServerIp() eq $ip )    ? 1 : 0;

	if ( $ssh && $http )
	{
		$out =
		  "The IP '$ip' is been used as management interface for SSH and HTTP services.";
	}
	elsif ( $ssh )
	{
		$out = "The IP '$ip' is been used as management interface for SSH service.";
	}
	elsif ( $http )
	{
		$out = "The IP '$ip' is been used as management interface for HTTP service.";
	}

	return $out;
}

1;