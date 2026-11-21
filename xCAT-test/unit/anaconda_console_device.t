#!/usr/bin/env perl
#
# The console device anaconda.pm names on the kernel command line, per architecture.
#
# nodehm.serialport is a port NUMBER, so the plugin supplies the device name. It chose between
# hvc and ttyS only, so an aarch64 node was given console=ttyS0. An aarch64 platform presents
# its serial port as pl011, which Linux names ttyAMA0, so the node wrote its console to a device
# that does not exist and a provisioning failure left no record.
#
# mksysclone and mkinstall are not driven here. mksysclone rewrites /etc/systemimager and starts
# systemimager-server-rsyncd, and mkinstall needs an install tree. Every architecture of the
# policy itself is asserted in console_policy.t.
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
make_path("$fixture/db", "$fixture/root/lib/perl", "$fixture/tftpboot/xcat", "$fixture/install");
symlink(repo_path('perl-xCAT/xCAT'), "$fixture/root/lib/perl/xCAT") or die $!;
$ENV{XCATROOT} = "$fixture/root";
$ENV{XCATCFG}  = "SQLite:$fixture/db";

require xCAT::Table;
require xCAT::SvrUtils;
require xCAT::DBobjUtils;
require(repo_path('xCAT-server/lib/xcat/plugins/anaconda.pm'));

xCAT::Table->new('site', -create => 1)->setAttribs({ key => $_->[0] }, { value => $_->[1] })
  for ([ installdir => "$fixture/install" ], [ tftpdir => "$fixture/tftpboot" ], [ master => '192.0.2.1' ]);

my $NODE = 'cons1';
xCAT::Table->new('nodelist', -create => 1)->setAttribs({ node => $NODE }, { groups => 'compute' });
xCAT::Table->new('noderes',  -create => 1)->setAttribs({ node => $NODE }, { xcatmaster => '192.0.2.1' });
xCAT::Table->new('mac',      -create => 1)->setAttribs({ node => $NODE }, { mac => 'aa:bb:cc:dd:ee:ff' });

# The serial console the node is asked for. The port is a number, which is the whole reason the
# plugin has to name the device itself.
xCAT::Table->new('nodehm', -create => 1)
  ->setAttribs({ node => $NODE }, { serialport => '0', serialspeed => '115200' });

my %addresses = ( $NODE => { 4 => '192.0.2.50' } );
no warnings 'redefine';
*xCAT::NetworkUtils::getipaddr = sub {
    my $host = shift;
    $host = shift if defined($host) && $host eq 'xCAT::NetworkUtils';
    my %opts  = @_;
    my $entry = $addresses{$host} || {};
    return undef if $opts{OnlyV6};
    return $entry->{4};
};
*xCAT::NetworkUtils::my_ip_facing_family = sub { return ( 0, '192.0.2.1' ); };
use warnings 'redefine';

# image <provmethod>, <arch> -- an image of that provisioning method on that architecture, and
# the node that boots it. rootimgdir is explicit, so one directory serves every architecture.
sub image {
    my ( $provmethod, $arch ) = @_;
    my $name = "el10-$provmethod-$arch";
    my $dir  = "$fixture/install/netboot/rhels10.0/$arch/compute";
    make_path($dir);
    write_text( "$dir/$_", "$_\n" )
      for qw(kernel initrd-stateless.gz initrd-statelite.gz rootimg-statelite.gz rootimg.gz);
    write_text( "$fixture/tftpboot/xcat/genesis.kernel.$arch",    "kernel\n" );
    write_text( "$fixture/tftpboot/xcat/genesis.fs.$arch.lzma",   "initrd\n" );
    xCAT::Table->new('osimage', -create => 1)->setAttribs({ imagename => $name },
        { osvers => 'rhels10.0', osarch => $arch, profile => 'compute', provmethod => $provmethod });
    xCAT::Table->new('linuximage', -create => 1)->setAttribs({ imagename => $name }, { rootimgdir => $dir });
    xCAT::Table->new('nodetype', -create => 1)->setAttribs({ node => $NODE },
        { os => 'rhels10.0', arch => $arch, profile => 'compute', provmethod => $name });
    return $name;
}

# nodeset <command> -- drives the plugin and returns the kernel command line it wrote.
sub nodeset {
    my ($command) = @_;
    local %::XCATSITEVALS = (
        installdir => "$fixture/install",
        tftpdir    => "$fixture/tftpboot",
        httpmethod => 'http',
    );
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

# console <command>, <arch> -- the console device and speed on that command line.
sub console {
    my ( $command, $arch ) = @_;
    image( 'netboot', $arch );
    my $kcmdline = nodeset($command);
    ok( length($kcmdline), "$command on $arch writes a kernel command line at all" );
    my @consoles = $kcmdline =~ m{\bconsole=(\S+)}g;
    return join( ' ', grep { $_ ne 'tty0' } @consoles );
}

# pl011 is what an aarch64 platform presents, and Linux names it ttyAMA. This is the defect.
is( console( 'mknetboot', 'aarch64' ), 'ttyAMA0,115200',
    'a diskless aarch64 node is told to use the pl011 console' );

# The two architectures that were already right. They are the discriminators: a change that
# renamed every console device would fail these.
is( console( 'mknetboot', 'ppc64le' ), 'hvc0,115200',
    'a diskless ppc64le node keeps the hypervisor console' );
is( console( 'mknetboot', 'x86_64' ), 'ttyS0,115200',
    'a diskless x86_64 node keeps the 16550 console' );

done_testing();
