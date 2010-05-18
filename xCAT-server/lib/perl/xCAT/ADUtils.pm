# IBM(c) 2010 EPL license http://www.eclipse.org/legal/epl-v10.html

#This module provides simplified methods for adding machine/user accounts to active directory,
#as well as setting passwords for aforementioned accounts.

#there exists direct perl ldap module, but too rare to bank on, going to use ldapmodify from
#system calls
package xCAT::ADUtils;
use strict;
use MIME::Base64;
use Encode;
use xCAT::Utils qw/genpassword runcmd3/;
use IPC::Open3;
use IO::Select;
use Symbol qw/gensym/;


my $machineldiftemplate = 'dn: CN=##NODENAME##,##OU##
changetype: add
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: user
objectClass: computer
cn: ##NODENAME##
distinguishedName: CN=##NODENAME##,##OU##
objectCategory: CN=Computer,CN=Schema,CN=Configuration##REALMDCS##
instanceType: 4
displayName: ##NODENAME##$
name: ##NODENAME##
userAccountControl: 4096
codePage: 0
countryCode: 0
accountExpires: 0
sAMAccountName: ##NODENAME##$
dNSHostName: ##NODENAME####DNSDOMAIN##
servicePrincipalName: host/##NODENAME##
servicePrincipalName: host/##NODENAME####DNSDOMAIN##
servicePrincipalName: nfs/##NODENAME##
servicePrincipalName: nfs/##NODENAME####DNSDOMAIN##

dn: CN=##NODENAME##,##OU##
changetype: modify
replace: unicodePwd
unicodePwd::##B64PASSWORD##';

my $machineldifpasschange = 'dn: CN=##NODENAME##,##OU##
changetype: modify
replace: unicodePwd
unicodePwd::##B64PASSWORD##';

my $useraccounttemplate = 'dn: CN=##FULLNAME##,##OU##
changetype: add
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: user
objectCategory: CN=Person,CN=Schema,CN=Configuration##REALMDCS##
codePage: 0
countryCode: 0
distinguishedName: CN=##FULLNAME##,##OU##
cn: ##FULLNAME##
sn: ##LASTNAME##
givenName: ##FIRSTNAME##
displayName: ##FULLNAME##
name: ##FULLNAME##
instanceType: 4
userAccountControl: 514
accountExpires: 0
uidNumber: ##UID##
gidNumber: ##GID##
sAMAccountName: ##USERNAME##
userPrincipalName: ##USERNAME##@##DNSDOMAIN##
mail: ##USERNAME##@##DNSDOMAIN##
homeDirectory: ##USERSMBHOME##
homeDrive: ##USERSMBDRIVELETTER##
unixHomeDirectory: ##USERHOME##
loginShell: ##USERSHELL##

dn: CN=##FULLNAME##,##OU##
changetype: modify
replace: unicodePwd
unicodePwd::##B64PASSWORD##

dn: CN=##FULLNAME##,##OU##
changetype: modify
replace: userAccountControl
userAccountControl: 512';


