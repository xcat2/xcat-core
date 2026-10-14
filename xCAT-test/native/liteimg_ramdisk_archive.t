#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(getcwd realpath);
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_text);
use File::Temp qw(tempdir);
use Sys::Hostname qw(hostname);
use Test::More;
use XCAT::Test::File qw(repo_path);

plan skip_all => 'liteimg packs real archives with Linux tools' unless $^O eq 'linux';
local $ENV{PATH} = "$ENV{PATH}:/usr/sbin:/sbin";

sub tool {
    my ($name) = @_;
    my ($path) = grep { -x $_ } map { "$_/$name" } split /:/, $ENV{PATH};
    return $path;
}
for my $name (qw(cpio gzip find)) {
    die "The liteimg archive test requires $name\n" unless tool($name);
}

my $fixture = realpath(tempdir(CLEANUP => 1));
make_path("$fixture/db", "$fixture/root/lib/perl", "$fixture/root/share", "$fixture/install/postscripts");
symlink(repo_path('perl-xCAT/xCAT'), "$fixture/root/lib/perl/xCAT") or die $!;
symlink(repo_path('xCAT-server/share/xcat'), "$fixture/root/share/xcat") or die $!;
write_text("$fixture/install/postscripts/xcatdsklspost", "#!/bin/sh\nexit 0\n");
local $ENV{XCATROOT} = "$fixture/root";
local $ENV{XCATCFG}  = "SQLite:$fixture/db";
require xCAT::Table;
require(repo_path('xCAT-server/lib/xcat/plugins/statelite.pm'));
xCAT::Table->new('site', -create => 1)->setAttribs({ key => 'installdir' }, { value => "$fixture/install" });
xCAT::Table->new('passwd', -create => 1)
  ->setAttribs({ key => 'system', username => 'root' }, { password => '*', cryptmethod => 'sha512' });
my $osimage    = xCAT::Table->new('osimage', -create => 1);
my $linuximage = xCAT::Table->new('linuximage', -create => 1);

# The image lock lives in /var/lock/xcat, so the test records the request and decides whether another operation holds it.
our ($HELD, @LOCKED);
{
    no warnings qw(redefine once);
    *xCAT::Utils::acquire_lock_imageop = sub {
        my (undef, $dir) = @_;
        push @LOCKED, $dir;
        return $HELD ? (1, "failed to acquire lock, seems there is another genimage/packimage/rmimage process 4242 running on root image dir \"$dir\"") : (0, {});
    };
}

(my $host = hostname()) =~ s/[^A-Za-z0-9.-]/_/g;
my $sequence = 0;

# The wrapper records what nodes would download while liteimg packs, then runs or fails the real compressor.
sub image {
    my ($mode) = @_;
    my $name = 'lite-' . ++$sequence;
    my $dest = "$fixture/images/$name";
    my $root = "$dest/rootimg";
    my $archive = "$dest/rootimg-statelite.gz";
    make_path("$root/etc/init.d", "$root/opt/xcat", "$root/usr/bin", "$dest/bin", "$dest/.packimage-$host+INTERRUP");
    write_text("$root/etc/shadow", "root:*:1:0:99999:7:::\n");
    write_text("$root/etc/fstab", "compute_x86_64 / tmpfs rw 0 1\n");
    write_text("$root/etc/hosts", "127.0.0.1 localhost\n");
    write_text("$root/usr/bin/payload", "payload of $name\n");
    write_text($archive, "previous archive\n");
    write_text("$archive.sha256", "previous checksum\n");
    write_text("$dest/rootimg.cpio.gz", "stateless archive\n");
    for my $compressor (qw(gzip pigz)) {
        my $real = tool('gzip');
        my $run = $mode eq 'fail' ? "printf 'injected failure\\n' >&2; exit 29" : "exec '$real' \"\$\@\"";
        write_text("$dest/bin/$compressor", <<"SCRIPT");
#!/bin/sh
cat '$archive' > '$dest/seen'
$run
SCRIPT
        chmod 0755, "$dest/bin/$compressor";
    }
    # ilitefile asks xcatd for the litefile entries of the image.
    write_text("$dest/bin/ilitefile", "#!/bin/sh\necho '$name tmpfs /etc/hosts'\n");
    chmod 0755, "$dest/bin/ilitefile";
    $osimage->setAttribs({ imagename => $name },
        { osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'statelite', rootfstype => 'ramdisk' });
    $linuximage->setAttribs({ imagename => $name }, { rootimgdir => $dest });
    return ($name, $dest, $archive);
}

