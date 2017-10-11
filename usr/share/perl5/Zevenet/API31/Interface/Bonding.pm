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

my @bond_modes_short = (
						 'balance-rr',  'active-backup',
						 'balance-xor', 'broadcast',
						 '802.3ad',     'balance-tlb',
						 'balance-alb',
);

sub new_bond    # ( $json_obj )
{
	my $json_obj = shift;

	require Zevenet::Net::Bonding;
	require Zevenet::Net::Validate;
	require Zevenet::System;

	my $desc = "Add a bond interface";

	# validate BOND NAME
	my $bond_re = &getValidFormat( 'bond_interface' );

	# size < 16: size = bonding_name.vlan_name:virtual_name
	if ( length $json_obj->{ name } > 11 )
	{
		my $msg = "Bonding interface name has a maximum length of 11 characters";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	unless (    $json_obj->{ name } =~ /^$bond_re$/
			 && &ifexist( $json_obj->{ name } ) eq 'false' )
	{
		my $msg = "Interface name is not valid";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# validate BOND MODE
	unless (    $json_obj->{ mode }
			 && &getValidFormat( 'bond_mode_short', $json_obj->{ mode } ) )
	{
		my $msg = "Bond mode is not valid";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	$json_obj->{ mode } =
	  &indexOfElementInArray( $json_obj->{ mode }, \@bond_modes_short );

	# validate SLAVES
	my $missing_slave;
	for my $slave ( @{ $json_obj->{ slaves } } )
	{
		unless ( grep { $slave eq $_ } &getBondAvailableSlaves() )
		{
			$missing_slave = $slave;
			last;
		}
	}

	if ( $missing_slave || !@{ $json_obj->{ slaves } } )
	{
		my $msg = "Error loading the slave interfaces list";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	eval { die if &applyBondChange( $json_obj, 'writeconf' ); };

	if ( $@ )
	{
		my $msg = "The $json_obj->{ name } bonding network interface can't be created";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $if_ref      = getSystemInterface( $json_obj->{ name } );
	my @bond_slaves = @{ $json_obj->{ slaves } };
	my @output_slaves;

	push ( @output_slaves, { name => $_ } ) for @bond_slaves;

	my $body = {
				 description => $desc,
				 params      => {
							 name   => $json_obj->{ name },
							 mode   => $bond_modes_short[$json_obj->{ mode }],
							 slaves => \@output_slaves,
							 status => $if_ref->{ status },
							 mac    => $if_ref->{ mac },
				 },
	};

	return &httpResponse( { code => 201, body => $body } );
}

# POST bond slave
# slave: nic
sub new_bond_slave    # ( $json_obj, $bond )
{
	my $json_obj = shift;
	my $bond     = shift;

	require Zevenet::Net::Bonding;

	my $desc = "Add a slave to a bond interface";

	# validate BOND NAME
	my $bonds = &getBondConfig();

	unless ( $bonds->{ $bond } )
	{
		my $msg = "Bond interface name not found";
		return &httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# validate SLAVE
	eval {
		$json_obj->{ name } or die;
		&getValidFormat( 'nic_interface', $json_obj->{ name } ) or die;
		grep ( { $json_obj->{ name } eq $_ } &getBondAvailableSlaves() ) or die;
		die
		  if grep ( { $json_obj->{ name } eq $_ } @{ $bonds->{ $bond }->{ slaves } } );
	};
	if ( $@ )
	{
		my $msg = "Could not add the slave interface to this bonding";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	push @{ $bonds->{ $bond }->{ slaves } }, $json_obj->{ name };

	eval { die if &applyBondChange( $bonds->{ $bond }, 'writeconf' ); };
	if ( $@ )
	{
		my $msg = "The $json_obj->{ name } bonding network interface can't be created";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $if_ref      = getSystemInterface( $bond );
	my @bond_slaves = @{ $bonds->{ $bond }->{ slaves } };
	my @output_slaves;

	push ( @output_slaves, { name => $_ } ) for @bond_slaves;

	my $body = {
				 description => $desc,
				 params      => {
							 name   => $bond,
							 mode   => $bond_modes_short[$bonds->{ $bond }->{ mode }],
							 slaves => \@output_slaves,
							 status => $if_ref->{ status },
							 mac    => $if_ref->{ mac },
				 },
	};

	return &httpResponse( { code => 201, body => $body } );
}

sub delete_interface_bond    # ( $bond )
{
	my $bond = shift;

	require Zevenet::Net::Core;
	require Zevenet::Net::Route;
	require Zevenet::Net::Interface;

	my $desc   = "Delete bonding network configuration";
	my $ip_v   = 4;
	my $if_ref = &getInterfaceConfig( $bond, $ip_v );

	if ( !$if_ref )
	{
		my $msg = "There is no configuration for the network interface.";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# not delete the interface if it has some vlan configured
	my @child = &getInterfaceChild( $bond );
	if ( @child )
	{
		my $child_string = join ( ', ', @child );
		my $msg =
		  "Is is not possible to delete $bond because there are virtual interfaces using it: $child_string.";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	eval {
		die if &delRoutes( "local", $if_ref );
		die if &downIf( $if_ref, 'writeconf' );    # FIXME: To be removed
		die if &delIf( $if_ref );
	};

	if ( $@ )
	{
		my $msg =
		  "The configuration for the bonding interface $bond couldn't be deleted.";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $message =
	  "The configuration for the bonding interface $bond has been deleted.";
	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $message,
	};

	return &httpResponse( { code => 200, body => $body } );
}

sub delete_bond    # ( $bond )
{
	my $bond = shift;

	require Zevenet::Net::Core;
	require Zevenet::Net::Bonding;

	my $desc  = "Remove bonding interface";
	my $bonds = &getBondConfig();

	# validate BOND
	unless ( $bonds->{ $bond } )
	{
		my $msg = "Bonding interface name not found";
		return &httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	#not destroy it if it has a VLAN configured
	my @vlans = grep ( /^$bond\./, &getLinkNameList() );
	if ( @vlans )
	{
		my $child_string = join ( ', ', @vlans );
		my $msg =
		  "Is is not possible to delete $bond if it has configured VLAN: $child_string.";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	#not destroy it if it has a virtual interface configured
	my @child = &getInterfaceChild( $bond );
	if ( @child )
	{
		my $child_string = join ( ', ', @child );
		my $msg =
		  "Is is not possible to delete $bond because there are virtual interfaces using it: $child_string.";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $bond_in_use = 0;
	$bond_in_use = 1 if &getInterfaceConfig( $bond, 4 );
	$bond_in_use = 1 if &getInterfaceConfig( $bond, 6 );
	$bond_in_use = 1 if grep ( /^$bond(:|\.)/, &getInterfaceList() );

	if ( $bond_in_use )
	{
		my $msg = "Bonding interface is being used";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	#~ eval {
	if ( ${ &getSystemInterface( $bond ) }{ status } eq 'up' )
	{
		die if &downIf( $bonds->{ $bond }, 'writeconf' );
	}

	die if &setBondMaster( $bond, 'del', 'writeconf' );

	#~ };

	if ( $@ )
	{
		my $msg = "The bonding interface $bond could not be deleted";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $message = "The bonding interface $bond has been deleted.";
	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $message,
	};

	return &httpResponse( { code => 200, body => $body } );
}

sub delete_bond_slave    # ( $bond, $slave )
{
	my $bond  = shift;
	my $slave = shift;

	require Zevenet::Net::Bonding;

	my $desc  = "Remove bonding slave interface";
	my $bonds = &getBondConfig();

	# validate BOND
	unless ( $bonds->{ $bond } )
	{
		my $msg = "Bonding interface not found";
		return &httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# validate SLAVE
	unless ( grep ( { $slave eq $_ } @{ $bonds->{ $bond }->{ slaves } } ) )
	{
		my $msg = "Bonding slave interface not found";
		return &httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	eval {
		@{ $bonds->{ $bond }{ slaves } } =
		  grep ( { $slave ne $_ } @{ $bonds->{ $bond }{ slaves } } );
		die if &applyBondChange( $bonds->{ $bond }, 'writeconf' );
	};
	if ( $@ )
	{
		my $msg = "The bonding slave interface $slave could not be removed";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $message = "The bonding slave interface $slave has been removed.";
	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $message,
	};

	return &httpResponse( { code => 200, body => $body } );
}

sub get_bond_list    # ()
{
	require Zevenet::Net::Bonding;
	require Zevenet::Net::Interface;

	my @output_list;

	my $desc      = "List bonding interfaces";
	my $bond_conf = &getBondConfig();

	# get cluster interface
	my $cluster_if;
	if ( eval { require Zevenet::Cluster; } )
	{
		my $zcl_conf = &getZClusterConfig();
		$cluster_if = $zcl_conf->{ _ }->{ interface };
	}

	for my $if_ref ( &getInterfaceTypeList( 'bond' ) )
	{
		$if_ref->{ status } = &getInterfaceSystemStatus( $if_ref );

		# Any key must cotain a value or "" but can't be null
		if ( !defined $if_ref->{ name } )    { $if_ref->{ name }    = ""; }
		if ( !defined $if_ref->{ addr } )    { $if_ref->{ addr }    = ""; }
		if ( !defined $if_ref->{ mask } )    { $if_ref->{ mask }    = ""; }
		if ( !defined $if_ref->{ gateway } ) { $if_ref->{ gateway } = ""; }
		if ( !defined $if_ref->{ status } )  { $if_ref->{ status }  = ""; }
		if ( !defined $if_ref->{ mac } )     { $if_ref->{ mac }     = ""; }

		my @bond_slaves = @{ $bond_conf->{ $if_ref->{ name } }->{ slaves } };
		my @output_slaves;
		push ( @output_slaves, { name => $_ } ) for @bond_slaves;

		my $if_conf = {
			name    => $if_ref->{ name },
			ip      => $if_ref->{ addr },
			netmask => $if_ref->{ mask },
			gateway => $if_ref->{ gateway },
			status  => $if_ref->{ status },
			mac     => $if_ref->{ mac },

			slaves => \@output_slaves,
			mode   => $bond_modes_short[$bond_conf->{ $if_ref->{ name } }->{ mode }],

			#~ ipv     => $if_ref->{ ip_v },
		};

		$if_conf->{ is_cluster } = 'true'
		  if $cluster_if && $cluster_if eq $if_ref->{ name };

		push @output_list, $if_conf;
	}

	my $body = {
				 description => $desc,
				 interfaces  => \@output_list,
	};

	return &httpResponse( { code => 200, body => $body } );
}

sub get_bond    # ()
{
	my $bond = shift;

	require Zevenet::Net::Bonding;
	require Zevenet::Net::Interface;

	my $interface;    # output
	my $desc      = "Show bonding interface";
	my $bond_conf = &getBondConfig();

	for my $if_ref ( &getInterfaceTypeList( 'bond' ) )
	{
		next unless $if_ref->{ name } eq $bond;

		$if_ref->{ status } = &getInterfaceSystemStatus( $if_ref );

		# Any key must cotain a value or "" but can't be null
		if ( !defined $if_ref->{ name } )    { $if_ref->{ name }    = ""; }
		if ( !defined $if_ref->{ addr } )    { $if_ref->{ addr }    = ""; }
		if ( !defined $if_ref->{ mask } )    { $if_ref->{ mask }    = ""; }
		if ( !defined $if_ref->{ gateway } ) { $if_ref->{ gateway } = ""; }
		if ( !defined $if_ref->{ status } )  { $if_ref->{ status }  = ""; }
		if ( !defined $if_ref->{ mac } )     { $if_ref->{ mac }     = ""; }

		my @bond_slaves = @{ $bond_conf->{ $if_ref->{ name } }->{ slaves } };
		my @output_slaves;
		push ( @output_slaves, { name => $_ } ) for @bond_slaves;

		$interface = {
					 name    => $if_ref->{ name },
					 ip      => $if_ref->{ addr },
					 netmask => $if_ref->{ mask },
					 gateway => $if_ref->{ gateway },
					 status  => $if_ref->{ status },
					 mac     => $if_ref->{ mac },
					 slaves  => \@output_slaves,
					 mode => $bond_modes_short[$bond_conf->{ $if_ref->{ name } }->{ mode }],
		};
	}

	unless ( $interface )
	{
		my $msg = "Bonding interface not found.";
		return &httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my $body = {
				 description => $desc,
				 interface   => $interface,
	};

	return &httpResponse( { code => 200, body => $body } );
}

sub actions_interface_bond    # ( $json_obj, $bond )
{
	my $json_obj = shift;
	my $bond     = shift;

	require Zevenet::Net::Core;
	require Zevenet::Net::Interface;

	my $desc = "Action on bond interface";
	my $ip_v = 4;

	unless ( grep { $bond eq $_->{ name } } &getInterfaceTypeList( 'bond' ) )
	{
		my $msg = "Bond interface not found";
		return &httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	if ( grep { $_ ne 'action' } keys %$json_obj )
	{
		my $msg = "Only the parameter 'action' is accepted";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# validate action parameter
	if ( $json_obj->{ action } eq 'destroy' )
	{
		return &delete_bond( $bond );    # doesn't return
	}
	elsif ( $json_obj->{ action } eq "up" )
	{
		require Zevenet::Net::Route;

		my $if_ref = &getInterfaceConfig( $bond, $ip_v );

		# Delete routes in case that it is not a vini
		&delRoutes( "local", $if_ref ) if $if_ref;

		&addIp( $if_ref ) if $if_ref;

		my $state = &upIf( { name => $bond }, 'writeconf' );

		if ( !$state )
		{
			require Zevenet::Net::Util;

			&applyRoutes( "local", $if_ref ) if $if_ref;

			# put all dependant interfaces up
			&setIfacesUp( $bond, "vlan" );
			&setIfacesUp( $bond, "vini" ) if $if_ref;
		}
		else
		{
			my $msg = "The interface $bond could not be set UP";
			return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}
	elsif ( $json_obj->{ action } eq "down" )
	{
		my $state = &downIf( { name => $bond }, 'writeconf' );

		if ( $state )
		{
			my $msg = "The interface $bond could not be set UP";
			return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}
	else
	{
		my $msg = "Action accepted values are: up, down or destroy";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $body = {
				 description => $desc,
				 params      => { action => $json_obj->{ action } },
	};

	return &httpResponse( { code => 200, body => $body } );
}

sub modify_interface_bond    # ( $json_obj, $bond )
{
	my $json_obj = shift;
	my $bond     = shift;

	require Zevenet::Net::Core;
	require Zevenet::Net::Route;
	require Zevenet::Net::Interface;

	my $desc = "Modify bond address";
	my $ip_v = 4;

	# validate BOND NAME
	my @system_interfaces = &getInterfaceList();
	my $type              = &getInterfaceType( $bond );

	unless ( grep ( { $bond eq $_ } @system_interfaces ) && $type eq 'bond' )
	{
		my $msg = "Nic interface not found.";
		return &httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	if ( grep { !/^(?:ip|netmask|gateway)$/ } keys %$json_obj )
	{
		my $msg = "Parameter not recognized";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	unless (    exists $json_obj->{ ip }
			 || exists $json_obj->{ netmask }
			 || exists $json_obj->{ gateway } )
	{
		my $msg = "No parameter received to be configured";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# not modify gateway or netmask if exists a virtual interface using this interface
	if ( exists $json_obj->{ netmask } || exists $json_obj->{ gateway } )
	{
		my @child = &getInterfaceChild( $bond );
		if ( @child )
		{
			my $child_string = join ( ', ', @child );
			my $msg =
			  "Is is not possible to modify $bond because there are virtual interfaces using it: $child_string.";
			return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}

	# Check address errors
	if ( exists $json_obj->{ ip } )
	{
		unless ( defined ( $json_obj->{ ip } )
				 && &getValidFormat( 'IPv4_addr', $json_obj->{ ip } )
				 || $json_obj->{ ip } eq '' )
		{
			my $msg = "IP Address is not valid.";
			return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		if ( $json_obj->{ ip } eq '' )
		{
			$json_obj->{ netmask } = '';
			$json_obj->{ gateway } = '';
		}
	}

	# Check netmask errors
	if ( exists $json_obj->{ netmask } )
	{
		unless ( defined ( $json_obj->{ netmask } )
				 && &getValidFormat( 'IPv4_mask', $json_obj->{ netmask } ) )
		{
			my $msg =
			  "Netmask Address $json_obj->{netmask} structure is not ok. Must be IPv4 structure or numeric.";
			return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}

	# Check gateway errors
	if ( exists $json_obj->{ gateway } )
	{
		unless ( defined ( $json_obj->{ gateway } )
				 && &getValidFormat( 'IPv4_addr', $json_obj->{ gateway } )
				 || $json_obj->{ gateway } eq '' )
		{
			my $msg = "Gateway Address $json_obj->{gateway} structure is not ok.";
			return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}

	# Delete old interface configuration
	my $if_ref = &getInterfaceConfig( $bond, $ip_v );

	# check if network is correct
	my $new_if = {
				   addr    => $json_obj->{ ip }      // $if_ref->{ addr },
				   mask    => $json_obj->{ netmask } // $if_ref->{ mask },
				   gateway => $json_obj->{ gateway } // $if_ref->{ gateway },
	};

	if ( $new_if->{ gateway } )
	{
		require Zevenet::Net::Validate;
		unless (
			 &getNetValidate( $new_if->{ addr }, $new_if->{ mask }, $new_if->{ gateway } ) )
		{
			my $msg = "The gateway is not valid for the network.";
			return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}

	# hash reference may exist without key-value pairs
	if ( $if_ref && keys %$if_ref )
	{
		# Delete old IP and Netmask from system to replace it
		&delIp( $if_ref->{ name }, $if_ref->{ addr }, $if_ref->{ mask } );

		# Remove routes if the interface has its own route table: nic and vlan
		&delRoutes( "local", $if_ref );

		$if_ref = undef;
	}

	# Setup new interface configuration structure
	$if_ref = &getInterfaceConfig( $bond ) // &getSystemInterface( $bond );
	$if_ref->{ addr }    = $json_obj->{ ip }      if exists $json_obj->{ ip };
	$if_ref->{ mask }    = $json_obj->{ netmask } if exists $json_obj->{ netmask };
	$if_ref->{ gateway } = $json_obj->{ gateway } if exists $json_obj->{ gateway };
	$if_ref->{ ip_v }    = 4;

	unless ( $if_ref->{ addr } && $if_ref->{ mask } )
	{
		my $msg = "Cannot configure the interface without address or without netmask.";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	eval {

		# Add new IP, netmask and gateway
		die if &addIp( $if_ref );

		# Writing new parameters in configuration file
		die if &writeRoutes( $if_ref->{ name } );

		# Put the interface up
		{
			my $previous_status = $if_ref->{ status };
			my $state = &upIf( $if_ref, 'writeconf' );

			if ( $state == 0 )
			{
				$if_ref->{ status } = "up";
				&applyRoutes( "local", $if_ref );
			}
			else
			{
				$if_ref->{ status } = $previous_status;
			}
		}

		&setInterfaceConfig( $if_ref ) or die;
	};

	if ( $@ )
	{
		my $msg = "Errors found trying to modify interface $bond";
		return &httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $body = {
				 description => $desc,
				 params      => $json_obj,
	};

	return &httpResponse( { code => 200, body => $body } );
}

1;
