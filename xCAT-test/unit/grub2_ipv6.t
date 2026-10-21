#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';

use Cwd qw(getcwd);
use FindBin;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

BEGIN {
    package xCAT::Scope;
    $INC{'xCAT/Scope.pm'} = __FILE__;

    package xCAT::Utils;
    sub parseMacTabEntry {
        my ($class, $macstring) = @_;
        my ($mac) = split(/\|/, $macstring || '');
        $mac =~ s/!.*// if defined($mac);
        return $mac;
    }
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package xCAT::TableUtils;
    our $httpport = 8080;
    sub getTftpDir { return '/tftpboot'; }
    sub get_site_attribute {
        my ($class, $attribute) = @_;
        return $httpport if $attribute eq 'httpport';
        return;
    }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::ServiceNodeUtils;
    $INC{'xCAT/ServiceNodeUtils.pm'} = __FILE__;

    package xCAT::NetworkUtils;
    our %addresses = (
        nodev4              => { 4 => '192.0.2.50' },
        nodev6              => { 6 => '2001:db8:1::50' },
        nodedual            => { 4 => '192.0.2.60', 6 => '2001:db8:1::60' },
        'boot4.example.test' => { 4 => '192.0.2.10' },
        'boot6.example.test' => { 6 => '2001:db8::10' },
    );
    our @legacy_facing_calls;
    our @family_facing_calls;

    sub getipaddr {
        my $host = shift;
        $host = shift if defined($host) && $host eq __PACKAGE__;
        my %opts = @_;
        my $entry = $addresses{$host} || {};
        return $entry->{6} if $opts{OnlyV6};
        return $entry->{4} if $opts{OnlyV4};
        return $entry->{4} || $entry->{6};
    }

    sub node_address_family {
        my $node = shift;
        $node = shift if defined($node) && $node eq __PACKAGE__;
        return 4 if getipaddr($node, OnlyV4 => 1);
        return 6 if getipaddr($node, OnlyV6 => 1);
        return;
    }

    sub my_ip_facing {
        my $node = shift;
        $node = shift if defined($node) && $node eq __PACKAGE__;
        push @legacy_facing_calls, $node;
        return (0, '192.0.2.1');
    }

    sub my_ip_facing_family {
        my $node = shift;
        $node = shift if defined($node) && $node eq __PACKAGE__;
        my $family = shift;
        push @family_facing_calls, [$node, $family];
        return (0, '2001:db8::1');
    }

    sub ipv6_server_for_node {
        my $node = shift;
        $node = shift if defined($node) && $node eq __PACKAGE__;
        my $server = shift;
        if (!defined($server) || $server eq '!myipfn!' || $server eq '<xcatmaster>') {
            my @facing = my_ip_facing_family(__PACKAGE__, $node, 6);
            return unless @facing && !$facing[0];
            return $facing[1];
        }
        return getipaddr(__PACKAGE__, $server, OnlyV6 => 1);
    }

    sub format_uri_host {
        my $host = shift;
        $host = shift if defined($host) && $host eq __PACKAGE__;
        return "[$host]" if defined($host) && $host =~ /:/;
        return $host;
    }

    sub format_host_port {
        my $host = shift;
        $host = shift if defined($host) && $host eq __PACKAGE__;
        my $port = shift;
        my $formatted = format_uri_host($host);
        return "$formatted:$port";
    }

    sub isIpaddr {
        my $ip = shift;
        $ip = shift if defined($ip) && $ip eq __PACKAGE__;
        return defined($ip) && $ip =~ /^\d{1,3}(?:\.\d{1,3}){3}$/;
    }
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;

    package xCAT::MsgUtils;
    $INC{'xCAT/MsgUtils.pm'} = __FILE__;

    package xCAT::Table;
    sub new { return; }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::Usage;
    $INC{'xCAT/Usage.pm'} = __FILE__;
}

my $source = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/grub2.pm";
require $source;

is(
    xCAT_plugin::grub2::grub2_root_spec('http', '192.0.2.1', 80),
    'http,192.0.2.1',
    'default-port IPv4 HTTP root remains byte-for-byte unchanged'
);
is(
    xCAT_plugin::grub2::grub2_root_spec('http', '192.0.2.1', 8080),
    'http,192.0.2.1:8080',
    'custom-port IPv4 HTTP root remains byte-for-byte unchanged'
);
is(
    xCAT_plugin::grub2::grub2_root_spec('http', '2001:db8::1', 80),
    'http,[2001:db8::1]',
    'default-port IPv6 HTTP root brackets the address'
);
is(
    xCAT_plugin::grub2::grub2_root_spec('http', '2001:db8::1', 8080),
    'http,[2001:db8::1]:8080',
    'custom-port IPv6 HTTP root brackets the address before the port'
);

@xCAT::NetworkUtils::legacy_facing_calls = ();
@xCAT::NetworkUtils::family_facing_calls = ();
is_deeply(
    [ xCAT_plugin::grub2::grub2_server_for_node('nodev6', '<xcatmaster>') ],
    [ 0, '2001:db8::1' ],
    'IPv6-only node selects the IPv6-facing xCAT server'
);
is_deeply(
    $xCAT::NetworkUtils::family_facing_calls[0],
    [ 'nodev6', 6 ],
    'IPv6-only server selection uses the shared family helper'
);
is(
    scalar(@xCAT::NetworkUtils::legacy_facing_calls),
    0,
    'IPv6-only server selection does not use the legacy IPv4 helper'
);

