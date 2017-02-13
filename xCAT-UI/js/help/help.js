/**
 * Global variables
 */
var helpTab; // Help tabs
var ivpChoices = new Array;
var ivpChoiceValues = new Array;
var selectInfo = new Object();
var xcatVerTabId = '';


/**
 * Load the help page and create the tabs.
 */
function loadHelpPage(){
    createHelpTab();
    createVerifyXCATTab();
}

/**
 * Create the Help Tab
 *
 * @return Tab object
 */
function createHelpTab(){
    // Create help tab
    var tab = new Tab();
    setHelpTab(tab);
    tab.init();
    $('#content').append(tab.object());

    var helpForm = $('<div class="form"></div>');
    helpForm.append(
        '<fieldset>' +
            '<legend>Quick Start</legend>' +
            '<div style="display: inline-table; vertical-align: middle;"><img src="images/help/quick_start.png" style="width: 90%;"></img></div>' +
            '<ol style="display: inline-table; vertical-align: middle;">' +
                '<li><a href="index.php" style="color: blue;">1. View defined nodes</a><br/>View node definitions by groups in a table.</li>' +
                '<li><a href="provision.php" style="color: blue;">2. Manage operating system images</a><br/>View operating system images defined in xCAT. Copy operating system ISOs into xCAT.</li>' +
                '<li><a href="provision.php" style="color: blue;">3. Provision nodes</a><br/>Create virtual machines. Install an operating system onto virtual machines.</li>' +
                '<li><a href="provision.php" style="color: blue;">4. Manage and provision storage and networks</a><br/>Create network devices. Define storage for systems.</li>' +
            '</ol>' +
        '</fieldset>' +
        '<fieldset>' +
            '<legend>Settings</legend>' +
            '<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/setting.png" style="width: 70px;"></img></div>' +
            '<ol style="display: inline-table; vertical-align: middle;">' +
                '<li><a href="configure.php" style="color: blue;">a. Manage and control user access</a></li>' +
                '<li><a href="configure.php" style="color: blue;">b. Edit the xCAT database tables</a></li>' +
            '</ol>' +
        '</fieldset>');
    tab.add('helpTab', 'Help', helpForm, false);
}


/**
 * Create the Verify xCAT Tab
 *
 * @return Tab object
 */
