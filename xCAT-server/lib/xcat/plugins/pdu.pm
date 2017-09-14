# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle pdu 

   Supported command:
        rpower 
        rinv
        rvitals

=cut

#-------------------------------------------------------
package xCAT_plugin::pdu;

BEGIN {
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::Table;
use xCAT::Utils;
use xCAT::FifoPipe;
use xCAT::MsgUtils;
use xCAT::State;
use xCAT::SvrUtils;
use xCAT::Usage;
use xCAT::NodeRange;
use Data::Dumper;
use Getopt::Long;
use File::Path;
use Term::ANSIColor;
use Time::Local;
use strict;
use Class::Struct;
use XML::Simple;
use Storable qw(dclone);
use SNMP;
use Expect;
use Net::Ping;

my $VERBOSE = 0;
my %allerrornodes = ();
my $callback;
my $pdutab;
my @pduents;
my $pdunodes;



#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
       rpower => ["nodehm:mgt","pduoutlet:pdu=\.\*"],
       rinv   => ["nodehm:mgt"],
       rvitals => ["nodehm:mgt"],
       nodeset => ["nodehm:mgt"],
       rspconfig => ["nodehm:mgt"],
       pdudiscover => "pdu",
    };
}

#--------------------------------------------------------------------------------
=head3   preprocess_request

Parse the arguments and display the usage or the version string.

=cut
#--------------------------------------------------------------------------------
sub preprocess_request {
    my $req = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    my $callback=shift;
    my @requests;

    my $command = $req->{command}->[0];
    my $noderange = $req->{node};           #Should be arrayref
    my $extrargs = $req->{arg};
    my @exargs=($req->{arg});
    if (ref($extrargs)) {
        @exargs=@$extrargs;
    }

    my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
    if ($usage_string) {
        $callback->({data=>[$usage_string]});
        $req = {};
        return;
    }

    if ((!$noderange) && ($command ne "pdudiscover") ){
        $usage_string = xCAT::Usage->getUsage($command);
        $callback->({ data => $usage_string });
        $req = {};
        return;
    }

    my @result = ();
    my $mncopy = {%$req};
    push @result, $mncopy;
    return \@result;

}


#-------------------------------------------------------

=head3  process_request

  Process the command.

=cut

#-------------------------------------------------------
sub process_request
{
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;
    my $command  = $request->{command}->[0];
    my $noderange = $request->{node};           #Should be arrayref
    my $extrargs  = $request->{arg};
    my @exargs    = ($request->{arg});

    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }

    #fill in the total outlet count for each pdu
    $pdutab = xCAT::Table->new('pdu');
    @pduents = $pdutab->getAllNodeAttribs(['node', 'outlet']);
    #fill_outletCount(\@pduents, $callback);

    if( $command eq "rinv") {
        #for higher performance, handle node in batch
        return showMFR($noderange, $callback);
    }elsif ($command eq "rvitals") {
        return showMonitorData($noderange, $callback);
    }elsif ($command eq "rpower") {
        my $subcmd = $exargs[0];
        if (($subcmd eq 'pduoff') || ($subcmd eq 'pduon') || ($subcmd eq 'pdustat')|| ($subcmd eq 'pdureset') ){
            #if one day, pdu node have pdu attribute, handle in this section too
            return powerpduoutlet($noderange, $subcmd, $callback);
        } else {
            #-------------------------------------------
            #there are 2 cases will enter this block
            #one is if node's mgt is pdu
            #another is if node has pdu attribute but mgt isn't pdu
            #if the node has pdu attribute but mgt isn't pdu, 
            #should do nothing for this node, let other plugin to hanle this node 
            #-------------------------------------------
            my @allpdunodes=();
            my $nodehm = xCAT::Table->new('nodehm');
            my $nodehmhash = $nodehm->getNodesAttribs($noderange, ['mgt']);
            foreach my $node (@$noderange) { 
                if($nodehmhash->{$node}->[0]->{mgt} eq 'pdu'){
                    push @allpdunodes, $node;
                }
            }
            if(@allpdunodes) {
                if(($subcmd eq 'on') || ($subcmd eq 'off') || ($subcmd eq 'stat') || ($subcmd eq 'state') || ($subcmd eq 'reset') ){
                    return powerpdu(\@allpdunodes, $subcmd, $callback);
                } else {
                    my $pdunode = join (",", @allpdunodes);
                    $callback->({ errorcode => [1],error => "The option $subcmd is not support for pdu node(s) $pdunode."});
                }
            }
        }
    }elsif($command eq "rspconfig") {
        my $subcmd = $exargs[0];
        if ($subcmd eq 'sshcfg') {
            process_sshcfg($noderange, $subcmd, $callback);
        }elsif ($subcmd =~ /ip|netmask|hostname/) {
            process_netcfg($request, $subreq, $subcmd, $callback);
        } else {
            $callback->({ errorcode => [1],error => "The input $command $subcmd is not support for pdu"});
        }
    }elsif($command eq "pdudiscover") {
        process_pdudiscover($request, $subreq, $callback);
    }elsif($command eq "nodeset") {
        $callback->({ errorcode => [1],error => "The input $command is not support for pdu"});
    }else{
        #reserve for other new command in future
    }

    return;
}

