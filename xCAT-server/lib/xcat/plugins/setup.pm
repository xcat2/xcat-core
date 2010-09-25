#!/usr/bin/env perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

#####################################################
#
# Reads the cluster configuration file and primes the database in prep
# for HW discovery and node deployment.
#
# Preconditions before running the xcatsetup cmd:
# - 
#
# Limitations on the values in the config file:
# - hostname ranges must have simple <alphachars><integer> format
# - IP address incrementing for ranges must currently be confined to the last field
# - the supernode-list file must contain all frames and the frame nodenames must sort correctly
# - do not yet support redundant bpcs or fsps
#
#####################################################
package xCAT_plugin::setup;

use strict;
#use warnings;
use xCAT::NodeRange;
use xCAT::Schema;
use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use Data::Dumper;
use xCAT::DBobjUtils;

my $CALLBACK;
my %STANZAS;

sub handled_commands {
    return( { xcatsetup => "setup" } );
}

sub process_request
{
    use Getopt::Long;
    Getopt::Long::Configure("bundling");
    #Getopt::Long::Configure("pass_through");
    Getopt::Long::Configure("no_pass_through");

    my $request  = shift;
    $CALLBACK = shift;
    #my $nodes    = $request->{node};
    #my $command  = $request->{command}->[0];
    my $args     = $request->{arg};
    my $VERSION;
    my $HELP;
    
    my $setup_usage = sub {
    	my $exitcode = shift @_;
    	my %rsp;
    	push @{$rsp{data}}, "Usage: xcatsetup [-v|--version] [-?|-h|--help] <cluster-config-file>";
        if ($exitcode) { $rsp{errorcode} = $exitcode; }
        $CALLBACK->(\%rsp);
    };

	# Process the cmd line args
    if ($args) { @ARGV = @{$args}; }
    else { @ARGV = (); }
    if (!GetOptions('h|?|help'  => \$HELP, 'v|version' => \$VERSION) ) { $setup_usage->(1); return; }

    if ($HELP || scalar(@ARGV)==0) { $setup_usage->(0); return; }

    if ($VERSION) {
        my %rsp;
        my $version = xCAT::Utils->Version();
        $rsp{data}->[0] = $version;
        $CALLBACK->(\%rsp);
        return;
    }
    
    my $input;
    my $filename = fullpath($ARGV[0], $request->{cwd}->[0]);
    if (!open($input, $filename)) {
    	errormsg("Can not open file $filename.", 2);
        return;
    }
    
    # Parse the config file
    my $success = readFileInput($input);
    close($input);
    if (!$success) { return; }
    
    # Write the db entries
    writedb($request->{cwd}->[0]);
}


