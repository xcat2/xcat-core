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
require xCAT::DBobjUtils;
require IO::Socket::INET;
use Getopt::Long;
use Data::Dumper;
use LWP::Simple;
use xCAT::Table;
use xCAT::NodeRange;
require XML::Parser;
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
		'gangliaconf'   => \&web_gangliaconf,
		'gangliastart'  => \&web_gangliastart,
		'gangliastop'   => \&web_gangliastop,
		'gangliastatus' => \&web_gangliastatus,
		'gangliacheck'  => \&web_gangliacheck,
		'installganglia'=> \&web_installganglia,
		'mkcondition'   => \&web_mkcondition,
		'monls'         => \&web_monls,
		'dynamiciprange'=> \&web_dynamiciprange,
		'discover'      => \&web_discover,
		'updatevpd'     => \&web_updatevpd,
		'writeconfigfile'=> \&web_writeconfigfile,
		'createimage'   => \&web_createimage,
        'provision'     => \&web_provision,
        'summary'       => \&web_summary,
	    'gangliashow'   => \&web_gangliaShow,
	    'gangliacurrent' => \&web_gangliaLatest,
	    'rinstall'	    => \&web_rinstall,
        'addnode'      => \&web_addnode,
		'graph'		    => \&web_graphinfo,
		'getdefaultuserentry' => \&web_getdefaultuserentry
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

		my $retInfo = xCAT::Utils->runcmd( 'nodels ' . $groupName . " ppc.nodetype", -1, 1 );
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

sub web_gangliaconf() {
	my ( $request, $callback, $sub_req ) = @_;

	# Get node range
	my $nr = $request->{arg}->[1];
	
	my $info;
	my $output;
	
	# Add gangliamon to the monitoring table (if not already)
	$output = `monadd gangliamon`;
	
	# Run the ganglia configuration script on node
	if ($nr) {
		$output = `moncfg gangliamon $nr -r`;
	} else {
		# If no node range is given, then assume all nodes
			
		# Handle localhost (this needs to be 1st)
		$output = `moncfg gangliamon`;
		# Handle remote nodes
		$output .= `moncfg gangliamon -r`;
	}

	my @lines = split( '\n', $output );
	foreach (@lines) {
		if ($_) {
			$info .= ( $_ . "\n" );
		}
	}

	$callback->( { info => $info } );
	return;
}

sub web_gangliastart() {
	my ( $request, $callback, $sub_req ) = @_;

	# Get node range
	my $nr = $request->{arg}->[1];

	my $info;
	my $output;
	
	# Add gangliamon to the monitoring table (if not already)
	$output = `monadd gangliamon`;
	
	# Start the gmond daemon on node
	if ($nr) {
		$output = `moncfg gangliamon $nr -r`;
		$output .= `monstart gangliamon $nr -r`;	
	} else {
		# If no node range is given, then assume all nodes
		
		# Handle localhost (this needs to be 1st)
		$output = `moncfg gangliamon`;
		# Handle remote nodes
		$output .= `moncfg gangliamon -r`;
		
		# Handle localhost (this needs to be 1st)
		$output .= `monstart gangliamon`;
		# Handle remote nodes
		$output .= `monstart gangliamon -r`;
	}
				
	my @lines = split( '\n', $output );
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
	
	my $info;
	my $output;
	
	# Stop the gmond daemon on node
	if ($nr) {
		$output = `monstop gangliamon $nr -r`;	
	} else {
		# If no node range is given, then assume all nodes
		
		# Handle localhost (this needs to be 1st)
		$output = `monstop gangliamon`;
		# Handle remote nodes
		$output .= `monstop gangliamon -r`;
	}
		
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
	
	# Loop through each node
	my $info;
	my $tab;
	my $attrs;
	my $osType;
	my $dir;
	my $pkglist;
	my $defaultDir;
	foreach (@nodes) {
		# Get os, arch, profile, and provmethod
		$tab = xCAT::Table->new('nodetype');
		$attrs = $tab->getNodeAttribs( $_, ['os', 'arch', 'profile', 'provmethod'] );
		
		# If any attributes are missing, skip
		if (!$attrs->{'os'} || !$attrs->{'arch'} || !$attrs->{'profile'} || !$attrs->{'provmethod'}) {
			$callback->( { info => "$_: (Error) Missing attribute (os, arch, profile, or provmethod) in nodetype table" } );
			next;
		}
		
		# Get the right OS type
		if ($attrs->{'os'} =~ /fedora/) {
			$osType = 'fedora';
		} elsif ($attrs->{'os'} =~ /rh/ || $attrs->{'os'} =~ /rhel/ || $attrs->{'os'} =~ /rhels/) {
			$osType = 'rh';
		} elsif ($attrs->{'os'} =~ /sles/) {
			$osType = 'sles';
		}
		
		# Assume /install/post/otherpkgs/<os>/<arch>/ directory is created
		# If Ganglia RPMs (ganglia-gmond-*, libconfuse-*, and libganglia-*) are not in directory
		$dir = "/install/post/otherpkgs/$attrs->{'os'}/$attrs->{'arch'}/";
		if (!(`test -e $dir/ganglia-gmond-* && echo 'File exists'` &&
			`test -e $dir/libconfuse-* && echo 'File exists'` &&
			`test -e $dir/libganglia-* && echo 'File exists'`)) {
			# Skip
			$callback->( { info => "$_: (Error) Missing Ganglia RPMs under $dir" } );
			next;
		}
					
		# Find pkglist directory
		$dir = "/install/custom/$attrs->{'provmethod'}/$osType";
		if (!(`test -d $dir && echo 'Directory exists'`)) {
			# Create pkglist directory
			`mkdir -p $dir`;
		}
		
		# Find pkglist file
		# Ganglia RPM names should be added to /install/custom/<inst_type>/<ostype>/<profile>.<os>.<arch>.otherpkgs.pkglist
		$pkglist = "$attrs->{'profile'}.$attrs->{'os'}.$attrs->{'arch'}.otherpkgs.pkglist";
		if (!(`test -e $dir/$pkglist && echo 'File exists'`)) {
			# Copy default otherpkgs.pkglist
			$defaultDir = "/opt/xcat/share/xcat/$attrs->{'provmethod'}/$osType";
			if (`test -e $defaultDir/$pkglist && echo 'File exists'`) {
				# Copy default pkglist
				`cp $defaultDir/$pkglist $dir/$pkglist`;
			} else {
				# Create pkglist
				`touch $dir/$pkglist`;
			}
			
			# Add Ganglia RPMs to pkglist
			`echo ganglia-gmond >> $dir/$pkglist`;
			`echo libconfuse >> $dir/$pkglist`;
			`echo libganglia >> $dir/$pkglist`;
		}

		# Check if libapr1 is installed
		$info = `xdsh $_ "rpm -qa libapr1"`;
		if (!($info =~ /libapr1/)) {
			$callback->( { info => "$_: (Error) libapr1 package not installed" } );
			next;
		}
		
		# Install Ganglia RPMs using updatenode
		$callback->( { info => "$_: Installing Ganglia..." } );
		$info = `updatenode $_ -S`;
		$callback->( { info => "$info" } );
	}
	
	return;
}

