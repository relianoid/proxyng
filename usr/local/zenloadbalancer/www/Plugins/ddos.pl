#!/usr/bin/perl

###############################################################################
#
#     Zen Load Balancer Software License
#     This file is part of the Zen Load Balancer software package.
#
#     Copyright (C) 2014 SOFINTEL IT ENGINEERING SL, Sevilla (Spain)
#
#     This library is free software; you can redistribute it and/or modify it
#     under the terms of the GNU Lesser General Public License as published
#     by the Free Software Foundation; either version 2.1 of the License, or
#     (at your option) any later version.
#
#     This library is distributed in the hope that it will be useful, but
#     WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser
#     General Public License for more details.
#
#     You should have received a copy of the GNU Lesser General Public License
#     along with this library; if not, write to the Free Software Foundation,
#     Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
###############################################################################

#~ use strict;
use Config::Tiny;
use Tie::File;


require "/usr/local/zenloadbalancer/www/farms_functions.cgi";
require "/usr/local/zenloadbalancer/www/functions_ext.cgi";


sub getDDOSParam
{
		my $key = shift;
		my $param = shift;
		
		my $confFile = &getGlobalConfiguration( 'ddosConf' );
		my $fileHandle = Config::Tiny->read( $confFile );
		
		return $fileHandle->{ $key } -> { $param };
}


# & setDDOSParam ($key,$param,$value)
sub setDDOSParam
{
		my $key = shift;
		my $param = shift;
		my $output;
		
		my $confFile = &getGlobalConfiguration( 'ddosConf' );
		my $fileHandle = Config::Tiny->read( $confFile );
		$fileHandle->{ $key } ->  { $param } = $value;
		$fileHandle->write( $confFile );
		
		#~ eliminar estas reglas
		&getDDOSLookForRule ( $key, $farmName );
		&setDDOSDeleteRule ( $key, $farmName );
		&setDDOSCreateRule( $key, $farmName );
		#¡'''???'''
		#~ crear estas reglas

		return $output;
}


=begin nd
        Function: getIptListV4

        Obtein IPv4 iptables rules for a couple table-chain

        Parameters:
				table - 
				chain - 
				
        Returns:
				== 0	- don't find any rule
             @out	- Array with rules

=cut
sub getIptListV4
{
	my ( $table, $chain ) = @_;

	if ( $table ne '' )
	{
		$table = "--table $table";
	}

	my $iptables_command = &getGlobalConfiguration( 'iptables' )
	  . " $table -L $chain -n -v --line-numbers";

	&zenlog( $iptables_command );

	## lock iptables use ##
	open my $ipt_lockfile, '>', $iptlock;
	&setIptLock( $ipt_lockfile );

	my @ipt_output = `$iptables_command`;

	## unlock iptables use ##
	&setIptUnlock( $ipt_lockfile );
	close $ipt_lockfile;

	return @ipt_output;
}

=begin nd
        Function: getDDOSLookForRule

        Look for a:
			- global rule 				( key )
			- set of rules applied a farm 	( key, farmName )
        
        Parameters:
				key		 - id that indetify a rule
				farmName - farm name
				
        Returns:
				== 0	- don't find any rule
             @out	- Array with reference hashs
							- out[i]= { 
									line  => num,
									table => string,
									chain => string
								  }

=cut
sub getDDOSLookForRule
{
	my ( $key, $farmName ) = @_;

	# table and chain where there are keep ddos rules
	my @table = ( 'raw'					, 'filter'	, 'filter'			, 'raw'							, 'mangle' );
	my @chain = ( 'PREROUTING', 'INPUT'	, 'FORWARD'	, 'PORT_SCANNING'	, 'PREROUTING' );

	my @output;
	$ind = -1;
	for ( @table )
	{
		$ind++;

		# Get line number
		my @rules = &getIptListV4( $table[$ind], $chain[$ind] );

		# Reverse @rules to delete first last rules
		@rules = reverse ( @rules );

		# Delete DDoS global conf
		foreach my $rule ( @rules )
		{
			my $flag = 0;
			my $lineNum;

			# Look for farm rule
			if ( $farmName )
			{
				if ( $rule =~ /^(\d+) .+DDOS_${key}_$farmName \*/ )
				{
					$lineNum = $1;
					$flag    = 1;
				}
			}

			# Look for global rule
			else
			{

				if ( $rule =~ /^(\d+) .+DDOS_$key/ )
				{
					$lineNum = $1;
					$flag    = 1;
				}
			}
			push @output, { line => $lineNum, table => $table[$ind], chain => $chain[$ind] }
			  if ( $flag );
		}
	}
	return \@output;
}

