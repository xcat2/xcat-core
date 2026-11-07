#!/usr/bin/env perl
#
# configdhcpv6duid has to be in the default postscript list, or it ships and never runs.
#
# The default lists are the chtab commands xcatconfig issues for the xcatdefaults node, so the
# command string is the artifact here, as a package name in a spec file is. AIX has neither
# NetworkManager nor systemd-networkd, so its list is left alone.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Slurper qw(read_text);
use Test::More tests => 7;
use XCAT::Test::File qw(repo_path);

my $script = repo_path('xCAT/postscripts/configdhcpv6duid');
ok(-f $script, 'the postscript is in the tree');
ok(-x $script, 'and is executable, so the tarball ships it runnable');

my $config = read_text(repo_path('xCAT-server/sbin/xcatconfig'));
my @defaults = $config =~ /node=xcatdefaults postscripts\.postscripts='([^']+)'/g;
is(scalar(@defaults), 3, 'xcatconfig sets three default postscript lists');

# Two are the Linux branches, one is AIX. The AIX one is the list without otherpkgs that also
# lacks the DUID writer, so count rather than assume an order.
my @with    = grep { /(?:^|,)configdhcpv6duid(?:,|$)/ } @defaults;
my @without = grep { !/(?:^|,)configdhcpv6duid(?:,|$)/ } @defaults;
is(scalar(@with), 2, 'the two Linux lists run the DUID writer');
is(scalar(@without), 1, 'and one list does not, which is AIX');
like($without[0], qr/^syslog,remoteshell,syncfiles$/,
    'the list without it is the AIX one, unchanged');

# It must run after remoteshell, which is what gives the node its keys, and before syncfiles.
my @order = grep { /configdhcpv6duid/ } @defaults;
is(scalar(grep { /remoteshell,configdhcpv6duid/ } @order), 2,
    'the DUID writer runs straight after remoteshell in both');
