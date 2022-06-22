#!/usr/bin/perl
###############################################################################
#      (c) Copyright International Business Machines Corporation 2016.
#                               All Rights Reserved.
###############################################################################
# COMPONENT: prep_zxcatIVP_LIBERTY.pl
#
# This is a preparation script for Installation Verification Program for xCAT
# on z/VM.  It prepares the driver script by gathering information from
# OpenStack configuration files on the compute node.
###############################################################################

use strict;
use warnings;

use File::Basename;
use File::Spec;
use Getopt::Long;
use MIME::Base64;
use Sys::Hostname;
use Socket;

my %commonConf;             # Common configuration options
my %ceilometerConf;         # Ceilometer configuration options
my %cinderConf;             # Cinder configuration options
my %novaConf;               # Nova configuration options
my %neutronConf;            # Neutron configuration options
my %ml2ConfIni;             # Neutron m12 configuration options
my %neutronZvmPluginIni;    # Neutron zvm configuration options

my $version = "5.0";
my $supportString = "This script supports code based on the OpenStack Liberty release.";

my $cmaAppliance     = 0;     # Assumed to not be run in a CMA system
my $cmaVersionString = '';    # CMA version string for a CMA
my $cmaSystemRole    = '';    # CMA system role string
my $commonOpts = ' host xcat_zhcp_nodename zvm_host zvm_xcat_master zvm_xcat_server zvm_xcat_username zvm_xcat_password ';

# Common options that can be specified in more than one configuration file
my $configFound = 0;    # At least 1 config file was found.  Defaults to false.
my $driver;             # Name of driver file to be created less the ".pl"
my $driverLocation = "/opt/xcat/bin/"; # Location of the IVP program in xCAT MN.
my $driverPrefix = "zxcatIVPDriver_"; # Prefix used in naming the driver program.
my $driverSuffix;    # Suffix used in naming the driver program.
my $displayHelp = 0; # Display help information.
my $host;            # Host command option value
my $initSuffix;      # Suffix used in naming multihomed init scripts
my $ivp           = "zxcatIVP.pl";                   # z/VM xCAT IVP script name
my $obfuscateProg = '/usr/bin/openstack-obfuscate';  # PW obfuscation program
my $pwVisible = 0;    # PW is visible in the driver script (1 = yes, 0 = no)
my $scan;             # Type of scan to be performed
my $verbose;          # Verbose flag - 0: quiet, 1: verbose
my $versionOpt = 0;   # Shov version information.

my $localIpAddress = '';    # Local IP address of system where we are prepping

# Locations of configuration files
my $locCeilometerConf      = '/etc/ceilometer/ceilometer.conf';
my $locCinderConf          = '/etc/cinder/cinder.conf';
my $locMl2ConfIni          = '/etc/neutron/plugins/ml2/ml2_conf.ini';
my $locNeutronConf         = '/etc/neutron/neutron.conf';
my $locNeutronZvmPluginIni = '/etc/neutron/plugins/zvm/neutron_zvm_plugin.ini';
my $locNovaConf            = '/etc/nova/nova.conf';

# Version related files
my $locVersionFileCMO = '/opt/ibm/cmo/version';
my $locDMSSICMOCopy   = '/var/lib/sspmod/DMSSICMO.COPY';
my $locApplSystemRole = '/var/lib/sspmod/appliance_system_role';

# Stems of startup scripts in /etc/init.d that can be scanned for
# configuration files names and locations.
my $ceilometerStem      = 'openstack-ceilometer-api';
my $neutronZvmAgentStem = 'neutron-zvm-agent';
my $novaComputeStem     = 'openstack-nova-compute';

# Eyecatchers used with --config operand
my $EyeCeilometerConf      = 'ceilometer_conf';
my $EyeCinderConf          = 'cinder_conf';
my $EyeMl2ConfIni          = 'm12_conf';
my $EyeNeutronConf         = 'neutron_conf';
my $EyeNeutronZvmPluginIni = 'neutron_zvm_plugin_conf';
my $EyeNovaConf            = 'nova_conf';

# set the usage message
my $usage_string = "Usage:\n
    $0\n
    or\n
    $0 -s serviceToScan -d driverProgramName\n
    or\n
    $0 --scan serviceToScan -driver driverProgramName\n
    The following options are supported:

      -c | --config <val>
             List of configuration files to be processed.  This list overrides
             the default configuration file locations or the ones determined by
             the --init-files operand.  Each configuration file is identified
             by an eyecatcher indicating which configuration file is being
             overriden followed by a colon and the fully qualified file
             specification.  Multiple configuration files may be specified by
             separating them with a comma (one file per eyecatcher).
             The following are recognized eyecathers and the files that they
             override:
               $EyeCeilometerConf - $locCeilometerConf
               $EyeCinderConf - $locCinderConf
               $EyeMl2ConfIni - $locMl2ConfIni
               $EyeNeutronConf - $locNeutronConf
               $EyeNeutronZvmPluginIni -
                 $locNeutronZvmPluginIni
               $EyeNovaConf - $locNovaConf
      -d | --driver       File specification of driver program to construct,
             or name of directory to contain the driver program.
      -h | --help         Display help information.
      -H | --host <val>   Name of z/VM host to process.  Startup scripts end
             with this suffix for the specified z/VM system. When this option is
             used with the -i option, it indicates which startup scripts should
             be scanned.
             The driver script created will contain the host value as part of
             its name.
      -i | --init-files   Scan the system for either System V style startup
             scripts or systemd service files related to OpenStack.  The
             files are scanned for the name of the related configuration file.
             For System V, /etc/init.d directory is scanned.  For systemd, it
             will scan /usr/lib/systemd/system/, /run/systemd/system/, and
             /etc/systemd/system/ service files (.service).
           --help         Display help information.
      -p | --password-visible
                          If specified, password values in the constructed
                          driver script program will be visible.  Otherwise,
                          password values are hidden.  This option is used
                          when building a driver script to run against an
                          older xCAT MN.
      -s | --scan         Services to scan ('all', 'nova' or 'neutron').
      -v                  Display script version information.
      -V | --verbose      Display verbose processing messages.\n";

#-------------------------------------------------------

=head3   buildDriverProgram

    Description : Build or update the driver program with the
                  data obtained by the scans.
    Arguments   : None
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = buildDriverProgram();

=cut

