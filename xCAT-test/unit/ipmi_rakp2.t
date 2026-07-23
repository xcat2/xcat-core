#!/usr/bin/env perl

use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)

BEGIN {
    package xCAT::SvrUtils;
    sub import { }
    $INC{'xCAT/SvrUtils.pm'} = __FILE__;

    package Crypt::Rijndael;
    sub import { }
    $INC{'Crypt/Rijndael.pm'} = __FILE__;

    package Crypt::CBC;
    sub import { }
    $INC{'Crypt/CBC.pm'} = __FILE__;

    package Digest::HMAC_SHA1;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{ $caller . '::hmac_sha1' } = \&Digest::SHA::hmac_sha1;
    }
    $INC{'Digest/HMAC_SHA1.pm'} = __FILE__;
}

package main;

no warnings qw/once redefine/;
use Digest::SHA ();
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

require xCAT::IPMI;

my @console_sid = (0x15, 0x58, 0x25, 0x7a);
my @managed_sid = (0x7c, 0x5a, 0xfd, 0xc3);

sub new_session {
    my (%overrides) = @_;
    my $errors = delete($overrides{errors}) || [];
    return bless {
        attempthash                => 256,
        hshfn                      => \&xCAT::IPMI::hmac_sha256,
        hshln                      => 16,
        ipmiversion                => '2.0',
        localsid                   => 0x1558257a,
        onlogon                    => sub { push @{$errors}, $_[0]; },
        onlogon_args               => undef,
        password                   => 'correct-password',
        pendingsessionid           => [@managed_sid],
        privlevel                  => 4,
        rakp_privbyte              => 0x14,
        randomnumber               => [0x10 .. 0x1f],
        rmcptag                    => 3,
        sessionestablishmentcontext => xCAT::IPMI::STATE_EXPECTINGRAKP2(),
        sessionid                  => [0, 0, 0, 0],
        sequencenumberbytes        => [0, 0, 0, 0],
        sidm                       => [@console_sid],
        userid                     => 'test',
        %overrides,
    }, 'xCAT::IPMI';
}

sub rakp2_payload {
    my ($session, $authcode) = @_;
    my @remote_random = (0x20 .. 0x2f);
    my @remote_guid = (0x30 .. 0x3f);
    return (
        $session->{rmcptag}, 0, 0, 0, @{$session->{sidm}},
        @remote_random, @remote_guid, @{$authcode}
    );
}

sub valid_rakp2_payload {
    my ($session) = @_;
    my @remote_random = (0x20 .. 0x2f);
    my @remote_guid = (0x30 .. 0x3f);
    my @user = unpack('C*', $session->{userid});
    my $hmacdata = pack(
        'C*',
        @{$session->{sidm}}, @{$session->{pendingsessionid}},
        @{$session->{randomnumber}}, @remote_random, @remote_guid,
        $session->{rakp_privbyte}, scalar(@user), @user
    );
    my @authcode = unpack(
        'C*',
        $session->{hshfn}->($hmacdata, $session->{password})
    );
    return (
        $session->{rmcptag}, 0, 0, 0, @{$session->{sidm}},
        @remote_random, @remote_guid, @authcode
    );
}

sub valid_rakp4_payload {
    my ($session) = @_;
    my @authcode = unpack(
        'C*',
        $session->{hshfn}->(
            pack(
                'C*',
                @{$session->{randomnumber}},
                @{$session->{pendingsessionid}},
                @{$session->{remoteguid}}
            ),
            $session->{sik}
        )
    );
    return (
        $session->{rmcptag}, 0, 0, 0, @{$session->{sidm}},
        @authcode[0 .. ($session->{hshln} - 1)]
    );
}

# Emulate the defective BMC firmware behavior reported in
# https://github.com/xcat2/xcat-core/issues/7512: suite 17 succeeds, but the
# RAKP2 response contains a 32-byte all-zero authentication code.
my @captured_zero_rakp2 = unpack(
    'C*',
    pack(
        'H*',
        '030000001558257a7fbac96cbf09227865a9cc62745e3d710ce54d903ff5ec11afa30000000000080000000000000000000000000000000000000000000000000000000000000000'
    )
);

is(scalar(@captured_zero_rakp2), 72, 'captured XCC RAKP2 payload is 72 bytes');

