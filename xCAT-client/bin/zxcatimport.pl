#!/usr/bin/perl
###############################################################################
# IBM (C) Copyright 2015, 2016 Eclipse Public License
# http://www.eclipse.org/org/documents/epl-v10.html
###############################################################################
# COMPONENT: zxcatimport
#
# This is a program to copy the xCAT /install files and the xCAT tables from
# an old XCAT userid to the new appliance
# See usage string below for parameters.
# return code = 0 successful; else error.
#
###############################################################################

use strict;
use warnings;
use Capture::Tiny ':all';
use Getopt::Long;
use lib '/opt/xcat/lib/perl/';
use xCAT::TableUtils;
use xCAT::Table;
use xCAT::zvmUtils;
use xCAT::MsgUtils;

my $lvmPath = "/dev/xcat/repo";
my $lvmMountPoint = "/install2";
my $lvmImportDir = "/install2/xcatmigrate";
my $lvmImportTablesDir = "/install2/xcatmigrate/xcattables";
my $lvmImportFcpConfigsDir = "/install2/xcatmigrate/fcpconfigs";
my $lvmImportFcpOtherFilesDir = "/install2/xcatmigrate/fcpotherfiles";
my $lvmImportDocloneFilesDir = "/install2/xcatmigrate/doclone";
my $lvmInfoFile = "lvminformation";
my $lsdasdInfoFile = "lsdasdinformation";
my $zvmVirtualDasdInfoFile = "zvmvirtualdasdinformation";
my $vgName = "xcat";
my $persistentMountPoint = "/persistent2";
my @defaultTables = ("hosts", "hypervisor", "linuximage", "mac", "networks", "nodelist",
                     "nodetype", "policy", "zvm");

my $version = "1.0";
my $out;
my $err;
my $returnValue;

my $copyLvmFiles = 0;           # Copy files under old /install to new /install
my $replaceAllXcatTables = 0;   # Copy one or all xcat tables
my $addTableData = '*none*';    # Add node data to one table or default tables
my $copyFcpConfigs = 0;         # copy old zhcp fcp *.conf files
my $copyDoclone = 0;            # copy old doclone.txt file
my $replaceSshKeys = 0;         # replace SSH keys with old xCAT SSH keys
my $displayHelp = 0;            # Display help information
my $versionOpt = 0;             # Show version information flag
my $rc = 0;

my $usage_string = "This script will mount or copy the old xcat lvm and old persistent disk\n
to this appliance. The old xCAT LVM volumes and the persistent disk on XCAT userid must \n
be linked in write mode by this appliance. The LVM will be mounted at '/install2' and \n
the persistent disk will be mounted at '/persistent2'.\n
\n
The default is to just mount the persistent and LVM disks.\n
They will be mounted as /install2 and /persistent2\n\n

 Usage:\n
    $0 [--addtabledata [tablename]] [--installfiles ] [--doclonefile]\n
          [--fcppoolconfigs] [--replacealltables] [--replaceSSHkeys] \n
    $0 [ -v ]\n
    $0 [ -h | --help ]\n
    The following options are supported:\n
      --addtabledata [tablename] | ['tablename1 tablename2 ..']\n
                          Add old xCAT data to specific table(s) or\n
                          default to the following xCAT tables:\n
                          hosts, hypervisor, linuximage, mac, networks, nodelist,\n
                          nodetype, policy, zvm/n
      --installfiles      Copy any files from old /install to appliance /install\n
      --doclonefile       Copy any doclone.txt to appliance\n
      --fcppoolconfigs    Copy any zhcp FCP pool configuration files\n
      --replacealltables  Replace all xCAT tables with old xCAT tables\n
      --replaceSSHkeys    Replaces the current xCAT SSH keys with the old xCAT SSH keys\n
      -h | --help         Display help information\n
      -v                  Display the version of this script.\n";

#-------------------------------------------------------

=head3   chompall

    Description : Issue chomp on all three input parms (pass by reference)
    Arguments   : arg1, arg2, arg3
    Returns     : nothing
    Example     : chompall(\$out, \$err, \$returnValue);

=cut

#-------------------------------------------------------
sub chompall{
    my ( $arg1, $arg2, $arg3 ) = @_;
    chomp($$arg1);
    chomp($$arg2);
    chomp($$arg3);
}

