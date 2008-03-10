#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::Template;
use strict;
use xCAT::Table;
use File::Basename;
use File::Path;
use Data::Dumper;
use Sys::Syslog;

my $tmplerr;
my $table;
my $key;
my $field;
my $idir;
my $node;

sub subvars { 
  my $self = shift;
  my $inf = shift;
  my $outf = shift;
  $node = shift;
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
  $et = $noderestab->getNodeAttribs($node,['servicenode']);
  if ($et and $et->{'servicenode'}) { 
    $master = $et->{'servicenode'};
  }
  $et = $noderestab->getNodeAttribs($node,['xcatmaster']);
  if ($et and $et->{'xcatmaster'}) { 
    $master = $et->{'xcatmaster'};
  }
  unless ($master) {
      die "Unable to identify master for $node";
  }
  $ENV{XCATMASTER}=$master;
  #FIRST, do *all* includes, recursive and all
  my $doneincludes=0;
  while (not $doneincludes) {
    $doneincludes=1;
    if ($inc =~ /#INCLUDE:[^#]+#/) {
      $doneincludes=0;
      $inc =~ s/#INCLUDE:([^#]+)#/includefile($1)/eg;
    }
  }
  #ok, now do everything else..
  $inc =~ s/#COMMAND:([^#]+)#/command($1)/eg;
  $inc =~ s/#TABLE:([^:]+):([^:]+):([^#]+)#/tabdb($1,$2,$3)/eg;
  $inc =~ s/#CRYPT:([^:]+):([^:]+):([^#]+)#/crydb($1,$2,$3)/eg;
  $inc =~ s/#XCATVAR:([^#]+)#/envvar($1)/eg;
  $inc =~ s/#ENV:([^#]+)#/envvar($1)/eg;
  if ($tmplerr) {
     close ($outh);
     return $tmplerr;
   }
  print $outh $inc;
  close($outh);
  return 0;
}
sub includefile
{
	my $file = shift;
	my $text = "";
    unless ($file =~ /^\//) {
      $file = $idir."/".$file;
    }

	open(INCLUDE,$file) || \
		return "#INCLUDEBAD:cannot open $file#";

	while(<INCLUDE>) {
		$text .= "$_";
	}

	close(INCLUDE);

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
    my $tabh = xCAT::Table->new($table);
    unless ($tabh) {
       $tmplerr="Unable to open table named $table";
       if ($table =~ /\.tab/) {
          $tmplerr .= " (.tab should not be specified as part of the table name in xCAT 2, as seems to be the case here)";
       }
      return "";
    }
    my $ent;
    if ($key eq "THISNODE" or $key eq '$NODE') {
      $ent = $tabh->getNodeAttribs($node,[$field]);
    } else {
      my %kp;
      foreach (split /,/,$key) {
        my $key;
        my $val;
        ($key,$val) = split /=/,$_;
        $kp{$key}=$val;
      }
      ($ent) = $tabh->getAttribs(\%kp,$field);
    }
    $tabh->close;
    unless($ent and  defined($ent->{$field})) {
      $tmplerr="Unable to find requested $field from $table in this context";
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
