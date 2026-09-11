#!/usr/bin/env perl
# mknb stages the Genesis payload before it can build a netboot image. Those copies are the
# only point at which mknb learns that an installed Genesis image is unusable, so a copy that
# fails silently produces an initramfs built from nothing and an exit status of 0 -- the node
# then never boots, with no error anywhere naming the cause.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

BEGIN { $INC{'xCAT/Utils.pm'} = 1; $INC{'xCAT/MsgUtils.pm'} = 1;
        $INC{'xCAT/Table.pm'} = 1; $INC{'xCAT/NetworkUtils.pm'} = 1;
        $INC{'xCAT/TableUtils.pm'} = 1; $INC{'xCAT_monitoring/monitorctrl.pm'} = 1; }

require "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/mknb.pm";

can_ok('xCAT_plugin::mknb', 'stage_genesis_payload')
    or BAIL_OUT('mknb has no stage_genesis_payload to drive');

# Drive the routine with a runner that fails exactly one copy, so each assertion names the
# copy it is about rather than the pair.
sub stage {
    my (%opt) = @_;
    my @ran;
    my ($rc, $src) = xCAT_plugin::mknb::stage_genesis_payload(
        genesis_type => $opt{type} // 'legacy',
        genesis_dir  => '/opt/xcat/share/xcat/netboot/genesis/x86_64',
        tftpdir      => '/tftpboot',
        arch         => 'x86_64',
        tempdir      => '/tmp/scratch',
        run          => sub {
            my ($cmd) = @_;
            push @ran, $cmd;
            return ($opt{fail} && $cmd =~ /$opt{fail}/) ? 256 : 0;
        },
    );
    return { rc => $rc, src => $src, ran => \@ran };
}

# --- legacy: both copies must be able to fail the step -----------------------
my $ok = stage();
is($ok->{rc}, 0, 'a legacy image whose copies both succeed stages cleanly');
is(scalar @{ $ok->{ran} }, 2, 'the legacy path copies the root tree and the kernel');

my $nofs = stage(fail => qr{/fs/\*});
isnt($nofs->{rc}, 0, 'an unreadable root tree fails the step');
like($nofs->{src}, qr{/fs$}, 'and the failure names the root tree');

my $nokernel = stage(fail => qr{/kernel });
isnt($nokernel->{rc}, 0, 'a missing kernel fails the step');
like($nokernel->{src}, qr{/kernel$}, 'and the failure names the kernel, not the root tree');

# --- exported (OpenEmbedded) path -------------------------------------------
my $nonb = stage(type => 'exported', fail => qr{/nbroot/\*});
isnt($nonb->{rc}, 0, 'an unreadable nbroot fails the step');
like($nonb->{src}, qr{/nbroot$}, 'and the failure names nbroot');

my $oknb = stage(type => 'exported');
is($oknb->{rc}, 0, 'an exported image whose copy succeeds stages cleanly');

done_testing();
