/**
 * Global variables
 */
var diskDatatable; // zVM datatable containing disks
var networkDatatable; // zVM datatable containing networks

/**
 * Get the disk datatable
 * 
 * @param Nothing
 * @return Data table object
 */
function getDiskDataTable() {
	return diskDatatable;
}

/**
 * Set the disk datatable
 * 
 * @param table
 *            Data table object
 * @return Nothing
 */
function setDiskDataTable(table) {
	diskDatatable = table;
}

/**
 * Get the network datatable
 * 
 * @param Nothing
 * @return Data table object
 */
function getNetworkDataTable() {
	return networkDatatable;
}

/**
 * Set the network datatable
 * 
 * @param table
 *            Data table object
 * @return Nothing
 */
function setNetworkDataTable(table) {
	networkDatatable = table;
}

/**
 * Load user entry of a given node
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function loadUserEntry(data) {
	var args = data.msg.split(';');

	// Get tab ID
	var ueDivId = args[0].replace('out=', '');
	// Get node
	var node = args[1].replace('node=', '');
	// Get user directory entry
	var userEntry = data.rsp[0].split(node + ':');

	// Remove loader
	var loaderId = node + 'TabLoader';
	$('#' + loaderId).remove();

	var toggleLinkId = node + 'ToggleLink';
	$('#' + toggleLinkId).click(function() {
		// Get text within this link
		var lnkText = $(this).text();

		// Toggle user entry division
		$('#' + node + 'UserEntry').toggle();
		// Toggle inventory division
		$('#' + node + 'Inventory').toggle();

		// Change text
		if (lnkText == 'Show directory entry') {
			$(this).text('Show inventory');
		} else {
			$(this).text('Show directory entry');
		}
	});

	// Put user entry into a list
	var fieldSet = $('<fieldset></fieldset>');
	var legend = $('<legend>Directory Entry</legend>');
	fieldSet.append(legend);

	var txtArea = $('<textarea></textarea>');
	for ( var i = 1; i < userEntry.length; i++) {
		userEntry[i] = jQuery.trim(userEntry[i]);
		txtArea.append(userEntry[i]);

		if (i < userEntry.length) {
			txtArea.append('\n');
		}
	}
	txtArea.attr('readonly', 'readonly');
	fieldSet.append(txtArea);

	/**
	 * Edit user entry
	 */
	txtArea.bind('dblclick', function(event) {
		txtArea.attr('readonly', '');
		txtArea.css( {
			'border-width' : '1px'
		});

		saveBtn.show();
		cancelBtn.show();
	});
	
	/**
	 * Save
	 */
	var saveBtn = createButton('Save');
	saveBtn.css('display', 'inline-table');
	saveBtn.hide();
	saveBtn.bind('click', function(event) {
		// Show loader
		var statusId = node + 'StatusBar';
		var statusBarLoaderId = node + 'StatusBarLoader';
		$('#' + statusBarLoaderId).show();
		$('#' + statusId).show();

		// Replace user entry
		var newUserEntry = jQuery.trim(txtArea.val()) + '\n';

		// Replace user entry
		$.ajax( {
			url : 'lib/zCmd.php',
			dataType : 'json',
			data : {
				cmd : 'chvm',
				tgt : node,
				args : '--replacevs',
				att : newUserEntry,
				msg : node
			},

			success : updateZNodeStatus
		});

		// Increment node process and save it in a cookie
		incrementNodeProcess(node);

		txtArea.attr('readonly', 'readonly');
		txtArea.css( {
			'border-width' : '0px'
		});

		// Disable save button
		$(this).hide();
		cancelBtn.hide();
	});

	/**
	 * Cancel
	 */
	var cancelBtn = createButton('Cancel');
	cancelBtn.css('display', 'inline-table');
	cancelBtn.hide();
	cancelBtn.bind('click', function(event) {
		txtArea.attr('readonly', 'readonly');
		txtArea.css( {
			'border-width' : '0px'
		});

		cancelBtn.hide();
		saveBtn.hide();
	});

	// Create info bar
	var infoBar = createInfoBar('Double click on the directory entry to edit');

	// Append user entry into division
	$('#' + ueDivId).append(infoBar);
	$('#' + ueDivId).append(fieldSet);
	$('#' + ueDivId).append(saveBtn);
	$('#' + ueDivId).append(cancelBtn);
}

/**
 * Increment number of processes running against a node
 * 
 * @param node
 *            Node to increment running processes
 * @return Nothing
 */
function incrementNodeProcess(node) {
	// Get current processes
	var procs = $.cookie(node + 'Processes');
	if (procs) {
		// One more process
		procs = parseInt(procs) + 1;
		$.cookie(node + 'Processes', procs);
	} else {
		$.cookie(node + 'Processes', 1);
	}
}

