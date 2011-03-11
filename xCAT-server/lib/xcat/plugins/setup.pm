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
# Todo: Limitations on the values in the config file:
# - do not yet support redundant bpcs or fsps
# - also support verbose mode
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
use xCAT_plugin::networks;

my $CALLBACK;
my %STANZAS;
my $SUB_REQ;
my $DELETENODES;
my %NUMCECSINFRAME;
my $DHCPINTERFACES;

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
    $SUB_REQ = shift;
    #my $nodes    = $request->{node};
    #my $command  = $request->{command}->[0];
    my $args     = $request->{arg};
    my $VERSION;
    my $HELP;
    my %SECTIONS;	# which stanzas should be processed
    my $SECT;
    
    my $setup_usage = sub {
    	my $exitcode = shift @_;
    	my %rsp;
    	push @{$rsp{data}}, "Usage: xcatsetup [-v|--version] [-?|-h|--help] [-s|--stanzas stanza-list] [--yesreallydeletenodes] <cluster-config-file>";
        if ($exitcode) { $rsp{errorcode} = $exitcode; }
        $CALLBACK->(\%rsp);
    };

	# Process the cmd line args
    if ($args) { @ARGV = @{$args}; }
    else { @ARGV = (); }
    if (!GetOptions('h|?|help'  => \$HELP, 'v|version' => \$VERSION, 's|stanzas=s' => \$SECT, 'yesreallydeletenodes' => \$DELETENODES) ) { $setup_usage->(1); return; }

    if ($HELP || (scalar(@ARGV)==0 && !$VERSION)) { $setup_usage->(0); return; }

    if ($VERSION) {
        my %rsp;
        my $version = xCAT::Utils->Version();
        $rsp{data}->[0] = $version;
        $CALLBACK->(\%rsp);
        return;
    }
    
    if ($SECT) {
    	foreach my $s (split(/[\s,]+/, $SECT)) { $SECTIONS{$s} = 1; }
    }
    
    #todo: support reading the config file from stdin
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
    writedb($request->{cwd}->[0], \%SECTIONS);
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
            $attr =~ tr/A-Z/a-z/;     # Convert to lowercase
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

# A few common tables that a lot of functions need.  The value is whether or not is should autocommit.
my %tables = ('site' => 1,
			'nodelist' => 1,
			'hosts' => 1,
			'ppc' => 1,
			'nodetype' => 1,
			'nodehm' => 1,
			'noderes' => 1,
			'postscripts' => 1,
			'nodepos' => 1,
			'servicenode' => 1,
			'nodegroup' => 0,
            'networks' => 1,
			);
my $CECPOSITIONS;	# a hash of the cec values in the nodepos table

sub writedb {
	my ($cwd, $sections) = @_;		# the current dir from the request and the stanzas that should be processed
	
	# Open some common tables that several of the stanzas need
	foreach my $tab (keys %tables) {
		$tables{$tab} = xCAT::Table->new($tab, -create=>1, -autocommit=>$tables{$tab});
		if (!$tables{$tab}) { errormsg("Can not open $tab table in database.  Exiting config file processing.", 3); return; }
	}

	# Write service LAN info (hash key=xcat-service-lan)
	#using hostname-range, write: nodelist.node, nodelist.groups, switches.switch
	#using hostname-range and starting-ip, write regex for: hosts.node, hosts.ip
	#using num-ports-per-switch, switch-port-prefix, switch-port-sequence, write: switch.node, switch.switch, switch.port
	#using dhcp-dynamic-range, write: networks.dynamicrange for the service network.
    # * Note: for AIX the permanent IPs for HMCs/FSPs/BPAs (specified in later stanzas) should be within this dynamic range, at the high end. For linux the permanent IPs should be outside this dynamic range.
    # * use the first IP in the specified dynamic range to locate the service network in the networks table 
	#on aix stop bootp - see section 2.2.1.1 of p hw mgmt doc
	#run makedhcp -n   
    my $iprange = $STANZAS{'xcat-service-lan'}->{'dhcp-dynamic-range'};
	if ($iprange && (!scalar(keys(%$sections))||$$sections{'xcat-service-lan'})) { 
        my $mkresult = xCAT_plugin::networks->donets();
		unless (writenetworks($iprange)) { closetables(); return; }
	}
	
	# Write site table attrs (hash key=xcat-site)
	my $domain = $STANZAS{'xcat-site'}->{domain};
	if ($domain && (!scalar(keys(%$sections))||$$sections{'xcat-site'})) { writesite($domain); }    
    
	# Write HMC info (hash key=xcat-hmcs)
	my $hmcrange = $STANZAS{'xcat-hmcs'}->{'hostname-range'};
	if ($hmcrange && (!scalar(keys(%$sections))||$$sections{'xcat-hmcs'})) { 
		unless (writehmc($hmcrange)) { closetables(); return; }
	}
	
	# Write frame info (hash key=xcat-frames)
	my $framerange = $STANZAS{'xcat-frames'}->{'hostname-range'};
	if ($framerange && (!scalar(keys(%$sections))||$$sections{'xcat-frames'})) { 
		unless (writeframe($framerange, $cwd)) { closetables(); return; }
	}
	
	# Write CEC info (hash key=xcat-cecs)
	my $cecrange = $STANZAS{'xcat-cecs'}->{'hostname-range'};
	if ($cecrange && (!scalar(keys(%$sections))||$$sections{'xcat-cecs'})) { 
		unless (writecec($cecrange, $cwd)) { closetables(); return; }
	}
	
	# Save the CEC positions for all the node definitions later
	if ($cecrange) {
		$CECPOSITIONS = $tables{'nodepos'}->getNodesAttribs([noderange($cecrange)], ['rack','u']);
		#print Dumper($CECPOSITIONS);
	}
	
	# Write BB info (hash key=xcat-building-blocks)
	my $framesperbb = $STANZAS{'xcat-building-blocks'}->{'num-frames-per-bb'};
	if ($framesperbb && (!scalar(keys(%$sections))||$$sections{'xcat-building-blocks'})) { 
		unless (writebb($framesperbb)) { closetables(); return; }
	}
	
	# Write lpar info in ppc, noderes, servicenode, etc.
	my $lparrange = $STANZAS{'xcat-lpars'}->{'hostname-range'};
	if ($lparrange && (!scalar(keys(%$sections))||$$sections{'xcat-lpars'})) { 
		unless (writelpar($lparrange)) { closetables(); return; }
		#unless (writelpar-service($lparrange)) { closetables(); return; }
		#unless (writelpar-storage($lparrange)) { closetables(); return; }
	}
	
	my $snrange = $STANZAS{'xcat-service-nodes'}->{'hostname-range'};
	if ($snrange && (!scalar(keys(%$sections))||$$sections{'xcat-service-nodes'})) { 
		unless (writesn($snrange)) { closetables(); return; }
	}
	
	my $storagerange = $STANZAS{'xcat-storage-nodes'}->{'hostname-range'};
	if ($storagerange && (!scalar(keys(%$sections))||$$sections{'xcat-storage-nodes'})) { 
		unless (writestorage($storagerange)) { closetables(); return; }
	}
	
	my $computerange = $STANZAS{'xcat-compute-nodes'}->{'hostname-range'};
	if ($computerange && (!scalar(keys(%$sections))||$$sections{'xcat-compute-nodes'})) { 
		unless (writecompute($computerange)) { closetables(); return; }
	}
	closetables();
}


sub closetables {
	# Close all the open common tables to finish up
	foreach my $tab (keys %tables) {
		if ($tables{$tab}) { $tables{$tab}->close(); }
	}
}

sub writenetworks {
    if ($DELETENODES) { return 1; }
    my $range = shift;
    infomsg('Defining networks attributes...');
    # set the IP range specified in the config file
    #print "range=$range\n";
    # find the network the range existed
    $range =~ /(\d+\.\d+\.\d+\.\d+)\-(\d+\.\d+\.\d+\.\d+)/;
    my ($ip1, $ip2, $ip3, $ip4) = split('\.', $1);
    my @entries = @{$tables{'networks'}->getAllEntries()};
    if (@entries) {
        for my $net (@entries) {
            my %netref = %$net;
            my ($m1, $m2, $m3, $m4) = split('\.', $netref{'mask'});
            my $n1 = ((int $ip1) & (int $m1));
            my $n2 = ((int $ip2) & (int $m2));
            my $n3 = ((int $ip3) & (int $m3));
            my $n4 = ((int $ip4) & (int $m4));
            my $ornet = "$n1.$n2.$n3.$n4";
            if ($ornet eq $netref{'net'}) {
                $tables{'networks'}->setAttribs({'net' => $netref{'net'}, 'mask' => $netref{'mask'}}, {'dynamicrange' => $range});
                $DHCPINTERFACES = $netref{'mgtifname'};
                last;
            }
        }
    }
    return 1;
}    

sub writesite {
	if ($DELETENODES) { return 1; }
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
	
	# set the HFI switch topology
	if ($STANZAS{'xcat-site'}->{topology}) {
		$tables{'site'}->setAttribs({key => 'topology'}, {value => $STANZAS{'xcat-site'}->{topology} });
	}
	
	# set site.dhcpinterfaces
	if ($DHCPINTERFACES) {
		$tables{'site'}->setAttribs({key => 'dhcpinterfaces'}, {value => $DHCPINTERFACES });
	}    
	return 1;
}


