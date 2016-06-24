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
                      'vm','vmclone','vmmigrate',
                      ]
    },
    {
        groupname => 'osimages',
        header => "Osimage resources",
        desc => "URI list which can be used to query, create osimage resources.",
        resources => ['osimage', 'osimage_allattr', 'osimage_attr', 'osimage_op']
    },
    {
        groupname => 'networks',
        header => "Network Resources",
        desc => "The URI list which can be used to create, query, change and manage network objects.",
        resources => ['allnetwork', 'network_allattr','network_attr']

    },
    {
        groupname => 'policy',
        header => "Policy Resources",
        desc => "The URI list which can be used to create, query, change and manage policy entries.",
        resources => ['policy', 'policy_allattr', 'policy_attr']
    },
    {
        groupname => 'groups', 
        header => "Group Resources",
        desc => "The URI list which can be used to create, query, change and manage group objects.",
        resources => ['all_groups','group_allattr','group_attr',
                      ]
    },
    {
        groupname => 'globalconf',
        header => "Global Configuration Resources",
        desc => "The URI list which can be used to create, query, change global configuration.",
        resources => ['all_site', 'site']
    },
    {
        groupname => 'services', 
        header => "Service Resources",
        desc => "The URI list which can be used to manage the host, dns and dhcp services on xCAT MN.",
        resources => ['dns','dhcp','host', 'slpnodes', 'specific_slpnodes',]
    },
    {
        groupname => 'tables',
        header => "Table Resources",
        desc => "URI list which can be used to create, query, change table entries.",
        resources => ['table_nodes', 'table_nodes_attrs', 'table_all_rows', 'table_rows', 'table_rows_attrs']
    },
);

my %formathdl = (
    text => \&outtext,
    wiki => \&outwiki,
    mediawiki => \&outmediawiki,
    rst => \&make_rst_format,
);


my @errmsg;

#--------------------------------------------------------------------------------

=head3   make_rst_format

    Descriptions:
        This subroutine is used to generate restapi doc in rst format
    Arguments:
        param1: The first parameter
        param2: The second parameter
        param3: The third parameter
    Returns:
        0 - success
        0 - fail
=cut

#--------------------------------------------------------------------------------
sub make_rst_format {
    my $def = shift;
    my $opt = shift;
    my $res = shift;

    if ($res) {
        if (defined ($res->{'desc'})) {
            # add \ for [ and ]
            #$res->{'desc'} =~ s/\[/\\\[/;
            #$res->{'desc'} =~ s/\]/\\\]/;
            print "$res->{'desc'}\n";
            print "-" x length($res->{'desc'}) . "\n\n";
        }
        foreach (1..10) {
            if (defined ($res->{'desc'.$_})) {
                print $res->{'desc'.$_}."\n\n";
            }
        }
    }

    my $postfix = "?userName=root&userPW=cluster&pretty=1";

    if (defined ($def->{desc})) {
        print "$opt - $def->{desc}\n";
        print "`" x length("$opt - $def->{desc}") . "\n\n";
    }
    foreach (1..10) {
        if (defined ($def->{'desc'.$_})) {
            print $def->{'desc'.$_}."\n\n";
        }
    }

    if (defined ($def->{cmd})) {
        my $manpath = search_manpage($def->{cmd});

        if ($manpath) {
            print "Refer to the man page: :doc:`$def->{cmd} <$manpath>`\n\n";
        } else {
            print "Refer to the man page of ".$def->{cmd}." command.\n\n";
        }

    }

    if (defined ($def->{usage})) {
        #$def->{usage} =~ s/\[/\\\[/;
        #$def->{usage} =~ s/\]/\\\]/;
        my @parts = split ('\|', $def->{usage});
        if ($parts[1]) {
            print "**Parameters:**\n\n* $parts[1]\n\n";
        }
        if ($parts[2]) {
            print "**Returns:**\n\n* $parts[2]\n\n";
        }
    }

    my @example_array = ();
    if (defined($def->{example})) {
        push @example_array, $def->{example};
    }
    foreach (1..10) {
        if (defined($def->{'example'.$_})) {
            push @example_array, $def->{'example'.$_};
        }
    }

    if (@example_array) {
        my $exampleno = "";
        if ($#example_array > 0) {
            $exampleno = 1;
        }
        foreach my $line (@example_array) {
            my @parts = split ('\|', $line);
            print "**Example$exampleno:** \n\n";
            if ($#example_array > 0) {
                $exampleno++;
            }

            if ($parts[1]) {
                print "$parts[1] :: \n\n";
            } else {
                push @errmsg, "Error format for:[".$def->{desc}."]\n";
            }

            if ($parts[2] && $parts[3] && ($parts[4] || $opt ne "GET")) {
                my ($uri, $data);
                if ($parts[3] =~ /\s+/) {
                    ($uri, $data) = split(/ /, $parts[3]);
                    print "\n    #curl -X $parts[2] -k \'https://127.0.0.1/xcatws$uri$postfix\' -H Content-Type:application/json --data \'$data\'\n";
                } else {
                    print "\n    #curl -X $parts[2] -k \'https://127.0.0.1/xcatws$parts[3]$postfix\'\n";
                }

                if ($parts[4]) {
                    $parts[4] =~ s/\n/\n    /g;
                    print "    $parts[4]\n\n";
                }
            } else {
                push @errmsg, "Error format for:[".$def->{desc}."]\n";
            }
        }
    } else {
        push @errmsg, "Error format for:[".$def->{desc}."]\n";
    }
}


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
                    

    my $postfix = "?userName=root&userPW=cluster&pretty=1";

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
    my @example_array = ();
    if (defined($def->{example})) {
        push @example_array, $def->{example};
    } else {
        foreach (1..10) {
            if (defined($def->{'example'.$_})) {
                push @example_array, $def->{'example'.$_};
            }
        }
    }
    if (@example_array) {
        foreach my $line (@example_array) {  
            my @parts = split ('\|', $line);
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
        }
    } else {
        push @errmsg, "Error format in:[".$def->{desc}."]\n";
    }
}

