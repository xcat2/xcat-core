#!/usr/bin/env perl

use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)
no warnings qw(once redefine);

use File::Spec;
use FindBin;
use Test::More;

BEGIN {
    for my $module (qw(
      xCAT::GlobalDef xCAT_monitoring::monitorctrl xCAT::IPMI
      xCAT::BMCUtils xCAT::PasswordUtils xCAT::Utils xCAT::TableUtils
      xCAT::IMMUtils xCAT::ServiceNodeUtils xCAT::NetworkUtils xCAT::Usage
      xCAT::data::ibmhwtypes xCAT::data::ibmleds
      xCAT::data::ipmigenericevents xCAT::data::ipmisensorevents
      IBM::EnergyManager
    )) {
        (my $file = $module) =~ s{::}{/}g;
        $INC{"$file.pm"} = __FILE__;
        no strict 'refs';
        *{"${module}::import"} = sub { };
    }

    package xCAT::SvrUtils;
    our @messages;
    sub import { }
    sub sendmsg { push @messages, $_[0]; }
    $INC{'xCAT/SvrUtils.pm'} = __FILE__;

    package xCAT::SPD;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::decode_spd"} = sub { return; };
    }
    $INC{'xCAT/SPD.pm'} = __FILE__;

    package File::Path;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::mkpath"} = sub { return; };
    }
    $INC{'File/Path.pm'} = __FILE__;

    package Thread;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::yield"} = sub { return; };
    }
    $INC{'Thread.pm'} = __FILE__;

    package LWP;
    our $VERSION = 5.64;
    sub import { }
    $INC{'LWP.pm'} = __FILE__;

    package HTTP::Request::Common;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::GET"}  = sub { return; };
        *{"${caller}::POST"} = sub { return; };
    }
    $INC{'HTTP/Request/Common.pm'} = __FILE__;

    package main;
    *CORE::GLOBAL::chmod = sub (@) { return 1; };
}

package main;

my $repo_root = File::Spec->catdir($FindBin::Bin, '..', '..');
$ENV{XCATROOT} = File::Spec->catdir($repo_root, 'xCAT-server');
my $plugin = File::Spec->catfile(
    $repo_root, qw(xCAT-server lib xcat plugins ipmi.pm)
);
do $plugin or die $@ || "Unable to load $plugin: $!";

sub new_sessdata {
    my ($pending) = @_;
    return {
        biosbuildid      => 'TCE123A',
        biosbuildpending => $pending,
        biosbuildversion => '2.13',
        bmcnum           => 1,
        extraargs        => [],
        fru_hash         => {},
        invtypes         => ['firmware'],
        isite            => 0,
        node             => 'node01',
    };
}

sub run_got_bios_date {
    my ($sessdata) = @_;
    my @calls;
    local *xCAT_plugin::ipmi::get_imm_property = sub {
        push @calls, { @_ };
    };
    xCAT_plugin::ipmi::got_bios_date(
        data     => '2026-08-30',
        sessdata => $sessdata,
    );
    return \@calls;
}

sub assert_next_property {
    my ($calls, $sessdata, $case) = @_;

    is(scalar(@{$calls}), 1, "$case: one next property request");
    is(
        $calls->[0]->{property},
        '/v2/fpga/build_id',
        "$case: FPGA build ID follows",
    );
    is(
        $calls->[0]->{callback},
        \&xCAT_plugin::ipmi::got_fpga_buildid,
        "$case: correct callback follows",
    );
    is(
        $calls->[0]->{sessdata},
        $sessdata,
        "$case: session data is preserved",
    );
}

subtest 'pending UEFI build ID is a separate inventory record' => sub {
    my $sessdata = new_sessdata('TCE124A');
    my $calls = run_got_bios_date($sessdata);

    is(
        $sessdata->{biosbuilddate},
        '2026-08-30',
        'BIOS build date is recorded',
    );
    is_deeply(
        [sort keys %{ $sessdata->{fru_hash} }],
        [qw(uefi uefi_pending)],
        'active and pending keys are exact',
    );

    my $active = $sessdata->{fru_hash}->{uefi};
    isa_ok($active, 'FRU', 'active inventory record');
    is(
        $active->rec_type,
        'bios,uefi,firmware',
        'active record type is unchanged',
    );
    is($active->desc, 'UEFI Version', 'active record label is unchanged');
    is(
        $active->value,
        '2.13 (TCE123A 2026-08-30)',
        'active value does not associate the pending build with this bank',
    );

    my $pending = $sessdata->{fru_hash}->{uefi_pending};
    isa_ok($pending, 'FRU', 'pending inventory record');
    is(
        $pending ? $pending->rec_type : undef,
        'bios,uefi,firmware',
        'pending record has firmware inventory types',
    );
    is(
        $pending ? $pending->desc : undef,
        'Pending UEFI Build ID',
        'pending record identifies the value as a build ID',
    );
    is(
        $pending ? $pending->value : undef,
        'TCE124A',
        'pending record contains the OEM pending build ID',
    );
    assert_next_property($calls, $sessdata, 'pending');

    local @xCAT::SvrUtils::messages = ();
    {
        local $SIG{__WARN__} = sub {
            my ($warning) = @_;
            return
              if $warning =~
              /\AArgument "uefi(?:_pending)?" isn't numeric in numeric comparison \(<=>\)/;
            die $warning;
        };
        xCAT_plugin::ipmi::fru_initted($sessdata);
    }
    is_deeply(
        \@xCAT::SvrUtils::messages,
        [
            sprintf(
                '%-20s %s',
                'UEFI Version:',
                '2.13 (TCE123A 2026-08-30)',
            ),
            sprintf('%-20s %s', 'Pending UEFI Build ID:', 'TCE124A'),
        ],
        'active UEFI output precedes pending UEFI output',
    );
};

subtest 'no pending UEFI build leaves inventory unchanged' => sub {
    my $sessdata = new_sessdata(0);
    my $calls = run_got_bios_date($sessdata);

    is_deeply(
        [sort keys %{ $sessdata->{fru_hash} }],
        ['uefi'],
        'only the active key is present',
    );
    my $active = $sessdata->{fru_hash}->{uefi};
    is(
        $active->rec_type,
        'bios,uefi,firmware',
        'active record type remains unchanged',
    );
    is($active->desc, 'UEFI Version', 'active record label remains unchanged');
    is(
        $active->value,
        '2.13 (TCE123A 2026-08-30)',
        'active record value remains unchanged',
    );
    ok(
        !exists $sessdata->{fru_hash}->{uefi_pending},
        'pending record is omitted',
    );
    assert_next_property($calls, $sessdata, 'no pending');
};

done_testing();