function createVerifyXCATTab() {
    var comments = 'Name of the IVP run';
    var ivpEnabled = 'checked';
    var ivpDisabled = '';

    // Get the tab
    var tab = getHelpTab();
    var fs, legend;

    // Generate new tab ID
    var instance = 0;
    xcatVerTabId = 'verifyXCATTab' + instance;

    // Build the list of IVPs in the table
    readIvpTable( 'NEW' );

    // Create info bar and status bar
    var introBarId = 'verifyXCATIntroBar' + instance;
    var introBar = createStatusBar(introBarId);
    introBar.find('div').append(
        '<br>' +
        'Run, schedule or remove Installation Verification Procedures.<br>' +
        '<p>' +
        'The IVP consists of a basic IVP and a full IVP. ' +
        'The basic IVP validates the xCAT and SMAPI environments with tests that include ' +
        'checking for access to the ZHCP agents and verifying disk space. ' +
        'The full IVP validates the OpenStack compute node in addition to the xCAT ' +
        'and SMAPI environments. ' +
        '<p>' +
        'The IVP is composed of multiple components which can take additional parameters '+
        'depending on the type of IVP. ' +
        'The parameters shown on this panel will vary based on the type of IVP that is chosen. ' +
        '<p>' +
        '- The orchestrator, xCAT verifynode command, coordinates the functions of the IVP. ' +
        'For a full IVP, the orchestrator transmits an analysis script known as the ' +
        'preparation script for an OpenStack compute node, invokes it and obtains ' +
        'the output of the script. ' +
        '<p>' +
        '- The IVP preparation script analyzes an OpenStack compute node and its OpenStack ' +
        'configuration files as they related to z/VM. ' +
        'The preparation script produces a driver script that is used to ' +
        'continue IVP processing with information gathered during the analysis. ' +
        'The preparations scripts are located in the /opt/xcat/share/xcat/tools/zvm/ ' +
        'directory on the CMA system that is running xCAT. ' +
        'The name of the script begins with \'prep_zxcatIVP_\' and ends with \'.pl\'. ' +
        'The middle part of the name is the human readable identifier of the OpenStack release, ' +
        'eg. prep_zxcatIVP_NEWTON.pl for the OpenStack Newton release. ' +
        '<p>' +
        '- The main IVP script, zxcatIVP.pl, handles the analysis of the xCAT environment. ' +
        'When invoked as part of a basic IVP, it verifies the xCAT environment as it relates ' +
        'to the xCAT Management Node, the ZHCP agent, z/VM SMAPI and CP. ' +
        'When invoked as part of a full IVP, it is invoked by the driver script and uses the ' +
        'OpenStack configuration options to verify the environment. This is similar to the tests ' +
        'performed by the basic IVP but the tests relate to the OpenStack compute node, ' +
        'the related z/VM and the ZHCP agent for that z/VM hypervisor ' +
        'instead of running tests for all ZHCP agents and disk pools. ' +
        'A full IVP drives a number of additional tests that are not part of the basic IVP. ' +
        '<p>' +
        'Three buttons at the bottom of the panel drive the tasks:<br>' +
        '\'Run...\' button immediately starts an IVP with the parameters specified on the panel.<br>' +
        '\'Save...\' button schedules an IVP to be run or modifies the settings of an existing scheduled IVP.<br> ' +
        '\'Remove...\' button removes the indicated scheduled IVP. ' +
        'Note: xCAT creates default IVPs when it detects that no IVPs are defined. ' +
        'For this reason, you do not want to remove all IVPs unless you want xCAT to recreate the ' +
        'default IVPs the next hour that it checks for IVPs to run.' +
        '<p>' +
        'ID of Run:<br>' +
        'Begin by selecting the either \'New\' or the Id of an existing run. ' +
        'Information about the run will be ' +
        'be filled in from the details in the xCAT zvmivp table, if it exists.' +
        '<p>' +
        'Type of IVP Run:<br>' +
        'Select the type of run based on whether a basic IVP of the xCAT MN and all of its ' +
        'ZHCP agents or a full IVP related to OpenStack and the xCAT MN, and the ZHCP related to ' +
        'the compute node. ' +
        '<p>' +
        'Orchestrator Parameters:<br>' +
        'The most often used orchestrator operand is the --ignore <msgID> operand to inform ' +
        'verifynode that it should ignore a specific warning. ' +
        'This prevents you from being notified by the IVP about a known condition that you ' +
        'do not consider an error. ' +
        '<p>' +
        'Preparation Script Parameters:<br>' +
        'The preparation script supports the --ignore <msgID> operand to ' +
        'ignore the specified messages. ' +
        'Sometimes your environment may have a configuration which you consider valid ' +
        'that would produce a warning message.  By using this operand, you instruct ' +
        'the preparation script that the warning should not be considered a problem. ' +
        'This avoids false warnings. ' +
        'For more information on possible preparation script operands, invoke the ' +
        'script that is for your level of OpenStack with the --help operand. '+
        '<p>' +
        'If you are running CMA as an OpenStack controller then no additional parameters ' +
        'required to verify the controller\'s environment.  If wish to verify an OpenStack ' +
        'compute node on another system then some additional parameters will be required. ' +
        '<p>' +
        'OpenStack System IP Address:<br>' +
        'You need to provide the IP address of the compute node that you would like to test. ' +
        '<p>' +
        'OpenStack User:<br>' +
        'The user name that is allowed to access the OpenStack configuration files. ' +
        'The IVP uses that information to send the preparation script and run it on the ' +
        'compute node. ' +
        '<p>' +
        'Main IVP Script Parameters:<br>' +
        'As with the orchestrator and preparation script, a field exists to provide ' +
        'tailoring to the main IVP script. ' +
        'The most commonly used operand is the --ignore <msgID> operand to ' +
        'ignore the listed messages. ' +
        'For more information on possible main IVP script operands, invoke the ' +
        'script as follows:<br> /opt/xcat/bin/zxcatIVP.pl --help '+
        '<p>' +
        'Scheduling related parameters:<br>' +
        'If you are going to schedule an IVP run then some additional operands are of interest ' +
        'to you.' +
        '<p>' +
        'Schedule:<br>' +
        'The schedule operand indicates when the IVP should be run. ' +
        'You can select it to be run every hour of the day or specify the hours. ' +
        '<p>' +
        'Name:<br>' +
        'The name operand allows you to associate a descriptive name with the run. ' +
        'This allows you to easily recognize a specific run in the \'ID or Run\' field. ' +
        '<p>' +
        'Disable:<br>' +
        'The disable checkbox allows you to temporarily disable an IVP from running. '
        );

    var statBarId = 'verifyXCATStatusBar' + instance;
    var statBar = createStatusBar(statBarId).hide();
    var loader = createLoader( '' );
    statBar.find('div').append( loader );

    // Create the verify form and put info and status bars on the form.
    var verifyXCATForm = $( '<div class="form"></div>' );
    verifyXCATForm.append( introBar, statBar );

    // Create 'Create a Verify xCAT' fieldset
    fs = $( '<fieldset></fieldset>' );
    fs.append( $( '<legend>Verify:</legend>' ));
    fs.append( $( '<div id=divIvpId><label>ID of Run:</label>'
                    + '<select name="ivpId" onchange= "setVarsForId( this.value )" >'
                    + '</select>'
                  + '</div>' ));
    fs.append( $('<div id=divRunType>'
                    + '<span style="font-weight:bold">Type of IVP Run:</span><br>'
                    + '<input type="radio" name="runType" value="verifyBasic"/>Basic IVP: xCAT MN/ZHCP Verification<br>'
                    + '<input type="radio" name="runType" value="verifyOpenStack"/>Full IVP: xCAT MN/ZHCP and OpenStack Verification'
                  + '</div>' ));
    fs.append( $('<div id=divFullBasicParms>'
                    + '<span style="font-weight:bold">Run Parameters:</span><br>'
                    + '<label>Orchestrator Script Parameters:</label><input type="text" size="80" id="orchParms" name="orchParms" value="" title="Orchestrator script (verifynode) parameters."/><br>'
                    + '<label>Main IVP Script Parameters:</label><input type="text" size="80" id="mainParms" name="mainParms" value="" title="Main IVP script (zxcatIVP) parameters."/>'
                  + '</div>' ));
    divFullParms = xcatVerTabId + "_divFullParms";
    fs.append( $('<div id=' + divFullParms + '>'
                    + '<label>OpenStack System IP Address:</label><input type="text" id="openstackIP" name="openstackIP" value="" title="IP address of OpenStack system"/><br>'
                    + '<label>OpenStack user:</label><input type="text" id="openstackUser" name="openstackUser" value="" title="User under which OpenStack runs (e.g. nova)"/><br>'
                    + '<label>Preparation Script Parameters:</label><input type="text" size="80" id="prepParms" name="prepParms" value="" title="Preparation script parameters."/>'
                  + '</div>' ));
    fs.append( $('<div id=divAutoParms>'
                    + '<span style="font-weight:bold">Automation Parameters:</span><br>'
                    +
               '<table style="border: 0pm none; text-align: left;">'+
               '<tr>'+
               '<td style="background-color:rgb(220,220,220)"><span style="font-weight:bold">Schedule</span></td>'+
               '<td><input type="checkbox" value="24" name="ivpSchedule" onclick="everyHourClick(this)">Every hour</td>'+
               '</tr><tr>'+
               '<td><input type="checkbox" value="0" name="ivpSchedule" onclick="hourClick(this)">Midnight</td>'
                    +
               '<td><input type="checkbox" value="1" name="ivpSchedule" onclick="hourClick(this)">1 am</td>'+
               '<td><input type="checkbox" value="2" name="ivpSchedule" onclick="hourClick(this)">2 am</td>'+
               '<td><input type="checkbox" value="3" name="ivpSchedule" onclick="hourClick(this)">3 am</td>'+
               '<td><input type="checkbox" value="4" name="ivpSchedule" onclick="hourClick(this)">4 am</td>'+
               '<td><input type="checkbox" value="5" name="ivpSchedule" onclick="hourClick(this)">5 am</td>'+
               '</tr><tr></td>'+
               '<td><input type="checkbox" value="6" name="ivpSchedule" onclick="hourClick(this)">6 am</td>'+
               '<td><input type="checkbox" value="7" name="ivpSchedule" onclick="hourClick(this)">7 am</td>'+
               '<td><input type="checkbox" value="8" name="ivpSchedule" onclick="hourClick(this)">8 am</td>'+
               '<td><input type="checkbox" value="9" name="ivpSchedule" onclick="hourClick(this)">9 am</td>'+
               '<td><input type="checkbox" value="10" name="ivpSchedule" onclick="hourClick(this)">10 am</td>'+
               '<td><input type="checkbox" value="11" name="ivpSchedule" onclick="hourClick(this)">11 am</td>'+
               '</tr><tr></td>'+
               '<td><input type="checkbox" value="12" name="ivpSchedule" onclick="hourClick(this)">Noon</td>'
                    +
               '<td><input type="checkbox" value="13" name="ivpSchedule" onclick="hourClick(this)">1 pm</td>'+
               '<td><input type="checkbox" value="14" name="ivpSchedule" onclick="hourClick(this)">2 pm</td>'+
               '<td><input type="checkbox" value="15" name="ivpSchedule" onclick="hourClick(this)">3 pm</td>'+
               '<td><input type="checkbox" value="16" name="ivpSchedule" onclick="hourClick(this)">4 pm</td>'+
               '<td><input type="checkbox" value="17" name="ivpSchedule" onclick="hourClick(this)">5 pm</td>'+
               '</tr><tr></td>'+
               '<td><input type="checkbox" value="18" name="ivpSchedule" onclick="hourClick(this)">6 pm</td>'+
               '<td><input type="checkbox" value="19" name="ivpSchedule" onclick="hourClick(this)">7 pm</td>'+
               '<td><input type="checkbox" value="20" name="ivpSchedule" onclick="hourClick(this)">8 pm</td>'+
               '<td><input type="checkbox" value="21" name="ivpSchedule" onclick="hourClick(this)">9 pm</td>'+
               '<td><input type="checkbox" value="22" name="ivpSchedule" onclick="hourClick(this)">10 pm</td>'+
               '<td><input type="checkbox" value="23" name="ivpSchedule" onclick="hourClick(this)">11 pm</td>'+
               '</tr>'+
               '</table>'
                    + '<p>'
                    + '<label>Name:</label><input type="text" size="80" id="comments" name="comments" value="'+comments+'" title="Name of the automated IVP run"/><br>'
                    + '<input type="checkbox" value="disabled" name="disableRun">Disable this run'
                  +
               '</div>'));
    verifyXCATForm.append( fs );
    verifyXCATForm.find('#' + divFullParms).hide();

    //************************************************************************
    // Function: Show appropriate division based on the runType.
    //************************************************************************
    verifyXCATForm.change(function(){
        var runType = $(this).parent().find('input[name="runType"]:checked').val();
        if ( runType == 'verifyBasic' ) {
            verifyXCATForm.find('#' + divFullParms).hide();
        } else if ( runType == 'verifyOpenStack' ) {
            verifyXCATForm.find('#' + divFullParms).show();
        } else {
            verifyXCATForm.find('#' + divFullParms).hide();
        }
    });

    //************************************************************************
    // Function: Run immediately button.
    //************************************************************************
    var verifyBtn = createButton( 'Run this IVP Now' );
    verifyBtn.click(function() {
        var driveFunction = 1;
        var argList = '';

        // Remove any warning messages
        $(this).parents('.ui-tabs-panel').find('.ui-state-error').remove();

        var runType = $(this).parent().find('input[name="runType"]:checked').val();
        if ( runType == 'verifyBasic' ) {
            argList += '||--basicivp';
        } else if ( runType == 'verifyOpenStack' ) {
            argList += '||--fullivp';
            var openstackIP = $(this).parent().find('input[name=openstackIP]').val();
            if ( openstackIP != '' ) {
                argList += '||--openstackip ' + openstackIP;
            } else {
                // Show an information message.
                $('#' + statBarId).find('div').append(
                    'You did not specify the IP address of the OpenStack system.  The IVP ' +
                    'will use the IP address of the system running the xCAT management node as ' +
                    'the OpenStack IP address.<br>');
            }
            var openstackUser = $(this).parent().find('input[name=openstackUser]').val();
            if ( openstackUser != '' ) {
                argList += '||--openstackuser ' + hexEncode( openstackUser );
            }
            var prepParms = $(this).parent().find('input[name=prepParms]').val();
            if ( prepParms != '' ) {
                argList += '||--prepparms ' + hexEncode( prepParms );
            }
        } else {
            // Show warning message
            var warn = createWarnBar('You did not select a basic or full IVP.');
            warn.prependTo($(this).parents('.ui-tabs-panel'));
            driveFunction = 0;
        }
        var orchParms = $(this).parent().find('input[name=orchParms]').val();
        if ( orchParms != '' ) {
            argList += '||--orchparms ' + hexEncode( orchParms );
        }
        var mainParms = $(this).parent().find('input[name=mainParms]').val();
        if ( mainParms != '' ) {
            argList += '||--zxcatparms ' + hexEncode( mainParms );
        }
        argList += '||end';

        if ( driveFunction == 1 ) {
            $('#' + statBarId).find('div').append( 'Invoking verifynode to run the IVP.<br>' );
            $('#' + statBarId).find('img').show();
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd  : 'webrun',
                    tgt  : '',
                    args : 'verifynode '+ argList,
                    msg  : 'out=' + statBarId + ';cmd=verifynode'
                },
                success : updateStatusBar
            });

            // Show status bar
            statBar.show();
        }
    });
    verifyXCATForm.append( verifyBtn );

    //************************************************************************
    // Function: Save an IVP button.
    //************************************************************************
    var scheduleBtn = createButton( 'Save this IVP Run' );
    scheduleBtn.click(function() {
        var driveFunction = 1;
        var argList = '';

        // Remove any warning messages
        $(this).parents('.ui-tabs-panel').find('.ui-state-error').remove();

        var ivpId = $(this).parent().find('select[name=ivpId]').val();
        if ( ivpId != 'NEW' ) {
            argList += '||--id ' + ivpId;
        }
        var runType = $(this).parent().find('input[name="runType"]:checked').val();
        if ( runType == 'verifyBasic' ) {
            argList += '||--type basicivp';
        } else if ( runType == 'verifyOpenStack' ) {
            argList += '||--type fullivp';
            var openstackIP = $(this).parent().find('input[name=openstackIP]').val();
            if ( openstackIP != '' ) {
                argList = argList + '||--openstackip ' + openstackIP;
            } else {
                // Show an information message.
                $('#' + statBarId).find('div').append(
                        'You did not specify the IP address of the OpenStack system.  The IVP ' +
                        'will use the IP address of the system running the xCAT management node as ' +
                        'the OpenStack IP address.<br>');
            }
            var openstackUser = $(this).parent().find('input[name=openstackUser]').val();
            if ( openstackUser != '' ) {
                argList += '||--openstackuser ' + hexEncode( openstackUser );
            } else {
                argList += '||--openstackuser \'\'';
            }
            var prepParms = $(this).parent().find('input[name=prepParms]').val();
            if ( prepParms != '' ) {
                argList += '||--prepparms ' + hexEncode( prepParms );
            } else {
                argList += '||--prepparms \'\'';
            }
        } else {
            // Show warning message
            var warn = createWarnBar('You did not select a basic or full IVP.');
            warn.prependTo($(this).parents('.ui-tabs-panel'));
            driveFunction = 0;
        }
        var ivpSchedule = "";
        var checkboxes = $(this).parent().find('input[name="ivpSchedule"]:checked');
        var everyHourChecked = $(this).parent().find('input[name="ivpSchedule"][value=24]').is(':checked')
        if ( everyHourChecked ) {
            ivpSchedule = '0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23';
        } else {
        for ( var i=0, n=checkboxes.length; i<n; i++ )
        {
            if ( checkboxes[i].checked )
            {
                ivpSchedule += " " + checkboxes[i].value;
            }
        }
        }
        if ( ivpSchedule != '' ) {
            argList += '||--schedule \'' + ivpSchedule + '\'';
        } else {
            // Show warning message
            var warn = createWarnBar('You did select the hours to run an IVP.');
            warn.prependTo($(this).parents('.ui-tabs-panel'));
            driveFunction = 0;
        }
        var comments = $(this).parent().find('input[name=comments]').val();
        if ( comments != '' ) {
            argList += '||--comments ' + hexEncode( comments );
        } else {
            argList += '||--comments \'\'';
        }
        var disableRun = $(this).parent().find('input[name="disableRun"]').is(':checked');
        if ( disableRun ) {
            argList += '||--disable';
        } else {
            argList += '||--enable';
        }
        var orchParms = $(this).parent().find('input[name=orchParms]').val();
        if ( orchParms != '' ) {
            argList += '||--orchparms ' + hexEncode( orchParms );
        } else {
            argList += '||--orchparms \'\'';
        }
        var mainParms = $(this).parent().find('input[name=mainParms]').val();
        if ( mainParms != '' ) {
            argList += '||--zxcatparms ' + hexEncode( mainParms );
        } else {
            argList += '||--zxcatparms \'\'';
        }
        argList += '||end';

        if ( driveFunction == 1 ) {
            $('#' + statBarId).find('div').append( 'Invoking verifynode to schedule the IVP.<br>' );
            $('#' + statBarId).find('img').show();
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd  : 'webrun',
                    tgt  : '',
                    args : 'verifynode '+ argList,
                    msg  : 'out=' + statBarId + ';cmd=verifynode;ivpId=' + ivpId
                },
                success : function(data) {
                    updateStatusBar(data);
                    var args = data.msg.split(';');
                    var ivpId = '';
                    for ( var i=0; i < args.length; i++ ) {
                        if ( args[i].match('^ivpId=') ) {
                            ivpId = args[i].replace('ivpId=', '');
                        }
                    }
                    readIvpTable( 'NEW' );
                }
            });

            // Show status bar
            statBar.show();
        }
    });
    verifyXCATForm.append( scheduleBtn );

    //************************************************************************
    // Function: Remove an IVP button.
    //************************************************************************
    var removeBtn = createButton( 'Remove this IVP Run' );
    removeBtn.click(function() {
        var driveFunction = 1;
        var argList = '';

        // Remove any warning messages
        $(this).parents('.ui-tabs-panel').find('.ui-state-error').remove();

        var ivpId = $(this).parent().find('select[name=ivpId]').val();
        if ( ivpId != 'NEW' ) {
            argList = '||--remove' + '||--id ' + ivpId + '||end';
        } else {
            // Show warning message
            var warn = createWarnBar('You did not select the ID of an existing run.');
            warn.prependTo($(this).parents('.ui-tabs-panel'));
            driveFunction = 0;
        }

        if ( driveFunction == 1 ) {
            $('#' + statBarId).find('div').append( 'Invoking verifynode to remove the IVP.<br>' );
            $('#' + statBarId).find('img').show();
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd  : 'webrun',
                    tgt  : '',
                    args : 'verifynode '+ argList,
                    msg  : 'out=' + statBarId + ';cmd=verifynode'
                },
                success : function(data) {
                    updateStatusBar(data);
                    readIvpTable( 'NEW' );
                }
            });

            // Show status bar
            statBar.show();
        }
    });
    verifyXCATForm.append( removeBtn );

    tab.add( xcatVerTabId, 'Verify xCAT', verifyXCATForm, false );
}


