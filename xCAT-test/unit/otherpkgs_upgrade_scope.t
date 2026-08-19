#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $script_path = File::Spec->catfile( $repo_root, 'xCAT/postscripts/otherpkgs' );

plan skip_all => "$script_path not found" unless -r $script_path;

open( my $fh, '<', $script_path ) or die "Unable to read $script_path: $!";
my $script = do { local $/; <$fh> };
close($fh);

# The postscript writes its repositories as [xcat-otherpkgs<index>]. The upgrade
# below is scoped with --enablerepo=xcat-otherpkgs*, so the two have to agree or
# the upgrade silently matches no repository at all.
like(
    $script,
    qr/echo\s+"\[xcat-otherpkgs\$urlrepoindex\]"/,
    'remote repositories are still defined as xcat-otherpkgs<index>'
);
like(
    $script,
    qr/echo\s+"\[xcat-otherpkgs\$localrepoindex\]"/,
    'local repositories are still defined as xcat-otherpkgs<index>'
);

# Both the verbose echo and the command actually executed must carry the same
# scoping, otherwise verbose output reports a command that was never run.
my @scoped = $script =~ /\$yumcmd\s+-y\s+--disablerepo=\*\s+--enablerepo=xcat-otherpkgs\*\s+upgrade/g;
is(
    scalar(@scoped),
    2,
    'the yum/dnf upgrade is scoped to the xcat-otherpkgs repositories in both the verbose echo and the executed command'
);

# Counted rather than matched with unlike(), so that a failure reports the count
# instead of dumping the whole postscript into the test output.
my @unscoped = $script =~ /(\$yumcmd\s+-y\s+upgrade)/g;
is(
    scalar(@unscoped),
    0,
    'no unscoped yum/dnf upgrade remains, which would also apply unrelated distribution updates'
);

# The install path must keep every repository enabled so that dependencies of
# the otherpkgs packages can still be resolved from the distribution.
like(
    $script,
    qr/\$yumcmd\s+-y\s+install\s+\$repo_pkgs/,
    'the package install path is left unscoped so dependencies still resolve'
);

done_testing();
