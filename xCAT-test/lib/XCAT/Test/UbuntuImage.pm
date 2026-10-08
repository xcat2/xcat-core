package XCAT::Test::UbuntuImage;

use strict;
use warnings;

use Capture::Tiny qw(capture_merged);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use JSON::PP qw(encode_json);
use XCAT::Test::File qw(repo_path);

sub new {
    my ($class) = @_;
    for my $tool (qw(bwrap timeout cpio gzip perl)) {
        die "Ubuntu image tests require $tool\n"
          unless grep { -x "$_/$tool" } qw(/usr/bin /bin /usr/sbin /sbin);
    }
    my $self = bless { root => tempdir(CLEANUP => 1) }, $class;
    make_path(map { "$self->{root}/$_" } qw(etc install tmp work/bin work/db));
    return $self;
}

sub write {
    my ($self, $file, $content) = @_;
    my $path = "$self->{root}/$file";
    make_path(dirname($path));
    write_binary($path, $content);
    return $path;
}

sub read {
    my ($self, $file) = @_;
    return read_binary("$self->{root}/$file");
}

sub run {
    my ($self, @command) = @_;
    my $root = $self->{root};
    my @sandbox = (
        'bwrap', '--unshare-all', '--die-with-parent', '--new-session',
        '--tmpfs', '/',
        (map { ('--ro-bind', $_, $_) } grep { -d $_ } qw(/usr /bin /sbin /lib /lib64)),
        '--dev', '/dev', '--proc', '/proc', '--dir', '/run', '--dir', '/sys',
        '--dir', '/opt',
        '--bind', "$root/etc", '/etc', '--bind', "$root/install", '/install',
        '--bind', "$root/tmp", '/tmp', '--bind', "$root/work", '/work',
        '--ro-bind', repo_path('.'), '/repo', '--chdir', '/work',
        '--setenv', 'PATH', '/work/bin:/usr/bin:/bin:/usr/sbin:/sbin',
        '--setenv', 'LC_ALL', 'C', '--setenv', 'XCATROOT', '/repo',
        '--setenv', 'XCATCFG', 'SQLite:/work/db',
        '--setenv', 'PERL5LIB', '/repo/perl-xCAT:/repo/xCAT-server/lib/perl',
    );
    push @sandbox, '--ro-bind', '/etc/alternatives', '/etc/alternatives'
      if -d '/etc/alternatives';
    my ($output, $status) = capture_merged {
        local %ENV = (PATH => '/usr/bin:/bin:/usr/sbin:/sbin');
        system(@sandbox, 'timeout', '45', @command);
        $?;
    };
    return ($status, $output);
}

sub prepare_genimage {
    my ($self) = @_;
    $self->write('etc/lsb-release', "DISTRIB_ID=Ubuntu\nDISTRIB_RELEASE=24.04\n");
    $self->write('etc/sysconfig/network-scripts/ifcfg-eth0', "SUBCHANNELS=0.0.f500,0.0.f501,0.0.f502\n");
}

sub bootstrap {
    my ($self, %options) = @_;
    $self->prepare_genimage();
    $self->write('work/packages/Packages.gz', 'package index fixture');
    $self->write('work/site.json', encode_json({
        (exists $options{mirror} ? (ubuntu_apt_mirror => $options{mirror}) : ()),
    }));
    if ($options{bootstrap_success}) {
        $self->write('work/bootstrap-success', '');
        for my $tool (qw(mount umount)) {
            my $path = $self->write("work/bin/$tool", "#!/bin/sh\nexit 0\n");
            chmod(0755, $path) or die "chmod $path: $!";
        }
        my $chroot = $self->write('work/bin/chroot', <<'SH');
#!/bin/sh
case "$*" in
    '/work/image/rootimg apt-get update')
        printf '%s\n' "$@" > /work/apt-update.args
        exit 23 ;;
    *) printf 'Unexpected chroot command: %s\n' "$*" >&2; exit 97 ;;
esac
SH
        chmod(0755, $chroot) or die "chmod $chroot: $!";
    }
    my $command = $self->write('work/bin/debootstrap', <<'SH');
#!/bin/sh
printf '%s\n' "$@" > /work/debootstrap.args
if [ -f /work/bootstrap-success ]; then
    mkdir -p "$5/etc/apt" "$5/proc" "$5/usr/sbin" "$5/mnt"
    exit 0
fi
exit 23
SH
    chmod(0755, $command) or die "chmod $command: $!";
    my ($status, $output) = $self->run('perl',
        '/repo/xCAT-test/native/fixtures/ubuntu_image/genimage.pl',
        '/repo/xCAT-server/share/xcat/netboot/ubuntu/genimage',
        '-a', $options{arch} || 'x86_64', '-o', 'ubuntu24.04',
        '-p', 'compute', '-i', 'eth0', '-n', 'fixture',
        '--rootimgdir', '/work/image',
        '--srcdir', $options{pkgdir} || '/work/packages', 'fixture-image');
    my $args = -f "$self->{root}/work/debootstrap.args"
      ? [split /\n/, $self->read('work/debootstrap.args')] : undef;
    return ($status, $output, $args);
}

1;
