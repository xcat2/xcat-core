/**
 * Global variables
 */
var serviceTabs;
var nodeName;
var nodePath;
var nodeStatus;
var gangliaTimer;

/**
 * Initialize service page
 */
function initServicePage() {
	// Reuqired JQuery plugins
	includeJs("js/jquery/jquery.dataTables.min.js");
	includeJs("js/jquery/jquery.cookie.min.js");
	includeJs("js/jquery/tooltip.min.js");
	includeJs("js/jquery/superfish.min.js");
	includeJs("js/jquery/jquery.jqplot.min.js");
    includeJs("js/jquery/jqplot.dateAxisRenderer.min.js");
	    
	// Show service page
	$("#content").children().remove();
	includeJs("js/service/service.js");
	includeJs("js/service/utils.js");
	loadServicePage();
}

/**
 * Load service page
 */
function loadServicePage() {
	// If the page is loaded
	if ($('#content').children().length) {
		// Do not load again
		return;
	}
		
	// Create manage and provision tabs
	serviceTabs = new Tab();
	serviceTabs.init();
	$('#content').append(serviceTabs.object());
	
	var manageTabId = 'manageTab';
	serviceTabs.add(manageTabId, 'Manage', '', false);
	loadManagePage(manageTabId);
	
	var provTabId = 'provisionTab';
	serviceTabs.add(provTabId, 'Provision', '', false);
	loadzProvisionPage(provTabId);

	serviceTabs.select(manageTabId);
	
	// Get zVM host names
	if (!$.cookie('srv_zvm')){
		$.ajax( {
			url : 'lib/srv_cmd.php',
			dataType : 'json',
			data : {
				cmd : 'webportal',
				tgt : '',
				args : 'lszvm',
				msg : ''
			},

			success : function(data) {
				setzVMCookies(data);
				loadzVMs();
			}
		});
	} else {
		loadzVMs();
	}
	
	// Get OS image names
	if (!$.cookie('srv_imagenames')){
		$.ajax( {
			url : 'lib/srv_cmd.php',
			dataType : 'json',
			data : {
				cmd : 'tabdump',
				tgt : '',
				args : 'osimage',
				msg : ''
			},

			success : function(data) {
				setOSImageCookies(data);
				loadOSImages();
			}
		});
	} else {
		loadOSImages();
	}
	
	// Get contents of hosts table
	if (!$.cookie('srv_groups')) {
		$.ajax( {
			url : 'lib/srv_cmd.php',
			dataType : 'json',
			data : {
				cmd : 'tabdump',
				tgt : '',
				args : 'hosts',
				msg : ''
			},

			success : function(data) {
				setGroupCookies(data);
				loadGroups();				
			}
		});
	} else {
		loadGroups();
	}
	
	// Get nodes owned by user
	$.ajax( {
		url : 'lib/srv_cmd.php',
		dataType : 'json',
		data : {
			cmd : 'tabdump',
			tgt : '',
			args : 'nodetype',
			msg : ''
		},

		success : function(data) {
			setUserNodes(data);
			getUserNodesDef();
			getNodesCurrentLoad();
		}
	});
	
	
}

/**
 * Load manage page
 * 
 * @param tabId
 * 			Tab ID where page will reside
 * @return Nothing
 */
function loadManagePage(tabId) {
	// Create manage form
	var loader = createLoader('');
	var manageForm = $('<div></div>').append(loader);

	// Append to manage tab
	$('#' + tabId).append(manageForm);
}

/**
 * Get the user nodes definitions
 */
function getUserNodesDef() {
	var userName = $.cookie('srv_usrname');
	var userNodes = $.cookie(userName + '_usrnodes');
	if (userNodes) {	
		 // Get nodes definitions
	    $.ajax( {
	        url : 'lib/srv_cmd.php',
	        dataType : 'json',
	        data : {
	            cmd : 'lsdef',
	            tgt : '',
	            args : userNodes,
	            msg : ''
	        },
	
	        success : loadNodesTable
	    });
	} else {
		prompt('Warning', $('<p>Your session has expired! Please log out and back in.</p>'));
	}
}

