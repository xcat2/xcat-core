# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Cloud;

BEGIN
{
    $::XCATROOT =
        $ENV{'XCATROOT'} ? $ENV{'XCATROOT'}
      : -d '/opt/xcat'   ? '/opt/xcat'
      : '/usr';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::NodeRange;
use xCAT::Utils;
use xCAT::TableUtils;
#use Data::Dumper;
use strict;



#-----------------------------------------------------------------------------

=head3 getcloudinfo 

   This function will be invoked by Postage.pm.  
   get the chef cookbook repository for each cloud from the clouds table, and 
   then get all the node --> cloud from the cloud table. The two type information
   will be stored in the %info

   If success, return the \%info.
	

    Arguments:
         none
    Returns: 
           \%info
                        
    Error:
        none
    Example:
         
    Comments:
        none

=cut

#-----------------------------------------------------------------------------


sub getcloudinfo
{
    my %info = ();

    my $tab = "clouds";
    my $ptab = xCAT::Table->new($tab);
    unless ($ptab) { 
        xCAT::MsgUtils->message("E", "Unable to open $tab table");
        return undef; 
    }
    my @rs = $ptab->getAllAttribs('name','repository', 'pubinterface');

    foreach my $r ( @rs ) {
       my $cloud = $r->{'name'};
       my $repos = $r->{'repository'};
       my $pubinterface = $r->{'pubinterface'};
       $info{ $cloud }{repository}  = $repos; 
       $info{ $cloud }{pubinterface}  = $pubinterface; 
    }

    $tab = "cloud";
    $ptab = xCAT::Table->new($tab);
    unless ($ptab) { 
        xCAT::MsgUtils->message("E", "Unable to open $tab table");
        return undef;
    }
    @rs = $ptab->getAllAttribs('node','cloudname');

    my $pre;
    my $curr;
    foreach my $r ( @rs ) {
       my $node = $r->{'node'};
       my $cloud = $r->{'cloudname'};
       $info{ $node }{cloud}  = $cloud;
    }
   
    return \%info;



} 


#-----------------------------------------------------------------------------

=head3 getcloudres 

   This function will be invoked by Postage.pm. And it's only for one chef-server. 
   1. get the chef cookbook repository for the clouds on one chef-server. 
   All the clouds's repositoryies on one chef-server should be the same one.
   2. get the cloud list for one chef-server
   3. get the cloud name for each node on the same chef-server
	

    Arguments:
         $cloudinfo_hash -- This is from the getcloudinfo function.
         $clients -- an array which stores different cloud nodes(chef-client)
    Returns: 
          $cloudres -- a string including cloud information
                        
    Error:
        none
    Example:
         
    Comments:
        none

=cut

#-----------------------------------------------------------------------------



sub getcloudres
{
    my $cloudinfo_hash = shift;
    my $node = shift;
    my $clients = shift;  
    my $cloudres;
    my $cloudlist;
    my $repos;
    if( @$clients == 0 ) {
        #This should not be a chef-server, and it's a chef-client
        if( defined($cloudinfo_hash) && defined($cloudinfo_hash->{$node}) ) {
            my $cloud=$cloudinfo_hash->{$node}->{cloud};
            my $pubinterface=$cloudinfo_hash->{$cloud}->{pubinterface};
            $cloudres="PUBINTERFACE='$pubinterface'\nexport PUBINTERFACE\n"; 
        }
        return $cloudres;
    }
    foreach my $client (@$clients) {
        my $cloud;
        if( defined($cloudinfo_hash) && defined($cloudinfo_hash->{$client}) ) {
            $cloud = $cloudinfo_hash->{$client}->{cloud};
        }
        #$cloudres .= "hput $client cloud $cloud\n";
        $cloudres .= "HASH".$client."cloud='$cloud'\nexport HASH".$client."cloud\n";
        if( defined($cloud) ) {
            if ( $cloudlist !~ $cloud ) {
                $cloudlist .="$cloud,";
            }
        }
        my $t = $cloudinfo_hash->{$cloud}->{repository};
        if( !defined($repos) && defined($t) ) {
            $repos =  $t;
        }
        if( defined($repos) && ( $repos != $t && "$repos/" != $t && $repos != "$t/" ) ) {
            xCAT::MsgUtils->message("E", "Two cloud repositories: $repos and $t.\n There should be only one cloud repository one ont chef-server.");
            return undef; 
        }
    }
    chop $cloudlist;
    $cloudres = "REPOSITORY='$repos'\nexport REPOSITORY\nCLOUDLIST='$cloudlist'\nexport CLOUDLIST\n$cloudres";
    return $cloudres;
}


1;
