# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::networks;
use xCAT::Table;
use Data::Dumper;
use Sys::Syslog;
use Socket;
use xCAT::Utils;

sub handled_commands
{
    return {makenetworks => "networks",};
}

sub preprocess_request
{
    my $req = shift;
    my $cb  = shift;
    if ($req->{_xcatdest}) { return [$req]; }    #exit if preprocessed
    my @requests = ({%$req}); #first element is local instance
    my @sn = xCAT::Utils->getSNList();
    foreach my $s (@sn)
    {
        my $reqcopy = {%$req};
        $reqcopy->{'_xcatdest'} = $s;
        push @requests, $reqcopy;
    }
    return \@requests;
}

sub process_request
{
    my $nettab = xCAT::Table->new('networks', -create => 1, -autocommit => 0);
    my @rtable = split /\n/, `/bin/netstat -rn`;
    open($rconf, "/etc/resolv.conf");
    my @nameservers;
    if ($rconf)
    {
        my @rcont;
        while (<$rconf>)
        {
            push @rcont, $_;
        }
        close($rconf);
        foreach (grep /nameserver/, @rcont)
        {
            my $line = $_;
            my @pair;
            $line =~ s/#.*//;
            @pair = split(/\s+/, $line);
            push @nameservers, $pair[1];
        }
    }
    splice @rtable, 0, 2;
    foreach (@rtable)
    { #should be the lines to think about, do something with U, and something else with UG
        my $net;
        my $mask;
        my $mgtifname;
        my $gw;
        my @ent = split /\s+/, $_;
        if ($ent[0] eq "169.254.0.0")
        {
            next;
        }
        if ($ent[3] eq 'U')
        {
            $net       = $ent[0];
            $mask      = $ent[2];
            $mgtifname = $ent[7];
            $nettab->setAttribs({'net' => $net},
                                {'mask' => $mask, 'mgtifname' => $mgtifname});
            my $tent = $nettab->getAttribs({'net' => $net}, 'nameservers');
            unless ($tent and $tent->{nameservers})
            {
                my $text = join ',', @nameservers;
                $nettab->setAttribs({'net' => $net}, {nameservers => $text});
            }
            unless ($tent and $tent->{tftpserver})
            {
                my $netdev = $ent[7];
                my @netlines = split /\n/, `/sbin/ip addr show dev $netdev`;
                foreach (grep /\s*inet\b/, @netlines)
                {
                    my @row = split(/\s+/, $_);
                    my $ipaddr = $row[2];
                    $ipaddr =~ s/\/.*//;
                    my @maska = split(/\./, $mask);
                    my @ipa   = split(/\./, $ipaddr);
                    my @neta  = split(/\./, $net);
                    my $isme  = 1;
                    foreach (0 .. 3)
                    {
                        my $oct = (0 + $maska[$_]) & ($ipa[$_] + 0);
                        unless ($oct == $neta[$_])
                        {
                            $isme = 0;
                            last;
                        }
                    }
                    if ($isme)
                    {
                        $nettab->setAttribs({'net' => $net},
                                            {tftpserver => $ipaddr});
                        last;
                    }
                }
            }
            $nettab->commit;

            #Nothing much sane to do for the other fields at the moment?
        }
        elsif ($ent[3] eq 'UG')
        {

            #TODO: networks through gateway. and how we might care..
        }
        else
        {

            #TODO: anything to do with such entries?
        }
    }
}
1;
