#!/usr/bin/env perl
use File::Basename;
use File::Path;
use File::Copy;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

my $prinic = 'eth0'; #TODO be flexible on node primary nic
my $secnic = 'eth1'; #TODO be flexible on node primary nic
my $arch = `uname -m`;
chomp($arch);
my $profile;
my $osver;
GetOptions(
   #'a=s' => \$architecture,
   'p=s' => \$profile,
   'o=s' => \$osver,
);
unless ($osver and $profile) {
   print 'Usage: genimage -o $OSVER -p $PROFILE'."\n";
   exit 1;
}

my $installroot = "/install";
my $srcdir = "$installroot/$osver/$arch";
unless ( -d $srcdir."/repodata" ) {
   print "Need $installroot/$osver/$arch/repodata available from a system that has ran copycds on $osver $arch";
   exit 1;
}
my $pathtofiles=dirname($0);
my $yumconfig;
open($yumconfig,">","/tmp/genimage.$$.yum.conf");
print $yumconfig "[$osver-$arch]\nname=$osver-$arch\nbaseurl=file://$srcdir\ngpgpcheck=0\n";
close($yumconfig);
my $yumcmd = "yum -y -c /tmp/genimage.$$.yum.conf --installroot=$installroot/netboot/$osver/$arch/$profile/rootimg/ --disablerepo=* --enablerepo=$osver-$arch install ";
open($yumconfig,"<","$pathtofiles/$profile.pkglist");
while (<$yumconfig>) {
   chomp;
   $yumcmd .= $_ . " ";
}
$yumcmd =~ s/ $/\n/;
my $rc = system($yumcmd);
if ($rc) { 
   print "yum invocation failed\n";
   exit 1;
}
postscripts(); #run 'postscripts'
unlink "/tmp/genimage.$$.yum.conf";



sub postscripts { # TODO: customized postscripts
   generic_post();
   if (-d "$installroot/postscripts/hostkeys") {
      for my $key (<$installroot/postscripts/hostkeys/*key>) {
         copy ($key,"$installroot/netboot/$osver/$arch/$profile/rootimg/etc/ssh/");
      }
      chmod 0600,</$installroot/netboot/$osver/$arch/$profile/rootimg/etc/ssh/*key>;
   }
   if (-d "/$installroot/postscripts/.ssh") {
      mkpath("/$installroot/netboot/$osver/$arch/$profile/rootimg/root/.ssh");
      chmod(0700,"/$installroot/netboot/$osver/$arch/$profile/rootimg/root/.ssh/");
      for my $file (</$installroot/postscripts/.ssh/*>) {
         copy ($file,"/$installroot/netboot/$osver/$arch/$profile/rootimg/root/.ssh/");
      }
      chmod(0600,</$installroot/netboot/$osver/$arch/$profile/rootimg/root/.ssh/*>);
   }
}

sub generic_post { #This function is meant to leave the image in a state approximating a normal install
   my $cfgfile;
   unlink("$installroot/netboot/$osver/$arch/$profile/rootimg/dev/null");
   system("mknod $installroot/netboot/$osver/$arch/$profile/rootimg/dev/null c 1 3");
   open($cfgfile,">","$installroot/netboot/$osver/$arch/$profile/rootimg/etc/fstab");
   print $cfgfile "devpts  /dev/pts devpts   gid=5,mode=620 0 0\n";
   print $cfgfile "tmpfs   /dev/shm tmpfs    defaults       0 0\n";
   print $cfgfile "proc    /proc    proc     defaults       0 0\n";
   print $cfgfile "sysfs   /sys     sysfs    defaults       0 0\n";
   close($cfgfile);
   open($cfgfile,">","$installroot/netboot/$osver/$arch/$profile/rootimg/etc/sysconfig/network");
   print $cfgfile "NETWORKING=yes\n";
   close($cfgfile);
   open($cfgfile,">","$installroot/netboot/$osver/$arch/$profile/rootimg/etc/sysconfig/network-scripts/ifcfg-$prinic");
   print ("$installroot/netboot/$osver/$arch/$profile/rootimg/etc/sysconfig/network-scripts/ifcfg-$prinic");
   print $cfgfile "ONBOOT=yes\nBOOTPROTO=dhcp\nDEVICE=$prinic\n";
   close($cfgfile);
   open($cfgfile,">","$installroot/netboot/$osver/$arch/$profile/rootimg/etc/sysconfig/network-scripts/ifcfg-$secnic");
   print $cfgfile "ONBOOT=no\nBOOTPROTO=dhcp\nDEVICE=$secnic\n";
   close($cfgfile);
   link("$installroot/netboot/$osver/$arch/$profile/rootimg/sbin/init","$installroot/netboot/$osver/$arch/$profile/rootimg/init");
   rename(<$installroot/netboot/$osver/$arch/$profile/rootimg/boot/vmlinuz*>,"$installroot/netboot/$osver/$arch/$profile/kernel");
}
