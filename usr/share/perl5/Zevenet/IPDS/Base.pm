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

use Config::Tiny;
use Tie::File;

#~ use Zevenet::Core;
#~ use Zevenet::Debug;
use Zevenet::IPDS::Core;

#~ use Zevenet::IPDS::RBL;
#~ use Zevenet::IPDS::Blacklist;
#~ use Zevenet::IPDS::DoS;

=begin nd
Function: addIPDSIptablesChain

	This function create the iptables chains where the IPDS rules will be created

Parameters:
	none - .			
				
Returns:
	Integer - Error code: 0 on success or other value on failure
	
=cut

sub addIPDSIptablesChain
{
	my $iptables        = &getGlobalConfiguration( 'iptables' );
	my $whitelist_chain = &getIPDSChain( "whitelist" );
	my $blacklist_chain = &getIPDSChain( "blacklist" );
	my $rbl_chain       = &getIPDSChain( "rbl" );
	my $dos_chain       = &getIPDSChain( "dos" );
	my @chains          = ( $whitelist_chain, $blacklist_chain, $rbl_chain );
	my $error;

	# creating chains
	$error |= &iptSystem( "$iptables -N $whitelist_chain -t raw" );
	$error |= &iptSystem( "$iptables -N $blacklist_chain -t raw" );
	$error |= &iptSystem( "$iptables -N $rbl_chain -t raw" );

	$error |= &iptSystem( "$iptables -N $whitelist_chain -t mangle" );
	$error |= &iptSystem( "$iptables -N $dos_chain -t mangle" );

	# link this chains
	if (
		&iptSystem( "$iptables -C PREROUTING -t raw -j $whitelist_chain 2>/dev/null" ) )
	{
		$error |= &iptSystem( "$iptables -A PREROUTING -t raw -j $whitelist_chain" );
	}
	if (
		 &iptSystem( "$iptables -C $whitelist_chain -t raw -j $blacklist_chain 2>/dev/null"
		 )
	  )
	{
		$error |=
		  &iptSystem( "$iptables -A $whitelist_chain -t raw -j $blacklist_chain" );
	}
	if (
		&iptSystem( "$iptables -C $blacklist_chain -t raw -j $rbl_chain 2>/dev/null" ) )
	{
		$error |= &iptSystem( "$iptables -A $blacklist_chain -t raw -j $rbl_chain" );
	}
	if (
		 &iptSystem( "$iptables -C PREROUTING -t mangle -j $whitelist_chain 2>/dev/null"
		 )
	  )
	{
		$error |= &iptSystem( "$iptables -A PREROUTING -t mangle -j $whitelist_chain" );
	}
	if (
		 &iptSystem( "$iptables -C $whitelist_chain -t mangle -j $dos_chain 2>/dev/null"
		 )
	  )
	{
		$error |= &iptSystem( "$iptables -A $whitelist_chain -t mangle -j $dos_chain" );
	}

	if ( $error )
	{
		&zenlog( "Error creating iptables chains" );
	}

	return $error;
}

=begin nd
Function: delIPDSIptablesChain

	This function delete the iptables chains where the IPDS rules are created

Parameters:
	none - .			
				
Returns:
	Integer - Error code: 0 on success or other value on failure
	
=cut

sub delIPDSIptablesChain
{
	my $iptables        = &getGlobalConfiguration( 'iptables' );
	my $whitelist_chain = &getIPDSChain( "whitelist" );
	my $blacklist_chain = &getIPDSChain( "blacklist" );
	my $rbl_chain       = &getIPDSChain( "rbl" );
	my $dos_chain       = &getIPDSChain( "dos" );
	my $error;

	$error |= &iptSystem( "$iptables -F $whitelist_chain -t raw" );
	$error |= &iptSystem( "$iptables -F $blacklist_chain -t raw" );
	$error |= &iptSystem( "$iptables -F $rbl_chain -t raw" );
	$error |= &iptSystem( "$iptables -F $whitelist_chain -t mangle" );
	$error |= &iptSystem( "$iptables -F $dos_chain -t mangle" );

	$error |= &iptSystem( "$iptables -D PREROUTING -t raw -j $whitelist_chain" );
	$error |= &iptSystem( "$iptables -D PREROUTING -t mangle -j $whitelist_chain" );

	$error |= &iptSystem( "$iptables -X $rbl_chain -t raw" );
	$error |= &iptSystem( "$iptables -X $blacklist_chain -t raw" );
	$error |= &iptSystem( "$iptables -X $whitelist_chain -t raw" );
	$error |= &iptSystem( "$iptables -X $dos_chain -t mangle" );
	$error |= &iptSystem( "$iptables -X $whitelist_chain -t mangle" );

	if ( $error )
	{
		&zenlog( "Error deleting iptables chains" );
	}

	return $error;
}

actions:

=begin nd
Function: runIPDSStartModule

        Boot the IPDS module

Parameters:
				
Returns:
	none - .
	
=cut

