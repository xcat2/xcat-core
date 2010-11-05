# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head 1
    xCAT plugin package to handle webrun command

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

		#command => function
		'pping'         => \&web_pping,
		'update'        => \&web_update,
		'chtab'         => \&web_chtab,
		'lscondition'   => \&web_lscond,
		'lsresponse'    => \&web_lsresp,
		'lscondresp'    => \&web_lscondresp,
		'mkcondresp'    => \&web_mkcondresp,
		'startcondresp' => \&web_startcondresp,
		'stopcondresp'  => \&web_stopcondresp,
		'lsrsrc'        => \&web_lsrsrc,
		'lsrsrcdef-api' => \&web_lsrsrcdef,
		'gettab'        => \&web_gettab,
		'lsevent'       => \&web_lsevent,
		'lsdef'         => \&web_lsdef,
		'unlock'        => \&web_unlock,
		'rmcstart'      => \&web_rmcmonStart,
		'rmcshow'       => \&web_rmcmonShow,
		'gangliastart'  => \&web_gangliastart,
		'gangliastop'  => \&web_gangliastop,
		'gangliastatus' => \&web_gangliastatus,

		#'xdsh' => \&web_xdsh,
		#THIS list needs to be updated
	);

	#to check whether the request is authorized or not
	split ' ', $request->{arg}->[0];
	my $cmd = $_[0];
	if ( grep { $_ eq $cmd } keys %authorized_cmds ) {
		my $func = $authorized_cmds{$cmd};
		$func->( $request, $callback, $sub_req );
	}
	else {
		$callback->( { error => "$cmd is not authorized!\n", errorcode => [1] } );
	}
}

sub web_lsdef {
	my ( $request, $callback, $sub_req ) = @_;
	print Dumper($request);

	#TODO: web_lsdef works only for "lsdef <noderange> -i nodetype"
	my $ret   = `$request->{arg}->[0]`;
	my @lines = split '\n', $ret;

	split '=', $lines[2];
	my $ntype = $_[1];

	$callback->( { data => "$ntype" } );
}

sub web_lsevent {
	my ( $request, $callback, $sub_req ) = @_;
	my @ret = `$request->{arg}->[0]`;

	#print Dumper(\@ret);
	#please refer the manpage for the output format of "lsevent"

	my %data = ();

	my %record = ();

	my $i = 0;
	my $j = 0;

	foreach my $item (@ret) {
		if ( $item ne "\n" ) {
			chomp $item;
			my ( $key, $value ) = split( "=", $item );
			$record{$key} = $value;
			$j++;
			if ( $j == 3 ) {
				$i++;
				$j = 0;
				while ( my ( $k, $v ) = each %record ) {
					$data{$i}{$k} = $v;
				}
				%record = ();
			}
		}

	}

	#print Dumper(\%data);

	while ( my ( $key, $value ) = each %data ) {
		$callback->( { data => $value } );
	}
}

sub web_lsrsrcdef {
	my ( $request, $callback, $sub_req ) = @_;
	my $ret = `$request->{arg}->[0]`;

	my @lines = split '\n', $ret;
	shift @lines;
	print Dumper( \@lines );
	my $data = join( "=", @lines );
	$callback->( { data => "$data" } );

}

sub web_lsrsrc {
	my ( $request, $callback, $sub_req ) = @_;
	my $ret = `$request->{arg}->[0]`;
	my @classes;

	my @lines = split '\n', $ret;
	shift @lines;
	foreach my $line (@lines) {
		my $index = index( $line, '"', 1 );
		push @classes, substr( $line, 1, $index - 1 );
	}
	my $data = join( "=", @classes );
	$callback->( { data => "$data" } );
}

sub web_mkcondresp {
	my ( $request, $callback, $sub_req ) = @_;
	print Dumper( $request->{arg}->[0] );    #debug
	my $ret = system( $request->{arg}->[0] );

	#there's no output for "mkcondresp"
	#TODO
	if ($ret) {

		#failed
	}
}

sub web_startcondresp {
	my ( $request, $callback, $sub_req ) = @_;
	print Dumper( $request->{arg}->[0] );    #debug
	my $ret = system( $request->{arg}->[0] );
	if ($ret) {

		#to handle the failure
	}
}

