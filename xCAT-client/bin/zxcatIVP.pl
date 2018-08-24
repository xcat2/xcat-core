#!/usr/bin/perl
###############################################################################
# IBM (C) Copyright 2014, 2016 Eclipse Public License
# http://www.eclipse.org/org/documents/epl-v10.html
###############################################################################
# COMPONENT: zxcatIVP.pl
#
# This is an Installation Verification Program for z/VM's xCAT Management Node
# and zHCP agent.
###############################################################################
package xCAT::verifynode;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

$XML::Simple::PREFERRED_PARSER='XML::Parser';

use strict;
#use warnings;
use Getopt::Long;
use Getopt::Long qw(GetOptionsFromString);
use MIME::Base64;
use Sys::Syslog qw( :DEFAULT setlogsock);
use Text::Wrap;
use LWP;
use JSON;
use lib "$::XCATROOT/lib/perl";
use xCAT::zvmMsgs;
require HTTP::Request;

# Global variables set based on input from the driver program.
my $glob_bypassMsg = 1;        # Display bypass messages
my $glob_CMA = 0;              # CMA appliance indicator, Assume not running in CMA
my $glob_CMARole = '';         # CMA role, CONTROLLER, COMPUTE or '' (unknown)
my $glob_cNAddress;            # IP address or hostname of the compute node that
                               # is accessing this xCAT MN. (optional)
my $glob_defaultUserProfile;   # Default profile used in creation of server instances.
my $glob_displayHelp = 0;      # Display help instead of running the IVP
my @glob_diskpools;            # Array of disk pools, e.g. ('POOLSCSI', 'POOL1'),
                               # that are expected to exist. (optional)
my $glob_expectedReposSpace;   # Minimum amount of repository space.
my $glob_expUser;              # User name used for importing and exporting images
my @glob_instFCPList;          # Array of FCPs used by server instances
my $glob_hostNode;             # Node of host being managed.  If blank,
                               # IVP will search for the host node. (optional)
my $glob_macPrefix;            # User prefix for MAC Addresses of Linux level 2 interfaces
my %glob_msgsToIgnore;         # Hash of messages to be ignored
my $glob_mgtNetmask;
my $glob_mnNode;               # Node name for xCAT MN (optional).
my $glob_moreCmdOps;           # Additional command operands passed with an environment variable
my @glob_networks;             # Array of networks and possible VLAN ranges
                               # eg. ( 'xcatvsw1', 'xcatvsw2:1:4999'). (optional)
my $obfuscatePw;               # Obfuscate the PW in the driver file that is built
my $glob_signalTimeout;        # Signal Shutdown mininum acceptable timeout
my $glob_syslogErrors;         # Log errors in SYSLOG: 0 - no, 1 - yes
my %glob_vswitchOSAs;          # Hash list of vswitches and their OSAs
my @glob_xcatDiskSpace;        # Array information of directories in xCAT MN that should be validated for disk space
my $glob_xcatMNIp;             # Expected IP address of this xCAT MN
my $glob_xcatMgtIp;            # Expected IP address of this xCAT MN on the Mgt Network
my $glob_xcatUser;             # User defined to communicate with xCAT MN
my $glob_xcatUserPw;           # User's password defined to communicate with xCAT MN
my @glob_zhcpDiskSpace;        # Array information of directories in zhcp that should be validated for disk space
my @glob_zhcpFCPList;          # Array of FCPs used by zHCP
my $glob_zhcpNode;             # Node name for xCAT zHCP server (optional)

# Global IVP run time variables
my $glob_versionInfo;          # Version info for xCAT MN and zHCP
my $glob_successfulTestCnt = 0;    # Number of successful tests
my @glob_failedTests;          # List of failed tests.
#my @glob_hostNodes;            # Array of host node names
my %glob_hostNodes;            # Hash of host node information
my %glob_ignored;              # List of ignored messages
my $glob_ignoreCnt = 0;        # Number of times we ignored a message
my %glob_localIPs;             # Hash of local IP addresses for the xCAT MN's system
my $glob_localZHCP = '';       # Local ZHCP node name and hostname when ZHCP is on xCAT MN's system
my $glob_totalFailed = 0;      # Number of failed tests
my $glob_testNum = 0;          # Number of tests that were run

my $glob_versionFileCMA = '/opt/ibm/cmo/version';
my $glob_versionFileXCAT = '/opt/xcat/version';
my $glob_applSystemRole = '/var/lib/sspmod/appliance_system_role';

# Tables for environment variable and command line operand processing.
my ( $cmdOp_bypassMsg, $cmdOp_cNAddress, $cmdOp_defaultUserProfile, $cmdOp_diskpools,
         $cmdOp_expectedReposSpace, $cmdOp_expUser, $cmdOp_hostNode, $cmdOp_ignore,
         $cmdOp_instFCPList, $cmdOp_instFCPList, $cmdOp_macPrefix, $cmdOp_mgtNetmask,
         $cmdOp_mnNode, $cmdOp_moreCmdOps, $cmdOp_bypassMsg, $cmdOp_networks, $cmdOp_pw_obfuscated,
         $cmdOp_syslogErrors, $cmdOp_signalTimeout, $cmdOp_vswitchOSAs,
         $cmdOp_xcatDiskSpace, $cmdOp_xcatMgtIp, $cmdOp_xcatMNIp,
         $cmdOp_xcatUser, $cmdOp_zhcpFCPList, $cmdOp_zhcpNode, $cmdOp_zhcpDiskSpace );
