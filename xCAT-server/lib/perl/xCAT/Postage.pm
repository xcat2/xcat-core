# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Postage;

BEGIN
{
    $::XCATROOT =
        $ENV{'XCATROOT'} ? $ENV{'XCATROOT'}
      : -d '/opt/xcat'   ? '/opt/xcat'
      : '/usr';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::NodeRange;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::Template;
use xCAT::SvrUtils;
#use Data::Dumper;
use File::Basename;
use Socket;
use strict;

#-------------------------------------------------------------------------------

=head1    Postage

=head2    xCAT post script support.

This program module file is a set of utilities to support xCAT post scripts.

=cut

#----------------------------------------------------------------------------
#----------------------------------------------------------------------------

=head3  create_mypostscript_or_not 

        
     checks the site table precreatemypostscripts attribute.
     if 1, then
        creates all the /tftpboot/mypostscripts/mypostscript.<nodename> for
        all nodes in the input noderange
     if 0 then
        removes all files in /tftpboot/mypostscripts/*

     xCAT::Postage::create_mypostscript_or_not($request, $callback, $subreq);


=cut

#-----------------------------------------------------------------------------

sub create_mypostscript_or_not {
  my $request = shift;
  my $callback = shift;
  my $subreq = shift;
  my $notmpfiles = shift;
  my $nofiles = shift;
  my $nodes  = $request->{node};
  # require xCAT::Postage;

  my $tftpdir = xCAT::TableUtils::getTftpDir();

  #if precreatemypostscripts=1  
  # then create each mypostscript for each node in the node range in
  # /tftpboot/mypostscript/mypostscript.<nodename>
  #if precreatemypostscripts=0, then
  # remove all the files for the input noderange.
  # if called by updatenode, then recreate them. updatenode will remove at the
  # end of the command

  my @entries =  xCAT::TableUtils->get_site_attribute("precreatemypostscripts");
  if ($entries[0] ) {
        $entries[0] =~ tr/a-z/A-Z/;
        if ($entries[0] =~ /^(1|YES)$/ ) { 
            #if the site.precreatemypostscripts=1,
            # we will remove the mypostscript.$n.tmp files for the noderange 
            foreach my $n (@$nodes ) {
               unlink("$tftpdir/mypostscripts/mypostscript.$n.tmp");
            } 
            my $state;
            if ($request->{scripttype}) { $state = $request->{scripttype}->[0];}
            xCAT::Postage::makescript($nodes, $state, $callback,$notmpfiles,$nofiles);   
        }
  } else {
       #if the site.precreatemypostscripts=0,we will remove the mypostscript.$n
       # files for this noderange 
       foreach my $n (@$nodes ) {
               unlink("$tftpdir/mypostscripts/mypostscript.$n");
       } 
       # if called by updatenode, then recreate the files but no tmp extension
       # no matter what the setting of site.precreatepostscripts
       # if called by destiny.pm,  then just remove them and leave
        
       if ((defined($notmpfiles) && ($notmpfiles ==1)) && 
        (defined($nofiles) && ($nofiles ==0 ))) {  # this is for updatenode
            my $state;
            if ($request->{scripttype}) { $state = $request->{scripttype}->[0];}
            xCAT::Postage::makescript($nodes, $state, $callback,$notmpfiles,$nofiles);   
       } 
    }


}


#-----------------------------------------------------------------------------

=head3 makescript 
 
	create the  mypostscript file for each node in the noderange, according to 
   the template file  mypostscript.tmpl. The template file is 
   /opt/xcat/share/xcat/templates/mypostscript/mypostscript.tmpl by default.
   user also can copy it to /install/postscripts/, and customize it there.
   The mypostscript.tmpl is for all the images.

   If success, there is a mypostscript.$nodename for each node in the $tftpdir/mypostscripts/      	
	

    Arguments:
       array of nodes
       notmpfiles - ignore the settings in site precreatepostscripts and
                   only create mypostscript.<nodename>.  Do no use the .tmp
                   extension
       nofiles -  do not create mypostscript.<nodename> files, return the file
                  contents in an array.
    Returns:
    Globals:
        %::GLOBAL_TAB_HASH: in subvars_for_mypostscript(),
          it will read mypostscript.tmpl and 
           see what db attrs will be needed.
           The  %::GLOBAL_TAB_HASH will store all
           the db attrs needed. And the format of value setting looks like:
           $::GLOBAL_TAB_HASH{$tabname}{$key}{$attrib} = $value;
           %::GLOBAL_SN_HASH: getservicenode() will 
           get all the nodes in the servicenode table. And the 
           result will store in the %::GLOBAL_SN_HASH. The format:
           $::GLOBAL_SN_HASH{$servicenod1} = 1;
                        
    Error:
        none
    Example:
         
    Comments:
        none

=cut

#-----------------------------------------------------------------------------
  my $tmplerr;
  my $table;
  my $key;
  my $field;
  my $idir;
  my $node;
  my $os;
  my $profile;
  my $arch;
  my $provmethod;
  my $mn;
%::GLOBAL_TAB_HASH;
%::GLOBAL_SN_HASH;
%::GLOBAL_TABDUMP_HASH;

sub makescript { 
  my $nodes        = shift;
  my $nodesetstate    = shift;
  my $callback     = shift;
  my $notmpfiles     = shift;
  my $nofiles     = shift;
  $tmplerr=undef; #clear tmplerr since we are starting fresh

  #
  # check if nofiles = 1 , then there should be only one node input
  # 
  my $arraySize = @$nodes;
  if ((defined($nofiles)) && ($nofiles == 1) && ($arraySize > 1)) { 
        my $rsp;
        $rsp->{data}->[0]= "makescript called with nofiles=$nofiles, but more than one node input. This is a software error.";
        xCAT::MsgUtils->message("SE", $rsp, $callback,1);
        return ;
  } 
  my $installroot="/install";   # set default 
  my @entries =  xCAT::TableUtils->get_site_attribute("installdir"); 
  if($entries[0]) {
       $installroot = $entries[0];
  }
  my $tmpl="$installroot/postscripts/mypostscript.tmpl";
    
  unless ( -r $tmpl) {
       $tmpl="$::XCATROOT/share/xcat/templates/mypostscript/mypostscript.tmpl";
  }
    
  unless ( -r "$tmpl") {
         my $rsp;
         $rsp->{data}->[0]= "site.precreatemypostscripts is set to 1 or yes. No mypostscript template exists in directory /install/postscripts or $::XCATROOT/share/xcat/templates/mypostscript/mypostscript.tmpl.\n";
         xCAT::MsgUtils->message("SE", $rsp, $callback,1);
         return ;
  }

  my $outh;
  my $inh;
  $idir = dirname($tmpl);
  open($inh,"<",$tmpl);
  unless ($inh) {
     my $rsp;
     $rsp->{errorcode}->[0]=1;
     $rsp->{error}->[0]="Unable to open $tmpl, aborting\n";
     $callback->($rsp);
     return;
  }

  $mn = xCAT::Utils->noderangecontainsMn(@$nodes);

  my $inc;
  my $t_inc;
  my %table;
  my @tabs;
  my %dump_results;
  #First load input into memory..
  while (<$inh>) {
      my $line = $_;      
      if ($line !~/^##/ ) {
          $t_inc.=$line;
      }

      if( $line =~ /#TABLE:([^:]+):([^:]+):([^#]+)#/ ) {
           my $tabname=$1;
           my $key=$2;
           my $attrib = $3;
           $table{$tabname}{$key}{$attrib} = 1;
      }
  
     if( $line =~ /^tabdump\(([\w]+)\)/) {
           my $tabname = $1;
           if( $tabname !~ /^(auditlog|bootparams|chain|deps|domain|eventlog|firmware|hypervisor|iscsi|kvm_nodedata|mac|nics|ipmi|mp|ppc|ppcdirect|site|websrv|zvm|statelite|rack|hosts|prodkey|switch|node)/) {
               push @tabs, $tabname;
           }
     }

  }

  close($inh);

    

  ##
  #   $Tabname_hash{$key}{$attrib}=value
  #   for example: $MAC_hash{cn001}{mac}=9a:ca:be:a9:ad:02
  #
  #
  #%::GLOBAL_TAB_HASH = ();
  my $rc = collect_all_attribs_for_tables_in_template(\%table, $nodes, $callback);
  if($rc == -1) {
     #return;
  }

  #print Dumper(\%::GLOBAL_TAB_HASH);

  #print Dumper(\@tabs); 
  dump_all_attribs_in_tabs(\@tabs,\%::GLOBAL_TABDUMP_HASH, $callback);
  #print Dumper(\%::GLOBAL_TABDUMP_HASH);

  my %script_fp;    
  my $allattribsfromsitetable;

  # read all attributes for the site table and write an export   
  # only run this function once for one command with noderange
  $allattribsfromsitetable = getAllAttribsFromSiteTab();

  # get the net', 'mask', 'gateway' from networks table
  my $nets = getNetworks(); 

  # For AIX, get the password and cryptmethod for system root
  my $aixrootpasswdvars = getAIXPasswdVars();

  #%image_hash is used to store the attributes in linuximage and osimage tabs
  my %image_hash;
  getLinuximage(\%image_hash);

  # get postscript and postscript
  my $script_hash = xCAT::Postage::getScripts($nodes, \%image_hash);

  my $tftpdir = xCAT::TableUtils::getTftpDir();

  getservicenode();
  #print Dumper(\%::GLOBAL_SN_HASH);
  #
  my $scriptdir = "$tftpdir/mypostscripts/";
  if( ! (-d $scriptdir )) {
      mkdir($scriptdir,0777);
  }
  # if $notmpfiles not set or precreatemypostscripts=0 or not defined
  # then create the mypostscript.<namename> file with a .tmp extension
  my $postfix;  
  if ((!defined($notmpfiles)) || ($notmpfiles == 0)) {
    my @entries =xCAT::TableUtils->get_site_attribute("precreatemypostscripts");
    if ($entries[0] ) {  # not 1 or yes
      $entries[0] =~ tr/a-z/A-Z/;
      if ($entries[0] !~ /^(1|YES)$/ ) {
          $postfix="tmp";
      }   
    } else {  # or not defined
      $postfix="tmp";
    }
  }

  foreach my $n (@$nodes ) {
      $node = $n; 
      $inc = $t_inc;
      
      ##attributes from site tab
      #
      #my $master = $attribsfromnoderes->{$node}->{xcatmaster};
      my $master;
      my $noderesent;
      if( defined( $::GLOBAL_TAB_HASH{noderes}) && defined( $::GLOBAL_TAB_HASH{noderes}{$node}) ) {
          $master = $::GLOBAL_TAB_HASH{noderes}{$node}{xcatmaster};
          $noderesent = $::GLOBAL_TAB_HASH{noderes}{$node};
      }
     
      if( !defined($master) ) {
          $::GLOBAL_TAB_HASH{noderes}{$node}{xcatmaster} = $::XCATSITEVALS{master};
      } 
       
      #get the node type, service node or compute node
      my $nodetype = getNodeType($node);

      #print Dumper($noderesent);
      #routes 
      my $route_vars;
      if ($noderesent and defined($noderesent->{'routenames'}))
      {
  	my $rn=$noderesent->{'routenames'};
  	my @rn_a=split(',', $rn);
	my $routestab = xCAT::Table->new('routes');
	if ((@rn_a > 0) && ($routestab)) {
	    $route_vars .= "NODEROUTENAMES=$rn\n";
	    $route_vars .= "export NODEROUTENAMES\n";
	    foreach my $route_name (@rn_a) {
		my $routesent = $routestab->getAttribs({routename => $route_name}, 'net', 'mask', 'gateway', 'ifname');
		if ($routesent and defined($routesent->{net}) and defined($routesent->{mask})) {
		    my $val="ROUTE_$route_name=" . $routesent->{net} . "," . $routesent->{mask};
		    $val .= ",";
		    if (defined($routesent->{gateway})) {
			$val .= $routesent->{gateway};
		    }
		    $val .= ",";
		    if (defined($routesent->{ifname})) {
			$val .= $routesent->{ifname};
		    }
		    $route_vars .=  "$val\n";
		    $route_vars .= "export ROUTE_$route_name\n";
		}
	    }
	}
    }

    #NODESETSTATE

    ### vlan related item
    #  for #VLAN_VARS_EXPORT#
    my $vlan_vars;
    $vlan_vars = getVlanItems($node);

    ## get monitoring server and other configuration data for monitoring setup on nodes
    # for #MONITORING_VARS_EXPORT#
    my $mon_vars;
    $mon_vars = getMonItems($node);    


    #print "nodesetstate:$nodesetstate\n";
    ## OSPKGDIR export
    #  for #OSIMAGE_VARS_EXPORT# 
    if (!$nodesetstate) { $nodesetstate = getnodesetstate($node); }
    #print "nodesetstate:$nodesetstate\n";
   
    #my $et = $typehash->{$node};
    my $et = $::GLOBAL_TAB_HASH{nodetype}{$node}; 
    $provmethod = $et->{'provmethod'};
    $os = $et->{'os'};
    $arch = $et->{'arch'};
    $profile = $et->{'profile'};
    my $osimgname;

    if($provmethod !~ /^install$|^netboot$|^statelite$/){ # using imagename
      $osimgname = $provmethod;
    } 
             
    my $osimage_vars;
    $osimage_vars = getImageitems_for_node($node, \%image_hash, $nodesetstate);
     
    ## network
    # for #NETWORK_FOR_DISKLESS_EXPORT#
    #
    my $diskless_net_vars;
    my $setbootfromnet = 0;
    $diskless_net_vars = getDisklessNet($nets, \$setbootfromnet, $image_hash{$osimgname}{provmethod}); 
    
    ## postscripts
    # for #INCLUDE_POSTSCRIPTS_LIST# 
    #
    #

    my $postscripts;
    $postscripts = getPostScripts($node, $osimgname, $script_hash, $setbootfromnet, $nodesetstate, $arch);

    ## postbootscripts
    # for #INCLUDE_POSTBOOTSCRIPTS_LIST#
    my $postbootscripts;
    $postbootscripts = getPostbootScripts($node, $osimgname, $script_hash);




  #ok, now do everything else..
  #$inc =~ s/#XCATVAR:([^#]+)#/envvar($1)/eg;
  #$inc =~ s/#ENV:([^#]+)#/envvar($1)/eg;
  #$inc =~ s/#NODE#/$node/eg;
  $inc =~ s/\$NODE/$node/eg;
  $inc =~ s/#SITE_TABLE_ALL_ATTRIBS_EXPORT#/$allattribsfromsitetable/eg; 
  #$inc =~ s/#TABLE:([^:]+):([^:]+):([^:]+):BLANKOKAY#/tabdb($1,$2,$3,1)/eg; 
  $inc =~ s/#TABLE:([^:]+):([^:]+):([^#]+)#/xCAT::Template::tabdb($1,$2,$3)/eg; 
  $inc =~ s/#ROUTES_VARS_EXPORT#/$route_vars/eg; 
  $inc =~ s/#VLAN_VARS_EXPORT#/$vlan_vars/eg; 
  $inc =~ s/#AIX_ROOT_PW_VARS_EXPORT#/$aixrootpasswdvars/eg; 
  $inc =~ s/#MONITORING_VARS_EXPORT#/$mon_vars/eg; 
  $inc =~ s/#OSIMAGE_VARS_EXPORT#/$osimage_vars/eg; 
  $inc =~ s/#NETWORK_FOR_DISKLESS_EXPORT#/$diskless_net_vars/eg; 
  $inc =~ s/#INCLUDE_POSTSCRIPTS_LIST#/$postscripts/eg; 
  $inc =~ s/#INCLUDE_POSTBOOTSCRIPTS_LIST#/$postbootscripts/eg; 
  
  #$inc =~ s/#COMMAND:([^#]+)#/command($1)/eg;
  $inc =~ s/\$NTYPE/$nodetype/eg;
  $inc =~ s/tabdump\(([\w]+)\)/tabdump($1)/eg;
  $inc =~ s/#Subroutine:([^:]+)::([^:]+)::([^:]+):([^#]+)#/runsubroutine($1,$2,$3,$4)/eg;

  # we will create a file in /tftboot/mypostscript/mypostscript_<nodename> 
  if ((!defined($nofiles)) || ($nofiles == 0)) { #
      my $script;
      my $scriptfile; 
      if( defined( $postfix ) ) {
          $scriptfile = "$tftpdir/mypostscripts/mypostscript.$node.tmp";
      } else { 
          $scriptfile = "$tftpdir/mypostscripts/mypostscript.$node";
      }
      open($script, ">$scriptfile");

      unless ($script)
      {
         my $rsp;
         push @{$rsp->{data}}, "Could not open $scriptfile for writing.\n";
         xCAT::MsgUtils->message("E", $rsp, $callback);
         return 1;
      }
      $script_fp{$node}=$script;
      `/bin/chmod ugo+x $scriptfile`;  
      print $script $inc;    
      close($script_fp{$node});
    # TODO remove the blank lines
  } 
     
} #end foreach node
  
  undef(%::GLOBAL_TAB_HASH);
  undef(%::GLOBAL_SN_HASH);
  undef(%::GLOBAL_TABDUMP_HASH);
  # if the request is for an array not a created file
  if ((defined($nofiles)) &&($nofiles == 1)){ # return array
   my @scriptd = grep { /\S/ } split(/\n/,$inc);
   my @goodscriptd;
   foreach my $line (@scriptd){
     $line = $line . "\n";   # add new line
     push @goodscriptd, $line; 
   }
   return @goodscriptd;
  } else {  # files were created
    return 0;
  }
}

sub getservicenode
{
    # reads all nodes from the service node table
    my $servicenodetab = xCAT::Table->new('servicenode');
    unless ($servicenodetab)    # no  servicenode table
    {
        xCAT::MsgUtils->message('I', "Unable to open servicenode table.\n");
        return undef;

    }
    my @nodes = $servicenodetab->getAllNodeAttribs(['tftpserver'],undef,prefetchcache=>1); 
    $servicenodetab->close;
    foreach my $n (@nodes)
    {
        my $node = $n->{node};
        $::GLOBAL_SN_HASH{$node}=1
    }

    return 0; 
}

sub getAllAttribsFromSiteTab {
    
    my $result;
    
    # all attributes for the site table are in  %::XCATSITEVALS, so write an export
    # for them in the mypostscript file
    my $attribute;
    my $value;
    my $masterset = 0;
    foreach (keys(%::XCATSITEVALS))    # export the attribute
    {
        $attribute = $_;
        $attribute =~ tr/a-z/A-Z/;
        $value = $::XCATSITEVALS{$_};
        if ($attribute eq "MASTER")
        {
            $masterset = 1;
            $result .= "SITEMASTER='" . $value . "'\n";
            $result .= "export SITEMASTER\n";
           
            #if noderes.master for each node exists, the following value will be replaced.
            #$result .= "$attribute=" . $value . "\n";
            #$result .= "export $attribute\n";

        }
        else
        {    # not Master attribute
            $result .= "$attribute='" . $value . "'\n";
            $result .= "export $attribute\n";
        }
    }    # end site table attributes

    return $result;
}


###
#  This runs all the command defined in the template file that is being
#  used  to create the mypostscript file
#  For example
#  ENABLESSHBETWEENNODES=#Subroutine:xCAT::Template::enablesshbetweennodes:$NODE#
sub runsubroutine
{
   my $prefix          = shift;
   my $module          = shift;
   my $subroutine_name = shift;
   my $key = shift;  
   my $result;   
   
   if ($key eq "THISNODE" or $key eq '$NODE') {
      $key=$node;  
   }
   my $function = join("::",$prefix,$module,$subroutine_name);
   
   {
       no strict 'refs';
       $result=$function->($key); 
       use strict;
   }

   return $result;
}


sub getNodeType
{

    my $node   = shift;
    my $result;
   
    if ( $node =~ /^$mn$/) {
        $result="MN";
        return $result;
    }
    # see if this is a service or compute node?
    if ($::GLOBAL_SN_HASH{$node} == 1)
    {
        $result="service";
    }
    else
    {
        $result="compute";
    }

    return $result;
}


sub getVlanItems_t
{

    my $node = shift;
    my $result;

    #get vlan related items
    my $vlan;
    my $swtab = xCAT::Table->new("switch", -create => 0);
    if ($swtab) {
	my $tmp = $swtab->getNodeAttribs($node, ['vlan'],prefetchcache=>1);
	if (defined($tmp) && ($tmp) && $tmp->{vlan})
	{
	    $vlan = $tmp->{vlan};
	    $result .= "VLANID='" . $vlan . "'\n";
	    $result .= "export VLANID\n";
	} else {
	    my $vmtab = xCAT::Table->new("vm", -create => 0);
	    if ($vmtab) {
		my $tmp1 = $vmtab->getNodeAttribs($node, ['nics'],prefetchcache=>1);
		if (defined($tmp1) && ($tmp1) && $tmp1->{nics})
		{
		    $result .= "VMNODE='YES'\n";
		    $result .= "export VMNODE\n";
		    
		    my @nics=split(',', $tmp1->{nics});
		    foreach my $nic (@nics) {
			if ($nic =~ /^vl([\d]+)$/) {
			    $vlan = $1;
			    $result .= "VLANID='" . $vlan . "'\n";
			    $result .= "export VLANID\n";
			    last;
			}
		    }
		}
	    }
	}
	
	if ($vlan) {
	    my $nwtab=xCAT::Table->new("networks", -create =>0);
	    if ($nwtab) {
		my $sent = $nwtab->getAttribs({vlanid=>"$vlan"},'net','mask');
		my $subnet;
		my $netmask;
		if ($sent and ($sent->{net})) {
		    $subnet=$sent->{net};
		    $netmask=$sent->{mask};
		} 
		if (($subnet) && ($netmask)) {
		    my $hoststab = xCAT::Table->new("hosts", -create => 0);
		    if ($hoststab) {
			my $tmp = $hoststab->getNodeAttribs($node, ['otherinterfaces'],prefetchcache=>1);
			if (defined($tmp) && ($tmp) && $tmp->{otherinterfaces})
			{
			    my $otherinterfaces = $tmp->{otherinterfaces};
			    my @itf_pairs=split(/,/, $otherinterfaces);
			    foreach (@itf_pairs) {
				my ($name,$ip)=split(/:/, $_);
				if(xCAT::NetworkUtils->ishostinsubnet($ip, $netmask, $subnet)) {
				    if ($name =~ /^-/ ) {
					$name = $node.$name;
				    }
				    $result .= "VLANHOSTNAME='" . $name . "'\n";
				    $result .= "export VLANHOSTNAME\n";
				    $result .= "VLANIP='" . $ip . "'\n";
				    $result .= "export VLANIP\n";
				    $result .= "VLANSUBNET='" . $subnet . "'\n";
				    $result .= "export VLANSUBNET\n";
				    $result .= "VLANNETMASK='" . $netmask . "'\n";
				    $result .= "export VLANNETMASK\n";
				    last;
				}
			    }	    
			}
		    }
		}
	    }
	}
    }



   return $result;
}

sub getAIXPasswdVars
{
     my $result;
     if ($^O =~ /^aix/i)  {
         require xCAT::PPCdb;
         my $et = xCAT::PPCdb::get_usr_passwd('system', 'root');
         if ($et and defined($et->{'password'}))
         {
              $result .= "ROOTPW=" . $et->{'password'} . "\n";
              $result .= "export ROOTPW\n";
         }
         if ($et and defined($et->{'cryptmethod'}))
         {
              $result .= "CRYPTMETHOD=" . $et->{'cryptmethod'} . "\n";
              $result .= "export CRYPTMETHOD\n";
          }

     }
     return $result;
}


sub getVlanItems
{

    my $node = shift;
    my $result;

    #get vlan related items
    my $module_name="xCAT_plugin::vlan";
    eval("use $module_name;");
    if (!$@) {
	no strict  "refs";
	if (defined(${$module_name."::"}{getNodeVlanConfData})) {
	    my @tmp_scriptd=${$module_name."::"}{getNodeVlanConfData}->($node);
	    #print Dumper(@tmp_scriptd);
	    if (@tmp_scriptd > 0) {
		$result = join(" ", @tmp_scriptd);
	    }
	}  
    }


   return $result;
}


sub getMonItems
{

    my $node = shift;
    my $result;

    #get monitoring server and other configuration data for monitoring setup on nodes
    my %mon_conf = xCAT_monitoring::monitorctrl->getNodeConfData($node);
    foreach (keys(%mon_conf))
    {
        $result .= "$_='" . $mon_conf{$_} . "'\n";
        $result .= "export $_\n";
    }



    return $result;
}

sub getLinuximage
{
   
    my $image_hash  = shift;
    my $linuximagetab = xCAT::Table->new('linuximage', -create => 1);   

    my @et2 = $linuximagetab->getAllAttribs('imagename', 'pkglist', 'pkgdir', 'otherpkglist', 'otherpkgdir' );
    if( @et2 ) {
          foreach my $tmp_et2 (@et2) {
               my $imagename= $tmp_et2->{imagename};
               $image_hash->{$imagename}->{pkglist}= $tmp_et2->{pkglist};
               $image_hash->{$imagename}->{pkgdir} = $tmp_et2->{pkgdir}; 
               $image_hash->{$imagename}->{otherpkglist} = $tmp_et2->{otherpkglist}; 
               $image_hash->{$imagename}->{otherpkgdir} = $tmp_et2->{otherpkgdir}; 
          }
    }


}

sub getImageitems_for_node
{

    my $node = shift;
    my $image_hash = shift;
    my $nodesetstate = shift;
  
    my $result;

    #get packge names for extra rpms
    my $pkglist;
    my $ospkglist;
    if (   ($^O =~ /^linux/i)
        && ($provmethod)
        && ($provmethod ne "install")
        && ($provmethod ne "netboot")
        && ($provmethod ne "statelite"))
    {

        #this is the case where image from the osimage table is used
        #my $linuximagetab = xCAT::Table->new('linuximage', -create => 1);
        #(my $ref1) =
        #  $linuximagetab->getAttribs({imagename => $provmethod},
        #                             'pkglist', 'pkgdir', 'otherpkglist',
        #                             'otherpkgdir');
        my $ref1 = $image_hash->{$provmethod};
        if ($ref1)
        {
            if ($ref1->{'pkglist'})
            {
                $ospkglist = $ref1->{'pkglist'};
                if ($ref1->{'pkgdir'})
                {
                    $result .= "OSPKGDIR='" . $ref1->{'pkgdir'} . "'\n";
                    $result .= "export OSPKGDIR\n";
                }
            }
            if ($ref1->{'otherpkglist'})
            {
                $pkglist = $ref1->{'otherpkglist'};
                if ($ref1->{'otherpkgdir'})
                {
                    $result .= 
                      "OTHERPKGDIR='" . $ref1->{'otherpkgdir'} . "'\n";
                    $result .=  "export OTHERPKGDIR\n";
                }
            }
        }
    }
    else
    {
        my $stat        = "install";
        my $installroot = xCAT::TableUtils->getInstallDir();
        if ($profile)
        {
            my $platform = "rh";
            if ($os)
            {
                if    ($os =~ /rh.*/)     { $platform = "rh"; }
                elsif ($os =~ /centos.*/) { $platform = "centos"; }
                elsif ($os =~ /fedora.*/) { $platform = "fedora"; }
                elsif ($os =~ /SL.*/)     { $platform = "SL"; }
                elsif ($os =~ /sles.*/)   { $platform = "sles"; }
                elsif ($os =~ /ubuntu.*/) { $platform = "ubuntu"; }
                elsif ($os =~ /debian.*/) { $platform = "debian"; }
                elsif ($os =~ /aix.*/)    { $platform = "aix"; }
                elsif ($os =~ /AIX.*/)    { $platform = "AIX"; }
            }
            if (($nodesetstate) && ($nodesetstate eq "netboot" || $nodesetstate eq "statelite"))
            {
                $stat = "netboot";
            }

            $ospkglist =
              xCAT::SvrUtils->get_pkglist_file_name(
                                          "$installroot/custom/$stat/$platform",
                                          $profile, $os, $arch);
            if (!$ospkglist)
            {
                $ospkglist =
                  xCAT::SvrUtils->get_pkglist_file_name(
                                       "$::XCATROOT/share/xcat/$stat/$platform",
                                       $profile, $os, $arch);
            }

            $pkglist =
              xCAT::SvrUtils->get_otherpkgs_pkglist_file_name(
                                          "$installroot/custom/$stat/$platform",
                                          $profile, $os, $arch);
            if (!$pkglist)
            {
                $pkglist =
                  xCAT::SvrUtils->get_otherpkgs_pkglist_file_name(
                                       "$::XCATROOT/share/xcat/$stat/$platform",
                                       $profile, $os, $arch);
            }
        }
    }
    #print "pkglist=$pkglist\n";
    #print "ospkglist=$ospkglist\n";
    require xCAT::Postage;
    if ($ospkglist)
    {
        my $pkgtext = xCAT::Postage::get_pkglist_tex($ospkglist);
        my ($envlist,$pkgtext) = xCAT::Postage::get_envlist($pkgtext);
        if ($envlist) {
           $result .= "ENVLIST='".$envlist."'\n";
           $result .= "export ENVLIST\n";
        }
        if ($pkgtext)
        {
            $result .= "OSPKGS='".$pkgtext."'\n";
            $result .= "export OSPKGS\n";
        }
    }

    if ($pkglist)
    {
        my $pkgtext = xCAT::Postage::get_pkglist_tex($pkglist);
        if ($pkgtext)
        {
            my @sublists = split('#NEW_INSTALL_LIST#', $pkgtext);
            my $sl_index = 0;
            foreach (@sublists)
            {
                $sl_index++;
                my $tmp = $_;
                my ($envlist, $tmp) = xCAT::Postage::get_envlist($tmp);
                if ($envlist) {
                    $result .= "ENVLIST$sl_index='".$envlist."'\n";
                    $result .= "export ENVLIST$sl_index\n";
                }
                $result .= "OTHERPKGS$sl_index='".$tmp."'\n";
                $result .= "export OTHERPKGS$sl_index\n";
            }
            if ($sl_index > 0)
            {
                $result .= "OTHERPKGS_INDEX=$sl_index\n";
                $result .= "export OTHERPKGS_INDEX\n";
            }
        }
    }


    # SLES sdk
    if ($os =~ /sles.*/)
    {
        my $installdir = $::XCATSITEVALS{'installdir'} ? $::XCATSITEVALS{'installdir'} : "/install";
        my $sdkdir = "$installdir/$os/$arch/sdk1";
        if (-e "$sdkdir")
        {
            $result .= "SDKDIR='" . $sdkdir . "'\n";
            $result .= "export SDKDIR\n";
        }
    }

    # check if there are sync files to be handled
    my $syncfile;
    if (   ($provmethod)
        && ($provmethod ne "install")
        && ($provmethod ne "netboot")
        && ($provmethod ne "statelite"))
    {
        #my $osimagetab = xCAT::Table->new('osimage', -create => 1);
        #if ($osimagetab)
        #{
        #    (my $ref) =
        #      $osimagetab->getAttribs(
        #                              {imagename => $provmethod}, 'osvers',
        #                              'osarch',     'profile',
        #                              'provmethod', 'synclists'
        #                              );
            my $ref = $image_hash->{$provmethod}; 
            if ($ref)
            {
                $syncfile = $ref->{'synclists'};
         #       if($ref->{'provmethod'}) {
#                    $provmethod = $ref->{'provmethod'};
         #       }
            }
        #}
    }
    if (!$syncfile)
    {
        my $stat = "install";
        if (($nodesetstate) && ($nodesetstate eq "netboot" || $nodesetstate eq "statelite")) {
            $stat = "netboot";
        }
        $syncfile =
          xCAT::SvrUtils->getsynclistfile(undef, $os, $arch, $profile, $stat);
    }
    if (!$syncfile)
    {
        $result .= "NOSYNCFILES=1\n";
        $result .= "export NOSYNCFILES\n";
    }

    return $result;
}

