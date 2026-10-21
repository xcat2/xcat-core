#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $bash = qx(command -v bash 2>/dev/null);
chomp($bash);
plan skip_all => 'bash is required' unless $bash && -x $bash;

my $directory = tempdir(CLEANUP => 1);
make_path(map { "$directory/$_" } qw(bin tmp etc/xcat etc/pki/tls var/lib/dhcp));
write_text("$directory/var/lib/dhcp/dhclient.eth0.leases", '');
symlink(repo_path('xCAT/postscripts/xcatlib.sh'), "$directory/xcatlib.sh")
    or die "link shell library: $!";

my $script = read_text(repo_path('xCAT/postscripts/documulusdiscovery'));
$script =~ s{(/etc/xcat|/etc/pki/tls|/var/lib/dhcp|/tmp)(?=/|\b)}{$directory$1}g;
write_text("$directory/documulusdiscovery", $script);
write_text("$directory/bin/openssl", <<'SH');
#!/bin/sh
echo attempted > "$KEY_ATTEMPT"
exit 1
SH
write_text("$directory/bin/logger", "#!/bin/sh\nexit 0\n");
write_text("$directory/bin/socat", "#!/bin/sh\nexit 0\n");
chmod(0755, map { "$directory/bin/$_" } qw(openssl logger socat));

local $ENV{PATH} = "$directory/bin:$ENV{PATH}";
local $ENV{KEY_ATTEMPT} = "$directory/key-attempt";
system($bash, "$directory/documulusdiscovery");
is($? >> 8, 1, 'discovery reports failed private-key generation');
ok(-f "$directory/key-attempt", 'the failure comes from the key generator');
ok(!-e "$directory/tmp/helper.socat.sh",
    'failed key generation leaves no listener helper behind');

done_testing();
