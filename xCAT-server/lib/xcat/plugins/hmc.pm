# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::hmc;
use strict;
use xCAT::PPC;


##########################################################################
# Command handler method from tables
##########################################################################
sub handled_commands {
  return {
      rpower    => 'nodehm:power,mgt',
      rvitals   => 'nodehm:mgt',
      rinv      => 'nodehm:mgt',
      mkvm      => 'nodehm:mgt',
      rmvm      => 'nodehm:mgt',
      lsvm      => 'nodehm:mgt',
      chvm      => 'nodehm:mgt',
      rscan     => 'nodehm:mgt',
      getmacs   => 'nodehm:getmac,mgt',
      rnetboot  => 'nodehm:mgt',
      rspconfig => 'nodehm:mgt',
      rflash    => 'nodehm:mgt',
      mkhwconn    => 'nodehm:mgt',
      rmhwconn    => 'nodehm:mgt',
      lshwconn    => 'nodehm:mgt',
      renergy   => 'nodehm:mgt'
  };
}


##########################################################################
# Pre-process request from xCat daemon
##########################################################################
sub preprocess_request {
    xCAT::PPC::preprocess_request(__PACKAGE__,@_);
}

##########################################################################
# Process request from xCat daemon
##########################################################################
sub process_request {
    xCAT::PPC::process_request(__PACKAGE__,@_);
}




1;