/**
 * Update provision new node status
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function updateZProvisionNewStatus(data) {
	// Get ajax response
	var rsp = data.rsp;
	var args = data.msg.split(';');

	// Get command invoked
	var cmd = args[0].replace('cmd=', '');
	// Get output ID
	var out2Id = args[1].replace('out=', '');
	
	// Get status bar ID
	var statBarId = 'zProvisionStatBar' + out2Id;
	// Get provision tab ID
	var tabId = 'zvmProvisionTab' + out2Id;
	// Get loader ID
	var loaderId = 'zProvisionLoader' + out2Id;

	// Get node name
	var node = $('#' + tabId + ' input[name=nodeName]').val();

	/**
	 * (2) Update /etc/hosts
	 */
	if (cmd == 'nodeadd') {
		// If there was an error, do not continue
		if (rsp.length) {
			$('#' + loaderId).hide();
			$('#' + statBarId).append('<p>(Error) Failed to create node definition</p>');
		} else {
			$('#' + statBarId).append('<p>Node definition created for ' + node + '</p>');
    		$.ajax( {
    			url : 'lib/cmd.php',
    			dataType : 'json',
    			data : {
    				cmd : 'makehosts',
    				tgt : '',
    				args : '',
    				msg : 'cmd=makehosts;out=' + out2Id
    			},
    
    			success : updateZProvisionNewStatus
    		});
		}
	}

	/**
	 * (3) Update DNS
	 */
	else if (cmd == 'makehosts') {
		// If there was an error, do not continue
		if (rsp.length) {
			$('#' + loaderId).hide();
			$('#' + statBarId).append('<p>(Error) Failed to update /etc/hosts</p>');
		} else {
			$('#' + statBarId).append('<p>/etc/hosts updated</p>');
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'makedns',
					tgt : '',
					args : '',
					msg : 'cmd=makedns;out=' + out2Id
				},

				success : updateZProvisionNewStatus
			});
		}		
	}

	/**
	 * (4) Create user entry
	 */
	else if (cmd == 'makedns') {		
		// Reset number of tries
		$.cookie('tries4' + tabId, 0);

		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).append(prg);

		// Get user entry
		var userEntry = $('#' + tabId + ' textarea').val();
		
		// Create user entry
		$.ajax( {
			url : 'lib/zCmd.php',
			dataType : 'json',
			data : {
				cmd : 'mkvm',
				tgt : node,
				args : '',
				att : userEntry,
				msg : 'cmd=mkvm;out=' + out2Id
			},

			success : updateZProvisionNewStatus
		});
	}

	/**
	 * (5) Add disk
	 */
	else if (cmd == 'mkvm') {		
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).append(prg);

		// If there was an error, do not continue
		if (prg.html().indexOf('Error') > -1) {
			// Try again
			var tries = parseInt($.cookie('tries4' + tabId));
			if (tries < 2) {
				$('#' + statBarId).append('<p>Trying again...</p>');
				tries = tries + 1;

				// One more try
				$.cookie('tries4' + tabId, tries);

				// Get user entry
				var userEntry = $('#' + tabId + ' textarea').val();
				// Create user entry
				$.ajax( {
					url : 'lib/zCmd.php',
					dataType : 'json',
					data : {
						cmd : 'mkvm',
						tgt : node,
						args : '',
						att : userEntry,
						msg : 'cmd=mkvm;out=' + out2Id
					},

					success : updateZProvisionNewStatus
				});
			} else {
				$('#' + loaderId).hide();
			}
		} else {
			// Reset number of tries
			$.cookie('tries4' + tabId, 0);

			// Set cookie for number of disks
			var diskRows = $('#' + tabId + ' table:visible tr');
			$.cookie('zProvisionDisks2Add' + out2Id, diskRows.length);
			if (diskRows.length > 0) {
				for ( var i = 0; i < diskRows.length; i++) {
					// Get disk type, address, size, mode, pool, and password
					var diskArgs = diskRows.eq(i).find('td');
					var type = diskArgs.eq(1).find('select').val();
					var address = diskArgs.eq(2).find('input').val();
					var size = diskArgs.eq(3).find('input').val();
					var mode = diskArgs.eq(4).find('select').val();
					var pool = diskArgs.eq(5).find('input').val();
					var password = diskArgs.eq(6).find('input').val();
					
					// Create ajax arguments
					var args = '';
					if (type == '3390') {
						args = '--add' + type + ';' + pool + ';' + address
							+ ';' + size + ';' + mode + ';' + password + ';'
							+ password + ';' + password;
					} else if (type == '9336') {
						var blkSize = '512';
						args = '--add' + type + ';' + pool + ';' + address + ';' 
							+ blkSize + ';' + size + ';' + mode + ';' + password + ';'
							+ password + ';' + password;
					}

					// Add disk
					$.ajax( {
						url : 'lib/cmd.php',
						dataType : 'json',
						data : {
							cmd : 'chvm',
							tgt : node,
							args : args,
							msg : 'cmd=chvm;out=' + out2Id
						},

						success : updateZProvisionNewStatus
					});
				}
			} else {
				$('#' + loaderId).hide();
			}
		}
	}

	/**
	 * (6) Set operating system for given node
	 */
	else if (cmd == 'chvm') {
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).append(prg);

		// If there was an error, do not continue
		if (prg.html().indexOf('Error') > -1) {
			$('#' + loaderId).hide();

			// Try again
			var tries = parseInt($.cookie('tries4' + tabId));
			if (tries < 2) {
				$('#' + statBarId).append('<p>Trying again...</p>');
				tries = tries + 1;

				// One more try
				$.cookie('tries4' + tabId, tries);

				// Set cookie for number of disks
				var diskRows = $('#' + tabId + ' table:visible tr');	
				$.cookie('zProvisionDisks2Add' + out2Id, diskRows.length);
				if (diskRows.length > 0) {
					for ( var i = 0; i < diskRows.length; i++) {
						// Get disk type, address, size, pool, and password
						var diskArgs = diskRows.eq(i).find('td');
						var type = diskArgs.eq(1).find('select').val();
						var address = diskArgs.eq(2).find('input').val();
						var size = diskArgs.eq(3).find('input').val();
						var mode = diskArgs.eq(4).find('select').val();
						var pool = diskArgs.eq(5).find('input').val();
						var password = diskArgs.eq(6).find('input').val();
						
						// Create ajax arguments
						var args = '';
						if (type == '3390') {
							args = '--add' + type + ';' + pool + ';' + address
								+ ';' + size + ';' + mode + ';' + password + ';'
								+ password + ';' + password;
						} else if (type == '9336') {
							var blkSize = '512';
							args = '--add' + type + ';' + pool + ';' + address + ';' 
								+ blkSize + ';' + size + ';' + mode + ';' + password + ';'
								+ password + ';' + password;
						}

						// Add disk
						$.ajax( {
							url : 'lib/cmd.php',
							dataType : 'json',
							data : {
								cmd : 'chvm',
								tgt : node,
								args : args,
								msg : 'cmd=chvm;out=' + out2Id
							},

							success : updateZProvisionNewStatus
						});
					}
				} else {
					$('#' + loaderId).hide();
				}
			} else {
				$('#' + loaderId).hide();
			}
		} else {
			// Reset number of tries
			$.cookie('tries4' + tabId, 0);
			
			// Get operating system image
			var osImage = $('#' + tabId + ' input[name=os]:visible').val();
			
			// Get cookie for number of disks
			var disks2add = $.cookie('zProvisionDisks2Add' + out2Id);
			// One less disk to add
			disks2add = disks2add - 1;
			// Set cookie for number of disks
			$.cookie('zProvisionDisks2Add' + out2Id, disks2add);

			// If an operating system image is given
			if (osImage) {
				var tmp = osImage.split('-');

				// Get operating system, architecture, provision method, and profile
				var os = tmp[0];
				var arch = tmp[1];
				var profile = tmp[3];

				// If the last disk is added
				if (disks2add < 1) {
					$.ajax( {
						url : 'lib/cmd.php',
						dataType : 'json',
						data : {
							cmd : 'nodeadd',
							tgt : '',
							args : node + ';noderes.netboot=zvm;nodetype.os='
								+ os + ';nodetype.arch=' + arch
								+ ';nodetype.profile=' + profile,
							msg : 'cmd=noderes;out=' + out2Id
						},

						success : updateZProvisionNewStatus
					});
				}
			} else {
				$('#' + loaderId).hide();
			}
		}
	}

	/**
	 * (7) Update DHCP
	 */
	else if (cmd == 'noderes') {
		// If there was an error
		// Do not continue
		if (rsp.length) {
			$('#' + loaderId).hide();
			$('#' + statBarId).append('<p>(Error) Failed to set operating system</p>');
		} else {
			$('#' + statBarId).append('<p>Operating system for ' + node + ' set</p>');
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'makedhcp',
					tgt : '',
					args : '-a',
					msg : 'cmd=makedhcp;out=' + out2Id
				},

				success : updateZProvisionNewStatus
			});
		}		
	}

	/**
	 * (8) Prepare node for boot
	 */
	else if (cmd == 'makedhcp') {
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).append(prg);
		
		// Prepare node for boot
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'nodeset',
				tgt : node,
				args : 'install',
				msg : 'cmd=nodeset;out=' + out2Id
			},

			success : updateZProvisionNewStatus
		});
	}

	/**
	 * (9) Boot node to network
	 */
	else if (cmd == 'nodeset') {
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).append(prg);
		
		// If there was an error
		// Do not continue
		if (prg.html().indexOf('Error') > -1) {
			$('#' + loaderId).hide();
		} else {
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'rnetboot',
					tgt : node,
					args : 'ipl=000C',
					msg : 'cmd=rnetboot;out=' + out2Id
				},

				success : updateZProvisionNewStatus
			});
		}
	}

	/**
	 * (10) Done
	 */
	else if (cmd == 'rnetboot') {
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).append(prg);
		if (prg.html().indexOf('Error') < 0) {
			$('#' + statBarId).append('<p>Open a VNC viewer to see the installation progress.  It might take a couple of minutes before you can connect.</p>');
		}

		// Hide loader
		$('#' + loaderId).hide();
	}
}

/**
 * Update the provision existing node status
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function updateZProvisionExistingStatus(data) {
	// Get ajax response
	var rsp = data.rsp;
	var args = data.msg.split(';');

	// Get command invoked
	var cmd = args[0].replace('cmd=', '');
	// Get provision tab instance
	var inst = args[1].replace('out=', '');
	
	// Get provision tab and status bar ID
	var statBarId = 'zProvisionStatBar' + inst;
	var tabId = 'zvmProvisionTab' + inst;
	
	/**
	 * (2) Prepare node for boot
	 */
	if (cmd == 'nodeadd') {
		// Get operating system
		var bootMethod = $('#' + tabId + ' select[name=bootMethod]').val();
		
		// Get nodes that were checked
		var dTableId = 'zNodesDatatable' + inst;
		var tgts = getNodesChecked(dTableId);
		
		// Prepare node for boot
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'nodeset',
				tgt : tgts,
				args : bootMethod,
				msg : 'cmd=nodeset;out=' + inst
			},

			success : updateZProvisionExistingStatus
		});
	} 
	
	/**
	 * (3) Boot node from network
	 */
	else if (cmd == 'nodeset') {
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).append(prg);

		// If there was an error
		// Do not continue
		if (prg.html().indexOf('Error') > -1) {
			var loaderId = 'zProvisionLoader' + inst;
			$('#' + loaderId).remove();
			return;
		}
				
		// Get nodes that were checked
		var dTableId = 'zNodesDatatable' + inst;
		var tgts = getNodesChecked(dTableId);
		
		// Boot node from network
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'rnetboot',
				tgt : tgts,
				args : 'ipl=000C',
				msg : 'cmd=rnetboot;out=' + inst
			},

			success : updateZProvisionExistingStatus
		});
	} 
	
	/**
	 * (4) Done
	 */
	else if (cmd == 'rnetboot') {
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + statBarId).append(prg);
		
		var loaderId = 'zProvisionLoader' + inst;
		$('#' + loaderId).remove();
	}
}

