#!/usr/bin/env perl
# The Ubuntu Genesis build root must carry every command the Ubuntu dracut module marks
# mandatory. dracut_install reports a missing command and returns 0, so a hole in the image
# does not fail the build.
#
# XCAT::GenesisBuildRoot::required_packages lists the packages of the build root, and
# XCAT::GenesisPayload::module_commands reads the mandatory commands from the module, as
# verify-genesis-payload does.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-genesis-base/lib";
use Test::More;

use XCAT::GenesisBuildRoot qw(required_packages);
use XCAT::GenesisPayload qw(module_commands);
use XCAT::Test::File qw(repo_path);

my $module = repo_path('xCAT-genesis-base/dracut_105/ubuntu/module-setup.sh');

# Mandatory commands a minimal Ubuntu server root does NOT already provide, and the package
# that supplies each one on every release xCAT builds for.
my %PACKAGE_FOR = (
    dhclient  => 'isc-dhcp-client',
    ifenslave => 'ifenslave',
);

# A release carries exactly the names in its list.
sub release {
    my %carried = map { $_ => 1 } @_;
    return sub { $carried{ $_[0] } };
}

# hwclock is not in that list because the package that carries it moved. Measured on the
# four Ubuntu management nodes: focal and jammy have it in util-linux, which is essential
# and always in the build root, and no util-linux-extra exists to install; noble and
# resolute have it in util-linux-extra. util-linux only Suggests that package, and this
# build passes --no-install-recommends, so the releases that split it must name it and the
# releases that did not must not.
my @noble = required_packages('amd64', 'noble', release('util-linux-extra'));
my @jammy = required_packages('amd64', 'jammy', release());

# An absolute path is a data file, not a command.
my %mandatory = map { $_ => 1 } grep { !m{^/} } module_commands($module);
my %packages  = map { $_ => 1 } @jammy;

for my $command (sort keys %PACKAGE_FOR) {
    ok($mandatory{$command}, "the Ubuntu dracut module installs '$command' unconditionally");
    ok($packages{ $PACKAGE_FOR{$command} },
       "the build root installs $PACKAGE_FOR{$command}, which provides '$command'");
}

# doxcat asks dhclient for the provisioning lease.
ok($mandatory{dhclient} && $packages{'isc-dhcp-client'},
   'the Genesis image can obtain a DHCP lease');

ok($mandatory{hwclock}, "the Ubuntu dracut module installs 'hwclock' unconditionally");

# Naming a package apt cannot locate fails the whole install, and the script runs under
# set -e, so an unconditional util-linux-extra stops the build on focal and jammy.
is_deeply([ grep { $_ eq 'util-linux-extra' } @jammy ], [],
    'a release without util-linux-extra does not get it');
is_deeply([ @noble[ 0 .. $#noble - 1 ] ], \@jammy,
    'a release that carries util-linux-extra gets the same list ...');
is($noble[-1], 'util-linux-extra', '... with util-linux-extra last');

my @ppc = required_packages('ppc64el', 'noble', release('util-linux-extra'));
is_deeply([ @noble[ -3 .. -1 ] ], [qw(dmidecode efibootmgr util-linux-extra)],
    'amd64 adds dmidecode and efibootmgr');
is_deeply([ @ppc[ 0 .. $#ppc - 1 ] ], [ @noble[ 0 .. $#noble - 3 ] ],
    'ppc64el gets neither dmidecode nor efibootmgr');

my @asked;
required_packages('amd64', 'noble', sub { push @asked, $_[0]; 1 });
is_deeply(\@asked, ['util-linux-extra'], 'apt is asked only about the optional package');

done_testing();
