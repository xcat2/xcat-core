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
    write_script( "$bindir/tcpdump", qq{printf '%s\\n' "\$0" "\$*" > '$marker'\nexit 0\n} );
    foreach my $tool (qw(awk head grep ps)) {
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

done_testing();
