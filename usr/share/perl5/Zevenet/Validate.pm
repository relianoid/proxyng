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
use Regexp::IPv6 qw($IPv6_re);

# Notes about regular expressions:
#
# \w matches the 63 characters [a-zA-Z0-9_] (most of the time)
#

my $UNSIGNED8BITS = qr/(?:25[0-5]|2[0-4]\d|[01]?\d\d?)/;           # (0-255)
my $UNSIGNED7BITS = qr/(?:[0-9]{1,2}|10[0-9]|11[0-9]|12[0-8])/;    # (0-128)
my $ipv6_word     = qr/(?:[A-Fa-f0-9]+){1,4}/;
my $ipv4_addr     = qr/(?:$UNSIGNED8BITS\.){3}$UNSIGNED8BITS/;
my $ipv6_addr     = $IPv6_re;
my $ipv4v6        = qr/(?:$ipv4_addr|$ipv6_addr)/;
my $boolean       = qr/(?:true|false)/;
my $enable        = qr/(?:enable|disable)/;
my $integer       = qr/\d+/;
my $natural = qr/[1-9]\d*/;    # natural number = {1, 2, 3, ...}
my $weekdays = qr/(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)/;
my $minutes  = qr/(?:\d|[0-5]\d)/;
my $hours    = qr/(?:\d|[0-1]\d|2[0-3])/;
my $months   = qr/(?:[1-9]|1[0-2])/;
my $dayofmonth = qr/(?:[1-9]|[1-2]\d|3[01])/;    # day of month

my $hostname = qr/[a-z][a-z0-9\-]{0,253}[a-z0-9]/;
my $service  = qr/[a-zA-Z0-9][a-zA-Z0-9_\-\.]*/;
my $zone     = qr/(?:$hostname\.)+[a-z]{2,}/;

my $vlan_tag    = qr/\d{1,4}/;
my $virtual_tag = qr/[a-zA-Z0-9\-]{1,13}/;
my $nic_if      = qr/[a-zA-Z0-9\-]{1,15}/;
my $bond_if     = qr/[a-zA-Z0-9\-]{1,15}/;
my $vlan_if     = qr/[a-zA-Z0-9\-]{1,13}\.$vlan_tag/;
my $interface   = qr/$nic_if(?:\.$vlan_tag)?(?:\:$virtual_tag)?/;
my $port_range =
  qr/(?:[1-5]?\d{1,4}|6[0-4]\d{3}|65[1-4]\d{2}|655[1-2]\d{1}|6553[1-5])/;
my $graphsFrequency = qr/(?:daily|weekly|monthly|yearly)/;

#~ my $dos_global= qr/(?:sshbruteforce|dropicmp)/;		# Next version
my $dos_global = qr/(?:sshbruteforce)/;
my $dos_all    = qr/(?:limitconns|limitsec)/;
my $dos_tcp    = qr/(?:bogustcpflags|limitrst)/;

my $run_actions = qr/^(?:stop|start|restart)$/;