# =======unit test/debugging routine ==========
# print the return data from tiny capture return
# data for: out, err, return value
sub printreturndata{
    my ( $arg1, $arg2, $arg3 ) = @_;
    print "=============================\n";
    print "Return value ($$arg3)\n";
    print "out ($$arg1)\n";
    print "err ($$arg2)\n\n";
}

## ---------------------------------------------- ##
##  Subroutine to find device name from address

sub get_disk($)
{
    my ($id_user) = @_;
    my $id = hex $id_user;
    my $hex_id = sprintf '%x', $id;
    my $dev_path = sprintf '/sys/bus/ccw/drivers/dasd-eckd/0.0.%04x', $id;
    unless (-d $dev_path) {
       $dev_path = sprintf '/sys/bus/ccw/drivers/dasd-fba/0.0.%04x', $id;
    }
    -d $dev_path or return undef;
    my $dev_block = "$dev_path/block";
    unless (-d $dev_block) {
         # Try bringing the device online
         for (1..5) {
             system("echo 1 > $dev_path/online");
             last if -d $dev_block;
             sleep(10);
         }
    }
    opendir(my $dir, $dev_block) or return undef;
    my $dev;
    while ($dev = readdir $dir) {
         last unless $dev eq '.' || $dev eq '..';
    }
    closedir $dir;
    defined $dev ? "/dev/$dev" : undef;
}

#-------------------------------------------------------

=head3   mountOldLVM

    Description : This routine will import the old LVM and mount
                  it at /install2
    Arguments   : none
    Returns     : 0 - LVM mounted or already mounted
                  non-zero - Error detected.
    Example     : $rc = mountOldLVM;

=cut

