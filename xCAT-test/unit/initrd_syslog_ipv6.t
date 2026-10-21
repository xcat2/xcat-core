#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempfile);
use FindBin;
use Test::More;

my $source = File::Spec->catfile(
    $FindBin::Bin, '..', '..',
    'xCAT-server/share/xcat/netboot/rh/dracut_105/patch/syslog/rsyslogd-start.sh'
);
open(my $source_fh, '<', $source) or die "Unable to read $source: $!";
my $content = do { local $/; <$source_fh> };
close($source_fh);

is(system('sh', '-n', $source), 0, 'initrd rsyslog launcher has valid shell syntax');

sub shell_function {
    my ($name) = @_;
    my ($definition) = $content =~ /(^\Q$name\E\(\)\s*\{.*?^\})/ms;
    die "Unable to extract $name from $source" unless defined($definition);
    return $definition;
}

my $format = shell_function('format_syslog_server');
my $configure = shell_function('rsyslog_config');
my ($template_fh, $template_path) = tempfile();
print {$template_fh} "# base config\n";
close($template_fh);

sub render_config {
    my ($server) = @_;
    open(
        my $pipe, '-|', 'sh', '-c',
        "$format\n$configure\nrsyslog_config \"\$1\" \"\$2\" '*.*'",
        'sh', $server, $template_path
    ) or die "Unable to run initrd rsyslog helper: $!";
    my $output = do { local $/; <$pipe> };
    close($pipe);
    is($?, 0, "rsyslog configuration renders for $server");
    return $output;
}

like(
    render_config('192.0.2.10'),
    qr/^\*\.\* \@192\.0\.2\.10$/m,
    'IPv4 initrd forwarding target remains unchanged'
);
like(
    render_config('logs.example.test'),
    qr/^\*\.\* \@logs\.example\.test$/m,
    'hostname initrd forwarding target remains unchanged'
);
like(
    render_config('2001:db8::10'),
    qr/^\*\.\* \@\[2001:db8::10\]$/m,
    'IPv6 initrd forwarding target is bracketed'
);
like(
    render_config('[2001:db8::10]'),
    qr/^\*\.\* \@\[2001:db8::10\]$/m,
    'already-bracketed IPv6 initrd target is not double-bracketed'
);

done_testing();
