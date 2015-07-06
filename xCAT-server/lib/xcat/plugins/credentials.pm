# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
   Plugin to handle credentials with good old fashioned priveleged port/host based authentication
   May also include xCAT state-sensitive denial/allow
   Also controlled by policy table (SECURITY: must document how to harden and make more convenient
   through policy table).

   This sounds horrible and most of the time it would be.  However, when dealing with unattended
   installs, it is better than nothing.  Apache does not appear to be able to give credence to
   privileged ports vs. non-privileged ports on the client, so simple nfs-style authentication is 
   not possible.

   The problem with more secure methods and unattended installs is that all rely upon the client to
   have a blessed credential, and giving that credential or blessing a credential I can't think of a 
   way to feasibly do unattended truly securely, so here we try to mitigate the exposure and 
   implement nfs-like security (with the plus of encryption, hopefully)

   Supported command:
      getcredentials

=cut

#-------------------------------------------------------
package xCAT_plugin::credentials;
use strict;
use xCAT::Table;
use Data::Dumper;
use xCAT::NodeRange;
use xCAT::Zone;
use IO::Socket::INET;
use Time::HiRes qw(sleep);

use xCAT::Utils;

use xCAT::MsgUtils;
use Getopt::Long;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {getcredentials => "credentials" };
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
my $callback;
sub process_request
{

    my $request  = shift;
    $callback = shift;
    my $command  = $request->{command}->[0];
    my $args     = $request->{arg};
    my $envs     = $request->{env};
    my $client;
    #Because clients may be stuck with stunnel, we cannot presume they 
    #can explicitly bind to a low port number as a client
    #unless ($request and $request->{'_xcat_clientport'} and $request->{'_xcat_clientport'}->[0] and  $request->{'_xcat_clientport'}->[0] < 1000) {
    #   print Dumper($request);
    #   return; #only accept requests from privileged ports
    #}
    if ($request->{'_xcat_clienthost'}) {
       $client = $request->{'_xcat_clienthost'}->[0];
    }
    my $rsp;
    # do your processing here
    # return info

    if ($client) { ($client) = noderange($client) };
    unless ($client) { #Not able to do host authentication, abort
       return;
    }
    my $credcheck;
    if ($request->{'callback_port'} and $request->{'callback_port'}->[0] and $request->{'callback_port'}->[0] < 1024) {
        $credcheck=[0,$request->{'callback_port'}->[0]];
    } elsif ($request->{'callback_https_port'} and $request->{'callback_https_port'}->[0] and $request->{'callback_https_port'}->[0] < 1024) {
        $credcheck=[1,$request->{'callback_https_port'}->[0]];
    } else {
       return;
    }
    unless (ok_with_node($client,$credcheck)) {
       return;
    }

    my @params_to_return = @{$request->{arg}};
    $rsp->{data}=[];
    my $tmpfile;
    my @filecontent;
    my $retdata;
    my $tfilename;

	my $root;
    if (xCAT::Utils->isAIX()) {
        $root = "";
    } else {
        $root = "/root";
    }
    
    foreach my $parm (@params_to_return) {
       
       # if  paramter is ssh_root_key or ssh_root_pub_key then
       # we need to see if a zonename is attached
       # it comes in as ssh_root_key:zonename
       # if zonename then we need to read the keys from the zone table sshkeydir attribute
       
       my $errorfindingkeys=0;
       my $foundkeys=0;
       my $sshrootkeydir="$root/.ssh";   # old default
       if ((($parm =~ /^ssh_root_key/) || ($parm =~ /^ssh_root_pub_key/)) && ($foundkeys==0)){
         my ($rootkeyparm,$zonename) = split(/:/,$parm);
         if ($zonename) {   
            $parm=$rootkeyparm;  # take the zone off
           `logger -t xcat -p local4.info "credentials: The node is asking for zone:$zonename sshkeys ."`;
           $sshrootkeydir = xCAT::Zone->getzonekeydir($zonename);
           if ($sshrootkeydir == 1) { # error return
               `logger -t xcat -p local4.info "credentials: The node is asking for zone:$zonename sshkeys and the $zonename is not defined."`;
           } else {
                $foundkeys=1;  # don't want to read the zone data twice
           }
         }
       }

       if ($parm  =~ /ssh_root_key/) { 
          unless (-r "$sshrootkeydir/id_rsa") {
            push @{$rsp->{'error'}},"Unable to read root's private ssh key";
            `logger -t xcat -p local4.info "credentials: Unable to read root's private ssh key"` ;
            next;
          }
          `logger -t xcat -p local4.info "credentials: sending $parm"` ;
          $tfilename = "$sshrootkeydir/id_rsa";
         `logger -t xcat -p local4.info "credentials: The  ssh root private key is in $tfilename."`;

       } elsif ($parm =~ /ssh_root_pub_key/) {
          unless (-r "$sshrootkeydir/id_rsa.pub") {
            push @{$rsp->{'error'}},"Unable to read root's public ssh key";
            `logger -t xcat -p local4.info "credentials: Unable to read root's public ssh key"` ;
            next;
          }
          `logger -t xcat -p local4.info "credentials: sending $parm"` ;
          $tfilename = "$sshrootkeydir/id_rsa.pub";
         `logger -t xcat -p local4.info "credentials: The  ssh root public key is in $tfilename."`;

       } elsif ($parm =~ /xcat_server_cred/) {
          unless (-r "/etc/xcat/cert/server-cred.pem") {
            push @{$rsp->{'error'}},"Unable to read xcat_server_cred";
            `logger -t xcat -p local4.info "credentials: Unable to read xcat_server_cred"` ;
            next;
          }
          `logger -t xcat -p local4.info "credentials: sending $parm"` ;
          $tfilename = "/etc/xcat/cert/server-cred.pem";

       } elsif (($parm =~ /xcat_client_cred/) or ($parm =~ /xcat_root_cred/)) {
          unless (-r "$root/.xcat/client-cred.pem") {
            push @{$rsp->{'error'}},"Unable to read xcat_client_cred or xcat_root_cred";
            `logger -t xcat -p local4.info "credentials: Unable to read xcat_client_cred or xcat_root_cred"` ;
            next;
          }
          `logger -t xcat -p local4.info "credentials: sending $parm"` ;
          $tfilename = "$root/.xcat/client-cred.pem";

       } elsif ($parm =~ /ssh_dsa_hostkey/) {
          `logger -t xcat -p local4.info "credentials: sending $parm"` ;
	  if (-r "/etc/xcat/hostkeys/$client/ssh_host_dsa_key") {
	  	$tfilename="/etc/xcat/hostkeys/$client/ssh_host_dsa_key";
	  } elsif (-r "/etc/xcat/hostkeys/ssh_host_dsa_key") {
	  	$tfilename="/etc/xcat/hostkeys/ssh_host_dsa_key";
	  } else {
             push @{$rsp->{'error'}},"Unable to read private DSA key from /etc/xcat/hostkeys";
            `logger -t xcat -p local4.info "credentials: Unable to read private DSA key"` ;
             next;
          }
       } elsif ($parm =~ /ssh_rsa_hostkey/) {
          `logger -t xcat -p local4.info "credentials: sending $parm"` ;
          if (-r "/etc/xcat/hostkeys/$client/ssh_host_rsa_key") {
	  	 $tfilename="/etc/xcat/hostkeys/$client/ssh_host_rsa_key";
	  } elsif (-r "/etc/xcat/hostkeys/ssh_host_rsa_key") {   
	  	 $tfilename="/etc/xcat/hostkeys/ssh_host_rsa_key";
	  } else {
             push @{$rsp->{'error'}},"Unable to read private RSA key from /etc/xcat/hostkeys";
            `logger -t xcat -p local4.info "credentials: Unable to read private RSA key"` ;
             next;
          }
       } elsif ($parm =~ /ssh_ecdsa_hostkey/) {
          `logger -t xcat -p local4.info "credentials: sending $parm"` ;
          if (-r "/etc/xcat/hostkeys/$client/ssh_host_ecdsa_key") {
	  	 $tfilename="/etc/xcat/hostkeys/$client/ssh_host_ecdsa_key";
	  } elsif (-r "/etc/xcat/hostkeys/ssh_host_ecdsa_key") {   
	  	 $tfilename="/etc/xcat/hostkeys/ssh_host_ecdsa_key";
	  } else {
             push @{$rsp->{'error'}},"Unable to read private ECDSA key from /etc/xcat/hostkeys";
            `logger -t xcat -p local4.info "credentials: Unable to read private ECDSA key"` ;
             next;
          }
       } elsif ($parm =~ /xcat_cfgloc/) {
          `logger -t xcat -p local4.info "credentials: sending $parm"` ;
          unless (-r "/etc/xcat/cfgloc") {
            push @{$rsp->{'error'}},"Unable to read /etc/xcat/cfgloc ";
            `logger -t xcat -p local4.info "credentials: Unable to read /etc/xcat/cfgloc"` ;
            next;
          }
          $tfilename = "/etc/xcat/cfgloc";

       } elsif ($parm =~ /krb5_keytab/) { #TODO: MUST RELAY TO MASTER
          `logger -t xcat -p local4.info "credentials: sending $parm"` ;
           my $princsuffix=$request->{'_xcat_clientfqdn'}->[0];
           $ENV{KRB5CCNAME}="/tmp/xcat/krb5cc_xcat_$$";
           system('kinit -S kadmin/admin -k -t /etc/xcat/krb5_pass xcat/admin');
           system("kadmin -p xcat/admin -c /tmp/xcat/krb5cc_xcat_$$ -q 'delprinc -force host/$princsuffix'");
           system("kadmin -p xcat/admin -c /tmp/xcat/krb5cc_xcat_$$ -q 'delprinc -force nfs/$princsuffix'");
           system("kadmin -p xcat/admin -c /tmp/xcat/krb5cc_xcat_$$ -q 'addprinc -randkey host/$princsuffix'");
           system("kadmin -p xcat/admin -c /tmp/xcat/krb5cc_xcat_$$ -q 'addprinc -randkey nfs/$princsuffix'");
           unlink "/tmp/xcat/keytab.$$";
           system("kadmin -p xcat/admin -c /tmp/xcat/krb5cc_xcat_$$ -q 'ktadd -k /tmp/xcat/keytab.$$ nfs/$princsuffix'");
           system("kadmin -p xcat/admin -c /tmp/xcat/krb5cc_xcat_$$ -q 'ktadd -k /tmp/xcat/keytab.$$ host/$princsuffix'");
           system("kdestroy -c /tmp/xcat/krb5cc_xcat_$$");
           unlink("/tmp/xcat/krb5cc_xcat_$$");
           my $keytab;
           open($keytab, "/tmp/xcat/keytab.$$");
           my $tabdata="\n";
           my $buf;
           require MIME::Base64;
           while (read($keytab,$buf,1140)) {
               $tabdata.=MIME::Base64::encode_base64($buf);
           }
           push @{$rsp->{'data'}},{content=>[$tabdata],desc=>[$parm]};
           unlink "/tmp/xcat/keytab.$$";
           next;
       } elsif ($parm =~ /x509cert/) {
          `logger -t xcat -p local4.info "credentials: sending $parm"` ;
	   my $csr = $request->{'csr'}->[0];
	   my $csrfile;
           my $oldumask = umask 0077;
	   if (-e "/tmp/xcat/client.csr.$$") { unlink "/tmp/xcat/client.csr.$$"; }
	   open($csrfile,">","/tmp/xcat/client.csr.$$");
	   unless($csrfile) { next; }
	   my @statdat = stat $csrfile;
	   while ($statdat[4] != 0 or $statdat[2] & 020 or $statdat[2] & 002) { #try to be paranoid, root better own the file, and it better not be writable by anyone but owner
		#this means to assure the filehandle is not write-accessible to others who may insert their malicious CSR
		close($csrfile);
                unlink("/tmp/xcat/client.csr.$$");
	        open($csrfile,">","/tmp/xcat/client.csr.$$");
	        @statdat = stat $csrfile;
           }
	   print $csrfile $csr;
	   close($csrfile);
           #ok, at this point, we can verify that the subject is one we wouldn't mind signing...
           my $subject=`openssl req -in /tmp/xcat/client.csr.$$ -subject -noout`;
	   chomp($subject);
	   unless ($subject =~ /CN=$client\z/) { unlink("/tmp/xcat/client.csr.$$"); next; }
	   unlink "/tmp/xcat/client.cert.$$";
           open($csrfile,">","/tmp/xcat/client.cert.$$");
	   @statdat = stat $csrfile;
	   while ($statdat[4] != 0 or $statdat[2] & 020 or $statdat[2] & 002) { #try to be paranoid, root better own the file, and it better not be writable by anyone but owner
		#this prevents an attacker from predicting pid and pre-setting up a file that they can corrupt for DoS
		close($csrfile);
                unlink("/tmp/xcat/client.csr.$$");
	        open($csrfile,">","/tmp/xcat/client.csr.$$");
	        @statdat = stat $csrfile;
           }
	   close($csrfile);
	   open($csrfile,"<","/etc/xcat/ca/index");
	   my @caindex = <$csrfile>;
	   close($csrfile);
           foreach (@caindex) {
		chomp;
		my ($type, $expiry, $revoke, $serial, $fname, $subject) = split /\t/;
		if ($type eq 'V' and $subject =~ /CN=$client\z/) { #we already have a valid certificate, new request replaces it, revoke old
			print "The time of replacing is at hand for $client\n";
			system("openssl ca -config /etc/xcat/ca/openssl.cnf -revoke /etc/xcat/ca/certs/$serial.pem");
		}
	   }
	   my $rc = system("openssl ca -config /etc/xcat/ca/openssl.cnf -in /tmp/xcat/client.csr.$$ -out /tmp/xcat/client.cert.$$ -batch");
	   unlink("/tmp/xcat/client.csr.$$");
	   umask ($oldumask);
	   if ($rc) { next; }
	   open ($csrfile,"<","/tmp/xcat/client.cert.$$");
	   my @certdata = <$csrfile>;
	   close($csrfile);
	   unlink "/tmp/xcat/client.cert.$$";
           my $certcontents = join('',@certdata);
           push @{$rsp->{'data'}},{content=>[$certcontents],desc=>[$parm]};
       } elsif ($parm =~ /xcat_dockerhost_cert/) {
          `logger -t xcat -p local4.info "credentials: sending $parm"` ;
          unless (-r "/etc/xcatdockerca/cert/dockerhost-cert.pem") {
            push @{$rsp->{'error'}},"Unable to read /etc/xcatdockerca/cert/dockerhost-cert.pem ";
            `logger -t xcat -p local4.info "credentials: Unable to read /etc/xcatdockerca/cert/dockerhost-cert.pem"` ;
            next;
          }
          $tfilename = "/etc/xcatdockerca/cert/dockerhost-cert.pem";

       } else {
          next;
       }
	#check if the file exists or not
       if (defined $tfilename && -r $tfilename) {
           open($tmpfile,$tfilename);
           @filecontent=<$tmpfile>;
           close($tmpfile);
           $retdata = "\n".join('',@filecontent);
           push @{$rsp->{'data'}},{content=>[$retdata],desc=>[$parm]};
           $retdata="";
           @filecontent=();
       }
    }
    if (defined $rsp->{data}->[0]) {
	#if we got the data from the file, send the data message to the client
        xCAT::MsgUtils->message("D", $rsp, $callback, 0);
        return;
    }else {
	#if the file doesn't exist, send the error message to the client
        delete $rsp->{'data'};
        xCAT::MsgUtils->message("E", $rsp, $callback, 0);
    }
    return;
}

