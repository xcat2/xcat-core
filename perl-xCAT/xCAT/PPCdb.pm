# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCdb;
use strict;
use xCAT::Table;
use xCAT::GlobalDef;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::NetworkUtils;
require xCAT::data::ibmhwtypes;

###########################################
# Factory defaults
###########################################
my %logon = (
    hmc   => ["hscroot","abc123"],
    ivm   => ["padmin", "padmin"],
    fsp   => ["admin",  "admin"],
    bpa   => ["admin",  "admin"],
    frame => ["admin",  "admin"],    
    cec   => ["admin",  "admin"], 
);

###########################################
# Tables based on HW Type
###########################################
my %hcptab = (
    hmc   => "ppchcp",
    ivm   => "ppchcp",
    fsp   => "ppcdirect",
    bpa   => "ppcdirect",
    frame => "ppcdirect",
    cec   => "ppcdirect",
    blade => "mpa",    
);

###########################################
# The default groups of hcp
###########################################
my %defaultgrp = (
    hmc   => "hmc",
    ivm   => "ivm",
    fsp   => "fsp",
    bpa   => "bpa",
    frame => "frame",
    cec   => "cec",
    blade => "blade", 
);
my %globlehwtype = (
    fsp   => $::NODETYPE_FSP,
    bpa   => $::NODETYPE_BPA,
    lpar  => $::NODETYPE_LPAR,
    hmc   => $::NODETYPE_HMC,
    ivm   => $::NODETYPE_IVM,
    frame => $::NODETYPE_FRAME,
    cec   => $::NODETYPE_CEC,
);

my %globalnodetype = (
    fsp  => $::NODETYPE_PPC,
    bpa  => $::NODETYPE_PPC,
    cec  => $::NODETYPE_PPC,
    frame=> $::NODETYPE_PPC,
    hmc  => $::NODETYPE_PPC,
    ivm  => $::NODETYPE_PPC,
    lpar =>"$::NODETYPE_PPC,$::NODETYPE_OSI"
);

