package XCAT::Test::UbuntuImage;

use strict;
use warnings;

use Capture::Tiny qw(capture_merged);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
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

1;
