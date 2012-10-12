#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

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
my $lastmachinepass;
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
	$lastmachinepass="";
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
  $inc =~ s/#HOSTNAME#/$node/eg;

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
                my $tempstr = "%inlcude /tmp/partitionfile\n";
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
    if ($lastmachinepass) { #note, this should only happen after another call
			    #to subvars that does *not* request reuse
			    #the issue being avoiding reuse in the installmonitor case
			    #subvars function clears this if appropriate
	return $lastmachinepass;
    }
    my $domaintab = xCAT::Table->new('domain');
    $ENV{HOME}='/etc/xcat';
    $ENV{LDAPRC}='ad.ldaprc';
    my $ou;
    if ($domaintab) {
        my $ouent = $domaintab->getNodeAttribs('node','ou');
        if ($ouent and $ouent->{ou}) {
            $ou = $ouent->{ou};
        }
    }
    #my $sitetab = xCAT::Table->new('site');
    #unless ($sitetab) {
    #    return "ERROR: unable to open site table"; 
    #}
    my $domain;
    #(my $et) = $sitetab->getAttribs({key=>"domain"},'value');
    my @domains =  xCAT::TableUtils->get_site_attribute("domain");
    my $tmp = $domains[0];
    if (defined($tmp)) {
        $domain = $tmp;
    } else {
        return "ERROR: no domain set in site table";
    }
    my $realm = uc($domain);
    $realm =~ s/\.$//;
    $realm =~ s/^\.//;
    $ENV{KRB5CCNAME}="/tmp/xcat/krbcache.$realm.$$";
    unless ($loggedrealms{$realm}) {
        my $passtab = xCAT::Table->new('passwd',-create=>0);
        unless ($passtab) { sendmsg([1,"Error authenticating to Active Directory"],$node); return; }
        (my $adpent) = $passtab->getAttribs({key=>'activedirectory'},['username','password']);
        unless ($adpent and $adpent->{username} and $adpent->{password}) {
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
    $tmp = $servers[0];
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
	$lastmachinepass=$data->{password};
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
    unless ($result =~ /^\$1\$/) {
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


my $os;
my $profile;
my $arch;
my $provmethod;
my $nodesetstate;
sub subvars_for_mypostscript { 
  my $self         = shift;
  my $nodes        = shift;
  $nodesetstate    = shift;
  my $callback     = shift;
  #my $tmpl          = shift;  #tmplfile  default: "/opt/xcat/share/xcat/templates/mypostscript/mypostscript.tmpl" customized: /install/postscripts/mypostscript.tmpl 
  $tmplerr=undef; #clear tmplerr since we are starting fresh
  my %namedargs = @_; #further expansion of this function will be named arguments, should have happened sooner.

  my $installroot =
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

  my $inc;
  my $t_inc;
  #First load input into memory..
  while (<$inh>) {
      $t_inc.=$_;
  }

  close($inh);


  my %script_fp;    
  my $allattribsfromsitetable;

  # read all attributes for the site table and write an export   
  # only run this function once for one command with noderange
  $allattribsfromsitetable = getAllAttribsFromSiteTab();

  my $masterhash = getMasters($nodes);

  ## nfsserver,installnic,primarynic
  my $attribsfromnoderes = getNoderes($nodes);

  foreach my $n (@$nodes ) {
      $node = $n; 
      $inc = $t_inc;
      my $tftpdir = xCAT::TableUtils::getTftpDir();
      my $script;
      my $scriptfile; 
      $scriptfile = "$tftpdir/mypostscripts/mypostscript.$node";
      mkpath(dirname($scriptfile));
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
      my $master = $masterhash->{$node};

      if( defined($master) ) {
          $allattribsfromsitetable =~ s/MASTER=([^\n]+)\n/MASTER=$master\n/; 
      } 

      # ENABLESSHBETWEENNODES
       
      ## nfsserver,installnic,primarynic
      my ($nfsserver, $installnic, $primarynic, $route_vars);

      my $noderesent;
      
      if(exists($attribsfromnoderes->{$node})) {
          $noderesent = $attribsfromnoderes->{$node};
      }
 
      if ($noderesent ){
              if($noderesent->{nfsserver}) {
                  $nfsserver = $noderesent->{nfsserver};
              }
              if($noderesent->{installnic}) {
                  $installnic = $noderesent->{installnic};
              }
              if($noderesent->{primarynic}) {
                  $primarynic = $noderesent->{primarynic};
              }
        
      }
      #print Dumper($noderesent);
      #routes 
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

    ## OSPKGDIR export
    #  for #OSIMAGE_VARS_EXPORT# 
    if (!$nodesetstate) { $nodesetstate = xCAT::Postage::getnodesetstate($node); }

    my $typetab    = xCAT::Table->new('nodetype');
    my $et =
      $typetab->getNodeAttribs($node, ['os', 'arch', 'profile', 'provmethod'],prefetchcache=>1);
    if ($^O =~ /^linux/i)
    {
        unless ($et and $et->{'os'} and $et->{'arch'})
        {
            my $rsp;
            push @{$rsp->{data}},
              "No os or arch setting in nodetype table for $node.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return undef;
        }
    }
    $provmethod = $et->{'provmethod'};
    $os = $et->{'os'};
    $arch = $et->{'arch'};
    $profile = $et->{'profile'};

    my $osimage_vars;
    $osimage_vars = getOsimageItems($node);
     
    ## network
    # for #NETWORK_FOR_DISKLESS_EXPORT#
    #
    my $diskless_net_vars;
    $diskless_net_vars = getDisklessNet(); 
    
    ## postscripts
    # for #INCLUDE_POSTSCRIPTS_LIST# 
    #
    my $postscripts;
    $postscripts = getPostScripts();

    ## postbootscripts
    # for #INCLUDE_POSTBOOTSCRIPTS_LIST#
    my $postbootscripts;
    $postbootscripts = getPostbootScripts();




  #ok, now do everything else..
  $inc =~ s/#XCATVAR:([^#]+)#/envvar($1)/eg;
  $inc =~ s/#ENV:([^#]+)#/envvar($1)/eg;
  $inc =~ s/#SITE_TABLE_ALL_ATTRIBS_EXPORT#/$allattribsfromsitetable/eg; 
  $inc =~ s/#TABLE:([^:]+):([^:]+):([^#]+)#/tabdb($1,$2,$3)/eg; 
  $inc =~ s/#ROUTES_VARS_EXPORT#/$route_vars/eg; 
  $inc =~ s/#VLAN_VARS_EXPORT#/$vlan_vars/eg; 
  $inc =~ s/#MONITORING_VARS_EXPORT#/$mon_vars/eg; 
  $inc =~ s/#OSIMAGE_VARS_EXPORT#/$osimage_vars/eg; 
  $inc =~ s/#NETWORK_FOR_DISKLESS_EXPORT#/$diskless_net_vars/eg; 
  $inc =~ s/#INCLUDE_POSTSCRIPTS_LIST#/$postscripts/eg; 
  $inc =~ s/#INCLUDE_POSTBOOTSCRIPTS_LIST#/$postbootscripts/eg; 
  
  $inc =~ s/#COMMAND:([^#]+)#/command($1)/eg;
  $inc =~ s/#NODE#/$node/eg;
  $inc =~ s/\$NODE/$node/eg;
  $inc =~ s/#NFSSERVER#/$nfsserver/eg;
  $inc =~ s/#INSTALLNIC#/$installnic/eg;
  $inc =~ s/#PRIMARYNIC#/$primarynic/eg;
  $inc =~ s/#Subroutine:([^:]+)::([^:]+)::([^:]+):([^#]+)#/subroutine($1,$2,$3,$4)/eg;

  #my $nrtab = xCAT::Table->new("noderes");
  #my $tftpserver = $nrtab->getNodeAttribs($node, ['tftpserver']);
  #my $sles_sdk_media = "http://" . $tftpserver->{tftpserver} . $media_dir . "/sdk1";
  
  #$inc =~ s/#SLES_SDK_MEDIA#/$sles_sdk_media/eg;

  #if ($tmplerr) {
  #   close ($outh);
  #   return $tmplerr;
  # }
  #print $outh $inc;
  #close($outh);
      print $script $inc;    
      close($script_fp{$node});
  }
  return 0;
}

sub getMasterFromNoderes
{
     my $node = shift;
     my $value;
 
     my $noderestab = xCAT::Table->new('noderes');
     # if node has service node as master then override site master
     my $et = $noderestab->getNodeAttribs($node, ['xcatmaster'],prefetchcache=>1);
     if ($et and defined($et->{'xcatmaster'}))
     {
           $value = $et->{'xcatmaster'};
     }
     else
     {
           my $sitemaster_value = $value;
           $value = xCAT::NetworkUtils->my_ip_facing($node);
           if ($value eq "0")
           {
                $value = $sitemaster_value;
           }
      }
      
      return $value;

}

sub getMasters
{
     my $nodes = shift;
     my %masterhash;

     my $noderestab = xCAT::Table->new('noderes');
     # if node has service node as master then override site master
     my $ethash = $noderestab->getNodesAttribs($nodes, ['xcatmaster'],prefetchcache=>1);

     
     if ($ethash) {
         foreach my $node ($nodes) {
             if( $ethash->{$node}->[0] ) {
                  $masterhash{$node} = $ethash->{$node}->[0]->{xcatmaster};    
             }

             if ( ! exists($masterhash{$node}))
             {
                  my $value;
                  $value = xCAT::NetworkUtils->my_ip_facing($node);
                  if ($value eq "0")
                  {
                      undef($value);
                  }
                  $masterhash{$node} = $value;
             }
         }
 
     } 
     
     return \%masterhash; 
}

sub getNoderes
{
     my $nodes = shift;
     my %nodereshash;

     my $noderestab = xCAT::Table->new('noderes');
       
     ## nfsserver,installnic,primarynic
     my ($nfsserver, $installnic, $primarynic, $route_vars);
      
     my $noderestab = xCAT::Table->new('noderes');
      
     my $ethash =
        $noderestab->getNodesAttribs($nodes,
                                  ['nfsserver', 'installnic', 'primarynic','routenames'],prefetchcache=>1);
     if ($ethash ){
          foreach my $node (@$nodes) {
              if( defined( $ethash->{$node}->[0]) ) {
                  $nodereshash{$node}{nfsserver} = $ethash->{$node}->[0]->{nfsserver};
                  $nodereshash{$node}{installnic} = $ethash->{$node}->[0]->{installnic};
                  $nodereshash{$node}{primarynic} = $ethash->{$node}->[0]->{primarynic};
                  $nodereshash{$node}{routenames} = $ethash->{$node}->[0]->{routenames};
              }
          }  
      }
     
     return \%nodereshash; 
}






sub getAllAttribsFromSiteTab {
    
    my $sitetab    = xCAT::Table->new('site');
    my $master;
    my $result;
    
    # read all attributes for the site table and write an export
    # for them in the post install file
    my $recs = $sitetab->getAllEntries();
    my $noderestab = xCAT::Table->new('noderes');
    my $attribute;
    my $value;
    my $masterset = 0;
    foreach (@$recs)    # export the attribute
    {
        $attribute = $_->{key};
        $attribute =~ tr/a-z/A-Z/;
        $value = $_->{value};
        if ($attribute eq "MASTER")
        {
            $masterset = 1;
            $result .= "SITEMASTER=" . $value . "\n";
            $result .= "export SITEMASTER\n";

            # if node has service node as master then override site master
            #my $et = $noderestab->getNodeAttribs($node, ['xcatmaster'],prefetchcache=>1);
            #if ($et and defined($et->{'xcatmaster'}))
            #{
            #    $value = $et->{'xcatmaster'};
            #}
            #else
            #{
            #    my $sitemaster_value = $value;
            #    $value = xCAT::Utils->my_ip_facing($node);
            #    if ($value eq "0")
            #    {
            #        $value = $sitemaster_value;
            #    }
            #}
            $result .= "$attribute=" . $value . "\n";
            $result .= "export $attribute\n";

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
       $result = "YES";
   } else {
       $result = "NO";
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

sub getVlanItems
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


sub getMonItems
{

    my $node = shift;
    my $result;

    #get monitoring server and other configuration data for monitoring setup on nodes
    my %mon_conf = xCAT_monitoring::monitorctrl->getNodeConfData($node);
    foreach (keys(%mon_conf))
    {
        $result .= "$_=" . $mon_conf{$_} . "\n";
        $result .= "export $_\n";
    }



    return $result;
}


sub getOsimageItems
{

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
        my $linuximagetab = xCAT::Table->new('linuximage', -create => 1);
        (my $ref1) =
          $linuximagetab->getAttribs({imagename => $provmethod},
                                     'pkglist', 'pkgdir', 'otherpkglist',
                                     'otherpkgdir');
        if ($ref1)
        {
            if ($ref1->{'pkglist'})
            {
                $ospkglist = $ref1->{'pkglist'};
                if ($ref1->{'pkgdir'})
                {
                    $result .= "OSPKGDIR=" . $ref1->{'pkgdir'} . "\n";
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
        my $osimagetab = xCAT::Table->new('osimage', -create => 1);
        if ($osimagetab)
        {
            (my $ref) =
              $osimagetab->getAttribs(
                                      {imagename => $provmethod}, 'osvers',
                                      'osarch',     'profile',
                                      'provmethod', 'synclists'
                                      );
            if ($ref)
            {
                $syncfile = $ref->{'synclists'};
            }
        }
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

my $setbootfromnet = 0;
sub getDisklessNet()
{
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
    
        if ($isdiskless)
        {
            (my $ip, my $mask, my $gw) = net_parms($node);
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
    $setbootfromnet = $bootfromnet;    

    return $result;

}

my $et;
my $et1;
my $et2;

sub getPostScripts
{

    my $node = shift;
    my $result;
    my $ps;
    my %post_hash = ();    #used to reduce duplicates
 
   
    my $posttab    = xCAT::Table->new('postscripts');
    my $ostab    = xCAT::Table->new('osimage');
    # get the xcatdefaults entry in the postscripts table
    my $et        =
      $posttab->getAttribs({node => "xcatdefaults"},
                           'postscripts', 'postbootscripts');
    my $defscripts = $et->{'postscripts'};
    if ($defscripts)
    {

        foreach my $n (split(/,/, $defscripts))
        {
            if (!exists($post_hash{$n}))
            {
                $post_hash{$n} = 1;
                $result .= $n . "\n";
            }
        }
    }
    
    # get postscripts for images
    my $osimgname = $provmethod;

    if($osimgname =~ /install|netboot|statelite/){
        $osimgname = "$os-$arch-$provmethod-$profile";
    }
    my $et2 =
      $ostab->getAttribs({'imagename' => "$osimgname"}, ['postscripts', 'postbootscripts']);
    $ps = $et2->{'postscripts'};
    if ($ps)
    {
        foreach my $n (split(/,/, $ps))
        {
            if (!exists($post_hash{$n}))
            {
                $post_hash{$n} = 1;
                $result .= $n . "\n";
            }
        }
    }

    # get postscripts for node specific
    my $et1 =
      $posttab->getNodeAttribs($node, ['postscripts', 'postbootscripts'],prefetchcache=>1);
    $ps = $et1->{'postscripts'};
    if ($ps)
    {
        foreach my $n (split(/,/, $ps))
        {
            if (!exists($post_hash{$n}))
            {
                $post_hash{$n} = 1;
                $result .=  $n . "\n";
            }
        }
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
    my $result;
    my $ps;
 
   
    my %postboot_hash = ();                         #used to reduce duplicates
    my $defscripts    = $et->{'postbootscripts'};
    if ($defscripts)
    {
        foreach my $n (split(/,/, $defscripts))
        {
            if (!exists($postboot_hash{$n}))
            {
                $postboot_hash{$n} = 1;
                $result .=   $n . "\n";
            }
        }
    }

    # get postbootscripts for image
    my $ips = $et2->{'postbootscripts'};
    if ($ips)
    {
        foreach my $n (split(/,/, $ips))
        {
            if (!exists($postboot_hash{$n}))
            {
                $postboot_hash{$n} = 1;
                $result .=  $n . "\n";
            }
        }
    }


    # get postscripts
    $ps = $et1->{'postbootscripts'};
    if ($ps)
    {
        foreach my $n (split(/,/, $ps))
        {
            if (!exists($postboot_hash{$n}))
            {
                $postboot_hash{$n} = 1;
                $result .=  $n . "\n";
            }
        }
    }

    return $result;
}




1;
