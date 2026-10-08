#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Slurper qw(read_lines);
use Test::More;

# The unit file is the artifact: systemd reads it, nothing in the tree runs it.
my $unit_file = "$FindBin::Bin/../../xCAT-server/etc/init.d/xcatd.service";

# Returns the [Service] settings as name => [values], in file order.
sub service_settings {
    my ($path) = @_;

    my (%settings, $section);
    foreach my $line (read_lines($path)) {
        next if $line =~ /^\s*(?:#|;|$)/;
        if ($line =~ /^\s*\[(\w+)\]\s*$/) {
            $section = $1;
            next;
        }
        next unless defined $section && $section eq 'Service';
        my ($name, $value) = $line =~ /^\s*(\w+)\s*=\s*(.*?)\s*$/ or next;
        push @{ $settings{$name} }, $value;
    }

    return \%settings;
}

my $service = service_settings($unit_file);

# systemd starts a shell in initrc_t and a bin_t binary in unconfined_service_t.
my @exec = @{ $service->{ExecStart} || [] };
is(scalar(@exec), 1, 'the unit has one ExecStart');
my ($program) = split /\s+/, ($exec[0] // '');
is($program, '/usr/sbin/xcatd', 'ExecStart runs the xcatd binary, not a shell');
like($exec[0] // '', qr{\s-p\s+/run/xcatd\.pid(?:\s|$)},
    '... and passes the pid file that PIDFile names');
is_deeply($service->{PIDFile}, ['/run/xcatd.pid'], 'PIDFile is /run/xcatd.pid');

# Environment= replaces what /etc/profile.d/xcat.sh gave xcatd.
my %env;
foreach my $setting (@{ $service->{Environment} || [] }) {
    foreach my $pair ($setting =~ /("[^"]*"|\S+)/g) {
        $pair =~ s/^"|"$//g;
        my ($name, $value) = split /=/, $pair, 2;
        $env{$name} = $value;
    }
}
is($env{XCATROOT}, '/opt/xcat', 'the unit sets XCATROOT=/opt/xcat');
is($env{PERL_BADLANG}, '0', 'the unit sets PERL_BADLANG=0');
my @path = split /:/, ($env{PATH} // '');
foreach my $dir (qw(/opt/xcat/bin /opt/xcat/sbin /opt/xcat/share/xcat/tools
    /usr/sbin /usr/bin /sbin /bin)) {
    ok((grep { $_ eq $dir } @path), "the unit PATH has $dir");
}

is_deeply($service->{EnvironmentFile}, ['-/etc/sysconfig/xcat'],
    '/etc/sysconfig/xcat can still override the environment');

done_testing();
