use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../../perl-xCAT";
use lib "$FindBin::Bin/../../../xCAT-server/lib/perl";
use JSON qw(encode_json);

$ENV{XCATROOT} = "$FindBin::Bin/../../../xCAT-server";
$ENV{XCATCFG} = '/tmp/fixture/config';
my $plugin = "$FindBin::Bin/../../../xCAT-server/lib/xcat/plugins/mknb.pm";
require $plugin;
$::XCATROOT = '/tmp/fixture/source';

no warnings qw(redefine once);
local *xCAT::TableUtils::getTftpDir = sub { return '/tmp/fixture/tftp'; };
local *xCAT::TableUtils::get_site_attribute = sub { return; };
local *xCAT::NetworkUtils::my_nets = sub { return {}; };
local *xCAT::NetworkUtils::my_hexnets = sub { return {}; };

my @responses;
umask oct($ARGV[0]);
xCAT_plugin::mknb::process_request(
    { arg => ['x86_64'] }, sub { push @responses, @_; },
);
print encode_json(\@responses), "\n";
exit((grep { $_->{error} || $_->{errorcode} } @responses) ? 1 : 0);
