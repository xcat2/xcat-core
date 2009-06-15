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
