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
my $tftp = "$root/tftp";
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "$root/config";
make_path($ENV{XCATCFG}, $tftp);
write_text("$tftp/pxelinux.0", 'loader');
require xCAT::TableUtils;
{
    no warnings qw(redefine once);
    local *xCAT::TableUtils::getTftpDir = sub { return $tftp; };
    for my $plugin (qw(pxe xnba ipxe boottarget)) {
        require(repo_path("xCAT-server/lib/xcat/plugins/$plugin.pm"));
    }
}

my (%rows, %written, %kernels);
my @responses;
sub render {
    my ($method, $input, %options) = @_;
    my @nodes = @{ $options{nodes} || ['192.0.2.10'] };
    my $node = $nodes[0];
    %written = ();
    @responses = ();
    %kernels = ($node => {
        kernel => $options{kernel} || 'vmlinuz', initrd => 'initrd', kcmdline => 'quiet',
        addkcmdline => $input,
    });
    %rows = (
        noderes => {$node => {tftpdir => $tftp}},
        chain => {$node => {currstate => 'install'}},
        nodetype => {$node => {os => 'boottarget', profile => 'custom',
            provmethod => $options{image} ? 'image' : 'install'}},
        mac => {}, iscsi => {}, bootparams => {}, nodehm => {},
        boottarget => {custom => {kernel => 'vmlinuz', initrd => 'initrd', kcmdline => $input}},
        linuximage => {image => {addkcmdline => $options{image}, boottarget => $options{boottarget}}},
        hosts => {$node => {
            ip => $node, empty => '', zero => '0',
            nested => '#NODEATTRIB:hosts:ip#',
            table => '#TABLE:hosts:THISNODE:ip#',
            special => 'a$1\\b&c',
            selfref => '#NODEATTRIB:hosts:selfref#',
            tableself => '#TABLE:hosts:THISNODE:tableself#',
            cycle_a => '#NODEATTRIB:hosts:cycle_b#',
            cycle_b => '#NODEATTRIB:hosts:cycle_a#',
            table_a => '#TABLE:hosts:THISNODE:table_b#',
            table_b => '#TABLE:hosts:THISNODE:table_a#',
            growing => 'x#NODEATTRIB:hosts:growing#',
            tablegrow => 'x#TABLE:hosts:THISNODE:tablegrow#',
            (map { ("depth$_" => $_ == 16 ? $node : '#NODEATTRIB:hosts:depth' . ($_ + 1) . '#') } 0 .. 16),
            (map { ("tabledepth$_" => $_ == 16 ? $node : '#TABLE:hosts:THISNODE:tabledepth' . ($_ + 1) . '#') } 0 .. 16),
        }},
    );
    for my $other (@nodes) {
        next if $other eq $node;
        $kernels{$other} = dclone($kernels{$node});
        for my $table (qw(noderes chain nodetype hosts)) {
            $rows{$table}{$other} = dclone($rows{$table}{$node});
        }
        $rows{hosts}{$other}{ip} = $other;
    }
    if ($options{bad_node}) {
        my $bad = $options{bad_node};
        $kernels{$bad}{addkcmdline} = $options{bad_input};
        $rows{nodetype}{$bad}{profile} = 'bad';
        $rows{boottarget}{bad} = {kernel => 'vmlinuz', initrd => 'initrd', kcmdline => $options{bad_input}};
    }
    no warnings qw(redefine once);
    local @ARGV;
    local $::myxcatname = 'mn.example';
    local *xCAT::Table::new = sub {
        my ($class, $table) = @_;
        die "Unexpected table $table" unless exists $rows{$table};
        return bless {table => $table}, 'Local::TemplateTable';
    };
    local *xCAT::TableUtils::getTftpDir = sub { return $tftp; };
    local *xCAT::TableUtils::getInstallDir = sub { return "$root/install"; };
    local *xCAT::TableUtils::get_site_attribute = sub {
        return ('n') if $_[1] eq 'dhcpsetup';
        return () if $_[1] eq 'httpport';
        die "Unexpected site attribute $_[1]";
    };
    local *xCAT::NetworkUtils::determinehostname = sub { return ('mn.example'); };
    local *xCAT::NetworkUtils::checkNodeIPaddress = sub { return {ip => $_[1]}; };
    local *xCAT::MsgUtils::trace = sub { return; };
    my $callback = sub {
        die "too many callback responses\n" if @responses == 5;
        push @responses, dclone($_[0]);
    };
    my $completed = eval {
        local $SIG{ALRM} = sub { die "template expansion timed out\n"; };
        alarm(2);
        "xCAT_plugin::$method"->can('process_request')->(
        {command => [$method eq 'boottarget' ? 'mknetboot' : 'nodeset'],
            node => \@nodes, arg => ['install']},
        $callback,
        sub {
            my ($request, $reply) = @_;
            if ($request->{command}[0] eq 'setdestiny') {
                $request->{bootparams}{$_} = [$kernels{$_}] for @nodes;
                $reply->({node => [{name => [$node], _addkcmdlinehandled => 1}]})
                    if $options{handled};
            } elsif ($request->{command}[0] !~ /\A(?:runbeginpre|runendpre)\z/) {
                die "Unexpected command $request->{command}[0]";
            }
        },
        );
        alarm(0);
        1;
    };
    my $exception = $@;
    alarm(0);
    return $exception if $options{bad_node};
    die $exception unless $completed;
    is_deeply(\@responses, [], "$method reports no errors");
    return $written{$node}{kcmdline} if $method eq 'boottarget';
    return $kernels{$node}{kcmdline};
}