my @cmdOps = (
        {
            'envVar'    => 'zxcatIVP_bypassMsg',
            'opName'    => 'bypassMsg',
            'inpVar'    => 'cmdOp_bypassMsg',
            'var'       => 'glob_bypassMsg',
            'type'      => 'scalar',
            'desc'      => "Controls whether bypass messages are produced:\n" .
                           "0: do not show bypass messages, or\n" .
                           "1: show bypass messages.\n" .
                           "Bypass messages indicate when a test is not run. " .
                           "This usually occurs when a required environment variable or command line operand is " .
                           "missing.",
        },
        {
            'envVar'    => 'zxcatIVP_cNAddress',
            'opName'    => 'cNAddress',
            'inpVar'    => 'cmdOp_cNAddress',
            'var'       => 'glob_cNAddress',
            'type'      => 'scalar',
            'desc'      => 'Specifies the IP address or hostname of the OpenStack compute node that is ' .
                           'accessing the xCAT MN.',
        },
        {
            'envVar'    => 'zxcatIVP_defaultUserProfile',
            'opName'    => 'defaultUserProfile',
            'inpVar'    => 'cmdOp_defaultUserProfile',
            'var'       => 'glob_defaultUserProfile',
            'type'      => 'scalar',
            'desc'      => 'Specifies the default profile that is used in creation of server instances.',
        },
        {
            'envVar'    => 'zxcatIVP_diskpools',
            'opName'    => 'diskpools',
            'inpVar'    => 'cmdOp_diskpools',
            'var'       => 'glob_diskpools',
            'type'      => 'array',
            'case'      => 'uc',
            'separator' => ';, ',
            'desc'      => 'Specifies an array of disk pools that are expected to exist. ' .
                           'The IVP will verify that space exists in those disk pools. ',
        },
        {
            'envVar'    => 'zxcatIVP_expectedReposSpace',
            'opName'    => 'expectedReposSpace',
            'inpVar'    => 'cmdOp_expectedReposSpace',
            'var'       => 'glob_expectedReposSpace',
            'type'      => 'scalar',
            'default'   => '1G',
            'desc'      => 'Specifies the expected space available in the xCAT MN image repository. ' .
                           'The OpenStack compute node attempts to ensure that the space is available ' .
                           'in the xCAT image repository by removing old images. This can cause ' .
                           'images it be removed and added more often than desired if the value is too high.',
        },
        {
            'envVar'    => 'zxcatIVP_expUser',
            'opName'    => 'expUser',
            'inpVar'    => 'cmdOp_expUser',
            'var'       => 'glob_expUser',
            'type'      => 'scalar',
            'desc'      => 'Specifies the name of the user under which the OpenStack Nova component runs ' .
                           'on the compute node. The IVP uses this name when it attempts to verify access ' .
                           'of the xCAT MN to the compute node.',
        },
        {
            'envVar'    => 'zxcatIVP_hostNode',
            'opName'    => 'hostNode',
            'inpVar'    => 'cmdOp_hostNode',
            'var'       => 'glob_hostNode',
            'type'      => 'scalar',
            'desc'      => 'Specifies the node of host being managed by the compute node. ' .
                           'The IVP will verify that the node name exists and use this to determine the ' .
                           'ZHCP node that supports the host. If this value is missing or empty, the ' .
                           'IVP will validate all host nodes that it detects on the xCAT MN.',
        },
        {
            'envVar'    => 'zxcatIVP_ignore',
            'opName'    => 'ignore',
            'inpVar'    => 'cmdOp_ignore',
            'var'       => 'glob_msgsToIgnore',
            'type'      => 'hash',
            'case'      => 'uc',
            'separator' => ';, ',
            'desc'      => 'Specifies a comma separated list of message Ids that should be ignored. ' .
                           'Ignored messages do not generate a full message and are not counted as ' .
                           'trigger to notify the monitoring userid (see XCAT_notify property in the ' .
                           'DMSSICNF COPY file).  Instead a line will be generated in the output indicating ' .
                           'that the message was ignored.',
        },
        {
            'envVar'    => 'zxcatIVP_instFCPList',
            'opName'    => 'instFCPList',
            'inpVar'    => 'cmdOp_instFCPList',
            'var'       => 'glob_instFCPList',
            'type'      => 'array',
            'separator' => ';, ',
            'desc'      => 'Specifies the list of FCPs used by instances.',
        },
        {
            'envVar'    => 'zxcatIVP_macPrefix',
            'opName'    => 'macPrefix',
            'inpVar'    => 'cmdOp_macPrefix',
            'var'       => 'glob_macPrefix',
            'type'      => 'scalar',
            'desc'      => 'Specifies user prefix for MAC Addresses of Linux level 2 interfaces.',
        },
        {
            'envVar'    => 'zxcatIVP_mgtNetmask',
            'opName'    => 'mgtNetmask',
            'inpVar'    => 'cmdOp_mgtNetmask',
            'var'       => 'glob_mgtNetmask',
            'type'      => 'scalar',
            'desc'      => 'Specifies xCat management interface netmask.',
        },
        {
            'envVar'    => 'zxcatIVP_mnNode',
            'opName'    => 'mnNode',
            'inpVar'    => 'cmdOp_mnNode',
            'var'       => 'glob_mnNode',
            'type'      => 'scalar',
            'desc'      => 'Specifies the node name for xCAT MN.',
        },
        {
            'envVar'    => 'zxcatIVP_moreCmdOps',
            'opName'    => 'moreCmdOps',
            'inpVar'    => 'cmdOp_moreCmdOps',
            'var'       => 'glob_moreCmdOps',
            'type'      => 'scalar',
            'desc'      => 'Specifies additional command operands to be passed to the zxcatIVP script. ' .
                           'This is used interally by the IVP programs.',
        },
        {
            'envVar'    => 'zxcatIVP_networks',
            'opName'    => 'networks',
            'inpVar'    => 'cmdOp_networks',
            'var'       => 'glob_networks',
            'type'      => 'array',
            'separator' => ';, ',
            'desc'      => "Specifies an array of networks and possible VLAN ranges. " .
                           "The array is a list composed of network names and optional " .
                           "vlan ranges in the form: vswitch:vlan_min:vlan_max where " .
                           "each network and vlan range components are separated by a colon.\n" .
                           "For example, 'vsw1,vsw2:1:4095' specifies two vswitches vsw1 without a " .
                           "vlan range and vsw2 with a vlan range of 1 to 4095.",
        },
        {
            'envVar'    => 'zxcatIVP_pw_obfuscated',
            'opName'    => 'pw_obfuscated',
            'inpVar'    => 'cmdOp_pw_obfuscated',
            'var'       => 'obfuscatePw',
            'type'      => 'scalar',
            'desc'      => "Indicates whether the password zxcatIVP_xcatUserPw is obfuscated:\n" .
                           "1 - obfuscated,\n0 - in the clear.",
        },
        {
            'envVar'    => 'zxcatIVP_signalTimeout',
            'opName'    => 'signalTimeout',
            'inpVar'    => 'cmdOp_signalTimeout',
            'var'       => 'glob_signalTimeout',
            'type'      => 'scalar',
            'default'   => '30',
            'desc'      => "Specifies the minimum acceptable time value that should be specified ".
                           "in the z/VM using the SET SIGNAL SHUTDOWNTIME configuration statement. ".
                           "A value less than this value will generate a warning in the IVP.",
        },
        {
            'envVar'    => 'zxcatIVP_syslogErrors',
            'opName'    => 'syslogErrors',
            'inpVar'    => 'cmdOp_syslogErrors',
            'var'       => 'glob_syslogErrors',
            'type'      => 'scalar',
            'default'   => '1',
            'desc'      => "Specifies whether Warnings and Errors detected by the IVP are ".
                           "logged in the xCAT MN syslog:\n0: do not log,\n1: log to syslog.",
        },
        {
            'envVar'    => 'zxcatIVP_vswitchOSAs',
            'opName'    => 'vswitchOSAs',
            'inpVar'    => 'cmdOp_vswitchOSAs',
            'var'       => 'glob_vswitchOSAs',
            'type'      => 'hash',
            'separator' => ';, ',
            'desc'      => 'Specifies vswitches and their related OSAs that are used by ' .
                           'systems created by the OpenStack compute node.',
        },
        {
            'envVar'    => 'zxcatIVP_xcatDiskSpace',
            'opName'    => 'xcatDiskSpace',
            'inpVar'    => 'cmdOp_xcatDiskSpace',
            'var'       => 'glob_xcatDiskSpace',
            'type'      => 'array',
            'separator' => ';,',
            'default'   => '/ 80 . 10M;/install 90 1g .',
            'desc'      => 'Specifies a list of directories in the xCAT server that should be '.
                           'verified for storage availability. Each directory consists of '.
                           'a blank separated list of values:'.
                           "\n".
                           '* directory name,'.
                           "\n".
                           '* maximum in use percentage (a period indicates that the value should not be tested),'.
                           "\n".
                           '* minumum amount of available storage (period indicates that '.
                           'available storage based on size should not be validated),'.
                           "\n".
                           '* minimum file size at which to generate a warning when available space tests '.
                           'detect a size issue (a period indicates that the value should not be tested).'.
                           "\n\n".
                           "For example: '/ 80 5G 3M' will cause the IVP to check the space for the ".
                           'root directory (/) to verify that it has at least 80% space available or '.
                           '5G worth of space available.  If the space tests fail, a warning will be '.
                           'generated for each file (that is not a jar or so file) which is 3M or larger. '.
                           'Additional directories may be specified using a list separator.',
        },
        {
            'envVar'    => 'zxcatIVP_xcatMgtIp',
            'opName'    => 'xcatMgtIp',
            'inpVar'    => 'cmdOp_xcatMgtIp',
            'var'       => 'glob_xcatMgtIp',
            'type'      => 'scalar',
            'desc'      => 'Specifies xCat MN\'s IP address on the xCAT management network.',
        },
        {
            'envVar'    => 'zxcatIVP_xcatMNIp',
            'opName'    => 'xcatMNIp',
            'inpVar'    => 'cmdOp_xcatMNIp',
            'var'       => 'glob_xcatMNIp',
            'type'      => 'scalar',
            'desc'      => 'Specifies the expected IP address of the xcat management node.',
        },
        {
            'envVar'    => 'zxcatIVP_xcatUser',
            'opName'    => 'xcatUser',
            'inpVar'    => 'cmdOp_xcatUser',
            'var'       => 'glob_xcatUser',
            'type'      => 'scalar',
            'desc'      => 'Specifies the user defined to communicate with xCAT management node.',
        },
        {
            'envVar'    => 'zxcatIVP_xcatUserPw',
            'opName'    => 'xcatUserPw',
            'inpVar'    => 'cmdOp_xcatUserPw',
            'var'       => 'glob_xcatUserPw',
            'type'      => 'scalar',
            'desc'      => 'Specifies the user password defined to communicate with xCAT MN over the REST API.',
        },
        {
            'envVar'    => 'zxcatIVP_zhcpFCPList',
            'opName'    => 'zhcpFCPList',
            'inpVar'    => 'cmdOp_zhcpFCPList',
            'var'       => 'glob_zhcpFCPList',
            'type'      => 'array',
            'separator' => ';, ',
            'desc'      => 'Specifies the list of FCPs used by zHCP.',
        },
        {
            'envVar'    => 'zxcatIVP_zhcpNode',
            'opName'    => 'zhcpNode',
            'inpVar'    => 'cmdOp_zhcpNode',
            'var'       => 'glob_zhcpNode',
            'type'      => 'scalar',
            'desc'      => 'Specifies the expected ZHCP node name that the compute node ' .
                           'expects to be used to manage the z/VM host.',
        },
        {
            'envVar'    => 'zxcatIVP_zhcpDiskSpace',
            'opName'    => 'zhcpDiskSpace',
            'inpVar'    => 'cmdOp_zhcpDiskSpace',
            'var'       => 'glob_zhcpDiskSpace',
            'type'      => 'array',
            'separator' => ';,',
            'default'   => '/ 90 . 10M',
            'desc'      => "Specifies a list of directories in the ZHCP server that should be ".
                           'verified for storage availability. Each directory consists of '.
                           'a blank separated list of values:'.
                           "\n".
                           '* directory name,'.
                           "\n".
                           '* maximum in use percentage (a period indicates that the value should not be tested),'.
                           "\n".
                           '* minumum amount of available storage (period indicates that '.
                           'available storage based on size should not be validated),'.
                           "\n".
                           '* minimum file size at which to generate a warning when available space tests '.
                           'detect a size issue (a period indicates that the value should not be tested).'.
                           "\n\n".
                           "For example: '/ 80 5G 3M' will cause the IVP to check the space for the ".
                           'root directory (/) to verify that it has at least 80% space available or '.
                           '5G worth of space available.  If the space tests fail, a warning will be '.
                           'generated for each file (that is not a jar or so file) which is 3M or larger. '.
                           'Additional directories may be specified using a list separator.',
        },
        );

my $usage_string = "Usage:\n
    zxcatIVP
or
    zxcatIVP <operands>
or
    zxcatIVP --help
or
    zxcatIVP -h\n\n";


#-------------------------------------------------------

=head3   applyOverrides

    Description : Apply the overrides from either
                  the environment variables or command
                  line to the target global variables.
    Arguments   : None
    Returns     : None.
    Example     : applyOverrides();

=cut

#-------------------------------------------------------
sub applyOverrides{
    # Handle the normal case variables and values.
    foreach my $opHash ( @cmdOps ) {
        my $opVarRef = eval('\$' . $opHash->{'inpVar'});
        if ( ! defined $$opVarRef) {
            #print "Did not find \$$opHash->{'inpVar'}\n";
            next;
        } else {
            #print "key: $opHash->{'inpVar'}, value: $$opVarRef\n"
        }

        # Modify the case of the value, if necessary.
        if ( ! exists $opHash->{'case'} ) {
            # Ignore case handling
        } elsif ( $opHash->{'case'} eq 'uc' ) {
            $$opVarRef = uc( $$opVarRef );
        } elsif ( $opHash->{'case'} eq 'lc' ) {
            $$opVarRef = lc( $$opVarRef );
        }

        # Process the value to set the variable in this script.
        if ( $opHash->{'type'} eq "scalar" ) {
            my $globRef = eval('\$' . $opHash->{'var'});
            $$globRef = $$opVarRef;
        } elsif ( $opHash->{'type'} eq "array" ) {
            my $globRef = eval('\@' . $opHash->{'var'});
            my @array;
            if ( $opHash->{'separator'} =~ /,/ and $$opVarRef =~ /,/ ) {
                @array = split( ',', $$opVarRef );
            } elsif ( $opHash->{'separator'} =~ /;/ and $$opVarRef =~ /;/ ) {
                @array = split( ';', $$opVarRef );
            } elsif ( $opHash->{'separator'} =~ /\s/ and $$opVarRef =~ /\s/ ) {
                @array = split( '\s', $$opVarRef );
            } else {
                push @array, $$opVarRef;
            }
            @$globRef = @array;
        } elsif ( $opHash->{'type'} eq "hash" ) {
            my $globRef = eval('\%' . $opHash->{'var'});
            my @array;
            my %hash;
            if ( $opHash->{'separator'} =~ /,/ and $$opVarRef =~ /,/ ) {
                @array = split( ',', $$opVarRef );
                %hash = map { $_ => 1 } @array;
            } elsif ( $opHash->{'separator'} =~ /;/ and $$opVarRef =~ /;/ ) {
                @array = split( ';', $$opVarRef );
                %hash = map { $_ => 1 } @array;
            } elsif ( $opHash->{'separator'} =~ /\s/ and $$opVarRef =~ /\s/ ) {
                @array = split( '\s', $$opVarRef );
                %hash = map { $_ => 1 } @array;
            } else {
                $hash{$$opVarRef} = 1;
            }
            %$globRef = %hash;
        } else {
            print "Internal error: Unsupported \%cmdOpRef type '$opHash->{'type'}' for $opHash->{'inpVar'}\n";
        }
    }
}


#-------------------------------------------------------

=head3   calculateRoutingPrefix

    Description : Calculate the routing prefix for a given subnet mask.
    Arguments   : Subnet Mask
    Returns     : -1 - Unable to calculate routing prefix
                  zero or non-zero - Routing prefix number
    Example     : $rc = calculateRoutingPrefix( $subnetMask );

=cut

#-------------------------------------------------------
sub calculateRoutingPrefix{
    my ( $subnetMask ) = @_;
    my $routingPrefix = 0;
    my @parts;

    # Determine the inet version based on the mask separator and
    # calculate the routing prefix.
    if ( $subnetMask =~ m/\./ ) {
        # inet 4 mask
        @parts = split( /\./, $subnetMask );
        foreach my $part ( @parts ) {
            if (( $part =~ /\D/ ) || ( length($part) > 3 )) {
                return -1;        # subnet mask is not valid
            }
            foreach my $i ( 1, 2, 4, 8,
                           16, 32, 64, 128 ) {
                if ( $part & $i ) {
                    $routingPrefix++;
                }
            }
        }
    } elsif ( $subnetMask =~ m/\:/ ) {
        # inet 6 mask
        @parts = split( /:/, $subnetMask );
        foreach my $part ( @parts ) {
            if (( $part =~ /[^0-9^a-f^A-F]/ ) || ( length($part) > 4 )) {
                print "part failed: $part\n";
                return -1;        # subnet mask is not valid
            }
            $part = hex $part;
            foreach my $i ( 1, 2, 4, 8,
                           16, 32, 64, 128,
                           256, 512, 1024, 2048,
                           4096, 8192, 16384, 32768 ) {
                if ( $part & $i ) {
                    $routingPrefix++;
                }
            }
        }
    }

    return $routingPrefix
}


