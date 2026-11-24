#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use Test::More;
use imgutils;

my $tmp = tempdir(CLEANUP => 1);
my $module = "$tmp/module";
make_path($module);
my $name = 'xcat-rootimg-checksum.sh';
my $source = "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils/$name";
my $copy = "$module/$name";

imgutils::stage_rootimg_helpers($module, 1);
is(scalar(read_binary($copy)), scalar(read_binary($source)), 'checksum-only images receive the helper');
is((stat($copy))[2] & oct('7777'), oct('644'), 'the sourced helper is readable but not executable');
my $installer = "$module/xcat-rootimg-install.sh";
is(scalar(read_binary($installer)),
    scalar(read_binary("$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils/xcat-rootimg-install.sh")),
    'the build helper is staged independently of UFTP eligibility');
is((stat($installer))[2] & oct('7777'), oct('644'), 'the build helper is readable but not executable');
write_binary($copy, 'old helper');
chmod(oct('777'), $copy) or die $!;
imgutils::stage_rootimg_helpers($module, 1);
is(scalar(read_binary($copy)), scalar(read_binary($source)), 'a repeated build replaces the old helper');
is((stat($copy))[2] & oct('7777'), oct('644'), 'a repeated build restores the helper mode');

imgutils::stage_rootimg_helpers($module, 0);
ok(!-e $copy, 'disabled staging removes the previous checksum helper');
ok(!-e $installer, 'a disabled build removes the previous installation helper');
symlink("$tmp/missing", $copy) or die $!;
imgutils::stage_rootimg_helpers($module, 0);
ok(!-l $copy, 'a disabled build removes a dangling helper link');
write_binary("$tmp/other", 'other file');
symlink("$tmp/other", $copy) or die $!;
imgutils::stage_rootimg_helpers($module, 1);
is(scalar(read_binary("$tmp/other")), 'other file', 'staging replaces a link without modifying its target');
ok(!-l $copy, 'the module gets its own helper file');

eval { imgutils::stage_rootimg_helpers("$tmp/absent/module", 1) };
like($@, qr{cannot copy .*\Q$name\E to \Q$tmp/absent/module/$name\E}, 'a failed copy stops the build');
unlink($copy) or die $!;
make_path("$copy/child");
eval { imgutils::stage_rootimg_helpers($module, 0) };
like($@, qr{cannot remove \Q$copy\E}, 'a failed removal stops the build');
done_testing();
