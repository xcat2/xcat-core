# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::bmcconfig;
use Data::Dumper;
use xCAT::Table;

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
  if ($ip =~ /[A-Za-z]/) {
    my $addr = (gethostbyname($ip))[4];
    my @bytes = unpack("C4",$addr);
    $ip = join(".",@bytes);
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
    if (($ipnum & $masknum)==$netnum) {
      return ($ip,$mask,$gw);
    } 
  }
}

  

sub process_request  {
  my $request = shift;
  my $callback = shift;
  my $node = $request->{'!xcat_clienthost'}->[0];
  my $sitetable = xCAT::Table->new('site');
  my $ipmitable = xCAT::Table->new('ipmi');
  my $passtable = xCAT::Table->new('passwd');
  my $tmphash;
  my $username = 'USERID';
  my $gennedpassword=0;
  my $bmc;
  my $password = 'PASSW0RD';
  if ($passtable) { $tmphash=$passtable->getAttribs({key=>'ipmi'},'username','password'); }
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
    $password = genpassword(8);
    $gennedpassword=1;
  } else {
    $tmphash=$ipmitable->getNodeAttribs($node,['password']);
    if ($tmphash->{password}) {
      $password = $tmphash->{password};
    }
  }
  $tmphash=$ipmitable->getNodeAttribs($node,['bmc','username']);
  if ($tmphash->{bmc} ) {
    $bmc=$tmphash->{bmc};
  }
  if ($tmphash->{username}) {
    $username = $tmphash->{username};
  }
  (my $ip,my $mask,my $gw) = net_parms($bmc);
  my $response={bmcip=>$ip,netmask=>$mask,gateway=>$gw,username=>$username,password=>$password};
  $callback->($response);
  if ($gennedpassword) { # save generated password
    $ipmitable->setNodeAttribs($node,{password=>$password});
  }

  return 1;
}



1;

