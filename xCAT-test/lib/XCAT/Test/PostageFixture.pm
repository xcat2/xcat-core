package XCAT::Test::PostageFixture;

use strict;
use warnings;
use FindBin;
use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use Exporter qw(import);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Storable qw(dclone);

our @EXPORT_OK = qw(fixture write_file read_file inventory
    $root $custom $stock $callback $template $expected @responses);

# Keep selection, expansion and reporting real; supply only database records.
BEGIN { $INC{'xCAT/Table.pm'} = __FILE__; }
{
    package xCAT::Table;
    our (%rows, @opened);
    sub new {
        my ($class, $table) = @_;
        die "Unexpected table $table" unless exists($rows{$table});
        push @opened, $table;
        return bless { table => $table }, $class;
    }
    sub project {
        my ($row, @fields) = @_;
        @fields = @{$fields[0]} if @fields == 1 && ref($fields[0]) eq 'ARRAY';
        return {map { $_ => $row->{$_} } @fields};
    }
    sub getAllAttribs {
        my ($self, @fields) = @_;
        return map { project($_, @fields) } @{$rows{$self->{table}}};
    }
    sub getAllNodeAttribs { return getAllAttribs(@_); }
    sub getAttribs {
        my ($self, $key, @fields) = @_;
        for my $row (@{$rows{$self->{table}}}) {
            next if grep { !defined($row->{$_}) || $row->{$_} ne $key->{$_} } keys %$key;
            return project($row, @fields);
        }
        return;
    }
    sub getNodeAttribs {
        my ($self, $node, @fields) = @_;
        return $self->getAttribs({node => $node}, @fields);
    }
    sub getNodesAttribs {
        my ($self, $nodes, @fields) = @_;
        return {map { $_ => [$self->getNodeAttribs($_, @fields)] } @$nodes};
    }
    sub getAllAttribsWhere {
        my ($self) = @_;
        die 'Only the empty management-node query is provided' unless $self->{table} eq 'nodelist';
        return;
    }
    sub setAttribs { die 'Unexpected table write'; }
    sub close { return; }
}
{
    package xCAT_monitoring::monitorctrl;
    sub getNodeConfData { return {}; }
}

my $temporary = tempdir(CLEANUP => 1);
symlink("$FindBin::Bin/../../xCAT-server/lib/xcat/plugins", "$temporary/xCAT_plugin") or croak $!;
unshift @INC, $temporary;
$ENV{XCATCFG} = "$temporary/database";
$ENV{XCATROOT} = "$FindBin::Bin/../..";
make_path($ENV{XCATCFG});
require xCAT::NetworkUtils;
{
    # DNS/interface discovery is outside the rendering contract.
    no warnings qw(redefine once);
    *xCAT::NetworkUtils::getipaddr = sub { return $_[1] eq 'node1' ? '192.0.2.10' : '192.0.2.1'; };
    *xCAT::NetworkUtils::gethostnameandip = sub () { return ('master', '192.0.2.1'); };
    *xCAT::NetworkUtils::my_ip_facing = sub { return (0, '192.0.2.1'); };
}

our ($root, $custom, $stock);
my $sequence = 0;
our @responses;
our $callback = sub { push @responses, dclone($_[0]); };
our $template = <<'TEMPLATE';
#!/bin/sh

ORIGIN='custom'
OSVER=#TABLE:nodetype:$NODE:os#
ARCH=#TABLE:nodetype:$NODE:arch#
PROFILE=#TABLE:nodetype:$NODE:profile#
PROVMETHOD=#TABLE:nodetype:$NODE:provmethod#
MASTER=#MASTER_IP_ADDR#
NODE=$NODE
ENABLESSHBETWEENNODES=$ENABLESSHBETWEENNODES
export ENABLESSHBETWEENNODES

# postscripts-start-here
#INCLUDE_POSTSCRIPTS_LIST#
# postscripts-end-here

# postbootscripts-start-here
#INCLUDE_POSTBOOTSCRIPTS_LIST#
# postbootscripts-end-here

cat <<'PAYLOAD'
private fixture value

  indented payload
PAYLOAD

TEMPLATE
$template =~ s/^  indented payload$/  indented payload\x20\x20/m;

our $expected = <<'EXPECTED';
#!/bin/sh

