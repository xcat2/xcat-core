#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use POSIX qw(_exit);
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

my $go_xcat_relative = 'xCAT-server/share/xcat/tools/go-xcat';
my ( $source_go_xcat, $go_xcat_source );
if ( defined $ENV{XCAT_TEST_GO_XCAT} ) {
    $source_go_xcat = $ENV{XCAT_TEST_GO_XCAT};
    die 'XCAT_TEST_GO_XCAT must name a readable regular file'
      unless length($source_go_xcat)
      && -f $source_go_xcat
      && -r _;
    $go_xcat_source = read_file($source_go_xcat);
}
else {
    $source_go_xcat = repo_path($go_xcat_relative);
    plan skip_all => "$source_go_xcat is required"
      unless -f $source_go_xcat && -r _;
    $go_xcat_source = slurp_repo_file($go_xcat_relative);
}

is( system( 'bash', '-n', $source_go_xcat ), 0,
    'go-xcat has valid Bash syntax' );

my $gawk = find_command('gawk');

my @public_scenarios = (
    {
        name       => 'quoted',
        os_release => qq{NAME="Ubuntu"\nID="ubuntu"\nVERSION_ID="24.04"\n},
        redhat     => "Red Hat Enterprise Linux release 9.6 (Plow)\n",
        suse       => "VERSION = 15.6\n",
        expected   => "distro=ubuntu\nversion=24.04\n",
    },
    {
        name       => 'unquoted',
        os_release => "ID_LIKE=rhel\nID=rocky\nVERSION_ID=9.6\n",
        expected   => "distro=rocky\nversion=9.6\n",
    },
    {
        name       => 'single-quoted',
        os_release => "ID='debian'\nVERSION_ID='13'\n",
        expected   => "distro='debian'\nversion='13'\n",
    },
    {
        name          => 'redhat-fallback',
        redhat        => "Red Hat Enterprise Linux release 9.6 (Plow)\n",
        requires_gawk => 1,
        expected      => "distro=rhel\nversion=9.6\n",
    },
    {
        name       => 'suse-release-fallback',
        os_release => "ID=\nVERSION_ID=\n",
        suse       => "VERSION = 15.6\n",
        expected   => "distro=sles\nversion=15.6\n",
    },
    {
        name       => 'suse-brand-fallback',
        os_release => '',
        suse_brand => "VERSION = 12.5\n",
        expected   => "distro=sles\nversion=12.5\n",
    },
    {
        name     => 'missing-release-data',
        expected => "distro=\nversion=\n",
    },
    {
        name       => 'independent-fields',
        os_release => "VERSION_ID=10.1\n",
        redhat     => "Red Hat Enterprise Linux release 8.10 (Ootpa)\n",
        expected   => "distro=rhel\nversion=10.1\n",
    },
    {
        name       => 'redhat-distro-precedes-suse',
        os_release => "VERSION_ID=10.1\n",
        redhat     => "Red Hat Enterprise Linux release 9.6 (Plow)\n",
        suse       => "VERSION = 15.6\n",
        suse_brand => "VERSION = 12.5\n",
        expected   => "distro=rhel\nversion=10.1\n",
    },
    {
        name          => 'redhat-version-precedes-suse',
        redhat        => "Red Hat Enterprise Linux release 9.6 (Plow)\n",
        suse          => "VERSION = 15.6\n",
        suse_brand    => "VERSION = 12.5\n",
        requires_gawk => 1,
        expected      => "distro=rhel\nversion=9.6\n",
    },
    {
        name       => 'suse-release-precedes-brand',
        suse       => "VERSION = 15.6\n",
        suse_brand => "VERSION = 12.5\n",
        expected   => "distro=sles\nversion=15.6\n",
    },
);

for my $scenario (@public_scenarios) {
    SKIP: {
        skip "$scenario->{name} requires gawk", 3
          if $scenario->{requires_gawk} && !defined $gawk;
        my $result = run_case(
            %{$scenario},
            command => ['public'],
            gawk    => $scenario->{requires_gawk} ? $gawk : undef,
        );
        is( $result->{status}, 0, "$scenario->{name} detection completes" );
        is( $result->{stdout}, $scenario->{expected},
            "$scenario->{name} detection preserves distro and version" );
        is( $result->{stderr}, '',
            "$scenario->{name} detection stays quiet" );
    }
}

