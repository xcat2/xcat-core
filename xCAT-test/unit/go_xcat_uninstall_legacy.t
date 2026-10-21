#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# `go-xcat uninstall` removes what go-xcat could have installed, plus the packages xCAT used to
# ship. A name dropped from that list is a package left behind on every management node that
# still has it: nothing else asks the package manager to remove it, and the operator is not
# told. So the list outlives the build that produced each package.
#
# go-xcat is sourced, so the list is the one the script builds. `type dpkg` fails, so the rpm
# list is read on any build host.

my $go_xcat = "$FindBin::Bin/../../xCAT-server/share/xcat/tools/go-xcat";
plan skip_all => 'go-xcat not found' unless -r $go_xcat;

my @uninstall = `bash -c 'type() { [[ \$1 == dpkg ]] && return 1; builtin type "\$@"; }
    source "\$1" && printf "%s\\n" "\${GO_XCAT_UNINSTALL_LIST[\@]}"' go-xcat '$go_xcat'`;
is($?, 0, 'go-xcat sources');
chomp @uninstall;
my %uninstall = map { $_ => 1 } @uninstall;

# xCAT-genesis-builder was built until 2.19 and is installed on existing management nodes.
ok($uninstall{'xCAT-genesis-builder'}, 'go-xcat uninstall still removes xCAT-genesis-builder');

# Two neighbours, so a list that evaluated to nothing cannot pass the assertion above.
ok($uninstall{'xCAT-genesis-openembedded-x86_64'},
    'go-xcat uninstall removes the OpenEmbedded Genesis packages');
ok($uninstall{'xCAT-server'}, 'go-xcat uninstall removes what it installs');

done_testing();
