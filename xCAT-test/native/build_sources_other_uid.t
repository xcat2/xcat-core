#!/usr/bin/env perl
# mock reads the staged sources as the uid of the target's chrootuid while buildrpms.pl
# runs as root. A process with another uid must read them. CI runs this file as root.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../build-utils/lib";
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use POSIX ();
use Test::More;
use XCAT::BuildUtils qw(build_sources_base prepare_build_sources_dir share_build_sources_dir);

plan skip_all => 'requires root to switch to another uid' if $> != 0;

# Flush before the fork below, or the child repeats this file's TAP output on exit.
$| = 1;

my $checkout = tempdir(CLEANUP => 1);
chmod 0755, $checkout or die "chmod $checkout: $!\n";
# A root $HOME the build uid cannot enter, as on the build hosts.
make_path("$checkout/root");
chmod 0550, "$checkout/root" or die "chmod: $!\n";
local $ENV{HOME} = "$checkout/root";

my $umask = umask 077;
my $dir = prepare_build_sources_dir(build_sources_base($checkout), $$, 'hosta');
make_path("$dir/sub");
write_text("$dir/xCAT-2.20.0.tar.gz", "payload\n");
write_text("$dir/sub/xcat.conf", "conf\n");
share_build_sources_dir($dir);
umask $umask;

my $pid = fork // die "fork: $!\n";
if ($pid == 0) {
    POSIX::setgid(1000);
    POSIX::setuid(1000);
    POSIX::_exit(2) if $> != 1000;
    my $ok = eval {
        opendir(my $dh, $dir) or die;
        read_text("$dir/xCAT-2.20.0.tar.gz") eq "payload\n"
            && read_text("$dir/sub/xcat.conf") eq "conf\n";
    };
    POSIX::_exit($ok ? 0 : 1);
}
waitpid($pid, 0);
is($? >> 8, 0, 'uid 1000 lists the staging directory and reads every staged file');

done_testing;
