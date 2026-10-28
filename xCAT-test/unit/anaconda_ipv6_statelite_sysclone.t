#!/usr/bin/env perl
#
# A statelite node and a cloned node take the static IPv6 address from the kernel command line,
# as a diskful and a diskless node already do.
#
# The firmware and the install initrd send different DHCPv6 identifiers and a reservation matches
# one, so an IPv6-only node is given its address directly. mknetboot excluded statelite with no
# reason recorded, and mksysclone had no IPv6 code at all, so both asked DHCPv6 with an identifier
# no reservation held and took a pool address.
use strict;
use warnings;
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(realpath);
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $fixture = realpath(tempdir(CLEANUP => 1));
make_path("$fixture/db", "$fixture/root/lib/perl", "$fixture/tftpboot", "$fixture/install");
symlink(repo_path('perl-xCAT/xCAT'), "$fixture/root/lib/perl/xCAT") or die $!;
$ENV{XCATROOT} = "$fixture/root";
$ENV{XCATCFG}  = "SQLite:$fixture/db";

require xCAT::Table;
require xCAT::SvrUtils;
require xCAT::DBobjUtils;
require(repo_path('xCAT-server/lib/xcat/plugins/anaconda.pm'));

xCAT::Table->new('site', -create => 1)->setAttribs({ key => $_->[0] }, { value => $_->[1] })
  for ([ installdir => "$fixture/install" ], [ tftpdir => "$fixture/tftpboot" ], [ master => '2001:db8::1' ]);

my $NODE = 'n6';
xCAT::Table->new('nodelist', -create => 1)->setAttribs({ node => $NODE }, { groups => 'compute' });
xCAT::Table->new('noderes',  -create => 1)->setAttribs({ node => $NODE }, { xcatmaster => '2001:db8::1' });
xCAT::Table->new('mac',      -create => 1)->setAttribs({ node => $NODE }, { mac => 'aa:bb:cc:dd:ee:ff' });

# The node answers on IPv6 only, which is what puts it on this path.
my %addresses = ( $NODE => { 6 => '2001:db8:1::50' } );
no warnings 'redefine';
*xCAT::NetworkUtils::getipaddr = sub {
    my $host = shift;
    $host = shift if defined($host) && $host eq 'xCAT::NetworkUtils';
    my %opts = @_;
    my $entry = $addresses{$host} || {};
    return $entry->{6} if $opts{OnlyV6};
    return undef if $opts{OnlyV4};
    return $entry->{6};
};
*xCAT::NetworkUtils::getNodeNetworkCfg6 = sub {
    my $node = shift;
    $node = shift if defined($node) && $node eq 'xCAT::NetworkUtils';
    return ( '2001:db8:1::50', $node, '2001:db8:1::fe', 64 );
};
*xCAT::NetworkUtils::my_ip_facing_family = sub { return ( 0, '2001:db8::1' ); };
use warnings 'redefine';

# image <provmethod> -- defines an image of that provisioning method and the node that boots it.
sub image {
    my ($provmethod, $rootfstype) = @_;
    my $name = "el10-$provmethod";
    my $dir  = "$fixture/install/netboot/rhels10.0/x86_64/compute";
    make_path($dir);
    write_text("$dir/$_", "$_\n")
      for qw(kernel initrd-stateless.gz initrd-statelite.gz rootimg-statelite.gz rootimg.gz);
    my %attrs = ( osvers => 'rhels10.0', osarch => 'x86_64', profile => 'compute', provmethod => $provmethod );
    $attrs{rootfstype} = $rootfstype if defined $rootfstype;
    xCAT::Table->new('osimage', -create => 1)->setAttribs({ imagename => $name }, \%attrs);
    xCAT::Table->new('linuximage', -create => 1)->setAttribs({ imagename => $name }, { rootimgdir => $dir });
    xCAT::Table->new('nodetype', -create => 1)->setAttribs({ node => $NODE },
        { os => 'rhels10.0', arch => 'x86_64', profile => 'compute', provmethod => $name });
    return $name;
}

# nodeset <command> -- drives the plugin and returns the kernel command line it wrote.
sub nodeset {
    my ($command) = @_;
    local %::XCATSITEVALS = (installdir => "$fixture/install", tftpdir => "$fixture/tftpboot", httpmethod => 'http');
    my $bootparams = {};
    my @responses;
    xCAT_plugin::anaconda::process_request(
        { command => [$command], node => [$NODE], bootparams => \$bootparams },
        sub { push @responses, @_ }, sub { });
    my @errors = map { ( @{ $_->{error} || [] },
                         map { @{ $_->{error} || [] } } @{ $_->{node} || [] } ) } @responses;
    diag("plugin said: $_") for @errors;
    return $bootparams->{$NODE}[0]{kcmdline} // '';
}

# The address, the gateway, the prefix, the host name and ":none", which is what turns DHCPv6 off
# in the initrd. The exact form is asserted in anaconda_ipv6_rendering.t.
my $STATIC = qr{\Qip=[2001:db8:1::50]::[2001:db8:1::fe]:64:\E\S*:\S*:none(?:\s|$)};

{
    image('statelite', 'ramdisk');
    my $kcmdline = nodeset('mkstatelite');
    ok(length($kcmdline), 'a statelite node gets a kernel command line at all');
    like($kcmdline, $STATIC, 'a statelite node takes the static IPv6 address');
    unlike($kcmdline, qr{\bip=dhcp\b}, 'and does not ask DHCPv6 for one');
}

{
    image('netboot');
    my $kcmdline = nodeset('mknetboot');
    like($kcmdline, $STATIC, 'a diskless node still takes it, so the statelite change did not move the gate');
}

{
    # A cloned node reaches the same dracut networking. mksysclone had no IPv6 code at all.
    # It boots the Genesis kernel from tftpboot rather than an image of its own.
    make_path("$fixture/tftpboot/xcat");
    write_text("$fixture/tftpboot/xcat/genesis.kernel.x86_64", "kernel\n");
    write_text("$fixture/tftpboot/xcat/genesis.fs.x86_64.lzma", "initrd\n");
    image('sysclone');
    my $kcmdline = nodeset('mksysclone');
    ok(length($kcmdline), 'a cloned node gets a kernel command line at all');
    like($kcmdline, $STATIC, 'a cloned node takes the static IPv6 address');
}

done_testing();
