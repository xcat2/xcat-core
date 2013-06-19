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
use xCAT::TableUtils;
require XML::Parser;

sub handled_commands {
    return { webrun => "web" };
}

sub process_request {
    my $request         = shift;
    my $callback        = shift;
    my $sub_req         = shift;
    my %authorized_cmds = (
        'update'              => \&web_update,
        'lscondition'         => \&web_lscond,
        'lsresponse'          => \&web_lsresp,
        'lscondresp'          => \&web_lscondresp,
        'mkcondresp'          => \&web_mkcondresp,
        'startcondresp'       => \&web_startcondresp,
        'stopcondresp'        => \&web_stopcondresp,
        'lsevent'             => \&web_lsevent,
        'unlock'              => \&web_unlock,
        'rmcstart'            => \&web_rmcmonStart,
        'rmcshow'             => \&web_rmcmonShow,
        'gangliaconf'         => \&web_gangliaconf,
        'gangliastart'        => \&web_gangliastart,
        'gangliastop'         => \&web_gangliastop,
        'gangliastatus'       => \&web_gangliastatus,
        'gangliacheck'        => \&web_gangliacheck,
        'installganglia'      => \&web_installganglia,
        'mkcondition'         => \&web_mkcondition,
        'monls'               => \&web_monls,
        'dynamiciprange'      => \&web_dynamiciprange,
        'discover'            => \&web_discover,
        'updatevpd'           => \&web_updatevpd,
        'writeconfigfile'     => \&web_writeconfigfile,
        'createimage'         => \&web_createimage,
        'provision'           => \&web_provision,
        'summary'             => \&web_summary,
        'gangliashow'         => \&web_gangliaShow,
        'gangliacurrent'      => \&web_gangliaLatest,
        'rinstall'            => \&web_rinstall,
        'addnode'             => \&web_addnode,
        'graph'               => \&web_graphinfo,
        'getdefaultuserentry' => \&web_getdefaultuserentry,
        'getzdiskinfo'        => \&web_getzdiskinfo,
        'passwd'              => \&web_passwd,
        'policy'              => \&web_policy,
        'deleteuser'          => \&web_deleteuser,
        'mkzprofile'          => \&web_mkzprofile,
        'rmzprofile'          => \&web_rmzprofile,
        'mkippool'            => \&web_mkippool,
        'rmippool'            => \&web_rmippool,
        'lsippool'            => \&web_lsippool,
        'updateosimage'       => \&web_updateosimage,
        'rmosimage'           => \&web_rmosimage,
        'updategroup'         => \&web_updategroup,
        'rmgroup'             => \&web_rmgroup,
        'framesetup'          => \&web_framesetup,
        'cecsetup'            => \&web_cecsetup
    );

    # Check whether the request is authorized or not
    split ' ', $request->{arg}->[0];
    my $cmd = $_[0];
    if ( grep { $_ eq $cmd } keys %authorized_cmds ) {
        my $func = $authorized_cmds{$cmd};
        $func->( $request, $callback, $sub_req );
    }
    else {
        $callback->(
            { error => "$cmd is not authorized!\n", errorcode => [1] } );
    }
}

sub web_lsevent {
    my ( $request, $callback, $sub_req ) = @_;
    my @ret = `$request->{arg}->[0]`;

    # Please refer the manpage for the output format of lsevent
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
            }
            else {
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

    # Create new associations
    if ( 1 < length( @resp[0] ) ) {
        $cmd = substr( @resp[0], 1 );
        $cmd =~ s/,/ /;
        $cmd = 'mkcondresp ' . $conditionName . ' ' . $cmd;
        my $retInfo = xCAT::Utils->runcmd( $cmd, -1, 1 );
    }

    # Delete old associations
    if ( 1 < length( @resp[1] ) ) {
        $cmd = substr( @resp[1], 1 );
        $cmd =~ s/,/ /;
        $cmd = 'rmcondresp ' . $conditionName . ' ' . $cmd;
        my $retInfo = xCAT::Utils->runcmd( $cmd, -1, 1 );
    }

    # There is no output for mkcondresp
    $cmd = 'startcondresp ' . $conditionName;
    my $refInfo = xCAT::Utils->runcmd( $cmd, -1, 1 );
    $callback->( { data => "Success." } );
}

sub web_startcondresp {
    my ( $request, $callback, $sub_req ) = @_;
    my $conditionName = $request->{arg}->[1];
    my $cmd           = 'startcondresp "' . $conditionName . '"';
    my $retInfo       = xCAT::Utils->runcmd( $cmd, -1, 1 );
    $callback->(
        { data => 'start monitor "' . $conditionName . '" Successful.' } );
}

sub web_stopcondresp {
    my ( $request, $callback, $sub_req ) = @_;
    my $conditionName = $request->{arg}->[1];
    my $cmd           = 'stopcondresp "' . $conditionName . '"';
    my $retInfo       = xCAT::Utils->runcmd( $cmd, -1, 1 );
    $callback->(
        { data => 'stop monitor "' . $conditionName . '" Successful.' } );
}

sub web_lscond {
    my ( $request, $callback, $sub_req ) = @_;
    my $nodeRange = $request->{arg}->[1];
    my $names     = '';

    # List all the conditions for all lpars in this group
    if ($nodeRange) {
        my @nodes = xCAT::NodeRange::noderange($nodeRange);
        my %tempHash;
        my $nodeCount = @nodes;

        # No node in this group
        if ( 1 > $nodeCount ) {
            return;
        }

        # No conditions return
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

    # Only list the conditions on local
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

        my $retInfo =
          xCAT::Utils->runcmd( 'nodels ' . $groupName . " ppc.nodetype", -1,
            1 );
        foreach my $line (@$retInfo) {
            my @temp = split( ':', $line );
            if ( @temp[1] !~ /lpar/ ) {
                $callback->(
                    {
                        data =>
                          'Error : only the compute nodes\' group could select.'
                    }
                );
                return;
            }

            push( @nodes, @temp[0] );
        }

        xCAT::Utils->runcmd( 'chcondition -n ' + join( ',', @nodes ) + '-m m ' +
              $conditionName );
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

    # If there is a condition name, then we only show the condition linked associations
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
    my $os         = "unknown";
    my $rpmNames   = $request->{arg}->[1];
    my $repository = $request->{arg}->[2];
    my $fileHandle;
    my $cmd;
    my $returnInfo;
    my $webpageContent    = undef;
    my $remoteRpmFilePath = undef;
    my $localRpmFilePath  = undef;

    if ( xCAT::Utils->isLinux() ) {
        $os = xCAT::Utils->osver();

        # SUSE Linux
        if ( $os =~ /sles.*/ ) {
            $rpmNames =~ s/,/ /g;

            # Create zypper command
            $cmd = "zypper -n -p " . $repository . " update " . $rpmNames;
        }

        # Red Hat
        else {

            # Check the yum config file, and detect if it exists
            if ( -e "/tmp/xCAT_update.yum.conf" ) {
                unlink("/tmp/xCAT_update.yum.conf");
            }

            # Create file, return error if failed
            unless ( open( $fileHandle, '>>', "/tmp/xCAT_update.yum.conf" ) ) {
                $callback->(
                    { error => "Created temp file error!\n", errorcode => [1] }
                );
                return;
            }

            # Write the RPM path into config file
            print $fileHandle "[xcat_temp_update]\n";
            print $fileHandle "name=temp prepository\n";
            $repository = "baseurl=" . $repository . "\n";
            print $fileHandle $repository;
            print $fileHandle "enabled=1\n";
            print $fileHandle "gpgcheck=0\n";
            close($fileHandle);

            # Use system to run the command: yum -y -c config-file update rpm-names
            $rpmNames =~ s/,/ /g;
            $cmd = "yum -y -c /tmp/xCAT_update.yum.conf update " . $rpmNames . " 2>&1";
        }

        # Run the command and return the result
        $returnInfo = readpipe($cmd);
        $callback->( { info => $returnInfo } );
    }

    # AIX
    else {

        # Open the RPM path and read the page's content
        $webpageContent = LWP::Simple::get($repository);
        unless ( defined($webpageContent) ) {
            $callback->({
                    error     => "open $repository error, please check!!",
                    errorcode => [1]
                });
            return;
        }

        # Must support updating several RPM
        foreach ( split( /,/, $rpmNames ) ) {

            # Find out RPMs corresponding RPM HREF on the web page
            $webpageContent =~ m/href="($_-.*?[ppc64|noarch].rpm)/i;
            unless ( defined($1) ) {
                next;
            }
            $remoteRpmFilePath = $repository . $1;
            $localRpmFilePath  = '/tmp/' . $1;

            # Download RPM package to temp
            unless ( -e $localRpmFilePath ) {
                $cmd = "wget -O " . $localRpmFilePath . " " . $remoteRpmFilePath;
                if ( 0 != system($cmd) ) {
                    $returnInfo = $returnInfo . "update " . $_ . " failed: cannot download the RPM\n";
                    $callback->( { error => $returnInfo, errorcode => [1] } );
                    return;
                }
            }

            # Update RPM by RPM packages
            $cmd        = "rpm -U " . $localRpmFilePath . " 2>&1";
            $returnInfo = $returnInfo . readpipe($cmd);
        }

        $callback->( { info => $returnInfo } );
    }
}

sub web_unlock {
    my ( $request, $callback, $sub_req ) = @_;
    my $node     = $request->{arg}->[1];
    my $password = $request->{arg}->[2];

    # Unlock a node by setting up the SSH keys
    my $out = `DSH_REMOTE_PASSWORD=$password /opt/xcat/bin/xdsh $node -K`;

    $callback->( { data => $out } );
}

sub web_gangliastatus {
    my ( $request, $callback, $sub_req ) = @_;

    # Get node range
    my $nr  = $request->{arg}->[1];
    my $out = `/opt/xcat/bin/xdsh $nr "service gmond status"`;

    # Parse output, and use $callback to send back to the web interface
    # Output looks like:
    #     node_1: Checking for gmond: ..running
    #     node_2: Checking for gmond: ..running
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
        $callback->({
            node => [{
                    name => [ $_[0] ],    # Node name
                    data => [$status]     # Output
                }]
        });
    }
}

