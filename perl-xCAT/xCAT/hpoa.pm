# 
# © Copyright 2009 Hewlett-Packard Development Company, L.P.
# EPL license http://www.eclipse.org/legal/epl-v10.html
#

## API for talking to HP Onboard Administrator

## NOTE:
## All parameters are passed by name!
## For example:
## 	hpoa->new(oaAddress => '16.129.49.209');

package xCAT::hpoa;

use strict;

use SOAP::Lite;
use vars qw(@ISA);
@ISA = qw(SOAP::Lite);

# Constructor
# Input: oaAddress, the IP address of the OA
# Output: SOAP::SOM object (SOAP response)
sub new {
  my $class = shift;
  return $class if ref $class;

  my $self = $class->SUPER::new();

  my %args = @_;

  die "oaAddress is a required parameter"
    unless defined $args{oaAddress};

  # Some info we'll need
  $self->{HPOA_HOST} 		= $args{oaAddress}; # OA IP address
  $self->{HPOA_KEY} 		= undef; # oaSessionKey returned by userLogIn
  $self->{HPOA_SECURITY_XML} 	= undef; # key placed in proper XML
  $self->{HPOA_SECURITY_HEADER} = undef; # XML translated to SOAP::Header obj

  bless($self, $class);

  # We contact the OA via this URL:
  my $proxy = "https://". $self->{HPOA_HOST} . ":443/hpoa";

  # One of the cool things about SOAP::Lite is that almost every
  # method returns $self.  This allows you to string together
  # as many calls as you need, like this:
  $self
    # keep the XML formatted for human readability, in case
    # we ever have to look at it (unlikely)
    -> readable(1)

    # Need to tell SOAP about some namespaces.  I don't know if they
    # are all necessary or not, but I got them from the hpoa.wsdl
    -> ns("http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd", "wsu")
    -> ns('http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd', "wsse")
    -> ns('http://www.w3.org/2001/XMLSchema-instance', 'xsi')
    -> ns('http://www.w3.org/2003/05/soap-encoding', 'SOAP-ENC')
    -> ns('http://www.w3.org/2003/05/soap-envelope', 'SOAP-ENV')
    -> ns('http://www.w3.org/2001/XMLSchema', 'xsd')
    -> default_ns("hpoa.xsd", "hpoa")

    # Inform SOAP of the OA URL
    -> proxy($proxy);

  return $self;
}

