# IBM(c) 2011 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head 1

    xCAT plugin to handle xCAT UI commands

=cut

#-------------------------------------------------------

package xCAT_plugin::web;
use strict;
require xCAT::Utils;
require xCAT::MsgUtils;
use Getopt::Long;
use Data::Dumper;
use LWP::Simple;
use xCAT::Table;
use xCAT::NodeRange;

sub handled_commands {
	return { webrun => "web", };
}

sub process_request {
	my $request         = shift;
	my $callback        = shift;
	my $sub_req         = shift;
	my %authorized_cmds = (
		'update'        => \&web_update,
		'lscondition'   => \&web_lscond,
		'lsresponse'    => \&web_lsresp,
		'lscondresp'    => \&web_lscondresp,
		'mkcondresp'    => \&web_mkcondresp,
		'startcondresp' => \&web_startcondresp,
		'stopcondresp'  => \&web_stopcondresp,
		'lsevent'       => \&web_lsevent,
		'unlock'        => \&web_unlock,
		'rmcstart'      => \&web_rmcmonStart,
		'rmcshow'       => \&web_rmcmonShow,
		'gangliastart'  => \&web_gangliastart,
		'gangliastop'   => \&web_gangliastop,
		'gangliastatus' => \&web_gangliastatus,
		'gangliacheck'  => \&web_gangliacheck,
		'installganglia'=> \&web_installganglia,
		'mkcondition'   => \&web_mkcondition,
		'monls'         => \&web_monls,
		'discover'      => \&web_discover,
		'updatevpd'     => \&web_updatevpd,
		'createimage'   => \&web_createimage
	);

	#check whether the request is authorized or not
	split ' ', $request->{arg}->[0];
	my $cmd = $_[0];
	if ( grep { $_ eq $cmd } keys %authorized_cmds ) {
		my $func = $authorized_cmds{$cmd};
		$func->( $request, $callback, $sub_req );
	} else {
		$callback->( { error => "$cmd is not authorized!\n", errorcode => [1] } );
	}
}

sub web_lsevent {
	my ( $request, $callback, $sub_req ) = @_;
	my @ret = `$request->{arg}->[0]`;

	#please refer the manpage for the output format of "lsevent"
	my $data   = [];
	my $record = '';
	my $i      = 0;
	my $j      = 0;

	foreach my $item (@ret) {
		if ( $item ne "\n" ) {
			chomp $item;
			my ( $key, $value ) = split( "=", $item );
			if ( $j < 2 ) {
				$record .= $value . ';';
			} else {
				$record .= $value;
			}

			$j++;
			if ( $j == 3 ) {
				$i++;
				$j = 0;
				push( @$data, $record );
				$record = '';
			}
		}

	}

	$callback->( { data => $data } );
}

sub web_mkcondresp {
	my ( $request, $callback, $sub_req ) = @_;
	my $conditionName = $request->{arg}->[1];
	my $temp          = $request->{arg}->[2];
	my $cmd           = '';
	my @resp          = split( ':', $temp );

	#create new associations
	if ( 1 < length( @resp[0] ) ) {
		$cmd = substr( @resp[0], 1 );
		$cmd =~ s/,/ /;
		$cmd = 'mkcondresp ' . $conditionName . ' ' . $cmd;
		my $retInfo = xCAT::Utils->runcmd( $cmd, -1, 1 );
	}

	#delete old associations
	if ( 1 < length( @resp[1] ) ) {
		$cmd = substr( @resp[1], 1 );
		$cmd =~ s/,/ /;
		$cmd = 'rmcondresp ' . $conditionName . ' ' . $cmd;
		my $retInfo = xCAT::Utils->runcmd( $cmd, -1, 1 );
	}

	#there's no output for "mkcondresp"
	$cmd = 'startcondresp ' . $conditionName;
	my $refInfo = xCAT::Utils->runcmd( $cmd, -1, 1 );
	$callback->( { data => "Success." } );
}

sub web_startcondresp {
	my ( $request, $callback, $sub_req ) = @_;
	my $conditionName = $request->{arg}->[1];
	my $cmd           = 'startcondresp "' . $conditionName . '"';
	my $retInfo       = xCAT::Utils->runcmd( $cmd, -1, 1 );
	$callback->( { data => 'start monitor "' . $conditionName . '" Successful.' } );
}

sub web_stopcondresp {
	my ( $request, $callback, $sub_req ) = @_;
	my $conditionName = $request->{arg}->[1];
	my $cmd           = 'stopcondresp "' . $conditionName . '"';
	my $retInfo       = xCAT::Utils->runcmd( $cmd, -1, 1 );
	$callback->( { data => 'stop monitor "' . $conditionName . '" Successful.' } );
}