#get ganglia data from rrd file. 
#args : 
#	nodeRange : the nodes' name which want to get
#	time range : which period want to get, like last hour, last day, last week .....
#	metric : which monitor attribute want to get, like load_one, bytes_in, bytes_out ......
#
#output: (till now there are 6 metic to get at one time at most)
#   metric1:timestamp1,value1,timestamp2,value2,.....;metric2:timestamp1,value1,timestamp2,value2,.....;....
sub web_gangliaShow{
	my ( $request, $callback, $sub_req ) = @_;
	my $nodename = $request->{arg}->[1];
	my $timeRange = 'now-1h';
	my $resolution = 60;
	my $metric = $request->{arg}->[3];
	my @nodes = ();
	my $retStr = '';
	my $runInfo;
	my $cmd = '';
	my $dirname = '/var/lib/ganglia/rrds/__SummaryInfo__/';
	#get the summary for this grid(the meaning of grid is referenced from ganglia )
	if ('_grid_' ne $nodename){
		$dirname = '/var/lib/ganglia/rrds/' . $nodename . '/';
	}

	if ('hour' eq $request->{arg}->[2]){
		$timeRange = 'now-1h';
		$resolution = 60;
	}
	elsif('day' eq $request->{arg}->[2]){
		$timeRange = 'now-1d';
		$resolution = 1800;
	}
	
	if ('_summary_' eq $metric){
		my @metricArray = ('load_one', 'cpu_num', 'cpu_idle', 'mem_free', 'mem_total', 'disk_total', 'disk_free', 'bytes_in', 'bytes_out');
		my $filename = '';
		my $step = 1;
		my $index = 0;
		my $size = 0;
		foreach my $tempmetric (@metricArray){
			my $temp = '';
			my $line = '';
			$retStr .= $tempmetric . ':';
			$filename = $dirname . $tempmetric . '.rrd';
			$cmd = "rrdtool fetch $filename -s $timeRange -r $resolution AVERAGE";
			$runInfo = xCAT::Utils->runcmd($cmd, -1, 1);
			if (scalar(@$runInfo) < 3){
				$callback->({data=>'error.'});
				return;
			}
			#delete the first 2 lindes
			shift(@$runInfo);
			shift(@$runInfo);

			#we only support 60 lines for one metric, in order to reduce the data load for web gui
			$size = scalar(@$runInfo);
			if ($size > 60){
				$step = int($size / 60) + 1;
			}
			
			if (($tempmetric eq 'cpu_idle') && ('_grid_' eq $nodename)){
				my $cpuidle = 0;
				my $cpunum = 0;
				for($index = 0; $index < $size; $index += $step){
					if ($runInfo->[$index] =~ /^(\S+): (\S+) (\S+)/){
						if (($2 eq 'NaNQ') || ($2 eq 'nan')){
							#the rrdtool fetch last outline line always nan, so no need to add into return string
							if ($index == ($size - 1)){
								next;
							}
							$temp .= $1 . ',0,';
						}
						else{
							$cpuidle = sprintf "%.2f", $2;
							$cpunum = sprintf "%.2f", $3;
							$temp .= $1 . ',' . (sprintf "%.2f", $cpuidle/$cpunum) . ',';
						}
					}
				}
			}
			else{
				for($index = 0; $index < $size; $index += $step){
					if ($runInfo->[$index] =~ /^(\S+): (\S+).*/){
						if (($2 eq 'NaNQ') || ($2 eq 'nan')){
							#the rrdtool fetch last outline line always nan, so no need to add into return string
							if ($index == ($size - 1)){
								next;
							}
							$temp .= $1 . ',0,';
						}
						else{
							$temp .= $1 . ',' . (sprintf "%.2f", $2) . ',';
						}
					}
				}
			}
			$retStr .= substr($temp, 0, -1) . ';';
		}
		$retStr = substr($retStr, 0, -1);
		$callback->({data=>$retStr});
		return;
	}
}

