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

#~ use Fcntl ':flock';                       #use of lock functions

=begin nd
Function: openlock

	Open file with lock

	Usage:

		$filehandle = &openlock($mode, $expr);
		$filehandle = &openlock($mode);

	Examples:

		$filehandle = &openlock(">>","output.txt");
		$filehandle = &openlock("<$fichero");

Parameters:
	mode - Mode used to open the file.
	expr - Path of file if 3 arguments open is used.

Returns:
	scalar - File handler.

Bugs:
	Not used yet.
=cut
sub openlock    # ($mode,$expr)
{
	my ( $mode, $expr ) = @_;    #parameters
	my $filehandle;

	if ( $expr ne "" )
	{                            #3 parameters
		if ( $mode =~ /</ )
		{                        #only reading
			open ( $filehandle, $mode, $expr )
			  || die "some problems happened reading the file $expr\n";
			flock $filehandle, LOCK_SH
			  ; #other scripts with LOCK_SH can read the file. Writing scripts with LOCK_EX will be locked
		}
		elsif ( $mode =~ />/ )
		{       #only writing
			open ( $filehandle, $mode, $expr )
			  || die "some problems happened writing the file $expr\n";
			flock $filehandle, LOCK_EX;    #other scripts cannot open the file
		}
	}
	else
	{                                      #2 parameters
		if ( $mode =~ /</ )
		{                                  #only reading
			open ( $filehandle, $mode )
			  || die "some problems happened reading the filehandle $filehandle\n";
			flock $filehandle, LOCK_SH
			  ; #other scripts with LOCK_SH can read the file. Writing scripts with LOCK_EX will be locked
		}
		elsif ( $mode =~ />/ )
		{       #only writing
			open ( $filehandle, $mode )
			  || die "some problems happened writing the filehandle $filehandle\n";
			flock $filehandle, LOCK_EX;    #other scripts cannot open the file
		}
	}
	return $filehandle;
}

=begin nd
Function: closelock

	Close file with lock

	Usage:

		&closelock($filehandle);

	Examples:

		&closelock(FILE);

Parameters:
	filehandle - reference to file handler.

Returns:
	none - .

Bugs:
	Not used yet.
=cut
sub closelock    # ($filehandle)
{
	my $filehandle = shift;

	close ( $filehandle )
	  || warn
	  "some problems happened closing the filehandle $filehandle";    #close file
}

=begin nd
Function: tielock

	tie aperture with lock

	Usage:

		$handleArray = &tielock($file);

	Examples:

		$handleArray = &tielock("test.dat");
		$handleArray = &tielock($filename);

Parameters:
	file_name - Path to File.

Returns:
	scalar - Reference to the array with the content of the file.

Bugs:
	Not used yet.
=cut
sub tielock    # ($file_name)
{
	my $file_name = shift;    #parameters

	$o = tie my @array, "Tie::File", $file_name;
	$o->flock;

	return \@array;
}

=begin nd
Function: untielock

	Untie close file with lock

	Usage:

		&untielock($array);

	Examples:

		&untielock($myarray);

Parameters:
	array - Reference to array.

Returns:
	none - .

Bugs:
	Not used yet.
=cut
sub untielock    # (@array)
{
	my $array = shift;

	untie @{ $array };
}

1;
