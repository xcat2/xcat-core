#!/usr/bin/env perl
use strict;
use warnings;

use Capture::Tiny qw(capture_merged);
use File::Glob qw(bsd_glob);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use Text::ParseWords qw(shellwords);

use XCAT::Test::File qw(repo_path);

plan skip_all => 'otherpkgs filesystem isolation requires Linux'
  unless $^O eq 'linux';

my $temporary_root = File::Spec->tmpdir();
local %ENV = ( PATH => '/usr/bin:/bin', LC_ALL => 'C' );
my $command_utils = repo_path('perl-xCAT/xCAT/CommandUtils.pm');
require $command_utils;
my $bwrap = xCAT::CommandUtils::find_executable('bwrap');
die "Install bubblewrap to run the otherpkgs test\n" unless $bwrap;
my $postscripts = repo_path('xCAT/postscripts');
my @utilities = qw(bash sh basename dirname cat cp expr grep ls mkdir rm uname wc);
push @utilities, 'coreutils' if xCAT::CommandUtils::find_executable('coreutils');
my @sandbox = (
    $bwrap, '--unshare-all', '--die-with-parent', '--new-session',
    '--ro-bind', '/', '/', '--tmpfs', '/etc', '--tmpfs', '/usr/bin',
    '--tmpfs', '/tmp', '--proc', '/proc', '--dev', '/dev',
    '--setenv', 'PATH', '/usr/bin', '--setenv', 'LC_ALL', 'C',
);
for my $utility (@utilities) {
    my $source = xCAT::CommandUtils::find_executable($utility);
    die "Required utility is unavailable: $utility\n" unless $source;
    push @sandbox, '--ro-bind', $source, "/usr/bin/$utility";
}

my ( $probe_output, $probe_status ) = capture_merged {
    system( @sandbox, '/usr/bin/sh', '-c', 'test ! -e /etc/os-release' );
};
die "Cannot isolate otherpkgs: $probe_output" if $probe_status;

for my $manager (qw(dnf yum)) {
    for my $case (
        { name => 'HTTP and local repositories', verbose => 1, remote => 1 },
        { name => 'mounted repositories', mounted => 1 },
        { name => 'upgrade failure', upgrade_status => 17, verbose => 1 },
        { name => 'install failure', install_status => 23, verbose => 1 },
        { name => 'repository-only mode', repoonly => 1, remote => 1 },
        { name => 'separate package lists', multiple => 1, verbose => 1 },
        { name => 'remote repository without installs', remote => 1, empty => 1 },
      )
    {
        subtest "$manager: $case->{name}" => sub {
            run_case( $manager, $case );
        };
    }
}

done_testing();

