# IBM(c) 2012 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1

    xCAT plugin to support PCM node management
    These commands are designed to be called by PCM GUI.
    
=cut

#-------------------------------------------------------
package xCAT_plugin::pcmnodes;

use strict;
use warnings;
require xCAT::Table;
require xCAT::DBobjUtils;
require xCAT::Utils;
require xCAT::TableUtils;
require xCAT::NetworkUtils;
require xCAT::MsgUtils;
require xCAT::PCMNodeMgmtUtils;

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
        addhost_hostfile   => 'pcmnodes',
        addhost_discover     => 'pcmnodes',
        removehost     => 'pcmnodes',
        updatehost     => 'pcmnodes',
    };
}


#-------------------------------------------------------

=head3  process_request

    Process the command.  This is the main call.

=cut

#-------------------------------------------------------
sub process_request {

    my $lock = xCAT::PCMNodeMgmtUtils->acquire_lock();
    unless ($lock){
        setrsp_errormsg("Can not acquire lock, some process is operating node related actions.");
        return;
    }
    $request = shift;
    $callback = shift;
    $request_command = shift;
    $command = $request->{command}->[0];
    $args = $request->{arg};
	
    if ($command eq "addhost_hostfile"){
        addhost_hostfile()
    } elsif ($command eq "removehost"){
    	removehost();
    } elsif ($command eq "updatehost"){
    	updatehost();
    }
    xCAT::PCMNodeMgmtUtils->release_lock($lock);
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

=head3  addhost_hostfile

    Description : Create nodes by import hostinfo file.
    Arguments   : N/A

=cut

#-------------------------------------------------------
sub addhost_hostfile {

    # Parse arges.
    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]Import PCM nodes through hostinfo file.\n");
    my $retstr = parse_args();
    if ($retstr){
        setrsp_errormsg($retstr);
        return;
    }
    # Make sure the specified parameters are valid ones.
    # TODO: support privisioning template.
    my @enabledparams = ('file', 'groups', 'networkprofile', 'hardwareprofile', 'imageprofile');
    foreach my $argname (keys %args_dict){
        if (! grep{ $_ eq $argname} @enabledparams){
            setrsp_errormsg("Illegal attribute $argname specified.");
            return;
        }
    }
    # validate hostinfo file.
    if (! exists $args_dict{'file'}){
        setrsp_errormsg("No hostinfo file specified.");
        return;
    }
    elsif(! (-e $args_dict{'file'})){
        setrsp_errormsg("The hostinfo file not exists.");
        return;
    }

    # Get database records: all hostnames, all ips, all racks...
    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]Getting database records.\n");
    my $recordsref = xCAT::PCMNodeMgmtUtils->get_allnode_singleattrib_hash('nodelist', 'node');
    %allhostnames = %$recordsref;
    $recordsref = xCAT::PCMNodeMgmtUtils->get_allnode_singleattrib_hash('ipmi', 'bmc');
    %allbmcips = %$recordsref;
    $recordsref = xCAT::PCMNodeMgmtUtils->get_allnode_singleattrib_hash('mac', 'mac');
    %allmacs = %$recordsref;
    $recordsref = xCAT::PCMNodeMgmtUtils->get_allnode_singleattrib_hash('hosts', 'ip');
    %allinstallips = %$recordsref;
    $recordsref = xCAT::NetworkUtils->get_all_nicips(1);
    %allips = %$recordsref;

    # Merge all BMC IPs and install IPs into allips.
    %allips = (%allips, %allbmcips, %allinstallips);

    #my $recordsref = xCAT::PCMNodeMgmtUtils->get_allnode_singleattrib_hash('rack', 'rackname');
    #%allracks = %$recordsref;
    #my $recordsref =  xCAT::PCMNodeMgmtUtils->get_allchassis(1);
    #%allchassis = %$recordsref;

    # Generate temporary hostnames for hosts entries in hostfile. 
    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]Generate temporary hostnames.\n");
    my ($retcode_read, $retstr_read) = read_and_generate_hostnames($args_dict{'file'});
    if ($retcode_read != 0){
        setrsp_errormsg($retstr_read);
        return;
    }

    # Parse and validate the hostinfo string. The real hostnames will be generated here.
    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]Parsing hostinfo string and validate it.\n");
    my ($hostinfo_dict_ref, $invalid_records_ref) = parse_hosts_string($retstr_read);
    my %hostinfo_dict = %$hostinfo_dict_ref;
    my @invalid_records = @$invalid_records_ref;
    if (@invalid_records){
        setrsp_invalidrecords(\@invalid_records);
        return;
    }
    unless (%hostinfo_dict){
        setrsp_errormsg("No valid host records found in hostinfo file.");
        return;
    }

    # Create the real hostinfo string in stanza file format.
    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]Generating new hostinfo string.\n");
    my ($retcode_gen, $retstr_gen) = gen_new_hostinfo_string(\%hostinfo_dict);
    unless ($retcode_gen){
        setrsp_errormsg($retstr_gen);
        return;
    }
    # call mkdef to create hosts and then call nodemgmt for node management plugins.
    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]call mkdef to create pcm nodes.\n");
    $request_command->({command=>["mkdef"], stdin=>[$retstr_gen], arg=>['-z']});

    my @nodelist = keys %hostinfo_dict;
    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]call nodemgmt plugins.\n");
    $request_command->({command=>["kitcmd_nodemgmt_add"], node=>\@nodelist});
    $request_command->({command=>["kitcmd_nodemgmt_finished"], node=>\@nodelist});
    setrsp_success(\@nodelist);
}

