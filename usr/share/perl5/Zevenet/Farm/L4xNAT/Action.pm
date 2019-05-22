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

use Zevenet::Nft;

=begin nd
Function: startL4Farm

	Run a l4xnat farm

Parameters:
	farm_name - Farm name
	writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:
	Integer - return 0 on success or different of 0 on failure

=cut

sub startL4Farm    # ($farm_name)
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $farm_name = shift;
	my $writeconf = shift // 0;

	require Zevenet::Farm::L4xNAT::Config;

	&zlog( "Starting farm $farm_name" ) if &debug == 2;

	my $status = 0;
	my $farm   = &getL4FarmStruct( $farm_name );

	&zenlog( "startL4Farm << farm_name:$farm_name" )
	  if &debug;

	&loadL4Modules( $$farm{ vproto } );

	$status = &startL4FarmNlb( $farm_name, $writeconf );
	if ( $status != 0 )
	{
		return $status;
	}

	&doL4FarmRules( "start", $farm_name );

	# Enable IP forwarding
	require Zevenet::Net::Util;
	&setIpForward( 'true' );

	if ( $farm->{ lbalg } eq 'leastconn' )
	{
		require Zevenet::Farm::L4xNAT::L4sd;
		&sendL4sdSignal();
	}

	return $status;
}

=begin nd
Function: stopL4Farm

	Stop a l4xnat farm

Parameters:
	farm_name - Farm name
	writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:
	Integer - return 0 on success or other value on failure

=cut

sub stopL4Farm    # ($farm_name)
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $farm_name = shift;
	my $writeconf = shift;
	my $pidfile   = &getL4FarmPidFile( $farm_name );

	require Zevenet::Farm::Core;
	require Zevenet::Farm::L4xNAT::Config;

	&zlog( "Stopping farm $farm_name" ) if &debug > 2;

	my $farm = &getL4FarmStruct( $farm_name );

	&doL4FarmRules( "stop", $farm_name );

	my $pid = &getNlbPid();
	if ( $pid <= 0 )
	{
		return 0;
	}

	my $status = &stopL4FarmNlb( $farm_name, $writeconf );

	unlink "$pidfile" if ( -e "$pidfile" );

	&unloadL4Modules( $$farm{ vproto } );

	if ( $farm->{ lbalg } eq 'leastconn' )
	{
		require Zevenet::Farm::L4xNAT::L4sd;
		&sendL4sdSignal();
	}

	return $status;
}

=begin nd
Function: setL4NewFarmName

	Function that renames a farm

Parameters:
	farmname - Farm name
	newfarmname - New farm name

Returns:
	Integer - return 0 on success or <> 0 on failure

=cut

sub setL4NewFarmName    # ($farm_name, $new_farm_name)
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $farm_name     = shift;
	my $new_farm_name = shift;
	my $output        = 0;

	require Tie::File;

	$output = &setL4FarmParam( 'name', "$new_farm_name", $farm_name );

	unlink "$configdir\/${farm_name}_l4xnat.cfg";

	return $output;
}

=begin nd
Function: loadL4NlbFarm

	Load farm configuration in nftlb

Parameters:
	farm_name - farm name configuration to be loaded

Returns:
	Integer - 0 on success or -1 on failure

=cut

sub loadL4FarmNlb    # ($farm_name)
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $farm_name = shift;

	require Zevenet::Farm::Core;

	my $farmfile = &getFarmFile( $farm_name );

	return 0 if ( !-e "$configdir/$farmfile" );

	return
	  &httpNlbRequest(
					   {
						 farm   => $farm_name,
						 method => "POST",
						 uri    => "/farms",
						 body   => qq(\@$configdir/$farmfile)
					   }
	  );
}

=begin nd
Function: startL4FarmNlb

	Start a new farm in nftlb

Parameters:
	farm_name - farm name to be started
	writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:
	Integer - 0 on success or -1 on failure

