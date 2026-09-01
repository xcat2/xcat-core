#!/usr/bin/env perl
# The deb build lock (VersatusHPC/xcat-core#52).
#
# builddebs.pl builds in-place in its own checkout -- it rewrites debian/changelog and
# debian/control and runs dpkg-buildpackage inside the package directories -- so two
# builds of the SAME checkout would corrupt each other and must fail fast, while two
# builds of DIFFERENT checkouts share nothing and must run concurrently. The historic
# host-global lock got that backwards and made the devel and stable CD lanes collide.
#
# This drives the real lock. The predecessor extracted a marked region out of
# build-ubunturepo with a regex and ran that; now the lock is a function, so it is
# called directly.
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../..";
use Test::More;

use BuildUtils qw(lock_id_for take_build_lock);

my $lockdir = tempdir(CLEANUP => 1);

is( lock_id_for('/opt/builds/devel/xcat-core'),
    lock_id_for('/opt/builds/devel/xcat-core'),
    'one checkout always maps to one lock id' );
isnt( lock_id_for('/opt/builds/devel/xcat-core'),
      lock_id_for('/opt/builds/stable/xcat-core'),
      'two checkouts map to different lock ids' );
like( lock_id_for('/any/path'), qr/\A[0-9a-f]{12}\z/,
    'the id is filesystem-safe, so it can name a file' );
is( length lock_id_for(''), 12, 'an empty path still yields an id rather than dying' );

# Same checkout: the second build must be refused.
my $devel = '/opt/builds/devel/xcat-core';
my $first = take_build_lock($devel, $lockdir);
ok( $first, 'the first build of a checkout takes the lock' );

my $second = eval { take_build_lock($devel, $lockdir) };
ok( !$second, 'a second build of the SAME checkout is refused' );
like( $@, qr/already holds/, 'and says which checkout is already building' );

# Different checkout: must not be blocked by the first.
my $stable = eval { take_build_lock('/opt/builds/stable/xcat-core', $lockdir) };
ok( $stable, 'a build of a DIFFERENT checkout runs concurrently' );

# Releasing lets the next build in.
close $first;
my $again = eval { take_build_lock($devel, $lockdir) };
ok( $again, 'the lock is released when the handle is closed' );

done_testing();
