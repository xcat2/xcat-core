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
our ($TARGET, @SEEN, %FAIL, %FAIL_FROM, %FAIL_AFTER, $NO_LINK);
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
        # A rename into a path of %FAIL_AFTER fails after the number of renames into it that the value gives.
        if ($FAIL{$to} || $FAIL_FROM{$from} || (defined($FAIL_AFTER{$to}) && $FAIL_AFTER{$to}-- <= 0)) {
            delete $FAIL{$to};
            delete $FAIL_FROM{$from};
            delete $FAIL_AFTER{$to} if defined($FAIL_AFTER{$to}) && $FAIL_AFTER{$to} < 0;
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
    if (!$case{first}) {
        write_text($TARGET, "previous archive\n");
        write_text("$TARGET.sha256", "previous checksum\n") if !$case{unchecked};
        write_text("$TARGET.metainfo", "previous metainfo\n");
    }
    write_text("$stage/rootimg.cpio.gz", "new archive\n");
    write_text("$stage/rootimg.cpio.gz.sha256", "new checksum\n") if $case{checksum};
    write_text("$stage/rootimg.cpio.gz.metainfo", "new metainfo\n") if $case{metainfo};
    local %FAIL = map { ("$dir/$_" => 1) } @{ $case{fail} || [] };
    local %FAIL_FROM = map { ("$stage/$_" => 1) } @{ $case{fail_from} || [] };
    local %FAIL_AFTER = map { ("$dir/$_->[0]" => $_->[1]) } @{ $case{fail_after} || [] };
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

for my $failed (qw(rootimg.cpio.gz rootimg.cpio.gz.metainfo)) {
    # No archive was published before, as for the first pack or a change of format.
    my ($error, $dir, $target) = publish(checksum => 1, metainfo => 1, first => 1, fail => [$failed]);
    like($error, qr/^Cannot publish \Q$target\E: /, "a failed rename to $failed of a first archive is reported");
    is_deeply([ grep { -e $_ } map { "$target$_" } ('', '.sha256', '.metainfo') ], [],
        "a failed rename to $failed leaves no archive, checksum or metainfo where none was");
    is_deeply([ glob("$dir/.rootimg-previous-*") ], [], "a failed rename to $failed of a first archive keeps no previous archive");
    ok(!-e "$dir/.packimage-publish", "the publication lock is released after a failed rename to $failed of a first archive");
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

{
    # The previous metainfo cannot go back after a failed publication, and staging cleanup would delete it.
    my ($error, $dir, $target) = publish(checksum => 1, metainfo => 1, fail => ['rootimg.cpio.gz.metainfo'], fail_from => ['previous.metainfo']);
    like($error // '', qr/the previous metainfo cannot be put back: .*It is kept in \Q$dir\E\/\.rootimg-previous-/,
        'a previous metainfo that cannot go back is reported with the directory that keeps it');
    my ($kept) = ($error // '') =~ /It is kept in (\S+)/;
    is($kept && read_binary("$kept/rootimg.cpio.gz.metainfo"), "previous metainfo\n", 'the kept directory holds the previous metainfo');
    is(read_binary($target), "previous archive\n", 'the previous archive goes back');
}

{
    # The previous checksum cannot go back after a failed publication.
    my ($error, $dir, $target) = publish(checksum => 1, metainfo => 1, fail => ['rootimg.cpio.gz.metainfo'],
        fail_after => [ [ 'rootimg.cpio.gz.sha256', 1 ] ]);
    like($error // '', qr/the previous checksum cannot be put back: /, 'a previous checksum that cannot go back is reported');
    is(read_binary($target), "previous archive\n", 'the previous archive goes back when its checksum cannot');
}

{
    # The previous archive can neither go back nor move out of staging, so staging stays when its owner drops it.
    my $dir = "$fixture/retained";
    make_path($dir);
    write_text("$dir/rootimg.cpio.gz", "previous archive\n");
    my ($stage) = xCAT::SvrUtils->rootimg_stage($dir);
    my $path = "$stage";
    write_text("$path/rootimg.cpio.gz",          "new archive\n");
    write_text("$path/rootimg.cpio.gz.metainfo", "new metainfo\n");
    my $error;
    {
        no warnings 'redefine';
        local *File::Temp::tempdir = sub { die "No space left on device\n" };
        local %FAIL      = ("$dir/rootimg.cpio.gz.metainfo" => 1);
        local %FAIL_FROM = ("$path/previous"                => 1);
        $error = xCAT::SvrUtils->publish_rootimg("$path/rootimg.cpio.gz", "$dir/rootimg.cpio.gz");
    }
    like($error // '', qr/the previous archive cannot be put back: .*It is kept in \Q$path\E$/,
        'a previous archive that only staging keeps is reported with the staging directory');
    undef $stage;
    is(-e "$path/previous" && read_binary("$path/previous"), "previous archive\n", 'staging keeps the previous archive when its owner drops it');
    xCAT::SvrUtils->remove_abandoned_rootimg_stages($dir);
    ok(-e "$path/previous", 'the removal of abandoned stages keeps staging that holds the previous archive');
    xCAT::SvrUtils->remove_abandoned_rootimg_stages($dir, 1);
    ok(!-e $path, 'the removal of all stages, as rmimage asks for, removes it too');
}

{
    # A publication that succeeds leaves no previous file in staging, so staging that its owner left is abandoned.
    my $dir = "$fixture/succeeded";
    make_path($dir);
    write_text("$dir/rootimg.cpio.gz",          "previous archive\n");
    write_text("$dir/rootimg.cpio.gz.metainfo", "previous metainfo\n");
    my ($stage) = xCAT::SvrUtils->rootimg_stage($dir);
    my $path = "$stage";
    write_text("$path/rootimg.cpio.gz", "new archive\n");
    is(xCAT::SvrUtils->publish_rootimg("$path/rootimg.cpio.gz", "$dir/rootimg.cpio.gz"), undef, 'a publication from staging succeeds');
    is_deeply([ grep { -e "$path/$_" } qw(previous previous.metainfo) ], [], 'staging holds no previous file after the publication');

    # The owner is killed and leaves staging behind.
    $stage->unlink_on_destroy(0);
    undef $stage;
    xCAT::SvrUtils->remove_abandoned_rootimg_stages($dir);
    ok(!-e $path, 'the removal of abandoned stages removes staging that holds no previous file');
}

for my $failed ('rootimg.cpio.gz', 'rootimg.cpio.gz.metainfo') {
    # The published checksum is a relative symlink, and the publication fails after it wrote the checksum list.
    my $dir = "$fixture/symlink-rollback-" . ($failed =~ s/\W/-/gr);
    make_path("$dir/releases", "$dir/.stage");
    write_text("$dir/rootimg.cpio.gz",          "previous archive\n");
    write_text("$dir/rootimg.cpio.gz.metainfo", "previous metainfo\n");
    write_text("$dir/releases/v1.sha256",       "checksum of v1\n");
    symlink('releases/v1.sha256', "$dir/rootimg.cpio.gz.sha256") or die $!;
    write_text("$dir/.stage/rootimg.cpio.gz", "new archive\n");
    write_text("$dir/.stage/rootimg.cpio.gz.$_", "new $_\n") for qw(sha256 metainfo);
    my $error;
    {
        local %FAIL = ("$dir/$failed" => 1);
        $error = xCAT::SvrUtils->publish_rootimg("$dir/.stage/rootimg.cpio.gz", "$dir/rootimg.cpio.gz");
    }
    like($error // '', qr/^Cannot publish /, "a failed rename to $failed is reported");
    unlike($error // '', qr/cannot be put back/, "after a failed rename to $failed, the previous files go back");
    is(readlink("$dir/rootimg.cpio.gz.sha256"), 'releases/v1.sha256', "after a failed rename to $failed, the checksum symlink goes back");
    is(read_binary("$dir/releases/v1.sha256"), "checksum of v1\n", "after a failed rename to $failed, the file of the symlink keeps its content");
    is(read_binary("$dir/rootimg.cpio.gz"), "previous archive\n", "after a failed rename to $failed, the previous archive goes back");
}

{
    # The checksum symlink cannot go back after a failed publication, so its previous content goes back instead.
    my $dir = "$fixture/symlink-content";
    make_path("$dir/releases", "$dir/.stage");
    write_text("$dir/rootimg.cpio.gz",          "previous archive\n");
    write_text("$dir/rootimg.cpio.gz.metainfo", "previous metainfo\n");
    write_text("$dir/releases/v1.sha256",       "checksum of v1\n");
    symlink('releases/v1.sha256', "$dir/rootimg.cpio.gz.sha256") or die $!;
    write_text("$dir/.stage/rootimg.cpio.gz", "new archive\n");
    write_text("$dir/.stage/rootimg.cpio.gz.$_", "new $_\n") for qw(sha256 metainfo);
    my $error;
    {
        local %FAIL       = ("$dir/rootimg.cpio.gz.metainfo" => 1);
        local %FAIL_AFTER = ("$dir/rootimg.cpio.gz.sha256"   => 1);
        $error = xCAT::SvrUtils->publish_rootimg("$dir/.stage/rootimg.cpio.gz", "$dir/rootimg.cpio.gz");
    }
    like($error // '', qr/the previous checksum cannot be put back: .*Its previous content went back instead/,
        'a checksum symlink that cannot go back is reported');
    is(read_binary("$dir/rootimg.cpio.gz.sha256"), "checksum of v1\n", 'the previous checksum content goes back instead');
}

{
    # glob splits a pattern at a space, so the first word of an image directory with a space named another path.
    my $dir = "$fixture/custom images/node";
    make_path("$fixture/custom/keep", $dir);
    my ($stage) = xCAT::SvrUtils->rootimg_stage($dir);
    my $path = "$stage";
    $stage->unlink_on_destroy(0);
    undef $stage;
    xCAT::SvrUtils->remove_abandoned_rootimg_stages($dir);
    ok(!-e $path, 'an abandoned stage in an image directory with a space is removed');
    ok(-d "$fixture/custom/keep", 'the directory that the first word of the image directory names stays');

    $dir = "$fixture/other images/node";
    make_path("$dir/.stage");
    write_text("$fixture/other", "file that the first word of the image directory names\n");
    write_text("$dir/rootimg.tar.xz", "archive in another format\n");
    write_text("$dir/.stage/rootimg.cpio.gz", "new archive\n");
    is(xCAT::SvrUtils->publish_rootimg("$dir/.stage/rootimg.cpio.gz", "$dir/rootimg.cpio.gz", 1), undef,
        'an archive is published in an image directory with a space');
    ok(!-e "$dir/rootimg.tar.xz", 'the archive in another format is removed from the image directory with a space');
    ok(-e "$fixture/other", 'the file that the first word of the image directory names stays');
}

done_testing();
