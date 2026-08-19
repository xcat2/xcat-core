#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

sub slurp {
    my ($rel) = @_;
    my $path = File::Spec->catfile( $repo_root, $rel );
    return unless -r $path;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $c = do { local $/; <$fh> };
    close($fh);
    return $c;
}

my $syncfiles  = slurp('xCAT-server/lib/xcat/plugins/syncfiles.pm');
my $updatenode = slurp('xCAT-server/lib/xcat/plugins/updatenode.pm');
my $xdsh       = slurp('xCAT-server/lib/xcat/plugins/xdsh.pm');

plan skip_all => 'plugins not found'
  unless defined($syncfiles) && defined($updatenode) && defined($xdsh);

# The xdcp subrequest has to state the identity the sync runs as.
my ($call) = $syncfiles =~ /(\$subreq->\(\{[^}]*command\s*=>\s*\['xdcp'\][^}]*\})/s;
ok( $call, 'the xdcp subrequest was located in syncfiles' )
  or BAIL_OUT('syncfiles.pm no longer matches the expected subrequest shape');

like( $call, qr/username\s*=>/, 'the xdcp subrequest names a username' );

# It must be an array reference. A bare string was the original form of this
# change and broke the non-hierarchical path, because the consumers index it as
# $request->{username}->[0].
like(
    $call,
    qr/username\s*=>\s*\['root'\]/,
    'the username is the arrayref form the consumers index into'
);
unlike(
    $call,
    qr/username\s*=>\s*'root'\s*,/,
    'the username is not a bare string, which would not survive ->[0]'
);

# The consumers this has to satisfy, pinned so the shape cannot drift apart.
like(
    $xdsh,
    qr/\$ENV\{DSH_FROM_USERID\}\s*=\s*\$request->\{username\}->\[0\]/,
    'xdsh still derives DSH_FROM_USERID from the request username'
);

# updatenode makes the same xdcp call and already passes a username. The two
# should not diverge again.
like(
    $updatenode,
    qr/command\s*=>\s*\["xdcp"\][^;]*username\s*=>/s,
    'updatenode still passes a username on its own xdcp call'
);

done_testing();
