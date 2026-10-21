#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);

plan skip_all => 'Cumulus discovery requires Linux' unless $^O eq 'linux';

my $directory = sandbox_root();
make_path(map { "$directory/$_" } qw(bin tmp etc/xcat etc/pki/tls var/lib/dhcp));
write_text("$directory/var/lib/dhcp/dhclient.eth0.leases", '');
write_text("$directory/bin/openssl", <<'SH');
#!/bin/sh
echo attempted > /fixture/key-attempt
exit 1
SH
write_text("$directory/bin/logger", "#!/bin/sh\nexit 0\n");
write_text("$directory/bin/socat", "#!/bin/sh\ntouch /fixture/listener-started\nexit 0\n");
chmod(0755, map { "$directory/bin/$_" } qw(openssl logger socat));

my ($rc, $output) = sandbox_run($directory, {
    read_only => {repo_path('xCAT/postscripts') => '/postscripts'},
    writable => {"$directory/var/lib/dhcp" => '/var/lib/dhcp'}},
    '/bin/bash', '/postscripts/documulusdiscovery');
is($rc, 1, 'discovery reports failed private-key generation') or diag($output);
ok(-f "$directory/key-attempt", 'the failure comes from the key generator');
ok(!-e "$directory/tmp/helper.socat.sh",
    'failed key generation leaves no listener helper behind');
ok(!-e "$directory/listener-started", 'failed key generation does not start a listener');

done_testing();
