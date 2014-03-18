#! /usr/bin/perl

package genrestapidoc;

my @apigroups = (
    {
        groupname => 'node', 
        resources => ['allnode', 'nodeallattr']
    },

    {
        groupname => 'network', 
        resources => ['network', 'network_allattr', 'network_attr']
    },
);

my %formathdl = (
    text => \&outtext,
);

sub outtext {
    my $def = shift;
    my $opt = shift;
    my $head = shift;

    if ($head) {
        print "\n$head\n";
    }

    my $postfix = "?userName=xxx&password=xxx&pretty=1";

    if (defined ($def->{desc})) {
        print "  $opt - $def->{desc}\n";
    }

    if (defined ($def->{usage})) {
        my @parts = split ('\|', $def->{usage});
        if ($parts[1]) {
            print "    Parameters: $parts[2]\n";
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
        }
        
        if ($parts[2] && $parts[3] && $parts[4]) {
            my ($uri, $data);
            if ($part[3] =~ /\s+/) {
                ($uri, $data) = split(/ /, $part[3]);
                print "        #curl $parts[2] -k \'https://myserver/xcatws$uri$postfix\' -H Content-Type:application/json --data \'$data\'\n";
            } else {
                print "        #curl $parts[2] -k \'https://myserver/xcatws$parts[3]$postfix\'\n";
            }
            $parts[4] =~ s/\n/\n        /g;
            print "        $parts[4]\n";
        }
        
    }
}

sub gendoc {
    my $URIdef = shift;
    my $format = shift;

    unless ($format) {
        $format = "text";
    }

    my @errmsg;

foreach my $group (@apigroups) {
    my $groupname = $group->{'groupname'};
    if (defined ($URIdef->{$groupname})) {
        foreach my $res (@{$group->{'resources'}}) {
            if (defined ($URIdef->{$groupname}->{$res})) {
                if (defined ($URIdef->{$groupname}->{$res}->{GET})) {
                    $formathdl{$format}->($URIdef->{$groupname}->{$res}->{GET}, "GET", $URIdef->{$groupname}->{$res}->{desc});
                }
                if (defined ($URIdef->{$groupname}->{$res}->{PUT})) {
                    $formathdl{$format}->($URIdef->{$groupname}->{$res}->{PUT}, "PUT");
                }
                if (defined ($URIdef->{$groupname}->{$res}->{POST})) {
                    $formathdl{$format}->($URIdef->{$groupname}->{$res}->{POST}, "POST");
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

    print @errmsg;
}
sub displayUsage {
    foreach my $group (keys %URIdef) {
        print "Resource Group: $group\n";
        foreach my $res (keys %{$URIdef{$group}}) {
            print "    Resource: $res\n";
            print "        $URIdef{$group}->{$res}->{desc}\n";
            if (defined ($URIdef{$group}->{$res}->{GET})) {
                print "            GET: $URIdef{$group}->{$res}->{GET}->{desc}\n";
            }
            if (defined ($URIdef{$group}->{$res}->{PUT})) {
                print "            PUT: $URIdef{$group}->{$res}->{PUT}->{desc}\n";
            }
            if (defined ($URIdef{$group}->{$res}->{POST})) {
                print "            POST: $URIdef{$group}->{$res}->{POST}->{desc}\n";
            }
            if (defined ($URIdef{$group}->{$res}->{DELETE})) {
                print "            DELETE: $URIdef{$group}->{$res}->{DELETE}->{desc}\n";
            }
        }
    }
}