sub fill_outletCount {
    my $pduentries = shift;
    my $callback = shift;
    my $outletoid = ".1.3.6.1.4.1.2.6.223.8.2.1.0";
    my $pdutab = xCAT::Table->new('pdu');

    foreach my $pdu (@$pduentries) {
        my $cur_pdu = $pdu->{node};
        my $count = $pdu->{outlet};
        #get total outlet number for the pdu
        if (!$count) {
            my $session = connectTopdu($cur_pdu,$callback);
            #will not log this error to output
            if (!$session) {
                next;
            }
            $count = $session->get("$outletoid");
            if ($count) {
                $pdutab->setNodeAttribs($cur_pdu, {outlet => $count});
            }
        }
        $pdunodes->{$cur_pdu}->{outlet}=$count;
    }
}

#-------------------------------------------------------

=head3  powerpdu 

    Process power command (stat/off/on) for pdu/pdus

=cut

#-------------------------------------------------------
sub powerpdu {
    my $noderange = shift;
    my $subcmd = shift;
    my $callback = shift;

    if (($subcmd eq "stat") || ($subcmd eq "state")){
        return powerstat($noderange, $callback);
    }

    foreach my $node (@$noderange) {
        my $session = connectTopdu($node,$callback);
        if (!$session) {
            $callback->({ errorcode => [1],error => "Couldn't connect to $node"});
            next;
        }
        my $count = $pdunodes->{$node}->{outlet};
        my $value;
        my $statstr;
        if ($subcmd eq "off") {
            $value = 0;
            $statstr = "off";
        } elsif ( $subcmd eq "on") {
            $value = 1;
            $statstr = "on";
        } else  {
            $value = 2;
            $statstr = "reset";
        }

        for (my $outlet =1; $outlet <= $count; $outlet++)
        {
            outletpower($session, $outlet, $value);
            if ($session->{ErrorStr}) { 
                $callback->({ errorcode => [1],error => "Failed to get outlet status for $node"});
            } else {
                my $output = " outlet $outlet is $statstr"; 
                xCAT::SvrUtils::sendmsg($output, $callback, $node, %allerrornodes);
            }
        }
    }
}

#-------------------------------------------------------

=head3  powerpduoutlet 

    Process power command (pdustat/pduoff/pduon) for compute nodes,
    the pdu attribute needs to be set 

=cut

