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
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

# global variable for bonding modes names
my @bond_modes = (
				'Round-robin policy',
				'Active-backup policy',
				'XOR policy',
				'Broadcast policy',
				'IEEE 802.3ad LACP',
				'Adaptive transmit load balancing',
				'Adaptive load balancing',
);

my @bond_modes_short = (
				'balance-rr',
				'active-backup',
				'balance-xor',
				'broadcast',
				'802.3ad',
				'balance-tlb',
				'balance-alb',
);

=begin nd
Function: getBondList

	Get a reference to a list of all bonding hashes.

	Bonding hash:
	name   - Interface name.
	mode   - Bonding mode
	slaves - NIC interfaces belonging to the bonding interface.

Parameters:
	none - .

Returns:
	scalar - reference to an array of bonding interfaces.

See Also:
	<applyBondChange>, <getAllBondsSlaves>
=cut
sub getBondList
{
	my $bonding_masters_filename = &getGlobalConfiguration('bonding_masters_filename');

	if ( !-f $bonding_masters_filename )
	{
		&zenlog( "Bonding module seems missing" );
		return undef;
	}

	open ( my $bond_file, '<', $bonding_masters_filename );

	if ( !$bond_file )
	{
		&zenlog( "Could not open file $bonding_masters_filename: $!" );
		return undef;
	}

	my @bond_names = split ( ' ', <$bond_file> );
	close $bond_file;
	chomp ( @bond_names );

	my @bonds = ();

	for my $bond_name ( @bond_names )
	{
		my $mode = &getBondMode( $bond_name );
		next if ( ref $mode ne 'ARRAY' );
		$mode = @{ $mode }[1];    # get mode code

		my $slaves = &getBondSlaves( $bond_name );
		next if ( ref $slaves ne 'ARRAY' );

		my %bond = (
					 name   => $bond_name,
					 mode   => $mode,
					 slaves => $slaves,
		);

		push ( @bonds, \%bond );
	}

	return \@bonds;
}

=begin nd
Function: getBondMode

	Get a reference to a list with two ways to express the bonding mode, name and number.

Parameters:
	bond_master - Bonding interface name.

Returns:
	scalar - list reference or undef if not found or an error happened.
	The list has two elements:
	- 0 - Bonding mode short name.
	- 1 - Bonding mode number.

Bugs:
	Returning a reference to a two elements array is making it too complicated.
	There is not need to return a reference. Returning a list is simpler.

See Also:
	
=cut
sub getBondMode
{
	my $bond_master = shift;

	my $sys_net_dir = &getGlobalConfiguration('sys_net_dir');
	my $bond_path = "$sys_net_dir/$bond_master";

	if ( !-d $bond_path )
	{
		&zenlog( "Could not find bonding $bond_path" );
		return undef;
	}

	my $bonding_mode_filename = &getGlobalConfiguration('bonding_mode_filename');

	open ( my $bond_mode_file, '<', "$bond_path/$bonding_mode_filename" );

	if ( !$bond_mode_file )
	{
		&zenlog( "Could not open file $bond_path/$bonding_mode_filename: $!" );
		return undef;
	}

	# input example: balance-rr 0
	# input example: balance-xor 2
	my @mode = split ( ' ', <$bond_mode_file> );
	close $bond_mode_file;
	chomp ( @mode );

# $mode[0] == balance-rr|active-backup|balance-xor|broadcast|802.3ad|balance-tlb|balance-alb
# $mode[1] == 0			| 1 			| 2 		| 3 	| 4 	| 5 		| 6
	return \@mode;
}

=begin nd
Function: getBondSlaves

	Get a reference to a list of NICs part of the bonding interface

Parameters:
	bond_master - Name of bonding interface.

Returns:
	scalar - reference to a list of slaves in bonding interface.

See Also:
	
=cut
sub getBondSlaves
{
	my $bond_master = shift;

	my $sys_net_dir = &getGlobalConfiguration('sys_net_dir');
	my $bond_path = "$sys_net_dir/$bond_master";

	if ( !-d $bond_path )
	{
		&zenlog( "Could not find bonding $bond_path" );
		return undef;
	}

	my $bonding_slaves_filename = &getGlobalConfiguration('bonding_slaves_filename');

	open ( my $bond_slaves_file, '<', "$bond_path/$bonding_slaves_filename" );

	if ( !$bond_slaves_file )
	{
		&zenlog( "Could not open file $bond_path/$bonding_slaves_filename: $!" );
		return undef;
	}

	# input example: eth1 eth2
	my @slaves = split ( ' ', <$bond_slaves_file> );
	close $bond_slaves_file;
	chomp ( @slaves );

	# $slaves[0] == eth1
	# $slaves[1] == eth2
	return \@slaves;
}

