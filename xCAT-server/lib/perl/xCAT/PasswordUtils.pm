package xCAT::PasswordUtils;
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::Utils;

my $ipmiuser  = "USERID";      # default username to apply if nothing specified
my $ipmipass  = "PASSW0RD";    # default password to apply if nothing specified
my $bladeuser = "USERID";      # default username to apply if nothing specified
my $bladepass = "PASSW0RD";    # default password to apply if nothing specified
my %CRYPT_METHOD = ('md5' => '$1$', 'sha256' => '$5$', 'sha512' => '$6$');


# Picks the IPMI authentication to use with or deploy to a BMC
# mandatory arguments:
# noderange: a list reference to nodes (e..g. ["node1","node2"])
# optional parameters:
# ipmihash: a prefetched hash reference of relevant ipmi table data
# mphash: a prefetched hash of relevent mp table
# RETURNS:
# A hash reference with usernames and passwords, e.g.: { 'node1' => { 'username' => 'admin', 'password' => 'reallysecure' }, 'node2' => { 'username' => 'admin', 'password' => 'reallysecure' } }
sub getIPMIAuth {

    #the algorithm intended is as follows:
    #Should the target have a valid ipmi.username/ipmi.password, that is preferred above all else
    #Otherwise, if it is a blade topology, then synchronize with the management module password parameters in mpa by default
    #if still not defined, but it is a blade topology, then use 'blade' passwd table values
    #if still not defined, use 'ipmi' table values
    #if still not defined, use the defaults hardcoded into this file
    my %args      = @_;
    my $noderange = $args{noderange};
    my $ipmihash  = $args{ipmihash};
    my $mphash    = $args{mphash};
    my $tmp;
    my %authmap;
    unless ($ipmihash) { #in the event that calling code does not pass us a prefetched set of values, pull it ourselves
        my $ipmitab = xCAT::Table->new('ipmi', -create => 0);
        if ($ipmitab) { $ipmihash = $ipmitab->getNodesAttribs($noderange, [ 'username', 'password' ]); }
    }
    unless ($mphash) {
        my $mptab = xCAT::Table->new('mp', -create => 0);
        if ($mptab) { $mphash = $mptab->getNodesAttribs($noderange, [ 'mpa', 'id' ]); }
    }
    my $passtab = xCAT::Table->new('passwd');
    if ($passtab) {
        ($tmp) = $passtab->getAttribs({ 'key' => 'ipmi' }, 'username', 'password');
        if (defined($tmp)) {
            $ipmiuser = $tmp->{username};
            $ipmipass = $tmp->{password};
            if ($ipmiuser or $ipmipass) {
                unless ($ipmiuser) {
                    $ipmiuser = '';
                }
                unless ($ipmipass) {
                    $ipmipass = '';
                }
            }
        }
        ($tmp) = $passtab->getAttribs({ 'key' => 'blade' }, 'username', 'password');
        if (defined($tmp)) {
            $bladeuser = $tmp->{username};
            $bladepass = $tmp->{password};
            if ($bladeuser or $bladepass) {
                unless ($bladeuser) {
                    $bladeuser = '';
                }
                unless ($bladepass) {
                    $bladepass = '';
                }
            }
        }
    }
    my $mpatab;
    if ($mphash) { $mpatab = xCAT::Table->new('mpa', -create => 0); }
    my %mpaauth;
    foreach $node (@$noderange) {
        $authmap{$node}->{username} = $ipmiuser;
        $authmap{$node}->{password} = $ipmipass;
        if ($mphash and ref $mphash->{$node} and $mphash->{$node}->[0]->{mpa}) { #this appears to be a Flex or similar config, tend to use blade credentials
            if ($bladeuser) { $authmap{$node}->{username} = $bladeuser; $authmap{$node}->{cliusername} = $bladeuser; }
            if ($bladepass) { $authmap{$node}->{password} = $bladepass; $authmap{$node}->{clipassword} = $bladepass; }
            my $mpa = $mphash->{$node}->[0]->{mpa};
            if (not $mpaauth{$mpa} and $mpatab) {
                my $mpaent = $mpatab->getNodeAttribs($mpa, [qw/username password/], prefetchcache => 1); #TODO: this might make more sense to do as one retrieval, oh well
                if (ref $mpaent and ($mpaent->{username} or $mpaent->{password})) {
                    if (!exists($mpaent->{username})) {
                        $mpaauth{$mpa}->{username} = '';
                    } else {
                        $mpaauth{$mpa}->{username} = $mpaent->{username};
                    }
                    if (!exists($mpaent->{password})) {
                        $mpaauth{$mpa}->{password} = '';
                    } else {
                        $mpaauth{$mpa}->{password} = $mpaent->{password};
                    }
                }
                $mpaauth{$mpa}->{checked} = 1; #remember we already looked this up, to save lookup time even if search was fruitless
            }
            if ($mpaauth{$mpa}->{username}) { $authmap{$node}->{username} = $mpaauth{$mpa}->{username}; $authmap{$node}->{cliusername} = $mpaauth{$mpa}->{username}; }
            if ($mpaauth{$mpa}->{password}) { $authmap{$node}->{password} = $mpaauth{$mpa}->{password}; $authmap{$node}->{clipassword} = $mpaauth{$mpa}->{password} }
        }
        unless (ref $ipmihash and ref $ipmihash->{$node}) {
            next;
        }
        if ($ipmihash->{$node}->[0]->{username} or $ipmihash->{$node}->[0]->{password}) {
            unless ($ipmihash->{$node}->[0]->{username}) {
                $authmap{$node}->{username} = '';
            } else {
                $authmap{$node}->{username} = $ipmihash->{$node}->[0]->{username};
            }
            unless ($ipmihash->{$node}->[0]->{password}) {
                $authmap{$node}->{password} = '';
            } else {
                $authmap{$node}->{password} = $ipmihash->{$node}->[0]->{password};
            }
        }
    }
    return \%authmap;
}

