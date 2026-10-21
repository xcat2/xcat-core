#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

sub read_file {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);
    return $contents;
}

sub shell_function {
    my ($script, $name) = @_;
    my ($definition) = $script =~ /(^\Q$name\E\(\)\n\{.*?^\})/ms;
    return $definition;
}

sub run_function {
    my ($definitions, $invocation, @args) = @_;
    open(my $pipe, '-|', 'bash', '-c', "$definitions\n$invocation", 'bash', @args)
      or die "Unable to run bash: $!";
    my $output = do { local $/; <$pipe> };
    close($pipe);
    is($?, 0, "$invocation exits successfully");
    chomp($output);
    return $output;
}

my $postinit_path = "$FindBin::Bin/../../xCAT/postscripts/xcatpostinit1.netboot";
my $installpost_path = "$FindBin::Bin/../../xCAT/postscripts/xcatinstallpost";
my $postinit = read_file($postinit_path);
my $installpost = read_file($installpost_path);

is(system('bash', '-n', $postinit_path), 0, 'stateless post-init script has valid bash syntax');
is(system('bash', '-n', $installpost_path), 0, 'stateful install-post script has valid bash syntax');

my $postinit_endpoint_host = shell_function($postinit, 'xcat_endpoint_host');
ok(defined($postinit_endpoint_host), 'stateless post-init endpoint parser is present');
is(
    run_function($postinit_endpoint_host, 'xcat_endpoint_host "$1"', '[2001:db8::1]:3001'),
    '2001:db8::1',
    'stateless post-init extracts a complete IPv6 host from XCAT'
);
is(
    run_function($postinit_endpoint_host, 'xcat_endpoint_host "$1"', '192.0.2.1:3001'),
    '192.0.2.1',
    'stateless post-init preserves IPv4 endpoint parsing'
);

my $install_endpoint_host = shell_function($installpost, 'xcat_endpoint_host');
my $install_format_host_port = shell_function($installpost, 'format_host_port');
ok(defined($install_endpoint_host), 'stateful postboot endpoint parser is present');
ok(defined($install_format_host_port), 'stateful postboot endpoint formatter is present');
is(
    run_function(
        "$install_endpoint_host\n$install_format_host_port",
        'format_host_port "$1" "$2"',
        q{'2001:db8::1'}, 3001
    ),
    '[2001:db8::1]:3001',
    'stateful postboot formats an OpenSSL-safe IPv6 endpoint'
);
is(
    run_function(
        "$install_endpoint_host\n$install_format_host_port",
        'format_host_port "$1" "$2"',
        '192.0.2.1', 3001
    ),
    '192.0.2.1:3001',
    'stateful postboot preserves the IPv4 endpoint form'
);
unlike(
    $installpost,
    qr/XCATSERVER="\$SIP:3001"/,
    'stateful postboot never appends a port to a raw server address'
);
is(
    scalar(() = $installpost =~ /updateflag\.awk \\"\\\$MASTER_IP\\" 3002/g),
    2,
    'stateful boot completion callbacks use the quoted resolved master address'
);
unlike(
    $installpost,
    qr/updateflag\.awk \\\$MASTER 3002/,
    'stateful boot completion callbacks do not use an unresolved master hostname'
);

done_testing();
