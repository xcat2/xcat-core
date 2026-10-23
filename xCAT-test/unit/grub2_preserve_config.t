#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';

use Cwd qw(getcwd);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use XCAT::Test::File qw(repo_path);

my $root = tempdir(CLEANUP => 1);
local $ENV{XCATROOT} = repo_path('xCAT-server');
local $ENV{XCATCFG} = "$root/config";
make_path($ENV{XCATCFG});
local %::XCATSITEVALS = (tftpdir => "$root/tftpboot", xcatdebugmode => 0);
require xCAT::Table;
require xCAT::NetworkUtils;

no warnings 'redefine';
local *xCAT::Table::new = sub { die 'Unexpected database access'; };
require(repo_path('xCAT-server/lib/xcat/plugins/grub2.pm'));

sub snapshot {
    my ($directory) = @_;
    opendir(my $dh, $directory) or die $!;
    my %files;
    for my $name (sort grep { !/^\./ } readdir($dh)) {
        my $file = "$directory/$name";
        my @stat = lstat($file);
        $files{$name} = {
            inode => $stat[1], mode => $stat[2], links => $stat[3],
            uid => $stat[4], gid => $stat[5], mtime => $stat[9],
            value => -l $file ? readlink($file) : scalar read_text($file),
        };
    }
    closedir($dh) or die $!;
    return \%files;
}

my @cases = (
    { name => 'invalid protocol', protocol => 'grub2-ftp',
      error => 'Invalid netboot method, please check noderes.netboot for node' },
    { name => 'unresolved server', server => 'missing-server',
      error => 'xCAT unable to resolve missing-server' },
    { name => 'failed facing address', server => '<xcatmaster>', facing => [1, 'no facing network'],
      error => 'no facing network' },
    { name => 'empty facing address', server => '<xcatmaster>', facing => [0, undef],
      error => 'Unable to determine the tftpserver for node' },
    { name => 'unresolved node', node_ip => undef,
      error => 'xCAT unable to resolve IP in grub2 plugin' },
    { name => 'unresolved boot node', state => 'boot', node_ip => undef,
      error => 'xCAT unable to resolve IP in grub2 plugin' },
    { name => 'unresolved offline node', state => 'offline', node_ip => undef,
      error => 'xCAT unable to resolve IP in grub2 plugin' },
    { name => 'missing architecture', missing_arch => 1,
      error => 'No archictecture defined in nodetype table for the node.' },
    { name => 'missing loader', missing_loader => 1 },
    { name => 'missing state', state => '',
      error => 'Cannot determine current state for this node' },
);

for my $arch (qw(x86_64 ppc64le aarch64 riscv64)) {
    for my $case (@cases) {
        subtest "$arch: $case->{name}" => sub {
            my $tftpdir = tempdir(DIR => $root, CLEANUP => 1);
            my $bootdir = "$tftpdir/boot/grub2";
            make_path($bootdir);
            my $loader_arch = $arch eq 'ppc64le' ? 'ppc' : $arch;
            my $loader = "$bootdir/grub2.$loader_arch";
            write_text($loader, "loader\n") unless $case->{missing_loader};
            write_text("$bootdir/grub2.previous", "previous loader\n");
            symlink('grub2.previous', "$bootdir/grub2-node") or die $!;
            symlink('grub2.previous', "$bootdir/grub2-node.efi") or die $!
                if $arch eq 'aarch64';
            write_text("$bootdir/node", "#shell\nset timeout=3\n");
            chmod 0640, "$bootdir/node" or die $!;
            for my $alias (qw(grub.cfg-C0000202 grub.cfg-01-02-00-00-00-00-02 old-alias)) {
                link("$bootdir/node", "$bootdir/$alias") or die $!;
            }
            write_text("$bootdir/unrelated", "#boot\n");
            my $before = snapshot($bootdir);
            my $node_ip = exists $case->{node_ip} ? $case->{node_ip} : '192.0.2.2';
            local *xCAT::NetworkUtils::getipaddr = sub {
                my ($class, $host) = @_;
                return '192.0.2.1' if $host eq 'server';
                return $node_ip if $host eq 'node';
                return if $host eq 'missing-server';
                die "Unexpected hostname: $host";
            };
            local *xCAT::NetworkUtils::my_ip_facing = sub {
                return @{ $case->{facing} || [0, '192.0.2.1'] };
            };
            my $cwd = getcwd();
            my @result = xCAT_plugin::grub2::setstate(
                'node',
                {node => [{kernel => 'images/vmlinuz', initrd => 'images/initrd.img', kcmdline => 'quiet'}]},
                {node => [{currstate => $case->{state} // 'install'}]},
                {node => [{mac => '02:00:00:00:00:02'}]},
                $tftpdir,
                {node => [{tftpserver => $case->{server} // 'server', netboot => $case->{protocol} // 'grub2-tftp'}]},
                {}, $case->{missing_arch} ? undef : $arch, 'linux',
            );
            chdir($cwd) or die "Cannot restore working directory: $!";
            my $error = $case->{error} // "Stop grub2 configuration for this node, \"$loader\" does not exits.";
            is_deeply(\@result, [1, $error], 'the requested update is rejected');
            is_deeply(snapshot($bootdir), $before, 'all prior artifacts and hard links remain unchanged');
            is(xCAT_plugin::grub2::getstate('node', $tftpdir), 'shell', 'reported state remains the previous state');
        };
    }
}

done_testing();
