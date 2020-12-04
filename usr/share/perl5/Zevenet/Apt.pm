#!/usr/bin/perl
use strict;

use Zevenet::Core;
use Zevenet::SystemInfo;
include 'Zevenet::Certificate::Activation';

my $cert_path = &getGlobalConfiguration( 'zlbcertfile_path' );
my $openssl   = &getGlobalConfiguration( 'openssl' );
my $grep      = &getGlobalConfiguration( 'grep_bin' );

=begin nd
Function: getAPTSerial

    It returns the certificate serial used to sync with the APT

Parameters:

Returns:
	string - serial

=cut

sub getAPTSerial
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $subserial = "$openssl x509 -in $cert_path -serial -noout";

	# command to get the serial
	my $serial = &logAndGet( $subserial );
	if ( $serial eq '' )
	{
		&zenlog( "Serial is not correct", "error", "apt" );
	}
	else
	{
		# creating the structure that apt understands
		$serial =~ s/serial=//;

		# delete line break of the variable
		$serial =~ s/[\r\n]//g;
	}

	return $serial;
}

=begin nd
Function: getAPTSubjKeyId

    It returns the certificate subject key ID

Parameters:

Returns:
	string - subject key ID

=cut

sub getAPTSubjKeyId
{
	my $subkeyidentifier =
	  "openssl x509 -in $cert_path -noout -text | $grep -A1 \"Subject Key Identifier\"";

	# command to get the Subject Key Identifier
	my $subjectkeyidentifier = `$subkeyidentifier`;
	if ( $? != 0 )
	{
		&zenlog( "The subject ID '$subjectkeyidentifier' is not correct",
				 "error", "apt" );
		return "";
	}

	$subjectkeyidentifier =~ s/[\r\n]//g;
	$subjectkeyidentifier =~ s/.*:\s+//g;

	return $subjectkeyidentifier;
}

=begin nd
Function: getAPTUserAgent

    It returns the string used in the HTTP User Agent header to validate the load balancer
    in the APT repository.

Parameters:
	cert serial -  This field is optional. The function will get it if it is not passed

Returns:
	string - value for the user agent header

=cut

sub getAPTUserAgent
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $serial = shift // &getAPTSerial();
	my $subjectkeyidentifier = &getAPTSubjKeyId();

	if ( $serial eq '' or $subjectkeyidentifier eq '' )
	{
		return '';
	}

	return "$serial:$subjectkeyidentifier";
}

=begin nd
Function: setAPTRepo

    It configures the system to connect with the APT.
    It modify the apt.conf file (adding proxy info if it is configured), get the
    gpg key, and the source list file.

Parameters:

Returns:
	Integer - Error code, 0 on success or another value on failure

=cut

sub setAPTRepo
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	# Variables
	my $keyid    = &getKeySigned();
	my $host     = &getGlobalConfiguration( 'repo_url_zevenet' );
	my $subkeyid = "$openssl x509 -in $cert_path -noout -text | $grep \"$keyid\"";
	my $file     = &getGlobalConfiguration( 'apt_source_zevenet' );
	my $apt_conf_file = &getGlobalConfiguration( 'apt_conf_file' );
	my $gpgkey        = &getGlobalConfiguration( 'gpg_key_zevenet' );
	my $aptget_bin    = &getGlobalConfiguration( 'aptget_bin' );
	my $aptkey_bin    = &getGlobalConfiguration( 'aptkey_bin' );
	my $wget          = &getGlobalConfiguration( 'wget' );
	my $distribution  = "buster";
	my $kernel        = "4.19-amd64";

	&zenlog( "Configuring the APT repository", "info", "SYSTEM" );

	# Function call to configure proxy (Zevenet::SystemInfo)
	&setEnv();

	# command to check keyid
	# do not use the logAndRun function to obfuscate the signing cert keyid
	my $err = system ( $subkeyid );
	if ( $err )
	{
		&zenlog( "Keyid is not correct", "error", "apt" );
		return 1;
	}

	my $serial    = &getAPTSerial();
	my $userAgent = &getAPTUserAgent( $serial );
	return 1 if ( $serial eq '' or $userAgent eq '' );

	# adding key
	my $error = &logAndRun(
		"$wget --no-check-certificate -T5 -t1 --header=\"User-Agent: $serial\" -O - https://$host/ee/$gpgkey | $aptkey_bin add -"
	);
	if ( $error )
	{
		&zenlog( "Error connecting to $host, $gpgkey couldn't be downloaded",
				 "error", "apt" );
		return 0;
	}

	# configuring user-agent
	open ( my $fh, '>', $apt_conf_file )
	  or die "Could not open file '$apt_conf_file' $!";
	print $fh "Acquire { http::User-Agent \"$userAgent\"; };\n";
	print $fh "Acquire::http::proxy \"\/\";\n";
	print $fh "Acquire::https::proxy \"\/\";\n";
	close $fh;

	&setAPTProxy();

	# get the kernel version
	my $kernelversion = &getKernelVersion();

	# configuring repository
	open ( my $FH, '>', $file ) or die "Could not open file '$file' $!";

	if ( $kernelversion =~ /^4.19/ )
	{
		print $FH "deb https://$host/ee/v6/$kernel $distribution main\n";

		#print $FH "deb https://$host/ee/zcmc $distribution main\n";
	}
	else
	{
		&zenlog( "The kernel version is not valid, $kernelversion", "error", "apt" );
		$error = 1;
	}

	close $fh;

	if ( !$error )
	{
		# update repositories
		$error = &logAndRun( "$aptget_bin update" );
	}

	return 0;
}