sub writehmc {
	# using hostname-range, write: nodelist.node, nodelist.groups
	my $hmcrange = shift;
	my $nodes = [noderange($hmcrange, 0)];
	if (!scalar(@$nodes)) { return 1; }
	if ($DELETENODES) {
		deletenodes('HMCs', $hmcrange);
		deletegroup('hmc');
		return 1;
	}
	my $hmchash;
	unless ($hmchash = parsenoderange($hmcrange)) { return 0; }
	infomsg('Defining HMCs...');
	$tables{'nodelist'}->setNodesAttribs($nodes, { groups => 'hmc,all' });
	staticGroup('hmc');
	
	# using hostname-range and starting-ip, write regex for: hosts.node, hosts.ip
	my $hmcstartip = $STANZAS{'xcat-hmcs'}->{'starting-ip'};
	if ($hmcstartip && isIP($hmcstartip)) {
		my $hmcstartnum = $$hmchash{'primary-start'};
		my ($ipbase, $ipstart) = $hmcstartip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
		# take the number from the nodename, and as it increases, increase the ip addr
        my $regex = '|\S+?(\d+)\D*$|' . "$ipbase.($ipstart+" . '$1' . "-$hmcstartnum)|";
		$tables{'hosts'}->setNodeAttribs('hmc', {ip => $regex});
	}
	
	# using hostname-range, write regex for: ppc.node, nodetype.nodetype 
	$tables{'ppc'}->setNodeAttribs('hmc', {nodetype => 'hmc'});
	#$tables{'nodetype'}->setNodeAttribs('hmc', {nodetype => 'hmc'});
	
	# Set the 1st two hmcs as the ones CNM should send service events to
	$nodes = [noderange($hmcrange, 0)];
	$tables{'site'}->setAttribs({key => 'ea_primary_hmc'}, {value => $$nodes[0]});
	if (scalar(@$nodes) >= 2) { $tables{'site'}->setAttribs({key => 'ea_backup_hmc'}, {value => $$nodes[1]}); }
	return 1;
}


sub writeframe {
	# write hostname-range in nodelist table
	my ($framerange, $cwd) = @_;
	my $nodes = [noderange($framerange, 0)];
	if (!scalar(@$nodes)) { return 1; }
	if ($DELETENODES) {
		deletenodes('frames', $framerange);
		deletegroup('frame');
		return 1;
	}
	infomsg('Defining frames...');
	$tables{'nodelist'}->setNodesAttribs($nodes, { groups => 'frame,all' });
	staticGroup('frame');
	
	# Using the frame group, write starting-ip in hosts table
    my $framehash;
	my $framestartip = $STANZAS{'xcat-frames'}->{'starting-ip'};
	if ($framestartip && isIP($framestartip)) {
        $framehash = parsenoderange($framerange);
		my $framestartnum = $$framehash{'primary-start'};
		my ($ipbase, $ipstart) = $framestartip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
		# take the number from the nodename, and as it increases, increase the ip addr
        my $regex = '|\S+?(\d+)\D*$|' . "$ipbase.($ipstart+" . '$1' . "-$framestartnum)|";
		$tables{'hosts'}->setNodeAttribs('frame', {ip => $regex});
	}
	
	# Using the frame group, write: nodetype.nodetype, nodehm.mgt
	$tables{'ppc'}->setNodeAttribs('frame', {nodetype => 'frame'});
	#$tables{'nodetype'}->setNodeAttribs('frame', {nodetype => 'bpa'});
	
	# Using the frame group, num-frames-per-hmc, hmc hostname-range, write regex for: ppc.node, ppc.hcp, ppc.id
	# The frame # should come from the nodename
    my $idregex = '|\S+?(\d+)\D*$|(0+$1)|';
	my %hash = (id => $idregex);

	if ($STANZAS{'xcat-site'}->{'use-direct-fsp-control'}) {
		$tables{'nodehm'}->setNodeAttribs('frame', {mgt => 'bpa'});
		my $hcpregex = '|(.+)|($1)|';		# its managed by itself
		$hash{hcp} = $hcpregex;
	}
	else {
		$tables{'nodehm'}->setNodeAttribs('frame', {mgt => 'hmc'});
		# let lsslp fill in the hcp
	}
	
	# Calculate which hmc manages this frame by dividing by num-frames-per-hmc
	my $framesperhmc = $STANZAS{'xcat-frames'}->{'num-frames-per-hmc'};
    if ($framesperhmc and $STANZAS{'xcat-hmcs'}->{'hostname-range'}) {
        my $hmchash;
        unless ($hmchash = parsenoderange($STANZAS{'xcat-hmcs'}->{'hostname-range'})) { return 0; }
        my $hmcbase = $$hmchash{'primary-base'};
        my $fnum = $$framehash{'primary-start'};
        my $hmcattch = $$hmchash{'attach'};
        my $umb = $$hmchash{'primary-start'};
        my $sfpregex;
        #unless ($hmcattch) { $sfpregex = '|\S+?(\d+)$|'.$hmcbase.'(0+$1)|'; }
        unless ($hmcattch) { $sfpregex = '|\S+?(\d+)$|'.$hmcbase.'((0+$1-'.$fnum.')/'.$framesperhmc.'+'.$umb.')|'; }
        #else { $sfpregex = '|\S+?(\d+)$|'.$hmcbase.'(0+$1)'.$hmcattch.'|'; }
        else { $sfpregex = '|\S+?(\d+)$|'.$hmcbase.'((0+$1-'.$fnum.')/'.$framesperhmc.'+'.$umb.')'.$hmcattch.'|'; }
        $hash{'sfp'} =  $sfpregex;
    }

	$tables{'ppc'}->setNodeAttribs('frame', \%hash);
	
	# Write vpd-file to vpd table
	if ($STANZAS{'xcat-frames'}->{'vpd-file'}) {
		my $filename = fullpath($STANZAS{'xcat-frames'}->{'vpd-file'}, $cwd);
		readwritevpd($filename);
	}
	return 1;
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
	my $nodes = [noderange($cecrange, 0)];
	if ($$nodes[0] =~ /\[/) {
		errormsg("hostname ranges with 2 sets of '[]' are not supported in xCAT 2.5 and below.", 21);
		return 0;
	}
	if (!scalar(@$nodes)) { return 1; }
	if ($DELETENODES) {
		deletenodes('CECs', $cecrange);
		deletegroup('cec');
		dynamicGroups('delete', $nodes);
		return 1;
	}
	infomsg('Defining CECs...');
	$tables{'nodelist'}->setNodesAttribs($nodes, { groups => 'cec,all' });
	staticGroup('cec');
	
	# Using the cec group, write starting-ip in hosts table
	my $cecstartip = $STANZAS{'xcat-cecs'}->{'starting-ip'};
	my $cechash = parsenoderange($cecrange);
	if ($cecstartip && isIP($cecstartip)) {
		my ($ipbase, $ip3rd, $ip4th) = $cecstartip =~/^(\d+\.\d+)\.(\d+)\.(\d+)$/;
		# take the number from the nodename, and as it increases, increase the ip addr
		#print Dumper($cechash);
		my $regex;
		if (defined($$cechash{'secondary-start'})) {
			# using name like f1c1
			my $primstartnum = $$cechash{'primary-start'};
			my $secstartnum = $$cechash{'secondary-start'};
			# Math for 3rd field:  ip3rd+primnum-primstartnum
			# Math for 4th field:  ip4th+secnum-secstartnum
            $regex = '|\D+(\d+)\D+(\d+)\D*$|' . "$ipbase.($ip3rd+" . '$1' . "-$primstartnum).($ip4th+" . '$2' . "-$secstartnum)|";
		}
		else {
			# using name like cec01
			my $cecstartnum = $$cechash{'primary-start'};
			# Math for 4th field:  (ip4th-1+cecnum-cecstartnum)%254 + 1
			# Math for 3rd field:  (ip4th-1+cecnum-cecstartnum)/254 + ip3rd
            $regex = '|\S+?(\d+)$\D*|' . "$ipbase.((${ip4th}-1+" . '$1' . "-$cecstartnum)/254+$ip3rd).((${ip4th}-1+" . '$1' . "-$cecstartnum)%254+1)|";
		}
		$tables{'hosts'}->setNodeAttribs('cec', {ip => $regex});
	}
	
	# Using the cec group, write: nodetype.nodetype
	$tables{'ppc'}->setNodeAttribs('cec', {nodetype => 'cec'});
	#$tables{'nodetype'}->setNodeAttribs('cec', {nodetype => 'fsp'});
	
	# Write regex for ppc.hcp, nodehm.mgt
	if ($STANZAS{'xcat-site'}->{'use-direct-fsp-control'}) {
		$tables{'nodehm'}->setNodeAttribs('cec', {mgt => 'fsp'});
		my $hcpregex = '|(.+)|($1)|';		# its managed by itself
		$tables{'ppc'}->setNodeAttribs('cec', {hcp => $hcpregex});
	}
	else {
		$tables{'nodehm'}->setNodeAttribs('cec', {mgt => 'hmc'});
		# let lsslp fill in the hcp
	}
	
	# Create dynamic groups for the nodes in each cec
	$nodes = [noderange($cecrange, 0)];		# the setNodesAttribs() function blanks out the nodes array
	dynamicGroups('add', $nodes, 'parent==');

	$nodes = [noderange($cecrange, 0)];		# the setNodesAttribs() function blanks out the nodes array
	
	# If they are taking the simple approach for now of not assigning supernode #s, but just told
	# us how many cecs should be in each frame, write: ppc.id, ppc.parent, nodelist.groups, nodepos.rack, nodepos.u
	if (!($STANZAS{'xcat-cecs'}->{'supernode-list'}) && $STANZAS{'xcat-cecs'}->{'num-cecs-per-frame'}) {
		# Loop thru all cecs, incrementing the cageid and frameindex appropriately, and put the cec attrs in the hashes.
		my $cecsperframe = $STANZAS{'xcat-cecs'}->{'num-cecs-per-frame'};
		my %ppchash;
		my %nodehash;
		my %nodeposhash;
		my $numcecs = 1;		# the # of cecs we have assigned to the current frame
		my $cageid = 5;		#todo: p7 ih starts at 5, but what about other models?
		my $frames = [noderange($STANZAS{'xcat-frames'}->{'hostname-range'}, 0)];
		my $frameindex = 0;
		foreach my $cec (@$nodes) {
			my $framename = $$frames[$frameindex];
			$ppchash{$cec} = { id => $cageid, parent => $framename };
			$nodehash{$cec} = { groups => "${framename}cecs,cec,all" };
            my ($framenum) = $framename =~ /\S+?(\d+)\D*$/;
			$nodeposhash{$cec} = { rack => $framenum+0, u => $cageid };
			# increment indexes for the next iteration of the loop
			$cageid += 2;
			$numcecs++;
			if ($numcecs > $cecsperframe) { $frameindex++; $numcecs=1; $cageid=5; }		#todo: p7 ih starts at 5
		}
		$tables{'ppc'}->setNodesAttribs(\%ppchash);
		$tables{'nodelist'}->setNodesAttribs(\%nodehash);
		$tables{'nodepos'}->setNodesAttribs(\%nodeposhash);
	}
	
	# If they specified supernode-list, write ppc.supernode.  While we are at it, also assign the cage id and parent.
	my %framesupers;
	if (!($STANZAS{'xcat-cecs'}->{'supernode-list'})) { return 1; }
	my $filename = fullpath($STANZAS{'xcat-cecs'}->{'supernode-list'}, $cwd);
	unless (readsupers($filename, \%framesupers)) { return; }
	my $i=0;	# the index into the array of cecs
	#my $maxcageid=0;	# check to see if all frames have same # of cecs if they are using f1c1 type name
	#my $alreadywarned=0;
	my $numcecs;		# how many cecs in a frame we have assigned supernode nums to
	my %ppchash;
	my %nodehash;
	my %nodeposhash;
	my @nonexistant;		# if there are less cecs in some frames, we may need to delete them
	# Collect each nodes supernode num into a hash
	foreach my $k (sort keys %framesupers) {
		my $f = $framesupers{$k};	# $f is a ptr to an array of super node numbers
		if (!$f) { next; }		# in case some frame nums did not get filled in by user
		my $cageid = 5;		#todo: p7 ih starts at 5, but what about other models?
		my $numcecs = 0;
		foreach my $s (@$f) {	# loop thru the supernode nums in this frame
			my $supernum = $s;
			my $numnodes = 4;
			if ($s =~ /\(\d+\)/) { ($supernum, $numnodes) = $s =~ /^(\d+)\((\d+)\)/; }
			for (my $j=0; $j<$numnodes; $j++) {		# assign the next few nodes to this supernode num
				my $nodename = $$nodes[$i++];
				$numcecs++;
				#print "Setting $nodename supernode attribute to $supernum,$j\n";
				$ppchash{$nodename} = { supernode => "$supernum,$j", id => $cageid, parent => $k };
				$nodehash{$nodename} = { groups => "${k}cecs,cec,all" };
                my ($framenum) = $k =~ /\S+?(\d+)\D*$/;
				$nodeposhash{$nodename} = { rack => $framenum+0, u => $cageid };
				$cageid += 2;
			}
		}
		$NUMCECSINFRAME{$k} = $numcecs;		# save this for later
		my ($knum) = $k =~ /(\d+)$/;
		$NUMCECSINFRAME{$knum+0} = $numcecs;		# also save it by the frame num
		if (defined($$cechash{'secondary-start'}) && $numcecs != ($$cechash{'secondary-end'}-$$cechash{'secondary-start'}+1)) {
			# There are some cecs in this frame that did not get assigned supernode nums - maybe they do not exist
			#infomsg("Warning: the xcat-cecs:hostname-range of $cecrange appears to be using frame and CEC numbers in the CEC hostnames, but there is not the same number of CECs in each frame (according to the supernodelist).  This causes the supernode numbers to be assigned to the wrong CECs.");
			my $totalcecs = $$cechash{'secondary-end'}-$$cechash{'secondary-start'}+1;
			#print "skipping cecs ", $numcecs+1, "-$totalcecs\n";
			if ($STANZAS{'xcat-cecs'}->{'delete-unused-cecs'}) {
				# mark to be delete the unused cecs that do not have supernode nums specified
				for (my $l=1; $l<=($totalcecs-$numcecs); $l++) { push @nonexistant, $$nodes[$i++]; }
			}
			else {
				$i += ($totalcecs - $numcecs);		# fast-forward over the cecs in this frame that do not have supernode nums
			}
		}
	}
	# Now write all of the attribute values to the tables
	if (scalar(keys %framesupers)) {
		if (scalar(@nonexistant)) {
			my $nr = join(',', @nonexistant);
			#print "deleting $nr\n";
			noderm($nr);
		}
		$tables{'ppc'}->setNodesAttribs(\%ppchash);
		$tables{'nodelist'}->setNodesAttribs(\%nodehash);
		$tables{'nodepos'}->setNodesAttribs(\%nodeposhash);
	}
	return 1;
}

# Read/parse the supernode-list file and return the values in a hash of arrays
sub readsupers {
	my $filename = shift;
	my $framesup = shift;
	if (!defined($filename)) { return; }
	my $input;
    if (!open($input, $filename)) {
    	errormsg("Can not open file $filename.", 2);
        return 0;
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
        	my $supers = [split(/[\s,]+/, $supernums)];
        	# check the format of the super number entries
        	foreach my $s (@$supers) {
        		unless ($s=~/^\d+$/ || $s=~/^\d+\(\d+\)$/) { errormsg("invalid supernode specification $s in supernode-list file line $linenum.",8); return 0; }
        	}
        	# store the entries
        	$$framesup{$frame} = $supers;
        }
        
        else {
        	errormsg("syntax error on supernode-list file line $linenum.", 3);
        	return 0;
        }
    }    # end while - go to next line
    close($input);
    return 1;
}


