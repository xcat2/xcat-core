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

sub _encode_values {
    my $values = shift;
    my $text = '';
    for my $key (qw(interface mac mtu NICTYPES NICDEVICES NICEXTRAPARAMS NICMACS)) {
        _fail("Invalid $key") unless defined($values->{$key}) && !ref($values->{$key}) &&
            $values->{$key} !~ /[^\x20-\x7e]/x;
        $text .= "$key=$values->{$key}\n";
    }
    return encode_base64($text, '');
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
    my $plan = compile(_encode_values(\%values), $planner);
    my %selected = map { $_ => 1 } $plan =~ /^I\t([a-z][a-z0-9]{0,14})\t/gmx;
    # Older boot images must not receive installed-node interface types.
    for my $field (qw(NICTYPES NICDEVICES NICEXTRAPARAMS NICMACS)) {
        $values{$field} = join(',', grep {
            my ($nic) = split(/!/x, $_, 2);
            $selected{$nic};
        } split(/,/x, $values{$field}));
    }
    return _encode_values(\%values);
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

sub _dhcp4_environment {
    my ($nics, $networks) = @_;
    _fail('Invalid DHCP network tables') unless ref($nics) eq 'HASH' && ref($networks) eq 'ARRAY';
    my %environment = (LC_ALL => 'C', NETWORKS_LINES => scalar(@{$networks}));
    for my $field (qw(nictypes nicdevices nicips nicnetworks nicextraparams niccustomscripts)) {
        _fail("Invalid $field") if ref($nics->{$field});
        $environment{uc($field)} = $nics->{$field} || '';
    }
    my $index = 0;
    for my $network (@{$networks}) {
        my @fields;
        for my $name (qw(netname net mask gateway mtu disable)) {
            my $value = $network->{$name} // '';
            _fail("Invalid network $name") if ref($value) || $value =~ /[^\x20-\x7e]|\|/x;
            push @fields, "$name=$value";
        }
        $environment{'NETWORKS_LINE' . ++$index} = join('||', @fields);
    }
    return \%environment;
}

sub dhcp4_reservations {
    my ($nics, $networks, $uuid, $planner) = @_;
    _fail('Missing shared network planner') if !defined($planner) || ref($planner) ||
        $planner !~ m{\A/}x || !-f $planner || -l $planner;
    my $result = xCAT::FreeBSDPkg::run_command(
        ['/usr/bin/awk', '-v', 'mode=dhcp4-reservations', '-f', $planner],
        environment => _dhcp4_environment($nics, $networks), timeout => 15,
        stdout_limit => 8192, stderr_limit => 4096);
    _fail($result->{stderr} || 'DHCP network planner failed') if $result->{exitcode} || $result->{signal};
    return [] if $result->{stdout} eq '';
    _fail('DHCP requires a valid vpd.uuid') if !defined($uuid) || ref($uuid) ||
        $uuid !~ /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/ix ||
        $uuid eq '00000000-0000-0000-0000-000000000000' ||
        lc($uuid) eq 'ffffffff-ffff-ffff-ffff-ffffffffffff';
    (my $hex = lc($uuid)) =~ s/-//gx;
    my (@reservations, %identifiers);
    for my $line (split(/\n/x, $result->{stdout})) {
        my ($interface, $address) = $line =~ /\A([a-z][a-z0-9]{0,14})\t([0-9.]+)\z/x;
        _fail('Invalid DHCP reservation plan') unless defined($interface);
        my $checksum = xCAT::FreeBSDPkg::run_command(
            ['/bin/sh', '-c', 'printf %s "$1" | cksum', 'xcat', $interface],
            environment => { LC_ALL => 'C', PATH => '/usr/bin:/bin' },
            timeout => 5, stdout_limit => 128, stderr_limit => 1024);
        my ($iaid) = $checksum->{stdout} =~ /\A([0-9]+)\s+[0-9]+\s*\z/x;
        _fail('Cannot compute DHCP interface identity') if $checksum->{exitcode} || $checksum->{signal} || !defined($iaid);
        my $identifier = sprintf('ff%08x0004%s', $iaid, $hex);
        _fail('Duplicate DHCP interface identity') if $identifiers{$identifier}++;
        $identifier = join(':', $identifier =~ /(..)/gx);
        push @reservations, { interface => $interface, address => $address, client_id => $identifier };
    }
    return \@reservations;
}

1;
