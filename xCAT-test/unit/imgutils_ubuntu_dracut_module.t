#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(realpath);
use File::Path qw(make_path);
use File::Slurper qw(read_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

use imgutils;

my $tmp    = realpath(tempdir(CLEANUP => 1));
my $srcdir = realpath("$FindBin::Bin/../../xCAT-server/share/xcat/netboot/ubuntu/dracut");

# Returns the files that the install script $install gives to inst_hook, relative to its module.
# dracut stops the build with "Cannot install a hook ... that does not exist" when one is absent.
sub hook_files {
    my ($install) = @_;
    return map { m{inst_hook\s+\S+\s+\d+\s+"\$moddir/([^"]+)"} ? $1 : () } split(/\n/, read_text($install));
}

foreach my $mode (qw(stateless statelite)) {
    my $moduledir = "$tmp/$mode/97xcat";
    make_path($moduledir);
    my @staged = imgutils::stage_dracut_module($srcdir, $moduledir, $mode);
    ok(-f "$moduledir/install", "the $mode module gets its install script");
    ok(-x "$moduledir/check", "the $mode module gets an executable check script");
    is_deeply([sort @staged], [sort map { -e "$moduledir/$_" ? $_ : () } @staged], "every file the $mode module reports is in the module");

    my @hooks = hook_files("$moduledir/install");
    ok(scalar(@hooks), "the $mode install script installs a hook");
    foreach my $hook (@hooks) {
        ok(-f "$moduledir/$hook", "the $mode module carries $hook, which its install script hooks in");
    }
}

my $stateless = "$tmp/stateless/97xcat";
ok(-x "$stateless/xcat-online.sh", 'the stateless module carries the executable online hook that fetches the root');
ok(-x "$stateless/xcatroot", 'the stateless module carries xcatroot');

eval { imgutils::stage_dracut_module($srcdir, "$tmp/bad", 'diskful') };
like($@, qr/the mode diskful is not supported/, 'an unknown mode is refused');

eval { imgutils::stage_dracut_module($srcdir, "$tmp/no-such-dir", 'stateless') };
like($@, qr{cannot copy \Q$srcdir\E/check to \Q$tmp\E/no-such-dir/check}, 'a failed copy stops genimage');

done_testing();
