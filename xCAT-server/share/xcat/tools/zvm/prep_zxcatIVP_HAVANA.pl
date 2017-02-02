#!/usr/bin/perl
###############################################################################
#      (c) Copyright International Business Machines Corporation 2014.
#                               All Rights Reserved.
###############################################################################
# COMPONENT: prep_zxcatIVP_HAVANA.pl
#
# This is a preparation script for Installation Verification Program for xCAT
# on z/VM.  It prepares the driver script by gathering information from
# OpenStack configuration files on the compute node.
###############################################################################

use strict;
#use warnings;

use Getopt::Long;
use Sys::Hostname;
use Socket;

my %cinderConf;
my %novaConf;
my %neutronConf;
my %ovsNeutronPluginIni;
my %neutronZvmPluginIni;

my $version = "1.1";
my $supportString = "Supports code based on the OpenStack Havana release.";

my $driver;                  # Name of driver file to be created less the ".pl"
my $driverLocation = "/opt/xcat/bin/";  # Location of the IVP program in xCAT MN.
my $driverPrefix = "zxcatIVPDriver_";  # Prefix used in naming the driver program.
my $displayHelp = 0;         # Display help information.
my $ivp = "zxcatIVP.pl";     # z/VM xCAT IVP script name
my $obfuscatePw;             # Obfuscate the PW in the driver file that is built
my $scan;                    # Type of scan to be performed
my $verbose;                 # Verbose flag - 0: quiet, 1: verbose
my $versionOpt = 0;          # Shov version information.

my $localIpAddress;          # Local IP address of system where we are prepping

