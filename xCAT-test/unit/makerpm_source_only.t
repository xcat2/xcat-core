#!/usr/bin/env perl
use strict;
use warnings;

use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $helper = repo_path('build-utils/source-only.sh');
plan skip_all => 'source-only build helper not found' unless -r $helper;
plan skip_all => 'bash not found' unless -x '/bin/bash';

my $dir = tempdir( CLEANUP => 1 );
my $sequence = 0;

sub run_shell {
    my ($body) = @_;
    my $script = "$dir/run-" . ++$sequence . '.sh';
    write_text( $script, "#!/bin/bash\nset -e\n. \"$helper\"\n$body\n" );
    my $output = `/bin/bash "$script" 2>&1`;
    return ( $output, $? >> 8 );
}

my @modes = (
    [ 'unset',       'unset SRCONLY', '-ba -ta' ],
    [ 'empty',       'SRCONLY=',      '-ba -ta' ],
    [ 'SRCONLY=0',   'SRCONLY=0',     '-ba -ta' ],
    [ 'SRCONLY=no',  'SRCONLY=no',    '-ba -ta' ],
    [ 'SRCONLY=1',   'SRCONLY=1',     '-bs -ts' ],
    [ 'SRCONLY=yes', 'SRCONLY=yes',   '-bs -ts' ],
    [ 'SRCONLY=true', 'SRCONLY=true', '-bs -ts' ],
);
foreach my $case (@modes) {
    my ( $name, $assignment, $expected ) = @{$case};
    my ( $got, $rc ) = run_shell(<<"SH");
$assignment
xcat_configure_rpm_build_mode Linux
echo "\$SPECBUILD \$TARBUILD"
SH
    chomp $got;
    is( $got, $expected, "$name selects '$expected'" );
    is( $rc, 0, "$name exits cleanly" );
}

my ( $aix, $aix_rc ) = run_shell(<<'SH');
SRCONLY=1
xcat_configure_rpm_build_mode AIX
SH
isnt( $aix_rc, 0, 'a source-only build on AIX stops with an error' );
like( $aix, qr/not supported on AIX/, 'the error names AIX' );

my ( $aix_default, $aix_default_rc ) = run_shell(<<'SH');
unset SRCONLY
xcat_configure_rpm_build_mode AIX
echo "$SPECBUILD $TARBUILD"
SH
is( $aix_default_rc, 0, 'a normal build on AIX is unchanged' );
like( $aix_default, qr/^-ba -ta$/m, 'a normal AIX build keeps its flags' );

my ( $binary_message, undef ) = run_shell(<<'SH');
SPECBUILD=-ba
RPMROOT=/build
EMBEDTXT=
xcat_announce_build xCAT-server-2.19.0 /build/RPMS/noarch/xCAT-server-2.19.0-snap\*.noarch.rpm
SH
like( $binary_message, qr{/build/RPMS/noarch/xCAT-server-2\.19\.0-snap\*\.noarch\.rpm},
    'a normal build names the binary package' );
unlike( $binary_message, qr/src\.rpm/, 'a normal build names no source package' );

my ( $source_message, undef ) = run_shell(<<'SH');
SPECBUILD=-bs
RPMROOT=/build
EMBEDTXT=
xcat_announce_build xCAT-server-2.19.0 /build/RPMS/noarch/xCAT-server-2.19.0-snap\*.noarch.rpm
SH
like( $source_message, qr{/build/SRPMS/xCAT-server-2\.19\.0-snap\*\.src\.rpm},
    'a source-only build names the source package' );
unlike( $source_message, qr{RPMS/noarch}, 'a source-only build names no binary package' );

my ( $build_calls, $build_calls_rc ) = run_shell(<<'SH');
function rpmbuild {
    printf 'rpmbuild'
    printf ' <%s>' "$@"
    printf '\n'
}
QUIET=--quiet
SRCONLY=1
xcat_configure_rpm_build_mode Linux
xcat_rpmbuild_spec package.spec --target riscv64 --define 'version 2.19.0'
xcat_rpmbuild_tar package.tar.gz --define 'version 2.19.0'
SH
is( $build_calls_rc, 0, 'source-only rpm wrappers exit cleanly' );
like( $build_calls, qr/^rpmbuild <--quiet> <-bs> <package\.spec>/m,
    'spec builds receive the source-only mode' );
like( $build_calls, qr/^rpmbuild <--quiet> <-ts> <package\.tar\.gz>/m,
    'tar builds receive the source-only mode' );
unlike( $build_calls, qr/<-ba>|<-ta>/, 'source-only wrappers pass no binary mode' );

my ( $ironic, $ironic_rc ) = run_shell(<<'SH');
SRCONLY=1
xcat_require_binary_build xCAT-OpenStack-ironic
SH
isnt( $ironic_rc, 0, 'the ironic package refuses source-only mode' );
like( $ironic, qr/not supported for xCAT-OpenStack-ironic/,
    'the ironic error names the package' );

my ( undef, $ironic_normal_rc ) = run_shell(<<'SH');
SRCONLY=0
xcat_require_binary_build xCAT-OpenStack-ironic
SH
is( $ironic_normal_rc, 0, 'the ironic package still accepts a normal build' );

done_testing();