##########################################################################
# Adds a node to the xCAT databases
##########################################################################
sub add_ppc {

    my $hwtype   = shift;
    my $values   = shift;
    my $not_overwrite = shift;
    my $otherinterfaces = shift;
    my @tabs     = qw(ppc vpd nodehm nodelist nodetype hosts mac); 
    my %db       = ();
    ###################################
    # Open database needed
    ###################################
    foreach ( @tabs ) {
        $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>0 );
        if ( !$db{$_} ) {
            return( "Error opening '$_'" );
        }
    }
    ###################################
    # Update tables 
    ###################################
    foreach ( @$values ) {
        my ($type,
            $name,
            $id,
            $model,
            $serial,
            $side,
            $server,
            $pprofile,
            $parent,
            $ips,
            $mac ) = split /,/;
        ###############################
        # Update nodetype table
        ###############################
        if ( $type =~ /^(fsp|bpa|hmc|ivm|frame|cec)$/ ) {
            $db{nodetype}->setNodeAttribs( $name,{nodetype=>'ppc'} );
            $db{nodetype}{commit} = 1;
        } elsif ($type =~ /^lpar$/) {
            $db{nodetype}->setNodeAttribs( $name,{nodetype=>'ppc,osi'} );
            $db{nodetype}{commit} = 1;
        }
        ###############################
        # If cannot be overwroten, get
        # old data firstly
        ###############################
        my $mgt = $hwtype;
        
        # Specify CEC and Frame's mgt as fsp and bpa
        if ( $type =~ /^cec$/)  {
            $mgt = "hmc";
        }
        if ( $type =~ /^frame$/)  {
            $mgt = "bpa";
        }    
        
             
        my $cons= $hwtype;
        if ( $not_overwrite)
        {
            my $enthash = $db{ppc}->getNodeAttribs( $name, [qw(hcp id pprofile parent)]);
            if ( $enthash )
            {
                $server   = $enthash->{hcp} if ($enthash->{hcp});
                $id       = $enthash->{id}  if ( $enthash->{id});
                $pprofile = $enthash->{pprofile} if ( $enthash->{pprofile});
                $parent   = $enthash->{parent} if ( $enthash->{parent});
            }
            $enthash = $db{nodehm}->getNodeAttribs( $name, [qw(mgt)]);
            if ( $enthash )
            {
                $mgt= $enthash->{mgt} if ( $enthash->{mgt});
                $cons= $enthash->{cons} if ( $enthash->{cons});
            }
            $enthash = $db{vpd}->getNodeAttribs( $name, [qw(mtm serial)]);
            if ( $enthash )
            {
                $model = $enthash->{mtm} if ( $enthash->{mtm});
                $serial= $enthash->{serial} if ( $enthash->{serial});
            }
        }

        ###############################
        # Update ppc table
        ###############################
        if ( $type =~ /^(fsp|bpa|lpar|frame|cec|hmc)$/ ) {
            $db{ppc}->setNodeAttribs( $name,
               { hcp=>$server,
                 id=>$id,
                 pprofile=>$pprofile,
                 parent=>$parent,
                 nodetype=>$globlehwtype{$type},
               }); 
            $db{ppc}{commit} = 1;

            ###########################
            # Update nodelist table
            ###########################
            updategroups( $name, $db{nodelist}, $type );
            my $tmp_group = xCAT::data::ibmhwtypes::parse_group($model);
            if (defined($tmp_group)) {
                updategroups($name, $db{nodelist}, $tmp_group);
            }
            if ( $type =~ /^(fsp|bpa)$/ )  {
                $db{nodelist}->setNodeAttribs( $name, {hidden => '1'});
            } else {
                $db{nodelist}->setNodeAttribs( $name, {hidden => '0'});
            }
            
            $db{nodelist}{commit} = 1;

            ###########################
            # Update nodehm table
            ###########################
            if($type =~ /^lpar$/){
                $db{nodehm}->setNodeAttribs( $name, {mgt=>$mgt,cons=>$cons} );
            } else {
                $db{nodehm}->setNodeAttribs( $name, {mgt=>$mgt} );
            }
            $db{nodehm}{commit} = 1;
        }
        ###############################
        # Update vpd table
        ###############################
        if ( $type =~ /^(fsp|bpa)$/ ) {
            $db{vpd}->setNodeAttribs( $name, 
                { mtm=>$model,
                  serial=>$serial,
                  side=>$side
                 });
        }                     
        if ( $type =~ /^(frame|cec)$/ ) {
            $db{vpd}->setNodeAttribs( $name, 
                { mtm=>$model,
                  serial=>$serial,
                 }); 
        }
        $db{vpd}{commit} = 1;

        ###############################
        # Update hosts table
        ###############################
        if ( $otherinterfaces ) {
            $db{hosts}->setNodeAttribs( $name,
               { otherinterfaces=>$ips });
        } else {
            $db{hosts}->setNodeAttribs( $name,
                { ip=>$ips });
        }
        $db{hosts}{commit} = 1;
        
        ###############################
        # Update mac table
        ###############################
        if ( $mac ) {
            $db{mac}->setNodeAttribs( $name,
                { mac=>$mac });
        }
        $db{mac}{commit} = 1;
    }

    ###################################
    # Commit changes 
    ###################################
    foreach ( @tabs ) {
        if ( exists( $db{$_}{commit} )) {
           $db{$_}->commit;
        }
    }
    return undef;
}
##########################################################################
# Update lpar information in the xCAT databases
##########################################################################
sub update_lpar {
    my $hwtype = shift;
    my $values = shift;
    my $write = shift;
    my @tabs     = qw(ppc vpd nodehm nodelist nodetype ppcdirect hosts mac); 
    my %db       = ();
    my @update_list = ();
    my @write_list = ();
    ###################################
    # Open database needed
    ###################################
    foreach ( @tabs ) {
        $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>0 );
        if ( !$db{$_} ) {
            return( "Error opening '$_'" );
        }
    }
    my @vpdlist = $db{vpd}->getAllNodeAttribs(['node','serial','mtm','side']);
    my @ppclist = $db{ppc}->getAllNodeAttribs(['node','hcp','id',
                                               'pprofile','parent','nodetype',
                                               'comments', 'disable']);
    #      'cec,cec1,,8246-L1D,100A9DA,,cec1,,cec1',
    #      'lpar,10-0A9DA,1,8246-L1D,100A9DA,,cec1,,cec1'
    my %ppchash = ();
    my %vpdhash = ();
    foreach my $ppcent (@ppclist) {
        if ($ppcent->{id} and $ppcent->{nodetype} and $ppcent->{nodetype} eq "lpar") {
            my $key = $ppcent->{node};
            $ppchash{$key}{id} = $ppcent->{id};
            $ppchash{$key}{parent} = $ppcent->{parent};
        }
    }
    foreach my $vpdent (@vpdlist)
    {
        my $key = $vpdent->{node};
        $vpdhash{$key}{mtm} = $vpdent->{mtm};
        $vpdhash{$key}{serial} = $vpdent->{serial};
    }
    my @ppc_lpars = keys %ppchash; 
    foreach my $value ( @$values ) {
        my ($ttype,
            $tname,
            $tid,
            $tmtm,
            $tsn,
            $tside,
            $server,
            $pprofile,
            $parent) = split /,/, $value;
            if ($ttype ne "lpar") {
                push @update_list, $value;
                next;
            }
            my $find_node = undef;
            foreach my $tmp_node (@ppc_lpars) {
                if ($ppchash{$tmp_node}{id} eq $tid) {
                    if (exists($ppchash{$tmp_node}{parent}) and $ppchash{$tmp_node}{parent} eq $parent) {
                        $find_node = $tmp_node;
                        last;
                    } elsif ($vpdhash{$tmp_node}{mtm} eq $tmtm and $vpdhash{$tmp_node}{serial} eq $tsn) {
                        $find_node = $tmp_node;
                        last;
                    }
                }
            }
            if (defined($find_node)) {
                if ( update_node_attribs($hwtype, $ttype, $find_node, $tid, $tmtm, $tsn, $tside,
                                    $server, $pprofile, $parent, "", \%db, $tname, \@ppclist))
                {
                    $value =~ s/^$ttype,$tname,/$ttype,$find_node,/; 
                    push @update_list, $value;  
                }
            } elsif (defined($write)) {
                push @write_list, $value;
            }
    }
    if (defined($write)) {
        &add_ppc($hwtype, \@write_list);
        return ([@update_list,@write_list]);
    } else {
        foreach ( @tabs ) {
            if ( exists( $db{$_}{commit} )) {
               $db{$_}->commit;
            }
        }
        return \@update_list;
    }
}

