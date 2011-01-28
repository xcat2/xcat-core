# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCdb;
use xCAT_plugin::lsslp;
use strict;
use xCAT::Table;
use xCAT::GlobalDef;


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
    my %nodetype = (
        fsp   => $::NODETYPE_FSP,
        bpa   => $::NODETYPE_BPA,
        lpar  =>"$::NODETYPE_LPAR,$::NODETYPE_OSI",
        hmc   => $::NODETYPE_HMC,
        ivm   => $::NODETYPE_IVM,
        frame => $::NODETYPE_FRAME,
        cec   => $::NODETYPE_CEC,
    );

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
        if ( $type =~ /^(fsp|bpa|lpar|hmc|ivm|frame|cec)$/ ) {
            $db{nodetype}->setNodeAttribs( $name,{nodetype=>$nodetype{$type}} );
            $db{nodetype}{commit} = 1;
        }
        ###############################
        # If cannot be overwroten, get
        # old data firstly
        ###############################
        my $mgt = $hwtype;
        
        # Specify CEC and Frame's mgt as fsp and bpa
        if ( $type =~ /^cec$/)  {
            $mgt = "fsp";
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
        if ( $type =~ /^(fsp|bpa|lpar|frame|cec)$/ ) {
            $db{ppc}->setNodeAttribs( $name,
               { hcp=>$server,
                 id=>$id,
                 pprofile=>$pprofile,
                 parent=>$parent,
                 nodetype=>$nodetype{$type},
               }); 
            $db{ppc}{commit} = 1;

            ###########################
            # Update nodelist table
            ###########################
            updategroups( $name, $db{nodelist}, $type );
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
        if ( $type =~ /^(fsp|bpa|frame|cec)$/ ) {
            $db{vpd}->setNodeAttribs( $name, 
                { mtm=>$model,
                  serial=>$serial,
                  side=>$side
                 });
            $db{vpd}{commit} = 1;
        }

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
# Update nodes in the xCAT databases
##########################################################################
sub update_ppc {

    my $hwtype   = shift;
    my $values   = shift;
    my $not_overwrite = shift;
    my @tabs     = qw(ppc vpd nodehm nodelist nodetype ppcdirect hosts mac); 
    my %db       = ();
    my %nodetype = (
        fsp  => $::NODETYPE_FSP,
        bpa  => $::NODETYPE_BPA,
        lpar =>"$::NODETYPE_LPAR,$::NODETYPE_OSI",
        hmc  => $::NODETYPE_HMC,
        ivm  => $::NODETYPE_IVM,
    );
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
            my $hostname =  xCAT_plugin::lsslp::gethost_from_url_or_old($tname, "FSP", $tmtm, $tsn, "", "", $tid, "","");
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
            my $hostname =  xCAT_plugin::lsslp::gethost_from_url_or_old($tname, "BPA", $tmtm, $tsn, "", "", $tid, "","");
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
        my $pwhash = $db->{ppcdirect}->getAttribs( {hcp=>$predefined_node,username=>$user}, qw(password comments disable));
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
         $namediff)
    {
        $db->{ppc}->delEntries( $key_col) if ( $namediff);
        $db->{ppc}->setNodeAttribs( $name,
                { hcp=>$server,
                id=>$id,
                pprofile=>$pprofile,
                parent=>$parent
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
        $db->{nodetype}->setNodeAttribs( $name,{nodetype=>$type} );
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
    my @tabs   = qw(ppchcp nodehm nodelist nodetype mac);
    my %db     = ();

    my ($name, $mac) = split ',', $values;

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
    my ($ent) = $db{ppchcp}->getAttribs({ hcp=>$name},'hcp');
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
    $db{nodetype}->setNodeAttribs( $name, {nodetype=>lc($hwtype)});

    ###################################
    # Update mac table
    ###################################
     $db{mac}->setNodeAttribs( $name, {mac=>$mac});

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
    my ($ent) = $db{mpa}->getAttribs({ mpa=>$name},'mpa');
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
    # Check passwd tab
    ###########################################
    my $tab = xCAT::Table->new( 'passwd' );
    if ( $tab ) {
        my $ent;
        if ( $user_specified)
        {
            ($ent) = $tab->getAttribs( {key=>$hwtype,username=>$user},qw(password));
        }
        else
        {
            ($ent) = $tab->getAttribs( {key=>$hwtype}, qw(username password));
        }
        if ( $ent ) {
            if (defined($ent->{password})) { $pass = $ent->{password}; }
            if (defined($ent->{username})) { $user = $ent->{username}; }
        }
    }
    ##########################################
    # Check table based on specific node 
    ##########################################
    $tab = xCAT::Table->new( $hcptab{$hwtype} );
    if ( $tab ) {
        my $ent;
        if ( $user_specified)
        {
            ($ent) = $tab->getAttribs( {hcp=>$server,username=>$user},qw(password));
        }
        else
        {
            ($ent) = $tab->getAttribs( {hcp=>$server}, qw(username password));
        }
        if ( $ent){
            if (defined($ent->{password})) { $pass = $ent->{password}; }
            if (defined($ent->{username})) { $user = $ent->{username}; }
        }
    ##############################################################
    # If no user/passwd found, check if there is a default group
    ##############################################################
        elsif( ($ent) = $tab->getAttribs( {hcp=>$defaultgrp{$hwtype}}, qw(username password)))
        {
            if ( $user_specified)
            {
                ($ent) = $tab->getAttribs( {hcp=>$defaultgrp{$hwtype},username=>$user},qw(password));
            }
            else
            {
                ($ent) = $tab->getAttribs( {hcp=>$defaultgrp{$hwtype}}, qw(username password));
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


1;

