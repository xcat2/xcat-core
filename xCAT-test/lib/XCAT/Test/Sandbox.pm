package XCAT::Test::Sandbox;

use strict;
use warnings;
use Exporter qw(import);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use XCAT::Test::Process qw(run_command);

our @EXPORT_OK = qw(sandbox_root sandbox_run);

sub sandbox_root {
    my $root = tempdir(CLEANUP => 1);
    make_path(map { "$root/$_" } qw(bin boot etc log target tmp));
    return $root;
}

sub sandbox_run {
    my ($root, @command) = @_;
    my $options = ref($command[0]) eq 'HASH' ? shift @command : {};
    my $bwrap = -x '/usr/bin/bwrap' ? '/usr/bin/bwrap' : '/bin/bwrap';
    die 'Install bubblewrap to run this test' unless -x $bwrap;
    my @sandbox = ($bwrap, '--unshare-all', '--die-with-parent', '--new-session',
        '--tmpfs', '/', '--proc', '/proc', '--dev', '/dev', '--tmpfs', '/run',
        '--setenv', 'PATH', '/fixture/bin:/usr/bin:/bin',
        '--setenv', 'LC_ALL', 'C', '--bind', $root, '/fixture', '--chdir', '/fixture');
    for my $directory (qw(/usr /bin /sbin /lib /lib64)) {
        push @sandbox, '--ro-bind', $directory, $directory if -d $directory;
    }
    for my $mount (qw(boot etc target tmp)) {
        push @sandbox, '--bind', "$root/$mount", "/$mount";
    }
    push @sandbox, '--bind', "$root/log", '/var/log';
    push @sandbox, '--ro-bind', '/etc/alternatives', '/etc/alternatives' if -d '/etc/alternatives';
    my @mounts;
    for my $kind (qw(read_only writable)) {
        my $flag = $kind eq 'read_only' ? '--ro-bind' : '--bind';
        push @mounts, map { [$flag, $_, $options->{$kind}{$_}] }
            keys %{$options->{$kind} // {}};
    }
    for my $mount (sort { length($a->[2]) <=> length($b->[2]) || $a->[2] cmp $b->[2] } @mounts) {
        push @sandbox, @$mount;
    }
    for my $name (keys %{$options->{env} // {}}) {
        push @sandbox, '--setenv', $name, $options->{env}{$name};
    }
    local %ENV;
    return run_command(@sandbox, '/usr/bin/timeout', '--kill-after=5', '45', @command);
}

1;
