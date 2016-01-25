###############################################################################
#
#     Zen Load Balancer Software License
#     This file is part of the Zen Load Balancer software package.
#
#     Copyright (C) 2014 SOFINTEL IT ENGINEERING SL, Sevilla (Spain)
#
#     This library is free software; you can redistribute it and/or modify it
#     under the terms of the GNU Lesser General Public License as published
#     by the Free Software Foundation; either version 2.1 of the License, or
#     (at your option) any later version.
#
#     This library is distributed in the hope that it will be useful, but
#     WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser
#     General Public License for more details.
#
#     You should have received a copy of the GNU Lesser General Public License
#     along with this library; if not, write to the Free Software Foundation,
#     Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
###############################################################################

use Sys::Hostname;
my $host = hostname();

print "
  <!--- CONTENT AREA -->
  <div class=\"content container_12\">
";

####################################
# CLUSTER INFO
####################################
&getClusterInfo();

###################################
#BREADCRUMB
###################################
print "<div class=\"grid_6\"><h1>Settings :: Server</h1></div>\n";

####################################
# CLUSTER STATUS
####################################
&getClusterStatus();

#process changes in global.conf when action=Modify

if ( $action =~ /^Modify$/ )
{
	#Get actual values
	$nextline = "false";
	open FR, "$globalcfg";
	my $i      = 0;    #Counter
	my $linea  = 0;
	my $flag   = 0;    #For showing changes
	my @linea  = ();
	my @values = ();
	while ( <FR> )
	{

		if ( $_ =~ /^#::INI/ )
		{
			$linea = $_;
			$linea =~ s/^#::INI//;
			my @actionform = split ( /\ /, $linea );
		}
		if ( $_ =~ /^#\./ )
		{
			$nextline = "true";
			$linea    = $_;
			$linea =~ s/^#\.//;
		}

		if ( $_ =~ /^\$/ && $nextline eq "true" )
		{
			$nextline = "false";
			@linea = split ( /=/, $_ );
			@linea[1] =~ s/"||\;//g;
			@linea[0] =~ s/^\$//g;
			chomp ( @linea[0] );
			chomp ( @linea[1] );
			if (    @linea[0] =~ /timeouterrors/
				 or @linea[0] =~ /ntp/
				 or @linea[0] =~ /zenrsync/ )
			{
				@values[$i]     = @linea[0];
				@values[$i + 1] = @linea[1];
				$i              = $i + 2;
			}
		}

	}
	close FR;

	#Modify Time Out Execution
	if ( $touterr ne @values[1] )
	{
		use Tie::File;
		tie @array, 'Tie::File', "$globalcfg";
		for ( @array )
		{
			s/\$$var1.*/\$$var1=\"$touterr\";/g;
		}
		untie @array;
		&successmsg( "Time out execution has been modified" );
	}

	#Modify Ntp Server
	if ( $ntp ne @values[3] )
	{
		use Tie::File;
		tie @array, 'Tie::File', "$globalcfg";
		for ( @array )
		{
			s/\$$var2.*/\$$var2=\"$ntp\";/g;
		}
		untie @array;
		&successmsg( "Ntp server has been modified" );
	}

	#Modify Rsync Replication Parameters
	if ( $zenrsync ne @values[5] )
	{
		use Tie::File;
		tie @array, 'Tie::File', "$globalcfg";
		for ( @array )
		{
			s/\$$var3.*/\$$var3=\"$zenrsync\";/g;
		}
		untie @array;
		&successmsg( "Rsync replication parameters have been modified" );
	}

	#dns modifications
	if ( $var eq "dns" )
	{
		print "var es $var";
		@dns = split ( "\ ", $line );
		open FW, ">$filedns";
		foreach $dnsserv ( @dns )
		{
			print FW "nameserver $dnsserv\n";
		}
		close FW;
	}
	if ( $var eq "mgwebip" || $var eq "mgwebport" )
	{
		&successmsg( "Changes OK, restart web service now" );
	}

	#actions with Modify buttom
}

#Modify Configuration
if ( $action eq "Modify Configuration" )
{
	#action Save DNS
	# if ( $var eq "Save DNS" )
	# {
	open FW, ">$filedns";
	print FW "$dnsserv";

	# &successmsg( "DNS saved" );
	close FW;

	# }

	#action Save APT
	# if ( $var eq "Save APT" )
	# {
	open FW, ">$fileapt";
	print FW "$aptrepo";

	# &successmsg( "APT saved" );
	close FW;

	# }

	#action save ip
	# if ( $action eq "Save IP" )
	# {
	use Tie::File;
	tie @array, 'Tie::File', "$confhttp";
	if ( $ipgui =~ /^\*$/ )
	{
		@array[1] = "#server!bind!1!interface = \n";
	}
	else
	{
		@array[1] = "server!bind!1!interface = $ipgui\n";
	}
	untie @array;

	# }

	#Change GUI https port
	# if ( $action eq "Change GUI https port" )
	# {
	&setGuiPort( $guiport, $confhttp );

	# }
	&successmsg( "Some changes were applied for Local configuration" );
}

#Restart GUI Server Button
if ( $action eq "Restart GUI Service" )
{
	if ( $pid = fork )
	{

		#$SIG{'CHLD'}='IGNORE';
		#print "Proceso de restart lanzado ...";
	}
	elsif ( defined $pid )
	{

		#$SIG{'CHLD'}=\&REAPER;
		#child
		#exec $MIGRASCRIPT,@args;
		system ( "/etc/init.d/cherokee restart > /dev/null &" );
		exit ( 0 );
	}
	if ( $ipgui =~ /^$/ )
	{
		$ipgui = &GUIip();
	}
	if ( $guiport =~ /^$/ )
	{
		$guiport = &getGuiPort( $confhttp );
	}
	if ( $ipgui =~ /\*/ )
	{
		&successmsg( "Restarted Service, access to GUI over any IP on port $guiport" );
	}
	else
	{
		&successmsg(
			"Restarted Service, access to GUI over $ipgui IP on port $guiport <a href=\"https:\/\/$ipgui:$guiport\/index.cgi?id=$id\">go here</a>"
		);
	}
}

#open glogal file config
$nextline = "false";
open FR, "$globalcfg";
while ( <FR> )
{
	if ( $_ =~ /^#::INI/ )
	{
		$linea = $_;
		$linea =~ s/^#::INI//;
		my @actionform = split ( /\ /, $linea );
		print "
                       <div class=\"box grid_12\">
                         <div class=\"box-head\">
                               <span class=\"box-icon-24 fugue-24 globe\"></span>        
                               <h2>$linea</h2>
                         </div>
                         <div class=\"box-content global-farm\">
		";
	}
	if ( $_ =~ /^#\./ )
	{
		$nextline = "true";
		print "<div class=\"form-row\">";
		$linea = $_;
		$linea =~ s/^#\.//;
		print "<p class=\"form-label\"><label>$linea</label></p>";
	}

	if ( $_ =~ /^\$/ && $nextline eq "true" )
	{
		$nextline = "false";
		my @linea = split ( /=/, $_ );
		@linea[1] =~ s/"||\;//g;
		@linea[0] =~ s/^\$//g;
		chomp ( @linea[1] );
		chomp ( @linea[0] );

		print "<form method=\"post\" action=\"index.cgi\">";
		print "<input type=\"hidden\" name=\"id\" value=\"3-1\">";
		print "<div class=\"form-item\">";
		if ( @linea[0] eq "timeouterrors" )
		{
			print
			  "<input type=\"number\" value=\"@linea[1]\" size=\"20\" name=\"touterr\" class=\"fixedwidth\"> ";
			print "<input type=\"hidden\" name=\"var1\" value=\"@linea[0]\">";
		}
		elsif ( @linea[0] eq "ntp" )
		{
			print
			  "<input type=\"text\" value=\"@linea[1]\" size=\"20\" name=\"ntp\" class=\"fixedwidth\"> ";
			print "<input type=\"hidden\" name=\"var2\" value=\"@linea[0]\">";
		}
		elsif ( @linea[0] eq "zenrsync" )
		{
			print
			  "<input type=\"text\" value=\"@linea[1]\" size=\"20\" name=\"zenrsync\" class=\"fixedwidth\"> ";
			print "<input type=\"hidden\" name=\"var3\" value=\"@linea[0]\">";
		}

		print "</div>";
		print "</div>";
	}

	if ( $_ =~ /^#::END/ )
	{
		print "<br>";
		print
		  "<input type=\"submit\" value=\"Modify\" name=\"action\" class=\"button grey\">";
		print "</form>";
		print "</div></div>";
	}
}

close FR;

#
#Local configuration
#

print "
       <div class=\"box grid_12\">
         <div class=\"box-head\">
               <span class=\"box-icon-24 fugue-24 server\"></span>       
               <h2>Local configuration</h2>
         </div>
         <div class=\"box-content global-farm\">
";

#
# Physical interface
#

open FR, "<$confhttp";

@file     = <FR>;
$hosthttp = @file[1];
close FR;

print "<div class=\"form-row\">";
print
  "<p class=\"form-label\"><b>Physical interface where is running GUI service. </b> If cluster is up you only can select \"--All interfaces--\" option, or \"the cluster interface\". Changes need restart GUI service.</p>";
print "<form method=\"post\" action=\"index.cgi\">";
print "<input type=\"hidden\" name=\"id\" value=\"3-1\">";

opendir ( DIR, "$configdir" );
@files = grep ( /^if.*/, readdir ( DIR ) );
closedir ( DIR );

@ipguic = split ( "=", @file[1] );
$hosthttp = @ipguic[1];
$hosthttp =~ s/\ //g;
chomp ( $hosthttp );

open FR, "<$filecluster";
@filecluster = <FR>;
close FR;
$lclusterstatus = @filecluster[2];
@lclustermember = split ( ":", @filecluster[0] );
chomp ( @lclustermember );
$lhost = @lclustermember[1];
$rhost = @lclustermember[3];
$lip   = @lclustermember[2];
$rip   = @lclustermember[4];
if ( $host eq $rhost )
{
	$thost = $rhost;
	$rhost = $lhost;
	$lhost = $thost;
	$tip   = $rip;
	$rip   = $lip;
	$lip   = $tip;
}

# Print "Zen cluster service is UP, Zen GUI should works over ip $lip";
print "<div class=\"form-item\">";
print "<select name=\"ipgui\" class=\"fixedwidth\">\n";

$existiphttp = "false";
if ( $hosthttp =~ /\*/ )
{
	print "<option value=\"*\" selected=\"selected\">--All interfaces--</option>";
	$existiphttp = "true";
}
else
{
	print "<option value=\"*\">--All interfaces--</option>";
}

if ( grep ( /UP/, $lclusterstatus ) )
{

	#cluster active you only can use all interfaces or cluster real ip
	if ( $hosthttp =~ /$lip/ )
	{
		print "<option value=\"$lip\" selected=\"selected\">*cluster $lip</option>";
		$existiphttp = "true";
	}
	else
	{
		print "<option value=\"$lip\">*cluster $lip</option>";
	}
}
else
{
	foreach $file ( @files )
	{
		if ( $file !~ /:/ )
		{
			open FI, "$configdir\/$file";
			@lines = <FI>;
			@line = split ( ":", @lines[0] );
			chomp ( @line );
			if ( @line[4] =~ /up/i )
			{
				chomp ( @line[2] );
				if ( $hosthttp =~ /@line[2]/ )
				{
					print
					  "<option value=\"@line[2]\" selected=\"selected\">@line[0] @line[2]</option>";
				}
				else
				{
					print "<option value=\"@line[2]\">@line[0] @line[2]</option>";
				}
			}

			close FI;
		}
	}

}

print "</select> ";
print "</div>\n";
print "</div>\n";

#
# HTTPS port for GUI interface
#
$guiport = &getGuiPort( $confhttp );
if ( $guiport =~ /^$/ )
{
	$guiport = 444;
}
else
{
	chomp ( $guiport );
}
print "<div class=\"form-row\">";
print
  "<p class=\"form-label\"><b>HTTPS Port where is running GUI service.</b> Default is 444. Changes need restart GUI service.</p>";

print "<div class=\"form-item\">";
print
  "<input type=\"number\" name=\"guiport\" class=\"fixedwidth\" value=\"$guiport\" size=\"12\"> ";

print "</div>\n";
print "</div>\n";

#
# DNS servers
#
print "<div class=\"form-row\">";
print "<p class=\"form-label\"><b>DNS servers</b></p>";

print "<div class=\"form-item\">";
print
  "<textarea name=\"dnsserv\" cols=\"30\" rows=\"2\" align=\"center\" class=\"fixedwidth\">";
open FR, "$filedns";
print <FR>;
print "</textarea> ";

print "</div>\n";
print "</div>\n";

print
  "<input type=\"submit\" value=\"Modify Configuration\" name=\"action\" class=\"button grey\">";
print
  "<input type=\"submit\" value=\"Restart GUI Service\" name=\"action\" class=\"button grey\">";

print "</form>";
print "</div></div></div>";

print "<br class=\"cl\">";
print "</div><!--Content END--></div></div>";

