# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::windows;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use Storable qw(dclone);
use Sys::Syslog;
use File::Temp qw/tempdir/;
use xCAT::Table;
use xCAT::Utils;
use xCAT::SvrUtils;
use Socket;
use xCAT::MsgUtils;
use Data::Dumper;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use File::Path;
use File::Copy;

my @cpiopid;

sub handled_commands
{
    return {
            copycd    => "windows",
            mkinstall => "nodetype:os=(win.*|imagex)",
            mkwinshell => "windows",
            mkimage => "nodetype:os=imagex",
            };
}

sub process_request
{
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my $distname = undef;
    my $arch     = undef;
    my $path     = undef;
    my $installroot;
    $installroot = "/install";
    if ($request->{command}->[0] eq 'copycd')
    {
        return copycd($request, $callback, $doreq);
    }
    elsif ($request->{command}->[0] eq 'mkwinshell') {
        return winshell($request,$callback,$doreq);
    }
   elsif ($request->{command}->[0] eq 'mkinstall')
   {
       return mkinstall($request, $callback, $doreq);
   }
   elsif ($request->{command}->[0] eq 'mkimage') {
       return mkimage($request, $callback, $doreq);
   }
}

sub mkimage {
#NOTES ON IMAGING:
#-System must be sysprepped before capture, with /generalize
#-EMS settings appear to be lost in the process
#-If going to /audit, it's more useful than /oobe.  
#  audit complains about incorrect password on first boot, without any login attempt
#  audit causes a 'system preparation tool' dialog on first boot that I close
    my $installroot = "/install";
    my $request = shift;
    my $callback = shift;
    my $doreq = shift;
    my @nodes = @{$request->{node}};
    my $node;
    my $ostab = xCAT::Table->new('nodetype');
    my $oshash = $ostab->getNodesAttribs(\@nodes,['profile','arch']);
    my $shandle;
    unless (-d "$installroot/autoinst") {
        mkpath "$installroot/autoinst";
    }
    foreach $node (@nodes) {
        $ent = $oshash->{$node}->[0];
        unless ($ent->{arch} and $ent->{profile})
        {
            $callback->(
                        {
                         error => ["No profile defined in nodetype for $node"],
                         errorcode => [1]
                        }
                        );
            next;    #No profile
        }
        open($shandle,">","$installroot/autoinst/$node.cmd");
        print $shandle  "if exist c:\\xcatimgcred.txt move c:\\xcatimgcred.txt c:\\xcatimgcred.cmd\r\n";
        print $shandle  "if not exist c:\\xcatimgcred.cmd (\r\n";
        print $shandle  "  echo ERROR: C:\\xcatimgcred.txt was missing, can't authenticate to server to store image\r\n";
        print $shandle ")\r\n";
        print $shandle "call c:\\xcatimgcred.cmd\r\n";
        print $shandle "del c:\\xcatimgcred.cmd\r\n";
        print $shandle "x:\r\n";
        print $shandle "cd \\xcat\r\n";
        print $shandle "net use /delete i:\r\n";
        print $shandle 'net use i: %IMGDEST% %PASSWORD% /user:%USER%'."\r\n";
        print $shandle 'mkdir i:\images'."\r\n";
        print $shandle 'mkdir i:\images'."\\".$ent->{arch}."\r\n";
        print $shandle "imagex /capture c: i:\\images\\".$ent->{arch}."\\".$ent->{profile}.".wim ".$ent->{profile}."_".$ent->{arch}."\r\n";
        print $shandle "IF %PROCESSOR_ARCHITECTURE%==AMD64 GOTO x64\r\n";
        print $shandle "IF %PROCESSOR_ARCHITECTURE%==x64 GOTO x64\r\n";
        print $shandle "IF %PROCESSOR_ARCHITECTURE%==x86 GOTO x86\r\n";
        print $shandle ":x86\r\n";
        print $shandle "i:\\postscripts\\upflagx86 %XCATD% 3002 next\r\n";
        print $shandle "GOTO END\r\n";
        print $shandle ":x64\r\n";
        print $shandle "i:\\postscripts\\upflagx64 %XCATD% 3002 next\r\n";
        print $shandle ":END\r\n";
        print $shandle "pause\r\n";
        close($shandle);
        mkwinlinks($node,$ent);
    }
}

sub mkwinlinks {
    my $installroot = "/install"; # for now put this, as it breaks for imagex
    my $node = shift;
    my $ent = shift;
    foreach (getips($node)) {
        link "$installroot/autoinst/$node.cmd","$installroot/autoinst/$_.cmd";
    }
}

