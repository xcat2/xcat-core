package XCAT::Test::Lifecycle;

use strict;
use warnings;
use Capture::Tiny qw(capture);
use Cwd qw(getcwd);
use File::Basename qw(dirname basename);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use Text::ParseWords qw(shellwords);
use XCAT::Test::File qw(repo_path);

sub command {
    my (@argv) = @_;
    my ($out, $err, $status) = capture { system(@argv) };
    $status = $status == -1 ? 255 : ($status & 127) ? 128 + ($status & 127) : $status >> 8;
    return ($status, $out, $err);
}

sub checked {
    my (@argv) = @_;
    my ($status, $out, $err) = command(@argv);
    die "@argv failed ($status):\n$out$err" if $status;
    return $out;
}

sub build_deb {
    my ($package) = @_;
    my $work = tempdir(CLEANUP => 1);
    checked('tar', '-cf', "$work/source.tar", '-C', repo_path('.'), $package);
    checked('tar', '-xf', "$work/source.tar", '-C', $work);
    my $previous = getcwd();
    chdir "$work/$package" or die "chdir: $!";
    local $ENV{PWD} = getcwd();
    my ($status, $out, $err) = command('dpkg-buildpackage', '-b', '-uc', '-us', '-d');
    chdir $previous or die "chdir: $!";
    die "Building $package failed ($status):\n$out$err" if $status;
    my @debs = glob "$work/*.deb";
    die "Expected one $package DEB, found @debs" unless @debs == 1;
    return $debs[0];
}

sub new {
    my ($class) = @_;
    my $root = tempdir(CLEANUP => 1);
    my $self = bless {root => $root}, $class;
    make_path(map { "$root/$_" } qw(etc opt var tmp run install root test-bin
        usr/sbin usr/lib/systemd/system usr/share/doc proc dev
        var/lib/dpkg/updates var/lib/dpkg/info var/lib/ucf var/cache/debconf
        etc/init.d etc/profile.d etc/systemd/system etc/alternatives));
    $self->write('/var/lib/dpkg/status', '');
    $self->write('/etc/passwd', "root:x:0:0:root:/root:/bin/sh\nwww-data:x:33:33:www-data:/var/www:/usr/sbin/nologin\n");
    $self->write('/etc/group', "root:x:0:\nwww-data:x:33:\n");
    $self->write('/etc/profile.d/xcat.sh', "export XCATROOT=/opt/xcat\nexport PATH=/test-bin:/opt/xcat/sbin:/usr/sbin:/usr/bin:/sbin:/bin\n");
    copy('/etc/ld.so.cache', "$root/etc/ld.so.cache") or die "copy ld.so.cache: $!" if -f '/etc/ld.so.cache';
    copy('/etc/debconf.conf', "$root/etc/debconf.conf") or die "copy debconf.conf: $!" if -f '/etc/debconf.conf';
    if (-f '/etc/debian_version') {
        my @packages = qw(base-files ucf debconf systemd init-system-helpers);
        $self->write('/var/lib/dpkg/status', checked('dpkg-query', '-s', @packages));
        for my $record ((map { "/var/lib/dpkg/info/$_.list" } @packages), '/var/lib/dpkg/info/ucf.templates') {
            copy($record, "$root/var/lib/dpkg/info/" . basename($record)) or die "copy $record: $!";
        }
    }
    for my $dir ('', '/sbin', '/lib', '/lib/systemd', '/share') {
        for my $entry (glob "/usr$dir/*") {
            my $name = basename($entry);
            next if $dir eq '/sbin' && $name eq 'init';
            next if -d "$root/usr$dir/$name";
            symlink("/host-usr$dir/$name", "$root/usr$dir/$name") or die "symlink: $!";
        }
    }
    for my $entry (glob '/etc/alternatives/*') {
        next unless -l $entry;
        symlink(readlink($entry), "$root/etc/alternatives/" . basename($entry)) or die "symlink: $!";
    }
    for my $dir (qw(bin sbin lib lib64)) {
        next unless -l "/$dir";
        symlink(readlink("/$dir"), "$root/$dir") or die "symlink: $!";
    }
    $self->private_bin('/sbin') if -d '/sbin' && !-l '/sbin';
    if (-f "$root/var/lib/dpkg/info/ucf.templates") {
        my ($status, $out, $err) = $self->run('debconf-loadtemplate', 'ucf', '/var/lib/dpkg/info/ucf.templates');
        die "Loading ucf templates failed: $out$err" if $status;
    }
    return $self;
}

sub path { return $_[0]->{root} . $_[1]; }

sub write {
    my ($self, $path, $text, $mode) = @_;
    my $destination = $self->path($path);
    make_path(dirname($destination));
    write_binary($destination, $text);
    chmod($mode, $destination) == 1 or die "chmod $destination: $!" if defined $mode;
}

sub read { return read_binary($_[0]->path($_[1])); }

