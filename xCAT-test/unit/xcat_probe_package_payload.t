#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(slurp_repo_file);

my $control = slurp_repo_file('xCAT-probe/debian/control');
my ($probe) = $control =~ /^Package: xcat-probe\n(.*?)(?:\n\n|\z)/ms;
like($probe // '', qr/^Depends:.*\biproute2\s*\|\s*net-tools\b/m,
    'Debian probe keeps the socket-tool alternatives');

# The rpm created subcmds/bin in %post, so the directory belonged to no package
# and took the context of its parent, usr_t, instead of the bin_t the policy
# gives /opt/.*/bin. Nothing relabels it afterwards, and xcatprobe drops a
# switchprobe symlink in it at run time. The Debian package already owns the
# directory through debian/dirs.
my $spec = slurp_repo_file('xCAT-probe/xCAT-probe.spec');
my ($install) = $spec =~ /^%install\n(.*?)^%\w+/ms;
like($install // '', qr{^mkdir -p \$RPM_BUILD_ROOT/%\{prefix\}/probe/subcmds/bin\b}m,
    '%install creates subcmds/bin, so rpm owns it and labels it from the policy');
my ($post) = $spec =~ /^%post\n(.*?)(?:^%\w+|\z)/ms;
unlike($post // '', qr{mkdir -p .*probe/subcmds/bin},
    '... and %post no longer creates it behind rpm');
my $dirs = slurp_repo_file('xCAT-probe/debian/dirs');
like($dirs, qr{^opt/xcat/probe/subcmds/bin$}m, 'the Debian package still owns it too');

done_testing();
