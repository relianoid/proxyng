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

use Config::Tiny;
use Tie::File;

require "/usr/local/zenloadbalancer/www/Plugins/ipds.cgi";
require "/usr/local/zenloadbalancer/www/farms_functions.cgi";
require "/usr/local/zenloadbalancer/www/functions_ext.cgi";

use warnings;
use strict;

sub setDDOSCreateFileConf
{
	my $confFile    = &getGlobalConfiguration( 'ddosConf' );
	my $ddosConfDir = &getGlobalConfiguration( 'ddosConfDir' );
	my $output;

	return 0 if ( -e $confFile );

	# create ddos directory if it doesn't exist
	if ( !-d $ddosConfDir )
	{
		$output = system ( &getGlobalConfiguration( 'mkdir' ) . " -p $ddosConfDir" );
		&zenlog( "Created ipds configuration directory: $ddosConfDir" );
	}

	# create file conf if doesn't exist
	if ( !$output )
	{
		&zenlog( "Created ddos configuration directory: $ddosConfDir" );
		$output = system ( &getGlobalConfiguration( 'touch' ) . " $confFile" );
		if ( $output )
		{
			&zenlog( "Error, creating ddos configuration directory: $ddosConfDir" );
		}
		else
		{
			&zenlog( "Created ddos configuration file: $confFile" );
		}
	}

	if ( !$output )
	{
		$output = &createDDOSRule( 'drop_icmp', 'DROPICMP' )
		  if ( &getDDOSExists( 'drop_icmp' ) ne "0" );
		$output = &createDDOSRule( 'ssh_brute_force', 'SSHBRUTEFORCE' )
		  if ( &getDDOSExists( 'ssh_brute_force' ) ne "0" );
	}
	else
	{
		&zenlog( "Error, creating ddos configuration file: $confFile" );
	}

	return $output;
}

sub getDDOSInitialParams
{
	my $key = shift;

	#~ my $param = shift;

	my %initial = (
		'BOGUSTCPFLAGS' => { 'farms' => '', 'type'       => 'farm' },
		'LIMITCONNS'    => { 'farms' => '', 'limitConns' => 10, 'type' => 'farm' },
		'LIMITRST' =>
		  { 'farms' => '', 'limit' => 2, 'limitBurst' => 2, 'type' => 'farm' },
		'LIMITSEC' =>
		  { 'farms' => '', 'limit' => 2, 'limitBurst' => 2, 'type' => 'farm' },
		'DROPICMP' => { 'status' => 'down', 'type' => 'system', 'rule' => 'drop_icmp' },
		'SSHBRUTEFORCE' => {
							 'status' => 'down',
							 'hits'   => 5,
							 'port'   => 22,
							 'time'   => 180,
							 'type'   => 'system',
							 'rule'   => 'ssh_brute_force'
		},

		#					'NEWNOSYN' => { 'farms' => '' },
		#					'DROPFRAGMENTS' => { 'farms'  => '' },
		#					'INVALID'       => { 'farms'  => '' },
		#					'SYNPROXY'     => { 'farms' => '', 'mss' => 1460, 'scale' => 7 },
		#					'SYNWITHMSS'   => { 'farms' => '' },
		#					'PORTSCANNING' => {
		#										'farms'    => '',
		#										'portScan' => 15,
		#										'blTime'   => 500,
		#										'time'     => 100,
		#										'hits'     => 3,
		#					},
	);

	#~ if ( $param )
	#~ {
	#~ $output = $initial{ $key }->{ $param };
	#~ }
	#~ else
	#~ {
	my $output = $initial{ $key };

	#~ }

	return $output;
}

# &getDDOSParam( $ruleName, $param );
sub getDDOSParam
{
	my $ruleName = shift;
	my $param    = shift;
	my $output;

	my $confFile   = &getGlobalConfiguration( 'ddosConf' );
	my $fileHandle = Config::Tiny->read( $confFile );

	if ( $param )
	{
		$output = $fileHandle->{ $ruleName }->{ $param };
	}
	else
	{
		$output = $fileHandle->{ $ruleName };
	}
	return $output;
}