/**
 * Update zVM node status
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function updateZNodeStatus(data) {
	var node = data.msg;
	var rsp = data.rsp;

	// Get cookie for number processes performed against this node
	var actions = $.cookie(node + 'Processes');
	// One less process
	actions = actions - 1;
	$.cookie(node + 'Processes', actions);
	
	if (actions < 1) {
		// Hide loader when there are no more processes
		var statusBarLoaderId = node + 'StatusBarLoader';
		$('#' + statusBarLoaderId).hide();
	}

	var statBarId = node + 'StatusBar';
	
	// Write ajax response to status bar
	var prg = writeRsp(rsp, '[A-Za-z0-9._-]+:');	
	$('#' + statBarId).append(prg);	
}

/**
 * Update clone status
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function updateZCloneStatus(data) {
	// Get ajax response
	var rsp = data.rsp;
	var args = data.msg.split(';');
	var cmd = args[0].replace('cmd=', '');

	// Get provision instance
	var inst = args[1].replace('inst=', '');
	// Get output division ID
	var out2Id = args[2].replace('out=', '');

	/**
	 * (2) Update /etc/hosts
	 */
	if (cmd == 'nodeadd') {
		var node = args[3].replace('node=', '');

		// If there was an error
		// Do not continue
		if (rsp.length) {
			$('#' + out2Id).find('img').hide();
			$('#' + out2Id).append('<p>(Error) Failed to create node definition</p>');
		} else {
			$('#' + out2Id).append('<p>Node definition created for ' + node + '</p>');
			
			// If last node definition was created
			var tmp = inst.split('/');
			if (tmp[0] == tmp[1]) {
				$.ajax( {
					url : 'lib/cmd.php',
					dataType : 'json',
					data : {
						cmd : 'makehosts',
						tgt : '',
						args : '',
						msg : 'cmd=makehosts;inst=' + inst + ';out=' + out2Id
					},

					success : updateZCloneStatus
				});
			}
		}		
	}

	/**
	 * (3) Update DNS
	 */
	else if (cmd == 'makehosts') {
		// If there was an error
		// Do not continue
		if (rsp.length) {
			$('#' + out2Id).find('img').hide();
			$('#' + out2Id).append('<p>(Error) Failed to update /etc/hosts</p>');
		} else {
			$('#' + out2Id).append('<p>/etc/hosts updated</p>');
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'makedns',
					tgt : '',
					args : '',
					msg : 'cmd=makedns;inst=' + inst + ';out=' + out2Id
				},

				success : updateZCloneStatus
			});
		}		
	}

	/**
	 * (4) Clone
	 */
	else if (cmd == 'makedns') {
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + out2Id).append(prg);
	
		// Get clone tab
		var tabId = out2Id.replace('CloneStatusBar', 'CloneTab');

		// If a node range is given
		var tgtNodeRange = $('#' + tabId + ' input[name=tgtNode]').val();
		var tgtNodes = '';
		if (tgtNodeRange.indexOf('-') > -1) {
			var tmp = tgtNodeRange.split('-');
			
			// Get node base name
			var nodeBase = tmp[0].match(/[a-zA-Z]+/);
			// Get the starting index
			var nodeStart = parseInt(tmp[0].match(/\d+/));
			// Get the ending index
			var nodeEnd = parseInt(tmp[1]);
			for ( var i = nodeStart; i <= nodeEnd; i++) {
				// Do not append comma for last node
				if (i == nodeEnd) {
					tgtNodes += nodeBase + i.toString();
				} else {
					tgtNodes += nodeBase + i.toString() + ',';
				}
			}
		} else {
			tgtNodes = tgtNodeRange;
		}
		
		// Get other inputs
		var srcNode = $('#' + tabId + ' input[name=srcNode]').val();
		hcp = $('#' + tabId + ' input[name=newHcp]').val();
		var group = $('#' + tabId + ' input[name=newGroup]').val();
		var diskPool = $('#' + tabId + ' input[name=diskPool]').val();
		var diskPw = $('#' + tabId + ' input[name=diskPw]').val();
		if (!diskPw) {
			diskPw = '';
		}

		// Clone
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'mkvm',
				tgt : tgtNodes,
				args : srcNode + ';pool=' + diskPool + ';pw=' + diskPw,
				msg : 'cmd=mkvm;inst=' + inst + ';out=' + out2Id
			},

			success : updateZCloneStatus
		});
	}

	/**
	 * (5) Done
	 */
	else if (cmd == 'mkvm') {
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');	
		$('#' + out2Id).append(prg);
		
		// Hide loader
		$('#' + out2Id).find('img').hide();
	}
}

/**
 * Get zVM resources
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function getZResources(data) {
	// Do not continue if there is no output
	if (data.rsp) {
		// Loop through each line
		var node, hcp;
		var hcpHash = new Object();
		for ( var i in data.rsp) {
			node = data.rsp[i][0];
			hcp = data.rsp[i][1];
			hcpHash[hcp] = 1;
		}

		// Create an array for hardware control points
		var hcps = new Array();
		for ( var key in hcpHash) {
			hcps.push(key);
			// Get the short host name
			hcp = key.split('.')[0];

			// Get disk pools
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'lsvm',
					tgt : hcp,
					args : '--diskpoolnames',
					msg : hcp
				},

				success : getDiskPool
			});

			// Get network names
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'lsvm',
					tgt : hcp,
					args : '--getnetworknames',
					msg : hcp
				},

				success : getNetwork
			});
		}

		// Set cookie
		$.cookie('HCP', hcps);
	}
}

/**
 * Get node attributes from HTTP request data
 * 
 * @param propNames
 *            Hash table of property names
 * @param keys
 *            Property keys
 * @param data
 *            Data from HTTP request
 * @return Hash table of property values
 */
function getAttrs(keys, propNames, data) {
	// Create hash table for property values
	var attrs = new Object();

	// Go through inventory and separate each property out
	var curKey; // Current property key
	var addLine; // Add a line to the current property?
	for ( var i = 1; i < data.length; i++) {
		addLine = true;

		// Loop through property keys
		// Does this line contains one of the properties?
		for ( var j = 0; j < keys.length; j++) {
			// Find property name
			if (data[i].indexOf(propNames[keys[j]]) > -1) {
				attrs[keys[j]] = new Array();

				// Get rid of property name in the line
				data[i] = data[i].replace(propNames[keys[j]], '');
				// Trim the line
				data[i] = jQuery.trim(data[i]);

				// Do not insert empty line
				if (data[i].length > 0) {
					attrs[keys[j]].push(data[i]);
				}

				curKey = keys[j];
				addLine = false; // This line belongs to a property
			}
		}

		// Line does not contain a property
		// Must belong to previous property
		if (addLine && data[i].length > 1) {
			data[i] = jQuery.trim(data[i]);
			attrs[curKey].push(data[i]);
		}
	}

	return attrs;
}

/**
 * Create add processor dialog
 * 
 * @param node
 * 			Node to add processor to
 * @return Nothing
 */
function openAddProcDialog(node) {	
	// Create form to add processor
	var addProcForm = $('<div class="form"></div>');
	// Create info bar
	var info = createInfoBar('Add a temporary processor');
	addProcForm.append(info);
	addProcForm.append('<div><label for="procNode">Processor for:</label><input type="text" readonly="readonly" id="procNode" name="procNode" value="' + node + '"/></div>');
	addProcForm.append('<div><label for="procAddress">Processor address:</label><input type="text" id="procAddress" name="procAddress"/></div>');
	
	// Create drop down for processor type
	var procType = $('<div></div>');
	procType.append('<label for="procType">Processor type:</label>');
	var typeSelect = $('<select id="procType" name="procType"></select>');
	typeSelect.append('<option>CP</option>'
		+ '<option>IFL</option>'
		+ '<option>ZAAP</option>'
		+ '<option>ZIIP</option>'
	);
	procType.append(typeSelect);
	addProcForm.append(procType);
	
	// Open dialog to add processor
	addProcForm.dialog({
		modal: true,
		width: 400,
		buttons: {
        	"Ok": function(){
        		// Remove any warning messages
        		$(this).find('.ui-state-error').remove();
        		
				// Get inputs
				var node = $(this).find('input[name=procNode]').val();
				var address = $(this).find('input[name=procAddress]').val();
				var type = $(this).find('select[name=procType]').val();
				
				// If inputs are not complete, show warning message
				if (!node || !address || !type) {
					var warn = createWarnBar('You are missing inputs.');
					warn.prependTo($(this));
				} else {
    				// Add processor
    				$.ajax( {
    					url : 'lib/cmd.php',
    					dataType : 'json',
    					data : {
    						cmd : 'chvm',
    						tgt : node,
    						args : '--addprocessoractive;' + address + ';' + type,
    						msg : node
    					},
    
    					success : updateZNodeStatus
    				});
    
    				// Increment node process
    				incrementNodeProcess(node);
    
    				// Show loader
    				var statusId = node + 'StatusBar';
    				var statusBarLoaderId = node + 'StatusBarLoader';
    				$('#' + statusBarLoaderId).show();
    				$('#' + statusId).show();
    				
    				// Close dialog
    				$(this).dialog( "close" );
				}
			},
			"Cancel": function() {
        		$(this).dialog( "close" );
        	}
		}
	});
}

