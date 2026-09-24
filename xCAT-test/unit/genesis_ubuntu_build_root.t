#!/usr/bin/env perl
# The Ubuntu Genesis build root must carry every command the Ubuntu dracut module marks
# mandatory. dracut_install reports a missing command and returns 0, so a hole in the image
# does not fail the build.
#
# XCAT::GenesisBuildRoot::required_packages lists the packages of the build root, and
# XCAT::GenesisPayload::module_commands reads the mandatory commands from the module, as
# verify-genesis-payload does. The refusal of a root of another release is in
# genesis_deb_per_codename.t.
use strict;
use warnings;

use File::Slurper qw(read_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-genesis-builder/lib";
use Test::More;

use XCAT::GenesisBuildRoot qw(required_packages);
use XCAT::GenesisPayload qw(module_commands);
use XCAT::Test::File qw(repo_path);

my $builder  = repo_path('xCAT-genesis-builder/builddeb-genesis-base');
my $module   = repo_path('xCAT-genesis-builder/dracut_105/ubuntu/module-setup.sh');

# Mandatory commands a minimal Ubuntu server root does NOT already provide, and the packages
# that supply each one. hwclock has two names: it left util-linux for util-linux-extra in
# 23.04.
my %PACKAGES_FOR = (
    dhclient  => ['isc-dhcp-client'],
    ifenslave => ['ifenslave'],
    hwclock   => [ 'util-linux-extra', 'util-linux' ],
);

# A release carries exactly the names in its list.
sub release {
    my %carried = map { $_ => 1 } @_;
    return sub { $carried{ $_[0] } };
}
my $NOBLE = release(qw(bind9-dnsutils dnsutils util-linux-extra util-linux tzdata-legacy));
my $FOCAL = release(qw(dnsutils util-linux));

my @noble = required_packages('amd64', 'noble', $NOBLE);
is_deeply([ @noble[ -5 .. -1 ] ],
    [qw(dmidecode efibootmgr bind9-dnsutils util-linux-extra tzdata-legacy)],
    'amd64 adds dmidecode and efibootmgr, then the first name the release carries');

my @focal = required_packages('amd64', 'focal', $FOCAL);
is_deeply([ @focal[ -2 .. -1 ] ], [qw(dnsutils util-linux)],
    'a release without the new names gets dnsutils and util-linux, and no tzdata-legacy');

my @ppc = required_packages('ppc64el', 'noble', $NOBLE);
is_deeply([ @ppc[ -3 .. -1 ] ], [qw(bind9-dnsutils util-linux-extra tzdata-legacy)],
    'ppc64el gets neither dmidecode nor efibootmgr');
is_deeply([ @ppc[ 0 .. $#ppc - 3 ] ], [ @noble[ 0 .. $#noble - 5 ] ],
    'ppc64el and amd64 share the base packages');

my @asked;
required_packages('amd64', 'noble', sub { push @asked, $_[0]; $NOBLE->($_[0]) });
is_deeply(\@asked, [qw(bind9-dnsutils util-linux-extra tzdata-legacy)],
    'apt is asked for the older name only when the newer one is absent');

ok(!eval { required_packages('amd64', 'oddball', release('bind9-dnsutils')); 1 },
    'a release that carries no hwclock package fails');
is($@, "ERROR: oddball carries none of these packages: util-linux-extra util-linux\n",
    'the failure names the release and the missing alternatives');

# --- every mandatory command has a package in the build root -----------------------------
# An absolute path is a data file, not a command.
my %mandatory = map { $_ => 1 } grep { !m{^/} } module_commands($module);
my %packages  = map { $_ => 1 } @noble;
for my $command (sort keys %PACKAGES_FOR) {
    my @provider = @{ $PACKAGES_FOR{$command} };
    ok($mandatory{$command}, "the Ubuntu dracut module installs '$command' unconditionally");
    ok(scalar(grep { $packages{$_} } @provider),
       "the build root installs @{[ join ' or ', @provider ]}, which provides '$command'");
}
ok(grep({ $_ eq 'util-linux' } @focal), 'a release before 23.04 gets hwclock from util-linux');

# doxcat asks dhclient for the provisioning lease.
ok($mandatory{dhclient} && $packages{'isc-dhcp-client'},
   'the Genesis image can obtain a DHCP lease');

# The build cannot run here, so the call to the payload gate is read from the script. The
# gate itself is exercised by genesis_payload_verification.t.
like(read_text($builder),
    qr{^bash "\$DIR/verify-genesis-payload" --commands-from "\$DRACUTMODDIR/module-setup\.sh" "\$GENESIS_FS"}m,
    'builddeb-genesis-base verifies the payload it packages against the module');

done_testing();
