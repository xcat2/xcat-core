/**
 * Global variables
 */
var gangliaTableId = 'nodesDatatable';
var gangliaNodesList;

/**
 * Load Ganglia monitoring tool
 * 
 * @return Nothing
 */
function loadGangliaMon() {
	// Get Ganglia tab
	var gangliaTab = $('#gangliamon');

	// Check whether Ganglia RPMs are installed on the xCAT MN
	$.ajax({
		url : 'lib/systemcmd.php',
		dataType : 'json',
		data : {
			cmd : 'rpm -q rrdtool ganglia-gmetad ganglia-gmond ganglia-web'
		},

		success : checkGangliaRPMs
	});

	// Create groups and nodes DIV
	var groups = $('<div id="groups"></div>');
	var nodes = $('<div id="nodes"></div>');
	gangliaTab.append(groups);
	gangliaTab.append(nodes);

	// Create info bar
	var info = createInfoBar('Select a group to view its nodes');
	nodes.append(info);

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

		success : loadGroups4Ganglia
	});

	return;
}

/**
 * Check whether Ganglia RPMs are installed
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function checkGangliaRPMs(data) {
	var gangliaTab = $('#gangliamon');

	// Get the list of Ganglia RPMs installed
	var status = data.rsp.split(/\n/);
	var gangliaRPMs = [ "rrdtool", "ganglia-gmetad", "ganglia-gmond", "ganglia-web" ];
	var warningMsg = 'Before continuing, please install the following packages: ';
	var missingRPMs = false;
	for ( var i in status) {
		if (status[i].indexOf("not installed") > -1) {
			warningMsg += gangliaRPMs[i] + ' ';
			missingRPMs = true;
		}
	}

	// Append Ganglia PDF
	if (missingRPMs) {
		warningMsg += ". Refer to <a href='http://xcat.svn.sourceforge.net/viewvc/xcat/xcat-core/trunk/xCAT-client/share/doc/xCAT2-Monitoring.pdf'>xCAT2-Monitoring.pdf</a> for more information.";

		var warningBar = createWarnBar(warningMsg);
		warningBar.css('margin-bottom', '10px');
		warningBar.prependTo(gangliaTab);
	} else {
		// Check if ganglia is running on the xCAT MN
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'monls',
				tgt : '',
				args : 'gangliamon',
				msg : ''
			},

			/**
			 * Append warning message
			 * 
			 * @param data
			 *            Data returned from HTTP request
			 * @return Nothing
			 */
			success : function(data) {
				if (data.rsp[0].indexOf("not-monitored") > -1) {
					// Create link to start Ganglia
					var startLnk = $('<a href="#">Click here</a>');
					startLnk.css( {
						'color' : 'blue',
						'text-decoration' : 'none'
					});
					startLnk.click(function() {
						// Turn on Ganglia for all nodes
						monitorNode('', 'on');
					});
		
					// Create warning bar
					var warningBar = $('<div class="ui-state-error ui-corner-all"></div>');
					var msg = $('<p></p>');
					msg.append('<span class="ui-icon ui-icon-alert"></span>');
					msg.append('Please start Ganglia Monitoring on xCAT. ');
					msg.append(startLnk);
					msg.append(' to start Ganglia Monitoring.');
					warningBar.append(msg);
					warningBar.css('margin-bottom', '10px');
		
					// If there are any warning messages, append this warning after it
					var curWarnings = $('#gangliamon').find('.ui-state-error');
					var gangliaTab = $('#gangliamon');
					if (curWarnings.length) {
						curWarnings.after(warningBar);
					} else {
						warningBar.prependTo(gangliaTab);
					}
				}
			}
		});
	}
	return;
}

/**
 * Load groups
 * 
 * @param data
 *            Data returned from HTTP request
 * @return
 */
