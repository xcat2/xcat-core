#!/usr/bin/perl
package xCAT::SwitchHandler;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::MacMap;
use IO::Select;
use IO::Handle;
use Sys::Syslog;
use Data::Dumper;
use POSIX qw/WNOHANG/;
use SNMP;

my $sysDescr='.1.3.6.1.2.1.1.1';

sub new {
  my $self = {};
  my $proto = shift;
  my $class = ref($proto) || $proto;
  $self->{switch} = shift;
  
  bless ($self, $class);
  return $self;
}


sub fill_sessionparms {
  my $self = shift;
  my %args = @_;
  my $community=$args{community};
  $self->{sessionparms}=$args{sessionents};
  if ($self->{sessionparms}->{snmpversion}) {
      if ($self->{sessionparms}->{snmpversion} =~ /3/) { #clean up to accept things like v3 or ver3 or 3, whatever.
	  $self->{sessionparms}->{snmpversion}=3;
	  unless ($self->{sessionparms}->{auth}) {
	      $self->{sessionparms}->{auth}='md5'; #Default to md5 auth if not specified but using v3
	  }
      } elsif ($self->{sessionparms}->{snmpversion} =~ /2/) {
	  $self->{sessionparms}->{snmpversion}=2;
      } else {
	  $self->{sessionparms}->{snmpversion}=1; #Default to lowest common denominator, snmpv1
      }
  }
  unless (defined $self->{sessionparms}->{password}) { #if no password set, inherit the community
      $self->{sessionparms}->{password}=$community;
  }
}



sub setoid {
    my $session = shift;
    my $oid = shift;
    my $offset = shift;
    my $value = shift;
    my $type = shift;
    unless ($type) { $type = 'INTEGER'; }
    my $varbind = new SNMP::Varbind([$oid,$offset,$value,$type]);
    my $data = $session->set($varbind);
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    return 0,$varbind;
}

#---------------------------------------------------------
=head3  getsnmpsession
   It gets an snmp session appropriate for a switch using the switches table 
   for guidance on the hows.
   Arguments: vlan=> $vid if needed for community string indexing (optional)
=cut
#------------------------------------------------------------
sub getsnmpsession {
    my $self = shift;
    my $community=shift;
    my $vlanid = shift;
    my $switch = $self->{switch};
    my $session;
    my $sessionparams;
    
    if (!$community) { $community="private"; }

    $self->{sitetab} = xCAT::Table->new('site');
    my $tmp = $self->{sitetab}->getAttribs({key=>'snmpc'},'value');
    if ($tmp and $tmp->{value}) { $community = $tmp->{value} }

    my $switchestab=xCAT::Table->new('switches',-create=>0);
    my $ent = $switchestab->getNodeAttribs($switch, [qw(switch snmpversion username password privacy auth)]);
    if ($ent) {
	$self->fill_sessionparms(community=>$community, sessionents=>$ent);
    }
 	
    $sessionparams=$self->{sessionparms};    

    my $snmpver='1';
    if ($sessionparams) {
	$snmpver=$sessionparams->{snmpversion};
	$community=$sessionparams->{password};
    }

    if ($snmpver ne '3') {
	if ($vlanid) { $community .= '@'.$vlanid; }
	$session = new SNMP::Session(
	    DestHost => $switch,
	    Version => $snmpver,
	    Community => $community,
	    UseNumeric => 1
	    );
    } else { #we have snmp3
	my %args= (
	    DestHost => $switch,
	    SecName => $sessionparams->{username},
	    AuthProto => uc($sessionparams->{auth}),
	    AuthPass => $community,
	    Version => $snmpver,
	    SecLevel => 'authNoPriv',
	    UseNumeric => 1
	    );
	if ($vlanid) { $args{Context}="vlan-".$vlanid; }
	if ($sessionparams->{privacy}) {
	    $args{SecLevel}='authPriv';
	    $args{PrivProto} = uc($sessionparams->{privacy});
	    $args{PrivPass} = $community;
	    $args{Retries} = 4;
	    $args{Timeout}=1500000; 
	}

        #print "args=" . Dumper(%args) . "\n";
	$session = new SNMP::Session(%args);
    }

    #print "switch=$switch\n";
    if (!$session) { return $session;}

    #get the the switch brand name
    my $tmp = xCAT::MacMap::walkoid($session, "$sysDescr", silentfail=>1);
    my $swbrand;
    if ($tmp->{0}) {
	#print "Desc=" . $tmp->{0} . "\n";
	my @switch_plugins=glob("$::XCATROOT/lib/perl/xCAT_plugin/vlan/*.pm");
	foreach my $fn (@switch_plugins) {
	    $fn =~ /.*\/([^\/]*).pm$/;
	    my $module = $1;
	    #print "fn=$fn,modele=$module\n";
	    if ( ! eval { require "$fn" }) {
		xCAT::MsgUtils->message("S", "Cannot load module $fn");
		next;
	    } else {
		no strict 'refs';
		my $filter=${"xCAT_plugin::vlan::".$module."::"}{filter_string}->();
		my $descr=$tmp->{0};
		if ($descr =~ /$filter/) {
		    $self->{module}=$module;
		    #print "found it:$module\n";
		    last;
		}
	    }
	}
    }

    if (!exists($self->{module})) {
	$self->{session}=0;
	return 0;
    } else {
	$self->{session}=$session;
	return $session;
    }
}


                
#--------------------------------------------------------------
=head3 get_vlan_ids    

  It gets the existing vlan IDs for the switch.
  Returns:  an array containing all the vlan ids for the switch
