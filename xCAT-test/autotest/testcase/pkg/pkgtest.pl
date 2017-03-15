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
my $osver;
my $log="/tmp/pkg.log";
my $needhelp  = 0;
my $setupenv = 0;
my $clearenv = 0;
my $setupenvinclude = 0;
my $removerpm = 0;
my $ospkg = 0;
my $osimg;
my $attr;
my $int;
if (
    !GetOptions("h|?"  => \$needhelp,
                "s" => \$setupenv,
                "c"=>\$clearenv,
                "i"=>\$setupenvinclude,
                "r"=>\$removerpm,
                "o"=>\$ospkg,
                "g=s"=>\$::OSIMG,
                "t=s"=>\$::ATTR,
                "v=s"=>\$::OSVERSION)
  )
{
    &usage;
    exit 1;
}

sub usage
{
    print "Usage:pkgtest.pl - Run xcat pkg test cases.\n";
    print "  pkgtest.pl [-?|-h]\n";
    print "  pkgtest.pl [-s] [-g osimage] [-t attribute] [-v os] set up package test environment \n";
    print "  pkgtest.pl [-i] [-g osimage] [-t attribute] [-v os] set up package test environment using include package list\n";
    print "  pkgtest.pl [-r] [-g osimage] [-t attribute] [-v os] remove package \n";
    print "  pkgtest.pl [-c] [-g osimage] [-t attribute] [-v os] clear package test environment \n";
    print "  pkgtest.pl [-o] [-g osimage] [-t attribute] [-v os] other package test  \n";
    print "\n";
    return;
}

sub getimgattr
{
    my @output = `lsdef -t osimage -o  $osimg -i $attr`;
    my $pkglistvalue;
    print " output is @output \n";   
    if($?){
        print "unkonw";
        return "Unknown";
       }
    if($? == 0){
        foreach my $output1 (@output){
             if($output1 =~ /$attr=(.*)/){
             print "output1 is $output1 ,attrs is  value is $1 \n";
             $pkglistvalue = $1 ;
             }
    }    }
    return $pkglistvalue;
}
 
sub setupenv
{  
      my $int = shift;
      if ($ospkg){
      `mkdir -p $int`;
      `cp -rf /xcat-core/* $int`;
       }else{
            `cat "$int" >> /tmp/pkgtest.bak`;
            }
       if (($osver =~ /ubuntu/)&&($ospkg ==0)){
           `echo "rpm" >>/tmp/pkgtest.bak `;
           }else{
           `echo "xCAT-test" >>/tmp/pkgtest.bak `; 
           }
}
sub clearenv
{
    my $int = shift; 
    if ($ospkg ==0){
    `rm -rf /tmp/pkgtest.* `;
    `rm -rf /install/pkgtest`;
     }else{
     `rm -rf /tmp/pkgtest.* `;
     `rm -rf $int`;
     }
}
 
sub setupenvinclude
{
    my $int = shift;
    if ($ospkg){
    `mkdir -p $int`;
    `cp -rf /xcat-core/* $int`;
     }else{
         ` cat $int >> /tmp/pkgtest.bak`;
          }
    if (($osver =~ /ubuntu/)&&($ospkg ==0)){
        `echo "rpm" >>/tmp/pkgtest.bak `;
        }else{
        `echo "xCAT-test" >> /tmp/pkgtest.includelist `;
        }
    `echo "#INCLUDE:/tmp/pkgtest.includelist#">>/tmp/pkgtest.bak `;
}
sub removerpm
{
    my $int = shift;
    if ($ospkg){
    `mkdir -p $int`;
    `cp -rf /xcat-core/* $int`;
        }else{
     `cat "$int" >> /tmp/pkgtest.bak`;
          }
    if (($osver =~ /ubuntu/)&&($ospkg ==0)){
    `echo "-rpm" >>/tmp/pkgtest.bak `;
    }elsif(($osver =~ /ubuntu/)&&($ospkg !=0)){
    `echo "-xcat-test">>/tmp/pkgtest.bak`;
    }else{
    `echo "-xCAT-test" >>/tmp/pkgtest.bak`;
    }
}
 
if  ($needhelp)
{
    &usage;
    exit 0;
}
if($::OSIMG)
{
    $osimg = $::OSIMG;
}
if($::ATTR)
{
    $attr = $::ATTR;
}
if($::OSVERSION)
{
   $osver = $::OSVERSION;
}
$int = getimgattr;
if ( ($setupenv) || ($setupenvinclude) ||($removerpm))
{
    if (! -f "/tmp/int"){
    `echo $int >> /tmp/int`;
    }else{
    print "please clear the pkg test environment first \n";
    exit 1;
    }
}
if ($setupenv)
{
   &setupenv($int);
}
if ($setupenvinclude)
{
    &setupenvinclude($int);
}
if ($removerpm)
{
    &removerpm($int);
}
if ($clearenv)
{   
    if (-f "/tmp/int"){
    my $int=`cat /tmp/int`;
    &clearenv($int);
    `rm -rf /tmp/int`;
    exit 0;
    }else{
    print "please set the pkg test environment first \n";
    exit 1;
    }
}
if (($setupenv) || ($setupenvinclude) ||($removerpm))
{
    `mkdir -p /install/pkgtest`;
    `cp -rf /xcat-core/* /install/pkgtest`;
    if (($osver !~ /ubuntu/)&&($ospkg ==0)){
    `chdef -t osimage -o $osimg pkgdir=/install/pkgtest pkglist=/tmp/pkgtest.bak `;
    }elsif (($osver !~ /ubuntu/)&&($ospkg !=0)){
    `chdef -t osimage -o $osimg otherpkglist=/tmp/pkgtest.bak`;
    }elsif(($osver =~ /ubuntu/)&&($ospkg !=0)){
    `chdef -t osimage -o  $osimg otherpkglist="/tmp/pkgtest.bak" otherpkgdir="http://xcat.org/files/xcat/repos/apt/2.12/xcat-core trusty main"`;
    }elsif(($osver =~ /ubuntu/)&&($ospkg ==0)){
    `chdef -t osimage -o $osimg pkglist=/tmp/pkgtest.bak`;
    }
}
if ($?)
{
     return 0;
}
