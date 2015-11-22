# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle getadapters management

   Supported command:
        getadapters->getadapters 
        findadapter->getadapters 

=cut

#-------------------------------------------------------
package xCAT_plugin::getadapter;

BEGIN{   
   $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use Data::Dumper;
use Getopt::Long;
use IO::Select;
use Term::ANSIColor;
use Time::Local;

my %usage = (
    "getadapters" => "Usage:\n\tgetadapters [-h|--help|-v|--version|V]\n\tgetadapters <noderange> [-f]",
);

my $inforootdir = "/var/lib/xcat/adapters/";
my $VERBOSE=0;
#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
        getadapters => "getadapter",
        findadapter => "getadapter",
    };
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;
    my $command  = $request->{command}->[0];
	
    if ($command eq "getadapters"){
        &handle_getadapters($request, $callback, $subreq);
    }

    if ($command eq "findadapter"){
        &handle_findadapter($request, $callback);
    }
	
    return;
}

sub handle_getadapters{
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;
    my $command  = $request->{command}->[0];
	
    my @args=(); 
    my $HELP;
    my $VERSION;
    my $FORCE;
    if (ref($request->{arg})) {
        @args=@{$request->{arg}};   
    } else {    
        @args=($request->{arg});
    }
    @ARGV = @args;
    Getopt::Long::Configure("bundling");    
    Getopt::Long::Configure("no_pass_through");	
    if (!GetOptions("h|help"    => \$HELP, 
	            "v|version" => \$VERSION,
	            "f"         => \$FORCE,
	            "V"         => \$VERBOSE   
    ) ) {
        if($usage{$command}) {
            my $rsp = {};
            $rsp->{error}->[0] = $usage{$command};
            $rsp->{errorcode}->[0] = 1;
            $callback->($rsp);
        }
        return;
    }

    if ($HELP) {
        if($usage{$command}) {
            my %rsp;
            $rsp{data}->[0]=$usage{$command};
            $callback->(\%rsp);
        }
        return;
    }	
	
    if ($VERSION) {
        my $ver = xCAT::Utils->Version();
        my %rsp;
        $rsp{data}->[0]="$ver";
        $callback->(\%rsp);
        return; 
    }
	
    my $tmpnodes = join(",", @{$request->{node}});
    my $tmpargs = join(",", @args);
    xCAT::MsgUtils->trace($VERBOSE,"d","getadapters: handling command <$command $tmpnodes $tmpargs>");

    if($FORCE || ! -d $inforootdir) {
        my @tmpnodes = @{$request->{node}};
        $request->{missnode} = \@tmpnodes;
        &scan_adapters($request, $callback, $subreq);            
    }else{
        my @nodes = @{$request->{node}};
        my $node;
        my @missnodes = ();
        foreach $node (@nodes){
            if ( ! -e "$inforootdir/$node.info" || -z "$inforootdir/$node.info"){
                push @missnodes,$node;
            }  
        }
		
        if(scalar(@missnodes) != 0){
           $request->{missnode} = \@missnodes;
           &scan_adapters($request, $callback, $subreq); 
        }
    }

    &get_info_from_loacal($request, $callback); 
    return;

}

sub handle_findadapter{

    my $request  = shift;
    my $callback = shift;
    my $hostname = $request->{hostname}->[0];
	
    xCAT::MsgUtils->trace($VERBOSE,"d","getadapters: receiving a findadapter response from $hostname");	

    my $nicnum = scalar @{$request->{nic}};
    my $content = "";
    #print "-----------nicnum = $nicnum----------------\n";	 
    for (my $i = 1; $i <= $nicnum; $i++) {
        $content .= "$i:";
        if(exists($request->{nic}->[$i-1]->{interface})){
            $content .= "hitn=".$request->{nic}->[$i-1]->{interface}->[0]."|";
        }
        if(exists($request->{nic}->[$i-1]->{pcilocation})){
            $content .= "pci=".$request->{nic}->[$i-1]->{pcilocation}->[0]."|";
        }
        if(exists($request->{nic}->[$i-1]->{mac})){
            $content .= "mac=".$request->{nic}->[$i-1]->{mac}->[0]."|";
        }
        if(exists($request->{nic}->[$i-1]->{predictablename})){
            $content .= "prdn=".$request->{nic}->[$i-1]->{predictablename}->[0]."|";
        }
        if(exists($request->{nic}->[$i-1]->{vendor})){
            $content .= "vnd=".$request->{nic}->[$i-1]->{vendor}->[0];
        }
        if(exists($request->{nic}->[$i-1]->{model})){
            $content .= "mod=".$request->{nic}->[$i-1]->{model}->[0];
        }
        $content .= "\n";
    }
    $content =~ s/\n$//g;
    xCAT::Utils->runcmd("echo '$content' > $inforootdir/$hostname.info");
    return;
}

