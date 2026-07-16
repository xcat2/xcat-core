#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir($FindBin::Bin, '..', '..')
);

foreach my $spec ('xCAT/xCAT.spec', 'xCATsn/xCATsn.spec') {
    my $source = read_file($spec);
    like(
        $source,
        qr{
            Requires:\ /usr/sbin/dhcpd\n
            %if\ 0%\{\?rhel\}\ ==\ 8\n
            \#\ EL8[^\n]*\n
            Requires:\ dhcp-server\ >=\ 12:4\.3\.6-48\n
            %endif
        }x,
        "$spec requires the EL8 non-MD5 OMAPI backport"
    );
}

done_testing();

sub read_file {
    my ($file) = @_;
    my $path = File::Spec->catfile($repo_root, split m{/}, $file);
    open(my $fh, '<', $path) or die "open $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh) or die "close $path: $!";
    return $contents;
}
