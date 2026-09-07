#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_BOOT_MODULE_DIR};
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Errno qw(EIO);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Find;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use IO::Compress::Gzip qw(gzip);
use JSON;
use POSIX ();
use Test::More;
use xCAT::FreeBSDBoot;
use xCAT::FreeBSDImage;

my $temporary = abs_path(tempdir(CLEANUP => 1));
my $sequence = 0;

sub write_file {
    my ($path, $text) = @_;
    make_path(dirname($path));
    chmod(0644, $path) if -f $path;
    open(my $file, '>', $path) or die "$path: $!";
    binmode($file);
    print {$file} $text;
    close($file) or die "$path: $!";
}

sub read_file {
    my $path = shift;
    open(my $file, '<', $path) or die "$path: $!";
    binmode($file);
    my $text = do { local $/; <$file> };
    close($file);
    return $text;
}

sub fixture {
    my $root = "$temporary/fixture-" . ++$sequence;
    make_path("$root/media", "$root/tftp");
    my $efi = "\0" x 512;
    substr($efi, 0, 2) = 'MZ';
    substr($efi, 60, 4) = pack('V', 128);
    substr($efi, 128, 4) = "PE\0\0";
    substr($efi, 132, 2) = pack('v', 0x8664);
    substr($efi, 152, 2) = pack('v', 0x20b);
    substr($efi, 220, 2) = pack('v', 10);
    my $elf = "\x7fELF\x02\x01\x01\x09" . ("\0" x 10) . pack('v', 62);
    my ($kernel, $mfsroot);
    gzip(\$elf => \$kernel) or die $IO::Compress::Gzip::GzipError;
    my $ramdisk = 'installer fixture';
    gzip(\$ramdisk => \$mfsroot) or die $IO::Compress::Gzip::GzipError;
    my %files = (
        'boot/pxeboot' => 'BIOS loader', 'boot/loader.efi' => $efi,
        'boot/loader.conf' => "mfs_name=\"/mfsroot\"\nmfs_load=\"YES\"\n",
        'boot/defaults/loader.conf' => 'loader defaults', 'boot/lua/loader.lua' => 'loader entry',
        'boot/kernel/kernel.gz' => $kernel, 'mfsroot.gz' => $mfsroot,
        'usr/freebsd-dist/base.txz' => 'base set', 'usr/freebsd-dist/kernel.txz' => 'kernel set',
    );
    $files{'usr/freebsd-dist/MANIFEST'} = join('', map {
        "$_\t" . sha256_hex($files{"usr/freebsd-dist/$_"}) . "\t1\tset\tSet\ton\n"
    } qw(base.txz kernel.txz));
    write_file("$root/media/$_", $files{$_}) for keys %files;
    write_file("$root/media/xcat/mfsbsd.json", JSON->new->canonical->encode({
        format => 'xcat-mfsbsd-1', release => '15.1-RELEASE', arch => 'amd64',
        files => { map { $_ => sha256_hex($files{$_}) } keys %files },
    }));
    my %options = (
        generation => 'a' x 32, pkgdir => "$root/media", tftpdir => "$root/tftp",
        media => xCAT::FreeBSDImage::inspect_media("$root/media"),
        config_url => 'http://192.0.2.1/install/autoinst/node01/generation',
        config_sha256 => 'b' x 64, mac => '52:54:00:12:34:56',
    );
    return ($root, \%options, \%files);
}

sub files_under {
    my $root = shift;
    my @files;
    File::Find::find({ no_chdir => 1, wanted => sub {
        push @files, substr($File::Find::name, length($root) + 1) if -f $File::Find::name;
    } }, $root);
    return [sort @files];
}

my ($root, $options, $files) = fixture();
my $result = xCAT::FreeBSDBoot::publish('node01', %$options);
is_deeply($result, { kernel => 'xcat/freebsd/node01/boot/pxeboot', initrd => '', kcmdline => '', addkcmdline => '' },
    'publication returns the native BIOS chain contract');
