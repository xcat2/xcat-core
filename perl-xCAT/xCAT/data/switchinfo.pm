# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

#This module includes some glocal table to look up the switch type via mac and vendor 

package xCAT::data::switchinfo;

require Exporter;
@ISA       = qw(Exporter);
@EXPORT    = qw();
@EXPORT_OK = qw(global_mac_identity global_switch_type);

use strict;

#the hash to look up switch type with MAC
our %global_mac_identity = (
    "a8:97:dc" => "BNT G8052 switch",
    "6c:ae:8b" => "BNT G8264-T switch",
    "fc:cf:62" => "BNT G8124 switch",
    "7c:fe:90" => "Mellanox IB switch",
    "cc:37:ab" => "Edgecore Networks Switch",
    "8c:ea:1b" => "Edgecore Networks Switch"
);

#the hash to lookup switch type with vendor
our %global_switch_type = (
    Juniper => "Juniper",
    juniper => "Juniper",
    Cisco => "Cisco",
    cisco => "Cisco",
    BNT => "BNT",
    Blade => "BNT",
    G8052 => "BNT",
    RackSwitch => "BNT",
    Mellanox => "Mellanox",
    mellanox => "Mellanox",
    MLNX => "Mellanox",
    MELLAN => "Mellanox",
    Cumulus => "onie",
    cumulus => "onie",
    Edgecore => "onie"
);



1;
