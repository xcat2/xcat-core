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

sub handled_commands
{
    return { webrun => "web",};
}

#sub preprocess_request
#{
#}

sub process_request
{
    my $request = shift;
    my $callback = shift;
    my $sub_req = shift;
    my %authorized_cmds = (
        #command => function
        'pping' => \&web_pping,
        'update'=> \&web_update,
        'chtab'=> \&web_chtab,
        'lscondition'=> \&web_lscond,
        'lsresponse'=> \&web_lsresp,
        'lscondresp' => \&web_lscondresp,
        'mkcondresp' => \&web_mkcondresp,
        'startcondresp' => \&web_startcondresp,
        'stopcondresp' => \&web_stopcondresp,
        'lsrsrc' => \&web_lsrsrc,
        'lsrsrcdef-api' => \&web_lsrsrcdef,
        'gettab' => \&web_gettab,
        'lsevent' => \&web_lsevent,
        'lsdef' => \&web_lsdef,
		'unlock' => \&web_unlock,

        #'xdsh' => \&web_xdsh,
        #THIS list needs to be updated
    );

    #to check whether the request is authorized or not
    split ' ', $request->{arg}->[0];
    my $cmd = $_[0];
    if(grep { $_ eq $cmd } keys %authorized_cmds) {
        my $func = $authorized_cmds{$cmd};
        $func->($request, $callback, $sub_req);
    }
    else {
        $callback->({error=>"$cmd is not authorizied!\n",errorcode=>[1]});
    }
}

sub web_lsdef {
    my ($request, $callback, $sub_req) = @_;
    print Dumper($request);

    #TODO: web_lsdef works only for "lsdef <noderange> -i nodetype"
    my $ret = `$request->{arg}->[0]`;
    my @lines = split '\n', $ret;
    
    split '=', $lines[2];
    my $ntype = $_[1];

    $callback->({data=>"$ntype"});
}

sub web_lsevent {
    my ($request, $callback, $sub_req) = @_;
    my @ret = `$request->{arg}->[0]`;

    #print Dumper(\@ret);
    #please refer the manpage for the output format of "lsevent"


    my %data = ();

    my %record = ();

    my $i = 0;
    my $j = 0;
    
    foreach my $item (@ret) {
        if($item ne "\n") {
            chomp $item;
            my ($key, $value) = split("=", $item);
            $record{$key} = $value;
            $j ++;
            if($j == 3) {
                $i++;
                $j = 0;
                while (my ($k, $v) = each %record) {
                    $data{$i}{$k} = $v;
                }
                %record = ();
            }
        }
        
    }
    #print Dumper(\%data);

    while (my ($key, $value) = each %data) {
        $callback->({data => $value});
    }
}

sub web_lsrsrcdef {
    my ($request, $callback, $sub_req) = @_;
    my $ret = `$request->{arg}->[0]`;

    my @lines = split '\n', $ret;
    shift @lines;
    print Dumper(\@lines);
    my $data = join("=", @lines);
    $callback->({data=>"$data"});

}

sub web_lsrsrc {
    my ($request, $callback, $sub_req)  = @_;
    my $ret = `$request->{arg}->[0]`;
    my @classes;

    my @lines = split '\n', $ret;
    shift @lines;
    foreach my $line(@lines) {
        my $index = index($line, '"', 1);
        push @classes, substr($line, 1, $index-1);
    }
    my $data = join("=",@classes);
    $callback->({data=>"$data"});
}



sub web_mkcondresp {
    my ($request, $callback, $sub_req) = @_;
    print Dumper($request->{arg}->[0]);#debug
    my $ret = system($request->{arg}->[0]);
    #there's no output for "mkcondresp"
    #TODO
    if($ret) {
        #failed
    }
}

sub web_startcondresp {
    my ($request, $callback, $sub_req) = @_;
    print Dumper($request->{arg}->[0]);#debug
    my $ret = system($request->{arg}->[0]);
    if($ret) {
        #to handle the failure
    }
}

sub web_stopcondresp {
    my ($request, $callback, $sub_req) = @_;
    print Dumper($request->{arg}->[0]);#debug
    my $ret = system($request->{arg}->[0]);
    if($ret) {
        #to handle the failure
    }
}

sub web_lscond {
    my ($request, $callback, $sub_req) = @_;
    my $ret = `lscondition`;
    
    my @lines  = split '\n', $ret;
    shift @lines;
    shift @lines;
    foreach my $line (@lines) {
	$callback->({data=>$line});
    }

}

sub web_lsresp {
    my ($request, $callback, $sub_req) = @_;
    my $ret = `lsresponse`;
    my @resps;

    my @lines = split '\n', $ret;
    shift @lines;
    shift @lines;

    foreach my $line (@lines) {
	$callback->({data=>$line});
    }
}

