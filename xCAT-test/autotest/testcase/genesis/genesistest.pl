#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Utils;
use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use Term::ANSIColor;
use Time::Local;
use File::Basename;
use File::Path;
use File::Copy;
use Sys::Hostname;
my $program_name              = basename("$0");
my $genesis_runcmd_test       = 0;
my $genesis_runimg_test       = 0;
my $genesis_nodesetshell_test = 0;
my $check_genesis_file;
my $noderange;
my $clear_env;
my $help = 0;
$::USAGE = "Usage:
    $program_name -h
    $program_name -n <node_range> -s 
    $program_name -n <node_range> -d 
    $program_name -n <node_range> -i 
    $program_name -n <node_range> -c
    $program_name -n <node_range> -g
Description:
    Run genesis testcase
    There will be default scripts for genesis's runcmd and runimg test if anyone want to use this function to test genesis please write scripts in /tmp/cmdtest for runcmd test and in /tmp/imgtest for runimg test
Options:
    -n : The range of node
    -i : Run genesis runimage
    -d : Run genesis runcmd
    -s : Run genesis nodeshell mode 
    -c : Clear genesis test environment
    -g : Check genesis file 
";
##################################
# main process
##################################
if (
    !GetOptions("h|?" => \$help,
        "s"   => \$genesis_nodesetshell_test,
        "d"   => \$genesis_runcmd_test,
        "i"   => \$genesis_runimg_test,
        "n=s" => \$noderange,
        "g"   => \$check_genesis_file,
        "c"   => \$clear_env
    ))
{
    send_msg(0, "$::USAGE");
    print "$::USAGE";
    exit 1;
}
if ($help) {
    print "$::USAGE";
    exit 0;
}
###############################
# init
##############################
if (!defined($noderange)) {
    send_msg(0, "Option -n is required");
    print "$::USAGE";
    exit 1;
}
my $os = xCAT::Utils->osver("all");
if ($check_genesis_file) {
    send_msg(2, "[$$]:Check genesis file...............");
    &check_genesis_file(&get_arch);
    if ($?) {
        send_msg(0, "genesis file not available");
    } else {
        send_msg(2, "genesis file available");
    }
}
my $master=xCAT::TableUtils->get_site_Master();
if (!$master) { $master=hostname(); }

