#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $dir = tempdir(CLEANUP => 1);
make_path("$dir/db");
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "SQLite:$dir/db";
require xCAT::Schema;
require xCAT::SvrUtils;
require xCAT::Table;
require xCAT::DBobjUtils;

sub build_nfsroot {
    return xCAT::SvrUtils->build_statelite_nfsroot_parameter('192.0.2.1', '/install/netboot/test/rootimg', shift);
}

my ($parameter, $error) = build_nfsroot(undef);
is($parameter, 'root=nfs:192.0.2.1:/install/netboot/test/rootimg:ro', 'unset options preserve the read-only default');
is($error, undef, 'unset options are valid');

($parameter, $error) = build_nfsroot('');
is($parameter, 'root=nfs:192.0.2.1:/install/netboot/test/rootimg:ro', 'empty options preserve the read-only default');
is($error, undef, 'empty options are valid');

($parameter, $error) = build_nfsroot('noac,actimeo=0');
is($parameter, 'root=nfs:192.0.2.1:/install/netboot/test/rootimg:ro,noac,actimeo=0', 'additional options follow the mandatory read-only option');
is($error, undef, 'valid additional options are accepted');

($parameter, $error) = build_nfsroot('ro,nfsvers=4.1');
is($parameter, 'root=nfs:192.0.2.1:/install/netboot/test/rootimg:ro,nfsvers=4.1', 'a redundant read-only option is normalized');
is($error, undef, 'a redundant read-only option is valid');

($parameter, $error) = build_nfsroot('clientaddr=2001:db8::1');
is($parameter, 'root=nfs:192.0.2.1:/install/netboot/test/rootimg:ro,clientaddr=2001:db8::1', 'option values may contain colons');
is($error, undef, 'an option value containing colons is valid');

foreach my $invalid ('rw', 'RW', 'noac,rw', 'defaults', 'noac, actimeo=0', 'noac,,actimeo=0') {
    ($parameter, $error) = build_nfsroot($invalid);
    is($parameter, undef, "invalid option list '$invalid' is rejected");
    like($error, qr/^nfsrootopts /, "invalid option list '$invalid' reports the attribute name");
    like(
        xCAT::SvrUtils->validate_statelite_nfsroot_options($invalid),
        qr/^nfsrootopts /,
        "command-time validation rejects '$invalid'"
    );
}

is(xCAT::SvrUtils->validate_statelite_nfsroot_options(undef), undef, 'command-time validation accepts an unset value');
is(xCAT::SvrUtils->validate_statelite_nfsroot_options(''), undef, 'command-time validation accepts an empty value');
is(xCAT::SvrUtils->validate_statelite_nfsroot_options('noac,actimeo=0'), undef, 'command-time validation accepts valid options');

ok(
    scalar(grep { $_ eq 'nfsrootopts' } @{ $xCAT::Schema::tabspec{osimage}->{cols} }),
    'osimage table includes nfsrootopts'
);
is(
    $xCAT::Schema::defspec{osimage}->{attrhash}->{nfsrootopts}->{tabentry},
    'osimage.nfsrootopts',
    'osimage object exposes nfsrootopts'
);

my %site = (installdir => "$dir/install", tftpdir => "$dir/tftp",
    master => '192.0.2.1', disablenodesetwarning => 1, xcatdebugmode => 0);
for my $key (keys %site) {
    set_row('site', { key => $key }, { value => $site{$key} });
}

no warnings qw(redefine once);
local *xCAT::NetworkUtils::determinehostname = sub { return 'localhost'; };
local *xCAT::Utils::isServiceNode = sub { return 0; };
local *xCAT::DBobjUtils::getNetwkInfo = sub { return (node => { mgtifname => 'eth0' }); };
local $::DISABLENODESETWARNING = 1;
local %::XCATSITEVALS = %site;
use warnings;

