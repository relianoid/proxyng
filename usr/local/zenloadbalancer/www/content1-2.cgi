#This cgi is part of Zen Load Balancer, is a Web GUI integrated with binary systems that
#create Highly Effective Bandwidth Managemen
#Copyright (C) 2010  Emilio Campos Martin / Laura Garcia Liebana
#
#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.

#You can read license.txt file for more information.

#Created by Emilio Campos Martin
#File that create the Zen Load Balancer GUI


#lateral menu
#print "
#<div id=\"page-wrapper\">
#  <div class=\"page\">
#";
#require "menu.cgi";

my $type = &getFarmType($farmname);

print "
    <!--Content INI-->
        <div id=\"page-content\">

                <!--Content Header INI-->";
                if ($farmname ne "" && $type != 1){
                        print "<h2>Manage::Farms\:\:$type\:\:$farmname</h2>";
                }else{
			if ($farmname ne ""){
	                        print "<h2>Manage::Farms::$farmname</h2>";
			} else {
        	                print "<h2>Manage::Farms</h2>";
			}
                }

print           "<!--Content Header END-->";

#evaluate the $action variable, used for manage forms
if ($action eq "addfarm" || $action eq "Save" || $action eq "Save & continue"){
	require "content1-21.cgi";
}

if ($action eq "deletefarm"){
	$stat = &runFarmStop($farmname,"true");
	if ($stat == 0){
		&successmsg("The Farm $farmname is now disabled");
	}

	$stat = &runFarmDelete($farmname);
	if ($stat == 0){
		&successmsg("The Farm $farmname is now deleted");
	} else {
		&successmsg("The Farm $farmname hasn't been deleted");
	}
}

if ($action eq "startfarm"){
	$stat = &runFarmStart($farmname,"true");
	if ($stat == 0){
		&successmsg("The Farm $farmname is now running");
		$stat = &getFarmGuardianStatus($farmname);
		if ($stat != 0){
			$stat = &runFarmGuardianStart($farmname,"");
			if ($stat == 0){
				&successmsg("The FarmGuardian of $farmname is now running");
			}
		}
	} else {
		&errormsg("The Farm $farmname isn't running, check if the IP address is up and the PORT is in use");
	}
}

if ($action eq "stopfarm"){
	$stat = &runFarmStop($farmname,"true");
	if ($stat == 0){
		&successmsg("The Farm $farmname is now disabled");
		$stat = &getFarmGuardianStatus($farmname);
		if ($stat != -1){
			$stat = &runFarmGuardianStop($farmname,"");
			if ($stat == 0){
				&successmsg("The FarmGuardian of $farmname is now stopped");
			}
		}
	} else {
		&errormsg("The Farm $farmname is not disabled");
	}
}

if ($action =~ "^editfarm" || $editfarm){
	if ($type == 1){
		&errormsg("Unknown farm type of $farmname");
	} else {
		$file = &getFarmFile($farmname);
		if ($type eq "tcp" || $type eq "udp"){
			require "content1-22.cgi";
		}
		if ($type eq "http" || $type eq "https"){
			require "content1-24.cgi";
		}
		if ($type eq "datalink"){
			require "content1-26.cgi";
		}
		if ($type eq "l4txnat" || $type eq "l4uxnat"){
			require "content1-28.cgi";
		}
	}
}

if ($action eq "managefarm"){
	$type = &getFarmType($farmname);
	if ($type == 1){
		&errormsg("Unknown farm type of $farmname");
	} else {
		$file = &getFarmFile($farmname);
		if ($type eq "tcp" || $type eq "udp"){
			require "content1-23.cgi";
		}
		if ($type eq "http" || $type eq "https"){
			require "content1-25.cgi";
		}
		if ($type eq "datalink"){
			require "content1-27.cgi";
		}
		if ($type eq "l4txnat" || $type eq "l4uxnat"){
			require "content1-29.cgi";
		}
	}
}

#list all farms configuration and status 
#first list all configuration files
@files = &getFarmList();
#print "<br class=\"cl\">";
$size = $#files + 1;
if ($size == 0){
	$action = "addfarm";
	$farmname = "";
	require "content1-21.cgi";
}

#table that print the info
#print "<div class=\"grid_8\">";
print "<div class=\"box-header\">Farms table</div>";
print "<div class=\"box table\">";

#para no perder el css de form
#if ( $action eq "addvip" )
#{
#print "<form method=\"get\" action=\"index.cgi\">";
#}

my @netstat = &getNetstat("atunp");
my $thereisdl = "false";

print "<table cellspacing=\"0\">";
print "<thead>";
print "<tr>";
print "<td width=85>Name</td>";
print "<td width=85>Virtual IP</td>";
print "<td>Virtual Port(s)</td>";
print "<td>Pending Conns</td>";
print "<td>Established Conns</td>";
print "<td>Closed Conns</td>";
print "<td>PID</td>";
print "<td>Status</td>";
print "<td>Profile</td>";
print "<td>Actions</td>";
print "</tr>";
print "</thead>";
print "<tbody>";

