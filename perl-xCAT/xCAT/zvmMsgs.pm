# IBM(c) 2016 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1

    This is a message utility plugin for z/VM.

=cut

#-------------------------------------------------------
package xCAT::zvmMsgs;
use Text::Wrap;
use strict;
use warnings;
1;


# Messages
# Severity strings
my @sevInfo = ( '',                 # No header
                'Bypassing test',   # Bypassing message
                'Info',             # Information message
                'unknown',          # Unknown severity
                'Warning',          # Warning message
                'Error'             # Error message
              );

# Hash of message ids.  Message ids should be in uppercase.  'ALL' should not
# be used as a message id as this indicates that all messages are wanted.
# For each message id there is another hash with additional info:
#   severity - Severity of message and indicate whether it gets a header to the
#              message text (e.g. "Error (IVP:MAINT01) " )
#                  0 - no message header, unrated output
#                  1 - bypass message used by automated tests
#                  2 - information message with "Info" header
#                  3 - unknown message severity
#                  4 - warning message with "Warning" header
#                  5 - error message with "Error" header
#   recAction - Recommended action:
#                   0 - non-fatal message, continue processing
#                   1 - fatal message, end further processing
#   explain  - Further explanation of the message.
#   subTab   - (optional) Indicates the tabbing characters to use.  This is
#              used to control whether subsequent lines of a message are
#              indented.  The default is '\t', to indent the lines.
#   sysAct   - System action to be performed.  Normally, this is not specified
#              because the severity generates a default system action.
#   userResp - Suggested user response.

