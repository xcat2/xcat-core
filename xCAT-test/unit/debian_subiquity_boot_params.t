#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
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
for my $name (qw(subiquity_nfsroot_server subiquity_kcmdline install_iso_name
    subiquity_iso_url subiquity_url_kcmdline link_install_iso subiquity_boot_params)) {
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
    # The default answer: a node that has an IPv4 address. The IPv6-only case injects its own.
    sub node_is_ipv6_only { return 0 }
    sub format_uri_host {
        my $host = shift;
        $host = shift if defined($host) && $host eq __PACKAGE__;
        return "[$host]" if defined($host) && $host =~ /:/;
        return $host;
    }
    sub format_host_port {
        my $host = shift;
        $host = shift if defined($host) && $host eq __PACKAGE__;
        my $port = shift;
        return format_uri_host($host) . ":$port";
    }
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

# ---- an IPv6-only node cannot use the live installer -----------------------------------------
# Measured on noble: the ipconfig in the casper initrd carries no IPv6 string at all, and klibc
# nfsmount answers "need a path" for both "[2001:db8::1]:/export" and "2001:db8::1:/export".
# So the node cannot configure its interface or mount its root, and a command line built for it
# can only PXE-loop. The refusal names the reason instead.
{
    my $ipv6_only = sub { return 1 };
    my ($kcmdline, $err) = T::subiquity_boot_params(
        'nofb utf8 auto xcatd=!myipfn!', '!myipfn!',
        '/install/ubuntu24.04/x86_64', '80', 'cn6', $resolver, $ipv6_only );
    ok( !defined $kcmdline, 'an IPv6-only node gets no Subiquity command line' );
    like( $err, qr/\bcn6\b/, '... and the refusal names the node' );
    like( $err, qr/nfsmount/, '... and names nfsmount, the one component that has no IPv6' );
}

# An IPv6-only node whose tree carries the ISO takes the HTTP route instead of being refused.
# casper's do_urlmount fetches the ISO with its own wget, which speaks IPv6, and klibc nfsmount
# is never reached.
{
    my $ipv6_only  = sub { return 1 };
    my $iso_exists = sub { return 1 };
    my ($kcmdline, $err) = T::subiquity_boot_params(
        'nofb utf8 auto xcatd=!myipfn!', '2001:db8::1',
        '/install/ubuntu24.04/x86_64', '80', 'cn7', $resolver, $ipv6_only, $iso_exists );
    ok( !defined $err, 'an IPv6-only node with the ISO in its tree is not refused' );
    like( $kcmdline, qr{\Qnetboot=url\E}, '... and casper is told to fetch a URL' );
    like(
        $kcmdline,
        qr{\Qurl=http://[2001:db8::1]:80/install/ubuntu24.04/x86_64/install.iso\E},
        '... from the bracketed install server, so the port can still be read'
    );
    like( $kcmdline, qr{\bip6=dhcp\b}, '... with ip6=, which casper gives to dhcpcd -6' );
    # casper calls configure_networking only when ip= is set, whatever the value. Without it
    # the whole networking stage is skipped and wget has no source address.
    like( $kcmdline, qr{\bip=off\b},
        '... and with ip=, which is what makes casper configure the interface at all' );
    unlike( $kcmdline, qr{\bnfsroot=}, '... and no nfsroot, which klibc nfsmount cannot use' );
    unlike( $kcmdline, qr{\btoram\b},
        '... and no toram, because do_urlmount already holds the ISO in tmpfs' );
    like( $kcmdline, qr{\Qds=nocloud-net;s=http://[2001:db8::1]:80/install/autoinst/cn7/\E},
        '... and the seed URL brackets the server too' );
}

# The refusal for an IPv6-only node whose tree has no ISO says what to do about it.
{
    my $ipv6_only  = sub { return 1 };
    my $iso_exists = sub { return 0 };
    my ($kcmdline, $err) = T::subiquity_boot_params(
        'nofb utf8 auto', '2001:db8::1',
        '/install/ubuntu24.04/x86_64', '80', 'cn8', $resolver, $ipv6_only, $iso_exists );
    ok( !defined $kcmdline, 'an IPv6-only node with no ISO gets no command line' );
    like( $err, qr{\Qinstall.iso\E}, '... and the refusal names the file that is missing' );
    like( $err, qr/copycds/, '... and the command that creates it' );
}

# A node that has an IPv4 address is unaffected, whatever the management node also has.
{
    my $ipv6_only = sub { return 0 };
    my ($kcmdline, $err) = T::subiquity_boot_params(
        'nofb utf8 auto xcatd=mn.cluster', 'mn.cluster',
        '/install/ubuntu24.04/x86_64', '80', 'cn1', $resolver, $ipv6_only );
    ok( !defined $err, 'a dual-stack node still gets a boot config' ) or diag("error: $err");
    like( $kcmdline, qr{nfsroot=10\.0\.0\.1:}, '... with its IPv4 nfsroot' );
}

# link_install_iso puts the ISO in the install tree, where httpd serves it. A symbolic link,
# because the Ubuntu 24.04 ISO is 3.2G and the xcat.conf xCAT ships gives /install
# "Options FollowSymLinks".
{
    my $dir  = tempdir( CLEANUP => 1 );
    my $tree = "$dir/install/ubuntu24.04/x86_64";
    my $iso  = "$dir/ubuntu-24.04.4-live-server-amd64.iso";
    mkdir "$dir/install"; mkdir "$dir/install/ubuntu24.04"; mkdir $tree;
    open my $fh, '>', $iso or die "cannot create $iso: $!";
    print {$fh} "not really an iso\n";
    close $fh;

    my @warnings;
    my $callback = sub { push @warnings, @{ $_[0]->{warning} || [] } };

    is( T::link_install_iso( $tree, $iso, $callback ), 1, 'the ISO is linked into the tree' );
    ok( -l "$tree/install.iso", '... as a symbolic link, not a copy' );
    is( readlink("$tree/install.iso"), $iso, '... pointing at the ISO copycds was given' );
    is_deeply( \@warnings, [], '... with nothing to warn about' );

    # copycds runs again on the same tree, which must not fail on the link already there.
    is( T::link_install_iso( $tree, $iso, $callback ), 1, 'linking again replaces the link' );
    is( readlink("$tree/install.iso"), $iso, '... and it still points at the ISO' );

    # A block device has no path to link, and copycds passes none.
    is( T::link_install_iso( $tree, undef, $callback ), 0, 'no ISO path links nothing' );
    is( T::link_install_iso( $tree, "$dir/absent.iso", $callback ), 0,
        'an ISO that does not exist links nothing' );
    is_deeply( \@warnings, [], 'neither case is a warning, because neither is an error' );
}

# copycds can be handed the ISO that is already in the tree, or the link to it. unlink
# then symlink would delete the media and leave a link pointing at nothing.
{
    my $dir  = tempdir( CLEANUP => 1 );
    my $tree = "$dir/tree";
    mkdir $tree;
    my $at_destination = "$tree/install.iso";
    open my $fh, '>', $at_destination or die "cannot create $at_destination: $!";
    print {$fh} "REAL ISO PAYLOAD";
    close $fh;

    is( T::link_install_iso( $tree, $at_destination, undef ), 1,
        'an ISO already at the destination needs no link' );
    ok( !-l $at_destination, '... and it is left as a file, not replaced by a link' );
    is( -s $at_destination, 16, '... with its contents intact' );

    # The same call again, now that the ISO really is a link to media elsewhere.
    my $media = "$dir/media.iso";
    open my $mh, '>', $media or die; print {$mh} "ELSEWHERE"; close $mh;
    unlink $at_destination;
    symlink( $media, $at_destination ) or die "cannot link: $!";
    is( T::link_install_iso( $tree, $at_destination, undef ), 1,
        'the link to the media resolves to the same file, so it is kept' );
    is( readlink($at_destination), $media, '... still pointing at the media' );
    ok( -e $at_destination, '... and it is not dangling' );

    # A different ISO replaces the link.
    my $other = "$dir/other.iso";
    open my $oh, '>', $other or die; print {$oh} "OTHER"; close $oh;
    is( T::link_install_iso( $tree, $other, undef ), 1, 'a different ISO is linked' );
    is( readlink($at_destination), $other, '... replacing the previous link' );
}

done_testing();
