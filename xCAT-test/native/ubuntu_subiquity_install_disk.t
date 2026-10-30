#!/usr/bin/env perl
# The storage config a Subiquity install receives for each linuximage.partitionfile form.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);
use XCAT::Test::Template qw(template_database render_template);

plan skip_all => 'installer execution requires Linux namespaces' unless $^O eq 'linux';
my $database = template_database();
# Subiquity runs its early commands under dash.
my ($shell) = grep { -x $_ } qw(/usr/bin/dash /bin/dash /bin/sh);
my $sequence = 0;

sub render_part {
    my ($script, $pattern, @entries) = @_;
    my $dir = "$database/case-" . ++$sequence;
    make_path($dir);
    my @partitionfile;
    for my $n (0 .. $#entries) {
        my ($prefix, $contents) = @{ $entries[$n] };
        write_text("$dir/partition-$n", $contents);
        push @partitionfile, "$prefix$dir/partition-$n";
    }
    render_template($database, repo_path("xCAT-server/share/xcat/install/scripts/$script"), "$dir/node.pre",
        'node', '', '', '', join(',', @partitionfile), {xcatmaster => '192.0.2.1'});
    my ($part) = read_text("$dir/node.pre") =~ $pattern;
    return $part;
}

# getinstdisk has already chosen /dev/sdz.
sub installer_root {
    my $root = sandbox_root();
    make_path("$root/efi", "$root/by-id");
    write_text("$root/bin/logger", "#!/bin/sh\nexit 0\n");
    chmod 0755, "$root/bin/logger" or die $!;
    write_text("$root/tmp/xcat.install_disk", "/dev/sdz\n");
    write_text("$root/nvme7n1", '');
    symlink('../../nvme7n1', "$root/by-id/nvme-link") or die $!;
    return $root;
}

sub storage_config {
    my ($root) = @_;
    return -e "$root/tmp/partitionfile" ? read_text("$root/tmp/partitionfile") : '';
}

# Written as PyYAML writes it, so it reads the same before and after the pre-script rewrites it.
my $layout = "storage:\n  version: 1\n  config:\n  - id: custom-disk\n    type: disk\n    path: /dev/disk/by-id/custom\n";
my $writer = "#!/bin/sh\ncat >/tmp/partitionfile <<'EOF'\n${layout}EOF\n";
my $diskscript = "#!/bin/sh\necho /dev/disk/by-id/scripted >/tmp/xcat.install_disk\n";

# Each case: label, the partitionfile entries as [prefix, file contents], and the disk the storage
# config must name.
my @cases = (
    ['no partitionfile', [], '/dev/sdz'],
    ['a disk file', [['d:', "/dev/disk/by-id/nvme-pinned /dev/sdb\n"]], '/dev/disk/by-id/nvme-pinned'],
    ['a disk file naming a link', [['d:', "/dev/disk/by-id/nvme-link\n"]], '/dev/nvme7n1'],
    ['a disk script', [['s:d:', $diskscript]], '/dev/disk/by-id/scripted'],
    ['a layout file', [['', $layout]], '/dev/disk/by-id/custom'],
    ['a layout script', [['s:', $writer]], '/dev/disk/by-id/custom'],
);
for my $case (@cases) {
    my ($label, $entries, $expected) = @$case;
    subtest $label => sub {
        my $part = render_part('pre.ubuntu.subiquity', qr/(^base64decode\(\)\n.*^exit 0$)/ms, @$entries);
        ok($part, 'the rendered script defines base64decode before the partitioning') or return;
        my $root = installer_root();
        write_text("$root/part.sh", $part);
        my ($rc, $output) = sandbox_run($root, {read_only => {"$root/efi" => '/sys/firmware/efi',
            "$root/by-id" => '/dev/disk/by-id', "$root/nvme7n1" => '/dev/nvme7n1'}}, $shell, '/fixture/part.sh');
        is($rc, 0, "the partitioning runs under $shell") or diag($output);
        my $config = storage_config($root);
        my ($disk) = $config =~ /^\s+type: disk\n(?:\s+\S+:.*\n)*?\s+path: (\S+)$/m;
        is($disk, $expected, "the storage config partitions $expected");
        is($config, $layout, 'the administrator layout replaces the default one') if $expected eq '/dev/disk/by-id/custom';
    };
}
done_testing();
