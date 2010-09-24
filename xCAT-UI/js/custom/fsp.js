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
var fspPlugin = function() {

};

/**
 * Load node inventory
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
fspPlugin.prototype.loadInventory = function(data) {

};

/**
 * Load clone page
 * 
 * @param node
 *            Source node to clone
 * @return Nothing
 */
fspPlugin.prototype.loadClonePage = function(node) {

};

/**
 * Load provision page
 * 
 * @param tabId
 *            The provision tab ID
 * @return Nothing
 */
fspPlugin.prototype.loadProvisionPage = function(tabId) {
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
	var inst = tabId.replace('fspProvisionTab', '');

	// Create provision form
	var provForm = $('<div class="form"></div>');

	// Create status bar
	var statBarId = 'fspProvisionStatBar' + inst;
	var statBar = createStatusBar(statBarId);
	statBar.hide();
	provForm.append(statBar);

	// Create loader
	var loader = createLoader('fspProvisionLoader' + inst);
	loader.hide();
	statBar.append(loader);

	// Create info bar
	var infoBar = createInfoBar('Provision a fsp node');
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
	var provNew = createProvisionNew('fsp', inst);
	provForm.append(provNew);

	/**
	 * Create provision existing node division
	 */
	var provExisting = createProvisionExisting('fsp', inst);
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
fspPlugin.prototype.loadResources = function() {

};

/**
 * Add node range
 * 
 * @return Nothing
 */
fspPlugin.prototype.addNode = function() {
	
};