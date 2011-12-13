#!/usr/bin/perl
# IBM(c) 2107 EPL license http://www.eclipse.org/legal/epl-v10.html
#(C)IBM Corp
#modified by jbjohnso@us.ibm.com
#This module abstracts the session management aspects of IPMI

package xCAT::IPMI;
        use Carp qw/confess cluck/;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";

use IO::Socket::INET;
my $doipv6=eval {
	require IO::Socket::INET6; 
	IO::Socket::INET6->import();
	require Socket6;
        Socket6->import();
	1;
};
use IO::Select;
#use Data::Dumper;
use Digest::MD5 qw/md5/;
my $pendingpackets=0;
my $maxpending; #determined dynamically based on rcvbuf detection
my $ipmi2support = eval {
    require Digest::SHA1;
    Digest::SHA1->import(qw/sha1/);
    require Digest::HMAC_SHA1;
    Digest::HMAC_SHA1->import(qw/hmac_sha1/);
    1;
};
my $aessupport;
if ($ipmi2support) {
    $aessupport = eval {
        require Crypt::Rijndael;
        require Crypt::CBC;
        1;
    };
}
sub hexdump {
    foreach  (@_) {
        printf "%02X ",$_;
    }
    print "\n";
}

my %payload_types = ( #help readability in certain areas of code by specifying payload by name rather than number
    'ipmi' => 0,
    'sol' => 1, 
    'rmcpplusopenreq' => 0x10,
    'rmcpplusopenresponse' => 0x11,
    'rakp1' => 0x12,
    'rakp2' => 0x13,
    'rakp3' => 0x14,
    'rakp4' => 0x15,
    );
my $socket; #global socket for all sessions to share.  Fun fun
my $select = IO::Select->new();

my %bmc_handlers; #hash from bmc address to a live session management object.  
#only one allowed at a time per bmc
my %sessions_waiting; #track session objects that may want to retry a packet, value is timestamp to 'wake' object for retransmit

sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self = {};
    bless $self,$class;
    my %args = @_;
    unless ($ipmi2support) {
        $self->{ipmi15only} = 1;
    }
    unless ($args{'bmc'} and defined $args{'userid'} and defined $args{'password'}) {
        $self->{error}="bmc, userid, and password must be specified";
        return $self;
    }
    foreach (keys %args) { #store all passed parameters
        $self->{$_} = $args{$_};
    }
    unless ($args{'port'}) { #default to port 623 unless specified
        $self->{'port'} = 623;
    }
    unless ($socket) {
	if ($doipv6) {
	        $socket = IO::Socket::INET6->new(Proto => 'udp');
	} else {
	        $socket = IO::Socket::INET->new(Proto => 'udp');
	}
        if (-r "/proc/sys/net/core/rmem_max") { # we can detect the maximum allowed socket, read it.
            my $sysctl;
            open ($sysctl,"<","/proc/sys/net/core/rmem_max");
            my $maxrcvbuf=<$sysctl>;
            my $rcvbuf = $socket->sockopt(SO_RCVBUF);
             if ($maxrcvbuf > $rcvbuf) {
                 $socket->sockopt(SO_RCVBUF,$maxrcvbuf/2);
             }
              $maxpending=$maxrcvbuf/1500; #probably could have maxpending go higher, but just go with typical MTU as a guess
        } else { #We do not have a way to determine how high we could set RCVBUF, so read the current value and run with it
            my $rcvbuf = $socket->sockopt(SO_RCVBUF);
            $maxpending=$rcvbuf/1500; #probably could have maxpending go higher, but just go with typical MTU as a guess
        }
        $select->add($socket);
    }
    my $bmc_n;
    my ($family, $socktype, $protocol, $saddr, $name, $ip, $service);
    if ($doipv6) {
       ($family, $socktype, $protocol, $saddr, $name) = Socket6::getaddrinfo($self->{bmc},623,AF_UNSPEC,SOCK_DGRAM,0);
       ($ip,$service) = getnameinfo($saddr,$Socket6::NI_NUMERICHOST);
    }
    unless ($saddr or $bmc_n = inet_aton($self->{bmc})) {
        $self->{error} = "Could not resolve ".$self->{bmc}." to an address";
        return $self;
    }

    if ($ip and $ip =~ /::ffff:\d+\.\d+\.+\d+\.\d+/) {
	$ip =~ s/::ffff://;
    } elsif (not $ip and $bmc_n) {
	$ip = inet_ntoa($bmc_n);
    }
    $bmc_handlers{$ip}=$self;
    if ($saddr) { 
       $self->{peeraddr} = $saddr;
    } else  {
       $self->{peeraddr} = sockaddr_in($self->{port},$bmc_n);
    }
    $self->{'sequencenumber'} = 0; #init sequence number
        $self->{'sequencenumberbytes'} = [0,0,0,0]; #init sequence number
        $self->{'sessionid'} = [0,0,0,0]; # init session id
        $self->{'authtype'}=0; # first messages will have auth type of 0
        $self->{'ipmiversion'}='1.5'; # send first packet as 1.5
        $self->{'timeout'}=2; #start at a quick timeout, increase on retry
        $self->{'seqlun'}=0; #the IPMB seqlun combo, increment by 4s
        $self->{'logged'}=0;
    return $self;
}
sub login {
    my $self = shift;
    my %args = @_;
    if ($self->{logged}) {
        $args{callback}->("SUCCESS",$args{callback_args});
        return;
    }
    $self->{onlogon} = $args{callback};
    $self->{onlogon_args} = $args{callback_args};
    $self->get_channel_auth_cap();
}

