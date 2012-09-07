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

    if($command eq 'kitcmd_nodemgmt_add')
    {
        $request_command->({command=>["makehosts"], node=>$nodelist});
        $request_command->({command=>["makedns"], node=>$nodelist}, arg=>['-n']);
        # Work around for makedns bug, it will set umask to 0007.
        umask(0022);
        $request_command->({command=>["makedhcp"], node=>$nodelist});
        $request_command->({command=>["makeknownhosts"], node=>$nodelist});
        my $firstnode = (@$nodelist)[0];
        my $profileref = xCAT::PCMNodeMgmtUtils->get_nodes_profiles([$firstnode]);
        my %profilehash = %$profileref;
        if (exists $profilehash{$firstnode}{"ImageProfile"}){
            $request_command->({command=>["nodeset"], node=>$nodelist, arg=>['osimage='.$profilehash{$firstnode}{"ImageProfile"}]});
        }

    }
    elsif ($command eq 'kitcmd_nodemgmt_remove'){
        $request_command->({command=>["nodeset"], node=>$nodelist, arg=>['offline']});
        $request_command->({command=>["makeknownhosts"], node=>$nodelist, arg=>['-r']});
        $request_command->({command=>["makedhcp"], node=>$nodelist, arg=>['-d']});
        $request_command->({command=>["makedns"], node=>$nodelist, arg=>['-d']});
        # Work around for makedns bug, it will set umask to 0007.
        umask(0022);
        $request_command->({command=>["makehosts"], node=>$nodelist, arg=>['-d']});
    }
    elsif ($command eq 'kitcmd_nodemgmt_update'){
        $request_command->({command=>["makehosts"], node=>$nodelist});
        $request_command->({command=>["makedns"], node=>$nodelist}, arg=>['-n']);
        # Work around for makedns bug, it will set umask to 0007.
        umask(0022);
        $request_command->({command=>["makedhcp"], node=>$nodelist});
        $request_command->({command=>["makeknownhosts"], node=>$nodelist});
        my $firstnode = (@$nodelist)[0];
        my $profileref = xCAT::PCMNodeMgmtUtils->get_nodes_profiles([$firstnode]);
        my %profilehash = %$profileref;
        if (exists $profilehash{$firstnode}{"ImageProfile"}){
            $request_command->({command=>["nodeset"], node=>$nodelist, arg=>['osimage='.$profilehash{$firstnode}{"ImageProfile"}]});
        }
    }
    elsif ($command eq 'kitcmd_nodemgmt_refresh'){
        $request_command->({command=>["makehosts"], node=>$nodelist});
        $request_command->({command=>["makedns"], node=>$nodelist}, arg=>['-n']);
        # Work around for makedns bug, it will set umask to 0007.
        umask(0022);
        $request_command->({command=>["makedhcp"], node=>$nodelist});
        $request_command->({command=>["makeknownhosts"], node=>$nodelist});
    }
    elsif ($command eq 'kitcmd_nodemgmt_finished')
    {
        $request_command->({command=>["makeconservercf"]});
    }
    else
    {
    }
}

1;
