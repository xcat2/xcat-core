# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

# This module is only used for provisionging VIOS partition through rh MN.

package xCAT_plugin::nimol;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use strict;

use POSIX qw(WNOHANG nice);
use POSIX qw(WNOHANG setsid :errno_h);
use File::Path;
use File::Copy;
use Fcntl qw/:flock/;

#use Data::Dumper;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::DBobjUtils;
use xCAT::Utils;

sub handled_commands {
    return {
        copycd => "nimol",
        nodeset => "noderes:netboot",
    };
}

my $global_callback;
sub copy_mksysb {
    my $srcpath = shift;
    my $dstpath = shift;
    my @mksysb_files = ();
    my %filehash = ();
    my $dstfile = $dstpath."/mksysb/mksysb";
    unless (-e $srcpath."/nimol/ioserver_res/") {
        return "No mksysb files found in this CD.";
    }
    unless (-e $dstpath."/mksysb") {
        return "No mksysb directory available in $dstpath.";
    }
    #my $all_filesize = 0;
    my $dir;
    opendir($dir, $srcpath."/nimol/ioserver_res/");
    while (my $file = readdir($dir)) {
        if ($file =~ /^mksysb/) {
            $filehash{$file} = 1;
            #my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = $stat($file);
            #$all_filesize += $size / 1024 / 1024; 
        }
    }
    closedir($dir);
    @mksysb_files = sort (keys %filehash);
    foreach (@mksysb_files) {
        my $rsp;
        push @{$rsp->{data}}, "Copying file $_ to $dstfile";
        xCAT::MsgUtils->message("I", $rsp, $global_callback);
        system("cat $srcpath/nimol/ioserver_res/$_ >> $dstfile");
    }
    return undef;
}
sub copy_spot {
    my $srcpath = shift;
    my $dstpath = shift;
    my $srcfile = $srcpath."/nimol/ioserver_res/ispot.tar.Z";
    my $dstfile = $dstpath."/spot/ispot.tar.Z";
    unless (-e $srcfile) {
        return "No spot file found in this CD.";
    }
    if (-e $dstfile) {
        return undef;
    }
    my $rsp;
    push @{$rsp->{data}}, "Copying ispot.tar.z to $dstfile";
    xCAT::MsgUtils->message("I", $rsp, $global_callback);

    copy($srcfile, $dstfile);
    xCAT::MsgUtils->message("I", {data=>["Extract file: $dstfile"]}, $global_callback);
    system("/bin/tar zxvf $dstfile -C $dstpath/spot > /dev/null");
    return undef;
}
sub copy_bootimg {
    my $srcpath = shift;
    my $dstpath = shift;    
    my $srcfile = $srcpath."/nimol/ioserver_res/booti.chrp.mp.ent.Z";
    my $dstfile = $dstpath."/bootimg/booti.chrp.mp.ent.Z";
    unless (-e $srcfile) {
        return "No bootimg file found in this CD.";
    }
    if (-e $dstfile) {
        return undef;
    }
    my $rsp;
    push @{$rsp->{data}}, "Copying file booti.chrp.mp.ent.Z to $dstfile";
    xCAT::MsgUtils->message("I", $rsp, $global_callback);
    copy($srcfile, $dstfile);
    xCAT::MsgUtils->message("I", {data=>["Extract file: $dstfile"]}, $global_callback);
    system("/bin/gunzip $dstfile > /dev/null");

    return undef;
}
sub copy_bosinstdata {
    my $srcpath = shift;
    my $dstpath = shift;
    my $srcfile = $srcpath."/nimol/ioserver_res/bosinst.data";
    my $dstfile = $dstpath."/bosinst_data/bosinst.data";
    unless (-e $srcfile) {
        return "No bosinst.data file found in this CD.";
    }
    if (-e $dstfile) {
        return undef;
    }
    my $rsp;
    push @{$rsp->{data}}, "Copying file bosinst.data to $dstfile";
    xCAT::MsgUtils->message("I", $rsp, $global_callback);
    copy($srcfile, $dstfile);
    return undef;
}
sub preprocess_request {
    my $request = shift;
    my $callback = shift;
    my $command = $request->{command}->[0];
    
    if ($command eq 'copycd') {
        return [$request];
    } elsif ($command eq 'nodeset') {
        my @args = ();
        if (ref($request->{arg})) {
            @args=@{$request->{arg}};
        } else {
            @args=($request->{arg});
        }
        if ($args[0] =~ /^osimage=(.*)$/) {
            $request->{opt}->{osimage} = $1;
        } else {
            $callback->({error=>["Only option 'osimage' support"]}, errorcode=>[1]);
            $request = {};
            return;
        }
        #print Dumper($request);
        return [$request];   
    } 
    
    return undef;
}

