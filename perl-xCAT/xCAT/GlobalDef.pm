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
$::NODETYPE_HMC="hmc";
$::NODETYPE_IVM="ivm";

# valid values for nodelist.status columns or other status 
$::STATUS_ACTIVE="alive";
$::STATUS_INACTIVE="unreachable";
$::STATUS_INSTALLING="installing";
$::STATUS_INSTALLED="installed";
$::STATUS_BOOTING="booting";
$::STATUS_NETBOOTING="netbooting";
$::STATUS_BOOTED="booted";
$::STATUS_POWERING_OFF="powering-off";
$::STATUS_DISCOVERING="discovering";
$::STATUS_DEFINED="defined";
$::STATUS_UNKNOWN="unknown";

#defined->[discovering]->installing->booting->booted->alive,  defined->netbooting->booted->alive,  alive/unreachable->booting->booted->alive,  powering-off->unreachable, alive->unreachable
%::NEXT_NODESTAT_VAL=(
  $::STATUS_DEFINED=>{$::STATUS_DISCOVERING=>1, $::STATUS_INSTALLING=>1, $::STATUS_NETBOOTING=>1, $::STATUS_POWERING_OFF=>1, $::STATUS_BOOTING=>1},
  $::STATUS_DISCOVERING=>{$::STATUS_INSTALLING=>1},
  $::STATUS_INSTALLING =>{$::STATUS_BOOTING=>1},
  $::STATUS_BOOTING=>{$::STATUS_BOOTED=>1,$::STATUS_ACTIVE=>1, $::STATUS_INACTIVE=>1},
  $::STATUS_NETBOOTING=>{$::STATUS_BOOTED=>1},
  $::STATUS_BOOTED=>{$::STATUS_ACTIVE=>1, $::STATUS_INACTIVE=>1},
  $::STATUS_ACTIVE=>{$::STATUS_INACTIVE=>1, $::STATUS_DISCOVERING=>1, $::STATUS_INSTALLING=>1, $::STATUS_NETBOOTING=>1, $::STATUS_POWERING_OFF=>1, $::STATUS_BOOTING=>1},
  $::STATUS_INACTIVE=>{$::STATUS_ACTIVE=>1, $::STATUS_DISCOVERING=>1, $::STATUS_INSTALLING=>1, $::STATUS_NETBOOTING=>1, $::STATUS_POWERING_OFF=>1, $::STATUS_BOOTING=>1},
  $::STATUS_POWERING_OFF=>{$::STATUS_INACTIVE=>1}
);


1;
 
