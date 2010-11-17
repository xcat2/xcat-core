/**
 * Global variables
 */
var nodesTabs; 		// Node tabs
var origAttrs = new Object();	// Original node attributes

/**
 * Set the nodes tab
 * 
 * @param obj
 *            Tab object
 * @return Nothing
 */
function setNodesTab(obj) {
	nodesTabs = obj;
}

/**
 * Get the nodes tab
 * 
 * @param Nothing
 * @return Tab object
 */
function getNodesTab() {
	return nodesTabs;
}

/**
 * Load nodes page
 * 
 * @return Nothing
 */
function loadNodesPage() {
	// If groups are not already loaded
	if (!$('#groups').length) {
		// Create a groups division
		groupDIV = $('<div id="groups"></div>');
		nodesDIV = $('<div id="nodes"></div>');
		$('#content').append(groupDIV);
		$('#content').append(nodesDIV);

		// Create loader
		var loader = createLoader();
		groupDIV.append(loader);
		
		// Create info bar
		var info = createInfoBar('Select a group to view its nodes');
		$('#nodes').append(info);

		// Get groups
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'extnoderange',
				tgt : '/.*',
				args : 'subgroups',
				msg : ''
			},

			success : loadGroups
		});
		
		// Get graphical view info
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'nodels',
				tgt : 'all',
				args : 'nodetype.nodetype;ppc.parent;vpd.mtm;nodelist.status;nodehm.mgt',
				msg : ''
			},

			success : extractGraphicalData
		});
	}
}

/**
 * Load groups
 * 
 * @param data
 *            Data returned from HTTP request
 * @return
 */
function loadGroups(data) {
	// Remove loader
	$('#groups').find('img').remove();
	
	var groups = data.rsp;
	setGroupsCookies(data);

	// Create a list of groups
	var ul = $('<ul></ul>');
	var item = $('<li id="root"><h3>Groups</h3></li>');
	ul.append(item);
	var subUL = $('<ul></ul>');
	item.append(subUL);

	// Create a link for each group
	for ( var i = groups.length; i--;) {
		var subItem = $('<li id="' + groups[i] + '"></li>');
		var link = $('<a>' + groups[i] + '</a>');
		subItem.append(link);
		subUL.append(subItem);
	}

	// Turn groups list into a tree
	$('#groups').append(ul);
	$('#groups').jstree( {
		core : { "initially_open" : [ "root" ] },
		themes : {
			"theme" : "default",
			"dots" : false,	// No dots
			"icons" : false	// No icons
		}
	});
	
	// Load nodes onclick
	$('#groups').bind('select_node.jstree', function(event, data) {
		var thisGroup = jQuery.trim(data.rslt.obj.text());
		if (thisGroup) {
			// Clear nodes division
			$('#nodes').children().remove();
			
			// Create loader
			var loader = $('<center></center>').append(createLoader());
			var loader2 = $('<center></center>').append(createLoader());
			
			// Create a tab for this group
			var tab = new Tab();
			setNodesTab(tab);
			tab.init();
			$('#nodes').append(tab.object());
			tab.add('nodesTab', 'Nodes', loader, false);
			tab.add('graphTab', 'Graphical', loader2, false);

			// Get nodes within selected group
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'lsdef',
					tgt : '',
					args : thisGroup,
					msg : thisGroup
				},

				success : loadNodes
			});
			
			// Get subgroups within selected group
			// only when this is the parent group and not a subgroup
			if (data.rslt.obj.attr('id').indexOf('Subgroup') < 0) {
    			$.ajax( {
    				url : 'lib/cmd.php',
    				dataType : 'json',
    				data : {
    					cmd : 'extnoderange',
    					tgt : thisGroup,
    					args : 'subgroups',
    					msg : thisGroup
    				},
    
    				success : loadSubgroups
    			});
			}
			
			// Get physical layout
			$.ajax({
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'lsdef',
					tgt : '',
					args : thisGroup + ';-s',
					msg : ''
				},
				
				success : createPhysicalLayout
			});
		} // End of if (thisGroup)
	});
	
	// Create link to add nodes
	var addNodeLink = $('<a title="Add a node or a node range to xCAT">Add node</a>');
	addNodeLink.bind('click', function(event) {
		var info = createInfoBar('Select the hardware management for the new node range');
		var addNodeForm = $('<div class="form"></div>');
		addNodeForm.append(info);
		addNodeForm.append('<div><label for="mgt">Hardware management:</label>'
    			+ '<select id="mgt" name="mgt">'
    			+ '<option>ipmi</option>' 
    			+ '<option>blade</option>'
    			+ '<option>hmc</option>' 
    			+ '<option>ivm</option>'
    			+ '<option>fsp</option>'
    			+ '<option>zvm</option>'
    		+ '</select>'
    	+ '</div>' );
					
		// Open dialog to add node
		addNodeForm.dialog({
			modal: true,
			width: 400,
			buttons: {
        		"Ok": function(){
					// Get hardware management
					var mgt = $(this).find('select[name=mgt]').val();					
					
					var plugin;
					switch(mgt) {
			    		case "blade":
			        		plugin = new bladePlugin();
			        		break;
			    		case "fsp":
			    			plugin = new fspPlugin();
			    			break;
			    		case "hmc":
			    			plugin = new hmcPlugin();
			    			break;
			    		case "ipmi":
			    			plugin = new ipmiPlugin();
			    			break;		
			    		case "ivm":
			    			plugin = new ivmPlugin();
			    			break;
			    		case "zvm":
			    			plugin = new zvmPlugin();
			    			break;
			    	}
					
					plugin.addNode();
					$(this).dialog( "close" );
				},
				"Cancel": function(){
        			$(this).dialog( "close" );
        		}
			}
		});

	});
	
	// Generate tooltips
	addNodeLink.tooltip({
		position: "center right",	// Place tooltip on the right edge
		offset: [-2, 10],	// A little tweaking of the position
		effect: "fade",		// Use the built-in fadeIn/fadeOut effect
		opacity: 0.7		// Custom opacity setting
	});
	
	$('#groups').append(addNodeLink);
}