=begin nd
Function: applyBondChange

	Configure the bonding interface, and optionally store the configuration.

Parameters:
	bond - reference to bonding interface.
	writeconf - Boolean, true to store the configuration, or false to only apply it.

Returns:
	scalar - 0 on success, -1 on failure.

Bugs:
	Use better return values.

See Also:
	
=cut
sub applyBondChange
{
	my $bond      = shift;
	my $writeconf = shift;    # bool: write config to disk

	my $return_code = -1;

	# validate $bond->{name}
	return $return_code if ref $bond ne 'HASH';
	return $return_code if !$bond->{ name };

	# validate $bond->{mode}
	return $return_code if $bond->{ mode } < 0 || $bond->{ mode } > 6;

	# validate $bond->{slaves}
	return $return_code if ref $bond->{ slaves } ne 'ARRAY';
	return $return_code if scalar @{ $bond->{ slaves } } == 0;

	my $bond_list = &getBondList();
	my $sys_bond;

	# look for bonding master if already configured
	for my $bond_ref ( @{ $bond_list } )
	{
		$sys_bond = $bond_ref if ( $bond->{ name } eq $bond_ref->{ name } );
	}

	# verify every slave interface
	my @interface_list = &getInterfaceList();
	for my $slave ( @{ $bond->{ slaves } } )
	{
		if ( $slave =~ /(:|\.)/ )    # do not allow vlans or vinis
		{
			&zenlog( "$slave is not a NIC" );
			return $return_code;
		}
		elsif (
				grep ( /^$slave$/, @interface_list ) !=
				1 )                  # only allow interfaces in the system
		{
			&zenlog( "Could not find $slave" );
			return $return_code;
		}
	}

	# add bond master and set mode only if it is a new one
	if ( !$sys_bond )
	{
		&zenlog( "Bonding not found, adding new master" );
		&setBondMaster( $bond->{ name }, 'add' );
		&setBondMode( $bond );
	}

	# auxiliar hash to remove unwanted slaves
	my %sys_bond_slaves;
	%sys_bond_slaves = map { $_ => $_ } @{ $sys_bond->{ slaves } } if $sys_bond;

	for my $slave ( @{ $bond->{ slaves } } )
	{
		if ( !$sys_bond )
		{
			&zenlog( "adding $slave" );
			&setBondSlave( $bond->{ name }, $slave, 'add' );
		}
		else
		{
			# add slave if not already configured
			if ( grep ( /^$slave$/, @{ $sys_bond->{ slaves } } ) == 0 )
			{
				&zenlog( "adding $slave" );
				&setBondSlave( $bond->{ name }, $slave, 'add' );
			}

			# discard all checked slaves
			$sys_bond_slaves{ $slave } = undef;
		}
	}

	for my $slave ( keys %sys_bond_slaves )
	{
		if ( $sys_bond_slaves{ $slave } )
		{
			&zenlog( "removing $slave" );
			&setBondSlave( $bond->{ name }, $slave, 'del' );
		}
	}

	# write bonding configuration
	if ( $writeconf )
	{
		my $bond_conf = &getBondConfig();
		$bond_conf->{ $bond->{ name } } = $bond;
		&setBondConfig( $bond_conf );
	}

	$return_code = 0;

	return $return_code;
}

=begin nd
Function: setBondMaster

	Creates or removes master bonding interface.

Parameters:
	bond_name - Name of bonding interface.
	operation - 'add' to or 'del'.
	writeconf - Boolean, true to store configuration changes.

Returns:
	scalar - 0 on success, or 1 on failure.

See Also:
	
