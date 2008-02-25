#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::DNSsn;
use xCAT::Table;

use xCAT::Utils;

use xCAT::MsgUtils;
use Getopt::Long;

#-------------------------------------------------------

=head1 
  xCAT plugin package to setup of DNS 


#-------------------------------------------------------

=head3  handled_commands 

Check to see if on a Service Node
Check database to see if this node is a DNS server
Call  setup_DNS

=cut

#-------------------------------------------------------

sub handled_commands
{
    my $rc=0;
    if (xCAT::Utils->isServiceNode())
    {
        my @nodeinfo   = xCAT::Utils->determinehostname;
        my $nodename   = $nodeinfo[0];
        my $nodeipaddr = $nodeinfo[1];
        my $service    = "nameservers";

        $rc = xCAT::Utils->isServiceReq($nodename, $service, $nodeipaddr);
        if ($rc == 1)
        {

            # service needed on this Service Node
            $rc = &setup_DNS($nodename);    # setup DNS
        }
    }
    return $rc;
}

#-------------------------------------------------------

=head3  process_request 

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{
    return;
}

#-----------------------------------------------------------------------------

=head3 setup_DNS 

    Sets up Domain Name service  
	http://www.adminschoice.com/docs/domain_name_service.htm#Introduction

=cut

#-----------------------------------------------------------------------------
sub setup_DNS
{
    my ($nodename) = @_;

    # backup the original
    if ((-e "/etc/named.conf") && (!(-e "/etc/named.conf.ORIG")))
    {
        `cp /etc/named.conf /etc/named.conf.ORIG`;
    }

    # read DB for nodeinfo
    my $master;
    my $os;
    my $arch;
    my $retdata = xCAT::Utils->readSNInfo($nodename);
    if ($retdata->{'arch'})
    {    # no error
        $master = $retdata->{'master'};
        $os     = $retdata->{'os'};
        $arch   = $retdata->{'arch'};

        # build the named.conf file
        if (($os =~ /rh/i) || ($os =~ /fe/i))
        {
            my $namedconfig = "/etc/named.conf";
            my @nameconfigtemplate;
            $nameconfigtemplate[0] = "options {directory \"/var/named\";\n";
            $nameconfigtemplate[1] =
              "     dump-file \"/var/named/data/cache_dump.db\";\n";
            $nameconfigtemplate[2] =
              "      statistics-file \"/var/named/data/named_stats.txt\";\n";
            $nameconfigtemplate[3] = "     forward only;\n";
            $nameconfigtemplate[4] = "     forwarders{$master;\n      };\n";
            $nameconfigtemplate[5] = "};\n";
            $nameconfigtemplate[6] = "\n";
            $nameconfigtemplate[7] = "controls {\n";
            $nameconfigtemplate[8] =
              "    inet 127.0.0.1 allow { localhost; } keys { rndckey; };\n";
            $nameconfigtemplate[9]  = "};\n";
            $nameconfigtemplate[10] = "\n";
            $nameconfigtemplate[11] = "zone \".\" IN {\n";
            $nameconfigtemplate[12] = "   type hint;\n";
            $nameconfigtemplate[13] = "   file \"named.ca\";\n";
            $nameconfigtemplate[14] = "};\n\n";
            $nameconfigtemplate[15] = "zone \"localdomain\" IN {\n";
            $nameconfigtemplate[16] = "    type master;\n";
            $nameconfigtemplate[17] = "    file \"localdomain.zone\";\n";
            $nameconfigtemplate[18] = "    allow-update { none; };\n";
            $nameconfigtemplate[19] = "};\n";
            $nameconfigtemplate[20] = "\n";
            $nameconfigtemplate[21] = "zone \"localhost\" IN {\n";
            $nameconfigtemplate[22] = "    type master;\n";
            $nameconfigtemplate[23] = "    file \"localhost.zone\";\n";
            $nameconfigtemplate[24] = "    allow-update { none; };\n";
            $nameconfigtemplate[25] = "};\n";
            $nameconfigtemplate[26] = "\n";
            $nameconfigtemplate[27] = "zone \"0.0.127.in-addr.arpa\" IN {\n";
            $nameconfigtemplate[28] = "    type master;\n";
            $nameconfigtemplate[29] = "    file \"named.local\";\n";
            $nameconfigtemplate[30] = "    allow-update { none; };\n";
            $nameconfigtemplate[31] = "};\n";
            $nameconfigtemplate[32] = "\n";
            $nameconfigtemplate[33] =
              "zone \"0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa\" IN { \n";
            $nameconfigtemplate[34] = "    type master; \n";
            $nameconfigtemplate[35] = "    file \"named.ip6.local\";\n";
            $nameconfigtemplate[36] = "    allow-update { none; };\n";
            $nameconfigtemplate[37] = "};\n";
            $nameconfigtemplate[38] = "\n";
            $nameconfigtemplate[39] = "zone \"255.in-addr.arpa\" IN {\n ";
            $nameconfigtemplate[40] = "    type master; \n";
            $nameconfigtemplate[41] = "    file \"named.broadcast\";\n";
            $nameconfigtemplate[42] = "    allow-update { none; };\n";
            $nameconfigtemplate[43] = "};\n";
            $nameconfigtemplate[44] = "\n";
            $nameconfigtemplate[45] = "zone \"0.in-addr.arpa\" IN {\n ";
            $nameconfigtemplate[46] = "    type master;\n ";
            $nameconfigtemplate[47] = "     file \"named.zero\";\n";
            $nameconfigtemplate[48] = "    allow-update { none; };\n";
            $nameconfigtemplate[49] = "};\n";
            $nameconfigtemplate[50] = "\n";
            $nameconfigtemplate[51] = "include \"/etc/rndc.key\";\n ";

            open(DNSCFG, ">$namedconfig")
              or xCAT::MsgUtils->message('S',
                                    "Cannot open $named.conf for DNS setup \n");
            print DNSCFG @nameconfigtemplate;
            close DNSCFG;

            # turn DNS on

            `cp /etc/named.conf /var/named/chroot/etc`;
            `chkconfig --level 345 named on`;
            `service named restart`;
             xCAT::Utils->update_xCATSN("dns"); 
        }
    }
    else
    {                                       # error reading DB
        return 1;
    }
    return 0;
}
1;