/**
 * Load subgroups belonging to a given group
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function loadSubgroups(data) {
	// Data returned
	var rsp = data.rsp;
	// Group name
	var group = data.msg;
	
	// Go through each subgroup
	for ( var i in rsp) {
		// Do not put the same group in the subgroup
		if (rsp[i] != group && $('#' + group).length) {
			// Add subgroup inside group
			$('#groups').jstree('create', $('#' + group), 'inside', {
				'attr': {'id': rsp[i] + 'Subgroup'},
				'data': rsp[i]}, 
			'', true);
		}
	} // End of for
}

/**
 * Load nodes belonging to a given group
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function loadNodes(data) {
	// Data returned
	var rsp = data.rsp;
	// Group name
	var group = data.msg;
	// Node attributes hash
	var attrs = new Object();
	// Node attributes
	var headers = new Object();
	
	// Clear cookie containing list of nodes where
	// their attributes need to be updated
	$.cookie('Nodes2Update', '');
	// Clear hash table containing node attributes
	origAttrs = '';

	var node;
	var args;
	for ( var i in rsp) {
		// Get the node
		var pos = rsp[i].indexOf('Object name:');
		if (pos > -1) {
			var temp = rsp[i].split(': ');
			node = jQuery.trim(temp[1]);

			// Create a hash for the node attributes
			attrs[node] = new Object();
			i++;
		}

		// Get key and value
		args = rsp[i].split('=');
		var key = jQuery.trim(args[0]);
		var val = jQuery.trim(args[1]);

		// Create a hash table
		attrs[node][key] = val;
		headers[key] = 1;
	}
	
	// Save attributes in hash table
	origAttrs = attrs;

	// Sort headers
	var sorted = new Array();
	for ( var key in headers) {
		// Do not put in comments twice
		if (key != 'usercomment') {
			sorted.push(key);
		}
	}
	sorted.sort();

	// Add column for check box, node, ping, power, and comments
	sorted.unshift('<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">', 
		'node', 
		'<a>ping</a><img src="images/loader.gif"></img>', 
		'<a>power</a><img src="images/loader.gif"></img>',
		'comments');

	// Create a datatable
	var dTable = new DataTable('nodesDataTable');
	dTable.init(sorted);

	// Go through each node
	for ( var node in attrs) {
		// Create a row
		var row = new Array();
		// Create a check box
		var checkBx = '<input type="checkbox" name="' + node + '"/>';
		// Open node onclick
		var nodeLink = $('<a class="node" id="' + node + '">' + node + '</a>').bind('click', loadNode);
		// Left align node link
		nodeLink.css('text-align', 'left');		
		// Push in checkbox, node link, ping, and power
		row.push(checkBx, nodeLink, '', '');

		// Put in comments
		var comment = attrs[node]['usercomment'];
		var iconSrc;
		// If no comments exists, show 'No comments' and set icon image source
		if (!comment) {
			comment = 'No comments';
			iconSrc = 'images/ui-icon-no-comment.png';
		} else {
			iconSrc = 'images/ui-icon-comment.png';
		}
				
		// Create comments icon
		var tipID = node + 'Tip';
		var icon = $('<img id="' + tipID + '" src="' + iconSrc + '"></img>').css({
			'width': '18px',
			'height': '18px'
		});
		
		// Create tooltip
		var tip = createCommentsToolTip(comment);
		// Create container to put icon and comment in
		var col = $('<span></span>').append(icon);
		col.append(tip);
		row.push(col);
		
		// Generate tooltips
		icon.tooltip({
			position: "center right",	// Place tooltip on the right edge
			offset: [-2, 10],			// A little tweaking of the position
			relative: true,
			effect: "fade",				// Use the built-in fadeIn/fadeOut
										// effect
			opacity: 0.8				// Custom opacity setting
		});
		
		// Go through each header
		for ( var i = 5; i < sorted.length; i++) {
			// Add the node attributes to the row
			var key = sorted[i];
			
			// Do not put in comments twice
			if (key != 'usercomment') {
    			var val = attrs[node][key];
    			if (val) {
    				row.push(val);
    			} else {
    				row.push('');
    			}
			} // End of if
		}

		// Add the row to the table
		dTable.add(row);
	}

	// Clear the tab before inserting the table
	$('#nodesTab').children().remove();
	
	// Create info bar for nodes tab
	var info = createInfoBar('Click on a cell to edit.  Click outside the table to write to the cell.  Hit the Escape key to ignore changes. Once you are satisfied with how the table looks, click on Save.');
	$('#nodesTab').append(info);

	// Create action bar
	var actionBar = $('<div class="actionBar"></div>');

	/**
	 * The following actions are available to perform against a given node:
	 * power, clone, delete, unlock, and advanced
	 */

	var powerLnk = $('<a>Power</a>');
	
	// Power on (rpower)
	var powerOnLnk = $('<a>Power on</a>');
	powerOnLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			powerNode(tgtNodes, 'on');
		}
	});
	
	// Power off (rpower)
	var powerOffLnk = $('<a>Power off</a>');
	powerOffLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			powerNode(tgtNodes, 'off');
		}
	});

	// Clone
	var cloneLnk = $('<a>Clone</a>');
	cloneLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable').split(',');
		for ( var i = 0; i < tgtNodes.length; i++) {
			var mgt = getNodeAttr(tgtNodes[i], 'mgt');
			
			// Create an instance of the plugin
			var plugin;
			switch(mgt) {
				case "blade":
		    		plugin = new bladePlugin();
		    		break;
				case "fsp":
					plugin = new fspPlugin();
					break;
				case "hmc":
					plugin = new hmcPlugin();
					break;
				case "ipmi":
					plugin = new ipmiPlugin();
					break;		
				case "ivm":
					plugin = new ivmPlugin();
					break;
				case "zvm":
					plugin = new zvmPlugin();
					break;
			}
			
			plugin.loadClonePage(tgtNodes[i]);
		}
	});

	// Delete (rmvm)
	var deleteLnk = $('<a>Delete</a>');
	deleteLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			deleteNode(tgtNodes);
		}
	});

	// Unlock
	var unlockLnk = $('<a>Unlock</a>');
	unlockLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			loadUnlockPage(tgtNodes);
		}
	});

	// Run script (xdsh)
	var scriptLnk = $('<a>Run script</a>');
	scriptLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			loadScriptPage(tgtNodes);
		}
	});

	// Update (updatenode)
	var updateLnk = $('<a>Update</a>');
	updateLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			loadUpdatenodePage(tgtNodes);
		}
	});

	// Set boot state (nodeset)
	var setBootStateLnk = $('<a>Set boot state</a>');
	setBootStateLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			loadNodesetPage(tgtNodes);
		}

	});

	// Boot to network (rnetboot)
	var boot2NetworkLnk = $('<a>Boot to network</a>');
	boot2NetworkLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			loadNetbootPage(tgtNodes);
		}
	});


	// Remote console (rcons)
	var rcons = $('<a>Open console</a>');
	rcons.bind('click', function(event){
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			loadRconsPage(tgtNodes);
		}
	});

	var advancedLnk = $('<a>Advanced</a>');

	// Power actions
	var powerActions = [ powerOnLnk, powerOffLnk ];
	var powerActionMenu = createMenu(powerActions);

	// Advanced actions
	var advancedActions;
	if ('compute' == group) {
		advancedActions = [ boot2NetworkLnk, scriptLnk, setBootStateLnk, updateLnk, rcons ];
	} else {
		advancedActions = [ boot2NetworkLnk, scriptLnk, setBootStateLnk, updateLnk ];
	}

	var advancedActionMenu = createMenu(advancedActions);

	/**
	 * Create an action menu
	 */
	var actionsDIV = $('<div></div>');
	var actions = [ [ powerLnk, powerActionMenu ], cloneLnk, deleteLnk, unlockLnk, [ advancedLnk, advancedActionMenu ] ];
	var actionMenu = createMenu(actions);
	actionMenu.superfish();
	actionsDIV.append(actionMenu);
	actionBar.append(actionsDIV);
	$('#nodesTab').append(actionBar);
	
	// Insert table
	$('#nodesTab').append(dTable.object());
	
	// Save changes
	var saveLnk = $('<a>Save</a>');
	saveLnk.bind('click', function(event){
		updateNodeAttrs(group);
	});
	
	// Undo changes
	var undoLnk = $('<a>Undo</a>');
	undoLnk.bind('click', function(event){
		restoreNodeAttrs();
	});

	/**
	 * Create menu to save and undo table changes
	 */
	// It will be hidden until a change is made
	var tableActionsMenu = createMenu([saveLnk, undoLnk]).hide();
	tableActionsMenu.css('margin-left', '100px');
	actionsDIV.append(tableActionsMenu);

	// Turn table into a datatable
	var myDataTable = $('#nodesDataTable').dataTable({
		'iDisplayLength': 50
	});
	
	// Do not sort ping, power, and comment column
	var pingCol = $('#nodesDataTable thead tr th').eq(2);
	var powerCol = $('#nodesDataTable thead tr th').eq(3);
	var commentCol = $('#nodesDataTable thead tr th').eq(4);
	pingCol.unbind('click');
	powerCol.unbind('click');
	commentCol.unbind('click');
	
	// Create enough space for loader to be displayed
	$('#nodesDataTable tbody tr td:nth-child(3)').css('min-width', '60px');
	$('#nodesDataTable tbody tr td:nth-child(4)').css('min-width', '60px');
	
	// Instead refresh the ping status and power status
	pingCol.bind('click', function(event) {
		refreshPingStatus(group);
	});
	
	powerCol.bind('click', function(event) {
		refreshPowerStatus(group);
	});
		
	/**
	 * Enable editable columns
	 */
	// Do not make 1st, 2nd, 3rd, 4th, or 5th column editable
	$('#nodesDataTable td:not(td:nth-child(1),td:nth-child(2),td:nth-child(3),td:nth-child(4),td:nth-child(5))').editable(
		function(value, settings) {			
			// Change text color to red
			$(this).css('color', 'red');
			
			// Get column index
			var colPos = this.cellIndex;
						
			// Get row index
			var dTable = $('#nodesDataTable').dataTable();
			var rowPos = dTable.fnGetPosition(this.parentNode);
			
			// Update datatable
			dTable.fnUpdate(value, rowPos, colPos);
			
			// Get node name
			var node = $(this).parent().find('td a.node').text();
			
			// Flag node to update
			flagNode2Update(node);
			
			// Show table menu actions
			tableActionsMenu.show();

			return (value);
		}, {
			onblur : 'submit', 	// Clicking outside editable area submits
								// changes
			type : 'textarea',
			placeholder: ' ',
			height : '30px' 	// The height of the text area
		});
	
	/**
	 * Get power and ping for each node
	 */

	// Get power status
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'rpower',
			tgt : group,
			args : 'stat',
			msg : ''
		},

		success : loadPowerStatus
	});

	// Get ping status
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'pping ' + group,
			msg : ''
		},

		success : loadPingStatus
	});
	
	/**
	 * Additional ajax requests need to be made for zVM
	 */

	// Get index of HCP column
	var i = $.inArray('hcp', sorted);
	if (i) {
		// Get hardware control point
		var rows = dTable.object().find('tbody tr');
		var hcps = new Object();
		for ( var j = 0; j < rows.length; j++) {
			var val = rows.eq(j).find('td').eq(i).html();
			hcps[val] = 1;
		}

		var args;
		for ( var h in hcps) {
			// Get node without domain name
			args = h.split('.');
			
			// Check if SMAPI is online
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'lsvm',
					tgt : args[0],
					args : '',
					msg : 'group=' + group + ';hcp=' + args[0]
				},

				// Load hardware control point (HCP) specific info
				// Get disk pools and network names
				success : loadHcpInfo
			});			
		} // End of for
	} // End of if
}

