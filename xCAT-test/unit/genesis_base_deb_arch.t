#!/usr/bin/env perl
# debuild-xcat-genesis-base converts the EL Genesis base rpm to a deb. The rpm name carries the
# Genesis target architecture, and the deb must carry the Debian architecture: ppc64 becomes
# ppc64el, x86_64 becomes amd64. An unmapped architecture leaves the deb named after the rpm and
# makes it break a genesis-scripts package that no repository publishes.
#
# The script is driven here with alien and dpkg-buildpackage shadowed by shell functions.
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $root   = "$FindBin::Bin/../..";
my $script = "$root/xCAT-genesis-builder/debuild-xcat-genesis-base";
BAIL_OUT("debuild-xcat-genesis-base not found at $script") unless -f $script;

my $tmpdir = tempdir(CLEANUP => 1);
my $driver = "$tmpdir/driver.sh";
open(my $driver_fh, '>', $driver) or die "open $driver: $!";
print {$driver_fh} <<'DRIVER';
#!/bin/bash

# alien names the deb after the rpm: lower case, and "_" written as "-".
alien() {
    local rpm="${!#}"
    local name="${rpm##*/}"
    name="${name%.rpm}"
    local dir="${name%%-snap*}"
    local package="${dir%-*}"
    package="${package,,}"
    package="${package//_/-}"

    mkdir -p "${dir}/debian"
    cat >"${dir}/debian/control" <<CONTROL
Source: ${package}
Section: alien
Priority: extra
Maintainer: xCAT <xcat-user@lists.sourceforge.net>

Package: ${package}
Architecture: all
Description: xCAT genesis base
CONTROL
    printf '%s (%s) unstable; urgency=low\n' "${package}" "1.0" \
        >"${dir}/debian/changelog"
    printf '#!/usr/bin/make -f\nbinary:\n\t@true\n' >"${dir}/debian/rules"
    chmod 0755 "${dir}/debian/rules"
}

cd "${WORK_DIR}" || exit 1
: >"${RPM_NAME}"
source "${SCRIPT}" "${RPM_NAME}" >/dev/null 2>&1
DRIVER
close($driver_fh) or die "close $driver: $!";

# Convert one rpm name and return the produced source directory and its control file.
sub convert {
    my ($name, $rpm) = @_;
    my $work = "$tmpdir/$name";
    mkdir $work or die "mkdir $work: $!";
    local %ENV = (%ENV, SCRIPT => $script, WORK_DIR => $work, RPM_NAME => $rpm);
    system('bash', $driver) == 0 or return (undef, '');
    my ($dir) = grep { -d $_ } glob("$work/*");
    return (undef, '') unless defined $dir && -f "$dir/debian/control";
    open(my $fh, '<', "$dir/debian/control") or die "read $dir/debian/control: $!";
    local $/; my $control = <$fh>; close $fh;
    $dir =~ s{^\Q$work\E/}{};
    return ($dir, $control);
}

my %expected = (
    'xCAT-genesis-base-x86_64-2.13.10-snap202601010000.noarch.rpm' => 'amd64',
    'xCAT-genesis-base-ppc64-2.13.10-snap202601010000.noarch.rpm'  => 'ppc64el',
);

for my $rpm (sort keys %expected) {
    my $arch = $expected{$rpm};
    my ($dir, $control) = convert($arch, $rpm);
    BAIL_OUT("debuild-xcat-genesis-base produced no source tree for $rpm")
      unless defined $dir;

    like($dir, qr/\Q-$arch-\E/, "$rpm builds in a $arch source tree");
    like($control, qr/^Package:\s*xcat-genesis-base-\Q$arch\E$/m,
        "$rpm builds the package xcat-genesis-base-$arch");
    like($control, qr/^Breaks:\s*xcat-genesis-scripts-\Q$arch\E\b/m,
        "xcat-genesis-base-$arch breaks the genesis scripts of its own architecture");
}

done_testing();
