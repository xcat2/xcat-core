# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle configcec

   Supported command:
         configcec

=cut

#-------------------------------------------------------
package xCAT_plugin::configcec;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;

#use warnings;
use Sys::Hostname;
use Getopt::Long;
require xCAT::Table;
require xCAT::Utils;
require xCAT::TableUtils;
require xCAT::ServiceNodeUtils;
require xCAT::MsgUtils;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return { configcec => "configcec" };
}

#-------------------------------------------------------------------------------

=head3
      parse_args
         Parse the command arguments

        Arguments:
          None

        Returns:

        Globals:
             @ARGV

        Error:
                None

=cut

#-------------------------------------------------------------------------------
sub parse_args()
{
    if (scalar(@ARGV) == 0)
    {
        &usage();
        exit 0;
    }
    $Getopt::Long::ignorecase = 0;
    if (!GetOptions(
            'n|numberoflpar=s' => \$::NUMBEROFLPARS,
            'vio'              => \$::VIO,
            'h|help'           => \$::HELP,
            'p|prefix=s'       => \$::prefix,
            'c|cpu=s'          => \$::cpu,
            'm|mem=s'          => \$::memory,
            'hea_mcs=s'        => \$::hea_mcs,
            'r|removelpars=s'  => \$::removelpars,
            'i|init'           => \$::init,
            'V|verbose'        => \$::VERBOSE,)) {

        &usage();
        exit 1;
    }

    if ($::HELP)
    {
        &usage();
        exit 0;
    }
}

#-------------------------------------------------------

=head3  preprocess_request

  Check and setup for hierarchy , if your command must run
  on service nodes. Otherwise preprocess_request not necessary

=cut