/**
 * Check each hour checkbox when the "Every Hour" checkbox is checked.
 *
 * @param cb checkbox object that was checked or unchecked.
 */
function everyHourClick( cb ) {
    if ( cb.checked ) {
        for (var i = 0; i <= 23; i++){
            var thisField = $( '#' + xcatVerTabId + ' input[name=ivpSchedule][value='+i+']' );
            thisField.attr( 'checked', true );
        }
    }
}


/**
 * Get node tab
 *
 * @return Tab object
 */
function getHelpTab() {
    return helpTab;
}


/**
 * Decodes a printable hex string back into the javascript
 * unicode string that it represents.
 *
 * @param hexVal Printable hex string to convert
 *               back into its original javascript string form.
 */
hexDecode = function( hexVal ){
    var result = "";

    if ( hexVal.match("^HexEncoded:") ) {
        hexVal = hexVal.replace( 'HexEncoded:', '' );
        var hexes = hexVal.match(/.{1,4}/g) || [];
        for( var i = 0; i < hexes.length; i++ ) {
            result += String.fromCharCode( parseInt( hexes[i], 16 ) );
        }
    } else {
        result = hexVal;
    }

    return result;
}


/**
 * Encode a string into printable hex.  This avoids
 * an issues with escaping quotes or handling unicode.
 *
 * @param str String to encode into printable hex.
 */