sub writebb {
	my $framesperbb = shift;
	if ($DELETENODES) { return 1; }
	infomsg('Defining building blocks...');
	
	# Set site.sharedtftp=1 since we have bldg blocks
	$tables{'site'}->setAttribs({key => 'sharedtftp'}, {value => 1});
	$tables{'site'}->setAttribs({key => 'sshbetweennodes'}, {value => 'service'});
	
	# Using num-frames-per-bb write ppc.parent (frame #) for bpas
	if ($framesperbb !~ /^\d+$/) { errormsg("invalid non-integer value for num-frames-per-bb: $framesperbb", 7); return 0; }
    my $bbregex = '|\S+?(\d+)\D*$|((($1-1)/' . $framesperbb . ')+1)|';
	$tables{'ppc'}->setNodeAttribs('frame', {parent => $bbregex});
	return 1;
}

# Create lpar node definitions.  This stanza is used only if they are using hostnames like f1c1p1
sub writelpar {
	my $range = shift;
	my $nodes = [noderange($range, 0)];
	if (!scalar(@$nodes)) { return 1; }
	if ($DELETENODES) {
		deletenodes('LPAR nodes', $range);
		deletegroup('lpar');
		deletegroup('service');
		deletegroup('compute');
		#todo:  also delete dynamic groups: dynamicGroups('delete', [keys(%servicenodes)]);
		return 1;
	}
	infomsg('Defining LPAR nodes...');
	my $rangeparts = parsenoderange($range);
	if (!defined($$rangeparts{'tertiary-start'})) { errormsg("Currently only support xcat-lpars:hostname-range format like f[1-2]c[1-2]p[1-2].", 5); return 0; }
	my ($startnum) = $$rangeparts{'primary-start'};		# save this value for later
	$tables{'nodelist'}->setNodesAttribs($nodes, { groups => 'compute,lpar,all' });
	staticGroup('lpar');
	staticGroup('service');
	staticGroup('compute');
	
	# Write regex for hosts.node, hosts.ip, etc, for all lpars.  Also write a special entry
	# for service nodes, since they also have an ethernet adapter.
	my $startip = $STANZAS{'xcat-lpars'}->{'starting-ip'};
	if ($startip && isIP($startip)) {
		my ($ipbase, $ip2nd, $ip3rd, $ip4th) = $startip =~/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
		# take the number from the nodename, and as it increases, increase the ip addr
		# using name like f1c1p1
		my $primstartnum = $$rangeparts{'primary-start'};
		my $secstartnum = $$rangeparts{'secondary-start'};
		my $thirdstartnum = $$rangeparts{'tertiary-start'};
		# Math for 2nd field:  ip2nd+primnum-primstartnum
		# Math for 3rd field:  ip3rd+secnum-secstartnum
		# Math for 4th field:  ip4th+thirdnum-thirdstartnum
        my $regex = '|\D+(\d+)\D+(\d+)\D+(\d+)\D*$|' . "$ipbase.($ip2nd+" . '$1' . "-$primstartnum).($ip3rd+" . '$2' . "-$secstartnum).($ip4th+" . '$3' . "-$thirdstartnum)|";
		my %hash = (ip => $regex);
		# for service nodes, use the starting ip from that stanza
		my $serviceip = $STANZAS{'xcat-service-nodes'}->{'starting-ip'};
		my ($servbase, $serv2nd, $serv3rd, $serv4th) = $serviceip =~/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
		my %servicehash;
		if ($serviceip && isIP($serviceip)) {
            my $serviceregex = '|\D+(\d+)\D+(\d+)\D+(\d+)\D*$|' . "$servbase.($serv2nd+" . '$1' . "-$primstartnum).($serv3rd+" . '$2' . "-$secstartnum).($serv4th+" . '$3' . "-$thirdstartnum)|";
			$servicehash{ip} = $serviceregex;
		}
		
		my $otherint = $STANZAS{'xcat-lpars'}->{'otherinterfaces'};
		if ($otherint) {
			# need to replace each ip addr in otherinterfaces with a regex
			my @ifs = split(/[\s,]+/, $otherint);
			foreach my $if (@ifs) {
				my ($nic, $nicip) = split(/:/, $if);
				if (!isIP($nicip)) { next; }
				my ($nicbase, $nic2nd, $nic3rd, $nic4th) = $nicip =~/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
				$if = "$nic:$nicbase.($nic2nd+" . '$1' . "-$primstartnum).($nic3rd+" . '$2' . "-$secstartnum).($nic4th+" . '$3' . "-$thirdstartnum)";
			}
            $regex = '|\D+(\d+)\D+(\d+)\D+(\d+)\D*$|' . join(',', @ifs) . '|';
			#print "regex=$regex\n";
			$hash{otherinterfaces} = $regex;
			if ($serviceip && isIP($serviceip)) {
				# same as regular lpar value, except prepend the lpar ip as -hf0
				my $hf0 = "-hf0:$ipbase.($ip2nd+" . '$1' . "-$primstartnum).($ip3rd+" . '$2' . "-$secstartnum).($ip4th+" . '$3' . "-$thirdstartnum)";
                my $serviceregex = '|\D+(\d+)\D+(\d+)\D+(\d+)\D*$|' . "$hf0," . join(',', @ifs) . '|';
				$servicehash{otherinterfaces} = $serviceregex;
			}
		}
		
		my $aliases = $STANZAS{'xcat-lpars'}->{'aliases'};
		if ($aliases) {
			# support more than 1 alias
			my @alist = split(/[\s,]+/, $aliases);
			foreach my $a (@alist) { if ($a=~/^-/) { $a = '($1)' . $a; } }	# prepend the hostname
			$regex = '|(.+)|' . join(',', @alist) . '|';
			$hash{hostnames} = $regex;
			
			# For services nodes, we do not really need any aliases, but we have to override the above
			$servicehash{hostnames} = '|(.+)|($1)-eth0|';
		}
		
		$tables{'hosts'}->setNodeAttribs('lpar', \%hash);
		if ($serviceip && isIP($serviceip)) { $tables{'hosts'}->setNodeAttribs('service', \%servicehash); }
	}
	
	# If there are an inconsistent # of cecs in each frame, delete the lpars that are not really there
	if ($STANZAS{'xcat-cecs'}->{'delete-unused-cecs'}) {
		my @nodestodelete;		# the lpars to delete
		my $maxcecs = $$rangeparts{'secondary-end'} - $$rangeparts{'secondary-start'} + 1;
		foreach my $k (sort keys %NUMCECSINFRAME) {
			if ($NUMCECSINFRAME{$k} >= $maxcecs) { next; }		# this frame is completely populated
			# create the noderange of the lpars that need to be deleted
			my ($framenum) = $k =~ /(\d+)$/;
			my $len = length($$rangeparts{'secondary-start'});
			my $index1 = $NUMCECSINFRAME{$k} + $$rangeparts{'secondary-start'};
			$index1 = sprintf("%0${len}d", $index1);
			my $index2 = $$rangeparts{'secondary-end'};
			$index2 = sprintf("%0${len}d", $index2);
			$len = length($$rangeparts{'primary-start'});
			$framenum = sprintf("%0${len}d", $framenum);
			my $nr = $$rangeparts{'primary-base'} . $framenum . $$rangeparts{'secondary-base'} . "[$index1-$index2]" . $$rangeparts{'tertiary-base'} . '[' . $$rangeparts{'tertiary-start'} . '-' . $$rangeparts{'tertiary-end'} . ']';
            if ($$rangeparts{'attach'}) { $nr .= $$rangeparts{'attach'};}
			push @nodestodelete, $nr;
		}
		my $delnodes = join(',', @nodestodelete);
		#print "should delete: $delnodes\n";
		#rmdef('f5c12p[1-8]');
		noderm($delnodes);
	}
	
	# Set some attrs common to all lpars
	$tables{'nodetype'}->setNodeAttribs('lpar', {nodetype => 'osi', arch => 'ppc64'});
	$tables{'nodehm'}->setNodeAttribs('lpar', {mgt => 'fsp', cons => 'fsp'});
	$tables{'noderes'}->setNodeAttribs('lpar', {netboot => 'yaboot'});
	
	# Write regexs for some of the ppc attrs
	# Note: we assume here that if they used f1c1p1 for nodes they should use f1c1 for cecs
	my $cechash = parsenoderange($STANZAS{'xcat-cecs'}->{'hostname-range'});
	my $cecprimbase = $$cechash{'primary-base'};
	#my $cecprimlen = length($$cechash{'primary-start'});
	my $cecsecbase = $$cechash{'secondary-base'};
	if (!$cecsecbase) { errormsg("when using LPAR names like f1c1p1, you must also use CEC names like f1c1",7); return 0; }
	my $framehash = parsenoderange($STANZAS{'xcat-frames'}->{'hostname-range'});
	#my $framebase = $$framehash{'primary-base'};
	#my $framestart = $$framehash{'primary-start'};
	#my $framelen = length($$framehash{'primary-start'});
	my %ppchash;
	my %nodeposhash;
    $ppchash{id} = '|^\D+\d+\D+\d+\D+(\d+)\D*$|(($1-1)*4+1)|';              #todo: this is p7 ih specific
	# convert between the lpar name and the cec name.  Assume that numbers are the same, but the base can be different
    my $regex = '|^\D+(\d+)\D+(\d+)\D+\d+\D*$|' . "$cecprimbase" . '($1)' . "$cecsecbase" .'($2)|';
	$ppchash{hcp} = $regex;
	$ppchash{parent} = $regex;
	$ppchash{nodetype} = 'lpar';
	#print Dumper($CECPOSITIONS);
	$tables{'ppc'}->setNodeAttribs('lpar', \%ppchash);
	
	#todo: for now, let the nodepos attrs for the cec be good enough
	#$nodeposhash{rack} = {rack => $CECPOSITIONS->{$cecname}->[0]->{rack}, u => $CECPOSITIONS->{$cecname}->[0]->{u}};
	#$nodeposhash{u} = {rack => $CECPOSITIONS->{$cecname}->[0]->{rack}, u => $CECPOSITIONS->{$cecname}->[0]->{u}};
	#$tables{'nodepos'}->setNodeAttribs('lpar', \%nodeposhash);
	
	# Figure out which lpars are service nodes and storage nodes and put them in groups
	my $framesperbb = $STANZAS{'xcat-building-blocks'}->{'num-frames-per-bb'};
	my $numframes = $$rangeparts{'primary-end'} - $$rangeparts{'primary-start'} + 1;
	my $numbbs = int($numframes/$framesperbb) + ($numframes%$framesperbb > 0);
	my %servicenodes;
	my %storagenodes;
	my %lpars;
	#my $cecsperbb = $STANZAS{'xcat-building-blocks'}->{'num-cecs-per-bb'};
	#if ($cecsperbb !~ /^\d+$/) { errormsg("invalid non-integer value for num-cecs-per-bb: $cecsperbb", 7); return 0; }
	for (my $b=1; $b<=$numbbs; $b++) {
		my $framebase = ($b-1) * $framesperbb + 1;
		findSNsinBB('service', $b, $framebase, $rangeparts, \%servicenodes, \%lpars) or return 0;
		findSNsinBB('storage', $b, $framebase, $rangeparts, \%storagenodes) or return 0;
	}
	if (scalar(keys(%servicenodes))) { $tables{'nodelist'}->setNodesAttribs(\%servicenodes); }
	if (scalar(keys(%storagenodes))) { $tables{'nodelist'}->setNodesAttribs(\%storagenodes); }
	if (scalar(keys(%lpars))) { $tables{'noderes'}->setNodesAttribs(\%lpars); }
	
	# Set some more service node specific attributes
	$tables{'servicenode'}->setNodeAttribs('service', {nameserver=>1, dhcpserver=>1, tftpserver=>1, nfsserver=>1, conserver=>1, monserver=>1, ftpserver=>1, nimserver=>1, ipforward=>1});
	if ($STANZAS{'ll-config'}->{'central_manager_list'}) {		# write the LL postscript for service nodes
		addPostscript('service', 'llserver.sh');
		addPostscript('compute', 'llcompute.sh');
	}
	
	dynamicGroups('add', [keys(%servicenodes)], 'xcatmaster==');
}