sub scan_adapters{
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;
    my @targetscannodes = @{$request->{missnode}};

    if (scalar(@{$request->{node}}) == 0){
        return 1;
    }
	
    my $tmptargetnodes = join(",", @targetscannodes);
    xCAT::MsgUtils->trace($VERBOSE,"d","getadapters: issue new scaning for $tmptargetnodes");
	
    my %autorsp;
    $autorsp{data}->[0]="-->Starting scan for: $tmptargetnodes";
    $callback->(\%autorsp);	
	
    if ( ! -d $inforootdir){
        xCAT::Utils->runcmd("mkdir -p $inforootdir");
    }
	
    my $node;
    foreach $node (@targetscannodes){
        if ( -e "$inforootdir/$node.info"){
             xCAT::Utils->runcmd("mv $inforootdir/$node.info $inforootdir/$node.info.bak");
             xCAT::MsgUtils->trace($VERBOSE,"d","getadapters: move $inforootdir/$node.info to $inforootdir/$node.info.bak");
        }  
    }

    #do scan stuff
    my $pid;
    my $forkcount = 0;
    my %pidrecord;
    foreach $node (@targetscannodes){
		
        $pid = xCAT::Utils->xfork();
        if (!defined($pid)){  
            $autorsp{info}->[0]="failed to fork process to restart $node";
            $callback->(\%autorsp);
            deletenode($request->{missnode}, "$node");
            last;
        }elsif ($pid == 0){
            # Child process
            xCAT::MsgUtils->trace($VERBOSE,"d","getadapters: fork new process $$ to start scaning $node");
           
            my $outref = xCAT::Utils->runxcmd(
                {
                    command => ['nodeset'],
                    node    => ["$node"],
                    arg     => ['runcmd=getadapter'],
                },
                ,$subreq, 0, 1);
            if($::RUNCMD_RC != 0){
                my $tmp = join(" ", @$outref);
                $autorsp{data}->[0]="$tmp";
                $callback->(\%autorsp);
                exit(1);				
            }
			
            my $tab = xCAT::Table->new("nodetype");
            my $nthash = $tab->getNodeAttribs(["$node"], ['arch']);
            $tab->close();
			
            if ($nthash->{arch} ne "ppc64"){
                $outref = xCAT::Utils->runxcmd(
                    {
                        command => ["rsetboot"],
                        node    => ["$node"],
                        arg     => ['net'],
                    },
                    ,$subreq, 0, 1); 
                if($::RUNCMD_RC != 0){
                    my $tmp = join(" ", @$outref);
                    $autorsp{data}->[0]="$tmp";
                    $callback->(\%autorsp);
                    exit(1);				
                }          
				
                $outref = xCAT::Utils->runxcmd(
                    {
                        command => ['rpower'],
                        node    => ["$node"],
                        arg     => ['reset'],
                    },
                    ,$subreq, 0, 1);
                if($::RUNCMD_RC != 0){
                    my $tmp = join(" ", @$outref);
                    $autorsp{data}->[0]="$tmp";
                    $callback->(\%autorsp);
                    exit(1);				
                }
            }else{
                $outref = xCAT::Utils->runxcmd(
                    {
                        command => ["rnetboot"],
                        node    => ["$node"],
                    },
                    ,$subreq, 0, 1);
                if($::RUNCMD_RC != 0){
                    my $tmp = join(" ", @$outref);
                    $autorsp{data}->[0]="$tmp";
                    $callback->(\%autorsp);
                    exit(1);				
                }					
            }	
            # Exit process
            exit(0);
        }
        # Parent process
        $forkcount++;
        $pidrecord{$node} = $pid;
    }

    # Wait for all processes to end
    if($forkcount == 0){
        return 1;        
    }else{
        my $cpid;
        while (($cpid=waitpid(-1,WNOHANG)) > 0) {
            my $cpr=$?;
            while(my($k,$v) = each %pidrecord){
                if($v == $cpid){
                    if($cpr>0){
                        deletenode($request->{missnode}, "$k");
                    }
                }
            }
        }
    }
    return 0;
}

