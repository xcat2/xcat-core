# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::AAAusage;
use strict;
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
      lsslp     => 'AAAusage',
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
  if (($#exargs==-1) or (($#exargs==0) and ($exargs[0] =~ /^\s*$/)) or (!$noderange)) {
     $exargs[0] = "--help";  # force help if no args
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
