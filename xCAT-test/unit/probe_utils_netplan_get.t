#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-probe/lib/perl";

use File::Temp qw(tempdir);
use Test::More;

require probe_utils;

sub write_file {
    my ($file, $contents) = @_;

    open(my $fh, '>', $file) or die "Unable to write $file: $!";
    print $fh $contents;
    close $fh;
}

sub read_file {
    my $file = shift;

    open(my $fh, '<', $file) or die "Unable to read $file: $!";
    local $/;
    my $contents = <$fh>;
    close $fh;
    return $contents;
}

my $fake_bin = tempdir(CLEANUP => 1);
my $argv_file = "$fake_bin/argv";
my $fake_netplan = "$fake_bin/netplan";

write_file($fake_netplan, <<'EOF');
#!/usr/bin/env perl
use strict;
use warnings;

open(my $fh, '>', $ENV{XCAT_TEST_NETPLAN_ARGV}) or die "Unable to record arguments: $!";
print $fh join("\n", @ARGV), "\n";
close $fh;

my $mode = $ENV{XCAT_TEST_NETPLAN_MODE} || '';
if ($mode eq 'multiple-lines') {
    print "first line\nsecond line\n";
} elsif ($mode eq 'continued-output') {
    local $| = 1;
    print "first line\n";
    local $SIG{PIPE} = 'IGNORE';
    for (1 .. 4096) {
        exit 7 unless print 'x' x 4096;
    }
} elsif ($mode eq 'empty-first-line') {
    print "\nsecond line\n";
} elsif ($mode eq 'no-trailing-newline') {
    print "single line";
} elsif ($mode eq 'empty-output') {
    exit 0;
} elsif ($mode eq 'failure') {
    print "ignored output\n";
    print STDERR "netplan get failed\n";
    exit 7;
} else {
    die "Unknown test mode: $mode";
}
EOF
chmod oct('755'), $fake_netplan;

local $ENV{PATH} = "$fake_bin:$ENV{PATH}";
local $ENV{XCAT_TEST_NETPLAN_ARGV} = $argv_file;

{
    local $ENV{XCAT_TEST_NETPLAN_MODE} = 'multiple-lines';
    is(
        probe_utils::_netplan_get('ethernets.eth0.addresses'),
        'first line',
        'netplan get returns only the first output line'
    );
    is(
        read_file($argv_file),
        "get\nethernets.eth0.addresses\n",
        'netplan get receives the exact subcommand and key arguments'
    );
}

{
    local $ENV{XCAT_TEST_NETPLAN_MODE} = 'continued-output';
    ok(
        !defined(probe_utils::_netplan_get('ethernets.eth0')),
        'a command failure after the first line still returns undef'
    );
}

{
    local $ENV{XCAT_TEST_NETPLAN_MODE} = 'empty-first-line';
    is(
        probe_utils::_netplan_get('ethernets.eth0'),
        '',
        'an empty first line remains a defined empty value'
    );
}

{
    local $ENV{XCAT_TEST_NETPLAN_MODE} = 'no-trailing-newline';
    is(
        probe_utils::_netplan_get('ethernets.eth0'),
        'single line',
        'output without a trailing newline is preserved'
    );
}

{
    local $ENV{XCAT_TEST_NETPLAN_MODE} = 'empty-output';
    ok(
        !defined(probe_utils::_netplan_get('ethernets.eth0')),
        'successful empty output returns undef'
    );
    my @values = probe_utils::_netplan_get('ethernets.eth0');
    is(scalar(@values), 1, 'successful empty output returns one undef value in list context');
    ok(!defined($values[0]), 'the list-context empty-output value is undef');
}

{
    local $ENV{XCAT_TEST_NETPLAN_MODE} = 'failure';
    ok(
        !defined(probe_utils::_netplan_get('ethernets.eth0')),
        'failed netplan get returns undef even when it writes output'
    );
    my @values = probe_utils::_netplan_get('ethernets.eth0');
    is(scalar(@values), 0, 'failed netplan get returns an empty list in list context');
}

{
    my $missing_bin = tempdir(CLEANUP => 1);
    local $ENV{PATH} = $missing_bin;
    my $value = probe_utils::_netplan_get('ethernets.eth0');
    my $status = $?;

    ok(!defined($value), 'netplan exec failure returns undef');
    is($status >> 8, 1, 'netplan exec failure preserves its original exit status');
}

done_testing();