my $prefix = "$root/tftp/xcat/freebsd";
my $shared = "$prefix/.images/$options->{media}{digest}";
my $generation = "$prefix/.nodes/node01/$options->{generation}";
is(readlink("$prefix/node01"), ".nodes/node01/$options->{generation}", 'the stable node link is relative and generation-scoped');
my @boot_files = sort grep { !m{^usr/} } keys %$files;
is_deeply(files_under($shared), \@boot_files, 'only boot payloads reach the shared TFTP image');
is_deeply(files_under($generation), \@boot_files, 'node generations contain no distribution archives or metadata');
for my $relative (@boot_files) {
    if ($relative eq 'boot/loader.conf') {
        isnt((stat("$generation/$relative"))[1], (stat("$shared/$relative"))[1], 'the node loader configuration is private');
    } else {
        is((stat("$generation/$relative"))[1], (stat("$shared/$relative"))[1], "$relative is hardlinked to the shared image");
    }
}
my $loader = "$files->{'boot/loader.conf'}\nxcat_config_url=\"$options->{config_url}\"\n" .
    "xcat_config_sha256=\"$options->{config_sha256}\"\nboot.netif.hwaddr=\"$options->{mac}\"\n";
is(read_file("$generation/boot/loader.conf"), $loader, 'the node loader preserves media settings and appends exact configuration pins');
is(read_file("$shared/boot/loader.conf"), $files->{'boot/loader.conf'}, 'shared loader settings are unchanged');
is((stat("$generation/boot/loader.conf"))[2] & 0777, 0444, 'the node configuration is read-only');
my $inode = (stat("$generation/boot/loader.conf"))[1];
xCAT::FreeBSDBoot::publish('node01', %$options);
is((stat("$generation/boot/loader.conf"))[1], $inode, 'repeated publication validates and reuses the generation');
xCAT::FreeBSDBoot::publish('node02', %$options, mac => '52:54:00:12:34:57');
is((stat("$prefix/node02/mfsroot.gz"))[1], (stat("$generation/mfsroot.gz"))[1], 'different nodes reuse one shared RAM image');
is(read_file("$generation/boot/loader.conf"), $loader, 'another node cannot change an existing node configuration');
my $next = 'c' x 32;
xCAT::FreeBSDBoot::publish('node01', %$options, generation => $next);
is(readlink("$prefix/node01"), ".nodes/node01/$next", 'a new generation replaces only the stable link');
ok(-d $generation, 'older generations remain available');

{
    my ($base, $arguments) = fixture();
    my $addfile = \&Digest::SHA::addfile;
    for my $case (['node01', 'new generation'], ['node01', 'reused generation'], ['node02', 'another node']) {
        my %reads;
        {
            no warnings 'redefine';
            local *Digest::SHA::addfile = sub {
                my @stat = stat($_[1]);
                $reads{"$stat[0]:$stat[1]"}++;
                return $addfile->(@_);
            };
            xCAT::FreeBSDBoot::publish($case->[0], %$arguments);
        }
        my $boot = "$base/tftp/xcat/freebsd";
        my $image = "$boot/.images/$arguments->{media}{digest}";
        my @paths = map { "$image/$_" } @boot_files;
        push @paths, "$boot/.nodes/$case->[0]/$arguments->{generation}/boot/loader.conf";
        my %expected = map { my @stat = stat($_); ("$stat[0]:$stat[1]" => 1) } @paths;
        is_deeply(\%reads, \%expected, "$case->[1] hashes shared payload once and its private loader separately");
    }
}

{
    my ($base, $arguments) = fixture();
    xCAT::FreeBSDBoot::publish('node01', %$arguments);
    my $boot = "$base/tftp/xcat/freebsd";
    my $payload = "$boot/.images/$arguments->{media}{digest}/mfsroot.gz";
    my @before = stat($payload);
    my $content = read_file($payload);
    substr($content, 0, 1) = chr(ord(substr($content, 0, 1)) ^ 1);
    write_file($payload, $content);
    chmod(0444, $payload) or die $!;
    utime($before[8], $before[9], $payload) or die $!;
    my @after = stat($payload);
    is_deeply([@after[0, 1, 7, 9]], [@before[0, 1, 7, 9]], 'in-place corruption preserves identity, size and modification time');
    eval { xCAT::FreeBSDBoot::publish('node01', %$arguments); 1 };
    like($@, qr/checksum mismatch/, 'a new publication rehashes shared bytes even when identity and modification time match');
    is(readlink("$boot/node01"), ".nodes/node01/$arguments->{generation}", 'shared corruption does not change the stable generation');
}

