# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::openstack;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::SvrUtils;
use xCAT::NetworkUtils;
use xCAT::Table;
use Data::Dumper;
use File::Path;
use File::Copy;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");


sub handled_commands {
    return {
		opsaddbmnode => "openstack",  #external command
		opsaddimage => "openstack",   #external command
		deploy_ops_bm_node => "openstack",   #internal command called from the baremetal driver
		cleanup_ops_bm_node => "openstack",  #internal command called from the baremetal driver
   }
}

sub process_request {
	my $request = shift;
	my $callback = shift;
	my $doreq = shift;
	my $command = $request->{command}->[0];
	
	if ($command eq "opsaddbmnode") {
		return opsaddbmnode($request, $callback, $doreq);
	} elsif ($command eq "opsaddimage") {
		return opsaddimage($request, $callback, $doreq);
	} elsif ($command eq "deploy_ops_bm_node") {
		return deploy_ops_bm_node($request, $callback, $doreq);
	} elsif ($command eq "cleanup_ops_bm_node") {
		return cleanup_ops_bm_node($request, $callback, $doreq);
	} else {
		$callback->({error=>["Unsupported command: $command."],errorcode=>[1]});
		return 1;
	}
}


#-------------------------------------------------------------------------------

=head3  opsaddbmnode
     This function takes the xCAT nodes and register them
     as the OpenStack baremetal nodes
=cut

