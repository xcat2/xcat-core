#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::State;

use constant REQUEST_ERROR  => 0;
use constant REQUEST_WAIT   => 1;
use constant REQUEST_UPDATE => 2;

use constant WAIT_STATE   => 'waiting';
use constant UPDATE_STATE => 'updating';

use constant INSPECT_ACTION => 'inspect';
use constant UPDATE_ACTION  => 'update';

1;
