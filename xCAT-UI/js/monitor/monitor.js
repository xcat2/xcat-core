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
			var monitorStatusHash = new Object();
			monitorStatusHash['xcatmon'] = 'Not monitored';
			monitorStatusHash['rmcmon'] = 'Not monitored';
			monitorStatusHash['rmcevent'] = 'Not monitored';
			monitorStatusHash['gangliamon'] = 'Not monitored';
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
					monitorStatusHash[name] = status;
				}
			}		
			
			var monitorTable = '<table><thead><tr><th>Monitor Tool</th><th>Status</th><th>Description</th></tr></thead>';
			
			// xCAT monitor
			monitorTable += '<tbody><tr><td><a href="#" name="xcatmon">xCAT Monitor</a></td>';
			monitorTable += '<td>' + monitorStatusHash['xcatmon'] + '</td>';
			monitorTable += '<td>Provides node status monitoring using fping on AIX and nmap on Linux. It also provides application status monitoring. The status and the appstatus columns of the nodelist table will be updated periodically  with the latest status values for the nodes.</td></tr>';
			
			// RMC monitor 
			monitorTable += '<tr><td><a href="#" name="rmcmon">RMC Monitor</a></td>';
			monitorTable += '<td>' + monitorStatusHash['rmcmon'] + '</td>';
			monitorTable += '<td>IBM\'s Resource Monitoring and Control (RMC) subsystem is our recommended software for monitoring xCAT clusters. It\'s is part of the IBM\'s Reliable Scalable Cluster Technology (RSCT) that provides a comprehensive clustering environment for AIX and LINUX.</td></tr>';
			
			// RMC event
			monitorTable += '<tr><td><a href="#" name="rmcevent">RMC Event</a></td>';
			monitorTable += '<td>' + monitorStatusHash['rmcevent'] + '</td>';
			monitorTable += '<td>Listing event monitoring information recorded by the RSCT Event Response resource manager in the audit log. Creating and removing a condition/response association.</td></tr>';
			
			// Ganglia event
			monitorTable += '<tr><td><a href="#" name="gangliamon">Ganglia Monitor</a></td>';
			monitorTable += '<td>' + monitorStatusHash['gangliamon'] + '</td>';
			monitorTable += '<td>A scalable distributed monitoring system for high-performance computing systems such as clusters and Grids.</td></tr>';
			
			// PCP monitor
			monitorTable += '<tr><td><a href="#" name="pcpmon">PCP Monitor</a></td>';
			monitorTable += '<td>Not monitored</td>';
			monitorTable += '<td>Under construction.</td></tr>';
			
			monitorTable += '</tbody></table>';
			
			// Append info bar
			$('#monitorTab div').empty().append(createInfoBar('Select a monitoring tool to use.'));
			$('#monitorTab .form').append(monitorTable);
			
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
	tab.add(monitorName, 'Unfinish', unfinishPage, true);
}