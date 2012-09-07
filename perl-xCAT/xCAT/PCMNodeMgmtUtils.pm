# IBM(c) 2012 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::PCMNodeMgmtUtils;

use strict;
use warnings;
use Socket;
use File::Path qw/mkpath/;
use File::Temp qw/tempfile/;
require xCAT::Table;
require xCAT::TableUtils;
require xCAT::NodeRange;
require xCAT::NetworkUtils;


#--------------------------------------------------------------------------------

=head1    xCAT::PCMNodeMgmtkUtils

=head2    Package Description

This program module file, is a set of PCM node management utilities.

=cut

#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------

=head3 get_allocable_staticips_innet
      Description : Get allocable IPs from a network.
      Arguments   : $netname - network name
                    $exclude_ips_ref - excluded IPs list reference.
      Returns     : Reference of allocable IPs list
=cut

#-------------------------------------------------------------------------------
sub get_allocable_staticips_innet
{
    my $class = shift;
    my $netname = shift;
    my $exclude_ips_ref = shift;
    my %iphash;
    my @allocableips;

    foreach (@$exclude_ips_ref){
        $iphash{$_} = 0;
    }

    my $networkstab = xCAT::Table->new('networks');
    my $netentry = ($networkstab->getAllAttribsWhere("netname = '$netname'", 'ALL'))[0];
    my ($startip, $endip) =  split('-', $netentry->{'staticrange'});
    my $incremental = $netentry->{'staticrangeincrement'};
    my $validipsref;
    if ($incremental and $startip and $endip){
        $validipsref = xCAT::NetworkUtils->get_allips_in_range($startip, $endip, $incremental);
    }
    foreach (@$validipsref){
        if (! exists($iphash{$_})){
            push @allocableips, $_;
        }
    }
    return \@allocableips;
}

#-------------------------------------------------------------------------------

=head3 genhosts_with_numric_tmpl
      Description : Generate numric hostnames using numric template name.
      Arguments   : $format - The hostname format string..
      Returns     : numric hostname list
      Example     : 
              calling  genhosts_with_numric_tmpl("compute#NNnode") will return a list like:
              ("compute00node", "compute01node", ..."compute98node", "compute99node")
=cut

#-------------------------------------------------------------------------------
sub genhosts_with_numric_tmpl
{
    my ($class, $format) = @_;

    my ($prefix, $appendix, $len) = xCAT::PCMNodeMgmtUtils->split_hostname($format, 'N');
    return xCAT::PCMNodeMgmtUtils->gen_numric_hostnames($prefix, $appendix, $len);
}

#-------------------------------------------------------------------------------

=head3 split_hostname
      Description : Split hostname format as prefix, appendix and number length.
      Arguments   : $format - hostname format
                    $patt_char - pattern char, we always use "N" to indicate numric pattern
      Returns     : ($prefix, $appendix, $numlen)
                    $prefix - the prefix string of hostname format.
                    $appendix - the appendix string of hostname format
                    $numlen - The number length in hostname format.
      Example     : 
              calling  split_hostname("compute#NNnode") will return a list like:
              ("compute", "node", 2)
=cut

