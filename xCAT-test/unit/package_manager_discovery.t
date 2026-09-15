#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source qw(repo_path slurp_repo_file scratch_dir);

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::Sandbox qw(replace_required assert_no_host_paths stub_bin run_confined);

my $postscripts = repo_path( File::Spec->catdir( 'xCAT', 'postscripts' ) );
my $library     = File::Spec->catfile( $postscripts, 'xcatpkgutils.sh' );

my $tmpdir    = tempdir( CLEANUP => 1 );
my $dnf_first = File::Spec->catdir( $tmpdir, 'dnf-first' );
my $yum_only  = File::Spec->catdir( $tmpdir, 'yum-only' );
my $neither   = File::Spec->catdir( $tmpdir, 'neither' );
make_path( $dnf_first, $yum_only, $neither );
write_executable( File::Spec->catfile( $dnf_first, 'dnf' ), "#!/bin/sh\n" );
write_executable( File::Spec->catfile( $dnf_first, 'yum' ), "#!/bin/sh\n" );
write_executable( File::Spec->catfile( $yum_only,  'yum' ), "#!/bin/sh\n" );

SKIP: {
    skip 'the shared discovery helper is introduced by the production commit', 3
      unless helper_available();
    is_deeply( [ run_helper($dnf_first) ], [ 0, "dnf\n" ], 'dnf is preferred when both RPM package managers are executable' );
    is_deeply( [ run_helper($yum_only) ],  [ 0, "yum\n" ], 'yum is used when dnf is unavailable' );
    is_deeply( [ run_helper($neither) ],   [ 1, '' ],      'discovery fails without output when neither package manager is executable' );
}

# ospkgs and otherpkgs write repository files under /etc, and otherpkgs downloads into /xcatpost
# and /tmp/postage when it cannot mount the install tree. Every such path in the staged copies
# points into $root, and a path the rewrites miss stops the test before the scripts run.
my $caller_dir = File::Spec->catdir( $tmpdir, 'callers' );
my $root       = File::Spec->catdir( $caller_dir, 'root' );
make_path( map { File::Spec->catdir( $root, $_ ) } qw(etc/yum.repos.d etc/apt/sources.list.d xcatpost tmp) );
stage_callers($caller_dir);

my $wget_trace = File::Spec->catfile( $caller_dir, 'wget.trace' );
my $bin        = stub_bin(
    dir   => File::Spec->catdir( $caller_dir, 'bin' ),
    tools => [qw(bash sh expr grep dirname sed rm cat mkdir mv cut)],
    stubs => {
        logger => 'exit 0',
        mount  => 'exit 1',
        uname  => "printf '%s\\n' Linux",
        dpkg   => 'exit 1',
        dnf    => 'exit 0',
        yum    => 'exit 0',
        zypper => 'exit 0',
        # The install tree is not mounted, so otherpkgs downloads it. The download fails, as
        # it does for a server the node cannot reach.
        wget => qq{printf '%s\\n' "\$*" >> '$wget_trace'\nexit 4},
        rpm  => <<'SH',
case "$*" in
    --version) exit 0 ;;
    -q\ zypper)
        [ "$XCAT_PM_SCENARIO" = zypper ] && exit 0
        exit 1
        ;;
esac
if [ -n "${XCAT_RPM_TRACE:-}" ]; then
    printf '%s\n' "$*" >> "$XCAT_RPM_TRACE"
    exit 0
fi
exit 1
SH
    },
);

my $bash_env = File::Spec->catfile( $caller_dir, 'bash-env.sh' );
# Fake only the absolute executable probes; the staged callers and library stay unchanged.
write_text(
    $bash_env,
    <<'SH'
function [
{
    case "$1:$2:$XCAT_PM_SCENARIO" in
        -x:/usr/bin/dnf:dnf) return 0 ;;
        -x:/usr/bin/dnf:*) return 1 ;;
        -x:/usr/bin/yum:dnf|-x:/usr/bin/yum:yum) return 0 ;;
        -x:/usr/bin/yum:*) return 1 ;;
    esac
    builtin [ "$@"
}

