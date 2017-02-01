#!/usr/bin/perl
###############################################################################
# IBM (C) Copyright 2015, 2016 Eclipse Public License
# http://www.eclipse.org/org/documents/epl-v10.html
###############################################################################
# COMPONENT: zxcatCopyCloneList.pl
#
# This is a program to copy the "DOCLONE COPY" file from the 193 disk to
# /opt/xcat/doclone.txt
###############################################################################

use strict;
#use warnings;
use Capture::Tiny ':all';
use Getopt::Long;

my $file_location = '/var/opt/xcat/';
my $source_file   = 'DOCLONE.COPY';
my $file_name     = 'doclone.txt';
my $tempPattern   = 'doclone.XXXXXXXX';
my $source_vdev   = '193';
my $version = "1.0";
my $out;
my $err;
my $returnvalue;
my $displayHelp = 0;            # Display help information
my $versionOpt = 0;             # Show version information flag

my $usage_string = "This script copies the DOCLONE COPY from the MAINT 193
to the $file_location$file_name\n\n
 Usage:\n
    $0 [ -v ]
    $0 [ -h | --help ]\n
    The following options are supported:\n
      -h | --help         Display help information\n
      -v                  Display the version of this script.\n";

# Copied this routine from sspmodload.pl
# This will get the Linux address of the vdev
sub get_disk($)
{
    my ($id_user) = @_;
    my $id = hex $id_user;
    my $hex_id = sprintf '%x', $id;
    my $completed = 1;
    my $dev_path = sprintf '/sys/bus/ccw/drivers/dasd-eckd/0.0.%04x', $id;
    if (!-d $dev_path) {
       $dev_path = sprintf '/sys/bus/ccw/drivers/dasd-fba/0.0.%04x', $id;
    }
    if (!-d $dev_path) {
        print "(Error) Unable to find a path to the $source_vdev in /sys/bus/ccw/drivers/\n";
    }
    -d $dev_path or return undef;

    #offline the disk so that a new online will pick up the current file
    my @sleepTimes = ( 1, 2, 3, 5, 8, 15, 22, 34, 60);
    system("echo 0 > $dev_path/online");

    my $dev_block = "$dev_path/block";

    #wait if the disk directory is still there
    if (-d $dev_block) {
        $completed = 0;
        foreach (@sleepTimes) {
            system("echo 0 > $dev_path/online");
            sleep $_;
            if (!-d $dev_block) {
                $completed = 1;
                last;
            }
        }
    }

    if (!$completed) {
        print "(Error) The 193 disk failed to complete the offline!\n";
        return undef;
    }

    system("echo 1 > $dev_path/online");
    # Bring the device online if offline
    if (!-d $dev_block) {
        $completed = 0;
        foreach (@sleepTimes) {
            system("echo 1 > $dev_path/online");
            sleep $_;
            if (-d $dev_block) {
                $completed = 1;
                last;
            }
        }
        if (!$completed) {
            print "(Error) The 193 disk failed to come online!\n";
            return undef;
        }
    }
    if (opendir(my $dir, $dev_block)) {
        my $dev;
        while ($dev = readdir $dir) {
            last if (!( $dev eq '.' || $dev eq '..' ) );
        }
        closedir $dir;
        if (!defined $dev) {
            print "(Error) undefined $dev\n";
        }
        defined $dev ? "/dev/$dev" : undef;
    } else {
       print "(Error) Unable to opendir $dev_block\n";
       return undef;
    }
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
    exit 0;
}

if ( $displayHelp ) {
    print $usage_string;
    exit 0;
}

