use strict;
use warnings;

use File::Slurper qw(read_text);
use JSON::PP qw(decode_json);
use xCAT::Table;

my %values = (master => '192.0.2.1', httpport => '80',
    %{ decode_json(read_text('/work/site.json')) });
my $site = xCAT::Table->new('site', -create => 1);
$site->setAttribs({ key => $_ }, { value => $values{$_} }) for keys %values;
$site->close();
exec 'perl', @ARGV;
die "exec genimage: $!";
