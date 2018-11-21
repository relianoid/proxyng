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
use feature 'state';

my $eload;
if ( eval { require Zevenet::ELoad; } )
{
	$eload = 1;
}

my $ip_bin = &getGlobalConfiguration( 'ip_bin' );

sub getInterfaceConfigFile
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $if_name   = shift;
	my $configdir = &getGlobalConfiguration( 'configdir' );
	return "$configdir/if_${if_name}_conf";
}

=begin nd
Variable: $if_ref

	Reference to a hash representation of a network interface.
	It can be found dereferenced and used as a (%iface or %interface) hash.

	$if_ref->{ name }     - Interface name.
	$if_ref->{ addr }     - IP address. Empty if not configured.
	$if_ref->{ mask }     - Network mask. Empty if not configured.
	$if_ref->{ gateway }  - Interface gateway. Empty if not configured.
	$if_ref->{ status }   - 'up' for enabled, or 'down' for disabled.
	$if_ref->{ ip_v }     - IP version, 4 or 6.
	$if_ref->{ dev }      - Name without VLAN or Virtual part (same as NIC or Bonding)
	$if_ref->{ vini }     - Part of the name corresponding to a Virtual interface. Can be empty.
	$if_ref->{ vlan }     - Part of the name corresponding to a VLAN interface. Can be empty.
	$if_ref->{ mac }      - Interface hardware address.
	$if_ref->{ type }     - Interface type: nic, bond, vlan, virtual.
	$if_ref->{ parent }   - Interface which this interface is based/depends on.
	$if_ref->{ float }    - Floating interface selected for this interface. For routing interfaces only.
	$if_ref->{ is_slave } - Whether the NIC interface is a member of a Bonding interface. For NIC interfaces only.

See also:
	<getInterfaceConfig>, <setInterfaceConfig>, <getSystemInterface>
=cut

=begin nd
Function: getInterfaceConfig

	Get a hash reference with the stored configuration of a network interface.

Parameters:
	if_name - Interface name.
	ip_version - Interface stack or IP version. 4 or 6 (Default: 4).

Returns:
	scalar - Reference to a network interface hash ($if_ref). undef if the network interface was not found.

Bugs:
	The configuration file exists but there isn't the requested stack.

See Also:
	<$if_ref>

	zcluster-manager, zenbui.pl, zapi/v?/interface.cgi, zcluster_functions.cgi, networking_functions_ext
=cut

