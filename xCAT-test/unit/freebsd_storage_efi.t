#!/usr/bin/env perl
use strict;
use warnings;

use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Process qw(run_command);

my $directory = $ENV{XCAT_FREEBSD_INSTALLER_DIR}
    || repo_path('xCAT-server/share/xcat/install/freebsd');
my $root = tempdir(CLEANUP => 1);
my $prefix = 'xe' . ('a' x 32);

sub write_file {
    my ($path, $data) = @_;
    open(my $fh, '>', $path) or croak "$path: $!";
    print {$fh} $data or croak "$path: $!";
    close($fh) or croak "$path: $!";
    return;
}

sub read_file {
    my ($path) = @_;
    open(my $fh, '<', $path) or croak "$path: $!";
    local $/ = undef;
    my $data = <$fh>;
    close($fh) or croak "$path: $!";
    return $data // '';
}

make_path("$root/bin");
write_file("$root/bin/sha256", "#!$^X\n" . <<'HASH');
use strict;
use warnings;
use Digest::SHA;
die 'Expected sha256 -q file' unless @ARGV == 2 && shift(@ARGV) eq '-q';
print Digest::SHA->new(256)->addfile($ARGV[0])->hexdigest, "\n";
HASH
chmod(0755, "$root/bin/sha256") == 1 or croak "chmod: $!";
write_file("$root/primary.sh", <<'SHELL');
#!/bin/sh
set -eu
. "$1/xcat-install-lib.sh"
. "$1/xcat-storage-efi.sh"
storage_root=$2/target storage_work=$2/job storage_tmpdir=$2/tmp
storage_count=$3 storage_prefix=$4
storage_primary=/dev/gpt/${storage_prefix}0
storage_efi_label=xcat-test storage_phase=mounted storage_efi_stage=unstarted
PATH_FSTAB=$2/fstab
# Supply the already-validated storage state without operating on native disks.
storage_paths() { :; }
storage_check() { :; }
storage_mounts() { :; }
storage_fstab() { :; }
sysctl() { [ "$*" = '-n machdep.efi_arch' ]; printf 'amd64\n'; }
storage_efi_snapshot() { mkdir "$1"; : > "$1/entries"; }
storage_release() { : > "$storage_work/released"; }
storage_efi_primary "$PATH_FSTAB" "$storage_root/boot/efi"
SHELL

sub primary_case {
    my ($name, $count, $kind, $contents, $accepted) = @_;
    subtest $name => sub {
        my $case = tempdir(DIR => $root, CLEANUP => 1);
        make_path("$case/target/boot/efi", "$case/job", "$case/tmp");
        write_file("$case/target/boot/loader.efi", 'native-loader');
        write_file("$case/fstab", 'validated-fstab');
        write_file("$case/sentinel", 'preserved');
        my $list = "$case/tmp/bsdinstall-esps";
        if ($kind eq 'file') {
            write_file($list, $contents);
        } elsif ($kind eq 'link' || $kind eq 'dangling') {
            my $target = $kind eq 'link' ? "$case/sentinel" : "$case/missing";
            symlink($target, $list) or croak "symlink: $!";
        } elsif ($kind eq 'directory') {
            make_path($list);
        }
        local $ENV{PATH} = "$root/bin:$ENV{PATH}";
        my ($status, $output) = run_command('/bin/sh', "$root/primary.sh",
            $directory, $case, $count, $prefix);
        if ($accepted) {
            is($status, 0, 'primary ESP preparation succeeds');
            is($output, "/dev/gpt/${prefix}0\n", 'returns the primary ESP');
            ok(-f "$case/job/released", 'releases the validated operation');
            SKIP: {
                skip 'ESP list was not accepted', 2 if $status;
                is(read_file($list), $contents, 'retains the complete extra-ESP selection');
                is(read_file("$case/job/efi-esps"), sha256_hex($contents) . "\n",
                    'pins the actual extra-ESP bytes');
            }
        } else {
            isnt($status, 0, 'rejects the extra-ESP state');
            is($output, '', 'does not return an approved ESP');
            ok(!-e "$case/job/released", 'does not release the operation');
            ok(!-e "$case/job/efi-before", 'does not inspect firmware after rejection');
            ok(!-e $list, 'does not fabricate missing redundant ESPs') if $kind eq 'missing';
            is(read_file($list), $contents, 'does not rewrite a rejected list') if $kind eq 'file';
            ok(-l $list, 'does not replace a symlink') if $kind eq 'link' || $kind eq 'dangling';
        }
        is(read_file("$case/sentinel"), 'preserved', 'leaves unrelated content unchanged');
        ok(!-e "$case/missing", 'does not create a dangling link target');
    };
    return;
}

primary_case('single disk without an extra-ESP file', 1, 'missing', '', 1);
primary_case('single disk with an empty extra-ESP file', 1, 'file', '', 1);
primary_case('single disk with an unexpected extra ESP', 1, 'file', "/dev/gpt/${prefix}1\n", 0);
primary_case('single disk with a symlink', 1, 'link', '', 0);
primary_case('single disk with a dangling symlink', 1, 'dangling', '', 0);
primary_case('single disk with a directory', 1, 'directory', '', 0);
primary_case('mirror without an extra-ESP file', 2, 'missing', '', 0);
primary_case('mirror with an empty extra-ESP file', 2, 'file', '', 0);
primary_case('mirror with its extra ESP', 2, 'file', "/dev/gpt/${prefix}1\n", 1);
primary_case('three disks with both extra ESPs', 3, 'file', "/dev/gpt/${prefix}1\n/dev/gpt/${prefix}2\n", 1);
primary_case('three disks with an incomplete list', 3, 'file', "/dev/gpt/${prefix}1\n", 0);
primary_case('three disks with reordered ESPs', 3, 'file', "/dev/gpt/${prefix}2\n/dev/gpt/${prefix}1\n", 0);

done_testing();