sub getNetworks
{
    my $nettab = xCAT::Table->new('networks');
    unless ($nettab) { 
        xCAT::MsgUtils->message("E", "Unable to open networks table");
        return undef 
    }
    my @nets = $nettab->getAllAttribs('net', 'mask', 'gateway');
         
    return \@nets;
}


sub getDisklessNet()
{
    my $nets = shift;
    my $setbootfromnet = shift;
    my $provmethod = shift;
   
    my $result;
    my $isdiskless     = 0;
    my $bootfromnet = 0;
    if (($arch eq "ppc64") || ($os =~ /aix.*/i))
    {

        # on Linux, the provmethod can be install,netboot or statelite,
        # on AIX, the provmethod can be null or image name
        #this is for Linux
        if (   ($provmethod)
            && (($provmethod eq "netboot") || ($provmethod eq "statelite")))
        {
            $isdiskless = 1;
        }
        
        if (   ($os =~ /aix.*/i)
            && ($provmethod)
            && ($provmethod ne "install")
            && ($provmethod ne "netboot")
            && ($provmethod ne "statelite"))
        {
            my $nimtype;
            my $nimimagetab = xCAT::Table->new('nimimage', -create => 1);
            if ($nimimagetab)
            {
                (my $ref) =
                  $nimimagetab->getAttribs({imagename => $provmethod},
                                           'nimtype');
                if ($ref)
                {
                    $nimtype = $ref->{'nimtype'};
                }
            }
            if ($nimtype eq 'diskless')
            {
                $isdiskless = 1;
            }
        }

        if ($isdiskless)
        {    
            (my $ip, my $mask, my $gw) = xCAT::Postage::net_parms($node, $nets); 
            if (!$ip || !$mask || !$gw)
            {
                xCAT::MsgUtils->message(
                    'S',
                    "Unable to determine IP, netmask or gateway for $node, can not set the node to boot from network"
                    );
            }
            else
            {
                $bootfromnet = 1;
                $result .= "NETMASK=$mask\n";
                $result .= "export NETMASK\n";
                $result .= "GATEWAY=$gw\n";
                $result .= "export GATEWAY\n";
            }
        }
    }
    $$setbootfromnet = $bootfromnet;    

    return $result;

}