sub getInterfaceConfig    # \%iface ($if_name, $ip_version)
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my ( $if_name ) = @_;

	unless ( defined $if_name )
	{
		&zenlog( 'getInterfaceConfig got undefined interface name',
				 'debug2', 'network' );
	}

	#~ &zenlog( "[CALL] getInterfaceConfig( $if_name )" );

	my $ip_version;
	my $if_line;
	my $if_status;
	my $configdir       = &getGlobalConfiguration( 'configdir' );
	my $config_filename = "$configdir/if_${if_name}_conf";

	if ( open my $file, '<', "$config_filename" )
	{
		my @lines = grep { !/^(\s*#|$)/ } <$file>;

		for my $line ( @lines )
		{
			my ( undef, $ip ) = split ';', $line;

			if ( defined $ip )
			{
				$ip_version =
				    ( $ip =~ /:/ )  ? 6
				  : ( $ip =~ /\./ ) ? 4
				  :                   undef;
			}

			if ( defined $ip_version && !$if_line )
			{
				$if_line = $line;
			}
			elsif ( $line =~ /^status=/ )
			{
				$if_status = $line;
				$if_status =~ s/^status=//;
				chomp $if_status;
			}
		}
		close $file;
	}

	# includes !$if_status to avoid warning
	if ( !$if_line && ( !$if_status || $if_status !~ /up/ ) )
	{
		return;
	}

	chomp ( $if_line );
	my @if_params = split ( ';', $if_line );

	# Example: eth0;10.0.0.5;255.255.255.0;up;10.0.0.1;

	require IO::Socket;
	my $socket = IO::Socket::INET->new( Proto => 'udp' );

	my %iface;

	$iface{ name }    = shift @if_params // $if_name;
	$iface{ addr }    = shift @if_params;
	$iface{ mask }    = shift @if_params;
	$iface{ gateway } = shift @if_params;                            # optional
	$iface{ status }  = $if_status;
	$iface{ dev }     = $if_name;
	$iface{ vini }    = undef;
	$iface{ vlan }    = undef;
	$iface{ mac }     = undef;
	$iface{ type }    = &getInterfaceType( $if_name );
	$iface{ parent }  = &getParentInterfaceName( $iface{ name } );
	$iface{ ip_v } =
	  ( $iface{ addr } =~ /:/ ) ? '6' : ( $iface{ addr } =~ /\./ ) ? '4' : 0;
	$iface{ net } =
	  &getAddressNetwork( $iface{ addr }, $iface{ mask }, $iface{ ip_v } );

	if ( $iface{ dev } =~ /:/ )
	{
		( $iface{ dev }, $iface{ vini } ) = split ':', $iface{ dev };
	}

	if ( !$iface{ name } )
	{
		$iface{ name } = $if_name;
	}

	if ( $iface{ dev } =~ /./ )
	{
		# dot must be escaped
		( $iface{ dev }, $iface{ vlan } ) = split '\.', $iface{ dev };
	}

	$iface{ mac } = $socket->if_hwaddr( $iface{ dev } );

	# Interfaces without ip do not get HW addr via socket,
	# in those cases get the MAC from the OS.
	unless ( $iface{ mac } )
	{
		open my $fh, '<', "/sys/class/net/$if_name/address";
		chomp ( $iface{ mac } = <$fh> );
		close $fh;
	}

	# complex check to avoid warnings
	if (
		 (
		      !exists ( $iface{ vini } )
		   || !defined ( $iface{ vini } )
		   || $iface{ vini } eq ''
		 )
		 && $iface{ addr }
	  )
	{
		require Config::Tiny;
		my $float = Config::Tiny->read( &getGlobalConfiguration( 'floatfile' ) );

		$iface{ float } = $float->{ _ }->{ $iface{ name } } // '';
	}

	state $saved_bond_slaves = 0;

	if ( $eload && $iface{ type } eq 'nic' )
	{
		# not die if the appliance has not a certificate
		eval {
			unless ( $saved_bond_slaves )
			{
				@TMP::bond_slaves = &eload( module => 'Zevenet::Net::Bonding',
											func   => 'getAllBondsSlaves', );

				$saved_bond_slaves = 1;
			}
		};

		$iface{ is_slave } =
		  ( grep { $iface{ name } eq $_ } @TMP::bond_slaves ) ? 'true' : 'false';
	}

	# for virtual interface, overwrite mask and gw with parent values
	if ( $iface{ type } eq 'vini' )
	{
		my $if_parent = &getInterfaceConfig( $iface{ parent } );
		$iface{ mask }    = $if_parent->{ mask };
		$iface{ gateway } = $if_parent->{ gateway };
	}

	#~ &zenlog(
	#~ "getInterfaceConfig( $if_name ) returns " . Dumper \%iface );

	return \%iface;
}

=begin nd
Function: setInterfaceConfig

	Store a network interface configuration.

Parameters:
	if_ref - Reference to a network interface hash.

Returns:
	boolean - 1 on success, or 0 on failure.

See Also:
	<getInterfaceConfig>, <setInterfaceUp>, zevenet, zenbui.pl, zapi/v?/interface.cgi
=cut

# returns 1 if it was successful
# returns 0 if it wasn't successful
sub setInterfaceConfig    # $bool ($if_ref)
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $if_ref = shift;

	if ( ref $if_ref ne 'HASH' )
	{
		&zenlog( "Input parameter is not a hash reference", "warning", "NETWORK" );
		return;
	}

	&zenlog( "setInterfaceConfig: " . Dumper $if_ref, "debug", "NETWORK" )
	  if &debug() > 2;
	my @if_params = ( 'name', 'addr', 'mask', 'gateway' );

	my $if_line         = join ( ';', @{ $if_ref }{ @if_params } ) . ';';
	my $configdir       = &getGlobalConfiguration( 'configdir' );
	my $config_filename = "$configdir/if_$$if_ref{ name }_conf";

	if ( $if_ref->{ addr } && !$if_ref->{ ip_v } )
	{
		$if_ref->{ ip_v } = &ipversion( $if_ref->{ addr } );
	}

	if ( !-f $config_filename )
	{
		open my $fh, '>', $config_filename;
		print $fh "status=up\n";
		close $fh;
	}

	# Example: eth0;10.0.0.5;255.255.255.0;up;10.0.0.1;
	require Tie::File;

	if ( tie my @file_lines, 'Tie::File', "$config_filename" )
	{
		require Zevenet::Net::Validate;
		my $ip_line_found = 0;

		for my $line ( @file_lines )
		{
			# skip commented and empty lines
			if ( grep { /^(\s*#|$)/ } $line )
			{
				next;
			}

			my ( undef, $ip ) = split ';', $line;

			#if ( $$if_ref{ ip_v } eq &ipversion( $ip ) && !$ip_line_found )
			if ( defined ( $ip ) && !$ip_line_found )
			{
				# replace line
				$line          = $if_line;
				$ip_line_found = 'true';
			}
			elsif ( $line =~ /^status=/ )
			{
				$line = "status=$$if_ref{status}";
			}
		}

		if ( !$ip_line_found )
		{
			push ( @file_lines, $if_line );
		}

		untie @file_lines;
	}
	else
	{
		&zenlog( "$config_filename: $!", "info", "NETWORK" );

		# returns zero on failure
		return 0;
	}

	# returns a true value on success
	return 1;
}

=begin nd
Function: getDevVlanVini

	Get a hash reference with the interface name divided into: dev, vlan, vini.

Parameters:
	if_name - Interface name.

Returns:
	Reference to a hash with:
	dev - NIC or Bonding part of the interface name.
	vlan - VLAN part of the interface name.
	vini - Virtual interface part of the interface name.

See Also:
	<getParentInterfaceName>, <getSystemInterfaceList>, <getSystemInterface>, zapi/v2/interface.cgi
=cut

sub getDevVlanVini    # ($if_name)
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my %if;
	$if{ dev } = shift;

	if ( $if{ dev } =~ /:/ )
	{
		( $if{ dev }, $if{ vini } ) = split ':', $if{ dev };
	}

	if ( $if{ dev } =~ /\./ )    # dot must be escaped
	{
		( $if{ dev }, $if{ vlan } ) = split '\.', $if{ dev };
	}

	return \%if;
}

=begin nd
Function: getConfigInterfaceList

	Get a reference to an array of all the interfaces saved in files.

Parameters:
	none - .

Returns:
	scalar - reference to array of configured interfaces.

See Also:
	zenloadbalanacer, zcluster-manager, <getIfacesFromIf>,
	<getActiveInterfaceList>, <getSystemInterfaceList>, <getFloatInterfaceForAddress>
=cut

sub getConfigInterfaceList
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my @configured_interfaces;
	my $configdir = &getGlobalConfiguration( 'configdir' );

	if ( opendir my $dir, "$configdir" )
	{
		for my $filename ( readdir $dir )
		{
			if ( $filename =~ /if_(.+)_conf/ )
			{
				my $if_name = $1;
				my $if_ref;

				#~ $if_ref = &getInterfaceConfig( $if_name, 4 );
				$if_ref = &getInterfaceConfig( $if_name );
				if ( $$if_ref{ addr } )
				{
					push @configured_interfaces, $if_ref;
				}

				#~ $if_ref = &getInterfaceConfig( $if_name, 6 );
				#~ if ( $$if_ref{ addr } )
				#~ {
				#~ push @configured_interfaces, $if_ref;
				#~ }
			}
		}

		closedir $dir;
	}
	else
	{
		&zenlog( "Error reading directory $configdir: $!", "error", "NETWORK" );
	}

	return \@configured_interfaces;
}

=begin nd
Function: getInterfaceSystemStatus

	Get the status of an network interface in the system.

Parameters:
	if_ref - Reference to a network interface hash.

Returns:
	scalar - 'up' or 'down'.

See Also:
	<getActiveInterfaceList>, <getSystemInterfaceList>, <getInterfaceTypeList>, zapi/v?/interface.cgi,
=cut

sub getInterfaceSystemStatus    # ($if_ref)
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $if_ref = shift;

	my $parent_if_name = &getParentInterfaceName( $if_ref->{ name } );
	my $status_if_name = $if_ref->{ name };

	if ( $if_ref->{ vini } ne '' )    # vini
	{
		$status_if_name = $parent_if_name;
	}

	my $ip_bin    = &getGlobalConfiguration( 'ip_bin' );
	my $ip_output = `$ip_bin link show $status_if_name`;
	$ip_output =~ / state (\w+) /;
	my $if_status = lc $1;

	if ( $if_status !~ /^(?:up|down)$/ )    # if not up or down, ex: UNKNOWN
	{
		my ( $flags ) = $ip_output =~ /<(.+)>/;
		my @flags = split ( ',', $flags );

		if ( grep ( /^UP$/, @flags ) )
		{
			$if_status = 'up';
		}
		else
		{
			$if_status = 'down';
		}
	}

	# Set as down vinis not available
	$ip_output = `$ip_bin addr show $status_if_name`;

	if ( $ip_output !~ /$$if_ref{ addr }/ && $if_ref->{ vini } ne '' )
	{
		$$if_ref{ status } = 'down';
		return $$if_ref{ status };
	}

	unless ( $if_ref->{ vini } ne '' && $if_ref->{ status } eq 'down' )    # vini
	{
		$if_ref->{ status } = $if_status;
	}

	return $if_ref->{ status } if $if_ref->{ status } eq 'down';

	return $if_ref->{ status } if !$parent_if_name;

	my $parent_if_ref = &getInterfaceConfig( $parent_if_name, $if_ref->{ ip_v } );

	# vlans do not require the parent interface to be configured
	return $if_ref->{ status } if !$parent_if_ref;

	return &getInterfaceSystemStatus( $parent_if_ref );
}