/**
 * Create add disk dialog
 * 
 * @param node
 * 			Node to add disk to
 * @param hcp
 * 			Hardware control point of node
 * @return Nothing
 */
function openAddDiskDialog(node, hcp) {
	// Get list of disk pools
	var cookie = $.cookie(hcp + 'DiskPools');
	var pools = cookie.split(',');
	
	// Create form to add disk
	var addDiskForm = $('<div class="form"></div>');
	// Create info bar
	var info = createInfoBar('Add a disk');
	addDiskForm.append(info);
	addDiskForm.append('<div><label for="diskNode">Disk for:</label><input type="text" readonly="readonly" id="diskNode" name="diskNode" value="' + node + '"/></div>');
	addDiskForm.append('<div><label for="diskType">Disk type:</label><select id="diskType" name="diskType"><option value="3390">3390</option><option value="9336">9336</option></select></div>');
	addDiskForm.append('<div><label for="diskAddress">Disk address:</label><input type="text" id="diskAddress" name="diskAddress"/></div>');
	addDiskForm.append('<div><label for="diskSize">Disk size:</label><input type="text" id="diskSize" name="diskSize"/></div>');
	
	// Create drop down for disk pool
	var diskPool = $('<div></div>');
	diskPool.append('<label for="diskPool">Disk pool:</label>');
	var poolSelect = $('<select id="diskPool" name="diskPool"></select>');
	for ( var i = 0; i < pools.length; i++) {
		poolSelect.append('<option>' + pools[i] + '</option>');
	}
	diskPool.append(poolSelect);
	addDiskForm.append(diskPool);

	// Create drop down for disk mode
	var diskMode = $('<div></div>');
	diskMode.append('<label for="diskMode">Disk mode:</label>');
	var modeSelect = $('<select id="diskMode" name="diskMode"></select>');
	modeSelect.append('<option>R</option>'
		+ '<option>RR</option>'
		+ '<option>W</option>'
		+ '<option>WR</option>'
		+ '<option>M</option>'
		+ '<option>MR</option>'
		+ '<option>MW</option>'
	);
	diskMode.append(modeSelect);
	addDiskForm.append(diskMode);

	addDiskForm.append('<div><label for="diskPassword">Disk password:</label><input type="password" id="diskPassword" name="diskPassword"/></div>');

	// Open dialog to add disk
	addDiskForm.dialog({
		modal: true,
		width: 400,
		buttons: {
        	"Ok": function(){
        		// Remove any warning messages
        		$(this).find('.ui-state-error').remove();
        		
				// Get inputs
				var node = $(this).find('input[name=diskNode]').val();
        		var type = $(this).find('select[name=diskType]').val();
        		var address = $(this).find('input[name=diskAddress]').val();
        		var size = $(this).find('input[name=diskSize]').val();
        		var pool = $(this).find('select[name=diskPool]').val();
        		var mode = $(this).find('select[name=diskMode]').val();
        		var password = $(this).find('input[name=diskPassword]').val();
        		
        		// If inputs are not complete, show warning message
        		if (!node || !type || !address || !size || !pool || !mode) {
					var warn = createWarnBar('You are missing inputs.');
					warn.prependTo($(this));
        		} else {
            		// Add disk
            		if (type == '3390') {
            			$.ajax( {
            				url : 'lib/cmd.php',
            				dataType : 'json',
            				data : {
            					cmd : 'chvm',
            					tgt : node,
            					args : '--add3390;' + pool + ';' + address + ';' + size
            						+ ';' + mode + ';' + password + ';' + password + ';' + password,
            					msg : node
            				},
    
            				success : updateZNodeStatus
            			});
    
            			// Increment node process
            			incrementNodeProcess(node);
    
            			// Show loader
            			var statusId = node + 'StatusBar';
            			var statusBarLoaderId = node + 'StatusBarLoader';
            			$('#' + statusBarLoaderId).show();
            			$('#' + statusId).show();
            		} else if (type == '9336') {
            			// Default block size for FBA volumes = 512
            			var blkSize = '512';
            			
            			$.ajax( {
            				url : 'lib/cmd.php',
            				dataType : 'json',
            				data : {
            					cmd : 'chvm',
            					tgt : node,
            					args : '--add9336;' + pool + ';' + address + ';' + blkSize + ';' + size
            						+ ';' + mode + ';' + password + ';' + password + ';' + password,
            					msg : node
            				},
    
            				success : updateZNodeStatus
            			});
    
            			// Increment node process
            			incrementNodeProcess(node);
    
            			// Show loader
            			var statusId = node + 'StatusBar';
            			var statusBarLoaderId = node + 'StatusBarLoader';
            			$('#' + statusBarLoaderId).show();
            			$('#' + statusId).show();
            		}
    				
    				// Close dialog
    				$(this).dialog( "close" );
        		} // End of else
			},
			"Cancel": function() {
        		$(this).dialog( "close" );
        	}
		}
	});
}

/**
 * Create add NIC dialog
 * 
 * @param node
 * 			Node to add NIC to
 * @param hcp
 * 			Hardware control point of node
 * @return Nothing
 */
