#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_DHCP_POLICY_DIR};
use File::Temp qw(tempdir);
use IO::Select;
use IO::Socket::INET;
use JSON;
use POSIX qw(WNOHANG);
use Socket qw(inet_aton);
use Test::More;
use Time::HiRes qw(sleep);
use xCAT::DHCP::BootPolicy;
use xCAT::DHCP::Backend::Kea;

my ($kea) = grep { -x $_ } qw(/usr/sbin/kea-dhcp4 /usr/local/sbin/kea-dhcp4);
my ($isc) = grep { -x $_ } qw(/usr/sbin/dhcpd /usr/local/sbin/dhcpd);
plan skip_all => 'ISC and Kea parsers are required' unless $kea && $isc;
plan skip_all => 'isolated DHCP checks require Linux and root' unless $^O eq 'linux' && $> == 0;

my $temporary = tempdir(CLEANUP => 1);
sub write_file {
    my ($name, $text) = @_;
    open(my $file, '>', $name) or die "$name: $!";
    print {$file} $text;
    close($file) or die "$name: $!";
}
my $root_path = xCAT::DHCP::BootPolicy->freebsd_native_root_path('node01', '192.0.2.1');
my $statement = xCAT::DHCP::BootPolicy->isc_freebsd_native_statement($root_path);
write_file("$temporary/isc.conf", "option user-class-identifier code 77 = string;\n" .
    "subnet 192.0.2.0 netmask 255.255.255.0 {}\n" .
    "host node01 { hardware ethernet 52:54:00:12:34:56; fixed-address 192.0.2.20; $statement }\n");
is(system($isc, '-t', '-cf', "$temporary/isc.conf"), 0, 'ISC accepts the generated native-loader condition');

my $classes = xCAT::DHCP::BootPolicy->kea_xnba_node_classes(nodes => [{
    node => 'node01', mac => '52:54:00:12:34:56', next_server => '192.0.2.1', freebsd_root_path => $root_path,
}], xnba_efi => 1);
my $backend = xCAT::DHCP::Backend::Kea->new();
my $rendered = $backend->render_dhcp4_config({
    interfaces => ['lo'], 'client-classes' => $classes,
    subnets => [{ id => 1, subnet => '127.0.0.0/8' }],
});
my $config = decode_json($rendered);
$config->{Dhcp4}{'interfaces-config'} = { interfaces => ['lo/127.0.0.1'], 'dhcp-socket-type' => 'udp' };
$config->{Dhcp4}{'lease-database'} = { type => 'memfile', persist => JSON::false };
$config->{Dhcp4}{loggers} = [{ name => 'kea-dhcp4', severity => 'INFO', output_options => [{output => 'stdout'}] }];
write_file("$temporary/kea.conf", encode_json($config));
is(system($kea, '-t', "$temporary/kea.conf"), 0, 'Kea accepts the generated native-loader class');

my $client = IO::Socket::INET->new(LocalAddr => '127.0.0.2', LocalPort => 0, Proto => 'udp') or die $!;
my $reserve = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'udp') or die $!;
my $server_port = $reserve->sockport;
close($reserve);
my $client_port = $client->sockport;
my $pid = fork();
die "fork: $!" unless defined($pid);
if (!$pid) {
    $ENV{KEA_PIDFILE_DIR} = $temporary;
    $ENV{KEA_LOCKFILE_DIR} = $temporary;
    open(STDOUT, '>', "$temporary/server.log") or die $!;
    open(STDERR, '>&', \*STDOUT) or die $!;
    exec($kea, '-c', "$temporary/kea.conf", '-p', $server_port, '-P', $client_port);
    die "exec: $!";
}
END {
    if ($pid) {
        kill 'TERM', $pid;
        for (1 .. 20) {
            my $waited = waitpid($pid, WNOHANG);
            if ($waited == $pid || $waited == -1) { $pid = undef; last; }
            sleep 0.05;
        }
        if ($pid) { kill 'KILL', $pid; waitpid($pid, 0); }
    }
}

sub inform {
    my ($user_class, $architecture, $mac) = @_;
    my $xid = int(rand(0xffffffff));
    my $packet = pack('CCCCNnn', 1, 1, 6, 0, $xid, 0, 0) . inet_aton('127.0.0.2') . ("\0" x 12) .
        pack('H*', $mac) . ("\0" x (236 - 34)) . "\x63\x82\x53\x63\x35\x01\x08\x37\x01\x11" .
        pack('CCn', 93, 2, $architecture);
    $packet .= pack('CC', 77, length($user_class)) . $user_class if defined($user_class);
    $packet .= "\xff";
    my $peer = Socket::sockaddr_in($server_port, inet_aton('127.0.0.1'));
    for (1 .. 15) {
        send($client, $packet, 0, $peer) or die $!;
        next unless IO::Select->new($client)->can_read(0.2);
        recv($client, my $reply, 4096, 0) or next;
        next unless length($reply) >= 240 && unpack('N', substr($reply, 4, 4)) == $xid;
        my %options;
        my $offset = 240;
        while ($offset < length($reply)) {
            my $code = ord(substr($reply, $offset++, 1));
            last if $code == 255;
            next if $code == 0;
            my $length = ord(substr($reply, $offset++, 1));
            $options{$code} = substr($reply, $offset, $length);
            $offset += $length;
        }
        return \%options;
    }
    return;
}

for my $case (
    ["\x07FreeBSD", 0, '525400123456', $root_path, 'native BIOS and native UEFI arch-zero tuple'],
    ["\x07FreeBSD", 7, '525400123456', $root_path, 'native tuple without architecture filtering'],
    [undef, 0, '525400123456', undef, 'BIOS firmware'],
    [undef, 7, '525400123456', undef, 'UEFI firmware'],
    ['xNBA', 0, '525400123456', undef, 'legacy xNBA'],
    ["\x04xNBA", 7, '525400123456', undef, 'tuple xNBA'],
    ['iPXE', 0, '525400123456', undef, 'iPXE'],
    ['Linux', 0, '525400123456', undef, 'Linux DHCP client'],
    ['FreeBSD', 0, '525400123456', undef, 'unprefixed near-match'],
    ["\x08FreeBSD!", 0, '525400123456', undef, 'extended near-match'],
    ["\x07FreeBSD", 0, '525400123457', undef, 'different node MAC'],
) {
    my ($user_class, $architecture, $mac, $expected, $description) = @$case;
    my $options = inform($user_class, $architecture, $mac);
    ok($options && $options->{53} eq "\x05", "Kea replies to $description");
    is($options ? $options->{17} : undef, $expected, "$description receives only its permitted root path");
    unless ($options) {
        open(my $log, '<', "$temporary/server.log") or die $!;
        diag(do { local $/; <$log> });
        close($log);
        last;
    }
}

done_testing;