sub web_lscond {
	my ( $request, $callback, $sub_req ) = @_;
	my $nodeRange = $request->{arg}->[1];
	my $names     = '';

	#list all the conditions on all lpars in this group
	if ($nodeRange) {
		my @nodes = xCAT::NodeRange::noderange($nodeRange);
		my %tempHash;
		my $nodeCount = @nodes;

		#no node in this group
		if ( 1 > $nodeCount ) {
			return;
		}

		#no conditions return
		my $tempCmd = 'lscondition -d :' . join( ',', @nodes );
		my $retInfo = xCAT::Utils->runcmd( $tempCmd, -1, 1 );
		if ( 1 > @$retInfo ) {
			return;
		}

		shift @$retInfo;
		shift @$retInfo;
		foreach my $line (@$retInfo) {
			my @temp = split( ':', $line );
			$tempHash{ @temp[0] }++;
		}

		foreach my $name ( keys(%tempHash) ) {
			if ( $nodeCount == $tempHash{$name} ) {
				$names = $names . $name . ';';
			}
		}
	}

	#only list the conditions on local.
	else {
		my $retInfo = xCAT::Utils->runcmd( 'lscondition -d', -1, 1 );
		if ( 2 > @$retInfo ) {
			return;
		}

		shift @$retInfo;
		shift @$retInfo;
		foreach my $line (@$retInfo) {
			my @temp = split( ':', $line );
			$names = $names . @temp[0] . ':' . substr( @temp[2], 1, 3 ) . ';';
		}
	}

	if ( '' eq $names ) {
		return;
	}

	$names = substr( $names, 0, ( length($names) - 1 ) );
	$callback->( { data => $names } );
}

sub web_mkcondition {
	my ( $request, $callback, $sub_req ) = @_;

	if ( 'change' eq $request->{arg}->[1] ) {
		my @nodes;
		my $conditionName = $request->{arg}->[2];
		my $groupName     = $request->{arg}->[3];

		my $retInfo = xCAT::Utils->runcmd( 'nodels ' . $groupName . " nodetype.nodetype", -1, 1 );
		foreach my $line (@$retInfo) {
			my @temp = split( ':', $line );
			if ( @temp[1] !~ /lpar/ ) {
				$callback->( { data => 'Error : only the compute nodes\' group could select.' } );
				return;
			}

			push( @nodes, @temp[0] );
		}

		xCAT::Utils->runcmd( 'chcondition -n ' + join( ',', @nodes ) + '-m m ' + $conditionName );
		$callback->( { data => 'Change scope success.' } );
	}

}

sub web_lsresp {
	my ( $request, $callback, $sub_req ) = @_;
	my $names = '';
	my @temp;
	my $retInfo = xCAT::Utils->runcmd( 'lsresponse -d', -1, 1 );

	shift @$retInfo;
	shift @$retInfo;
	foreach my $line (@$retInfo) {
		@temp = split( ':', $line );
		$names = $names . @temp[0] . ';';
	}

	$names = substr( $names, 0, ( length($names) - 1 ) );
	$callback->( { data => $names } );
}

sub web_lscondresp {
	my ( $request, $callback, $sub_req ) = @_;
	my $names = '';
	my @temp;

	#if there is condition name, then we only show the condition linked associations.
	if ( $request->{arg}->[1] ) {
		my $cmd = 'lscondresp -d ' . $request->{arg}->[1];
		my $retInfo = xCAT::Utils->runcmd( $cmd, -1, 1 );
		if ( 2 > @$retInfo ) {
			$callback->( { data => '' } );
			return;
		}

		shift @$retInfo;
		shift @$retInfo;
		for my $line (@$retInfo) {
			@temp = split( ':', $line );
			$names = $names . @temp[1] . ';';
		}
	}

	$names = substr( $names, 0, ( length($names) - 1 ) );
	$callback->( { data => $names } );
}

sub web_update {
	my ( $request, $callback, $sub_req ) = @_;
	my $os         = "unknow";
	my $RpmNames   = $request->{arg}->[1];
	my $repository = $request->{arg}->[2];
	my $FileHandle;
	my $cmd;
	my $ReturnInfo;
	my $WebpageContent    = undef;
	my $RemoteRpmFilePath = undef;
	my $LocalRpmFilePath  = undef;

	if ( xCAT::Utils->isLinux() ) {
		$os = xCAT::Utils->osver();

		#suse linux
		if ( $os =~ /sles.*/ ) {
			$RpmNames =~ s/,/ /g;

			#create zypper command
			$cmd = "zypper -n -p " . $repository . " update " . $RpmNames;
		}

		#redhat
		else {

			#check the yum config file, and delect it if exist.
			if ( -e "/tmp/xCAT_update.yum.conf" ) {
				unlink("/tmp/xCAT_update.yum.conf");
			}

			#create file, return error if failed.
			unless ( open( $FileHandle, '>>', "/tmp/xCAT_update.yum.conf" ) ) {
				$callback->( { error => "Create temp file error!\n", errorcode => [1] } );
				return;
			}

			#write the rpm path into config file.
			print $FileHandle "[xcat_temp_update]\n";
			print $FileHandle "name=temp prepository\n";
			$repository = "baseurl=" . $repository . "\n";
			print $FileHandle $repository;
			print $FileHandle "enabled=1\n";
			print $FileHandle "gpgcheck=0\n";
			close($FileHandle);

			#use system to run the cmd "yum -y -c config-file update rpm-names"
			$RpmNames =~ s/,/ /g;
			$cmd = "yum -y -c /tmp/xCAT_update.yum.conf update " . $RpmNames . " 2>&1";
		}

		#run the command and return the result
		$ReturnInfo = readpipe($cmd);
		$callback->( { info => $ReturnInfo } );
	}

	#AIX
	else {

		#open the rpmpath(may be error), and read the page's content
		$WebpageContent = LWP::Simple::get($repository);
		unless ( defined($WebpageContent) ) {
			$callback->( { error => "open $repository error, please check!!", errorcode => [1] } );
			return;
		}

		#must support for updating several rpms.
		foreach ( split( /,/, $RpmNames ) ) {

			#find out rpms' corresponding rpm href on the web page
			$WebpageContent =~ m/href="($_-.*?[ppc64|noarch].rpm)/i;
			unless ( defined($1) ) {
				next;
			}
			$RemoteRpmFilePath = $repository . $1;
			$LocalRpmFilePath  = '/tmp/' . $1;

			#download rpm package to temp
			unless ( -e $LocalRpmFilePath ) {
				$cmd = "wget -O " . $LocalRpmFilePath . " " . $RemoteRpmFilePath;
				if ( 0 != system($cmd) ) {
					$ReturnInfo =
					  $ReturnInfo . "update " . $_ . " failed: can not download the rpm\n";
					$callback->( { error => $ReturnInfo, errorcode => [1] } );
					return;
				}
			}

			#update rpm by rpm packages.
			$cmd        = "rpm -U " . $LocalRpmFilePath . " 2>&1";
			$ReturnInfo = $ReturnInfo . readpipe($cmd);
		}

		$callback->( { info => $ReturnInfo } );
	}
}

