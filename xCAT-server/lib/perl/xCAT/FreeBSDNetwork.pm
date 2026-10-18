package xCAT::FreeBSDNetwork;

use strict;
use warnings;
use MIME::Base64 qw(encode_base64 decode_base64);
use xCAT::FreeBSDPkg;

sub _fail { die "FreeBSD bootstrap network: $_[0]\n"; }

sub decode {
    my $encoded = shift;
    _fail('Invalid bootstrap network description') unless defined($encoded) && !ref($encoded) &&
        length($encoded) <= 8192 && $encoded =~ /\A[A-Za-z0-9+\/=]+\z/x;
    my $text = decode_base64($encoded);
    _fail('Noncanonical bootstrap network encoding') unless encode_base64($text, '') eq $encoded;
    my %values;
    my @keys = qw(interface mac mtu NICTYPES NICDEVICES NICEXTRAPARAMS NICMACS);
    my @lines = split(/\n/x, $text, -1);
    _fail('Incomplete bootstrap network description') unless @lines == 8 && pop(@lines) eq '';
    for my $key (@keys) {
        my $line = shift(@lines);
        _fail('Invalid bootstrap network field') unless $line =~ /\A\Q$key\E=([\x20-\x7e]*)\z/x;
        $values{$key} = $1;
    }
    _fail('Invalid bootstrap interface') unless $values{interface} =~ /\A[a-z][a-z0-9]{0,14}\z/x;
    _fail('Invalid bootstrap MAC') unless $values{mac} =~ /\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/x;
    _fail('Invalid bootstrap MTU') unless $values{mtu} =~ /\A[1-9][0-9]{2,3}\z/x &&
        $values{mtu} >= 576 && $values{mtu} <= 9216;
    return \%values;
}

sub compile {
    my ($encoded, $planner) = @_;
    my $values = decode($encoded);
    _fail('Missing shared network planner') unless defined($planner) && !ref($planner) &&
        $planner =~ m{\A/}x && -f $planner && !-l $planner;
    my %environment = map { $_ => $values->{$_} } qw(NICTYPES NICDEVICES NICEXTRAPARAMS NICMACS);
    my $result = xCAT::FreeBSDPkg::run_command(['/usr/bin/awk', '-v', 'mode=bootstrap',
        '-v', "bootstrapnic=$values->{interface}", '-v', "bootmac=$values->{mac}",
        '-v', "bootstrap_mtu=$values->{mtu}", '-f', $planner],
        environment => { %environment, LC_ALL => 'C' }, timeout => 15, stdout_limit => 32768, stderr_limit => 4096);
    _fail($result->{stderr} || 'Network planner failed') if $result->{exitcode} || $result->{signal};
    _fail('Network planner did not return a bootstrap plan') unless
        $result->{stdout} =~ /\AF\txcat-freebsd-bootstrap-1\nB\t\Q$values->{interface}\E\n/x;
    return $result->{stdout};
}

sub encode {
    my ($interface, $mac, $nics, $planner, $mtu) = @_;
    _fail('Missing nics table row') unless ref($nics) eq 'HASH';
    my %values = (interface => $interface, mac => $mac, mtu => (defined($mtu) ? $mtu : 1500));
    for my $field (qw(NICTYPES NICDEVICES NICEXTRAPARAMS)) {
        $values{$field} = $nics->{lc($field)} || '';
    }
    # nicsadapter is the existing xCAT inventory of interface identities.
    # Only carry MACs for physical interfaces named by this topology.
    my %physical;
    for my $entry (split(/,/x, $values{NICTYPES})) {
        $physical{$1} = 1 if $entry =~ /\A([a-z][a-z0-9]{0,14})!ethernet\z/ix;
    }
    my $adapters = $nics->{nicsadapter} || '';
    _fail('Invalid nicsadapter inventory') if ref($adapters) || length($adapters) > 65536 ||
        $adapters =~ /[^\x20-\x7e]/x;
    my %macs;
    for my $entry (split(/,/x, $adapters)) {
        my ($nic, $properties) = split(/!/x, $entry, 2);
        next unless $physical{$nic};
        _fail('Invalid physical nicsadapter entry') unless defined($properties) && !exists($macs{$nic});
        my @macs = $properties =~ /(?:\A|[ ])mac=([^ ]*)(?=[ ]|\z)/igx;
        _fail('Each physical nicsadapter entry requires one MAC') unless @macs == 1 &&
            $macs[0] =~ /\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/ix;
        $macs{$nic} = lc($macs[0]);
    }
    $values{NICMACS} = join(',', map { "$_!$macs{$_}" } sort keys %macs);
    my $text = '';
    for my $key (qw(interface mac mtu NICTYPES NICDEVICES NICEXTRAPARAMS NICMACS)) {
        _fail("Invalid $key") unless defined($values{$key}) && !ref($values{$key}) &&
            $values{$key} !~ /[^\x20-\x7e]/x;
        $text .= "$key=$values{$key}\n";
    }
    my $encoded = encode_base64($text, '');
    compile($encoded, $planner);
    return $encoded;
}

sub loader {
    my $encoded = shift;
    decode($encoded);
    my @chunks = $encoded =~ /.{1,120}/gx;
    my $text = 'xcat_network_chunks="' . scalar(@chunks) . "\"\n";
    for my $index (0 .. $#chunks) {
        $text .= "xcat_network_$index=\"$chunks[$index]\"\n";
    }
    return $text;
}

1;
