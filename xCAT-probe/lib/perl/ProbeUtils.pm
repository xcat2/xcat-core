package ProbeUtils;
use strict;
use File::Path;
use File::Copy;

#-----------------------------------------
=head3
    Description:
        Format output message depending on probe framework requirement
        Format is [<flag>] : <message>
        The valid <flag> are debug, warning, failed and ok
    Attribute:  list by input sequence
        output: where should output the message 
        num:  the number of <flag>
              0: debug
              1: warning
              2: failed
              3: ok
        msg:  the information need to output
     Return value:
        1 : Failed 
        0 : success 
=cut
#----------------------------------------
sub send_msg {
    my $output=shift;
    $output=shift if(($output) && ($output =~ /ProbeUtils/));
    my $num = shift;
    my $msg = shift;
    my $flag;

    if ($num == 0) {
        $flag = "[debug]  :";
    }elsif($num == 1) {
        $flag = "[warning]:";
    }elsif($num == 2) {
        $flag = "[failed] :";
    }elsif($num == 3){
         $flag = "[ok]     :";
    }
    if($output eq "stdout"){
        print "$flag $msg\n";
    }else{
        if (!open (LOGFILE, ">> $output") ) {
           return 1;
        }
        print LOGFILE "$flag $msg\n";
        close LOGFILE;
    }
    return 0;
}

#------------------------------------------
=head3
    Description:
        Judge if a string is a IP address 
    Attribute:  list by input sequence
        addr: the string want to be judged 
    Return value:
        1 : yes
        0 : no