function hexEncode( str ){
    var hex;

    var result = 'HexEncoded:';
    for (var i=0; i < str.length; i++) {
        hex = str.charCodeAt(i).toString(16);
        result += ("000"+hex).slice(-4);
    }

    return result;
}


/**
 * Handle click of an hour checkbox to uncheck the 24 hour checkbox, if this
 * was an uncheck of the hour.
 *
 * @param cb checkbox object that was checked or unchecked.
 */
function hourClick( cb ) {
    if ( ! cb.checked ) {
        var thisField = $( '#' + xcatVerTabId + ' input[name=ivpSchedule][value="24"]' );
        thisField.attr( 'checked', false );
    }
}


/**
 * Drive the tabdump API to obtain the scheduled IVP information.
 *
 * @param ivpId - Id of the IVP for which we should setup the panel fields
 *                after the read.  Currently, it is required to be 'NEW'.
 */
function readIvpTable( ivpId ) {
    if ( typeof console == "object" ) {
        console.log( "Entering readIvpTable(" + ivpId + ")" );
}

    // Get IVP information
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd  : 'tabdump',
            tgt  : '',
            args : 'zvmivp',
            msg  : 'ivpId=' + ivpId
        },

        success : function( data ) {
            setArrays( data );
            var ivpId = data.msg.replace('ivpId=', '');
            setVarsForId( ivpId );
        }
    });
}


