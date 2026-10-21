#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../lib";
use Cwd qw(abs_path);
use File::Temp qw(tempdir);
use JSON;
use Test::More;
use XCAT::Test::PostageFixture qw(fixture read_file $root $expected);
use xCAT::FreeBSDPostscript;
require xCAT::TableUtils;

subtest 'actual owner initialization precedes source context' => sub {
    fixture(0);
    local $ENV{XCATROOT} = "$root/stock";
    local $::XCATROOT = "$root/uninitialized";
    ok(!exists($INC{'xCAT/Postage.pm'}), 'actual owner must initialize before context observation');
    my $private = abs_path(tempdir(CLEANUP => 1));
    my $sealed = eval {
        xCAT::FreeBSDPostscript::seal_source('node1', 'install', directory => "$private/store");
    };
    ok(defined($sealed), 'source sealing loads the actual owner before stock selection');
    my $loaded = $INC{'xCAT/Postage.pm'};
    my $source = abs_path("$FindBin::Bin/../../xCAT-server/lib/perl/xCAT/Postage.pm");
    ok(defined($loaded) && -f $loaded && defined($source) && abs_path($loaded) eq $source,
        'actual Postage module is the regular selected source file');
    is($::XCATROOT, "$root/stock", 'actual owner initializes the stock root from its environment');
    my $json = JSON->new->canonical->utf8;
    my $record = $sealed ? $json->decode(read_file("$sealed->{directory}/manifest.json")) : {};
    is($record->{template}{kind}, 'stock', 'initialized stock selection is sealed');
    my $rendered = $sealed ? read_file("$sealed->{directory}/rendered") : '';
    my $stock_expected = $expected;
    $stock_expected =~ s/ORIGIN='custom'/ORIGIN='stock'/;
    ok($rendered eq $stock_expected, 'same actual renderer uses the initialized stock template');
    done_testing();
};
done_testing();