sub logout {
    my $self = shift;
    my %args = @_;
    $self->{onlogout} =  $args{callback};
    $self->{onlogout_args} = $args{callback_args};
    unless ($self->{logged}) {
        if ( $self->{onlogout}) { $self->{onlogout}->("SUCCESS",$self->{onlogout_args}); }
        return;
    }
    $self->subcmd(netfn=>0x6,command=>0x3c,data=>$self->{sessionid},callback=>\&logged_out,callback_args=>$self);
}
sub logged_out {
    my $rsp = shift;
    my $self = shift;
    if (defined $rsp->{code} and $rsp->{code} == 0) { 
        $self->{logged}=0;
        if ( $self->{onlogout}) { 
            $self->{onlogout}->("SUCCESS",$self->{onlogout_args});
        }
    } else {
        if ( $self->{onlogout}) {
            $self->{onlogout}->("ERROR:",$self->{onlogout_args});
        }
    }
}

sub get_channel_auth_cap { #implement special case for session management command
    my $self = shift;
    if (defined $self->{ipmi15only}) {
        $self->subcmd(netfn=>0x6,command=>0x38,data=>[0x0e,0x04],callback=>\&got_channel_auth_cap,callback_args=>$self);
    } else {
        $self->subcmd(netfn=>0x6,command=>0x38,data=>[0x8e,0x04],callback=>\&got_channel_auth_cap,callback_args=>$self);
    }
#0x8e, set bit to signify recognition of IPMI 2.0 and request channel 'e', current.  
#0x04, request administrator privilege
}

sub get_session_challenge  {
    my $self = shift;
    my @user;
    if ($self->{userbytes}) {
        @user = @{$self->{userbytes}};
    } else {
        @user =  unpack("C*",$self->{userid});
        for (my $i=scalar @user;$i<16;$i++) {
            $user[$i]=0;
        }
        $self->{userbytes} = \@user;
    }
    $self->subcmd(netfn=>0x6,command=>0x39,data=>[2,@user],callback=>\&got_session_challenge,callback_args=>$self); #we only support MD5, we would have errored out if not supported
}

sub got_session_challenge {
    my $rsp = shift;
    my $self = shift;
    my @data = @{$rsp->{data}};
    my %localcodes = ( 0x81 => "Invalid user name", 0x82 => "null user disabled" );
    my $code = $rsp->{code}; #just to save me some typing
        if ($code) { 
            my $errtxt = sprintf("ERROR: Get challenge failed with %02xh",$code);
            if ($localcodes{$code}) {
                $errtxt .= " ($localcodes{$code})";
            } #TODO: generic codes

            $self->{onlogon}->($errtxt, $self->{onlogon_args});
            return;
        }
    $self->{sessionid} = [splice @data,0,4];
    $self->{authtype}=2; #switch to auth mode
        $self->activate_session(@data);
}

