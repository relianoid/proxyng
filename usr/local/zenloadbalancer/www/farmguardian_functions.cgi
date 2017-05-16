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

# Returns FarmGuardian config file for this farm
sub getFarmGuardianFile    # ($fname,$svice)
{
	my ( $fname, $svice ) = @_;

	opendir ( my $dir, "$configdir" ) || return -1;
	my @files =
	  grep { /^$fname\_$svice.*guardian\.conf/ && -f "$configdir/$_" }
	  readdir ( $dir );
	closedir $dir;

	my $nfiles = @files;

	if ( $nfiles == 0 )
	{
		return -1;
	}
	else
	{
		return $files[0];
	}
}

# Returns if FarmGuardian is activated for this farm
sub getFarmGuardianStatus    # ($fname,$svice)
{
	my ( $fname, $svice ) = @_;

	my $fgfile = &getFarmGuardianFile( $fname, $svice );

	if ( $fgfile == -1 )
	{
		return -1;
	}

	open FR, "$configdir/$fgfile";
	my $line;
	my $lastline;
	while ( $line = <FR> )
	{
		$lastline = $line;
	}

	my @line_s = split ( "\:\:\:", $lastline );
	my $value = $line_s[3];
	close FR;

	if ( $value =~ /true/ )
	{
		return 1;
	}
	else
	{
		return 0;
	}
}

# Returns if FarmGuardian has logs activated for this farm
sub getFarmGuardianLog    # ($fname,$svice)
{
	my ( $fname, $svice ) = @_;

	my $fgfile = &getFarmGuardianFile( $fname, $svice );

	if ( $fgfile == -1 )
	{
		return -1;
	}

	open FR, "$configdir/$fgfile";
	my $line;
	my $lastline;
	while ( $line = <FR> )
	{
		$lastline = $line;
	}

	my @line_s = split ( "\:\:\:", $lastline );
	my $value = $line_s[4];
	close FR;

	if ( $value =~ /true/ )
	{
		return 1;
	}
	else
	{
		return 0;
	}
}

# Start FarmGuardian rutine
sub runFarmGuardianStart    # ($fname,$svice)
{
	my ( $fname, $svice ) = @_;

	my $status = 0;
	my $log;
	my $sv;
	my $ftype  = &getFarmType( $fname );
	my $fgfile = &getFarmGuardianFile( $fname, $svice );
	my $fgpid  = &getFarmGuardianPid( $fname, $svice );

	if ( $fgpid != -1 )
	{
		return -1;
	}

	if ( $fgfile == -1 )
	{
		return -1;
	}

	if ( &getFarmGuardianLog( $fname, $svice ) )
	{
		$log = "-l";
	}

	if ( $svice ne "" )
	{
		$sv = "-s '$svice'";
	}

	if ( $ftype =~ /http/ && $svice eq "" )
	{
		# Iterate over every farm service
		my $services = &getFarmVS( $fname, "", "" );
		my @servs = split ( " ", $services );
		foreach my $service ( @servs )
		{
			my $stat = &runFarmGuardianStart( $fname, $service );
			$status = $status + $stat;
		}
	}
	elsif ( $ftype eq 'l4xnat' || $ftype eq 'udp' || $ftype eq 'tcp' || $ftype =~ /http/ )
	{
		my $farmguardian = &getGlobalConfiguration('farmguardian');
		my $fg_cmd = "$farmguardian $fname $sv $log";
		&zenlog( "running $fg_cmd" );
		&zsystem( "$fg_cmd > /dev/null &" );
		$status = $?;
	}
	else
	{
		# WARNING: farm types not supported by farmguardian return 0.
		$status = 0;
	}

	return $status;
}

sub runFarmGuardianStop    # ($fname,$svice)
{
	my ( $fname, $svice ) = @_;
	my $status = 0;
	my $sv;
	my $type = &getFarmType( $fname );
	my $fgpid = &getFarmGuardianPid( $fname, $svice );

	if ( $type =~ /http/ && $svice eq "" )
	{
		# Iterate over every farm service
		my $services = &getFarmVS( $fname, "", "" );
		my @servs = split ( " ", $services );

		foreach my $service ( @servs )
		{
			my $stat = &runFarmGuardianStop( $fname, $service );
			$status |= $stat;
		}
	}
	else
	{
		if ( $svice ne "" )
		{
			$sv = "${svice}_";
		}

		if ( $fgpid != -1 )
		{
			&zenlog( "running 'kill 9, $fgpid' stopping FarmGuardian $fname $svice" );
			kill 9, $fgpid;
			$status = $?;    # FIXME
			unlink glob ( "/var/run/$fname\_${sv}guardian.pid" );

		}
	}
	return $status;
}