{
    my ($base, $arguments) = fixture();
    xCAT::FreeBSDBoot::publish('node01', %$arguments);
    my $boot = "$base/tftp/xcat/freebsd";
    my $payload = "$boot/.images/$arguments->{media}{digest}/mfsroot.gz";
    my @verified = stat($payload);
    my $content = read_file($payload);
    my $tempdir = \&File::Temp::tempdir;
    my $replaced = 0;
    {
        no warnings 'redefine';
        local *xCAT::FreeBSDBoot::tempdir = sub {
            my ($template, %settings) = @_;
            my $directory = $tempdir->(@_);
            if ($template =~ /^\.publish-stage/ && $settings{DIR} eq "$boot/.nodes/node02") {
                rename($payload, "$base/verified-original") or die $!;
                write_file($payload, $content);
                chmod(0444, $payload) or die $!;
                $replaced++;
            }
            return $directory;
        };
        eval { xCAT::FreeBSDBoot::publish('node02', %$arguments); 1 };
    }
    like($@, qr/not linked/, 'node publication rejects a different inode substituted after shared verification');
    is($replaced, 1, 'the substitution runs between shared verification and node staging');
    isnt((stat($payload))[1], $verified[1], 'the replacement has a distinct inode');
    is(read_file($payload), $content, 'the replacement has the same verified bytes');
    is((stat("$boot/node01/mfsroot.gz"))[1], $verified[1], 'the previous node keeps the verified inode');
    ok(!-e "$boot/node02", 'an unverified replacement publishes no stable node');
}

for my $change (
    [generation => '../escape'], [config_sha256 => 'bad'], [mac => '52:54:00:12:34:FF'],
    [config_url => 'http://192.0.2.1/../escape'], [config_url => "http://192.0.2.1/config\nBAD=1"],
    [tftpdir => '/'], [tftpdir => "$root/tftp/../tftp"], [unexpected => 'value'],
) {
    eval { xCAT::FreeBSDBoot::publish('node01', %$options, $change->[0] => $change->[1]); 1 };
    like($@, qr/FreeBSD boot publication:/, "invalid $change->[0] is rejected");
}
for my $node ('../node01', '.nodes', 'node01/child') {
    eval { xCAT::FreeBSDBoot::publish($node, %$options); 1 };
    like($@, qr/Invalid node name/, "unsafe node $node is rejected");
}
eval { xCAT::FreeBSDBoot::publish('node01', %$options, config_sha256 => 'd' x 64); 1 };
like($@, qr/checksum mismatch/, 'a generation cannot be reused with changed configuration pins');
is(readlink("$prefix/node01"), ".nodes/node01/$next", 'failed reuse leaves the stable generation unchanged');

for my $mutate (
    sub { $_[0]{digest} = 'bad'; },
    sub { $_[0]{files}{'boot/../outside'} = 'a' x 64; },
    sub { $_[0]{files}{'boot/pxeboot'} = 'bad'; },
    sub { delete $_[0]{files}{'mfsroot.gz'}; },
) {
    my ($base, $arguments) = fixture();
    $mutate->($arguments->{media});
    eval { xCAT::FreeBSDBoot::publish('node01', %$arguments); 1 };
    like($@, qr/(?:Validated|Invalid boot|Missing required)/, 'invalid inspected-media metadata is rejected');
    ok(!-e "$base/tftp/xcat/freebsd/node01", 'invalid metadata publishes no node');
}

{
    my ($base, $arguments) = fixture();
    chmod(0777, "$base/tftp") or die $!;
    eval { xCAT::FreeBSDBoot::publish('node01', %$arguments); 1 };
    like($@, qr/Unsafe directory permissions/, 'a writable parent cannot permit publication path substitution');
    ok(!-e "$base/tftp/xcat/freebsd/node01", 'unsafe directory permissions publish no node');
}

