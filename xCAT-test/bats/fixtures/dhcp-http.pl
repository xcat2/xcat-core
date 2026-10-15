use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage)
use FindBin;
use lib "$FindBin::Bin/../../../perl-xCAT";
use lib "$FindBin::Bin/../../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use JSON ();

BEGIN {
    *CORE::GLOBAL::readpipe = sub { return '' if $_[0] eq 'ip -6 route'; die "Unexpected command: $_[0]"; };
}

$ENV{XCATROOT} = "$FindBin::Bin/../../../xCAT-server";
$ENV{XCATCFG} = '/tmp/fixture/config';
make_path($ENV{XCATCFG}, '/tmp/xcat');
require xCAT::Utils;
require xCAT::TableUtils;
no warnings qw(redefine once);
local *xCAT::TableUtils::getTftpDir = sub { return '/tmp/fixture/tftp'; };
local *xCAT::Utils::osver = sub { return 'rhels9.4'; };
my $plugin = "$FindBin::Bin/../../../xCAT-server/lib/xcat/plugins/dhcp.pm";
require $plugin;

my $port = JSON->new->allow_nonref->decode($ARGV[0]);
my %site = (httpport => $port, domain => 'example.invalid', dhcpinterfaces => 'eth0', dnshandler => 'none');
local %::XCATSITEVALS = %site;
local $xCAT_plugin::dhcp::dhcpconffile = '/tmp/fixture/dhcpd.conf';
local *xCAT::TableUtils::get_site_attribute = sub { return $site{$_[-1]}; };
local *xCAT::DHCP::Backend::new_backend = sub { return bless {}, 'HTTPTestBackend'; };
local *xCAT::DHCP::OmapiRunner::key_algorithm_error = sub { return; };
local *xCAT::Utils::isServiceNode = sub { return 0; };
local *xCAT::Utils::isFIPS = sub { return 0; };
local *xCAT::Utils::checkservicestatus = sub { return 0; };
local *xCAT::Utils::restartservice = sub { return 0; };
local *xCAT::MsgUtils::trace = sub { return; };
local *xCAT::NetworkUtils::determinehostname = sub { return 'mn'; };
local *xCAT::NetworkUtils::my_ip_facing = sub { return (0, '192.0.2.1'); };
local *xCAT::NetworkUtils::nodeonmynet = sub { return 1; };
local *xCAT::NetworkUtils::getipaddr = sub { return '192.0.2.10'; };
local *xCAT_plugin::dhcp::getipaddr = sub { return '192.0.2.10'; };
local *xCAT_plugin::dhcp::local_ipv4_routes = sub { return ['192.0.2.0', 'eth0', '255.255.255.0', '']; };
local *xCAT::DBobjUtils::getnodetype = sub { return { cn1 => 'osi' }; };
local *xCAT::DBobjUtils::getNetwkInfo = sub { return (cn1 => {mgtifname => 'eth0'}); };
local *xCAT::Table::new = sub { return bless {name => $_[1]}, 'HTTPTestTable'; };
local *xCAT_plugin::dhcp::_open_omshell_writer = sub {
    open(my $fh, '>', '/tmp/fixture/omshell') or die $!;
    return $fh;
};
local *xCAT_plugin::dhcp::_close_omshell_writer = sub { close($_[0]) or die $!; };
my @errors;
xCAT_plugin::dhcp::process_request({_xcatpreprocessed => [1], node => ['cn1'], arg => []},
    sub { push @errors, @{$_[0]{error} || []}; });
die join("\n", @errors) if @errors;

package HTTPTestBackend;
sub name { return 'isc'; }

package HTTPTestTable;
sub getNodeAttribs { return {ip => '192.0.2.10'} if $_[0]{name} eq 'hosts'; return; }
sub getNodesAttribs {
    my %rows = (
        noderes => {netboot => 'petitboot', tftpserver => '192.0.2.1'},
        mac => {mac => '52:54:00:00:00:10'}, nodetype => {os => 'rhels9'},
        chain => {currstate => 'shell'},
    );
    return $rows{$_[0]{name}} ? {cn1 => [$rows{$_[0]{name}}]} : {};
}
sub getAllAttribs {
    return () unless $_[0]{name} eq 'networks';
    return {net => '192.0.2.0', mask => '255.255.255.0', mgtifname => 'eth0',
        domain => 'example.invalid', nameservers => '192.0.2.1'};
}
sub getAttribs {
    return {username => 'xcat_key', password => 'dGVzdA=='} if $_[0]{name} eq 'passwd';
    return {domain => 'example.invalid', nameservers => '192.0.2.1', tftpserver => '192.0.2.1'};
}
sub close { return; }
