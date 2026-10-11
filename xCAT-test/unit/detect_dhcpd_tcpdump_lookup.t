#!/usr/bin/env perl
use strict;
use warnings;

use Config;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;
use Time::HiRes qw(sleep);

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../build-utils/lib";
use lib "$FindBin::Bin/../lib";
use XCAT::BuildUtils qw(stage_probe_helpers);
use XCAT::Test::File qw(repo_path);
use xCAT::CommandUtils;

# Both detect_dhcpd copies refused to run unless /usr/sbin/tcpdump existed. Debian and Ubuntu
# install tcpdump as /usr/bin/tcpdump, so the rogue-DHCP detector refused to run on every Ubuntu
# management node whether tcpdump was installed or not, and the probe reported its tcpdump check
# as failed. The scripts are driven for real with a tcpdump that PATH alone can reach and that
# records how it was started. Outside the namespace below, a host that also carries
# /usr/sbin/tcpdump lets the previous guard pass as well.

my $repo  = repo_path('.');
my $tools = repo_path('xCAT-server/share/xcat/tools/detect_dhcpd');
my $probe = repo_path('xCAT-probe/subcmds/detect_dhcpd');
plan skip_all => 'detect_dhcpd not found' unless -f $tools && -f $probe;

my $perl = $Config{perlpath};
my $mac  = '02:00:5e:00:53:01';

# The capture run masks /tmp, so every fixture lives outside it.
my @fixture_dir = ( -d '/var/tmp' && -w '/var/tmp' ) ? ( DIR => '/var/tmp' ) : ();

# The standalone probe loads only the helpers staged by the package builders.
my $root = tempdir( @fixture_dir, CLEANUP => 1 );
make_path("$root/lib/perl", "$root/probe/lib/perl");
symlink( "$repo/perl-xCAT/xCAT",      "$root/lib/perl/xCAT" )   or die "symlink: $!";
symlink( "$repo/xCAT-probe/lib/perl/probe_utils.pm", "$root/probe/lib/perl/probe_utils.pm" ) or die "symlink: $!";
stage_probe_helpers("$repo/perl-xCAT/xCAT", "$root/probe/lib/perl/xCAT");
local @ENV{qw(PERL5LIB PERLLIB PERL5OPT)};
delete @ENV{qw(PERL5LIB PERLLIB PERL5OPT)};

sub write_script {
    my ( $path, $body, $interpreter ) = @_;
    $interpreter ||= '/bin/sh';
    open( my $fh, '>', $path ) or die "$path: $!";
    print {$fh} "#!$interpreter\n$body";
    close($fh);
    chmod 0755, $path;
}

# PATH will hold one directory: a tcpdump that records its invocation and the tools the scripts
# pipe through. The plain run gets an ip that answers nothing, so the scripts stop at the
# interface step before they open a socket or fork the capture.
my $marker = File::Spec->catfile( tempdir( @fixture_dir, CLEANUP => 1 ), 'tcpdump.ran' );
sub fixture_bin {
    my (%with) = @_;
    my $bindir = tempdir( @fixture_dir, CLEANUP => 1 );
    write_script( "$bindir/tcpdump", qq{printf '%s\\n' "\$0" "\$*" > '$marker'\ntrap 'exit 0' TERM\nwhile :; do sleep 1; done\n} );
    foreach my $tool (qw(awk head grep ps sleep)) {
        my $real = xCAT::CommandUtils::find_executable($tool) or next;
        symlink( $real, "$bindir/$tool" ) or die "symlink $tool: $!";
    }
    if ( $with{real_ip} ) {
        symlink( $with{real_ip}, "$bindir/ip" ) or die "symlink ip: $!";
    } else {
        write_script( "$bindir/ip", "exit 0\n" );
    }
    return $bindir;
}

sub script_command {
    my ( $script, @args ) = @_;
    return "$perl '$script' @args";
}

sub run_with_path {
    my ( $bindir, $script, @args ) = @_;
    local $ENV{PATH}     = $bindir;
    local $ENV{XCATROOT} = $root;
    unlink $marker;
    return `@{[ script_command( $script, @args ) ]} 2>&1`;
}

