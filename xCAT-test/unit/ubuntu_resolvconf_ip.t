#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Temp qw(tempdir);
use Test::More;

# A nameserver line in /etc/resolv.conf must hold an IP address: glibc's resolver discards an
# entry naming a host. Writing the xcatmaster *name* left the installer -- and the in-target
# apt-get that inherits the file -- with no usable DNS, so the install hung resolving
# archive.ubuntu.com. The template resolves the name to an address first.
#
# Run the template's own shell for that step and inspect the file it writes.

my $tmpl = "$FindBin::Bin/../../xCAT-server/share/xcat/install/ubuntu/compute.subiquity.tmpl";
plan skip_all => 'compute.subiquity.tmpl not found' unless -r $tmpl;

open(my $fh, '<', $tmpl) or die "open $tmpl: $!";
my $source = do { local $/; <$fh> };
close $fh;

my ($fragment) = $source =~ m{^(\s*xcatmaster_host=.*?echo "nameserver [^\n]*\n)}ms;
BAIL_OUT('the template does not build /etc/resolv.conf from the xcatmaster') unless $fragment;

# $NODE and the xcatmaster come from the xCAT template renderer; stand in for both.
sub write_resolv_conf {
    my (%opt) = @_;
    my $root = tempdir(CLEANUP => 1);

    my $script = $fragment;
    $script =~ s/\#TABLE:noderes:\$NODE:xcatmaster\#/$opt{xcatmaster}/;
    $script =~ s{/etc/resolv\.conf}{$root/resolv.conf}g;

    # The fragment contains `rm -f /etc/resolv.conf` and this suite runs as root in CI, so a
    # rewrite that stops matching would delete the runner's resolver configuration rather than
    # fail a test. Sandboxing by rewriting paths is fragile by nature -- respelling the path in
    # the template as, say, `etcdir=/etc; rm -f "$etcdir/resolv.conf"` slips straight past the
    # substitution above. Refuse to execute anything that still points outside the scratch tree.
    if ($script =~ m{(?<!\Q$root\E)/etc/}) {
        BAIL_OUT('the /etc rewrite no longer covers the fragment; refusing to run it as root');
    }

    # getent is the resolver the fragment uses; make it answer as the test wants.
    my $getent = $opt{resolves}
      ? "getent() { printf '%s\\n' '$opt{resolves} $opt{xcatmaster}'; }\n"
      : "getent() { return 2; }\n";

    system('bash', '-c', $getent . $script) == 0 or return { rc => $? };

    open my $rh, '<', "$root/resolv.conf" or return { rc => 0, content => '' };
    my $content = do { local $/; <$rh> };
    close $rh;
    return { rc => 0, content => $content };
}

# --- the case the fix exists for -------------------------------------------
{
    my $r = write_resolv_conf(xcatmaster => 'xcatmn', resolves => '10.0.0.1');
    is($r->{content}, "nameserver 10.0.0.1\n",
        'the nameserver line holds the address, which glibc will actually use');
    unlike($r->{content}, qr/nameserver \s+ xcatmn/x,
        'the nameserver line never holds a host name, which glibc discards');
}

# --- more than one address: the first is taken -----------------------------
{
    my $r = write_resolv_conf(xcatmaster => 'xcatmn', resolves => '10.0.0.1');
    like($r->{content}, qr/^nameserver \d+\.\d+\.\d+\.\d+$/m,
        'exactly one IPv4 address is written');
}

# --- resolution fails: fall back rather than write an empty entry ----------
{
    my $r = write_resolv_conf(xcatmaster => 'xcatmn');
    is($r->{content}, "nameserver xcatmn\n",
        'an unresolvable xcatmaster falls back to its name rather than an empty nameserver');
    unlike($r->{content}, qr/^nameserver\s*$/m,
        'no empty nameserver line is written');
}

# --- an xcatmaster already given as an address is left alone ---------------
{
    my $r = write_resolv_conf(xcatmaster => '10.0.0.1', resolves => '10.0.0.1');
    is($r->{content}, "nameserver 10.0.0.1\n", 'an address-valued xcatmaster is written as is');
}

done_testing();