##########################################################################
# Update nodes in the xCAT databases
##########################################################################
sub update_ppc {

    my $hwtype   = shift;
    my $values   = shift;
    my $not_overwrite = shift;
    my @tabs     = qw(ppc vpd nodehm nodelist nodetype ppcdirect hosts mac); 
    my %db       = ();
    my @update_list = ();

    ###################################
    # Open database needed
    ###################################
    foreach ( @tabs ) {
        $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>0 );
        if ( !$db{$_} ) {
            return( "Error opening '$_'" );
        }
    }
    my @vpdlist = $db{vpd}->getAllNodeAttribs(['node','serial','mtm','side']);
    my @hostslist = $db{hosts}->getAllNodeAttribs(['node','ip']);
    my @ppclist = $db{ppc}->getAllNodeAttribs(['node','hcp','id',
                                               'pprofile','parent','supernode',
                                               'comments', 'disable']);
    my @maclist = $db{mac}->getAllNodeAttribs(['node','mac']);
    ###################################
    # Need to do database migration first
    ###################################
    foreach my $value ( @$values ) {
        my ($ttype,
            $tname,
            $tid,
            $tmtm,
            $tsn,
            $tside,
            $server,
            $pprofile,
            $parent,
            $ips ) = split /,/, $value;
        if ( $ttype eq 'cec' )
        {
            my $hostname =  get_host($tname, "FSP", $tmtm, $tsn, "", "", $tid, "","");
            if ($hostname ne $tname) 
            {
                $hostname =~ /\-(\w)$/;
                if ($1 =~ /^(A|B)$/)
                {
                    $tside = $1;
                }
                if ( update_node_attribs($hwtype, $ttype, $hostname, $tid, $tmtm, $tsn, $tside,
                                    $server, $pprofile, $parent, $ips, \%db, $tname, \@ppclist))
                {
                    push @update_list, $value;  
                }
            }
        } elsif ( $ttype eq 'frame' )
        {
            my $hostname =  get_host($tname, "BPA", $tmtm, $tsn, "", "", $tid, "","");
            if ($hostname ne $tname) 
            {
                $hostname =~ /\-(\w)$/;
                if ($1 =~ /^(A|B)$/)
                {
                    $tside = $1;
                }

                if ( update_node_attribs($hwtype, $ttype, $hostname, $tid, $tmtm, $tsn, $tside,
                                    $server, $pprofile, $parent, $ips, \%db, $tname, \@ppclist))
                {
                    push @update_list, $value;  
                }
            }   
        } 
    }        
        
    ###################################
    # Update CEC in tables 
    ###################################
    foreach my $value ( @$values ) {
        my ($type,
            $name,
            $id,
            $model,
            $serial,
            $side,
            $server,
            $pprofile,
            $parent,
            $ips ) = split /,/, $value;
        next if ( $type ne 'cec' );
        my $predefined_node = undef;
        foreach my $vpdent (@vpdlist)
        {
            if ( $vpdent->{mtm} eq $model && $vpdent->{serial} eq $serial )
            {
                $predefined_node = $vpdent->{node};
                if ( update_node_attribs($hwtype, $type, $name, $id, $model, $serial, $side,
                                    $server, $pprofile, $parent, $ips,
                                    \%db, $predefined_node, \@ppclist))
                {
                    push @update_list, $value;
                }
            }
        }

    }

    my @newppclist = $db{ppc}->getAllNodeAttribs(['node','hcp','id',
                                               'pprofile','parent','supernode',
                                               'comments', 'disable']);
    ###################################
    # Update FRAME in tables 
    ###################################
    foreach my $value ( @$values ) {
        my ($type,
            $name,
            $id,
            $model,
            $serial,
            $side,
            $server,
            $pprofile,
            $parent,
            $ips ) = split /,/, $value;
         
        next if ( $type ne 'frame');

        my $predefined_node = undef;
        foreach my $vpdent (@vpdlist)
        {
            if ( $vpdent->{mtm} eq $model && $vpdent->{serial} eq $serial && $vpdent->{side} eq $side )
            {
                $predefined_node = $vpdent->{node};
 
                if (update_node_attribs($hwtype, $type, $name, $id, $model, $serial, $side,
                                    $server, $pprofile, $parent, $ips, 
                                    \%db, $predefined_node, \@newppclist))
                {
                    push @update_list, $value;
                }
            }
        }

    }

    ###################################
    # Commit changes 
    ###################################
    foreach ( @tabs ) {
        if ( exists( $db{$_}{commit} )) {
           $db{$_}->commit;
        }
    }
    return \@update_list;
}

