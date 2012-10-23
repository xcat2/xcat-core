# IBM(c) 2012 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1

    xCAT plugin to support Profiled nodes management
    
=cut

#-------------------------------------------------------
package xCAT_plugin::profilednodes;

use strict;
use warnings;
require xCAT::Table;
require xCAT::DBobjUtils;
require xCAT::Utils;
require xCAT::TableUtils;
require xCAT::NetworkUtils;
require xCAT::MsgUtils;
require xCAT::ProfiledNodeUtils;

# Globals.
# These 2 global variables are for storing the parse result of hostinfo file.
# These 2 global varialbes are set in lib xCAT::DBobjUtils->readFileInput.
#%::FILEATTRS;     
#@::fileobjnames;

# All database records.
my %allhostnames;
my %allbmcips;
my %allmacs;
my %allips;
my %allinstallips;
my %allnicips;
my %allracks;
my %allchassis;

# Define parameters for xcat requests.
my $request;
my $callback;
my $request_command;
my $command;
my $args;
# Put arguments in a hash.
my %args_dict;

#-------------------------------------------------------

=head3  handled_commands

    Return list of commands handled by this plugin

=cut

#-------------------------------------------------------
sub handled_commands {
    return {
        nodeimport => 'profilednodes',
        nodepurge => 'profilednodes',
        nodechprofile => 'profilednodes',
        noderefresh =>  'profilednodes',
        nodediscoverstart => 'profilednodes',
        nodediscoverstop => 'profilednodes',
        nodediscoverls => 'profilednodes',
        nodediscoverstatus => 'profilednodes',
        nodeaddunmged => 'profilednodes',
        nodechmac => 'profilednodes',
        findme => 'profilednodes',
    };
}


#-------------------------------------------------------

=head3  process_request

    Process the command.  This is the main call.

=cut

#-------------------------------------------------------
sub process_request {

    $request = shift;
    $callback = shift;
    #$::CALLBACK = $callback;
    $request_command = shift;
    $command = $request->{command}->[0];
    $args = $request->{arg};


    my $lock = xCAT::Utils->acquire_lock("nodemgmt", 1);
    if (! $lock){
        setrsp_errormsg("Can not acquire lock, some process is operating node related actions.");
        return;
    }

    # These commands should make sure no discover is running.
    if (grep{ $_ eq $command} ("nodeimport", "nodepurge", "nodechprofile", "nodeaddunmged", "nodechmac")){
        my $discover_running = xCAT::ProfiledNodeUtils->is_discover_started();
        if ($discover_running){
            setrsp_errormsg("Can not run command $command as profiled nodes discover is running.");
            xCAT::Utils->release_lock($lock, 1);
            return;
        }
    }
	
    if ($command eq "nodeimport"){
        nodeimport()
    } elsif ($command eq "nodepurge"){
    	nodepurge();
    } elsif ($command eq "nodechprofile"){
    	nodechprofile();
    } elsif ($command eq "noderefresh"){
    	noderefresh();
    } elsif ($command eq "nodediscoverstart"){
        nodediscoverstart();
    } elsif ($command eq "nodediscoverstop"){
        nodediscoverstop();
    } elsif ($command eq "nodediscoverstatus"){
        nodediscoverstatus();
    } elsif ($command eq "findme"){
        findme();
    } elsif ($command eq "nodediscoverls"){
        nodediscoverls();
    } elsif ($command eq "nodeaddunmged"){
        nodeaddunmged();
    } elsif ($command eq "nodechmac"){
        nodechmac();
    }

    xCAT::Utils->release_lock($lock, 1);
}

#-------------------------------------------------------

=head3  parse_args

    Description : Parse arguments. We placed arguments into a directory %args_dict
    Arguments   : args - args of xCAT requests.
    Returns     : undef - parse succeed.
                  A string - parse arguments failed, the return value is error message.
=cut

#-----------------------------------------------------

sub parse_args{
    foreach my $arg (@$args){
        my @argarray = split(/=/,$arg);
        my $arglen = @argarray;
        if ($arglen > 2){
            return "Illegal arg $arg specified.";
        }

        # translate the profile names into real group names in db.
        if($argarray[0] eq "networkprofile"){
            $args_dict{$argarray[0]} = "__NetworkProfile_".$argarray[1];
        } elsif ($argarray[0] eq "imageprofile"){
            $args_dict{$argarray[0]} = "__ImageProfile_".$argarray[1];
        } elsif ($argarray[0] eq "hardwareprofile"){
            $args_dict{$argarray[0]} = "__HardwareProfile_".$argarray[1];
        } else{
            $args_dict{$argarray[0]} = $argarray[1];
        }
    }
    return undef;
}

#-------------------------------------------------------

=head3 nodeimport 

    Description : 
    Create profiled nodes by importing hostinfo file.
    This sub maps to request "nodeimport", we need to call this command from CLI like following steps:
    # ln -s /opt/xcat/bin/xcatclientnnr /opt/xcat/bin/nodeimport
    # nodeimport file=/root/hostinfo.file networkprofile=network_cn imageprofile=rhel63_cn hardwareprofile=ipmi groups=group1,group2 
    
    The hostinfo file should be written like: (MAC address is mandatory attribute)
    # Auto generate hostname for this node entry.
    __hostname__:
       mac=11:11:11:11:11:11
    # Specified hostname node.
    node01:
       mac=22:22:22:22:22:22

    After this call finished, the compute node's info will be updated automatically in /etc/hosts, dns config, dhcp config, TFTP config...

=cut