/**
 * Load power status for each node
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function loadPowerStatus(data) {
	// Get datatable
	var dTable = $('#nodesDataTable').dataTable();
	var power = data.rsp;
	var rowNum, node, status, args;

	for ( var i in power) {
		// power[0] = nodeName and power[1] = state
		args = power[i].split(':');
		node = jQuery.trim(args[0]);
		status = jQuery.trim(args[1]);

		// Get the row containing the node
		rowNum = getRowNum(node);

		// Update the power status column
		dTable.fnUpdate(status, rowNum, 3);
	}
	
	// Hide power loader
	var powerCol = $('#nodesDataTable thead tr th').eq(3);
	powerCol.find('img').hide();
}

/**
 * Refresh power status for each node
 * 
 * @param group
 *            Group name
 * @return Nothing
 */
function refreshPowerStatus(group) {
	// Show power loader
	var powerCol = $('#nodesDataTable thead tr th').eq(3);
	powerCol.find('img').show();
	
	// Get the power status
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'rpower',
			tgt : group,
			args : 'stat',
			msg : ''
		},

		success : loadPowerStatus
	});
}

/**
 * Load ping status for each node
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function loadPingStatus(data) {
	// Get data table
	var dTable = $('#nodesDataTable').dataTable();
	var ping = data.rsp;
	var rowPos, node, status;

	// Get all nodes within the datatable
	var rows = dTable.fnGetNodes();
	for ( var i in ping) {
		// ping[0] = nodeName and ping[1] = state
		node = jQuery.trim(ping[i][0]);
		status = jQuery.trim(ping[i][1]);

		// Get the row containing the node
		rowPos = getRowNum(node);

		// Update the ping status column
		dTable.fnUpdate(status, rowPos, 2);
	}
	
	// Hide ping loader
	var pingCol = $('#nodesDataTable thead tr th').eq(2);
	pingCol.find('img').hide();
}

/**
 * Refresh ping status for each node
 * 
 * @param group
 *            Group name
 * @return Nothing
 */
