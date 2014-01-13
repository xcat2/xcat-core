#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::GlobalDef;

#--------------------------------------------------------------------------------

=head1    xCAT::GlobalDef

=head2    Package Description

This module contains all the global info for xCAT.


=cut

#--------------------------------------------------------------------------------


# valid values for nodelist.hwtype column
$::NODETYPE_LPAR="lpar"; 
$::NODETYPE_BPA="bpa"; 
$::NODETYPE_FSP="fsp";
$::NODETYPE_HMC="hmc";
$::NODETYPE_IVM="ivm";
$::NODETYPE_FRAME="frame";
$::NODETYPE_CEC="cec";
$::NODETYPE_BLADE="blade";
$::NODETYPE_CMM="cmm";

# valid values for nodelist.nodetype column
$::NODETYPE_OSI="osi"; 
$::NODETYPE_PPC="ppc";
$::NODETYPE_ZVM="zvm";
$::NODETYPE_MP="mp";

#valid values for nodelist.updatestatus
$::STATUS_SYNCING="syncing";
$::STATUS_OUT_OF_SYNC="out-of-sync";
$::STATUS_SYNCED="synced";
$::STATUS_FAILED="failed";


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
$::STATUS_CONFIGURING="configuring";
$::STATUS_STANDING_BY="standingby";
$::STATUS_SHELL="shell";
$::STATUS_DEFINED="defined";
$::STATUS_UNKNOWN="unknown";
$::STATUS_FAILED="failed";
$::STATUS_BMCREADY="bmcready";
%::VALID_STATUS_VALUES = (
	$::STATUS_ACTIVE=>1,
	$::STATUS_INACTIVE=>1,
	$::STATUS_INSTALLING=>1,
	$::STATUS_INSTALLED=>1,
	$::STATUS_BOOTING=>1,
	$::STATUS_NETBOOTING=>1,
	$::STATUS_BOOTED=>1,
	$::STATUS_POWERING_OFF=>1,
	$::STATUS_DISCOVERING=>1,
	$::STATUS_CONFIGURING=>1,
	$::STATUS_STANDING_BY=>1,
	$::STATUS_SHELL=>1,
	$::STATUS_DEFINED=>1,
	$::STATUS_UNKNOWN=>1,
        $::STATUS_FAILED=>1,
        $::STATUS_BMCREADY=>1,

	$::STATUS_SYNCING=>1,
	$::STATUS_OUT_OF_SYNC=>1,
	$::STATUS_SYNCED=>1,
);

#defined->[discovering]->[configuring]->[standingby]->installing->[installed]->booting->alive,  defined->[discovering]->[configuring]-[standingby]->netbooting->booted->alive,  alive/unreachable->booting->alive,  powering-off->unreachable, alive->unreachable
%::NEXT_NODESTAT_VAL=(
  $::STATUS_DEFINED=>{$::STATUS_DISCOVERING=>1, $::STATUS_INSTALLING=>1, $::STATUS_NETBOOTING=>1, $::STATUS_POWERING_OFF=>1, $::STATUS_BOOTING=>1, $::STATUS_CONFIGURING=>1},
  $::STATUS_DISCOVERING=>{$::STATUS_INSTALLING=>1, $::STATUS_NETBOOTING=>1, $::STATUS_CONFIGURING=>1, $::STATUS_BOOTING=>1},
  $::STATUS_CONFIGURING=>{$::STATUS_INSTALLING=>1, $::STATUS_NETBOOTING=>1, $::STATUS_STANDING_BY=>1},
  $::STATUS_INSTALLING =>{$::STATUS_INSTALLED=>1, $::STATUS_BOOTING=>1},
  $::STATUS_INSTALLED =>{$::STATUS_BOOTING=>1},
  $::STATUS_BOOTING=>{$::STATUS_BOOTED=>1, $::STATUS_ACTIVE=>1, $::STATUS_INACTIVE=>1},
  $::STATUS_NETBOOTING=>{$::STATUS_BOOTED=>1},
  $::STATUS_BOOTED=>{$::STATUS_ACTIVE=>1, $::STATUS_INACTIVE=>1},
  $::STATUS_ACTIVE=>{$::STATUS_INACTIVE=>1, $::STATUS_DISCOVERING=>1, $::STATUS_CONFIGURING=>1, $::STATUS_INSTALLING=>1, $::STATUS_NETBOOTING=>1, $::STATUS_POWERING_OFF=>1, $::STATUS_BOOTING=>1},
  $::STATUS_INACTIVE=>{$::STATUS_ACTIVE=>1, $::STATUS_DISCOVERING=>1, $::STATUS_CONFIGURING=>1, $::STATUS_INSTALLING=>1, $::STATUS_NETBOOTING=>1, $::STATUS_POWERING_OFF=>1, $::STATUS_BOOTING=>1},
  $::STATUS_POWERING_OFF=>{$::STATUS_INACTIVE=>1}
);


1;
 
