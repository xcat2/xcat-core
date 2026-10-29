#!/usr/bin/env perl
# getpostscript correlates a node-initiated request to a node. When the reverse lookup of the
# peer socket fails, the CN of the validated client certificate is the only other identity.
# A password or token login, and the request's own node attribute, must never select a node.
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;
use lib File::Spec->catdir($FindBin::Bin, '..', '..', 'perl-xCAT'),
  File::Spec->catdir($FindBin::Bin, '..', '..', 'xCAT-server', 'lib', 'perl');
use xCAT::DiscoveryUtils;

# Ninety xCAT modules put "$::XCATROOT/lib/perl" in @INC, so an installed product can shadow
# the checkout. Say which file answered.
my $under_test = $INC{'xCAT/DiscoveryUtils.pm'} // '';
ok(length $under_test, 'xCAT::DiscoveryUtils was loaded at all');
unlike($under_test, qr{^/opt/xcat/}, "the module under test is this checkout's, not an installed one ($under_test)");
can_ok('xCAT::DiscoveryUtils', qw(request_client_names request_client_node client_certificate_name));

sub names_for { return xCAT::DiscoveryUtils::request_client_names($_[0]) }

# --- client_certificate_name: what xcatd records as _xcat_certname -------------------------

is(xCAT::DiscoveryUtils::client_certificate_name('xcat59-cn', 'xcat59-cn'), 'xcat59-cn',
   'a request authenticated by its certificate records the certificate CN');
is(xCAT::DiscoveryUtils::client_certificate_name(undef, 'compute'), undef,
   'a token or password login without a certificate records no certificate name');
is(xCAT::DiscoveryUtils::client_certificate_name('root', 'compute'), undef,
   'becomeuser to another account records no certificate name');
is(xCAT::DiscoveryUtils::client_certificate_name('', ''), undef,
   'an empty certificate CN is not a name');

# --- request_client_names: the names logged and tried -------------------------------------

is_deeply([ names_for({ _xcat_clienthost => ['xcat58-cn'],
                        _xcat_clientfqdn => ['xcat58-cn.xcat58.lab'],
                        _xcat_certname   => ['xcat58-cn'] }) ],
          [ 'xcat58-cn', 'xcat58-cn.xcat58.lab' ],
          'the resolved peer host comes first, and the certificate name adds no duplicate');

is_deeply([ names_for({ _xcat_clienthost => [''],
                        _xcat_clientfqdn => [''],
                        _xcat_certname   => ['xcat59-cn'] }) ],
          [ 'xcat59-cn' ],
          'an empty peer host is skipped and the certificate name is offered instead');

is_deeply([ names_for({ _xcat_clientfqdn => ['xcat59-cn.xcat59.lab'] }) ],
          [ 'xcat59-cn.xcat59.lab' ],
          'the fully qualified peer name is offered when the short name is missing');

is_deeply([ names_for({ _xcat_clienthost => [''], _xcat_authname => ['compute'] }) ], [],
          'the authenticated name of a password or token login is never offered');

for my $request ({ node => ['xcat59-cn'] },
                 { node => ['xcat59-cn'], _xcat_clienthost => [''] },
                 { node => ['some-other-node'], _xcat_certname => ['xcat59-cn'] }) {
    my @got = names_for($request);
    ok(!grep({ $_ eq ($request->{node}->[0]) } @got),
       "the request's own node attribute is never offered as an identity ("
       . join(',', @got) . ')');
}

is_deeply([ names_for({}) ],        [], 'a request with no identity at all offers no name');
is_deeply([ names_for(undef) ],     [], 'an undefined request offers no name');
is_deeply([ names_for('string') ],  [], 'a request that is not a hash offers no name');
my @unwrapped = eval { names_for({ _xcat_clienthost => 'xcat59-cn' }) };
is($@, '', 'a value xcatd did not wrap in an array ref does not kill the lookup');
is_deeply(\@unwrapped, [], 'and is ignored rather than dereferenced');

# --- request_client_node: the node selected -------------------------------------------------

# node01 and node02 are nodes, compute is a group of both.
my %groups = (compute => [qw(node01 node02)]);
my %nodes  = map { $_ => 1 } qw(node01 node02);
sub expand {
    my ($range) = @_;
    return @{ $groups{$range} } if $groups{$range};
    return ('node01', 'node02') if $range eq 'node0[1-2]';
    return $nodes{$range} ? ($range) : ();
}
sub node_for { return xCAT::DiscoveryUtils::request_client_node($_[0], \&expand) }

is(node_for({ _xcat_clienthost => ['node01'] }), 'node01', 'a resolved peer host selects its node');
is(node_for({ _xcat_clienthost => [''], _xcat_certname => ['node02'] }), 'node02',
   'a certificate CN that names exactly one node selects it');
is(node_for({ _xcat_clienthost => [''], _xcat_certname => ['compute'] }), undef,
   'a certificate CN that names a group selects no node');
is(node_for({ _xcat_clienthost => [''], _xcat_certname => ['node0[1-2]'] }), undef,
   'a certificate CN that is a node range selects no node');
is(node_for({ _xcat_clienthost => [''], _xcat_certname => ['nosuchnode'] }), undef,
   'a certificate CN that is not a node selects no node');
is(node_for({ _xcat_clienthost => [''], _xcat_authname => ['node01'] }), undef,
   'the authenticated name alone selects no node');
is(node_for({ _xcat_clienthost => ['node01'], _xcat_certname => ['node02'] }), 'node01',
   'the resolved peer host wins over the certificate CN');

# --- the plugin -----------------------------------------------------------------------------

require File::Spec->catfile($FindBin::Bin, '..', '..', 'xCAT-server', 'lib', 'xcat', 'plugins', 'getpostscript.pm');
require xCAT::Postage;

sub served {
    my ($request) = @_;
    my @served;
    no warnings qw(redefine once);
    local $::XCATSITEVALS{nodeauthentication} = 0;
    local *xCAT_plugin::getpostscript::noderange = \&expand;
    local *xCAT::Postage::makescript = sub { push @served, @{ $_[0] }; return ('#script') };
    local *xCAT::MsgUtils::trace = sub { };
    xCAT_plugin::getpostscript::process_request(
        { command => ['getpostscript'], node => [], %$request }, sub { });
    return @served;
}

is_deeply([ served({ _xcat_clienthost => [''], _xcat_authname => ['compute'] }) ], [],
          'the plugin serves no node to a password or token login named after a group');
is_deeply([ served({ _xcat_clienthost => [''], _xcat_authname => ['node01'] }) ], [],
          'the plugin serves no node to a password or token login named after a node');
is_deeply([ served({ _xcat_clienthost => [''], _xcat_certname => ['compute'] }) ], [],
          'the plugin serves no node to a certificate named after a group');
is_deeply([ served({ _xcat_clienthost => [''], _xcat_certname => ['node02'] }) ], ['node02'],
          'the plugin serves the node its certificate names when the reverse lookup fails');
is_deeply([ served({ _xcat_clienthost => ['node01'] }) ], ['node01'],
          'the plugin serves the node its peer host resolves to');

done_testing();
