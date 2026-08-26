#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

use XCAT::Test::File qw(repo_path);
use xCAT::ProfiledNodeUtils;
use xCAT::Utils;

# riscv64 nodes boot through UEFI and grub2 only. This test pins the three
# places that declare which noderes.netboot values an architecture accepts:
# xCAT::Utils::lookupNetboot (used by nodeset/rinstall validation), the
# profiled-node netboot rule table in xCAT::ProfiledNodeUtils, and the
# schema descriptions that document the valid values.
#
# ---------------------------------------------------------------------------
# xCAT::Utils::lookupNetboot
# ---------------------------------------------------------------------------
my @lookup_cases = (
    [ 'rocky10.2', 'riscv64', 'Linux', 'grub2,grub2-tftp,grub2-http', 'riscv64 EL10 boots with grub2 over tftp or http' ],
    [ 'rhels10.2', 'riscv64', 'Linux', 'grub2,grub2-tftp,grub2-http', 'riscv64 RHEL 10 uses the same grub2 methods' ],
    [ 'ubuntu24.04.4', 'riscv64', 'Linux', 'grub2,grub2-tftp,grub2-http', 'riscv64 is arch-driven, not distro-driven' ],
    [ 'rhels10.2', 'RISCV64', 'Linux', 'grub2,grub2-tftp,grub2-http', 'the arch match is case-insensitive like the other arches' ],
    [ 'rhels9.4',  'aarch64', 'Linux', 'grub2', 'aarch64 keeps its single grub2 method' ],
    [ 'rhels9.4',  'x86_64',  'Linux', 'xnba,pxe,grub2', 'x86_64 methods are unchanged' ],
    [ 'rhels9.4',  'ppc64le', 'Linux', 'petitboot,grub2,grub2-tftp,grub2-http', 'ppc64le methods are unchanged' ],
    [ 'rhels10.2', 'riscv64', 'NIM',   'nimol', 'NIM images are not affected by the arch' ],
    [ 'rhels10.2', 'riscv32', 'Linux', '', 'unknown architectures still resolve to no netboot method' ],
);

for my $case (@lookup_cases) {
    my ( $osvers, $osarch, $imgtype, $expected, $label ) = @$case;
    is( xCAT::Utils->lookupNetboot( $osvers, $osarch, $imgtype ), $expected, $label );
}

# ---------------------------------------------------------------------------
# xCAT::ProfiledNodeUtils netboot rule table + cal_netboot
# ---------------------------------------------------------------------------
my $rule_table = \%xCAT::ProfiledNodeUtils::NETBOOT_RULES;

is( xCAT::ProfiledNodeUtils::cal_netboot( $rule_table, [ 'riscv64', 'rhels', '10', '*' ] ),
    'grub2', 'profiled riscv64 nodes default to grub2' );
is( xCAT::ProfiledNodeUtils::cal_netboot( $rule_table, [ 'riscv64', 'rhels', '10', 'ipmi' ] ),
    'grub2', 'riscv64 grub2 does not depend on the management method' );
is( xCAT::ProfiledNodeUtils::cal_netboot( $rule_table, [ 'x86_64', 'rhels', '10', '*' ] ),
    'xnba', 'x86_64 profiled nodes still default to xnba' );
is( xCAT::ProfiledNodeUtils::cal_netboot( $rule_table, [ 'ppc64le', 'rhels', '9', 'ipmi' ] ),
    'petitboot', 'ppc64le ipmi profiled nodes still default to petitboot' );
is( xCAT::ProfiledNodeUtils::cal_netboot( $rule_table, [ 'aarch64', 'rhels', '9', '*' ] ),
    '0', 'aarch64 profiled nodes are still undefined in the rule table' );

# ---------------------------------------------------------------------------
# Schema descriptions
# ---------------------------------------------------------------------------
SKIP: {
    skip 'xCAT::Schema is not loadable here', 3
      unless eval { require lib; lib->import( repo_path('perl-xCAT') ); require xCAT::Schema; 1 };

    like( $xCAT::Schema::tabspec{nodetype}{descriptions}{arch}, qr/\briscv64\b/,
        'nodetype.arch documents riscv64 as a valid value' );
    like( $xCAT::Schema::tabspec{osimage}{descriptions}{osarch}, qr/\briscv64\b/,
        'osimage.osarch documents riscv64 as a valid value' );
    like( $xCAT::Schema::tabspec{noderes}{descriptions}{netboot}, qr/riscv64\s+>=el10\s+grub2,grub2-http,grub2-tftp/,
        'noderes.netboot documents the riscv64 grub2 methods' );
}

done_testing();