# set the usage message
my $usage_string = "Usage:\n
    $0\n
    or\n
    $0 -s serviceToScan -d driverProgramName\n
    or\n
    $0 --scan serviceToScan -driver driverProgramName\n
      -s | --scan      Services to scan ('all', 'nova' or 'neutron').\n
      -d | --driver    Name of driver program to construct.\n
           --help      Display help information.\n
      -v               Display script version information.\n
      -V               Display the verbose message\n";

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
sub buildDriverProgram{
    my $rc;
    my @driverText;
    
    if ( $verbose ) {
        print "Building the IVP driver program.\n";
    }

    # Erase any existing driver program.
    if ( -e $driver and ! -z $driver ) {
        # Make certain the file is one of our driver files.
        my $found = `grep 'Function: z/VM xCAT IVP driver program' $driver`; 
        if ( ! $found ) {
            print "$driver is not a z/VM xCAT IVP driver program\n";
            print "File will not be changed.\n";
            return 251;
        } else {
            # Rename the existing driver file.
            print "Existing driver file is being saved as $driver.old\n";
            rename $driver,"$driver.old";
        }
    }

    # Open the driver program for output.
    $rc = open( my $fileHandle, '>', $driver ) or die;
    if ( $rc != 1 ) {
        print "Unable to open $driver for output: $!\n";
        return ( 200 + $rc );
    }

    # Construct the file in an array.
    push( @driverText, "#!/bin/bash" );
    push( @driverText, "# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html" );
    push( @driverText, "" );
    push( @driverText, "# Function: z/VM xCAT IVP driver program" );
    push( @driverText, "#           Built by $0 version $version." );
    push( @driverText, "#           $supportString" );
    push( @driverText, "" );
    push( @driverText, "############## Start of Nova Config Properties" );
    if ( exists $novaConf{'DEFAULT'}{'my_ip'} ) {
        push( @driverText, "" );
        push( @driverText, "# IP address or hostname of the compute node that is accessing this xCAT MN." );
        push( @driverText, "# From \'my_ip\' in /etc/nova/nova.conf." );
        push( @driverText, "export zxcatIVP_cNAddress=\"$novaConf{'DEFAULT'}{'my_ip'}\"" ); 
    } else {
        push( @driverText, "" );
        push( @driverText, "# IP address or hostname of the compute node that is accessing this xCAT MN." );
        push( @driverText, "# From the local IP address of this system." );
        push( @driverText, "export zxcatIVP_cNAddress=\"$localIpAddress\"" );
    }
    if ( exists $novaConf{'DEFAULT'}{'zvm_user_profile'} ) {
        push( @driverText, "" );
        push( @driverText, "# Default profile used in creation of server instances." );
        push( @driverText, "# From \'zvm_user_profile\' in /etc/nova/nova.conf." );
        push( @driverText, "export zxcatIVP_defaultUserProfile=\"$novaConf{'DEFAULT'}{'zvm_user_profile'}\"" );
    }
    if ( exists $novaConf{'DEFAULT'}{'zvm_diskpool'} ) {
        push( @driverText, "" );
        push( @driverText, "# Array of disk pools that are expected to exist." );
        push( @driverText, "# From \'zvm_diskpool\' in /etc/nova/nova.conf." );
        push( @driverText, "export zxcatIVP_diskpools=\"$novaConf{'DEFAULT'}{'zvm_diskpool'}\"" );
    }

    if ( exists $novaConf{'DEFAULT'}{'zvm_fcp_list'} ) {
        push( @driverText, "" );
        push( @driverText, "# The list of FCPs used by instances." );
        push( @driverText, "# From \'zvm_fcp_list\' in /etc/nova/nova.conf." );
        push( @driverText, "export zxcatIVP_instFCPList=\"$novaConf{'DEFAULT'}{'zvm_fcp_list'}\"" );
    }
    if ( exists $novaConf{'DEFAULT'}{'zvm_host'} ) {
        push( @driverText, "" );
        push( @driverText, "# Node of host being managed.  If blank, IVP will search for the host node." );
        push( @driverText, "# From \'zvm_host\' in /etc/nova/nova.conf." );
        push( @driverText, "export zxcatIVP_hostNode=\"$novaConf{'DEFAULT'}{'zvm_host'}\"" );
    }
    if ( exists $novaConf{'DEFAULT'}{'zvm_xcat_master'} ) {
        push( @driverText, "" );
        push( @driverText, "# Node name for xCAT MN (optional)." );
        push( @driverText, "# From \'zvm_xcat_master\' in /etc/nova/nova.conf." );
        push( @driverText, "export zxcatIVP_mnNode=\"$novaConf{'DEFAULT'}{'zvm_xcat_master'}\"" );
    }
    if ( exists $novaConf{'DEFAULT'}{'zvm_xcat_password'} ) {
        push( @driverText, "" );
        if ( $obfuscatePw ) {
            # Obfuscate the password so that it is not easily read.
            # Currently not used due to GUI restrictions that modify the obfuscated password.
            push( @driverText, "# User password defined to communicate with xCAT MN.  Note: Password is hidden." );
            push( @driverText, "export zxcatIVP_pw_obfuscated=1" );
            push( @driverText, "# From \'zvm_xcat_password\' in /etc/nova/nova.conf." );
            my @chars = split( //, $novaConf{'DEFAULT'}{'zvm_xcat_password'} );
            my @newChars;
            foreach my $char ( @chars ) {
                $char = ~$char;
                push( @newChars, $char );
            }
            my $hiddenPw = join( "", @newChars );
            push( @driverText, "export zxcatIVP_xcatUserPw=\"$hiddenPw\"" );
        } else {
            push( @driverText, "# User password defined to communicate with xCAT MN." );
            push( @driverText, "# From \'zvm_xcat_password\' in /etc/nova/nova.conf." );
            push( @driverText, "export zxcatIVP_xcatUserPw=\"$novaConf{'DEFAULT'}{'zvm_xcat_password'}\"" );
        }
    }
    if ( exists $novaConf{'DEFAULT'}{'zvm_xcat_server'} ) {
        push( @driverText, "" );
        push( @driverText, "# Expected IP address of the xcat MN" );
        push( @driverText, "# From \'zvm_xcat_server\' in /etc/nova/nova.conf." );
        push( @driverText, "export zxcatIVP_xcatMNIp=\"$novaConf{'DEFAULT'}{'zvm_xcat_server'}\"" );
    }
    if ( exists $novaConf{'DEFAULT'}{'zvm_xcat_username'} ) {
        push( @driverText, "" );
        push( @driverText, "# User defined to communicate with xCAT MN" );
        push( @driverText, "# From \'zvm_xcat_username\' in /etc/nova/nova.conf." );
        push( @driverText, "export zxcatIVP_xcatUser=\"$novaConf{'DEFAULT'}{'zvm_xcat_username'}\"" );
    }
    if ( exists $novaConf{'DEFAULT'}{'zvm_zhcp_fcp_list'} ) {
        push( @driverText, "" );
        push( @driverText, "# The list of FCPs used by zHCP." );
        push( @driverText, "# From \'zvm_zhcp_fcp_list\' in /etc/nova/nova.conf." );
        push( @driverText, "export zxcatIVP_zhcpFCPList=\"$novaConf{'DEFAULT'}{'zvm_zhcp_fcp_list'}\"" );
    }

    push( @driverText, "" );
    push( @driverText, "# Expected space available in the xCAT MN image repository" );
    push( @driverText, "# From \'xcat_free_space_threshold\' in /etc/nova/nova.conf." );
    push( @driverText, "export zxcatIVP_expectedReposSpace=\"$novaConf{'DEFAULT'}{'xcat_free_space_threshold'}G\"" );                

    push( @driverText, "" );
    push( @driverText, "############## End of Nova Config Properties" );
    push( @driverText, "" );
    push( @driverText, "############## Start of Neutron Config Properties" );
    if ( exists $neutronConf{'DEFAULT'}{'base_mac'} ) {
        my $prefix = $neutronConf{'DEFAULT'}{'base_mac'};
        $prefix =~ tr/://d;
        $prefix = substr( $prefix, 0, 6 );
        push( @driverText, "" );
        push( @driverText, "# User prefix for MAC Addresses of Linux level 2 interfaces" );
        push( @driverText, "# From \'base_mac\' in /etc/neutron/neutron.conf." );
        push( @driverText, "export zxcatIVP_macPrefix=\"$prefix\"" );
    }
    if ( exists $neutronZvmPluginIni{'agent'}{'xcat_mgt_ip'} ) {
        push( @driverText, "" );
        push( @driverText, "# xCat MN's address on the xCAT management network" );
        push( @driverText, "# From \'xcat_mgt_ip\' in /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini." );
        push( @driverText, "export zxcatIVP_xcatMgtIp=\"$neutronZvmPluginIni{'agent'}{'xcat_mgt_ip'}\"" );
    }
    if ( exists $neutronZvmPluginIni{'agent'}{'xcat_mgt_mask'} ) {
        push( @driverText, "" );
        push( @driverText, "# xCat management interface netmask" );
        push( @driverText, "# From \'xcat_mgt_mask\' in /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini." );
        push( @driverText, "export zxcatIVP_mgtNetmask=\"$neutronZvmPluginIni{'agent'}{'xcat_mgt_mask'}\"" );
    }
    if ( exists $ovsNeutronPluginIni{'ovs'}{'network_vlan_ranges'} ) {
        push( @driverText, "" );
        push( @driverText, "# Array of networks and possible VLAN ranges" );
        push( @driverText, "# From \'network_vlan_ranges\' in /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini." );
        push( @driverText, "export zxcatIVP_networks=\"$ovsNeutronPluginIni{'ovs'}{'network_vlan_ranges'}\"" );
    }
    if ( exists $neutronZvmPluginIni{'agent'}{'xcat_zhcp_nodename'} ) {
        push( @driverText, "" );
        push( @driverText, "# Node name for xCAT zHCP server" );
        push( @driverText, "# From \'xcat_zhcp_nodename\' in /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini." );
        push( @driverText, "export zxcatIVP_zhcpNode=\"$neutronZvmPluginIni{'agent'}{'xcat_zhcp_nodename'}\"" );
    }
    # Create the zxcatIVP_vswitchOSAs variable for any networks specified with an rdev list.
    my $vswitchOSAs = '';
    foreach my $section (sort keys %neutronZvmPluginIni) {
        next if ( $section eq 'agent');
        foreach my $property ( keys %{ $neutronZvmPluginIni{$section} } ) {
            next if ( $property ne "rdev_list" );
            my $list = $neutronZvmPluginIni{$section}{$property};
            $list =~ s/^\s+|\s+$//g;         # trim blanks from both ends of the list
            next if ( $list eq '' );
            $list =~ s/\s+/\,/g;              # insert comma between words
            $vswitchOSAs = "$section $list $vswitchOSAs";
        }
    }
    if ( defined $vswitchOSAs ) {
        push( @driverText, "" );
        push( @driverText, "# Vswitches and their related OSAs" );
        push( @driverText, "# From \'rdev_list\' in vswitch sections of /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini." );
        push( @driverText, "export zxcatIVP_vswitchOSAs=\"$vswitchOSAs\"" );
    }

    push( @driverText, "" );
    push( @driverText, "############## End of Neutron Config Properties" );

    push( @driverText, "" );
    push( @driverText, "# Name of user under which nova runs, default is nova." );
    push( @driverText, "# If you system is different then change this property." );
    push( @driverText, "export zxcatIVP_expUser=\"nova\"" );
    push( @driverText, "" );
    push( @driverText, "# Controls whether Warnings/Errors detected by the IVP are" );
    push( @driverText, "# logged in the xCAT MN syslog, 0: do not log, 1: log to syslog." );
    push( @driverText, "export zxcatIVP_syslogErrors=1" );
    push( @driverText, "" );
    push( @driverText, "perl $driverLocation$ivp" ); 

    # Write the array to the driver file.
    foreach (@driverText) {
        #print "$_\n";
        print $fileHandle "$_\n"; # Print each entry in our array to the file
    }

    close $fileHandle;

    print "$driver was built.\n";
}

#-------------------------------------------------------

=head3   hashFile

    Description : Read a file with equal signs designating
                  key value pairs and create a hash from it.
    Arguments   : File to read
                  Reference to hash that should be constructed.
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = hashFile( $file, \%novaConf, 1 );

=cut

#-------------------------------------------------------
sub hashFile{
    my ( $file, $hash, $required ) = @_;
    my $section = "null";
    my $caseInsensitive = 1;    # assume section/properties are case insensitive
    my @parts;

    if ( !-e $file ) {
        if ( $required ) {
            print "Warning: $file does not exist.\n";
        } else {
            print "Info: $file does not exist.\n";
        }
        return 601;
    }

    if ( $file =~ /.conf$/ ) {
        # File is case sensitive, translate sections and property names to uppercase.
        $caseInsensitive = 0;
    }

    # Read the configuration file and construct the hash of values.
    my $out = `egrep -v '(^#|^\\s*\\t*#)' $file`;
    my @lines = split( "\n", $out );
    foreach my $line ( @lines ) {
        if ( $line =~ /^\[/ ) {
            # Section header line
            $line =~ s/^\s+|\s+$//g;         # trim blanks from both ends of the line
            $line =~ s/^\[+|\]+$//g;         # trim [] from ends of the line
            if ( $caseInsensitive ) {
                $section = lc( $line );
            } else {
                $section = $line;
            }
        } else {
            # Property line
            @parts = split( "=", $line );
            next if ( ! exists $parts[0] );
            $parts[0] =~ s/^\s+|\s+$//g;       # trim both ends of the string
            next if ( length( $parts[0] ) == 0 );
            if ( $caseInsensitive ) {
                $parts[0] = lc( $parts[0] );
            }

            if ( exists $parts[1] ) {
                chomp( $parts[1] );
                $parts[1] =~ s/^\s+|\s+$//g;       # trim both ends of the string
            } else {
                $parts[1] = '';
            }

            $$hash{$section}{$parts[0]} = $parts[1];
            #print "$section $parts[0]" . ": " . $parts[1]. "\n";
            #print $parts[0] . ": " . $$hash{$section}{$parts[0]}. "\n";
        }

    }

    return 0;
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
sub scanCinder{
    my $rc;

    if ( $verbose ) {
        print "Scanning the Cinder configuration files.\n";
    }

    # Read the configuration file and construct the hash of values.
    my $file = '/etc/cinder/cinder.conf';
    $rc = hashFile( $file, \%cinderConf, 0 );

    return $rc;
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
sub scanNeutron{
    my $rc;

    if ( $verbose ) {
        print "Scanning the Neutron configuration files.\n";
    }

    # Read the configuration file and construct the hash of values.
    my $file = '/etc/neutron/neutron.conf';
    $rc = hashFile( $file, \%neutronConf, 1 );

    # Read the configuration file and construct the hash of values.
    $file = '/etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini';
    $rc = hashFile( $file, \%ovsNeutronPluginIni, 1 );

    # Read the configuration file and construct the hash of values.
    $file = '/etc/neutron/plugins/zvm/neutron_zvm_plugin.ini';
    $rc = hashFile( $file, \%neutronZvmPluginIni, 1 );

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
sub scanNova{
    my $rc;

    if ( $verbose ) {
        print "Scanning the Nova configuration files.\n";
    }
    # Verify the /etc/nova/nova.conf exists.
    my $file = '/etc/nova/nova.conf';

    $rc = hashFile( $file, \%novaConf, 1 );

    return $rc;
}

#-------------------------------------------------------

=head3   showHelp

    Description : Show the help inforamtion.
    Arguments   : None.
    Returns     : None.
    Example     : showHelp();

=cut

#-------------------------------------------------------
sub showHelp{
    print "$0 prepares and builds a z/VM xCAT IVP driver program
    using the information from the configuration files in the
    compute node.  The default name of the driver program is
    '$driverPrefix' following by the IP address of the
    system where the driver is being prepared and ending with
    '.sh'.

    $supportString

    The following files are scanned for input:
      /etc/cinder/cinder.conf
      /etc/nova/nova.conf
      /etc/neutron/neutron.conf
      /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini
      /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini
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
sub validateConfigs{
    my $rc = 0;
    my $option;
    if ( $verbose ) {
        print "Performing a local validation of the configuration files.\n";
    }

    #*******************************************************
    # Verify required configuration options were specified.
    #*******************************************************
    if ( keys %cinderConf ) {
        my @requiredCinderOpts = ();
        foreach $option ( @requiredCinderOpts ) {
            if ( !exists $cinderConf{'DEFAULT'}{$option} ) {
                #print "option:$option.\nvalue:$cinderConf{$option}\n";
                print "Warning: \'$option\' is missing from section \'DEFAULT\'\n" .
                    "      in /etc/cinder/cinder.conf.\n";
            }
        }
    }

    my @requiredNovaOpts = (
        "compute_driver",
        "config_drive_format",
        "force_config_drive",
        "host",
        'instance_name_template',
        'zvm_diskpool',
        'zvm_host',
        'zvm_user_profile',
        'zvm_xcat_master',
        'zvm_xcat_server',
        'zvm_xcat_username',
        'zvm_xcat_password',
        );
    foreach $option ( @requiredNovaOpts ) {
        if ( !exists $novaConf{'DEFAULT'}{$option} ) {
            #print "option:$option.\nvalue:$novaConf{$option}\n";
            print "Warning: \'$option\' is missing from section \'DEFAULT\'\n" .
                "      in /etc/nova/nova.conf.\n";
        }
    }

    my @requiredNeutronConfOpts = (
        'base_mac',
        'core_plugin', 
        );
    foreach $option ( @requiredNeutronConfOpts ) {
        if ( !exists $neutronConf{'DEFAULT'}{$option} ) {
            print "Warning: \'$option\' is missing from section \'DEFAULT\'\n" .
                "      in /etc/neutron/neutron.conf.\n";
        }
    }

    my @requiredOvsNeutronPluginIniOpts = (
        'network_vlan_ranges',
        'tenant_network_type',
        );
    foreach $option ( @requiredOvsNeutronPluginIniOpts ) {
        if ( !exists $ovsNeutronPluginIni{'ovs'}{$option} ) {
            print "Warning: \'$option\' is missing from section \'ovs\'\n" .
            "     in /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini.\n";
        }
    }

    my @requiredNeutronZvmPluginIniOpts = ( 
        "zvm_xcat_server",
        );
    foreach $option ( @requiredNeutronZvmPluginIniOpts ) {
        if ( !exists $neutronZvmPluginIni{'agent'}{$option} ) {
            print "Warning: \'$option\' is missing from section \'agent\'\n" .
                  "      in /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini.\n";
        }
    }

    #******************************************
    # Verify optional operands were specified.
    #******************************************
    if ( keys %cinderConf ) {
        if ( !exists $cinderConf{'DEFAULT'}{'san_ip'} and 
             !exists $cinderConf{'DEFAULT'}{'san_private_key'} and 
             !exists $cinderConf{'DEFAULT'}{'storwize_svc_connection_protocol'} and 
             !exists $cinderConf{'DEFAULT'}{'storwize_svc_volpool_name'} and 
             !exists $cinderConf{'DEFAULT'}{'storwize_svc_vol_iogrp'} and 
             !exists $cinderConf{'DEFAULT'}{'volume_driver'} ) {
             print "Info: z/VM specific Cinder keys are not defined in section \'DEFAULT\'\n" .
                    "      in /etc/cinder/cinder.conf.  Cinder support for creation of persistent\n" .
                    "      disks for z/VM is not enabled.  Further testing of these options will\n" .
                    "      not occur in this script.\n"
        } else {
            my %optionalCinderConfOpts = (
                "san_ip" => "This property is necessary when using persistent disks obtained\n" .
                    "      from the Cinder service.",
                "san_private_key" => "This property is necessary when using persistent disks obtained\n" .
                    "      from the Cinder service.",
                "storwize_svc_connection_protocol" => "This property is necessary when using persistent disks obtained\n" .
                    "      from the Cinder service.",
                "storwize_svc_volpool_name" => "This property is necessary when using persistent disks obtained\n" .
                    "      from the Cinder service.",
                'storwize_svc_vol_iogrp' => "This property is necessary when using persistent disks obtained\n" .
                    "      from the Cinder service.",
                'volume_driver' => "This property is necessary when using persistent disks obtained\n" .
                    "      from the Cinder service.",
            );
            my %defaultCinderConfOpts = ();
            foreach my $key ( keys %optionalCinderConfOpts ) {
                if ( !exists $cinderConf{'DEFAULT'}{$key} ) {
                    print "Info: \'$key\' is missing from section \'DEFAULT\'\n" .
                        "      in /etc/cinder/cinder.conf.\n";
                    if ( $optionalCinderConfOpts{$key} ne '' ) {
                        print "      " . $optionalCinderConfOpts{$key} . "\n";
                    }
                    if ( exists $defaultCinderConfOpts{$key} ) {
                        $cinderConf{'DEFAULT'}{$key} = $defaultCinderConfOpts{$key};
                    }
                }
            }
        }
    }

    my %optionalNovaConfOpts = (
        "image_cache_manager_interval" => "Default of 2400 (seconds) will be used.",
        "ram_allocation_ratio" => "",
        "rpc_response_timeout" => "zVM Live migration may timeout with the default " .
          "value (60 seconds).\n      The recommended value for z/VM is 180 to allow " .
          "zVM live migration\n      to succeed.",
        "xcat_free_space_threshold" => "Default of 50 (G) will be used.",
        "xcat_image_clean_period" => "Default of 30 (days) will be used.",
        "zvm_config_drive_inject_password" => "This value will default to 'FALSE'.",
        'zvm_diskpool_type' => "This value will default to \'ECKD\'.",
        "zvm_fcp_list" => "Persistent disks cannot be attached to server instances.",
        "zvm_zhcp_fcp_list" => "",
        "zvm_image_tmp_path" => "Defaults to '/var/lib/nova/images'.",
        "zvm_reachable_timeout" => "Default of 300 (seconds) will be used.",
        "zvm_scsi_pool" => "Default of \'xcatzfcp\' will be used.",
        "zvm_vmrelocate_force" => "",
        "zvm_xcat_connection_timeout" => "Default of 3600 seconds will be used.",
        );
    my %defaultNovaConfOpts = (
        "xcat_free_space_threshold" => 50,
        "xcat_image_clean_period" => 30,
        'zvm_diskpool_type' => 'ECKD',
        "zvm_scsi_pool" => "xcatzfcp",
        );
    foreach my $key ( keys %optionalNovaConfOpts ) {
        if ( !exists $novaConf{'DEFAULT'}{$key} ) {
            print "Info: \'$key\' is missing from section \'DEFAULT\'\n" .
                "      in /etc/nova/nova.conf.\n";
            if ( $optionalNovaConfOpts{$key} ne '' ) { 
                print "      " . $optionalNovaConfOpts{$key} . "\n";
            }
            if ( exists $defaultNovaConfOpts{$key} ) {
                $novaConf{'DEFAULT'}{$key} = $defaultNovaConfOpts{$key};
            }
        }
    }

    my %optionalNeutronConfOpts = ();
    my %defaultNeutronConfOpts = ();
    foreach my $key ( keys %optionalNeutronConfOpts ) {
        if ( !exists $neutronConf{'DEFAULT'}{$key} ) {
            print "Info: \'$key\' is missing from section \'DEFAULT\'\n" .
                "      in /etc/neutron/neutron.conf.\n";
            if ( $optionalNeutronConfOpts{$key} ne '' ) {
                print "      " . $optionalNeutronConfOpts{$key} . "\n";
            }
            if ( exists $defaultNeutronConfOpts{$key} ) {
                $neutronConf{'DEFAULT'}{$key} = $defaultNeutronConfOpts{$key};
            }
        }
    }

    my %optionalOvsNeutronPluginIniOpts = ();
    my %defaultOvsNeutronPluginIniOpts = ();
    foreach my $key ( keys %optionalOvsNeutronPluginIniOpts ) {
        if ( !exists $ovsNeutronPluginIni{'agent'}{$key} ) {
            print "Info: \'$key\' is missing from section \'agent\'\n" .
                  "      in /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini.\n";
            if ( $optionalOvsNeutronPluginIniOpts{$key} ne '' ) {
                print "      " . $optionalOvsNeutronPluginIniOpts{$key} . "\n";
            }
            if ( exists $defaultOvsNeutronPluginIniOpts{'agent'}{$key} ) {
                $ovsNeutronPluginIni{'agent'}{$key} = $defaultOvsNeutronPluginIniOpts{$key};
            }
        }
    }

    my %optionalNeutronZvmPluginIniOpts = (
        "xcat_mgt_ip" => "This property is necessary when deploying virtual server " .
          "instances that\n      do NOT have public IP addresses.",
        "xcat_mgt_mask" => "This property is necessary when deploying virtual server " .
          "instances that\n      do NOT have public IP addresses.",
        "polling_interval" => "A default value of \'2\' will be used.",
        "xcat_zhcp_nodename" => "A default value of \'zhcp\' will be used.",
        "zvm_xcat_password" => "A default value of \'admin\' is used.",
        "zvm_xcat_timeout" => "A default value of 300 seconds is used.",
        "zvm_xcat_username" => "A default value of \'admin\' is used.",
        );
    my %defaultNeutronZvmPluginIniOpts = (
        "polling_interval" => 2,
        "xcat_zhcp_nodename" => "zhcp",
        "zvm_xcat_password" => "admin",
        "zvm_xcat_timeout" => 300,
        "zvm_xcat_username" => "admin",
        );
    foreach my $key ( keys %optionalNeutronZvmPluginIniOpts ) {
        if ( !exists $neutronZvmPluginIni{'agent'}{$key} ) {
            print "Info: \'$key\' is missing from section \'agent\'\n" .
                  "      in /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini.\n";
            if ( $optionalNeutronZvmPluginIniOpts{$key} ne '' ) {
                print "      " . $optionalNeutronZvmPluginIniOpts{$key} . "\n";
            } 
            if ( exists $defaultNeutronZvmPluginIniOpts{'agent'}{$key} ) {
                $neutronZvmPluginIni{'agent'}{$key} = $defaultNeutronZvmPluginIniOpts{$key};
            }
        }
    }

    # Verify xCAT users are the same.
    if ( !exists $novaConf{'DEFAULT'}{'zvm_xcat_username'} ) {
        print "Info: Bypassing validation of 'zvm_xcat_username'.\n" .
              "      It is not specified in /etc/nova/nova.conf.\n";
    } elsif ( !exists $neutronZvmPluginIni{'agent'}{'zvm_xcat_username'} ) {
        print "Info: Bypassing validation of 'zvm_xcat_username'.\n" .
              "      It is not specified in /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini.\n";
    } else {
        if ( $novaConf{'DEFAULT'}{'zvm_xcat_username'} ne $neutronZvmPluginIni{'agent'}{'zvm_xcat_username'} ) {
            print "Warning: xCAT user names mismatch; review 'zvm_xcat_username':\n" .
                  "         \'$novaConf{'DEFAULT'}{'zvm_xcat_username'}\' in /etc/nova/nova.conf.\n" .
                  "         \'$neutronZvmPluginIni{'agent'}{'zvm_xcat_username'}\' in\n" .
                  "         /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini.\n";
        }
    }

    # Verify xCAT user passwords are the same.
    if ( !exists $novaConf{'DEFAULT'}{'zvm_xcat_password'} ) {
        print "Info: Bypassing validation of 'zvm_xcat_password'.\n" .
              "      It is not specified in /etc/nova/nova.conf.\n";
    } elsif ( !exists $neutronZvmPluginIni{'agent'}{'zvm_xcat_password'} ) {
        print "Info: Bypassing validation of 'zvm_xcat_password'.  It is not specified\n" .
              "      in /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini.\n";
    } else {
        if ( $novaConf{'DEFAULT'}{'zvm_xcat_password'} ne $neutronZvmPluginIni{'agent'}{'zvm_xcat_password'} ) {
            print "Warning: xCAT user passwords are not the same:\n" .
                  "         Please review 'zvm_xcat_password' in /etc/nova/nova.conf and\n" .
                  "         /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini.\n"; 
        }
    }

    # Verify the xcat server IP addresses are the same.
    if ( !exists $novaConf{'DEFAULT'}{'zvm_xcat_server'} ) {
        print "Info: Bypassing validation of 'zvm_xcat_server'.\n" .
              "      It is not specified in /etc/nova/nova.conf.\n";
    } elsif ( !exists $neutronZvmPluginIni{'agent'}{'zvm_xcat_server'} ) {
        print "Info: Bypassing validation of 'zvm_xcat_server'.\n" .
              "      It is not specified in /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini.\n";
    } else {
        if ( $novaConf{'DEFAULT'}{'zvm_xcat_server'} ne $neutronZvmPluginIni{'agent'}{'zvm_xcat_server'} ) {
            print "Warning: xCAT server addresses mismatch; review 'zvm_xcat_server':\n" .
                  "        \'$novaConf{'DEFAULT'}{'zvm_xcat_server'}\' in /etc/nova/nova.conf.\n" . 
                  "        \'$neutronZvmPluginIni{'agent'}{'zvm_xcat_server'}\' in /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini.\n";
        }
    }

    # Verify the instance name template is valid
    if ( exists $novaConf{'DEFAULT'}{'instance_name_template'} ) {
        # Use sprintf which is close enough to the python % support for formatting to construct a sample.
        my $base_name = sprintf( $novaConf{'DEFAULT'}{'instance_name_template'}, 1 );
        if ( length( $base_name ) > 8 ) {
            print "Warning: In /etc/nova/nova.conf, section \`DEFAULT\`, instance_name_template would\n" .
                  "         construct a value greater than 8 in length: \'$novaConf{'DEFAULT'}{'instance_name_template'}\'.\n";
        }
        if ( $novaConf{'DEFAULT'}{'instance_name_template'} =~ /(^RSZ)/ or $novaConf{'DEFAULT'}{'instance_name_template'} =~ /(^rsz)/ ) {
            print "Warning: In /etc/nova/nova.conf, instance_name_template begins\n" .
                  "         with 'RSZ' or 'rsz': \'$novaConf{'DEFAULT'}{'instance_name_template'}\'\n";
        }
    }

    # Verify the compute_driver is for z/VM
    if ( exists $novaConf{'DEFAULT'}{'compute_driver'} ) {
        if ( $novaConf{'DEFAULT'}{'compute_driver'} ne "nova.virt.zvm.ZVMDriver" and 
             $novaConf{'DEFAULT'}{'compute_driver'} ne "zvm.ZVMDriver") {
            print "Warning: In /etc/nova/nova.conf, compute_driver does not contain the\n" .
                  "         expected value of \'zvm.ZVMDriver\' and instead contains:\n" .
                  "        \'$novaConf{'DEFAULT'}{'compute_driver'}\'\n";
        }
    }

    # Check whether the rpc timeout is too small for z/VM
    if ( exists $novaConf{'DEFAULT'}{'rpc_response_timeout'} ) {
        if ( $novaConf{'DEFAULT'}{'rpc_response_timeout'} < 180 ) {
            print "Warning: In /etc/nova/nova.conf, section \'DEFAULT\', rpc_response_timeout\n" .
                "      specifies a value, \'$novaConf{'DEFAULT'}{'rpc_response_timeout'}\', which is " .
                "less than the recommended value\n      of \'180\'.\n";
        }
    }

    # Verify all SCSI disk operands are specified, if one exists.
    if ( exists $novaConf{'DEFAULT'}{'zvm_fcp_list'} or exists $novaConf{'DEFAULT'}{'zvm_zhcp_fcp_list'} ) {
        if ( !exists $novaConf{'DEFAULT'}{'zvm_fcp_list'} ) {
            print "Warning: In /etc/nova/nova.conf, \'zvm_fcp_list\' does not exist but\n" .
                  "         but other SCSI disk related operands exist.  Both should be \'\n" .
                  "         specified: \'zvm_fcp_list\' and \'zvm_zhcp_fcp_list\'\n";
        }
        if ( !exists $novaConf{'DEFAULT'}{'zvm_zhcp_fcp_list'} ) {
            print "Warning: In /etc/nova/nova.conf, \'zvm_zhcp_fcp_list\' does not exist but\n" .
                  "         but other SCSI disk related operands exist.  Both should be \'\n" .
                  "         specified: \'zvm_fcp_list\' and \'zvm_zhcp_fcp_list\'\n";
        }
    }

    # Verify any rdev_list in Neutron z/VM Plugin ini file contains a single value and/or not a comma
    foreach my $section (sort keys %neutronZvmPluginIni) {
        next if ( $section eq 'agent');
        foreach my $property ( keys %{ $neutronZvmPluginIni{$section} } ) {
            next if ( $property ne "rdev_list" );
            my $list = $neutronZvmPluginIni{$section}{$property};
            $list =~ s/^\s+|\s+$//g;         # trim blanks from both ends of the list
            if ( $list eq '' ) {
                print "Warning: In /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini, section \'$section\',\n" .
                  "      \'rdev_list\' is specified but has no value.\n";
            } else {
                my @vals = split ( /\s/, $list );
                if ( $#vals > 0 ) {
                    # $#vals is array size - 1.
                    print "Warning: In /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini, section \'$section\',\n" .
                          "      \'rdev_list\' contains too many values.\n";
                }
                foreach my $op ( @vals ) {
                    if ( $op =~ m/[^0-9a-fA-F]+/ ) {
                        print "Warning: In /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini, section \'$section\',\n" .
                          "      \'rdev_list\' contains non-hexadecimal characters: \'$op\'.\n";
                    } elsif ( length($op) > 4 ) {
                        print "Warning: In /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini, section \'$section\',\n" .
                          "      \'rdev_list\' contains a value that is not 1-4 characters in\n" .
                          "      length: \'$op\'.\n";
                    }
                }
            }
        }
    }

    # Check whether the storwize_svc_connection_protocol is not 'FC' for z/VM
    if ( exists $cinderConf{'DEFAULT'}{'storwize_svc_connection_protocol'} ) {
        if ( $cinderConf{'DEFAULT'}{'storwize_svc_connection_protocol'} ne 'FC' ) {
            print "Warning: In /etc/cinder/cinder.conf, section \'DEFAULT\',\n" .
                "      storwize_svc_connection_protocol specifies a value, " .
                "\'$cinderConf{'DEFAULT'}{'storwize_svc_connection_protocol'}\',\n" .
                "      which is not the required value of \'FC\'.\n";
        }
    }

    # Check whether the storwize_svc_connection_protocol is not 'FC' for z/VM
    if ( exists $cinderConf{'DEFAULT'}{'volume_driver'} ) {
        if ( $cinderConf{'DEFAULT'}{'volume_driver'} ne 'cinder.volume.drivers.zvm.storwize_svc.StorwizeSVCZVMDriver' ) {
            print "Warning: In /etc/cinder/cinder.conf, section \'DEFAULT\', volume_driver specifies\n" .
                "      a value, \'$cinderConf{'DEFAULT'}{'volume_driver'}\',\n      which is " .
                "not the required value of\n      \'cinder.volume.drivers.zvm.storwize_svc.StorwizeSVCZVMDriver\'.\n";
        }
    }

    return;
}


#*****************************************************************************
# Main routine
#*****************************************************************************
my $rc = 0;
my $clearPwOpt;
my $obfuscateOpt;

# Parse the arguments
$Getopt::Long::ignorecase = 0;
Getopt::Long::Configure( "bundling" );
if (!GetOptions( 's|scan=s'      => \$scan,
                 'd|driver=s'    => \$driver,
                 'h|help'        => \$displayHelp,
                 #'c'             => \$clearPwOpt,
                 #'o'             => \$obfuscateOpt,
                 'v'             => \$versionOpt,
                 'V'             => \$verbose )) {
    print $usage_string;
    goto FINISH;
}

if ( $versionOpt ) {
    print "Version: $version\n";
    print "$supportString\n";
}

if ( $displayHelp ) {
    showHelp();
}

if ( $displayHelp or $versionOpt ) {
    goto FINISH;
}

$localIpAddress = inet_ntoa((gethostbyname(hostname))[4]);

if ( defined( $scan ) ) {
    if ( $verbose ) {
      print "Operand --scan: $scan\n"; 
    }
    if ( 'all nova neutron' !~ $scan ) {
        print "--scan operand($scan) is not all, nova or neutron\n";
        $rc = 400;
        goto FINISH;
    }
} else {
    $scan = 'all';
}

if ( defined( $driver ) ) {
    if ( $verbose ) {
      print "Operand --driver: $driver\n"; 
    }
    $driver = "$driver.sh";
} else {
    $driver = "$driverPrefix$localIpAddress.sh";
}

if ( $scan =~ 'all' or $scan =~ 'nova' ) {
    !( $rc = scanNova() ) or goto FINISH;
}

if ( $scan =~ 'all' or $scan =~ 'cinder' ) {
    scanCinder();
}

if ( $scan =~ 'all' or $scan =~ 'neutron' ) {
    !( $rc = scanNeutron() ) or goto FINISH;
}

#if ( $obfuscateOpt ) {
#    print "obfuscateOpt: $obfuscateOpt\n";
#    $obfuscatePw = 1;
#} elsif ( $clearPwOpt ) {
#    $obfuscatePw = 0;
#}

!( $rc = validateConfigs() ) or goto FINISH;

!( $rc = buildDriverProgram() ) or goto FINISH;

FINISH:
exit $rc;

