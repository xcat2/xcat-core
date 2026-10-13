#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_text);
use Digest::SHA qw(sha256_hex);
use Errno qw(EIO ENOSPC EPERM);
use File::Temp qw(tempdir);
use Test::More;

# Nodes may fetch at any moment, so the test records the checksum and metainfo when the archive is renamed.
# The first rename into a path of %FAIL, or from a path of %FAIL_FROM, fails, as when the file system refuses it.
# With $NO_LINK, link fails, as on a file system without hard links.
# Nodes may also be killed publishers, so the checksum file must list the archive at each rename of it.
our ($TARGET, @SEEN, %FAIL, %FAIL_FROM, $NO_LINK);
BEGIN {
    *CORE::GLOBAL::link = sub {
        my ($from, $to) = @_;
        if ($NO_LINK) {
            $! = EPERM;
            return 0;
        }
        return CORE::link($from, $to);
    };
    *CORE::GLOBAL::rename = sub {
        my ($from, $to) = @_;
        if (defined $TARGET && $to eq $TARGET) {
            my $checksum = -f "$TARGET.sha256" ? read_binary("$TARGET.sha256") : -e "$TARGET.sha256" ? 'other' : 'missing';
            push @SEEN, { checksum => $checksum, metainfo => -e "$TARGET.metainfo" ? 1 : 0 };
        }
        if ($FAIL{$to} || $FAIL_FROM{$from}) {
            delete $FAIL{$to};
            delete $FAIL_FROM{$from};
            $! = EIO;
            return 0;
        }
        return CORE::rename($from, $to);
    };
}
require xCAT::SvrUtils;

my $fixture  = tempdir(CLEANUP => 1);
my $sequence = 0;