sub web_unlock {
	my ( $request, $callback, $sub_req ) = @_;
	my $node     = $request->{arg}->[1];
	my $password = $request->{arg}->[2];

	# Unlock a node by setting up the SSH keys
	my $out = `DSH_REMOTE_PASSWORD=$password xdsh $node -K`;

	$callback->( { data => $out } );
}

sub web_gangliastatus {
	my ( $request, $callback, $sub_req ) = @_;

	# Get node range
	my $nr  = $request->{arg}->[1];
	my $out = `xdsh $nr "service gmond status"`;

	# Parse output, and use $callback to send back to the web interface
	# Output looks like:
	# 	node_1: Checking for gmond: ..running
	# 	node_2: Checking for gmond: ..running
	my @lines = split( '\n', $out );
	my $line;
	my $status;
	foreach $line (@lines) {
		if ( $line =~ m/running/i ) {
			$status = 'on';
		} else {
			$status = 'off';
		}

		split( ': ', $line );
		$callback->(
			{
				node => [
					{
						name => [ $_[0] ],    # Node name
						data => [$status]     # Output
					}
				]
			}
		);
	}
}

sub web_gangliastart() {
	my ( $request, $callback, $sub_req ) = @_;

	# Get node range
	my $nr = $request->{arg}->[1];
	if ( !$nr ) {

		# If no node range is given, then assume all nodes
		$nr = '';
	}

	# Add gangliamon to the monitoring table
	my $info;
	my $output = `monadd gangliamon`;
	my @lines = split( '\n', $output );
	foreach (@lines) {
		if ($_) {
			$info .= ( $_ . "\n" );
		}
	}

	# Run the ganglia configuration script on node
	$output = `moncfg gangliamon $nr -r`;
	@lines = split( '\n', $output );
	foreach (@lines) {
		if ($_) {
			$info .= ( $_ . "\n" );
		}
	}

	# Start the gmond daemon on node
	$output = `monstart gangliamon $nr -r`;
	@lines = split( '\n', $output );
	foreach (@lines) {
		if ($_) {
			$info .= ( $_ . "\n" );
		}
	}

	$callback->( { info => $info } );
	return;
}

sub web_gangliastop() {
	my ( $request, $callback, $sub_req ) = @_;

	# Get node range
	my $nr = $request->{arg}->[1];
	if ( !$nr ) {
		$nr = '';
	}

	# Start the gmond daemon on node
	my $info;
	my $output = `monstop gangliamon $nr -r`;
	my @lines = split( '\n', $output );
	foreach (@lines) {
		if ($_) {
			$info .= ( $_ . "\n" );
		}
	}

	$callback->( { info => $info } );
	return;
}

sub web_gangliacheck() {
	my ( $request, $callback, $sub_req ) = @_;

	# Get node range
	my $nr = $request->{arg}->[1];
	if ( !$nr ) {
		$nr = '';
	}

	# Check if ganglia RPMs are installed
	my $info;
	my $info = `xdsh $nr "rpm -q ganglia-gmond libganglia libconfuse"`;
	$callback->( { info => $info } );
	return;
}

