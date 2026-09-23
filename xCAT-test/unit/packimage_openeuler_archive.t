#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(getcwd);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

plan skip_all => 'requires Linux cpio, gzip and tar'
  unless $^O eq 'linux' && -x '/usr/bin/cpio' && -x '/usr/bin/gzip' && -x '/usr/bin/tar';
local $ENV{PATH} = "$ENV{PATH}:/usr/sbin:/sbin";
my $dir = tempdir(CLEANUP => 1);
make_path("$dir/db", "$dir/root/lib/perl", "$dir/root/share", "$dir/install/postscripts");
symlink(repo_path('perl-xCAT/xCAT'), "$dir/root/lib/perl/xCAT") or die $!;
symlink(repo_path('xCAT-server/share/xcat'), "$dir/root/share/xcat") or die $!;
write_text("$dir/install/postscripts/xcatdsklspost", "#!/bin/sh\nexit 0\n");
$ENV{XCATROOT} = "$dir/root";
$ENV{XCATCFG} = "SQLite:$dir/db";
require xCAT::Table;
require(repo_path('xCAT-server/lib/xcat/plugins/packimage.pm'));
my $site = xCAT::Table->new('site', -create => 1);
$site->setAttribs({ key => 'installdir' }, { value => "$dir/install" });
$site->setAttribs({ key => 'secureroot' }, { value => '1' });
my $passwd = xCAT::Table->new('passwd', -create => 1);
$passwd->setAttribs({ key => 'system', username => 'root' }, { password => '*', cryptmethod => 'sha512' });
my $images = xCAT::Table->new('osimage', -create => 1);
my $linux = xCAT::Table->new('linuximage', -create => 1);
my $sequence = 0;
my ($unsquashfs) = grep { -x $_ } qw(/usr/bin/unsquashfs /usr/sbin/unsquashfs /sbin/unsquashfs);

for my $case (
    ['cpio', 'cpio'], ['cpio', 'gzip'], ['cpio', 'find'],
    ['tar', 'tar'], ['tar', 'gzip'], ['tar', 'find'],
    ['cpio', ''], ['tar', ''],
    ['cpio', 'xz', 'xz'], ['tar', 'pigz', 'pigz'],
    ['cpio', '', 'xz'], ['tar', '', 'xz'],
    ['cpio', '', 'pigz'], ['tar', '', 'pigz'],
    ['squashfs', 'find'], ['squashfs', 'cpio'], ['squashfs', 'mksquashfs'],
    ['squashfs', ''],
) {
    my ($method, $failure, $compress) = @$case;
    $compress //= 'gzip';
    SKIP: {
    skip "requires $compress", 1 unless -x "/usr/bin/$compress";
    skip 'requires squashfs-tools', 1 if $method eq 'squashfs'
      && (!$unsquashfs || (!-x '/usr/bin/mksquashfs' && !-x '/sbin/mksquashfs'));
    my $name = 'archive-' . ++$sequence;
    my $dest = "$dir/$name";
    make_path("$dest/rootimg/etc/rc.d/init.d", "$dest/rootimg/opt/xcat", "$dest/bin");
    symlink('rc.d/init.d', "$dest/rootimg/etc/init.d") or die $!;
    write_text("$dest/rootimg/etc/shadow", "root:*:1:0:99999:7:::\n");
    write_text("$dest/rootimg/etc/rc.d/init.d/statelite", "legacy StateLite script\n");
    write_text("$dest/rootimg/etc/rc.d/init.d/localdisk", "legacy StateLite storage script\n");
    write_text("$dest/rootimg/native-marker", "native image contents\n");
    my $suffix = $method eq 'squashfs' ? 'sfs' : "$method." . ($compress eq 'xz' ? 'xz' : 'gz');
    my $archive = "$dest/rootimg.$suffix";
    write_text($archive, "retained archive\n");
    write_text("$dest/rootimg.previous", "retained alternative\n");
    $images->setAttribs({ imagename => $name }, {
        osvers => 'openeuler24.03sp3', osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' });
    $linux->setAttribs({ imagename => $name }, { rootimgdir => $dest });
    if ($failure) {
        write_text("$dest/bin/$failure", "#!/bin/sh\nprintf 'injected archive failure\\n' >&2\nexit 29\n");
        chmod 0755, "$dest/bin/$failure";
    }
    my $cwd = getcwd();
    my $mask = umask();
    my @staging = glob("/tmp/packimage.$$.????????");
    local $ENV{PATH} = "$dest/bin:$ENV{PATH}";
    no warnings 'redefine';
    local *xCAT::Utils::acquire_lock_imageop = sub { return (0, undef); };
    my @responses;
    my $result = xCAT_plugin::packimage::process_request(
        { arg => ['--nosyncfiles', '-m', $method, '-c', $compress, $name] },
        sub { push @responses, @_ });
    my @errors = map { @{$_->{error} // []} } @responses;
    my $label = "$method $compress " . ($failure ? "$failure failure" : 'success');
    if ($failure) {
        ok($result && @errors, "$label is reported by the production pack command");
        is(archive_content($archive), "retained archive\n", "$label preserves the selected previous archive");
        is(archive_content("$dest/rootimg.previous"), "retained alternative\n", "$label preserves other previous formats");
    } else {
        ok(!$result && !@errors, "$label completes") or diag(@errors);
        isnt(archive_content($archive), "retained archive\n", "$label publishes new archive contents");
        my @integrity = $method eq 'squashfs' ? ($unsquashfs, '-s', $archive)
          : ("/usr/bin/$compress", '-t', $archive);
        is(system(@integrity), 0, "$label produces a valid archive");
        my @listing = $method eq 'cpio'
          ? ('/bin/bash', '-o', 'pipefail', '-c', '"$1" -dc "$2" | cpio -t', 'archive-list', $compress, $archive)
          : $method eq 'squashfs' ? ($unsquashfs, '-l', $archive)
          : ('/usr/bin/tar', '-tf', $archive);
        open(my $pipe, '-|', @listing) or die "list archive: $!";
        my $contents = do { local $/; <$pipe> };
        close($pipe);
        is($?, 0, "$label produces a readable native archive");
        like($contents, qr/(?:^|\/)native-marker\n/m, "$label retains the image payload");
        unlike($contents, qr{etc/(?:rc\.d/)?init\.d/(?:statelite|localdisk)},
            "$label excludes StateLite scripts through the real init.d directory");
        ok(!-e "$dest/rootimg.previous", "$label retires stale formats only after successful publication");
        is((stat($archive))[2] & 0777, 0644, "$label publishes the expected archive mode");
    }
    is(getcwd(), $cwd, "$label restores the caller working directory");
    is(umask(), $mask, "$label restores the caller umask");
    is_deeply([glob("$dest/.packimage-*")], [], "$label leaves no partial archive");
    is_deeply([glob("/tmp/packimage.$$.????????")], \@staging, "$label removes temporary file staging");
    chdir($cwd) or die $!;
    umask($mask);
    }
}
done_testing();

sub archive_content {
    my ($path) = @_;
    return -f $path ? read_binary($path) : undef;
}