#-------------------------------------------------------
sub buildDriverProgram {
    my $rc;
    my @driverText;

    if ($verbose) {
        print "Building the IVP driver program.\n";
    }

    # Erase any existing driver program.
    if (-e $driver and !-z $driver) {

        # Make certain the file is one of our driver files.
        my $found = `grep 'Function: z/VM xCAT IVP driver program' $driver`;
        if (!$found) {
            print "$driver is not a z/VM xCAT IVP driver program\n";
            print "File will not be changed.\n";
            return 251;
        } else {

            # Rename the existing driver file.
            print "Existing driver file is being saved as $driver.old\n";
            rename $driver, "$driver.old";
        }
    }

    # Open the driver program for output.
    $rc = open(my $fileHandle, '>', $driver);
    if (!defined $rc or $rc ne '1') {
        print "Unable to open $driver for output: $!\n";
        return 200;
    }

    # Construct the file in an array.
    push(@driverText, "#!/bin/bash");
    push(@driverText, "# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html");
    push(@driverText, "#");
    push(@driverText, "# Function: z/VM xCAT IVP driver program");
    push(@driverText, "#           Built by $0 version $version.");
    push(@driverText, "#           $supportString");
    push(@driverText, "");
    if ($cmaAppliance == 1) {
        push(@driverText, "# System is a CMA");
        push(@driverText, "# CMA system role: $cmaSystemRole");
        push(@driverText, "# $cmaVersionString");
        push(@driverText, "");
    }
    push(@driverText, "############## Start of Nova Config Properties");
    if (exists $novaConf{'DEFAULT'}{'my_ip'}) {
        push(@driverText, "");
        push(@driverText, "# IP address or hostname of the compute node that is accessing this xCAT MN.");
        push(@driverText, "# From \'my_ip\' in $locNovaConf.");
        push(@driverText, "export zxcatIVP_cNAddress=\"$novaConf{'DEFAULT'}{'my_ip'}\"");
    } else {
        if ($locNovaConf ne '') {
            print "Info: 'my_ip' property is missing from section 'DEFAULT'\n" .
              "      in $locNovaConf.  A default value of '$localIpAddress'\n" .
"      has been specified in the driver program for zxcatIVP_cNAddress.\n" .
"      If the value is not correct then you should update the driver file\n" .
              "      with the desired IP address.\n";
        } else {
            print "Info: The Nova configuration file was not found and thus this script is unable\n" .
"      to use the 'my_ip' property.  A default value of '$localIpAddress'\n" .
"      has been specified in the driver program for zxcatIVP_cNAddress.\n" .
"      If the value is not correct then you should update the driver file\n" .
              "      with the desired IP address.\n";
        }
        push(@driverText, "");
        push(@driverText, "# IP address or hostname of the compute node that is accessing this xCAT MN.");
        push(@driverText, "# From the local IP address of this system.");
        push(@driverText, "export zxcatIVP_cNAddress=\"$localIpAddress\"");
    }
    if (exists $novaConf{'DEFAULT'}{'zvm_user_profile'}) {
        push(@driverText, "");
        push(@driverText, "# Default profile used in creation of server instances.");
        push(@driverText, "# From \'zvm_user_profile\' in $locNovaConf.");
        push(@driverText, "export zxcatIVP_defaultUserProfile=\"$novaConf{'DEFAULT'}{'zvm_user_profile'}\"");
    }
    if (exists $novaConf{'DEFAULT'}{'zvm_diskpool'}) {
        push(@driverText, "");
        push(@driverText, "# Array of disk pools that are expected to exist.");
        push(@driverText, "# From \'zvm_diskpool\' in $locNovaConf.");
        push(@driverText, "export zxcatIVP_diskpools=\"$novaConf{'DEFAULT'}{'zvm_diskpool'}\"");
    }

    if (exists $novaConf{'DEFAULT'}{'zvm_fcp_list'}) {
        push(@driverText, "");
        push(@driverText, "# The list of FCPs used by instances.");
        push(@driverText, "# From \'zvm_fcp_list\' in $locNovaConf.");
        push(@driverText, "export zxcatIVP_instFCPList=\"$novaConf{'DEFAULT'}{'zvm_fcp_list'}\"");
    }
    if (exists $commonConf{'zvm_host'}{'value'}) {
        push(@driverText, "");
        push(@driverText, "# Node of host being managed.  If blank, IVP will search for the host node.");
        push(@driverText, "# From:");
        push(@driverText, split('\n', $commonConf{'zvm_host'}{'fromLines'}));
        push(@driverText, "export zxcatIVP_hostNode=\"$commonConf{'zvm_host'}{'value'}\"");

    }
    if (exists $commonConf{'zvm_xcat_master'}{'value'}) {
        push(@driverText, "");
        push(@driverText, "# Node name for xCAT MN (optional).");
        push(@driverText, "# From:");
        push(@driverText, split('\n', $commonConf{'zvm_xcat_master'}{'fromLines'}));
        push(@driverText, "export zxcatIVP_mnNode=\"$commonConf{'zvm_xcat_master'}{'value'}\"");
    }
    if (exists $commonConf{'zvm_xcat_password'}{'value'}) {
        my $clearPW = '';
        push(@driverText, "");
        push(@driverText, "# User password defined to communicate with xCAT MN.");
        push(@driverText, "# From:");
        push(@driverText, split('\n', $commonConf{'zvm_xcat_master'}{'fromLines'}));

        if (-e $obfuscateProg) {

            # assume password is obfuscated already and get it in the clear.
            $clearPW = `$obfuscateProg -u $commonConf{'zvm_xcat_password'}{'value'}`;
            $clearPW =~ s/\n+$//g;    # trim ending new line
        } else {

            # Assume password is in the clear because the obfuscation program is missing.
            $clearPW = $commonConf{'zvm_xcat_password'}{'value'};
        }

        if ($pwVisible) {
            push(@driverText, "export zxcatIVP_xcatUserPw=\"$clearPW\"");
            push(@driverText, "export zxcatIVP_pw_obfuscated=0");
        } else {
            my $hiddenPW = obfuscate($clearPW, 1);
            push(@driverText, "# Note: Password is hidden.");
            push(@driverText, "#       To override the support and pass the password in the");
            push(@driverText, "#       clear, either:");
            push(@driverText, "#         - specify the -p or --password-visible operand when");
            push(@driverText, "#           invoking prep_zxcatIVP.pl script, or");
            push(@driverText, "#         - change zxcatIVP_pw_obfuscated variable to 0 and");
            push(@driverText, "#           specify the password in the clear on the");
            push(@driverText, "#           zxcatIVP_xcatUserPw variable in the constructed");
            push(@driverText, "#           driver script.");
            push(@driverText, "export zxcatIVP_xcatUserPw=\"$hiddenPW\"");
            push(@driverText, "export zxcatIVP_pw_obfuscated=1");
        }
    }
    if (exists $commonConf{'zvm_xcat_server'}{'value'}) {
        push(@driverText, "");
        push(@driverText, "# Expected IP address of the xcat MN");
        push(@driverText, "# From:");
        push(@driverText, split('\n', $commonConf{'zvm_xcat_server'}{'fromLines'}));
        push(@driverText, "export zxcatIVP_xcatMNIp=\"$commonConf{'zvm_xcat_server'}{'value'}\"");
    }
    if (exists $commonConf{'zvm_xcat_username'}{'value'}) {
        push(@driverText, "");
        push(@driverText, "# User defined to communicate with xCAT MN");
        push(@driverText, "# From:");
        push(@driverText, split('\n', $commonConf{'zvm_xcat_server'}{'fromLines'}));
        push(@driverText, "export zxcatIVP_xcatUser=\"$commonConf{'zvm_xcat_username'}{'value'}\"");
    }
    if (exists $novaConf{'DEFAULT'}{'zvm_zhcp_fcp_list'}) {
        push(@driverText, "");
        push(@driverText, "# The list of FCPs used by zHCP.");
        push(@driverText, "# From \'zvm_zhcp_fcp_list\' in $locNovaConf.");
        push(@driverText, "export zxcatIVP_zhcpFCPList=\"$novaConf{'DEFAULT'}{'zvm_zhcp_fcp_list'}\"");
    }
    if (exists $novaConf{'DEFAULT'}{'xcat_free_space_threshold'}) {
        push(@driverText, "");
        push(@driverText, "# Expected space available in the xCAT MN image repository");
        push(@driverText, "# From \'xcat_free_space_threshold\' in $locNovaConf.");
        push(@driverText, "export zxcatIVP_expectedReposSpace=\"$novaConf{'DEFAULT'}{'xcat_free_space_threshold'}G\"");
    }

    push(@driverText, "");
    push(@driverText, "############## End of Nova Config Properties");

    if ((keys %neutronConf) or (keys %neutronZvmPluginIni) or (keys %ml2ConfIni)) {
        push(@driverText, "");
        push(@driverText, "############## Start of Neutron Config Properties");
        if (exists $neutronConf{'DEFAULT'}{'base_mac'}) {
            my $prefix = $neutronConf{'DEFAULT'}{'base_mac'};
            $prefix =~ tr/://d;
            $prefix = substr($prefix, 0, 6);
            push(@driverText, "");
            push(@driverText, "# User prefix for MAC Addresses of Linux level 2 interfaces");
            push(@driverText, "# From \'base_mac\' in $locNeutronConf.");
            push(@driverText, "export zxcatIVP_macPrefix=\"$prefix\"");
        }
        if (exists $neutronZvmPluginIni{'agent'}{'xcat_mgt_ip'}) {
            push(@driverText, "");
            push(@driverText, "# xCat MN's address on the xCAT management network");
            push(@driverText, "# From \'xcat_mgt_ip\' in $locNeutronZvmPluginIni.");
            push(@driverText, "export zxcatIVP_xcatMgtIp=\"$neutronZvmPluginIni{'agent'}{'xcat_mgt_ip'}\"");
        }
        if (exists $neutronZvmPluginIni{'agent'}{'xcat_mgt_mask'}) {
            push(@driverText, "");
            push(@driverText, "# xCat management interface netmask");
            push(@driverText, "# From \'xcat_mgt_mask\' in $locNeutronZvmPluginIni.");
            push(@driverText, "export zxcatIVP_mgtNetmask=\"$neutronZvmPluginIni{'agent'}{'xcat_mgt_mask'}\"");
        }
        if (exists $ml2ConfIni{'ml2_type_flat'}{'flat_networks'} or
            exists $ml2ConfIni{'ml2_type_vlan'}{'network_vlan_ranges'}) {
            my $list = '';
            if (exists $ml2ConfIni{'ml2_type_flat'}{'flat_networks'} and
                $ml2ConfIni{'ml2_type_flat'}{'flat_networks'} ne '*') {
                $list = $ml2ConfIni{'ml2_type_flat'}{'flat_networks'};
            }
            if (exists $ml2ConfIni{'ml2_type_vlan'}{'network_vlan_ranges'}) {
                if ($list ne '') {
                    $list = "$list,";
                }
                $list = "$list$ml2ConfIni{'ml2_type_vlan'}{'network_vlan_ranges'}";
            }
            $list =~ s/^\s+|\s+$//g;    # trim blanks from both ends of the list
            if ($list ne '') {
                push(@driverText, "");
                push(@driverText, "# Array of networks and possible VLAN ranges");
                push(@driverText, "# From $locMl2ConfIni,");
                push(@driverText, "#     \'flat_networks\' in section \'ml2_type_flat\' and ");
                push(@driverText, "#     \'network_vlan_ranges\' in section \'ml2_type_vlan\'.");
                push(@driverText, "export zxcatIVP_networks=\"$list\"");
            }
        }
        if (exists $commonConf{'xcat_zhcp_nodename'}{'value'}) {
            push(@driverText, "");
            push(@driverText, "# Node name for xCAT zHCP server");
            push(@driverText, "# From:");
            push(@driverText, split('\n', $commonConf{'xcat_zhcp_nodename'}{'fromLines'}));
            push(@driverText, "export zxcatIVP_zhcpNode=\"$commonConf{'xcat_zhcp_nodename'}{'value'}\"");
        }

        # Create the zxcatIVP_vswitchOSAs variable for any networks specified with an rdev list.
        my $vswitchOSAs = '';
        foreach my $section (sort keys %neutronZvmPluginIni) {
            next if ($section eq 'agent');
            foreach my $property (keys %{ $neutronZvmPluginIni{$section} }) {
                next if ($property ne "rdev_list");
                my $list = $neutronZvmPluginIni{$section}{$property};
                $list =~ s/^\s+|\s+$//g; # trim blanks from both ends of the list
                next if ($list eq '');
                $list =~ s/\s+/\,/g;     # insert comma between words
                $vswitchOSAs = "$section $list $vswitchOSAs";
            }
        }
        if ($vswitchOSAs ne '') {
            push(@driverText, "");
            push(@driverText, "# Vswitches and their related OSAs");
            push(@driverText, "# From \'rdev_list\' in vswitch sections of $locNeutronZvmPluginIni.");
            push(@driverText, "export zxcatIVP_vswitchOSAs=\"$vswitchOSAs\"");
        }

        push(@driverText, "");
        push(@driverText, "############## End of Neutron Config Properties");
    }

    push(@driverText, "");
    push(@driverText, "# Name of user under which nova runs, default is nova.");
    push(@driverText, "# If you system is different then change this property.");
    push(@driverText, "export zxcatIVP_expUser=\"nova\"");
    push(@driverText, "");
    push(@driverText, "# Controls whether Warnings/Errors detected by the IVP are");
    push(@driverText, "# logged in the xCAT MN syslog, 0: do not log, 1: log to syslog.");
    push(@driverText, "export zxcatIVP_syslogErrors=1");
    push(@driverText, "");
    push(@driverText, "perl $driverLocation$ivp");

    # Write the array to the driver file.
    foreach (@driverText) {

        #print "$_\n";
        print $fileHandle "$_\n";    # Print each entry in our array to the file
    }

    close $fileHandle;

    print "$driver was built.\n";
    return 0;
}

