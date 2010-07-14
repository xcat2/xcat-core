/**
 * Global variables
 */
var diskDataTable; // zVM datatable containing disks
var networkDataTable; // zVM datatable containing networks

/**
 * Get the disk datatable
 * 
 * @param Nothing
 * @return Data table object
 */
function getDiskDataTable() {
	return diskDataTable;
}

/**
 * Set the disk datatable
 * 
 * @param table
 *            Data table object
 * @return Nothing
 */
function setDiskDataTable(table) {
	diskDataTable = table;
}

/**
 * Get the network datatable
 * 
 * @param Nothing
 * @return Data table object
 */
function getNetworkDataTable() {
	return networkDataTable;
}

/**
 * Set the network datatable
 * 
 * @param table
 *            Data table object
 * @return Nothing
 */
function setNetworkDataTable(table) {
	networkDataTable = table;
}

/**
 * Load zVM provision page
 * 
 * @param tabId
 *            The provision tab ID
 * @return Nothing
 */
function loadZProvisionPage(tabId) {
	// Get tab area where new tab will go
	var myTab = getProvisionTab();
	var errMsg;

	// Get the OS image names
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'tabdump',
			tgt : '',
			args : 'osimage',
			msg : ''
		},

		success : setOSImageCookies
	});

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

		success : setGroupsCookies
	});

	// Generate new tab ID
	var inst = tabId.replace('zvmProvisionTab', '');

	// Open new tab
	// Create provision form
	var provForm = $('<div class="form"></div>');

	// Create status bar
	var barId = 'zProvisionStatBar' + inst;
	var statBar = createStatusBar(barId);
	statBar.hide();
	provForm.append(statBar);

	// Create loader
	var loader = createLoader('zProvisionLoader' + inst);
	loader.hide();
	statBar.append(loader);

	// Create info bar
	var infoBar = createInfoBar('Provision a zVM node');
	provForm.append(infoBar);

	// Append to provision tab
	$('#' + tabId).append(provForm);

	// Node name
	var nodeName = $('<div><label for="nodeName">Node:</label><input type="text" name="nodeName"/></div>');
	provForm.append(nodeName);

	// User ID
	var userId = $('<div><label for="userId">User ID:</label><input type="text" name="userId"/></div>');
	provForm.append(userId);

	// Hardware control point
	var hcpDiv = $('<div></div>');
	var hcpLabel = $('<label for="hcp">Hardware control point:</label>');
	hcpDiv.append(hcpLabel);

	var hcpInput = $('<input type="text" name="hcp"/>');
	hcpInput.blur(function() {
		// If there is a HCP
		if (hcpInput.val()) {
			var args = hcpInput.val().split('.');

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
	hcpDiv.append(hcpInput);
	provForm.append(hcpDiv);

	// Group
	var group = $('<div></div>');
	var groupLabel = $('<label for="group">Group:</label>');
	var groupInput = $('<input type="text" name="group"/>');

	// Get the groups on-focus
	groupInput.focus(function() {
		var groupNames = $.cookie('Groups');

		// If there are groups, turn on auto-complete
		if (groupNames) {
			$(this).autocomplete(groupNames.split(','));
		}
	});

	group.append(groupLabel);
	group.append(groupInput);
	provForm.append(group);

	// Operating system image
	var os = $('<div></div>');
	var osLabel = $('<label for="os">Operating system image:</label>');
	var osInput = $('<input type="text" name="os"/>');

	// Get the image names on-focus
	osInput.focus(function() {
		var imageNames = $.cookie('ImageNames');

		// If there are image names, turn on auto-complete
		if (imageNames) {
			$(this).autocomplete(imageNames.split(','));
		}
	});

	os.append(osLabel);
	os.append(osInput);
	provForm.append(os);

	// User entry
	var userEntry = $('<div><label for="userEntry">User entry:</label><textarea/></textarea>');
	provForm.append(userEntry);

	// Create disk table
	var diskDiv = $('<div class="provision"></div>');
	var diskLabel = $('<label>Disk(s):</label>');
	diskDiv.append(diskLabel);
	var diskTable = $('<table></table>');
	var diskHeader = $('<thead> <th></th> <th>Type</th> <th>Address</th> <th>Size</th> <th>Pool</th> <th>Password</th> </thead>');
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
	var addDiskLink = $('<a href="#">Add disk</a>');
	addDiskLink.bind('click', function(event) {
		var diskRow = $('<tr></tr>');

		// Remove button
		var removeBtn = $('<span class="ui-icon ui-icon-close"></span>');
		removeBtn.bind('click', function(event) {
			diskRow.remove();
		});
		var col = $('<td></td>').append(removeBtn);
		diskRow.append(col);

		// Disk type
		var diskType = $('<td></td>');
		var diskTypeSelect = $('<select></select>');
		var diskType3390 = $('<option value="3390">3390</option>');
		diskTypeSelect.append(diskType3390);
		diskType.append(diskTypeSelect);
		diskRow.append(diskType);

		// Disk address
		var diskAddr = $('<td><input type="text"/></td>');
		diskRow.append(diskAddr);

		// Disk size
		var diskSize = $('<td><input type="text"/></td>');
		diskRow.append(diskSize);

		// Get list of disk pools
		var thisTabId = $(this).parent().parent().parent().parent().parent()
			.attr('id');
		var thisHcp = $('#' + thisTabId + ' input[name=hcp]').val();
		var definedPools;
		if (thisHcp) {
			// Get node without domain
			var temp = thisHcp.split('.');
			definedPools = $.cookie(temp[0] + 'DiskPools');
		}

		// Set auto-complete for disk pool
		var diskPoolInput = $('<input type="text"/>').autocomplete(
			definedPools.split(','));
		var diskPool = $('<td></td>').append(diskPoolInput);
		diskRow.append(diskPool);

		// Disk password
		var diskPw = $('<td><input type="password"/></td>');
		diskRow.append(diskPw);

		diskBody.append(diskRow);
	});
	diskFooter.append(addDiskLink);

	diskTable.append(diskHeader);
	diskTable.append(diskBody);
	diskTable.append(diskFooter);
	diskDiv.append(diskTable);
	provForm.append(diskDiv);

	/**
	 * Provision
	 */
	var provisionBtn = createButton('Provision');
	provisionBtn
		.bind('click', function(event) {
			var ready = true;
			errMsg = '';

			// Get the tab ID
			var thisTabId = $(this).parent().parent().attr('id');
			var out2Id = thisTabId.replace('zvmProvisionTab', '');

			// Check node name, userId, hardware control point, and
			// group
			var inputs = $('#' + thisTabId + ' input');
			for ( var i = 0; i < inputs.length; i++) {
				// Do not check OS or disk password
				if (!inputs.eq(i).val() && inputs.eq(i).attr('name') != 'os'
					&& inputs.eq(i).attr('type') != 'password') {
					inputs.eq(i).css('border', 'solid #FF0000 1px');
					ready = false;
				} else {
					inputs.eq(i).css('border', 'solid #BDBDBD 1px');
				}
			}

			// Check user entry
			var thisUserEntry = $('#' + thisTabId + ' textarea');
			thisUserEntry.val(thisUserEntry.val().toUpperCase());
			if (!thisUserEntry.val()) {
				thisUserEntry.css('border', 'solid #FF0000 1px');
				ready = false;
			} else {
				thisUserEntry.css('border', 'solid #BDBDBD 1px');
			}

			// Check if user entry contains user ID
			var thisUserId = $('#' + thisTabId + ' input[name=userId]');
			var pos = thisUserEntry.val().indexOf(
				'USER ' + thisUserId.val().toUpperCase());
			if (pos < 0) {
				errMsg = errMsg + 'The user entry does not contain the correct user ID. ';
				ready = false;
			}

			// If no operating system is specified, create only user
			// entry
			os = $('#' + thisTabId + ' input[name=os]');

			// Check number of disks
			var diskRows = $('#' + thisTabId + ' table tr');
			// If an OS is given, disks are needed
			if (os.val() && (diskRows.length < 1)) {
				errMsg = errMsg + 'You need to add at some disks. ';
				ready = false;
			}

			// Check address, size, pool, and password
			var diskArgs = $('#' + thisTabId + ' table input');
			for ( var i = 0; i < diskArgs.length; i++) {
				if (!diskArgs.eq(i).val()
					&& diskArgs.eq(i).attr('type') != 'password') {
					diskArgs.eq(i).css('border', 'solid #FF0000 1px');
					ready = false;
				} else {
					diskArgs.eq(i).css('border', 'solid #BDBDBD 1px');
				}
			}

			if (ready) {
				if (!os.val()) {
					/**
					 * If no OS is given, create a virtual server
					 */
					var msg = '';
					if (diskRows.length > 0) {
						msg = 'Do you want to create virtual server(s) without an operating system ?';
					}

					// If no disks are given, create a virtual
					// server (no disk)
					else {
						msg = 'Do you want to create virtual server(s) without an operating system or disk(s) ?';
					}

					// If the user clicks Ok
					if (confirm(msg)) {
						// Stop this function from executing again
						// Unbind event
						provisionBtn.unbind('click');
						provisionBtn.css( {
							'background-color' : '#F2F2F2',
							'color' : '#BDBDBD'
						});

						// Show loader
						$('#zProvisionStatBar' + out2Id).show();
						$('#zProvisionLoader' + out2Id).show();

						// Stop this function from executing again
						// Unbind event
						addDiskLink.unbind('click');
						addDiskLink.css( {
							'color' : '#BDBDBD'
						});

						// Disable close button on disk table
						$('#' + thisTabId + ' table span').unbind('click');

						// Disable all fields
						var inputs = $('#' + thisTabId + ' input');
						inputs.attr('readonly', 'readonly');
						inputs.css( {
							'background-color' : '#F2F2F2'
						});

						var textarea = $('#' + thisTabId + ' textarea');

						// Add a new line at the end of the user entry
						var tmp = jQuery.trim(textarea.val());
						textarea.val(tmp + '\n');

						textarea.attr('readonly', 'readonly');
						textarea.css( {
							'background-color' : '#F2F2F2'
						});

						// Get node name
						var node = $('#' + thisTabId + ' input[name=nodeName]')
							.val();
						// Get userId
						var userId = $('#' + thisTabId + ' input[name=userId]')
							.val();
						// Get hardware control point
						var hcp = $('#' + thisTabId + ' input[name=hcp]').val();
						// Get group
						var group = $('#' + thisTabId + ' input[name=group]')
							.val();

						/**
						 * 1. Define node
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
								msg : 'cmd=nodeadd;out=' + out2Id
							},

							success : updateProvisionStatus
						});
					}
				} else {
					/**
					 * Create a virtual server and install OS
					 */

					// Stop this function from executing again
					// Unbind event
					$(this).unbind(event);
					$(this).css( {
						'background-color' : '#F2F2F2',
						'color' : '#BDBDBD'
					});

					// Show loader
					$('#zProvisionStatBar' + out2Id).show();
					$('#zProvisionLoader' + out2Id).show();

					// Stop this function from executing again
					// Unbind event
					addDiskLink.unbind('click');
					addDiskLink.css( {
						'color' : '#BDBDBD'
					});

					// Disable close button on disk table
					$('#' + thisTabId + ' table span').unbind('click');

					// Disable all fields
					var inputs = $('#' + thisTabId + ' input');
					inputs.attr('readonly', 'readonly');
					inputs.css( {
						'background-color' : '#F2F2F2'
					});

					var textarea = $('#' + thisTabId + ' textarea');

					// Add a new line at the end of the user entry
					var tmp = jQuery.trim(textarea.val());
					textarea.val(tmp + '\n');

					textarea.attr('readonly', 'readonly');
					textarea.css( {
						'background-color' : '#F2F2F2'
					});

					// Get node name
					var node = $('#' + thisTabId + ' input[name=nodeName]')
						.val();
					// Get userId
					var userId = $('#' + thisTabId + ' input[name=userId]')
						.val();
					// Get hardware control point
					var hcp = $('#' + thisTabId + ' input[name=hcp]').val();
					// Get group
					var group = $('#' + thisTabId + ' input[name=group]').val();

					/**
					 * 1. Define node
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
							msg : 'cmd=nodeadd;out=' + out2Id
						},

						success : updateProvisionStatus
					});
				}
			} else {
				alert('(Error) ' + errMsg);
			}
		});
	provForm.append(provisionBtn);
}

/**
 * Load netboot page
 * 
 * @param trgtNodes
 *            Targets to run rnetboot against
 * @return Nothing
 */
function loadZNetbootPage(trgtNodes) {
	// Get nodes tab
	var tab = getNodesTab();

	// Generate new tab ID
	var inst = 0;
	var newTabId = 'netbootTab' + inst;
	while ($('#' + newTabId).length) {
		// If one already exists, generate another one
		inst = inst + 1;
		newTabId = 'netbootTab' + inst;
	}

	// Open new tab
	// Create nodeset form
	var netbootForm = $('<div class="form"></div>');

	// Create status bar
	var barId = 'netbootStatusBar' + inst;
	var statusBar = createStatusBar(barId);
	statusBar.hide();
	netbootForm.append(statusBar);

	// Create loader
	var loader = createLoader('netbootLoader');
	statusBar.append(loader);

	// Create info bar
	var infoBar = createInfoBar('Cause the range of nodes to boot to network');
	netbootForm.append(infoBar);

	// Target node or group
	var target = $('<div><label for="target">Target node or group:</label><input type="text" name="target" value="' + trgtNodes + '"/></div>');
	netbootForm.append(target);

	// Create the rest of the form
	// Include IPL address
	netbootForm
		.append('<div><label>IPL address:</label><input type="text" id="ipl" name="ipl"/></div>');

	/**
	 * Ok
	 */
	var okBtn = createButton('Ok');
	okBtn.bind('click', function(event) {
		var ready = true;

		// Check state, OS, arch, and profile
		var inputs = $('#' + newTabId + ' input');
		for ( var i = 0; i < inputs.length; i++) {
			if (!inputs.eq(i).val() && inputs.eq(i).attr('name') != 'diskPw') {
				inputs.eq(i).css('border', 'solid #FF0000 1px');
				ready = false;
			} else {
				inputs.eq(i).css('border', 'solid #BDBDBD 1px');
			}
		}

		// If no inputs are empty
		if (ready) {
			// Get nodes
			var tgts = $('#' + newTabId + ' input[name=target]').val();

			// Get IPL address
			var ipl = $('#' + newTabId + ' input[name=ipl]').val();

			// Stop this function from executing again
			// Unbind event
			$(this).unbind(event);
			$(this).css( {
				'background-color' : '#F2F2F2',
				'color' : '#424242'
			});

			/**
			 * 1. Boot to network
			 */
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'rnetboot',
					tgt : tgts,
					args : 'ipl=' + ipl,
					msg : 'cmd=rnetboot;inst=' + inst
				},

				success : updateZNetbootStatus
			});

			// Show status bar
			statusBar.show();
		} else {
			alert('You are missing some values');
		}
	});
	netbootForm.append(okBtn);

	// Append to discover tab
	tab.add(newTabId, 'Netboot', netbootForm);

	// Select new tab
	tab.select(newTabId);
}

/**
 * Load the clone page
 * 
 * @param node
 *            Source node
 * @return Nothing
 */
function loadZClonePage(node) {
	// Get nodes tab
	var tab = getNodesTab();
	var newTabId = node + 'CloneTab';

	// If there is no existing clone tab for this node
	if (!$('#' + newTabId).length) {
		// Get table headers
		var table = $('#' + node).parent().parent().parent().parent();
		var headers = table.find('thead th');
		var cols = new Array();
		for ( var i = 0; i < headers.length; i++) {
			var col = headers.eq(i).text();
			cols.push(col);
		}

		// Get hardware control point column
		var hcpCol = $.inArray('hcp', cols);

		// Get hardware control point
		var nodeRow = $('#' + node).parent().parent();
		var myDataTable = getNodesDataTable();
		var rowPos = myDataTable.fnGetPosition(nodeRow.get(0));
		var aData = myDataTable.fnGetData(rowPos);
		var hcp = aData[hcpCol];

		// Create status bar, hide on load
		var statBarId = node + 'CloneStatusBar';
		var statBar = $('<div class="statusBar" id="' + statBarId + '"></div>')
			.hide();

		// Create info bar
		var infoBar = createInfoBar('Clone a node');

		// Create clone form
		var cloneForm = $('<div class="form"></div>');
		cloneForm.append(statBar);
		cloneForm.append(infoBar);

		// Target node range
		cloneForm
			.append('<div><label>Target node range:</label><input type="text" id="tgtNode" name="tgtNode"/></div>');
		// Target user ID range
		cloneForm
			.append('<div><label>Target user ID range:</label><input type="text" id="tgtUserId" name="tgtUserId"/></div>');

		// Create the rest of the form
		// Include clone source, hardware control point, group, disk pool, and
		// disk password
		cloneForm
			.append('<div><label>Clone source:</label><input type="text" id="srcNode" name="srcNode" readonly="readonly" value="' + node + '"/></div>');
		cloneForm
			.append('<div><label>Hardware control point:</label><input type="text" id="newHcp" name="newHcp" readonly="readonly" value="' + hcp + '"/></div>');

		// Group
		var group = $('<div></div>');
		var groupLabel = $('<label for="group">Group:</label>');
		var groupInput = $('<input type="text" id="newGroup" name="newGroup"/>');

		// Get the groups on-focus
		groupInput.focus(function() {
			var groupNames = $.cookie('Groups');

			// If there are groups, turn on auto-complete
			if (groupNames) {
				$(this).autocomplete(groupNames.split(','));
			}
		});

		group.append(groupLabel);
		group.append(groupInput);
		cloneForm.append(group);

		// Get the list of disk pools
		var temp = hcp.split('.');
		var diskPools = $.cookie(temp[0] + 'DiskPools');

		// Set autocomplete for disk pool
		var poolDiv = $('<div></div>');
		var poolLabel = $('<label>Disk pool:</label>');
		var poolInput = $('<input type="text" id="diskPool" name="diskPool"/>')
			.autocomplete(diskPools.split(','));
		poolDiv.append(poolLabel);
		poolDiv.append(poolInput);
		cloneForm.append(poolDiv);

		cloneForm
			.append('<div><label>Disk password:</label><input type="password" id="diskPw" name="diskPw"/></div>');

		/**
		 * Clone
		 */
		var cloneBtn = createButton('Clone');
		cloneBtn
			.bind('click', function(event) {
				var ready = true;
				var errMsg = '';

				// Check node name, userId, hardware control point, group,
				// and password
				var inputs = $('#' + newTabId + ' input');
				for ( var i = 0; i < inputs.length; i++) {
					if (!inputs.eq(i).val()
						&& inputs.eq(i).attr('name') != 'diskPw'
						&& inputs.eq(i).attr('name') != 'diskPool') {
						inputs.eq(i).css('border', 'solid #FF0000 1px');
						ready = false;
					} else {
						inputs.eq(i).css('border', 'solid #BDBDBD 1px');
					}
				}

				if (!ready) {
					errMsg = errMsg + 'You are missing some inputs. ';
				}

				// Get target node
				var nodeRange = $('#' + newTabId + ' input[name=tgtNode]')
					.val();
				// Get target user ID
				var userIdRange = $('#' + newTabId + ' input[name=tgtUserId]')
					.val();

				// Is a node range given
				if (nodeRange.indexOf('-') > -1
					|| userIdRange.indexOf('-') > -1) {
					if (nodeRange.indexOf('-') < 0
						|| userIdRange.indexOf('-') < 0) {
						errMsg = errMsg + 'A user ID range and node range needs to be given. ';
						ready = false;
					} else {
						var tmp = nodeRange.split('-');

						// Get node base name
						var nodeBase = tmp[0].match(/[a-zA-Z]+/);
						// Get the starting index
						var nodeStart = parseInt(tmp[0].match(/\d+/));
						// Get the ending index
						var nodeEnd = parseInt(tmp[1]);

						tmp = userIdRange.split('-');

						// Get user ID base name
						var userIdBase = tmp[0].match(/[a-zA-Z]+/);
						// Get the starting index
						var userIdStart = parseInt(tmp[0].match(/\d+/));
						// Get the ending index
						var userIdEnd = parseInt(tmp[1]);

						// Does starting and ending index match
						if (!(nodeStart == userIdStart)
							|| !(nodeEnd == userIdEnd)) {
							errMsg = errMsg + 'The node range and user ID range does not match. ';
							ready = false;
						}
					}
				}

				var srcNode = $('#' + newTabId + ' input[name=srcNode]').val();
				hcp = $('#' + newTabId + ' input[name=newHcp]').val();
				var group = $('#' + newTabId + ' input[name=newGroup]').val();
				var diskPool = $('#' + newTabId + ' input[name=diskPool]')
					.val();
				var diskPw = $('#' + newTabId + ' input[name=diskPw]').val();

				// If a value is given for every input
				if (ready) {
					// Disable all inputs
					var inputs = cloneForm.find('input');
					inputs.attr('readonly', 'readonly');
					inputs.css( {
						'background-color' : '#F2F2F2'
					});

					// If a node range is given
					if (nodeRange.indexOf('-') > -1) {
						var tmp = nodeRange.split('-');

						// Get node base name
						var nodeBase = tmp[0].match(/[a-zA-Z]+/);
						// Get the starting index
						var nodeStart = parseInt(tmp[0].match(/\d+/));
						// Get the ending index
						var nodeEnd = parseInt(tmp[1]);

						tmp = userIdRange.split('-');

						// Get user ID base name
						var userIdBase = tmp[0].match(/[a-zA-Z]+/);
						// Get the starting index
						var userIdStart = parseInt(tmp[0].match(/\d+/));
						// Get the ending index
						var userIdEnd = parseInt(tmp[1]);

						for ( var i = nodeStart; i <= nodeEnd; i++) {
							var node = nodeBase + i.toString();
							var userId = userIdBase + i.toString();
							var inst = i + '/' + nodeEnd;

							/**
							 * 1. Define node
							 */
							$.ajax( {
								url : 'lib/cmd.php',
								dataType : 'json',
								data : {
									cmd : 'nodeadd',
									tgt : '',
									args : node + ';zvm.hcp=' + hcp
										+ ';zvm.userid=' + userId
										+ ';nodehm.mgt=zvm' + ';groups='
										+ group,
									msg : 'cmd=nodeadd;inst=' + inst + ';out='
										+ statBarId + ';node=' + node
								},

								success : updateCloneStatus
							});
						}
					} else {
						/**
						 * 1. Define node
						 */
						$.ajax( {
							url : 'lib/cmd.php',
							dataType : 'json',
							data : {
								cmd : 'nodeadd',
								tgt : '',
								args : nodeRange + ';zvm.hcp=' + hcp
									+ ';zvm.userid=' + userIdRange
									+ ';nodehm.mgt=zvm' + ';groups=' + group,
								msg : 'cmd=nodeadd;inst=1/1;out=' + statBarId
									+ ';node=' + nodeRange
							},

							success : updateCloneStatus
						});
					}

					// Create loader
					var loader = createLoader('');
					$('#' + statBarId).append(loader);
					$('#' + statBarId).show();

					// Stop this function from executing again
					// Unbind event
					$(this).unbind(event);
					$(this).css( {
						'background-color' : '#F2F2F2',
						'color' : '#BDBDBD'
					});
				} else {
					alert('(Error) ' + errMsg);
				}
			});
		cloneForm.append(cloneBtn);

		// Add clone tab
		tab.add(newTabId, 'Clone', cloneForm);
	}
	tab.select(newTabId);
}

/**
 * Load node inventory
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function loadZInventory(data) {
	var args = data.msg.split(',');

	// Get tab ID
	var tabId = args[0].replace('out=', '');
	// Get node
	var node = args[1].replace('node=', '');
	// Get node inventory
	var inv = data.rsp[0].split(node + ':');

	// Remove loader
	var loaderId = node + 'TabLoader';
	$('#' + loaderId).remove();

	// Create status bar
	var statusBarId = node + 'StatusBar';
	var statusBar = createStatusBar(statusBarId);

	// Add loader to status bar, but hide it
	loaderId = node + 'StatusBarLoader';
	var loader = createLoader(loaderId);
	statusBar.append(loader);
	loader.hide();
	statusBar.hide();

	// Create array of property keys
	var keys = new Array('userId', 'host', 'os', 'arch', 'hcp', 'priv',
		'memory', 'proc', 'disk', 'nic');

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
	var attrs = getNodeAttrs(keys, attrNames, inv);

	// Create division to hold user entry
	var ueDivId = node + 'UserEntry';
	var ueDiv = $('<div class="userEntry" id="' + ueDivId + '"></div>');

	// Create division to hold inventory
	var invDivId = node + 'Inventory';
	var invDiv = $('<div class="inventory" id="' + invDivId + '"></div>');

	/**
	 * Show user entry
	 */
	var toggleLinkId = node + 'ToggleLink';
	var toggleLink = $('<a id="' + toggleLinkId + '" href="#">Show user entry</a>');
	toggleLink.one('click', function(event) {
		// Toggle inventory division
		$('#' + invDivId).toggle();

		// Create loader
		loader = createLoader(node + 'TabLoader');
		loader = $('<center></center>').append(loader);
		ueDiv.append(loader);

		// Get user entry
		var msg = 'out=' + ueDivId + ';node=' + node;
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'lsvm',
				tgt : node,
				args : '',
				msg : msg
			},

			success : loadUserEntry
		});

		// Change text
		$(this).text('Show inventory');

		// Stop this function from executing again
		// Unbind event
		$(this).unbind(event);
	});

	var toggleLnkDiv = $('<div class="toggle"></div>').css( {
		'text-align' : 'right'
	});
	toggleLnkDiv.append(toggleLink);

	/**
	 * General inventory
	 */
	var fieldSet = $('<fieldset></fieldset>');
	var legend = $('<legend>General</legend>');
	fieldSet.append(legend);
	var oList = $('<ol></ol>');
	var item, label, input, args;

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
	 * Hardware inventory
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
		 * Privilege
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
		 * Memory
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
		 * Processor
		 */
		else if (keys[k] == 'proc') {
			// Create a label - Property name
			label = $('<label>' + attrNames[keys[k]].replace(':', '') + '</label>');
			item.append(label);

			// Create a table to hold processor data
			var procTable = $('<table></table>');
			var procBody = $('<tbody></tbody>');
			var procFooter = $('<tfoot></tfoot>');

			// Table columns - Type, Address, ID, Base, Dedicated, and Affinity
			var procTabRow = $('<thead> <th>Type</th> <th>Address</th> <th>ID</th> <th>Base</th> <th>Dedicated</th> <th>Affinity</th> </thead>');
			procTable.append(procTabRow);
			var procType, procAddr, procId, procAff;

			// Create context menu - Remove processor
			var contextMenu = [ {
				'Remove' : function(menuItem, menu) {
					if (confirm('Are you sure?')) {
						removeProcessor(node, $(this).text());
					}
				}
			} ];

			// Loop through each processor
			var closeBtn;
			var n, temp;
			var procType, procAddr, procLink;
			for (l = 0; l < attrs[keys[k]].length; l++) {
				args = attrs[keys[k]][l].split(' ');

				// Get processor type, address, ID, and affinity
				n = 3;
				temp = args[args.length - n];
				while (!jQuery.trim(temp)) {
					n = n + 1;
					temp = args[args.length - n];
				}
				procType = $('<td>' + temp + '</td>');
				procAddr = $('<td></td>');
				procLink = $('<a href="#">' + args[1] + '</a>');

				// Append context menu to link
				procLink.contextMenu(contextMenu, {
					theme : 'vista'
				});

				procAddr.append(procLink);
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

			procTable.append(procBody);

			/**
			 * Add processor
			 */
			var addProcLink = $('<a href="#">Add processor</a>');
			addProcLink
				.bind(
					'click',
					function(event) {
						var procForm = '<div class="form">'
							+ '<div><label for="procNode">Processor for:</label><input type="text" readonly="readonly" id="procNode" name="procNode" value="'
							+ node
							+ '"/></div>'
							+ '<div><label for="procAddress">Processor address:</label><input type="text" id="procAddress" name="procAddress"/></div>'
							+ '<div><label for="procType">Processor type:</label>'
							+ '<select id="procType" name="procType">'
							+ '<option>CP</option>' + '<option>IFL</option>'
							+ '<option>ZAAP</option>' + '<option>ZIIP</option>'
							+ '</select>' + '</div>' + '</div>';

						$.prompt(procForm, {
							callback : addProcessor,
							buttons : {
								Ok : true,
								Cancel : false
							},
							prefix : 'cleanblue'
						});
					});
			procFooter.append(addProcLink);
			procTable.append(procFooter);

			item.append(procTable);
		}

		/**
		 * Disk
		 */
		else if (keys[k] == 'disk') {
			// Create a label - Property name
			label = $('<label>' + attrNames[keys[k]].replace(':', '') + '</label>');
			item.append(label);

			// Create a table to hold disk (DASD) data
			var dasdTable = $('<table></table>');
			var dasdBody = $('<tbody></tbody>');
			var dasdFooter = $('<tfoot></tfoot>');

			// Create context menu - Remove disk
			contextMenu = [ {
				'Remove' : function(menuItem, menu) {
					if (confirm('Are you sure?')) {
						removeDisk(node, $(this).text());
					}
				}
			} ];

			// Table columns - Virtual Device, Type, VolID, Type of Access, and
			// Size
			var dasdTabRow = $('<thead> <th>Virtual Device #</th> <th>Type</th> <th>VolID</th> <th>Type of Access</th> <th>Size</th> </thead>');
			dasdTable.append(dasdTabRow);
			var dasdVDev, dasdType, dasdVolId, dasdAccess, dasdSize;

			// Loop through each DASD
			for (l = 0; l < attrs[keys[k]].length; l++) {
				args = attrs[keys[k]][l].split(' ');

				// Get DASD virtual device, type, volume ID, access, and size
				dasdVDev = $('<td></td>');
				dasdLink = $('<a href="#">' + args[1] + '</a>');

				// Append context menu to link
				dasdLink.contextMenu(contextMenu, {
					theme : 'vista'
				});

				dasdVDev.append(dasdLink);

				dasdType = $('<td>' + args[2] + '</td>');
				dasdVolId = $('<td>' + args[3] + '</td>');
				dasdAccess = $('<td>' + args[4] + '</td>');
				dasdSize = $('<td>' + args[args.length - 9] + ' '
					+ args[args.length - 8] + '</td>');

				// Create a new row for each DASD
				dasdTabRow = $('<tr></tr>');
				dasdTabRow.append(dasdVDev);
				dasdTabRow.append(dasdType);
				dasdTabRow.append(dasdVolId);
				dasdTabRow.append(dasdAccess);
				dasdTabRow.append(dasdSize);
				dasdBody.append(dasdTabRow);
			}

			dasdTable.append(dasdBody);

			/**
			 * Add DASD
			 */
			var addDasdLink = $('<a href="#">Add disk</a>');
			addDasdLink
				.bind('click', function(event) {
					// Get list of disk pools
					var temp = attrs['hcp'][0].split('.');
					var cookie = $.cookie(temp[0] + 'DiskPools');

					// Create drop down list for disk pool
					var pools = cookie.split(',');
					var selectPool = '<select id="diskPool" name="diskPool">';
					for ( var i = 0; i < pools.length; i++) {
						selectPool = selectPool + '<option>' + pools[i]
							+ '</option>';
					}
					selectPool = selectPool + '</select>';

					var dasdForm = '<div class="form">'
						+ '<div><label for="diskNode">Disk for:</label><input type="text" readonly="readonly" id="diskNode" name="diskNode" value="'
						+ node
						+ '"/></div>'
						+ '<div><label for="diskType">Disk type:</label><select id="diskType" name="diskType"><option value="3390">3390</option></select></div>'
						+ '<div><label for="diskAddress">Disk address:</label><input type="text" id="diskAddress" name="diskAddress"/></div>'
						+ '<div><label for="diskSize">Disk size:</label><input type="text" id="diskSize" name="diskSize"/></div>'
						+ '<div><label for="diskPool">Disk pool:</label>'
						+ selectPool
						+ '</div>'
						+ '<div><label for="diskPassword">Disk password:</label><input type="password" id="diskPassword" name="diskPassword"/></div>'
						+ '</div>';

					$.prompt(dasdForm, {
						callback : addDisk,
						buttons : {
							Ok : true,
							Cancel : false
						},
						prefix : 'cleanblue'
					});
				});
			dasdFooter.append(addDasdLink);
			dasdTable.append(dasdFooter);

			item.append(dasdTable);
		}

		/**
		 * NIC
		 */
		else if (keys[k] == 'nic') {
			// Create a label - Property name
			label = $('<label>' + attrNames[keys[k]].replace(':', '') + '</label>');
			item.append(label);

			// Create a table to hold NIC data
			var nicTable = $('<table></table>');
			var nicBody = $('<tbody></tbody>');
			var nicFooter = $('<tfoot></tfoot>');

			// Create context menu - Remove NIC
			contextMenu = [ {
				'Remove' : function(menuItem, menu) {
					if (confirm('Are you sure?')) {
						removeNic(node, $(this).text());
					}
				}
			} ];

			// Table columns - Virtual device, Adapter Type, Port Name, # of
			// Devices, MAC Address, and LAN Name
			var nicTabRow = $('<th>Virtual Device #</th> <th>Adapter Type</th> <th>Port Name</th> <th># of Devices</th> <th>LAN Name</th>');
			nicTable.append(nicTabRow);
			var nicVDev, nicType, nicPortName, nicNumOfDevs, nicMacAddr, nicLanName;

			// Loop through each NIC (Data contained in 2 lines)
			for (l = 0; l < attrs[keys[k]].length; l = l + 2) {
				args = attrs[keys[k]][l].split(' ');

				// Get NIC virtual device, type, port name, and number of
				// devices
				nicVDev = $('<td></td>');
				nicLink = $('<a href="#">' + args[1] + '</a>');

				// Append context menu to link
				nicLink.contextMenu(contextMenu, {
					theme : 'vista'
				});

				nicVDev.append(nicLink);

				nicType = $('<td>' + args[3] + '</td>');
				nicPortName = $('<td>' + args[10] + '</td>');
				nicNumOfDevs = $('<td>' + args[args.length - 1] + '</td>');

				args = attrs[keys[k]][l + 1].split(' ');
				nicLanName = $('<td>' + args[args.length - 2] + ' '
					+ args[args.length - 1] + '</td>');

				// Create a new row for each DASD
				nicTabRow = $('<tr></tr>');
				nicTabRow.append(nicVDev);
				nicTabRow.append(nicType);
				nicTabRow.append(nicPortName);
				nicTabRow.append(nicNumOfDevs);
				nicTabRow.append(nicLanName);

				nicBody.append(nicTabRow);
			}

			nicTable.append(nicBody);

			/**
			 * Add NIC
			 */
			var addNicLink = $('<a href="#">Add NIC</a>');
			addNicLink
				.bind('click', function(event) {
					// Get network names
					var temp = attrs['hcp'][0].split('.');
					var networks = $.cookie(temp[0] + 'Networks').split(',');

					// Create a drop down list
					var gLans = '<select id="nicLanName" name="nicLanName">';
					var vswitches = '<select id="nicVSwitchName" name="nicVSwitchName">';
					for ( var i = 0; i < networks.length; i++) {
						var network = networks[i].split(' ');

						// Get VSwitches
						if (network[0] == 'VSWITCH') {
							vswitches = vswitches + '<option>' + network[0]
								+ ' ' + network[1] + '</option>';
						}

						// Get Guest LAN
						else if (network[0] == 'LAN') {
							gLans = gLans + '<option>' + network[0] + ' '
								+ network[1] + '</option>';
						}
					}
					vswitches = vswitches + '</select>';
					gLans = gLans + '</select>';

					var nicTypeForm = '<div class="form">'
						+ '<div><label for="nicNode">NIC for:</label><input type="text" readonly="readonly" id="nicNode" name="nicNode" value="'
						+ node
						+ '"/></div>'
						+ '<div><label for="nicAddress">NIC address:</label><input type="text" id="nicAddress" name="nicAddress"/></div>'
						+ '<div><label for="nicType">NIC type:</label>'
						+ '<select id="nicType" name="nicType">'
						+ '<option>QDIO</option>'
						+ '<option>HiperSocket</option>'
						+ '</select>'
						+ '</div>'
						+ '<div><label for="nicNetworkType">Network type:</label>'
						+ '<select id="nicNetworkType" name="nicNetworkType">'
						+ '<option>Guest LAN</option>'
						+ '<option>Virtual Switch</option>' + '</select>'
						+ '</div>' + '</div>';
					var configGuestLanForm = '<div class="form">'
						+ '<div><label for="nicLanName">Guest LAN name:</label>'
						+ gLans + '</div>' + '</div>';
					var configVSwitchForm = '<div class="form">'
						+ '<div><label for="nicVSwitchName">VSWITCH name:</label>'
						+ vswitches + '</div>' + '</div>';

					var states = {
						// Select NIC type
						type : {
							html : nicTypeForm,
							buttons : {
								Ok : true,
								Cancel : false
							},
							focus : 1,
							prefix : 'cleanblue',
							submit : function(v, m, f) {
								if (!v) {
									return true;
								} else {
									var networkType = f.nicNetworkType;
									if (networkType == 'Guest LAN')
										$.prompt.goToState('configGuestLan');
									else
										$.prompt.goToState('configVSwitch');
									return false;
								}
							}
						},

						// Configure guest LAN
						configGuestLan : {
							html : configGuestLanForm,
							callback : addNic,
							buttons : {
								Ok : true,
								Cancel : false
							},
							focus : 1,
							prefix : 'cleanblue',
							submit : function(v, m, f) {
								if (v) {
									return true;
								}
							}
						},

						// Configure VSwitch
						configVSwitch : {
							html : configVSwitchForm,
							callback : addNic,
							buttons : {
								Ok : true,
								Cancel : false
							},
							focus : 1,
							prefix : 'cleanblue',
							submit : function(v, m, f) {
								if (v) {
									return true;
								}
							}
						}
					};

					$.prompt(states, {
						callback : addNic,
						prefix : 'cleanblue'
					});
				});
			nicFooter.append(addNicLink);
			nicTable.append(nicFooter);

			item.append(nicTable);
		}

		oList.append(item);
	}

	// Append inventory to division
	fieldSet.append(oList);
	invDiv.append(fieldSet);

	// Append to tab
	$('#' + tabId).append(statusBar);
	$('#' + tabId).append(toggleLnkDiv);
	$('#' + tabId).append(ueDiv);
	$('#' + tabId).append(invDiv);
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
	// Get node user entry
	var userEntry = data.rsp[0].split(node + ':');

	// Remove loader
	var loaderId = node + 'TabLoader';
	$('#' + loaderId).remove();

	var toggleLinkId = node + 'ToggleLink';
	$('#' + toggleLinkId).click(function() {
		// Get the text within this link
		var lnkText = $(this).text();

		// Toggle user entry division
		$('#' + node + 'UserEntry').toggle();
		// Toggle inventory division
		$('#' + node + 'Inventory').toggle();

		// Change text
		if (lnkText == 'Show user entry') {
			$(this).text('Show inventory');
		} else {
			$(this).text('Show user entry');
		}
	});

	// Put user entry into a list
	var fieldSet = $('<fieldset></fieldset>');
	var legend = $('<legend>User Entry</legend>');
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

	// Save button
	var saveBtn = createButton('Save');
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
		incrementZNodeProcess(node);

		txtArea.attr('readonly', 'readonly');
		txtArea.css( {
			'border-width' : '0px'
		});

		// Stop this function from executing again
		// Unbind event
		$(this).unbind(event);
		$(this).hide();
		cancelBtn.hide();
	});

	// Cancel button
	var cancelBtn = createButton('Cancel');
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
	var infoBar = createInfoBar('Double click on the user entry to edit');

	// Append user entry into division
	$('#' + ueDivId).append(infoBar);
	$('#' + ueDivId).append(fieldSet);
	$('#' + ueDivId).append(saveBtn);
	$('#' + ueDivId).append(cancelBtn);
}

