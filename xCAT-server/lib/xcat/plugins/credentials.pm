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
      signx509cert (service-node delegation only)

=cut

#-------------------------------------------------------
package xCAT_plugin::credentials;
use strict;
use xCAT::Table;
use Data::Dumper;
use xCAT::NodeRange;
use xCAT::Zone;
use File::Temp qw(tempfile);
use IO::Socket::INET;
use Time::HiRes qw(sleep);

use xCAT::Utils;
use xCAT::NetworkUtils;
use xCAT::PasswordUtils;
use xCAT::TableUtils;

use xCAT::MsgUtils;
use Getopt::Long;

use constant DELEGATED_SIGNING_TIMEOUT => 30;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
        getcredentials => "credentials",
        signx509cert   => "credentials",
    };
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
my $callback;

sub process_request
{

    my $request = shift;
    $callback = shift;
    my $command = $request->{command}->[0];
    my $args    = $request->{arg};
    my $envs    = $request->{env};
    my $client;

    if ($command eq 'signx509cert') {
        my $node = $request->{arg} ? $request->{arg}->[0] : undef;
        my $csr  = $request->{csr} ? $request->{csr}->[0] : undef;
        unless ($node and $csr and _delegated_signer_allowed($request, $node)) {
            xCAT::MsgUtils->trace(0, 'E', 'Rejected delegated certificate request');
            $callback->({ error => ['Delegated certificate request denied'], errorcode => [1] });
            return;
        }
        my $certificate = _sign_x509_certificate($node, $csr);
        unless ($certificate) {
            $callback->({ error => ["Unable to sign certificate for $node"], errorcode => [1] });
            return;
        }
        $callback->({ data => [{ content => [$certificate], desc => ['x509cert'] }] });
        return;
    }

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
    my $origclient = $client;
    if ($client) { ($client) = noderange($client) }
    unless ($client) {    #Not able to do host authentication, abort
        xCAT::MsgUtils->trace(0, "E", "Received getcredentials from $origclient, which couldn't be correlated to a node (domain mismatch?)");
        return;
    }
    my $credcheck;
    if ($request->{'callback_port'} and $request->{'callback_port'}->[0] and $request->{'callback_port'}->[0] < 1024) {
        $credcheck = [ 0, $request->{'callback_port'}->[0] ];
    } elsif ($request->{'callback_https_port'} and $request->{'callback_https_port'}->[0] and $request->{'callback_https_port'}->[0] < 1024) {
        $credcheck = [ 1, $request->{'callback_https_port'}->[0] ];
    } else {
        xCAT::MsgUtils->trace(0, 'E', "Received malformed getcredentials requesting, ignore it.");
        return;
    }
    unless (ok_with_node($client, $credcheck)) {
        xCAT::MsgUtils->trace(0, 'E', "The node ($client) is not ready, ignore it.");
        return;
    }

    my @params_to_return = @{ $request->{arg} };
    $rsp->{data} = [];
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

        my $errorfindingkeys = 0;
        my $foundkeys        = 0;
        my $sshrootkeydir    = "$root/.ssh";    # old default
        if ((($parm =~ /^ssh_root_key/) || ($parm =~ /^ssh_root_pub_key/)) && ($foundkeys == 0)) {
            my ($rootkeyparm, $zonename) = split(/:/, $parm);
            my $client_zonename = xCAT::Zone->getmyzonename($client);
            my $default_zonename = xCAT::Zone->getdefaultzone();
            
            if ($zonename) {
                $parm = $rootkeyparm;           # take the zone off
                xCAT::MsgUtils->trace(0, 'I', "credentials: The node ($client) is asking for sshkeys of zone: $zonename.");
                if ($client_zonename eq $zonename) {
                    my $sshbetweenodes_allowed = xCAT::Zone->enableSSHbetweennodes($client);
                    if (($sshbetweenodes_allowed == 1) || ($parm =~ /^ssh_root_pub_key/)) { # check if sshbetweennodes is allowed or pub key is requested
                        $sshrootkeydir = xCAT::Zone->getzonekeydir($zonename);
                        if ($sshrootkeydir == 1) {    # error return
                            xCAT::MsgUtils->trace(0, 'W', "credentials: The zone: $zonename is not defined.");
                        } else {
                            $foundkeys = 1; # don't want to read the zone data twice
                        }
                    } else {
                        xCAT::MsgUtils->trace(0, 'E', "credentials: Not allowed to read root's private ssh key because sshbetweennodes is disabled.");
                        $sshrootkeydir = 1;
                    }
                } else {
                    xCAT::MsgUtils->trace(0, 'E', "credentials: Not allowed to read root's private ssh key of different zone.");
                    $sshrootkeydir = 1;
                }
            } elsif ($client_zonename ne $default_zonename) { # check if no zonename is submitted but node is not in default zone
                xCAT::MsgUtils->trace(0, 'E', "credentials: Not allowed to read root's private ssh key of default zone.");
                $sshrootkeydir = 1;
            }
        }
        if ($parm =~ /ssh_root_key/) {
            unless (-r "$sshrootkeydir/id_rsa") {
                push @{ $rsp->{'error'} }, "Unable to read root's private ssh key";
                xCAT::MsgUtils->trace(0, 'E', "credentials: Unable to read root's private ssh key");
                next;
            }
            xCAT::MsgUtils->trace(0, 'I', "credentials: sending $parm to $client");
            $tfilename = "$sshrootkeydir/id_rsa";
            xCAT::MsgUtils->trace(0, 'I', "credentials: The root's private ssh key is in $tfilename.");

        } elsif ($parm =~ /ssh_root_pub_key/) {
            unless (-r "$sshrootkeydir/id_rsa.pub") {
                push @{ $rsp->{'error'} }, "Unable to read root's public ssh key";
                xCAT::MsgUtils->trace(0, 'E', "credentials: Unable to read root's public ssh key");
                next;
            }
            xCAT::MsgUtils->trace(0, 'I', "credentials: sending $parm to $client");
            $tfilename = "$sshrootkeydir/id_rsa.pub";
            xCAT::MsgUtils->trace(0, 'I', "credentials: The root's public ssh key is in $tfilename.");

        } elsif ($parm =~ /xcat_server_cred/) {
            unless (-r "/etc/xcat/cert/server-cred.pem") {
                push @{ $rsp->{'error'} }, "Unable to read xcat_server_cred";
                xCAT::MsgUtils->trace(0, 'E', "credentials: Unable to read xcat_server_cred");
                next;
            }
            xCAT::MsgUtils->trace(0, 'I', "credentials: sending $parm to $client");
            $tfilename = "/etc/xcat/cert/server-cred.pem";

        } elsif (($parm =~ /xcat_client_cred/) or ($parm =~ /xcat_root_cred/)) {
            unless (-r "$root/.xcat/client-cred.pem") {
                push @{ $rsp->{'error'} }, "Unable to read xcat_client_cred or xcat_root_cred";
                xCAT::MsgUtils->trace(0, 'E', "credentials: Unable to read xcat_client_cred or xcat_root_cred");
                next;
            }
            xCAT::MsgUtils->trace(0, 'I', "credentials: sending $parm to $client");
            $tfilename = "$root/.xcat/client-cred.pem";

        } elsif ($parm =~ /ssh_dsa_hostkey/) {
            xCAT::MsgUtils->trace(0, 'I', "credentials: sending $parm to $client");
            if (-r "/etc/xcat/hostkeys/$client/ssh_host_dsa_key") {
                $tfilename = "/etc/xcat/hostkeys/$client/ssh_host_dsa_key";
            } elsif (-r "/etc/xcat/hostkeys/ssh_host_dsa_key") {
                $tfilename = "/etc/xcat/hostkeys/ssh_host_dsa_key";
            } else {
                push @{ $rsp->{'error'} }, "Unable to read private DSA key from /etc/xcat/hostkeys";
                xCAT::MsgUtils->trace(0, 'E', "credentials: Unable to read private DSA key");
                next;
            }
        } elsif ($parm =~ /ssh_rsa_hostkey/) {
            xCAT::MsgUtils->trace(0, 'I', "credentials: sending $parm to $client");
            if (-r "/etc/xcat/hostkeys/$client/ssh_host_rsa_key") {
                $tfilename = "/etc/xcat/hostkeys/$client/ssh_host_rsa_key";
            } elsif (-r "/etc/xcat/hostkeys/ssh_host_rsa_key") {
                $tfilename = "/etc/xcat/hostkeys/ssh_host_rsa_key";
            } else {
                push @{ $rsp->{'error'} }, "Unable to read private RSA key from /etc/xcat/hostkeys";
                xCAT::MsgUtils->trace(0, 'E', "credentials: Unable to read private RSA key");
                next;
            }
        } elsif ($parm =~ /ssh_ecdsa_hostkey/) {
            xCAT::MsgUtils->trace(0, 'I', "credentials: sending $parm to $client");
            if (-r "/etc/xcat/hostkeys/$client/ssh_host_ecdsa_key") {
                $tfilename = "/etc/xcat/hostkeys/$client/ssh_host_ecdsa_key";
            } elsif (-r "/etc/xcat/hostkeys/ssh_host_ecdsa_key") {
                $tfilename = "/etc/xcat/hostkeys/ssh_host_ecdsa_key";
            } else {
                push @{ $rsp->{'error'} }, "Unable to read private ECDSA key from /etc/xcat/hostkeys";
                xCAT::MsgUtils->trace(0, 'E', "credentials: Unable to read private ECDSA key");
                next;
            }
        } elsif ($parm =~ /ssh_ed25519_hostkey/) {
            xCAT::MsgUtils->trace(0, 'I', "credentials: sending $parm to $client");
            if (-r "/etc/xcat/hostkeys/$client/ssh_host_ed25519_key") {
                $tfilename = "/etc/xcat/hostkeys/$client/ssh_host_ed25519_key";
            } elsif (-r "/etc/xcat/hostkeys/ssh_host_ed25519_key") {
                $tfilename = "/etc/xcat/hostkeys/ssh_host_ed25519_key";
            } else {
                push @{ $rsp->{'error'} }, "Unable to read private ed25519 key from /etc/xcat/hostkeys";
                xCAT::MsgUtils->trace(0, 'E', "credentials: Unable to read private ed25519 key");
                next;
            }
        } elsif ($parm =~ /xcat_cfgloc/) {
            xCAT::MsgUtils->trace(0, 'I', "credentials: sending $parm to $client");
            unless (-r "/etc/xcat/cfgloc") {
                push @{ $rsp->{'error'} }, "Unable to read /etc/xcat/cfgloc ";
                xCAT::MsgUtils->trace(0, 'E', "credentials: Unable to read /etc/xcat/cfgloc");
                next;
            }
            $tfilename = "/etc/xcat/cfgloc";

        } elsif ($parm =~ /krb5_keytab/) {    #TODO: MUST RELAY TO MASTER
            xCAT::MsgUtils->trace(0, 'I', "credentials: sending $parm to $client");
            my $princsuffix = $request->{'_xcat_clientfqdn'}->[0];
            $ENV{KRB5CCNAME} = "/tmp/xcat/krb5cc_xcat_$$";
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
            my $tabdata = "\n";
            my $buf;
            require MIME::Base64;

            while (read($keytab, $buf, 1140)) {
                $tabdata .= MIME::Base64::encode_base64($buf);
            }
            push @{ $rsp->{'data'} }, { content => [$tabdata], desc => [$parm] };
            unlink "/tmp/xcat/keytab.$$";
            next;
        } elsif ($parm =~ /x509cert/) {
            xCAT::MsgUtils->trace(0, 'I', "credentials: sending $parm to $client");
            my $csr = $request->{'csr'}->[0];
            my ($certificate, $error);
            if (xCAT::Utils->isServiceNode()) {
                ($certificate, $error) = _request_x509_from_master($client, $csr);
            } else {
                $certificate = _sign_x509_certificate($client, $csr);
            }
            if ($certificate) {
                push @{ $rsp->{'data'} }, { content => [$certificate], desc => [$parm] };
            } elsif ($error) {
                push @{ $rsp->{'error'} }, $error;
            }
            next;
        } elsif ($parm =~ /xcat_secure_pw:/) {
            xCAT::MsgUtils->trace(0, 'I', "credentials: sending $parm to $client");
            my @users=split(/:/,$parm);
            if (defined($users[1]) and $users[1] eq 'root') {
                my $pass = xCAT::PasswordUtils::crypt_system_password();
                if ($pass) {
                    push @{$rsp->{'data'}}, { content => [ $pass ], desc => [ $parm ] };
                }
            }
            next;
        } else {
            xCAT::MsgUtils->trace(0, 'W', "credentials: Not supported type: $parm");
            next;
        }

        #check if the file exists or not
        if (defined $tfilename && -r $tfilename) {
            open($tmpfile, $tfilename);
            @filecontent = <$tmpfile>;
            close($tmpfile);
            $filecontent[$#filecontent] =~ s/\n?$/\n/;
            $retdata = "\n" . join('', @filecontent);
            push @{ $rsp->{'data'} }, { content => [$retdata], desc => [$parm] };
            $retdata     = "";
            @filecontent = ();
        }
    }
    if (defined $rsp->{data}->[0]) {

        #if we got the data from the file, send the data message to the client
        xCAT::MsgUtils->message("D", $rsp, $callback, 0);
        return;
    } else {

        #if the file doesn't exist, send the error message to the client
        delete $rsp->{'data'};
        xCAT::MsgUtils->message("E", $rsp, $callback, 0);
    }
    return;
}

