$(document).ready(function() {
	// Include utility scripts
	includeJs("js/custom/zvmUtils.js");
});

/**
 * Constructor
 * 
 * @return Nothing
 */
var zvm = function() {
	
};

/**
 * Load clone page
 * 
 * @param node
 *            Source node to clone
 * @return Nothing
 */
zvm.prototype.loadClonePage = function(node) {
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
		var dTable = getNodesDataTable();
		var rowPos = dTable.fnGetPosition(nodeRow.get(0));
		var aData = dTable.fnGetData(rowPos);
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
		cloneForm.append('<div><label>Target node range:</label><input type="text" id="tgtNode" name="tgtNode"/></div>');
		// Target user ID range
		cloneForm.append('<div><label>Target user ID range:</label><input type="text" id="tgtUserId" name="tgtUserId"/></div>');

		// Create the rest of the form
		// Include clone source, hardware control point, group, disk pool, and
		// disk password
		cloneForm.append('<div><label>Clone source:</label><input type="text" id="srcNode" name="srcNode" readonly="readonly" value="' + node + '"/></div>');
		cloneForm.append('<div><label>Hardware control point:</label><input type="text" id="newHcp" name="newHcp" readonly="readonly" value="' + hcp + '"/></div>');

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

		cloneForm.append('<div><label>Disk password:</label><input type="password" id="diskPw" name="diskPw"/></div>');

		/**
		 * Clone
		 */
		var cloneBtn = createButton('Clone');
		cloneBtn.bind('click', function(event) {
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
			var nodeRange = $('#' + newTabId + ' input[name=tgtNode]').val();
			// Get target user ID
			var userIdRange = $('#' + newTabId + ' input[name=tgtUserId]').val();

			// Is a node range given
			if (nodeRange.indexOf('-') > -1 || userIdRange.indexOf('-') > -1) {
				if (nodeRange.indexOf('-') < 0 || userIdRange.indexOf('-') < 0) {
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

					// If the starting and ending index do not match
					if (!(nodeStart == userIdStart) || !(nodeEnd == userIdEnd)) {
						// Not ready to provision
						errMsg = errMsg + 'The node range and user ID range does not match. ';
						ready = false;
					}
				}
			}

			var srcNode = $('#' + newTabId + ' input[name=srcNode]').val();
			hcp = $('#' + newTabId + ' input[name=newHcp]').val();
			var group = $('#' + newTabId + ' input[name=newGroup]').val();
			var diskPool = $('#' + newTabId + ' input[name=diskPool]').val();
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
					 * (1) Define node
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
};

/**
 * Load node inventory
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
zvm.prototype.loadInventory = function(data) {
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
	var statBarId = node + 'StatusBar';
	var statBar = createStatusBar(statBarId);

	// Add loader to status bar, but hide it
	loaderId = node + 'StatusBarLoader';
	var loader = createLoader(loaderId);
	statBar.append(loader);
	loader.hide();
	statBar.hide();

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
		var loader = createLoader(node + 'TabLoader');
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
	 * General info
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
	 * Hardware info
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

			/**
			 * Remove processor
			 */
			var contextMenu = [{
				'Remove' : function(menuItem, menu) {
					if (confirm('Are you sure?')) {
						removeProcessor(node, $(this).text());
					}
				}
			}];

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
			addProcLink.bind('click', function(event) {
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

			/**
			 * Remove disk
			 */
			contextMenu = [{
				'Remove' : function(menuItem, menu) {
					if (confirm('Are you sure?')) {
						removeDisk(node, $(this).text());
					}
				}
			}];

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
			 * Add disk
			 */
			var addDasdLink = $('<a href="#">Add disk</a>');
			addDasdLink.bind('click', function(event) {
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

			/**
			 * Remove NIC
			 */contextMenu = [ {
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
			addNicLink.bind('click', function(event) {
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
	$('#' + tabId).append(statBar);
	$('#' + tabId).append(toggleLnkDiv);
	$('#' + tabId).append(ueDiv);
	$('#' + tabId).append(invDiv);
};

/**
 * Load provision page
 * 
 * @param tabId
 *            The provision tab ID
 * @return Nothing
 */
zvm.prototype.loadProvisionPage = function(tabId) {
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
	provisionBtn.bind('click', function(event) {
		var ready = true;
		errMsg = '';

		// Get the tab ID
		var thisTabId = $(this).parent().parent().attr('id');
		var out2Id = thisTabId.replace('zvmProvisionTab', '');

		// Check node name, userId, hardware control point, and group
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

		// If no operating system is specified, create only user entry
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
				/*
				 * If no OS is given, create a virtual server
				 */
				var msg = '';
				if (diskRows.length > 0) {
					msg = 'Do you want to create virtual server(s) without an operating system ?';
				}

				// If no disks are given, create a virtual server (no disk)
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
};

/**
 * Load the resources
 * 
 * @return Nothing
 */
zvm.prototype.loadResources = function() {
	// Reset resource table
	setDiskDataTable('');
	setNetworkDataTable('');
	
	// Get hardware control points
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'nodels',
			tgt : 'mgt==zvm',
			args : 'zvm.hcp',
			msg : ''
		},
		success : getZResources
	});
};