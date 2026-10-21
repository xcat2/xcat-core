#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);

plan skip_all => 'statelite requires Linux' unless $^O eq 'linux';
my $script = repo_path('xCAT-server/share/xcat/netboot/add-on/statelite/add_ssh');

for my $with_dsa (0, 1) {
    my $root = sandbox_root();
    make_path(map { "$root/$_" }
        qw(etc/xcat/hostkeys etc/ssh root/.ssh target/etc/ssh));
    write_text("$root/target/etc/ssh/sshd_config", "X11Forwarding no\n");
    write_text("$root/etc/xcat/hostkeys/ssh_host_rsa_key", "rsa-host-key\n");
    write_text("$root/etc/xcat/hostkeys/ssh_host_dsa_key", "dsa-host-key\n")
        if $with_dsa;
    write_text("$root/root/.ssh/$_", "client-$_\n") for qw(id_rsa id_rsa.pub config);

    my ($rc, $output) = sandbox_run($root, {
        read_only => {$script => '/add_ssh'},
        writable => {"$root/root" => '/root'},
        env => {XCATROOT => '/opt/xcat'}},
        '/bin/bash', '/add_ssh', '/target');
    is($rc, 0, "statelite completes with DSA present=$with_dsa") or diag($output);
    is($output, '', "statelite reports no missing-key errors with DSA present=$with_dsa");
    like(read_text("$root/etc/ssh/ssh_config"), qr/StrictHostKeyChecking no/,
        'statelite writes client configuration inside the private filesystem');
    is(read_text("$root/target/etc/ssh/ssh_host_rsa_key"), "rsa-host-key\n",
        "statelite preserves the RSA host key with DSA present=$with_dsa");
    is(-f "$root/target/etc/ssh/ssh_host_dsa_key" ? 1 : 0, $with_dsa,
        'statelite copies the optional DSA key only when supplied');
    is((stat("$root/target/etc/ssh/ssh_host_rsa_key"))[2] & oct('0777'), oct('0600'),
        'statelite limits RSA host-key permissions');
    if ($with_dsa) {
        is(read_text("$root/target/etc/ssh/ssh_host_dsa_key"), "dsa-host-key\n",
            'statelite preserves the optional DSA key');
        is((stat("$root/target/etc/ssh/ssh_host_dsa_key"))[2] & oct('0777'), oct('0600'),
            'statelite limits DSA host-key permissions');
    }
}

done_testing();