my $tempFileName = '';
my $rc = 0;
my $oldFileExists = 0;
my $dev = get_disk($source_vdev);
if (defined($dev)) {
    # make sure directory exists
    if (!-d $file_location) {
        $returnvalue = mkdir "$file_location", 0755;
        if (!$returnvalue) {
            print "(Error) mkdir $file_location failed with errno:$!";
            $rc = 1;
            goto MAIN_EXIT;

        }
    }
    my $oldFiletime;
    # Create a temp file name to use while validating
    $tempFileName = `/bin/mktemp -p $file_location $tempPattern`;
    chomp($tempFileName);
    # if we are overwriting an existing file, save time stamp
    if (-e "$file_location$file_name") {
        # stat will return results in $returnvalue
        ( $out, $err, $returnvalue ) = eval { capture { `stat \'-c%y\' $file_location$file_name` } };
        chomp($out);
        chomp($err);
        chomp($returnvalue);
        if (length($err) > 0) {
            print "(Error) Cannot stat the $file_location$file_name\n$err\n";
            $rc = 1;
            goto MAIN_EXIT;
        }
        $oldFileExists = 1;
        $oldFiletime = $returnvalue;
    }

    ( $out, $err, $returnvalue ) = eval { capture { `/sbin/cmsfscp -d $dev -a $source_file $tempFileName` } };
    chomp($out);
    chomp($err);
    chomp($returnvalue);
    if (length($err) > 0) {
        # skip any blksize message for other blksize
        if ($err =~ 'does not match device blksize') {
        } else {
            print "(Error) Cannot copy $source_file\n$err\n";
            $rc = 1;
            goto MAIN_EXIT;
        }
    }

    if ($oldFileExists == 1) {
        ( $out, $err, $returnvalue ) = eval { capture { `stat \'-c%y\' $tempFileName` } };
        chomp($out);
        chomp($err);
        chomp($returnvalue);
        if (length($err) > 0) {
            print "(Error) Cannot stat the $tempFileName\n$err\n";
            $rc = 1;
            goto MAIN_EXIT;
        }
        if ($oldFiletime eq $returnvalue) {
            print "The $source_file copied to temporary file $tempFileName is the same time stamp as original.\n";
        } else {
            print "$source_file copied to temporary file $tempFileName successfully\n";
        }
    } else {
        print "$source_file copied to temporary file $tempFileName successfully\n";
    }

    print "Validating $tempFileName contents for proper syntax...\n";
    if (-f "$tempFileName") {
        $out = `cat $tempFileName`;
    } else {
        print "(Error) Missing temporary file: $tempFileName\n";
        $rc = 1;
        goto MAIN_EXIT;
    }
    my @lines = split('\n',$out);
    my %hash = ();
    my %imagenames = ();
    my $count = @lines;
    if ($count < 1) {
        print "(Error) $tempFileName does not have any data.\n";
        ( $out, $err, $returnvalue ) = eval { capture { `rm $tempFileName` } };
        chomp($out);
        chomp($err);
        chomp($returnvalue);
        if (length($err) > 0) {
            print "(Error) Cannot erase temporary file $tempFileName $err\n";
        }
        $rc = 1;
        goto MAIN_EXIT;
    }

    # loop for any lines found
    for (my $i=0; $i < $count; $i++) {
        # skip comment lines, * or /*
        if ( $lines[$i] =~ '^\s*[\*]') {
            next;
        }
        if ( $lines[$i] =~ '^\s*/[*]') {
            next;
        }
        # is this a blank line? if so skip it
        if ($lines[$i] =~/^\s*$/) {
            next;
        }
        my $semicolons = $lines[$i] =~ tr/\;//;
        if ($semicolons < 3) {
            print "(Error) Semicolons need to end each key=value on line ".($i+1)."\n";
            $rc = 1;
        }

        %hash = ('IMAGE_NAME' => 0,'CLONE_FROM' => 0,'ECKD_POOL' => 0, 'FBA_POOL' => 0 );
        # IMAGE_NAME=imgBoth; CLONE_FROM=testFBA; ECKD_POOL=POOLECKD; FBA_POOL=POOLFBA
        my @parms = split( ';', $lines[$i]);
        my $parmcount = @parms;
        # get the key and value for this item, store in hash
        for (my $j=0; $j < $parmcount; $j++) {
            # if this token is all blanks skip it. Could be reading blanks at the end of the line
            if ($parms[$j] =~ /^\s*$/) {
                next;
            }
            my $parmlength = length($parms[$j]);
            my @keyvalue = split('=', $parms[$j]);
            my $key   = $keyvalue[0];
            $key =~ s/^\s+|\s+$//g; # get rid of leading and trailing blanks

            if ( length( $key ) == 0 ) {
                print "(Error) Missing keyword on line ".($i+1)."\n";
                $rc = 1;
                next;
            }
            my $value = $keyvalue[1];
            $value =~ s/^\s+|\s+$//g;
            if ( length( $value ) == 0 ) {
                print "(Error) Missing value for key $key on line ".($i+1)."\n";
                $rc = 1;
                next
            }
            #uppercase both key and value;
            my $UCkey   = uc $key;
            my $UCvalue = uc $value;
            $hash{$UCkey} = $hash{$UCkey} + 1;
            if ($UCkey eq "IMAGE_NAME") {
                if (exists $imagenames{$UCvalue}) {
                    print "(Error) Duplicate IMAGE_NAME found on line ".($i+1)." with value: $value\n";
                    $rc = 1;
                } else {
                    $imagenames{$UCvalue} = 1;
                }
            }
            if ($UCkey ne "IMAGE_NAME" && $UCkey ne "CLONE_FROM" && $UCkey ne "ECKD_POOL" && $UCkey ne "FBA_POOL") {
                print "(Error) Unknown keyword $key found on line ".($i+1)."\n";
                $rc = 1;
            }
        }
        # Check to make sure they have at least an image name, from and one pool
        if ($hash{IMAGE_NAME} == 1 && $hash{CLONE_FROM} == 1 && ($hash{ECKD_POOL} ==1 || $hash{FBA_POOL} ==1 )) {
            next;
        } else {
            if ($hash{IMAGE_NAME} == 0) {
                print "(Error) Missing IMAGE_NAME key=value on line ".($i+1)."\n";
                $rc = 1;
            }
            if ($hash{IMAGE_NAME} > 1) {
                print "(Error) Multiple IMAGE_NAME keys found on line ".($i+1)."\n";
                $rc = 1;
            }
            if ($hash{CLONE_FROM} == 0) {
                print "(Error) Missing CLONE_FROM key=value on line ".($i+1)."\n";
                $rc = 1;
            }
            if ($hash{CLONE_FROM} > 1) {
                print "(Error) Multiple CLONE_FROM keys found on line ".($i+1)."\n";
                $rc = 1;
            }
            if ($hash{ECKD_POOL} == 0 && $hash{FBA_POOL} == 0) {
                print "(Error) Missing ECKD_POOL or FBA_POOL on line ".($i+1)."\n";
                $rc = 1;
            }
            if ($hash{ECKD_POOL} > 1) {
                print "(Error) Multiple ECKD_POOL keys found on line ".($i+1)."\n";
                $rc = 1;
            }
            if ($hash{FBA_POOL} > 1) {
                print "(Error) Multiple FBA_POOL keys found on line ".($i+1)."\n";
                $rc = 1;
            }
        }
    }
} else {
    print "(Error) Unable to access the $source_vdev disk.\n";
    $rc = 1;
}
# Main exit for this routine.  Handles any necessary clean up.
MAIN_EXIT:
if (length($tempFileName) > 0 ) {
    # If a good rc, Copy the temp file to the correct file
    if ($rc == 0) {
        ( $out, $err, $returnvalue ) = eval { capture { `/bin/cp -f $tempFileName $file_location$file_name` } };
        print $out;
        print $err;
        print $returnvalue;
        chomp($out);
        chomp($err);
        chomp($returnvalue);
        if (length($err) > 0) {
            print "(Error) Cannot copy the temporary file $tempFileName to $file_location$file_name \n $err\n";
            $rc = 1;
        } else {
            print "Validation completed. Temporary file copied to $file_location$file_name.\nIt is ready to use\n";
        }
    }
    ( $out, $err, $returnvalue ) = eval { capture { `rm $tempFileName` } };
    chomp($out);
    chomp($err);
    chomp($returnvalue);
    if (length($err) > 0) {
        print "(Error) Cannot erase temporary file $tempFileName\n$err\n";
        $rc = 1;
    }
}
exit $rc;
