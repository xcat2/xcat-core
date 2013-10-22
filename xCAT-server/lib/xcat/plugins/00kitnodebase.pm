# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::00kitnodebase;

use strict;
use warnings;
use Data::Dumper;
require xCAT::Utils;
require xCAT::Table;
require xCAT::ProfiledNodeUtils;

#-------------------------------------------------------

=head1

    xCAT plugin, which is also the default kit plugin.
    These commands are called by node management commands, 
    should not be called directly by external.

    The kit plugin framework is creating a common framework for kits' extension. The major feature of this framework is to update kits' related configuration files/services automatically while add/remove/update nodes.
    
    According to design, if a kit wants have such a auto configure feature, it should create a xCAT plugin which implement commands "kitcmd_nodemgmt_add", "kitcmd_nodemgmt_remove"..., just like plugin "00kitnodebase".

    For example, we create a kit for LSF, and want to update LSF's configuration file automatically updated while add/remove/update xCAT nodes, then we should create a xCAT plugin. This plugin will update LSF's configuration file and may also reconfigure/restart LSF service while these change happens.

    If we have multi kits, and all these kits have such a plugin, then all these plugins will be called while we add/remove/update xCAT nodes. To configure these kits in one go by auto.

    This plugin is a kit plugin, just for configure nodes' related configurations automatically. So that we do not need to run these make* commands manually after creating them.    

    About kit plugin naming:  naming this plugin starts with "00" is a way for specifying plugin calling orders, we want to call the default kit plugin in front of other kit plugins.

=cut

#-------------------------------------------------------

#-------------------------------------------------------

=head3  handled_commands

    Return list of commands handled by this plugin

=cut

#-------------------------------------------------------
sub handled_commands {
    return {
        kitnodeadd => '00kitnodebase',
        kitnoderemove => '00kitnodebase',
        kitnodeupdate => '00kitnodebase',
        kitnoderefresh => '00kitnodebase',
    };

}

#-------------------------------------------------------

=head3  process_request

    Process the command.  This is the main call.

=cut