sub _delegated_signer_allowed {
    my ($request, $node) = @_;
    return 0 unless $request->{'_xcat_authname'}
      and $request->{'_xcat_authname'}->[0] eq 'root';
    return 0 unless $node;

    my %requester;
    my @identity_attributes = $request->{'_xcat_clientip'}
      ? qw(_xcat_clientip)
      : qw(_xcat_clienthost _xcat_clientfqdn);
    foreach my $attribute (@identity_attributes) {
        next unless $request->{$attribute};
        my $value = ref($request->{$attribute}) eq 'ARRAY'
          ? $request->{$attribute}->[0] : $request->{$attribute};
        $requester{$_} = 1 for _endpoint_identities($value);
    }
    return 0 unless %requester;

    my $noderes = xCAT::Table->new('noderes');
    return 0 unless $noderes;
    my $attributes = $noderes->getNodeAttribs($node, ['servicenode']);
    return 0 unless $attributes and $attributes->{servicenode};

    foreach my $service_node (split /,/, $attributes->{servicenode}) {
        return 1 if grep { $requester{$_} } _endpoint_identities($service_node);
    }
    return 0;
}

sub _endpoint_identities {
    my $endpoint = shift;
    return unless defined($endpoint);
    $endpoint =~ s/^\s+|\s+$//g;
    return unless length($endpoint);

    my %identities;
    my $name = _normalize_endpoint_identity($endpoint);
    $identities{$name} = 1;

    my @addresses = xCAT::NetworkUtils->getipaddr($endpoint, GetAllAddresses => 1);
    foreach my $address (@addresses) {
        next unless defined($address) && length($address);
        $identities{_normalize_endpoint_identity($address)} = 1;
    }
    return keys %identities;
}

