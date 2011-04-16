/**
 * Execute when the DOM is fully loaded
 */
$(document).ready(function() {
	// Load utility scripts
});

/**
 * Constructor
 * 
 * @return Nothing
 */
var hmcPlugin = function() {

};

/**
 * Load node inventory
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
hmcPlugin.prototype.loadInventory = function(data) {
	// Get arguments
	var args = data.msg.split(',');
	// Get tab ID
	var tabId = args[0].replace('out=', '');
	// Get node
	var node = args[1].replace('node=', '');
	// Get node inventory
	var inv = data.rsp;

	// Remove loader
	$('#' + tabId).find('img').remove();

	// Create division to hold inventory
	var invDivId = tabId + 'Inventory';
	var invDiv = $('<div class="inventory" id="' + invDivId + '"></div>');

	// Loop through each line
	var fieldSet, legend, oList, item;
	for (var k = 0; k < inv.length; k++) {
		// Remove node name in front
		var str = inv[k].replace(node + ': ', '');
		str = jQuery.trim(str);

		// If string is a header
		if (str.indexOf('I/O Bus Information') > -1 || str.indexOf('Machine Configuration Info') > -1) {
			// Create a fieldset
			fieldSet = $('<fieldset></fieldset>');
			legend = $('<legend>' + str + '</legend>');
			fieldSet.append(legend);
			oList = $('<ol></ol>');
			fieldSet.append(oList);
			invDiv.append(fieldSet);
		} else {
			// If no fieldset is defined
			if (!fieldSet) {
				// Define general fieldset
				fieldSet = $('<fieldset></fieldset>');
				legend = $('<legend>General</legend>');
				fieldSet.append(legend);
				oList = $('<ol></ol>');
				fieldSet.append(oList);
				invDiv.append(fieldSet);
			}

			// Append the string to a list
			item = $('<li></li>');
			item.append(str);
			oList.append(item);
		}
	}

	// Append to inventory form
	$('#' + tabId).append(invDiv);
};

/**
 * Load clone page
 * 
 * @param node
 *            Source node to clone
 * @return Nothing
 */
hmcPlugin.prototype.loadClonePage = function(node) {
	// Get nodes tab
	var tab = getNodesTab();
	var newTabId = node + 'CloneTab';

	// If there is no existing clone tab
	if (!$('#' + newTabId).length) {
		// Create status bar and hide it
		var statBarId = node + 'CloneStatusBar';
		var statBar = $('<div class="statusBar" id="' + statBarId + '"></div>').hide();

		// Create info bar
		var infoBar = createInfoBar('Under construction');

		// Create clone form
		var cloneForm = $('<div class="form"></div>');
		cloneForm.append(statBar);
		cloneForm.append(infoBar);

		// Add clone tab
		tab.add(newTabId, 'Clone', cloneForm, true);
	}

	tab.select(newTabId);
};

/**
 * Load provision page
 * 
 * @param tabId
 *            The provision tab ID
 * @return Nothing
 */
