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

use Zevenet::IPDS::RBL::Core;

=begin nd
Function: runRBLIptablesRule

	Create a iptables for a farm with a action ( -A, -I, -D )

Parameters:
	Rulename -  Rule name
	Farmname -  Farm name. If farm name is in blank, the rule applies to all destine IPs and ports
	Action - Action to apply to iptables. The available options are: 'append', create the rule the last in the iptables list;
	  'insert', create the rule the first in the iptables list; or 'delete' delete the rule from iptables list
				
Returns:
	Integer - 0 on success or other value on failure
	
FIXME: Define the chain and the table for iptables
	
=cut

sub runRBLIptablesRule
{
	my ( $rule, $farmname, $action ) = @_;
	my $error;

	require Zevenet::IPDS::Core;
	require Zevenet::Netfilter;

	my $nfqueue   = &getRBLObjectRuleParam( $rule, 'nf_queue_number' );
	my $rbl_chain = &getIPDSChain( "rbl" );
	my @farmMatch = &getIPDSFarmMatch( $farmname );

	if ( $action eq "insert" )
	{
		$action = "-I";
	}
	elsif ( $action eq "append" )
	{
		$action = "-A";
	}
	elsif ( $action eq "delete" )
	{
		$action = "-D";
	}
	else
	{
		$error = -1;
		&zenlog( "Wrong action to create the rule " );
	}

	# only check packets with SYN flag: "--tcp-flags SYN SYN"
	# if packetbl is not running, return packet to netfilter flow: "--queue-bypass"

# iptables -I INPUT -p tcp --tcp-flags SYN SYN -i eth0 --dport 80 -j NFQUEUE --queue-num 0 --queue-bypass

	# execute without interblock
	foreach my $ruleParam ( @farmMatch )
	{
		my $tcp;
		my $cmd;

		# not add rules to UDP ports
		if ( $ruleParam !~ /\-\-protocol udp/ )
		{
			# It is necessary specific the tcp protocol to check add SYN flag option
			if ( $ruleParam !~ /\-\-protocol tcp/ )
			{
				$tcp = "--protocol tcp";
			}
			else
			{
				$tcp = "";
			}
			$cmd =
			    &getGlobalConfiguration( 'iptables' )
			  . " $action $rbl_chain -t raw $ruleParam $tcp --tcp-flags SYN SYN -j NFQUEUE --queue-num $nfqueue --queue-bypass"
			  . " -m comment --comment \"RBL,${rule},$farmname\"";

			# thre rule already exists
			return 0 if ( &getIPDSRuleExists( $cmd ) );

			$error = &iptSystem( $cmd );
		}
	}

	return $error;
}

=begin nd
Function: runRBLStart

	Run packetbl binary

Parameters:
	String - Rule name 
	
Returns:
	integer - 0 on success or other value on failure
	
=cut

sub runRBLStartPacketbl
{
	my $rule = shift;

	# Get packetbl bin
	my $packetbl = &getGlobalConfiguration( "packetbl_bin" );

	# Look for a not used nf queue and assign it to this rule
	&setRBLCreateNfqueue( $rule );

	# Create packetbl config file
	&setRBLPacketblConfig( $rule );

	# Get packetbl configuration file
	my $configfile = &getRBLPacketblConfig( $rule );

	# Run packetbl
	my $error = system ( "bash", "-c",
						 ". /etc/profile_packetbl && $packetbl -f $configfile" );
	&zenlog( "Error, starting packetbl" ) if ( $error );
	return $error;
}

=begin nd
Function: runRBLStopPacketbl

	Stop packetbl bin

Parameters:
	String - Rule name 
	
Returns:

FIXME:
	if packetbl is stopped without delete its pid file, the rule will appear in UP status
	
=cut

sub runRBLStopPacketbl
{
	my $rule = shift;

	# Remove associated nfqueue from configfile
	&setRBLRemoveNfqueue( $rule );

	# exec kill
	my $pid = &getRBLPacketblPid( $rule );

	return &logAndRun( "kill $pid" );
}