function openAddNicDialog(node, hcp) {
	// Get network names
	var networks = $.cookie(hcp + 'Networks').split(',');
		
	// Create form to add NIC
	var addNicForm = $('<div class="form"></div>');
	// Create info bar
	var info = createInfoBar('Add a NIC');
	addNicForm.append(info);
	addNicForm.append('<div><label for="nicNode">NIC for:</label><input type="text" readonly="readonly" id="nicNode" name="nicNode" value="' + node + '"/></div>');
	addNicForm.append('<div><label for="nicAddress">NIC address:</label><input type="text" id="nicAddress" name="nicAddress"/></div>');
	
	// Create drop down for NIC types
	var nicType = $('<div></div>');
	nicType.append('<label for="nicType">NIC type:</label>');
	var nicTypeSelect = $('<select id="nicType" name="nicType"></select>');
	nicTypeSelect.append('<option></option>'
		+ '<option>QDIO</option>'
		+ '<option>HiperSockets</option>'
	);
	nicType.append(nicTypeSelect);
	addNicForm.append(nicType);
		
	// Create drop down for network types
	var networkType = $('<div></div>');
	networkType.append('<label for="nicNetworkType">Network type:</label>');
	var networkTypeSelect = $('<select id="nicNetworkType" name="nicNetworkType"></select>');
	networkTypeSelect.append('<option></option>'
		+ '<option>Guest LAN</option>'
		+ '<option>Virtual Switch</option>'
	);
	networkType.append(networkTypeSelect);
	addNicForm.append(networkType);
			
	// Create drop down for network names
	var gLansQdioSelect = $('<select id="nicLanQdioName" name="nicLanQdioName"></select>');
	var gLansHipersSelect = $('<select id="nicLanHipersName" name="nicLanHipersName"></select>');
	var vswitchSelect = $('<select id="nicVSwitchName" name="nicVSwitchName"></select>');
	for ( var i = 0; i < networks.length; i++) {
		var network = networks[i].split(' ');
		var networkOption = $('<option>' + network[1] + ' ' + network[2] + '</option>');
		if (network[0] == 'VSWITCH') {
			vswitchSelect.append(networkOption);
		} else if (network[0] == 'LAN:QDIO') {
			gLansQdioSelect.append(networkOption);
		} else if (network[0] == 'LAN:HIPERS') {
			gLansHipersSelect.append(networkOption);
		}
	}
	
	// Hide network name drop downs until the NIC type and network type is selected
	// QDIO Guest LAN drop down
	var guestLanQdio = $('<div></div>').hide();
	guestLanQdio.append('<label for="nicLanQdioName">Guest LAN name:</label>');
	guestLanQdio.append(gLansQdioSelect);
	addNicForm.append(guestLanQdio);
	
	// HIPERS Guest LAN drop down
	var guestLanHipers = $('<div></div>').hide();
	guestLanHipers.append('<label for="nicLanHipersName">Guest LAN name:</label>');
	guestLanHipers.append(gLansHipersSelect);
	addNicForm.append(guestLanHipers);
	
	// VSWITCH drop down
	var vswitch = $('<div></div>').hide();
	vswitch.append('<label for="nicVSwitchName">VSWITCH name:</label>');
	vswitch.append(vswitchSelect);
	addNicForm.append(vswitch);
	
	// Show network names on change
	networkTypeSelect.change(function(){
		// Remove any warning messages
		$(this).parent().parent().find('.ui-state-error').remove();
		
		// Get NIC type and network type
		var nicType = $(this).parent().parent().find('select[name=nicType]').val();
		var networkType = $(this).val();
				
		// Hide network name drop downs
		var guestLanQdio = $(this).parent().parent().find('select[name=nicLanQdioName]').parent();
		var guestLanHipers = $(this).parent().parent().find('select[name=nicLanHipersName]').parent();
		var vswitch = $(this).parent().parent().find('select[name=nicVSwitchName]').parent();
		guestLanQdio.hide();
		guestLanHipers.hide();
		vswitch.hide();
		
		// Show correct network name
		if (networkType == 'Guest LAN' && nicType == 'QDIO') {
			guestLanQdio.show();
		} else if (networkType == 'Guest LAN' && nicType == 'HiperSockets') {
			guestLanHipers.show();
		} else if (networkType == 'Virtual Switch') {
			if (nicType == 'QDIO') {
				vswitch.show();
			} else {
				// No such thing as HIPERS VSWITCH
				var warn = createWarnBar('The selected choices are not valid.');
				warn.prependTo($(this).parent().parent());
			}
		}
	});
	
	// Show network names on change
	nicTypeSelect.change(function(){
		// Remove any warning messages
		$(this).parent().parent().find('.ui-state-error').remove();
		
		// Get NIC type and network type
		var nicType = $(this).val();
		var networkType = $(this).parent().parent().find('select[name=nicNetworkType]').val();

		// Hide network name drop downs
		var guestLanQdio = $(this).parent().parent().find('select[name=nicLanQdioName]').parent();
		var guestLanHipers = $(this).parent().parent().find('select[name=nicLanHipersName]').parent();
		var vswitch = $(this).parent().parent().find('select[name=nicVSwitchName]').parent();
		guestLanQdio.hide();
		guestLanHipers.hide();
		vswitch.hide();
		
		// Show correct network name
		if (networkType == 'Guest LAN' && nicType == 'QDIO') {
			guestLanQdio.show();
		} else if (networkType == 'Guest LAN' && nicType == 'HiperSockets') {
			guestLanHipers.show();
		} else if (networkType == 'Virtual Switch') {
			if (nicType == 'QDIO') {
				vswitch.show();
			} else {
				// No such thing as HIPERS VSWITCH
				var warn = createWarnBar('The selected choices are not valid.');
				warn.prependTo($(this).parent().parent());
			}
		}
	});
	
	// Open dialog to add NIC
	addNicForm.dialog({
		modal: true,
		width: 400,
		buttons: {
        	"Ok": function(){
        		// Remove any warning messages
        		$(this).find('.ui-state-error').remove();
        		
        		var ready = true;
				var errMsg = '';
				
        		// Get inputs
				var node = $(this).find('input[name=nicNode]').val();
				var nicType = $(this).find('select[name=nicType]').val();
				var networkType = $(this).find('select[name=nicNetworkType]').val();
				var address = $(this).find('input[name=nicAddress]').val();
        		     
				// If inputs are not complete, show warning message
				if (!node || !nicType || !networkType || !address) {
					errMsg = 'You are missing inputs.<br>';
					ready = false;
        		} 
				
				// If a HIPERS VSWITCH is selected, show warning message
				if (nicType == 'HiperSockets' && networkType == 'Virtual Switch') {
        			errMsg += 'The selected choices are not valid.'; 
        			ready = false;
        		} 
        		
        		// If there are errors 
				if (!ready) {
					// Show warning message
					var warn = createWarnBar(errMsg);
    				warn.prependTo($(this));
        		} else {
            		// Add guest LAN
            		if (networkType == 'Guest LAN') {
            			var temp;
            			if (nicType == 'QDIO') {
            				temp = $(this).find('select[name=nicLanQdioName]').val().split(' ');
            			} else {
            				temp = $(this).find('select[name=nicLanHipersName]').val().split(' ');
            			}
            			
            			var lanOwner = temp[0];
            			var lanName = temp[1];
            			
            			$.ajax( {
            				url : 'lib/cmd.php',
            				dataType : 'json',
            				data : {
            					cmd : 'chvm',
            					tgt : node,
            					args : '--addnic;' + address + ';' + nicType + ';3',
            					msg : 'node=' + node + ';addr=' + address + ';lan='
            						+ lanName + ';owner=' + lanOwner
            				},
            				success : connect2GuestLan
            			});
            		}
            
            		// Add virtual switch
            		else if (networkType == 'Virtual Switch' && nicType == 'QDIO') {
            			var temp = $(this).find('select[name=nicVSwitchName]').val().split(' ');
            			var vswitchName = temp[1];
            
            			$.ajax( {
            				url : 'lib/cmd.php',
            				dataType : 'json',
            				data : {
            					cmd : 'chvm',
            					tgt : node,
            					args : '--addnic;' + address + ';' + nicType + ';3',
            					msg : 'node=' + node + ';addr=' + address + ';vsw='
            						+ vswitchName
            				},
            
            				success : connect2VSwitch
            			});
            		} 
            		        		        		
            		// Increment node process
            		incrementNodeProcess(node);
            
            		// Show loader
            		var statusId = node + 'StatusBar';
            		var statusBarLoaderId = node + 'StatusBarLoader';
            		$('#' + statusBarLoaderId).show();
            		$('#' + statusId).show();
    		
    				// Close dialog
    				$(this).dialog( "close" );
        		} // End of else
			},
			"Cancel": function(){
        		$(this).dialog( "close" );
        	}
		}
	});
}

/**
 * Remove processor
 * 
 * @param node
 *            Node where processor is attached
 * @param address
 *            Virtual address of processor
 * @return Nothing
 */
function removeProcessor(node, address) {
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'chvm',
			tgt : node,
			args : '--removeprocessor;' + address,
			msg : node
		},

		success : updateZNodeStatus
	});

	// Increment node process
	incrementNodeProcess(node);

	// Show loader
	var statusId = node + 'StatusBar';
	var statusBarLoaderId = node + 'StatusBarLoader';
	$('#' + statusBarLoaderId).show();
	$('#' + statusId).show();
}

/**
 * Remove disk
 * 
 * @param node
 *            Node where disk is attached
 * @param address
 *            Virtual address of disk
 * @return Nothing
 */
function removeDisk(node, address) {
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'chvm',
			tgt : node,
			args : '--removedisk;' + address,
			msg : node
		},

		success : updateZNodeStatus
	});

	// Increment node process
	incrementNodeProcess(node);

	// Show loader
	var statusId = node + 'StatusBar';
	var statusBarLoaderId = node + 'StatusBarLoader';
	$('#' + statusBarLoaderId).show();
	$('#' + statusId).show();
}

/**
 * Remove NIC
 * 
 * @param node
 *            Node where NIC is attached
 * @param address
 *            Virtual address of NIC
 * @return Nothing
 */
function removeNic(node, nic) {
	var args = nic.split('.');
	var address = args[0];

	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'chvm',
			tgt : node,
			args : '--removenic;' + address,
			msg : node
		},

		success : updateZNodeStatus
	});

	// Increment node process
	incrementNodeProcess(node);

	// Show loader
	var statusId = node + 'StatusBar';
	var statusBarLoaderId = node + 'StatusBarLoader';
	$('#' + statusBarLoaderId).show();
	$('#' + statusId).show();
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
		$.cookie(node + 'DiskPools', pools);
	}
}

/**
 * Set a cookie for the network names of a given node
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function setNetworkCookies(data) {
	if (data.rsp) {
		var node = data.msg;
		var networks = data.rsp[0].split(node + ': ');
		$.cookie(node + 'Networks', networks);
	}
}

/**
 * Get contents of each disk pool
 * 
 * @param data
 *            HTTP request data
 * @return Nothing
 */