my $helper_probe = run_case(
    name    => 'helper-probe',
    command => ['helper-present'],
);
die 'os_release_value is required in the repository go-xcat'
  if $helper_probe->{status} != 0 && !defined $ENV{XCAT_TEST_GO_XCAT};

SKIP: {
    skip 'the legacy characterization source has no shared helper', 12
      if $helper_probe->{status} != 0;

    my $quoted_id = run_case(
        name            => 'helper-quoted-id',
        helper_contents => "ID_LIKE=debian\nID=\"ubuntu\"\nVERSION_ID=\"24.04\"\n",
        command         => [ 'value', 'ID' ],
    );
    is( $quoted_id->{status}, 0, 'the helper reads a quoted ID' );
    is( $quoted_id->{stdout}, "ubuntu\n",
        'the helper removes double quotes from an ID' );
    is( $quoted_id->{stderr}, '', 'quoted ID parsing stays quiet' );

    my $unquoted_version = run_case(
        name            => 'helper-unquoted-version',
        helper_contents => "ID=rocky\nVERSION_ID=9.6\n",
        command         => [ 'value', 'VERSION_ID' ],
    );
    is( $unquoted_version->{status}, 0,
        'the helper reads an unquoted version' );
    is( $unquoted_version->{stdout}, "9.6\n",
        'the helper preserves an unquoted version' );
    is( $unquoted_version->{stderr}, '',
        'unquoted version parsing stays quiet' );

    my $missing_key = run_case(
        name            => 'helper-missing-key',
        helper_contents => "ID=ubuntu\n",
        command         => [ 'value', 'VERSION_ID' ],
    );
    is( $missing_key->{status}, 0, 'a missing key is not an error' );
    is( $missing_key->{stdout}, '', 'a missing key produces no value' );
    is( $missing_key->{stderr}, '', 'a missing key stays quiet' );

    my $missing_file = run_case(
        name    => 'helper-missing-file',
        command => [ 'value', 'ID' ],
    );
    isnt( $missing_file->{status}, 0, 'a missing file preserves the AWK failure' );
    is( $missing_file->{stdout}, '', 'a missing file produces no value' );
    is( $missing_file->{stderr}, '', 'a missing file suppresses AWK diagnostics' );
}

done_testing();

sub run_case
{
    my (%option) = @_;
    my $root = tempdir( CLEANUP => 1 );
    my $fixtures = File::Spec->catdir( $root, 'fixtures' );
    my $bin = File::Spec->catdir( $root, 'bin' );
    make_path( $fixtures, $bin );

    my $os_release = File::Spec->catfile( $fixtures, 'os-release' );
    my $redhat_release = File::Spec->catfile( $fixtures, 'redhat-release' );
    my $suse_release = File::Spec->catfile( $fixtures, 'SuSE-release' );
    my $suse_brand = File::Spec->catfile( $fixtures, 'SUSE-brand' );
    my $helper_dir = File::Spec->catdir( $root, 'helper fixture' );
    my $helper_file = File::Spec->catfile( $helper_dir, 'os-release' );
    my $sandboxed_source = File::Spec->catfile( $root, 'go-xcat' );
    my $driver = File::Spec->catfile( $root, 'driver.sh' );
    my $stdout_file = File::Spec->catfile( $root, 'stdout' );
    my $stderr_file = File::Spec->catfile( $root, 'stderr' );

    my $body = $go_xcat_source;
    replace_required( \$body, '/etc/os-release', $os_release );
    replace_required( \$body, '/etc/redhat-release', $redhat_release );
    replace_required( \$body, '/etc/SuSE-release', $suse_release );
    replace_required( \$body, '/etc/SUSE-brand', $suse_brand );
    write_executable( $sandboxed_source, $body );
    write_executable( $driver, <<'DRIVER' );
#!/bin/bash
set -uo pipefail

function_body=$(
    for function_name in \
        os_release_value \
        check_linux_distro \
        check_linux_version
    do
        awk -v name="$function_name" '
            $0 == "function " name "()" { copy = 1 }
            copy { print }
            copy && /^}$/ { exit }
        ' "$GO_XCAT_SOURCE"
    done
)
eval "$function_body"
if [ "$?" -ne 0 ]; then
    printf 'unable to evaluate go-xcat functions\n' >&2
    exit 69