#******************************************************************************
# verifynode messages
#******************************************************************************
my %verifyMsgs = (
    'FATAL_DEFAULTS' =>
         {
           'sysAct'    => 'No further verification will be performed.'
         },
    'NONFATAL_DEFAULTS' =>
         {
           'sysAct'    => 'Verification continues.'
         },
    'GENERIC_RESPONSE' =>
         { 'severity'  => 0,
           'recAction' => 0,
           'text'      => '%s',
         },
    'GENERIC_RESPONSE_NOINDENT' =>
         { 'severity'  => 0,
           'recAction' => 0,
           'text'      => '%s',
           'subTab'    => '',
         },
    'CLNUP01' =>
         { 'severity'  => 5,
           'recAction' => 0,
           'text'      => 'Unable to remove the temporary directory, %s, from the'.
                          'from the compute node system at %s. '.
                          'The following command failed: %s with rc: %s, out: %s',
           'explain'   => 'The IVP created a temporary directory on the target system. '.
                          'It was unable to remove the directory when it was finished with it. '.
                          'The message indicate the command, return code and output of the command.',
           'userResp'  => 'Determine the cause of the error and correct it, if possible. You may want '.
                          'to access the system and remove the directory.',
         },
    'DFLT01' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => '%s so the function will use \'%s\' as the default value. %s',
           'explain'   => 'A value was not specified so the function will use the indicated default.',
           'userResp'  => 'You can specify the missing value in order to avoid this message in the future. ' .
                          'If the value is acceptable then you can ingnore this message.',
         },
    'DRIV01' =>
         { 'severity'  => 5,
           'recAction' => 1,
           'text'      => 'The driver script, %s, failed, rc: %s, out: %s',
           'explain'   => 'The driver script failed with the indicated return code and output. '.
                          'The IVP is unable to run the full installation verification test.',
           'sysAct'    => 'IVP processing stops.',
           'userResp'  => 'Determine the cause of the error and correct the error. Run the IVP after '.
                          'you have corrected the error. Otherwise, consult the support team.',
         },
    'DRIV02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The driver script, %s, did not specify the z/VM host node information in the %s property',
           'explain'   => 'The driver script did not specify the z/VM host node property. '.
                          'The IVP will default to notifying the user on the system where the '.
                          'xCAT management node runs.',
           'userResp'  => 'Determine why the property was not defined in OpenStack and correct the error. Run the IVP after '.
                          'you have corrected the error. Otherwise, consult the support team.',
         },
    'DRIV03' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The ZHCP agent related to the host, \'%s\', could not be determined from the xCAT node information.',
           'explain'   => 'The driver script specified a z/VM host. However, the IVP was not able to determine the ZHCP '.
                          'agent associated with the host.',
           'sysAct'    => 'IVP processing continues. The IVP will attempt to determine the ZHCP agent using some other information.',
           'userResp'  => 'Verify that the host node in xCAT has an hcp property and that hosttype is \'zvm\'. '.
                          'Run the IVP after you have corected the error.',
         },
    'GNRL01' =>
         { 'severity'  => 5,
           'recAction' => 0,
           'text'      => 'An unexpected command failure occurred, cmd: \'%s\', rc: %s, out: %s',
           'explain'   => 'An unexpected failure was encountered during processing.  The command that '.
                          'failed is shown along with the return code and output of the command.',
           'sysAct'    => 'This failure will cause some processing to be bypassed but the IVP run will continue.',
           'userResp'  => 'Determine the cause of the error and correct the error. Run the IVP after '.
                          'you have corrected the error. Otherwise, consult the support team.',
         },
    'GNRL02' =>
         { 'severity'  => 5,
           'recAction' => 0,
           'text'      => 'An error occurred attempting to punch \'%s\' from %s to user %s on %s. '.
                          'The file remains on the source system as \'%s\'. Output from the punch invocation: %s',
           'explain'   => 'An unexpected failure occurred while attempting to punch a file.',
           'sysAct'    => 'An attempt will be made to remove the file but this may fail. '.
                          'The IVP will try to send the file to an alternate user and will indicate if this was successful. '.
                          'This failure may prevent the IVP from sending the log file to the notify user on the target system.',
           'userResp'  => 'The original log file exists on the xCAT management node in the /var/log/xcat/ivp directory. '.
                          'You may access it on that system if you did not receive the file on an alternate userid and system.',
         },
    'GNRL04' =>
         { 'severity'  => 5,
           'recAction' => 1,
           'text'      => 'An unexpected command failure occurred, cmd: \'%s\', rc: %s, out: %s',
           'explain'   => 'An unexpected failure was encountered during processing.  The command that '.
                          'failed is shown along with the return code and output of the command.',
           'sysAct'    => 'Processing terminates.',
           'userResp'  => 'Determine the cause of the error and correct the error. Run the command again after '.
                          'you have corrected the error. Otherwise, consult the support team.',
         },
    'GOSL01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The command \'%s\' was sent to %s to determine the OpenStack level but '.
                          'did not return an expected response.  Instead it returned rc: %s and out: %s.',
           'explain'   => 'The value returned by the command was not an expected value. '.
                          'This is expected to be a single word, e.g. \'14.0.2\', with the '.
                          'components of the version separated by a period. There should be '.
                          'at least two components.',
           'userResp'  => 'Determine the reason that the OpenStack level is not a recognized value. '.
                          'Run the command again after you have corrected the error. '.
                          'Otherwise, consult the support team.',
         },
    'GOSL02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The command \'%s\' was sent to %s to determine the OpenStack level but '.
                          'did not return one of the recognized versions. '.
                          'Instead, it returned rc: %s and out: %s.',
           'explain'   => 'The value returned by the command was not an expected value. '.
                          'The expected values are listed in /opt/xcat/openstack.versions.',
           'userResp'  => 'Determine the reason that the OpenStack level is not a recognized value. '.
                          'Run the command again after you have corrected the error. '.
                          'Otherwise, consult the support team.',
         },
    'ID01' =>
         { 'severity'  => 5,
           'recAction' => 1,
           'text'      => 'The system attempted to generate a unique IVP id but failed to do so after 10000 attempts.',
           'explain'   => 'An IVP id was not specified so the system attempted to generate a unique IVP id. '.
                          'This begins with an id of 10 and increments by 1 upto 10010. Unfortunately, '.
                          'a unique unused Id was not found in the zvmivp table. You may have a corrupted '.
                          'zvmivp table or have somehow filled the table with 10000 IVPs which is highly abnormal.',
           'sysAct'    => 'Processing terminates.',
           'userResp'  => 'Determine the cause of the error and correct the error. Run the command again after '.
                          'you have corrected the error. Otherwise, consult the support team.',
         },
    'ID02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The IVP id, %s, does not exist. A new IVP will be scheduled using that id.',
           'explain'   => 'The specified IVP id was not found in the zvmivp table.',
           'sysAct'    => 'Processing continues and a new IVP will be added to the table of scheduled IVPs using the '.
                          'specified id.',
           'userResp'  => 'If you incorrectly specified the IVP id and did not want to add a new ID, then you should '.
                          'remove the IVP that you do not want. '.
                          'From the xCAT GUI, go to Help->Verify xCAT to remove the IVP.',
         },
    'ID03' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The IVP id does not exist in the zvmivp table: %s',
           'explain'   => 'The specified IVP id was not found in the zvmivp table.',
           'sysAct'    => 'Processing terminates.',
           'userResp'  => 'Specify the correct id and retry.',
         },
    'MN01' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => 'Could not find an xCAT management node which had an IP address of %s, cmd: \'%s\', rc: %s, out: %s',
           'explain'   => 'An xCAT node that represents the xCAT management node could not be found. '.
                          'The xCAT management node is not required by the IVP but some processing '.
                          'such as default notification of the z/VM host on which the xCAT management '.
                          'node runs will not occur.',
           'userResp'  => 'If you expected the xCAT management node to exist, please review the '.
                          'command that was issued and the return code and output to determine '.
                          'why the xCAT management node was not found and correct the issue. '.
                          'Run the IVP or other command that you issuedd after you have corrected the issue.',
         },
    'MN02' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => 'The xCAT management node is not defined as a node in xCAT and the function will not '.
                          'be performed.',
           'explain'   => 'The issued command requires the existence of the xCAT MN as an xCAT node. '.
                          'The requrested processing cannot be performed.',
           'sysAct'    => 'Processing terminates.',
           'userResp'  => 'Determine the cause of the error and correct the error.',
         },
    'MN03' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => 'The xCAT management node is not defined as a node so only a basic IVP will be run.',
           'explain'   => 'The xCAT MN should exist as an xCAT node. The failure to find the node indicates '.
                          'a larger failure. An automated IVP will be performed to verify the general '.
                          'functioning of the environment but it will not be added to the zvmivp table. '.
                          'We expect the installation to define the xCAT node upon seeing this message '.
                          'and that will allow the automated IVP to create default IVPs in the zvmivp table.',
           'sysAct'    => 'Processing continues.',
           'userResp'  => 'Define the xCAT management node in xCAT.',
         },
    'MSG01' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => '%s on %s is unable to receive messages at this time, status: \'%s\'. '.
                          'They will not be sent the IVP results message.',
           'explain'   => 'The IVP attempted to send a message to the user on the target system '.
                          'to notify them of the status of the IVP run. The user was '.
                          'unavailable to receive the message. '.
                          'Status of \'SSI\' indicates they are logged on another system in the SSI '.
                          'cluster while \'DSC\' indicates the machine is running disconnected. '.
                          'The userid is defined by the XCAT_notify property in the '.
                          'DMSSICNF COPY file or the zvmnotify property in the xCAT site table.',
           'sysAct'    => 'Processing continues. The log file from the run was '.
                          'sent to the userid as a spool file.',
           'userResp'  => 'If the userid is not the userid that you expected to receive the '.
                          'IVP status message then correct the XCAT_notify property in '.
                          'the DMSSICNF COPY file and recycle SMAPI to pick up the new value or '.
                          'as a temporary measure until the next recycle of SMAPI, update the '.
                          'zvmnotify property in the xCAT site table.',
         },
    'OPER01' =>
         { 'severity'  => 5,
           'recAction' => 1,
           'text'      => 'Required operand %s is missing.',
           'explain'   => 'The indicated operand is required but missing.',
           'sysAct'    => 'Processing terminates.',
           'userResp'  => 'Specify the command with the required operand.',
         },
    'OPER02' =>
         { 'severity'  => 5,
           'recAction' => 1,
           'text'      => 'Operand %s has a value of \'%s\' which is not one of the recognized values: %s.',
           'explain'   => 'The value for the operand is not recognized.',
           'sysAct'    => 'Processing terminates.',
           'userResp'  => 'Specify the command with the correct operand value.',
         },
    'OPER03' =>
         { 'severity'  => 5,
           'recAction' => 1,
           'text'      => 'Conflicting operands were specified: %s.',
           'sysAct'    => 'Processing terminates.',
           'userResp'  => 'Specify the command with the correct operand value.',
         },
    'PERL01' =>
         { 'severity'  => 4,
           'recAction' => 1,
           'text'      => 'A perl script error was detected in %s.\n'.
                          '        Calling parms: %s\n'.
                          '        Reason: %s',
           'explain'   => 'The indicated perl script encountered a perl scripting error '.
                          'that prevents it from operating correctly.  The script is '.
                          'ending the current run.  This error message is a restatement of '.
                          'a previous message so that you are ensured to see the error.',
           'userResp'  => 'Review the previous messages to determine whether the error '.
                          'is caused by bad invocation parameters or an error within '.
                          'the script.  Please report this problem if it is not caused '.
                          'by a user error.',
         },
    'PREP01' =>
         { 'severity'  => 5,
           'recAction' => 1,
           'text'      => 'Unable to create the %s directory in the system running the xCAT management node. rc: %s, out: %s',
           'explain'   => 'The specified directory is used to contain the driver script created '.
                          'by the IVP preparation script. This directory exists in the virtual '.
                          'server that runs the xCAT management node. The directory '.
                          'could not be created.'.
                          'The current OpenStack properties cannot be validated. '.
                          'A saved version of the driver script from a previous run will be used, if it exists.',
           'userResp'  => 'Determine the cause of the error.  It could be caused by running the '.
                          'verifynode script under a user that does not have root authority. '.
                          'If you cannot correct the problem then you can download the IVP preparation script '.
                          'to the target system and run it as discussed in the Enabling z/VM for OpenStack manual. '.
                          'The driver script may then be uploaded to the xCAT management node system and '.
                          'moved to the indicated location so that it can be used in a subsequent IVP.',
         },
    'PREP02' =>
         { 'severity'  => 5,
           'recAction' => 0,
           'text'      => 'Unable to send the IVP preparation script, %s, to the OpenStack system at %s. '.
                          'The script was intended to be used to create a driver script for the IVP '.
                          'on the system running the xCAT management node at %s. '.
                          'A previous version of the driver script will be used. '.
                          'The following command failed: %s with rc: %s, out: %s',
           'explain'   => 'The xCAT Management Node was unable to send the IVP preparation script to the '.
                          'specified system in order to analyze the OpenStack properties and '.
                          'construct the driver script for the next phase of the IVP. The command failed '.
                          'with the indicated return code and output. '.
                          'The current OpenStack properties cannot be validated. '.
                          'A saved version of the driver script from a previous run will be used, if it exists.',
           'userResp'  => 'Determine the cause of the error and correct it, if possible.'.
                          'If you cannot correct the problem then you can download the IVP preparation script '.
                          'to the target system and run it as discussed in the Enabling z/VM for OpenStack manual. '.
                          'The driver script may then be uploaded to the xCAT management node system and '.
                          'moved to the indicated location so that it can be used in a subsequent IVP.',
         },
    'PREP04' =>
         { 'severity'  => 5,
           'recAction' => 0,
           'text'      => 'Unable to retrieve the driver script created by the IVP preparation script, %s, '.
                          'from the OpenStack system at %s. '.
                          'The driver script was intended to be used to drive the IVP '.
                          'on the system running the xCAT management node at %s. '.
                          'The following command failed: %s with rc: %s, out: %s',
           'explain'   => 'The xCAT Management Node was unable to retrieve the driver script from the '.
                          'specified system for the next phase of the IVP. '.
                          'A saved version of the driver script from a previous run will be used, it it exists.',
           'userResp'  => 'Determine the cause of the error and correct it, if possible. '.
                          'If you cannot correct the problem then you can download the IVP preparation script '.
                          'to the target system and run it as discussed in the Enabling z/VM for OpenStack manual. '.
                          'The driver script may then be uploaded to the xCAT management node system and '.
                          'moved to the indicated location so that it can be used in a subsequent IVP.',
         },
    'PREP06' =>
         { 'severity'  => 5,
           'recAction' => 1,
           'text'      => 'Unable to determine the OpenStack level of the OpenStack system at %s. '.
                          'The full IVP cannot be run.',
           'explain'   => 'The xCAT Management Node was unable to level of OpenStack running the in the indicated system. '.
                          'This is necessary so that the correct level of analysis code can be run '.
                          'to validate the system. '.
                          'A saved version of the driver script from a previous run will be used, if it exists.',
           'userResp'  => 'Determine the cause of the error and correct it, if possible. If OpenStack '.
                          'Nova services are not actively running on the system then please start them '.
                          'and reattempt the IVP.'.
                          'If you cannot correct the problem then you can download the IVP preparation script '.
                          'to the target system and run it as discussed in the Enabling z/VM for OpenStack manual. '.
                          'The driver script may then be uploaded to the xCAT management node system and '.
                          'moved to the indicated location so that it can be used in a subsequent IVP.',
         },
    'PREP07' =>
         { 'severity'  => 5,
           'recAction' => 0,
           'text'      => 'Unable to reduce the file permissions on %s with command: %s,\nrc: %s, out: %s',
           'explain'   => 'The xCAT Management Node was unable to lower the file permission on the indicated file.',
           'userResp'  => 'Determine the cause of the error and correct it, if possible. You may want to change the '.
                          'permissions on the file.',
         },
    'SITE01' =>
         { 'severity'  => 5,
           'recAction' => 0,
           'text'      => 'The \'%s\' property from the site table has a value that is not valid. Value: \'%s\', '.
                          'bad portion of the value: \'%s\'',
           'explain'   => 'The site table contains a property that is used in the IVP processing. The value '.
                          'of the property has the following format:'.
                          "\n".
                          'zvmnotify: \'hostnode(userid_on_the_host)\' If additional host/userid combinations are specified '.
                          'then they are connected by a semicolon and no blanks are allowed between the '.
                          'components that make up the value. '.
                          'For example, \'host1(usera);host2(userb)\'',
           'userResp'  => 'Correct the error and rerun the IVP. Otherwise, consult the support team.',
         },
    'SITE02' =>
         { 'severity'  => 5,
           'recAction' => 0,
           'text'      => 'The \'%s\' property from the site table is missing or has an empty string value.',
           'explain'   => 'The site table contains a property that is used in the IVP processing. The property '.
                          'is missing from the table or has a value that is an empty string. The \'master\' '.
                          'property should specify the IP address of the xCAT management node that matches the value '.
                          'specified for the \'ip\' property of the node that represents the xCAT management node.',
           'userResp'  => 'Correctly specify the master property in the site table and rerun the IVP. '.
                          'Otherwise, consult the support team.',
         },
    'VSTN01' =>
         { 'severity'  => 4,
           'recAction' => 1,
           'text'      => 'Unable to SSH to %s.',
           'explain'   => 'The xCAT management node uses SSH to obtain information '.
                          'from the target system or to make changes within Linux on the '.
                          'target system.  This does not appear to be working. '.
                          'This may be due to the system not being unlocked to the xCAT management node for '.
                          'communication or a TCP/IP error.',
           'sysAct'    => 'The system action depends upon the severity of the problem. '.
                          'It will attempt to continue, if possible.',
           'userResp'  => 'First, attempt to unlock the target system from the xCAT GUI by selecting the ' .
                          'node on the Nodes->Nodes panel and choosing \'unlock\' in ' .
                          'the \'Configuration\' pulldown.  If that does not work then investigate '.
                          'TCP/IP errors or network configuration errors within the target system.',
         },
    'TP01' =>
         { 'severity'  => 5,
           'recAction' => 0,
           'text'      => 'The \'%s\' property from the %s table is %s: \'%s\'. A default of \'%s\' will be used instead of that property.',
           'explain'   => 'A property in the indicated table has a value that is not valid. '.
                          'The default will be used instead. ',
           'userResp'  => 'Correctly specify the property in the table.',
         },
    'VA01' =>
         { 'severity'  => 4,
           'recAction' => 1,
           'text'      => 'xCAT MN is unable to issue a simple \'pwd\' command on the target system.',
           'explain'   => 'The xCAT management node uses SSH to obtain information '.
                          'from the target system or to make changes within Linux on the '.
                          'target system.  The xCAT MN can access the system but is unable to issue '.
                          'a simple command.',
           'userResp'  => 'Unlock the target node from the xCAT GUI by selecting the ' .
                          'node on the Nodes->Nodes panel and choosing \'unlock\' in ' .
                          'the \'Configuration\' pulldown.  If this does not work then log onto the '.
                          'virtual machine to see why simple commands are failing.',
         },
    'VD01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => '%s is not a version supported by xCAT.',
           'explain'   => 'The Linux distribution name and version was compared to the list of '.
                          'versions that xCAT supports and was not found in the list.',
           'sysAct'    => 'Some xCAT functions may be unavailable such as image capture and deploy '.
                          'or work incorrectly.',
           'userResp'  => 'Either update the OS running in the target node or monitor the xCAT ' .
                          'responses to commands directed to the node to ensure that it is doing '.
                          'what you desire.',
         },
    'VPF01' =>
         { 'severity'  => 4,
           'recAction' => 1,
           'text'      => 'Unable to determine the power status of %s, rpower rc: %s, msg: %s',
           'explain'   => 'An xCAT rpower command with the stat option was issued to determine '.
                          'the power status of the specified node and returned a non-zero return code.',
           'userResp'  => 'The return code and the message returned by rpower (shown in the message '.
                          'after msg:) should be used to determine the cause of the error. '.
                          'Please correct the error and retry the test.',
         },
    'VP02' =>
         { 'severity'  => 4,
           'recAction' => 1,
           'text'      => '%s is not logged on.',
           'explain'   => 'The virtual machine related to the node is not currently logged on.',
           'userResp'  => 'Log the virtual machine on to the z/VM host and retry the verification.',
         },
    'VS05' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Linux is not configured for the service: %s.',
           'explain'   => 'The specified service should be configured on the target system. '.
                          'This ensures that images '.
                          'captured from this system will have the service started when the '.
                          'new system boots to allow xCAT and/or OpenStack to complete the configuration of the '.
                          'system the first time it boots.',
           'userResp'  => 'Configure Linux to start service on boot of the server.'
         },
    'VS06' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The %s service is not configured for the following run levels: %s',
           'explain'   => 'The specified service should be configured on the target '.
                          'system for the specified run levels.  This ensures that images '.
                          'captured from this system will have the service started when the '.
                          'new system boots to allow xCAT and/or OpenStack to complete the configuration of the '.
                          'system the first time it boots.',
           'userResp'  => 'Configure the service to be \'on\' for indicated run levels.'
         },
    'VX01' =>
         { 'severity'  => 4,
           'recAction' => 1,
           'text'      => 'Unable to determine the version number of the xcatconf4z that is shipped in the xCAT MN.',
           'explain'   => 'The verification code runs xcatconf4z with the \'version\' operand ' .
                          'on the target node.  The script did not return a version string. ' .
                          'This normally indicates that xcatconf4z is a very early version.',
           'userResp'  => 'xcatconf4z should be updated to the latest level.',
         },
    'VX02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'xcatconf4z on the system is back level.  Unable to determine the version installed.',
           'explain'   => 'xcatconf4z exists on the system but is very old and does not respond to the version query.',
           'userResp'  => 'xcatconf4z should be updated to the latest level.',
         },
    'VX03' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'xcatconf4z on the system is back level at %s.  It should be at %s.',
           'explain'   => 'The xcatconf4z on that target node is compared to the one shipped with ' .
                          'the xCAT MN.  The xcatconf4z should be at the same level as the one ' .
                          'on xCAT MN or at a later level.',
           'userResp'  => 'xcatconf4z should be updated to the latest level.'
         },
    'VX04' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'xcatconf4z is not set up to receive configuration directive files from its reader.',
           'explain'   => 'The xcatconf4z script reads configuration directives sent as reader files to it ' .
                          'from authorized userids. The script contains a variable, authorized_senders, that ' .
                          'lists the names of authorized virtual machines.',
           'userResp'  => 'Configure the authorized_senders variable in the script to contain the userids '.
                          'of ZHCP virtual machines that will send configuration directives to this node or '.
                          'to images create from this node.'
         },
    'VX05' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Linux is not setup to start xcatconf4z on boot.',
           'explain'   => 'The xcatconf4z script should be configured on the target '.
                          'system to start when the system boots.  This ensures that images '.
                          'captured from this system will have the service started when the '.
                          'new system boots to allow xCAT to complete the configuration of the '.
                          'system the first time it boots.',
           'userResp'  => 'Configure Linux to start xcatconf4z on boot of the server.'
         },
    'VX06' =>
         { 'severity'  => 4,
           'recAction'=> 1,
           'text'      => 'xcatconf4z was not found in the /opt directory on the target node.',
           'explain'   => 'The xcatconf4z script should exist in the /opt directory on the target node.',
           'userResp'  => 'Obtain xcatconf4z and put it in the /opt directory on the target node.'
         },
    'VX07' =>
         { 'severity'  => 4,
           'recAction'=> 0,
           'text'      => '/opt/bin/mkisofs was not found on the target system.',
           'explain'   => 'The xcatconf4z script invokes the /opt/bin/mkisofs to create ' .
                          'an ISO9660 disk in which it stores configuration '.
                          'data used by the activation engine.  The mkisofs file is missing '.
                          'and will prevent proper operation of the xcatconf4z script during '.
                          'deploy of an image.',
           'userResp'  => 'This function should be obtained from the Linux distribution and '.
                          'installed.'
         },
    );