sub winshell {
    my $installroot = "/install";
    my $request = shift;
    my $script = "cmd";
    my @nodes    = @{$request->{node}};
    my $node;
    my $ostab = xCAT::Table->new('nodetype');
    my $oshash = $ostab->getNodesAttribs(\@nodes,['profile','arch']);
    foreach $node (@nodes) {
        open($shandle,">","$installroot/autoinst/$node.cmd");
        print $shandle $script;
        close $shandle;
        mkwinlinks($node,$oshash->{$node}->[0]);
        my $bptab = xCAT::Table->new('bootparams',-create=>1);
        $bptab->setNodeAttribs(
                                $node,
                                {
                                 kernel   => "Boot/pxeboot.0",
                                 initrd   => "",
                                 kcmdline => ""
                                }
                                );
    }
}

sub applyimagescript {
#Applying will annoy administrator with password change and sysprep tool 
#in current process
#EMS settings loss also bad..
#require/use setup.exe for 2k8 to alleviate this?
    my $arch=shift;
    my $profile=shift;
    my $applyscript=<<ENDAPPLY
    echo select disk 0 > x:/xcat/diskprep.prt
    echo clean >> x:/xcat/diskprep.prt
    echo create partition primary >> x:/xcat/diskprep.prt
    echo format quick >> x:/xcat/diskprep.prt
    echo active >> x:/xcat/diskprep.prt
    echo assign >> x:/xcat/diskprep.prt
    if exist i:/images/$arch/$profile.prt copy i:/images/$arch/$profile.prt x:/xcat/diskprep.prt
    diskpart /s x:/xcat/diskprep.prt
    x:/windows/system32/imagex /apply i:/images/$arch/$profile.wim 1 c:
    IF %PROCESSOR_ARCHITECTURE%==AMD64 GOTO x64
    IF %PROCESSOR_ARCHITECTURE%==x64 GOTO x64
    IF %PROCESSOR_ARCHITECTURE%==x86 GOTO x86
    :x86
    i:/postscripts/upflagx86 %XCATD% 3002 next
    GOTO END
    :x64
    i:/postscripts/upflagx64 %XCATD% 3002 next
    :END
ENDAPPLY
}
#Don't sweat os type as for mkimage it is always 'imagex' if it got here
sub mkinstall
{
    my $installroot;
    $installroot = "/install";
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my @nodes    = @{$request->{node}};
    my $tftpdir="/tftpboot";
    my $node;
    my $ostab = xCAT::Table->new('nodetype');
    my %doneimgs;
    my $bptab = xCAT::Table->new('bootparams',-create=>1);
    my $hmtab = xCAT::Table->new('nodehm');
    unless (-r "$tftpdir/Boot/pxeboot.0" ) {
       $callback->(
        {error => [ "The Windows netboot image is not created, consult documentation on how to add Windows deployment support to xCAT"],errorcode=>[1]
        });
       return;
    }
    require xCAT::Template;
    foreach $node (@nodes)
    {
        my $osinst;
        my $ent = $ostab->getNodeAttribs($node, ['profile', 'os', 'arch']);
        unless ($ent->{os} and $ent->{arch} and $ent->{profile})
        {
            $callback->(
                        {
                         error => ["No profile defined in nodetype for $node"],
                         errorcode => [1]
                        }
                        );
            next;    #No profile
        }
        my $os      = $ent->{os};
        my $arch    = $ent->{arch};
        my $profile = $ent->{profile};
        if ($os eq "imagex") {
                     unless ( -r "$installroot/images/$arch/$profile.wim" ) {
                        $callback->({error=>["$installroot/images/$profile.$arch.wim not found, run rimage on a node to capture first"],errorcode=>[1]});
                         next;
                     }
                     my $script=applyimagescript($arch,$profile);
                     my $shandle;
                     open($shandle,">","$installroot/autoinst/$node.cmd");
                     print $shandle $script;
                     close($shandle);
                     mkwinlinks($node,$ent);
                    if ($arch =~ /x86_64/)
                    {
                        $bptab->setNodeAttribs(
                                                $node,
                                                {
                                                 kernel   => "Boot/pxeboot.0",
                                                 initrd   => "",
                                                 kcmdline => ""
                                                }
                                                );
                   } elsif ($arch =~ /x86/) {
                       unless (-r "$tftpdir/Boot/pxeboot32.0") {
                           my $origpxe;
                           my $pxeboot;
                           open($origpxe,"<$tftpdir/Boot/pxeboot.0");
                           open($pxeboot,">$tftpdir/Boot/pxeboot32.0");
                           binmode($origpxe);
                           binmode($pxeboot);
                           my @origpxecontent = <$origpxe>;
                           foreach (@origpxecontent) {
                               s/bootmgr.exe/bootm32.exe/;
                               print $pxeboot $_;
                           }
                       }
                       unless (-r "$tftpdir/bootm32.exe") {
                           my $origmgr;
                           my $bootmgr;
                           open($origmgr,"<$tftpdir/bootmgr.exe");
                           open($bootmgr,">$tftpdir/bootm32.exe");
                           binmode($origmgr);
                           binmode($bootmgr);
                           foreach (@data) {
                               s/(\\.B.o.o.t.\\.B.)C(.)D/${1}3${2}2/; # 16 bit encoding... cheat
                               print $bootmgr $_;
                           }
                       }
                        $bptab->setNodeAttribs(
                                                $node,
                                                {
                                                 kernel   => "Boot/pxeboot32.0",
                                                 initrd   => "",
                                                 kcmdline => ""
                                                }
                                                );
                   }
                     next;
        } 

        my $tmplfile=xCAT::SvrUtils::get_tmpl_file_name("$installroot/custom/install/windows", $profile, $os, $arch);
        if (! $tmplfile) { $tmplfile=xCAT::SvrUtils::get_tmpl_file_name("$::XCATROOT/share/xcat/install/windows", $profile, $os, $arch); }
        unless ( -r "$tmplfile")
        {
            $callback->(
                      {
                       error =>
                         ["No unattended template exists for " . $ent->{profile}],
                       errorcode => [1]
                      }
                      );
            next;
        }

        #Call the Template class to do substitution to produce an unattend.xml file in the autoinst dir
        my $tmperr;
        if (-r "$tmplfile")
        {
            $tmperr =
              xCAT::Template->subvars(
                         $tmplfile,
                         "/install/autoinst/$node",
                         $node
                         );
        }
        
        if ($tmperr)
        {
            $callback->(
                        {
                         node => [
                                  {
                                   name      => [$node],
                                   error     => [$tmperr],
                                   errorcode => [1]
                                  }
                         ]
                        }
                        );
            next;
        }
	
		# create the node-specific post script DEPRECATED, don't do
		#mkpath "/install/postscripts/";
		#xCAT::Postage->writescript($node, "/install/postscripts/".$node, "install", $callback);
        if (! -r "/tftpboot/Boot/pxeboot.0" ) {
           $callback->(
            {error => [ "The Windows netboot image is not created, consult documentation on how to add Windows deployment support to xCAT"],errorcode=>[1]
            });
        } elsif (-r $installroot."/$os/$arch/sources/install.wim") {

            if ($arch =~ /x86/)
            {
                $bptab->setNodeAttribs(
                                        $node,
                                        {
                                         kernel   => "Boot/pxeboot.0",
                                         initrd   => "",
                                         kcmdline => ""
                                        }
                                        );
            }
        }
        else
        {
            $callback->(
                {
                 error => [
                     "Failed to detect copycd configured install source at /$installroot/$os/$arch/sources/install.wim"
                 ],
                 errorcode => [1]
                }
                );
        }
        my $shandle;
        my $sspeed;
        my $sport;
        if ($hmtab) {
            my $sent = $hmtab->getNodeAttribs($node,"serialport","serialspeed");
            if ($sent and defined($sent->{serialport}) and $sent->{serialspeed}) {
                $sport = $sent->{serialport};
                $sspeed = $sent->{serialspeed};
            }
        }


        open($shandle,">","$installroot/autoinst/$node.cmd");
        if ($sspeed) {
            $sport++;
            print $shandle "i:\\$os\\$arch\\setup /unattend:i:\\autoinst\\$node /emsport:COM$sport /emsbaudrate:$sspeed /noreboot\r\n";
        } else {
            print $shandle "i:\\$os\\$arch\\setup /unattend:i:\\autoinst\\$node /noreboot\r\n";
        }
        #print $shandle "i:\\postscripts\
        print $shandle "IF %PROCESSOR_ARCHITECTURE%==AMD64 GOTO x64\r\n";
        print $shandle "IF %PROCESSOR_ARCHITECTURE%==x64 GOTO x64\r\n";
        print $shandle "IF %PROCESSOR_ARCHITECTURE%==x86 GOTO x86\r\n";
        print $shandle ":x86\r\n";
        print $shandle "i:\\postscripts\\upflagx86 %XCATD% 3002 next\r\n";
        print $shandle "GOTO END\r\n";
        print $shandle ":x64\r\n";
        print $shandle "i:\\postscripts\\upflagx64 %XCATD% 3002 next\r\n";
        print $shandle ":END\r\n";
        close($shandle);
        foreach (getips($node)) {
            link "$installroot/autoinst/$node.cmd","$installroot/autoinst/$_.cmd";
            unlink "/tftpboot/Boot/BCD.$_";
            if ($arch =~ /64/) {
                link "/tftpboot/Boot/BCD.64","/tftpboot/Boot/BCD.$_";
            } else {
                link "/tftpboot/Boot/BCD.32","/tftpboot/Boot/BCD.$_";
            }
        }
    }
}
sub getips { #TODO: all the possible ip addresses
    my $node = shift;
    my $ipn = inet_aton($node); #would use proper method, but trying to deprecate this anyhow
    unless ($ipn) { return (); }
    #THIS CURRENTLY WOULD BREAK WITH IPV6 anyway...
    my $ip = inet_ntoa($ipn);
    return ($ip);
}



