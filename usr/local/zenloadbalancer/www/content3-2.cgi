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
print "<div class=\"grid_6\"><h1>Settings :: Interfaces</h1></div>\n";

####################################
# CLUSTER STATUS
####################################
&getClusterStatus();

use IO::Socket;
use IO::Interface qw(:flags);
use Tie::File;

# action edit interface
if ( $action eq "editif" )
{
	require "./content3-21.cgi";
}

# action Save Config
elsif ( $action eq "Save Config" )
{
	$swaddif = "true";

	# check all possible errors
	# check if the interface is empty
	if ( $if =~ /^$/ )
	{
		&errormsg( "Interface name can not be empty" );
		$swaddif = "false";
	}

	# check if the new newip is correct
	if ( &ipisok( $newip ) eq "false" )
	{
		&errormsg( "IP Address $newip structure is not ok" );
		$swaddif = "false";
	}

	# check if the new netmask is correct, if empty don't worry
	if ( $netmask !~ /^$/ && &ipisok( $netmask ) eq "false" )
	{
		&errormsg( "Netmask address $netmask structure is not ok" );
		$swaddif = "false";
	}

	# check if the new gateway is correct, if empty don't worry
	if ( $gwaddr !~ /^$/ && &ipisok( $gwaddr ) eq "false" )
	{
		&errormsg( "Gateway address $gwaddr structure is not ok" );
		$swaddif = "false";
	}

	# end check, if all is ok
	if ( $swaddif eq "true" )
	{
		if ( $if =~ /\:/ )
		{
			&writeConfigIf( $if, "$if\:$newip\:$netmask\:$status\:\:" );
		}
		else
		{
			&writeRoutes( $if );
			&writeConfigIf( $if, "$if\:\:$newip\:$netmask\:$status\:$gwaddr\:" );
		}

		&successmsg( "All is ok, saved $if interface config file" );
	}
	else
	{
		&errormsg( "A problem detected editing or saving $if interface" );
	}
}

# action Save & Up!
elsif (    $action eq "Save & Up!"
		|| $action eq "addvip2"
		|| $action eq "addvlan2" )
{
	$swaddif = "true";

	# check all possible errors
	# check if the interface is empty
	if ( $if =~ /^$/ )
	{
		&errormsg( "Interface name can not be empty" );
		$swaddif = "false";
	}

	if ( $if =~ /\s+/ )
	{
		&errormsg( "Interface name is not valid" );
		$swaddif = "false";
	}

	if ( $action eq "addvlan2" && &isnumber( $if ) eq "false" )
	{
		&errormsg( "Invalid vlan tag value, it must be a numeric value" );
		$swaddif = "false";
	}

	if ( $action eq "addvip2" )
	{
		$if = "$toif\:$if";
	}

	if ( $action eq "addvlan2" )
	{
		$if = "$toif\.$if";
	}

	if ( $action eq "addvip2" || $action eq "addvlan2" )
	{
		$exists = &ifexist( $if );
		if ( $exists eq "true" )
		{
			&errormsg( "Network interface $if already exists." );
			$swaddif = "false";
		}
	}

	# check if the new newip is correct
	if ( &ipisok( $newip ) eq "false" )
	{
		&errormsg( "IP Address $newip structure is not ok" );
		$swaddif = "false";
	}
	
	# check if the new ip is already in use
	my @activeips = &listallips();
	for my $ip ( @activeips )
	{
		if ( $ip eq $newip )
		{
			&errormsg( "IP Address $newip is already in use, please insert a valid IP." );
			$swaddif = "false";
		}
	}

	# check if the new netmask is correct, if empty don't worry
	if ( $netmask !~ /^$/ && &ipisok( $netmask ) eq "false" )
	{
		&errormsg( "Netmask address $netmask structure is not ok" );
		$swaddif = "false";
	}

	# check if the new gateway is correct, if empty don't worry
	if ( $gwaddr !~ /^$/ && &ipisok( $gwaddr ) eq "false" )
	{
		&errormsg( "Gateway address $gwaddr structure is not ok" );
		$swaddif = "false";
	}

	# end check, if all is ok
	if ( $swaddif eq "true" )
	{
		$exists = &ifexist( $if );

		if ( $exists eq "false" )
		{
			&createIf( $if );
		}

		&delRoutes( "local", $if );
		&logfile( "running '$ifconfig_bin $if $newip netmask $netmask' " );
		@eject = `$ifconfig_bin $if $newip netmask $netmask 2> /dev/null`;
		&upIf( $if );
		$state = $?;

		if ( $state == 0 )
		{
			$status = "up";
			&successmsg( "Network interface $if is now UP" );
		}

		if ( $if =~ /\:/ )
		{
			&writeConfigIf( $if, "$if\:$newip\:$netmask\:$status\:\:" );
		}
		else
		{
			&writeRoutes( $if );
			&writeConfigIf( $if, "$if\:\:$newip\:$netmask\:$status\:$gwaddr\:" );
		}

		&applyRoutes( "local", $if, $gwaddr );
		&successmsg( "All is ok, saved $if interface config file" );
	}
	else
	{
		&errormsg( "A problem detected configurating $if interface" );
	}
}

