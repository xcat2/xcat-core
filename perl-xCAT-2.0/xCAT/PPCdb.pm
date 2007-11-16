# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCdb;
use strict;
use Getopt::Long;
use xCAT::Table;


##########################################################################
# Adds an LPAR to the xCAT databases
##########################################################################
sub add_ppc {

    my $hwtype = shift;
    my $values = shift;
    my @tabs   = qw(ppc vpd nodehm nodelist); 
    my %db     = ();

    ###################################
    # Open database needed
    ###################################
    foreach ( @tabs ) {
        $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>0 );
        if ( !$db{$_} ) {
            return;
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
            $server,
            $profile,
            $mgt,
            $ips ) = split /,/;

         
        ###############################
        # Update ppc table
        ###############################
        if ( $type =~ /^fsp|bpa|lpar$/ ) {
            my ($k,$u);
            $k->{node}    = $name;
            $u->{hcp}     = $server;
            $u->{id}      = $id;
            $u->{profile} = $profile;
            $u->{mgt}     = $mgt;
            $db{ppc}->setAttribs( $k, $u );
            $db{ppc}{commit} = 1;

            ###########################
            # Update nodelist table
            ###########################
            my ($k1,$u1);
            my %nodetype = ( 
                 fsp  => "fsp",
                 bpa  => "bpa",
                 lpar => "osi"
            );
            $k1->{node}     = $name;
            $u1->{groups}   = lc($hwtype).",all";
            $u1->{nodetype} = $nodetype{$type};   
            $db{nodelist}->setAttribs( $k1,$u1 );
            $db{nodelist}{commit} = 1;

            ###########################
            # Update nodehm table
            ###########################
            my ($k2,$u2);
            $k2->{node} = $name;
            $u2->{mgt}  = $hwtype;
            $db{nodehm}->setAttribs( $k2,$u2 );
            $db{nodehm}{commit} = 1;
        }
        ###############################
        # Update vpd table
        ###############################
        if ( $type =~ /^fsp|bpa$/ ) {
            my ($k,$u);
            $k->{node}   = $name;
            $u->{serial} = $serial;
            $u->{mtm}    = $model;
            $db{vpd}->setAttribs( $k,$u );
            $db{vpd}{commit} = 1;
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
}


##########################################################################
# Adds a hardware control point to the xCAT database
##########################################################################
sub add_ppch {

    my $hwtype  = shift;
    my $uid     = shift;
    my $pw      = shift;
    my $name    = shift;
    my $k;
    my $u;

    ###################################
    # Update HWCtrl Point table
    ###################################
    my $tab = xCAT::Table->new( 'ppch', -create=>1, -autocommit=>0 );
    if ( !$tab ) {
        return;
    }
    $k->{hcp}      = $name;
    $u->{username} = $uid;
    $u->{password} = $pw;

    $tab->setAttribs( $k, $u );
    $tab->commit;

}


##########################################################################
# Get userids and passwords from tables
##########################################################################
sub credentials {

    my $server = shift;
    my $hwtype = shift;
    my %db = (
        hmc => "ppchcp",
        ivm => "ppchcp",
        fsp => "ppcDirect"
    );

    ###########################################
    # Get userid/password based on HwCtrl Pt
    ###########################################
    my $tab = xCAT::Table->new( $db{$hwtype} );
    if ( $tab ) {
        my ($ent) = $tab->getAttribs({'hcp'=>$server},'username','password');
        if ( defined( $ent ) ) {
            return( $ent->{username},$ent->{password} );
        }
    }
    ###########################################
    # Get userid/password based on type
    ###########################################
    $tab = xCAT::Table->new( 'passwd' );
    if ( $tab ) {
        my ($ent) = $tab->getAttribs({'key'=>$hwtype},'username','password');
        if ( defined( $ent ) ) {
            return( $ent->{username},$ent->{password} );
        }
    }
    ###########################################
    # Use factory defaults
    ###########################################
    my %logon = (
        hmc => ["hscroot","abc123"],
        ivm => ["padmin", "padmin"],
        fsp => ["dev",    "FipSdev"]
    );
    return( @{$logon{$hwtype}}[0], @{$logon{$hwtype}}[1] );
}


1;
