#!/usr/bin/perl
###############################################################################
# IBM (C) Copyright 2015, 2016 Eclipse Public License
# http://www.eclipse.org/org/documents/epl-v10.html
###############################################################################
# COMPONENT: zxcatExport
#
# This is a program to save the xCAT tables to the /install/xcatmigrate directory;
# then close and export the /install LVM
#
# The reverse process on the other system can be done if the LVM disks are
# writeable and online. The zxcatmigrate script can be used for that.
# It will issue pvscan, vgimport, vgchange -ay, mkdir, then mount commands.
#
###############################################################################

use strict;
use warnings;
use Capture::Tiny ':all';
use Getopt::Long;
use lib '/opt/xcat/lib/perl/';
use xCAT::TableUtils;
use xCAT::zvmUtils;
$| = 1; # turn off STDOUT buffering

my $lvmPath = "/dev/xcat/repo";
my $mountPoint = "/install";
my $exportDir = "/install/xcatmigrate";
my $exportTablesDir = "/install/xcatmigrate/xcattables";
my $exportFcpConfigsDir = "/install/xcatmigrate/fcpconfigs";
my $exportFcpOtherFilesDir = "/install/xcatmigrate/fcpotherfiles";
my $exportDocloneFilesDir = "/install/xcatmigrate/doclone";
my $lvmInfoFile = "lvminformation";
my $lsdasdInfoFile = "lsdasdinformation";
my $zvmVirtualDasdInfoFile = "zvmvirtualdasdinformation";
my $vgName = "xcat";

# xCAT table information to be filled in
my $masterIP;
my $xcatNode;
my $hcp;
my $zhcpNode;

my $version = "1.1";
my $targetIP = "";              # IP address to get data from
my $skipInstallFiles = 0;       # Skip copying any install files
my $skipTables = 0;             # Skip copying and installing xcat tables
my $displayHelp = 0;            # Display help information
my $versionOpt = 0;             # Show version information flag

my @entries;
my @propNames;
my $propVals;

my $usage_string = "This script saves the xcat tables in /install/xcatmigrate and\n
then exports the LVM mounted at /install. This should only be used to migrate\n
the /install LVM to a new userid.\n\n
 Usage:\n
    $0 [ -v ]\n
    $0 [ -h | --help ]\n
    The following options are supported:\n
      -h | --help         Display help information\n
      -v                  Display the version of this script.\n";


#-------------------------------------------------------

=head3   chompall

    Description : Issue chomp on all three input parms (pass by reference)
    Arguments   : arg1, arg2, arg3
    Returns     : nothing
    Example     : chompall(\$out, \$err, \$returnvalue);

=cut

#-------------------------------------------------------
sub chompall{
    my ( $arg1, $arg2, $arg3 ) = @_;
    chomp($$arg1);
    chomp($$arg2);
    chomp($$arg3);
}

# ***********************************************************
# Mainline. Parse any arguments, usually no arguments
$Getopt::Long::ignorecase = 0;
Getopt::Long::Configure( "bundling" );

GetOptions(
    'h|help'          => \$displayHelp,
    'v'               => \$versionOpt );

if ( $versionOpt ) {
    print "Version: $version\n";
    exit;
}

if ( $displayHelp ) {
    print $usage_string;
    exit;
}

my $out = '';
my $err = '';
my $returnvalue = 0;

# This looks in the passwd table for a key = sudoer
($::SUDOER, $::SUDO) = xCAT::zvmUtils->getSudoer();

# Scan the xCAT tables to get the zhcp node name
# Print out a message and stop if any errors found
@entries = xCAT::TableUtils->get_site_attribute("master");
$masterIP = $entries[0];
if ( !$masterIP ) {
    print "xCAT site table is missing a master with ip address\n";
    exit;
}

# Get xcat node name from 'hosts' table using IP as key
@propNames = ( 'node');
$propVals = xCAT::zvmUtils->getTabPropsByKey('hosts', 'ip', $masterIP, @propNames);
$xcatNode = $propVals->{'node'};
if ( !$xcatNode ) {
    print "xCAT hosts table is missing a node with ip address of $masterIP\n";
    exit;
}

