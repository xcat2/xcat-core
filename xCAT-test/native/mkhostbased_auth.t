#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File    qw(repo_path);
use XCAT::Test::Process qw(run_command);

plan skip_all => 'host-based authentication requires Linux nodes' unless $^O eq 'linux';
for my $tool (qw(/usr/bin/python3 /usr/bin/ssh /usr/bin/ssh-keygen /usr/sbin/sshd)) {
    die "Install $tool to run the native host-based authentication test\n" unless -x $tool;
}

my ($status, $output) = run_command('/usr/bin/python3', '-I', repo_path('xCAT-test/native/mkhostbased_auth_ssh.py'),
    repo_path('xCAT-server/share/xcat/scripts/xcat-hostbased-auth.py'));
is($status, 0, 'OpenSSH applies the intended host-based policy') or diag($output);
done_testing();
