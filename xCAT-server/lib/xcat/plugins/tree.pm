package xCAT_plugin::tree;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::NodeRange;
use Data::Dumper;
use xCAT::Utils;
use Sys::Syslog;
use xCAT::GlobalDef;
use xCAT::Table;
use Getopt::Long;
use xCAT::SvrUtils;
#use strict;

sub handled_commands
{
    # currently, only for lstree command.
    return {
        lstree => "tree",
    };
}

sub usage
{
    my $command = shift;
    my $callback = shift;

    if($command eq "lstree")
    {
        &usage_lstree($callback);
        return 0;
    }
    else
    {
        return 1;
    }
}

#----------------------------------------------------------------------------

=head3  usage_lstree

=cut

#-----------------------------------------------------------------------------
sub usage_lstree
{
    my $callback = shift;

    my $rsp;
    push @{$rsp->{data}},
      "\n  lstree - Display the tree of service node hierarchy, hardware hierarchy, or VM hierarchy.";
    push @{$rsp->{data}}, "  Usage: ";
    push @{$rsp->{data}}, "\tlstree [-h | --help]";
    push @{$rsp->{data}}, "or";
    push @{$rsp->{data}}, "\tlstree [-s | --servicenode] [-H | --hardwaremgmt] [-v | --virtualmachine] [noderange]";
    
    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}

#----------------------------------------------------------------------------

=head3  process_request

=cut

#-----------------------------------------------------------------------------
sub process_request
{
    my $request = shift;
    my $callback = shift;
    my @nodes=();

    if($request->{node})
    {
        @nodes = @{$request->{node}};
    }
    else
    {
        # handle all nodes by default.
        my $nodelist = xCAT::Table->new('nodelist');
        unless ($nodelist)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Can not open nodelist table.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        }

        my @entries  = ($nodelist->getAllNodeAttribs([qw(node)]));
        foreach (@entries)
        {
            push @nodes, $_->{node};
        }
    }

    my $command = $request->{command}->[0];
    if($command eq "lstree")
    {
        &lstree($request, $callback, \@nodes);
        return 0;
    }
    else
    {
        $callback->({error=>["error in code..."], errorcode=>[127]});
        $request = {};
        return 0;
    }
}

#----------------------------------------------------------------------------

=head3  lstree

=cut

