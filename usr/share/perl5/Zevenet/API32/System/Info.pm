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

# show license
sub get_license
{
	&zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING" );
	my $format = shift;

	require Zevenet::System;

	my $desc = "Get license";
	my $licenseFile;

	if ( $format eq 'txt' )
	{
		$licenseFile = &getGlobalConfiguration( 'licenseFileTxt' );
	}
	elsif ( $format eq 'html' )
	{
		$licenseFile = &getGlobalConfiguration( 'licenseFileHtml' );
	}
	else
	{
		my $msg = "Not found license.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $file = &slurpFile( $licenseFile );

	&httpResponse({ code => 200, body => $file, type => 'text/plain' });
}

sub get_supportsave
{
	&zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING" );
	my $desc = "Get supportsave file";

	require Zevenet::System;

	my $ss_filename = &getSupportSave();

	&httpDownloadResponse( desc => $desc, dir => '/tmp', file => $ss_filename );
}

# GET /system/version
sub get_version
{
	&zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING" );
	require Zevenet::SystemInfo;
	require Zevenet::Certificate;

	my $desc    = "Get version";
	my $zevenet = &getGlobalConfiguration( 'version' );

	my $kernel     = &getKernelVersion();
	my $hostname   = &getHostname();
	my $date       = &getDate();
	my $applicance = &getApplianceVersion();

	my $params = {
				   'kernel_version'    => $kernel,
				   'zevenet_version'   => $zevenet,
				   'hostname'          => $hostname,
				   'system_date'       => $date,
				   'appliance_version' => $applicance,
	};
	my $body = { description => $desc, params => $params };

	&httpResponse( { code => 200, body => $body } );
}

1;