sub recorded_invocation {
    open( my $fh, '<', $marker ) or return;
    chomp( my @lines = <$fh> );
    close($fh);
    return @lines;
}

my $plain = fixture_bin();
my $out = run_with_path( $plain, $tools, '-i', 'lo', '-m', $mac, '-t', '1' );
unlike( $out, qr/install tcpdump/, 'the tool accepts a tcpdump found through PATH' );
like( $out, qr/IP\/MAC/, '... and gets as far as the interface step' );
$out = run_with_path( $plain, $probe, '-i', 'lo', '-m', $mac, '-d', '1' );
unlike( $out, qr/please install 'tcpdump' first/, 'the probe accepts a tcpdump found through PATH' );
like( $out, qr/IP\/MAC/, '... and gets as far as the interface step' );

# The capture itself runs only inside a private network and mount namespace: the loopback
# interface is the only one, its default route keeps the DHCP discover on the host, and a tmpfs
# over /tmp keeps the dump file out of the shared one. The scripts then reach tcpdump as they do
# on a management node. The loopback interface has no Ethernet address, so the MAC is given.
# /usr/sbin/tcpdump is hidden there, so the previous guard fails on every host.
sub isolation {
    my %bin = map { $_ => xCAT::CommandUtils::find_executable($_) } qw(unshare mount ip);
    return unless $bin{unshare} && $bin{mount} && $bin{ip};
    my $setup = "$bin{mount} -t tmpfs tmpfs /tmp && $bin{ip} link set lo up && $bin{ip} route add default dev lo"
      . " && { [ ! -e /usr/sbin/tcpdump ] || $bin{mount} --bind /dev/null /usr/sbin/tcpdump; }";
    foreach my $flags (qw(-mn -rmn)) {
        next unless system("$bin{unshare} $flags sh -c '$setup' >/dev/null 2>&1") == 0;
        return { unshare => $bin{unshare}, flags => $flags, setup => $setup, ip => $bin{ip} };
    }
    return;
}

sub run_isolated {
    my ( $ns, $bindir, $script, @args ) = @_;
    unlink $marker;
    my $command = "env PATH='$bindir' XCATROOT='$root' " . script_command( $script, @args );
    my $shell   = "$ns->{unshare} $ns->{flags} sh -c \"$ns->{setup} && exec $command\" 2>&1";
    my $out     = `$shell`;
    diag($out) if $?;
    return $out;
}

SKIP: {
    skip 'the private /tmp would hide this checkout or its fixtures', 8
      if index( $repo, '/tmp/' ) == 0 || !@fixture_dir;
    my $ns = isolation();
    skip 'no private network namespace on this host', 8 unless $ns;
    my $isolated = fixture_bin( real_ip => $ns->{ip} );

    $out = run_isolated( $ns, $isolated, $tools, '-i', 'lo', '-m', $mac, '-t', '1' );
    like( $out, qr/servers reply/, 'the tool runs its capture window in the namespace' );
    ok( -f $marker, '... and starts tcpdump' );
    my ( $ran, $args ) = recorded_invocation();
    is( $ran,  "$isolated/tcpdump",         '... by the path it resolved' );
    is( $args, "-i lo port 68 -n -vvvvvv", '... with the capture arguments' );

    $out = run_isolated( $ns, $isolated, $probe, '-i', 'lo', '-m', $mac, '-d', '1' );
    like( $out, qr/servers replied/, 'the probe runs its capture window in the namespace' );
    ok( -f $marker, '... and starts tcpdump' );
    ( $ran, $args ) = recorded_invocation();
    is( $ran,  "$isolated/tcpdump",         '... by the path it resolved' );
    is( $args, "-i lo port 68 -n -vvvvvv", '... with the capture arguments' );
}

