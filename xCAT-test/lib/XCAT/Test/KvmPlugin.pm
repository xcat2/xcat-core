package XCAT::Test::KvmPlugin;

use strict;
use warnings;

use Exporter qw(import);
use lib ();

use XCAT::Test::File qw(repo_path);

our @EXPORT_OK = qw(load_kvm_plugin);

#-------------------------------------------------------------------------------

=head3 load_kvm_plugin

    Descriptions:
        Loads xCAT-server/lib/xcat/plugins/kvm.pm from the checkout into the
        package xCAT_plugin::kvm, so that a test calls its routines in-process.
    Arguments:
        None.
    Returns:
        The paths in %INC that are under /opt/xcat. An empty list means that
        kvm.pm and every xCAT module it uses came from the checkout.

=cut

#-------------------------------------------------------------------------------
sub load_kvm_plugin {
    my $plugin = repo_path('xCAT-server/lib/xcat/plugins/kvm.pm');
    return _installed_modules() if $INC{$plugin};

    # kvm.pm loads Sys::Virt and the monitoring plugin when it compiles. The routines
    # under test use neither, and a test host has neither.
    $Sys::Virt::VERSION = '10.0.0';
    $INC{'Sys/Virt.pm'} = __FILE__;
    $INC{'xCAT_monitoring/monitorctrl.pm'} = __FILE__;

    # xCAT modules put $XCATROOT/lib/perl first in @INC. Point it at the checkout, or a
    # host with xCAT installed tests the installed modules.
    $ENV{XCATROOT} = repo_path('xCAT-server');
    lib->import(repo_path('perl-xCAT'), repo_path('xCAT-server/lib/perl'));

    require $plugin;

    return _installed_modules();
}

sub _installed_modules {
    return sort grep { defined and m{^/opt/xcat/} } values %INC;
}

1;

__END__

=head1 NAME

XCAT::Test::KvmPlugin - load the kvm plugin from the checkout for a unit test

=head1 SYNOPSIS

    use XCAT::Test::KvmPlugin qw(load_kvm_plugin);
    my @installed = load_kvm_plugin();
    is_deeply(\@installed, [], 'kvm.pm loads from the checkout');

=cut
