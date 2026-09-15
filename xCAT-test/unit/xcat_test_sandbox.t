#!/usr/bin/env perl
# XCAT::Test::Sandbox must fail closed: a rewrite that matches nothing, a host path left in a
# script and a command nobody stubbed each stop the test instead of reaching the host. As root,
# a confined command cannot write host paths or see the host's network.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source qw(repo_path scratch_dir);

use File::Spec;
use File::Temp ();
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use Test::More;
use XCAT::Test::Sandbox qw(
  replace_required replace_required_re assert_no_host_paths
  stub_bin confined_command run_confined confinement
);

# --- replace_required -----------------------------------------------------------------------
{
    my $root = '/scratch/root';
    my $text = "rm -f /etc/sudoers.d/xcat\ngrep -q x /etc/sudoers\n";

    is( replace_required( \$text, '/etc/sudoers', "$root/etc/sudoers" ), 2,
        'every occurrence is rewritten and counted' );
    unlike( $text, qr{(?<!\Q$root\E)/etc/sudoers},
        'no unrewritten occurrence is left, though the replacement contains the original' );
    is( $text, "rm -f $root/etc/sudoers.d/xcat\ngrep -q x $root/etc/sudoers\n", 'the text is rewritten exactly' );

    my $unrelated = "echo hello\n";
    ok( !eval { replace_required( \$unrelated, '/etc/hosts', "$root/etc/hosts" ); 1 },
        'a rewrite that matches nothing dies' );
    like( $@, qr{'/etc/hosts' does not occur}, 'the error names the string that did not occur' );
    is( $unrelated, "echo hello\n", 'a failed rewrite leaves the text unchanged' );
}

# --- replace_required_re --------------------------------------------------------------------
{
    my $text = "port=3002\nexec 3<>/dev/tcp/\$xm/\$port\nport=3002\n";

    is( replace_required_re( \$text, qr/port=3002/, 'port=0' ), 2, 'every match is rewritten and counted' );
    is( $text, "port=0\nexec 3<>/dev/tcp/\$xm/\$port\nport=0\n", 'the text is rewritten exactly' );
    ok( !eval { replace_required_re( \$text, qr/port=3002/, 'port=0' ); 1 }, 'a pattern that no longer matches dies' );
}

# --- assert_no_host_paths -------------------------------------------------------------------
{
    my $root = '/scratch/root';

    ok( eval { assert_no_host_paths( "cat $root/etc/hosts\n", root => $root ); 1 }, 'paths under the root pass' )
        or diag($@);
    ok( !eval { assert_no_host_paths( "set -e\ncat /etc/hosts\n", root => $root ); 1 },
        'an absolute host path dies' );
    like( $@, qr{^\s+2: cat /etc/hosts$}m, 'the error names the line and its number' );
    ok( !eval { assert_no_host_paths( "etcdir=/etc; rm -f \"\$etcdir/resolv.conf\"\n", root => $root ); 1 },
        'a host path respelled without a trailing slash dies' );
    ok( eval { assert_no_host_paths( "touch \$MNTDIR/etc/sysconfig/x \${ROOT}/etc/y\n", root => $root ); 1 },
        'a path after a variable the test sets passes' )
        or diag($@);
    ok( eval { assert_no_host_paths( "ls /var/tmp/x\n", root => $root, allow => [qr{/var/tmp/}] ); 1 },
        'an allowed line passes' )
        or diag($@);
    ok( !eval { assert_no_host_paths( "cat /xcatpost/xcatflowrequest\n", root => $root ); 1 },
        '/xcatpost counts as a host path' );

    # A scratch root lives under /tmp or /var/tmp, which a caller may also scan.
    my $tmp_root = '/tmp/xcat-unit-scratch/root';
    ok( eval {
            assert_no_host_paths( "cd $tmp_root/tmp/postage && mv x $tmp_root/xcatpost\n",
                root => $tmp_root, prefixes => [qw(/tmp /xcatpost)] );
            1;
        },
        'a root that sits under a scanned prefix does not flag its own rewrites' )
        or diag($@);
    ok( !eval {
            assert_no_host_paths( "cd $tmp_root/tmp/postage && rm -rf /tmp/postage/*\n",
                root => $tmp_root, prefixes => [qw(/tmp /xcatpost)] );
            1;
        },
        'a host path on the same line as a rewrite still dies' );
}

# --- stub_bin -------------------------------------------------------------------------------
{
    my $bin = stub_bin( stubs => { systemctl => 'echo "stub systemctl $*"' }, tools => ['cat'] );

    ok( -x "$bin/systemctl", 'a stub is executable' );
    ok( -x "$bin/cat" && !-l "$bin/cat", 'a tool is a wrapper, not a link a later write would follow' );
    open( my $echoed, '-|', "$bin/cat", File::Spec->devnull() ) or die "Unable to run the cat wrapper: $!";
    my $nothing = do { local $/; <$echoed> };
    close($echoed);
    is( $?, 0, 'the wrapper runs the real tool' );
    ok( !eval { stub_bin( tools => ['xcat-unit-no-such-tool'] ); 1 }, 'a tool that is not installed dies' );
    ok( !eval { stub_bin( stubs => { cat => 'exit 0' }, tools => ['cat'] ); 1 },
        'a name that is both a stub and a tool dies' );
}

