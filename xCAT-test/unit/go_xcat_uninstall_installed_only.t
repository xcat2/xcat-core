#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# `go-xcat uninstall` hands GO_XCAT_UNINSTALL_LIST to the package manager. That list names
# packages xCAT stopped producing -- xCAT-genesis-builder, yaboot-xcat, conserver-xcat -- so
# most of it is not installed on any one node. apt answers "Unable to locate package" for a
# name it does not know, and go-xcat prints a warning for each; dnf answers "No match for
# argument" and fails the whole call when nothing in the list matches.
#
# So what is not installed does not reach the package manager. That is also what makes keeping
# a retired name in the list free, which is why the list outlives the build.
#
# go-xcat is sourced and asked about the host's own package database. bash is installed on
# every build host, and the xcat-test-absent-* names are installed on none.

my $go_xcat = "$FindBin::Bin/../../xCAT-server/share/xcat/tools/go-xcat";
plan skip_all => 'go-xcat not found' unless -r $go_xcat;

# Run a bash snippet after go-xcat is sourced, and return its output lines.
sub go_xcat {
    my ($snippet) = @_;
    my @lines = `bash -c 'source "\$1" && eval "\$2"' go-xcat '$go_xcat' '$snippet'`;
    chomp @lines;
    return \@lines;
}

is_deeply(go_xcat('installed_packages xcat-test-absent-1 bash xcat-test-absent-2'), ['bash'],
    'only the installed packages are reported');

is_deeply(go_xcat('installed_packages xcat-test-absent-1 xcat-test-absent-2'), [],
    'a list with nothing installed reports nothing');

# remove_package is replaced so the test removes nothing from the host.
is_deeply(go_xcat('remove_package() { printf "remove %s\n" "$@"; }
    GO_XCAT_UNINSTALL_LIST=(xCAT-genesis-builder xcat-test-absent-1 bash)
    uninstall_xcat -y'), ['remove -y', 'remove bash'],
    'only the installed packages reach the package manager');

is_deeply(go_xcat('remove_package() { printf "remove %s\n" "$@"; }
    GO_XCAT_UNINSTALL_LIST=(xCAT-genesis-builder xcat-test-absent-1)
    uninstall_xcat -y; echo "uninstall_xcat returns $?"'), ['uninstall_xcat returns 0'],
    'a node with none of them installed hands the package manager nothing, and succeeds');

done_testing();