=begin nd
        Function: setDDOSRunRule

        Apply iptables rules to a farm or all balancer

        Parameters:
				key		 - id that indetify a rule, ( key = 'farms' to apply rules to farm )
				farmname - farm name
				
        Returns:

=cut
sub setDDOSRunRule
{
	my ( $key, $farmName ) = @_;
	my %hash;
	my $output = -2;
	my $protocol;
	
	if ( $farmName )
	{
		# get farm struct
		%hash = (
					 farmName => $farmName,
					 vip      => "-d " . &getFarmVip( 'vip', $farmName ),
					 vport    => "--dport " . &getFarmVip( 'vpp', $farmName ),
		);

		# -d farmIP -p PROTOCOL --dport farmPORT
		$protocol = &getFarmProto( $farmName );

		if ( $protocol =~ /UDP/i || $protocol =~ /TFTP/i || $protocol =~ /SIP/i )
		{
			$hash{ 'protocol' } = "-p udp";
		}
		if ( $protocol =~ /TCP/i || $protocol =~ /FTP/i )
		{
			$hash{ 'protocol' } = "-p tcp";
		}
	}
 
	# global rules 
	if ( $key eq 'SSHBRUTEFORCE' ){
		$output = &setDDOSSshBruteForceRule() ;
	}elsif ( $key eq 'DROPICMP' ){
		$output = &setDDOSDropIcmpRule();
		
	# rules for farms
	}elsif ( $key eq 'INVALID' ){
		$output = &setDDOSInvalidPacketRule( \%hash );
	}elsif ( $key eq 'BLOCKSPOOFED' ){
		$output = &setDDOSBlockSpoofedRule( \%hash );
	}elsif ( $key eq 'LIMITCONNS' ){
			$output = &setDDOSLimitConnsRule( \%hash );
	}elsif ( $key eq 'LIMITSEC' ){
			$output = &setDDOSLimitSecRule( \%hash );
						
	# rules for tcp farms
	}elsif ( $protocol =~ /TCP/i || $protocol =~ /FTP/i ){
		if ( $key eq 'PORTSCANNING' ){
			$output = &setDDOSPortScanningRule( \%hash );
		}elsif ( $key eq 'DROPFRAGMENTS' ){
			$output = &setDDOSDropFragmentsRule( \%hash );
		}elsif ( $key eq 'NEWNOSYN' ){
			$output = &setDDOSNewNoSynRule( \%hash ) ;
		}elsif ( $key eq 'SYNWITHMSS' ){
			$output = &setDDOSSynWithMssRule( \%hash );
		}elsif ( $key eq 'BOGUSTCPFLAGS' ){
			$output = &setDDOSBogusTcpFlagsRule( \%hash );
		}elsif ( $key eq 'LIMITRST' ){
			$output = &setDDOSLimitRstRule( \%hash );
		}elsif ( $key eq 'SYNPROXY') {
			$output = &setDDOSynProxyRule( \%hash );
		}
	}
	
	return $output;
}


=begin nd
        Function: setDDOSStopRule

        Remove iptables rules

        Parameters:
				key		 - id that indetify a rule, ( key = 'farms' to remove rules from farm )
				farmname - farm name
				
        Returns:
				== 0	- Successful
             != 0	- Number of rules didn't boot

