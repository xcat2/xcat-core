#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::Usage;
use Getopt::Long;

#-------------------------------------------------------------------------------
=head1  xCAT::Usage
=head2    Package Description
  xCAT usage module. Some commands such as rpower have different implementations 
  for different hardware. This module holds the usage usage string for these kind
  of commands so that the usage can be referenced from different modules.
=cut
#-------------------------------------------------------------------------------


my %usage = (
    "rnetboot" => 
"Usage: rnetboot <noderange> [-V|--verbose]
       rnetboot [-h|--help|-v|--version]",
    "rpower" => 
"Usage: rpower <noderange> [--nodeps][on|off|reset|stat|state|boot|of|cycle] [-V|--verbose]
       rpower [-h|--help|-v|--version]",
    "rbeacon" => 
"Usage: rbeacon <noderange> [on|off|stat] [-V|--verbose]
       rbeacon [-h|--help|-v|--version]",
    "rvitals" => 
"Usage: rvitals <noderange> [all|temp|wattage|voltage|fanspeed|power|leds|state] [-V|--verbose]
       rvitals [-h|--help|-v|--version]",
    "reventlog" => 
"Usage: reventlog <noderange> [all|clear|<number of entries to retrieve>] [-V|--verbose]
       reventlog [-h|--help|-v|--version]",
    "rinv" => 
"Usage: 
    Common:
       rinv <noderange> [all|model|serial] [-V|--verbose]
       rinv [-h|--help|-v|--version]
    BMC specific:
       rinv <noderange> [vpd|mprom|deviceid|uuid|guid]
    MPA specific:
       rinv <noderange> [firm|bios|diag|mprom|sprom|mparom|mac|mtm]
    PPC specific:
       rinv <noderange> [bus|config]",
    "rsetboot" => 
"Usage: rsetboot <noderange> [net|hd|cd|def|stat] [-V|--verbose]
       rsetboot [-h|--help|-v|--version]",
    "rbootseq" => 
"Usage: rbootseq <noderange> [hd0|hd1|hd2|hd3|net|iscsi|usbflash|floppy|none],...
       rbootseq [-h|--help|-v|--version]",
    "rscan" => 
"Usage: rscan <noderange> [-w][-x|-z] [-V|--verbose]
       rscan [-h|--help|-v|--version]",
    "rspconfig" => 
"Usage: 
   Common:
       rspconfig <noderange> [snmpdest|alert|community] [-V|--verbose]
       rspconfig <noderange> [snmpdest=<dest ip address>|alert=<on|off|en|dis|enable|disable>|community=<string>]
       rspconfig [-h|--help|-v|--version]
   BMC specific:
       rspconfig <noderange> [ip|netmask|gateway|backupgateway|garp]
       rspconfig <noderange> [garp=<number of 1/2 second>]
   MPA specific:
       rspconfig <noderange> [sshcfg|snmpcfg|build]
       rspconfig <noderange> [shcfg=<enable|disable>|snmpcfg=<enable|disable>|build|                             
           pd1[=nonred|redwoperf|redwperf]|
           pd2[=nonred|redwoperf|redwperf]|
           network[=xcat-table|ip,host,gateway,mask]|
           swnet[=ip,gateway,mask]|
           ntp[=ntp,ip,frequency,v3]]
   PPC specific:
       rspconfig <noderange>  autopower [enable|disable]|
           decfg [{enable|disable} policy,...]|
           spdump|
           date [mm-dd-yyyy]|
           time [hh:mm:ss]|
           memdecfg [{configure|deconfigure} unit=id (unit|bank)=all|id,...]|
           sysdump|
           procdecfg [{configure|deconfigure} unit=id all|id,...]|
           iocap [enable|disable]",
    "getmacs" => 
"Usage: 
   Common:
       getmacs <noderange> [-V|--verbose]
       getmacs [-h|--help|-v|--version]
   PPC specific:
       getmacs <noderange> [-c][-w][-S server -G gateway -C client]",
    "mkvm" => 
"Usage: mkvm singlenode -i id -n name [-V|--verbose]
       mkvm src_fsp -c dest_fsp [-V|--verbose]
       mkvm [-h|--help|-v|--version]",
    "lsvm" => 
"Usage: lsvm <noderange> [-V|--verbose] 
       lsvm [-h|--help|-v|--version]",
    "chvm" => 
"Usage: chvm <noderange> [-V|--verbose] 
       chvm [-h|--help|-v|--version]",
    "rmvm" => 
"Usage: rmvm <noderange> [-V|--verbose] 
       rmvm [-h|--help|-v|--version]"
);

my %version = (
    "rnetboot" => "Version 2.0",
    "rpower" => "Version 2.0",
    "rbeacon" => "Version 2.0",
    "rvitals" => "Version 2.0",
    "reventlog" => "Version 2.0",
    "rinv" => "Version 2.0",
    "rsetboot" => "Version 2.0",
    "rbootseq" => "Version 2.0",
    "rscan" => "Version 2.0",
    "rspconfig" => "Version 2.0",
    "getmacs" => "Version 2.0",
    "mkvm" => "Version 2.0",
    "lsvm" => "Version 2.0",
    "chvm" => "Version 2.0",
    "rmvm" => "Version 2.0"
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

#--------------------------------------------------------------------------------
=head3   getVersion
      It returns the version string for the given command.
    Arguments:
        command
    Returns:
        the version string for the command.
=cut
#-------------------------------------------------------------------------------
sub getVersion {
  my ($class, $command)=@_;
  if (exists($version{$command})) { return $version{$command};}  
  else { return "Version string for command $command cannot be found\n"; }
}

#--------------------------------------------------------------------------------
=head3   parseCommand
      This function parses the given command to see if the usage or version string
      need to be returned. 
    Arguments:
        command
        arguments
    Returns:
        the usage or the version string for the command. The caller need to display the
           string and then exit.
        none, if no usage or version strings are needed. The caller can keep going.
=cut
#-------------------------------------------------------------------------------
sub parseCommand {
  my $command=shift;
  if ($command =~ /xCAT::Usage/) { $command=shift; }
  my @exargs=@_;
  
  @ARGV=@exargs;

  #print "command=$command, args=@exargs, ARGV=@ARGV\n";

  $Getopt::Long::ignorecase=0;
  $Getopt::Long::pass_through=1;

  # parse the options
  if(!GetOptions(
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION)) {
    
    return "";
  }

  if ($::HELP) { return xCAT::Usage->getUsage($command); }
  if ($::VERSION) { return xCAT::Usage->getVersion($command); }

  return "";
}
