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


$db_if="iface.rrd";
#my @system = `$ifconfig_bin -a`;
my @system = `$ifconfig_bin`;

$is_if=0;
foreach $line(@system)
	{
	chomp($line);
	if ($line =~ /^[a-z]/ && $line !~ /^lo/)
		{
		my @if_name = split("\ ",$line);
		chomp(@if_name[0]);
		$if_name = @if_name[0];
		$is_if = 1;
		}	
	if ($is_if && $line =~ /rx bytes/i)
		{
		my @s_line = split(":",$line);
		my @rx = split("\ ",@s_line[1]);
		my @tx = split("\ ",@s_line[2]);
		$in = @rx[0];
		$out = @tx[0];
		$is_if = 0;
		#process if_name
		if (! -f "$rrdap_dir$rrd_dir$if_name$db_if")		
			{
			print "Creating traffic rrd database for $if_name $rrdap_dir$rrd_dir$if_name$db_if ...\n";
			RRDs::create "$rrdap_dir$rrd_dir$if_name$db_if",
                        	"-s 300",
                        	"DS:in:DERIVE:600:0:12500000",
                        	"DS:out:DERIVE:600:0:12500000",
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

			if ($ERROR = RRDs::error) { print "$0: unable to generate $if_name database: $ERROR\n"};
			}
		print "Information for $if_name interface graph ...\n";
		print "		in: $in\n";
		print "		out: $out\n";
		#update rrd info
		print "Updating Informatino in $rrdap_dir$rrd_dir$if_name$db_if ...\n";
		RRDs::update "$rrdap_dir$rrd_dir$if_name$db_if",
			"-t", "in:out",
			"N:$in:$out";
		#size graph
		$width="500";
		$height="150";
		#create graphs
		@time=("d","w","m","y");
		foreach $time_graph(@time)
			{

			$graph = $basedir.$img_dir.$if_name."_".$time_graph.".png";
			print "Creating graph in $graph ...\n";
			RRDs::graph ("$graph",
               			"--start=-1$time_graph",
				"-h", "$height", "-w", "$width",
              			"--lazy",
               			"-l 0",
               			"-a", "PNG",
               			"-v TRAFFIC ON $if_name",
               			"DEF:in=$rrdap_dir$rrd_dir$if_name$db_if:in:AVERAGE",
               			"DEF:out=$rrdap_dir$rrd_dir$if_name$db_if:out:AVERAGE",
               			"CDEF:out_neg=out,-1,*",
               			"AREA:in#32CD32:In ",
               			"LINE1:in#336600",
				"GPRINT:in:LAST:Last\\:%5.1lf %sByte/sec", 
				"GPRINT:in:MIN:Min\\:%5.1lf %sByte/sec",  
				"GPRINT:in:AVERAGE:Avg\\:%5.1lf %sByte/sec",  
				"GPRINT:in:MAX:Max\\:%5.1lf %sByte/sec\\n",
               			"AREA:out_neg#4169E1:Out",
               			"LINE1:out_neg#0033CC",
				"GPRINT:in:LAST:Last\\:%5.1lf %sByte/sec", 
				"GPRINT:in:MIN:Min\\:%5.1lf %sByte/sec",  
				"GPRINT:in:AVERAGE:Avg\\:%5.1lf %sByte/sec",  
				"GPRINT:in:MAX:Max\\:%5.1lf %sByte/sec\\n",
               			"HRULE:0#000000");

		       if ($ERROR = RRDs::error) { print "$0: unable to generate $if_name traffic graph: $ERROR\n"; }
			
			}
		
		#end process rrd for $if_name
		}
	if ($line =~ /^$/)
		{
		#line is blank
		$is_if = 0;
		}
	}