sub copycd
{
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my $distname = "";
    my $installroot;
    $installroot = "/install";
    my $sitetab = xCAT::Table->new('site');
    if ($sitetab)
    {
        (my $ref) = $sitetab->getAttribs({key => installdir}, value);
        if ($ref and $ref->{value})
        {
            $installroot = $ref->{value};
        }
    }

    @ARGV = @{$request->{arg}};
    GetOptions(
               'n=s' => \$distname,
               'a=s' => \$arch,
               'p=s' => \$path
               );
    unless ($path)
    {

        #this plugin needs $path...
        return;
    }
    if ($distname and $distname !~ /^win.*/)
    {

        #If they say to call it something other than win<something>, give up?
        return;
    }
    if (-d $path . "/sources/6.0.6000.16386_amd64" and -r $path . "/sources/install.wim")
    {
        $darch = x86_64;
        unless ($distname) {
            $distname = "win2k8";
        }
    }
    # add support for Win7
    if(-r $path . "/sources/idwbinfo.txt"){
	open(DBNAME, $path . "/sources/idwbinfo.txt");
	while(<DBNAME>){
		if(/BuildArch=amd64/){
			$darch = "x86_64";
		}
		if(/BuildBranch=win7_rtm/){
			$distname = "win7";
		}
	}
	close(DBNAME);
    }
    if (-r $path . "/sources/install_Windows Server 2008 R2 SERVERENTERPRISE.clg") {
        $distname = "win2k8r2";
    }
    unless ($distname)
    {
        return;
    }
    if ($darch)
    {
        unless ($arch)
        {
            $arch = $darch;
        }
        if ($arch and $arch ne $darch)
        {
            $callback->(
                     {
                      error =>
                        ["Requested Windows architecture $arch, but media is $darch"],
                        errorcode => [1]
                     }
                     );
            return;
        }
    }
    %{$request} = ();    #clear request we've got it.

    $callback->(
         {data => "Copying media to $installroot/$distname/$arch/$discnumber"});
    my $omask = umask 0022;
    mkpath("$installroot/$distname/$arch");
    umask $omask;
    my $rc;
    $SIG{INT} =  $SIG{TERM} = sub { 
       foreach(@cpiopid){
          kill 2, $_; 
       }
       if ($::CDMOUNTPATH) {
            chdir("/");
            system("umount $::CDMOUNTPATH");
       }
    };
    my $kid;
    chdir $path;
    my $numFiles = `find . -print | wc -l`;
    my $child = open($kid,"|-");
    unless (defined $child) {
      $callback->({error=>"Media copy operation fork failure"});
      return;
    }
    if ($child) {
       push @cpiopid,$child;
       my @finddata = `find .`;
       for (@finddata) {
          print $kid $_;
       }
       close($kid);
       $rc = $?;
    } else {
        my $c = "nice -n 20 cpio -vdump $installroot/$distname/$arch";
        my $k2 = open(PIPE, "$c 2>&1 |") ||
           $callback->({error => "Media copy operation fork failure"});
	push @cpiopid, $k2;
        my $copied = 0;
        my ($percent, $fout);
        while(<PIPE>){
          next if /^cpio:/;
          $percent = $copied / $numFiles;
          $fout = sprintf "%0.2f%%", $percent * 100;
          $callback->({sinfo => "$fout"});
          ++$copied;
        }
        exit;
    }
    chmod 0755, "$installroot/$distname/$arch";
    if ($rc != 0)
    {
        $callback->({error => "Media copy operation failed, status $rc"});
    }
    else
    {
        $callback->({data => "Media copy operation successful"});
	my @ret=xCAT::SvrUtils->update_tables_with_templates($distname, $arch);
        if ($ret[0] != 0) {
	    $callback->({data => "Error when updating the osimage tables: " . $ret[1]});
	}
   }
}

#sub get_tmpl_file_name {
#  my $base=shift;
#  my $profile=shift;
#  my $os=shift;
#  my $arch=shift;
#  if (-r   "$base/$profile.$os.$arch.tmpl") {
#    return "$base/$profile.$os.$arch.tmpl";
#  }
#  elsif (-r "$base/$profile.$arch.tmpl") {
#    return  "$base/$profile.$arch.tmpl";
#  }
#  elsif (-r "$base/$profile.$os.tmpl") {
#    return  "$base/$profile.$os.tmpl";
#  }
#  elsif (-r "$base/$profile.tmpl") {
#    return  "$base/$profile.tmpl";
#  }
#
#  return "";
#}
1;