my @cases = (
    [unset => undef, 'ro'], [blank => '', 'ro'],
    [custom => 'noac,actimeo=0', 'ro,noac,actimeo=0'],
    [readonly => 'ro,nfsvers=4.1', 'ro,nfsvers=4.1'],
    [ipv6 => 'clientaddr=2001:db8::1', 'ro,clientaddr=2001:db8::1'],
    [invalid => 'rw', undef], [spaces => 'noac, actimeo=0', undef],
);
for my $owner ([anaconda => 'rhels8'], [debian => 'ubuntu24.04'], [sles => 'sles15']) {
    my ($plugin, $os) = @$owner;
    require(repo_path("xCAT-server/lib/xcat/plugins/$plugin.pm"));
    my $run = "xCAT_plugin::${plugin}"->can('mknetboot');
    for my $mode (qw(named legacy)) {
        for my $case (@cases) {
            my ($label, $options, $expected) = @$case;
            subtest "$plugin $mode $label" => sub {
                my $profile = "$mode-$label";
                my $image = "$os-x86_64-statelite-$profile";
                my $root = "$dir/install/netboot/$os/x86_64/$profile";
                make_path("$root/rootimg/etc");
                write_binary("$root/kernel", 'kernel fixture');
                write_binary("$root/initrd-statelite.gz", 'initrd fixture');
                write_binary("$root/rootimg/etc/dracut.conf", '');
                set_row('nodetype', { node => 'node' }, { os => $os, arch => 'x86_64',
                    profile => $profile, provmethod => $mode eq 'named' ? $image : 'statelite' });
                set_row('osimage', { imagename => $image }, { osvers => $os, osarch => 'x86_64',
                    profile => $profile, provmethod => 'statelite', rootfstype => 'nfs',
                    nfsrootopts => $options });
                set_row('linuximage', { imagename => $image }, { rootimgdir => $root });
                set_row('noderes', { node => 'node' }, { xcatmaster => '192.0.2.1',
                    nfsserver => '192.0.2.2', nfsdir => '', installnic => 'eth0' });
                set_row('nodehm', { node => 'node' }, {});
                set_row('mac', { node => 'node' }, { mac => '02:00:00:00:00:01' });
                set_row('statelite', { node => 'node' }, { statemnt => '192.0.2.3:/state' });
                my $boot = {};
                my @errors;
                $run->({ command => ['mkstatelite'], node => ['node'], bootparams => \$boot },
                    sub {
                        push @errors, @{ $_[0]->{error} || [] };
                        push @errors, map { @{ $_->{error} || [] } } @{ $_[0]->{node} || [] };
                    },
                    sub { die 'Unexpected nested request'; });
                if ($plugin eq 'debian' && $mode eq 'legacy') {
                    like(join('\n', @errors), qr/OS image name must be specified/,
                        'Debian rejects deprecated node definitions');
                    ok(!exists $boot->{node}, 'no boot parameters are published');
                    return;
                }
                if (!defined $expected) {
                    like(join('\n', @errors), qr/nfsrootopts /, 'invalid options report the attribute');
                    ok(!exists $boot->{node}, 'invalid options do not publish boot parameters');
                    return;
                }
                is_deeply(\@errors, [], 'caller succeeds');
                my $params = $boot->{node}->[0] || {};
                my @roots = grep { /^root=/ } split /\s+/, $params->{kcmdline} || '';
                is_deeply(\@roots, ["root=nfs:192.0.2.2:$root/rootimg:$expected"],
                    'boot parameters preserve server, path and options');
                like($params->{kcmdline}, qr/\bSTATEMNT=192\.0\.2\.3:\/state\b/,
                    'the state mount remains separate from the root options');
                is($params->{kernel} ? read_binary("$dir/tftp/$params->{kernel}") : undef,
                    'kernel fixture', 'kernel is staged');
                is($params->{initrd} ? read_binary("$dir/tftp/$params->{initrd}") : undef,
                    'initrd fixture', 'initrd is staged');
            };
        }
    }
}

done_testing();

sub set_row {
    my ($name, $key, $values) = @_;
    my $table = xCAT::Table->new($name, -create => 1);
    $table->setAttribs($key, $values);
    $table->close();
}