#-------------------------------------------------------

=head3   convertDiskSize

    Description : Reduce a size with a magnitude (eg. 25G or 25M)
                  to a common scalar value.
    Arguments   : Size to convert.
    Returns     : non-negative - No error
                  -1 - Error detected.
    Example     : my $size = convertDiskSize( $diskType, $diskSize );

=cut

#-------------------------------------------------------
sub convertDiskSize{
    my ( $diskType, $diskSize ) = @_;
    my $size;

    my $bytesPer3390Cylinder = 849960;
    my $bytesPer3380Cylinder = 712140;
    my $bytesPer9345Cylinder = 696840;
    my $bytesPerFbaBlock = 512;
    my $cylindersPer3390_03 = 3339;
    my $kilobyte = 1024;
    my $megabyte = 1024 ** 2;
    my $gigabyte = 1024 ** 3;

    $diskType = uc( $diskType );
    if ( $diskType =~ '3390-' ) {
        $size = $diskSize * $bytesPer3390Cylinder / $gigabyte;
        $size = sprintf("%.2f", $size);
        $size = "$diskSize(cyl) -> $size" . "Gig";
    } elsif ( $diskType =~ '3380-') {
        $size = $diskSize * $bytesPer3380Cylinder / $gigabyte;
        $size = sprintf("%.2f", $size);
        $size = "$diskSize(cyl) -> $size" . "Gig";
    } elsif ( $diskType =~ '9345-') {
        $size = $diskSize * $bytesPer9345Cylinder / $gigabyte;
        $size = sprintf("%.2f", $size);
        $size = "$diskSize(cyl) -> $size" . "Gig";
    } elsif ( $diskType =~ '9336-') {
        $size = $diskSize * $bytesPerFbaBlock / $gigabyte;
        $size = sprintf("%.2f", $size);
        $size = "$diskSize(block) -> $size" . "Gig";
    } elsif ( $diskType =~ '9332') {
        $size = $diskSize * $bytesPerFbaBlock / $gigabyte;
        $size = "$diskSize(block)";
    } else {
        $size = "$diskSize";
    }

    return $size;
}


#-------------------------------------------------------

=head3   convertSize

    Description : Reduce a size with a magnitude (eg. 25G or 25M)
                  to a common scalar value.
    Arguments   : Size to convert.
    Returns     : non-negative - No error
                  -1 - Error detected.
    Example     : my $size = convertSize( "25G" );

=cut

#-------------------------------------------------------
sub convertSize{
    my ( $magSize ) = @_;
    my $size;
    my $numeric;
    my $kilobyte = 1024;
    my $megabyte = 1024 ** 2;
    my $gigabyte = 1024 ** 3;
    my $terabyte = 1024 ** 4;
    my $petabyte = 1024 ** 5;
    my $exabyte  = 1024 ** 6;

    $magSize = uc( $magSize );
    $numeric = substr( $magSize, 0, -1 );
    if ( length $magSize == 0 ) {
        logTest( 'misc', "size is less than expected, value: $magSize." );
    } elsif ( $magSize =~ m/K$/ ) {
        $size = $numeric * $kilobyte;
    } elsif ( $magSize =~ m/M$/ ) {
        $size = $numeric * $megabyte;
    } elsif ( $magSize =~ m/G$/ ) {
        $size = $numeric * $gigabyte;
    } elsif ( $magSize =~ m/T$/ ) {
        $size = $numeric * $terabyte;
    } elsif ( $magSize =~ m/P$/ ) {
        $size = $numeric * $petabyte;
    } elsif ( $magSize =~ m/E$/ ) {
        $size = $numeric * $exabyte;
    } else {
        logTest( 'misc', "magnitude of $magSize is unknown." );
        return -1;
    }

    return $size;
}


#-------------------------------------------------------

=head3   driveREST

    Description : Verify the REST interface is running.
    Arguments   : IP address
                  User
                  Password
                  Rest Object ( e.g. nodes/xcat )
                  Method ( GET | PUT | POST | DELETE )
                  Format
    Returns     : Response structure
    Example     : my $response = driveREST( $glob_xcatMNIp, $glob_xcatUser,
                     $glob_xcatUserPw, "nodes/$glob_mnNode", "GET", "json", \@restOps );

=cut

#-------------------------------------------------------
sub driveREST{
    my ( $addr, $user, $pw, $obj, $method, $format, $restOps) = @_;
    my $url = "https://$addr/xcatws/$obj" . "?userName=$user&password=$pw" .
        "&format=$format";

    my @updatearray;
    my $fieldname;
    my $fieldvalue;
    my @args = ();
    if ( scalar( @args ) > 0 ){
        foreach my $tempstr (@args) {
            push @updatearray, $tempstr;
        }
    }

    my $request;

    my $ua = LWP::UserAgent->new();
    my $response;
    if (( $method eq 'PUT' ) or ( $method eq 'POST' )) {
        my $tempstr = encode_json \@updatearray;
        $request = HTTP::Request->new( $method => $url );
        $request->header('content-type' => 'text/plain');
        $request->header( 'content-length' => length( $tempstr ) );
        $request->content( $tempstr );
    } elsif (( $method eq 'GET' ) or ( $method eq 'DELETE' )) {
        $request = HTTP::Request->new( $method=> $url );
    }

    $response = $ua->request( $request );

    #print $response->content . "\n";
    #print "code: " . $response->code . "\n";
    #print "message: " .$response->message . "\n";
    return $response;
}


#-------------------------------------------------------
=head3   findZhcpNode

    Description : Find the object name of the zHCP node.
    Arguments   : Target node whose ZHCP we want to find
    Returns     : zHCP node name, if found
                  undefined, if not found
    Example     : my $zhcpNode = findZhcpNode();

=cut

#-------------------------------------------------------
sub findZhcpNode{
    my ( $targetNode) = @_;
    my $rc = 0;
    my $zhcpNode;

    # Get the HCP hostname from the node
    my %targetInfo = getLsdefNodeInfo( $targetNode );
    my $hcpHostname = $targetInfo{'hcp'};

    # Find the node that owns the zHCP hostname
    my @nodes = getNodeNames();
    foreach my $node (@nodes){
        my %nodeInfo = getLsdefNodeInfo( $node );
        if ( $nodeInfo{'hostnames'} =~ $hcpHostname ) {
            $zhcpNode = $node;
            last;
        }
    }

    return $zhcpNode;
}


#-------------------------------------------------------

=head3   getDiskPoolNames

    Description : Obtain the list of disk pools for a
                  z/VM host.
    Arguments   : Host Node
    Returns     : Array of disk pool names - No error
                  empty array - Error detected.
    Example     : my @pools = getDiskPoolNames($node);

=cut

#-------------------------------------------------------
sub getDiskPoolNames{
    my ( $hostNode) = @_;
    my @pools;

    # Find the related zHCP node
    my $zhcpNode = findZhcpNode( $hostNode );
    if ( !defined $zhcpNode ) {
        return @pools;
    }

    my $out = `/opt/xcat/bin/lsvm $zhcpNode  --diskpoolnames | awk '{print \$NF}'`;
    @pools = split /\n/, $out;
    return @pools;
}


#-------------------------------------------------------

=head3   getHostNodeNames

    Description : Get a list of the host nodes defined to this
                  xCAT MN.
    Arguments   : none
    Returns     : List of host nodes
                  undefined - Error detected.
    Example     : my @hostNodes = getHostNodeNames();

=cut

#-------------------------------------------------------
sub getHostNodeNames{
    my @nodes = getNodeNames();
    my @hostNodes;

    foreach my $node (@nodes){
        my %nodeInfo = getLsdefNodeInfo( $node );
        if ( ! %nodeInfo ) {
            next;
        }
        if (( exists $nodeInfo{'hosttype'} ) and ( $nodeInfo{'hosttype'} =~ 'zvm' )) {
            push( @hostNodes, $node);
        }
    }

    return @hostNodes;
}


#-------------------------------------------------------

=head3   getLocalIPs

    Description : Get the IP addresses from ifconfig.
    Arguments   : Node name or IP address
    Returns     : Hash of local IP addresses
    Example     : %localIPs = getLocalIPs();

=cut

#-------------------------------------------------------
sub getLocalIPs {
    my $ip;
    my $junk;
    my %localIPs;
    my $rc = 0;

    my $out = `/sbin/ip addr | grep -e '^\\s*inet' -e '^\\s*inet6'`;
    my @lines = split( '\n', $out );
    foreach my $line ( @lines ) {
        my @parts = split( ' ', $line );
        ($ip) = split( '/', $parts[1], 2 );
        $localIPs{$ip} = 1;
    }

FINISH_getLocalIPs:
    return %localIPs;
}


#-------------------------------------------------------

=head3   getLsdefNodeInfo

    Description : Obtain node info from LSDEF.
    Arguments   : Name of node to retrieve
    Returns     : Hash of node properties.
    Example     : my %hash = getLsdefNodeInfo($node);

=cut

#-------------------------------------------------------
sub getLsdefNodeInfo{
    my ( $node) = @_;
    my %hash;

    my $out = `/opt/xcat/bin/lsdef $node`;

    my @list1 = split /\n/, $out;
    foreach my $item (@list1) {
        if ( $item !~ "Object name:" ) {
            my ($i,$j) = split(/=/, $item);
            $i =~ s/^\s+|\s+$//g;       # trim both ends of the string
            $hash{$i} = $j;
        }
    }

    return %hash;
}


#-------------------------------------------------------

=head3   getNodeNames

    Description : Get a list of the nodes defined to this
                  xCAT MN.
    Arguments   : none
    Returns     : Array of nodes
                  undefined - Error detected.
    Example     : my @nodes = getNodeNames();

=cut

#-------------------------------------------------------
sub getNodeNames{
    my $out = `/opt/xcat/bin/lsdef | sed "s/  (node)//g"`;
    my @nodes = split( /\n/, $out );
    return @nodes;
}


#-------------------------------------------------------

=head3   getUseridFromLinux

    Description : Obtain the z/VM virtual machine userid from
                  /proc/sysinfo file.
    Arguments   : Variable to receive the output
    Returns     : 0 - No error
                  non-zero - Can't get the virtual machine id.
    Example     : my $rc = getUseridFromLinux( \$userid );

=cut

#-------------------------------------------------------
sub getUseridFromLinux{
    my ( $userid) = @_;
    my $rc = 0;

    $$userid = `cat /proc/sysinfo | grep 'VM00 Name:' | awk '{print \$NF}'`;
    $$userid =~ s/^\s+|\s+$//g;       # trim both ends of the string

    if ( $$userid ne '' ) {
        $rc = 1;
    }

    return $rc;
}


#-------------------------------------------------------

=head3   getVswitchInfo

    Description : Query a vswitch and produce a hash of the data.
    Arguments   : zHCP node
                  Name of switch to be queried
    Returns     : hash of switch data, if found.
        hash contains either:
            $switchInfo{'Base'}{$property} = $value;
            $switchInfo{'Authorized users'}{'User'} = $value;
            $switchInfo{'Connections'}{$property} = $value;
            $switchInfo{'Real device xxxx'}{$property} = $value;
    Example     : $rc = getVswitchInfo( $zhcpNode, $switch );

=cut

