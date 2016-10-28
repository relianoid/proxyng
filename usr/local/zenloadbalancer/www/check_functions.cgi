#!/usr/bin/perl
###############################################################################
#
#     Zen Load Balancer Software License
#     This file is part of the Zen Load Balancer software package.
#
#     Copyright (C) 2016 SOFINTEL IT ENGINEERING SL, Sevilla (Spain)
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

# Notes about regular expressions:
#
# \w matches the 63 characters [a-zA-Z0-9_] (most of the time)
#

my $UNSIGNED8BITS = qr/(?:25[0-5]|2[0-4]\d|[01]?\d\d?)/;         # (0-255)
my $ipv4_addr     = qr/(?:$UNSIGNED8BITS\.){3}$UNSIGNED8BITS/;
my $ipv6_addr     = qr/(?:[\: \.a-f0-9]+)/;
my $boolean		= qr/(?:true|false)/;

my $hostname = qr/[a-z][a-z0-9\-]{0,253}[a-z0-9]/;
my $zone     = qr/(?:$hostname\.)+[a-z]{2,}/;
my $vlan_tag = qr/\d{1,4}/;

my %format_re = (
	# hostname
	'hostname' => $hostname,

	# farms
	'farm_name' => qr/[a-zA-Z0-9\-]+/,
	'backend'   => qr/\d+/,
	#~ 'service'   => qr{\w+},
	'service' => qr/[a-zA-Z1-9\-]+/,
	#~ 'zone'      => qr{\w+},
	'zone' => qr/(?:$hostname\.)+[a-z]{2,}/,
	#~ 'zone' = qr/([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}/,
	#~ 'zone' = qr/[a-z0-9].*-*.*\.[a-z0-9].*/,
	'resource_id'   => qr/\d+/,
	'resource_name' => qr/(?:[a-zA-Z0-9\-\.\_]+|\@)/,
	'resource_ttl'  => qr/\d+/,                     # except zero
	'resource_type' => qr/(?:NS|A|AAAA|CNAME|DYNA|MX|SRV|TXT|PTR|NAPTR)/,
	'resource_data' => qr/.+/, # alow anything (becouse of TXT type)
	'resource_data_A' => $ipv4_addr, 
	'resource_data_AAAA' => $ipv6_addr, 
	'resource_data_NS' => qr/[a-zA-Z0-9\-]+/, 
	'resource_data_CNAME' => qr/[a-z\.]+/, 
	'resource_data_MX' => qr/[a-z\.]+/, 
	'resource_data_TXT' => qr/.+/, 			# all characters allow 
	'resource_data_SRV' => qr/[a-z0-9 \.]/, 
	'resource_data_PTR' => qr/[a-z\.]+/, 
	'resource_data_NAPTR' => qr/.+/,		# all characters allow
	#~ 'resource_data' => qr/(?:$hostname|$zone|$ipv4)/, # hostname or IP

	# interfaces ( WARNING: lenght in characters < 16 )
	'nic_interface'  => qr/[a-zA-Z0-9]{1,15}/,
	'bond_interface' => qr/[a-zA-Z0-9]{1,15}/,
	'vlan_interface' => qr/[a-zA-Z0-9]{1,13}\.$vlan_tag/,
	'virt_interface' => qr/[a-zA-Z0-9]{1,13}(?:\.[a-zA-Z0-9]{1,4})?:[a-zA-Z0-9]{1,13}/,
	'interface_type' => qr/(?:nic|vlan|virtual|bond)/,
	'vlan_tag' => qr/$vlan_tag/,

	# ipds
	'rbl_list_name' => qr/[a-zA-Z0-9]+/,
	'rbl_source'    => qr/(?:\d{1,3}\.){3}\d{1,3}(?:\/\d{1,2})?/,

	# certificates filenames
	'certificate' => qr/\w[\w\.-]*\.(?:pem|csr)/,
	'cert_pem'    => qr/\w[\w\.-]*\.pem/,
	'cert_csr'    => qr/\w[\w\.-]*\.csr/,
	'cert_dh2048' => qr/\w[\w\.-]*_dh2048\.pem/,

	# ips
	'IPv4_addr' => qr/$ipv4_addr/,
	'IPv4_mask' => qr/(?:$ipv4_addr|3[0-2]|[1-2][0-9]|[0-9])/,
	
	# farm guardian
	'fg_type' => qr/(?:http|https|l4xnat|gslb)/,
	'fg_enabled'  => $boolean,
	'fg_log'  => $boolean,
	'fg_time'  => qr/[1-9]\d*/,		# this value can't be 0
	
);

=begin nd
        Function: getValidFormat

        Validates a data format matching a value with a regular expression.
        If no value is passed as an argument the regular expression is returned.

        Usage:
			# validate exact data
			if ( ! &getValidFormat( "farm_name", $input_farmname ) ) {
				print "error";
			}

			# use the regular expression as a component for another regular expression 
			my $file_regex = &getValidFormat( "certificate" );
			if ( $file_path =~ /$configdir\/$file_regex/ ) { ... }

        Parameters:
				format_name	- type of format
				value		- value to be validated (optional)
				
        Returns:
				false	- If value failed to be validated
				true	- If value was successfuly validated
				regex	- If no value was passed to be matched

=cut
# &getValidFormat ( $format_name, $value );
sub getValidFormat
{
	my ( $format_name, $value ) = @_;

	#~ print "getValidFormat type:$format_name value:$value\n"; # DEBUG

	if ( exists $format_re{ $format_name } )
	{
		if ( defined $value )
		{
			#~ print "$format_re{ $format_name }\n"; # DEBUG
			return $value =~ /^$format_re{ $format_name }$/;
		}
		else
		{
			#~ print "$format_re{ $format_name }\n"; # DEBUG
			return $format_re{ $format_name };
		}
	}
	else
	{
		my $message = "getValidFormat: format $format_name not found.";
		&zenlog( $message );
		die ( $message );
	}
}

# validate port format and check if available when possible
sub getValidPort # ( $ip, $port, $profile )
{
	my $ip = shift; # mandatory for HTTP, GSLB or no profile
	my $port = shift;
	my $profile = shift; # farm profile, optional

	if ( $profile eq 'HTTP' || $profile eq 'GSLB' )
	{
		return &isValidPortNumber( $port ) eq 'true' && &checkport( $ip, $port ) eq 'false';
	}
	elsif ( $profile eq 'L4xNAT' )
	{
		return &ismport( $port ) eq 'true';
	}
	elsif ( $profile eq 'DATALINK' )
	{
		return $port eq undef;
	}
	elsif ( ! defined $profile )
	{
		return &isValidPortNumber( $port ) eq 'true' && &checkport( $ip, $port ) eq 'false';
	}
	else # profile not supported
	{
		return 0;
	}
}

1;
