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

use Zevenet::Core;
use Zevenet::Lock;

include 'Zevenet::IPDS::WAF::Core';

=begin nd
Function: reloadWAFByFarm

	It reloads a farm to update the WAF configuration.

Parameters:
	Farm - It is the farm name

Returns:
	Integer - It returns 0 on success or another value on failure.

=cut

sub reloadWAFByFarm
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $farm = shift;
	my $err  = 0;
	require Zevenet::Farm::HTTP::Config;

	my $pound_ctl = &getGlobalConfiguration( 'poundctl' );
	my $socket    = &getHTTPFarmSocket( $farm );

	$err = &logAndRun( "$pound_ctl -c $socket -R" );

	return $err;
}

=begin nd
Function: addWAFsetToFarm

	It applies a WAF set to a HTTP farm.

Parameters:
	Farm - It is the farm name
	Set  - It is the WAF set name

Returns:
	Integer - It returns 0 on success or another value on failure.

=cut

sub addWAFsetToFarm
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $farm = shift;
	my $set  = shift;
	my $err  = 1;

	use File::Copy;
	require Zevenet::Farm::Core;

	my $set_file  = &getWAFSetFile( $set );
	my $farm_file = &getFarmFile( $farm );
	my $configdir = &getGlobalConfiguration( 'configdir' );
	my $farm_path = "$configdir/$farm_file";
	my $tmp_conf  = "$configdir/farm_http.tmp";
	my $pound     = &getGlobalConfiguration( 'pound' );

	my $lock_file = &getLockFile( $farm );
	my $lock_fh = &openlock( $lock_file, 'w' );

	copy( $farm_path, $tmp_conf );

	&ztielock( \my @filefarmhttp, $tmp_conf );

	# write conf
	my $flag_sets = 0;
	foreach my $line ( @filefarmhttp )
	{
		if ( $line =~ /^WafRules/ )
		{
			$flag_sets = 1;
		}
		elsif ( $line !~ /^WafRules/ and $flag_sets )
		{
			$err  = 0;
			$line = "WafRules	\"$set_file\"" . "\n" . $line;
			last;
		}

		# not found any waf directive
		elsif ( $line =~ /^\s*$/ )
		{
			$err  = 0;
			$line = "WafRules	\"$set_file\"" . "\n" . "\n";
			last;
		}
		elsif ( $line =~ /#HTTP\(S\) LISTENERS/ )
		{
			$err  = 0;
			$line = "WafRules	\"$set_file\"" . "\n" . $line;
			last;
		}
	}

	untie @filefarmhttp;

	# check config file
	my $cmd = "$pound -f $tmp_conf -c";
	$err = &logAndRun( $cmd );
	if ( $err )
	{
		unlink $tmp_conf;
		return $err;
	}

	# if there is not error, overwrite configfile
	move( $tmp_conf, $farm_path );

	# reload farm
	require Zevenet::Farm::Base;
	if ( &getFarmStatus( $farm ) eq 'up' and !$err )
	{
		$err = &reloadWAFByFarm( $farm );
	}

	close $lock_fh;

	return $err;
}

=begin nd
Function: removeWAFSetFromFarm

	It removes a WAF set from a HTTP farm.

Parameters:
	Farm - It is the farm name
	Set  - It is the WAF set name

Returns:
	Integer - It returns 0 on success or another value on failure.

=cut

sub removeWAFSetFromFarm
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $farm = shift;
	my $set  = shift;
	my $err  = 0;

	require Zevenet::Farm::Core;

	my $pound     = &getGlobalConfiguration( 'pound' );
	my $set_file  = &getWAFSetFile( $set );
	my $farm_file = &getFarmFile( $farm );
	my $configdir = &getGlobalConfiguration( 'configdir' );
	my $farm_path = "$configdir/$farm_file";

	my $lock_file = &getLockFile( $farm );
	my $lock_fh = &openlock( $lock_file, 'w' );

	# write conf
	$err = 1;
	&ztielock( \my @fileconf, $farm_path );

	my $index = 0;
	foreach my $line ( @fileconf )
	{
		if ( $line =~ /^WafRules\s+\"$set_file\"/ )
		{
			$err = 0;
			splice @fileconf, $index, 1;
			last;
		}
		$index++;
	}
	untie @fileconf;

	# This is a bugfix. Not to check WAF when it is deleting rules.

	# reload farm
	require Zevenet::Farm::Base;
	if ( &getFarmStatus( $farm ) eq 'up' and !$err )
	{
		$err = &reloadWAFByFarm( $farm );
	}

	close $lock_fh;

	return $err;
}

=begin nd
Function: reloadWAFByRule

	It reloads all farms where the WAF set is applied

Parameters:
	Set  - It is the WAF set name

Returns:
	Integer - It returns 0 on success or another value on failure.

=cut

sub reloadWAFByRule
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $set = shift;
	my $err;

	require Zevenet::Farm::Base;
	foreach my $farm ( &listWAFBySet( $set ) )
	{
		if ( &getFarmStatus( $farm ) eq 'up' )
		{
			if ( &reloadWAFByFarm( $farm ) )
			{
				$err++;
				&zenlog( "Error reloading the WAF in the farm $farm", "error", "waf" );
			}
		}
	}
	return $err;
}

# ???? add function to change wafbodysize. It is needed to restart
#~ my $bodysize = &getGlobalConfiguration( 'waf_body_size' );
#~ ... tener en cuenta que debe borrarse o comentarse la directiva si en
#~ globalconf esta vacia ... cambiar este parametro en el reload de la granja
#~ . Si cambia ... pedir un restart

1;