=cut
#------------------------------------------
sub isIpAddr{
    my $addr = shift;
    $addr=shift if(($addr) && ($addr =~ /ProbeUtils/));
    return 0 unless($addr);
    return 0 if($addr !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
    return 0 if ($1 > 255 || $1 == 0 || $2 > 255 || $3 > 255 || $4 > 255);
    return 1;
}  

#------------------------------------------
=head3
    Description:
        Judge if a IP address belongs to a network
    Attribute:  list by input sequence
        net : network address, such like 10.10.10.0
        mask: network mask.  suck like 255.255.255.0
        ip:   a ip address
    Return value:
        1 : yes
        0 : no
=cut
#------------------------------------------
sub isIpBelongToNet{
    my $net=shift;
    $net=shift if(($net) && ($net =~ /ProbeUtils/));
    my $mask=shift;
    my $targetip=shift;

    return 0 if($net !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
    return 0 if($mask !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
    return 0 if(! isIpAddr($targetip));

    my $bin_mask=0;
    $bin_mask=(($1+0)<<24)+(($2+0)<<16)+(($3+0)<<8)+($4+0) if($mask =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);

    my $bin_ip=0;
    $bin_ip=(($1+0)<<24)+(($2+0)<<16)+(($3+0)<<8)+($4+0) if($targetip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);

    my $tmp_net = $bin_mask&$bin_ip;

    my $bin_net=0;
    $bin_net=(($1+0)<<24)+(($2+0)<<16)+(($3+0)<<8)+($4+0) if($net =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);

    return 0 if( $tmp_net != $bin_net);
    return 1;
}

#------------------------------------------
=head3
   Description:
        Get distro name of current operating system
    Attribute:  list by input sequence
        None
    Return value:
        A string, include value are sles, redhat and ubuntu
=cut
#------------------------------------------
sub getOS{
    my $os="unknown";
    my $output = `cat /etc/*release* 2>&1`;
    if($output =~ /suse/i){
        $os="sles";
    }elsif($output =~ /Red Hat/i){
        $os="redhat";
    }elsif($output =~ /ubuntu/i){
        $os="ubuntu";
    }
    
    return  $os;
}

#------------------------------------------
=head3
    Description:
        Judge if a IP address is a static IP address 
    Attribute:  list by input sequence
        ip:   a ip address
        nic:  the network adapter which ip belongs to
    Return value:
        1 : yes
        0 : no
=cut
#------------------------------------------
sub isStaticIp{
    my $ip=shift;
    $ip=shift if(($ip) && ($ip =~ /ProbeUtils/));
    my $nic=shift;
    my $os = getOS();
    my $rst=0;

    if($os =~ /redhat/){
        my $output1=`cat /etc/sysconfig/network-scripts/ifcfg-$nic 2>&1 |grep -i IPADDR`;
        my $output2=`cat /etc/sysconfig/network-scripts/ifcfg-$nic 2>&1 |grep -i BOOTPROTO`;
        $rst=1  if(($output1 =~ /$ip/) && ($output2 =~ /static/i)); 
    }elsif($os =~ /sles/){
        my $output1=`cat /etc/sysconfig/network/ifcfg-$nic 2>&1 |grep -i IPADDR`;
        my $output2=`cat /etc/sysconfig/network/ifcfg-$nic 2>&1 |grep -i BOOTPROTO`;
        $rst=1 if(($output1 =~ /$ip/) && ($output2 =~ /static/i));
    }elsif($os =~/ubuntu/){
        my $output=`cat /etc/network/interfaces 2>&1|grep -E "iface\s+$nic"`;
        $rst=1 if($output =~ /static/i);
    }
    return $rst;
}

#------------------------------------------
=head3
    Description:
        Judge if SELinux is opened in current operating system 
    Attribute:  list by input sequence
         None
    Return value:
        1 : yes
        0 : no
=cut
#------------------------------------------
sub isSelinuxEnable{
    if (-e "/usr/sbin/selinuxenabled") {
       `/usr/sbin/selinuxenabled`;
       if ($? == 0) {
         return 1;
       } else {
         return 0;
       }
    } else {
       return 0;
    }
}   

#------------------------------------------
=head3
    Description:
        Judge if firewall is opened in current operating system
    Attribute:  list by input sequence
         None
    Return value:
        1 : yes
        0 : no
=cut
#------------------------------------------
sub isFirewallOpen{
    my $os =getOS();
    my $output;
    my $rst=0;

    if($os =~ /redhat/){
        $output=`service iptables status 2>&1`;
        $rst=1  if($output =~ /running/i);
    }elsif($os =~ /sles/){
        $output=`service SuSEfirewall2_setup status`;
        $rst=1 if($output =~ /running/i);
    }elsif($os =~/ubuntu/){
        $output=`ufw status`;
        $rst=1 if($output =~ /Status: active/i);        
    }
    return $rst;
}

#------------------------------------------
=head3
    Description:
        Judge if http service is ready to use in current operating system
    Attribute:  list by input sequence
        ip:  http server's ip 
    Return value:
        1 : yes
        0 : no
=cut
#------------------------------------------
sub isHttpReady{
     my $mnip=shift;
     $mnip=shift if(($mnip) && ($mnip =~ /ProbeUtils/));
      
     my $http = "http://$mnip/install/postscripts/efibootmgr";
     rename("./efibootmgr", "./efibootmgr.org") if(-e "./efibootmgr");

     my $outputtmp = `wget $http 2>&1`;
     my $rst =$?;
     if(($outputtmp =~ /200 OK/) && (!$rst) && (-e "./efibootmgr")){
         unlink("./efibootmgr");
         rename("./efibootmgr.org", "./efibootmgr") if(-e "./efibootmgr.org");
         return 1;
     }else{
         rename("./efibootmgr.org", "./efibootmgr") if(-e "./efibootmgr.org");
         return 0;
     }        
}

#------------------------------------------
=head3
    Description:
        Judge if tftp service is ready to use in current operating system
    Attribute:  list by input sequence
        ip:  tftp server's ip
    Return value:
        1 : yes
        0 : no
=cut
#------------------------------------------
sub isTftpReady{
     my $mnip=shift;
     $mnip=shift if(($mnip) && ($mnip =~ /ProbeUtils/));
  
     rename("/tftpboot/tftptestt.tmp", "/tftpboot/tftptestt.tmp.old") if(-e "/tftpboot/tftptestt.tmp");
     rename("./tftptestt.tmp", "./tftptestt.tmp.old") if(-e "./tftptestt.tmp");

     system("touch /tftpboot/tftptestt.tmp");
     my $output = `tftp -4 -v $mnip  -c get tftptestt.tmp`;
     if((!$?) && (-e "./tftptestt.tmp")){
         unlink("./tftptestt.tmp");
         rename("./tftptestt.tmp.old", "./tftptestt.tmp") if(-e "./tftptestt.tmp.old");
         rename("/tftpboot/tftptestt.tmp.old","/tftpboot/tftptestt.tmp") if(-e "/tftpboot/tftptestt.tmp.old");
         return 1;
     }else{
         rename("./tftptestt.tmp.old", "./tftptestt.tmp") if(-e "./tftptestt.tmp.old");
         rename("/tftpboot/tftptestt.tmp.old","/tftpboot/tftptestt.tmp") if(-e "/tftpboot/tftptestt.tmp.old");
         return 0;
     }
}


#------------------------------------------
=head3
    Description:
        Judge if DNS service is ready to use in current operating system
    Attribute:  list by input sequence
        ip:  DNS server's ip
    Return value:
        1 : yes
        0 : no
=cut
#------------------------------------------
sub isDnsReady{
    my $mnip=shift;
    $mnip=shift if(($mnip) && ($mnip =~ /ProbeUtils/));
    my $hostname=shift;
    my $domain=shift;
    
    my $output = `nslookup $mnip $mnip 2>&1`;
    
    if($?){
        return 0;
    }else{
         chomp($output);
         my $tmp=`echo "$output" |grep "Server:[\t\s]*$mnip" >/dev/null 2>&1`;
         print "$tmp";
         return 0 if($?);
         $tmp = `echo "$output"|grep "name ="|grep "$hostname\.$domain" >/dev/null 2>&1`;
         return 0 if($?);
         return 1;
    }
}

1;