=cut
sub setBondMaster
{
	my $bond_name = shift;
	my $operation = shift;    # add || del
	my $writeconf = shift;    # bool: write config to disk

	my $operator;
	my $return_code = 1;

	if ( $operation eq 'add' )
	{
		$operator = '+';
	}
	elsif ( $operation eq 'del' )
	{
		$operator = '-';
	}
	else
	{
		&zenlog( "Wrong bonding master operation" );
		return $return_code;
	}

	my $bonding_masters_filename = &getGlobalConfiguration('bonding_masters_filename');

	if ( !-f $bonding_masters_filename )
	{
		&zenlog( "Bonding module seems missing" );
		return $return_code;
	}

	open ( my $bond_file, '>', $bonding_masters_filename );

	if ( !$bond_file )
	{
		&zenlog( "Could not open file $bonding_masters_filename: $!" );
		return $return_code;
	}

	print $bond_file "$operator$bond_name";
	close $bond_file;

	# miimon
	my $sys_net_dir = &getGlobalConfiguration('sys_net_dir');
	my $bonding_miimon_filename = &getGlobalConfiguration('bonding_miimon_filename');
	my $miimon_filepath = "$sys_net_dir/$bond_name/$bonding_miimon_filename";

	open ( my $miimon_file, '>', $miimon_filepath );

	if ( !$miimon_file )
	{
		&zenlog( "Could not open file $miimon_filepath: $!" );
	}
	else
	{
		print $miimon_file "100";
		close $miimon_file;
	}    # end miimon

	if ( $writeconf )
	{
		my $bond_conf = &getBondConfig();
		delete $bond_conf->{ $bond_name };
		&setBondConfig( $bond_conf );

		my $configdir = &getGlobalConfiguration('configdir');

		unlink "$configdir/if_${bond_name}_conf";
		require Zevenet::RRD;
		&delGraph ( $bond_name, "iface" );
	}

	$return_code = 0;

	return $return_code;
}

=begin nd
Function: setBondMode

	Sets a bonding mode. Requires the bonding interface to have no slaves while changing the mode.

Parameters:
	bond - Reference to a bond interface.

Returns:
	scalar - 0 on success, or 1 on failure.

See Also:
	
=cut
sub setBondMode
{
	my $bond = shift;

	my $sys_net_dir = &getGlobalConfiguration('sys_net_dir');
	my $bond_path   = "$sys_net_dir/$bond->{name}";
	my $return_code = 1;

	if ( !-d $bond_path )
	{
		&zenlog( "Could not find bonding $bond_path" );
		return $return_code;
	}

	my $bonding_mode_filename = &getGlobalConfiguration('bonding_mode_filename');

	open ( my $bond_mode_file, '>', "$bond_path/$bonding_mode_filename" );

	if ( !$bond_mode_file )
	{
		&zenlog( "Could not open file $bond_path/$bonding_mode_filename: $!" );
		return $return_code;
	}

	print $bond_mode_file "$bond->{mode}";
	close $bond_mode_file;

	$return_code = 0;

	return $return_code;
}

=begin nd
Function: setBondSlave

	Adds or removes a slave interface to/from a bonding interface.

Parameters:
	bond_name - Name of bonding interface.
	bond_slave - Name of NIC interface.
	operation - 'add' or 'del'.

Returns:
	scalar - 0 on success, or 1 on failure.

See Also:
	
=cut
sub setBondSlave
{
	my $bond_name  = shift;
	my $bond_slave = shift;
	my $operation  = shift;    # add || del

	my $sys_net_dir = &getGlobalConfiguration('sys_net_dir');
	my $bond_path = "$sys_net_dir/$bond_name";
	my $operator;
	my $return_code = 1;

	if ( $operation eq 'add' )
	{
		$operator = '+';
	}
	elsif ( $operation eq 'del' )
	{
		$operator = '-';
	}
	else
	{
		&zenlog( "Wrong slave operation" );
		return $return_code;
	}

	if ( !-d $bond_path )
	{
		&zenlog( "Could not find bonding $bond_name in path $bond_path" );
	#	return $return_code;
	}

	my $bonding_slaves_filename = &getGlobalConfiguration('bonding_slaves_filename');

	#open ( my $bond_slaves_file, '>', "$bond_path/$bonding_slaves_filename" );
	my $bond_slaves_file = "${bond_path}\/${bonding_slaves_filename}";
	my $bondslave = "$bond_path/$bonding_slaves_filename";

	if ( ! -f $bond_slaves_file )
	{
		&zenlog( "Could not open file $bondslave: $!" );
		#return $return_code;
	}

	system("echo $operator$bond_slave > $bondslave");
	#close $bond_slaves_file;

	$return_code = 0;

	return $return_code;
}