=begin nd
Function: getAPTUpdatesList

    It returns information about the status of the system regarding updates.
    This information is parsed from a file

Parameters:

Returns:
	Hash ref -
		{
			 'message'    := message with the instructions to update the system
			 'last_check' := date of the last time that checkupgrades (or apt-get) was executed
			 'status'     := information about if there is pending updates.
			 'number'     := number of packages pending of updating
			 'packages'   := list of packages pending of updating
		};

=cut

sub getAPTUpdatesList
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $package_list = &getGlobalConfiguration( 'apt_outdated_list' );
	my $message_file = &getGlobalConfiguration( 'apt_msg' );

	my @pkg_list = ();
	my $msg;
	my $date   = "";
	my $status = "unknown";
	my $install_msg =
	  "To upgrade the system, please, execute in a shell the following command:
	'checkupgrades -i'";

	my $fh = &openlock( $package_list, '<' );
	if ( $fh )
	{
		@pkg_list = split ( ' ', <$fh> );
		close $fh;

		# remove the first item
		shift @pkg_list if ( $pkg_list[0] eq 'Listing...' );
	}

	$fh = &openlock( $message_file, '<' );
	if ( $fh )
	{
		$msg = <$fh>;
		close $fh;

		if ( $msg =~ /last check at (.+) -/ )
		{
			$date   = $1;
			$status = "Updates available";
		}
		elsif ( $msg =~ /Zevenet Packages are up-to-date/ )
		{
			$status = "Updated";
		}
	}

	return {
			 'message'    => $install_msg,
			 'last_check' => $date,
			 'status'     => $status,
			 'number'     => scalar @pkg_list,
			 'packages'   => \@pkg_list
	};
}

=begin nd
Function: getAPTConfig

    It validates if the APT is properly configured.

Parameters:

Returns:
	Integer - error code, 0 on success or another value on failure

=cut

sub getAPTConfig
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $file          = &getGlobalConfiguration( 'apt_source_zevenet' );
	my $apt_conf_file = &getGlobalConfiguration( 'apt_conf_file' );
	use File::Grep;

	if ( !-e $file or !-e $apt_conf_file )
	{
		&zenlog( "APT config files don't exist", "error", "apt" );
		return 1;
	}

	my $userAgent = &getAPTUserAgent();

	if (    ( !fgrep { /zevenet/ } $file )
		 or ( !fgrep { /http::User-Agent\s+\"$userAgent\"/ } $apt_conf_file ) )
	{
		&zenlog( "APT config is not done properly", "error", "apt" );
		return 1;
	}

	return 0;
}

=begin nd
Function: setCheckUpgradeAPT

    This function is used by checkupgrade in order to re-configre APT after any
    certificate key upload process

Parameters:

Returns:
	none - .

=cut

sub setCheckUpgradeAPT
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	if ( &getAPTConfig != 0 )
	{
		&setAPTRepo();
	}
}

=begin nd
Function: uploadAPTIsoOffline

	Store an uploaded ISO for offline updates.

Parameters:
	upload_filehandle - File handle or file content.

Returns:
	2     - The file is not a ISO
	1     - on failure.
	0 - on success.

=cut

sub uploadAPTIsoOffline
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $upload_filehandle = shift;

	my $error;
	my $dir              = &getGlobalConfiguration( 'update_dir' );
	my $file_bin         = &getGlobalConfiguration( 'file_bin' );
	my $checkupgrade_bin = &getGlobalConfiguration( 'checkupgrades_bin' );
	my $filepath         = "$dir/iso.tmp";

	mkdir $dir if !-d $dir;

	if ( open ( my $disk_fh, '>', $filepath ) )
	{
		binmode $disk_fh;

		use MIME::Base64 qw( decode_base64 );
		print $disk_fh decode_base64( $upload_filehandle );

		close $disk_fh;
	}
	else
	{
		&zenlog( "The file $filepath could not be created", 'error', 'apt' );
		return 1;
	}

	if ( &logAndRun( "$file_bin $filepath | $grep ISO" ) )
	{
		&zenlog( "The uploaded ISO doesn't look a valid ISO", 'error', 'apt' );
		unlink $filepath;
		return 2;
	}

	rename $filepath, "$dir/update.iso";

	# execute checkupgrades
	$error = &logAndRun( "$checkupgrade_bin" );

	return $error;
}

=begin nd
Function: setAPTProxy

        Sets http_proxy and https_proxy variables in the APT conf

Parameters:


Returns:

=cut

sub setAPTProxy
{
	&zenlog( __FILE__ . ":" . __LINE__ . ":" . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );

	my $http_proxy    = &getGlobalConfiguration( 'http_proxy' );
	my $https_proxy   = &getGlobalConfiguration( 'https_proxy' );
	my $apt_conf_file = &getGlobalConfiguration( 'apt_conf_file' );

	use Zevenet::Lock;
	&ztielock( \my @apt_conf, $apt_conf_file );
	foreach my $line ( @apt_conf )
	{
		if ( $line =~ /^Acquire::http::proxy/ )
		{
			$line = "Acquire::http::proxy \"$http_proxy\/\";\n";
		}
		if ( $line =~ /Acquire::https::proxy/ )
		{
			$line = "Acquire::https::proxy \"$https_proxy\/\";\n";
		}
	}
	untie @apt_conf;
}
1;
