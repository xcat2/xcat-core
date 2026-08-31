#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $helper = repo_path('build-utils/source-only.sh');
my $buildcore_helper = repo_path('build-utils/buildcore-source-only.sh');
plan skip_all => 'source-only build helper not found' unless -r $helper;
plan skip_all => 'buildcore source-only helper not found' unless -r $buildcore_helper;
plan skip_all => 'bash not found' unless -x '/bin/bash';

sub _touch {
    write_text( $_[0], '' );
}

sub run_helper {
    my ( $root, $name, $body ) = @_;
    my $script = "$root/$name.sh";
    write_text( $script,
        "#!/bin/bash\nset -e\n. \"$helper\"\n. \"$buildcore_helper\"\n$body\n" );
    my $output = `/bin/bash "$script" 2>&1`;
    return ( $output, $? >> 8 );
}

sub deliver_noarch {
    my ($source_only) = @_;
    my $root = tempdir( CLEANUP => 1 );
    make_path( "$root/rpmbuild/RPMS/noarch", "$root/rpmbuild/SRPMS",
        "$root/dest", "$root/src" );
    _touch("$root/rpmbuild/RPMS/noarch/xCAT-server-2.19.0-snap1.noarch.rpm");
    _touch("$root/rpmbuild/SRPMS/xCAT-server-2.19.0-snap1.src.rpm");
    _touch("$root/dest/xCAT-server-2.19.0-snap0.noarch.rpm");
    _touch("$root/src/xCAT-server-2.19.0-snap0.src.rpm");

    my ( $said, $status ) = run_helper( $root, 'deliver-noarch', <<"SH" );
SRCONLY=$source_only
source=$root/rpmbuild
DESTDIR=$root/dest
SRCDIR=$root/src
NOARCH=noarch
VER=2.19.0
xcat_deliver_noarch_package xCAT-server
SH
    return {
        said      => $said,
        status    => $status,
        delivered => [ sort map { s{.*/}{}r } glob("$root/dest/*") ],
        sources   => [ sort map { s{.*/}{}r } glob("$root/src/*") ],
        left      => [ sort map { s{.*/}{}r } glob("$root/rpmbuild/RPMS/noarch/*") ],
    };
}

sub deliver_arch {
    my ($source_only) = @_;
    my $root = tempdir( CLEANUP => 1 );
    make_path( "$root/rpmbuild/RPMS/riscv64", "$root/rpmbuild/SRPMS",
        "$root/dest", "$root/src" );
    _touch("$root/rpmbuild/RPMS/riscv64/xCAT-2.19.0-snap1.riscv64.rpm");
    _touch("$root/rpmbuild/SRPMS/xCAT-2.19.0-snap1.src.rpm");
    _touch("$root/dest/xCAT-2-snap0.riscv64.rpm");
    _touch("$root/src/xCAT-2-snap0.src.rpm");

    my ( $said, $status ) = run_helper( $root, 'deliver-arch', <<"SH" );
SRCONLY=$source_only
source=$root/rpmbuild
DESTDIR=$root/dest
SRCDIR=$root/src
VER=2.19.0
SHORTSHORTVER=2
xcat_deliver_arch_package xCAT
SH
    return {
        said      => $said,
        status    => $status,
        delivered => [ sort map { s{.*/}{}r } glob("$root/dest/*") ],
        sources   => [ sort map { s{.*/}{}r } glob("$root/src/*") ],
        left      => [ sort map { s{.*/}{}r } glob("$root/rpmbuild/RPMS/riscv64/*") ],
    };
}

sub deliver_genesis {
    my ($source_only) = @_;
    my $root = tempdir( CLEANUP => 1 );
    make_path( "$root/rpmbuild/RPMS/noarch", "$root/rpmbuild/SRPMS",
        "$root/dest", "$root/src" );
    for my $arch (qw(x86_64 ppc64)) {
        _touch("$root/rpmbuild/RPMS/noarch/xCAT-genesis-scripts-$arch-2.19.0-snap1.noarch.rpm");
        _touch("$root/rpmbuild/SRPMS/xCAT-genesis-scripts-$arch-2.19.0-snap1.src.rpm");
        _touch("$root/src/xCAT-genesis-scripts-$arch-2.19.0-snap0.src.rpm");
    }

    my ( $said, $status ) = run_helper( $root, 'deliver-genesis', <<"SH" );
SRCONLY=$source_only
source=$root/rpmbuild
DESTDIR=$root/dest
SRCDIR=$root/src
xcat_deliver_genesis_packages
SH
    return {
        said      => $said,
        status    => $status,
        delivered => [ sort map { s{.*/}{}r } glob("$root/dest/*") ],
        sources   => [ sort map { s{.*/}{}r } glob("$root/src/*") ],
    };
}

