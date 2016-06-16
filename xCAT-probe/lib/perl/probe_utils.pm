package probe_utils;

# IBM(c) 2016 EPL license http://www.eclipse.org/legal/epl-v10.html

use strict;
use File::Path;
use File::Copy;
use Socket;
#-----------------------------------------

=head3
    Description:
        Format output message depending on probe framework requirement
        Format is [<flag>] : <message>
        The valid <flag> are debug, warning, failed, info and ok
    Arguments:
        output: where should output the message 
        num:  the number of <flag>
              d: debug
              w: warning
              f: failed
              o: ok
              i: info
        msg:  the information need to output
     Returns:
        1 : Failed 
        0 : success 
=cut

#----------------------------------------
sub send_msg {
    my $output = shift;
    $output = shift if (($output) && ($output =~ /probe_utils/));
    my $tag = shift;
    my $msg = shift;
    my $flag;

    if ($tag eq "d") {
        $flag = "[debug]  :";
    } elsif ($tag eq "w") {
        $flag = "[warning]:";
    } elsif ($tag eq "f") {
        $flag = "[failed] :";
    } elsif ($tag eq "o") {
        $flag = "[ok]     :";
    } elsif ($tag eq "i") {
        $flag = "[info]   :";
    }

    if ($output eq "stdout") {
        print "$flag $msg\n";
    } else {
        if (!open(LOGFILE, ">> $output")) {
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
        Test if a string is a IP address
    Arguments:
        addr: the string want to be judged 
    Returns:
        1 : yes
        0 : no
=cut

#------------------------------------------
sub is_ip_addr {
    my $addr = shift;
    $addr = shift if (($addr) && ($addr =~ /probe_utils/));
    return 0 unless ($addr);
    return 0 if ($addr !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
    return 0 if ($1 > 255 || $1 == 0 || $2 > 255 || $3 > 255 || $4 > 255);
    return 1;
}

#------------------------------------------

=head3
    Description:
        Test if a IP address belongs to a network
    Arguments:
        net : network address, such like 10.10.10.0
        mask: network mask.  suck like 255.255.255.0
        ip:   a ip address
    Returns:
        1 : yes
        0 : no
=cut

#------------------------------------------
sub is_ip_belong_to_net {
    my $net = shift;
    $net = shift if (($net) && ($net =~ /probe_utils/));
    my $mask     = shift;
    my $targetip = shift;

    return 0 if ($net !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
    return 0 if ($mask !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
    return 0 if (!is_ip_addr($targetip));

    my $bin_mask = 0;
    $bin_mask = (($1 + 0) << 24) + (($2 + 0) << 16) + (($3 + 0) << 8) + ($4 + 0) if ($mask =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);

    my $bin_ip = 0;
    $bin_ip = (($1 + 0) << 24) + (($2 + 0) << 16) + (($3 + 0) << 8) + ($4 + 0) if ($targetip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);

    my $tmp_net = $bin_mask & $bin_ip;

    my $bin_net = 0;
    $bin_net = (($1 + 0) << 24) + (($2 + 0) << 16) + (($3 + 0) << 8) + ($4 + 0) if ($net =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);

    return 0 if ($tmp_net != $bin_net);
    return 1;
}

#------------------------------------------

=head3
   Description:
        Get distro name of current operating system
    Arguments:
        None
    Returns:
        A string, include value are sles, redhat and ubuntu
=cut

#------------------------------------------
sub get_os {
    my $os     = "unknown";
    my $output = `cat /etc/*release* 2>&1`;
    if ($output =~ /suse/i) {
        $os = "sles";
    } elsif ($output =~ /Red Hat/i) {
        $os = "redhat";
    } elsif ($output =~ /ubuntu/i) {
        $os = "ubuntu";
    }

    return $os;
}

#------------------------------------------

=head3
    Description:
        Test if a IP address is a static IP address 
    Arguments:
        ip:   a ip address
        nic:  the network adapter which ip belongs to
    Returns:
        1 : yes
        0 : no
=cut

#------------------------------------------
sub is_static_ip {
    my $ip = shift;
    $ip = shift if (($ip) && ($ip =~ /probe_utils/));
    my $nic = shift;
    my $os  = get_os();
    my $rst = 0;

    if ($os =~ /redhat/) {
        my $output1 = `cat /etc/sysconfig/network-scripts/ifcfg-$nic 2>&1 |grep -i IPADDR`;
        my $output2 = `cat /etc/sysconfig/network-scripts/ifcfg-$nic 2>&1 |grep -i BOOTPROTO`;
        $rst = 1 if (($output1 =~ /$ip/) && ($output2 =~ /static/i));
    } elsif ($os =~ /sles/) {
        my $output1 = `cat /etc/sysconfig/network/ifcfg-$nic 2>&1 |grep -i IPADDR`;
        my $output2 = `cat /etc/sysconfig/network/ifcfg-$nic 2>&1 |grep -i BOOTPROTO`;
        $rst = 1 if (($output1 =~ /$ip/) && ($output2 =~ /static/i));
    } elsif ($os =~ /ubuntu/) {
        my $output = `cat /etc/network/interfaces 2>&1|grep -E "iface\s+$nic"`;
        $rst = 1 if ($output =~ /static/i);
    }
    return $rst;
}

#------------------------------------------

=head3
    Description:
        Test if SELinux is opened in current operating system 
    Arguments:
         None
    Returns:
        1 : yes
        0 : no
=cut

#------------------------------------------
sub is_selinux_enable {
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
        Test if firewall is opened in current operating system
    Arguments:
         None
    Returns:
        1 : yes
        0 : no
=cut

#------------------------------------------
sub is_firewall_open {
    my $os = get_os();
    my $output;
    my $rst = 0;

    if ($os =~ /redhat/) {
        $output = `service iptables status 2>&1`;
        $rst = 1 if ($output =~ /running/i);
    } elsif ($os =~ /sles/) {
        $output = `service SuSEfirewall2_setup status`;
        $rst = 1 if ($output =~ /running/i);
    } elsif ($os =~ /ubuntu/) {
        $output = `ufw status`;
        $rst = 1 if ($output =~ /Status: active/i);
    }
    return $rst;
}

#------------------------------------------

=head3
    Description:
        Test if http service is ready to use in current operating system
    Arguments:
        ip:  http server's ip 
    Returns:
        1 : yes
        0 : no
=cut

#------------------------------------------
sub is_http_ready {
    my $mnip = shift;
    $mnip = shift if (($mnip) && ($mnip =~ /probe_utils/));

    my $http = "http://$mnip/install/postscripts/syslog";
    rename("./syslog", "./syslog.org") if (-e "./syslog");

    my $outputtmp = `wget $http 2>&1`;
    my $rst       = $?;
    if (($outputtmp =~ /200 OK/) && (!$rst) && (-e "./syslog")) {
        unlink("./syslog");
        rename("./syslog.org", "./syslog") if (-e "./syslog.org");
        return 1;
    } else {
        rename("./syslog.org", "./syslog") if (-e "./syslog.org");
        return 0;
    }
}

#------------------------------------------

=head3
    Description:
        Test if tftp service is ready to use in current operating system
    Arguments:
        ip:  tftp server's ip
    Returns:
        1 : yes
        0 : no
=cut

#------------------------------------------
sub is_tftp_ready {
    my $mnip = shift;
    $mnip = shift if (($mnip) && ($mnip =~ /probe_utils/));

    rename("/tftpboot/tftptestt.tmp", "/tftpboot/tftptestt.tmp.old") if (-e "/tftpboot/tftptestt.tmp");
    rename("./tftptestt.tmp", "./tftptestt.tmp.old") if (-e "./tftptestt.tmp");

    system("touch /tftpboot/tftptestt.tmp");
    my $output = `tftp -4 -v $mnip  -c get tftptestt.tmp`;
    if ((!$?) && (-e "./tftptestt.tmp")) {
        unlink("./tftptestt.tmp");
        rename("./tftptestt.tmp.old", "./tftptestt.tmp") if (-e "./tftptestt.tmp.old");
        rename("/tftpboot/tftptestt.tmp.old", "/tftpboot/tftptestt.tmp") if (-e "/tftpboot/tftptestt.tmp.old");
        return 1;
    } else {
        rename("./tftptestt.tmp.old", "./tftptestt.tmp") if (-e "./tftptestt.tmp.old");
        rename("/tftpboot/tftptestt.tmp.old", "/tftpboot/tftptestt.tmp") if (-e "/tftpboot/tftptestt.tmp.old");
        return 0;
    }
}


#------------------------------------------

=head3
    Description:
        Test if DNS service is ready to use in current operating system
    Arguments:
        ip:  DNS server's ip
    Returns:
        1 : yes
        0 : no
=cut

#------------------------------------------
sub is_dns_ready {
    my $mnip = shift;
    $mnip = shift if (($mnip) && ($mnip =~ /probe_utils/));
    my $hostname = shift;
    my $domain   = shift;

    my $output = `nslookup $mnip $mnip 2>&1`;

    if ($?) {
        return 0;
    } else {
        chomp($output);
        my $tmp = `echo "$output" |grep "Server:[\t\s]*$mnip" >/dev/null 2>&1`;
        print "$tmp";
        return 0 if ($?);
        $tmp = `echo "$output"|grep "name ="|grep "$hostname\.$domain" >/dev/null 2>&1`;
        return 0 if ($?);
        return 1;
    }
}

#------------------------------------------

=head3
    Description:
        Convert host name to ip address 
    Arguments:
        hostname: The hostname need to convert 
    Returns:
        ip: The ip address 
=cut

#------------------------------------------
sub get_ip_from_hostname{
    my $hostname = shift;
    $hostname=shift if(($hostname) && ($hostname =~ /probe_utils/));
    my $ip = "";

    my @output = `ping -c 1 $hostname 2>&1`;
    if(!$?){
       if($output[0] =~ /^PING.+\s+\((\d+\.\d+\.\d+\.\d+)\).+/){
           $ip=$1;
       }
    }
    return $ip;
}

#------------------------------------------

=head3
    Description:
        Calculate network address from ip and netmask 
    Arguments:
        ip: ip address
        mask: network mask
    Returns:
        network : The network address
=cut

#------------------------------------------
sub get_network{
    my $ip = shift;
    $ip=shift if(($ip) && ($ip =~ /probe_utils/));
    my $mask = shift;
    my $net="";

    return $net if (!is_ip_addr($ip));
    return $net if ($mask !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);

    my $bin_mask = 0;
    $bin_mask = (($1 + 0) << 24) + (($2 + 0) << 16) + (($3 + 0) << 8) + ($4 + 0) if ($mask =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);

    my $bin_ip = 0;
    $bin_ip = (($1 + 0) << 24) + (($2 + 0) << 16) + (($3 + 0) << 8) + ($4 + 0) if ($ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);

    my $net_int32 = $bin_mask & $bin_ip;
    $net = ($net_int32 >> 24) . "." . (($net_int32 >> 16) & 0xff) . "." . (($net_int32 >> 8) & 0xff) . "." . ($net_int32 & 0xff);
    return "$net/$mask";
}

#------------------------------------------

=head3
    Description:
        Convert ip to hostname 
    Arguments:
        ip: The ip need to convert
    Returns:
        hostname: hostname or "" 
=cut

#------------------------------------------
sub get_hostname_from_ip{
    my  $ip = shift;
    $ip=shift if(($ip) && ($ip =~ /probe_utils/));
    my $dns_server = shift;
    my $hostname="";
    my $output="";

    `which nslookup > /dev/null 2>&1`;
    if(!$?){ 
        $output = `nslookup $ip  $dns_server 2>&1`;
        if (!$?) {
            chomp($output);
            my $rc = $hostname = `echo "$output"|awk -F" " '/name =/ {print \$4}'|awk -F"." '{print \$1}'`;
            chomp($hostname);
            return $hostname if (!$rc);
        }    
    }
    if(($hostname eq "") && (-e "/etc/hosts")){
        $output = `cat /etc/hosts 2>&1 |grep $ip`;
        if(!$?){
            my @splitoutput = split(" ", $output);
            $hostname = $splitoutput[1]; 
        }
    }
    return $hostname; 
}

1;