=begin nd
Function: getParentInterfaceName

	Get the parent interface name.

Parameters:
	if_name - Interface name.

Returns:
	string - Parent interface name or undef if there is no parent interface (NIC and Bonding).

See Also:
	<getInterfaceConfig>, <getSystemInterface>, zevenet, zapi/v?/interface.cgi
=cut

sub getParentInterfaceName    # ($if_name)
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $if_name = shift;

	my $if_ref = &getDevVlanVini( $if_name );
	my $parent_if_name;

	my $is_vlan    = defined $if_ref->{ vlan } && length $if_ref->{ vlan };
	my $is_virtual = defined $if_ref->{ vini } && length $if_ref->{ vini };

	# child interface: eth0.100:virtual => eth0.100
	if ( $is_virtual && $is_vlan )
	{
		$parent_if_name = "$$if_ref{dev}.$$if_ref{vlan}";
	}

	# child interface: eth0:virtual => eth0
	elsif ( $is_virtual && !$is_vlan )
	{
		$parent_if_name = $if_ref->{ dev };
	}

	# child interface: eth0.100 => eth0
	elsif ( !$is_virtual && $is_vlan )
	{
		$parent_if_name = $if_ref->{ dev };
	}

	# child interface: eth0 => undef
	elsif ( !$is_virtual && !$is_vlan )
	{
		$parent_if_name = undef;
	}

	return $parent_if_name;
}

=begin nd
Function: getActiveInterfaceList

	Get a reference to a list of all running (up) and configured network interfaces.

Parameters:
	none - .

Returns:
	scalar - reference to an array of network interface hashrefs.

See Also:
	Zapi v3: post.cgi, put.cgi, system.cgi
=cut

sub getActiveInterfaceList
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my @configured_interfaces = @{ &getConfigInterfaceList() };

	# sort list
	@configured_interfaces =
	  sort { $a->{ name } cmp $b->{ name } } @configured_interfaces;

	# apply device status heritage
	$_->{ status } = &getInterfaceSystemStatus( $_ ) for @configured_interfaces;

	# discard interfaces down
	@configured_interfaces = grep { $_->{ status } eq 'up' } @configured_interfaces;

	# find maximun lengths for padding
	my $max_dev_length;
	my $max_ip_length;

	for my $iface ( @configured_interfaces )
	{
		if ( $iface->{ status } == 'up' )
		{
			my $dev_length = length $iface->{ name };
			$max_dev_length = $dev_length if $dev_length > $max_dev_length;

			my $ip_length = length $iface->{ addr };
			$max_ip_length = $ip_length if $ip_length > $max_ip_length;
		}
	}

	# make padding
	for my $iface ( @configured_interfaces )
	{
		my $dev_ip_padded = sprintf ( "%-${max_dev_length}s -> %-${max_ip_length}s",
									  $$iface{ name }, $$iface{ addr } );
		$dev_ip_padded =~ s/ +$//;
		$dev_ip_padded =~ s/ /&nbsp;/g;

		$iface->{ dev_ip_padded } = $dev_ip_padded;
	}

	return \@configured_interfaces;
}

=begin nd
Function: getSystemInterfaceList

	Get a reference to a list with all the interfaces, configured and not configured.

Parameters:
	none - .

Returns:
	scalar - reference to an array with configured and system network interfaces.

See Also:
	zapi/v?/interface.cgi, zapi/v3/cluster.cgi
=cut

