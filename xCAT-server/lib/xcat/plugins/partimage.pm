# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::partimage;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use Storable qw(dclone);
use Sys::Syslog;
use File::Temp qw/tempdir/;
use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::Template;
use xCAT::Postage;
use Data::Dumper;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use File::Path;
use File::Copy;

my $pImageDir = "$::XCATROOT/share/xcat/install/partimage";
my $tftpDir = "/tftpboot";
my @cpiopid;

sub handled_commands
{
	return {
		mkinstall => "nodetype:os=imagecapture|imagerestore",
	};
}

sub process_request
{
	my $request  = shift;
	my $callback = shift;
	my $doreq    = shift;
	my $distname = undef;
	my $arch     = undef;
	my $path     = undef;
	if($request->{command}->[0] eq 'mkinstall'){
		return mkinstall($request, $callback, $doreq);
  }else{
		errorSig($callback, "Error in partimage plugin, shouldn't call anything other than mkinstall function");
	}
}


sub errorSig {
	$callback = shift;
	$msg = shift;
	$callback->({
		error => ["$msg"],
		errorcode => [1]
	});
}

# function used for creating boot attributes for partimage functionality.
sub mkinstall {
	# we should be passed in the request which has the list of nodes
	my $request  = shift;
	# The callback function for what to print out and do with results.
	my $callback = shift;
	# doreq isn't used here, but we shift for good measure.
	my $doreq    = shift;
	my @nodes    = @{$request->{node}};
	my $node;
	# read the nodetype table for our nodes.
	my $ostab = xCAT::Table->new('nodetype');
	my %doneimgs;
	my $mode;

	# go through each node:
	# 1. Verify that nodetype table is filled out and accurate
	# 2. Create auto file by subbing through variables.
	foreach $node (@nodes){
		my $osinst;
		my $ent = $ostab->getNodeAttribs($node, ['profile', 'os', 'arch']);
		# Verify that the user configured the tables like we expect them to.
		# if not, then give them a stern warning.
		unless ($ent->{os}){
			errorSig($callback, "No OS defined in nodetype for $node.  OS types for partimage should be imagecapture or imagerestore");
			next;
		}
		unless($ent->{arch}){
			errorSig($callback, "No arch defined in nodetype for $node. only x86 and x86_64 supported");
			next;
		}
		unless($ent->{profile}){
			errorSig($callback, "No profile defined in nodetype for $node.  Default profile types are found in $pImageDir");
			next;
		}
		my $os      = $ent->{os};
		my $arch    = $ent->{arch};
		my $profile = $ent->{profile};

		if($os eq "imagecapture"){
			$mode = "capture";
		}
		elsif($os eq "imagerestore"){
			$mode = "restore";
		}else{
			errorSig($callback, "Unrecognized mode: $os.  Should be imagecapture or imagerestore for partimage");
			next;
		}

		# This is step 2. Take the template file and sub in the variables
		# so that there is a file in /install/autoinst/$node for each node
		my $tmplfile=get_tmpl_file_name("/install/custom/install/partimage", $profile, $os, $arch);
		if (! $tmplfile) { $tmplfile=get_tmpl_file_name($pImageDir, $profile, $os, $arch); }
		unless ( -r "$tmplfile"){
			errorSig($callback, "No profile template exists for $profile");
			next;
		}

		my $instDir = xCAT::Utils->get_site_attribute("installdir");
		if(! defined($instDir)){
			$instDir = "/install";
		}

		#Call the Template class to do substitution to produce the file
		my $tmperr = xCAT::Template->subvars(
			$tmplfile,
			"$instDir/autoinst/$node",
			$node
		);
		# if there were problems during substitution then let the user know
		# about it.
		if ($tmperr){
			$callback->({
				node => [{
					name      => [$node],
					error     => [$tmperr],
					errorcode => [1]
				}]
			});
			next;
		}
	
		# part 3.  Create the image capture/restore image
		# this is just a repackaging of the existing xCAT nbfs
		# partimage uses the 32 bit one.  No problems if its 64 bit
		# the 32 bit will still work.  This way we can capture 64 bit
		# and 64 bit os's.  What a clever tool!

		unless ($doneimgs{"$os|$arch"}){
			mkpath("$tftpDir/xcat/partimage/x86");
			mkpath("$instDir/partimage");

			# verify ramdisk is there
			if(-r "$tftpDir/xcat/nbfs.x86.gz"){
				copy("$tftpDir/xcat/nbfs.x86.gz", "$tftpDir/xcat/partimage/x86/");
			}else{
				errorSig($callback, "$tftpDir/xcat/nbfs.x86.gz was not found, please run 'mknb x86' first.");
			}

			# verify that kernel is there
			if(-r "$tftpDir/xcat/nbk.x86"){
				copy("$tftpDir/xcat/nbk.x86", "$tftpDir/xcat/partimage/x86/");
			}else{
				errorSig($callback, "$tftpDir/xcat/nbk.x86 was not found, please run 'mknb x86' first.");
			}

			# now get the image supped up
			mkPartImage($node,$tftpDir,$callback);
			$doneimgs{"$os|$arch"} = 1;
		}

		# part 4.  Create the boot parameters for the machine.
		#
		# if there was an error then setBootParams will return 1;
		# if there is no error it will return 0.
		if(setBootParams($node,$callback, $instDir, $mode)){
			next;
		}
	}		
}


