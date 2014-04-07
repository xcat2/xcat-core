#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::xcatd;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use strict;
use xCAT::Table;
use xCAT::MsgUtils;
use Data::Dumper;
use xCAT::NodeRange;
use xCAT::Utils;
#--------------------------------------------------------------------------------

=head1    xCAT::XCATD

=head2    Package Description

This program module file, is a set of utilities used by xCAT daemon. 

=cut


#------------------------------------------------------------------------------

=head3   validate 

  Here is where we check if  $peername is allowed to do $request in policy tbl.
   $peername, if set signifies client has a cert that the xCAT CA accepted.
   Logs to syslog and auditlog table all user commands, see site.auditskipcmds
   attribute. 
    
    Arguments:
        
    Returns:
        returns 1 if policy engine allows the action, 0 if denied.
    Globals:
        none
    Error:
        none
    Example:
       if(xCAT::XCATd->validate($peername,$peerhost,$req,$peerhostorg,\@deferredmsgargs)) {
                .
                .
    Comments:
        none
=cut

#------------------------------------------------------------------------------

sub validate {


  my $class=shift;
  my $peername=shift;
  my $peerhost=shift;
  my $request=shift;
  my $peerhostorg=shift;
  my $deferredmsgargs=shift;
   
  # now check the policy table if user can run the command
  my $policytable = xCAT::Table->new('policy');
  unless ($policytable) {
     xCAT::MsgUtils->message("S","Unable to open policy data, denying");
    return 0;
  }
 
  my $policies = $policytable->getAllEntries;
  $policytable->close;
  my $rule;
  my $peerstatus="untrusted";
  # This sorts the policy table  rows based on the level of the priority field in the row.
  # note the lower the number in the policy table the higher the priority
  my @sortedpolicies = sort { $a->{priority} <=> $b->{priority} } (@$policies);
  # check to see if peerhost is trusted
  foreach $rule (@sortedpolicies) {
     
    if (($rule->{name} and $rule->{name} eq $peername)  && ($rule->{rule}=~ /trusted/i)) {
     $peerstatus="Trusted";
     last;
    }
  }
  RULE: foreach $rule (@sortedpolicies) {
    if ($rule->{name} and $rule->{name} ne '*') {
      #TODO: more complex matching (lists, wildcards)
      next unless ($peername and $peername eq $rule->{name});
    }
    if ($rule->{name} and $rule->{name} eq '*') { #a name is required, but can be any name whatsoever....
      next unless ($peername);
    }
    if ($rule->{time} and $rule->{time} ne '*') {
      #TODO: time ranges
    }
    if ($rule->{host} and $rule->{host} ne '*') {
      #TODO: more complex matching (lists, noderanges?, wildcards)
      next unless ($peerhost eq $rule->{host});
    }
    if ($rule->{commands} and $rule->{commands} ne '*') {
      my @commands = split(",", $rule->{commands});
      my $found =0;
      foreach my $cmd (@commands) {
        if ($request->{command}->[0] eq $cmd) {
           $found=1;
           last;
        }
      }
      if ($found == 0) {  # no command match
        next ;
      }
    }
    if ($rule->{parameters} and $rule->{parameters} ne '*') {
      my $parms;
      if ($request->{arg}) {
         $parms = join(' ',@{$request->{arg}});
      } else {
         $parms = "";
      }
      my $patt = $rule->{parameters};
      unless ($parms =~ /$patt/) {
         next;
      }
    }
    if ($rule->{noderange} and $rule->{noderange} ne '*') {
      my $matchall=0;
      if ($rule->{rule} =~ /allow/i or $rule->{rule} =~ /accept/i or $rule->{rule} =~ /trusted/i) {
          $matchall=1;
      }
      
      if (defined $request->{noderange}->[0]) {
        my @tmpn= xCAT::NodeRange::noderange($request->{noderange}->[0]);
        $request->{node}=\@tmpn;
      }
      unless (defined $request->{node}) {
          next RULE;
      }
      my @reqnodes = @{$request->{node}};
      my %matchnodes;
      foreach (noderange($rule->{noderange})) {
          $matchnodes{$_}=1;
      }
      REQN: foreach (@reqnodes) {
          if (defined ($matchnodes{$_})) {
              if ($matchall) {
                  next REQN;
              } else {
                last REQN;
              }
          } elsif ($matchall) {
                  next RULE;
          }
      }
    }
    # If we are still in, that means this rule is the first match and dictates behavior.
    # We are not going to log getdestiny,getbladecons,getipmicons commands, way
    # too many of them
    #print Dumper($request);
    if ($rule->{rule}) {
      my $logst;
      my $rc;
      my $status;
      if ($rule->{rule} =~ /allow/i or $rule->{rule} =~ /accept/i or $rule->{rule} =~ /trusted/i) {
         $logst = "xCAT: Allowing ".$request->{command}->[0];
         $status = "Allowed";
         $rc=1;
      } else {
         $logst = "xCAT: Denying ".$request->{command}->[0];
         $status = "Denied";
         $rc=0;
      }
     if (($request->{command}->[0] ne "getdestiny") && ($request->{command}->[0] ne "getbladecons") && ($request->{command}->[0] ne "getipmicons")) {
      # set username authenticated to run command
      # if from Trusted host, use input username,  else set from creds
      if (($request->{username}) && defined($request->{username}->[0])) {
         if ($peerstatus ne "Trusted" ) {  # then set to peername
            $request->{username}->[0] = $peername;
         }
      } else {
            $request->{username}->[0] = $peername;
      }
      if ($request->{noderange} && defined($request->{noderange}->[0]))
       {
          $logst .= " to ".$request->{noderange}->[0];
       } else { # no noderange maybe a nodes
          
           if ($request->{node} && defined($request->{node}->[0])) {
             my @reqnodes = @{$request->{node}};
             if (@reqnodes) {
               $logst .= " to ";
               foreach my $node (@reqnodes) {
                 $logst .= "$node,";
               }
               chop $logst;
             }
           }
       }
        # add each argument
      my $args = $request->{arg};
      my $arglist;
      foreach my $argument (@$args){

             $arglist .= " " . $argument;
      }
      if ($arglist) { $logst .= $arglist; }
      if($peername) { $logst .= " for " . $request->{username}->[0]};
      if ($peerhost) { $logst .= " from " . $peerhost };

      # read site.auditskipcmds attribute,
      # if set skip commands else audit all cmds.
      my @skipcmds=($::XCATSITEVALS{auditskipcmds}); #xCAT::Utils->get_site_attribute('auditskipcmds');
      # if not "ALL" and not a command from site.auditskipcmds 
      # and not getcredentials and not getcredentials ,
      # put in syslog and  auditlog
      my $skip = 0; 
      my $all = "all";
      if (defined($skipcmds[0])) { # if there are values
        if (grep(/$all/i, @skipcmds)) {  # skip all
           $skip = 1;
        } else {
          if (grep(/$request->{command}->[0]/, @skipcmds)) {  # skip the command 
             $skip = 1;
          }
          # if skip clienttype clienttype:value
          my $client="clienttype:";
          $client .= $request->{clienttype}->[0];
          if (grep(/$client/, @skipcmds)) { #skip the client 
             $skip = 1;
          }
        }
        
      }
      @$deferredmsgargs=(); #should be redundant, but just in case
      if (($request->{command}->[0] ne "getpostscript") && ($request->{command}->[0] ne "getcredentials") && ($skip == 0)) {
      
        # put in audit Table and syslog
        my $rsp = {};
        $rsp->{syslogdata}->[0] = $logst;
        if ($peername) {
           $rsp->{userid} ->[0] = $request->{username}->[0];
        }
        if ($peerhost) {
          $rsp->{clientname} -> [0] = $peerhost;
        }
        if (defined $request->{clienttype}) {
          $rsp->{clienttype} -> [0] = $request->{clienttype} -> [0];
        } else {
           if (defined $request->{becomeuser}) {
             $rsp->{clienttype} -> [0] = "webui";
           } else {
             $rsp->{clienttype} -> [0] = "other";
           }
        }
        $rsp->{command} -> [0] = $request->{command}->[0];
        if ($request->{noderange} && defined($request->{noderange}->[0])) { 
            $rsp->{noderange} -> [0] = $request->{noderange}->[0];
        }
        $rsp->{args} -> [0] =$arglist; 
        $rsp->{status} -> [0] = $status;
        @$deferredmsgargs = ("SA",$rsp);
      } else { # getpostscript or getcredentials, just syslog
          unless ($::XCATSITEVALS{skipvalidatelog}) { @$deferredmsgargs=("S",$logst); }
      }
     } # end getbladecons,etc check
      return $rc;
    } else { #Shouldn't be possible....
       xCAT::MsgUtils->message("S","Impossible line in xcatd reached");
      return 0;
    }
  } # end RULE
  #Reached end of policy table, reject by default.
   xCAT::MsgUtils->message("S","Request matched no policy rule: peername=$peername, peerhost=$peerhost  ".$request->{command}->[0]);
  return 0;
}

my $tokentimeout = 86400;  # one day
# this subroutine search the token table 
# 1. find the existed token entry for the user and reset the expire time
# 1.1. if not find existed token, create a new one and add it to token table
# 2. clean up the expired token
#
# this subroutine is called after the account has been authorized 
sub gettoken {
    my $class=shift;
    my $req = shift;

    my $user = $req->{gettoken}->[0]->{username}->[0];
    my $tokentb = xCAT::Table->new('token');
    unless ($tokentb) {
        return undef;
    }
    my $tokens = $tokentb->getAllEntries;
    my $expiretime = time() + $tokentimeout;
    foreach my $token (@{$tokens}) {
        if ($token->{username} eq $user) {
            #delete old token
            $tokentb->delEntries({'tokenid'=>$token->{tokenid}});
        } else {
            #clean the expired token
            if ($token->{expire} > $expiretime) {
                $tokentb->delEntries({'tokenid'=>$token->{tokenid}});
            }
        }
    }
    
    # create a new token for this request
    my $uuid = xCAT::Utils->genUUID();
    $tokentb->setAttribs({tokenid=>$uuid, username => $user}, {expire => $expiretime});
    $tokentb->close();
   
    return ($uuid, $expiretime);
}

# verify the token has correct entry in token table and expire time is not exceeded.
sub verifytoken {
    my $class=shift;
    my $req = shift;

    my $tokenid = $req->{tokens}->[0]->{tokenid}->[0];
    my $tokentb = xCAT::Table->new('token');
    unless ($tokentb) {
        return undef;
    }
    my $token = $tokentb->getAttribs({'tokenid' => $tokenid}, ('username', 'expire'));
    if (defined ($token) && defined ($token->{'username'}) && defined ($token->{'expire'})) {
        my $expiretime = time() + $tokentimeout;
        if ($token->{'expire'} < time()) {
            $tokentb->delEntries({'tokenid'=>$token->{tokenid}});
            return undef;
        } else {
            return $token->{'username'};
        }
    } else {
        return undef;
    }
}

1;
