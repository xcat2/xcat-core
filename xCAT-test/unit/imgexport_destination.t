#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(getcwd realpath);
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

# A remote export copies the bundle with scp, so the test records the command instead.
our @SCP;
BEGIN {
    *CORE::GLOBAL::system = sub {
        my @command = @_ == 1 ? split(' ', $_[0]) : @_;
        if ($command[0] eq '/usr/bin/scp') {
            push @SCP, \@command;
            return 0;
        }
        return CORE::system(@_);
    };
}

plan skip_all => 'imgexport packs bundles with tar on Linux' unless $^O eq 'linux';

my $fixture = realpath(tempdir(CLEANUP => 1));
make_path("$fixture/db", "$fixture/cwd/sub", "$fixture/out", "$fixture/with space", "$fixture/image");
$ENV{XCATCFG} = "SQLite:$fixture/db";
require xCAT::Table;
require(repo_path('xCAT-server/lib/xcat/plugins/imgport.pm'));
write_text("$fixture/image/$_", "$_\n") for qw(kernel initrd-stateless.gz rootimg.cpio.gz compute.pkglist);
xCAT::Table->new('osimage', -create => 1)->setAttribs({ imagename => 'img' },
    { osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' });
xCAT::Table->new('linuximage', -create => 1)
  ->setAttribs({ imagename => 'img' }, { rootimgdir => "$fixture/image", pkglist => "$fixture/image/compute.pkglist" });

sub export {
    my (@args) = @_;
    my $cwd = getcwd();
    my @responses;
    xCAT_plugin::imgport::process_request({ command => ['imgexport'], arg => [ 'img', @args ], cwd => ["$fixture/cwd"] },
        sub { push @responses, @_ });
    chdir($cwd) or die $!;
    return join("\n", map { @{ $_->{error} || [] } } @responses);
}

# Returns whether $path is a bundle with a manifest.
sub bundle {
    my ($path) = @_;
    return 0 if !-f $path;
    open(my $list, '-|', 'tar', '-tzf', $path) or return 0;
    my $manifest = grep { m{/manifest\.xml$}x } <$list>;
    close($list);
    return $manifest;
}

for my $case ([ 'sub/relative.tgz', "$fixture/cwd/sub/relative.tgz" ], [ "$fixture/out/absolute.tgz", "$fixture/out/absolute.tgz" ],
    [ "$fixture/out/", "$fixture/out/img.tgz" ], [ "$fixture/with space/spaced.tgz", "$fixture/with space/spaced.tgz" ],
    [ undef, "$fixture/cwd/img.tgz" ])
{
    my ($dest, $expected) = @$case;
    my $label = defined($dest) ? "destination $dest" : 'no destination';
    is(export(defined($dest) ? $dest : ()), '', "$label: imgexport reports no error");
    ok(bundle($expected), "$label: the bundle is written to $expected");
}
is_deeply([ grep { -e "$fixture/cwd/$_" } qw(relative.tgz absolute.tgz spaced.tgz) ], [],
    'no bundle goes to the current working directory instead of its destination');

like(export("$fixture/missing/bundle.tgz"), qr/Cannot export img to \Q$fixture\E\/missing\/bundle\.tgz: the directory does not exist/,
    'a destination in a missing directory is reported');
ok(!-e "$fixture/missing" && !-e "$fixture/cwd/bundle.tgz", 'no bundle is written for a destination in a missing directory');

is(export('/remote/dir/remote.tgz', '-R', 'user@remote.example'), '', 'a remote export reports no error');
is(scalar(@SCP), 1, 'a remote export copies the bundle once');
is($SCP[0][-1], 'user@remote.example:/remote/dir/remote.tgz', 'a remote export copies the bundle to its destination on the remote host');
ok(!-e $SCP[0][-2], 'a remote export removes its local bundle');

opendir(my $dir, "$fixture/cwd") or die $!;
is_deeply([ grep { /^imgexport\./x } readdir($dir) ], [], 'no temporary file or directory is left');
closedir($dir);

done_testing();