sub deliver_tarball {
    my ($source_only) = @_;
    my $root = tempdir( CLEANUP => 1 );
    make_path( "$root/build/xcat-core", "$root/dest" );
    _touch("$root/build/xcat-core/build-input");

    my ( $said, $status ) = run_helper( $root, 'deliver-tarball', <<"SH" );
cd "$root/build"
SRCONLY=$source_only
TARNAME=xCAT-core-test.tar.bz2
XCATCORE=xcat-core
DESTDIR="$root/dest"
DEST=1
OSNAME=Linux
SYSGRP=\$(id -gn)
verboseflag=
xcat_create_binary_tarball
xcat_publish_tarball_link
SH
    return {
        said        => $said,
        status      => $status,
        tarball     => -f "$root/build/xCAT-core-test.tar.bz2" ? 1 : 0,
        link        => -l "$root/xCAT-core-test.tar.bz2" ? 1 : 0,
        link_target => -l "$root/xCAT-core-test.tar.bz2"
          ? readlink("$root/xCAT-core-test.tar.bz2") : undef,
    };
}

sub deliver_embed_link {
    my ($source_only) = @_;
    my $root = tempdir( CLEANUP => 1 );
    make_path( "$root/core", "$root/stage/embed" );
    _touch("$root/core/xCAT-server-2.19.0-snap1.noarch.rpm");

    my ( $said, $status ) = run_helper( $root, 'deliver-embed', <<"SH" );
cd "$root"
SRCONLY=$source_only
EMBED=linux
EMBEDLINK=xCAT-server
DESTDIR="$root/stage/embed"
XCATCORE=core
SHORTSHORTVER=2.19.0
xcat_deliver_embed_links
SH
    my $link = "$root/stage/embed/xCAT-server-2.19.0-snap1.noarch.rpm";
    return {
        said        => $said,
        status      => $status,
        link        => -l $link ? 1 : 0,
        link_target => -l $link ? readlink($link) : undef,
    };
}

my $normal = deliver_noarch('');
is( $normal->{status}, 0, 'normal noarch delivery exits cleanly' );
is_deeply( $normal->{delivered}, ['xCAT-server-2.19.0-snap1.noarch.rpm'],
    'a normal build replaces the delivered binary package' );
is_deeply( $normal->{sources}, ['xCAT-server-2.19.0-snap1.src.rpm'],
    'a normal build replaces the delivered source package' );
is_deeply( $normal->{left}, [],
    'a normal build moves the binary package out of the build tree' );

my $source_only = deliver_noarch('1');
is( $source_only->{status}, 0, 'source-only noarch delivery exits cleanly' );
is_deeply( $source_only->{delivered}, ['xCAT-server-2.19.0-snap0.noarch.rpm'],
    'a source-only build keeps the earlier binary package' );
is_deeply( $source_only->{sources}, ['xCAT-server-2.19.0-snap1.src.rpm'],
    'a source-only build delivers the new source package' );
is_deeply( $source_only->{left}, ['xCAT-server-2.19.0-snap1.noarch.rpm'],
    'a source-only build leaves the binary artifact in the build tree' );

my $normal_arch = deliver_arch('0');
is( $normal_arch->{status}, 0, 'normal architecture delivery exits cleanly' );
is_deeply( $normal_arch->{delivered}, ['xCAT-2.19.0-snap1.riscv64.rpm'],
    'a normal architecture build replaces the delivered binary package' );
is_deeply( $normal_arch->{sources}, ['xCAT-2.19.0-snap1.src.rpm'],
    'a normal architecture build replaces the delivered source package' );

my $source_arch = deliver_arch('yes');
is( $source_arch->{status}, 0, 'source-only architecture delivery exits cleanly' );
is_deeply( $source_arch->{delivered}, ['xCAT-2-snap0.riscv64.rpm'],
    'a source-only architecture build keeps the earlier binary package' );
is_deeply( $source_arch->{sources}, ['xCAT-2.19.0-snap1.src.rpm'],
    'a source-only architecture build delivers the new source package' );

my $source_genesis = deliver_genesis('1');
is( $source_genesis->{status}, 0,
    'source-only Genesis delivery exits cleanly' );
is_deeply( $source_genesis->{delivered}, [],
    'source-only Genesis delivery publishes no binary packages' );
is_deeply(
    $source_genesis->{sources},
    [
        'xCAT-genesis-scripts-ppc64-2.19.0-snap1.src.rpm',
        'xCAT-genesis-scripts-x86_64-2.19.0-snap1.src.rpm',
    ],
    'source-only delivery preserves both architecture-specific Genesis SRPMs',
);

my $normal_tarball = deliver_tarball('0');
is( $normal_tarball->{status}, 0, 'normal tarball delivery exits cleanly' );
ok( $normal_tarball->{tarball}, 'a normal build creates the binary tarball' );
ok( $normal_tarball->{link}, 'a normal build publishes the tarball link' );
is( $normal_tarball->{link_target}, 'build/xCAT-core-test.tar.bz2',
    'the tarball link points to the generated archive' );

