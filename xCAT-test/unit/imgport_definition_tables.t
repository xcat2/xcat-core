#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $fixture = tempdir(CLEANUP => 1);
make_path("$fixture/db", "$fixture/install");
$ENV{XCATCFG} = "SQLite:$fixture/db";
require xCAT::Table;
require(repo_path('xCAT-server/lib/xcat/plugins/imgport.pm'));
xCAT::Table->new('site', -create => 1)->setAttribs({ key => 'installdir' }, { value => "$fixture/install" });

# The import locks live in /var/lock/xcat, so the test grants them.
{
    no warnings qw(redefine once);
    *xCAT::Utils::acquire_lock_imageop = sub { return (0, {}) };
    *xCAT::Utils::acquire_lock         = sub { return {} };
}

my $published = "image that packimage published\n";
my $sequence  = 0;
my $new       = \&xCAT::Table::new;

for my $table (qw(osimage linuximage kit kitrepo kitcomponent)) {
    # The import cannot open a table of the image definition.
    my $name   = 'tables-' . ++$sequence;
    my $dest   = "$fixture/install/netboot/$name";
    my $bundle = "$fixture/bundle-$sequence";
    make_path($dest, $bundle);
    write_text("$dest/rootimg.cpio.gz",        $published);
    write_text("$dest/rootimg.cpio.gz.sha256", sha256_hex($published) . "  rootimg.cpio.gz\n");
    write_text("$dest/$_",   "published $_\n")       for qw(kernel initrd-stateless.gz);
    write_text("$bundle/$_", "$_ from the bundle\n") for qw(rootimg.cpio.gz kernel initrd-stateless.gz);
    xCAT::Table->new('osimage', -create => 1)->setAttribs({ imagename => $name }, { osvers => 'rhels9.5', provmethod => 'netboot' });
    my @errors;
    my $placed;
    {
        no warnings 'redefine';
        local *xCAT::Table::new = sub { return if $_[1] eq $table && caller() eq 'xCAT_plugin::imgport'; goto &$new };
        $placed = xCAT_plugin::imgport::place_image(
            {
                rootimg => "$dest/rootimg.cpio.gz",
                kernel  => "$dest/kernel",
                ramdisk => "$dest/initrd-stateless.gz",
                osimage => { imagename => $name, osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' },
            },
            $bundle, sub { push @errors, @{ $_[0]{error} || [] } });
    }
    ok(!$placed, "$table: an import fails when it cannot open the table");
    like(join("\n", @errors), qr/Unable to open table '\Q$table\E'/, "$table: the table is reported");
    is(read_binary("$dest/rootimg.cpio.gz"), $published, "$table: the published image stays");
    is(read_binary("$dest/rootimg.cpio.gz.sha256"), sha256_hex($published) . "  rootimg.cpio.gz\n", "$table: the published checksum stays");
    is(read_binary("$dest/$_"), "published $_\n", "$table: the published $_ stays") for qw(kernel initrd-stateless.gz);
    my ($row) = xCAT::Table->new('osimage')->getAttribs({ imagename => $name }, 'osvers');
    is($row && $row->{osvers}, 'rhels9.5', "$table: the image definition stays");
}

done_testing();