#-------------------------------------------------------

=head3   hashFile

    Description : Read a file with equal signs designating
                  key value pairs and create a hash from it.
    Arguments   : File to read
                  Reference to hash that should be constructed.
                  File is required to exist or there is a serious error.
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = hashFile( $file, \%novaConf, 1 );

=cut

#-------------------------------------------------------
sub hashFile {
    my ($file, $hash, $required) = @_;
    my $section       = "null";
    my $caseSensitive = 0;      # assume section/properties are case insensitive
    my @parts;
    my $out;

    # Clear the hash
    %$hash = ();

    if ($file eq '') {
        return 602;
    }

    if (!-e $file) {
        if ($required) {
            print "Warning: $file does not exist.\n";
        } else {
            print "Info: $file does not exist.\n";
        }
        return 601;
    }

    if (($file =~ /.conf$/) or ($file =~ /.service$/) or ($file =~ /.COPY$/)) {

        # File is case sensitive, translate sections and property names to uppercase.
        $caseSensitive = 1;
    }

    # Read the configuration file and construct the hash of values.
    if (($file =~ /.conf$/) or ($file =~ /.ini$/) or ($file =~ /.service$/)) {
        $out = `egrep -v '(^#|^\\s*\\t*#)' $file`;
        my $rc = $?;
        if ($rc != 0) {
            if ($required) {
                print "Warning: $file cannot be read.\n" .
"         Verification continues but without properties from the indicated file.\n";
            } else {
                print "Info: $file cannot be read.\n" .
"      Verification continues but without properties from the indicated file.\n";
            }
            return 603;
        }
        my @lines = split("\n", $out);
        foreach my $line (@lines) {
            if ($line =~ /^\[/) {

                # Section header line
                $line =~ s/^\s+|\s+$//g; # trim blanks from both ends of the line
                $line =~ s/^\[+|\]+$//g; # trim [] from ends of the line
                if (!$caseSensitive) {
                    $section = lc($line);
                } else {
                    $section = $line;
                }
            } else {

                # Property line
                @parts = split("=", $line, 2);
                next if (!exists $parts[0]);
                $parts[0] =~ s/^\s+|\s+$//g;    # trim both ends of the string
                next if (length($parts[0]) == 0);
                if (!$caseSensitive) {
                    $parts[0] = lc($parts[0]);
                }

                if (exists $parts[1]) {
                    chomp($parts[1]);
                    $parts[1] =~ s/^\s+|\s+$//g;  # trim both ends of the string
                } else {
                    $parts[1] = '';
                }

                $$hash{$section}{ $parts[0] } = $parts[1];

                #print "$section $parts[0]" . ": " . $parts[1]. "\n";
                #print $parts[0] . ": " . $$hash{$section}{$parts[0]}. "\n";
            }
        }
    } else {

        # Hash .COPY files
        # Read the file and remove comment lines
        $out = `grep -v ^\$ $file`;
        my $rc = $?;
        if ($rc != 0) {
            if ($required) {
                print "Warning: $file cannot be read.\n" .
"         Verification continues but without properties from the indicated file.\n";
            } else {
                print "Info: $file cannot be read.\n" .
"      Verification continues but without properties from the indicated file.\n";
            }
            return 604;
        }
        $out =~ s{/\*.*?\*/}{}gs;

        my @lines = split("\n", $out);
        foreach my $line (@lines) {

            # Remove sequence numbers and weed out blank lines
            $line = substr($line, 0, 71);
            $line =~ s/^\s+|\s+$//g;    # trim both ends of the string
            next if (length($line) == 0);

            # Parse the line
            @parts = split("=", $line, 2);
            next if (!exists $parts[0]);
            $parts[0] =~ s/^\s+|\s+$//g;    # trim both ends of the string
            next if (length($parts[0]) == 0);
            if (!$caseSensitive) {
                $parts[0] = lc($parts[0]);
            }

            # Add the property to the hash if it has data.
            if (exists $parts[1]) {
                chomp($parts[1]);
                $parts[1] =~ s/^\s+|\s+$//g;    # trim both ends of the string
                $parts[1] =~ s/^"+|"+$//g; # trim double quotes from both ends of the string
            } else {
                $parts[1] = '';
            }

            $$hash{ $parts[0] } = $parts[1];

            #print $parts[0] . ": " . $$hash{$parts[0]}. "\n";
        }
    }

    return 0;
}

#-------------------------------------------------------

=head3   obfuscate

    Description : Build or update the driver program with the
                  data obtained by the scans.
    Arguments   : string to be processed
                  direction: 1 - obfuscate (hide it!)
                             0 - unobfuscate (unhide it!)
    Returns     : processed password (either hiden or unhidden))
    Example     : $rc = obfuscate( $pw, 1 );

=cut

#-------------------------------------------------------
sub obfuscate {
    my ($pw, $hide) = @_;

    if ($hide == 1) {
        $pw = encode_base64($pw, '');
    } else {
        $pw = decode_base64($pw);
    }

    return $pw;
}

#-------------------------------------------------------

=head3   saveCommonOpt

    Description : Save a common option for later use and
                  verify the value is consistent.
    Arguments   : option
                  section that contained the option
                  configuration file name
                  name of the option in the commonConf hash
                  value
    Returns     : 0 - No error
                  1 - Already saved with a different value
    Example     : $rc = saveCommonOpt( $confFile, $opt, $section, $confFile $commonOptName, $value );

=cut

