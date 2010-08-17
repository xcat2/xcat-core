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
use xCAT::Table;
use Data::Dumper;
use xCAT::NodeRange;
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
    my %rsp;
    # do your processing here
    # return info

    if ($client) { ($client) = noderange($client) };
    unless ($client) { #Not able to do host authentication, abort
       return;
    }
    my $credcheck;
    if ($request->{'callback_port'} and $request->{'callback_port'}->[0] and $request->{'callback_port'}->[0] < 1024) {
        $credcheck=[0,request->{'callback_port'}->[0]];
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

    foreach (@params_to_return) {

       if (/ssh_root_key/) { 
          unless (-r "$root/.ssh/id_rsa") {
            push @{$rsp->{'error'}},"Unable to read root's private ssh key";
            next;
          }
          $tfilename = "$root/.ssh/id_rsa";

       } elsif (/xcat_server_cred/) {
          unless (-r "/etc/xcat/cert/server-cred.pem") {
            push @{$rsp->{'error'}},"Unable to read root's private xCAT key";
            next;
          }
          $tfilename = "/etc/xcat/cert/server-cred.pem";

       } elsif (/xcat_client_cred/ or /xcat_root_cred/) {
          unless (-r "$root/.xcat/client-cred.pem") {
            push @{$rsp->{'error'}},"Unable to read root's private xCAT key";
            next;
          }
          $tfilename = "$root/.xcat/client-cred.pem";

       } elsif (/ssh_dsa_hostkey/) {
          unless (-r "/etc/xcat/hostkeys/ssh_host_dsa_key") {
             push @{$rsp->{'error'}},"Unable to read private DSA key from /etc/xcat/hostkeys";
             next;
          }
          $tfilename="/etc/xcat/hostkeys/ssh_host_dsa_key";

       } elsif (/ssh_rsa_hostkey/) {
          unless (-r "/etc/xcat/hostkeys/ssh_host_rsa_key") {
             push @{$rsp->{'error'}},"Unable to read private RSA key from /etc/xcat/hostkeys";
             next;
          }
          $tfilename="/etc/xcat/hostkeys/ssh_host_rsa_key";

       } elsif (/xcat_cfgloc/) {
          unless (-r "/etc/xcat/cfgloc") {
            push @{$rsp->{'error'}},"Unable to read xCAT database location";
            next;
          }
          $tfilename = "/etc/xcat/cfgloc";

       } elsif (/krb5_keytab/) { #TODO: MUST RELAY TO MASTER
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
           push @{$rsp->{'data'}},{content=>[$tabdata],desc=>[$_]};
           unlink "/tmp/xcat/keytab.$$";
           next;
       } else {
          next;
       }
	#check if the file exists or not
       if (defined $tfilename && -r $tfilename) {
           open($tmpfile,$tfilename);
           @filecontent=<$tmpfile>;
           close($tmpfile);
           $retdata = "\n".join('',@filecontent);
           push @{$rsp->{'data'}},{content=>[$retdata],desc=>[$_]};
           $retdata="";
           @filecontent=();
       }
    }
    if (defined $rsp->{data}->[0]) {
	#if we got the data from the file, send the data message to the client
        xCAT::MsgUtils->message("D", $rsp, $callback, 0);
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