#-------------------------------------------------------
sub powerpduoutlet {
    my $noderange = shift;
    my $subcmd = shift;
    my $callback = shift;
    my $output;
    my $value;
    my $statstr;

    my $tmpnodestr = join(",", @$noderange);

    my $nodetab = xCAT::Table->new('pduoutlet');
    my $nodepdu = $nodetab->getNodesAttribs($noderange,['pdu']);
    foreach my $node (@$noderange) {
        # the pdu attribute needs to be set
        if(! $nodepdu->{$node}->[0]->{pdu}){
            $callback->({ error => "$node: without pdu attribute"});
            next;
        }

        my @pdus = split /,/, $nodepdu->{$node}->[0]->{pdu};
        foreach my $pdu_outlet (@pdus) {
            my ($pdu, $outlet) = split /:/, $pdu_outlet;
            my $session = connectTopdu($pdu,$callback);
            if (!$session) {
                $callback->({ errorcode => [1],error => "$node: Couldn't connect to $pdu"});
                next;
            }
            if ($outlet > $pdunodes->{$pdu}->{outlet} ) {
                $callback->({ error => "$node: $pdu outlet number $outlet is invalid"});
                next;
            }
            my $cmd;
            if ($subcmd eq "pdustat") {
                $statstr=outletstat($session, $outlet);
            } elsif ($subcmd eq "pduoff") {
                $value = 0;
                $statstr = "off";
                outletpower($session, $outlet, $value);
            } elsif ($subcmd eq "pduon") {
                $value = 1;
                $statstr = "on";
                outletpower($session, $outlet, $value);
            } elsif ($subcmd eq "pdureset") {
                $value = 2;
                $statstr = "reset";
                outletpower($session, $outlet, $value);
            } else {
                $callback->({ error => "$subcmd is not support"});
            } 
    
            if ($session->{ErrorStr}) { 
                $callback->({ errorcode => [1],error => "$node: $pdu outlet $outlet has error = $session->{ErrorStr}"});
            } else {
                $output = "$pdu outlet $outlet is $statstr"; 
                xCAT::SvrUtils::sendmsg($output, $callback, $node, %allerrornodes);
            }
        }
    }
}

#-------------------------------------------------------

=head3  outletpower 

    Process power command for one pdu outlet,

=cut

#-------------------------------------------------------
sub outletpower {
    my $session = shift;
    my $outlet = shift;
    my $value = shift;

    my $oid = ".1.3.6.1.4.1.2.6.223.8.2.2.1.11";
    my $type = "INTEGER";
    if ($session->{newmib}) {
        $oid = ".1.3.6.1.4.1.2.6.223.8.2.2.1.13";
    }    


    my $varbind = new SNMP::Varbind([ $oid, $outlet, $value, $type ]);
    return $session->set($varbind);
}

#-------------------------------------------------------

=head3  powerstat 

    Process command to query status of pdu

=cut

#-------------------------------------------------------
sub powerstat {
    my $noderange = shift;
    my $callback = shift;
    my $output;

    foreach my $pdu (@$noderange) {
        my $session = connectTopdu($pdu,$callback);
        if (!$session) {
            $callback->({ errorcode => [1],error => "Couldn't connect to $pdu"});
            next;
        }
        my $count = $pdunodes->{$pdu}->{outlet};
        for (my $outlet =1; $outlet <= $count; $outlet++)
        {
            my $statstr = outletstat($session, $outlet);
            my $msg = " outlet $outlet is $statstr";
            xCAT::SvrUtils::sendmsg($msg, $callback, $pdu, %allerrornodes);
        }
    }
}

#-------------------------------------------------------

=head3  outletstat 

    Process command to query status of one pdu outlet

=cut

#-------------------------------------------------------
sub outletstat {
    my $session = shift;
    my $outlet = shift;
 
    my $oid = ".1.3.6.1.4.1.2.6.223.8.2.2.1.11";
    my $output;
    my $statstr;
    if ($session->{newmib}) {
        $oid = ".1.3.6.1.4.1.2.6.223.8.2.2.1.13";
    }

    $output = $session->get("$oid.$outlet");
    if ($output eq 1) {
        $statstr = "on";
    } elsif ($output eq 0) {
        $statstr = "off";
    } else {
        return;
    }
    return $statstr;
}

#-------------------------------------------------------

=head3  connectTopdu 

   connect pdu via snmp session 

=cut