subtest 'RMCP response identity validation' => sub {
    my @wrong_sid = @console_sid;
    $wrong_sid[-1] ^= 0xff;
    my $expected_tag = new_session()->{rmcptag};
    my @cases = (
        {
            description => 'matching nonzero tag is accepted even when SID differs',
            tag         => $expected_tag,
            sid         => \@wrong_sid,
            return      => 0,
            advances    => 1,
        },
        {
            description => 'wrong nonzero tag is rejected even when SID matches',
            tag         => $expected_tag + 1,
            sid         => \@console_sid,
            return      => 9,
            advances    => 0,
        },
        {
            description => 'zero tag is accepted when SID matches',
            tag         => 0,
            sid         => \@console_sid,
            return      => 0,
            advances    => 1,
        },
        {
            description => 'zero tag is rejected when SID differs',
            tag         => 0,
            sid         => \@wrong_sid,
            return      => 9,
            advances    => 0,
        },
    );

    foreach my $case (@cases) {
        my $session = new_session(
            sessionestablishmentcontext => xCAT::IPMI::STATE_OPENSESSION(),
        );
        my $rakp1_sent = 0;
        local *xCAT::IPMI::send_rakp1 = sub { $rakp1_sent++; };
        my @response = (
            $case->{tag}, 0, 4, 0, @{$case->{sid}}, @managed_sid,
        );

        is(
            $session->got_rmcp_response(@response),
            $case->{return},
            "$case->{description}: return code"
        );
        is(
            $rakp1_sent,
            $case->{advances},
            "$case->{description}: negotiation advance"
        );
    }

    my $rakp4_session = new_session(
        sessionestablishmentcontext => xCAT::IPMI::STATE_EXPECTINGRAKP4(),
        remoteguid                  => [0x30 .. 0x3f],
        sik                         => 'session-integrity-key',
    );
    my $admin_level_set = 0;
    local *xCAT::IPMI::set_admin_level = sub { $admin_level_set++; };
    my @rakp4_response = valid_rakp4_payload($rakp4_session);
    $rakp4_response[0] = 0;

    is(
        $rakp4_session->got_rakp4(@rakp4_response),
        0,
        'tag-zero RAKP4 with matching SID is accepted'
    );
    is(
        $rakp4_session->{sessionestablishmentcontext},
        xCAT::IPMI::STATE_ESTABLISHED(),
        'tag-zero RAKP4 establishes the session'
    );
    is(
        $admin_level_set,
        1,
        'tag-zero RAKP4 advances to privilege setup'
    );
};

subtest 'malformed RMCP response identity behavior is preserved' => sub {
    my @callers = (
        ['Open Session', 'got_rmcp_response', xCAT::IPMI::STATE_OPENSESSION(),    [6, 4, 1]],
        ['RAKP2',         'got_rakp2',         xCAT::IPMI::STATE_EXPECTINGRAKP2(), [2, 0, 1]],
        ['RAKP4',         'got_rakp4',         xCAT::IPMI::STATE_EXPECTINGRAKP4(), [6, 4, 1]],
    );
    my @payloads = (
        ['missing tag', []],
        ['tag zero without session ID', [0]],
        ['nonnumeric tag with wrong session ID', ['not-a-number', 0, 0, 0, 0, 0, 0, 0]],
    );

    foreach my $caller (@callers) {
        my ($caller_name, $method, $state, $warning_counts) = @{$caller};
        for (my $index = 0; $index < @payloads; $index++) {
            my $payload = $payloads[$index];
            my ($payload_name, $data) = @{$payload};
            my $session = new_session(sessionestablishmentcontext => $state);
            my @warnings;
            my $return;
            {
                local $SIG{__WARN__} = sub { push @warnings, @_ };
                $return = $session->$method(@{$data});
            }

            is($return, 9, "$caller_name rejects $payload_name");
            is(
                scalar(@warnings),
                $warning_counts->[$index],
                "$caller_name preserves warnings for $payload_name"
            );
        }
    }

    my $legacy_session = new_session(
        sessionestablishmentcontext => xCAT::IPMI::STATE_OPENSESSION(),
        sidm                        => [0, 0, 0, 0],
    );
    my $rakp1_sent = 0;
    local *xCAT::IPMI::send_rakp1 = sub { $rakp1_sent++; };
    my @legacy_warnings;
    my $return;
    {
        local $SIG{__WARN__} = sub { push @legacy_warnings, @_ };
        $return = $legacy_session->got_rmcp_response(0, 0, 4, 0);
    }

    is($return, 0, 'short tag-zero response retains legacy SID behavior');
    is($rakp1_sent, 1, 'legacy short response advances to RAKP1');
    is(scalar(@legacy_warnings), 4, 'legacy short response preserves warnings');

    my $wrong_tag_session = new_session();
    my @wrong_tag_warnings;
    {
        local $SIG{__WARN__} = sub { push @wrong_tag_warnings, @_ };
        $return = $wrong_tag_session->got_rakp2(
            $wrong_tag_session->{rmcptag} + 1,
            0, 0, 0, undef, undef, undef, undef
        );
    }
    is($return, 9, 'wrong RAKP2 tag with undefined SID bytes is rejected');
    is(
        scalar(@wrong_tag_warnings),
        4,
        'wrong RAKP2 tag preserves SID evaluation warnings'
    );

    my $zero_tag_session = new_session(rmcptag => 0);
    my @zero_tag_warnings;
    {
        local $SIG{__WARN__} = sub { push @zero_tag_warnings, @_ };
        $return = $zero_tag_session->got_rakp2();
    }
    is($return, 9, 'missing RAKP2 tag retains expected-zero tag behavior');
    is(
        $zero_tag_session->{sessionestablishmentcontext},
        xCAT::IPMI::STATE_FAILED(),
        'missing expected-zero tag retains the password-failure path'
    );
    is(
        scalar(@zero_tag_warnings),
        35,
        'missing expected-zero tag preserves warning count'
    );
};

