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

    if($command eq 'kitnodeadd')
    {
        setrsp_progress("Updating hosts entries");
        $retref = xCAT::Utils->runxcmd({command=>["makehosts"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);

        setrsp_progress("Updating DNS entries");
        $retref = xCAT::Utils->runxcmd({command=>["makedns"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);

        if($macflag)
        {
            setrsp_progress("Update DHCP entries");
            $retref = xCAT::Utils->runxcmd({command=>["makedhcp"], node=>$nodelist}, $request_command, 0, 2);
            log_cmd_return($retref);
        }

        setrsp_progress("Update known hosts");
        $retref = xCAT::Utils->runxcmd({command=>["makeknownhosts"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);

        my $firstnode = (@$nodelist)[0];
        my $chaintab = xCAT::Table->new("chain");
        my $chainref = $chaintab->getNodeAttribs($firstnode, ['chain']);
        my $chainstr = $chainref->{'chain'};
        my @chainarray = split(",", $chainstr);

        if($macflag)
        {
            if ($chainarray[0]){
                setrsp_progress("Update nodes' boot settings");
                $retref = xCAT::Utils->runxcmd({command=>["nodeset"], node=>$nodelist, arg=>[$chainarray[0]]}, $request_command, 0, 2);
                log_cmd_return($retref);
            }
        }
        my $isfsp = xCAT::ProfiledNodeUtils->is_fsp_node([$firstnode]);
        if ($isfsp) {
            setrsp_progress("Updating FSP's IP address");
            $retref = xCAT::Utils->runxcmd({command=>["rspconfig"], node=>$nodelist, arg=>['network=*']}, $request_command, 0, 2);
            log_cmd_return($retref);

            my $cmmref = xCAT::ProfiledNodeUtils->get_nodes_cmm($nodelist);
            my @cmmchassis = keys %$cmmref;
            setrsp_progress("Update node's some attributes through 'rscan -u'");
            $retref = xCAT::Utils->runxcmd({command=>["rscan"], node=>\@cmmchassis, arg=>['-u']}, $request_command, 0, 2);
            log_cmd_return($retref);

            setrsp_progress("Sets up connections for nodes to FSP");
            $retref = xCAT::Utils->runxcmd({command=>["mkhwconn"], node=>$nodelist, arg=>['-t']}, $request_command, 0, 2);
            log_cmd_return($retref);
        }
        
        setrsp_progress("Updating conserver configuration files");
        $retref = xCAT::Utils->runxcmd({command=>["makeconservercf"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);
    }
    elsif ($command eq 'kitnoderemove'){
        setrsp_progress("Updating conserver configuration files");
        $retref = xCAT::Utils->runxcmd({command=>["makeconservercf"], node=>$nodelist, arg=>['-d']}, $request_command, 0, 2);
        log_cmd_return($retref);

        setrsp_progress("Update nodes' boot settings");
        $retref = xCAT::Utils->runxcmd({command=>["nodeset"], node=>$nodelist, arg=>['offline']}, $request_command, 0, 2);
        log_cmd_return($retref);

        setrsp_progress("Update known hosts");
        $retref = xCAT::Utils->runxcmd({command=>["makeknownhosts"], node=>$nodelist, arg=>['-r']}, $request_command, 0, 2);
        log_cmd_return($retref);

        setrsp_progress("Update DHCP entries");
        $retref = xCAT::Utils->runxcmd({command=>["makedhcp"], node=>$nodelist, arg=>['-d']}, $request_command, 0, 2);
        log_cmd_return($retref);
    }
    elsif ($command eq 'kitnodeupdate'){
        setrsp_progress("Updating hosts entries");
        $retref = xCAT::Utils->runxcmd({command=>["makehosts"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);

        setrsp_progress("Updating DNS entries");
        $retref = xCAT::Utils->runxcmd({command=>["makedns"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);

        setrsp_progress("Update DHCP entries");
        $retref = xCAT::Utils->runxcmd({command=>["makedhcp"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);

        setrsp_progress("Update known hosts");
        $retref = xCAT::Utils->runxcmd({command=>["makeknownhosts"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);
        my $firstnode = (@$nodelist)[0];
        my $profileref = xCAT::ProfiledNodeUtils->get_nodes_profiles([$firstnode]);
        my %profilehash = %$profileref;
        if (exists $profilehash{$firstnode}{"ImageProfile"}){
            setrsp_progress("Update nodes' boot settings");
            $retref = xCAT::Utils->runxcmd({command=>["nodeset"], node=>$nodelist, arg=>['osimage='.$profilehash{$firstnode}{"ImageProfile"}]}, $request_command, 0, 2);
            log_cmd_return($retref);
        }

        setrsp_progress("Updating conserver configuration files");
        $retref = xCAT::Utils->runxcmd({command=>["makeconservercf"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);
    }
    elsif ($command eq 'kitnoderefresh'){
        # This is due to once update nicips table, we need remove node's records first and then re-create by run make* commands.
        setrsp_progress("Remove nodes entries from system configuration files first.");
        $retref = xCAT::Utils->runxcmd({command=>["kitnoderemove"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);

        setrsp_progress("Updating hosts entries");
        $retref = xCAT::Utils->runxcmd({command=>["makehosts"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);

        setrsp_progress("Updating DNS entries");
        $retref = xCAT::Utils->runxcmd({command=>["makedns"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);

        setrsp_progress("Update DHCP entries");
        $retref = xCAT::Utils->runxcmd({command=>["makedhcp"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);

        setrsp_progress("Update known hosts");
        $retref = xCAT::Utils->runxcmd({command=>["makeknownhosts"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);

        setrsp_progress("Updating conserver configuration files");
        $retref = xCAT::Utils->runxcmd({command=>["makeconservercf"], node=>$nodelist}, $request_command, 0, 2);
        log_cmd_return($retref);
    }
    else
    {
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
