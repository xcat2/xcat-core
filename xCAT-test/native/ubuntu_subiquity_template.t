#!/usr/bin/env perl
use strict;
use warnings;
use File::Copy qw(copy);
use Capture::Tiny qw(capture);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use JSON::PP qw(encode_json decode_json);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);
use XCAT::Test::Template qw(template_database set_row render_template);

plan skip_all => 'Subiquity command execution requires Linux' unless $^O eq 'linux';
my $database = template_database();
require xCAT::SvrUtils;
set_row('noderes', {node => 'node'}, {xcatmaster => '127.0.0.1'});
write_text("$database/extra.pkglist", "htop\nwget\n");
write_text("$database/image.pkglist", "#INCLUDE:$database/extra.pkglist#\nvim\n");

sub load_yaml {
    my ($file) = @_;
    my ($stdout, $stderr, $status) = capture {
        system('/usr/bin/python3', '-I', '-c',
            'import json, sys, yaml; json.dump(yaml.safe_load(open(sys.argv[1])), sys.stdout)', $file)
    };
    die "Cannot parse $file: $stderr" if $status;
    return decode_json($stdout);
}

sub render {
    my ($version, $arch, $nic, $primary) = @_;
    set_row('nodetype', {node => 'node'}, {os => "ubuntu$version", arch => $arch, provmethod => 'image'});
    set_row('noderes', {node => 'node'}, {installnic => $nic, primarynic => $primary});
    my $template = xCAT::SvrUtils->get_tmpl_file_name(
        repo_path('xCAT-server/share/xcat/install/ubuntu'), 'compute', "ubuntu$version", $arch, 'subiquity');
    my $output = "$database/autoinstall.yaml";
    render_template($database, $template, $output, 'node', "$database/image.pkglist",
        "/install/ubuntu$version/$arch", 'ubuntu', undef, {xcatmaster => '127.0.0.1'}, osarch => $arch);
    my $text = read_text($output);
    like($text, qr/\A#cloud-config\n/, 'renders a cloud-config document');
    unlike($text, qr/#(?:TABLE|CRYPT|SUBIQUITY|INCLUDE|XCATVAR)[^\n]*#/, 'resolves all template inputs');
    return (load_yaml($output)->{autoinstall}, $text);
}

for my $release (qw(20.04 22.04 24.04 26.04)) {
    subtest "Ubuntu $release data" => sub {
        my ($config) = render($release, 'x86_64', '', '');
        is($config->{version}, 1, 'uses autoinstall version 1');
        is_deeply($config->{identity}, {
            realname => 'xCAT Admin', username => 'xcatadm', hostname => 'node', password => '*',
        }, 'supplies a noninteractive identity with a locked password');
        is($config->{kernel}{package}, 'linux-generic', 'selects the generic kernel');
        ok($config->{ssh}{'install-server'}, 'installs the SSH server');
        ok(!$config->{'user-data'}{package_update} && !$config->{'user-data'}{package_upgrade}, 'leaves automatic package updates disabled');
        is($config->{'user-data'}{timezone}, 'UTC', 'uses the site timezone');
        my %packages;
        $packages{$_}++ for @{$config->{packages}};
        is($packages{$_}, 1, "installs $_ once") for qw(openssh-server wget htop vim);
        ok(!$packages{'nfs-common'}, 'does not require NFS tools from the offline media');
        ok(!$config->{apt}{geoip}, 'keeps mirror geolocation disabled');
        is($config->{apt}{'mirror-selection'}{primary}[0]{uri}, 'http://archive.ubuntu.com/ubuntu', 'selects the x86 archive');
        if ($release eq '20.04' || $release eq '22.04') {
            is($config->{apt}{sources}{'xcat-ubuntu-archive.list'}{source},
                'deb http://archive.ubuntu.com/ubuntu $RELEASE main restricted universe multiverse',
                'defers the legacy apt suite to the installer release');
        } else {
            ok(!exists $config->{apt}{sources}{'xcat-ubuntu-archive.list'}, 'does not duplicate the Deb822 primary mirror');
        }
    };
}

my @cases = (
    ['named', 'eno2', '', 'eno2', 0],
    ['primary', '', 'ens3', 'ens3', 0],
    ['mac', '', '', undef, 0],
    ['literal-mac', '52:54:00:12:34:56', 'ens3', undef, 0],
    ['unresolved', 'eno2', '', 'eno2', 0],
    ['fail-disk', '', '', undef, 8],
    ['empty-disk', '', '', undef, 1],
    ['fail-pre', '', '', undef, 8],
    ['empty-pre', '', '', undef, 1],
    ['no-partition', '', '', undef, 1],
    ['post-failure', '', '', undef, 42],
);
for my $case (@cases) {
    my ($name, $nic, $primary, $rename, $expected_status) = @$case;
    subtest "installer $name" => sub {
        my ($config, $text) = render('24.04', 'riscv64', $nic, $primary);
        is($config->{apt}{'mirror-selection'}{primary}[0]{uri}, 'http://ports.ubuntu.com/ubuntu-ports', 'selects the RISC-V ports archive');
        my $root = sandbox_root();
        make_path(map { "$root/$_" } qw(payloads target/etc/default target/etc/apt/sources.list.d target/etc/apt/apt.conf.d target/root));
        write_text("$root/autoinstall.yaml", "$text\n...\n");
        write_text("$root/commands.json", encode_json($config));
        write_text("$root/etc/resolv.conf", "nameserver 192.0.2.53\n");
        my $hosts = "127.0.0.1 localhost\n";
        $hosts .= "127.0.1.1 oldname\n" if $name eq 'named';
        write_text("$root/target/etc/hosts", $hosts);
        write_text("$root/target/etc/default/grub", "GRUB_TIMEOUT=5\n");
        my @temporary_sources = qw(xcat-otherpkgs-0.list xcat-otherpkgs-1.sources xcat-pkgdir-0.list xcat-pkgdir-1.sources);
        write_text("$root/target/etc/apt/sources.list.d/$_", "temporary\n") for @temporary_sources;
        write_text("$root/target/etc/apt/sources.list.d/admin.list", "preserved\n");
        write_text("$root/target/etc/apt/apt.conf.d/94curtin-config", "temporary\n");
        write_text("$root/payloads/getinstdisk", "#!/bin/sh\nprintf /dev/vda >/tmp/install_disk\n");
        write_text("$root/payloads/node.pre", <<'SH');
#!/bin/sh
printf ran >/fixture/pre-ran
[ "$XCAT_TEST_SCENARIO" != no-partition ] || exit 0
printf '  storage:\n    layout:\n      name: direct\n' >/tmp/partitionfile
SH
        write_text("$root/payloads/node.post", <<'SH');
#!/bin/sh
printf ran >/fixture/post-ran
[ "$XCAT_TEST_SCENARIO" != post-failure ] || exit 42
SH
        for my $command (qw(ip getent wget curtin)) {
            copy(repo_path('xCAT-test/fixtures/subiquity/command'), "$root/bin/$command") or die $!;
            chmod 0755, "$root/bin/$command" or die $!;
        }
        copy(repo_path('xCAT-test/fixtures/subiquity/run.pl'), "$root/run.pl") or die $!;
        my ($status, $output) = sandbox_run($root, {env => {XCAT_TEST_SCENARIO => $name}}, $^X, '/fixture/run.pl');
        unless (is($status, $expected_status, 'the complete command sequence returns the expected status')) {
            diag($output);
            diag(read_text("$root/$_")) for grep { -f "$root/$_" } qw(tmp/pre-install.log target/var/log/xcat/xcat.log statuses.json);
            return;
        }
        my $statuses = decode_json(read_text("$root/statuses.json"));
        is($statuses->[-1][1], $expected_status, 'the result comes from an installer command');
        if ($expected_status) {
            ok(!-e "$root/monitor-request", 'does not advance the boot chain after failure');
            is(read_text("$root/target/etc/apt/apt.conf.d/94curtin-config"), "temporary\n", 'does not run later cleanup after failure');
            ok(!-e "$root/post-ran", 'does not run the postscript after early failure') unless $name eq 'post-failure';
            return;
        }
        is(read_text("$root/monitor-request"), "next\n", 'advances through the real monitor handshake');
        is(read_text("$root/monitor-status"), "0\n", 'completes the monitor exchange');
        is(read_text("$root/pre-ran"), 'ran', 'executes the downloaded pre-script');
        is(read_text("$root/post-ran"), 'ran', 'executes the downloaded postscript');
        is(load_yaml("$root/final-autoinstall.yaml")->{autoinstall}{storage}{layout}{name}, 'direct', 'injects the supplied storage layout');
        is(read_text("$root/etc/resolv.conf"), ($name eq 'unresolved' ? "nameserver 192.0.2.53\n" : "nameserver 127.0.0.1\n") . "domain example.invalid\n", 'writes a numeric resolver or retains DHCP DNS');
        my $network = load_yaml("$root/target/etc/netplan/00-xcat-install.yaml")->{network};
        my %interface = (match => {macaddress => '52:54:00:12:34:56'}, dhcp4 => JSON::PP::true, 'dhcp4-overrides' => {'use-domains' => JSON::PP::true});
        $interface{'set-name'} = $rename if defined $rename;
        is_deeply($network, {version => 2, ethernets => {'xcat-install' => \%interface}}, 'writes the resolved interface and DHCP policy');
        is((stat("$root/target/etc/netplan/00-xcat-install.yaml"))[2] & oct('0777'), oct('0600'), 'restricts netplan permissions');
        is(read_text("$root/target/etc/hostname"), "node\n", 'writes the node hostname');
        is(read_text("$root/target/etc/hosts"), "127.0.0.1 localhost\n127.0.1.1 node\n", 'replaces or appends the local hostname');
        ok(-f "$root/target/etc/cloud/cloud-init.disabled", 'disables target cloud-init');
        is(read_text("$root/grub-input"), "GRUB_TIMEOUT=5\nGRUB_CMDLINE_LINUX=\"console=ttyS0 quiet\"\n", 'passes the quoted kernel command line to update-grub2');
        ok(!-e "$root/target/etc/apt/sources.list.d/$_", "removes $_ after the postscript") for @temporary_sources;
        ok(!-e "$root/target/etc/apt/apt.conf.d/94curtin-config", 'removes installer apt settings');
        is(read_text("$root/target/etc/apt/sources.list.d/admin.list"), "preserved\n", 'retains administrator sources');
    };
}

done_testing();