sub  collect_all_attribs_for_tables_in_template
{
  my $table = shift;
  my $nodes = shift;
  my $callback = shift;
  my $blankok;
  if(defined($table) ) {
       foreach my $tabname (keys %$table) {
            my $key_hash = $table->{$tabname};
            my @keys = keys %$key_hash;
            my $key = $keys[0];
            my $attrib_hash = $table->{$tabname}->{$key};
            my @attribs = keys %$attrib_hash;
            my $tabh = xCAT::Table->new($tabname);
            unless ($tabh) {
                xCAT::MsgUtils->message(
                    'E',
                    "Unable to open the table: $table."
                    );
                return;
            }
           
            my $ent;
            my $bynode=0;
            #if ($key eq "THISNODE" or $key eq '$NODE') {
                if( $tabname =~ /^noderes$/ ) {
                    @attribs = (@attribs, "netboot", "tftpdir"); ## add the attribs which will be needed in other place.
                } 
                $ent = $tabh->getNodesAttribs($nodes,@attribs); 
                if ($ent) {
                    foreach my $node (@$nodes) {
                         if( $ent->{$node}->[0] ) {
                              foreach my $attrib (@attribs) {
                                  $::GLOBAL_TAB_HASH{$tabname}{$node}{$attrib} = $ent->{$node}->[0]->{$attrib};
                                  
                                  #for noderes.xcatmaster
                                  if ($tabname =~ /^noderes$/ && $attrib =~ /^xcatmaster$/ && ! exists($::GLOBAL_TAB_HASH{noderes}{$node}{xcatmaster}))
                                  {
                                      my $value;
                                      $value = xCAT::NetworkUtils->my_ip_facing($node);
                                      if ($value eq "0")
                                      {
                                         undef($value);
                                      }
                                      $::GLOBAL_TAB_HASH{$tabname}{$node}{$attrib} = $value;
                                  }

                                  # for nodetype.os and nodetype.arch
                                  if ($^O =~ /^linux/i  && $tabname =~ /^nodetype$/ && ($attrib =~ /^(os|arch)$/))
                                  {
                                       unless ( $::GLOBAL_TAB_HASH{nodetype}{$node}{'os'} or $::GLOBAL_TAB_HASH{nodetype}{$node}{'arch'})
                                       {
                                            my $rsp;
                                            push @{$rsp->{data}},
                                                             "No os or arch setting in nodetype table for $node.\n";
                                            xCAT::MsgUtils->message("E", $rsp, $callback);
                                            return -1;
                                       }
                                   }

                              }
                         } 

                         # for noderes.nfsserver and  noderes.tftpserver    
                         if( ! defined($::GLOBAL_TAB_HASH{noderes}) ||  !defined ($::GLOBAL_TAB_HASH{noderes}{$node} ) ||
                                                            !defined ($::GLOBAL_TAB_HASH{noderes}{$node}{xcatmaster} ) ) {
                              $::GLOBAL_TAB_HASH{noderes}{$node}{xcatmaster} = $::XCATSITEVALS{master};
                         } 
                              
                         if(!defined ($::GLOBAL_TAB_HASH{noderes}{$node}{nfsserver}) ) {
                             $::GLOBAL_TAB_HASH{noderes}{$node}{nfsserver} = $::GLOBAL_TAB_HASH{noderes}{$node}{xcatmaster};
                         } 
                         if(!defined ($::GLOBAL_TAB_HASH{noderes}{$node}{tftpserver}) ) {
                             $::GLOBAL_TAB_HASH{noderes}{$node}{tftpserver} = $::GLOBAL_TAB_HASH{noderes}{$node}{xcatmaster};
                         }
                         #if the values are not got, we will set them to ''; 
                         foreach my $attrib (@attribs) {
                             if( !defined($::GLOBAL_TAB_HASH{$tabname}) || !defined($::GLOBAL_TAB_HASH{$tabname}{$node}) ||  !defined($::GLOBAL_TAB_HASH{$tabname}{$node}{$attrib})) {
                                   $::GLOBAL_TAB_HASH{$tabname}{$node}{$attrib} = '';
                                  } 
                         } 
                        


                  }

            } 
            $tabh->close;
        #}     
    }
   
  }


}