sub publish {
    my (%case) = @_;
    my $dir   = "$fixture/image-" . ++$sequence;
    my $stage = "$dir/.stage";
    make_path($stage);
    local $TARGET = "$dir/rootimg.cpio.gz";
    write_text($TARGET, "previous archive\n");
    write_text("$TARGET.sha256", "previous checksum\n") if !$case{unchecked};
    write_text("$TARGET.metainfo", "previous metainfo\n");
    write_text("$stage/rootimg.cpio.gz", "new archive\n");
    write_text("$stage/rootimg.cpio.gz.sha256", "new checksum\n") if $case{checksum};
    write_text("$stage/rootimg.cpio.gz.metainfo", "new metainfo\n") if $case{metainfo};
    local %FAIL = map { ("$dir/$_" => 1) } @{ $case{fail} || [] };
    local %FAIL_FROM = map { ("$stage/$_" => 1) } @{ $case{fail_from} || [] };
    local $NO_LINK = $case{no_link};
    no warnings 'redefine';
    local *File::Copy::copy = sub { $! = ENOSPC; return 0 } if $case{no_copy};
    @SEEN = ();
    my $mask = umask($case{umask} // umask());
    my $error = xCAT::SvrUtils->publish_rootimg("$stage/rootimg.cpio.gz", $TARGET);
    umask($mask);
    return ($error, $dir, $TARGET);
}

{
    my ($error, $dir, $target) = publish(checksum => 1);
    is($error, undef, 'a staged archive and checksum are published');
    is_deeply(\@SEEN, [ { checksum => "new checksum\nprevious checksum\n", metainfo => 0 } ],
        'while the archive is replaced, the checksum file lists the new and the previous archive, and the previous metainfo is gone');
    is(read_binary($target), "new archive\n", 'the new archive is published');
    is(read_binary("$target.sha256"), "new checksum\n", 'then the checksum file lists only the new archive');
    ok(!-e "$target.metainfo", 'the previous metainfo is removed');
    ok(!-e "$dir/.packimage-publish", 'the publication lock is released');
}

{
    my ($error, $dir, $target) = publish(checksum => 1, unchecked => 1);
    is($error, undef, 'an archive packed before the check is replaced');
    is_deeply(\@SEEN, [ { checksum => "new checksum\n" . sha256_hex("previous archive\n") . "  rootimg.cpio.gz\n", metainfo => 0 } ],
        'while an archive packed before the check is replaced, the checksum file also lists it');
    is(read_binary("$target.sha256"), "new checksum\n", 'then the checksum file lists only the new archive');
}

{
    my ($error, $dir, $target) = publish();
    is($error, undef, 'a staged archive without a checksum is published');
    is_deeply(\@SEEN, [ { checksum => 'missing', metainfo => 0 } ],
        'a previous checksum without a successor is gone when the archive is replaced');
    ok(!-e "$target.sha256", 'no checksum is left for the new archive');
}

for my $failed (qw(rootimg.cpio.gz rootimg.cpio.gz.metainfo)) {
    my ($error, $dir, $target) = publish(checksum => 1, metainfo => 1, fail => [$failed]);
    like($error, qr/^Cannot publish \Q$target\E: /, "a failed rename to $failed is reported");
    is(read_binary($target), "previous archive\n", "a failed rename to $failed leaves the previous archive");
    is(read_binary("$target.sha256"), "previous checksum\n", "a failed rename to $failed leaves the previous checksum");
    is(read_binary("$target.metainfo"), "previous metainfo\n", "a failed rename to $failed leaves the previous metainfo");
    ok(!-e "$dir/.packimage-publish", "the publication lock is released after a failed rename to $failed");
}

{
    my ($error, $dir, $target) = publish(checksum => 1, fail => ['rootimg.cpio.gz.sha256']);
    like($error, qr/^Cannot publish \Q$target\E: /, 'a checksum list that cannot be written is reported');
    is(read_binary($target), "previous archive\n", 'the previous archive stays when the checksum list cannot be written');
    is(read_binary("$target.sha256"), "previous checksum\n", 'the previous checksum stays when the checksum list cannot be written');
}

{
    my ($error, $dir, $target) = publish(checksum => 1, fail_from => ['rootimg.cpio.gz.sha256']);
    is($error, undef, 'a checksum file that keeps the previous line does not fail the publication');
    is(read_binary($target), "new archive\n", 'the new archive is published');
    is(read_binary("$target.sha256"), "new checksum\nprevious checksum\n", 'the checksum file still lists the new archive');
}

{
    my ($error, $dir, $target) = publish(checksum => 1, unchecked => 1, fail => ['rootimg.cpio.gz']);
    like($error, qr/^Cannot publish \Q$target\E: /, 'a failure over an archive packed before the check is reported');
    is(read_binary($target), "previous archive\n", 'the previous archive stays');
    ok(!-e "$target.sha256", 'the checksum file of the new archive goes, as the previous archive had none');
}

{
    my ($error, $dir, $target) = publish(checksum => 1, metainfo => 1, no_link => 1, fail => ['rootimg.cpio.gz.metainfo']);
    like($error, qr/^Cannot publish \Q$target\E: /, 'a failure without hard links is reported');
    is(read_binary($target), "previous archive\n", 'a copy puts the previous archive back without hard links');
    is(read_binary("$target.sha256"), "previous checksum\n", 'the previous checksum stays without hard links');
}

{
    my ($error, $dir, $target) = publish(checksum => 1, metainfo => 1, fail => ['rootimg.cpio.gz.metainfo'], fail_from => ['previous']);
    my ($kept) = ($error // '') =~ /cannot be put back: .*It is kept in (\S+)$/;
    ok($kept, 'a previous archive that cannot be put back is reported with the directory that keeps it');
    is(read_binary($target), "new archive\n", 'the new archive stays when the previous one cannot be put back');
    is(read_binary("$kept/rootimg.cpio.gz"), "previous archive\n", 'the previous archive is kept');
    is(read_binary("$kept/rootimg.cpio.gz.metainfo"), "previous metainfo\n", 'the previous metainfo is kept');
    is(read_binary("$kept/rootimg.cpio.gz.sha256"), "previous checksum\n", 'the previous checksum is kept');
    unlike($kept, qr{/\.stage/}, 'the kept files are outside the staging directory that is removed');
}

{
    my ($error, $dir, $target) = publish(checksum => 1, metainfo => 1, no_link => 1, no_copy => 1);
    like($error, qr/^Cannot publish \Q$target\E: /, 'an archive that cannot be kept for a rollback is reported');
    is(read_binary($target), "previous archive\n", 'nothing is published when the previous archive cannot be kept');
    is(read_binary("$target.sha256"), "previous checksum\n", 'the previous checksum stays when the previous archive cannot be kept');
    is(read_binary("$target.metainfo"), "previous metainfo\n", 'the previous metainfo stays when the previous archive cannot be kept');
}

{
    # packimage publishes under umask 0077, so a copy of the previous archive must keep its mode.
    my ($error, $dir, $target) = publish(checksum => 1, metainfo => 1, no_link => 1, umask => 077, fail => ['rootimg.cpio.gz.metainfo']);
    like($error, qr/^Cannot publish \Q$target\E: /, 'a failure under umask 0077 without hard links is reported');
    is(read_binary($target), "previous archive\n", 'the copy puts the previous archive back');
    is((stat($target))[2] & 07777, 0666 & ~umask(), 'the previous archive keeps the mode that nodes read it with');
}

done_testing();
