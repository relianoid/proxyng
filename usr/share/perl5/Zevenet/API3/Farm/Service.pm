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

use Zevenet::Farm::Core;


# POST

sub new_farm_service    # ( $json_obj, $farmname )
{
	my $json_obj = shift;
	my $farmname = shift;

	# Check that the farm exists
	if ( &getFarmFile( $farmname ) == -1 )
	{
		# Error
		my $errormsg = "The farmname $farmname does not exists.";

		my $body = {
					 description => "New service",
					 error       => "true",
					 message     => $errormsg
		};

		&httpResponse( { code => 404, body => $body } );
	}

	my $type = &getFarmType( $farmname );

	if ( $type eq "http" || $type eq "https" )
	{
		require Zevenet::Farm::HTTP::Service;

		if ( $json_obj->{ id } =~ /^$/ )
		{
			&zenlog(
				"ZAPI error, trying to create a new service in farm $farmname, invalid service name."
			);

			# Error
			my $errormsg = "Invalid service, please insert a valid value.";

			my $body = {
						 description => "New service",
						 error       => "true",
						 message     => $errormsg
			};

			&httpResponse( { code => 400, body => $body } );
		}

		my $result = &setFarmHTTPNewService( $farmname, $json_obj->{ id } );

		if ( $result eq "0" )
		{
			&zenlog(
				"ZAPI success, a new service has been created in farm $farmname with id $json_obj->{id}."
			);

			# Success
			my $body = {
						 description => "New service " . $json_obj->{ id },
						 params      => { id => $json_obj->{ id } },
			};

			require Zevenet::Farm::Base;

			if ( &getFarmStatus( $farmname ) eq 'up' )
			{
				require Zevenet::Farm::Action;
				&setFarmRestart( $farmname );
				$body->{ status } = 'needed restart';
			}

			&httpResponse( { code => 201, body => $body } );
		}
		if ( $result eq "2" )
		{
			&zenlog(
				"ZAPI error, trying to create a new service in farm $farmname, new service $json_obj->{id} can't be empty."
			);

			# Error
			my $errormsg = "New service can't be empty.";
			my $body = {
						 description => "New service " . $json_obj->{ id },
						 error       => "true",
						 message     => $errormsg
			};

			&httpResponse( { code => 400, body => $body } );
		}
		if ( $result eq "1" )
		{
			&zenlog(
				"ZAPI error, trying to create a new service in farm $farmname, the service $json_obj->{id} already exists."
			);

			# Error
			my $errormsg = "Service named " . $json_obj->{ id } . " already exists.";
			my $body = {
						 description => "New service " . $json_obj->{ id },
						 error       => "true",
						 message     => $errormsg
			};

			&httpResponse( { code => 400, body => $body } );
		}
		if ( $result eq "3" )
		{
			&zenlog(
				"ZAPI error, trying to create a new service in farm $farmname, the service name $json_obj->{id} is not valid, only allowed numbers,letters and hyphens."
			);

			# Error
			my $errormsg =
			  "Service name is not valid, only allowed numbers, letters and hyphens.";
			my $body = {
						 description => "New service " . $json_obj->{ id },
						 error       => "true",
						 message     => $errormsg
			};

			&httpResponse( { code => 400, body => $body } );
		}
	}

	if ( $type eq "gslb" )
	{
		require Zevenet::Farm::GSLB::Service;

		if ( $json_obj->{ id } =~ /^$/ )
		{
			&zenlog(
				"ZAPI error, trying to create a new service in farm $farmname, invalid service name."
			);

			# Error
			my $errormsg = "Invalid service, please insert a valid value.";
			my $body = {
						 description => "New service " . $json_obj->{ id },
						 error       => "true",
						 message     => $errormsg
			};

			&httpResponse( { code => 400, body => $body } );
		}

		if ( $json_obj->{ algorithm } =~ /^$/ )
		{
			&zenlog(
				"ZAPI error, trying to create a new service in farm $farmname, invalid algorithm."
			);

			# Error
			my $errormsg = "Invalid algorithm, please insert a valid value.";
			my $body = {
						 description => "New service " . $json_obj->{ id },
						 error       => "true",
						 message     => $errormsg
			};

			&httpResponse( { code => 400, body => $body } );
		}

		my $status = &setGSLBFarmNewService( $farmname,
											 $json_obj->{ id },
											 $json_obj->{ algorithm } );
		if ( $status != -1 )
		{
			&zenlog(
				"ZAPI success, a new service has been created in farm $farmname with id $json_obj->{id}."
			);

			# Success
			my $body = {
						 description => "New service " . $json_obj->{ id },
						 params      => {
									 id        => $json_obj->{ id },
									 algorithm => $json_obj->{ algorithm }
						 },
			};

			require Zevenet::Farm::Base;

			if ( &getFarmStatus( $farmname ) eq 'up' )
			{
				require Zevenet::Farm::Action;

				&setFarmRestart( $farmname );
				$body->{ status } = 'needed restart';
			}

			&httpResponse( { code => 201, body => $body } );
		}
		else
		{
			&zenlog(
				"ZAPI error, trying to create a new service in farm $farmname, it's not possible to create the service $json_obj->{id}."
			);

			# Error
			my $errormsg = "It's not possible to create the service " . $json_obj->{ id };
			my $body = {
						 description => "New service " . $json_obj->{ id },
						 error       => "true",
						 message     => $errormsg
			};

			&httpResponse( { code => 400, body => $body } );
		}
	}
}