for my $kind (qw(source-root source-child tftp-root managed-child managed-node stable-directory stable-link stable-other-node)) {
    my ($base, $arguments) = fixture();
    my $boot = "$base/tftp/xcat/freebsd";
    make_path("$base/outside", $boot);
    write_file("$base/outside/sentinel", 'unchanged');
    if ($kind eq 'source-root' || $kind eq 'tftp-root') {
        my $key = $kind eq 'source-root' ? 'pkgdir' : 'tftpdir';
        symlink($arguments->{$key}, "$base/alias") or die $!;
        $arguments->{$key} = "$base/alias";
    } elsif ($kind eq 'source-child') {
        rename("$base/media/boot/lua", "$base/lua") or die $!;
        symlink("$base/lua", "$base/media/boot/lua") or die $!;
    } elsif ($kind eq 'managed-child') {
        symlink("$base/outside", "$boot/.images") or die $!;
    } elsif ($kind eq 'managed-node') {
        make_path("$boot/.nodes");
        symlink("$base/outside", "$boot/.nodes/node01") or die $!;
    } elsif ($kind eq 'stable-directory') {
        make_path("$boot/node01");
        write_file("$boot/node01/sentinel", 'unrelated');
    } else {
        symlink($kind eq 'stable-link' ? "$base/outside" : '.nodes/node02/' . ('a' x 32), "$boot/node01") or die $!;
    }
    eval { xCAT::FreeBSDBoot::publish('node01', %$arguments); 1 };
    like($@, qr/(?:plain directory|unrelated)/, "$kind cannot redirect publication");
    is(read_file("$base/outside/sentinel"), 'unchanged', "$kind leaves unrelated data unchanged");
}

for my $kind (qw(shared-bytes generation-bytes shared-directory generation-directory extra-file detached-link)) {
    my ($base, $arguments) = fixture();
    xCAT::FreeBSDBoot::publish('node01', %$arguments);
    my $boot = "$base/tftp/xcat/freebsd";
    my $tree = "$boot/.nodes/node01/$arguments->{generation}";
    if ($kind eq 'shared-bytes') {
        write_file("$boot/.images/$arguments->{media}{digest}/mfsroot.gz", 'corrupted');
    } elsif ($kind eq 'generation-bytes') {
        write_file("$tree/boot/loader.conf", 'corrupted');
    } elsif ($kind eq 'shared-directory') {
        chmod(0777, "$boot/.images/$arguments->{media}{digest}/boot") or die $!;
    } elsif ($kind eq 'generation-directory') {
        chmod(0777, "$tree/boot") or die $!;
    } elsif ($kind eq 'extra-file') {
        write_file("$tree/usr/freebsd-dist/base.txz", 'unexpected');
    } else {
        my $content = read_file("$tree/mfsroot.gz");
        unlink("$tree/mfsroot.gz") or die $!;
        write_file("$tree/mfsroot.gz", $content);
    }
    eval { xCAT::FreeBSDBoot::publish('node01', %$arguments); 1 };
    like($@, qr/(?:checksum mismatch|Unexpected boot|not linked|Unsafe directory permissions)/, "changed $kind fails validation");
    is(readlink("$boot/node01"), ".nodes/node01/$arguments->{generation}", 'validation failure does not switch the stable link');
}

{
    my ($base, $arguments) = fixture();
    my $copy = \&File::Copy::copy;
    my $count = 0;
    {
        no warnings 'redefine';
        local *xCAT::FreeBSDBoot::copy = sub {
            if (++$count == 2) { $! = EIO; return 0; }
            return $copy->(@_);
        };
        eval { xCAT::FreeBSDBoot::publish('node01', %$arguments); 1 };
    }
    like($@, qr/Cannot copy/, 'a mid-copy failure is reported');
    ok(!-e "$base/tftp/xcat/freebsd/node01", 'a failed copy publishes no stable node');
    opendir(my $directory, "$base/tftp/xcat/freebsd/.images") or die $!;
    is_deeply([grep { $_ ne '.' && $_ ne '..' } readdir($directory)], [], 'only the failed unique image stage is cleaned up');
    closedir($directory);
}

{
    my ($base, $arguments) = fixture();
    my $copy = \&File::Copy::copy;
    {
        no warnings 'redefine';
        local *xCAT::FreeBSDBoot::copy = sub {
            my $ok = $copy->(@_);
            write_file($_[1], 'corrupted during copy') if $ok;
            return $ok;
        };
        eval { xCAT::FreeBSDBoot::publish('node01', %$arguments); 1 };
    }
    like($@, qr/checksum mismatch/, 'copied boot bytes are verified before publication');
    ok(!-e "$base/tftp/xcat/freebsd/node01", 'copy corruption publishes no stable node');
}