#-----------------------------------------------------------------------------
sub lstree
{
    my $request = shift;
    my $callback = shift;
    my $nodelist = shift;

    unless($request->{arg} || defined $nodelist)
    {
        &usage_lstree($callback);
        return 1;
    }

    # parse the options
    Getopt::Long::Configure("no_pass_through");
    Getopt::Long::Configure("bundling");
    
    if ($request->{arg})
    {
        @ARGV = @{$request->{arg}};
        
        if (
            !GetOptions(
                        'h|help'           => \$::HELP,
                        's|servicenode'    => \$::SVCNODE,
                        'H|hardwaremgmt'   => \$::HDWR,
                        'v|virtualmachine' => \$::VMACHINE,
            )
          )
        {
            &usage_lstree($callback);
            return 1;
        }
    }

    if ($::HELP)
    {
        &usage_lstree($callback);
        return 0;
    }

    if (!$::SVCNODE && !$::HDWR && !$::VMACHINE)
    {
        # show both vmtree and hwtree by default.
        $::SHOWALL = 1;
    }

    my %hwtrees;
    my %vmtrees;
    my %sntrees;
    
    # servicenode hierarchy
    if ($::SVCNODE)
    {
        # build up sn tree hash.
        my $snhash;
        my @entries;
        my $restab = xCAT::Table->new('noderes');
        if ($restab)
        {
            $snhash = $restab->getNodesAttribs($nodelist, ['servicenode']);
            @entries = $restab->getAllNodeAttribs(['node','servicenode']);
        }
        else
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Can not open noderes table.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        }

        foreach my $node (@$nodelist)
        {
            # servicenode defined for this node
            if ($snhash->{$node}->[0]->{'servicenode'})
            {
                unless (grep(/$node/, @{$sntrees{$snhash->{$node}->[0]->{'servicenode'}}}))
                {
                    push @{$sntrees{$snhash->{$node}->[0]->{'servicenode'}}}, $node;
                }
            }
            else # need to know if itself is service node
            {
                foreach my $ent (@entries)
                {
                    if ($ent->{servicenode} eq $node)
                    {
                        unless (grep(/$ent->{node}/, @{$sntrees{$node}}))
                        {
                            push @{$sntrees{$node}}, $ent->{node};
                        }
                    }
                }
            }
        
        }
        #print Dumper(\%sntreehash);

        # show service node tree
        &showtree(\%sntrees, 0, 0, $callback);
    }    

    # get hwtree hash from each plugin
    if ($::HDWR || $::SHOWALL)
    {
        # classify the nodes
        # read nodehm.mgt
        my $hmhash;
        my $hmtab = xCAT::Table->new('nodehm');
        if ($hmtab)
        {
            $hmhash = $hmtab->getNodesAttribs($nodelist, ['mgt']);
        }
        else
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Can not open nodehm table.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        }

        # may add new support later.
        my @supportedhw = ("hmc", "fsp", "blade", "ipmi");
        my %hwnodes;

        foreach my $node (@$nodelist)
        {
            # mgt defined for this node
            unless ($hmhash->{$node}->[0]->{'mgt'})
            {
                next;
            }

            if (grep(/$hmhash->{$node}->[0]->{'mgt'}/, @supportedhw))
            {
                push @{$hwnodes{$hmhash->{$node}->[0]->{'mgt'}}}, $node;
            }
        }

        if (%hwnodes)
        {
            foreach my $type (keys %hwnodes)
            {
                $hwtrees{$type} = ${"xCAT_plugin::".$type."::"}{genhwtree}->(\@{$hwnodes{$type}}, $callback);
            }
        }

        #print Dumper(\%hwtrees);
    }

    if ($::HDWR && !$::VMACHINE)
    {
        &showtree(0, \%hwtrees, 0, $callback);
    }

    # generate vmtree from xcat vm table
    if ($::VMACHINE || $::SHOWALL)
    {

        # here is a special case for zvm.
        ########### start ################
        # read nodehm.mgt
        my $hmhash;
        my $hmtab = xCAT::Table->new('nodehm');
        if ($hmtab)
        {
            $hmhash = $hmtab->getNodesAttribs($nodelist, ['mgt']);
        }
        else
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Can not open nodehm table.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        }

        my @znodes;

        foreach my $node (@$nodelist)
        {
            # mgt defined for this node
            unless ($hmhash->{$node}->[0]->{'mgt'})
            {
                next;
            }

            if ($hmhash->{$node}->[0]->{'mgt'} =~ /zvm/)
            {
                push @znodes, $node;
            }
        }

        my $ret = xCAT_plugin::zvm::listTree($callback, \@znodes);
        
        ########### end ################
        
        # read vm.host
        my $vmhash;
        
        my $vmtab = xCAT::Table->new('vm');
        if ($vmtab)
        {
            $vmhash = $vmtab->getNodesAttribs($nodelist, ['host']);
        }
        else
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Can not open vm table.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        }

        my @entries = $vmtab->getAllNodeAttribs(['node','host']);
        
        foreach my $node (@$nodelist)
        {
            foreach my $ent (@entries)
            {
                if ($ent->{host} =~ /$node/) # host
                {
                    push @{$vmtrees{$node}}, $ent->{node};
                }
            }
            
            if ($vmhash && $vmhash->{$node}->[0]->{'host'}) # vm
            {
                unless (grep(/$node/, @{$vmtrees{$vmhash->{$node}->[0]->{'host'}}}))
                {
                    push @{$vmtrees{$vmhash->{$node}->[0]->{'host'}}}, $node;
                }
            }
        }        
        #print Dumper(\%vmtrees);
    }

    # vm tree output
    if (!$::HDWR && $::VMACHINE)
    {
        &showtree(0, 0, \%vmtrees, $callback);
    }

    if ($::SHOWALL || ($::HDWR && $::VMACHINE))
    {
        &showtree(0, \%hwtrees, \%vmtrees, $callback);
    }
    return;

} # lstree end

