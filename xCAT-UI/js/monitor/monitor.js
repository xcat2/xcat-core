/**
 * Global variables
 */
var monitorTabs; // Monitor tabs

/**
 * Set the monitor tab
 *
 * @param o
 *            Tab object
 * @return Nothing
 */
function setMonitorTab(o) {
    monitorTabs = o;
}

/**
 * Get the monitor tab
 *
 * @return Tab object
 */
function getMonitorTab() {
    return monitorTabs;
}

/**
 * Load the monitor page
 */
function loadMonitorPage() {
    // If the page is already loaded
    if ($('#monitor_page').children().length) {
        // Do not reload the monitor page
        return;
    }

    // Create monitor tab
    var tab = new Tab();
    setMonitorTab(tab);
    tab.init();
    $('#content').append(tab.object());

    var monitorForm = $('<div class="form"></div>');
    monitorForm.append('Getting monitoring status ').append(createLoader());
    tab.add('monitorTab', 'Monitor', monitorForm, false);

    // Get monitoring status of each tool
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'monls',
            msg : ''
        },

        /**
         * Load monitoring status
         *
         * @param data Data returned from HTTP request
         */
        success : function(data){
            data = decodeRsp(data);
            // Initialize status for each tool
            var statusHash = new Object();
            statusHash['xcatmon'] = 'Off';
            statusHash['rmcmon'] = 'Off';
            statusHash['rmcevent'] = 'Off';
            statusHash['gangliamon'] = 'Off';
            if (data.rsp[0]) {
                var tempArray = data.rsp[0].split(';');
                var position = 0;
                var name = '';
                var status = '';
                for ( var i in tempArray) {
                    position = tempArray[i].indexOf(':');
                    if (position == -1) {
                        continue;
                    }

                    name = tempArray[i].substr(0, position);
                    status = tempArray[i].substr(position + 1);
                    statusHash[name] = status;
                }
            }

            // Create a status buttonset for each monitoring tool
            var statusButtonHash = new Object();
            for ( var name in statusHash) {
                var statusButton = $('<div></div>').css({
                    'width': '100px',
                    'text-align': 'center'
                });
                statusButtonHash[name] = statusButton;

                // Set button to correct status
                if (statusHash[name] == 'On') {
                    statusButton.append($('<input type="radio" id="' + name + 'On" name="' + name + '" value="On" checked="checked"/><label for="' + name + 'On">On</label>'));
                    statusButton.append($('<input type="radio" id="' + name + 'Off" name="' + name + '" value="Off"/><label for="' + name + 'Off">Off</label>'));
                } else {
                    statusButton.append($('<input type="radio" id="' + name + 'On" name="' + name + '" value="On"/><label for="' + name + 'On">On</label>'));
                    statusButton.append($('<input type="radio" id="' + name + 'Off" name="' + name + '" value="Off" checked="checked"/><label for="' + name + 'Off">Off</label>'));
                }

                statusButton.find('label').css({
                    'margin': '0px',
                    'padding': '0px',
                    'font-size': '10px',
                    'width': 'auto'
                });
                statusButton.buttonset();

                // Turn on or off monitoring tool when clicked
                statusButton.find('input["' + name + '"]:radio').change(toggleMonitor);
            }

            var monTable = $('<table></table>');
            monTable.append($('<thead class="ui-widget-header"><tr><th><b>Tool</b></th><th><b>Status</b></th><th><b>Description</b></th></tr></thead>'));

            var monTableBody = $('<tbody></tbody>');
            monTable.append(monTableBody);

            var xcatMon = $('<tr></tr>');
            xcatMon.append($('<td><a href="#" name="xcatmon">xCAT</a></td>'));
            xcatMon.append($('<td></td>').append(statusButtonHash['xcatmon']));
            xcatMon.append($('<td>xCAT provides node status monitoring using fping on AIX and nmapon Linux. It also provides application status monitoring. The status and the appstatus columns of the nodelist table will be updated periodically with the latest status values for the nodes.</td>'));
            monTableBody.append(xcatMon);

            var rmcMon = $('<tr></tr>');
            rmcMon.append($('<td><a href="#" name="rmcmon">RMC</a></td>'));
            rmcMon.append($('<td></td>').append(statusButtonHash['rmcmon']));
            rmcMon.append($('<td>Resource Monitoring and Control (RMC) is a generalized framework for managing, monitoring and manipulating resources, such as physical or logical system entities. RMC is utilized as a communication mechanism for reporting service events to the Hardware Management Console (HMC).</td>'));
            monTableBody.append(rmcMon);

            var rmcEvent = $('<tr></tr>');
            rmcEvent.append($('<td><a href="#" name="rmcevent">RMC Event</a></td>'));
            rmcEvent.append($('<td></td>').append(statusButtonHash['rmcevent']));
            rmcEvent.append($('<td>Shows a list of events recorded by the RSCT Event Response resource manager in the audit log.</td>'));
            monTableBody.append(rmcEvent);

            var gangliaMon = $('<tr></tr>');
            gangliaMon.append($('<td><a href="#" name="gangliamon">Ganglia</a></td>'));
            gangliaMon.append($('<td></td>').append(statusButtonHash['gangliamon']));
            gangliaMon.append($('<td>Ganglia is a scalable distributed monitoring system for high-performance computing systems such as clusters and Grids.</td>'));
            monTableBody.append(gangliaMon);

            // Do not word wrap
            monTableBody.find('td:nth-child(1)').css('white-space', 'nowrap');
            monTableBody.find('td:nth-child(3)').css({
                'white-space': 'normal',
                'text-align': 'left'
            });

            // Append info bar
            $('#monitorTab div').empty().append(createInfoBar('Select a monitoring tool to use'));
            $('#monitorTab .form').append(monTable);

            // Open monitoring tool onclick
            $('#monitorTab .form a').bind('click', function() {
                loadMonitorTab($(this).attr('name'));
            });
        }
    });
}