/**
 * Load user nodes definitions into a table
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function loadNodesTable(data) {
	// Clear the tab before inserting the table
	$('#manageTab').children().remove();
	
	// Nodes datatable ID
	var nodesDTId = 'userNodesDT';
	
	// Hash of node attributes
	var attrs = new Object();
	// Node attributes
	var headers = new Object();	
	var node, args;
	// Create hash of node attributes
	for (var i in data.rsp) {
		// Get node name
		if (data.rsp[i].indexOf('Object name:') > -1) {
			var temp = data.rsp[i].split(': ');
			node = jQuery.trim(temp[1]);

			// Create a hash for the node attributes
			attrs[node] = new Object();
			i++;
		}

		// Get key and value
		args = data.rsp[i].split('=', 2);
		var key = jQuery.trim(args[0]);
		var val = jQuery.trim(data.rsp[i].substring(data.rsp[i].indexOf('=') + 1, data.rsp[i].length));
		
		// Create a hash table
		attrs[node][key] = val;
		headers[key] = 1;
	}

	// Sort headers
	var sorted = new Array();
	var attrs2hide = new Array('status', 'statustime', 'appstatus', 'appstatustime', 'usercomment');
	var attrs2show = new Array('arch', 'groups', 'hcp', 'hostnames', 'ip', 'os', 'userid');
	for (var key in headers) {
		// Show node attributes
		if (jQuery.inArray(key, attrs2show) > -1) {
			sorted.push(key);
		}
	}
	sorted.sort();

	// Add column for check box, node, ping, power, monitor, and comments
	sorted.unshift('<input type="checkbox" onclick="selectAll(event, $(this))">', 
		'node', 
		'<span><a>status</a></span><img src="images/loader.gif" style="display: none;"></img>', 
		'<span><a>power</a></span><img src="images/loader.gif" style="display: none;"></img>',
		'<span><a>monitor</a></span><img src="images/loader.gif" style="display: none;"></img>',
		'comments');

	// Create a datatable
	var nodesDT = new DataTable(nodesDTId);
	nodesDT.init(sorted);
	
	// Go through each node
	for (var node in attrs) {
		// Create a row
		var row = new Array();
		
		// Create a check box, node link, and get node status
		var checkBx = $('<input type="checkbox" name="' + node + '"/>');
		var nodeLink = $('<a class="node" id="' + node + '">' + node + '</a>').bind('click', loadNode);
		
		// If there is no status attribute for the node, do not try to access hash table
		// Else the code will break
		var status = '';
		if (attrs[node]['status']) {
			status = attrs[node]['status'].replace('sshd', 'ping');
		}
			
		// Push in checkbox, node, status, monitor, and power
		row.push(checkBx, nodeLink, status, '', '');
		
		// If the node attributes are known (i.e the group is known)
		if (attrs[node]['groups']) {
			// Put in comments
			var comments = attrs[node]['usercomment'];			
			// If no comments exists, show 'No comments' and set icon image source
			var iconSrc;
			if (!comments) {
				comments = 'No comments';
				iconSrc = 'images/nodes/ui-icon-no-comment.png';
			} else {
				iconSrc = 'images/nodes/ui-icon-comment.png';
			}
					
			// Create comments icon
			var tipID = node + 'Tip';
			var icon = $('<img id="' + tipID + '" src="' + iconSrc + '"></img>').css({
				'width': '18px',
				'height': '18px'
			});
			
			// Create tooltip
			var tip = createCommentsToolTip(comments);
			var col = $('<span></span>').append(icon);
			col.append(tip);
			row.push(col);
		
			// Generate tooltips
			icon.tooltip({
				position: "center right",
				offset: [-2, 10],
				effect: "fade",	
				opacity: 0.8,
				relative: true,
				delay: 500
			});
		} else {
			// Do not put in comments if attributes are not known
			row.push('');
		}
		
		// Go through each header
		for (var i = 6; i < sorted.length; i++) {
			// Add the node attributes to the row
			var key = sorted[i];
			
			// Do not put comments and status in twice
			if (key != 'usercomment' && key != 'status' && key.indexOf('statustime') < 0) {
    			var val = attrs[node][key];
    			if (val) {
    				row.push($('<span>' + val + '</span>'));
    			} else {
    				row.push('');
    			}
			}
		}

		// Add the row to the table
		nodesDT.add(row);
	}
	
	// Create info bar
	var infoBar = createInfoBar('Manage and monitor your Linux virtual machines on System z.');
	$('#manageTab').append(infoBar);
	
	// Insert action bar and nodes datatable
	$('#manageTab').append(nodesDT.object());
		
	// Turn table into a datatable
	$('#' + nodesDTId).dataTable({
		'iDisplayLength': 50,
		'bLengthChange': false,
		"sScrollX": "100%",
		"sScrollXInner": "110%"
	});
	
	// Set datatable header class to add color
	$('.datatable thead').attr('class', 'ui-widget-header');
	
	// Do not sort ping, power, and comment column
	var cols = $('#' + nodesDTId + ' thead tr th').click(function() {		
		getNodeAttrs(group);
	});
	var checkboxCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(0)');
	var pingCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(2)');
	var powerCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(3)');
	var monitorCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(4)');
	var commentCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(5)');
	checkboxCol.unbind('click');
	pingCol.unbind('click');
	powerCol.unbind('click');
	monitorCol.unbind('click');
	commentCol.unbind('click');
	
	// Refresh the node ping, power, and monitor status on-click
	var nodes = getNodesShown(nodesDTId);
	pingCol.find('span a').click(function() {
		refreshNodeStatus(nodes);
	});
	powerCol.find('span a').click(function() {
		refreshPowerStatus(nodes);
	});
	monitorCol.find('span a').click(function() {
		refreshGangliaStatus(nodes);
	});
	
	// Create actions menu
	// Power on
	var powerOnLnk = $('<a>Power on</a>');
	powerOnLnk.click(function() {
		var tgtNodes = getNodesChecked(nodesDTId);
		if (tgtNodes) {
			powerNode(tgtNodes, 'on');
		}
	});
	
	// Power off
	var powerOffLnk = $('<a>Power off</a>');
	powerOffLnk.click(function() {
		var tgtNodes = getNodesChecked(nodesDTId);
		if (tgtNodes) {
			powerNode(tgtNodes, 'off');
		}
	});
	
	// Turn monitoring on
	var monitorOnLnk = $('<a>Monitor on</a>');
	monitorOnLnk.click(function() {
		var tgtNodes = getNodesChecked(nodesDTId);
		if (tgtNodes) {
			monitorNode(tgtNodes, 'on');
		}
	});

	// Turn monitoring off
	var monitorOffLnk = $('<a>Monitor off</a>');
	monitorOffLnk.click(function() {
		var tgtNodes = getNodesChecked(nodesDTId);
		if (tgtNodes) {
			monitorNode(tgtNodes, 'off');
		}
	});
	
	// Delete
	var deleteLnk = $('<a>Delete</a>');
	deleteLnk.click(function() {
		var tgtNodes = getNodesChecked(nodesDTId);
		if (tgtNodes) {
			deleteNode(tgtNodes);
		}
	});

	// Unlock
	var unlockLnk = $('<a>Unlock</a>');
	unlockLnk.click(function() {
		var tgtNodes = getNodesChecked(nodesDTId);
		if (tgtNodes) {
			unlockNode(tgtNodes);
		}
	});
	
	// Prepend menu to datatable
	var actionsLnk = '<a>Actions</a>';
	var actionMenu = createMenu([deleteLnk, powerOnLnk, powerOffLnk, monitorOnLnk, monitorOffLnk, unlockLnk]);
	var menu = createMenu([[actionsLnk, actionMenu]]);
	menu.superfish();
	$('#' + nodesDTId + '_filter').css('display', 'inline-block');
	$('#' + nodesDTId + '_wrapper').prepend(menu);
	
	$('.sf-menu li:hover, .sf-menu li.sfHover').attr('class', 'ui-widget-header');
	
	// Get power and monitor status
	var nodes = getNodesShown(nodesDTId);
	refreshPowerStatus(nodes);
	refreshGangliaStatus(nodes);	
}

/**
 * Refresh ping status for each node
 * 
 * @param nodes
 * 			Nodes to get ping status
 * @return Nothing
 */
function refreshNodeStatus(nodes) {
	// Show ping loader
	var nodesDTId = 'userNodesDT';
	var pingCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(2)');
	pingCol.find('img').show();
		
	// Get the node ping status
	$.ajax( {
		url : 'lib/srv_cmd.php',
		dataType : 'json',
		data : {
			cmd : 'nodestat',
			tgt : nodes,
			args : '-u',
			msg : ''
		},

		success : loadNodePing
	});
}

/**
 * Load node ping status for each node
 * 
 * @param data
 * 			Data returned from HTTP request
 * @return Nothing
 */
function loadNodePing(data) {
	var nodesDTId = 'userNodesDT';
	var datatable = $('#' + nodesDTId).dataTable();
	var rsp = data.rsp;
	var args, rowPos, node, status;

	// Get all nodes within datatable
	for (var i in rsp) {
		args = rsp[i].split(':');
		
		// args[0] = node and args[1] = status
		node = jQuery.trim(args[0]);
		status = jQuery.trim(args[1]).replace('sshd', 'ping');
		
		// Get row containing node
		rowPos = findRow(node, '#' + nodesDTId, 1);

		// Update ping status column
		datatable.fnUpdate(status, rowPos, 2, false);
	}
	
	// Hide status loader
	var pingCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(2)');
	pingCol.find('img').hide();
	datatable.fnDraw();
}

/**
 * Refresh power status for each node
 * 
 * @param nodes
 * 			Nodes to get power status
 * @return Nothing
 */
function refreshPowerStatus(nodes) {	
	// Show power loader
	var nodesDTId = 'userNodesDT';
	var powerCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(3)');
	powerCol.find('img').show();
			
	// Get power status
	$.ajax( {
		url : 'lib/srv_cmd.php',
		dataType : 'json',
		data : {
			cmd : 'rpower',
			tgt : nodes,
			args : 'stat',
			msg : ''
		},

		success : loadPowerStatus
	});
}

/**
 * Load power status for each node
 * 
 * @param data
 *   		Data returned from HTTP request
 * @return Nothing
 */
function loadPowerStatus(data) {
	var nodesDTId = 'userNodesDT';
	var datatable = $('#' + nodesDTId).dataTable();
	var power = data.rsp;
	var rowPos, node, status, args;

	for (var i in power) {
		// power[0] = nodeName and power[1] = state
		args = power[i].split(':');
		node = jQuery.trim(args[0]);
		status = jQuery.trim(args[1]);
		
		// Get the row containing the node
		rowPos = findRow(node, '#' + nodesDTId, 1);

		// Update the power status column
		datatable.fnUpdate(status, rowPos, 3, false);
	}
	
	// Hide power loader
	var powerCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(3)');
	powerCol.find('img').hide();
	datatable.fnDraw();
}

/**
 * Refresh the status of Ganglia for each node
 * 
 * @param nodes
 * 			Nodes to get Ganglia status
 * @return Nothing
 */
function refreshGangliaStatus(nodes) {
	// Show ganglia loader
	var nodesDTId = 'userNodesDT';
	var gangliaCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(4)');
	gangliaCol.find('img').show();
	
	// Get the status of Ganglia
	$.ajax( {
		url : 'lib/srv_cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'gangliastatus;' + nodes,
			msg : ''
		},

		success : loadGangliaStatus
	});
}

/**
 * Load the status of Ganglia for a given group
 * 
 * @param data
 * 			Data returned from HTTP request
 * @return Nothing
 */
function loadGangliaStatus(data) {
	// Get datatable
	var nodesDTId = 'userNodesDT';
	var datatable = $('#' + nodesDTId).dataTable();
	var ganglia = data.rsp;
	var rowNum, node, status;

	for ( var i in ganglia) {
		// ganglia[0] = nodeName and ganglia[1] = state
		node = jQuery.trim(ganglia[i][0]);
		status = jQuery.trim(ganglia[i][1]);

		// Get the row containing the node
		rowNum = findRow(node, '#' + nodesDTId, 1);

		// Update the power status column
		datatable.fnUpdate(status, rowNum, 4);
	}

	// Hide Ganglia loader
	var gangliaCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(4)');
	gangliaCol.find('img').hide();
	datatable.fnDraw();
}