hmcPlugin.prototype.loadProvisionPage = function(tabId) {
	// Get OS image names
	if (!$.cookie('imagenames')) {
		$.ajax({
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
	}

	// Get groups
	if (!$.cookie('groups')) {
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
	}

	// Get provision tab instance
	var inst = tabId.replace('hmcProvisionTab', '');

	// Create provision form
	var provForm = $('<div class="form"></div>');

	// Create status bar
	var statBar = createStatusBar('statBar').hide();
	provForm.append(statBar);

	// Create loader
	var loader = createLoader('loader').hide();
	statBar.append(loader);

	// Create info bar
	var infoBar = createInfoBar('Provision a node on System p.');
	provForm.append(infoBar);

	// Append to provision tab
	$('#' + tabId).append(provForm);

	// Create provision type drop down
	provForm.append('<div><label>Provision:</label><select><option value="existing">Existing node</option></select></div>');

	/**
	 * Create provision existing node division
	 */
	provForm.append(createHmcProvisionExisting(inst));

	var hmcProvisionBtn = createButton('Provision');
	hmcProvisionBtn.bind('click', function(event) {
		// Remove any warning messages
		var tempTab = $(this).parent().parent();
		tempTab.find('.ui-state-error').remove();

		var ready = true;
		var errMsg = '';
		var tempNodes = '';

		// Get nodes that were checked
		tempNodes = getCheckedByObj(tempTab.find('table'));
		if ('' == tempNodes) {
			errMsg += 'You need to select a node.<br>';
			ready = false;
		} else {
			tempNodes = tempNodes.substr(0, tempNodes.length - 1);
		}

		// If all inputs are valid, ready to provision
		if (ready) {
			// Disable provision button
			$(this).attr('disabled', 'true');

			// Show loader
			tempTab.find('#statBar').show();
			tempTab.find('#loader').show();

			// Disable all selects, input and checkbox
			tempTab.find('input').attr('disabled', 'disabled');

			// Get operating system image
			var os = tempTab.find('#osname').val();
			var arch = tempTab.find('#arch').val();
			var profile = tempTab.find('#pro').val();

			/**
			 * (1) Set operating system
			 */
			$.ajax({
				url : 'lib/cmd.php',
				dataType : 'json',
				data : {
					cmd : 'nodeadd',
					tgt : '',
					args : tempNodes + ';noderes.netboot=yaboot;nodetype.os=' + os
							+ ';nodetype.arch=' + arch + ';nodetype.profile=' + profile,
					msg : 'cmd=nodeadd;out=' + tempTab.attr('id')
				},

				success : pProvisionExisting
			});
		} else {
			// Show warning message
			var warn = createWarnBar(errMsg);
			warn.prependTo(tempTab);
		}
	});
	provForm.append(hmcProvisionBtn);

	// Update the node table on group select
	provForm.find('#groupname').bind('change', function() {
		var groupName = $(this).val();
		var nodeArea = $('#hmcSelectNodesTable' + inst);
		nodeArea.empty();
		if (!groupName) {
			nodeArea.html('Select a group to view its nodes');
			return;
		}

		nodeArea.append(createLoader());
		createNodesArea(groupName, 'hmcSelectNodesTable' + inst);
	});
};

/**
 * Load resources
 * 
 * @return Nothing
 */
hmcPlugin.prototype.loadResources = function() {
	// Get resource tab ID
	var tabId = 'hmcResourceTab';
	// Remove loader
	$('#' + tabId).find('img').remove();

	// Create info bar
	var infoBar = createInfoBar('Under construction');

	// Create resource form
	var resrcForm = $('<div class="form"></div>');
	resrcForm.append(infoBar);

	$('#' + tabId).append(resrcForm);
};

/**
 * Add node range
 * 
 * @return Nothing
 */
hmcPlugin.prototype.addNode = function() {
	openDialog('info', 'Under construction');
};

/**
 * Create hmc provision existing form
 * 
 * @return: Form content
 */
function createHmcProvisionExisting(inst) {
	// Create the group area
	var strGroup = '<div><label>Group:</label>';
	var groupNames = $.cookie('groups');
	if (groupNames) {
		strGroup += '<select id="groupname"><option></option>';
		var temp = groupNames.split(',');
		for (var i in temp) {
			strGroup += '<option value="' + temp[i] + '">' + temp[i] + '</option>';
		}
		strGroup += '</select>';
	} else {
		strGroup += '<input type="text" id="groupname">';
	}
	strGroup += '</div>';

	// Create nodes area
	var strNodes = '<div><label>Nodes:</label><div id="hmcSelectNodesTable'
			+ inst
			+ '" style="display:inline-block;width:700px;overflow-y:auto;">Select a group to view its nodes</div></div>';

	// Create boot method
	var strBoot = '<div><label>Boot Method:</label><select id="boot">'
			+ '<option value="install">install</option>'
			+ '<option value="netboot">netboot</option>'
			+ '<option value="statelite">statelite</option></select></div>';

	// Create operating system
	var strOs = '<div><label>Operating system:</label>';
	var osName = $.cookie('osvers');
	if (osName) {
		strOs += '<select id="osname">';
		var temp = osName.split(',');
		for (var i in temp) {
			strOs += '<option value="' + temp[i] + '">' + temp[i] + '</option>';
		}
		strOs += '</select>';
	} else {
		strOs += '<input type="text" id="osname">';
	}
	strOs += '</div>';

	// Create architecture
	var strArch = '<div><label>Architecture:</label>';
	var archName = $.cookie('osarchs');
	if ('' != archName) {
		strArch += '<select id="arch">';
		var temp = archName.split(',');
		for (var i in temp) {
			strArch += '<option value="' + temp[i] + '">' + temp[i] + '</option>';
		}
		strArch += '</select>';
	} else {
		strArch += '<input type="text" id="arch">';
	}
	strArch += '</div>';

	// Create profile
	var strPro = '<div><label>Profile:</label>';
	var proName = $.cookie('profiles');
	if ('' != proName) {
		strPro += '<select id="pro">';
		var temp = proName.split(',');
		for (var i in temp) {
			strPro += '<option value="' + temp[i] + '">' + temp[i] + '</option>';
		}
		strPro += '</select>';
	} else {
		strPro += '<input type="text" id="pro">';
	}
	strPro += '</div>';

	var strRet = strGroup + strNodes + strBoot + strOs + strArch + strPro;
	return strRet;
}

/**
 * Refresh the nodes area base on group selected
 * 
 * @return Nothing
 */
function createNodesArea(groupName, areaId) {
	// Get group nodes
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'nodels',
			tgt : groupName,
			args : '',
			msg : areaId
		},

		/**
		 * Create nodes datatable
		 * 
		 * @param data
		 *            Data returned from HTTP request
		 * @return Nothing
		 */
		success : function(data) {
			var areaObj = $('#' + data.msg);
			var nodes = data.rsp;
			var index;
			var showStr = '<table><thead><tr><th><input type="checkbox" onclick="selectAllCheckbox(event, $(this))"></th>';
			showStr += '<th>Node</th></tr></thead><tbody>';
			for (index in nodes) {
				var node = nodes[index][0];
				if ('' == node) {
					continue;
				}
				showStr += '<tr><td><input type="checkbox" name="' + node + '"/></td><td>'
						+ node + '</td></tr>';
			}
			showStr += '</tbody></table>';
			areaObj.empty().append(showStr);
			if (index > 10) {
				areaObj.css('height', '300px');
			} else {
				areaObj.css('height', 'auto');
			}
		} // End of function(data)
	});
}

