/**
 * Load Ganglia monitoring tool
 * 
 * @return Nothing
 */
function loadGangliaMon() {
	// Get Ganglia tab
	var gangliaTab = $('#gangliamon');

	// Check whether Ganglia RPMs are installed on the xCAT MN
	$.ajax( {
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
	$('#groups')
		.bind('select_node.jstree', function(event, data) {
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
			var msg = $('<p></p>');
			msg.append('<span class="ui-icon ui-icon-info"></span>');
			msg
				.append('Review the nodes that are monitored by Ganglia.  You can turn on Ganglia monitoring on a node by selecting it and clicking on Monitor. If you are satisfied with the nodes you want to monitor, ');
			msg.append(gangliaLnk);
			msg.append(' to open Ganglia page.');
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

				success : loadNodes4Ganglia
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
	}   );
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
	sorted.unshift('<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">', 'node', '<a>ping</a><img src="images/loader.gif"></img>',
		'<a>power</a><img src="images/loader.gif"></img>', '<a>ganglia</a><img src="images/loader.gif"></img>');

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
		row.push(checkBx, nodeLink, '', '', '');

		// Go through each header
		for ( var i = 5; i < sorted.length; i++) {
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
	 * power and monitor
	 */

	/*
	 * Power
	 */
	var powerLnk = $('<a>Power</a>');

	// Power on
	var powerOnLnk = $('<a>Power on</a>');
	powerOnLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			powerNode(tgtNodes, 'on');
		}
	});

	// Power off
	var powerOffLnk = $('<a>Power off</a>');
	powerOffLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
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
	monitorLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {

		}
	});

	// Turn monitoring on
	var monitorOnLnk = $('<a>Monitor on</a>');
	monitorOnLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			monitorNode(tgtNodes, 'on');
		}
	});

	// Turn monitoring off
	var monitorOffLnk = $('<a>Monitor off</a>');
	monitorOffLnk.bind('click', function(event) {
		var tgtNodes = getNodesChecked('nodesDataTable');
		if (tgtNodes) {
			monitorNode(tgtNodes, 'off');
		}
	});

	// Power actions
	var monitorActions = [ monitorOnLnk, monitorOffLnk ];
	var monitorActionMenu = createMenu(monitorActions);

	/**
	 * Create an action menu
	 */
	var actionsDIV = $('<div></div>');
	var actions = [ [ powerLnk, powerActionMenu ], [ monitorLnk, monitorActionMenu ] ];
	var actionMenu = createMenu(actions);
	actionMenu.superfish();
	actionsDIV.append(actionMenu);
	actionBar.append(actionsDIV);
	$('#nodesTab').append(actionBar);

	// Insert table
	$('#nodesTab').append(dTable.object());

	// Turn table into a datatable
	var myDataTable = $('#nodesDataTable').dataTable();

	// Do not sort ping and power column
	var pingCol = $('#nodesDataTable thead tr th').eq(2);
	var powerCol = $('#nodesDataTable thead tr th').eq(3);
	var gangliaCol = $('#nodesDataTable thead tr th').eq(4);
	pingCol.unbind('click');
	powerCol.unbind('click');
	gangliaCol.unbind('click');

	// Create enough space for loader to be displayed
	$('#nodesDataTable tbody tr td:nth-child(3)').css('min-width', '60px');
	$('#nodesDataTable tbody tr td:nth-child(4)').css('min-width', '60px');
	$('#nodesDataTable tbody tr td:nth-child(5)').css('min-width', '80px');

	// Instead refresh the ping status and power status
	pingCol.bind('click', function(event) {
		refreshPingStatus(group);
	});

	powerCol.bind('click', function(event) {
		refreshPowerStatus(group);
	});

	gangliaCol.bind('click', function(event) {
		refreshGangliaStatus(group);
	});

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

	// Get the status of Ganglia
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'gangliastatus;' + group,
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
	var dTable = $('#nodesDataTable').dataTable();
	var ganglia = data.rsp;
	var rowNum, node, status, args;

	for ( var i in ganglia) {
		// ganglia[0] = nodeName and ganglia[1] = state
		node = jQuery.trim(ganglia[i][0]);
		status = jQuery.trim(ganglia[i][1]);

		// Get the row containing the node
		rowNum = getRowNum(node);

		// Update the power status column
		dTable.fnUpdate(status, rowNum, 4);
	}

	// Hide Ganglia loader
	var gangliaCol = $('#nodesDataTable thead tr th').eq(4);
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
	var gangliaCol = $('#nodesDataTable thead tr th').eq(4);
	gangliaCol.find('img').show();

	// Get the status of Ganglia
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : 'gangliastatus;' + group,
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
	var args;

	if (monitor == 'on') {
		// Append loader to warning bar
		var gangliaLoader = createLoader('');
		var warningBar = $('#gangliamon').find('.ui-state-error p');
		if (warningBar.length) {
			warningBar.append(gangliaLoader);
		}

		if (node) {
			args = 'gangliastart;' + node;
		} else {
			args = 'gangliastart';
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
				// Remove any warnings
				$('#gangliamon').find('.ui-state-error').remove();
			}
		});
	} else {
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