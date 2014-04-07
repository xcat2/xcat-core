#! /usr/bin/perl

package genrestapidoc;

my @apigroups = (
    {
        groupname => 'tokens',
        header => "Token Resources",
        desc => "The URI list which can be used to create tokens for account .",
        resources => ['tokens'],
    },
    {
        groupname => 'nodes', 
        header => "Node Resources",
        desc => "The URI list which can be used to create, query, change and manage node objects.",
        resources => ['allnode', 'nodeallattr', 'nodeattr', 'nodehost', 'nodedns', 'nodedhcp', 'nodestat', 'subnodes', 
                      'power', 'energy', 'energyattr', 'serviceprocessor', 'nextboot', 'bootstate',
                      'vitals', 'vitalsattr', 'inventory', 'inventoryattr', 'eventlog', 'beacon', 
                      'updating','filesyncing','software_maintenance','postscript', 'nodeshell', 'nodecopy',
                      ]
    },
    {
        groupname => 'groups', 
        header => "Group Resources",
        desc => "The URI list which can be used to create, query, change and manage group objects.",
        resources => ['all_groups','group_allattr','group_attr',
                      ]
    },
    {
        groupname => 'services', 
        header => "Services Resources",
        desc => "The URI list which can be used to manage the dns and dhcp services on xCAT MN.",
        resources => ['dns','dhcp','host', 'slpnodes', 'specific_slpnodes',]
    },
    {
        groupname => 'policy',
        header => "Policy Resources",
        desc => "The URI list which can be used to create, query, change and manage policy entries.",
        resources => ['policy', 'policy_allattr', 'policy_attr']
    },
    {
        groupname => 'globalconf',
        header => "Global Configuration Resources",
        desc => "The URI list which can be used to create, query, change global configuration.",
        resources => ['all_site', 'site']
    },
    {
        groupname => 'table',
        header => "Table Resources",
        desc => "URI list which can be used to create, query, change global configuration.",
        resources => ['table_nodes', 'table_rows']
    },
    {
        groupname => 'osimage',
        header => "Osimage resources",
        desc => "URI list which can be used to query, create osimage resources.",
        resources => ['osimage', 'osimage_allattr']
    },
    {
    #    groupname => 'network', 
        resources => ['network', 'network_allattr']
    },
);

my %formathdl = (
    text => \&outtext,
    wiki => \&outwiki,
);


my @errmsg;

sub outtext {
    my $def = shift;
    my $opt = shift;
    my $res = shift;

    if ($res) {
        if (defined ($res->{'desc'})) {
            print "\n$res->{'desc'}\n";
        }
        foreach (1..10) {
            if (defined ($res->{'desc'.$_})) {
                print $res->{'desc'.$_}."\n";
            }
        }
    }
                    

    my $postfix = "?userName=root&password=cluster&pretty=1";

    if (defined ($def->{desc})) {
        print "  $opt - $def->{desc}\n";
    }
    foreach (1..10) {
        if (defined ($def->{'desc'.$_})) {
            print "   ".$def->{'desc'.$_}."\n";
        }
    }

    if (defined ($def->{usage})) {
        my @parts = split ('\|', $def->{usage});
        if ($parts[1]) {
            print "    Parameters: $parts[1]\n";
        }
        if ($parts[2]) {
            print "    Returns: $parts[2]\n";
        }
    }

    if (defined ($def->{example})) {
        my @parts = split ('\|', $def->{example});
        print "    Example:\n";

        if ($parts[1]) {
            print "    $parts[1]\n";
        } else {
            push @errmsg, "Error format in:[".$def->{desc}."]\n";
        }
        
        if ($parts[2] && $parts[3] && ($parts[4] || $opt ne "GET")) {
            my ($uri, $data);
            if ($parts[3] =~ /\s+/) {
                ($uri, $data) = split(/ /, $parts[3]);
                print "        #curl -X $parts[2] -k \'https://127.0.0.1/xcatws$uri$postfix\' -H Content-Type:application/json --data \'$data\'\n";
            } else {
                print "        #curl -X $parts[2] -k \'https://127.0.0.1/xcatws$parts[3]$postfix\'\n";
            }
            $parts[4] =~ s/\n/\n        /g;
            print "        $parts[4]\n";
        } else {
            push @errmsg, "Error format in:[".$def->{desc}."]\n";
        }
        
    } else {
        push @errmsg, "Error format in:[".$def->{desc}."]\n";
    }
}