function loadGroups4Ganglia(data) {
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
		core : {
			"initially_open" : [ "root" ]
		},
		themes : {
			"theme" : "default",
			"dots" : false, // No dots
			"icons" : false // No icons
		}
	});

	// Load nodes onclick
	$('#groups').bind('select_node.jstree', function(event, data) {
			// If there are subgroups, remove them
			data.rslt.obj.children('ul').remove();
			var thisGroup = jQuery.trim(data.rslt.obj.text());
			if (thisGroup) {
				// Clear nodes division
			$('#nodes').children().remove();

			// Create link to Ganglia
			var gangliaLnk = $('<a href="#">click here</a>');
			gangliaLnk.css( {
				'color' : 'blue',
				'text-decoration' : 'none'
			});
			gangliaLnk.click(function() {
				// Open a new window for Ganglia
				window.open('../ganglia/');
			});

			// Create info bar
			var info = $('<div class="ui-state-highlight ui-corner-all"></div>');
			info.append('<span class="ui-icon ui-icon-info" style="display: inline-block; margin: 10px 5px;"></span>');
			var msg = $('<p style="display: inline-block; width: 95%;"></p>');
			msg.append('Review the nodes that are monitored by Ganglia. Install Ganglia onto a node you want to monitor by selecting it and clicking on Install. Turn on Ganglia monitoring for a node by selecting it and clicking on Monitor. If you are satisfied with the nodes you want to monitor, ');
			msg.append(gangliaLnk);
			msg.append(' to open the Ganglia page.');
			info.append(msg);
			info.css('margin-bottom', '10px');
			$('#nodes').append(info);

			// Create loader
			var loader = $('<center></center>').append(createLoader());

			// Create a tab for this group
			var tab = new Tab();
			setNodesTab(tab);
			tab.init();
			$('#nodes').append(tab.object());
			tab.add('nodesTab', 'Nodes', loader, false);

			// To improve performance, get all nodes within selected group
			// Get node definitions only for first 50 nodes
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'nodels',
					tgt : thisGroup,
					args : '',
					msg : thisGroup
				},

				/**
				 * Get node definitions for first 50 nodes
				 * 
				 * @param data
				 *            Data returned from HTTP request
				 * @return Nothing
				 */
				success : function(data) {
					var rsp = data.rsp;
					var group = data.msg;
					
					// Save nodes in a list so it can be accessed later
					nodesList = new Array();
					for (var i in rsp) {
						if (rsp[i][0]) {
							nodesList.push(rsp[i][0]);
						}
					}
										
					// Sort nodes list
					nodesList.sort();
					
					// Get first 50 nodes
					var nodes = '';
					for (var i = 0; i < nodesList.length; i++) {
						if (i > 49) {
							break;
						}
						
						nodes += nodesList[i] + ',';						
					}
								
					// Remove last comma
					nodes = nodes.substring(0, nodes.length-1);
					
					// Get nodes definitions
					$.ajax( {
						url : 'lib/cmd.php',
						dataType : 'json',
						data : {
							cmd : 'lsdef',
							tgt : '',
							args : nodes,
							msg : group
						},

						success : loadNodes4Ganglia
					});
				}
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
		} // End of if (thisGroup)
	});
}

