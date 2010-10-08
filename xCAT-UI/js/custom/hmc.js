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
	var loaderId = tabId + 'TabLoader';
	$('#' + loaderId).remove();

	// Create division to hold inventory
	var invDivId = tabId + 'Inventory';
	var invDiv = $('<div class="inventory" id="' + invDivId + '"></div>');

	// Loop through each line
	var fieldSet, legend, oList, item;
	for ( var k = 0; k < inv.length; k++) {
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

	// Get provision tab instance
	var inst = tabId.replace('hmcProvisionTab', '');

	// Create provision form
	var provForm = $('<div class="form"></div>');

	// Create status bar
	var statBarId = 'hmcProvisionStatBar' + inst;
	var statBar = createStatusBar(statBarId);
	statBar.hide();
	provForm.append(statBar);

	// Create loader
	var loader = createLoader('hmcProvisionLoader' + inst);
	loader.hide();
	statBar.append(loader);

	// Create info bar
	var infoBar = createInfoBar('Provision a hmc node');
	provForm.append(infoBar);

	// Append to provision tab
	$('#' + tabId).append(provForm);

	// Create provision type drop down
	var provType = $('<div></div>');
	var typeLabel = $('<label>Provision:</label>');
	var typeSelect = $('<select></select>');
	var provNewNode = $('<option value="new">New node</option>');
	var provExistNode = $('<option value="existing">Existing node</option>');
	typeSelect.append(provNewNode);
	typeSelect.append(provExistNode);
	provType.append(typeLabel);
	provType.append(typeSelect);
	provForm.append(provType);

	/**
	 * Create provision new node division
	 */
	// You should copy whatever is in this function, put it here, and customize it
	var provNew = createProvisionNew('hmc', inst);
	provForm.append(provNew);

	/**
	 * Create provision existing node division
	 */
	// You should copy whatever is in this function, put it here, and customize it
	var provExisting = createProvisionExisting('hmc', inst);
	provForm.append(provExisting);

	// Toggle provision new/existing on select
	typeSelect.change(function() {
		var selected = $(this).val();
		if (selected == 'new') {
			provNew.toggle();
			provExisting.toggle();
		} else {
			provNew.toggle();
			provExisting.toggle();
		}
	});
};

/**
 * Load resources
 * 
 * @return Nothing
 */
hmcPlugin.prototype.loadResources = function() {
	// Get resource tab ID
	var tabID = 'hmcResourceTab';
	// Get loader ID
	var loaderID = 'hmcResourceLoader';
	if ($('#' + loaderID).length) {
		$('#' + loaderID).remove();
	}
	
	// Create info bar
	var infoBar = createInfoBar('Under construction');

	// Create resource form
	var resrcForm = $('<div class="form"></div>');
	resrcForm.append(infoBar);
	
	$('#' + tabID).append(resrcForm);
};

/**
 * Add node range
 * 
 * @return Nothing
 */
hmcPlugin.prototype.addNode = function() {
	openDialog('info', 'Under construction');
};