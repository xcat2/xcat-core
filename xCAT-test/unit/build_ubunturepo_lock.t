#!/usr/bin/env perl
#
# Unit test for the build-ubunturepo build lock (issue VersatusHPC/xcat-core#52).
#
# build-ubunturepo builds its packages in-place in its own source checkout, so the
# resource two concurrent builds contend for is the checkout -- not the host. The lock
# is therefore keyed on the checkout path ($curdir): builds of the SAME checkout
# fail-fast (they would corrupt each other), builds of DISTINCT checkouts get distinct
# locks and run in parallel (this is what lets the devel and stable Ubuntu CD lanes
# build concurrently on one host).
#
# The test extracts the two marked regions from build-ubunturepo VERBATIM so it
# exercises the real code, not a copy:
#   * build-lock-id      -- derives LOCKFILE from $curdir (pure string computation)
#   * build-lock-acquire -- opens fd 8 on LOCKFILE and flock -n's it (needs a writable
#                           lock dir; skipped with a diag where /var/lock isn't writable)

use strict;
use warnings;

use FindBin;
use File::Temp qw(tempdir tempfile);
use IPC::Open2;
use Test::More;

my $script = "$FindBin::Bin/../../build-ubunturepo";
ok( -f $script, "found build-ubunturepo at $script" )
  or BAIL_OUT("build-ubunturepo not found");

my $src = do { local ( @ARGV, $/ ) = $script; <> };

my $workdir = tempdir( CLEANUP => 1 );    # scratch for temp scripts + capture files

# --- pull the two marked regions out of the script verbatim -----------------
sub region {
    my ($name) = @_;
    my ($body) = $src =~ /^# BEGIN \Q$name\E\n(.*?)^# END \Q$name\E\n/ms;
    ok( defined $body, "extracted the '$name' region from build-ubunturepo" )
      or BAIL_OUT("marker region '$name' missing -- did the lock block change?");
    return $body;
}
my $id_region      = region('build-lock-id');
my $acquire_region = region('build-lock-acquire');

# Write a self-contained shell program (the given region(s) + a tail) to a temp file
# and return its path. Using a file avoids any quoting of the extracted shell.
my $prog_seq = 0;
sub write_prog {
    my ($body) = @_;
    my $path = "$workdir/prog." . $prog_seq++ . ".sh";
    open( my $fh, '>', $path ) or die "write $path: $!";
    print $fh "set -eu\ncurdir=\"\$1\"\n$body";
    close $fh;
    return $path;
}

sub lockfile_for {
    my ($curdir) = @_;
    my $prog = write_prog( "$id_region\nprintf '%s\\n' \"\$LOCKFILE\"\n" );
    my $out = qx{bash --noprofile --norc "$prog" "$curdir"};
    chomp $out;
    return $out;
}

# --- LOCKFILE derivation (always runnable -- no filesystem writes) -----------
subtest 'lock is scoped per checkout, under /var/lock' => sub {
    my $a  = tempdir( CLEANUP => 1 );
    my $b  = tempdir( CLEANUP => 1 );
    my $la = lockfile_for($a);
    my $lb = lockfile_for($b);

    like( $la, qr{^/var/lock/xcatbld-[0-9a-f]{12}\.lock$},
        'LOCKFILE is /var/lock/xcatbld-<hash>.lock' );
    is( lockfile_for($a), $la, 'same checkout => same lock (deterministic)' );
    isnt( $la, $lb, 'distinct checkouts => distinct locks' );

    # the derivation must not create anything inside the checkout itself
    ok( !glob("$a/*") && !glob("$a/.*xcatbld*"),
        'source checkout is left byte-pristine (no lock file written into it)' );
};

# --- flock contention (needs a writable lock dir) ---------------------------
# The acquire region hard-codes /var/lock; run it only where that is writable
# (the GitHub Actions runner's /run/lock is sticky world-writable). Elsewhere,
# skip these two with a diag rather than failing on the environment.
my $probe = "/var/lock/.xcatbld-selftest.$$";
my $lock_writable = open( my $pf, '>', $probe );
if ($lock_writable) { close $pf; unlink $probe; }

SKIP: {
    skip "/var/lock is not writable here -- flock contention subtests need it", 2
      unless $lock_writable;

    # Launch a holder that acquires the lock for $curdir and blocks (holding fd 8)
    # until we send it a newline on stdin. Returns ($pid, $to_child, $from_child, $first).
    my $hold_prog = write_prog(
        "$id_region\n$acquire_region\nprintf 'ACQUIRED %s\\n' \"\$LOCKFILE\"\nIFS= read -r _ || true\n"
    );
    my $holder = sub {
        my ($curdir) = @_;
        my $pid = open2( my $out, my $in, 'bash', '--noprofile', '--norc',
            $hold_prog, $curdir );
        my $first = <$out>;    # blocks until the holder has the lock (or died)
        return ( $pid, $in, $out, $first );
    };

    # A contender that tries to acquire and, if it gets past the lock, prints MARK.
    my $try_prog = sub {
        my ($mark) = @_;
        return write_prog(
            "$id_region\n$acquire_region\nprintf '%s\\n' '$mark'\n" );
    };
    my $run = sub {
        my ( $prog, $curdir ) = @_;
        my $cap = "$workdir/cap." . $prog_seq++ . ".out";
        my $rc  = system("bash --noprofile --norc \"$prog\" \"$curdir\" >\"$cap\" 2>&1");
        my $out = do { local ( @ARGV, $/ ) = $cap; <> };
        $out = '' unless defined $out;
        return ( $rc, $out );
    };

    subtest 'same checkout: second build fails fast' => sub {
        my $dir = tempdir( CLEANUP => 1 );
        my ( $pid, $in, $out, $first ) = $holder->($dir);
        like( $first, qr/^ACQUIRED /, 'first build acquired the checkout lock' )
          or BAIL_OUT('holder never acquired -- cannot test contention');

        my ( $rc, $output ) = $run->( $try_prog->('SHOULD_NOT_REACH'), $dir );
        isnt( $rc, 0, 'second build of the SAME checkout exits non-zero' );
        like( $output, qr/Can't get lock/, 'it reports the lock contention' );
        like( $output, qr/\Q$dir\E/, 'the error names the contended checkout' );
        unlike( $output, qr/SHOULD_NOT_REACH/, 'it did not proceed into the build' );

        print $in "\n"; close $in;    # release the holder
        waitpid( $pid, 0 );
    };

    subtest 'distinct checkouts: both build in parallel' => sub {
        my $dir_a = tempdir( CLEANUP => 1 );
        my $dir_b = tempdir( CLEANUP => 1 );
        my ( $pid, $in, $out, $first ) = $holder->($dir_a);
        like( $first, qr/^ACQUIRED /, 'checkout A acquired its lock' );

        # while A still holds its lock, B (a different checkout) must acquire too
        my ( $rc, $output ) = $run->( $try_prog->('B_ACQUIRED'), $dir_b );
        is( $rc, 0, 'the other checkout acquires concurrently (exit 0)' );
        like( $output, qr/B_ACQUIRED/, 'it ran past the lock while A held its own' );
        unlike( $output, qr/Can't get lock/, 'no contention between distinct checkouts' );

        print $in "\n"; close $in;
        waitpid( $pid, 0 );
    };
}

done_testing;