#-------------------------------------------------------
sub saveCommonOpt {
    my ($opt, $section, $confFile, $commonOptName, $value) = @_;
    my $rc = 0;

    if (!exists $commonConf{$commonOptName}) {
        $commonConf{$commonOptName}{'value'} = $value;
        $commonConf{$commonOptName}{'fromLines'} = '#   ' . $opt . ' in ' . $confFile;
        $commonConf{$commonOptName}{'firstOpt'}     = $opt;
        $commonConf{$commonOptName}{'firstSection'} = $section;
        $commonConf{$commonOptName}{'firstConf'}    = $confFile;
    } else {
        if ($commonConf{$commonOptName}{'value'} eq $value) {
            $commonConf{$commonOptName}{'fromLines'} = $commonConf{$commonOptName}{'fromLines'} .
              "\n#   " . $opt . " in " . $confFile;
        } else {
            print "Warning: \'$opt\' property in section \'$section\'\n" .
              "         in $confFile\n" .
              "         has a value that is different from the value of the\n" .
"         \'$commonConf{$commonOptName}{'firstOpt'}\' property in section \'$commonConf{$commonOptName}{'firstSection'}\'\n" .
              "         in $commonConf{$commonOptName}{'firstConf'}.\n" .
              "         They should be the same.  The value\n" .
              "         in $confFile is:\n" .
              "           $value\n" .
              "         and in $commonConf{$commonOptName}{'firstConf'} is:\n" .
              "           $commonConf{$commonOptName}{'value'}\n";
            $rc = 1;
        }
    }
    return $rc;
}

#-------------------------------------------------------

=head3   scanCeilometer

    Description : Scan the ceilometer configuration files.
    Arguments   : None
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = scanCeilometer();

=cut

#-------------------------------------------------------
sub scanCeilometer {
    my $rc;

    if ($locCeilometerConf eq '') {
        return 602;
    }

    if ($verbose) {
        print "Scanning the Ceilometer configuration files:\n";
        print "  $locCeilometerConf\n";
    }

    # Read the configuration file and construct the hash of values.
    $rc = hashFile($locCeilometerConf, \%ceilometerConf, 0);
    if ($rc == 0) {
        $configFound = 1;
    }

    return $rc;
}

#-------------------------------------------------------

=head3   scanCinder

    Description : Scan the cinder configuration files.
    Arguments   : None
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = scanCinder();

=cut

#-------------------------------------------------------
sub scanCinder {
    my $rc;

    if ($locCinderConf eq '') {
        return 602;
    }

    if ($verbose) {
        print "Scanning the Cinder configuration files:\n";
        print "  $locCinderConf\n";
    }

    # Read the configuration file and construct the hash of values.
    $rc = hashFile($locCinderConf, \%cinderConf, 0);
    if ($rc == 0) {
        $configFound = 1;
    }

    return $rc;
}

#-------------------------------------------------------

=head3   scanInitScript

    Description : Scan the init script for the
                  specified configuration file property.
    Arguments   : Configuration file name
                  Config property containing the value
    Returns     : Null - error locating the config file.
                  Non-null - file specification of the
                  configuration file.
    Example     : $confFile = scanInitScript('openstack-cinder-volume-$host',
                                       'config');

=cut

#-------------------------------------------------------
sub scanInitScript {
    my ($filename, $property) = @_;
    my $configFile = '';
    my $out;

    if (-e $filename) {
        if ($verbose) {
            print "Scanning $filename for '$property' variable.\n";
        }

        # Strip out the lines after the desired config property is set and
        # remove comment lines then echo the property value.
        $out = `awk '{print} /$property=/ {exit}' /etc/init.d/$filename | grep -v ^\#  | grep  .`;
        $out        = $out . "echo -n \$$property";
        $configFile = `$out`;
    }

    return $configFile;
}

#-------------------------------------------------------

=head3   scanNeutron

    Description : Scan the neutron configuration files.
    Arguments   : None
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = scanNeutron();

=cut

#-------------------------------------------------------
sub scanNeutron {
    my $rc;

    if ($locNeutronConf eq '' and $locMl2ConfIni eq ''
        and $locNeutronZvmPluginIni eq '') {
        return 602;
    }

    if ($verbose) {
        print "Scanning the Neutron configuration files:\n";
        print "  $locNeutronConf\n";
        print "  $locMl2ConfIni\n";
        print "  $locNeutronZvmPluginIni\n";
    }

    # Read the configuration file and construct the hash of values.
    $rc = hashFile($locNeutronConf, \%neutronConf, 1);
    if ($rc == 0) {
        $configFound = 1;
    }

    # Read the configuration file and construct the hash of values.
    $rc = hashFile($locMl2ConfIni, \%ml2ConfIni, 1);
    if ($rc == 0) {
        $configFound = 1;
    }

    # Read the configuration file and construct the hash of values.
    $rc = hashFile($locNeutronZvmPluginIni, \%neutronZvmPluginIni, 1);
    if ($rc == 0) {
        $configFound = 1;
    }

    return $rc;
}

#-------------------------------------------------------

=head3   scanNova

    Description : Scan the Nova configuration files.
    Arguments   : None.
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = scanNova();

=cut

#-------------------------------------------------------
sub scanNova {
    my $rc;

    if ($locNovaConf eq '') {
        return 602;
    }

    if ($verbose) {
        print "Scanning the Nova configuration file:\n";
        print "  $locNovaConf\n";
    }

    # Verify the /etc/nova/nova.conf exists.
    $rc = hashFile($locNovaConf, \%novaConf, 1);
    if ($rc == 0) {
        $configFound = 1;
    }

    return $rc;
}

#-------------------------------------------------------

=head3   scanServiceUnit

    Description : Scan the service unit for the
                  specified configuration file property.
    Arguments   : Service file name
                  Section containing the desired property
                  Config property containing the value
    Returns     : Null - error locating the config file.
                  Non-null - file specification of the
                  configuration file.
    Example     : $confFile = scanServiceUnit( 'openstack-cinder-volume-$host',
                                               'Service', 'ExecStart' );

=cut

#-------------------------------------------------------
sub scanServiceUnit {
    my ($filename, $section, $property) = @_;
    my $configFile = '';
    my $out;
    my $serviceFile = '';
    my %serviceFileData;

    # verify the file exists
    if (-e "/etc/systemd/system/$filename") {
        $serviceFile = "/etc/systemd/system/$filename";
    } elsif (-e "/run/systemd/system/$filename") {
        $serviceFile = "/run/systemd/system/$filename";
    } elsif (-e "/usr/lib/systemd/system/$filename") {
        $serviceFile = "/usr/lib/systemd/system/$filename";
    } else {
        return $configFile;    # Unit file was not found
    }

    if ($verbose) {
        print "Scanning $filename for '$property' variable in section $section.\n";
    }

    my $rc = hashFile($serviceFile, \%serviceFileData, 0);
    if ($rc != 0) {
        return $configFile;    # Could not build the hash
    }

    if (exists $serviceFileData{$section}{$property}) {
        my @parms = split(' --config-file ', $serviceFileData{$section}{$property});
        @parms = split(' ', $parms[1]);
        $configFile = $parms[0];
    }

    return $configFile;
}

#-------------------------------------------------------

=head3   showHelp

    Description : Show the help inforamtion.
    Arguments   : None.
    Returns     : None.
    Example     : showHelp();

=cut

#-------------------------------------------------------
sub showHelp {
    print "$0 prepares and builds a z/VM xCAT IVP driver program
    using the information from the configuration files in the
    compute node.

    The default name of the driver program is composed of the following:
      '$driverPrefix', and
      IP address of the system where driver was prepared, and
      (optionally) a hypen and the value specified on --Host operand, and
      '.sh'.
    For example:
      $driverPrefix" . "9.123.345.91.sh
      $driverPrefix" . "9.123.345.91-hostzvm.sh

    $supportString

    The following configuration files are scanned for input:
      $locCeilometerConf
      $locCinderConf
      $locNovaConf
      $locNeutronConf
      $locMl2ConfIni
      $locNeutronZvmPluginIni

    When the --init-files operand is specified, OpenStack startup
    scripts are scanned in /etc/init.d.  The --host operand should
    be specified to indicate the suffix to use for scripts that
    are unique to a specific z/VM host.  The following startup
    scripts are scanned:
      $ceilometerStem-<hostzvm>
      neutron-server
      $neutronZvmAgentStem-<hostzvm>
      $novaComputeStem-<hostzvm>
      openstack-cinder-volume

    When --init-files is specified without the --host operand,
    the following scripts are scanned:
      $ceilometerStem
      neutron-server
      $neutronZvmAgentStem
      $novaComputeStem
      openstack-cinder-volume

    The constructed driver program can then be uploaded to
    the xCAT MN and used to validate the configuration between
    the compute node and xCAT.\n\n";
    print $usage_string;
    return;
}

#-------------------------------------------------------

=head3   validateConfigs

    Description : Compare and validate the configuration
                  values obtained by the scans.
    Arguments   : None.
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = validateConfigs();

=cut

