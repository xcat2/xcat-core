#!/usr/bin/env perl
# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use strict;
use warnings;
use warnings;

package Confluent::Client;

use Confluent::TLV;
use DB_File;
use IO::Socket::SSL;
use IO::Socket::UNIX;
use MIME::Base64;
use Net::SSLeay;

sub get_fingerprint {
    my $pem = Net::SSLeay::PEM_get_string_X509(shift);
    $pem =~ s/-----BEGIN CERTIFICATE-----//;
    $pem =~ s/-----END CERTIFICATE-----//;
    return 'sha512$' . sha512_hex(decode_base64($pem));
}

sub parse_nettarget {
    my $target = shift;
    if ($target =~ /^\[(.*)\]:(.*)/) {
        return $1, $2;
    } elsif ($target =~ /^\[(.*)\]$/) {
        return $1, 13001;
    } elsif ($target =~ /^(.*):(.*)$/) {
        return $1, $2;
    } else {
        return $target, 13001;
    }
}

sub _verify {
    my $self = shift;
    my $peername = shift;
    my $addfingerprint = shift;
    my $coreverified = shift;
    if ($coreverified) {
        return $coreverified;
    }
    my %knownhosts;
    tie %knownhosts, 'DB_File', glob("~/.confluent/knownhosts");
    my $fingerprint = get_fingerprint($_[3]);
    if ($addfingerprint) {
        $knownhosts{$peername} = $addfingerprint;
    }
    if (not $knownhosts{$peername}) {
        die "UKNNOWN_FINGERPRINT: fingerprint=>$fingerprint"
    }
    if ($fingerprint ne $knownhosts{$peername}) {
        die "CONFLICT_FINGERPRINT: fingerprint=>$fingerprint";
    }
    return 1;
}

sub ssl_connect {
    my $self = shift;
    my ($peer, $port) = parse_nettarget(shift);
    my %args = @_;
    my $addfingerprint = undef;
    if ($args{fingerprint}) {
        $addfingerprint = $args{fingerprint};
    }
    # TODO: support typical X509 style when CA present
    my %sslargs = (
        PeerAddr => $peer,
        PeerPort => $port,
        SSL_verify_mode => SSL_VERIFY_PEER,
        SSL_verify_callback =>
            sub { $self->_verify($port."@".$peer, $addfingerprint, @_); },
        SSL_verifycn_scheme => 'none',
    );
    if (1) { # TODO: check for ca location
        # we would do 'undef'.  However, older IO::Socket::SSL doesn't do
        # for now, go ahead and tell it to check in a futile manner for
        # certificates before failing into our callback to do knownhosts
        # style
        $sslargs{SSL_ca_path} = '/';
    } else {
    }
    $self->{handle} = IO::Socket::SSL->new(%sslargs);
    unless ($self->{handle}) {
        die "Unable to reach target, $SSL_ERROR/$!";
    }
}

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    bless($self, $class);
    my $serverlocation = shift;
    my %args = @_;
    if (not $serverlocation) {
        $serverlocation = "/var/run/confluent/api.sock";
    }
    if (-S $serverlocation) {
        $self->{handle} = IO::Socket::UNIX->new($serverlocation);
    } else {  # assume a remote network connection
        $self->{handle} = $self->ssl_connect($serverlocation, @_);
    }
    unless ($self->{handle}) {
        die "General failure connecting $!";
    }
    $self->{server} = Confluent::TLV->new($self->{handle});
    my $banner = $self->{server}->recv();
    my $authdata = $self->{server}->recv();
    $self->{authenticated} = 0;
    if ($authdata->{authpassed}) {
        $self->{authenticated} = 1;
    }
    if ($args{username} and not $self->{authenticated}) {
        $self->authenticate(%args);
    }
    return $self;
}

sub authenticate {
    my $self = shift;
    my %args = @_;
    $self->{server}->send({username=>$args{username},
                           passphrase=>$args{passphrase}});

    my $authdata = $self->{server}->recv();
    if ($authdata->{authpassed}) {
        $self->{authenticated} = 1;
    }
}

sub create {
    my $self = shift;
    my $path = shift;
    return $self->send_request(operation=>'create', path=>$path, @_);
}

sub update {
    my $self = shift;
    my $path = shift;
    return $self->send_request(operation=>'update', path=>$path, @_);
}

sub read {
    my $self = shift;
    my $path = shift;
    my %args = @_;
    return $self->send_request(operation=>'retrieve', path=>$path);
}

sub delete {
    my $self = shift;
    my $path = shift;
    my %args = @_;
    return $self->send_request(operation=>'delete', path=>$path);
}

sub send_request {
    my $self = shift;
    if (not $self->{authenticated}) {
        die "not yet authenticated";
    }
    if ($self->{pending}) {
        die "Cannot submit multiple requests to same object concurrently";
    }
    $self->{pending} = 1;
    my %args = @_;
    my %payload = (
        operation => $args{operation},
        path => $args{path},
    );
    if ($args{parameters}) {
        $payload{parameters} = $args{parameters};
    }
    $self->{server}->send(\%payload);
}

sub next_result {
    my $self = shift;
    unless ($self->{pending}) {
        return undef;
    }
    my $result = $self->{server}->recv();
    if (exists $result->{_requestdone}) {
        $self->{pending} = 0;
    }
    return $result;
}

1;
