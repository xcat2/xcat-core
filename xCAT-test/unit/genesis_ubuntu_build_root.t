#!/usr/bin/env perl
# The Ubuntu Genesis build root must carry every command the Ubuntu dracut module marks
# mandatory. dracut_install reports a missing command and returns 0, so a hole in the image
# does not fail the build.
#
# The mandatory list comes from RUNNING the module: module-setup.sh is sourced with
# dracut_install shadowed, _dracut_install_opt neutralised, and install() called. The
# package list comes from evaluating the REQUIRED_PACKAGES assignment in the build script.
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $builder = repo_path('xCAT-genesis-builder/builddeb-genesis-base');
my $module  = repo_path('xCAT-genesis-builder/dracut_105/ubuntu/module-setup.sh');
plan skip_all => 'builddeb-genesis-base not found' unless -f $builder;
plan skip_all => 'ubuntu module-setup.sh not found' unless -f $module;
plan tests => 9;

# Mandatory commands a minimal Ubuntu server root does NOT already provide, and the packages
# that supply each one. hwclock has two names: it left util-linux for util-linux-extra in
# 23.04, and the build root asks apt which name this release carries.
my %PACKAGES_FOR = (
    dhclient  => ['isc-dhcp-client'],
    ifenslave => ['ifenslave'],
    hwclock   => [ 'util-linux-extra', 'util-linux' ],
);

my %mandatory = map { $_ => 1 } mandatory_commands($module);
my @packages  = required_packages($builder);

for my $command (sort keys %PACKAGES_FOR) {
    my @provider = @{ $PACKAGES_FOR{$command} };
    ok($mandatory{$command}, "the Ubuntu dracut module installs '$command' unconditionally");
    my @named = grep { my $p = $_; grep { $_ eq $p } @packages } @provider;
    ok(scalar @named,
       "the build root installs @{[ join ' or ', @provider ]}, which provides '$command'");
}

# doxcat asks dhclient for the provisioning lease.
ok($mandatory{dhclient} && scalar(grep { $_ eq 'isc-dhcp-client' } @packages),
   'the Genesis image can obtain a DHCP lease');

# dracut_install is silent about a missing command, so the payload needs its own gate.
# xCAT-genesis-base.spec runs the same verifier on the EL path.
my $text = do { open my $fh, '<', $builder or die "$builder: $!"; local $/; <$fh> };
like($text, qr{verify-genesis-payload}, 'builddeb-genesis-base verifies the payload it packages');

# The image belongs to the release whose kernel it carries, so the builder must refuse a
# root of any other release.
like($text, qr{--expect-codename}, 'builddeb-genesis-base takes the release it is building for');

# An absolute path in the install() output is a data file, not a command.
sub mandatory_commands {
    my ($path) = @_;
    my $dir = tempdir(CLEANUP => 1);
    my $driver = "$dir/collect.sh";
    open my $fh, '>', $driver or die "$driver: $!";
    print $fh <<"BASH";
dracut_install() { printf '%s\\n' "\$\@"; }
instmods() { :; }
inst_multiple() { :; }
inst() { :; }
dpkg-architecture() { echo x86_64-linux-gnu; }
. '$path'
# _dracut_install_opt installs only what the build root already has. Neutralise it after
# sourcing, so its commands stay out of the mandatory set.
_dracut_install_opt() { :; }
install
BASH
    close $fh;
    my @out = qx{bash '$driver' 2>/dev/null};
    die("running install() from $path produced nothing") unless @out;
    my %seen;
    my @names = grep { !$seen{$_}++ } grep { length && !m{^/} } map { chomp; $_ } @out;
    die("install() from $path named no bare commands") unless @names;
    return @names;
}

# Evaluate the assignment rather than parse it, so the list is the value the script uses.
# add_first_available names the alternatives for a package that was renamed between releases,
# so its candidates count too.
sub required_packages {
    my ($path) = @_;
    my $text = do { open my $fh, '<', $path or die "$path: $!"; local $/; <$fh> };
    my ($block) = $text =~ /^(REQUIRED_PACKAGES="[^"]*")/ms;
    die("no REQUIRED_PACKAGES assignment in $path") unless $block;
    my $out = qx{bash -c 'set -u; $block; printf "%s\\n" \$REQUIRED_PACKAGES' 2>/dev/null};
    my @packages = grep { length } split /\s+/, ($out // '');
    die("REQUIRED_PACKAGES in $path evaluated to nothing") unless @packages;
    push @packages, grep { length } split /\s+/, $1
        while $text =~ /^add_first_available\s+(.+)$/mg;
    return @packages;
}