sub _normalize_endpoint_identity {
    my $identity = lc(shift);
    $identity =~ s/\.$//;
    $identity =~ s/^::ffff:(?=\d+(?:\.\d+){3}\z)//;
    return $identity;
}

sub _request_x509_from_master {
    my ($node, $csr) = @_;
    my @masters = xCAT::TableUtils->get_site_attribute('master');
    unless ($masters[0]) {
        my $error = 'The management node is not configured';
        xCAT::MsgUtils->trace(0, 'E', $error);
        return wantarray ? (undef, $error) : undef;
    }

    require xCAT::Client;
    local $ENV{XCATHOST} = $masters[0] =~ /:/
      ? "[$masters[0]]:3001"
      : "$masters[0]:3001";
    my $certificate;
    my @errors;
    my $request = {
        command => ['signx509cert'],
        arg     => [$node],
        csr     => [$csr],
    };
    my $failure;
    {
        local $SIG{ALRM} = sub {
            die 'management node request timed out after '
              . DELEGATED_SIGNING_TIMEOUT . " seconds\n";
        };
        my $request_ok = eval {
            alarm(DELEGATED_SIGNING_TIMEOUT);
            xCAT::Client::submit_request($request, sub {
                my $response = shift;
                my $response_errors = $response->{error};
                if (defined($response_errors)) {
                    my @response_errors = ref($response_errors) eq 'ARRAY'
                      ? @{$response_errors} : ($response_errors);
                    push @errors,
                      grep { defined($_) && !ref($_) && length($_) } @response_errors;
                }
                foreach my $data (@{ $response->{data} || [] }) {
                    next unless ref($data) eq 'HASH';
                    my $description = ref($data->{desc}) eq 'ARRAY'
                      ? $data->{desc}->[0] : $data->{desc};
                    next unless $description and $description eq 'x509cert';
                    $certificate = ref($data->{content}) eq 'ARRAY'
                      ? $data->{content}->[0] : $data->{content};
                }
            });
            1;
        };
        $failure = $@ unless $request_ok;
        alarm(0);
    }
    unless ($certificate) {
        my $reason = $failure || join('; ', @errors) || 'management node returned no certificate';
        $reason =~ s/[\r\n]+/ /g;
        $reason =~ s/\s+$//;
        my $error = "Unable to obtain a delegated certificate for $node: $reason";
        xCAT::MsgUtils->trace(0, 'E', $error);
        return wantarray ? (undef, $error) : undef;
    }
    return wantarray ? ($certificate, undef) : $certificate;
}