function getDiskPool(data) {
	if (data.rsp) {
		var hcp = data.msg;
		var pools = data.rsp[0].split(hcp + ': ');

		// Get contents of each disk pool
		for ( var i in pools) {
			if (pools[i]) {
				pools[i] = jQuery.trim(pools[i]);
				      
				// Get used space
				$.ajax( {
					url : 'lib/cmd.php',
					dataType : 'json',
					data : {
						cmd : 'lsvm',
						tgt : hcp,
						args : '--diskpool;' + pools[i] + ';used',
						msg : 'hcp=' + hcp + ';pool=' + pools[i] + ';stat=used'
					},

					success : loadDiskPoolTable
				});

				// Get free space
				$.ajax( {
					url : 'lib/cmd.php',
					dataType : 'json',
					data : {
						cmd : 'lsvm',
						tgt : hcp,
						args : '--diskpool;' + pools[i] + ';free',
						msg : 'hcp=' + hcp + ';pool=' + pools[i] + ';stat=free'
					},

					success : loadDiskPoolTable
				});
			} // End of if
		} // End of for
	}
}

/**
 * Get details of each network
 * 
 * @param data
 *            HTTP request data
 * @return Nothing
 */
function getNetwork(data) {
	if (data.rsp) {
		var hcp = data.msg;
		var networks = data.rsp[0].split(hcp + ': ');

		// Loop through each network
		for ( var i = 1; i < networks.length; i++) {
			var args = networks[i].split(' ');
			var type = args[0];
			var name = args[2];

			// Get network details
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'lsvm',
					tgt : hcp,
					args : '--getnetwork;' + name,
					msg : 'hcp=' + hcp + ';type=' + type + ';network=' + name
				},

				success : loadNetworkTable
			});
		} // End of for
	} // End of if
}

/**
 * Load disk pool contents into a table
 * 
 * @param data
 *            HTTP request data
 * @return Nothing
 */
function loadDiskPoolTable(data) {
	var args = data.msg.split(';');
	var hcp = args[0].replace('hcp=', '');
	var pool = args[1].replace('pool=', '');
	var stat = args[2].replace('stat=', '');
	var tmp = data.rsp[0].split(hcp + ': ');

	// Remove loader
	var loaderID = 'zvmResourceLoader';
	if ($('#' + loaderID).length) {
		$('#' + loaderID).remove();
	}

	// Resource tab ID
	var tabID = 'zvmResourceTab';

	// Get datatable
	var dTable = getDiskDataTable();
	if (!dTable) {
		// Create info bar
		var info = createInfoBar('Shows DASD volume pools defined in the EXTENT CONTROL file.');
		$('#' + tabID).append(info);
		
		// Create disks section
		var fieldSet = $('<fieldset></fieldset>');
		var legend = $('<legend>Disks</legend>');
		fieldSet.append(legend);

		// Create a datatable
		var tableID = 'zDiskDataTable';
		var table = new DataTable(tableID);
		// Resource headers: volume ID, device type, start address, and size
		table.init( [ 'Hardware control point', 'Pool', 'Status', 'Volume ID', 'Device type', 'Start address', 'Size' ]);

		// Append datatable to tab
		fieldSet.append(table.object());
		$('#' + tabID).append(fieldSet);

		// Turn into datatable
		dTable = $('#' + tableID).dataTable();
		setDiskDataTable(dTable);
	}

	// Skip index 0 and 1 because it contains nothing
	for ( var i = 2; i < tmp.length; i++) {
		tmp[i] = jQuery.trim(tmp[i]);
		var diskAttrs = tmp[i].split(' ');
		dTable.fnAddData( [ hcp, pool, stat, diskAttrs[0], diskAttrs[1], diskAttrs[2], diskAttrs[3] ]);
	}
}

/**
 * Load network details into a table
 * 
 * @param data
 *            HTTP request data
 * @return Nothing
 */
function loadNetworkTable(data) {
	var args = data.msg.split(';');
	var hcp = args[0].replace('hcp=', '');
	var type = args[1].replace('type=', '');
	var name = args[2].replace('network=', '');
	var tmp = data.rsp[0].split(hcp + ': ');

	// Remove loader
	var loaderID = 'zvmResourceLoader';
	if ($('#' + loaderID).length) {
		$('#' + loaderID).remove();
	}

	// Resource tab ID
	var tabID = 'zvmResourceTab';

	// Get datatable
	var dTable = getNetworkDataTable();
	if (!dTable) {
		// Create info bar
		var info = createInfoBar('Shows LANs and VSWITCHes found by a given zHCP.');
		$('#' + tabID).append(info);
		
		// Create networks section
		var fieldSet = $('<fieldset></fieldset>');
		var legend = $('<legend>Networks</legend>');
		fieldSet.append(legend);

		// Create table
		var tableID = 'zNetworkDataTable';
		var table = new DataTable(tableID);
		table.init( [ 'Hardware control point', 'Type', 'Name', 'Details' ]);

		// Append datatable to tab
		fieldSet.append(table.object());
		$('#' + tabID).append(fieldSet);

		// Turn into datatable
		dTable = $('#' + tableID).dataTable();
		setNetworkDataTable(dTable);

		// Set the column width
		var cols = table.object().find('thead tr th');
		cols.eq(0).css('width', '20px'); // HCP column
		cols.eq(1).css('width', '20px'); // Type column
		cols.eq(2).css('width', '20px'); // Name column
		cols.eq(3).css('width', '600px'); // Details column
	}

	// Skip index 0 because it contains nothing
	var details = '';
	for ( var i = 1; i < tmp.length; i++) {
		details += tmp[i] + '<br>';
	}
	dTable.fnAddData( [ hcp, type, name, details ]);
}

/**
 * Connect a NIC to a Guest LAN
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function connect2GuestLan(data) {
	var rsp = data.rsp;
	var args = data.msg.split(';');
	var node = args[0].replace('node=', '');
	var address = args[1].replace('addr=', '');
	var lanName = args[2].replace('lan=', '');
	var lanOwner = args[3].replace('owner=', '');

	var statBarId = node + 'StatusBar';
	
	// Write ajax response to status bar
	var prg = writeRsp(rsp, node + ': ');	
	$('#' + statBarId).append(prg);	
			
	// Connect NIC to Guest LAN
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'chvm',
			tgt : node,
			args : '--connectnic2guestlan;' + address + ';' + lanName + ';'
				+ lanOwner,
			msg : node
		},

		success : updateZNodeStatus
	});
}

/**
 * Connect a NIC to a VSwitch
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function connect2VSwitch(data) {
	var rsp = data.rsp;
	var args = data.msg.split(';');
	var node = args[0].replace('node=', '');
	var address = args[1].replace('addr=', '');
	var vswitchName = args[2].replace('vsw=', '');

	var statBarId = node + 'StatusBar';
	
	// Write ajax response to status bar
	var prg = writeRsp(rsp, node + ': ');	
	$('#' + statBarId).append(prg);	

	// Connect NIC to VSwitch
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'chvm',
			tgt : node,
			args : '--connectnic2vswitch;' + address + ';' + vswitchName,
			msg : node
		},

		success : updateZNodeStatus
	});
}

/**
 * Create provision existing node division
 * 
 * @param inst	
 * 			Provision tab instance
 * @return Provision existing node division
 */