my @cases = (
    ['undefined', undef, undef, 'quiet'],
    ['empty', '', '', 'quiet'],
    ['zero', '0', '0', 'quiet'],
    ['literal', 'console=ttyS0', 'console=ttyS0', 'quiet console=ttyS0 '],
    ['node attribute', 'ip=#NODEATTRIB:hosts:ip#', 'ip=192.0.2.10', 'quiet ip=192.0.2.10 '],
    ['table key', 'ip=#TABLE:hosts:THISNODE:ip#', 'ip=192.0.2.10', 'quiet ip=192.0.2.10 '],
    ['dollar key', 'ip=#TABLE:hosts:$NODE:ip#', 'ip=192.0.2.10', 'quiet ip=192.0.2.10 '],
    ['node selector', '#TABLE:hosts:node=$NODE:ip#', '192.0.2.10', 'quiet 192.0.2.10 '],
    ['mixed order', '#TABLE:hosts:THISNODE:ip#,#NODEATTRIB:hosts:zero#,#TABLE:hosts:$NODE:ip#', '192.0.2.10,0,192.0.2.10', 'quiet 192.0.2.10,0,192.0.2.10 '],
    ['missing', 'a=#NODEATTRIB:hosts:missing# b=#TABLE:hosts:THISNODE:missing#', 'a= b=', 'quiet a= b= '],
    ['empty and zero', 'a=#NODEATTRIB:hosts:empty# b=#NODEATTRIB:hosts:zero#', 'a= b=0', 'quiet a= b=0 '],
    ['repeat', '#NODEATTRIB:hosts:ip#,#NODEATTRIB:hosts:ip#', '192.0.2.10,192.0.2.10', 'quiet 192.0.2.10,192.0.2.10 '],
    ['nested node', '#NODEATTRIB:hosts:nested#', '192.0.2.10', 'quiet 192.0.2.10 '],
    ['node replacement limit', '#NODEATTRIB:hosts:depth1#', '192.0.2.10', 'quiet 192.0.2.10 '],
    ['table replacement limit', '#TABLE:hosts:THISNODE:tabledepth1#', '192.0.2.10', 'quiet 192.0.2.10 '],
    ['shared node budget', '#NODEATTRIB:hosts:depth0#,#NODEATTRIB:hosts:ip#',
        '192.0.2.10,192.0.2.10', 'quiet 192.0.2.10,192.0.2.10 '],
    ['shared table budget', '#TABLE:hosts:THISNODE:tabledepth0#,#TABLE:hosts:THISNODE:ip#',
        '192.0.2.10,192.0.2.10', 'quiet 192.0.2.10,192.0.2.10 '],
    ['many independent nodes', join(',', ('#NODEATTRIB:hosts:ip#') x 20),
        join(',', ('192.0.2.10') x 20), 'quiet ' . join(',', ('192.0.2.10') x 20) . ' '],
    ['many independent tables', join(',', ('#TABLE:hosts:THISNODE:ip#') x 20),
        join(',', ('192.0.2.10') x 20), 'quiet ' . join(',', ('192.0.2.10') x 20) . ' '],
    ['node then table', '#NODEATTRIB:hosts:table#', '192.0.2.10', 'quiet 192.0.2.10 '],
    ['table recursion', '#TABLE:hosts:THISNODE:table#', '192.0.2.10', 'quiet 192.0.2.10 '],
    ['table does not restart node pass', '#TABLE:hosts:THISNODE:nested#', '#NODEATTRIB:hosts:ip#', 'quiet #NODEATTRIB:hosts:ip# '],
    ['literal replacement', '#NODEATTRIB:hosts:special#', 'a$1\\b&c', 'quiet a$1\\b&c '],
    ['persistent', 'R::keep=1 marker=#NODEATTRIB:hosts:ip#', 'R::keep=1 marker=192.0.2.10', 'quiet marker=192.0.2.10 '],
    ['persistent only', 'R::keep=1', 'R::keep=1', 'quiet '],
    ['partial token', '#NODEATTRIB:hosts:ip', '#NODEATTRIB:hosts:ip', 'quiet #NODEATTRIB:hosts:ip '],
);