##########################################################################
# Update one node in the xCAT databases
##########################################################################
sub update_node_attribs
{
    my $mgt = shift;
    my $type = shift;
    my $name = shift;
    my $id = shift;
    my $model = shift;
    my $serial = shift;
    my $side   = shift;
    my $server = shift;
    my $pprofile = shift;
    my $parent = shift;
    my $ips = shift;
    my $db = shift;
    my $predefined_node = shift;
    my $ppclist = shift;

    my $updated = undef;
    my $namediff = $name ne $predefined_node;
    my $key_col = { node=>$predefined_node};

    #############################
    # update vpd table
    #############################
    my $vpdhash = $db->{vpd}->getNodeAttribs( $predefined_node, [qw(mtm serial)]);
    if ( $model ne $vpdhash->{mtm} or $serial ne $vpdhash->{serial} or $namediff)
    {
        $db->{vpd}->delEntries( $key_col) if ( $namediff);
        $db->{vpd}->setNodeAttribs( $name, { mtm=>$model, serial=>$serial, side=>$side});
        $db->{vpd}->{commit} = 1;
        $updated = 1;
    }

    ###########################
    # Update ppcdirect table
    ###########################
    my @users = qw(HMC admin general);
    foreach my $user ( @users ) {
        my $pwhash = $db->{ppcdirect}->getAttribs( {hcp=>$predefined_node,username=>$user}, qw(password comments disable));  # need regx 
        if ( $pwhash )
        {
            if ( $namediff )
            {
                $db->{ppcdirect}->delEntries( {hcp=>$predefined_node,username=>$user}) if ( $namediff);;
                $db->{ppcdirect}->setAttribs({hcp=>$name,username=>$user},
                        {password=>$pwhash->{password},
                        comments=>$pwhash->{comments},
                        disable=>$pwhash->{disable}});
                $db->{ppcdirect}->{commit} = 1;
                $updated = 1;
            }
        }
    }

    #############################
    # update ppc table
    #############################
    my $ppchash = $db->{ppc}->getNodeAttribs( $predefined_node, [qw(hcp id pprofile parent)]);
    if ( $ppchash->{parent} ne $predefined_node ) 
    {
        $parent = $ppchash->{parent};
    }

    if ( $server ne $ppchash->{hcp} or
         $id     ne $ppchash->{id} or
         $pprofile ne $ppchash->{pprofile} or
         $parent ne $ppchash->{parent} or
         $type ne $ppchash->{nodetype} or
         $namediff)
    {
        $db->{ppc}->delEntries( $key_col) if ( $namediff);
        $db->{ppc}->setNodeAttribs( $name,
                { hcp=>$server,
                id=>$id,
                pprofile=>$pprofile,
                parent=>$parent,
                nodetype=>$globlehwtype{$type},
                }); 
        if ( $namediff)
        {
            for my $ppcent (@$ppclist)
            {
                next if ($ppcent->{node} eq $predefined_node);
                if ($ppcent->{parent} eq $predefined_node)
                {
                    $db->{ppc}->setNodeAttribs( $ppcent->{node}, {parent=>$name});
                }
            }
        }
        $db->{ppc}->{commit} = 1;
        $updated = 1;
    }

    ###########################
    # Update nodehm table
    ###########################
    my $nodehmhash = $db->{nodehm}->getNodeAttribs( $predefined_node, [qw(mgt)]);
    if ( $mgt ne $nodehmhash->{mgt} or $namediff)
    {
        $db->{nodehm}->delEntries( $key_col) if ( $namediff);
        $db->{nodehm}->setNodeAttribs( $name, {mgt=>$mgt} );
        $db->{nodehm}->{commit} = 1;
        $updated = 1;
    }

    ###########################
    # Update nodetype table
    ###########################
    my $nodetypehash = $db->{nodetype}->getNodeAttribs( $predefined_node, [qw(nodetype)]);
    if ( $type ne $nodetypehash->{nodetype} or $namediff)
    {
        $db->{nodetype}->delEntries( $key_col) if ( $namediff);
        $db->{nodetype}->setNodeAttribs( $name,{nodetype=>$globalnodetype{$type}} );
        $db->{nodetype}->{commit} = 1;
        $updated = 1;
    }

    ###########################
    # Update nodelist table
    ###########################
    my $nodelisthash = $db->{nodelist}->getNodeAttribs( $predefined_node, [qw(groups status appstatus primarysn comments disable)]);
    if ( $namediff)
    {
        updategroups( $name, $db->{nodelist}, $type );
        my $tmp_group = xCAT::data::ibmhwtypes::parse_group($model);
        if (defined($tmp_group)) {
            updategroups($name, $db->{nodelist}, $tmp_group);
        }
        $db->{nodelist}->setNodeAttribs( $name, {status=>$nodelisthash->{status},
                                                 appstatus=>$nodelisthash->{appstatus},
                                                 primarysn=>$nodelisthash->{primarysn},
                                                 comments=>$nodelisthash->{comments},
                                                 disable=>$nodelisthash->{disable}
                                               });
        $db->{nodelist}->delEntries( $key_col);
        $db->{nodelist}->{commit} = 1;
        $updated = 1;
    }

    ###########################
    # Update hosts table
    ###########################
    my $hostslisthash = $db->{hosts}->getNodeAttribs( $predefined_node, [qw(ip otherinterfaces)]);
    if ( $namediff )
    {
        $db->{hosts}->delEntries( $key_col);
        $db->{hosts}->setNodeAttribs( $name,{ip=>$ips,
                                             otherinterfaces=>$hostslisthash->{otherinterfaces}
                                            } );
        $db->{hosts}->{commit} = 1;
        $updated = 1;
    }

    ###########################
    # Update mac table
    ###########################
    my $maclisthash = $db->{mac}->getNodeAttribs( $predefined_node, [qw(mac)]);
    if ( $namediff )
    {
        $db->{mac}->delEntries( $key_col);
        $db->{mac}->setNodeAttribs( $name,{mac=>$maclisthash->{mac}} );
        $db->{mac}->{commit} = 1;
        $updated = 1;
    }

    return $updated;
}

##########################################################################
# Updates the nodelist.groups attribute 
##########################################################################
sub updategroups {

    my $name   = shift;
    my $tab    = shift;
    my $hwtype = shift;

    ###############################
    # Get current value 
    ###############################
    my ($ent) = $tab->getNodeAttribs( $name, ['groups'] );
    my @list = ( lc($hwtype), "all" );

    ###############################
    # Keep any existing groups
    ###############################
    if ( defined($ent) and $ent->{groups} ) {
        push @list, split( /,/, $ent->{groups} );
    }
    ###############################
    # Remove duplicates
    ###############################
    my %saw;
    @saw{@list} = ();
    @list = keys %saw;

    $tab->setNodeAttribs( $name, {groups=>join(",",@list)} );
}