#----------------------------------------------------------------------------

=head3  showtree

=cut

#-----------------------------------------------------------------------------
sub showtree
{
    my $snthash = shift;
    my $hwthash = shift;
    my $vmthash = shift;
    my $callback = shift;

    my %sntrees = %$snthash;
    my %hwtrees = %$hwthash;
    my %vmtrees = %$vmthash;

    # temp workaround before we integrate LPARs into vm table
    my $lparinvm = 0;
    my @entries;

    if (!$lparinvm)
    {
        # read ppc table
        my $ppctab = xCAT::Table->new('ppc');
        unless ($ppctab)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Can not open ppc table.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        }

        @entries = $ppctab->getAllNodeAttribs(['node','id','parent']);    
    }

    if (%sntrees)
    {
        my $rsp;

        foreach my $sn (sort(keys %sntrees))
        {
            push @{$rsp->{data}}, "Service Node: $sn";
            foreach my $cn (sort(@{$sntrees{$sn}}))
            {
                push @{$rsp->{data}}, "|__$cn";
            }
            push @{$rsp->{data}}, "\n";
        }
        xCAT::MsgUtils->message("I", $rsp, $callback);  
    }

    # show hardware hierarchy
    if (%hwtrees)    
    {
        my $rsp;

        # hmc tree output
        foreach my $hmc (sort(keys %{$hwtrees{hmc}}))
        {
            push @{$rsp->{data}}, "HMC: $hmc";
            foreach my $frame (sort(keys %{$hwtrees{hmc}{$hmc}}))
            {
                if ($frame eq '0')
                {
                    # no frame
                    push @{$rsp->{data}}, "|__Frame: n/a";
                }
                else
                {
                    # get bpas for frame.
                    my $bpas = xCAT::DBobjUtils->getchildren($frame);
                    my $bpalist = join ',', @$bpas; 
                    push @{$rsp->{data}}, "|__Frame: $frame $bpalist";
                }
                
                foreach my $cec (sort @{$hwtrees{hmc}{$hmc}{$frame}})
                {

                    # get fsps for cec.
                    my $fsps = xCAT::DBobjUtils->getchildren($cec);
                    my $fsplist = join ',', @$fsps; 
                    push @{$rsp->{data}}, "   |__CEC: $cec $fsplist";

                    if ($lparinvm)
                    {
                        # if show both, tailing with vmtree.
                        if (%vmtrees)
                        {
                            foreach my $host (sort(keys %vmtrees))
                            {
                                if ($host =~ /$cec/)
                                {
                                    foreach my $vm (sort(@{$vmtrees{$host}}))
                                    {
                                        push @{$rsp->{data}}, "      |__ $vm";
                                    }

                                    # remove it as shown
                                    undef $vmtrees{$host};
                                }
                            }
                        }                    
                    }
                    elsif ($::VMACHINE || $::SHOWALL) # temp workaround before we integrate LPARs into vm table
                    {
                        my %vm;
                        # get all lpars in this cec.
                        foreach my $ent (@entries)
                        {
                            if ($ent->{parent} =~ /$cec/)
                            {
                                $vm{$ent->{id}} = $ent->{node};
                            }
                        }

                        foreach my $id (sort(keys %vm))
                        {
                            push @{$rsp->{data}}, "      |__LPAR $id: $vm{$id}";
                        }
                    }
                }
            }
            push @{$rsp->{data}}, "\n";
        }

        # DFM tree output
        foreach my $sfp (sort(keys %{$hwtrees{fsp}}))
        {
            if ($sfp eq '0')
            {
                # no frame
                push @{$rsp->{data}}, "Service Focal Point: n/a";
            }
            else
            {
                push @{$rsp->{data}}, "Service Focal Point: $sfp";
            }

            foreach my $frame (sort(keys %{$hwtrees{fsp}{$sfp}}))
            {
                if ($frame eq '0')
                {
                    # no frame
                    push @{$rsp->{data}}, "|__Frame: n/a";
                }
                else
                {
                    # get bpas for frame.
                    my $bpas = xCAT::DBobjUtils->getchildren($frame);
                    my $bpalist = join ',', @$bpas; 
                    push @{$rsp->{data}}, "|__Frame: $frame $bpalist";
                }
                
                foreach my $cec (sort @{$hwtrees{fsp}{$sfp}{$frame}})
                {

                    # get fsps for cec.
                    my $fsps = xCAT::DBobjUtils->getchildren($cec);
                    my $fsplist = join ',', @$fsps; 
                    push @{$rsp->{data}}, "   |__CEC: $cec $fsplist";

                    if ($lparinvm)
                    {
                        # if show both, tailing with vmtree.
                        if (%vmtrees)
                        {
                            foreach my $host (sort(keys %vmtrees))
                            {
                                if ($host =~ /$cec/)
                                {
                                    foreach my $vm (sort(@{$vmtrees{$host}}))
                                    {
                                        push @{$rsp->{data}}, "      |__ $vm";
                                    }
                                    # remove it as shown
                                    undef $vmtrees{$host};                                
                                }
                            }
                        }                    
                    }
                    elsif ($::VMACHINE || $::SHOWALL) # temp workaround before we integrate LPARs into vm table
                    {
                        my %vm;
                        # get all lpars in this cec.
                        foreach my $ent (@entries)
                        {
                            if ($ent->{parent} =~ /$cec/)
                            {
                                $vm{$ent->{id}} = $ent->{node};
                            }
                        }

                        foreach my $id (sort(keys %vm))
                        {
                            push @{$rsp->{data}}, "      |__LPAR $id: $vm{$id}";
                        }
                    }
                }
            }
            push @{$rsp->{data}}, "\n";
        }

        # blade tree output
        foreach my $mm (sort(keys %{$hwtrees{blade}}))
        {
            push @{$rsp->{data}}, "Management Module: $mm";

            foreach my $slot (sort(keys %{$hwtrees{blade}{$mm}}))
            {
                my $blade = $hwtrees{blade}{$mm}{$slot};
                push @{$rsp->{data}}, "|__Blade $slot: $blade"; 

                # if show both, tailing with vmtree.
                if (%vmtrees)
                {
                    foreach my $host (sort(keys %vmtrees))
                    {
                        if ($host =~ /$blade/)
                        {
                            foreach my $vm (sort(@{$vmtrees{$host}}))
                            {
                                push @{$rsp->{data}}, "   |__ $vm";
                            }
                            # remove it as shown
                            undef $vmtrees{$host};                            
                        }
                    }
                }
            }
            push @{$rsp->{data}}, "\n";
        }

        # ipmi tree output
        foreach my $bmc (sort(keys %{$hwtrees{ipmi}}))
        {
            push @{$rsp->{data}}, "BMC: $bmc";
            foreach my $svr (sort(@{$hwtrees{ipmi}{$bmc}}))
            {
                push @{$rsp->{data}}, "|__Server: $svr";

                # if show both, tailing with vmtree.
                if (%vmtrees)
                {
                    foreach my $host (sort(keys %vmtrees))
                    {
                        if ($host =~ /$svr/)
                        {
                            foreach my $vm (sort(@{$vmtrees{$host}}))
                            {
                                push @{$rsp->{data}}, "   |__ $vm";
                            }
                            # remove it as shown
                            undef $vmtrees{$host};                            
                        }
                    }
                }                
            }
            push @{$rsp->{data}}, "\n";
        }        
        
        xCAT::MsgUtils->message("I", $rsp, $callback);                    
    }    

    # show VM hierarchy
    if (%vmtrees)
    {
        my $rsp;
        foreach my $host (sort(keys %vmtrees))
        {
            if (defined $vmtrees{$host})
            {
                push @{$rsp->{data}}, "Server: $host";
                foreach my $vm (sort(@{$vmtrees{$host}}))
                {
                    push @{$rsp->{data}}, "|__ $vm";
                }
            }
            push @{$rsp->{data}}, "\n";
        }
        xCAT::MsgUtils->message("I", $rsp, $callback);
        
    }
    
    return;
}



1;