#-------------------------------------------------------

=head3  removehost

    Description : Remove nodes.
    Arguments   : N/A

=cut

#-------------------------------------------------------
sub removehost{
    my $nodes   = $request->{node};
    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]Remove PCM nodes.\n");
    # For remove nodes, we should call 'nodemgmt' in front of 'noderm'
    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]call nodemgmt plugins.\n");
    $request_command->({command=>["kitcmd_nodemgmt_remove"], node=>$nodes});
    $request_command->({command=>["kitcmd_nodemgmt_finished"], node=>$nodes});
    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]call noderm to remove nodes.\n");
    $request_command->({command=>["noderm"], node=>$nodes});
    setrsp_success($nodes);
}

#-------------------------------------------------------

=head3  updatehost

    Description : Update host profiles.
    Arguments   : N/A

=cut

#-------------------------------------------------------
sub updatehost{
    my $nodes   = $request->{node};
    my %updated_groups;

    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]Update PCM nodes settings.\n");
    # Parse arges.
    my $retstr = parse_args();
    if ($retstr){
        setrsp_errormsg($retstr);
        return;
    }
    # Make sure the specified parameters are valid ones.
    # TODO: support privisioning template.
    my @enabledparams = ('networkprofile', 'hardwareprofile', 'imageprofile');
    foreach my $argname (keys %args_dict){
        if (! grep{ $_ eq $argname} @enabledparams){
            setrsp_errormsg("Illegal attribute $argname specified.");
            return;
        }
    }

    # Get current templates for all nodes.
    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]Read database to get groups for all nodes.\n");
    my %groupdict;
    my $nodelstab = xCAT::Table->new('nodelist');
    my $nodeshashref = $nodelstab->getNodesAttribs($nodes, ['groups']);
    my %nodeshash = %$nodeshashref;
    my %updatenodeshash;
    foreach (keys %nodeshash){
        my @groups;
        my $attrshashref = $nodeshash{$_}[0];
        my %attrshash = %$attrshashref;
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
    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]Update database records.\n");
    my $nodetab = xCAT::Table->new('nodelist',-create=>1);
    $nodetab->setNodesAttribs(\%updatenodeshash);
    $nodetab->close();
    
    # call plugins
    xCAT::MsgUtils->message('S', "[PCM nodes mgmt]call nodemgmt plugins.\n");
    $request_command->({command=>["kitcmd_nodemgmt_update"], node=>$nodes});
    $request_command->({command=>["kitcmd_nodemgmt_finished"], node=>$nodes});
    setrsp_success($nodes);
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
    my $netprofileattrsref = xCAT::PCMNodeMgmtUtils->get_netprofile_nic_attrs($args_dict{'networkprofile'});
    my %netprofileattr = %$netprofileattrsref;
    my %freeipshash;
    foreach (keys %netprofileattr){
        my $netname = $netprofileattr{$_}{'network'};
        if($netname and (! exists $freeipshash{$netname})) {
            $freeipshash{$netname} = xCAT::PCMNodeMgmtUtils->get_allocable_staticips_innet($netname, \@allknownips);
        }
    }

    # Get networkprofile's installip
    my $noderestab = xCAT::Table->new('noderes');
    my $networkprofile = $args_dict{'networkprofile'};
    my $nodereshashref = $noderestab->getNodeAttribs($networkprofile, ['installnic']);
    my %nodereshash = %$nodereshashref;
    my $installnic = $nodereshash{'installnic'};

    # Get node's provisioning method
    my $provmethod = xCAT::PCMNodeMgmtUtils->get_imageprofile_prov_method($args_dict{'imageprofile'});

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
    my $freehostnamesref = xCAT::PCMNodeMgmtUtils->gen_numric_hostnames("TMPHOSTS","", 4);
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

    my $nicstab = xCAT::Table->new('nics');
    my $nodehashref = $nicstab->getNodeAttribs($args_dict{'networkprofile'}, ['hostnameformat']);
    my $nameformat = $nodehashref->{'hostnameformat'};

    my $nameformattype = xCAT::PCMNodeMgmtUtils->get_hostname_format_type($nameformat);
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
                $numricformat = xCAT::PCMNodeMgmtUtils->rackformat_to_numricformat($nameformat, $::FILEATTRS{$_}{"rack"});
            } else{
                # pure numric hostname format
                $numricformat = $nameformat;
            }

            # Generate hostnames based on numric hostname format.
            if (! exists $freehostnames{$numricformat}){
                $freehostnames{$numricformat} = xCAT::PCMNodeMgmtUtils->genhosts_with_numric_tmpl($numricformat);
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
            #TODO: xCAT switch discovery enhance: verify whether port exists.
        }elsif ($_ eq "rack"){
            if (not exists $allracks{$node_entry{$_}}){
                return "Specified rack $node_entry{$_} not defined";
            }
        }elsif ($_ eq "chassis"){
            if (not exists $allchassis{$node_entry{$_}}){
                return "Specified chassis $node_entry{$_} not defined";
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
    # For blades, don't support specify unit and height.
    if(exists $node_entry{"chassis"} ){
        if(exists $node_entry{"unit"}){
            return "Can not specify 'unit' together with 'chassis'";
        }
        if(exists $node_entry{"height"}){
            return "can not specify 'height' together with 'chassis'";
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
    my $master=xCAT::TableUtils->get_site_Master();
    
    # The total number of invalid records.
    $rsp->{invalid_records_num} = scalar @$recordsref;

    # We write details of invalid records into a file.
    my ($fh, $filename) = xCAT::PCMNodeMgmtUtils->get_output_filename();
    foreach (@$recordsref){
    	my @erroritem = @$_;
        print $fh "nodename $erroritem[0], error: $erroritem[1]\n";
    }
    close $fh;
    # Tells the URL of the details file.
    xCAT::MsgUtils->message('S', "Detailed response info placed in file: http://$master/$filename\n");
    $rsp->{details} = "http://$master/$filename";
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
    $rsp->{error}->[0] = $errormsg;
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
    my $rsp;
    my $master=xCAT::TableUtils->get_site_Master();
    
    # The total number of success nodes.
    $rsp->{success_nodes_num} = scalar @$recordsref;
    my ($fh, $filename) = xCAT::PCMNodeMgmtUtils->get_output_filename();
    foreach (@$recordsref){
        print $fh "success: $_\n";
    }
    close $fh;
    # Tells the URL of the details file.
    xCAT::MsgUtils->message('S', "Detailed response info placed in file: http://$master/$filename\n");
    $rsp->{details} = "http://$master/$filename";
    $callback->($rsp);
}
1;