#-------------------------------------------------------
sub nodeimport{

    # Parse arges.
    xCAT::MsgUtils->message('S', "Import profiled nodes through hostinfo file.");
    my $retstr = parse_args();
    if ($retstr){
        setrsp_errormsg($retstr);
        return;
    }
    # Make sure the specified parameters are valid ones.
    my @enabledparams = ('file', 'groups', 'networkprofile', 'hardwareprofile', 'imageprofile', 'hostnameformat');
    foreach my $argname (keys %args_dict){
        if (! grep{ $_ eq $argname} @enabledparams){
            setrsp_errormsg("Illegal attribute $argname specified.");
            return;
        }
    }
    # Mandatory arguments.
    foreach (('file','networkprofile', 'imageprofile', 'hostnameformat')){
        if(! exists($args_dict{$_})){
            setrsp_errormsg("Mandatory parameter $_ not specified.");
            return;
        }
    }

    if(! (-e $args_dict{'file'})){
        setrsp_errormsg("The hostinfo file not exists.");
        return;
    }

    # Get database records: all hostnames, all ips, all racks...
    xCAT::MsgUtils->message('S', "Getting database records.");
    my $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('nodelist', 'node');
    %allhostnames = %$recordsref;
    $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('ipmi', 'bmc');
    %allbmcips = %$recordsref;
    $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('mac', 'mac');
    %allmacs = %$recordsref;
    # MAC records looks like: "01:02:03:04:05:0E!node5│01:02:03:05:0F!node6-eth1". We want to get the real mac addres.
    foreach (keys %allmacs){
        my @hostentries = split(/\|/, $_);
        foreach my $hostandmac ( @hostentries){
            my ($macstr, $machostname) = split("!", $hostandmac);
            $allmacs{$macstr} = 0;
        }
    }
    $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('hosts', 'ip');
    %allinstallips = %$recordsref;
    $recordsref = xCAT::NetworkUtils->get_all_nicips(1);
    %allips = %$recordsref;

    # Merge all BMC IPs and install IPs into allips.
    %allips = (%allips, %allbmcips, %allinstallips);

    #TODO: can not use getallnode to get rack infos.
    $recordsref = xCAT::ProfiledNodeUtils->get_all_rack(1);
    %allracks = %$recordsref;
    $recordsref =  xCAT::ProfiledNodeUtils->get_all_chassis(1);
    %allchassis = %$recordsref;

    # Generate temporary hostnames for hosts entries in hostfile. 
    xCAT::MsgUtils->message('S', "Generate temporary hostnames.");
    my ($retcode_read, $retstr_read) = read_and_generate_hostnames($args_dict{'file'});
    if ($retcode_read != 0){
        setrsp_progress("Validate hostinfo file failed");
        setrsp_errormsg($retstr_read);
        return;
    }

    # Parse and validate the hostinfo string. The real hostnames will be generated here.
    xCAT::MsgUtils->message('S', "Parsing hostinfo string and validate it.");
    my ($hostinfo_dict_ref, $invalid_records_ref) = parse_hosts_string($retstr_read);
    my %hostinfo_dict = %$hostinfo_dict_ref;
    my @invalid_records = @$invalid_records_ref;
    if (@invalid_records){
        setrsp_progress("Validate hostinfo file failed");
        setrsp_invalidrecords(\@invalid_records);
        return;
    }
    unless (%hostinfo_dict){
        setrsp_progress("Validate hostinfo file failed");
        setrsp_errormsg("No valid host records found in hostinfo file.");
        return;
    }

    # Create the real hostinfo string in stanza file format.
    xCAT::MsgUtils->message('S', "Generating new hostinfo string.");
    my ($retcode_gen, $retstr_gen) = gen_new_hostinfo_string(\%hostinfo_dict);
    unless ($retcode_gen){
        setrsp_progress("Validate hostinfo file failed");
        setrsp_errormsg($retstr_gen);
        return;
    }
    # call mkdef to create hosts and then call nodemgmt for node management plugins.
    setrsp_progress("Import nodes started.");
    setrsp_progress("call mkdef to create nodes.");
    my $warnstr = "";
    my $retref = xCAT::Utils->runxcmd({command=>["mkdef"], stdin=>[$retstr_gen], arg=>['-z']}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running mkdef: $retstr");
    # runxcmd failed.
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to import some nodes into db."); 
        $warnstr = "Warning: failed to import some nodes into db while running mkdef. details: $retstr";
    }

    my @nodelist = keys %hostinfo_dict;
    setrsp_progress("call nodemgmt plugins.");
    $retref = xCAT::Utils->runxcmd({command=>["kitnodeadd"], node=>\@nodelist}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running kitnodeadd: $retstr");
    if ($::RUNCMD_RC != 0){
        $warnstr .= "Warning: failed to run command kitnodeadd. details: $retstr";
    }

    $retref = xCAT::Utils->runxcmd({command=>["kitnodefinished"], node=>\@nodelist}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running kitnodefinished: $retstr");
    if ($::RUNCMD_RC != 0){
        $warnstr .= "Warning: failed to run command kitnodefinished. details: $retstr";
    }

    setrsp_progress("Import nodes success.");
    #TODO: get the real nodelist here.
    setrsp_success(\@nodelist, $warnstr);
}

#-------------------------------------------------------

=head3  nodepurge

    Description : Remove nodes. After nodes removed, their info in /etc/hosts, dhcp, dns... will be removed automatically.
    Arguments   : N/A

=cut

#-------------------------------------------------------
sub nodepurge{
    my $nodes   = $request->{node};
    xCAT::MsgUtils->message('S', "Purging nodes.");
    # For remove nodes, we should call 'nodemgmt' in front of 'noderm'
    setrsp_progress("Call kit node plugins.");
    my $warnstr = "";
    my $retref = xCAT::Utils->runxcmd({command=>["kitnoderemove"], node=>$nodes}, $request_command, 0, 1);
    my $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running kitnoderemove: $retstr");
    # runxcmd failed.
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to call some kit commands.");
        $warnstr = "Warning: failed to call command kitnoderemove. details: $retstr";
    }
    $retref = xCAT::Utils->runxcmd({command=>["kitnodefinished"], node=>$nodes}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running kitnodefinished: $retstr");
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to call some kit commands.");
        $warnstr = "Warning: failed to call command kitnodefinished. details: $retstr";
    }
    setrsp_progress("Call noderm to remove nodes.");
    $retref = xCAT::Utils->runxcmd({command=>["noderm"], node=>$nodes}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running noderm: $retstr");
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to call noderm to remove some nodes.");
        $warnstr = "Warning: failed to call command noderm to remove some nodes. details: $retstr";
    }
    setrsp_progress("Purge nodes success.");
    setrsp_success($nodes, $warnstr);
}

#-------------------------------------------------------

=head3  noderefresh

    Description : Re-Call kit plugins for node management
    Arguments   : N/A

=cut

#------------------------------------------------------
sub noderefresh
{
    my $nodes   = $request->{node};
    my $retref = xCAT::Utils->runxcmd({command=>["kitnoderefresh"], node=>$nodes}, $request_command, 0, 1);
    my $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running kitnoderefresh: $retstr");
    # runxcmd failed.
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to call some kit commands. Details: $retstr");
    }
    $retref = xCAT::Utils->runxcmd({command=>["kitnodefinished"], node=>$nodes}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running kitnodefinished: $retstr");
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to call some kit commands. Details: $retstr");
    }
    setrsp_success($nodes);
}

#-------------------------------------------------------

=head3  nodechprofile

    Description : Update node profiles: imageprofile, networkprofile and hardwareprofile.
    Arguments   : N/A

=cut

