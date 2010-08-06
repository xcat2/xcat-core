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
use xCAT::SvrUtils;
my $output_handler;
my $newiqns;
my $domain;
my $iscsitab;
my $nodetypeinfo;

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
    $output_handler = shift;
    $iscsitab = xCAT::Table->new('iscsi');
    unless ($iscsitab) {
        xCAT::SvrUtils::sendmsg([1,"iSCSI configuration lacking from the iscsi table"], $output_handler);
        return;
    }
    my @nodes = @{$request->{node}};
    my $sitetab = xCAT::Table->new('site');
    (my $dent) = $sitetab->getAttribs({key=>'domain'},'value');
    if ($dent and $dent->{value}) {
        $domain = $dent->{value};
        $domain = join(".",reverse(split(/\./,$domain)));
    } else {
        xCAT::SvrUtils::sendmsg([1,"Cannot determine domain name for iqn generation from site table"], $output_handler);
        return;
    }
    my $nodetype =xCAT::Table->new('nodetype',-create=>0);
    unless ($nodetype) {
        xCAT::SvrUtils::sendmsg([1,"ONTAP plugin requires nodetype table to be populated"], $output_handler);
        return;
    }
    $nodetypeinfo = $nodetype->getNodesAttribs(\@nodes,['os']);
    my $iscsitabdata = $iscsitab->getNodesAttribs(\@nodes,[qw/server lun iname file/]);
    my $node;
    foreach $node (keys %$iscsitabdata) { #Re-layout the data so we can iterate target-wise rather than node wise
        $iscsicfg{$iscsitabdata->{$node}->[0]->{server}}->{$node}=$iscsitabdata->{$node}->[0];
    }
    my $controller;
    foreach $controller (keys %iscsicfg) { #TODO: we need to forkify this
    #Develop serially first, then put fork semantics in place
        handle_targets($controller,$request);
    }
    #use Data::Dumper;
};

sub get_controller_iqn {
    my $controller = shift;
    my $output = `ssh $controller iscsi nodename`;
    $output =~ s/^[^:]*://;
    chomp $output;
    $output =~ s/^\s*//;
    return $output;
}

sub build_lunmap {
    my $controller = shift;
    my @nodes = @_;
    my $lunmap;
    my @groupoutput = `ssh $controller igroup show `;
    my @mapoutput = `ssh $controller lun show -m`;
    shift @mapoutput; #Get rid of header
    shift @mapoutput;
    my $groupname;
    my $tgr;
    my $node;
    my $iqn;
    my @time = localtime;
    my $year = 1900+$time[5];
    my $month = $time[4]+1;
    my %returns;
    foreach $node (@nodes) {
        $tgr = undef;
        $iqn = $iscsicfg{$controller}->{$node}->{iname};
        unless ($iqn) { #We must control client iqn, ONTAP acls require it
            $newiqns->{$node} = sprintf("iqn.%d-%02d.%s:%s-initiator",$year,$month,$domain,$node);
            $iqn = $newiqns->{$node};
            $iscsicfg{$controller}->{$node}->{iname} = $iqn;
        }
        foreach (@groupoutput) {
            if (/^    ([^ ]+)/) { #This is a new group
                $tgr = $1;
            } elsif (/^        $iqn/) {
                $groupname = $tgr;
            } 
        }
        unless ($groupname) {
            next;
        }
        foreach (@mapoutput) {
            unless (/iSCSI/) { next; }
            my $backing;
            my $igr;
            my $lunid;
            my $method;
            ($backing,$igr,$lunid,$method) = split /\s+/,$_,4;
            if ($igr eq $groupname) { 
                $returns{$node}->{$backing}=$lunid;
            }
        }
    }
    foreach $node (keys %$newiqns) { #setNodesAttribs won't work since the values are unique per node
        $iscsitab->setNodeAttribs($node,{iname=>$newiqns->{$node}});
    }
    return \%returns;
}

    
sub handle_targets {
    my $controller = shift;
    my $request = shift;
    my $node;
    my $target = get_controller_iqn($controller);
    my @nodes = keys %{$iscsicfg{$controller}};
    my @upnodes;
    foreach $node (@nodes) { #though traversing this is marginally more expensive than just setting, 
                             #do this to allow group level definitions to look sane when manually done
        if ($iscsicfg{$controller}->{$node}->{target} ne $target)  {
            push @upnodes,$node;
        }
    }
    $iscsitab->setNodesAttribs(\@upnodes,{target=>$target});
    my $lunmap = build_lunmap($controller,keys %{$iscsicfg{$controller}});
    foreach $node (@nodes) {
        configure_node($controller,$node,$lunmap,$request);
    }
    
}

