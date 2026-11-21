package XCAT::Test::IPMISDR;

use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)
no warnings qw(once redefine);
use Exporter qw(import);
use XCAT::Test::File qw(repo_path);

our @EXPORT_OK = qw(load_ipmi_plugin new_session);

# Install guards before the plugin compiles its filesystem operations.
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
    sub sendmsg { push @messages, { text => $_[0], node => $_[2] }; }
    $INC{'xCAT/SvrUtils.pm'} = __FILE__;

    package xCAT::SPD;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::decode_spd"} = sub { return; };
    }
    $INC{'xCAT/SPD.pm'} = __FILE__;

    # Load File::Temp before this fixture; the plugin needs a compile-time File::Path stub.
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

    package XCAT::Test::IPMISDR;
    *CORE::GLOBAL::chmod = sub (@) { return 1; };
}

sub load_ipmi_plugin {
    $ENV{XCATROOT} = repo_path('xCAT-server');
    my $plugin = repo_path('xCAT-server/lib/xcat/plugins/ipmi.pm');
    do $plugin or die $@ || "Unable to load $plugin: $!";
    return;
}

sub new_session {
    return bless { calls => [] }, 'XCAT::Test::IPMISDR::Session';
}

package XCAT::Test::IPMISDR::Session;

sub subcmd {
    my ($self, %args) = @_;
    push @{ $self->{calls} }, \%args;
    return;
}

1;