sub activate_session {
    my $self = shift;
    my @challenge = @_;
    my @data = (2,4,@challenge,1,0,0,0);
    $self->subcmd(netfn=>0x6,command=>0x3a,data=>\@data,callback=>\&session_activated,callback_args=>$self);
}

sub session_activated {
    my $rsp = shift;
    my $self = shift;
    my $code = $rsp->{code}; #just to save me some typing
        my %localcodes = (
                0x81 => "No available login slots",
                0x82 => "No available login slots for ".$self->{userid},
                0x83 => "No slot available as administrator",
                0x84 => "Session sequence number out of range",
                0x85 => "Invalid session ID",
                0x86 => $self->{userid}. " is not allowed to be Administrator or Administrator not allowed over network",
                );
    my @data = @{$rsp->{data}};
    if ($code) {
        my $errtxt = sprintf("ERROR: Unable to log in to BMC due to code %02xh",$code);
        if ($localcodes{$code}) {
            $errtxt .= " ($localcodes{$code})";
        }
        $self->{onlogon}->($errtxt, $self->{onlogon_args});
    }
    $self->{sessionid} = [splice @data,1,4];
    $self->{sequencenumber}=$data[1]+($data[2]<<8)+($data[3]<<16)+($data[4]<<24);
    $self->{sequencenumberbytes} = [splice @data,1,4];
    $self->set_admin_level();
}

sub set_admin_level {
    my $self= shift;
    $self->subcmd(netfn=>0x6,command=>0x3b,data=>[4],callback=>\&admin_level_set,callback_args=>$self);
}
sub admin_level_set {
    my $rsp = shift;
    my $self = shift;
    my %localcodes = (
            0x80 => $self->{userid}." is not allowed administrator access",
            0x81 => "This user or channel is not allowed administrator access",
            0x82 => "Cannot disable User Level authentication",
            );
    my $code = $rsp->{code};
    if ($code) {
        my $errtxt = sprintf("ERROR: Failed requesting  administrator privilege %02xh",$code);
        if ($localcodes{$code}) {
            $errtxt .= " (".$localcodes{$code}.")";
        }
        $self->{onlogon}->($errtxt,$self->{onlogon_args});
    } else {
        $self->{logged}=1;
        $self->{onlogon}->("SUCCESS",$self->{onlogon_args});
    }
}
sub got_channel_auth_cap {
    my $rsp = shift;
    my $self = shift;
    if ($rsp->{error}) {
        $self->{onlogon}->("ERROR: ".$rsp->{error}, $self->{onlogon_args});
        return;
    }
    my $code = $rsp->{code}; #just to save me some typing
        if ($code == 0xcc and not defined $self->{ipmi15only}) { #ok, most likely a stupid ipmi 1.5 bmc
            $self->{ipmi15only}=1;
            return $self->get_channel_auth_cap();
        }
    if ($code != 0) { 
        $self->{onlogon}->("ERROR: Get channel capabilities failed with $code", $self->{onlogon_args});
        return;
    }
    my @data = @{$rsp->{data}};
    $self->{currentchannel} = $data[0];
    if (($data[1] & 0b10000000) and ($data[3] & 0b10)) {
        $self->{ipmiversion} = '2.0';
    }
    if ($self->{ipmiversion} eq '1.5') {
        unless ($data[1] & 0b100) { 
            $self->{onlogon}->("ERROR: MD5 is required but not enabeld or available on target BMC",$self->{onlogon_args});
        }
        $self->get_session_challenge();
    } elsif ($self->{ipmiversion} eq '2.0') { #do rmcp+
        $self->open_rmcpplus_request();

    }

}
sub open_rmcpplus_request {
    my $self = shift;
    $self->{'authtype'}=6;
    $self->{sidm} = [0x15,0x58,0x25,0x7a];
    my @payload = (0x1f,#message tag, TODO: could be random
            0, #requested privilege role, 0 is highest allowed
            0,0, #reserved
            0x15,0x58,0x25,0x7a, #we only have to sweat one session, so no need to generate
            0,0,0,8,1,0,0,0, #table 13-17, request sha
            1,0,0,8,1,0,0,0); #sha integrity
        if ($aessupport) { 
            push @payload,(2,0,0,8,1,0,0,0);
        } else {
            push @payload,(2,0,0,8,0,0,0,0);
        }
    $self->{sessionestablishmentcontext} = 'opensession';
    $self->sendpayload(payload=>\@payload,type=>$payload_types{'rmcpplusopenreq'});
}