my %format_re = (

	# generic types
	'integer'     => $integer,
	'natural_num' => $natural,
	'boolean'     => $boolean,

	# hostname
	'hostname' => $hostname,

	# license
	'license_format' => qr/(?:txt|html)/,

	# log
	'log' => qr/[\.\-\w]+/,

	#zapi
	'zapi_key'      => qr/[a-zA-Z0-9]+/,
	'zapi_status'   => $enable,
	'zapi_password' => qr/.+/,

	# common
	'port'     => $port_range,
	'user'     => qr/[\w]+/,
	'password' => qr/.+/,

	# system
	'dns_nameserver' => $ipv4v6,
	'dns'            => qr/(?:primary|secondary)/,
	'ssh_port'       => $port_range,
	'ssh_listen'     => qr/(?:$ipv4v6|\*)/,
	'snmp_status'    => $boolean,
	'snmp_ip'        => qr/(?:$ipv4v6|\*)/,
	'snmp_port'      => $port_range,
	'snmp_community' => qr{[\w]+},
	'snmp_scope'     => qr{(?:\d{1,3}\.){3}\d{1,3}\/\d{1,2}},    # ip/mask
	'ntp'            => qr{[\w\.\-]+},

	# farms
	'farm_name'             => qr/[a-zA-Z0-9\-]+/,
	'farm_profile'          => qr/HTTP|GSLB|L4XNAT|DATALINK/,
	'backend'               => qr/\d+/,
	'service'               => $service,
	'gslb_service'          => qr/[a-zA-Z0-9][\w\-]*/,
	'farm_modules'          => qr/(?:gslb|dslb|lslb)/,
	'service_position'      => qr/\d+/,
	'farm_maintenance_mode' => qr/(?:drain|cut)/,

	# cipher
	'ciphers' => qr/(?:all|highsecurity|customsecurity|ssloffloading)/,

	# backup
	'backup'        => qr/[\w-]+/,
	'backup_action' => qr/apply/,

	# graphs
	'graphs_frequency' => $graphsFrequency,
	'graphs_system_id' => qr/(?:cpu|load|ram|swap)/,
	'mount_point'      => qr/root[\w\-\.\/]*/,

	# http
	'redirect_code'    => qr/(?:301|302|307)/,
	'http_sts_status'  => qr/(?:true|false)/,
	'http_sts_timeout' => qr/(?:\d+)/,

	# GSLB
	'zone'          => qr/(?:$hostname\.)+[a-z]{2,}/,
	'resource_id'   => qr/\d+/,
	'resource_name' => qr/(?:[\w\-\.]+|\@)/,
	'resource_ttl'  => qr/$natural/,                    # except zero
	'resource_type' => qr/(?:NS|A|AAAA|CNAME|DYNA|MX|SRV|TXT|PTR|NAPTR)/,
	'resource_data'      => qr/.+/,            # alow anything (because of TXT type)
	'resource_data_A'    => $ipv4_addr,
	'resource_data_AAAA' => $ipv6_addr,
	'resource_data_DYNA' => $service,
	'resource_data_NS'   => qr/[a-zA-Z0-9\-]+/,
	'resource_data_CNAME' => qr/[a-z\.]+/,
	'resource_data_MX'    => qr/[a-z\.\ 0-9]+/,
	'resource_data_TXT'   => qr/.+/,              # all characters allow
	'resource_data_SRV'   => qr/[a-z0-9 \.]/,
	'resource_data_PTR'   => qr/[a-z\.]+/,
	'resource_data_NAPTR' => qr/.+/,              # all characters allow

	# interfaces ( WARNING: length in characters < 16  )
	'nic_interface'    => $nic_if,
	'bond_interface'   => $bond_if,
	'vlan_interface'   => $vlan_if,
	'virt_interface'   => qr/(?:$bond_if|$nic_if)(?:\.$vlan_tag)?:$virtual_tag/,
	'routed_interface' => qr/(?:$nic_if|$bond_if|$vlan_if)/,
	'interface_type'   => qr/(?:nic|vlan|virtual|bond)/,
	'vlan_tag'         => qr/$vlan_tag/,
	'virtual_tag'      => qr/$virtual_tag/,
	'bond_mode_num'    => qr/[0-6]/,
	'bond_mode_short' =>
	  qr/(?:balance-rr|active-backup|balance-xor|broadcast|802.3ad|balance-tlb|balance-alb)/,

	# notifications
	'notif_alert'  => qr/(?:backends|cluster)/,
	'notif_method' => qr/(?:email)/,
	'notif_tls'    => $boolean,
	'notif_action' => $enable,
	'notif_time'   => $natural,                   # this value can't be 0

	# IPDS
	# blacklists
	'day_of_month'              => qr{$dayofmonth},
	'weekdays'                  => qr{$weekdays},
	'blacklists_name'           => qr{\w+},
	'blacklists_source'         => qr{(?:\d{1,3}\.){3}\d{1,3}(?:\/\d{1,2})?},
	'blacklists_source_id'      => qr{\d+},
	'blacklists_type'           => qr{(?:local|remote)},
	'blacklists_policy'         => qr{(?:allow|deny)},
	'blacklists_url'            => qr{.+},
	'blacklists_hour'           => $hours,
	'blacklists_minutes'        => $minutes,
	'blacklists_period'         => $natural,
	'blacklists_unit'           => qr{(:?hours|minutes)},
	'blacklists_day'            => qr{(:?$dayofmonth|$weekdays)},
	'blacklists_frequency'      => qr{(:?daily|weekly|monthly)},
	'blacklists_frequency_type' => qr{(:?period|exact)},

	# DoS
	'dos_name'        => qr/[\w]+/,
	'dos_rule'        => qr/(?:$dos_global|$dos_all|$dos_tcp)/,
	'dos_rule_farm'   => qr/(?:$dos_all|$dos_tcp)/,
	'dos_rule_global' => $dos_global,
	'dos_rule_all'    => $dos_all,
	'dos_rule_tcp'    => $dos_tcp,
	'dos_time'        => $natural,
	'dos_limit_conns' => $natural,
	'dos_limit'       => $natural,
	'dos_limit_burst' => $natural,
	'dos_status'      => qr/(?:down|up)/,
	'dos_port'        => $port_range,
	'dos_hits'        => $natural,

	# RBL
	'rbl_name'          => qr/[\w]+/,
	'rbl_domain'        => qr/[\w\.\-]+/,
	'rbl_log_level'     => qr/[0-7]/,
	'rbl_only_logging'  => $boolean,
	'rbl_cache_size'    => $natural,
	'rbl_cache_time'    => $natural,
	'rbl_queue_size'    => $natural,
	'rbl_thread_max'    => $natural,
	'rbl_local_traffic' => $boolean,
	'rbl_actions'       => $run_actions,

	# WAF
	'http_code'      => qr/[0-9]{3}/,
	'waf_set_name'   => qr/[\.\w-]+/,
	'waf_rule_id'    => qr/\d+/,
	'waf_chain_id'   => qr/\d+/,
	'waf_severity'   => qr/[0-9]/,
	'waf_phase'      => qr/(?:[1-5]|request|response|logging)/,
	'waf_log'        => qr/(?:$boolean|)/,
	'waf_audit_log'  => qr/(?:$boolean|)/,
	'waf_skip'       => qr/[0-9]+/,
	'waf_skip_after' => qr/\w+/,
	'waf_action'     => qr/(?:allow|block|redirect|pass|deny)/,
	'waf_set_status' => qr/(?:$boolean|detection)/,

	# certificates filenames
	'certificate' => qr/\w[\w\.\(\)\@ \-]*\.(?:pem|csr)/,
	'cert_pem'    => qr/\w[\w\.\(\)\@ \-]*\.pem/,
	'cert_csr'    => qr/\w[\w\.\-]*\.csr/,
	'cert_dh2048' => qr/\w[\w\.\-]*_dh2048\.pem/,

	# IPS
	'IPv4_addr' => qr/$ipv4_addr/,
	'IPv4_mask' => qr/(?:$ipv4_addr|3[0-2]|[1-2][0-9]|[0-9])/,

	'IPv6_addr' => qr/$ipv6_addr/,
	'IPv6_mask' => $UNSIGNED7BITS,

	'ip_addr' => $ipv4v6,
	'ip_mask' => qr/(?:$ipv4_addr|$UNSIGNED7BITS)/,

	# farm guardian
	'fg_name'    => qr/[\w-]+/,
	'fg_type'    => qr/(?:http|https|l4xnat|gslb)/,
	'fg_enabled' => $boolean,
	'fg_log'     => $boolean,
	'fg_time'    => qr/$natural/,                     # this value can't be 0

	# RBAC
	'user_name'     => qr/[a-z][-a-z0-9_]+/,
	'rbac_password' => qr/(?=.*[0-9])(?=.*[a-zA-Z]).{8,16}/,
	'group_name'    => qr/[\w-]+/,
	'role_name'     => qr/[\w-]+/,

	# alias
	'alias_id'        => qr/(?:$ipv4v6|$interface)/,
	'alias_backend'   => qr/$ipv4v6/,
	'alias_interface' => qr/$interface/,
	'alias_name'      => qr/[\w-]+/,
	'alias_type'      => qr/(?:backend|interface)/,

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

See also:
	Mainly but not exclusively used in zapi v3.
=cut

# &getValidFormat ( $format_name, $value );
sub getValidFormat
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
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

=begin nd
Function: getValidPort

	Validate port format and check if available when possible.

Parameters:
	ip - IP address.
	port - Port number.
	profile - Farm profile (HTTP, L4XNAT, GSLB or DATALINK). Optional.

Returns:
	Boolean - TRUE for a valid port number, FALSE otherwise.

Bugs:

See Also:
	zapi/v3/post.cgi
=cut

sub getValidPort    # ( $ip, $port, $profile )
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $ip      = shift;    # mandatory for HTTP, GSLB or no profile
	my $port    = shift;
	my $profile = shift;    # farm profile, optional

	#~ &zenlog("getValidPort( ip:$ip, port:$port, profile:$profile )");# if &debug;
	require Zevenet::Net::Validate;
	if ( $profile =~ /^(?:HTTP|GSLB)$/i )
	{
		return &isValidPortNumber( $port ) eq 'true'
		  && &checkport( $ip, $port ) eq 'false';
	}
	elsif ( $profile =~ /^(?:L4XNAT)$/i )
	{
		require Zevenet::Farm::L4xNAT::Validate;
		return &ismport( $port ) eq 'true';
	}
	elsif ( $profile =~ /^(?:DATALINK)$/i )
	{
		return $port eq undef;
	}
	elsif ( !defined $profile )
	{
		return &isValidPortNumber( $port ) eq 'true'
		  && &checkport( $ip, $port ) eq 'false';
	}
	else    # profile not supported
	{
		return 0;
	}
}