/**
 * Load nodes belonging to a given group
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function loadNodes4Ganglia(data) {
	// Data returned
	var rsp = data.rsp;
	// Group name
	var group = data.msg;
	// Node attributes hash
	var attrs = new Object();
	// Node attributes
	var headers = new Object();

	// Variable to send command and request node status
	var getNodeStatus = true;
	
	var node, args;
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
		args = rsp[i].split('=', 2);
		var key = jQuery.trim(args[0]);
		var val = jQuery.trim(rsp[i].substring(rsp[i].indexOf('=') + 1, rsp[i].length));
		
		// Create a hash table
		attrs[node][key] = val;
		headers[key] = 1;
		
		// If the node status is available
		if (key == 'status') {
			// Do not send command to request node status
			getNodeStatus = false;
		}
	}
	
	// Add nodes that are not in data returned
	for (var i in nodesList) {
		if (!attrs[nodesList[i]]) {
			// Create attributes list and save node name
			attrs[nodesList[i]] = new Object();
			attrs[nodesList[i]]['node'] = nodesList[i];
		}
	}
	
	// Sort headers
	var sorted = new Array();
	for ( var key in headers) {
		// Do not put comments and status in
		if (key != 'usercomment' && key != 'status' && key.indexOf('statustime') < 0) {
			sorted.push(key);
		}
	}
	sorted.sort();

	// Add column for check box, node, ping, and power
	sorted.unshift('<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">', 
		'node', 
		'<span><a>status</a></span><img src="images/loader.gif"></img>',
		'<span><a>power</a></span><img src="images/loader.gif" style="display: none;"></img>', 
		'<span><a>ganglia</a></span><img src="images/loader.gif" style="display: none;"></img>');

	// Create a datatable
	var gangliaTable = new DataTable(gangliaTableId);
	gangliaTable.init(sorted);

	// Go through each node
	for ( var node in attrs) {
		// Create a row
		var row = new Array();

		// Create a check box, node link, and get node status
		var checkBx = '<input type="checkbox" name="' + node + '"/>';
		var nodeLink = $('<a class="node" id="' + node + '">' + node + '</a>').bind('click', loadNode);
		
		// If there is no status attribute for the node, do not try to access hash table
		// Else the code will break
		var status = '';
		if (attrs[node]['status']) {
			status = attrs[node]['status'].replace('sshd', 'ping');
		}

		// Push in checkbox, node, status, and power
		row.push(checkBx, nodeLink, status, '', '');

		// Go through each header
		for ( var i = 5; i < sorted.length; i++) {
			// Add the node attributes to the row
			var key = sorted[i];
			
			// Do not put comments and status in
			if (key != 'usercomment' && key != 'status' && key.indexOf('statustime') < 0) {
    			var val = attrs[node][key];
    			if (val) {
    				row.push(val);
    			} else {
    				row.push('');
    			}
			}
		}

		// Add the row to the table
		gangliaTable.add(row);
	}
	
	// Clear the tab before inserting the table
	$('#nodesTab').children().remove();

	// Create action bar
	var actionBar = $('<div class="actionBar"></div>');

	/**
	 * The following actions are available to perform against a given node:
	 * power and monitor
	 */

	/*
	 * Power
	 */
	var powerLnk = $('<a>Power</a>');

	// Power on
	var powerOnLnk = $('<a>Power on</a>');
	powerOnLnk.click(function() {
		var tgtNodes = getNodesChecked(gangliaTableId);
		if (tgtNodes) {
			powerNode(tgtNodes, 'on');
		}
	});

	// Power off
	var powerOffLnk = $('<a>Power off</a>');
	powerOffLnk.click(function() {
		var tgtNodes = getNodesChecked(gangliaTableId);
		if (tgtNodes) {
			powerNode(tgtNodes, 'off');
		}
	});

	// Power actions
	var powerActions = [ powerOnLnk, powerOffLnk ];
	var powerActionMenu = createMenu(powerActions);

	/*
	 * Monitor
	 */
	var monitorLnk = $('<a>Monitor</a>');

	// Turn monitoring on
	var monitorOnLnk = $('<a>Monitor on</a>');
	monitorOnLnk.click(function() {
		var tgtNodes = getNodesChecked(gangliaTableId);
		if (tgtNodes) {
			monitorNode(tgtNodes, 'on');
		}
	});

	// Turn monitoring off
	var monitorOffLnk = $('<a>Monitor off</a>');
	monitorOffLnk.click(function() {
		var tgtNodes = getNodesChecked(gangliaTableId);
		if (tgtNodes) {
			monitorNode(tgtNodes, 'off');
		}
	});
	
	// Install Ganglia
	var installLnk = $('<a>Install</a>');
	installLnk.click(function() {
		var tgtNodes = getNodesChecked(gangliaTableId);
		if (tgtNodes) {
			installGanglia(tgtNodes);
		}
	});

	// Power actions
	var monitorActions = [ monitorOnLnk, monitorOffLnk ];
	var monitorActionMenu = createMenu(monitorActions);

	// Create an action menu
	var actionsDIV = $('<div></div>');
	var actions = [ [ powerLnk, powerActionMenu ], [ monitorLnk, monitorActionMenu ], installLnk ];
	var actionMenu = createMenu(actions);
	actionMenu.superfish();
	actionsDIV.append(actionMenu);
	actionBar.append(actionsDIV);
	$('#nodesTab').append(actionBar);

	// Insert table
	$('#nodesTab').append(gangliaTable.object());

	// Turn table into a datatable
	var gangliaDataTable = $('#' + gangliaTableId).dataTable({
		'iDisplayLength': 50
	});
	
	// Filter table when enter key is pressed
	$('#' + gangliaTableId + '_filter input').unbind();
	$('#' + gangliaTableId + '_filter input').bind('keyup', function(e){
		if (e.keyCode == 13) {
			var table = $('#' + gangliaTableId).dataTable();
			table.fnFilter($(this).val());
			
			// If there are nodes found, get the node attributes
			if (!$('#' + gangliaTableId + ' .dataTables_empty').length) {
				getNodeAttrs4Ganglia(group);
			}
		}
	});
	
	// Load node definitions when next or previous buttons are clicked
	$('#' + gangliaTableId + '_next, #' + gangliaTableId + '_previous').click(function() {
		getNodeAttrs4Ganglia(group);
	});

	// Do not sort ping, power, and comment column
	var cols = $('#' + gangliaTableId + ' thead tr th').click(function() {		
		getNodeAttrs4Ganglia(group);
	});
	var pingCol = $('#' + gangliaTableId + ' thead tr th').eq(2);
	var powerCol = $('#' + gangliaTableId + ' thead tr th').eq(3);
	var gangliaCol = $('#' + gangliaTableId + ' thead tr th').eq(4);
	pingCol.unbind('click');
	powerCol.unbind('click');
	gangliaCol.unbind('click');

	// Create enough space for loader to be displayed
	var style = {'min-width': '60px', 'text-align': 'center'};
	$('#' + gangliaTableId + ' tbody tr td:nth-child(3)').css(style);
	$('#' + gangliaTableId + ' tbody tr td:nth-child(4)').css(style);
	$('#' + gangliaTableId + ' tbody tr td:nth-child(5)').css(style);

	// Instead refresh the ping status and power status
	pingCol.find('span a').bind('click', function(event) {
		refreshNodeStatus(group, gangliaTableId);
	});
	powerCol.find('span a').bind('click', function(event) {
		refreshPowerStatus(group, gangliaTableId);
	});
	gangliaCol.find('span a').bind('click', function(event) {
		refreshGangliaStatus(group);
	});
	
	// Create tooltip for status 
	var tooltipConf = {
		position: "center right",
		offset: [-2, 10],
		effect: "fade",	
		opacity: 0.8,
		relative: true,
		predelay: 800
	};
	
	var pingTip = createStatusToolTip();
	pingCol.find('span').append(pingTip);
	pingCol.find('span a').tooltip(tooltipConf);
	
	// Create tooltip for power 
	var powerTip = createPowerToolTip();
	powerCol.find('span').append(powerTip);
	powerCol.find('span a').tooltip(tooltipConf);
	
	// Create tooltip for ganglia 
	var gangliaTip = createGangliaToolTip();
	gangliaCol.find('span').append(gangliaTip);
	gangliaCol.find('span a').tooltip(tooltipConf);

	/**
	 * Get node and ganglia status
	 */
	
	// If request to get node status is made
	if (getNodeStatus) {
    	// Get the node status
    	$.ajax( {
    		url : 'lib/cmd.php',
    		dataType : 'json',
    		data : {
    			cmd : 'nodestat',
    			tgt : group,
    			args : '',
    			msg : ''
    		},
    
    		success : loadNodeStatus
    	});
	} else {
		// Hide status loader
		var statCol = $('#' + gangliaTableId + ' thead tr th').eq(2);
		statCol.find('img').hide();
	}

	// Get the status of Ganglia
	var nodes = getNodesShown(gangliaTableId);
	$.ajax( {
		url : 'lib/cmd.php',
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
 *            Data returned from HTTP request
 * @return Nothing
 */
function loadGangliaStatus(data) {
	// Get datatable
	var datatable = $('#' + gangliaTableId).dataTable();
	var ganglia = data.rsp;
	var rowNum, node, status, args;

	for ( var i in ganglia) {
		// ganglia[0] = nodeName and ganglia[1] = state
		node = jQuery.trim(ganglia[i][0]);
		status = jQuery.trim(ganglia[i][1]);

		// Get the row containing the node
		rowNum = findRow(node, '#' + gangliaTableId, 1);

		// Update the power status column
		datatable.fnUpdate(status, rowNum, 4);
	}

	// Hide Ganglia loader
	var gangliaCol = $('#' + gangliaTableId + ' thead tr th').eq(4);
	gangliaCol.find('img').hide();
}

/**
 * Refresh the status of Ganglia for each node
 * 
 * @param group
 *            Group name
 * @return Nothing
 */
function refreshGangliaStatus(group) {
	// Show ganglia loader
	var gangliaCol = $('#' + gangliaTableId + ' thead tr th').eq(4);
	gangliaCol.find('img').show();
	
	// Get power status for nodes shown
	var nodes = getNodesShown(gangliaTableId);

	// Get the status of Ganglia
	$.ajax( {
		url : 'lib/cmd.php',
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
		var warningBar = $('#gangliamon').find('.ui-state-error p');
		if (warningBar.length) {
			warningBar.append(gangliaLoader);
		}

		if (node) {
			// Check if ganglia RPMs are installed
			$.ajax( {
				url : 'lib/cmd.php',
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
						warningBar.prependTo($('#nodes'));
					} else {
						$.ajax( {
							url : 'lib/cmd.php',
							dataType : 'json',
							data : {
								cmd : 'webrun',
								tgt : '',
								args : 'gangliastart;' + data.msg,
								msg : ''
							},

							success : function(data) {
								// Remove any warnings
								$('#nodes').find('.ui-state-error').remove();
								$('#gangliamon').find('.ui-state-error').remove();
							}
						});
					} // End of if (warn)
				} // End of function(data)
			});
		} else {
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'webrun',
					tgt : '',
					args : 'gangliastart',
					msg : ''
				},

				success : function(data) {
					// Remove any warnings
					$('#gangliamon').find('.ui-state-error').remove();
				}
			});
		} // End of if (node)
	} else {
		var args;
		if (node) {
			args = 'gangliastop;' + node;
		} else {
			args = 'gangliastop';
		}

		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'webrun',
				tgt : '',
				args : args,
				msg : ''
			},

			success : function(data) {
				// Do nothing
			}
		});
	}
}