##########################################################################
# Adds an HMC/IVM to the xCAT database
##########################################################################
sub add_ppchcp {

    my $hwtype = shift;
    my $values = shift;
    my @tabs   = qw(ppchcp nodehm nodelist nodetype mac ppc vpd);
    my %db     = ();

    my ($name, $mac, $mtm, $sn, $ip) = split ',', $values;

    ###################################
    # Open database needed
    ###################################
    foreach ( @tabs ) {
        $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>1 );
        if ( !$db{$_} ) {
            return( "Error opening '$_'" );
        }
    }
    ###################################
    # Update ppchcp table
    ###################################
    my ($ent) = $db{ppchcp}->getNodeAttribs( $name,'hcp');
    if ( !defined($ent) ) {
        $db{ppchcp}->setAttribs( {hcp=>$name}, 
            { username=>"",
              password=>""
            });
    }
    ###################################
    # Update nodehm table
    ###################################
    $db{nodehm}->setNodeAttribs( $name, {mgt=>lc($hwtype)} );
    
    ###################################
    # Update nodetype table
    ###################################
    $db{nodetype}->setNodeAttribs( $name, {nodetype=>$globalnodetype{$hwtype}});
    $db{ppc}->setNodeAttribs( $name, {nodetype=>$globlehwtype{$hwtype}});

    ###################################
    # Update mac table
    ###################################
     $db{mac}->setNodeAttribs( $name, {mac=>$mac});
    ###################################
    # Update vpd table
    ###################################
     $db{vpd}->setNodeAttribs( $name, {mtm=>$mtm});
     $db{vpd}->setNodeAttribs( $name, {serial=>$sn});

    ###################################
    # Update nodelist table
    ###################################
    updategroups( $name, $db{nodelist}, $hwtype );
    return undef;
}


##########################################################################
# Removes a node from the xCAT databases
##########################################################################
sub rm_ppc {

    my $node = shift;
    my @tabs = qw(ppc nodehm nodelist);

    foreach ( @tabs ) {
        ###################################
        # Open table
        ###################################
        my $tab = xCAT::Table->new($_);
        if ( !$tab ) {
            return( "Error opening '$_'" );
        }
        ###############################
        # Remove entry
        ###############################
        $tab->delEntries( {'node'=>$node} );
    }
    return undef;
}



##########################################################################
# Adds a Management-Module or RSA to the appropriate tables
##########################################################################
sub add_systemX {

    my $hwtype = shift;
    my $name   = shift;
    my $data   = shift;
    my @tabs   = qw(mpa mp nodehm nodelist);
    my %db     = ();

    ###################################
    # Open database needed
    ###################################
    foreach ( @tabs ) {
        $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>1 );
        if ( !$db{$_} ) {
            return( "Error opening '$_'" );
        }
    }
    ###################################
    # Update mpa table
    ###################################
    my ($ent) = $db{mpa}->getNodeAttribs( $name,'mpa');
    if ( !defined($ent) ) {
        $db{mpa}->setAttribs( {mpa=>$name}, 
            { username=>"",
              password=>""
            });
    }
    ###################################
    # Update mp table
    ###################################
    $db{mp}->setNodeAttribs( $name,
        { mpa=>$name,
          id=>"0"
        }); 

    ###################################
    # Update nodehm table
    ###################################
    $db{nodehm}->setNodeAttribs( $name, {mgt=>"blade"} );

    ###################################
    # Update nodelist table
    ###################################
    updategroups( $name, $db{nodelist}, $hwtype );
    return undef;
}



##########################################################################
# Get userids and passwords from tables
##########################################################################
sub credentials {

    my $server = shift;
    my $hwtype = shift;
    my $user   = shift;
    my $pass   = undef;
    my $user_specified = $user;
    if ( !$user_specified or $user eq @{$logon{$hwtype}}[0])
    {
        $user = @{$logon{$hwtype}}[0];
        $pass = @{$logon{$hwtype}}[1];
    }

    ###########################################
    # find parent for fsp/bpa, use parent's attributes first
    ###########################################
    my $ntype = xCAT::DBobjUtils->getnodetype($server, "ppc");
    if ($ntype =~ /^(fsp|bpa)$/)  {
        my $ptab =  xCAT::Table->new('ppc');
        if ($ptab)  {
            my $parent = $ptab->getNodeAttribs($server, ["parent"]);
            if ($parent and $parent->{parent})  {
                my $ptype = xCAT::DBobjUtils->getnodetype($parent->{parent}, "ppc");
                if (($ptype =~ /^cec$/ and $ntype =~ /^fsp$/) or ($ptype =~ /^frame$/ and $ntype =~ /^bpa$/))
                {
                    $server = $parent->{parent};
                }
            }
        }
    }
    ###########################################
    # Check passwd tab
    ###########################################
    #my $tab = xCAT::Table->new( 'passwd' );
    #if ( $tab ) {
    #my $ent;
    #    if ( $user_specified)
    #    {
    #        ($ent) = $tab->getAttribs( {key=>$hwtype,username=>$user},qw(password));
    #    }
    #    else
    #    {
    #        ($ent) = $tab->getAttribs( {key=>$hwtype}, qw(username password));
    #    }
    #    if ( $ent ) {
    #        if (defined($ent->{password})) { $pass = $ent->{password}; }
    #        if (defined($ent->{username})) { $user = $ent->{username}; }
    #    }
    #}
    my ($ent) = get_usr_passwd($hwtype, $user); 
    if ($ent) {
        if (defined($ent->{password})) { $pass = $ent->{password};}
        if (defined($ent->{username})) { $user = $ent->{username};}
    }
    ##########################################
    # Check table based on specific node 
    ##########################################
    my $tab = xCAT::Table->new( $hcptab{$hwtype} );
    if ( $tab ) {
        my $ent;
        if ( $user_specified) 
        { # need regx
            #($ent) = $tab->getAttribs( {hcp=>$server,username=>$user},qw(password));
            #($ent) = $tab->getNodeSpecAttribs( $server, {username=>$user},qw(password));
            my @output = $tab->getNodeAttribs($server, qw(username password));
            foreach my $tmp_entry (@output) {
                if ($tmp_entry->{username} =~ /^$user$/) {
                    $ent = $tmp_entry;
                    last;
                }
            }
        }
        else
        {
            ($ent) = $tab->getNodeAttribs( $server, qw(username password));
        }
        if ( $ent){
            if (defined($ent->{password})) { $pass = $ent->{password}; }
            if (defined($ent->{username})) { $user = $ent->{username}; }
        }
    ##############################################################
    # If no user/passwd found, check if there is a default group
    ##############################################################
        else
        {
            if ( $user_specified)
            { # need regx
                #($ent) = $tab->getAllAttribs( {hcp=>$defaultgrp{$hwtype},username=>$user},qw(password));
                #($ent) = $tab->getNodeSpecAttribs( $defaultgrp{$hwtype}, {username=>$user},qw(password));
                my @output = $tab->getNodeAttribs( $defaultgrp{$hwtype}, qw(username password));
                foreach my $tmp_entry (@output) {
                    if ($tmp_entry->{username} =~ /^$user$/) {
                        $ent = $tmp_entry;
                        last;
                    }
                }
            }
            else
            {
                ($ent) = $tab->getNodeAttribs( $defaultgrp{$hwtype}, qw(username password));
            }
            if ( $ent){
                if (defined($ent->{password})) { $pass = $ent->{password}; }
                if (defined($ent->{username})) { $user = $ent->{username}; }
            }
        }
    }
    return( $user,$pass );
}