my $ganglia_return_flag = 0;
my %gangliaHash;
my $gangliaclustername;
my $ganglianodename;
#use socket to connect ganglia port to get the latest value/status
sub web_gangliaLatest{
	my ( $request, $callback, $sub_req ) = @_;
	my $type = $request->{arg}->[1];
	my $groupname = '';
	my $xmlparser;
	my $telnetcmd = '';
	my $connect;
	my $xmloutput = '';

	$ganglia_return_flag = 0;
	$gangliaclustername = '';
	$ganglianodename = '';
	undef(%gangliaHash);

	if($request->{arg}->[2]){
		$groupname = $request->{arg}->[2];
	}
	if ('grid' eq $type){
		$xmlparser = XML::Parser->new(Handlers=>{Start=>\&web_gangliaGridXmlStart, End=>\&web_gangliaXmlEnd});
		$telnetcmd = "/?filter=summary\n";
	}
	elsif('node' eq $type){
		$xmlparser = XML::Parser->new(Handlers=>{Start=>\&web_gangliaNodeXmlStart, End=>\&web_gangliaXmlEnd});
		$telnetcmd = "/\n";
	}

	#use socket to telnet 127.0.0.1 8652(ganglia's interactive port)
	$connect = IO::Socket::INET->new('127.0.0.1:8652');
	unless($connect){
		$callback->({'data'=>'error: connect local port failed.'});
		return;
	}

	print $connect $telnetcmd;
	open(TEMPFILE, '>/tmp/gangliadata');
	while(<$connect>){
		print TEMPFILE $_;
	}
	close($connect);
	close(TEMPFILE);

	$xmlparser->parsefile('/tmp/gangliadata');

	if ('grid' eq $type){
		web_gangliaGridLatest($callback);
	}
	elsif('node' eq $type){
		web_gangliaNodeLatest($callback, $groupname);
	}
	return;
}

#create return data for grid current status
sub web_gangliaGridLatest{
	my $callback = shift;
	my $retStr = '';
	my $timestamp = time();
	my $metricname = '';
	my @metricArray = ('load_one', 'cpu_num', 'mem_total', 'mem_free', 'disk_total', 'disk_free', 'bytes_in', 'bytes_out');

	if ($gangliaHash{'cpu_idle'}){
		my $sum = $gangliaHash{'cpu_idle'}->{'SUM'};
		my $num = $gangliaHash{'cpu_idle'}->{'NUM'};
		$retStr .= 'cpu_idle:' . $timestamp . ',' . (sprintf("%.2f", $sum/$num )) . ';';
	}
	foreach $metricname (@metricArray){
		if ($gangliaHash{$metricname}){
			$retStr .= $metricname . ':' . $timestamp . ',' . $gangliaHash{$metricname}->{'SUM'} . ';';
		}
	}
	$retStr = substr($retStr, 0, -1);
	$callback->({data=>$retStr});
}

#create return data for node current status
sub web_gangliaNodeLatest{
	my ($callback, $groupname) = @_;
	my $node = '';
	my $retStr = '';
	my $timestamp = time() - 180;
	my @nodes;
	#get all nodes by group
	if ($groupname){
		@nodes = xCAT::NodeRange::noderange($groupname, 1);
	}
	else{
		@nodes = xCAT::DBobjUtils->getObjectsOfType('node');
	}
	foreach $node(@nodes){
		#if the node install the ganglia
		if ($gangliaHash{$node}){
			my $lastupdate = $gangliaHash{$node}->{'timestamp'};
			#can not get the monitor data for too long time
			if ($lastupdate < $timestamp){
				$retStr .= $node . ':ERROR,Can not get monitor data more than 3 minutes!;';
				next;
			}
			
			if ($gangliaHash{$node}->{'load_one'} > $gangliaHash{$node}->{'cpu_num'}){
				$retStr .= $node . ':WARNING,';
			}
			else{
				$retStr .= $node . ':NORMAL,';
			}
			$retStr .= $gangliaHash{$node}->{'path'} . ';'
		}
		else{
			$retStr .= $node . ':UNKNOWN,;' ;
		}
	}

	$retStr = substr($retStr, 0, -1);
	$callback->({data=>$retStr});
}
#xml parser end function, do noting here
sub web_gangliaXmlEnd{
}

#xml parser start function for grid latest value
sub web_gangliaGridXmlStart{
	my( $parseinst, $elementname, %attrs ) = @_;
	my $metricname = '';

	#only parser grid infomation
	if ($ganglia_return_flag){
		return;
	}
	if ('METRICS' eq $elementname){
		$metricname = $attrs{'NAME'};
		$gangliaHash{$metricname}->{'SUM'} = $attrs{'SUM'};
		$gangliaHash{$metricname}->{'NUM'} = $attrs{'NUM'};
	}
	elsif ('CLUSTER' eq $elementname){
		$ganglia_return_flag = 1;
		return;
	}
	else{
		return;
	}
	#only need the grid summary info, if receive cluster return directly
}

