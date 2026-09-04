#!/usr/bin/env perl
# xCAT and xCATsn name their Debian architectures explicitly. An architecture missing from that
# list is not a build failure -- it is a package that never exists: apt on that architecture says
#
#   E: Unable to locate package xcat
#
# and the management node cannot be installed at all. riscv64 was missing while the rest of the
# tree already carried riscv64 install templates, DHCP boot policy and a Genesis machine config.
#
# The list is compared against the architectures the DEB build itself supports, taken from
# build-utils/lib/XCAT/BuildUtils or, failing that, the documented set.
use strict;
use warnings;

use FindBin;
use Test::More;

my $root = "$FindBin::Bin/../..";

# The Debian architectures xCAT ships. dpkg names, not rpm ones.
my @arches = qw(amd64 ppc64el riscv64);

my @controls = grep { -f } ("$root/xCAT/debian/control", "$root/xCATsn/debian/control");
plan skip_all => 'no Debian control files in this tree' unless @controls;

for my $ctl (@controls) {
    open my $fh, '<', $ctl or die "read $ctl: $!";
    local $/; my $text = <$fh>; close $fh;
    (my $short = $ctl) =~ s{^\Q$root\E/}{};
    my @lines = ($text =~ /^Architecture:\s*(.+)$/mg);
    my @explicit = grep { !/^(?:any|all)$/ } map { s/^\s+|\s+$//gr } @lines;
    ok(scalar(@explicit), "$short names architectures explicitly") or next;
    for my $line (@explicit) {
        my %have = map { $_ => 1 } split /\s+/, $line;
        my @missing = grep { !$have{$_} } @arches;
        is_deeply(\@missing, [], "$short covers @arches");
    }
}

# The genesis dependency must follow the architecture. xCAT and xCATsn are built once per
# architecture from one control file, so an unrestricted "Depends: xcat-genesis-scripts-amd64"
# reaches the ppc64el and riscv64 debs too. That package is Architecture: all, so it installs and
# apt reports no error -- it lays down the x86_64 Genesis tree and pulls the 128 MB amd64
# genesis-base, and the management node gets no Genesis for its own architecture. The rpm side
# already selects per architecture through %{?genesistarch:Requires: xCAT-genesis-scripts-...}.
#
# xCAT-genesis-scripts keeps one control file per Debian architecture, and the file name is the
# Debian architecture. Its package name and its genesis-base dependency must carry that same
# architecture: xcat-genesis-base-ppc64 is a name no repository publishes, while the base deb
# that builddeb-genesis-base builds for ppc64el is xcat-genesis-base-ppc64el.

# Return the folded value of a control field, or undef.
sub control_field {
    my ($text, $name) = @_;
    return $1 if $text =~ /^\Q$name\E:[ \t]*(.*(?:\n[ \t]+.*)*)/m;
    return;
}

# Split a dependency field into [package name, architecture restriction] pairs. Alternatives
# separated by "|" are returned one by one, because a restriction binds to one alternative.
sub dependency_terms {
    my ($field) = @_;
    my @terms;
    return @terms unless defined $field;
    $field =~ s/\n/ /g;
    for my $dep (split /,/, $field) {
        for my $alt (split /\|/, $dep) {
            next unless $alt =~ /^\s*([A-Za-z0-9][A-Za-z0-9+.-]*)\s*(?:\([^)]*\))?\s*(?:\[([^\]]*)\])?/;
            push @terms, [ $1, $2 ];
        }
    }
    return @terms;
}

# dpkg-gencontrol drops a dependency whose architecture restriction excludes the build
# architecture. No restriction means the dependency reaches every architecture.
sub term_applies {
    my ($restriction, $arch) = @_;
    return 1 unless defined $restriction;
    my @tokens = grep { length } split /\s+/, $restriction;
    return 1 unless @tokens;
    my $negated = ($tokens[0] =~ /^!/) ? 1 : 0;
    my %named = map { my $t = $_; $t =~ s/^!//; $t =~ s/^any-//; ($t => 1) } @tokens;
    return $negated ? (exists $named{$arch} ? 0 : 1) : (exists $named{$arch} ? 1 : 0);
}

# The architectures xCAT-genesis-scripts is packaged for, taken from its per-architecture control
# files. riscv64 has none on purpose: its Genesis is the OpenEmbedded image.
my $scripts_debian = "$root/xCAT-genesis-scripts/debian";
my @scripts_arches = sort map { m{/control-(.+)$} ? $1 : () } glob("$scripts_debian/control-*");

SKIP: {
    skip 'xCAT-genesis-scripts has no per-architecture control files', 1 unless @scripts_arches;

    for my $arch (@scripts_arches) {
        my $ctl = "$scripts_debian/control-$arch";
        open my $fh, '<', $ctl or die "read $ctl: $!";
        local $/; my $text = <$fh>; close $fh;

        my ($package) = ($text =~ /^Package:\s*(\S+)/m);
        is($package, "xcat-genesis-scripts-$arch",
            "control-$arch builds xcat-genesis-scripts-$arch");

        my @bases = grep { /^xcat-genesis-base-/ }
          map { $_->[0] } dependency_terms(control_field($text, 'Depends'));
        is_deeply(\@bases, ["xcat-genesis-base-$arch"],
            "xcat-genesis-scripts-$arch depends on xcat-genesis-base-$arch");
    }

    for my $ctl (@controls) {
        open my $fh, '<', $ctl or die "read $ctl: $!";
        local $/; my $text = <$fh>; close $fh;
        (my $short = $ctl) =~ s{^\Q$root\E/}{};

        my ($arch_line) = ($text =~ /^Architecture:\s*(.+)$/m);
        next unless defined $arch_line;
        my @built = grep { !/^(?:any|all)$/ } split /\s+/, $arch_line;

        my @genesis = grep { $_->[0] =~ /^xcat-genesis-scripts-/ }
          dependency_terms(control_field($text, 'Depends'));

        for my $arch (@built) {
            my @reaching = map { $_->[0] }
              grep { term_applies($_->[1], $arch) } @genesis;
            my @foreign = grep { $_ ne "xcat-genesis-scripts-$arch" } @reaching;
            is_deeply(\@foreign, [],
                "$short on $arch depends on no other architecture's genesis scripts");

            my %packaged = map { $_ => 1 } @scripts_arches;
            next unless $packaged{$arch};
            ok(scalar(grep { $_ eq "xcat-genesis-scripts-$arch" } @reaching),
                "$short on $arch depends on xcat-genesis-scripts-$arch");
        }
    }
}


done_testing();
