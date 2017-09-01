package probe_utils;

# IBM(c) 2016 EPL license http://www.eclipse.org/legal/epl-v10.html

use strict;
use File::Path;
use File::Copy;
use Time::Local;
use Socket;
use List::Util qw/sum/;

#-----------------------------------------

=head3
    Description:
        Format output message depending on probe framework requirement
        Format is [<flag>] : <message>
        The valid <flag> are debug, warning, failed, info and ok
    Arguments:
        output: where should the message be output 
              The vaild values are:
              stdout : print message to STDOUT
              a file name: print message to the specified "file name" 
        tag:  the type of message, the valid values are:
              d: debug
              w: warning
              f: failed
              o: ok
              i: info

              If tag is NULL, output message without a tag
             
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
    my $flag="";

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
        print "$flag$msg\n";
    } elsif($output) {
        syswrite $output, "$flag$msg\n";
    } else {
        if (!open(LOGFILE, ">> $output")) {
            return 1;
        }
        print LOGFILE "$flag$msg\n";
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
        $rst = 1 if (($output1 =~ /$ip/) && ($output2 =~ /static|none/i));
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
    my $output;
    my $rst = 0;

    my $output = `iptables -nvL -t filter 2>&1`;

    `echo "$output" |grep "Chain INPUT (policy ACCEPT" > /dev/null  2>&1`;
    $rst = 1 if ($?);

    `echo "$output" |grep "Chain FORWARD (policy ACCEPT" > /dev/null  2>&1`;
    $rst = 1 if ($?);

    `echo "$output" |grep "Chain OUTPUT (policy ACCEPT" > /dev/null  2>&1`;
    $rst = 1 if ($?);

    return $rst;
}

#------------------------------------------

=head3
    Description:
        Test if http service is ready to use in current operating system
    Arguments:
        ip:  http server's ip 
        errormsg_ref: (output attribute) if there is something wrong for HTTP service, this attribute save the possible reason.
    Returns:
        1 : yes
        0 : no
=cut

