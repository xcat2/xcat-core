#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;
use XCAT::Test::File qw(repo_path);
require xCAT::Utils;

# The kit lock lives in /var/lock/xcat. Like flock, the test lock has one holder, and a second open of it fails.
our ($OTHER, $HELD, $NESTED, @RAN);
{
    no warnings qw(redefine once);

    # kit.pm reads the OS when it loads, and refuses kits on RHEL 8 and later.
    *xCAT::Utils::osver = sub { return 'rhels,7.9' };
    *xCAT::Utils::acquire_lock = sub {
        return if $OTHER || $HELD;
        $HELD = 1;
        return { name => $_[1] };
    };
    *xCAT::Utils::release_lock = sub { $HELD = 0; return };
}
require(repo_path('xCAT-server/lib/xcat/plugins/kit.pm'));

sub kit_command {
    my ($command) = @_;
    my @errors;
    xCAT_plugin::kit::process_request({ command => [$command], arg => [] }, sub { push @errors, @{ $_[0]{error} || [] } });
    return join("\n", @errors);
}
{
    no warnings qw(redefine once);

    # lskit runs lskitcomp in the same process when the test asks for it, as runxcmd does.
    *xCAT_plugin::kit::lskit = sub {
        push @RAN, $HELD ? 'lskit' : 'lskit without the lock';
        push @RAN, 'lskitcomp: ' . kit_command('lskitcomp') if $NESTED;
        return 0;
    };
    *xCAT_plugin::kit::lskitcomp = sub { push @RAN, $HELD ? 'lskitcomp' : 'lskitcomp without the lock'; return 0 };
}

sub lskit { @RAN = (); return kit_command('lskit') }

{
    local ($OTHER, $HELD, $NESTED) = (0, 0, 0);
    is(lskit(), '', 'a kit command reports no error while no process holds the kit lock');
    is_deeply(\@RAN, ['lskit'], 'a kit command runs while it holds the kit lock');
    ok(!$HELD, 'a kit command releases the kit lock');
}

{
    # This process ran a kit command before, and another process holds the lock now.
    local ($OTHER, $HELD, $NESTED) = (1, 0, 0);
    like(lskit(), qr/another process is running/, 'a kit command reports the kit lock that another process holds');
    is_deeply(\@RAN, [], 'a kit command does not run while another process holds the kit lock');
}

{
    local ($OTHER, $HELD, $NESTED) = (0, 0, 1);
    is(lskit(), '', 'a kit command that runs another kit command reports no error');
    is_deeply(\@RAN, [ 'lskit', 'lskitcomp', 'lskitcomp: ' ], 'the kit command that it runs goes on under its lock');
    ok(!$HELD, 'the outer kit command releases the kit lock');
}

done_testing();
