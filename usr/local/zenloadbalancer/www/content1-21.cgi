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

if ($action eq "Save"){
	#check if farm name is ok
	$farmname =~ s/\ //g;
	$farmname =~ s/\_//g;
	#check ip is ok
	$error = "false";
	@fvip = split(" ",$vip);
	$fdev = @fvip[0];
	$vip = @fvip[1];

	if ($vip eq ""){
		$error = "true";
		&errormsg("Please select a Virtual IP or add a new Virtual IP in \"Settings >> Interfaces\" Section");
		$action = "addfarm";
	}

	#check if vipp is a number and if vipp in the correct vip is not in use.
	if ($farmname =~ /^$/){
		$error = "true";
		&errormsg("The farm name can't be empty");
		$action = "addfarm";
	}

	if ($farmprotocol eq "DATALINK" || $vipp =~ /^[+-]?\d+$/){
		$inuse = &checkport($vip,$vipp);
		if ($inuse eq "true"){
			$error = "true";
			&errormsg("The Virtual Port $vipp in Virtual IP $vip is in use, select another port or add another Virtual IP");
			$action = "addfarm";
		}
	} else {
		$error = "true";
		&errormsg("Invalid Virtual Port value, it must be numeric");
		$action = "addfarm";
	}

	if ($error eq "false"){
		$error = 0;
		$status = &runFarmCreate($farmprotocol,$vip,$vipp,$farmname,$fdev);
		if ($status == -1){
			&errormsg("The $farmname farm can't be created");
			$error = 1;
			
		}
		if ($status == -2){
			&errormsg("The $farmname farm already exists, please set a different farm name");
			$error = 1;
		}
		if ($error == 0){
			&successmsg("The $farmname farm has been added to VIP $vip over $fdev, now you can manage it");
		} else {
			$action = "addfarm";
		}
	}
}

if ($action eq "addfarm" || $action eq "Save & continue"){

print "<div class=\"container_12\">";
print "<div class=\"box-header\">Configure a new Farm</div>";
print "<div class=\"box stats\">";
print "<div class=\"row\">";

print "<form method=\"get\" action=\"index.cgi\">";
print "<input type=\"hidden\" name=\"id\" value=\"$id\">";
#farm name
print "<b>Farm Description Name: </b>";
if ($farmname ne ""){
	print "<input type=\"text\" value=\"$farmname\" size=\"40\" name=\"farmname\">";
} else {
	print "<input type=\"text\" value=\"\" size=\"40\" name=\"farmname\">";
}

#farm profile
print "&nbsp;&nbsp;&nbsp;<b> Profile:<b>";
if ($farmprotocol eq "" || $farmname eq ""){
	print "<select name=\"farmprotocol\">";
	print "<option value=\"TCP\">TCP</option>\n";
	print "<option value=\"UDP\">UDP</option>\n";
	print "<option value=\"HTTP\">HTTP</option>\n";
	print "<option value=\"HTTPS\">HTTPS</option>\n";
	print "<option value=\"DATALINK\">DATALINK</option>\n";
	print "</select>";
} else {
	print "<input type=\"text\" value=\"$farmprotocol\" size=\"10\" name=\"farmprotocol\" disabled >";
	print "<input type=\"hidden\" name=\"farmprotocol\" value=\"$farmprotocol\">";
}
print "<br><br>";

if ($farmprotocol ne "" && $farmname ne ""){

	#eth interface selection
	print "<b>Virtual IP: </b>";
	my $nvips;
	if ($farmprotocol eq "DATALINK"){
		$nvips=&listactiveips("phvlan");
	} else {
		$nvips=&listactiveips();
	}
	my @vips = split(" ",$nvips);
	print "<select name=\"vip\">\n";
	print "<option value=\"\">-Select One-</option>\n";
	for ($i=0; $i<=$#vips; $i++){
		my @ip = split("->",@vips[$i]);
		print "<option value=\"@ip[0] @ip[1]\">@vips[$i]</option>\n";
	}
	print "</select>";
	print "<b> or add <a href=\"index.cgi?id=3-2\">new VIP interface</a>.</b>";

	if ($farmprotocol ne "DATALINK"){
		#vip port
		print "<b> Virtual Port: </b>";
		print "<input type=\"text\" value=\"\" size=\"4\" name=\"vipp\">";
	}
	print "<br><br><input type=\"submit\" value=\"Save\" name=\"action\" class=\"button small\">";
	print "<input type=\"submit\" value=\"Cancel\" name=\"action\" class=\"button small\">";
} else {
	#print "<input type=\"hidden\" name=\"action\" value=\"addfarm\">";
	print "<input type=\"submit\" value=\"Save & continue\" name=\"action\" class=\"button small\">";
	print "<input type=\"submit\" value=\"Cancel\" name=\"action\" class=\"button small\">";
}

print "</form>";
print "</div>";

print "</div></div>";
}

print "<br>";