/**
 * Load inventory for given node
 * 
 * @param e
 *            Windows event
 * @return Nothing
 */
function loadNode(e) {
	if (!e) {
		e = window.event;
	}
	
	// Get node that was clicked
	var node = (e.target) ? e.target.id : e.srcElement.id;
	
	// Create a new tab to show inventory
	var tabId = node + '_inventory';

	if(!$('#' + tabId).length) {
		// Add new tab, only if one does not exist
		var loader = createLoader(node + 'Loader');
		loader = $('<center></center>').append(loader);
		serviceTabs.add(tabId, node, loader, true);
			
		// Get node inventory
		var msg = 'out=' + tabId + ',node=' + node;
		$.ajax( {
			url : 'lib/srv_cmd.php',
			dataType : 'json',
			data : {
				cmd : 'rinv',
				tgt : node,
				args : 'all',
				msg : msg
			},

			success : showInventory
		});
	}	

	// Select new tab
	serviceTabs.select(tabId);
}

/**
 * Show node inventory
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function showInventory(data) {
	var args = data.msg.split(',');

	// Get tab ID
	var tabId = args[0].replace('out=', '');
	// Get node
	var node = args[1].replace('node=', '');
	// Get node inventory
	var inv = data.rsp[0].split(node + ':');

	// Remove loader
	$('#' + tabId).find('img').remove();

	// Create array of property keys
	var keys = new Array('userId', 'host', 'os', 'arch', 'hcp', 'priv', 'memory', 'proc', 'disk', 'nic');

	// Create hash table for property names
	var attrNames = new Object();
	attrNames['userId'] = 'z/VM UserID:';
	attrNames['host'] = 'z/VM Host:';
	attrNames['os'] = 'Operating System:';
	attrNames['arch'] = 'Architecture:';
	attrNames['hcp'] = 'HCP:';
	attrNames['priv'] = 'Privileges:';
	attrNames['memory'] = 'Total Memory:';
	attrNames['proc'] = 'Processors:';
	attrNames['disk'] = 'Disks:';
	attrNames['nic'] = 'NICs:';

	// Create hash table for node attributes
	var attrs = getAttrs(keys, attrNames, inv);

	// Create division to hold inventory
	var invDivId = node + 'Inventory';
	var invDiv = $('<div class="inventory" id="' + invDivId + '"></div>');
	
	var infoBar = createInfoBar('Below is the inventory for the virtual machine you selected.');
	invDiv.append(infoBar);

	/**
	 * General info section
	 */
	var fieldSet = $('<fieldset></fieldset>');
	var legend = $('<legend>General</legend>');
	fieldSet.append(legend);
	var oList = $('<ol></ol>');
	var item, label, args;

	// Loop through each property
	for ( var k = 0; k < 5; k++) {
		// Create a list item for each property
		item = $('<li></li>');

		// Create a label - Property name
		label = $('<label>' + attrNames[keys[k]] + '</label>');
		item.append(label);

		for ( var l = 0; l < attrs[keys[k]].length; l++) {
			// Create a input - Property value(s)
			// Handle each property uniquely
			item.append(attrs[keys[k]][l]);
		}

		oList.append(item);
	}
	// Append to inventory form
	fieldSet.append(oList);
	invDiv.append(fieldSet);
	
	/**
	 * Monitoring section
	 */
	fieldSet = $('<fieldset id="' + node + '_monitor"></fieldset>');
	legend = $('<legend>Monitoring</legend>');
	fieldSet.append(legend);
	getMonitorMetrics(node);
	
	// Append to inventory form
	invDiv.append(fieldSet);

	/**
	 * Hardware info section
	 */
	var hwList, hwItem;
	fieldSet = $('<fieldset></fieldset>');
	legend = $('<legend>Hardware</legent>');
	fieldSet.append(legend);
	oList = $('<ol></ol>');

	// Loop through each property
	var label;
	for (k = 5; k < keys.length; k++) {
		// Create a list item
		item = $('<li></li>');

		// Create a list to hold the property value(s)
		hwList = $('<ul></ul>');
		hwItem = $('<li></li>');

		/**
		 * Privilege section
		 */
		if (keys[k] == 'priv') {
			// Create a label - Property name
			label = $('<label>' + attrNames[keys[k]].replace(':', '') + '</label>');
			item.append(label);

			// Loop through each line
			for (l = 0; l < attrs[keys[k]].length; l++) {
				// Create a new list item for each line
				hwItem = $('<li></li>');

				// Determine privilege
				args = attrs[keys[k]][l].split(' ');
				if (args[0] == 'Directory:') {
					label = $('<label>' + args[0] + '</label>');
					hwItem.append(label);
					hwItem.append(args[1]);
				} else if (args[0] == 'Currently:') {
					label = $('<label>' + args[0] + '</label>');
					hwItem.append(label);
					hwItem.append(args[1]);
				}

				hwList.append(hwItem);
			}

			item.append(hwList);
		}

		/**
		 * Memory section
		 */
		else if (keys[k] == 'memory') {
			// Create a label - Property name
			label = $('<label>' + attrNames[keys[k]].replace(':', '') + '</label>');
			item.append(label);

			// Loop through each value line
			for (l = 0; l < attrs[keys[k]].length; l++) {
				// Create a new list item for each line
				hwItem = $('<li></li>');
				hwItem.append(attrs[keys[k]][l]);
				hwList.append(hwItem);
			}

			item.append(hwList);
		}

		/**
		 * Processor section
		 */
		else if (keys[k] == 'proc') {
			// Create a label - Property name
			label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
			item.append(label);

			// Create a table to hold processor data
			var procTable = $('<table></table>');
			var procBody = $('<tbody></tbody>');

			// Table columns - Type, Address, ID, Base, Dedicated, and Affinity
			var procTabRow = $('<thead class="ui-widget-header"> <th>Type</th> <th>Address</th> <th>ID</th> <th>Base</th> <th>Dedicated</th> <th>Affinity</th> </thead>');
			procTable.append(procTabRow);
			var procType, procAddr, procId, procAff;

			// Loop through each processor
			var n, temp;
			for (l = 0; l < attrs[keys[k]].length; l++) {
				if (attrs[keys[k]][l]) {			
    				args = attrs[keys[k]][l].split(' ');
    				
    				// Get processor type, address, ID, and affinity
    				n = 3;
    				temp = args[args.length - n];
    				while (!jQuery.trim(temp)) {
    					n = n + 1;
    					temp = args[args.length - n];
    				}
    				procType = $('<td>' + temp + '</td>');
    				procAddr = $('<td>' + args[1] + '</td>');
    				procId = $('<td>' + args[5] + '</td>');
    				procAff = $('<td>' + args[args.length - 1] + '</td>');
    
    				// Base processor
    				if (args[6] == '(BASE)') {
    					baseProc = $('<td>' + true + '</td>');
    				} else {
    					baseProc = $('<td>' + false + '</td>');
    				}
    
    				// Dedicated processor
    				if (args[args.length - 3] == 'DEDICATED') {
    					dedicatedProc = $('<td>' + true + '</td>');
    				} else {
    					dedicatedProc = $('<td>' + false + '</td>');
    				}
    
    				// Create a new row for each processor
    				procTabRow = $('<tr></tr>');
    				procTabRow.append(procType);
    				procTabRow.append(procAddr);
    				procTabRow.append(procId);
    				procTabRow.append(baseProc);
    				procTabRow.append(dedicatedProc);
    				procTabRow.append(procAff);
    				procBody.append(procTabRow);
				}
			}
			
			procTable.append(procBody);
			item.append(procTable);
		}

		/**
		 * Disk section
		 */
		else if (keys[k] == 'disk') {
			// Create a label - Property name
			label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
			item.append(label);

			// Create a table to hold disk (DASD) data
			var dasdTable = $('<table></table>');
			var dasdBody = $('<tbody></tbody>');

			// Table columns - Virtual Device, Type, VolID, Type of Access, and Size
			var dasdTabRow = $('<thead class="ui-widget-header"> <th>Virtual Device #</th> <th>Type</th> <th>VolID</th> <th>Type of Access</th> <th>Size</th> </thead>');
			dasdTable.append(dasdTabRow);
			var dasdVDev, dasdType, dasdVolId, dasdAccess, dasdSize;

			// Loop through each DASD
			for (l = 0; l < attrs[keys[k]].length; l++) {
				if (attrs[keys[k]][l]) {
    				args = attrs[keys[k]][l].split(' ');

    				// Get DASD virtual device, type, volume ID, access, and size
    				dasdVDev = $('<td>' + args[1] + '</td>');    
    				dasdType = $('<td>' + args[2] + '</td>');
    				dasdVolId = $('<td>' + args[3] + '</td>');
    				dasdAccess = $('<td>' + args[4] + '</td>');
    				dasdSize = $('<td>' + args[args.length - 9] + ' ' + args[args.length - 8] + '</td>');
    
    				// Create a new row for each DASD
    				dasdTabRow = $('<tr></tr>');
    				dasdTabRow.append(dasdVDev);
    				dasdTabRow.append(dasdType);
    				dasdTabRow.append(dasdVolId);
    				dasdTabRow.append(dasdAccess);
    				dasdTabRow.append(dasdSize);
    				dasdBody.append(dasdTabRow);
				}
			}

			dasdTable.append(dasdBody);
			item.append(dasdTable);
		}

		/**
		 * NIC section
		 */
		else if (keys[k] == 'nic') {
			// Create a label - Property name
			label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
			item.append(label);

			// Create a table to hold NIC data
			var nicTable = $('<table></table>');
			var nicBody = $('<tbody></tbody>');

			// Table columns - Virtual device, Adapter Type, Port Name, # of Devices, MAC Address, and LAN Name
			var nicTabRow = $('<thead class="ui-widget-header"><th>Virtual Device #</th> <th>Adapter Type</th> <th>Port Name</th> <th># of Devices</th> <th>LAN Name</th></thead>');
			nicTable.append(nicTabRow);
			var nicVDev, nicType, nicPortName, nicNumOfDevs, nicLanName;

			// Loop through each NIC (Data contained in 2 lines)
			for (l = 0; l < attrs[keys[k]].length; l = l + 2) {
				if (attrs[keys[k]][l]) {
    				args = attrs[keys[k]][l].split(' ');
    
    				// Get NIC virtual device, type, port name, and number of devices
    				nicVDev = $('<td>' + args[1] + '</td>');
    				nicType = $('<td>' + args[3] + '</td>');
    				nicPortName = $('<td>' + args[10] + '</td>');
    				nicNumOfDevs = $('<td>' + args[args.length - 1] + '</td>');
    
    				args = attrs[keys[k]][l + 1].split(' ');
    				nicLanName = $('<td>' + args[args.length - 2] + ' ' + args[args.length - 1] + '</td>');
    
    				// Create a new row for each DASD
    				nicTabRow = $('<tr></tr>');
    				nicTabRow.append(nicVDev);
    				nicTabRow.append(nicType);
    				nicTabRow.append(nicPortName);
    				nicTabRow.append(nicNumOfDevs);
    				nicTabRow.append(nicLanName);
    
    				nicBody.append(nicTabRow);
				}
			}

			nicTable.append(nicBody);
			item.append(nicTable);
		}

		oList.append(item);
	}

	// Append inventory to division
	fieldSet.append(oList);
	invDiv.append(fieldSet);
	invDiv.find('th').css({
		'padding': '5px 10px',
		'font-weight': 'bold'
	});

	// Append to tab
	$('#' + tabId).append(invDiv);
}