sub getSystemInterfaceList
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	use IO::Interface qw(:flags);

	my @interfaces;    # output
	my @configured_interfaces = @{ &getConfigInterfaceList() };

	my $socket = IO::Socket::INET->new( Proto => 'udp' );
	my @system_interfaces = &getInterfaceList();

	## Build system device "tree"
	for my $if_name ( @system_interfaces )    # list of interface names
	{
		# ignore loopback device, ipv6 tunnel, vlans and vinis
		next if $if_name =~ /^lo$|^sit\d+$/;
		next if $if_name =~ /\./;
		next if $if_name =~ /:/;

		my %if_parts = %{ &getDevVlanVini( $if_name ) };

		my $if_ref;
		my $if_flags = $socket->if_flags( $if_name );

		# run for IPv4 and IPv6
		#~ for my $ip_stack ( 4, 6 )
		{
			#~ $if_ref = &getInterfaceConfig( $if_name, $ip_stack );
			$if_ref = &getInterfaceConfig( $if_name );

			if ( !$$if_ref{ addr } )
			{
				# populate not configured interface
				$$if_ref{ status } = ( $if_flags & IFF_UP ) ? "up" : "down";
				$$if_ref{ mac }    = $socket->if_hwaddr( $if_name );
				$$if_ref{ name }   = $if_name;
				$$if_ref{ addr }   = '';
				$$if_ref{ mask }   = '';
				$$if_ref{ dev }    = $if_parts{ dev };
				$$if_ref{ vlan }   = $if_parts{ vlan };
				$$if_ref{ vini }   = $if_parts{ vini };
				$$if_ref{ ip_v }   = '';
				$$if_ref{ type }   = &getInterfaceType( $if_name );
			}

			if ( !( $if_flags & IFF_RUNNING ) && ( $if_flags & IFF_UP ) )
			{
				$$if_ref{ link } = "off";
			}

			# add interface to the list
			push ( @interfaces, $if_ref );

			# add vlans
			for my $vlan_if_conf ( @configured_interfaces )
			{
				next if $$vlan_if_conf{ dev } ne $$if_ref{ dev };
				next if $$vlan_if_conf{ vlan } eq '';
				next if $$vlan_if_conf{ vini } ne '';

				#~ if ( $$vlan_if_conf{ ip_v } == $ip_stack )
				{
					push ( @interfaces, $vlan_if_conf );

					# add vini of vlan
					for my $vini_if_conf ( @configured_interfaces )
					{
						next if $$vini_if_conf{ dev } ne $$if_ref{ dev };
						next if $$vini_if_conf{ vlan } ne $$vlan_if_conf{ vlan };
						next if $$vini_if_conf{ vini } eq '';

						#~ if ( $$vini_if_conf{ ip_v } == $ip_stack )
						{
							push ( @interfaces, $vini_if_conf );
						}
					}
				}
			}

			# add vini of nic
			for my $vini_if_conf ( @configured_interfaces )
			{
				next if $$vini_if_conf{ dev } ne $$if_ref{ dev };
				next if $$vini_if_conf{ vlan } ne '';
				next if $$vini_if_conf{ vini } eq '';

				#~ if ( $$vini_if_conf{ ip_v } == $ip_stack )
				{
					push ( @interfaces, $vini_if_conf );
				}
			}
		}
	}

	@interfaces = sort { $a->{ name } cmp $b->{ name } } @interfaces;
	$_->{ status } = &getInterfaceSystemStatus( $_ ) for @interfaces;

	return \@interfaces;
}

=begin nd
Function: getSystemInterface

	Get a reference to a network interface hash from the system configuration, not the stored configuration.

Parameters:
	if_name - Interface name.

Returns:
	scalar - reference to a network interface hash as is on the system or undef if not found.

See Also:
	<getInterfaceConfig>, <setInterfaceConfig>
=cut

sub getSystemInterface    # ($if_name)
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $if_ref = {};
	$$if_ref{ name } = shift;

	use IO::Interface qw(:flags);

	my %if_parts = %{ &getDevVlanVini( $$if_ref{ name } ) };
	my $socket   = IO::Socket::INET->new( Proto => 'udp' );
	my $if_flags = $socket->if_flags( $$if_ref{ name } );

	$$if_ref{ mac } = $socket->if_hwaddr( $$if_ref{ name } );

	return if not $$if_ref{ mac };
	$$if_ref{ status } = ( $if_flags & IFF_UP ) ? "up" : "down";
	$$if_ref{ addr }   = '';
	$$if_ref{ mask }   = '';
	$$if_ref{ dev }    = $if_parts{ dev };
	$$if_ref{ vlan }   = $if_parts{ vlan };
	$$if_ref{ vini }   = $if_parts{ vini };
	$$if_ref{ type }   = &getInterfaceType( $$if_ref{ name } );
	$$if_ref{ parent } = &getParentInterfaceName( $$if_ref{ name } );

	state $saved_bond_slaves = 0;

	if ( $eload && $$if_ref{ type } eq 'nic' )
	{
		# not die if the appliance has not a certificate
		eval {
			unless ( $saved_bond_slaves )
			{
				@TMP::bond_slaves = &eload( module => 'Zevenet::Net::Bonding',
											func   => 'getAllBondsSlaves', );

				$saved_bond_slaves = 1;
			}
		};

		$$if_ref{ is_slave } =
		  ( grep { $$if_ref{ name } eq $_ } @TMP::bond_slaves ) ? 'true' : 'false';
	}

	return $if_ref;
}

=begin nd
Function: getInterfaceType

	Get the type of a network interface from its name using linux 'hints'.

	Original source code in bash:
	http://stackoverflow.com/questions/4475420/detect-network-connection-type-in-linux

	Translated to perl and adapted by Zevenet

	Interface types: nic, virtual, vlan, bond, dummy or lo.

Parameters:
	if_name - Interface name.

Returns:
	scalar - Interface type: nic, virtual, vlan, bond, dummy or lo.

See Also:

=cut

