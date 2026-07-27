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

subtest 'Open Session errors retry once with suite 3 without persisting' => sub {
    my @cases = (
        [0x09, 'Invalid role'],
        [0x11, 'No cipher suite match with proposed security algorithms'],
    );

    foreach my $case (@cases) {
        my ($code, $error) = @{$case};
        my @errors;
        my @sent;
        my $session = new_session(
            errors => \@errors,
            sessionestablishmentcontext => xCAT::IPMI::STATE_OPENSESSION(),
        );
        my $original_localsid = $session->{localsid};
        my $original_tag = $session->{rmcptag};
        local *xCAT::IPMI::sendpayload = sub {
            my ($self, %args) = @_;
            push @sent, \%args;
        };

        is(
            $session->got_rmcp_response($original_tag, $code),
            9,
            sprintf('Open Session code 0x%02x is rejected', $code),
        );
        is(scalar(@sent), 1, 'one replacement Open Session request is sent');
        is($session->{attempthash}, 1, 'replacement request selects SHA1');
        ok(!exists($session->{zero_rakp2_fallback}), 'ordinary fallback is not persisted');
        is($session->{localsid}, $original_localsid + 1, 'replacement request uses a new console session ID');
        is($session->{rmcptag}, $original_tag + 1, 'replacement request uses a new message tag');
        is(
            $session->{sessionestablishmentcontext},
            xCAT::IPMI::STATE_OPENSESSION(),
            'session waits for the replacement Open Session response',
        );
        is_deeply(
            [@{ $sent[0]->{payload} }[12, 20, 28]],
            [1, 1, 1],
            'replacement request proposes suite 3 algorithms',
        );
        is_deeply(\@errors, [], 'fallback does not invoke the login callback');

        is(
            $session->got_rmcp_response($session->{rmcptag}, $code),
            9,
            'the replacement rejection keeps the existing error return',
        );
        is(scalar(@sent), 1, 'SHA1 is not downgraded a second time');
        is_deeply(\@errors, ["ERROR: $error"], 'the replacement rejection reports the existing error');
    }
};

subtest 'RAKP2 role errors retry once with suite 3 without persisting' => sub {
    my @cases = (
        [0x09, 'Invalid role'],
        [0x0d, 'Unauthorized name'],
    );

    foreach my $case (@cases) {
        my ($code, $error) = @{$case};
        my @errors;
        my @sent;
        my $session = new_session(errors => \@errors, privlevel => 3);
        my $original_localsid = $session->{localsid};
        my $original_tag = $session->{rmcptag};
        local *xCAT::IPMI::sendpayload = sub {
            my ($self, %args) = @_;
            push @sent, \%args;
        };

        is(
            $session->got_rakp2($original_tag, $code),
            undef,
            sprintf('RAKP2 code 0x%02x keeps the retry return', $code),
        );
        is(scalar(@sent), 1, 'one replacement Open Session request is sent');
        is($session->{attempthash}, 1, 'replacement request selects SHA1');
        ok(!exists($session->{zero_rakp2_fallback}), 'ordinary fallback is not persisted');
        is($session->{localsid}, $original_localsid + 1, 'replacement request uses a new console session ID');
        is($session->{rmcptag}, $original_tag + 1, 'replacement request uses a new message tag');
        is_deeply(
            [@{ $sent[0]->{payload} }[12, 20, 28]],
            [1, 1, 1],
            'replacement request proposes suite 3 algorithms',
        );
        is_deeply(\@errors, [], 'fallback does not invoke the login callback');

        $session->{sessionestablishmentcontext} = xCAT::IPMI::STATE_EXPECTINGRAKP2();
        is(
            $session->got_rakp2($session->{rmcptag}, $code),
            9,
            'the replacement rejection keeps the existing error return',
        );
        is(scalar(@sent), 1, 'SHA1 is not downgraded a second time');
        is_deeply(\@errors, ["ERROR: $error"], 'the replacement rejection reports the existing error');
        is(
            $session->{sessionestablishmentcontext},
            xCAT::IPMI::STATE_FAILED(),
            'the replacement rejection fails the exchange',
        );
    }
};

subtest 'captured all-zero SHA256 RAKP2 retries once with suite 3' => sub {
    my @errors;
    my @sent;
    my $session = new_session(errors => \@errors);
    my $original_localsid = $session->{localsid};
    my $original_tag = $session->{rmcptag};
    local *xCAT::IPMI::sendpayload = sub {
        my ($self, %args) = @_;
        push @sent, \%args;
    };

    is($session->got_rakp2(@captured_zero_rakp2), 9, 'invalid response is not accepted');
    is(scalar(@sent), 1, 'one replacement Open Session request is sent');
    is($session->{attempthash}, 1, 'retry selects SHA1');
    ok($session->{zero_rakp2_fallback}, 'fallback is recorded for this login');
    is($session->{localsid}, $original_localsid + 1, 'replacement request uses a new console session ID');
    is($session->{rmcptag}, $original_tag + 1, 'replacement request uses a new message tag');
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