#-------------------------------------------------------------------------------
sub opsaddbmnode {
	my $request = shift;
	my $callback = shift;
	my $doreq = shift;
	
	@ARGV = @{$request->{arg}};
	Getopt::Long::Configure("bundling");
	Getopt::Long::Configure("no_pass_through");
	
	my $help;
	my $version;
	my $host;
	
    if(!GetOptions(
            'h|help'      => \$help,
            'v|version'   => \$version,
            's=s'         => \$host,
       ))
    {
        &opsaddbmnode_usage($callback);
        return 1;
    }
    # display the usage if -h or --help is specified
    if ($help) {
        &opsaddbmnode_usage($callback);
        return 0;
    }
    # display the version statement if -v or --verison is specified
    if ($version)
    {
        my $rsp={};
        $rsp->{data}->[0]= xCAT::Utils->Version();
        $callback->($rsp);
        return 0;
    }
	
	if (!$request->{node}) {
		$callback->({error=>["Please specify at least one node."],errorcode=>[1]});
		return 1;  
	}
	if (!$host) {
		$callback->({error=>["Please specify the OpenStack compute host name with -s flag."],errorcode=>[1]});
		return 1;  
	}
    
    my $nodes = $request->{node};

    #get node mgt
    my $nodehmhash;
    my $nodehmtab = xCAT::Table->new("nodehm");
    if ($nodehmtab) {
        $nodehmhash = $nodehmtab->getNodesAttribs($nodes,['power', 'mgt']);
    }

    #get bmc info for the nodes
	my $ipmitab = xCAT::Table->new("ipmi", -create => 0);
	my $tmp_ipmi;
	if ($ipmitab) {
		$tmp_ipmi = $ipmitab->getNodesAttribs($nodes, ['bmc','username', 'password'], prefetchcache=>1);
		#print Dumper($tmp_ipmi);
	} else {
		$callback->({error=>["Cannot open the ipmi table."],errorcode=>[1]});
		return 1;		
	}

    #get mac for the nodes
	my $mactab = xCAT::Table->new("mac", -create => 0);
	my $tmp_mac;
	if ($mactab) {
		$tmp_mac = $mactab->getNodesAttribs($nodes, ['mac'], prefetchcache=>1);
		#print Dumper($tmp_mac);
	} else {
		$callback->({error=>["Cannot open the mac table."],errorcode=>[1]});
		return 1;		
	}

    #get cpu, memory and disk info for the nodes
	my $hwinvtab = xCAT::Table->new("hwinv", -create => 0);
	my $tmp_hwinv;
	if ($hwinvtab) {
		$tmp_hwinv = $hwinvtab->getNodesAttribs($nodes, ['cpucount', 'memory', 'disksize'], prefetchcache=>1);
		#print Dumper($tmp_hwinv);
	} else {
		$callback->({error=>["Cannot open the hwinv table."],errorcode=>[1]});
		return 1;		
	}

    #get default username and password for bmc
    my $d_bmcuser;
    my $d_bmcpasswd;
	my $passtab = xCAT::Table->new('passwd');
	if ($passtab) {
		($tmp_passwd)=$passtab->getAttribs({'key'=>'ipmi'},'username','password');
		if (defined($tmp_passwd)) {
			$d_bmcuser = $tmp_passwd->{username};
			$d_bmcpasswd = $tmp_passwd->{password};
		}
	}

	#print "d_bmcuser=$d_bmcuser, d_bmcpasswd=$d_bmcpasswd \n";
	foreach my $node (@$nodes) {
        #collect the node infomation needed for each node, some info
		my $mgt;
		my $ref_nodehm = $nodehmhash->{$node}->[0];
		if ($ref_nodehm) {
			if ($ref_nodehm->{'power'}) {
				$mgt = $ref_nodehm->{'power'};
			} elsif ($ref_nodehm->{'mgt'}) {
				$mgt = $ref_nodehm->{'mgt'};
			}
		}

		my ($bmc, $bmc_user, $bmc_password, $mac, $cpu, $memory, $disk);
		if (($mgt) && ($mgt eq 'ipmi')) { 
			my $ref_ipmi = $tmp_ipmi->{$node}->[0]; 
			if ($ref_ipmi) {
				if (exists($ref_ipmi->{bmc})) {
					$bmc = $ref_ipmi->{bmc};
				}
				if (exists($ref_ipmi->{username})) {
					$bmc_user = $ref_ipmi->{username};
					if (exists($ref_ipmi->{password})) {
						$bmc_password = $ref_ipmi->{password};
					} 
				} else { #take the default if they cannot be found on ipmi table
					if ($d_bmcuser) { $bmc_user = $d_bmcuser; }
					if ($d_bmcpasswd) { $bmc_password = $d_bmcpasswd; }
				}
			}
		} # else { # for hardware control point other than ipmi, just fake it in OpenStack.
			#$bmc = "0.0.0.0";
			#$bmc_user = "xCAT";
			#$bmc_password = "xCAT";
		#}

		my $ref_mac = $tmp_mac->{$node}->[0]; 
	    if ($ref_mac) {
			if (exists($ref_mac->{mac})) {
				$mac = $ref_mac->{mac};
			}
		}

		$ref_hwinv = $tmp_hwinv->{$node}->[0]; 
	    if ($ref_hwinv) {
			if (exists($ref_hwinv->{cpucount})) {
				$cpu = $ref_hwinv->{cpucount};
			}
			if (exists($ref_hwinv->{memory})) {
				$memory = $ref_hwinv->{memory};
                #TODO: what if the unit is not in MB? We need to convert it to MB
				$memory =~ s/MB|mb//g;
			}
			if (exists($ref_hwinv->{disksize})) {
				#The format of the the disk size is: sda:250GB,sdb:250GB or just 250GB
                #We need to get the size of the first one
				$disk = $ref_hwinv->{disksize};
				my @a = split(',', $disk);
				my @b = split(':', $a[0]);
				if (@b > 1) {
					$disk = $b[1];
				} else {
					$disk = $b[0];
				}
                #print "a=@a, b=@b\n";
                #TODO: what if the unit is not in GB? We need to convert it to MB
				$disk =~ s/GB|gb//g;
			}
		}

		#some info are mendatory
        if (!$mac) {
			$callback->({error=>["Mac address is not defined in the mac table for node $node."],errorcode=>[1]});
			next;
		}
		if (!$cpu) {
			#default cpu count is 1
			$cpu = 1;
		}
		if (!$memory) {
			#default memory size is 1024MB=1GB
			$memory = 1024;
		}
		if (!$disk) {
			#default disk size is 1GB
			$disk = 1;
		}				
		
		#print "$bmc, $bmc_user, $bmc_password, $mac, $cpu, $memory, $disk\n";

		#call OpenStack command to add the node into the OpenStack as
        #a baremetal node.
        my $cmd_tmp = "nova baremetal-node-create";
		if ($bmc) {
			#make sure it is an ip address
			if (($bmc !~ /\d+\.\d+\.\d+\.\d+/) && ($bmc !~ /:/)) {
				$bmc =  xCAT::NetworkUtils->getipaddr($bmc);
			}
			$cmd_tmp .= " --pm_address=$bmc";			
		}
		if ($bmc_user) {
			$cmd_tmp .= " --pm_user=$bmc_user";
		}
		if ($bmc_password) {
			$cmd_tmp .= " --pm_password=$bmc_password";
		}
		$cmd_tmp .= " $host $cpu $memory $disk $mac";
 
		my $cmd = qq~source \~/openrc;$cmd_tmp~;
		#print "cmd=$cmd\n";
		my $output =
			xCAT::InstUtils->xcmd($callback, $doreq, "xdsh", [$host], $cmd, 0);
		if ($::RUNCMD_RC != 0) {
			my $rsp;
			push @{$rsp->{data}}, "OpenStack creating baremetal node $node:";
			push @{$rsp->{data}}, "$output";
			xCAT::MsgUtils->message("E", $rsp, $callback);
		}
	}
}