sub outwiki {
    my $def = shift;
    my $opt = shift;
    my $res = shift;

    if ($res) {
        if (defined ($res->{'desc'})) {
            print "===$res->{'desc'}===\n";
        }
        foreach (1..10) {
            if (defined ($res->{'desc'.$_})) {
                print $res->{'desc'.$_}."\n\n";
            }
        }
    }

    my $postfix = "?userName=root&password=cluster&pretty=1";

    if (defined ($def->{desc})) {
        print "===='''$opt - $def->{desc}'''====\n";
    }
    foreach (1..10) {
        if (defined ($def->{'desc'.$_})) {
            print $def->{'desc'.$_}."\n\n";
        }
    }

    if (defined ($def->{cmd})) {
        my $manpath = search_manpage($def->{cmd});

        if ($manpath) {
            print "Refer to the man page:[http://xcat.sourceforge.net".$manpath.".html ".$def->{cmd}."]\n\n";
        } else {
            print "Refer to the man page of ".$def->{cmd}." command.\n\n";
        }

    }

    if (defined ($def->{usage})) {
        my @parts = split ('\|', $def->{usage});
        if ($parts[1]) {
            print "'''Parameters:'''\n\n*$parts[1]\n";
        }
        if ($parts[2]) {
            print "'''Returns:'''\n\n*$parts[2]\n";
        }
    }

    if (defined ($def->{example})) {
        my @parts = split ('\|', $def->{example});
        print "'''Example:'''\n\n";

        if ($parts[1]) {
            print "$parts[1]\n";
        } else {
            push @errmsg, "Error format for:[".$def->{desc}."]\n";
        }
        
        if ($parts[2] && $parts[3] && ($parts[4] || $opt ne "GET")) {
            my ($uri, $data);
            if ($parts[3] =~ /\s+/) {
                ($uri, $data) = split(/ /, $parts[3]);
                print " #curl -X $parts[2] -k \'https://127.0.0.1/xcatws$uri$postfix\' -H Content-Type:application/json --data \'$data\'\n";
            } else {
                print " #curl -X $parts[2] -k \'https://127.0.0.1/xcatws$parts[3]$postfix\'\n";
            }
            $parts[4] =~ s/\n/\n /g;
            print " $parts[4]\n";
        } else {
            push @errmsg, "Error format for:[".$def->{desc}."]\n";
        }
        
    } else {
        push @errmsg, "Error format for:[".$def->{desc}."]\n";
    }
}


sub search_manpage {
    my $cmd = shift;

    if (-d "/opt/xcat/share/man") {
        my $run = "cd /opt/xcat/share/man; find . | grep \'$cmd\\.\'";
        my @output = `$run`;
        if (@output) {
            $output[0] =~ s/^\.//;
            chomp($output[0]);
            return $output[0];
        }
    }

    return undef;
}

sub gendoc {
    my $URIdef = shift;
    my $format = shift;

    unless ($format) {
        $format = "text";
    }


    foreach my $group (@apigroups) {
        my $groupname = $group->{'groupname'};
        if (defined ($URIdef->{$groupname})) {
            # display the head of resource group
            if ($format eq "text") {
                print "############################################\n";
                print "##########".$group->{'header'}."\n";                
                print $group->{'desc'}."\n";
                print "############################################\n";
            } elsif ($format eq "wiki") {
                print "==".$group->{'header'}."==\n";
                print $group->{'desc'}."\n";
            }
            foreach my $res (@{$group->{'resources'}}) {
                if (defined ($URIdef->{$groupname}->{$res})) {
                    my $headdone;
                    if (defined ($URIdef->{$groupname}->{$res}->{GET})) {
                        $formathdl{$format}->($URIdef->{$groupname}->{$res}->{GET}, "GET", $URIdef->{$groupname}->{$res});
                        $headdone = 1;
                    }
                    if (defined ($URIdef->{$groupname}->{$res}->{PUT})) {
                        if ($headdone) {
                            $formathdl{$format}->($URIdef->{$groupname}->{$res}->{PUT}, "PUT");
                        } else {
                            $formathdl{$format}->($URIdef->{$groupname}->{$res}->{PUT}, "PUT", $URIdef->{$groupname}->{$res});
                        }
                        $headdone = 1;
                    }
                    if (defined ($URIdef->{$groupname}->{$res}->{POST})) {
                        if ($headdone) {
                            $formathdl{$format}->($URIdef->{$groupname}->{$res}->{POST}, "POST");
                        } else {
                            $formathdl{$format}->($URIdef->{$groupname}->{$res}->{POST}, "POST", $URIdef->{$groupname}->{$res});
                        }
                    }
                    if (defined ($URIdef->{$groupname}->{$res}->{DELETE})) {
                        $formathdl{$format}->($URIdef->{$groupname}->{$res}->{DELETE}, "DELETE");
                    }
                } else {
                    push @errmsg, "Cannot find the definition for resource [$res]\n";
                }
            }
        } else {
            push @errmsg, "Cannot find the definition for resource group [$groupname]\n";
       } 
    }

    if (@errmsg) {
        print "\n\n\n================= Error Messages ===================\n";
        print @errmsg;
    }
}

1;
