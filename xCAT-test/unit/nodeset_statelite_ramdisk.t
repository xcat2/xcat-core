#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(realpath);
use Data::Dumper;
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $fixture = realpath(tempdir(CLEANUP => 1));
make_path("$fixture/db", "$fixture/root/lib/perl", "$fixture/tftpboot");
symlink(repo_path('perl-xCAT/xCAT'), "$fixture/root/lib/perl/xCAT") or die $!;
$ENV{XCATROOT} = "$fixture/root";
$ENV{XCATCFG}  = "SQLite:$fixture/db";

require xCAT::Table;
require xCAT::SvrUtils;
require xCAT::DBobjUtils;
require(repo_path('xCAT-server/lib/xcat/plugins/debian.pm'));
require(repo_path('xCAT-server/lib/xcat/plugins/sles.pm'));

xCAT::Table->new('site', -create => 1)->setAttribs({ key => $_->[0] }, { value => $_->[1] })
  for ([ installdir => "$fixture/install" ], [ tftpdir => "$fixture/tftpboot" ]);
my $sequence = 0;

# Defines a statelite image and a node that boots it, and returns the node and the image directory.
sub image {
    my (%args) = @_;
    my $name = "$args{plugin}-" . ++$sequence;
    my $node = "n$sequence";
    my $dir  = "$fixture/install/netboot/$name";
    make_path("$dir/rootimg/etc");
    write_text("$dir/rootimg/etc/dracut.conf", "\n") if $args{dracut};
    write_text("$dir/$_", "$_ of $name\n") for qw(kernel initrd-stateless.gz initrd-statelite.gz rootimg-statelite.gz);
    xCAT::SvrUtils->write_initrd_check_marker("$dir/initrd-stateless.gz");
    xCAT::Table->new('nodelist', -create => 1)->setAttribs({ node => $node }, { groups => 'compute' });
    xCAT::Table->new('noderes', -create => 1)->setAttribs({ node => $node }, { xcatmaster => '192.0.2.1' });
    xCAT::Table->new('nodetype', -create => 1)->setAttribs({ node => $node },
        { os => $args{os}, arch => 'x86_64', profile => 'compute', provmethod => $name });
    xCAT::Table->new('osimage', -create => 1)->setAttribs({ imagename => $name },
        { osvers => $args{os}, osarch => 'x86_64', profile => 'compute', provmethod => 'statelite', rootfstype => $args{rootfstype} });
    xCAT::Table->new('linuximage', -create => 1)->setAttribs({ imagename => $name }, { rootimgdir => $dir });
    return ($node, $name, $dir);
}

sub content {
    my ($path) = @_;
    return -f $path ? read_text($path) : undef;
}

# Runs nodeset for a statelite node and returns its boot parameters and the errors.
sub nodeset {
    my ($plugin, $node) = @_;
    no warnings 'once';
    local %::XCATSITEVALS = (installdir => "$fixture/install", tftpdir => "$fixture/tftpboot", httpmethod => 'http');
    my $bootparams = {};
    my @responses;
    no strict 'refs';
    &{"xCAT_plugin::${plugin}::process_request"}({ command => ['mkstatelite'], node => [$node], bootparams => \$bootparams },
        sub { push @responses, @_ }, sub { });
    local $Data::Dumper::Indent = 0;
    return ($bootparams->{$node}[0] || {}, [ grep { /error/ } map { Dumper($_) } @responses ]);
}

{
    my ($node, $name, $dir) = image(plugin => 'debian', os => 'ubuntu24.04', rootfstype => 'ramdisk', dracut => 1);
    my ($boot, $errors) = nodeset(debian => $node);
    is_deeply($errors, [], 'Ubuntu: nodeset of a statelite ramdisk node reports no error');
    like($boot->{kcmdline} // '', qr{(?:^| )imgurl=http://\S+\Q$dir\E/rootimg-statelite\.gz STATEMNT=},
        'Ubuntu: a statelite ramdisk node downloads rootimg-statelite.gz');
    unlike($boot->{kcmdline} // '', qr{root=nfs|NFSROOT=}, 'Ubuntu: a statelite ramdisk node gets no NFS root');
    like($boot->{initrd} // '', qr{/initrd-stateless\.gz$}, 'Ubuntu: a statelite ramdisk node boots the initial ramdisk that downloads the image');
    is(content("$fixture/tftpboot/xcat/osimage/$name/initrd-stateless.gz"), "initrd-stateless.gz of $name\n",
        'Ubuntu: that initial ramdisk is copied to TFTP');
}

{
    my ($node, $name, $dir) = image(plugin => 'debian', os => 'ubuntu24.04', rootfstype => 'nfs', dracut => 1);
    my ($boot, $errors) = nodeset(debian => $node);
    is_deeply($errors, [], 'Ubuntu: nodeset of a statelite NFS node reports no error');
    like($boot->{kcmdline} // '', qr{root=nfs:\S*\Q$dir\E/rootimg}, 'Ubuntu: a statelite NFS node mounts the image over NFS');
    unlike($boot->{kcmdline} // '', qr{imgurl=}, 'Ubuntu: a statelite NFS node downloads no archive');
}

for my $case ([ ramdisk => 1, 'initrd-stateless.gz' ], [ ramdisk => 0, 'initrd-statelite.gz' ], [ nfs => 1, 'initrd-statelite.gz' ]) {
    my ($rootfstype, $dracut, $initrd) = @$case;
    my $label = "SLES $rootfstype" . ($dracut ? ' with dracut' : ' without dracut');
    my ($node, $name, $dir) = image(plugin => 'sles', os => 'sle15.6', rootfstype => $rootfstype, dracut => $dracut);
    my ($boot, $errors) = nodeset(sles => $node);
    is_deeply($errors, [], "$label: nodeset reports no error");
    like($boot->{initrd} // '', qr{/\Q$initrd\E$}, "$label: the node boots $initrd");
    is(content("$fixture/tftpboot/xcat/osimage/$name/$initrd"), "$initrd of $name\n", "$label: $initrd is copied to TFTP");
}

done_testing();