/**
 * Load provision page (z)
 * 
 * @param tabId
 * 			Tab ID where page will reside
 * @return Nothing
 */
function loadzProvisionPage(tabId) {	
	// Create provision form
	var provForm = $('<div></div>');

	// Create info bar
	var infoBar = createInfoBar('Provision a Linux virtual machine on System z by selecting the appropriate choices below.  Once you are ready, click on Provision to provision the virtual machine.');
	provForm.append(infoBar);

	// Append to provision tab
	$('#' + tabId).append(provForm);
	
	// Create provision table
	var provTable = $('<table id="select-table" style="margin: 10px;"></table');
	var provHeader = $('<thead class="ui-widget-header"> <th>zVM</th> <th>Group</th> <th>Image</th></thead>');
	var provBody = $('<tbody></tbody>');
	var provFooter = $('<tfoot></tfoot>');
	provTable.append(provHeader, provBody, provFooter);
	provForm.append(provTable);
	
	provHeader.children('th').css({
		'font': 'bold 12px verdana, arial, helvetica, sans-serif'
	});
	
	// Create row to contain selections
	var provRow = $('<tr></tr>');
	provBody.append(provRow);
	// Create columns for zVM, group, and image
	var zvmCol = $('<td style="vertical-align: top;"></td>');
	provRow.append(zvmCol);
	var groupCol = $('<td style="vertical-align: top;"></td>');
	provRow.append(groupCol);
	var imageCol = $('<td style="vertical-align: top;"></td>');
	provRow.append(imageCol);
	
	provRow.children('td').css({
		'min-width': '250px'
	});
	
	/**
	 * Provision VM
	 */
	var provisionBtn = createButton('Provision');
	provisionBtn.bind('click', function(event) {
		var hcp = $('#select-table tbody tr:eq(0) td:eq(0) input[name="hcp"]:checked').val();
		var group = $('#select-table tbody tr:eq(0) td:eq(1) input[name="group"]:checked').val();
		var img = $('#select-table tbody tr:eq(0) td:eq(2) input[name="image"]:checked').val();
		var owner = $.cookie('srv_usrname');;
		
		// Begin by creating VM
		createVM(tabId, group, hcp, img, owner);
	});
	provForm.append(provisionBtn);
}

/**
 * Create virtual machine
 * 
 * @param tabId
 * 			Tab ID
 * @param group
 * 			Group
 * @param hcp
 * 			Hardware control point
 * @param img
 * 			OS image
 * @return Nothing
 */
function createVM(tabId, group, hcp, img, owner) {
	var statBar = createStatusBar('provsionStatBar');
	var loader = createLoader('provisionLoader');
	statBar.find('div').append(loader);
	statBar.prependTo($('#provisionTab'));
	
	// Submit request to create VM
	// webportal provzlinux [group] [hcp] [image] [owner]
	$.ajax({
        url : 'lib/srv_cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webportal',
            tgt : '',
            args : 'provzlinux;' + group + ';' + hcp + ';' + img + ';' + owner,
            msg : '' 
        },
        success:function(data){
        	$('#provisionLoader').remove();
             for(var i in data.rsp){
                 $('#provsionStatBar').find('div').append('<pre>' + data.rsp[i] + '</pre>');
             }
             
             // Refresh nodes table
             $.ajax( {
         		url : 'lib/srv_cmd.php',
         		dataType : 'json',
         		data : {
         			cmd : 'tabdump',
         			tgt : '',
         			args : 'nodetype',
         			msg : ''
         		},

         		success : function(data) {
         			setUserNodes(data);
         		}
         	});
        }
    });
}

/**
 * Load zVMs into column
 */
function loadzVMs() {
	var zvmCol = $('#select-table tbody tr:eq(0) td:eq(0)');
	
	// Get group names and description and append to group column
	var groupNames = $.cookie('srv_zvms').split(',');
	var radio, zvmBlock, args, zvm, hcp;
	for (var i in groupNames) {
		args = groupNames[i].split(':');
		zvm = args[0];
		hcp = args[1];
		
		// Create block for each group
		zvmBlock = $('<div class="ui-state-default"></div>').css({
			'border': '1px solid',
			'max-width': '200px',
			'margin': '5px auto',
			'padding': '5px',
			'display': 'inline-block', 
			'vertical-align': 'middle',
			'cursor': 'pointer'
		}).click(function(){
			$(this).children('input:radio').attr('checked', 'checked');
			$(this).parents('td').find('div').attr('class', 'ui-state-default');
			$(this).attr('class', 'ui-state-active');
		});
		radio = $('<input type="radio" name="hcp" value="' + hcp + '"/>').css('display', 'none');
		zvmBlock.append(radio, $('<span><b>Name: </b>' + zvm + '</span>'), $('<span><b>zHCP: </b>' + hcp + '</span>'));
		zvmBlock.children('span').css({
			'display': 'block',
			'margin': '5px'
		});
		zvmCol.append(zvmBlock);
	}
}