# ---- capture lifecycle: a private dump file, tcpdump run directly and stopped by pid ------------
# Both copies wrote /tmp/dhcpdumpfile.log, ran tcpdump behind a shell, killed every tcpdump on the
# interface by pattern, and reported zero servers when tcpdump failed to start. The fake tcpdump
# below records who started it and where its output goes, waits for the TERM the script owes it,
# and a second one fails at once. ps records any use, since the scripts no longer need it.
sub lifecycle_bin {
    my (%with) = @_;
    my $bindir = tempdir( @fixture_dir, CLEANUP => 1 );
    my $record = "$with{record}";
    if ( $with{fail} ) {
        write_script( "$bindir/tcpdump", qq{printf 'started\\n' >> '$record'\nexit 1\n} );
    } elsif ( $with{quit} ) {
        write_script( "$bindir/tcpdump", qq{printf 'started\\n' >> '$record'\nexit 0\n} );
    } elsif ( $with{killed} ) {
        write_script( "$bindir/tcpdump", qq{printf 'started\\n' >> '$record'\nkill -9 \$\$\n} );
    } elsif ( $with{stubborn} ) {
        write_script( "$bindir/tcpdump", qq{trap '' TERM\nprintf 'started\\n' >> '$record'\nwhile :; do sleep 1; done\n} );
    } elsif ( $with{exec_failure} ) {
        write_script( "$bindir/tcpdump", '', '/missing-capture-interpreter' );
    } else {
        my $term_status = $with{term_status} || 0;
        my $release = $with{release}
          ? qq{while [ ! -f "$with{release}" ]; do sleep 0.05 & wait \$!; done; }
          : '';
        write_script( "$bindir/tcpdump",
                qq{parent=\$(cat /proc/\$PPID/comm 2>/dev/null)\n}
              . qq{out=\$(readlink /proc/\$\$/fd/1 2>/dev/null)\n}
              . qq{mode=\$(stat -c %a "\$out")\n}
              . qq{trap 'printf "TERM\\n" >> "$record"; ${release}exit $term_status' TERM\n}
              . qq{printf 'pid=%s ppid=%s parent=%s mode=%s out=%s\\n' "\$\$" "\$PPID" "\$parent" "\$mode" "\$out" >> '$record'\n}
              . qq{printf 'tcpdump-private-stderr\\n' >&2\n}
              . qq{printf '%s\\n' '12:00:00.000000 IP 192.0.2.1.67 > 255.255.255.255.68:' '    Client-Ethernet-Address $mac' '    Your-IP 192.0.2.44' '    Server-IP 192.0.2.2' '    DHCP-Message Option 53: Offer' '12:00:01.000000 IP 192.0.2.1.67 > 255.255.255.255.68:'\n}
              . qq{while :; do sleep 1 & wait \$!; done\n} );
    }
    write_script( "$bindir/ps", qq{printf 'ps %s\\n' "\$*" >> '$record.ps'\nexit 0\n} );
    foreach my $tool (qw(awk head grep cat readlink sleep stat)) {
        my $real = xCAT::CommandUtils::find_executable($tool) or next;
        symlink( $real, "$bindir/$tool" ) or die "symlink $tool: $!";
    }
    symlink( $with{real_ip}, "$bindir/ip" ) or die "symlink ip: $!";
    return $bindir;
}

sub run_isolated_status {
    my ( $ns, $bindir, $tmpdir, $script, @args ) = @_;
    my $command = "env PATH='$bindir' XCATROOT='$root' TMPDIR='$tmpdir' " . script_command( $script, @args );
    my $shell   = "$ns->{unshare} $ns->{flags} sh -c \"$ns->{setup} && exec $command\" 2>&1";
    my $out     = `$shell`;
    return ( $out, $? >> 8 );
}

sub slurp_lines {
    my ($path) = @_;
    open( my $fh, '<', $path ) or return;
    chomp( my @lines = <$fh> );
    close($fh);
    return @lines;
}

