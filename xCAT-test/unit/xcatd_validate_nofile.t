#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

my $xcatdlib = "$FindBin::Bin/../../xCAT-server/lib/perl";
plan skip_all => 'xcatd.pm not found' unless -r "$xcatdlib/xCAT/xcatd.pm";

# Load xcatd.pm with stub modules. The policy is one nameless rule that allows
# rpower. An authorized request returns 1, so only the ^file guard can deny it.
# NodeRange is a spy. It records the expansion and reports a rejected ^file, as
# the real module does.
BEGIN {
    for my $mod (qw(Date::Parse xCAT::Table xCAT::TableUtils xCAT::MsgUtils
        xCAT::Utils xCAT::NodeRange)) {
        (my $path = $mod) =~ s{::}{/}g;
        $INC{"$path.pm"} = 1;
    }

    package Date::Parse;
    package xCAT::TableUtils;
    our $AUTOLOAD; sub AUTOLOAD { return } sub DESTROY { }

    package xCAT::MsgUtils;
    our $AUTOLOAD2; sub AUTOLOAD { return } sub DESTROY { }

    package xCAT::Utils;
    our $AUTOLOAD3; sub AUTOLOAD { return } sub DESTROY { }

    package xCAT::Table;
    sub new { return bless {}, shift }
    sub getAllEntries { return [ { priority => 1, rule => 'allow', commands => 'rpower' } ] }
    sub close { }
    our $AUTOLOAD4; sub AUTOLOAD { return } sub DESTROY { }

    package xCAT::NodeRange;
    our @CALLS;
    our $REJECTED = 0;
    sub noderange {
        my ($range, undef, undef, %opts) = @_;
        push @CALLS, [@_];
        $REJECTED = ($opts{nofile} && defined $range && $range =~ /\^/) ? 1 : 0;
        return ('somenode');
    }
    sub file_operator_rejected { return $REJECTED }
    sub nodesmissed { return () }
    our $AUTOLOAD5; sub AUTOLOAD { return } sub DESTROY { }
}

push @INC, $xcatdlib;
require xCAT::xcatd;

sub run {
    my ($peername, $noderange) = @_;
    @xCAT::NodeRange::CALLS = ();
    my $req = { command => ['rpower'], noderange => [$noderange] };
    my $rc = xCAT::xcatd->validate($peername, '10.0.0.9', $req, '10.0.0.9', []);
    my ($call) = grep { defined $_->[0] && $_->[0] eq $noderange } @xCAT::NodeRange::CALLS;
    my $nofile = 0;
    if ($call) {
        my @a = @$call;
        for my $i (1 .. $#a - 1) {
            $nofile = $a[$i + 1] if defined $a[$i] && $a[$i] eq 'nofile';
        }
    }
    return ($rc, $nofile);
}

my ($rc_auth, $nf_auth) = run('someuser', '^/etc/shadow');
ok(!$nf_auth, 'authenticated: the ^ file operator is honored (no nofile)');
is($rc_auth, 1, 'authenticated: an authorized ^file request is allowed');

my ($rc_anon) = run(undef, '^/etc/shadow');
is($rc_anon, 0, 'unauthenticated: a ^file request is denied (fail closed)');

my ($rc_mixed) = run(undef, 'node01,^touch /tmp/x |');
is($rc_mixed, 0, 'unauthenticated: a mixed node,^file range is denied');

my (undef, $nf_zero) = run('0', '^/etc/shadow');
ok(!$nf_zero, 'identity "0" is treated as authenticated, not anonymous');

done_testing();
