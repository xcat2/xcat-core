#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::Usage;

#-------------------------------------------------------------------------------
=head1  xCAT::Usage
=head2    Package Description
  xCAT usage module. Some commands such as rpower have different implementations 
  for different hardware. This module holds the usage usage string for these kind
  of commands so that the usage can be referenced from different modules.
=cut
#-------------------------------------------------------------------------------


my %usage = (
    "rpower" => "Usage: rpower <noderange> [--nodeps][on|off|reset|stat|boot]",
    "rbeacon" => "Usage: rbeacon <noderange> [on|off|stat]",
    "rvitals" => "Usage: rvitals <noderange> [all|temp|wattage|voltage|fanspeed|power|leds]",
    "reventlog" => "Usage: reventlog <noderange> [all|clear|<number of entries to retrieve>]",
    "rinv" => "Usage: rinv <noderange> [all|model|serial|vpd|mprom|deviceid|uuid]",
    "rsetboot" => "Usage: rsetboot <noderange> [net|hd|cd|def|stat]",
    "rbootseq" => "Usage: rbootseq <noderange> [hd0|hd1|hd2|hd3|net|iscsi|usbflash|floppy|none],...",
    "rscan" => "Usage: rscan <noderange> [-w][-x|-z]",
    "rspconfig" => 
"Usage: 
   Common:
       rspconfig <noderange> [snmpdest|alert|community]
       rspconfig <noderange> [snmpdest=<dest ip address>|alert=<on|off|en|dis|enable|disable>|community=<string>]
   BMC specific:
       rspconfig <noderange> [ip|netmask|gateway|backupgateway|garp]
       rspconfig <noderange> [garp=<number of 1/2 second>]
   MPA specific:
       rspconfig <noderange> [sshcfg|snmpcfg|build]
       rspconfig <noderange> [shcfg=<enable|disable>|snmpcfg=<enable|disable>]"
);

#--------------------------------------------------------------------------------
=head3   getUsage
      It returns the usage string for the given command.
    Arguments:
        command
    Returns:
        the usage string for the command.
=cut
#-------------------------------------------------------------------------------
sub getUsage {
  my ($class, $command)=@_;
  if (exists($usage{$command})) { return $usage{$command};}  
  else { return "Usage for command $command cannot be found\n"; }
}