# GET

#GET /farms/<name>/services/<service>
sub farm_services
{
	my ( $farmname, $servicename ) = @_;

	my $service;
	my $description = "Get services of a farm";

	# Check that the farm exists
	if ( &getFarmFile( $farmname ) eq '-1' )
	{
		# Error
		my $errormsg = "The farmname $farmname does not exist.";
		my $body = {
				description => $description,
				error => "true",
				message => $errormsg
		};

		&httpResponse({ code => 404, body => $body });
	}

	my $type = &getFarmType( $farmname );
	if ( $type !~ /http/i )
	{
		# Error
		my $errormsg = "This functionality only is available for HTTP farms.";
		my $body = {
				description => $description,
				error => "true",
				message => $errormsg
		};

		&httpResponse({ code => 400, body => $body });
	}

	require Zevenet::Farm::HTTP::Service;
	my @services = &getHTTPFarmServices( $farmname );
	if ( ! grep ( /^$servicename$/, @services ) )
	{
		# Error
		my $errormsg = "The required service does not exist.";
		my $body = {
				description => $description,
				error => "true",
				message => $errormsg
		};

		&httpResponse({ code => 404, body => $body });
	}

	require Zevenet::Farm::Config;
	$service = &getServiceStruct ( $farmname, $servicename );
	foreach my $be ( @{ $service->{backends} } )
	{
		$be->{status} = "up" if $be->{status} eq "undefined";
	}


	# Success
	my $body = {
				 description => $description,
				 services    	=> $service,
	};

	&httpResponse({ code => 200, body => $body });
}

# PUT

