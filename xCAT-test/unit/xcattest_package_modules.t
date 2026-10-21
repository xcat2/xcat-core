#!/usr/bin/env perl
# The installed xcattest loads the modules under xCAT-test/lib/xCAT from /opt/xcat/lib/perl, so
# both packages must ship each one.
use strict;
use warnings;
use File::Find;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path slurp_repo_file);

my $lib = repo_path('xCAT-test/lib');
my @modules;
find(sub { push @modules, $File::Find::name =~ s{\A\Q$lib\E/}{}r if /\.pm\z/ }, "$lib/xCAT");
@modules = sort @modules;
ok(@modules, 'xCAT-test ships at least one Perl module to the installed tree');

my $rpm_spec       = slurp_repo_file('xCAT-test/xCAT-test.spec');
my $debian_install = slurp_repo_file('xCAT-test/debian/install');
for my $module (@modules) {
    (my $dir = $module) =~ s{/[^/]+\z}{};
    like($rpm_spec, qr{^cp\s+lib/\Q$module\E\s+\$RPM_BUILD_ROOT/%\{prefix\}/lib/perl/\Q$dir\E/?\s*$}m,
        "the RPM installs $module under lib/perl/$dir");
    like($debian_install, qr{^lib/\Q$module\E\s+opt/xcat/lib/perl/\Q$dir\E/?\s*$}m,
        "the Debian package installs $module under opt/xcat/lib/perl/$dir");
}

done_testing();
