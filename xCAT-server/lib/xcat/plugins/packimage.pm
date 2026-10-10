# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
    xCAT plugin package to pack the stateless image

    Supported options:
        -h Display usage message
        -v Command Version
        -o Operating system (fedora8, rhel5, sles10,etc)
        -p Profile (compute,service)
        -a Architecture (ppc64,x86_64,etc)
        -m Method (default cpio)

=cut

#-------------------------------------------------------
package xCAT_plugin::packimage;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use strict;
use lib "$::XCATROOT/lib/perl";
use Data::Dumper;
use xCAT::Table;
use Getopt::Long;
use File::Path;
use File::Copy;
use Cwd;
use Errno qw(EEXIST);
use File::Temp;
use Sys::Hostname ();
use File::Basename;
use File::Path;

#use xCAT::Utils qw(genpassword);
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::SvrUtils;
use xCAT::PasswordUtils;
use Digest::MD5 qw(md5_hex);

Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");


my $verbose = 0;

#$verbose = 1;

# Publication takes milliseconds, so packimage waits no longer than this for the publication lock.
my $publish_lock_wait = 60;

#-------------------------------------------------------

=head3  handled_commands

    Return list of commands handled by this plugin

=cut

#-------------------------------------------------------
sub handled_commands {
    return {
        packimage => "packimage",
      }
}

#-------------------------------------------------------

=head3  Process the command

=cut

