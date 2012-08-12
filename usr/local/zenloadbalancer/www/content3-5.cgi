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
use File::stat;
use File::Basename;
use Time::localtime;
use Sys::Hostname;
my $host = hostname();

print "
<!--Content INI-->
<div id=\"page-content\">

<!--Content Header INI-->
<h2>Settings::Backup</h2>
<!--Content Header END-->";


if ($action eq "apply")
	{
	&successmsg("Backup will be decompressed and Zen Load Balancer will be restarted, Zen Cluster node could switch...");
	my @eject = `$tar -xvzf backup/$file -C /`;
	&logfile("unpacking files: @eject");	
	my @eject = `/etc/init.d/zenloadbalancer restart`;
	if ($? == 0)
		{
		&successmsg("Backup applied and Zen Load Balancer restarted...");
		}
	else
		{
		&errormsg("Problem restarting Zen Load Balancer service");
		}

	}

if ($action eq "Create Backup")
	{
	if ($name !~ /^$/)
		{
		$name =~ s/\ //g;		
		my @eject = `$zenbackup $name -c 2> /dev/null`;
		&successmsg("Local system backup created <b>backup-$name.tar.gz</b>");
		}


	}

if ($action eq "del")
	{
	$filepath = "$backupdir$file";
	if (-e $filepath)
		{
		unlink($filepath);
		&successmsg("Deleted backup file <b>$file</b>");

		}
	else
		{
		&errormsg("File <b>$file</b> not found");
		}

	}

#if ($action eq "Upload Backup")
#	{
#$CGI::POST_MAX = 1024 * 5000;  
#my $query = new CGI;
#my $safe_filename_characters = "a-zA-Z0-9_.-";  
#my $upload_dir = "$backupdir";  
#my $filex = $query->param("file"); 
#my $upload_filehandle = $query->upload("fileName");  
# 
#open ( UPLOADFILE, ">$backupdir$file" ) or die "$!";  
#binmode UPLOADFILE;  
# 
#while ( <$upload_filehandle> )  
#{  
# print UPLOADFILE;  
#}  
# 
#close UPLOADFILE;  
#	}

print "<div class=\"container_12\">";
print "	<div class=\"grid_12\">";
print "		<div class=\"box-header\">Backup</div>";
print "		<div class=\"box stats\">";


print "<form method=\"get\" action=\"index.cgi\">";
print "<b>Description name: </b><input type=\"text\" name=\"name\" value=\"$lhost\">";
print "<input type=\"hidden\" name=\"id\" value=\"$id\">";
print "<input type=\"submit\" value=\"Create Backup\" name=\"action\" class=\"button small\">";
print "</form>";
print "<br><br>";

print "</div></div></div>";
print "<br class=\"cl\">";
#table
print "<div class=\"box-header\"> Backup files <a href=\"index.cgi?id=$id\"><img src=\"img/icons/small/arrow_refresh.png\" title=\"refresh\"></a></div>";
print "<div class=\"box table\">";

print "<table>";
print "<thead>";

print "<tr>";
print "<td>Description name</td>";
print "<td>Date</td>";
print "<td>Host</td>";
print "<td>Action</td>";
print "</tr>";
print "</thead>";
print "<tbody>";

opendir(DIR, "$backupdir");
@files = grep(/^backup.*/,readdir(DIR));
closedir(DIR);

foreach $file(@files)
	{
	print "<tr>";
	$filepath = "$backupdir$file";
	chomp($filepath);
	#print "filepath: $filepath";
	$datetime_string = ctime(stat($filepath)->mtime);
	print "<td>$file</td>";
	print "<td>$datetime_string</td>";
	print "<td>$host</td>";
	print "<td>";
	&createmenubackup($file);
	print "</td>";
	print "</tr>";
	}

print "<tr><td colspan=3></td><td>";

&upload();

print "</td></tr>";
print "</tbody>";
print "</table>";
print "</div>";





#print "		</div>";
#print "<br>";
#print "	</div>";
#print "</div>";




print "<br class=\"cl\">";
#content 3-4 END
print " </div>
    <!--Content END-->
</div>
";