#-------------------------------------------------------
sub mountOldLVM{

    my $saveMsg;
    my $saveErr;
    my $saveReturnValue;

    #Check for /install2 If already mounted should get a return value(8192) and $err output
    #Check $err for "is already mounted on", if found we are done.
    print "Checking for $lvmMountPoint.\n";
    ( $out, $err, $returnValue ) = eval { capture { system( "mount $lvmMountPoint"); } };
    chompall(\$out, \$err, \$returnValue);
    if (index($err, "already mounted on $lvmMountPoint") > -1) {
        print "Old xCAT LVM is already mounted at $lvmMountPoint\n";
        return 0;
    }

    print "Importing $vgName\n";
    ( $out, $err, $returnValue ) = eval { capture { system( "/sbin/vgimport $vgName"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        # There could be a case where the LVM has been imported already
        # Save this error information and do the next step (vgchange)
        $saveMsg = "Error rv:$returnValue trying to vgimport $vgName";
        $saveErr = "$err";
        $saveReturnValue = $returnValue;
    }

    print "Activating LVM $vgName\n";
    ( $out, $err, $returnValue ) = eval { capture { system( "/sbin/vgchange -a y $vgName"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        # If the import failed previously, put out that message instead.
        if (!defined $saveMsg) {
            print "$saveMsg\n";
            print "$saveErr\n";
            return $saveReturnValue;
        } else {
            print "Error rv:$returnValue trying to vgchange -a y $vgName\n";
            print "$err\n";
            retun $returnValue;
        }
    }

    print "Making $lvmMountPoint directory\n";
    ( $out, $err, $returnValue ) = eval { capture { system( "mkdir -p $lvmMountPoint"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to mkdir -p $lvmMountPoint\n";
        print "$err\n";
        return $returnValue;
    }

    print "Mounting LVM $lvmPath at $lvmMountPoint\n";
    ( $out, $err, $returnValue ) = eval { capture { system( "mount -t ext3 $lvmPath $lvmMountPoint"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to mkdir -p $lvmMountPoint\n";
        print "$err\n";
        return $returnValue;
    }

    print "Old xCAT LVM is now mounted at $lvmMountPoint\n";
    return 0;
}

#-------------------------------------------------------

=head3   mountOldPersistent

    Description : This routine will look for the old persistent disk and mount
                  it at /persistent2
    Arguments   : none
    Returns     : 0 - /persistent2 mounted or already mounted
                  non-zero - Error detected.
    Example     : $rc = mountOldPersistent;

=cut

#-------------------------------------------------------
sub mountOldPersistent{

    #Check for /persistent2 If already mounted should get a return value(8192) and $err output
    #Check $err for "is already mounted on", if found we are done.
    print "Checking for $persistentMountPoint.\n";
    ( $out, $err, $returnValue ) = eval { capture { system( "mount $persistentMountPoint"); } };
    chompall(\$out, \$err, \$returnValue);
    if (index($err, "already mounted on $persistentMountPoint") > -1) {
        print "The old xCAT /persistent disk already mounted at $persistentMountPoint\n";
        return 0;
    }

    # search the exported Linux lsdasd file to get the vdev for vdev 100 (dasda)
    # should look like: 0.0.0100   active      dasda     94:0    ECKD  4096   2341MB    599400
    my $dasda = `cat "$lvmImportDir/$lsdasdInfoFile" | egrep -i "dasda"`;
    if (length($dasda) <= 50) {
        print "Unable to find dasda information in $lvmImportDir/$lsdasdInfoFile\n";
        return 1;
    }
    my @tokens = split(/\s+/, $dasda);
    my @vdevparts = split (/\./, $tokens[0]);
    my $vdev = $vdevparts[2];
    if (!(length($vdev))) {
        print "Unable to find a vdev value for dasda\n";
        return 1;
    }

    # search the exported zVM virtual dasd list to get the volume id of the disk
    # should look like: DASD 0100 3390 QVCD69 R/W       3330 CYL ON DASD  CD69 SUBCHANNEL = 000B
    my $voliddata = `cat "$lvmImportDir/$zvmVirtualDasdInfoFile" | egrep -i "DASD $vdev"`;
    if (length($voliddata) <= 50) {
        print "Unable to find volid information for $vdev in $lvmImportDir/$zvmVirtualDasdInfoFile\n";
        return 1;
    }
    @tokens = split(/\s+/, $voliddata);
    my $volid = $tokens[3];
    if (!(length($volid))) {
        print "Unable to find a volume id for vdev $vdev\n";
        return 1;
    }

    # Now display the current zVM query v dasd to see if they have the volid listed
    # and what vdev it is mounted on
    ( $out, $err, $returnValue ) = eval { capture { system( "vmcp q v dasd 2>&1"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to vmcp q v dasd\n";
        print "$err\n";
        return $returnValue;
    }

    # get the current VDEV the old volid is now using
    # If not they they did not update the directory to link to the old classic disk
    ( $out, $err, $returnValue ) = eval { capture { system( "echo \"$out\" | egrep -i $volid"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to echo $out\n";
        print "$err\n";
        return $returnValue;
    }
    if (!(length($out))) {
        print "Unable to find a current vdev value for volume id $volid\n";
        return 1;
    }
    @tokens = split(/\s+/, $out);
    my $currentvdev = $tokens[1];
    if (!(length($currentvdev))) {
        print "Unable to find a current vdev value for volume id $volid\n";
        return 1;
    }

    # Now get the Linux disk name that is being used for this vdev (/dev/dasdx)
    my $devname = get_disk($currentvdev);
    #print "Devname found: $devname\n";
    if (!(defined $devname)) {
        print "Unable to find a Linux disk for address $currentvdev volume id $volid\n";
        return 1;
    }

    # Create the directory for the mount of old persistent disk
    ( $out, $err, $returnValue ) = eval { capture { system( "mkdir -p -m 0755 $persistentMountPoint"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to create $persistentMountPoint:\n";
        print "$err\n";
        return $returnValue;
    }

    # Mount the old persistent disk, must be partition 1
    my $partition = 1;
    ( $out, $err, $returnValue ) = eval { capture { system( "mount -t ext3 $devname$partition $persistentMountPoint"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to mount -t ext3 $devname$partition $persistentMountPoint\n";
        print "$err\n";
        return $returnValue;
    }
    print "The old xCAT /persistent disk is mounted at $persistentMountPoint\n";
    return 0;
}
# ***********************************************************
# Mainline. Parse any arguments
$Getopt::Long::ignorecase = 0;
Getopt::Long::Configure( "bundling" );

GetOptions(
    'installfiles'     => \$copyLvmFiles,
    'replacealltables' => \$replaceAllXcatTables,
    'addtabledata:s'   => \$addTableData,
    'fcppoolconfigs'   => \$copyFcpConfigs,
    'doclonefile'      => \$copyDoclone,
    'replaceSSHkeys'   => \$replaceSshKeys,
    'h|help'           => \$displayHelp,
    'v'                => \$versionOpt );

if ( $versionOpt ) {
    print "Version: $version\n";
    exit 0;
}

if ( $displayHelp ) {
    print $usage_string;
    exit 0;
}

# Use sudo or not
# This looks in the passwd table for a key = sudoer
($::SUDOER, $::SUDO) = xCAT::zvmUtils->getSudoer();

$rc = mountOldLVM();
if ($rc != 0) {
    exit 1;
}

$rc = mountOldPersistent();
if ($rc != 0) {
    exit 1;
}

# *****************************************************************************
# **** Copy the LVM files from old xCAT LVM to current LVM
if ( $copyLvmFiles ) {
    $rc = chdir("$lvmMountPoint");
    if (!$rc) {
        print "Error rv:$rc trying to chdir $lvmMountPoint\n";
        exit 1;
    }

    $out = `cp -a * /install 2>&1`;
    if ($?) {
        print "Error rv:$? trying to copy from $lvmMountPoint to /install. $out\n";
        exit $?;
    }
    print "Old LVM Files copied from $lvmMountPoint to /install\n" ;
}

# *****************************************************************************
# **** Replace all the current xCAT tables with the old xCAT tables
if ( $replaceAllXcatTables ) {
    print "Restoring old xCAT tables from $lvmImportTablesDir\n";
    # restorexCATdb - restores the xCAT db tables from the directory  -p path
    ( $out, $err, $returnValue ) = eval { capture { system( ". /etc/profile.d/xcat.sh; /opt/xcat/sbin/restorexCATdb -p $lvmImportTablesDir"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to restore the xcat tables from $lvmImportTablesDir:\n";
        print "$err\n";
        exit 1;
    }
    # There is a chance the return value is 0, and the $out says "Restore of Database Complete.";
    # Yet some of the tables had failures. That information is in $err
    if (length($err)) {
        print "Some tables did not restore. Error output:\n$err\n ";
        exit 1;
    }
}

# *****************************************************************************
# **** Copy the zhcp FCP config files
if ($copyFcpConfigs) {
    # Check if there are any FCP config files to copy
    ( $out, $err, $returnValue ) = eval { capture { system( "ls $lvmImportFcpConfigsDir/*.conf"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue == 0) {
        # Save any *.conf files
        print "Copying $lvmImportFcpConfigsDir/*.conf files to /var/opt/zhcp/zfcp\n";
        ( $out, $err, $returnValue ) = eval { capture { system( "mkdir -p /var/opt/zhcp/zfcp && cp -R $lvmImportFcpConfigsDir/*.conf /var/opt/zhcp/zfcp/"); } };
        chompall(\$out, \$err, \$returnValue);
        if ($returnValue) {
            print "Error rv:$returnValue trying to use cp to copy files from $lvmImportFcpConfigsDir\n";
            print "$err\n";
            exit 1;
        }
    } else {
        print "There were not any zhcp FCP *.conf files to copy\n";
    }
    # Check if there are any other FCP files to copy
    ( $out, $err, $returnValue ) = eval { capture { system( "ls $lvmImportFcpOtherFilesDir/*"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue == 0) {
        # Save any files
        print "Copying $lvmImportFcpOtherFilesDir/* files to /opt/zhcp/conf\n";
        ( $out, $err, $returnValue ) = eval { capture { system( "mkdir -p /opt/zhcp/conf && cp -R $lvmImportFcpOtherFilesDir/* /opt/zhcp/conf/"); } };
        chompall(\$out, \$err, \$returnValue);
        if ($returnValue) {
            print "Error rv:$returnValue trying to use cp to copy files from $lvmImportFcpOtherFilesDir\n";
            print "$err\n";
            exit 1;
        }
    } else {
        print "There were not any zhcp files from /opt/zhcp/conf to copy\n";
    }
}

# *****************************************************************************
# **** Copy the doclone.txt file if it exists
if ($copyDoclone) {
    # Check if there is a doclone.txt to copy
    ( $out, $err, $returnValue ) = eval { capture { system( "ls $lvmImportDocloneFilesDir/doclone.txt"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue == 0) {
        # Save this file in correct location
        print "Copying $lvmImportDocloneFilesDir/doclone.txt file to /var/opt/xcat/doclone.txt\n";
        ( $out, $err, $returnValue ) = eval { capture { system( "cp -R $lvmImportDocloneFilesDir/doclone.txt /var/opt/xcat/"); } };
        chompall(\$out, \$err, \$returnValue);
        if ($returnValue) {
            print "Error rv:$returnValue trying to use cp to copy doclone.txt file from $lvmImportDocloneFilesDir\n";
            print "$err\n";
            exit 1;
        }
    } else {
        print "There was not any doclone.txt file to copy\n";
    }
}

# *****************************************************************************
# **** Add old xCAT table data to a table
my $test = length($addTableData);
# Add old xCAT data to an existing table. Admin may need to delete out duplicates using the GUI
if ((length($addTableData)==0) || $addTableData ne "*none*") {
    #defaultTables = ("hosts", "hypervisor", "linuximage", "mac", "networks", "nodelist",
    #                  "nodetype", "policy", "zvm");
    my @tables = @defaultTables;
    if (length($addTableData)>1 ) {
        # use the table specified
        @tables = ();
        @tables = split(' ',$addTableData);
    }
    foreach my $atable (@tables) {
        print "Adding data to table $atable\n";
        # the current xCAT code we have does not support the -a option
        # use xCAT::Table functions

        my $tabledata = `cat "$lvmImportTablesDir\/$atable\.csv"`;
        if (length($tabledata) <= 10) {
                print "Unable to find table information for $atable in $lvmImportTablesDir\n";
                return 1;
        }
        # remove the hash tag from front
        $tabledata =~ s/\#//;
        my @rows = split('\n', $tabledata);
        my @keys;
        my @values;
        my $tab;
        # loop through all the csv rows, first are the header keys, rest is data
        foreach my $i (0 .. $#rows) {
            my %record;
            #print "row $i data($rows[$i])\n";
            if ($i == 0) {
                @keys = split(',', $rows[0]);
                #print "Keys found:(@keys)\n";
            } else {
                # now that we know we have data, lets create table
                if (!defined $tab) {
                    $tab = xCAT::Table->new($atable, -create => 1, -autocommit => 0);
                }
                # put the data into the new table.
                @values = split(',', $rows[$i]);
                foreach my $v (0 .. $#values) {
                    # Strip off any leading and trailing double quotes
                    $values[$v] =~ s/"(.*?)"\z/$1/s;
                    $record{$keys[$v]} = $values[$v];
                    #print "Row $i matches key $keys[$v] Value found:($values[$v])\n";
                }
            }
            # write out the row if any keys added to the hash
            if (%record) {
                my @dbrc = $tab->setAttribs(\%record, \%record);
                if (!defined($dbrc[0])) {
                    print "Error ($dbrc[1]) setting database for table $atable";
                    $tab->rollback();
                    $tab->close;
                    exit 1;
                }
            }
        }
        # if we made it here and $tab is defined, commit it.
        if (defined $tab) {
            $tab->commit;
            print "Data successfully added and committed to $atable.\n*****! Remember to check the table and remove any rows not needed\n";
        }
    }#end for each table
}

# *****************************************************************************
# **** Replace the xCAT SSH key with the old xCAT SSH key

# First copy the current keys and copy the old xCAT keys into unique file names
if ($replaceSshKeys) {
    # Make temp file names to hold the current and old ssh public and private key
    my $copySshKey= `/bin/mktemp -p /root/.ssh/ id_rsa.pub_XXXXXXXX`;
    chomp($copySshKey);
    my $copySshPrivateKey= `/bin/mktemp -p /root/.ssh/ id_rsa_XXXXXXXX`;
    chomp($copySshPrivateKey);

    # Make temp files for the RSA backup keys in appliance
    my $copyHostSshKey= `/bin/mktemp -p /etc/ssh/ ssh_host_rsa_key.pub_XXXXXXXX`;
    chomp($copyHostSshKey);
    my $copyHostSshPrivateKey= `/bin/mktemp -p /etc/ssh/ ssh_host_rsa_key_XXXXXXXX`;
    chomp($copyHostSshPrivateKey);

    # Save old keys in unique names
    my $oldSshKey= `/bin/mktemp -p /root/.ssh/ id_rsa.pub_OldMachineXXXXXXXX`;
    chomp($oldSshKey);
    my $oldSshPrivateKey= `/bin/mktemp -p /root/.ssh/ id_rsa_OldMachineXXXXXXXX`;
    chomp($oldSshPrivateKey);

    print "Making backup copies of current xCAT SSH keys\n";
    ( $out, $err, $returnValue ) = eval { capture { system( "cp \-p /root/.ssh/id_rsa.pub $copySshKey"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to use cp to copy /root/.ssh/id_rsa.pub to $copySshKey\n";
        print "$err\n";
        exit 1;
    }
    ( $out, $err, $returnValue ) = eval { capture { system( "cp \-p /root/.ssh/id_rsa $copySshPrivateKey"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to use cp to copy /root/.ssh/id_rsa to $copySshPrivateKey\n";
        print "$err\n";
        exit 1;
    }

    # Save appliance backup keys
    ( $out, $err, $returnValue ) = eval { capture { system( "cp \-p /etc/ssh/ssh_host_rsa_key.pub $copyHostSshKey"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to use cp to copy /etc/ssh/ssh_host_rsa_key.pub to $copyHostSshKey\n";
        print "$err\n";
        exit 1;
    }
    ( $out, $err, $returnValue ) = eval { capture { system( "cp \-p /etc/ssh/ssh_host_rsa_key $copyHostSshPrivateKey"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to use cp to copy /etc/ssh/ssh_host_rsa_key to $copyHostSshPrivateKey\n";
        print "$err\n";
        exit 1;
    }

    # Copy the old public key and make sure the permissions are 644
    print "Copying old xCAT SSH keys (renamed) from /persistent2 to /root/.ssh\n";
    ( $out, $err, $returnValue ) = eval { capture { system( "cp /persistent2/root/.ssh/id_rsa.pub $oldSshKey"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to use cp to copy /persistent2/root/.ssh/id_rsa.pub to $oldSshKey\n";
        print "$err\n";
        exit 1;
    }
    ( $out, $err, $returnValue ) = eval { capture { system( "chmod 644 $oldSshKey"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to chmod 644 $oldSshKey\n";
        print "$err\n";
        exit 1;
    }

    # Copy the private key and make sure the permissions are 600
    ( $out, $err, $returnValue ) = eval { capture { system( "cp /persistent2/root/.ssh/id_rsa $oldSshPrivateKey"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to use cp to copy /persistent2/root/.ssh/id_rsa to $oldSshPrivateKey\n";
        print "$err\n";
        exit 1;
    }
    ( $out, $err, $returnValue ) = eval { capture { system( "chmod 600 $oldSshPrivateKey"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to chmod 600 $oldSshPrivateKey\n";
        print "$err\n";
        exit 1;
    }

    # Now compare the IP of xCAT to zHCP .
    # If they are the same, then only the private and public key in xCAT needs to be changed.
    # If zhcp is on a different machine, then the first thing to be done is add the old xCAT key
    # to the zhcp authorized_keys files, then do the switch on xcat of public and private keys

    my $xcatIp;
    my $zhcpIp;
    my $zhcpHostName;
    my $zhcpNode;
    my $xcatNodeName;
    my @propNames;
    my $propVals;
    my @entries;
    my $rc = 0;

    # Scan the xCAT tables to get the zhcp node name
    # Print out a message and stop if any errors found
    @entries = xCAT::TableUtils->get_site_attribute("master");
    $xcatIp = $entries[0];
    if ( !$xcatIp ) {
        print "xCAT site table is missing a master with ip address\n";
        exit 1;
    }

    # Get xcat node name from 'hosts' table using IP as key
    @propNames = ( 'node');
    $propVals = xCAT::zvmUtils->getTabPropsByKey('hosts', 'ip', $xcatIp, @propNames);
    $xcatNodeName = $propVals->{'node'};
    if ( !$xcatNodeName ) {
        print "xCAT hosts table is missing a node with ip address of $xcatIp\n";
        exit 1;
    }

    # Get hcp hostname for xcat from the zvm table using xcat node name
    @propNames = ( 'hcp');
    $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $xcatNodeName, @propNames );
    $zhcpHostName = $propVals->{'hcp'};
    if ( !$zhcpHostName ) {
        print "xCAT zvm table is missing hcp value for $xcatNodeName\n";
        exit 1;
    }

    # Get zhcp IP and node from 'hosts' table using hostname as key
    @propNames = ( 'ip', 'node');
    $propVals = xCAT::zvmUtils->getTabPropsByKey('hosts', 'hostnames', $zhcpHostName, @propNames);
    $zhcpIp = $propVals->{'ip'};
    if ( !$zhcpIp ) {
        print "xCAT hosts table is missing a zhcp node IP with hostname of $zhcpHostName\n";
        exit 1;
    }
    $zhcpNode = $propVals->{'node'};
    if ( !$zhcpNode ) {
        print "xCAT hosts table is missing a zhcp node with hostname of $zhcpHostName\n";
        exit 1;
    }

    if ($zhcpIp eq $xcatIp) {
        print "xCAt and zhcp are on same IP, only need to update public and private keys\n";
    } else {
        # Need to append the old SSH key to zhcp authorized_keys file
        my $target = "$::SUDOER\@$zhcpHostName";
        print "Copying old SSH key to zhcp\n";
        ( $out, $err, $returnValue ) = eval { capture { system( "scp $oldSshKey $target:$oldSshKey"); } };
        chompall(\$out, \$err, \$returnValue);
        if ($returnValue) {
            print "Error rv:$returnValue trying to use scp to copy $oldSshKey to zhcp $oldSshKey\n";
            print "$err\n";
            exit 1;
        }
        # Adding the old SSH key to the authorized_keys file
        # Make a copy of the old authorized_users file
        my $suffix = '_' . substr($oldSshKey, -8);
        ( $out, $err, $returnValue ) = eval { capture { system( "ssh $target cp \"/root/.ssh/authorized_keys /root/.ssh/authorized_keys$suffix\""); } };
        chompall(\$out, \$err, \$returnValue);
        if ($returnValue) {
            print "Error rv:$returnValue trying to make a copy of the /root/.ssh/authorized_keys file\n";
            print "$err\n";
            exit 1;
        }
        # Add the key to zhcp authorized_keys file
        ( $out, $err, $returnValue ) = eval { capture { system( "ssh $target cat \"$oldSshKey >> /root/.ssh/authorized_keys\""); } };
        chompall(\$out, \$err, \$returnValue);
        if ($returnValue) {
            print "Error rv:$returnValue trying to append zhcp $oldSshKey to /root/.ssh/authorized_keys\n";
            print "$err\n";
            exit 1;
        }
    }
    # We need to replace the xCAT public and private key with the old keys
    # and add the old key to the authorized_keys on xCAT
    ( $out, $err, $returnValue ) = eval { capture { system( "cat $oldSshKey >> /root/.ssh/authorized_keys"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to append xcat $oldSshKey to /root/.ssh/authorized_keys\n";
        print "$err\n";
        exit 1;
    }
    ( $out, $err, $returnValue ) = eval { capture { system( "cp \-f $oldSshKey /root/.ssh/id_rsa.pub"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to replace the /root/.ssh/id_rsa.pub with the $oldSshKey\n";
        print "$err\n";
        exit 1;
    }
    ( $out, $err, $returnValue ) = eval { capture { system( "cp \-f $oldSshPrivateKey /root/.ssh/id_rsa"); } };
    chompall(\$out, \$err, \$returnValue);
    #printreturndata(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to replace the /root/.ssh/id_rsa with the $oldSshPrivateKey\n";
        print "$err\n";
        exit 1;
    }
    # Copy old keys into appliance saved key locations
    ( $out, $err, $returnValue ) = eval { capture { system( "cp \-f $oldSshKey /etc/ssh/ssh_host_rsa_key.pub"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to replace the /etc/ssh/ssh_host_rsa_key.pub with the $oldSshKey\n";
        print "$err\n";
        exit 1;
    }
    ( $out, $err, $returnValue ) = eval { capture { system( "cp \-f $oldSshPrivateKey /etc/ssh/ssh_host_rsa_key"); } };
    chompall(\$out, \$err, \$returnValue);
    if ($returnValue) {
        print "Error rv:$returnValue trying to replace the /etc/ssh/ssh_host_rsa_key with the $oldSshPrivateKey\n";
        print "$err\n";
        exit 1;
    }

    print "Old xCAT SSH keys have replaced current SSH keys. Previous key data saved in unique names.\n";
}

exit 0;