=begin nd
Function: getBondConfig

	Get a hash reference with all the stored bonding interfaces configuration.

Parameters:
	none - .

Returns:
	scalar - Hash reference with pairs (bonding name => bonding hashref) of all bonding interfaces.

See Also:
	
=cut
sub getBondConfig
{
	# returns:	0 on failure
	#			Config_tiny object on success

	# requires:
	#~ use Config::Tiny;
	my $bond_config_file = &getGlobalConfiguration('bond_config_file');

	if ( !-f $bond_config_file )
	{
		&zenlog( "Creating bonding configuration file $bond_config_file" );
		open my $bond_file, '>', $bond_config_file;

		if ( !$bond_file )
		{
			&zenlog( "Could not create bonding configuration file $bond_config_file: $!" );
			return 0;
		}

		close $bond_file;
	}

	# Open the config
	my $bond_conf = Config::Tiny->read( $bond_config_file );

	# put slaves as array elements
	for my $bond ( keys %{ $bond_conf } )
	{
		next if $bond eq '_';

		$bond_conf->{ $bond }->{ slaves } =
		  [split ( ' ', $bond_conf->{ $bond }->{ slaves } )];
	}

	# FIXME: error handling?
	return $bond_conf;
}

=begin nd
Function: setBondConfig

	Save/Store the bonding configuration.

Parameters:
	bond_conf - Hashref with all bondings configuration.

Returns:
	none - .

See Also:
	
=cut
sub setBondConfig
{
	my $bond_conf = shift;

	# store slaves as a string
	for my $bond ( keys %{ $bond_conf } )
	{
		next if $bond eq '_';

		$bond_conf->{ $bond }->{ slaves } = "@{ $bond_conf->{ $bond }->{ slaves } }";
	}

	my $bond_config_file = &getGlobalConfiguration('bond_config_file');
	$bond_conf->write( $bond_config_file );

	# put slaves back as array elements
	for my $bond ( keys %{ $bond_conf } )
	{
		next if $bond eq '_';

		$bond_conf->{ $bond }->{ slaves } =
		  [split ( ' ', $bond_conf->{ $bond }->{ slaves } )];
	}

	return;
}

=begin nd
Function: getBondAvailableSlaves

	Get a list with all the nic interfaces with the conditions to be included in a bonding interface as a slave interface.

Parameters:
	none - .

Returns:
	list - list of nic interfaces available.

See Also:
	
=cut
sub getBondAvailableSlaves
{
	my @bond_list = ();
	my $bonding_masters_filename = &getGlobalConfiguration('bonding_masters_filename');

	# get bonding interfaces
	open my $bond_list_file, '<', $bonding_masters_filename;

	if ( $bond_list_file )
	{
		@bond_list = split ' ', <$bond_list_file>;
		close $bond_list_file;
	}

	# get list of all the interfaces
	my $sys_net_dir = &getGlobalConfiguration('sys_net_dir');
	opendir ( my $dir_h, $sys_net_dir );

	if ( !$dir_h )
	{
		&zenlog( "Could not open $sys_net_dir: $!" );
		return -1;
	}

	my @avail_ifaces;

	while ( my $dir_entry = readdir $dir_h )
	{
		next if $dir_entry eq '.';                      # not . dir
		next if $dir_entry eq '..';                     # not .. dir
		next if $dir_entry eq 'bonding_masters';        # not bonding_masters file
		next if $dir_entry =~ /(:|\.)/;                 # not vlan nor vini
		next if grep ( /^$dir_entry$/, @bond_list );    # not a bond
		my $iface = &getSystemInterface( $dir_entry );
		next if $iface->{ status } ne 'down';           # must be down
		#~ next if $iface->{ addr };                       # without address

		push ( @avail_ifaces, $dir_entry );
	}

	close $dir_h;
	return @avail_ifaces;
}

=begin nd
Function: getAllBondsSlaves

	Get a list of all the nics belonging to a bonding interface.

Parameters:
	none - .

Returns:
	list - list of NIC names used by bonding interfaces.

See Also:
	
=cut
sub getAllBondsSlaves
{
	my @slaves; # output

	my $bond_list_ref = &getBondList();

	if ( $bond_list_ref )
	{
		for my $bond ( @{ $bond_list_ref } )
		{
			push @slaves, @{ &getBondSlaves( $bond->{ name } ) };
		}
	}

	return @slaves;
}

1;