/**
 * Load groups into column
 */
function loadGroups() {
	var groupCol = $('#select-table tbody tr:eq(0) td:eq(1)');
	
	// Get group names and description and append to group column
	var groupNames = $.cookie('srv_groups').split(',');
	var groupBlock, radio, args, name, ip, hostname, desc;
	for (var i in groupNames) {
		args = groupNames[i].split(':');
		name = args[0];
		ip = args[1];
		hostname = args[2];
		desc = args[3];
		
		// Create block for each group
		groupBlock = $('<div class="ui-state-default"></div>').css({
			'border': '1px solid',
			'max-width': '200px',
			'margin': '5px auto',
			'padding': '5px',
			'display': 'inline-block', 
			'vertical-align': 'middle',
			'cursor': 'pointer'
		}).click(function(){
			$(this).children('input:radio').attr('checked', 'checked');
			$(this).parents('td').find('div').attr('class', 'ui-state-default');
			$(this).attr('class', 'ui-state-active');
		});
		radio = $('<input type="radio" name="group" value="' + name + '"/>').css('display', 'none');
		groupBlock.append(radio, $('<span><b>Name: </b>' + name + '</span>'), $('<span><b>Description: </b>' + desc + '</span>'));
		groupBlock.children('span').css({
			'display': 'block',
			'margin': '5px'
		});
		groupCol.append(groupBlock);
	}
}

/**
 * Load OS images into column
 */
function loadOSImages() {
	var imgCol = $('#select-table tbody tr:eq(0) td:eq(2)');
	
	// Get group names and description and append to group column
	var imgNames = $.cookie('srv_imagenames').split(',');
	var imgBlock, radio, args, name, desc;
	for (var i in imgNames) {
		args = imgNames[i].split(':');
		name = args[0];
		desc = args[1];
		
		// Create block for each image
		imgBlock = $('<div class="ui-state-default"></div>').css({
			'border': '1px solid',
			'max-width': '200px',
			'margin': '5px auto',
			'padding': '5px',
			'display': 'inline-block', 
			'vertical-align': 'middle',
			'cursor': 'pointer'
		}).click(function(){
			$(this).children('input:radio').attr('checked', 'checked');
			$(this).parents('td').find('div').attr('class', 'ui-state-default');
			$(this).attr('class', 'ui-state-active');
		});
		radio = $('<input type="radio" name="image" value="' + name + '"/>').css('display', 'none');
		imgBlock.append(radio, $('<span><b>Name: </b>' + name + '</span>'), $('<span><b>Description: </b>' + desc + '</span>'));
		imgBlock.children('span').css({
			'display': 'block',
			'margin': '5px'
		});
		imgCol.append(imgBlock);
	}
}

/**
 * Set a cookie for zVM host names
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function setzVMCookies(data) {
	if (data.rsp) {
		var zvms = new Array();
		for ( var i = 0; i < data.rsp.length; i++) {
			zvms.push(data.rsp[i]);
		}
		
		// Set cookie to expire in 60 minutes
		var exDate = new Date();
		exDate.setTime(exDate.getTime() + (240 * 60 * 1000));
		$.cookie('srv_zvms', zvms, { expires: exDate });
	}
}

/**
 * Set a cookie for disk pool names
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function setGroupCookies(data) {
	if (data.rsp) {
		var groups = new Array();
		
		// Index 0 is the table header
		var cols, name, ip, hostname, desc;
		for ( var i = 1; i < data.rsp.length; i++) {
			// Split into columns:
			// node, ip, hostnames, otherinterfaces, comments, disable
			cols = data.rsp[i].split(',');
			name = cols[0].replace(new RegExp('"', 'g'), '');
			ip = cols[1].replace(new RegExp('"', 'g'), '');
			hostname = cols[2].replace(new RegExp('"', 'g'), '');
			desc = cols[4].replace(new RegExp('"', 'g'), '');
			groups.push(name + ':' + ip + ':' + hostname + ':' + desc);
		}
		
		// Set cookie to expire in 60 minutes
		var exDate = new Date();
		exDate.setTime(exDate.getTime() + (240 * 60 * 1000));
		$.cookie('srv_groups', groups, { expires: exDate });
	}
}

/**
 * Set a cookie for the OS images
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function setOSImageCookies(data) {
	// Get response
	var rsp = data.rsp;

	var imageNames = new Array;
	var profilesHash = new Object();
	var osVersHash = new Object();
	var osArchsHash = new Object();
	var imagePos = 0;
	var profilePos = 0;
	var osversPos = 0;
	var osarchPos = 0;
	var provMethodPos = 0;
	var comments = 0;
	// Get the column value
	var colNameArray = rsp[0].substr(1).split(',');
	for (var i in colNameArray){
		switch (colNameArray[i]){
			case 'imagename': {
				imagePos = i;
			}
			break;
			
			case 'profile':{
				profilePos = i;
			}
			break;
			
			case 'osvers':{
				osversPos = i;
			}
			break;
			
			case 'osarch':{
				osarchPos = i;
			}
			break;
			
			case 'comments':{
				comments = i;
			}
			break;
			
			case 'provmethod':{
				provMethodPos = i;
			}			
			break;
			
			default :
			break;
		}
	}
	
	// Go through each index
	for (var i = 1; i < rsp.length; i++) {
		// Get image name
		var cols = rsp[i].split(',');
		var osImage = cols[imagePos].replace(new RegExp('"', 'g'), '');
		var profile = cols[profilePos].replace(new RegExp('"', 'g'), '');
		var provMethod = cols[provMethodPos].replace(new RegExp('"', 'g'), '');
		var osVer = cols[osversPos].replace(new RegExp('"', 'g'), '');
		var osArch = cols[osarchPos].replace(new RegExp('"', 'g'), '');
		var osComments = cols[comments].replace(new RegExp('"', 'g'), '');
		
		// Only save compute profile and install boot
		if (profile.indexOf('compute') > -1 && provMethod.indexOf('install') > -1) {
			if (!osComments)
				osComments = 'No descritption';
			imageNames.push(osImage + ':' + osComments);
			profilesHash[profile] = 1;
			osVersHash[osVer] = 1;
			osArchsHash[osArch] = 1;
		}
		
		
	}

	// Save image names in a cookie
	$.cookie('srv_imagenames', imageNames);

	// Save profiles in a cookie
	var tmp = new Array;
	for (var key in profilesHash) {
		tmp.push(key);
	}
	$.cookie('srv_profiles', tmp);

	// Save OS versions in a cookie
	tmp = new Array;
	for (var key in osVersHash) {
		tmp.push(key);
	}
	$.cookie('srv_osvers', tmp);

	// Save OS architectures in a cookie
	tmp = new Array;
	for (var key in osArchsHash) {
		tmp.push(key);
	}
	$.cookie('srv_osarchs', tmp);
}

/**
 * Set a cookie for disk pool names of a given node
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function setDiskPoolCookies(data) {
	if (data.rsp) {
		var node = data.msg;
		var pools = data.rsp[0].split(node + ': ');
		for (var i in pools) {
			pools[i] = jQuery.trim(pools[i]);
		}
		
		// Set cookie to expire in 60 minutes
		var exDate = new Date();
		exDate.setTime(exDate.getTime() + (240 * 60 * 1000));
		$.cookie(node + 'diskpools', pools, { expires: exDate });
	}
}

/**
 * Set a cookie for user nodes
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function setUserNodes(data) {
	if (data.rsp) {
		// Get user name that is logged in
		var userName = $.cookie('srv_usrname');
		var usrNodes = new Array();
		
		// Ignore first columns because it is the header
		for ( var i = 1; i < data.rsp.length; i++) {
			// Go through each column
			// where column names are: node, os, arch, profile, provmethod, supportedarchs, nodetype, comments, disable
			var cols = data.rsp[i].split(',');
			var node = cols[0].replace(new RegExp('"', 'g'), '');
			var owner = cols[7].replace(new RegExp('"', 'g'), '');
			owner = owner.replace('owner:', '');
			
			if (owner == userName) {
				usrNodes.push(node);
			}
		} // End of for
		
		// Set cookie to expire in 240 minutes
		var exDate = new Date();
		exDate.setTime(exDate.getTime() + (240 * 60 * 1000));
		$.cookie(userName + '_usrnodes', usrNodes, { expires: exDate });
	} // End of if
}

/**
 * Power on a given node
 * 
 * @param node
 *            Node to power on or off
 * @param power2
 *            Power node to given state
 * @return Nothing
 */