#-------------------------------------------------------
sub getVswitchInfo{
    my ( $zhcpNode, $switch ) = @_;
    my %switchInfo;
    my @word;
    my $device;

    my $out = `ssh $zhcpNode smcli Virtual_Network_Vswitch_Query -T xxxx -s $switch`;
    if ( $out !~ /^Failed/ ) {
        # Got some information.  Process it.
        my @lines = split( "\n", $out );
        pop( @lines );
        my $subsection = 'Base';
        foreach my $line ( @lines ) {
            #print "line: $line\n";
            my $indent = $line =~ /\S/ ? $-[0] : length $line;   # Get indentation level
            $line =~ s/^\s+|\s+$//g;                             # trim both ends of the line;
            if ( $line eq '' ) {
                next;
            } elsif ( $indent == 0 ) {
                if ( $line =~ 'VSWITCH:' ) {
                    $line = substr( $line, 8 );
                    $line =~ s/^\s+|\s+$//g;                     # trim both ends of the line;
                    @word = split( /:/, $line );
                    $word[1] =~ s/^\s+|\s+$//g;                  # trim both ends of the line;
                    $switchInfo{'Base'}{$word[0]} = $word[1];
                }
            } elsif ( $indent == 2 ) {
                if ( $line =~ /Devices:/ ) {
                    $subsection = 'Real device';
                } elsif ( $line =~ /Authorized users:/ ) {
                    $subsection = 'Authorized users';
                } elsif ( $line =~ /Connections:/ ) {
                    $subsection = 'Connections';
                } else {
                    $subsection = 'Base';
                    @word = split( /:/, $line );
                    $switchInfo{$subsection}{$word[0]} = $word[1];
                }
            } elsif ( $indent == 4 ) {
                if ( $subsection eq 'Real device' ) {
                    @word = split( ':', $line );
                    if ( $line =~ /Real device:/ ) {
                        $device = $word[1];
                        $device =~ s/^\s+|\s+$//g;       # trim both ends of the string
                    } else {
                        if ( !exists $word[1] ) {
                            $word[1] = '';
                        }
                        my $key = "$subsection $device";
                        $switchInfo{$key}{$word[0]} = $word[1];
                    }
                } elsif ( $subsection eq 'Authorized users' ) {
                    @word = split( ':', $line );
                    if ( $word[1] eq '' ) {
                        next;
                    }
                    if ( exists $switchInfo{$subsection} ) {
                        $switchInfo{$subsection} = "$switchInfo{$subsection} $word[1]";
                    } else {
                        $switchInfo{$subsection} = "$word[1]";
                    }
                } elsif ( $subsection eq 'Connections' ) {
                    @word = split( ' ', $line );
                    if ( !exists $word[2] ) {
                        next;
                    }
                    $switchInfo{$subsection}{$word[2]} = $word[5];
                }
            }
        }
    }
    return %switchInfo;
}


#-------------------------------------------------------

=head3   getVswitchInfoExtended

    Description : Query a vswitch and produce a hash of the data
                  using the extended (keyword) related API.
    Arguments   : zHCP node
                  Name of switch to be queried
    Returns     : hash of switch data, if found.
        hash contains sections and hash/value pairs:
            $switchInfo{'Base'}{$property} = $value;
            $switchInfo{'Real device'}{$device}{$property} = $value;
            $switchInfo{'Authorized users'}{$authUser}{$property} = $value;
            $switchInfo{'Connections'}{$adapter_owner}{$property} = $value;
    Example     : $rc = getVswitchInfoExtended( $zhcpNode, $switch );

=cut

#-------------------------------------------------------
sub getVswitchInfoExtended{
    my ( $zhcpNode, $switch ) = @_;
    my %switchInfo;
    my @word;
    my $device;
    my $authUser;

    my $out = `ssh $zhcpNode smcli Virtual_Network_Vswitch_Query_Extended -T xxxx -k switch_name=$switch`;
    if ( $out !~ /^Failed/ ) {
        # Got some information.  Process it.
        my @lines = split( "\n", $out );
        pop( @lines );
        my $subsection = 'Base';
        my $authPort;
        my $adapter_owner;

        foreach my $line ( @lines ) {
            #print "line: $line\n";
            my $indent = $line =~ /\S/ ? $-[0] : length $line;   # Get indentation level
            $line =~ s/^\s+|\s+$//g;                             # trim both ends of the line;
            if ( $line eq '' ) {
                next;
            }

            $line =~ s/^\s+|\s+$//g;                     # trim both ends of the line;
            @word = split( /:/, $line );
            $word[1] =~ s/^\s+|\s+$//g;                  # trim both ends of the line;
            if ( !exists $word[1] ) {
                $word[1] = '';
            }

            if ( $word[0] eq 'switch_name' ) {
                $switchInfo{'Base'}{$word[0]} = $word[1];
                $subsection = 'Base';
                next;
            } elsif ( $word[0] eq 'real_device_address' ) {
                $subsection = 'Real device';
                $device = $word[1];
                if ( !exists $switchInfo{$subsection}{'RDEVs'} ) {
                    $switchInfo{$subsection}{'RDEVs'} = $device;
                } else {
                    $switchInfo{$subsection}{'RDEVs'} = $switchInfo{$subsection}{'RDEVs'} . ' ' . $device;
                }
                next;
            } elsif ( $word[0] eq 'port_num' ) {
                $subsection = 'Authorized users';
                $authPort = $word[1];
                next;
            } elsif ( $word[0] eq 'adapter_owner' ) {
                $subsection = 'Connections';
                $adapter_owner = $word[1];
                if ( !exists $switchInfo{$subsection}{'ConnectedUsers'} ) {
                    $switchInfo{$subsection}{'ConnectedUsers'} = $adapter_owner;
                } else {
                    $switchInfo{$subsection}{'ConnectedUsers'} = $switchInfo{$subsection}{'ConnectedUsers'} . ' ' . $adapter_owner;
                }
                next;
            }

            # Fill in hash based upon the subsection we are handling.
            my $key;
            if ( $subsection eq 'Base' ) {
                $switchInfo{$subsection}{$word[0]} = $word[1];
            } elsif ( $subsection eq 'Real device' ) {
                $switchInfo{$subsection}{$device}{$word[0]} = $word[1];
            } elsif ( $subsection eq 'Authorized users' ) {
                if ( $word[0] eq 'grant_userid' ) {
                    $authUser = $word[1];
                    $switchInfo{$subsection}{$authUser}{'port_num'} = $authPort;
                    if ( !exists $switchInfo{$subsection}{'AuthorizedUsers'} ) {
                        $switchInfo{$subsection}{'AuthorizedUsers'} = $authUser;
                    } else {
                        $switchInfo{$subsection}{'AuthorizedUsers'} = $switchInfo{$subsection}{'AuthorizedUsers'} . ' ' . $authUser;
                    }
                } else {
                    $switchInfo{$subsection}{$authUser}{$word[0]} = $word[1];
                }
            } elsif ( $subsection eq 'Connections' ) {
                $switchInfo{$subsection}{$adapter_owner}{$word[0]} = $word[1];
            }
        }
    }
    return %switchInfo;
}


#-------------------------------------------------------

=head3   hexDecode

    Description : Convert a string of printable hex
                  characters (4 hex characters per actual
                  character) into the actual string that
                  it represents.
    Arguments   : printable hex value
    Returns     : Perl string
    Example     : $rc = hexDecode();

=cut

#-------------------------------------------------------
sub hexDecode {
    my ( $hexVal ) = @_;
    my $result = '';

    if ( $hexVal =~ /^HexEncoded:/ ) {
        ($hexVal) = $hexVal =~ m/HexEncoded:(.*)/;
        my @hexes = unpack( "(a4)*", $hexVal);
        for ( my $i = 0; $i < scalar(@hexes); $i++ ) {
            $result .= chr( hex( $hexes[$i] ) );
        }
    } else {
        $result = $hexVal;
    }

    return $result;
}


#-------------------------------------------------------

=head3   logTest

    Description : Log the start and result of a test.
                  Failures are added to syslog and printed as script output.
    Arguments   : Status of the test:
                      bypassed: Bypassed a test (STDOUT, optionally SYSLOGged)
                      failed: Failed test (STDOUT, optionally SYSLOGged)
                      passed: Successful test (STDOUT only)
                      started: Start test (STDOUT only, increments test number)
                      misc: Miscellaneous output (STDOUT only)
                      miscNF: Miscellaneous non-formatted output (STDOUT only)
                      info: Information output similar to miscellaneous output
                        but has a message number (STDOUT only)
                  Message ID (used for "bypassed", "failed", or "warning" messages) or
                      message TEXT (used for "misc", "passed", or "started" messages).
                      Message id should begin with the initials of the subroutine
                      generating the message and begin at 1.  For example, the
                      first error message from verifyNode subroutine would be 'VN01'.
                  Message substitution values (used for "bypassed", "failed", or
                      "warning" messages)
    Returns     : None
    Example     : logTest( 'failed', "VMNI01", $name, $tgtIp );
                  logTest( 'started', "xCAT MN has a virtual storage size of at least $vstorMin." );

=cut

#-------------------------------------------------------
sub logTest{
    my ( $testStatus, $msgInfo, @msgSubs ) = @_;
    my $extraInfo;
    my $rc;
    my $sev;
    my $msg;

    if ( $testStatus eq 'misc' ) {
        # Miscellaneous output
        $msgSubs[0] = "$msgInfo\n";
        ( $rc, $sev, $msg, $extraInfo ) = xCAT::zvmMsgs->buildMsg('ZXCATIVP', 'GENERIC_RESPONSE', \@msgSubs );
        print( "$msg\n" );
    } elsif ( $testStatus eq 'miscNF' ) {
        # Miscellaneous output
        print("$msgInfo\n");
    } elsif ( $testStatus eq 'passed' ) {
        # Test was successful.  Log it as ok.
        if ( $msgInfo ne '' ) {
            $msgSubs[0] = "$msgInfo\n";
            ( $rc, $sev, $msg, $extraInfo ) = xCAT::zvmMsgs->buildMsg('ZXCATIVP', 'GENERIC_RESPONSE', \@msgSubs );
            print( "$msg\n" );
        }
    } elsif ( $testStatus eq 'started' ) {
        # Start test
        $glob_testNum++;
        print( "\n" );
        $msgSubs[0] = "Test $glob_testNum: Verifying $msgInfo";
        ( $rc, $sev, $msg, $extraInfo ) = xCAT::zvmMsgs->buildMsg('ZXCATIVP', 'GENERIC_RESPONSE', \@msgSubs );
        print( "$msg\n" );
    } else {
        ( $rc, $sev, $msg, $extraInfo ) = xCAT::zvmMsgs->buildMsg('ZXCATIVP', $msgInfo, \@msgSubs );

        # Determine whether we need to ignore the message or produce it and count it.
        if ( defined $glob_msgsToIgnore{$msgInfo} ) {
            # Ignore this message id
            $glob_ignored{$msgInfo} = 1;
            $glob_ignoreCnt += 1;
            print( "Message $msgInfo is being ignored but would have occurred here.\n" );
        } elsif ( defined $glob_msgsToIgnore{$sev} ) {
            # Ignoring all messages of this severity.
            $glob_ignored{$msgInfo} = 1;
            $glob_ignoreCnt += 1;
            print( "Message $msgInfo is being ignored but would have occurred here.\n" );
        } else {
            # Handle the failed, warning and bypassed messages
            if ( $testStatus eq 'failed' ) {
                # Test failed.  Log it as failure and produce necessary messages
                $glob_totalFailed += 1;
                if ( $glob_totalFailed == 1 || $glob_failedTests[-1] != $glob_testNum ) {
                    push( @glob_failedTests, $glob_testNum );
                }
                print( "$msg" );
                if ( $extraInfo ne '' ) {
                    print( "$extraInfo" );
                }
            } elsif ( $testStatus eq 'warning' ) {
                # Warning unrelated to a test.
                print("$msg");
                if ( $extraInfo ne '' ) {
                    print( "$extraInfo" );
                }
            } elsif ( $testStatus eq 'info' ) {
                # Information message
                print("$msg");
                if ( $extraInfo ne '' ) {
                    print( "$extraInfo" );
                }
            } elsif ( $testStatus eq 'bypassed' ) {
                # Bypass message
                if ( $glob_bypassMsg != 0 ) {
                    print("$msg");
                    if ( $extraInfo ne '' ) {
                        print( "$extraInfo" );
                    }
                }
            }

            # Write the message to syslog
            if ( $testStatus ne 'info' ) {
                my $logMsg = $msg;
                $logMsg =~ s/\t//g;
                $logMsg =~ s/\n/ /g;
                syslog( 'err', $logMsg );
            }
        }
    }
}