/**
 * Get attributes for nodes not yet initialized
 * 
 * @param group
 *            Group name
 * @return Nothing
 */
function getNodeAttrs4Ganglia(group) {	
	// Get datatable headers and rows
	var headers = $('#' + gangliaTableId + ' thead tr th');
	var nodes = $('#' + gangliaTableId + ' tbody tr');
	
	// Find group column
	var head, groupsCol;
	for (var i = 0; i < headers.length; i++) {
		head = headers.eq(i).html();
		if (head == 'groups') {
			groupsCol = i;
			break;
		}
	}

	// Check if groups definition is set
	var node, cols;
	var tgtNodes = '';
	for (var i = 0; i < nodes.length; i++) {
		cols = nodes.eq(i).find('td');
		if (!cols.eq(groupsCol).html()) {
			node = cols.eq(1).text();
			tgtNodes += node + ',';
		}
	}
		
	// If there are node definitions to load
	if (tgtNodes) {
		// Remove last comma
		tgtNodes = tgtNodes.substring(0, tgtNodes.length-1);
				
		// Get node definitions
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'lsdef',
				tgt : '',
				args : tgtNodes,
				msg : group
			},
	
			success : addNodes2GangliaTable
		});
		
		// Create dialog to indicate table is updating
		var update = $('<div id="updatingDialog" class="ui-state-highlight ui-corner-all">' 
				+ '<p><span class="ui-icon ui-icon-info"></span> Updating table <img src="images/loader.gif"/></p>'
			+'</div>');
		update.dialog({
			modal: true,
			width: 300,
			position: 'center'
		});
	}
}

