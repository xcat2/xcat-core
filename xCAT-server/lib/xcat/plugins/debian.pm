# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::debian;

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
use xCAT::MsgUtils;
use Data::Dumper;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use File::Path;
use File::Copy;

use Socket;

#use strict;
my $useflowcontrol = "0";
my @cpiopid;

##############################################################################
#
# Author:
#
# Arif Ali (OCF plc) <mail@arif-ali.co.uk>
#
# Notes:
#
# This will not work with Ubuntu Desktop Edition, as all the packages are in
# a compressed image, and not readily available for creating images. So will
# only support Server ISOs.
#
#
#
# ChangeLog:
#
# 13 Aug 2010 - Initial release
#             - Implementation of only copycd
#             - Tested with 9.10 desktop and server ISOs
# 06 Oct 2010 - Added copycd support for Ubuntu 10.04 Server (LTS releases)
#             - Added support for mkinstall, install successfull for 10.04
#               -> used function from anaconda.pm
#               -> Need to cleanup so that it has no references to rhel
# 07 Oct 2010 - Added preprocess_request (direct copy from anaconda.pm)
#
##############################################################################

sub handled_commands
{
    return {
        copycd      => "debian",
        mknetboot   => "nodetype:os=(ubuntu.*)|(debian.*)",
        mkinstall   => "nodetype:os=(ubuntu.*)|(debian.*)",
        mkstatelite => "nodetype:os=(ubuntu.*)|(debian.*)",
    };
}

sub preprocess_request
{
    my $req      = shift;
    my $callback = shift;
    return [$req];    #calls are only made from pre-farmed out scenarios
    if ($req->{command}->[0] eq 'copycd')
    {                 #don't farm out copycd
        return [$req];
    }

    my $stab = xCAT::Table->new('site');
    my $sent;
    ($sent) = $stab->getAttribs({ key => 'sharedtftp' }, 'value');
    unless ($sent
        and defined($sent->{value})
        and ($sent->{value} eq "no" or $sent->{value} eq "NO" or $sent->{value} eq "0"))
    {

        #unless requesting no sharedtftp, don't make hierarchical call
        return [$req];
    }

    my %localnodehash;
    my %dispatchhash;
    my $nrtab = xCAT::Table->new('noderes');
    my $nrents = $nrtab->getNodesAttribs($req->{node}, [qw(tftpserver servicenode)]);
    foreach my $node (@{ $req->{node} })
    {
        my $nodeserver;
        my $tent = $nrents->{$node}->[0]; #$nrtab->getNodeAttribs($node, ['tftpserver']);
        if ($tent) { $nodeserver = $tent->{tftpserver} }
        unless ($tent and $tent->{tftpserver})
        {
            $tent = $nrents->{$node}->[0]; #$nrtab->getNodeAttribs($node, ['servicenode']);
            if ($tent) { $nodeserver = $tent->{servicenode} }
        }
        if ($nodeserver)
        {
            $dispatchhash{$nodeserver}->{$node} = 1;
        }
        else
        {
            $localnodehash{$node} = 1;
        }
    }
    my @requests;
    my $reqc = {%$req};
    $reqc->{node} = [ keys %localnodehash ];
    if (scalar(@{ $reqc->{node} })) { push @requests, $reqc }

    foreach my $dtarg (keys %dispatchhash)
    {    #iterate dispatch targets
        my $reqcopy = {%$req};    #deep copy
        $reqcopy->{'_xcatdest'} = $dtarg;
        $reqcopy->{node} = [ keys %{ $dispatchhash{$dtarg} } ];
        push @requests, $reqcopy;
    }
    return \@requests;
}

sub process_request
{
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my $distname = undef;
    my $arch     = undef;
    my $path     = undef;
    if ($::XCATSITEVALS{"useflowcontrol"}) { $useflowcontrol = $::XCATSITEVALS{"useflowcontrol"}; }
    if ($request->{command}->[0] eq 'copycd')
    {
        return copycd($request, $callback, $doreq);
    }
    elsif ($request->{command}->[0] eq 'mkinstall')
    {
        return mkinstall($request, $callback, $doreq);
    }
    elsif ($request->{command}->[0] eq 'mknetboot' or
        $request->{command}->[0] eq 'mkstatelite')
    {
        return mknetboot($request, $callback, $doreq);
    }
}

# Check whether the dracut is supported by this os
sub using_dracut
{
    my $os = shift;
    if ($os =~ /ubuntu(\d+)/) {
        if ($1 >= 12.04) {
            return 1;
        }
    } elsif ($os =~ /debian(\d+)/) {
        if ($1 >= 6.0) {
            return 1;
        }
    }

    return 0;
}

sub copyAndAddCustomizations {
    my $source = shift;
    my $dest   = shift;

    #first, it's simple, we copy...
    copy($source, $dest);

    #next, we apply xCAT customizations to enhance debian installer..
    chdir("$::XCATROOT/share/xcat/install/debian/initoverlay");
    system("find . |cpio -o -H newc | gzip -c - -9 >> $dest");
}