sub web_installganglia() {
	my ( $request, $callback, $sub_req ) = @_;

	# Get node range
	my $nr = $request->{arg}->[1];
	my @nodes = split( ',', $nr );
	
	# Get repository type
	my $os = xCAT::Utils->osver();
	# Get repository name
	my $xcatDep = 'xCAT-dep';
	
	# Get location of repository
	my $loc;
	if ($os =~ /rh/) {
		# Red Hat
		$loc = `cat /etc/yum.repos.d/$xcatDep.repo | grep "baseurl"`;
	} elsif ($os =~ /sles11/) {
		# SUSE
		$loc = `cat /etc/zypp/repos.d/$xcatDep.repo | grep "baseurl"`;
	} else {
		$loc = '';
	}

	$loc =~ s/baseurl=//g;
	$loc =~ s/file://g; 	# Downloaded xCAT-dep
	
	# Trim right and left
	$loc =~ s/\s*$//;
	$loc =~ s/^\s*//;
	
	# Get the base directory for xcat-dep
	$loc = substr($loc, 0, index($loc, 'xcat-dep/') + 8);
	
	# Get the appropriate directory for each nodes
	# This is based on the nodetype.os and nodetype.arch attributes
	# e.g. xcat-dep/<os>/<arch>, where <os> can be: fedora8, fedora9, fedora12, fedora13, rh4, rh5, rh6, sles10, sles11
	# and where <arch> can be: ppc64, s390x, x86, x86_64
	my $info;
	my $tab;
	my $attrs;
	my $tmp;
	
	# Repository location: $repo{$node}
	my $repo;
	# Go through each node because each node might have a different repository 
	# location, based on its OS and arch
	foreach (@nodes) {
		# Get table
		$tab = xCAT::Table->new('nodetype');
		# Get property values
		$attrs = $tab->getNodeAttribs( $_, ['os', 'arch'] );

		if ($attrs->{'arch'} && $attrs->{'os'}) {
			# Point to the right OS
			if ($attrs->{'os'} =~ /fedora8/) {
				$attrs->{'os'} = 'fedora8';
			} elsif ($attrs->{'os'} =~ /fedora9/) {
				$attrs->{'os'} = 'fedora9';
			} elsif ($attrs->{'os'} =~ /fedora12/) {
				$attrs->{'os'} = 'fedora12';
			} elsif ($attrs->{'os'} =~ /fedora13/) {
				$attrs->{'os'} = 'fedora13';
			} elsif ($attrs->{'os'} =~ /rh4/ || $attrs->{'os'} =~ /rhel4/) {
				$attrs->{'os'} = 'rh4';
			} elsif ($attrs->{'os'} =~ /rh5/ || $attrs->{'os'} =~ /rhel5/) {
				$attrs->{'os'} = 'rh5';
			} elsif ($attrs->{'os'} =~ /rh6/ || $attrs->{'os'} =~ /rhel6/) {
				$attrs->{'os'} = 'rh6';
			} elsif ($attrs->{'os'} =~ /sles10/) {
				$attrs->{'os'} = 'sles10';
			} elsif ($attrs->{'os'} =~ /sles11/) {
				$attrs->{'os'} = 'sles11';
			}
			
			$repo = "$loc/$attrs->{'os'}/$attrs->{'arch'}";
		} else {
			$callback->( { info => '(Error) Missing the nodetype.os and nodetype.arch attributes for $_' } );	
		}
				
		# Transfer Ganglia packages into /tmp directory of node
		$callback->( { info => "$_: Copying over Ganglia packages..." } );
		$info = `xdcp $_ $repo/ganglia-gmond-* $repo/libconfuse-* $repo/libganglia-* /tmp`;
		$callback->( { info => $info } );
		
		# Check if libapr1 is installed
		$tmp = '/tmp';
		$info = `xdsh $_ "rpm -qa libapr1"`;
		if (!($info =~ /libapr1/)) {
			$callback->( { info => "(Error) libapr1 package not installed on $_" } );
		} else {
			# If libapr1 is installed, install Ganglia packages
			$callback->( { info => "$_: Installing Ganglia..." } );
			$info = `xdsh $_ "rpm -i $tmp/ganglia-gmond-* $tmp/libconfuse-* $tmp/libganglia-*"`;
			$callback->( { info => $info } );
		}
		
		# Remove Ganglia packages from /tmp
		$callback->( { info => "$_: Removing Ganglia packages..." } );
		$info = `xdsh $_ "rm $tmp/ganglia-gmond-* $tmp/libconfuse-* $tmp/libganglia-*"`;
		$callback->( { info => $info } );
	}
	
	return;
}

sub web_rmcmonStart {
	my ( $request, $callback, $sub_req ) = @_;
	my $nodeRange = $request->{arg}->[1];
	my $table;
	my $retData = "";
	my $output;

	#check the running status
	$table = xCAT::Table->new('monitoring');
	my $rmcWorkingStatus = $table->getAttribs( { name => 'rmcmon' }, 'disable' );
	$table . close();

	#the rmc monitoring is running so return directly
	if ($rmcWorkingStatus) {
		if ( $rmcWorkingStatus->{disable} =~ /0|No|no|NO|N|n/ ) {
			$callback->( { info => 'RMC Monitoring is running now.' } );
			return;
		}
	}

	$retData .= "RMC is not running, start it now.\n";

	#check the monsetting table rmc's montype contains "performance"
	$table = xCAT::Table->new('monsetting');
	my $rmcmonType = $table->getAttribs( { name => 'rmcmon', key => 'montype' }, 'value' );
	$table . close();

	#the rmc monitoring is not configure right we should configure it again
	#there is no rmcmon in monsetting table
	if ( !$rmcmonType ) {
		$output = xCAT::Utils->runcmd( 'monadd rmcmon -s [montype=perf]', -1, 1 );
		foreach (@$output) {
			$retData .= ( $_ . "\n" );
		}
		$retData .= "Add the rmcmon to monsetting table complete.\n";
	}

	#configure before but there is not performance monitoring, so change the table
	else {
		if ( !( $rmcmonType->{value} =~ /perf/ ) ) {
			$output =
			  xCAT::Utils->runcmd( 'chtab name=rmcmon,key=montype monsetting.value=perf', -1, 1 );
			foreach (@$output) {
				$retData .= ( $_ . "\n" );
			}
			$retData .= "Change the rmcmon configure in monsetting table finish.\n";
		}
	}

	#run the rmccfg command to add all nodes into local RMC configuration
	$output = xCAT::Utils->runcmd( "moncfg rmcmon $nodeRange", -1, 1 );
	foreach (@$output) {
		$retData .= ( $_ . "\n" );
	}

	#run the rmccfg command to add all nodes into remote RMC configuration
	$output = xCAT::Utils->runcmd( "moncfg rmcmon $nodeRange -r", -1, 1 );
	foreach (@$output) {
		$retData .= ( $_ . "\n" );
	}

#check the monfiguration
#use lsrsrc -a IBM.Host Name. compare the command's return and the noderange, then decide witch node should be refrsrc

	#start the rmc monitor
	$output = xCAT::Utils->runcmd( "monstart rmcmon", -1, 1 );
	foreach (@$output) {
		$retData .= ( $_ . "\n" );
	}

	$callback->( { info => $retData } );
	return;
}

