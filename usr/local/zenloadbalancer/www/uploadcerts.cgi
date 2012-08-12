#!/usr/bin/perl
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

require "config/global.conf";
require "functions.cgi";
use CGI qw(:standard escapeHTML);
print "Content-type: text/html\n\n";

##REQUIRES
#require "help-content.cgi";


print "
<HTML>
<head>
<meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\" />

<link type=\"text/css\" rel=\"stylesheet\" media=\"all\" href=\"css/base.css\" />
<link type=\"text/css\" rel=\"stylesheet\" media=\"all\" href=\"css/grid.css\" />
<title>Upload Certificates</title></head>";

print "<BODY onunload=\"opener.location=('index.cgi?id=1-3')\">";

print "<div id=\"header\">
	 <div class=\"header-top tr\">";

print "<br><br><br>";
print "<div id=\"page-header\"></div>

	 </div>
      </div>";


#print "<b>Upload Backup.</b>";
#print "<div id=\"page-header\"></div>";

my $query = new CGI;
my $upload_dir= $configdir;
my $action = $query->param("action");
my $filename = $query->param("fileup");

my $upload_filehandle = $query->upload("fileup");

if ($action eq "Upload" && $filename !~ /^$/)
        {
	if ($filename =~ /\.pem$/)
		{
		if ($filename =~ /\\/){
                @filen = split(/\\/,$filename);
                $filename = $filen[-1];
		        }

        	open ( UPLOADFILE, ">$upload_dir/$filename" ) or die "$!";
        	binmode UPLOADFILE;
        	while ( <$upload_filehandle> )
        	        {
        	        print UPLOADFILE;
        	        }
       	 	close UPLOADFILE;
		print "<br>";
		&successmsg("File $filename uploaded!");
		}
	else
		{
		print "<br>";
		&errormsg("file withuot pem extension");
		}
        }

print "<br>";
print "<br>";

print "<form method=\"post\" action=\"uploadcerts.cgi\" enctype=\"multipart/form-data\">";
#print "<form method=\"post\" action=\"index.cgi\">";
#print "<b>File:</b> <input  type=\"file\" name=\"file\">";
#print qq{
#<input type="text" id="fileName" class="file_input_textbox" readonly="readonly">
#<div class="file_input_div">
#  <input type="button" value="Search files" class="button small" />
#  <input type="file" class="file_input_hidden" name="file" onchange="javascript: document.getElementById('fileName').value = this.value" >
#</div>
#};

print "<b>Upload file on pem format. <font size=1> filename.pem</fon>:</b> <input   type=\"file\" name=\"fileup\" value=\"Ex\" >";
print "<br>";
print "<br>";
print "<input type=\"submit\" value=\"Upload\" name=\"action\" class=\"button small\">";
print "</form>";
print "<br>";



print "</BODY>";
print "</HTML>"; 

