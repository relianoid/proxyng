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
Function: getFarmType

	Get the farm type for a farm
	 
Parameters:
	farmname - Farm name

Returns:
	String - "http", "https", "datalink", "l4xnat", "gslb" or 1 on failure

NOTE:
	Generic function

=cut
sub getFarmType    # ($farm_name)
{
	my ( $farm_name ) = @_;

	my $farm_filename = &getFarmFile( $farm_name );

	if ( $farm_filename =~ /^$farm_name\_pound.cfg/ )
	{
		use File::Grep qw( fgrep );

		if ( fgrep { /ListenHTTPS/ } "$configdir/$farm_filename" ) {
			return "https";
		}
		else {
			return "http";
		}
	}
	elsif ( $farm_filename =~ /^$farm_name\_datalink.cfg/ )
	{
		return "datalink";
	}
	elsif ( $farm_filename =~ /^$farm_name\_l4xnat.cfg/ )
	{
		return "l4xnat";
	}
	elsif ( $farm_filename =~ /^$farm_name\_gslb.cfg/ )
	{
		return "gslb";
	}

	return 1;
}

=begin nd
Function: getFarmFile

	Returns farm file name
	 
Parameters:
	farmname - Farm name

Returns:
	String - file name or -1 on failure
	
NOTE:
	Generic function

=cut
sub getFarmFile    # ($farm_name)
{
	my ( $farm_name ) = @_;

	opendir ( my $dir, "$configdir" ) || return -1;
	my @farm_files =
	  grep {
		     /^$farm_name\_.*\.cfg/
		  && !/^$farm_name\_.*guardian\.conf/
		  && !/^$farm_name\_status.cfg/
	  } readdir ( $dir );
	closedir $dir;

	if ( @farm_files )
	{
		return $farm_files[0];
	}
	else
	{
		return -1;
	}
}

=begin nd
Function: getFarmName

	Returns farms configuration filename list
		
Parameters:
	file - Farm file

Returns:
	String - farm name
	
NOTE:
	Generic function
	
=cut
sub getFarmName    # ($farm_filename)
{
	my $farm_filename = shift;

	my @filename_split = split ( "_", $farm_filename );

	return $filename_split[0];
}

=begin nd
Function: getFarmList

	Returns farms configuration filename list
		
Parameters:
	none - .

Returns:
	Array - List of configuration files
	
NOTE:
	Generic function
	
=cut
sub getFarmList    # ()
{
	opendir ( DIR, $configdir );
	my @files1 = grep ( /\_pound.cfg$/, readdir ( DIR ) );
	closedir ( DIR );

	opendir ( DIR, $configdir );
	my @files2 = grep ( /\_datalink.cfg$/, readdir ( DIR ) );
	closedir ( DIR );

	opendir ( DIR, $configdir );
	my @files3 = grep ( /\_l4xnat.cfg$/, readdir ( DIR ) );
	closedir ( DIR );

	opendir ( DIR, $configdir );
	my @files4 = grep ( /\_gslb.cfg$/, readdir ( DIR ) );
	closedir ( DIR );

	my @files = ( @files1, @files2, @files3, @files4 );

	return @files;
}

=begin nd
Function: getFarmsByType

	Get all farms of a type 
	 
Parameters:
	type - Farm type. The available options are "http", "https", "datalink", "l4xnat" or "gslb"

Returns:
	Array - List of farm name of a type

NOTE:
	Generic function

=cut
sub getFarmsByType    # ($farm_type)
{
	my ( $farm_type ) = @_;

	my @farm_names = ();

	opendir ( my $dir, "$configdir" ) || return -1;

  # gslb uses a directory, not a file
  # my @farm_files = grep { /^.*\_.*\.cfg/ && -f "$configdir/$_" } readdir ( $dir );
	my @farm_files = grep { /^.*\_.*\.cfg/ } readdir ( $dir );
	closedir $dir;

	foreach my $farm_filename ( @farm_files )
	{
		next if $farm_filename =~ /.*status.cfg/;
		my $farm_name = &getFarmName( $farm_filename );

		if ( &getFarmType( $farm_name ) eq $farm_type )
		{
			push ( @farm_names, $farm_name );
		}
	}

	return @farm_names;
}

=begin nd
Function: getFarmNameList

	Returns a list with the farm names.

Parameters:
	none - .

Returns:
	array - list of farm names.
=cut
sub getFarmNameList
{
	my @farm_names;    # output: returned list

	# take every farm filename
	require Zevenet::Farm::Core;
	foreach my $farm_filename ( &getFarmList() )
	{
		# add the farm name to the list
		push ( @farm_names, &getFarmName( $farm_filename ) );
	}

	return @farm_names;
}

1;
