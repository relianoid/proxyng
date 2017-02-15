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

#FOOTER

use Time::localtime;
$currentyear = localtime->year() + 1900;

print "
<!-- Start Footer -->
<div class=\"footer container_12\">
<p class=\"grid_12\">Copyright &copy; 2010-$currentyear SOFINTEL IT ENGINEERING S.L. // ZEVENET is created under GNU/LGPL License // <a href=\"https://www.zevenet.com\" target=\"_blank\">www.zevenet.com</a></p>
</div>
<!-- End Footer -->

<script>

/* Spinner */
\$(window).load(function(){
    \$('#cover').fadeOut(1000);
});

</script>

</body>
</html>
";