#-------------------------------------------------------
sub preprocess_request
{
    my $req  = shift;
    my $args = $req->{arg};
    $::CALLBACK = shift;
    my @requests = ();
    my $sn;

    @ARGV = @{$args};

    &parse_args();

    #if already preprocessed, go straight to request
    if (($req->{_xcatpreprocessed}) and ($req->{_xcatpreprocessed}->[0] == 1)) { return [$req]; }

    if (!defined($req->{'node'}) || scalar(@{ $req->{'node'} }) == 0)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "No cec is specified, exiting...";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 0);
        return;
    }

    my $nodes   = $req->{node};
    my $service = "xcat";

    # find service nodes for requested nodes
    # build an individual request for each service node
    if ($nodes) {
        $sn = xCAT::ServiceNodeUtils->get_ServiceNode($nodes, $service, "MN");

        # build each request for each service node

        foreach my $snkey (keys %$sn)
        {
            my $n       = $sn->{$snkey};
            my $reqcopy = {%$req};
            $reqcopy->{node}                   = $sn->{$snkey};
            $reqcopy->{'_xcatdest'}            = $snkey;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            push @requests, $reqcopy;

        }
        return \@requests;    # return requests for all Service nodes
    } else {
        return [$req];        # just return original request
    }
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{

    my $request = shift;
    $::CALLBACK = shift;
    my $nodes   = $request->{node};
    my $command = $request->{command}->[0];
    my $args    = $request->{arg};
    my $envs    = $request->{env};
    my %rsp;
    my @nodes = @$nodes;
    @ARGV = @{$args};    # get arguments

    &parse_args();

    if (defined($::hea_mcs) && ($::hea_mcs != 1) && ($::hea_mcs != 2) && ($::hea_mcs != 4) && ($::hea_mcs != 8) && ($::hea_mcs != 16))
    {
        my $rsp = {};
        $rsp->{data}->[0] = "The hea_mcs value $::hea_mcs is not valid, valid values are 1,2,4,8,16";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 0);
        return;
    }

    # do your processing here
    # return info

    my $ppctabhash;

    # the hash key is hmc, the hash value is an array of the nodes managed by this HMC
    my $hmchash;
    my $ppctab = xCAT::Table->new("ppc");
    if ($ppctab) {
        $ppctabhash = $ppctab->getNodesAttribs(\@nodes, ['hcp']);
    }
    foreach my $nd (keys %$ppctabhash)
    {
        my $hcp = $ppctabhash->{$nd}->[0]->{'hcp'};
        if ($hcp)
        {
            push @{ $hmchash->{$hcp} }, $nd;
        }
    }

    # Connect to the HMCs and run commands
    # TODO: do this in parellell
    foreach my $hmc (keys %{$hmchash})
    {
        # lssyscfg -r sys -m $sys
        # lshwres -r proc -m $sys --level sys
        # lshwres -r mem -m $sys --level sys
        # lshwres -r io -m $sys --rsubtype slot
        # lshwres -r hea -m $sys --level sys --rsubtype phys
        # lshwres -r hea -m $sys --level port_group --rsubtype phys
        # lshwres -r hea -m $sys --level port --rsubtype phys
        foreach my $sys (@{ $hmchash->{$hmc} })
        {

            # Hardware configuration information for this CEC
            my $syscfgref;
            my $hwresref;
            my $cmd;
            my $outref;

            if ($::removelpars)
            {
                my @lparids = split /,/, $::removelpars;
                foreach my $lparid (@lparids)
                {
                    $cmd = "rmsyscfg -r lpar -m $sys --id $lparid";
                    $outref = &run_hmc_cmd($hmc, $cmd);
                }
                return;
            }

            if ($::init)
            {
                $cmd = "rstprofdata -m $sys -l 4";
                $outref = &run_hmc_cmd($hmc, $cmd);
                return;
            }

            #$cmd = "lssyscfg -r sys -m $sys";
            #$outref = &run_hmc_cmd($hmc, $cmd);
            #$syscfgref = &parse_hmc_output($outref);

            $cmd                = "lshwres -r proc -m $sys --level sys";
            $outref             = &run_hmc_cmd($hmc, $cmd);
            $hwresref->{'proc'} = &parse_hmc_output($outref);

            $cmd               = "lshwres -r mem -m $sys --level sys";
            $outref            = &run_hmc_cmd($hmc, $cmd);
            $hwresref->{'mem'} = &parse_hmc_output($outref);

            $cmd = "lshwres -r io -m $sys --rsubtype slot";
            $outref = &run_hmc_cmd($hmc, $cmd);
            my @ioarray = split /\n/, $outref;
            foreach my $ioline (@ioarray)
            {
                $ioline =~ /drc_index=(.*),lpar_id/;
                if ($1)
                {
                    $hwresref->{'io'}->{$1} = &parse_hmc_output($ioline);
                }
            }

            # HEA
            $cmd = "lshwres -r hea -m $sys --level port_group --rsubtype phys";
            $outref = &run_hmc_cmd($hmc, $cmd);
            my @heaarray = split /\n/, $outref;
            foreach my $healine (@heaarray)
            {
                $healine =~ /adapter_id=(.*),port_group=(\d)+,/;
                if ($1 && $2)
                {
                    $hwresref->{'hea'}->{$1}->{$2} = &parse_hmc_output($healine);
                }
            }

            # Set HEA Pending Port Group MCS value
            if ($::hea_mcs)
            {
                foreach my $hea_adapter (keys %{ $hwresref->{'hea'} })
                {
                    foreach my $p_grp (keys %{ $hwresref->{'hea'}->{$hea_adapter} })
                    {
                        # Only if the pend_mcs is not equal to the new one
                        if ($hwresref->{'hea'}->{$hea_adapter}->{$p_grp}->{'pend_port_group_mcs_value'} != $::hea_mcs)
                        {
                            $cmd = "chhwres -r hea -m $sys -o s -l $hea_adapter -g $p_grp -a \"pend_port_group_mcs_value=$::hea_mcs\"";
                            &run_hmc_cmd($hmc, $cmd);
                        }
                    }
                }

                # Do not expect to do anything else together with setting the HEA MCS value
                return;
            }
            if (!$::prefix)
            {
                if ($sys =~ /^Server-.*-SN(.*?)$/)
                {
                    $::prefix = lc($1);
                }
                else
                {
                    $::prefix = lc($sys);
                }
            }
            else
            {
                if (!open(FILE, $::prefix))
                {
                    my $rsp = {};
                    $rsp->{data}->[0] = "File $::prefix isn't able to open...";
                    xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 0);
                    return;
                }
                while (<FILE>)
                {
                    chomp($_);
                    $_ .= ",";
                    s/"/\\"/g;
                    s/lpar_name/profile_name/g;
                    s/min_num_huge_pages(.*?),//;
                    s/desired_num_huge_pages(.*?),//;
                    s/max_num_huge_pages(.*?),//;
                    s/uncap_weight(.*?),//;
                    s/shared_proc_pool_id(.*?),//;
                    s/electronic_err_reporting(.*?),//;
                    s/,$//;
                    my $cmd = "mksyscfg -r lpar -m $sys -i \'" . $_ . "\'";
                    print "cmd = $cmd\n";
                    $outref = &run_hmc_cmd($hmc, $cmd);

                }
                close(FILE);
                return;
            }

            # Create vio partition
            if ($::VIO)
            {
                # Basic configuration for vio server: 2GB memory, 1 CPU
                my $prof = "name=" . $::prefix . "vio,profile_name=" . $::prefix . "vio,lpar_env=vioserver";

                my $cpustr = generate_cpu_conf($hwresref);
                $prof .= $cpustr;

                my $memstr = generate_mem_conf($hwresref);
                $prof .= $memstr;

                # Assign all I/O slots to vio server
                $prof .= ",\\\"io_slots=";
                foreach my $ioslot (keys %{ $hwresref->{'io'} })
                {
                    #io_slots=21010200/none/1,21010201/none/1
                    $prof .= "$hwresref->{'io'}->{$ioslot}->{'drc_index'}\/$hwresref->{'io'}->{$ioslot}->{'slot_io_pool_id'}\/1,";
                }

                # Remove the additional ","
                $prof =~ s/,$//;

                $prof .= "\\\"";

                # Virtual SCSI adapters
                $prof .= ",\\\"virtual_scsi_adapters=";

                # One virtual SCSI server adapter per LPAR
                if ($::NUMBEROFLPARS)
                {
                    my $i = 1;
                    while ($i <= $::NUMBEROFLPARS)
                    {
                        my $slotid = 10 + $i;
                        $prof .= "$slotid/server/any//any/0,";
                        $i++;
                    }
                }

                # Remove the additional ","
                $prof =~ s/,$//;
                $prof .= "\\\"";
                $prof .= ",max_virtual_slots=100";

                # LHEA - map each LHEA physical ports to the VIOS and LPARs
                my $heastr = &get_lhea_logical_ports($hwresref->{'hea'});
                $prof .= $heastr;

                $prof .= ",auto_start=1,boot_mode=norm";


                $cmd = "mksyscfg -r lpar -m $sys -i \'$prof\'";
                print "cmd = $cmd\n";
                $outref = &run_hmc_cmd($hmc, $cmd);
            }    # end if $::VIO
                 # Create LPARs
            if ($::NUMBEROFLPARS)
            {
                my $i = 0;
                while ($i < $::NUMBEROFLPARS)
                {
                    $i++;

                    my $prof = "name=" . $::prefix . "lpar$i,profile_name=" . $::prefix . "lpar$i,lpar_env=aixlinux";

                    my $cpustr = generate_cpu_conf($hwresref);
                    $prof .= $cpustr;

                    my $memstr = generate_mem_conf($hwresref);
                    $prof .= $memstr;

                    # Virtual SCSI adapters
                    $prof .= ",\\\"virtual_scsi_adapters=";
                    my $slotid = 10 + $i;
                    $prof .= "$slotid/client//" . $::prefix . "vio/$slotid/0,";

                    # Remove the additional ","
                    $prof =~ s/,$//;
                    $prof .= "\\\"";
                    $prof .= ",max_virtual_slots=100";

                    # LHEA - map each LHEA physical ports to the VIOS and LPARs
                    my $heastr = &get_lhea_logical_ports($hwresref->{'hea'});
                    $prof .= $heastr;

                    $prof .= ",auto_start=1,boot_mode=norm";

                    $cmd = qq~mksyscfg -r lpar -m $sys -i \'$prof\'~;
                    print "cmd = $cmd\n";
                    $outref = &run_hmc_cmd($hmc, $cmd);
                }
            }

        }    # end if foreach system
    }    # end if foreach hmc

    return;

}