function powerNode(node, power2) {
	$.ajax({
		url : 'lib/srv_cmd.php',
		dataType : 'json',
		data : {
			cmd : 'rpower',
			tgt : node,
			args : power2,
			msg : node
		},

		success : updatePowerStatus
	});
}

/**
 * Update power status of a node in the datatable
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function updatePowerStatus(data) {
	// Get datatable
	var nodesDTId = 'userNodesDT';
	var dTable = $('#' + nodesDTId).dataTable();

	// Get xCAT response
	var rsp = data.rsp;
	// Loop through each line
	var node, status, rowPos, strPos;
	for (var i in rsp) {
		// Get node name
		node = rsp[i].split(":")[0];

		// If there is no error
		if (rsp[i].indexOf("Error") < 0 || rsp[i].indexOf("Failed") < 0) {
			// Get the row containing the node link
			rowPos = findRow(node, '#' + nodesDTId, 1);

			// If it was power on, then the data return would contain "Starting"
			strPos = rsp[i].indexOf("Starting");
			if (strPos > -1) {
				status = 'on';
			} else {
				status = 'off';
			}

			// Update the power status column
			dTable.fnUpdate(status, rowPos, 3, false);
		} else {
			// Power on/off failed
			alert(rsp[i]);
		}
	}
}

/**
 * Turn on monitoring for a given node
 * 
 * @param node
 *            Node to monitor on or off
 * @param monitor
 *            Monitor state, on or off
 * @return Nothing
 */
function monitorNode(node, monitor) {
	if (monitor == 'on') {
		// Append loader to warning bar
		var gangliaLoader = createLoader('');
		var warningBar = $('#nodesTab').find('.ui-state-error p');
		if (warningBar.length) {
			warningBar.append(gangliaLoader);
		}

		if (node) {
			// Check if ganglia RPMs are installed
			$.ajax( {
				url : 'lib/srv_cmd.php',
				dataType : 'json',
				data : {
					cmd : 'webrun',
					tgt : '',
					args : 'gangliacheck;' + node,
					msg : node	// Node range will be passed along in data.msg
				},

				/**
				 * Start ganglia on a given node range
				 * 
				 * @param data
				 *            Data returned from HTTP request
				 * @return Nothing
				 */
				success : function(data) {
					// Get response
					var out = data.rsp[0].split(/\n/);

					// Go through each line
					var warn = false;
					var warningMsg = '';
					for (var i in out) {
						// If an RPM is not installed
						if (out[i].indexOf('not installed') > -1) {
							warn = true;
							
							if (warningMsg) {
								warningMsg += '<br>' + out[i];
							} else {
								warningMsg = out[i];
							}
						}
					}
					
					// If there are warnings
					if (warn) {
						// Create warning bar
						var warningBar = createWarnBar(warningMsg);
						warningBar.css('margin-bottom', '10px');
						warningBar.prependTo($('#nodesTab'));
					} else {
						$.ajax( {
							url : 'lib/srv_cmd.php',
							dataType : 'json',
							data : {
								cmd : 'webrun',
								tgt : '',
								args : 'gangliastart;' + data.msg,
								msg : data.msg
							},

							success : function(data) {
								// Remove any warnings
								$('#nodesTab').find('.ui-state-error').remove();
								refreshGangliaStatus(data.msg);
							}
						});
					} // End of if (warn)
				} // End of function(data)
			});
		}
	} else {
		var args;
		if (node) {
			args = 'gangliastop;' + node;
			$.ajax( {
				url : 'lib/srv_cmd.php',
				dataType : 'json',
				data : {
					cmd : 'webrun',
					tgt : '',
					args : args,
					msg : node
				},

				success : function(data) {
					refreshGangliaStatus(data.msg);
				}
			});
		}
	}
}

/**
 * Open a dialog to delete node
 * 
 * @param tgtNodes
 *            Nodes to delete
 * @return Nothing
 */
function deleteNode(tgtNodes) {
	var nodes = tgtNodes.split(',');
		
	// Loop through each node and create target nodes string
	var tgtNodesStr = '';
	for (var i in nodes) {		
		if (i == 0 && i == nodes.length - 1) {
			// If it is the 1st and only node
			tgtNodesStr += nodes[i];
		} else if (i == 0 && i != nodes.length - 1) {
			// If it is the 1st node of many nodes, append a comma to the string
			tgtNodesStr += nodes[i] + ', ';
		} else {
			if (i == nodes.length - 1) {
				// If it is the last node, append nothing to the string
				tgtNodesStr += nodes[i];
			} else {
				// Append a comma to the string
				tgtNodesStr += nodes[i] + ', ';
			}
		}
	}
	
	// Confirm delete
	var confirmMsg = $('<p>Are you sure you want to delete ' + tgtNodesStr + '?</p>').css({
		'display': 'inline',
		'margin': '5px',
		'vertical-align': 'middle',
		'word-wrap': 'break-word'
	});
	
	var style = {
		'display': 'inline-block',
		'margin': '5px',
		'vertical-align': 'middle'
	};

	var dialog = $('<div></div>');
	var icon = $('<span class="ui-icon ui-icon-alert"></span>').css(style);
	dialog.append(icon);
	dialog.append(confirmMsg);
		
	// Open dialog
	dialog.dialog({
		title: "Confirm",
		modal: true,
		width: 400,
		buttons: {
			"Yes": function(){ 
				// Create status bar and append to tab
				var instance = 0;
				var statBarId = 'deleteStat' + instance;
				while ($('#' + statBarId).length) {
					// If one already exists, generate another one
					instance = instance + 1;
					statBarId = 'deleteStat' + instance;
				}
				
				var statBar = createStatusBar(statBarId);
				var loader = createLoader('');
				statBar.find('div').append(loader);
				statBar.prependTo($('#manageTab'));
				
				// Delete the virtual server
				$.ajax( {
					url : 'lib/srv_cmd.php',
					dataType : 'json',
					data : {
						cmd : 'rmvm',
						tgt : tgtNodes,
						args : '',
						msg : 'out=' + statBarId + ';cmd=rmvm;tgt=' + tgtNodes
					},

					success : function(data) {
						var args = data.msg.split(';');
						var statBarId = args[0].replace('out=', '');
						var tgts = args[2].replace('tgt=', '').split(',');
						
						// Get data table
						var nodesDTId = 'userNodesDT';
						var dTable = $('#' + nodesDTId).dataTable();
						var failed = false;

						// Create an info box to show output
						var output = writeRsp(data.rsp, '');
						output.css('margin', '0px');
						// Remove loader and append output
						$('#' + statBarId + ' img').remove();
						$('#' + statBarId + ' div').append(output);
						
						// If there was an error, do not continue
						if (output.html().indexOf('Error') > -1) {
							failed = true;
						}

						// Update data table
						var rowPos;						
						for (var i in tgts) {
							if (!failed) {
								// Get row containing the node link and delete it
								rowPos = findRow(tgts[i], '#' + nodesDTId, 1);
								dTable.fnDeleteRow(rowPos);
							}
						}
						
						// Refresh nodes owned by user
						$.ajax( {
							url : 'lib/srv_cmd.php',
							dataType : 'json',
							data : {
								cmd : 'tabdump',
								tgt : '',
								args : 'nodetype',
								msg : ''
							},

							success : function(data) {
								setUserNodes(data);
							}
						});
					}
				});
				
				$(this).dialog("close");
			},
			"No": function() {
				$(this).dialog("close");
			}
		}
	});
}

