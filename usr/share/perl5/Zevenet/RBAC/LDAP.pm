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
use Zevenet::Core;
use Zevenet::Config;
include 'Zevenet::RBAC::Core';

my $ldap_file = &getRBACServicesConfPath();

=begin nd
Function: getLDAP

	Get the configuration to connect with the the LDAP server

Parameters:
	none - .

Returns:
	hash ref - the LDAP server settings. The list of parameters are:
		enabled, it indicates if the service is enabled (value 'true') or if it is not (value 'false')
		host, it is the LDAP URL or the server IP
		port, it is the port where the LDAP server is listening. This filed is skipt if the host is a URL or overwrite the port
	    binddn, it is the LDAP admin user used to modify manage. It is not necessary if the LDAP can be queried anonimously
	    bindpw, it is the password for the admin user
	    basedn, it is the base used to look for the user in the LDAP
	    filter, it is used to get an user based on some attribute
	    version, it is the LDAP version used by the server
	    scope, the search scope, can be base, one or sub, defaults to sub
        timeout, timeout of the query

=cut

sub getLDAP
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $ldap = &getTiny( $ldap_file );
	$ldap = $ldap->{ 'ldap' };

#~ my $ldap_host = "192.168.101.253";
#~ my $ldap_binddn = "cn=admin,dc=zevenet,dc=com";
#~ my $ldap_bindpwd = "admin";
#~ my $ldap_basedn = "dc=zevenet,dc=com";
#~ my $ldap_filter = '(&(objectClass=inetOrgPerson)(objectClass=posixAccount)(uid=%s))';

	# connection parameters
	$ldap->{ enabled } //= 'false';
	$ldap->{ host }    //= '';
	$ldap->{ port }    //= '389';
	$ldap->{ binddn }  //= '';
	$ldap->{ bindpw }  //= '';
	$ldap->{ version } //= 3;
	$ldap->{ timeout } //= 60;

	# search parameters
	$ldap->{ filter } //= '';
	$ldap->{ scope }  //= 'sub';
	$ldap->{ basedn } //= '';

	return $ldap;
}

=begin nd
Function: setLDAP

	Modify the LDAP configuration which is used to connect with the LDAP server

Parameters:
	hash ref - the LDAP server settings. The list of parameters are:
		enabled, it indicates if the service is enabled (value 'true') or if it is not (value 'false')
		host, it is the LDAP URL or the server IP
		port, it is the port where the LDAP server is listening. This filed is skipt if the host is a URL or overwrite the port
	    binddn, it is the LDAP admin user used to modify manage. It is not necessary if the LDAP can be queried anonimously
	    bindpw, it is the password for the admin user
	    basedn, it is the base used to look for the user in the LDAP
	    filter, it is used to get an user based on some attribute
	    version, it is the LDAP version used by the server
	    scope, the search scope, can be base, one or sub, defaults to sub
        timeout, timeout of the query

Returns:
	Integer - Error code. 0 on success or another value on failure

=cut

sub setLDAP
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $conf = shift;

	if ( exists $conf->{ bindpw } )
	{
		include 'Zevenet::Code';
		$conf->{ bindpw } = &getCodeEncode( $conf->{ bindpw } );
	}

	my $err = &setTinyObj( $ldap_file, 'ldap', $conf );
	return $err;
}

=begin nd
Function: bindLDAP

	It connects with the LDAP server if the LDAP configuration is completed.
	If the connection was successfully, the unbind ($ldap->unbind) must be done when the object will have no more use.

Parameters:
	none - .

Returns:
	Net::LDAP object - It retuns a Net::LDAP object if it was success,
					1 if LDAP service is disabled,
					2 if LDAP configuration is not complete,
					3 if cannot connect with server,
					4 if cannot bind with server.

=cut

sub bindLDAP
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $rc = 2;
	my $ldap;
	my $ldap_conf = &getLDAP();

	if ( $ldap_conf->{ enabled } ne 'true' )
	{
		&zenlog( "The LDAP service is disabled", 'debug', 'rbac' );
		return 1;
	}

	if ( $ldap_conf->{ host } )
	{
		require Net::LDAP;
		if (
			 $ldap = Net::LDAP->new(
									 $ldap_conf->{ host },
									 port    => $ldap_conf->{ port },
									 timeout => $ldap_conf->{ timeout },
									 version => $ldap_conf->{ version },
			 )
		  )
		{
			if ( $ldap_conf->{ binddn } )
			{

				my @bind_cfg = ( $ldap_conf->{ binddn } );
				if ( $ldap_conf->{ bindpw } )
				{
					include 'Zevenet::Code';
					my $pass = &getCodeDecode( $ldap_conf->{ bindpw } );
					push @bind_cfg, ( 'password' => $pass );
				}

				my $msg = $ldap->bind( @bind_cfg );
				if ( $msg->code )
				{
					$ldap->unbind();
					$rc = 4;
					&zenlog( "Error trying to bind with LDAP: " . $msg->code, 'warning', 'rbac' );
				}
				else
				{
					$rc = $ldap;
				}
			}
		}
		else
		{
			$rc = 3;
			&zenlog(
				"Error trying to connect with LDAP server $ldap_conf->{ host } : $ldap_conf->{ port }",
				'warning', 'rbac'
			);
		}
	}

	if ( $rc == 2 )
	{
		&zenlog( "The LDAP configuration is not complete", 'debug', 'rbac' );
	}

	return $rc;
}