#-------------------------------------------------------

=head3   setOverrides

    Description : Set global variables based on input from
                  an external driver perl script, the
                  command line or the zxcatIVP_moreCmdOps
                  environment variable.  This allows
                  the script to be run standalone or overriden
                  by a driver perl script.
    Arguments   : None
    Returns     : None.
    Example     : setOverrides();

=cut

#-------------------------------------------------------
sub setOverrides{
    my $rc;
    my $unrecognizedOps = '';
    my $val;

    # Read the environment variables.
    foreach my $opHash ( @cmdOps ) {
        my $inpRef = eval('\$' . $opHash->{'inpVar'});

        # Update the local input variable with the value from the environment
        # variable or set the default.
        if ( defined $ENV{ $opHash->{'envVar'} } ) {
            $$inpRef = $ENV{ $opHash->{'envVar'} };
        } else {
            if ( exists $opHash->{'default'} ) {
                $$inpRef = $opHash->{'default'};
            } else {
                next;
            }
        }
    }

    # Apply the environent variables as overrides to the global variables in this script.
    applyOverrides();

    # Clear the input variables so that we can use them for command line operands.
    foreach my $opHash ( @cmdOps ) {
        my $inpRef = eval('\$' . $opHash->{'inpVar'});
        $$inpRef = undef;
    }

    # Handle options from the command line.
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );
    if ( !GetOptions(
        'bypassMsg=s'               => \$cmdOp_bypassMsg,
        'cNAddress=s'               => \$cmdOp_cNAddress,
        'defaultUserProfile=s'      => \$cmdOp_defaultUserProfile,
        'diskpools=s'               => \$cmdOp_diskpools,
        'expectedReposSpace=s'      => \$cmdOp_expectedReposSpace,
        'expUser=s'                 => \$cmdOp_expUser,
        'h|help'                    => \$glob_displayHelp,
        'hostNode=s'                => \$cmdOp_hostNode,
        'ignore=s'                  => \$cmdOp_ignore,
        'instFCPList=s'             => \$cmdOp_instFCPList,
        'macPrefix=s'               => \$cmdOp_macPrefix,
        'mgtNetmask=s'              => \$cmdOp_mgtNetmask,
        'mnNode=s'                  => \$cmdOp_mnNode,
        'moreCmdOps=s'              => \$glob_moreCmdOps,
        'networks=s'                => \$cmdOp_networks,
        'pw_obfuscated'             => \$cmdOp_pw_obfuscated,
        'signalTimeout=s'           => \$cmdOp_signalTimeout,
        'syslogErrors'              => \$cmdOp_syslogErrors,
        'vswitchOSAs=s'             => \$cmdOp_vswitchOSAs,
        'xcatDiskSpace=s'           => \$cmdOp_xcatDiskSpace,
        'xcatMgtIp=s'               => \$cmdOp_xcatMgtIp,
        'xcatMNIp=s'                => \$cmdOp_xcatMNIp,
        'xcatUser=s'                => \$cmdOp_xcatUser,
        'zhcpDiskSpace=s'           => \$cmdOp_zhcpDiskSpace,
        'zhcpFCPList=s'             => \$cmdOp_zhcpFCPList,
        'zhcpNode=s'                => \$cmdOp_zhcpNode,
        )) {
        print $usage_string;
    }

    # Handle options passed using the environment variable.
    # This will override the same value that was passed in the command line.
    # Don't specify the same option on both the command line and in the environment variable.
    if ( defined $glob_moreCmdOps ) {
        $glob_moreCmdOps =~ hexDecode( $glob_moreCmdOps );
        ($rc, $unrecognizedOps) = GetOptionsFromString(
            $glob_moreCmdOps,
            'bypassMsg=s'               => \$cmdOp_bypassMsg,
            'cNAddress=s'               => \$cmdOp_cNAddress,
            'defaultUserProfile=s'      => \$cmdOp_defaultUserProfile,
            'diskpools=s'               => \$cmdOp_diskpools,
            'expectedReposSpace=s'      => \$cmdOp_expectedReposSpace,
            'expUser=s'                 => \$cmdOp_expUser,
            'h|help'                    => \$glob_displayHelp,
            'hostNode=s'                => \$cmdOp_hostNode,
            'ignore=s'                  => \$cmdOp_ignore,
            'instFCPList=s'             => \$cmdOp_instFCPList,
            'macPrefix=s'               => \$cmdOp_macPrefix,
            'mgtNetmask=s'              => \$cmdOp_mgtNetmask,
            'mnNode=s'                  => \$cmdOp_mnNode,
            'networks=s'                => \$cmdOp_networks,
            'pw_obfuscated'             => \$cmdOp_pw_obfuscated,
            'signalTimeout=s'           => \$cmdOp_signalTimeout,
            'syslogErrors'              => \$cmdOp_syslogErrors,
            'vswitchOSAs=s'             => \$cmdOp_vswitchOSAs,
            'xcatDiskSpace=s'           => \$cmdOp_xcatDiskSpace,
            'xcatMgtIp=s'               => \$cmdOp_xcatMgtIp,
            'xcatMNIp=s'                => \$cmdOp_xcatMNIp,
            'xcatUser=s'                => \$cmdOp_xcatUser,
            'zhcpDiskSpace=s'           => \$cmdOp_zhcpDiskSpace,
            'zhcpFCPList=s'             => \$cmdOp_zhcpFCPList,
            'zhcpNode=s'                => \$cmdOp_zhcpNode,
            );
        if ( $rc == 0 ) {
            print $usage_string;
        }
    }

    # Apply the command line operands as overrides to the global variables in this script.
    applyOverrides();

    # Special handling for the deobfuscation of the user pw.
    if ( defined $glob_xcatUserPw and $glob_xcatUserPw ne '' and $obfuscatePw ) {
        # Unobfuscate the password so that we can use it.
        $glob_xcatUserPw = decode_base64($val);
    }

    # Special processing for ignore messages to convert general severity type
    # operands to their numeric value.
    if ( $glob_msgsToIgnore{'BYPASS'} ) {
        delete $glob_msgsToIgnore{'BYPASS'};
        $glob_msgsToIgnore{'2'} = 1;
    }
    if ( $glob_msgsToIgnore{'INFO'} ) {
        delete $glob_msgsToIgnore{'INFO'};
        $glob_msgsToIgnore{'3'} = 1;
    }
    if ( $glob_msgsToIgnore{'WARNING'} ) {
        delete $glob_msgsToIgnore{'WARNING'};
        $glob_msgsToIgnore{'4'} = 1;
    }
    if ( $glob_msgsToIgnore{'ERROR'} ) {
        delete $glob_msgsToIgnore{'ERROR'};
        $glob_msgsToIgnore{'5'} = 1;
    }

FINISH_setOverrides:
    return;
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
    my ($rc, $sev, $extraInfo, @array);
    my $msg;

    print "$0 run tests to verify the xCAT installation.\n\n";
    print $usage_string;
    print "The following environment variables (indicated by env:) ".
          "and command line\noperands (indicated by cmd:) are supported.\n\n";
    foreach my $opHash ( @cmdOps ) {
        if ( exists $opHash->{'desc'} ) {
            if ( exists $opHash->{'envVar'} ) {
                print "env: $opHash->{'envVar'}\n";
            }
            if ( exists $opHash->{'opName'} ) {
                print "cmd: --$opHash->{'opName'} <value>\n";
            }
            if ( exists $opHash->{'separator'} ) {
                print "List separator: '$opHash->{'separator'}'\n"
            }
            if ( exists $opHash->{'default'} ) {
                print "Default: $opHash->{'default'}\n";
            }
            print wrap( '', '', "Value: $opHash->{'desc'}" ). "\n";
            print "\n";
        }
    }
    print (
           "Usage notes:\n" .
           "1.  An input value can be specified in one of three ways, either as:   \n" .
           "      * an environment variable,   \n" .
           "      * an operand on the command line using the --<operandName>       \n" .
           "        operand, or                                                    \n" .
           "      * a --moreCmdOps operand.                                        \n" .
           "    The input value in the --<operandName> operand overrides the value \n" .
           "    specifed by the environment variable.  The --moreCmdOps operand    \n" .
           "    overrides both the --<operandName> operand and the environment     \n" .
           "    variable.                                                          \n" .
           "2.  The value for an operand that has a list value may have the        \n" .
           "    members of the list separated by one of the indicated              \n" .
           "    'List separator' operands.  The same separator should be used to   \n" .
           "    separator all members of the list.  For example, do NOT separate   \n" .
           "    the first and second element by a comma and separate the second .  \n" .
           "    and third element by a semi-colon.                                 \n" .
           "3.  If blank is an allowed list separator for the operand and is used  \n" .
           "    then the list should be enclosed in quotes or double quotes so that\n" .
           "    the list is interpretted as a value associated with the operand.   \n" .
           "    You may need to escape the quotes depending on how you are invoking\n" .
           "    the command.  For this reason, it is often better to choose a      \n" .
           "    separator other than blank.                                        \n"
    );

    return;
}


#-------------------------------------------------------

=head3   showPoolInfo

    Description : Show available space for each disk in the pool
    Arguments   : Disk pool name
                  Array of disk information for the pool
    Returns     : None.
    Example     : showPoolInfo($node, $args);

=cut

#-------------------------------------------------------
sub showPoolInfo{
    my ( $diskPool, $diskLines ) = @_;
    my $lines;

    $lines = "$diskPool contains the following disks that have space available:";
    foreach my $disk ( @$diskLines ) {
        my @diskInfo = split( / /, $disk );
        my $size = convertDiskSize( $diskInfo[2], $diskInfo[4] );
        $lines = $lines . "\nvolid: $diskInfo[1], type: $diskInfo[2], available: $size";
    }
    logTest( 'misc', $lines );
}


#-------------------------------------------------------

=head3   verifyCMAProperties

    Description : Verify key CMA properties are specified
                  and set the global ROLE property for
                  user by other functions.
    Arguments   : None
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = verifyCMAProperties();

=cut

