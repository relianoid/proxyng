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

my $configdir = &getGlobalConfiguration('configdir');

=begin nd
Function: runGSLBFarmCreate

	Create a gslb farm

Parameters:
	vip - Virtual IP
	port - Virtual port
	farmname - Farm name

Returns:
	Integer - Error code: 0 on success or different of 0 on failure
=cut
sub runGSLBFarmCreate    # ($vip,$vip_port,$farm_name)
{
	my ( $fvip, $fvipp, $fname ) = @_;

	require Zevenet::Farm::Core;
	require Zevenet::Net::Util;
	require Zevenet::GSLB::Config;

	# get a control port not used
	my $httpport;
	my @gslb_ports = ();
	my @gslb_farms = &getFarmsByType( 'gslb' );
	push @gslb_ports, &getGSLBControlPort( $_ ) for @gslb_farms;
	do
	{
		$httpport = &getRandomPort();
	} while ( grep( /^$httpport$/, @gslb_ports ) );

	my $type     = "gslb";
	my $ffile    = &getFarmFile( $fname );
	my $output   = -1;
	if ( $ffile != -1 )
	{
		# the farm name already exists
		$output = -2;
		return $output;
	}

	my $farm_path = "$configdir/${fname}_${type}\.cfg";
	&zenlog( "running 'Create' for $fname farm $type in path $farm_path ", "info", "GSLB" );

	mkdir "$farm_path";
	mkdir "$farm_path\/etc";
	mkdir "$farm_path\/etc\/zones";
	mkdir "$farm_path\/etc\/plugins";
	mkdir "$farm_path\/var";
	mkdir "$farm_path\/var/lib";

	# create admin_state file so there is no warning about the missing file
	open ( my $state_file, ">", "$configdir\/$fname\_$type.cfg\/var\/lib\/admin_state" );
	close $state_file;

	open ( my $file, ">", "$configdir\/$fname\_$type.cfg\/etc\/config" );
	print $file ";up\n"
	  . "options => {\n"
	  . "   listen = $fvip\n"
	  . "   dns_port = $fvipp\n"
	  . "   http_port = $httpport\n"
	  . "   http_listen = 127.0.0.1\n"
	  . "   zones_rfc1035_auto = true\n"
	  . "   run_dir = $configdir\/$fname\_$type.cfg\/var\/run\n"
	  . "   state_dir = $configdir\/$fname\_$type.cfg\/var\/lib\n"
	  . "}\n\n";
	print $file "service_types => { \n\n}\n\n";
	print $file
	  "plugins => { \n\textmon => { helper_path => \"/usr/local/zevenet/app/gdnsd/gdnsd_extmon_helper\" },\n}\n\n";
	close $file;

	include 'Zevenet::Farm::GSLB::Action';

	#run farm
	my $exec = &getGSLBStartCommand( $fname );

	&zenlog( "running $exec", "info", "GSLB" );
	require Zevenet::System;
	zsystem( "$exec > /dev/null 2>&1" );

	#TODO
	#$output = $?;
	$output = 0;

	if ( $output != 0 )
	{
		&runFarmDelete( $fname );
	}
	return $output;
}

1;
