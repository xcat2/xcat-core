# IBM(c) 2012 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1

    xCAT plugin to support Profiled nodes management
    
=cut

#-------------------------------------------------------
package xCAT_plugin::profilednodes;

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case);
use Data::Dumper;
require xCAT::Table;
require xCAT::Utils;
require xCAT::TableUtils;
require xCAT::NetworkUtils;
require xCAT::MsgUtils;
require xCAT::ProfiledNodeUtils;

# Globals.
# These 2 global variables are for storing the parse result of hostinfo file.
# These 2 global varialbes are set in lib xCAT::ProfiledNodeUtils->parse_nodeinfo_file.
#%::profiledNodeAttrs;
#@::profiledNodeObjNames;

# All database records.
my %allhostnames;
my %allbmcips;
my %allmacs;
my %allmacsupper;
my %allips;
my %allinstallips;
my %allnicips;
my %allracks;
my %allchassis;
my %allswitches;
my %all_switchports;

# The array of all chassis which is special CMM 
my %allcmmchassis;
my %allothernics;

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
        noderegenips => 'profilednodes',
        noderefresh =>  'profilednodes',
        nodediscoverstart => 'profilednodes',
        nodediscoverstop => 'profilednodes',
        nodediscoverls => 'profilednodes',
        #nodediscoverstatus => 'profilednodes',
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

    # There is no need to acquire lock for command nodediscoverstatus, nodediscoverls and noderegenips.
    if ($command eq "nodediscoverstatus"){
        nodediscoverstatus();
        return;
    } elsif ($command eq "nodediscoverls"){
        nodediscoverls();
        return;
    } elsif ($command eq "noderegenips"){
        noderegenips();
        return;
    }

    my $lock = xCAT::Utils->acquire_lock("nodemgmt", 1);
    if (! $lock){
        setrsp_errormsg("Cannot acquire lock, another process is already running.");
        return;
    }

    # These commands should make sure no discover is running.
    if (grep{ $_ eq $command} ("nodeimport", "nodepurge", "nodechprofile", "nodeaddunmged", "nodechmac")){
        my $discover_running = xCAT::ProfiledNodeUtils->is_discover_started();
        if ($discover_running){
            my %errormsg_dict = (
                'nodeimport' => 'import nodes',
                'nodepurge' => 'remove nodes',
                'nodechprofile' => 'change profiles',
                'nodeaddunmged' => 'add devices',
                'nodechmac' => 'change MAC address'
            );  
                
            setrsp_errormsg("Cannot $errormsg_dict{$command} while node discovery is running.");
            xCAT::Utils->release_lock($lock, 1);
            return;
        }
    }
	
    if ($command eq "nodeimport"){
        nodeimport();
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
    } elsif ($command eq "findme"){
        findme();
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
    %args_dict = ();
    foreach my $arg (@ARGV){
        my @argarray = split(/=/,$arg);
        my $arglen = @argarray;
        if ($arglen > 2){
            return "Illegal argument $arg specified.";
        }

        # translate the profile names into real group names in db.
        if($argarray[1])
        {
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
    }
    return undef;
}

sub validate_args{
    my $helpmsg = shift;
    my $enabledparamsref = shift;
    my $mandatoryparamsref = shift;

    # The -h -v are handled by seqdiscovery.pm
    # -t -u -l only works for nodediscoverls, and them only handled by seqdiscovery.pm
    my ($help, $ver, $type, $uuid, $long);

    @ARGV = ();
    if($args) {
        @ARGV = @$args;
    }
    GetOptions(
        'h|help' => \$help,
        'v|version' => \$ver,
        't=s' => \$type,
        'u=s' => \$uuid,
        'l' => \$long,
    );

    if($help){
        # just return to make sequential discovery to handle it
        return 0;
    }

    if($ver){
        # just return to make sequential discovery to handle it
        return 0;
    }

    if ($type || $uuid || $long) {
        # these args for general discovery, return directly
        return 0;
    }
    
    my $parseret = parse_args();
    if ($parseret){
        setrsp_errormsg($parseret);
        return 0;
    }

    # If specified the nodrange= arg, we asume that the sequential discovery will be started
    if (defined $args_dict{'noderange'}) {
        # This is a sequential discovery request, just return to make sequential to handle it
        return 0;
    }

    # Mandatory arguments.
    my @mandatoryparams = ();
    if ($mandatoryparamsref){
        @mandatoryparams = @$mandatoryparamsref;
    }

    if (@mandatoryparams) {
        my $profiledis;
        foreach (@mandatoryparams){
            if (exists($args_dict{$_})) {
                # this is for profile discovery
                $profiledis = 1;
                last;
            }
        }
        unless ($profiledis) {
            # Not see the nodrange and 'networkprofile', 'imageprofile', 'hostnameformat'
            # return to make sequential discovery to display help message
            return 0;
        }
    }
    
    foreach (@mandatoryparams){
        if(! exists($args_dict{$_})){
            setrsp_errormsg("For profile discovery, the $_ option must be specified.");
            setrsp_infostr($helpmsg);
            return 0;
        }
    }
    
    # Make sure the specified parameters are valid ones.
    my @enabledparams = ();
    if($enabledparamsref){
        @enabledparams = @$enabledparamsref;
    }
    
    foreach my $argname (keys %args_dict){
        if (! grep{ $_ eq $argname} @enabledparams){
            setrsp_errormsg("Illegal attribute $argname specified.");
            setrsp_infostr($helpmsg);
            return 0;
        }
    }



    return 1;
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

    my $helpmsg = "nodeimport: create profiled nodes by importing hostinfo file.
Usage: 
\tnodeimport file=<hostinfo file> networkprofile=<networkprofile> imageprofile=<imageprofile> hostnameformat=<hostnameformat> [hardwareprofile=<hardwareprofile>] [groups=<groups>]
\tnodeimport [-h|--help] 
\tnodeimport {-v|--version}";

    my @enabledparams = ('file', 'groups', 'networkprofile', 'hardwareprofile', 'imageprofile', 'hostnameformat');
    my @mandatoryparams = ('file','networkprofile', 'imageprofile', 'hostnameformat');

    my $ret = validate_args($helpmsg, \@enabledparams, \@mandatoryparams);
    if (! $ret){
        return;
    }

    if(! (-e $args_dict{'file'})){
        setrsp_errormsg("Node information file does not exist.");
        return;
    }

    # validate hostnameformat:
    my $nameformattype = xCAT::ProfiledNodeUtils->get_hostname_format_type($args_dict{'hostnameformat'});
    if ($nameformattype eq "unknown"){
        setrsp_errormsg("Invalid node name format: $args_dict{'hostnameformat'}");
        return;
    }
    
    # Validate if profile consistent
    my $imageprofile = $args_dict{'imageprofile'};
    my $networkprofile = $args_dict{'networkprofile'};
    my $hardwareprofile = $args_dict{'hardwareprofile'};
    my ($returncode, $errmsg) = xCAT::ProfiledNodeUtils->check_profile_consistent($imageprofile, $networkprofile, $hardwareprofile);
    if (not $returncode) {
        setrsp_errormsg($errmsg);
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
    
    # Get all FSP ip address
    $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('ppc', 'hcp');
    my %allfspips = %$recordsref;

    # Get all switches name
    $recordsref = xCAT::ProfiledNodeUtils->get_db_switches();
    %allswitches = %$recordsref;

    # Get all switches_switchport
    $recordsref = xCAT::ProfiledNodeUtils->get_db_switchports();
    %all_switchports = %$recordsref;

    # MAC records looks like: "01:02:03:04:05:0E!node5.01:02:03:05:0F!node6-eth1". We want to get the real mac addres.
    foreach (keys %allmacs){
        my @hostentries = split(/\|/, $_);
        foreach my $hostandmac ( @hostentries){
            my ($macstr, $machostname) = split("!", $hostandmac);
            $allmacs{$macstr} = 0;
        }
    }
    %allmacsupper = ();
    foreach (keys %allmacs){
            $allmacsupper{uc($_)} = 0;
    }

    $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('hosts', 'ip');
    %allinstallips = %$recordsref;
    $recordsref = xCAT::NetworkUtils->get_all_nicips(1);
    %allips = %$recordsref;

    # Merge all BMC IPs and install IPs into allips.
    %allips = (%allips, %allbmcips, %allinstallips, %allfspips);

    #TODO: can not use getallnode to get rack infos.
    $recordsref = xCAT::ProfiledNodeUtils->get_all_rack(1);
    %allracks = %$recordsref;
    $recordsref =  xCAT::ProfiledNodeUtils->get_all_chassis(1);
    %allchassis = %$recordsref;
    $recordsref =  xCAT::ProfiledNodeUtils->get_all_chassis(1,'cmm');
    %allcmmchassis = %$recordsref;

    # Generate temporary hostnames for hosts entries in hostfile. 
    xCAT::MsgUtils->message('S', "Generate temporary hostnames.");
    my ($retcode_read, $retstr_read) = read_and_generate_hostnames($args_dict{'file'});
    if ($retcode_read != 0){
        setrsp_progress("Failed to validate node information file.");
        setrsp_errormsg($retstr_read);
        return;
    }
    my ($parse_ret, $parse_str) = xCAT::ProfiledNodeUtils->parse_nodeinfo_file($retstr_read);
    if (! $parse_ret){
        setrsp_progress("Failed to validate node information file.");
        setrsp_errormsg($parse_str);
        return;
    }

    my $mac_addr_mode = 0;
    my $switch_mode = 0;
    # Parse and validate the hostinfo string. The real hostnames will be generated here.
    xCAT::MsgUtils->message('S', "Parsing hostinfo string and validate it.");
    my ($hostinfo_dict_ref, $invalid_records_ref) = validate_node_entries();
    my %hostinfo_dict = %$hostinfo_dict_ref;
    my @invalid_records = @$invalid_records_ref;
    if (@invalid_records){
        setrsp_progress("Failed to validate node information file.");
        setrsp_invalidrecords(\@invalid_records);
        return;
    }
    unless (%hostinfo_dict){
        setrsp_progress("Failed to validate node information file.");
        setrsp_errormsg("Cannot find node records in node information file.");
        return;
    }

    # if user specified the switch, we need to add a new item into switch table
    my @nodelist = keys %hostinfo_dict;
    foreach my $mynode (@nodelist)
    {
        if(defined($hostinfo_dict{$mynode}{'mac'}))
        {
            $mac_addr_mode = 1;
        }
        if(defined($hostinfo_dict{$mynode}{'switch'}))
        {
            $switch_mode = 1;
        }
        # cannot mix switch discovery with mac import
        if(($mac_addr_mode == 1) && ($switch_mode == 1))
        {
            setrsp_progress("Failed to validate node information file.");
            setrsp_errormsg("Cannot define mac import node in switch discovery hostinfo file.");
            return;
        }
    }

    # Create the real hostinfo string in stanza file format.
    xCAT::MsgUtils->message('S', "Generating new hostinfo string.");
    my ($retcode_gen, $retstr_gen) = gen_new_hostinfo_string(\%hostinfo_dict);
    unless ($retcode_gen){
        setrsp_progress("Failed to validate node information file.");
        setrsp_errormsg($retstr_gen);
        return;
    }
    # call mkdef to create hosts and then call nodemgmt for node management plugins.
    setrsp_progress("Importing nodes...");
    setrsp_progress("Creating nodes...");
    my $warnstr = "";
    my $retref = xCAT::Utils->runxcmd({command=>["mkdef"], stdin=>[$retstr_gen], arg=>['-z']}, $request_command, 0, 2);
    my $retstrref = parse_runxcmd_ret($retref);
    # runxcmd failed.
    if ($::RUNCMD_RC != 0){
        $warnstr = "Warning: failed to import some nodes.";
        setrsp_progress($warnstr); 
        if ($retstrref->[1]) {
            $warnstr .= "Details: $retstrref->[1]";
        }
    }

    setrsp_progress("Configuring nodes...");
    $retref = xCAT::Utils->runxcmd({command=>["kitnodeadd"], node=>\@nodelist, sequential=>[1], macflag=>[$mac_addr_mode]}, $request_command, 0, 2);
    $retstrref = parse_runxcmd_ret($retref);
    if ($::RUNCMD_RC != 0){
        $warnstr .= "Warning: failed to run command kitnodeadd.";
        if ($retstrref->[1]) {
            $warnstr .= "Details: $retstrref->[1]";
        }
    }

    setrsp_progress("Imported nodes.");
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
    my $helpmsg = "nodepurge: Removes nodes from database and system configuration.
Usage: 
\tnodepurge <noderange>
\tnodepurge [-h|--help] 
\tnodepurge {-v|--version}";

    my $ret = validate_args($helpmsg);
    if (! $ret){
        return;
    }
    if (! $nodes){
        setrsp_infostr($helpmsg);
        return;
    }

    xCAT::MsgUtils->message('S', "Purging nodes.");
    # For remove nodes, we should call 'nodemgmt' in front of 'noderm'
    setrsp_progress("Configuring nodes...");

    my $warnstr = "";
    my $retref = xCAT::Utils->runxcmd({command=>["kitnoderemove"], node=>$nodes, sequential=>[1]}, $request_command, 0, 2);
    my $retstrref = parse_runxcmd_ret($retref);
    # runxcmd failed.
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to call kitnoderemove command.");
        $warnstr .= "Warning: failed to call kitnoderemove command.";
        if ($retstrref->[1]) {
            $warnstr .= "Details: $retstrref->[1]";
        }
    }

    setrsp_progress("Updating DNS entries");
    $retref = xCAT::Utils->runxcmd({command=>["makedns"], node=>$nodes, arg=>['-d']}, $request_command, 0, 2);

    setrsp_progress("Updating hosts entries");
    $retref = xCAT::Utils->runxcmd({command=>["makehosts"], node=>$nodes, arg=>['-d']}, $request_command, 0, 2);

    setrsp_progress("Removing nodes...");
    $retref = xCAT::Utils->runxcmd({command=>["noderm"], node=>$nodes}, $request_command, 0, 2);
    $retstrref = parse_runxcmd_ret($retref);
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: Cannot remove all nodes. The noderm command failed to remove some of the nodes.");
        $warnstr .= "Warning: Cannot remove all nodes. The noderm command failed to remove some of the nodes.";
        if ($retstrref->[1]) {
            $warnstr .= "Details: $retstrref->[1]";
        }
    }
    setrsp_progress("Removed all nodes.");
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
    my $helpmsg = "noderefresh: Calls kit plugins for the nodes in the profile.
Usage: 
\tnoderefresh <noderange>
\tnoderefresh [-h|--help] 
\tnoderefresh {-v|--version}";

    if (! $nodes){
        setrsp_infostr($helpmsg);
        return;
    }
    my $ret = validate_args($helpmsg);
    if (! $ret){
        return;
    }

    my $retref = xCAT::Utils->runxcmd({command=>["kitnoderefresh"], node=>$nodes, sequential=>[1]}, $request_command, 0, 2);
    my $retstrref = parse_runxcmd_ret($retref);
    # runxcmd failed.
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: Failed to call kit commands.");
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
    my $helpmsg = "nodechprofile: Update node profiles for profiled nodes.
Usage: 
\tnodechprofile <noderange> [networkprofile=<networkprofile>] [imageprofile=<imageprofile>] [hardwareprofile=<hardwareprofile>]
\tnodechprofile [-h|--help] 
\tnodechprofile {-v|--version}"; 
    if (! $nodes){
        setrsp_infostr($helpmsg);
        return;
    }

    my @enabledparams = ('networkprofile', 'hardwareprofile', 'imageprofile');
    my $ret = validate_args($helpmsg, \@enabledparams);
    if (! $ret){
        return;
    }

    xCAT::MsgUtils->message('S', "Update nodes' profile settings.");
    # Get current templates for all nodes.
    setrsp_progress("Getting all node groups from the database...");
    my %groupdict;
    my $nodelstab = xCAT::Table->new('nodelist');
    my $nodeshashref = $nodelstab->getNodesAttribs($nodes, ['groups']);
    my %updatenodeshash;

    my %nodeoldprofiles = ();
    foreach (@$nodes){
        my %nodecurrprofiles = ();
        
        # Get each node's profiles.
        my $groupsstr = $nodeshashref->{$_}->[0]->{'groups'};
        unless ($groupsstr){
            setrsp_errormsg("node $_ does not have any profiles, can not change its profiles.");
            return;
        }
        my @groups = split(/,/, $groupsstr);
        foreach my $group (@groups){
            if ($group =~ /__ImageProfile/){
                $nodecurrprofiles{'imageprofile'} = $group;
            }elsif ($group =~ /__NetworkProfile/){
                $nodecurrprofiles{'networkprofile'} = $group;
            }elsif ($group =~ /__HardwareProfile/){
                $nodecurrprofiles{'hardwareprofile'} = $group;
            }else{
                $nodecurrprofiles{'groups'} .= $group.",";
            }
        }
        # initialize node old profiles.
        unless (%nodeoldprofiles){
            $nodeoldprofiles{'imageprofile'} = $nodecurrprofiles{'imageprofile'};
            $nodeoldprofiles{'networkprofile'} = $nodecurrprofiles{'networkprofile'};
            $nodeoldprofiles{'hardwareprofile'} = $nodecurrprofiles{'hardwareprofile'};
        }
        # Make sure whether all nodes having same profiles.
        if($nodeoldprofiles{'imageprofile'} ne $nodecurrprofiles{'imageprofile'}){
            setrsp_errormsg("node $_ does not have same imageprofile with other nodes.");
            return;
        } elsif ($nodeoldprofiles{'hardwareprofile'} ne $nodecurrprofiles{'hardwareprofile'}){
            setrsp_errormsg("node $_ does not have same hardwareprofile with other nodes.");
            return;
        } elsif ($nodeoldprofiles{'networkprofile'} ne $nodecurrprofiles{'networkprofile'}){
            setrsp_errormsg("node $_ does not have same networkprofile with other nodes.");
            return;
        }

        # Replace the old profiles name with new specified ones in args_dict
        if ($nodecurrprofiles{'groups'}){
            $updatenodeshash{$_}{'groups'} = $nodecurrprofiles{'groups'};
        }
    }
    
    # After checking, all nodes' profile should be same
    # Get the new profile with specified ones in args_dict
    my $changeflag = 0;
    my $profile_groups;
    my $profile_status;
    if(exists $args_dict{'networkprofile'}){
        $profile_groups .= $args_dict{'networkprofile'}.",";
        if ($args_dict{'networkprofile'} ne $nodeoldprofiles{'networkprofile'}){
            $changeflag = 1;
        }else{
            xCAT::MsgUtils->message('S', "Specified networkprofile is same with current value, ignore.");
            delete($args_dict{'networkprofile'});
        }
    }
    if(exists $args_dict{'hardwareprofile'}){
        $profile_groups .= $args_dict{'hardwareprofile'}.",";
        if ($args_dict{'hardwareprofile'} ne $nodeoldprofiles{'hardwareprofile'}){
            $profile_status = 'defined';
            $changeflag = 1;
        }else{
            xCAT::MsgUtils->message('S', "Specified hardwareprofile is same with current value, ignore.");
            delete($args_dict{'hardwareprofile'});
        }
    }
    if(exists $args_dict{'imageprofile'}){
        $profile_groups .= $args_dict{'imageprofile'}.",";
        if ($args_dict{'imageprofile'} ne $nodeoldprofiles{'imageprofile'}){
            $profile_status = 'defined';
            $changeflag = 1;
        }else{
            xCAT::MsgUtils->message('S', "Specified imageprofile is same with current value, ignore.");
            delete($args_dict{'imageprofile'});
        }
    }
    # make sure there are something changed, otherwise we should quit without any changes.
    unless ($changeflag){
        setrsp_errormsg("No profile changes detect.");
        return;
    }
    
    # Update nodes' attributes
    foreach (@$nodes) {
        $updatenodeshash{$_}{'groups'} .= $profile_groups;
        if ($profile_status){
            $updatenodeshash{$_}{'status'} = $profile_status;
        }
    }    
    
    #update DataBase.
    setrsp_progress("Updating database records...");
    my $nodetab = xCAT::Table->new('nodelist',-create=>1);
    $nodetab->setNodesAttribs(\%updatenodeshash);
    $nodetab->close();

    my $retref;
    my $retstrref;
    # Call update plugins first.
    if(exists $args_dict{'hardwareprofile'} || exists $args_dict{'imageprofile'}){
        setrsp_progress("Configuring nodes...");
        $retref = xCAT::Utils->runxcmd({command=>["kitnodeupdate"], node=>$nodes, sequential=>[1]}, $request_command, 0, 2);
        $retstrref = parse_runxcmd_ret($retref);
        if ($::RUNCMD_RC != 0){
            setrsp_progress("Warning: failed to call kit commands.");
        }
    }

    # If network profile specified. Need re-generate IPs for all nodess again.
    if(exists $args_dict{'networkprofile'}){
        setrsp_progress("Regenerate IP addresses for nodes...");
        $retref = xCAT::Utils->runxcmd({command=>["noderegenips"], node=>$nodes, sequential=>[1]}, $request_command, 0, 2);
        $retstrref = parse_runxcmd_ret($retref);
        if ($::RUNCMD_RC != 0){
            setrsp_progress("Warning: failed to generate IPs for nodes.");
        }
    }
    
    setrsp_progress("Updated the image/network/hardware profiles used by nodes.");
    setrsp_success($nodes);
}