sub getUnits {
    my $amount = shift;
    my $defunit = shift;
    my $divisor=shift;
    unless ($divisor) {
        $divisor = 1;
    }
    if ($amount =~ /(\D)$/) { #If unitless, add unit
        $defunit=$1;
        chop $amount;
    }
    if ($defunit =~ /k/i) {
        return $amount*1024/$divisor;
    } elsif ($defunit =~ /m/i) {
        return $amount*1048576/$divisor;
    } elsif ($defunit =~ /g/i) {
        return $amount*1073741824/$divisor;
    }
}


sub create_new_lun {
    #print Dumper(@_);
    my $controller = shift;
    my $gname = shift;
    my $cfg = shift;
    my %args = @_;
    my $lunsize;
    my $mspec;
    if ($args{mspec}) {
        $mspec = $args{mspec}
    } elsif ($args{lsize}) {
        $lunsize = $args{lsize};
    }
    
    my %osmap = (
        'rh.*' => 'linux',
        'centos.*' => 'linux',
        'sles.*' => 'linux',
        'win2k8' => 'windows_2008',
        'win2k3' => 'windows',
        imagex => 'windows'
    );
    unless ($nodetypeinfo->{$gname}->[0]->{os}) {
        xCAT::SvrUtils::sendmsg([1,"nodetype.os must be set for ONTAP plugin to create a lun"], $output_handler);
    }
    my $ltype;
    my $ost=$nodetypeinfo->{$gname}->[0]->{os};
    foreach (keys %osmap) {
        if ($ost =~ /$_/) {
            $ltype = $osmap{$_};
            last;
        }
    }
    my $gtype = $ltype;
    $gtype =~ s/_2008//; #The group types don't include a 2k8 specific type

    my $file = $cfg->{file};
    my $iname = $cfg->{iname};


    my $output;
    unless (($lunsize or $mspec) and $ltype and $file and $gtype) { #TODO etc
        xCAT::SvrUtils::sendmsg([1,"Insufficient data"], $output_handler);
    }
    if ($lunsize) {
        my $size = getUnits($lunsize,'g',1048576);
        $size .= "m";
         $output = `ssh $controller lun create -s $size -t $ltype $file`;
    } elsif ($mspec) {
        my $mlun;
        my $msnap;
        ($mlun,$msnap) = split /@/,$mspec,2;
        my $output = `ssh $controller lun clone create $file -b $mlun $msnap`; 
    }

    $output = `ssh $controller igroup create -i -t $gtype $gname`;
    $output = `ssh $controller igroup add $gname $iname`;
    $output = `ssh $controller lun map $file $gname`;
}

sub configure_node {
    my $controller = shift;
    my $node = shift;
    my $cfg = $iscsicfg{$controller}->{$node};
    my $lunmap = shift;
    my $request = shift;
    my $lunsize;
    my $masterspec;
    if ($request->{arg}) {
        use Getopt::Long;
        @ARGV=@{$request->{arg}};
         GetOptions(
                   "size|s=i" => \$lunsize,
                   "master|m=s" => \$masterspec,
         );
    }
    unless (defined $lunmap->{$node}->{$cfg->{file}}) {
        if ($lunsize) {
            create_new_lun($controller,$node,$cfg,lsize=>$lunsize);
        } elsif ($masterspec) {
            create_new_lun($controller,$node,$cfg,mspec=>$masterspec);
        } else {
            die "IMPLEMENT MAKING NEW LUN";
        }
    }
    if ($cfg->{lun} ne $lunmap->{$node}->{$cfg->{file}}) {
        $iscsitab->setNodeAttribs($node,{lun=>$lunmap->{$node}->{$cfg->{file}}});
    }
}
    
1;