function refreshPingStatus(group) {
	// Show ping loader
	var pingCol = $('#nodesDataTable thead tr th').eq(2);
	pingCol.find('img').show();
	
	// Get the ping status
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'pping ' + group,
			msg : ''
		},

		success : loadPingStatus
	});
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
	var mgt = getNodeAttr(node, 'mgt');
		
	// Create an instance of the plugin
	var plugin;
	switch(mgt) {
		case "blade":
    		plugin = new bladePlugin();
    		break;
		case "fsp":
			plugin = new fspPlugin();
			break;
		case "hmc":
			plugin = new hmcPlugin();
			break;
		case "ipmi":
			plugin = new ipmiPlugin();
			break;		
		case "ivm":
			plugin = new ivmPlugin();
			break;
		case "zvm":
			plugin = new zvmPlugin();
			break;
	}

	// Get tab area where a new tab will be inserted
	var myTab = getNodesTab();
	var inst = 0;
	var newTabId = 'nodeTab' + inst;
	while ($('#' + newTabId).length) {
		// If one already exists, generate another one
		inst = inst + 1;
		newTabId = 'nodeTab' + inst;
	}
	// Reset node process
	$.cookie(node + 'Processes', 0);

	// Add new tab, only if one does not exist
	var loader = createLoader(newTabId + 'TabLoader');
	loader = $('<center></center>').append(loader);
	myTab.add(newTabId, node, loader, true);

	// Get node inventory
	var msg = 'out=' + newTabId + ',node=' + node;
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'rinv',
			tgt : node,
			args : 'all',
			msg : msg
		},

		success : plugin.loadInventory
	});

	// Select new tab
	myTab.select(newTabId);
}

/**
 * Unlock a node by setting the SSH keys
 * 
 * @param tgtNodes
 *            Nodes to unlock
 * @return Nothing
 */
function loadUnlockPage(tgtNodes) {
	// Get nodes tab
	var tab = getNodesTab();

	// Generate new tab ID
	var instance = 0;
	var newTabId = 'UnlockTab' + instance;
	while ($('#' + newTabId).length) {
		// If one already exists, generate another one
		instance = instance + 1;
		newTabId = 'UnlockTab' + instance;
	}

	var unlockForm = $('<div class="form"></div>');

	// Create status bar, hide on load
	var statBarId = 'UnlockStatusBar' + instance;
	var statusBar = createStatusBar(statBarId).hide();
	unlockForm.append(statusBar);

	// Create loader
	var loader = createLoader('');
	statusBar.append(loader);

	// Create info bar
	var infoBar = createInfoBar('Give the root password for this node range to setup its SSH keys');
	unlockForm.append(infoBar);

	unlockForm.append('<div><label>Target node range:</label><input type="text" id="node" name="node" readonly="readonly" value="' + tgtNodes + '" title="The node or node range to unlock"/></div>');
	unlockForm.append('<div><label>Password:</label><input type="password" id="password" name="password" title="The root password to unlock this node"/></div>');

	// Generate tooltips
	unlockForm.find('div input[title]').tooltip({
		position: "center right",	// Place tooltip on the right edge
		offset: [-2, 10],	// A little tweaking of the position
		effect: "fade",		// Use the built-in fadeIn/fadeOut effect
		opacity: 0.7		// Custom opacity setting
	});
	
	/**
	 * Ok
	 */
	var okBtn = createButton('Ok');
	okBtn.bind('click', function(event) {
		// Remove any warning messages
		$(this).parent().parent().find('.ui-state-error').remove();
		
		// If form is complete
		var ready = formComplete(newTabId);
		if (ready) {
			var password = $('#' + newTabId + ' input[name=password]').val();

			// Setup SSH keys
    		$.ajax( {
    			url : 'lib/cmd.php',
    			dataType : 'json',
    			data : {
    				cmd : 'webrun',
    				tgt : '',
    				args : 'unlock;' + tgtNodes + ';' + password,
    				msg : 'out=' + statBarId + ';cmd=unlock;tgt=' + tgtNodes
    			},
    
    			success : updateStatusBar
    		});
    
    		// Show status bar
    		statusBar.show();
    
    		// Disable Ok button
    		$(this).attr('disabled', 'true');
    	} else {
    		// Show warning message
			var warn = createWarnBar('You are missing some values');
			warn.prependTo($(this).parent().parent());
    	}
    });

	unlockForm.append(okBtn);
	tab.add(newTabId, 'Unlock', unlockForm, true);
	tab.select(newTabId);
}

/**
 * Load script page
 * 
 * @param tgtNodes
 *            Targets to run script against
 * @return Nothing
 */