#-------------------------------------------------------
sub validateConfigs {
    my $bypassCinder = 0;
    my $rc           = 0;
    my $option;
    if ($verbose) {
        print "Performing a local validation of the configuration files.\n";
    }

    #*******************************************************
    # Verify required configuration options were specified.
    #*******************************************************
    if (keys %ceilometerConf) {
        my @requiredCeilometerOpts = (
            'DEFAULT', 'host',
            'DEFAULT', 'hypervisor_inspector',
            'zvm',     'zvm_host',
            'zvm',     'zvm_xcat_master',
            'zvm',     'zvm_xcat_password',
            'zvm',     'zvm_xcat_server',
            'zvm',     'zvm_xcat_username',
        );
        for (my $i = 0 ; $i < $#requiredCeilometerOpts ; $i = $i + 2) {
            my $section = $requiredCeilometerOpts[$i];
            my $option  = $requiredCeilometerOpts[ $i + 1 ];
            if (!exists $ceilometerConf{$section}{$option}) {

                #print "option:$option.\nvalue:$ceilometerConf{$section}{$option}\n";
                print "Warning: \'$option\' is missing from section \'$section\'\n" .
                  "      in $locCeilometerConf.\n";
            } else {
                saveCommonOpt($option, $section, $locCeilometerConf, $option, $ceilometerConf{$section}{$option});
            }
        }
    }

    if (keys %cinderConf) {
        my @requiredCinderOpts = ();
        foreach $option (@requiredCinderOpts) {
            if (!exists $cinderConf{'DEFAULT'}{$option}) {

                #print "option:$option.\nvalue:$cinderConf{$option}\n";
                print "Warning: \'$option\' is missing from section \'DEFAULT\'\n" .
                  "      in $locCinderConf.\n";
            }
        }
    }

    if (keys %novaConf) {
        my @requiredNovaOpts = (
            'DEFAULT', 'compute_driver',
            'DEFAULT', 'force_config_drive',
            'DEFAULT', 'host',
            'DEFAULT', 'instance_name_template',
            'DEFAULT', 'zvm_diskpool',
            'DEFAULT', 'zvm_host',
            'DEFAULT', 'zvm_xcat_master',
            'DEFAULT', 'zvm_xcat_server',
            'DEFAULT', 'zvm_xcat_username',
            'DEFAULT', 'zvm_xcat_password',
        );
        for (my $i = 0 ; $i < $#requiredNovaOpts ; $i = $i + 2) {
            my $section = $requiredNovaOpts[$i];
            my $option  = $requiredNovaOpts[ $i + 1 ];
            if (!exists $novaConf{$section}{$option}) {
                print "Warning: \'$option\' is missing from section \'$section\'\n" .
                  "      in $locNovaConf.\n";
            } elsif ($commonOpts =~ m/ $option /) {
                saveCommonOpt($option, $section, $locNovaConf, $option, $novaConf{'DEFAULT'}{$option});
            } elsif ($option eq 'host') {
                saveCommonOpt($option, $section, $locNovaConf, 'zvm_host', $novaConf{'DEFAULT'}{$option});
            }
        }
    }

    if (keys %neutronConf) {
        my @requiredNeutronConfOpts = (
            'DEFAULT', 'core_plugin',
        );
        for (my $i = 0 ; $i < $#requiredNeutronConfOpts ; $i = $i + 2) {
            my $section = $requiredNeutronConfOpts[$i];
            my $option  = $requiredNeutronConfOpts[ $i + 1 ];
            if (!exists $neutronConf{$section}{$option}) {
                print "Warning: \'$option\' is missing from section \'$section\'\n" .
                  "      in $locNeutronConf/neutron/neutron.conf.\n";
            }
        }
    }

    if (keys %ml2ConfIni) {
        my @requiredMl2ConfIniOpts = (
            'ml2',           'mechanism_drivers',
            'ml2_type_flat', 'flat_networks',
        );
        for (my $i = 0 ; $i < $#requiredMl2ConfIniOpts ; $i = $i + 2) {
            my $section = $requiredMl2ConfIniOpts[$i];
            my $option  = $requiredMl2ConfIniOpts[ $i + 1 ];
            if (!exists $ml2ConfIni{$section}{$option}) {
                print "Warning: \'$option\' is missing from section \'$section\'\n" .
                  "     in $locMl2ConfIni.\n";
            }
        }
    }

    if (keys %neutronZvmPluginIni) {
        my @requiredNeutronZvmPluginIniOpts = (
            'agent', 'zvm_host',
            'agent', 'zvm_xcat_server',
        );
        for (my $i = 0 ; $i < $#requiredNeutronZvmPluginIniOpts ; $i = $i + 2) {
            my $section = $requiredNeutronZvmPluginIniOpts[$i];
            my $option  = $requiredNeutronZvmPluginIniOpts[ $i + 1 ];
            if (!exists $neutronZvmPluginIni{$section}{$option}) {
                print "Warning: \'$option\' is missing from section \'$section\'\n" .
                  "      in $locNeutronZvmPluginIni.\n";
            } else {
                saveCommonOpt($option, $section, $locNeutronZvmPluginIni, $option, $neutronZvmPluginIni{$section}{$option});
            }
        }
    }

    #******************************************
    # Verify optional operands were specified.
    #******************************************
    if (keys %ceilometerConf) {
        if (!exists $ceilometerConf{'DEFAULT'}{'host'} and
            !exists $ceilometerConf{'zvm'}{'zvm_host'}
          ) {
            print "Info: Most z/VM specific Ceilometer options are not defined.  Ceilometer\n" .
"      support is not enabled for z/VM.  Further testing of these options will\n" .
              "      not occur in this script.\n";
        } else {
            my %optionalCeilometerConfOpts = (
'zvm xcat_zhcp_nodename' => 'A default of \'zhcp\' will be used.',
            );
            my %defaultCeilometerConfOpts = (
                "zvm xcat_zhcp_nodename" => 'zhcp',
            );
            foreach my $key (keys %optionalCeilometerConfOpts) {
                my @opts    = split(/\s/, $key);
                my $section = $opts[0];
                my $option  = $opts[1];
                if (!exists $ceilometerConf{$section}{$option}) {
                    print "Info: \'$option\' is missing from section \'$section\'\n" .
                      "      in $locCeilometerConf.\n";
                    if ($optionalCeilometerConfOpts{$key} ne '') {
                        print "      " . $optionalCeilometerConfOpts{$key} . "\n";
                    }
                    if (exists $defaultCeilometerConfOpts{$key}) {
                        $cinderConf{$section}{$option} = $defaultCeilometerConfOpts{$key};
                    }
                }
            }
        }
    }

    if (keys %cinderConf) {
        if ($cmaSystemRole ne "CONTROLLER") {
            print "Info: CMA system role is NOT a controller.\n      Cinder will not be validated.\n";
            $bypassCinder = 1;
        } elsif (!exists $cinderConf{'DEFAULT'}{'san_ip'} and
            !exists $cinderConf{'DEFAULT'}{'san_private_key'} and
            !exists $cinderConf{'DEFAULT'}{'storwize_svc_volpool_name'}
          ) {
            print "Info: Most z/VM specific Cinder options are not defined.\n" .
"      Cinder support for creation of persistent disks for z/VM\n" .
              "      is not enabled.  Further testing of these options will\n" .
              "      not occur in this script.\n";
            $bypassCinder = 1;
        } else {
            my %optionalCinderConfOpts = (
"DEFAULT san_ip" => "This property is necessary when using persistent SAN disks obtained\n" .
                  "      from the Cinder service.",
"DEFAULT san_private_key" => "This property is necessary when using persistent SAN disks obtained\n" .
                  "      from the Cinder service.",
"DEFAULT storwize_svc_connection_protocol" => "This property is necessary when using StorWize persistent disks obtained\n" .
                  "      from the Cinder service.",
"DEFAULT storwize_svc_volpool_name" => "This property is necessary when using StorWize persistent disks obtained\n" .
                  "      from the Cinder service.  The default is 'volpool'.",
'DEFAULT storwize_svc_vol_iogrp' => "This property is necessary when using StorWize persistent disks obtained\n" .
                  "      from the Cinder service.  The default is 0.",
'DEFAULT volume_driver' => "This property is necessary when using persistent disks obtained\n" .
                  "      from the Cinder service.",
            );
            my %defaultCinderConfOpts = (
                'DEFAULT storwize_svc_volpool_name' => 'volpool',
            );
            foreach my $key (keys %optionalCinderConfOpts) {
                my @opts    = split(/\s/, $key);
                my $section = $opts[0];
                my $option  = $opts[1];
                if (!exists $cinderConf{$section}{$option}) {
                    print "Info: \'$option\' is missing from section \'$section\'\n" .
                      "      in $locCinderConf.\n";
                    if ($optionalCinderConfOpts{$key} ne '') {
                        print "      " . $optionalCinderConfOpts{$key} . "\n";
                    }
                    if (exists $defaultCinderConfOpts{$key}) {
                        $cinderConf{$section}{$option} = $defaultCinderConfOpts{$key};
                    }
                }
            }
        }
    }

    if (keys %novaConf) {
        my %optionalNovaConfOpts = (
'DEFAULT config_drive_format' => 'Default of \'iso9660\' will be used.',
"DEFAULT image_cache_manager_interval" => "Default of 2400 (seconds) will be used.",
            "DEFAULT ram_allocation_ratio" => "",
"DEFAULT rpc_response_timeout" => "zVM Live migration may timeout with the default " .
"value (60 seconds).\n      The recommended value for z/VM is 180 to allow " .
              "zVM live migration\n      to succeed.",
"DEFAULT xcat_free_space_threshold" => "Default of 50 (G) will be used.",
"DEFAULT xcat_image_clean_period" => "Default of 30 (days) will be used.",
"DEFAULT zvm_config_drive_inject_password" => "This value will default to 'FALSE'.",
            "DEFAULT zvm_diskpool_type" => "Default of \'ECKD\' will be used.",
"DEFAULT zvm_fcp_list" => "As a result, Cinder volumes cannot be attached to server instances.",
            "DEFAULT zvm_zhcp_fcp_list" => "",
"DEFAULT zvm_image_tmp_path" => "Default of '/var/lib/nova/images' will be used.",
            "DEFAULT zvm_multiple_fcp" => "Default of 'false' will be used.",
"DEFAULT zvm_reachable_timeout" => "Default of 300 (seconds) will be used.",
            "DEFAULT zvm_scsi_pool" => "Default of \'xcatzfcp\' will be used.",
"DEFAULT zvm_user_default_privilege" => "Default of G will be used.",
            "DEFAULT zvm_user_profile"     => "Default is 'OSDFLT'.",
            "DEFAULT zvm_user_root_vdev"   => "Default of 100 will be used.",
            "DEFAULT zvm_vmrelocate_force" => "",
"DEFAULT zvm_xcat_connection_timeout" => "Default of 3600 seconds will be used.",
"DEFAULT zvm_image_compression_level" => "Image compression is controlled by the xCAT ZHCP " .
"server in\n      the /var/opt/zhcp/settings.conf file.  Compressing images during image\n" .
              "      capture is the default.",
        );
        my %defaultNovaConfOpts = (
            'DEFAULT config_drive_format'        => 'iso9660',
            "DEFAULT xcat_free_space_threshold"  => 50,
            "DEFAULT xcat_image_clean_period"    => 30,
            "DEFAULT zvm_user_default_privilege" => "G",
            "DEFAULT zvm_user_profile"           => 'OSDFLT',
            "DEFAULT zvm_user_root_vdev"         => 100,
            "DEFAULT zvm_diskpool_type"          => 'ECKD',
            "DEFAULT zvm_scsi_pool"              => "xcatzfcp",
        );
        foreach my $key (keys %optionalNovaConfOpts) {
            my @opts    = split(/\s/, $key);
            my $section = $opts[0];
            my $option  = $opts[1];
            if (!exists $novaConf{$section}{$option}) {
                print "Info: \'$option\' is missing from section \'$section\'\n" .
                  "      in $locNovaConf.\n";
                if ($optionalNovaConfOpts{$key} ne '') {
                    print "      " . $optionalNovaConfOpts{$key} . "\n";
                }
                if (exists $defaultNovaConfOpts{$key}) {
                    $novaConf{$section}{$option} = $defaultNovaConfOpts{$key};
                }
            }
        }
    }

    if (keys %neutronConf) {
        my %optionalNeutronConfOpts = (
'DEFAULT base_mac' => 'A default value of \'fa:16:3e:00:00:00\' will be used.',
        );
        my %defaultNeutronConfOpts = (
            'DEFAULT base_mac' => 'fa:16:3e:00:00:00',
        );
        foreach my $key (keys %optionalNeutronConfOpts) {
            my @opts    = split(/\s/, $key);
            my $section = $opts[0];
            my $option  = $opts[1];
            if (!exists $neutronConf{$section}{$option}) {
                print "Info: \'$option\' is missing from section \'$section\'\n" .
                  "      in $locNeutronConf.\n";
                if ($optionalNeutronConfOpts{$key} ne '') {
                    print "      " . $optionalNeutronConfOpts{$key} . "\n";
                }
                if (exists $defaultNeutronConfOpts{$key}) {
                    $neutronConf{$section}{$option} = $defaultNeutronConfOpts{$key};
                }
            }
        }
    }

    if (keys %ml2ConfIni) {
        my %optionalMl2ConfIniOpts = (
            'ml2_type_vlan network_vlan_ranges' =>
"This property is optional and is used to specify z/VM vswitches\n" .
"      usable for VLAN provider and tenant networks.  In addition,\n" .
"      it can include a range of VLAN ids to be used with the switch.",
'ml2 tenant_network_types' => 'This property is an ordered list of ' .
'network types to allocate as tenant (project) networks, separated by commas. ' .
              'A default value of \'local\' will be used.',
'ml2 type_drivers' => 'This property lists the network types to be supported. ' .
              'A default value of \'local,flat,vlan\' will be used.',
        );
        my %defaultMl2ConfIniOpts = (
            'ml2 tenant_network_types' => 'local',
            'ml2 type_drivers'         => 'local,flat,vlan',
        );
        foreach my $key (keys %optionalMl2ConfIniOpts) {
            my @opts    = split(/\s/, $key);
            my $section = $opts[0];
            my $option  = $opts[1];
            if (!exists $ml2ConfIni{$section}{$option}) {
                print "Info: \'$option\' is missing from section \'$section\'\n" .
                  "      in $locMl2ConfIni.\n";
                if ($optionalMl2ConfIniOpts{$key} ne '') {
                    print "      " . $optionalMl2ConfIniOpts{$key} . "\n";
                }
                if (exists $defaultMl2ConfIniOpts{$key}) {
                    $ml2ConfIni{$section}{$option} = $defaultMl2ConfIniOpts{$key};
                }
            }
        }
    }

    if (keys %neutronZvmPluginIni) {
        my %optionalNeutronZvmPluginIniOpts = (
"agent xcat_mgt_ip" => "This property is necessary when deploying virtual server " .
              "instances that\n      do NOT have public IP addresses.",
"agent xcat_mgt_mask" => "This property is necessary when deploying virtual server " .
              "instances that\n      do NOT have public IP addresses.",
            "agent polling_interval" => "A default value of '5' will be used.",
"agent xcat_zhcp_nodename" => "A default value of \'zhcp\' will be used.",
"agent zvm_xcat_password" => "A default value of \'admin\' is used.",
"agent zvm_xcat_timeout" => "A default value of 300 seconds is used.",
"agent zvm_xcat_username" => "A default value of \'admin\' is used.",
        );
        my %defaultNeutronZvmPluginIniOpts = (
            "agent polling_interval"   => 2,
            "agent xcat_zhcp_nodename" => "zhcp",
            "agent zvm_xcat_password"  => "admin",
            "agent zvm_xcat_timeout"   => 300,
            "agent zvm_xcat_username"  => "admin",
        );
        foreach my $key (keys %optionalNeutronZvmPluginIniOpts) {
            my @opts    = split('\s', $key);
            my $section = $opts[0];
            my $option  = $opts[1];
            if (!exists $neutronZvmPluginIni{$section}{$option}) {
                print "Info: \'$option\' is missing from section \'$section\'\n" .
                  "      in $locNeutronZvmPluginIni.\n";
                if ($optionalNeutronZvmPluginIniOpts{$key} ne '') {
                    print "      " . $optionalNeutronZvmPluginIniOpts{$key} . "\n";
                }
                if (exists $defaultNeutronZvmPluginIniOpts{$key}) {
                    $neutronZvmPluginIni{$section}{$option} = $defaultNeutronZvmPluginIniOpts{$key};
                    if ($commonOpts =~ m/ $option /) {
                        saveCommonOpt($option, $section, $locNeutronZvmPluginIni, $option, $neutronZvmPluginIni{$section}{$option});
                    }
                }
            }
        }
    }

    # Verify the instance name template is valid
    if (exists $novaConf{'DEFAULT'}{'instance_name_template'}) {

        # Use sprintf which is close enough to the python % support for formatting to construct a sample.
        my $base_name = sprintf($novaConf{'DEFAULT'}{'instance_name_template'}, 1);
        if (length($base_name) > 8) {
            print "Warning: In $locNovaConf, section \`DEFAULT\`, instance_name_template would\n" .
"         construct a value greater than 8 in length: $novaConf{'DEFAULT'}{'instance_name_template'}\n";
        }
        if (($base_name eq $novaConf{'DEFAULT'}{'instance_name_template'}) ||
            ($novaConf{'DEFAULT'}{'instance_name_template'} !~ /%/)) {
            print "Warning: In $locNovaConf, instance_name_template will not\n" .
"         create a usable name with the value: $novaConf{'DEFAULT'}{'instance_name_template'}\n";
        }
        my $words;
        $words++ while $base_name =~ /\S+/g;
        if ($words != 1) {
            print "Warning: In $locNovaConf, instance_name_template will not create\n" .
"         an instance name that is a single blank delimited word using\n" .
"         the value: $novaConf{'DEFAULT'}{'instance_name_template'}\n";
        }
        if ($novaConf{'DEFAULT'}{'instance_name_template'} =~ m/(^RSZ)/i) {
            print "Warning: In $locNovaConf, instance_name_template should not begin\n" .
"         with 'rsz': $novaConf{'DEFAULT'}{'instance_name_template'}\n";
        }
    }

    # Verify the compute_driver is for z/VM
    if (exists $novaConf{'DEFAULT'}{'compute_driver'}) {
        if ($novaConf{'DEFAULT'}{'compute_driver'} ne "nova.virt.zvm.ZVMDriver" and
            $novaConf{'DEFAULT'}{'compute_driver'} ne "zvm.ZVMDriver") {
            print "Warning: In $locNovaConf, compute_driver does not contain the\n" .
"         expected value of \'zvm.ZVMDriver\' and instead contains:\n" .
              "        \'$novaConf{'DEFAULT'}{'compute_driver'}\'\n";
        }
    }

    # Check whether the rpc timeout is too small for z/VM
    if (exists $novaConf{'DEFAULT'}{'rpc_response_timeout'}) {
        if ($novaConf{'DEFAULT'}{'rpc_response_timeout'} < 180) {
            print "Warning: In $locNovaConf, section \'DEFAULT\', rpc_response_timeout\n" .
"      specifies a value, \'$novaConf{'DEFAULT'}{'rpc_response_timeout'}\', which is " .
              "less than the recommended value\n      of \'180\'.\n";
        }
    }

    # Verify all SCSI disk operands are specified, if one exists.
    if (exists $novaConf{'DEFAULT'}{'zvm_fcp_list'} or exists $novaConf{'DEFAULT'}{'zvm_zhcp_fcp_list'}) {
        if (!exists $novaConf{'DEFAULT'}{'zvm_fcp_list'}) {
            print "Warning: In $locNovaConf, \'zvm_fcp_list\' does not exist but\n" .
"         other SCSI disk related operands exist.  Both should be\n" .
"         specified: \'zvm_fcp_list\' and \'zvm_zhcp_fcp_list\'\n";
        }
        if (!exists $novaConf{'DEFAULT'}{'zvm_zhcp_fcp_list'}) {
            print "Warning: In $locNovaConf, \'zvm_zhcp_fcp_list\' does not exist but\n" .
"         other SCSI disk related operands exist.  Both should be\n" .
"         specified: \'zvm_fcp_list\' and \'zvm_zhcp_fcp_list\'\n";
        }
    }

    # Verify neutron.conf operands with a fixed set of possible values
    if (exists $neutronConf{'DEFAULT'}{'core_plugin'}) {
        if ($neutronConf{'DEFAULT'}{'core_plugin'} eq 'neutron.plugins.ml2.plugin.Ml2Plugin') {
            print "Info: In $locNeutronConf, \'core_plugin\' in section \'DEFAULT\'\n" .
"      specifies a value, '$neutronConf{'DEFAULT'}{'core_plugin'}',\n" .
              "      which is deprecated.  The recommended value is 'ml2'.\n";
        }
        elsif ($neutronConf{'DEFAULT'}{'core_plugin'} ne 'ml2') {
            print "Warning: In $locNeutronConf, \'core_plugin\' in section \'DEFAULT\'\n" .
"      specifies a value, '$neutronConf{'DEFAULT'}{'core_plugin'}',\n" .
              "      which is not 'ml2'.\n";
        }
    }

    # Verify any rdev_list in Neutron z/VM Plugin ini file contains a single value and/or not a comma
    foreach my $section (sort keys %neutronZvmPluginIni) {
        next if ($section eq 'agent');
        foreach my $property (keys %{ $neutronZvmPluginIni{$section} }) {
            next if ($property ne "rdev_list");
            my $list = $neutronZvmPluginIni{$section}{$property};
            $list =~ s/^\s+|\s+$//g;    # trim blanks from both ends of the list
            if ($list eq '') {
                print "Warning: In $locNeutronZvmPluginIni, section \'$section\',\n" .
                  "      \'rdev_list\' is specified but has no value.\n";
            } else {
                my @vals = split(/\s/, $list);
                if ($#vals > 0) {

                    # $#vals is array size - 1.
                    print "Warning: In $locNeutronZvmPluginIni, section \'$section\',\n" .
                      "      \'rdev_list\' contains too many values.\n";
                }
                foreach my $op (@vals) {
                    if ($op =~ m/[^0-9a-fA-F]+/) {
                        print "Warning: In $locNeutronZvmPluginIni, section \'$section\',\n" .
"      \'rdev_list\' contains non-hexadecimal characters: \'$op\'.\n";
                    } elsif (length($op) > 4) {
                        print "Warning: In $locNeutronZvmPluginIni, section \'$section\',\n" .
"      \'rdev_list\' contains a value that is not 1-4 characters in\n" .
                          "      length: \'$op\'.\n";
                    }
                }
            }
        }
    }

    # Check whether the storwize_svc_connection_protocol is not 'FC' for z/VM
    if (exists $cinderConf{'DEFAULT'}{'storwize_svc_connection_protocol'}) {
        if ($cinderConf{'DEFAULT'}{'storwize_svc_connection_protocol'} ne 'FC') {
            print "Warning: In $locCinderConf, section \'DEFAULT\',\n" .
              "      storwize_svc_connection_protocol specifies a value, " .
"\'$cinderConf{'DEFAULT'}{'storwize_svc_connection_protocol'}\',\n" .
              "      which is not the required value of \'FC\'.\n";
        }
    }

    # Check whether the volume_driver is correct for z/VM
    if (!$bypassCinder and exists $cinderConf{'DEFAULT'}{'volume_driver'}) {
        if ($cinderConf{'DEFAULT'}{'volume_driver'} ne 'cinder.volume.drivers.ibm.storwize_svc.StorwizeSVCDriver') {
            print "Warning: In $locCinderConf, section \'DEFAULT\', volume_driver specifies\n" .
"      a value, \'$cinderConf{'DEFAULT'}{'volume_driver'}\',\n      which is " .
"not the required value of\n      \'cinder.volume.drivers.ibm.storwize_svc.StorwizeSVCDriver\'.\n";
        }
    }

    return;
}


