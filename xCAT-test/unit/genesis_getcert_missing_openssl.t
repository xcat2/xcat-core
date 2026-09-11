#!/usr/bin/env perl
# Drive getcert with openssl absent, and with a certificate key that is not ready yet.
# doxcat runs getcert in the foreground and ignores its status, so a wait with no bound stops
# the boot and prints nothing.
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $getcert = repo_path('xCAT-genesis-scripts/usr/bin/getcert');
plan skip_all => 'getcert not found' unless -f $getcert;
plan tests => 7;

my $tmpdir = tempdir(CLEANUP => 1);

# The el10 legacy image ships no openssl. getcert must say so and give up.
my $bin = stub_dir(openssl => undef);
my ($status, $out) = run_getcert($bin, 10, 60);
isnt($status, 124, 'getcert without openssl stops on its own') or diag($out);
isnt($status, 0,   'getcert without openssl reports a failure');
like($out, qr/openssl/, 'getcert names openssl');

# doxcat writes /etc/xcat/certkey.pem in the background, so the first requests can fail.
# getcert must keep asking, then give up and say why.
my $counter = "$tmpdir/req-count";
$bin = stub_dir(openssl => "always-fails", counter => $counter);
($status, $out) = run_getcert($bin, 30, 5);
isnt($status, 124, 'getcert with an unusable key stops on its own') or diag($out);
isnt($status, 0,   'getcert with an unusable key reports a failure');
my $tries = -f $counter ? scalar(() = read_text($counter) =~ /req/g) : 0;
cmp_ok($tries, '>', 1, "getcert retries the certificate request ($tries tries)");
like($out, qr/certkey\.pem/, 'getcert names the key it could not use');

#---
# stub_dir: a PATH directory holding the commands getcert runs. openssl is absent when the
# openssl option is undef.
#---
sub stub_dir {
    my (%opt) = @_;
    my $dir = tempdir(DIR => $tmpdir, CLEANUP => 1);
    write_stub($dir, 'allowcred.awk', "exec sleep 3\n");
    write_stub($dir, 'hostname',      "echo node1\n");
    write_stub($dir, 'logger',        "echo \"\$@\" >&2\n");
    write_stub($dir, 'sleep',         "exec /bin/sleep \"\$@\"\n");
    if (defined $opt{openssl}) {
        my $count = $opt{counter} ? "echo req >> '$opt{counter}'\n" : '';
        write_stub($dir, 'openssl', "[ \"\$1\" = req ] && { $count exit 1; }\nexit 0\n");
    }
    return $dir;
}

sub write_stub {
    my ($dir, $name, $body) = @_;
    write_text("$dir/$name", "#!/bin/sh\n$body");
    chmod 0755, "$dir/$name";
    return;
}

#---
# run_getcert: run getcert with only the stub directory on PATH. The timeout is the harness
# guard: a status of 124 means getcert never stopped.
#---
sub run_getcert {
    my ($bin, $limit, $csr_timeout) = @_;
    my $outfile = "$tmpdir/out.$$";
    my $cmd = sprintf(
        "timeout -k 2 %d env PATH=%s GETCERT_CSR_TIMEOUT=%d /bin/bash %s 192.0.2.1:3001 >%s 2>&1 </dev/null",
        $limit, $bin, $csr_timeout, $getcert, $outfile);
    system($cmd);
    my $status = $? >> 8;
    my $out = -f $outfile ? read_text($outfile) : '';
    unlink $outfile;
    return ($status, $out);
}
