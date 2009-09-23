# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#This plugin enables stateless boot of IBM Bootable Media Creator as
#a provisioning target.
#Instead of 'genimage', the first step here is to visit IBM support website
#and download the bootable media creator utility 
#Download the version intended to run on your management node, regardless of
#the managed node platform.  I.e. if your management node is RHEL5 and your 
#managed nodes are SLES10, an example download would be:
#https://www-947.ibm.com/systems/support/supportsite.wss/docdisplay?lndocid=MIGR-5079820&brandind=5000008
#Then, execute the utility.  Mostly choose preferred options, but you must:
#-Use '--tui' (this instructs ToolsCenter to evoke the text startup path that xCAT coopts
#-Use --pxe /instal/netboot/bomc/x86_64/compute (x86_64 may be x86 and compute may be whatever profile name is preferable).
#-m should be given a list of 'machine type' numbers.  If the nodes underwent 
#the xCAT discovery process, this can be extracted from the vpd.mtm property:
#$ nodels n3 vpd.mtm
#n3: 7321
#It should then be possible to run 'nodeset <noderange> netboot=bomc-x86_64-compute'
#Future ToolsCenter enhancements may dictate that we drop support for version 1.10 to cleanly take advantage of it



package xCAT_plugin::toolscenter;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use Storable qw(dclone);
use Sys::Syslog;
use Thread qw(yield);
use POSIX qw(WNOHANG nice);
use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::SvrUtils;
#use Data::Dumper;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use File::Path;
use File::Copy;
use File::Temp qw/mkdtemp/;
my @cpiopid;


sub handled_commands
{
    return {
            mknetboot => "nodetype:os=(bomc.*)|(toolscenter.*)",
            };
}

sub preprocess_request
{
    my $req      = shift;
    my $callback = shift;
    return [$req]; #calls are only made from pre-farmed out scenarios
    if ($req->{command}->[0] eq 'copycd')
    {    #don't farm out copycd
        return [$req];
    }

    my $stab = xCAT::Table->new('site');
    my $sent;
    ($sent) = $stab->getAttribs({key => 'sharedtftp'}, 'value');
    unless (    $sent
            and defined($sent->{value})
            and ($sent->{value} =~ /no/i or $sent->{value} =~ /0/))
    {

        #unless requesting no sharedtftp, don't make hierarchical call
        return [$req];
    }

    my %localnodehash;
    my %dispatchhash;
    my $nrtab = xCAT::Table->new('noderes');
    my $nrents = $nrtab->getNodesAttribs($req->{node},[qw(tftpserver servicenode)]);
    foreach my $node (@{$req->{node}})
    {
        my $nodeserver;
        my $tent = $nrents->{$node}->[0]; #$nrtab->getNodeAttribs($node, ['tftpserver']);
        if ($tent) { $nodeserver = $tent->{tftpserver} }
        unless ($tent and $tent->{tftpserver})
        {
            $tent = $nrents->{$node}->[0]; #$nrtab->getNodeAttribs($node, ['servicenode']);
            if ($tent) { $nodeserver = $tent->{servicenode} }
        }
        if ($nodeserver)
        {
            $dispatchhash{$nodeserver}->{$node} = 1;
        }
        else
        {
            $localnodehash{$node} = 1;
        }
    }
    my @requests;
    my $reqc = {%$req};
    $reqc->{node} = [keys %localnodehash];
    if (scalar(@{$reqc->{node}})) { push @requests, $reqc }

    foreach my $dtarg (keys %dispatchhash)
    {    #iterate dispatch targets
        my $reqcopy = {%$req};    #deep copy
        $reqcopy->{'_xcatdest'} = $dtarg;
        $reqcopy->{node} = [keys %{$dispatchhash{$dtarg}}];
        push @requests, $reqcopy;
    }
    return \@requests;
}

sub process_request
{
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my $distname = undef;
    my $arch     = undef;
    my $path     = undef;

    if ($request->{command}->[0] eq 'mknetboot')
    {
        return mknetboot($request, $callback, $doreq);
    }
}