sub process_request {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;
    my $command = $request->{command}->[0];

    if ($command eq 'copycd') {
        return copycd($request, $callback, $subreq);
    } elsif ($command eq 'nodeset') {
        #print Dumper($request);
        return nodeset($request, $callback, $subreq);
    }
}

sub copycd {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;
    @ARGV = @{$request->{arg}};
    $global_callback = $callback;
#   copycd 
#       -m mntpath 
#       -p path  
#       -i inspection
#       -a arch  
#       -f $file
#       -w nonoverwrite
    my $mntpath;
    my $file;
    my $distname;
    my $path;
    my $arch;
    GetOptions( 'm=s' => \$mntpath,
                'a=s' => \$arch, 
                'f=s' => \$file,
                'p=s' => \$path,
                'n=s' => \$distname,
              );
    unless($distname && $file && $mntpath && $arch) {
        #$callback->({error=>"distname, file or mntpath not specified, $distname, $file, $mntpath"});
        return ;
    }
    if ($distname && $distname !~ /^vios/i) {
        #$callback->({error=>"distname incorrect"});
        return ;
    } elsif ($arch !~ /^ppc64/i) {
        #$callback->({error=>"arch incorrect"});
        return ;
    } elsif (!$file) {
        #$callback->({error=>"Only suport to use the iso file vios"});
        return;
    }
    #print __LINE__."=====>vios=====.\n";
    #print Dumper($request);
    my $installroot = "/install";
    my @entries = xCAT::TableUtils->get_site_attribute("installdir");
    my $t_entry = $entries[0];
    if (defined($t_entry)) {
        $installroot = $t_entry;
    }
    # OSLEVEL= 6.1.8.15
    #my $oslevel; 
    #if (-r "$mntpath/OSLEVEL" and -f "$mntpath/OSLEVEL") {
    #    my $oslevel_fd;
    #    open ($mkcd_fd, $mntpath."/OSLEVEL");
    #    my $line = <$mkcd_fd>;
    #    if ($line =~ /^OSLEVEL=\s*(\d*\.\d*\.\d*\.\d*)/) {
    #        $oslevel_fd = $1;
    #    } 
    #} else {
    #    $callback->({error=>"There is no 'OSLEVEL' file found for this iso file"});
    #    return;
    #}
    my $rsp;
    push @{$rsp->{data}}, "Copying media to $installroot/nim/$distname/";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    unless($path) {
        $path = "$installroot/nim/$distname";
    }
    my $omask = umask 0022;
    # check the disk number, the 1st or 2nd CD
    unless (-e $path) {
        mkpath("$path");
    } 
    unless (-e $path."/mksysb") {
        mkpath($path."/mksysb");
    }
    unless (-e $path."/spot") {
        mkpath($path."/spot");
    }
    unless (-e $path."/bootimg") {
        mkpath($path."/bootimg");
    }
    unless (-e $path."/bosinst_data") {
        mkpath($path."/bosinst_data");
    }
    umask $omask;
    my $expect_cd;
    my $oslevel;
    unless  (-e "$path/expect_cd") {
        $expect_cd = 1;
    } else {
        my $expectcd_fd;
        open ($expectcd_fd, "<", "$path/expect_cd");
        $expect_cd = <$expectcd_fd>;
        chomp($expect_cd);
        close($expectcd_fd);
    }
    if ($expect_cd eq "END") {
        #goto CREATE_OBJ;
        $callback->({error=>"All the cds for $distname are gotten."});
        return;    
    }
    if (-r "$mntpath/mkcd.data" and -f "$mntpath/mkcd.data") {
        my $mkcd_fd;
        open ($mkcd_fd, "<", "$mntpath/mkcd.data");
        while (<$mkcd_fd>) {
            if (/VOLUME=(\d+)/) {
                if ($expect_cd ne $1) {
                    $callback->({error=>"The $expect_cd cd is expected."});
                    return;    
                } else {
                    $expect_cd += 1;
                }
            } elsif (/LASTVOLUME/) {
                $expect_cd = "END";
            }
        }
        close($mkcd_fd);
    } else {
        $callback->({error=>"There is no 'mkcd' file found for this iso file"});
        return;
    }   
    {   # write the expect cd num
        my $expectcd_fd;
        open ($expectcd_fd, ">", "$path/expect_cd");
        print $expectcd_fd $expect_cd;
        close ($expectcd_fd);
    }
    {
        my $oslevel_fd;
        open($oslevel_fd, "<", "$mntpath/OSLEVEL");
        $oslevel = <$oslevel_fd>;
        chomp $oslevel;
        $oslevel =~ s/OSLEVEL=\s*(\d+\.\d+\.\d+\.\d+)/$1/; 
        close($oslevel_fd);
    }
    my $res;
    $res = &copy_mksysb($mntpath, $path); 
    if (defined($res)) {
        $callback->({error=>$res});
        return;
    }
    $res = &copy_spot($mntpath, $path);    
    if (defined($res)) {
        $callback->({error=>$res});
        return;
    }
    $res = &copy_bootimg($mntpath, $path);    
    if (defined($res)) {
        $callback->({error=>$res});
        return;
    }
    $res = &copy_bosinstdata($mntpath, $path);    
    if (defined($res)) {
        $callback->({error=>$res});
        return;
    }
    #CREATE_OBJ:
    if ($expect_cd eq "END") {
        my $imagename = $distname.'_sysb';
        xCAT::MsgUtils->message("I", {data=>["create osimage object: $imagename"]}, $callback);
        my $osimagetab = xCAT::Table->new('osimage', -create=>1);
        if ($osimagetab) {
            my %key_col = (imagename=>$imagename);
            my %tb_cols = (imagetype=>"NIM",
                           provmethod=>"nimol",
                           osname=>"AIX",
                           osdistroname=>$distname,
                           osvers=>$oslevel,
                           osarch=>$arch);
            #print Dumper(%tb_cols);
            $osimagetab->setAttribs(\%key_col, \%tb_cols);
        } else {
            $callback->({error=>"Can not open 'osimage' table"});
            return;
        }
        $osimagetab->close();
    }
}

