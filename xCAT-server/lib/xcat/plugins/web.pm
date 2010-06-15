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
    #update the xcat-web rpm package 
    #TODO
    #Note: this is not finished now!
    my $repo_dir = "/root/svn/xcat-core/trunk/aix-core-snap";
    my $REPO;
    my @flist;
    if( -d $repo_dir) {
        opendir REPO, $repo_dir;
        @flist = readdir REPO;
    }
    closedir REPO;
    #get the name of xcat-web package
    my ($file) =  grep(/^xCAT\-web/, @flist);

    system("rpm -Uvh $repo_dir/$file");#TODO:use runcmd() to replace it
}

#-------------------------------------------------------

=head3   web_unlock

	Description	: Unlock a node by exchanging its SSH keys
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