# Find either service nodes or storage nodes in a BB.  Adds the nodenames of the lpars to the snodes hash,
# and defines the groups in the hash, and assigns the other lpars to the correct service node.
sub findSNsinBB {
	my ($sntext, $bb, $framebase, $rangeparts, $snodes, $lpars) = @_;
	my $primbase = $$rangeparts{'primary-base'};
	my $primlen = length($$rangeparts{'primary-start'});
	my $secbase = $$rangeparts{'secondary-base'};
	my $seclen = length($$rangeparts{'secondary-start'});
	my $tertbase = $$rangeparts{'tertiary-base'};
	my $tertlen = length($$rangeparts{'tertiary-start'});
	my $framesperbb = $STANZAS{'xcat-building-blocks'}->{'num-frames-per-bb'};
	
	# Determine the lpar node name for each service/storage node
	my $snsperbb = $STANZAS{"xcat-$sntext-nodes"}->{"num-$sntext-nodes-per-bb"};
	if ($snsperbb !~ /^\d+$/) { errormsg("invalid non-integer value for num-$sntext-nodes-per-bb: $snsperbb", 7); return 0; }
	my @snpositions = split(/[\s,]+/, $STANZAS{"xcat-$sntext-nodes"}->{'cec-positions-in-bb'});
	if (scalar(@snpositions) != $snsperbb) { errormsg("invalid number of positions specified for xcat-$sntext-nodes:cec-positions-in-bb.", 3); return 0; }
	my @snsinbb;
	foreach my $p (@snpositions) {
		my $cecbase = 0;
		my $frame = $framebase;
		while ($p > ($cecbase + $NUMCECSINFRAME{$frame})) {
			# p is not in this frame, go on to the next
			$cecbase += $NUMCECSINFRAME{$frame};
			$frame++;
			#print "cecbase=$cecbase, frame=$frame\n";
			if ($frame >= ($framebase+$framesperbb)) { errormsg("Can not find $sntext node position $p in building block $bb.",9); return 0; }
		}
		my $cecinframe = $p - $cecbase;
		#my $nodename = $primbase . sprintf("%0${primlen}d", $frame) . $secbase . sprintf("%0${seclen}d", $cecinframe) . $tertbase . sprintf("%0${tertlen}d", 1);
		my $nodename = buildNodename($frame, $cecinframe, 1, $primbase, $primlen, $secbase, $seclen, $tertbase, $tertlen);
		#print "nodename=$nodename\n";
		$$snodes{$nodename} = { groups => "bb$bb$sntext,$sntext,lpar,all" };
		push @snsinbb, "$frame,$cecinframe";	# save for later
	}
	
	if ($lpars) {
		# Set xcatmaster/servicenode attrs for lpars
		my $cecsperbb = $STANZAS{'xcat-building-blocks'}->{'num-cecs-per-bb'};
		if ($cecsperbb !~ /^\d+$/) { errormsg("invalid non-integer value for num-cecs-per-bb: $cecsperbb", 7); return 0; }
		my $servsperbb = $STANZAS{'xcat-service-nodes'}->{'num-service-nodes-per-bb'};
		my $cecspersn = int($cecsperbb / $snsperbb);
		my $pmax = $STANZAS{'xcat-lpars'}->{'num-lpars-per-cec'};
		# Loop thru all lpars in this BB, assigning it to a service node
		my $snindex = 0;
		my $cecinthisbb = 1;
		for (my $f=$framebase; $f<($framebase+$framesperbb); $f++) {
			for (my $c=1; $c<=$NUMCECSINFRAME{$f}; $c++) {
				# form the current service node name
				my ($snframe, $sncec) = split(/,/, $snsinbb[$snindex]);
				my $snname = buildNodename($snframe, $sncec, 1, $primbase, $primlen, $secbase, $seclen, $tertbase, $tertlen);
				my $othersns;
				# build the list of other service node names
				for (my $s=0; $s<scalar(@snsinbb); $s++) {
					if ($s != $snindex) {
						my ($snf, $snc) = split(/,/, $snsinbb[$s]);
						$othersns .= ',' . buildNodename($snf, $snc, 1, $primbase, $primlen, $secbase, $seclen, $tertbase, $tertlen);;
					}
				}
				# assign all partitions in this cec to this service node
				for (my $p=1; $p<=$pmax; $p++) {
					my $lparname = buildNodename($f, $c, $p, $primbase, $primlen, $secbase, $seclen, $tertbase, $tertlen);
					$$lpars{$lparname} = {xcatmaster => $snname, servicenode => "$snname$othersns"};
				}
				# move to the next cec and possibly the next sn
				$cecinthisbb++;
				if ($cecinthisbb>$cecspersn && $snindex<(scalar(@snsinbb)-1)) { $snindex++; }
			}
		}
		# delete the service nodes themselves from this list
		foreach my $serv (@snsinbb) {
			my ($snframe, $sncec) = split(/,/, $serv);
			my $snname = buildNodename($snframe, $sncec, 1, $primbase, $primlen, $secbase, $seclen, $tertbase, $tertlen);
			delete $$lpars{$snname};
		}
	}
	return 1;
}