{
    my ($base, $arguments) = fixture();
    xCAT::FreeBSDBoot::publish('node01', %$arguments);
    my $boot = "$base/tftp/xcat/freebsd";
    my $tempdir = \&File::Temp::tempdir;
    {
        no warnings 'redefine';
        local *xCAT::FreeBSDBoot::tempdir = sub {
            my $directory = $tempdir->(@_);
            write_file("$directory/node", 'collision') if $_[0] =~ /^\.link-stage/;
            return $directory;
        };
        eval { xCAT::FreeBSDBoot::publish('node01', %$arguments, generation => 'c' x 32); 1 };
    }
    like($@, qr/Cannot stage node link/, 'a failed stable-link update reports the error');
    is(readlink("$boot/node01"), ".nodes/node01/$arguments->{generation}", 'a failed stable-link update preserves the previous generation');
    ok(-d "$boot/.nodes/node01/" . ('c' x 32), 'a complete but unactivated generation is retained');
    opendir(my $directory, $boot) or die $!;
    is_deeply([grep { /^\.link-stage/ } readdir($directory)], [], 'the failed unique link stage is removed');
    closedir($directory);
}

{
    my ($base, $arguments) = fixture();
    my @children;
    for (1 .. 3) {
        my $pid = fork();
        die $! unless defined($pid);
        if (!$pid) {
            my $ok = eval { xCAT::FreeBSDBoot::publish('node01', %$arguments); 1 };
            warn $@ unless $ok;
            POSIX::_exit($ok ? 0 : 1);
        }
        push @children, $pid;
    }
    for my $pid (@children) {
        waitpid($pid, 0);
        is($?, 0, 'concurrent publication validates or creates the same generation');
    }
    is(readlink("$base/tftp/xcat/freebsd/node01"), ".nodes/node01/$arguments->{generation}",
        'concurrent publication retains one complete stable generation');
}

sub config_fixture {
    my $base = "$temporary/config-" . ++$sequence;
    make_path($base);
    return ($base, { installroot => $base, generation => 'd' x 32,
        content => "format=xcat-freebsd-install-1\nnode=node01\n" });
}

{
    my ($base, $arguments) = config_fixture();
    my $relative = xCAT::FreeBSDBoot::publish_config('node01', %$arguments);
    is($relative, 'autoinst/freebsd/node01/' . ('d' x 32) . '.conf', 'configuration publication returns only its relative path');
    is(read_file("$base/$relative"), $arguments->{content}, 'published configuration preserves exact rendered bytes');
    is((stat("$base/$relative"))[2] & 07777, 0644, 'published configuration is mode 0644');
    my $inode = (stat("$base/$relative"))[1];
    is(xCAT::FreeBSDBoot::publish_config('node01', %$arguments), $relative, 'identical configuration generation can be reused');
    is((stat("$base/$relative"))[1], $inode, 'configuration reuse preserves the inode');
    eval { xCAT::FreeBSDBoot::publish_config('node01', %$arguments, content => 'changed'); 1 };
    like($@, qr/contents differ/, 'changed configuration generation is rejected');
    is(read_file("$base/$relative"), $arguments->{content}, 'changed generation cannot overwrite existing configuration');
    my $next = xCAT::FreeBSDBoot::publish_config('node01', %$arguments, generation => 'e' x 32, content => 'next');
    is(read_file("$base/$next"), 'next', 'a new configuration generation is independently published');
    is(read_file("$base/$relative"), $arguments->{content}, 'older configuration generations remain available');
    is_deeply(files_under($base), [sort($relative, $next)], 'successful publication leaves no temporary configuration');
}

for my $invalid (
    [generation => 'invalid'], [installroot => 'relative'], [installroot => "$temporary/../outside"],
    [content => undef], [content => ''], [content => 'x' x 32769], [content => []],
    [content => "\x{100}"], [unexpected => 1],
) {
    my ($base, $arguments) = config_fixture();
    eval { xCAT::FreeBSDBoot::publish_config('node01', %$arguments, @$invalid); 1 };
    like($@, qr/FreeBSD boot publication:/, "invalid configuration $invalid->[0] is rejected");
    is_deeply(files_under($base), [], 'invalid configuration input publishes no file');
}

{
    my ($base, $arguments) = config_fixture();
    my $relative = xCAT::FreeBSDBoot::publish_config('node01', %$arguments, content => 'x' x 32768);
    is(length(read_file("$base/$relative")), 32768, 'the maximum configuration length is accepted');
    eval { xCAT::FreeBSDBoot::publish_config('../node01', %$arguments); 1 };
    like($@, qr/Invalid node name/, 'configuration publication rejects node traversal');
}

