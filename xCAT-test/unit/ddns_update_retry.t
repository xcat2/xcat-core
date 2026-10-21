#!/usr/bin/env perl

# send_ddns_update retries a rejected dynamic DNS update. Net::DNS appends the TSIG to the
# additional section, so every attempt must sign its own request: named answers FORMERR to a
# message that carries two TSIG records (measured on BIND 9.18.33).
#
# Run this test with XCATROOT set to the tree under test. xCAT::Table does
# "use lib $::XCATROOT/lib/perl", so an installed /opt/xcat shadows the modules under test:
#   XCATROOT=$PWD/xCAT-server prove xCAT-test/unit/ddns_update_retry.t

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

$ENV{XCATCFG}  ||= 'SQLite:/tmp';
$ENV{XCATROOT} ||= "$FindBin::Bin/../../xCAT-server";

my $ddns_plugin_path =
  "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/ddns.pm";
if ( -f $ddns_plugin_path ) {
    require $ddns_plugin_path;
}
else {
    require xCAT_plugin::ddns;
}

my $SECRET = 'c2VjcmV0LXNlY3JldC1zZWNyZXQtc2VjcmV0LXNlY3I=';
my $ZONE   = 'test.lab';

subtest 'every attempt of a rejected update carries one TSIG' => sub {
    my $resolver = Local::DDNS::Resolver->new( replies => [ 'NOTAUTH', 'NOTAUTH', 'NOTAUTH' ] );
    my $rc = send_update($resolver);

    is( $rc, 1, 'a persistently rejected update reports failure' );
    is( scalar( @{ $resolver->{sent} } ), 3, 'the update is sent three times' );
    is_deeply(
        [ map { $_->{tsig_count} } @{ $resolver->{sent} } ],
        [ 1, 1, 1 ],
        'each attempt carries exactly one TSIG record'
    );
    is_deeply(
        [ map { $_->{updates} } @{ $resolver->{sent} } ],
        [ ( ['n1.test.lab. 300 IN A 10.0.0.1'] ) x 3 ],
        'each attempt carries the same update records'
    );
};

subtest 'a retry can be accepted' => sub {
    my $resolver = Local::DDNS::Resolver->new( replies => [ 'NOTAUTH', 'NOERROR' ] );
    my $rc = send_update($resolver);

    is( $rc, 0, 'the accepted retry reports success' );
    is( scalar( @{ $resolver->{sent} } ), 2, 'the update is sent twice' );
};

done_testing();

#---------------------------------------------------------------------------

=head3 send_update

    Description: Send one dynamic DNS update through send_ddns_update.
    Arguments:   the recording resolver
    Returns:     the send_ddns_update return code

=cut

#---------------------------------------------------------------------------
sub send_update {
    my ($resolver) = @_;

    my $settings = xCAT::DHCP::OmapiPolicy->settings(
        site_values => {
            dhcpomapialgorithm => 'hmac-sha256',
            dhcpomapikeyname   => undef,
            dhcpomshellpath    => undef,
        }
    );
    die "Unusable OMAPI settings: $settings->{error}" if $settings->{error};

    my $ctx = {
        omapi_settings => $settings,
        privkey        => $SECRET,
    };

    my $update = Net::DNS::Update->new($ZONE);
    $update->push( update => Net::DNS::RR->new('n1.test.lab. 300 IN A 10.0.0.1') );

    no warnings qw(redefine once);
    local *xCAT::SvrUtils::sendmsg = sub { return; };

    # Net::DNS 1.36 removed sign_tsig($name, $secret) and signs from a key file. Report the
    # version that signs from a KEY RR, so the test needs no key file.
    local $Net::DNS::VERSION = '1.25';
    return xCAT_plugin::ddns::send_ddns_update( $ctx, $resolver, $update, $ZONE, 'n1.test.lab' );
}

{

    package Local::DDNS::Resolver;

    # Answer FORMERR to a message with more than one TSIG record, as named does, and otherwise
    # answer the next scripted rcode.
    sub new {
        my ( $class, %args ) = @_;
        return bless { replies => $args{replies}, sent => [] }, $class;
    }

    sub send {
        my ( $self, $packet ) = @_;

        my @tsig = grep { $_->type eq 'TSIG' } $packet->additional;
        push @{ $self->{sent} },
          {
            tsig_count => scalar(@tsig),
            updates    => [ map { $_->plain } $packet->authority ],
          };

        my $rcode = shift @{ $self->{replies} };
        $rcode = 'SERVFAIL' unless defined $rcode;
        $rcode = 'FORMERR' if @tsig > 1;
        return Local::DDNS::Reply->new($rcode);
    }
}

{

    package Local::DDNS::Reply;

    sub new {
        my ( $class, $rcode ) = @_;
        return bless { rcode => $rcode }, $class;
    }

    sub header { return $_[0]; }

    sub rcode { return $_[0]->{rcode}; }
}
