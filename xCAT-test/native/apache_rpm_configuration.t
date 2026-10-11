#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(slurp_repo_file);
use XCAT::Test::RPM;

plan skip_all => 'Native RPM distribution and Linux namespaces are required'
    unless $^O eq 'linux' && -f '/etc/redhat-release';

sub succeeds {
    my ($label, @result) = @_;
    is($result[0], 0, $label) or diag "$result[1]$result[2]";
    unlike($result[2], qr/scriptlet failed|scriptlet failure/i, "$label completes scriptlets");
}

for my $package (qw(xCAT xCATsn)) {
    my $old_rpm = XCAT::Test::RPM->build_fixture('legacy-apache', '--define', "test_package $package");
    for my $target (
        ['el-modern', 'xcat.conf.apach24', '--define', 'rhel 8'],
        ['el-legacy', 'xcat.conf', '--define', 'rhel 6'],
        ['suse-modern', 'xcat.conf.apach24', '--define', 'rhel 0', '--define', 'suse_version 1500'],
    ) {
        my ($label, $source, @defines) = @$target;
        my $rpm = XCAT::Test::RPM->build($package, 1, @defines);
        my $expected = slurp_repo_file("xCAT/$source");
        for my $state (qw(default24 default22 edited absent symlink fresh)) {
            subtest "$package $label $state configuration" => sub {
                my $root = XCAT::Test::RPM->new;
                $root->write('/opt/xcat/sbin/xcatconfig', "#!/bin/sh\nexit 0\n", 0755);
                $root->write('/opt/xcat/share/xcat/scripts/xHRM', '');
                succeeds('install legacy ownership fixture', $root->install($old_rpm)) unless $state eq 'fresh';
                my $prior = $state eq 'default22' ? "# prior Apache 2.2 default\n" : "# prior Apache 2.4 default\n";
                $root->write('/etc/xcat/conf.orig/xcat.conf.apach24', $prior) if $state eq 'fresh';
                for my $daemon (qw(httpd apache2)) {
                    my $active = "/etc/$daemon/conf.d/xcat.conf";
                    if ($state eq 'absent' || $state eq 'symlink') {
                        unlink $root->path($active) or die "unlink $active: $!";
                    }
                    if ($state eq 'symlink') {
                        $root->write("/etc/$daemon/local.conf", $prior);
                        symlink('../local.conf', $root->path($active)) or die "symlink: $!";
                    } elsif ($state ne 'absent') {
                        $root->write($active, $state eq 'edited' ? "# administrator configuration\n" : $prior);
                    }
                }
                succeeds('upgrade to configuration ownership', $root->install($rpm));
                for my $daemon (qw(httpd apache2)) {
                    my $active = "/etc/$daemon/conf.d/xcat.conf";
                    ok(-e $root->path($active), "$daemon has active configuration");
                    next unless -e $root->path($active);
                    if ($state eq 'edited' || $state eq 'symlink' || $state eq 'fresh') {
                        is($root->read($active), $state eq 'edited' ? "# administrator configuration\n" : $prior, "$daemon retains local bytes");
                        ok(-f $root->path("$active.rpmnew"), "$daemon receives a separate package default");
                        is($root->read("$active.rpmnew"), $expected, "$daemon rpmnew has selected Apache syntax") if -f $root->path("$active.rpmnew");
                        is(readlink($root->path($active)), '../local.conf', "$daemon keeps administrator symlink") if $state eq 'symlink';
                    } else {
                        is($root->read($active), $expected, "$daemon installs selected Apache syntax");
                        ok(!-e $root->path("$active.rpmnew"), "$daemon default is active without an rpmnew");
                    }
                    ok(!-e $root->path("$active.rpmsave"), "$daemon does not leave an rpmsave on upgrade");
                }
            };
        }
    }
}

done_testing();