=cut
sub setDDOSStopRule
{
	my ( $key, $farmName ) = @_;
	my $output;

	my $ind++;
	foreach my $rule ( @{ &getDDOSLookForRule( $key, $farmName ) } )
	{
		my $cmd = &getGlobalConfiguration( 'iptables' )
		  . " --table $rule->{'table'} -D $rule->{'chain'} $rule->{'line'}";
		my $output = &iptSystem( $cmd );
		if ( $output != 0 )
		{
			&zenlog( "Error deleting '$cmd'" );
			$output++;
		}
		else
		{
			&zenlog( "Deleted '$cmd' successful" );
		}
	}
	return $output;
}

=begin nd
        Function: setDDOSBoot

        Boot all DDoS rules

        Parameters:
				
        Returns:
				== 0	- Successful
             != 0	- Number of rules didn't boot

=cut
sub setDDOSBoot
{
	my $confFile = &getGlobalConfiguration( 'ddosConf' );
	my $output;

	#create  PORT_SCANNING chain
	# /sbin/iptables -N PORT_SCANNING
	
	if ( -e $confFile )
	{
		my $fileHandle = Config::Tiny->read( $confFile );
		foreach my $key ( keys %{ $fileHandle } )
		{
			if ( exists $fileHandle->{ $key }->{ 'farms' } )
			{
				my $farmList = $fileHandle->{ $key }->{ 'farms' };
				my @farms = split ( ' ', $farmList );
				foreach my $farmName ( @farms )
				{
					$output++ if ( &setDDOSRunRule( $key, $farmName ) != 0 );
				}
			}
			else
			{
					$output++ if ( &setDDOSRunRule( $key, 'status' ) != 0 );
			}		
		}
	}
	return $output;
}

=begin nd
        Function: setDDOSStop

        Stop all DDoS rules

        Parameters:
				
        Returns:
				== 0	- Successful
             != 0	- Number of rules didn't Stop

=cut
sub setDDOSStop
{
	my $output;

	if ( -e $confFile )
	{
		my $fileHandle = Config::Tiny->read( $confFile );
		foreach my $key ( keys %{ $fileHandle } )
		{
			# Applied to farm
			if ( $key eq 'farms' )
			{
				my $farmList = $fileHandle->{ $key }->{ 'farms' };
				my @farms = split ( ' ', $farmList );
				foreach my $farmName ( @farms )
				{
					$output++ if ( &setDDOSStopRule( $key, $farmName ) != 0 );
				}
			}
			# Applied to balancer
			elsif ( $fileHandle->{ $key }->{ 'status' } eq 'up' )
			{
				$output++ if ( &setDDOSStopRule( $key ) != 0 );
			}
		}
	}
	return $output;
}

=begin nd
        Function: setDDOSCreateRule

        Create a DDoS rules
        This rules have two types: applied to a farm or applied to the balancer

        Parameters:
				key		 - id that indetify a rule
				farmname - farm name
				
        Returns:
				== 0	- Successful
             != 0	- Error

=cut
sub setDDOSCreateRule
{
	my ( $key, $farmName ) = @_;
	my $confFile = &getGlobalConfiguration( 'ddosConf' );
	my $output;

	if ( !-e $confFile )
	{
		if ( system ( &getGlobalConfiguration( 'touch' ) . " " . $confFile ) != 0 )
		{
			&zenlog( "Error creating " . $confFile );
			return -2;
		}
	}

	my $fileHandle = Config::Tiny->read( $confFile );
	my $farmList   = $fileHandle->{ $key }->{ 'farms' };

print "key:$key,farm:$farmName\n"; # ????

	if ( $farmName )
	{
		my $farmList   = $fileHandle->{ $key }->{ 'farms' };
		if ( $farmList !~ /(^| )$farmName( |$)/ )
		{
			$output = &setDDOSRunRule( $key, $farmName );
			
			if ( $output != -2 )
			{
				$fileHandle->{ $key }->{ 'farms' } = "$farmList $farmName";
				$fileHandle->write( $confFile );
			}
		}
	}

	# check param is down
	elsif ( $fileHandle->{ $key }->{ 'status' } ne "up" )
	{
		$fileHandle->{ $key }->{ 'status' } = "up";
		$fileHandle->write( $confFile );

		$output = &setDDOSRunRule( $key );
	}

	return $output;
}