sub get_info_from_loacal{
    my $request  = shift;
    my $callback = shift;
    my $retry = 60;
    my $rsp = {};
	
    push @{$rsp->{data}}, "\nThe whole scan result:";      

    if (scalar(@{$request->{node}}) == 0){
        $callback->({
            error=>[qq{Please indicate the nodes which are needed to scan}], 
            errorcode=>[1]});
        return 1;
	}

    if (exists($request->{missnode}) && (scalar(@{$request->{missnode}}) > 0)){
        my $nodenum = scalar @{$request->{missnode}}; 
        my $backnum = 0;
        while($retry && $backnum != $nodenum){
            xCAT::Utils->runcmd("sleep 10");
            $retry--;
            $backnum = 0;
            foreach $backnode (@{$request->{missnode}}){ 
                if( -e "$inforootdir/$backnode.info" ){
                    $backnum++;
                    deletenode($request->{missnode}, "$backnode");
                }				
            }			
        }
    }

    if($retry == 0){
        my $tmpnode = join(",", @{$request->{missnode}});
        xCAT::MsgUtils->trace($VERBOSE,"d","getadapters: waiting scan result time out");
        push @{$rsp->{data}}, "waiting scan result for $tmpnode time out";
    }	
	
    my $node;
    foreach $node (@{$request->{node}}){
        push @{$rsp->{data}}, "--------------------------------------";
        if ( ! -e "$inforootdir/$node.info" &&  ! -e "$inforootdir/$node.info.bak" ){
		
            #scan failed, but without old file
            push @{$rsp->{data}}, "[$node] Scan failed and without old data. there isn't data to show";
            
        }elsif( ! -e "$inforootdir/$node.info" && -e "$inforootdir/$node.info.bak" ){
		
            #scan failed, using old file
            xCAT::Utils->runcmd("mv $inforootdir/$node.info.bak $inforootdir/$node.info");
            push @{$rsp->{data}}, "[$node] Scan failed but old data exist, using the old data:";
            if( -z "$inforootdir/$node.info"){
                push @{$rsp->{data}}, "[$node] the old file is empty, nothing to show";
            }else{
                if (open($myfile, "$inforootdir/$node.info")) {
                    while ($line = <$myfile>) {
                        push @{$rsp->{data}}, "$node:$line";
                    }
                    close($myfile); 
                }else{
                    push @{$rsp->{data}}, "[$node] Can't open $inforootdir/$node.info ";
                }
            }
			
        }elsif( -e "$inforootdir/$node.info" && ! -e "$inforootdir/$node.info.bak" ){
		
            push @{$rsp->{data}}, "[$node] with no need for scan due to old data exist, using the old data:";
            if( -z "$inforootdir/$node.info"){
                push @{$rsp->{data}}, "[$node] the old file is empty, nothing to show";
            }else{
                if (open($myfile, "$inforootdir/$node.info")) {
                    while ($line = <$myfile>) {
                        push @{$rsp->{data}}, "$node:$line";
                    }
                    close($myfile); 
                }else{
                    push @{$rsp->{data}}, "[$node] Can't open $inforootdir/$node.info";
                }
            }
        }else{
            xCAT::Utils->runcmd("rm -f $inforootdir/$node.info.bak");		
            push @{$rsp->{data}}, "[$node] scan successfully, below are the latest data:";
            #scan successfully, using new file
            if (open($myfile, "$inforootdir/$node.info")) {
                while ($line = <$myfile>) {
                    push @{$rsp->{data}}, "$node:$line";
                }
                close($myfile); 
            }else{
                push @{$rsp->{data}}, "[$node] Can't open $inforootdir/$node.info";
            }	
        }		
    }	
    $callback->($rsp);	
	
    return;
}

sub deletenode{
    my $arrref = shift;
    my $targetnode = shift;
    my $arrlong = scalar @$arrref;
    my $targetindex=0;
	
    if( "$targetnode" ne "all" ){
        for (my $i = 0; $i < $arrlong; $i++){
            if ("$arrref->[$i]" eq "$targetnode"){
                $targetindex = $i;
                last;
            }
        }
        for (my $i = $targetindex; $i < $arrlong-1; $i++){
            $arrref->[$i] = $arrref->[$i+1] ;
        }
        pop @$arrref;
    }else{
        for (my $i = 0; $i < $arrlong; $i++){
            pop @$arrref;		
        }
    }
}

1;