# Method: call
# Input: method and a hash of method's input params (see below)
# Output: SOAP::SOM object (SOAP response)
#
# All methods in the OA API end up getting called by this routine,
# even though the user invokes them directly using the method name.
# For example, code that looks like this:
# 	$hpoa->userLogIn(username=>$name, password=>$pass)
# results in this call:
#	$hpoa->call('userLogIn', username=>$name, password=>$pass)
sub call {
  my ($self, $method, %args) = @_;

  #
  # Each item of %args is of the form:
  #    ($name => $value).
  #
  # $value is usually a scalar and SOAP::Lite infers a type.
  #
  # If the value needs to be explicitly typed, the $value should be a
  # reference to an array of the form:
  #    [ $scalar, $type ]
  # This should work for any parameter that you want to explicitly
  # type, but for some reason the OA was not having any of it the
  # last time I tried.
  #
  # If the method calls for an array of values, the $value should be
  # a reference to an array of the form:
  #    [ $itemName, $itemArrayRef, $itemType ]
  #
  # If the method calls for more complicated structure, the $value
  # should be a reference to a hash of the form:
  #    { name1 => value1, name2 => value2 ... }
  # The values can themselves be scalars, array refs or hash refs,
  # which will themselves be processed recursively.
  #

  # Put the params in a form SOAP likes.
  my @soapargs = ();
  while (my ($k, $v) = each %args) {
    push @soapargs, $self->process_args($k, $v);
  }
  # This is required if there are no params, otherwise SOAP::Lite
  # makes an XML construct that the OA doesn't like.
  @soapargs = SOAP::Data->type('xml'=> undef)
    unless @soapargs;

  # Add the security header if it's not the login method.
  # I'm hoping that the header will be ignored by the few methods
  # that don't require security.
  push (@soapargs, $self->{HPOA_SECURITY_HEADER})
    unless ($method eq 'userLogIn') || !defined $self->{HPOA_SECURITY_HEADER};

  # Make sure we're using the correct version of SOAP, but
  # don't mess up packages that use a different version.
  my $version = hpoa->soapversion();
  hpoa->soapversion('1.2');

  # Call the method and put the response in $r
  my $r = $self->SUPER::call($method, @soapargs);

  # Reset the SOAP version
  hpoa->soapversion($version);

  # If this was the login method and it was successful, then extract
  # the session key and remember it for subsequent calls.
  if ($method eq 'userLogIn' && !$r->fault) {

    my $key = $r->result()->{oaSessionKey};

    # Got this XML code from the HP Insight Onboard Administrator SOAP
    # Interface Guide 0.9.7
    my $xml = '
<wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" SOAP-ENV:mustUnderstand="true">
  <hpoa:HpOaSessionKeyToken xmlns:hpoa="hpoa.xsd">
     <hpoa:oaSessionKey>'
       . $key .
    '</hpoa:oaSessionKey>
  </hpoa:HpOaSessionKeyToken>
</wsse:Security>';

    $self->{HPOA_KEY} 		  = $key;
    $self->{HPOA_SECURITY_XML} 	  = $xml;
    $self->{HPOA_SECURITY_HEADER} = SOAP::Header->type('xml' => $xml);
  }

  # Return the response
  return $r;
}

## Create the correct SOAP::Data structure for the given args
## $n is the argument name
## $v is the value and can be of the following 4 forms:
##   $scalar
##	- A scalar value.  No further processing takes place.
##	  Produces: <name>value</name>
##   [ $scalar, $type ]
##	- An array ref containing a scalar value and type.  No further
##	  will take place.
##	  Produces: <name type=aType>value</name>
##   [ $itemName, $aref, $type ]
##	- An array ref containing the name for the elements, the elements
##	  themselves in an array ref, and the type for the elements.  The
##	  elements themselves can be processed.
##	  Produces: <name>
##		      <item type=aType>value1</item>
##		      <item type=aType>value2</item>
##		    </name>
##   { $n1 => $v1, $n2 => $v2 ... }
##	- A hash ref containing name value pairs that can themselves
##	  be processed.
##	  Produces: <name>
##		      <n1>v1</n1>
##		      <n2>v2</n2>
##	 	    </name>

sub process_args {
  my ($self, $n, $v, $t) = @_;
  print "process args: $n => $v\n"					if 0;

  if (!ref $v) {		# untyped scalar
    print "\nUNTYPED SCALAR: $n => $v\n"				if 0;
    return SOAP::Data->new(name => $n, value => $v, type => '');
  }

  if (ref $v eq 'HASH') {	# structure
    my ($nn, $vv, @ar);
    while (($nn, $vv) = each %$v) {
      print "\nSTRUCTURE $n: $nn => $vv\n"				if 0;
      unshift @ar, $self->process_args($nn, $vv);
    }
    return SOAP::Data->name($n => \SOAP::Data->value(@ar));
  }

  if (ref $v eq 'ARRAY') {

    if (scalar @$v == 2) {	# typed scalar
      my ($value, $type) = @$v;
      print "\nTYPED SCALAR: $n => $value ($type)\n"			if 0;
      return SOAP::Data->new(name => $n, value => $value, type => $type);
    }

    # Else an array of values
    my ($itemName, $aref, $type) = @$v;
    my (@ar, $item);
    foreach $item (@$aref) {
      if (ref $item eq 'HASH') {
	print "\nSUB STRUCTURE $n: $itemName => $item ($type)\n"	if 0;
	unshift @ar, $self->process_args("$itemName", $item);
      } else {
	print "\nARRAY $n: $itemName => $item ($type)\n"		if 0;
	unshift @ar, $self->process_args($itemName, [$item, $type]);
      }
    }
    return SOAP::Data->name($n => \SOAP::Data->value(@ar));
  }

  die "Unexpected input parameter value: $n => $v\n";
}

