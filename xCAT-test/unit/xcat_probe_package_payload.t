#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(slurp_repo_file);

my $control = slurp_repo_file('xCAT-probe/debian/control');
my ($probe) = $control =~ /^Package: xcat-probe\n(.*?)(?:\n\n|\z)/ms;
like($probe // '', qr/^Depends:.*\biproute2\s*\|\s*net-tools\b/m,
    'Debian probe keeps the socket-tool alternatives');

done_testing();