sub del_host_account {
    my %args = @_;
    my $directoryserver = $args{directoryserver};
    my $dnsdomain = $args{dnsdomain};
    my $account = $args{account};
    unless ($dnsdomain and $directoryserver and $account) {
        die "Invalid arguments $dnsdomain and $directoryserver and $account";
    }
    my $domain_components = $dnsdomain;
    $domain_components =~ s/^\.//;
    $domain_components =~ s/\./,dc=/g;
    $domain_components =~ s/^/dc=/;
    my @searchcmd = qw/ldapsearch  -H /;
    push @searchcmd,"ldaps://$directoryserver","-b",$domain_components;
    push @searchcmd,"(&(&(&(objectClass=user)(objectClass=computer))(!(isCriticalSystemObject=TRUE)))(name=$account))","dn";
    my $searchout;
    my $searchin;
    my $searcherr = gensym;
    my $search = open3($searchin,$searchout,$searcherr,@searchcmd);
    print $searchout;
    print $searchin;
    my $searchselect = IO::Select->new($searchout,$searcherr);
    my @handles;
    my $failure;
    my $dn;
    while (@handles = $searchselect->can_read()) {
        foreach (@handles) {
            my $line = <$_>;
            print $line;
            if (not defined $line) {
                $searchselect->remove($_);
                next;
            }
            print $line;
            if ($_ == $searcherr) {
                if ($line =~ /error/i or $line =~ /problem/i) {
                    return {error=>$line};
                }
            } elsif ($line =~ /^dn: (.*)$/) {
                if ($dn) { die "TODO: identify these cases, let xcat-user know this can happen"; }
                $dn = $1;
            }
        }
    }
    my $ldif = "dn: $dn
changetype: delete";
    my $deletein;
    my $deleteout;
    my $deleteerr = gensym;
    my $deletion = open3($deletein,$deleteout,$deleteerr,'ldapmodify','-H',"ldaps://$directoryserver");
    print $deletein $ldif."\n";
    close($deletein);
    print $ldif;
    my $delselect = IO::Select->new($deleteout,$deleteerr);
    while (@handles = $delselect->can_read()) {
        foreach (@handles) {
            my $line = <$_>;
            print $line;
            if (not defined $line) {
                $delselect->remove($_);
                next;
            }
            if ($_ == $deleteerr) {
                if ($line =~ /error/i or $line =~ /problem/i) {
                    return {error=> $line};
                }
            }
        }
    }
}
sub del_user_account {
    my %args = @_;
    my $directoryserver = $args{directoryserver};
    my $dnsdomain = $args{dnsdomain};
    my $account = $args{account};
    unless ($dnsdomain and $directoryserver and $account) {
        die "Invalid arguments $dnsdomain and $directoryserver and $account";
    }
    my $domain_components = $dnsdomain;
    $domain_components =~ s/^\.//;
    $domain_components =~ s/\./,dc=/g;
    $domain_components =~ s/^/dc=/;
    my @searchcmd = qw/ldapsearch  -H /;
    push @searchcmd,"ldaps://$directoryserver","-b",$domain_components;
    push @searchcmd,"(sAMAccountname=$account)","dn";
    my $searchout;
    my $searchin;
    my $searcherr = gensym;
    my $search = open3($searchin,$searchout,$searcherr,@searchcmd);
    print $searchout;
    print $searchin;
    my $searchselect = IO::Select->new($searchout,$searcherr);
    my @handles;
    my $failure;
    my $dn;
    while (@handles = $searchselect->can_read()) {
        foreach (@handles) {
            my $line = <$_>;
            print $line;
            if (not defined $line) {
                $searchselect->remove($_);
                next;
            }
            print $line;
            if ($_ == $searcherr) {
                if ($line =~ /error/i or $line =~ /problem/i) {
                    return {error=>$line};
                }
            } elsif ($line =~ /^dn: (.*)$/) {
                if ($dn) { die "TODO: identify these cases, let xcat-user know this can happen"; }
                $dn = $1;
            }
        }
    }
    my $ldif = "dn: $dn
changetype: delete";
    my $deletein;
    my $deleteout;
    my $deleteerr = gensym;
    my $deletion = open3($deletein,$deleteout,$deleteerr,'ldapmodify','-H',"ldaps://$directoryserver");
    print $deletein $ldif."\n";
    close($deletein);
    print $ldif;
    my $delselect = IO::Select->new($deleteout,$deleteerr);
    while (@handles = $delselect->can_read()) {
        foreach (@handles) {
            my $line = <$_>;
            print $line;
            if (not defined $line) {
                $delselect->remove($_);
                next;
            }
            if ($_ == $deleteerr) {
                if ($line =~ /error/i or $line =~ /problem/i) {
                    return {error=> $line};
                }
            }
        }
    }
}

