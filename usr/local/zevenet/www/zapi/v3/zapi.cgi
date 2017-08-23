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

package GLOBAL {
	our $http_status_codes = {

		# 2xx Success codes
		200 => 'OK',
		201 => 'Created',
		204 => 'No Content',

		# 4xx Client Error codes
		400 => 'Bad Request',
		401 => 'Unauthorized',
		403 => 'Forbidden',
		404 => 'Not Found',
		406 => 'Not Acceptable',
		415 => 'Unsupported Media Type',
		422 => 'Unprocessable Entity',
	};
};

use Zevenet::Log;
use Zevenet::Debug;
use Zevenet::CGI;
use Zevenet::API3::HTTP;

my $q = &getCGI();


##### Debugging messages #############################################
#
#~ use Data::Dumper;
#
#~ if ( debug() )
#~ {
	#~ &zenlog( ">>>>>> CGI REQUEST: <$ENV{REQUEST_METHOD} $ENV{SCRIPT_URL}> <<<<<<" ) if &debug;
	#~ &zenlog( "HTTP HEADERS: " . join ( ', ', $q->http() ) );
	#~ &zenlog( "HTTP_AUTHORIZATION: <$ENV{HTTP_AUTHORIZATION}>" )
	#~ if exists $ENV{ HTTP_AUTHORIZATION };
	#~ &zenlog( "HTTP_ZAPI_KEY: <$ENV{HTTP_ZAPI_KEY}>" )
	#~ if exists $ENV{ HTTP_ZAPI_KEY };
	#~
	#~ #my $session = new CGI::Session( $q );
	#~
	#~ my $param_zapikey = $ENV{'HTTP_ZAPI_KEY'};
	#~ my $param_session = new CGI::Session( $q );
	#~
	#~ my $param_client = $q->param('client');
	#~
	#~
	#~ &zenlog("CGI PARAMS: " . Dumper $params );
	#~ &zenlog("CGI OBJECT: " . Dumper $q );
	#~ &zenlog("CGI VARS: " . Dumper $q->Vars() );
	#~ &zenlog("PERL ENV: " . Dumper \%ENV );
	#~
	#~
	#~ my $post_data = $q->param( 'POSTDATA' );
	#~ my $put_data  = $q->param( 'PUTDATA' );
	#~
	#~ &zenlog( "CGI POST DATA: " . $post_data ) if $post_data && &debug && $ENV{ CONTENT_TYPE } eq 'application/json';
	#~ &zenlog( "CGI PUT DATA: " . $put_data )   if $put_data && &debug && $ENV{ CONTENT_TYPE } eq 'application/json';
#~ }


##### OPTIONS method request #########################################
require Zevenet::API3::Routes::Options if ( $ENV{ REQUEST_METHOD } eq 'OPTIONS' );
#~ logNewModules("After OPTIONS");


##### Load more basic modules ########################################
require Zevenet::Config;
#~ logNewModules("With Zevenet::Config");
require Zevenet::Validate;
#~ logNewModules("With Zevenet::Validate");


##### Authentication #################################################
require Zevenet::API3::Auth;
#~ logNewModules("With Zevenet::API3::Auth");

# Session request
require Zevenet::API3::Routes::Session if ( $q->path_info eq '/session' );

# Verify authentication
unless (    ( exists $ENV{ HTTP_ZAPI_KEY } && &validZapiKey() )
		 or ( exists $ENV{ HTTP_COOKIE } && &validCGISession() ) )
{
	&httpResponse(
				   { code => 401, body => { message => 'Authorization required' } } );
}
#~ logNewModules("After authentication");


##### Load API routes ################################################
require Zevenet::API3::Routes;

&httpResponse(
			   {
				 code => 404,
				 body => {
						   message => 'Request not found',
						   error   => 'true',
				 }
			   }
);
