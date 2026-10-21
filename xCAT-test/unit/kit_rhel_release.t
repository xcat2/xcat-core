#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use POSIX ();
use Test::More;
use XCAT::Test::File qw(repo_path);
require xCAT::Utils;

# kit.pm reads the OS when it loads, so each OS loads it in a process of its own and runs lskit there.
sub lskit_on {
    my ($osver) = @_;
    my $pid = open(my $from_child, '-|') // die "cannot fork: $!";
    if (!$pid) {
        no warnings qw(redefine once);
        *xCAT::Utils::osver = sub { return $osver };

        # The kit lock lives in /var/lock/xcat.
        *xCAT::Utils::is_locked    = sub { return 0 };
        *xCAT::Utils::acquire_lock = sub { return { name => $_[1] } };
        *xCAT::Utils::release_lock = sub { return };
        require(repo_path('xCAT-server/lib/xcat/plugins/kit.pm'));
        my $ran = 0;
        *xCAT_plugin::kit::lskit = sub { $ran = 1; return 0 };
        my @errors;
        xCAT_plugin::kit::process_request({ command => ['lskit'], arg => [] }, sub { push @errors, @{ $_[0]{error} || [] } });
        print(($ran ? 'ran' : 'refused') . ': ' . join(' ', @errors));
        POSIX::_exit(0);
    }
    my $result = do { local $/; <$from_child> };
    close($from_child);
    return $result;
}

is(lskit_on('rhels,7.9'), 'ran: ', 'a kit command runs on RHEL 7');
for my $osver (qw(rhel,8.10 rhels,9.6 rhel,10.1 rhel,11.0)) {
    is(lskit_on($osver), 'refused: KITs are not supported on rhel8 or above', "a kit command is refused on $osver");
}
is(lskit_on('sles,15.6'),     'ran: ', 'the release check leaves SLES alone');
is(lskit_on('ubuntu,24.04'),  'ran: ', 'the release check leaves Ubuntu alone');

done_testing();
