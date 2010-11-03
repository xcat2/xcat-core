# Allows for nodes that don't have rsyslog set up to remotely log messages
# to the xCAT management server.
# this is primarily used for the xCAT runimage=http://.... commands where
# the xCAT boot kernel can run remote commands.  In this case you may want 
# to log messages to the syslog so we can view what is happening on our nodes.
#
# In particular, if we had a remote image that had a bunch of firmware flashes
# then we want to let the syslog know that we're updating them all.
#
# To use this function do the following.  
# 1.  update policy table to add the commands:
# ours is set like this:
# "4.9",,,"xcatlogmsg",,,,"allow",,
# "4.10",,,"xcatlogerr",,,,"allow",,
#
# 2.  Use a cool awk script to send the message on whatever host you have.
# in our case we created an awk script called: xcatremotelog.awk
# #!/usr/bin/awk -f
# BEGIN {
#  localport = 301
#  type = ARGV[1] # the type can be error or warn or just log
#  msg = ARGV[2]  # this is the message
#
#  if (type == "err" ) {
#        cmd = "xcatlogerr"
#  }else{
#        cmd = "xcatlogmsg"
#  }
#
#  ns = "/inet/tcp/0/127.0.0.1/" localport
#  canexit = 0
#
#  print "<xcatrequest>" |& ns
#  print "<command>"  cmd  "</command>" |& ns
#  print "<arg>" msg "</arg>" |& ns
#  print "</xcatrequest>" |& ns
#
#  close(ns)
#  exit 0
#}
#
# 3.  In whatever script you want to log in create two functions:
# #!/bin/sh
#
#log()
#{
#        xcatremotelog.awk log "$1"
#}
#
#err() 
#{
#        xcatremotelog.awk err "$1"
#}
# log "This is a message a node will send to the xCAT masternode syslog" 
# err "This is an error a node will send to the xCAT masternode syslog" 
# QED

package xCAT_plugin::logger;
use strict;
use xCAT::NodeRange qw/noderange/;
use xCAT::Utils;
use Sys::Syslog;



##########################################################################
# Command handler method from tables
##########################################################################
sub handled_commands {
  return {
	'xcatlogmsg' => "logger",
	'xcatlogerr' => "logger",
  } 
}

##########################################################################
# Process request from xCat daemon
##########################################################################
sub process_request {
	my $request = shift;
	my $callback = shift;
	my $noderange;
	my $image;
	# the request can come from node or some one running command
	# on xCAT mgmt server
	# argument could also be image...

	# if request comes from user:
	if($request->{node}){
		$noderange = $request->{node};
		
	# if request comes from node post script .awk file.
	}elsif($request->{'_xcat_clienthost'}){
		$noderange = $request->{'_xcat_clienthost'};
	}else{
		$callback->({error=>["No node names are given. I can't figure out who you are."],errorcode=>[1]});
		return;
	}

	if(!$noderange){
		my $usage_string="Missing Noderange\n";
		$callback->({error=>[$usage_string],errorcode=>[1]});
		$request = {};
		return;
	}
	my $command = $request->{command}->[0];
	if($command eq "xcatlogmsg"){
		return logmsg("log",$request,$callback,$noderange);
	}elsif($command eq "xcatlogerr"){
		return logmsg("err",$request, $callback,$noderange);
	}else{
		$callback->({error=>["this logging code is not supported"], errorcode=>[127]});
		$request = {};
		return;
	}
}

sub logmsg{
	my $type = shift;
	if ($type eq 'err') {
		$type = "ERROR: ";	
	}else{
		$type = "";
	}
	my $req = shift;
	my $callback = shift;
	my $noderange = shift;
	my $arg = $req->{arg};
				
	xCAT::MsgUtils->message("S","$type" . join(',',$noderange->[0]) . ": " . join(',',$arg->[0]));
}




1;