#*****************************************************************************
# Main routine
#*****************************************************************************
my $configOpt;
my $rc = 0;
my $obfuscateOpt;
my $out;
my $scanInitOpt;

# Parse the arguments
$Getopt::Long::ignorecase = 0;
Getopt::Long::Configure("bundling");
if (!GetOptions(
        'c|config=s'         => \$configOpt,
        'd|driver=s'         => \$driver,
        'h|help'             => \$displayHelp,
        'H|host=s'           => \$host,
        'i|init-files'       => \$scanInitOpt,
        'p|password-visible' => \$pwVisible,
        's|scan=s'           => \$scan,
        'v'                  => \$versionOpt,
        'V|verbose'          => \$verbose)) {
    print $usage_string;
    goto FINISH;
}

if ($versionOpt) {
    print "Version: $version\n";
    print "$supportString\n";
}

if ($displayHelp) {
    showHelp();
}

if ($displayHelp or $versionOpt) {
    goto FINISH;
}

# Determine the local IP address for this system.
my $errorLines = '';
my $hostname   = hostname;
if ($hostname ne '') {
    $localIpAddress = gethostbyname($hostname);
    if (defined $localIpAddress) {
        my $len = length($localIpAddress);
        if ($len == 4) {
            $localIpAddress = inet_ntoa($localIpAddress);
        } else {
            $localIpAddress = '';
            $errorLines = $errorLines . "         The IP address obtained from perl gethostbyname function does not\n" .
"         appear to be an IPv4 address.  An IPv4 address should be used.\n";
        }
    } else {
        $errorLines = $errorLines . "         The IP address related to the following host name was not found:\n" .
          "             $hostname\n";
        if (defined $?) {
            $errorLines = $errorLines . "         The perl gethostbyname function failed with errno: $?\n";
        }
        $localIpAddress = '';
    }
} else {
    $errorLines = $errorLines . "         The host name was not found.\n";
}