subtest 'captured all-zero SHA256 RAKP2 retries once with suite 3' => sub {
    my @errors;
    my @sent;
    my $session = new_session(errors => \@errors);
    local *xCAT::IPMI::sendpayload = sub {
        my ($self, %args) = @_;
        push @sent, \%args;
    };

    is($session->got_rakp2(@captured_zero_rakp2), 9, 'invalid response is not accepted');
    is(scalar(@sent), 1, 'one replacement Open Session request is sent');
    is($session->{attempthash}, 1, 'retry selects SHA1');
    ok($session->{zero_rakp2_fallback}, 'fallback is recorded for this login');
    is(
        $session->{sessionestablishmentcontext},
        xCAT::IPMI::STATE_OPENSESSION(),
        'session waits for the replacement Open Session response'
    );
    is_deeply(
        [@{ $sent[0]->{payload} }[12, 20, 28]],
        [1, 1, 1],
        'replacement request proposes suite 3 algorithms'
    );

    my @suite3_response = (
        $session->{rmcptag}, 0, 4, 0, @{$session->{sidm}},
        0x11, 0x22, 0x33, 0x44,
        0, 0, 0, 8, 1, 0, 0, 0,
        1, 0, 0, 8, 1, 0, 0, 0,
        2, 0, 0, 8, 1, 0, 0, 0,
    );
    is($session->got_rmcp_response(@suite3_response), 0, 'suite 3 response is accepted');
    is(scalar(@sent), 2, 'suite 3 response advances to RAKP1');
    is($session->got_rakp2(@captured_zero_rakp2), 9, 'stale SHA256 response is ignored');
    is(scalar(@sent), 2, 'stale response cannot start another fallback');

    my @valid_sha1_rakp2 = valid_rakp2_payload($session);
    is($session->got_rakp2(@valid_sha1_rakp2), 0, 'valid suite 3 RAKP2 is accepted');
    is(scalar(@sent), 3, 'valid suite 3 RAKP2 advances to RAKP3');

    my $admin_level_set = 0;
    local *xCAT::IPMI::set_admin_level = sub { $admin_level_set++; };
    my @valid_sha1_rakp4 = valid_rakp4_payload($session);
    is($session->got_rakp4(@valid_sha1_rakp4), 0, 'valid suite 3 RAKP4 is accepted');
    is(
        $session->{sessionestablishmentcontext},
        xCAT::IPMI::STATE_ESTABLISHED(),
        'suite 3 session is established'
    );
    is($admin_level_set, 1, 'established session advances to privilege setup');
    is_deeply(\@errors, [], 'fallback does not report an incorrect password');
};