sub copycd
{
    my $request     = shift;
    my $callback    = shift;
    my $doreq       = shift;
    my $distname    = "";
    my $detdistname = "";
    my $installroot;
    my $arch;
    my $path;
    $installroot = "/install";
    my $sitetab = xCAT::Table->new('site');

    if ($sitetab)
    {
        (my $ref) = $sitetab->getAttribs({ key => 'installdir' }, 'value');

        #print Dumper($ref);
        if ($ref and $ref->{value})
        {
            $installroot = $ref->{value};
        }
    }

    @ARGV = @{ $request->{arg} };
    GetOptions(
        'n=s' => \$distname,
        'a=s' => \$arch,
        'p=s' => \$copypath,
        'm=s' => \$path,
        'i'   => \$inspection,
        'o'   => \$noosimage,
        'w'   => \$nonoverwrite,
    );
    unless ($path)
    {

        #this plugin needs $path...
        return;
    }
    if ($distname
        and $distname !~ /^debian/i
        and $distname !~ /^ubuntu/i)
    {

        #If they say to call it something unidentifiable, give up?
        return;
    }

    unless (-r $path . "/.disk/info")
    {
        #xCAT::MsgUtils->message("S","The CD doesn't look like a Debian CD, exiting...");
        return;
    }

    if ($copypath || $nonoverwrite)
    {
        $callback->({ info => ["copycds on Ubuntu/Debian does not support -p or -w option."] });
        return;
    }

    my $dinfo;
    open($dinfo, $path . "/.disk/info");
    my $line = <$dinfo>;
    chomp($line);
    my @line2 = split(/ /, $line);
    close($dinfo);

    my $isnetinst = 0;
    my $prod      = $line2[0];    # The product should be the first word
    my $ver       = $line2[1];    # The version should be the second word
    my $darch     = $line2[6];    # The architecture should be the seventh word

    # Check to see if $darch is defined
    unless ($darch)
    {
        return;
    }

    my $discno = '';
    if ($prod eq "Debian")
    {
        # Debian specific, the arch and version are in different places
        $darch  = $line2[6];
        $ver    = $line2[2];
        $discno = $line2[8];

        # For the purpose of copying the netinst cd before the main one
        # So that we have the netboot images
        $isnetinst = 1 if ($line2[7] eq "NETINST");

        if (!$distname) {
            $distname = "debian" . $ver;
        }
        $detdistname = "debian" . $ver;
    }
    elsif ($prod eq "Ubuntu" or $prod eq "Ubuntu-Server")
    {
        # to cover for LTS releases
        $darch = $line2[7] if ($line2[2] eq "LTS");

        if (!$distname) {
            $distname = "ubuntu" . $ver;
        }
        $detdistname = "ubuntu" . $ver;
        $discno = `cat $path/README.diskdefines | grep 'DISKNUM ' | awk '{print \$3}'`;
    }
    else
    {
        return;
    }

    # So that I can use amd64 below
    my $debarch = $darch;

    if ($darch and $darch =~ /i.86/)
    {
        $darch = "x86";
    }
    elsif ($darch and $darch =~ /ppc64el/)
    {
        $darch = "ppc64el";
    }
    elsif ($darch and ($darch =~ /ppc/ or $darch =~ /powerpc/))
    {
        $darch = "ppc64";
    }
    elsif ($darch and $darch =~ /amd64/)
    {
        $darch = "x86_64";
    }

    if ($darch)
    {
        unless ($arch)
        {
            $arch = $darch;
        }
        if ($arch and ($arch ne $darch) and ($arch ne $debarch))
        {
            $callback->(
                {
                    error =>
                      ["Requested Debian architecture $arch, but media is $darch"],
                    errorcode => [1]
                }
            );
            return;
        }
    }
    if ($inspection) {
        $callback->(
            {
                info =>
"DISTNAME:$distname\n" . "ARCH:$debarch\n" . "DISCNO:$discno\n"
            }
        );
        return;
    }
    %{$request} = ();    #clear request we've got it.

    $callback->(
        { data => "Copying media to $installroot/$distname/$arch" });
    my $omask = umask 0022;
    mkpath("$installroot/$distname/$arch");
    mkpath("$installroot/$distname/$arch/install/netboot") if ($isnetinst);
    umask $omask;
    my $rc;
    $SIG{INT} = $SIG{TERM} = sub {
        foreach (@cpiopid) {
            kill 2, $_;
        }
        if ($path) {
            chdir("/");
            system("umount $path");
        }
    };
    my $kid;
    chdir $path;
    my $numFiles = `find . -print | wc -l`;
    my $child = open($kid, "|-");
    unless (defined $child) {
        $callback->({ error => "Media copy operation fork failure" });
        return;
    }
    if ($child) {
        push @cpiopid, $child;
        my @finddata = `find .`;
        for (@finddata) {
            print $kid $_;
        }
        close($kid);
        $rc = $?;
    } else {
        my $c = "nice -n 20 cpio -vdump $installroot/$distname/$arch";
        my $k2 = open(PIPE, "$c 2>&1 |") ||
          $callback->({ error => "Media copy operation fork failure" });
        push @cpiopid, $k2;
        my $copied = 0;
        my ($percent, $fout);
        while (<PIPE>) {
            next if /^cpio:/;
            $percent = $copied / $numFiles;
            $fout = sprintf "%0.2f%%", $percent * 100;
            $callback->({ sinfo => "$fout" });
            ++$copied;
        }
        exit;
    }

    #  system(
    #    "cd $path; find . | nice -n 20 cpio -dump $installroot/$distname/$arch/"
    #    );
    chmod 0755, "$installroot/$distname/$arch";

    # Need to do this otherwise there will be warning about corrupt Packages file
    # when installing a system

    # Grabs the distribution codename
    my @line = split(" ", `ls -lh $installroot/$distname/$arch/dists/ | grep dr`);
    my $dist = $line[ @line - 1 ];

    # touches the Packages file so that deb packaging works
    system("touch $installroot/$distname/$arch/dists/$dist/restricted/binary-$debarch/Packages");

    # removes the links unstable and testing, otherwise the repository does not work for debian
    system("rm -f $installroot/$distname/$arch/dists/unstable");
    system("rm -f $installroot/$distname/$arch/dists/testing");

    # copies the netboot files for debian
    if ($isnetinst)
    {
        system("cp install.*/initrd.gz $installroot/$distname/$arch/install/netboot/.");
        system("cp install.*/vmlinuz $installroot/$distname/$arch/install/netboot/.");
    }

    if ($rc != 0)
    {
        $callback->({ error => "Media copy operation failed, status $rc" });
    }
    else
    {
        my $osdistoname = $distname . "-" . $arch;
        my $temppath    = "$installroot/$distname/$arch";
        my @ret = xCAT::SvrUtils->update_osdistro_table($distname, $arch, $temppath, $osdistroname);
        if ($ret[0] != 0) {
            $callback->({ data => "Error when updating the osdistro tables: " . $ret[1] });
        }

        $callback->({ data => "Media copy operation successful" });
        unless ($noosimage) {
            my @ret = xCAT::SvrUtils->update_tables_with_templates($distname, $arch, $temppath, $osdistroname);
            if ($ret[0] != 0) {
                $callback->({ data => "Error when updating the osimage tables: " . $ret[1] });
            }
            my @ret = xCAT::SvrUtils->update_tables_with_diskless_image($distname, $arch, undef, "netboot", $temppath, $osdistroname);
            if ($ret[0] != 0) {
                $callback->({ data => "Error when updating the osimage tables for stateless: " . $ret[1] });
            }
        }
    }
}