sub checksum {
    my $self = shift;
    my $sum = 0;
    foreach(@_) {
        $sum += $_;
    }
    $sum = ~$sum + 1;
    return($sum&0xff);
}

sub subcmd {
    my $self = shift;
    my %args = @_;
    my $rqaddr=0x81; #see section 5.5 of ipmi2 spec, rqsa by old code 
    my $rsaddr=0x20; #figrue 13-4, rssa by old code
    my @rnl = ($rsaddr,$args{netfn}<<2);
    my @rest = ($rqaddr,$self->{seqlun},$args{command},@{$args{data}});
    my @payload=(@rnl,$self->checksum(@rnl),@rest,$self->checksum(@rest));
    $self->{seqlun} += 4; #increment by 1<<2
    $self->{seqlun} &= 0xff; #keep it one byte
    $self->{ipmicallback} = $args{callback};
    $self->{ipmicallback_args} = $args{callback_args};
    my $type = $payload_types{'ipmi'};
    if ($self->{integrityalgo}) {
        $type = $type | 0b01000000; #add integrity
    }
    if ($self->{confalgo}) {
        $type = $type | 0b10000000; #add secrecy
    }
    $self->sendpayload(payload=>\@payload,type=>$type);
}

sub waitforrsp {
    my $self=shift;
    my $data;
    my $peerport;
    my $peerhost;
    my $timeout; #TODO: code to scan pending objects to find soonest retry deadline
    my $curtime=time();
    foreach (keys %sessions_waiting) {
       if  ($sessions_waiting{$_}->{timeout} <= $curtime) { #retry or fail..
           my $session = $sessions_waiting{$_}->{ipmisession};
           delete $sessions_waiting{$_};
           $pendingpackets-=1;
           $session->timedout();
           next;
        }
        if (defined $timeout) {
            if ($timeout < $sessions_waiting{$_}->{timeout}-$curtime) {
                next;
            }
        }
        $timeout = $sessions_waiting{$_}->{timeout}-$curtime;
    }
    unless (defined $timeout) {
        return scalar (keys %sessions_waiting);
    }

    if ($select->can_read($timeout)) {
        while ($select->can_read(0)) {
            $peerport = $socket->recv($data,1500,0);
            route_ipmiresponse($peerport,unpack("C*",$data));
        }
    }
    return scalar (keys %sessions_waiting);
}

sub timedout {
    my $self = shift;
    $self->{timeout} = $self->{timeout}+1;
    if ($self->{timeout} > 4) { #giveup, really
        $self->{timeout}=2;
        my $rsp={};
        $rsp->{error} = "timeout";
        $self->{ipmicallback}->($rsp,$self->{ipmicallback_args});
        return;
    }
    $self->sendpayload(%{$self->{pendingargs}});
}
sub route_ipmiresponse {
    my $sockaddr=shift;
    my @rsp = @_;
    unless (
        $rsp[0] == 0x6 and
        $rsp[2] == 0xff and
        $rsp[3] == 0x07) {
        return; #ignore non-ipmi packets
    }
    my $host;
    my $port;
    #($port,$host) = sockaddr_in6($sockaddr);
    #$host = inet_ntoa($host);
    if ($doipv6) {
	    ($host,$port) = getnameinfo($sockaddr,$Socket6::NI_NUMERICHOST);
    } else {
	($port,$host) = sockaddr_in($sockaddr);
	$host = inet_ntoa($host);
    }
    if ($host =~ /::ffff:\d+\.\d+\.+\d+\.\d+/) {
	$host =~ s/::ffff://;
    }
    if ($bmc_handlers{$host}) {
        $pendingpackets-=1;
        $bmc_handlers{$host}->handle_ipmi_packet(@rsp);
    }
}