=begin nd
        Function: setDDOSCreateRule

        Create a DDoS rules
        This rules have two types: applied to farm or balancer

        Parameters:
				key		 - id that indetify a rule
				farmname - farm name
				
        Returns:
				== 0	- Successful
             != 0	- Error

=cut
sub setDDOSDeleteRule
{
	my ( $key, $farmName ) = @_;
	my $confFile   = &getGlobalConfiguration( 'ddosConf' );
	my $fileHandle = Config::Tiny->read( $confFile );
	my $output;

	if ( -e $confFile )
	{
		if ( $farmName )
		{
			$fileHandle->{ $key }->{ 'farms' } =~ s/(^| )$farmName( |$)/ /;
			$fileHandle->write( $confFile );
			$output = &setDDOSStopRule( $key, $farmName );
		}
		else
		{
			$fileHandle->{ $key }->{ 'status' } = "down";
			$fileHandle->write( $confFile );
			$output = &setDDOSStopRule( $key );
		}
	}
	return $output;
}


# permivisve rule
### Drop invalid packets ###
# &setDDOSInvalidPacketRule ( ruleOpt )
sub setDDOSInvalidPacketRule
{
	my ( $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	my $key = "INVALID";
	my $logMsg = "[Blocked by rule $key]";
	
	# /sbin/iptables -t raw -A PREROUTING -m conntrack --ctstate INVALID -j DROP
	my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "-m conntrack --ctstate INVALID "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '$key' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	return $output;
}


# Only TCP farms
# restrictive rule
### Drop TCP packets that are new and are not SYN ###
# &setDDOSNewNoSynRule ( ruleOpt )
sub setDDOSNewNoSynRule
{
	my ( $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	my $key = "NEWNOSYN";
	my $logMsg = "[Blocked by rule $key]";
	
# sbin/iptables -t raw -A PREROUTING -p tcp ! --syn -m conntrack --ctstate NEW -j DROP
	my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "! --syn -m conntrack --ctstate NEW "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '$key' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	return $output;
}


# Only TCP farms
### Drop SYN packets with suspicious MSS value ###
# &setDDOSSynWithMssRule ( ruleOpt )
sub setDDOSSynWithMssRule
{
	my ( $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	my $key = "SYNWITHMSS";
	my $logMsg = "[Blocked by rule $key]";
	
# /sbin/iptables -t raw -A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP
	my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "-m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 "  # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '$key' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	return $output;
}

# Only TCP farms
### Block packets with bogus TCP flags ###
# &setDDOSBogusTcpFlagsRule ( ruleOpt )
sub setDDOSBogusTcpFlagsRule
{
	my ( $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	my $key = "BOGUSTCPFLAGS";
	my $logMsg = "[Blocked by rule $key]";
	
# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j DROP
	my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_1' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

 # /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags FIN,SYN FIN,SYN "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_2' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

 # /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags SYN,RST SYN,RST "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_3' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

 # /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags SYN,FIN SYN,FIN "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_4' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

 # /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags FIN,RST FIN,RST "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_5' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags FIN,ACK FIN -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags FIN,ACK FIN "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_6' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ACK,URG URG -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags ACK,URG URG "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_7' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ACK,FIN FIN -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags ACK,FIN FIN "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_8' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ACK,PSH PSH -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags ACK,PSH PSH "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_9' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ALL ALL -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags ALL ALL "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_10' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ALL NONE -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags ALL NONE "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_11' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

 # /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags ALL FIN,PSH,URG "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_12' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ALL SYN,FIN,PSH,URG -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags ALL SYN,FIN,PSH,URG "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_13' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags ALL SYN,RST,ACK,FIN,URG "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_14' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	return $output;
}


### Block spoofed packets ###
# &setDDOSBlockSpoofedRule ( ruleOpt )
sub setDDOSBlockSpoofedRule
{
	my ( $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	my $key = "BLOCKSPOOFED";
	my $logMsg = "[Blocked by rule $key]";
	
	# /sbin/iptables -t raw -A PREROUTING -s 224.0.0.0/3 -j DROP
	my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "-s 192.0.2.0/24,192.168.0.0/16,10.0.0.0/8,0.0.0.0/8,240.0.0.0/5 " # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";     # comment

	my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_1' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -s 127.0.0.0/8 ! -i lo -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "-s 127.0.0.0/8 ! -i lo "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_2' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	return $output;
}

# All balancer
###  Drop ICMP ###
# &setDDOSDropIcmpRule ( ruleOpt )
sub setDDOSDropIcmpRule
{
	my $key = "DROPICMP";
	my $logMsg = "[Blocked by rule $key]";
	
	# /sbin/iptables -t raw -A PREROUTING -p icmp -j DROP
	my $cmd = &getGlobalConfiguration( 'iptables' )
	  . " -t raw -A PREROUTING "     # select iptables struct
	  . "-p icmp "                      # rules for block
	  . "-m comment --comment \"DDOS_${key}\"";    # comment

	my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '$key' rule." );
	}

	return $output;
}

# only ipv4
### Drop fragments in all chains ###
# &setDDOSDropFragmentsRule ( ruleOpt )
sub setDDOSDropFragmentsRule
{
	my ( $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	my $key = "DROPFRAGMENTS";
	my $logMsg = "[Blocked by rule $key]";
	
	# only in IPv4
	if ( &getBinVersion( $ruleOpt{ 'farmName' } ) =~ /6/ )
	{
		return 0;
	}

	# /sbin/iptables -t raw -A PREROUTING -f -j DROP
	my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "-f "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '$key' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	return $output;
}

# Only TCP farms
### Limit connections per source IP ###
# &setDDOSLimitConnsRule ( ruleOpt )
sub setDDOSLimitConnsRule
{
	my ( $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	my $key = "LIMITCONNS";
	my $logMsg = "[Blocked by rule $key]";
	
	my $limitConns = &getDDOSParam( $key, 'limitConns');

# SOLO DISPONIBLE EN TABLA FILTER, EVALUAR SI INSERTAR EN FORWARD O INPUT  ???
# /sbin/iptables -A PREROUTING -t INPUT -p tcp -m connlimit --connlimit-above 111 -j REJECT --reject-with tcp-reset
	my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -A INPUT -t filter "         # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "-m connlimit --connlimit-above $limitConns "    # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

	my $output = &iptSystem( "$cmd -j LOG  --log-prefix \"$logMsg\" --log-level 4 " );

	$output = &iptSystem( "$cmd -j REJECT --reject-with tcp-reset" );
	
	if ( $output != 0 )
	{
		&zenlog( "Error appling '$key' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	return $output;
}

# Only TCP farms
### Limit RST packets ###
# &setDDOSLimitRstRule ( ruleOpt )
sub setDDOSLimitRstRule
{
	my ( $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	my $key = "LIMITRST";
	my $logMsg = "[Blocked by rule $key]";
	my $limit = &getDDOSParam( $key, 'limit');
	my $limitBurst = &getDDOSParam( $key, 'limitBurst');

# /sbin/iptables -A PREROUTING -t mangle -p tcp --tcp-flags RST RST -m limit --limit 2/s --limit-burst 2 -j ACCEPT
	my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -A PREROUTING -t mangle "       # select iptables struct
	  . "-j ACCEPT $ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "--tcp-flags RST RST -m limit --limit $limit/s --limit-burst $limitBurst " # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";             # comment

	my $output = &iptSystem( $cmd );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_1' rule to farm '$ruleOpt{ 'farmName' }'." );
	}
	else
	{
		# /sbin/iptables -I PREROUTING -t mangle -p tcp --tcp-flags RST RST -j DROP
		$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
		  . " -I PREROUTING -t mangle "    # select iptables struct
		  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
		  . "--tcp-flags RST RST "    # rules for block
		  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

		my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
		if ( $output != 0 )
		{
			&zenlog( "Error appling '${key}_2' rule to farm '$ruleOpt{ 'farmName' }'." );
		}
	}
	return $output;
}

### Limit new TCP connections per second per source IP ###
# &setDDOSLimitSecRule ( ruleOpt )
sub setDDOSLimitSecRule
{
	my ( $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	my $key = "LIMITSEC";
	my $logMsg = "[Blocked by rule $key]";
	my $limitNew = &getDDOSParam( $key, 'limit');
	my $limitBurstNew = &getDDOSParam( $key, 'limitBurst');

# /sbin/iptables -I PREROUTING -t mangle -p tcp -m conntrack --ctstate NEW -m limit --limit 60/s --limit-burst 20 -j ACCEPT
	my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -I PREROUTING -t mangle "           # select iptables struct
	  . "-j ACCEPT $ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
	  . "-m conntrack --ctstate NEW -m limit --limit $limitBurstNew/s --limit-burst $limitBurstNew " # rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";                               # comment

	my $output = &iptSystem( $cmd );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_1' rule to farm '$ruleOpt{ 'farmName' }'." );
	}
	else
	{
		# /sbin/iptables -I PREROUTING -t mangle -p tcp -m conntrack --ctstate NEW -j DROP
		$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
		  . " -I PREROUTING -t mangle "    # select iptables struct
		  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
		  . "-m conntrack --ctstate NEW "    # rules for block
		  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

		my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
		if ( $output != 0 )
		{
			&zenlog( "Error appling '${key}_2' rule to farm '$ruleOpt{ 'farmName' }'." );
		}
	}
	return $output;
}

#~ # Balancer
#~ ### Protection against port scanning ###
#~ # &setDDOSPortScanningRule ( ruleOpt )
sub setDDOSPortScanningRule
{
	my ( $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	my $key = "PORTSCANNING";
	my $logMsg = "[Blocked by rule $key]";
	my $output;
	
	my $cmd = &getGlobalConfiguration( 'iptables' )
	  . " -N PORT_SCANNING -t raw ";   
	&iptSystem( $cmd );
	
	# iptables -A PREROUTING -t raw -p tcp --tcp-flags SYN,ACK,FIN,RST RST -j PORT_SCANNING
	$cmd = &getGlobalConfiguration( 'iptables' )
				. " -A PREROUTING --table raw "     # select iptables struct
				#~ . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " # who is destined
				. "-j PORT_SCANNING " 
				. "-p tcp --tcp-flags SYN,ACK,FIN,RST RST "    # rules for block
				#~ . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment
				. "-m comment --comment \"DDOS_${key}\"";    # comment
	$output = &iptSystem( $cmd );

	# iptables -A PORT_SCANNING -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN
	$cmd = &getGlobalConfiguration( 'iptables' )
				. " -A PORT_SCANNING -t raw "     # select iptables struct
				. "-j RETURN "
				. "-p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 "    # rules for block
				. "-m comment --comment \"DDOS_${key}\"";    # comment
	$output = &iptSystem( $cmd );

	# /sbin/iptables -A port-scanning -j DROP
	$cmd = &getGlobalConfiguration( 'iptables' )
				 . " -A PORT_SCANNING -t raw "     # select iptables struct
				 . "-m comment --comment \"DDOS_${key}\"";    # comment
	$output = &setIPDSDropAndLog ( $cmd, $logMsg );

	if ( $output != 0 )
	{
		&zenlog( "Error appling '$key' rule." );
	}

	return $output;
}

=begin nd
        Function: setDDOSSshBruteForceRule

        This rule is a protection against brute-force atacks to ssh protocol.
        This rule applies to the balancer

        Parameters:
				
        Returns:
				== 0	- successful
                != 0	- error

=cut

# balancer
### SSH brute-force protection ###
# &setDDOSSshBruteForceRule
sub setDDOSSshBruteForceRule
{
	my $key = "SSHBRUTEFORCE";
	my $hits = &getDDOSParam( $key, 'hits');
	my $time = &getDDOSParam( $key, 'time');
	my $port = &getDDOSParam( $key, 'port');
	my $logMsg = "[Blocked by rule $key]";


# /sbin/iptables -I PREROUTING -t mangle -p tcp --dport ssh -m conntrack --ctstate NEW -m recent --set
	my $cmd =
	  &getGlobalConfiguration( 'iptables' ) . " -I PREROUTING -t mangle "  # select iptables struct
	  . "-p tcp --dport $port "                               # who is destined
	  . "-m conntrack --ctstate NEW -m recent --set "       # rules for block
	  . "-m comment --comment \"DDOS_$key\"";               # comment

	my $output = &iptSystem( $cmd );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_1' rule." );
	}

# /sbin/iptables -I PREROUTING -t mangle -p tcp --dport ssh -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 10 -j DROP
	my $cmd =
	  &getGlobalConfiguration( 'iptables' ) . " -I PREROUTING -t mangle "  # select iptables struct
	  . "-p tcp --dport $port "                       # who is destined
	  . "-m conntrack --ctstate NEW -m recent --update --seconds $time --hitcount $hits " # rules for block
	  . "-m comment --comment \"DDOS_$key\"";                                             # comment

	my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_2' rule." );
	}

	return $output;
}



# solo usable en chain INPUT / FORWARD
### Use SYNPROXY on all ports (disables connection limiting rule) ###
#/sbin/iptables -t raw -A PREROUTING -p tcp -m tcp --syn -j CT --notrack
#/sbin/iptables -A INPUT -p tcp -m tcp -m conntrack --ctstate INVALID,UNTRACKED -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460
#/sbin/iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

# balancer
### SSH brute-force protection ###
# &setDDOSSshBruteForceRule
sub setDDOSynProxyRule
{
	my ( $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };
	
	my $key = "SYNPROXY";
	my $logMsg = "[Blocked by rule $key]";
	my $scale = getDDOSParam ( $key, 'scale' );
	my $mss = getDDOSParam ( $key, 'mss' );

# iptables -t raw -A PREROUTING -p tcp -m tcp --syn -j CT
	my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -A PREROUTING -t raw "           																			# select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " 						# who is destined
	  . "-m tcp --syn " 																										# rules for block
	  . "-j CT "																													# action
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";	# comment
	my $output = &iptSystem( "$cmd" );

# iptables -I INPUT -p tcp -m tcp -m conntrack --ctstate NEW -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -A INPUT "           																								# select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " 					# who is destined
	  . "-j SYNPROXY --sack-perm --timestamp --wscale $scale --mss $mss "	# action
	  . "-m conntrack --ctstate NEW "														 				# rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";	# comment
	$output = &iptSystem( "$cmd" );

# iptables -I FORWARD -p tcp -m tcp -m conntrack --ctstate NEW -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -A FORWARD "           																						# select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " 					# who is destined
	  . "-j SYNPROXY --sack-perm --timestamp --wscale $scale --mss $mss "	# action
	  . "-m conntrack --ctstate NEW "														 				# rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";	# comment
	$output = &iptSystem( "$cmd" );

# iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -A INPUT "           																				# select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " 	# who is destined
	  . "-m conntrack --ctstate INVALID " 													# rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";	# comment
	$output = &setIPDSDropAndLog ( $cmd, $logMsg );

# iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -A FORWARD "           																				# select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vpp' } " 	# who is destined
	  . "-m conntrack --ctstate INVALID " 													# rules for block
	  . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";	# comment
	$output = &setIPDSDropAndLog ( $cmd, $logMsg );
	
	
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_2' rule." );
	}

	return $output;
}


# LOGS
# &setIPDSDropAndLog ( $cmd, $logMsg );
sub setIPDSDropAndLog
{
	my ( $cmd, $logMsg ) = @_;

	my $output = &iptSystem( "$cmd -j LOG  --log-prefix \"$logMsg\" --log-level 4 " );
	$output = &iptSystem( "$cmd -j DROP" );

	return $output;
}


1;



=begin nd

### 1: Drop invalid packets ###
/sbin/iptables -t mangle -A PREROUTING -m conntrack --ctstate INVALID -j DROP

### 2: Drop TCP packets that are new and are not SYN ###
/sbin/iptables -t mangle -A PREROUTING -p tcp ! --syn -m conntrack --ctstate NEW -j DROP

### 3: Drop SYN packets with suspicious MSS value ###
/sbin/iptables -t mangle -A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP

### 4: Block packets with bogus TCP flags ###
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j DROP
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags FIN,ACK FIN -j DROP
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags ACK,URG URG -j DROP
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags ACK,FIN FIN -j DROP
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags ACK,PSH PSH -j DROP
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL ALL -j DROP
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL NONE -j DROP
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL SYN,FIN,PSH,URG -j DROP
/sbin/iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP

### 5: Block spoofed packets ###
/sbin/iptables -t mangle -A PREROUTING -s 224.0.0.0/3 -j DROP
/sbin/iptables -t mangle -A PREROUTING -s 169.254.0.0/16 -j DROP
/sbin/iptables -t mangle -A PREROUTING -s 172.16.0.0/12 -j DROP
/sbin/iptables -t mangle -A PREROUTING -s 192.0.2.0/24 -j DROP
/sbin/iptables -t mangle -A PREROUTING -s 192.168.0.0/16 -j DROP
/sbin/iptables -t mangle -A PREROUTING -s 10.0.0.0/8 -j DROP
/sbin/iptables -t mangle -A PREROUTING -s 0.0.0.0/8 -j DROP
/sbin/iptables -t mangle -A PREROUTING -s 240.0.0.0/5 -j DROP
/sbin/iptables -t mangle -A PREROUTING -s 127.0.0.0/8 ! -i lo -j DROP

### 6: Drop ICMP (you usually don't need this protocol) ###
/sbin/iptables -t mangle -A PREROUTING -p icmp -j DROP

### 7: Drop fragments in all chains ###
/sbin/iptables -t mangle -A PREROUTING -f -j DROP

### 8: Limit connections per source IP ###
/sbin/iptables -A INPUT -p tcp -m connlimit --connlimit-above 111 -j REJECT --reject-with tcp-reset

### 9: Limit RST packets ###
/sbin/iptables -A INPUT -p tcp --tcp-flags RST RST -m limit --limit 2/s --limit-burst 2 -j ACCEPT
/sbin/iptables -A INPUT -p tcp --tcp-flags RST RST -j DROP

### 10: Limit new TCP connections per second per source IP ###
/sbin/iptables -A INPUT -p tcp -m conntrack --ctstate NEW -m limit --limit 60/s --limit-burst 20 -j ACCEPT
/sbin/iptables -A INPUT -p tcp -m conntrack --ctstate NEW -j DROP

### 11: Use SYNPROXY on all ports (disables connection limiting rule) ###
#/sbin/iptables -t raw -D PREROUTING -p tcp -m tcp --syn -j CT --notrack
#/sbin/iptables -D INPUT -p tcp -m tcp -m conntrack --ctstate INVALID,UNTRACKED -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460
#/sbin/iptables -D INPUT -m conntrack --ctstate INVALID -j DROP
iptables -t raw -I PREROUTING -p tcp -m tcp --syn -j CT --notrack
iptables -I INPUT -p tcp -m tcp -m conntrack --ctstate INVALID,UNTRACKED -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

### SSH brute-force protection ###
/sbin/iptables -A INPUT -p tcp --dport ssh -m conntrack --ctstate NEW -m recent --set
/sbin/iptables -A INPUT -p tcp --dport ssh -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 10 -j DROP

### Protection against port scanning ###
/sbin/iptables -N port-scanning
/sbin/iptables -A port-scanning -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN
/sbin/iptables -A port-scanning -j DROP

=cut
