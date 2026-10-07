#!/usr/bin/env perl
# The Genesis kernel is the one file mknb stages into the TFTP root from the xCAT install tree,
# so it is the one file that can arrive with the install tree's SELinux context.
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

my $TFTPDIR = '/tftpboot';
my $KERNEL  = "$TFTPDIR/xcat/genesis.kernel.x86_64";

# cp carries the SELinux context when the preserve set holds context or xattr, because the
# context is stored in the security.selinux xattr. -a sets both, and the last --preserve or
# --no-preserve for an item wins. Model that, so the assertion is about what cp does and not
# about which spelling mknb chose.
sub preserves_context {
    my ($command) = @_;
    my %keeps = (context => 0, xattr => 0);
    foreach my $word (split(/\s+/, $command)) {
        if ($word =~ m{\A--(no-)?preserve=(.*)\z}) {
            my $value = $1 ? 0 : 1;
            foreach my $item (split(/,/, $2)) {
                @keeps{ keys %keeps } = ($value) x keys(%keeps) if $item eq 'all';
                $keeps{$item} = $value if exists($keeps{$item});
            }
        } elsif ($word =~ m{\A-[a-zA-Z]+\z} && $word =~ m{a}) {
            @keeps{ keys %keeps } = (1) x keys(%keeps);
        }
    }
    return ($keeps{context} || $keeps{xattr}) ? 1 : 0;
}

# Drive the legacy path with a runner that records every command and can fail one of them.
sub stage {
    my (%opt) = @_;
    my @ran;
    no warnings qw(redefine once);
    local *xCAT::Utils::isSELINUX = sub { return $opt{selinux} ? 0 : 1 };
    my ($rc, $src) = xCAT_plugin::mknb::stage_genesis_payload(
        genesis_type => 'legacy',
        genesis_dir  => '/opt/xcat/share/xcat/netboot/genesis/x86_64',
        tftpdir      => $TFTPDIR,
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

# --- the copy must not carry the install tree's context into the TFTP root ---------
is(preserves_context('cp -a src dst'), 1,
    'the model reads cp -a as context-preserving');
is(preserves_context('cp -a --no-preserve=context src dst'), 1,
    'and reads cp -a --no-preserve=context the same way, because the xattr still carries it');
is(preserves_context('cp -a --no-preserve=context,xattr src dst'), 0,
    'and reads a copy that drops both items as not context-preserving');
is(preserves_context('cp -p src dst'), 0,
    'and reads cp -p as not context-preserving');

my $on = stage(selinux => 1);
my ($copy) = grep { m{\Qcp \E} && m{\Q$KERNEL\E} } @{ $on->{ran} };
ok($copy, 'the legacy path copies the Genesis kernel into the TFTP root')
    or diag(join("\n", @{ $on->{ran} }));
is(preserves_context($copy // ''), 0,
    'and the copy does not preserve the SELinux context of the install tree');

# --- the staged kernel is relabelled, so an upgraded node is corrected too ---------
my @relabel = grep { m{restorecon} } @{ $on->{ran} };
is(scalar @relabel, 1, 'one relabel runs when SELinux is enabled');
like($relabel[0] // '', qr{\Q$KERNEL\E},
    'and the relabel names the staged Genesis kernel');
my ($copy_index)    = grep { $on->{ran}->[$_] eq ($copy // '') } 0 .. $#{ $on->{ran} };
my ($relabel_index) = grep { $on->{ran}->[$_] =~ m{restorecon} } 0 .. $#{ $on->{ran} };
ok(defined($copy_index) && defined($relabel_index) && $relabel_index > $copy_index,
    'and it runs after the copy, not before it');

my $off = stage(selinux => 0);
is(scalar(grep { m{restorecon} } @{ $off->{ran} }), 0,
    'a node without SELinux runs no relabel');

# --- a relabel that fails must not fail the step ----------------------------------
my $norelabel = stage(selinux => 1, fail => qr{restorecon});
is($norelabel->{rc}, 0, 'a failed relabel leaves the staged payload in place');
is($norelabel->{src}, undef, 'and names no unreadable source');

# --- the existing failures still name the copy that failed ------------------------
my $nokernel = stage(selinux => 1, fail => qr{/kernel\s});
isnt($nokernel->{rc}, 0, 'an unreadable kernel still fails the step');
is(scalar(grep { m{restorecon} } @{ $nokernel->{ran} }), 0,
    'and a kernel that was not copied is not relabelled');

done_testing();