exit()
{
    if builtin [ -n "${XCAT_PM_STATE_TRACE:-}" ]; then
        printf '%s|%s|%s|%s|%s\n' "${yumcmd:-}" "${hasrpm:-}" "${hasyum:-}" \
            "${haszypper:-}" "${supdatecommand:-}" \
            > "$XCAT_PM_STATE_TRACE"
    fi
    builtin exit "$@"
}
SH
);

my %common_env = (
    ARCH       => 'x86_64',
    BASH_ENV   => $bash_env,
    INSTALLDIR => 'INSTALLDIR',
    NFSSERVER  => 'package-test-server',
    NODE       => 'node1',
    OSVER      => 'rocky9',
);

for my $scenario ( [ dnf => 'dnf||||' ], [ yum => 'yum||||' ] ) {
    my ( $name, $expected_state ) = @{$scenario};
    my ( $status, $output, $state ) = run_caller( 'ospkgs', $name );
    is( $status, 0, "ospkgs completes with $name" ) or diag($output);
    is( $state, $expected_state, "ospkgs selects $name" );
}

# ospkgs writes one repository per OS package directory. They are written into the sandbox root,
# where they can be read, and not into the host's /etc/yum.repos.d.
{
    my %expected = (
        0 => 'baseurl=http://package-test-server:INSTALLDIR/rocky9/x86_64/BaseOS',
        1 => 'baseurl=http://package-test-server:INSTALLDIR/rocky9/x86_64/AppStream',
    );
    foreach my $index ( sort keys %expected ) {
        my $repo = File::Spec->catfile( $root, 'etc', 'yum.repos.d', "xCAT-rocky9-path$index.repo" );
        ok( -f $repo, "ospkgs writes xCAT-rocky9-path$index.repo inside the sandbox root" );
        like( -f $repo ? read_text($repo) : '', qr/^\Q$expected{$index}\E$/m,
            "xCAT-rocky9-path$index.repo points at the OS package directory" );
    }
}

my ( $ospkgs_status, $ospkgs_output, $ospkgs_state ) = run_caller( 'ospkgs', 'neither' );
is( $ospkgs_status, 1, 'ospkgs still stops when neither dnf nor yum is available' );
is( $ospkgs_state, '||||', 'ospkgs leaves package-manager state empty on failure' );
like( $ospkgs_output, qr/^Please install yum or dnf on node1\.$/m, 'ospkgs retains its package-manager installation error' );

for my $scenario (
    [ dnf    => 'dnf|1|1|0|rpm -Uvh --replacepkgs' ],
    [ yum    => 'yum|1|1|0|rpm -Uvh --replacepkgs' ],
    [ zypper => '|1|0|1|rpm -Uvh --replacepkgs' ],
    [ rpm    => '|1|0|0|rpm -Uvh --replacepkgs' ],
  )
{
    my ( $name, $expected_state ) = @{$scenario};
    my ( $status, $output, $state ) = run_caller( 'otherpkgs', $name );
    is( $status, 0, "otherpkgs completes with the $name discovery outcome" ) or diag($output);
    is( $state, $expected_state, "otherpkgs retains the $name discovery outcome" );
}

like(
    read_text( File::Spec->catfile( $caller_dir, 'otherpkgs-rpm-command.trace' ) ),
    qr/^-Uvh --replacepkgs package-test\*$/m,
    'otherpkgs executes its raw RPM installation fallback'
);
like( -f $wget_trace ? read_text($wget_trace) : '', qr{package-test-server},
    'otherpkgs downloads through the wget stub, not the network' );

done_testing();

sub run_helper {
    my ($directory) = @_;
    return run_command( '/bin/sh', '-c', '. "$1"; xcat_find_rpm_package_manager "$2"',
        'package-manager-discovery-test', $library, $directory );
}

sub helper_available {
    return system( '/bin/sh', '-c', '. "$1"; command -v xcat_find_rpm_package_manager >/dev/null 2>&1',
        'package-manager-discovery-test', $library ) == 0;
}