# &setDDOSParam ($name,$param,$value)
sub setDDOSParam
{
	my $rule  = shift;
	my $param = shift;
	my $value = shift;

	my $key = &getDDOSParam( $rule, 'key' );

	#Stop related rules
	&setDDOSStopRule( $rule );

	my $confFile   = &getGlobalConfiguration( 'ddosConf' );
	my $fileHandle = Config::Tiny->read( $confFile );
	$fileHandle = Config::Tiny->read( $confFile );

	$fileHandle->{ $rule }->{ $param } = $value;
	$fileHandle->write( $confFile );

	#~ # Rule global for the balancer
	if ( &getDDOSParam( $rule, 'type' ) eq 'system' )
	{
		if ( &getDDOSParam( $rule, 'status' ) eq 'up' )
		{
			&setDDOSRunRule( $rule );
		}
	}

	# Rule applied to farm
	elsif ( &getDDOSParam( $rule, 'farms' ) )
	{
		my $farmsString = &getDDOSParam( $rule, 'farms' );
		foreach my $farm ( split ( ' ', $farmsString ) )
		{
			&setDDOSRunRule( $rule, $farm );
		}
	}
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
	my ( $ruleName, $farmName ) = @_;

	# table and chain where there are keep ddos rules

 # active this when port scanning rule will be available
 #~ my @table = ( 'raw', 'filter', 'filter', 'raw', 'mangle' );
 #~ my @chain = ( 'PREROUTING', 'INPUT', 'FORWARD', 'PORT_SCANNING', 'PREROUTING' );

	my @table = ( 'raw',        'filter', 'filter',  'mangle' );
	my @chain = ( 'PREROUTING', 'INPUT',  'FORWARD', 'PREROUTING' );
	my $farmNameRule;

	my @output;
	my $ind = -1;
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
				if ( $rule =~ /^(\d+) .+DDOS_${ruleName}_$farmName \*/ )
				{
					$lineNum = $1;
					$flag    = 1;
				}
			}

			# Look for global rule
			else
			{
				my $farmNameFormat = &getValidFormat( 'farm_name' );
				if ( $rule =~ /^(\d+) .+DDOS_$ruleName/ )
				{
					$lineNum      = $1;
					$flag         = 1;
					$farmNameRule = $2;
				}
			}
			push @output, { line => $lineNum, table => $table[$ind], chain => $chain[$ind] }
			  if ( $flag );
		}
	}
	return \@output;
}

# return -1 if not exists
# return  0 if exists
# return  array with all rules if the function not receive params
# &getDDOSExists ( $rule );
sub getDDOSExists
{
	my $rule       = shift;
	my $output     = -1;
	my $confFile   = &getGlobalConfiguration( 'ddosConf' );
	my $fileHandle = Config::Tiny->read( $confFile );
	my @aux;

	if ( $rule )
	{
		$output = 0 if ( exists $fileHandle->{ $rule } );
	}
	else
	{
		@aux    = keys %{ $fileHandle };
		$output = \@aux;
	}

	return $output;
}

# key is the rule identifier
# &createDDOSRule( $rule, $key );
sub createDDOSRule
{
	my $ruleName = shift;
	my $key      = shift;
	my $params;

	my $confFile   = &getGlobalConfiguration( 'ddosConf' );
	my $fileHandle = Config::Tiny->read( $confFile );
	$fileHandle = Config::Tiny->read( $confFile );

	if ( exists $fileHandle->{ $ruleName } )
	{
		&zenlog( "$ruleName rule already exists." );
		return -1;
	}
	$params = &getDDOSInitialParams( $key );

	if ( !$params )
	{
		&zenlog( "Error, saving $ruleName rule." );
		return -2;
	}

	$fileHandle->{ $ruleName } = $params;
	$fileHandle->{ $ruleName }->{ 'key' } = $key;
	if ( $params->{ 'type' } eq 'farm' )
	{
		$fileHandle->{ $ruleName }->{ 'rule' } = $ruleName;
	}
	$fileHandle->write( $confFile );
	&zenlog( "$ruleName rule created successful." );

	return 0;
}

