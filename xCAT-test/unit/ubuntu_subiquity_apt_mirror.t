#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use Test::More;
use YAML::PP;
use XCAT::Test::File qw(repo_path);

my $dir = tempdir(CLEANUP => 1);
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "SQLite:$dir";
require lib;
lib->import(repo_path('perl-xCAT'), repo_path('xCAT-server/lib/perl'));
require xCAT::Template;

my $archive = 'http://archive.ubuntu.com/ubuntu';
my $ports = 'http://ports.ubuntu.com/ubuntu-ports';
my $override = 'https://mirror.example.invalid/ubuntu';
my $yaml = YAML::PP->new();
my $site = xCAT::Table->new('site', -create => 1);
die 'Cannot create the site table' unless $site;

for my $setting ('missing', 'override', 'cleared') {
    $site->setAttribs({key => 'ubuntu_apt_mirror'}, {value => $override})
        if $setting eq 'override';
    $site->setAttribs({key => 'ubuntu_apt_mirror'}, {value => ''})
        if $setting eq 'cleared';
    for my $case (
        ['x86_64', $archive], ['amd64', $archive],
        ['x86', $archive], ['i386', $archive],
        ['ppc64el', $ports], ['ppc64le', $ports],
        ['riscv64', $ports], ['s390x', $ports],
        [undef, $archive], ['', $archive],
    ) {
        my ($arch, $default) = @$case;
        my $mirror = $setting eq 'override' ? $override : $default;
        my $name = defined($arch) ? "'$arch'" : 'undefined';
        is(xCAT::Template::ubuntu_subiquity_apt_mirror($arch), $mirror,
            "$setting site, $name architecture: selected mirror");
        for my $release (qw(ubuntu22.04 ubuntu24.04)) {
            my $rendered = xCAT::Template::ubuntu_subiquity_apt_config($release, $arch);
            my $apt = $yaml->load_string($rendered)->{apt};
            is_deeply($apt->{'mirror-selection'}->{primary}, [{uri => $mirror}],
                "$setting site, $name architecture, $release: primary mirror in YAML");
            if ($release eq 'ubuntu22.04') {
                is($apt->{sources}->{'xcat-ubuntu-archive.list'}->{source},
                    "deb $mirror \$RELEASE main restricted universe multiverse",
                    "$setting site, $name architecture: classic archive source");
                is($apt->{sources}->{'xcat-ubuntu-updates.list'}->{source},
                    "deb $mirror \$RELEASE-updates main restricted universe multiverse",
                    "$setting site, $name architecture: classic updates source");
            } else {
                ok(!exists $apt->{sources},
                    "$setting site, $name architecture: no duplicate Deb822 sources");
            }
        }
    }
}
$site->close();

{
    no warnings qw(redefine once);
    local *xCAT::Table::new = sub { return };
    is(xCAT::Template::ubuntu_subiquity_apt_mirror('riscv64'), $ports,
        'unavailable site table keeps the architecture default');
    is(xCAT::Template::ubuntu_subiquity_apt_mirror(undef), $archive,
        'unavailable site table and architecture keep the main archive');
}

done_testing();
