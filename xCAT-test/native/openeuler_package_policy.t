#!/usr/bin/env perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path);

foreach my $command ('rpm', 'rpmspec', 'rpmbuild') {
    system('sh', '-c', 'command -v "$1" >/dev/null 2>&1', 'sh', $command) == 0
        or plan skip_all => "$command is required for native RPM policy validation";
}
my $root = tempdir(CLEANUP => 1);
make_path(map {"$root/$_"} qw(BUILD BUILDROOT RPMS SOURCES SPECS SRPMS));
my @macros = ('--define', 'version 2.18.0', '--define', 'release 1',
    '--undefine', 'rhel', '--undefine', 'fedora', '--undefine', 'suse_version', '--undefine', 'openEuler');
my @roles = (
    ['mn', $ENV{XCAT_TEST_MN_SPEC} || repo_path('xCAT/xCAT.spec')],
    ['sn', $ENV{XCAT_TEST_SN_SPEC} || repo_path('xCATsn/xCATsn.spec')],
);
my %consumer;
foreach my $role (@roles) {
    my ($name, $spec) = @$role;
    my ($rc, $requires) = run('rpmspec', '-q', '--requires', '--target', 'x86_64', @macros,
        '--define', 'openEuler 2', $spec);
    is($rc, 0, "$name native dependencies parse through RPM");
    die("Unable to parse $spec: $requires") if $rc;
    my @dhcp = grep { /\bkea(?:-hooks)?\b|\/usr\/sbin\/dhcpd/ } split(/\n/, $requires);
    ok(@dhcp, "$name emits DHCP policy requirements");
    $consumer{$name} = build_fixture("policy-$name", join('', map {"Requires: $_\n"} @dhcp));

    foreach my $arch ('x86_64', 'ppc64le') {
        foreach my $platform (['openEuler', '2', 'apach24'], ['rhel', '9', 'apach24'], ['legacy', '0', 'apach22']) {
            my @platform_macros = $platform->[0] eq 'legacy' ? () : ('--define', "$platform->[0] $platform->[1]");
            my ($parse_rc, $parsed) = run('rpmspec', '--parse', '--target', $arch, @macros, @platform_macros, $spec);
            is($parse_rc, 0, "$name $platform->[0] $arch spec parses");
            my ($install) = $parsed =~ /^%install\b(.*?)(?=^%post\b)/ms;
            my $source = $platform->[2] eq 'apach24' ? 'xcat.conf.apach24' : 'xcat.conf';
            like($install || '', qr{^cp\s+\S*/\Q$source\E\s+\$RPM_BUILD_ROOT/etc/httpd/conf\.d/xcat\.conf$}m,
                "$name $platform->[0] $arch installs the expected Apache configuration");
        }
    }
}

my $server_spec = $ENV{XCAT_TEST_SERVER_SPEC} || repo_path('xCAT-server/xCAT-server.spec');
foreach my $arch ('x86_64', 'ppc64le') {
    foreach my $platform (['openEuler', 2, 1], ['rhel', 8, 1], ['rhel', 7, 0], ['fedora', 44, 1], ['legacy', 0, 0]) {
        my @platform_macros = $platform->[0] eq 'legacy' ? () : ('--define', "$platform->[0] $platform->[1]");
        my ($rc, $requires) = run('rpmspec', '-q', '--buildrequires', '--target', $arch, @macros,
            @platform_macros, $server_spec);
        is($rc, 0, "server $platform->[0] $platform->[1] $arch build requirements parse");
        is($requires =~ /^perl-generators(?:\s|$)/m ? 1 : 0, $platform->[2],
            "server $platform->[0] $platform->[1] $arch selects the expected Perl build tools");
    }
}

