#!/usr/bin/perl

use feature 'say';
use Tie::File;
use File::Basename;
use constant BASENAME => basename $0;
require "/usr/local/zenloadbalancer/config/global.conf";
require "/usr/local/zenloadbalancer/www/functions.cgi";
my $BASENAME = basename $0;

&zenlog("Running $BASENAME...");

# check if fwmarks file exist
if ( !-e $fwmarksconf )
{
	&zenlog("$BASENAME: File $fwmarksconf not found. Nothing to be migrated.");
	exit 0;
}

open my $input_file, '<', "$fwmarksconf" or die "Cannot open $fwmarksconf: $!";
my $decimal_found = grep { !/^0x... \/\/ / } <$input_file>; # FIXME

# check if there are decimal tags to be fixed
if ( $decimal_found == 0 )
{
	&zenlog("$BASENAME: File $fwmarksconf has no tags to be migrated.");
	exit 0;
}

# set cursor at the begining of file
seek ( $input_file, 0, SEEK_SET );

# collect hexadecimal marks
#
my @marks;

while ( my $line = <$input_file> )
{
	# skip hexadecimal tags
	if ( $line =~ /^0x... \/\/ / )
	{
		my ($tag, undef, $comment) = split ' ', $line;
		my $farm_name = ( split '_', $comment )[1];
		push @marks, $tag;
	}
}

# get the latest hexagecimal tag used, and decimal value
@marks = sort @marks;
my $last_hex_tag = $marks[-1];
my $last_dec_tag = hex $last_hex_tag;
#~ print "$last_hex_tag\n";
#~ print "$last_dec_tag\n";

# Get L4 farm names
#
my @l4_farmnames;

opendir my $cfg_dirh, $configdir or die $!;
while ( my $file = readdir $cfg_dirh )
{
	if ( $file =~ /_l4xnat\.cfg$/ )
	{
		my $farm_name = ( split '_l4xnat.cfg', $file )[0];
		push ( @l4_farmnames, $farm_name );
	}
}

#~ say "farms found: @l4_farmnames";

# Stop L4 farms
#
foreach my $farm_name ( @l4_farmnames )
{
	my $boot_status = &getL4FarmBootStatus($farm_name);

	if ($boot_status eq 'up')
	{
		my $status = &_runL4FarmStop( $farm_name, 'false' );
		
		if ( defined $status && $status == 0 )
		{
			&zenlog("$BASENAME: $farm_name stopped");
		}
		else
		{
			&zenlog("$BASENAME: failed to stop $farm_name");
		}
	}
}
# flush mangle and nat tables to make sure they are clean
system("$iptables -t nat -F");
system("$iptables -t mangle -F");


# Make new fwmarks file
#
seek ( $input_file, 0, SEEK_SET );
open my $output_file, '>', "$fwmarksconf.tmp"
  or die "Cannot open $fwmarksconf.tmp: $!";

# rewrite fwmarks file
while ( my $line = <$input_file> )
{
	# keep hexadecimal tags in the new file
	if ( $line =~ /^0x... \/\/ / )
	{
		print $output_file "$line";
		next;
	}

	# fix decimal tags
	if ( $line =~ /^... \/\/ / )
	{
		my ( $mark, $farm_comment ) = split " // ", $line;
		my $hex_mark = sprintf ( "0x%x", $mark );
		chomp ( $farm_comment );

		my $farm_name = ( split '_', $farm_comment )[1];

		if ( grep {/^$farm_name$/} @l4_farmnames )
		{
			# get ready for next tag
			$last_dec_tag++;
			$last_hex_tag = sprintf ( "0x%x", $last_dec_tag );

			&zenlog("$BASENAME: Migrating tag $mark to $last_hex_tag for farm $farm_name.");

			# Fix fwmarks line
			#
			print $output_file "$last_hex_tag // FARM_${farm_name}_\n";

			# Fix L4 farm file
			#
			my $farm_filename = "${farm_name}_l4xnat.cfg";
			tie my @farm_file, 'Tie::File', "$configdir\/$farm_filename"
			  or die "Cannot open $farm_filename: $!";

			foreach my $line ( @farm_file )
			{
				$line =~ s/;$hex_mark;/;$last_hex_tag;/ if $line =~ /;$hex_mark;/;
			}

			close @farm_file;
		}
	}
}

close $input_file;
close $output_file;

# Replace fwmarks file
#
#~ rename "$fwmarksconf", "$fwmarksconf.bkp";
rename "$fwmarksconf.tmp", "$fwmarksconf";

# Start L4 farms
#
foreach my $farm_name ( @l4_farmnames )
{
	my $boot_status = &getL4FarmBootStatus($farm_name);

	if ($boot_status eq 'up')
	{
		my $status = &_runL4FarmStart( $farm_name, 'false' );
		
		if ( defined $status && $status == 0 )
		{
			&zenlog("$BASENAME: $farm_name started");
		}
		else
		{
			&zenlog("$BASENAME: failed to start $farm_name");
		}
	}
}

&zenlog("Finished running $BASENAME");