sub list_host_accounts { #provide enough data to construct an /etc/passwd looking output
    my %args = @_;
    my $directoryserver = $args{directoryserver};
    my $dnsdomain = $args{dnsdomain};
    unless ($dnsdomain and $directoryserver) {
        die "Invalid arguments";
    }
    my $domain_components = $dnsdomain;
    $domain_components =~ s/^\.//;
    $domain_components =~ s/\./,dc=/g;
    $domain_components =~ s/^/dc=/;
    my @searchcmd = qw/ldapsearch  -H /;
    push @searchcmd,"ldaps://$directoryserver","-b",$domain_components;
    push @searchcmd,qw/(&(&(objectClass=user)(objectClass=computer))(!(isCriticalSystemObject=TRUE))) name operatingSystem operatingSystemServicePack/;
    my $searchout;
    my $searchin;
    my $searcherr = gensym;
    my $search = open3($searchin,$searchout,$searcherr,@searchcmd);
    my $searchselect = IO::Select->new($searchout,$searcherr);
    my @handles;
    my $failure;
    my %currvalues =();
    my %acchash= ();
    while (@handles = $searchselect->can_read()) {
        foreach (@handles) {
            my $line = <$_>;
            if (not defined $line) {
                $searchselect->remove($_);
                next;
            }
            if ($_ == $searcherr) {
                if ($line =~ /error/i or $line =~ /problem/i) {
                    print $line;
                    $failure=1;
                }
            } elsif ($line =~ /^dn: (.*)$/) {
                foreach(keys %currvalues) {
                    $acchash{$currvalues{accountname}}->{$_} = $currvalues{$_};
                }
                %currvalues=();
            } elsif ($line =~ /^name: (.*)$/) {
                $currvalues{accountname} = $1;
            } elsif ($line =~ /^OperatingSystem: (.*)$/) {
                $currvalues{os} = $1;
            } elsif ($line =~ /^OperatingSystemServicePack: (.*)$/) {
                $currvalues{osservicepack} = $1;
            }
        }
    }
    if ($failure) { return undef; }
    foreach(keys %currvalues) {
        $acchash{$currvalues{accountname}}->{$_} = $currvalues{$_};
    }
    return \%acchash;
}
sub list_user_accounts { #provide enough data to construct an /etc/passwd looking output
    my %args = @_;
    my $directoryserver = $args{directoryserver};
    my $dnsdomain = $args{dnsdomain};
    unless ($dnsdomain and $directoryserver) {
        die "Invalid arguments";
    }
    my $domain_components = $dnsdomain;
    $domain_components =~ s/^\.//;
    $domain_components =~ s/\./,dc=/g;
    $domain_components =~ s/^/dc=/;
    my @searchcmd = qw/ldapsearch  -H /;
    push @searchcmd,"ldaps://$directoryserver","-b",$domain_components;
    push @searchcmd,qw/(&(&(objectClass=user)(!(objectClass=computer)))(!(isCriticalSystemObject=TRUE))) sAMAccountName unixHomeDirectory uidNumber gidNumber cn loginShell/;
    my $searchout;
    my $searchin;
    my $searcherr = gensym;
    my $search = open3($searchin,$searchout,$searcherr,@searchcmd);
    my $searchselect = IO::Select->new($searchout,$searcherr);
    my @handles;
    my $failure;
    my %currvalues =();
    my %userhash= ();
    while (@handles = $searchselect->can_read()) {
        foreach (@handles) {
            my $line = <$_>;
            if (not defined $line) {
                $searchselect->remove($_);
                next;
            }
            if ($_ == $searcherr) {
                if ($line =~ /error/i or $line =~ /problem/i) {
                    print $line;
                    $failure=1;
                }
            } elsif ($line =~ /^dn: (.*)$/) {
                foreach(keys %currvalues) {
                    $userhash{$currvalues{accountname}}->{$_} = $currvalues{$_};
                }
                %currvalues=();
            } elsif ($line =~ /^cn: (.*)$/) {
                $currvalues{fullname} = $1;
            } elsif ($line =~ /^sAMAccountName: (.*)$/) {
                $currvalues{accountname} = $1;
            } elsif ($line =~ /^uidNumber: (.*)$/) {
                $currvalues{uid} = $1;
            } elsif ($line =~ /^gidNumber: (.*)$/) {
                $currvalues{gid} = $1;
            } elsif ($line =~ /^unixHomeDirectory: (.*)$/) {
                $currvalues{homedir} = $1;
            } elsif ($line =~ /^loginShell: (.*)$/) {
                $currvalues{shell} = $1;
            }
        }
    }
    if ($failure) { return undef; }
    foreach(keys %currvalues) {
        $userhash{$currvalues{accountname}}->{$_} = $currvalues{$_};
    }
    return \%userhash;
}
sub delete_user_account { #provide enough data to construct an /etc/passwd looking output
    my %args = @_;
    my $directoryserver = $args{directoryserver};
    my $dnsdomain = $args{dnsdomain};
    my $username = $args{username};
    unless ($dnsdomain and $directoryserver and $username) {
        die "Invalid arguments";
    }
}
=cut
  example: add_user_account(username=>'fred',fullname=>'fred the great');
