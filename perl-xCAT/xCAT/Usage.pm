#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::Usage;
use Getopt::Long;
use xCAT::Utils;

#-------------------------------------------------------------------------------
=head1  xCAT::Usage
=head2    Package Description
  xCAT usage module. Some commands such as rpower have different implementations 
  for different hardware. This module holds the usage string for these kind
  of commands so that the usage can be referenced from different modules.
=cut
#-------------------------------------------------------------------------------


my %usage = (
    "rnetboot" => 
"Usage: rnetboot <noderange> [-s net|hd] [-F] [-f] [-V|--verbose] [-m table.colum==expectedstatus] [-m table.colum==expectedstatus...] [-r <retrycount>] [-t <timeout>]
       rnetboot [-h|--help|-v|--version]",
    "rpower" => 
"Usage: rpower <noderange> [--nodeps] [on|onstandby|off|suspend|reset|stat|state|boot] [-V|--verbose] [-m table.colum==expectedstatus][-m table.colum==expectedstatus...] [-r <retrycount>] [-t <timeout>]
       rpower [-h|--help|-v|--version]
     KVM Virtualization specific:
       rpower <noderange> [boot] [ -c <path to iso> ]
     PPC (with IVM or HMC) specific:
       rpower <noderange> [--nodeps] [of] [-V|--verbose]
     PPC (HMC) specific:
       rpower <noderange> [onstandby] [-V|--verbose]
     CEC(using Direct FSP Management) specific:
       rpower <noderange> [on|onstandby|off|stat|state|lowpower|resetsp]
     Frame(using Direct FSP Management) specific:
       rpower <noderange> [stat|state|rackstandby|exit_rackstandby|resetsp]
     LPAR(using Direct FSP Management) specific:
       rpower <noderange> [on|off|reset|stat|state|boot|of|sms]
     Blade specific:
       rpower <noderange> [cycle|softoff] [-V|--verbose]
",
    "rbeacon" => 
"Usage: rbeacon <noderange> [on|off|stat] [-V|--verbose]
       rbeacon [-h|--help|-v|--version]",
    "rvitals" => 
"Usage:
  Common:
      rvitals [-h|--help|-v|--version]
  FSP/LPAR (with HMC) specific:
      rvitals noderange {temp|voltage|lcds|all}
  CEC/LPAR/Frame (using Direct FSP Management)specific:
      rvitals noderange {rackenv|lcds|all}
  MPA specific:
      rvitals noderange {temp|voltage|wattage|fanspeed|power|leds|summary|all}
  Blade specific:
      rvitals noderange {temp|wattage|fanspeed|leds|summary|all}
  BMC specific:
      rvitals noderange {temp|voltage|wattage|fanspeed|power|leds|lcds|summary|all}",
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
    PPC specific(with HMC):
       rinv <noderange> [bus|config|serial|model|firm|all]
    PPC specific(using Direct FSP Management):
       rinv <noderange> [firm|deconfig]
    Blade specific:
       rinv <noderange> [mtm|serial|mac|bios|diag|mprom|mparom|firm|all]
    VMware specific:
       rinv <noderange>",
    "rsetboot" => 
"Usage: rsetboot <noderange> [net|hd|cd|floppy|def|stat] [-V|--verbose]
       rsetboot [-h|--help|-v|--version]",
    "rbootseq" => 
"Usage: 
       Common:
           rbootseq [-h|--help|-v|--version]
       Blade specific:
           rbootseq <noderange> [hd0|hd1|hd2|hd3|net|iscsi|usbflash|floppy|none],...
       PPC (using Direct FSP Management) specific:
           rbootseq <noderange> [hfi|net]",
    "rscan" => 
"Usage: rscan <noderange> [-u][-w][-x|-z] [-V|--verbose]
       rscan [-h|--help|-v|--version]",
    "rspconfig" => 
"Usage: 
   Common:
       rspconfig [-h|--help|-v|--version]
   BMC/MPA Common:
       rspconfig <noderange> [snmpdest|alert|community] [-V|--verbose]
       rspconfig <noderange> [snmpdest=<dest ip address>|alert=<on|off|en|dis|enable|disable>|community=<string>]
   BMC specific:
       rspconfig <noderange> [ip|netmask|gateway|backupgateway|garp]
       rspconfig <noderange> [garp=<number of 1/2 second>]
   iDataplex specific:
       rspconfig <noderange> [thermprofile]
       rspconfig <noderange> [thermprofile=<two digit number from chassis>]
   MPA specific:
       rspconfig <noderange>  [sshcfg|snmpcfg|pd1|pd2|network|swnet|ntp|textid|frame]
       rspconfig <singlenode> [textid=name]
       rspconfig <singlenode> [frame=number]
       rspconfig <noderange>  [sshcfg=<enable|disable>|
           snmpcfg=<enable|disable>|                             
           pd1=<nonred|redwoperf|redwperf>|
           pd2=<nonred|redwoperf|redwperf>|
           network=<*|[ip],[host],[gateway],[netmask]>|
           swnet=<[ip],[gateway],[netmask]>|
           textid=<*>|
           frame=<*>|
           ntp=<[ntp],[ip],[frequency],[v3]>
   FSP/BPA Common:
       rspconfig <noderange> [autopower|iocap|decfg|memdecfg|procdecfg|time|date|spdump|sysdump|network|hostname]
       rspconfig <noderange> autopower=<enable|disable>|
           iocap=<enable|disable>|
           decfg=<enable|disable>:<policy name>,...|
           memdecfg=<configure|deconfigure>:<processing unit>:<bank|unit>:<bank/unit number>:id,...|
           procdecfg=<configure|deconfigure>:<processing unit>:id,...|
           date=<mm-dd-yyyy>|
           time=<hh:mm:ss>|
           network=<*|[ip],[host],[gateway],[netmask]>|
           HMC_passwd=<currentpasswd,newpasswd>|
           admin_passwd=<currentpasswd,newpasswd>|
           general_passwd=<currentpasswd,newpasswd>|
           *_passwd=<currentpasswd,newpasswd>|
           hostname=<*|hostname>
   FSP/CEC (using Direct FSP Management) Specific:
       rspconfig <noderange> HMC_passwd=<currentpasswd,newpasswd>
       rspconfig <noderange> admin_passwd=<currentpasswd,newpasswd>
       rspconfig <noderange> general_passwd=<currentpasswd,newpasswd>
       rspconfig <noderange> *_passwd=<currentpasswd,newpasswd>
       rspconfig <noderange> [sysname]
       rspconfig <noderange> [sysname=<*|name>]
       rspconfig <noderange> [pending_power_on_side]
       rspconfig <noderange> [pending_power_on_side=<temp|perm>]
       rspconfig <noderange> [cec_off_policy]
       rspconfig <noderange> [cec_off_policy=<poweroff|stayon>]
       rspconfig <noderange> [BSR]
       rspconfig <noderange> --resetnet
   BPA/Frame (using Direct FSP Management)specific:
       rspconfig <noderange> HMC_passwd=<currentpasswd,newpasswd>
       rspconfig <noderange> admin_passwd=<currentpasswd,newpasswd>
       rspconfig <noderange> general_passwd=<currentpasswd,newpasswd>
       rspconfig <noderange> *_passwd=<currentpasswd,newpasswd>
       rspconfig <noderange> [frame]
       rspconfig <noderange> frame=<*|frame>
       rspconfig <noderange> [sysname]
       rspconfig <noderange> [sysname=<*|name>]
       rspconfig <noderange> [pending_power_on_side]
       rspconfig <noderange> [pending_power_on_side=<temp|perm>]
       rspconfig <noderange> --resetnet
   HMC specific:
       rspconfig <noderange>  [sshcfg]
       rspconfig <noderange>  [sshcfg=<enable|disable>]
   CEC|Frame(using ASM)Specific:
       rspconfig <noderange>  [dev|celogin1]
       rspconfig <noderange>  [dev=<enable|disable>]|
       rspconfig <noderange>  [celogin1=<enable|disable>]
    ",
    "getmacs" => 
"Usage: 
   Common:
       getmacs [-h|--help|-v|--version]
   PPC specific:
       getmacs <noderange> [-F filter] 
       getmacs <noderange> [-V| --verbose] [-f] [-d] [--arp] | [-D [-S server] [-G gateway] [-C client]]
   blade specific:
       getmacs <noderange> [-V| --verbose] [-d] [--arp]
",
    "mkvm" => 
"Usage:
    Common:
       mkvm [-h|--help|-v|--version]
    For PPC(with HMC):
       mkvm noderange -i id -l singlenode [-V|--verbose]
       mkvm noderange -c destcec -p profile [-V|--verbose]
       mkvm noderange --full [-V|--verbose]
    For KVM
       mkvm noderange -m|--master mastername -s|--size disksize -f|--force",
    "lsvm" => 
"Usage:
   Common:
       lsvm <noderange> [-V|--verbose]
       lsvm [-h|--help|-v|--version]
   PPC (with HMC) specific:
       lsvm <noderange> [-a|--all]
   PPC (using Direct FSP Management) specific:
       lsvm <noderange> [-l|--long]",
    "chvm" => 
"Usage:
   Common:
       chvm [-h|--help|-v|--version]
   PPC (with HMC) specific:
       chvm <noderange> [-p profile][-V|--verbose] 
       chvm <noderange> <attr>=<val> [<attr>=<val>...]
   PPC (using Direct FSP Management) specific:
       chvm <noderange> [-p <profile>]
       chvm <noderange> [lparname=<*|name>]
       chvm <noderange> -i <id> [-m <memory_interleaving>] -r <partition_rule>
   VMware specific:
       chvm <noderange> [-a size][-d disk][-p disk][--resize disk=size][--cpus count][--mem memory]",
    "rmvm" => 
"Usage: rmvm <noderange> [--service][-V|--verbose] 
       rmvm [-h|--help|-v|--version],
       rmvm [-p] [-f]",
    "lsslp" =>
"Usage: lsslp [-h|--help|-v|--version]
       lsslp [<noderange>][-V|--verbose][-i ip[,ip..]][-w][-r|-x|-z][-n][-I][-s FRAME|CEC|MM|IVM|RSA|HMC][-C counts][-T timeout]
             [-t tries][-m][-e cmd][-c [timeinterval[interval,..]]][--vpdtable]
             [-M vpd|switchport][--makedhcp][--updatehost][--resetnet]",
  "rflash" =>
"Usage: 
    rflash [ -h|--help|-v|--version]
    PPC (with HMC) specific:
	rflash <noderange> -p <rpm_directory> [--activate concurrent | disruptive][-V|--verbose] 
	rflash <noderange> [--commit | --recover] [-V|--verbose]
    PPC (using Direct FSP Management) specific:
	rflash <noderange> -p <rpm_directory> --activate disruptive [-d <data_directory>]
	rflash <noderange> [--commit | --recover] [-V|--verbose]",
    "mkhwconn" =>
"Usage:
    mkhwconn [-h|--help]
    
    PPC (with HMC) specific:
    mkhwconn noderange -t [--bind] [-V|--verbose]
    mkhwconn noderange -p single_hmc [-P HMC passwd] [-V|--verbose]
    
    PPC (using Direct FSP Management) specific:
    mkhwconn noderange -t [-T tooltype] [--port port_value]
    mkhwconn noderange -s [hmcnode] [-P HMC passwd] [-V|--verbose]",
    "rmhwconn" =>
"Usage:
    rmhwconn [-h|--help]
    
    PPC (with HMC) specific:
    rmhwconn noderange [-V|--verbose]
    
    PPC (using Direct FSP Management) specific:
    rmhwconn noderange [-T tooltype]
    rmhwconn noderange -s",
    "lshwconn" =>
"Usage:
    lshwconn [-h|--help]
    
    PPC (with HMC) specific:
    lshwconn noderange [-V|--verbose]
    
    PPC (using Direct FSP Management) specific:
    lshwconn noderange [-T tooltype]
    lshwconn noderange -s",
    "renergy" =>
"Usage:
    renergy [-h | --help] 
    renergy [-v | --version] 

    Power 6 server specific :
    renergy noderange [-V] { all | { [savingstatus] [cappingstatus] [cappingmaxmin] [cappingvalue] [cappingsoftmin] [averageAC] [averageDC] [ambienttemp] [exhausttemp] [CPUspeed] } }
    renergy noderange [-V] { {savingstatus}={on | off} | {cappingstatus}={on | off} | {cappingwatt}=watt | {cappingperc}=percentage } 

    Power 7 server specific :
    renergy noderange [-V] { all | { [savingstatus] [dsavingstatus] [cappingstatus] [cappingmaxmin] [cappingvalue] [cappingsoftmin] [averageAC] [averageDC] [ambienttemp] [exhausttemp] [CPUspeed] [syssbpower] [sysIPLtime] [fsavingstatus] [ffoMin] [ffoVmin] [ffoTurbo] [ffoNorm] [ffovalue] } }
    renergy noderange [-V] { {savingstatus}={on | off} | {dsavingstatus}={on-norm | on-maxp | off} | {fsavingstatus}={on | off} | {ffovalue}=MHZ | {cappingstatus}={on | off} | {cappingwatt}=watt | {cappingperc}=percentage }

    Blade specific :
    renergy noderange [-V] { all | pd1all | pd2all | { [pd1status] [pd2status] [pd1policy] [pd2policy] [pd1powermodule1] [pd1powermodule2] [pd2powermodule1] [pd2powermodule2] [pd1avaiablepower] [pd2avaiablepower] [pd1reservedpower] [pd2reservedpower] [pd1remainpower] [pd2remainpower] [pd1inusedpower] [pd2inusedpower] [availableDC] [averageAC] [thermaloutput] [ambienttemp] [mmtemp] } }
    renergy noderange [-V] { all | { [averageDC] [capability] [cappingvalue] [CPUspeed] [maxCPUspeed] [savingstatus] [dsavingstatus] } }
    renergy noderange [-V] { {savingstatus}={on | off} | {dsavingstatus}={on-norm | on-maxp | off} }",
  "updatenode" =>
"Usage:
    updatenode [-h|--help|-v|--version]
    or
    updatenode <noderange> [-V|--verbose] [-k|--security] [-s|--sn]
    or
    updatenode <noderange> [-V|--verbose] [-k|--security] [--user] 
        [--devicetype]
    or
    updatenode <noderange> [-V|--verbose] [-F|--sync | -f|--snsync] [-S|--sw] 
        [-P|--scripts [script1,script2,...]] [-s|--sn] 
        [-A|--updateallsw] [-c|--cmdlineonly] [-d alt_source_dir]
        [attr=val [attr=val...]]
    or
    updatenode <noderange> [-V|--verbose] [script1,script2,...]

Options:
    <noderange> A list of nodes or groups.

    [-k|--security] Update the security keys and certificates for the 
        target nodes.

    [-k|--security] [--user] [--devicetype] Update the ssh keys for 
        specific device.

    [-F|--sync] Perform File Syncing.

    [-f|--snsync] Performs File Syncing to the service nodes that service 
        the nodes in the noderange.

    [-S|--sw] Perform Software Maintenance.

    [-P|--scripts] Execute postscripts listed in the postscripts table or 
        parameters.

    [-c|--cmdlineonly] Only use AIX software maintenance information 
        provided on the command line. (AIX only)

    [-s|--sn] Set the server information stored on the nodes.

    [-A|--updateallsw] Install or update all software contained in the source 
        directory. (AIX only)

    [-d <alt_source_dir>] Used to indicate a source directory other than
        the standard lpp_source directory specified in the xCAT osimage 
        definition.  (AIX only)

    [script1,script2,...] A comma separated list of postscript names. 
        If omitted, all the post scripts defined for the nodes will be run.

    [attr=val [attr=val...]]  Specifies one or more 'attribute equals value' 
        pairs, separated by spaces. (AIX only)",
  "lsflexnode" =>
"Usage:
    lsflexnode [-h|--help|-v|--version]
    lsflexnode <noderange>",
  "mkflexnode" =>
"Usage:
    mkflexnode [-h|--help|-v|--version]
    mkflexnode <noderange>",
  "nodeset" =>
"Usage:
   Common:
      nodeset [-h|--help|-v|--version]
      nodeset <noderange> [install|shell|boot|runcmd=bmcsetup|netboot|iscsiboot|osimage=<imagename>|statelite]",
  "rmflexnode" =>
"Usage:
    rmflexnode [-h|--help|-v|--version]
    rmflexnode <noderange>",
);
my $vers = xCAT::Utils->Version();
my %version = (
    "rnetboot" => "$vers",
    "rpower" => "$vers",
    "rbeacon" => "$vers",
    "rvitals" => "$vers",
    "reventlog" => "$vers",
    "rinv" => "$vers",
    "rsetboot" => "$vers",
    "rbootseq" => "$vers",
    "rscan" => "$vers",
    "rspconfig" => "$vers",
    "getmacs" => "$vers",
    "mkvm" => "$vers",
    "lsvm" => "$vers",
    "chvm" => "$vers",
    "rmvm" => "$vers",
    "lsslp" => "$vers",
    "rflash" => "$vers",
    "renergy" => "$vers",
    "lsflexnode" => "$vers",
    "mkflexnode" => "$vers",
    "rmflexnode" => "$vers",
    "nodeset" => "$vers"
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

  Getopt::Long::Configure('pass_through','no_ignore_case');

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

