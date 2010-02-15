# IBM(c) 2010 EPL license http://www.eclipse.org/legal/epl-v10.html

#This module provides simplified methods for adding machine/user accounts to active directory,
#as well as setting passwords for aforementioned accounts.

#there exists direct perl ldap module, but too rare to bank on, going to use ldapmodify from
#system calls

use strict;
use MIME::Base64;
use Encode;
use xCAT::Utils qw/genpassword/;
use IPC::Open3;
use IO::Select;


my $machineldiftemplate = 'dn: CN=##UPCASENODENAME##,##OU##
changetype: add
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: user
objectClass: computer
cn: ##UPCASENODENAME##
distinguishedName: CN=##UPCASENODENAME##,##OU##
objectCategory: CN=Computer,CN=Schema,CN=Configuration##REALMDCS##
instanceType: 4
displayName: ##UPCASENODENAME##$
name: ##UPCASENODENAME##
userAccountControl: 4096
codePage: 0
countryCode: 0
accountExpires: 0
sAMAccountName: ##UPCASENODENAME##$
dNSHostName: ##UPCASENODENAME####DNSDOMAIN##
servicePrincipalName: HOST/##UPCASENODENAME##
servicePrincipalName: HOST/##UPCASENODENAME####DNSDOMAIN##

dn: CN=##UPCASENODENAME##,##OU##
changetype: modify
replace: unicodePwd
unicodePwd::##B64PASSWORD##';


=cut
add_machine_account
Arguments are in a hash:
    node=>name of machine to add
=cut
sub add_machine_account {
    my %args = @_;
    my $nodename = $args{node};
    my $ou = $args{ou};
    my $dnsdomain = $args{dnsdomain};
    if (not $dnsdomain and $nodename =~ /\./) { #if no domain provided, guess from nodename
        $dnsdomain = $nodename;
        $dnsdomain =~ s/^[^\.]*//;
    }
    unless ($dnsdomain =~ /^\./) {
        $dnsdomain = '.'.$dnsdomain;
    }
    $nodename =~ s/\..*//; #strip dns domain if part of nodename
    my $upnodename = uc($nodename);
    my $domain_components = $dnsdomain;
    $domain_components =~ s/\./,dc=/g;
    unless ($domain_components =~ /^,dc=/) {
        $domain_components = ",dc=".$domain_components;
    }
    if ($ou) { 
        unless ($ou =~ /$domain_components\z/) {
            $ou .= $domain_components;
        }
    } else {
        $ou = "CN=Computers".$domain_components;
    }
    my $directoryserver = $args{directoryserver};
    unless ($domain_components and $dnsdomain and $ou and $upnodename and $directoryserver) {
        return {error=>"Unable to determine all required parameters"};
    }
    my $newpassword = $args{password};
    unless ($newpassword) {
        $newpassword = '"'.genpassword(8).'"';
    }
    Encode::from_to($newpassword,"utf8","utf16le"); #ms uses utf16le, we use utf8
    my $b64password = encode_base64($newpassword);
    my $ldif = $machineldiftemplate;
    $ldif =~ s/##B64PASSWORD##/$b64password/g;
    $ldif =~ s/##OU##/$ou/g;
    $ldif =~ s/##REALMDCS##/$domain_components/g;
    $ldif =~ s/##DNSDOMAIN##/$dnsdomain/g;
    $ldif =~ s/##UPCASENODENAME##/$upnodename/g;
    my $dn = "CN=$upnodename,$ou";
    my $rc = system("ldapsearch -H ldaps://$directoryserver -b $dn");
    if ($rc == 0) { 
        return {error=>"System already exists"};
    } elsif (not $rc==8192) {
        return {error=>"Unknown error $rc"};
    }
    $rc = system("echo '$ldif'|ldapmodify  -H ldaps://$directoryserver"); 
    return {password=>$newpassword};
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
    my $ldaperr;
    my $ldappid = open3($ldapin,$ldapout,$ldaperr,qw!ldapsearch -H !,"ldaps://$directoryserver","-b","$dc",qw!(uidNumber=*) uidNumber!);
    my $select = IO::Select->new($ldapout,$ldaperr);
    my @handles;
    my %useduids=();
    while (@handles = $select->can_read()) {
        foreach (@handles) {
            my $line = <$_>;
            if (not defined $line) {
                $select->remove($_);
                next;
            }
            if ($line =~ /^uidNumber: (\d+)$/) {
                $useduids{$1}=1;
            }
        }
    }

    while (1) { #loop through until 'return'
        unless ($useduids{$uidnumber}) {
            return {uidNumber=>$uidnumber};
        }
        $uidnumber +=1;
    }
}


use Data::Dumper;
print Dumper(find_free_params(directoryserver=>"v4.xcat.e1350",ou=>"dc=xcat,dc=e1350"));
