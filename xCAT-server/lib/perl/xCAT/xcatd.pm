#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::xcatd;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use strict;
use Date::Parse;
use xCAT::Table;
use xCAT::TableUtils;
use xCAT::MsgUtils;
use Data::Dumper;
use xCAT::NodeRange;
use xCAT::Utils;
use Scalar::Util qw/looks_like_number/;

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
   attribute and auditnosyslog attribute.

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


    my $class           = shift;
    my $peername        = shift;
    my $peerhost        = shift;
    my $request         = shift;
    my $peerhostorg     = shift;
    my $deferredmsgargs = shift;

    my @filtered_cmds   = qw( getdestiny getbladecons getipmicons getopenbmccons getcons);

    # now check the policy table if user can run the command
    my $policytable = xCAT::Table->new('policy');
    unless ($policytable) {
        xCAT::MsgUtils->message("S", "Unable to open policy data, denying");
        return 0;
    }

    my $remote_host = undef;
    if ($request->{'remote_client'} && defined($request->{'remote_client'}->[0])) {
        $remote_host = $request->{'remote_client'}->[0];
    }

    my $policies = $policytable->getAllEntries;
    $policytable->close;
    my $rule;
    my $peerstatus = "untrusted";

    # This sorts the policy table  rows based on the level of the priority field in the row.
    # note the lower the number in the policy table the higher the priority
    my @sortedpolicies = sort { $a->{priority} <=> $b->{priority} } (@$policies);

    # check to see if peerhost is trusted
    foreach $rule (@sortedpolicies) {

        if (($rule->{name} and $rule->{name} eq $peername) && ($rule->{rule} =~ /trusted/i)) {
            $peerstatus = "Trusted";
            last;
        }
    }

    my %req_noderange_info;
    if (defined $request->{noderange}->[0]) {
        my @tmpn = xCAT::NodeRange::noderange($request->{noderange}->[0]);
        $req_noderange_info{leftnodenum} = @tmpn;
        if($req_noderange_info{leftnodenum}){
            $req_noderange_info{leftnodes} =  \@tmpn;
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
            if (defined($remote_host) and $remote_host ne '') {
                my @tmp_hosts = split(",",$remote_host);
                my $found = 0;
                foreach my $tmp_host (@tmp_hosts) {
                    if ($tmp_host eq $rule->{host}) {
                        $found = 1;
                        last;
                    }
                }
                next unless ($found);
            } else {
                next unless ($peerhost eq $rule->{host});
            }
        }
        if ($rule->{commands} and $rule->{commands} ne '*') {
            my @commands = split(",", $rule->{commands});
            my $found = 0;
            foreach my $cmd (@commands) {
                if ($request->{command}->[0] eq $cmd) {
                    $found = 1;
                    last;
                }
            }
            if ($found == 0) {    # no command match
                next;
            }
         }

         if ($rule->{parameters} and $rule->{parameters} ne '*') {
            my $parms;
            if ($request->{arg}) {
                $parms = join(' ', @{ $request->{arg} });
            } else {
                $parms = "";
            }
            my $patt = $rule->{parameters};
            unless ($parms =~ /$patt/) {
                next;
            }
        }
        if ($rule->{noderange} and $rule->{noderange} ne '*') {
            unless($req_noderange_info{leftnodenum}){
               next RULE;
            }

            my $allow = 0;
            if ($rule->{rule} =~ /allow/i or $rule->{rule} =~ /accept/i or $rule->{rule} =~ /trusted/i) {
                $allow = 1;
            }

            my %rulenodes;
            foreach (noderange($rule->{noderange})) {
                $rulenodes{$_} = 1;
            }

            my $hitnum = 0;
            my @non_hit_nodes;
            foreach (@{$req_noderange_info{leftnodes}}) {
                if (defined($rulenodes{$_})) {
                    ++$hitnum;
                }else{
                    push @non_hit_nodes, $_;
                }
            }

            if($hitnum == 0){
                next RULE;
            }elsif($hitnum && $hitnum != $req_noderange_info{leftnodenum}){
                if($allow){
                    $req_noderange_info{leftnodenum} = @non_hit_nodes;
                    $req_noderange_info{leftnodes} = \@non_hit_nodes;
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
                $logst  = "xCAT: Allowing " . $request->{command}->[0];
                $status = "Allowed";
                $rc     = 1;
            } else {
                $logst  = "xCAT: Denying " . $request->{command}->[0];
                $status = "Denied";
                $rc     = 0;
            }
            if (! grep { /$request->{command}->[0]/ } @filtered_cmds) {

                # set username authenticated to run command
                # if from Trusted host, use input username,  else set from creds
                if (($request->{username}) && defined($request->{username}->[0])) {
                    if ($peerstatus ne "Trusted") {    # then set to peername
                        $request->{username}->[0] = $peername;
                    }
                } else {
                    $request->{username}->[0] = $peername;
                }
                if ($request->{noderange} && defined($request->{noderange}->[0]))
                {
                    $logst .= " to " . $request->{noderange}->[0];
                } else {    # no noderange maybe a nodes

                    if ($request->{node} && defined($request->{node}->[0])) {
                        my @reqnodes = @{ $request->{node} };
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
                foreach my $argument (@$args) {
                    $arglist .= " " . $argument;
                }
                my $saveArglist = $arglist;

                # If this is mkvm check for --password or -w
                if ($request->{command}->[0] eq "mkvm") {
                    my $first;
                    my $restcommand;
                    my $passw = index ($saveArglist, '--password');
                    if ($passw > -1) {
                        $passw = $passw + 11;
                        my $first = substr($saveArglist,0,$passw). "******** ";
                        my $restcommand = substr($saveArglist,$passw);
                        $restcommand =~ s/^\S+\s*//;
                        $saveArglist = "$first$restcommand";
                    }
                    # now check for -w with password
                    $passw = index ($saveArglist, '-w');
                    if ($passw > -1) {
                        $passw = $passw + 3;
                        $first = substr($saveArglist,0,$passw). "******** ";
                        $restcommand = substr($saveArglist,$passw);
                        $restcommand =~ s/^\S+\s*//;
                        $saveArglist = "$first$restcommand";
                   }
                }
                # Replace passwords with 'x'
                if ($arglist)  { $logst .= redact_password($request->{command}->[0], $saveArglist); }
                if ($peername) { $logst .= " for " . $request->{username}->[0] }
                if ($peerhost) { $logst .= " from " . $peerhost }

                # read site.auditskipcmds and auditnosyslog attributes,
                # if set skip commands else audit all cmds.
                # is auditnosyslog, then only write to auditlog table and not to syslog
                my @skipcmds      = ($::XCATSITEVALS{auditskipcmds});
                my $auditnosyslog = ($::XCATSITEVALS{auditnosyslog});
                my $skipsyslog = 0; # default is to write all commands to auditlog and syslog
                if (defined($auditnosyslog)) {
                    $skipsyslog = $auditnosyslog; # take setting from site table,  1 means no syslog
                }

                # if not "ALL" and not a command from site.auditskipcmds
                # and not getcredentials and not getcredentials ,
                # put in syslog and  auditlog
                my $skip = 0;
                my $all  = "all";
                if (defined($skipcmds[0])) {    # if there are values
                    if (grep(/$all/i, @skipcmds)) {    # skip all
                        $skip = 1;
                    } else {
                        if (grep(/$request->{command}->[0]/, @skipcmds)) { # skip the command
                            $skip = 1;
                        }

                        # if skip clienttype clienttype:value
                        my $client = "clienttype:";
                        $client .= $request->{clienttype}->[0];
                        if (grep(/$client/, @skipcmds)) {    #skip the client
                            $skip = 1;
                        }
                    }

                }
                @$deferredmsgargs = ();   #should be redundant, but just in case
                if (($request->{command}->[0] ne "getpostscript") && ($request->{command}->[0] ne "getcredentials") && ($skip == 0)) {

                    # put in audit Table and syslog unless site.noauditsyslog=1
                    my $rsp = {};

                    if ($skipsyslog == 0) {    # write to syslog and auditlog
                        $rsp->{syslogdata}->[0] = $logst;   # put in syslog data
                    }
                    if ($peername) {
                        $rsp->{userid}->[0] = $request->{username}->[0];
                    }
                    if ($peerhost) {
                        $rsp->{clientname}->[0] = $peerhost;
                    }
                    if (defined $request->{clienttype}) {
                        $rsp->{clienttype}->[0] = $request->{clienttype}->[0];
                    } else {
                        if (defined $request->{becomeuser}) {
                            $rsp->{clienttype}->[0] = "webui";
                        } else {
                            $rsp->{clienttype}->[0] = "other";
                        }
                    }
                    $rsp->{command}->[0] = $request->{command}->[0];
                    if ($request->{noderange} && defined($request->{noderange}->[0])) {
                        $rsp->{noderange}->[0] = $request->{noderange}->[0];
                    }
                    $rsp->{args}->[0]   = $arglist;
                    $rsp->{status}->[0] = $status;
                    if ($skipsyslog == 0) {    # write to syslog and auditlog
                        @$deferredmsgargs = ("SA", $rsp);
                    } else {                   # only auditlog
                        @$deferredmsgargs = ("A", $rsp);
                    }
                } else {    # getpostscript or getcredentials, just syslog
                    if (($request->{command}->[0] eq "getpostscript")
                        || ($request->{command}->[0] eq "getcredentials")) {
                        unless ($::XCATSITEVALS{skipvalidatelog}) { @$deferredmsgargs = ("S", $logst); }
                    } else {  #other skipped command syslog unless auditnosyslog
                        if ($skipsyslog == 0) {    # write to syslog
                            @$deferredmsgargs = ("S", $logst);
                        }
                    }
                }
            }    # end getbladecons,etc check
            return $rc;
        } else {    #Shouldn't be possible....
            xCAT::MsgUtils->message("S", "Impossible line in xcatd reached");
            return 0;
        }
    }    # end RULE
         #Reached end of policy table, reject by default.

    if($req_noderange_info{leftnodenum}){
        my $leftnodes = join(",", @{$req_noderange_info{leftnodes}});
        xCAT::MsgUtils->message("S", "Request matched no policy rule: peername=$peername, peerhost=$peerhost $request->{command}->[0] to $leftnodes");
    }else{
        xCAT::MsgUtils->message("S", "Request matched no policy rule: peername=$peername, peerhost=$peerhost  " . $request->{command}->[0]);
    }
    return 0;
}

my $one_day = 86400;      # one day in seconds
my $days = 1;             # default days for token expiration
my $never_label = "never";

# this subroutine creates a new token in token table
# 1. If old style unix DateTime format token found in the token table
#      if expired -> remove it
#      if not expired -> replace unix DateTime expiration with new human readable format
# 2. create a new token and add it to token table
#
# this subroutine is called after the account has been authorized
sub gettoken {
    my $class = shift;
    my $req   = shift;

    my $current_time = time();
    my $user    = $req->{gettoken}->[0]->{username}->[0];
    my $tokentb = xCAT::Table->new('token');
    unless ($tokentb) {
        return undef;
    }
    my $tokens = $tokentb->getAllEntries;

    # Search for "old" style tokens containing unix DateTime format expiration date
    foreach my $token (@{$tokens}) {

        if ($token->{'expire'} and looks_like_number($token->{'expire'})) {
            # Expiration field contains only digits -> this is a old style token with unix DateTime format

            if ($token->{'expire'} and ($token->{'expire'} < $current_time)) {
                # Clean expired token with old unix DateTime format
                $tokentb->delEntries({ tokenid => $token->{tokenid} });
            } else {
                # Change non-expired old style token to new human readable format
                $tokentb->setAttribs({ tokenid => $token->{tokenid}, username => $token->{'username'} }, {expire => xCAT::Utils->time2string($token->{'expire'}, "-")});
            }
        }
    }

    # create a new token id
    my $uuid       = xCAT::Utils->genUUID();
    # extract site table setting for number of days before token expires
    my $token_days = xCAT::TableUtils->get_site_attribute("tokenexpiredays");
    my $expiretime = $current_time + $one_day; # default is one day
    my $expire_time_string = xCAT::Utils->time2string($expiretime, "-");
    if ($token_days and (uc($token_days) eq uc($never_label))) {
        # Tokens never expire
        $expiretime = $never_label;
        $expire_time_string = $never_label;
    }
    elsif ($token_days and $token_days >  0) {
        # Use number of days from site table
        $days = $token_days;
        $expiretime = $current_time + $one_day * $days;
        $expire_time_string = xCAT::Utils->time2string($expiretime, "-");
    }
    my $access_time_string = xCAT::Utils->time2string($current_time, "-");
    # create a new token and set its expiration and creation time
    $tokentb->setAttribs({ tokenid => $uuid, username => $user },
        { expire => $expire_time_string, created => $access_time_string });
    $tokentb->close();

    return ($uuid, $expiretime);
}

# verify the token has correct entry in token table and expire time is not exceeded.
sub verifytoken {
    my $class = shift;
    my $req   = shift;

    my $current_time = time();
    my $tokenid = $req->{tokens}->[0]->{tokenid}->[0];
    my $tokentb = xCAT::Table->new('token');
    unless ($tokentb) {
        return undef;
    }
    my $token = $tokentb->getAttribs({ 'tokenid' => $tokenid }, ('username', 'expire'));
    if (defined($token) && defined($token->{'username'}) && defined($token->{'expire'})) {

        if ($token->{'expire'} and looks_like_number($token->{'expire'})) {
            # Expiration field contains only digits -> this is a old style token with unix DateTime format
            if ($token->{'expire'} and $token->{'expire'} < $current_time) {
                # Clean expired token with old unix DateTime format
                $tokentb->delEntries({ 'tokenid' => $token->{tokenid} });
                return undef;
            } else {
                # Change non-expired old style token to new human readable format
                $tokentb->setAttribs({ tokenid => $tokenid, username => $token->{'username'} },
                                     {access => xCAT::Utils->time2string($current_time, "-"),
                                      expire => xCAT::Utils->time2string($token->{'expire'}, "-")});
                return $token->{'username'};
            }
        } else {
            if ($token->{'expire'} and ($token->{'expire'} ne "never") and str2time($token->{'expire'}) < $current_time) {
                # Expired new style token
                return undef;
            } else {
                # Not expired new style token - update current access time
                $tokentb->setAttribs({ tokenid => $tokenid, username => $token->{'username'} }, {access => xCAT::Utils->time2string($current_time, "-")});
                return $token->{'username'};
            }
        }
    } else {
        # Token entry was not found
        return undef;
    }
}
# --------------------------------------------------------------------------------

=head3 redact_password

     Used to redact the password in command line parameters with 'x'
     For example, command: rspconfig f6u13k18 'HMC_passwd=123' '*_passwd=abc,xyz'

     Arguments:
                  Type 1:
                      Called from sbin/xcatd to log command to /var/log/xcat/commands.log

                      $class: Calling module name, for example:
                          xCAT::xcatd
                      $request: Single line string of the header + command + arguments, for example:
                          header [Request]    rspconfig f6u13k18 'HMC_passwd=123' '*_passwd=abc,xyz'

                  Type 2:
                      Called from this module to log command to /var/log/messages and
                                                                /var/log/xcat/cluster.log

                      $class: Command name sting, for example:
                          rspconfig
                      $request: Single line string of arguments, for example:
                          'HMC_passwd=123' '*_passwd=abc,xyz'
     Returns string:
                  Type 1:
                      header [Request]    rspconfig f6u13k18 'HMC_passwd=xxx' '*_passwd=xxxxxxx'

                  Type 2:
                      'HMC_passwd=xxx' '*_passwd=xxxxxxx'
=cut

# --------------------------------------------------------------------------------
sub redact_password {
    my $class = shift;
    my $request = shift;
    my $redact_string = "xxxxxxxx";

    my %commads_with_password = (
        bmcdiscover => {
            flags => ["-p ", "-n "],
        },
        mkhwconn => {
            flags => ["-P "],
        },
        rspconfig => {
            flags => ["admin_passwd=","HMC_passwd=","general_passwd=","*_passwd=","USERID="],
        },
    );

    my $full_command;
    my $header;
    # split out command and its parameters and flags
    if ($request =~ '\[Request\]') {
        ($header, $full_command) = split('\[Request\]',$request,2);
    } else {
        $full_command = $class . " " . $request;
    }
    my ($command, $parameters) = split(' ',$full_command,2);

    # Check if passed in $command appears in the %commads_with_password hash
    for (keys %commads_with_password) {
        if ($_ eq $command) {
            my @all_command_flags = split(' ', $parameters);
            my $ref = $commads_with_password{$command}{flags};
            my @flags_array = @$ref;
            foreach my $password_flag (@flags_array) {
                # For each flag of the command from hash, check if passed in
                # command flags match
                my $flag_index = index ($parameters, $password_flag);
                if ($flag_index >= 0) {
                    # Passed in command contains one of the flags, redact pw
                    my ($passwd, $rest) = split(/\s+/,substr($parameters, $flag_index+length($password_flag)));
                    my $pw_replacement = $redact_string;
                    if (index($passwd, "'") > 0) {
                        # Password and password flag was enclosed in "'", preserve that quote
                        $pw_replacement .= "'";
                    }
                    # Replace password with $pw_replacement
                    substr($parameters, $flag_index+length($password_flag), length($passwd)) = $pw_replacement;
                }
            }
        }
    }
    # Return original request with password replaced by 'x' in $parameters string
    if ($request =~ '\[Request\]') {
        return $header . "[Request]    " . $command . " " . $parameters;
    } else {
        return " " . $parameters;
    }
}
1;
