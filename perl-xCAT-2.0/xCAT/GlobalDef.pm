#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::GlobalDef;

#--------------------------------------------------------------------------------

=head1    xCAT::GlobalDef

=head2    Package Description

This module contains all the global info for xCAT.


=cut

#--------------------------------------------------------------------------------


# valid values for nodelist.nodetype column
$::NODETYPE_OSI="osi"; 
$::NODETYPE_LPAR="lpar"; 
$::NODETYPE_BPA="bpa"; 
$::NODETYPE_FSP="fsp";


# valid values for nodelist.status columns or other status 
$::STATUS_ACTIVE="active";
$::STATUS_INACTIVE="inactive";
$::STATUS_UNKNOWN="unknown";

1;
 