#-------------------------------------------------------------------------------

=head3
      usage

        puts out  usage message  for help

        Arguments:
          None

        Returns:

        Globals:

        Error:
                None


=cut

#-------------------------------------------------------------------------------

sub usage
{
    my $usagemsg = " configcec <CECs List> -n <number of lpars> <--prefix> [--vio] [--cpu <desired_cpu_per_lpar>] [--mem <memory_of_MB_per_lpar>] [-V]
 configcec <CECs List> --hea_mcs <MCS value> [-V]
 configcec <CECs List> --init [-V]
 configcec <CECs List> --removelpars lpars_ids_list [-V]
 configcec -h\n";
    my $rsp = {};
    $rsp->{data}->[0] = $usagemsg;
    xCAT::MsgUtils->message("I", $rsp, $::CALLBACK, 0);
    return;
}

#-------------------------------------------------------------------------------

=head3
      parse_hmc_output
         Parse the HMC commands output, the HMC commands output lines looks like:
         attr1=val1,attr2=val2,"attr3=val3,val4,val5",attr4=val6

        Arguments:
          None

        Returns:
          Hash reference that use the attrs as key and vals as value

        Globals:

        Error:

=cut

#-------------------------------------------------------------------------------
sub parse_hmc_output()
{
    my ($output) = @_;

    my @outa = split /,/, $output;

    my $prevattr;
    my %strhash;
    foreach my $str (@outa)
    {
        $str =~ s/"//g;

        if ($str =~ /^(.*)=(.*)$/)
        {
            $prevattr = $1;
            $strhash{$1} = $2;
        }
        else
        {
            $strhash{$prevattr} .= ",$str";
        }
    }
    return \%strhash;
}