# action adddvip2 if ok add if not ok error and set variables
#print "el bc es $bc, la nueva ip es $newip con la ip $toip y la netmask es $netmask";
elsif ( $action eq "deleteif" )
{
	if ( $if !~ /^$/ )
	{
		&delRoutes( "local", $if );
		&downIf( $if );
		&delIf( $if );
		&successmsg( "Interface $if is now DELETED and DOWN" );
	}
	else
	{
		&errormsg( "The interface is not detected" );
	}
}
elsif ( $action eq "upif" )
{
	if ( $if !~ /^$/ )
	{
		$exists = &ifexist( $if );
		my $error = "false";

		if ( $exists eq "false" )
		{
			&createIf( $if );
		}

		# open config file to get the interface parameters
		tie @array, 'Tie::File', "$configdir/if_$if\_conf", recsep => ':';
		
		# check if the ip is already in use
		my @activeips = &listallips();
		for my $ip ( @activeips )
		{
			if ( $ip eq @array[2] )
			{
				&errormsg( "Interface $if is not UP, IP Address @array[2] is already in use." );
				$error = "true";
			}
		}
		
		# check there is no error
		if ( $error eq "false" )
		{
			&logfile( "running '$ifconfig_bin $if @array[2] netmask @array[3]' " );
			@eject = `$ifconfig_bin $if @array[2] netmask @array[3] 2> /dev/null`;
			&upIf( $if );
			$state = $?;

			if ( $state == 0 )
			{
				@array[4] = "up";
				&successmsg( "Network interface $if is now UP" );
			}
			else
			{
				&errormsg( "Interface $if cannot be UP, bad configuration or duplicate ip" );
			}

			&applyRoutes( "local", $if, @array[5] );
		}
		
		# close config file
		untie @array;
	}
	else
	{
		&errormsg( "The interface is not detected" );
	}
}
elsif ( $action eq "downif" )
{
	tie @array, 'Tie::File', "$configdir/if_$if\_conf", recsep => ':';
	&delRoutes( "local", $if );
	&downIf( $if );

	if ( $? == 0 )
	{
		@array[4] = "down";
		&successmsg( "Interface $if is now DOWN" );
	}
	else
	{
		&errormsg(
			  "Interface $if is not DOWN, check if any Farms is running over this interface"
		);
	}

	untie @array;
}
elsif ( $action eq "editgw" )
{
	if ( $gwaddr !~ /^$/ )
	{
		&applyRoutes( "global", $if, $gwaddr );
		$state = $?;

		# TODO write def gw in file
		$action = "";

		if ( $state == 0 )
		{
			&successmsg( "The default gateway has been changed successfully" );
		}
		else
		{
			&errormsg( "The default gateway hasn't been changed" );
		}
	}
}
elsif ( $action eq "deletegw" )
{
	&delRoutes( "global", $if );
	$state  = $?;
	$action = "";

	if ( $state == 0 )
	{
		&successmsg( "The default gateway has been deleted successfully" );
	}
	else
	{
		&errormsg( "The default gateway hasn't been deleted" );
	}
}

#list interfaces
my $s = IO::Socket::INET->new( Proto => 'udp' );
my @interfaces = $s->if_list;
my @interfacesdw;