#-------------------------------------------------------
sub connectTopdu {
    my $pdu = shift;
    my $callback = shift;

    my $snmpver = "1";
    my $community = "public";
    my $session;
    my $msg = "connectTopdu";
    my $versionoid = ".1.3.6.1.4.1.2.6.223.7.3.0";

    $session = new SNMP::Session(
        DestHost       => $pdu,
        Version        => $snmpver,
        Community      => $community,
        UseSprintValue => 1,
    );
    unless ($session) {
        return;
    }

    my $varbind = new SNMP::Varbind([ $versionoid, '' ]);
    my $pduversion = $session->get($varbind);
    if ($session->{ErrorStr}) {
        return;
    }

    $session->{newmib} = 0;
    if ($pduversion =~ /sLEN/) {
        $session->{newmib} = 1;
    }

    return $session;

}

#-------------------------------------------------------

=head3  process_netcfg 
   
    Config hostname of PDU
    Config ip/netmask of PDU via PduManager command 
      PduManager is a tool for CoralPdu to manager the PDU.
      * /dev/shm/bin/PduManager -h
          '-i' set PDU system IP
          '-n' set system ip netmask. e.g.:PduManager -i xxx.xxx.xxx.xxx -n xxx.xxx.xxx.xxx

    example:  rspconfig coralpdu hostname=coralpdu
              rspconfig coralpdu ip=1.1.1.1 netmask=255.0.0.0

=cut

#-------------------------------------------------------
sub process_netcfg {
    my $request = shift;
    my $subreq    = shift;
    my $subcmd    = shift;
    my $callback = shift;
    my $hostname;
    my $ip;
    my $netmask;
    my $args;
    my $exp;
    my $errstr;

    my $extrargs  = $request->{arg};
    my @exargs    = ($request->{arg});
    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }

    my $nodes = $request->{node};
    my $node_number = @$nodes;
    if ($node_number gt "1") {
        xCAT::SvrUtils::sendmsg("Can not configure more than 1 nodes", $callback);
        return;
    }

    my $pdu = @$nodes[0];
    my $rsp = {};

    my $nodetab = xCAT::Table->new('hosts');
    my $nodehash = $nodetab->getNodesAttribs($nodes,['ip','otherinterfaces']);

    # connect to PDU
    my $static_ip = $nodehash->{$pdu}->[0]->{ip};
    my $discover_ip = $nodehash->{$pdu}->[0]->{otherinterfaces};
    ($exp, $errstr) = session_connect($static_ip, $discover_ip);
    if (defined $errstr) {
        xCAT::SvrUtils::sendmsg("Failed to connect", $callback);
        return;
    }

    foreach my $cmd (@exargs) {
        my ($key, $value) = split(/=/, $cmd);
        if ($key =~ /hostname/) {
            $hostname = $value;
            my ($ret, $err) = session_exec($exp, "echo $hostname > /etc/hostname;/etc/init.d/hostname.sh");
            if (defined $err) {
               xCAT::SvrUtils::sendmsg("Failed to set hostname", $callback);
            }
        }elsif ($key =~ /ip/) {
            $ip = $value;
        } elsif ($key =~ /netmask/) {
            $netmask = $value;
        } else {
            xCAT::SvrUtils::sendmsg("rspconfig $cmd is not support yet, ignored", $callback);
        }
    }

    $args = "/dev/shm/bin/PduManager ";
    my $opt;
    if ($ip) {
        $opt = "-i $ip ";
    }
    if ($netmask) {
        $opt = $opt . "-n $netmask";
    }
    if ($opt) {
        my $dshcmd = $args . $opt ;
        my ($ret, $err) = session_exec($exp, $dshcmd);
        if (defined $err) {
            #session will be hung if ip address changed
            my $p = Net::Ping->new();
            if  ( ($p->ping($ip)) && ($err =~ /TIMEOUT/) ) {
               xCAT::SvrUtils::sendmsg("$ip is reachable", $callback);
            } else {
                xCAT::SvrUtils::sendmsg("Failed to run $dshcmd, error=$err", $callback);
                return;
            }
        } 
        xCAT::SvrUtils::sendmsg("$dshcmd ran successfully", $callback);
        xCAT::Utils->runxcmd({ command => ['chdef'], arg => ['-t','node','-o',$pdu,"ip=$ip","otherinterfaces="] }, $subreq, 0, 1);
        xCAT::Utils->runxcmd({ command => ['makehosts'], node => [$pdu] },  $subreq, 0, 1);
    }
    if (defined $exp) {
        $exp->hard_close();
    }
}