# Source in bash translated to perl:
# http://stackoverflow.com/questions/4475420/detect-network-connection-type-in-linux
#
# Interface types: nic, virtual, vlan, bond
sub getInterfaceType
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $if_name = shift;

	my $type;

	return if $if_name eq '' || !defined $if_name;

	# interfaz for cluster when is in maintenance mode
	return 'dummy' if $if_name eq 'cl_maintenance';

	if ( !-d "/sys/class/net/$if_name" )
	{
		my ( $parent_if ) = split ( ':', $if_name );
		my $quoted_if     = quotemeta $if_name;
		my $ip_bin        = &getGlobalConfiguration( 'ip_bin' );
		my $found =
		  grep ( /inet .+ $quoted_if$/, `$ip_bin addr show $parent_if 2>/dev/null` );

		if ( !$found )
		{
			my $configdir = &getGlobalConfiguration( 'configdir' );
			$found = ( -f "$configdir/if_${if_name}_conf" && $if_name =~ /^.+\:.+$/ );
		}

		if ( $found )
		{
			return 'virtual';
		}
		else
		{
			return;
		}
	}

	my $code;    # read type code
	{
		my $if_type_filename = "/sys/class/net/$if_name/type";

		open ( my $type_file, '<', $if_type_filename )
		  or die "Could not open file $if_type_filename: $!";
		chomp ( $code = <$type_file> );
		close $type_file;
	}

	if ( $code == 1 )
	{
		$type = 'nic';

		# Ethernet, may also be wireless, ...
		if ( -f "/proc/net/vlan/$if_name" )
		{
			$type = 'vlan';
		}
		elsif ( -d "/sys/class/net/$if_name/bonding" )
		{
			$type = 'bond';
		}

#elsif ( -d "/sys/class/net/$if_name/wireless" || -l "/sys/class/net/$if_name/phy80211" )
#{
#	$type = 'wlan';
#}
#elsif ( -d "/sys/class/net/$if_name/bridge" )
#{
#	$type = 'bridge';
#}
#elsif ( -f "/sys/class/net/$if_name/tun_flags" )
#{
#	$type = 'tap';
#}
#elsif ( -d "/sys/devices/virtual/net/$if_name" )
#{
#	$type = 'dummy' if $if_name =~ /^dummy/;
#}
	}
	elsif ( $code == 24 )
	{
		$type = 'nic';    # firewire ;; # IEEE 1394 IPv4 - RFC 2734
	}
	elsif ( $code == 32 )
	{
		if ( -d "/sys/class/net/$if_name/bonding" )
		{
			$type = 'bond';
		}

		#elsif ( -d "/sys/class/net/$if_name/create_child" )
		#{
		#	$type = 'ib';
		#}
		#else
		#{
		#	$type = 'ibchild';
		#}
	}

	#elsif ( $code == 512 ) { $type = 'ppp'; }
	#elsif ( $code == 768 )
	#{
	#	$type = 'ipip';    # IPIP tunnel
	#}
	#elsif ( $code == 769 )
	#{
	#	$type = 'ip6tnl';    # IP6IP6 tunnel
	#}
	elsif ( $code == 772 ) { $type = 'lo'; }

	#elsif ( $code == 776 )
	#{
	#	$type = 'sit';       # sit0 device - IPv6-in-IPv4
	#}
	#elsif ( $code == 778 )
	#{
	#	$type = 'gre';       # GRE over IP
	#}
	#elsif ( $code == 783 )
	#{
	#	$type = 'irda';      # Linux-IrDA
	#}
	#elsif ( $code == 801 )   { $type = 'wlan_aux'; }
	#elsif ( $code == 65534 ) { $type = 'tun'; }

	# The following case statement still has to be replaced by something
	# which does not rely on the interface names.
	# case $if_name in
	# 	ippp*|isdn*) type=isdn;;
	# 	mip6mnha*)   type=mip6mnha;;
	# esac

	return $type if defined $type;

	my $msg = "Could not recognize the type of the interface $if_name.";

	&zenlog( $msg, "error", "NETWORK" );
	die ( $msg );    # This should not happen
}

=begin nd
Function: getInterfaceTypeList

	Get a list of hashrefs with interfaces of a single type.

	Types supported are: nic, bond, vlan and virtual.

Parameters:
	list_type - Network interface type.

Returns:
	list - list of network interfaces hashrefs.

See Also:

=cut

sub getInterfaceTypeList
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $list_type = shift;

	my @interfaces = ();

	if ( $list_type =~ /^(?:nic|bond|vlan)$/ )
	{
		my @system_interfaces = sort &getInterfaceList();

		for my $if_name ( @system_interfaces )
		{
			if ( $list_type eq &getInterfaceType( $if_name ) )
			{
				my $output_if = &getInterfaceConfig( $if_name );

				if ( !$output_if || !$output_if->{ mac } )
				{
					$output_if = &getSystemInterface( $if_name );
				}

				push ( @interfaces, $output_if );
			}
		}
	}
	elsif ( $list_type eq 'virtual' )
	{
		require Zevenet::Validate;

		opendir my $conf_dir, &getGlobalConfiguration( 'configdir' );
		my $virt_if_re = &getValidFormat( 'virt_interface' );

		for my $file_name ( sort readdir $conf_dir )
		{
			if ( $file_name =~ /^if_($virt_if_re)_conf$/ )
			{
				my $iface = &getInterfaceConfig( $1 );
				$iface->{ status } = &getInterfaceSystemStatus( $iface );

				# put the gateway and netmask of parent interface
				my $parent_if = &getInterfaceConfig( $iface->{ parent } );
				$iface->{ mask }    = $parent_if->{ mask };
				$iface->{ gateway } = $parent_if->{ gateway };
				push ( @interfaces, $iface );
			}
		}
	}
	else
	{
		my $msg = "Interface type '$list_type' is not supported.";
		&zenlog( $msg, "error", "NETWORK" );
		die ( $msg );
	}

	return @interfaces;
}

=begin nd
Function: getAppendInterfaces

	Get vlans or virtual interfaces configured from a interface.
	If the interface is a nic or bonding, this function return the virtual interfaces
	create from the VLANs, for example: eth0.2:virt

Parameters:
	ifaceName - Interface name.
	type - Interface type: vlan or virtual.

Returns:
	scalar - reference to an array of interfaces names.

See Also:

=cut

# Get vlan or virtual interfaces appended from a interface
sub getAppendInterfaces    # ( $iface_name, $type )
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my ( $if_parent, $type ) = @_;
	my @output = ();

	my @list = &getInterfaceList();

	my $vlan_tag    = &getValidFormat( 'vlan_tag' );
	my $virtual_tag = &getValidFormat( 'virtual_tag' );

	foreach my $if ( @list )
	{
		if ( $type eq 'vlan' )
		{
			push @output, $if if ( $if =~ /^$if_parent\.$vlan_tag$/ );
		}

		if ( $type eq 'virtual' )
		{
			push @output, $if if ( $if =~ /^$if_parent(?:\.$vlan_tag)?\:$virtual_tag$/ );
		}
	}

	return \@output;
}