sub update_export {
    my $export_fd;
    open ($export_fd, "<", "/etc/exports");
    flock($export_fd,LOCK_SH);
    my @curr_export=<$export_fd>;
    flock($export_fd,LOCK_UN);
    close($export_fd); 
    my @new_export = ();
    my $need_update = 0;
    my $i = 0;
    for ($i = 0; $i < scalar(@curr_export); $i++) {
        my $line = $curr_export[$i];
        if ($line =~ /^\/install\s*\*\((.*)\)/) {
            my @tmp_options = split /,/,$1;
            unless (grep(/insecure/,@tmp_options)) {
                push @tmp_options, "insecure";
                $need_update = 1;
            }
            push @new_export, join(',',@tmp_options);
        } else {
            push @new_export, $line;
        }
    } 
    unless ($need_update) {
        return;
    }
    my $new_export_fd;
    open($new_export_fd, ">>", "/etc/exports");
    flock($new_export_fd,LOCK_EX);
    seek($new_export_fd,0,0);
    truncate($new_export_fd,0);
    for my $l  (@new_export) { print $new_export_fd $l; }
    flock($new_export_fd,LOCK_UN);
    close($new_export_fd);
    #system("service nfs restart");
    my $retcode=xCAT::Utils->restartservice("nfs");
    return $retcode;
}