my $source_tarball = deliver_tarball('1');
is( $source_tarball->{status}, 0, 'source-only tarball delivery exits cleanly' );
ok( !$source_tarball->{tarball}, 'a source-only build creates no binary tarball' );
ok( !$source_tarball->{link}, 'a source-only build creates no dangling tarball link' );
like( $source_tarball->{said}, qr/Not creating xCAT-core-test\.tar\.bz2/,
    'source-only tarball delivery explains the omission' );

my $normal_embed = deliver_embed_link('');
is( $normal_embed->{status}, 0, 'normal embedded-link delivery exits cleanly' );
ok( $normal_embed->{link}, 'a normal build publishes the embedded-package link' );
is( $normal_embed->{link_target}, '../../core/xCAT-server-2.19.0-snap1.noarch.rpm',
    'the embedded-package link points to the built binary package' );

my $source_embed = deliver_embed_link('1');
is( $source_embed->{status}, 0, 'source-only embedded-link delivery exits cleanly' );
ok( !$source_embed->{link}, 'a source-only build creates no embedded-package link' );

my ( $binary_arches, $binary_arches_status ) = run_helper(
    tempdir( CLEANUP => 1 ),
    'binary-arches',
    "SRCONLY=0\nxcat_rpm_build_arches x86_64 ppc64 ppc64le s390x aarch64\n",
);
is( $binary_arches_status, 0, 'normal architecture selection exits cleanly' );
is(
    $binary_arches,
    "x86_64\nppc64\nppc64le\ns390x\naarch64\n",
    'a binary build keeps every target architecture',
);

my ( $source_xcat_arches, $source_xcat_arches_status ) = run_helper(
    tempdir( CLEANUP => 1 ),
    'source-arches',
    "SRCONLY=true\nxcat_rpm_build_arches x86_64 ppc64 ppc64le s390x aarch64\n",
);
is( $source_xcat_arches_status, 0,
    'source architecture selection exits cleanly' );
is( $source_xcat_arches, "x86_64\n",
    'a source-only xCAT or xCATsn build creates its target-independent SRPM once' );

sub finalized_repositories {
    my ($source_only) = @_;
    my $root = tempdir( CLEANUP => 1 );
    make_path( "$root/binary", "$root/source" );
    my ( $output, $status ) = run_helper( $root, 'repositories', <<"SH" );
function createrepo {
    printf 'indexed %s\n' "\$1"
}
SRCONLY=$source_only
RPMSIGN=0
xcat_finalize_repository binary "$root/binary"
xcat_finalize_repository source "$root/source"
SH
    return ( $output, $status, $root );
}

my ( $binary_repositories, $binary_repositories_status, $binary_root ) =
  finalized_repositories('0');
is( $binary_repositories_status, 0, 'normal repository finalization exits cleanly' );
is(
    $binary_repositories,
    "indexed $binary_root/binary\nindexed $binary_root/source\n",
    'a normal build refreshes both binary and source repositories',
);

my ( $source_repositories, $source_repositories_status, $source_root ) =
  finalized_repositories('1');
is( $source_repositories_status, 0, 'source repository finalization exits cleanly' );
is(
    $source_repositories,
    "indexed $source_root/source\n",
    'a source-only build refreshes only the source repository',
);

sub write_buildinfo {
    my ($source_only) = @_;
    my $root = tempdir( CLEANUP => 1 );
    my $buildinfo = "$root/buildinfo";
    write_text( $buildinfo, "previous binary build\n" );
    my ( $output, $status ) = run_helper( $root, 'buildinfo', <<"SH" );
SRCONLY=$source_only
VER=2.19.0
XCAT_RELEASE=snap1
BUILD_TIME=2026-08-26T12:00:00Z
BUILD_MACHINE=builder.example.test
COMMIT_ID=abc123
COMMIT_ID_LONG=abc123def456
xcat_write_binary_buildinfo "$buildinfo"
SH
    return ( $output, $status, read_text($buildinfo) );
}

my ( $binary_buildinfo_output, $binary_buildinfo_status, $binary_buildinfo ) =
  write_buildinfo('0');
is( $binary_buildinfo_status, 0, 'normal buildinfo generation exits cleanly' );
is( $binary_buildinfo_output, '', 'normal buildinfo generation is quiet' );
is(
    $binary_buildinfo,
    "VERSION=2.19.0\nRELEASE=snap1\nBUILD_TIME=2026-08-26T12:00:00Z\n"
      . "BUILD_MACHINE=builder.example.test\nCOMMIT_ID=abc123\nCOMMIT_ID_LONG=abc123def456\n",
    'a normal build describes the newly built binary bundle',
);

my ( $source_buildinfo_output, $source_buildinfo_status, $source_buildinfo ) =
  write_buildinfo('yes');
is( $source_buildinfo_status, 0, 'source-only buildinfo handling exits cleanly' );
like( $source_buildinfo_output, qr/source-only build makes no binary bundle/,
    'source-only buildinfo handling explains the omission' );
is( $source_buildinfo, "previous binary build\n",
    'a source-only build leaves the previous binary buildinfo untouched' );

done_testing();