/**
 * Setup the arrays/hashes with the data from the zvmivp table
 *
 * @param data Data from HTTP request
 */
function setArrays(data) {
    if ( typeof console == "object" ) {
        console.log( "Entering setArrays(" + data.rsp + ")" );
    }

    // Get response
    var rsp = data.rsp;

    // Clear the list of IVP information.
    ivpChoices = new Array();
    ivpChoiceValues = new Array();
    selectInfo = new Object();

    // Get column value
    var idPos = 0;
    var ipPos = 0;
    var schedulePos = 0;
    var lrPos = 0;
    var torPos = 0;
    var aUserPos = 0;
    var oParmsPos = 0;
    var pParmsPos = 0;
    var mainParmsPos = 0;
    var cmntPos = 0;

    var colNameArray = rsp[0].substr(1).split(',');
    for ( var i in colNameArray ) {
        switch ( colNameArray[i] ) {
            case 'id':
                idPos = i;
                break;
            case 'ip':
                ipPos = i;
                break;
            case 'schedule':
                schedulePos = i;
                break;
            case 'last_run':
                lrPos = i;
                break;
            case 'type_of_run':
                typeOfRunPos = i;
                break;
            case 'access_user':
                aUserPos = i;
                break;
            case 'orch_parms':
                oParmsPos = i;
                break;
            case 'prep_parms':
                pParmsPos = i;
                break;
            case 'main_ivp_parms':
                mainParmsPos = i;
                break;
            case 'comments':
                cmntPos = i;
                break;
            case 'disable':
                disablePos = i;
                break;
            default :
                break;
        }
    }

    // Get IVP information from the table data.
    for (var i = 1; i < rsp.length; i++) {
        var cols = rsp[i].split(',');
        var id = cols[idPos].replace(new RegExp('"', 'g'), '');
        var ip = cols[ipPos].replace(new RegExp('"', 'g'), '');
        var schedule = cols[schedulePos].replace(new RegExp('"', 'g'), '');
        var typeOfRun = cols[typeOfRunPos].replace(new RegExp('"', 'g'), '');
        var openstackUser = cols[aUserPos].replace(new RegExp('"', 'g'), '');
        var orchParms = cols[oParmsPos].replace(new RegExp('"', 'g'), '');
        var prepParms = cols[pParmsPos].replace(new RegExp('"', 'g'), '');
        var mainParms = cols[mainParmsPos].replace(new RegExp('"', 'g'), '');
        var comments = cols[cmntPos].replace(new RegExp('"', 'g'), '');
        var disable = cols[disablePos].replace(new RegExp('"', 'g'), '');

        ivpChoiceValues.push( id );
        selectInfo[id] = new Object();
        selectInfo[id]['id'] = id;
        selectInfo[id]['ip'] = ip;
        selectInfo[id]['schedule'] = schedule;
        selectInfo[id]['typeOfRun'] = typeOfRun.toLowerCase();
        selectInfo[id]['openstackUser'] = hexDecode( openstackUser );
        selectInfo[id]['orchParms'] = hexDecode( orchParms );
        selectInfo[id]['prepParms'] = hexDecode( prepParms );
        selectInfo[id]['mainParms'] = hexDecode( mainParms );
        selectInfo[id]['comments'] = hexDecode(comments);
        selectInfo[id]['disable'] = disable.toLowerCase();
    }

    // Sort the choices so we get a pretty list and build the choice strings.
    ivpChoiceValues.sort( function(a, b) {
        if ( ! isNaN(a) && ! isNaN(b) ) {
            // Both are numbers, do a numeric compare
            return a-b;
        } else if ( isNaN(a) && isNaN(b) ) {
            // Both are strings, do a string compare
            return a.localeCompare( b );
        } else if ( isNaN(a) ) {
            // Strings go after numbers
            return 1;
        } else {
            // Numbers go before strings
            return -1;
        }
    } );
    ivpChoiceValues.forEach( function( id ) {
        var idComments;
        if ( selectInfo[id]['comments'] != '' ) {
            idComments = id + ': ' + selectInfo[id]['comments'];
        } else {
            idComments = id + ': A comment was not specified.';
        }
        ivpChoices.push( idComments );
    }, this);

    // Clear out a hash element for the 'NEW' choice.
    selectInfo['NEW'] = new Object();
    selectInfo['NEW']['id'] = '';
    selectInfo['NEW']['ip'] = '';
    selectInfo['NEW']['schedule'] = '';
    selectInfo['NEW']['typeOfRun'] = '';
    selectInfo['NEW']['openstackUser'] = '';
    selectInfo['NEW']['orchParms'] = '';
    selectInfo['NEW']['prepParms'] = '';
    selectInfo['NEW']['mainParms'] = '';
    selectInfo['NEW']['comments'] = '';
    selectInfo['NEW']['disable'] = '';

    // Add in the NEW option at the top of the array.
    ivpChoices.unshift( "NEW: New IVP" );
    ivpChoiceValues.unshift( "NEW" );

    // Construct the new Select option choices
    var ivpChoicesLen = ivpChoices.length;
    var selectIdOptions = '';
    for ( var i = 0; i < ivpChoicesLen; i++ ) {
        selectIdOptions += '<option value="' + ivpChoiceValues[i] + '">' + ivpChoices[i] + '</option>';
    }

    // Find the division containing the select and replace its contents
    var thisIvpSelect = $( '#' + xcatVerTabId + ' select[name=ivpId]' );
    thisIvpSelect.children().remove();
    thisIvpSelect.append( selectIdOptions );
}