#-------------------------------------------------------------------------------

=head3  opsaddimage
     This function takes the xCAT nodes and register them
     as the OpenStack baremetal nodes
=cut

#-------------------------------------------------------------------------------
sub opsaddimage {
	my $request = shift;
	my $callback = shift;
	my $doreq = shift;
	
	@ARGV = @{$request->{arg}};
	Getopt::Long::Configure("bundling");
	Getopt::Long::Configure("no_pass_through");
	
	my $help;
	my $version;
	#my $cloud;
	my $ops_img_names;
    my $controller;
	
    if(!GetOptions(
            'h|help'      => \$help,
            'v|version'   => \$version,
            'c=s'         => \$controller,
			'n=s'         => \$ops_img_names,
       ))
    {
        &opsaddimage_usage($callback);
        return 1;
    }
    # display the usage if -h or --help is specified
    if ($help) {
        &opsaddimage_usage($callback);
        return 0;
    }
    # display the version statement if -v or --verison is specified
    if ($version)
    {
        my $rsp={};
        $rsp->{data}->[0]= xCAT::Utils->Version();
        $callback->($rsp);
        return 0;
    }
	
	if (@ARGV ==0) {
		$callback->({error=>["Please specify an image name or a list of image names."],errorcode=>[1]});
		return 1;  
	}

	#make sure the input cloud name is valid.
	#if (!$cloud) {
	#	$callback->({error=>["Please specify the name of the cloud with -c flag."],errorcode=>[1]});
	#	return 1;  
	#} else {
	#	my $cloudstab = xCAT::Table->new('clouds', -create => 0);
	#	my @et = $cloudstab->getAllAttribs('name', 'controller');
	#	if(@et) {
	#		foreach my $tmp_et (@et) {
	#			if ($tmp_et->{name} eq $cloud) {
	#				if ($tmp_et->{controller}) {
	#					$controller = $tmp_et->{controller};
	#					last;
	#				} else {
	#					$callback->({error=>["Please specify the controller in the clouds table for the cloud: $cloud."],errorcode=>[1]});
	#					return 1;  	
	#				}
	#			}
	#		}
	#	}
	
	if (!$controller) {
		$callback->({error=>["Please specify the OpenStack controller node name with -c."],errorcode=>[1]});
		return 1;  			
	}
	#}

	#make sure that the images from the command are valid image names
    @images = split(',', $ARGV[0]);
    @new_names = ();
	if ($ops_img_names) {
		@new_names = split(',', $ops_img_names);
	}
	#print "images=@images, new image names=@new_names, controller=$controller\n";

	my $image_hash = {};
    my $osimgtab = xCAT::Table->new('osimage', -create => 0);
    my @et = $osimgtab->getAllAttribs('imagename');
	if(@et) {
		foreach my $tmp_et (@et) {
			$image_hash->{$tmp_et->{imagename}}{'xCAT'} = 1;
		}
	}
	my @bad_images;
	foreach my $image (@images) {
		if (!exists($image_hash->{$image})) {
			push @bad_images, $image;
		}
	}
	if (@bad_images > 0) {
		$callback->({error=>["The following images cannot be found in xCAT osimage table:\n  " . join("\n  ", @bad_images) . "\n"],errorcode=>[1]});
		return 1;  
	}

	my $index=0;
 	foreach my $image (@images) {
		my $new_name = shift(@new_names);
		if (!$new_name) {
			$new_name = $image; #the default new name is xCAT image name
		}
        my $cmd_tmp = "glance image-create --name $new_name --public --disk-format qcow2 --container-format bare --property xcat_image_name=\'$image\' < /tmp/$image.qcow2";

		my $cmd = qq~touch /tmp/$image.qcow2;source \~/openrc;$cmd_tmp;rm /tmp/$image.qcow2~;
		#print "cmd=$cmd\ncontroller=$controller\n";
		my $output =
			xCAT::InstUtils->xcmd($callback, $doreq, "xdsh", [$controller], $cmd, 0);
		if ($::RUNCMD_RC != 0) {
			my $rsp;
			push @{$rsp->{data}}, "OpenStack creating image $new_name:";
			push @{$rsp->{data}}, "$output";
			xCAT::MsgUtils->message("E", $rsp, $callback);
		}		 
	}
}