=cut
sub add_user_account {
    my %args = @_;
    my $dnsdomain = $args{dnsdomain};
    unless ($dnsdomain =~ /^\./) {
        $dnsdomain = '.'.$dnsdomain;
    }
    my $directoryserver = $args{directoryserver};
    my $domain_components = $dnsdomain;
    $domain_components =~ s/\./,dc=/g;
    unless ($domain_components =~ /^,dc=/) {
        $domain_components = ",dc=".$domain_components;
    }
    my $ou = $args{ou};
    if ($ou) {
        unless ($ou =~ /$domain_components\z/) {
            $ou .= $domain_components;
        }
    } else {
        $ou = "CN=Users".$domain_components;
    }
    unless ($domain_components and $dnsdomain and $ou and $directoryserver) {
        return {error=>"Unable to determine all required parameters"};
    }
    my $newpassword = $args{password};
    if ($newpassword) {
        $newpassword = '"'.$newpassword.'"';
    } else {
        $newpassword = '"'.genpassword(8).'"';
    }
    Encode::from_to($newpassword,"utf8","utf16le"); #ms uses utf16le, we use utf8
    my $b64password = encode_base64($newpassword);
    my $username = $args{username};
    my $fullname;
    if ($args{fullname}) {
        $fullname = $args{fullname};
    } else {
        $fullname = $username;
    }
    my $firstname;
    if ($args{firstname}) {
        $firstname = $args{firstname};
    } else {
        $firstname = $fullname;
        $firstname =~ s/ .*//; #remove anything after any space
    }
    my $lastname;
    if ($args{lastname}) {
        $firstname = $args{lastname};
    } else {
        $lastname = $fullname;
        $lastname =~ s/.* //; #remove anything before any space
    }
    my $gid;
    my $uid;
    if ($args{gid}) {
        $gid = $args{gid};
    } else {
        $gid = 100; #TODO, something more generic?
    }
    if ($args{uid}) {
        $uid = $args{uid};
    } else {
        my $base = $domain_components;
        $base =~ s/^,//;
        my $parms = find_free_params(directoryserver=>$directoryserver,ou=>$base);
        unless ($parms) {
            return { error => "Unable to auto-detect a valid uid" };
        }
        $uid = $parms->{uidNumber};
    }
    my $shell = $args{shell};
    unless ($shell) { $shell = "/bin/bash"; }
    my $uhome = $args{homedir};
    unless ($uhome) { $uhome = "/home/".$username; }
    my $ldif = $useraccounttemplate;
    if ($args{smbhome} and $args{smbhomeletter}) {
        my $smbhome = $args{smbhome};
        my $smbhomeletter = $args{smbhomeletter};
        $ldif =~ s/##USERSMBHOME##/$smbhome/g;
        $ldif =~ s/##USERSMBDRIVELETTER##/$smbhome/g;
    } else {
        $ldif =~ s/homeDirectory: ##USERSMBHOME##
//g;
        $ldif =~ s/homeDrive: ##USERSMBDRIVELETTER##
//g;
    }
    $ldif =~ s/##FULLNAME##/$fullname/g;
    $ldif =~ s/##USERNAME##/$username/g;
    $ldif =~ s/##FIRSTNAME##/$firstname/g;
    $ldif =~ s/##LASTNAME##/$lastname/g;
    $ldif =~ s/##OU##/$ou/g;
    $ldif =~ s/##DNSDOMAIN##/$dnsdomain/g;
    $ldif =~ s/##REALMDCS##/$domain_components/g;
    $ldif =~ s/##UID##/$uid/g;
    $ldif =~ s/##GID##/$gid/g;
    $ldif =~ s/##USERHOME##/$uhome/g;
    $ldif =~ s/##USERSHELL##/$shell/g;
    $ldif =~ s/##B64PASSWORD##/$b64password/g;
    my $dn = "CN=$fullname,$ou";
    my $retdata = runcmd3(command=>["ldapsearch","-H","ldaps://$directoryserver","-b" ,"$dn"]);
    my $rc = $retdata->{exitcode};
    if ($rc == 0) {
        return {error=>"User already exists"};
    } elsif (not $rc==32) {
        return {error=>"Unknown error $rc:".$retdata->{errors}};
    }
    $retdata = runcmd3(input=>$ldif,command=>["ldapmodify","-H","ldaps://$directoryserver"]); 
    return {password=>$newpassword};
}
=cut
add_host_account
Arguments are in a hash:
    node=>name of machine to add