sub web_stopcondresp {
	my ( $request, $callback, $sub_req ) = @_;
	print Dumper( $request->{arg}->[0] );    #debug
	my $ret = system( $request->{arg}->[0] );
	if ($ret) {

		#to handle the failure
	}
}

sub web_lscond {
	my ( $request, $callback, $sub_req ) = @_;
	my $ret = `lscondition`;

	my @lines = split '\n', $ret;
	shift @lines;
	shift @lines;
	foreach my $line (@lines) {
		$callback->( { data => $line } );
	}

}

sub web_lsresp {
	my ( $request, $callback, $sub_req ) = @_;
	my $ret = `lsresponse`;
	my @resps;

	my @lines = split '\n', $ret;
	shift @lines;
	shift @lines;

	foreach my $line (@lines) {
		$callback->( { data => $line } );
	}
}

sub web_lscondresp {
	my ( $request, $callback, $sub_req ) = @_;
	my @ret = `lscondresp`;
	shift @ret;
	shift @ret;

	foreach my $line (@ret) {
		chomp $line;
		$callback->( { data => $line } );
	}
}

# currently, web_chtab only handle chtab for the table "monitoring"
sub web_chtab {
	my ( $request, $callback, $sub_req ) = @_;
	split ' ', $request->{arg}->[0];
	my $tmp_str = $_[2];
	split '\.', $tmp_str;
	my $table = $_[0];    #get the table name
	if ( $table == "monitoring" ) {
		system("$request->{arg}->[0]");
	}
	else {
		$callback->( { error => "the table $table is not authorized!\n", errorcode => [1] } );
	}
}

sub web_gettab {

	#right now, gettab only support the monitoring table
	my ( $request, $callback, $sub_req ) = @_;
	split ' ', $request->{arg}->[0];
	my $tmp_str = $_[2];
	split '\.', $tmp_str;
	my $table = $_[0];
	if ( $table == "monitoring" ) {
		my $val = `$request->{arg}->[0]`;
		chomp $val;
		$callback->( { data => $val } );
	}
	else {
		$callback->(
			{
				error     => "The table $table is not authorized to get!\n",
				errorcode => [1]
			}
		);
	}
}

#-------------------------------------------------------

=head3   web_update

	Description	: Update the xCAT associate RPM on manangement node
    Arguments	: RPM Name
    			  Repository address
    Returns		: Nothing
    
=cut

#-------------------------------------------------------
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
					$ReturnInfo = $ReturnInfo . "update " . $_ . " failed: can not download the rpm\n";
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

#-------------------------------------------------------

=head3   web_pping

	Description	: Get the ping status of a given node
    Arguments	: Node
    Returns		: Nothing
    
=cut

#-------------------------------------------------------
sub web_pping {
	my ( $request, $callback, $sub_req ) = @_;

	# Treat the argument as the commandline, run it, and get the return message
	my $out = `$request->{arg}->[0]`;

	# Parse output, and use $callback to send back to the web interface
	# Output looks like:
	# 	xcat_n02: ping
	# 	xcat_n03: ping
	# 	xcat_n51: ping
	# 	xcat_n52: noping
	my @lines = split( '\n', $out );
	my $line;
	foreach $line (@lines) {
		split( ':', $line );
		$callback->(
			{
				node => [
					{
						name => [ $_[0] ],    # Node name
						data => [ $_[1] ]     # Output
					}
				]
			}
		);
	}
}

#-------------------------------------------------------

=head3   web_unlock

	Description	: Unlock a node by setting up the SSH keys
    Arguments	: 	Node
    				Password
    Returns		: Nothing
    
=cut

#-------------------------------------------------------
sub web_unlock {
	my ( $request, $callback, $sub_req ) = @_;

	my $node     = $request->{arg}->[1];
	my $password = $request->{arg}->[2];
	my $out      = `DSH_REMOTE_PASSWORD=$password xdsh $node -K`;

	$callback->( { data => $out } );
}

#-------------------------------------------------------

=head3   web_gangliastatus

	Description	: Get the status of Ganglia on a given node
    Arguments	: Node
    Returns		: Nothing
    
=cut

