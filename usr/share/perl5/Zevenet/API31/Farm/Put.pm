###############################################################################
#
#    Zevenet Software License
#    This file is part of the Zevenet Load Balancer software package.
#
#    Copyright (C) 2014-today ZEVENET SL, Sevilla (Spain)
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

use strict;
use Zevenet::Farm::Core;

sub modify_farm # ( $json_obj, $farmname )
{
	my $json_obj = shift;
	my $farmname = shift;

	my $desc = "Modify farm";

	# Check that the farm exists
	if ( &getFarmFile( $farmname ) eq '-1' )
	{
		my $msg = "The farmname $farmname does not exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my $type = &getFarmType( $farmname );

	if ( $type eq "http" || $type eq "https" )
	{
		require Zevenet::API31::Farm::Put::HTTP;
		&modify_http_farm( $json_obj, $farmname );
	}

	if ( $type eq "l4xnat" )
	{
		require Zevenet::API31::Farm::Put::L4xNAT;
		&modify_l4xnat_farm( $json_obj, $farmname );
	}

	if ( $type eq "datalink" )
	{
		require Zevenet::API31::Farm::Put::Datalink;
		&modify_datalink_farm( $json_obj, $farmname );
	}

	if ( $type eq "gslb" )
	{
		if ( eval { require Zevenet::API31::Farm::Put::GSLB; } )
		{
			&modify_gslb_farm( $json_obj, $farmname );
		}
	}
}

1;