=cut
sub add_host_account {
    my %args = @_;
    my $nodename = $args{node};
    my $dnsdomain = $args{dnsdomain};
    my $changepassondupe = $args{changepassondupe};
    if (not $dnsdomain and $nodename =~ /\./) { #if no domain provided, guess from nodename
        $dnsdomain = $nodename;
        $dnsdomain =~ s/^[^\.]*//;
    }
    unless ($dnsdomain =~ /^\./) {
        $dnsdomain = '.'.$dnsdomain;
    }
    $nodename =~ s/\..*//; #strip dns domain if part of nodename
    my $domain_components = $dnsdomain;
    $domain_components =~ s/\./,dc=/g;
    unless ($domain_components =~ /^,dc=/) {
        $domain_components = ",dc=".$domain_components;
    }
    my $ou = $args{ou};
    if ($ou) { 
        unless ($ou =~ /$domain_components\z/) {
            $ou .= $domain_components;
        }
    } else {
        $ou = "CN=Computers".$domain_components;
    }
    my $directoryserver = $args{directoryserver};
    unless ($domain_components and $dnsdomain and $ou and $nodename and $directoryserver) {
        return {error=>"Unable to determine all required parameters"};
    }
    my $newpassword = $args{password};
    if ($newpassword) {
        $newpassword = '"'.$newpassword.'"';
    } else {
        $newpassword = '"'.genpassword(8).'a0P"'; #add a little to assure that a fluke doesn't produce a password that won't pass MS filters
    }
    my $nativenewpassword = $newpassword;
    Encode::from_to($newpassword,"utf8","utf16le"); #ms uses utf16le, we use utf8
    my $b64password = encode_base64($newpassword);
    my $ldif;
    my $dn = "CN=$nodename,$ou";
    my $retdata = runcmd3(command=>["ldapsearch","-H","ldaps://$directoryserver","-b","$dn"]); #TODO: for mass add, search once, hit that
    my $rc = $retdata->{exitcode};
    if ($rc == 0) { 
        if ($changepassondupe) {
            $ldif = $machineldifpasschange;
        } else {
            return {error=>"System already exists"};
        }
    } elsif (not $rc==32) {
        return {error=>"Unknown error $rc: ".$retdata->{errors}};
    } else {
        $ldif = $machineldiftemplate;
    }
    $ldif =~ s/##B64PASSWORD##/$b64password/g;
    $ldif =~ s/##OU##/$ou/g;
    $ldif =~ s/##REALMDCS##/$domain_components/g;
    $ldif =~ s/##DNSDOMAIN##/$dnsdomain/g;
    $ldif =~ s/##NODENAME##/$nodename/g;
    $retdata = runcmd3(input=>$ldif,command=>['ldapmodify','-H',"ldaps://$directoryserver"]); 
    substr $nativenewpassword,0,1,'';
    chop($nativenewpassword);
    #if ($retdata->{exitcode} != 0) {
    #}
    return {password=>$nativenewpassword};
}

