use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../../perl-xCAT", "$FindBin::Bin/../../../xCAT-server/lib/perl";

$ENV{XCATROOT} = "$FindBin::Bin/../../../xCAT-server";
$ENV{XCATCFG} = 'SQLite:/fixture/db';
require xCAT::Table;
require xCAT::Template;
require xCAT::Postage;

my %site = (installdir => '/install', tftpdir => '/tftpboot', master => '192.0.2.1',
    xcatiport => 3002, httpport => 80, xcatdebugmode => 0, nodestatus => 0);
for my $key (sort keys %site) {
    my $table = xCAT::Table->new('site', -create => 1) or die 'Cannot create site';
    $table->setAttribs({key => $key}, {value => $site{$key}});
    $table->close();
}
%::XCATSITEVALS = %site;
for my $row (
    ['nodelist', {groups => 'all'}],
    ['nodetype', {os => 'rhels8', arch => 'x86_64', provmethod => 'install'}],
    ['noderes', {xcatmaster => '192.0.2.1'}],
) {
    my $table = xCAT::Table->new($row->[0], -create => 1) or die "Cannot create $row->[0]";
    $table->setAttribs({node => 'node'}, $row->[1]);
    $table->close();
}
my $error = xCAT::Template->subvars(
    "$ENV{XCATROOT}/share/xcat/install/scripts/$ARGV[0]", '/fixture/installer',
    'node', undef, '/install/media', 'rh', undef, {xcatmaster => '192.0.2.1'});
die "Cannot render installer: $error" if $error;