#-------------------------------------------------------

=head3  process_sshcfg 
   
    Config passwordless for coralpdu 

    example:  rspconfig coralpdu sshcfg 

=cut

#-------------------------------------------------------
sub process_sshcfg { 
    my $noderange = shift;
    my $subcmd = shift;
    my $callback = shift;

    #this is default password for CoralPDU
    my $password = "password8";
    my $userid = "root";
    my $timeout = 30;
    my $keyfile = "/root/.ssh/id_rsa.pub";
    my $rootkey = `cat /root/.ssh/id_rsa.pub`;
    my $cmd;

    my $nodetab = xCAT::Table->new('hosts');
    my $nodehash = $nodetab->getNodesAttribs($noderange,['ip','otherinterfaces']);
    
    foreach my $pdu (@$noderange) {
        my $msg = " process_sshcfg";
        xCAT::SvrUtils::sendmsg($msg, $callback, $pdu, %allerrornodes);

        #remove old host key from /root/.ssh/known_hosts
        $cmd = "ssh-keygen -R $pdu";
        xCAT::Utils->runcmd($cmd, 0);

        my $static_ip = $nodehash->{$pdu}->[0]->{ip};
        my $discover_ip = $nodehash->{$pdu}->[0]->{otherinterfaces};
        my ($exp, $errstr) = session_connect($static_ip, $discover_ip);
        if (!defined $exp) {
            $msg = " Failed to connect $errstr";
            xCAT::SvrUtils::sendmsg($msg, $callback, $pdu, %allerrornodes);
            next;
        }

        my $ret;
        my $err;

        ($ret, $err) = session_exec($exp, "mkdir -p /home/root/.ssh");
        ($ret, $err) = session_exec($exp, "chmod 700 /home/root/.ssh");
        ($ret, $err) = session_exec($exp, "echo \"$rootkey\" >/home/root/.ssh/authorized_keys");
        ($ret, $err) = session_exec($exp, "chmod 644 /home/root/.ssh/authorized_keys");

        $exp->hard_close();
    }

    return;
}

sub session_connect {
    my $static_ip   = shift;
    my $discover_ip   = shift;

    #default password for coral pdu
    my $password = "password8";
    my $userid = "root";
    my $timeout = 30;

    my $ssh_ip;
    my $p = Net::Ping->new();
    if ($p->ping($static_ip)) {
        $ssh_ip = $static_ip;
    } elsif ($p->ping($discover_ip)) {
        $ssh_ip = $discover_ip;
    } else {
        return(undef, " is not reachable\n");
    }

    my $ssh      = Expect->new;
    my $command     = 'ssh';
    my @parameters  = ($userid . "@" . $ssh_ip);

     $ssh->debug(0);
     $ssh->log_stdout(0);    # suppress stdout output..
     $ssh->slave->stty(qw(sane -echo));

     unless ($ssh->spawn($command, @parameters))
     {
         my $err = $!;
         $ssh->soft_close();
         my $rsp;
         return(undef, "unable to run command $command $err\n");
     }

     $ssh->expect($timeout,
                   [ "-re", qr/WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED/, sub {die "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!\n"; } ],
                   [ "-re", qr/\(yes\/no\)\?\s*$/, sub { $ssh->send("yes\n");  exp_continue; } ],
                   [ "-re", qr/ password:/,        sub {$ssh->send("$password\n"); exp_continue; } ],
                   [ "-re", qr/:~\$/,              sub { $ssh->send("sudo su\n"); exp_continue; } ],
                   [ "-re", qr/.*#/,               sub { $ssh->clear_accum(); } ],
                   [ timeout => sub { die "No login.\n"; } ]
                  );
     $ssh->clear_accum();
     return ($ssh);
}


sub session_exec {
     my $exp = shift;
     my $cmd = shift;
     my $timeout    = shift;
     my $prompt =  shift;

     $timeout = 30 unless defined $timeout;
     $prompt = qr/.*#/ unless defined $prompt;


     $exp->clear_accum();
     $exp->send("$cmd\n");
     my ($mpos, $merr, $mstr, $mbmatch, $mamatch) = $exp->expect(6,  "-re", $prompt);

     if (defined $merr) {
         return(undef,$merr);
     }
     return($mbmatch);
}

#-----------------------------------------------------------------

=head3  process_pdudiscover
   
    Discover the pdu for a given range of DHCP ip address
    it will call switchdiscover command with -s snmp --pdu options 

    example: pdudiscover --range iprange -w

=cut

#------------------------------------------------------------------
sub process_pdudiscover {
    my $request  = shift;
    my $sub_req  = shift;
    my $callback = shift;
    my $extrargs = $request->{arg};
    my @exargs   = ($request->{arg});
    if (ref($extrargs)) {
        @exargs=@$extrargs;
    }

    #check case in GetOptions
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );
    Getopt::Long::Configure("no_pass_through");
    my %opt;
    if (!GetOptions( \%opt,
                    qw(h|help V|verbose x z w r range=s setup))) {
        my $usage_string = xCAT::Usage->getUsage($request->{command}->[0]);
        $callback->({ data => $usage_string });
        return;

    }

    push @exargs, "-s snmp --pdu";
    my $cmd = "switchdiscover @exargs";
    my $result = xCAT::Utils->runcmd($cmd, 0);

    my $rsp = {};
    push @{ $rsp->{data} }, "$result";
    xCAT::MsgUtils->message("I", $rsp, $callback);
}