function loadScriptPage(tgtNodes) {
	// Get nodes tab
	var tab = getNodesTab();

	// Generate new tab ID
	var inst = 0;
	var newTabId = 'scriptTab' + inst;
	while ($('#' + newTabId).length) {
		// If one already exists, generate another one
		inst = inst + 1;
		newTabId = 'scriptTab' + inst;
	}

	// Open new tab
	// Create remote script form
	var scriptForm = $('<div class="form"></div>');

	// Create status bar
	var barId = 'scriptStatusBar' + inst;
	var statBar = createStatusBar(barId);
	statBar.hide();
	scriptForm.append(statBar);

	// Create loader
	var loader = createLoader('scriptLoader' + inst);
	statBar.append(loader);

	// Create info bar
	var infoBar = createInfoBar('Run a script against this node range');
	scriptForm.append(infoBar);

	// Target node or group
	var tgt = $('<div><label for="target">Target node range:</label><input type="text" name="target" value="' + tgtNodes + '" title="The node or node range to run a given script against"/></div>');
	scriptForm.append(tgt);

	// Upload file
	var upload = $('<form action="lib/upload.php" method="post" enctype="multipart/form-data"></form>');
	var label = $('<label for="file">Remote file:</label>');
	var file = $('<input type="file" name="file" id="file"/>');
	var subBtn = createButton('Load');
	upload.append(label);
	upload.append(file);
	upload.append(subBtn);
	scriptForm.append(upload);
	
	// Generate tooltips
	scriptForm.find('div input[title]').tooltip({
		position: "center right",	// Place tooltip on the right edge
		offset: [-2, 10],	// A little tweaking of the position
		effect: "fade",		// Use the built-in fadeIn/fadeOut effect
		opacity: 0.7		// Custom opacity setting
	});

	// Script
	var script = $('<div><label>Script:</label><textarea/>');
	scriptForm.append(script);

	// Ajax form options
	var options = {
		// Output to text area
		target : '#' + newTabId + ' textarea'
	};
	upload.ajaxForm(options);

	/**
	 * Run
	 */
	var runBtn = createButton('Run');
	runBtn.bind('click', function(event) {
		// Remove any warning messages
		$(this).parent().parent().find('.ui-state-error').remove();
		
		var ready = true;

		// Check script
		var textarea = $('#' + newTabId + ' textarea');
		for ( var i = 0; i < textarea.length; i++) {
			if (!textarea.eq(i).val()) {
				textarea.eq(i).css('border', 'solid #FF0000 1px');
				ready = false;
			} else {
				textarea.eq(i).css('border', 'solid #424242 1px');
			}
		}

		// If no inputs are empty
		if (ready) {
			// Run script
			runScript(inst);
		} else {
			// Show warning message
			var warn = createWarnBar('You are missing some values');
			warn.prependTo($(this).parent().parent());
		}
	});
	scriptForm.append(runBtn);

	// Append to discover tab
	tab.add(newTabId, 'Script', scriptForm, true);

	// Select new tab
	tab.select(newTabId);
}

/**
 * Sort a list
 * 
 * @return Sorted list
 */
jQuery.fn.sort = function() {
	return this.pushStack( [].sort.apply(this, arguments), []);
};

function sortAlpha(a, b) {
	return a.innerHTML > b.innerHTML ? 1 : -1;
};

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
	node = node.replace('Power', '');
	$.ajax( {
		url : 'lib/cmd.php',
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
 * Delete a given node
 * 
 * @param tgtNodes
 *            Nodes to delete
 * @return Nothing
 */
function deleteNode(tgtNodes) {
	// Get datatable
	var myTab = getNodesTab();

	// Generate new tab ID
	var inst = 0;
	newTabId = 'DeleteTab' + inst;
	while ($('#' + newTabId).length) {
		// If one already exists, generate another one
		inst = inst + 1;
		newTabId = 'DeleteTab' + inst;
	}

	// Create status bar, hide on load
	var statBarId = 'DeleteStatusBar' + inst;
	var statBar = $('<div class="statusBar" id="' + statBarId + '"></div>').hide();

	// Create loader
	var loader = createLoader('');
	statBar.append(loader);
	statBar.hide();

	// Create target nodes string
	var tgtNodesStr = '';
	var nodes = tgtNodes.split(',');
	// Loop through each node
	for ( var i in nodes) {
		// If it is the 1st and only node
		if (i == 0 && i == nodes.length - 1) {
			tgtNodesStr += nodes[i];
		}
		// If it is the 1st node of many nodes
		else if (i == 0 && i != nodes.length - 1) {
			// Append a comma to the string
			tgtNodesStr += nodes[i] + ', ';
		} else {
			// If it is the last node
			if (i == nodes.length - 1) {
				// Append nothing to the string
				tgtNodesStr += nodes[i];
			} else {
				// Append a comma to the string
				tgtNodesStr += nodes[i] + ', ';
			}
		}
	}

	var deleteForm = $('<div class="form"></div>');
	deleteForm.append(statBar);
	deleteForm.append(statBar);
	
	// Word wrap
	var instr = $('<p>Do you want to delete ' + tgtNodesStr + '?</p>').css('word-wrap', 'break-word');
	deleteForm.append(instr);

	/**
	 * Delete
	 */
	var deleteBtn = createButton('Delete');
	deleteBtn.bind('click', function(event) {
		// Delete the virtual server
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'rmvm',
				tgt : tgtNodes,
				args : '',
				msg : 'out=' + statBarId + ';cmd=rmvm;tgt=' + tgtNodes
			},

			success : updateStatusBar
		});

		// Show status bar loader
		statBar.show();

		// Disable delete button
		$(this).attr('disabled', 'true');
	});
	
	var cancelBtn = createButton('Cancel');
	cancelBtn.bind('click', function(){
		myTab.remove($(this).parent().parent().attr('id'));
	});

	deleteForm.append(deleteBtn);
	deleteForm.append(cancelBtn);
	myTab.add(newTabId, 'Delete', deleteForm, true);

	myTab.select(newTabId);
}

