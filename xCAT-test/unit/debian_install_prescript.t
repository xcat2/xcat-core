#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# Ubuntu has two installers and two pre-install scripts that are not interchangeable.
# pre.ubuntu.subiquity writes a curtin "storage:" document that the autoinstall
# early-commands append to /autoinstall.yaml. pre.ubuntu.ppc64 writes a partman recipe
# for the debian-installer, which is not YAML at all.
#
# mkinstall chose the subiquity script, then overwrote that choice for every ppc64
# node. A ppc64el 24.04 install therefore appended a partman recipe to its
# autoinstall.yaml, Subiquity failed on the malformed document, the error-commands
# tarred /var/log/installer and the node rebooted into the installer again -- nine
# times in build #121 of xcat-core-devel-ubuntu-cd, cell ubuntu-24-ppc64le-devel,
# case reg_linux_diskfull_installation_flat. The node answered ping from the live
# installer the whole time, so the case failed on
# "root@xcat25-cn: Permission denied (publickey,password)".
#
# The ppc64 script belongs to the debian-installer path only.

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/debian.pm";
plan skip_all => 'debian.pm not found' unless -r $plugin;
eval { require $plugin; 1 } or plan skip_all => "could not load debian.pm: $@";

can_ok('xCAT_plugin::debian', 'install_prescript')
    or BAIL_OUT('mkinstall still chooses the pre-install script inline, so nothing can drive it');

sub chosen {
    my ($platform, $arch, $subiquity) = @_;
    my $path = xCAT_plugin::debian::install_prescript($platform, $arch, $subiquity);
    $path =~ s{.*/}{};
    return $path;
}

# --- subiquity: the arch never changes the script -------------------------
is(chosen('ubuntu', 'x86_64',  1), 'pre.ubuntu.subiquity',
    'an x86_64 subiquity install gets the subiquity pre-install script');
is(chosen('ubuntu', 'ppc64el', 1), 'pre.ubuntu.subiquity',
    'a ppc64el subiquity install gets the subiquity pre-install script, not the partman one');
is(chosen('ubuntu', 'ppc64le', 1), 'pre.ubuntu.subiquity',
    'the ppc64le spelling reaches the same script');
is(chosen('ubuntu', 'ppc64',   1), 'pre.ubuntu.subiquity',
    'so does the bare ppc64 spelling');

# --- debian-installer: ppc64 keeps its own script -------------------------
is(chosen('ubuntu', 'ppc64el', 0), 'pre.ubuntu.ppc64',
    'a ppc64el debian-installer install keeps the partman pre-install script');
is(chosen('ubuntu', 'ppc64',   0), 'pre.ubuntu.ppc64',
    'and so does the bare ppc64 spelling');
is(chosen('ubuntu', 'x86_64',  0), 'pre.ubuntu',
    'an x86_64 debian-installer install gets the plain script');

# --- the override is Ubuntu only -----------------------------------------
is(chosen('debian', 'ppc64el', 0), 'pre.debian',
    'Debian on POWER has no ppc64 pre-install script to select');

done_testing();
