#!/usr/bin/env perl
use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $postscripts = repo_path(File::Spec->catdir('xCAT', 'postscripts'));
my $library = File::Spec->catfile( $postscripts, 'xcatpkgutils.sh' );
my $loader = File::Spec->catfile( $postscripts, 'xcatpkgutils-loader.sh' );

my $tmpdir = tempdir( CLEANUP => 1 );
my $dnf_first = File::Spec->catdir( $tmpdir, 'dnf-first' );
my $yum_only = File::Spec->catdir( $tmpdir, 'yum-only' );
my $neither = File::Spec->catdir( $tmpdir, 'neither' );
make_path( $dnf_first, $yum_only, $neither );
write_executable( File::Spec->catfile( $dnf_first, 'dnf' ), "#!/bin/sh\n" );
write_executable( File::Spec->catfile( $dnf_first, 'yum' ), "#!/bin/sh\n" );
write_executable( File::Spec->catfile( $yum_only, 'yum' ), "#!/bin/sh\n" );

SKIP: {
    skip 'the shared discovery helper is introduced by the production commit', 3
      unless helper_available();
    is_deeply(
        [ run_helper($dnf_first) ],
        [ 0, "dnf\n" ],
        'dnf is preferred when both RPM package managers are executable'
    );
    is_deeply(
        [ run_helper($yum_only) ],
        [ 0, "yum\n" ],
        'yum is used when dnf is unavailable'
    );
    is_deeply(
        [ run_helper($neither) ],
        [ 1, '' ],
        'discovery fails without output when neither package manager is executable'
    );
}

my $caller_dir = File::Spec->catdir( $tmpdir, 'callers' );
my $test_bin = File::Spec->catdir( $caller_dir, 'bin' );
make_path($test_bin);
stage_callers($caller_dir);
write_executable( File::Spec->catfile( $test_bin, 'logger' ), "#!/bin/sh\nexit 0\n" );
write_executable( File::Spec->catfile( $test_bin, 'mount' ), "#!/bin/sh\nexit 1\n" );
write_executable(
    File::Spec->catfile( $test_bin, 'uname' ),
    "#!/bin/sh\nprintf '%s\\n' Linux\n"
);
write_executable( File::Spec->catfile( $test_bin, 'dpkg' ), "#!/bin/sh\nexit 1\n" );
write_executable(
    File::Spec->catfile( $test_bin, 'rpm' ),
    <<'SH'
#!/bin/sh
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
);
write_executable( File::Spec->catfile( $test_bin, 'dnf' ), "#!/bin/sh\nexit 0\n" );
write_executable( File::Spec->catfile( $test_bin, 'yum' ), "#!/bin/sh\nexit 0\n" );
write_executable( File::Spec->catfile( $test_bin, 'zypper' ), "#!/bin/sh\nexit 0\n" );

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
    PATH       => "$test_bin:$ENV{PATH}",
);

for my $scenario (
    [ dnf => 'dnf||||' ],
    [ yum => 'yum||||' ],
  )
{
    my ( $name, $expected_state ) = @{$scenario};
    my ( $status, $output, $state ) = run_caller( 'ospkgs', $name );
    is( $status, 0, "ospkgs completes with $name" ) or diag($output);
    is( $state, $expected_state, "ospkgs selects $name" );
}

my ( $ospkgs_status, $ospkgs_output, $ospkgs_state ) =
  run_caller( 'ospkgs', 'neither' );
is( $ospkgs_status, 1, 'ospkgs still stops when neither dnf nor yum is available' );
is( $ospkgs_state, '||||', 'ospkgs leaves package-manager state empty on failure' );
like(
    $ospkgs_output,
    qr/^Please install yum or dnf on node1\.$/m,
    'ospkgs retains its package-manager installation error'
);

for my $scenario (
    [ dnf     => 'dnf|1|1|0|rpm -Uvh --replacepkgs' ],
    [ yum     => 'yum|1|1|0|rpm -Uvh --replacepkgs' ],
    [ zypper  => '|1|0|1|rpm -Uvh --replacepkgs' ],
    [ rpm      => '|1|0|0|rpm -Uvh --replacepkgs' ],
  )
{
    my ( $name, $expected_state ) = @{$scenario};
    my ( $status, $output, $state ) = run_caller( 'otherpkgs', $name );
    is( $status, 0, "otherpkgs completes with the $name discovery outcome" )
      or diag($output);
    is( $state, $expected_state, "otherpkgs retains the $name discovery outcome" );
}

like(
    read_text( File::Spec->catfile( $caller_dir, 'otherpkgs-rpm-command.trace' ) ),
    qr/^-Uvh --replacepkgs package-test\*$/m,
    'otherpkgs executes its raw RPM installation fallback'
);

done_testing();

sub run_helper {
    my ($directory) = @_;
    return run_command(
        '/bin/sh', '-c', '. "$1"; xcat_find_rpm_package_manager "$2"',
        'package-manager-discovery-test', $library, $directory
    );
}

sub helper_available {
    return system(
        '/bin/sh', '-c',
        '. "$1"; command -v xcat_find_rpm_package_manager >/dev/null 2>&1',
        'package-manager-discovery-test', $library
    ) == 0;
}

sub run_caller {
    my ( $caller, $scenario ) = @_;
    my $trace = File::Spec->catfile( $caller_dir, "$caller-$scenario.trace" );
    local %ENV = ( %ENV, %common_env );
    $ENV{XCAT_PM_SCENARIO} = $scenario;
    $ENV{XCAT_PM_STATE_TRACE} = $trace;

    my @arguments;
    if ( $caller eq 'ospkgs' ) {
        delete @ENV{qw(OTHERPKGS OTHERPKGS_INDEX UPDATENODE)};
        $ENV{OSPKGS} = 'package-test';
        @arguments = ('--keeprepo');
    } else {
        delete @ENV{qw(OSPKGS OTHERPKGS)};
        $ENV{OSVER} = 'custom9';
        if ( $scenario eq 'rpm' ) {
            $ENV{OTHERPKGS1} = 'package-test';
            $ENV{OTHERPKGS_INDEX} = 1;
            $ENV{XCAT_RPM_TRACE} = File::Spec->catfile(
                $caller_dir, 'otherpkgs-rpm-command.trace'
            );
        } else {
            delete @ENV{qw(OTHERPKGS1 XCAT_RPM_TRACE)};
            $ENV{OTHERPKGS_INDEX} = 0;
        }
        $ENV{UPDATENODE} = 1;
    }

    my ( $status, $output ) = run_command(
        File::Spec->catfile( $caller_dir, $caller ), @arguments
    );
    my $state = read_text($trace);
    chomp($state);
    return ( $status, $output, $state );
}

sub stage_callers {
    my ($directory) = @_;
    for my $source (
        $library, $loader,
        map { File::Spec->catfile( $postscripts, $_ ) } qw(ospkgs otherpkgs)
      )
    {
        my $filename = ( File::Spec->splitpath($source) )[2];
        my $destination = File::Spec->catfile( $directory, $filename );
        copy( $source, $destination )
          or die "Unable to stage $source as $destination: $!";
        chmod 0755, $destination
          or die "Unable to make $destination executable: $!";
    }
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
