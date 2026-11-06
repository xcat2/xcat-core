#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Test::More;
use imgutils;

plan skip_all => 'requires Linux sed' unless $^O eq 'linux';
my $dir = tempdir(CLEANUP => 1);

my @legacy_repositories = qw(Rocky-BaseOS.repo almalinux.repo CentOS-Base.repo oracle-linux-ol10.repo);
my @custom_repositories = qw(local-repository-0.repo xCAT-custom.repo administrator.repo);
my $enabled = "[fixture]\nenabled=1\ngpgcheck=1\nbaseurl=https://repo.invalid/\n";
my $disabled = "[fixture]\nenabled=0\ngpgcheck=1\nbaseurl=https://repo.invalid/\n";
my $native = "[OS]\nenabled=1\ngpgcheck=1\n[update]\n \tenabled = 1\n[disabled]\nenabled=0\n#enabled=1\n";
my $native_disabled = "[OS]\nenabled=0\ngpgcheck=1\n[update]\nenabled=0\n[disabled]\nenabled=0\n#enabled=1\n";
for my $repository_case (
    ['enabled', $native, $native_disabled],
    ['already-disabled', $native_disabled, $native_disabled],
    ['absent', undef, undef],
) {
    my ($name, $input, $expected) = @$repository_case;
    subtest $name => sub {
        my $root = tempdir(DIR => $dir, CLEANUP => 1);
        my $repos = "$root/etc/yum.repos.d";
        make_path($repos);
        write_text("$repos/$_", $enabled) for (@legacy_repositories, @custom_repositories);
        write_text("$repos/openEuler.repo", $input) if defined $input;
        for my $pass (1, 2) {
            imgutils::disable_vendor_repositories($root);
            if (defined $expected) {
                is(read_text("$repos/openEuler.repo"), $expected,
                    "pass $pass disables only active native repository assignments");
            } else {
                ok(!-e "$repos/openEuler.repo", "pass $pass does not create an absent vendor file");
            }
            is(read_text("$repos/$_"), $disabled, "pass $pass preserves policy for $_")
                for @legacy_repositories;
            is(read_text("$repos/$_"), $enabled, "pass $pass leaves $_ unchanged")
                for @custom_repositories;
        }
    };
}

done_testing();
