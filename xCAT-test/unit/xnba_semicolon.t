#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Slurper qw(read_text write_binary write_text);
use File::Temp qw(tempdir);
use Storable qw(dclone);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $root = tempdir(CLEANUP => 1);
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "$root/config";
make_path($ENV{XCATCFG}, "$root/tftp/xcat");
require xCAT::TableUtils;
{
    no warnings qw(redefine once);
    local *xCAT::TableUtils::getTftpDir = sub { return "$root/tftp"; };
    require(repo_path('xCAT-server/lib/xcat/plugins/xnba.pm'));
}

my %rows;
my $port;
sub nodeset {
    my ($node, $state, $kernel) = @_;
    %rows = (
        noderes => { tftpdir => "$root/tftp" },
        chain => { currstate => $state },
        nodetype => { provmethod => 'install' },
        iscsi => {}, linuximage => {},
    );
    my (@responses, @commands);
    no warnings qw(redefine once);
    local @ARGV;
    local *xCAT::Table::new = sub {
        my ($class, $table) = @_;
        die "Unexpected table $table" unless exists $rows{$table};
        return bless { table => $table }, 'Local::BootTable';
    };
    local *xCAT::TableUtils::get_site_attribute = sub {
        return ('n') if $_[1] eq 'dhcpsetup';
        return defined($port) ? ($port) : () if $_[1] eq 'httpport';
        die "Unexpected site attribute $_[1]";
    };
    local *xCAT::NetworkUtils::determinehostname = sub { return ('mn.example'); };
    local *xCAT::NetworkUtils::checkNodeIPaddress = sub { return { ip => '192.0.2.10' }; };
    local *xCAT::MsgUtils::trace = sub { return; };
    xCAT_plugin::xnba::process_request(
        { command => ['nodeset'], node => [$node], arg => [$state] },
        sub { push @responses, dclone($_[0]); },
        sub {
            my ($request) = @_;
            my $command = $request->{command}[0];
            push @commands, $command;
            if ($command eq 'setdestiny') {
                $request->{bootparams}{$node} = [dclone($kernel)];
            } elsif ($command ne 'runbeginpre' && $command ne 'runendpre'
                && !($command eq 'makedhcp' && $state eq 'offline')) {
                die "Unexpected command $command";
            }
        },
    );
    my @expected = qw(runbeginpre setdestiny);
    push @expected, 'makedhcp' if $state eq 'offline';
    push @expected, 'runendpre';
    is_deeply(\@commands, \@expected, 'runs the complete nodeset path');
    my @errors = grep { $_->{error} || $_->{errorcode} || $_->{node} } @responses;
    is_deeply(\@errors, [], 'no request errors');
    return [map { @{ $_->{warning} || [] } } @responses];
}

sub script {
    return read_text("$root/tftp/xcat/xnba/nodes/$_[0]");
}

my $cmdline = 'ds=nocloud-net;s=http://192.0.2.1/seed/ quiet';
for my $case (
    ['modern', 'xcat/ubuntu24.04/vmlinuz', 'xcat/initrd', $cmdline, 1],
    ['sles-kernel', 'xcat/sles11.4/vmlinuz', 'xcat/initrd', $cmdline, 0],
    ['sle-initrd', 'xcat/second/vmlinuz', 'xcat/sle11/initrd', $cmdline, 0],
    ['sles-cmdline', 'xcat/third/vmlinuz', 'xcat/initrd', "$cmdline image=sles11", 0],
    ['sles12', 'xcat/sles12/vmlinuz', 'xcat/initrd', $cmdline, 1],
    ['sles110', 'xcat/sles110/vmlinuz', 'xcat/initrd', $cmdline, 1],
    ['not-sles', 'xcat/notsles11/vmlinuz', 'xcat/initrd', $cmdline, 1],
) {
    my ($node, $kernel, $initrd, $args, $efi) = @$case;
    subtest $node => sub {
        (my $directory = "$root/tftp/$kernel") =~ s{/[^/]+$}{};
        make_path($directory);
        write_binary("$root/tftp/$kernel", "\0" x 64 . pack('H*', '504500006486') . "\0" x 440);
        is_deeply(nodeset($node, 'install', {kernel => $kernel, initrd => $initrd, kcmdline => $args}),
            [], 'direct kernels do not require pxelinux');
        like(script($node), qr/^imgargs kernel \Q$args\E BOOTIF=01-\$\{netX\/mac:hexhyp\}$/m,
            'BIOS keeps the complete command line including semicolon');
        if ($efi) {
            like(script("$node.uefi"), qr/^imgargs kernel \Q$args\E BOOTIF=01-\$\{netX\/mac:hexhyp\} initrd=initrd$/m,
                'UEFI keeps the complete command line including semicolon');
        } else {
            is(script("$node.uefi"), "#!gpxe\nchain http://\${next-server}/tftpboot/xcat/elilo-x64.efi -C /tftpboot/xcat/xnba/nodes/$node.elilo\n",
                'SLES 11 uses elilo despite advertising EFI stub support');
            like(script("$node.elilo"), qr/append="\Q$args\E BOOTIF=%B"/,
                'elilo retains the command line');
        }
        nodeset($node, 'boot', {});
        is(script("$node.uefi"), "#!gpxe\n#boot\nexit\n", 'local boot replaces stale UEFI install content');
        nodeset($node, 'offline', {});
        ok(!-e "$root/tftp/xcat/xnba/nodes/$node", 'offline removes BIOS script');
        ok(!-e "$root/tftp/xcat/xnba/nodes/$node.uefi", 'offline removes UEFI script');
    };
}

for my $kernel ('xcat/memdisk', 'xcat/mboot.c32', 'kernel!hypervisor') {
    subtest "pxelinux $kernel" => sub {
        my $warnings = nodeset('chain', 'install', {kernel => $kernel, initrd => 'initrd', kcmdline => 'quiet'});
        is(scalar(@$warnings), 1, 'missing pxelinux produces one warning');
        like($warnings->[0], qr/Unable to find pxelinux\.0/, 'warning names the missing loader');
        like(script('chain'), qr/imgexec pxelinux\.0/, 'generated configuration actually chains pxelinux');
    };
}

write_text("$root/tftp/xcat/pxelinux.0", 'loader');
is_deeply(nodeset('present', 'install', {kernel => 'xcat/memdisk', initrd => 'initrd', kcmdline => 'quiet'}),
    [], 'an installed pxelinux needs no warning');

done_testing();

package Local::BootTable;
sub getNodesAttribs {
    my ($self, $nodes) = @_;
    return {map { $_ => [ { %{ $rows{$self->{table}} } } ] } @$nodes};
}
sub close { return; }
