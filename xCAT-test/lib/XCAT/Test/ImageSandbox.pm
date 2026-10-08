package XCAT::Test::ImageSandbox;
use strict;
use warnings;
use Capture::Tiny qw(capture);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use XCAT::Test::File qw(repo_path);

sub new {
    my ($class, %options) = @_;
    my $self = bless { %options, root => tempdir(CLEANUP => 1) }, $class;
    make_path(map { "$self->{root}/$_" } qw(etc install tmp work/bin work/db));
    return $self;
}

sub write {
    my ($self, $path, $bytes) = @_;
    my $file = "$self->{root}/$path";
    make_path(dirname($file));
    write_binary($file, $bytes);
    return $file;
}

sub command {
    my ($self, $name, $script) = @_;
    my $file = $self->write("work/bin/$name", "#!/bin/sh\n$script");
    chmod(0755, $file) or die "chmod $file: $!";
    return $file;
}

sub read {
    my ($self, $path) = @_;
    return read_binary("$self->{root}/$path");
}

sub run {
    my ($self, @command) = @_;
    my @sandbox = ('bwrap', '--unshare-all', '--die-with-parent', '--new-session', '--tmpfs', '/',
        (map { ('--ro-bind', $_, $_) } grep { -d $_ } qw(/usr /bin /sbin /lib /lib64)),
        '--proc', '/proc', '--dev', '/dev', '--dir', '/run', '--dir', '/sys', '--dir', '/opt',
        (map { ('--bind', "$self->{root}/$_", "/$_") } qw(etc install tmp work)),
        '--ro-bind', repo_path('.'), '/repo', '--chdir', '/work',
        '--setenv', 'PATH', '/work/bin:/usr/bin:/bin:/usr/sbin:/sbin',
        '--setenv', 'LC_ALL', 'C', '--setenv', 'XCATROOT', '/repo/xCAT-server',
        '--setenv', 'XCATCFG', 'SQLite:/work/db',
        '--setenv', 'PERL5LIB', '/repo/perl-xCAT:/repo/xCAT-server/lib/perl');
    push @sandbox, '--ro-bind', '/etc/alternatives', '/etc/alternatives' if -d '/etc/alternatives';
    push @sandbox, @{ $self->{mounts} || [] };
    my ($output, $error, $rc) = capture {
        local %ENV = (PATH => '/usr/bin:/bin:/usr/sbin:/sbin');
        system(@sandbox, 'timeout', '45', @command);
        $?;
    };
    return ($rc, $output, $error);
}
1;
