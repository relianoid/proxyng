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
	my @chains          = ( $whitelist_chain, $blacklist_chain, $rbl_chain );
	my $error;

	# create chains
	for my $chain ( @chains )
	{
		# if the chain does not exists
		unless ( &iptSystem( "$iptables -L $chain -t raw" ) == 0  )
		{
			$error = &iptSystem( "$iptables -N $chain -t raw" ); # create chain
			last if $error;
		}
	}

	# link this chains
	$error = &iptSystem( "$iptables -A PREROUTING -t raw -j $whitelist_chain" )
	  if ( !$error );
	$error =
	  &iptSystem( "$iptables -A $whitelist_chain -t raw -j $blacklist_chain" )
	  if ( !$error );
	$error = &iptSystem( "$iptables -A $blacklist_chain -t raw -j $rbl_chain" )
	  if ( !$error );

	# last sentence in each chain is return to above chain
	$error = &iptSystem( "$iptables -A $whitelist_chain -t raw -j RETURN" )
	  if ( !$error );
	$error = &iptSystem( "$iptables -A $blacklist_chain -t raw -j RETURN" )
	  if ( !$error );
	$error = &iptSystem( "$iptables -A $rbl_chain -t raw -j RETURN" )
	  if ( !$error );


	if ($error)
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
	my $error;

	# clean and remove all IPDS chains
	for my $chain ( $rbl_chain, $blacklist_chain, $whitelist_chain )
	{
		# if the chain does not exists
		if ( &iptSystem( "$iptables -L $chain -t raw" ) == 0 )
		{
			$error = &iptSystem( "$iptables -F $chain -t raw" ); # flush it
			$error = &iptSystem( "$iptables -X $chain -t raw" ) if (!$error); # remove it
			last if $error;
		}
	}

	$error = &iptSystem( "$iptables -D PREROUTING -t raw -j $whitelist_chain" ) if (!$error);

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
	require Zevenet::IPDS::Blacklist::Actions if ( @{ $rules->{ blacklist } } );
	require Zevenet::IPDS::DoS::Actions       if ( @{ $rules->{ dos } } );
	require Zevenet::IPDS::RBL::Actions       if ( @{ $rules->{ rbl } } );

	# start BL rules
	foreach my $rule ( @{ $rules->{ blacklist } } )
	{
		&runRBLStart( $rule, $farmname );
	}

	# start dos rules
	foreach my $rule ( @{ $rules->{ dos } } )
	{
		&runDOSStart( $rule, $farmname );
	}

	# start rbl rules
	foreach my $rule ( @{ $rules->{ rbl } } )
	{
		&runBLStart( $rule, $farmname );
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
	require Zevenet::IPDS::Blacklist::Actions if ( @{ $rules->{ blacklist } } );
	require Zevenet::IPDS::DoS::Actions       if ( @{ $rules->{ dos } } );
	require Zevenet::IPDS::RBL::Actions       if ( @{ $rules->{ rbl } } );

	# start BL rules
	foreach my $rule ( @{ $rules->{ blacklist } } )
	{
		&runRBLStop( $rule, $farmname );
	}

	# start dos rules
	foreach my $rule ( @{ $rules->{ dos } } )
	{
		&runDOSStop( $rule, $farmname );
	}

	# start rbl rules
	foreach my $rule ( @{ $rules->{ rbl } } )
	{
		&runBLStop( $rule, $farmname );
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
	require Zevenet::IPDS::Blacklist::Actions if ( @{ $rules->{ blacklist } } );
	require Zevenet::IPDS::DoS::Actions       if ( @{ $rules->{ dos } } );
	require Zevenet::IPDS::RBL::Actions       if ( @{ $rules->{ rbl } } );

	# start BL rules
	foreach my $rule ( @{ $rules->{ blacklist } } )
	{
		&runRBLStop( $rule, $farmname );
		&runRBLStart( $rule, $farmname );
	}

	# start dos rules
	foreach my $rule ( @{ $rules->{ dos } } )
	{
		&runDOSStop( $rule, $farmname );
		&runDOSStart( $rule, $farmname );
	}

	# start rbl rules
	foreach my $rule ( @{ $rules->{ rbl } } )
	{
		&runBLStop( $rule, $farmname );
		&runBLStart( $rule, $farmname );
	}
}

1;