sub readFileInput {
    my $input = shift;

	my $l;
	my $stanza;
	my $linenum = 0;
    while ($l=<$input>) {
    	$linenum++;

        # skip blank and comment lines
        next if ( $l =~ /^\s*$/ || $l =~ /^\s*#/ );

        # process a real line
        if ( $l =~ /^\s*(\S+)\s*=\s*(.*)\s*$/ ) {
            my $attr = $1;
            my $val  = $2;
            #$attr =~ s/^\s*//;       # Remove any leading whitespace - already did that
            #$attr =~ s/\s*$//;       # Remove any trailing whitespace - already did that
            $attr =~ tr/A-Z/a-z/;    # Convert to lowercase
            #$val  =~ s/^\s*//;
            #$val  =~ s/\s*$//;

            # set the value in the hash for this stanza
            if (!defined($stanza)) { errormsg("expected stanza header at line $linenum.", 3); return; }
            $STANZAS{$stanza}->{$attr} = $val;
        }
        
        elsif ( $l =~ /^\s*(\S+)\s*:\s*$/) {
        	$stanza = $1;
        }
        
        else {
        	errormsg("syntax error on line $linenum.", 3);
        	return 0;
        }
    }    # end while - go to next line

    return 1;
}

# A few global variables for common tables that a lot of functions need
my %tables = ('site' => 0,
			'nodelist' => 0,
			'hosts' => 0,
			'ppc' => 0,
			'nodetype' => 0,
			'nodehm' => 0,
			'noderes' => 0,
			);

sub writedb {
	my $cwd = shift;		# the current dir from the request
	#todo: add syntax checking for input values
	
	# Open some common tables that several of the stanzas need
	foreach my $tab (keys %tables) {
		$tables{$tab} = xCAT::Table->new($tab, -create=>1);
		if (!$tables{$tab}) { errormsg("Can not open $tab table in database.  Exiting config file processing.", 3); return; }
	}
	
	# Write site table attrs (hash key=xcat-site)
	my $domain = $STANZAS{'xcat-site'}->{domain};
	if ($domain) { writesite($domain); }
	
	# Write service LAN info (hash key=xcat-service-lan)
	#using hostname-range, write: nodelist.node, nodelist.groups, switches.switch
	#using hostname-range and starting-ip, write regex for: hosts.node, hosts.ip
	#using num-ports-per-switch, switch-port-prefix, switch-port-sequence, write: switch.node, switch.switch, switch.port
	#using dhcp-dynamic-range, write: networks.dynamicrange for the service network.
    # * Note: for AIX the permanent IPs for HMCs/FSPs/BPAs (specified in later stanzas) should be within this dynamic range, at the high end. For linux the permanent IPs should be outside this dynamic range.
    # * use the first IP in the specified dynamic range to locate the service network in the networks table 
	#on aix stop bootp - see section 2.2.1.1 of p hw mgmt doc
	#run makedhcp -n
	
	# Write HMC info (hash key=xcat-hmcs)
	my $hmcrange = $STANZAS{'xcat-hmcs'}->{'hostname-range'};
	if ($hmcrange) { writehmc($hmcrange); }
	
	# Write frame info (hash key=xcat-frames)
	my $framerange = $STANZAS{'xcat-frames'}->{'hostname-range'};
	if ($framerange) { writeframe($framerange, $cwd); }
	
	# Write CEC info (hash key=xcat-cecs)
	my $cecrange = $STANZAS{'xcat-cecs'}->{'hostname-range'};
	if ($cecrange) { writecec($cecrange, $cwd); }
	
	# Write BB info (hash key=xcat-building-blocks)
	my $framesperbb = $STANZAS{'xcat-building-blocks'}->{'num-frames-per-bb'};
	if ($framesperbb) { writebb($framesperbb); }
	
	# Write lpar info in ppc, noderes, servicenode
	my $snrange = $STANZAS{'xcat-lpars'}->{'service-node-hostname-range'};
	if ($snrange) { writesn($snrange); }
	my $storagerange = $STANZAS{'xcat-lpars'}->{'storage-node-hostname-range'};
	if ($storagerange) { writestorage($storagerange); }
	my $computerange = $STANZAS{'xcat-lpars'}->{'compute-node-hostname-range'};
	if ($computerange) { writecompute($computerange); }
	
	# Close all the open common tables to finish up
	foreach my $tab (keys %tables) {
		if ($tables{$tab}) { $tables{$tab}->close(); }
	}
	
	# Temporarily write out the contents of the hash
	#foreach my $k (keys %STANZAS) {
	#	my $stanza = $STANZAS{$k};
	#	print "$k\n";
	#	foreach my $attr (keys %$stanza) {
	#		my $val = $$stanza{$attr};
	#		print "  $attr=$val\n";
	#	}
	#}
}


sub writesite {
	#write: domain, nameservers=<MN>
	my $domain = shift;
	infomsg('Defining site attributes...');
	# set the domain specified in the config file
	#print "domain=$domain\n";
	$tables{'site'}->setAttribs({key => 'domain'}, {value => $domain});
		
	# set the site.nameservers value to the site.master value
	my $ref = $tables{'site'}->getAttribs({key => 'master'}, 'value');
	if ($ref) {
		$tables{'site'}->setAttribs({key => 'nameservers'}, {value => $ref->{value} });
	}
	$tables{'site'}->close();
	
	#todo: put dynamic range in networks table
	#todo: set site.dhcpinterfaces
}


sub writehmc {
	#using hostname-range, write: nodelist.node, nodelist.groups
	my $hmcrange = shift;
	infomsg('Defining HMCs...');
	my $nodes = [noderange($hmcrange, 0)];
	my ($hmcstartnum) = $$nodes[0] =~/^\D+(\d+)$/;		# save this value for later
	#print "$$nodes[0], $hmcstartnum\n";
	if (scalar(@$nodes)) {
		#my %nodehash;
		#foreach my $n (@$nodes) { print "n=$n\n"; $nodehash{$n} = { node => $n, groups => 'hmc,all' }; }
		$tables{'nodelist'}->setNodesAttribs($nodes, { groups => 'hmc,all' });
	}
	
	#using hostname-range and starting-ip, write regex for: hosts.node, hosts.ip
	my $hmcstartip = $STANZAS{'xcat-hmcs'}->{'starting-ip'};
	if ($hmcstartip) {
		my ($ipbase, $ipstart) = $hmcstartip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
		# take the number from the nodename, and as it increases, increase the ip addr
		my $regex = '|\D+(\d+)|' . "$ipbase.($ipstart+" . '$1' . "-$hmcstartnum)|";
		$tables{'hosts'}->setNodeAttribs('hmc', {ip => $regex});
	}
	
	#using hostname-range, write regex for: ppc.node, nodetype.nodetype 
	$tables{'ppc'}->setNodeAttribs('hmc', {comments => 'hmc'});
	$tables{'nodetype'}->setNodeAttribs('hmc', {nodetype => 'hmc'});
}


sub writeframe {
	# write hostname-range in nodelist table
	my ($framerange, $cwd) = @_;
	infomsg('Defining frames...');
	my $nodes = [noderange($framerange, 0)];
	my ($framestartnum) = $$nodes[0] =~/^\D+(\d+)$/;		# save this value for later
	#print "$$nodes[0], $framestartnum\n";
	if (scalar(@$nodes)) {
		#my %nodehash;
		#foreach my $n (@$nodes) { print "n=$n\n"; $nodehash{$n} = { node => $n, groups => 'hmc,all' }; }
		$tables{'nodelist'}->setNodesAttribs($nodes, { groups => 'frame,all' });
	}
	
	# Using the frame group, write starting-ip in hosts table
	my $framestartip = $STANZAS{'xcat-frames'}->{'starting-ip'};
	if ($framestartip) {
		my ($ipbase, $ipstart) = $framestartip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
		# take the number from the nodename, and as it increases, increase the ip addr
		my $regex = '|\D+(\d+)|' . "$ipbase.($ipstart+" . '$1' . "-$framestartnum)|";
		$tables{'hosts'}->setNodeAttribs('frame', {ip => $regex});
	}
	
	# Using the frame group, write: nodetype.nodetype, nodehm.mgt
	$tables{'nodetype'}->setNodeAttribs('frame', {nodetype => 'bpa'});
	
	# Using the frame group, num-frames-per-hmc, hmc hostname-range, write regex for: ppc.node, ppc.hcp, ppc.id
	# The frame # should come from the nodename
	my $idregex = '|\D+(\d+)|(0+$1)|';
	my %hash = (id => $idregex);

	if ($STANZAS{'xcat-site'}->{'use-direct-fsp-control'}) {
		$tables{'nodehm'}->setNodeAttribs('frame', {mgt => 'fsp'});
		my $hcpregex = '|(.+)|($1)|';		# its managed by itself
		$hash{hcp} = $hcpregex;
	}
	else {
		$tables{'nodehm'}->setNodeAttribs('frame', {mgt => 'hmc'});
		# let lsslp fill in the hcp
	}
	
	# Calculate which hmc manages this frame by dividing by num-frames-per-hmc
	#my $framesperhmc = $STANZAS{'xcat-frames'}->{'num-frames-per-hmc'};
	
	$tables{'ppc'}->setNodeAttribs('frame', \%hash);
	
	# Write vpd-file to vpd table
	my $filename = fullpath($STANZAS{'xcat-frames'}->{'vpd-file'}, $cwd);
	readwritevpd($filename);
	
}

sub readwritevpd {
	my $filename = shift;
	if (!defined($filename)) { return; }
	my $content;
	if (!open(STANZAF, $filename)) { errormsg("Can not open file $filename.", 2); return; }
	while (my $line = <STANZAF>) { $content .= $line; }
	close STANZAF;
	#print "content=$content";

	my $rc = xCAT::DBobjUtils->readFileInput($content);
	if ($rc) { errormsg("Error in processing stanza file $filename, rc=$rc.", 2); return; }

	$rc = xCAT::DBobjUtils->setobjdefs(\%::FILEATTRS);
	if ($rc) { errormsg("Error setting database attributes from stanza file $filename, rc=$rc.", 2); return; }
}


sub writecec {
	# write hostname-range in nodelist table
	my ($cecrange, $cwd) = @_;
	infomsg('Defining CECs...');
	my $nodes = [noderange($cecrange, 0)];
	if (scalar(@$nodes)) {
		#my %nodehash;
		#foreach my $n (@$nodes) { print "n=$n\n"; $nodehash{$n} = { node => $n, groups => 'hmc,all' }; }
		$tables{'nodelist'}->setNodesAttribs($nodes, { groups => 'cec,all' });
	}
	
	# Using the cec group, write starting-ip in hosts table
	my $cecstartip = $STANZAS{'xcat-cecs'}->{'starting-ip'};
	if ($cecstartip) {
		my ($ipbase, $ip3rd, $ip4th) = $cecstartip =~/^(\d+\.\d+)\.(\d+)\.(\d+)$/;
		# take the number from the nodename, and as it increases, increase the ip addr
		my $cechash = parsenoderange($cecrange);
		my $cecstartnum = $$cechash{'primary-start'};
		# Math for 4th field:  (ip4th-1+cecnum-cecstartnum)%254 + 1
		# Math for 3rd field:  (ip4th-1+cecnum-cecstartnum)/254 + ip3rd
		my $regex = '|\D+(\d+)|' . "$ipbase.((${ip4th}-1+" . '$1' . "-$cecstartnum)/254+$ip3rd).((${ip4th}-1+" . '$1' . "-$cecstartnum)%254+1)|";
		$tables{'hosts'}->setNodeAttribs('cec', {ip => $regex});
	}
	
	# Using the cec group, write: nodetype.nodetype, nodehm.mgt
	$tables{'nodetype'}->setNodeAttribs('cec', {nodetype => 'fsp'});
	
	# Write regex for ppc.hcp.  lsslp will fill in parent.
	if ($STANZAS{'xcat-site'}->{'use-direct-fsp-control'}) {
		$tables{'nodehm'}->setNodeAttribs('cec', {mgt => 'fsp'});
		my $hcpregex = '|(.+)|($1)|';		# its managed by itself
		$tables{'ppc'}->setNodeAttribs('cec', {hcp => $hcpregex});
	}
	else {
		$tables{'nodehm'}->setNodeAttribs('cec', {mgt => 'hmc'});
		# let lsslp fill in the hcp
	}
	
	# Write supernode-list in ppc.supernode.  While we are at it, also assign the cage id and parent.
	#todo: handle the !sequential option?
	$nodes = [noderange($cecrange, 0)];		# the setNodesAttribs() function blanks out the nodes array
	my %framesupers;
	my $filename = fullpath($STANZAS{'xcat-cecs'}->{'supernode-list'}, $cwd);
	readsupers($filename, \%framesupers);
	my $i=0;	# the index into the array of cecs
	my %nodehash;
	# Collect each nodes supernode num into a hash
	foreach my $k (sort keys %framesupers) {
		my $f = $framesupers{$k};	# $f is a ptr to an array of super node numbers
		if (!$f) { next; }		# in case some frame nums did not get filled in by user
		my $cageid = 1;
		foreach my $s (@$f) {	# loop thru the supernode nums in this frame
			my $supernum = $s;
			my $numnodes = 4;
			if ($s =~ /\(\d+\)/) { ($supernum, $numnodes) = $s =~ /^(\d+)\((\d+)\)/; }
			for (my $j=0; $j<$numnodes; $j++) {		# assign the next few nodes to this supernode num
				my $nodename = $$nodes[$i++];
				#print "Setting $nodename supernode attribute to $supernum,$j\n";
				$nodehash{$nodename} = { supernode => "$supernum,$j", id => $cageid, parent => $k };
				$cageid += 2;
			}
		}
	}
	# Now write all of the supernode values to the ppc table
	if (scalar(keys %framesupers)) { $tables{'ppc'}->setNodesAttribs(\%nodehash); }
}

# Read/parse the supernode-list file and return the values in a hash of arrays
sub readsupers {
	my $filename = shift;
	my $framesup = shift;
	if (!defined($filename)) { return; }
	my $input;
    if (!open($input, $filename)) {
    	errormsg("Can not open file $filename.", 2);
        return;
    }
	my $l;
	my $linenum = 0;
    while ($l=<$input>) {
    	$linenum++;

        # skip blank and comment lines
        next if ( $l =~ /^\s*$/ || $l =~ /^\s*#/ );
        #print "l=$l\n";

        # process a real line - name, then colon, then only whitespace, numbers, and parens
        my ($frame, $supernums);
        if ( ($frame, $supernums) = $l =~ /^\s*(\S+)\s*:\s*([\s,\(\)\d]+)$/ ) {
        	#print "frame=$frame, supernums=$supernums\n";
        	$$framesup{$frame} = [split(/[\s,]+/, $supernums)];
        }
        
        else {
        	errormsg("syntax error on line $linenum.", 3);
        	return;
        }
    }    # end while - go to next line
    close($input);
}


sub writebb {
	my $framesperbb = shift;
	infomsg('Defining building blocks...');
	
	# Set site.sharedtftp=1 since we have bldg blocks
	$tables{'site'}->setAttribs({key => 'sharedtftp'}, {value => 1});
	
	# Write num-frames-per-bb in ppc.parent for bpas
	my $bbregex = '|\D+(\d+)|((($1-1)/' . $framesperbb . ')+1)|';
	$tables{'ppc'}->setNodeAttribs('frame', {parent => $bbregex});
}


# Create service node definitions
sub writesn {
	my $range = shift;
	infomsg('Defining service nodes...');
	my $nodes = [noderange($range, 0)];
	my ($startnum) = $$nodes[0] =~/^\D+(\d+)$/;		# save this value for later
	if (scalar(@$nodes)) {
		$tables{'nodelist'}->setNodesAttribs($nodes, { groups => 'service,all' });
	}
	
	# Write regex for: hosts.node, hosts.ip
	my $startip = $STANZAS{'xcat-lpars'}->{'service-node-starting-ip'};
	if ($startip) {
		my ($ipbase, $ipstart) = $startip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
		# take the number from the nodename, and as it increases, increase the ip addr
		my $regex = '|\D+(\d+)|' . "$ipbase.($ipstart+" . '$1' . "-$startnum)|";
		my %hash = (ip => $regex);
		my $otherint = $STANZAS{'xcat-lpars'}->{'service-node-otherinterfaces'};
		if ($otherint) {
			# need to replace each ip addr in otherinterfaces with a regex
			my @ifs = split(/[\s,]+/, $otherint);
			foreach my $if (@ifs) {
				my ($nic, $startip) = split(/:/, $if);
				($ipbase, $ipstart) = $startip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
				$if = "$nic:$ipbase.($ipstart+" . '$1' . "-$startnum)";
			}
			$regex = '|\D+(\d+)|' . join(',', @ifs) . '|';
			#print "regex=$regex\n";
			$hash{otherinterfaces} = $regex;
		}
		
		$tables{'hosts'}->setNodeAttribs('service', \%hash);
	}
	
	# Write regex for: ppc.node, nodetype.nodetype 
	$tables{'ppc'}->setNodeAttribs('service', {id => '1'});
	$tables{'nodetype'}->setNodeAttribs('service', {nodetype => 'osi', arch => 'ppc64'});
	$tables{'nodehm'}->setNodeAttribs('service', {mgt => 'fsp', cons => 'fsp'});
	$tables{'noderes'}->setNodeAttribs('service', {netboot => 'yaboot'});
	my $sntab = xCAT::Table->new('servicenode', -create=>1);
	if (!$sntab) { errormsg("Can not open servicenode table in database.", 3); }
	else {
		$sntab->setNodeAttribs('service', {nameserver=>1, dhcpserver=>1, tftpserver=>1, nfsserver=>1, conserver=>1, monserver=>1, ftpserver=>1, nimserver=>1, ipforward=>1});
	}
	
	# Write ppc.hcp and ppc.parent
	# Math for SN in BB:  cecnum = ( ( (snnum-1) / snsperbb) * cecsperbb) + snpositioninbb
	# Math for position:  snpositioninbb = ( ( (snnum-1) % snsperbb) * (cecsperbb-1) ) +  1
	my $cecsperbb = $STANZAS{'xcat-building-blocks'}->{'num-cecs-per-bb'};
	my $snsperbb = $STANZAS{'xcat-lpars'}->{'num-service-nodes-per-bb'};
	my $cechash = parsenoderange($STANZAS{'xcat-cecs'}->{'hostname-range'});
	my $base = $$cechash{'primary-base'};
	my $start = $$cechash{'primary-start'};
	my $len = length($$cechash{'primary-start'});
	my $snpositioninbb = '((($1-1)%' . "$snsperbb)*($cecsperbb-1))+$start";
	my $regex = '|\D+(\d+)|' . "$base(sprintf('%0${len}d'," . '((($1-1)/' . "$snsperbb)*$cecsperbb)+$snpositioninbb))|";
	$tables{'ppc'}->setNodeAttribs('service', {hcp => $regex, parent => $regex});
}


# Create storage node definitions
sub writestorage {
	my $range = shift;
	infomsg('Defining storage nodes...');
	my $nodes = [noderange($range, 0)];
	my ($startnum) = $$nodes[0] =~/^\D+(\d+)$/;		# save this value for later
	if (scalar(@$nodes)) {
		$tables{'nodelist'}->setNodesAttribs($nodes, { groups => 'storage,all' });
	}
	
	# Write regex for: hosts.node, hosts.ip
	my $startip = $STANZAS{'xcat-lpars'}->{'storage-node-starting-ip'};
	if ($startip) {
		my ($ipbase, $ipstart) = $startip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
		# take the number from the nodename, and as it increases, increase the ip addr
		my $regex = '|\D+(\d+)|' . "$ipbase.($ipstart+" . '$1' . "-$startnum)|";
		my %hash = (ip => $regex);
		my $otherint = $STANZAS{'xcat-lpars'}->{'storage-node-otherinterfaces'};
		if ($otherint) {
			# need to replace each ip addr in otherinterfaces with a regex
			my @ifs = split(/[\s,]+/, $otherint);
			foreach my $if (@ifs) {
				my ($nic, $startip) = split(/:/, $if);
				($ipbase, $ipstart) = $startip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
				$if = "$nic:$ipbase.($ipstart+" . '$1' . "-$startnum)";
			}
			$regex = '|\D+(\d+)|' . join(',', @ifs) . '|';
			#print "regex=$regex\n";
			$hash{otherinterfaces} = $regex;
		}
		my $aliases = $STANZAS{'xcat-lpars'}->{'storage-node-aliases'};
		if ($aliases) {
			#todo: support more than 1 alias
			$regex = '|(.+)|($1)' . "$aliases|";
			$hash{hostnames} = $regex;
		}
		
		$tables{'hosts'}->setNodeAttribs('storage', \%hash);
	}
	
	# Write regex for: ppc.node, nodetype.nodetype 
	$tables{'ppc'}->setNodeAttribs('storage', {id => '1'});
	$tables{'nodetype'}->setNodeAttribs('storage', {nodetype => 'osi', arch => 'ppc64'});
	$tables{'nodehm'}->setNodeAttribs('storage', {mgt => 'fsp', cons => 'fsp'});
	$tables{'noderes'}->setNodeAttribs('storage', {netboot => 'yaboot'});
	
	#todo: Write regex for xcatmaster and servicenode to point it to its SN
	
	#todo: Write ppc.hcp and ppc.parent
	#my $cecsperbb = $STANZAS{'xcat-building-blocks'}->{'num-cecs-per-bb'};
	#my $regex = '|\D+(\d+)|((($1-1)/' . $cecsperbb . ')+1)|';
	#$tables{'ppc'}->setNodeAttribs('service', {parent => $regex});
}


# Create storage node definitions
sub writecompute {
	my $range = shift;
	infomsg('Defining compute nodes...');
	my $nodes = [noderange($range, 0)];
	my ($startnum) = $$nodes[0] =~/^\D+(\d+)$/;		# save this value for later
	if (scalar(@$nodes)) {
		$tables{'nodelist'}->setNodesAttribs($nodes, { groups => 'compute,all' });
	}
	
	# Write regex for: hosts.node, hosts.ip
	my $startip = $STANZAS{'xcat-lpars'}->{'compute-node-starting-ip'};
	if ($startip) {
		my ($ipbase, $ipstart) = $startip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
		# take the number from the nodename, and as it increases, increase the ip addr
		my $regex = '|\D+(\d+)|' . "$ipbase.($ipstart+" . '$1' . "-$startnum)|";
		my %hash = (ip => $regex);
		my $otherint = $STANZAS{'xcat-lpars'}->{'compute-node-otherinterfaces'};
		if ($otherint) {
			# need to replace each ip addr in otherinterfaces with a regex
			my @ifs = split(/[\s,]+/, $otherint);
			foreach my $if (@ifs) {
				my ($nic, $startip) = split(/:/, $if);
				($ipbase, $ipstart) = $startip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
				$if = "$nic:$ipbase.($ipstart+" . '$1' . "-$startnum)";
			}
			$regex = '|\D+(\d+)|' . join(',', @ifs) . '|';
			#print "regex=$regex\n";
			$hash{otherinterfaces} = $regex;
		}
		my $aliases = $STANZAS{'xcat-lpars'}->{'compute-node-aliases'};
		if ($aliases) {
			#todo: support more than 1 alias
			$regex = '|(.+)|($1)' . "$aliases|";
			$hash{hostnames} = $regex;
		}
		
		$tables{'hosts'}->setNodeAttribs('compute', \%hash);
	}
	
	# Write regex for: nodetype.nodetype, etc.
	$tables{'nodetype'}->setNodeAttribs('compute', {nodetype => 'osi', arch => 'ppc64'});
	$tables{'nodehm'}->setNodeAttribs('compute', {mgt => 'fsp', cons => 'fsp'});
	$tables{'noderes'}->setNodeAttribs('compute', {netboot => 'yaboot'});
	
	
	#todo: Write regex for xcatmaster and servicenode to point it to its SN
	
	# Write ppc.hcp and ppc.parent
	my $lparspercec = $STANZAS{'xcat-lpars'}->{'num-lpars-per-cec'};
	my $cechash = parsenoderange($STANZAS{'xcat-cecs'}->{'hostname-range'});
	my $base = $$cechash{'primary-base'};
	my $start = $$cechash{'primary-start'};
	my $len = length($$cechash{'primary-start'});
	# Math:  cecnum = ( nodenum-1) / nodespercec) + cecstartnum 
	my $regex = '|\D+(\d+)|' . "$base(sprintf('%0${len}d'," . '(($1-1)/' . "$lparspercec)+$start))|";
	$tables{'ppc'}->setNodeAttribs('compute', {hcp => $regex, parent => $regex});
	
	# Write ppc.id (lpar id)
	if ($lparspercec == 1) { $regex = '1'; }		# this will be faster than doing the calculation below
	elsif ($lparspercec == 8) {
		#todo: for now assume 8 means a p7 IH.  Make a different way to determine this is a p7 IH
		# Math:  lparid = ( ( (nodenum-1) % nodespercec) *4) + 1 
		$regex = '|\D+(\d+)|(((($1-1)%' . "$lparspercec)*4)+1)|";
	}
	else {
		# Math:  lparid = ( (nodenum-1) % nodespercec) + 1 
		$regex = '|\D+(\d+)|((($1-1)%' . "$lparspercec)+1)|";
	}
	$tables{'ppc'}->setNodeAttribs('compute', {id => $regex});
}


# Parse a noderange like n01-n20, n[01-20], or f[1-2]c[01-10].
# Returns a hash that contains:  primary-base, primary-start, primary-end, primary-pad, secondary-base, secondary-start, secondary-end, secondary-pad
sub parsenoderange {
	my $nr = shift;
	my $ret = {};
	
	# Check for a 2 square bracket range, e.g. f[1-2]c[01-10]
	if ( $nr =~ /^\s*\S+\[\d+[\-\:]\d+\]\S+\[\d+[\-\:]\d+\]\s*$/ ) {
		($$ret{'primary-base'}, $$ret{'primary-start'}, $$ret{'primary-end'}, $$ret{'secondary-base'}, $$ret{'secondary-start'}, $$ret{'secondary-end'}) = $nr =~ /^\s*(\S+)\[(\d+)[\-\:](\d+)\](\S+)\[(\d+)[\-\:](\d+)\]\s*$/;
		return $ret;
	}
	
	# Check for a square bracket range, e.g. n[01-20]
	if ( $nr =~ /^\s*\S+\[\d+[\-\:]\d+\]\s*$/ ) {
		($$ret{'primary-base'}, $$ret{'primary-start'}, $$ret{'primary-end'}) = $nr =~ /^\s*(\S+)\[(\d+)[\-\:](\d+)\]\s*$/;
		return $ret;
	}
	
	# Check for normal range, e.g. n01-n20
	my $base2;
	if ( $nr =~ /^\s*\D+\d+\-\D+\d+\s*$/ ) {
		($$ret{'primary-base'}, $$ret{'primary-start'}, $base2, $$ret{'primary-end'}) = $nr =~ /^\s*(\D+)(\d+)\-(\D+)(\d+)\s*$/;
		if ($$ret{'primary-base'} ne $base2) { return undef; }		# ill-formed range
		return $ret;
	}
	
	return undef;   # range did not match any of the cases above
}


sub errormsg {
	my $msg = shift;
	my $exitcode = shift;
	my %rsp;
    push @{$rsp{error}}, $msg;
    xCAT::MsgUtils->message('E', \%rsp, $CALLBACK, $exitcode);
    return;
}


sub infomsg {
	my $msg = shift;
	my %rsp;
    push @{$rsp{info}}, $msg;
    xCAT::MsgUtils->message('I', \%rsp, $CALLBACK);
    return;
}

sub fullpath {
	my ($filename, $cwd) = @_;
	if ($filename =~ /^\s*\//) { return $filename; }		# it was already a full path
	return xCAT::Utils->full_path($filename, $cwd);
}

1;