SKIP: {
    skip 'the private /tmp would hide this checkout or its fixtures', 128
      if index( $repo, '/tmp/' ) == 0 || !@fixture_dir;
    my $ns = isolation();
    skip 'no private network namespace on this host', 128 unless $ns;

    foreach my $case ( [ $tools, 'the tool', '-t' ], [ $probe, 'the probe', '-d' ] ) {
        my ( $script, $label, $window ) = @$case;
        my $tmpdir = tempdir( @fixture_dir, CLEANUP => 1 );
        my $record = File::Spec->catfile( tempdir( @fixture_dir, CLEANUP => 1 ), 'tcpdump.record' );
        my $bindir = lifecycle_bin( record => $record, real_ip => $ns->{ip} );

        my ( $out, $status ) = run_isolated_status( $ns, $bindir, $tmpdir, $script, '-i', 'lo', '-m', $mac, $window, '1', '-V' );
        is( $status, 0, "$label exits 0 after a capture window" );
        my @rec = slurp_lines($record);
        my ($start) = grep { /^pid=/ } @rec;
        ok( defined $start, "$label started tcpdump" ) or diag($out);
        like( $start // '', qr/ parent=perl /, '... directly from the script, with no shell in between' );
        like( $start // '', qr{ out=\Q$tmpdir\E/detect_dhcpd\.\w+$}, '... writing a private capture file under TMPDIR' );
        like( $start // '', qr/ mode=600 /, '... with owner-only access' );
        like( $out, qr/There are 1 servers repl/, '... and reads the captured offer after stopping tcpdump' );
        like( $out, qr/Server:192\.0\.2\.1 assign IP \[192\.0\.2\.44\].*next server is \[192\.0\.2\.2\]/,
            '... preserving the captured server and address details' );
        unlike( $out, qr/tcpdump-private-stderr/, '... without exposing tcpdump stderr' );
        my ($captured_pid) = ($start // '') =~ /^pid=(\d+)/;
        if ($script eq $probe) {
            like( $out, qr/Kill process \Q$captured_pid\E used to capture the packet by 'tcpdump'/,
                'the probe retains its verbose stop message' );
        } else {
            unlike( $out, qr/Kill process/, 'the tool does not add the probe stop message' );
        }
        ok( ( grep { $_ eq 'TERM' } @rec ), '... and stopped it with TERM when the window ended' );
        ok( !-e "$record.ps", '... without searching the process table' );
        my @left = glob("$tmpdir/detect_dhcpd.*");
        is( scalar(@left), 0, '... and removed the capture file on exit' );

        my $failing = lifecycle_bin( record => $record, real_ip => $ns->{ip}, fail => 1 );
        ( $out, $status ) = run_isolated_status( $ns, $failing, $tmpdir, $script, '-i', 'lo', '-m', $mac, $window, '1' );
        is( $status, 1, "$label exits 1 when tcpdump fails to start" ) or diag($out);
        like( $out, qr/tcpdump ended before the capture window did, with status 1|Capture the packets by tcpdump/, '... and says the capture failed' );
        unlike( $out, qr/0 servers repl/, '... instead of reporting zero servers' );
        @left = glob("$tmpdir/detect_dhcpd.*");
        is( scalar(@left), 0, '... and leaves no capture file behind' );

        my $unexecutable = lifecycle_bin( record => $record, real_ip => $ns->{ip}, exec_failure => 1 );
        ( $out, $status ) = run_isolated_status( $ns, $unexecutable, $tmpdir, $script, '-i', 'lo', '-m', $mac, $window, '1', '-V' );
        is( $status, 1, "$label exits 1 when exec cannot load tcpdump" );
        like( $out, qr/tcpdump ended before the capture window did, with status 1/, '... and reports the failed child' );
        is( scalar(glob_files($tmpdir)), 0, '... and removes the failed capture file' );

        my $failed_stop = lifecycle_bin( record => $record, real_ip => $ns->{ip}, term_status => 7 );
        ( $out, $status ) = run_isolated_status( $ns, $failed_stop, $tmpdir, $script, '-i', 'lo', '-m', $mac, $window, '1', '-V' );
        is( $status, 1, "$label rejects a nonzero exit after TERM" );
        like( $out, qr/tcpdump left the capture with status 7/, '... and retains the exit status' );
        unlike( $out, qr/servers repl/, '... without reporting an incomplete capture as success' );
        is( scalar(glob_files($tmpdir)), 0, '... and removes the failed capture file' );

        my $quitting = lifecycle_bin( record => $record, real_ip => $ns->{ip}, quit => 1 );
        ( $out, $status ) = run_isolated_status( $ns, $quitting, $tmpdir, $script, '-i', 'lo', '-m', $mac, $window, '1', '-V' );
        is( $status, 1, "$label exits 1 when tcpdump quits early with status 0" ) or diag($out);
        unlike( $out, qr/0 servers repl/, '... instead of reporting zero servers' );
        like( $out, qr/tcpdump ended before the capture window did, with status 0/, '... and identifies the early successful exit' );
        is( scalar(glob_files($tmpdir)), 0, '... and removes the early capture file' );

        my $dying = lifecycle_bin( record => $record, real_ip => $ns->{ip}, killed => 1 );
        ( $out, $status ) = run_isolated_status( $ns, $dying, $tmpdir, $script, '-i', 'lo', '-m', $mac, $window, '1', '-V' );
        is( $status, 1, "$label exits 1 when tcpdump dies on another signal" ) or diag($out);
        like( $out, qr/tcpdump ended before the capture window did, on signal 9/, '... and identifies the early signal death' );

        my $stubborn = lifecycle_bin( record => $record, real_ip => $ns->{ip}, stubborn => 1 );
        my $began = time;
        ( $out, $status ) = run_isolated_status( $ns, $stubborn, $tmpdir, $script, '-i', 'lo', '-m', $mac, $window, '1', '-V' );
        is( $status, 1, "$label exits 1 when tcpdump ignores TERM" ) or diag($out);
        cmp_ok( time - $began, '<', 20, '... after a bounded grace period' );
        like( $out, qr/tcpdump left the capture on signal 9/, '... having killed it after the capture window' );

        # An interrupt while the capture runs: the script is signalled once the fake tcpdump has
        # reported the script's pid, and must stop tcpdump and remove the file on its way out.
        foreach my $signals ([qw(INT INT)], [qw(TERM TERM)], [qw(INT TERM)], [qw(TERM INT)]) {
            my ($interrupt, $second) = @$signals;
            my $int_record = File::Spec->catfile( tempdir( @fixture_dir, CLEANUP => 1 ), 'tcpdump.record' );
            my $release    = "$int_record.release";
            my $int_bin    = lifecycle_bin( record => $int_record, real_ip => $ns->{ip}, release => $release );
            my $runner     = fork;
            die "fork: $!" unless defined $runner;
            if ( $runner == 0 ) {
                my ( undef, $st ) = run_isolated_status( $ns, $int_bin, $tmpdir, $script, '-i', 'lo', '-m', $mac, $window, '30' );
                exit $st;
            }
            my $started;
            foreach ( 1 .. 150 ) {
                ($started) = grep { /^pid=/ } slurp_lines($int_record);
                last if $started;
                sleep 0.2;
            }
            my ($tcpdump_pid) = ( $started // '' ) =~ /^pid=(\d+)/;
            my ($script_pid)  = ( $started // '' ) =~ / ppid=(\d+)/;
            ok( $script_pid, "$label reports the pid to interrupt" ) or diag( $started // 'tcpdump never started' );
            my $stopping;
            if ($script_pid) {
                kill $interrupt, $script_pid;
                foreach (1 .. 100) {
                    ($stopping) = grep { $_ eq 'TERM' } slurp_lines($int_record);
                    last if $stopping;
                    sleep 0.02;
                }
                if ($stopping) {
                    kill $second, $script_pid;
                    sleep 0.2;
                }
            }
            ok( $stopping, '... waits for tcpdump to acknowledge TERM before the second interrupt' );
            ok( $script_pid && kill(0, $script_pid), '... keeps the command alive while tcpdump cannot exit' );
            ok( $tcpdump_pid && kill(0, $tcpdump_pid), '... keeps tcpdump alive until its release' );
            open( my $release_fh, '>', $release ) or die "$release: $!";
            close($release_fh) or die "$release: $!";
            waitpid( $runner, 0 );
            is( $? >> 8, 1, "... and exits 1 on $interrupt followed by $second during the capture" );
            ok( ( grep { $_ eq 'TERM' } slurp_lines($int_record) ), '... after stopping tcpdump' );
            ok( !( $tcpdump_pid && kill( 0, $tcpdump_pid ) ), '... which is gone' );
            @left = glob("$tmpdir/detect_dhcpd.*");
            is( scalar(@left), 0, '... and the capture file is removed' );
        }
    }
}

sub glob_files {
    my ($directory) = @_;
    my @files = glob("$directory/detect_dhcpd.*");
    return @files;
}

done_testing();
