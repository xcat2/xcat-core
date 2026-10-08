#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Digest::SHA qw(sha256_hex);
use Errno qw(EACCES);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

our ($fail_rename, $rename_calls);
BEGIN {
    *CORE::GLOBAL::rename = sub ($$) {
        if ($fail_rename && ++$rename_calls == $fail_rename) {
            $! = EACCES;
            return 0;
        }
        return CORE::rename($_[0], $_[1]);
    };
}

my $root = tempdir(CLEANUP => 1);
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "$root/config";
make_path($ENV{XCATCFG});
require(repo_path('xCAT-server/lib/xcat/plugins/mknb.pm'));
my @sources = qw(kernel initramfs.cpio.gz xcat-genesis.manifest);
my @destinations = qw(genesis.kernel.x86_64 genesis.fs.x86_64.gz genesis.exact-arch.x86_64);
my @contents = ('new kernel', 'new initrd', "format=xcat-genesis\nversion=1\narchitecture=x86_64\n");

sub fixture {
    my ($name, $existing) = @_;
    my $dir = "$root/$name";
    make_path("$dir/export", "$dir/tftp/xcat");
    my @sums;
    for my $index (0..2) {
        write_text("$dir/export/$sources[$index]", $contents[$index]);
        push @sums, sha256_hex($contents[$index]) . "  $sources[$index]\n";
        if ($existing) {
            write_text("$dir/tftp/xcat/$destinations[$index]", "old $index");
            chmod oct('604'), "$dir/tftp/xcat/$destinations[$index]" or die $!;
        }
    }
    write_text("$dir/export/SHA256SUMS", join('', @sums));
    return $dir;
}

sub entries {
    my ($directory) = @_;
    opendir(my $handle, $directory) or die $!;
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir($handle);
    closedir($handle) or die $!;
    return \@names;
}

my $old_umask = umask oct('027');
for my $existing (0, 1) {
    for my $failure (0..3) {
        subtest "existing=$existing rename failure=$failure" => sub {
            my $dir = fixture("rename-$existing-$failure", $existing);
            local $fail_rename = $failure;
            local $rename_calls = 0;
            my ($result, $error) = xCAT_plugin::mknb::_install_prebuilt_genesis("$dir/export", "$dir/tftp", 'x86_64');
            if ($failure) {
                is($result, undef, 'failed publication returns no initrd');
                like($error, qr/^Unable to install Genesis artifact:/, 'publication failure is reported');
            } else {
                is($error, undef, 'publication succeeds');
                is($result, "$dir/tftp/xcat/genesis.fs.x86_64.gz", 'published initrd path is returned');
            }
            my $present = $existing || !$failure;
            is_deeply(entries("$dir/tftp/xcat"), $present ? [sort @destinations] : [],
                'only complete published artifacts remain');
            if ($present) {
                for my $index (0..2) {
                    my $path = "$dir/tftp/xcat/$destinations[$index]";
                    is(read_text($path), $failure ? "old $index" : $contents[$index],
                        'artifact content is installed or rolled back');
                    my $mode = !$failure ? oct('644')
                        : $index < $failure - 1 ? oct('640') : oct('604');
                    is((stat($path))[2] & oct('777'), $mode,
                        'rollback keeps the existing copy-and-rename mode behavior');
                }
            }
        };
    }
}

my $copy = \&xCAT_plugin::mknb::copy;
for my $failure (1..6) {
    subtest "copy failure=$failure" => sub {
        my $dir = fixture("copy-$failure", 1);
        my $copies = 0;
        no warnings 'redefine';
        local *xCAT_plugin::mknb::copy = sub {
            return 0 if ++$copies == $failure;
            return $copy->(@_);
        };
        my ($result, $error) = xCAT_plugin::mknb::_install_prebuilt_genesis("$dir/export", "$dir/tftp", 'x86_64');
        is($result, undef, 'copy failure returns no initrd');
        like($error, qr/^Unable to (?:stage|preserve) Genesis artifact:/, 'copy failure is reported');
        is_deeply(entries("$dir/tftp/xcat"), [sort @destinations], 'copy failure leaves no staging entries');
        for my $index (0..2) {
            is(read_text("$dir/tftp/xcat/$destinations[$index]"), "old $index", 'copy failure preserves published content');
        }
    };
}

SKIP: {
    skip 'root can write mode-500 directories', 5 if $< == 0;
    my $dir = fixture('unwritable-destination', 1);
    chmod oct('500'), "$dir/tftp/xcat" or die $!;
    my ($result, $error) = xCAT_plugin::mknb::_install_prebuilt_genesis("$dir/export", "$dir/tftp", 'x86_64');
    chmod oct('700'), "$dir/tftp/xcat" or die $!;
    is($result, undef, 'an unwritable destination returns no initrd');
    like($error, qr/^Unable to stage Genesis artifact:/, 'staging allocation failure is reported');
    is_deeply(entries("$dir/tftp/xcat"), [sort @destinations], 'staging allocation failure leaves no partial files');
    for my $defect ('symlink', 'checksum') {
        my $invalid = fixture("invalid-$defect", 1);
        my $expected;
        if ($defect eq 'symlink') {
            rename("$invalid/export/kernel", "$invalid/linked-kernel") or die $!;
            symlink('../linked-kernel', "$invalid/export/kernel") or die $!;
            $expected = "Missing Genesis artifact: $invalid/export/kernel";
        } else {
            write_text("$invalid/export/SHA256SUMS", join('',
                map { sha256_hex($contents[$_]) . "  $sources[$_]\n" } (1, 2)));
            $expected = 'Missing Genesis checksum entry: kernel';
        }
        chmod oct('500'), "$invalid/tftp/xcat" or die $!;
        my (undef, $invalid_error) = xCAT_plugin::mknb::_install_prebuilt_genesis("$invalid/export", "$invalid/tftp", 'x86_64');
        chmod oct('700'), "$invalid/tftp/xcat" or die $!;
        is($invalid_error, $expected, 'artifact validation still precedes staging allocation');
    }
}
umask $old_umask;

done_testing();
