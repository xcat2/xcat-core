#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use Term::ANSIColor;
use Time::Local;
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
my $genesisdir="/opt/xcat/share/xcat/netboot/genesis/";
my $timesleep = 0;
my $runimgtest="/tmp/runme.sh";
if (
    !GetOptions("h|?"  => \$needhelp,
                "c"=>\$rungenesiscmd,
                "i"=>\$rungenesisimg,
                "t"=>\$timesleep,
                "s"=>\$shellmode)
)
{
    &usage;
    exit 1;
}
sub usage
{
    print "Usage:run genesis cases.\n";
    print "  genesistest.pl [-?|-h]\n";
    print "  genesistest.pl [-s]  set up genesis in shell mode \n";
    print "  genesistest.pl [-i]  runimg in genesis\n";
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
    `echo "#!/bin/bash">>$cmdtest`; 
    `echo "#This is test for genesis scripts">>$cmdtest`;
    `echo "echo \"test\" >> $cmdtest">>$cmdtest`;
    `chmod 777 $cmdtest`;
     if ($ARGV[0] =~ /ppc64/){
         `cp -rf $cmdtest "$genesisdir""ppc64"/fs/bin`;
         `mknb ppc64`;
          print "mknb ppc64\n";
      }else{
          `cp -rf $cmdtest "$genesisdir""$ARGV[0]"/fs/bin`;
          `mknb $ARGV[0]`;
           print "mkmn $ARGV[0]\n";
      }
}
sub rungenesisimg
{
    my $rc=0;
    runcmd("mkdir -p /install/my_image");
    `echo "#!/bin/bash">>$runimgtest`;
    `echo "#This is test for genesis scripts">>$runimgtest`;
    `echo "echo "test" >> /tmp/cmdtest" >>$runimgtest`;
    `chmod +x $runimgtest`;
    `cp $runimgtest  /install/my_image`;
    `cd /install/my_image ;tar -zcvf my_image.tgz  .`;
    ` nodeset $ARGV[0] "runimage=http://$ARGV[1]/install/my_image/my_image.tgz",shell`;
}
sub timesleep
{
    my @output = runcmd("ping $ARGV[0] -c 10");
    my $value = 0;
    print "output is $value ,@output\n";
    if ($::RUNCMD_RC){
        foreach $value (1 .. 60) {
        @output = runcmd("ping $ARGV[0] -c 10");
        last  if ($::RUNCMD_RC == 0);
        }
     }
    my @output1 = runcmd("xdsh $ARGV[0] date");
    if ($::RUNCMD_RC){
        foreach $value (1 .. 60) {
        @output1 = runcmd("xdsh $ARGV[0] date");
        last if ($::RUNCMD_RC == 0);
        }
    }
    if ($::RUNCMD_RC == 0){
        print "test ok\n";
     }
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
if ($?)
   {
    return 0;
   }


