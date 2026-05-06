#!/usr/bin/env perl
use strict;
use warnings;

BEGIN {
    $ENV{XCATCFG} ||= 'SQLite:/tmp';
}

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::DBobjUtils;

my %missing_mgt = (
    objtype => 'node',
    groups  => 'test',
    bmc     => '10.0.0.1',
);
my @failures = xCAT::DBobjUtils->validate_only_if_attrs('node01', 'node', \%missing_mgt, {});
is(scalar @failures, 1, 'bmc without mgt fails only_if validation');
like($failures[0]->{message}, qr/mgt value is .*openbmc/, 'failure explains accepted mgt values');

my %explicit_openbmc = (
    objtype => 'node',
    groups  => 'test',
    mgt     => 'openbmc',
    bmc     => '10.0.0.1',
);
@failures = xCAT::DBobjUtils->validate_only_if_attrs('node01', 'node', \%explicit_openbmc, {});
is(scalar @failures, 0, 'explicit mgt=openbmc satisfies bmc only_if validation');

my %existing_openbmc = (
    objtype => 'node',
    groups  => 'test',
    bmc     => '10.0.0.1',
);
my %dbattrs = (mgt => 'openbmc');
@failures = xCAT::DBobjUtils->validate_only_if_attrs('node01', 'node', \%existing_openbmc, \%dbattrs);
is(scalar @failures, 0, 'existing mgt=openbmc satisfies bmc only_if validation');

my %group_openbmc = (
    objtype => 'node',
    groups  => 'openbmcgrp',
    bmc     => '10.0.0.1',
);
my %groupattrs = (openbmcgrp => { mgt => 'openbmc' });
@failures = xCAT::DBobjUtils->validate_only_if_attrs('node01', 'node', \%group_openbmc, {}, \%groupattrs);
is(scalar @failures, 0, 'group mgt=openbmc satisfies bmc only_if validation');

done_testing();
