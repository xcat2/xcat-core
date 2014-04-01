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
use xCAT::TableUtils;
use xCAT::MsgUtils;
use xCAT::SvrUtils;
#use Data::Dumper;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use File::Path;
use File::Copy;
use File::stat;
use File::Temp qw/mkdtemp/;
use strict;
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

    #my $stab = xCAT::Table->new('site');
    #my $sent;
    #($sent) = $stab->getAttribs({key => 'sharedtftp'}, 'value');
    my @entries =  xCAT::TableUtils->get_site_attribute("sharedtftp");
    my $t_entry = $entries[0];
    unless (  defined($t_entry)
            and ($t_entry eq "no" or $t_entry eq "NO"  or $t_entry eq "0"))
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
    unless ($req->{arg}) {
        $req->{arg} = [];
    }
    my @args     = @{$req->{arg}};
    my @nodes    = @{$req->{node}};
    my $ostab    = xCAT::Table->new('nodetype');
    #my $sitetab  = xCAT::Table->new('site');

    my $installroot = xCAT::TableUtils->getInstallDir();
    my $tftpdir = xCAT::TableUtils->getTftpDir();

    my $xcatiport;

    #if ($sitetab)
    #{
        #(my $ref) = $sitetab->getAttribs({key => 'xcatiport'}, 'value');
        my @entries =  xCAT::TableUtils->get_site_attribute("xcatiport");
        my $t_entry = $entries[0];
        if ( defined($t_entry) )
        {
            $xcatiport = $t_entry;
        }
    #}
    my %oents = %{$ostab->getNodesAttribs(\@nodes,[qw(os arch profile)])};
    my $restab = xCAT::Table->new('noderes');
    my $bptab  = xCAT::Table->new('bootparams',-create=>1);
    my $hmtab  = xCAT::Table->new('nodehm');
    my $firmtab  = xCAT::Table->new('firmware');
    my $firmhash  = $firmtab->getNodesAttribs(\@nodes, ['cfgfile']);
    my $reshash    = $restab->getNodesAttribs(\@nodes, ['tftpserver','xcatmaster']);
    my $hmhash =
          $hmtab->getNodesAttribs(\@nodes,
                                 ['serialport', 'serialspeed', 'serialflow']);
    #my $addkcmdhash =
    #    $bptab->getNodesAttribs(\@nodes, ['addkcmdline']);
    foreach my $node (@nodes)
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
	my $path = "/$installroot/netboot/$osver/$arch/$profile";
	my $tpath = "/$tftpdir/xcat/netboot/$osver/$arch/$profile";
	my $firmfile = $firmhash->{$node}->[0]->{cfgfile};   
	if ($firmfile) {
	  copy($firmfile,"$path/repo/$node.cfgfile");
	}
	my $asu = "/toolscenter/asu";
	if ($ent->{arch} eq "x86_64") {
	    $asu = "/toolscenter/asu64";
	}
        unless ( -r "$path/img2a" and -r "$path/img3a" and -r "$path/tc.zip") {
            $callback->(
                        {
                         error     => ["Unavailable or unrecognized IBM ToolsCenter image in $path"],
                         errorcode => [1]
                        }
                        );
            next;
        }
        unless (-r "$path/img2b" and # but not if it's newer
                stat("$path/img2b")->mtime > stat("$path/img2a")->mtime) {
            system("dd if=$path/img2a of=$path/img2b bs=2048 skip=1");
        }
        unless (-r "$path/img3b"  and # but not if it's newer
                stat("$path/img3b")->mtime > stat("$path/img3a")->mtime) {
            system("dd if=$path/img3a of=$path/img3b bs=2048 skip=1");
        }
        unless (-r "$path/tc.xcat.zip" and 
# regen if tc.zip is newer - they updated the repo underneath us
     		stat("$path/tc.xcat.zip")->mtime > stat("$path/tc.zip")->mtime) {
            my $dpath = mkdtemp("/tmp/xcat/toolscenter.$$.XXXXXXX");
            unless (-d $dpath) {
                $callback->({error => ["Failure creating temporary directory to extract ToolsCenter content for xCAT customization" ], errorcode => [1]});
                return 1;
            }
            chdir $dpath;
            system("unzip $path/tc.zip");
            my $menush;
            open($menush,">","menu/menu.sh");
            print $menush "#!/bin/sh -x\n";
            print $menush 'LOG_PATH=/bomc/${hostname}',"\n";
            print $menush 'mkdir -p $LOG_PATH',"\n";
            print $menush 'ERROR_FILE=/bomc/${hostname}/bomc.error',"\n";
            print $menush 'LOG_FILE=/bomc/${hostname}/bomc.log',"\n";
            print $menush '${UXSPI_BINARY_PATH} update --unattended --firmware -l ${UXSPI_BOOTABLE} --timeout=${UXSPI_TIMEOUT} >${LOG_FILE} 2>${ERROR_FILE}'."\n";
            print $menush 'DIR=`dirname $0`'."\n";
            print $menush 'ERROR_FILE=/bomc/${hostname}/asu.error',"\n";
            print $menush 'LOG_FILE=/bomc/${hostname}/asu.log',"\n";
            print $menush 'if [ "${cmos_file}" != "" ]; then',"\n";
            print $menush "  $asu",' batch ${cmos_file} >${LOG_FILE} 2>${ERROR_FILE}', "\n";
            print $menush "fi\n";
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
                        print $0 | "logger -p local4.info -t xcat"

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
            open($menush,"<","menu/unattended_menu.sh");
            my @oldunattendmenu = <$menush>; #store old menu;
            close($menush);
            open($menush,">","menu/unattended_menu.sh");
            foreach (@oldunattendmenu) {
                if (/^exit 0/) { #the exit line, hijack this
                    print $menush 'DIR=`dirname $0`'."\n";
                    print $menush 'mkdir -p $LOG_PATH',"\n";
                    print $menush 'ERROR_FILE=/bomc/${hostname}/asu.error',"\n";
                    print $menush 'LOG_FILE=/bomc/${hostname}/asu.log',"\n";
                    print $menush 'if [ ${cmos_file} != "" ]; then',"\n";
                    print $menush "  $asu",' batch ${cmos_file} >${LOG_FILE} 2>${ERROR_FILE}', "\n";
                    print $menush "fi\n";
                    print $menush '$DIR/calltoxcat.awk ${xcat_server} '."$xcatiport\n";
                    print $menush "reboot\n";
                } else {
                    print $menush $_;
                }
            }
            close($menush);
            system("zip $path/tc.xcat.zip -r .");
            chdir "..";
            system("rm -rf $dpath");
        }
                
        mkpath($tpath);

	unless ( -r "$tpath/img2b"  and 
           stat("$path/img2b")->mtime < stat("$tpath/img2b")->mtime) {
          copy("$path/img2b",$tpath);
	}
	unless ( -r "$tpath/img3b"  and 
           stat("$path/img3b")->mtime < stat("$tpath/img3b")->mtime) {
          copy("$path/img3b",$tpath);
	}
	unless ( -r "$tpath/tcrootfs"  and 
           stat("$path/tcrootfs")->mtime < stat("$tpath/tcrootfs")->mtime) {
          copy("$path/tcrootfs",$tpath);
	}
	unless ( -r "$tpath/tc.zip"  and 
          stat("$path/tc.xcat.zip")->mtime < stat("$tpath/tc.zip")->mtime) {
          copy("$path/tc.xcat.zip","$tpath/tc.zip");
        }
        unless ( -r "$tpath/img2b" and -r "$tpath/img3b" and
	 	-r "$tpath/tcrootfs" and -r "$tpath/tc.zip")
        {
            $callback->(
                {
                 error => [ "Copying to $tpath failed" ],
                 errorcode => [1]
                }
                );
            next;
        }
        $ent    = $reshash->{$node}->[0];#$restab->getNodeAttribs($node, ['primarynic']);
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
	$tpath =~ s!/$tftpdir/!!;
        my $kcmdline = "vga=0x317 root=/dev/ram0 rw ramdisk_size=100000 tftp_server=$imgsrv tftp_tcrootfs=$tpath/tcrootfs tftp_tczip=$tpath/tc.zip xcat_server=$xcatserver hostname=$node";
	if ($firmfile) {
		$kcmdline .= " cmos_file=/bomc/$node.cfgfile";
	}
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
        
	    my $kernstr="$tpath/img2b";
        $bptab->setNodeAttribs(
                      $node,
                      {
                       kernel => "$kernstr",
                       initrd => "$tpath/img3b",
                       kcmdline => $kcmdline
                      }
                      );
    }

    #my $rc = xCAT::TableUtils->create_postscripts_tar();
    #if ( $rc != 0 ) {
    #	xCAT::MsgUtils->message( "S", "Error creating postscripts tar file." );
    #}
}

1;