sub handle_ipmi_packet {
    #return zero if we like the response
    my $self = shift;
    my @rsp = @_;
    if ($rsp[4] == 0 or $rsp[4] == 2) { #IPMI 1.5 (check 0 assumption...)
        my $remsequencenumber=$rsp[5]+$rsp[6]>>8+$rsp[7]>>16+$rsp[8]>>24;
        if ($self->{remotesequencenumber} and $remsequencenumber < $self->{remotesequencenumber} ) {
            return 5; #ignore malformed sequence number
        }
        $self->{remotesequencenumber}=$remsequencenumber;
        $self->{remotesequencebytes} = [@rsp[5..8]];
        if ($rsp[4] != $self->{authtype}) {
            return 2; # not thinking about packets that do not match our preferred auth type
        }
        unless ($rsp[9] == $self->{sessionid}->[0] and 
                $rsp[10] == $self->{sessionid}->[1] and
                $rsp[11] == $self->{sessionid}->[2] and
                $rsp[12] == $self->{sessionid}->[3]) {
            return 1; #this response does not match our current session id, ignore it
        }
        my @authcode=();
        if ($rsp[4] == 2) {
            @authcode = splice @rsp,13,16;
        }
        my @payload = splice (@rsp,14,$rsp[13]);
        if (@authcode) { #authcode is longer than 0, check it
            $self->{checkremotecode}=1;
            my @expectedauthcode = $self->ipmi15authcode(@payload);
            $self->{checkremotecode}=0;
            foreach (0..15) {
                if ($expectedauthcode[$_] != $authcode[$_]) {
                    return 3; #invalid authcode
                }
            }
        }
        return $self->parse_ipmi_payload(@payload);
    } elsif ($rsp[4] == 6) { #IPMI 2.0
        if (($rsp[5]& 0b00111111) == 0x11) {
            return $self->got_rmcp_response(splice @rsp,16); #the function always leaves ourselves waiting, no need to deregister
        } elsif (($rsp[5]& 0b00111111) == 0x13) {
            return $self->got_rakp2(splice @rsp,16); #same as above
        } elsif (($rsp[5]& 0b00111111) == 0x15) {
            return $self->got_rakp4(splice @rsp,16); #same as above
        } elsif (($rsp[5]& 0b00111111) == 0x0) { #ipmi payload, sophisticated logic to follow
            my $encrypted;
            if ($rsp[5]&0b10000000) {
                $encrypted=1;
            }
            unless ($rsp[5]&0b01000000) {
                return 3; #we refuse to examine unauthenticated packets in this context
            }
            splice (@rsp,0,4); #ditch the rmcp header
            my @authcode = splice(@rsp,-12);#strip away authcode and remember it
            my @expectedcode = unpack("C*",hmac_sha1(pack("C*",@rsp),$self->{k1}));
            splice (@expectedcode,12);
            foreach (@expectedcode) {
                unless ($_ == shift @authcode) {
                   return 3; #authcode bad, pretend it never existed
                }
            }
            unless ($rsp[2] == 0x15 and 
                    $rsp[3] == 0x58 and
                    $rsp[4] == 0x25 and
                    $rsp[5] == 0x7a) {
                return 1; #this response does not match our current session id, ignore it
            }
            my $remsequencenumber=$rsp[6]+$rsp[7]>>8+$rsp[8]>>16+$rsp[9]>>24;
            if ($self->{remotesequencenumber} and $remsequencenumber < $self->{remotesequencenumber} ) {
                return 5; #ignore malformed sequence number
            }
            $self->{remotesequencenumber}=$remsequencenumber;
            my $psize = $rsp[10]+($rsp[11]<<8);
            my @payload = splice(@rsp,12,$psize);
            if ($encrypted) {
                my $iv = pack("C*",splice @payload,0,16);
                my $cipher = Crypt::CBC->new(-literal_key => 1,-key=>$self->{aeskey},-cipher=>"Crypt::Rijndael",-header=>"none",-iv=>$iv,-keysize=>16,-blocksize=>16,-padding=>\&cbc_pad);
                my $crypted = pack("C*",@payload);
                @payload = unpack("C*",$cipher->decrypt($crypted));
            }
            return $self->parse_ipmi_payload(@payload);
        } else {
            return 6; #unsupported payload
        }
    } else {
        return 7; #unsupported ASF traffic
    }
}
sub cbc_pad {
    my $block = shift;
    my $size = shift;
    my $mode = shift;
    if ($mode eq 'e') {
        my $neededpad=$size-length($block)%$size;
        $neededpad -= 1;
        my @pad=unpack("C*",$block);
        foreach (1..$neededpad) {
            push @pad,$_;
        }
        push @pad,$neededpad;
        return pack("C*",@pad);
    } elsif ($mode eq 'd') {
        my @block = unpack("C*",$block);
        my $count = pop @block;
	unless ($count) {
        	return pack("C*",@block);
	}
        splice @block,0-$count;
        return pack("C*",@block);
    }
}

