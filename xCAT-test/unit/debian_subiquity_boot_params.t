#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# Regression: the helpers were covered and the call site was not.
#
# subiquity_nfsroot_server and subiquity_kcmdline each had tests, but reverting the CALL SITE in
# mkinstall -- putting `xCAT::NetworkUtils->getipaddr($instserver)` back in place of
# subiquity_nfsroot_server, i.e. the exact regression the fix removes -- left the whole unit
# suite green. A helper can be perfectly covered while nothing connects it to production.
#
# mkinstall needs a management node, so the composition it performs (resolve the install server,
# then build the command line, or explain why not) lives in subiquity_boot_params, which takes
# its inputs and returns an answer. The caller keeps report_node_error and the loop's `next`.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);
my $plugin = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'lib', 'xcat', 'plugins', 'debian.pm'
);
plan skip_all => "debian.pm not found" unless -f $plugin;

my $src = do { local $/; open my $fh, '<', $plugin or die $!; <$fh> };

# BAIL_OUT rather than skip, so a rename fails loudly instead of silently covering nothing.
my $body = '';
for my $name (qw(subiquity_nfsroot_server subiquity_kcmdline subiquity_boot_params)) {
    my ($sub) = $src =~ /\n(sub \Q$name\E \{.*?\n\})\n/s;
    BAIL_OUT("could not extract $name from debian.pm") unless defined $sub;
    $body .= "$sub\n";
}

# Stand in for the module the routine falls back to when no resolver is injected. Without this
# a call site that bypassed the injected resolver would die on a missing module -- a red, but
# for the wrong reason. With it, bypassing the resolver produces the WRONG ANSWER instead of an
# exception, which is what the assertions below are meant to catch.
{
    package xCAT::NetworkUtils;
    sub getipaddr { return undef }
}

{
    package T;
    eval "$body; 1" or main::BAIL_OUT("could not eval the subiquity helpers: $@");
}

my $resolver = sub { $_[0] eq 'mn.cluster' ? '10.0.0.1' : undef };

# The regression this exists to catch: an unset noderes.xcatmaster gives '!myipfn!', and the
# boot config must still be produced with the placeholder intact, because pxe.pm and grub2.pm
# substitute it with an address when they write the config.
{
    my ($kcmdline, $err) = T::subiquity_boot_params(
        'nofb utf8 auto xcatd=!myipfn!', '!myipfn!',
        '/install/ubuntu24.04/x86_64', '80', 'cn1', $resolver );
    ok( !defined $err, 'a node with no xcatmaster still gets a boot config' )
      or diag("error was: $err");
    like( $kcmdline, qr/nfsroot=!myipfn!:/,
        'and nfsroot keeps the placeholder for pxe.pm/grub2.pm to substitute' );
    like( $kcmdline, qr/boot=casper/, 'the casper boot flag survives the composition' );
}

# A resolvable name still becomes an address, because klibc's nfsmount has no resolver.
{
    my ($kcmdline, $err) = T::subiquity_boot_params(
        'nofb utf8 auto xcatd=mn.cluster', 'mn.cluster',
        '/install/ubuntu24.04/x86_64', '80', 'cn1', $resolver );
    ok( !defined $err, 'a resolvable install server produces a boot config' );
    like( $kcmdline, qr{nfsroot=10\.0\.0\.1:/install/ubuntu24\.04/x86_64},
        'and nfsroot carries the address, not the name' );
    like( $kcmdline, qr{ds=nocloud-net;s=http://mn\.cluster:80/},
        'while the cloud-init seed URL keeps the name, where DNS works' );
}

# A dual-stack management node has both an A and an AAAA record, and getipaddr answers with
# whichever the resolver returns first. casper mounts the live filesystem with klibc's nfsmount,
# which takes an IPv4 address, and it takes everything after the first colon in nfsroot= as the
# path -- so an IPv6 address there is not a slower path, it is an unparseable one. This install
# asks for ip=dhcp, so the address must be IPv4.
{
    no warnings 'redefine';
    local *xCAT::NetworkUtils::getipaddr = sub {
        my ($class, $host, %opt) = @_;
        return $opt{OnlyV4} ? '10.0.0.1' : '2001:db8::1';
    };

    my ($kcmdline, $err) = T::subiquity_boot_params(
        'nofb utf8 auto xcatd=mn.cluster', 'mn.cluster',
        '/install/ubuntu24.04/x86_64', '80', 'cn1' );
    ok( !defined $err, 'a dual-stack install server produces a boot config' )
      or diag("error was: $err");
    like( $kcmdline, qr{nfsroot=10\.0\.0\.1:/install/ubuntu24\.04/x86_64},
        'and nfsroot carries the IPv4 address of the install server' );
    unlike( $kcmdline, qr/nfsroot=[^ ]*::/,
        'never the IPv6 address, which klibc nfsmount cannot use' );
}

# The guard the original commit added must survive: a name that does not resolve is an error,
# not a command line with a name in nfsroot.
{
    my ($kcmdline, $err) = T::subiquity_boot_params(
        'nofb utf8 auto xcatd=nosuchhost', 'nosuchhost',
        '/install/ubuntu24.04/x86_64', '80', 'cn1', $resolver );
    ok( !defined $kcmdline, 'an unresolvable install server yields no boot config' );
    like( $err, qr/nosuchhost/, 'and the error names the server that failed' );
    like( $err, qr/klibc|nfsmount|address/i, 'and says why it matters' );
}

done_testing();