sub deleteDDOSRule
{
	my $name = shift;

	my $confFile   = &getGlobalConfiguration( 'ddosConf' );
	my $fileHandle = Config::Tiny->read( $confFile );
	$fileHandle = Config::Tiny->read( $confFile );

	if ( !exists $fileHandle->{ $name } )
	{
		&zenlog( "$name rule doesn't exist." );
		return -1;
	}

	delete $fileHandle->{ $name };
	$fileHandle->write( $confFile );

	return 0;
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
	my ( $ruleName, $farmName ) = @_;
	my %hash;
	my $output = -2;
	my $protocol;

	# return if this rule already is applied
	if ( @{ &getDDOSLookForRule( $ruleName, $farmName ) } )
	{
		&zenlog( "This rule already is applied." );
		return -1;
	}

	if ( $farmName )
	{
		# get farm struct
		%hash = (
				  farmName => $farmName,
				  vip      => "-d " . &getFarmVip( 'vip', $farmName ),
				  vport    => "--dport " . &getFarmVip( 'vipp', $farmName ),
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

	my $key = &getDDOSParam( $ruleName, 'key' );

	if (    ( $key eq 'DROPFRAGMENTS' )
		 || ( $key eq 'NEWNOSYN' )
		 || ( $key eq 'SYNWITHMSS' )
		 || ( $key eq 'BOGUSTCPFLAGS' )
		 || ( $key eq 'LIMITRST' )
		 || ( $key eq 'SYNPROXY' ) )
	{
		if ( $protocol !~ /TCP/i && $protocol !~ /FTP/i )
		{
			&zenlog( "$key rule is only available in farms based in protocol TCP or FTP." );
			return -1;
		}
	}

	use Switch;
	switch ( $key )
	{
		# comented rules aren't finished
		# global rules
		case 'SSHBRUTEFORCE' { $output = &setDDOSSshBruteForceRule(); }
		case 'DROPICMP'      { $output = &setDDOSDropIcmpRule(); }

		#~ case 'PORTSCANNING'		{ $output = &setDDOSPortScanningRule();		}

		# rules for farms
		case 'LIMITCONNS' { $output = &setDDOSLimitConnsRule( $ruleName, \%hash ); }
		case 'LIMITSEC' { $output = &setDDOSLimitSecRule( $ruleName, \%hash ); }

		#~ case 'INVALID'				{ $output = &setDDOSInvalidPacketRule();	}
		#~ case 'BLOCKSPOOFED'	{ $output = &setDDOSBlockSpoofedRule();	}

		# rules for tcp farms
		case 'BOGUSTCPFLAGS'
		{
			$output = &setDDOSBogusTcpFlagsRule( $ruleName, \%hash );
		}
		case 'LIMITRST' { $output = &setDDOSLimitRstRule( $ruleName, \%hash ); }

		#~ case 'DROPFRAGMENTS'	{ $output = &setDDOSDropFragmentsRule(); }
		#~ case 'NEWNOSYN'				{ $output = &setDDOSNewNoSynRule();		 }
		#~ case 'SYNWITHMSS'			{ $output = &setDDOSSynWithMssRule();	 }
		#~ case 'SYNPROXY'				{ $output = &setDDOSynProxyRule();			 }
	}

	return $output;
}

=begin nd
        Function: setDDOSStopRule

        Remove iptables rules

        Parameters:
				ruleName		- id that indetify a rule, ( key = 'farms' to remove rules from farm )
				farmname 	- farm name
				
        Returns:
				== 0	- Successful
             != 0	- Number of rules didn't boot

=cut

sub setDDOSStopRule
{
	my ( $ruleName, $farmName ) = @_;
	my $output = 0;

	my $ind++;
	foreach my $rule ( @{ &getDDOSLookForRule( $ruleName, $farmName ) } )
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

	&zenlog( "Booting ddos system... " );
	&setDDOSCreateFileConf();

	#create  PORT_SCANNING chain
	# /sbin/iptables -N PORT_SCANNING

	if ( -e $confFile )
	{
		my $fileHandle = Config::Tiny->read( $confFile );
		foreach my $ruleName ( keys %{ $fileHandle } )
		{
			if ( $fileHandle->{ $ruleName }->{ 'type' } eq 'farm' )
			{
				my $farmList = $fileHandle->{ $ruleName }->{ 'farms' };
				my @farms = split ( ' ', $farmList );
				foreach my $farmName ( @farms )
				{
					$output++ if ( &setDDOSRunRule( $ruleName, $farmName ) != 0 );
				}
			}
			elsif ( $fileHandle->{ $ruleName }->{ 'type' } eq 'system' )
			{
				if ( $fileHandle->{ $ruleName }->{ 'status' } eq "up" )
				{
					$output++ if ( &setDDOSRunRule( $ruleName, 'status' ) != 0 );
				}
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
	my $output   = 0;
	my $confFile = &getGlobalConfiguration( 'ddosConf' );

	if ( -e $confFile )
	{
		my $fileHandle = Config::Tiny->read( $confFile );
		foreach my $rule ( keys %{ $fileHandle } )
		{
			# Applied to farm
			if ( $fileHandle->{ $rule }->{ 'type' } eq "farm" )
			{
				if ( $fileHandle->{ $rule }->{ 'farms' } )
				{
					my $farmList = $fileHandle->{ $rule }->{ 'farms' };
					my @farms = split ( ' ', $farmList );
					foreach my $farmName ( @farms )
					{
						$output++ if ( &setDDOSStopRule( $rule, $farmName ) != 0 );
					}
				}
			}

			# Applied to balancer
			elsif ( $fileHandle->{ $rule }->{ 'type' } eq 'system' )
			{
				if ( $fileHandle->{ $rule }->{ 'status' } eq 'up' )
				{
					$output++ if ( &setDDOSStopRule( $rule ) != 0 );
				}
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
				rule		 		- id that indetify a rule
				farmname - farm name
				
        Returns:
				== 0	- Successful
             != 0	- Error

=cut

sub setDDOSCreateRule
{
	my ( $rule, $farmName ) = @_;
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

	if ( $farmName )
	{
		my $farmList = $fileHandle->{ $rule }->{ 'farms' };
		if ( $farmList !~ /(^| )$farmName( |$)/ )
		{
			$output = &setDDOSRunRule( $rule, $farmName );

			if ( $output != -2 )
			{
				$fileHandle = Config::Tiny->read( $confFile );
				$fileHandle->{ $rule }->{ 'farms' } = "$farmList $farmName";
				$fileHandle->write( $confFile );
			}
			else
			{
				&zenlog( "Rule $rule only is available for TCP protocol" );
			}
		}
	}

	# check param is down
	elsif ( $fileHandle->{ $rule }->{ 'status' } ne "up" )
	{
		$fileHandle->{ $rule }->{ 'status' } = "up";
		$fileHandle->write( $confFile );

		$output = &setDDOSRunRule( $rule );
	}

	return $output;
}

=begin nd
        Function: setDDOSCreateRule

        Create a DDoS rules
        This rules have two types: applied to farm or balancer

        Parameters:
				rule		 - id that indetify a rule
				farmname - farm name
				
        Returns:
				== 0	- Successful
             != 0	- Error

=cut

sub setDDOSDeleteRule
{
	my ( $rule, $farmName ) = @_;
	my $confFile   = &getGlobalConfiguration( 'ddosConf' );
	my $fileHandle = Config::Tiny->read( $confFile );
	my $output;

	if ( -e $confFile )
	{
		if ( $farmName )
		{
			$fileHandle->{ $rule }->{ 'farms' } =~ s/(^| )$farmName( |$)/ /;
			$fileHandle->write( $confFile );
			$output = &setDDOSStopRule( $rule, $farmName );
		}
		else
		{
			$fileHandle->{ $rule }->{ 'status' } = "down";
			$fileHandle->write( $confFile );
			$output = &setDDOSStopRule( $rule );
		}
	}
	return $output;
}

# Only TCP farms
### Block packets with bogus TCP flags ###
# &setDDOSBogusTcpFlagsRule ( ruleOpt )
sub setDDOSBogusTcpFlagsRule
{
	my ( $rule, $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	#~ my $key    = "BOGUSTCPFLAGS";
	my $logMsg = "[Blocked by rule $rule]";

# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j DROP
	my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	my $output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_1' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags FIN,SYN FIN,SYN "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_2' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags SYN,RST SYN,RST "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_3' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags SYN,FIN SYN,FIN "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_4' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags FIN,RST FIN,RST "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_5' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags FIN,ACK FIN -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags FIN,ACK FIN "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_6' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ACK,URG URG -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags ACK,URG URG "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_7' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ACK,FIN FIN -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags ACK,FIN FIN "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_8' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ACK,PSH PSH -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags ACK,PSH PSH "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_9' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ALL ALL -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags ALL ALL "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_10' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ALL NONE -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags ALL NONE "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_11' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags ALL FIN,PSH,URG "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_12' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ALL SYN,FIN,PSH,URG -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags ALL SYN,FIN,PSH,URG "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_13' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

# /sbin/iptables -t raw -A PREROUTING -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP
	$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -t raw -A PREROUTING "    # select iptables struct
	  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags ALL SYN,RST,ACK,FIN,URG "    # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_14' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	return $output;
}

### Limit connections per source IP ###
# &setDDOSLimitConnsRule ( ruleOpt )
sub setDDOSLimitConnsRule
{
	my ( $rule, $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	#~ my $key    = "LIMITCONNS";
	my $logMsg = "[Blocked by rule $rule]";
	my $chain  = "INPUT";                     # default, this chain is for L7 apps
	my $dest   = $ruleOpt{ 'vip' };
	my $port   = $ruleOpt{ 'vport' };
	my $output;
	my $limitConns = &getDDOSParam( $rule, 'limitConns' );

	# especific values to L4 farm
	if ( &getFarmType( $ruleOpt{ 'farmName' } ) eq "l4xnat" )
	{
		$chain = "FORWARD";
		my @run = &getFarmServers( $ruleOpt{ 'farmName' } );
		for my $l4Backends ( @run )
		{
			my @l_serv = split ( "\;", $l4Backends );
			$dest = "-d $l_serv[1]";
			$port = "--dport $l_serv[2]";

# /sbin/iptables -A FORWARD -t filter -d 1.1.1.1,54.12.1.1 -p tcp --dport 5 -m connlimit --connlimit-above 5 -m comment --comment "DDOS_LIMITCONNS_aa" -j REJECT --reject-with tcp-reset
			my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )

			  #~ . " -A INPUT -t filter "         # select iptables struct
			  . " -A $chain -t filter "                          # select iptables struct
			  . "$dest $ruleOpt{ 'protocol' } $port "            # who is destined
			  . "-m connlimit --connlimit-above $limitConns "    # rules for block
			  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

			$output = &iptSystem( "$cmd -j LOG  --log-prefix \"$logMsg\" --log-level 4 " );

			$output = &iptSystem( "$cmd -j REJECT --reject-with tcp-reset" );
		}
	}

	else
	{
# /sbin/iptables -A FORWARD -t filter -d 1.1.1.1,54.12.1.1 -p tcp --dport 5 -m connlimit --connlimit-above 5 -m comment --comment "DDOS_LIMITCONNS_aa" -j REJECT --reject-with tcp-reset
		my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )

		  #~ . " -A INPUT -t filter "         # select iptables struct
		  . " -A $chain -t filter "                          # select iptables struct
		  . "$dest $ruleOpt{ 'protocol' } $port "            # who is destined
		  . "-m connlimit --connlimit-above $limitConns "    # rules for block
		  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

		my $output =
		  &iptSystem( "$cmd -j LOG  --log-prefix \"$logMsg\" --log-level 4 " );

		$output = &iptSystem( "$cmd -j REJECT --reject-with tcp-reset" );
	}
	if ( $output != 0 )
	{
		&zenlog( "Error appling '$rule' rule to farm '$ruleOpt{ 'farmName' }'." );
	}

	return $output;
}

# Only TCP farms
### Limit RST packets ###
# &setDDOSLimitRstRule ( ruleOpt )
sub setDDOSLimitRstRule
{
	my ( $rule, $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	#~ my $key        = "LIMITRST";
	my $logMsg     = "[Blocked by rule $rule]";
	my $limit      = &getDDOSParam( $rule, 'limit' );
	my $limitBurst = &getDDOSParam( $rule, 'limitBurst' );

# /sbin/iptables -A PREROUTING -t mangle -p tcp --tcp-flags RST RST -m limit --limit 2/s --limit-burst 2 -j ACCEPT
	my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -A PREROUTING -t mangle "    # select iptables struct
	  . "-j ACCEPT $ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "--tcp-flags RST RST -m limit --limit $limit/s --limit-burst $limitBurst " # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";            # comment

	my $output = &iptSystem( $cmd );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_1' rule to farm '$ruleOpt{ 'farmName' }'." );
	}
	else
	{
		# /sbin/iptables -I PREROUTING -t mangle -p tcp --tcp-flags RST RST -j DROP
		$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
		  . " -A PREROUTING -t mangle "    # select iptables struct
		  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
		  . "--tcp-flags RST RST "    # rules for block
		  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

		my $output = &setIPDSDropAndLog( $cmd, $logMsg );
		if ( $output != 0 )
		{
			&zenlog( "Error appling '${rule}_2' rule to farm '$ruleOpt{ 'farmName' }'." );
		}
	}
	return $output;
}

### Limit new TCP connections per second per source IP ###
# &setDDOSLimitSecRule ( ruleOpt )
sub setDDOSLimitSecRule
{
	my ( $rule, $ruleOptRef ) = @_;
	my %ruleOpt = %{ $ruleOptRef };

	#~ my $key        = "LIMITSEC";
	my $logMsg     = "[Blocked by rule $rule]";
	my $limit      = &getDDOSParam( $rule, 'limit' );
	my $limitBurst = &getDDOSParam( $rule, 'limitBurst' );

# /sbin/iptables -I PREROUTING -t mangle -p tcp -m conntrack --ctstate NEW -m limit --limit 60/s --limit-burst 20 -j ACCEPT
	my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
	  . " -A PREROUTING -t mangle "    # select iptables struct
	  . "-j ACCEPT $ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
	  . "-m conntrack --ctstate NEW -m limit --limit $limit/s --limit-burst $limitBurst " # rules for block
	  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";                   # comment

	my $output = &iptSystem( $cmd );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${rule}_1' rule to farm '$ruleOpt{ 'farmName' }'." );
	}
	else
	{
	  # /sbin/iptables -I PREROUTING -t mangle -p tcp -m conntrack --ctstate NEW -j DROP
		$cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
		  . " -A PREROUTING -t mangle "    # select iptables struct
		  . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
		  . "-m conntrack --ctstate NEW "    # rules for block
		  . "-m comment --comment \"DDOS_${rule}_$ruleOpt{ 'farmName' }\"";    # comment

		my $output = &setIPDSDropAndLog( $cmd, $logMsg );
		if ( $output != 0 )
		{
			&zenlog( "Error appling '${rule}_2' rule to farm '$ruleOpt{ 'farmName' }'." );
		}
	}
	return $output;
}

# All balancer
###  Drop ICMP ###
# &setDDOSDropIcmpRule ( ruleOpt )
sub setDDOSDropIcmpRule
{
	my $key = "drop_icmp";

	#~ my $key    = "DROPICMP";
	my $logMsg = "[Blocked by rule $key]";

	# /sbin/iptables -t raw -A PREROUTING -p icmp -j DROP
	my $cmd = &getGlobalConfiguration( 'iptables' )
	  . " -t raw -A PREROUTING "                   # select iptables struct
	  . "-p icmp "                                 # rules for block
	  . "-m comment --comment \"DDOS_${key}\"";    # comment

	my $output = &setIPDSDropAndLog( $cmd, $logMsg );
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
	my $key = 'ssh_brute_force';

	#~ my $key    = "SSHBRUTEFORCE";
	my $hits = &getDDOSParam( $key, 'hits' );
	my $time = &getDDOSParam( $key, 'time' );
	my $port = &getDDOSParam( $key, 'port' );
	my $logMsg = "[Blocked by rule $key]";

# /sbin/iptables -I PREROUTING -t mangle -p tcp --dport ssh -m conntrack --ctstate NEW -m recent --set
	my $cmd =
	  &getGlobalConfiguration( 'iptables' )
	  . " -A PREROUTING -t mangle "                      # select iptables struct
	  . "-p tcp --dport $port "                          # who is destined
	  . "-m conntrack --ctstate NEW -m recent --set "    # rules for block
	  . "-m comment --comment \"DDOS_$key\"";            # comment

	my $output = &iptSystem( $cmd );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_1' rule." );
	}

# /sbin/iptables -I PREROUTING -t mangle -p tcp --dport ssh -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 10 -j DROP
	$cmd =
	  &getGlobalConfiguration( 'iptables' )
	  . " -A PREROUTING -t mangle "                      # select iptables struct
	  . "-p tcp --dport $port "                          # who is destined
	  . "-m conntrack --ctstate NEW -m recent --update --seconds $time --hitcount $hits " # rules for block
	  . "-m comment --comment \"DDOS_$key\"";                                             # comment

	$output = &setIPDSDropAndLog( $cmd, $logMsg );
	if ( $output != 0 )
	{
		&zenlog( "Error appling '${key}_2' rule." );
	}

	return $output;
}

1;

#######
# NOT WORK YET
#######

# solo usable en chain INPUT / FORWARD
### Use SYNPROXY on all ports (disables connection limiting rule) ###
#/sbin/iptables -t raw -A PREROUTING -p tcp -m tcp --syn -j CT --notrack
#/sbin/iptables -A INPUT -p tcp -m tcp -m conntrack --ctstate INVALID,UNTRACKED -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460
#/sbin/iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

#~ # balancer
#~ ### SSH brute-force protection ###
#~ # &setDDOSSshBruteForceRule
#~ sub setDDOSynProxyRule
#~ {
#~ my ( $ruleOptRef ) = @_;
#~ my %ruleOpt = %{ $ruleOptRef };

#~ my $key = "SYNPROXY";
#~ my $logMsg = "[Blocked by rule $key]";
#~ my $scale = getDDOSParam ( $key, 'scale' );
#~ my $mss = getDDOSParam ( $key, 'mss' );

#~ # iptables -t raw -A PREROUTING -p tcp -m tcp --syn -j CT
#~ my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
#~ . " -A PREROUTING -t raw "           																			# select iptables struct
#~ . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " 						# who is destined
#~ . "-m tcp --syn " 																										# rules for block
#~ . "-j CT "																													# action
#~ . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";	# comment
#~ my $output = &iptSystem( "$cmd" );

#~ # iptables -I INPUT -p tcp -m tcp -m conntrack --ctstate NEW -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460
#~ $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
#~ . " -A INPUT "           																								# select iptables struct
#~ . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " 					# who is destined
#~ . "-j SYNPROXY --sack-perm --timestamp --wscale $scale --mss $mss "	# action
#~ . "-m conntrack --ctstate NEW "														 				# rules for block
#~ . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";	# comment
#~ $output = &iptSystem( "$cmd" );

#~ # iptables -I FORWARD -p tcp -m tcp -m conntrack --ctstate NEW -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460
#~ $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
#~ . " -A FORWARD "           																						# select iptables struct
#~ . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " 					# who is destined
#~ . "-j SYNPROXY --sack-perm --timestamp --wscale $scale --mss $mss "	# action
#~ . "-m conntrack --ctstate NEW "														 				# rules for block
#~ . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";	# comment
#~ $output = &iptSystem( "$cmd" );

#~ # iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
#~ $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
#~ . " -A INPUT "           																				# select iptables struct
#~ . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " 	# who is destined
#~ . "-m conntrack --ctstate INVALID " 													# rules for block
#~ . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";	# comment
#~ $output = &setIPDSDropAndLog ( $cmd, $logMsg );

#~ # iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP
#~ $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
#~ . " -A FORWARD "           																				# select iptables struct
#~ . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " 	# who is destined
#~ . "-m conntrack --ctstate INVALID " 													# rules for block
#~ . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";	# comment
#~ $output = &setIPDSDropAndLog ( $cmd, $logMsg );

#~ if ( $output != 0 )
#~ {
#~ &zenlog( "Error appling '${key}_2' rule." );
#~ }

#~ return $output;
#~ }

# Balancer
### Protection against port scanning ###
# &setDDOSPortScanningRule ( ruleOpt )
#~ sub setDDOSPortScanningRule
#~ {
#~ # my ( $ruleOptRef ) = @_;
#~ # my %ruleOpt = %{ $ruleOptRef };

#~ my $key = "PORTSCANNING";
#~ my $logMsg = "[Blocked by rule $key]";
#~ my $output;

#~ my $portScan = &getDDOSParam( $key, 'portScan');
#~ my $blTime = &getDDOSParam( $key, 'blTime');
#~ my $time = &getDDOSParam( $key, 'time');
#~ my $hits = &getDDOSParam( $key, 'hits');

#~ my $cmd = &getGlobalConfiguration( 'iptables' )
#~ . " -N PORT_SCANNING -t raw ";
#~ &iptSystem( $cmd );

#~ # iptables -A PREROUTING -t raw -p tcp --tcp-flags SYN,ACK,FIN,RST RST -j PORT_SCANNING
#~ $cmd = &getGlobalConfiguration( 'iptables' )
#~ . " -A PREROUTING --table raw "     # select iptables struct
#~ # . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
#~ . "-j PORT_SCANNING "
#~ . "-p tcp --tcp-flags SYN,ACK,FIN,RST RST "    # rules for block
#~ # . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment
#~ . "-m comment --comment \"DDOS_${key}\"";    # comment
#~ $output = &iptSystem( $cmd );

#~ # iptables -A PORT_SCANNING -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN
#~ $cmd = &getGlobalConfiguration( 'iptables' )
#~ . " -A PORT_SCANNING -t raw "     # select iptables struct
#~ . "-j RETURN "
#~ . "-p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit $time/s --limit-burst $hits "    # rules for block
#~ . "-m comment --comment \"DDOS_${key}\"";    # comment
#~ $output = &iptSystem( $cmd );

#~ # /sbin/iptables -A port-scanning -j DROP
#~ $cmd = &getGlobalConfiguration( 'iptables' )
#~ . " -A PORT_SCANNING -t raw "     # select iptables struct
#~ . "-m comment --comment \"DDOS_${key}\"";    # comment
#~ $output = &setIPDSDropAndLog ( $cmd, $logMsg );

#~ if ( $output != 0 )
#~ {
#~ &zenlog( "Error appling '$key' rule." );
#~ }

#~ # /sbin/iptables -A PREROUTING -t mangle -m recent --name portscan --rcheck --seconds $blTime
#~ $cmd = &getGlobalConfiguration( 'iptables' )
#~ . " -A PREROUTING -t mangle " # select iptables struct
#~ . "-m recent --name portscan --rcheck --seconds $blTime "
#~ . "-m comment --comment \"DDOS_${key}\"";    # comment
#~ $output = &setIPDSDropAndLog ( $cmd, $logMsg );

#~ # /sbin/iptables -A OUTPUT -t mangle -m recent --name portscan --rcheck --seconds $blTime
#~ $cmd = &getGlobalConfiguration( 'iptables' )
#~ . " -A OUTPUT -t mangle "    # select iptables struct
#~ . "-m recent --name portscan --rcheck --seconds $blTime "
#~ . "-m comment --comment \"DDOS_${key}\"";    # comment
#~ $output = &setIPDSDropAndLog ( $cmd, $logMsg );

#~ # /sbin/iptables -A PREROUTING -t mangle -m recent --name portscan --remove
#~ $cmd = &getGlobalConfiguration( 'iptables' )
#~ . " -A PREROUTING -t mangle " # select iptables struct
#~ . "-m recent --name portscan --remove "
#~ . "-m comment --comment \"DDOS_${key}\"";    # comment
#~ $output = &iptSystem( $cmd );

#~ # /sbin/iptables -A OUTPUT -t mangle -m recent --name portscan --remove
#~ $cmd = &getGlobalConfiguration( 'iptables' )
#~ . " -A OUTPUT -t mangle "    # select iptables struct
#~ . "-m recent --name portscan --remove "
#~ . "-m comment --comment \"DDOS_${key}\"";    # comment
#~ $output = &iptSystem( $cmd );

#~ # /sbin/iptables -A PREROUTING -t mangle -p tcp -m tcp --dport $portScan -m recent --name portscan --set -j DROP
#~ $cmd = &getGlobalConfiguration( 'iptables' )
#~ . " -A PREROUTING -t mangle " # select iptables struct
#~ . "-p tcp -m tcp --dport $portScan -m recent --name portscan --set "
#~ . "-m comment --comment \"DDOS_${key}\"";    # comment
#~ $output = &setIPDSDropAndLog ( $cmd, $logMsg );

#~ # /sbin/iptables -A OUTPUT -t mangle -p tcp -m tcp --dport $portScan -m recent --name portscan --set -j DROP
#~ $cmd = &getGlobalConfiguration( 'iptables' )
#~ . " -A OUTPUT -t mangle "    # select iptables struct
#~ . "-p tcp -m tcp --dport $portScan -m recent --name portscan --set "
#~ . "-m comment --comment \"DDOS_${key}\"";    # comment
#~ $output = &setIPDSDropAndLog ( $cmd, $logMsg );

#~ return $output;
#~ }

#~ # only ipv4
#~ ### Drop fragments in all chains ###
#~ # &setDDOSDropFragmentsRule ( ruleOpt )
#~ sub setDDOSDropFragmentsRule
#~ {
#~ my ( $ruleOptRef ) = @_;
#~ my %ruleOpt = %{ $ruleOptRef };

#~ my $key = "DROPFRAGMENTS";
#~ my $logMsg = "[Blocked by rule $key]";

#~ # only in IPv4
#~ if ( &getBinVersion( $ruleOpt{ 'farmName' } ) =~ /6/ )
#~ {
#~ return 0;
#~ }

#~ # /sbin/iptables -t raw -A PREROUTING -f -j DROP
#~ my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
#~ . " -t raw -A PREROUTING "    # select iptables struct
#~ . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
#~ . "-f "    # rules for block
#~ . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

#~ my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
#~ if ( $output != 0 )
#~ {
#~ &zenlog( "Error appling '$key' rule to farm '$ruleOpt{ 'farmName' }'." );
#~ }

#~ return $output;
#~ }

#~ ### Block spoofed packets ###
#~ # &setDDOSBlockSpoofedRule ( ruleOpt )
#~ sub setDDOSBlockSpoofedRule
#~ {
#~ my ( $ruleOptRef ) = @_;
#~ my %ruleOpt = %{ $ruleOptRef };

#~ my $key = "BLOCKSPOOFED";
#~ my $logMsg = "[Blocked by rule $key]";

#~ # /sbin/iptables -t raw -A PREROUTING -s 224.0.0.0/3 -j DROP
#~ my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
#~ . " -t raw -A PREROUTING "    # select iptables struct
#~ . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
#~ . "-s 192.0.2.0/24,192.168.0.0/16,10.0.0.0/8,0.0.0.0/8,240.0.0.0/5 " # rules for block
#~ . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";     # comment

#~ my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
#~ if ( $output != 0 )
#~ {
#~ &zenlog( "Error appling '${key}_1' rule to farm '$ruleOpt{ 'farmName' }'." );
#~ }

#~ # /sbin/iptables -t raw -A PREROUTING -s 127.0.0.0/8 ! -i lo -j DROP
#~ $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
#~ . " -t raw -A PREROUTING "    # select iptables struct
#~ . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
#~ . "-s 127.0.0.0/8 ! -i lo "    # rules for block
#~ . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

#~ $output = &setIPDSDropAndLog ( $cmd, $logMsg );
#~ if ( $output != 0 )
#~ {
#~ &zenlog( "Error appling '${key}_2' rule to farm '$ruleOpt{ 'farmName' }'." );
#~ }

#~ return $output;
#~ }

#~ # Only TCP farms
#~ ### Drop SYN packets with suspicious MSS value ###
#~ # &setDDOSSynWithMssRule ( ruleOpt )
#~ sub setDDOSSynWithMssRule
#~ {
#~ my ( $ruleOptRef ) = @_;
#~ my %ruleOpt = %{ $ruleOptRef };

#~ my $key = "SYNWITHMSS";
#~ my $logMsg = "[Blocked by rule $key]";

#~ # /sbin/iptables -t raw -A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP
#~ my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
#~ . " -t raw -A PREROUTING "    # select iptables struct
#~ . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
#~ . "-m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 "  # rules for block
#~ . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

#~ my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
#~ if ( $output != 0 )
#~ {
#~ &zenlog( "Error appling '$key' rule to farm '$ruleOpt{ 'farmName' }'." );
#~ }

#~ return $output;
#~ }

#~ # Only TCP farms
#~ # restrictive rule
#~ ### Drop TCP packets that are new and are not SYN ###
#~ # &setDDOSNewNoSynRule ( ruleOpt )
#~ sub setDDOSNewNoSynRule
#~ {
#~ my ( $ruleOptRef ) = @_;
#~ my %ruleOpt = %{ $ruleOptRef };

#~ my $key = "NEWNOSYN";
#~ my $logMsg = "[Blocked by rule $key]";

#~ # sbin/iptables -t raw -A PREROUTING -p tcp ! --syn -m conntrack --ctstate NEW -j DROP
#~ my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
#~ . " -t raw -A PREROUTING "    # select iptables struct
#~ . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
#~ . "! --syn -m conntrack --ctstate NEW "    # rules for block
#~ . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

#~ my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
#~ if ( $output != 0 )
#~ {
#~ &zenlog( "Error appling '$key' rule to farm '$ruleOpt{ 'farmName' }'." );
#~ }

#~ return $output;
#~ }

#~ # permivisve rule
#~ ### Drop invalid packets ###
#~ # &setDDOSInvalidPacketRule ( ruleOpt )
#~ sub setDDOSInvalidPacketRule
#~ {
#~ my ( $ruleOptRef ) = @_;
#~ my %ruleOpt = %{ $ruleOptRef };

#~ my $key = "INVALID";
#~ my $logMsg = "[Blocked by rule $key]";

#~ # /sbin/iptables -t raw -A PREROUTING -m conntrack --ctstate INVALID -j DROP
#~ my $cmd = &getBinVersion( $ruleOpt{ 'farmName' } )
#~ . " -t raw -A PREROUTING "    # select iptables struct
#~ . "$ruleOpt{ 'vip' } $ruleOpt{ 'protocol' } $ruleOpt{ 'vport' } " # who is destined
#~ . "-m conntrack --ctstate INVALID "    # rules for block
#~ . "-m comment --comment \"DDOS_${key}_$ruleOpt{ 'farmName' }\"";    # comment

#~ my $output = &setIPDSDropAndLog ( $cmd, $logMsg );
#~ if ( $output != 0 )
#~ {
#~ &zenlog( "Error appling '$key' rule to farm '$ruleOpt{ 'farmName' }'." );
#~ }

#~ return $output;
#~ }