for my $kind (qw(root-link parent-link file-link directory fifo writable-file writable-directory)) {
    my ($base, $arguments) = config_fixture();
    my $outside = "$temporary/outside-" . ++$sequence;
    make_path($outside);
    write_file("$outside/sentinel", 'unchanged');
    my $parent = "$base/autoinst/freebsd/node01";
    my $destination = "$parent/$arguments->{generation}.conf";
    if ($kind eq 'root-link') {
        symlink($base, "$base-alias") or die $!;
        $arguments->{installroot} = "$base-alias";
    } elsif ($kind eq 'parent-link') {
        symlink($outside, "$base/autoinst") or die $!;
    } else {
        make_path($parent);
        if ($kind eq 'file-link') {
            symlink("$outside/sentinel", $destination) or die $!;
        } elsif ($kind eq 'directory') {
            make_path($destination);
        } elsif ($kind eq 'fifo') {
            POSIX::mkfifo($destination, 0644) == 0 or die $!;
        } elsif ($kind eq 'writable-file') {
            write_file($destination, $arguments->{content});
            chmod(0666, $destination) or die $!;
        } else {
            chmod(0777, $parent) or die $!;
        }
    }
    eval { xCAT::FreeBSDBoot::publish_config('node01', %$arguments); 1 };
    like($@, qr/(?:plain directory|Unsafe|Cannot open configuration)/, "configuration $kind is rejected");
    is(read_file("$outside/sentinel"), 'unchanged', 'configuration failure preserves unrelated files');
}

{
    my ($base, $arguments) = config_fixture();
    my $tempfile = \&File::Temp::tempfile;
    my $stage_path;
    {
        no warnings 'redefine';
        local *xCAT::FreeBSDBoot::tempfile = sub {
            my @result = $tempfile->(@_);
            $stage_path = $result[1];
            return @result;
        };
        local *IO::Handle::sync = sub {
            rename($stage_path, "$stage_path.retained") or die $!;
            mkdir($stage_path) or die $!;
            $! = EIO;
            return 0;
        };
        eval { xCAT::FreeBSDBoot::publish_config('node01', %$arguments); 1 };
    }
    like($@, qr/Cannot sync configuration:.*\nCannot remove temporary configuration /s,
        'publication preserves the original error when temporary-file cleanup also fails');
    ok(!-e "$base/autoinst/freebsd/node01/$arguments->{generation}.conf",
        'failed publication and cleanup cannot publish a configuration');
}

for my $method (qw(flush sync)) {
    my ($base, $arguments) = config_fixture();
    {
        no warnings 'redefine';
        no strict 'refs';
        local *{"IO::Handle::$method"} = sub { $! = EIO; return 0; };
        eval { xCAT::FreeBSDBoot::publish_config('node01', %$arguments); 1 };
    }
    like($@, qr/Cannot $method configuration/, "configuration $method failure is reported");
    is_deeply(files_under($base), [], "configuration $method failure leaves no published or temporary file");
}

{
    my ($base, $arguments) = config_fixture();
    my $tempfile = \&File::Temp::tempfile;
    {
        no warnings 'redefine';
        local *xCAT::FreeBSDBoot::tempfile = sub {
            my @temporary = $tempfile->(@_);
            write_file("$base/autoinst/freebsd/node01/$arguments->{generation}.conf", 'concurrent winner');
            return @temporary;
        };
        eval { xCAT::FreeBSDBoot::publish_config('node01', %$arguments); 1 };
    }
    like($@, qr/contents differ/, 'a differing concurrent configuration wins without being overwritten');
    my $relative = "autoinst/freebsd/node01/$arguments->{generation}.conf";
    is(read_file("$base/$relative"), 'concurrent winner', 'no-overwrite publication preserves the concurrent file');
    is_deeply(files_under($base), [$relative], 'a concurrent conflict cleans only its unique temporary file');
}

{
    my ($base, $arguments) = config_fixture();
    my @children;
    for (1 .. 3) {
        my $pid = fork();
        die $! unless defined($pid);
        if (!$pid) {
            my $ok = eval { xCAT::FreeBSDBoot::publish_config('node01', %$arguments); 1 };
            warn $@ unless $ok;
            POSIX::_exit($ok ? 0 : 1);
        }
        push @children, $pid;
    }
    for my $pid (@children) {
        waitpid($pid, 0);
        is($?, 0, 'identical concurrent configurations publish or reuse successfully');
    }
    is(read_file("$base/autoinst/freebsd/node01/$arguments->{generation}.conf"), $arguments->{content},
        'concurrent configuration publication retains the complete content');
}

done_testing;