sub dump_all_attribs_in_tabs 
{
   my $tabs     = shift;
   my $result   = shift;
   my $callback = shift;   

   my $rsp;
   my $tab;
   foreach $tab (@$tabs) {
       my $ptab = xCAT::Table->new("$tab"); 
       unless ($ptab) {
           push @{$rsp->{data}},
              "Unable to open $tab table";
           xCAT::MsgUtils->message("E", $rsp, $callback);
           return undef;
       }


       my $tabdetails = xCAT::Table->getTableSchema($tab);
       my $cols = $tabdetails->{cols};
  
       my $recs = $ptab->getAllEntries();  
       my $sum = @$recs;
       $tab =~ tr/a-z/A-Z/;
       my $res = "$tab"."_LINES=$sum\n";  
       $res .= "export $tab"."_LINES\n";
       my $num = 0;
       my $rec;
       foreach $rec (@$recs) {
           my $attrib;
           $num++;  
           my $values;       
           my $t; 
           foreach $attrib (@$cols) {
               my $val = $rec->{$attrib};
               # We use "||" as the delimiter of the attribute=value pair in each line.
               # Uses could put special characters in the comments attribute.
               # So we put the comments attribute as the last in the list.
               # The parsing could consider everything after "comments=" as the comments value, regardless of whether or not it had "||" in it.
               if( $attrib =~ /^comments$/) {
                   $t = $val;   
               } else {
                   $values .="$attrib=$val||";
                   if( $attrib =~ /^disable$/) {
                       $values .="comments=$t";   
                   }
               }                 
           } 
           $values="$tab"."_LINE$num=\'$values\'\n";
           $values .="export $tab"."_LINE$num\n";
           $res .= $values;     
       }
       $tab =~ tr/A-Z/a-z/;
       $result->{$tab} = $res;
   }  

}