sub liteimg {
    my ($dest, $name, @args) = @_;
    my ($cwd, $mask) = (getcwd(), umask());
    @LOCKED = ();
    my @responses;
    my $output = '';
    open(my $stdout, '>', \$output) or die $!;
    {
        local $ENV{PATH} = "$dest/bin:$ENV{PATH}";
        local *STDOUT = $stdout;
        eval { xCAT_plugin::statelite::process_request({ arg => [ @args, $name ] }, sub { push @responses, @_ }) };
        push @responses, { error => ["liteimg died: $@"] } if $@;
    }
    chdir($cwd) or die $!;
    umask($mask);
    return join("\n", map { @{ $_->{error} || [] } } @responses);
}

sub listing {
    my ($archive) = @_;
    open(my $pipe, '-|', '/bin/sh', '-c', 'gzip -dc "$1" | cpio -t 2>/dev/null', 'list', $archive) or die $!;
    my $text = do { local $/; <$pipe> };
    close($pipe);
    return $text;
}

{
    my ($name, $dest, $archive) = image('pass');
    my $errors = liteimg($dest, $name);
    is($errors, '', 'liteimg reports no error');
    is_deeply(\@LOCKED, ["$dest/rootimg"], 'liteimg holds the image lock that packimage takes');
    is(read_binary("$dest/seen"), "previous archive\n", 'nodes get the previous archive while liteimg packs');
    like(listing($archive), qr{(?:^|/)usr/bin/payload$}m, 'the new archive holds the image');
    is((stat($archive))[2] & 07777, 0644, 'the new archive is readable by nodes');
    is(read_binary("$archive.sha256"), sha256_hex(read_binary($archive)) . "  rootimg-statelite.gz\n",
        'the checksum of the new archive is published next to it');
    is(read_binary("$dest/rootimg.cpio.gz"), "stateless archive\n", 'the stateless archive of the image stays');
    is_deeply([ glob("$dest/.packimage-$host+*") ], [], 'no temporary directory is left, including an abandoned one');
    ok(!-e "$dest/.packimage-publish", 'the publication lock is released');
}

{
    my ($name, $dest, $archive) = image('fail');
    my $errors = liteimg($dest, $name);
    like($errors, qr/liteimg failed while running: .*(?:pigz|gzip)/, 'a failed compressor is reported');
    is(read_binary($archive), "previous archive\n", 'a failed pack keeps the previous archive');
    is(read_binary("$archive.sha256"), "previous checksum\n", 'a failed pack keeps the previous checksum');
    is_deeply([ glob("$dest/.packimage-$host+*") ], [], 'a failed pack leaves no partial archive');
}

{
    my ($name, $dest, $archive) = image('pass');
    $linuximage->setAttribs({ imagename => $name }, { rootimgchecksum => 'no' });
    my $errors = liteimg($dest, $name);
    is($errors, '', 'liteimg with the check turned off reports no error');
    like(listing($archive), qr{(?:^|/)usr/bin/payload$}m, 'the new archive is published');
    is(read_binary("$archive.sha256"), sha256_hex(read_binary($archive)) . "  rootimg-statelite.gz\n",
        'the checksum is published also when the check is turned off');
}

{
    local $HELD = 1;
    my ($name, $dest, $archive) = image('pass');
    my $errors = liteimg($dest, $name);
    like($errors, qr/failed to acquire lock/, 'liteimg fails while another image operation holds the lock');
    is(read_binary($archive), "previous archive\n", 'the published archive stays while the lock is held');
    ok(!-e "$dest/rootimg/xcatpost", 'liteimg does not change the image while the lock is held');
}

{
    my ($name, $dest, $archive) = image('pass');
    write_text("$dest/bin/ctorrent", <<"SCRIPT");
#!/bin/sh
echo "\$*" > '$dest/ctorrent.args'
while [ \$# -gt 1 ]; do [ "\$1" = -s ] && out=\$2; shift; done
{ echo "\$1 \$(stat -c %s "\$1")"; cat '$archive'; } > "\$out"
SCRIPT
    chmod 0755, "$dest/bin/ctorrent";
    my $errors = liteimg($dest, $name, '--tracker', 'http://192.0.2.1:6969/announce');
    is($errors, '', 'liteimg with --tracker reports no error');
    like(read_binary("$dest/ctorrent.args"), qr{(?:^| )-u http://192\.0\.2\.1:6969/announce }, 'the metainfo names the tracker URL that --tracker gives');
    is(read_binary("$archive.metainfo"), 'rootimg-statelite.gz ' . (-s $archive) . "\nprevious archive\n",
        'the metainfo describes the new archive under its final name before the archive is replaced');
}

done_testing();
