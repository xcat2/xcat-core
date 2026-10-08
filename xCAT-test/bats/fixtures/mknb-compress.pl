use strict;
use warnings;
BEGIN {
    *CORE::GLOBAL::rename = sub ($$) {
        my ($source, $destination) = @_;
        if ($destination =~ m{\A/tmp/fixture/tftp/xcat/genesis\.}) {
            die "Genesis staging crosses destination filesystem\n"
                unless (stat($source))[0] == (stat('/tmp/fixture/tftp/xcat'))[0];
        }
        return CORE::rename($source, $destination);
    };
}
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
