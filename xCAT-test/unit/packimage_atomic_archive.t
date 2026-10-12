#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(getcwd realpath);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_text);
use File::Temp qw(tempdir);
use POSIX ();
use Sys::Hostname qw(hostname);
use Test::More;
use XCAT::Test::File qw(repo_path);

plan skip_all => 'packimage packs real archives with Linux tools' unless $^O eq 'linux';
local $ENV{PATH} = "$ENV{PATH}:/usr/sbin:/sbin";

sub tool {
    my ($name) = @_;
    my ($path) = grep { -x $_ } map { "$_/$name" } split /:/, $ENV{PATH};
    return $path;
}
for my $name (qw(cpio gzip tar find)) {
    plan skip_all => "$name is required" unless tool($name);
}

my $fixture = realpath(tempdir(CLEANUP => 1));
make_path("$fixture/db", "$fixture/root/lib/perl", "$fixture/root/share", "$fixture/install/postscripts");
symlink(repo_path('perl-xCAT/xCAT'), "$fixture/root/lib/perl/xCAT") or die $!;
symlink(repo_path('xCAT-server/share/xcat'), "$fixture/root/share/xcat") or die $!;
write_text("$fixture/install/postscripts/xcatdsklspost", "#!/bin/sh\nexit 0\n");
$ENV{XCATROOT} = "$fixture/root";
$ENV{XCATCFG}  = "SQLite:$fixture/db";
require xCAT::Table;
require(repo_path('xCAT-server/lib/xcat/plugins/packimage.pm'));
xCAT::Table->new('site', -create => 1)->setAttribs({ key => 'installdir' }, { value => "$fixture/install" });
xCAT::Table->new('passwd', -create => 1)
  ->setAttribs({ key => 'system', username => 'root' }, { password => '*', cryptmethod => 'sha512' });
my $osimage    = xCAT::Table->new('osimage', -create => 1);
my $linuximage = xCAT::Table->new('linuximage', -create => 1);
{
    no warnings qw(redefine once);
    *xCAT::Utils::acquire_lock_imageop = sub { return (0, undef); };
    *xCAT::Utils::runcmd = sub {
        my ($class, $command) = @_;
        if ($command =~ /^ilitefile /) {
            $::RUNCMD_RC = 0;
            return ([@main::LITEFILES]);
        }
        my @output = `$command 2>&1`;
        $::RUNCMD_RC = $? >> 8;
        return (\@output);
    };
}

our @LITEFILES;
(my $host = hostname()) =~ s/[^A-Za-z0-9.-]/_/g;
my ($unsquashfs, $mksquashfs) = (tool('unsquashfs'), tool('mksquashfs'));
my $sequence = 0;

