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

use Zevenet::SNMP;

# GET /system/snmp
sub get_snmp
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $desc = "Get snmp";

	my $snmp = &getSnmpdConfig();
	$snmp->{ 'status' } = &getSnmpdStatus();

	&httpResponse(
				   { code => 200, body => { description => $desc, params => $snmp } } );
}

#  POST /system/snmp
sub set_snmp
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $json_obj = shift;

	my $desc = "Post snmp";

	require Zevenet::Net::Interface;
	my $ip_list = &getIpAddressList();
	push @{ $ip_list }, '*';

	my $params = {
				   "port" => {
							   'valid_format' => 'snmp_port',
							   'non_blank'    => 'true',
				   },
				   "status" => {
								 'values'    => ['true', 'false'],
								 'non_blank' => 'true',
				   },
				   "ip" => {
							 'values'    => $ip_list,
							 'non_blank' => 'true',
				   },
				   "community" => {
									'length'    => 32,
									'non_blank' => 'true',
				   },
				   "scope" => {
								'valid_format' => 'snmp_scope',
								'non_blank'    => 'true',
				   },
	};

	# Check allowed parameters
	my $error_msg = &checkZAPIParams( $json_obj, $params, $desc );
	return &httpErrorResponse( code => 400, desc => $desc, msg => $error_msg )
	  if ( $error_msg );

	my $snmp       = &getSnmpdConfig();
	my $status_cur = &getSnmpdStatus();

	my $status = $json_obj->{ 'status' } // $status_cur;
	my $port   = $json_obj->{ 'port' }   // $snmp->{ port };
	my $ip     = $json_obj->{ 'ip' }     // $snmp->{ ip };

	if ( ( $port ne $snmp->{ port } ) or ( $ip ne $snmp->{ ip } ) )
	{
		if ( $status eq 'true' and !&validatePort( $ip, $port, 'udp', undef, 'snmp' ) )
		{
			my $msg = "The '$ip' ip and '$port' port are in use.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}

	delete $json_obj->{ 'status' } if exists $json_obj->{ 'status' };
	foreach my $key ( keys %{ $json_obj } )
	{
		$snmp->{ $key } = $json_obj->{ $key };
	}

	my $error = &setSnmpdConfig( $snmp );
	if ( $error )
	{
		my $msg = "There was a error modifying ssh.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	if ( $status eq 'true' && $status_cur eq 'false' )
	{
		&setSnmpdStatus( 'true' );    # starting snmp
	}
	elsif ( $status eq 'false' && $status_cur eq 'true' )
	{
		&setSnmpdStatus( 'false' );    # stopping snmp
	}
	elsif ( $status ne 'false' && $status_cur ne 'false' )
	{
		&setSnmpdStatus( 'false' );    # stopping snmp
		&setSnmpdStatus( 'true' );     # starting snmp
	}

	$snmp->{ status } = &getSnmpdStatus();

	&httpResponse(
				   { code => 200, body => { description => $desc, params => $snmp } } );
}

1;

