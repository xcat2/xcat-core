#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(realpath);
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $fixture = realpath(tempdir(CLEANUP => 1));
make_path("$fixture/db", "$fixture/root/lib/perl", "$fixture/root/share", "$fixture/tftpboot");
symlink(repo_path('perl-xCAT/xCAT'), "$fixture/root/lib/perl/xCAT") or die $!;
symlink(repo_path('xCAT-server/share/xcat'), "$fixture/root/share/xcat") or die $!;
$ENV{XCATROOT} = "$fixture/root";
$ENV{XCATCFG}  = "SQLite:$fixture/db";
require xCAT::Table;
require(repo_path('xCAT-server/lib/xcat/plugins/genimage.pm'));

# The genimage script builds the image and the initial ramdisk, so the test only records its command.
our @COMMANDS;
{
    no warnings qw(redefine once);
    *xCAT::Utils::runcmd = sub {
        my (undef, $command) = @_;
        push @COMMANDS, $command;
        $::RUNCMD_RC = 0;
        return [];
    };
}

write_text("$fixture/compute.pkglist", "bash\n");
xCAT::Table->new('site', -create => 1)->setAttribs({ key => $_->[0] }, { value => $_->[1] })
  for ([ installdir => "$fixture/install" ], [ tftpdir => "$fixture/tftpboot" ]);
my $osimage    = xCAT::Table->new('osimage', -create => 1);
my $linuximage = xCAT::Table->new('linuximage', -create => 1);
my $sequence   = 0;

sub image {
    my (%attrs) = @_;
    my $name = 'img-' . ++$sequence;
    my $dir  = "$fixture/install/netboot/$name";
    make_path($dir, "$fixture/tftpboot/xcat/osimage/$name");
    write_text("$dir/initrd-stateless.gz", "initial ramdisk that checks the root image\n");
    write_text("$dir/kernel", "kernel\n");
    write_text("$dir/rootimg.cpio.gz", "root image packed before the check\n");
    write_text("$fixture/tftpboot/xcat/osimage/$name/initrd-stateless.gz", "initial ramdisk that nodes boot now\n");
    $osimage->setAttribs({ imagename => $name }, { osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' });
    $linuximage->setAttribs({ imagename => $name }, { pkglist => "$fixture/compute.pkglist", rootimgdir => $dir, %attrs });
    return ($name, $dir, "$fixture/tftpboot/xcat/osimage/$name");
}

sub content {
    my ($path) = @_;
    return -f $path ? read_binary($path) : undef;
}

sub genimage {
    my ($name) = @_;
    @COMMANDS = ();
    my @responses;
    xCAT_plugin::genimage::process_request({ command => ['genimage'], arg => [ '--onlyinitrd', '--tempfile', "$fixture/genimage.$sequence", $name ] },
        sub { push @responses, @_ }, sub { });
    return join("\n", map { @{ $_->{error} || [] } } @responses);
}

{
    my ($name, $dir, $tftp) = image();
    my $errors = genimage($name);
    is($errors, '', 'genimage reports no error');
    like($COMMANDS[0] // '', qr{genimage .*--onlyinitrd}, 'the genimage script rebuilds the initial ramdisk');
    is(content("$dir/rootimg.cpio.gz.sha256"), sha256_hex("root image packed before the check\n") . "  rootimg.cpio.gz\n",
        'the root image packed before the check gets its checksum');
    is(read_binary("$tftp/initrd-stateless.gz"), "initial ramdisk that checks the root image\n", 'the new initial ramdisk reaches TFTP');
}

{
    my ($name, $dir, $tftp) = image(rootimgchecksum => 'no');
    is(genimage($name), '', 'genimage of an image with the check turned off reports no error');
    is(content("$dir/rootimg.cpio.gz.sha256"), sha256_hex("root image packed before the check\n") . "  rootimg.cpio.gz\n",
        'the checksum is written also when the check is turned off, for nodes whose older boot entries still check');
    is(read_binary("$tftp/initrd-stateless.gz"), "initial ramdisk that checks the root image\n", 'the new initial ramdisk reaches TFTP');
}

{
    my ($name, $dir, $tftp) = image();
    mkdir("$dir/.packimage-publish") or die $!;
    write_text("$dir/.packimage-publish/owner", "other.host 4242\n");
    utime(time() - 120, time() - 120, "$dir/.packimage-publish") or die $!;
    like(genimage($name), qr/is held by other\.host 4242\..*The new initial ramdisk is not copied to \Q$tftp\E\. Run packimage \Q$name\E, then nodeset\./s,
        'a checksum that cannot be published is reported with the remedy');
    ok(!-e "$dir/rootimg.cpio.gz.sha256", 'no checksum is written while another host publishes');
    is(read_binary("$tftp/initrd-stateless.gz"), "initial ramdisk that nodes boot now\n",
        'nodes keep the initial ramdisk that boots the image without a checksum');
}

done_testing();