/**
 * Update status bar of a given tab
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function updateStatusBar(data) {
	// Get ajax response
	var rsp = data.rsp;
	var args = data.msg.split(';');
	var statBarId = args[0].replace('out=', '');
	var cmd = args[1].replace('cmd=', '');
	var tgts = args[2].replace('tgt=', '').split(',');

	if (cmd == 'unlock' || cmd == 'updatenode') {
		// Hide loader
		$('#' + statBarId).find('img').hide();

		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).append(prg);	
	} else if (cmd == 'rmvm') {
		// Get data table
		var dTable = $('#nodesDataTable').dataTable();
		var failed = false;

		// Hide loader
		$('#' + statBarId).find('img').hide();

		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).append(prg);	
		
		// If there was an error, do not continue
		if (prg.html().indexOf('Error') > -1) {
			failed = true;
		}

		// Update data table
		var rows = dTable.fnGetNodes();
		for ( var i = 0; i < tgts.length; i++) {
			if (!failed) {
				// Get the row containing the node link and delete it
				var row = getNodeRow(tgts[i], rows);
				var rowPos = dTable.fnGetPosition(row);
				dTable.fnDeleteRow(rowPos);
			}
		}
	} else if (cmd == 'xdsh') {
		// Hide loader
		$('#' + statBarId).find('img').hide();
		
		// Write ajax response to status bar
		var prg = $('<p></p>');
		for (var i in rsp) {
			for (var j in tgts) {
				rsp[i] = rsp[i].replace(new RegExp(tgts[j] + ':', 'g'), '<br>');
			}

			prg.append(rsp[i]);
			prg.append('<br>');	
		}
		$('#' + statBarId).append(prg);	
		
		// Enable fields
		$('#' + statBarId).parent().find('input').removeAttr('disabled');
		$('#' + statBarId).parent().find('textarea').removeAttr('disabled');
		
		// Enable buttons
		$('#' + statBarId).parent().find('button').removeAttr('disabled');
	} else {
		// Hide loader
		$('#' + statBarId).find('img').hide();
		
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '[A-Za-z0-9._-]+:');	
		$('#' + statBarId).append(prg);	
	}
}

/**
 * Check if the form is complete
 * 
 * @param tabId
 *            Tab ID containing form
 * @return True: If the form is complete, False: Otherwise
 */
function formComplete(tabId) {
	var ready = true;

	// Check all inputs within the form
	var inputs = $('#' + tabId + ' input');
	for ( var i = 0; i < inputs.length; i++) {
		// If there is no value given in the input
		if (!inputs.eq(i).val()) {
			inputs.eq(i).css('border', 'solid #FF0000 1px');
			
			// It is not complete
			ready = false;
		} else {
			inputs.eq(i).css('border', 'solid #BDBDBD 1px');
		}
	}

	return ready;
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
	var dTable = $('#nodesDataTable').dataTable();

	// Get all nodes within the datatable
	var rows = dTable.fnGetNodes();

	// Get xCAT response
	var rsp = data.rsp;
	// Loop through each line
	for ( var i = 0; i < rsp.length; i++) {
		// Get the node
		var node = rsp[i].split(":")[0];

		// If there is no error
		var status;
		if (rsp[i].indexOf("Error") < 0 || rsp[i].indexOf("Failed") < 0) {
			// Get the row containing the node link
			var row = getNodeRow(node, rows);
			var rowPos = dTable.fnGetPosition(row);

			// If it was power on, then the data return would contain "Starting"
			var strPos = rsp[i].indexOf("Starting");
			if (strPos > -1) {
				status = 'on';
			} else {
				status = 'off';
			}

			// Update the power status column
			dTable.fnUpdate(status, rowPos, 3);
		} else {
			// Power on/off failed
			alert(rsp[i]);
		}
	}
}

/**
 * Run a script
 * 
 * @param inst
 *            Remote script tab instance
 * @return Nothing
 */
function runScript(inst) {
	var tabId = 'scriptTab' + inst;
	
	// Get node name
	var tgts = $('#' + tabId + ' input[name=target]').val();
	// Get script
	var script = $('#' + tabId + ' textarea').val();
	
	var statBarId = 'scriptStatusBar' + inst;
	$('#' + statBarId).show();					// Show status bar
	$('#' + statBarId + ' img').show();			// Show loader
	$('#' + statBarId + ' p').remove();			// Clear status bar

	// Disable all fields
	$('#' + tabId + ' input').attr('disabled', 'true');
	$('#' + tabId + ' textarea').attr('disabled', 'true');
	
	// Disable buttons
	$('#' + tabId + ' button').attr('disabled', 'true');

	// Run script
	$.ajax( {
		url : 'lib/zCmd.php',
		dataType : 'json',
		data : {
			cmd : 'xdsh',
			tgt : tgts,
			args : '-e',
			att : script,
			msg : 'out=scriptStatusBar' + inst + ';cmd=xdsh;tgt=' + tgts
		},

		success : updateStatusBar
	});
}

/**
 * Get an attribute of a given node
 * 
 * @param node
 *            The node
 * @param attrName
 *            The attribute
 * @return The attribute of the node
 */