=begin nd
Function: getValidOptParams

	Check parameters when all params are optional

	Before called:	getValidPutParams

Parameters:
	\%json_obj - .
	\@allowParams - .

Returns:
	none - .

Bugs:

See Also:

=cut

sub getValidOptParams    # ( \%json_obj, \@allowParams )
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $params         = shift;
	my $allowParamsRef = shift;
	my @allowParams    = @{ $allowParamsRef };
	my $output;
	my $pattern;

	if ( !keys %{ $params } )
	{
		return "Not found any param.";
	}

	# Check if any param isn't for this call
	$pattern .= "$_|" for ( @allowParams );
	chop ( $pattern );
	my @errorParams = grep { !/^(?:$pattern)$/ } keys %{ $params };
	if ( @errorParams )
	{
		$output .= "$_, " for ( @errorParams );
		chop ( $output );
		chop ( $output );
		$output = "Illegal params: $output";
	}

	return $output;
}

=begin nd
Function: getValidReqParams

	Check parameters when there are required params

	Before called:	getValidPostParams

Parameters:
	\%json_obj - .
	\@requiredParams - .
	\@optionalParams - .

Returns:
	none - .

Bugs:

See Also:

=cut

sub getValidReqParams    # ( \%json_obj, \@requiredParams, \@optionalParams )
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $params            = shift;
	my $requiredParamsRef = shift;
	my $allowParamsRef    = shift || [];
	my @requiredParams    = @{ $requiredParamsRef };
	my @allowParams;
	@allowParams = @{ $allowParamsRef } if ( $allowParamsRef );
	push @allowParams, @requiredParams;
	my $output;
	my $pattern;

	# Check all required params are in called
	$pattern .= "$_|" for ( @requiredParams );

	chop ( $pattern );
	my $aux = grep { /^(?:$pattern)$/ } keys %{ $params };
	if ( $aux != scalar @requiredParams )
	{
		$aux    = scalar @requiredParams - $aux;
		$output = "Missing required parameters. Parameters missed: $aux.";
	}

	# Check if any param isn't for this call
	if ( !$output )
	{
		$output  = "";
		$pattern = "";
		$pattern .= "$_|" for ( @allowParams );
		chop ( $pattern );
		my @errorParams = grep { !/^(?:$pattern)$/ } keys %{ $params };
		if ( @errorParams )
		{
			$output .= "$_, " for ( @errorParams );
			chop ( $output );
			chop ( $output );
			$output = "Illegal params: $output";
		}
	}

	return $output;
}

