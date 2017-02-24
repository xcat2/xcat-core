/**
 * Global variables
 */
var helpTab; // Help tabs
var ivpChoices = new Array;
var ivpChoiceValues = new Array;
var selectInfo = new Object();


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
    var comments = 'Description of the IVP run';
    var ivpEnabled = 'checked';
    var ivpDisabled = '';

    // Get the tab
    var tab = getHelpTab();
    var fs, legend;

    // Generate new tab ID
    var instance = 0;
    var newTabId = 'verifyXCATTab' + instance;
    while ($('#' + newTabId).length) {
        // If one already exists, generate another one
        instance = instance + 1;
        newTabId = 'verifyXCATTab' + instance;
    }

    // Build the list of IVPs in the table
    readIvpTable();

    // Create info bar and status bar
    var infoBar = createInfoBar( 'Run or schedule Installation Verification Procedures to verify:<br>' +
                                 '-xCAT MN/ZHCP Environment, or<br>' +
                                 '-xCAT MN/ZHCP and OpenStack Environment.' );

    var statBarId = 'verifyXCATStatusBar' + instance;
    var statBar = createStatusBar(statBarId).hide();
    var loader = createLoader( '' );
    statBar.find('div').append( loader );

    // Create the verify form and put info and status bars on the form.
    var verifyXCATForm = $( '<div class="form"></div>' );
    verifyXCATForm.append( infoBar, statBar );

    // Create 'Create a Verify xCAT' fieldset
    fs = $( '<fieldset></fieldset>' );
    fs.append( $( '<legend>Verify:</legend>' ));
    fs.append( $( '<div id=divIvpId><label>ID of Run:</label>'
                    + '<select name="ivpId" onchange= "setVarsForId( this )" >'
                    + '</select>'
                  + '</div>' ));
    fs.append( $('<div><span style="font-weight:bold">Type of IVP Run:</span></div>'));
    fs.append( $('<div><input type="radio" name="runType" value="verifyBasic"/>Basic IVP: xCAT MN/ZHCP Verification</div>' ));
    fs.append( $('<div><input type="radio" name="runType" value="verifyOpenStack"/>Full IVP: xCAT MN/ZHCP and OpenStack Verification</div>' ));
    fs.append( $('<div><span style="font-weight:bold">Basic and Full IVP Parameters:</span></div>'));
    fs.append( $('<div><label>Orchestrator Script Parameters:</label><input type="text" size="80" id="orchParms" name="orchParms" value="" title="Orchestrator script (verifynode) override parameters."/></div>' ));
    fs.append( $('<div><label>Main IVP Script Parameters:</label><input type="text" size="80" id="mainParms" name="mainParms" value="" title="Main IVP script (zxcatIVP) override parameters."/></div>' ));
    fs.append( $('<div><span style="font-weight:bold">Full IVP Parameters:</span></div>'));
    fs.append( $('<div><label>OpenStack System IP Address:</label><input type="text" id="openstackIP" name="openstackIP" value="" title="IP address of OpenStack system"/></div>' ));
    fs.append( $('<div><label>OpenStack user:</label><input type="text" id="openstackUser" name="openstackUser" value="" title="User under which OpenStack runs (e.g. nova)"/></div>' ));
    fs.append( $('<div><label>Preparation Script Parameters:</label><input type="text" size="80" id="prepParms" name="prepParms" value="" title="Preparation script override parameters."/></div>' ));
    fs.append( $('<div><span style="font-weight:bold">Automated IVP Parameters:</span></div>'));
    fs.append( $('<div><label>Automated IVP Comments:</label><input type="text" size="80" id="comments" name="comments" value="'+comments+'" title="Comments for an automated IVP run"/></div>' ));
    fs.append( '<div>'+
               '<table style="border: 0pm none; text-align: left;">'+
               '<tr>'+
               '<td style="background-color:rgb(220,220,220)"><span style="font-weight:bold">Schedule</span></td>'+
               '<td><input type="checkbox" value="0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23" name="ivpSchedule">Every hour</td>'+
               '</tr><tr>'+
               '<td><input type="checkbox" value="0" name="ivpSchedule">Midnight</td>'+
               '<td><input type="checkbox" value="1" name="ivpSchedule">1 am</td>'+
               '<td><input type="checkbox" value="2" name="ivpSchedule">2 am</td>'+
               '<td><input type="checkbox" value="3" name="ivpSchedule">3 am</td>'+
               '<td><input type="checkbox" value="4" name="ivpSchedule">4 am</td>'+
               '<td><input type="checkbox" value="5" name="ivpSchedule">5 am</td>'+
               '</tr><tr></td>'+
               '<td><input type="checkbox" value="6" name="ivpSchedule">6 am</td>'+
               '<td><input type="checkbox" value="7" name="ivpSchedule">7 am</td>'+
               '<td><input type="checkbox" value="8" name="ivpSchedule">8 am</td>'+
               '<td><input type="checkbox" value="9" name="ivpSchedule">9 am</td>'+
               '<td><input type="checkbox" value="10" name="ivpSchedule">10 am</td>'+
               '<td><input type="checkbox" value="11" name="ivpSchedule">11 am</td>'+
               '</tr><tr></td>'+
               '<td><input type="checkbox" value="12" name="ivpSchedule">Noon</td>'+
               '<td><input type="checkbox" value="13" name="ivpSchedule">1 pm</td>'+
               '<td><input type="checkbox" value="14" name="ivpSchedule">2 pm</td>'+
               '<td><input type="checkbox" value="15" name="ivpSchedule">3 pm</td>'+
               '<td><input type="checkbox" value="16" name="ivpSchedule">4 pm</td>'+
               '<td><input type="checkbox" value="17" name="ivpSchedule">5 pm</td>'+
               '</tr><tr></td>'+
               '<td><input type="checkbox" value="18" name="ivpSchedule">6 pm</td>'+
               '<td><input type="checkbox" value="19" name="ivpSchedule">7 pm</td>'+
               '<td><input type="checkbox" value="20" name="ivpSchedule">8 pm</td>'+
               '<td><input type="checkbox" value="21" name="ivpSchedule">9 pm</td>'+
               '<td><input type="checkbox" value="22" name="ivpSchedule">10 pm</td>'+
               '<td><input type="checkbox" value="23" name="ivpSchedule">11 pm</td>'+
               '</tr>'+
               '</table>'+
               '</div>');
    fs.append( $('<div>Disable or Enable the IVP Run:</div>'));
    fs.append( $('<div><input type="radio" name="disable" value="enabled"'+ivpEnabled+'/>Enabled to be run periodically</div>' ));
    fs.append( $('<div><input type="radio" name="disable" value="disabled"'+ivpDisabled+'/>Disabled from running periodically</div>' ));
    verifyXCATForm.append( fs );

    var verifyBtn = createButton( 'Run an IVP Now' );
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

    var scheduleBtn = createButton( 'Schedule an IVP Run' );
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
        var checkboxes = $(this).parent().find('input[name="ivpSchedule"]:checked');
        var ivpSchedule = "";
        for ( var i=0, n=checkboxes.length; i<n; i++ )
        {
            if ( checkboxes[i].checked )
            {
                ivpSchedule += " " + checkboxes[i].value;
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
        var disable = $(this).parent().find('input[name="disable"]:checked').val();
        if ( disable == 'disabled' ) {
            argList += '||--disable';
        } else if ( disable == 'enabled' ) {
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
                    msg  : 'out=' + statBarId + ';cmd=verifynode'
                },
                success : function(data) {
                    updateStatusBar(data);
                    readIvpTable();
                }
            });

            // Show status bar
            statBar.show();
        }
    });
    verifyXCATForm.append( scheduleBtn );

    var removeBtn = createButton( 'Remove an IVP Run' );
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
                    readIvpTable();
                }
            });

            // Show status bar
            statBar.show();
        }
    });
    verifyXCATForm.append( removeBtn );

    tab.add( newTabId, 'Verify xCAT', verifyXCATForm, false );

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
 * Drive the tabdump API to obtain the scheduled IVP information.
 *
 * @param None.
 */
