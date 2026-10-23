#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Carp qw(croak);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use MIME::Base64 qw(encode_base64);
use Test::More;
use XCAT::Test::Chroot qw(stage_binary);
use xCAT::FreeBSDConfig;
use xCAT::FreeBSDInstall;
use xCAT::FreeBSDNetwork;
use xCAT::FreeBSDPkg;
use xCAT::NetworkUtils;

BEGIN { $INC{'xCAT/Table.pm'} = __FILE__; }
{
    package xCAT::Table;
    our %rows;
    sub new { return bless {table => $_[1]}, $_[0]; }
    sub getNodeAttribs { return $rows{$_[0]{table}}{$_[1]}; }
    sub close { return; }
}

my $source = "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd";
my $planner = "$FindBin::Bin/../../xCAT/postscripts/confignetwork-freebsd.awk";
my $media = {format => 'xcat-mfsbsd-2', release => '15.1-RELEASE', arch => 'x86_64',
    install_contract => 'xcat-freebsd-install-6', network_contract => 'xcat-freebsd-bootstrap-1',
    ipv6_contract => 'xcat-freebsd-ipv6-1', digest => 'a' x 64,
    files => {'xcat/runtime.tsv' => 'b' x 64}};
my $settings = xCAT::FreeBSDConfig::boot_settings({target_disk => 'vtbd0',
    target_disk_ident => 'OS_SERIAL', filesystem => 'zfs', swap_size => '0',
    authorized_key_base64 => encode_base64('ssh-ed25519 AAAA', '')}, '', {}, $media);
my $network = {master => '2001:db8:1::1', port => '3002', mac => '52:54:00:12:34:56',
    ipv4 => '', netmask => '', gateway => '', hostname => 'node1.example.test',
    ipv6 => '2001:db8:1::10', ipv6_prefix => '64', ipv6_gateway => '', ipv6_mtu => '1500',
    install_url => 'http://[2001:db8:1::1]:8080/install', nameservers => '2001:db8:1::53'};
my $generation = 'c' x 32;
sub render {
    my ($values, $image, $policy) = @_;
    return xCAT::FreeBSDConfig::render_pkgbase('node1', $policy || $settings, $values || $network,
        {media => $image || $media, package_plan_sha256 => 'd' x 64}, $generation);
}
sub write_file {
    my ($path, $text) = @_;
    open(my $file, '>', $path) or croak $!;
    print {$file} $text or croak $!;
    close($file) or croak $!;
}