#-------------------------------------------------------
sub verifyCMAProperties{
    logTest( "started", "some key CMA properties");

    my $out = `cat $glob_versionFileCMA`;
    chomp( $out );
    if ( $out ne '' ) {
        $glob_versionInfo = "$out";
        # Determine CMA role: Controller or Compute
        my $delim = "=";
        open( FILE, $glob_applSystemRole );
        while ( <FILE> ) {
            my $line = $_;
            if ( $line =~ "^role$delim" or $line =~ "^role $delim" ) {
                my @array = split( /$delim/, $line, 2 );
                $array[1] =~ s/^\s+|\s+$//g;       # trim both ends of the string
                $glob_CMARole  = uc( $array[1] );
            }
        }
        close(FILE);
        if ( ' CONTROLLER COMPUTE COMPUTE_MN MN ' !~ / $glob_CMARole / ) {
            logTest( "failed", "VCMAP01", $glob_applSystemRole );
            $glob_CMARole = '';
        }
    } else {
        $glob_versionInfo = "CMO Appliance version unknown";
        logTest( "failed", "VCMAP02", $glob_versionFileCMA );
    }
}


#-------------------------------------------------------

=head3   verifyComputeNodeConnectivity

    Description : Verify the xCAT MN can SSH to the
                  Compute Node.
    Arguments   : Node address (IP or hostname) of the
                  Compute Node.
                  User underwhich remote exports will be performed.
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : my $rc = verifyComputeNodeConnectivity( $nodeAddress );

=cut

#-------------------------------------------------------
sub verifyComputeNodeConnectivity{
     my ( $nodeAddress, $user ) = @_;

     logTest( 'started', "xCAT MN can ssh to $nodeAddress with user $user." );
     my $out = `ssh -o "NumberOfPasswordPrompts 0" $user\@$nodeAddress pwd`;
     my $rc = $? >> 8;
     if ( $rc != 0 ) {
         logTest( 'failed', "VCNC01", $nodeAddress, $user );
         return 0;                # Non-critical error detected
     }

     return 0;
}


#-------------------------------------------------------

=head3   verifyDirectorySpace

    Description : Verify disk directory space is sufficient.
    Arguments   : Array of directories containing:
                    directory name,
                    maximum percentage in use,
                    maximum file size (or empty if we should not check)
                  Printable node name or ZHCP host name (if remote = 1)
                  Remote processing flag (1 - use SSH to contact the node)
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : $rc = verifyDirectorySpace( \@dirInfo, $zhcpIP );

=cut

#-------------------------------------------------------
sub verifyDirectorySpace{
    my ( $dirInfoRef, $system, $remote ) = @_;
    my @dirInfo = @$dirInfoRef;
    my $minAvailableSpace = '100M';
    my $largeFileSize = '30000k';
    my $out;
    my $rc;
    my @sizes;

    # If system is the ZHCP running on this xCAT MN's system then bypass the test
    # because we would have already tested the directories when we ran the tests
    # for the xCAT MN.
    if ( $system eq $glob_localZHCP ) {
        logTest( 'bypassed', "BPVDS01" );
        goto FINISH_verifyDirectorySpace;
    }

    foreach my $line ( @dirInfo ) {
        chomp( $line );
        $line =~ s/^\s+|\s+$//g;       # trim both ends of the string

        my @info = split( ' ', $line );
        if ( ! defined $info[0] or $info[0] eq '' or ! defined $info[1] or $info[1] eq '' ) {
            # Empty array item and/or maximum percentage is missing.
            next;
        }
        if ( defined $info[2] and $info[2] ne '' and $info[2] ne '.' ) {
            $minAvailableSpace = $info[2];
        }
        if ( defined $info[3] and $info[3] ne '' and $info[3] ne '.' ) {
            $largeFileSize = $info[3];
        }

        # Special case for old ZHCP servers with a memory backed / directory.
        if ( $remote and $info[0] eq '/' ) {
            $out = `ssh $system ls /persistent 1>/dev/null 2>/dev/null`;
            $rc = $? >> 8;
            if ( $rc == 255 ) {
                logTest( 'failed', "STN01", $system );
                next;
            } elsif ( $rc == 0 ) {
                # Validate /persistent directory instead of /
                $info[0] = '/persistent';
            }
        }

        logTest( 'started', "the file system related to $info[0] on the $system system has sufficient space available." );
        my $sizeTestFailed = 0;
        if( $remote ) {
            $out = `ssh $system df -h $info[0] | sed '1d' | sed 'N;s/\\n/ /' | awk '{print \$4,\$5}'`;
            $rc = $? >> 8;
            if ( $rc == 255 ) {
                logTest( 'failed', "STN01", $system );
                next;
            }
        } else {
            $out = `df -h $info[0] | sed '1d' | sed 'N;s/\\n/ /' | awk '{print \$4,\$5}'`;
        }
        chomp( $out );
        if ( $out ) {
            @sizes = split( ' ', $out, 2 );
            # Percentage In Use test
            $sizes[1] =~ s/\%+$//g;       # trim percent from end of the string
            if ( $info[1] ne '.' and $sizes[1] > $info[1] ) {
                logTest( 'failed', "VDS01", $info[0], $system, $sizes[1], $info[1] );
                $sizeTestFailed = 1;
            }
            # Minimum Available Size test
            if ( $info[2] ne '.' and convertSize( $sizes[0] ) < convertSize( $minAvailableSpace ) ) {
                logTest( 'failed', "VDS02", $info[0], $system, $sizes[0], $minAvailableSpace );
                $sizeTestFailed = 1;
            }

            if ( $sizeTestFailed == 0 ) {
                logTest( 'misc', "The file system related to $info[0] on the $system system is $sizes[1] percent in use with $sizes[0] available." );
            }
        } else {
            logTest( 'failed', "VDS03", $system, $info[0] );
            $sizeTestFailed = 1;
            return 0;
        }

        if ( $info[3] ne '.' and $sizeTestFailed == 1 ) {
            # Show any large files in the directory space.
            logTest( 'started', "the file system related to $info[0] directory on $system system has reasonable size files." );
            if( $remote ) {
                $out = `ssh $system find $info[0] -mount -type f -size +$largeFileSize 2>/dev/null -exec ls -lh {} \\; | grep -v -e .so. -e .so -e .jar | awk \'{ print \$9 \": \" \$5 }\'`;
                $rc = $? >> 8;
                if ( $rc == 255 ) {
                    logTest( 'failed', "STN01", $system );
                    next;
                }
            } else {
                $out = `find $info[0] -mount -type f -size +$largeFileSize 2>/dev/null -exec ls -lh {} \\; | grep -v -e .so. -e .so -e .jar | awk \'{ print \$9 \": \" \$5 }\'`;
            }
            if ( $out ne '' ) {
                $out =~ s/\n+$//g;       # remove last newline
                logTest( 'failed', "VDS04", $largeFileSize, $out );
            } else {
                logTest( 'passed', "" );
            }
        }
    }

    if ( $system eq 'xCAT MN' and $glob_expectedReposSpace ne '' ) {
        if ( convertSize( $sizes[0] ) < convertSize( $glob_expectedReposSpace ) ) {
            logTest( 'failed', "VDS05", $sizes[0], $glob_expectedReposSpace );
        } else {
            logTest( 'passed', "" );
        }
    }

FINISH_verifyDirectorySpace:
    return 0;
}


#-------------------------------------------------------

=head3   verifyDiskPools

    Description : Verify disk pools are defined and have
                  at least a minimum amount of space.
    Arguments   : Array of expected disk pools.
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : $rc = verifyDiskPools( $hostNode, $diskpools );

    lsvm zhcp  --diskpoolnames
    lsvm zhcp  --diskpool pool1 free
    lsvm zhcp  --diskpool pool1 used

=cut