function readIvpTable() {
    // Get IVP information
    if (!$.cookie('xcat_ivpinfo')){
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'tabdump',
                tgt : '',
                args : 'zvmivp',
                msg : ''
            },

            success : setArrays
        });
    }
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
 * Setup the arrays/hashes with the data from the zvmivp table
 *
 * @param data Data from HTTP request
 */
function setArrays(data) {
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
    var thisTabId = $(this).parents('.tab').attr('id');
    var thisIvpSelect = $( '#' + thisTabId + ' select[name=ivpId]' );
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
function setVarsForId( selected ) {
    var id = selected.value;

    // Change the form fields based on the selected ID.
    var thisTabId = $(this).parents('.tab').attr('id');

    var thisField = $( '#' + thisTabId + ' input[name="runType"]' );
    if ( selectInfo[id]['typeOfRun'] == 'basicivp' ) {
        thisField.val(['verifyBasic']);
    } else if ( selectInfo[id]['typeOfRun'] == 'fullivp' ) {
        thisField.val(['verifyOpenStack']);
    } else {
        var warn = createWarnBar('IVP with the id of '+id+' has an unrecognized type of run value: '+selectInfo[id]['typeOfRun']);
        warn.prependTo($(this).parents('.ui-tabs-panel'));
    }

    thisField = $( '#' + thisTabId + ' input[name=orchParms]' );
    thisField.val( selectInfo[id]['orchParms'] );

    thisField = $( '#' + thisTabId + ' input[name=prepParms]' );
    thisField.val( selectInfo[id]['prepParms'] );

    var thisfield = $( '#' + thisTabId + ' input[name=mainParms]' );
    thisfield.val( selectInfo[id]['mainParms'] );

    thisField = $( '#' + thisTabId + ' input[name=openstackIP]' );
    thisField.val( selectInfo[id]['ip'] );

    thisField = $( '#' + thisTabId + ' input[name=openstackUser]' );
    thisField.val( selectInfo[id]['openstackUser'] );

    var hours = new Object();
    var fullDay = 1;
    var hour = selectInfo[id]['schedule'].split(' ');
    for ( var j = 0; j < hour.length; j++ ) {
        hours[hour[j]] = 1;
    }

    for (var i = 0; i <= 23; i++) {
        thisField = $( '#' + thisTabId + ' input[name=ivpSchedule][value='+i+']' );
        if ( hours[i] == 1 ) {
            thisField.attr( 'checked', true );
        } else {
            fullDay = 0;
            thisField.attr( 'checked', false );
        }
    }
    if ( fullDay == 1 ) {
        thisField = $( '#' + thisTabId + ' input[name=ivpSchedule][value=Every hour]' );
        thisField.attr( 'checked', true );
        for (var i = 0; i <= 23; i++) {
            thisField = $( '#' + thisTabId + ' input[name=ivpSchedule][value='+i+']' );
            thisField.attr( 'checked', false );
        }
    }

    thisField = $( '#' + thisTabId + ' input[name=comments]' );
    thisField.val( selectInfo[id]['comments'] );

    thisField = $( '#' + thisTabId + ' input[name=disable]' );
    if ( selectInfo[id]['disable'] == 1 || selectInfo[id]['disable'] == 'yes' ) {
        thisField.val(['disabled']);
    } else if ( selectInfo[id]['disable'] == '' || selectInfo[id]['disable'] == 0 ) {
        thisField.val(['enabled']);
    } else {
        var warn = createWarnBar('IVP with the id of '+id+' has an unrecognized disable value: '+selectInfo[id]['disable']);
        warn.prependTo($(this).parents('.ui-tabs-panel'));
    }
}


/**
 * Update status bar of a given tab
 *
 * @param data Data returned from HTTP request
 */
function updateStatusBar(data) {
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
