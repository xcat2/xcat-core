#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path);

plan skip_all => 'requires rpmspec to render package conditionals'
    if system('sh', '-c', 'command -v rpmspec >/dev/null 2>&1');
my @macros = ('--define', 'version 2.18.0', '--define', 'release 1',
    '--undefine', 'rhel', '--undefine', 'fedora', '--undefine', 'suse_version', '--undefine', 'openEuler');
my @roles = (['mn', repo_path('xCAT/xCAT.spec')], ['sn', repo_path('xCATsn/xCATsn.spec')]);
for my $platform (['openEuler', 2, 'apach24'], ['rhel', 9, 'apach24'],
                  ['fedora', 40, 'apach24'], ['suse_version', 1500, 'apach24'],
                  ['rhel', 6, 'apach22']) {
    my ($macro, $value, $generation) = @$platform;
    for my $role (@roles) {
        open(my $pipe, '-|', 'rpmspec', '-P', @macros,
            '--define', "$macro $value", $role->[1]) or die "rpmspec: $!";
        my $rendered = do { local $/; <$pipe> };
        close($pipe) or die "Cannot render $role->[0] for $macro: $?";
        my ($install) = $rendered =~ /^%install\s*\n(.*?)(?=^%[a-z]|\z)/msg;
        die 'Rendered spec has no install section' unless defined($install);
        my $source = $generation eq 'apach24' ? 'xcat.conf.apach24' : 'xcat.conf';
        for my $directory (qw(httpd apache2)) {
            like($install, qr{^cp\s+\S*/\Q$source\E\s+\$RPM_BUILD_ROOT/etc/$directory/conf\.d/xcat\.conf\s*$}m,
                "$role->[0] $macro $value installs $generation for $directory");
        }
    }
}
done_testing();