/**
 * Set a cookie to track the number of processes for a given node
 * 
 * @param node
 *            Node to set cookie for
 * @return Nothing
 */
function incrementZNodeProcess(node) {
	// Set cookie for number actions performed against node
	var actions = $.cookie(node + 'Processes');
	if (actions) {
		// One more process
		actions = parseInt(actions) + 1;
		$.cookie(node + 'Processes', actions);
	} else {
		$.cookie(node + 'Processes', 1);
	}
}

/**
 * Update the provision status bar
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function updateProvisionStatus(data) {
	var rsp = data.rsp;
	var args = data.msg.split(';');

	// Get command invoked
	var cmd = args[0].replace('cmd=', '');
	// Get output ID
	var out2Id = args[1].replace('out=', '');

	var statBarId = 'zProvisionStatBar' + out2Id;
	var tabId = 'zvmProvisionTab' + out2Id;

	// The tab must be open in order to get these inputs

	// Get node name
	var node = $('#' + tabId + ' input[name=nodeName]').val();
	// Get userId
	var userId = $('#' + tabId + ' input[name=userId]').val();
	// Get hardware control point
	var hcp = $('#' + tabId + ' input[name=hcp]').val();
	// Get group
	var group = $('#' + tabId + ' input[name=group]').val();
	// Get user entry
	var userEntry = $('#' + tabId + ' textarea').val();
	// Get operating system
	var osImage = $('#' + tabId + ' input[name=os]').val();

	/**
	 * 2. Update /etc/hosts
	 */
	if (cmd == 'nodeadd') {

		// If no output, no errors occurred
		if (rsp.length) {
			$('#' + statBarId).append(
				'<p>(Error) Failed to create node definition</p>');
		} else {
			$('#' + statBarId).append(
				'<p>Node definition created for ' + node + '</p>');
		}

		// Update /etc/hosts
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'makehosts',
				tgt : '',
				args : '',
				msg : 'cmd=makehosts;out=' + out2Id
			},

			success : updateProvisionStatus
		});
	}

	/**
	 * 3. Update DNS
	 */
	else if (cmd == 'makehosts') {
		// If no output, no errors occurred
		if (rsp.length) {
			$('#' + statBarId).append(
				'<p>(Error) Failed to update /etc/hosts</p>');
		} else {
			$('#' + statBarId).append('<p>/etc/hosts updated</p>');
		}

		// Update DNS
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'makedns',
				tgt : '',
				args : '',
				msg : 'cmd=makedns;out=' + out2Id
			},

			success : updateProvisionStatus
		});
	}

	/**
	 * 4. Create user entry
	 */
	else if (cmd == 'makedns') {
		// Reset the number of tries
		$.cookie('tries4' + tabId, 0);

		// Separate output into lines
		var p = $('<p></p>');
		for ( var i = 0; i < rsp.length; i++) {
			if (rsp[i]) {
				p.append(rsp[i]);
				p.append('<br>');
			}
		}

		$('#' + statBarId).append(p);

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

			success : updateProvisionStatus
		});
	}

	/**
	 * 5. Add disk and format disk
	 */
	else if (cmd == 'mkvm') {
		var failed = false;

		// Separate output into lines
		var p = $('<p></p>');
		for ( var i = 0; i < rsp.length; i++) {
			if (rsp[i]) {
				// Find the node name and insert a break before it
				rsp[i] = rsp[i].replace(new RegExp(node + ': ', 'g'), '<br>');

				p.append(rsp[i]);
				p.append('<br>');

				// If the call failed
				if (rsp[i].indexOf('Failed') > -1
					|| rsp[i].indexOf('Error') > -1) {
					failed = true;
				}
			}
		}

		$('#' + statBarId).append(p);

		// If the call failed
		if (failed) {
			// Try again (at least 2 times)
			var tries = parseInt($.cookie('tries4' + tabId));
			if (tries < 2) {
				$('#' + statBarId).append('<p>Trying again</p>');
				tries = tries + 1;

				// One more try
				$.cookie('tries4' + tabId, tries);

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

					success : updateProvisionStatus
				});
			} else {
				// Failed - Do not continue
				var loaderId = 'zProvisionLoader' + out2Id;
				$('#' + loaderId).hide();
			}
		}
		// If there were no errors
		else {

			// Reset the number of tries
			$.cookie('tries4' + tabId, 0);

			// Set cookie for number of disks
			var diskRows = $('#' + tabId + ' table tr');
			$.cookie('zProvisionDisks2Add' + out2Id, diskRows.length);

			if (diskRows.length > 0) {
				for ( var i = 0; i < diskRows.length; i++) {
					var diskArgs = diskRows.eq(i).find('td');
					var type = diskArgs.eq(1).find('select').val();
					var address = diskArgs.eq(2).find('input').val();
					var size = diskArgs.eq(3).find('input').val();
					var pool = diskArgs.eq(4).find('input').val();
					var password = diskArgs.eq(5).find('input').val();

					// Add disk and format disk
					if (type == '3390') {
						$.ajax( {
							url : 'lib/cmd.php',
							dataType : 'json',
							data : {
								cmd : 'chvm',
								tgt : node,
								args : '--add3390;' + pool + ';' + address
									+ ';' + size + ';MR;' + password + ';'
									+ password + ';' + password,
								msg : 'cmd=chvm;out=' + out2Id
							},

							success : updateProvisionStatus
						});
					} else {
						// Virtual server created
						var loaderId = 'zProvisionLoader' + out2Id;
						$('#' + loaderId).hide();
					}
				}
			} else {
				// Virtual server created (no OS, no disks)
				var loaderId = 'zProvisionLoader' + out2Id;
				$('#' + loaderId).hide();
			}
		}
	}

	/**
	 * 6. Set the operating system for given node
	 */
	else if (cmd == 'chvm') {
		var failed = false;

		// Separate output into lines
		var p = $('<p></p>');
		for ( var i = 0; i < rsp.length; i++) {
			if (rsp[i]) {
				// Find the node name and insert a break before it
				rsp[i] = rsp[i].replace(new RegExp(node + ': ', 'g'), '<br>');

				p.append(rsp[i]);
				p.append('<br>');

				// If the call failed
				if (rsp[i].indexOf('Failed') > -1
					|| rsp[i].indexOf('Error') > -1) {
					failed = true;
				}
			}
		}

		$('#' + statBarId).append(p);

		// If the call failed
		if (failed) {
			// Try again (at least 2 times)
			var tries = parseInt($.cookie('tries4' + tabId));
			if (tries < 2) {
				$('#' + statBarId).append('<p>Trying again</p>');
				tries = tries + 1;

				// One more try
				$.cookie('tries4' + tabId, tries);

				// Set cookie for number of disks
				var diskRows = $('#' + tabId + ' table tr');
				$.cookie('zProvisionDisks2Add' + out2Id, diskRows.length);
				if (diskRows.length > 0) {
					for ( var i = 0; i < diskRows.length; i++) {
						var diskArgs = diskRows.eq(i).find('td');
						var address = diskArgs.eq(1).find('input').val();
						var size = diskArgs.eq(2).find('input').val();
						var pool = diskArgs.eq(3).find('input').val();
						var password = diskArgs.eq(4).find('input').val();

						// Add disk and format disk
						$.ajax( {
							url : 'lib/cmd.php',
							dataType : 'json',
							data : {
								cmd : 'chvm',
								tgt : node,
								args : '--add3390;' + pool + ';' + address
									+ ';' + size + ';MR;' + password + ';'
									+ password + ';' + password,
								msg : 'cmd=chvm;out=' + out2Id
							},

							success : updateProvisionStatus
						});
					}
				} else {
					// Virtual server created (no OS, no disks)
					var loaderId = 'zProvisionLoader' + out2Id;
					$('#' + loaderId).hide();
				}
			} else {
				// Failed - Do not continue
				var loaderId = 'zProvisionLoader' + out2Id;
				$('#' + loaderId).remove();
			}
		} else {
			// Reset the number of tries
			$.cookie('tries4' + tabId, 0);

			// Get cookie for number of disks
			var disks2add = $.cookie('zProvisionDisks2Add' + out2Id);
			// One less disk to add
			disks2add = disks2add - 1;
			// Set cookie for number of disks
			$.cookie('zProvisionDisks2Add' + out2Id, disks2add);

			// If an operating system is given
			if (osImage) {
				var tmp = osImage.split('-');
				var os = tmp[0];
				var arch = tmp[1];
				var provisionMethod = tmp[2];
				var profile = tmp[3];

				// If this is the last disk added
				if (disks2add < 1) {
					// Set operating system
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

						success : updateProvisionStatus
					});
				}
			} else {
				// Virtual server created (no OS)
				var loaderId = 'zProvisionLoader' + out2Id;
				$('#' + loaderId).hide();
			}
		}
	}

	/**
	 * 7. Update DHCP
	 */
	else if (cmd == 'noderes') {
		// If no output, no errors occurred
		if (rsp.length) {
			$('#' + statBarId).append(
				'<p>(Error) Failed to set operating system</p>');
		} else {
			$('#' + statBarId).append(
				'<p>Operating system for ' + node + ' set</p>');
		}

		// Update DHCP
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'makedhcp',
				tgt : '',
				args : '-a',
				msg : 'cmd=makedhcp;out=' + out2Id
			},

			success : updateProvisionStatus
		});
	}

	/**
	 * 8. Prepare node for boot
	 */
	else if (cmd == 'makedhcp') {
		var failed = false;

		// Separate output into lines
		var p = $('<p></p>');
		for ( var i = 0; i < rsp.length; i++) {
			if (rsp[i]) {
				// Find the node name and insert a break before it
				rsp[i] = rsp[i].replace(new RegExp(node + ': ', 'g'), '<br>');

				p.append(rsp[i]);
				p.append('<br>');

				// If the call failed
				if (rsp[i].indexOf('Failed') > -1
					|| rsp[i].indexOf('Error') > -1) {
					failed = true;
				}
			}
		}

		$('#' + statBarId).append(p);

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

			success : updateProvisionStatus
		});
	}

	/**
	 * 9. Boot node from network
	 */
	else if (cmd == 'nodeset') {
		var failed = false;

		// Separate output into lines
		var p = $('<p></p>');
		for ( var i = 0; i < rsp.length; i++) {
			if (rsp[i]) {
				// Find the node name and insert a break before it
				rsp[i] = rsp[i].replace(new RegExp(node + ': ', 'g'), '<br>');

				p.append(rsp[i]);
				p.append('<br>');

				// If the call failed
				if (rsp[i].indexOf('Failed') > -1
					|| rsp[i].indexOf('Error') > -1) {
					failed = true;
				}
			}
		}

		$('#' + statBarId).append(p);

		// If the call failed
		if (failed) {
			// Failed - Do not continue
			var loaderId = 'zProvisionLoader' + out2Id;
			$('#' + loaderId).remove();
		} else {
			// Boot node from network
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'rnetboot',
					tgt : node,
					args : 'ipl=000C',
					msg : 'cmd=rnetboot;out=' + out2Id
				},

				success : updateProvisionStatus
			});
		}
	}

	/**
	 * 10. Done
	 */
	else if (cmd == 'rnetboot') {
		var failed = false;

		// Separate output into lines
		var p = $('<p></p>');
		for ( var i = 0; i < rsp.length; i++) {
			if (rsp[i]) {
				// Find the node name and insert a break before it
				rsp[i] = rsp[i].replace(new RegExp(node + ': ', 'g'), '<br>');

				p.append(rsp[i]);
				p.append('<br>');

				// If the call failed
				if (rsp[i].indexOf('Failed') > -1
					|| rsp[i].indexOf('Error') > -1) {
					failed = true;
				}
			}
		}

		$('#' + statBarId).append(p);

		// If the call was successful
		if (!failed) {
			$('#' + statBarId)
				.append(
					'<p>Open a VNC viewer to see the installation progress.  It might take a couple of minutes before you can connect.</p>');
		}

		// Hide loader
		$('#' + statBarId).find('img').hide();
	}
}

