#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(slurp_repo_file);

my $control = slurp_repo_file('xCAT-server/debian/control');
my ($server) = $control =~ /^Package: xcat-server\n(.*?)(?:\n\n|\z)/ms;
like($server // '', qr/^Depends:.*\blibdigest-sha-perl\b/m,
    'the Debian server package requires Digest::SHA');

done_testing();