my $configuration;
subtest 'IPv6 configuration requires admitted media and a complete static network' => sub {
    my $ok = eval { $configuration = render(); 1 };
    ok($ok, 'pkgbase renderer accepts IPv6 after DHCPv4 bootstrap') or do { diag($@); return; };
    like($configuration, qr/^ipv4=\nnetmask=\ngateway=$/mx, 'temporary bootstrap IPv4 is not installed');
    like($configuration, qr{^install_url=http://\[2001:db8:1::1\]:8080/install$}mx, 'package transport uses an IPv6 URI');
    like($configuration, qr/^master=2001:db8:1::1$/mx, 'status reports use the IPv6 controller');
    my %old = %$media;
    delete $old{ipv6_contract};
    ok(!eval { render(undef, \%old); 1 }, 'older media cannot accept an IPv6 request');
    like($@, qr/xcat-freebsd-ipv6-1/x, 'the diagnostic identifies the required media contract');
    ok(!eval { render(undef, undef, {%$settings, bootstrap => 'static'}); 1 }, 'IPv6 requires DHCPv4 for the initial bootstrap');
    for my $change (
        {ipv6 => '::'}, {ipv6 => '::1'}, {ipv6 => 'fe80::10'}, {ipv6 => 'ff02::10'},
        {ipv6 => '::ffff:c000:20a'}, {ipv6 => '2001:db8:::10'}, {ipv6 => '2001:db8:1::10%vtnet0'},
        {ipv6_prefix => '129'}, {ipv6_prefix => '064'}, {ipv6_mtu => '1279'},
        {ipv6_gateway => '2001:db8:2::1'}, {ipv6_gateway => '2001:DB8:1:0:0:0:0:10'},
        {master => '192.0.2.1'}, {master => '2001:db8:2::1'}, {nameservers => '192.0.2.53'},
        {install_url => 'http://2001:db8:1::1/install'}, {install_url => 'http://[2001:db8:1::1]:0/install'},
        {install_url => 'http://[2001:db8:1::1]:080/install'}, {install_url => 'http://[2001:db8:1::1]/../private'},
        {install_url => 'http://[2001:db8:2::1]/install'}, {ipv4 => '192.0.2.10'},
    ) {
        ok(!eval { render({%$network, %$change}); 1 }, 'invalid network policy is rejected by the producer');
    }
};

subtest 'the shipped shell reader and network initializer consume the IPv6 configuration' => sub {
    plan(skip_all => 'The shell fixture requires Linux lab root') unless $^O eq 'linux' && $> == 0;
    ok(defined($configuration), 'the producer supplied the fixture') or return;
    my $root = tempdir(CLEANUP => 1);
    make_path(map { "$root/$_" } qw(bin usr/bin usr/local/libexec fixture dev));
    for my $binary (qw(/bin/sh /bin/cat /bin/cp /usr/bin/awk /usr/bin/wc /usr/bin/base64 /usr/bin/tr)) { stage_binary($root, $binary); }
    copy("$source/xcat-install-lib.sh", "$root/usr/local/libexec/xcat-install-lib.sh") or croak $!;
    copy("$source/xcat-network.sh", "$root/usr/local/libexec/xcat-network.sh") or croak $!;
    copy($planner, "$root/usr/local/libexec/confignetwork-freebsd.awk") or croak $!;
    write_file("$root/dev/null", '');
    for my $command (qw(ifconfig route nc sleep)) {
        write_file("$root/bin/$command", "#!/bin/sh\nprintf '%s %s\\n' '$command' \"\$*\" >> /fixture/commands\n");
        chmod(oct('0555'), "$root/bin/$command") == 1 or croak $!;
    }
    my $invoke = sub {
        return xCAT::FreeBSDPkg::run_command(['/usr/sbin/chroot', $root, '/bin/sh', '-eu', '-c',
            '. /usr/local/libexec/xcat-install-lib.sh; xcat_read_config /fixture/config; XCAT_PROVISIONING_IF=vtnet0; xcat_install_ipv6'],
            environment => {PATH => '/bin:/usr/bin', LC_ALL => 'C'}, timeout => 10);
    };
    write_file("$root/fixture/config", $configuration);
    my $result = $invoke->();
    is($result->{exitcode}, 0, 'the generated policy reaches the actual network initializer') or diag($result->{stderr});
    open(my $commands, '<', "$root/fixture/commands") or croak $!;
    my $calls = do { local $/ = undef; <$commands> };
    close($commands) or croak $!;
    is($calls, "ifconfig vtnet0 mtu 1500 up\nifconfig vtnet0 inet6 -ifdisabled\n"
        . "ifconfig vtnet0 inet6 2001:db8:1::10/64 alias\nnc -6 -z -w 2 -s 2001:db8:1::10 2001:db8:1::1 3002\n",
        'IPv6 setup binds the readiness probe to the configured source');
    for my $change ([ipv6 => '::'], [ipv6_gateway => '2001:db8:2::1'], [ipv6_prefix => '129'],
        [ipv6_mtu => '1279'], [master => '192.0.2.1'], [nameservers => '192.0.2.53'],
        [install_url => 'http://[2001:db8:1::1]:0/install'], [ipv6_prefix => undef]) {
        my $bad = $configuration;
        my ($key, $value) = @$change;
        $bad =~ s/^\Q$key\E=.*\n/defined($value) ? "$key=$value\n" : ''/emx;
        write_file("$root/fixture/config", $bad);
        unlink("$root/fixture/commands") or croak $! if -e "$root/fixture/commands";
        my $failed = $invoke->();
        isnt($failed->{exitcode}, 0, 'malformed wire policy fails in the shipped shell reader');
        ok(!-e "$root/fixture/commands", 'rejection precedes all network commands');
    }
    my $inventory = {nictypes => 'vtnet0!ethernet,vtnet1!ethernet,lagg0!lagg,vlan100!vlan,bridge0!bridge',
        nicdevices => 'lagg0!vtnet0|vtnet1,vlan100!lagg0,bridge0!vlan100',
        nicextraparams => 'lagg0!LAGGPROTO=failover,bridge0!STP=no',
        nicsadapter => 'vtnet0!mac=52:54:00:12:34:56,vtnet1!mac=52:54:00:12:34:57'};
    my $encoded = xCAT::FreeBSDNetwork::encode('bridge0', $network->{mac}, $inventory, $planner);
    write_file("$root/fixture/config", render(undef, undef, {%$settings, bootstrap_network_base64 => $encoded}));
    my $handoff = xCAT::FreeBSDPkg::run_command(['/usr/sbin/chroot', $root, '/bin/sh', '-eu', '-c',
        '. /usr/local/libexec/xcat-install-lib.sh; . /usr/local/libexec/xcat-network.sh; '
        . 'xcat_read_config /fixture/config; XCAT_WORK=/fixture; xcat_network_rc'],
        environment => {PATH => '/bin:/usr/bin', LC_ALL => 'C'}, timeout => 10);
    is($handoff->{exitcode}, 0, 'the shipped bootstrap compiler renders the installed IPv6 topology') or diag($handoff->{stderr});
    like($handoff->{stdout}, qr/^ifconfig_bridge0_ipv6="inet6[ ]2001:0db8:0001:0000:0000:0000:0000:0010[ ]prefixlen[ ]64"$/mx,
        'the installed address belongs to the bridge above VLAN and LAGG');
    unlike($handoff->{stdout}, qr/\binet[ ]|SYNCDHCP/x, 'no temporary IPv4 bootstrap address persists in the installed graph');
    my $normal = xCAT::FreeBSDPkg::run_command(['/usr/bin/awk', '-v', 'bootnic=vtnet0', '-v', "bootmac=$network->{mac}",
        '-v', 'configure_boot=1', '-f', $planner], environment => {LC_ALL => 'C',
        NICTYPES => $inventory->{nictypes}, NICDEVICES => $inventory->{nicdevices},
        NICEXTRAPARAMS => $inventory->{nicextraparams}, NICIPS => 'bridge0!2001:db8:1::10',
        NICNETWORKS => 'bridge0!management', IPADDR => '2001:db8:1::10', NETWORKS_LINES => 1,
        NETWORKS_LINE1 => 'netname=management||net=2001:db8:1::||mask=64||gateway=||mtu=1500||disable='}, timeout => 10);
    is($normal->{exitcode}, 0, 'the regular postscript accepts the same IPv6 management graph') or diag($normal->{stderr});
    open(my $saved, '<', "$root/fixture/target-network.plan") or croak $!;
    my $ownership = do { local $/ = undef; <$saved> };
    close($saved) or croak $!;
    is($ownership, $normal->{stdout}, 'installer ownership matches later network management byte for byte');
    my $observed = <<'IFCONFIG';
vtnet0: flags=1008843<UP,BROADCAST,RUNNING,MULTICAST,LOWER_UP> metric 0 mtu 1500
    ether 52:54:00:12:34:56
    nd6 options=29<PERFORMNUD,IFDISABLED,AUTO_LINKLOCAL>
vtnet1: flags=1008843<UP,BROADCAST,RUNNING,MULTICAST,LOWER_UP> metric 0 mtu 1500
    ether 52:54:00:12:34:57
    nd6 options=29<PERFORMNUD,IFDISABLED,AUTO_LINKLOCAL>
lagg0: flags=1008843<UP,BROADCAST,RUNNING,MULTICAST,LOWER_UP> metric 0 mtu 1500
    ether 52:54:00:12:34:56
    laggproto failover lagghash l2,l3,l4
    laggport: vtnet0 flags=5<MASTER,ACTIVE>
    laggport: vtnet1 flags=0<>
    nd6 options=29<PERFORMNUD,IFDISABLED,AUTO_LINKLOCAL>
vlan100: flags=1008843<UP,BROADCAST,RUNNING,MULTICAST,LOWER_UP> metric 0 mtu 1500
    ether 52:54:00:12:34:56
    vlan: 100 vlanpcp: 0 parent interface: lagg0
    nd6 options=29<PERFORMNUD,IFDISABLED,AUTO_LINKLOCAL>
bridge0: flags=1008843<UP,BROADCAST,RUNNING,MULTICAST,LOWER_UP> metric 0 mtu 1500
    ether 52:54:00:12:34:56
    member: vlan100 flags=143<LEARNING,DISCOVER,AUTOEDGE,AUTOPTP>
    inet 192.0.2.200 netmask 0xffffff00 broadcast 192.0.2.255
    nd6 options=29<PERFORMNUD,IFDISABLED,AUTO_LINKLOCAL>
IFCONFIG
    write_file("$root/bin/ifconfig", "#!/bin/sh\n[ \"\$*\" = -a ] || exit 1\ncat /fixture/observed\n");
    my $readback = sub {
        write_file("$root/fixture/observed", shift);
        return xCAT::FreeBSDPkg::run_command(['/usr/sbin/chroot', $root, '/bin/sh', '-eu', '-c',
            '. /usr/local/libexec/xcat-install-lib.sh; xcat_read_config /fixture/config; '
            . 'XCAT_WORK=/fixture; XCAT_PROVISIONING_IF=bridge0; XCAT_BOOTSTRAP_MODE=dhcp; '
            . 'XCAT_BOOT_NETWORK_PLAN=/fixture/target-bootstrap.plan; '
            . 'XCAT_BOOT_NETWORK_BASE64=$XCAT_BOOTSTRAP_NETWORK_BASE64; xcat_check_bootstrap'],
            environment => {PATH => '/bin:/usr/bin', LC_ALL => 'C'}, timeout => 10);
    };
    my $checked = $readback->($observed);
    is($checked->{exitcode}, 0, 'the IPv6 bootstrap readback accepts one DHCPv4 lease on the bridge') or diag($checked->{stderr});
    my $strict = xCAT::FreeBSDPkg::run_command(['/usr/sbin/chroot', $root, '/usr/bin/awk', '-v', 'mode=verify',
        '-f', '/usr/local/libexec/confignetwork-freebsd.awk', '/fixture/bootstrap.expected', '/fixture/observed'], timeout => 10);
    isnt($strict->{exitcode}, 0, 'ordinary network readback still rejects that undeclared address');
    for my $case ('missing lease', 'second lease', 'member address', 'missing member', 'wrong MAC', 'wrong MTU') {
        my $bad = $observed;
        $bad =~ s/^[ ]{4}inet[ ].*\n//mx if $case eq 'missing lease';
        $bad .= "    inet 192.0.2.201 netmask 0xffffff00\n" if $case eq 'second lease';
        $bad =~ s/(vtnet1:[^\n]*\n)/$1    inet 192.0.2.201 netmask 0xffffff00\n/x if $case eq 'member address';
        $bad =~ s/^[ ]{4}laggport:[ ]vtnet1[^\n]*\n//mx if $case eq 'missing member';
        $bad =~ s/(bridge0:[^\n]*\n[ ]{4}ether[ ])52:54:00:12:34:56/${1}52:54:00:12:34:58/x if $case eq 'wrong MAC';
        $bad =~ s/mtu[ ]1500/mtu 1400/x if $case eq 'wrong MTU';
        my $rejected = $readback->($bad);
        isnt($rejected->{exitcode}, 0, "$case is rejected by bootstrap readback");
    }
};

subtest 'IPv6 status reporting verifies the resolved node identity' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $token = xCAT::FreeBSDInstall::prepare('node1', 'a' x 64, directory => "$root/state");
    my @commands;
    no warnings 'redefine';
    local *xCAT::NetworkUtils::clearcache = sub { return; };
    my $resolver = \&xCAT::NetworkUtils::getipaddr;
    local *xCAT::NetworkUtils::getipaddr = sub {
        my ($class, $node, %options) = @_;
        return $resolver->(@_) unless $node eq 'node1';
        return $options{OnlyV6} ? '2001:db8:1::10' : undef;
    };
    my $dispatch = sub {
        my $request = shift;
        push @commands, $request;
        $xCAT::Table::rows{nodelist}{node1}{status} = $request->{arg}[0];
        return {};
    };
    my $message = 'freebsd-install-v1 ' . $token . ' ' . ('b' x 32) . " begin\n";
    for my $peer ('2001:db8:1::11', '192.0.2.10', 'fe80::10', '2001:db8:1::10%vtnet0') {
        ok(!eval { xCAT::FreeBSDInstall::handle_status('node1', $peer, $message, $dispatch, directory => "$root/state"); 1 },
            'another or scoped source cannot claim the install');
    }
    is_deeply(\@commands, [], 'rejected peers do not change controller state');
    my $reply = eval { xCAT::FreeBSDInstall::handle_status('node1', '2001:DB8:1:0:0:0:0:10',
        $message, $dispatch, directory => "$root/state") };
    is($reply, "freebsd-install-v1 $token begin ok\n", 'equivalent IPv6 spelling acknowledges the real transition') or diag($@);
    is(xCAT::FreeBSDInstall::state('node1', directory => "$root/state")->{phase}, 'installing',
        'the IPv6 report advances the persisted lifecycle');
};

done_testing();