sub update_syslog {
    my $syslog_fd;
    open ($syslog_fd, "<", "/etc/rsyslog.conf");
    flock($syslog_fd,LOCK_SH);
    my @curr_syslog=<$syslog_fd>;
    flock($syslog_fd,LOCK_UN);
    close($syslog_fd); 
    unless (grep /local2.*nimol\.log/, @curr_syslog) {
        my $new_syslog_fd;
        open($new_syslog_fd, ">>", "/etc/exports");
        print $new_syslog_fd "local2.* /var/log/nimol.log\n";
        close($new_syslog_fd);
        #system("service rsyslog restart");
	my $retcode=xCAT::Utils->restartservice("rsyslog");
	return $retcode;
    } else {
        print "Don't need to update syslog configure file.\n";
    }
}



sub create_imgconf_file {
    my $nodes = shift;
    my $subreq = shift;
    my $nim_root = shift;
    my $bootimg_root = shift;
    my $relative_path = $bootimg_root;
    $relative_path =~ s/^\/tftpboot//;
    # Get nodes network information
    my %nethash = ();
    %nethash = xCAT::DBobjUtils->getNetwkInfo($nodes);
    my $rootpw = undef;
    my $passwdtab = xCAT::Table->new('passwd');            
    if ($passwdtab) {                                      
        my $et = $passwdtab->getAttribs({key => 'vios', username => 'padmin'}, 'password');
        if ($et and defined ($et->{'password'})) {     
            $rootpw = $et->{'password'};
        }
    }
    unless (defined($rootpw)) {
        return "Unable to find requested password from passwd, with key=vios,username=padmin";
    }
    unless (-e $bootimg_root."/viobootimg") {
        return "Unable to find VIOS bootimg file";
    }
    chdir($bootimg_root);
    foreach my $node (@$nodes) {
        my $bootimg_conf_fd;
        my $gateway = $nethash{$node}{gateway};
        my $mask = $nethash{$node}{mask};
        my $gateway_ip = xCAT::NetworkUtils->getipaddr($gateway);
        my $master_node = xCAT::TableUtils->GetMasterNodeName($node);
        my $master = xCAT::NetworkUtils->gethostname($master_node);
        my $master_ip = xCAT::NetworkUtils->getipaddr($master); 
        my $node_ip = xCAT::NetworkUtils->getipaddr($node);
        my $relative_bootfile = $relative_path."/viobootimg-$node";
        unless (-e "viobootimg-$node") {
            symlink("viobootimg", "viobootimg-$node");
        }
        if (-e $bootimg_root."/viobootimg-$node.info") {
            unlink($bootimg_root."/viobootimg-$node.info");
        }
        open ($bootimg_conf_fd, ">", $bootimg_root."/viobootimg-$node.info"); 
        print $bootimg_conf_fd "export NIM_SERVER_TYPE=linux\n";
        print $bootimg_conf_fd "export NIM_SYSLOG_PORT=514\n";
        print $bootimg_conf_fd "export NIM_SYSLOG_FACILITY=local2\n";
        print $bootimg_conf_fd "export NIM_NAME=viobootimg-$node\n";
        print $bootimg_conf_fd "export NIM_HOSTNAME=$node\n";
        print $bootimg_conf_fd "export NIM_CONFIGURATION=standalone\n";
        print $bootimg_conf_fd "export NIM_MASTER_HOSTNAME=$master\n";
        print $bootimg_conf_fd "export REMAIN_NIM_CLIENT=no\n";
        print $bootimg_conf_fd "export RC_CONFIG=rc.bos_inst\n";
        print $bootimg_conf_fd "export NIM_BOSINST_ENV=\"/../SPOT/usr/lpp/bos.sysmgt/nim/methods/c_bosinst_env\"\n";
        print $bootimg_conf_fd "export NIM_BOSINST_RECOVER=\"/../SPOT/usr/lpp/bos.sysmgt/nim/methods/c_bosinst_env -a hostname=$node\"\n";
        print $bootimg_conf_fd "export NIM_BOSINST_DATA=/NIM_BOSINST_DATA\n";
        print $bootimg_conf_fd "export SPOT=$master:$nim_root/spot/SPOT/usr\n";
        print $bootimg_conf_fd "export NIM_CUSTOM=\"/../SPOT/usr/lpp/bos.sysmgt/nim/methods/c_script -a location=$master:$nim_root/scripts/xcatvio.script\"\n";
        print $bootimg_conf_fd "export NIM_BOS_IMAGE=/NIM_BOS_IMAGE\n";
        print $bootimg_conf_fd "export NIM_BOS_FORMAT=mksysb\n";
        print $bootimg_conf_fd "export NIM_HOSTS=\" $node_ip:$node $master_ip:$master \"\n";
        print $bootimg_conf_fd "export NIM_MOUNTS=\" $master:$nim_root/bosinst_data/bosinst.data:/NIM_BOSINST_DATA:file $master:$nim_root/mksysb/mksysb:/NIM_BOS_IMAGE:file \"\n";
        print $bootimg_conf_fd "export ROUTES=\" default:0:$gateway_ip \"\n";
        print $bootimg_conf_fd "export NIM_IPADDR=$node_ip\n";
        print $bootimg_conf_fd "export NIM_NETMASK=$mask\n";
        print $bootimg_conf_fd "export PADMIN_PASSWD=$rootpw\n";
        print $bootimg_conf_fd "export SEA_ADAPTERS=bootnic\n";
        close($bootimg_conf_fd);

        $subreq->({command=>['makedhcp'],
                   node=>[$node],
                   arg=>['-s', 'supersede server.filename=\"'.$relative_bootfile.'\";']}, $global_callback); 
    } 
}

