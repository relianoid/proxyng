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
use Zevenet::IPDS::Blacklist::Core;

# GET /ipds/blacklists
sub get_blacklists_all_lists
{
	require Config::Tiny;

	my $desc           = "List the available blacklists";
	my $blacklistsConf = &getGlobalConfiguration( 'blacklistsConf' );
	my %bl             = %{ Config::Tiny->read( $blacklistsConf ) };
	my @lists;
	delete $bl{ _ };

	my @active_lists = `ipset -L -name`;

	foreach my $list_name ( sort keys %bl )
	{
		my $bl_n  = $bl{ $list_name };
		my $bl_nf = $bl_n->{ farms };

		my %listHash = (
					   name   => $list_name,
					   farms  => $bl_nf ? split ( ' ', $bl_nf ) : [],
					   policy => $bl_n->{ policy },
					   type   => $bl_n->{ type },
					   status => ( grep ( /^$list_name$/, @active_lists ) ) ? "up" : "down",
					   preload => $bl_n->{ preload },
		);

		push @lists, \%listHash;
	}

	&httpResponse(
		  { code => 200, body => { description => $desc, params => \@lists } } );
}

#GET /ipds/blacklists/<listname>
sub get_blacklists_list
{
	my $listName = shift;

	my $descr = "Get the blacklist $listName";

	if ( &getBLExists( $listName ) )
	{
		my $msg = "Requested list doesn't exist.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $listHash = &getBLzapi( $listName );

	&httpResponse(
			   { code => 200, body => { description => $desc, params => $listHash } } );
}

#  POST /ipds/blacklists
sub add_blacklists_list
{
	my $json_obj = shift;

	require Zevenet::IPDS::Blacklist::Config;

	my $desc     = "Create the blacklist $listName";
	my $listName = $json_obj->{ 'name' };
	my $listParams;

	my @requiredParams = ( "name",   "type" );
	my @optionalParams = ( "policy", "url" );

	my $msg = &getValidReqParams( $json_obj, \@requiredParams, \@optionalParams );

	# $errormsg == 0, no error
	if ( $msg )
	{
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# A list already exists with this name
	if ( &getBLExists( $listName ) != -1 )
	{
		my $msg = "A list already exists with name '$listName'.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# Check key format
	foreach my $key ( keys %$json_obj )
	{
		if ( !&getValidFormat( "blacklists_$key", $json_obj->{ $key } ) )
		{
			my $msg = "$key hasn't a correct format.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}

	if ( exists $json_obj->{ 'url' } )
	{
		if ( $json_obj->{ 'type' } ne 'remote' )
		{
			my $msg = "Url only is available in remote lists.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		$listParams->{ 'url' } = $json_obj->{ 'url' };
	}
	else
	{
		if ( $json_obj->{ 'type' } eq 'remote' )
		{
			my $msg = "It's necessary to add the url where is allocated the list.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}

	$listParams->{ 'type' }   = $json_obj->{ 'type' };
	$listParams->{ 'policy' } = $json_obj->{ 'policy' }
	  if ( exists $json_obj->{ 'policy' } );

	if ( &setBLCreateList( $listName, $listParams ) )
	{
		my $msg = "Error, creating a new list.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $listHash = &getBLParam( $listName );
	delete $listHash->{ 'source' };

	&httpResponse(
				   {
					 code => 200,
					 body => { description => $desc, params => $listHash }
				   }
	);
}

#  PUT /ipds/blacklists/<listname>
sub set_blacklists_list
{
	my $json_obj = shift;
	my $listName = shift;

	require Zevenet::IPDS::Blacklist::Config;

	my $desc = "Modify the blacklist $listName.";
	my $errormsg;

	# remove time hash and add its param to common configuration hash
	foreach my $timeParameters ( ( 'period', 'unit', 'hour', 'minutes' ) )
	{
		if ( exists $json_obj->{ 'time' }->{ $timeParameters } )
		{
			$json_obj->{ $timeParameters } = $json_obj->{ 'time' }->{ $timeParameters };
		}
	}
	delete $json_obj->{ 'time' };

	my @allowParams = (
						"policy",         "url",    "source", "name",
						"minutes",        "hour",   "day",    "frequency",
						"frequency_type", "period", "unit"
	);

	# check if BL exists
	if ( &getBLExists( $listName ) == -1 )
	{
		my $msg = "The list '$listName' doesn't exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# check not allowed actions on preloaded BL
	if ( &getBLParam( $listName, 'preload' ) eq 'true' )
	{
		my $errormsg = &getValidOptParams( $json_obj, ["policy"] );

		if ( $errormsg )
		{
			my $msg = "In preload lists only is allowed to change the policy";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}

	my $type = &getBLParam( $listName, 'type' );
	my $errormsg = &getValidOptParams( $json_obj, \@allowParams );

	if ( $errormsg )
	{
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# Check key format
	foreach my $key ( keys %{ $json_obj } )
	{
		next if ( $key eq 'source' );
		if ( !&getValidFormat( "blacklists_$key", $json_obj->{ $key } ) )
		{
			my $msg = "$key hasn't a correct format.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}

	# Cron params and url only is used in remote lists
	if ( $type ne 'remote' )
	{
		if (
			 grep ( /^(url|minutes|hour|day|frequency|frequency_type|period|unit)$/,
					keys %{ $json_obj } )
		  )

#~ if ( ! &getValidOptParams( $json_obj, [ "url", "minutes", "hour", "day", "frequency", "frequency_type", "period", "unit" ] ) )
		{
			my $msg = "Error, trying to change a remote list parameter in a local list.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}

	# Sources only is used in local lists
	if ( exists $json_obj->{ 'sources' }
		 && $type ne 'local' )
	{
		my $msg = "Source parameter only is available in local lists.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $cronFlag;

	# if there is a new update time configuration to remote lists, delete old configuration
	#checking available configurations
	if (
		 grep ( /^(minutes|hour|day|frequency|frequency_type|period|unit)$/,
				keys %{ $json_obj } )
	  )
	{
		$json_obj->{ 'frequency' } ||= &getBLParam( $listName, "frequency" );

		if ( $json_obj->{ 'frequency' } eq 'daily' )
		{
			$json_obj->{ 'frequency_type' } ||= &getBLParam( $listName, "frequency_type" );

			if ( $json_obj->{ 'frequency_type' } eq 'period' )
			{
				$json_obj->{ 'period' } = &getBLParam( $listName, "period" )
				  if ( !exists $json_obj->{ 'period' } );

				$json_obj->{ 'unit' } = &getBLParam( $listName, "unit" )
				  if ( !exists $json_obj->{ 'unit' } );

				foreach my $timeParam ( "period", "unit" )
				{
					if (   !&getValidFormat( "blacklists_$timeParam", $json_obj->{ $timeParam } )
						 || $json_obj->{ $timeParam } eq '' )
					{
						my $msg =
						  "$timeParam parameter missing to $json_obj->{ frequency } configuration.";
						&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
					}
				}

				&delBLParam( $listName, $_ ) for ( "minutes", "hour", "day" );

				# rewrite cron task if exists some of the next keys
				$cronFlag = 1;
			}
			elsif ( $json_obj->{ 'frequency_type' } eq 'exact' )
			{
				$json_obj->{ 'minutes' } = &getBLParam( $listName, "minutes" )
				  if ( !exists $json_obj->{ 'minutes' } );
				$json_obj->{ 'hour' } = &getBLParam( $listName, "hour" )
				  if ( !exists $json_obj->{ 'hour' } );

				foreach my $timeParam ( "minutes", "hour" )
				{
					if (   !&getValidFormat( "blacklists_$timeParam", $json_obj->{ $timeParam } )
						 || $json_obj->{ $timeParam } eq '' )
					{
						my $msg =
						  "$timeParam parameter missing to $json_obj->{ frequency } configuration.";
						&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
					}
				}

				&delBLParam( $listName, $_ ) for ( "unit", "period", "day" );

				# rewrite cron task if exists some of the next keys
				$cronFlag = 1;
			}
			else
			{
				my $msg = "It's neccessary indicate frequency type for daily frequency.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}
		}
		elsif ( $json_obj->{ 'frequency' } eq 'weekly' )
		{
			$json_obj->{ 'minutes' } = &getBLParam( $listName, "minutes" )
			  if ( !exists $json_obj->{ 'minutes' } );
			$json_obj->{ 'hour' } = &getBLParam( $listName, "hour" )
			  if ( !exists $json_obj->{ 'hour' } );
			$json_obj->{ 'day' } = &getBLParam( $listName, "day" )
			  if ( !exists $json_obj->{ 'day' } );

			foreach my $timeParam ( "minutes", "hour", "day" )
			{
				if (   !&getValidFormat( "blacklists_$timeParam", $json_obj->{ $timeParam } )
					 || $json_obj->{ $timeParam } eq '' )
				{
					my $msg =
					  "$timeParam parameter missing to $json_obj->{ frequency } configuration.";
					&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
				}
			}

			if ( !&getValidFormat( 'weekdays', $json_obj->{ 'day' } ) )
			{
				my $msg =
				  "Error value of day parameter in $json_obj->{ 'frequency' } frequency.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			&delBLParam( $listName, $_ ) for ( "frequency_type", "period", "unit" );

			# rewrite cron task if exists some of the next keys
			$cronFlag = 1;
		}
		elsif ( $json_obj->{ 'frequency' } eq 'monthly' )
		{
			$json_obj->{ 'minutes' } = &getBLParam( $listName, "minutes" )
			  if ( !exists $json_obj->{ 'minutes' } );
			$json_obj->{ 'hour' } = &getBLParam( $listName, "hour" )
			  if ( !exists $json_obj->{ 'hour' } );
			$json_obj->{ 'day' } = &getBLParam( $listName, "day" ) + 0
			  if ( !exists $json_obj->{ 'day' } );    # number format

			# check if exists all paramameters
			foreach my $timeParam ( "hour", "minutes", "day" )
			{
				if (   !&getValidFormat( "blacklists_$timeParam", $json_obj->{ $timeParam } )
					 || $json_obj->{ $timeParam } eq '' )
				{
					my $msg =
					  "$timeParam parameter missing to $json_obj->{ frequency } configuration.";
					&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
				}
			}

			if ( !&getValidFormat( 'day_of_month', $json_obj->{ 'day' } ) )
			{
				my $msg =
				  "Error value of day parameter in $json_obj->{ 'frequency' } frequency.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			&delBLParam( $listName, $_ ) for ( "unit", "period", "frequency_type" );

			# rewrite cron task if exists some of the next keys
			$cronFlag = 1;
		}
		else
		{
			my $msg = "Error with update configuration parameters.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}

	my $source_format = &getValidFormat( 'blacklists_source' );

	foreach my $key ( keys %{ $json_obj } )
	{
		# add only the sources with a correct format
		# no correct format sources are ignored
		if ( $key eq 'sources' )
		{
			my $noPush = grep ( !/^$source_format$/, @{ $json_obj->{ 'sources' } } );

			# error
			&zenlog( "$noPush sources couldn't be added" ) if ( $noPush );
		}

		# set params
		$errormsg = &setBLParam( $listName, $key, $json_obj->{ $key } );

		# once changed list, update de list name
		if ( $key eq 'name' )
		{
			$listName = $json_obj->{ 'name' };
		}

		# not continue if there was a error
		if ( $errormsg )
		{
			my $msg = "Error, modifying $key in $listName.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}

	if ( $cronFlag && @{ &getBLParam( $listName, 'farms' ) } )
	{
		&setBLCronTask( $listName );
	}

	# all successful
	my $listHash = &getBLzapi( $listName );
	delete $listHash->{ 'sources' };
	delete $listHash->{ 'farms' };

	my $body = { description => $desc, params => $listHash };

	require Zevenet::Cluster;
	&runZClusterRemoteManager( 'ipds_bl', 'restart', $listName );

	&httpResponse( { code => 200, body => $body } );
}

#  DELETE /ipds/blacklists/<listname> Delete a Farm
sub del_blacklists_list
{
	my $listName = shift;

	require Zevenet::IPDS::Blacklist::Config;

	my $desc     = "Delete the list $listName";
	my $errormsg = &getBLExists( $listName );

	# check BL is available
	if ( $errormsg == -1 )
	{
		my $msg = "$listName doesn't exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# check the list is not being used
	if ( @{ &getBLParam( $listName, 'farms' ) } )
	{
		my $msg = "Remove this list from all farms before deleting it.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $error = &setBLDeleteList( $listName );

	# check for errors deleting the BL
	if ( $error )
	{
		my $msg = "Error, deleting the list $listName.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $msg = "The list $listName has been deleted successful.";
	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $msg,
	};

	&httpResponse( { code => 200, body => $body } );
}

# POST /ipds/blacklists/BLACKLIST/actions
sub actions_blacklists
{
	my $json_obj = shift;
	my $listName = shift;

	require Zevenet::IPDS::Blacklist::Actions;

	my $desc     = "Apply a action to a blacklist $listName";
	my $errormsg = "Error, applying the action to the blacklist.";

	my $error = &getBLExists( $listName );
	if ( $error == -1 )
	{
		my $msg = "$listName doesn't exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# allow only available actions
	if ( $json_obj->{ action } eq 'update' )
	{
		&update_remote_blacklists( $listName );
	}
	elsif ( $json_obj->{ action } eq 'start' )
	{
		my $error = &runBLStartByRule( $listName );
		&httpErrorResponse( code => 400, desc => $desc, msg => $errormsg ) if $error;
	}
	elsif ( $json_obj->{ action } eq 'stop' )
	{
		my $error = &runBLStopByRule( $listName );
		&httpErrorResponse( code => 400, desc => $desc, msg => $errormsg ) if $error;
	}
	elsif ( $json_obj->{ action } eq 'restart' )
	{
		my $error = &runBLRestartByRule( $listName );
		&httpErrorResponse( code => 400, desc => $desc, msg => $errormsg ) if $error;
	}
	else
	{
		my $msg = "The action has not a valid value";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# restart in remote node if an update was requested, or do the requested action
	my $action = $json_obj->{ action } eq 'update'? 'restart': $json_obj->{ action };

	require Zevenet::Cluster;
	&runZClusterRemoteManager( 'ipds_bl', $action, $listName );

	my $body = {
				 description => $desc,
				 success     => "true",
				 params      => $json_obj->{ action }
	};

	&httpResponse( { code => 200, body => $body } );
}

# POST /ipds/blacklists/BLACKLIST/actions 	update a remote blacklist
sub update_remote_blacklists
{
	my $listName = shift;

	require Zevenet::IPDS::Blacklist::Runtime;

	my $desc = "Update a remote list";

	if ( &getBLParam( $listName, 'type' ) ne 'remote' )
	{
		my $msg = "Error, only remote lists can be updated.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $errormsg = &setBLDownloadRemoteList( $listName );
	my $statusUpd = &getBLParam( $listName, 'update_status' );

	if ( $errormsg )
	{
		my $msg = $statusUpd;
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	if ( @{ &getBLParam( $listName, 'farms' ) } )
	{
		&setBLRefreshList( $listName );
	}

	my $body = {
				 description => $desc,
				 success     => "true",
				 params      => { "action" => "update" }
	};

	&httpResponse( { code => 200, body => $body } );
}

#GET /ipds/blacklists/<listname>/sources
sub get_blacklists_source
{
	my $listName = shift;

	my $desc = "List the sources of the blacklist $listName";
	my $err  = &getBLExists( $listName );

	if ( $err )
	{
		my $msg = "Requested list doesn't exist.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my @ipList;
	my $index = 0;

	foreach my $source ( @{ &getBLParam( $listName, 'source' ) } )
	{
		push @ipList, { id => $index++, source => $source };
	}

	&httpResponse( { code => 200, body => { description => $desc, params => \@ipList } } );
}

#  POST /ipds/blacklists/<listname>/sources
sub add_blacklists_source
{
	my $json_obj = shift;
	my $listName = shift;

	my $desc = "Add a source to the blacklist $listName.";
	my @requiredParams = ( "source" );
	my @optionalParams;

	if ( &getBLExists( $listName ) == -1 )
	{
		my $msg = "$listName doesn't exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my $msg = &getValidReqParams( $json_obj, \@requiredParams, \@optionalParams );

	if ( $msg )
	{
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	if ( !&getValidFormat( 'blacklists_source', $json_obj->{ 'source' } ) )
	{
		my $msg = "It's necessary to introduce a correct source.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	if ( grep ( /^$json_obj->{'source'}$/, @{ &getBLParam( $listName, 'source' ) } ) )
	{
		my $msg = "$json_obj->{'source'} already exists in the list.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# ipset not allow the input 0.0.0.0/0, if this source is set, replace it for 0.0.0.0/1 and 128.0.0.0/1
	if ( $json_obj->{ 'source' } eq '0.0.0.0/0' )
	{
		my $msg =
		  "Error, the source $json_obj->{'source'} is not valid, for this action, use the list \"All\".";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	require Zevenet::IPDS::Blacklist::Config;
	my $error = &setBLAddSource( $listName, $json_obj->{ 'source' } );

	if ( $error )
	{
		my $msg = "Error, adding source to $listName.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my @ipList;
	my $index = 0;

	foreach my $source ( @{ &getBLParam( $listName, 'source' ) } )
	{
		push @ipList, { id => $index++, source => $source };
	}

	require Zevenet::Cluster;
	&runZClusterRemoteManager( 'ipds_bl', 'restart', $listName );

	# no error found, send successful response
	$msg = "Added $json_obj->{'source'} successful.";
	my $body = {
				 description => $description,
				 params      => \@ipList,
				 message     => $errormsg,
	};

	&httpResponse( { code => 200, body => $body } );
}

#  PUT /ipds/blacklists/<listname>/sources/<id>
sub set_blacklists_source
{
	my $json_obj = shift;
	my $listName = shift;
	my $id       = shift;

	require Zevenet::IPDS::Blacklist::Config;

	my $desc        = "Modify a source of the blacklsit $listName";
	my @allowParams = ( "source" );

	# check list exists
	if ( &getBLExists( $listName ) == -1 )
	{
		my $msg = "$listName not found";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# check source id exists
	elsif ( @{ &getBLParam( $listName, 'source' ) } <= $id )
	{
		my $msg = "Source id $id not found";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my $errormsg = &getValidOptParams( $json_obj, \@allowParams );

	if ( $errormsg )
	{
		&httpErrorResponse( code => 400, desc => $desc, msg => $errormsg );
	}

	if ( !&getValidFormat( 'blacklists_source', $json_obj->{ 'source' } ) )
	{
		my $msg = "Wrong source format.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	if ( &setBLModifSource( $listName, $id, $json_obj->{ 'source' } ) != 0 )
	{
		my $msg = "Error, putting the source to the list.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $msg = "Source $id has been modified successful.";
	my $body = {
				 description => $desc,
				 message     => $msg,
				 params      => { "source" => $json_obj->{ 'source' }, 'id' => $id }
	};

	require Zevenet::Cluster;
	&runZClusterRemoteManager( 'ipds_bl', 'restart', $listName );

	&httpResponse( { code => 200, body => $body } );
}

#  DELETE /ipds/blacklists/<listname>/sources/<id>	Delete a source from a black list
sub del_blacklists_source
{
	my $listName = shift;
	my $id       = shift;

	require Zevenet::IPDS::Blacklist::Config;

	my $desc = "Delete a source from the blacklist $listName";

	if ( &getBLExists( $listName ) == -1 )
	{
		$msg = "$listName doesn't exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	if ( @{ &getBLParam( $listName, 'source' ) } <= $id )
	{
		my $msg = "ID $id doesn't exist in the list $listName.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	if ( &setBLDeleteSource( $listName, $id ) != 0 )
	{
		my $msg = "Error deleting source $id";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $msg = "Source $id has been deleted successful.";
	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $errormsg,
	};

	require Zevenet::Cluster;
	&runZClusterRemoteManager( 'ipds_bl', 'restart', $listName );

	&httpResponse( { code => 200, body => $body } );
}

#  POST /farms/<farmname>/ipds/blacklists
sub add_blacklists_to_farm
{
	my $json_obj = shift;
	my $farmName = shift;

	my $desc     = "Apply the blacklist $listName to the farm $farmName";
	my $listName = $json_obj->{ 'name' };
	my $errormsg = &getValidReqParams( $json_obj, ["name"] );

	if ( $errormsg )
	{
		&httpErrorResponse( code => 400, desc => $desc, msg => $errormsg );
	}

	require Zevenet::Farm::Core;

	if ( &getFarmFile( $farmName ) eq "-1" )
	{
		my $msg = "$farmName doesn't exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	if ( &getBLExists( $listName ) == -1 )
	{
		my $msg = "$listName doesn't exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	if ( grep ( /^$farmName$/, @{ &getBLParam( $listName, 'farms' ) } ) )
	{
		my $msg = "$listName is already applied to $farmName.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	require Zevenet::IPDS::Blacklist::Runtime;
	$errormsg = &setBLApplyToFarm( $farmName, $listName );

	if ( $errormsg )
	{
		my $msg = "Error, applying $listName to $farmName";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $msg =
	  "Blacklist rule $listName was applied successful to the farm $farmName.";
	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $msg
	};

	require Zevenet::Cluster;
	&runZClusterRemoteManager( 'ipds_bl', 'start', $listName, $farmName );

	&httpResponse( { code => 200, body => $body } );
}

# DELETE /farms/<farmname>/ipds/blacklists/<listname>
sub del_blacklists_from_farm
{
	my $farmName = shift;
	my $listName = shift;

	require Zevenet::IPDS::Blacklist::Runtime;

	my $desc = "Unset the blacklist $listName from the farm $farmName";

	if ( &getFarmFile( $farmName ) eq '-1' )
	{
		my $msg = "$farmName doesn't exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	if ( &getBLExists( $listName ) == -1 )
	{
		my $msg = "$listName doesn't exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	if ( !grep ( /^$farmName$/, @{ &getBLParam( $listName, 'farms' ) } ) )
	{
		my $msg = "Not found a rule associated to $listName and $farmName.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my $error = &setBLRemFromFarm( $farmName, $listName );

	if ( $error )
	{
		my $msg = "Error, removing $listName rule from $farmName.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $msg =
	  "Blacklist rule $listName was removed successful from the farm $farmName.";
	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $msg,
	};

	require Zevenet::Cluster;
	&runZClusterRemoteManager( 'ipds_bl', 'stop', $listName, $farmName );

	&httpResponse( { code => 200, body => $body } );
}

1;