foreach $file (@files) {
	$name = &getFarmName($file);
	$type = &getFarmType($name);

	if ($type ne "datalink"){

		if ($farmname eq $name && $action ne "addfarm" && $action ne "Cancel"){
			print "<tr class=\"selected\">";
		} else {
			print "<tr>";
		}
		#print the farm description name
		print "<td>$name</td>";
		#print the virtual ip
		$vip = &getFarmVip("vip",$name);
		print "<td>$vip</td>";
		#print the virtual port where the vip is listening
		$vipp = &getFarmVip("vipp",$name);
		print "<td>$vipp</td>";
	
		#print global connections bar
		$pid = &getFarmPid($name);
		$status = &getFarmStatus($name);
		if ($status eq "up"){
			# SYN_RECV connections
			$synconns = &getFarmSYNConns($name,@netstat);
			print "<td> $synconns </td>";
		} else {
			print "<td>0</td>";
		}
		if ($status eq "up"){
			@gconns=&getFarmEstConns($name,@netstat);
			$global_conns = @gconns;
			print "<td>";
			print " $global_conns ";
			print "</td>";
		} else {
			print "<td>0</td>";
		}
		# TIME_WAIT connections
		$waitedconns = &getFarmTWConns($name,@netstat);
		print "<td> $waitedconns </td>";
		#print the pid of the process 
		if ($pid eq "-1"){
			print "<td> - </td>";
		} else {
			print "<td>$pid</td>";
		}

		#print status of a farm
		if ($status ne "up"){
			print "<td><img src=\"img/icons/small/stop.png\" title=\"down\"></td>";
		} else {
			print "<td><img src=\"img/icons/small/start.png\" title=\"up\"></td>";
		}

		#type of farm
		print "<td>$type</td>";

		#menu
		print "<td>";
		if ($type eq "tcp" || $type eq "udp" || $type eq "l4txnat" || $type eq "l4uxnat"){
			&createmenuvip($name,$id,$status);
		}
		if ($type =~ /http/ ){
			&createmenuviph($name,$id,"HTTP");
		}
		print "</td>";
		print "</tr>";
	} else {
		$thereisdl = "true";
	}
}
print "</tbody>";

# DATALINK

if ($thereisdl eq "true"){
print "<thead>";
print "<tr>";
print "<td width=85>Name</td>";
print "<td width=85>IP</td>";
print "<td>Interface</td>";
#print "<td>Rx Bytes<br>Rx Bytes/sec</td>";
#print "<td>Rx Packets<br>Rx Packets/sec</td>";
#print "<td>Tx Bytes<br>Tx Bytes/sec</td>";
#print "<td>Tx Packets<br>Tx Packets/sec</td>";
print "<td>Rx Bytes/sec</td>";
print "<td>Rx Packets/sec</td>";
print "<td>Tx Bytes/sec</td>";
print "<td>Tx Packets/sec</td>";
print "<td>Status</td>";
print "<td>Profile</td>";
print "<td>Actions</td>";
print "</tr>";
print "</thead>";
print "<tbody>";
use Time::HiRes qw (sleep);

foreach $file (@files) {
	$name = &getFarmName($file);
	$type = &getFarmType($name);

	if ($type eq "datalink"){

		$vipp = &getFarmVip("vipp",$name);
		my @startdata = &getDevData($vipp);
		#print "@startdata<br>";
		sleep (0.5);
		my @enddata = &getDevData($vipp);
		#print "@enddata<br>";

		if ($farmname eq $name && $action ne "addfarm" && $action ne "Cancel"){
			print "<tr class=\"selected\">";
		} else {
			print "<tr>";
		}
		#print the farm description name
		print "<td>$name</td>";
		#print the virtual ip
		$vip = &getFarmVip("vip",$name);
		print "<td>$vip</td>";
		#print the interface to be the defaut gw
		print "<td>$vipp</td>";
	
		#print global packets
		$status = &getFarmStatus($name);
		
		if ($status eq "up"){
			my $ncalc = (@enddata[0]-@startdata[0])*2;
			#print "<td> @enddata[0] B<br>$ncalc B/s </td>";
			print "<td> $ncalc B/s </td>";
		} else {
			print "<td>0</td>";
		}

		if ($status eq "up"){
			my $ncalc = (@enddata[1]-@startdata[1])*2;
			#print "<td> @enddata[1] Pkt<br>$ncalc Pkt/s </td>";
			print "<td> $ncalc Pkt/s </td>";
		} else {
			print "<td>0</td>";
		}

		if ($status eq "up"){
			my $ncalc = (@enddata[2]-@startdata[2])*2;
			#print "<td> @enddata[2] B<br>$ncalc B/s </td>";
			print "<td> $ncalc B/s </td>";
		} else {
			print "<td>0</td>";
		}

		if ($status eq "up"){
			my $ncalc = (@enddata[3]-@startdata[3])*2;
			#print "<td> @enddata[3] Pkt<br>$ncalc Pkt/s </td>";
			print "<td>$ncalc Pkt/s </td>";
		} else {
			print "<td>0</td>";
		}

		#print status of a farm

		if ($status ne "up"){
			print "<td><img src=\"img/icons/small/stop.png\" title=\"down\"></td>";
		} else {
			print "<td><img src=\"img/icons/small/start.png\" title=\"up\"></td>";
		}

		#type of farm
		print "<td>$type</td>";

		#menu
		print "<td>";
		&createmenuvip($name,$id,$status);

		print "</td>";
		print "</tr>";
	}
}


## END DATALINK

print "</tbody>";
}
print "<tr><td colspan=\"9\"></td><td><a href=\"index.cgi?id=$id&action=addfarm\"><img src=\"img/icons/small/farm_add.png\" title=\"Add new Farm\"></a></td></tr>";

print "</table>";
print "</div>";

print "<br class=\"cl\" >";
print "</div>";



#print "<br class=\"cl\">";
#rint "        </div>
#    <!--Content END-->";
#  </div>
#</div>
#";