#-------------------------------------------------------

=head3  showMFR 

    show MFR information of PDU via PduManager command 
      PduManager is a tool for CoralPdu to manager the PDU.
      * /dev/shm/bin/PduManager -h
          '-m' show MFR info 

    example:  rinv coralpdu

=cut

#-------------------------------------------------------

sub showMFR {
    my $noderange = shift;
    my $callback = shift;
    my $output;

    my $nodetab = xCAT::Table->new('hosts');
    my $nodehash = $nodetab->getNodesAttribs($noderange,['ip','otherinterfaces']);

    foreach my $pdu (@$noderange) {
        # connect to PDU
        my $static_ip = $nodehash->{$pdu}->[0]->{ip};
        my $discover_ip = $nodehash->{$pdu}->[0]->{otherinterfaces};
        my ($exp, $errstr) = session_connect($static_ip, $discover_ip);
        if (defined $errstr) {
            xCAT::SvrUtils::sendmsg("Failed to connect: $errstr", $callback);
        }

        my ($ret, $err) = session_exec($exp, "/dev/shm/bin/PduManager -m");
        if (defined $err) {
            xCAT::SvrUtils::sendmsg("Failed to list MFR information: $err", $callback);
        }
        if (defined $ret) {
            xCAT::SvrUtils::sendmsg("$ret", $callback);
        }

        $exp->hard_close();
    }
}


#-------------------------------------------------------

=head3  showMonitorData 

    Show realtime monitor data(input voltage, current, power) 
        of PDU via PduManager command 
    PduManager is a tool for CoralPdu to manager the PDU.
      * /dev/shm/bin/PduManager -h
          '-d' show realtime monitor data(input voltage, current, power) 

    example:  rvitals coralpdu 

=cut

#-------------------------------------------------------
sub showMonitorData {
    my $noderange = shift;
    my $callback = shift;
    my $output;

    my $nodetab = xCAT::Table->new('hosts');
    my $nodehash = $nodetab->getNodesAttribs($noderange,['ip','otherinterfaces']);

    foreach my $pdu (@$noderange) {
        # connect to PDU
        my $static_ip = $nodehash->{$pdu}->[0]->{ip};
        my $discover_ip = $nodehash->{$pdu}->[0]->{otherinterfaces};
        my ($exp, $errstr) = session_connect($static_ip, $discover_ip);

        my $ret;
        my $err;

        ($ret, $err) = session_exec($exp, "/dev/shm/bin/PduManager -d");
        if (defined $err) {
            xCAT::SvrUtils::sendmsg("Failed to show monitor data: $err", $callback);
        }
        if (defined $ret) {
            xCAT::SvrUtils::sendmsg("$ret", $callback,$pdu);
        }

        $exp->hard_close();
    }
}


1;