sub ok_with_node {
   my $node = shift;
   #Here we connect to the node on a privileged port and ask the
   #node if it just asked us for credential.  It's convoluted, but it is 
   #a convenient way to see if root on the ip has approved requests for
   #credential retrieval.  Given the nature of the situation, it is only ok
   #to assent to such requests before users can log in.  During postscripts
   #stage in stateful nodes and during the rc scripts of stateless boot
   #This is about equivalent to host-based authentication in Unix world
   #Generally good to move on to more robust mechanisms, but in an unattended context
   #this proves difficult to do robustly.
   #one TODO would be a secure mode where we make use of TPM modules to enhance in some way
   my $select = new IO::Select;
   #sleep 0.5; # gawk script race condition might exist, try to lose just in case
   my $parms = shift;
   my $method=$parms->[0];
   my $port = $parms->[1];
   if ($method == 0) { #PLAIN
       my $sock = new IO::Socket::INET(PeerAddr=>$node,
                                         Proto => "tcp",
                                         PeerPort => $port);
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
   } elsif ($method == 1) { #HTTPS
       use LWP;
       use HTTP::Request::Common;
       my $browser = LWP::UserAgent->new();
       $browser->timeout(10);
       $SIG{ALRM} = sub {}; #just need to interrupt the system call
       alarm(10);
       my $response = $browser->request(GET "https://$node:$port/");
       alarm(0);
       if ($response->is_success and $response->{'_content'} =~ /Ciphers supported in s_server binary/) { 
            #We are looking for openssl s_server running with -http, not settling for just any https response
           return 1;
       }
   }
   return 0;#if here, something wrong happened, return false
}
                                    
   
1;
