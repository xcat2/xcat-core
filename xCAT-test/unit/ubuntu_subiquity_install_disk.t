#!/usr/bin/env perl
# The storage config a Subiquity install receives for each linuximage.partitionfile form.
#
# The node's pre-install script is rendered through the production Template entry point,
# as debian.pm renders <node>.pre, and its part from base64decode to the end is executed.
# Subiquity runs that script under dash, so dash runs it here when it is installed.
use strict;
use warnings;
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

plan skip_all => 'pre-install scripts require Linux' unless $^O eq 'linux';
plan skip_all => 'requires python3 with PyYAML, as the Subiquity live system has'
    if system('python3 -c "import yaml" >/dev/null 2>&1');
my ($shell) = grep { -x $_ } qw(/usr/bin/dash /bin/dash /bin/sh);
my $tmp = tempdir(CLEANUP => 1);
make_path("$tmp/db", "$tmp/bin");
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "SQLite:$tmp/db";
require xCAT::Table;
require xCAT::Template;
%::XCATSITEVALS = (xcatdebugmode => 0, nodestatus => 0, httpport => 80, xcatiport => 3002);
my $site = xCAT::Table->new('site', -create => 1);
for my $key (keys %::XCATSITEVALS) {
    $site->setAttribs({key => $key}, {value => $::XCATSITEVALS{$key}});
}
$site->close();

sub write_file {
    my ($path, $contents) = @_;
    open(my $fh, '>', $path) or die "$path: $!";
    print {$fh} $contents;
    close($fh) or die "$path: $!";
}
sub read_file {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "$path: $!";
    local $/;
    return <$fh> // '';
}
write_file("$tmp/bin/logger", "#!/bin/sh\nexit 0\n");
write_file("$tmp/bin/uname", "#!/bin/sh\necho x86_64\n");
chmod 0755, "$tmp/bin/logger", "$tmp/bin/uname";

# Written as PyYAML writes it, so it reads the same before and after the pre-script rewrites it.
my $layout = "storage:\n  version: 1\n  config:\n  - id: custom-disk\n    type: disk\n    path: /dev/disk/by-id/custom\n";
my $writer = "#!/bin/sh\ncat > \"\$XCAT_DISK_FIXTURE/tmp/partitionfile\" <<'EOF'\n${layout}EOF\n";

# Each case: label, the partitionfile entries as [prefix, file contents], and the disk the
# storage config must name. FIXTURE stands for the case's fixture directory. getinstdisk has
# already chosen /dev/sdz in every case.
my $diskscript = "#!/bin/sh\necho /dev/disk/by-id/scripted > \"\$XCAT_DISK_FIXTURE/tmp/xcat.install_disk\"\n";
my @cases = (
    ['no partitionfile', [], '/dev/sdz'],
    ['a disk file', [['d:', "/dev/disk/by-id/nvme-pinned /dev/sdb\n"]], '/dev/disk/by-id/nvme-pinned'],
    ['a disk file naming a link', [['d:', "FIXTURE/dev/disk/by-id/nvme-link\n"]], 'FIXTURE/dev/nvme7n1'],
    ['a disk script', [['s:d:', $diskscript]], '/dev/disk/by-id/scripted'],
    ['a layout file', [['', $layout]], '/dev/disk/by-id/custom'],
    ['a layout script', [['s:', $writer]], '/dev/disk/by-id/custom'],
);
for my $case (@cases) {
    my ($label, $entries, $expected) = @$case;
    subtest $label => sub {
        my $fixture = tempdir(DIR => $tmp, CLEANUP => 1);
        make_path("$fixture/tmp", "$fixture/sys/firmware/efi", "$fixture/dev/disk/by-id");
        write_file("$fixture/tmp/xcat.install_disk", "/dev/sdz\n");
        write_file("$fixture/dev/nvme7n1", '');
        symlink('../../nvme7n1', "$fixture/dev/disk/by-id/nvme-link") or die $!;
        $expected =~ s/FIXTURE/$fixture/;
        my @partitionfile;
        for my $n (0 .. $#$entries) {
            my ($prefix, $contents) = @{ $entries->[$n] };
            $contents =~ s/FIXTURE/$fixture/g;
            write_file("$fixture/partition-$n", $contents);
            push @partitionfile, "$prefix$fixture/partition-$n";
        }
        my $partitionfile = join(',', @partitionfile);
        my $error = xCAT::Template->subvars(repo_path('xCAT-server/share/xcat/install/scripts/pre.ubuntu.subiquity'),
            "$fixture/node.pre", 'node', '', '', '', $partitionfile, {xcatmaster => '192.0.2.1'});
        ok(!$error, 'renders through the production Template entry point') or diag($error);
        my ($part) = read_file("$fixture/node.pre") =~ /(^base64decode\(\)\n.*^exit 0$)/ms;
        ok($part, 'the rendered script defines base64decode before the partitioning') or return;
        $part =~ s{(?<![[:alnum:]_/])/(tmp|sys)(?=/)}{$fixture/$1}g;
        write_file("$fixture/part.sh", $part);
        local %ENV = (%ENV, PATH => "$tmp/bin:/usr/bin:/bin", XCAT_DISK_FIXTURE => $fixture);
        my $output = `$shell $fixture/part.sh 2>&1`;
        is($?, 0, "the partitioning runs under $shell") or diag($output);
        my $config = read_file("$fixture/tmp/partitionfile");
        my ($disk) = $config =~ /^\s+type: disk\n(?:\s+\S+:.*\n)*?\s+path: (\S+)$/m;
        is($disk, $expected, "the storage config partitions $expected");
        is($config, $layout, 'the administrator layout replaces the default one') if $expected eq '/dev/disk/by-id/custom';
    };
}
done_testing();
