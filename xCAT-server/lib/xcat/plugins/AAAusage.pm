# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::AAAusage;
use strict;
use xCAT::Usage;
##########################################################################
#  Common help plugin for table-driven commands
##########################################################################

##########################################################################
# Command handler method from tables
##########################################################################
sub handled_commands {
  return {
      rnetboot  => 'AAAusage',
      rpower    => 'AAAusage',
      rbeacon	=> 'AAAusage',
      rvitals   => 'AAAusage',
      reventlog => 'AAAusage',
      rinv      => 'AAAusage',
      rsetboot  => 'AAAusage',
      rbootseq  => 'AAAusage',
      rscan     => 'AAAusage',
      rspconfig => 'AAAusage',
      getmacs   => 'AAAusage',
      mkvm      => 'AAAusage',
      lsvm      => 'AAAusage',
      chvm      => 'AAAusage',
      rmvm      => 'AAAusage',
      mkdocker  => 'AAAusage',
      lsdocker  => 'AAAusage',
      rmdocker  => 'AAAusage',
      #lsslp     => 'AAAusage',
      rflash    => 'AAAusage',
      mkhwconn  => 'AAAusage',
      rmhwconn  => 'AAAusage',
      lshwconn  => 'AAAusage',
      renergy   => 'AAAusage',
      nodeset   => 'AAAusage'
  };
}


##########################################################################
# Pre-process request from xCat daemon
##########################################################################
sub preprocess_request {
  my $request = shift;
  #if ($request->{_xcatdest}) { return [$request]; }    #exit if preprocessed

  if (($request->{_xcatpreprocessed}) and ($request->{_xcatpreprocessed}->[0] == 1) ) { return [$request]; }
  my $callback=shift;
  my @requests;

  #display usage statement if -h is present or no noderage is specified
  my $noderange = $request->{node}; #Should be arrayref
  my $command = $request->{command}->[0];
  my $extrargs = $request->{arg};
  my @exargs=($request->{arg});
  if (ref($extrargs)) {
    @exargs=@$extrargs;
  }
  if (($#exargs==-1) or (($#exargs==0) and ($exargs[0] =~ /^\s*$/)) and (!$noderange and $command ne "lsslp")) {
     $exargs[0] = "--help";  # force help if no args
  }

  # rflash: -p flag is to specify a directory, which will be parsed as a node range with regular expression
  # stop the rflash command without noderange
  # rflash -p /tmp/test  --activate disruptive
  # where the /tmp/test will be treated as noderange with regular expression
  # this is a general issue for the xcatclient commands, if with a flag can be followed by directory
  # however, rflash is the only one we can think of for now.
  if(!$noderange and $command eq "rflash") {
      $exargs[0] = "--help";
  }

  my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
  if ($usage_string) {
    $callback->({data=>[$usage_string]});
    $request = {};
    return;
  }

}

##########################################################################
# Process request from xCat daemon
##########################################################################
sub process_request {
    return 0;
}




1;