#-------------------------------------------------------
sub web_gangliastatus {
	my ( $request, $callback, $sub_req ) = @_;

	# Get node range
	my $nr = $request->{arg}->[1];
	my $out  = `xdsh $nr "service gmond status"`;

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
		}
		else {
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

#-------------------------------------------------------

=head3   web_gangliastart

	Description	: Start ganglia monitoring
    Arguments	: Node range
    Returns		: Nothing
    
=cut

#-------------------------------------------------------
sub web_gangliastart() {
	my ( $request, $callback, $sub_req ) = @_;
	
	# Get node range
	my $nr = $request->{arg}->[1];
	if (!$nr) {
		# If no node range is given, then assume all nodes
		$nr = '';
	}

	# Check the running status
	my $table = xCAT::Table->new('monitoring');
	my $gangWorkingStatus = $table->getAttribs( { name => 'gangliamon' }, 'disable' );
	$table . close();

	# Ganglia is running so return directly
	if ($gangWorkingStatus) {
		if ( $gangWorkingStatus->{disable} =~ /0|No|no|NO|N|n/ ) {
			$callback->( { info => 'Ganglia Monitoring is running now.' } );
			return;
		}
	}
	
	# Add gangliamon to the monitoring table
	my $info;
	my $output = `monadd gangliamon`;
	my @lines = split('\n', $output);
	foreach(@lines){
		if ($_) {
			$info .= ($_ . "\n");
		}
	}

	# Run the ganglia configuration script on node
	$output = `moncfg gangliamon $nr -r`;
	@lines = split('\n', $output);
	foreach(@lines){
		if ($_) {
			$info .= ($_ . "\n");
		}
	}

	# Start the gmond daemon on node
	$output = `monstart gangliamon $nr -r`;
	@lines = split('\n', $output);
	foreach(@lines){
		if ($_) {
			$info .= ($_ . "\n");
		}
	}

	$callback->( { info => $info } );
	return;
}

#-------------------------------------------------------

=head3   web_gangliastop

	Description	: Stop ganglia monitoring
    Arguments	: Node range
    Returns		: Nothing
    
=cut

#-------------------------------------------------------
sub web_gangliastop() {
	my ( $request, $callback, $sub_req ) = @_;
	
	# Get node range
	my $nr = $request->{arg}->[1];
	if (!$nr) {
		$nr = '';
	}

	# Start the gmond daemon on node
	my $info;
	my $output = `monstop gangliamon $nr -r`;
	my @lines = split('\n', $output);
	foreach(@lines){
		if ($_) {
			$info .= ($_ . "\n");
		}
	}

	$callback->( { info => $info } );
	return;
}

#-------------------------------------------------------

=head3   web_rmcStart

	Description	: Start the RMC monitoring on management node
    Arguments	: Nothing
    Returns		: Nothing
    
=cut

#-------------------------------------------------------
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
			$output = xCAT::Utils->runcmd( 'chtab name=rmcmon,key=montype monsetting.value=perf', -1, 1 );
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

	#configure the rmc monitoring
}

sub web_rmcmonShow() {
	my ( $request, $callback, $sub_req ) = @_;
	my $nodeRange = $request->{arg}->[1];
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
		$output =
		  xCAT::Utils->runcmd( "monshow rmcmon -s -t 10 -a PctTotalTimeIdle,PctTotalTimeWait,PctTotalTimeUser,PctTotalTimeKernel,PctRealMemFree", -1, 1 );
		foreach $temp (@$output) {

			#the attribute name
			if ( $temp =~ /Pct/ ) {
				$temp =~ s/ //g;

				#the first one
				if ( "" eq $retInfo ) {
					$retInfo .= ( $temp . ':' );
				}
				else {
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
			}
			else {
				push( @rmcNodes, @temp[0] );
			}
		}

		#there are not rmc nodes, so we should return directly
		if ( @rmcNodes < 1 ) {
			$callback->($retHash);
			return;
		}

		$tempNodes = join( ',', @rmcNodes );
		$output = xCAT::Utils->runcmd( "xdsh $tempNodes \"/bin/ps -ef | /bin/grep rmcd | /bin/grep -v grep\" | /bin/awk '{print \$1\$9}'", -1, 1 );
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
	$output =
	  xCAT::Utils->runcmd( "monshow rmcmon $nodeRange -t 60 -a PctTotalTimeIdle,PctTotalTimeWait,PctTotalTimeUser,PctTotalTimeKernel,PctRealMemFree", -1, 1 );
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
				push( @{ $retHash->{node} }, { name => $attrName, data => join( ',', @attrValue ) } );
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