#-------------------------------------------------------------------------------
sub split_hostname
{
    my ($class, $format, $patt_char) = @_;

    my $idx = index $format, "#$patt_char";
    my @array_format = split(//, $format);
    my $pos = $idx+2;
    while ( $pos <= (scalar(@array_format) - 1)){
        if ($array_format[$pos] eq "$patt_char"){
            $pos++;
        }else{
            last;
        }
    }
    my $ridx = $pos - 1;

    my $prefix = "";
    $prefix = substr $format, 0, $idx;
    my $appendix = "";
    if (($ridx + 1) != scalar(@array_format)){
        $appendix = substr $format, $ridx + 1;
    }
    return $prefix, $appendix, ($ridx - $idx);
}

#-------------------------------------------------------------------------------

=head3 gen_numric_hostnames
      Description : Generate numric hostnames.
      Arguments   : $prefix - The prefix string of the hostname.
                    $appendix - The appendix string of the hostname.
                    $len - the numric number length in hostname.
      Returns     : numric hostname list
      Example     : 
              calling  gen_numric_hostnames("compute", "node",2) will return a list like:
              ("compute00node", "compute01node", ..."compute98node", "compute99node")
=cut

#-------------------------------------------------------------------------------
sub gen_numric_hostnames
{
    my ($class, $prefix, $appendix, $len) = @_;
    my @hostnames;

    my $cnt=0;
    my $maxnum = 10 ** $len;
    while($cnt < $maxnum)
    {
        my $fullnum = $maxnum + $cnt;
        my $hostname = $prefix.(substr $fullnum, 1).$appendix;
        push (@hostnames, $hostname);
        $cnt++;
    }
    return \@hostnames;
}

#-------------------------------------------------------------------------------

=head3 get_hostname_format_type
      Description : Get hostname format type.
      Arguments   : $format - hostname format
      Returns     : hostname format type value:
                    "numric" - numric hostname format.
                    "rack" - rack info hostname format.
      Example     : 
              calling  get_hostname_format_type("compute#NNnode") will return "numric"
              calling  get_hostname_format_type("compute-#RR-#NN") will return "rack" 
=cut

#-------------------------------------------------------------------------------
sub get_hostname_format_type{
    my ($class, $format) =  @_;
    my $type;

    my $ridx = index $format, "#R";
    my $nidx = index $format, "#N";
    if ($ridx >= 0){
        $type = "rack";
    } elsif ($nidx >= 0){
        $type = "numric";
    }
    return $type;
}

#-------------------------------------------------------------------------------

=head3 rackformat_to_numricformat
      Description : convert rack hostname format into numric hostname format.
      Arguments   : $format - rack hostname format
                    $racknum - rack number.
      Returns     : numric hostname format.
      Example     : 
           calling  rackformat_to_numricformat("compute-#RR-#NN", 1) will return "compute-01-#NN" 
=cut

#-------------------------------------------------------------------------------
sub rackformat_to_numricformat{
    my ($class, $format, $racknum) = @_;
    my ($prefix, $appendix, $len) = xCAT::PCMNodeMgmtUtils->split_hostname($format, 'R');

    my $maxnum = 10 ** $len;
    my $fullnum = $maxnum + $racknum;
    return $prefix.(substr $fullnum, 1).$appendix;
}

#-------------------------------------------------------------------------------

=head3 get_netprofile_nic_attrs
      Description : Get networkprofile's NIC attributes and return a dict.
      Arguments   : $netprofilename - network profile name.
      Returns     : A hash %netprofileattrs for network profile attributes.
                    keys of %netprofileattrs are nics names, like: ib0, eth0, bmc...
                    values of %netprofileattrs are attributes of a specific nic, like:
                        type : nic type
                        hostnamesuffix: hostname suffix
                        customscript: custom script for this nic
                        network: network name for this nic
=cut

#-------------------------------------------------------------------------------
sub get_netprofile_nic_attrs{
    my $class = shift;
    my $netprofilename = shift;

    my $nicstab = xCAT::Table->new( 'nics');
    my $entry = $nicstab->getNodeAttribs("$netprofilename", ['nictypes', 'nichostnamesuffixes', 'niccustomscripts', 'nicnetworks']);

    my %netprofileattrs;
    my @nicattrslist;

    if ($entry->{'nictypes'}){
        @nicattrslist = split(",", $entry->{'nictypes'});
        foreach (@nicattrslist){
            my @nicattrs = split(":", $_);
            $netprofileattrs{$nicattrs[0]}{'type'} = $nicattrs[1];
        }
    }

    if($entry->{'nichostnamesuffixes'}){
        @nicattrslist = split(",", $entry->{'nichostnamesuffixes'});
        foreach (@nicattrslist){
            my @nicattrs = split(":", $_);
            $netprofileattrs{$nicattrs[0]}{'hostnamesuffix'} = $nicattrs[1];
        }
    }

    if($entry->{'niccustomscripts'}){
        @nicattrslist = split(",", $entry->{'niccustomscripts'});
        foreach (@nicattrslist){
            my @nicattrs = split(":", $_);
            $netprofileattrs{$nicattrs[0]}{'customscript'} = $nicattrs[1];
        }
    }

    if($entry->{'nicnetworks'}){
        @nicattrslist = split(",", $entry->{'nicnetworks'});
        foreach (@nicattrslist){
            my @nicattrs = split(":", $_);
            $netprofileattrs{$nicattrs[0]}{'network'} = $nicattrs[1];
        }
    }

    return \%netprofileattrs;
}

#-------------------------------------------------------------------------------

=head3 get_netprofile_bmcnet
      Description : Get bmc network name of a network profile.
      Arguments   : $nettmpl - network profile name 
      Returns     : bmc network name of this network profile.
=cut

#-------------------------------------------------------------------------------
sub get_netprofile_bmcnet{
    my ($class, $netprofilename) = @_;

    my $netprofile_nicshash_ref = xCAT::PCMNodeMgmtUtils->get_netprofile_nic_attrs($netprofilename);
    my %netprofile_nicshash = %$netprofile_nicshash_ref;
    if (exists $netprofile_nicshash{'bmc'}{"network"}){
        return $netprofile_nicshash{'bmc'}{"network"}
    }else{
        return undef;
    }
}

#-------------------------------------------------------------------------------

=head3 get_netprofile_provisionnet
      Description : Get deployment network of a network profile.
      Arguments   : $nettmpl - network profile name 
      Returns     : deployment network name of this network profile.
=cut

#-------------------------------------------------------------------------------
sub get_netprofile_provisionnet{
    my ($class, $netprofilename) = @_;

    my $netprofile_nicshash_ref = xCAT::PCMNodeMgmtUtils->get_netprofile_nic_attrs($netprofilename);
    my %netprofile_nicshash = %$netprofile_nicshash_ref;
    my $restab = xCAT::Table->new('noderes');
    my $installnicattr = $restab->getNodeAttribs($netprofilename, ['installnic']);
    my $installnic = $installnicattr->{'installnic'};

    if ($installnic){
        if (exists $netprofile_nicshash{$installnic}{"network"}){
            return $netprofile_nicshash{$installnic}{"network"}
        }
    }
    return undef;
}

#-------------------------------------------------------------------------------

=head3 get_output_filename
      Description : Generate a temp file name for placing output details for PCM node management operations.
                    We make this file generated under /install/ so that clients can access it through http.
      Arguments   : N/A
      Returns     : A temp filename placed under /install/pcm/work/
=cut

#-------------------------------------------------------------------------------
sub get_output_filename
{
    my $installdir = xCAT::TableUtils->getInstallDir();
    my $pcmworkdir = $installdir."/pcm/work/";
    if (! -d $pcmworkdir)
    {
        mkpath($pcmworkdir);
    }
    return tempfile("hostinfo_result_XXXXXXX", DIR=>$pcmworkdir);
}

#-------------------------------------------------------------------------------

=head3 get_all_chassis
      Description : Get all chassis in system.
      Arguments   : hashref: if not set, return a array ref.
                             if set, return a hash ref.
      Returns     : ref for node list.
      Example     : 
                    my $arrayref = xCAT::PCMNodeMgmtUtils->get_all_chassis();
                    my $hashref = xCAT::PCMNodeMgmtUtils->get_all_chassis(1);
=cut

#-------------------------------------------------------------------------------
sub get_all_chassis
{
    my $class = shift;
    my $hashref = shift;
    my %chassishash;

    my @chassis = xCAT::NodeRange::noderange('__Chassis');
    if ($hashref){
        foreach (@chassis){
            $chassishash{$_} = 1;
        }
        return \%chassishash;
    } else{
        return \@chassis;
    }
}

#-------------------------------------------------------------------------------

=head3 get_allnode_singleattrib_hash
      Description : Get all records of a column from a table, then return a hash.
                    The return hash's keys are the records of this attribute 
                    and values are all set as 1.
      Arguments   : $tabname - the table name.
                    $attr - the attribute name.
      Returns     : Reference of the records hash.
=cut

#-------------------------------------------------------------------------------
sub get_allnode_singleattrib_hash
{
    my $class = shift;
    my $tabname = shift;
    my $attr = shift;
    my $table = xCAT::Table->new($tabname);
    my @entries = $table->getAllNodeAttribs([$attr]);
    my %allrecords;
    foreach (@entries) {
        if ($_->{$attr}){
            $allrecords{$_->{$attr}} = 0;
        }
    }
    return \%allrecords;
}

#-------------------------------------------------------------------------------

=head3 acquire_lock
      Description : Create lock file for node management plugin so that there is 
                    no multi node mamangement plugins running.
                    The file content will be the pid of the plugin running process.
                    Once the plugin process terminated abnormally and lock file not removed,
                    next time node management plugin runs, it will read the lock file 
                    and check whether this process is running or not. If not, 
                    just remove this lock file and create a new one.
      Arguments   : N/A
      Returns     : 1 - create lock success.
                    0 - failed, there may be a node management process running.
=cut

#-------------------------------------------------------------------------------
sub acquire_lock
{
    my $lockfile = "/var/lock/pcm/nodemgmt";
    my $lockdir = "/var/lock/pcm";
    mkdir "$lockdir", 0755 unless -d "$lockdir";

    if (-e $lockfile) {
        open LOCKFILE, "<$lockfile";
        my @lines = <LOCKFILE>;
        my $pid = $lines[0];
        if (-d "/proc/$pid") {
            return 0;
        } else{
            # the process already not exists, remove lock file.
            File::Path->rmtree($lockfile);
        }
    }
    open LOCKFILE, ">$lockfile";
    print LOCKFILE $$;
    close LOCKFILE;
    return 1;
}

#-------------------------------------------------------------------------------

=head3 release_lock
      Description : Release lock for node management process.
      Arguments   : N/A
      Returns     : N/A
=cut

#-------------------------------------------------------------------------------
sub release_lock
{
    my $lockfile = "/var/lock/pcm/nodemgmt";
    if (-e $lockfile){
        open LOCKFILE, "<$lockfile";
        my @lines = <LOCKFILE>;
        my $pid = $lines[0];
        close LOCKFILE;
        if ($pid ne $$){
            File::Path->rmtree($lockfile);
        }
    }
}

#-------------------------------------------------------------------------------

=head3 get_node_profiles
      Description : Get nodelist's profile and return a hash ref.
      Arguments   : node list.
      Returns     : nodelist's profile hash.
                    keys are node names.
                    values are hash ref. This hash ref is placing the node's profile information:
                        keys can be followings: "NetworkProfile", "ImageProfile", "HardwareProfile"
                        values are the profile names.
=cut

#-------------------------------------------------------------------------------

sub get_nodes_profiles
{
    my $class = shift;
    my $nodelistref = shift;
    my %profile_dict;

    my $nodelisttab = xCAT::Table->new('nodelist');
    my $groupshashref = $nodelisttab->getNodesAttribs($nodelistref, ['groups']);
    my %groupshash = %$groupshashref;

    foreach (keys %groupshash){
        my $value = $groupshash{$_};
        my $groups = $value->[0]->{'groups'};
        # groups looks like "__Managed,__NetworkProfile_default_cn,__ImageProfile_rhels6.3-x86_64-install-compute"
        my @grouplist = split(',', $groups);
        my @profilelist = ("NetworkProfile", "ImageProfile", "HardwareProfile");
        foreach my $group (@grouplist){
            foreach my $profile (@profilelist){
                my $idx = index ($group, $profile);
                # The Group starts with __, so index will be 2.
                if ( $idx == 2 ){
                    # The group string will like @NetworkProfile_<profile name>
                    # So, index should +3, 2 for '__', 1 for _.
                    my $append_index = length($profile) + 3;
                    $profile_dict{$_}{$profile} = substr $group, $append_index;
                    last;
                }
            }
        }
    }
    return \%profile_dict;
}

#-------------------------------------------------------------------------------

=head3 get_imageprofile_prov_method
      Description : Get A node's provisioning method from its imageprofile attribute.
      Arguments   : $imgprofilename - imageprofile name
      Returns     : node's provisioning method: install, netboot...etc
=cut

#-------------------------------------------------------------------------------
sub get_imageprofile_prov_method
{

    # For imageprofile, we can get node's provisioning method through:
    # nodetype table: node (imageprofile name), provmethod (osimage name)
    # osimage table: imagename (osimage name), provmethod (node deploy method: install, netboot...)
    my $class = shift;
    my $imgprofilename = shift;

    my $nodetypestab = xCAT::Table->new('nodetype');
    my $entry = ($nodetypestab->getAllAttribsWhere("node = '$imgprofilename'", 'ALL' ))[0];
    my $osimgname = $entry->{'provmethod'};

    my $osimgtab = xCAT::Table->new('osimage');
    my $osimgentry = ($osimgtab->getAllAttribsWhere("imagename = '$osimgname'", 'ALL' ))[0];
    return $osimgentry->{'provmethod'};
}

