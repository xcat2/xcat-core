#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::Template;
use strict;
use xCAT::Table;
use File::Basename;
use File::Path;
use Data::Dumper;
use Sys::Syslog;
use xCAT::ADUtils; #to allow setting of one-time machine passwords
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

sub subvars { 
  my $self = shift;
  my $inf = shift;
  my $outf = shift;
  $tmplerr=undef; #clear tmplerr since we are starting fresh
  $node = shift;
  my $pkglistfile=shift;

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
  my $sitetab = xCAT::Table->new('site');
  my $noderestab = xCAT::Table->new('noderes');
  (my $et) = $sitetab->getAttribs({key=>"master"},'value');
  if ($et and $et->{value}) {
      $master = $et->{value};
  }
  $et = $noderestab->getNodeAttribs($node,['xcatmaster']);
  if ($et and $et->{'xcatmaster'}) { 
    $master = $et->{'xcatmaster'};
  }
  unless ($master) {
      die "Unable to identify master for $node";
  }
  $ENV{XCATMASTER}=$master;

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
  #ok, now do everything else..
  $inc =~ s/#XCATVAR:([^#]+)#/envvar($1)/eg;
  $inc =~ s/#ENV:([^#]+)#/envvar($1)/eg;
  $inc =~ s/#MACHINEPASSWORD#/machinepassword()/eg;
  $inc =~ s/#TABLE:([^:]+):([^:]+):([^#]+)#/tabdb($1,$2,$3)/eg;
  $inc =~ s/#TABLEBLANKOKAY:([^:]+):([^:]+):([^#]+)#/tabdb($1,$2,$3,'1')/eg;
  $inc =~ s/#CRYPT:([^:]+):([^:]+):([^#]+)#/crydb($1,$2,$3)/eg;
  $inc =~ s/#COMMAND:([^#]+)#/command($1)/eg;
  $inc =~ s/#INCLUDE_NOP:([^#^\n]+)#/includefile($1,1,0)/eg;
  $inc =~ s/#INCLUDE_PKGLIST:([^#^\n]+)#/includefile($1,0,1)/eg;
  $inc =~ s/#INCLUDE_PTRNLIST:([^#^\n]+)#/includefile($1,0,2)/eg;
  $inc =~ s/#INCLUDE_RMPKGLIST:([^#^\n]+)#/includefile($1,0,3)/eg;
  $inc =~ s/#INCLUDE:([^#^\n]+)#/includefile($1, 0, 0)/eg;
  $inc =~ s/#HOSTNAME#/$node/eg;


  if ($tmplerr) {
     close ($outh);
     return $tmplerr;
   }
  print $outh $inc;
  close($outh);
  return 0;
}
sub machinepassword {
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
    my $sitetab = xCAT::Table->new('site');
    unless ($sitetab) {
        return "ERROR: unable to open site table"; 
    }
    my $domain;
    (my $et) = $sitetab->getAttribs({key=>"domain"},'value');
    if ($et and $et->{value}) {
        $domain = $et->{value};
    }
    unless ($domain) {
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
    my $server = $sitetab->getAttribs({key=>'directoryserver'},['value']);
    if ($server and $server->{value}) {
        $server = $server->{value};
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
         $tmplerr="Unable to find requested $field from $table, with $key";
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

1;
