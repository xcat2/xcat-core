#!/usr/bin/env perl
## no critic (NamingConventions::Capitalization, TestingAndDebugging::ProhibitNoWarnings)
use strict;
use warnings;

our $VERSION = '1.0';

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

use xCAT::Template;

{

    package UbuntuSubiquityReleaseTable;
    sub getNodeAttribs { return { os => 'ubuntu26.04' }; }
}

my @release_cases = (
    [ '/install/ubuntu23.10/x86_64',   0, 0, 'Ubuntu 23.10' ],
    [ '/install/ubuntu24.04/x86_64',   1, 0, 'Ubuntu 24.04' ],
    [ 'ubuntu25.10',                   1, 0, 'Ubuntu 25.10' ],
    [ '/install/ubuntu26.04/ppc64le',  1, 1, 'Ubuntu 26.04' ],
    [ 'ubuntu29.10',                   1, 1, 'Ubuntu 29.10' ],
    [ 'ubuntu99.04',                   1, 1, 'Ubuntu 99.04' ],
    [ 'ubuntu100.04',                  0, 0, 'three-digit release year' ],
    [ '/install/ubuntu24.04.1/x86_64', 1, 0, 'Ubuntu 24.04 point release' ],
    [ '/install/ubuntu26.04.1/x86_64', 1, 1, 'Ubuntu 26.04 point release' ],
    [ '/install/debian26.04/x86_64',   0, 0, 'non-Ubuntu release' ],
    [ '/install/ubuntu26/x86_64', 0, 0, 'release without a minor version' ],
    [
        '/install/ubuntu26.x/x86_64', 0, 0,
        'release with a nonnumeric minor version'
    ],
);

foreach my $case (@release_cases) {
    my ( $release, $uses_deb822, $uses_generated_cdrom, $description ) =
      @{$case};
    is( xCAT::Template::ubuntu_subiquity_uses_deb822_sources($release),
        $uses_deb822, "$description keeps the Deb822 source policy" );
    is(
        xCAT::Template::ubuntu_subiquity_uses_generated_cdrom_source($release),
        $uses_generated_cdrom,
        "$description keeps the generated cdrom source policy"
    );
}

{
    no warnings 'redefine';
    local *xCAT::Table::new =
      sub { return bless {}, 'UbuntuSubiquityReleaseTable'; };

    ok(
        xCAT::Template::ubuntu_subiquity_uses_deb822_sources(),
        'nodetype OS fallback selects Deb822 sources'
    );
    ok(
        xCAT::Template::ubuntu_subiquity_uses_generated_cdrom_source(),
        'nodetype OS fallback selects the generated cdrom source'
    );
}

{
    no warnings 'redefine';
    local *xCAT::Table::new = sub { return; };

    ok(
        !xCAT::Template::ubuntu_subiquity_uses_deb822_sources(),
        'missing nodetype data does not select Deb822 sources'
    );
    ok(
        !xCAT::Template::ubuntu_subiquity_uses_generated_cdrom_source(),
        'missing nodetype data does not select the generated cdrom source'
    );
}

done_testing();