sub mknetboot
{
    my $req      = shift;
    my $callback = shift;
    my $doreq    = shift;
    my $tftpdir  = "/tftpboot";
    my $nodes    = @{$request->{node}};
    my @args     = @{$req->{arg}};
    my @nodes    = @{$req->{node}};
    my $ostab    = xCAT::Table->new('nodetype');
    my $sitetab  = xCAT::Table->new('site');
    my $installroot;
    $installroot = "/install";
    my $xcatiport;

    if ($sitetab)
    {
        (my $ref) = $sitetab->getAttribs({key => installdir}, value);
        if ($ref and $ref->{value})
        {
            $installroot = $ref->{value};
        }
        ($ref) = $sitetab->getAttribs({key => xcatiport}, value);
        if ($ref and $ref->{value})
        {
            $xcatiport = $ref->{value};
        }
    }
    my %donetftp=();
    my %oents = %{$ostab->getNodesAttribs(\@nodes,[qw(os arch profile)])};
    my $restab = xCAT::Table->new('noderes');
    my $bptab  = xCAT::Table->new('bootparams',-create=>1);
    my $hmtab  = xCAT::Table->new('nodehm');
    my $reshash    = $restab->getNodesAttribs(\@nodes, ['tftpserver','xcatmaster']);
    my $hmhash =
          $hmtab->getNodesAttribs(\@nodes,
                                 ['serialport', 'serialspeed', 'serialflow']);
    #my $addkcmdhash =
    #    $bptab->getNodesAttribs(\@nodes, ['addkcmdline']);
    foreach $node (@nodes)
    {
        my $ent = $oents{$node}->[0]; #ostab->getNodeAttribs($node, ['os', 'arch', 'profile']);
        unless ($ent->{os} and $ent->{arch} and $ent->{profile})
        {
            $callback->(
                        {
                         error     => ["Insufficient nodetype entry for $node"],
                         errorcode => [1]
                        }
                        );
            next;
        }

        my $osver = $ent->{os};
        my $platform;
        my $arch    = $ent->{arch};
        my $profile = $ent->{profile};
        my $suffix  = 'gz';
        unless ( -r "/$installroot/netboot/$osver/$arch/$profile/img2a" and -r "/$installroot/netboot/$osver/$arch/$profile/img3a") {
            $callback->(
                        {
                         error     => ["Unavailable or unrecognized IBM ToolsCenter image in $installroot/netboot/$osver/$arch/$profile/"],
                         errorcode => [1]
                        }
                        );
            next;
        }
        unless ( -r "/$installroot/netboot/$osver/$arch/$profile/img2b" ) {
            system("dd if=/$installroot/netboot/$osver/$arch/$profile/img2a of=/$installroot/netboot/$osver/$arch/$profile/img2b bs=2048 skip=1");
        }
        unless ( -r "/$installroot/netboot/$osver/$arch/$profile/img3b" ) {
            system("dd if=/$installroot/netboot/$osver/$arch/$profile/img3a of=/$installroot/netboot/$osver/$arch/$profile/img3b bs=2048 skip=1");
        }
        unless ( -r "/$installroot/netboot/$osver/$arch/$profile/tc.xcat.zip" ) {
            my $dpath = mkdtemp("/tmp/xcat/toolscenter.$$.XXXXXXX");
            unless (-d $dpath) {
                $callback->({error => ["Failure creating temporary directory to extract ToolsCenter content for xCAT customization" ], errorcode => [1]});
                return 1;
            }
            chdir $dpath;
            system("unzip /$installroot/netboot/$osver/$arch/$profile/tc.zip");
            my $menush;
            open($menush,">","menu/menu.sh");
            print $menush "#!/bin/sh\n";
            print $menush '${UXSPI_BINARY_PATH} update --unattended --firmware -l ${UXSPI_BOOTABLE} --timeout=${UXSPI_TIMEOUT}'."\n";
            print $menush 'if [ $? ]; then /bin/sh; fi'."\n";#TODO: proper feedback
            print $menush 'DIR=`dirname $0`'."\n";
            print $menush '$DIR/calltoxcat.awk ${xcat_server} '."$xcatiport\n";
            print $menush "reboot\n";
            close($menush);
            open($menush,">","menu/calltoxcat.awk");
            print $menush <<'ENDOFAWK';
#!/bin/awk -f
BEGIN {
    xcatdhost = ARGV[1]
    xcatdport = ARGV[2]
    flag = ARGV[3]
    
        if (!flag) flag = "next"

        ns = "/inet/tcp/0/" ARGV[1] "/" xcatdport

        while(1) {
                if((ns |& getline) > 0)
                        print $0 | "logger -t xcat"

                if($0 == "ready")
                        print flag |& ns
                if($0 == "done")
                        break
        }

        close(ns)

        exit 0
}
ENDOFAWK
            close($menush);
            system("zip /$installroot/netboot/$osver/$arch/$profile/tc.xcat.zip -r .");
            chdir ..
            system("rm -rf $dpath");
        }
                
        mkpath("/$tftpdir/xcat/netboot/$osver/$arch/$profile/");

        #TODO: only copy if newer...
        unless ($donetftp{$osver,$arch,$profile}) {
        copy("/$installroot/netboot/$osver/$arch/$profile/img2b",
             "/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
        copy("/$installroot/netboot/$osver/$arch/$profile/img3b",
             "/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
        copy("/$installroot/netboot/$osver/$arch/$profile/tcrootfs",
             "/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
        copy("/$installroot/netboot/$osver/$arch/$profile/tc.xcat.zip",
             "/$tftpdir/xcat/netboot/$osver/$arch/$profile/tc.zip");
            $donetftp{$osver,$arch,$profile} = 1;
        }
        unless (    -r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/img2b"
                and -r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/img3b")
        {
            $callback->(
                {
                 error => [
                     "Copying to /$tftpdir/xcat/netboot/$osver/$arch/$profile failed"
                 ],
                 errorcode => [1]
                }
                );
            next;
        }
        my $ent    = $reshash->{$node}->[0];#$restab->getNodeAttribs($node, ['primarynic']);
        my $sent   = $hmhash->{$node}->[0];
#          $hmtab->getNodeAttribs($node,
#                                 ['serialport', 'serialspeed', 'serialflow']);

        # determine image server, if tftpserver use it, else use xcatmaster
        # last resort use self
        my $imgsrv;
        my $ient;
        my $xcatserver;
        if ($reshash->{$node}->[0]->{xcatmaster}) {
            $xcatserver = $reshash->{$node}->[0]->{xcatmaster};
        } else {
            $xcatserver = '!myipfn!';
        }
        $ient = $reshash->{$node}->[0]; #$restab->getNodeAttribs($node, ['tftpserver']);
        if ($ient and $ient->{tftpserver})
        {
            $imgsrv = $ient->{tftpserver};
        }
        else
        {
            $imgsrv = $xcatserver;
        }

        unless ($imgsrv)
        {
            $callback->(
                {
                 error => [
                     "Unable to determine or reasonably guess the image server for $node"
                 ],
                 errorcode => [1]
                }
                );
            next;
        }
        my $kcmdline = "root=/dev/ram0 rw ramdisk_size=100000 tftp_server=$imgsrv tftp_tcrootfs=xcat/netboot/$osver/$arch/$profile/tcrootfs tftp_tczip=xcat/netboot/$osver/$arch/$profile/tc.zip xcat_server=$xcatserver";
        if (defined $sent->{serialport})
        {

            #my $sent = $hmtab->getNodeAttribs($node,['serialspeed','serialflow']);
            unless ($sent->{serialspeed})
            {
                $callback->(
                    {
                     error => [
                         "serialport defined, but no serialspeed for $node in nodehm table"
                     ],
                     errorcode => [1]
                    }
                    );
                next;
            }
            $kcmdline .=
              " console=tty0 console=ttyS" . $sent->{serialport} . "," . $sent->{serialspeed};
            if ($sent->{serialflow} =~ /(hard|tcs|ctsrts)/)
            {
                $kcmdline .= "n8r";
            }
        }
        # add the addkcmdline attribute  to the end
        # of the command, if it exists
        #my $addkcmd   = $addkcmdhash->{$node}->[0];
        # add the extra addkcmd command info, if in the table
        #if ($addkcmd->{'addkcmdline'}) {
        #        $kcmdline .= " ";
        #        $kcmdline .= $addkcmd->{'addkcmdline'};
           
        #}
        
	    my $kernstr="xcat/netboot/$osver/$arch/$profile/img2b";
        $bptab->setNodeAttribs(
                      $node,
                      {
                       kernel => "$kernstr",
                       initrd => "xcat/netboot/$osver/$arch/$profile/img3b",
                       kcmdline => $kcmdline
                      }
                      );
    }

    #my $rc = xCAT::Utils->create_postscripts_tar();
    #if ( $rc != 0 ) {
    #	xCAT::MsgUtils->message( "S", "Error creating postscripts tar file." );
    #}
}

1;