#-------------------------------------------------------
sub process_request {
    my $request     = shift;
    my $callback    = shift;
    my $doreq       = shift;
    my $installroot = xCAT::TableUtils->getInstallDir();
    my @timezone    = xCAT::TableUtils->get_site_attribute("timezone");

    my $args;
    if (defined($request->{arg})) {
        $args = $request->{arg};
        @ARGV = @{$args};
    }
    if (scalar(@ARGV) == 0) {
        $callback->({ info => ["Usage:\n   packimage [-m| --method=cpio|tar] [-c| --compress=gzip|pigz|xz] [--nosyncfiles] <imagename>\n   packimage [-h| --help]\n   packimage [-v| --version]"] });
        return 0;
    }

    my $osver;
    my $arch;
    my $profile;
    my $method = 'cpio';
    my $compress;
    my $exlistloc;
    my $syncfile;
    my $rootimg_dir;
    my $destdir;
    my $nosyncfiles;
    my $imagename;
    my $dotorrent;
    my $provmethod;
    my $envars;
    my $help;
    my $version;
    my $lock;

    GetOptions(
        "profile|p=s" => \$profile,
        "arch|a=s"    => \$arch,
        "osver|o=s"   => \$osver,
        "method|m=s"  => \$method,
        "compress|c=s"  => \$compress,
        "tracker=s"   => \$dotorrent,
        'nosyncfiles'      => \$nosyncfiles,
        "help|h"      => \$help,
        "version|v"   => \$version
    );
    if ($arch or $osver or $profile) {
        $callback->({ error => ["-o, -p and -a options are obsoleted, please use 'packimage <osimage name>' instead."], errorcode => [1] });
        return 1;
    }
    if ($version) {
        my $version = xCAT::Utils->Version();
        $callback->({ info => [$version] });
        return 0;
    }
    if ($help) {
        $callback->({ info => ["Usage:\n   packimage [-m| --method=cpio|tar] [-c| --compress=gzip|pigz|xz] [--nosyncfiles] <imagename>\n   packimage [-h| --help]\n   packimage [-v| --version]"] });
        return 0;
    }

    if (@ARGV > 0) {
        $imagename = $ARGV[0];

        # load the module in memory
        eval { require("$::XCATROOT/lib/perl/xCAT/Table.pm") };
        if ($@) {
            $callback->({ error => [$@], errorcode => [1] });
            return 1;
        }

        # get the info from the osimage and linux
        my $osimagetab = xCAT::Table->new('osimage', -create => 1);
        unless ($osimagetab) {
            $callback->({ error => ["The osimage table cannot be opened."], errorcode => [1] });
            return 1;
        }
        my $linuximagetab = xCAT::Table->new('linuximage', -create => 1);
        unless ($linuximagetab) {
            $callback->({ error => ["The linuximage table cannot be opened."], errorcode => [1] });
            return 1;
        }
        (my $ref) = $osimagetab->getAttribs({ imagename => $imagename }, 'osvers', 'osarch', 'profile', 'provmethod', 'synclists','environvar');
        unless ($ref) {
            $callback->({ error => ["Cannot find image \'$imagename\' from the osimage table."], errorcode => [1] });
            return 1;
        }
        (my $ref1) = $linuximagetab->getAttribs({ imagename => $imagename }, 'exlist', 'rootimgdir');
        unless ($ref1) {
            $callback->({ error => ["Cannot find $imagename from the linuximage table."], errorcode => [1] });
            return 1;
        }

        $osver      = $ref->{'osvers'};
        $arch       = $ref->{'osarch'};
        $profile    = $ref->{'profile'};
        $syncfile   = $ref->{'synclists'};
        $provmethod = $ref->{'provmethod'};
        $envars     = $ref->{'environvar'};

        unless ($osver and $arch and $profile and $provmethod) {
            $callback->({ error => ["osimage.osvers, osimage.osarch, osimage.profile and osimage.provmethod must be specified for the image $imagename in the database."], errorcode => [1] });
            return 1;
        }

        if ($provmethod ne 'netboot') {
            $callback->({ error => ["\'$imagename\' cannot be used to build diskless image. Make sure osimage.provmethod is 'netboot'."], errorcode => [1] });
            return 1;
        }

        $exlistloc = $ref1->{'exlist'};
        $destdir   = $ref1->{'rootimgdir'};
    } else {
        $callback->({ error => ["An image name is required, use 'packimage <osimage name>'."], errorcode => [1] });
        return 1;
    }

    unless ($destdir) {
        $destdir = "$installroot/netboot/$osver/$arch/$profile";
    }
    $rootimg_dir = "$destdir/rootimg";

    my $is_openeuler = $osver =~ /^openeuler/;
    if ($is_openeuler) {
        unless (defined(xCAT::Utils::normalize_openeuler_version(substr($osver, 9)))
            && $arch =~ /^(?:x86_64|ppc64le)$/) {
            $callback->({ error => ["Unsupported openEuler image release or architecture: $osver $arch"], errorcode => [1] });
            return 1;
        }
        if (-f "$rootimg_dir/.statelite/litefile.save") {
            $callback->({ error => ["openEuler StateLite images are not supported"], errorcode => [1] });
            return 1;
        }
        unless (-d $rootimg_dir) {
            $callback->({ error => ["$rootimg_dir does not exist; run genimage first"], errorcode => [1] });
            return 1;
        }
    }

    my $retcode;
    ($retcode,$lock)=xCAT::Utils->acquire_lock_imageop($rootimg_dir);
    if($retcode){
        $callback->({ error => ["$lock"], errorcode => [1]});
        return 1;
    }

    my $distname = $osver;
    if ($osver =~ /^leap15/) {
        $distname = "sles";
    } else {
        until (-r "$::XCATROOT/share/xcat/netboot/$distname/" or not $distname) {
            chop($distname);
        }
    }
    unless ($distname) {
        $callback->({ error => ["Unable to find $::XCATROOT/share/xcat/netboot directory for $osver"], errorcode => [1] });
        return 1;
    }
    unless ($installroot) {
        $callback->({ error => ["No installdir defined in site table"], errorcode => [1] });
        return 1;
    }
    my $oldpath = cwd();

    #before generating rootimg.$suffix, copy $installroot/postscripts into the image at /xcatpost
    if (-e "$rootimg_dir/xcatpost") {
        system("rm -rf $rootimg_dir/xcatpost");
    }

    system("mkdir -p $rootimg_dir/xcatpost");
    system("cp -r $installroot/postscripts/* $rootimg_dir/xcatpost/");

    #put the image name, uuid and timestamp into diskless image when it is packed.
    `echo IMAGENAME="'$imagename'" > $rootimg_dir/opt/xcat/xcatinfo`;

    my $uuid = `uuidgen`;
    chomp $uuid;
    `echo IMAGEUUID="'$uuid'" >> $rootimg_dir/opt/xcat/xcatinfo`;

    my $timestamp = `date`;
    chomp $timestamp;
    `echo TIMESTAMP="'$timestamp'" >> $rootimg_dir/opt/xcat/xcatinfo`;


    # before generating rootimg.$suffix or rootimg.sfs, need to switch the rootimg to stateless mode if necessary
    my $rootimg_status = 0; # 0 means stateless mode, while 1 means statelite mode
    $rootimg_status = 1 if (-f "$rootimg_dir/.statelite/litefile.save");

    my %liteHash;           # create hash table for the entries in @listList
    unless ($is_openeuler) {
        my @ret = xCAT::Utils->runcmd("ilitefile $osver-$arch-statelite-$profile", 0, 1);
        if (parseLiteFiles($ret[0], \%liteHash)) {
            $callback->({ error => ["Failed for parsing litefile table!"], errorcode => [1] });
            return 1;
        }
    }

    $verbose && $callback->({ data => [ "rootimg_status = $rootimg_status at line " . __LINE__ ] });

    # Each StateLite change is recorded, so that every exit undoes exactly what was done.
    my ($statelite_converted, @statelite_moved, @statelite_created, %statelite_saved);
    # Every return after the conversion below must call this.
    my $restore_statelite = sub {
        return 0 unless $statelite_converted;
        $statelite_converted = 0;
        my @failed;
        foreach my $filename (@statelite_moved) {
            xCAT::Utils->runcmd("rm -rf $rootimg_dir$filename", 0, 1);
            xCAT::Utils->runcmd("mv $rootimg_dir/.statebackup$filename $rootimg_dir$filename", 0, 1);
            push @failed, $filename if $::RUNCMD_RC;
        }
        foreach my $filename (@statelite_created) {
            xCAT::Utils->runcmd("rm -rf $rootimg_dir$filename", 0, 1);
        }
        foreach my $saved (sort keys %statelite_saved) {
            xCAT::Utils->runcmd("mv $rootimg_dir/.statebackup/$saved $rootimg_dir$statelite_saved{$saved}", 0, 1);
            push @failed, $statelite_saved{$saved} if $::RUNCMD_RC;
        }
        if (@failed) {
            $callback->({ error => ["Cannot restore the StateLite files " . join(', ', @failed)
                  . " in $rootimg_dir. The originals stay in $rootimg_dir/.statebackup."], errorcode => [1] });
            return 1;
        }
        xCAT::Utils->runcmd("rm -rf $rootimg_dir/.statebackup", 0, 1);
        return 0;
    };
    my $statelite_failure = sub {
        my $message = shift;
        $callback->({ error => [$message], errorcode => [1] });
        $restore_statelite->();
        return 1;
    };

    if ($rootimg_status) {
        # A .statebackup that an earlier pack could not restore holds the only copy of the original files.
        if (-e "$rootimg_dir/.statebackup" || -l "$rootimg_dir/.statebackup") {
            $callback->({ error => ["$rootimg_dir/.statebackup holds StateLite files that an earlier packimage did not restore. "
                  . "Restore them and remove the directory, then run packimage again."], errorcode => [1] });
            return 1;
        }
        unless (mkdir("$rootimg_dir/.statebackup")) {
            $callback->({ error => ["Cannot create $rootimg_dir/.statebackup: $!"], errorcode => [1] });
            return 1;
        }
        $statelite_converted = 1;

        # read through the litefile table to decide which file/directory should be restore
        my $defaultloc = "$rootimg_dir/.default";
        foreach my $entry (keys %liteHash) {
            my @tmp      = split /\s+/, $entry;
            my $filename = $tmp[1];
            my $fileopt  = $tmp[0];

            if ($fileopt =~ m/link/) {

                # backup them into .statebackup dirctory
                # restore the files with "link" options
                if ($filename =~ m/\/$/) {
                    chop $filename;
                }

                # create the parent directory if $filename's directory is not there,
                my $parent = dirname $filename;
                unless (-d "$rootimg_dir/.statebackup$parent") {
                    unlink "$rootimg_dir/.statebackup$parent";
                    $verbose && $callback->({ data => ["mkdir -p $rootimg_dir/.statebackup$parent"] });
                    xCAT::Utils->runcmd("mkdir -p $rootimg_dir/.statebackup$parent", 0, 1);
                    return $statelite_failure->("Cannot create $rootimg_dir/.statebackup$parent") if $::RUNCMD_RC;
                }
                $verbose && $callback->({ data => [ "backing up the file $filename.. at line " . __LINE__ ] });
                $verbose && print "++ $defaultloc$filename ++ $rootimg_dir$filename ++ at " . __LINE__ . "\n";
                if (-e "$rootimg_dir$filename" || -l "$rootimg_dir$filename") {
                    xCAT::Utils->runcmd("mv $rootimg_dir$filename $rootimg_dir/.statebackup$filename", 0, 1);
                    return $statelite_failure->("Cannot move $rootimg_dir$filename to $rootimg_dir/.statebackup") if $::RUNCMD_RC;
                    push @statelite_moved, $filename;
                } else {
                    push @statelite_created, $filename;
                }
                xCAT::Utils->runcmd("cp -r -a $defaultloc$filename $rootimg_dir$filename", 0, 1);
            }
        }
    }

    unless ($is_openeuler) {
        # TODO: following the old genimage code, to update the stateles-only files/directories
        # # another file should be /opt/xcat/xcatdsklspost, but it seems  not necessary
        if (-e "$rootimg_dir/etc/init.d/statelite") {
            xCAT::Utils->runcmd("mv $rootimg_dir/etc/init.d/statelite $rootimg_dir/.statebackup/statelite ", 0, 1);
            if ($statelite_converted) {
                return $statelite_failure->("Cannot move $rootimg_dir/etc/init.d/statelite to $rootimg_dir/.statebackup") if $::RUNCMD_RC;
                $statelite_saved{statelite} = '/etc/init.d/statelite';
            }
        }
        if (-e "$rootimg_dir/usr/share/dracut") {

            # currently only used for redhat families, not available for SuSE families
            if (-e "$rootimg_dir/etc/rc.sysinit.backup") {
                xCAT::Utils->runcmd("mv $rootimg_dir/etc/rc.sysinit.backup $rootimg_dir/etc/rc.sysinit", 0, 1);
            }
        }

        #restore the install.netboot of xcat dracut module
        if (-e "$rootimg_dir/usr/lib/dracut/modules.d/97xcat/install") {
            xCAT::Utils->runcmd("mv $rootimg_dir/usr/lib/dracut/modules.d/97xcat/install $rootimg_dir/.statebackup/install", 0, 1);
            if ($statelite_converted) {
                return $statelite_failure->("Cannot move $rootimg_dir/usr/lib/dracut/modules.d/97xcat/install to $rootimg_dir/.statebackup") if $::RUNCMD_RC;
                $statelite_saved{install} = '/usr/lib/dracut/modules.d/97xcat/install';
            }
        }
        my $dracut_install = "$::XCATROOT/share/xcat/netboot/$distname/dracut_033/install.netboot";
        if (!-r $dracut_install) {
            $dracut_install = "$::XCATROOT/share/xcat/netboot/rh/dracut_033/install.netboot";
        }
        xCAT::Utils->runcmd("cp $dracut_install $rootimg_dir/usr/lib/dracut/modules.d/97xcat/install", 0, 1);
    }


    # timedatectl requires /etc/localtime link to the zoneinfo in /usr/share/zoneinfo
    if ($timezone[0]) {
        unlink("$rootimg_dir/etc/localtime");
        symlink("../usr/share/zoneinfo/$timezone[0]", "$rootimg_dir/etc/localtime");
            
        if (not stat "$rootimg_dir/etc/localtime") {
            $callback->({ warning => ["Unable to set timezone to \'$timezone[0]\', check this is a valid timezone"] });
        } 
    } else {
        $callback->({ info => ["No timezone defined in site table, skipping timezone /etc/localtime configuration"] });
    }

    my $native_filelist = $is_openeuler ? File::Temp->new(TMPDIR => 1, UNLINK => 1) : undef;
    my $xcat_packimg_tmpfile = $is_openeuler ? "$native_filelist" : "/tmp/xcat_packimg.$$";
    my $excludestr           = "find . -xdev ";
    my $includestr;
    if ($exlistloc) {
        my @excludeslist = split ',', $exlistloc;
        foreach my $exlistlocname (@excludeslist) {
            my $exlist;
            my $excludetext;
            open($exlist, "<", $exlistlocname);
            system("echo -n > $xcat_packimg_tmpfile");
            while (<$exlist>) {
                $excludetext .= $_;
            }
            close($exlist);

            if ($timezone[0]) {
                # Add the zoneinfo to the include list
                $excludetext .= "+./usr/share/zoneinfo/$timezone[0]\n";
                
                # /usr/share/zoneinfo can have many levels of links
                # If the configured timezone is a link, also add the link target to the include list
                # Note: this logic can only handle 2 levels of linking
                my $realtimezonefile = Cwd::abs_path("$rootimg_dir/usr/share/zoneinfo/$timezone[0]");
                if ("$rootimg_dir/usr/share/zoneinfo/$timezone[0]" ne "$realtimezonefile") {
                    my $relativetzpath = substr($realtimezonefile, length($rootimg_dir));
                    $excludetext .= "+.$relativetzpath\n";
                }
                
            } else {
                $callback->({ info => ["No timezone defined in site table, skipping timezone exlist configuration"] });
            }

            #handle the #INLCUDE# tag recursively
            my $idir         = dirname($exlistlocname);
            my $doneincludes = 0;
            while (not $doneincludes) {
                $doneincludes = 1;
                if ($excludetext =~ /#INCLUDE:[^#^\n]+#/) {
                    $doneincludes = 0;
                    $excludetext =~ s/#INCLUDE:([^#^\n]+)#/include_file($1,$idir)/eg;
                }

            }

            my @tmp = split("\n", $excludetext);
            foreach (@tmp) {
                chomp $_;
                s/\s*#.*//;    #-- remove comments
                next if /^\s*$/;    #-- skip empty lines
                if (/^\+/) {
                    s/^\+//;        #remove '+'
                    $includestr .= "-path '" . $_ . "' -o ";
                } else {
                    s/^\-//;        #remove '-' if any
                    $excludestr .= "'!' -path '" . $_ . "' -a ";
                }
            }
        }
    }

    # the files specified for statelite should be excluded
    my @excludeStatelite = ("./etc/init.d/statelite", "./etc/rc.sysinit.backup", "./.statelite*", "./.default*", "./.statebackup*");
    push @excludeStatelite, './etc/rc.d/init.d/statelite', './etc/rc.d/init.d/localdisk',
      './etc/init.d/localdisk', './.sllocal*' if $is_openeuler;
    foreach my $entry (@excludeStatelite) {
        $excludestr .= "'!' -path '" . $entry . "' -a ";
    }

    $excludestr =~ s/-a $//;
    if ($includestr) {
        $includestr =~ s/-o $//;
        $includestr = "find . -xdev " . $includestr;
    }

    print "\nexcludestr=$excludestr\n\n includestr=$includestr\n\n";    # debug

    # add the xCAT post scripts to the image
    unless (-d "$rootimg_dir") {
        $callback->({ error => ["$rootimg_dir does not exist, run genimage -o $osver -p $profile on a server with matching architecture"], errorcode => [1] });
        $restore_statelite->();
        return 1;
    }

    # some rpms like atftp mount the rootimg/proc to /proc, we need to make sure rootimg/proc is free of junk
    # before packaging the image
    system("umount $rootimg_dir/proc");
    copybootscript($installroot, $rootimg_dir, $osver, $arch, $profile, $callback);


    my $pass = xCAT::PasswordUtils::crypt_system_password();
    if (!defined($pass)) {
        $pass = 'cluster';
    }
    my @secure_root    = xCAT::TableUtils->get_site_attribute("secureroot");
    if ($secure_root[0] == 1) {
        $pass = '*';
    }
    my $oldmask = umask(0077);
    my $shadow;
    open($shadow, "<", "$rootimg_dir/etc/shadow");
    my @shadents = <$shadow>;
    close($shadow);
    open($shadow, ">", "$rootimg_dir/etc/shadow");
    print $shadow "root:$pass:13880:0:99999:7:::\n";
    foreach (@shadents) {
        unless (/^root:/) {
            print $shadow "$_";
        }
    }
    close($shadow);
    umask($oldmask);

    if (not $nosyncfiles) {
        # sync fils configured in the synclist to the rootimage
        $syncfile = xCAT::SvrUtils->getsynclistfile(undef, $osver, $arch, $profile, "netboot", $imagename);
        if ( defined($syncfile) && -d $rootimg_dir) {
            my $myenv='';
            if($envars){
                $myenv.=" XCAT_OSIMAGE_ENV=$envars";
            }
            my @filelist = split ',', $syncfile;
            foreach my $synclistfile (@filelist) {
                if ( -f $synclistfile) {
                    print "Syncing files from $synclistfile to root image dir: $rootimg_dir\n";
                    my $cmd = "$myenv $::XCATROOT/bin/xdcp -i $rootimg_dir -F $synclistfile";
                    xCAT::Utils->runcmd($cmd, 0, 1);
                }
            }
        }
    } else {
        print "Bypass of syncfiles requested, will not sync files to root image directory.\n";
    }

    my $temppath;
    my $oldmask;
    my $native_failure = sub {
        my $message = shift;
        $callback->({ error => [$message], errorcode => [1] });
        chdir($oldpath);
        umask($oldmask) if defined($oldmask);
        rmtree($temppath) if defined($temppath) && -d $temppath;
        unlink($xcat_packimg_tmpfile);
        $restore_statelite->();
        return 1;
    };
    unless (-d $rootimg_dir) {
        return $native_failure->("$rootimg_dir does not exist, run genimage -o $osver -p $profile on a server with matching architecture");
    }

    my $suffix;
    if ($compress) {
        if ($compress eq 'gzip') {
            my $isgzip = system("bash -c 'type -p gzip' >/dev/null 2>&1");
            unless ($isgzip == 0) {
                return $native_failure->("Command gzip does not exist, please make sure it is installed.");
            }
            $suffix = "gz";
        } elsif ($compress eq 'pigz') {
            my $ispigz = system("bash -c 'type -p pigz' >/dev/null 2>&1");
            unless ($ispigz == 0) {
                return $native_failure->("Command pigz does not exist, please make sure it is installed.");
            }
            $suffix = "gz";
        } elsif ($compress eq 'xz') {
            my $isxz = system("bash -c 'type -p xz' >/dev/null 2>&1");
            unless ($isxz == 0) {
                return $native_failure->("Command xz does not exist, please make sure it is installed.");
            }
            $suffix = "xz";
        } else {
            return $native_failure->("Invalid compress method '$compress' requested");
        }
    } else {
        my $ispigz = system("bash -c 'type -p pigz' >/dev/null 2>&1");
        if ($ispigz == 0) {
            $compress = "pigz";
        } else {
            my $isgzip = system("bash -c 'type -p gzip' >/dev/null 2>&1");
            if ($isgzip == 0) {
                $compress = "gzip";
            } else {
                return $native_failure->("The default compress tool 'gzip' and 'pigz' does not exist, please specify an available compress method with '-c'.");
            }
        }
        $suffix = "gz";
    }

    unless (($method eq 'cpio') or ($method eq 'tar') or ($method eq 'squashfs')) {
        return $native_failure->("Invalid archive method '$method' requested");
    }
    $callback->({ data => ["Packing contents of $rootimg_dir"] });
    $callback->({ info => ["archive method:$method"] });
    unless ($method =~ /squashfs/) {
        $callback->({ info => ["compress method:$compress"] });
    }

    $suffix = $method.".".$suffix;
    my $image_file = $method eq 'squashfs' ? 'rootimg.sfs' : "rootimg.$suffix";
    # The image lock is per host, so only this host's .packimage files are known to be abandoned.
    (my $host = Sys::Hostname::hostname()) =~ s/[^A-Za-z0-9.-]/_/g;
    my @abandoned = glob("$destdir/.packimage-$host+????????");
    rmtree(\@abandoned) if @abandoned;
    # ctorrent names the metainfo after the archive, so both are built under their final names in a private directory.
    my $stage = eval { File::Temp->newdir(".packimage-$host+XXXXXXXX", DIR => $destdir) }
      or return $native_failure->("Cannot create a temporary directory in $destdir: $@");
    my $archive_output = "$stage/$image_file";
    $archive_output =~ s/'/'\\''/g;
    $archive_output = "'$archive_output'";
    chdir($rootimg_dir) or return $native_failure->("Cannot enter $rootimg_dir: $!");
    my ($list_rc, $list_output) = native_pack_command("$excludestr > $xcat_packimg_tmpfile");
    return $native_failure->("Cannot enumerate $rootimg_dir: $list_output") if $list_rc;
    if ($includestr) {
        ($list_rc, $list_output) = native_pack_command("$includestr >> $xcat_packimg_tmpfile");
        return $native_failure->("Cannot enumerate included files: $list_output") if $list_rc;
    }
    # Nodes keep downloading the previous archive until the rename replaces it.
    my $publish_archive = sub {
        # The image lock is per host, and mkdir is atomic for every host, also on NFS without locks.
        my $publish_lock = "$destdir/.packimage-publish";
        for (my $waited = 0; !mkdir($publish_lock); $waited++) {
            return $native_failure->("Cannot create $publish_lock: $!") unless $! == EEXIST;
            my $age = time() - ((stat($publish_lock))[9] // time());
            if ($waited >= $publish_lock_wait || $age > $publish_lock_wait) {
                my $holder = '';
                if (open(my $owner, '<', "$publish_lock/owner")) {
                    $holder = <$owner> // '';
                    close($owner);
                    chomp($holder);
                    $holder = " by $holder" if $holder;
                }
                return $native_failure->("$publish_lock is held$holder. If no packimage of this image runs on any host, "
                      . "remove it and run packimage again.");
            }
            sleep 1;
        }
        if (open(my $owner, '>', "$publish_lock/owner")) {
            print $owner "$host $$\n";
            close($owner);
        }
        my $target = "$destdir/$image_file";
        my ($new_archive, $new_metainfo) = ("$stage/$image_file", "$stage/$image_file.metainfo");
        my $metainfo = -e $new_metainfo;

        # The previous metainfo goes first, so no failure leaves a metainfo that describes another archive.
        my $published = -s $new_archive && chmod(0644, $new_archive) && (!$metainfo || chmod(0644, $new_metainfo))
          && (!-e "$target.metainfo" || unlink("$target.metainfo"))
          && rename($new_archive, $target)
          && (!$metainfo || rename($new_metainfo, "$target.metainfo"));
        my $error = $!;
        unlink grep { $_ ne $target && $_ ne "$target.metainfo" } glob("$destdir/rootimg.*") if $published;
        unlink("$publish_lock/owner");
        rmdir($publish_lock);
        return $native_failure->("Cannot publish $target: $error") unless $published;
        return 0;
    };

    if ($method =~ /cpio/) {
        if (!$excludestr) {
            $excludestr = "find . -xdev -print0 | cpio -H newc -o -0 | $compress -c - > $archive_output";
        } else {
            $excludestr = "cat $xcat_packimg_tmpfile|cpio -H newc -o | $compress -c - > $archive_output";
        }
        $oldmask = umask 0077;
    } elsif ($method =~ /tar/) {
        my $checkoption1 = `tar --xattrs-include 2>&1`;
        my $checkoption2 = `tar --selinux 2>&1`;
        my $option;
        if ($checkoption1 !~ /unrecognized/) {
            $option .= " --xattrs --xattrs-include='*' ";
        }
        if ($checkoption2 !~ /unrecognized/) {
            $option .= "--selinux ";
        }
        if (!$excludestr) {
            $excludestr = "find . -xdev -print0 | tar $option --no-recursion --use-compress-program=$compress --null -T - -cf $archive_output";
        } else {
            $excludestr = "cat $xcat_packimg_tmpfile| tar $option --no-recursion --use-compress-program=$compress -T - -cf  $archive_output";
        }
        $oldmask = umask 0077;
    } elsif ($method =~ /squashfs/) {
        $temppath = eval { mkdtemp("/tmp/packimage.$$.XXXXXXXX") }
          or return $native_failure->("Cannot create a staging directory: $@");
        chmod 0755, $temppath;
        $excludestr = "cat $xcat_packimg_tmpfile|cpio -dump $temppath";
    }
    chdir("$rootimg_dir");
    my ($archive_rc, $outputmsg) = native_pack_command($excludestr);
    unless($archive_rc){
        $callback->({ info => ["$outputmsg"] });
    }else{
        $callback->({ info => ["$outputmsg"] });
        return $native_failure->("packimage failed while running: \n $excludestr");
    }
    if ($method =~ /squashfs/) {
        my $flags = "";
        if ($osver =~ /rhels5/) {
            if ($arch =~ /x86/) {
                $flags = "-le";
            } elsif ($arch =~ /ppc/) {
                $flags = "-be";
            }
        }

        if (!-x "/sbin/mksquashfs" && !-x "/usr/bin/mksquashfs") {
            return $native_failure->("mksquashfs not found; install squashfs-tools") if $is_openeuler;
            if ($osver =~ /sle/) {
                return $native_failure->("mksquashfs not found, squashfs rpm should be installed on the management node");
            }
            return $native_failure->("mksquashfs not found, squashfs-tools rpm should be installed on the management node");
        }
        my $mksquashfs_command = "mksquashfs $temppath $archive_output $flags";
        xCAT::Utils->runcmd($mksquashfs_command, 0, 1);
        my $rc = $::RUNCMD_RC;
        if ($rc) {
            return $native_failure->("Command \"$mksquashfs_command\" failed");
        }
        $rc = system("rm -rf $temppath");
        if ($rc) {
            return $native_failure->("Failed to clean up temp space");
        }
    }

    if ($dotorrent && $method =~ /cpio/) {
        my $made = chdir("$stage") && !system("ctorrent -t -u $dotorrent -l 1048576 -s $image_file.metainfo $image_file");
        return $native_failure->("ctorrent cannot create the metainfo of $destdir/$image_file") unless $made;
    }

    # The StateLite files must be back in place before the new archive replaces the previous one.
    return $native_failure->("$destdir keeps its previous archive because the StateLite files of $rootimg_dir were not restored")
      if $restore_statelite->();
    return 1 if $publish_archive->();

    umask($oldmask) if defined($oldmask);
    system("rm -f $xcat_packimg_tmpfile");


    my $restored = chdir($oldpath);
    return $is_openeuler ? 0 : $restored;
}

sub native_pack_command {
    my ($command) = @_;
    open(my $pipe, '-|', '/bin/bash', '-o', 'pipefail', '-c', "{ $command; } 2>&1")
      or return (1, "Cannot execute archive command: $!");
    my $output = do { local $/; <$pipe> };
    close($pipe);
    return ($?, $output // '');
}

#-------------------------------------------------------

=head3  copybootscript

    copy the xCAT diskless init scripts to the image

=cut

#-------------------------------------------------------
sub copybootscript {

    my $installroot = shift;
    my $rootimg_dir = shift;
    my $osver       = shift;
    my $arch        = shift;
    my $profile     = shift;
    my $callback    = shift;

    if (-f "$installroot/postscripts/xcatdsklspost") {

        # copy the xCAT diskless post script to the image
        mkpath("$rootimg_dir/opt/xcat");

        copy("$installroot/postscripts/xcatdsklspost", "$rootimg_dir/opt/xcat/xcatdsklspost");
        chmod(0755, "$rootimg_dir/opt/xcat/xcatdsklspost");

    } else {

        my $rsp;
        push @{ $rsp->{data} }, "Could not find the script $installroot/postscripts/xcatdsklspost.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }


    #if ( -f "$installroot/postscripts/xcatpostinit") {
    # copy the linux diskless init script to the image
    #   - & set the permissions
    #copy ("$installroot/postscripts/xcatpostinit","$rootimg_dir/etc/init.d/xcatpostinit");

    #chmod(0755,"$rootimg_dir/etc/init.d/xcatpostinit");

    # run chkconfig
    #my $chkcmd = "chroot $rootimg_dir chkconfig --add xcatpostinit";
    #symlink "/etc/init.d/xcatpostinit","$rootimg_dir/etc/rc3.d/S84xcatpostinit";
    #symlink "/etc/init.d/xcatpostinit","$rootimg_dir/etc/rc4.d/S84xcatpostinit";
    #symlink "/etc/init.d/xcatpostinit","$rootimg_dir/etc/rc5.d/S84xcatpostinit";
    #my $rc = system($chkcmd);
    #if ($rc) {
    #my $rsp;
    #  	push @{$rsp->{data}}, "Could not run the chkconfig command.\n";
    #  	xCAT::MsgUtils->message("E", $rsp, $callback);
    #      	return 1;
    #  }
    #} else {
    #my $rsp;
    #    push @{$rsp->{data}}, "Could not find the script $installroot/postscripts/xcatpostinit.\n";
    #    xCAT::MsgUtils->message("E", $rsp, $callback);
    #    return 1;
    #}
    return 0;
}

#-------------------------------------------------------

=head3  include_file


=cut

#-------------------------------------------------------
sub include_file
{
    my $file = shift;
    my $idir = shift;
    my @text = ();
    unless ($file =~ /^\//) {
        $file = $idir . "/" . $file;
    }

    open(INCLUDE, $file) || \
      return "#INCLUDEBAD:cannot open $file#";

    while (<INCLUDE>) {
        chomp($_);
        s/\s+$//;    #remove trailing spaces
        next if /^\s*$/;    #-- skip empty lines
        push(@text, $_);
    }

    close(INCLUDE);

    return join("\n", @text);
}

#-------------------------------------------------------

=head3  parseLiteFiles

    In the liteentry table, one directory and its sub-items (including sub-directory and entries) can co-exist;
    In order to handle such a scenario, one hash is generated to show the hirarachy relationship

    For example, one array with entry names is used as the input:
    my @entries = (
        "imagename bind,persistent /var/",
        "imagename bind /var/tmp/",
        "imagename tmpfs,rw /root/",
        "imagename tmpfs,rw /root/.bashrc",
        "imagename tmpfs,rw /root/test/",
        "imagename bind /etc/resolv.conf",
        "imagename bind /var/run/"
    );
    Then, one hash will generated as:
    %hashentries = {
        'bind,persistent /var/' => [
            'bind /var/tmp/',
            'bind /var/run/'
        ],
        'bind /etc/resolv.conf' => undef,
        'tmpfs,rw /root/' => [
            'tmpfs,rw /root/.bashrc',
            'tmpfs,rw /root/test/'
        ]
    };

    Arguments:
        one array with entrynames,
        one hash to hold the entries parsed

    Returns:
        0 if sucucess
        1 if fail

=cut

#-------------------------------------------------------
sub parseLiteFiles {
    my ($flref, $dhref) = @_;
    my @entries = @{$flref};


    foreach (@entries) {
        my $entry = $_;
        my @str = split /\s+/, $entry;
        shift @str;
        $entry = join "\t", @str;
        my $file = $str[1];
        chop $file if ($file =~ m{/$});
        unless (exists $dhref->{"$entry"}) {
            my $parent = dirname($file);

            # to see whether $parent exists in @entries or not
            unless ($parent =~ m/\/$/) {
                $parent .= "/";
            }
            my @res = grep { $_ =~ m/\Q$parent\E$/ } @entries;
            my $found = scalar @res;

            if ($found == 1) {    # $parent is found in @entries
                                  # handle $res[0];
                my @tmpresentry = split /\s+/, $res[0];
                shift @tmpresentry;
                $res[0] = join "\t", @tmpresentry;
                chop $parent;
                my @keys = keys %{$dhref};
                my $kfound = grep { $_ =~ m/\Q$res[0]\E$/ } @keys;
                if ($kfound eq 0) {
                    $dhref->{ $res[0] } = [];
                }
                push @{ $dhref->{"$res[0]"} }, $entry;
            } else {
                $dhref->{"$entry"} = ();
            }
        }
    }

    return 0;
}

1;
