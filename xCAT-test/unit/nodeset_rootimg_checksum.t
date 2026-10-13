#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(realpath);
use Data::Dumper;
use Errno qw(ENOSPC);
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
require(repo_path('xCAT-server/lib/xcat/plugins/anaconda.pm'));
require(repo_path('xCAT-server/lib/xcat/plugins/sles.pm'));
require(repo_path('xCAT-server/lib/xcat/plugins/debian.pm'));

my %dir;
for my $image (qw(stateless ramdisk)) {
    $dir{$image} = "$fixture/install/netboot/$image";
    make_path($dir{$image});
    write_text("$dir{$image}/kernel", "kernel\n");
    write_text("$dir{$image}/initrd-stateless.gz", "initial ramdisk of $image\n");
    write_text("$dir{$image}/initrd-statelite.gz", "statelite initial ramdisk of $image\n");
}
write_text("$dir{stateless}/rootimg.cpio.gz", "root image\n");
write_text("$dir{ramdisk}/rootimg-statelite.gz", "statelite root image\n");

my %tables = (
    site       => [ [ { key => 'installdir' }, { value => "$fixture/install" } ],
                    [ { key => 'tftpdir' },    { value => "$fixture/tftpboot" } ] ],
    nodelist   => [ map { [ { node => $_ }, { groups => 'compute' } ] } qw(n1 n2 n3) ],
    nodetype   => [ (map { [ { node => $_ }, { os => 'rhels9.6', arch => 'x86_64', profile => 'compute', provmethod => 'stateless' } ] } qw(n1 n2)),
                    [ { node => 'n3' }, { os => 'rhels9.6', arch => 'x86_64', profile => 'compute', provmethod => 'ramdisk' } ] ],
    noderes    => [ map { [ { node => $_ }, { xcatmaster => '192.0.2.1' } ] } qw(n1 n2 n3) ],
    osimage    => [ [ { imagename => 'stateless' }, { osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' } ],
                    [ { imagename => 'ramdisk' },   { osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'statelite', rootfstype => 'ramdisk' } ] ],
    linuximage => [ map { [ { imagename => $_ }, { rootimgdir => $dir{$_} } ] } qw(stateless ramdisk) ],
);
for my $name (keys %tables) {
    my $table = xCAT::Table->new($name, -create => 1) or die "cannot open $name";
    $table->setAttribs(@$_) for @{ $tables{$name} };
}
my $linuximage = xCAT::Table->new('linuximage');
our $NOUPDATEINITRD;

# Runs nodeset for every node and returns the kernel command lines and the warnings.
sub nodeset {
    my (%site) = @_;
    no warnings 'once';
    local %::XCATSITEVALS = (installdir => "$fixture/install", tftpdir => "$fixture/tftpboot", httpmethod => 'http', %site);
    my $bootparams = {};
    my @responses;
    for my $request ([ mknetboot => qw(n1 n2) ], [ mkstatelite => 'n3' ]) {
        my ($command, @nodes) = @$request;
        xCAT_plugin::anaconda::process_request(
            { command => [$command], node => \@nodes, bootparams => \$bootparams, noupdateinitrd => $NOUPDATEINITRD },
            sub { push @responses, @_ }, sub { });
    }
    my %kcmdline = map { $_ => $bootparams->{$_}[0]{kcmdline} } keys %$bootparams;
    my @warnings = map { @{ $_->{warning} || [] } } @responses;
    local $Data::Dumper::Indent = 0;
    my @errors = grep { /error/ } map { Dumper($_) } @responses;
    return (\%kcmdline, \@warnings, \@errors);
}

my ($kcmdline, $warnings, $errors) = nodeset();
is_deeply($errors, [], 'nodeset reports no error');
ok(-e "$dir{stateless}/rootimg.cpio.gz.sha256", 'nodeset writes the checksum of a stateless archive packed before the check, although no marker shows that the initial ramdisk checks it');
ok(-e "$dir{ramdisk}/rootimg-statelite.gz.sha256", 'nodeset writes the checksum of a statelite ramdisk archive packed before the check');
for my $node (qw(n1 n2 n3)) {
    ok(defined $kcmdline->{$node}, "$node gets a kernel command line");
    like($kcmdline->{$node} // '', qr/(?:^| )rootimgchecksum=yes /, "$node is asked to check by default");
}
like($kcmdline->{n3} // '', qr{imgurl=http://\S+/rootimg-statelite\.gz STATEMNT=}, 'the statelite ramdisk node downloads its archive');
is(scalar(grep { /Cannot tell whether the initial ramdisk/ } @$warnings), 2,
    'one warning for each image whose initial ramdisk has no matching marker');
like(join("\n", @$warnings), qr/Cannot tell whether the initial ramdisk \Q$fixture\E\/tftpboot\/xcat\/osimage\/stateless\/initrd-stateless\.gz checks the root image checksum, so nodes may boot the root image of stateless unchecked\. Run genimage/,
    'the warning names the initial ramdisk, the image and the remedy');

for my $image (qw(stateless ramdisk)) {
    is(xCAT::SvrUtils->write_initrd_check_marker("$dir{$image}/initrd-stateless.gz"), undef, "genimage marks the initial ramdisk of $image");
}
($kcmdline, $warnings) = nodeset();
is_deeply($warnings, [], 'no warning when the initial ramdisks can check the checksum');

{
    my $tftp = "$fixture/tftpboot/xcat/osimage/stateless/initrd-stateless.gz";
    my $before = -f $tftp ? read_text($tftp) : undef;
    unlink("$dir{stateless}/rootimg.cpio.gz.sha256") or die $!;
    write_text("$dir{stateless}/initrd-stateless.gz", "initial ramdisk that checks, rebuilt\n");
    xCAT::SvrUtils->write_initrd_check_marker("$dir{stateless}/initrd-stateless.gz");
    mkdir("$dir{stateless}/.packimage-publish") or die $!;
    write_text("$dir{stateless}/.packimage-publish/owner", "other.host 4242\n");
    utime(time() - 120, time() - 120, "$dir{stateless}/.packimage-publish") or die $!;
    my ($lines, undef, $failures) = nodeset();
    ok(!exists($lines->{n1}), 'a node gets no boot entry when its root image cannot get the checksum it needs');
    like(join(' ', @$failures), qr/root image of stateless has no checksum that its initial ramdisk can check: .*is held by other\.host 4242.*Run packimage for the image, then nodeset/,
        'the missing checksum is reported with the remedy');
    is(-f $tftp ? read_text($tftp) : undef, $before, 'nodes keep the initial ramdisk that they boot now');
    ok(exists($lines->{n3}), 'nodes of other images are set up');
    unlink("$dir{stateless}/.packimage-publish/owner");
    rmdir("$dir{stateless}/.packimage-publish") or die $!;
}
like($kcmdline->{$_} // '', qr/(?:^| )rootimgchecksum=yes /, "the check stays on for $_") for qw(n1 n2 n3);

write_text("$dir{stateless}/initrd-stateless.gz", "initial ramdisk rebuilt by an older genimage\n");
($kcmdline, $warnings) = nodeset();
is(scalar(@$warnings), 1, 'a marker that does not match the initial ramdisk does not silence the warning');
like($warnings->[0] // '', qr{\Q$fixture\E/tftpboot/xcat/osimage/stateless/initrd-stateless\.gz}, 'the warning is for the rebuilt initial ramdisk that nodes boot');

unlink("$dir{stateless}/rootimg.cpio.gz.sha256");
($kcmdline, $warnings) = nodeset(rootimgchecksum => 'no');
unlike($kcmdline->{$_}, qr/rootimgchecksum=/, "site.rootimgchecksum=no turns the check off for $_") for qw(n1 n2 n3);
ok(-e "$dir{stateless}/rootimg.cpio.gz.sha256", 'nodeset writes a missing checksum also when the check is turned off');
{
    no warnings 'redefine';
    local *xCAT::SvrUtils::publish_missing_rootimg_checksums = sub { return 'the publication lock is held' };
    my ($lines, $warned, $failures) = nodeset(rootimgchecksum => 'no');
    is_deeply($failures, [], 'a checksum that cannot be written does not refuse nodes that skip the check');
    ok(defined($lines->{$_}) && $lines->{$_} !~ /rootimgchecksum=/, "$_ is still set up, without the check") for qw(n1 n2 n3);
    like(join("\n", @$warned), qr/the publication lock is held\. Nodes of stateless whose boot entries still ask for the check download the root image again until nodeset runs for them/,
        'the nodes that still check are reported');
}
like($kcmdline->{n3}, qr/(?:^| )imgurl=\S+ STATEMNT=/, 'the statelite ramdisk node keeps STATEMNT after its image URL');
is_deeply($warnings, [], 'no warning when the check is turned off');

$linuximage->setAttribs({ imagename => 'stateless' }, { rootimgchecksum => 'yes' });
($kcmdline, $warnings) = nodeset(rootimgchecksum => 'no');
like($kcmdline->{n1}, qr/(?:^| )rootimgchecksum=yes /, 'the image turns the check on although the site turns it off');
unlike($kcmdline->{n3}, qr/rootimgchecksum=/, 'the other image follows the site');

$linuximage->setAttribs({ imagename => 'stateless' }, { rootimgchecksum => '0' });
($kcmdline, $warnings) = nodeset();
unlike($kcmdline->{n1}, qr/rootimgchecksum=/, 'the image turns the check off although the site keeps it on');
like($kcmdline->{n3}, qr/(?:^| )rootimgchecksum=yes /, 'the other image keeps the check on');
is_deeply($warnings, [], 'an image with the check turned off gets no warning');

{
    local $NOUPDATEINITRD = 1;
    my $tftp = "$fixture/tftpboot/xcat/osimage/stateless/initrd-stateless.gz";
    $linuximage->setAttribs({ imagename => 'stateless' }, { rootimgchecksum => '' });
    write_text("$dir{stateless}/initrd-stateless.gz", "initial ramdisk that checks\n");
    xCAT::SvrUtils->write_initrd_check_marker("$dir{stateless}/initrd-stateless.gz");
    write_text($tftp, "initial ramdisk that nodes boot now, built before the check\n");
    ($kcmdline, $warnings) = nodeset();
    is(scalar(@$warnings), 1, 'with --noupdateinitrd, the initial ramdisk that nodes boot decides the warning');
    like($warnings->[0] // '', qr/initial ramdisk \Q$tftp\E checks the root image checksum/, 'the warning names the initial ramdisk in TFTP');
    is(read_text($tftp), "initial ramdisk that nodes boot now, built before the check\n", 'nodeset keeps that initial ramdisk');
    write_text($tftp, "initial ramdisk that checks\n");
    ($kcmdline, $warnings) = nodeset();
    is_deeply($warnings, [], 'a copy that matches the marker of the image checks the checksum');
}

# The checksum step of the first node fails, as while another host holds the publication lock.
sub fail_first_checksum_step {
    my $calls = 0;
    return sub { return $calls++ ? undef : 'the publication lock is held' };
}

{
    my $tftp = "$fixture/tftpboot/xcat/osimage/stateless/initrd-stateless.gz";
    write_text("$dir{stateless}/initrd-stateless.gz", "initial ramdisk for the copy test\n");
    xCAT::SvrUtils->write_initrd_check_marker("$dir{stateless}/initrd-stateless.gz");
    write_text($tftp, "initial ramdisk that nodes boot now\n");
    no warnings 'redefine';
    local *xCAT::SvrUtils::publish_missing_rootimg_checksums = fail_first_checksum_step();
    my ($lines) = nodeset();
    is(scalar(grep { exists($lines->{$_}) } qw(n1 n2)), 1, 'the next node of an image is set up after the first fails the checksum step');
    is(read_text($tftp), "initial ramdisk for the copy test\n", 'the next node copies the boot files that the first node did not');
}

{
    my $tftp = "$fixture/tftpboot/xcat/osimage/stateless/initrd-stateless.gz";
    write_text("$dir{stateless}/initrd-stateless.gz", "initial ramdisk that cannot be copied\n");
    xCAT::SvrUtils->write_initrd_check_marker("$dir{stateless}/initrd-stateless.gz");
    my $before = read_text($tftp);
    no warnings 'redefine';
    local *xCAT_plugin::anaconda::copy = sub { $! = ENOSPC; return 0 };
    my ($lines, undef, $failures) = nodeset();
    ok(!exists($lines->{n1}) && !exists($lines->{n2}), 'nodes get no boot entry when their boot files cannot be copied');
    like(join(' ', @$failures), qr/Copying to \S+ failed: /, 'the failed copy is reported');
    is(read_text($tftp), $before, 'the boot files in TFTP stay as they were');
}

# SUSE and Ubuntu nodeset build the stateless command line in their own plugins.
our @RUN_NODES = ('n4');
for my $case ([ sles => 'sle15.6' ], [ debian => 'ubuntu24.04' ]) {
    my ($plugin, $os) = @$case;
    my $dir = "$fixture/install/netboot/$plugin";
    make_path($dir);
    write_text("$dir/$_", "$_ of $plugin\n") for qw(kernel initrd-stateless.gz rootimg.cpio.gz);
    for my $node (qw(n4 n5)) {
        xCAT::Table->new('nodetype')->setAttribs({ node => $node }, { os => $os, arch => 'x86_64', profile => 'compute', provmethod => $plugin });
        xCAT::Table->new('noderes')->setAttribs({ node => $node }, { xcatmaster => '192.0.2.1' });
        xCAT::Table->new('nodelist')->setAttribs({ node => $node }, { groups => 'compute' });
    }
    xCAT::Table->new('osimage')->setAttribs({ imagename => $plugin }, { osvers => $os, osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' });
    $linuximage->setAttribs({ imagename => $plugin }, { rootimgdir => $dir });
    my $run = sub {
        my (%site) = @_;
        no warnings 'once';
        local %::XCATSITEVALS = (installdir => "$fixture/install", tftpdir => "$fixture/tftpboot", httpmethod => 'http', %site);
        my $bootparams = {};
        my @responses;
        no strict 'refs';
        &{"xCAT_plugin::${plugin}::process_request"}({ command => ['mknetboot'], node => [@RUN_NODES], bootparams => \$bootparams },
            sub { push @responses, @_ }, sub { });
        return ($bootparams->{n4}[0]{kcmdline}, [ map { @{ $_->{warning} || [] } } @responses ], $bootparams);
    };
    my ($line, $warned) = $run->();
    like($line // '', qr{imgurl=http://\S+/rootimg\.cpio\.gz }, "$plugin: the node downloads the root image");
    like($line // '', qr/(?:^| )rootimgchecksum=yes /, "$plugin: the node is asked to check by default");
    is(scalar(grep { /Cannot tell whether the initial ramdisk/ } @$warned), 1, "$plugin: an unmarked initial ramdisk is reported");
    xCAT::SvrUtils->write_initrd_check_marker("$dir/initrd-stateless.gz");
    ($line, $warned) = $run->();
    is(scalar(grep { /root image checksum/ } @$warned), 0, "$plugin: a marked initial ramdisk is not reported");
    ($line, $warned) = $run->(rootimgchecksum => 'no');
    unlike($line // '', qr/rootimgchecksum=/, "$plugin: site.rootimgchecksum=no turns the check off");
    {
        my $tftp = "$fixture/tftpboot/xcat/osimage/$plugin/initrd-stateless.gz";
        write_text("$dir/initrd-stateless.gz", "initial ramdisk of $plugin for the copy test\n");
        xCAT::SvrUtils->write_initrd_check_marker("$dir/initrd-stateless.gz");
        write_text($tftp, "initial ramdisk that nodes boot now\n");
        no warnings 'redefine';
        local *xCAT::SvrUtils::publish_missing_rootimg_checksums = fail_first_checksum_step();
        local @RUN_NODES = qw(n4 n5);
        my (undef, undef, $boot) = $run->();
        is(scalar(grep { $boot->{$_}[0]{kcmdline} } qw(n4 n5)), 1, "$plugin: the next node of an image is set up after the first fails the checksum step");
        is(read_text($tftp), "initial ramdisk of $plugin for the copy test\n", "$plugin: the next node copies the boot files");
    }
}

done_testing();