=begin nd
Function: runRBLRestartPacketbl

	Restart packetbl bin. It is useful to reload configuration

Parameters:
	String - Rule name 
	
Returns:
	integer - 0 on success or other value on failure

=cut

sub runRBLRestartPacketbl
{
	my $rule = shift;
	&runRBLStopPacketbl( $rule );
	my $error = &runRBLStartPacketbl( $rule );
	return $error;
}

=begin nd
Function: setRBLPacketblConfig

	before than exec packetbl, configure a new config file with rule configuration and overwrite the existing one

Parameters:
	String - Rule name 
	
Returns:
	Integer - 0 on success or other value on failure

=cut

sub setRBLPacketblConfig
{
	my $rule = shift;

	require Zevenet::Lock;
	my $params = &getRBLObjectRule( $rule );
	my $error  = 0;

	# filling config file
	my $fileContent = "
<host>";

	# not review local traffic
	if ( $params->{ 'local_traffic' } eq 'no' )
	{
		$fileContent .= "
	whitelist	192.168.0.0/16
	whitelist	169.254.0.0/16
	whitelist	172.16.0.0/12
	whitelist	10.0.0.0/8";
	}

	foreach my $domain ( @{ $params->{ 'domains' } } )
	{
		$fileContent .= "\n\tblacklistbl\t$domain";
	}

	$fileContent .= "	
</host>
FallthroughAccept	yes
AllowNonPort25		yes
AllowNonSyn			no
DryRun			$params->{'only_logging'}
CacheSize	$params->{'cache_size'}
CacheTTL		$params->{'cache_time'}
LogFacility	daemon
AlternativeDomain		rbl.zevenet.com
AlternativeResolveFile	usr/local/zevenet/config/ipds/rbl/zevenet_nameservers.conf
Queueno		$params->{'nf_queue_number'}
Queuesize	$params->{'queue_size'}
Threadmax	$params->{'threadmax'}
LogLevel	$params->{'log_level'}
";

	# save file
	my $fh;
	my $filename = &getRBLPacketblConfig( $rule );
	$fh = &openlock( '>', $filename );
	unless ( $fh )
	{
		&zenlog( "Could not open file $filename: $!" );
		return -1;
	}
	print $fh $fileContent;
	&closelock( $fh );

	return $error;
}

=begin nd
Function: setRBLCreateNfqueue

	Looking for a not used nf queue and assigned it to a RBL rule

Parameters:
	String - Rule name 
	
Returns:
	integer - netfilter queue number
	
=cut

sub setRBLCreateNfqueue
{
	my $rule = shift;

	require Config::Tiny;
	require Zevenet::IPDS::RBL::Config;

	my $queue_num = 0;
	my @rules     = &getRBLRuleList();
	require Config::Tiny;
	my $fileHandle = Config::Tiny->read( $rblConfigFile );
	my @queue_list;

	foreach my $rule ( @rules )
	{
		if ( $fileHandle->{ $rule }->{ 'nf_queue_number' } ne "" )
		{
			push @queue_list, $fileHandle->{ $rule }->{ 'nf_queue_number' };
		}
	}

	# Increase $queue_num until to find one is not used
	while ( $queue_num < 65000 )
	{
		last if ( !grep ( /^$queue_num$/, @queue_list ) );
		$queue_num = $queue_num + 1;
	}

	# Save this queue
	&setRBLObjectRuleParam( $rule, 'nf_queue_number', $queue_num );

	return $queue_num;
}

=begin nd
Function: setRBLRemoveNfqueue

	Remove the associated netfilter queue for a rule

Parameters:
	String - Rule name 
	
Returns:
	none - .
	
=cut

sub setRBLRemoveNfqueue
{
	my $rule = shift;

	require Zevenet::IPDS::RBL::Config;
	&setRBLObjectRuleParam( $rule, 'nf_queue_number', '' );
}

1;