sub got_rmcp_response {
    my $self = shift;
    my @data = @_;
    my $byte = shift @data;
    unless ($self->{sessionestablishmentcontext} eq 'opensession') {
        return 9; #now's not the time for this response, ignore it
    }
    unless ($byte == 0x1f) {
        return 9;
    }
    $byte = shift @data;
    unless ($byte == 0x00) {
        $self->{onlogon}->("ERROR: $byte code on opening RMCP+ session",$self->{onlogon_args}); #TODO: errors
        return 9;
    }
    $byte = shift @data;
    unless ($byte >= 4) {
        $self->{onlogon}->("ERROR: Cannot acquire sufficient privilege",$self->{onlogon_args});
        return 9;
    }
    splice @data,0,5;
    $self->{pendingsessionid} = [splice @data,0,4];
    $self->{sessionestablishmentcontext} = 'rakp2';
    $self->send_rakp1();
    return 0;
}

sub send_rakp3 {
    my $self = shift;
    my @payload = (0x1f,0,0,0,@{$self->{pendingsessionid}});
    my @user = unpack("C*",$self->{userid});
    push @payload,unpack("C*",hmac_sha1(pack("C*",@{$self->{remoterandomnumber}},@{$self->{sidm}},4,scalar @user,@user),$self->{password}));
    $self->sendpayload(payload=>\@payload,type=>$payload_types{'rakp3'});
}

sub send_rakp1 {
    my $self = shift;
    my @payload = (0x1f,0,0,0,@{$self->{pendingsessionid}});
    $self->{randomnumber}=[];
    foreach (1..16) {
        my $randomnumber = int(rand(255));
        push @{$self->{randomnumber}},$randomnumber;
    }
    push @payload, @{$self->{randomnumber}};
    push @payload,(4,0,0); # request admin
    my @user = unpack("C*",$self->{userid});
    push @payload,scalar @user;
    push @payload,@user;
    $self->sendpayload(payload=>\@payload,type=>$payload_types{'rakp1'});
}

sub got_rakp4 {
    my $self = shift;
    my @data = @_;
    my $byte = shift @data;
    unless ($self->{sessionestablishmentcontext} eq 'rakp4') {
        return 9; #now's not the time for this response, ignore it
    }
    unless ($byte == 0x1f) {
        return 9;
    }
    $byte = shift @data;
    unless ($byte == 0x00) {
        $self->{onlogon}->("ERROR: $byte code on opening RMCP+ session",$self->{onlogon_args}); #TODO: errors
        return 9;
    }
    splice @data,0,6; #discard reserved bytes and session id
    my @expectauthcode = unpack("C*",hmac_sha1(pack("C*",@{$self->{randomnumber}},@{$self->{pendingsessionid}},@{$self->{remoteguid}}),$self->{sik}));
    foreach  (@expectauthcode[0..11]) {
        unless ($_ == (shift @data)) {
            $self->{onlogon}->("ERROR: failure in final rakp exchange message",$self->{onlogon_args});
            return 9;
        }
    }
    $self->{sessionid} = $self->{pendingsessionid};
    $self->{integrityalgo}='sha1';
    if ($aessupport) {
        $self->{confalgo} = 'aes';
    }
    $self->{sequencenumber}=1;
    $self->{sequencenumberbytes}=[1,0,0,0];
    $self->{sessionestablishmentcontext} = 'done'; #will move on to relying upon session sequence number
    $self->set_admin_level();
    return 0;
}