/**
 * Set node tab
 *
 * @param tab
 *            Tab object
 * @return Nothing
 */
function setHelpTab(tab) {
    helpTab = tab;
}


/**
 * Set IVP variables based on the chosen Id
 *
 * @param data Data from HTTP request
 */
function setVarsForId( id ) {
    if ( typeof console == "object" ) {
        console.log( "Entering setVarsForId(" + id + ")" );
    }

    var thisField = $( '#' + xcatVerTabId + ' input[name="runType"]' );
    if ( selectInfo[id]['typeOfRun'] == 'basicivp' ) {
        thisField.val(['verifyBasic']);
    } else if ( selectInfo[id]['typeOfRun'] == 'fullivp' ) {
        thisField.val(['verifyOpenStack']);
    } else {
        thisField.val([]);
    }

    thisField = $( '#' + xcatVerTabId + ' input[name=orchParms]' );
    thisField.val( selectInfo[id]['orchParms'] );

    thisField = $( '#' + xcatVerTabId + ' input[name=prepParms]' );
    thisField.val( selectInfo[id]['prepParms'] );

    var thisfield = $( '#' + xcatVerTabId + ' input[name=mainParms]' );
    thisfield.val( selectInfo[id]['mainParms'] );

    thisField = $( '#' + xcatVerTabId + ' input[name=openstackIP]' );
    thisField.val( selectInfo[id]['ip'] );

    thisField = $( '#' + xcatVerTabId + ' input[name=openstackUser]' );
    thisField.val( selectInfo[id]['openstackUser'] );

    var hours = new Object();
    var fullDay = 1;
    var hour = selectInfo[id]['schedule'].split(' ');
    for ( var j = 0; j < hour.length; j++ ) {
        hours[hour[j]] = 1;
    }

    for (var i = 0; i <= 23; i++) {
        thisField = $( '#' + xcatVerTabId + ' input[name=ivpSchedule][value='+i+']' );
        if ( hours[i] == 1 ) {
            thisField.attr( 'checked', true );
        } else {
            fullDay = 0;
            thisField.attr( 'checked', false );
        }
    }
    if ( fullDay == 1 ) {
        thisField = $( '#' + xcatVerTabId + ' input[name=ivpSchedule][value=24]' );
        thisField.attr( 'checked', true );
    } else {
            thisField = $( '#' + xcatVerTabId + " input[name=ivpSchedule][value=24]" );
            thisField.attr( 'checked', false );
        }

    thisField = $( '#' + xcatVerTabId + ' input[name=comments]' );
    thisField.val( selectInfo[id]['comments'] );

    thisField = $( '#' + xcatVerTabId + ' input[name=disableRun][value=disabled]' );
    if ( selectInfo[id]['disable'] == 1 || selectInfo[id]['disable'] == 'yes' ) {
        thisField.attr( 'checked', true );
    } else {
        thisField.attr( 'checked', false );
    }
}


