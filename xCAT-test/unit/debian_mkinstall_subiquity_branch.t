#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# Regression: the helpers were covered, the CALL SITE was not.
#
# subiquity_boot_params and subiquity_nfsroot_server each have tests, but putting mkinstall's
# pre-fix branch back -- getipaddr plus the inline command line -- left the entire unit suite
# green. Argument order, the error branch, and the `next` that skips the node were all
# unobservable, which is exactly where the bug this PR fixes lived.
#
# mkinstall needs a management node and a database, so the branch is lifted out and eval'd into
# a scratch package with report_node_error stubbed, and driven inside a real loop so the `next`
# it performs is the `next` under test.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);
my $plugin = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'lib', 'xcat', 'plugins', 'debian.pm'
);
plan skip_all => "debian.pm not found" unless -f $plugin;

my $src = do { local $/; open my $fh, '<', $plugin or die $!; <$fh> };

# The helpers the branch calls, plus the branch itself. BAIL_OUT rather than skip, so a rename
# fails loudly instead of silently covering nothing.
my $helpers = '';
for my $name (qw(subiquity_nfsroot_server subiquity_kcmdline subiquity_boot_params)) {
    my ($sub) = $src =~ /\n(sub \Q$name\E \{.*?\n\})\n/s;
    BAIL_OUT("could not extract $name from debian.pm") unless defined $sub;
    $helpers .= "$sub\n";
}

# There are several `if (using_subiquity(...))` in debian.pm; take the one that actually builds
# the boot parameters, selected by what it contains rather than by where it sits, so adding
# another above it does not silently swap which branch is under test.
my @candidates = $src =~ /\n[ ]+if \(using_subiquity\([^)]*\)\) \{\n(.*?)\n[ ]+\} else \{\n/gs;
my @wanted = grep { /subiquity_boot_params\(/ } @candidates;
BAIL_OUT('could not find the mkinstall branch that builds the subiquity boot parameters')
  unless @wanted == 1;
my $branch = $wanted[0];
BAIL_OUT('the extracted branch does not skip the node on error')
  unless $branch =~ /\bnext\b/;
BAIL_OUT('the extracted branch is implausibly large -- the match ran past its block')
  if ($branch =~ tr/\n//) > 20;

my @reported;

# The branch calls subiquity_boot_params with no resolver, exactly as production does, so the
# fallback to xCAT::NetworkUtils->getipaddr is the seam to stand in at. That keeps the call path
# under test identical to the real one -- nothing is injected into it.
{
    package xCAT::NetworkUtils;
    sub getipaddr {
        my (undef, $name) = @_;
        return $name if defined($name) && $name =~ /^\d+\.\d+\.\d+\.\d+$/;
        return '10.0.0.1' if defined($name) && $name eq 'mn.cluster';
        return undef;
    }
}

{
    package xCAT::MsgUtils;
    sub report_node_error { shift; my ($cb, $node, $msg) = @_; push @reported, [ $node, $msg ]; }
}

my $driver = <<"CODE";
$helpers
sub drive {
    my (\$kcmdline, \$instserver, \$pkgdir, \$httpport, \$node) = \@_;
    my \$callback;
    my \$result;
    NODE: foreach my \$n (\$node) {
$branch
        \$result = \$kcmdline;
    }
    return \$result;
}
CODE

# `next` inside the branch belongs to the loop the driver wraps around it.
$driver =~ s/\bnext;/next NODE;/g;

{
    package T;
    eval "$driver; 1" or main::BAIL_OUT("could not eval the mkinstall branch: $@");
}

# A resolvable install server: the branch must produce a live command line.
{
    @reported = ();
    my $out = T::drive( 'nofb utf8 auto xcatd=10.0.0.1', '10.0.0.1',
        '/install/ubuntu24.04/x86_64', '80', 'cn1' );
    ok( defined $out, 'a resolvable install server yields a command line' );
    like( $out, qr/boot=casper/,       'the branch puts boot=casper on the command line' );
    like( $out, qr/\btoram\b/,         'and toram' );
    like( $out, qr{nfsroot=10\.0\.0\.1:/install/ubuntu24\.04/x86_64},
        'and nfsroot as a literal address, in the media path' );
    is( scalar @reported, 0, 'and nothing is reported as an error' );
}

# The placeholder: this is the case the fix restored, driven through the call site rather than
# through the helper.
{
    @reported = ();
    my $out = T::drive( 'nofb utf8 auto xcatd=!myipfn!', '!myipfn!',
        '/install/ubuntu24.04/x86_64', '80', 'cn1' );
    ok( defined $out, 'a node with no xcatmaster is not skipped' );
    like( $out, qr/nfsroot=!myipfn!:/,
        'and the placeholder reaches the boot config for pxe.pm/grub2.pm to substitute' );
    is( scalar @reported, 0, 'and no error is reported for it' );
}

# An install server that does not resolve must skip the node, not emit a command line naming it.
{
    @reported = ();
    my $out = T::drive( 'nofb utf8 auto xcatd=nosuchhost', 'nosuchhost',
        '/install/ubuntu24.04/x86_64', '80', 'cn1' );
    ok( !defined $out, 'an unresolvable install server skips the node' );
    is( scalar @reported, 1, 'and reports exactly one error' );
    like( $reported[0][1], qr/nosuchhost/, 'naming the server that failed' );
    is( $reported[0][0], 'cn1', 'and the node it happened on' );
}

done_testing();
