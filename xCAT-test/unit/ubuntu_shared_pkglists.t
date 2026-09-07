#!/usr/bin/env perl
use strict;
use warnings;

use File::Basename qw(basename);
use File::Spec;
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use xCAT::SvrUtils;
use xCAT::Postage;

# The arch-neutral Ubuntu package lists are what every release and architecture without a list
# of its own falls back to. Postage exports the resolved list as OSPKGS and ospkgs hands it to
# one apt-get install, so one name the archive no longer carries loses every package on the
# list. ntp and ntpdate are gone from 26.04, libodbc1 (the unixODBC runtime the odbcsetup
# postscript needs) was renamed on 24.04, libvirt-bin is gone from 20.04 on and qemu-kvm from
# 22.04 on. Older releases keep the names, and the daemon, they had.

my $repo_root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
my $share     = File::Spec->catdir( $repo_root, 'xCAT-server', 'share', 'xcat' );
my $install   = File::Spec->catdir( $share, 'install', 'ubuntu' );
my $netboot   = File::Spec->catdir( $share, 'netboot', 'ubuntu' );

# ospkgs receives the list as get_pkglist_tex renders it for OSPKGS, includes expanded.
sub packages_in {
    my ($path) = @_;
    return {} unless $path && -f $path;
    my %p = map { $_ => 1 } grep { length } split /,/, xCAT::Postage::get_pkglist_tex($path);
    return \%p;
}

# The list an osimage of this profile, release and architecture resolves to, and its packages.
sub resolved {
    my ( $dir, $profile, $os, $arch ) = @_;
    my $file = xCAT::SvrUtils->get_pkglist_file_name( $dir, $profile, $os, $arch );
    return ( basename( $file || '' ), packages_in($file) );
}

# The shared lists keep ntp for the releases that still carry it. aarch64 has no list of its own.
foreach my $case ( [ $install, 'compute' ], [ $install, 'service' ], [ $install, 'kvm' ], [ $netboot, 'compute' ] ) {
    my ( $dir, $profile ) = @$case;
    my ( $file, $p ) = resolved( $dir, $profile, 'ubuntu24.04.4', 'aarch64' );
    is( $file, "$profile.pkglist", "$profile on 24.04 without a list of its own resolves to the shared list" );
    ok( $p->{ntp}, "... which keeps ntp" );
    ok( !$p->{$_}, "... and no longer names $_" ) for qw(libodbc1 qemu-kvm libvirt-bin);
}
ok( packages_in("$install/service.pkglist")->{unixodbc}, 'the shared service list names unixodbc' );
ok( packages_in("$install/service.pkglist")->{'libdbd-pg-perl'}, '... and the PostgreSQL driver beside the MySQL one' );

# 26.04 dropped ntp, so each shared list has a 26.04 counterpart that carries chrony.
foreach my $case ( [ $install, 'compute' ], [ $install, 'service' ], [ $install, 'kvm' ], [ $netboot, 'compute' ] ) {
    my ( $dir, $profile ) = @$case;
    my ( $file, $p ) = resolved( $dir, $profile, 'ubuntu26.04.1', 'aarch64' );
    is( $file, "$profile.ubuntu26.04.pkglist", "$profile on 26.04 without a list of its own resolves to the 26.04 list" );
    ok( $p->{chrony},                 "... which names chrony" );
    ok( !$p->{ntp} && !$p->{ntpdate}, "... and neither ntp nor ntpdate" );
}
ok( packages_in("$install/service.ubuntu26.04.pkglist")->{unixodbc}, 'the 26.04 service list names unixodbc' );
ok( packages_in("$install/service.ubuntu26.04.pkglist")->{'libdbd-pg-perl'}, '... and the PostgreSQL driver beside the MySQL one' );

