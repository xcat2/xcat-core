#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

my $fixture = tempdir(CLEANUP => 1);
make_path("$fixture/db");
$ENV{XCATCFG} = "SQLite:$fixture/db";
require xCAT::Table;
require xCAT::SvrUtils;

my $osimage    = xCAT::Table->new('osimage',    -create => 1);
my $linuximage = xCAT::Table->new('linuximage', -create => 1);
my $site       = xCAT::Table->new('site',       -create => 1);

# The images that a release without the root image check left.
$osimage->setAttribs({ imagename => $_->[0] }, { provmethod => $_->[1] })
  for ([ stateless => 'netboot' ], [ lite => 'statelite' ], [ checked => 'netboot' ], [ diskful => 'install' ], [ bare => 'netboot' ]);
$linuximage->setAttribs({ imagename => $_ }, { rootimgdir => "/install/netboot/$_" }) for qw(stateless lite checked diskful);
$linuximage->setAttribs({ imagename => 'checked' }, { rootimgchecksum => 'yes' });

sub checksum {
    my ($row) = $linuximage->getAttribs({ imagename => $_[0] }, 'rootimgchecksum');
    return $row ? $row->{rootimgchecksum} : undef;
}

sub site_value {
    my ($row) = $site->getAttribs({ key => 'rootimgchecksum' }, 'value');
    return $row ? $row->{value} : undef;
}

is(xCAT::SvrUtils->upgrade_rootimg_checksum(), undef, 'the upgrade step reports no error');
is(checksum('stateless'), 'no', 'a stateless image of the earlier release keeps booting unchecked');
is(checksum('lite'),      'no', 'a statelite image of the earlier release keeps booting unchecked');
is(checksum('bare'),      'no', 'a stateless image without a linuximage row keeps booting unchecked');
is(checksum('checked'),   'yes', 'an image that sets the attribute keeps it');
is(checksum('diskful'),   undef, 'an image that nodes install is left alone');
is(site_value(),          'yes', 'new images get the check');

# A later upgrade finds site.rootimgchecksum set.
$osimage->setAttribs({ imagename => 'new' }, { provmethod => 'netboot' });
$linuximage->setAttribs({ imagename => 'new' }, { rootimgdir => '/install/netboot/new' });
is(xCAT::SvrUtils->upgrade_rootimg_checksum(), undef, 'a later upgrade reports no error');
is(checksum('new'), undef, 'a later upgrade leaves the check of a new image on');

# An administrator turned the check off for the site before the upgrade.
$site->setAttribs({ key => 'rootimgchecksum' }, { value => 'no' });
is(xCAT::SvrUtils->upgrade_rootimg_checksum(), undef, 'an upgrade with the site attribute set reports no error');
is(checksum('new'),  undef, 'an upgrade with the site attribute set changes no image');
is(site_value(),     'no', 'an upgrade keeps the site attribute that the administrator set');

done_testing();