sub krb_login {
    #TODO: use distinct credential cache
    #TODO: klist -s to see if credentials are good
    my %args = @_;
    my $password = $args{password};
    my $username = $args{username};
    my $realm = $args{realm};
    my $krbin;
    my $krbout;
    my $krberr = gensym;
    my $kinit = "kinit";
    if (-x "/usr/kerberos/bin/kinit") {
        $kinit = "/usr/kerberos/bin/kinit";
    }
    $kinit = open3($krbin,$krbout,$krberr,$kinit,$username."@".$realm);
    my $ksel = IO::Select->new($krbout,$krberr);
    my @handles;
    while (@handles = $ksel->can_read()) {
        foreach (@handles) {
            my $line;
            my $done = sysread $_,$line,180;
            unless ($done) {
                $ksel->remove($_);
            }
            if ($line =~ /Password for /) {
                print $krbin $password."\n";
            }
        }
    }
    if (waitpid($kinit,0)) {
        return $?;
    } else {
        die "Bug, $kinit got reaped before we could get to it\n";
    }
}




sub find_free_params { #search for things like next available uidNumber
    my %args = @_;
    my @needed_parms = split /,/,$args{needed_params};
    my $uidnumber = 10000; #common linux default is 500, some unix people would say 100, MS went with 10000.  In this case, the highest number
                             #seems the best choice since it won't confuse any software assuming too low a number is a 'system' account
                             #also, a machine having local ids of 500-9999 won't as likely conflict with network accounts
                             #modern systems should tolerate 4.2 billion ids, so potentially wasting 9,500 isn't that big of a deal
                                
    #for now, just supporting uidNumber
    my $directoryserver = $args{directoryserver};
    my $dc = $args{ou};
    my $ldapout;
    my $ldapin;
    my $ldaperr=gensym;
    my $ldappid = open3($ldapin,$ldapout,$ldaperr,qw!ldapsearch -H !,"ldaps://$directoryserver","-b","$dc",qw!(uidNumber=*) uidNumber!);
    my $select = IO::Select->new($ldapout,$ldaperr);
    my @handles;
    my %useduids=();
    my $failure;
    while (@handles = $select->can_read()) {
        foreach (@handles) {
            my $line = <$_>;
            if (not defined $line) {
                $select->remove($_);
                next;
            }
            if ($_ == $ldaperr) {
                if ($line =~ /error/i or $line =~ /problem/i) {
                    print $line;
                    $failure=1;
                }
            } elsif ($line =~ /^uidNumber: (\d+)$/) {
                $useduids{$1}=1;
            }  
        }
    }

    if ($failure) { return undef; }
    while (1) { #loop through until 'return'
        unless ($useduids{$uidnumber}) {
            return {uidNumber=>$uidnumber};
        }
        $uidnumber +=1;
    }
}


#use Data::Dumper;
#krb_login(username=>"Administrator",password=>"cluster",realm=>"XCAT.E1350");
#print Dumper(list_user_accounts(directoryserver=>"v4.xcat.e1350",dnsdomain=>'xcat.e1350'));
#print Dumper(find_free_params(directoryserver=>"v4.xcat.e1350",ou=>"dc=xcat,dc=e1350"));
#use Data::Dumper;
#print Dumper(add_user_account(dnsdomain=>'xcat.e1350',username=>'ffuu',directoryserver=>'v4.xcat.e1350'));
#print Dumper add_machine_account(node=>'ufred.xcat.e1350',directoryserver=>'v4.xcat.e1350');

1;