#xml parser start function for node current status
sub web_gangliaNodeXmlStart{
	my( $parseinst, $elementname, %attrs ) = @_;
	my $metricname = '';
	#save the cluster name
	if('CLUSTER' eq $elementname){
		$gangliaclustername = $attrs{'NAME'};
		return;
	}
	elsif('HOST' eq $elementname){
		if ($attrs{'NAME'} =~ /(\S+?)\.(.*)/){
			$ganglianodename = $1;
		}
		else{
			$ganglianodename = $attrs{'NAME'};
		}
		$gangliaHash{$ganglianodename}->{'path'} = $gangliaclustername . '/' . $attrs{'NAME'};
		$gangliaHash{$ganglianodename}->{'timestamp'} = $attrs{'REPORTED'};
	}
	elsif('METRIC' eq $elementname){
		$metricname = $attrs{'NAME'};
		if (('load_one' eq $metricname) || ('cpu_num' eq $metricname)){
			$gangliaHash{$ganglianodename}->{$metricname} = $attrs{'VAL'};
		}
	}
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
	my $temp = "";

	#only get the system rmc info
	#like this PctTotalTimeIdle=>"10.0000, 20.0000, 12.0000, 30.0000"
	if ( 'summary' eq $nodeRange ) {
		$output = xCAT::Utils->runcmd( "monshow rmcmon -s -t 60 -o p -a " . $attr, -1, 1 );
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

	if ( 'compute' eq $nodeRange ) {
		my $node;
		#get nodes detail containt
		@nodes = xCAT::NodeRange::noderange($nodeRange);
		for $node (@nodes){
			if (-e "/var/rrd/$node"){
				push( @{ $retHash->{node} }, { name => $node, data => 'OK' } );
			}
			else{
				push( @{ $retHash->{node} }, { name => $node, data => 'UNKNOWN' } );
			}
		}

		$callback->($retHash);
		return;
	}

    my $attrName  = "";
    my @attrs = split(/,/, $attr);
    for $attrName (@attrs){
        my @attrValue = ();
        $output = xCAT::Utils->runcmd( "rrdtool fetch /var/rrd/${nodeRange}/${attrName}.rrd -r 60 -s e-1h AVERAGE", -1, 1 );
        foreach(@$output){
            $temp = $_;
            if ($temp eq ''){
                next;
            }
            
            if ($temp =~ /[NaNQ|nan]/){
                next;
            }
            
            if ($temp =~ /^(\d+): (\S+) (\S+)/){
                push( @attrValue, (sprintf "%.2f", $2));
            }
        }
        
        if(scalar(@attrValue) > 1){
            push(@{$retHash->{node}}, { name => $attrName, data => join( ',', @attrValue )});
        }
        else{
        	$retHash->{node}= { name => $attrName, data => ''};
        	last;
        }
    }
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

sub web_dynamiciprange{
	my ($request, $callback, $sub_req ) = @_;
	my $iprange = $request->{arg}->[1];

	open(TEMPFILE, '>/tmp/iprange.conf');
	print TEMPFILE "xcat-service-lan:\n";
	print TEMPFILE "dhcp-dynamic-range = " . $iprange . "\n";
	close(TEMPFILE);

	#run xcatsetup command to change the dynamic ip range
	xCAT::Utils->runcmd("xcatsetup /tmp/iprange.conf", -1, 1);
	unlink('/tmp/iprange.conf');
	xCAT::Utils->runcmd("makedhcp -n", -1, 1);
	#restart the dhcp server
	if (xCAT::Utils->isLinux()){
	#	xCAT::Utils->runcmd("service dhcpd restart", -1, 1);
	}
	else{
	#	xCAT::Utils->runcmd("startsrc -s dhcpsd", -1, 1);
	}
}

sub web_discover {
	my ( $request, $callback, $sub_req ) = @_;
	my $type = uc( $request->{arg}->[1] );

	my $retStr  = '';
	my $retInfo =
	  xCAT::Utils->runcmd( "lsslp -s -m $type 2>/dev/null | grep $type | awk '{print \$1\":\" \$2\"-\"\$3}'",
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

sub web_writeconfigfile{
	my ( $request, $callback, $sub_req ) = @_;
	my $filename = $request->{arg}->[1];
	my $content = $request->{arg}->[2];

	open(TEMPFILE, '>'.$filename);
	print TEMPFILE $content;
	
	close(TEMPFILE);
	return;
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
	$tempos =~ s/[0-9\.]//g;
	my $CONFILE;
	my $archFlag = 0;
	my $ret      = '';
	my $cmdPath  = '';

	if ( $request->{arg}->[6] ) {
		@softArray = split( ',', $request->{arg}->[6] );

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
			} elsif ( 'ganglia' eq $soft) {
				web_gangliaConfig( $ostype, $profile, $osarch, 'netboot', $installdir);
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
	system("createrepo $installdir/post/otherpkgs/$ostype/$osarch/gpfs");

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
	system("createrepo $installdir/post/otherpkgs/$ostype/$osarch/rsct");

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
	system("createrepo $installdir/post/otherpkgs/$ostype/$osarch/pe");
	system("createrepo $installdir/post/otherpkgs/$ostype/$osarch/compilers");

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

	#createrepo
	system("createrepo $installdir/post/otherpkgs/$ostype/$osarch/essl");

	#pkglist
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.pkglist" );
	if ( $ostype =~ /rh/i ) {
		print $CONFILE
		  "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/compilers/compilers.rhels6.pkglist#\n";
	} else {
		print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/essl/essl.pkglist#\n";
	}

	#otherpkgs
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.otherpkgs.pkglist" );
	print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/essl/essl.otherpkgs.pkglist#\n";
	close($CONFILE);

	#exlist
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.exlist" );
	print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/essl/essl.exlist#\n";
	close($CONFILE);

	#postinstall
	open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.postinstall" );
	print $CONFILE,
"installroot=\$1 essldir=$installdir/post/otherpkgs/rhels6/ppc64/essl NODESETSTATE=genimage   /opt/xcat/share/xcat/IBMhpc/essl/essl_install";
	close($CONFILE);
}

sub web_gangliaConfig{
	my ( $ostype, $profile, $osarch, $provtype, $installdir ) = @_;
	my $CONFILE;
	#createrepo
	system("createrepo $installdir/post/otherpkgs/$ostype/$osarch/ganglia");

	#pkglist
	open ( $CONFILE, ">>$installdir/custom/$provtype/$ostype/$profile.otherpkgs.pkglist" );
	print $CONFILE "#created by xCAT Web Gui.\n";
	print $CONFILE "ganglia/ganglia\n";
	print $CONFILE "ganglia/ganglia-gmond\n";
	print $CONFILE "ganglia/ganglia-gmetad\n";
	print $CONFILE "ganglia/rrdtool\n";
	close($CONFILE);
}
#check ganglia install needed rpm are put in the right directory
sub web_gangliaRpmCheck{
	my ( $ostype, $profile, $osarch, $installdir ) = @_;
	my @rpmnames = ("rrdtool", "ganglia", "ganglia-gmond", "ganglia-gmetad");
	my %temphash;
	my $rpmdir = "$installdir/post/otherpkgs/$ostype/$osarch/ganglia";
	my $errorstr = '';
	unless (-e $rpmdir){
		return "Put rrdtool,ganglia,ganglia-gmond,ganglia-gmetad rpms into $rpmdir.";
	}

	opendir(DIRHANDLE, $rpmdir);
	foreach my $filename (readdir(DIRHANDLE)){
		if ($filename =~ /(\D+)-(\d+)\..*\.rpm$/){
			$temphash{$1} = 1;
		}
	}
	closedir(DIRHANDLE);
	
	#check if all rpm are in the array
	foreach (@rpmnames){
		unless ($temphash{$_}){
			$errorstr .= $_ . ',';
		}
	}

	if ($errorstr){
		$errorstr = substr($errorstr, 0, -1);
		return "Put $errorstr rpms into $rpmdir.";
	}
	else{
		return "";
	}
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

sub web_provision_preinstall{
	my ($ostype, $profile, $arch, $installdir, $softwarenames) = @_;
	my $checkresult = '';
	my $errorstr = '';
	my @software = split(',', $softwarenames);
	my $softwarenum = scalar(@software);
  
    if (-e "$installdir/custom/install/$ostype/"){
        opendir(DIRHANDLE, "$installdir/custom/install/$ostype/");
        foreach my $filename (readdir(DIRHANDLE)){
            if ('.' eq $filename || '..' eq $filename){
                next;
            }
            $filename = "$installdir/custom/install/$ostype/" . $filename;
            if ($filename =~ /(.*)\.guibak$/){
                #no software recover the file, else do nothing
                if ($softwarenum < 1){
                    system("mv $filename $1");
                }
                next;
            }
            `/bin/grep 'xCAT Web Gui' $filename`;
            if ($?){
                #backup the origional config file
                if ($softwarenum > 0){
                    system("mv $filename ${filename}.guibak");
                }
            }
            else{
                unlink($filename);
            }
        }
        closedir(DIRHANDLE);
    }
    else{
        `mkdir -p $installdir/custom/install/$ostype -m 0755`;
    }

	if ($softwarenum < 1){
		return '';
	}

	foreach (@software){
		if ('ganglia' eq $_){
            $checkresult = web_gangliaRpmCheck($ostype, $profile, $arch, $installdir);
        }
        if ($checkresult){
            $errorstr .= $checkresult . "\n";
        }
	}
	
	if ($errorstr){
		return $errorstr;
	}

	foreach(@software){
		if ('ganglia' eq $_){
			web_gangliaConfig($ostype, $profile, $arch, 'install', $installdir);
		}
	}
	return '';
}

sub web_provision{
    my ( $request, $callback, $sub_req ) = @_;
    my $nodes = $request->{arg}->[1];
    my $imageName = $request->{arg}->[2];
    my ($arch, $inic, $pnic, $master, $tftp, $nfs) = split(/,/, $request->{arg}->[3]);
    my $line = '';
    my %imageattr;
    my $retinfo = xCAT::Utils->runcmd("lsdef -t osimage -l $imageName", -1, 1);
	my $installdir = xCAT::Utils->getInstallDir();
    #parse output, get the os name, type
    foreach $line(@$retinfo){
        if ($line =~ /(\w+)=(\S*)/){
            $imageattr{$1} = $2;
        }
    }
	#check the output
    unless($imageattr{'osname'}){
        web_infomsg("Image infomation error. Check the image first.\nprovision stop.", $callback);
        return;
    }

	if ('install' eq $imageattr{'provmethod'}){
		my $prepareinfo = web_provision_preinstall($imageattr{'osvers'}, $imageattr{'profile'}, $arch, $installdir, $request->{arg}->[4]);
		if ($prepareinfo){
			web_infomsg("$prepareinfo \nprovision stop.", $callback);
			return;
		}
	}
    
    if($imageattr{'osname'} =~ /aix/i){
        web_provisionaix($nodes, $imageName, $imageattr{'nimtype'}, $inic, $pnic, $master, $tftp, $nfs, $callback);
    }
    else{
        web_provisionlinux($nodes, $arch, $imageattr{'osvers'}, $imageattr{'provmethod'}, $imageattr{'profile'}, $inic, $pnic, $master, $tftp, $nfs, $callback);
    }
}

sub web_provisionlinux{
    my ($nodes, $arch, $os, $provmethod, $profile, $inic, $pnic, $master, $tftp, $nfs, $callback) = @_;
    my $outputMessage = '';
    my $retvalue = 0;
    my $netboot = '';
    if ($arch =~ /ppc/i){
        $netboot = 'yaboot';
    }
    elsif($arch =~ /x.*86/i){
        $netboot = 'xnba';
    }
    $outputMessage = "Do provison : $nodes \n".
          " Arch:$arch\n OS:$os\n Provision:$provmethod\n Profile:$profile\n Install NIC:$inic\n Primary NIC:$pnic\n" .
          " xCAT Master:$master\n TFTP Server:$tftp\n NFS Server:$nfs\n Netboot:$netboot\n";

    web_infomsg($outputMessage, $callback);

    #change the nodes attribute
    my $cmd = "chdef -t node -o $nodes arch=$arch os=$os provmethod=$provmethod profile=$profile installnic=$inic tftpserver=$tftp nfsserver=$nfs netboot=$netboot" .
              " xcatmaster=$master primarynic=$pnic";
    web_runcmd($cmd, $callback);
    #error return
    if ($::RUNCMD_RC){
        web_infomsg("Configure nodes' attributes error.\nprovision stop.", $callback);
        return;
    }

    #dhcp
    $cmd = "makedhcp $nodes";
    web_runcmd($cmd, $callback);
    if ($::RUNCMD_RC){
        web_infomsg("Make DHCP error.\nprovision stop.", $callback);
        return;
    }
    #restart dhcp
    $cmd = "service dhcpd restart";
    web_runcmd($cmd, $callback);
    #conserver
    $cmd = "makeconservercf $nodes";
    web_runcmd($cmd, $callback);
    if ($::RUNCMD_RC){
        web_infomsg("Configure conserver error.\nprovision stop.", $callback);
        return;
    }

    #for system x, should configure boot sequence first.
    if ($arch =~ /x.*86/i){
        $cmd = "rbootseq $nodes net,hd";
        web_runcmd($cmd, $callback);
        if($::RUNCMD_RC){
            web_infomsg("Set boot sequence error.\nprovision stop.", $callback);
            return;
        }
    }

    #nodeset
    $cmd = "nodeset $nodes $provmethod";
    web_runcmd($cmd, $callback);
    if ($::RUNCMD_RC){
        web_infomsg("Set nodes provision method error.\nprovision stop.", $callback);
        return;
    }
    
    #reboot the node fro provision
    if($arch =~ /ppc/i){
        $cmd = "rnetboot $nodes";
    }
    else{
        $cmd = "rpower $nodes boot";
    }
    web_runcmd($cmd, $callback);
    if ($::RUNCMD_RC){
        web_infomsg("Boot nodes error.\nprovision stop.", $callback);
        return;
    }

    #provision complete
    web_infomsg("Provision on $nodes success.\nprovision stop.");
}

sub web_provisionaix{
    my ($nodes, $imagename, $nimtype, $inic, $pnic, $master, $tftp, $nfs, $callback) = @_;
    my $outputMessage = '';
    my $retinfo;
    my %nimhash;
    my $line;
    my @updatenodes;
    my @addnodes;
    my $cmd = '';
    #set attibutes
    $cmd = "chdef -t node -o $nodes installnic=$inic tftpserver=$tftp nfsserver=$nfs xcatmaster=$master primarynic=$pnic";
    web_runcmd($cmd, $callback);
    if ($::RUNCMD_RC){
        web_infomsg("Change nodes' attributes error.\nprovision stop.", $callback);
        return;
    }
    #get all nim resource to filter nodes
    $retinfo = xCAT::Utils->runcmd("lsnim -c machines", -1, 1);
    foreach $line (@$retinfo){
        if($line =~ /(\S+)\s+\S+/){
            $nimhash{$1} = 1;
        }
    }

    foreach my $node(split(/,/, $nodes)){
        if ($nimhash{$node}){
            push(@updatenodes, $node);
        }
        else{
            push(@addnodes, $node);
        }
    }

    #xcat2nim
    if(0 < scalar(@addnodes)){
        $cmd = "xcat2nim -t node -o " . join(",", @addnodes);
        web_runcmd($cmd, $callback);
        if ($::RUNCMD_RC){
            web_infomsg("xcat2nim command error.\nprovision stop.", $callback);
            return;
        }
    }

    #update nimnode
    if(0 < scalar(@updatenodes)){
        $cmd = "xcat2nim -u -t node -o " . join(",", @updatenodes);
        web_runcmd($cmd, $callback);
        if ($::RUNCMD_RC){
            web_infomsg("xcat2nim command error.\nprovision stop.", $callback);
            return;
        }
    }

    #make con server
    $cmd = "makeconservercf $nodes";
    web_runcmd($cmd, $callback);
    if ($::RUNCMD_RC){
        web_infomsg("Configure conserver error.\nprovision stop.", $callback);
        return;
    }

    #nodeset
    if ($nimtype =~ /diskless/){
        $cmd = "mkdsklsnode -i $imagename $nodes";
    }
    else{
        $cmd = "nimnodeset -i $imagename $nodes";
    }
    web_runcmd($cmd, $callback);
    if ($::RUNCMD_RC){
        web_infomsg("Set node install method error.\nprovision stop.", $callback);
        return;
    }

    #reboot nodes
    $cmd = "rnetboot $nodes";
    web_runcmd($cmd, $callback);
    if ($::RUNCMD_RC){
        web_infomsg("Reboot nodes error.\nprovision stop.", $callback);
        return;
    }

    web_infomsg("Provision on $nodes success.\nprovision stop.");
}

#run the cmd by xCAT::Utils->runcmd and show information.
sub web_runcmd{
    my $cmd = shift;
    my $callback = shift;
    my $showstr = "\n" . $cmd . "\n";
    web_infomsg($showstr, $callback);
    my $retvalue = xCAT::Utils->runcmd($cmd, -1, 1);
    $showstr = join("\n", @$retvalue);
    $showstr .= "\n";
    web_infomsg($showstr, $callback);
}

sub web_infomsg {
    my $msg = shift;
    my $callback = shift;
    my %rsp;
    push @{$rsp{info}}, $msg;
    xCAT::MsgUtils->message('I', \%rsp, $callback);
    return;
}

sub web_summary{
    my ( $request, $callback, $sub_req ) = @_;
    my $groupName = $request->{arg}->[1];
    my @nodes;
    my $nodetypeTab;
	my $nodelistTab;
    my $attrs;
    my %oshash;
    my %archhash;
    my %provhash;
    my %typehash;
	my %statushash;
    my $retHash = {};
    my $temp;
    #$groupName is undefined, use all nodes
    if (defined($groupName)){
        @nodes = xCAT::NodeRange::noderange($groupName);
    }
    #groupName if definded, use the defined group name
    else{
        @nodes = xCAT::DBobjUtils->getObjectsOfType('node');
    }

    $nodetypeTab = xCAT::Table->new('nodetype');
    unless($nodetypeTab){
        return;
    }

	$nodelistTab = xCAT::Table->new('nodelist');
	unless($nodelistTab){
		return;
	}

    $attrs = $nodetypeTab->getNodesAttribs(\@nodes, ['os','arch','provmethod','nodetype']);
    unless($attrs){
        return;
    }

    while( my ($key, $value) = each(%{$attrs})){
        web_attrcount($value->[0]->{'os'}, \%oshash);
        web_attrcount($value->[0]->{'arch'}, \%archhash);
        web_attrcount($value->[0]->{'provmethod'},, \%provhash);
        web_attrcount($value->[0]->{'nodetype'},, \%typehash);
    }
    
	$attrs = $nodelistTab->getNodesAttribs(\@nodes, ['status']);
	while(my ($key, $value) = each(%{$attrs})){
		web_attrcount($value->[0]->{'status'}, \%statushash);
	}

    #status
	$temp = '';
	while(my ($key, $value) = each(%statushash)){
		$temp .= ($key . ':' . $value . ';');
	}
	$temp = substr($temp, 0, -1);
	push(@{$retHash->{'data'}}, 'Status=' . $temp);
	#os
    $temp = '';
    while(my ($key, $value) = each(%oshash)){
        $temp .= ($key . ':' . $value . ';');
    }
    $temp = substr($temp, 0, -1);
    push(@{$retHash->{'data'}}, 'Operating System=' . $temp);

    #arch
    $temp = '';
    while(my ($key, $value) = each(%archhash)){
        $temp .= ($key . ':' . $value . ';');
    }
    $temp = substr($temp, 0, -1);
    push(@{$retHash->{'data'}}, 'Architecture=' . $temp);

    #provmethod
    $temp = '';
    while(my ($key, $value) = each(%provhash)){
        $temp .= ($key . ':' . $value . ';');
    }
    $temp = substr($temp, 0, -1);
    push(@{$retHash->{'data'}}, 'Provision Method=' . $temp);

    #nodetype
    $temp = '';
    while(my ($key, $value) = each(%typehash)){
        $temp .= ($key . ':' . $value . ';');
    }
    $temp = substr($temp, 0, -1);
    push(@{$retHash->{'data'}}, 'Node Type=' . $temp);

    #return data
    $callback->($retHash);
}

#called by web_summay, count all attr numbers
sub web_attrcount{
    my ($key, $container) = @_;
    unless(defined($key)){
        $key = 'unknown';
    }

    if ($container->{$key}){
        $container->{$key}++;
    }
    else{
        $container->{$key} = 1;
    }
}

sub web_rinstall {
	my ( $request, $callback, $sub_req ) = @_;
	my $os = $request->{arg}->[1];
	my $profile = $request->{arg}->[2];
	my $arch = $request->{arg}->[3];
	my $node = $request->{arg}->[4];

	# Begin installation
	my $out = `rinstall -o $os -p $profile -a $arch $node`;

	$callback->( { data => $out } );
}

sub web_addnode{
	my ( $request, $callback, $sub_req ) = @_;
	my $nodetype = $request->{arg}->[1];
	my @tempArray = split(',', $request->{arg}->[2]);

	my $hcpname = shift(@tempArray);
	if ('node' ne $nodetype){
		my $username = $tempArray[0];
		my $passwd = $tempArray[1];
		my $ip = $tempArray[2];
		`/bin/grep '$hcpname' /etc/hosts`;
		if ($?){
			open(OUTPUTFILE, '>>/etc/hosts');
			print OUTPUTFILE "$ip  $hcpname\n";
			close(OUTPUTFILE);
		}
		if ('hmc' eq $nodetype){
			`chdef -t node -o $hcpname username=$username password=$passwd mgt=hmc nodetype=$nodetype groups=all`
		}
		else{
			`chdef -t node -o $hcpname username=$username password=$passwd mgt=blade mpa=$hcpname nodetype=$nodetype id=0 groups=mm,all`
		}
		return;
	}

	my %temphash;
	my $writeflag = 0;
	my $line = '';
	#save all node into a hash
	foreach(@tempArray) {
		$temphash{$_} = 1;
	}
	for (my $i = 0; $i < scalar(@tempArray); $i = $i + 2){
		$temphash{$tempArray[$i]} = $tempArray[$i + 1];
	}
	`rscan $hcpname -z > /tmp/rscanall.tmp`;
	#if can not create the rscan result file, error
	unless(-e '/tmp/rscanall.tmp'){
		return;
	}

	open(INPUTFILE, '/tmp/rscanall.tmp');
	open(OUTPUTFILE, '>/tmp/webrscan.tmp');
	while($line=<INPUTFILE>){
		if ($line =~ /(\S+):$/){
			if ($temphash{$1}){
				$writeflag = 1;
				print OUTPUTFILE $temphash{$1} . ":\n";
			}
			else{
				$writeflag = 0;
			}
		}
		else{
			if ($writeflag){
				print OUTPUTFILE $line;
			}
		}
	}

	close(INPUTFILE);
	close(OUTPUTFILE);
	unlink('/tmp/rscanall.tmp');

	`cat /tmp/webrscan.tmp | chdef -z`;
	unlink('/tmp/webrscan.tmp');
}

sub web_graphinfo{
	my ( $request, $callback, $sub_req ) = @_;
	my $nodetypeTab;
	my @nodes;
	my @parray;
	my @bladearray;
	my @xarray;
	my %phash;
	my %bladehash;
	my %xhash;
	my @unsupportarray;
	my @missinfoarray;
	my $result;
	my $pretstr = '';
	my $bladeretstr = '';
	my $xretstr = '';
	my $unsupretstr = '';
	my $missretstr = '';

	@nodes = xCAT::DBobjUtils->getObjectsOfType('node');

	$nodetypeTab = xCAT::Table->new('nodetype');
    unless($nodetypeTab){
        return;
    }

	#get all nodes type to seperate nodes into different group
	$result = $nodetypeTab->getNodesAttribs(\@nodes,['nodetype']);
	while(my ($key, $value) = each(%$result)){
		my $temptype = $value->[0]->{'nodetype'};
		if ($temptype =~ /(ppc|lpar|cec|frame)/i){
			push(@parray, $key);
		}
		elsif ($temptype =~ /blade/i){
			push(@bladearray, $key);
		}
		elsif ($temptype =~ /osi/i){
			push(@xarray, $key);
		}
		else{
			push(@unsupportarray, $key);
		}
	}
	$nodetypeTab->close();

	#get all infomations for system p node
	if (scalar(@parray) > 0){
		my $ppctab = xCAT::Table->new('ppc');
		#nodetype, parent
		$result = $ppctab->getNodesAttribs(\@parray, ['parent']);
		foreach(@parray){
			my $value = $result->{$_};
			if ($value->[0]){
				$phash{$_} = xCAT::DBobjUtils->getnodetype($_) . ':' . $value->[0]->{'parent'} . ':';
			}
			else{
				push(@missinfoarray, $_);
			}
		}
		$ppctab->close();

		undef @parray;
		@parray = keys %phash;
	}
	if (scalar(@parray) > 0){
		#mtm
		my $vpdtab = xCAT::Table->new('vpd');
		$result = $vpdtab->getNodesAttribs(\@parray, ['mtm']);
		foreach(@parray){
			my $value = $result->{$_};
			$phash{$_} = $phash{$_} . $value->[0]->{'mtm'} . ':';
		}
		$vpdtab->close();
		
		#status
		my $nodelisttab = xCAT::Table->new('nodelist');
		$result = $nodelisttab->getNodesAttribs(\@parray, ['status']);
		foreach(@parray){
			my $value = $result->{$_};
			$phash{$_} = $phash{$_} . $value->[0]->{'status'};
		}
		$nodelisttab->close();

		while(my ($key, $value) = each(%phash)){
			$pretstr = $pretstr . $key . ':' . $value . ';';
		}
	}

	#get all information for blade node
	if (scalar(@bladearray) > 0){
		#mpa, id
		my $mptab = xCAT::Table->new('mp');
		$result = $mptab->getNodesAttribs(\@bladearray, ['mpa', 'id']);
		foreach(@bladearray){
			my $value = $result->{$_};
			if ($value->[0]->{'mpa'}){
				$bladehash{$_} = 'blade:' . $value->[0]->{'mpa'} . ':' . $value->[0]->{'id'} . ':';
			}
			else{
				push(@missinfoarray, $_);
			}
		}
		$mptab->close();

		undef @bladearray;
		@bladearray = keys %bladehash;
	}
	if (scalar(@bladearray) > 0){
		#status
		my $nodelisttab = xCAT::Table->new('nodelist');
		$result = $nodelisttab->getNodesAttribs(\@bladearray, ['status']);
		foreach(@bladearray){
			my $value = $result->{$_};
			$bladehash{$_} = $bladehash{$_} . $value->[0]->{'status'};
		}
		$nodelisttab->close();
		while(my ($key, $value) = each(%bladehash)){
			$bladeretstr = $bladeretstr . $key . ':' . $value . ';';
		}
	}

	#get all information for system x node
	if (scalar(@xarray) > 0){
		#rack, unit
		my $nodepostab = xCAT::Table->new('nodepos');
		$result = $nodepostab->getNodesAttribs(\@xarray, ['rack', 'u']);
		foreach(@xarray){
			my $value = $result->{$_};
			if ($value->[0]->{'rack'}){
				$xhash{$_} = 'systemx:' . $value->[0]->{'rack'} . ':' . $value->[0]->{'u'} . ':';
			}
			else{
				push(@missinfoarray, $_);
			}
		}
		$nodepostab->close();

		undef @xarray;
		@xarray = keys %xhash;
	}
	if (scalar(@xarray) > 0){
		#mtm
		my $vpdtab = xCAT::Table->new('vpd');
		$result = $vpdtab->getNodesAttribs(\@xarray, ['mtm']);
		foreach(@xarray){
			my $value = $result->{$_};
			$xhash{$_} = $xhash{$_} . $value->[0]->{'mtm'} . ':';
		}
		$vpdtab->close();

		#status
		my $nodelisttab = xCAT::Table->new('nodelist');
		$result = $nodelisttab->getNodesAttribs(\@xarray, ['status']);
		foreach(@xarray){
			my $value = $result->{$_};
			$xhash{$_} = $xhash{$_} . $value->[0]->{'status'};
		}
		while(my ($key, $value) = each(%xhash)){
			$xretstr = $xretstr . $key . ':' . $value . ';';
		}
	}

	foreach(@missinfoarray){
		$missretstr = $missretstr . $_ . ':miss;'; 
	}

	#combine all information into a string
	my $retstr = $pretstr . $bladeretstr . $xretstr . $missretstr;
	if ($retstr){
		$retstr = substr($retstr, 0, -1);
	}

	$callback->({data => $retstr});
}

sub web_getdefaultuserentry {
	# Get default user entry
	my ( $request, $callback, $sub_req ) = @_;
	
	# Get hardware control point
	my $hcp = $request->{arg}->[1];
	my $profile = $request->{arg}->[2];
	
	if (!$profile) {
		$profile = 'default';
	}
	
	my $entry;
	if (!(`ssh $hcp "test -e /opt/zhcp/conf/profiles/$profile.direct && echo 'File exists'"`)) {
		$entry = `ssh $hcp "cat /opt/zhcp/conf/profiles/default.direct"`;
	} else {
		$entry = `ssh $hcp "cat /opt/zhcp/conf/profiles/$profile.direct"`;	
	}
	
	$callback->( { data => $entry } );
}
1;
