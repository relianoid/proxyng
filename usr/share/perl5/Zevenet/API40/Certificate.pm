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

my $eload;
if ( eval { require Zevenet::ELoad; } )
{
	$eload = 1;
}

my $CSR_KEY_SIZE = 2048;

# GET /certificates
sub certificates    # ()
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	require Zevenet::Certificate;

	my $desc         = "List certificates";
	my @certificates = &getCertFiles();
	my $configdir    = &getGlobalConfiguration( 'configdir' );
	my @out;

	foreach my $cert ( @certificates )
	{
		push @out, &getCertInfo( $cert, $configdir );
	}

	my $body = {
				 description => $desc,
				 params      => \@out,
	};

	&httpResponse( { code => 200, body => $body } );
}

# GET /certificates/CERTIFICATE
sub download_certificate    # ()
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $cert_filename = shift;

	my $desc      = "Download certificate";
	my $cert_dir  = &getGlobalConfiguration( 'configdir' );
	my $cert_path = "$cert_dir/$cert_filename";

	unless ( $cert_filename =~ /\.(pem|csr)$/ && -f $cert_path )
	{
		my $msg = "Could not find such certificate";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	&httpDownloadResponse(
						   desc => $desc,
						   dir  => $cert_dir,
						   file => $cert_filename
	);
}