/**
 * Unlock a node by setting the ssh keys
 * 
 * @param tgtNodes
 *            Nodes to unlock
 * @return Nothing
 */
function unlockNode(tgtNodes) {
	var nodes = tgtNodes.split(',');
	
	// Loop through each node and create target nodes string
	var tgtNodesStr = '';
	for (var i in nodes) {		
		if (i == 0 && i == nodes.length - 1) {
			// If it is the 1st and only node
			tgtNodesStr += nodes[i];
		} else if (i == 0 && i != nodes.length - 1) {
			// If it is the 1st node of many nodes, append a comma to the string
			tgtNodesStr += nodes[i] + ', ';
		} else {
			if (i == nodes.length - 1) {
				// If it is the last node, append nothing to the string
				tgtNodesStr += nodes[i];
			} else {
				// Append a comma to the string
				tgtNodesStr += nodes[i] + ', ';
			}
		}
	}

	var dialog = $('<div></div>');
	var infoBar = createInfoBar('Give the root password for this node range to setup its SSH keys.');
	dialog.append(infoBar);
	
	var unlockForm = $('<div class="form"></div>').css('margin', '5px');
	unlockForm.append('<div><label>Target node range:</label><input type="text" id="node" name="node" readonly="readonly" value="' + tgtNodes + '" title="The node or node range to unlock"/></div>');
	unlockForm.append('<div><label>Password:</label><input type="password" id="password" name="password" title="The root password to unlock this node"/></div>');
	dialog.append(unlockForm);
	
	dialog.find('div input').css('margin', '5px');
	
	// Generate tooltips
	unlockForm.find('div input[title]').tooltip({
		position: "center right",
		offset: [-2, 10],
		effect: "fade",
		opacity: 0.7,
		predelay: 800,
		events : {
			def : "mouseover,mouseout",
			input : "mouseover,mouseout",
			widget : "focus mouseover,blur mouseout",
			tooltip : "mouseover,mouseout"
		}
	});
		
	// Open dialog
	dialog.dialog({
		title: "Confirm",
		modal: true,
		width: 450,
		buttons: {
			"Ok": function(){
				// Create status bar and append to tab
				var instance = 0;
				var statBarId = 'unlockStat' + instance;
				while ($('#' + statBarId).length) {
					// If one already exists, generate another one
					instance = instance + 1;
					statBarId = 'unlockStat' + instance;
				}
				
				var statBar = createStatusBar(statBarId);
				var loader = createLoader('');
				statBar.find('div').append(loader);
				statBar.prependTo($('#manageTab'));
								
				// If a password is given
				var password = unlockForm.find('input[name=password]:eq(0)');
				if (password.val()) {
					// Setup SSH keys
		    		$.ajax( {
		    			url : 'lib/srv_cmd.php',
		    			dataType : 'json',
		    			data : {
		    				cmd : 'webrun',
		    				tgt : '',
		    				args : 'unlock;' + tgtNodes + ';' + password.val(),
		    				msg : 'out=' + statBarId + ';cmd=unlock;tgt=' + tgtNodes
		    			},
		    
		    			success : function(data) {
							// Create an info box to show output
							var output = writeRsp(data.rsp, '');
							output.css('margin', '0px');
							// Remove loader and append output
							$('#' + statBarId + ' img').remove();
							$('#' + statBarId + ' div').append(output);
		    			}
		    		});
		    		
		    		$(this).dialog("close");
				}			
			},
			"Cancel": function() {
				$(this).dialog("close");
			}
		}
	});
}

/**
 * Get nodes current load information
 */
function getNodesCurrentLoad(){
	var userName = $.cookie('srv_usrname');
	var nodes = $.cookie(userName + '_usrnodes');
	
    // Get nodes current status
    $.ajax({
    	url : 'lib/srv_cmd.php',
        dataType : 'json',
        data : {
        	cmd : 'webrun',
            tgt : '',
            args : 'gangliacurrent;node;' + nodes,
            msg : ''
        },
        
        success: saveNodeLoad
    });
}

/**
 * Save node load data
 * 
 * @param status
 * 			Data returned from HTTP request
 */
function saveNodeLoad(status){
	// Save node path and status for future use
	nodePath = new Object();
	nodeStatus = new Object();
	
	// Get nodes status
    var nodes = status.rsp[0].split(';');
    
    var i = 0, pos = 0;
    var node = '', tmpStr = '';
    var tmpArry;   
    
    for (i = 0; i < nodes.length; i++){
        tmpStr = nodes[i];
        pos = tmpStr.indexOf(':');
        node = tmpStr.substring(0, pos);
        tmpArry = tmpStr.substring(pos + 1).split(',');
        
        switch(tmpArry[0]){
            case 'UNKNOWN':{
                nodeStatus[node] = -2;
            }
            break;
            case 'ERROR':{
                nodeStatus[node] = -1;
            }
            break;
            case 'WARNING':{
                nodeStatus[node] = 0;
                nodePath[node] = tmpArry[1];
            }
            break;
            case 'NORMAL':{
                nodeStatus[node] = 1;
                nodePath[node] = tmpArry[1];
            }
            break;
        }
    }
}

/**
 * Get monitoring metrics and load into inventory fieldset
 * 
 * @param node
 * 			Node to collect metrics
 * @return Nothing
 */
function getMonitorMetrics(node) {
	$('#' + node + '_monitor').children().remove();
	
	// Get monitoring metrics
	$.ajax({
        url : 'lib/srv_cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'gangliashow;' + nodePath[node] + ';hour;_summary_',
            msg : node
        },
        
        success: drawMonitoringCharts
    });
}

/**
 * Draw monitoring charts based on node metrics
 * 
 * @param data
 * 			Data returned from HTTP request
 * @return Nothing
 */
function drawMonitoringCharts(data){
	var nodeMetrics = new Object();
	var metricData = data.rsp[0].split(';');
	var node = data.msg;
		
    var metricName = '';
    var metricVal = '';
    var pos = 0;
    
    // Go through the metrics returned
    for (var m = 0; m < metricData.length; m++){
        pos = metricData[m].indexOf(':');

        // Get metric name
        metricName = metricData[m].substr(0, pos);
        nodeMetrics[metricName] = new Array();
        // Get metric values
        metricVal = metricData[m].substr(pos + 1).split(',');
        // Save node metrics
        for (var i = 0; i < metricVal.length; i++){
            nodeMetrics[metricName].push(Number(metricVal[i]));
        }
    }
    
    drawLoadFlot(node, nodeMetrics['load_one'], nodeMetrics['cpu_num']);
    drawCpuFlot(node, nodeMetrics['cpu_idle']);
    drawMemFlot(node, nodeMetrics['mem_free'], nodeMetrics['mem_total']);
    drawDiskFlot(node, nodeMetrics['disk_free'], nodeMetrics['disk_total']);
    drawNetworkFlot(node, nodeMetrics['bytes_in'], nodeMetrics['bytes_out']);
}

/**
 * Draw load metrics flot
 * 
 * @param node
 * 			Node name
 * @param loadpair
 * 			Load timestamp and value pair
 * @param cpupair
 * 			CPU number and value pair
 * @return Nothing
 */
function drawLoadFlot(node, loadPair, cpuPair){
    var load = new Array();
    var cpu = new Array();
    
    var i = 0;
    var yAxisMax = 0;
    var interval = 1;
    
    // Append flot to node monitoring fieldset
    var loadFlot = $('<div id="' + node + '_load"></div>').css({
    	'float': 'left',
	    'height': '150px',
	    'margin': '0 0 10px',
	    'width': '300px'
    });
    $('#' + node + '_monitor').append(loadFlot);
    $('#' + node + '_load').empty();
    
    // Parse load pair where:
    // timestamp must be mutiplied by 1000 and Javascript timestamp is in ms
    for (i = 0; i < loadPair.length; i += 2){
        load.push([loadPair[i] * 1000, loadPair[i + 1]]);
        if (loadPair[i + 1] > yAxisMax){
            yAxisMax = loadPair[i + 1];
        }
    }
    
    // Parse CPU pair
    for (i = 0; i < cpuPair.length; i += 2){
        cpu.push([cpuPair[i] * 1000, cpuPair[i + 1]]);
        if (cpuPair[i + 1] > yAxisMax){
            yAxisMax = cpuPair[i + 1];
        }
    }
    
    interval = parseInt(yAxisMax / 3);
    if (interval < 1){
        interval = 1;
    }
    
    $.jqplot(node + '_load', [load, cpu],{
        title: ' Loads/Procs Last Hour',
        axes:{
            xaxis:{
                renderer : $.jqplot.DateAxisRenderer,
                numberTicks: 4,
                tickOptions : {
                    formatString : '%R',
                    show : true
                }
            },
            yaxis: {
                min : 0,
                tickInterval : interval
            }
        },
        legend : {
            show: true,
            location: 'nw'
        },
        series:[{label:'Load'}, {label: 'CPU Number'}],
        seriesDefaults : {showMarker: false}
    });
}

