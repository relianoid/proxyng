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

=begin nd
Function: getSystemGlobal

	Get the global settings of the system.

Parameters:
	none - .

Returns:
	Hash ref -
		ssyncd, shows if ssyncd is enabled "true" or disabled "false"
		duplicated_network, shows if the system will duplicate a network segment for each interface "true" or it will be applied only once in the system "false"
		arp_announce, the system will send a arg packet to the net when it is set up or stood up, "true". The system will not notice anything to the net when it is set up or stood up, "false"

=cut

sub getSystemGlobal
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $ssyncd_enabled = &getGlobalConfiguration( 'ssyncd_enabled' );
	my $duplicated_net = &getGlobalConfiguration( 'duplicated_net' );
	my $arp_announce   = &getGlobalConfiguration( 'arp_announce' );
	my $proxy          = &getGlobalConfiguration( 'proxy_ng' );

	my $out = {};
	$out->{ ssyncd }             = ( $ssyncd_enabled eq 'true' ) ? 'true' : 'false';
	$out->{ duplicated_network } = ( $duplicated_net eq 'true' ) ? 'true' : 'false';
	$out->{ arp_announce }       = ( $arp_announce eq 'true' )   ? 'true' : 'false';
	$out->{ proxy_new_generation } = ( $proxy eq 'true' ) ? 'true' : 'false';

	return $out;
}

=begin nd
Function: setSystemGlobal

	Get the global settings of the system.

Parameters:
	none - . Returns: 0 on success,
						2 if there was an error related to stop http farms
						another value on failure

Returns:
	Ingeger - Error code.

=cut

sub setSystemGlobal
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $global = shift;
	my $err    = 0;

	if ( exists $global->{ ssyncd } )
	{
		include 'Zevenet::Ssyncd';
		$err = &setSsyncd( $global->{ ssyncd } );
		return $err if $err;
	}

	if ( exists $global->{ duplicated_network } )
	{
		$err =
		  &setGlobalConfiguration( 'duplicated_net', $global->{ duplicated_network } );
		return $err if $err;
	}

	if ( exists $global->{ arp_announce } )
	{
		include 'Zevenet::Net::Util';
		$err =
		  ( $global->{ arp_announce } eq 'true' )
		  ? &setArpAnnounce()
		  : &unsetArpAnnounce();
		return $err if $err;
	}

	my $ng_val = &getGlobalConfiguration( 'proxy_ng' );
	if ( exists $global->{ proxy_new_generation }
		 and ( $ng_val ne $global->{ proxy_new_generation } ) )
	{
		require Zevenet::Farm::Core;
		require Zevenet::Farm::Base;
		require Zevenet::Farm::Action;

		my $ng   = $global->{ proxy_new_generation };
		my $base = ( $ng eq 'true' ) ? 'base_zproxy' : 'base_pound';
		my $bin  = ( $ng eq 'true' ) ? 'zproxy' : 'pound';
		my $ctl  = ( $ng eq 'true' ) ? 'zproxyctl' : 'poundctl';
		my $base = &getGlobalConfiguration( $base );
		my $bin  = &getGlobalConfiguration( $bin );
		my $ctl  = &getGlobalConfiguration( $ctl );
		$err = 0;

		# stop l7 farms
		my @farmsf = &getFarmsByType( 'http' );
		push @farmsf, &getFarmsByType( 'https' );
		my @farms_stopped;
		my $farm_err;

		foreach my $farmname ( @farmsf )
		{
			if ( &getFarmStatus( $farmname ) eq "up" )
			{
				$err = &runFarmStop( $farmname, "false" );
				if ( $err )
				{
					$err = 2;
					last;
				}
				else { push @farms_stopped, $farmname; }
			}
		}

		if ( !$err )
		{
			# set binary
			$err += &setGlobalConfiguration( 'base_proxy', $base );
			$err += &setGlobalConfiguration( 'proxy',      $bin );
			$err += &setGlobalConfiguration( 'proxyctl',   $ctl );
			$err += &setGlobalConfiguration( 'proxy_ng',   $ng ) if ( !$err );
		}

		# start l7 farms
		foreach my $farmname ( @farms_stopped )
		{
			my $farm_err = &runFarmStart( $farmname, "false" );
			$err = 3 if ( $farm_err and !$err );
		}
	}

	return $err;
}

1;