/**
 * Provision for existing system p node
 * 
 * @return Nothing
 */
function pProvisionExisting(data) {
	// Get ajax response
	var rsp = data.rsp;
	var args = data.msg.split(';');

	// Get command invoked
	var cmd = args[0].replace('cmd=', '');
	// Get provision tab instance
	var tabId = args[1].replace('out=', '');

	// Get tab obj
	var tempTab = $('#' + tabId);

	/**
	 * (2) Prepare node for boot
	 */
	if (cmd == 'nodeadd') {
		// Get operating system
		var bootMethod = tempTab.find('#boot').val();

		// Get nodes that were checked
		var tgts = getCheckedByObj(tempTab.find('table'));

		// Prepare node for boot
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'nodeset',
				tgt : tgts,
				args : bootMethod,
				msg : 'cmd=nodeset;out=' + tabId
			},

			success : pProvisionExisting
		});
	}

	/**
	 * (3) Boot node from network
	 */
	else if (cmd == 'nodeset') {
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');
		tempTab.find('#statBar').append(prg);

		// If there was an error, do not continue
		if (prg.html().indexOf('Error') > -1) {
			tempTab.find('#loader').remove();
			return;
		}

		// Get nodes that were checked
		var tgts = getCheckedByObj(tempTab.find('table'));

		// Boot node from network
		$.ajax({
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'rnetboot',
				tgt : tgts,
				args : '',
				msg : 'cmd=rnetboot;out=' + tabId
			},

			success : pProvisionExisting
		});
	}

	/**
	 * (4) Done
	 */
	else if (cmd == 'rnetboot') {
		// Write ajax response to status bar
		var prg = writeRsp(rsp, '');
		tempTab.find('#statBar').append(prg);
		tempTab.find('#loader').remove();
	}
}

/**
 * Get all select elements' name in the obj
 * 
 * @return All nodes name, seperate by ','
 */
function getCheckedByObj(obj) {
	var tempStr = '';
	// Get nodes that were checked
	obj.find('input:checked').each(function() {
		if ($(this).attr('name')) {
			tempStr += $(this).attr('name') + ',';
		}
	});

	if ('' != tempStr) {
		tempStr = tempStr.substr(0, tempStr.length - 1);
	}

	return tempStr;
}