sub web_rmcmonShow() {
	my ( $request, $callback, $sub_req ) = @_;
	my $nodeRange = $request->{arg}->[1];
	my $attr      = $request->{arg}->[2];
	my @nodes;
	my $retInfo;
	my $retHash = {};
	my $output;
	my @activeNodes;
	my @rmcNodes;
	my $tempNodes;
	my $temp = "";

	#only get the system rmc info
	#like this PctTotalTimeIdle=>"10.0000, 20.0000, 12.0000, 30.0000"
	if ( 'summary' eq $nodeRange ) {
		$output = xCAT::Utils->runcmd( "monshow rmcmon -s -t 60 -a " . $attr, -1, 1 );
		foreach $temp (@$output) {

			#the attribute name
			if ( $temp =~ /Pct/ ) {
				$temp =~ s/ //g;

				#the first one
				if ( "" eq $retInfo ) {
					$retInfo .= ( $temp . ':' );
				} else {
					$retInfo =~ s/,$/;/;
					$retInfo .= ( $temp . ':' );
				}
				next;
			}

			#the content of the attribute
			$temp =~ m/\s+(\d+\.\d{4})/;
			if ( defined($1) ) {
				$retInfo .= ( $1 . ',' );
			}
		}

		#return the rmc info
		$retInfo =~ s/,$//;
		$callback->( { info => $retInfo } );
		return;
	}

	if ( 'lpar' eq $nodeRange ) {

		#get nodes detail containt
		@nodes = xCAT::NodeRange::noderange($nodeRange);
		if ( (@nodes) && ( @nodes > 0 ) ) {

			#get all the active nodes
			$temp = join( ' ', @nodes );
			$output = `fping -a $temp 2> /dev/null`;
			chomp($output);
			@activeNodes = split( /\n/, $output );

			#get all the inactive nodes by substracting the active nodes from all.
			my %temp2;
			foreach (@activeNodes) {
				$temp2{$_} = 1;
			}
			foreach (@nodes) {
				if ( !$temp2{$_} ) {
					push( @{ $retHash->{node} }, { name => $_, data => 'NA' } );
				}
			}
		}

		if ( @activeNodes < 1 ) {
			$callback->($retHash);
			return;
		}

		$tempNodes = join( ',', @activeNodes );
		$output = xCAT::Utils->runcmd( "xdsh $tempNodes rpm -q rsct.core", -1, 1 );

		#non-installed
		foreach (@$output) {
			my @temp = split( /:/, $_ );
			if ( @temp[1] =~ /not installed/ ) {
				push( @{ $retHash->{node} }, { name => @temp[0], data => 'NI' } );
			} else {
				push( @rmcNodes, @temp[0] );
			}
		}

		#there are not rmc nodes, so we should return directly
		if ( @rmcNodes < 1 ) {
			$callback->($retHash);
			return;
		}

		$tempNodes = join( ',', @rmcNodes );
		$output = xCAT::Utils->runcmd(
"xdsh $tempNodes \"/bin/ps -ef | /bin/grep rmcd | /bin/grep -v grep\" | /bin/awk '{print \$1\$9}'",
			-1, 1
		);
		foreach (@$output) {
			my @temp = split( /:/, $_ );
			if ( @temp[1] =~ /rmcd/ ) {
				push( @{ $retHash->{node} }, { name => @temp[0], data => 'OK' } );
			}

			#not running
			else {
				push( @{ $retHash->{node} }, { name => @temp[0], data => 'NR' } );
			}
		}

		$callback->($retHash);
		return;
	}

	my $attrName  = "";
	my @attrValue = ();
	$output = xCAT::Utils->runcmd( "monshow rmcmon $nodeRange -t 60 -a " . $attr, -1, 1 );
	foreach (@$output) {
		$temp = $_;
		if ( $temp =~ /\t/ ) {
			$temp =~ s/\t/ /g;
			chomp($temp);
		}

		#the attribute name
		if ( $temp =~ m/\s+(Pct.*)\s+/ ) {
			$temp = $1;

			#the first one
			if ( "" ne $attrName ) {
				push(
					@{ $retHash->{node} },
					{ name => $attrName, data => join( ',', @attrValue ) }
				);
				$attrName  = "";
				@attrValue = ();
			}
			$attrName = $temp;
			next;
		}

		#the content of the attribute
		$temp =~ m/\s+(\d+\.\d{4})\s*$/;
		if ( defined($1) ) {
			push( @attrValue, $1 );
		}
	}

	#push the last attribute name and values.
	push( @{ $retHash->{node} }, { name => $attrName, data => join( ',', @attrValue ) } );
	$callback->($retHash);
}

