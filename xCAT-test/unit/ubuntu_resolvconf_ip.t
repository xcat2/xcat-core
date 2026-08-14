#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Regression: the Ubuntu (subiquity) diskful install writes the installer's /etc/resolv.conf
# from compute.subiquity.tmpl's "DNS setup" early-command. A nameserver line in
# /etc/resolv.conf MUST be an IP address -- glibc's resolver does NOT resolve a hostname
# given on a nameserver line, it simply discards the entry. The template used to write the
# xcatmaster *name* there:
#
#     echo "nameserver #TABLE:noderes:$NODE:xcatmaster#" >/etc/resolv.conf
#
# which left the installer (and the in-target apt-get update, which inherits this resolv.conf)
# with no usable DNS. The install then hangs resolving archive.ubuntu.com -- the node never
# finishes, and the test sees "ssh: connect ... port 22: Connection refused". (Everything the
# early-command did BEFORE this point still worked because the live installer's DHCP-provided
# resolv.conf can resolve the xcatmaster name -- so the failure only surfaces at the very next
# DNS-dependent step, the in-target apt.)
#
# The fix resolves the xcatmaster hostname to an IPv4 address (via getent, while DNS still
# works) and writes that IP into resolv.conf.

sub slurp { my ($p) = @_; local $/; open my $fh, '<', $p or return undef; <$fh> }

my $tmpl = slurp('xCAT-server/share/xcat/install/ubuntu/compute.subiquity.tmpl');
plan skip_all => 'compute.subiquity.tmpl not found' unless defined $tmpl;

# The old, broken form -- a bare hostname token written straight into the nameserver line --
# must be gone.
unlike($tmpl, qr/nameserver \s+ \#TABLE:noderes:\$NODE:xcatmaster\# /x,
    'resolv.conf nameserver is NOT the bare xcatmaster hostname token (glibc cannot resolve a name there)');

# The xcatmaster name must be resolved to an IPv4 address before it is used as a nameserver.
like($tmpl, qr/getent \s+ ahostsv4 /x,
    'DNS setup resolves the xcatmaster to an IPv4 address via getent ahostsv4');

# And the nameserver line must be written from that resolved IP variable.
like($tmpl, qr/nameserver \s+ \$xcatmaster_ip/x,
    'resolv.conf nameserver is written from the resolved xcatmaster IP');

done_testing();