sub runIPDSStartModule
{
	require Zevenet::IPDS::Blacklist::Actions;
	require Zevenet::IPDS::RBL::Actions;
	require Zevenet::IPDS::DoS::Actions;
	require Zevenet::Cluster;

	&addIPDSIptablesChain();

	# Add cluster exception not to block traffic from the other node of cluster
	&setZClusterIptablesException( "insert" );
	&runBLStartModule();
	&runRBLStartModule();
	&runDOSStartModule();
}

=begin nd
Function: runIPDSStopModule

        Stop the IPDS module

Parameters:
				
Returns:
	none - .

=cut

sub runIPDSStopModule
{
	require Zevenet::Cluster;
	require Zevenet::IPDS::Blacklist::Actions;
	require Zevenet::IPDS::RBL::Actions;
	require Zevenet::IPDS::DoS::Actions;

	&runRBLStopModule();
	&runBLStopModule();
	&runDOStopModule();

	# Remove cluster exception not to block traffic from the other node of cluster
	&setZClusterIptablesException( "delete" );

	&delIPDSIptablesChain();
}

actions_by_farm:

=begin nd
Function: runIPDSStartByFarm

	Link a farm with all its IPDS rules. If some rule is not been used by another farm, the rule is run.
	It is useful when a farm is started, stopped or modified

Parameters:
	Farmname - Farm name
				
Returns:
	none - .
	
=cut

sub runIPDSStartByFarm
{
	my $farmname = shift;

	# get rules and perl modules
	my $rules = &getIPDSfarmsRules( $farmname );
	require Zevenet::IPDS::Blacklist::Actions if ( @{ $rules->{ blacklists } } );
	require Zevenet::IPDS::DoS::Actions       if ( @{ $rules->{ dos } } );
	require Zevenet::IPDS::RBL::Actions       if ( @{ $rules->{ rbl } } );
	my $name;

	# start BL rules
	foreach my $rule ( @{ $rules->{ blacklists } } )
	{
		$name = $rule->{ name };
		&runBLStart( $name, $farmname );
	}

	# start dos rules
	foreach my $rule ( @{ $rules->{ dos } } )
	{
		$name = $rule->{ name };
		&runDOSStart( $name, $farmname );
	}

	# start rbl rules
	foreach my $rule ( @{ $rules->{ rbl } } )
	{
		$name = $rule->{ name };
		&runRBLStart( $name, $farmname );
	}
}

=begin nd
Function: runIPDSStopByFarm

	Unlink a farm with all its IPDS rules. If no more farm is using the rule, stop it.
	It is useful when a farm is stopped or remove from rule

Parameters:
	Farmname - Farm name
				
Returns:
	none - .
	
=cut

sub runIPDSStopByFarm
{
	my $farmname = shift;

	# get rules and perl modules
	my $rules = &getIPDSfarmsRules( $farmname );
	require Zevenet::IPDS::Blacklist::Actions if ( @{ $rules->{ blacklists } } );
	require Zevenet::IPDS::DoS::Actions       if ( @{ $rules->{ dos } } );
	require Zevenet::IPDS::RBL::Actions       if ( @{ $rules->{ rbl } } );
	my $name;

	# start BL rules
	foreach my $rule ( @{ $rules->{ blacklists } } )
	{
		$name = $rule->{ name };
		&runBLStop( $name, $farmname );
	}

	# start dos rules
	foreach my $rule ( @{ $rules->{ dos } } )
	{
		$name = $rule->{ name };
		&runDOSStop( $name, $farmname );
	}

	# start rbl rules
	foreach my $rule ( @{ $rules->{ rbl } } )
	{
		$name = $rule->{ name };
		&runRBLStop( $name, $farmname );
	}
}

=begin nd
Function: runIPDSRestartByFarm

	Reload all IPDS rules to a farm.
	It is useful when a farm is modified

Parameters:
	Farmname - Farm name
				
Returns:
	none - .
	
=cut

sub runIPDSRestartByFarm
{
	my $farmname = shift;

	# get rules and perl modules
	my $rules = &getIPDSfarmsRules( $farmname );
	require Zevenet::IPDS::Blacklist::Actions if ( @{ $rules->{ blacklists } } );
	require Zevenet::IPDS::DoS::Actions       if ( @{ $rules->{ dos } } );
	require Zevenet::IPDS::RBL::Actions       if ( @{ $rules->{ rbl } } );
	my $name;

	# start BL rules
	foreach my $rule ( @{ $rules->{ blacklists } } )
	{
		$name = $rule->{ name };
		&runBLStop( $name, $farmname );
		&runBLStart( $name, $farmname );
	}

	# start dos rules
	foreach my $rule ( @{ $rules->{ dos } } )
	{
		$name = $rule->{ name };
		&runDOSStop( $name, $farmname );
		&runDOSStart( $name, $farmname );
	}

	# start rbl rules
	foreach my $rule ( @{ $rules->{ rbl } } )
	{
		$name = $rule->{ name };
		&runRBLStop( $name, $farmname );
		&runRBLStart( $name, $farmname );
	}
}

1;