function createZProvisionExisting(inst) {
	// Create provision existing and hide it
	var provExisting = $('<div></div>').hide();
		
	// Create group input
	var group = $('<div></div>');
	var groupLabel = $('<label for="provType">Group:</label>');
	group.append(groupLabel);
	
	// Turn on auto complete for group
	var groupNames = $.cookie('Groups');
	if (groupNames) {
		// Split group names into an array
		var tmp = groupNames.split(',');
		
		// Create drop down for groups		
		var groupSelect = $('<select></select>');
		groupSelect.append('<option></option>');
		for (var i in tmp) {
			// Add group into drop down
			var opt = $('<option value="' + tmp[i] + '">' + tmp[i] + '</option>');
			groupSelect.append(opt);
		}
		group.append(groupSelect);
		
		// Create node datatable
		groupSelect.change(function(){			
			// Get group selected
			var thisGroup = $(this).val();
			// If a valid group is selected
			if (thisGroup) {
				createNodesDatatable(thisGroup, 'zNodesDatatableDIV' + inst);
			}
		});
	} else {
		// If no groups are cookied
		var groupInput = $('<input type="text" name="group"/>');
		group.append(groupInput);
	}
	provExisting.append(group);

	// Create node input
	var node = $('<div></div>');
	var nodeLabel = $('<label for="nodeName">Nodes:</label>');
	var nodeDatatable = $('<div class="indent" id="zNodesDatatableDIV' + inst + '"><p>Select a group to view its nodes</p></div>');
	node.append(nodeLabel);
	node.append(nodeDatatable);
	provExisting.append(node);

	// Create operating system image input
	var os = $('<div></div>');
	var osLabel = $('<label for="os">Operating system image:</label>');
	var osInput = $('<input type="text" name="os"/>');
	// Get image names on focus
	osInput.one('focus', function(){
		var imageNames = $.cookie('ImageNames');
		if (imageNames) {
			// Turn on auto complete
			$(this).autocomplete(imageNames.split(','));
		}
	});
	os.append(osLabel);
	os.append(osInput);
	provExisting.append(os);
	
	// Create boot method drop down
	var bootMethod = $('<div></div>');
	var methoddLabel = $('<label>Boot method:</label>');
	var methodSelect = $('<select name="bootMethod"></select>');
	methodSelect.append('<option value="boot">boot</option>'
		+ '<option value="install">install</option>'
		+ '<option value="iscsiboot">iscsiboot</option>'
		+ '<option value="netboot">netboot</option>'
		+ '<option value="statelite">statelite</option>'
	);
	bootMethod.append(methoddLabel);
	bootMethod.append(methodSelect);
	provExisting.append(bootMethod);
	
	/**
	 * Provision existing
	 */
	var provisionBtn = createButton('Provision');
	provisionBtn.bind('click', function(event) {
		// Remove any warning messages
		$(this).parent().parent().find('.ui-state-error').remove();
		
		var ready = true;
		var errMsg = '';

		// Get provision tab ID
		var thisTabId = $(this).parent().parent().parent().attr('id');
		// Get provision tab instance
		var inst = thisTabId.replace('zvmProvisionTab', '');
		
		// Get nodes that were checked
		var dTableId = 'zNodesDatatable' + inst;
		var tgts = getNodesChecked(dTableId);
		if (!tgts) {
			errMsg += 'You need to select a node.<br>';
			ready = false;
		}
		
		// Check operating system image
		var os = $('#' + thisTabId + ' input[name=os]:visible');
		if (!os.val()) {
			errMsg += 'You need to select a operating system image.';
			os.css('border', 'solid #FF0000 1px');
			ready = false;
		} else {
			os.css('border', 'solid #BDBDBD 1px');
		}
		
		// If all inputs are valid, ready to provision
		if (ready) {			
			// Disable provision button
			$(this).attr('disabled', 'true');
			
			// Show loader
			$('#zProvisionStatBar' + inst).show();
			$('#zProvisionLoader' + inst).show();

			// Disable all inputs
			var inputs = $('#' + thisTabId + ' input:visible');
			inputs.attr('disabled', 'disabled');
						
			// Disable all selects
			var selects = $('#' + thisTabId + ' select');
			selects.attr('disabled', 'disabled');
						
			// Get operating system image
			var osImage = $('#' + thisTabId + ' input[name=os]:visible').val();
			var tmp = osImage.split('-');
			var os = tmp[0];
			var arch = tmp[1];
			var profile = tmp[3];
									
			/**
			 * (1) Set operating system
			 */
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'nodeadd',
					tgt : '',
					args : tgts + ';noderes.netboot=zvm;nodetype.os=' + os + ';nodetype.arch=' + arch + ';nodetype.profile=' + profile,
					msg : 'cmd=nodeadd;out=' + inst
				},

				success : updateZProvisionExistingStatus
			});
		} else {
			// Show warning message
			var warn = createWarnBar(errMsg);
			warn.prependTo($(this).parent().parent());
		}
	});
	provExisting.append(provisionBtn);
	
	return provExisting;
}

/**
 * Create provision new node division
 * 
 * @param inst	
 * 			Provision tab instance
 * @return Provision new node division
 */