=begin nd
Function: testLDAP

	Do a connection with the LDAP server to check the availability

Parameters:
	none - .

Returns:
	Integer - Returns 0 when the server is reachable and bind is succesful, 
		          1 on LDAP service disabled,
		          2 on configuration failure,
		          3 on connecting failure,
			  4 on connection succesful and bind failure

=cut

sub testLDAP
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $rc        = 0;
	my $ldap      = &bindLDAP();
	my $ldap_conf = &getLDAP();

	if ( ref ( $ldap ) eq 'Net::LDAP' )
	{
		$rc = 0;
		my $filter = $ldap_conf->{ filter };
		$filter =~ s/\%s/\*/g;
		my $result = $ldap->search(
									base   => $ldap_conf->{ basedn },
									filter => $filter,
									scope  => 'base',
									attrs  => ['1.1']
		);
		$ldap->unbind();

		# LDAP_REFERRAL (10)
		# LDAP_NO_SUCH_OBJECT (32)
		# LDAP_INVALID_DN_SYNTAX (34)
		# LDAP_FILTER_ERROR (87)
		# LDAP_PARAM_ERROR (89)
		my $error_code = $result->code;
		if ( $error_code == 32 or $error_code == 10 )
		{
			$rc = 5;
			&zenlog( "The BaseDN is not valid", "debug", "rbac" );
			return $rc;
		}
		if ( $error_code == 87 or $error_code == 89 )
		{
			$rc = 6;
			&zenlog( "The search Filter is not valid", "debug", "rbac" );
			return $rc;
		}
		&zenlog( "The load balancer can access to the LDAP service", "debug", "rbac" );
	}
	else
	{
		$rc = $ldap;
	}

	return $rc;
}

=begin nd
Function: authLDAP

	Authenticate a user against a LDAP server

Parameters:
	User - User name
	Password - User password

Returns:
	Integer - Return 1 if the user was properly validated or another value if it failed

=cut

sub authLDAP
{
	my ( $user, $pass ) = @_;
	my $suc       = 0;
	my $ldap_conf = &getLDAP();
	delete $ldap_conf->{ filter } if ( $ldap_conf->{ filter } eq '' );

	if ( &getRBACServiceEnabled( 'ldap' ) eq 'true' )
	{
		delete $ldap_conf->{ enabled };
		require Authen::Simple::LDAP;
		eval {

			include 'Zevenet::Code';
			$ldap_conf->{ bindpw } = &getCodeDecode( $ldap_conf->{ bindpw } )
			  if ( defined $ldap_conf->{ bindpw } );

			my $ldap = Authen::Simple::LDAP->new( $ldap_conf );
			if ( $ldap->authenticate( $user, $pass ) )
			{
				&zenlog( "The user '$user' login with ldap auth service", "debug", "auth" );
				$suc = 1;
			}
		};
		if ( $@ )
		{
			$suc = 0;
			&zenlog( "The load balancer cannot run the LDAP query: $@", "debug", "rbac" );
		}
	}
	else
	{
		$suc = 0;
		&zenlog( "LDAP Authentication Service is not active", "debug", "rbac" );
	}

	return $suc;
}

=begin nd
Function: getLDAPUserExists

	It checks if the user exists in the LDAP remote server. It used when the user do not need authentication, it using the ZAPI key.
	Before, the ldap setting is checked (using function bindLDAP).

Parameters:
	User - User name

Returns:
	Integer - Return 1 if the user exists or 0 if it does not.

=cut

sub getLDAPUserExists
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $user  = shift;
	my $exist = 0;

	my $ldap = &bindLDAP();

	if ( ref ( $ldap ) eq 'Net::LDAP' )
	{
		my $ldap_conf = &getLDAP();

		# add filter:
		my $filter = $ldap_conf->{ filter };

		# setting the default value of the Auth::LDAP::simple module
		$filter = '(uid=%s)' if ( $filter eq '' );
		$filter =~ s/\%s/$user/g;

		my $result = $ldap->search(
									base   => $ldap_conf->{ basedn },
									scope  => $ldap_conf->{ scope },
									filter => $filter,
		);

		if ( $result->count == 1 )
		{
			&zenlog( "The '$user' was found successfully", "debug", "RBAC" );
			$exist = 1;
		}
		elsif ( $result->count > 1 )
		{
			&zenlog( "More than a entry '$user' was found in LDAP service",
					 "warning", "RBAC" );
		}
		else
		{
			&zenlog( "The '$user' user was not found in LDAP service", "warning", "RBAC" );
		}
		$ldap->unbind();
	}

	return $exist;
}

1;