sub modify_services # ( $json_obj, $farmname, $service )
{
	my ( $json_obj, $farmname, $service ) = @_;

	my $output_params;
	my $description = "Modify service";
	my $errormsg;

	# validate FARM NAME
	if ( &getFarmFile( $farmname ) == -1 )
	{
		# Error
		my $errormsg = "The farmname $farmname does not exist.";

		my $body = {
					 description => $description,
					 error       => "true",
					 message     => $errormsg
		};

		&httpResponse( { code => 404, body => $body } );
	}

	# validate FARM TYPE
	my $type = &getFarmType( $farmname );
	unless ( $type eq 'gslb' || $type eq 'http' || $type eq 'https' )
	{
		# Error
		my $errormsg = "The $type farm profile does not support services.";
		my $body = {
					 description => $description,
					 error       => "true",
					 message     => $errormsg
		};

		&httpResponse({ code => 400, body => $body });
	}

	# validate SERVICE
	require Zevenet::Farm::Service;
	my @services = &getFarmServices($farmname);

	my $found_service = grep { $service eq $_ } @services;

	if ( !$found_service )
	{
		# Error
		my $errormsg = "Could not find the requested service.";
		my $body = {
					 description => $description,
					 error       => "true",
					 message     => $errormsg
		};

		&httpResponse({ code => 404, body => $body });
	}

	my $error = "false";

	if ( $type eq "http" || $type eq "https" )
	{
		require Zevenet::Farm::Config;

		# Functions
		if ( exists ( $json_obj->{ vhost } ) )
		{
			&setFarmVS( $farmname, $service, "vs", $json_obj->{ vhost } );
		}

		if ( exists ( $json_obj->{ urlp } ) )
		{
			&setFarmVS( $farmname, $service, "urlp", $json_obj->{ urlp } );
		}

		my $redirecttype = &getFarmVS( $farmname, $service, "redirecttype" );

		if ( exists ( $json_obj->{ redirect } ) )
		{
			my $redirect = $json_obj->{ redirect };

			if ( $redirect =~ /^http\:\/\//i || $redirect =~ /^https:\/\//i || $redirect eq '' )
			{
				&setFarmVS( $farmname, $service, "redirect", $redirect );
			}
			else
			{
				$error = "true";
				&zenlog(
					"ZAPI error, trying to modify the service $service in a farm $farmname, invalid redirect."
				);
			}
		}

		my $redirect = &getFarmVS( $farmname, $service, "redirect" );

		if ( exists ( $json_obj->{ redirecttype } ) )
		{
			my $redirecttype = $json_obj->{ redirecttype };

			if ( $redirecttype eq "default" )
			{
				&setFarmVS( $farmname, $service, "redirect", $redirect );
			}
			elsif ( $redirecttype eq "append" )
			{
				&setFarmVS( $farmname, $service, "redirectappend", $redirect );
			}
			elsif ( exists $json_obj->{ redirect } && $json_obj->{ redirect } )
			{
				$error = "true";
				&zenlog(
					"ZAPI error, trying to modify the service $service in a farm $farmname, invalid redirecttype."
				);
			}
		}

		if ( exists ( $json_obj->{ sessionid } ) )
		{
			&setFarmVS( $farmname, $service, "sessionid", $json_obj->{ sessionid } );
		}

		if ( exists ( $json_obj->{ ttl } ) )
		{
			if ( $json_obj->{ ttl } =~ /^$/ )
			{
				$error = "true";
				&zenlog(
					"ZAPI error, trying to modify the service $service in a farm $farmname, invalid ttl, can't be blank."
				);
			}
			elsif ( $json_obj->{ ttl } =~ /^\d+/ )
			{
				my $status = &setFarmVS( $farmname, $service, "ttl", "$json_obj->{ttl}" );
				if ( $status != 0 )
				{
					$error = "true";
					&zenlog(
						"ZAPI error, trying to modify the service $service in a farm $farmname, it's not possible to change the ttl parameter."
					);
				}
			}
			else
			{
				$error = "true";
				&zenlog(
					"ZAPI error, trying to modify the service $service in a farm $farmname, invalid ttl, must be numeric."
				);
			}
		}

		if ( exists ( $json_obj->{ persistence } ) )
		{
			if ( $json_obj->{ persistence } =~ /^|IP|BASIC|URL|PARM|COOKIE|HEADER$/ )
			{
				my $session = $json_obj->{ persistence };
				$session = 'nothing' if $session eq "";

				my $status = &setFarmVS( $farmname, $service, "session", $session );

				if ( $status != 0 )
				{
					$error = "true";
					&zenlog(
						"ZAPI error, trying to modify the service $service in a farm $farmname, it's not possible to change the persistence parameter."
					);
				}
			}
		}		

		if ( exists ( $json_obj->{ leastresp } ) )
		{
			if ( $json_obj->{ leastresp } =~ /^$/ )
			{
				$error = "true";
				&zenlog(
					"ZAPI error, trying to modify the service $service in a farm $farmname, invalid leastresp, can't be blank."
				);
			}
			elsif ( $json_obj->{ leastresp } =~ /^true|false$/ )
			{
				if ( ( $json_obj->{ leastresp } eq "true" ) )
				{
					&setFarmVS( $farmname, $service, "dynscale", $json_obj->{ leastresp } );
				}
				elsif ( ( $json_obj->{ leastresp } eq "false" ) )
				{
					&setFarmVS( $farmname, $service, "dynscale", "" );
				}
			}
			else
			{
				$error = "true";
				&zenlog(
					"ZAPI error, trying to modify the service $service in a farm $farmname, invalid leastresp."
				);
			}
		}

		if ( exists ( $json_obj->{ cookieinsert } ) )
		{
			if ( $json_obj->{ cookieinsert } =~ /^$/ )
			{
				$error = "true";
				&zenlog(
					"ZAPI error, trying to modify the service $service in a farm $farmname, invalid cookieinsert, can't be blank."
				);
			}
			elsif ( $json_obj->{ cookieinsert } =~ /^true|false$/ )
			{
				if ( ( $json_obj->{ cookieinsert } eq "true" ) )
				{
					&setFarmVS( $farmname, $service, "cookieins", $json_obj->{ cookieinsert } );
				}
				elsif ( ( $json_obj->{ cookieinsert } eq "false" ) )
				{
					&setFarmVS( $farmname, $service, "cookieins", "" );
				}
			}
			else
			{
				$error = "true";
				&zenlog(
					"ZAPI error, trying to modify the service $service in a farm $farmname, invalid cookieinsert."
				);
			}
		}

		my $cookieins_status = &getHTTPFarmVS ($farmname,$service, 'cookieins');
		if ( $json_obj->{ cookieinsert } eq "true"  || $cookieins_status eq 'true' )
		{
			if ( exists ( $json_obj->{ cookiedomain } ) )
			{
				&setFarmVS( $farmname, $service, "cookieins-domain", $json_obj->{ cookiedomain } );
			}

			if ( exists ( $json_obj->{ cookiename } ) )
			{
				&setFarmVS( $farmname, $service, "cookieins-name", $json_obj->{ cookiename } );
			}

			if ( exists ( $json_obj->{ cookiepath } ) )
			{
				&setFarmVS( $farmname, $service, "cookieins-path", $json_obj->{ cookiepath } );
			}

			if ( exists ( $json_obj->{ cookiettl } ) )
			{
				if ( $json_obj->{ cookiettl } =~ /^$/ )
				{
					$error = "true";
					&zenlog(
						"ZAPI error, trying to modify the service $service in a farm $farmname, invalid cookiettl, can't be blank."
					);
				}
				else
				{
					&setFarmVS( $farmname, $service, "cookieins-ttlc", $json_obj->{ cookiettl } );
				}
			}
		}

		if ( exists ( $json_obj->{ httpsb } ) )
		{
			if ( $json_obj->{ httpsb } =~ /^$/ )
			{
				$error = "true";
				&zenlog(
					"ZAPI error, trying to modify the service $service in a farm $farmname, invalid httpsb, can't be blank."
				);
			}
			elsif ( $json_obj->{ httpsb } =~ /^true|false$/ )
			{
				if ( ( $json_obj->{ httpsb } eq "true" ) )
				{
					&setFarmVS( $farmname, $service, "httpsbackend", $json_obj->{ httpsb } );
				}
				elsif ( ( $json_obj->{ httpsb } eq "false" ) )
				{
					&setFarmVS( $farmname, $service, "httpsbackend", "" );
				}
			}
			else
			{
				$error = "true";
				&zenlog(
					"ZAPI error, trying to modify the service $service in a farm $farmname, invalid httpsb."
				);
			}
		}

		$output_params = &getHTTPServiceStruct( $farmname, $service );
	}

	if ( $type eq "gslb" )
	{
		# Functions
		if ( $json_obj->{ deftcpport } =~ /^$/ )
		{
			$error = "true";
			&zenlog(
				"ZAPI error, trying to modify the service $service in a farm $farmname, invalid deftcpport, can't be blank."
			);
		}
		if ( $error eq "false" )
		{
			# change to number format
			$json_obj->{ deftcpport } += 0;
			
			my $old_deftcpport = &getGSLBFarmVS ($farmname,$service, 'dpc');
			require Zevenet::Farm::Config;
			&setFarmVS( $farmname, $service, "dpc", $json_obj->{ deftcpport } );
			
			# Update farmguardian
			require Zevenet::Farm::GSLB::FarmGuardian;
			my ( $fgTime, $fgScript ) = &getGSLBFarmGuardianParams( $farmname, $service );
			
			# Changing farm guardian port check
			if ( $fgScript =~ s/-p $old_deftcpport/-p $json_obj->{ deftcpport }/ )
			{
				&setGSLBFarmGuardianParams( $farmname, $service, 'cmd', $fgScript );
			}
			
			if ( $? eq 0 )
			{
				require Zevenet::Farm::GSLB::Config;
				&runGSLBFarmReload( $farmname );
			}
			else
			{
				$error = "true";
				&zenlog(
					"ZAPI error, trying to modify the service $service in a farm $farmname, it's not possible to change the deftcpport parameter."
				);
			}
		}

		# FIXME: Read gslb configuration instead of returning input
		$output_params = $json_obj;
	}

	# Print params
	if ( $error ne "true" )
	{
		require Zevenet::Farm::Base;

		&zenlog(
			"ZAPI success, some parameters have been changed in service $service in farm $farmname."
		);

		# Success
		my $body = {
			description => "Modify service $service in farm $farmname",
			params      => $output_params,
		};

		if ( &getFarmStatus( $farmname ) eq 'up' )
		{
			require Zevenet::Farm::Action;

			&setFarmRestart( $farmname );
			$body->{ status } = 'needed restart';
			$body->{ info } = "There're changes that need to be applied, stop and start farm to apply them!";
		}
		
		&httpResponse({ code => 200, body => $body });
	}
	else
	{
		&zenlog(
			"ZAPI error, trying to modify the zones in a farm $farmname, it's not possible to modify the service $service."
		);

		# Error
		$errormsg = "Errors found trying to modify farm $farmname";

		my $body = {
					 description => $description,
					 error       => "true",
					 message     => $errormsg
		};

		&httpResponse({ code => 400, body => $body });
	}
}

sub move_services
{
	my ( $json_obj, $farmname, $service ) = @_;

	require Zevenet::Farm::HTTP::Service;
	my @services = &getHTTPFarmServices( $farmname );
	my $services_num = scalar @services;
	my $description = "Move service";
	my $moveservice;
	my $errormsg;

	# validate FARM NAME
	if ( &getFarmFile( $farmname ) == -1 ) {
		# Error
		$errormsg = "The farmname $farmname does not exists.";
		my $body = {
					 description => $description,
					 error       => "true",
					 message     => $errormsg
		};

		&httpResponse({ code => 404, body => $body });
	}
	elsif ( ! grep ( /^$service$/, @services ) )
	{
		$errormsg = "$service not found.";
		my $body = {
					 description => $description,
					 error       => "true",
					 message     => $errormsg
		};
		&httpResponse({ code => 404, body => $body });
	}

	# Move services
	else
	{
		$errormsg = &getValidOptParams( $json_obj, ["position"] );

		if ( !$errormsg )
		{
			if ( !&getValidFormat( 'service_position', $json_obj->{ 'position' } ) )
			{
				$errormsg = "Error in service position format.";
			}
			else
			{
				my $srv_position = &getFarmVSI( $farmname, $service );
				if ( $srv_position == $json_obj->{ 'position' } )
				{
					$errormsg = "The service already is in required position.";
				}
				elsif ( $services_num <= $json_obj->{ 'position' } )
				{
					$errormsg = "The required position is bigger than number of services.";
				}

				# select action
				elsif ( $srv_position > $json_obj->{ 'position' } )
				{
					$moveservice = "up";
				}
				else
				{
					$moveservice = "down";
				}

				if ( !$errormsg )
				{
					# stopping farm
					require Zevenet::Farm::Base;
					my $farm_status = &getFarmStatus( $farmname );
					if ( $farm_status eq 'up' )
					{
						if ( &runFarmStop( $farmname, "true" ) != 0 )
						{
							$errormsg = "Error stopping the farm.";
						}
						else
						{
							&zenlog( "Farm stopped successful." );
						}
					}
					if ( !$errormsg )
					{
						# move service until required position
						while ( $srv_position != $json_obj->{ 'position' } )
						{
							#change configuration file
							&moveServiceFarmStatus( $farmname, $moveservice, $service );
							&moveService( $farmname, $moveservice, $service );

							$srv_position = &getFarmVSI( $farmname, $service );
						}

						# start farm if his status was up
						if ( $farm_status eq 'up' )
						{
							if ( &runFarmStart( $farmname, "true" ) == 0 )
							{
								&setHTTPFarmBackendStatus( $farmname );
								&zenlog( "$service was moved successful." );
							}
							else
							{
								$errormsg = "The $farmname farm hasn't been restarted";
							}
						}

						if ( !$errormsg )
						{
							$errormsg = "$service was moved successful.";

							if ( &getFarmStatus( $farmname ) eq 'up' )
							{
								&runGSLBFarmReload( $farmname );
								require Zevenet::Cluster;
								&runZClusterRemoteManager( 'farm', 'restart', $farmname );
							}

							my $body =
							  { description => $description, params => $json_obj, message => $errormsg, };
							&httpResponse( { code => 200, body => $body } );
						}
					}
				}
			}
		}
	}

	my $body =
	  { description => $description, error => "true", message => $errormsg };
	&httpResponse( { code => 400, body => $body } );
}

# DELETE

# DELETE /farms/<farmname>/services/<servicename> Delete a service of a Farm
sub delete_service # ( $farmname, $service )
{
	my ( $farmname, $service ) = @_;

	# Check that the farm exists
	if ( &getFarmFile( $farmname ) == -1 )
	{
		# Error
		my $errormsg = "The farmname $farmname does not exists.";
		my $body = {
					 description => "Delete service",
					 error       => "true",
					 message     => $errormsg
		};

		&httpResponse({ code => 404, body => $body });
	}

	my $type = &getFarmType( $farmname );
	
	# Check that the provided service is configured in the farm
	my @services;
	if ($type eq "gslb")
	{
		require Zevenet::Farm::GSLB::Service;
		@services = &getGSLBFarmServices($farmname);
	}
	else
	{
		require Zevenet::Farm::HTTP::Service;
		@services = &getHTTPFarmServices($farmname);
	}

	my $found = 0;
	foreach my $farmservice (@services)
	{
		#print "service: $farmservice";
		if ($service eq $farmservice)
		{
			$found = 1;
			last;
		}
	}

	if ($found == 0)
	{
		# Error
		my $errormsg = "Invalid service name, please insert a valid value.";
		my $body = {
				description => "Delete service",
				error => "true",
				message => $errormsg
		};

		&httpResponse({ code => 400, body => $body });
	}
	
	my $return;
	if ( $type eq "http" || $type eq "https" )
	{
		$return = &deleteFarmService( $farmname, $service );
	}
	elsif ( $type eq "gslb" )
	{
		$return = &setGSLBFarmDeleteService( $farmname, $service );
	}

	if ( $return == -2 )
	{
		&zenlog(
				 "ZAPI error, the service $service in farm $farmname hasn't been deleted. The service is used by a zone." );

		# Error
		my $message = "The service $service in farm $farmname hasn't been deleted. The service is used by a zone.";
		my $body = {
					 description => "Delete service $service in farm $farmname.",
					 error       => "true",
					 message     => $message
		};

		&httpResponse({ code => 400, body => $body });
	}
	elsif ( $return == 0 )
	{
		&zenlog(
				 "ZAPI success, the service $service in farm $farmname has been deleted." );

		# Success
		my $message = "The service $service in farm $farmname has been deleted.";
		my $body = {
					 description => "Delete service $service in farm $farmname.",
					 success     => "true",
					 message     => $message
		};

		require Zevenet::Farm::Base;

		if ( &getFarmStatus( $farmname ) eq 'up' )
		{
			require Zevenet::Farm::Action;

			$body->{ status } = "needed restart";
			&setFarmRestart( $farmname );
		}

		&httpResponse({ code => 200, body => $body });
	}
	else
	{
		&zenlog(
			"ZAPI error, trying to delete the service $service in farm $farmname, the service hasn't been deleted."
		);

		# Error
		my $errormsg = "Service $service in farm $farmname hasn't been deleted.";
		my $body = {
					 description => "Delete service $service in farm $farmname",
					 error       => "true",
					 message     => $errormsg
		};

		&httpResponse({ code => 400, body => $body });
	}
}

1;
