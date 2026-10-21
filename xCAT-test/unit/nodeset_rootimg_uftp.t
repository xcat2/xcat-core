#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(realpath);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $fixture = realpath(tempdir(CLEANUP => 1));
make_path("$fixture/db", "$fixture/root/lib/perl", "$fixture/tftpboot", "$fixture/etc");
symlink(repo_path('perl-xCAT/xCAT'), "$fixture/root/lib/perl/xCAT") or die $!;
$ENV{XCATROOT} = "$fixture/root";
$ENV{XCATCFG}  = "SQLite:$fixture/db";

require xCAT::Table;
require xCAT::SvrUtils;
require xCAT::UFTP;
require xCAT::DBobjUtils;
require(repo_path('xCAT-server/lib/xcat/plugins/anaconda.pm'));
require(repo_path('xCAT-server/lib/xcat/plugins/sles.pm'));
require(repo_path('xCAT-server/lib/xcat/plugins/debian.pm'));

my $fp = '31:94:09:9D:B1:24:3F:32:C0:B9:1A:BB:AC:F4:74:2B:80:F9:77:B2';
my $uftp = qr/(?:^| )xcat\.uftp=2045 xcat\.uftpfp=\Q$fp\E /;
write_text("$fixture/etc/server.fingerprint", "$fp\n");
write_text("$fixture/etc/listener.conf", "listen_address = 192.0.2.1\nlisten_port = 2045\n"
      . "image_roots = $fixture/install/netboot\nfingerprint_file = $fixture/etc/server.fingerprint\n");
{
    no warnings 'once';
    $xCAT::UFTP::CONFIG_FILE = "$fixture/etc/listener.conf";
}

