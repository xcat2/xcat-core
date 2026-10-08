use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../../../perl-xCAT";
use lib "$FindBin::Bin/../../../xCAT-server/lib/perl";
use XCAT::Test::File qw(repo_path);
use File::Path qw(make_path);

my ($version, $dir, $debug) = @ARGV;
$version =~ /\A(?:8|10)\z/ or die 'Unsupported postscript';
make_path("$dir/db");
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "SQLite:$dir/db";
$ENV{MASTER_IP} = '192.0.2.10';
require xCAT::Table;
require xCAT::Template;
my $site = xCAT::Table->new('site', -create => 1);
$site->setAttribs({ key => 'xcatdebugmode' }, { value => $debug });
$site->close();
my $error = xCAT::Template->subvars(
    repo_path("xCAT-server/share/xcat/install/scripts/post.rhels$version"),
    "$dir/post", 'node', undef, undef, 'rh', undef, { xcatmaster => '192.0.2.10' });
die $error if $error;
