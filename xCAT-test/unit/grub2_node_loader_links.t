#!/usr/bin/env perl
# The per-node loader links nodeset publishes in boot/grub2. An aarch64 node also gets
# grub2-<node>.efi, the name DHCP hands it, and grub2-<node> stays for DHCP that makedhcp did not write.
use strict;
use warnings;
no warnings 'once';

use Cwd qw(getcwd);
use File::Path qw(make_path);
use File::Slurper qw(write_text);
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
local *xCAT::NetworkUtils::getipaddr = sub {
    my ($class, $host) = @_;
    return '192.0.2.1' if $host eq 'server';
    return '192.0.2.2' if $host eq 'node';
    die "Unexpected hostname: $host";
};
use warnings 'redefine';

require(repo_path('xCAT-server/lib/xcat/plugins/grub2.pm'));

sub new_bootdir {
    my ($arch) = @_;
    my $tftpdir = tempdir(DIR => $root, CLEANUP => 1);
    make_path("$tftpdir/boot/grub2");
    write_text("$tftpdir/boot/grub2/grub2.$arch", "fixture loader\n");
    return $tftpdir;
}

sub nodeset {
    my ($tftpdir, $arch, $currstate, $os) = @_;
    my $cwd = getcwd();
    my @result = xCAT_plugin::grub2::setstate(
        'node',
        {node => [{kernel => 'images/vmlinuz', initrd => 'images/initrd.img', kcmdline => 'quiet'}]},
        {node => [{currstate => $currstate}]},
        {node => [{mac => '02:00:00:00:00:02'}]},
        $tftpdir, {node => [{tftpserver => 'server', netboot => 'grub2'}]}, {}, $arch, $os // 'rhels9.4',
    );
    chdir($cwd) or die "Cannot restore working directory: $!";
    is_deeply(\@result, [0, ''], "nodeset $currstate succeeds");
    return;
}

sub links {
    my ($tftpdir) = @_;
    opendir(my $dh, "$tftpdir/boot/grub2") or die "Cannot read $tftpdir/boot/grub2: $!";
    my %links = map { $_ => readlink("$tftpdir/boot/grub2/$_") } grep { -l "$tftpdir/boot/grub2/$_" } readdir($dh);
    closedir($dh);
    return \%links;
}

for my $case (['aarch64', 'aarch64'], ['x86_64', 'x86_64'], ['riscv64', 'riscv64'], ['ppc64', 'ppc']) {
    my ($arch, $loader_arch) = @$case;
    subtest "$arch: install" => sub {
        my $tftpdir = new_bootdir($loader_arch);
        nodeset($tftpdir, $arch, 'install');
        my %expected = ('grub2-node' => "grub2.$loader_arch");
        $expected{'grub2-node.efi'} = 'grub2.aarch64' if $arch eq 'aarch64';
        is_deeply(links($tftpdir), \%expected, 'the node loader links point at the architecture loader');

        nodeset($tftpdir, $arch, 'install');
        is_deeply(links($tftpdir), \%expected, 'a second nodeset leaves the same links');
    };
}

subtest 'aarch64: install after an older nodeset' => sub {
    my $tftpdir = new_bootdir('aarch64');
    symlink('grub2.aarch64', "$tftpdir/boot/grub2/grub2-node") or die "Cannot create the old link: $!";
    nodeset($tftpdir, 'aarch64', 'install');
    is_deeply(links($tftpdir), {'grub2-node' => 'grub2.aarch64', 'grub2-node.efi' => 'grub2.aarch64'},
        'the .efi link is added beside the old one');
};

for my $case (['boot'], ['offline'], ['standby', 'sles15.5']) {
    my ($state, $os) = @$case;
    subtest "aarch64: $state after install" . ($os ? " on $os" : '') => sub {
        my $tftpdir = new_bootdir('aarch64');
        nodeset($tftpdir, 'aarch64', 'install', $os);
        nodeset($tftpdir, 'aarch64', $state, $os);
        is_deeply(links($tftpdir), {}, 'both node loader links are removed');
    };
}

subtest 'aarch64: standby on an older SLES keeps both links' => sub {
    my $tftpdir = new_bootdir('aarch64');
    nodeset($tftpdir, 'aarch64', 'install', 'sles12.5');
    nodeset($tftpdir, 'aarch64', 'standby', 'sles12.5');
    is_deeply(links($tftpdir), {'grub2-node' => 'grub2.aarch64', 'grub2-node.efi' => 'grub2.aarch64'},
        'the node loader links stay');
};

done_testing();