function createZProvisionNew(inst) {
	// Create provision new node division
	var provNew = $('<div></div>');
	
	// Create group input
	var group = $('<div></div>');
	var groupLabel = $('<label>Group:</label>');
	var groupInput = $('<input type="text" name="group"/>');
	// Get groups on-focus
	groupInput.one('focus', function(){
		var groupNames = $.cookie('Groups');
		if (groupNames) {
			// Turn on auto complete
			$(this).autocomplete(groupNames.split(','));
		}
	});
	group.append(groupLabel);
	group.append(groupInput);
	provNew.append(group);
		
	// Create node input
	var nodeName = $('<div></div>');
	var nodeLabel = $('<label>Node:</label>');
	var nodeInput = $('<input type="text" name="nodeName"/>');
	nodeName.append(nodeLabel);
	nodeName.append(nodeInput);
	provNew.append(nodeName);

	// Create user ID input
	var userId = $('<div><label>User ID:</label><input type="text" name="userId"/></div>');
	provNew.append(userId);

	// Create hardware control point input
	var hcpDiv = $('<div></div>');
	var hcpLabel = $('<label for="hcp">Hardware control point:</label>');
	var hcpInput = $('<input type="text" name="hcp"/>');
	hcpInput.blur(function() {
		if ($(this).val()) {
			var args = $(this).val().split('.');

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
		}
	});
	hcpDiv.append(hcpLabel);
	hcpDiv.append(hcpInput);
	provNew.append(hcpDiv);
	
	// Create operating system image input
	var os = $('<div></div>');
	var osLabel = $('<label for="os">Operating system image:</label>');
	var osInput = $('<input type="text" name="os"/>');
	// Get image names on focus
	osInput.one('focus', function(){
		var imageNames = $.cookie('ImageNames');
		if (imageNames) {
			// Turn on auto complete
			$(this).autocomplete(imageNames.split(','));
		}
	});
	os.append(osLabel);
	os.append(osInput);
	provNew.append(os);

	// Create user entry input
	var userEntry = $('<div><label for="userEntry">Directory entry:</label><textarea/></textarea>');
	provNew.append(userEntry);

	// Create disk table
	var diskDiv = $('<div class="provision"></div>');
	var diskLabel = $('<label>Disks:</label>');
	var diskTable = $('<table></table>');
	var diskHeader = $('<thead> <th></th> <th>Type</th> <th>Address</th> <th>Size</th> <th>Mode</th> <th>Pool</th> <th>Password</th> </thead>');
	// Adjust header width
	diskHeader.find('th').css( {
		'width' : '80px'
	});
	diskHeader.find('th').eq(0).css( {
		'width' : '20px'
	});
	var diskBody = $('<tbody></tbody>');
	var diskFooter = $('<tfoot></tfoot>');

	/**
	 * Add disks
	 */
	var addDiskLink = $('<a>Add disk</a>');
	addDiskLink.bind('click', function(event) {
		// Create a row
		var diskRow = $('<tr></tr>');

		// Add remove button
		var removeBtn = $('<span class="ui-icon ui-icon-close"></span>');
		var col = $('<td></td>').append(removeBtn);
		removeBtn.bind('click', function(event) {
			diskRow.remove();
		});
		diskRow.append(col);

		// Create disk type drop down
		var diskType = $('<td></td>');
		var diskTypeSelect = $('<select></select>');
		diskTypeSelect.append('<option value="3390">3390</option>'
			+ '<option value="9336">9336</option>'
		);
		diskType.append(diskTypeSelect);
		diskRow.append(diskType);

		// Create disk address input
		var diskAddr = $('<td><input type="text"/></td>');
		diskRow.append(diskAddr);

		// Create disk size input
		var diskSize = $('<td><input type="text"/></td>');
		diskRow.append(diskSize);
		
		// Create disk mode input
		var diskMode = $('<td></td>');
		var diskModeSelect = $('<select></select>');
		diskModeSelect.append('<option value="R">R</option>'
			+ '<option value="RR">RR</option>'
			+ '<option value="W">W</option>'
			+ '<option value="WR">WR</option>'
			+ '<option value="M">M</option>'
			+ '<option value="MR">MR</option>'
			+ '<option value="MW">MW</option>'
		);
		diskMode.append(diskModeSelect);
		diskRow.append(diskMode);

		// Get list of disk pools
		var thisTabId = $(this).parent().parent().parent().parent().parent().parent().attr('id');
		var thisHcp = $('#' + thisTabId + ' input[name=hcp]').val();
		var definedPools;
		if (thisHcp) {
			// Get node without domain name
			var temp = thisHcp.split('.');
			definedPools = $.cookie(temp[0] + 'DiskPools');
		}

		// Create disk pool input
		// Turn on auto complete for disk pool
		var diskPoolInput = $('<input type="text"/>').autocomplete(definedPools.split(','));
		var diskPool = $('<td></td>').append(diskPoolInput);
		diskRow.append(diskPool);

		// Create disk password input
		var diskPw = $('<td><input type="password"/></td>');
		diskRow.append(diskPw);

		diskBody.append(diskRow);
	});
	
	// Create disk table
	diskFooter.append(addDiskLink);
	diskTable.append(diskHeader);
	diskTable.append(diskBody);
	diskTable.append(diskFooter);
	
	diskDiv.append(diskLabel);
	diskDiv.append(diskTable);
	provNew.append(diskDiv);
	
	/**
	 * Provision new
	 */
	var provisionBtn = createButton('Provision');
	provisionBtn.bind('click', function(event) {
		// Remove any warning messages
		$(this).parent().parent().find('.ui-state-error').remove();
		
		var ready = true;
		var errMsg = '';

		// Get tab ID
		var thisTabId = $(this).parent().parent().parent().attr('id');
		// Get provision tab instance
		var inst = thisTabId.replace('zvmProvisionTab', '');

		// Check node name, userId, hardware control point, and group
		var inputs = $('#' + thisTabId + ' input:visible');
		for ( var i = 0; i < inputs.length; i++) {
			// Do not check OS or disk password
			if (!inputs.eq(i).val() 
				&& inputs.eq(i).attr('name') != 'os'
				&& inputs.eq(i).attr('type') != 'password') {
				inputs.eq(i).css('border', 'solid #FF0000 1px');
				ready = false;
			} else {
				inputs.eq(i).css('border', 'solid #BDBDBD 1px');
			}
		}

		// Check user entry
		var thisUserEntry = $('#' + thisTabId + ' textarea:visible');
		thisUserEntry.val(thisUserEntry.val().toUpperCase());
		if (!thisUserEntry.val()) {
			thisUserEntry.css('border', 'solid #FF0000 1px');
			ready = false;
		} else {
			thisUserEntry.css('border', 'solid #BDBDBD 1px');
		}
		
		// Show error message for missing inputs
		if (!ready) {
			errMsg = errMsg + 'You are missing inputs.<br>';
		}

		// Check if user entry contains user ID
		var thisUserId = $('#' + thisTabId + ' input[name=userId]:visible');
		var pos = thisUserEntry.val().indexOf('USER ' + thisUserId.val().toUpperCase());
		if (pos < 0) {
			errMsg = errMsg + 'The directory entry does not contain the correct user ID.<br>';
			ready = false;
		}

		// If no operating system is specified, create only user entry
		os = $('#' + thisTabId + ' input[name=os]:visible');
		
		// Check number of disks
		var diskRows = $('#' + thisTabId + ' table tr');
		// If an OS is given, disks are needed
		if (os.val() && (diskRows.length < 1)) {
			errMsg = errMsg + 'You need to add at some disks.<br>';
			ready = false;
		}

		// Check address, size, mode, pool, and password
		var diskArgs = $('#' + thisTabId + ' table input:visible');
		for ( var i = 0; i < diskArgs.length; i++) {
			if (!diskArgs.eq(i).val()
				&& diskArgs.eq(i).attr('type') != 'password') {
				diskArgs.eq(i).css('border', 'solid #FF0000 1px');
				ready = false;
			} else {
				diskArgs.eq(i).css('border', 'solid #BDBDBD 1px');
			}
		}

		// If inputs are valid, ready to provision
		if (ready) {
			if (!os.val()) {
				// If no OS is given, create a virtual server
				var msg = '';
				if (diskRows.length > 0) {
					msg = 'Do you want to create a virtual server without an operating system?';
				} else {
					// If no disks are given, create a virtual server (no disk)
					msg = 'Do you want to create a virtual server without an operating system or disks?';
				}

				// Open dialog to confirm
				var confirmDialog = $('<div><p>' + msg + '</p></div>');   				
				confirmDialog.dialog({
					modal: true,
					width: 400,
					buttons: {
						"Ok": function(){
							// Disable provision button
							provisionBtn.attr('disabled', 'true');
							
							// Show loader
							$('#zProvisionStatBar' + inst).show();
							$('#zProvisionLoader' + inst).show();

							// Disable add disk button
							addDiskLink.attr('disabled', 'true');
							
							// Disable close button on disk table
							$('#' + thisTabId + ' table span').unbind('click');
							
							// Disable all inputs
							var inputs = $('#' + thisTabId + ' input');
							inputs.attr('disabled', 'disabled');
												
							// Disable all selects
							var selects = $('#' + thisTabId + ' select');
							selects.attr('disabled', 'disabled');
												
							// Add a new line at the end of the user entry
							var textarea = $('#' + thisTabId + ' textarea');
							var tmp = jQuery.trim(textarea.val());
							textarea.val(tmp + '\n');
							textarea.attr('readonly', 'readonly');
							textarea.css( {
								'background-color' : '#F2F2F2'
							});

							// Get node name
							var node = $('#' + thisTabId + ' input[name=nodeName]').val();
							// Get userId
							var userId = $('#' + thisTabId + ' input[name=userId]').val();
							// Get hardware control point
							var hcp = $('#' + thisTabId + ' input[name=hcp]').val();
							// Get group
							var group = $('#' + thisTabId + ' input[name=group]').val();

							/**
							 * (1) Define node
							 */
							$.ajax( {
								url : 'lib/cmd.php',
								dataType : 'json',
								data : {
									cmd : 'nodeadd',
									tgt : '',
									args : node + ';zvm.hcp=' + hcp
										+ ';zvm.userid=' + userId
										+ ';nodehm.mgt=zvm' + ';groups=' + group,
									msg : 'cmd=nodeadd;out=' + inst
								},

								success : updateZProvisionNewStatus
							});
														
							$(this).dialog("close");
						},
						"Cancel": function() {
							$(this).dialog("close");
						}
					}
				});	
			} else {
				/**
				 * Create a virtual server and install OS
				 */

				// Disable provision button
				$(this).attr('disabled', 'true');
				
				// Show loader
				$('#zProvisionStatBar' + inst).show();
				$('#zProvisionLoader' + inst).show();

				// Disable add disk button
				addDiskLink.attr('disabled', 'true');
				
				// Disable close button on disk table
				$('#' + thisTabId + ' table span').unbind('click');

				// Disable all inputs
				var inputs = $('#' + thisTabId + ' input');
				inputs.attr('disabled', 'disabled');
				inputs.css( {
					'background-color' : '#F2F2F2'
				});
				
				// Disable all selects
				var selects = $('#' + thisTabId + ' select');
				selects.attr('disabled', 'disabled');
				selects.css( {
					'background-color' : '#F2F2F2'
				});
				
				// Add a new line at the end of the user entry
				var textarea = $('#' + thisTabId + ' textarea');
				var tmp = jQuery.trim(textarea.val());
				textarea.val(tmp + '\n');
				textarea.attr('readonly', 'readonly');
				textarea.css( {
					'background-color' : '#F2F2F2'
				});

				// Get node name
				var node = $('#' + thisTabId + ' input[name=nodeName]').val();
				// Get userId
				var userId = $('#' + thisTabId + ' input[name=userId]').val();
				// Get hardware control point
				var hcp = $('#' + thisTabId + ' input[name=hcp]').val();
				// Get group
				var group = $('#' + thisTabId + ' input[name=group]').val();

				/**
				 * (1) Define node
				 */
				$.ajax( {
					url : 'lib/cmd.php',
					dataType : 'json',
					data : {
						cmd : 'nodeadd',
						tgt : '',
						args : node + ';zvm.hcp=' + hcp + ';zvm.userid='
							+ userId + ';nodehm.mgt=zvm' + ';groups='
							+ group,
						msg : 'cmd=nodeadd;out=' + inst
					},

					success : updateZProvisionNewStatus
				});
			}
		} else {
			// Show warning message
			var warn = createWarnBar(errMsg);
			warn.prependTo($(this).parent().parent());
		}
	});
	provNew.append(provisionBtn);
	
	return provNew;
}