sub tabdump
{
    my $tab =shift;
    my $value= $::GLOBAL_TABDUMP_HASH{$tab};

    return $value;
}


1;
#----------------------------------------------------------------------------

=head3   get_envlist

        extract environment variables list from pkglist text.
=cut

#-----------------------------------------------------------------------------
sub get_envlist
{
    my $envlist;
    my $pkgtext = shift;
    $envlist = join ' ', ($pkgtext =~ /#ENV:([^#^\n]+)#/g);
    $pkgtext =~ s/#ENV:[^#^\n]+#,?//g;
    return ($envlist, $pkgtext);
}
#----------------------------------------------------------------------------

=head3   get_pkglist_text

        read the pkglist file, expand it and return the content.
        the "pkglist file" input can be a comma-separated list of
           fully-qualified files

=cut

#-----------------------------------------------------------------------------
sub get_pkglist_tex
{
    my $allfiles_pkglist   = shift;
    my $allfiles_pkgtext;
    foreach my $pkglist (split(/,/, $allfiles_pkglist))
    {
        my $pkgtext;
        my @otherpkgs = ();
        if (open(FILE1, "<$pkglist"))
        {
            while (readline(FILE1))
            {
                chomp($_);    #remove newline
                s/\s+$//;     #remove trailing spaces
                s/^\s*//;     #remove leading blanks
                next if /^\s*$/;    #-- skip empty lines
                next
                  if (   /^\s*#/
                      && !/^\s*#INCLUDE:[^#^\n]+#/
                      && !/^\s*#NEW_INSTALL_LIST#/
                      && !/^\s*#ENV:[^#^\n]+#/);    #-- skip comments
                if (/^@(.*)/)
                {    #for groups that has space in name
                    my $save = $1;
                    if ($1 =~ / /) { $_ = "\@" . $save; }
                }
                push(@otherpkgs, $_);
            }
            close(FILE1);
        }
        if (@otherpkgs > 0)
        {
            $pkgtext = join(',', @otherpkgs);

            #handle the #INCLUDE# tag recursively
            my $idir         = dirname($pkglist);
            my $doneincludes = 0;
            while (not $doneincludes)
            {
                $doneincludes = 1;
                if ($pkgtext =~ /#INCLUDE:[^#^\n]+#/)
                {
                    $doneincludes = 0;
                    $pkgtext =~ s/#INCLUDE:([^#^\n]+)#/includefile($1,$idir)/eg;
                }
            }
        }
        $allfiles_pkgtext = $allfiles_pkgtext.",".$pkgtext;
    }
    $allfiles_pkgtext =~ s/^(,)+//;
    $allfiles_pkgtext =~ s/(,)+$//;
    return $allfiles_pkgtext;
}

#----------------------------------------------------------------------------

=head3   includefile

        handles #INCLUDE# in otherpkg.pkglist file
=cut

#-----------------------------------------------------------------------------
sub includefile
{
    my $file = shift;
    my $idir = shift;
    my @text = ();
    unless ($file =~ /^\//)
    {
        $file = $idir . "/" . $file;
    }

    open(INCLUDE, $file) || \return "#INCLUDEBAD:cannot open $file#";

    while (<INCLUDE>)
    {
        chomp($_);    #remove newline
        s/\s+$//;     #remove trailing spaces
        next if /^\s*$/;    #-- skip empty lines
        next
          if (   /^\s*#/
              && !/^\s*#INCLUDE:[^#^\n]+#/
              && !/^\s*#NEW_INSTALL_LIST#/
              && !/^\s*#ENV:[^#^\n]+#/);   #-- skip comments
        if (/^@(.*)/)
        {    #for groups that has space in name
            my $save = $1;
            if ($1 =~ / /) { $_ = "\@" . $save; }
        }
        push(@text, $_);
    }

    close(INCLUDE);

    return join(',', @text);
}

#----------------------------------------------------------------------------

=head3   getnodesetstate

        Determine the nodeset stat.
=cut

#-----------------------------------------------------------------------------
sub getnodesetstate
{
    my $node = shift;
    return xCAT::SvrUtils->get_nodeset_state($node,prefetchcache=>1);
}

sub net_parms
{
    my $ip = shift;
    my $nets = shift;
    $ip = xCAT::NetworkUtils->getipaddr($ip);
    if (!$ip)
    {
        xCAT::MsgUtils->message("S", "Unable to resolve $ip");
        return undef;
    }
 
    if(!defined($nets) ) {  
        my $nettab = xCAT::Table->new('networks');
        unless ($nettab) { return undef }
        my @tmp_nets = $nettab->getAllAttribs('net', 'mask', 'gateway'); 
        $nets = \@tmp_nets;
    }
    foreach (@$nets)
    {
        my $net  = $_->{'net'};
        my $mask = $_->{'mask'};
        my $gw   = $_->{'gateway'};
        if($gw eq '<xcatmaster>')
        {
             if(xCAT::NetworkUtils->ip_forwarding_enabled())
             {
                 $gw = xCAT::NetworkUtils->my_ip_in_subnet($net, $mask);
             }
             else
             {
                 $gw = '';
             }
        }
        if (xCAT::NetworkUtils->ishostinsubnet($ip, $mask, $net))
        {
            return ($ip, $mask, $gw);
        }
    }
    xCAT::MsgUtils->message(
        "S",
        "xCAT BMC configuration error, no appropriate network for $ip found in networks, unable to determine netmask"
        );
}


sub getScripts
{

    my $nodes = shift;
    my $image_hash = shift;
    my %script_hash;    #used to reduce duplicates
 
   
    my $posttab    = xCAT::Table->new('postscripts');
    my $ostab    = xCAT::Table->new('osimage');
    # get the xcatdefaults entry in the postscripts table
    my $et        =
      $posttab->getAttribs({node => "xcatdefaults"},
                           'postscripts', 'postbootscripts');
    $script_hash{default_post} = $et->{'postscripts'}; 
    $script_hash{default_postboot} = $et->{'postbootscripts'}; 
     
   
    my @et2 = $ostab->getAllAttribs('imagename', 'postscripts', 'postbootscripts', 'osvers','osarch','profile','provmethod','synclists');
    if( @et2 ) {
          foreach my $tmp_et2 (@et2) {
               my $imagename= $tmp_et2->{imagename};
               $script_hash{osimage_post}{$imagename}= $tmp_et2->{postscripts};
               $script_hash{osimage_postboot}{$imagename} = $tmp_et2->{postbootscripts};
               $image_hash->{$imagename}->{osvers} = $tmp_et2->{osvers}; 
               $image_hash->{$imagename}->{osarch} = $tmp_et2->{osarch}; 
               $image_hash->{$imagename}->{profile} = $tmp_et2->{profile}; 
               $image_hash->{$imagename}->{provmethod} = $tmp_et2->{provmethod}; 
               $image_hash->{$imagename}->{synclists} = $tmp_et2->{synclists}; 
          }
    }

    my $et1 = $posttab->getNodesAttribs($nodes, 'postscripts', 'postbootscripts');
   
    if( $et1 ) {
        foreach my $node (@$nodes) {
            if( $et1->{$node}->[0] ) {
                $script_hash{node_post}{$node}=$et1->{$node}->[0]->{postscripts};
                $script_hash{node_postboot}{$node}=$et1->{$node}->[0]->{postbootscripts};
            }
        } 
    }


    return \%script_hash;
}

sub getPostScripts
{

    my $node        = shift;
    my $osimgname = shift;
    my $script_hash = shift;
    my $setbootfromnet = shift;
    my $nodesetstate = shift;
    my $arch = shift;
    my $result;
    my $ps;
    my %post_hash = ();    #used to reduce duplicates
    my $defscripts;
    
    if( defined($script_hash) && defined($script_hash->{default_post}) ) {
        $defscripts = $script_hash->{default_post};
    }
    if ($defscripts)
    {
        $result .= "# defaults-postscripts-start-here\n";

        foreach my $n (split(/,/, $defscripts))
        {
            if (!exists($post_hash{$n}))
            {
                $post_hash{$n} = 1;
                $result .= $n . "\n";
            }
        }
        $result .=  "# defaults-postscripts-end-here\n";
    }
    
    # get postscripts for images
    
    if(defined($script_hash) && defined($script_hash->{osimage_post} ) && defined ($script_hash->{osimage_post}->{$osimgname})) {
        $ps = $script_hash->{osimage_post}->{$osimgname}; 
    }
    if ($ps)
    {
        $result .= "# osimage-postscripts-start-here\n";

        foreach my $n (split(/,/, $ps))
        {
            if (!exists($post_hash{$n}))
            {
                $post_hash{$n} = 1;
                $result .= $n . "\n";
            }
        }

        $result .=  "# osimage-postscripts-end-here\n";
    }

    # get postscripts for node specific
    if(defined($script_hash) && defined($script_hash->{node_post} ) && defined ($script_hash->{node_post}->{$node})) {
        $ps = $script_hash->{node_post}->{$node}; 
    }

    if ($ps)
    {
        $result .= "# node-postscripts-start-here\n";
        foreach my $n (split(/,/, $ps))
        {
            if (!exists($post_hash{$n}))
            {
                $post_hash{$n} = 1;
                $result .= $n . "\n";
            }
        }
        $result .= "# node-postscripts-end-here\n";
    }

   
    if ($setbootfromnet)
    {
        $result .=  "setbootfromnet\n";
    }

    # add setbootfromdisk if the nodesetstate is install and arch is ppc64
    if (($nodesetstate) && ($nodesetstate eq "install") && ($arch eq "ppc64"))
    {
        $result .=  "setbootfromdisk\n";
    }


    return $result;
}


sub getPostbootScripts
{

    my $node = shift;
    my $osimgname = shift;
    my $script_hash = shift;
    my $result;
    my $ps;
    
   if( !defined($script_hash)) {
       return;
   }
   
    my %postboot_hash = ();                         #used to reduce duplicates
    my $defscripts;
   
    if( defined($script_hash->{default_postboot}) ) {
        $defscripts = $script_hash->{default_postboot};
    }

    if ($defscripts)
    {
        $result .=  "# defaults-postbootscripts-start-here\n";
        foreach my $n (split(/,/, $defscripts))
        {
            if (!exists($postboot_hash{$n}))
            {
                $postboot_hash{$n} = 1;
                $result .=   $n . "\n";
            }
        }
        $result .= "# defaults-postbootscripts-end-here\n";
    }

    # get postbootscripts for image
    my $ips; 
    if(defined($script_hash->{osimage_postboot} ) && defined ($script_hash->{osimage_postboot}->{$osimgname})) {
        $ips = $script_hash->{osimage_postboot}->{$osimgname}; 
    }

    if ($ips)
    {
        $result .= "# osimage-postbootscripts-start-here\n";
        foreach my $n (split(/,/, $ips))
        {
            if (!exists($postboot_hash{$n}))
            {
                $postboot_hash{$n} = 1;
                $result .=  $n . "\n";
            }
        }
        $result .= "# osimage-postbootscripts-end-here\n";
    }


    # get postscripts
    if(defined($script_hash->{node_postboot} ) && defined ($script_hash->{node_postboot}->{$node})) {
        $ps = $script_hash->{node_postboot}->{$node}; 
    }
    if ($ps)
    {
        $result .= "# node-postbootscripts-start-here\n";
        foreach my $n (split(/,/, $ps))
        {
            if (!exists($postboot_hash{$n}))
            {
                $postboot_hash{$n} = 1;
                $result .=  $n . "\n";
            }
        }
        $result .= "# node-postbootscripts-end-here\n";
    }

    return $result;
}




1;