#******************************************************************************
# zxcatIVP messages
#******************************************************************************
my %zxcativpMsgs = (
    'FATAL_DEFAULTS' =>
         {
           'sysAct'    => 'No further verification will be performed.'
         },
    'NONFATAL_DEFAULTS' =>
         {
           'sysAct'    => 'Verification continues.'
         },
    'GENERIC_RESPONSE' =>
         { 'severity'  => 0,
           'recAction' => 0,
           'text'      => '%s',
         },
    'GENERIC_RESPONSE_NOINDENT' =>
         { 'severity'  => 0,
           'recAction' => 0,
           'text'      => '%s',
           'subTab'    => '',
         },
    'BPVMN01' =>
         { 'severity'  => 1,
           'recAction' => 0,
           'text'      => 'The node id for the xCAT MN was not specified, so the IVP will not verify that it exists.',
           'explain'   => 'The node name of the xCAT MN is a configuration property, zvm_xcat_master '.
                          'in /etc/nova/nova.conf file, that is used by z/VM OpenStack plugin code. '.
                          'The driver script created by the IVP preparation script normally passes this value '.
                          'in the zxcatIVP_mnNode environment variable. '.
                          'The IVP perform tests related to the value. This bypass message is '.
                          'expected when the IVP is driven directly without a driver script; for '.
                          'example, in basic test mode but is not expected when a full IVP is run.',
           'sysAct'    => 'Some tests which use the node name of the xCAT MN will not be run.',
           'userResp'  => 'If you did not run the preparation script to create a driver script, then '.
                          'consider doing so and rerunning the test with the driver script. '.
                          'If you intended to run the basic IVP which is run without a driver script '.
                          'then you can ignore this message.'
         },
    'BPVDP01' =>
         { 'severity'  => 1,
           'recAction' => 0,
           'text'      => 'Disk pool names were not specified, so IVP will verify the pools associated with each host.',
           'explain'   => 'Directory manager disk pools are used for obtaining OpenStack ephemeral '.
                          'disks. The zvm_diskpool property in /etc/nova/nova.conf file specifies the disk pools. '.
                          'The driver script created by the IVP preparation script normally passes this value '.
                          'in the zxcatIVP_diskpools environment variable. '.
                          'The IVP perform tests related to the value. This bypass message is '.
                          'expected when the IVP is driven directly without a driver script; for '.
                          'example, in basic test mode but is not expected when a full IVP is run.',
           'userResp'  => 'If you did not run the preparation script to create a driver script, then '.
                          'consider doing so and rerunning the test with the driver script. '.
                          'If you intended to run the basic IVP which is run without a driver script '.
                          'then you can ignore this message.'
         },
    'BPVDS01' =>
         { 'severity'  => 1,
           'recAction' => 0,
           'text'      => 'Directory space tests related to ZHCP agent will not be run.',
           'explain'   => 'The IVP detected that the ZHCP agent is on the same system as the xCAT management node. ' .
                          'The space related tests would have already be run for the xCAT MN so similar tests ' .
                          'will not be run for the ZHCP agent.',
           'userResp'  => 'If you want to verify additional directories for the ZHCP running on the xCAT MN\'s system '.
                          'then specify the directory information as part of the xcatDiskSpace command line operand or ' .
                          'zxcatIVP_xcatDiskSpace environment variable.  Please remember to include directories '.
                          'that are defaults for the xCAT MN\'s directory space tests.  You can see the defaults in the ' .
                          'help output for zxcatIVP.'
         },
    'BPVN01' =>
         { 'severity'  => 1,
           'recAction' => 0,
           'text'      => 'Networks were not specified, so IVP will not verify them.',
           'explain'   => 'Virtual switches are used for internet access by the deployed '.
                          'virtual servers. The flat_networks property in section ml2_type_flat '.
                          'and the network_vlan_ranges property in section ml2_type_vlan '.
                          'in the /etc/neutron/plugins/ml2/ml2_conf.ini file specify the vswitches. '.
                          'The driver script created by the IVP preparation script normally passes this value '.
                          'in the zxcatIVP_networks environment variable. '.
                          'The IVP perform tests related to the value. This bypass message is '.
                          'expected when the IVP is driven directly without a driver script; for '.
                          'example, in basic test mode but is not expected when a full IVP is run.',
           'userResp'  => 'If you did not run the preparation script to create a driver script, then '.
                          'consider doing so and rerunning the test with the driver script. '.
                          'If you intended to run the basic IVP which is run without a driver script '.
                          'then you can ignore this message.'
         },
    'BPVCNC01' =>
         { 'severity'  => 1,
           'recAction' => 0,
           'text'      => 'Compute Node address or export user was not specified, so the IVP will '.
                          'not verify that the xCAT MN can communicate with the compute node.',
           'explain'   => 'The address of the virtual server where the nova compute services '.
                          'are running is configured in the '.
                          'my_ip property in the /etc/nova/nova.conf file. The driver script '.
                          'created by the IVP preparation script normally passes this value '.
                          'in the zxcatIVP_cNAddress environment variable. '.
                          "\n\n".
                          'The export user is normally set to \'nova\' by the IVP preparation script '.
                          'and is passed in the zxcatIVP_expUser environment variable.'.
                          'The IVP will perform tests related to these values. This bypass message is '.
                          'expected when the IVP is driven directly without a driver script; for '.
                          'example, in basic test mode but is not expected when a full IVP is run.',
           'userResp'  => 'If you did not run the preparation script to create a driver script, then '.
                          'consider doing so and rerunning the test with the driver script. '.
                          'If you intended to run the basic IVP which is run without a driver script '.
                          'then you can ignore this message.',
         },
    'MAIN01' =>
         { 'severity'  => 4,
           'recAction' => 1,
           'text'      => 'Significant error detected, no further verification will be performed.',
           'explain'   => 'A significant warning was detected, which prevents further tests '.
                          'from accurately validating the system.',
           'sysAct'    => 'No further verification will be performed for this run.',
           'userResp'  => 'You should correct the situation indicated by previous warning '.
                          'messages and then rerun the IVP.',
         },
    'STN01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Unable to SSH to %s.',
           'explain'   => 'The xCAT management node uses SSH to obtain information '.
                          'from the target node or to make changes within Linux on the '.
                          'target node. This does not appear to be working.',
           'userResp'  => 'You should investigate TCP/IP errors or network configuration errors within the target node.',
         },
    'VCMAP01' =>
         { 'severity'  => 4,
           'recAction' => 1,
           'text'      => 'Unable to determine the role of the Cloud Manager Appliance from the %s file.',
           'explain'   => 'The Cloud Manager Appliance has a /var/lib/sspmod/appliance_system_role '.
                          'file that cannot be read or does not contain the expected role property '.
                          'in its expected form of "role=value" where the value is either: '.
                          'CONTROLLER, COMPUTE, COMPUTE_MN, or MN.'.
                          'This indicates corruption of the file and possibly other files, or a failed '.
                          'install.',
           'userResp'  => 'You should correct the corruption of the /var/lib/sspmod/appliance_system_role '.
                          'file and then rerun the IVP.',
         },
    'VCMAP02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Unable to determine the version of Cloud Manager Appliance from the %s file.',
           'explain'   => 'The Cloud Manager Appliance contains a /opt/ibm/cmo/version file '.
                          'that cannot be read or does not contain a line indicating the '.
                          'version of the appliance. This indicates a possible corruption of '.
                          'the file system or a failed install.',
           'userResp'  => 'You should verify that the file exists on the appliance and has the proper '.
                          'permissions set to allow user root to read the file.',
         },
    'VCNC01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'xCAT MN is unable to SSH to %s with user %s.',
           'explain'   => 'The xCAT MN could not SSH into the compute node. This can occur for the '.
                          'following reasons:'.
                          "\n".
                          '* the wrong user name was specified,'.
                          "\n".
                          '* the wrong IP address was specified,'.
                          "\n".
                          '* or the SSH keys were not set up on the compute '.
                          'node to allow the xCAT MN to push data to that node.'.
                          "\n\n".
                          'The error message indicates the IP address and user name that the IVP thinks '.
                          'xCAT MN will use.',
           'userResp'  => 'Verify the my_ip property, if it was specified in '.
                          '/etc/nova/nova.conf, or verify the local IP address of the OpenStack system. '.
                          'The local IP address is used by the IVP preparation script as a default '.
                          'when the my_ip property is not set. The IVP uses this '.
                          'address to verify that the xCAT MN can access the compute node. xCAT MN '.
                          'communicates with the compute node using this IP address. An address '.
                          'which is not accessible by the xCAT MN will cause various xCAT functions '.
                          'to fail. If the my_ip is not set, an incorrect default for your compute '.
                          'node might have been chosen. You may wish to specify the my_ip property '.
                          'with a valid value for your environment. Also, verify the value of the '.
                          'zxcatIVP_expUser specified in the driver script by the IVP preparation script '.
                          'script. This value defaults to "nova", which is the user name under '.
                          'which the compute node will allow xCAT MN to access the system.',
         },
    'VDP01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Disk pool %s was not found as a disk pool.',
           'explain'   => 'The specified disk pool was not found. The disk pool is specified in '.
                          '/etc/nova/nova.conf and is passed to the IVP in the driver script '.
                          'by the zxcatIVP_diskpools environment variable.',
           'userResp'  => 'Verify the zvm_diskpool property in /etc/nova/nova.conf is correct.'
         },
    'VDP02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Disk pool %s has no free space',
           'explain'   => 'The indicated disk pool has no space for minidisk creation. '.
                          'You may need to add disks to the directory manager disk pool '.
                          'or specify a different disk pool for the zvm_diskpool property in '.
                          '/etc/nova/nova.conf.'.
                          "\n\n".
                          'If you are running a basic IVP and see this message for disk pool '.
                          'XCAT1, you can ignore the warning. Disk pool XCAT1 is a special '.
                          'disk pool that normally has no available space. This disk pool '.
                          'is not intended to be used as a disk pool by the compute node.',
           'userResp'  => 'Add space to the disk pool in the directory manager.'
         },
    'VDP03' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Unable to obtain a list of disk pools for host %s.',
           'explain'   => 'The list of disk pools defined in the directory manager could not be obtained for '.
                          'the specified host.',
           'userResp'  => 'This can be caused by a few different problems. They include: '.
                          "\n".
                          '* No disk pools/regions defined in the directory manager - Use directory manager '.
                          'commands to verify that disk pools have been defined, or to define them. '.
                          "\n".
                          '* The ZHCP server is unresponsive - Ensure that the ZHCP server is running. Other '.
                          'error messages will occur if it is not running. '.
                          "\n".
                          '* SMAPI is unable to communicate with the directory manager - Use the SMAPI '.
                          'SMSTATUS command to collect SMAPI debug information and verify the configuration '.
                          'between SMAPI and the directory manager. '.
                          "\n".
                          '* If the name of the host node is incorrect in the message, then the xCAT server '.
                          'may have been previously started prior to modifying the properties in '.
                          'DMSSICNF COPY. This can cause an invalid xCAT node to be created for the host. Subsequent '.
                          'restarts with a correctly configured DMSSICNF COPY file will not remove the '.
                          'incorrect node but only add the new one. When the IVP attempts to verify the '.
                          'host, it fails. See "zxcatIVP Issues" in the Enabling Manual for information on how to '.
                          'remove the invalid node.',
         },
    'VDS01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The file system related to the %s directory on the %s system has %s percent space '.
                          'in use which is more than the expected maximum of %s percent.',
           'explain'   => 'The file system is over the recommended percentage of space in use. This can cause processing errors.',
           'userResp'  => 'You can eliminate this warning by freeing up space in the directories related to the file system. '.
                          'See the troubleshooting sections on space issues related to the type of system, whether it is running '.
                          'xCAT MN or the ZHCP server, in the Enabling z/VM for OpenStack Manual for instructions on addressing space issues.'
         },
    'VDS02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The file system related to the %s directory on the %s system has %s available space '.
                          'which is less than the expected minimum of %s.',
           'explain'   => 'The file system has less than the minimum available space. This can cause processing errors.',
           'userResp'  => 'You can eliminate this warning by freeing up space in the directories related to the file system. '.
                          'See the troubleshooting sections on space issues related to the type of system, whether it is running '.
                          'xCAT MN or the ZHCP server, in the Enabling z/VM for OpenStack Manual for instructions on addressing space issues.'
         },
    'VDS03' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Unable to determine the percentage of disk space used by the %s system\'s file system '.
                          'related to the %s directory.',
           'explain'   => 'The IVP attempts to determine the size of the file system disk space related to the specified directory '.
                          'using the df -h command and is unable to do so. This error is normally '.
                          'related to disk corruption issue or problems with a logical volume associated with the directory.',
           'userResp'  => 'Please review the messages log file on the affected system for errors related to the disks.'
         },
    'VDS04' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The following files are larger than the expected maximum of \'%s\': %s',
           'explain'   => 'Very large files in the indicated directory and it subdirectories can consume space needed '.
                          'for normal operations. The IVP program warns of very large files.',
           'userResp'  => 'You should consider removing the identified files. Please note that '.
                          'the IVP program compiles a simple '.
                          'list of large files in the directories. It only removes some files from the list such as '.
                          'files ending in .so or with .so. in the name or .jar at the end of the filename. For this reason, '.
                          'you should only remove files which you have identified as log files or which you know '.
                          'are files which can be safely removed. See "Space Issues on persistent '.
                          'Directory Can Lead to xCAT MN Issues" in the Enabling Manual for '.
                          'instructions on addressing space issues.'
         },
    'VDS05' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The size of the logical volume on which the xCAT MN image repository resides (%s) '.
                          'is less than image pruning goal (%s).',
           'explain'   => 'The xCAT MN image repository is a subdirectory of the /install '.
                          'directory. The IVP compares the size of the logical volume '.
                          'providing storage for the directory to the value specified in the '.
                          'xcat_free_space_threshold property in the /etc/install/nova.conf '.
                          'file in the OpenStack systen (passed using the '.
                          'xcatIVP_expectedReposSpace property in the driver script). When '.
                          'the OpenStack performs automated pruning of older OpenStack '.
                          'images from the xCAT image repository (images that still exist in '.
                          'Glance), it will attempt to free up enough space to match the '.
                          'xcat_free_space_threshold. An xcat_free_space_threshold value '.
                          'that is greater than the size of the logical volume can result in '.
                          'more images being removed than necessary when automatic pruning '.
                          'occurs. This will result in images being transferred between '.
                          'OpenStack and xCAT unnecessarily.',
           'userResp'  => 'You should consider adding additional volumes the logical volume '.
                          'by updating the XCAT_iso property in the DMSSICNF COPY file for '.
                          'an xCAT MN system, or to the cmo_data_disk property in the '.
                          'DMSSICMO COPY file for a CMA in controller role.'
         },
    'VHN01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The host node (%s) was not defined.',
           'explain'   => 'The specified host node was not defined to xCAT. ',
           'userResp'  => 'Verify that the zvm_host property is specified '.
                         'correctly in /etc/nova/nova.conf. This property is passed by the driver '.
                         'script in the zxcatIVP_hostNode environment variable.'
         },
    'VHN02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Host node does not have an ZHCP associated with it.',
           'explain'   => 'The specified host node, specified with the zvm_host property in '.
                          '/etc/nova/nova.conf, does not have a ZHCP agent associated with it. '.
                          'This property is passed by the driver script in the zxcatIVP_hostNode '.
                          'environment variable.',
           'userResp'  => 'You should correct the host node in xCAT by associating a ZHCP agent '.
                          'using the hcp property so that it can be managed by xCAT and the services '.
                          'services that use xCAT.'
         },
    'VMN01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'MN node(%s) was not defined.',
           'explain'   => 'The xCAT management node specified on the zvm_xcat_master '.
                          'property in the /etc/nova/nova.conf file was not in the list of '.
                          'defined xCAT nodes. The probable cause of this message is an '.
                          'incorrectly specified property value for the xCAT node that '.
                          'represents the xCAT MN.',
           'userResp'  => 'You can view the list of nodes using the xCAT GUI in the '.
                          'Nodes->Nodes tab. The xCAT MN node should be in the list of '.
                          'nodes for the "all" group. You can view other xCAT node groups '.
                          'by selecting the group name in the "Groups" frame on the left '.
                          'side of the web page.'
         },
    'VMNI01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'xCAT MN does not have an interface defined for %s with address: %s.',
           'explain'   => 'The xCAT MN does not have the specified IP address defined. This '.
                          'is most likely caused by a typo in the configuration files. The '.
                          'IVP driver script contains the values used in the test, and which '.
                          'configuration file and property provided the value.',
           'userResp'  => 'Use the information to identify the property in error and correct '.
                          'the address in the configuration file.'
         },
    'VMNI02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Unable to determine the routing prefix information for %s %s.',
           'explain'   => 'While attempting to verify the information specified for the IVP, '.
                          'the routing prefix for the xCAT MN IP address could not be determined. '.
                          'This could indicate a problem with the IP interface for xCAT MN.',
           'userResp'  => 'Use the information to identify the property in error and correct '.
                          'the address in the configuration file.'
         },
    'VMNI03' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Subnet mask specified as input is not valid: %s.',
           'explain'   => 'The subnet mask specified as input to the IVP is not a valid subnet mask.',
           'userResp'  => 'Please verify the subnet mask used as input to the installation '.
                          'verification program.'
         },
    'VMNI04' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'xCAT MN subnet mask for %s has a routing prefix of %s which '.
                          'does not match the calculated routing prefix of %s for the subnet '.
                          'mask passed as input: %s.',
           'explain'   => 'The routing prefix for the xCAT MN does not match the calculated '.
                          'routing prefix for the subnet mask that was specified as input '.
                          'to the IVP.',
           'userResp'  => 'Please verify the subnet mask used as input to the installation verification program.'
         },
    'VMHS01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Unable to determine the signal shutdown time on %s. Query returned, rc: %s, output: %s',
           'explain'   => 'The IVP program attempted to determine the signal shutdown duration on the z/VM host '.
                          'and either encountered an unexpected return code or response from the command. '.
                          'The response is expected to be in English.',
           'userResp'  => 'Determine the cause of the error and correct it.'
         },
    'VMHS02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The signal shutdown time on %s is %s seconds which is less than the tested minimum of %s seconds.',
           'explain'   => 'The signal shutdown time defines the time CP will wait for a virtual machine to respond to '.
                          'a shutdown signal sent to it by SIGNAL, FORCE, or SHUTDOWN commands before forcing a virtual '.
                          'machine off the z/VM system. A value of 0 causes CP to immediately force a virtual machine '.
                          'without sending it a shutdown signal. xCAT and SMAPI use one or more of these commands in the '.
                          'process of powering off a virtual machine.'.
                          "\n\n".
                          'Linux systems cache their disk reads and writes to improve performance.  For this reason, a sufficient '.
                          'delay is recommended to allow the Linux operating system to clear the disk cache. '.
                          'Failure to clear the cache can cause disk problems when the virtual machine logs back on '.
                          'the z/VM system.',
           'userResp'  => 'You should change the signal shutdown time for the z/VM host. The system configuration '.
                          'file supports a SET SIGNAL SHUTDOWNTIME statement that allows you to set the time. '.
                          'In addition, the CP class A and C SET SIGNAL SHUTDOWNTIME command can be used to '.
                          'change the time for the current system IPL. '.
                          "\n\n".
                          'The test run by the IVP checks for a minimum amount of time.  You should choose a time that '.
                          'allows sufficient time for the Linux virtual machines that are running on your system. This '.
                          'will depend upon the performance of your system and the activity performed by the Linux virtual '.
                          'machines.  In general, setting a larger time interval such as 300 seconds (5 minutes) is safer '.
                          'than an interval that is too short.  In most cases, the virtual machines will shutdown upon '.
                          'receiving the signal in a much shorter time and thus avoid the forced log off that results '.
                          'from the time interval expiring.'
         },
    'VMS01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Unable to determine the virtual storage size.',
           'explain'   => 'An attempt to verify the virtual storage size of the z/VM virtual '.
                          'machine running xCAT MN using the z/VM CP QUERY VIRTUAL STORAGE '.
                          'command failed. This can indicate a command authorization problem.',
           'userResp'  => 'Please ensure that the virtual machine is permitted to run the command.'
         },
    'VMS02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Virtual machine storage size (%s) is less than the recommended '.
                          'size of %s.',
           'explain'   => 'The virtual storage size of the z/VM virtual machine which is '.
                          'running xCAT MN is less than the recommended size.',
           'userResp'  => 'Please update the user directory for that virtual machine to '.
                          'increase its virtual storage.'
         },
    'VMUP01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'MACID user prefix for the %s is \'%s\' and is not the expected value of \'%s\'',
           'explain'   => 'The MACADDR user prefix portion of the base_mac property in '.
                          '/etc/neutron/neutron.conf does not match the value specified '.
                          'on the z/VM VMLAN system configuration property in the z/VM '.
                          'host. The IVP uses the z/VM CP Query VMLAN '.
                          'command along with the information in the "VMLAN MAC address '.
                          'assignment" portion of the command response, specifically the '.
                          'user prefix information.',
           'userResp'  => 'This error is most often caused by an error in the OpenStack configuration '.
                          'property. Either the OpenStack property should be changed to match the z/VM '.
                          'system or the z/VM system\'s value should be changed.',
         },
    'VN01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Network %s was not found as a network.',
           'explain'   => 'The specified network is not a known network on the host. The most '.
                          'likely cause of this problem is a typo in the flat_networks and/or '.
                          'network_vlan_ranges properties of the /etc/neutron/plugins/ml2/ml2_conf.ini file.',
           'userResp'  => 'Correct the OpenStack configuration files.'
         },
    'VN02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Network %s is not %s as expected.',
           'explain'   => 'The specified network on the host is not configured with the '.
                          'expected VLAN awareness. The most likely cause of this problem '.
                          'is an error in the flat_networks and/or network_vlan_ranges '.
                          'properties of the /etc/neutron/plugins/ml2/ml2_conf.ini file.',
           'userResp'  => 'Correct the OpenStack configuration files.',
         },
    'VNE01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Node %s is not defined to xCAT.',
           'explain'   => 'The indicated node is not defined to xCAT. '.
                          'This most often indicates a typo in a configuration file.',
           'userResp'  => 'If using a driver script created by the IVP preparation script, '.
                          'please review the driver script to determine the OpenStack '.
                          'property and configuration file which specified the node. You can '.
                          'do this by locating the node name in the driver script and then '.
                          'reading the comments which indicate what property was used to set '.
                          'the value in the driver script.'
         },
    'VP01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Unable to get the directory statements for profile %s',
           'explain'   => 'The profile specified as input is not in the z/VM directory. '.
                          'The cause of this error is either a typo in the zvm_user_profile '.
                          'property in the /etc/nova/nova.conf file or that the profile was not'.
                          'defined to z/VM.',
           'userResp'  => 'Correct the OpenStack configuration file.',
         },
    'VR01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'REST API failed to successfully respond to request.\n' .
                          '  Response code: %s, Message: %s\n' .
                          '  Response content: %s',
           'explain'   => 'A REST communication to the xCAT Management Node from the same '.
                          'server on which the management node was running failed. This '.
                          'can be caused by a typo in the zvm_xcat_username, zvm_xcat_password, '.
                          'and/or zvm_xcat_server properties in /etc/nova/nova.conf file. The xCAT '.
                          'management node obtains the value that it recognizes for the user name from the '.
                          'XCAT_MN_admin property in DMSSICNF COPY. The user name properties '.
                          'should match. It can also occur if there are configuration errors '.
                          'or TCP/IP errors in the xCAT management node.',
           'userResp'  => 'Review the REST response data that is provided with the message. '.
                          'It should help isolate the problem.'
         },
    'VU01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'user %s is not in the policy table.',
           'explain'   => 'The specified xCAT user is not a known xCAT user. This is most likely '.
                          'caused by a typo in the zvm_xcat_username property in the '.
                          '/etc/nova/nova.conf file. The xCAT management node obtains the value that it '.
                          'recognizes for the user name from the XCAT_MN_admin property in DMSSICNF COPY.',
           'userResp'  => 'Correct the OpenStack configuration file.',
         },
    'VVO01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'vswitch %s does not exist.',
           'explain'   => 'The specified virtual switch does not exist in the z/VM system.',
           'userResp'  => 'The vswitch name was specified as the section name in the '.
                          '/etc/neutron/plugins/zvm/neutron_zvm_plugin.ini file before the '.
                          'rdev_list property. The neutron agent creates the virtual switches '.
                          'when it starts up. If the switch is not defined, you should determine '.
                          'whether the neutron agent was started and is successfully communicating '.
                          'with xCAT.'
         },
    'VVO02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'vswitch %s does not use real device %s',
           'explain'   => 'The /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini file indicated that '.
                          'the virtual switch has a real device associated with it at the specified '.
                          'address which does not match the actual vswitch definition in z/VM.',
           'userResp'  => 'This is most likely an error in the rdev_list property for the section '.
                          'indicated by the vswitch name in the /etc/neutron/plugins/zvm/neutron_zvm_plugin.ini file. '.
                          'Correct the OpenStack configuration file.',
         },
    'VZN01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'zHCP node %s did not respond to a ping.',
           'explain'   => 'The indicated ZHCP node did not respond to a ping. '.
                          'The virtual machine may be logged off the z/VM system '.
                          'or there may be problems in the configuration of this server causing it '.
                          'to fail to IPL, or configure its TCP/IP interfaces. '.
                          'ZHCP is necessary to manage the z/VM host and its virtual servers. '.
                          'The ZHCP node is associated with the host specified by the zvm_host property in the '.
                          '/etc/nova/nova.conf file.',
           'userResp'  => 'There are a number of possibilities that you should consider: '.
                          "\n".
                          '* Verify that the virtual machine is logged on. '.
                          'If it is not logged on then verify that you have performed the necessary steps to '.
                          'tell SMAPI to start the server when SMAPI starts. '.
                          'This is discussed in the z/VM Systems Management Application Programming manual.'.
                          "\n".
                          '* Obtain the console log from the virtual server and verify that the system has '.
                          'not stopped itself due to an error. This is not a normal condition and '.
                          'usually indicates a serious configuration error.',
         },
    'VZN02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'zHCP node %s is either not powered on or responding.',
           'explain'   => 'The indicated ZHCP node did not respond to simple power status request. '.
                          'There may be problems with the set up of this ZHCP.',
           'userResp'  => 'Pay particular attention to whether there are SSL key problems. Another '.
                          'possible cause is an error preventing ZHCP from communicating with the '.
                          'z/VM CP. The ZHCP node is associated with the host specified by the zvm_host '.
                          'property in the /etc/nova/nova.conf file.',
         },
    'VZN03' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Unable to get the directory statements for %s. The statements should be for userid %s.',
           'explain'   => 'The indicated ZHCP node did not provide the proper response to a request for '.
                          'information on a user in the z/VM directory. '.
                          'The IVP checks the directory statements to verify that a USER or IDENTITY statement '.
                          'was returned with the userid that was specified in the xCAT zvm table. '.
                          'In addition, the SMAPI servers or the directory manager '.
                          'may not be configured to communicate with the ZHCP agent. '.
                          "\n".
                          'The ZHCP node is associated with the host specified by the zvm_host property in the '.
                          '/etc/nova/nova.conf file.',
           'userResp'  => 'Verify that:'.
                          "\n".
                          '* the zvm table has the userid property correctly listed for the '.
                          'virtual machine that is running the ZHCP node. If not then correct it.'.
                          "\n".
                          '* the Directory manager is operational. This can be accomplished by issuing '.
                          'a command to review a userid\'s directory entries to see if you get a valid response.'.
                          "\n".
                          '* the Directory manager is properly configuring to communicate with the SMAPI servers. '.
                          'This is discussed in the z/VM Systems Management Application Programming manual.',
         },
    'VZN04' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'zHCP node %s is encountering errors communicating with SMAPI, out: %s',
           'explain'   => 'The indicated ZHCP node was not able to execute a simple query to the SMAPI '.
                          'servers and receive an expected result. This indicates a possible error '.
                          'in the SMAPI configuration.',
           'userResp'  => 'You should review the SMAPI configuration to ensure all steps were '.
                          'accomplished and that the virtual machine running the ZHCP agent is '.
                          'authorized to communicate with the SMAPI servers and that '.
                          'the SMAPI servers are running. For example, verify that '.
                          'the VSMWORK1 AUTHLIST file in \'VMSYS:VSMWORK1.\' SFS directory lists '.
                          'the virtual machine that is running the ZHCP agent and that the information in the file '.
                          'is in the correct columns.',
         },
    'VZN05' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'Unable to find a zHCP node related to host %s.',
           'explain'   => 'The indicated host node does not have a ZHCP node which is defined and '.
                          'associated with it. The IVP program expects each host to have an hcp property '.
                          'defined and that property to be related to an xCAT node that represents '.
                          'the ZHCP server and has the same host name as specified for the host\'s hcp property.',
           'userResp'  => 'Define a node in xCAT for the ZHCP server.'
         },
    );