my %provider = (
    native_ga => build_fixture('native-ga', "Provides: openEuler-release = 24.03LTS\nProvides: system-release = 24.03LTS\n"),
    native_sp => build_fixture('native-sp', "Provides: openEuler-release = 24.03LTS_SP3\nProvides: system-release = 24.03LTS_SP3\n"),
    el9 => build_fixture('el9-release', "Provides: system-release = 9.6\n"),
    el10 => build_fixture('el10-release', "Provides: system-release = 10.1\n"),
    suse => build_fixture('suse-release', ''),
    isc => build_fixture('isc-provider', '', '/usr/sbin/dhcpd'),
    kea => build_fixture('kea-provider', "Provides: kea\n"),
    hooks => build_fixture('hooks-provider', "Provides: kea-hooks\n"),
);
my @scenarios = (
    ['native GA ISC', 1, qw(native_ga isc)],
    ['native SP ISC', 1, qw(native_sp isc)],
    ['native GA Kea only', 0, qw(native_ga kea hooks)],
    ['native SP Kea only', 0, qw(native_sp kea hooks)],
    ['native missing DHCP', 0, qw(native_sp)],
    ['EL9 ISC', 1, qw(el9 isc)],
    ['EL9 Kea only', 0, qw(el9 kea hooks)],
    ['EL10 Kea', 1, qw(el10 kea hooks)],
    ['EL10 ISC only', 0, qw(el10 isc)],
    ['EL10 missing hooks', 0, qw(el10 kea)],
    ['SUSE ISC', 1, qw(suse isc)],
    ['SUSE Kea only', 0, qw(suse kea hooks)],
);
foreach my $scenario (@scenarios) {
    my ($label, $success, @providers) = @$scenario;
    my $db = tempdir(DIR => $root, CLEANUP => 1);
    my ($init_rc, $init_output) = run('rpm', '--dbpath', $db, '--initdb');
    die("Cannot initialize test RPM database: $init_output") if $init_rc;
    my ($install_rc, $install_output) = run('rpm', '--dbpath', $db, '--justdb', '--nodeps', '-i', map {$provider{$_}} @providers);
    die("Cannot seed test RPM database: $install_output") if $install_rc;
    foreach my $role (@roles) {
        my ($rc, $output) = run('rpm', '--dbpath', $db, '--test', '-i', $consumer{$role->[0]});
        is($rc == 0 ? 1 : 0, $success, "$role->[0] $label has the expected dependency result")
            or diag($output);
        like($output, qr/(?:kea|dhcpd).*needed/, "$role->[0] rejects the missing DHCP provider") unless $success;
    }
}
done_testing();

sub build_fixture {
    my ($name, $requirements, $file) = @_;
    my $spec = "$root/SPECS/$name.spec";
    open(my $fh, '>', $spec) or die "$spec: $!";
    print {$fh} "Name: $name\nVersion: 1\nRelease: 1\nSummary: RPM policy fixture\nLicense: MIT\nBuildArch: noarch\n$requirements\n%description\nRPM transaction fixture.\n%install\nmkdir -p %{buildroot}\n";
    if ($file) {
        (my $parent = $file) =~ s{/[^/]+$}{};
        print {$fh} "mkdir -p %{buildroot}$parent\ntouch %{buildroot}$file\n";
    }
    print {$fh} "\n%files\n", $file || '', "\n";
    close($fh) or die "$spec: $!";
    my ($rc, $output) = run('rpmbuild', '-bb', '--define', "_topdir $root", '--define', '_build_id_links none', $spec);
    die("Cannot build RPM fixture $name: $output") if $rc;
    my $rpm = "$root/RPMS/noarch/$name-1-1.noarch.rpm";
    die("RPM fixture missing: $rpm") unless -f $rpm;
    return $rpm;
}
sub run {
    my (@command) = @_;
    my $log = "$root/command.log";
    my $pid = fork();
    die "fork: $!" unless defined($pid);
    if (!$pid) {
        open(STDOUT, '>', $log) or die $!;
        open(STDERR, '>&', \*STDOUT) or die $!;
        exec(@command) or die "@command: $!";
    }
    waitpid($pid, 0);
    my $status = (($? & 127) ? 128 + ($? & 127) : $? >> 8);
    open(my $fh, '<', $log) or die "$log: $!";
    return ($status, do {local $/; scalar <$fh>} || '');
}
