use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source;

use File::Spec;
use Test::More;

my $repo_root = File::Spec->catdir($FindBin::Bin, '..', '..');

my $anaconda = File::Spec->catfile(
    $repo_root,
    'xCAT-server/lib/xcat/plugins/anaconda.pm'
);
do $anaconda or die $@ || "Unable to load $anaconda: $!";

is(
    xCAT_plugin::anaconda::_oracle_linux_distname('Oracle Linux 8.4.0'),
    'ol8.4',
    'Oracle Linux media version with trailing update zero maps to major.minor distname'
);

is(
    xCAT_plugin::anaconda::_oracle_linux_distname('Oracle Linux 9.3'),
    'ol9.3',
    'Oracle Linux media version without trailing update zero keeps major.minor distname'
);

is(
    xCAT_plugin::anaconda::_oracle_linux_distname('Oracle Linux 9.0'),
    'ol9.0',
    'Oracle Linux zero minor release keeps major.minor distname'
);

is(
    xCAT_plugin::anaconda::_oracle_linux_distname('OL-7.9 Server.x86_64'),
    'ol7.9',
    'legacy OL media description maps to major.minor distname'
);

is(
    xCAT_plugin::anaconda::_oracle_linux_distname('Rocky Linux 9.6'),
    undef,
    'Oracle Linux distname helper ignores other distributions'
);

done_testing();