sub buildNodename {
	my ($frame, $cec, $partition, $primbase, $primlen, $secbase, $seclen, $tertbase, $tertlen) = @_;
	my $lparname = $primbase . sprintf("%0${primlen}d", $frame) . $secbase . sprintf("%0${seclen}d", $cec) . $tertbase . sprintf("%0${tertlen}d", $partition);
	return $lparname;
}


# Create service node definitions
sub writesn {
	my $range = shift;
	if (defined($STANZAS{'xcat-lpars'}->{'hostname-range'})) { errormsg("Can not define hostname-range in both the xcat-lpars and xcat-service-nodes stanzas.", 8); return 0; }
	my $nodes = [noderange($range, 0)];
	if (!scalar(@$nodes)) { return 1; }
	if ($DELETENODES) {
		deletenodes('service nodes', $range);
		deletegroup('service');
		dynamicGroups('delete', $nodes);
		return 1;
	}
	infomsg('Defining service nodes...');
	# We support name formats: sn01 or (todo:) b1s1
	my $rangeparts = parsenoderange($range);
	my ($startnum) = $$rangeparts{'primary-start'};		# save this value for later
	$tables{'nodelist'}->setNodesAttribs($nodes, { groups => 'service,lpar,all' });
	staticGroup('service');
	
	# Write regex for: hosts.node, hosts.ip
	my $startip = $STANZAS{'xcat-service-nodes'}->{'starting-ip'};
	if ($startip && isIP($startip)) {
		my ($ipbase, $ipstart) = $startip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
		# take the number from the nodename, and as it increases, increase the ip addr
		my $regex = '|\S+?(\d+)$|' . "$ipbase.($ipstart+" . '$1' . "-$startnum)|";
		my %hash = (ip => $regex);
		my $otherint = $STANZAS{'xcat-service-nodes'}->{'otherinterfaces'};
		if ($otherint) {
			# need to replace each ip addr in otherinterfaces with a regex
			my @ifs = split(/[\s,]+/, $otherint);
			foreach my $if (@ifs) {
				my ($nic, $startip) = split(/:/, $if);
				if (!isIP($startip)) { next; }
				($ipbase, $ipstart) = $startip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
				$if = "$nic:$ipbase.($ipstart+" . '$1' . "-$startnum)";
			}
			$regex = '|\S+?(\d+)$|' . join(',', @ifs) . '|';
			#print "regex=$regex\n";
			$hash{otherinterfaces} = $regex;
		}
		
		$tables{'hosts'}->setNodeAttribs('service', \%hash);
	}
	
	# Write regex for: ppc.id, nodetype.nodetype, etc.
	$tables{'ppc'}->setNodeAttribs('service', {id => '1', nodetype => 'lpar'});
	$tables{'nodetype'}->setNodeAttribs('service', {nodetype => 'osi', arch => 'ppc64'});
	$tables{'nodehm'}->setNodeAttribs('service', {mgt => 'fsp', cons => 'fsp'});
	$tables{'noderes'}->setNodeAttribs('service', {netboot => 'yaboot'});
	$tables{'servicenode'}->setNodeAttribs('service', {nameserver=>1, dhcpserver=>1, tftpserver=>1, nfsserver=>1, conserver=>1, monserver=>1, ftpserver=>1, nimserver=>1, ipforward=>1});
	if ($STANZAS{'ll-config'}->{'central_manager_list'}) {		# write the LL postscript for service nodes
		addPostscript('service', 'llserver.sh')
	}
	
	# Figure out what cec each sn is in and write ppc.hcp and ppc.parent
	# Math for SN in BB:  cecnum = ( ( (snnum-1) / snsperbb) * cecsperbb) + cecstart-1 + snpositioninbb
	my $cecsperbb = $STANZAS{'xcat-building-blocks'}->{'num-cecs-per-bb'};
	if ($cecsperbb !~ /^\d+$/) { errormsg("invalid non-integer value for num-cecs-per-bb: $cecsperbb", 7); return 0; }
	my $snsperbb = $STANZAS{'xcat-service-nodes'}->{'num-service-nodes-per-bb'};
	if ($snsperbb !~ /^\d+$/) { errormsg("invalid non-integer value for num-service-nodes-per-bb: $snsperbb", 7); return 0; }
	my @positions = split(/[\s,]+/, $STANZAS{'xcat-service-nodes'}->{'cec-positions-in-bb'});
	if (scalar(@positions) != $snsperbb) { errormsg("invalid number of positions specified for xcat-service-nodes:cec-positions-in-bb.", 3); return 0; }
	my $cechash = parsenoderange($STANZAS{'xcat-cecs'}->{'hostname-range'});
	my $cecbase = $$cechash{'primary-base'};
	my $cecstart = $$cechash{'primary-start'};
	my $ceclen = length($$cechash{'primary-start'});
	# these are only needed for names like f2c3
	my $secbase = $$cechash{'secondary-base'};
	my $secstart = $$cechash{'secondary-start'};
	my $secend = $$cechash{'secondary-end'};
	my $seclen = length($$cechash{'secondary-start'});
	$nodes = [noderange($range, 0)];
	my %nodehash;
	my %nodeposhash;
	my %grouphash;
	# Go thru each service node and calculate which cec it is in
	for (my $i=0; $i<scalar(@$nodes); $i++) {
		# figure out the BB num to add this node to that group
		my $bbnum = int($i/$snsperbb) + 1;
		my $bbname = "bb$bbnum";
		$grouphash{$$nodes[$i]} = {groups => "${bbname}service,service,lpar,all"};
		# figure out the CEC num
		my $snpositioninbb = $positions[$i % $snsperbb];		# the offset within the BB
		my $cecnum = ( int($i/$snsperbb) * $cecsperbb) + $snpositioninbb;		# which cec num, counting from the beginning
		my $cecname;
		if (!$secbase) {
			$cecname = $cecbase . sprintf("%0${ceclen}d", $cecnum);
		}
		else {		# calculate the 2 indexes for a name like f2c3
			# we essentially have to do base n math, where n is the size of the second range
			my $n = $secend - $secstart + 1;
			my $primary = int(($cecnum-1) / $n) + 1;
			my $secondary = ($cecnum-1) % $n + 1;
			$cecname = $cecbase . sprintf("%0${ceclen}d", $primary) . $secbase . sprintf("%0${seclen}d", $secondary);
		}
		#print "sn=$$nodes[$i], cec=$cecname\n";
		$nodehash{$$nodes[$i]} = {hcp => $cecname, parent => $cecname};
		#print Dumper($CECPOSITIONS);
		#print "cecname=$cecname\n";
		$nodeposhash{$$nodes[$i]} = {rack => $CECPOSITIONS->{$cecname}->[0]->{rack}, u => $CECPOSITIONS->{$cecname}->[0]->{u}};
	}
	$tables{'ppc'}->setNodesAttribs(\%nodehash);
	$tables{'nodelist'}->setNodesAttribs(\%grouphash);
	$tables{'nodepos'}->setNodesAttribs(\%nodeposhash);
	
	# Create dynamic groups for the nodes in each service node
	$nodes = [noderange($range, 0)];		# the setNodesAttribs() function blanks out the nodes array
	dynamicGroups('add', $nodes, 'xcatmaster==');
	return 1;
}