=begin nd
Function: checkZAPIParams

	Function to check parameters of a PUT or POST call.
	It check a list of parameters, and apply it some checks:
	- Almost 1 parameter
	- All required parameters must exist
	- All required parameters are correct

	Also, it checks: getValidFormat funcion, if black is allowed, intervals, aditionals regex, excepts regex and a list with the possbile values

	It is possible add a error message with the correct format. For example: $parameter . "must have letters and digits"


Parameters:
	Json_obj - Parameters sent in a POST or PUT call
	Parameters - Hash of parameter objects

	parameter object:
	{
		parameter :
		{		# parameter is the key or parameter name
			"required" 	: "true",		# or not defined
			"non_blank" : "true",		# or not defined
			"interval" 	: "1,65535",	# it is possible define strings matchs ( non implement). For example: "ports" = "1-65535", "log_level":"1-3", ...
										# ",10" indicates that the value has to be less than 10 but without low limit
										# "10," indicates that the value has to be more than 10 but without high limit
			"exceptions"	: [ "zapi", "webgui", "root" ],	# The parameter can't have got any of the listed values
			"values" : ["priority", "weight"],		# list of possible values for a parameter
			"regex"	: "/\w+,\d+/",		# regex format
			"valid_format"	: "farmname",		# regex stored in Validate.pm file, it checks with the function getValidFormat
			"function" : \&func,		# function of validating, the input parameter is the value of the argument. The function has to return 0 or 'false' when a error exists
			"format_msg"	: "must have letters and digits",	# used message when a value is not correct
		}
		param2 :
		{
			...
		}
		....
	}