print "
               <div class=\"box grid_12\">
                 <div class=\"box-head\">
                       <span class=\"box-icon-24 fugue-24 server\"></span>       
                       <h2>Interfaces table</h2>
                 </div>
                 <div class=\"box-content no-pad\">
		<ul class=\"table-toolbar\"></ul>
       ";

# dont loose the css of form
if ( $action eq "addvip" or $action eq "addvlan" )
{
	print "<form method=\"post\" name=\"interfaces\" action=\"index.cgi\">";
}

print "<table id=\"interfaces-table\" class=\"display\">";
print "<thead>";
print "<tr>";
print "<th>Name</th>";
print "<th>Addr</th>";
print "<th>HWaddr</th>";
print "<th>Netmask</th>";
print "<th>Gateway</th>";
print "<th>Status</th>";
print "<th>Actions</th>";
print "</tr>";
print "</thead>";
print "<tbody>";

# Calculate cluster and gui ips
$clrip = &getClusterRealIp();
$guiip = &GUIip();
$clvip = &getClusterVirtualIp();

#check interfaces status

for my $if ( @interfaces )
{
	if ( $if !~ /^lo|sit0/ )
	{
		my $flags = $s->if_flags( $if );
		$hwaddr  = $s->if_hwaddr( $if );
		$status  = "";
		$ip      = "";
		$netmask = "";
		$gw      = "";
		$link    = "on";

		if ( $flags & IFF_UP )
		{
			$status  = "up";
			$ip      = $s->if_addr( $if );
			$netmask = $s->if_netmask( $if );
			$bc      = $s->if_broadcast( $if );
			$gw      = &getDefaultGW( $if );
		}
		else
		{
			$status = "down";

			if ( -e "$configdir/if_$if\_conf" )
			{
				tie @array, 'Tie::File', "$configdir/if_$if\_conf", recsep => ':';
				$ip      = $array[2];
				$netmask = $array[3];
				$gw      = $array[5];
				untie @array;
			}
		}

		if ( !( $flags & IFF_RUNNING ) && ( $flags & IFF_UP ) )
		{
			$link = "off";
		}

		if ( !$netmask ) { $netmask = "-"; }
		if ( !$ip )      { $ip      = "-"; }
		if ( !$hwaddr )  { $hwaddr  = "-"; }
		if ( !$gw )      { $gw      = "-"; }

		# Physical interfaces are shown always, virtual or vlan interfaces
		# only shows if are configured
		if (    ( $if !~ /\:/ && $if !~ /\./ )
			 || ( $status eq "up" )
			 || ( -e "$configdir/if_$if\_conf" ) )
		{
			if ( ( $if eq $toif ) && ( $action eq "editif" ) )
			{
				print "<tr class=\"selected\">";
			}
			else
			{
				print "<tr>";
			}

			print "<td>$if";

			if ( $ip eq $clrip || $ip eq $clvip )
			{
				print
				  "&nbsp;&nbsp;<i class=\"fa fa-database action-icon fa-fw\" title=\"The cluster service interface has to be changed or disabled before to be able to modify this interface\"></i>";
			}

			if ( $ip eq $guiip )
			{
				print
				  "&nbsp;&nbsp;<i class=\"fa fa-home action-icon fa-fw\" title=\"The GUI service interface has to be changed before to be able to modify this interface\"></i>";
			}

			print "</td>";
			print "<td>$ip</td>";
			print "<td>$hwaddr</td>";
			print "<td>$netmask</td>";
			my $phif = $if;

			if ( $if =~ /\:/ )
			{
				my @splif = split ( ":", $if );
				$phif = $splif[0];
			}

			my $ifused = &uplinkUsed( $phif );

			if ( $ifused eq "false" )
			{
				print "<td class=\"aligncenter\">$gw</td>";
			}
			else
			{
				print
				  "<td class=\"aligncenter\">&nbsp;&nbsp;<i class=\"fa fa-lock action-icon fa-fw\" title=\"A datalink farm is locking the gateway of this interface\"></td>";
			}

			if ( $status eq "up" )
			{
				print
				  "<td class=\"aligncenter\"><img src=\"img/icons/small/start.png\" title=\"up\">";
			}
			else
			{
				print
				  "<td class=\"aligncenter\"><img src=\"img/icons/small/stop.png\" title=\"down\">";
			}

			if ( $link eq "off" )
			{
				print
				  "&nbsp;&nbsp;<img src=\"img/icons/small/disconnect.png\" title=\"No link\">";
			}

			print "</td>";
			&createmenuif( $if, $id, $configured, $status );
			print "</tr>";
		}

		if ( ( $action eq "addvip" || $action eq "addvlan" ) && ( $if eq $toif ) )
		{
			print "<tr class=\"selected\">";

			if ( $action eq "addvip" )
			{
				print "<form method=\"post\" action=\"index.cgi\" class=\"myform\">";
				print
				  "<td>$if:<input type=\"text\" maxlength=\"10\" size=\"12\"  name=\"if\" value=\"$ifname\"></td>";
			}
			elsif ( $action eq "addvlan" )
			{
				print "<form method=\"post\" action=\"index.cgi\" class=\"myform\">";
				print
				  "<td>$if.<input type=\"text\" maxlength=\"10\" size=\"10\"  name=\"if\" value=\"$ifname\"></td>";
			}

			print "<td><input type=\"text\" name=\"newip\" size=\"14\"> </td>";
			print "<input type=\"hidden\" name=\"id\" value=\"3-2\">";
			print "<input type=\"hidden\" name=\"toif\" value=\"$if\">";
			print "<input type=\"hidden\" name=\"status\" value=\"$status\">";
			print "<td>$hwaddr</td>";

			if ( $action eq "addvip" )
			{
				print "<input type=\"hidden\" name=\"netmask\" value=\"$netmask\" size=\"14\">";
				print "<td>$netmask</td>";
				my @splif = split ( ":", $if );
				my $ifused = &uplinkUsed( $splif[0] );

				if ( $ifused eq "false" )
				{
					print "<td>$gateway</td>";
				}
				else
				{
					print
					  "<td class=\"aligncenter\">&nbsp;&nbsp;<i class=\"fa fa-lock action-icon fa-fw\" title=\"A datalink farm is locking the gateway of this interface\"></td>";
				}

				print "<input type=\"hidden\" name=\"action\" value=\"addvip2\">";
			}
			elsif ( $action eq "addvlan" )
			{
				print
				  "<td><input type=\"text\" size=\"14\"  name=\"netmask\" value=\"\" ></td>";
				print "<td><input type=\"text\" size=\"14\"  name=\"gwaddr\" value=\"\" ></td>";
				print "<input type=\"hidden\" name=\"action\" value=\"addvlan2\">";
			}

			print "<td class=\"aligncenter\">Adding</td>";
			print "<td>";

			if ( $action eq "addvip" )
			{
				print "
				<button type=\"submit\" class=\"myicons\" title=\"save virtual interface\">
					<i class=\"fa fa-floppy-o fa-fw action-icon\"></i>
				</button>
				</form>";
			}
			elsif ( $action eq "addvlan" )
			{
				print "
				<button type=\"submit\" class=\"myicons\" title=\"save vlan interface\">
					<i class=\"fa fa-floppy-o fa-fw action-icon\"></i>
				</button>
				</form>";
			}

			print "
			<form method=\"post\" action=\"index.cgi\" class=\"myform\">
			<button type=\"submit\" class=\"myicons\" title=\"cancel operation\">
				<i class=\"fa fa-sign-out fa-fw action-icon\"></i>
			</button>
			<input type=\"hidden\" name=\"id\" value=\"$id\">
			</form>";
			print "</td>";
			print "</tr>";
		}

		# List configured interfaces with down state
		opendir ( DIR, "$configdir" );
		@files = grep ( /^if\_$if.*\_conf$/, readdir ( DIR ) );
		closedir ( DIR );

		foreach my $file ( @files )
		{
			my @filename = split ( '_', $file );
			$iff = $filename[1];

			if ( !( grep $_ eq $iff, @interfaces ) && !( grep $_ eq $iff, @interfacesdw ) )
			{
				open FI, "$configdir/$file";

				while ( my $line = <FI> )
				{
					my @s_line = split ( ':', $line );
					$ifnamef = $s_line[1];
					$toipv   = $s_line[2];
					$netmask = $s_line[3];
					$status  = "down";
					$gw      = $s_line[5];
					close FI;

					if ( ( $iff eq $toif ) && ( $action eq "editif" ) )
					{
						print "<tr class=\"selected\">";
					}
					else
					{
						print "<tr>";
					}

					print "<td>$iff";

					if ( $toipv eq $clrip || $toipv eq $clvip )
					{
						print
						  "&nbsp;&nbsp;<i class=\"fa fa-database action-icon fa-fw\" title=\"The cluster service interface has to be changed or disabled before to be able to modify this interface\"></i>";
					}

					if ( $toipv eq $guiip )
					{
						print
						  "&nbsp;&nbsp;<i class=\"fa fa-home action-icon fa-fw\" title=\"The GUI service interface has to be changed before to be able to modify this interface\"></i>";
					}

					print "</td>";
					print "<td>$toipv</td>";
					print "<input type=\"hidden\" name=\"id\" value=\"3-2\">";
					print "<td>$hwaddr</td>";
					print "<td>$netmask</td>";
					print "<td class=\"aligncenter\">$gw</td>";

					if ( $status eq "up" )
					{
						print
						  "<td class=\"aligncenter\"><img src=\"img/icons/small/start.png\" title=\"up\">";
					}
					else
					{
						print
						  "<td class=\"aligncenter\"><img src=\"img/icons/small/stop.png\" title=\"down\">";
					}

					if ( $link eq "off" )
					{
						print
						  "&nbsp;&nbsp;<img src=\"img/icons/small/disconnect.png\" title=\"No link\">";
					}

					print "</td>";
					&createmenuif( $iff, $id, $configured, $status );
					print "</tr>";
				}

				# No show this interface again
				push ( @interfacesdw, $iff );
			}
		}
	}
}

