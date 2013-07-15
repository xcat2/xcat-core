# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::geninitrd;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

use strict;
use lib "$::XCATROOT/lib/perl";
use File::Copy;
use xCAT::MsgUtils;
use xCAT::TableUtils;
use xCAT::Table;
use xCAT::Scope;

sub handled_commands
{
    return {
        geninitrd => "geninitrd",
    }
}

sub preprocess_request
{
    my $req = shift;
    my $callback = shift;

    unless (defined ($req->{arg}) && $req->{arg}->[0]) {
        xCAT::MsgUtils->message("E", {error=>["An osimage name needs to be specified."], errorcode=>["1"]}, $callback);
        return;
    }
 
    #if tftpshared is not set, dispatch this command to all the service nodes
    my @entries =  xCAT::TableUtils->get_site_attribute("sharedtftp");
    my $t_entry = $entries[0];
    if ( defined($t_entry) and ($t_entry == 0 or $t_entry =~ /no/i)) {
        $req->{'_disparatetftp'}=[1];
        return xCAT::Scope->get_broadcast_scope($req,@_);
    }
   return [$req];
}


sub process_request
{
    my $req  = shift;
    my $callback = shift;

    if ($req->{command}->[0] eq 'geninitrd')
    {
        return geninitrd($req, $callback);
    }

}