# create farmguardian config file
sub runFarmGuardianCreate    # ($fname,$ttcheck,$script,$usefg,$fglog,$svice)
{
	my ( $fname, $ttcheck, $script, $usefg, $fglog, $svice ) = @_;

	my $fgfile = &getFarmGuardianFile( $fname, $svice );
	my $output = -1;

	if ( $fgfile == -1 )
	{
		if ( $svice ne "" )
		{
			$svice = "${svice}_";
		}
		$fgfile = "${fname}_${svice}guardian.conf";

		&zenlog(
			  "running 'Create FarmGuardian $ttcheck $script $usefg $fglog' for $fname farm"
		);
	}

	if ( ( $ttcheck eq "" || $script eq "" ) && $usefg eq "true" )
	{
		return $output;
	}

	open FO, ">$configdir/$fgfile";
	print FO "$fname\:\:\:$ttcheck\:\:\:$script\:\:\:$usefg\:\:\:$fglog\n";
	$output = $?;
	close FO;

	return $output;
}

# Remove farmguardian check status
sub runFarmGuardianRemove    # ( $fname, $svice )
{
	my ( $fname, $svice ) = @_;
	my $type = &getFarmType( $fname );
	my $status = 0;
	
	if ( $type =~ /http/ && $svice eq "" )
	{
		# Iterate over every farm service
		my $services = &getFarmVS( $fname, "", "" );
		my @servs = split ( " ", $services );

		foreach my $service ( @servs )
		{
			my $stat = &runFarmGuardianStop( $fname, $service );
			$status |= $stat;
		}
	}
	
	else
	{
		if ( $type eq "http" || $type eq "https" )
		{
			if ( -e "$configdir\/$fname\_status.cfg" )
			{
				my $portadmin = &getFarmPort( $fname );
				my $idsv      = &getFarmVSI( $fname, $svice );

				tie my @filelines, 'Tie::File', "$configdir\/$fname\_status.cfg";
				
				my @fileAux = @filelines;
				my $lines     = scalar @fileAux;
				
				while ( $lines >= 0 )
				{
					$lines--;
					my $line = $fileAux[ $lines ];
					if ( $fileAux[ $lines ] =~ /0 $idsv (\d+) fgDOWN/ )
					{
						my $index = $1;
						my $auxlin = splice ( @fileAux, $lines, 1, );
						my $poundctl = &getGlobalConfiguration('poundctl');
						system ( "$poundctl -c $portadmin -B 0 $idsv $index >/dev/null 2>&1" );
					}
				}
				@filelines = @fileAux;
				untie @filelines;
			}
		}
		
		if ( $type eq "l4xnat" )
		{
			my @be = &getFarmBackendStatusCtl( $fname );
			my $i  = -1;
		
			foreach my $line ( @be )
			{
				my @subbe = split ( ";", $line );
				$i++;
				my $backendid     = $i;
				my $backendserv   = $subbe[2];
				my $backendport   = $subbe[3];
				my $backendstatus = $subbe[7];
				chomp $backendstatus;
		
				if ( $backendstatus eq "fgDOWN" )
				{
					$status |= &setFarmBackendStatus( $fname, $i, "up" );
				}
			}
		}
	
	}
}

#
sub getFarmGuardianConf    # ($fname,$svice)
{
	my ( $fname, $svice ) = @_;
	my $lastline;

	# get filename
	my $fgfile = &getFarmGuardianFile( $fname, $svice );

	if ( $fgfile == -1 )
	{
		if ( $svice ne "" )
		{
			$svice = "${svice}_";
		}
		$fgfile = "${fname}_${svice}guardian.conf";
	}

	# read file
	open FG, "$configdir/$fgfile";
	my $line;
	while ( $line = <FG> )
	{
		if ( $line !~ /^#/ )
		{
			$lastline = $line;
			last;
		}
	}
	close FG;
	my @line = split ( ":::", $lastline );
	chomp ( @line );

	#&zenlog("getting 'FarmGuardianConf @line' for $fname farm");
	return @line;
}

#
sub getFarmGuardianPid    # ($fname,$svice)
{
	my ( $fname, $svice ) = @_;

	my $pidfile = "";
	my $piddir = &getGlobalConfiguration('piddir');

	opendir ( my $dir, "$piddir" ) || return -1;
	my @files =
	  grep { /^$fname\_$svice.*guardian\.pid/ && -f "$piddir/$_" } readdir ( $dir );
	closedir $dir;

	if ( @files )
	{
		$pidfile = $files[0];
		open FR, "$piddir/$pidfile";
		my $fgpid = <FR>;
		close FR;
		return $fgpid;
	}
	else
	{
		return -1;
	}
}

1;
