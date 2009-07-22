# IBM(c) 2009 EPL license http://www.eclipse.org/legal/epl-v10.html

#This plugin handles 'setupiscsidev' operation for ONTAP platform devices, 
#such as the IBM N-series storage subsystems.
#It requires that the storage enclosure have root's public key as an 
#authorized key for passwordless 
package xCAT_plugin::ontap;
#In ONTAP world, the entire controller is a particular target iqn, that shows
#different lun numbers depending on client iqn.
#iscsi.target, iscsi.server, and iscsi.lun may therefore look identital
#for multiple nodes, but mean entirely different things
#This plugin will populate the lun and targetname
use strict;
BEGIN
{
      $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

use lib "$::XCATROOT/lib/perl";
use warnings "all";
use xCAT::Table;

sub handled_commands {
    return {
         testontap => 'ontap',
#        setupiscsidev => iscsi:method
#Mayhaps need an iscsiserver table?  iscsi table column has a pretty weak 
#association, but on the other hand, iscsi servers aren't necessarily a node
#So two options:
#  Add field to iscsi table to declare the mechanism to setup device:
#       Pros:
#           -No extra 'nodes' required to be defined            
#       Cons:
#           -Could be awkward if the enviornment has hybrid iscsi storage providers
#   Add new table
#       Pros: allows the management method of the target to be abstracted from the node
#       cons: requires that every iscsi entity be defined as a node

    }
}
my %iscsicfg;

sub process_request {
    my $request = shift;
    my $callback = shift;
    my $iscsitab = xCAT::Table->new('iscsi');
    my @nodes = @{$request->{node}};
    my $iscsitabdata = $iscsitab->getNodesAttribs(\@nodes,[qw/server iname file/]);
    my $node;
    foreach $node (keys %$iscsitabdata) { #Re-layout the data so we can iterate target-wise rather than node wise
        $iscsicfg{$iscsitabdata->{$node}->[0]->{server}}->{$node}=$iscsitabdata->{$node}->[0];
    }
    my $controller;
    foreach $controller (keys %iscsicfg) { #TODO: we need to forkify this
    #Develop serially first, then put fork semantics in place
        handle_targets($controller,$request);
    }
    use Data::Dumper;
    print Dumper(\%iscsicfg);
};

sub get_controller_iqn {
    my $controller = shift;
    my $output = `ssh $controller iscsi nodename`;
    $output =~ s/^[^:]*://;
    chomp $output;
    $output =~ s/^\s*//;
    return $output;
}

sub get_luns_for_iqn {
    #extract all the backing files presented to the given iqn, with lun id
    my $controller = shift;
    my $iqn = shift;
    my @output = `ssh $controller igroup show `;
    my %returns;
    my $groupname;
    my $tgr;
    foreach (@output) {
        if (/^    ([^ ]+)/) { #This is a new group
            $tgr = $1;
        } elsif (/^        $iqn/) {
            $groupname = $tgr;
        } 
    }
    unless ($groupname) {
        return undef;
    }
    @output = `ssh $controller lun show -m`;
    shift @output; #discard header
    shift @output;
    foreach (@output) {
        unless (/iSCSI/) { next; }
        my $backing;
        my $igr;
        my $lunid;
        ($backing,$igr,$lunid) = split /\s+/,$_,3;
        if ($igr eq $groupname) { 
            $returns{$backing}=$lunid;
        }
    }
    return \%returns;
}

sub handle_targets {
    my $controller = shift;
    my $request = shift;
    my $node;
    print get_controller_iqn($controller);
    foreach $node (keys %{$iscsicfg{$controller}}) {
        configure_node($controller,$node,$request);
    }
    
}

sub configure_node {
    my $controller = shift;
    my $node = shift;
    my $request = shift;
    my $lunsize;
    if ($request->{arg}) {
        @ARGV=@{$request->{arg}};
         GetOptions(
                   "size|s=i" => \$lunsize,
         );
    }
    my $current_view = get_luns_for_iqn($controller,$iscsicfg{$controller}->{$node}->{iname});
    print Dumper($current_view);
}
    
1;


