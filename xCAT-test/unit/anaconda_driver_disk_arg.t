#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(getcwd);
use File::Slurper qw(write_text);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $plugin = repo_path('xCAT-server/lib/xcat/plugins/anaconda.pm');
plan skip_all => 'anaconda.pm not found' unless -r $plugin;
$ENV{XCATROOT} ||= repo_path('xCAT-server');
require $plugin;

my $tempdir = tempdir(CLEANUP => 1);
my $initrd = File::Spec->catfile($tempdir, 'initrd.img');
my $driver_disk = File::Spec->catfile($tempdir, 'vendor-dd.img');
write_text($initrd, "base initrd\n");
write_text($driver_disk, "driver disk\n");
my $base_size = -s $initrd;

sub insert_driver_disk {
    my ($source, $fail_archive) = @_;
    my $cwd = getcwd();
    my @inserted;
    my @messages;
    {
        no warnings qw(redefine once);
        my $real_runcmd = \&xCAT::Utils::runcmd;
        local *xCAT::TableUtils::getInstallDir = sub { return $tempdir; };
        local *xCAT::MsgUtils::message = sub {
            my $rsp = $_[2];
            push @messages, @{ $rsp->{data} || [] };
            return;
        };
        local *xCAT::Utils::runcmd = sub {
            my ($class, $command, @arguments) = @_;
            if ($fail_archive && $command =~ /cpio -H newc -o/) {
                $::RUNCMD_RC = 1;
                return;
            }
            return $real_runcmd->($class, $command, @arguments);
        };
        @inserted = xCAT_plugin::anaconda::insert_dd(
            sub { return; },
            'rhels9.6', 'x86_64', $initrd, undef,
            $source, '', '', 0,
        );
    }
    chdir($cwd) or die "Unable to restore $cwd: $!";
    return ( \@inserted, \@messages );
}

my ($inserted) = insert_driver_disk("dud:$driver_disk");
is_deeply($inserted, [$driver_disk], 'insert_dd reports the driver disk it appended');
cmp_ok(-s $initrd, '>', $base_size, 'the driver disk archive is appended to the initrd');

my $marker = xCAT_plugin::anaconda::_driver_disk_marker_path($initrd);
ok(-f $marker, 'successful injection records the driver disk beside the initrd');

is(
    xCAT_plugin::anaconda::_driver_disk_kernel_arg('6.10', $initrd),
    '',
    'anaconda before 7 continues to auto-load the embedded driver disk',
);
is(
    xCAT_plugin::anaconda::_driver_disk_kernel_arg('9.6', $initrd),
    ' inst.dd=/dd.img',
    'anaconda 7 and newer is given the inst.dd argument it reads',
);
write_text($initrd, "reused initrd\n");
is(
    xCAT_plugin::anaconda::_driver_disk_kernel_arg('9.6', $initrd),
    ' inst.dd=/dd.img',
    'a later nodeset --noupdateinitrd run reuses the persistent marker',
);

write_text($initrd, "fresh initrd\n");
my ($without_disk) = insert_driver_disk(undef);
is_deeply($without_disk, [], 'an image without a driver disk reports no insertion');
ok(!-e $marker, 'rebuilding without a driver disk clears a stale marker');
is(
    xCAT_plugin::anaconda::_driver_disk_kernel_arg('9.6', $initrd),
    '',
    'an image without an injected driver disk receives no kernel argument',
);

my $missing_disk = File::Spec->catfile($tempdir, 'missing-dd.img');
my ($failed, $copy_messages) = insert_driver_disk("dud:$missing_disk");
is_deeply($failed, [], 'a driver disk that cannot be copied is not reported as inserted');
like(join("\n", @{$copy_messages}), qr/Could not copy the driver disk/, 'the failed copy takes the expected error path');
ok(!-e $marker, 'failed injection leaves no driver disk marker');

($inserted) = insert_driver_disk("dud:$driver_disk");
ok(-f $marker, 'the marker exists before an archive failure is exercised');
my ($archive_failed, $archive_messages) = insert_driver_disk("dud:$driver_disk", 1);
is_deeply($archive_failed, [], 'a driver disk that cannot be archived is not reported as inserted');
like(join("\n", @{$archive_messages}), qr/Could not archive the driver disk/, 'the failed archive takes the expected error path');
ok(!-e $marker, 'a failed driver disk archive leaves no marker');

ok(
    xCAT_plugin::anaconda::_set_driver_disk_marker(undef, 0),
    'clearing a marker for an unavailable initrd is a no-op',
);

done_testing();