#------------------------------------------------------

=head3 noderegenips

  Description: Re-generate IPs automatically for specified nodes.
               All these nodes must be in same networkprofile.
               If no nics specified, then re-generate IP all nics in the networkprofile.

=cut
#-----------------------------------------------------
sub noderegenips
{
    my $nodes   = $request->{node};
    my $helpmsg = "noderegenips: Regenerate nodes IP addresses.
Usage:
\tnoderegenips <noderange> [nics=<eth0,eth1...>] 
\tnoderegenips [-h|--help]
\tnoderegenips {-v|--version}";
    if (! $nodes){
        setrsp_infostr($helpmsg);
        return;
    }
    my @enabledparams = ('nics');
    my $ret = validate_args($helpmsg, \@enabledparams);
    if (! $ret){
        return;
    }

    my @updateNics = ();
    my @removedNics = ();
    my $netProfileName = '';
    my $netProfileNicsRef;
    my %freeIPsHash = ();
    # nicipsAttr and ipAttr are for storing node's nicips and ip attribute
    my %nicipsAttr = ();
    my %ipAttr = ();
    my $installnic = '';
    xCAT::MsgUtils->message('S', "Start running noderegenips.");
    #1. Validate all nodes have same network profile.  networkprofile.
    my $nodesProfilesRef = xCAT::ProfiledNodeUtils->get_nodes_profiles($nodes);
    foreach my $node (keys %$nodesProfilesRef){
        unless( $nodesProfilesRef->{$node}->{NetworkProfile} ){
            setrsp_errormsg("Node $node does not have a network profile.");
            return;
        }
        unless( $netProfileName ){
            $netProfileName = "__NetworkProfile_".$nodesProfilesRef->{$node}->{NetworkProfile};
            next;
        }
        if ("__NetworkProfile_".$nodesProfilesRef->{$node}->{NetworkProfile} ne $netProfileName){
            setrsp_errormsg("Node $node has a different network profile with other nodes.");
            return;
        }
    }
    #2. Get network profile nics settings. 
    $netProfileNicsRef = xCAT::ProfiledNodeUtils->get_nodes_nic_attrs([$netProfileName]);
    my $nicsref = $netProfileNicsRef->{$netProfileName};
    my @nicslist = keys %$nicsref;
    #3. validate specified nics 
    if(exists $args_dict{'nics'}){
        @updateNics = split(",", $args_dict{'nics'});
    }
    foreach (@updateNics){
        unless ($netProfileNicsRef->{$netProfileName}->{$_}){
            # We want to remove this nic from these nodes.
            push(@removedNics, $_);
        }
    }
    unless (@updateNics){
        @updateNics = @nicslist;
    }
    # get install nic for these nodes.
    my $restab = xCAT::Table->new('noderes');
    my $installnicattr = $restab->getNodeAttribs($netProfileName, ['installnic']);
    $installnic = $installnicattr->{'installnic'};

    #4. get all node's current database nics settings.
    my $nodesNicsRef = xCAT::ProfiledNodeUtils->get_nodes_nic_attrs($nodes);

    my $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('ipmi', 'bmc');
    %allbmcips = %$recordsref;
    $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('hosts', 'ip');
    %allinstallips = %$recordsref;
    $recordsref = xCAT::NetworkUtils->get_all_nicips(1);
    %allips = %$recordsref;
    $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('ppc', 'hcp');
    my %allfspips = %$recordsref;
    %allips = (%allips, %allbmcips, %allinstallips, %allfspips);

    #5. free currently used IPs for all nodes. 
    foreach my $node (@$nodes){
        foreach my $nicname (@updateNics){
            my $nicip = $nodesNicsRef->{$node}->{$nicname}->{"ip"};
            if ($nicip){
                delete($allips{$nicip});
            }
        }
    }

    #6. Generate new free IPs for each network.
    my @allknownips = keys %allips;
    foreach my $updnic (@updateNics){
        #No need generate for removed nics.
        unless (grep {$_ eq $updnic} @removedNics){
            my $netname = $netProfileNicsRef->{$netProfileName}->{$updnic}->{"network"};
            $freeIPsHash{$updnic} = xCAT::ProfiledNodeUtils->get_allocable_staticips_innet($netname, \@allknownips);
        }
    }
    
    #7. Assign new free IPs for nodes and generate nicips and hosts attribute.
    my %bmcipsAttr = {};
    my %fspipsAttr = {};
    my $provision_flag = 0;
    my $bmc_flag = 0;
    my $fsp_flag = 0;
    foreach my $node (@$nodes){
        foreach my $nicname (@nicslist){
            # Remove records from nicips for removed nics.
            if (grep {$_ eq $nicname} @removedNics){
                next;
            }

            unless (grep {$_ eq $nicname} @updateNics){
                # if the nic not specified, just keep the old IP&NIC record in nics table.
                my $oldip = $nodesNicsRef->{$node}->{$nicname}->{"ip"};
                $nicipsAttr{$node}{nicips} .= $nicname."!".$oldip.",";
            }else{
                my $ipsref = $freeIPsHash{$nicname};
                my $nextip = shift @$ipsref;
                unless ($nextip){
                    setrsp_errormsg("There are no more IP addresses available in the static network range for nic $nicname.");
                    return;
                }
                $nicipsAttr{$node}{nicips} .= $nicname."!".$nextip.",";
                if ($installnic eq $nicname){
                    $provision_flag = 1;
                    $ipAttr{$node}{ip} = $nextip;
                }elsif ($nicname eq 'bmc'){
                    $bmc_flag = 1;
                    $bmcipsAttr{$node}{"bmc"} = $nextip;
                }elsif ($nicname eq 'fsp'){
                    $fsp_flag = 1;
                    $fspipsAttr{$node}{"hcp"} = $nextip;
                }
            }
        }
    }

    #8. Update database.
    setrsp_progress("Updating database records...");
    my $nicstab = xCAT::Table->new('nics',-create=>1);
    $nicstab->setNodesAttribs(\%nicipsAttr);
    $nicstab->close();
    
    # Update hosts table if provisioning NIC ip change
    if ($provision_flag) {
        my $hoststab = xCAT::Table->new('hosts', -create=>1);
        $hoststab->setNodesAttribs(\%ipAttr);
        $hoststab->close();
    }
    # Update ipmi table if bmc NIC ip change
    if ($bmc_flag) {
        my $ipmitab = xCAT::Table->new('ipmi',-create=>1);
        $ipmitab->setNodesAttribs(\%bmcipsAttr);
        $ipmitab->close();
    }
    # Update ppc table if fsp NIC ip change
    if ($fsp_flag) {
        my $ppctab = xCAT::Table->new('ppc',-create=>1);
        $ppctab->setNodesAttribs(\%fspipsAttr);
        $ppctab->close();
    }
    
    #9. If provisioning NIC ip or BMC ip changed for nodes, update chain table
    # If FSP ip changed for nodes, push the new ip to fsp and establish hardware connection
    my @kitcommands = ();
    if ( $provision_flag or  $bmc_flag) {
        #Get node's provmethod. 
        my $nodetypetab = xCAT::Table->new('nodetype');
        my $firstnode = $nodes->[0];
        my $records = $nodetypetab->getNodeAttribs($firstnode, ['node', 'provmethod']);
        my $imgname = $records->{provmethod};
        
        my $chainstr = "osimage=$imgname";
        if ( $bmc_flag ) {
           $chainstr = "runcmd=bmcsetup,osimage=$imgname:reboot4deploy";
        }
        
        # Update chain table
        my %chainAttr = {};
        foreach my $node (@$nodes){
            $chainAttr{$node}{'chain'} = $chainstr;
        }
        my $chaintab = xCAT::Table->new('chain', -create=>1);
        $chaintab->setNodesAttribs(\%chainAttr);
        $chaintab->close();
        
        # Remove all nodes information
        push(@kitcommands, "removenodes");
        # Add all nodes information back
        push(@kitcommands, "kitnodeadd");  
        
    } elsif ( $fsp_flag ) {
        # Remove all nodes information
        push(@kitcommands, "removenodes");
        # Add all nodes information back
        push(@kitcommands, "kitnodeadd");
    } else {
        push(@kitcommands, "kitnoderefresh");
    }    

    #10. Call plugins.   
    foreach my $command (@kitcommands) {
        my $retref;
        if ($command eq 'removenodes'){
            # Not run makedns -d as it costs too much time
            #setrsp_progress("Updating DNS entries");
            #$retref = xCAT::Utils->runxcmd({command=>["makedns"], node=>$nodes, arg=>['-d']}, $request_command, 0, 2);

            #setrsp_progress("Updating hosts entries");
            $retref = xCAT::Utils->runxcmd({command=>["makehosts"], node=>$nodes, arg=>['-d']}, $request_command, 0, 2);
            next;
        }
        $retref = xCAT::Utils->runxcmd({command=>[$command], node=>$nodes, sequential=>[1]}, $request_command, 0, 2);
        my $retstrref = parse_runxcmd_ret($retref);
        if ($::RUNCMD_RC != 0){
            setrsp_progress("Warning: failed to call kit commands.");
            last;
        }
    }

    setrsp_progress("Re-generated node's IPs for specified nics.");
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
    my $helpmsg = "nodeaddunmged: Creates an unmanaged node specifying the node name and IP address
Usage: 
\tnodeaddunmged hostname<hostname> ip=<ip>
\tnodeaddunmged [-h|--help] 
\tnodeaddunmged {-v|--version}";

    my @enabledparams = ('hostname', 'ip');
    my $ret = validate_args($helpmsg, \@enabledparams, \@enabledparams);
    if (! $ret){
        return;
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
        setrsp_errormsg("The specified IP address $args_dict{'ip'} already exists in the IP address database. You must use a different IP address.");
        return;
    }elsif((xCAT::NetworkUtils->validate_ip($args_dict{'ip'}))[0]->[0] ){
        setrsp_errormsg("The specified IP address $args_dict{'ip'} is invalid. You must use a valid IP address.");
        return;
    }

    # validate hostname.
    $recordsref = xCAT::ProfiledNodeUtils->get_allnode_singleattrib_hash('nodelist', 'node');
    %allhostnames = %$recordsref;
    if (exists $allhostnames{$args_dict{'hostname'}}){
        setrsp_errormsg("The specified device name $args_dict{'hostname'} already exists. You must use a different device name.");
        return;
    }
    if (! xCAT::NetworkUtils->isValidHostname($args_dict{'hostname'})){
        setrsp_errormsg("The specified device name $args_dict{'hostname'} is invalid. You must use a valid device name composed of 'a-z' '0-9'.");
        return;
    }

    my %updatenodeshash = ();
    $updatenodeshash{$args_dict{'hostname'}}{'ip'} = $args_dict{'ip'};
    my $hoststab = xCAT::Table->new('hosts',-create=>1);
    $hoststab->setNodesAttribs(\%updatenodeshash);
    $hoststab->close();

    %updatenodeshash = ();
    $updatenodeshash{$args_dict{'hostname'}}{'groups'} = "__Unmanaged";
    my $nodetab = xCAT::Table->new('nodelist',-create=>1);
    $nodetab->setNodesAttribs(\%updatenodeshash);
    $nodetab->close();

    my $retref = xCAT::Utils->runxcmd({command=>["makehosts"], node=>[$args_dict{"hostname"}]}, $request_command, 0, 2);
    my $retstrref = parse_runxcmd_ret($retref);
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to update /etc/hosts for unmanaged node.");
    }

    $retref = xCAT::Utils->runxcmd({command=>["makedns"], node=>[$args_dict{"hostname"}]}, $request_command, 0, 2);
    $retstrref = parse_runxcmd_ret($retref);
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to update dns for unmanaged node.");
    }

    setrsp_infostr("Created unmanaged node.");
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
    my $helpmsg = "nodechmac: updates the MAC address for a provisioning network interface.