sub got_rakp2 {
    my $self=shift;
    my @data = @_;
    my $byte = shift @data;
    unless ($self->{sessionestablishmentcontext} eq 'rakp2') {
        return 9; #now's not the time for this response, ignore it
    }
    unless ($byte == 0x1f) {
        return 9;
    }
    $byte = shift @data;
    unless ($byte == 0x00) {
        $self->{onlogon}->("ERROR: $byte code on opening RMCP+ session",$self->{onlogon_args}); #TODO: errors
        return 9;
    }
    splice @data,0,6; # throw away reserved bytes, and session id, might need to check
    $self->{remoterandomnumber} = [];
    foreach (1..16) {
        push @{$self->{remoterandomnumber}},(shift @data);
    }
    $self->{remoteguid} = [];
    foreach (1..16) {
        push @{$self->{remoteguid}},(shift @data);
    }
    #Data now represents authcode.. sha1 only..
    my @user = unpack("C*",$self->{userid});
    my $ulength = scalar @user;
    my $hmacdata = pack("C*",(0x15,0x58,0x25,0x7a,@{$self->{pendingsessionid}},@{$self->{randomnumber}},@{$self->{remoterandomnumber}},@{$self->{remoteguid}},4,$ulength,@user));
    my @expectedhash = (unpack("C*",hmac_sha1($hmacdata,$self->{password})));
    foreach (0..(scalar(@expectedhash)-1)) {
        if ($expectedhash[$_] != $data[$_]) {
            $self->{onlogon}->("ERROR: Incorrect password provided",$self->{onlogon_args});
            return 9;
        }
    }
    $self->{sik} = hmac_sha1(pack("C*",@{$self->{randomnumber}},@{$self->{remoterandomnumber}},4,$ulength,@user),$self->{password});
    $self->{k1} = hmac_sha1(pack("C*",1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1),$self->{sik});
    if ($aessupport) {
        $self->{k2} = hmac_sha1(pack("C*",2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2),$self->{sik});
        my @aeskey = unpack("C*",$self->{k2});
        $self->{aeskey} = pack("C*",(splice @aeskey,0,16));
    }
    $self->{sessionestablishmentcontext} = 'rakp4';
    $self->send_rakp3();
    return 0;
}

sub parse_ipmi_payload {
    my $self=shift;
    my @payload = @_;
    #for now, just trash the headers, this has been validated to death anyway
    #except seqlun, that one is important
    if ($payload[4] != ($self->{seqlun} ? $self->{seqlun}-4 : 252)) {
        print "Successfully didn't get confused by stale response ".$payload[4]." and ".($self->{seqlun}-4)."\n";
        hexdump(@payload);
        return 1; #response mismatch
    }
    delete $sessions_waiting{$self}; #deregister self as satisfied, callback will reregister if appropriate
    splice @payload,0,5; #remove rsaddr/netfs/lun/checksum/rq/seq/lun
    pop @payload; #remove checksum
    my $rsp;
    $rsp->{cmd} = shift @payload;
    $rsp->{code} = shift @payload;
    $rsp->{data} = \@payload;
    $self->{ipmicallback}->($rsp,$self->{ipmicallback_args});
    return 0;
}

sub ipmi15authcode {
    my $self = shift;
    #per table 22-22 'authcode algorithms'
    my @data = @_;
    my @password;
    my @code;
    if ($self->{passbytes}) {
        @password = @{$self->{passbytes}};
    } else {
        @password =  unpack("C*",$self->{password});
        for (my $i=scalar @password;$i<16;$i++) {
            $password[$i]=0;
        }
        $self->{passbytes} = \@password;
    }
    my @sequencebytes = @{$self->{sequencenumberbytes}};
    if ($self->{checkremotecode}) {
        @sequencebytes = @{$self->{remotesequencebytes}};
    }
    if ($self->{authtype} == 0) {
        return ();
    } elsif ($self->{authtype} == 2) { 
        return unpack("C*",md5(pack("C*",@password,@{$self->{sessionid}},@data,@sequencebytes,@password))); #ignoring single-session channels
    }
    #Not supporting plaintext passwords, that would be asinine
}

