#!/usr/bin/env perl
use strict;
use warnings;

use Config;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../../perl-xCAT";
use xCAT::CommandUtils;

# Both detect_dhcpd copies refused to run unless /usr/sbin/tcpdump existed. Debian and Ubuntu
# install tcpdump as /usr/bin/tcpdump, so the rogue-DHCP detector refused to run on every Ubuntu
# management node whether tcpdump was installed or not, and the probe reported its tcpdump check
# as failed. The scripts are driven for real with a tcpdump that PATH alone can reach and that
# records how it was started. Outside the namespace below, a host that also carries
# /usr/sbin/tcpdump lets the previous guard pass as well.

my $repo  = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
my $tools = "$repo/xCAT-server/share/xcat/tools/detect_dhcpd";
my $probe = "$repo/xCAT-probe/subcmds/detect_dhcpd";
plan skip_all => 'detect_dhcpd not found' unless -f $tools && -f $probe;

my $perl = $Config{perlpath};
my $mac  = '02:00:5e:00:53:01';

# The capture run masks /tmp, so every fixture lives outside it.
my @fixture_dir = ( -d '/var/tmp' && -w '/var/tmp' ) ? ( DIR => '/var/tmp' ) : ();

# An XCATROOT whose lib/perl and probe/lib/perl are this checkout, so the scripts load the
# libraries they would load on a management node.
my $root = tempdir( @fixture_dir, CLEANUP => 1 );
make_path("$root/lib/perl", "$root/probe/lib");
symlink( "$repo/perl-xCAT/xCAT",      "$root/lib/perl/xCAT" )   or die "symlink: $!";
symlink( "$repo/xCAT-probe/lib/perl", "$root/probe/lib/perl" ) or die "symlink: $!";

sub write_script {
    my ( $path, $body ) = @_;
    open( my $fh, '>', $path ) or die "$path: $!";
    print {$fh} "#!/bin/sh\n$body";
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
    return "$perl -I '$repo/perl-xCAT' -I '$repo/xCAT-probe/lib/perl' '$script' @args";
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
    } else {
        write_script( "$bindir/tcpdump",
                qq{parent=\$(cat /proc/\$PPID/comm 2>/dev/null)\n}
              . qq{out=\$(readlink /proc/\$\$/fd/1 2>/dev/null)\n}
              . qq{printf 'pid=%s ppid=%s parent=%s out=%s\\n' "\$\$" "\$PPID" "\$parent" "\$out" >> '$record'\n}
              . qq{trap 'printf "TERM\\n" >> "$record"; exit 0' TERM\n}
              . qq{while :; do sleep 1; done\n} );
    }
    write_script( "$bindir/ps", qq{printf 'ps %s\\n' "\$*" >> '$record.ps'\nexit 0\n} );
    foreach my $tool (qw(awk head grep cat readlink sleep)) {
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
    skip 'the private /tmp would hide this checkout or its fixtures', 44
      if index( $repo, '/tmp/' ) == 0 || !@fixture_dir;
    my $ns = isolation();
    skip 'no private network namespace on this host', 44 unless $ns;

    foreach my $case ( [ $tools, 'the tool', '-t' ], [ $probe, 'the probe', '-d' ] ) {
        my ( $script, $label, $window ) = @$case;
        my $tmpdir = tempdir( @fixture_dir, CLEANUP => 1 );
        my $record = File::Spec->catfile( tempdir( @fixture_dir, CLEANUP => 1 ), 'tcpdump.record' );
        my $bindir = lifecycle_bin( record => $record, real_ip => $ns->{ip} );

        my ( $out, $status ) = run_isolated_status( $ns, $bindir, $tmpdir, $script, '-i', 'lo', '-m', $mac, $window, '1' );
        is( $status, 0, "$label exits 0 after a capture window" );
        my @rec = slurp_lines($record);
        my ($start) = grep { /^pid=/ } @rec;
        ok( defined $start, "$label started tcpdump" ) or diag($out);
        like( $start // '', qr/ parent=perl /, '... directly from the script, with no shell in between' );
        like( $start // '', qr{ out=\Q$tmpdir\E/detect_dhcpd\.\w+$}, '... writing a private capture file under TMPDIR' );
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

        my $quitting = lifecycle_bin( record => $record, real_ip => $ns->{ip}, quit => 1 );
        ( $out, $status ) = run_isolated_status( $ns, $quitting, $tmpdir, $script, '-i', 'lo', '-m', $mac, $window, '1' );
        is( $status, 1, "$label exits 1 when tcpdump quits early with status 0" ) or diag($out);
        unlike( $out, qr/0 servers repl/, '... instead of reporting zero servers' );

        my $dying = lifecycle_bin( record => $record, real_ip => $ns->{ip}, killed => 1 );
        ( $out, $status ) = run_isolated_status( $ns, $dying, $tmpdir, $script, '-i', 'lo', '-m', $mac, $window, '1' );
        is( $status, 1, "$label exits 1 when tcpdump dies on another signal" ) or diag($out);
        like( $out, qr/on signal 9|Capture the packets by tcpdump/, '... and names the signal or the failed step' );

        my $stubborn = lifecycle_bin( record => $record, real_ip => $ns->{ip}, stubborn => 1 );
        my $began = time;
        ( $out, $status ) = run_isolated_status( $ns, $stubborn, $tmpdir, $script, '-i', 'lo', '-m', $mac, $window, '1' );
        is( $status, 1, "$label exits 1 when tcpdump ignores TERM" ) or diag($out);
        cmp_ok( time - $began, '<', 20, '... after a bounded grace period' );
        like( $out, qr/on signal 9|Capture the packets by tcpdump/, '... having killed it' );

        # An interrupt while the capture runs: the script is signalled once the fake tcpdump has
        # reported the script's pid, and must stop tcpdump and remove the file on its way out.
        my $int_record = File::Spec->catfile( tempdir( @fixture_dir, CLEANUP => 1 ), 'tcpdump.record' );
        my $int_bin    = lifecycle_bin( record => $int_record, real_ip => $ns->{ip} );
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
            select( undef, undef, undef, 0.2 );
        }
        my ($tcpdump_pid) = ( $started // '' ) =~ /^pid=(\d+)/;
        my ($script_pid)  = ( $started // '' ) =~ / ppid=(\d+)/;
        ok( $script_pid, "$label reports the pid to interrupt" ) or diag( $started // 'tcpdump never started' );
        if ($script_pid) {
            kill 'INT', $script_pid;
            select( undef, undef, undef, 0.3 );
            kill 'INT', $script_pid;
        }
        waitpid( $runner, 0 );
        is( $? >> 8, 1, '... and exits 1 on a double interrupt during the capture' );
        ok( ( grep { $_ eq 'TERM' } slurp_lines($int_record) ), '... after stopping tcpdump' );
        ok( !( $tcpdump_pid && kill( 0, $tcpdump_pid ) ), '... which is gone' );
        @left = glob("$tmpdir/detect_dhcpd.*");
        is( scalar(@left), 0, '... and the capture file is removed' );
    }
}

done_testing();