#-------------------------------------------------------
sub verifyDiskPools{
    my ( $hostNode, $diskPools ) = @_;
    my $out;
    my $zhcpNode;

    if ( exists $glob_hostNodes{$hostNode}{'zhcp'} ) {
        $zhcpNode = $glob_hostNodes{$hostNode}{'zhcp'};
    } else {
        return 0;
    }

    logTest( 'started', "disk pools for host: $hostNode." );

    $out = `/opt/xcat/bin/lsvm $zhcpNode  --diskpoolnames | awk '{print \$NF}'`;
    my @definedPools = split /\n/, $out;

    # Warn if no disk pools are defined.
    if ( @definedPools == 0 ) {
        logTest( 'failed', "VDP03", $hostNode );
        return 0;
    }

    logTest( 'misc', "$hostNode has the following disk pools defined: " . join(', ', @$diskPools) . "." );

    foreach my $diskPool ( @$diskPools ) {
        $diskPool = uc( $diskPool );

        # Verify pool is in the list of pools
        if ( grep { $_ eq $diskPool } @definedPools ) {
        } else {
            logTest( 'failed', "VDP01", $diskPool );
            next;
        }

        # Warn if we have very little disk space available
        $out = `/opt/xcat/bin/lsvm $zhcpNode --diskpool $diskPool free | grep $zhcpNode | sed '1d'`;
        my @disks = split /\n/, $out;
        my $numberOfDisks = @disks;
        if ( $numberOfDisks == 0 ) {
            if (( $diskPool ne 'XCAT' ) and ( $diskPool ne 'XCAT1' )) {
                logTest( 'failed', "VDP02", $diskPool );
            }
        } else {
            showPoolInfo( $diskPool, \@disks );
        }
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyHost

    Description : Verify the Host node is defined properly.
    Arguments   : Host node
                  ZHCP node
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : my $rc = verifyHost( $node );

=cut

#-------------------------------------------------------
sub verifyHost{
    my ( $node) = @_;
    my %hostInfo = getLsdefNodeInfo( $node );

    # Verify node is defined
    logTest( 'started', "that the host node ($node) is defined in xCAT." );
    my $count = keys %hostInfo;
    if ( $count == 0 ) {
      logTest( 'failed', "VHN01", $node );
      return 1;             # Critical error detected. IVP should exit.
    }

    # Verify the 'hcp' is defined for the node
    logTest( 'started', "a zHCP is associated with the host node ($node)." );
    if ( $hostInfo{'hcp'} eq '' ) {
        logTest( 'failed', "VHN02" );
        return 1;             # Critical error detected. IVP should exit.
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyHostNode

    Description : Verify the Host node is defined properly.
    Arguments   : Host node
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : my $rc = verifyHostNode( $node );

=cut

#-------------------------------------------------------
sub verifyHostNode{
    my ( $node ) = @_;
    my %hostInfo = getLsdefNodeInfo( $node );

    # Verify node is defined
    logTest( 'started', "that the host node ($node) is defined in xCAT." );
    my $count = keys %hostInfo;
    if ( $count == 0 ) {
      logTest( 'failed', "VHN01", $node );
      return 1;             # Critical error detected. IVP should exit.
    }

    # Verify the 'hcp' is defined for the node
    logTest( 'started', "a zHCP is associated with the host node ($node)." );
    if ( $hostInfo{'hcp'} eq '' ) {
        logTest( 'failed', "VHN02" );
        return 1;             # Critical error detected. IVP should exit.
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyMACUserPrefix

    Description : Verify that the specified MACADDR
                  user prefix matches the one on the host.
    Arguments   : Host node
                  MACADDR user prefix
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : verifyMACUserPrefix( $hostNode, $userPrefix );

=cut

#-------------------------------------------------------
sub verifyMACUserPrefix{
    my ( $hostNode, $userPrefix ) = @_;
    $userPrefix = uc( $userPrefix );
    logTest( 'started', "the z/VM system's MACID user prefix matches the one specified in the OpenStack configuration file." );

    my %nodeInfo = getLsdefNodeInfo($hostNode);

    my $hostUserPrefix = `ssh $nodeInfo{'hcp'} vmcp QUERY VMLAN | sed '1,/VMLAN MAC address assignment:/d' | grep '  MACADDR Prefix:' | awk '{print \$6}'`;
    chomp( $hostUserPrefix );

    if ( $userPrefix ne $hostUserPrefix ) {
        logTest( 'failed', "VMUP01", $hostNode, $hostUserPrefix, $userPrefix );
    } else {
        logTest( 'passed', "" );
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyMemorySize

    Description : Verify the virtual machine has
                  sufficient memory.
    Arguments   : None
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = verifyMemorySize($node, $args);

=cut

#-------------------------------------------------------
sub verifyMemorySize{
    my $vstorMin = '8G';
    my ( $out, $tag, $storSize );

    # Verify the virtual machine has the recommended virtual storage size.
    logTest( 'started', "xCAT MN has a virtual storage size of at least $vstorMin." );

    $out = `vmcp query virtual storage | grep STORAGE`;
    if ( $out eq '' ) {
        logTest( 'failed', "VMS01" );
        return 0;
    }

    ($tag, $storSize) = split(/=/, $out, 2);
    $storSize =~ s/^\s+|\s+$//g;       # trim both ends of the string
    my $convStorSize = convertSize( $storSize );
    my $convVStorMin = convertSize( $vstorMin );

    if ( $convStorSize < $convVStorMin ) {
        logTest( 'failed', "VMS02", $storSize, $vstorMin );
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyMiscHostStuff

    Description : Verify miscellaneous items related to
                  the host.
    Arguments   : Host node
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : my $rc = verifyMiscHostStuff( $node );

=cut

#-------------------------------------------------------
sub verifyMiscHostStuff{
    my ( $hostNode) = @_;
    my $out;
    my $rc;
    my $zhcpNode;

    if ( exists $glob_hostNodes{$hostNode}{'zhcp'} ) {
        $zhcpNode = $glob_hostNodes{$hostNode}{'zhcp'};
    } else {
        return 0;
    }

    # Verify the signal shutdown time is not too small
    logTest( 'started', "the signal shutdown timeout on $hostNode is more than $glob_signalTimeout." );
    my $timeVal;
    $out = `ssh $zhcpNode vmcp query signal shutdowntime`;
    $rc = $? >> 8;
    if ( $rc == 255 ) {
        logTest( 'failed', 'STN01', $zhcpNode );
    } elsif ( $out !~ "System default shutdown signal timeout:" ) {
        logTest( 'failed', 'VMHS01', $hostNode, $rc, $out );
    } else {
        ($timeVal) = $out =~ m/System default shutdown signal timeout: (.*) seconds/;
        if ( $timeVal < $glob_signalTimeout ) {
            logTest( 'failed', 'VMHS02', $hostNode, $timeVal, $glob_signalTimeout );
        }
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyMnIp

    Description : Verify the xCAT MN Ip is the same one used
                  by this xCAT MN.
    Arguments   : xCAT MN IP address or host name
                  hostName flag, 1 - can be a hostname, 0 - must be an IP address
                  descriptive name string
                  subnet mask (optional)
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : my $rc = verifyMnIp( $ip, $possibleHostname, $name, $subnetMask );

=cut

#-------------------------------------------------------
sub verifyMnIp{
    my ( $ip, $possibleHostname, $name, $subnetMask ) = @_;
    my ( $out, $rest );
    my $tgtIp = $ip;
    my $localRP;
    my $addrType = 4;

    # Verify the IP address or hostname is defined for this machine
    logTest( 'started', "xCAT MN has an interface for the $name defined as $ip." );

    if ( $possibleHostname ) {
        # Assume the input is a hostname, obtain the IP address associated with that name.
        # Look for the name in /etc/hosts
        $out = `grep " $ip " < /etc/hosts`;
        if ( $out ne '' ) {
            ($tgtIp, $rest) = split(/\s/, $out, 2);
        }
    }

    if ( $tgtIp =~ /:/ ) {
        $addrType = 6;
    }

    # Verify the IP address is defined
    $out=`ip addr show to $tgtIp`;
    if ( $out eq '' ) {
        logTest( 'failed', "VMNI01", $name, $tgtIp );
        return 0;                # Non-critical error detected
    } else {
        my $inetString;
        if ( $addrType == 4 ) {
            $inetString = "    inet";
        } else {
            $inetString = "    inet$addrType";
        }

        my @lines= split( /\n/, $out );
        @lines= grep( /$inetString/, @lines );
        if ( @lines == 0 ) {
            logTest( 'failed', "VMNI02", $name, $tgtIp );
            return 0;            # Non-critical error detected
        }
        my @ipInfo = split( ' ', $lines[0] );          # split, ignoring leading spaces
        my @parts = split( '/', $ipInfo[1] );
        $localRP = $parts[1];
    }

    # Verify the subnet mask matches what is set on the system
    if ( defined $subnetMask ) {
        logTest( 'started', "xCAT MN's subnet mask is $subnetMask." );
        my $rp = calculateRoutingPrefix( $subnetMask );
        if ( $rp == -1 ) {
            logTest( 'failed', "VMNI03", $subnetMask );
        }
        elsif ( $rp != $localRP ) {
            logTest( 'failed', "VMNI04", $tgtIp, $localRP, $rp, $subnetMask, $name );
        }
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyMnNode

    Description : Verify the xCAT MN node is defined properly.
    Arguments   : xCAT MN node
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : my $rc = verifyMnNode( $node );

=cut

#-------------------------------------------------------
sub verifyMnNode{
    my ( $node) = @_;
    my %mnInfo = getLsdefNodeInfo( $node );

    # Verify node is defined
    logTest( 'started', "xCAT MN node ($node) is defined in xCAT." );
    my $count = keys %mnInfo;
    if ( $count == 0 ) {
      logTest( 'failed', "VMN01", $node );
      return 0;                # Non-critical error detected
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyNodeExists

    Description : Verify that a named node exists in xCAT.
    Arguments   : Node name
                  Function of the node (e.g. "zHCP node")
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : verifyNodeExists($node, $function);

=cut

#-------------------------------------------------------
sub verifyNodeExists{
    my ( $node, $function ) = @_;

    logTest( 'started', "$function is defined and named $node." );
    my %hash = getLsdefNodeInfo($node);
    if ( %hash ) {
        logTest( 'passed', "" );
    } else {
        logTest( 'failed', "VNE01", $node );
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyNetworks

    Description : Verify the specified networks are defined
                  and have the expected VLAN settings.
    Arguments   : Host node name
                  Reference to array of networks to be verified
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : my $rc = verifyNetworks($hostNode, $network);

    lsvm zhcp  --getnetworknames
    lsvm zhcp  --getnetwork xcatvsw2

=cut

#-------------------------------------------------------
sub verifyNetworks{
    my ( $hostNode, $networks ) = @_;
    my $out;

    my $zhcpNode = $glob_hostNodes{$hostNode}{'zhcp'};

    foreach my $network ( @$networks ) {
        $network = uc( $network );

        # Split off any VLAN information from the input
        my $match;
        my @vlans = split( /:/, $network );
        if ( exists $vlans[1] ) {
            $network = $vlans[0];      # Remove vlan info from the $network variable
            $match = "VLAN Aware";
        } else {
            $match = "VLAN Unaware";
        }
        logTest( 'started', "$network is defined as a network to $hostNode." );

        # Obtain the network info
        my %switchInfo = getVswitchInfo( $zhcpNode, $network );
        if ( !%switchInfo ) {
            logTest( 'failed', "VN01", $network );
            next;                # Non-critical error detected, iterate to the next switch
        }

        # Verify that the defined network matches the expectations.
        logTest( 'started', "$network is $match" );
        if (( $match eq "VLAN Aware"  &&  $switchInfo{'Base'}{'VLAN ID'} != 0 ) ||
            ( $match eq "VLAN Unaware"  &&  $switchInfo{'Base'}{'VLAN ID'} == 0 )) {
            logTest( 'passed', "" );
        } else {
            logTest( 'failed', "VN02", $network, $match );
        }
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyProfile

    Description : Verify profile is defined in the z/VM directory.
    Arguments   : Host node name
                  Profile to be verified
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : $rc = verifyProfile($hostNode, $profile);

=cut

#-------------------------------------------------------
sub verifyProfile{
    my ( $hostNode, $profile ) = @_;
    $profile = uc( $profile );

    logTest( 'started', "$hostNode has the profile ($profile) in the z/VM directory." );
    my $zhcpNode = $glob_hostNodes{$hostNode}{'zhcp'};

    my $out = `/opt/xcat/bin/chhypervisor $hostNode --smcli 'Image_Query_DM -T $profile'`;
    if ( $out !~ "PROFILE $profile" ) {
      logTest( 'failed', "VP01", $profile );
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyREST

    Description : Verify the REST interface is running.
    Arguments   : None
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : my $rc = verifyREST();

=cut

#-------------------------------------------------------
sub verifyREST{
    logTest( 'started', "REST API is accepting requests from user $glob_xcatUser." );
    my @restOps = ();
    my $response = driveREST( $glob_xcatMNIp, $glob_xcatUser, $glob_xcatUserPw, "nodes/$glob_mnNode", "GET", "json", \@restOps );
    #print "Content: " . $response->content . "\n";
    #print "Code: " . $response->code . "\n";
    #print "Message: " .$response->message . "\n";

    if ( $response->message ne "OK" or $response->code != 200 ) {
        logTest( 'failed', "VR01", $response->code, $response->message, $response->content );
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyUser

    Description : Verify a user is authorized for xCAT MN.
    Arguments   : User
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : $rc = verifyUser( $user );

=cut

#-------------------------------------------------------
sub verifyUser{
    my ( $user ) = @_;
    my $out;

    logTest( 'started', "user ($user) is in the xCAT policy table." );
    $out = `/opt/xcat/bin/gettab name=\'$user\' policy.rule`;
    $out =~ s/^\s+|\s+$//g;       # trim both ends of the string
    if ( $out eq '' ) {
      logTest( 'failed', "VU01", $user );
    } elsif ( $out ne 'allow' and $out ne 'accept' ) {
      logTest( 'failed', "VU02", $user, $out );
    } else {
      logTest( 'passed', "The test is successful.  The user ($user) is in the policy table with the rule: \'$out\'." );
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyVswitchOSAs

    Description : Verify the specified vswitches OSA exist.
    Arguments   : Hash of Vswitches and their OSAs
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : my $rc = verifyVswitchOSAs( \%vswitchOSAs );

=cut

#-------------------------------------------------------
sub verifyVswitchOSAs{
    my ( $hostNode, $vswitchOSAs ) = @_;
    my $out;

    logTest( 'started', "vswitches with related OSAs are valid." );

    my $zhcpNode = $glob_hostNodes{$hostNode}{'zhcp'};

    # For each vswitch, verify that it has the specified OSA associated
    # with it and it is active or a backup.
    foreach my $switch ( keys %$vswitchOSAs ) {
        my %switchInfo = getVswitchInfoExtended( $zhcpNode, uc( $switch ) );
        if ( !%switchInfo ) {
            logTest( 'failed', "VVO01", $switch );
            next;                # Non-critical error detected, iterate to the next switch
        }

        my @devices = split( ',', $$vswitchOSAs{$switch} );
        foreach my $device ( @devices ) {
            $device = uc( $device );

            my @osa = split( /\./, $device );

            # Verify the RDEV
            $device = substr( "000$osa[0]", -4 ); # pad with zeroes
            if ( $switchInfo{'Real device'}{'RDEVs'} !~ $device ) {
                logTest( 'failed', "VVO02", $switch, $device );
            }
        }
    }

    return 0;
}


#-------------------------------------------------------

=head3   verifyZHCPNode

    Description : Verify the xCAT zHCP node is defined properly.
    Arguments   : Host node
    Returns     : 0 - OK, or only a non-critical error detected
                  non-zero - Critical error detected, IVP should exit.
    Example     : my $rc = verifyZHCPNode( $node );

=cut

#-------------------------------------------------------
sub verifyZHCPNode{
    my ( $hostNode ) = @_;
    my $out;
    my $rc;

    logTest( 'started', "that a zHCP node is associated with the host: $hostNode." );
    my $zhcpNode = findZhcpNode( $hostNode );
    if ( ! defined $zhcpNode ) {
        logTest( "failed", "VZN05", $hostNode );
        return 1;             # Critical error detected. IVP should exit.
    }
    my %zhcpNodeInfo = getLsdefNodeInfo( $zhcpNode );

    # Check if this ZHCP node is on the same system as the xCAT MN
    if ( exists $zhcpNodeInfo{'ip'} and exists $glob_localIPs{$zhcpNodeInfo{'ip'}} ) {
        $glob_localZHCP = $zhcpNode;
    }

    # Verify that we can ping zHCP
    logTest( 'started', "zHCP node ($zhcpNode) is running." );
    $out = `/opt/xcat/bin/pping $zhcpNode`;
    if ( $out !~ "$zhcpNode: ping" ) {
        logTest( 'failed', "VZN01", $zhcpNode );
        return 1;             # Critical error detected. IVP should exit.
    }

    # Obtain and zHCP version information.
    $out = `ssh $zhcpNode "[ -e \"/opt/zhcp/version\" ] \&\& cat \"/opt/zhcp/version\""`;
    $rc = $? >> 8;
    if ( $rc == 255) {
        logTest( 'failed', "STN01", $zhcpNode );
        return 1;             # Critical error detected. IVP should exit.
    }
    if ( $out ne '' ) {
        chomp( $out );
        $glob_versionInfo = "$glob_versionInfo\nOn $zhcpNode node: $out";
    } else {
        $glob_versionInfo = "$glob_versionInfo\nOn $zhcpNode node: ZHCP version level is unknown.";
    }

    # Drive a simple rpower request to zHCP which talks to CP
    logTest( 'started', "zHCP ($zhcpNode) can handle a simple request to talk to CP." );
    $out = `/opt/xcat/bin/rpower $zhcpNode stat | grep '$zhcpNode:'`;
    if ( $out !~ "$zhcpNode: on" ) {
        logTest( 'failed', "VZN02", $zhcpNode );
        return 1;             # Critical error detected. IVP should exit.
    }

    # Drive a simple SMAPI request thru zHCP
    logTest( 'started', "zHCP ($zhcpNode) can handle a simple request to SMAPI." );
    $out = `ssh $zhcpNode /opt/zhcp/bin/smcli Query_API_Functional_Level -T dummy 2>&1`;
    $rc = $? >> 8;
    if ( $rc == 255) {
        logTest( 'failed', "STN01", $zhcpNode );
        return 1;             # Critical error detected. IVP should exit.
    }
    if ( $out !~ "The API functional level is" ) {
        chomp( $out );
        logTest( 'failed', "VZN04", $zhcpNode, $out );
        return 1;             # Critical error detected. IVP should exit.
    }

    # Yea, We can talk to SMAPI.  Remember that we can use this ZHCP for other tests.
    $glob_hostNodes{$hostNode}{'zhcp'} = $zhcpNode;

    # Drive a more complex request to zHCP, an LSVM command
    logTest( 'started', "zHCP ($zhcpNode) can handle a more complex xCAT LSVM request." );
    $out = `/opt/xcat/bin/lsvm $zhcpNode | grep '$zhcpNode:'`;
    $rc = $? >> 8;
    if ( $rc == 255) {
        logTest( 'failed', "STN01", $zhcpNode );
        return 1;             # Critical error detected. IVP should exit.
    }
    my $zhcpUserid = uc( $zhcpNodeInfo{'userid'} );
    if ( $out !~ "USER $zhcpUserid" and $out !~ "IDENTITY $zhcpUserid" ) {
        logTest( 'failed', "VZN03", $zhcpNode, $zhcpUserid );
        return 1;             # Critical error detected. IVP should exit.
    }

    return 0;
}



#*****************************************************************************
# Main IVP routine
#*****************************************************************************

my $rc;
my $out;
my $userid;
my $terminatingError = 0;

# Update global variables based on overrides from an external perl script.
setOverrides();

# Handle help function.
if ( $glob_displayHelp == 1 ) {
    showHelp();
    goto FINISH;
}

# Establish SYSLOG logging for errors if function is desired.
if ( $glob_syslogErrors == 1 ) {
    my $user = $ENV{ 'USER' };
    setlogsock( 'unix' );
    openlog( 'xcatIVP', '', 'user');
    syslog( 'info', "Began xcatIVP test" );
}

# Detect CMA and obtain the CMA's version information
if ( -e $glob_versionFileCMA ) {
    $glob_CMA = 1;
    verifyCMAProperties();
} else {
    $glob_CMA = 0;
}

%glob_localIPs = getLocalIPs();

# Obtain the xCAT MN's version information
my $xcatVersion;
if ( -e $glob_versionFileXCAT ) {
    $out = `cat $glob_versionFileXCAT`;
    chomp( $out );
    $xcatVersion = "$out";
} else {
    $xcatVersion = "xCAT version: unknown";
}
if ( $glob_versionInfo eq '' ) {
    $glob_versionInfo = $xcatVersion;
} else {
    $glob_versionInfo = "$glob_versionInfo\n$xcatVersion";
}

# Verify the memory size.
if ( $glob_CMA == 1 ) {
    verifyMemorySize();
}

# Verify xCAT MN's IP address
if ( defined $glob_xcatMNIp) {
    verifyMnIp( $glob_xcatMNIp, 1, "xCAT server address" );
}

# Verify xCAT MN mgt network IP address
if ( defined $glob_xcatMgtIp) {
    verifyMnIp( $glob_xcatMgtIp, 0, "Mgt network IP address", $glob_mgtNetmask );
}

# Verify the management node is properly defined in xCAT
if ( defined $glob_mnNode ) {
    verifyMnNode( $glob_mnNode );
} else {
    logTest( 'bypassed', "BPVMN01" );
}

# Create the list of host node information.
if ( defined $glob_hostNode ) {
    $glob_hostNodes{$glob_hostNode}{'input'} = 1;
} else {
    my @hostNodes = getHostNodeNames();
    foreach my $hostNode (@hostNodes) {
        $glob_hostNodes{$hostNode}{'input'} = 0;
    }
    if ( keys %glob_hostNodes ) {
        $glob_hostNode = split( ' ', keys( %glob_hostNodes ), 1 );
    }
}

# Verify the host node is properly defined in xCAT and has a ZHCP agent.
foreach my $hostNode ( keys %glob_hostNodes ) {;
    $terminatingError = verifyHostNode( $hostNode );
    if ( $terminatingError and scalar keys( %glob_hostNodes ) == 1 ) {
         goto FINISH;
    }
    $terminatingError = 0;

    # Verify the zHCP node is properly defined in xCAT
    $terminatingError = verifyZHCPNode( $hostNode );
    if ( $terminatingError and keys( %glob_hostNodes ) == 1 ) {
        goto FINISH;
    }
    $terminatingError = 0;
}

# Verify the zHCP node specified as input is accessible.
if ( defined $glob_zhcpNode ) {
    # Verify the zHCP node is properly defined in xCAT
    verifyNodeExists( $glob_zhcpNode, "zHCP node" );
}

# Verify the disk pools used to create virtual machines exist
# in the Directory Manager.
if ( @glob_diskpools ) {
    verifyDiskPools( $glob_hostNode, \@glob_diskpools );
} else {
    logTest( 'bypassed', "BPVDP01" );
    foreach my $hostNode ( keys %glob_hostNodes ) {
        my @pools = getDiskPoolNames( $hostNode );
        verifyDiskPools( $hostNode, \@pools );
    }
}

# Verify the networks used by deployed virtual machines exist.
if ( @glob_networks ) {
    verifyNetworks( $glob_hostNode, \@glob_networks );
} else {
    logTest( 'bypassed', "BPVN01" );
}

# Verify the MACADDR user prefix matches the one on the host.
if ( defined $glob_macPrefix ) {
    verifyMACUserPrefix( $glob_hostNode, $glob_macPrefix );
}

# Verify vswitches with related OSAs are valid.
if ( %glob_vswitchOSAs ) {
    verifyVswitchOSAs( $glob_hostNode, \%glob_vswitchOSAs );
}

# Verify file system space on the xCAT MN.
verifyDirectorySpace( \@glob_xcatDiskSpace, 'xCAT MN', 0 );

# Verify file system space on the zhcp server for each host.
foreach my $hostNode ( keys %glob_hostNodes ) {
    verifyDirectorySpace( \@glob_zhcpDiskSpace, $glob_hostNodes{$hostNode}{'zhcp'}, 1 );
}

# Verify Host related items for each host in the hostNodes hash.
foreach my $hostNode ( keys %glob_hostNodes ) {
    # Verify default user profile is defined to the Directory Manager.
    if ( defined $glob_defaultUserProfile ) {
        verifyProfile( $hostNode, $glob_defaultUserProfile );
    }
    # Verify the signal shutdown interval is appropriate.
    if ( $glob_signalTimeout != 0 ) {
        verifyMiscHostStuff( $hostNode );
    }
}

# Verify the xCAT user is defined in the xCAT policy table.
if ( defined $glob_xcatUser ) {
    verifyUser( $glob_xcatUser );
}

# Verify the REST Interface is responsive.
if ( defined $glob_xcatUser and defined $glob_xcatUserPw and defined $glob_xcatMNIp and defined $glob_mnNode ) {
    verifyREST();
}

# Verify that xCAT MN can access the compute node.
if ( defined $glob_cNAddress and defined $glob_expUser ) {
    verifyComputeNodeConnectivity( $glob_cNAddress, $glob_expUser );
} else {
    logTest( "bypassed", "BPVCNC01" );
}

FINISH:
if ( $terminatingError ) {
    logTest( "warning", "MAIN01" );
}

logTest( "misc", "" );

if ( $glob_versionInfo ) {
    logTest( "miscNF", "The following versions of code were detected:\n" . $glob_versionInfo );
    logTest( "misc", "" );
}

if ( scalar(@glob_failedTests) != 0 ) {
    logTest( "misc",  "The following tests generated warning(s): " . join(", ", @glob_failedTests) . '.' );
}
if ( $glob_displayHelp != 1 ) {
    logTest( "misc", "$glob_testNum IVP tests ran, " . $glob_totalFailed . " tests generated warnings." );
}

if ( $glob_ignoreCnt != 0 ){
    logTest( "misc", "Ignored messages $glob_ignoreCnt times." );
    my @ignoreArray = sort keys %glob_ignored;
    my $ignoreList = join ( ', ', @ignoreArray );
    logTest( "misc", "Message Ids of ignored messages: $ignoreList" );
}

# Close out our use of syslog
if ( $glob_syslogErrors == 1 ) {
    syslog( 'info', "Ended zxcatIVP test" );
    closelog();
}

exit 0;