#this function accepts a generic ipmi command and applies current session data and handles the 1.5<->2.0 differences
sub sendpayload {
#implementation used section 13.6, examle ipmi over lan packet
    my $self = shift;
    my %args = @_;
    my @msg = (0x6,0x0,0xff,0x07); #RMCP header is constant in IPMI
    my $type = $args{type} & 0b00111111;
    $sessions_waiting{$self}={};
    $sessions_waiting{$self}->{timeout}=time()+$self->{timeout};
    $sessions_waiting{$self}->{ipmisession}=$self;
    my @payload = @{$args{payload}};
    $self->{pendingargs} = \%args;
    push @msg,$self->{'authtype'}; # add authtype byte (will support 0 only for session establishment, 2 for ipmi 1.5, 6 for ipmi2
    if ($self->{'ipmiversion'} eq '2.0') { #TODO: revisit this to see if assembly makes sense
        push @msg, $args{type};
        if ($type == 2) {
            push @msg,@{$self->{'iana'}},0;
            push @msg,@{$self->{'oem_payload_id'}};
        }
        push @msg,@{$self->{sessionid}};
    }
    push @msg,@{$self->{sequencenumberbytes}};
    if ($self->{'ipmiversion'} eq '1.5') { #ipmi 2.0 for some reason swapped session id and seq number location
       push @msg,@{$self->{sessionid}};
       unless ($self->{authtype} == 0) {
           push @msg,$self->ipmi15authcode(@payload);
       }
       push @msg,scalar(@payload);
       push @msg,@payload;
       #TODO: sweat a pad or not? spec isn't crystal clear on the 'legacy pad' and it sounds like it is just for some old crappy nics that have no business in a good server
    } elsif ($self->{'ipmiversion'} eq '2.0') {
#TODO:
            my $size = scalar(@payload);
            if ($self->{confalgo}) {
                my $pad = ($size+1)%16;
                if ($pad) { $pad = 16-$pad; }
                my $newsize =$size+$pad+17;
                push @msg,($newsize&0xff,$newsize>>8);
                my @iv;
                foreach (1..16) { #generate a new iv for outbound packet
                    my $num = int(rand(255));
                    push @msg,$num;
                    push @iv, $num;
                }
                my $cipher = Crypt::CBC->new(-literal_key => 1,-key=>$self->{aeskey},-cipher=>"Rijndael",-header=>"none",-iv=>pack("C*",@iv),-keysize=>16,-padding=>\&cbc_pad);
                push @msg,(unpack("C*",$cipher->encrypt(pack("C*",@payload))));
            } else {
                push @msg,($size&0xff,$size>>8);
                push @msg,@payload;
            }
            if ($self->{integrityalgo}) {
                my @integdata = @msg[4..(scalar @msg)-1];
                my $neededpad=((scalar @integdata)+2)%4;
                if ($neededpad) { $neededpad = 4-$neededpad; }
                for (my $i=0;$i<$neededpad;$i++) {
                    push @integdata,0xff;
                    push @msg,0xff;
                }
                push @msg,$neededpad;
                push @integdata,$neededpad;
                push @msg,7;
                push @integdata,7;
                my $intdata = pack("C*",@integdata);
                my @acode = unpack("C*",hmac_sha1($intdata,$self->{k1}));
                push @msg,splice @acode,0,12;
            #push integrity pad
            #push @msg,0x7; #reserved byte in 2.0
            #push integrity data
            }
    }
    while ($pendingpackets > $maxpending) { #if we hit our ceiling, wait until a slot frees up
        $self->waitforrsp();
    }
    $socket->send(pack("C*",@msg),0,$self->{peeraddr});
    $pendingpackets+=1;
    if ($self->{sequencenumber}) { #if using non-zero, increment, otherwise..
        $self->{sequencenumber} += 1;
        $self->{sequencenumberbytes} =  [$self->{sequencenumber}&0xff,($self->{sequencenumber}>>8)&0xff,($self->{sequencenumber}>>16)&0xff,($self->{sequencenumber}>>24)&0xff];
    }
}

1;
