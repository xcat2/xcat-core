#!/usr/bin/env perl
# The URLs the Subiquity templates fetch from carry the master as a URI host.
#
# They were built as "http://#XCATVAR:XCATMASTER##COLONHTTPPORT#/install/autoinst/...", and
# that tag renders the bare value. For an IPv6-only node that is a literal address, so wget
# read the last group as a port:
#
#   wget -T 30 -O /tmp/getinstdisk http://2001:db8:147::1/install/autoinst/getinstdisk
#   http://2001:db8:147::1/install/autoinst/getinstdisk: Bad port number.
#
# The early-commands script runs under "set -eux", so that one line failed the whole script,
# subiquity reported CalledProcessError from Early/run, and the install stopped before curtin.
#
# The templates are the artifact here, so they are read. #MASTERURIHOST# renders through
# format_uri_host, which networkutils_ipv6_helpers.t covers.
use strict;
use warnings;

use File::Slurper qw(read_text);
use File::Spec;
use FindBin;
use Test::More;

my $root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

foreach my $kind (qw(compute service)) {
    my $tmpl = File::Spec->catfile( $root, 'xCAT-server', 'share', 'xcat', 'install',
        'ubuntu', "$kind.subiquity.tmpl" );
    SKIP: {
        skip "$kind.subiquity.tmpl not found", 4 unless -f $tmpl;
        my $text = read_text($tmpl);

        # Every http:// URL in the template takes the URI host, never the bare tag.
        my @urls = $text =~ m{(http://#[A-Z:]+#[^ '"]*)}g;
        ok( scalar(@urls), "$kind template builds at least one URL" );
        my @bare = grep { m{^http://#XCATVAR:XCATMASTER#} } @urls;
        is_deeply( \@bare, [],
            "$kind template builds no URL from the bare master value" );
        my @uri = grep { m{^http://#MASTERURIHOST#} } @urls;
        is( scalar(@uri), scalar(@urls),
            "$kind template builds every URL from the URI host" );

        # /dev/tcp takes a bare host, so that one keeps the bare tag.
        like( $text, qr{xm=#XCATVAR:XCATMASTER#},
            "$kind template still gives /dev/tcp the unbracketed host" );
    }
}

# The tag has to be substituted, or it reaches the node as text.
my $pm = File::Spec->catfile( $root, 'xCAT-server', 'lib', 'perl', 'xCAT', 'Template.pm' );
SKIP: {
    skip 'Template.pm not found', 1 unless -f $pm;
    ok( index( read_text($pm), 's/#MASTERURIHOST#/$master_uri_host/' ) >= 0,
        'Template.pm substitutes the tag' );
}

done_testing();
