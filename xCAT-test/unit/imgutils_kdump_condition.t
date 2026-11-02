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

my $dropin = 'etc/systemd/system/kdump.service.d/xcat-dump-memory.conf';
my $condition = "[Unit]\nConditionKernelCommandLine=|crashkernel\nConditionKernelCommandLine=|fadump\n";

sub image_root {
    my (%units) = @_;
    my $root = tempdir(CLEANUP => 1);
    for my $unit (keys %units) {
        make_path("$root/usr/lib/systemd/system");
        write_text("$root/usr/lib/systemd/system/$unit", $units{$unit});
    }
    return $root;
}

{
    my $root = image_root('kdump.service' => "[Service]\nExecStart=/usr/bin/kdumpctl start\n",
        'NetworkManager.service' => "[Service]\n");
    make_path("$root/etc/systemd/system/kdump.service.d");
    write_text("$root/etc/systemd/system/kdump.service.d/site.conf", "[Service]\nTimeoutSec=600\n");
    for my $pass (1, 2) {
        imgutils::skip_kdump_without_dump_memory($root);
        is(read_text("$root/$dropin"), $condition,
            "pass $pass: kdump.service runs only with crashkernel= or fadump=");
    }
    opendir(my $dh, "$root/etc/systemd/system/kdump.service.d") or die "opendir: $!";
    is_deeply([sort grep { !/^\./ } readdir($dh)], ['site.conf', 'xcat-dump-memory.conf'],
        'the drop-in is written once next to the site drop-ins');
    closedir($dh);
    is(read_text("$root/etc/systemd/system/kdump.service.d/site.conf"), "[Service]\nTimeoutSec=600\n",
        'a site drop-in is unchanged');
    ok(!-e "$root/etc/systemd/system/NetworkManager.service.d", 'other units get no drop-in');
}

{
    my $root = image_root('NetworkManager.service' => "[Service]\n");
    imgutils::skip_kdump_without_dump_memory($root);
    ok(!-e "$root/etc/systemd/system/kdump.service.d", 'an image without kdump.service is unchanged');
}

done_testing();
