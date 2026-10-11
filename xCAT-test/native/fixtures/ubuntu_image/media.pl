use strict;
use warnings;

use File::Slurper qw(write_binary);
use JSON::PP qw(encode_json);
use xCAT::Table;

my $plugin = '/repo/xCAT-server/lib/xcat/plugins/debian.pm';
require $plugin;

my $site = xCAT::Table->new('site', -create => 1);
$site->setAttribs({ key => 'installdir' }, { value => '/install' });
$site->close();

my @responses;
my $detected = xCAT_plugin::debian::is_ubuntu_live_media('/work/media');
xCAT_plugin::debian::process_request(
    { command => ['copycd'], arg => ['-m', '/work/media', '-o'] },
    sub { push @responses, @_ },
);
my $osdistro = xCAT::Table->new('osdistro');
my $row = $osdistro->getAttribs({ osdistroname => 'ubuntu24.04-x86_64' },
    qw(arch dirpaths type));
$osdistro->close();
write_binary('/work/result.json', encode_json({ detected => $detected,
    responses => \@responses, osdistro => $row }));