/**
 * Add nodes to datatable
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function addNodes2GangliaTable(data) {
	// Data returned
	var rsp = data.rsp;
	// Group name
	var group = data.msg;
	// Hash of node attributes
	var attrs = new Object();
	// Node attributes
	var headers = $('#' + gangliaTableId + ' thead tr th');

	// Variable to send command and request node status
	var getNodeStatus = true;
	
	// Go through each attribute
	var node, args;
	for (var i in rsp) {
		// Get node name
		if (rsp[i].indexOf('Object name:') > -1) {
			var temp = rsp[i].split(': ');
			node = jQuery.trim(temp[1]);

			// Create a hash for node attributes
			attrs[node] = new Object();
			i++;
		}

		// Get key and value
		args = rsp[i].split('=', 2);
		var key = jQuery.trim(args[0]);
		var val = jQuery.trim(rsp[i].substring(rsp[i].indexOf('=') + 1, rsp[i].length));

		// Create a hash table
		attrs[node][key] = val;
		
		// If node status is available
		if (key == 'status') {
			// Do not request node status
			getNodeStatus = false;
		}
	}

	// Set the first four headers
	var headersCol = new Object();
	headersCol['node'] = 1;
	headersCol['status'] = 2;
	headersCol['power'] = 3;
	headersCol['ganglia'] = 4;
	
	// Go through each header
	for (var i = 5; i < headers.length; i++) {
		// Get the column index
		headersCol[headers.eq(i).html()] = i;
	}

	// Go through each node
	var datatable = $('#' + gangliaTableId).dataTable();
	var rows = datatable.fnGetData();
	for (var node in attrs) {
		// Get row containing node
		var nodeRowPos;
		for (var i in rows) {
			// If column contains node
			if (rows[i][1].indexOf('>' + node + '<') > -1) {
				nodeRowPos = i;
				break;
			}
		}

		// Get node status
		var status = '';
		if (attrs[node]['status']){
			status = attrs[node]['status'].replace('sshd', 'ping');
		}
		
		rows[nodeRowPos][headersCol['status']] = status;

		// Go through each header
		for (var key in headersCol) {
			// Do not put comments and status in twice
			if (key != 'usercomment' && key != 'status' && key.indexOf('statustime') < 0) {
    			var val = attrs[node][key];
    			if (val) {
    				rows[nodeRowPos][headersCol[key]] = val;
    			}
			}
		}
		
		// Update row
		datatable.fnUpdate(rows[nodeRowPos], nodeRowPos, 0, false);
	}

	// Enable node link
	$('.node').bind('click', loadNode);

	// Close dialog for updating table
	$('.ui-dialog-content').dialog('close');
	
	// If request to get node status is made
	if (getNodeStatus) {
    	// Get the node status
    	$.ajax( {
    		url : 'lib/cmd.php',
    		dataType : 'json',
    		data : {
    			cmd : 'nodestat',
    			tgt : group,
    			args : '',
    			msg : ''
    		},
    
    		success : loadNodeStatus
    	});
	} else {
		// Hide status loader
		var statCol = $('#' + gangliaTableId + ' thead tr th').eq(2);
		statCol.find('img').hide();
	}

	// Get the status of Ganglia
	var nodes = getNodesShown(gangliaTableId);
	$.ajax( {
		url : 'lib/cmd.php',
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
 * Create a tool tip for ganglia status
 * 
 * @return Tool tip
 */
function createGangliaToolTip() {
	// Create tooltip container
	var toolTip = $('<div class="tooltip">Click here to refresh the Ganglia status</div>').css({
		'width': '150px'
	});	
	return toolTip;
}

/**
 * Install Ganglia on a given node
 * 
 * @param node
 *            Node to install Ganglia on
 * @return Nothing
 */
function installGanglia(node) {
	var iframe = createIFrame('lib/cmd.php?cmd=webrun&tgt=&args=installganglia;' + node + '&msg=' + node + '&opts=flush');
	iframe.prependTo($('#gangliamon #nodes'));
}