# --- run_confined: environment and PATH -----------------------------------------------------
{
    my $bin = stub_bin( tools => ['sh'], stubs => { systemctl => 'echo "stub systemctl $*"' } );
    local $ENV{XCAT_UNIT_LEAK} = 'leaked';

    my ( $status, $output ) = run_confined( cmd => [ 'sh', '-c', 'systemctl status' ], bin => $bin );
    is( $status, 0, 'a stubbed command runs' );
    like( $output, qr/^stub systemctl status$/m, 'the stub, not the host command, answers' );

    # uname is installed on every host, so only the PATH restriction makes it "not found".
    ( $status, $output ) = run_confined( cmd => [ 'sh', '-c', 'uname -s' ], bin => $bin );
    is( $status, 127, 'an installed command that is neither stubbed nor listed is not found' ) or diag($output);

    ( $status, $output ) = run_confined(
        cmd => [ 'sh', '-c', 'echo "path=$PATH"; echo "leak=${XCAT_UNIT_LEAK:-none}"; echo "given=$GIVEN"' ],
        bin => $bin,
        env => { GIVEN => 'yes' },
    );
    like( $output, qr/^path=\Q$bin\E$/m, 'PATH is the stub directory and nothing else' );
    like( $output, qr/^leak=none$/m,     'the caller environment does not reach the command' );
    like( $output, qr/^given=yes$/m,     'variables the test passes do' );

    # confined_command hands the streams to the caller.
    my @command = confined_command(
        cmd => [ 'sh', '-c', 'echo "out path=$PATH leak=${XCAT_UNIT_LEAK:-none}"; echo err >&2; exit 3' ],
        bin => $bin,
    );
    my $stderr = gensym;
    my $pid    = open3( my $stdin, my $stdout, $stderr, @command );
    close($stdin);
    my $out = do { local $/; <$stdout> };
    my $err = do { local $/; <$stderr> };
    waitpid( $pid, 0 );
    is( $? >> 8, 3, 'confined_command keeps the exit status' );
    is( $out, "out path=$bin leak=none\n", 'confined_command keeps stdout apart, with the stub PATH and no caller environment' );
    is( $err, "err\n", 'confined_command keeps stderr apart' );
}

# --- run_confined: host paths and network ---------------------------------------------------
SKIP: {
    my $how = confinement();
    skip "this host offers no namespaces to a normal user, so file permissions are the protection ($how)", 6
        if $how eq 'none';

    my $bin   = stub_bin( tools => [qw(sh cat)] );
    my $probe = '/etc/xcat-unit-sandbox-probe';
    ok( !-e $probe, 'precondition: the probe file does not exist on the host' );

    my ( $status, $output ) = run_confined( cmd => [ 'sh', '-c', "echo x > $probe" ], bin => $bin );
    isnt( $status, 0, 'a write under /etc fails inside the confinement' );
    ok( !-e $probe, 'the host /etc is unchanged' );

    ( $status, $output ) = run_confined( cmd => [ 'cat', '/proc/net/dev' ], bin => $bin );
    my @interfaces = map { /^\s*([^:\s]+):/ ? $1 : () } split /\n/, $output;
    is_deeply( \@interfaces, ['lo'], 'only the loopback interface exists inside the confinement' ) or diag($output);

    # net => 0 is for a command that talks to a listener in the test process.
    open( my $host_dev, '<', '/proc/net/dev' ) or die "Unable to read /proc/net/dev: $!";
    my $host_interfaces = grep { /^\s*[^:\s]+:/ } <$host_dev>;
    close($host_dev);
    ( $status, $output ) = run_confined( cmd => [ 'cat', '/proc/net/dev' ], bin => $bin, net => 0 );
    is( scalar( grep { /^\s*[^:\s]+:/ } split /\n/, $output ), $host_interfaces,
        'with net => 0 the command keeps the host network' ) or diag($output);

    ( $status, $output ) = run_confined(
        cmd => [ 'sh', '-c', 'echo ok > "$TMPDIR/written" && cat "$TMPDIR/written"' ],
        bin => $bin,
    );
    like( $output, qr/^ok$/m, 'the scratch TMPDIR stays writable' ) or diag($output);
}

# --- confine_self ---------------------------------------------------------------------------
SKIP: {
    skip 'confine_self only acts as root', 3 unless $> == 0;

    my $script = File::Temp->new( DIR => scratch_dir(), SUFFIX => '.t' );
    my $lib    = repo_path('xCAT-test/lib');
    print {$script} <<"PERL";
use strict;
use warnings;
use lib '$lib';
use XCAT::Test::Source;
use XCAT::Test::Sandbox qw(confine_self);
BEGIN { confine_self() }
my \$wrote = open( my \$fh, '>', '/etc/xcat-unit-confine-probe' ) ? 1 : 0;
print "wrote=\$wrote\\n";
print "confined=\$ENV{XCAT_TEST_CONFINED}\\n";
PERL
    close($script);

    my $output = `$^X @{[ $script->filename ]} 2>&1`;
    like( $output, qr/^confined=1$/m, 'the test runs again inside the confinement' ) or diag($output);
    like( $output, qr/^wrote=0$/m,    'in-process code cannot write under /etc' ) or diag($output);
    ok( !-e '/etc/xcat-unit-confine-probe', 'the host /etc is unchanged' );
}

done_testing();