sub nodeset {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;

    my $command = $request->{command}->[0];
    my $args = $request->{arg};
    my $nodes = $request->{node};

    my $osimage = $request->{opt}->{osimage};
    my $nim_root;
    my $bootimg_root;
    unless ($osimage) {
        $callback->({error=>["No param specified."], errorcode=>[1]});
         return;
    }
    {
        my $installroot = "/install";
        my @entries = xCAT::TableUtils->get_site_attribute("installdir");
        my $t_entry = $entries[0];
        if (defined($t_entry)) {
            $installroot = $t_entry;
        }

        my $osimagetab = xCAT::Table->new('osimage');
        (my $ref) = $osimagetab->getAttribs({imagename=>$osimage}, 'osdistroname', 'provmethod');
        if ($ref) {
            if ($ref->{provmethod} and $ref->{provmethod} eq 'nimol' and $ref->{osdistroname}) {
                $nim_root = $installroot."/nim/".$ref->{osdistroname};
                $bootimg_root = "/tftpboot/".$ref->{osdistroname}."/nodes";
            } else {
                $callback->({error=>["The 'provmethod' for OS image $osimage can only be 'nimol'."], errorcode=>[1]});
                return;
            }
        } else {
            $callback->({error=>["No OS image $osimage found on the osimage table."], errorcode=>[1]});
            return;
        }
    } 
    
    update_export();
    update_syslog();
    unless (-e $bootimg_root) {
        mkpath($bootimg_root);
        copy($nim_root."/bootimg/booti.chrp.mp.ent", $bootimg_root."/viobootimg");
    }       
    
    unless (-e $nim_root."/scripts/xcatvio.script") {
        mkpath($nim_root."/scripts/");
        copy($::XCATROOT."/share/xcat/scripts/xcatvio.script", $nim_root."/scripts/");
    }
    
    my $res = &create_imgconf_file($nodes, $subreq, $nim_root, $bootimg_root);
    if ($res) {
        $callback->({error=>["$res"], errorcode=>[1]});
        return;
    }
}


1;
