#!/usr/bin/perl
#This script is part of Zen Load Balancer, that create rrdtool graphs 
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


#Created by Emilio Campos Martin
#
use RRDs;
require ("/usr/local/zenloadbalancer/config/global.conf");

$db_load="load.rrd";
#create db memory if not exist
if (! -f "$rrdap_dir$rrd_dir$db_load" )

	{
	print "Creating load rrd data base $rrdap_dir$rrd_dir$db_load ...\n";
	RRDs::create "$rrdap_dir$rrd_dir$db_load",
		"-s 300",
		"DS:load:GAUGE:600:0,00:100,00",
		"DS:load5:GAUGE:600:0,00:100,00",
		"DS:load15:GAUGE:600:0,00:100,00",
		"RRA:LAST:0.5:1:288",		# daily - every 5 min - 288 reg
		"RRA:MIN:0.5:1:288",		# daily - every 5 min - 288 reg
		"RRA:AVERAGE:0.5:1:288",	# daily - every 5 min - 288 reg
		"RRA:MAX:0.5:1:288",		# daily - every 5 min - 288 reg
		"RRA:LAST:0.5:12:168",		# weekly - every 1 hour - 168 reg
		"RRA:MIN:0.5:12:168",		# weekly - every 1 hour - 168 reg
		"RRA:AVERAGE:0.5:12:168",	# weekly - every 1 hour - 168 reg
		"RRA:MAX:0.5:12:168",		# weekly - every 1 hour - 168 reg
		"RRA:LAST:0.5:96:93",		# monthly - every 8 hours - 93 reg
		"RRA:MIN:0.5:96:93",		# monthly - every 8 hours - 93 reg
		"RRA:AVERAGE:0.5:96:93",	# monthly - every 8 hours - 93 reg
		"RRA:MAX:0.5:96:93",		# monthly - every 8 hours - 93 reg
		"RRA:LAST:0.5:288:372",		# yearly - every 1 day - 372 reg
		"RRA:MIN:0.5:288:372",		# yearly - every 1 day - 372 reg
		"RRA:AVERAGE:0.5:288:372",	# yearly - every 1 day - 372 reg
		"RRA:MAX:0.5:288:372";		# yearly - every 1 day - 372 reg
	}

#information
if (-f "/proc/loadavg")
        {
        open FR,"/proc/loadavg";
        while ($line=<FR>)
                {
                $lastline = $line
                }
        my @splitline = split(" ", $lastline);
        $last = @splitline[0];
        $last5 = @splitline[1];
        $last15 = @splitline[2];
	print "Information for load graph ...\n";
	print "		Last minute: $last\n";
	print "		Last 5 minutes: $last5\n";
	print "		Last 15 minutes: $last15\n";
	}
	else
	{
	print "Error /proc/loadavg not exist...";
	exit 1;
	}

#update rrd info
print "Updating Information in $rrdap_dir$rrd_dir$db_load ...\n";		
RRDs::update "$rrdap_dir$rrd_dir$db_load",
	"-t", "load:load5:load15",
	"N:$last:$last5:$last15";

#$last =  RRDs::last "$rrdap_dir$rrd_dir$db_load";