sub web_lscondresp {
    my ($request, $callback, $sub_req) = @_;
    my @ret = `lscondresp`;
    shift @ret;
    shift @ret;

    foreach my $line (@ret) {
        chomp $line;
	$callback->({data=>$line});
    }
}
# currently, web_chtab only handle chtab for the table "monitoring"
sub web_chtab {
    my ($request, $callback, $sub_req) = @_;
    split ' ', $request->{arg}->[0];
    my $tmp_str = $_[2];
    split '\.', $tmp_str;
    my $table = $_[0];   #get the table name
    if($table == "monitoring") {
        system("$request->{arg}->[0]");
    }else {
        $callback->({error=>"the table $table is not authorized!\n",errorcode=>[1]});
    }
}
 sub web_gettab {
    #right now, gettab only support the monitoring table
    my ($request, $callback, $sub_req) = @_;
    split ' ', $request->{arg}->[0];
    my $tmp_str = $_[2];
    split '\.', $tmp_str;
    my $table = $_[0];
    if($table == "monitoring") {
        my $val = `$request->{arg}->[0]`;
        chomp $val;
        $callback->({data=>$val});
    }else {
        $callback->(
            {error=>"The table $table is not authorized to get!\n",
                errorcode=>[1]});
    }
}

   

sub web_pping {
    my ($request, $callback, $sub_req) = @_;
    #treat the argument as the commandline, run it and get the return message
    my $ret = `$request->{arg}->[0]`;

    #parse the message, and use $callback to send back to the web interface

    #the message is like this:
    #  xcat_n02: ping
    #  xcat_n03: ping
    #  xcat_n51: ping
    #  xcat_n52: noping
    my @total_stat = split '\n', $ret;
    my $str;
    foreach $str(@total_stat) {
        #TODO
        split ':', $str;
        $callback->({node=>[{name=>[$_[0]],data=>[{contents=>[$_[1]]}]}]});
    }
}

sub web_update {
    my ($request, $callback, $sub_req) = @_;
    my $os = "unknow";
    my $RpmNames = $request->{arg}->[1];
    my $repository = $request->{arg}->[2];
    my $FileHandle;
    my $cmd;
    my $ReturnInfo;
    my $WebpageContent = undef;
    my $RemoteRpmFilePath = undef;
    my $LocalRpmFilePath = undef;
    if (xCAT::Utils->isLinux())
    {
        $os = xCAT::Utils->osver();
        #suse linux
        if ($os =~ /sles.*/)
        {
            $RpmNames =~ s/,/ /g;
            #create zypper command
            $cmd = "zypper -t package -r " . $repository . $RpmNames;
        }
        #redhat
        else
        {
            #check the yum config file, and delect it if exist.
            if (-e "/tmp/xCAT_update.yum.conf")
            {
                unlink("/tmp/xCAT_update.yum.conf");
            }

            #create file, return error if failed.
            unless ( open ($FileHandle, '>>', "/tmp/xCAT_update.yum.conf"))
            {
                $callback->({error=>"Create temp file eror!\n",errorcode=>[1]});
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
            $cmd = "yum -y -c /tmp/xCAT_update.yum.conf update " . $RpmNames . "\n";
        }

        #run the command and return the result
        if (0 == system($cmd))
        {
            $ReturnInfo = "update" . $RpmNames ."successful";
            $callback->({info=>$ReturnInfo});
        }
        else
        {
            $ReturnInfo = "update " . $RpmNames . "failed. detail:" . $!;
            $callback->({error=>$ReturnInfo, errorcode=>[1]});
        }
    }
    #AIX
    else
    {
        #open the rpmpath(may be error), and read the page's content
        $WebpageContent = LWP::Simple::get($repository);
        unless (defined($WebpageContent))
        {
            $callback->({error=>"open $repository error, please check!!", errorcode=>[1]});
            return;
        }

        #must support for updating several rpms.
        foreach (split (/,/, $RpmNames))
        {
            #find out rpms' corresponding rpm href on the web page
            $WebpageContent =~ m/href="($_-.*?[ppc64|noarch].rpm)/i;
            unless(defined($1))
            {
                next;
            }
            $RemoteRpmFilePath = $repository . $1;
            $LocalRpmFilePath = '/tmp/' . $1;

            #download rpm package to temp
            unless(-e $LocalRpmFilePath)
            {
                $cmd = "wget -O " . $LocalRpmFilePath . " " . $RemoteRpmFilePath;
                if(0 != system($cmd))
                {
                    $ReturnInfo = $ReturnInfo . "update " . $_ . " failed: can not download the rpm\n";
                    $callback->({error=>$ReturnInfo, errorcode=>[1]});
                    return;
                }
            }

            #update rpm by rpm packages.
            $cmd = "rpm -U " . $LocalRpmFilePath;
            $ReturnInfo = $ReturnInfo . readpipe($cmd);
        }
        $callback->({info=>$ReturnInfo});
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