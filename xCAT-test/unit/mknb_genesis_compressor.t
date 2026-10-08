#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use File::Slurper qw(read_binary write_text);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $root = tempdir(CLEANUP => 1);
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "$root/config";
make_path($ENV{XCATCFG});
require(repo_path('xCAT-server/lib/xcat/plugins/mknb.pm'));

# xz supports the lzma invocation name even where the distribution omits that link.
symlink('/usr/bin/xz', "$root/lzma") or die "create lzma alias: $!";
local $ENV{PATH} = "$root:$ENV{PATH}";

write_text("$root/payload", "Genesis payload\n");
is(system("cd '$root' && printf 'payload\\n' | cpio -o -H newc > archive.cpio"), 0,
    'builds an actual newc archive');
my $archive = read_binary("$root/archive.cpio");
like($archive, qr/^070701/, 'fixture is a newc archive');

for my $case ([1, 1, 'lzma'], [1, 0, 'lzma'], [0, 1, 'xz']) {
    my ($lzma, $xz, $name) = @$case;
    subtest "$name with lzma=$lzma xz=$xz" => sub {
        my $command = xCAT_plugin::mknb::genesis_lzma_command($lzma, $xz);
        like($command, qr/^\Q$name\E /, 'selects the available compressor');
        is(system("$command < '$root/archive.cpio' > '$root/archive.lzma'"), 0,
            'selected command compresses the archive');
        is(system("xz --format=lzma -dc '$root/archive.lzma' > '$root/decoded.cpio'"), 0,
            'output has the promised LZMA container');
        is(read_binary("$root/decoded.cpio"), $archive, 'decompression preserves every archive byte');
    };
}
is(xCAT_plugin::mknb::genesis_lzma_command(0, 0), undef,
    'no LZMA command is selected when neither compressor is available');

done_testing();