#-------------------------------------------------------------------------------

=head3  deploy_ops_bm_node
	This is a internel command called by OpenStack xCAT-baremetal driver. 
	It prepares the node by adding the config_ops_bm_node postbootscript 
	to the postscript table for the node, then call nodeset and then boot 
	the node up.
=cut

#-------------------------------------------------------------------------------
sub deploy_ops_bm_node {
	my $request = shift;
	my $callback = shift;
	my $doreq = shift;
	
	@ARGV = @{$request->{arg}};
	Getopt::Long::Configure("bundling");
	Getopt::Long::Configure("no_pass_through");

	my $node = $request->{node}->[0];
	
	my $help;
	my $version;
	my $img_name;
    my $hostname;
	my $fixed_ip;
	my $netmask;
	
    if(!GetOptions(
            'h|help'      => \$help,
            'v|version'   => \$version,
            'image=s'     => \$img_name,
			'host=s'      => \$hostname,
			'ip=s'        => \$fixed_ip,
			'mask=s'      => \$netmask,
       ))
    {
        &deploy_ops_bm_node_usage($callback);
        return 1;
    }
    # display the usage if -h or --help is specified
    if ($help) {
        &deploy_ops_bm_node_usage($callback);
        return 0;
    }
    # display the version statement if -v or --verison is specified
    if ($version)
    {
        my $rsp={};
        $rsp->{data}->[0]= xCAT::Utils->Version();
        $callback->($rsp);
        return 0;
    }
	#print "node=$node, image=$img_name, host=$hostname, ip=$fixed_ip, mask=$netmask\n";

	#validate the image name
    my $osimagetab = xCAT::Table->new('osimage', -create=>1);
	my $ref = $osimagetab->getAttribs({imagename => $img_name}, 'imagename');
	if (!$ref) {
		$callback->({error=>["Invalid image name: $img_name."],errorcode=>[1]});
		return 1;  
	}

	#check if the fixed ip is within the xCAT management network.
	#get the master ip address for the node then check if the master ip and 
	#the OpenStack fixed_ip are on the same subnet.
	#my $same_nw = 0;
	#my $master = xCAT::TableUtils->GetMasterNodeName($node);
	#my $master_ip = xCAT::NetworkUtils->toIP($master);
	#if (xCAT::NetworkUtils::isInSameSubnet($master_ip, $fixed_ip, $netmask, 0)) {
	#	$same_nw = 1;
	#}
	   
	
	#add config_ops_bm_node to the node's postbootscript
	my $script = "config_ops_bm_node $hostname $fixed_ip $netmask";
	add_postscript($callback, $node, $script);

    #run nodeset 
	my $cmd = qq~osimage=$img_name~;
	my $output = xCAT::Utils->runxcmd(
		{command => ["nodeset"],
		 node    => [$node], 
		 arg     => [$cmd]},
		$doreq, -1, 1);
	if ($::RUNCMD_RC != 0) {
		my $rsp;
		push @{$rsp->{data}}, "nodeset:";
		push @{$rsp->{data}}, "$output";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}		
 
    #deploy the node now, supported nodehm.mgt values: ipmi, blade,fsp, hmc.
    my $hmtab  = xCAT::Table->new('nodehm');
	my $hment = $hmtab->getNodeAttribs($node,['mgt']);
	if ($hment && $hment->{'mgt'}) {
		my $mgt = $hment->{'mgt'};
		if ($mgt eq 'ipmi') { 
			deploy_bmc_node($callback, $doreq, $node);
		} elsif (($mgt eq 'blade') || ($mgt eq 'fsp')) {
			deploy_blade($callback, $doreq, $node);
		} elsif ($mgt eq 'hmc') {
			deploy_hmc_node($callback, $doreq, $node);
		} else {
			my $rsp;
			push @{$rsp->{data}}, "Node $node: nodehm.mgt=$mgt is not supported in the OpenStack cloud.";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}
	} else {
		#nodehm.mgt must setup for node 
		my $rsp;
		push @{$rsp->{data}}, "Node $node: nodehm.mgt cannot be empty in order to deploy.";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

}

# Deploy a rack-mounted node
sub deploy_bmc_node {
	my $callback = shift;
	my $doreq = shift;
	my $node = shift;

    #set boot order
	my $cmd = qq~net~;
	my $output = xCAT::Utils->runxcmd(
		{command => ["rsetboot"],
		 node    => [$node], 
		 arg     => [$cmd]},
		$doreq, -1, 1);
	if ($::RUNCMD_RC != 0) {
		my $rsp;
		push @{$rsp->{data}}, "rsetboot:";
		push @{$rsp->{data}}, "$output";
		xCAT::MsgUtils->message("E", $rsp, $callback);
	}		
	
    #reboot the node
	my $cmd = qq~boot~;
	my $output = xCAT::Utils->runxcmd(
		{command => ["rpower"],
		 node    => [$node], 
		 arg     => [$cmd]},
		$doreq, -1, 1);
	if ($::RUNCMD_RC != 0) {
		my $rsp;
		push @{$rsp->{data}}, "rpower:";
		push @{$rsp->{data}}, "$output";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}
}

# Deploy a blade or fsp controlled node
sub deploy_blade {
	my $callback = shift;
	my $doreq = shift;
	my $node = shift;

    #set boot order
	my $cmd = qq~net~;
	my $output = xCAT::Utils->runxcmd(
		{command => ["rbootseq"],
		 node    => [$node], 
		 arg     => [$cmd]},
		$doreq, -1, 1);
	if ($::RUNCMD_RC != 0) {
		my $rsp;
		push @{$rsp->{data}}, "rbootseq:";
		push @{$rsp->{data}}, "$output";
		xCAT::MsgUtils->message("E", $rsp, $callback);
	}		
	
    #reboot the node
	my $cmd = qq~boot~;
	my $output = xCAT::Utils->runxcmd(
		{command => ["rpower"],
		 node    => [$node], 
		 arg     => [$cmd]},
		$doreq, -1, 1);
	if ($::RUNCMD_RC != 0) {
		my $rsp;
		push @{$rsp->{data}}, "rpower:";
		push @{$rsp->{data}}, "$output";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}	
}

# Deploy a node controlled by HMC
sub deploy_hmc_node {
	my $callback = shift;
	my $doreq = shift;
	my $node = shift;

	my $output = xCAT::Utils->runxcmd(
		{command => ["rnetboot"],
		 node    => [$node]},
		$doreq, -1, 1);
	if ($::RUNCMD_RC != 0) {
		my $rsp;
		push @{$rsp->{data}}, "rnetboot:";
		push @{$rsp->{data}}, "$output";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}	
}


#-------------------------------------------------------------------------------

=head3  cleanup_ops_bm_node
	This is a internel command called by OpenStack xCAT-baremetal driver.
	It undoes all the changes made by deploy_ops_bm_node command. It removes
	the config_ops_bmn_ode postbootscript from the postscript table for the 
	node, removes the alias ip and then power off the node.
=cut

#-------------------------------------------------------------------------------
sub cleanup_ops_bm_node {
	my $request = shift;
	my $callback = shift;
	my $doreq = shift;
	
	@ARGV = @{$request->{arg}};
	Getopt::Long::Configure("bundling");
	Getopt::Long::Configure("no_pass_through");

	my $node = $request->{node}->[0];
	
	my $help;
	my $version;
 	my $fixed_ip;
	
    if(!GetOptions(
            'h|help'      => \$help,
            'v|version'   => \$version,
			'ip=s'        => \$fixed_ip,
       ))
    {
        &cleanup_ops_bm_node_usage($callback);
        return 1;
    }
    # display the usage if -h or --help is specified
    if ($help) {
        &cleanup_ops_bm_node_usage($callback);
        return 0;
    }
    # display the version statement if -v or --verison is specified
    if ($version)
    {
        my $rsp={};
        $rsp->{data}->[0]= xCAT::Utils->Version();
        $callback->($rsp);
        return 0;
    }
	#print "node=$node, ip=$fixed_ip\n";   
	
	#removes the config_ops_bm_node postbootscript from the postscripts table
	remove_postscript($callback, $node, "config_ops_bm_node");


	#run updatenode to remove the ip alias 
	my $cmd = qq~-P deconfig_ops_bm_node $fixed_ip~;
	my $output = xCAT::Utils->runxcmd(
		{command => ["updatenode"],
		 node    => [$node], 
		 arg     => [$cmd]},
		$doreq, -1, 1);
	if ($::RUNCMD_RC != 0) {
		my $rsp;
		push @{$rsp->{data}}, "updatenode:";
		push @{$rsp->{data}}, "$output";
		xCAT::MsgUtils->message("E", $rsp, $callback);
	}
		
    #turn the node power off
	$ssh_ok = 0;
	my $cmd = qq~stat~;
	my $output = xCAT::Utils->runxcmd(
		{command => ["rpower"],
		 node    => [$node], 
		 arg     => [$cmd]},
		$doreq, -1, 1);

	if ($::RUNCMD_RC != 0) {
		my $rsp;
		push @{$rsp->{data}}, "rpower:";
		push @{$rsp->{data}}, "$output";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}   else {
		if ($output !~ /: off/) {
			#power off the node
			my $cmd = qq~off~;
			my $output = xCAT::Utils->runxcmd(
				{command => ["rpower"],
				 node    => [$node], 
				 arg     => [$cmd]},
				$doreq, -1, 1);
			if ($::RUNCMD_RC != 0) {
				my $rsp;
				push @{$rsp->{data}}, "rpower:";
				push @{$rsp->{data}}, "$output";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				return 1;
			}		
		}
	}
}

#-------------------------------------------------------
=head3  add_postscript

	It adds the 'config_ops_bm_node' postbootscript to the 
	postscript table for the given node.

=cut
#-------------------------------------------------------
sub  add_postscript {
    my $callback=shift;
    my $node=shift;
	my $script=shift;
	#print "script=$script\n";

    my $posttab=xCAT::Table->new("postscripts", -create =>1);
	my %setup_hash;
	my $ref = $posttab->getNodeAttribs($node,[qw(postscripts postbootscripts)]);
	my $found=0;
	if ($ref) {
		if (exists($ref->{postscripts})) {
		    my @a = split(/,/, $ref->{postscripts});
		    if (grep(/^config_ops_bm_node/, @a)) {
				$found = 1;
				if (!grep(/^$script$/, @a)) {
					#not exact match, must replace it with the new script
					for (@a) {
						s/^config_ops_bm_node.*$/$script/;
					}
					my $new_post = join(',', @a);
					$setup_hash{$node}={postscripts=>"$new_post"};
				}
			}
		}
		

		if (exists($ref->{postbootscripts})) {
		    my $post=$ref->{postbootscripts};
		    my @old_a=split(',', $post);
		    if (grep(/^config_ops_bm_node/, @old_a)) {
				if (!grep(/^$script$/, @old_a)) {
					#not exact match, will replace it with new script
					for (@old_a) {
						s/^config_ops_bm_node.*$/$script/;
					}
					my $new_postboot = join(',', @old_a);
					$setup_hash{$node}={postbootscripts=>"$new_postboot"};
				}
		    } else {
				if (! $found) {
					$setup_hash{$node}={postbootscripts=>"$post,$script"};
				}
		    }
		} else {
            if (! $found) {
				$setup_hash{$node}={postbootscripts=>"$script"};
			}
		}
	} else {
		$setup_hash{$node}={postbootscripts=>"$script"};
	}

	if (keys(%setup_hash) > 0) {
	    $posttab->setNodesAttribs(\%setup_hash);
	}

    return 0;
}

#-------------------------------------------------------
=head3  remove_postscript

	It removes the 'config_ops_bm_node' postbootscript from 
	the postscript table for the given node.

=cut
#-------------------------------------------------------
sub  remove_postscript {
    my $callback=shift;
    my $node=shift;
	my $script=shift;

    my $posttab=xCAT::Table->new("postscripts", -create =>1);
	my %setup_hash;
	my $ref = $posttab->getNodeAttribs($node,[qw(postscripts postbootscripts)]);
	my $found=0;
	if ($ref) {
		if (exists($ref->{postscripts})) {
		    my @old_a = split(/,/, $ref->{postscripts});
		    my @new_a = grep(!/^$script/, @old_a);
			if (scalar(@new_a) != scalar(@old_a)) {
				my $new_post = join(',', @new_a);
				$setup_hash{$node}={postscripts=>"$new_post"};
			}
		}

		if (exists($ref->{postbootscripts})) {
		    my @old_b = split(/,/, $ref->{postbootscripts});
		    my @new_b = grep(!/^$script/, @old_b);
			if (scalar(@new_b) != scalar(@old_b)) {
				my $new_post = join(',', @new_b);
				$setup_hash{$node}={postbootscripts=>"$new_post"};
			}
		}

	}
	
	if (keys(%setup_hash) > 0) {
	    $posttab->setNodesAttribs(\%setup_hash);
	}

    return 0;
}


#-------------------------------------------------------------------------------

=head3  opsaddbmnode_usage
	The usage text for opsaddbmnode command.
=cut

#-------------------------------------------------------------------------------
sub opsaddbmnode_usage {
    my $cb=shift;
    my $rsp={};

    $rsp->{data}->[0]= "Usage: opsaddbmnode -h";
    $rsp->{data}->[1]= "       opsaddbmnode -v";
    $rsp->{data}->[2]= "       opsaddbmnode <noderange> -s <service_host>";
    $cb->($rsp);
}


#-------------------------------------------------------------------------------

=head3  opsaddimage_usage
	The usage text for opsaddimage command.
=cut

#-------------------------------------------------------------------------------
sub opsaddimage_usage {
    my $cb=shift;
    my $rsp={};

    $rsp->{data}->[0]= "Usage: opsaddimage -h";
    $rsp->{data}->[1]= "       opsaddimage -v";
    $rsp->{data}->[2]= "       opsaddimage <image1,image2...> [-n <new_name1,new_name2...> -c <controller>";
    $cb->($rsp);
}

#-------------------------------------------------------------------------------

=head3   deploy_ops_bm_node_usage
	The usage text for deploy_ops_bm_node command.
=cut

#-------------------------------------------------------------------------------
sub deploy_ops_bm_node_usage {
    my $cb=shift;
    my $rsp={};

    $rsp->{data}->[0]= "Usage: deploy_ops_bm_node -h";
    $rsp->{data}->[1]= "       deploy_ops_bm_node -v";
    $rsp->{data}->[2]= "       deploy_ops_bm_node <node> --image <image_name> --host <ops_hostname> --ip <ops_fixed_ip> --mask <netmask>";
    $cb->($rsp);
}

#-------------------------------------------------------------------------------

=head3  cleanup_ops_bm_node_usage
	The usage text cleanup_ops_bm_node command.
=cut

#-------------------------------------------------------------------------------
sub cleanup_ops_bm_node_usage {
    my $cb=shift;
    my $rsp={};

    $rsp->{data}->[0]= "Usage: cleanup_ops_bm_node -h";
    $rsp->{data}->[1]= "       cleanup_ops_bm_node -v";
    $rsp->{data}->[2]= "       cleanup_ops_bm_node <node> [--ip <ops_fixed_ip>]";
    $cb->($rsp);
}

1;
