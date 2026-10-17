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
use XCAT::Test::Process qw(run_command);

my $root = tempdir(CLEANUP => 1);
make_path("$root/bin");
write_text("$root/bin/openssl", <<'SH');
#!/bin/sh
printf '%s\n' "$1" >> "$CALLS"
if [ "$1" = "$ACCEPT" ]; then
    printf 'public key\n'
    exit 0
fi
printf '%s failed\n' "$1" >&2
exit 73
SH
chmod 0755, "$root/bin/openssl" or die "chmod openssl: $!";
local $ENV{PATH} = "$root/bin:$ENV{PATH}";
local $ENV{CALLS} = "$root/calls";

for my $library ('xCAT-genesis-scripts/usr/lib/xcat/fips.sh', 'xCAT/postscripts/xcatlib.sh') {
    my $shell = $library =~ /genesis/ ? 'sh' : 'bash';
    for my $mode (0, 1) {
        for my $case (['pkey', "pkey\n"], ['rsa', "pkey\nrsa\n"],
            ['ec', "pkey\nrsa\nec\n"], ['none', "pkey\nrsa\nec\n"]) {
            my ($accept, $calls) = @$case;
            local $ENV{ACCEPT} = $accept;
            write_text($ENV{CALLS}, '');
            my ($rc, $output) = run_command($shell, '-c',
                '. "$1"; xcat_discovery_public_key "$2" unused-key',
                'fips-fallback-test', repo_path($library), $mode);
            is($rc, $accept eq 'none' ? 73 : 0, "$library mode $mode exports through $accept");
            is($output, $accept eq 'none' ? "ec failed\n" : "public key\n",
                'only the final error or successful key reaches the caller');
            is(read_text($ENV{CALLS}), $calls, 'fallbacks run in order and stop on success');
        }
    }
}

done_testing();
