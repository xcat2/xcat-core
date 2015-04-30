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
use XML::Simple;
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
  my $partitionfileval=shift;
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
  $ENV{PERSKCMDLINE}=getPersistentKcmdline($node);


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
          if ((/^\s*#.*/ ) || ( $_ =~ /^-/ )){ 
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

  #if user specify the partion file, replace the default partition strategy
  my $partcontent;
  my $diskcontent;
  my $configcontent;
  my $scriptflag = 0;
  my $partscriptflag = 0;
  my $diskscriptflag = 0;
  my $configscriptflag = 0;
  my $preseedflag =0;
  my $configfile;
  my $partitionfile;
  my $diskfile;
  my @partitionfilelist=split(/,/,$partitionfileval);
  foreach my $filepath (@partitionfilelist){
     $scriptflag =0;
     if($filepath =~ /^s:(.*)/){
        $scriptflag = 1;
        $filepath=$1;
     }

     if($filepath =~ /^d:(.*)/){
       $diskfile=$1;
       if($scriptflag ) {$diskscriptflag=1;};
     }elsif($filepath =~ /^c:(.*)/){
       $configfile=$1;
       if($scriptflag ) {$configscriptflag=1;};
     }elsif($filepath){
       $partitionfile=$filepath;
       if($scriptflag ) {$partscriptflag=1;};
     }
  }
 
  if($configfile){
      if (-r $configfile){
          open ($inh, "<", $configfile);
          while (<$inh>){
              $configcontent .= $_;
          }
          close ($inh);
      }

      # append the partition file into the $inc to do the replacement
      $inc .= "\nFFFFFFFFFFFFPARTITIONCONFIGFILESTART\n".$configcontent."\nFFFFFFFFFFFFPARTITIONCONFIGFILEEND\n";
  }    
 
  if($diskfile){
      if (-r $diskfile){
          open ($inh, "<", $diskfile);
          while (<$inh>){
              $diskcontent .= $_;
          }
          close ($inh);
      }

      # append the partition file into the $inc to do the replacement
      $inc .= "\nFFFFFFFFFFFFPARTITIONDISKFILESTART\n".$diskcontent."\nFFFFFFFFFFFFPARTITIONDISKFILEEND\n";     
  }

  if ($partitionfile){
 
      if($inc =~ /#XCA_PARTMAN_RECIPE_SCRIPT#/){
          $preseedflag=1; 
      }
  
      if (-r $partitionfile){
          open ($inh, "<", $partitionfile);
          while (<$inh>){
              $partcontent .= $_;
          }
          close ($inh);
      }

      # append the partition file into the $inc to do the replacement
      $inc .= "\nFFFFFFFFFFFFPARTITIONFILESTART\n".$partcontent."\nFFFFFFFFFFFFPARTITIONFILEEND\n";
  }


  #do *all* includes, recursive for all
  my $doneincludes=0;
  while (not $doneincludes) {
      $doneincludes=1;
      $inc =~ s/#ENV:([^#]+)#/envvar($1)/eg;  # handle the variable in #INCLUDE
      if ($inc =~ /#INCLUDE_PKGLIST:[^\n]+#/) {
          # get in this section but might not do the replace since it needs wait
          # for the replace of sting inside the #INCLUDE_PKGLIST:xx#
          $doneincludes=0;
          $inc =~ s/#INCLUDE_PKGLIST:([^#^\n]+)#/includefile($1, 0, 1)/eg;
      }
      if ($inc =~ /#INCLUDE_PTRNLIST:[^\n]+#/) {
          $doneincludes=0;
          $inc =~ s/#INCLUDE_PTRNLIST:([^#^\n]+)#/includefile($1, 0, 2)/eg;
      }
      if ($inc =~ /#INCLUDE_RMPKGLIST:[^\n]+#/) {
          $doneincludes=0;
          $inc =~ s/#INCLUDE_RMPKGLIST:([^#^\n]+)#/includefile($1, 0, 3)/eg;
      }
      if ($inc =~ /#INCLUDE:[^\n]+#/) {
          $doneincludes=0;
          $inc =~ s/#INCLUDE:([^#^\n]+)#/includefile($1, 0, 0)/eg;
      }

      #support multiple paths of osimage in rh/sles diskfull installation
      my @pkgdirs;
      if ( defined($media_dir) ) {
          @pkgdirs = split(",", $media_dir);
          my $source;
          my $source_in_pre;
          my $c = 0; 
          foreach my $pkgdir(@pkgdirs) {
              if( $platform =~ /^(rh|SL|centos|fedora)$/ ) {
                  if ( $c == 0 ) {
                      # After some tests, if we put the repo in  pre scripts in the kickstart like for rhels6.x
                      # the rhels5.9 will not be installed successfully. So put in kickstart directly.
                      $source_in_pre .=  "echo 'url --url http://'\$nextserver'/$pkgdir' >> /tmp/repos";
                      $source .=  "url --url http://#TABLE:noderes:\$NODE:nfsserver#/$pkgdir\n"; #For rhels5.9
                  } else {
                      $source_in_pre .=  "\necho 'repo --name=pkg$c --baseurl=http://'\$nextserver'/$pkgdir' >> /tmp/repos";  
                      $source .=  "repo --name=pkg$c --baseurl=http://#TABLE:noderes:\$NODE:nfsserver#/$pkgdir\n";  #for rhels5.9
                  }
              } elsif ($platform =~ /^(sles|suse)/) {
                  my $http = "http://#TABLE:noderes:\$NODE:nfsserver#$pkgdir";
                  $source .=  "         <listentry>
               <media_url>$http</media_url>
               <product>SuSE-Linux-pkg$c</product>
               <product_dir>/</product_dir>
               <ask_on_error config:type=\"boolean\">false</ask_on_error> <!-- available since openSUSE 11.0 -->
               <name>SuSE-Linux-pkg$c</name> <!-- available since openSUSE 11.1/SLES11 (bnc#433981) -->
             </listentry>";
               $source_in_pre .="<listentry><media_url>http://'\$nextserver'$pkgdir</media_url><product>SuSE-Linux-pkg$c</product><product_dir>/</product_dir><ask_on_error config:type=\"boolean\">false</ask_on_error><name>SuSE-Linux-pkg$c</name></listentry>";
              }
              $c++;
          }
    
          $inc =~ s/#INSTALL_SOURCES#/$source/g;
          $inc =~ s/#INSTALL_SOURCES_IN_PRE#/$source_in_pre/g;
          if (("ubuntu" eq $platform) || ("debian" eq $platform)) {
              $inc =~ s/#INCLUDE_OSIMAGE_PKGDIR#/$pkgdirs[-1]/;
          }
      }
    
      #ok, now do everything else..
      my $shortname = $node;
      $shortname =~ s/\..*//;
      $inc =~ s/#TABLE:([^:]+):([^:]+):([^#]+)#/tabdb($1,$2,$3)/eg;
      $inc =~ s/#TABLEBLANKOKAY:([^:]+):([^:]+):([^#]+)#/tabdb($1,$2,$3,'1')/eg;
      $inc =~ s/#INCLUDE_NOP:([^#^\n]+)#/includefile($1,1,0)/eg;
      $inc =~ s/#XCATVAR:([^#]+)#/envvar($1)/eg;
      $inc =~ s/#ENV:([^#]+)#/envvar($1)/eg;
      $inc =~ s/#MACHINEPASSWORD#/machinepassword()/eg;
      $inc =~ s/#CRYPT:([^:]+):([^:]+):([^#]+)#/crydb($1,$2,$3)/eg;
      $inc =~ s/#COMMAND:([^#]+)#/command($1)/eg;
      $inc =~ s/#KICKSTARTNET#/kickstartnetwork()/eg;
      $inc =~ s/#MIRRORSPEC#/mirrorspec()/eg;
      $inc =~ s/#YAST2NET#/yast2network()/eg;
      $inc =~ s/#KICKSTARTBOOTLOADER#/kickstartbootloader()/eg;
      $inc =~ s/#ESXIPV6SETUP#/esxipv6setup()/eg;
      $inc =~ s/#WINTIMEZONE#/xCAT::TZUtils::get_wintimezone()/eg;
      $inc =~ s/#WINPRODKEY:([^#]+)#/get_win_prodkey($1)/eg;
      $inc =~ s/#WINNETCFG#/windows_net_cfg()/eg;
      $inc =~ s/#WINADJOIN#/windows_join_data()/eg;
      $inc =~ s/#WINPOSTSCRIPTS#/windows_postscripts()/eg;
      $inc =~ s/#WINDNSCFG#/windows_dns_cfg()/eg;
      $inc =~ s/#WINACCOUNTDATA#/windows_account_data()/eg;
      $inc =~ s/#WINDISABLENULLADMIN#/windows_disable_null_admin()/eg;
      $inc =~ s/#MANAGEDADDRESSMODE#/managed_address_mode()/eg;
      $inc =~ s/#HOSTNAME#/$node/g;
      $inc =~ s/#SHORTNAME#/$shortname/g;
      $inc =~ s/#GETNODEDOMAIN:([^#]+)#/get_node_domain($1)/eg;
    
      my $nrtab = xCAT::Table->new("noderes");
      my $tftpserver = $nrtab->getNodeAttribs($node, ['tftpserver']);
      my $sles_sdk_media = "http://" . $tftpserver->{tftpserver} . $media_dir . "/sdk1";
      
      $inc =~ s/#SLES_SDK_MEDIA#/$sles_sdk_media/eg;

      if ($partitionfile && $doneincludes) {
          #the content of the specified file is a script which can write partition definition into /tmp/partitionfile
          # split the partition file out from the $inc
          ($inc, $partcontent) = split(/FFFFFFFFFFFFPARTITIONFILESTART\n/, $inc);
          ($partcontent, $res) = split(/\nFFFFFFFFFFFFPARTITIONFILEEND/, $partcontent);
          $inc .=$res;
          if ($partscriptflag or $preseedflag){
              # since the whole partition file needs be packaged in %pre first and generate an executable file at running time,
              # all the special chars like ',",%,\ need be kept, we have to use the base64 coding to code it and put it in
              # %pre and decode it out during the running time.
              use MIME::Base64;
              $partcontent = encode_base64($partcontent);
              $partcontent =~ s/\n//g;
              
              #for redhat/sl/centos/kvm/fedora
              if ($inc =~ /#XCAT_PARTITION_START#/) {
                  my $tempstr = "%include /tmp/partitionfile\n";
                  $inc =~ s/#XCAT_PARTITION_START#[\s\S]*#XCAT_PARTITION_END#/$tempstr/;
                  # Put the base64 coded partitionfile into %pre part
                  $partcontent = "cat > /tmp/partscript.enc << EOFEOF\n" . $partcontent . "\nEOFEOF\n";
                  # Put the code to decode the partitionfile
                  $partcontent .= "python -c 'import base64; print base64.b64decode(open(\"/tmp/partscript.enc\",\"rb\").read())' >/tmp/partscript\n";
                  $partcontent .= "chmod 755 /tmp/partscript\n";
                  $partcontent .= "/tmp/partscript\n";
                  #replace the #XCA_PARTITION_SCRIPT#
                  $inc =~ s/#XCA_PARTITION_SCRIPT#/$partcontent/;
              }
              #for sles/suse
              elsif ($inc =~ /<!-- XCAT-PARTITION-START -->/){
                  my $tempstr = "<drive><device>XCATPARTITIONTEMP</device></drive>";
                  $inc =~ s/<!-- XCAT-PARTITION-START -->[\s\S]*<!-- XCAT-PARTITION-END -->/$tempstr/;
                  # Put the base64 coded partitionfile into %pre part
                  $partcontent = "cat > /tmp/partscript.enc << EOFEOF\n" . $partcontent . "\nEOFEOF\n";
                  # Put the code to decode the partitionfile
                  $partcontent .= "perl -ne 'use MIME::Base64; print decode_base64(\$_)' </tmp/partscript.enc > /tmp/partscript\n";
                  $partcontent .= "chmod 755 /tmp/partscript\n";
                  $partcontent .= "/tmp/partscript\n";
                  $inc =~ s/#XCA_PARTITION_SCRIPT#/$partcontent/;
              }
              #for ubuntu
              elsif ($inc =~ /#XCA_PARTMAN_RECIPE_SCRIPT#/){
                  # Put the base64 coded partitionfile into %pre part
                  $partcontent = "cat > /tmp/partscript.enc << EOFEOF\n" . $partcontent . "\nEOFEOF\n";
                  if( $scriptflag ){
                     # Put the code to decode preseed script and run it to generate pressed recipe file
                     #$partcontent .= "python -c 'import base64; print base64.b64decode(open(\"/tmp/partscript.enc\",\"rb\").read())' >/tmp/partscript\n";
                     $partcontent .= "base64decode</tmp/partscript.enc >/tmp/partscript\n";
                     $partcontent .= "chmod 755 /tmp/partscript\n";
                     $partcontent .= "/tmp/partscript\n";
                  }else{
                     # Put the code to decode the preseed recipe file
                     #$partcontent .= "python -c 'import base64; print base64.b64decode(open(\"/tmp/partscript.enc\",\"rb\").read())' >/tmp/partitioning\n";
                     $partcontent .= "base64decode</tmp/partscript.enc >/tmp/partitioning\n";
                    
                  }
                  #replace the #XCA_PARTMAN_RECIPE_SCRIPT#
                  $inc =~ s/#XCA_PARTMAN_RECIPE_SCRIPT#/$partcontent/;
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
     
 
      if ($diskfile && $doneincludes) {
          #the content of the specified file is the disknames to partition or a script which can write disk names into /tmp/boot_disk
          # split the disk file out from the $inc
          ($inc, $diskcontent) = split(/FFFFFFFFFFFFPARTITIONDISKFILESTART\n/, $inc);
          ($diskcontent,$res) = split(/\nFFFFFFFFFFFFPARTITIONDISKFILEEND/, $diskcontent);
          $inc .=$res;
          # since the whole partition file needs be packaged in %pre first and generate an executable file at running time,
          # all the special chars like ',",%,\ need be kept, we have to use the base64 coding to code it and put it in
          # %pre and decode it out during the running time.
          use MIME::Base64;
          $diskcontent = encode_base64($diskcontent);
          $diskcontent =~ s/\n//g;

          if ($inc =~ /#XCA_PARTMAN_DISK_SCRIPT#/){
             # Put the base64 coded disk file/script into %pre part
             $diskcontent = "cat > /tmp/diskscript.enc << EOFEOF\n" . $diskcontent . "\nEOFEOF\n";
             if( $diskscriptflag ){
                # Put the code to decode disk script and run it to generate pressed disk file
                #$diskcontent .= "python -c 'import base64; print base64.b64decode(open(\"/tmp/diskscript.enc\",\"rb\").read())' >/tmp/diskscript\n";
                $diskcontent .= "base64decode</tmp/diskscript.enc >/tmp/diskscript\n";
                $diskcontent .= "chmod 755 /tmp/diskscript\n";
                $diskcontent .= "/tmp/diskscript\n";
             }else{
                # Put the code to decode the preseed  disk file
                #$diskcontent .= "python -c 'import base64; print base64.b64decode(open(\"/tmp/diskscript.enc\",\"rb\").read())' >/tmp/boot_disk\n";
                $diskcontent .= "base64decode</tmp/diskscript.enc >/tmp/boot_disk\n";

             }
             #replace the #XCA_PARTMAN_DISK_SCRIPT#
             $inc =~ s/#XCA_PARTMAN_DISK_SCRIPT#/$diskcontent/;
           }
      }
 
      if ($configfile && $doneincludes) {
          #the content of the specified file is the additional pressed config with 'd-i' or 
          # a script set the additional pressed config with "debconf-set"
          # split the config file out from the $inc
          ($inc, $configcontent) = split(/FFFFFFFFFFFFPARTITIONCONFIGFILESTART\n/, $inc);
          ($configcontent,$res) = split(/\nFFFFFFFFFFFFPARTITIONCONFIGFILEEND/, $configcontent);
          $inc .=$res;
          


          if ($configscriptflag){
             # since the whole partition file needs be packaged in %pre first and generate an executable file at running time,
             # all the special chars like ',",%,\ need be kept, we have to use the base64 coding to code it and put it in
             # %pre and decode it out during the running time.
             use MIME::Base64;
             $configcontent = encode_base64($configcontent);
             $configcontent =~ s/\n//g;
             # Put the base64 coded config script into %pre part
             $configcontent = "cat > /tmp/configscript.enc << EOFEOF\n" . $configcontent . "\nEOFEOF\n";

             # Put the code to decode config script and run it to generate pressed config
             $configcontent .= "base64decode</tmp/configscript.enc >/tmp/configscript\n";
             $configcontent .= "chmod 755 /tmp/configscript\n";
             $configcontent .= "/tmp/configscript\n";
             $inc =~ s/#XCA_PARTMAN_ADDITIONAL_CONFIG_SCRIPT#/$configcontent/;
         }else{
             $inc =~ s/#XCA_PARTMAN_ADDITIONAL_CFG#/$configcontent/; 
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
			
	my $domain;
        my $doment;
	my $domaintab = xCAT::Table->new('domain',-create=>0);
	if ($domaintab) {
           $doment = $domaintab->getNodeAttribs($node,['authdomain','type'],prefetchcache=>1);
	}
	unless ($::XCATSITEVALS{directoryprovider} eq "activedirectory" or ($doment and $doment->{type} eq "activedirectory")) {
		return $useraccountxml;
	}
	if ($doment and $doment->{authdomain}) {
		$domain = $doment->{authdomain};
	} else {
		$domain = $::XCATSITEVALS{domain};
	}
	$useraccountxml.="<DomainAccounts><DomainAccountList>\r\n<DomainAccount wcm:action=\"add\">\r\n<Group>Administrators</Group>\r\n<Name>Domain Admins</Name>\r\n</DomainAccount>\r\n<Domain>".$domain."</Domain>\r\n</DomainAccountList>\r\n</DomainAccounts>\r\n";
		return $useraccountxml;
}
sub windows_net_cfg {
    if ($::XCATSITEVALS{managedaddressmode} =~ /static/) { return "<!-- WINCFG Static not supported -->"; }
    unless ($::XCATSITEVALS{managedaddressmode} =~ /autoula/) {
        # handle the general windows deployment that create interfaces sections from nic table
        my $component_head = '<component name="Microsoft-Windows-TCPIP" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">';
        my $component_end = '</component>';
        
        my $interfaces_cfg = '<Interfaces>';

        # get the installnic
        my $nrtab = xCAT::Table->new('noderes',-create=>0);
        my $installnic;
        if ($nrtab) {
            my $nrent = $nrtab->getNodeAttribs($node,['installnic', 'primarynic']);
            if ($nrent) {
                if (defined ($nrent->{'installnic'})) {
                    $installnic = $nrent->{'installnic'};
                } elsif (defined ($nrent->{'primarynic'})) {
                    $installnic = $nrent->{'primarynic'};
                }
            }
        }

        # get the site.setinstallnic
        my @ents = xCAT::TableUtils->get_site_attribute("setinstallnic");
        my $setinstallnic;
        if ($ents[0] =~ /1|yes|y/i) {
            $setinstallnic = 1;
        }

        my $nicstab = xCAT::Table->new('nics',-create=>0);
        my $hasif;
        if ($nicstab) {
            my $nicsent = $nicstab->getNodeAttribs($node,['nicips']);
            if ($nicsent->{nicips}) {
                my @nics = split (/,/, $nicsent->{nicips});
                foreach (@nics) {
                    my $gateway;
                    my $interface_cfg = '<Interface wcm:action="add">';
                    my ($nicname, $ips) = split(/!/, $_);
                    unless ($nicname) { next; }
                    if ($nicname =~ /^bmc/) { next; }  # do nothing for bmc interface
                    my $dosetgw = 0;
                    if ($nicname eq $installnic) {
                        if ($setinstallnic) {
                            # set to static with gateway
                            $dosetgw = 1;
                        } else {# else: do nothing means using dhcp
                            next;
                        }
                    } # else: do not set gateway, since gateway only set for installnic
                    if ($ips) {
                        $interface_cfg .= '<Ipv4Settings><DhcpEnabled>false</DhcpEnabled></Ipv4Settings><Ipv6Settings><DhcpEnabled>false</DhcpEnabled></Ipv6Settings>';
                        $interface_cfg .= "<Identifier>$nicname</Identifier>";
                        $interface_cfg .= '<UnicastIpAddresses>';
                        
                        my @setip = split (/\|/, $ips);
                        my $num = 1;
                        foreach my $ip (@setip) {
                            my ($netmask, $gw) = getNM_GW($ip);
                            unless ($netmask) {
                                next;
                            }
                            if ($gw) { $gateway = $gw; }
                            if ($gateway eq '<xcatmaster>') {
                                $gateway = xCAT::NetworkUtils->my_ip_facing($ip);
                            }
                            $interface_cfg .= '<IpAddress wcm:action="add" wcm:keyValue="'.$num++.'">'.$ip."/$netmask".'</IpAddress>';
                        }
                        if ($num eq 1) {
                            # no correct IP with correct network is found
                            next;
                        }
                        
                        $interface_cfg .= "</UnicastIpAddresses>"
                    } else {
                        # set with dhcp
                        $interface_cfg .= '<Ipv4Settings><DhcpEnabled>true</DhcpEnabled></Ipv4Settings><Ipv6Settings><DhcpEnabled>true</DhcpEnabled></Ipv6Settings>';
                        $interface_cfg .= "<Identifier>$nicname</Identifier>";
                    }

        
                    # add the default gateway
                    if ($gateway && $dosetgw) {
                        $interface_cfg .= '<Routes><Route wcm:action="add"><Identifier>1</Identifier><NextHopAddress>'.$gateway.'</NextHopAddress><Prefix>0/0</Prefix></Route></Routes>';
                    }
                    $interface_cfg .= '</Interface>';
                    
                    $interfaces_cfg .= $interface_cfg;
                    $hasif = 1;
                }
            }
        }
        $interfaces_cfg .= "</Interfaces>";
        if ($hasif) {
            return "$component_head$interfaces_cfg$component_end"; #windows default behavior
        } else {
            return "";
        }
    }
	
    #autoula, 
    my $hoststab;
    my $mactab = xCAT::Table->new('mac',-create=>0);
    unless ($mactab) { die "mac table should always exist prior to template processing when doing autoula"; }
    my $ent = $mactab->getNodeAttribs($node,['mac'],prefetchcache=>1);
    unless ($ent and $ent->{mac}) { die "missing mac data for $node"; }
    my $suffix = xCAT::Utils->parseMacTabEntry($ent->{mac},$node);
    my $mac = $suffix;
    $suffix = lc($suffix);
    $mac =~ s/:/-/g;
    unless ($hoststab) { $hoststab = xCAT::Table->new('hosts',-create=>1); }
    my $ulaaddr = autoulaaddress($suffix);
    $hoststab->setNodeAttribs($node,{ip=>$ulaaddr});
    return '<component name="Microsoft-Windows-TCPIP" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'."\r\n<Interfaces><Interface wcm:action=\"add\">\r\n<Ipv4Settings><DhcpEnabled>false</DhcpEnabled></Ipv4Settings><Ipv6Settings><DhcpEnabled>false</DhcpEnabled></Ipv6Settings>\r\n<Identifier>$mac</Identifier>\r\n<UnicastIpAddresses>\r\n<IpAddress wcm:action=\"add\" wcm:keyValue=\"1\">$ulaaddr/64</IpAddress>\r\n</UnicastIpAddresses>\r\n</Interface>\r\n</Interfaces>\r\n</component>\r\n";
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
#this will lay out the data from postscripts table in a manner that is appropriate for windows consumption in Microsoft-Windows-Deployment
#component under specialize pass
sub windows_postscripts {
	my $posttab = xCAT::Table->new('postscripts',-create=>0);
	unless ($posttab) { return ""; }
	my $psent = $posttab->getNodeAttribs($node,['postscripts'],prefetchcache=>1);
	unless ($psent and $psent->{postscripts}) { return ""; }
	my @cmds = split /,/,$psent->{postscripts};
	my $order = 1;
	my $xml;
	my $pscript;
	foreach $pscript (@cmds) {
		unless ($pscript =~ /\\/) { 
			$pscript = "C:\\xcatpost\\".$pscript;
		}
		$xml .= "<RunSynchronousCommand wcm:action=\"add\">\r\n<Order>$order</Order>\r\n<Path>$pscript</Path>\r\n</RunSynchronousCommand>\r\n";
	}
}
#this will examine table data, decide *if* a Microsoft-Windows-UnattendedJoin is warranted
#there are two variants in how to proceed:
#-Hide domain administrator from node: xCAT will use MACHINEPASSWORD to do joining to AD.  Currently requires SSL be enabled on DC.  Samba 4 TODO
#-Provide domain administrator credentials, avoiding the SSL scenario.  This is by default forbidden as it is high risk for exposing sensitive credentials.
# Also populate MachineObjectOU 
sub windows_join_data {
        my $doment;
	my $domaintab = xCAT::Table->new('domain',-create=>0);
	if ($domaintab) {
           $doment = $domaintab->getNodeAttribs($node,['ou','type','authdomain','adminuser','adminpassword'],prefetchcache=>1);
	}
	unless ($::XCATSITEVALS{directoryprovider} eq "activedirectory" or ($doment and $doment->{type} eq "activedirectory")) {
		return "";
	}
	#we are still here, meaning configuration has a domain and activedirectory set, probably want to join..
	#TODO: provide a per-node 'disable' so that non-AD could be mixed into a nominally AD environment
	my $prejoin =1; 
	if (defined $::XCATSITEVALS{prejoinactivedirectory} and not  $::XCATSITEVALS{prejoinactivedirectory} ) {
		$prejoin = 0;
	}
	my $domain;
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
		my $adminuser;
		my $adminpass;
		if ($doment and $doment->{adminuser}) {
			$adminuser = $doment->{adminuser};
		}
		if ($doment and $doment->{adminpassword}) {
			$adminpass = $doment->{adminpassword};
		}
		unless ($adminuser and $adminpass) {
	        	my $passtab = xCAT::Table->new('passwd',-create=>0);
		        unless ($passtab) { sendmsg([1,"Error authenticating to Active Directory"],$node); return; }
			my @adpents = $passtab->getAttribs({key=>'activedirectory'},['username','password','authdomain']);
			my $adpent;
			foreach $adpent (@adpents) {
				if ($adpent and $adpent->{authdomain} and $adpent->{authdomain} ne $domain) { next; }
				if ($adpent and $adpent->{username} and $adpent->{password}) {
					$adminuser = $adpent->{username};
					$adminpass = $adpent->{password};
					last;
				}
			}
		}
		unless ($adminuser and $adminpass) { die "Missing active directory admin auth data from passwd table" }
		$componentxml .= "<Credentials><Domain>".$domain."</Domain>\r\n<Username>".$adminuser."</Username>\r\n<Password>".$adminpass."</Password>\r\n</Credentials>\r\n";
	}
	$componentxml .= "</Identification>\r\n</component>\r\n";
		
}
sub get_win_prodkey {
	my $osvariant = shift;
	my $keytab = xCAT::Table->new("prodkey",-create=>0);
	my $keyent;
	if ($keytab) {
	   my @keyents = $keytab->getNodeAttribs($node,[qw/product key/]);
	   foreach my $tkey (@keyents) {
		if ($tkey->{product} eq $osvariant) {
		     $keyent = $tkey;
		     last;
		} elsif (not $tkey->{product}) {
		     $keyent = $tkey;
		}
	   }
	   unless ($keyent) {
		$keyent = $keytab->getAttribs({product=>$osvariant},"key");
	   }
	}
	if ($keyent and $keyent->{key}) { 
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


sub get_node_domain {
    my $lcnode=shift;
    if ( $lcnode eq 'THISNODE' ){
       $lcnode=$node;
    }

    my $nd = xCAT::NetworkUtils->getNodeDomains([$lcnode]);
    my %nodedomains = %$nd;
    my $domain=$nodedomains{$lcnode};

    return $domain;

}


#get persistent command options from node and osimage definition
sub getPersistentKcmdline {
    my $lcnode=shift;
    if ( $lcnode eq 'THISNODE' ){
       $lcnode=$node;
    }

    my @nodes=($lcnode);

    my $bptab=xCAT::Table->new('bootparams',-create=>1);
    my $bphash = $bptab->getNodesAttribs(\@nodes,['addkcmdline']);

    my $typetab=xCAT::Table->new('nodetype',-create=>1);
    my $typehash=$typetab->getNodesAttribs(\@nodes,['provmethod']);
    my $linuximgtab=xCAT::Table->new('linuximage',-create=>1);

    my $ent = $typehash->{$lcnode}->[0];
    my $osimgname = $ent->{'provmethod'};

    my $linuximghash = $linuximgtab->getAttribs({imagename => $osimgname}, 'boottarget', 'addkcmdline');
    my $kern = $bphash->{$lcnode}->[0];

    my $addkcmdline;
    if ($kern->{addkcmdline}) {
        $addkcmdline .= $kern->{addkcmdline}." ";
    }

    if($linuximghash and $linuximghash->{'addkcmdline'})
    {
        unless($linuximghash->{'boottarget'})
        {
            $addkcmdline .= $linuximghash->{'addkcmdline'}." ";
        }
    }

    my $cmdhashref;
    if($addkcmdline){
       $cmdhashref=xCAT::Utils->splitkcmdline($addkcmdline);
    }

    my $ret="";
    if($cmdhashref and $cmdhashref->{persistent})
    {
       $ret=$cmdhashref->{persistent};
    }

    return $ret;
}


sub kickstartbootloader {
    my $line="bootloader";
    if($ENV{PERSKCMDLINE}){
       $line.=" --append=\"".$ENV{PERSKCMDLINE}."\"";
    }
    return $line;
}


sub esxipv6setup {
 if (not $::XCATSITEVALS{managedaddressmode} or $::XCATSITEVALS{managedaddressmode} =~ /v4/) { return ""; } # blank line for ipv4 schemes
 my $v6addr;
 if ($::XCATSITEVALS{managedaddressmode} eq "autoula") { 
	my $hoststab;
      my $mactab = xCAT::Table->new('mac',-create=>0);
      my $ent = $mactab->getNodeAttribs($node,['mac'],prefetchcache=>1);
      my $suffix = xCAT::Utils->parseMacTabEntry($ent->{mac},$node);
      $suffix = lc($suffix);
      unless ($mactab) { die "mac table should always exist prior to template processing when doing autoula"; }
 #in autoula, because ESXi weasel doesn't seemingly grok IPv6 at all, we'll have to do it in %pre
		unless ($hoststab) { $hoststab = xCAT::Table->new('hosts',-create=>1); }
		 $v6addr = autoulaaddress($suffix);
		$hoststab->setNodeAttribs($node,{ip=>$v6addr});
 } else {
 	my $hoststab = xCAT::Table->new('hosts',-create=>0);
	unless ($hoststab) { die "unable to proceed, no hosts table to  read from" }
	my $ent = $hoststab->getNodeAttribs($node,["ip"],prefetchcache=>1);
	unless ($ent and $ent->{ip}) { die "no hosts table entry with viable IP in hosts table for $node" }
	$v6addr = $ent->{ip};
	unless ($v6addr =~ /:/) { die "incorrect format for static ipv6 in hosts table for $node" }
 }
 return 'esxcfg-vmknic -i '.$v6addr.'/64 "Management Network"'." #ESXISTATICV6\n";
}




sub kickstartnetwork {
      my $line = "network --onboot=yes --bootproto="; 
      my $hoststab;
      my $mactab = xCAT::Table->new('mac',-create=>0);
      unless ($mactab) { $tmplerr ="mac table should always exist prior to template processing when doing autoula"; return;}
      my $ent = $mactab->getNodeAttribs($node,['mac'],prefetchcache=>1);
      unless ($ent and $ent->{mac}) { $tmplerr ="missing mac data for $node"; return;}
      my $suffix = xCAT::Utils->parseMacTabEntry($ent->{mac},$node);
      $suffix = lc($suffix);
	if ($::XCATSITEVALS{managedaddressmode} eq "autoula") {
		unless ($hoststab) { $hoststab = xCAT::Table->new('hosts',-create=>1); }
		$line .= "static --device=$suffix --noipv4 --ipv6=";
		my $ulaaddr = autoulaaddress($suffix);
		$hoststab->setNodeAttribs($node,{ip=>$ulaaddr});
		$line .= $ulaaddr;
	} elsif ($::XCATSITEVALS{managedaddressmode} =~ /static/)  {
                my ($ipaddr,$hostname,$gateway,$netmask)=xCAT::NetworkUtils->getNodeNetworkCfg($node);
                unless($ipaddr) { die "cannot resolve the network configuration of $node"; }
            
                if($gateway eq '<xcatmaster>'){
                   $gateway = xCAT::NetworkUtils->my_ip_facing($ipaddr);
                }

                $line .="static  --device=$suffix --ip=$ipaddr --netmask=$netmask --gateway=$gateway --hostname=$hostname ";

                my %nameservers=%{xCAT::NetworkUtils->getNodeNameservers([$node])};
                my @nameserverARR=split (",",$nameservers{$node});
                my @nameserversIP;
                foreach (@nameserverARR)
                {
                   my $ip;
                   if($_ eq '<xcatmaster>'){
                      $ip = xCAT::NetworkUtils->my_ip_facing($gateway);
                   }else{
                      (undef,$ip) = xCAT::NetworkUtils->gethostnameandip($_);
                   }
                   push @nameserversIP, $ip;

                }
                #there is no network option to set dns search domain in kickstart, it will be set in %post
                if (scalar @nameserversIP) {
                   $line .=" --nameserver=". join(",",@nameserversIP);
                } 


		#return "#KSNET static unsupported";
	} else {
		$line .= "dhcp --device=$suffix";
	}
	return $line;
}

sub mirrorspec{
      my $line;
      my $ostab    = xCAT::Table->new('nodetype'); 
      my %oents = %{$ostab->getNodesAttribs([$node],[qw(os arch profile provmethod)])};
      my $ent = $oents{$node}->[0];
      my $imagename;
      if ($ent and $ent->{provmethod} and ($ent->{provmethod} ne 'install') and ($ent->{provmethod} ne 'netboot') and ($ent->{provmethod} ne 'statelite')) {
            $imagename=$ent->{provmethod};
      }
      unless($imagename){
            $tmplerr ="cannot determine the osimage for $node"; 
            return;
      }

      my $pkgdirval;
      my $linuximagetab=xCAT::Table->new('linuximage', -create=>1);
      my $ref = $linuximagetab->getAttribs({imagename => $imagename}, 'pkgdir');
      if (($ref) && ($ref->{'pkgdir'})) {
            $pkgdirval=$ref->{'pkgdir'};
      }
      
      my $pkgdir;
      my @mirrors;
      my @pkgdirlist=split(/,/,$pkgdirval);
      foreach (@pkgdirlist){
               if($_ =~ /^http|ssh/){
                 push @mirrors,$_;
               }else{
                 $pkgdir=$_;
               }
      }
      
      if($pkgdir){
            $line .="
d-i mirror/country string manual\n
d-i mirror/protocol string http\n
d-i mirror/http/directory string $pkgdir\n
d-i mirror/http/proxy string\n";
      }

      if(scalar @mirrors){
         my $index=0;
         foreach(@mirrors){
            $line .= " 
d-i apt-setup/local$index/repository string deb $_\n
d-i apt-setup/local$index/comment string online mirror $index\n";
               $index=$index+1;
         }
      }

      return $line;
}



sub yast2network {
      my $line;
      my $hoststab;
      my $mactab = xCAT::Table->new('mac',-create=>0);
      unless ($mactab) { die "mac table should always exist prior to template processing when doing autoula"; }
      my $ent = $mactab->getNodeAttribs($node,['mac'],prefetchcache=>1);
      unless ($ent and $ent->{mac}) { die "missing mac data for $node"; }
      my $suffix = xCAT::Utils->parseMacTabEntry($ent->{mac},$node);
      $suffix = lc($suffix);
	if ($::XCATSITEVALS{managedaddressmode} eq "autoula") {
           #TODO
                return "#YAST2NET autoula unsupported"
	} elsif ($::XCATSITEVALS{managedaddressmode} =~ /static/)  {
                my ($ipaddr,$hostname,$gateway,$netmask)=xCAT::NetworkUtils->getNodeNetworkCfg($node);
                unless($ipaddr) { die "cannot resolve the network configuration of $node"; }

                if($gateway eq '<xcatmaster>'){
                   $gateway = xCAT::NetworkUtils->my_ip_facing($ipaddr);
                }

                my %nameservers=%{xCAT::NetworkUtils->getNodeNameservers([$node])};

                my @nameserverARR=split (",",$nameservers{$node});

                my @nameserversIP;
                foreach (@nameserverARR)
                {
                   my $ip;
                   if($_ eq '<xcatmaster>'){
                      $ip = xCAT::NetworkUtils->my_ip_facing($gateway);
                   }else{
                      (undef,$ip) = xCAT::NetworkUtils->gethostnameandip($_);
                   }
                   push @nameserversIP, $ip;

                }
 
                # get the domains for each node - one call for all nodes in hosts file
                my $nd = xCAT::NetworkUtils->getNodeDomains([$node]);
                my %nodedomains = %$nd;
                my $domain=$nodedomains{$node};
                my $networkhash={
                   'networking' => [
                            {
                              'dns' => [
                                         {
                                           'domain' => [
                                                         "$domain"
                                                       ],
                                           'dhcp_hostname' => [
                                                                {
                                                                  'content' => 'false',
                                                                  'config:type' => 'boolean'
                                                                }
                                                              ],
                                           'dhcp_resolv' => [
                                                              {
                                                                'content' => 'false',
                                                                'config:type' => 'boolean'
                                                              }
                                                            ],
                                           'nameservers' => [
                                                              {
                                                                'config:type' => 'list',
                                                                'nameserver' => [@nameserversIP]
                                                              }
                                                            ],
                                           'hostname' => [
                                                           $hostname
                                                         ],
                                           'searchlist' => [
                                                             {
                                                               'search' => [
                                                                             $domain
                                                                           ],
                                                               'config:type' => 'list'
                                                             }
                                                           ]
                                         }
                                       ],
                              'interfaces' => [
                                                {
                                                  'interface' => [
                                                                   {
                                                                     'bootproto' => [
                                                                                      'static'
                                                                                    ],
                                                                     'startmode' => [
                                                                                      'onboot'
                                                                                    ],
                                                                     'netmask' => [
                                                                                     $netmask
                                                                                  ],
                                                                     'device' => [
                                                                                   'eth0'
                                                                                 ],
                                                                     'ipaddr' => [
                                                                                   $ipaddr
                                                                                 ]
                                                                   }
                                                                 ],
                                                  'config:type' => 'list'
                                                }
                                              ],
                              'routing' => [
                                             {
                                               'ip_forward' => [
                                                                 {
                                                                   'content' => 'false',
                                                                   'config:type' => 'boolean'
                                                                 }
                                                               ],
                                               'routes' => [
                                                             {
                                                               'route' => [
                                                                            {
                                                                              'destination' => [
                                                                                                 'default'
                                                                                               ],
                                                                              'gateway' => [
                                                                                             $gateway
                                                                                           ],
                                                                              'netmask' => [
                                                                                             '-'
                                                                                           ],
                                                                              'device' => [
                                                                                            '-'
                                                                                          ]
                                                                            }
                                                                          ],
                                                               'config:type' => 'list'
                                                             }
                                                           ]
                                             }
                                           ]
                            }
                ]
        };
        my  $xml = new XML::Simple(KeepRoot => 1);
        $line=$xml->XMLout($networkhash); 

		#return "#KSNET static unsupported";
	} else {

        my $networkhash={
          'networking' => [
                          {
                            'dns' => [
                                     {
                                       'domain' => [
                                                   'local'
                                                 ],
                                       'dhcp_hostname' => [
                                                          {
                                                            'content' => 'true',
                                                            'config:type' => 'boolean'
                                                          }
                                                        ],
                                       'hostname' => [
                                                     'linux'
                                                   ],
                                       'dhcp_resolv' => [
                                                        {
                                                          'content' => 'true',
                                                          'config:type' => 'boolean'
                                                        }
                                                      ]
                                     }
                                   ],
                            'interfaces' => [
                                            {
                                              'interface' => [
                                                             {
                                                               'startmode' => [
                                                                              'onboot'
                                                                            ],
                                                               'bootproto' => [
                                                                              'dhcp'
                                                                            ],
                                                               'device' => [
                                                                           'eth0'
                                                                         ]
                                                             }
                                                           ],
                                              'config:type' => 'list'
                                            }
                                          ],
                            'routing' => [
                                         {
                                           'ip_forward' => [
                                                           {
                                                             'content' => 'false',
                                                             'config:type' => 'boolean'
                                                           }
                                                         ],
                                           'routes' => [
                                                       {
                                                         'config:type' => 'list'
                                                       }
                                                     ]
                                         }
                                       ]
                          }
                        ]
        };

        
        my  $xml = new XML::Simple(KeepRoot => 1);
        $line=$xml->XMLout($networkhash);             

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
   

   if( %::GLOBAL_TAB_HASH && defined( $::GLOBAL_TAB_HASH{$table} ) ) {
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
         my $savekey=$key;
         $key = '$NODE';  # make sure we use getNodeAttribs when get_replacement
                          # calls this routine (tabdb)
         my $rep=get_replacement($table,$key,$field);
         $key=$savekey;   # restore just in case we rely on the node=$node setting
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

#  This routine is used in the creation of the mypostscript file and is defined
# in /opt/xcat/share/xcat/templates/mypostcript/mypostscript.tmpl
# It cannot be moved to another perl library, due to migration problems.
#
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

sub getNM_GW()
{
    my $ip = shift;
    
    my $nettab = xCAT::Table->new("networks");
    if ($nettab) {
        my @nets = $nettab->getAllAttribs('net','mask','gateway');
        foreach my $net (@nets) {
            if (xCAT::NetworkUtils::isInSameSubnet( $net->{'net'}, $ip, $net->{'mask'}, 0)) {
                return (xCAT::NetworkUtils::formatNetmask($net->{'mask'},0,1), $net->{'gateway'});
            }
        }
    }

    return (undef, undef);
}


1;