sub mkinstall {
    xCAT::MsgUtils->message("S", "Doing debian mkinstall");
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my @nodes    = @{ $request->{node} };
    my $bootparams = ${$request->{bootparams}};
    my $sitetab  = xCAT::Table->new('site');
    my $linuximagetab;
    my $osimagetab;
    my %img_hash = ();

    #>>>>>>>used for trace log start>>>>>>>
    my @args = ();
    my %opt;
    if (ref($request->{arg})) {
        @args = @{ $request->{arg} };
    } else {
        @args = ($request->{arg});
    }
    @ARGV = @args;
    GetOptions('V' => \$opt{V});
    my $verbose_on_off = 0;
    if ($opt{V}) { $verbose_on_off = 1; }

    #>>>>>>>used for trace log end>>>>>>>

    my $installroot;
    $installroot = "/install";
    if ($sitetab)
    {
        (my $ref) = $sitetab->getAttribs({ key => 'installdir' }, 'value');
        if ($ref and $ref->{value})
        {
            $installroot = $ref->{value};
        }
    }

    xCAT::MsgUtils->trace($verbose_on_off, "d", "debian->mkinstall: installroot=$installroot");

    # Check whether the default getinstdisk script exist, if so, copy it into /install/autoinst/
    if (-r "$::XCATROOT/share/xcat/install/scripts/getinstdisk") {
        if (!(-e "$installroot/autoinst")) {
            mkdir("$installroot/autoinst");
        }
        copy("$::XCATROOT/share/xcat/install/scripts/getinstdisk", "$installroot/autoinst/getinstdisk");
    }

    my $node;
    my $ostab = xCAT::Table->new('nodetype');
    my %donetftp;
    my $restab = xCAT::Table->new('noderes');
    my $hmtab  = xCAT::Table->new('nodehm');
    my $mactab = xCAT::Table->new('mac');
    my %osents = %{ $ostab->getNodesAttribs(\@nodes, [ 'profile', 'os', 'arch', 'provmethod' ]) };
    my %rents =
      %{ $restab->getNodesAttribs(\@nodes,
            [ 'xcatmaster', 'nfsserver', 'primarynic', 'installnic', 'tftpserver' ]) };
    my %hents =
      %{ $hmtab->getNodesAttribs(\@nodes,
            [ 'serialport', 'serialspeed', 'serialflow' ]) };
    my %macents = %{ $mactab->getNodesAttribs(\@nodes, ['mac']) };

    require xCAT::Template;


    foreach $node (@nodes)
    {
        my $os;
        my $arch;
        my $darch;
        my $profile;
        my $tmplfile;
        my $partitionfile;
        my $pkgdir;
        my $pkgdirval;
        my @mirrors;
        my $pkglistfile;
        my $imagename;    # set it if running of 'nodeset osimage=xxx'
        my $platform;
        my %tmpl_hash;

        my $ient = $rents{$node}->[0];
        if ($ient and $ient->{xcatmaster}) {
            $tmpl_hash{"xcatmaster"} = $ient->{xcatmaster};
        }
        if ($ient and $ient->{tftpserver}) {
            $tmpl_hash{"tftpserver"} = $ient->{tftpserver};
        }

        my $osinst;
        my $ent = $osents{$node}->[0]; #$ostab->getNodeAttribs($node, ['profile', 'os', 'arch']);
        if ($ent and $ent->{provmethod} and ($ent->{provmethod} ne 'install') and ($ent->{provmethod} ne 'netboot') and ($ent->{provmethod} ne 'statelite')) {
            $imagename = $ent->{provmethod};
            if (!exists($img_hash{$imagename})) {
                if (!$osimagetab) {
                    $osimagetab = xCAT::Table->new('osimage', -create => 1);
                }
                (my $ref) = $osimagetab->getAttribs({ imagename => $imagename }, 'osvers', 'osarch', 'profile', 'provmethod');
                if ($ref) {
                    $img_hash{$imagename}->{osver}      = $ref->{'osvers'};
                    $img_hash{$imagename}->{osarch}     = $ref->{'osarch'};
                    $img_hash{$imagename}->{profile}    = $ref->{'profile'};
                    $img_hash{$imagename}->{provmethod} = $ref->{'provmethod'};
                    if (!$linuximagetab) {
                        $linuximagetab = xCAT::Table->new('linuximage', -create => 1);
                    }
                    (my $ref1) = $linuximagetab->getAttribs({ imagename => $imagename }, 'template', 'pkgdir', 'pkglist', 'partitionfile');
                    if ($ref1) {
                        if ($ref1->{'template'}) {
                            $img_hash{$imagename}->{template} = $ref1->{'template'};
                        }
                        if ($ref1->{'pkgdir'}) {
                            $img_hash{$imagename}->{pkgdir} = $ref1->{'pkgdir'};
                        }
                        if ($ref1->{'pkglist'}) {
                            $img_hash{$imagename}->{pkglist} = $ref1->{'pkglist'};
                        }
                        if ($ref1->{'partitionfile'}) {
                            $img_hash{$imagename}->{partitionfile} = $ref1->{'partitionfile'};
                        }
                    }

                    # if the install template wasn't found, then lets look for it in the default locations.
                    unless ($img_hash{$imagename}->{template}) {
                        my $pltfrm = getplatform($ref->{'osvers'});
                        my $tmplfile = xCAT::SvrUtils::get_tmpl_file_name("$installroot/custom/install/$pltfrm",
                            $ref->{'profile'}, $ref->{'osvers'}, $ref->{'osarch'}, $ref->{'osvers'});
                        if (!$tmplfile) {
                            $tmplfile = xCAT::SvrUtils::get_tmpl_file_name("$::XCATROOT/share/xcat/install/$pltfrm",
                                $ref->{'profile'}, $ref->{'osvers'}, $ref->{'osarch'}, $ref->{'osvers'});
                        }

                        # if we managed to find it, put it in the hash:
                        if ($tmplfile) {
                            $img_hash{$imagename}->{template} = $tmplfile;
                        }
                    }

                    #if the install pkglist wasn't found, then lets look for it in the default locations
                    unless ($img_hash{$imagename}->{pkglist}) {
                        my $pltfrm = getplatform($ref->{'osvers'});
                        my $pkglistfile = xCAT::SvrUtils::get_pkglist_file_name("$installroot/custom/install/$pltfrm",
                            $ref->{'profile'}, $ref->{'osvers'}, $ref->{'osarch'}, $ref->{'osvers'});
                        if (!$pkglistfile) {
                            $pkglistfile = xCAT::SvrUtils::get_pkglist_file_name("$::XCATROOT/share/xcat/install/$pltfrm",
                                $ref->{'profile'}, $ref->{'osvers'}, $ref->{'osarch'}, $ref->{'osvers'});
                        }

                        # if we managed to find it, put it in the hash:
                        if ($pkglistfile) {
                            $img_hash{$imagename}->{pkglist} = $pkglistfile;
                        }
                    }
                }
                else {
                    xCAT::MsgUtils->report_node_error($callback, $node, "The OS image '$imagename' for node does not exist");
                    next;
                }
            }

            my $ph = $img_hash{$imagename};
            $os            = $ph->{osver};
            $arch          = $ph->{osarch};
            $profile       = $ph->{profile};
            $partitionfile = $ph->{partitionfile};
            $platform      = xCAT_plugin::debian::getplatform($os);

            $tmplfile  = $ph->{template};
            $pkgdirval = $ph->{pkgdir};
            my @pkgdirlist = split(/,/, $pkgdirval);
            foreach (@pkgdirlist) {
                if ($_ =~ /^http|ssh/) {
                    push @mirrors, $_;
                } else {

                    # If multiple pkgdirs are provided,  The first path in the value of osimage.pkgdir
                    # must be the OS base pkg dir path, so use the first path as pkgdir
                    if (!$pkgdir) {
                        $pkgdir = $_;
                    }
                }
            }

            if (!$pkgdir) {
                $pkgdir = "$installroot/$os/$arch";
            }
            $pkglistfile = $ph->{pkglist};

            xCAT::MsgUtils->trace($verbose_on_off, "d", "debian->mkinstall: imagename=$imagename pkgdir=$pkgdir pkglistfile=$pkglistfile tmplfile=$tmplfile");
        }
        else {
            # This is deprecated mode to define node's provmethod, not supported now.
            xCAT::MsgUtils->report_node_error($callback, $node, "OS image name must be specified in nodetype.provmethod");
            next;

            $os       = $ent->{os};
            $arch     = $ent->{arch};
            $profile  = $ent->{profile};
            $platform = xCAT_plugin::debian::getplatform($os);
            my $genos = $os;
            $genos =~ s/\..*//;

            $tmplfile = xCAT::SvrUtils::get_tmpl_file_name("$installroot/custom/install/$platform", $profile, $os, $arch, $genos);
            if (!$tmplfile) {
                $tmplfile = xCAT::SvrUtils::get_tmpl_file_name("$::XCATROOT/share/xcat/install/$platform", $profile, $os, $arch, $genos);
            }

            $pkglistfile = xCAT::SvrUtils::get_pkglist_file_name("$installroot/custom/install/$platform", $profile, $os, $arch, $genos);
            if (!$pkglistfile) {
                $pkglistfile = xCAT::SvrUtils::get_pkglist_file_name("$::XCATROOT/share/xcat/install/$platform", $profile, $os, $arch, $genos);
            }

            $pkgdir = "$installroot/$os/$arch";
            xCAT::MsgUtils->trace($verbose_on_off, "d", "debian->mkinstall: pkgdir=$pkgdir pkglistfile=$pkglistfile tmplfile=$tmplfile");
        }

        if ($arch eq "x86_64") {
            $darch = "amd64";
        }
        elsif ($arch eq "x86") {
            $darch = "i386";
        }
        else {
            if ($arch ne "ppc64le" and $arch ne "ppc64el") {
                xCAT::MsgUtils->message("S", "debian.pm: Unknown arch ($arch)");
            }
            $darch = $arch;
        }

        my @missingparms;
        unless ($os) {
            if ($imagename) {
                push @missingparms, "osimage.osvers";
            }
            else {
                push @missingparms, "nodetype.os";
            }
        }

        unless ($arch) {
            if ($imagename) {
                push @missingparms, "osimage.osarch";
            }
            else {
                push @missingparms, "nodetype.arch";
            }
        }
        unless ($profile) {
            if ($imagename) {
                push @missingparms, "osimage.profile";
            }
            else {
                push @missingparms, "nodetype.profile";
            }
        }

        unless ($os and $arch and $profile) {
            xCAT::MsgUtils->report_node_error($callback, $node, "Missing " . join(',', @missingparms) . " for $node");
            next;    # No profile
        }

        unless (-r "$tmplfile") {
            xCAT::MsgUtils->report_node_error($callback, $node, "No $platform preseed template exists for " . $profile);
            next;
        }

        #Call the Template class to do substitution to produce a preseed file in the autoinst dir
        my $tmperr;
        my $preerr;
        my $posterr;
        if ($imagename) {
            $tmperr = "Unable to find template file: $tmplfile";
        } else {
            $tmperr = "Unable to find template in $installroot/custom/install/$platform or $::XCATROOT/share/xcat/install/$platform (for $profile/$os/$arch combination)";
        }
        if (-r "$tmplfile") {
            $tmperr =
              xCAT::Template->subvars($tmplfile,
                "$installroot/autoinst/" . $node,
                $node,
                $pkglistfile,
                $pkgdir,
                $platform,
                $partitionfile,
                \%tmpl_hash
              );
        }

        my $prescript = "$::XCATROOT/share/xcat/install/scripts/pre.$platform";
        my $postscript = "$::XCATROOT/share/xcat/install/scripts/post.$platform";

        # for powerkvm VM ubuntu LE#
        if ($arch =~ /ppc64/i and $platform eq "ubuntu") {
            $prescript = "$::XCATROOT/share/xcat/install/scripts/pre.$platform.ppc64";
        }


        if (-r "$prescript") {
            $preerr = xCAT::Template->subvars($prescript,
                "$installroot/autoinst/" . $node . ".pre",
                $node,
                "",
                "",
                "",
                $partitionfile,
                \%tmpl_hash
            );
        }

        if (-r "$postscript") {
            $posterr = xCAT::Template->subvars($postscript,
                "$installroot/autoinst/" . $node . ".post",
                $node,
                "",
                "",
                "",
                "",
                \%tmpl_hash
            );
        }

        my $errtmp;

        if ($errtmp = $tmperr or $errtmp = $preerr or $errtmp = $posterr) {
            xCAT::MsgUtils->report_node_error($callback, $node, $errtmp);
            next;
        }

        if ($arch =~ /ppc64/i and !(-e "$pkgdir/install/netboot/initrd.gz") and
            !(-e "$pkgdir/install/netboot/ubuntu-installer/$darch/initrd.gz")) {
            xCAT::MsgUtils->report_node_error($callback, $node, 
                "The network boot initrd.gz is not found in $pkgdir/install/netboot.  This is provided by Ubuntu, please download and retry."
                );
            next;
        }
        my $tftpdir = "/tftpboot";

        # create the node-specific post scripts
        #mkpath "$installroot/postscripts/";
        my $kernpath;
        my $initrdpath;
        my $maxmem;

        if (
            (
                ($arch =~ /x86/ and
                    (
                        (-r "$pkgdir/install/hwe-netboot/ubuntu-installer/$darch/linux"
                            and $kernpath = "$pkgdir/hwe-install/netboot/ubuntu-installer/$darch/linux"
                            and -r "$pkgdir/install/hwe-netboot/ubuntu-installer/$darch/initrd.gz"
                            and $initrdpath = "$pkgdir/install/hwe-netboot/ubuntu-installer/$darch/initrd.gz"
                        ) or
                        (-r "$pkgdir/install/netboot/ubuntu-installer/$darch/linux"
                            and $kernpath = "$pkgdir/install/netboot/ubuntu-installer/$darch/linux"
                            and -r "$pkgdir/install/netboot/ubuntu-installer/$darch/initrd.gz"
                            and $initrdpath = "$pkgdir/install/netboot/ubuntu-installer/$darch/initrd.gz"
                        ) or
                        (-r "$pkgdir/install/netboot/vmlinuz"
                            and $kernpath = "$pkgdir/install/netboot/vmlinuz"
                            and -r "$pkgdir/install/netboot/initrd.gz"
                            and $initrdpath = "$pkgdir/install/netboot/initrd.gz"
                        )
                    )
                ) or (
                    $arch =~ /ppc64/i and (
                        (-r "$pkgdir/install/netboot/ubuntu-installer/$darch/vmlinux"
                            and $kernpath = "$pkgdir/install/netboot/ubuntu-installer/$darch/vmlinux"
                            and -r "$pkgdir/install/netboot/ubuntu-installer/$darch/initrd.gz"
                            and $initrdpath = "$pkgdir/install/netboot/ubuntu-installer/$darch/initrd.gz"
                        ) or
                        (-r "$pkgdir/install/vmlinux"
                            and $kernpath = "$pkgdir/install/vmlinux"
                            and -r "$pkgdir/install/netboot/initrd.gz"
                            and $initrdpath = "$pkgdir/install/netboot/initrd.gz"
                        )
                    )
                )
            )
          ) {
            #TODO: driver slipstream, targetted for network.

            # Copy the install resource to /tftpboot and check to only copy once
            my $docopy = 0;
            my $tftppath;
            my $rtftppath;    # the relative tftp path without /tftpboot/
            if ($imagename) {
                $tftppath  = "$tftpdir/xcat/osimage/$imagename";
                $rtftppath = "xcat/osimage/$imagename";
                unless ($donetftp{$imagename}) {
                    $docopy = 1;
                    $donetftp{$imagename} = 1;
                }
            } else {
                $tftppath  = "/$tftpdir/xcat/$os/$arch/$profile";
                $rtftppath = "xcat/$os/$arch/$profile";
                unless ($donetftp{"$os|$arch"}) {
                    $docopy = 1;
                    $donetftp{"$os|$arch"} = 1;
                }
            }

            if ($docopy) {
                mkpath("$tftppath");
                copy($kernpath, "$tftppath/vmlinuz");
                copyAndAddCustomizations($initrdpath, "$tftppath/initrd.img");
            }

            # We have a shot...
            my $ent    = $rents{$node}->[0];
            my $sent   = $hents{$node}->[0];
            my $macent = $macents{$node}->[0];
            my $instserver;
            if ($ent and $ent->{xcatmaster}) {
                $instserver = $ent->{xcatmaster};
            }
            else {
                $instserver = '!myipfn!';
            }

            if ($ent and $ent->{nfsserver}) {
                $instserver = $ent->{nfsserver};
            }

            my $kcmdline = "nofb utf8 auto url=http://" . $instserver . "/install/autoinst/" . $node;

            $kcmdline .= " xcatd=" . $instserver;
            $kcmdline .= " mirror/http/hostname=" . $instserver;
            if ($maxmem) {
                $kcmdline .= " mem=$maxmem";
            }

            # parse Mac table to get one mac address in case there are multiples.
            my $mac;
            if ($macent->{mac}) {
                $mac = xCAT::Utils->parseMacTabEntry($macent->{mac}, $node);
            }

            my $net_params = xCAT::NetworkUtils->gen_net_boot_params($ent->{installnic}, $ent->{primarynic}, $mac);
            if (exists($net_params->{nicname})) {
                $kcmdline .= " netcfg/choose_interface=" . $net_params->{nicname};
            } elsif (exists($net_params->{mac})) {
                $kcmdline .= " netcfg/choose_interface=" . $net_params->{mac};
            }

            #TODO: dd=<url> for driver disks
            if (defined($sent->{serialport})) {
                unless ($sent->{serialspeed}) {
                    xCAT::MsgUtils->report_node_error($callback, $node, "serialport defined, but no serialspeed for this node in nodehm table");
                    next;
                }
                if ($arch =~ /ppc64/i) {
                    $kcmdline .= " console=tty0 console=hvc" . $sent->{serialport} . "," . $sent->{serialspeed};
                } else {
                    $kcmdline .= " console=tty0 console=ttyS" . $sent->{serialport} . "," . $sent->{serialspeed};
                }
                if ($sent->{serialflow} =~ /(hard|cts|ctsrts)/) {
                    $kcmdline .= "n8r";
                }
            } else {
                $callback->({ warning => ["rcons may not work since no serialport is specified for $node"], });
            }

            # need to add these in, otherwise aptitude will ask questions
            $kcmdline .= " locale=en_US";

            #$kcmdline .= " netcfg/wireless_wep= netcfg/get_hostname= netcfg/get_domain=";

            # default answers as much as possible, we don't want any interactiveness :)
            $kcmdline .= " priority=critical";

            # Automatically detect all HDD
            # $kcmdline .= " all-generic-ide irqpoll";

            # by default do text based install
            # $kcmdline .= " DEBIAN_FRONTEND=text";

            # Maybe useful for debugging purposes
            #
            # $kcmdline .= " BOOT_DEBUG=3";
            # $kcmdline .= " DEBCONF_DEBUG=5";

            # I don't need the timeout for ubuntu, but for debian there is a problem with getting dhcp in a timely manner
            # safer way to set hostname, avoid problems with nameservers
            $kcmdline .= " hostname=" . $node;

            #from 12.10, the live install changed, so add the live-installer
            if (-r "$pkgdir/install/filesystem.squashfs") {
                $kcmdline .= " live-installer/net-image=http://${instserver}${pkgdir}/install/filesystem.squashfs";
            }

            xCAT::MsgUtils->trace($verbose_on_off, "d", "debian->mkinstall: kcmdline=$kcmdline kernal=$rtftppath/vmlinuz initrd=$rtftppath/initrd.img");
            $bootparams->{$node}->[0]->{kernel} = "$rtftppath/vmlinuz";
            $bootparams->{$node}->[0]->{initrd} = "$rtftppath/initrd.img";
            $bootparams->{$node}->[0]->{kcmdline} = $kcmdline;
        }
        else {
            xCAT::MsgUtils->report_node_error($callback, $node, "Install image not found in $installroot/$os/$arch");
            next;
        }
    }# end foreach node
}

