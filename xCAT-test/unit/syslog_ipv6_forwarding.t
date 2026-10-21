#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $source = File::Spec->catfile(
    $FindBin::Bin, '..', '..', 'xCAT', 'postscripts', 'syslog'
);
open( my $source_fh, '<', $source ) or die "Unable to read $source: $!";
my $content = do { local $/; <$source_fh> };
close($source_fh);

sub shell_function {
    my ($name) = @_;
    my ($definition) =
      $content =~ /(^\Q$name\E\(\)\s*\n\{.*?^\})/ms;
    die "Unable to extract $name from $source" unless defined($definition);
    return $definition;
}

sub run_shell_function {
    my ( $definition, $invocation, @args ) = @_;
    open( my $pipe, '-|', 'bash', '-c', "$definition\n$invocation", 'bash', @args )
      or die "Unable to run bash: $!";
    my $output = do { local $/; <$pipe> };
    close($pipe);
    is( $?, 0, "$invocation exits successfully" );
    chomp($output);
    return $output;
}

is( system( 'bash', '-n', $source ), 0, 'syslog postscript has valid bash syntax' );

my $format_target = shell_function('format_syslog_forward_target');
is(
    run_shell_function( $format_target, 'format_syslog_forward_target "$1"', '192.0.2.10' ),
    '192.0.2.10',
    'IPv4 rsyslog targets remain byte-for-byte unchanged'
);
is(
    run_shell_function( $format_target, 'format_syslog_forward_target "$1"', 'logs.example.test' ),
    'logs.example.test',
    'hostname rsyslog targets remain byte-for-byte unchanged'
);
is(
    run_shell_function( $format_target, 'format_syslog_forward_target "$1"', '2001:db8::10' ),
    '[2001:db8::10]',
    'IPv6 rsyslog targets are bracketed to disambiguate address colons from a port'
);
is(
    run_shell_function( $format_target, 'format_syslog_forward_target "$1"', '[2001:db8::10]' ),
    '[2001:db8::10]',
    'an already-bracketed IPv6 rsyslog target is not double-bracketed'
);

my $syslog_ng_driver = shell_function('syslog_ng_udp_driver');
is(
    run_shell_function( $syslog_ng_driver, 'syslog_ng_udp_driver "$1"', '192.0.2.10' ),
    'udp',
    'syslog-ng keeps its legacy IPv4 UDP destination for IPv4 targets'
);
is(
    run_shell_function( $syslog_ng_driver, 'syslog_ng_udp_driver "$1"', 'logs.example.test' ),
    'udp',
    'syslog-ng keeps name resolution behavior for hostname targets'
);
is(
    run_shell_function( $syslog_ng_driver, 'syslog_ng_udp_driver "$1"', '2001:db8::10' ),
    'udp6',
    'syslog-ng selects its IPv6 UDP destination for an IPv6 literal'
);

unlike(
    $content,
    qr/echo\s+"[^"\n]*@\$master/,
    'no rsyslog or traditional syslog forwarding rule appends a raw master address'
);
is(
    scalar( () = $content =~ /echo\s+"[^"\n]*@\$syslog_forward_target/g ),
    5,
    'all selector-style forwarding paths use the family-safe target'
);
like(
    $content,
    qr/syslog_ng_driver=\$\(syslog_ng_udp_driver "\$master"\).*?\$\{syslog_ng_driver\}\(\\"\$master\\"\)/s,
    'syslog-ng emits the selected address-family-specific destination driver'
);

done_testing();
