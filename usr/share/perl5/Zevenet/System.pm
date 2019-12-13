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
Function: getTotalConnections

	Get the number of current connections on this appliance.

Parameters:
	none - .

Returns:
	integer - The number of connections.

See Also:
	zapi/v3/system_stats.cgi
=cut

sub getTotalConnections
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $conntrack = &getGlobalConfiguration( "conntrack" );
	my $conns     = `$conntrack -C`;
	$conns =~ s/(\d+)/$1/;
	$conns += 0;

	return $conns;
}

=begin nd
Function: indexOfElementInArray

	Get the index of the first position where an element if found in an array.

Parameters:
	searched_element - Element to search.
	array_ref        - Reference to the array to be searched.

Returns:
	integer - Zero or higher if the element was found. -1 if the element was not found. -2 if no array reference was received.

See Also:
	Zapi v3: <new_bond>
=cut

sub indexOfElementInArray
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $searched_element = shift;
	my $array_ref        = shift;

	if ( ref $array_ref ne 'ARRAY' )
	{
		return -2;
	}

	my @arrayOfElements = @{ $array_ref };
	my $index           = 0;

	for my $list_element ( @arrayOfElements )
	{
		if ( $list_element eq $searched_element )
		{
			last;
		}

		$index++;
	}

	# if $index is greater than the last element index
	if ( $index > $#arrayOfElements )
	{
		# return an invalid index
		$index = -1;
	}

	return $index;
}

=begin nd
Function: slurpFile

	It returns a file as a byte stream. It interpretes the '\n' character and it is not used to split the lines in different chains.

Parameters:
	none - .

Returns:
	String - The supportsave file name is returned.

=cut

sub slurpFile
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $path = shift;

	# Slurp: store an entire file in a variable.

	require Zevenet::Log;

	my $file;

	open ( my $fh, '<', $path );

	unless ( $fh )
	{
		my $msg = "Could not open $file: $!";

		&zenlog( $msg );
		die $msg;
	}

	{
		local $/ = undef;
		$file = <$fh>;
	}

	close $fh;

	return $file;
}

=begin nd
Function: getSpaceFree

	It gets the free space that contains a partition. The partition is calculated
	from a directory

Parameters:
	directroy - directory to know the free space

Returns:
	Integer - Number of bytes free in the partition

=cut

sub getSpaceFree
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $dir      = shift;
	my $df_bin   = &getGlobalConfiguration( "df_bin" );
	my $sed_bin  = &getGlobalConfiguration( "sed_bin" );
	my $cut_bin  = &getGlobalConfiguration( "cut_bin" );
	my $grep_bin = &getGlobalConfiguration( "grep_bin" );

	my $cmd =
	  "$df_bin -B1 $dir | $grep_bin -Ev '^(Filesystem|\$)' | $sed_bin -E 's/\\s+/ /g' | $cut_bin -d ' ' -f4";
	my $size = `$cmd`;
	chomp $size;

	&zenlog( "Dir: $dir, Free space (Bytes): $size", "debug2" );

	return $size;
}

=begin nd
Function: getSpaceFormatHuman

	It converts a number of bytes to human format, converting Bytes to KB, MB or GB

Parameters:
	Bytes - Number of bytes

Returns:
	String - String with size and its units

=cut

sub getSpaceFormatHuman
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $size = shift;

	my $human = $size;
	my $unit  = 'B';

	if ( $human > 1024 )
	{
		$human = $human / 1024;
		$unit  = "KB";
	}
	if ( $human > 1024 )
	{
		$human = $human / 1024;
		$unit  = "MB";
	}
	if ( $human > 1024 )
	{
		$human = $human / 1024;
		$unit  = "GB";
	}

	my $human = sprintf ( "%.2f", $human );
	my $out = $human . $unit;
	return $out;
}

=begin nd
Function: getSupportSaveSize

	It gets the aproximate size that the supportsave will need.
	The size is calculated using the config and log directories size and adding
	a offset of 20MB

Parameters:
	directory - Directory where the supportsave will be created

Returns:
	Integer - Number of bytes that supportsave will use

=cut

sub getSupportSaveSize
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $dir    = shift;
	my $offset = "20971520";                             # 20 MB
	my $dirs   = "/usr/local/zevenet/config /var/log";

	my $tar_bin = &getGlobalConfiguration( 'tar' );
	my $size    = `$tar_bin cz - $dirs 2>/dev/null | wc -c`;

	return $offset + $size;
}

=begin nd
Function: checkSupportSaveSpace

	Check if the disk has enough space to create a supportsave

Parameters:
	directory - Directory where the supportsave will be created

Returns:
	Integer - It returns 0 on success or the number of bytes needed to create a supportsave

=cut

sub checkSupportSaveSpace
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $dir = shift // "/tmp";

	my $supp_size = &getSupportSaveSize( $dir );
	my $freeSpace = &getSpaceFree( $dir );

	my $out = ( $freeSpace > $supp_size ) ? 0 : $supp_size;

	if ( $out )
	{
		&zenlog(
			"There is no enough free space ('$freeSpace') in the '$dir' partition. Supportsave needs '$supp_size' bytes",
			"error", "system"
		);
	}
	else
	{
		&zenlog(
			"Checking free space ('$freeSpace') in the '$dir' partition. Supportsave needs '$supp_size' bytes",
			"debug", "system"
		);
	}

	return $out;
}

=begin nd
Function: getSupportSave

	It creates a support save file used for supporting purpose. It is created in the '/tmp/' directory

Parameters:
	none - .

Returns:
	String - The supportsave file name is returned.

=cut

sub getSupportSave
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $zbindir   = &getGlobalConfiguration( 'zbindir' );
	my @ss_output = `${zbindir}/supportsave 2>&1`;

	# get the last "word" from the first line
	my $first_line = shift @ss_output;
	my $last_word = ( split ( ' ', $first_line ) )[-1];

	my $ss_path = $last_word;

	my ( undef, $ss_filename ) = split ( '/tmp/', $ss_path );

	return $ss_filename;
}

=begin nd
Function: applyFactoryReset

	Run a factory reset in the load balancer. It can be executed using several modes. The modes are described in the type parameter.

Parameters:
	Interface - Management interface that will not me delete while the factory reset process.
	Reset Type - Type of reset factory. The options are:
			'remove-backups', expecifies that the backups will be deleted.
			'hard-reset', reset factory is executed in its hard mode, deleting the zevenet certificate.
			'hardware', is a hard reset, and set up the management interface with the hardware default IP.
			If no paratemers are used in the function, the reset factory does not delete the backups and it will executed in its soft mode.

Returns:
	Integer - The function will return 0 on success, or another value on failure

=cut

sub applyFactoryReset
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $if_name = shift;
	my $reset_type = shift // '';

	if ( !$if_name )
	{
		&zenlog( "Factory reset needs a interface", "error", "Factory" );
		return -1;
	}

	unless ( $reset_type =~ /^(?:remove-backups|hardware||hard-reset)$/ )
	{
		&zenlog( "Reset type do not recognized: $reset_type", "error", "Factory" );
		return -2;
	}

	$reset_type = "--$reset_type" if ( $reset_type ne '' );

	my $cmd =
	  &getGlobalConfiguration( 'factory_reset_bin' ) . " -i $if_name $reset_type";
	my $err = &logAndRunBG( $cmd )
	  ;    # it has to be executed in background for being used from api

	return $err;
}

1;