if ($localIpAddress eq '') {
    print "Warning: Unable to obtain the host name and/or IP address for this system.\n";
    print "         The local IP address is used in the name of the driver script.\n" .
"         Some variables in the driver script such as zxcatIVP_cNAddress\n" .
"         may be set to an empty string value.  You may wish to correct\n" .
      "         the driver script and your system configuration.\n";
    if ($errorLines ne '') {
        print "    Additional Information:\n$errorLines";
    }
}

# Detect CMA
if (-e $locVersionFileCMO) {

    # CMA version file exists, treat this as a CMA node
    $cmaAppliance     = 1;
    $cmaVersionString = `cat $locVersionFileCMO`;
    chomp($cmaVersionString);
    if ($cmaVersionString eq '') {
        $cmaVersionString = "version unknown";
    }

    # Determine the role of this CMA system
    my %settings;
    if (-e $locApplSystemRole) {
        $rc = hashFile($locApplSystemRole, \%settings, 0);
        if (exists $settings{'role'}) {
            $cmaSystemRole = uc($settings{'role'});
        }
    }
    if ($cmaSystemRole eq '' and -e $locDMSSICMOCopy) {
        $rc = hashFile($locDMSSICMOCopy, \%settings, 0);
        if (exists $settings{'openstack_system_role'}) {
            $cmaSystemRole = uc($settings{'openstack_system_role'});
        }
    }
    if ($cmaSystemRole eq '') {
        $cmaSystemRole = 'unknown';
    }
}