# Create storage node definitions
sub writestorage {
	my $range = shift;
	if (defined($STANZAS{'xcat-lpars'}->{'hostname-range'})) { errormsg("Can not define hostname-range in both the xcat-lpars and xcat-storage-nodes stanzas.", 8); return 0; }
	my $nodes = [noderange($range, 0)];
	if (!scalar(@$nodes)) { return 1; }
	if ($DELETENODES) {
		deletenodes('storage nodes', $range);
		deletegroup('storage');
		return 1;
	}
	infomsg('Defining storage nodes...');
	my $rangeparts = parsenoderange($range);
	my ($startnum) = $$rangeparts{'primary-start'};		# save this value for later
	$tables{'nodelist'}->setNodesAttribs($nodes, { groups => 'storage,lpar,all' });
	staticGroup('storage');
	
	# Write regex for: hosts.node, hosts.ip
	my $startip = $STANZAS{'xcat-storage-nodes'}->{'starting-ip'};
	if ($startip && isIP($startip)) {
		my ($ipbase, $ipstart) = $startip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
		# take the number from the nodename, and as it increases, increase the ip addr
		my $regex = '|\S+?(\d+)$|' . "$ipbase.($ipstart+" . '$1' . "-$startnum)|";
		my %hash = (ip => $regex);
		my $otherint = $STANZAS{'xcat-storage-nodes'}->{'otherinterfaces'};
		if ($otherint) {
			# need to replace each ip addr in otherinterfaces with a regex
			my @ifs = split(/[\s,]+/, $otherint);
			foreach my $if (@ifs) {
				my ($nic, $startip) = split(/:/, $if);
				if (!isIP($startip)) { next; }
				($ipbase, $ipstart) = $startip =~/^(\d+\.\d+\.\d+)\.(\d+)$/;
				$if = "$nic:$ipbase.($ipstart+" . '$1' . "-$startnum)";
			}
			$regex = '|\S+?(\d+)$|' . join(',', @ifs) . '|';
			#print "regex=$regex\n";
			$hash{otherinterfaces} = $regex;
		}
		my $aliases = $STANZAS{'xcat-storage-nodes'}->{'aliases'};
		if ($aliases) {
			# support more than 1 alias
			my @alist = split(/[\s,]+/, $aliases);
			foreach my $a (@alist) { if ($a=~/^-/) { $a = '($1)' . $a; } }	# prepend the hostname
			$regex = '|(.+)|' . join(',', @alist) . '|';
			$hash{hostnames} = $regex;
		}
		
		$tables{'hosts'}->setNodeAttribs('storage', \%hash);
	}
	
	# Write ppc.id, nodetype.nodetype, etc.
	$tables{'ppc'}->setNodeAttribs('storage', {id => '1', nodetype => 'lpar'});
	$tables{'nodetype'}->setNodeAttribs('storage', {nodetype => 'osi', arch => 'ppc64'});
	$tables{'nodehm'}->setNodeAttribs('storage', {mgt => 'fsp', cons => 'fsp'});
	$tables{'noderes'}->setNodeAttribs('storage', {netboot => 'yaboot'});
	
	# Figure out what cec each storage node is in and write ppc.hcp, ppc.parent, noderes.xcatmaster, noderes.servicenode
	# Math for SN in BB:  cecnum = ( ( (snnum-1) / snsperbb) * cecsperbb) + cecstart-1 + snpositioninbb
	my $cecsperbb = $STANZAS{'xcat-building-blocks'}->{'num-cecs-per-bb'};
	if ($cecsperbb !~ /^\d+$/) { errormsg("invalid non-integer value for num-cecs-per-bb: $cecsperbb", 7); return 0; }
	my $snsperbb = $STANZAS{'xcat-storage-nodes'}->{'num-storage-nodes-per-bb'};
	if ($snsperbb !~ /^\d+$/) { errormsg("invalid non-integer value for num-storage-nodes-per-bb: $snsperbb", 7); return 0; }
	my @positions = split(/[\s,]+/, $STANZAS{'xcat-storage-nodes'}->{'cec-positions-in-bb'});
	if (scalar(@positions) != $snsperbb) { errormsg("invalid number of positions specified for xcat-storage-nodes:cec-positions-in-bb.", 3); return 0; }
	my $cechash = parsenoderange($STANZAS{'xcat-cecs'}->{'hostname-range'});
	my $cecbase = $$cechash{'primary-base'};
	my $cecstart = $$cechash{'primary-start'};
	my $ceclen = length($$cechash{'primary-start'});
	# these are only needed for names like f2c3
	my $secbase = $$cechash{'secondary-base'};
	my $secstart = $$cechash{'secondary-start'};
	my $secend = $$cechash{'secondary-end'};
	my $seclen = length($$cechash{'secondary-start'});
	my $sns = [noderange($STANZAS{'xcat-service-nodes'}->{'hostname-range'}, 0)];
	$nodes = [noderange($range, 0)];
	my %nodehash;
	my %nodeposhash;
	my %grouphash;
	my %nodereshash;
	# Go thru each storage node and calculate which cec it is in
	for (my $i=0; $i<scalar(@$nodes); $i++) {
		# figure out the BB num to add this node to that group
		my $bbnum = int($i/$snsperbb) + 1;
		my $bbname = "bb$bbnum";
		$grouphash{$$nodes[$i]} = {groups => "${bbname}storage,lpar,storage,all"};
		# figure out the CEC num
		my $snpositioninbb = $positions[$i % $snsperbb];		# the offset within the BB
		my $cecnum = ( int($i/$snsperbb) * $cecsperbb) + $snpositioninbb;		# which cec num, counting from the beginning
		my $cecname;
		if (!$secbase) {
			$cecname = $cecbase . sprintf("%0${ceclen}d", $cecnum);
		}
		else {		# calculate the 2 indexes for a name like f2c3
			# we essentially have to do base n math, where n is the size of the second range
			my $n = $secend - $secstart + 1;
			my $primary = int(($cecnum-1) / $n) + 1;
			my $secondary = ($cecnum-1) % $n + 1;
			$cecname = $cecbase . sprintf("%0${ceclen}d", $primary) . $secbase . sprintf("%0${seclen}d", $secondary);
		}
		#print "sn=$$nodes[$i], cec=$cecname\n";
		$nodehash{$$nodes[$i]} = {hcp => $cecname, parent => $cecname};
		$nodeposhash{$$nodes[$i]} = {rack => $CECPOSITIONS->{$cecname}->[0]->{rack}, u => $CECPOSITIONS->{$cecname}->[0]->{u}};
		
		# Now determine the service node this storage node is under
		#my $bbnum = int(($cecnum-1) / $cecsperbb) + 1;
		my $cecinthisbb = ($cecnum-1) % $cecsperbb + 1;
		my $servsperbb = $STANZAS{'xcat-service-nodes'}->{'num-service-nodes-per-bb'};
		#todo: handle case where this does not divide evenly
		my $cecspersn = int($cecsperbb / $servsperbb); 
		my $snoffset = int(($cecinthisbb-1) / $cecspersn) + 1;
		my $snsbeforethisbb = ($bbnum-1) * $servsperbb;
		my $snnum = $snsbeforethisbb + $snoffset;
		my $snname = $$sns[$snnum-1];
		# generate a list of the other SNs in this BB
		my $othersns;
		for (my $s=$snsbeforethisbb+1; $s<=$snsbeforethisbb+$servsperbb; $s++) {
			if ($s != $snnum) { $othersns .= ',' . $$sns[$s-1]; }
		}
		$nodereshash{$$nodes[$i]} = {xcatmaster => $snname, servicenode => "$snname$othersns"};
	}
	$tables{'ppc'}->setNodesAttribs(\%nodehash);
	$tables{'nodelist'}->setNodesAttribs(\%grouphash);
	$tables{'noderes'}->setNodesAttribs(\%nodereshash);
	$tables{'nodepos'}->setNodesAttribs(\%nodeposhash);
	return 1;
}