##########################################################################
# Get password for user in 'passwd' table, if doesn't exist, use default
# password for this user.
##########################################################################
my %power_accounts = (
    HMC => 'abc123',
    general => 'general',
    admin => 'admin',    
);
my %default_passwd_accounts = (
    system  => { root => 'cluster',},
    hmc     => { hscroot => 'abc123',},
    fsp     => \%power_accounts,
    bpa     => \%power_accounts,
    frame   => \%power_accounts,
    cec     => \%power_accounts,
    blade   => { USERID => 'PASSW0RD',
                 HMC => 'PASSW0RD'},
    ipmi    => { USERID => 'PASSW0RD',},
    ivm     => { padmin => 'padmin',},
    vmware  => { root => '',},
    vcenter => { Administrator => ''},
);

sub get_usr_passwd {
    my $key = shift;
    if ($key && ($key =~ /xCAT::/)) {
        $key = shift;
    }
    my $user = shift;
    my $ent;
    my $passwdtab = xCAT::Table->new('passwd');
    if (!$passwdtab) {
        return undef;
    }
    if ($user) {
        ($ent) = $passwdtab->getAttribs({key => $key, username => $user}, qw(password cryptmethod));
    } else {
        ($ent) = $passwdtab->getNodeAttribs($key, qw(username password));
    }
    if (!$ent) {
        if ($key eq "cec") {
            $key = "fsp";
        } elsif ($key eq "frame") {
            $key = "bpa";
        }
        if ($user) {
            ($ent) = $passwdtab->getAttribs({key => $key, username => $user}, qw(password cryptmethod));
        } else {
            ($ent) = $passwdtab->getNodeAttribs($key, qw(username password));
        }
    }
    if (!$ent or !$ent->{password}) {
        my $hash = $default_passwd_accounts{$key};
        if (!$hash or ($user and !defined($hash->{$user}))) {
            return undef;
        }
        if (!$user) {
            my @tmp_keys = keys (%$hash);
            $user = $tmp_keys[0];
        }
        $ent->{username} = $user;
        $ent->{password} = $hash->{$user};
    }
    return $ent;
}

