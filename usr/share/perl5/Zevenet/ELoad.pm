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

require Zevenet::Debug;

sub eload
{
	my %req = @_;

	my @required = ( qw(module func) );
	my @params   = ( qw(module func args just_ret ) );

	# check required params
	if ( my ( $required ) = grep { not exists $req{ $_ } } @required )
	{
		my $msg = "Required eload parameter '$required' missing";

		&zenlog( $msg );
		die( $msg );
	}

	use Carp qw(cluck);
	cluck "[eload]" if &debug() > 4; # warn with stack backtrace

	# check not used params
	if ( grep { not exists $req{ $_ } } @required )
	{
		my $params = join( ', ', @required );
		my $msg = "Warning: Detected unused eload parameter: $params";

		&zenlog( $msg );
	}

	# make sure $req{ args } is always an array reference
	my $validArrayRef = exists $req{ args } && ref $req{ args } eq 'ARRAY';
	$req{ args } = [] unless $validArrayRef;


	# Run directly Already running inside enterprise.bin
	if ( defined &main::include )
	{
		sub include;
		#~ &include( $req{ module } );

		include $req{ module };

		my $code_ref = \&{ $req{ func } };
		return $code_ref->( @{  $req{ args }  } );
	}

	my $zbin_path = '/usr/local/zevenet/bin';
	my $bin       = "$zbin_path/enterprise.bin";
	my $input;

	require JSON;
	JSON->import( qw( encode_json decode_json ) );

	unless ( ref( $req{ args } ) eq 'ARRAY' )
	{
		&zenlog("eload: ARGS is ARRAY ref: Failed!");
	}

	if ( exists $ENV{ PATH_INFO } && $ENV{ PATH_INFO } eq '/certificates/activation' )
	{
		# escape '\n' characters in activation certificate
		$req{ args }->[0] =~ s/\n/\\n/g;
	}

	unless ( eval { $input = encode_json( $req{ args } ) } )
	{
		my $msg = "eload: Error encoding JSON: $@";

		zenlog( $msg );
		die $msg;
	}

	my $cmd = "$bin $req{ module } $req{ func }";

	if ( &debug() )
	{
		&zenlog("eload: CMD: '$cmd'");
		&zenlog("eload: INPUT: '$input'") unless $input eq '[]';
	}

	my $ret_output;
	{
		local %ENV = %ENV;
		delete $ENV{ GATEWAY_INTERFACE };
		$ret_output = `echo -n '$input' | $cmd`;
	}
	my $rc = $?;

	chomp $ret_output;

	&zenlog( "enterprise.bin errno: '$rc'" );
	&zenlog( "$req{ module }::$req{ func } output: '$ret_output'" );

	if ( $rc )
	{
		my $msg = "Error loading enterprise module $req{ module }";
		chomp $ret_output;

		#~ zenlog( "rc: '$rc'" );
		#~ zenlog( "ret_output: '$ret_output'" );
		&zenlog( "$msg. $ret_output" );
		exit 1 if $0 =~ /zevenet$/; # finish zevenet process
		die( $msg );
	}

	# condition flags
	my $ret_f = exists $req{ just_ret } && $req{ just_ret };
	my $api_f = ( $req{ module } =~ /^Zevenet::API/ );

	my $output = ( not $ret_f && $api_f ) ?	decode_json( $ret_output ): $ret_output;
	my @output = eval{ @{ decode_json( $ret_output ) } };

	if ( $@ )
	{
		&zenlog( $@ );
		@output = undef;
	}

	use Data::Dumper;
	&zenlog( "eload $req{ module } $req{ func } output: " . Dumper \@output ) if @output;

	# return function output for non-API functions (service)
	if ( $ret_f || not $api_f )
	{
		return wantarray ? @output : shift @output;
	}

	&httpResponse( @output );
}

1;