# Get hcp for xcat from the zvm table using xcat node name
@propNames = ( 'hcp');
$propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $xcatNode, @propNames );
$hcp = $propVals->{'hcp'};
if ( !$hcp ) {
    print "xCAT zvm table is missing hcp value for $xcatNode\n";
    exit;
}

# Get zhcp node name from 'hosts' table using hostname as key
@propNames = ( 'node');
$propVals = xCAT::zvmUtils->getTabPropsByKey('hosts', 'hostnames', $hcp, @propNames);
$zhcpNode = $propVals->{'node'};
if ( !$zhcpNode ) {
    print "xCAT hosts table is missing a zhcp node with hostname of $hcp\n";
    exit;
}

#Create the migrate directory and the xcat tables directory. This should not get error even if it exists
print "Creating directory $exportDir\n";
( $out, $err, $returnvalue ) = eval { capture { system( "mkdir -p -m 0755 $exportDir"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue) {
    print "Error rv:$returnvalue trying to create $exportDir:\n";
    print "$err\n";
    exit;
}

print "Creating directory $exportTablesDir\n";
( $out, $err, $returnvalue ) = eval { capture { system( "mkdir -p -m 0755 $exportTablesDir"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue) {
    print "Error rv:$returnvalue trying to create $exportTablesDir:\n";
    print "$err\n";
    exit;
}

print "Creating directory $exportFcpConfigsDir\n";
( $out, $err, $returnvalue ) = eval { capture { system( "mkdir -p -m 0755 $exportFcpConfigsDir"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue) {
    print "Error rv:$returnvalue trying to create $exportFcpConfigsDir:\n";
    print "$err\n";
    exit;
}

print "Creating directory $exportFcpOtherFilesDir\n";
( $out, $err, $returnvalue ) = eval { capture { system( "mkdir -p -m 0755 $exportFcpOtherFilesDir"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue) {
    print "Error rv:$returnvalue trying to create $exportFcpOtherFilesDir:\n";
    print "$err\n";
    exit;
}

print "Creating directory $exportDocloneFilesDir\n";
( $out, $err, $returnvalue ) = eval { capture { system( "mkdir -p -m 0755 $exportDocloneFilesDir"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue) {
    print "Error rv:$returnvalue trying to create $exportDocloneFilesDir:\n";
    print "$err\n";
    exit;
}

#Save the current LVM information
print "Saving current LVM information at $exportDir/$lvmInfoFile \n";
( $out, $err, $returnvalue ) = eval { capture { system( "vgdisplay '-v' 2>&1 > $exportDir/$lvmInfoFile"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue) {
    print "Error rv:$returnvalue trying to display LVM information:\n";
    print "$err\n";
    exit;
}

#Save the current Linux DASD list information
print "Saving current Linux DASD list information at $exportDir/$lsdasdInfoFile \n";
( $out, $err, $returnvalue ) = eval { capture { system( "lsdasd 2>&1 > $exportDir/$lsdasdInfoFile"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue) {
    print "Error rv:$returnvalue trying to display Linux DASD list information:\n";
    print "$err\n";
    exit;
}

#Save the current zVM virtual DASD list information
print "Saving current zVM virtual DASD list information at $exportDir/$zvmVirtualDasdInfoFile \n";
( $out, $err, $returnvalue ) = eval { capture { system( "vmcp q v dasd 2>&1 > $exportDir/$zvmVirtualDasdInfoFile"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue) {
    print "Error rv:$returnvalue trying to display zVM virtual DASD list information:\n";
    print "$err\n";
    exit;
}

#save the xcat tables
print "Dumping xCAT tables to $exportTablesDir\n";
( $out, $err, $returnvalue ) = eval { capture { system( ". /etc/profile.d/xcat.sh; /opt/xcat/sbin/dumpxCATdb -p $exportTablesDir"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue) {
    print "Error rv:$returnvalue trying to dump the xcat tables to $exportTablesDir:\n";
    print "$err\n";
    exit;
}

#Check for and save any zhcp FCP configuration files
print "Checking zhcp for any FCP configuration files\n";
( $out, $err, $returnvalue ) = eval { capture { system( "ssh $zhcpNode ls /var/opt/zhcp/zfcp/*.conf"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue == 0) {
    # Save any *.conf files
    print "Copying /var/opt/zhcp/zfcp/*.conf files to $exportFcpConfigsDir\n";
    ( $out, $err, $returnvalue ) = eval { capture { system( "scp $::SUDOER\@$zhcpNode:/var/opt/zhcp/zfcp/*.conf $exportFcpConfigsDir"); } };
    chompall(\$out, \$err, \$returnvalue);
    if ($returnvalue) {
        print "Error rv:$returnvalue trying to use scp to copy files from $zhcpNode\n";
        print "$err\n";
        exit;
    }
} else {
    # If file not found, that is an OK error,  if others then display error and exit
    if (index($err, "No such file or directory")== -1) {
        print "Error rv:$returnvalue trying to use ssh to list files on $zhcpNode\n";
        print "$err\n";
        exit;
    }
}
# Check for any other zhcp FCP files
( $out, $err, $returnvalue ) = eval { capture { system( "ssh $zhcpNode ls /opt/zhcp/conf/*"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue == 0) {
    # Save any files found
    print "Copying /opt/zhcp/conf/*.conf files to $exportFcpOtherFilesDir\n";
    ( $out, $err, $returnvalue ) = eval { capture { system( "scp $::SUDOER\@$zhcpNode:/opt/zhcp/conf/* $exportFcpOtherFilesDir"); } };
    chompall(\$out, \$err, \$returnvalue);
    if ($returnvalue) {
        print "Error rv:$returnvalue trying to use scp to copy /opt/zhcp/conf/* files from $zhcpNode\n";
        print "$err\n";
        exit;
    }
} else {
    # If file not found, that is an OK error,  if others then display error and exit
    if (index($err, "No such file or directory")== -1) {
        print "Error rv:$returnvalue trying to use ssh to list files on $zhcpNode\n";
        print "$err\n";
        exit;
    }
}

# Check for any doclone.txt file
( $out, $err, $returnvalue ) = eval { capture { system( "ls /var/opt/xcat/doclone.txt"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue == 0) {
    # Save any file found
    print "Copying /var/opt/xcat/doclone.txt file to $exportDocloneFilesDir\n";
    ( $out, $err, $returnvalue ) = eval { capture { system( "cp /var/opt/xcat/doclone.txt $exportDocloneFilesDir"); } };
    chompall(\$out, \$err, \$returnvalue);
    if ($returnvalue) {
        print "Error rv:$returnvalue trying to copy /var/opt/xcat/doclone.txt file\n";
        print "$err\n";
        exit;
    }
} else {
    # If file not found, that is an OK error,  if others then display error and exit
    if (index($err, "No such file or directory")== -1) {
        print "Error rv:$returnvalue trying to copy /var/opt/xcat/doclone.txt file\n";
        print "$err\n";
        exit;
    }
}

#unmount the /install
print "Unmounting $lvmPath\n";
( $out, $err, $returnvalue ) = eval { capture { system( "umount $lvmPath"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue) {
    print "Error rv:$returnvalue trying to umount $lvmPath:\n";
    print "$err\n";
    exit;
}

#mark the lvm inactive
print "Making the LVM $vgName inactive\n";
( $out, $err, $returnvalue ) = eval { capture { system( "vgchange '-an' $vgName"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue) {
    print "Error rv:$returnvalue trying to inactivate volume group $vgName:\n";
    print "$err\n";
    exit;
}

#export the volume group
print "Exporting the volume group $vgName\n";
( $out, $err, $returnvalue ) = eval { capture { system( "vgexport $vgName"); } };
chompall(\$out, \$err, \$returnvalue);
if ($returnvalue) {
    print "Error rv:$returnvalue trying to export volume group $vgName:\n";
    print "$err\n";
    exit;
}

print "\nVolume group $vgName is exported, you can now signal shutdown xcat and\n";
print "have the xcat lvm disks linked RW in the new appliance.";
exit 0;