##########################################################################
# Set userids and passwords to tables
##########################################################################
sub update_credentials 
{

    my $server = shift;
    my $hwtype = shift;
    my $user   = shift;
    my $pass   = shift;

    ##########################################
    # Set password to specific table
    ##########################################
    my $tab = xCAT::Table->new( $hcptab{$hwtype} );
    if ( $tab ) {
        my $ent;
        $tab->setAttribs( {hcp=>$server, username=>$user},{password=>$pass} );
    }

    return undef;
}
#############################################################################
# used for FSP/BPA redundancy database migration
# if return something, it means it will use the old data name
# or new data name
# if return undef, it means the ip is not invalid and won't make any definition
#############################################################################
sub get_host {
    my $nodename        = shift;
    my $type            = shift;
    my $mtm             = shift;
    my $sn              = shift;
    my $side            = shift;
    my $ip              = shift;
    my $cage_number     = shift;
    my $parmtm          = shift;
    my $parsn           = shift;
    my $pname           = shift;
    my $flagref         = shift;

    #######################################
    # Extract IP from URL
    #######################################
    if ($ip)
    {
        my $nets = xCAT::NetworkUtils::my_nets();
        my $avip = getip_from_iplist( $ip, $nets);
        #if ( !defined( $ip )) {
        #    return undef;
        #}
    }
    # get the information of existed nodes to do the migration

    read_from_table() unless (%::OLD_DATA_CACHE);
    foreach my $oldnode ( keys %::OLD_DATA_CACHE )
    {
        my $tmpmtm    = @{$::OLD_DATA_CACHE{$oldnode}}[0];
        my $tmpsn     = @{$::OLD_DATA_CACHE{$oldnode}}[1];
        my $tmpside   = @{$::OLD_DATA_CACHE{$oldnode}}[2];
        my $tmpip     = @{$::OLD_DATA_CACHE{$oldnode}}[3];
        my $tmpid     = @{$::OLD_DATA_CACHE{$oldnode}}[4];
        my $tmpparent = @{$::OLD_DATA_CACHE{$oldnode}}[5];
        my $tmptype   = uc(@{$::OLD_DATA_CACHE{$oldnode}}[6]);
        my $unmatched = @{$::OLD_DATA_CACHE{$oldnode}}[7];

        # used to match fsp defined by xcatsetup
        # should return fast to save time  
        if (($type eq "BPA" or $type eq "FSP") and ($tmptype eq $type) and $pname and $side) {
            if ($pname eq $tmpparent and $side eq $tmpside)  {
                $$flagref = 1;
                return $oldnode;
            }
        }

        # match the existed nodes including old data and user defined data
        if (($type eq "BPA" or $type eq "FSP") and ($tmptype eq $type)) {
            unless ($tmpmtm) {
                next;
            }

            if ( $tmpmtm eq $mtm  and  $tmpsn eq $sn) {
                my $ifip = xCAT::NetworkUtils->isIpaddr($oldnode);
                if ( $ifip )  {# which means that the node is defined by the new lsslp
                    if ( $tmpside eq $side ) {# match! which means that node is the same as the new one
                        if ( $ip eq $tmpip ) { #which means that the ip is not changed
                            # maybe we should check if the ip is invalid and send a warning
                            $$flagref = 1;
                            return $ip;
                        }  else { #which means that the ip is changed
                            my $vip = check_ip($ip);
                            if ( !$vip )  { #which means the ip is changed and valid
                                # maybe we should check if the old ip is invalid and send a warning
                                # even so we should keep the definition as before
                                # because this case, we can't put check_ip in the end
                                $$flagref = 1;
                                return $oldnode;
                            } else {
                                return $ip;
                            }
                        }
                    }
                }
                else { # name is not a ip
                    $side =~ /(\w)\-(\w)/;
                    my $slot = $1;
                    if ( $tmpside and $tmpside !~ /\-/ )  {# side is like A or B
                        if ( $slot eq $tmpside ) {
                            if ( $oldnode =~ /^Server\-/)  {#judge if need to change node's name
                                if ( $ip eq $tmpip ) {
                                    if ( $oldnode =~ /\-(A|B)$/) {
                                        @{$::OLD_DATA_CACHE{$oldnode}}[7] = 0;
                                        $$flagref = 1;
                                        return  $oldnode;
                                    } else {
                                        @{$::OLD_DATA_CACHE{$oldnode}}[7] = 0;
                                        #change node name, need to record the node here
                                        $::UPDATE_CACHE{$mtm.'-'.$sn} = $oldnode;
                                        $$flagref = 1;
                                        return $oldnode.'-'.$slot;
                                    }
                                } else   {# not find a matched definition, but need to use the old node name
                                    if ($unmatched){
                                        $$flagref = 1;
                                        return $oldnode;
                                    }
                                }
                            } elsif ( $tmpside =~ /\-/ )  {# end of if ( $oldnode =~ /^Server\-/)
                                if ( $ip eq $tmpip ) {
                                    @{$::OLD_DATA_CACHE{$oldnode}}[7] = 0;
                                    $$flagref = 1;
                                    return $oldnode;
                                } else{
                                    if ($unmatched){
                                        $$flagref = 1;
                                        return $oldnode;
                                    }
                                }
                            }
                        }
                    } elsif ( $tmpside =~ /\-/ ){
                        if ( $side eq $tmpside ) {
                            $$flagref = 1;
                            return $oldnode;
                        }
                    } elsif ( !$tmpside ) {
                        if ( $oldnode =~ /^Server\-/)  {#judge if need to change node's name
                            if ( $oldnode !~ /\-(A|B)$/ ) {
                                delete $::OLD_DATA_CACHE{$oldnode};
                                $$flagref = 1; 
                                return $oldnode."-".$slot;
                            }
                        }
                        # if mtms could match but side not defined, we will trate
                        # it as the result by rscan. And alway use its name.
                        delete $::OLD_DATA_CACHE{$oldnode};
                        $$flagref = 1;
                        return $oldnode;
                    }
                }
            }# end of if ($tmpmtm eq $mtm  and  $tmpsn eq $sn)


        } 
        if ( ($type eq "FRAME" or $type eq "CEC") and ($type eq $tmptype)){
            if ( !$tmpmtm and !$tmpid)  {
                next;
            }
            # user may define cec only with parent /id /type
            # we should match this situation
            if ( ($type eq "CEC") and $parmtm and $parsn  and  $cage_number ) {
                my $tpparmtm = @{$::OLD_DATA_CACHE{$tmpparent}}[0];
                my $tpparsn  = @{$::OLD_DATA_CACHE{$tmpparent}}[1];
                if ( ($tpparmtm eq $parmtm) and ($tpparsn eq $parsn) and ($cage_number eq $tmpid) and ($type eq $tmptype) ) {
                    $$flagref = 1;
                    return $oldnode;
                }
            }

            # user may define cec/frame only with mtms
            # but what we consider here is just the data in xCAT 2.6
            if ($tmpmtm eq $mtm  and  $tmpsn eq $sn and $tmptype eq $type)  {
                if ( $oldnode =~ /^Server\-/)  {#judge if need to change node's name
                    if ( $oldnode =~ /(\-A)$/) {
                        $nodename = s/(\-A)$//;
                        # should send a warning here
                        $$flagref = 1;
                        return $nodename;
                    }
                    else  {
                        $$flagref = 1;
                        return $oldnode;
                    }
                } else {
                    $$flagref = 1;
                    return $oldnode;
                }
            }
        } # end of foreach my $oldnode ( keys %::OLD_DATA_CACHE ), not match
    }

    # not matched, use the new name
    my $ifip = xCAT::NetworkUtils->isIpaddr($nodename);
    unless ($ifip) {
        return $nodename;
    }else {
        my $vip = check_ip($nodename);
        if ( $vip )   {#which means the ip is a valid one
            return $nodename;
        } else {
            return undef;
        }
    }

}