# Create compute node definitions
sub writecompute {
	my $range = shift;
	if (defined($STANZAS{'xcat-lpars'}->{'hostname-range'})) { errormsg("Can not define hostname-range in both the xcat-lpars and xcat-storage-nodes stanzas.", 8); return 0; }
	my $nodes = [noderange($range, 0)];
	if (!scalar(@$nodes)) { return 1; }
	if ($DELETENODES) {
		deletenodes('compute nodes', $range);
		deletegroup('compute');
		return 1;
	}
	infomsg('Defining compute nodes...');
	$tables{'nodelist'}->setNodesAttribs($nodes, { groups => 'compute,lpar,all' });
	staticGroup('compute');
	
	# Write regex for: hosts.node, hosts.ip
	my $nodehash = parsenoderange($range);
	my $startip = $STANZAS{'xcat-compute-nodes'}->{'starting-ip'};
	if ($startip && isIP($startip)) {
		my ($ipbase, $ip3rd, $ip4th) = $startip =~/^(\d+\.\d+)\.(\d+)\.(\d+)$/;
		# take the number from the nodename, and as it increases, increase the ip addr
		my $startnum = $$nodehash{'primary-start'};
		# Math for 4th field:  (ip4th-1+nodenum-startnum)%254 + 1
		# Math for 3rd field:  (ip4th-1+nodenum-startnum)/254 + ip3rd
		my $regex = '|\S+?(\d+)$|' . "$ipbase.((${ip4th}-1+" . '$1' . "-$startnum)/254+$ip3rd).((${ip4th}-1+" . '$1' . "-$startnum)%254+1)|";
		#my $regex = '|\D+(\d+)|' . "$ipbase.($ipstart+" . '$1' . "-$startnum)|";
		my %hash = (ip => $regex);
		my $otherint = $STANZAS{'xcat-compute-nodes'}->{'otherinterfaces'};
		if ($otherint) {
			# need to replace each ip addr in otherinterfaces with a regex
			my @ifs = split(/[\s,]+/, $otherint);
			foreach my $if (@ifs) {
				my ($nic, $startip) = split(/:/, $if);
				if (!isIP($startip)) { next; }
				($ipbase, $ip3rd, $ip4th) = $startip =~/^(\d+\.\d+)\.(\d+)\.(\d+)$/;
				#$if = "$nic:$ipbase.($ipstart+" . '$1' . "-$startnum)";
				$if = "$nic:$ipbase.((${ip4th}-1+" . '$1' . "-$startnum)/254+$ip3rd).((${ip4th}-1+" . '$1' . "-$startnum)%254+1)";
			}
			$regex = '|\S+?(\d+)$|' . join(',', @ifs) . '|';
			#print "regex=$regex\n";
			$hash{otherinterfaces} = $regex;
		}
		my $aliases = $STANZAS{'xcat-compute-nodes'}->{'aliases'};
		if ($aliases) {
			# support more than 1 alias
			my @alist = split(/[\s,]+/, $aliases);
			foreach my $a (@alist) { if ($a=~/^-/) { $a = '($1)' . $a; } }	# prepend the hostname
			$regex = '|(.+)|' . join(',', @alist) . '|';
			$hash{hostnames} = $regex;
		}
		
		$tables{'hosts'}->setNodeAttribs('compute', \%hash);
	}
	
	# Write regex for: nodetype.nodetype, etc.
	$tables{'ppc'}->setNodeAttribs('compute', {nodetype => 'lpar'});
	$tables{'nodetype'}->setNodeAttribs('compute', {nodetype => 'osi', arch => 'ppc64'});
	$tables{'nodehm'}->setNodeAttribs('compute', {mgt => 'fsp', cons => 'fsp'});
	$tables{'noderes'}->setNodeAttribs('compute', {netboot => 'yaboot'});
	if ($STANZAS{'ll-config'}->{'central_manager_list'}) {		# write the LL postscript for compute nodes
		addPostscript('compute', 'llcompute.sh');
	}
	
	# Figure out what cec each compute node is in and write ppc.hcp, ppc.parent, ppc.id, noderes.xcatmaster, noderes.servicenode
	my $cecsperbb = $STANZAS{'xcat-building-blocks'}->{'num-cecs-per-bb'};
	if ($cecsperbb !~ /^\d+$/) { errormsg("invalid non-integer value for num-cecs-per-bb: $cecsperbb", 7); return 0; }
	my $lparspercec = $STANZAS{'xcat-lpars'}->{'num-lpars-per-cec'};
	if ($lparspercec !~ /^\d+$/) { errormsg("invalid non-integer value for num-lpars-per-cec: $lparspercec", 7); return 0; }
	my $snsperbb = $STANZAS{'xcat-service-nodes'}->{'num-service-nodes-per-bb'};
	# store the positions of service and storage nodes, so we can avoid those
	my %snpositions;
	my @positions = split(/[\s,]+/, $STANZAS{'xcat-service-nodes'}->{'cec-positions-in-bb'});
	foreach (@positions) { $snpositions{$_} = 1; }
	@positions = split(/[\s,]+/, $STANZAS{'xcat-storage-nodes'}->{'cec-positions-in-bb'});
	foreach (@positions) { $snpositions{$_} = 1; }
	my $cecs = [noderange($STANZAS{'xcat-cecs'}->{'hostname-range'}, 0)];
	my $sns = [noderange($STANZAS{'xcat-service-nodes'}->{'hostname-range'}, 0)];
	$nodes = [noderange($range, 0)];
	my %nodehash;
	my %nodeposhash;
	my %nodereshash;
	# set these incrementers to the imaginary position just before the 1st position
	my $cecnum = 0;
	my $lparid = $lparspercec;
	# Go thru each compute node and calculate which cec it is in
	for (my $i=0; $i<scalar(@$nodes); $i++) {
		if ($lparid >= $lparspercec) { $cecnum++; $lparid=1; }	# at the end of the cec
		else { $lparid++ }
		if ($lparid == 1) {		# check if this is a service or storage node position
			my $pos = ($cecnum-1) % $cecsperbb + 1;
			if ($snpositions{$pos}) {
				if ($lparid >= $lparspercec) { $cecnum++; $lparid=1; }	# at the end of the cec
				else { $lparid++ }
			}
		}
		my $cecname = $$cecs[$cecnum-1];
		my $id = $lparid;
		if ($lparspercec == 8) {
			#todo: for now assume 8 means a p7 IH.  Make a different way to determine this is a p7 IH
			$id = ( ($lparid-1) * 4) + 1;
		}
		#print "sn=$$nodes[$i], cec=$cecname\n";
		$nodehash{$$nodes[$i]} = {hcp => $cecname, parent => $cecname, id => $id};
		$nodeposhash{$$nodes[$i]} = {rack => $CECPOSITIONS->{$cecname}->[0]->{rack}, u => $CECPOSITIONS->{$cecname}->[0]->{u}};
		
		# Now determine the service node this compute node is under
		my $bbnum = int(($cecnum-1) / $cecsperbb) + 1;
		my $cecinthisbb = ($cecnum-1) % $cecsperbb + 1;
		#todo: handle case where this does not divide evenly
		my $cecspersn = int($cecsperbb / $snsperbb); 
		my $snoffset = int(($cecinthisbb-1) / $cecspersn) + 1;
		my $snsbeforethisbb = ($bbnum-1) * $snsperbb;
		my $snnum = $snsbeforethisbb + $snoffset;
		my $snname = $$sns[$snnum-1];
		# generate a list of the other SNs in this BB
		my $othersns;
		for (my $s=$snsbeforethisbb+1; $s<=$snsbeforethisbb+$snsperbb; $s++) {
			if ($s != $snnum) { $othersns .= ',' . $$sns[$s-1]; }
		}
		$nodereshash{$$nodes[$i]} = {xcatmaster => $snname, servicenode => "$snname$othersns"};
	}
	$tables{'ppc'}->setNodesAttribs(\%nodehash);
	$tables{'noderes'}->setNodesAttribs(\%nodereshash);
	$tables{'nodepos'}->setNodesAttribs(\%nodeposhash);
	return 1;
}