for my $method (qw(pxe xnba ipxe boottarget)) {
    for my $case (@cases) {
        my ($name, $input, $target, $netboot) = @$case;
        subtest "$method $name" => sub {
            my $expected = $method eq 'boottarget' ? $target : $netboot;
            is(render($method, $input), $expected, 'expansion keeps the caller contract');
            if ($method eq 'pxe') {
                is(read_text("$tftp/pxelinux.cfg/192.0.2.10"),
                    "#install\nDEFAULT xCAT\nLABEL xCAT\n KERNEL vmlinuz\n APPEND initrd=initrd $expected\n  IPAPPEND 2\n",
                    'PXE writes the complete expected configuration');
            } elsif ($method ne 'boottarget') {
                like(read_text("$tftp/xcat/$method/nodes/192.0.2.10"),
                    qr/^imgargs kernel \Q$expected\E BOOTIF=01-\$\{netX\/mac:hexhyp\}$/m,
                    'the selected method writes the expanded BIOS arguments');
                like(read_text("$tftp/xcat/$method/nodes/192.0.2.10.elilo"),
                    qr/append="\Q$expected\E BOOTIF=%B"/,
                    'the selected method writes the expanded UEFI fallback arguments');
            } else {
                is_deeply($written{'192.0.2.10'},
                    {kernel => 'vmlinuz', initrd => 'initrd', kcmdline => $expected},
                    'boottarget persists the kernel, initrd and expanded arguments');
            }
        };
    }
    next if $method eq 'boottarget';
    subtest "$method image arguments" => sub {
        is(render($method, 'node=#NODEATTRIB:hosts:ip#', image => 'R::keep=1 image=#TABLE:hosts:$NODE:ip#'),
            'quiet node=192.0.2.10 image=192.0.2.10 ', 'node and image arguments retain their order');
    };
    subtest "$method handled arguments" => sub {
        is(render($method, '#TABLE:hosts:unsupported:ip#', handled => 1),
            'quiet', 'a prior owner can suppress mini-template expansion');
    };
    next if $method eq 'pxe';
    subtest "$method direct UEFI" => sub {
        write_binary("$tftp/modern-kernel", "\0" x 64 . pack('H*', '504500006486') . "\0" x 440);
        is(render($method, 'marker=#NODEATTRIB:hosts:ip#', kernel => 'modern-kernel'), 'quiet marker=192.0.2.10 ',
            'a modern kernel gets the same expansion');
        like(read_text("$tftp/xcat/$method/nodes/192.0.2.10.uefi"),
            qr/^imgargs kernel quiet marker=192\.0\.2\.10  BOOTIF=01-\$\{netX\/mac:hexhyp\} initrd=initrd$/m,
            'direct UEFI boot receives the expanded arguments');
        unlink("$tftp/modern-kernel") or die "unlink kernel: $!";
    };
}

my @failures;
for my $position (0, 1, 2) {
    for my $existing (0, 1) {
        push @failures, [$position, $existing, 'unsupported key',
            'before=#NODEATTRIB:hosts:ip# #TABLE:hosts:unsupported:ip# #TABLE:hosts:other:ip#',
            'Table key of unsupported not yet supported by boottarget mini-template'];
    }
}
for my $case (
    ['node self-reference', '#NODEATTRIB:hosts:selfref#'],
    ['table self-reference', '#TABLE:hosts:THISNODE:tableself#'],
    ['node cycle', '#NODEATTRIB:hosts:cycle_a#'],
    ['table cycle', '#TABLE:hosts:THISNODE:table_a#'],
    ['growing node', '#NODEATTRIB:hosts:growing#'],
    ['growing table', '#TABLE:hosts:THISNODE:tablegrow#'],
    ['node over limit', '#NODEATTRIB:hosts:depth0#', '#NODEATTRIB:hosts:depth16#'],
    ['table over limit', '#TABLE:hosts:THISNODE:tabledepth0#', '#TABLE:hosts:THISNODE:tabledepth16#'],
    ['node budget stays separate', '#NODEATTRIB:hosts:depth0#,#TABLE:hosts:THISNODE:ip#',
        '#NODEATTRIB:hosts:depth16#'],
    ['table budget stays separate', '#NODEATTRIB:hosts:ip#,#TABLE:hosts:THISNODE:tabledepth0#',
        '#TABLE:hosts:THISNODE:tabledepth16#'],
) {
    my ($name, $input, $token) = @$case;
    $token //= $input;
    push @failures, [1, 1, $name, $input,
        "Node template expansion exceeded its replacement limit at $token"];
}