sub private_bin {
    my ($self, $dir) = @_;
    my $target = $self->path($dir);
    unlink $target or die "unlink $target: $!" if -l $target;
    make_path($target);
    my $host = $dir =~ m{^/usr/} ? "/host-usr" . substr($dir, 4) : "/host" . $dir;
    for my $entry (glob "$dir/*") {
        my $name = basename($entry);
        next if $name eq 'init';
        next if -e "$target/$name" || -l "$target/$name";
        symlink("$host/$name", "$target/$name") or die "symlink: $!";
    }
}

sub hide_command {
    my ($self, $name) = @_;
    for my $dir (qw(/usr/bin /usr/sbin /bin /sbin)) {
        next if -l $dir;
        $self->private_bin($dir);
        my $entry = $self->path("$dir/$name");
        unlink $entry or die "unlink $entry: $!" if -e $entry || -l $entry;
    }
}

sub start_unit {
    my ($self, $path) = @_;
    my ($section, @commands);
    for my $line (split /\n/, $self->read($path)) {
        if ($line =~ /^\s*\[([^]]+)\]\s*$/) { $section = $1; next; }
        next unless ($section // '') eq 'Service' && $line =~ /^\s*ExecStart\s*=\s*(.*)$/;
        my $value = $1;
        if (length $value) { push @commands, $value; } else { @commands = (); }
    }
    die 'Expected one service start command' unless @commands == 1;
    return $self->run(shellwords($commands[0]));
}

sub run {
    my ($self, @argv) = @_;
    my $root = $self->{root};
    my $prefix = $self->{chroot} ? '/image' : '';
    my @mounts;
    if ($self->{chroot}) {
        push @mounts, '--tmpfs', '/', '--ro-bind', '/usr', '/usr';
        for my $dir (qw(bin sbin lib lib64)) {
            next unless -e "/$dir";
            push @mounts, -l "/$dir" ? ('--symlink', readlink("/$dir"), "/$dir")
                : ('--ro-bind', "/$dir", "/$dir");
        }
    }
    push @mounts, ('--bind', $root, "$prefix/", '--ro-bind', '/usr', "$prefix/host-usr",
        '--ro-bind', repo_path('.'), "$prefix/source");
    for my $dir (qw(bin sbin lib lib64)) {
        next unless -e "/$dir";
        next if -l "$root/$dir";
        push @mounts, -l "/$dir" ? ('--symlink', readlink("/$dir"), "$prefix/$dir")
            : ('--ro-bind', "/$dir", "$prefix/" . (-d "$root/$dir" ? "host/$dir" : $dir));
    }
    push @mounts, ('--ro-bind', $self->{deb}, "$prefix/package.deb") if $self->{deb};
    push @mounts, ('--proc', "$prefix/proc") if $self->{live};
    push @mounts, ('--cap-add', 'CAP_SYS_CHROOT') if $self->{chroot};
    unshift @argv, 'chroot', $prefix if $self->{chroot};
    return command('/usr/bin/env', '-i', 'PATH=/usr/bin:/bin',
        'bwrap', '--die-with-parent', '--unshare-all', '--uid', $self->{uid} // 0,
        '--gid', $self->{gid} // 0,
        @mounts, '--dev', "$prefix/dev", '--setenv', 'PATH',
        '/test-bin:/opt/xcat/sbin:/usr/sbin:/usr/bin:/sbin:/bin',
        '--setenv', 'HOME', '/root', '--setenv', 'LC_ALL', 'C',
        '--setenv', 'DEBIAN_FRONTEND', 'noninteractive', '--chdir', '/', @argv);
}

sub record_command {
    my ($self, $path, $delegate) = @_;
    my $name = basename($path);
    my $forward = defined $delegate ? "exec \"$delegate\" \"\$@\"\n" : '';
    $self->write($path, "#!/bin/sh\nprintf '$name' >> /calls\n" .
        'for arg do printf " <%s>" "$arg" >> /calls; done' .
        "\nprintf '\\n' >> /calls\n$forward", 0755);
}

sub install_deb {
    my ($self, $deb) = @_;
    local $self->{deb} = $deb;
    return $self->run('dpkg', '--force-depends', '--force-confold', '-i', '/package.deb');
}

sub deb_script {
    my ($self, $deb, $script, @args) = @_;
    local $self->{deb} = $deb;
    my @unpack = $self->run('dpkg-deb', '-e', '/package.deb', '/tmp/control');
    return @unpack if $unpack[0];
    my $package = checked('dpkg-deb', '-f', $deb, 'Package');
    chomp $package;
    return $self->run('env', "DPKG_MAINTSCRIPT_PACKAGE=$package",
        "DPKG_MAINTSCRIPT_NAME=$script", 'DPKG_MAINTSCRIPT_ARCH=all',
        '/bin/sh', "/tmp/control/$script", @args);
}

1;