sub geninitrd {
    my $req  = shift;
    my $callback = shift;

    my $osimage = $req->{arg}->[0];

    my ($osvers, $arch, $pkgdir, $driverupdatesrc, $netdrivers, $osdisupdir);

    # get attributes from osimage table
    my $osimagetab=xCAT::Table->new('osimage');
    unless ($osimagetab) {
        xCAT::MsgUtils->message("E", {error=>["Cannot open the table osimage."], errorcode=>["1"]}, $callback);
        return;
    }

    my $oient = $osimagetab->getAttribs({imagename => $osimage}, 'osvers', 'osarch', 'osupdatename');
    unless ($oient && $oient->{'osvers'} && $oient->{'osarch'} ) {
        xCAT::MsgUtils->message("E", {error=>["The osimage [$osimage] was not defined or [osvers, osarch] attributes were not set."], errorcode=>["1"]}, $callback);
        return;
    }
    $osvers = $oient->{'osvers'};
    $arch = $oient->{'osarch'};

    # get attributes from linuximage table
    my $linuximagetab=xCAT::Table->new('linuximage');
    unless ($linuximagetab) {
        xCAT::MsgUtils->message("E", {error=>["Cannot open the table linuximage."], errorcode=>["1"]}, $callback);
        return;
    }

    my $lient = $linuximagetab->getAttribs({imagename => $osimage}, 'pkgdir',  'driverupdatesrc',  'netdrivers');
    unless ($lient && $lient->{'pkgdir'}) {
        xCAT::MsgUtils->message("E", {error=>["The osimage [$osimage] was not defined or [pkgdir] attribute was not set."], errorcode=>["1"]}, $callback);
        return;
    }
    $pkgdir = $lient->{'pkgdir'};
    $driverupdatesrc = $lient->{'driverupdatesrc'};
    $netdrivers = $lient->{'netdrivers'};

    # get the path list of the osdistroupdate
    if ($oient->{'osupdatename'}) {
        my @osupdatenames = split (/,/, $oient->{'osupdatename'});
        
        my $osdistrouptab=xCAT::Table->new('osdistroupdate', -create=>1);
        unless ($osdistrouptab) {
            xCAT::MsgUtils->message("E", { error => ["Cannot open the table osdistroupdate."], errorcode => [1] }, $callback);
            return;
        }

        my @osdup = $osdistrouptab->getAllAttribs("osupdatename", "dirpath");
        foreach my $upname (@osupdatenames) {
            foreach my $upref (@osdup) {
                if ($upref->{'osupdatename'} eq $upname) {
                    $osdisupdir .= ",$upref->{'dirpath'}";
                    last;
                }
            }
        }

        $osdisupdir =~ s/^,//;
    }

    # get the source path of initrd and kernel from the pkgdir of osimage
    # copy the initrd and kernel to /tftpboot
    # pass the path of initrd and kernel in /tftpboot to insertdd 
    my $initrdpath;
    my $kernelpath;
    my $tftpdir = "/tftpboot";
    my @entries =  xCAT::TableUtils->get_site_attribute("$tftpdir");
    my $t_entry = $entries[0];
    if ( defined($t_entry) ) {
        $tftpdir = $t_entry;
    }
    my $tftppath = "$tftpdir/xcat/osimage/$osimage";
    if ($arch =~ /x86/) {
        if ($osvers =~ /(^ol[0-9].*)|(centos.*)|(rh.*)|(fedora.*)|(SL.*)/) {
            $kernelpath = "$tftppath/vmlinuz";
            copy("$pkgdir/images/pxeboot/vmlinuz", $kernelpath);
            $initrdpath = "$tftppath/initrd.img";
            copy("$pkgdir/images/pxeboot/initrd.img", $initrdpath);
        } elsif ($osvers =~ /(sles.*)|(suse.*)/) {
            $kernelpath = "$tftppath/linux";
            copy("$pkgdir/1/boot/$arch/loader/linux", $kernelpath);
            $initrdpath = "$tftppath/initrd";
            copy("$pkgdir/1/boot/$arch/loader/initrd", $initrdpath);
        } else {
            xCAT::MsgUtils->message("E", { error => ["unknow osvers [$osvers]."], errorcode => [1] }, $callback);
            return;
        } 
    } elsif ($arch =~ /ppc/) {
        if ($osvers =~ /(^ol[0-9].*)|(centos.*)|(rh.*)|(fedora.*)|(SL.*)/) {
            $kernelpath = "$tftppath/vmlinuz";
            copy("$pkgdir/ppc/ppc64/vmlinuz", $kernelpath);
            if (-r "$pkgdir/ppc/ppc64/ramdisk.image.gz") {
                $initrdpath = "$tftppath/initrd.img";
                copy ("$pkgdir/ppc/ppc64/ramdisk.image.gz", $initrdpath);
            } elsif (-r "$pkgdir/ppc/ppc64/initrd.img") {
                $initrdpath = "$tftppath/initrd.img";
                copy("$pkgdir/ppc/ppc64/initrd.img", $initrdpath);
            }
        } elsif ($osvers =~ /(sles.*)|(suse.*)/) {
            $kernelpath = undef;
            $initrdpath = "$tftppath/inst64";
            copy ("$pkgdir/1/suseboot/inst64", $initrdpath);
        } else {
            xCAT::MsgUtils->message("E", { error => ["unknow osvers [$osvers]."], errorcode => [1] }, $callback);
            return;
        }
    } else {
        xCAT::MsgUtils->message("E", { error => ["unknow arch [$arch]."], errorcode => [1] }, $callback);
        return;
    }

    # call the insert_dd function in the anaconda or sles to hack the initrd that:
    # 1. Get the new kernel from update distro and copy it to /tftpboot
    # 2. Inject the drivers to initrd in /tftpboot base on the new kernel ver
    if ($osvers =~ /(^ol[0-9].*)|(centos.*)|(rh.*)|(fedora.*)|(SL.*)/) {
        require  xCAT_plugin::anaconda;
        xCAT_plugin::anaconda->insert_dd($callback, $osvers, $arch, $initrdpath, $kernelpath, $driverupdatesrc, $netdrivers, $osdisupdir);
    } elsif ($osvers =~ /(sles.*)|(suse.*)/) {
        require  xCAT_plugin::sles;
        xCAT_plugin::sles->insert_dd($callback, $osvers, $arch, $initrdpath, $kernelpath, $driverupdatesrc, $netdrivers, $osdisupdir);
    } 

}

1;
