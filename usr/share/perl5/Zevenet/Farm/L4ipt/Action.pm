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

my $configdir = &getGlobalConfiguration( 'configdir' );

=begin nd
Function: startL4Farm

	Run a l4xnat farm

Parameters:
	farmname - Farm name

Returns:
	Integer - return 0 on success or different of 0 on failure

=cut

sub startL4Farm    # ($farm_name)
{
	&zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING" );
	my $farm_name = shift;

	require Zevenet::Lock;
	require Zevenet::Net::Util;
	require Zevenet::Netfilter;
	require Zevenet::Farm::L4xNAT::Config;

	&zlog( "Starting farm $farm_name" ) if &debug == 2;

	my $status = 0;

	&zenlog( "startL4Farm << farm_name:$farm_name", "debug", "LSLB" )
	  if &debug;

	# initialize a farm struct
	my $farm = &getL4FarmStruct( $farm_name );

	require Tie::File;

	tie my @configfile, 'Tie::File', "$configdir\/$$farm{ filename }";
	foreach ( @configfile )
	{
		s/\;down/\;up/g;
		last;
	}
	untie @configfile;

	my $l4sd = &getGlobalConfiguration( 'l4sd' );

	# Load L4 scheduler if needed
	if ( $$farm{ lbalg } eq 'leastconn' && -e "$l4sd" )
	{
		system ( "$l4sd >/dev/null 2>&1 &" );
	}

	if ( $$farm{ vproto } =~ /sip|ftp/ )    # helpers
	{
		&loadL4Modules( $$farm{ vproto } );

		my $rule_ref = &genIptHelpers( $farm );
		foreach my $rule ( @{ $rule_ref } )
		{
			$status |= &runIptables( &applyIptRuleAction( $rule, 'append' ) );
		}
	}

	my $rules;
	my $lowest_prio;
	my $server_prio;    # reference to the selected server for prio algorithm

	## Set ip rule mark ##
	my $ip_bin      = &getGlobalConfiguration( 'ip_bin' );
	my $vip_if_name = &getInterfaceOfIp( $farm->{ vip } );
	my $vip_if      = &getInterfaceConfig( $vip_if_name );
	my $table_if =
	  ( $vip_if->{ type } eq 'virtual' ) ? $vip_if->{ parent } : $vip_if->{ name };

# insert the save rule, then insert on top the restore rule
# WARNING: Set Connmark rules BEFORE getting the farm rules or Connmark rules will be misplaced
	&setIptConnmarkSave( $farm_name, 'true' );
	&setIptConnmarkRestore( $farm_name, 'true' );

	foreach my $server ( @{ $$farm{ servers } } )
	{
		&zenlog( "startL4Farm :: server:$server->{id}", "debug", "LSLB" ) if &debug;

		my $backend_rules;

		## Set ip rule mark ##
		my $ip_cmd = "$ip_bin rule add fwmark $server->{ tag } table table_$table_if";
		&logAndRun( $ip_cmd );

		# TMP: leastconn dynamic backend status check
		if ( $$farm{ lbalg } =~ /weight|leastconn/ )
		{
			$backend_rules = &getL4ServerActionRules( $farm, $server, 'on' );

			push ( @{ $$rules{ t_mangle_p } }, @{ $$backend_rules{ t_mangle_p } } );
			push ( @{ $$rules{ t_mangle } },   @{ $$backend_rules{ t_mangle } } );
			push ( @{ $$rules{ t_nat } },      @{ $$backend_rules{ t_nat } } );
			push ( @{ $$rules{ t_snat } },     @{ $$backend_rules{ t_snat } } );
		}
		elsif ( $$farm{ lbalg } eq 'prio' && $$server{ status } ne 'fgDOWN' )
		{
			# find the lowest priority server
			if ( $$server{ priority } ne ''
				 && ( $$server{ priority } < $lowest_prio || !defined $lowest_prio ) )
			{
				$server_prio = $server;
				$lowest_prio = $$server{ priority };
			}
		}
	}

	# prio only apply rules to one server
	if ( $server_prio && $$farm{ lbalg } eq 'prio' )
	{
		system ( "echo 10 > /proc/sys/net/netfilter/nf_conntrack_udp_timeout_stream" );
		system ( "echo 5 > /proc/sys/net/netfilter/nf_conntrack_udp_timeout" );

		$rules = &getL4ServerActionRules( $farm, $server_prio, 'on' );
	}

	## lock iptables use ##
	my $iptlock = &getGlobalConfiguration( 'iptlock' );
	my $ipt_lockfile = &openlock( $iptlock, 'w' );

	for my $table ( qw(t_mangle_p t_mangle t_nat t_snat) )
	{
		$status = &applyIptRules( @{ $$rules{ $table } } );
		return $status if $status;
	}

	## unlock iptables use ##
	close $ipt_lockfile;

	# Enable IP forwarding
	&setIpForward( 'true' );

	# Enable active l4 file
	if ( $status == 0 )
	{
		my $piddir = &getGlobalConfiguration( 'piddir' );
		open my $fi, '>', "$piddir\/$$farm{name}\_l4xnat.pid";
		close $fi;
	}

	#enable log rule
	if ( &getL4FarmParam( 'logs', $farm_name ) eq "true" )
	{
		&reloadL4FarmLogsRule( $farm_name, "true" );
	}

	return $status;
}

