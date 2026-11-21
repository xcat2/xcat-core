#!/usr/bin/env perl
# The TFTP server xCAT asks for on openSUSE must serve IPv6.
#
# xCAT.spec required the file /usr/sbin/in.tftpd. Two openSUSE packages provide it, and the
# solver picked atftp, whose server has no IPv6 option at all: it binds 0.0.0.0:69 only, even
# with --bind-address ::. A node that boots over DHCPv6 then gets its address and its
# RFC 5970 bootfile-url, asks the server for the loader, times out, releases the address and
# starts again. The tftp package is the hpa server, which listens on both families and is what
# EL already resolves this dependency to.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $rpmspec = qx(command -v rpmspec 2>/dev/null);
chomp($rpmspec);
plan skip_all => 'rpmspec is required' unless $rpmspec && -x $rpmspec;

# requires <define> -- the Requires of xCAT for one distro
sub requires {
    my ($define) = @_;
    open(my $fh, '-|', $rpmspec, '-q', '--requires', '--target', 'x86_64',
        '--define', 'version 2.20.0', '--define', 'release 1',
        '--undefine', 'rhel', '--undefine', 'suse_version', '--undefine', 'openEuler',
        '--define', $define, repo_path('xCAT/xCAT.spec')) or die "run rpmspec: $!";
    my @requires = <$fh>;
    close($fh) or die "rpmspec failed for $define";
    chomp @requires;
    return @requires;
}

my @suse = requires('suse_version 1500');
is(scalar(grep { $_ eq 'tftp' } @suse), 1,
    'xCAT requires the tftp package on openSUSE, whose server listens on IPv6');
is(scalar(grep { $_ eq '/usr/sbin/in.tftpd' } @suse), 0,
    'xCAT does not leave openSUSE a file dependency that atftp can satisfy');

# EL publishes one provider of the file, tftp-server, so the file dependency is unambiguous.
my @el = requires('rhel 10');
is(scalar(grep { $_ eq '/usr/sbin/in.tftpd' } @el), 1,
    'EL keeps the file dependency, which resolves to tftp-server');
is(scalar(grep { $_ eq 'tftp' } @el), 0,
    'EL does not ask for the openSUSE package name');

done_testing();
