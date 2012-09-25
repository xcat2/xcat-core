# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::00pcmkitbase;

use strict;
use warnings;
require xCAT::Utils;
require xCAT::Table;
require xCAT::PCMNodeMgmtUtils;

#-------------------------------------------------------

=head1

    xCAT plugin, which is also the default PCM kit plugin.
    These commands are called by PCM node management commands, 
    should not be called directly by external.

    The kit plugin framework is creating a common framework for kits' extension. The major feature of this framework is to update kits' related configuration files/services automatically while add/remove/update nodes.
    
    According to design, if a kit wants have such a auto configure feature, it should create a xCAT plugin which implement commands "kitcmd_nodemgmt_add", "kitcmd_nodemgmt_remove"..., just like plugin "00pcmkitbase".

    For example, we create a kit for LSF, and want to update LSF's configuration file automatically updated while add/remove/update xCAT nodes, then we should create a xCAT plugin. This plugin will update LSF's configuration file and may also reconfigure/restart LSF service while these change happens.

    If we have multi kits, and all these kits have such a plugin, then all these plugins will be called while we add/remove/update xCAT nodes. To configure these kits in one go by auto.

    This plugin is a PCM kit plugin, just for configure nodes' related configurations automatically. So that we do not need to run these make* commands manually after creating them.    

    About PCM kit plugin naming:  naming this plugin starts with "00" is a way for specifying plugin calling orders, we want to call the default kit plugin in front of other kit plugins.

=cut

#-------------------------------------------------------

#-------------------------------------------------------

=head3  handled_commands

    Return list of commands handled by this plugin

=cut

#-------------------------------------------------------
sub handled_commands {
    return {
        kitcmd_nodemgmt_add => '00pcmkitbase',
        kitcmd_nodemgmt_remove => '00pcmkitbase',
        kitcmd_nodemgmt_update => '00pcmkitbase',
        kitcmd_nodemgmt_refresh => '00pcmkitbase',
        kitcmd_nodemgmt_finished => '00pcmkitbase',
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
    
    my $nodelist = $request->{node};
    my $retref;

    if($command eq 'kitcmd_nodemgmt_add')
    {
        $retref = xCAT::Utils->runxcmd({command=>["makehosts"], node=>$nodelist}, $request_command, 0, 1);
        $retref = xCAT::Utils->runxcmd({command=>["makedns"], node=>$nodelist, arg=>['-n']}, $request_command, 0, 1);
        # Work around for makedns bug, it will set umask to 0007.
        #umask(0022);
        $retref = xCAT::Utils->runxcmd({command=>["makekdhcp"], node=>$nodelist}, $request_command, 0, 1);
        $retref = xCAT::Utils->runxcmd({command=>["makeknownhosts"], node=>$nodelist}, $request_command, 0, 1);
        my $firstnode = (@$nodelist)[0];
        my $profileref = xCAT::PCMNodeMgmtUtils->get_nodes_profiles([$firstnode]);
        my %profilehash = %$profileref;
        if (exists $profilehash{$firstnode}{"ImageProfile"}){
            $retref = xCAT::Utils->runxcmd({command=>["nodeset"], node=>$nodelist, arg=>['osimage='.$profilehash{$firstnode}{"ImageProfile"}]}, $request_command, 0, 1);
        }

    }
    elsif ($command eq 'kitcmd_nodemgmt_remove'){
        $retref = xCAT::Utils->runxcmd({command=>["nodeset"], node=>$nodelist, arg=>['offline']}, $request_command, 0, 1);
        $retref = xCAT::Utils->runxcmd({command=>["makeknownhosts"], node=>$nodelist, arg=>['-r']}, $request_command, 0, 1);
        $retref = xCAT::Utils->runxcmd({command=>["makekdhcp"], node=>$nodelist, arg=>['-d']}, $request_command, 0, 1);
        $retref = xCAT::Utils->runxcmd({command=>["makedns"], node=>$nodelist, arg=>['-d']}, $request_command, 0, 1);
        # Work around for makedns bug, it will set umask to 0007.
        #umask(0022);
        $retref = xCAT::Utils->runxcmd({command=>["makehosts"], node=>$nodelist, arg=>['-d']}, $request_command, 0, 1);
    }
    elsif ($command eq 'kitcmd_nodemgmt_update'){
        $retref = xCAT::Utils->runxcmd({command=>["makehosts"], node=>$nodelist}, $request_command, 0, 1);
        $retref = xCAT::Utils->runxcmd({command=>["makedns"], node=>$nodelist, arg=>['-n']}, $request_command, 0, 1);
        # Work around for makedns bug, it will set umask to 0007.
        #umask(0022);
        $retref = xCAT::Utils->runxcmd({command=>["makekdhcp"], node=>$nodelist}, $request_command, 0, 1);
        $retref = xCAT::Utils->runxcmd({command=>["makeknownhosts"], node=>$nodelist}, $request_command, 0, 1);
        my $firstnode = (@$nodelist)[0];
        my $profileref = xCAT::PCMNodeMgmtUtils->get_nodes_profiles([$firstnode]);
        my %profilehash = %$profileref;
        if (exists $profilehash{$firstnode}{"ImageProfile"}){
            $retref = xCAT::Utils->runxcmd({command=>["nodeset"], node=>$nodelist, arg=>['osimage='.$profilehash{$firstnode}{"ImageProfile"}]}, $request_command, 0, 1);
        }
    }
    elsif ($command eq 'kitcmd_nodemgmt_refresh'){
        $retref = xCAT::Utils->runxcmd({command=>["makehosts"], node=>$nodelist}, $request_command, 0, 1);
        $retref = xCAT::Utils->runxcmd({command=>["makedns"], node=>$nodelist, arg=>['-n']}, $request_command, 0, 1);
        # Work around for makedns bug, it will set umask to 0007.
        #umask(0022);
        $retref = xCAT::Utils->runxcmd({command=>["makekdhcp"], node=>$nodelist}, $request_command, 0, 1);
        $retref = xCAT::Utils->runxcmd({command=>["makeknownhosts"], node=>$nodelist}, $request_command, 0, 1);
    }
    elsif ($command eq 'kitcmd_nodemgmt_finished')
    {
        $retref = xCAT::Utils->runxcmd({command=>["makeconservercf"]}, $request_command, 0, 1);
    }
    else
    {
    }
}

1;
