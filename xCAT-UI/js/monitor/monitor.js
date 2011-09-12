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
 * @param Nothing
 * @return Tab object
 */
function getMonitorTab() {
	return monitorTabs;
}

/**
 * Load the monitor page
 * 
 * @return Nothing
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
		 * @param data
		 *            Data returned from HTTP request
		 * @return Nothing
		 */
		success : function(data){
			// Initialize status for each tool
			var statusHash = new Object();
			statusHash['xcatmon'] = 'Off';
			statusHash['rmcmon'] = 'Off';
			statusHash['rmcevent'] = 'Off';
			statusHash['gangliamon'] = 'Off';
			statusHash['pcpmon'] = 'Off';
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
			monTable.append($('<thead><tr><th><b>Tool</b></th><th><b>Status</b></th><th><b>Description</b></th></tr></thead>'));
			
			var monTableBody = $('<tbody></tbody>');
			monTable.append(monTableBody);			
			
			var xcatMon = $('<tr></tr>');
			xcatMon.append($('<td><a href="#" name="xcatmon">xCAT</a></td>'));
			xcatMon.append($('<td></td>').append(statusButtonHash['xcatmon']));
			xcatMon.append($('<td>Provides node status monitoring using fping on AIX and nmap on Linux. It also provides application status monitoring. The status and the appstatus columns of the nodelist table will be updated periodically  with the latest status values for the nodes.</td>'));
			monTableBody.append(xcatMon);
			
			var rmcMon = $('<tr></tr>');
			rmcMon.append($('<td><a href="#" name="rmcmon">RMC</a></td>'));
			rmcMon.append($('<td></td>').append(statusButtonHash['rmcmon']));
			rmcMon.append($('<td>IBM\'s Resource Monitoring and Control (RMC) subsystem is our recommended software for monitoring xCAT clusters. It\'s is part of the IBM\'s Reliable Scalable Cluster Technology (RSCT) that provides a comprehensive clustering environment for AIX and Linux.</td>'));
			monTableBody.append(rmcMon);
			
			var rmcEvent = $('<tr></tr>');
			rmcEvent.append($('<td><a href="#" name="rmcevent">RMC Event</a></td>'));
			rmcEvent.append($('<td></td>').append(statusButtonHash['rmcevent']));
			rmcEvent.append($('<td>Listing event monitoring information recorded by the RSCT Event Response resource manager in the audit log. Creating and removing a condition/response association.</td>'));
			monTableBody.append(rmcEvent);

			var gangliaMon = $('<tr></tr>');
			gangliaMon.append($('<td><a href="#" name="gangliamon">Ganglia</a></td>'));
			gangliaMon.append($('<td></td>').append(statusButtonHash['gangliamon']));
			gangliaMon.append($('<td>A scalable distributed monitoring system for high-performance computing systems such as clusters and Grids.</td>'));
			monTableBody.append(gangliaMon);
			
			var pcpMon = $('<tr></tr>');
			pcpMon.append($('<td><a href="#" name="pcpmon">PCP</a></td>'));
			pcpMon.append($('<td></td>').append(statusButtonHash['pcpmon']));
			pcpMon.append($('<td>Under construction.</td>'));
			monTableBody.append(pcpMon);
			
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
	
	// Create resources tab
	var resrcForm = $('<div class="form"></div>');

	// Create info bar
	var resrcInfoBar = createInfoBar('Select a platform to view its current resources.');
	resrcForm.append(resrcInfoBar);

	// Create radio buttons for platforms
	var hwList = $('<ol>Platforms available:</ol>');
	var ipmi = $('<li><input type="radio" name="hw" value="ipmi" checked/>iDataPlex</li>');
	var blade = $('<li><input type="radio" name="hw" value="blade"/>BladeCenter</li>');
	var hmc = $('<li><input type="radio" name="hw" value="hmc"/>System p</li>');
	var zvm = $('<li><input type="radio" name="hw" value="zvm"/>System z</li>');

	hwList.append(ipmi);
	hwList.append(blade);
	hwList.append(hmc);
	hwList.append(zvm);
	resrcForm.append(hwList);

	var okBtn = createButton('Ok');
	okBtn.bind('click', function(event) {
		// Get hardware that was selected
		var hw = $(this).parent().find('input[name="hw"]:checked').val();

		// Generate new tab ID
		var newTabId = hw + 'ResourceTab';
		if (!$('#' + newTabId).length) {
			// Create loader
			var loader = $('<center></center>').append(createLoader(hw + 'ResourceLoader'));
			tab.add(newTabId, hw, loader, true);

			// Create an instance of the plugin
			var plugin;
			switch (hw) {
				case "blade":
					plugin = new bladePlugin();
					break;
				case "hmc":
					plugin = new hmcPlugin();
					break;
				case "ipmi":
					plugin = new ipmiPlugin();
					break;
				case "zvm":
					plugin = new zvmPlugin();
					break;
			}

			plugin.loadResources();
		}

		// Select tab
		tab.select(newTabId);
	});
	
	resrcForm.append(okBtn);
	tab.add('resourceTab', 'Resources', resrcForm, false);
}

/**
 * Load monitoring tool in a new tab
 * 
 * @param name
 *            Name of monitoring tool
 * @return Nothing
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
		case 'pcpmon':
			loadUnfinish(name, tab);
			break;
	}

	tab.select(name);
}

/**
 * Load tab showing 'Under contruction'
 * 
 * @param monitorName
 *            Name of monitoring tool
 * @param tab
 *            Tab area
 * @return Nothing
 */
function loadUnfinish(monitorName, tab) {
	var unfinishPage = $('<div></div>');
	unfinishPage.append(createInfoBar('Under construction'));
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
		command = 'monstop'	;
	}
		
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : command,
			tgt : '',
			args : name + ';-r',
			msg : name + ' switched ' + status
		},
		success : updateMonStatus
	});
}

/**
 * Update the monitoring status on Monitor tab
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function updateMonStatus(data) {
	var rsp = data.rsp[data.rsp.length-1];
	var msg = data.msg;
	
	// Create appropriate info or warning bar
	var bar = '';
	if (rsp.indexOf('started') > -1 || rsp.indexOf('stopped') > -1) {
		bar = createInfoBar(msg);
	} else {
		var bar = createWarnBar('Failed to ' + msg + '. ' + rsp);
	}
	
	// Prepend info or warning bar to tab
	bar.prependTo($('#monitorTab .form'));
	bar.delay(4000).slideUp();
}