#-------------------------------------------------------
sub nodechprofile{
    my $nodes   = $request->{node};
    my %updated_groups;

    xCAT::MsgUtils->message('S', "Update nodes' profile settings.");
    # Parse arges.
    my $retstr = parse_args();
    if ($retstr){
        setrsp_errormsg($retstr);
        return;
    }
    # Make sure the specified parameters are valid ones.
    my @enabledparams = ('networkprofile', 'hardwareprofile', 'imageprofile');
    foreach my $argname (keys %args_dict){
        if (! grep{ $_ eq $argname} @enabledparams){
            setrsp_errormsg("Illegal attribute $argname specified.");
            return;
        }
    }

    # Get current templates for all nodes.
    setrsp_progress("Read database to get groups for all nodes.");
    my %groupdict;
    my $nodelstab = xCAT::Table->new('nodelist');
    my $nodeshashref = $nodelstab->getNodesAttribs($nodes, ['groups']);
    my %nodeshash = %$nodeshashref;
    my %updatenodeshash;
    foreach (keys %nodeshash){
        my @groups;
        my $attrshashref = $nodeshash{$_}[0];
        my %attrshash = %$attrshashref;
        # Update node's status to defined
        $updatenodeshash{$_}{'status'} = 'defined';
        # Update node's groups (profiles) info.
        if ($attrshash{'groups'}){
            @groups = split(/,/, $attrshash{'groups'});

            my $groupsref;
            # Replace the old template name with new specified ones in args_dict
            if(exists $args_dict{'networkprofile'}){
                $groupsref = replace_item_in_array(\@groups, "NetworkProfile", $args_dict{'networkprofile'});
            }
            if(exists $args_dict{'hardwareprofile'}){
                $groupsref = replace_item_in_array(\@groups, "HardwareProfile", $args_dict{'hardwareprofile'});
            }
            if(exists $args_dict{'imageprofile'}){
                $groupsref = replace_item_in_array(\@groups, "ImageProfile", $args_dict{'imageprofile'});
            }
            $updatenodeshash{$_}{'groups'} = join (',', @$groupsref);
        }
    }
    
    #update DataBase.
    setrsp_progress("Update database records.");
    my $nodetab = xCAT::Table->new('nodelist',-create=>1);
    $nodetab->setNodesAttribs(\%updatenodeshash);
    $nodetab->close();
    
    # call plugins
    setrsp_progress("Call nodemgmt plugins.");
    my $retref = xCAT::Utils->runxcmd({command=>["kitnodeupdate"], node=>$nodes}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running kitnodeupdate: $retstr");
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to call some kit commands. Details: $retstr");
    }

    $retref = xCAT::Utils->runxcmd({command=>["kitnodefinished"], node=>$nodes}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running kitnodefinished: $retstr");
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to call some kit commands. Details: $retstr");
    }
    setrsp_progress("Update node's profile success");
    setrsp_success($nodes);
}


#-------------------------------------------------------

=head3 nodeaddunmged

    Description : Create a node with hostname and ip address specified.
                  This node will belong to group "__Unmanaged".
                  Host file /etc/hosts will be updated automatically.
    Arguments   : N/A

=cut