if ( $action eq "addvip" or $action eq "addvlan" )
{
	print "</form>";
}

print "</tbody>";
print "</table>";
print "</div></div>";

#### Default GW section

if ( $action eq "editgw" )
{
	print
	  "<form name=\"gatewayform\" method=\"post\" action=\"index.cgi\" class=\"myform\">";
}

print "
               <div class=\"box grid_12\">
                 <div class=\"box-head\">
                       <span class=\"box-icon-24 fugue-24 home\"></span>         
                       <h2>Default gateway</h2>
                 </div>
                 <div class=\"box-content no-pad\">
       ";

print "<table class=\"display\">";
print "<thead>";
print "<tr>";
print "<th>Addr</th>";
print "<th>Interface</th>";
print "<th>Actions</th>";
print "</tr>";
print "</thead>";
print "<tbody>";

if ( $action eq "editgw" )
{
	print "<tr class=\"selected\"><td>";
	print "<input type=\"text\" size=\"14\" name=\"gwaddr\" value=\"";
	print &getDefaultGW();
	print "\">";
	print "</td><td>";
	print "<select name=\"if\">";
	$iface   = &getIfDefaultGW();
	$isfirst = "true";

	for my $if ( @interfaces )
	{
		my $flags = $s->if_flags( $if );

		if ( ( $if !~ /^lo|sit|.*\:.*/ ) && ( $flags & IFF_RUNNING ) )
		{
			print "<option value=\"$if\" ";

			if ( ( $iface eq "" && $isfirst eq "true" ) || $iface eq $if )
			{
				$isfirst = "false";
				print "selected";
			}

			print ">$if</option>";
		}
	}

	print "</select>";
	print "<input type=\"hidden\" name=\"id\" value=\"$id\">";
}
else
{
	print "<tr><td>";
	print &getDefaultGW();
	print "</td><td>";
	print &getIfDefaultGW();
}
print "</td><td>";
&createmenuGW( $id, $action );

print "</td></tr>";
print "</tbody>";
print "</table>";
print "</div></div>";

print "
<script>
\$(document).ready(function() {
    \$('#interfaces-table').DataTable( {
        \"bJQueryUI\": true,     
        \"sPaginationType\": \"full_numbers\",
		\"aLengthMenu\": [
			[10, 25, 50, 100, 200, -1],
			[10, 25, 50, 100, 200, \"All\"]
		],
		\"iDisplayLength\": 10
    });
} );
</script>
";