sub web_monls() {
	my ( $request, $callback, $sub_req ) = @_;
	my $retInfo = xCAT::Utils->runcmd( "monls", -1, 1 );
	my $ret = '';
	foreach my $line (@$retInfo) {
		my @temp = split( /\s+/, $line );
		$ret .= @temp[0];
		if ( 'not-monitored' eq @temp[1] ) {
			$ret .= ':Off;';
		} else {
			$ret .= ':On;';
		}
	}
	if ( '' eq $ret ) {
		return;
	}

	$ret = substr( $ret, 0, length($ret) - 1 );
	$callback->( { data => $ret } );
}

sub web_discover {
	my ( $request, $callback, $sub_req ) = @_;
	my $type1 = '';
	my $type2 = uc( $request->{arg}->[1] );

	if ( 'FRAME' eq $type1 ) {
		$type1 = 'BPA';
	} elsif ( 'CEC' eq $request->{arg}->[1] ) {
		$type1 = 'FSP';
	} elsif ( 'HMC' eq $request->{arg}->[1] ) {
		$type1 = 'HMC';
	}

	my $retStr  = '';
	my $retInfo =
	  xCAT::Utils->runcmd( "lsslp -s $type1 2>null | grep $type2 | awk '{print \$2\"-\"\$3}'",
		-1, 1 );
	if ( scalar(@$retInfo) < 1 ) {
		$retStr = 'Error: Can not discover frames in cluster!';
	} else {
		foreach my $line (@$retInfo) {
			$retStr .= $line . ';';
		}
		$retStr = substr( $retStr, 0, -1 );
	}
	$callback->( { data => $retStr } );
}

sub web_updatevpd {
	my ( $request, $callback, $sub_req ) = @_;
	my $harwareMtmsPair = $request->{arg}->[1];
	my @hardware        = split( /:/, $harwareMtmsPair );

	my $vpdtab = xCAT::Table->new('vpd');
	unless ($vpdtab) {
		return;
	}
	foreach my $hard (@hardware) {

		#the sequence must be object name, mtm, serial
		my @temp = split( /,/, $hard );
		$vpdtab->setAttribs( { 'node' => @temp[0] }, { 'serial' => @temp[2], 'mtm' => @temp[1] } );
	}

	$vpdtab->close();
}