sub mknetboot
{
    my $xenstyle  = 0;
    my $req       = shift;
    my $callback  = shift;
    my $doreq     = shift;
    my $statelite = 0;
    if ($req->{command}->[0] =~ 'mkstatelite') {
        $statelite = "true";
    }
    my $bootparams = ${$req->{bootparams}};
    my $tftpdir = "/tftpboot";
    my $nodes   = @{ $req->{node} };
    my @args    = @{ $req->{arg} };
    my @nodes   = @{ $req->{node} };
    my $ostab   = xCAT::Table->new('nodetype');
    my $sitetab = xCAT::Table->new('site');
    my $linuximagetab;
    my $osimagetab;
    my %img_hash = ();
    my $installroot;
    $installroot = "/install";
    my $xcatdport  = "3001";
    my $xcatiport  = "3002";
    my $nodestatus = "y";
    my @myself     = xCAT::NetworkUtils->determinehostname();
    my $myname     = $myself[ (scalar @myself) - 1 ];

    if ($sitetab)
    {
        (my $ref) = $sitetab->getAttribs({ key => 'installdir' }, 'value');
        if ($ref and $ref->{value})
        {
            $installroot = $ref->{value};
        }
        ($ref) = $sitetab->getAttribs({ key => 'xcatdport' }, 'value');
        if ($ref and $ref->{value})
        {
            $xcatdport = $ref->{value};
        }
        ($ref) = $sitetab->getAttribs({ key => 'xcatiport' }, 'value');
        if ($ref and $ref->{value})
        {
            $xcatiport = $ref->{value};
        }
        ($ref) = $sitetab->getAttribs({ key => 'tftpdir' }, 'value');
        if ($ref and $ref->{value})
        {
            $globaltftpdir = $ref->{value};
        }
        ($ref) = $sitetab->getAttribs({ key => 'nodestatus' }, 'value');
        if ($ref and $ref->{value})
        {
            $nodestatus = $ref->{value};
        }
    }
    my %donetftp = ();
    my %oents = %{ $ostab->getNodesAttribs(\@nodes, [qw(os arch profile provmethod)]) };
    my $restab = xCAT::Table->new('noderes');
    my $hmtab  = xCAT::Table->new('nodehm');
    my $mactab = xCAT::Table->new('mac');

    my $machash = $mactab->getNodesAttribs(\@nodes, [ 'interface', 'mac' ]);

    my $reshash = $restab->getNodesAttribs(\@nodes, [ 'primarynic', 'tftpserver', 'xcatmaster', 'nfsserver', 'nfsdir', 'installnic' ]);
    my $hmhash =
      $hmtab->getNodesAttribs(\@nodes,
        [ 'serialport', 'serialspeed', 'serialflow' ]);
    my $statetab;
    my $stateHash;
    if ($statelite) {
        $statetab = xCAT::Table->new('statelite', -create => 1);
        $stateHash = $statetab->getNodesAttribs(\@nodes, ['statemnt']);
    }

    foreach my $node (@nodes)
    {
        my $osver;
        my $arch;
        my $profile;
        my $platform;
        my $rootimgdir;
        my $nodebootif; # nodebootif will be used if noderes.installnic is not set
        my $dump; # for kdump, its format is "nfs://<nfs_server_ip>/<kdump_path>"
        my $crashkernelsize;
        my $rootfstype;
        my $tftpdir;
        my $imagename;    # set it if running of 'nodeset osimage=xxx'

        if ($reshash->{$node}->[0] and $reshash->{$node}->[0]->{tftpdir}) {
            $tftpdir = $reshash->{$node}->[0]->{tftpdir};
        } else {
            $tftpdir = $globaltftpdir;
        }

        my $ent = $oents{$node}->[0]; #ostab->getNodeAttribs($node, ['os', 'arch', 'profile']);
        if ($ent and $ent->{provmethod} and ($ent->{provmethod} ne 'install') and ($ent->{provmethod} ne 'netboot') and ($ent->{provmethod} ne 'statelite')) {
            $imagename = $ent->{provmethod};
            if (!exists($img_hash{$imagename})) {
                if (!$osimagetab) {
                    $osimagetab = xCAT::Table->new('osimage', -create => 1);
                }
                (my $ref) = $osimagetab->getAttribs({ imagename => $imagename }, 'osvers', 'osarch', 'profile', 'provmethod', 'rootfstype');
                if ($ref) {
                    $img_hash{$imagename}->{osver}      = $ref->{'osvers'};
                    $img_hash{$imagename}->{osarch}     = $ref->{'osarch'};
                    $img_hash{$imagename}->{profile}    = $ref->{'profile'};
                    $img_hash{$imagename}->{provmethod} = $ref->{'provmethod'};
                    $img_hash{$imagename}->{rootfstype} = $ref->{'rootfstype'};
                    if (!$linuximagetab) {
                        $linuximagetab = xCAT::Table->new('linuximage', -create => 1);
                    }
                    (my $ref1) = $linuximagetab->getAttribs({ imagename => $imagename }, 'rootimgdir');
                    if (($ref1) && ($ref1->{'rootimgdir'})) {
                        $img_hash{$imagename}->{rootimgdir} = $ref1->{'rootimgdir'};
                    }
                    if (($ref1) && ($ref1->{'nodebootif'})) {
                        $img_hash{$imagename}->{nodebootif} = $ref1->{'nodebootif'};
                    }
                    if ($ref1) {
                        if ($ref1->{'dump'}) {
                            $img_hash{$imagename}->{dump} = $ref1->{'dump'};
                        }
                    }
                    if (($ref1) && ($ref1->{'crashkernelsize'})) {
                        $img_hash{$imagename}->{crashkernelsize} = $ref1->{'crashkernelsize'};
                    }
                } else {
                    xCAT::MsgUtils->report_node_error($callback, $node, "The OS image '$imagename' for node does not exist");
                    next;
                }
            }
            my $ph = $img_hash{$imagename};
            $osver   = $ph->{osver};
            $arch    = $ph->{osarch};
            $profile = $ph->{profile};

            $rootfstype = $ph->{rootfstype};

            $rootimgdir = $ph->{rootimgdir};
            unless ($rootimgdir) {
                $rootimgdir = "$installroot/netboot/$osver/$arch/$profile";
            }

            $nodebootif      = $ph->{nodebootif};
            $crashkernelsize = $ph->{crashkernelsize};
            $dump            = $ph->{dump};
        }
        else {
            # This is deprecated mode to define node's provmethod, not supported now.
            xCAT::MsgUtils->report_node_error($callback, $node, "OS image name must be specified in nodetype.provmethod");
            next;

            $osver      = $ent->{os};
            $arch       = $ent->{arch};
            $profile    = $ent->{profile};
            $rootimgdir = "$installroot/netboot/$osver/$arch/$profile";

            $rootfstype = "nfs";  # TODO: try to get it from the option or table
            my $imgname;
            if ($statelite) {
                $imgname = "$osver-$arch-statelite-$profile";
            } else {
                $imgname = "$osver-$arch-netboot-$profile";
            }


            if (!$osimagetab) {
                $osimagetab = xCAT::Table->new('osimage');
            }

            if ($osimagetab) {
                my ($ref1) = $osimagetab->getAttribs({ imagename => $imgname }, 'rootfstype');
                if (($ref1) && ($ref1->{'rootfstype'})) {
                    $rootfstype = $ref1->{'rootfstype'};
                }
            } else {
                xCAT::MsgUtils->report_node_error($callback, $node,
                    qq{Cannot find the linux image called "$osver-$arch-$imgname-$profile", maybe you need to use the "nodeset <nr> osimage=<osimage name>" command to set the boot state}
                    );
                next;
            }

            if (!$linuximagetab) {
                $linuximagetab = xCAT::Table->new('linuximage');
            }
            if ($linuximagetab) {
                (my $ref1) = $linuximagetab->getAttribs({ imagename => $imgname }, 'dump', 'crashkernelsize');
                if ($ref1 and $ref1->{'dump'}) {
                    $dump = $ref1->{'dump'};
                }
                if ($ref1 and $ref1->{'crashkernelsize'}) {
                    $crashkernelsize = $ref1->{'crashkernelsize'};
                }
            } else {
                xCAT::MsgUtils->report_node_error($callback, $node,
                    qq{Cannot find the linux image called "$osver-$arch-$imgname-$profile", maybe you need to use the "nodeset <nr> osimage=<osimage name>" command to set the boot state}
                    );
                next;
            }
        }

        #print"osvr=$osver, arch=$arch, profile=$profile, imgdir=$rootimgdir\n";
        unless ($osver and $arch and $profile)
        {
            xCAT::MsgUtils->report_node_error($callback, $node, "Insufficient nodetype entry or osimage entry for $node");
            next;
        }

        $platform = xCAT_plugin::debian::getplatform($osver);
        my $compressedrootimg=xCAT::SvrUtils->searchcompressedrootimg("$rootimgdir");

        # statelite images are not packed.
        if ($statelite) {
            unless (-r "$rootimgdir/kernel") {
                xCAT::MsgUtils->report_node_error($callback, $node,
                    qq{Did you run "genimage" before running "liteimg"? kernel cannot be found at $rootimgdir/kernel on $myname}
                    );
                next;
            }
            if (!-r "$rootimgdir/initrd-statelite.gz") {
                if (!-r "$rootimgdir/initrd.gz") {
                    xCAT::MsgUtils->report_node_error($callback, $node,
                        qq{Did you run "genimage" before running "liteimg"? initrd.gz or initrd-statelite.gz cannot be found}
                        );
                    next;
                }
                else {
                    copy("$rootimgdir/initrd.gz", "$rootimgdir/initrd-statelite.gz");
                }
            }
            if ($rootfstype eq "ramdisk" and !-r "$rootimgdir/rootimg-statelite.gz") {
                xCAT::MsgUtils->report_node_error($callback, $node,
                    qq{No packed image for platform $osver, architecture $arch and profile $profile, please run "liteimg" to create it.}
                    );
                next;
            }
        } else {
            unless (-r "$rootimgdir/kernel") {
                xCAT::MsgUtils->report_node_error($callback, $node,
                    qq{Did you run "genimage" before running "packimage"? kernel cannot be found at $rootimgdir/kernel on $myname}
                    );
                next;
            }
            if (!-r "$rootimgdir/initrd-stateless.gz") {
                if (!-r "$rootimgdir/initrd.gz") {
                    xCAT::MsgUtils->report_node_error($callback, $node,
                        qq{Did you run "genimage" before running "packimg"? initrd.gz or initrd-statelite.gz cannot be found}
                        );
                    next;
                    next;
                }
                else {
                    copy("$rootimgdir/initrd.gz", "$rootimgdir/initrd-stateless.gz");
                }
            }
            unless (-f -r "$rootimgdir/$compressedrootimg") {
                xCAT::MsgUtils->report_node_error($callback, $node,
                    "No packed image for platform $osver, architecture $arch, and profile $profile, please run packimage (e.g.  packimage -o $osver -p $profile -a $arch)"
                    );
                next;
            }
        }

        # create the node-specific post scripts
        #mkpath "/install/postscripts/";
        #xCAT::Postage->writescript($node,"/install/postscripts/".$node, "netboot", $callback);

        # Copy the boot resource to /tftpboot and check to only copy once
        my $docopy = 0;
        my $tftppath;
        my $rtftppath;    # the relative tftp path without /tftpboot/
        if ($imagename) {
            $tftppath  = "$tftpdir/xcat/osimage/$imagename";
            $rtftppath = "xcat/osimage/$imagename";
            unless ($donetftp{$imagename}) {
                $docopy = 1;
                $donetftp{$imagename} = 1;
            }
        } else {
            $tftppath  = "/$tftpdir/xcat/netboot/$osver/$arch/$profile/";
            $rtftppath = "xcat/netboot/$osver/$arch/$profile/";
            unless ($donetftp{ $osver, $arch, $profile }) {
                $docopy = 1;
                $donetftp{ $osver, $arch, $profile } = 1;
            }
        }

        if ($docopy) {
            mkpath("$tftppath");
            if (-f "$rootimgdir/hypervisor") {
                copy("$rootimgdir/hypervisor", "$tftppath");
                $xenstyle = 1;
            }
            copy("$rootimgdir/kernel", "$tftppath");
            if ($statelite) {
                if ($rootfstype eq "ramdisk") {
                    copy("$rootimgdir/initrd-stateless.gz", "$tftppath");
                } else {
                    copy("$rootimgdir/initrd-statelite.gz", "$tftppath");
                }
            } else {
                copy("$rootimgdir/initrd-stateless.gz", "$tftppath");
            }
        }

        if ($statelite) {
            my $initrdloc = "$tftppath";
            if ($rootfstype eq "ramdisk") {
                $initrdloc .= "/initrd-stateless.gz";
            } else {
                $initrdloc .= "/initrd-statelite.gz";
            }
            unless (-r "$tftppath/kernel" and -r $initrdloc) {
                xCAT::MsgUtils->report_node_error($callback, $node, qq{Copying to $tftppath failed.});
                next;
            }
        } else {

            unless (-r "$tftppath/kernel" and -r "$tftppath/initrd-stateless.gz") {
                xCAT::MsgUtils->report_node_error($callback, $node, qq{Copying to $tftppath failed.});
                next;
            }
        }
        my $ent = $reshash->{$node}->[0]; #$restab->getNodeAttribs($node, ['primarynic']);
        my $sent = $hmhash->{$node}->[0];

        #          $hmtab->getNodeAttribs($node,
        #                                 ['serialport', 'serialspeed', 'serialflow']);

        # determine image server, if tftpserver use it, else use xcatmaster
        # last resort use self
        my $imgsrv;
        my $ient;
        my $xcatmaster;

        $ient = $reshash->{$node}->[0]; #$restab->getNodeAttribs($node, ['tftpserver']);
        if ($ient and $ient->{xcatmaster}) {
            $xcatmaster = $ient->{xcatmaster};
        } else {
            $xcatmaster = '!myipfn!'; #allow service nodes to dynamically nominate themselves as a good contact point, this is of limited use in the event that xcat is not the dhcp/tftp server
        }

        if ($ient and $ient->{nfsserver} and $ient->{nfsserver} ne '<xcatmaster>') {
            $imgsrv = $ient->{nfsserver};
        }elsif ($ient and $ient->{tftpserver} and $ient->{tftpserver} ne '<xcatmaster>') {
            $imgsrv = $ient->{tftpserver};
        } else {
            $imgsrv = $xcatmaster;
        }
        unless ($imgsrv) {
            xCAT::MsgUtils->report_node_error($callback, $node, "Unable to determine or reasonably guess the image server for $node");
            next;
        }

        my $kcmdline;
        if ($statelite) {
            if (rootfstype ne "ramdisk") {

                # get entry for nfs root if it exists:
                # have to get nfssvr and nfsdir from noderes table
                my $nfssrv = $imgsrv;
                my $nfsdir = $rootimgdir;
                if ($ient->{nfsdir} ne '') {
                    $nfsdir = $ient->{nfsdir} . "/netboot/$osver/$arch/$profile";

                    #this code sez, "if nfsdir starts with //, then
                    #use a absolute path, i.e. do not append xCATisms"
                    #this is required for some statelite envs.
                    #still open for debate.

                    if ($ient->{nfsdir} =~ m!^//!) {
                        $nfsdir = $ient->{nfsdir};
                        $nfsdir =~ s!^/!!;
                    }
                }

                # special case for redhat6, fedora12/13/14
                if (&using_dracut($osver)) {
                    $kcmdline = "root=nfs:$nfssrv:$nfsdir/rootimg:ro STATEMNT=";
                } else {
                    $kcmdline = "NFSROOT=$nfssrv:$nfsdir STATEMNT=";
                }
            } else {
                $kcmdline = "imgurl=http://$imgsrv/$rootimgdir/rootimg-statelite.gz STATEMNT=";
            }




            # add support for subVars in the value of "statemnt"
            my $statemnt = "";
            if (exists($stateHash->{$node})) {
                $statemnt = $stateHash->{$node}->[0]->{statemnt};
                if (grep /\$/, $statemnt) {
                    my ($server, $dir) = split(/:/, $statemnt);

                    #if server is blank, then its the directory
                    unless ($dir) {
                        $dir    = $server;
                        $server = '';
                    }
                    if (grep /\$|#CMD/, $dir) {
                        $dir = xCAT::SvrUtils->subVars($dir, $node, 'dir', $callback);
                        $dir = ~s/\/\//\//g;
                    }
                    if ($server) {
                        $server = xCAT::SvrUtils->subVars($server, $node, 'server', $callback);
                    }
                    $statemnt = $server . ":" . $dir;
                }
            }
            $kcmdline .= $statemnt . " ";
            $kcmdline .=
              "XCAT=$xcatmaster:$xcatdport ";
            $kcmdline .=
              "NODE=$node ";

            # add flow control setting
            $kcmdline .= "FC=$useflowcontrol ";

            # BEGIN service node
            my $isSV = xCAT::Utils->isServiceNode();
            my $res = xCAT::Utils->runcmd("hostname", 0);
            my $sip = inet_ntoa(inet_aton($res)); # this is the IP of service node
            if ($isSV and (($xcatmaster eq $sip) or ($xcatmaster eq $res))) {

                # if the NFS directory in litetree is on the service node,
                # and it is not exported, then it will be mounted automatically
                xCAT::SvrUtils->setupNFSTree($node, $sip, $callback);

                # then, export the statemnt directory if it is on the service node
                if ($statemnt) {
                    xCAT::SvrUtils->setupStatemnt($sip, $statemnt, $callback);
                }
            }

            # END service node
        }
        else
        {
            $kcmdline =
              "imgurl=http://$imgsrv/$rootimgdir/$compressedrootimg ";
            $kcmdline .= "XCAT=$xcatmaster:$xcatdport ";
        }

        # if site.nodestatus='n', add "nonodestatus" to kcmdline to inform the node not to update nodestatus during provision
        if (($nodestatus eq "n") or ($nodestatus eq "N") or ($nodestatus eq "0")) {
            $kcmdline .= " nonodestatus ";
        }


        if (($::XCATSITEVALS{xcatdebugmode} eq "1") or ($::XCATSITEVALS{xcatdebugmode} eq "2")) {

            my ($host, $ipaddr) = xCAT::NetworkUtils->gethostnameandip($xcatmaster);
            if ($ipaddr) {
                $kcmdline .= " LOGSERVER=$ipaddr ";
            }
            else {
                $kcmdline .= " LOGSERVER=$xcatmaster ";
            }

            $kcmdline .= " xcatdebugmode=$::XCATSITEVALS{xcatdebugmode} ";
        }


        # add one parameter: ifname=<eth0>:<mac address>
        # which is used for dracut
        # the redhat5.x os will ignore it

        my $installnic = undef;
        my $primarynic = undef;
        my $mac        = undef;

        if ($reshash->{$node}->[0] and $reshash->{$node}->[0]->{installnic}) {
            $installnic = $reshash->{$node}->[0]->{installnic};
        }
        if ($reshash->{$node}->[0] and $reshash->{$node}->[0]->{primarynic}) {
            $primarynic = $reshash->{$node}->[0]->{primarynic};
        }

        #else { #no, we autodetect and don't presume anything
        #    $kcmdline .="eth0:";
        #    print "eth0 is used as the default booting network devices...\n";
        #}
        # append the mac address
        my $mac;
        if ($machash->{$node}->[0] && $machash->{$node}->[0]->{'mac'}) {

            # TODO: currently, only "mac" attribute with classic style is used, the "|" delimited string of "macaddress!hostname" format is not used
            $mac = xCAT::Utils->parseMacTabEntry($machash->{$node}->[0]->{'mac'}, $node);
        }
        my $net_params = xCAT::NetworkUtils->gen_net_boot_params($installnic, $primarynic, $mac, $nodebootif);
        if (defined($net_params->{ifname})) {
            $kcmdline .= "$net_params->{ifname} ";
        }
        if (defined($net_params->{netdev})) {
            $kcmdline .= "$net_params->{netdev} ";
        } elsif (defined($net_params->{BOOTIF}) && ($net_params->{setmac} || $arch =~ /ppc/)) {
            $kcmdline .= "$net_params->{BOOTIF} ";
        }

        my %client_nethash = xCAT::DBobjUtils->getNetwkInfo([$node]);
        if ($client_nethash{$node}{mgtifname} =~ /hf/)
        {
            $kcmdline .= "rdloaddriver=hf_if ";
        }


        if (defined $sent->{serialport}) {

            #my $sent = $hmtab->getNodeAttribs($node,['serialspeed','serialflow']);
            unless ($sent->{serialspeed}) {
                xCAT::MsgUtils->report_node_error($callback, $node,"serialport defined, but no serialspeed for $node in nodehm table");
                next;
            }
            if ($arch =~ /ppc64/i) {
                $kcmdline .=
                    "console=tty0 console=hvc" . $sent->{serialport} . "," . $sent->{serialspeed};
            } else {
                $kcmdline .=
                    "console=tty0 console=ttyS" . $sent->{serialport} . "," . $sent->{serialspeed};
            }
            if ($sent->{serialflow} =~ /(hard|tcs|ctsrts)/)
            {
                $kcmdline .= "n8r";
            }
        } else {
            $callback->(
                {
                    warning => ["rcons may not work since no serialport is specified for $node"],
                }
            );
        }

        # add the addkcmdline attribute  to the end
        # of the command, if it exists
        #my $addkcmd   = $addkcmdhash->{$node}->[0];
        # add the extra addkcmd command info, if in the table
        #if ($addkcmd->{'addkcmdline'}) {
        #        $kcmdline .= " ";
        #        $kcmdline .= $addkcmd->{'addkcmdline'};

        #}

        my $kernstr = "$rtftppath/kernel";
        if ($xenstyle) {
            $kernstr .= "!$rtftppath/hypervisor";
        }
        my $initrdstr = "$rtftppath/initrd-stateless.gz";
        $initrdstr = "$rtftppath/initrd-statelite.gz" if ($statelite);

        # special case for the dracut-enabled OSes
        if (&using_dracut($osver)) {
            if ($statelite and $rootfstype eq "ramdisk") {
                $initrdstr = "$rtftppath/initrd-stateless.gz";
            }
        }

        if ($statelite)
        {
            my $statelitetb = xCAT::Table->new('statelite');
            my $mntopts = $statelitetb->getNodeAttribs($node, ['mntopts']);

            my $mntoptions = $mntopts->{'mntopts'};
            unless (defined($mntoptions))
            {
                $kcmdline .= " MNTOPTS=";
            }
            else
            {
                $kcmdline .= " MNTOPTS=$mntoptions";
            }
        }
        $bootparams->{$node}->[0]->{kernel} = $kernstr;
        $bootparams->{$node}->[0]->{initrd} = $initrdstr;
        $bootparams->{$node}->[0]->{kcmdline} = $kcmdline;
    }

    #my $rc = xCAT::TableUtils->create_postscripts_tar();
    #if ( $rc != 0 ) {
    #	xCAT::MsgUtils->message( "S", "Error creating postscripts tar file." );
    #}
}