=begin nd
Function: getInterfaceList

	Return a list of all network interfaces detected in the system.

Parameters:
	None.

Returns:
	array - list of network interface names.
	array empty - if no network interface is detected.

See Also:
	<listActiveInterfaces>
=cut

sub getInterfaceList
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my @if_list = ();

	#Get link interfaces
	push @if_list, &getLinkNameList();

	#Get virtual interfaces
	push @if_list, &getVirtualInterfaceNameList();

	return @if_list;
}

=begin nd
Function: getVirtualInterfaceNameList

	Get a list of the virtual interfaces names.

Parameters:
	none - .

Returns:
	list - Every virtual interface name.
=cut

sub getVirtualInterfaceNameList
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	require Zevenet::Validate;

	opendir ( my $conf_dir, &getGlobalConfiguration( 'configdir' ) );
	my $virt_if_re = &getValidFormat( 'virt_interface' );
	my @interfaces;

	foreach my $filename ( readdir ( $conf_dir ) )
	{
		push @interfaces, $1 if ( $filename =~ /^if_($virt_if_re)_conf$/ );
	}

	closedir ( $conf_dir );

	return @interfaces;
}

=begin nd
Function: getLinkInterfaceNameList

	Get a list of the link interfaces names.

Parameters:
	none - .

Returns:
	list - Every link interface name.
=cut

sub getLinkNameList
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $sys_net_dir = getGlobalConfiguration( 'sys_net_dir' );

	# Get link interfaces (nic, bond and vlan)
	opendir ( my $if_dir, $sys_net_dir );
	my @if_list = grep { -l "$sys_net_dir/$_" } readdir $if_dir;
	closedir $if_dir;

	return @if_list;
}

=begin nd
Function: getIpAddressExists

	Return if a IP exists in some configurated interface

Parameters:
	IP - IP address

Returns:
	Integer - 0 if it doesn't exist or 1 if the IP already exists

=cut

sub getIpAddressExists
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $ip = shift;

	require Zevenet::Net::Validate;

	my $output   = 0;
	my $ip_ver   = &ipversion( $ip );
	my $addr_ref = NetAddr::IP->new( $ip );

	foreach my $if_ref ( @{ &getConfigInterfaceList() } )
	{
		# IPv4
		if ( $ip_ver == 4 && $if_ref->{ ip_v } == 4 && $if_ref->{ addr } eq $ip )
		{
			$output = 1;
			last;
		}

		# IPv6
		if ( $ip_ver == 6 && $if_ref->{ ip_v } == 6 )
		{
			if ( NetAddr::IP->new( $if_ref->{ addr } ) eq $addr_ref )
			{
				$output = 1;
				last;
			}
		}
	}

	return $output;
}

=begin nd
Function: getInterfaceChild

	Show the interfaces that depends directly of the interface.
	From a nic, bonding and VLANs interfaces depend the virtual interfaces.
	From a virtual interface depends the floating itnerfaces.

Parameters:
	ifaceName - Interface name.

Returns:
	scalar - Array of interfaces names.

FIXME: rename me, this function is used to check if the interface has some interfaces
 that depends of it. It is useful to avoid that corrupts the child interface

See Also:

=cut

sub getInterfaceChild
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $if_name = shift;

	my @output      = ();
	my $if_ref      = &getInterfaceConfig( $if_name );
	my $virtual_tag = &getValidFormat( 'virtual_tag' );

	# show floating interfaces used by this virtual interface
	if ( $if_ref->{ 'type' } eq 'virtual' )
	{
		require Config::Tiny;
		my $float = Config::Tiny->read( &getGlobalConfiguration( 'floatfile' ) );

		foreach my $iface ( keys %{ $float->{ _ } } )
		{
			push @output, $iface if ( $float->{ _ }->{ $iface } eq $if_name );
		}
	}

	# the other type of interfaces can have virtual interfaces as child
	# vlan, bond and nic
	else
	{
		push @output,
		  grep ( /^$if_name:$virtual_tag$/, &getVirtualInterfaceNameList() );
	}

	return @output;
}

sub getAddressNetwork
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my ( $addr, $mask, $ip_v ) = @_;

	require NetAddr::IP;

	my $net;

	if ( $ip_v == 4 )
	{
		my $ip = NetAddr::IP->new( $addr, $mask );
		$net = lc $ip->network()->addr();
	}
	elsif ( $ip_v == 6 )
	{
		my $ip = NetAddr::IP->new6( $addr, $mask );
		$net = lc $ip->network()->addr();
	}
	else
	{
		$net = undef;
	}

	return $net;
}