my %plugin = (anaconda => 'rhels9.6', sles => 'sle15.6', debian => 'ubuntu24.04');
my %dir;
my %tables = (
    site     => [ [ { key => 'installdir' }, { value => "$fixture/install" } ], [ { key => 'tftpdir' }, { value => "$fixture/tftpboot" } ] ],
    nodelist => [ map { [ { node => $_ }, { groups => 'compute' } ] } qw(n1 n2 n3) ],
    noderes  => [ map { [ { node => $_ }, { xcatmaster => '192.0.2.1' } ] } qw(n1 n2 n3) ],
);
for my $name (keys %tables) {
    my $table = xCAT::Table->new($name, -create => 1) or die "cannot open $name";
    $table->setAttribs(@$_) for @{ $tables{$name} };
}
my $nodetype   = xCAT::Table->new('nodetype',   -create => 1);
my $osimage    = xCAT::Table->new('osimage',    -create => 1);
my $linuximage = xCAT::Table->new('linuximage', -create => 1);
for my $name (sort keys %plugin) {
    $dir{$name} = "$fixture/install/netboot/$name";
    make_path($dir{$name});
    write_text("$dir{$name}/$_", "$_ of $name\n") for qw(kernel initrd-stateless.gz rootimg.cpio.gz);
    $osimage->setAttribs({ imagename => $name }, { osvers => $plugin{$name}, osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' });
    $linuximage->setAttribs({ imagename => $name }, { rootimgdir => $dir{$name} });
}

# The anaconda plugin also sets up a statelite node whose ramdisk root image is downloaded.
$dir{ramdisk} = "$fixture/install/netboot/ramdisk";
make_path($dir{ramdisk});
write_text("$dir{ramdisk}/$_", "$_ of ramdisk\n") for qw(kernel initrd-stateless.gz initrd-statelite.gz rootimg-statelite.gz);
$osimage->setAttribs({ imagename => 'ramdisk' },
    { osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'statelite', rootfstype => 'ramdisk' });
$linuximage->setAttribs({ imagename => 'ramdisk' }, { rootimgdir => $dir{ramdisk} });

# genimage built every initial ramdisk with the UFTP receiver and the root image check.
sub mark {
    my ($name) = @_;
    is(xCAT::UFTP::write_initrd_marker("$dir{$name}/initrd-stateless.gz"), undef, "genimage marks the initial ramdisk of $name");
    is(xCAT::SvrUtils->write_initrd_check_marker("$dir{$name}/initrd-stateless.gz"), undef, "genimage marks the check of $name");
}
mark($_) for (sort keys %plugin), 'ramdisk';

# Runs nodeset for n1 and n2 with the image of $name, and n3 with the statelite ramdisk image for anaconda.
# Returns the kernel command lines and the errors.
sub nodeset {
    my ($name, %opt) = @_;
    $nodetype->setAttribs({ node => $_ }, { os => $plugin{$name}, arch => 'x86_64', profile => 'compute', provmethod => $name }) for qw(n1 n2);
    $nodetype->setAttribs({ node => 'n3' }, { os => 'rhels9.6', arch => 'x86_64', profile => 'compute', provmethod => 'ramdisk' });
    no warnings 'once';
    local %::XCATSITEVALS = (installdir => "$fixture/install", tftpdir => "$fixture/tftpboot", httpmethod => 'http', %{ $opt{site} || {} });
    my $bootparams = { map { ($_ => [ { addkcmdline => $opt{node_addkcmdline}{$_} } ]) } keys %{ $opt{node_addkcmdline} || {} } };
    my @responses;
    my @requests = ([ mknetboot => qw(n1 n2) ]);
    push @requests, [ mkstatelite => 'n3' ] if $name eq 'anaconda';
    for my $request (@requests) {
        my ($command, @nodes) = @$request;
        no strict 'refs';
        &{"xCAT_plugin::${name}::process_request"}(
            { command => [$command], node => \@nodes, bootparams => \$bootparams, noupdateinitrd => $opt{noupdateinitrd} },
            sub { push @responses, @_ }, sub { });
    }
    my %kcmdline = map { $_ => $bootparams->{$_}[0]{kcmdline} } grep { $bootparams->{$_}[0]{kcmdline} } keys %$bootparams;
    my @errors = map { (@{ $_->{error} || [] }, map { @{ $_->{error} || [] } } @{ $_->{node} || [] }) } @responses;
    return (\%kcmdline, join("\n", @errors));
}

for my $name (sort keys %plugin) {
    my ($kcmdline, $errors) = nodeset($name);
    is($errors, '', "$name: nodeset reports no error");
    unlike($kcmdline->{n1} // '', qr/xcat\.uftp/, "$name: nodes download the root image over HTTP by default");

    $linuximage->setAttribs({ imagename => $name }, { rootimgtransport => 'uftp' });
    ($kcmdline, $errors) = nodeset($name);
    is($errors, '', "$name: an image set to uftp reports no error");
    for my $node (qw(n1 n2)) {
        like($kcmdline->{$node} // '', $uftp, "$name: $node gets the listener port and the server key fingerprint");
        like($kcmdline->{$node} // '', qr{imgurl=http://\S+/rootimg\.cpio\.gz .*rootimgchecksum=yes }, "$name: $node keeps the HTTP image URL and the check");
    }

    ($kcmdline, $errors) = nodeset($name, node_addkcmdline => { n2 => 'quiet xcat.uftpfp=AA' });
    like($kcmdline->{n1} // '', $uftp, "$name: other nodes are set up when one node sets a managed argument");
    ok(!exists($kcmdline->{n2}), "$name: a node whose bootparams.addkcmdline sets a managed argument gets no boot entry");
    like($errors, qr/bootparams\.addkcmdline must not set xcat\.uftpfp/, "$name: the managed argument of the node is reported");

    $linuximage->setAttribs({ imagename => $name }, { addkcmdline => 'console=ttyS0 xcat.uftp=1' });
    ($kcmdline, $errors) = nodeset($name);
    ok(!exists($kcmdline->{n1}) && !exists($kcmdline->{n2}), "$name: no node gets a boot entry while the image sets a managed argument");
    like($errors, qr/linuximage\.addkcmdline must not set xcat\.uftp;/, "$name: the managed argument of the image is reported");
    $linuximage->setAttribs({ imagename => $name }, { addkcmdline => '' });

    $linuximage->setAttribs({ imagename => $name }, { rootimgchecksum => 'no' });
    ($kcmdline, $errors) = nodeset($name);
    ok(!exists($kcmdline->{n1}), "$name: a node gets no boot entry when its image sends over UFTP without the check");
    like($errors, qr/UFTP needs the root image checksum/, "$name: the missing check is reported");
    $linuximage->setAttribs({ imagename => $name }, { rootimgchecksum => '' });

    # A refused node keeps its boot entry, so the kernel and initial ramdisk that it names must stay too.
    my $tftp = "$fixture/tftpboot/xcat/osimage/$name";
    my %booted = map { ($_ => read_text("$tftp/$_")) } qw(kernel initrd-stateless.gz);
    write_text("$dir{$name}/kernel", "kernel of $name rebuilt\n");
    write_text("$dir{$name}/initrd-stateless.gz", "initial ramdisk of $name rebuilt without the receiver\n");
    xCAT::SvrUtils->write_initrd_check_marker("$dir{$name}/initrd-stateless.gz");
    ($kcmdline, $errors) = nodeset($name);
    ok(!exists($kcmdline->{n1}), "$name: a node gets no boot entry when its initial ramdisk lacks the UFTP receiver");
    like($errors, qr{\Q$dir{$name}\E/initrd-stateless\.gz is not the initial ramdisk that genimage built with the UFTP receiver},
        "$name: the initial ramdisk of the image is named");
    is(read_text("$tftp/$_"), $booted{$_}, "$name: nodes keep the $_ that they boot now") for sort keys %booted;
    mark($name);
    rename($xCAT::UFTP::CONFIG_FILE, "$xCAT::UFTP::CONFIG_FILE.off") or die $!;
    ($kcmdline, $errors) = nodeset($name);
    rename("$xCAT::UFTP::CONFIG_FILE.off", $xCAT::UFTP::CONFIG_FILE) or die $!;
    like($errors, qr/UFTP listener configuration: Cannot read/, "$name: a missing listener configuration is reported");
    is(read_text("$tftp/$_"), $booted{$_}, "$name: a missing listener configuration keeps the $_ that nodes boot") for sort keys %booted;
    ($kcmdline, $errors) = nodeset($name);
    like($kcmdline->{n1} // '', $uftp, "$name: a rebuilt initial ramdisk with the receiver is accepted");

    # The debian plugin has no --noupdateinitrd.
    if ($name ne 'debian') {
        write_text("$fixture/tftpboot/xcat/osimage/$name/initrd-stateless.gz", "initial ramdisk that nodes boot now\n");
        ($kcmdline, $errors) = nodeset($name, noupdateinitrd => 1);
        like($errors, qr/is not the initial ramdisk that genimage built with the UFTP receiver/,
            "$name: with --noupdateinitrd, the initial ramdisk that nodes boot decides");
    }

    $linuximage->setAttribs({ imagename => $name }, { rootimgtransport => 'tftp' });
    ($kcmdline, $errors) = nodeset($name);
    ok(!exists($kcmdline->{n1}), "$name: a node gets no boot entry when its image has an unknown transport");
    like($errors, qr/The rootimgtransport attribute of the image is 'tftp', but only http and uftp are supported/,
        "$name: the unknown transport is reported");

    $linuximage->setAttribs({ imagename => $name }, { rootimgtransport => '' });
    ($kcmdline, $errors) = nodeset($name, site => { rootimgtransport => 'uftp' });
    like($kcmdline->{n1} // '', $uftp, "$name: site.rootimgtransport sets the transport of an image that does not set it");
    $linuximage->setAttribs({ imagename => $name }, { rootimgtransport => 'http' });
    ($kcmdline, $errors) = nodeset($name, site => { rootimgtransport => 'uftp' });
    unlike($kcmdline->{n1} // '', qr/xcat\.uftp/, "$name: an image set to http overrides site.rootimgtransport");
    $linuximage->setAttribs({ imagename => $name }, { rootimgtransport => '' });
}

{
    my ($kcmdline, $errors) = nodeset('anaconda', site => { rootimgtransport => 'uftp' });
    is($errors, '', 'site.rootimgtransport=uftp reports no error for a statelite image');
    like($kcmdline->{n3} // '', qr{imgurl=http://\S+/rootimg-statelite\.gz }, 'the statelite ramdisk node downloads its archive');
    unlike($kcmdline->{n3} // '', qr/xcat\.uftp/, 'the statelite ramdisk node does not use UFTP');
}

for my $name (qw(anaconda sles)) {
    $linuximage->setAttribs({ imagename => $name }, { rootimgtransport => 'uftp' });
    my ($kcmdline, $errors) = nodeset($name, site => { httpmethod => 'https' });
    ok(!exists($kcmdline->{n1}), "$name: a node gets no boot entry when its image URL uses https");
    like($errors, qr/requires site\.httpmethod=http, not https/, "$name: the https image URL is reported");
    $linuximage->setAttribs({ imagename => $name }, { rootimgtransport => '' });
}

done_testing();