/**
 * Update netboot status
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function updateZNetbootStatus(data) {
	var rsp = data.rsp;
	var args = data.msg.split(';');
	var cmd = args[0].replace('cmd=', '');

	// Get nodeset instance
	var inst = args[1].replace('inst=', '');
	var statBarId = 'netbootStatusBar' + inst;
	var tabId = 'netbootTab' + inst;

	// Get nodes
	var tgts = $('#' + tabId + ' input[name=target]').val();

	/**
	 * 2. Done
	 */
	if (cmd == 'rnetboot') {
		var tgtsArray = tgts.split(',');

		// Separate output into lines
		var p = $('<p></p>');
		for ( var i = 0; i < rsp.length; i++) {
			if (rsp[i]) {
				// Find the node name and insert a break before it
				for ( var j = 0; j < tgtsArray.length; j++) {
					rsp[i] = rsp[i].replace(new RegExp(tgtsArray[j], 'g'),
						'<br>' + tgtsArray[j]);
				}

				p.append(rsp[i]);
				p.append('<br>');
			}
		}

		$('#' + statBarId).append(p);

		// Hide loader
		$('#' + statBarId).find('img').hide();
	} else {
		return;
	}
}

/**
 * Update node status bar
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

	var statusId = node + 'StatusBar';
	var failed = false;

	// Separate output into lines
	var p = $('<p></p>');
	for ( var i = 0; i < rsp.length; i++) {
		if (rsp[i]) {
			// Find the node name and insert a break before it
			rsp[i] = rsp[i].replace(new RegExp(node + ': ', 'g'), '<br>');

			p.append(rsp[i]);
			p.append('<br>');

			// If the call failed
			if (rsp[i].indexOf('Failed') > -1 || rsp[i].indexOf('Error') > -1) {
				failed = true;
			}
		}
	}

	$('#' + statusId).append(p);
}

/**
 * Update the clone status bar
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function updateCloneStatus(data) {
	var rsp = data.rsp;
	var args = data.msg.split(';');
	var cmd = args[0].replace('cmd=', '');

	// Get provision instance
	var inst = args[1].replace('inst=', '');
	var out2Id = args[2].replace('out=', '');

	/**
	 * 2. Update /etc/hosts
	 */
	if (cmd == 'nodeadd') {
		var node = args[3].replace('node=', '');

		// If no output, no errors occurred
		if (rsp.length) {
			$('#' + out2Id).append(
				'<p>(Error) Failed to create node definition</p>');
		} else {
			$('#' + out2Id).append(
				'<p>Node definition created for ' + node + '</p>');
		}

		// Is this the last instance
		var tmp = inst.split('/');
		if (tmp[0] == tmp[1]) {
			// Update /etc/hosts
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'makehosts',
					tgt : '',
					args : '',
					msg : 'cmd=makehosts;inst=' + inst + ';out=' + out2Id
				},

				success : updateCloneStatus
			});
		}
	}

	/**
	 * 3. Update DNS
	 */
	else if (cmd == 'makehosts') {
		// If no output, no errors occurred
		if (rsp.length) {
			$('#' + out2Id)
				.append('<p>(Error) Failed to update /etc/hosts</p>');
		} else {
			$('#' + out2Id).append('<p>/etc/hosts updated</p>');
		}

		// Update DNS
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'makedns',
				tgt : '',
				args : '',
				msg : 'cmd=makedns;inst=' + inst + ';out=' + out2Id
			},

			success : updateCloneStatus
		});
	}

	/**
	 * 4. Clone
	 */
	else if (cmd == 'makedns') {
		// Separate output into lines
		var p = $('<p></p>');
		for ( var i = 0; i < rsp.length; i++) {
			if (rsp[i]) {
				p.append(rsp[i]);
				p.append('<br>');
			}
		}

		$('#' + out2Id).append(p);

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

		// The tab must be opened for this to work

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

			success : updateCloneStatus
		});
	}

	/**
	 * 5. Done
	 */
	else if (cmd == 'mkvm') {
		var failed = false;

		// Separate output into lines
		var p = $('<p></p>');
		for ( var i = 0; i < rsp.length; i++) {
			if (rsp[i]) {
				p.append(rsp[i]);
				p.append('<br>');

				// If the call failed
				if (rsp[i].indexOf('Failed') > -1
					|| rsp[i].indexOf('Error') > -1) {
					failed = true;
				}
			}
		}

		$('#' + out2Id).append(p);

		// Hide loader
		$('#' + out2Id).find('img').hide();
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
function getNodeAttrs(keys, propNames, data) {
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
 * Add processor
 * 
 * @param v
 *            Value of the button clicked
 * @param m
 *            jQuery object of the message within the active state when the user
 *            clicked the button
 * @param f
 *            Key/value pairs of the form values
 * 
 * @return Nothing
 */
function addProcessor(v, m, f) {
	// If user clicks Ok, add processor
	if (v) {
		var node = f.procNode;
		var type = f.procType;
		var address = f.procAddress;

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

		// Increment node process and save it in a cookie
		incrementZNodeProcess(node);

		// Show loader
		var statusId = node + 'StatusBar';
		var statusBarLoaderId = node + 'StatusBarLoader';
		$('#' + statusBarLoaderId).show();
		$('#' + statusId).show();
	}
}

/**
 * Add disk
 * 
 * @param v
 *            Value of the button clicked
 * @param m
 *            jQuery object of the message within the active state when the user
 *            clicked the button
 * @param f
 *            Key/value pairs of the form values
 * @return Nothing
 */
function addDisk(v, m, f) {
	// If user clicks Ok, add disk
	if (v) {
		var node = f.diskNode;
		var type = f.diskType;
		var address = f.diskAddress;
		var size = f.diskSize;
		var pool = f.diskPool;
		var password = f.diskPassword;

		// Add disk
		if (type == '3390') {
			$.ajax( {
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'chvm',
					tgt : node,
					args : '--add3390;' + pool + ';' + address + ';' + size
						+ ';MR;' + password + ';' + password + ';' + password,
					msg : node
				},

				success : updateZNodeStatus
			});

			// Increment node process and save it in a cookie
			incrementZNodeProcess(node);

			// Show loader
			var statusId = node + 'StatusBar';
			var statusBarLoaderId = node + 'StatusBarLoader';
			$('#' + statusBarLoaderId).show();
			$('#' + statusId).show();
		}
	}
}

/**
 * Add NIC
 * 
 * @param v
 *            Value of the button clicked
 * @param m
 *            jQuery object of the message within the active state when the user
 *            clicked the button
 * @param f
 *            Key/value pairs of the form values
 * @return Nothing
 */
function addNic(v, m, f) {
	// If user clicks Ok, add NIC
	if (v) {
		var node = f.nicNode;
		var nicType = f.nicType;
		var networkType = f.nicNetworkType;
		var address = f.nicAddress;

		/**
		 * Add guest LAN
		 */
		if (networkType == 'Guest LAN') {
			var temp = f.nicLanName.split(' ');
			var lanName = temp[1];
			var lanOwner = temp[0];

			// Add NIC
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

		/**
		 * Add virtual switch
		 */
		else if (networkType == 'Virtual Switch') {
			var temp = f.nicVSwitchName.split(' ');
			var vswitchName = temp[1];

			// Add NIC
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

		// Increment node process and save it in a cookie
		incrementZNodeProcess(node);

		// Show loader
		var statusId = node + 'StatusBar';
		var statusBarLoaderId = node + 'StatusBarLoader';
		$('#' + statusBarLoaderId).show();
		$('#' + statusId).show();
	}
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
	// Remove processor
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

	// Increment node process and save it in a cookie
	incrementZNodeProcess(node);

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
	// Remove disk
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

	// Increment node process and save it in a cookie
	incrementZNodeProcess(node);

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

	// Remove NIC
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

	// Set cookie for number actions performed against node
	incrementZNodeProcess(node);

	// Show loader
	var statusId = node + 'StatusBar';
	var statusBarLoaderId = node + 'StatusBarLoader';
	$('#' + statusBarLoaderId).show();
	$('#' + statusId).show();
}

/**
 * Set a cookie for the disk pool names of a given node
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function setDiskPoolCookies(data) {
	// Do not set cookie if there is no output
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
	// Do not set cookie if there is no output
	if (data.rsp) {
		var node = data.msg;
		var networks = data.rsp[0].split(node + ': ');
		$.cookie(node + 'Networks', networks);
	}
}

/**
 * Get the resources for ZVM
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
function getZResources(data) {
	// Do not set cookie if there is no output
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
 * Get the contents of each disk pool
 * 
 * @param data
 *            HTTP request data
 * @return Nothing
 */
function getDiskPool(data) {
	if (data.rsp) {
		var hcp = data.msg;
		var pools = data.rsp[0].split(hcp + ': ');

		// Get the contents of each disk pool
		for ( var i in pools) {
			if (pools[i]) {
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
			}
		}

	}
}

/**
 * Get the details of each network
 * 
 * @param data
 *            HTTP request data
 * @return Nothing
 */
function getNetwork(data) {
	if (data.rsp) {
		var hcp = data.msg;
		var networks = data.rsp[0].split(hcp + ': ');

		// Get the network details
		for ( var i = 1; i < networks.length; i++) {
			var args = networks[i].split(' ');
			var type = args[0];
			var name = args[1];

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
		}
	}
}

/**
 * Load the disk pool contents into a table
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

	// Get datatable (if any)
	var dTable = getDiskDataTable();
	if (!dTable) {
		// Create disks section
		var fieldSet = $('<fieldset></fieldset>');
		var legend = $('<legend>Disks</legend>');
		fieldSet.append(legend);

		// Create a datatable
		var tableID = 'zDiskDataTable';
		var table = new DataTable(tableID);
		// Resource headers: volume ID, device type, start address, and size
		table.init( [ 'Hardware control point', 'Pool', 'Status', 'Volume ID',
			'Device type', 'Start address', 'Size' ]);

		// Append datatable to tab
		fieldSet.append(table.object());
		$('#' + tabID).append(fieldSet);

		// Turn into datatable
		dTable = $('#' + tableID).dataTable();
		setDiskDataTable(dTable);
	}

	// Skip index 0 and 1 because it contains nothing
	for ( var i = 2; i < tmp.length; i++) {
		var diskAttrs = tmp[i].split(' ');
		dTable.fnAddData( [ hcp, pool, stat, diskAttrs[0], diskAttrs[1],
			diskAttrs[2], diskAttrs[3] ]);
	}
}

/**
 * Load the network details into a table
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

	// Get datatable (if any)
	var dTable = getNetworkDataTable();
	if (!dTable) {
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

	var statusId = node + 'StatusBar';
	var failed = false;

	// Separate output into lines
	var p = $('<p></p>');
	for ( var i = 0; i < rsp.length; i++) {
		if (rsp[i]) {
			// Find the node name and insert a break before it
			rsp[i] = rsp[i].replace(new RegExp(node + ': ', 'g'), '<br>');

			p.append(rsp[i]);
			p.append('<br>');

			// If the call failed
			if (rsp[i].indexOf('Failed') > -1 || rsp[i].indexOf('Error') > -1) {
				failed = true;
			}
		}
	}

	$('#' + statusId).append(p);

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

	var statusId = node + 'StatusBar';
	var failed = false;

	// Separate output into lines
	var p = $('<p></p>');
	for ( var i = 0; i < rsp.length; i++) {
		if (rsp[i]) {
			// Find the node name and insert a break before it
			rsp[i] = rsp[i].replace(new RegExp(node + ': ', 'g'), '<br>');

			p.append(rsp[i]);
			p.append('<br>');

			// If the call failed
			if (rsp[i].indexOf('Failed') > -1 || rsp[i].indexOf('Error') > -1) {
				failed = true;
			}
		}
	}

	$('#' + statusId).append(p);

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