sub run_caller {
    my ( $caller, $scenario ) = @_;
    my $trace = File::Spec->catfile( $caller_dir, "$caller-$scenario.trace" );
    my %env   = (
        %common_env,
        XCAT_PM_SCENARIO    => $scenario,
        XCAT_PM_STATE_TRACE => $trace,
    );

    my @arguments;
    if ( $caller eq 'ospkgs' ) {
        $env{OSPKGS} = 'package-test';
        @arguments = ('--keeprepo');
    } else {
        $env{OSVER}      = 'custom9';
        $env{UPDATENODE} = 1;
        if ( $scenario eq 'rpm' ) {
            $env{OTHERPKGS1}      = 'package-test';
            $env{OTHERPKGS_INDEX} = 1;
            $env{XCAT_RPM_TRACE}  = File::Spec->catfile( $caller_dir, 'otherpkgs-rpm-command.trace' );
        } else {
            $env{OTHERPKGS_INDEX} = 0;
        }
    }

    my ( $status, $output ) = run_confined(
        cmd      => [ File::Spec->catfile( $caller_dir, $caller ), @arguments ],
        bin      => $bin,
        env      => \%env,
        writable => [$caller_dir],
        dir      => $caller_dir,
    );
    my $state = -f $trace ? read_text($trace) : '';
    chomp($state);
    return ( $status, $output, $state );
}

#-------------------------------------------------------------------------------

=head3 stage_callers

    Descriptions: Copies ospkgs, otherpkgs and the helper library into a directory, with every
                  host path the two callers name moved under the sandbox root.
    Arguments:
        $directory - the directory to stage into
    Returns: nothing

=cut

#-------------------------------------------------------------------------------
sub stage_callers {
    my ($directory) = @_;

    my %rewrites = (
        ospkgs => [
            [ '/etc/yum.repos.d',      "$root/etc/yum.repos.d" ],
            [ '/etc/apt/sources.list', "$root/etc/apt/sources.list" ],
            [ '="/install"',           "=\"$root/install\"" ],
        ],
        otherpkgs => [
            [ '/etc/yum.repos.d',        "$root/etc/yum.repos.d" ],
            [ '/etc/apt/sources.list.d', "$root/etc/apt/sources.list.d" ],
            [ '/etc/os-release',         "$root/etc/os-release" ],
            [ '/xcatpost',               "$root/xcatpost" ],
            [ '/tmp/postage',            "$root/tmp/postage" ],
            [ '/tmp/wget.log',           "$root/tmp/wget.log" ],
            [ 'repo_base="/tmp"',        "repo_base=\"$root/tmp\"" ],
            [ '="/install"',             "=\"$root/install\"" ],
        ],
    );

    foreach my $name (qw(xcatpkgutils.sh xcatpkgutils-loader.sh ospkgs otherpkgs)) {
        my $script = slurp_repo_file( File::Spec->catfile( 'xCAT', 'postscripts', $name ) );
        foreach my $rewrite ( @{ $rewrites{$name} || [] } ) {
            replace_required( \$script, @$rewrite );
        }
        assert_no_host_paths(
            $script,
            root     => $root,
            prefixes => [qw(/etc /var /root /home /boot /opt /srv /install /tftpboot /xcatpost /tmp)],
            allow    => [qr/^\s*#/],
        );
        write_executable( File::Spec->catfile( $directory, $name ), $script );
    }

    return;
}

sub write_executable {
    my ( $path, $contents ) = @_;
    write_text( $path, $contents );
    chmod 0755, $path or die "Unable to make $path executable: $!";
}

sub run_command {
    my (@command) = @_;
    my $pid = open( my $pipe, '-|' );
    die "Unable to fork for @command: $!" unless defined($pid);
    if ( $pid == 0 ) {
        open( STDERR, '>&', STDOUT ) or die "Unable to merge stderr: $!";
        exec { $command[0] } @command;
        die "Unable to execute @command: $!";
    }

    my $output = do { local $/; <$pipe> } // '';
    close($pipe);
    return ( $? >> 8, $output );
}