sub web_createimage {
	my ( $request, $callback, $sub_req ) = @_;
	my $ostype    = $request->{arg}->[1];
	my $osarch    = lc( $request->{arg}->[2] );
	my $profile   = $request->{arg}->[3];
	my $bootif    = $request->{arg}->[4];
	my $imagetype = lc( $request->{arg}->[5] );
	my @softArray;
	my $netdriver  = '';
	my $installdir = xCAT::Utils->getInstallDir();
	my $tempos     = $ostype;
	$tempos =~ s/[0-9]//;
	my $CONFILE;
	my $archFlag = 0;
	my $ret      = '';
	my $cmdPath  = '';

	if ( $request->{arg}->[6] ) {
		@softArray = split( ',', $request->{arg}->[6] );

		#check the arch
		if ( 'ppc64' ne $osarch ) {
			$callback->( { data => 'Error: only support PPC64!' } );
			return;
		}

		#check the osver
		unless ( -e "/opt/xcat/share/xcat/IBMhpc/IBMhpc.$ostype.ppc64.pkglist" ) {
			$callback->( { data => 'Error: only support rhels6 and sles11!' } );
			return;
		}

		#check the custom package, if the path is not exist, must create the dir first
		if ( -e "$installdir/custom/netboot/$ostype/" ) {

			#the path is exist, so archive all file under this path.
			opendir( TEMPDIR, "$installdir/custom/netboot/$ostype/" );
			my @fileArray = readdir(TEMPDIR);
			closedir(TEMPDIR);
			if ( 2 < scalar(@fileArray) ) {
				$archFlag = 1;
				unless ( -e "/tmp/webImageArch/" ) {
					system("mkdir -p /tmp/webImageArch/");
				}
				system("mv $installdir/custom/netboot/$ostype/*.* /tmp/webImageArch/");
			} else {
				$archFlag = 0;
			}
		} else {

			#do not need to archive
			$archFlag = 0;
			system("mkdir -p $installdir/custom/netboot/$ostype/");
		}

		#write pkglist
		open( $CONFILE, ">$installdir/custom/netboot/$ostype/$profile.pkglist" );
		print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/IBMhpc.$ostype.ppc64.pkglist# \n";
		close($CONFILE);

		#write otherpkglist
		open( $CONFILE, ">$installdir/custom/netboot/$ostype/$profile.otherpkgs.pkglist" );
		print $CONFILE "\n";
		close($CONFILE);

		#write exlist for stateless
		open( $CONFILE, ">$installdir/custom/netboot/$ostype/$profile.exlist" );
		print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/IBMhpc.$ostype.$osarch.exlist#\n";
		close($CONFILE);

		#write postinstall
		open( $CONFILE, ">$installdir/custom/netboot/$ostype/$profile.postinstall" );
		print $CONFILE
		  "/opt/xcat/share/xcat/IBMhpc/IBMhpc.$tempos.postinstall \$1 \$2 \$3 \$4 \$5 \n";
		close($CONFILE);

		for my $soft (@softArray) {
			$soft = lc($soft);
			if ( 'gpfs' eq $soft ) {
				web_gpfsConfigure( $ostype, $profile, $osarch, $installdir );
			} elsif ( 'rsct' eq $soft ) {
				web_rsctConfigure( $ostype, $profile, $osarch, $installdir );
			} elsif ( 'pe' eq $soft ) {
				web_peConfigure( $ostype, $profile, $osarch, $installdir );
			} elsif ( 'essl' eq $soft ) {
				web_esslConfigure( $ostype, $profile, $osarch, $installdir );
			}
		}

		#chmod
		system("chmod 755 $installdir/custom/netboot/$ostype/*.*");
	}

	if ( $bootif =~ /hf/i ) {
		$netdriver = 'hf_if';
	} else {
		$netdriver = 'ibmveth';
	}

	if ( $tempos =~ /rh/i ) {
		$cmdPath = "/opt/xcat/share/xcat/netboot/rh";
	} else {
		$cmdPath = "/opt/xcat/share/xcat/netboot/sles";
	}

	#for stateless only run packimage is ok
	if ( 'stateless' eq $imagetype ) {
		my $retInfo =
		  xCAT::Utils->runcmd(
			"${cmdPath}/genimage -i $bootif -n $netdriver -o $ostype -p $profile",
			-1, 1 );
		$ret = join( "\n", @$retInfo );

		if ($::RUNCMD_RC) {
			web_restoreChange( $request->{arg}->[6], $archFlag, $imagetype, $ostype, $installdir );
			$callback->( { data => $ret } );
			return;
		}

		$ret .= "\n";
		my $retInfo = xCAT::Utils->runcmd( "packimage -o $ostype -p $profile -a $osarch", -1, 1 );
		$ret .= join( "\n", @$retInfo );
	} else {

		#for statelist we should check the litefile table
		#step1 save the old litefile table content into litefilearchive.csv
		system('tabdump litefile > /tmp/litefilearchive.csv');

		#step2 write the new litefile.csv for this lite image
		open( $CONFILE, ">/tmp/litefile.csv" );
		print $CONFILE "#image,file,options,comments,disable\n";
		print $CONFILE '"ALL","/etc/lvm/","tmpfs",,' . "\n";
		print $CONFILE '"ALL","/etc/ntp.conf","tmpfs",,' . "\n";
		print $CONFILE '"ALL","/etc/resolv.conf","tmpfs",,' . "\n";
		print $CONFILE '"ALL","/etc/sysconfig/","tmpfs",,' . "\n";
		print $CONFILE '"ALL","/etc/yp.conf","tmpfs",,' . "\n";
		print $CONFILE '"ALL","/etc/ssh/","tmpfs",,' . "\n";
		print $CONFILE '"ALL","/var/","tmpfs",,' . "\n";
		print $CONFILE '"ALL","/tmp/","tmpfs",,' . "\n";
		print $CONFILE '"ALL","/root/.ssh/","tmpfs",,' . "\n";
		print $CONFILE '"ALL","/opt/xcat/","tmpfs",,' . "\n";
		print $CONFILE '"ALL","/xcatpost/","tmpfs",,' . "\n";

		if ( 'rhels' eq $tempos ) {
			print $CONFILE '"ALL","/etc/adjtime","tmpfs",,' . "\n";
			print $CONFILE '"ALL","/etc/securetty","tmpfs",,' . "\n";
			print $CONFILE '"ALL","/etc/rsyslog.conf","tmpfs",,' . "\n";
			print $CONFILE '"ALL","/etc/rsyslog.conf.XCATORIG","tmpfs",,' . "\n";
			print $CONFILE '"ALL","/etc/udev/","tmpfs",,' . "\n";
			print $CONFILE '"ALL","/etc/ntp.conf.predhclient","tmpfs",,' . "\n";
			print $CONFILE '"ALL","/etc/resolv.conf.predhclient","tmpfs",,' . "\n";
		} else {
			print $CONFILE '"ALL","/etc/ntp.conf.org","tmpfs",,' . "\n";
			print $CONFILE '"ALL","/etc/syslog-ng/","tmpfs",,' . "\n";
			print $CONFILE '"ALL","/etc/fstab","tmpfs",,' . "\n";
		}
		close($CONFILE);

		#write the hpc software litefile into temp litefile.csv
		for my $soft (@softArray) {
			$soft = lc($soft);
			if ( -e "/opt/xcat/share/xcat/IBMhpc/$soft/litefile.csv" ) {
				system(
"grep '^[^#]' /opt/xcat/share/xcat/IBMhpc/$soft/litefile.csv >> /tmp/litefile.csv"
				);
			}
		}

		system("tabrestore /tmp/litefile.csv");

		#create the image
		my $retInfo =
		  xCAT::Utils->runcmd(
			"${cmdPath}/genimage -i $bootif -n $netdriver -o $ostype -p $profile",
			-1, 1 );
		$ret = join( "\n", @$retInfo );
		if ($::RUNCMD_RC) {
			web_restoreChange( $request->{arg}->[6], $archFlag, $imagetype, $ostype, $installdir );
			$callback->( { data => $ret } );
			return;
		}
		$ret .= "\n";
		my $retInfo = xCAT::Utils->runcmd( "liteimg -o $ostype -p $profile -a $osarch", -1, 1 );
		$ret .= join( "\n", @$retInfo );
	}

	web_restoreChange( $request->{arg}->[6], $archFlag, $imagetype, $ostype, $installdir );
	$callback->( { data => $ret } );
	return;
}