=cut

sub startL4FarmNlb    # ($farm_name)
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $farm_name = shift;
	my $writeconf = shift;

	require Zevenet::Farm::L4xNAT::Config;

	my $output =
	  &setL4FarmParam( ( $writeconf ) ? 'bootstatus' : 'status', "up", $farm_name );

	my $pidfile = &getL4FarmPidFile( $farm_name );

	if ( !-e "$pidfile" )
	{
		open my $fi, '>', "$pidfile";
		close $fi;
	}

	return $output;
}

=begin nd
Function: stopL4FarmNlb

	Stop an existing farm in nftlb

Parameters:
	farm_name - farm name to be started
	writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:
	Integer - 0 on success or -1 on failure

=cut

sub stopL4FarmNlb    # ($farm_name)
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $farm_name = shift;
	my $writeconf = shift;

	require Zevenet::Farm::Core;

	my $farmfile = &getFarmFile( $farm_name );

	my $out = &setL4FarmParam( ( $writeconf ) ? 'bootstatus' : 'status',
							   "down", $farm_name );

	return $out;
}

=begin nd
Function: getL4FarmPidFile

	Return the farm pid file

Parameters:
	farm_name - Name of the given farm

Returns:
	String - Pid file path or -1 on failure

=cut

sub getL4FarmPidFile
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my ( $farm_name ) = @_;

	my $piddir  = &getGlobalConfiguration( 'piddir' );
	my $pidfile = "$piddir/$farm_name\_l4xnat.pid";

	return $pidfile;
}

=begin nd
Function: sendL4NlbCmd

	Send the param to Nlb for a L4 Farm

Parameters:
	self - hash that includes hash_keys -> ( $farm, $backend, $file, $method, $body )

Returns:
	Integer - return code of the request command

=cut

sub sendL4NlbCmd
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $self    = shift;
	my $cfgfile = "";
	my $output  = -1;

	# load the configuration file first if the farm is down
	my $status = &getL4FarmStatus( $self->{ farm } );
	if ( $status ne "up" )
	{
		my $out = &loadL4FarmNlb( $self->{ farm } );
		return $out if ( $out != 0 );
	}

  # avoid farm configuration file destruction by asking nftlb only for modifications
	if ( $self->{ method } =~ /PUT/ )
	{
		my $file = "/tmp/nft_$$";

		$output = httpNlbRequest(
								  {
									method => "GET",
									uri    => "/farms/" . $self->{ farm },
									file   => "$file"
								  }
		);

		open my $fh, "<", $file;
		my $match = 0;
		while ( my $line = <$fh> )
		{
			if ( $line =~ /\"name\"\: \"$$self{ farm }\"/ )
			{
				$match = 1;
				last;
			}
		}
		close $fh;
		unlink ( $file );

		&loadL4FarmNlb( $self->{ farm } ) if ( !$match );
	}

	if ( $self->{ method } =~ /PUT|DELETE/ )
	{
		$cfgfile = $self->{ file };
		$self->{ file } = "";
	}

	if ( defined $self->{ backend } && $self->{ backend } ne "" )
	{
		$self->{ uri } =
		  "/farms/" . $self->{ farm } . "/backends/" . $self->{ backend };
	}
	else
	{
		$self->{ uri } = "/farms";
		$self->{ uri } = "/farms/" . $self->{ farm }
		  if ( $self->{ method } eq "DELETE" );
	}

	$output = &httpNlbRequest( $self );

	return $output if ( $self->{ method } eq "GET" or !defined $self->{ file } );

	if ( $self->{ method } =~ /PUT|DELETE/ )
	{
		$self->{ file } = $cfgfile;
	}

	$self->{ method } = "GET";
	$self->{ uri }    = "/farms/" . $self->{ farm };
	$self->{ body }   = "";

	$output = &httpNlbRequest( $self ) || $output;

	return $output;
}

1;