=begin nd
Function: stopL4Farm

	Stop a l4xnat farm

Parameters:
	farmname - Farm name

Returns:
	Integer - return 0 on success or other value on failure

=cut

sub stopL4Farm    # ($farm_name)
{
	&zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING" );
	my ( $farm_name ) = @_;

	require Zevenet::Lock;
	require Zevenet::Net::Util;
	require Zevenet::Farm::L4xNAT::Config;


	my $status;

	# Remove log rules
	&reloadL4FarmLogsRule( $farm_name, "false" );

	## lock iptables use ##
	my $iptlock = &getGlobalConfiguration( 'iptlock' );
	my $ipt_lockfile = &openlock( $iptlock, 'w' );

	# Disable rules
	my @allrules;

	require Zevenet::Netfilter;
	@allrules = &getIptList( $farm_name, "mangle", "PREROUTING" );
	$status =
	  &deleteIptRules( $farm_name,   "farm", $farm_name, "mangle",
					   "PREROUTING", @allrules );

	@allrules = &getIptList( $farm_name, "nat", "PREROUTING" );
	$status = &deleteIptRules( $farm_name,   "farm", $farm_name, "nat",
							   "PREROUTING", @allrules );

	@allrules = &getIptList( $farm_name, "nat", "POSTROUTING" );
	$status =
	  &deleteIptRules( $farm_name, "farm", $farm_name, "nat", "POSTROUTING",
			   @allrules );

	@allrules = &getIptList( $farm_name, "raw", "PREROUTING" );
	$status =
	  &deleteIptRules( $farm_name,   "farm", $farm_name, "raw",
					   "PREROUTING", @allrules );

	## unlock iptables use ##
	close $ipt_lockfile;

	# Disable active l4xnat file
	my $piddir = &getGlobalConfiguration( 'piddir' );
	unlink ( "$piddir\/$farm_name\_l4xnat.pid" );

	if ( -e "$piddir\/$farm_name\_l4xnat.pid" )
	{
		$status = -1;
	}

	## Delete ip rule mark ##
	my $farm        = &getL4FarmStruct( $farm_name );
	my $ip_bin      = &getGlobalConfiguration( 'ip_bin' );
	&setL4FarmParam( 'status', "down", $farm_name );
	my $vip_if_name = &getInterfaceOfIp( $farm->{ vip } );
	my $vip_if      = &getInterfaceConfig( $vip_if_name );
	my $table_if =
	  ( $vip_if->{ type } eq 'virtual' ) ? $vip_if->{ parent } : $vip_if->{ name };

	foreach my $server ( @{ $$farm{ servers } } )
	{
		# remove conntrack
		&resetL4FarmBackendConntrackMark( $server );

		unless ( defined $table_if )
		{
			&zenlog(
				"Warning: Skipping removal of backend $server->{ tag } routing rule. Interface table not found.",
				"warning", "LSLB"
			);
			next;
		}

		my $ip_cmd = "$ip_bin rule del fwmark $server->{ tag } table table_$table_if";
		&logAndRun( $ip_cmd );
	}

	## Delete ip rule mark END ##
	&setIptConnmarkRestore( $farm_name );
	&setIptConnmarkSave( $farm_name );

	# Reload conntrack modules
	if ( $$farm{ vproto } =~ /sip|ftp/ )
	{
		&unloadL4Modules( $$farm{ vproto } );
	}

	# Stopping L4xNAT Scheduler Daemon
	if ( &getNumberOfFarmTypeRunning( 'l4xnat' ) == 0 )
	{
		system ( "pkill l4sd >/dev/null 2>&1" );
	}

	return $status;
}

=begin nd
Function: setL4NewFarmName

	Function that renames a farm

Parameters:
	newfarmname - New farm name
	farmname - Farm name

Returns:
	Array - Each line has the next format: ";server;ip;port;mark;weight;priority;status"

=cut