/**
 * Draw CPU usage flot
 * 
 * @param node
 * 			Node name
 * @param cpuPair 
 * 			CPU timestamp and value pair
 * @return Nothing
 */
function drawCpuFlot(node, cpuPair){
    var cpu = new Array();
    
	// Append flot to node monitoring fieldset
    var cpuFlot = $('<div id="' + node + '_cpu"></div>').css({
    	'float': 'left',
	    'height': '150px',
	    'margin': '0 0 10px',
	    'width': '300px'
    });
    $('#' + node + '_monitor').append(cpuFlot);
    $('#' + node + '_cpu').empty();
    
    // Time stamp should by mutiplied by 1000
    // CPU idle comes from server, subtract 1 from idle
    for(var i = 0; i < cpuPair.length; i +=2){
        cpu.push([(cpuPair[i] * 1000), (100 - cpuPair[i + 1])]);
    }
    
    $.jqplot(node + '_cpu', [cpu],{
        title: 'CPU Use Last Hour',
        axes:{
            xaxis:{
                renderer : $.jqplot.DateAxisRenderer,
                numberTicks: 4,
                tickOptions : {
                    formatString : '%R',
                    show : true
                }
            },
            yaxis: {
                min : 0,
                max : 100,
                tickOptions:{formatString : '%d\%'}
            }
        },
        seriesDefaults : {showMarker: false}
    });
}

/**
 * Draw memory usage flot
 * 
 * @param node
 * 			Node name
 * @param freePair 
 * 			Free memory timestamp and value pair
 * @param totalPair 
 * 			Total memory timestamp and value pair
 * @return Nothing
 */
function drawMemFlot(node, freePair, totalPair){
    var used = new Array();
    var total = new Array();
    var size = 0;
    
	// Append flot to node monitoring fieldset
    var memoryFlot = $('<div id="' + node + '_memory"></div>').css({
    	'float': 'left',
	    'height': '150px',
	    'margin': '0 0 10px',
	    'width': '300px'
    });
    $('#' + node + '_monitor').append(memoryFlot);
    $('#' + node + '_memory').empty();
    
    if(freePair.length < totalPair.length){
        size = freePair.length;
    } else {
        size = freePair.length;
    }
    
    var tmpTotal, tmpUsed;
    for(var i = 0; i < size; i+=2){
        tmpTotal = totalPair[i+1];
        tmpUsed = tmpTotal-freePair[i+1];
        tmpTotal = tmpTotal/1000000;
        tmpUsed = tmpUsed/1000000;
        total.push([totalPair[i]*1000, tmpTotal]);
        used.push([freePair[i]*1000, tmpUsed]);
    }
    
    $.jqplot(node + '_memory', [used, total],{
        title: 'Memory Use Last Hour',
        axes:{
            xaxis:{
                renderer : $.jqplot.DateAxisRenderer,
                numberTicks: 4,
                tickOptions : {
                    formatString : '%R',
                    show : true
                }
            },
            yaxis: {
                min : 0,
                tickOptions:{formatString : '%.2fG'}
            }
        },
        legend : {
            show: true,
            location: 'nw'
        },
        series:[{label:'Used'}, {label: 'Total'}],
        seriesDefaults : {showMarker: false}
    });
}

/**
 * Draw disk usage flot
 * 
 * @param node
 * 			Node name
 * @param freePair 
 * 			Free disk space (Ganglia only logs free data)
 * @param totalPair 
 * 			Total disk space
 * @return Nothing
 */
function drawDiskFlot(node, freePair, totalPair) {
	var used = new Array();
	var total = new Array();
	var size = 0;

	// Append flot to node monitoring fieldset
	var diskFlot = $('<div id="' + node + '_disk"></div>').css({
		'float' : 'left',
		'height' : '150px',
		'margin' : '0 0 10px',
		'width' : '300px'
	});
	$('#' + node + '_monitor').append(diskFlot);
	$('#' + node + '_disk').empty();

	if (freePair.length < totalPair.length) {
		size = freePair.length;
	} else {
		size = freePair.length;
	}

	var tmpTotal, tmpUsed;
	for ( var i = 0; i < size; i += 2) {
		tmpTotal = totalPair[i + 1];
		tmpUsed = tmpTotal - freePair[i + 1];
		total.push([ totalPair[i] * 1000, tmpTotal ]);
		used.push([ freePair[i] * 1000, tmpUsed ]);
	}

	$.jqplot(node + '_disk', [ used, total ], {
		title : 'Disk Use Last Hour',
		axes : {
			xaxis : {
				renderer : $.jqplot.DateAxisRenderer,
				numberTicks : 4,
				tickOptions : {
					formatString : '%R',
					show : true
				}
			},
			yaxis : {
				min : 0,
				tickOptions : {
					formatString : '%.2fG'
				}
			}
		},
		legend : {
			show : true,
			location : 'nw'
		},
		series : [ {
			label : 'Used'
		}, {
			label : 'Total'
		} ],
		seriesDefaults : {
			showMarker : false
		}
	});
}

/**
 * Draw network usage flot
 * 
 * @param node
 *            Node name
 * @param freePair
 *            Free memory timestamp and value pair
 * @param totalPair
 *            Total memory timestamp and value pair
 * @return Nothing
 */
function drawNetworkFlot(node, inPair, outPair) {
	var inArray = new Array();
	var outArray = new Array();
	var maxVal = 0;
	var unitName = 'B';
	var divisor = 1;

	// Append flot to node monitoring fieldset
	var diskFlot = $('<div id="' + node + '_network"></div>').css({
		'float' : 'left',
		'height' : '150px',
		'margin' : '0 0 10px',
		'width' : '300px'
	});
	$('#' + node + '_monitor').append(diskFlot);
	$('#' + node + '_network').empty();
	
	for (var i = 0; i < inPair.length; i += 2) {
		if (inPair[i + 1] > maxVal) {
			maxVal = inPair[i + 1];
		}
	}

	for (var i = 0; i < outPair.length; i += 2) {
		if (outPair[i + 1] > maxVal) {
			maxVal = outPair[i + 1];
		}
	}

	if (maxVal > 3000000) {
		divisor = 1000000;
		unitName = 'GB';
	} else if (maxVal >= 3000) {
		divisor = 1000;
		unitName = 'MB';
	} else {
		// Do nothing
	}

	for (i = 0; i < inPair.length; i += 2) {
		inArray.push([ (inPair[i] * 1000), (inPair[i + 1] / divisor) ]);
	}

	for (i = 0; i < outPair.length; i += 2) {
		outArray.push([ (outPair[i] * 1000), (outPair[i + 1] / divisor) ]);
	}

	$.jqplot(node + '_network', [ inArray, outArray ], {
		title : 'Network Last Hour',
		axes : {
			xaxis : {
				renderer : $.jqplot.DateAxisRenderer,
				numberTicks : 4,
				tickOptions : {
					formatString : '%R',
					show : true
				}
			},
			yaxis : {
				min : 0,
				tickOptions : {
					formatString : '%d' + unitName
				}
			}
		},
		legend : {
			show : true,
			location : 'nw'
		},
		series : [ {
			label : 'In'
		}, {
			label : 'Out'
		} ],
		seriesDefaults : {
			showMarker : false
		}
	});
}