if (defined($scan)) {
    if ($verbose) {
        print "Operand --scan: $scan\n";
    }
    if ('all cinder neutron nova' !~ $scan) {
        print "--scan operand ($scan) is not all, cinder, neutron or nova\n";
        $rc = 400;
        goto FINISH;
    }
} else {
    $scan = 'all';
}

if (defined($host)) {
    if ($verbose) {
        print "Operand --Host: $host\n";
    }
    $driverSuffix = "_$host";
    $initSuffix   = "-$host";
} else {
    $host         = '';
    $driverSuffix = "";
    $initSuffix   = "";
}

if (defined($scanInitOpt)) {
    if ($verbose) {
        print "Operand --initFiles\n";
    }

    my $configFile = '';
    if ($scan =~ 'all' or $scan =~ 'nova') {

        # Look for a System V startup script
        $configFile = scanInitScript("$novaComputeStem$initSuffix", 'config');
        if ($configFile eq '') {

            # Look for systemd unit files
            $configFile = scanServiceUnit("$novaComputeStem$initSuffix.service", 'Service', 'ExecStart');
        }
        if ($configFile ne '') {
            $locNovaConf = $configFile;
        } else {
            print "Info: Unable to determine the Nova configuration file.\n";
            $locNovaConf = '';
        }
    }

    if ($scan =~ 'all' or $scan =~ 'ceilometer') {

        # Look for a System V startup script
        $configFile = scanInitScript("$ceilometerStem$initSuffix", 'config');
        if ($configFile eq '') {

            # Look for systemd unit files
            $configFile = scanServiceUnit("$ceilometerStem$initSuffix.service", 'Service', 'ExecStart');
        }
        if ($configFile ne '') {
            $locCeilometerConf = $configFile;
        } else {
            print "Info: Unable to determine the Ceilometer configuration file.\n";
            $locCeilometerConf = '';
        }
    }

    if ($scan =~ 'all' or $scan =~ 'cinder') {

        # Look for a System V startup script
        $configFile = scanInitScript('openstack-cinder-volume', 'config');
        if ($configFile eq '') {

            # Look for systemd unit files
            $configFile = scanServiceUnit('openstack-cinder-volume.service', 'Service', 'ExecStart');
        }
        if ($configFile ne '') {
            $locCinderConf = $configFile;
        } else {
            print "Info: Unable to determine the Cinder configuration file.\n";
            $locCinderConf = '';
        }
    }

    if ($scan =~ 'all' or $scan =~ 'neutron') {

        # Look for a System V startup script
        $configFile = scanInitScript('neutron-server', 'config');
        if ($configFile eq '') {

            # Look for systemd unit files
            $configFile = scanServiceUnit('neutron-server.service', 'Service', 'ExecStart');
        }
        if ($configFile ne '') {
            $locNeutronConf = $configFile;
        } else {
            print "Info: Unable to determine the Neutron configuration file.\n";
            $locNeutronConf = '';
        }

        $configFile = scanInitScript("$neutronZvmAgentStem$initSuffix", 'config');
        if ($configFile eq '') {

            # Look for systemd unit files
            $configFile = scanServiceUnit("$neutronZvmAgentStem$initSuffix.service", 'Service', 'ExecStart');
        }
        if ($configFile ne '') {
            $locNeutronZvmPluginIni = $configFile;
        } else {
            print "Info: Unable to determine the Neutron z/VM plugin configuration file.\n";
            $locNeutronZvmPluginIni = '';
        }

        $configFile = scanInitScript("$neutronZvmAgentStem$initSuffix", 'plugin_config');
        if ($configFile eq '') {

            # Look for systemd unit files
            $configFile = scanServiceUnit("$neutronZvmAgentStem$initSuffix.service", 'Service', 'ExecStart');
        }
        if ($configFile ne '') {
            $locMl2ConfIni = $configFile;
        } else {
            print "Info: Unable to determine the Neutron ml2 configuration file.\n";
            $locMl2ConfIni = '';
        }
    }
}

if (defined($configOpt)) {
    if ($verbose) {
        print "Operand --config $configOpt\n";
    }

    my @items = split(',', $configOpt);
    foreach my $item (@items) {
        my @parts = split(':', $item);
        if (defined $parts[1]) {
            $parts[0] =~ s/^\s+|\s+$//g; # trim blanks from both ends of the list
        }
        if (defined $parts[1]) {
            $parts[1] =~ s/^\s+|\s+$//g; # trim blanks from both ends of the list
        }

        if (!defined $parts[1] or $parts[1] eq '') {
            print("Warning: --config option: $parts[0] did not specify a file. " .
                  "Default file specification will be used.\n");
            next;
        }

        if ($parts[0] eq $EyeCeilometerConf) {
            $locCeilometerConf = $parts[1];
        } elsif ($parts[0] eq $EyeCinderConf) {
            $locCinderConf = $parts[1];
        } elsif ($parts[0] eq $EyeMl2ConfIni) {
            $locMl2ConfIni = $parts[1];
        } elsif ($parts[0] eq $EyeNeutronConf) {
            $locNeutronConf = $parts[1];
        } elsif ($parts[0] eq $EyeNeutronZvmPluginIni) {
            $locNeutronZvmPluginIni = $parts[1];
        } elsif ($parts[0] eq $EyeNovaConf) {
            $locNovaConf = $parts[1];
        }
    }
}

my ($volume, $directory, $file) = '';
if (defined($driver)) {
    if ($verbose) {
        print "Operand --driver: $driver\n";
    }

    my @dirs;
    if (-d $driver) {

        # Driver operand is a directory name only
        ($volume, $directory, $file) = File::Spec->splitpath($driver, 1);
        $driver = File::Spec->catpath($volume, $directory, "$driverPrefix$localIpAddress$driverSuffix.sh");
    } else {

        # Driver operand is a bad directory or a file in a directory
        ($volume, $directory, $file) = File::Spec->splitpath($driver);
        if (-d $directory) {
            $driver = File::Spec->catpath($volume, $directory, $file);
        } else {
            print "Driver property does not specify a valid directory: $directory\n";
            $rc = 500;
            goto FINISH;
        }
    }
} else {
    $directory = File::Spec->curdir();
    $driver = File::Spec->catpath($volume, $directory, "$driverPrefix$localIpAddress$driverSuffix.sh");
}

# Validate CMA related information
if ($cmaSystemRole ne '') {
    my %cmaRoles = ('CONTROLLER' => 1, 'COMPUTE' => 1, 'COMPUTE_MN' => 1, 'MN' => 1, 'ZHCP' => 1);

    # Validate Controller related information
    if (!exists $cmaRoles{$cmaSystemRole}) {
        my @k = keys %cmaRoles;
        my $keyNames = join(', ', @k);
        print "Warning: The value of the openstack_system_role ($cmaSystemRole) is not\n" .
          "         one of the possible values:\n" .
          "         $keyNames\n";
        $rc = 503;

        # Allow other processing to continue
    }
}

# Scan the configuration files.
if ($scan =~ 'all' or $scan =~ 'nova') {
    scanNova();
}

if ($scan =~ 'all' or $scan =~ 'ceilometer') {
    scanCeilometer();
}

if ($scan =~ 'all' or $scan =~ 'cinder') {
    scanCinder();
}

if ($scan =~ 'all' or $scan =~ 'neutron') {
    scanNeutron();
}

# Validate the settings and produce the driver script.
if (!$configFound) {
    print "Warning: No configuration files were found.  " .
      "No further processing will be performed.\n";
    $rc = 501;

    # Allow other processing to continue
}

!($rc = validateConfigs()) or goto FINISH;

!($rc = buildDriverProgram()) or goto FINISH;

FINISH:
exit $rc;