Returns:
	String - Return a error message with the first error found or undef on success

=cut

sub checkZAPIParams
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $json_obj  = shift;
	my $param_obj = shift;

	my @rec_keys      = keys %{ $json_obj };
	my @expect_params = keys %{ $param_obj };

	# Almost 1 parameter
	return "At least a parameters is expected." if ( !keys %{ $json_obj } );

	# All required parameters must exist
	my @miss_params;

	foreach my $param ( @expect_params )
	{
		next if ( !exists $param_obj->{ $param }->{ 'required' } );
		if ( $param_obj->{ $param }->{ 'required' } eq 'true' )
		{
			push @miss_params, $param if ( !grep ( /^$param$/, keys %{ $json_obj } ) );
		}
	}
	return
	  &putArrayAsText( \@miss_params,
				   "The required parameter<sp>s</sp> <pl> <bs>is<|>are</bp> missing." )
	  if ( @miss_params );

	# All sent parameters are correct
	my @non_valid;
	foreach my $param ( @rec_keys )
	{
		push @non_valid, $param if ( !grep ( /^$param$/, keys %{ $param_obj } ) );
	}
	return
	  &putArrayAsText( \@non_valid,
		"The parameter<sp>s</sp> <pl> <bs>is<|>are</bp> not correct for this call. Please, try with: "
		  . join ( ', ', @expect_params ) )
	  if ( @non_valid );

	# check for each parameter
	foreach my $param ( @rec_keys )
	{
		# if blank value is allowed
		if ( $param_obj->{ $param }->{ 'non_blank' } eq 'true' )
		{
			return "The parameter $param can't be in blank."
			  if ( $json_obj->{ $param } eq '' );
		}

		if ( exists $param_obj->{ $param }->{ 'values' } )
		{
			return "The parameter $param expects once of the following values: "
			  . join ( ', ', @{ $param_obj->{ $param }->{ 'values' } } )
			  if (
				  !grep ( /^$json_obj->{ $param }$/, @{ $param_obj->{ $param }->{ 'values' } } )
			  );
		}

		# getValidFormat funcion:
		if ( exists $param_obj->{ $param }->{ 'valid_format' } )
		{
			if (
				 !&getValidFormat(
								   $param_obj->{ $param }->{ 'valid_format' },
								   $json_obj->{ $param }
				 )
			  )
			{

				if ( exists $param_obj->{ $param }->{ format_msg } )
				{
					return "$param $param_obj->{ $param }->{ format_msg }";
				}
				else
				{
					return "The parameter $param has not a valid value.";
				}
			}
		}

		# intervals
		if ( exists $param_obj->{ $param }->{ 'interval' } )
		{
			if ( $param_obj->{ $param }->{ 'interval' } =~ /,/ )
			{
				my ( $low_limit, $high_limit ) =
				  split ( ',', $param_obj->{ $param }->{ 'interval' } );
				my $low_str =
				  ( $low_limit ) ? "$param has to be greater than or equal to $low_limit" : "";
				my $high_str =
				  ( $high_limit ) ? "$param has to be lower than or equal to $high_limit" : "";
				my $msg = $low_str if $low_str;

				if ( $high_str )
				{
					$msg .= ". " if $msg;
					$msg .= $high_str;
				}
				return $msg
				  if (    ( $json_obj->{ $param } !~ /^\d*$/ )
					   || ( $json_obj->{ $param } > $high_limit )
					   || ( $json_obj->{ $param } > $high_limit ) );
			}
			else
			{
				die "Expected a interval string, got: $param_obj->{ $param }->{ 'interval' }";
			}
		}

		# exceptions
		if ( exists $param_obj->{ $param }->{ 'exceptions' } )
		{
			return
			  "The value $json_obj->{ $param } is a reserved word of the parameter $param."
			  if (
				   grep ( /^$json_obj->{ $param }$/,
						  @{ $param_obj->{ $param }->{ 'exceptions' } } ) );
		}

		# aditionals

		# regex
		if ( exists $param_obj->{ $param }->{ 'regex' } )
		{
			return "The value $json_obj->{ $param } is not valid for the parameter $param."
			  if ( $json_obj->{ $param } !~ /$param_obj->{ $param }->{ 'regex' }/ );
		}

		if ( exists $param_obj->{ $param }->{ 'function' } )
		{
			my $result =
			  &{ $param_obj->{ $param }->{ 'function' } }( $json_obj->{ $param } );
			if ( !$result or $result eq 'false' )
			{
				if ( exists $param_obj->{ $param }->{ format_msg } )
				{
					return "$param $param_obj->{ $param }->{ format_msg }";
				}
				else
				{
					return "The parameter $param has not a valid value.";
				}
			}
		}
	}

	return;
}

