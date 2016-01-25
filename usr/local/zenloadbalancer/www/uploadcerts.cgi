#!/usr/bin/perl
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

require "/usr/local/zenloadbalancer/config/global.conf";
require "./functions.cgi";
require "./login_functions.cgi";
use CGI qw(:standard escapeHTML);
&login();
print "Content-type: text/html\n\n";

##REQUIRES
#require "help-content.cgi";

print "
<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<!---CSS Files-->
<link rel=\"stylesheet\" href=\"css/master.css\">
<link rel=\"stylesheet\" href=\"css/tables.css\">
<link rel=\"stylesheet\" href=\"/font/font-aw/css/font-awesome.min.css\">
<title>Upload certificate file</title></head>";

print "<body onUnload=\"opener.location=('index.cgi?id=1-3')\">";

print "<img src=\"img/logo.png\" alt=\"Logo\">";

print "<div class=\"container_12\">";

print "<div class=\"grid_12\">";

#print "<b>Upload Backup.</b>";
#print "<div id=\"page-header\"></div>";

my $query      = new CGI;
my $upload_dir = $configdir;
my $action     = $query->param( "action" );
my $filename   = $query->param( "fileup" );

my $upload_filehandle = $query->upload( "fileup" );

if ( $action eq "Upload" && $filename !~ /^$/ )
{
	if ( $filename =~ /\.pem$/ )
	{
		if ( $filename =~ /\\/ )
		{
			@filen = split ( /\\/, $filename );
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
		&successmsg( "File $filename uploaded!" );
	}
	else
	{
		print "<br>";
		&errormsg( "file withuot pem extension" );
	}
}

print "<br>";
print "<br>";

print
  "<form method=\"post\" action=\"uploadcerts.cgi\" enctype=\"multipart/form-data\">";

#print "<form method=\"post\" action=\"index.cgi\">";
#print "<b>File:</b> <input  type=\"file\" name=\"file\">";
#print qq{
#<input type="text" id="fileName" class="file_input_textbox" readonly="readonly">
#<div class="file_input_div">
#  <input type="button" value="Search files" class="button small" />
#  <input type="file" class="file_input_hidden" name="file" onchange="javascript: document.getElementById('fileName').value = this.value" >
#</div>
#};

print "<p><b>Upload certificate file.</b> Please use filename.pem format.</p>";
print "<div class=\"spacer\"></div>";
print "<input type=\"file\" name=\"fileup\" value=\"Ex\" >";
print "<br>";
print "<br>";
print
  "<input type=\"submit\" value=\"Upload\" name=\"action\" class=\"button normal grey\">";
print "</form>";

print "</div>";

print "</div>";

print "</body>";
print "</html>";

