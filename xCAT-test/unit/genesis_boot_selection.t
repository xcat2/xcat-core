#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $root = tempdir(CLEANUP => 1);
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "$root/config";
make_path($ENV{XCATCFG}, "$root/xcat");
require(repo_path('xCAT-server/lib/xcat/plugins/anaconda.pm'));
require(repo_path('xCAT-server/lib/xcat/plugins/sles.pm'));
my @owners = (
    ['Anaconda', \&xCAT_plugin::anaconda::_find_genesis_boot_files],
    ['SLES', \&xCAT_plugin::sles::_find_genesis_boot_files],
);

sub selection {
    my ($arch, $expected, $description) = @_;
    for my $owner (@owners) {
        is_deeply([$owner->[1]->($root, $arch)], $expected, "$owner->[0]: $description");
    }
}

for my $arch (qw(x86 x86_64 ppc64 ppc64le aarch64 armv7hf riscv64 s390x)) {
    selection($arch, [], "$arch without kernel is not selected");
    write_text("$root/xcat/genesis.kernel.$arch", 'kernel');
    selection($arch, [], "$arch without initrd is not selected");
    write_text("$root/xcat/genesis.fs.$arch.gz", 'initrd');
    selection($arch, ["genesis.kernel.$arch", "genesis.fs.$arch.gz"], "$arch selects its exact files");
    link("$root/xcat/genesis.fs.$arch.gz", "$root/xcat/genesis.fs.$arch.lzma") or die $!;
    selection($arch, ["genesis.kernel.$arch", "genesis.fs.$arch.lzma"], "$arch prefers LZMA on equal ctime");
}
write_text("$root/xcat/genesis.kernel.x86_64-extra", 'kernel');
write_text("$root/xcat/genesis.fs.x86_64-extra.gz", 'initrd');
for my $arch (undef, '', '../x86_64', "x86_64\n", 'ppc64el', 'x86_64-extra') {
    selection($arch, [], 'no fallback or partial architecture match');
}

unlink "$root/xcat/genesis.fs.x86_64.gz" or die $!;
sleep 1;
write_text("$root/xcat/genesis.fs.x86_64.gz", 'new gzip');
selection('x86_64', ['genesis.kernel.x86_64', 'genesis.fs.x86_64.gz'], 'newer gzip wins');
sleep 1;
write_text("$root/xcat/genesis.fs.x86_64.lzma", 'new lzma');
selection('x86_64', ['genesis.kernel.x86_64', 'genesis.fs.x86_64.lzma'], 'newer LZMA wins');

SKIP: {
    skip 'root can read mode-000 files', 6 if $< == 0;
    chmod 0000, "$root/xcat/genesis.fs.x86_64.lzma" or die $!;
    selection('x86_64', ['genesis.kernel.x86_64', 'genesis.fs.x86_64.gz'], 'unreadable LZMA is ignored');
    chmod 0000, "$root/xcat/genesis.fs.x86_64.gz" or die $!;
    selection('x86_64', [], 'unreadable initrds yield no partial selection');
    chmod 0644, "$root/xcat/genesis.fs.x86_64.gz" or die $!;
    chmod 0000, "$root/xcat/genesis.kernel.x86_64" or die $!;
    selection('x86_64', [], 'unreadable kernel yields no selection');
}

done_testing();
