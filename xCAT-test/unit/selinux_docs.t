#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Slurper qw(read_text);
use Test::More;

# The SELinux pages and the policy module disagreed. The security page said the
# package defines no type and that xcatd runs in unconfined_service_t, while
# xcat.te declared two domains. Derive the domain set from the policy source,
# so a page cannot describe a module that is not shipped.
my $root = "$FindBin::Bin/../..";

my $te = read_text("$root/xCAT-selinux/xcat.te");
my @permissive = sort($te =~ /^\s*permissive\s+(\w+)\s*;/mg);
is_deeply(\@permissive, [ 'xcat_image_t', 'xcat_t' ],
    "xcat.te declares the permissive domains @permissive");

my @pages = (
    'docs/source/advanced/security/selinux.rst',
    'docs/source/advanced/selinux/index.rst',
);
my %text;
foreach my $page (@pages) {
    $text{$page} = read_text("$root/$page");
    ok(length($text{$page}) > 1000, "$page holds @{[length $text{$page}]} characters");
}

foreach my $page (@pages) {
    foreach my $domain (@permissive) {
        like($text{$page}, qr/\Q$domain\E/, "$page names $domain");
    }
    like($text{$page}, qr/permissive/, "$page says the domains are permissive");

    # xcatd enters xcat_t on the xcatd script. A page that still names the
    # domain of an unconfined service describes the module before xcat_t.
    unlike($text{$page}, qr/unconfined_service_t/,
        "$page does not put an xCAT service in unconfined_service_t");
    unlike($text{$page}, qr/defines no type/,
        "$page does not say the package defines no type");
}

# The branch ships noderes.selinux, so a page cannot place the nodes outside
# the scope of what xCAT decides.
my $modes = read_text("$root/perl-xCAT/xCAT/SELinux.pm");
like($modes, qr/sub node_modes/, 'SELinux.pm resolves the mode of a node');
foreach my $page (@pages) {
    like($text{$page}, qr/noderes\.selinux/, "$page names noderes.selinux");
    unlike($text{$page}, qr/xCAT does not select their mode/,
        "$page does not say xCAT leaves the mode of a node alone");
}

done_testing();