#-------------------------------------------------------------------------------

=head3
      run_hmc_command
          Run hmc commands remotely through ssh

        Arguments:
          $hmc - HMC hostname or ip address
          $cmd - The command that will be run on the HMC

        Returns:
          Hash reference for HMC commands output

        Globals:

        Error:

=cut

#-------------------------------------------------------------------------------
sub run_hmc_cmd()
{
    my ($hmc, $hmccmd) = @_;

    my $cmd = "ssh hscroot\@$hmc \"$hmccmd\"";
    my $outref = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Failed to run command $cmd, the error is:\n$outref\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 0);
        return undef;
    }
    else
    {
        return $outref;
    }
}

#-------------------------------------------------------------------------------

=head3
       get_lhea_logical_ports
          Get available LHEA logical ports for the lpar, and generate conf line

        Arguments:
          $lhearesref - Hash reference for LHEA resources

        Returns:
          Conf line for LHEA used by mksyscfg

        Globals:

        Error:

=cut

#-------------------------------------------------------------------------------
sub get_lhea_logical_ports()
{
    my ($hearesref) = @_;
    my $res;

    $res .= ",\\\"lhea_logical_ports=";
    foreach my $hea_adapter (keys %{$hearesref})
    {
        foreach my $port_group (keys %{ $hearesref->{$hea_adapter} })
        {
            my $unassigned_logical_port_ids = $hearesref->{$hea_adapter}->{$port_group}->{'unassigned_logical_port_ids'};
            my %available_lports = ();
            foreach my $lport (split /,/, $unassigned_logical_port_ids)
            {
                $available_lports{$lport} = 1;
            }
            my $phys_port_ids = $hearesref->{$hea_adapter}->{$port_group}->{'phys_port_ids'};
            foreach my $physport (split /,/, $phys_port_ids)
            {
                # Numberical sort the LHEA logical ports
                my $lport = (sort { $a <=> $b } (keys %available_lports))[0];
                if (!$lport)
                {
                    my $rsp = {};
                    $rsp->{data}->[0] = "No LHEA logical port available, do not assign LHEA logical ports to this partition\n";
                    xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 0);
                    return "";
                }
                $res .= "$hea_adapter/$port_group/$physport/$lport/all,";
                delete $available_lports{$lport};
            }
            $hearesref->{$hea_adapter}->{$port_group}->{'unassigned_logical_port_ids'} = join(',', keys %available_lports);
        }
    }

    # Remove the additional ","
    $res =~ s/,$//;
    $res .= "\\\"";
    return $res;
}

sub generate_cpu_conf()
{
    my ($hwresref) = @_;
    my $res;

    my $min_proc_units;
    my $desired_proc_units;
    my $max_proc_units;
    if ($::cpu)
    {
        $min_proc_units     = $::cpu / 2;
        $desired_proc_units = $::cpu;
        $max_proc_units     = $::cpu * 2;
    }
    else    #Default one CPU
    {
        $min_proc_units     = 0.5;
        $desired_proc_units = 1;
        $max_proc_units     = 2;
    }

    # Update hwres to reflect the CPU usage by VIO server
    $hwresref->{'proc'}->{'curr_avail_sys_proc_units'} -= $desired_proc_units;

    # Virtual CPU number: 2
    $res = ",proc_mode=shared,min_proc_units=$min_proc_units,desired_proc_units=$desired_proc_units,max_proc_units=$max_proc_units,min_procs=1,desired_procs=2,max_procs=3,sharing_mode=cap";

    return $res;
}

sub generate_mem_conf()
{
    my ($hwresref) = @_;

    my $res;
    my $min_mem;
    my $desired_mem;
    my $max_mem;
    if ($::memory)
    {
        $min_mem     = $::memory / 2;
        $desired_mem = $::memory;
        $max_mem     = $::memory * 2;
    }
    else    #Default 2GB for VIO server
    {
        $min_mem     = 1024;
        $desired_mem = 2048;
        $max_mem     = 4096;
    }
    $res .= ",min_mem=$min_mem,desired_mem=$desired_mem,max_mem=$max_mem";

    # Update hwres to reflect the CPU usage by VIO server
    $hwresref->{'mem'}->{'curr_avail_sys_mem'} -= $desired_mem;
    return $res;
}
1;
