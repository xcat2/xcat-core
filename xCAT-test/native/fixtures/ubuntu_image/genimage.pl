use strict;
use warnings;

use File::Slurper qw(read_text write_binary);
use JSON::PP qw(decode_json encode_json);
use xCAT::Table;

my %values = (master => '192.0.2.1', httpport => '80',
    %{ decode_json(read_text('/work/site.json')) });
my $site = xCAT::Table->new('site', -create => 1);
for my $key (keys %values) {
    $site->setAttribs({ key => $key }, { value => 'https://previous.example.invalid/ubuntu' })
      if $key eq 'ubuntu_apt_mirror' && $values{$key} eq '';
    $site->setAttribs({ key => $key }, { value => $values{$key} });
}
my $mirror_row = $site->getAttribs({ key => 'ubuntu_apt_mirror' }, qw(key value));
write_binary('/work/site-row.json', encode_json({ mirror => $mirror_row }));
$site->close();
exec 'perl', @ARGV;
die "exec genimage: $!";
