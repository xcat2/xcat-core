#!/usr/bin/env perl
use strict;
use warnings;
## no critic (TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use Test::More;
use lib "$FindBin::Bin/../../perl-xCAT";

our %test_users = (
    alice => [ 'alice', 'x', 1000, 100 ],
    bob   => [ 'bob',   'x', 1001, 102 ],
);
our %test_groups = (
    primary => [ 'primary', 'x', 100, '' ],
    ops     => [ 'ops',     'x', 101, 'alice bob' ],
    devops  => [ 'devops',  'x', 102, 'bob' ],
    root    => [ 'root',    'x',   0, 'alice' ],
);
our %test_getgrnam_calls;

BEGIN {
    *CORE::GLOBAL::getpwnam = sub {
        my ($username) = @_;
        return unless exists $main::test_users{$username};
        return @{ $main::test_users{$username} };
    };
    *CORE::GLOBAL::getgrnam = sub {
        my ($group_name) = @_;
        $main::test_getgrnam_calls{$group_name}++;
        return unless exists $main::test_groups{$group_name};
        return @{ $main::test_groups{$group_name} };
    };
    *CORE::GLOBAL::setgrent = sub { die 'group enumeration is not allowed'; };
    *CORE::GLOBAL::getgrent = sub { die 'group enumeration is not allowed'; };
    *CORE::GLOBAL::endgrent = sub { die 'group enumeration is not allowed'; };

    package xCAT::Table;
    our $policies = [];
    sub new { return bless {}, shift; }
    sub getAllEntries { return $policies; }
    sub close { return; }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::TableUtils;
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::MsgUtils;
    sub message { return; }
    $INC{'xCAT/MsgUtils.pm'} = __FILE__;

    package xCAT::NodeRange;
    sub noderange { return; }
    $INC{'xCAT/NodeRange.pm'} = __FILE__;

}

require xCAT::Utils;

my $source_xcatd = "$FindBin::Bin/../../xCAT-server/lib/perl/xCAT/xcatd.pm";
require $source_xcatd;

my $source_rollupdate = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/rollupdate.pm";
require $source_rollupdate;

sub validate_policies {
    my ($peername, $policies, $request_username) = @_;
    $xCAT::Table::policies = $policies;

    my $request = {
        command   => ['nodels'],
        noderange => [],
        arg       => [],
        username  => [ $request_username || $peername ],
    };
    my @deferred_messages;
    my $allowed = xCAT::xcatd->validate(
        $peername,
        'localhost',
        $request,
        undef,
        \@deferred_messages,
    );
    return ($allowed, $request->{username}->[0]);
}

sub validate_policy {
    my ($peername, $name, $rule, $request_username) = @_;
    return validate_policies(
        $peername,
        [ {
            priority => 1,
            name     => $name,
            rule     => $rule || 'allow',
        } ],
        $request_username,
    );
}

sub rollupdate_policy {
    my ($userid, $name) = @_;
    $xCAT::Table::policies = [ {
        name     => $name,
        commands => 'runrollupdate',
        rule     => 'allow',
    } ];
    return xCAT_plugin::rollupdate::check_policy($userid, 'runrollupdate');
}

ok(
    xCAT::Utils->user_matches_policy_name('alice', 'alice'),
    'bare policy name matches an exact username',
);
ok(
    !xCAT::Utils->user_matches_policy_name('alice', 'root'),
    'bare policy name does not match a same-named Unix group',
);
ok(
    xCAT::Utils->user_matches_policy_name('alice', '%primary'),
    'explicit primary group matches by gid',
);
ok(
    xCAT::Utils->user_matches_policy_name('alice', '%ops'),
    'explicit supplementary group matches an exact member',
);
ok(
    !xCAT::Utils->user_matches_policy_name('alice', '%op'),
    'partial group names do not match',
);
ok(
    !xCAT::Utils->user_matches_policy_name('alice', '%devops'),
    'nonmember group does not match',
);
ok(
    !xCAT::Utils->user_matches_policy_name('missing', '%ops'),
    'group lookup fails closed for an unknown user',
);
ok(
    !xCAT::Utils->user_matches_policy_name('alice', '%'),
    'empty group principal fails closed',
);
ok(
    !xCAT::Utils->user_matches_policy_name('alice', "%ops\n"),
    'group principal with a trailing newline fails closed',
);

my ($allowed) = validate_policy('alice', 'alice');
ok($allowed, 'existing username policy behavior is preserved');

($allowed) = validate_policy('alice', '%primary');
ok($allowed, 'primary group policy allows a member');

($allowed) = validate_policy('alice', '%ops');
ok($allowed, 'supplementary group policy allows a member');

($allowed) = validate_policy('alice', 'root');
ok(!$allowed, 'existing username rule is not widened by a group collision');

($allowed) = validate_policy('alice', '%devops');
ok(!$allowed, 'nonmember group policy denies access');

($allowed) = validate_policy('missing', '%ops');
ok(!$allowed, 'unknown user does not gain group access');

($allowed) = validate_policy('missing', 'missing');
ok($allowed, 'unknown user can still match the existing username policy path');

my $effective_username;
($allowed, $effective_username) = validate_policy('alice', '%ops', 'trusted', 'spoofed');
ok($allowed, 'trusted group rule can allow its command');
is($effective_username, 'alice', 'group rule does not grant trusted identity handling');

($allowed, $effective_username) = validate_policies(
    '%ops',
    [
        { priority => 1, name => '%ops', commands => 'lsdef', rule => 'trusted' },
        { priority => 2, name => '*', rule => 'allow' },
    ],
    'spoofed',
);
ok($allowed, 'later wildcard rule allows a percent-prefixed username');
is($effective_username, '%ops', 'group principal cannot grant trusted identity by name collision');

($allowed, $effective_username) = validate_policy('alice', 'alice', 'trusted', 'spoofed');
ok($allowed, 'trusted username rule still allows its command');
is($effective_username, 'spoofed', 'trusted username rule preserves existing identity handling');

%test_getgrnam_calls = ();
($allowed) = validate_policies(
    'alice',
    [
        { priority => 1, name => '%ops', commands => 'lsdef', rule => 'allow' },
        { priority => 2, name => '%ops', rule => 'allow' },
    ],
);
ok($allowed, 'later duplicate group rule can allow the command');
is($test_getgrnam_calls{ops}, 1, 'group match is cached within one policy evaluation');

is(rollupdate_policy('alice', '%ops'), 0, 'rollupdate accepts an explicit group policy');
is(rollupdate_policy('alice', 'root'), 1, 'rollupdate preserves username-only bare names');
is(rollupdate_policy('alice', 'alice'), 0, 'rollupdate preserves direct username policies');

done_testing();
