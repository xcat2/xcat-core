#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use XCAT::Test::File qw(repo_path);
use xCAT::Utils;

my $tmpdir = tempdir(CLEANUP => 1);
my $fips_status = File::Spec->catfile($tmpdir, 'fips_enabled');

write_text($fips_status, "1\n");
ok(xCAT::Utils->isFIPS($fips_status), 'kernel status 1 enables FIPS mode');

write_text($fips_status, "0\n");
ok(!xCAT::Utils->isFIPS($fips_status), 'kernel status 0 disables FIPS mode');
write_text($fips_status, "  1  \n");
ok(xCAT::Utils->isFIPS($fips_status), 'kernel status permits surrounding whitespace');
write_text($fips_status, "enabled\n");
ok(!xCAT::Utils->isFIPS($fips_status), 'malformed kernel status does not enable FIPS mode');
write_text($fips_status, '');
ok(!xCAT::Utils->isFIPS($fips_status), 'empty kernel status does not enable FIPS mode');
ok(!xCAT::Utils->isFIPS(File::Spec->catfile($tmpdir, 'missing')), 'missing kernel status is not FIPS mode');

foreach my $case (
    ['el7', 1], ['el8', 1], ['el9', 1], ['el10', 0], ['el11', 0],
    ['ubuntu', 1], ['sles12', 1], ['sles15', 1], ['aix', 1],
) {
    my ($platform, $legacy_allowed) = @{$case};
    is(xCAT::Utils->dsaHostKeyAllowed($platform, 0), $legacy_allowed,
        "$platform retains its non-FIPS DSA policy");
    is(xCAT::Utils->dsaHostKeyAllowed($platform, 1), 0,
        "$platform rejects DSA in FIPS mode");
}

SKIP: {
    skip 'statelite requires Linux shell utilities', 12 unless $^O eq 'linux';

    foreach my $with_dsa (0, 1) {
        my $fixture = tempdir(CLEANUP => 1);
        my $image = "$fixture/image";
        make_path("$fixture/hostkeys", "$fixture/client",
            "$image/etc/ssh", "$image/root/.ssh");
        write_text("$image/etc/ssh/sshd_config", "X11Forwarding no\n");
        write_text("$fixture/hostkeys/ssh_host_rsa_key", "rsa-host-key\n");
        write_text("$fixture/hostkeys/ssh_host_dsa_key", "dsa-host-key\n")
            if $with_dsa;
        write_text("$fixture/client/$_", "client-$_\n") for qw(id_rsa id_rsa.pub config);

        my $source = read_text(repo_path('xCAT-server/share/xcat/netboot/add-on/statelite/add_ssh'));
        $source =~ s{/etc/xcat/hostkeys}{$fixture/hostkeys}g;
        $source =~ s{/install/postscripts/_ssh}{$fixture/postscript-keys}g;
        $source =~ s{(?<!\$ROOTDIR)/root/\.ssh}{$fixture/client}g;
        $source =~ s{(?<!\$ROOTDIR)/etc/ssh/ssh_config}{$fixture/client/ssh_config}g;
        write_text("$fixture/add_ssh", $source);

        my $pid = fork();
        die "fork: $!" unless defined $pid;
        if (!$pid) {
            open(STDOUT, '>', "$fixture/stdout") or die $!;
            open(STDERR, '>', "$fixture/stderr") or die $!;
            $ENV{XCATROOT} = $fixture;
            exec('bash', "$fixture/add_ssh", $image);
            die "exec bash: $!";
        }
        waitpid($pid, 0);
        is($?, 0, "statelite completes with DSA present=$with_dsa");
        is(read_text("$fixture/stderr"), '',
            "statelite reports no missing-key errors with DSA present=$with_dsa");
        like(read_text("$fixture/client/ssh_config"), qr/StrictHostKeyChecking no/,
            'statelite writes client configuration only inside the fixture');
        is(read_text("$image/etc/ssh/ssh_host_rsa_key"), "rsa-host-key\n",
            "statelite preserves the RSA host key with DSA present=$with_dsa");
        is(-f "$image/etc/ssh/ssh_host_dsa_key" ? 1 : 0, $with_dsa,
            'statelite copies the optional DSA key only when supplied');
        is((stat("$image/etc/ssh/ssh_host_rsa_key"))[2] & oct('0777'), oct('0600'),
            'statelite limits host-key permissions');
    }
}

done_testing();