ORIGIN='custom'
OSVER='freebsd15.1'
ARCH='x86_64'
PROFILE='compute'
PROVMETHOD='image1'
MASTER=192.0.2.1
NODE=node1
ENABLESSHBETWEENNODES='NO'
export ENABLESSHBETWEENNODES

# postscripts-start-here
# defaults-postscripts-start-here
first 'two words'
same value
# defaults-postscripts-end-here
# osimage-postscripts-start-here
image "quoted value"
# osimage-postscripts-end-here
# node-postscripts-start-here
same different
last
# node-postscripts-end-here

# postscripts-end-here

# postbootscripts-start-here
# defaults-postbootscripts-start-here
bootfirst
# defaults-postbootscripts-end-here
# osimage-postbootscripts-start-here
bootimage
# osimage-postbootscripts-end-here
# node-postbootscripts-start-here
bootlast
# node-postbootscripts-end-here

# postbootscripts-end-here

cat <<'PAYLOAD'
private fixture value

  indented payload
PAYLOAD

EXPECTED
$expected =~ s/^  indented payload$/  indented payload\x20\x20/m;

sub write_file {
    my ($path, $contents) = @_;
    open(my $file, '>:raw', $path) or croak "$path: $!";
    print {$file} $contents or croak "$path: $!";
    close($file) or croak "$path: $!";
    return;
}

sub read_file {
    my ($path) = @_;
    open(my $file, '<:raw', $path) or croak "$path: $!";
    my $contents = do { local $/; <$file> };
    close($file) or croak "$path: $!";
    return defined($contents) ? $contents : '';
}

sub inventory {
    my %files;
    find({no_chdir => 1, wanted => sub {
        my $path = $File::Find::name;
        my @state = lstat($path);
        croak 'Unexpected fixture symlink' if -l _;
        $files{$path} = [@state[0, 1, 2, 3, 4, 5, 7], -f _ ? sha256_hex(read_file($path)) : 'directory'];
    }}, $root);
    return \%files;
}

sub fixture {
    my ($use_custom) = @_;
    $root = "$temporary/case-" . ++$sequence;
    make_path("$root/install/postscripts", "$root/tftp/xcat/xnba/nodes", "$root/stock/share/xcat/mypostscript");
    write_file("$root/tftp/xcat/xnba/nodes/node1", "#!gpxe\n#install\n");
    $custom = "$root/install/postscripts/mypostscript.tmpl";
    $stock = "$root/stock/share/xcat/mypostscript/mypostscript.tmpl";
    my $stock_template = $template;
    $stock_template =~ s/ORIGIN='custom'/ORIGIN='stock'/;
    write_file($stock, $stock_template);
    write_file($custom, $template) if $use_custom;
    {
        no warnings 'once';
        $ENV{XCATROOT} = "$root/stock";
        $::XCATROOT = "$root/stock";
        %::XCATSITEVALS = (installdir => "$root/install", tftpdir => "$root/tftp",
            master => 'master', sshbetweennodes => 'NOGROUPS');
        %::GLOBAL_TAB_HASH = ();
        %::GLOBAL_SN_HASH = ();
        %::GLOBAL_TABDUMP_HASH = ();
        @::exclude_nodes = ();
    }
    %xCAT::Table::rows = (map { $_ => [] } qw(site networks routes linuximage servicenode cfgmgt zone kit kitcomponent));
    $xCAT::Table::rows{nodelist} = [{node => 'node1', groups => 'compute'}];
    $xCAT::Table::rows{noderes} = [{node => 'node1', netboot => 'xnba', xcatmaster => 'master', tftpdir => "$root/tftp"}];
    $xCAT::Table::rows{nodetype} = [{node => 'node1', os => 'freebsd15.1', arch => 'x86_64',
        profile => 'compute', provmethod => 'image1'}];
    $xCAT::Table::rows{osimage} = [{imagename => 'image1', provmethod => 'install',
        osvers => 'freebsd15.1', osarch => 'x86_64', profile => 'compute', synclists => '/fixture/synclist',
        postscripts => 'same value,image "quoted value"', postbootscripts => 'bootfirst,bootimage'}];
    $xCAT::Table::rows{postscripts} = [
        {node => 'xcatdefaults', postscripts => "first 'two words',same value", postbootscripts => 'bootfirst'},
        {node => 'node1', postscripts => 'same value,same different,last', postbootscripts => 'bootlast,bootimage'},
    ];
    @xCAT::Table::opened = ();
    @responses = ();
    return \%xCAT::Table::rows;
}

1;