#-------------------------------------------------------
sub process_request {
    my $request = shift;
    my $callback = shift;
    my $request_command = shift;
    my $command = $request->{command}->[0];
    my $argsref = $request->{arg};
    my $macflag = 1;
    if(exists($request->{macflag}))
    {
        $macflag = $request->{macflag}->[0];
    }
    my $nodelist = $request->{node};
    my $retref;
    my $rsp;
    
    # Get nodes profile 
    my $profileref = xCAT::ProfiledNodeUtils->get_nodes_profiles($nodelist);
    my %profilehash = %$profileref;
    
    # Check whetehr we need to run makeconservercf
    # If one node has hardwareprofile, we need to run makeconservercf
    my $runconservercmd = 0;
    foreach (keys %profilehash) {
        if (exists $profilehash{$_}{'HardwareProfile'}) {
            $runconservercmd = 1;
            last;
        }
    }
    
    my @commandslist;
    my %argslist;
    my $noupdate_flag = 0;
    my %msghash = ( "makehosts"         => "Updating hosts entries",
                    "makedns"           => "Updating DNS entries",
                    "makedhcp"          => "Update DHCP entries",
                    "makeknownhosts"    => "Update known hosts",
                    "makeconservercf"   => "Updating conserver configuration files",
                    "kitnoderemove"     => "Remove nodes entries from system configuration files first.",
                    "nodeset"           => "Update nodes' boot settings",
                    "rspconfig"         => "Updating FSP's IP address",
                    "rscan"             => "Update node's some attributes through 'rscan -u'",
                    "mkhwconn"          => "Sets up connections for nodes to FSP",
                  );
    
    # Stage1:  pre-run     
    if ($command eq 'kitnoderefresh') {
        # This is due to once update nicips table, we need remove node's records first and then re-create by run make* commands. If not, old records can't be removed.
        push @commandslist, ['makedns', '-d'];
        push @commandslist, ['makehosts', '-d'];
    }
    
    # Stage2: run xcat commands
    if ($command eq 'kitnodeadd' or $command eq 'kitnodeupdate' or $command eq 'kitnoderefresh') {
        push @commandslist, ['makehosts', ''];
        push @commandslist, ['makedns', ''];
        if ($macflag) {
            push @commandslist, ['makedhcp', ''];
        }
        push @commandslist, ['makeknownhosts', ''];
        if ($runconservercmd) {
            push @commandslist, ['makeconservercf', ''];
        }
    }elsif ($command eq 'kitnoderemove') {
        if ($runconservercmd) {
            push @commandslist, ['makeconservercf', '-d'];
        }
        push @commandslist, ['makeknownhosts', '-r'];
        if ($macflag) {
            push @commandslist, ['makedhcp', '-d'];
        }
    }
    
    # Stage3: post-run
    if ($command eq 'kitnodeadd') {
        my $firstnode = (@$nodelist)[0];
        my $chaintab = xCAT::Table->new("chain");
        my $chainref = $chaintab->getNodeAttribs($firstnode, ['chain']);
        my $chainstr = $chainref->{'chain'};
        my @chainarray = split(",", $chainstr);

        if($macflag)
        {
            if ($chainarray[0]){
                if($chainarray[0] =~ m/^osimage=/)
                {
                    $noupdate_flag = 1;
                }
                push @commandslist, ['nodeset', $chainarray[0]];
            }
        }
        my $isfsp = xCAT::ProfiledNodeUtils->is_fsp_node([$firstnode]);
        if ($isfsp) {
            my $cmmref = xCAT::ProfiledNodeUtils->get_nodes_cmm($nodelist);
            my @cmmchassis = keys %$cmmref;

            push @commandslist, ['rspconfig', 'network=*'];
            push @commandslist, ['rscan', '-u', \@cmmchassis];
            push @commandslist, ['rmhwconn', ''];
            push @commandslist, ['mkhwconn', '-t'];
        }
    }elsif ($command eq 'kitnoderemove') {
        push @commandslist, ['nodeset', 'offline'];
    }elsif ($command eq 'kitnodeupdate') {
        my $firstnode = (@$nodelist)[0];
        if (exists $profilehash{$firstnode}{"ImageProfile"}){
            my $osimage = 'osimage='.$profilehash{$firstnode}{"ImageProfile"};
            $noupdate_flag = 1;
            push @commandslist, ['nodeset', $osimage];
        }
    }

    # Run commands
    foreach (@commandslist) {
        my $current_cmd = $_->[0];
        my $current_args = $_->[1];
        setrsp_progress($msghash{$current_cmd});
        $retref = "";
        if(($current_cmd eq "nodeset") && $noupdate_flag)
        {
            $retref = xCAT::Utils->runxcmd({command=>[$current_cmd], node=>$nodelist, arg=>[$current_args, "--noupdateinitrd"]}, $request_command, 0, 2);
        }
        elsif($current_cmd eq "rscan")
        {
            my $current_nodelist = $_->[2];
            $retref = xCAT::Utils->runxcmd({command=>[$current_cmd], node=>$current_nodelist, arg=>[$current_args]}, $request_command, 0, 2);
        }
        else
        {
            $retref = xCAT::Utils->runxcmd({command=>[$current_cmd], node=>$nodelist, arg=>[$current_args]}, $request_command, 0, 2);
        }
        log_cmd_return($retref);
    }
    
}

#-------------------------------------------------------

=head3  setrsp_progress

       Description:  generate progresss info and return to client.
       Args: $msg - The progress message.

=cut

#-------------------------------------------------------
sub setrsp_progress
{
    my $msg = shift;
    xCAT::MsgUtils->message('S', "$msg");
}

#-------------------------------------------------------

=head3  log_cmd_return

       Description:  Log commands return ref into log files.
       Args: $return - command return ref.

=cut

#-------------------------------------------------------
sub log_cmd_return
{
    my $return = shift;
    if ($return){
        if ($return->{error}){
            my $errarrayref = $return->{error};
            xCAT::MsgUtils->message('S', "Command error message:".Dumper($errarrayref));
        }
        if ($return->{data}){
            my $dataarrayref = $return->{data};
            xCAT::MsgUtils->message('S', "Command output message:".Dumper($dataarrayref));
        }
    }
}

1;