# Parse a noderange like n01-n20, n[01-20], or f[1-2]c[01-10].
# Returns a hash that contains:  primary-base, primary-start, primary-end, primary-pad, secondary-base, secondary-start, secondary-end, secondary-pad
sub parsenoderange {
	my $nr = shift;
	my $ret = {};
	
    # Check for a 3 square bracket range, e.g. f[1-2]c[01-10]p[1-8]a
	if ( $nr =~ /^\s*(\S+?)\[(\d+)[\-\:](\d+)\](\S+?)\[(\d+)[\-\:](\d+)\](\S+?)\[(\d+)[\-\:](\d+)\](\S+?)\s*$/ ) {
		($$ret{'primary-base'}, $$ret{'primary-start'}, $$ret{'primary-end'}, $$ret{'secondary-base'}, $$ret{'secondary-start'}, $$ret{'secondary-end'}, $$ret{'tertiary-base'}, $$ret{'tertiary-start'}, $$ret{'tertiary-end'}, $$ret{'attach'}) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);
		if ( (length($$ret{'primary-start'}) != length($$ret{'primary-end'})) || (length($$ret{'secondary-start'}) != length($$ret{'secondary-end'})) || (length($$ret{'tertiary-start'}) != length($$ret{'tertiary-end'})) ) { errormsg("invalid noderange format: $nr. The beginning and ending numbers of the range must have the same number of digits.", 5); return undef; }
		if ( ($$ret{'primary-start'} != 1) || ($$ret{'secondary-start'} != 1) || ($$ret{'tertiary-start'} != 1) ) { errormsg("invalid noderange format: $nr. Currently noderanges must start at 1.", 5); return undef; }
		return $ret;
	}
    
	# Check for a 3 square bracket range, e.g. f[1-2]c[01-10]p[1-8]
	if ( $nr =~ /^\s*(\S+?)\[(\d+)[\-\:](\d+)\](\S+?)\[(\d+)[\-\:](\d+)\](\S+?)\[(\d+)[\-\:](\d+)\]\s*$/ ) {
		($$ret{'primary-base'}, $$ret{'primary-start'}, $$ret{'primary-end'}, $$ret{'secondary-base'}, $$ret{'secondary-start'}, $$ret{'secondary-end'}, $$ret{'tertiary-base'}, $$ret{'tertiary-start'}, $$ret{'tertiary-end'}) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
		if ( (length($$ret{'primary-start'}) != length($$ret{'primary-end'})) || (length($$ret{'secondary-start'}) != length($$ret{'secondary-end'})) || (length($$ret{'tertiary-start'}) != length($$ret{'tertiary-end'})) ) { errormsg("invalid noderange format: $nr. The beginning and ending numbers of the range must have the same number of digits.", 5); return undef; }
		if ( ($$ret{'primary-start'} != 1) || ($$ret{'secondary-start'} != 1) || ($$ret{'tertiary-start'} != 1) ) { errormsg("invalid noderange format: $nr. Currently noderanges must start at 1.", 5); return undef; }
		return $ret;
	}
	
	# Check for a 2 square bracket range, e.g. f[1-2]c[01-10]a
	if ( $nr =~ /^\s*(\S+?)\[(\d+)[\-\:](\d+)\](\S+?)\[(\d+)[\-\:](\d+)\](\S+?)\s*$/ ) {
		($$ret{'primary-base'}, $$ret{'primary-start'}, $$ret{'primary-end'}, $$ret{'secondary-base'}, $$ret{'secondary-start'}, $$ret{'secondary-end'}, $$ret{'attach'}) = ($1, $2, $3, $4, $5, $6, $7);
		if ( (length($$ret{'primary-start'}) != length($$ret{'primary-end'})) || (length($$ret{'secondary-start'}) != length($$ret{'secondary-end'})) ) { errormsg("invalid noderange format: $nr. The beginning and ending numbers of the range must have the same number of digits.", 5); return undef; }
		if ( ($$ret{'primary-start'} != 1) || ($$ret{'secondary-start'} != 1) ) { errormsg("invalid noderange format: $nr. Currently noderanges must start at 1.", 5); return undef; }
		return $ret;
	}
    
	# Check for a 2 square bracket range, e.g. f[1-2]c[01-10]
	if ( $nr =~ /^\s*(\S+?)\[(\d+)[\-\:](\d+)\](\S+?)\[(\d+)[\-\:](\d+)\]\s*$/ ) {
		($$ret{'primary-base'}, $$ret{'primary-start'}, $$ret{'primary-end'}, $$ret{'secondary-base'}, $$ret{'secondary-start'}, $$ret{'secondary-end'}) = ($1, $2, $3, $4, $5, $6);
		if ( (length($$ret{'primary-start'}) != length($$ret{'primary-end'})) || (length($$ret{'secondary-start'}) != length($$ret{'secondary-end'})) ) { errormsg("invalid noderange format: $nr. The beginning and ending numbers of the range must have the same number of digits.", 5); return undef; }
		if ( ($$ret{'primary-start'} != 1) || ($$ret{'secondary-start'} != 1) ) { errormsg("invalid noderange format: $nr. Currently noderanges must start at 1.", 5); return undef; }
		return $ret;
	}
	
	# Check for a square bracket range, e.g. n[01-20]a
	if ( $nr =~ /^\s*(\S+?)\[(\d+)[\-\:](\d+)\](\S+?)\s*$/ ) {
		($$ret{'primary-base'}, $$ret{'primary-start'}, $$ret{'primary-end'}, $$ret{'attach'}) = ($1, $2, $3, $4);
		if (length($$ret{'primary-start'}) != length($$ret{'primary-end'})) { errormsg("invalid noderange format: $nr. The beginning and ending numbers of the range must have the same number of digits.", 5); return undef; }
		if ($$ret{'primary-start'} != 1) { errormsg("invalid noderange format: $nr. Currently noderanges must start at 1.", 5); return undef; }
		return $ret;
	}
    
	# Check for a square bracket range, e.g. n[01-20]
	if ( $nr =~ /^\s*(\S+?)\[(\d+)[\-\:](\d+)\]\s*$/ ) {
		($$ret{'primary-base'}, $$ret{'primary-start'}, $$ret{'primary-end'}) = ($1, $2, $3);
		if (length($$ret{'primary-start'}) != length($$ret{'primary-end'})) { errormsg("invalid noderange format: $nr. The beginning and ending numbers of the range must have the same number of digits.", 5); return undef; }
		if ($$ret{'primary-start'} != 1) { errormsg("invalid noderange format: $nr. Currently noderanges must start at 1.", 5); return undef; }
		return $ret;
	}
	
	# Check for normal range, e.g. n01a-n20a
	my $base2;
	if ( $nr =~ /^\s*(\S+?)(\d+)(\S+?)\-(\S+?)(\d+)(\S+?)\s*$/ ) {
        ($$ret{'primary-base'}, $$ret{'primary-start'},  $$ret{'attach'}, $base2, $$ret{'primary-end'}, $$ret{'attach2'}) = ($1, $2, $3, $4, $5, $6);
		if ($$ret{'primary-base'} ne $base2) { errormsg("invalid noderange format: $nr", 5); return undef; }
		if (length($$ret{'primary-start'}) != length($$ret{'primary-end'})) { errormsg("invalid noderange format: $nr. The beginning and ending numbers of the range must have the same number of digits.", 5); return undef; }
		if ($$ret{'primary-start'} != 1) { errormsg("invalid noderange format: $nr. Currently noderanges must start at 1.", 5); return undef; }
		return $ret;
	}
    
	# Check for normal range, e.g. n01-n20
	my $base2;
	if ( $nr =~ /^\s*(\S+?)(\d+)\-(\S+?)(\d+)\s*$/ ) {
		($$ret{'primary-base'}, $$ret{'primary-start'}, $base2, $$ret{'primary-end'}) = ($1, $2, $3, $4);
		if ($$ret{'primary-base'} ne $base2) { errormsg("invalid noderange format: $nr", 5); return undef; }
		if (length($$ret{'primary-start'}) != length($$ret{'primary-end'})) { errormsg("invalid noderange format: $nr. The beginning and ending numbers of the range must have the same number of digits.", 5); return undef; }
		if ($$ret{'primary-start'} != 1) { errormsg("invalid noderange format: $nr. Currently noderanges must start at 1.", 5); return undef; }
		return $ret;
	}
	
	# It may be a simple single nodename
	if ( $nr =~ /^\s*([^\[\]\-\:\s]+?)(\d+)\s*$/ ) {
		($$ret{'primary-base'}, $$ret{'primary-start'}, $$ret{'primary-end'}) = ($1, $2, $2);
		return $ret;
	}
	
	errormsg("invalid noderange format: $nr", 5);
	return undef;   # range did not match any of the cases above
}


# Verify this is valid IP address format (ipv4 only for right now).
# If not, print error msg and return 0.
sub isIP {
	my $ip = shift;
	if ($ip =~ /^\s*\d+\.\d+\.\d+\.\d+\s*$/) { return 1; }
	errormsg("invalid IP address format: $ip", 6);
	return 0;
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

sub deletenodes {
	my ($name, $range) = @_;
	if ($range !~ /\S/) { return; }
	infomsg("Deleting $name...");
	rmdef($range);
	return;
}

sub deletegroup {
	my $group = shift;
	if ($group !~ /\S/) { return; }
	#print "group=$group\n";
	my $ret = xCAT::Utils->runxcmd({ command => ['rmdef'], arg => ['-t','group','--nocache','-o',$group] }, $SUB_REQ, 0, 1);
	if ($$ret[0] !~ /^Object definitions have been removed\.$/) { xCAT::MsgUtils->message('D', {data=>$ret}, $CALLBACK); }
}

sub rmdef {
	my $range = shift;
	if ($range !~ /\S/) { return; }
	#print "deleting $range\n";
	my $ret = xCAT::Utils->runxcmd({ command => ['rmdef'], arg => ['-t','node','--nocache','-o',$range] }, $SUB_REQ, 0, 1);
	#print Dumper($ret);
	if ($$ret[0] !~ /^Object definitions have been removed\.$/ && $$ret[0] !~ /^Could not find an object named/) { xCAT::MsgUtils->message('D', {data=>$ret}, $CALLBACK); }
	#$CALLBACK->({data=>$ret});
}

sub noderm {
	my $range = shift;
	if ($range !~ /\S/) { return; }
	#print "noderm $range\n";
	my $ret = xCAT::Utils->runxcmd({ command => ['noderm'], noderange => [$range] }, $SUB_REQ, 0, 1);
	xCAT::MsgUtils->message('D', {data=>$ret}, $CALLBACK);
}


# Create or delete dynamic groups for the given node list
sub dynamicGroups {
	my ($action, $nodes, $where) = @_;
	#my $ntab = xCAT::Table->new('nodegroup', -create=>1,-autocommit=>0);
	#if (!$ntab) { errormsg("Can not open nodegroup table in database.", 3);  return; }
	my $ntab = $tables{'nodegroup'};
	foreach my $n (@$nodes) {
		if ($action ne 'delete') {
			#print "adding group ${n}nodes with $where$n\n";
			$ntab->setAttribs({groupname => "${n}nodes"}, {grouptype => 'dynamic', members => 'dynamic', wherevals => "$where$n" });
		} else {
			$ntab->delEntries({groupname => "${n}nodes"});
		}
	}
	$ntab->commit();
	#$ntab->close();
}

sub staticGroup {
	my $group = shift;
	$tables{'nodegroup'}->setAttribs({groupname => $group}, {grouptype => 'static', members => 'static'});	# this makes rmdef happier
	$tables{'nodegroup'}->commit();
}

sub addPostscript {
	my ($group, $postscript) = @_;
	my $ref = $tables{'postscripts'}->getNodeAttribs($group, 'postscripts');
	#print Dumper($ref);
	my $posts;
	if ($ref && $ref->{postscripts}=~/\S/) {
		$posts = $ref->{postscripts};
		if ($posts !~ /(^|,)llserver\.sh(,|$)/) { $posts .= ",$postscript"; }
	}
	else { $posts = "$postscript"; }
	$tables{'postscripts'}->setNodeAttribs($group, {postscripts => $posts });
}

1;