sub web_gangliaconf() {
    my ( $request, $callback, $sub_req ) = @_;

    # Get node range
    my $nr = $request->{arg}->[1];

    my $info;
    my $output;

    # Add gangliamon to the monitoring table (if not already)
    $output = `/opt/xcat/bin/monadd gangliamon`;

    # Run the ganglia configuration script on node
    if ($nr) {
        $output = `/opt/xcat/bin/moncfg gangliamon $nr -r`;
    }
    else {

        # If no node range is given, then assume all nodes

        # Handle localhost (this needs to be 1st)
        $output = `/opt/xcat/bin/moncfg gangliamon`;

        # Handle remote nodes
        $output .= `/opt/xcat/bin/moncfg gangliamon -r`;
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
    $output = `/opt/xcat/bin/monadd gangliamon`;

    # Start the gmond daemon on node
    if ($nr) {
        $output = `/opt/xcat/bin/moncfg gangliamon $nr -r`;
        $output .= `/opt/xcat/bin/monstart gangliamon $nr -r`;
    }
    else {

        # If no node range is given, then assume all nodes

        # Handle localhost (this needs to be 1st)
        $output = `/opt/xcat/bin/moncfg gangliamon`;

        # Handle remote nodes
        $output .= `/opt/xcat/bin/moncfg gangliamon -r`;

        # Handle localhost (this needs to be 1st)
        $output .= `/opt/xcat/bin/monstart gangliamon`;

        # Handle remote nodes
        $output .= `/opt/xcat/bin/monstart gangliamon -r`;
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
        $output = `/opt/xcat/bin/monstop gangliamon $nr -r`;
    }
    else {

        # If no node range is given, then assume all nodes

        # Handle localhost (this needs to be 1st)
        $output = `/opt/xcat/bin/monstop gangliamon`;

        # Handle remote nodes
        $output .= `/opt/xcat/bin/monstop gangliamon -r`;
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
    my $info = `/opt/xcat/bin/xdsh $nr "rpm -q ganglia-gmond libganglia libconfuse"`;
    $callback->( { info => $info } );
    return;
}

sub web_installganglia() {
    my ( $request, $callback, $sub_req ) = @_;

    # Get node range
    my $nr    = $request->{arg}->[1];
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
        $tab   = xCAT::Table->new('nodetype');
        $attrs =
          $tab->getNodeAttribs( $_, [ 'os', 'arch', 'profile', 'provmethod' ] );

        # If any attributes are missing, skip
        if ( !$attrs->{'os'}
	            || !$attrs->{'arch'}
	            || !$attrs->{'profile'}
	            || !$attrs->{'provmethod'} ){
            $callback->({ info => "$_: (Error) Missing attribute (os, arch, profile, or provmethod) in nodetype table" });
            next;
        }

        # Get the right OS type
        if ( $attrs->{'os'} =~ /fedora/ ) {
            $osType = 'fedora';
        } elsif ($attrs->{'os'} =~ /rh/
	            || $attrs->{'os'} =~ /rhel/
	            || $attrs->{'os'} =~ /rhels/ ) {
            $osType = 'rh';
        } elsif ( $attrs->{'os'} =~ /sles/ ) {
            $osType = 'sles';
        }

		# Assume /install/post/otherpkgs/<os>/<arch>/ directory is created
		# If Ganglia RPMs (ganglia-gmond-*, libconfuse-*, and libganglia-*) are not in directory
        $dir = "/install/post/otherpkgs/$attrs->{'os'}/$attrs->{'arch'}/";
        if (!( `test -e $dir/ganglia-gmond-* && echo 'File exists'`
                && `test -e $dir/libconfuse-* && echo 'File exists'`
                && `test -e $dir/libganglia-* && echo 'File exists'`
            )) {

            # Skip
            $callback->({ info => "$_: (Error) Missing Ganglia RPMs under $dir" });
            next;
        }

        # Find pkglist directory
        $dir = "/install/custom/$attrs->{'provmethod'}/$osType";
        if ( !(`test -d $dir && echo 'Directory exists'`) ) {
            # Create pkglist directory
            `mkdir -p $dir`;
        }

		# Find pkglist file
		# Ganglia RPM names should be added to /install/custom/<inst_type>/<ostype>/<profile>.<os>.<arch>.otherpkgs.pkglist
        $pkglist = "$attrs->{'profile'}.$attrs->{'os'}.$attrs->{'arch'}.otherpkgs.pkglist";
        if ( !(`test -e $dir/$pkglist && echo 'File exists'`) ) {

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
        if ( !( $info =~ /libapr1/ ) ) {
            $callback->(
                { info => "$_: (Error) libapr1 package not installed" } );
            next;
        }

        # Install Ganglia RPMs using updatenode
        $callback->( { info => "$_: Installing Ganglia..." } );
        $info = `/opt/xcat/bin/updatenode $_ -S`;
        $callback->( { info => "$info" } );
    }

    return;
}

sub web_gangliaShow {
	# Get ganglia data from RRD file
	
    my ( $request, $callback, $sub_req ) = @_;
    my $nodename   = $request->{arg}->[1];
    my $timeRange  = 'now-1h';
    my $resolution = 60;
    my $metric     = $request->{arg}->[3];
    my @nodes      = ();
    my $retStr     = '';
    my $runInfo;
    my $cmd     = '';
    my $dirname = '/var/lib/ganglia/rrds/__SummaryInfo__/';

    # Get the summary for this grid (the meaning of grid is referenced from Ganglia)
    if ( '_grid_' ne $nodename ) {
        $dirname = '/var/lib/ganglia/rrds/' . $nodename . '/';
    }

    if ( 'hour' eq $request->{arg}->[2] ) {
        $timeRange  = 'now-1h';
        $resolution = 60;
    } elsif ( 'day' eq $request->{arg}->[2] ) {
        $timeRange  = 'now-1d';
        $resolution = 1800;
    }

    if ( '_summary_' eq $metric ) {
        my @metricArray = (
            'load_one',  'cpu_num',    'cpu_idle',  'mem_free',
            'mem_total', 'disk_total', 'disk_free', 'bytes_in',
            'bytes_out'
        );
        
        my $filename = '';
        my $step     = 1;
        my $index    = 0;
        my $size     = 0;
        foreach my $tempmetric (@metricArray) {
            my $temp = '';
            my $line = '';
            $retStr .= $tempmetric . ':';
            $filename = $dirname . $tempmetric . '.rrd';
            $cmd      = "rrdtool fetch $filename -s $timeRange -r $resolution AVERAGE";
            $runInfo = xCAT::Utils->runcmd( $cmd, -1, 1 );
            if ( scalar(@$runInfo) < 3 ) {
                $callback->( { data => 'error.' } );
                return;
            }

            # Delete the first 2 lines
            shift(@$runInfo);
            shift(@$runInfo);

            # We only support 60 lines for one metric, in order to reduce the data load for web GUI
            $size = scalar(@$runInfo);
            if ( $size > 60 ) {
                $step = int( $size / 60 ) + 1;
            }

            if ( ( $tempmetric eq 'cpu_idle' ) && ( '_grid_' eq $nodename ) ) {
                my $cpuidle = 0;
                my $cpunum  = 0;
                for ( $index = 0 ; $index < $size ; $index += $step ) {
                    if ( $runInfo->[$index] =~ /^(\S+): (\S+) (\S+)/ ) {
                        my $timestamp = $1;
                        my $value     = $2;
                        my $valuenum  = $3;
                        if (( lc($value) =~ /nanq/ ) || ( lc($value) =~ /nan/ )) {
                            # The rrdtool fetch last line is always NaN, so no need to add into the return string
                            if ( $index == ( $size - 1 ) ) {
                                next;
                            }
                            
                            $temp .= $timestamp . ',0,';
                        } else {
                            $cpuidle = sprintf "%.2f", $value;
                            $cpunum  = sprintf "%.2f", $valuenum;
                            $temp .= $timestamp . ',' . ( sprintf "%.2f", $cpuidle / $cpunum ) . ',';
                        }
                    }
                }
            } else {
                for ( $index = 0 ; $index < $size ; $index += $step ) {
                    if ( $runInfo->[$index] =~ /^(\S+): (\S+).*/ ) {
                        my $timestamp = $1;
                        my $value     = $2;
                        if (( lc($value) =~ /nanq/ ) || ( lc($value) =~ /nan/ )) {
                            # The rrdtool fetch last line is always NaN, so no need to add into the return string
                            if ( $index == ( $size - 1 ) ) {
                                next;
                            }
                            
                            $temp .= $timestamp . ',0,';
                        } else {
                            $temp .= $timestamp . ',' . ( sprintf "%.2f", $2 ) . ',';
                        }
                    }
                }
            }
            
            $retStr .= substr( $temp, 0, -1 ) . ';';
        }
        
        $retStr = substr( $retStr, 0, -1 );
        $callback->( { data => $retStr } );
        return;
    }
}

my $ganglia_return_flag = 0;
my %gangliaHash;
my $gangliaclustername;
my $ganglianodename;

sub web_gangliaLatest {
	# Use socket to connect ganglia port to get the latest value/status
	
    my ( $request, $callback, $sub_req ) = @_;
    my $type      = $request->{arg}->[1];
    my $groupname = '';
    my $xmlparser;
    my $telnetcmd = '';
    my $connect;
    my $xmloutput   = '';
    my $tmpFilename = '/tmp/gangliadata';

    $ganglia_return_flag = 0;
    $gangliaclustername  = '';
    $ganglianodename     = '';
    undef(%gangliaHash);

    if ( $request->{arg}->[2] ) {
        $groupname = $request->{arg}->[2];
    }
    if ( 'grid' eq $type ) {
        $xmlparser = XML::Parser->new(
            Handlers => {
                Start => \&web_gangliaGridXmlStart,
                End   => \&web_gangliaXmlEnd
            });
        $telnetcmd   = "/?filter=summary\n";
        $tmpFilename = '/tmp/gangliagriddata';
    } elsif ( 'node' eq $type ) {
        $xmlparser = XML::Parser->new(
            Handlers => {
                Start => \&web_gangliaNodeXmlStart,
                End   => \&web_gangliaXmlEnd
            });
        $telnetcmd   = "/\n";
        $tmpFilename = '/tmp/ganglianodedata';
    }

    # Use socket to telnet 127.0.0.1:8652 (Ganglia's interactive port)
    $connect = IO::Socket::INET->new('127.0.0.1:8652');
    unless ($connect) {
        $callback->( { 'data' => 'error: connect local port failed.' } );
        return;
    }

    print $connect $telnetcmd;
    open( TEMPFILE, '>' . $tmpFilename );
    while (<$connect>) {
        print TEMPFILE $_;
    }
    
    close($connect);
    close(TEMPFILE);

    $xmlparser->parsefile($tmpFilename);

    if ( 'grid' eq $type ) {
        web_gangliaGridLatest($callback);
    } elsif ( 'node' eq $type ) {
        web_gangliaNodeLatest( $callback, $groupname );
    }
    return;
}

sub web_gangliaGridLatest {
	# Create return data for grid current status
	
    my $callback    = shift;
    my $retStr      = '';
    my $timestamp   = time();
    my $metricname  = '';
    my @metricArray = (
        'load_one',   'cpu_num',   'mem_total', 'mem_free',
        'disk_total', 'disk_free', 'bytes_in',  'bytes_out'
    );

    if ( $gangliaHash{'cpu_idle'} ) {
        my $sum = $gangliaHash{'cpu_idle'}->{'SUM'};
        my $num = $gangliaHash{'cpu_idle'}->{'NUM'};
        $retStr .= 'cpu_idle:'
          . $timestamp . ','
          . ( sprintf( "%.2f", $sum / $num ) ) . ';';
    }
    
    foreach $metricname (@metricArray) {
        if ( $gangliaHash{$metricname} ) {
            $retStr .=
                $metricname . ':'
              . $timestamp . ','
              . $gangliaHash{$metricname}->{'SUM'} . ';';
        }
    }
    
    $retStr = substr( $retStr, 0, -1 );
    $callback->( { data => $retStr } );
}

sub web_gangliaNodeLatest {
	# Create return data for node current status
	
    my ( $callback, $groupname ) = @_;
    my $node      = '';
    my $retStr    = '';
    my $timestamp = time() - 180;
    my @nodes;

    # Get all nodes by group
    if ($groupname) {
        @nodes = xCAT::NodeRange::noderange( $groupname, 1 );
    } else {
        @nodes = xCAT::DBobjUtils->getObjectsOfType('node');
    }
    
    foreach $node (@nodes) {
        # If the node has Ganglia
        if ( $gangliaHash{$node} ) {
            my $lastupdate = $gangliaHash{$node}->{'timestamp'};

            # Cannot get monitor data for too long
            if ( $lastupdate < $timestamp ) {
                $retStr .= $node . ':ERROR,Can not get monitor data more than 3 minutes!;';
                next;
            }

            if ( $gangliaHash{$node}->{'load_one'} >
                $gangliaHash{$node}->{'cpu_num'} ) {
                $retStr .= $node . ':WARNING,';
            } else {
                $retStr .= $node . ':NORMAL,';
            }
            
            $retStr .= $gangliaHash{$node}->{'path'} . ';';
        } else {
            $retStr .= $node . ':UNKNOWN,;';
        }
    }

    $retStr = substr( $retStr, 0, -1 );
    $callback->( { data => $retStr } );
}

sub web_gangliaXmlEnd {
	# XML parser end function, do noting here
}

sub web_gangliaGridXmlStart {
	# XML parser start function
	
    my ( $parseinst, $elementname, %attrs ) = @_;
    my $metricname = '';

    # Only parse grid information
    if ($ganglia_return_flag) {
        return;
    }
    
    if ( 'METRICS' eq $elementname ) {
        $metricname                        = $attrs{'NAME'};
        $gangliaHash{$metricname}->{'SUM'} = $attrs{'SUM'};
        $gangliaHash{$metricname}->{'NUM'} = $attrs{'NUM'};
    } elsif ( 'CLUSTER' eq $elementname ) {
        $ganglia_return_flag = 1;
        return;
    } else {
        return;
    }
}

sub web_gangliaNodeXmlStart {
    # XML parser start function for node current status
    
    my ( $parseinst, $elementname, %attrs ) = @_;
    my $metricname = '';

    # Save cluster name
    if ( 'CLUSTER' eq $elementname ) {
        $gangliaclustername = $attrs{'NAME'};
        return;
    } elsif ( 'HOST' eq $elementname ) {
        if ( $attrs{'NAME'} =~ /(\S+?)\.(.*)/ ) {
            $ganglianodename = $1;
        } else {
            $ganglianodename = $attrs{'NAME'};
        }
        
        $gangliaHash{$ganglianodename}->{'path'} =
          $gangliaclustername . '/' . $attrs{'NAME'};
        $gangliaHash{$ganglianodename}->{'timestamp'} = $attrs{'REPORTED'};
    } elsif ( 'METRIC' eq $elementname ) {
        $metricname = $attrs{'NAME'};
        if ( ( 'load_one' eq $metricname ) || ( 'cpu_num' eq $metricname ) ) {
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

    # Check running status
    $table = xCAT::Table->new('monitoring');
    my $rmcWorkingStatus = $table->getAttribs( { name => 'rmcmon' }, 'disable' );
    $table . close();

    # RMC monitoring is running so return
    if ($rmcWorkingStatus) {
        if ( $rmcWorkingStatus->{disable} =~ /0|No|no|NO|N|n/ ) {
            $callback->( { info => 'RMC Monitoring is running now.' } );
            return;
        }
    }

    $retData .= "RMC is not running, start it now.\n";

    # Check monsetting table to see if rmc's montype contains performance
    $table = xCAT::Table->new('monsetting');
    my $rmcmonType =
      $table->getAttribs( { name => 'rmcmon', key => 'montype' }, 'value' );
    $table . close();

    # RMC monitoring is not configured right, we should configure it again
    # There is no rmcmon in monsetting table
    if ( !$rmcmonType ) {
        $output = xCAT::Utils->runcmd( 'monadd rmcmon -s [montype=perf]', -1, 1 );
        foreach (@$output) {
            $retData .= ( $_ . "\n" );
        }
        
        $retData .= "Adding rmcmon to the monsetting table complete.\n";
    }

    # Configure before but there is no performance monitoring, so change the table
    else {
        if ( !( $rmcmonType->{value} =~ /perf/ ) ) {
            $output = xCAT::Utils->runcmd('chtab name=rmcmon,key=montype monsetting.value=perf', -1, 1 );
            foreach (@$output) {
                $retData .= ( $_ . "\n" );
            }
            
            $retData .= "Change the rmcmon configure in monsetting table finish.\n";
        }
    }

    # Run the rmccfg command to add all nodes into local RMC configuration
    $output = xCAT::Utils->runcmd("moncfg rmcmon $nodeRange", -1, 1);
    foreach (@$output) {
        $retData .= ( $_ . "\n" );
    }

    # Run the rmccfg command to add all nodes into remote RMC configuration
    $output = xCAT::Utils->runcmd( "moncfg rmcmon $nodeRange -r", -1, 1 );
    foreach (@$output) {
        $retData .= ( $_ . "\n" );
    }

    # Start the RMC monitor
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

    # Only get the system RMC info
    if ( 'summary' eq $nodeRange ) {
        $output = xCAT::Utils->runcmd( "monshow rmcmon -s -t 60 -o p -a " . $attr, -1, 1 );
        foreach $temp (@$output) {
            # The attribute name
            if ( $temp =~ /Pct/ ) {
                $temp =~ s/ //g;

                # The first one
                if ( "" eq $retInfo ) {
                    $retInfo .= ( $temp . ':' );
                } else {
                    $retInfo =~ s/,$/;/;
                    $retInfo .= ( $temp . ':' );
                }
                
                next;
            }

            # The content of the attribute
            $temp =~ m/\s+(\d+\.\d{4})/;
            if ( defined($1) ) {
                $retInfo .= ( $1 . ',' );
            }
        }

        # Return the RMC info
        $retInfo =~ s/,$//;
        $callback->( { info => $retInfo } );
        return;
    }

    if ('compute' eq $nodeRange) {
        my $node;

        @nodes = xCAT::NodeRange::noderange($nodeRange);
        for $node (@nodes) {
            if ( -e "/var/rrd/$node" ) {
                push( @{ $retHash->{node} }, { name => $node, data => 'OK' } );
            } else {
                push( @{ $retHash->{node} }, { name => $node, data => 'UNKNOWN' } );
            }
        }

        $callback->($retHash);
        return;
    }

    my $attrName = "";
    my @attrs = split( /,/, $attr );
    for $attrName (@attrs) {
        my @attrValue = ();
        $output = xCAT::Utils->runcmd( "rrdtool fetch /var/rrd/${nodeRange}/${attrName}.rrd -r 60 -s e-1h AVERAGE", -1, 1 );
        foreach (@$output) {
            $temp = $_;
            if ( $temp eq '' ) {
                next;
            }

            if ( lc($temp) =~ /[nanq|nan]/ ) {
                next;
            }

            if ( $temp =~ /^(\d+): (\S+) (\S+)/ ) {
                push( @attrValue, ( sprintf "%.2f", $2 ) );
            }
        }

        if ( scalar(@attrValue) > 1 ) {
            push( @{ $retHash->{node} }, { name => $attrName, data => join( ',', @attrValue ) } );
        } else {
            $retHash->{node} = { name => $attrName, data => '' };
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

sub web_dynamiciprange {
    my ( $request, $callback, $sub_req ) = @_;
    my $iprange = $request->{arg}->[1];

    open( TEMPFILE, '>/tmp/iprange.conf' );
    print TEMPFILE "xcat-service-lan:\n";
    print TEMPFILE "dhcp-dynamic-range = " . $iprange . "\n";
    close(TEMPFILE);

    # Run xcatsetup command to change the dynamic IP range
    xCAT::Utils->runcmd( "xcatsetup /tmp/iprange.conf", -1, 1 );
    unlink('/tmp/iprange.conf');
    xCAT::Utils->runcmd( "makedhcp -n", -1, 1 );

    # Restart the DHCP server
    if ( xCAT::Utils->isLinux() ) {
        # xCAT::Utils->runcmd("service dhcpd restart", -1, 1);
    } else {
        # xCAT::Utils->runcmd("startsrc -s dhcpsd", -1, 1);
    }
}

sub web_discover {
    my ( $request, $callback, $sub_req ) = @_;
    my $type = uc( $request->{arg}->[1] );

    my $retStr  = '';
    my $retInfo = xCAT::Utils->runcmd( "lsslp -m -s $type 2>/dev/null | grep -i $type | awk '{print \$1\":\" \$2\"-\"\$3}'", -1, 1 );
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
        # The sequence must be object name, mtm, serial
        my @temp = split( /,/, $hard );
        $vpdtab->setAttribs( { 'node' => @temp[0] }, { 'serial' => @temp[2], 'mtm' => @temp[1] } );
    }

    $vpdtab->close();
}

sub web_writeconfigfile {
    my ( $request, $callback, $sub_req ) = @_;
    my $filename = $request->{arg}->[1];
    my $content  = $request->{arg}->[2];

    open( TEMPFILE, '>' . $filename );
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
    my $installdir = xCAT::TableUtils->getInstallDir();
    my $tempos     = $ostype;
    $tempos =~ s/[0-9\.]//g;
    my $CONFILE;
    my $archFlag = 0;
    my $ret      = '';
    my $cmdPath  = '';

    if ( $request->{arg}->[6] ) {
        @softArray = split( ',', $request->{arg}->[6] );

        # Check the custom package, if the directory does not exist, create the directory first
        if ( -e "$installdir/custom/netboot/$ostype/" ) {
            # The path exist, so archive all file under this path
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
            # No need to archive
            $archFlag = 0;
            system("mkdir -p $installdir/custom/netboot/$ostype/");
        }

        # Write pkglist
        open( $CONFILE, ">$installdir/custom/netboot/$ostype/$profile.pkglist" );
        print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/IBMhpc.$ostype.ppc64.pkglist# \n";
        close($CONFILE);

        # Write otherpkglist
        open( $CONFILE, ">$installdir/custom/netboot/$ostype/$profile.otherpkgs.pkglist" );
        print $CONFILE "\n";
        close($CONFILE);

        # Write exlist for stateless
        open( $CONFILE, ">$installdir/custom/netboot/$ostype/$profile.exlist" );
        print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/IBMhpc.$ostype.$osarch.exlist#\n";
        close($CONFILE);

        # Write postinstall
        open( $CONFILE, ">$installdir/custom/netboot/$ostype/$profile.postinstall" );
        print $CONFILE "/opt/xcat/share/xcat/IBMhpc/IBMhpc.$tempos.postinstall \$1 \$2 \$3 \$4 \$5 \n";
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
            } elsif ( 'ganglia' eq $soft ) {
                web_gangliaConfig( $ostype, $profile, $osarch, 'netboot', $installdir );
            }
        }

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

    # For stateless only run packimage
    if ( 'stateless' eq $imagetype ) {
        my $retInfo = xCAT::Utils->runcmd( "${cmdPath}/genimage -i $bootif -n $netdriver -o $ostype -p $profile", -1, 1 );
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
        # For statelist we should check the litefile table
        # Step 1: Save the old litefile table content into litefilearchive.csv
        system('tabdump litefile > /tmp/litefilearchive.csv');

        # Step 2: Write the new litefile.csv for this lite image
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
            print $CONFILE '"ALL","/etc/rsyslog.conf.XCATORIG","tmpfs",,'
              . "\n";
            print $CONFILE '"ALL","/etc/udev/","tmpfs",,' . "\n";
            print $CONFILE '"ALL","/etc/ntp.conf.predhclient","tmpfs",,' . "\n";
            print $CONFILE '"ALL","/etc/resolv.conf.predhclient","tmpfs",,'
              . "\n";
        } else {
            print $CONFILE '"ALL","/etc/ntp.conf.org","tmpfs",,' . "\n";
            print $CONFILE '"ALL","/etc/syslog-ng/","tmpfs",,' . "\n";
            print $CONFILE '"ALL","/etc/fstab","tmpfs",,' . "\n";
        }
        close($CONFILE);

        # Write the HPC software litefile into temp litefile.csv
        for my $soft (@softArray) {
            $soft = lc($soft);
            if ( -e "/opt/xcat/share/xcat/IBMhpc/$soft/litefile.csv" ) {
                system("grep '^[^#]' /opt/xcat/share/xcat/IBMhpc/$soft/litefile.csv >> /tmp/litefile.csv");
            }
        }

        system("tabrestore /tmp/litefile.csv");

        # Create the image
        my $retInfo = xCAT::Utils->runcmd("${cmdPath}/genimage -i $bootif -n $netdriver -o $ostype -p $profile", -1, 1);
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

    system("createrepo $installdir/post/otherpkgs/$ostype/$osarch/gpfs");

    open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.otherpkgs.pkglist" );
    print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/gpfs/gpfs.otherpkgs.pkglist#\n";
    close($CONFILE);

    open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.exlist" );
    print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/gpfs/gpfs.exlist#\n";
    close($CONFILE);

    system('cp /opt/xcat/share/xcat/IBMhpc/gpfs/gpfs_mmsdrfs $installdir/postscripts/gpfs_mmsdrfs');
    open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.postinstall" );
    print $CONFILE "NODESETSTATE=genimage installroot=\$1 /opt/xcat/share/xcat/IBMhpc/gpfs/gpfs_updates\n";
    print $CONFILE "installroot=\$1 $installdir/postscripts/gpfs_mmsdrfs\n";
    close($CONFILE);
}

sub web_rsctConfigure {
    my ( $ostype, $profile, $osarch, $installdir ) = @_;
    my $CONFILE;

    system("createrepo $installdir/post/otherpkgs/$ostype/$osarch/rsct");

    if ( $ostype =~ /sles/i ) {
        open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.pkglist" );
        print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/rsct/rsct.pkglist# \n";
        close($CONFILE);
    }

    open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.exlist" );
    print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/rsct/rsct.exlist#\n";
    close($CONFILE);

    open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.postinstall" );
    print $CONFILE "installroot=\$1 rsctdir=$installdir/post/otherpkgs/rhels6/ppc64/rsct NODESETSTATE=genimage   /opt/xcat/share/xcat/IBMhpc/rsct/rsct_install\n";
    close($CONFILE);
}

sub web_peConfigure {
    my ( $ostype, $profile, $osarch, $installdir ) = @_;
    my $CONFILE;

    system("createrepo $installdir/post/otherpkgs/$ostype/$osarch/pe");
    system("createrepo $installdir/post/otherpkgs/$ostype/$osarch/compilers");

    open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.pkglist" );
    if ( $ostype =~ /rh/i ) {
        print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/pe/pe.$ostype.pkglist#\n";
    } else {
        print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/compilers/compilers.pkglist#\n";
        print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/pe/pe.pkglist#\n";
    }
    
    close($CONFILE);

    open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.otherpkgs.pkglist" );
    print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/pe/pe.otherpkgs.pkglist#\n";
    close($CONFILE);

    open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.exlist" );
    print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/compilers/compilers.exlist#\n";
    print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/pe/pe.exlist#\n";
    close($CONFILE);

    open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.postinstall" );
    print $CONFILE "installroot=\$1 NODESETSTATE=genimage   /opt/xcat/share/xcat/IBMhpc/compilers/compilers_license";
    print $CONFILE "installroot=\$1 pedir=$installdir/post/otherpkgs/rhels6/ppc64/pe NODESETSTATE=genimage   /opt/xcat/share/xcat/IBMhpc/pe/pe_install";
    close($CONFILE);
}

sub web_esslConfigure {
    my ( $ostype, $profile, $osarch, $installdir ) = @_;
    my $CONFILE;

    system("createrepo $installdir/post/otherpkgs/$ostype/$osarch/essl");

    open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.pkglist" );
    if ( $ostype =~ /rh/i ) {
        print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/compilers/compilers.rhels6.pkglist#\n";
    } else {
        print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/essl/essl.pkglist#\n";
    }

    open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.otherpkgs.pkglist" );
    print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/essl/essl.otherpkgs.pkglist#\n";
    close($CONFILE);

    open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.exlist" );
    print $CONFILE "#INCLUDE:/opt/xcat/share/xcat/IBMhpc/essl/essl.exlist#\n";
    close($CONFILE);

    open( $CONFILE, ">>$installdir/custom/netboot/$ostype/$profile.postinstall" );
    print $CONFILE, "installroot=\$1 essldir=$installdir/post/otherpkgs/rhels6/ppc64/essl NODESETSTATE=genimage   /opt/xcat/share/xcat/IBMhpc/essl/essl_install";
    close($CONFILE);
}

sub web_gangliaConfig {
    my ( $ostype, $profile, $osarch, $provtype, $installdir ) = @_;
    my $CONFILE;

    system("createrepo $installdir/post/otherpkgs/$ostype/$osarch/ganglia");

    open( $CONFILE, ">>$installdir/custom/$provtype/$ostype/$profile.otherpkgs.pkglist" );
    print $CONFILE "#created by xCAT Web Gui.\n";
    print $CONFILE "ganglia/ganglia\n";
    print $CONFILE "ganglia/ganglia-gmond\n";
    print $CONFILE "ganglia/ganglia-gmetad\n";
    print $CONFILE "ganglia/rrdtool\n";
    close($CONFILE);
}

sub web_gangliaRpmCheck {
    my ( $ostype, $profile, $osarch, $installdir ) = @_;
    my @rpmnames = ( "rrdtool", "ganglia", "ganglia-gmond", "ganglia-gmetad" );
    my %temphash;
    my $rpmdir   = "$installdir/post/otherpkgs/$ostype/$osarch/ganglia";
    my $errorstr = '';
    unless ( -e $rpmdir ) {
        return "Put rrdtool,ganglia,ganglia-gmond,ganglia-gmetad rpms into $rpmdir.";
    }

    opendir( DIRHANDLE, $rpmdir );
    foreach my $filename ( readdir(DIRHANDLE) ) {
        if ( $filename =~ /(\D+)-(\d+)\..*\.rpm$/ ) {
            $temphash{$1} = 1;
        }
    }
    closedir(DIRHANDLE);

    # Check if all RPMs are in the array
    foreach (@rpmnames) {
        unless ( $temphash{$_} ) {
            $errorstr .= $_ . ',';
        }
    }

    if ($errorstr) {
        $errorstr = substr( $errorstr, 0, -1 );
        return "Put $errorstr rpms into $rpmdir.";
    } else {
        return "";
    }
}

sub web_restoreChange {
    my ( $software, $archFlag, $imagetype, $ostype, $installdir ) = @_;

    # Recover all file in the $installdir/custom/netboot/$ostype/
    if ($software) {
        system("rm -f $installdir/custom/netboot/$ostype/*.*");
    }

    if ($archFlag) {
        system("mv /tmp/webImageArch/*.* $installdir/custom/netboot/$ostype/");
    }

    # Recover the litefile table for statelite image
    if ( 'statelite' == $imagetype ) {
        system("rm -r /tmp/litefile.csv ; mv /tmp/litefilearchive.csv /tmp/litefile.csv ; tabrestore /tmp/litefile.csv");
    }
}

sub web_provision_preinstall {
    my ( $ostype, $profile, $arch, $installdir, $softwarenames ) = @_;
    my $checkresult = '';
    my $errorstr    = '';
    my @software    = split( ',', $softwarenames );
    my $softwarenum = scalar(@software);

    if ( -e "$installdir/custom/install/$ostype/" ) {
        opendir( DIRHANDLE, "$installdir/custom/install/$ostype/" );
        foreach my $filename ( readdir(DIRHANDLE) ) {
            if ( '.' eq $filename || '..' eq $filename ) {
                next;
            }
            
            $filename = "$installdir/custom/install/$ostype/" . $filename;
            if ( $filename =~ /(.*)\.guibak$/ ) {
                if ( $softwarenum < 1 ) {
                    system("mv $filename $1");
                }
                next;
            }
            
            `/bin/grep 'xCAT Web Gui' $filename`;
            if ($?) {
                # Backup the original config file
                if ( $softwarenum > 0 ) {
                    system("mv $filename ${filename}.guibak");
                }
            } else {
                unlink($filename);
            }
        }
        
        closedir(DIRHANDLE);
    } else {
        `mkdir -p $installdir/custom/install/$ostype -m 0755`;
    }

    if ( $softwarenum < 1 ) {
        return '';
    }

    foreach (@software) {
        if ( 'ganglia' eq $_ ) {
            $checkresult = web_gangliaRpmCheck( $ostype, $profile, $arch, $installdir );
        }
        
        if ($checkresult) {
            $errorstr .= $checkresult . "\n";
        }
    }

    if ($errorstr) {
        return $errorstr;
    }

    foreach (@software) {
        if ( 'ganglia' eq $_ ) {
            web_gangliaConfig( $ostype, $profile, $arch, 'install', $installdir );
        }
    }
    return '';
}

sub web_provision {
    my ( $request, $callback, $sub_req ) = @_;
    my $nodes     = $request->{arg}->[1];
    my $imageName = $request->{arg}->[2];
    my ( $arch, $inic, $pnic, $master, $tftp, $nfs ) = split( /,/, $request->{arg}->[3] );
    my $line = '';
    my %imageattr;
    my $retinfo = xCAT::Utils->runcmd( "lsdef -t osimage -l $imageName", -1, 1 );
    my $installdir = xCAT::TableUtils->getInstallDir();

    # Parse output, get the OS name and type
    foreach $line (@$retinfo) {
        if ( $line =~ /(\w+)=(\S*)/ ) {
            $imageattr{$1} = $2;
        }
    }

    # Check the output
    unless ( $imageattr{'osname'} ) {
        web_infomsg( "Image infomation error. Check the image first.\nprovision stop.", $callback );
        return;
    }

    if ( 'install' eq $imageattr{'provmethod'} ) {
        my $prepareinfo = web_provision_preinstall( $imageattr{'osvers'}, $imageattr{'profile'}, $arch, $installdir, $request->{arg}->[4] );
        if ($prepareinfo) {
            web_infomsg( "$prepareinfo \nprovision stop.", $callback );
            return;
        }
    }

    if ( $imageattr{'osname'} =~ /aix/i ) {
        web_provisionaix( $nodes, $imageName, $imageattr{'nimtype'}, $inic, $pnic, $master, $tftp, $nfs, $callback );
    } else {
        web_provisionlinux(
            $nodes,                $arch,
            $imageattr{'osvers'},  $imageattr{'provmethod'},
            $imageattr{'profile'}, $inic,
            $pnic,                 $master,
            $tftp,                 $nfs,
            $callback
        );
    }
}

sub web_provisionlinux {
    my ($nodes, $arch, $os, $provmethod, $profile, $inic, $pnic, $master, $tftp, $nfs, $callback) = @_;
    my $outputMessage = '';
    my $retvalue      = 0;
    my $netboot       = '';
    
    if ( $arch =~ /ppc/i ) {
        $netboot = 'yaboot';
    } elsif ( $arch =~ /x.*86/i ) {
        $netboot = 'xnba';
    }
    
    $outputMessage =
        "Do provison : $nodes \n"
      . " Arch:$arch\n OS:$os\n Provision:$provmethod\n Profile:$profile\n Install NIC:$inic\n Primary NIC:$pnic\n"
      . " xCAT Master:$master\n TFTP Server:$tftp\n NFS Server:$nfs\n Netboot:$netboot\n";

    web_infomsg( $outputMessage, $callback );

    # Change the node attribute
    my $cmd = "chdef -t node -o $nodes arch=$arch os=$os provmethod=$provmethod profile=$profile installnic=$inic tftpserver=$tftp nfsserver=$nfs netboot=$netboot" . " xcatmaster=$master primarynic=$pnic";
    web_runcmd( $cmd, $callback );
    if ($::RUNCMD_RC) {
        web_infomsg( "Configure nodes' attributes error.\nProvision stop.", $callback );
        return;
    }

    $cmd = "makedhcp $nodes";
    web_runcmd( $cmd, $callback );
    if ($::RUNCMD_RC) {
        web_infomsg( "Make DHCP error.\nProvision stop.", $callback );
        return;
    }

    # Restart DHCP
    $cmd = "service dhcpd restart";
    web_runcmd( $cmd, $callback );

    # Conserver
    $cmd = "makeconservercf $nodes";
    web_runcmd( $cmd, $callback );
    if ($::RUNCMD_RC) {
        web_infomsg( "Configure conserver error.\nProvision stop.", $callback );
        return;
    }

    # For system x, should configure boot sequence first
    if ( $arch =~ /x.*86/i ) {
        $cmd = "rbootseq $nodes net,hd";
        web_runcmd( $cmd, $callback );
        if ($::RUNCMD_RC) {
            web_infomsg( "Set boot sequence error.\nProvision stop.",
                $callback );
            return;
        }
    }

    # Nodeset
    $cmd = "nodeset $nodes $provmethod";
    web_runcmd( $cmd, $callback );
    if ($::RUNCMD_RC) { web_infomsg( "Set nodes provision method error.\nprovision stop.", $callback );
        return;
    }

    # Reboot the node fro provision
    if ( $arch =~ /ppc/i ) {
        $cmd = "rnetboot $nodes";
    } else {
        $cmd = "rpower $nodes boot";
    }
    
    web_runcmd( $cmd, $callback );
    if ($::RUNCMD_RC) {
        web_infomsg( "Boot nodes error.\nProvision stop.", $callback );
        return;
    }

    # Provision complete
    web_infomsg("Provision on $nodes success.\nProvision stop.");
}

sub web_provisionaix {
    my (
        $nodes,  $imagename, $nimtype, $inic, $pnic,
        $master, $tftp,      $nfs,     $callback
      ) = @_;
    my $outputMessage = '';
    my $retinfo;
    my %nimhash;
    my $line;
    my @updatenodes;
    my @addnodes;
    my $cmd = '';

    # Set attributes
    $cmd = "chdef -t node -o $nodes installnic=$inic tftpserver=$tftp nfsserver=$nfs xcatmaster=$master primarynic=$pnic";
    web_runcmd( $cmd, $callback );
    if ($::RUNCMD_RC) {
        web_infomsg( "Change nodes' attributes error.\nprovision stop.", $callback );
        return;
    }

    # Get all NIM resource to filter nodes
    $retinfo = xCAT::Utils->runcmd( "lsnim -c machines", -1, 1 );
    foreach $line (@$retinfo) {
        if ( $line =~ /(\S+)\s+\S+/ ) {
            $nimhash{$1} = 1;
        }
    }

    foreach my $node ( split( /,/, $nodes ) ) {
        if ( $nimhash{$node} ) {
            push( @updatenodes, $node );
        } else {
            push( @addnodes, $node );
        }
    }

    if ( 0 < scalar(@addnodes) ) {
        $cmd = "xcat2nim -t node -o " . join( ",", @addnodes );
        web_runcmd( $cmd, $callback );
        if ($::RUNCMD_RC) {
            web_infomsg( "xcat2nim command error.\nprovision stop.", $callback );
            return;
        }
    }

    if ( 0 < scalar(@updatenodes) ) {
        $cmd = "xcat2nim -u -t node -o " . join( ",", @updatenodes );
        web_runcmd( $cmd, $callback );
        if ($::RUNCMD_RC) {
            web_infomsg( "xcat2nim command error.\nprovision stop.", $callback );
            return;
        }
    }

    $cmd = "makeconservercf $nodes";
    web_runcmd( $cmd, $callback );
    if ($::RUNCMD_RC) {
        web_infomsg( "Configure conserver error.\nprovision stop.", $callback );
        return;
    }

    if ( $nimtype =~ /diskless/ ) {
        $cmd = "mkdsklsnode -i $imagename $nodes";
    } else {
        $cmd = "nimnodeset -i $imagename $nodes";
    }
    
    web_runcmd( $cmd, $callback );
    if ($::RUNCMD_RC) {
        web_infomsg( "Set node install method error.\nprovision stop.", $callback );
        return;
    }

    $cmd = "rnetboot $nodes";
    web_runcmd( $cmd, $callback );
    if ($::RUNCMD_RC) {
        web_infomsg( "Reboot nodes error.\nprovision stop.", $callback );
        return;
    }

    web_infomsg("Provision on $nodes success.\nprovision stop.");
}

sub web_runcmd {
    my $cmd      = shift;
    my $callback = shift;
    my $showstr  = "\n" . $cmd . "\n";
    
    web_infomsg( $showstr, $callback );
    
    my $retvalue = xCAT::Utils->runcmd( $cmd, -1, 1 );
    $showstr = join( "\n", @$retvalue );
    $showstr .= "\n";
    
    web_infomsg( $showstr, $callback );
}

sub web_infomsg {
    my $msg      = shift;
    my $callback = shift;
    my %rsp;
    
    push @{ $rsp{info} }, $msg;
    xCAT::MsgUtils->message( 'I', \%rsp, $callback );
    return;
}

sub web_summary {
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

    if ( defined($groupName) ) {
        @nodes = xCAT::NodeRange::noderange($groupName);
    } else {
        @nodes = xCAT::DBobjUtils->getObjectsOfType('node');
    }

    $nodetypeTab = xCAT::Table->new('nodetype');
    unless ($nodetypeTab) {
        return;
    }

    $nodelistTab = xCAT::Table->new('nodelist');
    unless ($nodelistTab) {
        return;
    }

    $attrs = $nodetypeTab->getNodesAttribs( \@nodes, [ 'os', 'arch', 'provmethod', 'nodetype' ] );
    unless ($attrs) {
        return;
    }

    while ( my ( $key, $value ) = each( %{$attrs} ) ) {
        web_attrcount( $value->[0]->{'os'},          \%oshash );
        web_attrcount( $value->[0]->{'arch'},        \%archhash );
        web_attrcount( $value->[0]->{'provmethod'},, \%provhash );
        web_attrcount( $value->[0]->{'nodetype'},,   \%typehash );
    }

    $attrs = $nodelistTab->getNodesAttribs( \@nodes, ['status'] );
    while ( my ( $key, $value ) = each( %{$attrs} ) ) {
        web_attrcount( $value->[0]->{'status'}, \%statushash );
    }

    # Status
    $temp = '';
    while ( my ( $key, $value ) = each(%statushash) ) {
        $temp .= ( $key . ':' . $value . ';' );
    }
    $temp = substr( $temp, 0, -1 );
    push( @{ $retHash->{'data'} }, 'Status=' . $temp );

    # OS
    $temp = '';
    while ( my ( $key, $value ) = each(%oshash) ) {
        $temp .= ( $key . ':' . $value . ';' );
    }
    $temp = substr( $temp, 0, -1 );
    push( @{ $retHash->{'data'} }, 'Operating System=' . $temp );

    # Architecture
    $temp = '';
    while ( my ( $key, $value ) = each(%archhash) ) {
        $temp .= ( $key . ':' . $value . ';' );
    }
    $temp = substr( $temp, 0, -1 );
    push( @{ $retHash->{'data'} }, 'Architecture=' . $temp );

    # Provision method
    $temp = '';
    while ( my ( $key, $value ) = each(%provhash) ) {
        $temp .= ( $key . ':' . $value . ';' );
    }
    $temp = substr( $temp, 0, -1 );
    push( @{ $retHash->{'data'} }, 'Provision Method=' . $temp );

    # Nodetype
    $temp = '';
    while ( my ( $key, $value ) = each(%typehash) ) {
        $temp .= ( $key . ':' . $value . ';' );
    }
    $temp = substr( $temp, 0, -1 );
    push( @{ $retHash->{'data'} }, 'Node Type=' . $temp );

    # Return data
    $callback->($retHash);
}

sub web_attrcount {
    my ( $key, $container ) = @_;
    unless ( defined($key) ) {
        $key = 'unknown';
    }

    if ( $container->{$key} ) {
        $container->{$key}++;
    } else {
        $container->{$key} = 1;
    }
}

sub web_rinstall {
    my ( $request, $callback, $sub_req ) = @_;
    my $os      = $request->{arg}->[1];
    my $profile = $request->{arg}->[2];
    my $arch    = $request->{arg}->[3];
    my $node    = $request->{arg}->[4];

    # Begin installation
    my $out = `rinstall -o $os -p $profile -a $arch $node`;

    $callback->( { data => $out } );
}

sub web_addnode {
    my ( $request, $callback, $sub_req ) = @_;
    my $nodetype  = $request->{arg}->[1];
    my @tempArray = split( ',', $request->{arg}->[2] );

    my $hcpname = shift(@tempArray);
    if ( 'node' ne $nodetype ) {
        my $username = $tempArray[0];
        my $passwd   = $tempArray[1];
        my $ip       = $tempArray[2];
        `/bin/grep '$hcpname' /etc/hosts`;
        if ($?) {
            open( OUTPUTFILE, '>>/etc/hosts' );
            print OUTPUTFILE "$ip $hcpname\n";
            close(OUTPUTFILE);
        }
        
        if ( 'hmc' eq $nodetype ) {
            `/opt/xcat/bin/chdef -t node -o $hcpname username=$username password=$passwd mgt=hmc nodetype=$nodetype ip=$ip groups=all`;
        } else {
            `/opt/xcat/bin/chdef -t node -o $hcpname username=$username password=$passwd mgt=blade mpa=$hcpname nodetype=$nodetype id=0 groups=mm,all`;
        }
        return;
    }

    my %temphash;
    my $writeflag = 0;
    my $line      = '';

    # Save all nodes into a hash
    foreach (@tempArray) {
        $temphash{$_} = 1;
    }
    
    for ( my $i = 0 ; $i < scalar(@tempArray) ; $i = $i + 2 ) {
        $temphash{ $tempArray[$i] } = $tempArray[ $i + 1 ];
    }
    
    `/opt/xcat/bin/rscan $hcpname -z > /tmp/rscanall.tmp`;

    unless ( -e '/tmp/rscanall.tmp' ) {
        return;
    }

    open( INPUTFILE,  '/tmp/rscanall.tmp' );
    open( OUTPUTFILE, '>/tmp/webrscan.tmp' );
    while ( $line = <INPUTFILE> ) {
        if ( $line =~ /(\S+):$/ ) {
            if ( $temphash{$1} ) {
                $writeflag = 1;
                print OUTPUTFILE $temphash{$1} . ":\n";
            } else {
                $writeflag = 0;
            }
        } else {
            if ($writeflag) {
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

sub web_graphinfo {
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
    my $pretstr     = '';
    my $bladeretstr = '';
    my $xretstr     = '';
    my $unsupretstr = '';
    my $missretstr  = '';

    @nodes = xCAT::DBobjUtils->getObjectsOfType('node');

    $nodetypeTab = xCAT::Table->new('nodetype');
    unless ($nodetypeTab) {
        return;
    }

    # Get all nodetype and seperate nodes into different group
    $result = $nodetypeTab->getNodesAttribs( \@nodes, ['nodetype'] );
    while ( my ( $key, $value ) = each(%$result) ) {
        my $temptype = $value->[0]->{'nodetype'};
        if ( $temptype =~ /(ppc|lpar|cec|frame)/i ) {
            push( @parray, $key );
        } elsif ( $temptype =~ /blade/i ) {
            push( @bladearray, $key );
        } elsif ( $temptype =~ /osi/i ) {
            push( @xarray, $key );
        } else {
            push( @unsupportarray, $key );
        }
    }
    $nodetypeTab->close();

    # Get all information for System p node
    if ( scalar(@parray) > 0 ) {
        my $ppctab = xCAT::Table->new('ppc');

        $result = $ppctab->getNodesAttribs( \@parray, ['parent'] );
        my $typehash = xCAT::DBobjUtils->getnodetype( \@parray );
        foreach (@parray) {
            my $value = $result->{$_};
            if ( $value->[0] ) {
                $phash{$_} = $$typehash{$_} . ':' . $value->[0]->{'parent'} . ':';
            } else {
                $phash{$_} = $$typehash{$_} . '::';
            }
        }
        $ppctab->close();

        undef @parray;
        @parray = keys %phash;
    }
    if ( scalar(@parray) > 0 ) {
        # mtm
        my $vpdtab = xCAT::Table->new('vpd');
        $result = $vpdtab->getNodesAttribs( \@parray, ['mtm'] );
        foreach (@parray) {
            my $value = $result->{$_};
            $phash{$_} = $phash{$_} . $value->[0]->{'mtm'} . ':';
        }
        $vpdtab->close();

        # Status
        my $nodelisttab = xCAT::Table->new('nodelist');
        $result = $nodelisttab->getNodesAttribs( \@parray, ['status'] );
        foreach (@parray) {
            my $value = $result->{$_};
            $phash{$_} = $phash{$_} . $value->[0]->{'status'};
        }
        $nodelisttab->close();

        while ( my ( $key, $value ) = each(%phash) ) {
            $pretstr = $pretstr . $key . ':' . $value . ';';
        }
    }

    # Get all information for blade node
    if ( scalar(@bladearray) > 0 ) {
        my $mptab = xCAT::Table->new('mp');
        $result = $mptab->getNodesAttribs( \@bladearray, [ 'mpa', 'id' ] );
        foreach (@bladearray) {
            my $value = $result->{$_};
            if ( $value->[0]->{'mpa'} ) {
                $bladehash{$_} = 'blade:' . $value->[0]->{'mpa'} . ':' . $value->[0]->{'id'} . ':';
            } else {
                push( @missinfoarray, $_ );
            }
        }
        
        $mptab->close();

        undef @bladearray;
        @bladearray = keys %bladehash;
    }
    
    if ( scalar(@bladearray) > 0 ) {
        # Status
        my $nodelisttab = xCAT::Table->new('nodelist');
        $result = $nodelisttab->getNodesAttribs( \@bladearray, ['status'] );
        foreach (@bladearray) {
            my $value = $result->{$_};
            $bladehash{$_} = $bladehash{$_} . $value->[0]->{'status'};
        }
        $nodelisttab->close();
        while ( my ( $key, $value ) = each(%bladehash) ) {
            $bladeretstr = $bladeretstr . $key . ':' . $value . ';';
        }
    }

    # Get all information for System x node
    if ( scalar(@xarray) > 0 ) {
        # Rack and unit
        my $nodepostab = xCAT::Table->new('nodepos');
        $result = $nodepostab->getNodesAttribs( \@xarray, [ 'rack', 'u' ] );
        foreach (@xarray) {
            my $value = $result->{$_};
            if ( $value->[0]->{'rack'} ) {
                $xhash{$_} = 'systemx:' . $value->[0]->{'rack'} . ':' . $value->[0]->{'u'} . ':';
            } else {
                push( @missinfoarray, $_ );
            }
        }
        
        $nodepostab->close();

        undef @xarray;
        @xarray = keys %xhash;
    }
    
    if ( scalar(@xarray) > 0 ) {
        # mtm
        my $vpdtab = xCAT::Table->new('vpd');
        $result = $vpdtab->getNodesAttribs( \@xarray, ['mtm'] );
        foreach (@xarray) {
            my $value = $result->{$_};
            $xhash{$_} = $xhash{$_} . $value->[0]->{'mtm'} . ':';
        }
        $vpdtab->close();

        # Status
        my $nodelisttab = xCAT::Table->new('nodelist');
        $result = $nodelisttab->getNodesAttribs( \@xarray, ['status'] );
        foreach (@xarray) {
            my $value = $result->{$_};
            $xhash{$_} = $xhash{$_} . $value->[0]->{'status'};
        }
        
        while ( my ( $key, $value ) = each(%xhash) ) {
            $xretstr = $xretstr . $key . ':' . $value . ';';
        }
    }

    @missinfoarray = (@missinfoarray, @unsupportarray);
    foreach (@missinfoarray) {
        $missretstr = $missretstr . $_ . ':linux:other;';
    }
    
    # Combine all information into a string
    my $retstr = $pretstr . $bladeretstr . $xretstr . $missretstr;
    if ($retstr) {
        $retstr = substr( $retstr, 0, -1 );
    }

    $callback->( { data => $retstr } );
}

sub web_getdefaultuserentry {

    # Get default user entry
    my ( $request, $callback, $sub_req ) = @_;

    # Get profile
    my $profile = $request->{arg}->[1];

    if ( !$profile ) {
        $profile = 'default';
    }

    my $entry;
    if ( !(`test -e /var/opt/xcat/profiles/$profile.direct && echo 'File exists'`) ) {
        $entry = `cat /var/opt/xcat/profiles/default.direct`;
    } else {
        $entry = `cat /var/opt/xcat/profiles/$profile.direct`;
    }

    $callback->( { data => $entry } );
}

sub web_passwd() {
    my ( $request, $callback, $sub_req ) = @_;

    # Get current and new passwords
    my $user = $request->{arg}->[1];
    my $password = $request->{arg}->[2];

    # Generate encrypted password
    my $random    = rand(10000000);
    my $encrypted = `perl -e "print crypt($password, $random)"`;

    # Save in xCAT passwd table
    `/opt/xcat/sbin/chtab username=$user passwd.key=xcat passwd.password=$encrypted`;

    my $info = "User password successfully updated";
    $callback->( { info => $info } );
    return;
}

sub web_policy() {
    my ( $request, $callback, $sub_req ) = @_;

    # Get user attributes
    my $priority = $request->{arg}->[1];
    my $args = $request->{arg}->[2];

    # Save in xCAT passwd and policy tables
    my $out = `/opt/xcat/sbin/chtab priority=$priority $args`;

    my $info = "User policy successfully updated";
    $callback->( { info => $info } );
    return;
}

sub web_deleteuser() {
    my ( $request, $callback, $sub_req ) = @_;

    # Get user attributes
    my $user  = $request->{arg}->[1];
    my @users = split( ',', $user );

    # Delete user from xCAT passwd and policy tables
    foreach (@users) {
        `/opt/xcat/sbin/chtab -d username=$_ passwd`;
        `/opt/xcat/sbin/chtab -d name=$_ policy`;
    }

    my $info = "User successfully deleted";
    $callback->( { info => $info } );
    return;
}

sub web_getzdiskinfo() {

    # Get default disk info
    my ( $request, $callback, $sub_req ) = @_;

    # Get profile
    my $profile = $request->{arg}->[1];

    if ( !$profile ) {
        $profile = 'default';
    }

    my $info;
    if ( !(`test -e /var/opt/xcat/profiles/$profile.conf && echo 'File exists'`)) {
        $info = `cat /var/opt/xcat/profiles/default.conf`;
    } else {
        $info = `cat /var/opt/xcat/profiles/$profile.conf`;
    }

    $callback->( { info => $info } );
}

sub web_mkzprofile() {

    # Create default profile
    my ( $request, $callback, $sub_req ) = @_;

    # Get profile
    my $profile = $request->{arg}->[1];
    my $pool    = $request->{arg}->[2];
    my $size    = $request->{arg}->[3];

    # Create profile under /var/opt/xcat/profiles
    `mkdir -p /var/opt/xcat/profiles`;
    my $var = "";
`echo "# Configuration for virtual machines" > /var/opt/xcat/profiles/$profile.conf`;
    $var = $profile . "_diskpool";
    `echo "$var=$pool" >> /var/opt/xcat/profiles/$profile.conf`;
    $var = $profile . "_eckd_size";
    `echo "$var=$size" >> /var/opt/xcat/profiles/$profile.conf`;

    # Move directory entry into /var/opt/xcat/profiles from /var/tmp    
    `mv /var/tmp/$profile.direct /var/opt/xcat/profiles`;

    my $info = "Profile successfully created/updated";
    $callback->( { info => $info } );
}

sub web_rmzprofile() {

    # Delete default profile
    my ( $request, $callback, $sub_req ) = @_;

    # Get profile
    my $profile  = $request->{arg}->[1];
    my @profiles = split( ',', $profile );

    # Delete profile under /var/opt/xcat/profiles
    foreach (@profiles) {
        `rm /var/opt/xcat/profiles/$_.conf`;
        `rm /var/opt/xcat/profiles/$_.direct`;
    }

    my $info = "Profile successfully deleted";
    $callback->( { info => $info } );
}

sub web_mkippool() {

    # Create group IP pool
    my ( $request, $callback, $sub_req ) = @_;

    # Get profile
    my $group = $request->{arg}->[1];

    # Move directory entry into /var/opt/xcat/ippool from /var/tmp
    `mkdir -p /var/opt/xcat/ippool`;
    `mv /var/tmp/$group.pool /var/opt/xcat/ippool`;

    my $info = "IP pool successfully created/updated";
    $callback->( { info => $info } );
}

sub web_rmippool() {

    # Delete group IP pool
    my ( $request, $callback, $sub_req ) = @_;

    # Get profile
    my $group  = $request->{arg}->[1];
    my @groups = split( ',', $group );

    # Delete IP pool under /var/opt/xcat/ippool
    foreach (@groups) {
        `rm -rf /var/opt/xcat/ippool/$_.pool`;
    }

    my $info = "IP pool successfully deleted";
    $callback->( { info => $info } );
}

sub web_lsippool() {

    # List IP pool
    my ( $request, $callback, $sub_req ) = @_;

    # Get profile
    my $group  = $request->{arg}->[1];
    
    # IP pool contained in /var/opt/xcat/ippool where a file exists per group
    my $entries;
    if ( !(`test -e /var/opt/xcat/ippool/$group.pool && echo Exists`) ) {
        $entries = "No IP pool found!";
    } else {
    	# List IP pool under /var/opt/xcat/ippool   
        $entries = `cat /var/opt/xcat/ippool/$group.pool`;
    }
    
    $callback->( { info => $entries } );
}

sub web_updateosimage() {

    # Add OS image to xCAT table
    my ( $request, $callback, $sub_req ) = @_;

    my $name       = $request->{arg}->[1];
    my $type       = $request->{arg}->[2];
    my $arch       = $request->{arg}->[3];
    my $osName     = $request->{arg}->[4];
    my $osVersion  = $request->{arg}->[5];
    my $profile    = $request->{arg}->[6];
    my $provMethod = $request->{arg}->[7];
    my $comments   = $request->{arg}->[8];

    `/opt/xcat/sbin/chtab -d imagename=$name osimage`;
    `/opt/xcat/sbin/chtab osimage.imagename=$name osimage.imagetype=$type osimage.osarch=$arch osimage.osname=$osName osimage.osvers=$osVersion osimage.profile=$profile osimage.provmethod=$provMethod osimage.comments=$comments`;
    my $info = "Image successfully updated";
    $callback->( { info => $info } );
}

sub web_rmosimage() {

    # Delete OS image from xCAT table
    my ( $request, $callback, $sub_req ) = @_;

    my $name  = $request->{arg}->[1];
    my @names = split( ',', $name );

    # Delete user from xCAT passwd and policy tables
    foreach (@names) {
        `/opt/xcat/sbin/chtab -d imagename=$_ osimage`;
    }

    my $info = "Image successfully deleted";
    $callback->( { info => $info } );
}

sub web_updategroup() {

    # Add group to xCAT table
    my ( $request, $callback, $sub_req ) = @_;

    my $name = $request->{arg}->[1];
    my $ip   = $request->{arg}->[2];
    $ip =~ s/'//g;

    my $hostnames = $request->{arg}->[3];
    $hostnames =~ s/'//g;

    my $comments = $request->{arg}->[4];
    $comments =~ s/'//g;

    `/opt/xcat/sbin/chtab -d node=$name hosts`;
    `/opt/xcat/sbin/chtab node=$name hosts.ip="$ip" hosts.hostnames="$hostnames" hosts.comments="$comments"`;

    my $info = "Group successfully updated";
    $callback->( { info => $info } );
}

sub web_rmgroup() {

    # Delete group from xCAT table
    my ( $request, $callback, $sub_req ) = @_;

    my $name  = $request->{arg}->[1];
    my @names = split( ',', $name );

    # Delete user from xCAT passwd and policy tables
    foreach (@names) {
        `/opt/xcat/sbin/chtab -d node=$_ hosts`;
        `rm -rf /var/opt/xcat/ippool/$_.pool`;
    }

    my $info = "Group successfully deleted";
    $callback->( { info => $info } );
}

sub web_framesetup() {
    my ( $request, $callback, $sub_req ) = @_;
    my $adminpasswd = $request->{arg}->[1];
    my $generalpasswd = $request->{arg}->[2];
    my $hmcpasswd = $request->{arg}->[3];
    my $configphase = $request->{arg}->[4];
    my @tempnode = 'bpa';
    
    if ($configphase == 1){
        #run makedhcp
        xCAT::Utils->runcmd('makedhcp bpa', -1, 1);
        sleep(10);
        #run makehosts
        xCAT::Utils->runcmd('makehosts bpa', -1, 1);
        $callback->( { info => 'FRAMEs DHCP, DNS configured.' } );
    } elsif ($configphase == 2){
        #run chtab command
        xCAT::Utils->runcmd('chtab key=bpa,username=HMC passwd.password=' . $hmcpasswd, -1, 1);
        xCAT::Utils->runcmd('chtab key=bpa,username=admin passwd.password=' . $adminpasswd, -1, 1);
        xCAT::Utils->runcmd('chtab key=bpa,username=general passwd.password=' . $generalpasswd, -1, 1);
    
        #mkhwconn
        xCAT::Utils->runcmd('mkhwconn frame -t', -1, 1);
        #rspconfig
        xCAT::Utils->runcmd('rspconfig frame general_passwd=general,' . $generalpasswd, -1, 1);
        xCAT::Utils->runcmd('rspconfig frame admin_passwd=admin,' . $adminpasswd, -1, 1);
        xCAT::Utils->runcmd('rspconfig frame HMC_passwd=,' . $hmcpasswd, -1, 1);

        $callback->( { info => 'Hardware connection and configure password created.' } );
    }
}

sub web_cecsetup() {
    my ( $request, $callback, $sub_req ) = @_;
    my $adminpasswd = $request->{arg}->[1];
    my $generalpasswd = $request->{arg}->[2];
    my $hmcpasswd = $request->{arg}->[3];
    my $configphase = $request->{arg}->[4];
    my @tempnode = 'bpa';

    if ($configphase == 1){
        # Run makedhcp
        xCAT::Utils->runcmd('makedhcp fsp', -1, 1);
        sleep(10);
        # Run makehosts
        xCAT::Utils->runcmd('makehosts fsp', -1, 1);
        $callback->( { info => 'CEC DHCP, DNS configured.' } );
    } elsif ($configphase == 2){
        # Run chtab command
        xCAT::Utils->runcmd('chtab key=fsp,username=HMC passwd.password=' . $hmcpasswd, -1, 1);
        xCAT::Utils->runcmd('chtab key=fsp,username=admin passwd.password=' . $adminpasswd, -1, 1);
        xCAT::Utils->runcmd('chtab key=fsp,username=general passwd.password=' . $generalpasswd, -1, 1);
        # Run mkhwconn
        xCAT::Utils->runcmd('mkhwconn cec -t', -1, 1);
        # Run rspconfig
        xCAT::Utils->runcmd('rspconfig cec general_passwd=general,' . $generalpasswd, -1, 1);
        xCAT::Utils->runcmd('rspconfig cec admin_passwd=admin,' . $adminpasswd, -1, 1);
        xCAT::Utils->runcmd('rspconfig cec HMC_passwd=,' . $hmcpasswd, -1, 1);

        $callback->( { info => 'Hardware connection and configure password created.' } );
    }
}

1;