# qemu-kvm was a transitional name for the emulator of the host architecture. No current release
# has one name for that, so a per-architecture list names the native one and the shared kvm lists
# fall back to qemu-system, which carries every emulator. ospkgs installs without recommends, so
# every list names qemu-utils for the qcow2 volumes kvm.pm creates. 12.04, 14.04 and 16.04 keep
# the names they shipped with.
my @kvm = (
    # os              arch       list                              emulator            libvirt
    [ 'ubuntu12.04.5', 'x86_64',  'kvm.ubuntu12.04.pkglist',         'qemu-kvm',         'libvirt-bin' ],
    [ 'ubuntu14.04.4', 'x86_64',  'kvm.ubuntu14.04.pkglist',         'qemu-kvm',         'libvirt-bin' ],
    [ 'ubuntu16.04',   'x86_64',  'kvm.ubuntu16.04.pkglist',         'qemu-kvm',         'libvirt-bin' ],
    [ 'ubuntu18.04',   'x86_64',  'kvm.x86_64.pkglist',              'qemu-system-x86',  'libvirt-daemon-system' ],
    [ 'ubuntu24.04.4', 'x86_64',  'kvm.x86_64.pkglist',              'qemu-system-x86',  'libvirt-daemon-system' ],
    [ 'ubuntu24.04.4', 'ppc64el', 'kvm.ppc64el.pkglist',             'qemu-system-ppc',  'libvirt-daemon-system' ],
    [ 'ubuntu24.04.4', 'ppc64le', 'kvm.ppc64le.pkglist',             'qemu-system-ppc',  'libvirt-daemon-system' ],
    [ 'ubuntu24.04.4', 'riscv64', 'kvm.ubuntu24.04.riscv64.pkglist', 'qemu-system-misc', 'libvirt-daemon-system' ],
    [ 'ubuntu26.04.1', 'x86_64',  'kvm.ubuntu26.04.x86_64.pkglist',  'qemu-system-x86',  'libvirt-daemon-system' ],
    [ 'ubuntu26.04.1', 'ppc64el', 'kvm.ubuntu26.04.ppc64el.pkglist', 'qemu-system-ppc',  'libvirt-daemon-system' ],
    [ 'ubuntu26.04.1', 'ppc64le', 'kvm.ubuntu26.04.ppc64le.pkglist', 'qemu-system-ppc',  'libvirt-daemon-system' ],
);
foreach my $case (@kvm) {
    my ( $os, $arch, $list, $emulator, $libvirt ) = @$case;
    my ( $file, $p ) = resolved( $install, 'kvm', $os, $arch );
    is( $file, $list, "kvm on $os $arch resolves to $list" );
    ok( $p->{$emulator}, "... which installs $emulator" );
    ok( $p->{$libvirt},  "... and $libvirt" );
    ok( !$p->{'qemu-system'}, "... and not the qemu-system fallback" );
    ok( $p->{'qemu-utils'}, "... and qemu-utils" ) if $libvirt eq 'libvirt-daemon-system';
}

# An architecture without a list of its own gets the qemu-system fallback. On 26.04 riscv64
# libvirt-daemon-system depends on qemu-kvm or qemu-system and nothing provides qemu-kvm, so apt
# installs that fallback there whatever the list names, and that release keeps its 26.04 list.
foreach my $case ( [ 'ubuntu24.04.4', 'aarch64', 'kvm.pkglist' ], [ 'ubuntu26.04.1', 'aarch64', 'kvm.ubuntu26.04.pkglist' ],
                   [ 'ubuntu26.04.1', 'riscv64', 'kvm.ubuntu26.04.pkglist' ] ) {
    my ( $os, $arch, $list ) = @$case;
    my ( $file, $p ) = resolved( $install, 'kvm', $os, $arch );
    is( $file, $list, "kvm on $os $arch resolves to $list" );
    ok( $p->{'qemu-system'} && $p->{'qemu-utils'} && $p->{'libvirt-daemon-system'}, '... which names the fallback emulator, qemu-utils and libvirt' );
}

done_testing();
