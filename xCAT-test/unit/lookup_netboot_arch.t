#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

# riscv64 nodes boot through UEFI and grub2 only. This test pins the three
# places that declare which noderes.netboot values an architecture accepts:
# xCAT::Utils::lookupNetboot (used by nodeset/rinstall validation), the
# profiled-node netboot rule table in xCAT::ProfiledNodeUtils, and the
# schema descriptions that document the valid values.
#
# xCAT::Utils and xCAT::ProfiledNodeUtils pull in the database layer at load
# time, so the shipped subroutines are extracted from the source and evaluated
# directly instead of loading the whole modules.

my $utils_pm = repo_path('perl-xCAT/xCAT/Utils.pm');
my $pnu_pm = repo_path('perl-xCAT/xCAT/ProfiledNodeUtils.pm');

plan skip_all => "$utils_pm not found" unless -r $utils_pm;
plan skip_all => "$pnu_pm not found"   unless -r $pnu_pm;

# ---------------------------------------------------------------------------
# xCAT::Utils::lookupNetboot
# ---------------------------------------------------------------------------
my $utils_source = slurp_repo_file('perl-xCAT/xCAT/Utils.pm');
my ($lookup_sub) = $utils_source =~ m{^(sub lookupNetboot \{.*?^\})}ms;
ok( $lookup_sub, 'lookupNetboot was located in xCAT::Utils' )
  or BAIL_OUT('Utils.pm no longer matches the expected lookupNetboot shape');

{
    package Test::LookupNetboot;
    my $code = $lookup_sub;
    eval $code;    ## no critic (BuiltinFunctions::ProhibitStringyEval)
    die "Unable to evaluate lookupNetboot: $@" if $@;
}

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
    is( Test::LookupNetboot::lookupNetboot( $osvers, $osarch, $imgtype ), $expected, $label );
}

is( Test::LookupNetboot::lookupNetboot( 'xCAT::Utils', 'rocky10.2', 'riscv64', 'Linux' ),
    'grub2,grub2-tftp,grub2-http', 'the class-method calling convention works for riscv64' );

# ---------------------------------------------------------------------------
# xCAT::ProfiledNodeUtils netboot rule table + cal_netboot
# ---------------------------------------------------------------------------
my $pnu_source = slurp_repo_file('perl-xCAT/xCAT/ProfiledNodeUtils.pm');
my ($netboot_dict) = $pnu_source =~ m{^(\s*my %netboot_dict = \(.*?^\s*\);)}ms;
ok( $netboot_dict, 'the profiled-node netboot rule table was located' )
  or BAIL_OUT('ProfiledNodeUtils.pm no longer matches the expected %netboot_dict shape');
my ($cal_netboot) = $pnu_source =~ m{^(sub cal_netboot \{.*?^\})}ms;
ok( $cal_netboot, 'cal_netboot was located in xCAT::ProfiledNodeUtils' )
  or BAIL_OUT('ProfiledNodeUtils.pm no longer matches the expected cal_netboot shape');

my $rule_table;
{
    package Test::ProfiledNetboot;
    my $code = "$cal_netboot\n sub rule_table { $netboot_dict return \\%netboot_dict; }";
    eval $code;    ## no critic (BuiltinFunctions::ProhibitStringyEval)
    die "Unable to evaluate the profiled-node netboot rules: $@" if $@;
    $rule_table = rule_table();
}

is( Test::ProfiledNetboot::cal_netboot( $rule_table, [ 'riscv64', 'rhels', '10', '*' ] ),
    'grub2', 'profiled riscv64 nodes default to grub2' );
is( Test::ProfiledNetboot::cal_netboot( $rule_table, [ 'riscv64', 'rhels', '10', 'ipmi' ] ),
    'grub2', 'riscv64 grub2 does not depend on the management method' );
is( Test::ProfiledNetboot::cal_netboot( $rule_table, [ 'x86_64', 'rhels', '10', '*' ] ),
    'xnba', 'x86_64 profiled nodes still default to xnba' );
is( Test::ProfiledNetboot::cal_netboot( $rule_table, [ 'ppc64le', 'rhels', '9', 'ipmi' ] ),
    'petitboot', 'ppc64le ipmi profiled nodes still default to petitboot' );
is( Test::ProfiledNetboot::cal_netboot( $rule_table, [ 'aarch64', 'rhels', '9', '*' ] ),
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