sub web_gpfsConfigure {
	my ( $ostype, $profile, $osarch, $installdir ) = @_;
	my $CONFILE;

	#createrepo
	system('createrepo $installdir/post/otherpkgs/$ostype/$osarch/gpfs');

	#other pakgs
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.otherpkgs.pkglist" );
	print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/gpfs/gpfs.otherpkgs.pkglist#\n";
	close($CONFILE);

	#exlist
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.exlist" );
	print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/gpfs/gpfs.exlist#\n";
	close($CONFILE);

	#postinstall
	system('cp /opt/xcat/share/xcat/IBMhpc/gpfs/gpfs_mmsdrfs $installdir/postscripts/gpfs_mmsdrfs');
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.postinstall" );
	print $CONFILE
	  "NODESETSTATE=genimage installroot=\$1 /opt/xcat/share/xcat/IBMhpc/gpfs/gpfs_updates\n";
	print $CONFILE "installroot=\$1 $installdir/postscripts/gpfs_mmsdrfs\n";
	close($CONFILE);
}

sub web_rsctConfigure {
	my ( $ostype, $profile, $osarch, $installdir ) = @_;
	my $CONFILE;

	#createrepo
	system('createrepo $installdir/post/otherpkgs/$ostype/$osarch/rsct');

	#packagelist for sles11
	if ( $ostype =~ /sles/i ) {
		open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.pkglist" );
		print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/rsct/rsct.pkglist# \n";
		close($CONFILE);
	}

	#exlist
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.exlist" );
	print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/rsct/rsct.exlist#\n";
	close($CONFILE);

	#postinstall
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.postinstall" );
	print $CONFILE
"installroot=\$1 rsctdir=$installdir/post/otherpkgs/rhels6/ppc64/rsct NODESETSTATE=genimage   /opt/xcat/share/xcat/IBMhpc/rsct/rsct_install\n";
	close($CONFILE);
}

sub web_peConfigure {
	my ( $ostype, $profile, $osarch, $installdir ) = @_;
	my $CONFILE;

	#createrepo
	system('createrepo $installdir/post/otherpkgs/$ostype/$osarch/pe');
	system('createrepo $installdir/post/otherpkgs/$ostype/$osarch/compilers');

	#pkglist
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.pkglist" );
	if ( $ostype =~ /rh/i ) {
		print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/pe/pe.$ostype.pkglist#\n";
	} else {
		print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/compilers/compilers.pkglist#\n";
		print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/pe/pe.pkglist#\n";
	}
	close($CONFILE);

	#otherpaglist
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.otherpkgs.pkglist" );
	print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/pe/pe.otherpkgs.pkglist#\n";
	close($CONFILE);

	#exlist
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.exlist" );
	print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/compilers/compilers.exlist#\n";
	print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/pe/pe.exlist#\n";
	close($CONFILE);

	#postinstall
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.postinstall" );
	print $CONFILE
"installroot=\$1 NODESETSTATE=genimage   /opt/xcat/share/xcat/IBMhpc/compilers/compilers_license";
	print $CONFILE
"installroot=\$1 pedir=$installdir/post/otherpkgs/rhels6/ppc64/pe NODESETSTATE=genimage   /opt/xcat/share/xcat/IBMhpc/pe/pe_install";
	close($CONFILE);
}

sub web_esslConfigure {
	my ( $ostype, $profile, $osarch, $installdir ) = @_;
	my $CONFILE;

	#reaterepo
	system('createrepo $installdir/post/otherpkgs/$ostype/$osarch/essl');

	#pkglist
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.pkglist" );
	if ( $ostype =~ /rh/i ) {
		print $CONFILE,
		  "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/compilers/compilers.rhels6.pkglist#\n";
	} else {
		print $CONFILE, "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/essl/essl.pkglist#\n";
	}

	#otherpkgs
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.otherpkgs.pkglist" );
	print $CONFILE, "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/essl/essl.otherpkgs.pkglist#\n";
	close($CONFILE);

	#exlist
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.exlist" );
	print $CONFILE, "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/essl/essl.exlist#\n";
	close($CONFILE);

	#postinstall
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.postinstall" );
	print $CONFILE,
"installroot=\$1 essldir=$installdir/post/otherpkgs/rhels6/ppc64/essl NODESETSTATE=genimage   /opt/xcat/share/xcat/IBMhpc/essl/essl_install";
	close($CONFILE);
}

sub web_restoreChange {
	my ( $software, $archFlag, $imagetype, $ostype, $installdir ) = @_;

	#recover all file in the $installdir/custom/netboot/$ostype/
	if ($software) {
		system("rm -f $installdir/custom/netboot/$ostype/*.*");
	}

	if ($archFlag) {
		system("mv /tmp/webImageArch/*.* $installdir/custom/netboot/$ostype/");
	}

	#recover the litefile table for statelite image
	if ( 'statelite' == $imagetype ) {
		system(
"rm -r /tmp/litefile.csv ; mv /tmp/litefilearchive.csv /tmp/litefile.csv ; tabrestore /tmp/litefile.csv"
		);
	}
}
1;