sub setL4NewFarmName    # ($farm_name,$new_farm_name)
{
	&zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING" );
	my ( $farm_name, $new_farm_name ) = @_;

	require Tie::File;

	my $farm_filename     = &getFarmFile( $farm_name );
	my $new_farm_filename = "$new_farm_name\_l4xnat.cfg";
	my $output            = 0;

	# previous farm info
	my $prev_farm = &getL4FarmStruct( $farm_name );

	my $farm       = &getL4FarmStruct( $farm_name );
	my $fg_enabled = ( &getFarmGuardianConf( $$farm{ name } ) )[3];
	my $fg_pid;

	if ( $$farm{ status } eq 'up' )
	{
		if ( $fg_enabled eq 'true' )
		{
			$fg_pid = &getFarmGuardianPid( $farm_name );
			kill 'STOP' => $fg_pid if ( $fg_pid > 0 );
		}
	}

	tie my @configfile, 'Tie::File', "$configdir\/$farm_filename";

	for ( @configfile )
	{
		s/^$farm_name\;/$new_farm_name\;/g;
	}
	untie @configfile;

	my $piddir = &getGlobalConfiguration( 'piddir' );
	rename ( "$configdir\/$farm_filename", "$configdir\/$new_farm_filename" )
	  or $output = -1;
	if ( -f "$piddir\/$farm_name\_l4xnat.pid" )
	{
		rename ( "$piddir\/$farm_name\_l4xnat.pid",
				 "$piddir\/$new_farm_name\_l4xnat.pid" )
		  or $output = -1;
	}

	# Rename fw marks for this farm
	require Zevenet::Netfilter;
	&renameMarks( $farm_name, $new_farm_name );

	$farm = &getL4FarmStruct( $new_farm_name );
	my $apply_farm = $farm;
	$apply_farm = $prev_farm if $$farm{ lbalg } eq 'prio';

	if ( $$farm{ status } eq 'up' )
	{
		my @rules;

		my $prio_server;
		$prio_server = &getL4ServerWithLowestPriority( $$farm{ name } )
		  if ( $$farm{ lbalg } eq 'prio' );

		# refresh backends probability values
		&getL4BackendsWeightProbability( $farm ) if ( $$farm{ lbalg } eq 'weight' );

		# get new rules
		foreach my $server ( @{ $$farm{ servers } } )
		{
			# skip cycle for servers not running
			#~ next if ( $$server{ status } !~ /up|maintenance/ );

			next if ( $$farm{ lbalg } eq 'prio' && $$server{ id } != $$prio_server{ id } );

			my $rule;
			my $rule_num;

			# refresh marks
			my $rule_ref = &genIptMark( $prev_farm, $server );
			foreach my $rule ( @{ $rule_ref } )
			{
				$rule_num =
				  ( $$farm{ lbalg } eq 'prio' )
				  ? &getIptRuleNumber( $rule, $$apply_farm{ name } )
				  : &getIptRuleNumber( $rule, $$apply_farm{ name }, $$server{ id } );
				my $rule_ref = &genIptMark( $farm, $server );
				foreach my $rule ( @{ $rule_ref } )
				{
					$rule = &applyIptRuleAction( $rule, 'replace', $rule_num );
					push ( @rules, $rule );
				}
			}

			if ( $$farm{ persist } ne 'none' )    # persistence
			{
				my $prule_ref = &genIptMarkPersist( $prev_farm, $server );
				foreach my $rule ( @{ $prule_ref } )
				{
					$rule_num =
					  ( $$farm{ lbalg } eq 'prio' )
					  ? &getIptRuleNumber( $rule, $$apply_farm{ name } )
					  : &getIptRuleNumber( $rule, $$apply_farm{ name }, $$server{ id } );
					my $rule_ref = &genIptMarkPersist( $farm, $server );
					foreach my $rule ( @{ $rule_ref } )
					{
						$rule = &applyIptRuleAction( $rule, 'replace', $rule_num );
						push ( @rules, $rule );
					}
				}
			}

			# redirect
			my $rule_ref = &genIptRedirect( $prev_farm, $server );
			foreach my $rule ( @{ $rule_ref } )
			{
				$rule_num =
				  ( $$farm{ lbalg } eq 'prio' )
				  ? &getIptRuleNumber( $rule, $$apply_farm{ name } )
				  : &getIptRuleNumber( $rule, $$apply_farm{ name }, $$server{ id } );
				$rule = &genIptRedirect( $farm, $server );
				$rule = &applyIptRuleAction( $rule, 'replace', $rule_num );
				push ( @rules, $rule );
			}

			if ( $$farm{ nattype } eq 'nat' )    # nat type = nat
			{
				my $rule_ref = &genIptMasquerade( $farm, $server );
				foreach my $rule ( @{ $rule_ref } )
				{
					my $rule_num =
					  ( $$farm{ lbalg } eq 'prio' )
					  ? &getIptRuleNumber( $rule, $$apply_farm{ name } )
					  : &getIptRuleNumber( $rule, $$apply_farm{ name }, $$server{ id } );

					$rule = &applyIptRuleAction( $rule, 'replace', $rule_num );
					push ( @rules, $rule );
				}
			}
		}

		if ( $fg_enabled eq 'true' )
		{
			if ( $0 !~ /farmguardian/ && $fg_pid > 0 )
			{
				kill 'CONT' => $fg_pid;
			}
		}

		# apply new rules
		$output = &applyIptRules( @rules );
	}

	return $output;
}

1;