Usage: 
\tnodechmac <node> mac=<mac>
\tnodechmac [-h|--help] 
\tnodechmac  {-v|--version}";

    my @enabledparams = ('mac');
    my $ret = validate_args($helpmsg, \@enabledparams, \@enabledparams);
    if (! $ret){
        return;
    }

    my $nodelist = $request->{node};
    my $hostname = $nodelist->[0];

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
    %allmacsupper = ();
    foreach (keys %allmacs){
        $allmacsupper{uc($_)} = 0;
    }
    if (exists $allmacsupper{uc($args_dict{"mac"})}){
        setrsp_errormsg("The specified MAC address $args_dict{'mac'} already exists. You must use a different MAC address.");
        return;
    } elsif(! xCAT::NetworkUtils->isValidMAC($args_dict{'mac'})){
        setrsp_errormsg("The specified MAC address $args_dict{'mac'} is invalid. You must use a valid MAC address.");
        return;
    }

    # Update database records.
    setrsp_progress("Updating database...");
    my $mactab = xCAT::Table->new('mac',-create=>1);
    $mactab->setNodeAttribs($hostname, {mac=>$args_dict{'mac'}});
    $mactab->close();

    # Call Plugins.
    setrsp_progress("Configuring nodes...");
    my $retref = xCAT::Utils->runxcmd({command=>["kitnodeupdate"], node=>[$hostname], sequential=>[1]}, $request_command, 0, 2);
    my $retstrref = parse_runxcmd_ret($retref);
    if ($::RUNCMD_RC != 0){
        setrsp_progress("Warning: failed to call kit commands.");
    }

    # Update node's status.
    setrsp_progress("Updating node status...");
    my $nodelisttab = xCAT::Table->new('nodelist',-create=>1);
    my (
      $sec,  $min,  $hour, $mday, $mon,
      $year, $wday, $yday, $isdst
    ) = localtime(time);
    my $currtime = sprintf("%02d-%02d-%04d %02d:%02d:%02d",
                         $mon + 1, $mday, $year + 1900,
                         $hour, $min, $sec);

    $nodelisttab->setNodeAttribs($hostname, {status=>'defined', statustime=>$currtime});
    $nodelisttab->close();

    setrsp_progress("Updated MAC address.");
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
    xCAT::MsgUtils->message("Profiled nodes discovery started.");

    my $helpmsg = "nodediscoverstart: Start profiled nodes discovery.
