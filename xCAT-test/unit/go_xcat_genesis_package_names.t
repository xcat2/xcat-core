#!/usr/bin/env perl
# go-xcat installs and uninstalls a fixed list of package names, and it keeps one list per
# packaging format. The Genesis packages are named after the architecture, and the two formats
# spell that architecture differently: the rpm is xCAT-genesis-scripts-ppc64, the deb is
# xcat-genesis-scripts-ppc64el. A name that no repository publishes makes apt fail the whole
# transaction, so one stale entry stops "go-xcat install" and "go-xcat uninstall" on that
# architecture.
#
# The lists are built by go-xcat itself here, not read as text: the deb list exists only when
# "type dpkg" succeeds, so a shell function decides which branch each run takes.
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $root    = "$FindBin::Bin/../..";
my $go_xcat = "$root/xCAT-server/share/xcat/tools/go-xcat";
BAIL_OUT("go-xcat not found at $go_xcat") unless -f $go_xcat;

my $tmpdir = tempdir(CLEANUP => 1);
my $driver = "$tmpdir/driver.sh";
open(my $driver_fh, '>', $driver) or die "open $driver: $!";
print {$driver_fh} <<'DRIVER';
#!/bin/bash

if [[ ${WANT_DPKG:-0} == 1 ]]
then
    dpkg() { :; }
fi

list_body=$(
    awk '
        /^GO_XCAT_INSTALL_LIST=\(/ { copy = 1 }
        /^PATH=/ { exit }
        copy { print }
    ' "$GO_XCAT_SOURCE"
)
[[ -n "${list_body}" ]] || { echo "go-xcat package arrays not found" >&2 ; exit 3 ; }

# A real dpkg on the build host would select the deb branch on every run.
PATH=""
eval "${list_body}"

printf 'install %s\n' "${GO_XCAT_INSTALL_LIST[*]}"
printf 'uninstall %s\n' "${GO_XCAT_UNINSTALL_LIST[*]}"
DRIVER
close($driver_fh) or die "close $driver: $!";

# Run go-xcat's array definitions and return the two lists it built.
sub package_lists {
    my ($want_dpkg) = @_;
    local %ENV = (%ENV, GO_XCAT_SOURCE => $go_xcat, WANT_DPKG => $want_dpkg);
    open(my $out, '-|', 'bash', $driver) or die "run $driver: $!";
    my %list;
    while (my $line = <$out>) {
        chomp $line;
        my ($which, $packages) = split /\s+/, $line, 2;
        $list{$which} = [ split /\s+/, ($packages // '') ];
    }
    close($out);
    BAIL_OUT('go-xcat package arrays could not be evaluated')
      unless $list{install} && $list{uninstall};
    return \%list;
}

# Read the whole of a file.
sub slurp {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "read $path: $!";
    local $/; my $text = <$fh>; close $fh;
    return $text;
}

# The package names, sorted, that match a prefix.
sub named {
    my ($packages, $prefix) = @_;
    my @found = sort grep { index($_, $prefix) == 0 } @{$packages};
    return \@found;
}

my $rpm = package_lists(0);
my $deb = package_lists(1);
BAIL_OUT('the dpkg branch of go-xcat was not taken')
  unless grep { $_ eq 'xcat-client' } @{ $deb->{install} };
BAIL_OUT('the rpm branch of go-xcat was not taken')
  unless grep { $_ eq 'xCAT-client' } @{ $rpm->{install} };

# The deb names come from the packaging: one control file per Debian architecture names the
# genesis-scripts package, and its Depends names the genesis-base package that carries the
# Genesis tree for that same architecture.
my @control = sort glob("$root/xCAT-genesis-scripts/debian/control-*");
BAIL_OUT('no xCAT-genesis-scripts Debian control files') unless @control;
my (@deb_scripts, @deb_base);
for my $control (@control) {
    my $text = slurp($control);
    push @deb_scripts, ($text =~ /^Package:\s*(\S+)/mg);
    push @deb_base, ($text =~ /^Depends:.*?(xcat-genesis-base-[a-z0-9]+)/mg);
}
@deb_scripts = sort @deb_scripts;
@deb_base    = sort @deb_base;

for my $which (qw(install uninstall)) {
    is_deeply(named($deb->{$which}, 'xcat-genesis-scripts-'), \@deb_scripts,
        "the deb $which list names the genesis scripts packages xCAT-genesis-scripts builds");
    is_deeply(named($deb->{$which}, 'xcat-genesis-base-'), \@deb_base,
        "the deb $which list names the genesis base packages those scripts depend on");
}

# The rpm names use the Genesis target architecture of the spec, which is not a Debian
# architecture name.
my %tarch = map { $_ => 1 } (slurp("$root/xCAT-genesis-builder/xCAT-genesis-base.spec")
      =~ /^%define\s+tarch\s+(\S+)/mg);
BAIL_OUT('no Genesis target architectures in xCAT-genesis-base.spec') unless %tarch;

for my $which (qw(install uninstall)) {
    for my $prefix (qw(xCAT-genesis-scripts- xCAT-genesis-base-)) {
        my @wrong = grep { my $arch = substr($_, length $prefix); !$tarch{$arch} }
          @{ named($rpm->{$which}, $prefix) };
        is_deeply(\@wrong, [],
            "the rpm $which list names only Genesis target architectures for $prefix*");
    }
}

done_testing();