fi
for function_name in check_linux_distro check_linux_version; do
    if ! declare -F "$function_name" >/dev/null; then
        printf 'missing %s\n' "$function_name" >&2
        exit 70
    fi
done

case "$1" in
    public)
        printf 'distro=%s\n' "$(check_linux_distro)"
        printf 'version=%s\n' "$(check_linux_version)"
        ;;
    helper-present)
        declare -F os_release_value >/dev/null
        ;;
    value)
        if ! declare -F os_release_value >/dev/null; then
            printf 'missing os_release_value\n' >&2
            exit 70
        fi
        os_release_value "$2" "$HELPER_OS_RELEASE"
        ;;
    *)
        exit 64
        ;;
esac
DRIVER

    write_file( $os_release, $option{os_release} )
      if defined $option{os_release};
    write_file( $redhat_release, $option{redhat} )
      if defined $option{redhat};
    write_file( $suse_release, $option{suse} )
      if defined $option{suse};
    write_file( $suse_brand, $option{suse_brand} )
      if defined $option{suse_brand};
    if ( defined $option{helper_contents} ) {
        make_path($helper_dir);
        write_file( $helper_file, $option{helper_contents} );
    }
    if ( defined $option{gawk} ) {
        symlink( $option{gawk}, File::Spec->catfile( $bin, 'awk' ) )
          or die "Unable to select gawk: $!";
    }

    local %ENV = (
        %ENV,
        GO_XCAT_SOURCE    => $sandboxed_source,
        HELPER_OS_RELEASE => $helper_file,
        PATH              => "$bin:$ENV{PATH}",
    );

    my $pid = fork();
    die "Unable to fork go-xcat fixture: $!" unless defined $pid;
    if ( $pid == 0 ) {
        open( STDIN, '<', '/dev/null' ) or _exit(126);
        open( STDOUT, '>:raw', $stdout_file ) or _exit(126);
        open( STDERR, '>:raw', $stderr_file ) or _exit(126);
        exec 'bash', $driver, @{ $option{command} } or _exit(127);
    }
    my $reaped = waitpid( $pid, 0 );
    my $raw_status = $?;
    my $status = $reaped == $pid && !( $raw_status & 127 )
      ? $raw_status >> 8
      : 255;

    return {
        status => $status,
        stdout => read_optional($stdout_file),
        stderr => read_optional($stderr_file),
    };
}

sub replace_required
{
    my ( $body_ref, $from, $to ) = @_;
    my $count = $$body_ref =~ s/\Q$from\E/$to/g;
    die "Unable to sandbox $from" unless $count;
    die "Sandbox rewrite left $from in go-xcat"
      if index( $$body_ref, $from ) >= 0;
}

sub write_executable
{
    my ( $file, $contents ) = @_;
    write_file( $file, $contents );
    chmod 0755, $file or die "Unable to make $file executable: $!";
}

sub write_file
{
    my ( $file, $contents ) = @_;
    open( my $fh, '>:raw', $file ) or die "Unable to write $file: $!";
    print {$fh} $contents;
    close($fh) or die "Unable to close $file: $!";
}

sub read_file
{
    my ($file) = @_;
    open( my $fh, '<:raw', $file ) or die "Unable to read $file: $!";
    my $contents = do { local $/; <$fh> };
    close($fh) or die "Unable to close $file: $!";
    return $contents;
}

sub read_optional
{
    my ($file) = @_;
    return '' unless -f $file;
    return read_file($file) // '';
}

sub find_command
{
    my ($command) = @_;
    for my $directory ( File::Spec->path() ) {
        my $candidate = File::Spec->catfile( $directory, $command );
        return $candidate if -f $candidate && -x _;
    }
    return;
}