subtest 'all-zero SHA1 RAKP2 keeps the existing mismatch path' => sub {
    my @errors;
    my @sent;
    my $session = new_session(
        errors               => \@errors,
        attempthash          => 1,
        hshfn                => \&xCAT::IPMI::hmac_sha1,
        hshln                => 12,
        zero_rakp2_fallback  => 1,
    );
    my @payload = rakp2_payload($session, [(0) x 20]);
    local *xCAT::IPMI::sendpayload = sub { push @sent, 1; };

    is($session->got_rakp2(@payload), 9, 'second invalid response is rejected');
    is(scalar(@sent), 0, 'no second fallback is attempted');
    is(
        $session->{sessionestablishmentcontext},
        xCAT::IPMI::STATE_FAILED(),
        'session fails after the bounded retry'
    );
    is_deeply(
        \@errors,
        ['ERROR: Incorrect password provided'],
        'suite 3 retains the existing mismatch error'
    );
};

subtest 'ordinary HMAC mismatch remains a password failure' => sub {
    my @errors;
    my @sent;
    my $session = new_session(errors => \@errors);
    my @payload = rakp2_payload($session, [0, (1) x 31]);
    local *xCAT::IPMI::sendpayload = sub { push @sent, 1; };

    is($session->got_rakp2(@payload), 9, 'nonzero bad HMAC is rejected');
    is(scalar(@sent), 0, 'ordinary mismatch does not trigger fallback');
    is_deeply(
        \@errors,
        ['ERROR: Incorrect password provided'],
        'existing wrong-password contract is preserved'
    );
};

subtest 'valid SHA256 RAKP2 continues to RAKP3' => sub {
    my @errors;
    my $rakp3_sent = 0;
    my $session = new_session(errors => \@errors);
    my @payload = valid_rakp2_payload($session);
    local *xCAT::IPMI::send_rakp3 = sub { $rakp3_sent++; };

    is($session->got_rakp2(@payload), 0, 'valid response succeeds');
    is($rakp3_sent, 1, 'RAKP3 is sent');
    is(
        $session->{sessionestablishmentcontext},
        xCAT::IPMI::STATE_EXPECTINGRAKP4(),
        'session advances to RAKP4'
    );
    is_deeply(\@errors, [], 'valid response emits no error');
};

subtest 'malformed zero authentication lengths do not downgrade' => sub {
    foreach my $length (31, 33) {
        my @errors;
        my @sent;
        my $session = new_session(errors => \@errors);
        my @payload = rakp2_payload($session, [(0) x $length]);
        local *xCAT::IPMI::sendpayload = sub { push @sent, 1; };

        is($session->got_rakp2(@payload), 9, "$length-byte response is rejected");
        is(scalar(@sent), 0, "$length-byte response does not trigger fallback");
        is_deeply(\@errors, ['ERROR: Incorrect password provided'], 'existing error path is preserved');
    }
};

subtest 'wrong console session ID cannot trigger a downgrade' => sub {
    my @errors;
    my @sent;
    my $session = new_session(errors => \@errors);
    my @payload = @captured_zero_rakp2;
    $payload[4] ^= 0xff;
    local *xCAT::IPMI::sendpayload = sub { push @sent, 1; };

    is($session->got_rakp2(@payload), 9, 'invalid response is rejected');
    is(scalar(@sent), 0, 'stale response cannot force fallback');
    is_deeply(\@errors, ['ERROR: Incorrect password provided'], 'legacy mismatch path is preserved');
    is(
        $session->{sessionestablishmentcontext},
        xCAT::IPMI::STATE_FAILED(),
        'legacy mismatch path fails the exchange'
    );
};

subtest 'legacy tag zero cannot trigger a downgrade' => sub {
    my @errors;
    my @sent;
    my $session = new_session(errors => \@errors);
    my @payload = @captured_zero_rakp2;
    $payload[0] = 0;
    local *xCAT::IPMI::sendpayload = sub { push @sent, 1; };

    is($session->got_rakp2(@payload), 9, 'tag-zero response is rejected by the HMAC check');
    is(scalar(@sent), 0, 'tag-zero response cannot force fallback');
    is_deeply(\@errors, ['ERROR: Incorrect password provided'], 'legacy mismatch path is preserved');
};

subtest 'suite 3 selection survives internal relog initialization' => sub {
    my $session = new_session(zero_rakp2_fallback => 1);
    $session->init();
    is($session->{attempthash}, 1, 'relog initialization keeps SHA1 selected');

    local *xCAT::IPMI::get_channel_auth_cap = sub { };
    $session->login(callback => sub { }, callback_args => undef);
    is($session->{attempthash}, 256, 'a new external login starts with SHA256');
    ok(!exists($session->{zero_rakp2_fallback}), 'a new external login clears the fallback flag');
};

done_testing();
