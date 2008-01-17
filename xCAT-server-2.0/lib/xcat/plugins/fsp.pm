# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::fsp;
use strict;
use xCAT::PPC;


##########################################################################
# Command handler method from tables
##########################################################################
sub handled_commands {
  return {
      rpower    => 'nodehm:power,mgt',
      reventlog => 'nodehm:mgt',
      rfsp      => 'nodehm:mgt'
  };
}


##########################################################################
# Process request from xCat daemon
##########################################################################
sub process_request {

    #######################################################
    # IO::Socket::SSL apparently does not work with LWP.pm
    # When used, POST/GETs return immediately with:
    #     500 Can't connect to <nodename>:443 (Timeout)
    #
    # Net::HTTPS, used by LWP::Protocol::https::Socket,
    # uses either IO::Socket::SSL or Net::SSL. It chooses
    # by looking to see if $IO::Socket::SSL::VERSION
    # is defined (i.e. the module's already loaded) and
    # uses that if so. If not, it first tries Net::SSL,
    # then IO::Socket::SSL only if that cannot be loaded.
    #######################################################
    $IO::Socket::SSL::VERSION = undef;
    eval { require Net::SSL };
    if ( $@ ) {
        my $callback = $_[1];
        $callback->( {data=>[$@]} );
        return(1);
    }
    xCAT::PPC::process_request(__PACKAGE__,@_);
}




1;