# The wrapper records what nodes would download while the pack runs, then runs or fails the real tool.
sub image {
    my ($method, $compress, $wrapped, $mode) = @_;
    my $name = 'atomic-' . ++$sequence;
    my $dest = "$fixture/images/$name";
    my $root = "$dest/rootimg";
    make_path("$root/etc", "$root/opt/xcat", "$root/usr/bin", "$root/usr/lib/dracut/modules.d/97xcat", "$dest/bin");
    write_text("$root/etc/shadow", "root:*:1:0:99999:7:::\n");
    write_text("$root/usr/bin/payload", "payload of $name\n");
    my $suffix = $method eq 'squashfs' ? 'sfs' : "$method." . ($compress eq 'xz' ? 'xz' : 'gz');
    my $archive = "$dest/rootimg.$suffix";
    write_text($archive, "previous archive\n");
    write_text("$archive.metainfo", "previous metainfo\n");
    write_text("$dest/rootimg.previous", "previous format\n");
    write_text("$dest/.packimage-$host+INTERRUP", "partial archive of an interrupted pack on this host\n");
    make_path("$dest/.packimage-$host+INTERDIR");
    write_text("$dest/.packimage-$host+INTERDIR/rootimg.$suffix", "partial archive of an interrupted pack on this host\n");
    write_text("$dest/.packimage-other.host+ACTIVE00", "archive that another host is writing\n");
    write_text("$dest/.packimage-$host-backup+ACTIVE00", "archive that a host with a longer name is writing\n");
    my $real = tool($wrapped);
    my $fail = "printf 'injected $wrapped failure\\n' >&2; exit 29";
    my $run = $mode eq 'fail' ? $fail
      : $mode eq 'fail-listing' ? "if [ \"\$1\" = . ] && [ \"\$2\" = -xdev ]; then $fail; fi\nexec '$real' \"\$\@\""
      : $mode eq 'fail-restore' ? "case \"\$1\" in */.statebackup/*) $fail;; esac\nexec '$real' \"\$\@\""
      : "exec '$real' \"\$\@\"";
    write_text("$dest/bin/$wrapped", <<"SCRIPT");
#!/bin/sh
if [ -f '$archive' ]; then cat '$archive' > '$dest/seen'; else echo missing > '$dest/seen'; fi
$run
SCRIPT
    chmod 0755, "$dest/bin/$wrapped";
    $osimage->setAttribs({ imagename => $name },
        { osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' });
    $linuximage->setAttribs({ imagename => $name }, { rootimgdir => $dest });
    return ($name, $dest, $archive);
}

sub packimage {
    my ($dest, @args) = @_;
    my ($cwd, $mask) = (getcwd(), umask());
    my @responses;
    my $output = '';
    open(my $stdout, '>', \$output) or die $!;
    my $result;
    {
        local $ENV{PATH} = "$dest/bin:$ENV{PATH}";
        local *STDOUT = $stdout;
        $result = eval {
            xCAT_plugin::packimage::process_request({ arg => [ '--nosyncfiles', @args ] }, sub { push @responses, @_ });
        };
        push @responses, { error => ["packimage died: $@"] } if $@;
    }
    chdir($cwd) or die $!;
    umask($mask);
    return ($result, join("\n", map { @{ $_->{error} || [] } } @responses));
}

sub content {
    my ($path) = @_;
    return -f $path ? read_binary($path) : undef;
}

sub listing {
    my ($method, $compress, $archive) = @_;
    my @command = $method eq 'squashfs' ? ($unsquashfs, '-l', $archive)
      : $method eq 'tar' ? (tool('tar'), '-tf', $archive)
      : ('/bin/sh', '-c', '"$1" -dc "$2" | cpio -t 2>/dev/null', 'list', tool($compress), $archive);
    open(my $pipe, '-|', @command) or die "list $archive: $!";
    my $text = do { local $/; <$pipe> };
    close($pipe);
    return $? ? undef : $text;
}

for my $case ([ 'cpio', 'gzip' ], [ 'cpio', 'xz' ], [ 'cpio', 'pigz' ], [ 'tar', 'gzip' ], [ 'tar', 'xz' ],
    [ 'squashfs', 'gzip' ]) {
    my ($method, $compress) = @$case;
    my $wrapped = $method eq 'squashfs' ? 'mksquashfs' : $compress;
    SKIP: {
        skip "$wrapped is not installed", 18 unless tool($wrapped);
        skip 'unsquashfs is not installed', 18 if $method eq 'squashfs' && !$unsquashfs;
        my @args = $method eq 'squashfs' ? ('-m', 'squashfs') : ('-m', $method, '-c', $compress);
        my $label = $method eq 'squashfs' ? 'squashfs' : "$method $compress";

        my ($name, $dest, $archive) = image($method, $compress, $wrapped, 'pass');
        my ($result, $errors) = packimage($dest, @args, $name);
        is($errors, '', "$label: the pack reports no error");
        is(content("$dest/seen"), "previous archive\n", "$label: nodes get the previous archive while the pack runs");
        isnt(content($archive), "previous archive\n", "$label: the new archive replaces the previous one");
        like(listing($method, $compress, $archive) // '', qr{(?:^|/)usr/bin/payload$}m,
            "$label: the new archive holds the image");
        is((stat($archive))[2] & 07777, 0644, "$label: the new archive is world readable");
        ok(!-e "$archive.metainfo", "$label: the metainfo of the previous archive is removed");
        ok(!-e "$dest/rootimg.previous", "$label: other formats are removed after the replacement");
        is_deeply([ glob("$dest/.packimage-$host+*") ], [], "$label: no partial archive is left, including an interrupted one");
        ok(-e "$dest/.packimage-other.host+ACTIVE00", "$label: the archive that another host is writing stays");
        ok(-e "$dest/.packimage-$host-backup+ACTIVE00", "$label: the archive of a host whose name starts with this one stays");

        ($name, $dest, $archive) = image($method, $compress, $wrapped, 'fail');
        ($result, $errors) = packimage($dest, @args, $name);
        like($errors, $method eq 'squashfs' ? qr/Command "mksquashfs .*" failed/s : qr/packimage failed while running/,
            "$label: the failure is reported");
        is(content("$dest/seen"), "previous archive\n", "$label: nodes get the previous archive while the failing pack runs");
        is(content($archive), "previous archive\n", "$label: a failed pack keeps the previous archive");
        is(content("$archive.metainfo"), "previous metainfo\n", "$label: a failed pack keeps the previous metainfo");
        is(content("$dest/rootimg.previous"), "previous format\n", "$label: a failed pack keeps other formats");
        is_deeply([ glob("$dest/.packimage-$host+*") ], [], "$label: a failed pack leaves no partial archive");
        my ($row) = $linuximage->getAttribs({ imagename => $name }, 'rootimgdir');
        is($row->{rootimgdir}, $dest, "$label: the image definition is unchanged");
        ok(-d "$dest/rootimg/usr/bin", "$label: the root image directory is unchanged");
    }
}

# A failure before the compressor, while listing or reading the files, must also keep the previous archive.
for my $case ([ 'cpio', 'cpio', 'fail', qr/packimage failed while running/ ],
    [ 'cpio', 'find', 'fail-listing', qr/Cannot enumerate/ ], [ 'tar', 'find', 'fail-listing', qr/Cannot enumerate/ ],
    [ 'squashfs', 'find', 'fail-listing', qr/Cannot enumerate/ ]) {
    my ($method, $wrapped, $mode, $error) = @$case;
    SKIP: {
        skip 'mksquashfs or unsquashfs is not installed', 5 if $method eq 'squashfs' && (!$mksquashfs || !$unsquashfs);
        my @args = $method eq 'squashfs' ? ('-m', 'squashfs') : ('-m', $method, '-c', 'gzip');
        my $label = "$method, $wrapped failure";
        my ($name, $dest, $archive) = image($method, 'gzip', $wrapped, $mode);
        my (undef, $errors) = packimage($dest, @args, $name);
        like($errors, $error, "$label: the failure is reported");
        is(content($archive), "previous archive\n", "$label: the previous archive stays");
        is(content("$archive.metainfo"), "previous metainfo\n", "$label: the previous metainfo stays");
        is(content("$dest/rootimg.previous"), "previous format\n", "$label: other formats stay");
        is_deeply([ glob("$dest/.packimage-$host+*") ], [], "$label: no partial archive is left");
    }
}

# packimage converts a StateLite tree to stateless files while it packs, and must convert it back on every exit.
my @statelite_files = qw(etc/hosts.lite etc/hosts.link etc/init.d/statelite usr/lib/dracut/modules.d/97xcat/install);
sub statelite_state {
    my ($root) = @_;
    my %state = map {
        my $path = "$root/$_";
        ($_ => -l $path ? '-> ' . readlink($path) : -f $path ? content($path) : 'missing')
    } @statelite_files;
    $state{'.statebackup'} = -e "$root/.statebackup" ? 'present' : 'absent';
    return \%state;
}
sub statelite_tree {
    my ($name, $root) = @_;
    make_path("$root/.statelite", "$root/.default/etc", "$root/etc/init.d");
    write_text("$root/.statelite/litefile.save", "litefile table\n");
    write_text("$root/etc/hosts.lite", "original lite file\n");
    write_text("$root/.default/etc/hosts.lite", "default lite file\n");
    symlink('hosts.lite', "$root/etc/hosts.link") or die $!;
    write_text("$root/.default/etc/hosts.link", "default for the link\n");
    write_text("$root/etc/init.d/statelite", "StateLite init script\n");
    write_text("$root/usr/lib/dracut/modules.d/97xcat/install", "StateLite dracut install\n");
    return ("$name link /etc/hosts.lite", "$name link /etc/hosts.link");
}
for my $case ([ 'find', 'fail-listing', qr/Cannot enumerate/ ], [ 'gzip', 'fail', qr/packimage failed while running/ ]) {
    my ($wrapped, $mode, $error) = @$case;
    my ($name, $dest, $archive) = image('cpio', 'gzip', $wrapped, $mode);
    my $root = "$dest/rootimg";
    local @LITEFILES = statelite_tree($name, $root);
    my $before = statelite_state($root);
    my $label = "StateLite, $wrapped failure";
    my (undef, $errors) = packimage($dest, '-m', 'cpio', '-c', 'gzip', $name);
    like($errors, $error, "$label: the failure is reported");
    is_deeply(statelite_state($root), $before, "$label: the files moved for packing are restored");
    unlink("$dest/bin/$wrapped") or die $!;
    (undef, $errors) = packimage($dest, '-m', 'cpio', '-c', 'gzip', $name);
    is($errors, '', "$label: a retry succeeds");
    is_deeply(statelite_state($root), $before, "$label: the retry keeps the original files");
    isnt(content($archive), "previous archive\n", "$label: the retry replaces the archive");
}

SKIP: {
    skip 'root can create the temporary archive in a read-only directory', 5 if $> == 0;
    my ($name, $dest, $archive) = image('cpio', 'gzip', 'gzip', 'pass');
    my $root = "$dest/rootimg";
    local @LITEFILES = statelite_tree($name, $root);
    my $before = statelite_state($root);
    my $label = 'StateLite, temporary archive failure';
    chmod 0555, $dest or die $!;
    my (undef, $errors) = packimage($dest, '-m', 'cpio', '-c', 'gzip', $name);
    chmod 0755, $dest or die $!;
    like($errors, qr/Cannot create a temporary directory in \Q$dest\E/, "$label: the failure is reported");
    is_deeply(statelite_state($root), $before, "$label: the files moved for packing are restored");
    is(content($archive), "previous archive\n", "$label: the previous archive stays");
    (undef, $errors) = packimage($dest, '-m', 'cpio', '-c', 'gzip', $name);
    is($errors, '', "$label: a retry succeeds");
    is_deeply(statelite_state($root), $before, "$label: the retry keeps the original files");
}

{
    my ($name, $dest, $archive) = image('cpio', 'gzip', 'mv', 'fail-restore');
    my $root = "$dest/rootimg";
    local @LITEFILES = statelite_tree($name, $root);
    my $label = 'StateLite, failed restore';
    my (undef, $errors) = packimage($dest, '-m', 'cpio', '-c', 'gzip', $name);
    like($errors, qr/Cannot restore the StateLite files .* The originals stay in \Q$root\E\/\.statebackup\./s,
        "$label: the failure is reported");
    is(content("$root/.statebackup/etc/hosts.lite"), "original lite file\n", "$label: the original file stays in .statebackup");
    is(readlink("$root/.statebackup/etc/hosts.link"), 'hosts.lite', "$label: the original link stays in .statebackup");
    is(content("$root/.statebackup/install"), "StateLite dracut install\n", "$label: the original dracut install stays in .statebackup");
    is(content($archive), "previous archive\n", "$label: the previous archive stays");
    is(content("$archive.metainfo"), "previous metainfo\n", "$label: the previous metainfo stays");
    unlink("$dest/bin/mv") or die $!;
    (undef, $errors) = packimage($dest, '-m', 'cpio', '-c', 'gzip', $name);
    like($errors, qr/\Q$root\E\/\.statebackup holds StateLite files that an earlier packimage did not restore/,
        "$label: the next pack refuses to run");
    is(content("$root/.statebackup/etc/hosts.lite"), "original lite file\n", "$label: the next pack keeps the original file");
    is(content("$root/.statebackup/install"), "StateLite dracut install\n", "$label: the next pack keeps the original dracut install");
}

{
    my ($name, $dest, $archive) = image('cpio', 'gzip', 'gzip', 'pass');
    my $label = 'another host publishing';
    mkdir("$dest/.packimage-publish") or die $!;
    write_text("$dest/.packimage-publish/owner", "other.host 4242\n");
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if ($pid == 0) {
        my (undef, $errors) = packimage($dest, '-m', 'cpio', '-c', 'gzip', $name);
        POSIX::_exit($errors eq '' ? 0 : 1);
    }
    my $deadline = time() + 30;
    sleep 1 until (!-e "$dest/.packimage-$host+INTERRUP" && (() = glob("$dest/.packimage-$host+????????")))
      || time() > $deadline;
    sleep 2;
    is(waitpid($pid, POSIX::WNOHANG()), 0, "$label: the pack waits while another host publishes");
    is(content($archive), "previous archive\n", "$label: the previous archive stays while another host publishes");
    unlink("$dest/.packimage-publish/owner");
    rmdir("$dest/.packimage-publish") or die $!;
    waitpid($pid, 0);
    is($? >> 8, 0, "$label: the pack succeeds after the other host finishes");
    isnt(content($archive), "previous archive\n", "$label: the new archive is published after the other host finishes");
    ok(!-e "$dest/.packimage-publish", "$label: the pack releases the publication lock");
}

{
    my ($name, $dest, $archive) = image('cpio', 'gzip', 'gzip', 'pass');
    my $label = 'publication lock left by another pack';
    mkdir("$dest/.packimage-publish") or die $!;
    write_text("$dest/.packimage-publish/owner", "other.host 4242\n");
    utime(time() - 120, time() - 120, "$dest/.packimage-publish") or die $!;
    my ($result, $errors) = packimage($dest, '-m', 'cpio', '-c', 'gzip', $name);
    like($errors, qr/\Q$dest\E\/\.packimage-publish is held by other\.host 4242\. If no packimage of this image runs on any host, remove it/,
        "$label: the failure names the holder and the recovery");
    is(content($archive), "previous archive\n", "$label: the previous archive stays");
    is(content("$dest/rootimg.previous"), "previous format\n", "$label: other formats stay");
    ok(-d "$dest/.packimage-publish", "$label: the lock of the other pack is not taken over");
    is_deeply([ glob("$dest/.packimage-$host+*") ], [], "$label: no partial archive is left");
}

{
    my ($name, $dest, $archive) = image('cpio', 'gzip', 'gzip', 'pass');
    my $label = 'tracker';
    write_text("$dest/bin/ctorrent", <<"SCRIPT");
#!/bin/sh
while [ \$# -gt 1 ]; do [ "\$1" = -s ] && out=\$2; shift; done
{ echo "\$1 \$(stat -c %s "\$1")"; cat '$archive'; } > "\$out"
SCRIPT
    chmod 0755, "$dest/bin/ctorrent";
    my (undef, $errors) = packimage($dest, '-m', 'cpio', '-c', 'gzip', '--tracker', 'http://tracker.example:6969/announce', $name);
    is($errors, '', "$label: the pack reports no error");
    is(content("$archive.metainfo"), 'rootimg.cpio.gz ' . (-s $archive) . "\nprevious archive\n",
        "$label: the metainfo describes the new archive under its final name before the archive is replaced");
    is((stat("$archive.metainfo"))[2] & 07777, 0644, "$label: nodes can read the metainfo");
    is_deeply([ glob("$dest/.packimage-$host+*") ], [], "$label: no temporary file is left");
}

{
    my ($name, $dest, $archive) = image('cpio', 'gzip', 'gzip', 'pass');
    my $label = 'failed tracker';
    write_text("$dest/bin/ctorrent", <<"SCRIPT");
#!/bin/sh
while [ \$# -gt 1 ]; do [ "\$1" = -s ] && out=\$2; shift; done
echo partial > "\$out"
exit 3
SCRIPT
    chmod 0755, "$dest/bin/ctorrent";
    my (undef, $errors) = packimage($dest, '-m', 'cpio', '-c', 'gzip', '--tracker', 'http://tracker.example:6969/announce', $name);
    like($errors, qr/ctorrent cannot create the metainfo of \Q$archive\E/, "$label: the failure is reported");
    is(content($archive), "previous archive\n", "$label: the previous archive stays");
    is(content("$archive.metainfo"), "previous metainfo\n", "$label: the previous metainfo stays");
    is(content("$dest/rootimg.previous"), "previous format\n", "$label: other formats stay");
    is_deeply([ glob("$dest/.packimage-$host+*") ], [], "$label: no temporary file is left");
}

{
    my ($name, $dest, $archive) = image('cpio', 'gzip', 'gzip', 'pass');
    my $label = 'previous metainfo that cannot be removed';
    write_text("$dest/bin/ctorrent", <<"SCRIPT");
#!/bin/sh
while [ \$# -gt 1 ]; do [ "\$1" = -s ] && out=\$2; shift; done
echo new metainfo > "\$out"
SCRIPT
    chmod 0755, "$dest/bin/ctorrent";
    unlink("$archive.metainfo") or die $!;
    make_path("$archive.metainfo/held");
    my (undef, $errors) = packimage($dest, '-m', 'cpio', '-c', 'gzip', '--tracker', 'http://tracker.example:6969/announce', $name);
    like($errors, qr/Cannot publish \Q$archive\E: /, "$label: the failure is reported");
    is(content($archive), "previous archive\n", "$label: the previous archive stays");
    ok(-d "$archive.metainfo/held", "$label: the previous metainfo stays");
    is(content("$dest/rootimg.previous"), "previous format\n", "$label: other formats stay");
    is_deeply([ glob("$dest/.packimage-$host+*") ], [], "$label: no temporary file is left");
}

done_testing();