sub get_interface_list_struct
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	require Zevenet::User;

	my @output_list;

	# Configured interfaces list
	my @interfaces = @{ &getSystemInterfaceList() };    #140

	# get cluster interface
	my $cluster_if;

	if ( $eload )
	{
		my $zcl_conf = &eload(
							   module => 'Zevenet::Cluster',
							   func   => 'getZClusterConfig',              # 100
		);

		if ( exists $zcl_conf->{ _ }->{ interface } )
		{
			$cluster_if = $zcl_conf->{ _ }->{ interface };
		}
	}

	my $rbac_mod;
	my $rbac_if_list = [];
	my $user         = &getUser();

	if ( $eload && ( $user ne 'root' ) )
	{
		$rbac_mod = 1;
		$rbac_if_list = &eload(
								module => 'Zevenet::RBAC::Group::Core',    # 100
								func   => 'getRBACUsersResources',
								args   => [$user, 'interfaces'],
		);
	}

	# to include 'has_vlan' to nics
	my @vlans = &getInterfaceTypeList( 'vlan' );       # 70

	my $alias;
	$alias = &eload(
					 module => 'Zevenet::Alias',
					 func   => 'getAlias',
					 args   => ['interface']
	) if $eload;

	for my $if_ref ( @interfaces )
	{
		# Exclude cluster maintenance interface
		next if $if_ref->{ type } eq 'dummy';

		# Exclude no user's virtual interfaces
		next
		  if (    $rbac_mod
			   && !grep ( /^$if_ref->{ name }$/, @{ $rbac_if_list } )
			   && ( $if_ref->{ type } eq 'virtual' ) );

		$if_ref->{ status } = &getInterfaceSystemStatus( $if_ref );

		# Any key must cotain a value or "" but can't be null
		if ( !defined $if_ref->{ name } )    { $if_ref->{ name }    = ""; }
		if ( !defined $if_ref->{ addr } )    { $if_ref->{ addr }    = ""; }
		if ( !defined $if_ref->{ mask } )    { $if_ref->{ mask }    = ""; }
		if ( !defined $if_ref->{ gateway } ) { $if_ref->{ gateway } = ""; }
		if ( !defined $if_ref->{ status } )  { $if_ref->{ status }  = ""; }
		if ( !defined $if_ref->{ mac } )     { $if_ref->{ mac }     = ""; }

		my $if_conf = {
			alias   => $alias->{ $if_ref->{ name } },
			name    => $if_ref->{ name },
			ip      => $if_ref->{ addr },
			netmask => $if_ref->{ mask },
			gateway => $if_ref->{ gateway },
			status  => $if_ref->{ status },
			mac     => $if_ref->{ mac },
			type    => $if_ref->{ type },

			#~ ipv     => $if_ref->{ ip_v },
		};

		$if_conf->{ alias } = $alias->{ $if_ref->{ name } } if $eload;

		if ( $if_ref->{ type } eq 'nic' )
		{
			my @bond_slaves = ();

			@bond_slaves = &eload(
								   module => 'Zevenet::Net::Bonding',
								   func   => 'getAllBondsSlaves',
			) if ( $eload );

			$if_conf->{ is_slave } =
			  ( grep { $$if_ref{ name } eq $_ } @bond_slaves ) ? 'true' : 'false';

			# include 'has_vlan'
			for my $vlan_ref ( @vlans )
			{
				if ( $vlan_ref->{ parent } eq $if_ref->{ name } )
				{
					$if_conf->{ has_vlan } = 'true';
					last;
				}
			}

			$if_conf->{ has_vlan } = 'false' unless $if_conf->{ has_vlan };
		}

		if ( $cluster_if && $cluster_if eq $if_ref->{ name } )
		{
			$if_conf->{ is_cluster } = 'true';
		}

		push @output_list, $if_conf;
	}

	return \@output_list;
}

sub get_nic_struct
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $nic = shift;

	my $interface;
	my $alias;
	$alias = &eload(
					 module => 'Zevenet::Alias',
					 func   => 'getAlias',
					 args   => ['interface']
	) if $eload;

	for my $if_ref ( &getInterfaceTypeList( 'nic' ) )
	{
		next unless $if_ref->{ name } eq $nic;

		$if_ref->{ status } = &getInterfaceSystemStatus( $if_ref );

		# Any key must contain a value or "" but can't be null
		if ( !defined $if_ref->{ name } )    { $if_ref->{ name }    = ""; }
		if ( !defined $if_ref->{ addr } )    { $if_ref->{ addr }    = ""; }
		if ( !defined $if_ref->{ mask } )    { $if_ref->{ mask }    = ""; }
		if ( !defined $if_ref->{ gateway } ) { $if_ref->{ gateway } = ""; }
		if ( !defined $if_ref->{ status } )  { $if_ref->{ status }  = ""; }
		if ( !defined $if_ref->{ mac } )     { $if_ref->{ mac }     = ""; }

		$interface = {
					   name    => $if_ref->{ name },
					   ip      => $if_ref->{ addr },
					   netmask => $if_ref->{ mask },
					   gateway => $if_ref->{ gateway },
					   status  => $if_ref->{ status },
					   mac     => $if_ref->{ mac },
		};

		$interface->{ alias }    = $alias->{ $if_ref->{ name } } if $eload;
		$interface->{ is_slave } = $if_ref->{ is_slave }         if $eload;
	}

	return $interface;
}

sub get_nic_list_struct
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my @output_list;

	my @vlans = &getInterfaceTypeList( 'vlan' );

	# get cluster interface
	my $cluster_if;
	my $alias;
	if ( $eload )
	{
		$alias = &eload(
						 module => 'Zevenet::Alias',
						 func   => 'getAlias',
						 args   => ['interface']
		);

		my $zcl_conf = &eload( module => 'Zevenet::Cluster',
							   func   => 'getZClusterConfig' );
		$cluster_if = $zcl_conf->{ _ }->{ interface };
	}

	for my $if_ref ( &getInterfaceTypeList( 'nic' ) )
	{
		$if_ref->{ status } = &getInterfaceSystemStatus( $if_ref );

		# Any key must cotain a value or "" but can't be null
		if ( !defined $if_ref->{ name } )    { $if_ref->{ name }    = ""; }
		if ( !defined $if_ref->{ addr } )    { $if_ref->{ addr }    = ""; }
		if ( !defined $if_ref->{ mask } )    { $if_ref->{ mask }    = ""; }
		if ( !defined $if_ref->{ gateway } ) { $if_ref->{ gateway } = ""; }
		if ( !defined $if_ref->{ status } )  { $if_ref->{ status }  = ""; }
		if ( !defined $if_ref->{ mac } )     { $if_ref->{ mac }     = ""; }

		my $if_conf = {
						name    => $if_ref->{ name },
						ip      => $if_ref->{ addr },
						netmask => $if_ref->{ mask },
						gateway => $if_ref->{ gateway },
						status  => $if_ref->{ status },
						mac     => $if_ref->{ mac },
		};

		$if_conf->{ alias } = $alias->{ $if_ref->{ name } } if $eload;
		$if_conf->{ is_slave } = $if_ref->{ is_slave } if $eload;
		$if_conf->{ is_cluster } = 'true' if $cluster_if eq $if_ref->{ name };

		# include 'has_vlan'
		for my $vlan_ref ( @vlans )
		{
			if ( $vlan_ref->{ parent } eq $if_ref->{ name } )
			{
				$if_conf->{ has_vlan } = 'true';
				last;
			}
		}

		$if_conf->{ has_vlan } = 'false' unless $if_conf->{ has_vlan };

		push @output_list, $if_conf;
	}

	return \@output_list;
}