/**
 * Update status bar of a given tab
 *
 * @param data Data returned from HTTP request
 */
function updateStatusBar(data) {
    if ( typeof console == "object" ) {
        console.log( "Entering updateStatusBar(\nmsg: " + data.msg + "\nrsp: " + data.rsp + ")" );
    }

    // Get ajax response
    var rsp = data.rsp;
    var args = data.msg.split(';');
    var statBarId = '';
    var cmd = '';
    for ( var i=0; i < args.length; i++ ) {
        if ( args[i].match('^cmd=') ) {
            cmd = args[i].replace('cmd=', '');
        } else if ( args[i].match('^out=') ) {
            statBarId = args[i].replace('out=', '');
        }
    }

    if (cmd == 'verifynode') {
        // Hide loader
        $('#' + statBarId).find('img').hide();

        // Write ajax response to status bar
        var prg = writeRsp(rsp, '');
        $('#' + statBarId).find('div').append(prg);

        // Put a check box after the response.
        var icon = $('<span class="ui-icon ui-icon-circle-check"></span>').css({
            'vertical-align': 'top'
        });
        $('#' + statBarId).find( 'div' ).append(icon);
        $('#' + statBarId).find( 'div' ).append( '<br/><br/>' );
    } else {
        // Hide loader
        $('#' + statBarId).find('img').hide();

        // Write ajax response to status bar
        var prg = writeRsp(rsp, '');
        $('#' + statBarId).find('div').append(prg);
    }
}
