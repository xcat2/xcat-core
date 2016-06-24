
###########
xcatdebug.8
###########

.. highlight:: perl


****
NAME
****


\ **xcatdebug**\  - Enable or disable the trace facilities for xCAT. (Only supports Linux Operating System)


********
SYNOPSIS
********


\ **xcatdebug**\  { [\ **-f enable**\  | \ **disable**\  [\ **-c**\  {\ *configuration file*\  | \ *subroutine list*\ }]] | [ \ **-d enable**\  | \ **disable**\ ]}


***********
DESCRIPTION
***********


xCAT offers two trace facilities to debug the xCAT:


\ **Subroutine calling trace**\ 

Display the calling trace for subroutine when it is called.

The trace message includes: The name of the called subroutine; The arguments which passed to the called subroutine; The calling stack of the subroutine. By default, the trace will be enabled to all the subroutines in the xcatd and plugin modules. The target subroutine can be configured by configuration file or through xcatdebug command line.

The flag \ **-c**\  is used to specify the subroutine list for \ **subroutine calling trace**\ , it can only work with \ **-f**\ . The value of \ **-c**\  can be a configuration file or a subroutine list.
  \ **configuration file**\ : a file contains multiple lines of \ **SUBROUTINE_DEFINITION**\ 
  \ **subroutine list**\ :    \ **SUBROUTINE_DEFINITION | SUBROUTINE_DEFINITION|...**\ 

\ **SUBROUTINE_DEFINITION**\ : is the element for the \ **-c**\  to specify the subroutine list.

The format of \ **SUBROUTINE_DEFINITION**\ : [plugin](subroutine1,subroutine2,...)

If ignoring the [plugin], the subroutines in the () should be defined in the xcatd.
    e.g. (daemonize,do_installm_service,do_udp_service)

Otherwise, the package name of the plugin should be specified.
    e.g. xCAT::Utils(isMN,Version)
    e.g. xCAT_plugin::DBobjectdefs(defls,process_request)

The trace log will be written to /var/log/xcat/subcallingtrace. The log file subcallingtrace will be backed up for each running of the \ **xcatdebug -f enable**\ .

\ **Commented trace log**\ 

The trace log code is presented as comments in the code of xCAT. In general mode, it will be kept as comments. But in debug mode, it will be commented back as common code to display the trace log.

NOTE: This facility can be enabled by pass the \ **ENABLE_TRACE_CODE=1**\  global variable when running the xcatd. e.g. ENABLE_TRACE_CODE=1 xcatd -f

This facility offers two formats for the trace log code:


Trace section
    ## TRACE_BEGIN
    # print "In the debug\n";
    ## TRACE_END

Trace in a single line
    ## TRACE_LINE print "In the trace line\n";

The \ **commented trace log**\  can be added in xcatd and plugin modules. But following section has been added into the BEGIN {} section of the target plugin module to enable the facility.


.. code-block:: perl

    if (defined $ENV{ENABLE_TRACE_CODE}) {
      use xCAT::Enabletrace qw(loadtrace filter);
      loadtrace();
    }



*******
OPTIONS
*******



\ **-f**\ 
 
 Enable or disable the \ **subroutine calling trace**\ .
 
 For \ **enable**\ , if ignoring the \ **-c**\  flag, all the subroutines in the xcatd and plugin modules will be enabled.
 
 For \ **disable**\ , all the subroutines which has been enabled by \ **-f enable**\  will be disabled. \ **-c**\  will be ignored.
 


\ **-c**\ 
 
 Specify the configuration file or subroutine list.
 
 
 \ **configuration file**\ : a file contains multiple lines of \ **SUBROUTINE_DEFINITION**\ 
   e.g.
     (plugin_command)
     xCAT_plugin::DBobjectdefs(defls,process_request)
     xCAT::DBobjUtils(getobjdefs)
 
 \ **subroutine list**\ : a string like  \ **SUBROUTINE_DEFINITION | SUBROUTINE_DEFINITION|...**\ 
   e.g.
     "(plugin_command)|xCAT_plugin::DBobjectdefs(defls,process_request)|xCAT::DBobjUtils(getobjdefs)"
 


\ **-d**\ 
 
 Enable or disable the \ **commented trace log**\ .
 
 Note: The xcatd will be restarted for the performing of \ **-d**\ 
 



********
EXAMPLES
********



1. Enable the \ **subroutine calling trace**\  for all the subroutines in the xcatd and plugin modules.
 
 
 .. code-block:: perl
 
   xcatdebug -f enable
 
 


2. Enable the \ **subroutine calling trace**\  for the subroutines configured in the /opt/xcat/share/xcat/samples/tracelevel0
 
 
 .. code-block:: perl
 
   xcatdebug -f enable -c /opt/xcat/share/xcat/samples/tracelevel0
 
 


3. Enable the \ **subroutine calling trace**\  for the plugin_command in xcatd and defls,process_request in the xCAT_plugin::DBobjectdefs module.
 
 
 .. code-block:: perl
 
   xcatdebug -f enable -c "xCAT_plugin::DBobjectdefs(defls,process_request)|(plugin_command)"
 
 


4. Disable the \ **subroutine calling trace**\  for all the subroutines which have been enabled by \ **xcatdebug -f enable**\ .
 
 
 .. code-block:: perl
 
   xcatdebug -f disable
 
 


5. Enable the \ **commented trace log**\ 
 
 
 .. code-block:: perl
 
   xcatdebug -d enable
 
 


6. Enable both the \ **subroutine calling trace**\  and \ **commented trace log**\ 
 
 
 .. code-block:: perl
 
    xcatdebug -f enable -c /opt/xcat/share/xcat/samples/tracelevel0 -d enable
 
 


