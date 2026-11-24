#!/usr/bin/env perl
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use Errno qw(EIO EPERM);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

our ($FAIL, $OWNER);
BEGIN {
    *CORE::GLOBAL::close = sub (*) {
        my $result = CORE::close($_[0]);
        if (($FAIL // '') eq 'close' && caller eq $OWNER) {
            $! = EIO;
            return 0;
        }
        return $result;
    };
    *CORE::GLOBAL::chmod = sub {
        if (($FAIL // '') eq 'chmod' && caller eq $OWNER) {
            $! = EPERM;
            return 0;
        }
        return CORE::chmod($_[0], @_[1 .. $#_]);
    };
    *CORE::GLOBAL::rename = sub ($$) {
        if (($FAIL // '') eq 'rename' && caller eq $OWNER) {
            $! = EIO;
            return 0;
        }
        return CORE::rename($_[0], $_[1]);
    };
}
require xCAT::SvrUtils;

sub entries {
    my ($dir) = @_;
    opendir(my $handle, $dir) or die "$dir: $!";
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir($handle);
    closedir($handle) or die $!;
    return \@names;
}

subtest 'checksum publication' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $image = "$dir/rootimg.gz";
    my $target = "$image.sha256";
    for my $bytes ('', '0', "binary\0image\xff\n") {
        write_binary($image, $bytes);
        is(xCAT::SvrUtils->write_rootimg_checksum($image), undef, 'checksum publication succeeds');
        is(scalar(read_binary($target)), sha256_hex($bytes) . "  rootimg.gz\n", 'checksum bytes are unchanged');
        is((stat($target))[2] & 07777, 0644, 'published checksum is readable');
    }
    for my $fault (qw(close chmod rename)) {
        write_binary($target, 'previous checksum');
        chmod(0640, $target) or die $!;
        local ($FAIL, $OWNER) = ($fault, 'xCAT::SvrUtils');
        like(xCAT::SvrUtils->write_rootimg_checksum($image), qr/^Cannot write \Q$target\E: /,
            "$fault failure is returned");
        is(scalar(read_binary($target)), 'previous checksum', "$fault failure keeps previous bytes");
        is((stat($target))[2] & 07777, 0640, "$fault failure keeps previous permissions");
        is_deeply(entries($dir), [qw(rootimg.gz rootimg.gz.sha256)], "$fault failure leaves no staging file");
    }
    SKIP: {
        skip 'permission denial requires an unprivileged user', 3 unless $>;
        chmod(0500, $dir) or die $!;
        my $error = xCAT::SvrUtils->write_rootimg_checksum($image);
        chmod(0700, $dir) or die $!;
        like($error, qr/^Cannot write \Q$target\E: /, 'creation failure is returned, not thrown');
        is(scalar(read_binary($target)), 'previous checksum', 'creation failure preserves published bytes');
        is_deeply(entries($dir), [qw(rootimg.gz rootimg.gz.sha256)], 'creation failure leaves no staging file');
    }
    for my $kind (qw(file symlink)) {
        my $old_temp = "$target.$$";
        write_binary("$dir/unrelated", 'leave this alone');
        if ($kind eq 'symlink') {
            symlink('unrelated', $old_temp) or die $!;
        } else {
            write_binary($old_temp, 'other writer');
        }
        is(xCAT::SvrUtils->write_rootimg_checksum($image), undef, "$kind at an old staging name does not block publication");
        is(scalar(read_binary("$dir/unrelated")), 'leave this alone', "$kind does not redirect the write");
        ok(-e $old_temp, "$kind at the old staging name is retained");
        is(-e $old_temp ? scalar(read_binary($old_temp)) : undef,
            $kind eq 'symlink' ? 'leave this alone' : 'other writer', "$kind retains its contents");
        is_deeply(entries($dir), ['rootimg.gz', 'rootimg.gz.sha256', "rootimg.gz.sha256.$$", 'unrelated'],
            'only owned staging files are removed');
        unlink($old_temp) if -e $old_temp || -l $old_temp;
        unlink("$dir/unrelated") or die $!;
    }
};

done_testing();
