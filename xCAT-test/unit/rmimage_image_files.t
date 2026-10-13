#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(realpath);
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use Sys::Hostname qw(hostname);
use Test::More;
use XCAT::Test::File qw(repo_path);

plan skip_all => 'rmimage runs only on Linux' unless $^O eq 'linux';

my $fixture = realpath(tempdir(CLEANUP => 1));
make_path("$fixture/db", "$fixture/root/lib/perl", "$fixture/tftpboot");
symlink(repo_path('perl-xCAT/xCAT'), "$fixture/root/lib/perl/xCAT") or die $!;
$ENV{XCATROOT} = "$fixture/root";
$ENV{XCATCFG}  = "SQLite:$fixture/db";
require xCAT::Table;
require(repo_path('xCAT-server/lib/xcat/plugins/rmimage.pm'));

# The image lock lives in /var/lock/xcat, so the test records the request instead.
our @LOCKED;
{
    no warnings qw(redefine once);
    *xCAT::Utils::acquire_lock_imageop = sub { push @LOCKED, $_[1]; return (0, {}) };
}

xCAT::Table->new('site', -create => 1)->setAttribs({ key => $_->[0] }, { value => $_->[1] })
  for ([ installdir => "$fixture/install" ], [ tftpdir => "$fixture/tftpboot" ]);
(my $host = hostname()) =~ s/[^A-Za-z0-9.-]/_/g;
my $dir = "$fixture/install/netboot/lite";
make_path("$dir/rootimg/etc", "$dir/.packimage-$host+ABANDONE", "$dir/.packimage-other.host+WRITING1");
write_text("$dir/.packimage-$host+ABANDONE/rootimg-statelite.gz", "partial archive\n");
write_text("$dir/.packimage-other.host+WRITING1/rootimg.cpio.gz", "archive that another host writes\n");
make_path("$dir/.packimage-$host+KEEPPREV");
write_text("$dir/.packimage-$host+KEEPPREV/previous", "previous archive that a failed publication keeps in staging\n");
make_path("$dir/.rootimg-previous-KEPTARCH");
write_text("$dir/.rootimg-previous-KEPTARCH/rootimg.cpio.gz", "previous archive that a failed publication kept\n");
my @image_files = qw(kernel initrd-stateless.gz initrd-stateless.gz.rootimgcheck initrd-statelite.gz
  rootimg.cpio.gz rootimg.cpio.gz.sha256 rootimg.cpio.gz.metainfo
  rootimg-statelite.gz rootimg-statelite.gz.sha256 rootimg-statelite.gz.metainfo);
write_text("$dir/$_", "$_\n") for (@image_files, 'notes.txt');
xCAT::Table->new('osimage', -create => 1)->setAttribs({ imagename => 'lite' },
    { osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'statelite' });
xCAT::Table->new('linuximage', -create => 1)->setAttribs({ imagename => 'lite' }, { rootimgdir => $dir });

my @responses;
{
    no warnings 'once';
    local %::XCATSITEVALS = (installdir => "$fixture/install", tftpdir => "$fixture/tftpboot");
    xCAT_plugin::rmimage::process_request({ arg => ['lite'] }, sub { push @responses, @_ }, sub { });
}
is(join("\n", map { @{ $_->{error} || [] } } @responses), '', 'rmimage reports no error');
is_deeply(\@LOCKED, ["$dir/rootimg"], 'rmimage holds the image lock');
is_deeply([ grep { -e "$dir/$_" } @image_files ], [], 'the archives, their checksums and metainfo, and the marker are removed');
ok(!-e "$dir/rootimg", 'the image tree is removed');
ok(!-e "$dir/.packimage-$host+ABANDONE", 'a temporary directory that this host abandoned is removed');
ok(-e "$dir/.packimage-other.host+WRITING1/rootimg.cpio.gz", 'a temporary directory of another host stays');
ok(!-e "$dir/.packimage-$host+KEEPPREV", 'a temporary directory that keeps the previous archive of a failed publication is removed with the image');
ok(!-e "$dir/.rootimg-previous-KEPTARCH", 'a previous archive that a failed publication kept is removed with the image');
ok(-e "$dir/notes.txt", 'a file that is not part of the image stays');

{
    # The image directory has a space, and the first word of its path names another directory, which stays.
    my $spaced = "$fixture/install/netboot/custom images/lite";
    make_path("$spaced/rootimg/etc", "$spaced/.rootimg-previous-KEPTARCH", "$fixture/install/netboot/custom/keep");
    write_text("$spaced/$_", "$_\n") for qw(rootimg.cpio.gz rootimg-statelite.gz.sha256);
    xCAT::Table->new('osimage')->setAttribs({ imagename => 'spaced' },
        { osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'statelite' });
    xCAT::Table->new('linuximage')->setAttribs({ imagename => 'spaced' }, { rootimgdir => $spaced });
    my @spaced_responses;
    {
        no warnings 'once';
        local %::XCATSITEVALS = (installdir => "$fixture/install", tftpdir => "$fixture/tftpboot");
        xCAT_plugin::rmimage::process_request({ arg => ['spaced'] }, sub { push @spaced_responses, @_ }, sub { });
    }
    is(join("\n", map { @{ $_->{error} || [] } } @spaced_responses), '', 'rmimage of an image directory with a space reports no error');
    ok(!-e "$spaced/rootimg.cpio.gz" && !-e "$spaced/rootimg-statelite.gz.sha256", 'the archives of the image directory with a space are removed');
    ok(!-e "$spaced/.rootimg-previous-KEPTARCH", 'a kept previous archive of the image directory with a space is removed');
    ok(-d "$fixture/install/netboot/custom/keep", 'the directory that the first word of the image directory names stays');
}

done_testing();