# Encrypt system password based on the values in passwd table
# The values for system root user will be used if query key-pair is not defined
sub crypt_system_password {
    # Just leave these arguments here for the compability reasons in Template.pm
    # which get these values by parsing the template files.
    my ($table, $kp, $fields) = @_;
    if  (!defined($table)) {
        $table = 'passwd';
    }
    if (!defined($kp)) {
        $kp->{'key'} = 'system';
        $kp->{username} = 'root';
        $fields->[0] = 'password';
        $fields->[1] = 'cryptmethod';
    }
    my $tabh = xCAT::Table->new($table);
    unless ($tabh) {
        return undef;
    }
    $data = $tabh->getAttribs($kp, @{$fields});
    if (!defined($data)) {
        xCAT::MsgUtils->message("S",
            "ERROR: Unable to get data from database table $table, key=$key");
        return undef;
    }
    $tabh->close();
    $password = $data->{'password'};
    if (!defined($password)) {
        xCAT::MsgUtils->message("S",
            "ERROR: Unable to get password from database table $table, key=$key");
        return undef;
    }
    if (($password =~ /^\$1\$/) || ($password =~ /^\$5\$/) || ($password =~ /^\$6\$/)) {
        # $password is already hashed
        $result = $password;
    } else {
        $cryptmethod = $data->{'cryptmethod'};
        if (!$cryptmethod) {
            # Use sha256 crypt method by default
            $result = crypt($password, $CRYPT_METHOD{'sha256'} . xCAT::Utils::genpassword(8));
        } elsif( defined($CRYPT_METHOD{$cryptmethod})) {
            $result = crypt($password,
                $CRYPT_METHOD{$cryptmethod} . xCAT::Utils::genpassword(8));
        } else {
            xCAT::MsgUtils->message("S", "Unsupported crypt method $cryptmethod");
            return undef;
        }
    }
    return $result;
}