=cut
#-------------------------------------------------------------
sub get_vlan_ids {
  my $self = shift;
  my $session=$self->{session};
  if (! $self->{session}) {
    $session  = $self->getsnmpsession();
  }
  unless ($session) { xCAT::MsgUtils->message("S","Failed to communicate with " . $self->{switch} . " or find a plugin module for the switch."); return; }

  no strict 'refs';
  return ${"xCAT_plugin::vlan::".$self->{module}."::"}{get_vlan_ids}->($session);
}


#--------------------------------------------------------------
=head3 get_vlanids_for_ports   
    It returns a hash pointer that contains the vlan id for each given port.
=cut
#-------------------------------------------------------------
sub get_vlanids_for_ports {
  my $self = shift;
  my @ports=@_;

  my $session=$self->{session};
  if (! $self->{session}) {
    $session  = $self->getsnmpsession();
  }
  unless ($session) { xCAT::MsgUtils->message("S","Failed to communicate with " . $self->{switch} . " or find a plugin module for the switch."); return; }

  no strict 'refs';
  return ${"xCAT_plugin::vlan::".$self->{module}."::"}{get_vlanids_for_ports}->($session, @ports);

}


#--------------------------------------------------------------
=head3 create_vlan   
    Creates a new vlan on the switch
    Returns an array. (erorcode, errormsg). When errorcode=0, means no error.
=cut
#-------------------------------------------------------------
sub  create_vlan {
    my $self = shift;
    my $vlan_id=shift;
    my $vlan_name="xcat_vlan_" . $vlan_id;

    #print "create vlan get called.\n";
       
    my $session=$self->{session};
    if (! $self->{session}) {
	$session  = $self->getsnmpsession();
    }
    #my $session  = $self->getsnmpsession();
    unless ($session) { xCAT::MsgUtils->message("S","Failed to communicate with " . $self->{switch}. " or find a plugin module for the switch."); return; }
    #print Dumper($self->{sessionparms});

    no strict 'refs';
    return ${"xCAT_plugin::vlan::".$self->{module}."::"}{create_vlan}->($session, $vlan_id);
}

#--------------------------------------------------------------
=head3 add_ports_to_vlan   
    Adds the given ports to the existing vlan
    Returns an array. (erorcode, errormsg). When errorcode=0, means no error.
=cut
#-------------------------------------------------------------
sub  add_ports_to_vlan {
    my $self = shift;
    my $vlan_id=shift;
    my $portmode=shift;
    my @ports=@_;
    
    #print "vlan=$vlan_id, ports=@ports\n";
    
    my $session=$self->{session};
    if (! $self->{session}) {
	$session  = $self->getsnmpsession();
    }
    #my $session  = $self->getsnmpsession();
    unless ($session) { xCAT::MsgUtils->message("S","Failed to communicate with " . $self->{switch}. " or find a plugin module for the switch."); return; }

    no strict 'refs';
    return ${"xCAT_plugin::vlan::".$self->{module}."::"}{add_ports_to_vlan}->($session, $vlan_id, $portmode, @ports);
}

#-------------------------------------------------------
=head3  add_crossover_ports_to_vlan
  It enables the vlan on the cross-over links.
    Returns an array. (erorcode, errormsg). When errorcode=0, means no error.
=cut
#-------------------------------------------------------
sub add_crossover_ports_to_vlan {
    my $self = shift;
    my $vlan_id=shift;
    my @switches=@_;

    if (@switches == 0) { return (0, ""); }

    my $session=$self->{session};
    if (! $self->{session}) {
	$session  = $self->getsnmpsession();
    }
    #my $session  = $self->getsnmpsession();
    unless ($session) { xCAT::MsgUtils->message("S","Failed to communicate with " . $self->{switch}. " or find a plugin module for the switch."); return; }

    no strict 'refs';
    return ${"xCAT_plugin::vlan::".$self->{module}."::"}{add_crossover_ports_to_vlan}->($session, $vlan_id, $self->{switch}, @switches);    
}

#--------------------------------------------------------------
=head3 remove_vlan   
    Remove a vlan from the switch
    Returns an array. (erorcode, errormsg). When errorcode=0, means no error.
=cut
#-------------------------------------------------------------
sub  remove_vlan {
    my $self = shift;
    my $vlan_id=shift;
    
    my $session=$self->{session};
    if (! $self->{session}) {
	$session  = $self->getsnmpsession();
    }
    #my $session  = $self->getsnmpsession();
    unless ($session) { xCAT::MsgUtils->message("S","Failed to communicate with " . $self->{switch}. " or find a plugin module for the switch."); return; }

    no strict 'refs';
    return ${"xCAT_plugin::vlan::".$self->{module}."::"}{remove_vlan}->($session, $vlan_id);
}

#--------------------------------------------------------------
=head3 remove_ports_from_vlan  
    Remove ports from a vlan
    Returns an array. (erorcode, errormsg). When errorcode=0, means no error.
=cut
#-------------------------------------------------------------
sub  remove_ports_from_vlan {
    my $self = shift;
    my $vlan_id=shift;
    my @ports = @_;
    
    my $session=$self->{session};
    if (! $self->{session}) {
	$session  = $self->getsnmpsession();
    }
    #my $session  = $self->getsnmpsession();
    unless ($session) { xCAT::MsgUtils->message("S","Failed to communicate with " . $self->{switch}. " or find a plugin module for the switch."); return; }

    no strict 'refs';
    return ${"xCAT_plugin::vlan::".$self->{module}."::"}{remove_ports_from_vlan}->($session, $vlan_id, @ports);
}



1;
