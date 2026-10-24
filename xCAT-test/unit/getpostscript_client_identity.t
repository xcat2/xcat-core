#!/usr/bin/env perl
# A diskless node that boots and cannot be correlated to a node gets no postscripts, and that
# costs the whole provision: remoteshell never installs root's authorized_keys, so every xdsh and
# ssh answers "Permission denied (publickey)" on a node that answers ping, and nothing ever
# reports "booted".
#
# Measured on xcat59-mn, an openEuler 22.03sp4 management node, on 2026-10-24. xcatd logged
# "xCAT: Allowing getpostscript xcat59-cn" with no "from <peerhost>" and then "Received malformed
# getpostscript requesting, ignore it." -- 100 times, 0 "Sending scripts data" in the whole log,
# against 3 sends and 0 malformed on the green openEuler 24.03sp4 cell beside it. The client
# certificate named the node correctly; only the reverse lookup of the peer socket failed, and
# getpostscript.pm looked at nothing else.
#
# So the identity a request offers is its own decision, and this is it. The request hash is the
# only input and a list of names is the only output, so it is driven directly.
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;
use lib File::Spec->catdir($FindBin::Bin, '..', '..', 'perl-xCAT'),
  File::Spec->catdir($FindBin::Bin, '..', '..', 'xCAT-server', 'lib', 'perl');
use xCAT::DiscoveryUtils;

sub names_for { return xCAT::DiscoveryUtils::request_client_names($_[0]) }

# The resolved peer stays first, so a management node whose reverse lookup works behaves exactly
# as it did.
is_deeply([ names_for({ _xcat_clienthost => ['xcat58-cn'],
                        _xcat_clientfqdn => ['xcat58-cn.xcat58.lab'],
                        _xcat_authname   => ['xcat58-cn'] }) ],
          [ 'xcat58-cn', 'xcat58-cn.xcat58.lab' ],
          'the resolved peer host comes first, and the certificate name adds no duplicate');

# The failure measured on xcat59-mn: xcatd set the peer host to the empty string, because the
# reverse lookup returned nothing. An empty name is not a name.
is_deeply([ names_for({ _xcat_clienthost => [''],
                        _xcat_clientfqdn => [''],
                        _xcat_authname   => ['xcat59-cn'] }) ],
          [ 'xcat59-cn' ],
          'an empty peer host is skipped and the certificate name is offered instead');

# The same request with the keys absent rather than empty.
is_deeply([ names_for({ _xcat_authname => ['xcat59-cn'] }) ], [ 'xcat59-cn' ],
          'a request carrying only a certificate name still identifies its node');

# The fqdn alone is enough when the short name did not resolve.
is_deeply([ names_for({ _xcat_clientfqdn => ['xcat59-cn.xcat59.lab'] }) ],
          [ 'xcat59-cn.xcat59.lab' ],
          'the fully qualified peer name is offered when the short name is missing');

# The node attribute is client-supplied: it says what the client wants to be. Offering it would
# let any host that can reach port 3001 ask for another node's postscripts, which carry the
# cluster's root ssh key.
for my $request ({ node => ['xcat59-cn'] },
                 { node => ['xcat59-cn'], _xcat_clienthost => [''] },
                 { node => ['some-other-node'], _xcat_authname => ['xcat59-cn'] }) {
    my @got = names_for($request);
    ok(!grep({ $_ eq ($request->{node}->[0]) } @got),
       "the request's own node attribute is never offered as an identity ("
       . join(',', @got) . ')');
}

# Nothing to go on is an empty list, not an empty name: the caller must be able to tell the
# difference and say so.
is_deeply([ names_for({}) ],        [], 'a request with no identity at all offers no name');
is_deeply([ names_for(undef) ],     [], 'an undefined request offers no name');
is_deeply([ names_for('string') ],  [], 'a request that is not a hash offers no name');
# Wrapped in eval, because without the guard the sub DIES here rather than returning a wrong
# answer, and a test that dies names no assertion -- it reports as a count discrepancy that is
# easy to skim past in a prove summary.
my @unwrapped = eval { names_for({ _xcat_clienthost => 'xcat59-cn' }) };
is($@, '', 'a value xcatd did not wrap in an array ref does not kill the lookup');
is_deeply(\@unwrapped, [], 'and is ignored rather than dereferenced');

# Duplicates would make the caller try the same noderange twice and log the same failure twice.
is_deeply([ names_for({ _xcat_clienthost => ['xcat59-cn'],
                        _xcat_clientfqdn => ['xcat59-cn'],
                        _xcat_authname   => ['xcat59-cn'] }) ],
          [ 'xcat59-cn' ], 'the same name arriving three ways is offered once');

done_testing();