##########################################################################
# Get correct IP from ip list in SLP Attr
##########################################################################
sub getip_from_iplist
{
    my $iplist  = shift;
    my $nets    = shift;
    my $inc     = shift;

    my @ips = split /,/, $iplist;
    my @ips2 = split /,/, $inc;
    if ( $inc)
    {
        for my $net (keys %$nets)
        {
            my $flag = 1;
            for my $einc (@ips2) {
                if ( $nets->{$net} eq $einc) { 
                    $flag = 0;
                }
            }
            delete $nets->{$net} if ($flag) ;
        }
    }


    for my $ip (@ips)
    {
        next if ( $ip =~ /:/); #skip IPV6 addresses
        for my $net ( keys %$nets)
        {
            my ($n,$m) = split /\//,$net;
            if ( xCAT::NetworkUtils::isInSameSubnet( $n, $ip, $m, 1) and
                 xCAT::NetworkUtils::isPingable( $ip))
            {
                return $ip;
            }
        }
    }
    return undef;
}

sub read_from_table {
    my %idhash;
    my %typehash;
    my %iphash;
    my %vpdhash;
    if ( !(%::OLD_DATA_CACHE))
    {
        # find out all the existed nodes' ipaddresses
        my $hoststab  = xCAT::Table->new('hosts');
        if ( $hoststab ) {
            my @ipentries = $hoststab->getAllNodeAttribs( ['node','ip'] );
            for my $ipentry ( @ipentries ) {
                $iphash{$ipentry->{node}} = $ipentry->{ip};
            }
        } else {
            return 1;
        }

        #find out all the existed nodes' type
        my $nodetypetab  = xCAT::Table->new('nodetype');
        if ( $nodetypetab ) {
            my @typeentries = $nodetypetab->getAllNodeAttribs( ['node','nodetype'] );
            for my $typeentry ( @typeentries) {
                $typehash{$typeentry->{node}} = $typeentry->{nodetype};
            }
        } else {
            return 2;
        }

        # find out all the existed nodes' mtms and side
        my $vpdtab  = xCAT::Table->new( 'vpd' );
        if ( $vpdtab )  {
            my @vpdentries = $vpdtab->getAllNodeAttribs(['node','mtm','serial','side']);
            for my $entry ( @vpdentries ) {
                @{$vpdhash{$entry->{node}}}[0] = $entry->{mtm};
                @{$vpdhash{$entry->{node}}}[1] = $entry->{serial}; 
                @{$vpdhash{$entry->{node}}}[2] = $entry->{side};
            }
        } else {
            return 3;
        }
        # find out all the existed nodes' attributes
        my $ppctab  = xCAT::Table->new('ppc');
        if ( $ppctab ) {
            my @identries = $ppctab->getAllNodeAttribs( ['node','id','parent','nodetype'] );
            for my $entry ( @identries ) {
                next if ($entry->{nodetype} =~ /lpar/);
                @{$::OLD_DATA_CACHE{$entry->{node}}}[0] = @{$vpdhash{$entry->{node}}}[0];#mtm
                @{$::OLD_DATA_CACHE{$entry->{node}}}[1] = @{$vpdhash{$entry->{node}}}[1];#sn
                @{$::OLD_DATA_CACHE{$entry->{node}}}[2] = @{$vpdhash{$entry->{node}}}[2];#side
                # find node ip address, check node name first, then check hosts table
                my $ifip = xCAT::NetworkUtils->isIpaddr($entry->{node});
                if ( $ifip )
                {
                    @{$::OLD_DATA_CACHE{$entry->{node}}}[3] = $entry->{node};#ip
                } else
                {
                    if ( exists ($iphash{$entry->{node}}) ) {
                       @{$::OLD_DATA_CACHE{$entry->{node}}}[3] = $iphash{$entry->{node}};#ip
                    }
                    else  {
                        @{$::OLD_DATA_CACHE{$entry->{node}}}[3] = "";#ip
                    }
                }
                @{$::OLD_DATA_CACHE{$entry->{node}}}[4] = $entry->{id};#id
                @{$::OLD_DATA_CACHE{$entry->{node}}}[5] = $entry->{parent};#parent
                if ( exists $entry->{nodetype}) {
                    @{$::OLD_DATA_CACHE{$entry->{node}}}[6] = $entry->{nodetype};#nodetype
                } else {
                    if ( exists ($typehash{$entry->{node}}) ) {
                        @{$::OLD_DATA_CACHE{$entry->{node}}}[6] = $typehash{$entry->{node}};
                    } else {
                        @{$::OLD_DATA_CACHE{$entry->{node}}}[6] = "";
                    }
                }    
                @{$::OLD_DATA_CACHE{$entry->{node}}}[7] = 1;
            }
        } else
        {
            return 4;
        }
    }
    return 0;
}
##########################################################################
# Makesure the ip in SLP URL is valid
# return 1 if valid, 0 if invalid
##########################################################################
sub check_ip {
    my $myip = shift;
    my $firstoctet = $myip;
    my @invalidiplist = (
        "192.168.2.144",
        "192.168.2.145",
        "192.168.2.146",
        "192.168.2.147",
        "192.168.2.148",
        "192.168.2.149",
        "192.168.3.144",
        "192.168.3.145",
        "192.168.3.146",
        "192.168.3.147",
        "192.168.3.148",
        "192.168.3.149",
        "169.254.",
        "127.0.0.0",
        "127",
        0,
        );
    $firstoctet =~ s/^(\d+)\..*/$1/;
    if ($firstoctet >= 224 and $firstoctet <= 239)
    {
        return 0;
    }
    foreach (@invalidiplist)
    {
        if ( $myip =~ /^($_)/ )
        {
            return 0;
        }
    }

    return 1;
}
1;