@xCAT::NetworkUtils::legacy_facing_calls = ();
@xCAT::NetworkUtils::family_facing_calls = ();
is_deeply(
    [ xCAT_plugin::grub2::grub2_server_for_node('nodev4', '<xcatmaster>') ],
    [ 0, '192.0.2.1' ],
    'IPv4 node retains legacy facing-server selection'
);
is_deeply(
    \@xCAT::NetworkUtils::legacy_facing_calls,
    ['nodev4'],
    'IPv4 node still invokes the legacy helper'
);
is(
    scalar(@xCAT::NetworkUtils::family_facing_calls),
    0,
    'IPv4 node does not invoke the new family helper'
);

@xCAT::NetworkUtils::legacy_facing_calls = ();
@xCAT::NetworkUtils::family_facing_calls = ();
is_deeply(
    [ xCAT_plugin::grub2::grub2_server_for_node('nodedual', '<xcatmaster>') ],
    [ 0, '192.0.2.1' ],
    'dual-stack node retains the legacy IPv4 server preference'
);
is(
    scalar(@xCAT::NetworkUtils::family_facing_calls),
    0,
    'dual-stack node does not switch existing provisioning to IPv6'
);

{
    no warnings 'redefine';
    local *xCAT::NetworkUtils::my_ip_facing = sub {
        return (2, 'node is in an undefined subnet');
    };
    is_deeply(
        [ xCAT_plugin::grub2::grub2_server_for_node('nodev4', '<xcatmaster>') ],
        [ 1, 'node is in an undefined subnet' ],
        'legacy IPv4 facing-server failures retain the setstate error code'
    );
}

is_deeply(
    [ xCAT_plugin::grub2::grub2_server_for_node('nodev6', 'boot6.example.test') ],
    [ 0, '2001:db8::10' ],
    'IPv6-only node resolves an explicit boot server in IPv6'
);

sub exercise_setstate {
    my ($node, $mac) = @_;
    my $tftpdir = tempdir(CLEANUP => 1);
    my $bootloader_root = "$tftpdir/boot/grub2";
    make_path($bootloader_root);

    open(my $binary, '>', "$bootloader_root/grub2.x86_64")
      or die "Unable to create test GRUB binary: $!";
    print {$binary} "test grub binary\n";
    close($binary);

    my %bootparams = (
        $node => [
            {
                kernel   => '/install/rhels10/x86_64/vmlinuz',
                initrd   => '/install/rhels10/x86_64/initrd.img',
                kcmdline => 'inst.ks=http://example.test/autoinst/node',
            },
        ],
    );
    my %chain = ($node => [{ currstate => 'install' }]);
    my %macs = ($node => [{ mac => $mac }]);
    my %noderes = (
        $node => [
            {
                netboot   => 'grub2-http',
                tftpserver => '<xcatmaster>',
            },
        ],
    );

    my $oldcwd = getcwd();
    local $::XCATSITEVALS{xcatdebugmode} = '0';
    my @result = xCAT_plugin::grub2::setstate(
        $node,
        \%bootparams,
        \%chain,
        \%macs,
        $tftpdir,
        \%noderes,
        undef,
        'x86_64',
        'rhels10',
    );
    chdir($oldcwd) or die "Unable to restore test working directory: $!";

    open(my $config, '<', "$bootloader_root/$node")
      or die "Unable to read generated GRUB config: $!";
    local $/;
    my $content = <$config>;
    close($config);

    return ($tftpdir, $bootloader_root, $content, @result);
}

$xCAT::TableUtils::httpport = 8080;

@xCAT::NetworkUtils::legacy_facing_calls = ();
@xCAT::NetworkUtils::family_facing_calls = ();
my ($v6_tftpdir, $v6_root, $v6_config, $v6_rc, $v6_message) =
  exercise_setstate('nodev6', '02:00:00:00:00:61');
is($v6_rc, 0, "IPv6-only GRUB config generation succeeds: $v6_message");
like(
    $v6_config,
    qr/^    set root=http,\[2001:db8::1\]:8080$/m,
    'generated IPv6 GRUB HTTP root uses a bracketed authority'
);
ok(
    -e "$v6_root/grub.cfg-01-02-00-00-00-00-61",
    'IPv6-only node retains its MAC-specific GRUB config alias'
);
my @v6_ip_aliases = grep { $_ !~ /grub\.cfg-01-02-00-00-00-00-61$/ } glob("$v6_root/grub.cfg-*");
is_deeply(
    \@v6_ip_aliases,
    [],
    'IPv6-only node does not create an IPv4-hex GRUB config alias'
);

@xCAT::NetworkUtils::legacy_facing_calls = ();
@xCAT::NetworkUtils::family_facing_calls = ();
my ($v4_tftpdir, $v4_root, $v4_config, $v4_rc, $v4_message) =
  exercise_setstate('nodev4', '02:00:00:00:00:41');
is($v4_rc, 0, "IPv4 GRUB config generation succeeds: $v4_message");
like(
    $v4_config,
    qr/^    set root=http,192\.0\.2\.1:8080$/m,
    'generated IPv4 GRUB HTTP root remains byte-for-byte unchanged'
);
ok(
    -e "$v4_root/grub.cfg-C0000232",
    'IPv4 node retains its IPv4-hex GRUB config alias'
);
ok(
    -e "$v4_root/grub.cfg-01-02-00-00-00-00-41",
    'IPv4 node retains its MAC-specific GRUB config alias'
);

done_testing();