my %reposList = (
    'VERIFYNODE'    => \%verifyMsgs,
    'ZXCATIVP'      => \%zxcativpMsgs,
    );




#-------------------------------------------------------

=head3   buildMsg

    Description : Build a message from a message repository file.
    Arguments   : Group identifier
                  Message identifier
                    'BLANK_LINE' is a special identifier that does not appear in
                      the message repository but instead causes a blank line to
                      be printed to the display.
                  Message substitutions
    Returns     : Recommended action:
                    0: Continue processing
                    1: Fatal, end processing
                  severity - Severity of message and indicate whether it gets
                      a header to the message text (e.g. "Error (IVP:MAINT01) " )
                      0 - no message header, unrated output
                      1 - bypass message used by automated tests
                      2 - information message with "Info" header
                      3 - unknown message severity
                      4 - warning message with "Warning" header
                      5 - error message with "Error" header
                  Constructed message
                  Additional information (e.g. explanation, system action, user action)
    Example     : ( $rc, $sev, $msg, $extraInfo ) = xCAT::zvmMsgs->buildMsg('ZXCATIVP', 'IVP', $msgInfo, \@msgSubs);

=cut

#-------------------------------------------------------
sub buildMsg {
    my ( $class, $groupId, $msgId, $subs ) = @_;
    my @msgSubs = ();
    my $recAction = 0;
    my %respMsgs;
    my $respHash;
    my $retMsg = '';
    my $retExtra = '';
    my $sev = 0;
    my ( $init_tab, $subsequent_tab );

    $Text::Wrap::unexpand = 0;

    if ( defined $subs ) {
        @msgSubs = @$subs;
    }

    # Get the hash of the messages.
    if ( exists $reposList{$groupId} ) {
        $respHash = $reposList{$groupId};
    } else {
        $respHash = \%verifyMsgs;
    }
    %respMsgs = %$respHash;

    # Find the message
    if ( $msgId eq 'BLANK_LINE' ) {
        $retMsg = "\n";
    } elsif ( !exists $respMsgs{$msgId} ) {
        $retMsg = "Warning ($groupId:$msgId): Message was not found!  Unable to find " .
                  "\'$msgId\' in \'$groupId\' messages.\n";
        $sev = 3;
        # Recommended Action is 'continue'.
    } else {
        # Build severity and message Id portion of the message.
        my $msg = '';
        if ( exists $respMsgs{$msgId}{'severity'} ) {
            $sev = $respMsgs{$msgId}{'severity'};
            if ( $respMsgs{$msgId}{'severity'} != 0 ) {
                $msg = $sevInfo[ $respMsgs{$msgId}{'severity'} ] . " ($groupId:$msgId) ";
            }
        } else {
            # Unknown severity
            $msg = $sevInfo[1] . " ($groupId:$msgId) ";
            $sev = 3;
        }

        # Determine the recommended action to return to the caller.
        if ( exists $respMsgs{$msgId}{'recAction'} ) {
            $recAction = $respMsgs{$msgId}{'recAction'};
        }

        # Build text portion of the message.
        if ( exists $respMsgs{$msgId}{'text'} ) {
            # Determine the number of '%s' in the message and pad @msgSubs
            # so that we do not get a sprintf error due to having to few
            # substitution values.
            my $numSubs = 0;
            while ( $respMsgs{$msgId}{'text'} =~ /\%s/g ) { $numSubs++ }
            if ( $numSubs > 0 and $numSubs > ( scalar @msgSubs ) ) {
                # Too few subs. Push on some empty strings so that sprintf does not complain.
                for ( my $i = (scalar @msgSubs); $i <= $numSubs; $i++ ) {
                    push @msgSubs, '';
                }
            }

            if ( @msgSubs ) {
                # Ensure all elements in @msgSubs are defined.
                for ( my $i = 0; $i < (scalar @msgSubs); $i++) {
                    if ( ! defined $msgSubs[$i] ) {
                        $msgSubs[$i] = '';
                    }
                }

                # Insert the substitutions
                my $msgText = sprintf( $respMsgs{$msgId}{'text'}, @msgSubs);
                $msg = "$msg$msgText";
            } else {
                $msg = $msg . $respMsgs{$msgId}{'text'};
            }
        }

        # Set the subsequent wrap/tab value for formatting.
        if ( exists $respMsgs{$msgId}{'initTab'} ) {
            $init_tab = $respMsgs{$msgId}{'initTab'};
        } else {
            $init_tab = "";
        }
        if ( exists $respMsgs{$msgId}{'subTab'} ) {
            $subsequent_tab = $respMsgs{$msgId}{'subTab'};
        } else {
            $subsequent_tab = "\t";
        }

        # Format the messages lines with proper indentation.
        my $line;
        chomp $msg;
        my @msgLines = split( /\\n/, $msg );
        for ( my $i = 0; $i < scalar @msgLines; $i++ ) {
            $line = "$msgLines[$i]";
            $retMsg = $retMsg . wrap( $init_tab, $subsequent_tab, $line ) . "\n";
        }

        if ( $respMsgs{$msgId}{'severity'} >= 1 ) {
            # Build explanation portion of the known messages that are bypass,
            # info, warning or error.  These can have extra information.
            if ( exists $respMsgs{$msgId}{'explain'} ) {
                my $expLines = "    Explanation: $respMsgs{$msgId}{'explain'}";
                @msgLines = split( /\\n/, $expLines );
                for ( my $i = 0; $i < scalar @msgLines; $i++ ) {
                    $line = "$msgLines[$i]";
                    if ( $i != 0 ) {
                        $line = "\t$line";
                    }
                    $retExtra = $retExtra . wrap( $init_tab, $subsequent_tab, $line ) . "\n";
                }
            }

            # Build system action portion of the message.
            my $sysAction;
            if ( exists $respMsgs{$msgId}{'sysAct'} ) {
                $sysAction = "    System Action: $respMsgs{$msgId}{'sysAct'}";
            } else {
                if ( $recAction == 0 and exists $respMsgs{'NONFATAL_DEFAULTS'}{'sysAct'} ) {
                    $sysAction = "    System Action: $respMsgs{'NONFATAL_DEFAULTS'}{'sysAct'}";
                } elsif ( $recAction == 1 and exists $respMsgs{'FATAL_DEFAULTS'}{'sysAct'} ) {
                    $sysAction = "    System Action:  $respMsgs{'FATAL_DEFAULTS'}{'sysAct'}";
                }
            }
            if ( defined $sysAction ) {
                #@msgLines = split( /\\n/, $sysAction );
                #$retMsg = $retMsg . wrap( "", "\t", @msgLines ) . "\n";

                @msgLines = split( /\\n/, $sysAction );
                for ( my $i = 0; $i < scalar @msgLines; $i++ ) {
                    $line = "$msgLines[$i]";
                    if ( $i != 0 ) {
                        $line = "\t$line";
                    }
                    $retExtra = $retExtra . wrap( $init_tab, $subsequent_tab, $line ) . "\n";
                }
            }

            # Build user response portion of the message.
            if ( exists $respMsgs{$msgId}{'userResp'} ) {
                @msgLines = split( /\\n/, "    User Response: $respMsgs{$msgId}{'userResp'}" );
                #$retMsg = $retMsg . wrap( "", "\t", @msgLines ) . "\n";
                for ( my $i = 0; $i < scalar @msgLines; $i++ ) {
                    $line = "$msgLines[$i]";
                    if ( $i != 0 ) {
                        $line = "\t$line";
                    }
                    $retExtra = $retExtra . wrap( $init_tab, $subsequent_tab, $line ) . "\n";
                }
            }
        }
    }

    return ( $recAction, $sev, $retMsg, $retExtra );
}