sub getplatform {
    my $os = shift;
    my $platform;
    if ($os =~ /debian.*/) {
        $platform = "debian";
    }
    elsif ($os =~ /ubuntu.*/) {
        $platform = "ubuntu";
    }
    return $platform;
}

# sub subVars
# copied from litetreee.pm
# TODO: need to move the function to xCAT::Utils?

# some directories will have xCAT database values, like:
# $nodetype.os.  If that is the case we need to open up
# the database and look at them.  We need to make sure
# we do this sparingly...  We don't like tons of hits
# to the database.

sub subVars()
{
    my $dir      = shift;
    my $node     = shift;
    my $type     = shift;
    my $callback = shift;

    # parse all the dollar signs...
    # if its a directory then it has a / in it, so you have to parse it.
    # if its a server, it won't have one so don't worry about it.
    my @arr = split("/", $dir);
    my $fdir = "";
    foreach my $p (@arr) {

        # have to make this geric so $ can be in the midle of the name: asdf$foobar.sitadsf
        if ($p =~ /\$/) {
            my $pre;
            my $suf;
            my @fParts;
            if ($p =~ /([^\$]*)([^# ]*)(.*)/) {
                $pre = $1;
                $p   = $2;
                $suf = $3;
            }

            # have to sub here:
            # get rid of the $ sign.
            foreach my $part (split('\$', $p)) {
                if ($part eq '') { next; }

                #$callback->({error=>["part is $part"],errorcode=>[1]});
                # check if p is just the node name:
                if ($part eq 'node') {

                    # it is so, just return the node.
                    #$fdir .= "/$pre$node$suf";
                    push @fParts, $node;
                } else {

                    # ask the xCAT DB what the attribute is.
                    my ($table, $col) = split('\.', $part);
                    unless ($col) { $col = 'UNDEFINED' }
                    my $tab = xCAT::Table->new($table);
                    unless ($tab) {
                        $callback->({ error => ["$table does not exist"], errorcode => [1] });
                        return;
                    }
                    my $ent;
                    my $val;
                    if ($table eq 'site') {
                        $val = $tab->getAttribs({ key => "$col" }, 'value');
                        $val = $val->{'value'};
                    } else {
                        $ent = $tab->getNodeAttribs($node, [$col]);
                        $val = $ent->{$col};
                    }
                    unless ($val) {

                        # couldn't find the value!!
                        $val = "UNDEFINED"
                    }
                    push @fParts, $val;
                }
            }
            my $val = join('.', @fParts);
            if ($type eq 'dir') {
                $fdir .= "/$pre$val$suf";
            } else {
                $fdir .= $pre . $val . $suf;
            }
        } else {

            # no substitution here
            $fdir .= "/$p";
        }
    }

    # now that we've processed variables, process commands
    # this isn't quite rock solid.  You can't name directories with #'s in them.
    if ($fdir =~ /#CMD=/) {
        my $dir;
        foreach my $p (split(/#/, $fdir)) {
            if ($p =~ /CMD=/) {
                $p =~ s/CMD=//;
                my $cmd = $p;

                #$callback->({info=>[$p]});
                $p = `$p 2>&1`;
                chomp($p);

                #$callback->({info=>[$p]});
                unless ($p) {
                    $p = "#CMD=$p did not return output#";
                }
            }
            $dir .= $p;
        }
        $fdir = $dir;
    }

    return $fdir;
}

sub setupNFSTree {
    my $node     = shift;
    my $sip      = shift;
    my $callback = shift;

    my $cmd = "litetree $node";
    my @uris = xCAT::Utils->runcmd($cmd, 0);

    foreach my $uri (@uris) {

        # parse the result
        # the result looks like "nodename: nfsserver:directory";
        $uri =~ m/\Q$node\E:\s+(.+):(.+)$/;
        my $nfsserver    = $1;
        my $nfsdirectory = $2;

        if ($nfsserver eq $sip) {    # on the service node
            unless (-d $nfsdirectory) {
                if (-e $nfsdirectory) {
                    unlink $nfsdirectory;
                }
                mkpath $nfsdirectory;
            }


            $cmd = "showmount -e $nfsserver";
            my @entries = xCAT::Utils->runcmd($cmd, 0);
            shift @entries;
            if (grep /\Q$nfsdirectory\E/, @entries) {
                $callback->({ data => ["$nfsdirectory has been exported already!"] });
            } else {
                $cmd = "/usr/sbin/exportfs :$nfsdirectory";
                xCAT::Utils->runcmd($cmd, 0);

                # exportfs can export this directory immediately
                $callback->({ data => ["now $nfsdirectory is exported!"] });
                $cmd = "cat /etc/exports";
                @entries = xCAT::Utils->runcmd($cmd, 0);
                unless (my $entry = grep /\Q$nfsdirectory\E/, @entries) {

                    # if no entry in /etc/exports, one entry with default options will be added
                    $cmd = qq{echo "$nfsdirectory *(rw,no_root_squash,sync,no_subtree_check)" >> /etc/exports};
                    xCAT::Utils->runcmd($cmd, 0);
                    $callback->({ data => ["$nfsdirectory is added to /etc/exports with default option"] });
                }
            }
        }
    }
}

sub setupStatemnt {
    my $sip      = shift;
    my $statemnt = shift;
    my $callback = shift;

    $statemnt =~ m/^(.+):(.+)$/;
    my $nfsserver    = $1;
    my $nfsdirectory = $2;

    if ($sip eq inet_ntoa(inet_aton($nfsserver))) {
        unless (-d $nfsdirectory) {
            if (-e $nfsdirectory) {
                unlink $nfsdirectory;
            }
            mkpath $nfsdirectory;
        }

        my $cmd = "showmount -e $nfsserver";
        my @entries = xCAT::Utils->runcmd($cmd, 0);
        shift @entries;
        if (grep /\Q$nfsdirectory\E/, @entries) {
            $callback->({ data => ["$nfsdirectory has been exported already!"] });
        } else {
            $cmd = "/usr/sbin/exportfs :$nfsdirectory -o rw,no_root_squash,sync,no_subtree_check";
            xCAT::Utils->runcmd($cmd, 0);
            $callback->({ data => ["now $nfsdirectory is exported!"] });

            # add the directory into /etc/exports if not exist
            $cmd = "cat /etc/exports";
            @entries = xCAT::Utils->runcmd($cmd, 0);
            if (my $entry = grep /\Q$nfsdirectory\E/, @entries) {
                unless ($entry =~ m/rw/) {
                    $callback->({ data => ["The $nfsdirectory should be with rw option in /etc/exports"] });
                }
            } else {
                xCAT::Utils->runcmd(qq{echo "$nfsdirectory *(rw,no_root_squash,sync,no_subtree_check)" >> /etc/exports}, 0);
                $callback->({ data => ["$nfsdirectory is added into /etc/exports with default options"] });
            }
        }
    }
}


1;