#-------------------------------------------------------
sub nodeaddunmged
{
    xCAT::MsgUtils->message("Adding a unmanaged node.");
    # Parse arges.
    my $retstr = parse_args();
    if ($retstr){
        setrsp_errormsg($retstr);
        return;
    }

    # Make sure the specified parameters are valid ones.
    my @enabledparams = ('hostname', 'ip');
    foreach my $argname (keys %args_dict){
        if (! grep{ $_ eq $argname} @enabledparams){
            setrsp_errormsg("Illegal attribute $argname specified.");
            return;
        }
    }
    # Mandatory arguments.
    foreach (('hostname','ip')){
        if(! exists($args_dict{$_})){
            setrsp_errormsg("Mandatory parameter $_ not specified.");
            return;
        }
    }
    
    # validate the IP address
    my $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('ipmi', 'bmc');
    %allbmcips = %$recordsref;
    $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('hosts', 'ip');
    %allinstallips = %$recordsref;
    $recordsref = xCAT::NetworkUtils->get_all_nicips(1);
    %allips = %$recordsref;

    %allips = (%allips, %allbmcips, %allinstallips);

    if (exists $allips{$args_dict{'ip'}}){
        setrsp_errormsg("Specified IP address $args_dict{'ip'} conflicts with IPs in database");
        return;
    }elsif((xCAT::NetworkUtils->validate_ip($args_dict{'ip'}))[0][0] ){
        setrsp_errormsg("Specified IP address $args_dict{'ip'} is invalid");
        return;
    }elsif(xCAT::NetworkUtils->isReservedIP($args_dict{'ip'})){
        setrsp_errormsg("Specified IP address $args_dict{'ip'} is invalid");
        return;
    }

    # validate hostname.
    $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('nodelist', 'node');
    %allhostnames = %$recordsref;
    if (exists $allhostnames{$args_dict{'hostname'}}){
        setrsp_errormsg("Specified hostname $args_dict{'hostname'} conflicts with records in database");
        return;
    }
    if (! xCAT::NetworkUtils->isValidHostname($args_dict{'hostname'})){
        setrsp_errormsg("Specified hostname: $args_dict{'hostname'} is invalid");
        return;
    }

    # run nodeadd to create node records.
    my $retref = xCAT::Utils->runxcmd({command=>["nodeadd"], arg=>[$args_dict{"hostname"}, "groups=__Unmanaged", "hosts.ip=$args_dict{'ip'}"]}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running nodeadd: $retstr");
    if ($::RUNCMD_RC != 0){
        setrsp_errormsg("Failed to call nodeadd to create node. Details: $retstr");
        return;
    }
    $retref = xCAT::Utils->runxcmd({command=>["makehosts"], node=>[$args_dict{"hostname"}]}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running makehosts: $retstr");
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to call makehosts. Details: $retstr");
    }

    setrsp_infostr("Create unmanaged node success");
}

#-------------------------------------------------------

=head3 nodechmac

    Description : Change node's provisioning NIC's MAC address.
                  And then call kits plugins for nodes.
    Arguments   : N/A

=cut

#-------------------------------------------------------
sub nodechmac
{
    xCAT::MsgUtils->message("Replacing node's mac address.");
    # Parse arges.
    my $nodelist = $request->{node};
    my $hostname = $nodelist->[0];
    my $retstr = parse_args();
    if ($retstr){
        setrsp_errormsg($retstr);
        return;
    }

    # Make sure the specified parameters are valid ones.
    my @enabledparams = ('mac');
    foreach my $argname (keys %args_dict){
        if (! grep{ $_ eq $argname} @enabledparams){
            setrsp_errormsg("Illegal attribute $argname specified.");
            return;
        }
    }
    # Mandatory arguments.
    foreach (('mac')){
        if(! exists($args_dict{$_})){
            setrsp_errormsg("Mandatory parameter $_ not specified.");
            return;
        }
    }
    # Validate MAC address
    my $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('mac', 'mac');
    %allmacs = %$recordsref;
    foreach (keys %allmacs){
        my @hostentries = split(/\|/, $_);
        foreach my $hostandmac ( @hostentries){
            my ($macstr, $machostname) = split("!", $hostandmac);
            $allmacs{$macstr} = 0;
        }
    }
    if (exists $allmacs{$args_dict{"mac"}}){
        setrsp_errormsg("Specified MAC address $args_dict{'mac'} conflicts with MACs in database");
        return;
    } elsif(! xCAT::NetworkUtils->isValidMAC($args_dict{'mac'})){
        setrsp_errormsg("Specified MAC address $args_dict{'mac'} is invalid");
        return;
    }

    # Update database records.
    setrsp_progress("Updating database records");
    my $mactab = xCAT::Table->new('mac',-create=>1);
    $mactab->setNodeAttribs($hostname, {mac=>$args_dict{'mac'}});
    $mactab->close();

    # Call Plugins.
    setrsp_progress("Calling kit plugins");
    my $retref = xCAT::Utils->runxcmd({command=>["kitnodeupdate"], node=>[$hostname]}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running kitnodeupdate: $retstr");
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to call kit commands. Details: $retstr");
    }

    $retref = xCAT::Utils->runxcmd({command=>["kitnodefinished"], node=>[$hostname]}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running kitnodefinished: $retstr");
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to call kit commands. Details: $retstr");
    }
    setrsp_progress("Change node's mac success");
}

#-------------------------------------------------------

=head3 nodediscoverstart 

    Description : Start profiled nodes discovery. If already started, return a failure.
                  User should specify networkprofile, hardwareprofile, 
                  imageprofile, hostnameformat, rack, chassis, height and u so
                  that node's IP address will be generated automatcially 
                  according to networkprofile, node's hardware settings will
                  be set according to hardware profile, node's os settings will
                  be set according to image profile, node's hostname will be 
                  set according to hostnameformat and rank. And other node's 
                  attribs will also be set according to rack, chassis, height and u.
    Arguments   : N/A

=cut

#-------------------------------------------------------
sub nodediscoverstart{
    # Parse arges.
    xCAT::MsgUtils->message("Profiled nodes discovery started.");
    my $retstr = parse_args();
    if ($retstr){
        setrsp_errormsg($retstr);
        return;
    }

    my @enabledparams = ('networkprofile', 'hardwareprofile', 'imageprofile', 'hostnameformat', 'rank', 'rack', 'chassis', 'height', 'unit');
    foreach my $argname (keys %args_dict){
        if (! grep{ $_ eq $argname} @enabledparams){
            setrsp_errormsg("Illegal attribute $argname specified.");
            return;
        }
    }
    # mandatory arguments.
    foreach my $key ('networkprofile', 'imageprofile', 'hostnameformat'){
        if (! exists $args_dict{$key}){
            setrsp_errormsg("argument $key must be specified");
            return;
        }
    }

    my $recordsref = xCAT::ProfiledNodeUtils->get_all_rack(1);
    %allracks = %$recordsref;
    $recordsref =  xCAT::ProfiledNodeUtils->get_all_chassis(1);
    %allchassis = %$recordsref;
    # check rack
    if (exists $args_dict{'rack'}){
        if (! exists $allracks{$args_dict{'rack'}}){
            setrsp_errormsg("Specified rack $args_dict{'rack'} not defined");
            return;
        }
        # rack must be specified with chassis or unit + height.
        if (exists $args_dict{'chassis'}){
        } else{
            # We set default value for height and u if rack specified
            if(! exists $args_dict{'height'}){$args_dict{'height'} = 1}
            if(! exists $args_dict{'unit'}){$args_dict{'unit'} = 1}
        }
    }

    # chassis jdugement.
    if (exists $args_dict{'chassis'}){
        if (! exists  $args_dict{'rack'}){
            setrsp_errormsg("Argument chassis must be used together with rack");
            return;
        }

        if (! exists $allchassis{$args_dict{'chassis'}}){
            setrsp_errormsg("Specified chassis $args_dict{'chassis'} not defined");
            return;
        }
        if (exists $args_dict{'unit'} or exists $args_dict{'height'}){
            setrsp_errormsg("Argument chassis can not be specified together with unit or height");
            return;
        }
    }
   
    # height and u must be valid numbers.
    if (exists $args_dict{'unit'}){
        # Not a valid number.
        if (!($args_dict{'unit'} =~ /^\d+$/)){
            setrsp_errormsg("Specified unit $args_dict{'u'} is a invalid number");
            return;
        }
    }
    if (exists $args_dict{'height'}){
        # Not a valid number.
        if (!($args_dict{'height'} =~ /^\d+$/)){
            setrsp_errormsg("Specified height $args_dict{'height'} is a invalid number");
            return;
        }
    }

    # Read DB to confirm the discover is not started yet. 
    my @sitevalues = xCAT::TableUtils->get_site_attribute("__PCMDiscover");
    if ($sitevalues[0]){
        setrsp_errormsg("Profiled nodes discovery already started.");
        return;
    }

    # save discover args into table site.
    my $valuestr = "";
    foreach (keys %args_dict){
        if($args_dict{$_}){
            $valuestr .= "$_:$args_dict{$_},";
        }
    }

    my $sitetab = xCAT::Table->new('site',-create=>1);
    $sitetab->setAttribs({"key" => "__PCMDiscover"}, {"value" => "$valuestr"});
    $sitetab->close();
    setrsp_infostr("Profiled node's discover started");
}

#-------------------------------------------------------

=head3  nodediscoverstop

    Description : Stop profiled nodes auto discover. This action will remove the 
                  dababase flags.
    Arguments   : N/A

=cut

#------------------------------------------------------
sub nodediscoverstop{
    # Read DB to confirm the discover is started. 
    xCAT::MsgUtils->message("Stopping profiled node's discover.");
    my @sitevalues = xCAT::TableUtils->get_site_attribute("__PCMDiscover");
    if (! $sitevalues[0]){
        setrsp_errormsg("Profiled nodes discovery not started yet.");
        return;
    }

    # remove site table records: discover flag.
    my $sitetab=xCAT::Table->new("site");
    my %keyhash;
    $keyhash{'key'} = "__PCMDiscover";
    $sitetab->delEntries(\%keyhash);
    $sitetab->commit();
    
    # Update node's attributes, remove from gruop "__PCMDiscover".
    # we'll call rmdef so that node's groupinfo in table nodelist will be updated automatically.
    my @nodes = xCAT::NodeRange::noderange('__PCMDiscover');
    if (@nodes){
        # There are some nodes discvoered.
        my $retref = xCAT::Utils->runxcmd({command=>["rmdef"], arg=>["-t", "group", "-o", "__PCMDiscover"]}, $request_command, 0, 1);
    }
    setrsp_infostr("Profiled node's discover stopped");
}


#-------------------------------------------------------

=head3  nodediscoverstatus

    Description : Detect whether Profiled nodes discovery is running or not.
    Arguments   : N/A

=cut

#-------------------------------------------------------
sub nodediscoverstatus{
    my $discover_running = xCAT::ProfiledNodeUtils->is_discover_started();
    if($discover_running){
        setrsp_progress("Profiled nodes discover is running");
    }else{
        setrsp_progress("Profiled nodes discover not started");
    }
}

#-------------------------------------------------------

=head3  nodediscoverls

    Description : List all discovered profiled nodes.
    Arguments   : N/A

=cut

#-------------------------------------------------------
sub nodediscoverls{
    # Read DB to confirm the discover is started. 
    my @sitevalues = ();
    @sitevalues = xCAT::TableUtils->get_site_attribute("__PCMDiscover");
    if (! $sitevalues[0]){
        setrsp_errormsg("Profiled nodes discovery not started yet.");
        return;
    }

    my @nodes = xCAT::NodeRange::noderange('__PCMDiscover');
    my $mactab = xCAT::Table->new("mac");
    my $macsref = $mactab->getNodesAttribs(\@nodes, ['mac']);
    my $nodelisttab = xCAT::Table->new("nodelist");
    my $statusref = $nodelisttab->getNodesAttribs(\@nodes, ['status']);

    my $rspentry;
    my $i = 0;
    foreach (@nodes){
        if (! $_){
            next;
        }
        $rspentry->{node}->[$i]->{"name"} = $_;
        # Only get the MAC address of provisioning NIC.
        my @hostentries = split(/\|/, $macsref->{$_}->[0]->{"mac"});
        foreach my $hostandmac ( @hostentries){
            if (! $hostandmac){
                next;
            }
            if(index($hostandmac, "!")  == -1){
                $rspentry->{node}->[$i]->{"mac"} = $hostandmac;
                last;
            }
        }

        if ($statusref->{$_}->[0]){
            $rspentry->{node}->[$i]->{"status"} = $statusref->{$_}->[0]->{status};
        } else{
            $rspentry->{node}->[$i]->{"status"} = "defined";
        }
        $i++;
    }
    $callback->($rspentry);
}

#-------------------------------------------------------

=head3  findme

    Description : The default interface for node discovery. 
                  We must implement this method so that 
                  profiled nodes's findme request can be answered 
                  while profiled nodes discovery is running.
    Arguments   : N/A

=cut

#-------------------------------------------------------
sub findme{
    xCAT::MsgUtils->message('S', "Profield nodes discover: Start.\n");
    # Read DB to confirm the discover is started. 
    my @sitevalues = xCAT::TableUtils->get_site_attribute("__PCMDiscover");
    if (! @sitevalues){
        setrsp_errormsg("Profiled nodes discovery not started yet.");
        return;
    }

    # We store node profiles in site table, key is "__PCMDiscover"
    my @profilerecords = split(',', $sitevalues[0]);
    foreach (@profilerecords){
        if ($_){
            my ($profilename, $profilevalue) = split(':', $_);
            if ($profilename and $profilevalue){
                $args_dict{$profilename} = $profilevalue;
            }
        }
    }

    # Get database records: all hostnames, all ips, all racks...
    # To improve performance, we should initalize a daemon later??
    xCAT::MsgUtils->message('S', "Getting database records.\n");
    my $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('nodelist', 'node');
    %allhostnames = %$recordsref;
    $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('ipmi', 'bmc');
    %allbmcips = %$recordsref;
    $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('mac', 'mac');
    %allmacs = %$recordsref;
    foreach (keys %allmacs){
        my @hostentries = split(/\|/, $_);
        foreach my $hostandmac ( @hostentries){
            my ($macstr, $machostname) = split("!", $hostandmac);
            $allmacs{$macstr} = 0;
        }
    }
    $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('hosts', 'ip');
    %allinstallips = %$recordsref;
    $recordsref = xCAT::NetworkUtils->get_all_nicips(1);
    %allips = %$recordsref;
    # Merge all BMC IPs and install IPs into allips.
    %allips = (%allips, %allbmcips, %allinstallips);

    $recordsref = xCAT::ProfiledNodeUtils->get_all_rack(1);
    %allracks = %$recordsref;
    $recordsref =  xCAT::ProfiledNodeUtils->get_all_chassis(1);
    %allchassis = %$recordsref;

    # Get discovered client IP and MAC
    my $ip = $request->{'_xcat_clientip'};
    xCAT::MsgUtils->message('S', "Profield nodes discover: _xcat_clientip is $ip.\n");
    my $mac = '';
    my $arptable = `/sbin/arp -n`;
    my @arpents = split /\n/,$arptable;
    foreach  (@arpents) {
        if (m/^($ip)\s+\S+\s+(\S+)\s/) {
            $mac=$2;
            last;
        }
    }
    if (! $mac){
        setrsp_errormsg("Profiled nodes discover: Can not get mac address of this node.");
        return;
    }
    xCAT::MsgUtils->message('S', "Profiled nodes discover: mac is $mac.\n");
    if ( exists $allmacs{$mac}){
        setrsp_errormsg("Discovered MAC $mac already exists in database.");
        return;
    }

    # Assign TMPHOSTS9999 as a temporary hostname, in parse_hsots_string, 
    # it will detect this and arrange a real hostname for it.
    my $raw_hostinfo_str = "TMPHOSTS9999:\n  mac=$mac\n";
    # Append rack, chassis, unit, height into host info string.
    foreach my $key ('rack', 'chassis', 'unit', 'height'){
        if(exists($args_dict{$key})){
            $raw_hostinfo_str .= "  $key=$args_dict{$key}\n";
        }
    }
    if (exists $args_dict{'unit'} and exists $args_dict{'height'}){
        # increase start unit automatically.
        $args_dict{'unit'} = $args_dict{'unit'} + $args_dict{'height'};
        # save discover args into table site.
        my $valuestr = "";
        foreach (keys %args_dict){
            if($args_dict{$_}){
                $valuestr .= "$_:$args_dict{$_},";
            }
        }

        my $sitetab = xCAT::Table->new('site',-create=>1);
        $sitetab->setAttribs({"key" => "__PCMDiscover"}, {"value" => "$valuestr"});
        $sitetab->close();
    }


    my ($hostinfo_dict_ref, $invalid_records_ref) = parse_hosts_string($raw_hostinfo_str);
    my %hostinfo_dict = %$hostinfo_dict_ref;
    # Create the real hostinfo string in stanza file format.
    xCAT::MsgUtils->message('S', "Profiled nodes discover: Generating new hostinfo string.\n");
    my ($retcode_gen, $retstr_gen) = gen_new_hostinfo_string($hostinfo_dict_ref);
    unless ($retcode_gen){
        setrsp_errormsg($retstr_gen);
        return;
    }

    # call mkdef to create hosts and then call nodemgmt for node management plugins.
    xCAT::MsgUtils->message('S', "Call mkdef to create nodes.\n");
    my $retref = xCAT::Utils->runxcmd({command=>["mkdef"], stdin=>[$retstr_gen], arg=>['-z']}, $request_command, 0, 1);
    my $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running mkdef: $retstr");
    # runxcmd failed.
    if ($::RUNCMD_RC != 0){
        setrsp_errormsg($retstr_gen);
        return;
    }

    my @nodelist = keys %hostinfo_dict;
    xCAT::MsgUtils->message('S', "Call nodemgmt plugins.\n");
    $retref = xCAT::Utils->runxcmd({command=>["kitnodeadd"], node=>\@nodelist}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running kitnodeadd: $retstr");

    $retref = xCAT::Utils->runxcmd({command=>["kitnodefinished"], node=>\@nodelist}, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running kitnodefinished: $retstr");


    # call discover to notify client.
    xCAT::MsgUtils->message('S', "Call discovered request.\n");
    $request->{"command"} = ["discovered"];
    $request->{"node"} = \@nodelist;
    $retref = xCAT::Utils->runxcmd($request, $request_command, 0, 1);
    $retstr = get_cmd_return($retref);
    xCAT::MsgUtils->message('S', "The return message of running discovered: $retstr");
    # runxcmd failed.
    if ($::RUNCMD_RC != 0){
        xCAT::MsgUtils->message('S', "Warning: Failed to run command discovered for mac $mac. Details: $retstr");
    }

    # Set discovered flag.
    my $nodegroupstr = $hostinfo_dict{$nodelist[0]}{"groups"};
    my $nodelstab = xCAT::Table->new('nodelist',-create=>1);
    $nodelstab->setNodeAttribs($nodelist[0],{groups=>$nodegroupstr.",__PCMDiscover"});
    $nodelstab->close();
}

#-------------------------------------------------------

=head3  replace_item_in_array

    Description : Replace an item in a list with new value. This item should match specified pattern.
    Arguments   : arrayref - the list.
                  pattern - the pattern which the old item must match.
                  newitem - the updated value.
=cut

#-------------------------------------------------------
sub replace_item_in_array{
    my $arrayref = shift;
    my $pattern = shift;
    my $newitem = shift;

    my @newarray;
    foreach (@$arrayref){
        if ($_ =~ /__$pattern/){
            next;
        }
        push (@newarray, $_);
    }
    push(@newarray, $newitem);
    return \@newarray;
}

#-------------------------------------------------------

=head3  gen_new_hostinfo_string

    Description : Generate a stanza file format string used for 'mkdef' to create nodes.
    Arguments   : hostinfo_dict_ref - The reference of hostinfo dict.
    Returns     : (returnvalue, returnmsg)
                  returnvalue - 0, stands for generate new hostinfo string failed.
                                1, stands for generate new hostinfo string OK.
                  returnnmsg -  error messages if generate failed.
                             - the new hostinfo string if generate OK.
=cut

#-------------------------------------------------------
sub gen_new_hostinfo_string{
    my $hostinfo_dict_ref = shift;
    my %hostinfo_dict = %$hostinfo_dict_ref;

    # Get free ips list for all networks in network profile.
    my @allknownips = keys %allips;
    my $netprofileattrsref = xCAT::ProfiledNodeUtils->get_nodes_nic_attrs([$args_dict{'networkprofile'}])->{$args_dict{'networkprofile'}};
    my %netprofileattr = %$netprofileattrsref;
    my %freeipshash;
    foreach (keys %netprofileattr){
        my $netname = $netprofileattr{$_}{'network'};
        if($netname and (! exists $freeipshash{$netname})) {
            $freeipshash{$netname} = xCAT::ProfiledNodeUtils->get_allocable_staticips_innet($netname, \@allknownips);
        }
    }

    # Get networkprofile's installip
    my $noderestab = xCAT::Table->new('noderes');
    my $networkprofile = $args_dict{'networkprofile'};
    my $nodereshashref = $noderestab->getNodeAttribs($networkprofile, ['installnic']);
    my %nodereshash = %$nodereshashref;
    my $installnic = $nodereshash{'installnic'};

    # Get node's provisioning method
    my $provmethod = xCAT::ProfiledNodeUtils->get_imageprofile_prov_method($args_dict{'imageprofile'});

    # compose the stanza string for hostinfo file.
    my $hostsinfostr = "";
    foreach my $item (keys %hostinfo_dict){
        # Generate IPs for all interfaces.
        my %ipshash;
        foreach (keys %netprofileattr){
            my $netname = $netprofileattr{$_}{'network'};
            my $freeipsref;
            if ($netname){
                $freeipsref = $freeipshash{$netname};
            }
            my $nextip = shift @$freeipsref;
            if (!$nextip){
                return 0, "No sufficient IP address in network $netname for interface $_";
            }else{
                $ipshash{$_} = $nextip;
                $allips{$nextip} = 0;
            }
        }
        my $nicips = "";
        foreach(keys %ipshash){ 
            $nicips = "$_:$ipshash{$_},$nicips";
        }
        $hostinfo_dict{$item}{"nicips"} = $nicips;

        # Generate IP address if no IP specified.
        if (! exists $hostinfo_dict{$item}{"ip"}) {
            if (exists $ipshash{$installnic}){
                $hostinfo_dict{$item}{"ip"} = $ipshash{$installnic};
            }else{
                return 0, "No sufficient IP address for interface $installnic";
            }
        }
        $hostinfo_dict{$item}{"objtype"} = "node";
        $hostinfo_dict{$item}{"groups"} = "__Managed";
        if (exists $args_dict{'networkprofile'}){$hostinfo_dict{$item}{"groups"} .= ",".$args_dict{'networkprofile'}}
        if (exists $args_dict{'imageprofile'}){$hostinfo_dict{$item}{"groups"} .= ",".$args_dict{'imageprofile'}}
        if (exists $args_dict{'hardwareprofile'}){$hostinfo_dict{$item}{"groups"} .= ",".$args_dict{'hardwareprofile'}}
        
        # Update BMC records.
        if (exists $netprofileattr{"bmc"}){
            $hostinfo_dict{$item}{"mgt"} = "ipmi";
            $hostinfo_dict{$item}{"chain"} = 'runcmd=bmcsetup,'.$provmethod;

            if (exists $ipshash{"bmc"}){
                $hostinfo_dict{$item}{"bmc"} = $ipshash{"bmc"};
            } else{
                return 0, "No sufficient IP addresses for BMC";
            }
        } else{
            $hostinfo_dict{$item}{"chain"} = $provmethod;
        }
 
        # Generate the hostinfo string.
        $hostsinfostr = "$hostsinfostr$item:\n";
        my $itemdictref = $hostinfo_dict{$item};
        my %itemdict = %$itemdictref;
        foreach (keys %itemdict){
            $hostsinfostr = "$hostsinfostr  $_=\"$itemdict{$_}\"\n";
        }
    }
    return 1, $hostsinfostr;
}

#-------------------------------------------------------

=head3  read_and_generate_hostnames

    Description : Read hostinfo file and generate temporary hostnames for no-hostname specified ones.
    Arguments   : hostfile - the location of hostinfo file.
    Returns     : (returnvalue, returnmsg)
                  returnvalue - 0, stands for a failed return
                                1, stands for a success return
                  returnnmsg -  error messages for failed return.
                             -  the contents of the hostinfo string.
=cut

#-------------------------------------------------------
sub read_and_generate_hostnames{
    my $hostfile = shift;

    # Get 10000 temprary hostnames.
    my $freehostnamesref = xCAT::ProfiledNodeUtils->gen_numric_hostnames("TMPHOSTS","", 4);
    # Auto generate hostnames for "__hostname__" entries.
    open(HOSTFILE, $hostfile);
    my $filecontent = join("", <HOSTFILE>); 
    while ((index $filecontent, "__hostname__:") >= 0){
    	my $nexthost = shift @$freehostnamesref;
    	# no more valid hostnames to assign.
    	if (! $nexthost){
            return 1, "Can not generate hostname automatically: No more valid hostnames available .";
    	}
    	# This hostname already specified in hostinfo file.
    	if ((index $filecontent, "$nexthost:") >= 0){
            next;
    	}
        # This hostname should not in database.
        if (exists $allhostnames{$nexthost}){
            next;
        }
    	$filecontent =~ s/__hostname__/$nexthost/;
    }
    close(HOSTFILE);
    return 0, $filecontent;
}

#-------------------------------------------------------

=head3  parse_hosts_string
    
    Description : Parse the hostinfo string and validate it.
    Arguments   : filecontent - The content of hostinfo file.
    Returns     : (hostinfo_dict, invalid_records)
                  hostinfo_dict -  Reference of hostinfo dict. Key are hostnames and values is an attributes dict.
                  invalid_records - Reference of invalid records list.
=cut    
        
#-------------------------------------------------------
sub parse_hosts_string{
    my $filecontent = shift;
    my %hostinfo_dict;
    my @invalid_records;

    my $nameformat = $args_dict{'hostnameformat'};

    my $nameformattype = xCAT::ProfiledNodeUtils->get_hostname_format_type($nameformat);
    my %freehostnames;

    # Parse hostinfo file string.
    xCAT::DBobjUtils->readFileInput($filecontent);

    # Record duplicated items.
    # We should go through list @::fileobjnames first as  %::FILEATTRS is just a hash, 
    # it not tells whether there are some duplicated hostnames in the hostinfo string.
    my %hostnamedict;
    foreach my $hostname (@::fileobjnames){
        if (exists $hostnamedict{$hostname}){
            push @invalid_records, [$hostname, "Duplicated hostname defined"];
        } else{
            $hostnamedict{$hostname} = 0;
        }
    }
    # Verify each node entry.
    foreach (keys %::FILEATTRS){
        my $errmsg = validate_node_entry($_, $::FILEATTRS{$_});
        if ($errmsg) {
            if ($_=~ /^TMPHOSTS/){
                push @invalid_records, ["__hostname__", $errmsg];
            } else{
                push @invalid_records, [$_, $errmsg];
            }
            next;
        }

        # We need generate hostnames for this entry.
        if ($_=~ /^TMPHOSTS/)
        {
            # rack + numric hostname format, we must specify rack in node's definition.
            my $numricformat;
            # Need convert hostname format into numric format first.
            if ($nameformattype eq "rack"){
                if (! exists $::FILEATTRS{$_}{"rack"}){
                    push @invalid_records, ["__hostname__", "No rack info specified. Do specify it because the nameformat contains rack info."];
                    next;
                }
                $numricformat = xCAT::ProfiledNodeUtils->rackformat_to_numricformat($nameformat, $::FILEATTRS{$_}{"rack"});
            } else{
                # pure numric hostname format
                $numricformat = $nameformat;
            }

            # Generate hostnames based on numric hostname format.
            if (! exists $freehostnames{$numricformat}){
                my $rank = 0;
                if (exists($args_dict{'rank'})){
                    $rank = $args_dict{'rank'};
                }
                $freehostnames{$numricformat} = xCAT::ProfiledNodeUtils->genhosts_with_numric_tmpl($numricformat, $rank);
            }
            my $hostnamelistref = $freehostnames{$numricformat};
            my $nexthostname = shift @$hostnamelistref;
            while (exists $allhostnames{$nexthostname}){
                $nexthostname = shift @$hostnamelistref;
            }
            $hostinfo_dict{$nexthostname} = $::FILEATTRS{$_};
        } else{
            $hostinfo_dict{$_} = $::FILEATTRS{$_};
        }
    }
    return (\%hostinfo_dict, \@invalid_records);
}

#-------------------------------------------------------

=head3  validate_node_entry
    
    Description : Validate a node info hash.
    Arguments   : node_name - node hostname.
                  node_entry_ref - Reference of the node info hash.
    Returns     : errormsg
                      - undef: stands for no errror.
                      - valid string: stands for the error message of validation.    
=cut

#-------------------------------------------------------
sub validate_node_entry{
    my $node_name = shift;
    my $node_entry_ref = shift;
    my %node_entry = %$node_entry_ref;

    # duplicate hostname found in hostinfo file.
    if (exists $allhostnames{$node_name}) {
        return "Specified hostname $node_name conflicts with database records.";
    }
    # Must specify either MAC or switch + port.
    if (exists $node_entry{"mac"} || 
        exists $node_entry{"switch"} && exists $node_entry{"port"}){
    } else{
        return "Neither MAC nor switch + port specified";
    }

    if (! xCAT::NetworkUtils->isValidHostname($node_name)){
        return "Specified hostname: $node_name is invalid";
    }
    # validate each single value.
    foreach (keys %node_entry){
        if ($_ eq "mac"){
            if (exists $allmacs{$node_entry{$_}}){
                return "Specified MAC address $node_entry{$_} conflicts with MACs in database or hostinfo file";
            }elsif(! xCAT::NetworkUtils->isValidMAC($node_entry{$_})){
                return "Specified MAC address $node_entry{$_} is invalid";
            }else{
                $allmacs{$node_entry{$_}} = 0;
            }
        }elsif ($_ eq "ip"){
            if (exists $allips{$node_entry{$_}}){
                return "Specified IP address $node_entry{$_} conflicts with IPs in database or hostinfo file";
            }elsif((xCAT::NetworkUtils->validate_ip($node_entry{$_}))[0][0] ){
                return "Specified IP address $node_entry{$_} is invalid";
            }elsif(xCAT::NetworkUtils->isReservedIP($node_entry{$_})){
                return "Specified IP address $node_entry{$_} is invalid";
            }else {
                #push the IP into allips list.
                $allips{$node_entry{$_}} = 0;
            }
        }elsif ($_ eq "switch"){
            #TODO: xCAT switch discovery enhance: verify whether switch exists.
        }elsif ($_ eq "port"){
        }elsif ($_ eq "rack"){
            if (not exists $allracks{$node_entry{$_}}){
                return "Specified rack $node_entry{$_} not defined";
            }
            # rack must be specified with chassis or unit + height.
            if (exists $node_entry{"chassis"}){
            } elsif (exists $node_entry{"height"} and exists $node_entry{"unit"}){
            } else {
                return "Rack must be specified together with chassis or height + unit ";
            }
        }elsif ($_ eq "chassis"){
            if (not exists $allchassis{$node_entry{$_}}){
                return "Specified chassis $node_entry{$_} not defined";
            }
            # Chassis must not be specified with unit and height.
            if (exists $node_entry{"height"} or exists $node_entry{"unit"}){
                return "Chassis should not be specified together with height or unit";
            }
        }elsif ($_ eq "unit"){
            # Not a valid number.
            if (!($node_entry{$_} =~ /^\d+$/)){
                return "Specified unit $node_entry{$_} is a invalid number";
            }
        }elsif ($_ eq "height"){
            # Not a valid number.
            if (!($node_entry{$_} =~ /^\d+$/)){
                return "Specified height $node_entry{$_} is a invalid number";
            }
        }else{
           return "Invalid attribute $_ specified";
        }
    }
    # push hostinfo into global dicts.
    $allhostnames{$node_name} = 0;
    return undef;
}


#-------------------------------------------------------

=head3  setrsp_invalidrecords
    
    Description : Set response for processing invalid host records.
    Arguments   : recordsref - Refrence of invalid nodes list.

=cut

#-------------------------------------------------------
sub setrsp_invalidrecords
{
    my $recordsref =  shift;
    my $rsp;
    
    # The total number of invalid records.
    $rsp->{error} = "Some error records detected";
    $rsp->{errorcode} = 1;
    $rsp->{invalid_records_num} = scalar @$recordsref;

    # We write details of invalid records into a file.
    my ($fh, $filename) = xCAT::ProfiledNodeUtils->get_output_filename();
    foreach (@$recordsref){
    	my @erroritem = @$_;
        print $fh "nodename $erroritem[0], error: $erroritem[1]\n";
    }
    close $fh;
    #make it readable for http.
    system("chmod +r $filename");
    # Tells the URL of the details file.
    xCAT::MsgUtils->message('S', "Detailed response info placed in file: $filename\n");
    $rsp->{details} = $filename;
    $callback->($rsp);
}

#-------------------------------------------------------

=head3  setrsp_errormsg
    
    Description : Set response for error messages.
    Arguments   : errormsg - Error messages.

=cut

#-------------------------------------------------------
sub setrsp_errormsg
{
    my $errormsg = shift;
    my $rsp;
    xCAT::MsgUtils->message('S', "$errormsg\n");
    $rsp->{error} = $errormsg;
    $rsp->{errorcode} = 1;
    $callback->($rsp);
}

#-------------------------------------------------------

=head3  setrsp_infostr
    
    Description : Set response for a info string.
    Arguments   : infostr - The info string..

=cut

#-------------------------------------------------------
sub setrsp_infostr
{
    my $infostr = shift;
    my $rsp;
    xCAT::MsgUtils->message('S', "$infostr\n");
    $rsp->{data} = $infostr;
    $callback->($rsp);
}

#-------------------------------------------------------

=head3  setrsp_progress
    
    Description : Set response for running progress
    Arguments   : progress: the progress string.

=cut

#-------------------------------------------------------
sub setrsp_progress
{
    my $progress = shift;
    my $rsp;
    xCAT::MsgUtils->message('S', "$progress");
    $rsp->{info} = $progress;
    $callback->($rsp);
}



#-------------------------------------------------------

=head3  setrsp_success
    
    Description : Set response for successfully processed nodes.
    Arguments   : recordsref - Refrence of nodes list.

=cut

#-------------------------------------------------------
sub setrsp_success
{
    my $recordsref = shift;
    my $warnstr = shift;
    my $rsp;
    
    # The total number of success nodes.
    $rsp->{success_nodes_num} = scalar @$recordsref;
    my ($fh, $filename) = xCAT::ProfiledNodeUtils->get_output_filename();
    foreach (@$recordsref){
        print $fh "success: $_\n";
    }
    if ($warnstr){
        print $fh "There are some warnings:\n$warnstr\n";
    }
    close $fh;
    #make it readable for http.
    system("chmod +r $filename");
    # Tells the URL of the details file.
    xCAT::MsgUtils->message('S', "Detailed response info placed in file: $filename\n");
    $rsp->{details} = $filename;
    $callback->($rsp);
}

#-----------------------------------------------------
=head3  get_cmd_return

    Description : Get return of runxcmd and compose a string.
    Arguments   : The return reference of runxcmd

=cut

#-----------------------------------------------------
sub get_cmd_return
{
    my $return = shift;
    my $returnmsg = ();
    if ($return){
        foreach (@$return){
            $returnmsg .= "$_\n";
        }
    }
    return $returnmsg;
}

1;