function getNodeAttr(node, attrName) {
	// Get the row
	var row = $('[id=' + node + ']').parent().parent();

	// Search for the column containing the attribute
	var attrCol;
	var cols = row.parent().parent().find('th:contains("' + attrName + '")');
	// Loop through each column
	for (var i in cols) {
		// Find column that matches the attribute
		if (cols.eq(i).html() == attrName) {
			attrCol = cols.eq(i);
			break;
		}
	}
	
	// If the column containing the attribute is found
	if (attrCol) {
		// Get the attribute column index
		var attrIndex = attrCol.index();

		// Get the attribute for the given node
		var attr = row.find('td:eq(' + attrIndex + ')');

		return attr.text();
	} else {
		return '';
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
	var rsp = data.rsp;

	var imageNames = new Array;
	var profilesHash = new Object();
	var osVersHash = new Object();
	var osArchsHash = new Object();

	for ( var i = 1; i < rsp.length; i++) {
		// osimage table columns: imagename, profile, imagetype, provmethod,
		// osname, osvers, osdistro, osarch, synclists, comments, disable
		// e.g. sles11.1-s390x-statelite-compute, compute, linux, statelite,
		// Linux, sles11.1, , s390x, , s,

		// Get the image name
		var cols = rsp[i].split(',');
		var osImage = cols[0].replace(new RegExp('"', 'g'), '');
		var profile = cols[1].replace(new RegExp('"', 'g'), '');
		var osVer = cols[5].replace(new RegExp('"', 'g'), '');
		var osArch = cols[7].replace(new RegExp('"', 'g'), '');
		imageNames.push(osImage);
		profilesHash[profile] = 1;
		osVersHash[osVer] = 1;
		osArchsHash[osArch] = 1;
	}

	// Save image names in a cookie
	$.cookie('ImageNames', imageNames);

	// Save profiles in a cookie
	var tmp = new Array;
	for ( var key in profilesHash) {
		tmp.push(key);
	}
	$.cookie('Profiles', tmp);

	// Save OS versions in a cookie
	tmp = [];
	for ( var key in osVersHash) {
		tmp.push(key);
	}
	$.cookie('OSVers', tmp);

	// Save OS architectures in a cookie
	tmp = [];
	for ( var key in osArchsHash) {
		tmp.push(key);
	}
	$.cookie('OSArchs', tmp);
}

/**
 * Set a cookie for the groups
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function setGroupsCookies(data) {
	var rsp = data.rsp;
	$.cookie('Groups', rsp);
}

/**
 * Get row element that contains given node
 * 
 * @param tgtNode
 *            Node to find
 * @param rows
 *            Rows within the datatable
 * @return Row element
 */
function getNodeRow(tgtNode, rows) {
	// Find the row
	for ( var i in rows) {
		// Get all columns within the row
		var cols = rows[i].children;
		// Get the 1st column (node name)
		var cont = cols[1].children;
		var node = cont[0].innerHTML;

		// If the node matches the target node
		if (node == tgtNode) {
			// Return the row
			return rows[i];
		}
	}

	return;
}

/**
 * Get nodes that are checked in a given datatable
 * 
 * @param datatableId
 *            The datatable ID
 * @return Nodes that were checked
 */
function getNodesChecked(datatableId) {
	var tgts = '';

	// Get nodes that were checked
	var nodes = $('#' + datatableId + ' input[type=checkbox]:checked');
	for ( var i = 0; i < nodes.length; i++) {
		var tgtNode = nodes.eq(i).attr('name');
		
		if (tgtNode){
			tgts += tgtNode;
			
			// Add a comma at the end
			if (i < nodes.length - 1) {
				tgts += ',';
			}
		}
	}

	return tgts;
}

/**
 * Get the column index for a given column name
 * 
 * @param colName
 *            The column name to search
 * @return The index containing the column name
 */
function getColNum(colName){
	var colNum;
	var columns = $('table thead tr').children();
	
	for(colNum = 1; colNum < columns.length; colNum++){
		if (colName == columns[colNum].innerHTML){
			return colNum;
		}
	}
	return -1;
}

/**
 * Get the row index for a given node name
 * 
 * @param nodeName
 *            Node name
 * @return The row index containing the node name
 */
function getRowNum(nodeName){
	// Get datatable
	var dTable = $('#nodesDataTable').dataTable();
	
	// Get all data from datatable
	var data = dTable.fnGetData();
	
	var row;
	var nodeItem;
			
	for(row = 0; row < data.length; row++){
		nodeItem = data[row][1];
		if(nodeItem.indexOf('>' + nodeName + '<') > -1){
			return row;
		}
	}
	return -1;
}

/**
 * Select all checkboxes in a given datatable
 * 
 * @param event
 *            Event on element
 * @param obj
 *            Object triggering event
 * @return Nothing
 */
function selectAllCheckbox(event, obj) {
	// Get datatable ID
	// This will ascend from <input> <td> <tr> <thead> <table>
	var datatableId = obj.parent().parent().parent().parent().attr('id');
	var status = obj.attr('checked');
	$('#' + datatableId + ' :checkbox').attr('checked', status);
	event.stopPropagation();
}

/**
 * Load rcons page
 * 
 * @param tgtNodes
 *            Targets to run rcons against
 * @return Nothing
 */
function loadRconsPage(tgtNodes){
	var hostName = window.location.host;
	var urlPath = window.location.pathname;
	var redirectUrl = 'https://';
	var pos = 0;
	// We only support one node
	if (-1 != tgtNodes.indexOf(',')){
		alert("Sorry, the Rcons Page only support one node.");
		return;
	}
	
	redirectUrl += hostName;
	pos = urlPath.lastIndexOf('/');
	redirectUrl += urlPath.substring(0, pos + 1);
	redirectUrl += 'rconsShow.php';
	
	// Open the rcons page
	window.open(redirectUrl + "?rconsnd=" + tgtNodes, '', "toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=no,width=670,height=436");
}

/**
 * Flag the node in the group table to update
 * 
 * @param node
 *            The node name
 * @return Nothing
 */
function flagNode2Update(node) {
	// Get list containing current nodes to update
	var nodes = $.cookie('Nodes2Update');

	// If the node is not in the list
	if (nodes.indexOf(node) == -1) {
		// Add the new node to list
		nodes += node + ';';
		$.cookie('Nodes2Update', nodes);
	}
}

/**
 * Update the node attributes
 * 
 * @param group
 *            The node group name
 * @return Nothing
 */
function updateNodeAttrs(group) {
	// Get header table names
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'lsdef',
			tgt : '',
			args : group + ';-l;-V',	// Long verbose
			msg : ''
		},

		/**
		 * Create a command to send to xCAT to update the nodes attributes
		 * 
		 * @param data
		 *            Data returned from HTTP request
		 * @return Nothing
		 */
		success : function(data){
			// Get data returned
			var out = data.rsp;

			// Create hash table where key = attribute and value = table name
			var attrTable = new Object();
			var key, value;
			var begin, end, tmp;
			for (var i = 0; i < out.length; i++) {
				// If the line contains "("
				if (out[i].indexOf('(') > -1) {
					// Get the index of "(" and ")"
					begin = out[i].indexOf('(') + 1;
					end = out[i].indexOf(')');
					
					// Split the attribute, e.g. Table:nodetype - Key:node -
					// Column:arch
					tmp = out[i].substring(begin, end).split('-');
					key = jQuery.trim(tmp[2].replace('Column:', ''));
					value = jQuery.trim(tmp[0].replace('Table:', ''));
					attrTable[key] = value;
				}
			}
			
			// Get the nodes datatable
			var dTable = $('#nodesDataTable').dataTable();
			// Get all nodes within the datatable
			var rows = dTable.fnGetNodes();
			
			// Get table headers
			var headers = $('#nodesDataTable thead tr th');
									
			// Get list of nodes to update
			var nodesList = $.cookie('Nodes2Update');
			var nodes = nodesList.split(';');
			
			// Create the arguments
			var args;
			var row, colPos, value;
			var attrName, tableName;
			// Go through each node where an attribute was changed
			for (var i = 0; i < nodes.length; i++) {
				if (nodes[i]) {
					args = '';
					
		        	// Get the row containing the node link
		        	row = getNodeRow(nodes[i], rows);
		        	$(row).find('td').each(function (){
		        		if ($(this).css('color') == 'red') {
		        			// Change color back to normal
		        			$(this).css('color', '');
		        			
		        			// Get column position
		        			colPos = $(this).parent().children().index($(this));
		        			// Get column value
		        			value = $(this).text();
		        			
		        			// Get attribute name
		        			attrName = jQuery.trim(headers.eq(colPos).text());
		        			// Get table name where attribute belongs in
		        			tableName = attrTable[attrName];
		        			
		        			// Build argument string
		        			if (args) {
		        				// Handle subsequent arguments
		        				args += ' ' + tableName + '.' + attrName + '="' + value + '"';
		        			} else {
		        				// Handle the 1st argument
		        				args += tableName + '.' + attrName + '="' + value + '"';
		        			}
		        			        			
		        		}
		        	});
		        	
		        	// Send command to change node attributes
		        	$.ajax( {
		        		url : 'lib/cmd.php',
		        		dataType : 'json',
		        		data : {
		        			cmd : 'webrun',
		        			tgt : '',
		        			args : 'chtab node=' + nodes[i] + ' ' + args,
		        			msg : ''
		        		},

		        		success: showChtabOutput
		        	});
				} // End of if
			} // End of for
			
			// Clear cookie containing list of nodes where
			// their attributes need to be updated
			$.cookie('Nodes2Update', '');
		} // End of function
	});
}