sub _csr_subject_matches_node {
    my ($csrpath, $client) = @_;
    open(my $subject_file, '-|', 'openssl', 'req', '-in', $csrpath,
        '-subject', '-noout', '-nameopt', 'RFC2253')
      or die "cannot inspect CSR";
    my $subject = <$subject_file>;
    close($subject_file) or die "invalid CSR";
    $subject =~ s/[\r\n]+$// if defined($subject);
    return 0 unless defined($subject);
    return $subject =~ /^subject=\s*CN=\Q$client\E\z/ ? 1 : 0;
}

sub _sign_x509_certificate {
    my ($client, $csr) = @_;
    my $oldumask = umask 0077;
    my ($csrfile, $csrpath);
    my ($certfile, $certpath);
    my $certificate;
    my $failure;

    my $signing_ok = eval {
        ($csrfile, $csrpath) = tempfile('xcat-client-csr-XXXXXX', TMPDIR => 1, UNLINK => 0);
        print {$csrfile} $csr or die "cannot write CSR";
        close($csrfile) or die "cannot close CSR";

        die "certificate subject does not match node"
          unless _csr_subject_matches_node($csrpath, $client);

        ($certfile, $certpath) = tempfile('xcat-client-cert-XXXXXX', TMPDIR => 1, UNLINK => 0);
        close($certfile) or die "cannot close certificate file";

        open(my $index, '<', '/etc/xcat/ca/index') or die "cannot read CA index";
        my @caindex = <$index>;
        close($index) or die "cannot close CA index";
        foreach (@caindex) {
            chomp;
            my ($type, $expiry, $revoke, $serial, $fname, $certificate_subject) = split /\t/;
            if ($type eq 'V' and $certificate_subject =~ /^\/CN=\Q$client\E\z/) {
                xCAT::MsgUtils->trace(0, 'I', "credentials: replacing the certificate for $client");
                system('openssl', 'ca', '-config', '/etc/xcat/ca/openssl.cnf',
                    '-revoke', "/etc/xcat/ca/certs/$serial.pem") == 0
                  or die "cannot revoke previous certificate";
            }
        }
        system('openssl', 'ca', '-config', '/etc/xcat/ca/openssl.cnf',
            '-in', $csrpath, '-out', $certpath, '-batch') == 0
          or die "certificate signing failed";

        open(my $signed, '<', $certpath) or die "cannot read signed certificate";
        local $/;
        $certificate = <$signed>;
        close($signed) or die "cannot close signed certificate";
        1;
    };
    $failure = $@ unless $signing_ok;

    unlink($csrpath) if $csrpath and -e $csrpath;
    unlink($certpath) if $certpath and -e $certpath;
    umask($oldumask);
    if ($failure) {
        chomp($failure);
        xCAT::MsgUtils->trace(0, 'E', "Unable to sign certificate for $client: $failure");
        return;
    }
    return $certificate;
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
    my $parms  = shift;
    my $method = $parms->[0];
    my $port   = $parms->[1];
    if ($method == 0) {    #PLAIN
        my $sock = new IO::Socket::INET(PeerAddr => $node,
            Proto    => "tcp",
            PeerPort => $port);
        my $rsp;
        unless ($sock) { return 0 }
        $select->add($sock);
        print $sock "CREDOKBYYOU?\n";
        unless ($select->can_read(5)) {    #wait for data for up to five seconds
            return 0;
        }
        my $response = <$sock>;
        chomp($response);
        if ($response eq "CREDOKBYME") {
            return 1;
        }
    } elsif ($method == 1) {    #HTTPS
        use LWP;
        use HTTP::Request::Common;
        my $browser = LWP::UserAgent->new();
        $browser->timeout(10);
        $SIG{ALRM} = sub { };    #just need to interrupt the system call
        alarm(10);
        my $response = $browser->request(GET "https://$node:$port/");
        alarm(0);

        if ($response->is_success and $response->{'_content'} =~ /Ciphers supported in s_server binary/) {

            #We are looking for openssl s_server running with -http, not settling for just any https response
            return 1;
        }
    }
    return 0;    #if here, something wrong happened, return false
}


1;