###
### Special fault info for OAs
###

# The OA uses it's own fault data structures.  The simple
# fault methods provided by SOAP::Lite are usually undef.
# The OA's fault data looks like this:
# {
#   'Detail' => {
#      'faultInfo' => {
#         'operationName' => 'userLogIn',
#         'errorText' => 'The user could not be authenticated.',
#         'errorCode' => '150',
#         'errorType' => 'USER_REQUEST'
#      }
#   },
#   'Reason' => {
#      'Text' => 'User Request Error'
#   },
#   'Code' => {
#      'Value' => 'SOAP-ENV:Sender'
#   }
#}
#
# In your code, you should generally check that $response->fault
# is defined, then print $response->oaErrorMessage.
# If you know the codes, you can act on $response->oaErrorCode
#

# The OA's fault structure
sub SOAP::SOM::oaFaultInfo {
  my ($self, @args) = @_;

  return $self->fault->{Detail}->{faultInfo}
    if (defined $self->fault &&
	defined $self->fault->{Detail} &&
	defined $self->fault->{Detail}->{faultInfo});

  return undef;
}

# The name of the method producing the fault
sub SOAP::SOM::oaOperationName {
  my ($self, @args) = @_;

  my $oafi = $self->oaFaultInfo;

  return $oafi->{operationName}
    if defined $oafi &&
      defined $oafi->{operationName};

  return undef;
}

# Text of the OA fault
sub SOAP::SOM::oaErrorText {
  my ($self, @args) = @_;

  my $oafi = $self->oaFaultInfo;

  return $oafi->{errorText}
    if defined $oafi &&
      defined $oafi->{errorText};

  return undef;
}

# Numeric code of the OA fault
sub SOAP::SOM::oaErrorCode {
  my ($self, @args) = @_;

  my $oafi = $self->oaFaultInfo;

  if (defined $oafi) {

    return $oafi->{errorCode}
      if defined $oafi->{errorCode};

    return $oafi->{internalErrorCode}
      if defined $oafi->{internalErrorCode};
  }

  return undef;
}

# Bay Number of the OA fault
sub SOAP::SOM::oaOperationBayNumber {
  my ($self, @args) = @_;

  my $oafi = $self->oaFaultInfo;

  return $oafi->{operationBayNumber}
    if defined $oafi &&
      defined $oafi->{operationBayNumber};

  return undef;
}

# Sometimes there's extra fault information
# (Haven't seen any yet!)
sub SOAP::SOM::oaExtraFaultData {
  my ($self, @args) = @_;

  my $oafi = $self->oaFaultInfo;

  return $oafi->{extraData}
    if defined $oafi &&
      defined $oafi->{extraData};

  return undef;
}

# Nicely formatted error message for human consumption.
# Tries to use the oaErrorText and oaErrorCode, if defined,
# else uses the reason text.
sub SOAP::SOM::oaErrorMessage {
  my ($self, @args) = @_;

  my $errorText  = $self->oaErrorText;

  # Reason text is either an error message from SOAP (as when
  # the method or argument doesn't exist), or it's a formatted
  # form of the faultInfo->errorType enumeration.
  my $reasonText = $self->fault->{Reason}->{Text};

  return $reasonText
    unless defined $errorText;

  my $operationName = $self->oaOperationName;
  my $operationBay  = $self->oaOperationBayNumber;
  my $errorCode     = $self->oaErrorCode;
  my $extraData     = $self->oaExtraFaultData;

  my $operation = "'$operationName' call";
  $operation .= " on bay $operationBay"
    if $operationBay;

  my $completeText =
    "$reasonText $errorCode during $operation: $errorText";
  $completeText .= "\n\t$extraData" if $extraData;

  return $completeText;
}

1;