for my $method (qw(pxe xnba ipxe boottarget)) {
    for my $failure (@failures) {
        my ($position, $existing, $name, $input, $message) = @$failure;
        subtest "$method $name at $position existing=$existing" => sub {
            my @nodes = qw(192.0.2.20 192.0.2.21 192.0.2.22);
            my $bad = $nodes[$position];
            for my $good (grep { $_ ne $bad } @nodes) {
                next if $method eq 'boottarget';
                my $file = $method eq 'pxe' ? "$tftp/pxelinux.cfg/$good"
                    : "$tftp/xcat/$method/nodes/$good";
                write_text($file, "previous boot configuration\n");
            }
            my @files = $method eq 'pxe' ? ("$tftp/pxelinux.cfg/$bad")
                : $method eq 'boottarget' ? ()
                : map { "$tftp/xcat/$method/nodes/$bad$_" } ('', '.pxelinux', '.uefi', '.elilo');
            for my $file (@files) {
                if ($existing) {
                    write_text($file, "previous boot configuration\n");
                } else {
                    unlink($file) or die "unlink $file: $!" if -e $file;
                }
            }
            my $link;
            if ($method eq 'pxe') {
                $link = "$tftp/pxelinux.cfg/" . sprintf('%02X%02X%02X%02X', split(/\./, $bad));
                unlink($link) or die "unlink $link: $!" if -e $link || -l $link;
                symlink($bad, $link) or die "symlink $link: $!" if $existing;
            }
            my $exception = render($method, 'marker=#NODEATTRIB:hosts:ip#',
                nodes => \@nodes, bad_node => $bad,
                bad_input => $input);
            is($exception, '', 'request completes before the timeout');
            my @expected = ({node => [{name => [$bad], errorcode => [1], error => [$message]}]});
            push @expected, {errorcode => [1], error =>
                ['Failed to generate xnba configurations for some node(s) on mn.example. Check xCAT log file for more details.']}
                if $method eq 'xnba' || $method eq 'ipxe';
            is_deeply(\@responses, \@expected,
                'responses contain the node error and only the caller-required summary');
            for my $file (@files) {
                if ($existing) {
                    ok(-f $file, 'failure keeps the existing artifact') or next;
                    is(read_text($file), "previous boot configuration\n", 'failure preserves the existing artifact');
                } else {
                    ok(!-e $file, 'failure creates no artifact');
                }
            }
            if ($link) {
                if ($existing) {
                    ok(-l $link, 'failure preserves the existing boot symlink');
                    is(readlink($link), $bad, 'failure preserves the boot symlink target');
                } else {
                    ok(!-e $link && !-l $link, 'failure creates no boot symlink');
                }
            }
            if ($method eq 'boottarget') {
                ok(!exists($written{$bad}), 'failure does not update bootparams');
            } else {
                is($kernels{$bad}{kcmdline}, 'quiet', 'failure does not append a partial expansion');
            }
            for my $good (grep { $_ ne $bad } @nodes) {
                if ($method eq 'boottarget') {
                    is($written{$good}{kcmdline}, "marker=$good", 'other nodes still update bootparams');
                } else {
                    my $file = $method eq 'pxe' ? "$tftp/pxelinux.cfg/$good"
                        : "$tftp/xcat/$method/nodes/$good";
                    like(read_text($file), qr/marker=\Q$good\E /, 'other nodes still get boot artifacts');
                }
            }
        };
    }
}

done_testing();

package Local::TemplateTable;
sub getNodesAttribs {
    my ($self, $nodes) = @_;
    return {map { $_ => [$rows{$self->{table}}{$_} || {}] } @$nodes};
}
sub getNodeAttribs {
    my ($self, $node) = @_;
    return $rows{$self->{table}}{$node} || {};
}
sub getAttribs {
    my ($self, $key) = @_;
    my ($value) = values %$key;
    return $rows{$self->{table}}{$value};
}
sub setNodeAttribs {
    my ($self, $node, $attributes) = @_;
    die "Unexpected write to $self->{table}" unless $self->{table} eq 'bootparams';
    $written{$node} = Storable::dclone($attributes);
    return;
}
sub close { return; }