Usage: 
\tnodediscoverstart networkprofile=<networkprofile> imageprofile=<imageprofile> hostnameformat=<hostnameformat> [hardwareprofile=<hardwareprofile>] [groups=<groups>] [rack=<rack>] [chassis=<chassis>] [height=<height>] [unit=<unit>] [rank=rank]
\tnodediscoverstart [-h|--help] 
\tnodediscoverstart {-v|--version}
";

    my @enabledparams = ('networkprofile', 'hardwareprofile', 'imageprofile', 'hostnameformat', 'rank', 'rack', 'chassis', 'height', 'unit', 'groups');
    my @mandatoryparams = ('networkprofile', 'imageprofile', 'hostnameformat');
    my $ret = validate_args($helpmsg, \@enabledparams, \@mandatoryparams);
    if (! $ret){
        return;
    }

    my ($returncode, $errmsg) = xCAT::ProfiledNodeUtils->check_profile_consistent($args_dict{'imageprofile'}, $args_dict{'networkprofile'}, $args_dict{'hardwareprofile'});
    if (not $returncode) {
        setrsp_errormsg($errmsg);
        return;
    }

    # validate hostnameformat:
    my $nameformattype = xCAT::ProfiledNodeUtils->get_hostname_format_type($args_dict{'hostnameformat'});
    if ($nameformattype eq "unknown"){
        setrsp_errormsg("Invalid node name format: $args_dict{'hostnameformat'}");
        return;
    }elsif($nameformattype eq 'rack'){
        if ((! exists $args_dict{'rack'}) && (! exists $args_dict{'chassis'})){
            setrsp_errormsg("Specify rack/chassis as node name format includes rack info.");
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
            setrsp_errormsg("Specified rack $args_dict{'rack'} is not defined");
            return;
        }
        # rack must be specified with chassis or unit + height.
        if (exists $args_dict{'chassis'}){
            setrsp_errormsg("Specified chassis cannot be used with rack.");
            return;
        } else{
            # We set default value for height and u if rack specified
            if(! exists $args_dict{'height'}){$args_dict{'height'} = 1}
            if(! exists $args_dict{'unit'}){$args_dict{'unit'} = 1}
        }
    }

    # chassis jdugement.
    if (exists $args_dict{'chassis'}){
        if (! exists $allchassis{$args_dict{'chassis'}}){
            setrsp_errormsg("Specified chassis $args_dict{'chassis'} is not defined.");
            return;
        }
        if (exists $args_dict{'unit'} or exists $args_dict{'height'}){
            setrsp_errormsg("Specified chassis cannot be used with unit or height.");
            return;
        }
    }
   
    # height and u must be valid numbers.
    if (exists $args_dict{'unit'}){
        # unit must be specified together with rack.
        if (! exists $args_dict{'rack'}){
            setrsp_errormsg("Specified unit must also include specified rack");
            return;
        }
        # Not a valid number.
        if (!($args_dict{'unit'} =~ /^\d+$/)){
            setrsp_errormsg("Specified unit $args_dict{'u'} is invalid");
            return;
        }
    }
    if (exists $args_dict{'height'}){
        # unit must be specified together with rack.
        if (! exists $args_dict{'rack'}){
            setrsp_errormsg("Specified height must include specified rack.");
            return;
        }
        # Not a valid number.
        if (!($args_dict{'height'} =~ /^\d+$/)){
            setrsp_errormsg("Specified height $args_dict{'height'} is invalid.");
            return;
        }
    }

    # Check the running of sequential discovery
    my @PCMdiscover = xCAT::TableUtils->get_site_attribute("__SEQDiscover");
    if ($PCMdiscover[0]) {
        setrsp_errormsg("Profile Discovery cannot be run together with Sequential discovery.");
        return;
    }

    # Read DB to confirm the discover is not started yet. 
    my $discover_running = xCAT::ProfiledNodeUtils->is_discover_started();
    if ($discover_running){
        setrsp_errormsg("Profiled nodes discovery already started.");
        return;
    }

    # Make sure provisioning network has a dynamic range.
    my $provnet = xCAT::ProfiledNodeUtils->get_netprofile_provisionnet($args_dict{networkprofile});
    if (! $provnet){
        setrsp_errormsg("Provisioning network not defined for network profile.");
        return;
    }
    my $networkstab = xCAT::Table->new("networks");
    my $netentry = ($networkstab->getAllAttribsWhere("netname = '$provnet'", 'ALL'))[0];
    if (! $netentry->{'dynamicrange'}){
        setrsp_errormsg("Dynamic IP address range not defined for provisioning network.");
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

    my $helpmsg = "nodediscoverstop: stops node auto-discovery.
Usage: 
\tnodediscoverstop
\tnodediscoverstop [-h|--help] 
\tnodediscoverstop {-v|--version}";

    my $ret = validate_args($helpmsg);
    if (! $ret){
        return;
    }

    # Read DB to confirm the discover is started. 
    xCAT::MsgUtils->message("Stopping profiled node's discover.");
    my $discover_running = xCAT::ProfiledNodeUtils->is_discover_started();
    if (! $discover_running){
        # do nothing that make sequential discovery to handle the message
        # setrsp_errormsg("Node discovery for all nodes using profiles is not started.");
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
        my $retref = xCAT::Utils->runxcmd({command=>["rmdef"], arg=>["-t", "group", "-o", "__PCMDiscover"]}, $request_command, 0, 2);
    }
    setrsp_infostr("Node discovery for all nodes using profiles stopped.");
}


