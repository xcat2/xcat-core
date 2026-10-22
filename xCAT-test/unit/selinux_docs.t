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

# A repair of a published artifact is a persistent file-context mapping, applied
# with restorecon. chcon writes a type that no mapping selects, and a recursive
# chcon over an image root walks into both guest trees.
my $repair = 'docs/source/advanced/selinux/index.rst';
unlike($text{$repair}, qr/chcon\s+-R/, "$repair documents no recursive chcon");
like($text{$repair}, qr/semanage fcontext -a/, "$repair maps the artifact with semanage");
like($text{$repair}, qr/restorecon -R/, "$repair applies the mapping with restorecon");
like($text{$repair}, qr/installdir/,
    "$repair takes the publication directory from site.installdir");
foreach my $guest (qw(rootimg rootimg-statelite)) {
    like($text{$repair}, qr/\Q$guest\E/, "$repair names the $guest tree");
}

my $fc = read_text("$root/xCAT-selinux/xcat.fc");
unlike($fc, qr/chcon/, 'xcat.fc advises no chcon');
like($fc, qr/semanage fcontext/, 'xcat.fc names the command that maps a path');

done_testing();