=begin nd
Function: putArrayAsText

	This funcion receives a text string and a list of values and it generates a
	text with the values.

	It uses a delimited to modify the text string passed as argument:
	put list - <pl>
	select plural - <sp>text</sp>
	select single - <ss>text</ss>
	select between single or plural - <bs>text_single<|>text_plural</bp>

	Examples:
		putArrayAsText ( ["password", "user", "key"], "The possible value<sp>s</sp> <sp>are</sp>: <pl>")
			return: ""
		putArrayAsText ( ["", "", ""], "The values are")
			return: ""


Parameters:
	Parameters - List of parameters to add to the string message
	Text string - Text

Returns:
	String - Return a message adjust to the number of parameters passed

=cut

sub putArrayAsText
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $array_ref = shift;
	my $msg       = shift;
	my @array     = @{ $array_ref };

	# one element
	if ( scalar @array eq 1 )
	{
		# save single tags
		$msg =~ s/<\/?ss>//g;

		# remove plural text
		#~ $msg =~ s/<sp>.+<\/?sp>// while ( $msg =~ /<sp>/ );
		$msg =~ s/<sp>.+<\/?sp>//g;

		# select between plural and single text
		#~ $msg =~ s/<bs>(.+)<|>.+<\/bp>/$1/ while ( $msg =~ /<|>/ );
		$msg =~ s/<bs>(.+)<\|>.+<\/bp>/$1/g;

		# put list
		$msg =~ s/<pl>/$array[0]/;
	}

	# more than one element
	else
	{
		# save plual tags
		$msg =~ s/<\/?sp>//g;

		# remove single text
		#~ $msg =~ s/<ss>.+<\/?ss>// while ( $msg =~ /<ss>/ );
		$msg =~ s/<ss>.+<\/?ss>//g;

		# select between plural and single text
		#~ $msg =~ s/<bs>.+<|>(.+)<\/bp>/$1/ while ( $msg =~ /<|>/ );
		$msg =~ s/<bs>.+<\|>(.+)<\/bp>/$1/g;

		my $lastItem = pop @array;
		my $list = join ( ', ', @array );
		$list .= " and $lastItem";

		# put list
		$msg =~ s/<pl>/$list/;
	}

	return $msg;
}

1;
