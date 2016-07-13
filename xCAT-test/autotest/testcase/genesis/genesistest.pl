#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use Term::ANSIColor;
use Time::Local;
use File::Basename;
use File::Path;
use File::Copy;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";
my $needhelp  = 0;
my $rungenesiscmd = 0;
my $rungenesisimg = 0;
my $shellmode = 0;
my $cmdtest="/tmp/cmdtest";
my $timesleep = 0;
my $noderange = 0;
my $clearenv = 0;
my $arch = 0;
my $imgip ;
my $runimgtest="/tmp/imgtest";
my $testresult="/tmp/testresult";
my $genesisdir="/opt/xcat/share/xcat/netboot/genesis";
my $genesisfiledir="$genesisdir/$arch/fs/bin";

if (
    !GetOptions("h|?"  => \$::HELP,
                "d"=>\$rungenesiscmd,
                "g"=>\$rungenesisimg,
                "t"=>\$timesleep,
                "c"=>\$clearenv,
                "n=s"=>\$::NODE,
                "i=s"=>\$::IMGIP,
                "r=s"=>\$::ARCH)
)
{
    &usage;
    exit 1;
}
sub usage
{
    print "Usage:run genesis cases.\n";
    print "  genesistest.pl [-?|-h]\n";
    print "  genesistest.pl [-d] [-n node] [-r arch]  Test runcmd for genesis \n";
    print "  genesistest.pl [-g] [-n ndoe] [-i imgip] Test runimg for genesis\n";
    print "  genesistest.pl [-t] [-n node] Sleep for genesis test\n";
    print "  genesistest.pl [-c] [-n node][-r arch] Clear environment for genesis test\n";
    print "\n";
    return;
}
sub runcmd
{
    my ($cmd) = @_;
    my $rc = 0;
    $::RUNCMD_RC = 0;
    my $outref = [];
    @$outref = `$cmd 2>&1`;
    if ($?)
    {
        $rc = $? ;
        $rc = $rc >> 8;
        $::RUNCMD_RC = $rc;
    }
    chomp(@$outref);
    return @$outref;

}
sub rungenesiscmd
{
    open(TESTCMD, ">$cmdtest")
    or die "Can't open testscripts for writing: $!";
    print TESTCMD join("\n", "#!/bin/bash"), "\n";
    print TESTCMD join("\n", "#This is test for genesis scripts"), "\n";
    print TESTCMD join("\n", "echo \"testcmd\" >> $testresult"), "\n";
    close(TESTCMD);
    if ($arch =~ /ppc64/)
     {
         $arch = "ppc64";
     }
     $genesisfiledir="$genesisdir/$arch/fs/bin";
     copy("$cmdtest" ,"$genesisfiledir");
     chmod 0755, "$genesisfiledir/cmdtest";
     `mknb $arch`;
     print "mknb $arch\n";
}
sub rungenesisimg
{
    mkdir("/install/my_image");
    open(TESTIMG, ">$runimgtest")
    or die "Can't open testscripts for writing: $!";
    print TESTIMG join("\n", "#!/bin/bash"), "\n";
    print TESTIMG join("\n", "#This is test for genesis scripts"), "\n";
    print TESTIMG join("\n", "echo \"testimg\" >> $testresult"), "\n";
    close(TESTIMG);
    copy("$runimgtest" ,"/install/my_image/runme.sh" ) or die "Copy failed: $!";
    chmod 0755,"/install/my_image/runme.sh"; 
    `cd /install/my_image ;tar -zcvf my_image.tgz  .`;
    `nodeset $noderange "runimage=http://$imgip/install/my_image/my_image.tgz",shell`;
}
sub timesleep
{
    my @output = runcmd("ping $noderange -c 10");
    my $value = 0;
    print "output is $value ,@output\n";
    if ($::RUNCMD_RC){
        foreach $value (1 .. 60) {
        @output = runcmd("ping $noderange -c 10");
        last  if ($::RUNCMD_RC == 0);
        }
     }
    my @output1 = runcmd("xdsh $noderange date");
    if ($::RUNCMD_RC){
        foreach $value (1 .. 60) {
        @output1 = runcmd("xdsh $noderange -t 1 date");
        print "sleep $value\n";
        last if ($::RUNCMD_RC == 0);
        }
    }
    if ($::RUNCMD_RC == 0){
        print "test ok\n";
     }
}
sub clearenv
{
   if (-f "/tmp/imgtest"){
       unlink("/install/my_image/runme.sh");
       unlink("/install/my_image/my_image.tgz");
       unlink("$runimgtest");
       rmdir("/install/my_image");
       print "img del ok\n";
   }
   if (-f "/tmp/cmdtest"){
      if ($arch =~ /ppc64/)
      {
         $arch = "ppc64";
      }
      
      $genesisfiledir="$genesisdir/$arch/fs/bin";
      my $genesisfile = "$genesisfiledir/cmdtest";
      print "genesis file is $genesisfile\n";
      unlink("$genesisfile");
      unlink("$cmdtest");
     `mknb $arch`;
     print "mknb $arch\n";
   }
   `nodeset $noderange boot`; 
}
if ($::NODE)
{
    $noderange = $::NODE; 
}
if($::ARCH)
{
   $arch = $::ARCH;
}
if($::IMGIP)
{
   $imgip = $::IMGIP;
}
if ($::HELP) {
usage;
}
if ($rungenesiscmd)
{
    &rungenesiscmd;
}
if ($timesleep)
{
    &timesleep;
}
if($rungenesisimg)
   {
   &rungenesisimg;
   }
if($clearenv)
{
   &clearenv;
}
