# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::bmcconfig;
use Data::Dumper;
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::Utils;
use IO::Select;
use Socket;

sub handled_commands {
    return {
          getbmcconfig => 'bmcconfig',
        };
}

sub genpassword {
  my $length = shift;
  my $password='';
  my $characters= 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234567890';
  srand; #have to reseed, rand is not rand otherwise
  while (length($password) < $length) {
    $password .= substr($characters,int(rand 63),1);
  }
  return $password;
}

sub net_parms {
  my $ip = shift;
  if (inet_aton($ip)) {
     $ip = inet_ntoa(inet_aton($ip));
  } else {
     xCAT::MsgUtils->message("S","Unable to resolve $ip");
     return undef;
  }
  my $nettab = xCAT::Table->new('networks');
  unless ($nettab) { return undef };
  my @nets = $nettab->getAllAttribs('net','mask','gateway');
  foreach (@nets) {
    my $net = $_->{'net'};
    my $mask =$_->{'mask'};
    my $gw = $_->{'gateway'};
    $ip =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/;
    my $ipnum = ($1<<24)+($2<<16)+($3<<8)+$4;
    $mask =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/;
    my $masknum = ($1<<24)+($2<<16)+($3<<8)+$4;
    $net =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/;
    my $netnum = ($1<<24)+($2<<16)+($3<<8)+$4;
    if ($gw eq '<xcatmaster>') {
	$gw=xCAT::Utils->my_ip_facing($ip);
    }
    if (($ipnum & $masknum)==$netnum) {
      return ($ip,$mask,$gw);
    } 
  }
  xCAT::MsgUtils->message("S","xCAT BMC configuration error, no appropriate network for $ip found in networks, unable to determine netmask");
}

  
sub ok_with_node {
   my $node = shift;
   #Here we connect to the node on a privileged port (in the clear) and ask the
   #node if it just asked us for credential.  It's convoluted, but it is 
   #a convenient way to see if root on the ip has approved requests for
   #credential retrieval.  Given the nature of the situation, it is only ok
   #to assent to such requests before users can log in.  During postscripts
   #stage in stateful nodes and during the rc scripts of stateless boot
   my $select = new IO::Select;
   #sleep 0.5; # gawk script race condition might exist, try to lose just in case
   my $sock = new IO::Socket::INET(PeerAddr=>$node,
                                     Proto => "tcp",
                                     PeerPort => shift);
   my $rsp;
   unless ($sock) {return 0};
   $select->add($sock);
   print $sock "CREDOKBYYOU?\n";
   unless ($select->can_read(5)) { #wait for data for up to five seconds
      return 0;
   }
   my $response = <$sock>;
   chomp($response);
   if ($response eq "CREDOKBYME") {
      return 1;
   }
   return 0;
}

sub process_request  {
  my $request = shift;
  my $callback = shift;
  my $node = $request->{'_xcat_clienthost'}->[0];
  unless (ok_with_node($node,300)) {
     $callback->({error=>["Unable to prove root on your IP approves of this request"],errorcode=>[1]});
     return;
  }
  my $sitetable = xCAT::Table->new('site');
  my $ipmitable = xCAT::Table->new('ipmi');
  my $passtable = xCAT::Table->new('passwd');
  my $tmphash;
  my $username = 'USERID';
  my $gennedpassword=0;
  my $bmc;
  my $password = 'PASSW0RD';
  if ($passtable) { ($tmphash)=$passtable->getAttribs({key=>'ipmi'},'username','password'); }
  #Check for generics, can grab for both user and pass with a query
  #since they cannot be in disparate records in passwd tab
  if ($tmphash->{username}) { 
    $username=$tmphash->{username};
  }
  if ($tmphash->{password}) { #It came for free with the last query
    $password=$tmphash->{password};
  }
  $tmphash=($sitetable->getAttribs({key=>'genpasswords'},'value'))[0];
  if ($tmphash->{value} eq "1" or $tmphash->{value}  =~ /y(es)?/i) {
    $password = genpassword(8)."1c";
    $gennedpassword=1;
    $tmphash=$ipmitable->getNodeAttribs($node,['bmc','username','bmcport']);
  } else {
    $tmphash=$ipmitable->getNodeAttribs($node,['bmc','username','bmcport','password']);
    if ($tmphash->{password}) {
      $password = $tmphash->{password};
    }
  }
  my $bmcport;
  if (defined $tmphash->{bmcport}) {
      $bmcport = $tmphash->{bmcport};
  }
  if ($tmphash->{bmc} ) {
    $bmc=$tmphash->{bmc};
  }
  if ($tmphash->{username}) {
    $username = $tmphash->{username};
  }
  unless (defined $bmc) {
     xCAT::MsgUtils->message('S',"Unable to identify bmc for $node, refusing to give config data");
     $callback->({error=>["Invalid table configuration for bmcconfig"],errorcode=>[1]});
     return 1;
  }
  foreach my $sbmc (split /,/,$bmc) {
	  (my $ip,my $mask,my $gw) = net_parms($sbmc);
	  unless ($ip and $mask and $username and $password) {
	     xCAT::MsgUtils->message('S',"Unable to determine IP, netmask, username, and/or pasword for $sbmc, ensure that host resolution is working.  Best guess parameters would have been: IP: '$ip', netmask: '$netmask', username: '$username', password: '$password'",  );
	     $callback->({error=>["Invalid table configuration for bmcconfig"],errorcode=>[1]});
	     return 1;
	  }
	  my $response={bmcip=>$ip,netmask=>$mask,gateway=>$gw,username=>$username,password=>$password};
	  if (defined $bmcport) {
	      $response->{bmcport}=$bmcport;
	  }
  	$callback->($response);
  }
  if ($gennedpassword) { # save generated password
    $ipmitable->setNodeAttribs($node,{password=>$password});
  }

  return 1;
}



1;