/**
 * Restore node attributes to their original content
 * 
 * @return Nothing
 */
function restoreNodeAttrs() {
	// Get list of nodes to update
	var nodesList = $.cookie('Nodes2Update');
	var nodes = nodesList.split(';');
	
	// Get the nodes datatable
	var dTable = $('#nodesDataTable').dataTable();
	// Get table headers
	var headers = $('#nodesDataTable thead tr th');
	// Get all nodes within the datatable
	var rows = dTable.fnGetNodes();
		
	// Go through each node where an attribute was changed
	var row, colPos;
	var attrName, origVal;
	for (var i = 0; i < nodes.length; i++) {
		if (nodes[i]) {			
			// Get the row containing the node link
        	row = getNodeRow(nodes[i], rows);
        	$(row).find('td').each(function (){
        		if ($(this).css('color') == 'red') {
        			// Change color back to normal
        			$(this).css('color', '');
        			
        			// Get column position
        			colPos = $(this).parent().children().index($(this));	        			
        			// Get attribute name
        			attrName = jQuery.trim(headers.eq(colPos).text());
        			// Get original content
        			origVal = origAttrs[nodes[i]][attrName];
        			
        			// Update column
        			rowPos = getRowNum(nodes[i]);
        			dTable.fnUpdate(origVal, rowPos, colPos);
        		}
        	});
		} // End of if
	} // End of for
	
	// Clear cookie containing list of nodes where
	// their attributes need to be updated
	$.cookie('Nodes2Update', '');
}

/**
 * Create a tool tip for comment
 * 
 * @param comment
 *            The comments to be placed in the tool tip
 * @return Tool tip
 */
function createCommentsToolTip(comment) {
	// Create tooltip container
	var toolTip = $('<div class="tooltip"></div>');
	// Create textarea to hold comment
	var txtArea = $('<textarea>' + comment + '</textarea>').css({
		'font-size': '10px',
		'height': '50px',
		'width': '200px',
		'background-color': '#000',
		'color': '#fff',
		'border': '0px',
		'display': 'block'
	});
	
	// Create links to save and cancel changes
	var lnkStyle = {
		'color': '#58ACFA',
		'font-size': '10px',
		'display': 'inline-block',
		'padding': '5px',
		'float': 'right'
	};
	var saveLnk = $('<a>Save</a>').css(lnkStyle).hide();
	var cancelLnk = $('<a>Cancel</a>').css(lnkStyle).hide();
	
	// Save changes onclick
	saveLnk.bind('click', function(){
		// Get node and comment
		var node = $(this).parent().parent().find('img').attr('id').replace('Tip', '');
		var comments = $(this).parent().find('textarea').val();
		
		// Save comment
		$.ajax( {
    		url : 'lib/cmd.php',
    		dataType : 'json',
    		data : {
    			cmd : 'webrun',
    			tgt : '',
    			args : 'chtab node=' + node + ' nodelist.comments="' + comments + '"',
    			msg : ''
    		},
    		
    		success: showChtabOutput
		});
		
		// Hide cancel and save links
		$(this).hide();
		cancelLnk.hide();
	});
		
	// Cancel changes onclick
	cancelLnk.bind('click', function(){
		// Get original comment and put it back
		var orignComments = $(this).parent().find('textarea').text();
		$(this).parent().find('textarea').val(orignComments);
		
		// Hide cancel and save links
		$(this).hide();
		saveLnk.hide();
	});
	
	// Show save link when comment is edited
	txtArea.bind('click', function(){
		saveLnk.show();
		cancelLnk.show();
	});
		
	toolTip.append(txtArea);
	toolTip.append(cancelLnk);
	toolTip.append(saveLnk);
	
	return toolTip;
}

/**
 * Show chtab output
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function showChtabOutput(data) {
	// Get output
	var out = data.rsp;
	
	// Find info bar on nodes tab, if any
	var info = $('#nodesTab').find('.ui-state-highlight');
	if (!info.length) {
		// Create info bar if one does not exist
		info = createInfoBar('');
		$('#nodesTab').append(info);
	}
		
	// Go through output and append to paragraph
	var node, status;
	var pg = $('<p></p>');
	for ( var i in out) {
		// out[0] = node name and out[1] = status
		node = jQuery.trim(out[i][0]);
		status = jQuery.trim(out[i][1]);
		pg.append(node + ': ' + status + '<br>');
	}
	
	info.append(pg);
}