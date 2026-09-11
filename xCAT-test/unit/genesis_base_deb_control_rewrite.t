#!/usr/bin/env perl
# builddeb-genesis-base builds the Genesis base deb natively on Ubuntu. It writes the target
# architecture into debian/control, which is held in the amd64 form in the tree. 2.19 renames
# the ppc64 debs to ppc64el, so the ppc control must also name the deb it supersedes: without
# the relation dpkg keeps xcat-genesis-base-ppc64 installed beside the new package, and that
# old package owns the same files under /opt/xcat/share/xcat/netboot/genesis.
#
# The script needs dracut and root, so rewrite_control() is lifted out of it and run alone
# against the control file the tree ships.
use strict;
use warnings;

use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

my $script  = repo_path('xCAT-genesis-builder/builddeb-genesis-base');
my $control = repo_path('xCAT-genesis-builder/debian/control');
plan skip_all => 'builddeb-genesis-base not found' unless -f $script;
plan tests => 8;

my $text = slurp_repo_file('xCAT-genesis-builder/builddeb-genesis-base');
my ($function) = $text =~ /^(rewrite_control\(\)\s*\{.*?^\})/ms;
BAIL_OUT('rewrite_control() no longer matches in builddeb-genesis-base')
  unless defined $function;

my $tmpdir = tempdir(CLEANUP => 1);

# What the ppc64el package has to take over from, and what amd64 already took over from.
my %superseded = (
    'amd64'   => 'xcat-genesis-amd64',
    'ppc64el' => 'xcat-genesis-ppc64, xcat-genesis-base-ppc64',
);

for my $arch (sort keys %superseded) {
    my $out = rewrite($arch);

    like($out, qr/^Package:\s*xcat-genesis-base-\Q$arch\E$/m,
        "$arch control names the package xcat-genesis-base-$arch");
    like($out, qr/^Replaces:\s*\Q$superseded{$arch}\E\s*$/m,
        "$arch control replaces $superseded{$arch}");
    like($out, qr/^Breaks:\s*\Q$superseded{$arch}\E\b/m,
        "$arch control breaks $superseded{$arch}");
    like($out, qr/^Breaks:.*\bxcat-genesis-scripts-\Q$arch\E \(<< 2\.13\.10\)/m,
        "$arch control breaks the genesis scripts of its own architecture");
}

#---
# rewrite: run the lifted rewrite_control() over a copy of the control file in the tree.
#---
sub rewrite {
    my ($arch) = @_;
    my $copy = "$tmpdir/control.$arch";
    write_text($copy, read_text($control));
    my $driver = "$tmpdir/driver.$arch.sh";
    write_text($driver, "#!/bin/bash\nset -eu\n$function\nrewrite_control \"\$1\" \"\$2\"\n");
    system('bash', $driver, $copy, $arch) == 0
      or BAIL_OUT("rewrite_control failed for $arch");
    return read_text($copy);
}
