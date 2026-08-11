#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);

sub read_file {
    my ($filename) = @_;
    open( my $fh, '<', $filename )
      or die "Unable to read $filename: $!";
    my $content = do { local $/; <$fh> };
    close($fh);
    return $content;
}

my $rpm_spec = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'xCAT-server.spec' )
);
my @rpm_sha_requirements =
  $rpm_spec =~ /^Requires:.*\bperl\(Digest::SHA\)(?:\s|$)/mg;
is(
    scalar(@rpm_sha_requirements),
    2,
    'both RPM architecture branches require Digest::SHA',
);

my $debian_control = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'control' )
);
like(
    $debian_control,
    qr/^Depends:.*\blibdigest-sha-perl\b/m,
    'the Debian package requires Digest::SHA',
);

done_testing();
