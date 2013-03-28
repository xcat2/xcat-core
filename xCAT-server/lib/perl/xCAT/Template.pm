#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
use xCAT::TZUtils;
use xCAT::WinUtils;

package xCAT::Template;
use strict;
use xCAT::Table;
use File::Basename;
use File::Path;
#use Data::Dumper;
use Sys::Syslog;
use xCAT::ADUtils; #to allow setting of one-time machine passwords
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::NetworkUtils;
BEGIN
{
      $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}



my $netdnssupport = eval {
    require Net::DNS;
    1;
};

my $tmplerr;
my $table;
my $key;
my $field;
my $idir;
my $node;
my %loggedrealms;
my $lastmachinepassdata;
my $localadminenabled; #indicate whether Windows template has local logins enabled or not
my %tab_replacement=(
     "noderes:nfsserver"=>"noderes:xcatmaster",
     "noderes:tftpserver"=>"noderes:xcatmaster",
    );



sub subvars { 
  my $self = shift;
  my $inf = shift;
  my $outf = shift;
  $tmplerr=undef; #clear tmplerr since we are starting fresh
  $node = shift;
  my $pkglistfile=shift;
  my $media_dir = shift;
  my $platform=shift;
  my $partitionfile=shift;
  my %namedargs = @_; #further expansion of this function will be named arguments, should have happened sooner.
  unless ($namedargs{reusemachinepass}) {
	$lastmachinepassdata->{password}="";
  }

  my $outh;
  my $inh;
  $idir = dirname($inf);
  open($inh,"<",$inf);
  unless ($inh) {
    return "Unable to open $inf, aborting";
  }
  mkpath(dirname($outf));
  open($outh,">",$outf);
  unless($outh) {
    return "Unable to open $outf for writing/creation, aborting";
  }
  my $inc;
  #First load input into memory..
  while (<$inh>) {
    $inc.=$_;
  }
  close($inh);
  my $master;
  #my $sitetab = xCAT::Table->new('site');
  my $noderestab = xCAT::Table->new('noderes');
  #(my $et) = $sitetab->getAttribs({key=>"master"},'value');
  my @masters = xCAT::TableUtils->get_site_attribute("master");
  my $tmp = $masters[0];
  if ( defined($tmp) ) {
      $master = $tmp;
  }
  my $ipfn = xCAT::NetworkUtils->my_ip_facing($node);
  if ($ipfn) {
      $master = $ipfn;
  }
  my $et = $noderestab->getNodeAttribs($node,['xcatmaster']);
  if ($et and $et->{'xcatmaster'}) { 
    $master = $et->{'xcatmaster'};
  }
  unless ($master) {
      die "Unable to identify master for $node";
  }
  $ENV{XCATMASTER}=$master;

  my @nodestatus = xCAT::TableUtils->get_site_attribute("nodestatus");
  my $tmp=$nodestatus[0];
  if( defined($tmp)  ){
	$ENV{NODESTATUS}=$tmp;
  }

  #replace the env with the right value so that correct include files can be found
  $inc =~ s/#ENV:([^#]+)#/envvar($1)/eg;

  #support multiple paths of osimage in rh/sles diskfull installation
  my @pkgdirs;
  if ( defined($media_dir) ) {
      @pkgdirs = split(",", $media_dir);
      my $source;
      my $c = 0;
      foreach my $pkgdir(@pkgdirs) {
          if( $platform =~ /^(rh|SL)$/ ) { 
              $source .=  "repo --name=pkg$c --baseurl=http://#TABLE:noderes:\$NODE:nfsserver#/$pkgdir\n";
          } elsif ($platform =~ /^(sles|suse)/) {
              my $http = "http://#TABLE:noderes:\$NODE:nfsserver#$pkgdir";
              $source .=  "         <listentry>
           <media_url>$http</media_url>
           <product>SuSE-Linux-pkg$c</product>
           <product_dir>/</product_dir>
           <ask_on_error config:type=\"boolean\">false</ask_on_error> <!-- available since openSUSE 11.0 -->
           <name>SuSE-Linux-pkg$c</name> <!-- available since openSUSE 11.1/SLES11 (bnc#433981) -->
         </listentry>";
          }
          $c++;
      }

      $inc =~ s/#INSTALL_SOURCES#/$source/g;
  }

  if ($pkglistfile) {
      #substitute the tag #INCLUDE_DEFAULT_PKGLIST# with package file name (for full install of  rh, centos,SL, esx fedora)
      $inc =~ s/#INCLUDE_DEFAULT_PKGLIST#/#INCLUDE:$pkglistfile#/g;
            
      #substitute the tag #INCLUDE_DEFAULT_PKGLIST_S# with package file name (for full install of sles)
      #substitute the tag #INCLUDE_DEFAULT_PERNLIST_S# with package file name (for full install sles
      #substitute the tag #INCLUDE_DEFAULT_RMPKGLIST_S# with package file name (for full install sles)
      $inc =~ s/#INCLUDE_DEFAULT_PKGLIST_S#/#INCLUDE_PKGLIST:$pkglistfile#/g;
      $inc =~ s/#INCLUDE_DEFAULT_PTRNLIST_S#/#INCLUDE_PTRNLIST:$pkglistfile#/g;
      $inc =~ s/#INCLUDE_DEFAULT_RMPKGLIST_S#/#INCLUDE_RMPKGLIST:$pkglistfile#/g;
  }

  if (("ubuntu" eq $platform) || ("debian" eq $platform)) {
    # since debian/ubuntu uses a preseed file instead of a kickstart file, pkglist
    # must be included via simple string replacement instead of using includefile()

    # the first line of $pkglistfile is the space-delimited package list
    # the additional lines are considered preseed directives and included as is

    if ($pkglistfile) {
      # handle empty and non-empty $pkglistfile's

      if (open PKGLISTFILE, "<$pkglistfile") {
        my $pkglist = '';
        # append preseed directive lines
        while (<PKGLISTFILE>) {
          chomp $_;
          if (/^\s*#.*/ ){
            next;
          }
          $pkglist .= " " . $_;
        }

        $inc =~ s/#INCLUDE_DEFAULT_PKGLIST_PRESEED#/$pkglist/g;
        close PKGLISTFILE;
      }
    } else {
      # handle no $pkglistfile
      $inc =~ s/#INCLUDE_DEFAULT_PKGLIST_PRESEED#//g;
    }
  }

  #do *all* includes, recursive and all
  my $doneincludes=0;
  while (not $doneincludes) {
    $doneincludes=1;
    if ($inc =~ /#INCLUDE_PKGLIST:[^#^\n]+#/) {
      $doneincludes=0;
      $inc =~ s/#INCLUDE_PKGLIST:([^#^\n]+)#/includefile($1, 0, 1)/eg;
    }
    if ($inc =~ /#INCLUDE_PTRNLIST:[^#^\n]+#/) {
      $doneincludes=0;
      $inc =~ s/#INCLUDE_PTRNLIST:([^#^\n]+)#/includefile($1, 0, 2)/eg;
    }
    if ($inc =~ /#INCLUDE_RMPKGLIST:[^#^\n]+#/) {
      $doneincludes=0;
      $inc =~ s/#INCLUDE_RMPKGLIST:([^#^\n]+)#/includefile($1, 0, 3)/eg;
    }
    if ($inc =~ /#INCLUDE:[^#^\n]+#/) {
      $doneincludes=0;
      $inc =~ s/#INCLUDE:([^#^\n]+)#/includefile($1, 0, 0)/eg;
    }
  }

  #Support hierarchical include
  $inc =~ s/#ENV:([^#]+)#/envvar($1)/eg;
  if ($inc =~ /#INCLUDE:[^#^\n]+#/) {
     $inc =~ s/#INCLUDE:([^#^\n]+)#/includefile($1, 0, 0)/eg;
  }

  #ok, now do everything else..
  $inc =~ s/#XCATVAR:([^#]+)#/envvar($1)/eg;
  $inc =~ s/#ENV:([^#]+)#/envvar($1)/eg;
  $inc =~ s/#MACHINEPASSWORD#/machinepassword()/eg;
  $inc =~ s/#TABLE:([^:]+):([^:]+):([^#]+)#/tabdb($1,$2,$3)/eg;
  $inc =~ s/#TABLEBLANKOKAY:([^:]+):([^:]+):([^#]+)#/tabdb($1,$2,$3,'1')/eg;
  $inc =~ s/#CRYPT:([^:]+):([^:]+):([^#]+)#/crydb($1,$2,$3)/eg;
  $inc =~ s/#COMMAND:([^#]+)#/command($1)/eg;
  $inc =~ s/#KICKSTARTNET#/kickstartnetwork()/eg;
  $inc =~ s/#ESXIPV6SETUP#/esxipv6setup()/eg;
  $inc =~ s/#INCLUDE_NOP:([^#^\n]+)#/includefile($1,1,0)/eg;
  $inc =~ s/#INCLUDE_PKGLIST:([^#^\n]+)#/includefile($1,0,1)/eg;
  $inc =~ s/#INCLUDE_PTRNLIST:([^#^\n]+)#/includefile($1,0,2)/eg;
  $inc =~ s/#INCLUDE_RMPKGLIST:([^#^\n]+)#/includefile($1,0,3)/eg;
  $inc =~ s/#INCLUDE:([^#^\n]+)#/includefile($1, 0, 0)/eg;
  $inc =~ s/#WINTIMEZONE#/xCAT::TZUtils::get_wintimezone()/eg;
  $inc =~ s/#WINPRODKEY:([^#]+)#/get_win_prodkey($1)/eg;
  $inc =~ s/#WINADJOIN#/windows_join_data()/eg;
  $inc =~ s/#WINDNSCFG#/windows_dns_cfg()/eg;
  $inc =~ s/#WINACCOUNTDATA#/windows_account_data()/eg;
  $inc =~ s/#WINDISABLENULLADMIN#/windows_disable_null_admin()/eg;
  $inc =~ s/#MANAGEDADDRESSMODE#/managed_address_mode()/eg;
  $inc =~ s/#HOSTNAME#/$node/g;

  my $nrtab = xCAT::Table->new("noderes");
  my $tftpserver = $nrtab->getNodeAttribs($node, ['tftpserver']);
  my $sles_sdk_media = "http://" . $tftpserver->{tftpserver} . $media_dir . "/sdk1";
  
  $inc =~ s/#SLES_SDK_MEDIA#/$sles_sdk_media/eg;

  #if user specify the partion file, replace the default partition strategy
  if ($partitionfile){
    #if the content of the partition file is definition replace the default is ok
    my $partcontent = '';
    my $scriptflag = 0;

    if ($partitionfile =~ /^s:(.*)/){
        $scriptflag = 1;
        $partitionfile = $1;
    }

    if (-r $partitionfile){
        open ($inh, "<", $partitionfile);
        while (<$inh>){
            $partcontent .= $_;
        }
        close ($inh);

        #the content of the specified file is a script which can write partition definition into /tmp/partitionfile
        if ($scriptflag){
            #for redhat/sl/centos/kvm/fedora
            if ($inc =~ /#XCAT_PARTITION_START#/) {
                my $tempstr = "%include /tmp/partitionfile\n";
                $inc =~ s/#XCAT_PARTITION_START#[\s\S]*#XCAT_PARTITION_END#/$tempstr/;
                #modify the content in the file, and write into %pre part
                $partcontent = "cat > /tmp/partscript << EOFEOF\n" . $partcontent . "\nEOFEOF\n";
                $partcontent .= "chmod 755 /tmp/partscript\n";
                $partcontent .= "/tmp/partscript\n";
                #replace the #XCA_PARTITION_SCRIPT#
                $inc =~ s/#XCA_PARTITION_SCRIPT#/$partcontent/;
            }
            #for sles/suse
            elsif ($inc =~ /<!-- XCAT-PARTITION-START -->/){
                my $tempstr = "<drive><device>XCATPARTITIONTEMP</device></drive>";
                $inc =~ s/<!-- XCAT-PARTITION-START -->[\s\S]*<!-- XCAT-PARTITION-END -->/$tempstr/;
                $partcontent = "cat > /tmp/partscript << EOFEOF\n" . $partcontent . "\nEOFEOF\n";
                $partcontent .= "chmod 755 /tmp/partscript\n";
                $partcontent .= "/tmp/partscript\n";
                $inc =~ s/#XCA_PARTITION_SCRIPT#/$partcontent/;
            }
        }
        else{
            $partcontent =~ s/\s$//;
            if ($inc =~ /#XCAT_PARTITION_START#/){
                $inc =~ s/#XCAT_PARTITION_START#[\s\S]*#XCAT_PARTITION_END#/$partcontent/;
            }
            elsif ($inc =~ /<!-- XCAT-PARTITION-START -->/){
                $inc =~ s/<!-- XCAT-PARTITION-START -->[\s\S]*<!-- XCAT-PARTITION-END -->/$partcontent/;
            }
        }
    }
  }

  if ($tmplerr) {
     close ($outh);
     return $tmplerr;
   }
  print $outh $inc;
  close($outh);
  return 0;
}
sub windows_disable_null_admin { 
#in the event where windows_account_data has not set an administrator user, we explicitly disable the administrator user 
	unless ($localadminenabled) {
		return "<RunSynchronousCommand wcm:action=\"add\">\r
                       <Order>100</Order>\r
                       <Path>cmd /c %systemroot%\\system32\\net.exe user Administrator /active:no</Path>\r
               </RunSynchronousCommand>";
	}
	return "";
}
sub windows_account_data { 
#this will add domain accounts if configured to be in active directory
#it will also put in an administrator password for local account, *if* specified
	my $passtab = xCAT::Table->new('passwd',-create=>0);
	my $useraccountxml="";
	$localadminenabled=0;
	if ($passtab) {
		my $passent = $passtab->getAttribs({key=>"system",username=>"Administrator"},['password']);
		if ($passent and $passent->{password}) {
			$useraccountxml="<AdministratorPassword>\r\n<Value>".$passent->{password}."</Value>\r\n<PlainText>true</PlainText>\r\n</AdministratorPassword>\r\n";
			$useraccountxml.="<!-- Plaintext=false would only protect against the most cursory over the shoulder glance, this implementation opts not to even give the illusion of privacy by only doing plaintext. -->\r\n";
			$localadminenabled=1;
		}
	}
			
	unless ($::XCATSITEVALS{directoryprovider} eq "activedirectory" and $::XCATSITEVALS{domain}) {
		return $useraccountxml;
	}
	my $domain;
        my $doment;
	my $domaintab = xCAT::Table->new('domain',-create=>0);
	if ($domaintab) {
           $doment = $domaintab->getNodeAttribs($node,['authdomain'],prefetchcache=>1);
	}
	if ($doment and $doment->{authdomain}) {
		$domain = $doment->{authdomain};
	} else {
		$domain = $::XCATSITEVALS{domain};
	}
	$useraccountxml.="<DomainAccounts><DomainAccountList>\r\n<DomainAccount wcm:action=\"add\">\r\n<Group>Administrators</Group>\r\n<Name>Domain Admins</Name>\r\n</DomainAccount>\r\n<Domain>".$domain."</Domain>\r\n</DomainAccountList>\r\n</DomainAccounts>\r\n";
		return $useraccountxml;
}
sub windows_dns_cfg {
	my $domain;
        my $doment;
	my $noderesent;
	my $noderestab = xCAT::Table->new("noderes",-create=>0);
	unless ($noderestab) { return ""; }
	$noderesent = $noderestab->getNodeAttribs($node,['nameservers'],prefetchcache=>1);
	unless ($noderesent and $noderesent->{nameservers}) { return ""; }
	my $mac="==PRINIC==";
	my $mactab = xCAT::Table->new('mac',-create=>0);
	if ($mactab) {
		my $macent = $mactab->getNodeAttribs($node,['mac'],prefetchcache=>1);
		if ($macent and $macent->{mac}) {
			$mac=$macent->{mac};
			$mac=~ s/!.*//;
			$mac=~ s/\|.*//;
			$mac =~ s/:/-/g;
		}
	}
	my $nameservers =  $noderesent->{nameservers};
	
	my $domaintab = xCAT::Table->new('domain',-create=>0);
	if ($domaintab) {
           $doment = $domaintab->getNodeAttribs($node,['authdomain'],prefetchcache=>1);
	}
	if ($doment and $doment->{authdomain}) {
		$domain = $doment->{authdomain};
	} else {
		$domain = $::XCATSITEVALS{domain};
	}
	my $componentxml = '<component name="Microsoft-Windows-DNS-Client" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'."\r\n<DNSDomain>$domain</DNSDomain>\r\n".
	"<Interfaces><Interface wcm:action=\"add\">\r\n<Identifier>$mac</Identifier>\r\n<DNSServerSearchOrder>\r\n";
	my $idx=1;
	foreach (split /,/,$nameservers) {
		$componentxml.="<IpAddress wcm:action=\"add\" wcm:keyValue=\"$idx\">$_</IpAddress>\r\n";
		$idx+=1;
	}
	$componentxml .= "</DNSServerSearchOrder>\r\n</Interface>\r\n</Interfaces>\r\n</component>\r\n";
	return $componentxml;
}
#this will examine table data, decide *if* a Microsoft-Windows-UnattendedJoin is warranted
#there are two variants in how to proceed:
#-Hide domain administrator from node: xCAT will use MACHINEPASSWORD to do joining to AD.  Currently requires SSL be enabled on DC.  Samba 4 TODO
#-Provide domain administrator credentials, avoiding the SSL scenario.  This is by default forbidden as it is high risk for exposing sensitive credentials.
# Also populate MachineObjectOU 
sub windows_join_data {
	unless ($::XCATSITEVALS{directoryprovider} eq "activedirectory" and $::XCATSITEVALS{domain}) {
		return "";
	}
	#we are still here, meaning configuration has a domain and activedirectory set, probably want to join..
	#TODO: provide a per-node 'disable' so that non-AD could be mixed into a nominally AD environment
	my $prejoin =1; 
	if (defined $::XCATSITEVALS{prejoinactivedirectory} and not  $::XCATSITEVALS{prejoinactivedirectory} ) {
		$prejoin = 0;
	}
	my $domain;
        my $doment;
	my $domaintab = xCAT::Table->new('domain',-create=>0);
	if ($domaintab) {
           $doment = $domaintab->getNodeAttribs($node,['ou','authdomain'],prefetchcache=>1);
	}
	my $ou;
	if ($doment and $doment->{ou}) {
		$ou = $doment->{ou};
	}
	if ($doment and $doment->{authdomain}) {
		$domain = $doment->{authdomain};
	} else {
		$domain = $::XCATSITEVALS{domain};
	}
	my $componentxml = '<component name="Microsoft-Windows-UnattendedJoin" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'."\r\n<Identification>\r\n<JoinDomain>".$domain."</JoinDomain>\r\n";
	if ($ou) {
		$componentxml .= "<MachineObjectOU>".$ou."</MachineObjectOU>\r\n";
	}
	if ($prejoin) {
		my $adinfo = machinepassword(wantref=>1); #TODO: needs rearranging in non prejoin case
		#a note, MS is incorrect when they document unsecure join as " UnsecureJoin is performed, by using a null session with a pre-existing account. This means there is no authentication to the domain controller when configuring the machine account; it is done anonymously".
		#the more informative bit is http://technet.microsoft.com/en-us/library/cc730845%28v=ws.10%29.aspx which says of 'securejoin': this method is actually less secure because the credentials reside in the ImageUnattend.xml file in plain text.  
		#xCAT is generating a one-time password that is kept as limited as is feasible for the deployment strategy
		#in theory, a domain join will either fail of the one-time password is compromised and changed, or domain
		#join will invalidate any 'snooped' one time password
		$componentxml .= "<MachinePassword>".$adinfo->{password}."</MachinePassword>\n<UnsecureJoin>true</UnsecureJoin>\n";
	} else { #this is the pass-through credentials case, currrently inaccessible until TODO, this must be used 
		#with care as used incorrectly, an LDAP manager account is at high risk of compromise
        	my $passtab = xCAT::Table->new('passwd',-create=>0);
	        unless ($passtab) { sendmsg([1,"Error authenticating to Active Directory"],$node); return; }
		my @adpents = $passtab->getAttribs({key=>'activedirectory'},['username','password','authdomain']);
		my $adpent;
		my $username;
		my $password;
		foreach $adpent (@adpents) {
			if ($adpent and $adpent->{authdomain} and $adpent->{authdomain} ne $domain) { next; }
			if ($adpent and $adpent->{username} and $adpent->{password}) {
				$username = $adpent->{username};
				$password = $adpent->{password};
				last;
			}
		}
		unless ($username and $password) { die "Missing active directory admin auth data from passwd table" }
		$componentxml .= "<Credentials><Domain>".$domain."</Domain>\r\n<Username>".$username."</Username>\r\n<Password>".$password."</Password>\r\n</Credentials>\r\n";
	}
	$componentxml .= "</Identification>\r\n</component>\r\n";
		
}
sub get_win_prodkey {
	my $osvariant = shift;
	my $keytab = xCAT::Table->new("prodkey",-create=>0);
	my $keyent;
	if ($keytab) {
	   $keyent = $keytab->getAttribs({product=>$osvariant},"key");
	}
	if ($keyent) { 
		return "<ProductKey><WillShowUI>OnError</WillShowUI><Key>".$keyent->{key}."</Key></ProductKey>";
	}
	if ($xCAT::WinUtils::kmskeymap{$osvariant}) {
		return "<ProductKey><WillShowUI>OnError</WillShowUI><Key>".$xCAT::WinUtils::kmskeymap{$osvariant}."</Key></ProductKey>";
	}
	return ""; #in the event that we have no specified key and no KMS key, then try with no key, user may have used some other mechanism 
} 

sub managed_address_mode {
	return $::XCATSITEVALS{managedaddressmode};
}
sub esxipv6setup {
 if ($::XCATSITEVALS{managedaddressmode} ne "autoula") { return ""; } # blank unless autoula
	my $hoststab;
      my $mactab = xCAT::Table->new('mac',-create=>0);
      my $ent = $mactab->getNodeAttribs($node,['mac']);
      my $suffix = $ent->{mac};
      $suffix = lc($suffix);
      unless ($mactab) { die "mac table should always exist prior to template processing when doing autoula"; }
 #in autoula, because ESXi weasel doesn't seemingly grok IPv6 at all, we'll have to do it in %pre
		unless ($hoststab) { $hoststab = xCAT::Table->new('hosts',-create=>1); }
		my $ulaaddr = autoulaaddress($suffix);
		$hoststab->setNodeAttribs($node,{ip=>$ulaaddr});
 return 'esxcfg-vmknic -i '.$ulaaddr.'/64 "Management Network"'."\n";
}

sub kickstartnetwork {
	my $line = "network --onboot=yes --bootproto=";
	my $hoststab;
      my $mactab = xCAT::Table->new('mac',-create=>0);
      unless ($mactab) { die "mac table should always exist prior to template processing when doing autoula"; }
      my $ent = $mactab->getNodeAttribs($node,['mac']);
      unless ($ent and $ent->{mac}) { die "missing mac data for $node"; }
      my $suffix = $ent->{mac};
      $suffix = lc($suffix);
	if ($::XCATSITEVALS{managedaddressmode} eq "autoula") {
		unless ($hoststab) { $hoststab = xCAT::Table->new('hosts',-create=>1); }
		$line .= "static --device=$suffix --noipv4 --ipv6=";
		my $ulaaddr = autoulaaddress($suffix);
		$hoststab->setNodeAttribs($node,{ip=>$ulaaddr});
		$line .= $ulaaddr;
	} elsif ($::XCATSITEVALS{managedaddressmode} =~ /static/)  {
		return "#KSNET static unsupported";
	} else {
		$line .= "dhcp --device=$suffix";
	}
	return $line;
}
sub autoulaaddress {
      my $suffix = shift;
      my $prefix = $::XCATSITEVALS{autoulaprefix};
      $suffix =~ /(..):(..:..):(..:..):(..)/;
      my $leadbyte = $1;
      my $mask = ((hex($leadbyte) & 2) ^ 2);
      if ($mask) {
        $leadbyte = hex($leadbyte) | $mask;
      } else {
        $leadbyte = hex($leadbyte) & 0xfd; #mask out the one bit
      }
      $suffix = sprintf("%02x$2ff:fe$3$4",$leadbyte);

      return $prefix.$suffix;
}

sub machinepassword {
    my %funargs = @_;
    if ($lastmachinepassdata->{password}) { #note, this should only happen after another call
			    #to subvars that does *not* request reuse
			    #the issue being avoiding reuse in the installmonitor case
			    #subvars function clears this if appropriate
	if ($funargs{wantref}) { 
		return $lastmachinepassdata;
	}
	return $lastmachinepassdata->{password};
    }
    my $passdata;
    my $domaintab = xCAT::Table->new('domain');
    $ENV{HOME}='/etc/xcat';
    $ENV{LDAPRC}='ad.ldaprc';
    my $ou;
    my $domain;
    if ($domaintab) {
        my $ouent = $domaintab->getNodeAttribs($node,['ou','authdomain'],prefetchcache=>1);
        if ($ouent and $ouent->{ou}) {
            $ou = $ouent->{ou};
        }
        if ($ouent and $ouent->{authdomain}) {
		$domain = $ouent->{authdomain};
	}
    }
    $passdata->{ou}=$ou;
    #my $sitetab = xCAT::Table->new('site');
    #unless ($sitetab) {
    #    return "ERROR: unable to open site table"; 
    #}
    #(my $et) = $sitetab->getAttribs({key=>"domain"},'value');
    unless ($domain) {
    my @domains =  xCAT::TableUtils->get_site_attribute("domain");
    my $tmp = $domains[0];
    if (defined($tmp)) {
        $domain = $tmp;
    } else {
        return "ERROR: no domain set in site table or in domain.authdomain for $node";
    }
    }
    $passdata->{domain}=$domain;
    my $realm = uc($domain);
    $realm =~ s/\.$//;
    $realm =~ s/^\.//;
    $ENV{KRB5CCNAME}="/tmp/xcat/krbcache.$realm.$$";
    unless ($loggedrealms{$realm}) {
        my $passtab = xCAT::Table->new('passwd',-create=>0);
        unless ($passtab) { sendmsg([1,"Error authenticating to Active Directory"],$node); return; }
	my @adpents = $passtab->getAttribs({key=>'activedirectory'},['username','password','authdomain']);
	my $adpent;
	my $username;
	my $password;
	foreach $adpent (@adpents) {
		if ($adpent and $adpent->{authdomain} and $adpent->{authdomain} ne $domain) { next; }
		if ($adpent and $adpent->{username} and $adpent->{password}) {
			$username = $adpent->{username};
			$password = $adpent->{password};
			last;
		}
	}
	unless ($username and $password) {
            return "ERROR: activedirectory entry missing from passwd table";
        }
        my $err = xCAT::ADUtils::krb_login(username=>$adpent->{username},password=>$adpent->{password},realm=>$realm);
        if ($err) {
            return "ERROR: authenticating to Active Directory";
        }
        $loggedrealms{$realm}=1;
    }
    #my $server = $sitetab->getAttribs({key=>'directoryserver'},['value']);
    my $server;
    my @servers = xCAT::TableUtils->get_site_attribute("directoryserver");
    my $tmp = $servers[0];
    if (defined($tmp)) {
        $server = $tmp;
    } else {
        $server = '';
        if ($netdnssupport) {
           my $res = Net::DNS::Resolver->new;
           my $query = $res->query("_ldap._tcp.$domain","SRV");
           if ($query) {
               foreach my $srec ($query->answer) {
                   $server = $srec->{target};
               }
           }
        }
        unless ($server) {
            sendmsg([1,"Unable to determine a directory server to communicate with, try site.directoryserver"]);
            return;
        }
    }
    $passdata->{dc} = $server;
    my %args = (
        node => $node,
        dnsdomain => $domain,
        directoryserver => $server,
        changepassondupe => 1,
    );
    if ($ou) { $args{ou} = $ou };
    my $data = xCAT::ADUtils::add_host_account(%args);
    if ($data->{error}) { 
        return "ERROR: ".$data->{error};
    } else {
	$passdata->{password}=$data->{password};
	$lastmachinepassdata=$passdata;
	if ($funargs{wantref}) { 
		return $passdata;
	}
        return $data->{password};
    }
}
sub includefile
{
    my $file = shift;
    my $special=shift;
    my $pkglist=shift; #1 means package list, 
                       #2 means pattern list, pattern list starts with @, 
                       #3 means remove package list, packages to be removed start with -.
    my $text = "";
    unless ($file =~ /^\//) {
      $file = $idir."/".$file;
    }

    open(INCLUDE,$file) || return "#INCLUDEBAD:cannot open $file#";
    
    my $pkgb = "";
    my $pkge = "";
    if ($pkglist) {
	if ($pkglist == 2) {
	    $pkgb = "<pattern>";
	    $pkge = "</pattern>";
	} else {
	    $pkgb = "<package>";
	    $pkge = "</package>";
	}
    } 
    while(<INCLUDE>) {
        if ($pkglist == 1) {
            s/#INCLUDE:/#INCLUDE_PKGLIST:/;
        }  elsif ($pkglist == 2) {
            s/#INCLUDE:/#INCLUDE_PTRNLIST:/;
        }  elsif ($pkglist == 3) {
            s/#INCLUDE:/#INCLUDE_RMPKGLIST:/;
        }

        if (( $_ =~ /^\s*#/ ) || ( $_ =~ /^\s*$/ )) { 
	    $text .= "$_";
        } else {
	    my $tmp=$_;
            chomp($tmp);  #remove return char
            $tmp =~ s/\s*$//;  #removes trailing spaces
	    next if (($pkglist == 1) && (($tmp=~/^\s*@/) || ($tmp=~/^\s*-/)));  #for packge list, do not include the lines start with @
	    if ($pkglist == 2) { #for pattern list, only include the lines start with @
		if ($tmp =~/^\s*@(.*)/) {
		    $tmp=$1;
		    $tmp =~s/^\s*//;  #removes leading spaces
		} else { next; }
	    } elsif ($pkglist == 3) { #for rmpkg list, only include the lines start with -
		if ($tmp =~/^\s*-(.*)/) {
		    $tmp=$1;
		    $tmp =~s/^\s*//;  #removes leading spaces
		} else { next; }
	    }
	    $text .= "$pkgb$tmp$pkge\n";
        }
    }
    
    close(INCLUDE);
    
    if ($special) {
	$text =~ s/\$/\\\$/g;
	$text =~ s/`/\\`/g;
    }

    chomp($text);
    return($text);
}

sub command
{
	my $command = shift;
	my $r;

#	if(($r = `$command`) == 0) {
#		chomp($r);
#		return($r);
#	}
#	else {
#		return("#$command: failed $r#");
#	}

	$r = `$command`;
	chomp($r);
	return($r);
}

sub envvar
{
	my $envvar = shift;

	if($envvar =~ /^\$/) {
		$envvar =~ s/^\$//;
	}

	return($ENV{$envvar});
}

sub genpassword {
#Generate a pseudo-random password of specified length
    my $length = shift;
    my $password='';
    my $characters= 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234567890';
    srand; #have to reseed, rand is not rand otherwise
    while (length($password) < $length) {
        $password .= substr($characters,int(rand 63),1);
    }
    return $password;
}

sub crydb
{
    my $result = tabdb(@_);
    # 1 - MD5, 5 - SHA256, 6 - SHA512
    unless (($result =~ /^\$1\$/) || ($result =~ /^\$5\$/) || ($result =~ /^\$6\$/)) {
        $result = crypt($result,'$1$'.genpassword(8));
    }
    return $result;
}
sub tabdb
{
	my $table = shift;
	my $key = shift;
	my $field = shift;
   my $blankok = shift;
   

   if( defined( %::GLOBAL_TAB_HASH) && defined( $::GLOBAL_TAB_HASH{$table} ) ) {
        if( !defined( $::GLOBAL_TAB_HASH{$table}{$key}) ) {
            return "''";   
        }
            
        if( defined($::GLOBAL_TAB_HASH{$table}{$key}{$field}) ) {
             return "'".$::GLOBAL_TAB_HASH{$table}{$key}{$field}."'";
        } else {
            return "''";   
        }
       
   }

    my $tabh = xCAT::Table->new($table);
    unless ($tabh) {
       $tmplerr="Unable to open table named $table";
       if ($table =~ /\.tab/) {
          $tmplerr .= " (.tab should not be specified as part of the table name in xCAT 2, as seems to be the case here)";
       }
      return "";
    }
    my $ent;
    my $bynode=0;
    if ($key eq "THISNODE" or $key eq '$NODE') {
      $ent = $tabh->getNodeAttribs($node,[$field]);
      $key="node=$node";
    } else {
      my %kp;
      foreach (split /,/,$key) {
        my $key;
        my $val;
        if ($_ eq 'THISNODE' or $_ eq '$NODE') {
            $bynode=1;
        } else {
            ($key,$val) = split /=/,$_;
            $kp{$key}=$val;
        }
      }
      if ($bynode) {
          my @ents = $tabh->getNodeAttribs($node,[keys %kp,$field]);
          my $tent; #Temporary ent
          TENT: foreach $tent (@ents) {
              foreach (keys %kp) {
                  unless ($kp{$_} eq $tent->{$_}) {
                      next TENT;
                  }
              } #If still here, we found it
             $ent = $tent;
              
          }
      } else {
          ($ent) = $tabh->getAttribs(\%kp,$field);
      }
    }
    $tabh->close;
    unless($ent and  defined($ent->{$field})) {
      unless ($blankok) {
         if ($field eq "xcatmaster") {
           my $ipfn = xCAT::NetworkUtils->my_ip_facing($node);
           if ($ipfn) {
             return $ipfn;
           }
         }
         #$tmplerr="Unable to find requested $field from $table, with $key";
         my $rep=get_replacement($table,$key,$field);
         if ($rep) {
            return tabdb($rep->[0], $rep->[1], $rep->[2]);
         } else {
            $tmplerr="Unable to find requested $field from $table, with $key"
         }
      }
      return "";
      #return "#TABLEBAD:$table:field $field not found#";
    }
    return $ent->{$field};


	#if($key =~ /^\$/) {
	#	$key =~ s/^\$//;
	#	$key = $ENV{$key};
	#}
	#if($field =~ /^\$/) {
	#	$field =~ s/^\$//;
	#	$field = $ENV{$field};
	#}
	#if($field == '*') {
	#	$field = 1;
	#	$all = 1;
	#}

	#--$field;

	#if($field < 0) {
	#	return "#TABLE:field not found#"
	#}

	#open(TAB,$table) || \
	#	return "#TABLE:cannot open $table#";

	#while(<TAB>) {
	#	if(/^$key(\t|,| )/) {
	#		m/^$key(\t|,| )+(.*)/;
	#		if($all == 1) {
	#			return "$2";
	#		}
	#		@fields = split(',',$2);
	#		if(defined $fields[$field]) {
	#			return "$fields[$field]";
	#		}
	#		else {
	#			return "#TABLE:field not found#"
	#		}
	#	}
	#}

	#close(TAB);
	#return "#TABLE:key not found#"
}

sub get_replacement {
    my $table=shift;
    my $key=shift;
    my $field=shift;
    my $rep;
    if (exists($tab_replacement{"$table:$field"})) {
	my $repstr=$tab_replacement{"$table:$field"};
	if ($repstr) {
	    my @a=split(':', $repstr);
	    if (@a > 2) {
		$rep=\@a;
	    } else {
		$rep->[0]=$a[0];
                $rep->[1]=$key;
                $rep->[2]=$a[1];
	    }
	}
    }
    return $rep;
}





#-----------------------------------------------------------------------------

=head3 subvars_for_mypostscript 
 
	create the  mypostscript file for each node in the noderange, according to 
        the template file  mypostscript.tmpl. The template file is 
        /opt/xcat/share/xcat/templates/mypostscript/mypostscript.tmpl by default. and
        uses also can copy it to /install/postscripts/, and customize it there.
        The mypostscript.tmpl is for all the images.

        If success, there is a mypostscript.$nodename for each node in the $tftpdir/mypostscripts/      	
	

    Arguments:
       hostname 
    Returns:
    Globals:
        %::GLOBAL_TAB_HASH: in subvars_for_mypostscript(), it will read mypostscript.tmpl and 
                            see what db attrs will be needed. The  %::GLOBAL_TAB_HASH will store all
                            the db attrs needed. And the format of value setting looks like:
                            $::GLOBAL_TAB_HASH{$tabname}{$key}{$attrib} = $value;
        %::GLOBAL_SN_HASH: getservicenode() will get all the nodes in the servicenode table. And the 
                            result will store in the %::GLOBAL_SN_HASH. The fortmac of the value setting
                            looks like:
                            $::GLOBAL_SN_HASH{$servicenod1} = 1;
                        
    Error:
        none
    Example:
         
    Comments:
        none

=cut

#-----------------------------------------------------------------------------


my $os;
my $profile;
my $arch;
my $provmethod;
my $mn;
%::GLOBAL_TAB_HASH;
%::GLOBAL_SN_HASH;
%::GLOBAL_TABDUMP_HASH;

sub subvars_for_mypostscript { 
  my $self         = shift;
  my $nodes        = shift;
  my $nodesetstate    = shift;
  my $callback     = shift;
  #my $tmpl          = shift;  #tmplfile  default: "/opt/xcat/share/xcat/templates/mypostscript/mypostscript.tmpl" customized: /install/postscripts/mypostscript.tmpl 
  $tmplerr=undef; #clear tmplerr since we are starting fresh
  my %namedargs = @_; #further expansion of this function will be named arguments, should have happened sooner.
 
  my $installroot; 
  my @entries =  xCAT::TableUtils->get_site_attribute("installdir"); 
  if($entries[0]) {
       $installroot = $entries[0];
  }
  my $tmpl="$installroot/postscripts/mypostscript.tmpl";
    
  unless ( -r $tmpl) {
       $tmpl="$::XCATROOT/share/xcat/templates/mypostscript/mypostscript.tmpl";
  }
    
  unless ( -r "$tmpl") {
       $callback->(
       {
             error => [
                           "site.precreatemypostscripts is set to 1 or yes. But No mypostscript template exists"
                            . " in directory $installroot/install/postscripts or $::XCATROOT/share/xcat/templates/mypostscript/mypostscript.tmpl"
                       ],
              errorcode => [1]
           }
         );
       return;
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

  my $postfix;  
  my @entries =  xCAT::TableUtils->get_site_attribute("precreatemypostscripts");
  if ($entries[0] ) {
      $entries[0] =~ tr/a-z/A-Z/;
      if ($entries[0] !~ /^(1|YES)$/ ) {
          $postfix="tmp";
      }   
  } else {
      $postfix="tmp";
  }

  foreach my $n (@$nodes ) {
      $node = $n; 
      $inc = $t_inc;
      my $script;
      my $scriptfile; 
      if( defined( $postfix ) ) {
          $scriptfile = "$tftpdir/mypostscripts/mypostscript.$node.tmp";
      } else { 
          $scriptfile = "$tftpdir/mypostscripts/mypostscript.$node";
      }
      #mkpath(dirname($scriptfile));
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
    if (!$nodesetstate) { $nodesetstate = xCAT::Postage::getnodesetstate($node); }
    #print "nodesetstate:$nodesetstate\n";
   
    #my $et = $typehash->{$node};
    my $et = $::GLOBAL_TAB_HASH{nodetype}{$node}; 
    $provmethod = $et->{'provmethod'};
    $os = $et->{'os'};
    $arch = $et->{'arch'};
    $profile = $et->{'profile'};

    
    my $osimgname = $provmethod;
    if($osimgname =~ /^(install|netboot|statelite)$/){
         $osimgname = "$os-$arch-$provmethod-$profile";
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
    $postscripts = xCAT::Postage::getPostScripts($node, $osimgname, $script_hash, $setbootfromnet, $nodesetstate, $arch);

    ## postbootscripts
    # for #INCLUDE_POSTBOOTSCRIPTS_LIST#
    my $postbootscripts;
    $postbootscripts = xCAT::Postage::getPostbootScripts($node, $osimgname, $script_hash);




  #ok, now do everything else..
  #$inc =~ s/#XCATVAR:([^#]+)#/envvar($1)/eg;
  #$inc =~ s/#ENV:([^#]+)#/envvar($1)/eg;
  #$inc =~ s/#NODE#/$node/eg;
  $inc =~ s/\$NODE/$node/eg;
  $inc =~ s/#SITE_TABLE_ALL_ATTRIBS_EXPORT#/$allattribsfromsitetable/eg; 
  #$inc =~ s/#TABLE:([^:]+):([^:]+):([^:]+):BLANKOKAY#/tabdb($1,$2,$3,1)/eg; 
  $inc =~ s/#TABLE:([^:]+):([^:]+):([^#]+)#/tabdb($1,$2,$3)/eg; 
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
  $inc =~ s/#Subroutine:([^:]+)::([^:]+)::([^:]+):([^#]+)#/subroutine($1,$2,$3,$4)/eg;

  print $script $inc;    
  close($script_fp{$node});
  }
  
  undef(%::GLOBAL_TAB_HASH);
  undef(%::GLOBAL_SN_HASH);
  undef(%::GLOBAL_TABDUMP_HASH);
  return 0;
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



sub enablesshbetweennodes
{
   my $node = shift;  
   my $result;   

   my $enablessh=xCAT::TableUtils->enablessh($node); 
   if ($enablessh == 1) {
       $result = "'YES'";
   } else {
       $result = "'NO'";
   }      
   
   return $result;
}

sub subroutine
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
                      "OTHERPKGDIR=" . $ref1->{'otherpkgdir'} . "\n";
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