#-------------------------------------------------------

=head3  nodediscoverstatus

    Description :  This function is obsoleted that the status will be displayed by sequential discovery
                       Detect whether Profiled nodes discovery is running or not.
    Arguments   : N/A

=cut

#-------------------------------------------------------
sub nodediscoverstatus{

    my $helpmsg = "nodediscoverstatus: detects if node discovery is running.
Usage: 
\tnodediscoverstatus
\tnodediscoverstatus [-h|--help] 
\tnodediscoverstatus {-v|--version}";
    
    my $ret = validate_args($helpmsg);
    if (! $ret){
        return;
    }

    my $discover_running = xCAT::ProfiledNodeUtils->is_discover_started();
    if($discover_running){
        setrsp_progress("Node discovery for all nodes using profiles is running");
    }else{
        # do nothing that make sequential discovery to handle the message
        # setrsp_progress("Node discovery for all nodes using profiles is not started");
    }
}

#-------------------------------------------------------

=head3  nodediscoverls

    Description : List all discovered profiled nodes.
    Arguments   : N/A

=cut

#-------------------------------------------------------
sub nodediscoverls{
    my $helpmsg = "nodediscoverls: lists all discovered nodes using profiles.
Usage: 
\tnodediscoverls
\tnodediscoverls [-h|--help] 
\tnodediscoverls {-v|--version}";

    my $ret = validate_args($helpmsg);
    if (! $ret){
        return;
    }

    # Read DB to confirm the discover is started. 
    my $discover_running = xCAT::ProfiledNodeUtils->is_discover_started();
    if (! $discover_running){
        # do nothing that make sequential discovery to handle the message
        # setrsp_errormsg("Node discovery process is not running.");
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
    # re-initalize the global variable
    %args_dict = ();
    # Read DB to confirm the discover is started. 
    my $sitetab = xCAT::Table->new('site');
    my $stabent =  $sitetab->getAttribs({'key'=>'__PCMDiscover'},('value'));
    my $sitevaluesstr;
    if (ref $stabent) { 
       $sitevaluesstr = $stabent->{'value'};
    }
    unless ($sitevaluesstr){
        #setrsp_errormsg("Profiled nodes discovery not started yet.");
        return;
    }
    
    xCAT::MsgUtils->message('S', "Profile Discovery: Start.\n");

    # We store node profiles in site table, key is "__PCMDiscover"
    my @profilerecords = split(',', $sitevaluesstr);
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
    %allmacsupper = ();
    foreach (keys %allmacs){
        $allmacsupper{uc($_)} = 0;
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
    $recordsref =  xCAT::ProfiledNodeUtils->get_all_chassis(1,'cmm');
    %allcmmchassis = %$recordsref;

    # Get discovered client IP and MAC
    my $ip = $request->{'_xcat_clientip'};
    xCAT::MsgUtils->message('S', "Profield nodes discover: _xcat_clientip is $ip.\n");
    my $mac = '';
    my $arptable;
    if ( -x "/usr/sbin/arp" ){
        $arptable = `/usr/sbin/arp -n`;
    }
    else {
        $arptable = `/sbin/arp -n`;
    }
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
    if ( exists $allmacsupper{uc($mac)}){
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

        $sitetab = xCAT::Table->new('site',-create=>1);
        $sitetab->setAttribs({"key" => "__PCMDiscover"}, {"value" => "$valuestr"});
        $sitetab->close();
    }
    # For auto discovering PureFlex (x) nodes, set slotid attribute by default.
    if (exists $args_dict{'chassis'}){
        if(exists $allcmmchassis{$args_dict{'chassis'}}){
            $raw_hostinfo_str .= " slotid=1\n";
        }
    }

    xCAT::ProfiledNodeUtils->parse_nodeinfo_file($raw_hostinfo_str);

    my ($hostinfo_dict_ref, $invalid_records_ref) = validate_node_entries();
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
    my $retref = xCAT::Utils->runxcmd({command=>["mkdef"], stdin=>[$retstr_gen], arg=>['-z']}, $request_command, 0, 2);
    my $retstrref = parse_runxcmd_ret($retref);
    # runxcmd failed.
    if ($::RUNCMD_RC != 0){
        setrsp_errormsg($retstr_gen);
        return;
    }

    my @nodelist = keys %hostinfo_dict;

    # call discover to notify client.
    xCAT::MsgUtils->message('S', "Call discovered request.\n");
    $request->{"command"} = ["discovered"];
    $request->{"node"} = \@nodelist;
    $request->{discoverymethod} = ['profile'];
    $retref = xCAT::Utils->runxcmd($request, $request_command, 0, 2);
    $retstrref = parse_runxcmd_ret($retref);

    xCAT::MsgUtils->message('S', "Call nodemgmt plugins.\n");
    $retref = xCAT::Utils->runxcmd({command=>["kitnodeadd"], node=>\@nodelist, sequential=>[1]}, $request_command, 0, 2);
    $retstrref = parse_runxcmd_ret($retref);

    # Set discovered flag.
    my $nodegroupstr = $hostinfo_dict{$nodelist[0]}{"groups"};
    my $nodelstab = xCAT::Table->new('nodelist',-create=>1);
    $nodelstab->setNodeAttribs($nodelist[0],{groups=>$nodegroupstr.",__PCMDiscover"});
    $nodelstab->close();
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

    # Check whether this is Power env.
    my $is_fsp = xCAT::ProfiledNodeUtils->is_fsp_node($args_dict{'networkprofile'});

    # compose the stanza string for hostinfo file.
    my $hostsinfostr = "";
    foreach my $item (sort(keys %hostinfo_dict)){       
        # Generate IPs for other interfaces defined in MAC file.
        my %ipshash;
        foreach (keys %netprofileattr){            
            # Not generate IP if exists other nics
            if (exists $allothernics{$item}->{$_}) {
                $ipshash{$_} = $allothernics{$item}->{$_};
            }
        }

        # Generate IPs for not defined interfaces.
        foreach (keys %netprofileattr){   
            my $netname = $netprofileattr{$_}{'network'};
            my $freeipsref;
            if ($netname){
                $freeipsref = $freeipshash{$netname};
            }
            
            # Not generate other nic's ip if it is defined in file
            if (exists $allothernics{$item}->{$_}) {
                next;
            }
            # Not generate install nic ip if it is defined in file
            if ($_ eq $installnic and exists $hostinfo_dict{$item}{"ip"}){
                next;
            }
            
            # If generated IP is already used, re-generate free ip 
            my $nextip = shift @$freeipsref;
            while (exists $allips{$nextip}){
                $nextip = shift @$freeipsref;
            }
            
            if (!$nextip){
                return 0, "There are no more IP addresses available in the static network range of network $netname for interface $_";
            }else{
                $ipshash{$_} = $nextip;
                $allips{$nextip} = 0;
            }    
        }
        # Apply generated install nic ip to node if it is not defined in file.
        if (! exists $hostinfo_dict{$item}{"ip"}) {
            if (exists $ipshash{$installnic}){
                $hostinfo_dict{$item}{"ip"} = $ipshash{$installnic};
            }else{
                return 0, "There are no more IP addresses available in the static network range for interface $installnic";
            }
        }
 
        my $nicips = $installnic."!".$hostinfo_dict{$item}{"ip"};
        foreach(keys %ipshash){
            if ( $_ eq $installnic ) {next;}
            $nicips = "$_!$ipshash{$_},$nicips";
        }
        $hostinfo_dict{$item}{"nicips"} = $nicips;

        $hostinfo_dict{$item}{"objtype"} = "node";
        $hostinfo_dict{$item}{"groups"} = "__Managed";
        if (exists $args_dict{'networkprofile'}){$hostinfo_dict{$item}{"groups"} .= ",".$args_dict{'networkprofile'}}
        if (exists $args_dict{'imageprofile'}){$hostinfo_dict{$item}{"groups"} .= ",".$args_dict{'imageprofile'}}
        if (exists $args_dict{'hardwareprofile'}){$hostinfo_dict{$item}{"groups"} .= ",".$args_dict{'hardwareprofile'}}
        if (exists $args_dict{'groups'}){$hostinfo_dict{$item}{"groups"} .= ",".$args_dict{'groups'}}

        # xCAT limitation: slotid attribute only for power, id is for x.
        if ((exists $hostinfo_dict{$item}{"slotid"}) && (! $is_fsp) ){
            $hostinfo_dict{$item}{"id"} = $hostinfo_dict{$item}{"slotid"};
            delete($hostinfo_dict{$item}{"slotid"});
        }
        # generage mpa attribute for blades managed by CMM.
        if (exists $hostinfo_dict{$item}{"chassis"}){
            my $chassisname = $hostinfo_dict{$item}{"chassis"};
            if(exists $allcmmchassis{$chassisname}){
                $hostinfo_dict{$item}{"mpa"} = $chassisname;
            }
        }
        
        # get the chain attribute from hardwareprofile and insert it to node.
        my $chaintab = xCAT::Table->new('chain');
        my $hardwareprofile = $args_dict{'hardwareprofile'};
        my $chain = $chaintab->getNodeAttribs($hardwareprofile, ['chain']);

        if (exists $chain->{'chain'}) {
           my $hardwareprofile_chain = $chain->{'chain'};
           $hostinfo_dict{$item}{"chain"} = $hardwareprofile_chain.',osimage='.$provmethod;
        }

        else {
           $hostinfo_dict{$item}{"chain"} = 'osimage='.$provmethod;
        }

        if (exists $netprofileattr{"bmc"}){ # Update BMC records.
            $hostinfo_dict{$item}{"mgt"} = "ipmi";
            if (index($hostinfo_dict{$item}{"chain"}, "runcmd=bmcsetup") == -1){
                $hostinfo_dict{$item}{"chain"} = 'runcmd=bmcsetup,'.$hostinfo_dict{$item}{"chain"}.':reboot4deploy';
            }
            else{
                $hostinfo_dict{$item}{"chain"} = $hostinfo_dict{$item}{"chain"}.':reboot4deploy';
            }

            if (exists $ipshash{"bmc"}){
                $hostinfo_dict{$item}{"bmc"} = $ipshash{"bmc"};
            } else{
                return 0, "There are no more IP addresses available in the static network range for the BMC network.";
            }
        } elsif (exists $netprofileattr{"fsp"}){ # Update FSP records
            $hostinfo_dict{$item}{"mgt"} = "fsp";
            $hostinfo_dict{$item}{"mpa"}= $hostinfo_dict{$item}{"chassis"};
            
            if (exists $ipshash{"fsp"}){
                $hostinfo_dict{$item}{"hcp"} = $ipshash{"fsp"};
            } else{
                return 0, "No sufficient IP addresses for FSP";
            }
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
    # Convert windows txt file into unix format.
    $filecontent =~ s/\cM\cJ/\n/g;
    while ((index $filecontent, "__hostname__:") >= 0){
    	my $nexthost = shift @$freehostnamesref;
    	# no more valid hostnames to assign.
    	if (! $nexthost){
            return 1, "Failed to generate a node name. There are no more valid node names available.";
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

=head3  validate_node_entries
    
    Description : Validate the node entrie and generate proper attributes.
    Arguments   : N/A
    Returns     : (hostinfo_dict, invalid_records)
                  hostinfo_dict -  Reference of hostinfo dict. Key are hostnames and values is an attributes dict.
                  invalid_records - Reference of invalid records list.
=cut    
        
#-------------------------------------------------------
sub validate_node_entries{
    my %hostinfo_dict;
    my @invalid_records;

    my $nameformat = $args_dict{'hostnameformat'};

    my $nameformattype = xCAT::ProfiledNodeUtils->get_hostname_format_type($nameformat);
    my %freehostnames;

    # Record duplicated items.
    # We should go through list @::profiledNodeObjNames first as  %::profiledNodeAttrs is just a hash, 
    # it not tells whether there are some duplicated hostnames in the hostinfo string.
    my %hostnamedict;
    foreach my $hostname (@::profiledNodeObjNames){
        if (exists $hostnamedict{$hostname}){
            push @invalid_records, [$hostname, "Duplicated hostname defined"];
        } else{
            $hostnamedict{$hostname} = 0;
        }
    }
    # Verify each node entry.
    my $rank = 0; 
    if (exists($args_dict{'rank'})){
        $rank = $args_dict{'rank'};
    }

    # Get all nics attribute in networkprofile
    my $networkprofile = $args_dict{networkprofile};
    my $netprofileattrsref = xCAT::ProfiledNodeUtils->get_nodes_nic_attrs([$networkprofile])->{$networkprofile};
    my %netprofileattr = %$netprofileattrsref;
    
    # Get install nic and provision network
    my $noderestab = xCAT::Table->new('noderes');
    my $nodereshashref = $noderestab->getNodeAttribs($networkprofile, ['installnic']);
    my %nodereshash = %$nodereshashref;
    my $installnic = $nodereshash{'installnic'};
    my $provnet = $netprofileattr{$installnic}{"network"};
    $noderestab->close();
    
    # Get all nics' static range
    my %freeipshash = ();
    foreach (keys %netprofileattr){
        my $netname = $netprofileattr{$_}{'network'};
        if($netname and (! exists $freeipshash{$netname})) {
            $freeipshash{$netname} = xCAT::ProfiledNodeUtils->get_allocable_staticips_innet($netname);
        }
    }
    my $freeprovipsref = $freeipshash{$provnet};
 
    # get all chassis's rack info.
    my @chassislist = keys %allchassis;
    my $chassisrackref = xCAT::ProfiledNodeUtils->get_racks_for_chassises(\@chassislist);

    foreach my $attr (@::profiledNodeObjNames){
        my $errmsg = validate_node_entry($attr, $::profiledNodeAttrs{$attr});
        # Check whether specified IP is in our prov network, static range.
        if ($::profiledNodeAttrs{$attr}->{'ip'}){
            unless (grep{ $_ eq $::profiledNodeAttrs{$attr}->{'ip'}} @$freeprovipsref){
                $errmsg .= "Specified IP address $::profiledNodeAttrs{$attr}->{'ip'} not in static range of provision network $provnet";
            }
        }
        
        # Check nicips
        my $nic_and_ips;
        if  ($::profiledNodeAttrs{$attr}->{'nicips'}) {
            my ($ret, $othernicsref, $outputmsg) = xCAT::ProfiledNodeUtils->check_nicips($installnic, $netprofileattrsref, \%freeipshash,$::profiledNodeAttrs{$attr}->{'nicips'});
            if ($ret) {
                $errmsg .= $outputmsg;
            }else {
                $nic_and_ips = $othernicsref;
            }
            delete $::profiledNodeAttrs{$attr}->{'nicips'};
        }
        
        # Set rack info for blades too.
        if ($::profiledNodeAttrs{$attr}->{'chassis'}){
            $::profiledNodeAttrs{$attr}->{'rack'} = $chassisrackref->{$::profiledNodeAttrs{$attr}->{'chassis'}};
        }
        if ($errmsg) {
            if ($attr =~ /^TMPHOSTS/){
                push @invalid_records, ["__hostname__", $errmsg];
            } else{
                push @invalid_records, [$attr, $errmsg];
            }
            next;
        }
        
        my $definedhostname = "";
        # We need generate hostnames for this entry.
        if ($attr =~ /^TMPHOSTS/)
        {
            # rack + numric hostname format, we must specify rack in node's definition.
            my $numricformat;
            # Need convert hostname format into numric format first.
            if ($nameformattype eq "rack"){
                if (! exists $::profiledNodeAttrs{$attr}{"rack"}){
                    push @invalid_records, ["__hostname__", "Rack information is not specified. You must enter the required rack information."];
                    next;
                }
                $numricformat = xCAT::ProfiledNodeUtils->rackformat_to_numricformat($nameformat, $::profiledNodeAttrs{$attr}{"rack"});
                if(! $numricformat){
                    push @invalid_records, ["__hostname__", "The rack number of rack $::profiledNodeAttrs{$attr}{'rack'} does not match hostname format $nameformat"];
                }
            } else{
                # pure numric hostname format
                $numricformat = $nameformat;
            }

            # Generate hostnames based on numric hostname format.
            my $hostnamelistref;
            if (! exists $freehostnames{$numricformat}){
                $hostnamelistref = xCAT::ProfiledNodeUtils->genhosts_with_numric_tmpl($numricformat, $rank, 10000);
                $rank = $rank + 10000;
                if (! @$hostnamelistref){
                    push @invalid_records, ["__hostname__", "Can not generate sufficient hostnames from hostname format."];
                    last;
                }else{
                    $freehostnames{$numricformat} = $hostnamelistref;
                }
            }

            $hostnamelistref = $freehostnames{$numricformat};
            my $nexthostname = shift @$hostnamelistref;
            while ( (! $nexthostname) || exists $allhostnames{$nexthostname}){
                if (! @$hostnamelistref){
                    $hostnamelistref = xCAT::ProfiledNodeUtils->genhosts_with_numric_tmpl($numricformat, $rank, 10000);
                    $rank = $rank + 10000;
                    if(! @$hostnamelistref){
                        push @invalid_records, ["__hostname__", "Can not generate sufficient hostnames from hostname format."];
                        last;
                    }
                }

                $nexthostname = shift @$hostnamelistref;
            }
            $definedhostname = $nexthostname;
            $hostinfo_dict{$nexthostname} = $::profiledNodeAttrs{$attr};
        } else{
            $definedhostname = $attr;
            $hostinfo_dict{$attr} = $::profiledNodeAttrs{$attr};
        }
        
        if ($nic_and_ips){
            $allothernics{$definedhostname} = $nic_and_ips;
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
    my $errmsg = "";

    # duplicate hostname found in hostinfo file.
    if (exists $allhostnames{$node_name}) {
        $errmsg .= "Node name $node_name already exists. You must use a new node name.\n";
    }
    # Must specify either MAC or switch + port.
    if (exists $node_entry{"mac"} || 
        exists $node_entry{"switch"} && exists $node_entry{"switchport"}){
    } else{
        $errmsg .= "MAC address, switch and port is not specified. You must specify the MAC address or switch and port.\n";
    }

    if (! xCAT::NetworkUtils->isValidHostname($node_name)){
        unless ($node_name =~ /^TMPHOSTS/){
            $errmsg .= "Node name: $node_name is invalid. You must use a valid node name.\n";
        }
    }
    
    # validate if node use FSP network
    my $is_fsp = xCAT::ProfiledNodeUtils->is_fsp_node($args_dict{'networkprofile'});
    
    # validate each single value.
    foreach (keys %node_entry){
        if ($_ eq "mac"){
            if (exists $allmacsupper{uc($node_entry{$_})}){
                $errmsg .= "MAC address $node_entry{$_} already exists in the database or in the nodeinfo file. You must use a new MAC address.\n";
            }elsif(! xCAT::NetworkUtils->isValidMAC($node_entry{$_})){
                $errmsg .= "MAC address $node_entry{$_} is invalid. You must use a valid MAC address.\n";
            }else{
                $allmacs{$node_entry{$_}} = 0;
            }
        }elsif ($_ eq "ip"){
            if (exists $allips{$node_entry{$_}}){
                $errmsg .= "IP address $node_entry{$_} already exists in the database or in the nodeinfo file.\n";
            }elsif((xCAT::NetworkUtils->validate_ip($node_entry{$_}))[0]->[0] ){
                $errmsg .= "IP address $node_entry{$_} is invalid. You must use a valid IP address.\n";
            }else {
                #push the IP into allips list.
                $allips{$node_entry{$_}} = 0;
            }
        }elsif ($_ eq "switch"){
            #TODO: xCAT switch discovery enhance: verify whether switch exists.
            if (! exists $allswitches{$node_entry{$_}}){
                $errmsg .= "Specified switch $node_entry{$_} is not defined\n";
            }
        }elsif ($_ eq "switchport"){
            if (! exists $node_entry{"switchport"}){
                $errmsg .= "Specified switch must be used with port.\n";
            }
            # Not a valid number.
            if (!($node_entry{$_} =~ /^\d+$/)){
                $errmsg .= "Specified port $node_entry{$_} is invalid\n";
            }
            # now, we need to check "swith_switchport" string list to avoid duplicate config
            my $switch_port = $node_entry{'switch'} . "_" . $node_entry{$_};
            if (exists $all_switchports{$switch_port}){
                $errmsg .= "Specified switch port $node_entry{$_} already exists in the database or in the nodeinfo file. You must use a new switch port.\n";
            }else{
            # after checking, add this one into all_switchports 
            $all_switchports{$switch_port} = 0;
            }
        }elsif ($_ eq "rack"){
            if (! exists $allracks{$node_entry{$_}}){
                $errmsg .= "Specified rack $node_entry{$_} is not defined\n";
            }
            # rack must be specified with chassis or unit + height.
            if (exists $node_entry{"chassis"}){
                $errmsg .= "Specified rack cannot be used with chassis.\n";
            } elsif (exists $node_entry{"height"} and exists $node_entry{"unit"}){
            } else {
                $errmsg .= "Specified rack must also specify the chassis or the height and unit.\n";
            }
        }elsif ($_ eq "chassis"){
            if (! exists $allchassis{$node_entry{$_}}){
                $errmsg .= "Specified chassis $node_entry{$_} is not defined\n";
            }
            # Chassis must not be specified with unit and height.
            if (exists $node_entry{"height"} or exists $node_entry{"unit"}){
                $errmsg .= "Specified chassis cannot be used with height or unit.\n";
            }
            # Check if this chassis is CMM. If it is, must specify slotid
            if (exists $allcmmchassis{$node_entry{$_}}){
                if (not exists $node_entry{"slotid"}){
                    $errmsg .= "Specified CMM Chassis must be used with slotid";
                }
            }else {
                # If the specific chassis is not CMM chassis, but network is fsp
                if ($is_fsp) {
                    $errmsg .= "Specified FSP network must be used with CMM chassis."
                }
            }
        }elsif ($_ eq "unit"){
            if (! exists $node_entry{"rack"}){
                $errmsg .= "Specified unit must be used with rack.\n";
            }
            # Not a valid number.
            if (!($node_entry{$_} =~ /^\d+$/)){
                $errmsg .= "Specified unit $node_entry{$_} is invalid\n";
            }
        }elsif ($_ eq "height"){
            if (! exists $node_entry{"rack"}){
                $errmsg .= "Height must be used with rack\n";
            }
            # Not a valid number.
            if (!($node_entry{$_} =~ /^\d+$/)){
                $errmsg .= "Specified height $node_entry{$_} is invalid\n";
            }
        }elsif ($_ eq "slotid"){
            if (not exists $node_entry{"chassis"}){
                $errmsg .= "Specified slotid must be used with chassis";
            }
            # Not a valid number.
            if (!($node_entry{$_} =~ /^[1-9]\d*$/)){
                $errmsg .= "Specified slotid $node_entry{$_} is invalid";
            }
        }elsif ($_ eq "nicips"){
            # Check Multi-Nic's ip
            my $othernics = $node_entry{$_};
            foreach my $nic_ips (split(/,/, $othernics)) {
                my @nic_and_ips = ();
                my $nic = "";
                my $nic_ip = "";
                if($nic_ips =~ /!/ and $nic_ips !~ /!$/) {
                    @nic_and_ips = split(/!/, $nic_ips);
                    $nic_ip = $nic_and_ips[1];
                    if (exists $allips{$nic_ip}){
                        $errmsg .= "IP address $nic_ip already exists in the database or in the nodeinfo file.\n";
                    }elsif((xCAT::NetworkUtils->validate_ip($nic_ip))[0]->[0] ){
                        $errmsg .= "IP address $nic_ip is invalid. You must use a valid IP address.\n";
                    }else {
                        #push the IP into allips list.
                        $allips{$nic_ip} = 0;
                    }
                }
            } 
        }else{
           $errmsg .= "Invalid attribute $_ specified\n";
        }
    }
    # push hostinfo into global dicts.
    $allhostnames{$node_name} = 0;
    return $errmsg;
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
    $rsp->{error} = ["Errors found in nodeinfo file"];
    $rsp->{errorcode} = [2];
    $rsp->{invalid_records_num}->[0] = scalar @$recordsref;

    # We write details of invalid records into a file.
    my ($fh, $filename) = xCAT::ProfiledNodeUtils->get_output_filename();
    foreach (@$recordsref){
    	my @erroritem = @$_;
        print $fh "nodename $erroritem[0], error:\n$erroritem[1]\n";
    }
    close $fh;
    #make it readable for http.
    system("chmod +r $filename");
    # Tells the URL of the details file.
    xCAT::MsgUtils->message('S', "Detailed response info placed in file: $filename\n");
    $rsp->{details} = [$filename];
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
    $rsp->{error} = [$errormsg];
    $rsp->{errorcode} = [1];
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
    $rsp->{data} = [$infostr];
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
    $rsp->{info} = [$progress];
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
    $rsp->{success_nodes_num}->[0] = scalar @$recordsref;
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
    $rsp->{details} = [$filename];
    $callback->($rsp);
}

#-----------------------------------------------------
=head3  parse_runxcmd_ret

    Description : Get return of runxcmd and convert it into strings.
    Arguments   : The return reference of runxcmd
    Return:     : [$outstr, $errstr], A reference of list, placing standard output and standard error message.

=cut

#-----------------------------------------------------
sub parse_runxcmd_ret
{
    my $retref = shift;
    
    my $msglistref;
    my $outstr = "";
    my $errstr = "";
    if ($retref){
        if($retref->{data}){
            $msglistref = $retref->{data};
            $outstr = Dumper(@$msglistref);
            xCAT::MsgUtils->message('S',"Command standard output: $outstr");
        }
        if($retref->{error}){
            $msglistref = $retref->{error};
            $errstr =  Dumper(@$msglistref);
            xCAT::MsgUtils->message('S',"Command error output: $errstr");
        }
    }
    return [$outstr, $errstr];
}

1;
