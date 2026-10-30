use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Fcntl qw(S_IMODE);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

$ENV{XCATROOT} = repo_path('xCAT-server');
require(repo_path('xCAT-server/share/xcat/netboot/imgutils/imgutils.pm'));

my @both = ('etc/sysconfig/network-scripts', 'etc/NetworkManager/system-connections');

sub image {
    my $root = tempdir(CLEANUP => 1);
    make_path(map { "$root/$_" } @_);
    return $root;
}

sub mode {
    my ($file) = @_;
    return -f $file ? sprintf('%04o', S_IMODE((stat $file)[2])) : 'missing';
}

sub profiles {
    my ($root) = @_;
    return [map { substr($_, length($root) + 1) } sort glob("$root/{$both[0],$both[1]}/*")];
}

for my $case (['rhels10.1', 'etc/NetworkManager/system-connections'], ['alma10.1', @both]) {
    my ($os, @dirs) = @$case;
    my $root = image(@dirs);
    imgutils::write_nic_profiles($root, $os, 'eth0', 'eth1,,eth2');
    is_deeply(profiles($root), [map { "$both[1]/xcat-genimage-$_.nmconnection" } qw(eth1 eth2)],
        "a $os image with " . join(' and ', @dirs) . ' gets keyfiles for the requested interfaces only');
    for my $nic (qw(eth1 eth2)) {
        my $file = "$root/$both[1]/xcat-genimage-$nic.nmconnection";
        is(-f $file ? read_text($file) : '',
            "[connection]\nid=$nic\ntype=ethernet\ninterface-name=$nic\n\n[ipv4]\nmethod=auto\n",
            "the $os keyfile for $nic asks for DHCP");
        is(mode($file), '0600', "only root can read the $os keyfile for $nic");
    }
}

my $rebuilt = image($both[1]);
write_text("$rebuilt/$both[1]/site.nmconnection", "site profile\n");
imgutils::write_nic_profiles($rebuilt, 'rhels10.1', 'eth0', 'eth1,eth2');
imgutils::write_nic_profiles($rebuilt, 'rhels10.1', 'eth0', 'eth2');
is_deeply(profiles($rebuilt), ["$both[1]/site.nmconnection", "$both[1]/xcat-genimage-eth2.nmconnection"],
    'a rebuilt EL10 image drops the keyfile of an interface that is no longer requested and keeps other profiles');

my $el9 = image(@both);
imgutils::write_nic_profiles($el9, 'rhels9.6', 'eth0', 'eth1');
is_deeply(profiles($el9), ["$both[0]/ifcfg-eth0", "$both[0]/ifcfg-eth1"], 'an EL9 image gets ifcfg files only');
is(read_text("$el9/$both[0]/ifcfg-eth0"), "ONBOOT=no\nBOOTPROTO=dhcp\nDEVICE=eth0\n",
    'the EL9 interface of the initial ramdisk stays off at boot');
is(read_text("$el9/$both[0]/ifcfg-eth1"), "ONBOOT=yes\nBOOTPROTO=dhcp\nDEVICE=eth1\n",
    'the EL9 interface eth1 gets DHCP');
is(mode("$el9/$both[0]/ifcfg-eth1"), '0644', 'the EL9 ifcfg file keeps its permissions');

for my $os (qw(rhels10.1 rhels9.6)) {
    my $bare = image('etc');
    imgutils::write_nic_profiles($bare, $os, 'eth0', 'eth1');
    ok(!-e "$bare/etc/sysconfig" && !-e "$bare/etc/NetworkManager", "a $os image without either directory gets no profile");
}

done_testing();