#------------------------------------------
sub is_http_ready {
    my $mnip = shift;
    $mnip = shift if (($mnip) && ($mnip =~ /probe_utils/));
    my $installdir = shift;
    my $errormsg_ref = shift;

    my $http      = "http://$mnip/$installdir/postscripts/syslog";
    my %httperror = (
    "400" => "The request $http could not be understood by the server due to malformed syntax",
    "401" => "The request requires user authentication.",
    "403" => "The server understood the request, but is refusing to fulfill it.",
    "404" => "The server has not found anything matching the test Request-URI $http.",
    "405" => "The method specified in the Request-Line $http is not allowe.",
    "406" => "The method specified in the Request-Line $http is not acceptable.",
    "407" => "The wget client must first authenticate itself with the proxy.",
    "408" => "The client did not produce a request within the time that the server was prepared to wait. The client MAY repeat the request without modifications at any later time.",
    "409" => "The request could not be completed due to a conflict with the current state of the resource.",
    "410" => "The requested resource $http is no longer available at the server and no forwarding address is known.",
    "411" => "The server refuses to accept the request without a defined Content- Length.",
    "412" => "The precondition given in one or more of the request-header fields evaluated to false when it was tested on the server.",
    "413" => "The server is refusing to process a request because the request entity is larger than the server is willing or able to process.",
    "414" => "The server is refusing to service the request because the Request-URI is longer than the server is willing to interpret.",
    "415" => "The server is refusing to service the request because the entity of the request is in a format not supported by the requested resource for the requested method.",
    "416" => "Requested Range Not Satisfiable",
    "417" => "The expectation given in an Expect request-header field could not be met by this server",
    "500" => "The server encountered an unexpected condition which prevented it from fulfilling the request.",
    "501" => "The server does not recognize the request method and is not capable of supporting it for any resource.",
    "502" => "The server, while acting as a gateway or proxy, received an invalid response from the upstream server it accessed in attempting to fulfill the reques.",
    "503" => "The server is currently unable to handle the request due to a temporary overloading or maintenance of the server.",
    "504" => "The server, while acting as a gateway or proxy, did not receive a timely response from the upstream server specified by the URI or some other auxiliary server it needed to access in attempting to complete the request.",
    "505" => "The server does not support, or refuses to support, the HTTP protocol version that was used in the request message.");

    my $tmpdir = "/tmp/xcatprobe$$/";
    if(! mkpath("$tmpdir")){
        $$errormsg_ref = "Prepare test environment error: $!";
        return 0;
    }
    my @outputtmp = `wget -O $tmpdir/syslog $http 2>&1`;
    my $rst       = $?;
    $rst = $rst >> 8;

    if ((!$rst) && (-e "$tmpdir/syslog")) {
        unlink("$tmpdir/syslog");
        rmdir ("$tmpdir");
        return 1;
    } elsif ($rst == 4) {
        $$errormsg_ref = "Network failure, the server refuse connection. Please check if httpd service is running first.";
    } elsif ($rst == 5) {
        $$errormsg_ref = "SSL verification failure, the server refuse connection";
    } elsif ($rst == 6) {
        $$errormsg_ref = "Username/password authentication failure, the server refuse connection";
    } elsif ($rst == 8) {
        my $returncode = $outputtmp[2];
        chomp($returncode);
        $returncode =~ s/.+(\d\d\d).+/$1/g;
        if(exists($httperror{$returncode})){
            $$errormsg_ref = $httperror{$returncode};
        }else{
            #should not hit this block normally
            $$errormsg_ref = "Unknown return code of wget <$returncode>.";
        }
    }
    unlink("$tmpdir/syslog");
    if(! rmdir ("$tmpdir")){
        $$errormsg_ref .= " Clean test environment error(rmdir $tmpdir): $!";
    }
    return 0;
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
    my $tftpdir = shift;
    
    rename("/$tftpdir/tftptestt.tmp", "/$tftpdir/tftptestt.tmp.old") if (-e "/$tftpdir/tftptestt.tmp");
    rename("./tftptestt.tmp", "./tftptestt.tmp.old") if (-e "./tftptestt.tmp");

    system("touch /$tftpdir/tftptestt.tmp");
    my $output = `tftp -4 -v $mnip  -c get tftptestt.tmp`;
    if ((!$?) && (-e "./tftptestt.tmp")) {
        unlink("./tftptestt.tmp");
        rename("./tftptestt.tmp.old", "./tftptestt.tmp") if (-e "./tftptestt.tmp.old");
        rename("/$tftpdir/tftptestt.tmp.old", "/$tftpdir/tftptestt.tmp") if (-e "/$tftpdir/tftptestt.tmp.old");
        return 1;
    } else {
        rename("./tftptestt.tmp.old", "./tftptestt.tmp") if (-e "./tftptestt.tmp.old");
        rename("/$tftpdir/tftptestt.tmp.old", "/$tftpdir/tftptestt.tmp") if (-e "/$tftpdir/tftptestt.tmp.old");
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
    my $serverip = shift;
    my $hostname = shift;
    my $domain   = shift;

    my $output = `nslookup $mnip $serverip 2>&1`;

    if ($?) {
        return 0;
    } else {
        chomp($output);
        my $tmp = grep {$_ =~ "Server:[\t\s]*$serverip"} split(/\n/, $output);
        return 0 if ($tmp == 0);

        $tmp = grep {$_ =~ "name = $hostname\.$domain"} split(/\n/, $output);
        return 0 if ($tmp == 0);
        return 1;
    }
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
sub get_network {
    my $ip = shift;
    $ip = shift if (($ip) && ($ip =~ /probe_utils/));
    my $mask = shift;
    my $net  = "";

    return $net if (!is_ip_addr($ip));
    return $net if ($mask !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);

    my $bin_mask = unpack("N", inet_aton($mask));
    my $bin_ip   = unpack("N", inet_aton($ip));
    my $net_int32 = $bin_mask & $bin_ip;
    $net = ($net_int32 >> 24) . "." . (($net_int32 >> 16) & 0xff) . "." . (($net_int32 >> 8) & 0xff) . "." . ($net_int32 & 0xff);
    return "$net/$mask";
}

#------------------------------------------

=head3
    Description:
        Check if the free space of specific directory is more than expected value 
    Arguments:
        targetdir: The directory needed to be checked 
        expect_free_space: the expected free space for above directory
    Returns:
        0: the free space of specific directory is less than expected value
        1: the free space of specific directory is more than expected value
        2: the specific directory isn't mounted on standalone disk. it is a part of "/" 
=cut

#------------------------------------------
sub is_dir_has_enough_space{
    my $targetdir=shift;
    $targetdir = shift if (($targetdir) && ($targetdir =~ /probe_utils/));
    my $expect_free_space = shift;
    my @output = `df -k`;

    foreach my $line (@output){
        chomp($line);
        my @line_array = split(/\s+/, $line);
        if($line_array[5] =~ /^$targetdir$/){
            my $left_space = $line_array[3]/1048576;
            if($left_space >= $expect_free_space){
                return 1;
            }else{
                return 0;
            }
        }
    }
    return 2;
}

#------------------------------------------

=head3
    Description:
        Convert node range in Regular Expression to a node name array
    Arguments:
        noderange : the range of node
    Returns:
        An array which contains each node name
=cut

#------------------------------------------
sub parse_node_range {
    my $noderange = shift;
    $noderange= shift if (($noderange) && ($noderange =~ /probe_utils/));
    my @nodeslist = `nodels $noderange`;
    chomp @nodeslist;
    return @nodeslist;
}

#------------------------------------------

=head3
    Description:
        Test if ntp service is ready to use in current operating system
    Arguments:
        errormsg_ref: (output attribute) if there is something wrong for ntp service, this attribute save the possible reason.
    Returns:
        1 : yes
        0 : no
=cut

#------------------------------------------
sub is_ntp_ready{
    my $errormsg_ref = shift;
    $errormsg_ref= shift if (($errormsg_ref) && ($errormsg_ref =~ /probe_utils/));

    my $cmd = 'ntpq -c "rv 0"';
    $| = 1;

    #wait 5 seconds for ntpd synchronize at most
    for (my $i = 0; $i < 5; ++$i) {
        if(!open(NTP, $cmd." 2>&1 |")){
            $$errormsg_ref = "Can't start ntpq: $!";
            return 0;
        }else{
            while(<NTP>) {
                chomp;
                if (/^associd=0 status=(\S{4}) (\S+),/) {
                    my $leap=$2;

                    last if ($leap =~ /(sync|leap)_alarm/);

                    if ($leap =~ /leap_(none|((add|del)_sec))/){
                        close(NTP);
                        return 1;
                    }

                    #should not hit below 3 lines normally
                    $$errormsg_ref = "Unexpected ntpq output ('leap' status <$leap>), please contact xCAT team";
                    close(NTP);
                    return 0;
                }elsif(/Connection refused/) {
                    $$errormsg_ref = "ntpd service is not running! Please setup ntp in current node";
                    close(NTP);
                    return 0;
                }else{
                    #should not hit this block normally
                    $$errormsg_ref = "Unexpected ntpq output <$_>, please contact xCAT team";
                    close(NTP);
                    return 0;
                }
            }
        }
        close(NTP);
        sleep 1;
    }
    $$errormsg_ref = "ntpd did not synchronize.";
    return 0;
}

#------------------------------------------

=head3
    Description:
        Convert second to time
    Arguments:
        second_in : the time in seconds
    Returns:
        xx:xx:xx xx hours xx minutes xx seconds
=cut

#------------------------------------------
sub convert_second_to_time {
    my $second_in = shift;
    $second_in = shift if (($second_in) && ($second_in =~ /probe_utils/));
    my @time = ();
    my $result;

    if ($second_in == 0) {
        return "00:00:00";
    }

    my $count = 0;
    while ($count < 3) {
        my $tmp_second;
        if ($count == 2) {
            $tmp_second = $second_in % 100;
        } else {
            $tmp_second = $second_in % 60;
        }

        if ($tmp_second < 10) {
            push @time,  "0$tmp_second";
        } else {
            push @time, "$tmp_second";
        }

        $second_in = ($second_in - $tmp_second) / 60;
        $count++;
    }

    my @time_result = reverse @time;
    $result = join(":", @time_result);

    return $result;
}

#------------------------------------------

=head3
    Description:
        print table
    Arguments:
        content: double dimensional array
        has_title: whether has title in content
        
        eg: @content = ($title,
                        @content1,
                        @content2,
                        ......
            );
            $has_title = 1;
            print_table(\@content, $has_title);

        or @content = (@content1,
                       @content2,
                       ......
           );
           $has_title = 0;
           print_table(\@content, $has_title);

    Ouput:
        --------------------------
        |         xxxxxxx        |
        --------------------------
        | xxx | xxxx | xx   | xx |  
        --------------------------
        | xx  | xxxx | xxxx | xx | 
        --------------------------

        or 

        --------------------------
        | xxx | xxxx | xx   | xx |
        --------------------------
        | xx  | xxxx | xxxx | xx |
        --------------------------

=cut

#------------------------------------------
sub print_table {
    my $content = shift;
    $content = shift if (($content) && ($content =~ /probe_utils/));
    my $has_title = shift;
    my $title;

    if ($has_title) {
        $title = shift(@$content);
    }

    my @length_array;
    foreach my $row (@$content) {
        for (my $i = 0; $i < @{$row}; $i++) {
            my $ele_length = length(${$row}[$i]);
            $length_array[$i] = $ele_length if ($length_array[$i] < $ele_length);
        }
    }

    my @content_new;
    my @row_new;
    my $row_line;
    my $whole_length;
    foreach my $row (@$content) {
        @row_new = ();
        for (my $i = 0; $i < @{$row}; $i++) {
            push @row_new, ${$row}[$i] . " " x ($length_array[$i] - length(${$row}[$i]));
        }
        $row_line = "| " . join(" | ", @row_new) . " |";
        push @content_new, $row_line;
    }
    $whole_length = length($row_line);

    my $title_new;
    my $title_length = length($title);
    if ($has_title) {
        if ($whole_length - 1 <= $title_length) {
            $title_new = $title;
        } else {
            $title_new = " " x (($whole_length - 2 - $title_length)/2) . "$title";
            $title_new .= " " x ($whole_length - 2 - length($title_new));
            $title_new = "|" . $title_new . "|";
        }
    }

    my $format_line = "-" x $whole_length;
    print $format_line . "\n" if ($has_title);
    print $title_new . "\n" if ($has_title);
    print $format_line . "\n";
    foreach (@content_new) {
        print $_ . "\n";
    }
    print $format_line . "\n";
}

1;