####################################
####nodesetshell test for genesis
####################################
if ($genesis_nodesetshell_test) {
    send_msg(2, "[$$]:Running nodesetshell test...............");
    `nodeset $noderange shell`;
    if ($?) {
        send_msg(0, "[$$]:nodeset shell failed...............");
        exit 1;
    }
    `rpower $noderange boot`;
    if ($?) {
        send_msg(0, "[$$]:rpower node failed...............");
        exit 1;
    }
    #run nodeshell test
    send_msg(2, "prepare for nodeshell script.");
    if ( &testxdsh(3)) {
        send_msg(0, "[$$]:Could not verify test results using xdsh...............");
        exit 1;
    }
    send_msg(2, "[$$]:Running nodesetshell test success...............");
}
####################################
####runcmd test for genesis
####################################
if ($genesis_runcmd_test) {
    send_msg(2, "[$$]:Running runcmd test...............");
    if (&testxdsh(&rungenesiscmd(&get_arch))) {
        send_msg(0, "[$$]:Could not verify test results using xdsh...............");
        exit 1;
    }
    send_msg(2, "[$$]:Running runcmd test success...............");
}
##################################
####runimg test for genesis
##################################
if ($genesis_runimg_test) {
    send_msg(2, "[$$]:Run runimg test...............");
    if (&testxdsh(&rungenesisimg)) {
        send_msg(0, "[$$]:Could not verify test results using xdsh ...............");
        exit 1;
    }

    send_msg(2, "[$$]:Running runimage test success...............");
}
###################################
####clear test environment
###################################
if ($clear_env) {
    send_msg(2, "[$$]:clear genesis test enviroment...............");
    if (&clearenv(&get_arch)) {
        send_msg(0, "[$$]:clear environment failed...............");
        exit 1;
    }
    send_msg(2, "[$$]:clear genesis test enviroment success...............");
}
##################################
#check_genesis_file
#################################
sub check_genesis_file {
    my $arch = shift;
    my $genesis_base;
    my $genesis_scripts;
    if ($os =~ "unknown") {
        send_msg(0, "The OS is not supported.");
        return 1;
    } elsif ($os =~ "ubuntu") {
        $genesis_base = `dpkg -l | grep -i "ii  xcat-genesis-base" | grep -i "$arch"`;
        $genesis_scripts = `dpkg -l | grep -i "ii  xcat-genesis-scripts" | grep -i "$arch"`;
    } else {
        $genesis_base = `rpm -qa | grep -i "xcat-genesis-base" | grep -i "$arch"`;
        $genesis_scripts = `rpm -qa | grep -i "xcat-genesis-scripts" | grep -i "$arch"`;
    }
    unless ($genesis_base and $genesis_scripts) {
        send_msg(0, "xCAT-genesis for $arch did not be installed.");
        return 1;
    }
    return 0;
}
###################################################
###write runcmd script to verify runcmd could work
##################################################
sub rungenesiscmd {
    my $runcmd_script    = "/tmp/cmdtest";
    my $result           = "/tmp/testresult";
    my $genesis_base_dir = "$::XCATROOT/share/xcat/netboot/genesis";
    my $genesis_bin_dir;
    my $value = 0;
    my $arch  = shift;
    if (!(-e $runcmd_script)) {
        $value = 1;

        #means runcmd test using test scripts genesistest.pl writes
        send_msg(2, "no runcmd scripts for test prepared.");
        open(TESTCMD, ">$runcmd_script")
          or die "Can't open testscripts for writing: $!";
        print TESTCMD join("\n", "#!/bin/bash"),                       "\n";
        print TESTCMD join("\n", "#This is test for genesis scripts"), "\n";
        print TESTCMD join("\n", "echo \"testcmd\" >> $result"),       "\n";
        close(TESTCMD);
    } else {
        $value = 3;

        #means runcmd test using test scripts user writes
        send_msg(2, "runcmd scripts for test ready.");
    }
    $genesis_bin_dir = "$genesis_base_dir/$arch/fs/bin";
    copy("$runcmd_script", "$genesis_bin_dir");
    chmod 0755, "$genesis_bin_dir/cmdtest";
    `mknb $arch`;
    if ($?) {
        send_msg(0, "mknb $arch failed for runcmd test.");
    }
    `nodeset $noderange "runcmd=cmdtest,shell"`;
    if ($?) {
        send_msg(0, "nodeset noderange shell failed for runcmd test");
    }
    `rpower $noderange boot`;
    if ($?) {
        send_msg(0, "rpower noderange boot failed for runcmd test");
    }
    return $value;
}
#######################################################################################################################
####write runimage script to verify runimage could work eg.runimage=http://<IP of xCAT Management Node>/<dir>/image.tgz
#######################################################################################################################
sub rungenesisimg {
    my $runimg_script    = "/tmp/imgtest";
    my $result           = "/tmp/testresult";
    my $genesis_base_dir = "$::XCATROOT/share/xcat/netboot/genesis";
    my $genesis_bin_dir;
    my $value = 0;
    mkdir("/install/my_image");
    if (!(-e $runimg_script)) {
        $value = 2;

        #means runimg test using test scripts genesistest.pl writes
        send_msg(2, "no runimg scripts for test prepared.");
        open(TESTIMG, ">$runimg_script")
          or die "Can't open testscripts for writing: $!";
        print TESTIMG join("\n", "#!/bin/bash"),                       "\n";
        print TESTIMG join("\n", "#This is test for genesis scripts"), "\n";
        print TESTIMG join("\n", "echo \"testimg\" >> $result"),       "\n";
        close(TESTIMG);
        print "value is $value \n";
    } else {
        $value = 3;

        #means runimg test using test scripts user writes
        send_msg(2, "runimg scripts for test ready.");
    }
    copy("$runimg_script", "/install/my_image/runme.sh") or die "Copy failed: $!";
    chmod 0755, "/install/my_image/runme.sh";
    `tar -zcvf /tmp/my_image.tgz -C /install/my_image .`;
    copy("/tmp/my_image.tgz", "/install/my_image") or die "Copy failed: $!";
    `nodeset $noderange "runimage=http://$master/install/my_image/my_image.tgz",shell`;
    if ($?) {
        send_msg(0, "nodeset noderange failed for runimg");
    }
    `rpower $noderange boot`;
    if ($?) {
        send_msg(0, "rpower boot failed for runimg test");
    }
    return $value;
}
########################################
####sleep while for xdsh $$CN could work
#########################################
sub testxdsh {
    my $value = shift;
    print "value is $value \n";
    my $checkstring;
    my $checkfile;
    if ($value == 1) {
        #mean runcmd test using test scripts genesistest.pl writes
        $checkstring = "testcmd";
        $checkfile   = "/tmp/testresult";
    } elsif ($value == 2) {
        $checkstring = "testimg";
        $checkfile   = "/tmp/testresult";
    } elsif ($value == 3) {
        $checkstring = "destiny=shell";
        $checkfile   = "/proc/cmdline";
    }
    if (($value == 1) || ($value == 2) || ($value == 3)) {
        `xdsh $noderange -t 2 cat $checkfile |grep $checkstring`;
        if ($?) {
            foreach (1 .. 1500) {
                `xdsh $noderange -t 2 cat $checkfile | grep $checkstring`;
                last if ($? == 0);
            }
        }
    }
    return $?;
}
##########################
####clear test environment
##########################
sub clearenv {
    my $arch             = shift;
    my $runcmd_script    = "/tmp/cmdtest";
    my $runimg_script    = "/tmp/imgtest";
    my $runme            = "/install/my_image/runme.sh";
    my $runmetar            = "/install/my_image/my_image.tgz";
    my $runmetar_tmp         = "/tmp/my_image.tgz";
    my $runmedir         = "/install/my_image";
    my $genesis_base_dir = "$::XCATROOT/share/xcat/netboot/genesis";
    if (-e "$runimg_script") {
        unlink("$runme");
        unlink("$runmetar_tmp");
        unlink("$runmetar");
        unlink("$runimg_script");
        rmdir("$runmedir");
        send_msg(2, "clear runimage test environment");
    }
    if (-e "$runcmd_script") {
        my $genesis_bin_dir     = "$genesis_base_dir/$arch/fs/bin";
        my $genesis_test_script = "$genesis_bin_dir/cmdtest";
        unlink("$genesis_test_script");
        unlink("$runcmd_script");
        `mknb $arch`;
        if ($?) {
            send_msg(0, "mknb for runcmd test environment failed");
            exit 1;
        }
    }
    `nodeset $noderange boot`;
    if ($?) {
        send_msg(0, "nodeset node failed");
        exit 1;
    }
    `rpower $noderange boot`;
    if ($?) {
        send_msg(0, "rpower node failed");
        exit 1;
    }
    return 0;
}
####################################
#get arch
###################################
sub get_arch {
     use POSIX qw(uname);
     my @uname = uname();
     my $arch = $uname[4];
     if ($arch =~ /ppc64/i) {
         $arch = "ppc64";
     } elsif (($arch =~ /x86/i)&&($os =~ /ubuntu/i)) {
         if ($check_genesis_file) {
             $arch = "amd64";
         } 
     } 
    return $arch;
}
#######################################
## send messages
########################################
sub send_msg {
    my $log_level = shift;
    my $msg = shift;
    my $content;
    my $logfile    = "";
    my $logfiledir = "/tmp/genesistestlog";
    my $date = `date  +"%Y%m%d"`;
    chomp($date);
    if (!-e $logfiledir)
    {
        mkpath( $logfiledir );
    }
    $logfile = "genesis" . $date . ".log";
    if ($log_level == 0) {
        $content = "Fatal error:";
    } elsif ($log_level == 1) {
        $content = "Warning:";
    } elsif ($log_level == 2) {
        $content = "Notice:";
    }
    if (!open(LOGFILE, ">> $logfiledir/$logfile")) {
        return 1;
    }
    print LOGFILE "$date $$ $content $msg\n";
    close LOGFILE;

}