sub run_case {
    my ( $manager, $case ) = @_;
    my $fixture = tempdir( DIR => $temporary_root, CLEANUP => 1 );
    make_path("$fixture/bin");
    write_command( "$fixture/bin/logger", "exit 0\n" );
    write_command( "$fixture/bin/dpkg", "exit 1\n" );
    write_command( "$fixture/bin/rpm", '[ "$*" = --version ]' . "\n" );
    write_command(
        "$fixture/bin/mount",
        $case->{mounted}
        ? "printf '%s\\n' 'package-server:/install on /install type nfs (rw)'\n"
        : "exit 0\n"
    );
    write_command( "$fixture/bin/$manager", <<'SH' );
printf '%s\t' "${0##*/}" "SCOPE_ENV=${SCOPE_ENV:-}" "$@" >> /tmp/fixture/commands
printf '\n' >> /tmp/fixture/commands
sequence=$(wc -l < /tmp/fixture/commands)
mkdir "/tmp/fixture/repos.$sequence"
cp /etc/yum.repos.d/*.repo "/tmp/fixture/repos.$sequence/" 2>/dev/null || :
for argument do
    case "$argument" in
        upgrade)
            printf '%s\n' upgrade-result
            exit "$UPGRADE_STATUS"
            ;;
        install)
            printf '%s\n' install-result
            exit "$INSTALL_STATUS"
            ;;
    esac
done
exit 0
SH

    my %environment = (
        OSVER => 'rhel9', ARCH => 'x86_64', UPDATENODE => 1,
        NFSSERVER => 'package-server', HTTPPORT => 80, INSTALLDIR => '/install',
        OTHERPKGDIR => '/install/other', OTHERPKGS_INDEX => 1,
        OTHERPKGS1 => $case->{empty} ? '' : 'alpha/tool-one,beta/tool-two',
        ENVLIST1 => 'SCOPE_ENV=first', VERBOSE => $case->{verbose} ? 1 : '',
        UPGRADE_STATUS => $case->{upgrade_status} || 0,
        INSTALL_STATUS => $case->{install_status} || 0,
    );
    $environment{OTHERPKGDIR} =
      'https://packages.example.invalid/extra,/install/other' if $case->{remote};
    if ( $case->{multiple} ) {
        @environment{qw(OTHERPKGS_INDEX OTHERPKGS1 OTHERPKGS2 ENVLIST2)} =
          ( 2, 'alpha/tool-one,beta/tool-two', 'gamma/tool-three', 'SCOPE_ENV=second' );
    }

    my @command = (
        @sandbox, '--bind', $fixture, '/tmp/fixture',
        '--ro-bind', $postscripts, '/tmp/postscripts', '--chdir', '/tmp/fixture',
    );
    for my $tool (qw(logger dpkg rpm mount), $manager) {
        push @command, '--ro-bind', "$fixture/bin/$tool", "/usr/bin/$tool";
    }
    for my $key ( sort keys %environment ) {
        push @command, '--setenv', $key, $environment{$key};
    }
    push @command, '/usr/bin/sh', '-c', <<'SH', 'otherpkgs-test';
/usr/bin/bash /tmp/postscripts/otherpkgs "$@"
status=$?
mkdir /tmp/fixture/final-repos
cp /etc/yum.repos.d/*.repo /tmp/fixture/final-repos/ 2>/dev/null || :
exit "$status"
SH
    push @command, '--repoonly' if $case->{repoonly};

    my ( $output, $status ) = capture_merged { system(@command) };
    is( $status, ( $case->{upgrade_status} || $case->{install_status} || 0 ) << 8,
        'the postscript returns the package-manager status' ) or diag($output);
    ok( -f "$fixture/commands", 'the real postscript reaches the package manager' );
    return unless -f "$fixture/commands";

    my @calls = map { [ split /\t/ ] } split /\n/, read_text("$fixture/commands");
    my @transactions;
    for my $index ( 0 .. $#calls ) {
        my $call = $calls[$index];
        my @operands = grep { !/^-/ } @{$call}[ 2 .. $#{$call} ];
        next if @operands && ( $operands[0] eq 'clean' || $operands[0] eq 'list' );
        push @transactions, [ $index + 1, $call ];
    }
    my @expected;
    my @groups = $case->{multiple}
      ? ( [ first => qw(tool-one tool-two) ], [ second => 'tool-three' ] )
      : ( [ first => ( $case->{empty} ? () : qw(tool-one tool-two) ) ] );
    unless ( $case->{repoonly} ) {
        for my $group (@groups) {
            my ( $label, @packages ) = @{$group};
            push @expected,
              [ $manager, "SCOPE_ENV=$label", '-y', '--disablerepo=*',
                '--enablerepo=xcat-otherpkgs*', 'upgrade' ];
            push @expected, [ $manager, "SCOPE_ENV=$label", '-y', 'install', @packages ]
              if @packages;
        }
    }
    is_deeply( [ map { $_->[1] } @transactions ], \@expected,
        'only upgrades are repository-scoped; installs retain dependency repositories' );

    my @printed = map { [ shellwords($_) ] }
      grep { /^SCOPE_ENV=/ } split /\n/, $output;
    my @expected_printed = $case->{verbose}
      ? map { [ $_->[1], $_->[0], @{$_}[ 2 .. $#{$_} ] ] } @expected : ();
    is_deeply( \@printed, \@expected_printed,
        'verbose commands describe the executed transactions and quiet mode omits them' );

    for my $transaction (@transactions) {
        my ( $sequence, $call ) = @{$transaction};
        my @paths = $case->{multiple}
          ? ( $call->[1] eq 'SCOPE_ENV=first' ? qw(alpha beta) : 'gamma' )
          : ( $case->{empty} ? () : qw(alpha beta) );
        check_repositories( "$fixture/repos.$sequence", $case, \@paths );
    }
    my @final_paths = $case->{multiple} ? ('gamma')
      : $case->{empty} ? () : qw(alpha beta);
    check_repositories( "$fixture/final-repos", $case, \@final_paths );
    if ( $case->{verbose} && !$case->{repoonly} ) {
        like( $output, qr/^upgrade-result$/m, 'upgrade output reaches the caller' );
        like( $output, qr/^install-result$/m, 'install output reaches the caller' )
          unless $case->{empty};
    }
}

sub check_repositories {
    my ( $directory, $case, $paths ) = @_;
    my $base = $case->{mounted} ? 'file://' : 'http://package-server:80';
    my @expected = (
        [ 'xCAT-rhel9-path0', "$base/install/rhel9/x86_64/BaseOS", '1' ],
        [ 'xCAT-rhel9-path1', "$base/install/rhel9/x86_64/AppStream", '1' ],
    );
    my $index = 0;
    push @expected, [ 'xcat-otherpkgs' . $index++,
        'https://packages.example.invalid/extra', '1' ] if $case->{remote};
    push @expected, [ 'xcat-otherpkgs' . $index++, "$base/install/other/$_", '1' ]
      for @{$paths};
    my @actual;
    for my $file ( bsd_glob("$directory/*.repo") ) {
        my $contents = read_text($file);
        my @sections = $contents =~ /^\[([^\]\n]+)\]$/mg;
        my @urls = $contents =~ /^baseurl=(.*?)\s*$/mg;
        my @enabled = $contents =~ /^enabled=(.*?)\s*$/mg;
        my @gpgcheck = $contents =~ /^gpgcheck=(.*?)\s*$/mg;
        push @actual, [ @sections, @urls, @enabled, @gpgcheck ];
    }
    is_deeply(
        [ sort { $a->[0] cmp $b->[0] } @actual ],
        [ map { [ @{$_}, '0' ] } sort { $a->[0] cmp $b->[0] } @expected ],
        'generated repositories match the upgrade scope and retain the OS repositories'
    );
}

sub write_command {
    my ( $file, $body ) = @_;
    write_text( $file, "#!/usr/bin/sh\n$body" );
    chmod 0755, $file or die "Cannot make $file executable: $!";
}