# The subroutine is used to generate restapi doc in sourceforage markdown wiki
sub outwiki {
    my $def = shift;
    my $opt = shift;
    my $res = shift;

    if ($res) {
        if (defined ($res->{'desc'})) {
            # add \ for [ and ]
            $res->{'desc'} =~ s/\[/\\\[/;
            $res->{'desc'} =~ s/\]/\\\]/;
            print "##$res->{'desc'}##\n";
        }
        foreach (1..10) {
            if (defined ($res->{'desc'.$_})) {
                print $res->{'desc'.$_}."\n\n";
            }
        }
    }

    my $postfix = "?userName=root&userPW=cluster&pretty=1";

    if (defined ($def->{desc})) {
        print "###$opt - $def->{desc}###\n";
    }
    foreach (1..10) {
        if (defined ($def->{'desc'.$_})) {
            print $def->{'desc'.$_}."\n\n";
        }
    }

    if (defined ($def->{cmd})) {
        my $manpath = search_manpage($def->{cmd});
        $manpath =~ s/\.gz//;

        if ($manpath) {
            print "Refer to the man page:[$def->{cmd}](http://xcat-docs.readthedocs.org/en/latest/guides/admin-guides/references/index.html#xcat-man-pages).\n\n";
        } else {
            print "Refer to the man page of ".$def->{cmd}." command.\n\n";
        }

    }

    if (defined ($def->{usage})) {
        $def->{usage} =~ s/\[/\\\[/;
        $def->{usage} =~ s/\]/\\\]/;
        my @parts = split ('\|', $def->{usage});
        if ($parts[1]) {
            print "**Parameters:**\n\n* $parts[1]\n\n";
        }
        if ($parts[2]) {
            print "**Returns:**\n\n* $parts[2]\n\n";
        }
    }

    my @example_array = ();
    if (defined($def->{example})) {
        push @example_array, $def->{example};
    }
    foreach (1..10) {
        if (defined($def->{'example'.$_})) {
            push @example_array, $def->{'example'.$_};
        }
    }

    if (@example_array) {
        my $exampleno = "";
        if ($#example_array > 0) {
            $exampleno = 1;
        }
        foreach my $line (@example_array) {
            my @parts = split ('\|', $line);
            print "**Example$exampleno:**\n";
            if ($#example_array > 0) {
                $exampleno++;
            }

            if ($parts[1]) {
                print "$parts[1]\n";
            } else {
                push @errmsg, "Error format for:[".$def->{desc}."]\n";
            }
        
            if ($parts[2] && $parts[3] && ($parts[4] || $opt ne "GET")) {
                my ($uri, $data);
                if ($parts[3] =~ /\s+/) {
                    ($uri, $data) = split(/ /, $parts[3]);
                    print "\n    #curl -X $parts[2] -k \'https://127.0.0.1/xcatws$uri$postfix\' -H Content-Type:application/json --data \'$data\'\n";
                } else {
                    print "\n    #curl -X $parts[2] -k \'https://127.0.0.1/xcatws$parts[3]$postfix\'\n";
                }

                if ($parts[4]) {
                    $parts[4] =~ s/\n/\n    /g;
                    print "    $parts[4]\n\n---\n";
                } else {
                    print "\n---\n";
                }
            } else {
                push @errmsg, "Error format for:[".$def->{desc}."]\n";
            }
        }
    } else {
        push @errmsg, "Error format for:[".$def->{desc}."]\n";
    }
}


# outmediawiki is the backup subroutine to generate restapi doc for mediawiki 
sub outmediawiki {
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

    my $postfix = "?userName=root&userPW=cluster&pretty=1";

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
            print "Refer to the man page:[http://xcat-docs.readthedocs.org/en/latest/guides/admin-guides/references/index.html#xcat-man-pages ".$def->{cmd}."]\n\n";
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

    my @example_array = ();
    if (defined($def->{example})) {
        push @example_array, $def->{example};
    } else {
        foreach (1..10) {
            if (defined($def->{'example'.$_})) {
                push @example_array, $def->{'example'.$_};
            }
        }
    }

    if (@example_array) {
        foreach my $line (@example_array) {
            my @parts = split ('\|', $line);
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
        }
    } else {
        push @errmsg, "Error format for:[".$def->{desc}."]\n";
    }
}


sub search_manpage {
    my $cmd = shift;

    if (-d "../../docs/source/guides/admin-guides/references/") {
        my $run = "find ../../docs/source/guides/admin-guides/references/ | grep \'$cmd\\.\'";
        my @output = `$run`;
        if (@output) {
            $output[0] =~ s/..\/..\/docs\/source//;
            $output[0] =~ s/\.rst$//;
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

    if ($format eq "wiki") {
        print "![](http://xcat.org/images/Official-xcat-doc.png)\n\n";
        print "\n[TOC]\n";
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
                print "#".$group->{'header'}."#\n";
                print $group->{'desc'}."\n";
                print "\n\n---\n\n---\n";
            } elsif ($format eq "mediawiki") {
                print "==".$group->{'header'}."==\n";
                print $group->{'desc'}."\n";
            } elsif ($format eq "rst") {
                print $group->{'header'} . "\n";
                print "=" x length($group->{'header'}) . "\n\n";
                print $group->{'desc'}."\n\n";
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
