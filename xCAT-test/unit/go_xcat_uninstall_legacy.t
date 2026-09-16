#!/usr/bin/env perl
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# `go-xcat uninstall` removes what go-xcat could have installed, plus the packages xCAT used to
# ship. A name dropped from that list is a package left behind on every management node that
# still has it: nothing else asks the package manager to remove it, and the operator is not
# told. So the list outlives the build that produced each package.
#
# The two assignments are evaluated rather than read, with `type` shadowed so the rpm branch
# stands, and the names asserted are the ones go-xcat would hand to the package manager.

my $go_xcat = "$FindBin::Bin/../../xCAT-server/share/xcat/tools/go-xcat";
plan skip_all => 'go-xcat not found' unless -r $go_xcat;
plan tests => 3;

my @uninstall = uninstall_list($go_xcat);

# xCAT-genesis-builder was built until 2.19 and is installed on existing management nodes.
ok(scalar(grep { $_ eq 'xCAT-genesis-builder' } @uninstall),
   'go-xcat uninstall still removes xCAT-genesis-builder');

# Two neighbours, so a list that evaluated to nothing cannot pass the assertion above.
ok(scalar(grep { $_ eq 'xCAT-genesis-openembedded-x86_64' } @uninstall),
   'go-xcat uninstall removes the OpenEmbedded Genesis packages');
ok(scalar(grep { $_ eq 'xCAT-server' } @uninstall),
   'go-xcat uninstall removes what it installs');

# Evaluate both assignments: the uninstall list is built from the install one, and the Debian
# reassignment below it is guarded by `type dpkg`, which is shadowed away.
sub uninstall_list {
    my ($path) = @_;
    my $dir = tempdir(CLEANUP => 1);
    my $driver = "$dir/driver.sh";
    open my $fh, '>', $driver or die "$driver: $!";
    print {$fh} <<'BASH';
set -u
type() { return 1; }
eval "$(awk '/^GO_XCAT_INSTALL_LIST=\(/ { copy = 1 } copy { print } copy && /^$/ { exit }' "$GO_XCAT_SOURCE")"
printf '%s\n' "${GO_XCAT_UNINSTALL_LIST[@]}"
BASH
    close $fh;
    local $ENV{GO_XCAT_SOURCE} = $path;
    my @out = qx{bash '$driver' 2>/dev/null};
    chomp @out;
    my @names = grep { length } @out;
    BAIL_OUT("no package list read from $path") unless @names;
    return @names;
}
