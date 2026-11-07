#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Slurper qw(read_text write_text);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Test::More;
use XCAT::Test::Process qw(run_command);
use imgutils;

plan skip_all => 'systemd condition evaluation requires Linux' unless $^O eq 'linux';
my ($analyze) = grep { -x $_ } qw(/usr/bin/systemd-analyze /bin/systemd-analyze);
BAIL_OUT('Install systemd to run this test') unless $analyze;

# systemd evaluates the drop-in's own conditions; SYSTEMD_PROC_CMDLINE stands in
# for the kernel command line of the node.
my $root = tempdir(CLEANUP => 1);
make_path("$root/usr/lib/systemd/system");
write_text("$root/usr/lib/systemd/system/kdump.service", "[Service]\n");
imgutils::skip_kdump_without_dump_memory($root);
my @conditions = grep { /^Condition/ }
  split /\n/, read_text("$root/etc/systemd/system/kdump.service.d/xcat-dump-memory.conf");
ok(@conditions, 'the drop-in carries conditions');

for my $case (
    ['crashkernel=256M quiet',                                      1, 'a crashkernel= reservation'],
    ['fadump=on fadump_reserve_mem=1G dump=nfs://192.0.2.1/dumps', 1, 'a POWER firmware-assisted dump'],
    ['quiet console=ttyS0,115200',                                  0, 'no dump memory'],
) {
    my ($cmdline, $start, $label) = @$case;
    local $ENV{SYSTEMD_PROC_CMDLINE} = $cmdline;
    my ($status, $output) = run_command($analyze, 'condition', @conditions);
    is($status == 0 ? 1 : 0, $start, ($start ? 'kdump.service starts with ' : 'kdump.service does not start with ') . $label)
      or diag($output);
}

done_testing();