# DELETE /certificates/CERTIFICATE
sub delete_certificate    # ( $cert_filename )
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $cert_filename = shift;

	require Zevenet::Certificate;

	my $desc     = "Delete certificate";
	my $cert_dir = &getGlobalConfiguration( 'configdir' );

	# check is the certificate file exists
	if ( !-f "$cert_dir\/$cert_filename" )
	{
		my $msg = "Certificate file not found.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my $status = &getFarmCertUsed( $cert_filename );

	# check is the certificate is being used
	if ( $status == 0 )
	{
		my $msg = "File can't be deleted because it's in use by a farm.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	&delCert( $cert_filename );

	# check if the certificate exists
	if ( -f "$cert_dir\/$cert_filename" )
	{
		my $msg = "Error deleting certificate $cert_filename.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# no errors found, make a succesful response
	my $msg = "The Certificate $cert_filename has been deleted.";
	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $msg,
	};

	&httpResponse( { code => 200, body => $body } );
}

# POST /certificates (Create CSR)
sub create_csr
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $json_obj = shift;

	require Zevenet::Certificate;

	my $desc      = 'Create CSR';
	my $configdir = &getGlobalConfiguration( 'configdir' );

	if ( -f "$configdir/$json_obj->{name}.csr" )
	{
		my $msg = "$json_obj->{name} already exists.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	$json_obj->{ name }         = &getCleanBlanc( $json_obj->{ name } );
	$json_obj->{ fqdn }         = &getCleanBlanc( $json_obj->{ fqdn } );
	$json_obj->{ division }     = &getCleanBlanc( $json_obj->{ division } );
	$json_obj->{ organization } = &getCleanBlanc( $json_obj->{ organization } );
	$json_obj->{ locality }     = &getCleanBlanc( $json_obj->{ locality } );
	$json_obj->{ state }        = &getCleanBlanc( $json_obj->{ state } );
	$json_obj->{ country }      = &getCleanBlanc( $json_obj->{ country } );
	$json_obj->{ mail }         = &getCleanBlanc( $json_obj->{ mail } );

	if (    $json_obj->{ name } =~ /^$/
		 || $json_obj->{ fqdn } =~ /^$/
		 || $json_obj->{ division } =~ /^$/
		 || $json_obj->{ organization } =~ /^$/
		 || $json_obj->{ locality } =~ /^$/
		 || $json_obj->{ state } =~ /^$/
		 || $json_obj->{ country } =~ /^$/
		 || $json_obj->{ mail } =~ /^$/ )
	{
		my $msg = "Fields can not be empty. Try again.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	if ( &checkFQDN( $json_obj->{ fqdn } ) eq "false" )
	{
		my $msg =
		  "FQDN is not valid. It must be as these examples: domain.com, mail.domain.com, or *.domain.com. Try again.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	if ( $json_obj->{ name } !~ /^[a-zA-Z0-9\-]*$/ )
	{
		my $msg =
		  "Certificate Name is not valid. Only letters, numbers and '-' chararter are allowed. Try again.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $error = &createCSR(
							$json_obj->{ name },
							$json_obj->{ fqdn },
							$json_obj->{ country },
							$json_obj->{ state },
							$json_obj->{ locality },
							$json_obj->{ organization },
							$json_obj->{ division },
							$json_obj->{ mail },
							$CSR_KEY_SIZE,
							""
	);

	if ( $error )
	{
		my $msg = "Error, creating certificate $json_obj->{ name }.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $message = "Certificate $json_obj->{ name } created";
	&zenlog( $message, "info", "LSLB" );

	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $message,
	};

	&httpResponse( { code => 200, body => $body } );
}

# POST /certificates/CERTIFICATE (Upload PEM)
sub upload_certificate    # ()
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $upload_data = shift;
	my $filename    = shift;

	require Zevenet::File;

	my $desc      = "Upload PEM certificate";
	my $configdir = &getGlobalConfiguration( 'configdir' );

	if ( not &getValidFormat( 'certificate', $filename ) )
	{
		my $msg = "Invalid certificate file name";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# check if the certificate filename already exists
	$filename =~ s/[\(\)\@ ]//g;
	if ( -f "$configdir/$filename" )
	{
		my $msg = "Certificate file name already exists";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	unless ( &setFile( "$configdir/$filename", $upload_data ) )
	{
		my $msg = "Could not save the certificate file";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# no errors found, return sucessful response
	my $message = "Certificate uploaded";
	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $message,
	};

	&httpResponse( { code => 200, body => $body } );
}

# GET /ciphers
sub ciphers_available    # ( $json_obj, $farmname )
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $desc = "Get the ciphers available";

	my @out = (
				{ 'ciphers' => "all",            "description" => "All" },
				{ 'ciphers' => "highsecurity",   "description" => "High security" },
				{ 'ciphers' => "customsecurity", "description" => "Custom security" }
	);

	if ( $eload )
	{
		push (
			   @out,
			   &eload(
					   module => 'Zevenet::Farm::HTTP::HTTPS::Ext',
					   func   => 'getExtraCipherProfiles',
			   )
		);
	}

	my $body = {
				 description => $desc,
				 params      => \@out,
	};

	&httpResponse( { code => 200, body => $body } );
}

# POST /farms/FARM/certificates (Add certificate to farm)
sub add_farm_certificate    # ( $json_obj, $farmname )
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $json_obj = shift;
	my $farmname = shift;

	require Zevenet::Farm::Core;
	require Zevenet::Farm::Base;
	unless ( $eload ) { require Zevenet::Farm::HTTP::HTTPS; }

	my $desc = "Add certificate to farm '$farmname'";

	# Check if the farm exists
	if ( !&getFarmExists( $farmname ) )
	{
		my $msg = "Farm not found";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my $configdir   = &getGlobalConfiguration( 'configdir' );
	my $cert_pem_re = &getValidFormat( 'cert_pem' );

	# validate certificate filename and format
	unless ( -f $configdir . "/" . $json_obj->{ file }
			 && &getValidFormat( 'cert_pem', $json_obj->{ file } ) )
	{
		my $msg = "Invalid certificate name, please insert a valid value.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $cert_in_use;
	if ( $eload )
	{
		$cert_in_use = grep ( /^$json_obj->{ file }$/,
							  &eload(
									  module => 'Zevenet::Farm::HTTP::HTTPS::Ext',
									  func   => 'getFarmCertificatesSNI',
									  args   => [$farmname]
							  ) );
	}
	else
	{
		$cert_in_use = &getFarmCertificate( $farmname ) eq $json_obj->{ file };
	}

	if ( $cert_in_use )
	{
		my $msg = "The certificate already exists in the farm.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# FIXME: Show error if the certificate is already in the list
	my $status;
	if ( $eload )
	{
		$status = &eload(
						  module => 'Zevenet::Farm::HTTP::HTTPS::Ext',
						  func   => 'setFarmCertificateSNI',
						  args   => [$json_obj->{ file }, $farmname],
		);
	}
	else
	{
		$status = &setFarmCertificate( $json_obj->{ file }, $farmname );
	}

	if ( $status )
	{
		my $msg =
		  "It's not possible to add the certificate with name $json_obj->{file} for the $farmname farm";

		&zenlog( "It's not possible to add the certificate.", "error", "LSLB" );
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# no errors found, return succesful response
	&zenlog( "Success trying to add a certificate to the farm.", "info", "LSLB" );

	my $message =
	  "The certificate $json_obj->{file} has been added to the farm $farmname, you need restart the farm to apply";

	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $message,
	};

	if ( &getFarmStatus( $farmname ) ne 'down' )
	{
		require Zevenet::Farm::Action;

		&setFarmRestart( $farmname );
		$body->{ status } = 'needed restart';
	}

	&httpResponse( { code => 200, body => $body } );
}

# DELETE /farms/FARM/certificates/CERTIFICATE
sub delete_farm_certificate    # ( $farmname, $certfilename )
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $farmname     = shift;
	my $certfilename = shift;

	require Zevenet::Farm::Core;
	require Zevenet::Farm::Base;

	my $desc = "Delete farm certificate";

	unless ( $eload )
	{
		my $msg = "HTTPS farm without certificate is not allowed.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# Check if the farm exists
	if ( !&getFarmExists( $farmname ) )
	{
		my $msg = "The farmname $farmname does not exists";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# validate certificate
	unless ( $certfilename && &getValidFormat( 'cert_pem', $certfilename ) )
	{
		my $msg = "Invalid certificate id, please insert a valid value.";
		&zenlog( "Invalid certificate id.", "error", "LSLB" );
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my @certSNI = &eload(
						  module => 'Zevenet::Farm::HTTP::HTTPS::Ext',
						  func   => 'getFarmCertificatesSNI',
						  args   => [$farmname],
	);

	my $number = scalar grep ( { $_ eq $certfilename } @certSNI );
	if ( !$number )
	{
		my $msg = "Certificate is not used by the farm.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $status;

 # This is a BUGFIX: delete the certificate all times that it appears in config file
	for ( my $it = 0 ; $it < $number ; $it++ )
	{
		$status = &eload(
						  module => 'Zevenet::Farm::HTTP::HTTPS::Ext',
						  func   => 'setFarmDeleteCertNameSNI',
						  args   => [$certfilename, $farmname],
		);
		last if ( $status == -1 );
	}

	# check if the certificate could not be removed
	if ( $status == -1 )
	{
		&zenlog( "It's not possible to delete the certificate.", "error", "LSLB" );

		my $msg =
		  "It isn't possible to delete the selected certificate $certfilename from the SNI list";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

   # check if removing the certificate would leave the SNI list empty, not supported
	if ( $status == 1 )
	{
		&zenlog(
			"It's not possible to delete all certificates, at least one is required for HTTPS.",
			"error", "LSLB"
		);

		my $msg =
		  "It isn't possible to delete all certificates, at least one is required for HTTPS profiles";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# no errors found, return succesful response
	my $msg = "The Certificate $certfilename has been deleted";
	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $msg
	};

	if ( &getFarmStatus( $farmname ) ne 'down' )
	{
		require Zevenet::Farm::Action;

		&setFarmRestart( $farmname );
		$body->{ status } = 'needed restart';
	}

	&zenlog( "Success trying to delete a certificate to the SNI list.",
			 "error", "LSLB" );
	&httpResponse( { code => 200, body => $body } );
}

1;