sub get_vlan_struct
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my ( $vlan ) = @_;

	my $interface;
	my $alias;
	$alias = &eload(
					 module => 'Zevenet::Alias',
					 func   => 'getAlias',
					 args   => ['interface']
	) if $eload;

	for my $if_ref ( &getInterfaceTypeList( 'vlan' ) )
	{
		next unless $if_ref->{ name } eq $vlan;

		$interface = $if_ref;
	}

	return unless $interface;

	$interface->{ status } = &getInterfaceSystemStatus( $interface );

	# Any key must contain a value or "" but can't be null
	if ( !defined $interface->{ name } )    { $interface->{ name }    = ""; }
	if ( !defined $interface->{ addr } )    { $interface->{ addr }    = ""; }
	if ( !defined $interface->{ mask } )    { $interface->{ mask }    = ""; }
	if ( !defined $interface->{ gateway } ) { $interface->{ gateway } = ""; }
	if ( !defined $interface->{ status } )  { $interface->{ status }  = ""; }
	if ( !defined $interface->{ mac } )     { $interface->{ mac }     = ""; }

	my $output = {
				   name    => $interface->{ name },
				   ip      => $interface->{ addr },
				   netmask => $interface->{ mask },
				   gateway => $interface->{ gateway },
				   status  => $interface->{ status },
				   mac     => $interface->{ mac },
	};

	$output->{ alias } = $alias->{ $interface->{ name } } if $eload;

	return $output;
}

sub get_vlan_list_struct
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my @output_list;
	my $cluster_if;

	my $alias;
	if ( $eload )
	{
		$alias = &eload(
						 module => 'Zevenet::Alias',
						 func   => 'getAlias',
						 args   => ['interface']
		);

		# get cluster interface
		my $zcl_conf = &eload( module => 'Zevenet::Cluster',
							   func   => 'getZClusterConfig', );
		$cluster_if = $zcl_conf->{ _ }->{ interface };
	}

	for my $if_ref ( &getInterfaceTypeList( 'vlan' ) )
	{
		$if_ref->{ status } = &getInterfaceSystemStatus( $if_ref );

		# Any key must cotain a value or "" but can't be null
		if ( !defined $if_ref->{ name } )    { $if_ref->{ name }    = ""; }
		if ( !defined $if_ref->{ addr } )    { $if_ref->{ addr }    = ""; }
		if ( !defined $if_ref->{ mask } )    { $if_ref->{ mask }    = ""; }
		if ( !defined $if_ref->{ gateway } ) { $if_ref->{ gateway } = ""; }
		if ( !defined $if_ref->{ status } )  { $if_ref->{ status }  = ""; }
		if ( !defined $if_ref->{ mac } )     { $if_ref->{ mac }     = ""; }

		my $if_conf = {
						name    => $if_ref->{ name },
						ip      => $if_ref->{ addr },
						netmask => $if_ref->{ mask },
						gateway => $if_ref->{ gateway },
						status  => $if_ref->{ status },
						mac     => $if_ref->{ mac },
						parent  => $if_ref->{ parent },
		};

		$if_conf->{ alias } = $alias->{ $if_ref->{ name } } if $eload;
		$if_conf->{ is_cluster } = 'true'
		  if $cluster_if && $cluster_if eq $if_ref->{ name };

		push @output_list, $if_conf;
	}

	return \@output_list;
}

sub get_virtual_struct
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my ( $virtual ) = @_;

	my $interface;
	my $alias;
	$alias = &eload(
					 module => 'Zevenet::Alias',
					 func   => 'getAlias',
					 args   => ['interface']
	) if $eload;

	for my $if_ref ( &getInterfaceTypeList( 'virtual' ) )
	{
		next unless $if_ref->{ name } eq $virtual;

		$interface = $if_ref;
	}

	return unless $interface;

	$interface->{ status } = &getInterfaceSystemStatus( $interface );

	# Any key must contain a value or "" but can't be null
	if ( !defined $interface->{ name } )    { $interface->{ name }    = ""; }
	if ( !defined $interface->{ addr } )    { $interface->{ addr }    = ""; }
	if ( !defined $interface->{ mask } )    { $interface->{ mask }    = ""; }
	if ( !defined $interface->{ gateway } ) { $interface->{ gateway } = ""; }
	if ( !defined $interface->{ status } )  { $interface->{ status }  = ""; }
	if ( !defined $interface->{ mac } )     { $interface->{ mac }     = ""; }

	my $output = {
				   name    => $interface->{ name },
				   ip      => $interface->{ addr },
				   netmask => $interface->{ mask },
				   gateway => $interface->{ gateway },
				   status  => $interface->{ status },
				   mac     => $interface->{ mac },
	};

	$output->{ alias } = $alias->{ $interface->{ name } };

	return $output;
}

sub get_virtual_list_struct
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my @output_list = ();
	my $alias;
	$alias = &eload(
					 module => 'Zevenet::Alias',
					 func   => 'getAlias',
					 args   => ['interface']
	) if $eload;

	for my $if_ref ( &getInterfaceTypeList( 'virtual' ) )
	{
		$if_ref->{ status } = &getInterfaceSystemStatus( $if_ref );

		# Any key must cotain a value or "" but can't be null
		if ( !defined $if_ref->{ name } )    { $if_ref->{ name }    = ""; }
		if ( !defined $if_ref->{ addr } )    { $if_ref->{ addr }    = ""; }
		if ( !defined $if_ref->{ mask } )    { $if_ref->{ mask }    = ""; }
		if ( !defined $if_ref->{ gateway } ) { $if_ref->{ gateway } = ""; }
		if ( !defined $if_ref->{ status } )  { $if_ref->{ status }  = ""; }
		if ( !defined $if_ref->{ mac } )     { $if_ref->{ mac }     = ""; }

		push @output_list,
		  {
			name    => $if_ref->{ name },
			ip      => $if_ref->{ addr },
			netmask => $if_ref->{ mask },
			gateway => $if_ref->{ gateway },
			status  => $if_ref->{ status },
			mac     => $if_ref->{ mac },
			parent  => $if_ref->{ parent },
		  };

		$output_list[-1]->{ alias } = $alias->{ $if_ref->{ name } } if $eload;
	}

	return \@output_list;
}

1;
