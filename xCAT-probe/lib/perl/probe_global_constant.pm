#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package probe_global_constant;

#The type of log
$::LOGTYPE_RSYSLOG = 0;    #rsyslog
$::LOGTYPE_HTTP    = 1;    #apache log

#The lable of specific line log
$::LOGLABEL_DHCPD  = 0;
$::LOGLABEL_TFTP   = 1;
$::LOGLABEL_HTTP   = 2;
$::LOGLABEL_XCAT   = 3;
$::LOGLABEL_UNDEF  = 4;
$::LOGLABEL_DOXCAT = 5;
$::LOGLABEL_DISCOVERY = 6;

#The important stage of provision process
$::STATE_POWER_ON       = 1;
$::STATE_POWERINGON     = 2;
$::STATE_DHCP           = 3;
$::STATE_BOOTLODER      = 4;
$::STATE_KERNEL         = 5;
$::STATE_INITRD         = 6;
$::STATE_KICKSTART      = 7;
$::STATE_INSTALLING     = 8;
$::STATE_INSTALLRPM     = 9;
$::STATE_POSTSCRIPT     = 10;
$::STATE_BOOTING        = 11;
$::STATE_POSTBOOTSCRIPT = 12;
$::STATE_COMPLETED      = 13;

#The description of every important stage of provision process
%::STATE_DESC = (
    $::STATE_POWER_ON       => "rpower_to_install",
    $::STATE_POWERINGON     => "powering_on",
    $::STATE_DHCP           => "got_ip_from_dhcp",
    $::STATE_BOOTLODER      => "download_bootloder",
    $::STATE_KERNEL         => "download_kernel",
    $::STATE_INITRD         => "download_initrd",
    $::STATE_KICKSTART      => "download_kickstart",
    $::STATE_INSTALLING     => "installing",
    $::STATE_INSTALLRPM     => "start_to_install_os_package",
    $::STATE_POSTSCRIPT     => "running_postscripts",
    $::STATE_BOOTING        => "booting",
    $::STATE_POSTBOOTSCRIPT => "running_postbootscripts",
    $::STATE_COMPLETED      => "complete",
);

# The important stage of discovery process
$::STATE_DISCOVER_DHCP           = 1;
$::STATE_DISCOVER_BOOTLODER      = 2;
$::STATE_DISCOVER_KERNEL         = 3;
$::STATE_DISCOVER_INITRD         = 4;
$::STATE_DISCOVER_DOXCAT         = 5;
$::STATE_DISCOVER_DISCOVERY      = 6;
$::STATE_DISCOVER_REPORT         = 7;
$::STATE_DISCOVER_UPDATE         = 8;
$::STATE_DISCOVER_FAILED         = 9;
$::STATE_DISCOVER_COMPLETED      = 10;

#The description of every important stage of discovery process
%::STATE_DISCOVER_DESC = (
    $::STATE_DISCOVER_DHCP           => "got_ip_from_dhcp",
    $::STATE_DISCOVER_BOOTLODER      => "download_bootloder",
    $::STATE_DISCOVER_KERNEL         => "download_genesis_kernel",
    $::STATE_DISCOVER_INITRD         => "download_genesis_initrd",
    $::STATE_DISCOVER_DOXCAT         => "enter_genesis",
    $::STATE_DISCOVER_DISCOVERY      => "start_to_discovery",
    $::STATE_DISCOVER_REPORT         => "send_discovery_request",
    $::STATE_DISCOVER_UPDATE         => "start_update_node_information",
    $::STATE_DISCOVER_FAILED         => "can't_find_related_node",
    $::STATE_DISCOVER_COMPLETED      => "discovery_complete",
);


1;