/**
 * Load monitoring tool in a new tab
 *
 * @param name Name of monitoring tool
 */
function loadMonitorTab(name) {
    // If the tab exist, then we only need to select it
    var tab = getMonitorTab();
    if ($("#" + name).length) {
        tab.select(name);
        return;
    }

    switch (name) {
        case 'xcatmon':
            tab.add(name, 'xCAT', '', true);
            loadXcatMon();
            break;
        case 'rmcmon':
            tab.add(name, 'RMC Monitor', '', true);
            loadRmcMon();
            break;
        case 'gangliamon':
            tab.add(name, 'Ganglia', '', true);
            loadGangliaMon();
            break;
        case 'rmcevent':
            tab.add(name, 'RMC Event', '', true);
            loadRmcEvent();
            break;
    }

    tab.select(name);
}

/**
 * Load tab showing 'Under contruction'
 *
 * @param monitorName Name of monitoring tool
 * @param tab Tab area
 */
function loadUnfinish(monitorName, tab) {
    var unfinishPage = $('<div></div>');
    unfinishPage.append(createInfoBar('Not yet supported'));
    tab.add(monitorName, 'Unfinished', unfinishPage, true);
}

/**
 * Turn on or off monitoring tool
 *
 * @return Nothing
 */
function toggleMonitor() {
    // Get the name of the monitoring tool
    var name = $(this).attr('name');
    // Get the status to toggle to, either on or off
    var status = $(this).val();

    // Start or stop monitoring plugin
    var command = 'monstart';
    if (status == 'Off') {
        command = 'monstop'    ;
    }

    // Start or stop monitoring on xCAT
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : command,
            tgt : '',
            args : name + '',
            msg : ''
        },
        success : function(data) {
            data = decodeRsp(data);
            // Start or stop monitoring on remote nodes
            $.ajax({
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : command,
                    tgt : '',
                    args : name + ';-r',
                    msg : name + ' switched ' + status
                },
                success : function(data) {
                    data = decodeRsp(data);
                    updateMonStatus(data);
                }
            });
        }
    });
}

/**
 * Update the monitoring status on Monitor tab
 *
 * @param data Data returned from HTTP request
 */
function updateMonStatus(data) {
    var rsp = data.rsp[data.rsp.length-1];
    var msg = data.msg;

    // Create appropriate info or warning bar
    var bar = '';
    if (rsp.indexOf('started') > -1 || rsp.indexOf('stopped') > -1) {
        bar = createInfoBar(msg);
    } else {
        bar = createWarnBar('Failed to ' + msg + '. ' + rsp);
    }

    // Prepend info or warning bar to tab
    bar.prependTo($('#monitorTab .form'));
    bar.delay(4000).slideUp();
}