sub mkPartImage{
	# modify nbfs.tgz 
	my $node = shift;
	my $tftpDir = shift;
	my $callback = shift;
	my $pDataDir = "$pImageDir/data";
	my $pNbDir = "$tftpDir/xcat/partimage/x86/tmp";
# $callback->({data=>["Creating nbfs.$arch.gz in $tftpdir/xcat"]});
	print "$pNbDir";
	# remove this directory if it exists.
	if(-d $pNbDir){
		rmtree("$pNbDir");
		#	errorSig($callback, "could not remove $pNbDir");
	}
	if(-r "$pNbDir/../pnbfs.x86.gz"){
		unless(unlink("$pNbDir/../pnbfs.x86.gz") == 0 ){
			errorSig($callback, "could not remove $pNbDir/../pnbfs.x86.gz\n");
		}
	}
	mkpath($pNbDir);
	$callback=>({data=>["cd $pNbDir; gunzip -c ../nbfs.x86.gz | cpio -id"]});	
	system("cd $pNbDir; gunzip -c ../nbfs.x86.gz | cpio -id");	


# Tput files
# /usr/bin/tput
	copy("$pDataDir/tput", "$pNbDir/usr/bin/");
	system("chmod 755 $pNbDir/usr/bin/");
	
# /lib/libdl.so.2
	copy("$pDataDir/lib/libdl.so.2", "$pNbDir/lib/");
# /usr/lib/libncursesw.so.5
	copy("$pDataDir/lib/libncursesw.so.5", "$pNbDir/usr/lib/");


	copy("$pDataDir/lib/ld-linux.so.2", "$pNbDir/lib/");
	system("chmod 755 $pNbDir/lib/ld-linux.so.2");

	copy("$pDataDir/lib/libc.so.6", "$pNbDir/lib/");
	system("chmod 755 $pNbDir/lib/libc.so.6");

	copy("$pDataDir/sfdisk", "$pNbDir/sbin");
	system("chmod 755 $pNbDir/sbin/sfdisk");

	copy("$pDataDir/e2fsck", "$pNbDir/sbin");
	system("chmod 755 $pNbDir/sbin/e2fsck");

	copy("$pDataDir/partimage", "$pNbDir/bin/");
	system("chmod 755 $pNbDir/bin/partimage");

	copy("$pDataDir/partimage.sh", "$pNbDir/etc/init.d/S80partimage.sh");

	unlink("$pNbDir/etc/init.d/S99xcat.sh");

	# we make a new nbfs.x86.gz and call it pnbfs.  Its really just
	# nbfs with some other things added and taken away.
	system("cd $pNbDir; find . | cpio -o -H newc | gzip -9 > $pNbDir/../pnbfs.x86.gz");	

	# remove all the junk after compressing the file.
	rmtree("$pNbDir");

}

# set the boot parameters of the node.  If we return 1 there is an error
# if we return 0 everything went according to plan.
sub setBootParams{
	my $node = shift;
	my $callback = shift;
	my $instDir = shift;
	my $mode = shift;
	# get all the info we need for the node:
	# ms, NIC, etc.
	my $restab = xCAT::Table->new('noderes');
	my $bptab = xCAT::Table->new('bootparams',-create=>1);
	my $hmtab  = xCAT::Table->new('nodehm');
	my $ent    =
		$restab->getNodeAttribs(
			$node,['nfsserver', 'primarynic', 'installnic']
		);
	my $sent =
		$hmtab->getNodeAttribs(
			$node, ['serialport', 'serialspeed', 'serialflow']
		);
	unless ($ent and $ent->{nfsserver}){
		errorSig($callback, "No noderes.nfsserver for $node defined");
    $callback->("No noderes.nfsserver for $node defined");
    return 1;
	}

	my $kernel = "xcat/partimage/x86/nbk.x86";
	my $initrd = "xcat/partimage/x86/pnbfs.x86.gz";
	my $kcmdline = "quiet";

	# console stuff
	if (defined $sent->{serialport}){
		unless ($sent->{serialspeed}){
			errorSig($callback, "serialport defined, but no serialspeed for $node in nodehm table");
			return 1;
		}
		$kcmdline .=
			" console=ttyS"
			. $sent->{serialport} . ","
			. $sent->{serialspeed};
		if($sent and ($sent->{serialflow} =~ /(ctsrts|cts|hard)/)){
			$kcmdline .= "n8r";
		}
	}

	# xcatd stuff	
	# get xCATd port:
	my $xPort = xCAT::Utils->get_site_attribute("xcatdport");
	$kcmdline .= " xcatd=" . $ent->{nfsserver} . ":" . $xPort;
	$kcmdline .= " pcfg=http://" . $ent->{nfsserver} . "/$instDir/autoinst/$node";
	$kcmdline .= " mode=$mode"; 
	$bptab->setNodeAttribs(
		$node, {
			kernel   => $kernel,
			initrd   => $initrd,
			kcmdline => $kcmdline
		}
	);
	return 0;
}


sub get_tmpl_file_name {
  my $base=shift;
  my $profile=shift;
  my $os=shift;
  my $arch=shift;
  if (-r   "$base/$profile.$os.$arch.tmpl") {
    return "$base/$profile.$os.$arch.tmpl";
  }
  elsif (-r "$base/$profile.$arch.tmpl") {
    return  "$base/$profile.$arch.tmpl";
  }
  elsif (-r "$base/$profile.$os.tmpl") {
    return  "$base/$profile.$os.tmpl";
  }
  elsif (-r "$base/$profile.tmpl") {
    return  "$base/$profile.tmpl";
  }

  return "";
}

1;
