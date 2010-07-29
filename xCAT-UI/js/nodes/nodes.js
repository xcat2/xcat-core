/**
 * Global variables
 */
var nodesTabs; // Node tabs
var nodesDataTable; // Datatable containing all nodes within a group

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
 * Get the nodes datatable
 * 
 * @param Nothing
 * @return Data table object
 */
function getNodesDataTable() {
	return nodesDataTable;
}

/**
 * Set the nodes datatable
 * 
 * @param table
 *            Data table object
 * @return Nothing
 */
function setNodesDataTable(table) {
	nodesDataTable = table;
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
	var item = $('<li><ins></ins><h3>Groups</h3></li>');
	ul.append(item);
	var subUL = $('<ul></ul>');
	item.append(subUL);

	// Create a link for each group
	for ( var i = groups.length; i--;) {
		var subItem = $('<li></li>');
		var link = $('<a href="#"><ins></ins>' + groups[i] + '</a>');
		subItem.append(link);
		subUL.append(subItem);
	}

	// Turn groups list into a tree
	$('#groups').append(ul);
	$('#groups').tree( {
		callback : {
			// Open group onclick
    		onselect : function(node, tree) {
    			var thisGroup = tree.get_text(node);
    			if (thisGroup) {
    				// Clear nodes division
    				$('#nodes').children().remove();
    				// Create loader
    				var loader = $('<center></center>').append(createLoader());
    
    				// Create a tab for this group
    				var tab = new Tab();
    				setNodesTab(tab);
    				tab.init();
    				$('#nodes').append(tab.object());
    				tab.add('nodesTab', 'Nodes', loader);
    
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
    			} // End of if (thisGroup)
    		} // End of onselect
    	} // End of callback
    });
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

	// Sort headers
	var sorted = new Array();
	for ( var key in headers) {
		sorted.push(key);
	}
	sorted.sort();

	// Add column for check box, node, ping, and power
	sorted.unshift('<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">', 'node', 'ping', 'power');

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
		var nodeLink = $('<a class="node" id="' + node + '" href="#">' + node + '</a>').bind('click', loadNode);
		row.push(checkBx, nodeLink, '', '');

		// Go through each header
		for ( var i = 4; i < sorted.length; i++) {
			// Add the node attributes to the row
			var key = sorted[i];
			var val = attrs[node][key];
			if (val) {
				row.push(val);
			} else {
				row.push('');
			}
		}

		// Add the row to the table
		dTable.add(row);
	}

	// Clear the tab before inserting the table
	$('#nodesTab').children().remove();

	// Create action bar
	var actionBar = $('<div class="actionBar"></div>');

	/**
	 * The following actions are available to perform against a given node:
	 * power, clone, delete, unlock, and advanced
	 */

	/*
	 * Power
	 */
	var powerLnk = $('<a href="#">Power</a>');

	/*
	 * Power on
	 */
	var powerOnLnk = $('<a href="#">Power on</a>');
	powerOnLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			powerNode(tgtNodes, 'on');
		}
	});

	/*
	 * Power off
	 */
	var powerOffLnk = $('<a href="#">Power off</a>');
	powerOffLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			powerNode(tgtNodes, 'off');
		}
	});

	/*
	 * Clone
	 */
	var cloneLnk = $('<a href="#">Clone</a>');
	cloneLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable').split(',');
		for ( var i = 0; i < tgtNodes.length; i++) {
			var mgt = getNodeMgt(tgtNodes[i]);
			
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

	/*
	 * Delete
	 */
	var deleteLnk = $('<a href="#">Delete</a>');
	deleteLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			deleteNode(tgtNodes);
		}
	});

	/*
	 * Unlock
	 */
	var unlockLnk = $('<a href="#">Unlock</a>');
	unlockLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			loadUnlockPage(tgtNodes);
		}
	});

	/*
	 * Run script
	 */
	var scriptLnk = $('<a href="#">Run script</a>');
	scriptLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			loadScriptPage(tgtNodes);
		}
	});

	/*
	 * Update node
	 */
	var updateLnk = $('<a href="#">Update</a>');
	updateLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			loadUpdatenodePage(tgtNodes);
		}
	});

	/*
	 * Set boot state
	 */
	var setBootStateLnk = $('<a href="#">Set boot state</a>');
	setBootStateLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			loadNodesetPage(tgtNodes);
		}

	});

	/*
	 * Boot to network
	 */
	var boot2NetworkLnk = $('<a href="#">Boot to network</a>');
	boot2NetworkLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			loadNetbootPage(tgtNodes);
		}
	});

	/*
	 * Advanced
	 */
	var advancedLnk = $('<a href="#">Advanced</a>');

	// Power actions
	var powerActions = [ powerOnLnk, powerOffLnk ];
	var powerActionMenu = createMenu(powerActions);

	// Advanced actions
	var advancedActions = [ boot2NetworkLnk, scriptLnk, setBootStateLnk, updateLnk ];
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

	// Turn table into a datatable
	var myDataTable = $('#nodesDataTable').dataTable();
	setNodesDataTable(myDataTable);

	/**
	 * Get power and ping status for each node
	 */

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

	/**
	 * Additional ajax requests need to be made for zVM
	 */

	// Get the index of the HCP column
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

			// Get disk pools
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'lsvm',
					tgt : args[0],
					args : '--diskpoolnames',
					msg : args[0]
				},

				success : setDiskPoolCookies
			});

			// Get network names
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'lsvm',
					tgt : args[0],
					args : '--getnetworknames',
					msg : args[0]
				},

				success : setNetworkCookies
			});
		}
	}
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
	var dTable = getNodesDataTable();
	var power = data.rsp;
	var rowNum, node, status, args;

	for ( var i in power) {
		// node name and power status, where power[0] = nodeName and power[1] = state
		args = power[i].split(':');
		node = jQuery.trim(args[0]);
		status = jQuery.trim(args[1]);

		// Get the row containing the node
		rowNum = getRowNum(node);

		//update the data in the 
		dTable.fnUpdate(status, rowNum, 3);
	}
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
	var dTable = getNodesDataTable();
	var ping = data.rsp;
	var rowPos, node, status;

	// Get all nodes within the datatable
	var rows = dTable.fnGetNodes();
	for ( var i in ping) {
		// where ping[0] = nodeName ping[1] = state
		node = jQuery.trim(ping[i][0]);
		status = jQuery.trim(ping[i][1]);

		// Get the row containing the node
		rowPos = getRowNum(node);

		// Update the power status column
		dTable.fnUpdate(status, rowPos, 2);
	}
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
	var mgt = getNodeMgt(node);
	
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
	// the node name may contain special char(such as '.','#'), so we can not use the node name as a id.
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
	myTab.add(newTabId, node, loader);

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
	// tabid may contains special char, so we had to use the index
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

	unlockForm.append('<div><label>Node range:</label><input type="text" id="node" name="node" readonly="readonly" value="' + tgtNodes + '"/></div>');
	unlockForm.append('<div><label>Password:</label><input type="password" id="password" name="password"/></div>');

	/**
	 * Ok
	 */
	var okBtn = createButton('Ok');
	okBtn.bind('click', function(event) {
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
    		$(this).unbind(event);
    		$(this).css( {
    			'background-color' : '#F2F2F2',
    			'color' : '#BDBDBD'
    		});
    	}
    });

	unlockForm.append(okBtn);
	tab.add(newTabId, 'Unlock', unlockForm);
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
	var loader = createLoader('scriptLoader');
	statBar.append(loader);

	// Create info bar
	var infoBar = createInfoBar('Run a script against this node range');
	scriptForm.append(infoBar);

	// Target node or group
	var tgt = $('<div><label for="target">Target node or group:</label><input type="text" name="target" value="' + tgtNodes + '"/></div>');
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

			// Stop this function from executing again
			// Unbind event
			$(this).unbind(event);
			$(this).css( {
				'background-color' : '#F2F2F2',
				'color' : '#424242'
			});

			// Show status bar
			statBar.show();
		} else {
			alert('You are missing some values');
		}
	});
	scriptForm.append(runBtn);

	// Append to discover tab
	tab.add(newTabId, 'Script', scriptForm);

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
		$(this).unbind(event);
		$(this).css( {
			'background-color' : '#F2F2F2',
			'color' : '#BDBDBD'
		});
	});
	
	var cancelBtn = createButton('Cancel');
	cancelBtn.bind('click', function(){
		myTab.remove($(this).parent().parent().attr('id'));
	});

	deleteForm.append(deleteBtn);
	deleteForm.append(cancelBtn);
	myTab.add(newTabId, 'Delete', deleteForm);

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

	if (cmd == 'unlock') {
		// Hide loader
		$('#' + statBarId).find('img').hide();

		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).append(prg);	
	} else if (cmd == 'rmvm') {
		// Get data table
		var dTable = getNodesDataTable();
		var failed = false;

		// Hide loader
		$('#' + statBarId).find('img').hide();

		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).append(prg);	
		
		// If there was an error
		// Do not continue
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
	var dTable = getNodesDataTable();

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

	// Disable all fields
	$('#' + tabId + ' input').attr('readonly', 'readonly');
	$('#' + tabId + ' input').css( {
		'background-color' : '#F2F2F2'
	});

	$('#' + tabId + ' textarea').attr('readonly', 'readonly');
	$('#' + tabId + ' textarea').css( {
		'background-color' : '#F2F2F2'
	});

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
 * Get the hardware management of a given node
 * 
 * @param node
 *            The node
 * @return The hardware management of the node
 */
function getNodeMgt(node) {
	// Get the row, 
	// may be node contain special char(such as '.' '#'),so we can not use $('#') directly
	var row = $('[id=' + node + ']').parent().parent();

	// Search for the mgt column
	var mgtCol = row.parent().parent().find('th:contains("mgt")');
	// Get the mgt column index
	var mgtIndex = mgtCol.index();

	// Get the mgt for the given node
	var mgt = row.find('td:eq(' + mgtIndex + ')');

	return mgt.text();
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
 * 				The datatable ID
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

function getColNum(colName){
	var temp;
	var columns = $('table thead tr').children();
	
	for(temp = 1; temp < columns.length; temp++){
		if (colName == columns[temp].innerHTML){
			return temp;
		}
	}
	return -1;
}

function getRowNum(nodeName){
	// Get datatable
	var dTable = getNodesDataTable();
	
	// Get all data from datatable
	var data = dTable.fnGetData();
	
	var temp;
	var nodeItem;
			
	for(temp = 0; temp < data.length; temp++){
		nodeItem = data[temp][1];
		if(nodeItem.indexOf('>' + nodeName + '<') > -1){
			return temp;
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