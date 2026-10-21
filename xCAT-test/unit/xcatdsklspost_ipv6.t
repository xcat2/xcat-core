#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Temp qw(tempfile);
use Test::More;

my $source = "$FindBin::Bin/../../xCAT/postscripts/xcatdsklspost";
open(my $source_fh, '<', $source) or die "Unable to read $source: $!";
my $content = do { local $/; <$source_fh> };
close($source_fh);

sub shell_function {
    my ($name) = @_;
    my ($function) = $content =~ /^(\Q$name\E \(\)\n\{.*?^\})/ms;
    die "Unable to extract $name from $source" unless defined($function);
    return $function;
}

my ($fh, $script) = tempfile();
print {$fh} shell_function('parsehttpserver'), "\n";
print {$fh} shell_function('format_host_port'), "\n";
print {$fh} <<'SHELL';
set -e
check() {
    expected=$1
    shift
    actual="$($@)"
    [ "$actual" = "$expected" ] || {
        echo "expected '$expected', got '$actual' from: $*" >&2
        exit 1
    }
}
check 192.0.2.10 parsehttpserver 192.0.2.10 server
check 80 parsehttpserver 192.0.2.10 port
check manager.example.test parsehttpserver manager.example.test:8080 server
check 8080 parsehttpserver manager.example.test:8080 port
check 2001:db8::10 parsehttpserver '[2001:db8::10]:8443' server
check 8443 parsehttpserver '[2001:db8::10]:8443' port
check 2001:db8::10 parsehttpserver 2001:db8::10 server
check 80 parsehttpserver 2001:db8::10 port
check 2001:db8::10 parsehttpserver '[2001:db8::10]' server
check 80 parsehttpserver '[2001:db8::10]' port
check 192.0.2.10:3001 format_host_port 192.0.2.10 3001
check manager.example.test:3001 format_host_port manager.example.test 3001
check '[2001:db8::10]:3001' format_host_port 2001:db8::10 3001
check '[2001:db8::10]:3001' format_host_port '[2001:db8::10]' 3001
SHELL
close($fh);

is(system('bash', $script), 0, 'endpoint helpers preserve IPv4 and support bracketed IPv6');

like(
    $content,
    qr/wget .*"http:\/\/\$authority\$INSTALLDIR\/postscripts\/"/,
    'recursive postscript download quotes the normalized HTTP authority'
);
like(
    $content,
    qr/XCATSERVER=\$\(format_host_port "\$SIP" 3001\)/,
    'runtime xCAT endpoint is formatted with IPv6 brackets when needed'
);
unlike(
    $content,
    qr/(?:XCATSERVER|SIP)=`echo \$(?:TMP|i) \| cut -d: -f1`/,
    'kernel XCAT endpoint is not truncated at the first IPv6 colon'
);

is(
    scalar(() = $content =~ /updateflag\.awk \\\"\\\$MASTER_IP\\\" 3002/g),
    4,
    'all generated boot completion callbacks use the quoted resolved master address'
);
unlike(
    $content,
    qr/updateflag\.awk \\\$MASTER 3002/,
    'generated boot completion callbacks do not use an unresolved master hostname'
);

done_testing();
