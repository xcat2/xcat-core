/**
 * Global variables
 */
var provisionTabs; // Provision tabs

/**
 * Set the provision tab
 * 
 * @param obj
 *            Tab object
 * @return Nothing
 */
function setProvisionTab(obj) {
	provisionTabs = obj;
}

/**
 * Get the provision tab
 * 
 * @param Nothing
 * @return Tab object
 */
function getProvisionTab() {
	return provisionTabs;
}

/**
 * Load provision page
 * 
 * @return Nothing
 */
function loadProvisionPage() {
	// If the page is loaded
	if ($('#provision_page').children().length) {
		// Do not load again
		return;
	}

	// Create status bar, hide on load
	var statBarId = 'ProvisionStatusBar';
	var statBar = $('<div class="statusBar" id="' + statBarId + '"></div>')
		.hide();

	// Create info bar
	var infoBar = createInfoBar('Provision a node');
	$('#provision_page').append(infoBar);

	// Create provision form
	provForm = $('<div class="provision"></div>');
	provForm.append(statBar);
	provForm.append(infoBar);

	// Create provision tab
	var tab = new Tab();
	setProvisionTab(tab);
	tab.init();
	$('#provision_page').append(tab.object());

	// Create drop-down menu
	// Hardware available to provision - ipmi, blade, hmc, ivm, fsp, and zvm
	var div = $('<div></div>');
	provForm.append(div);

	var label = $('<span>Select the hardware to provision:</span>');
	var hw = $('<select></select>');
	var ipmi = $('<option value="ipmi">ipmi</option>');
	var blade = $('<option value="blade">blade</option>');
	var hmc = $('<option value="hmc">hmc</option>');
	var ivm = $('<option value="ivm">ivm</option>');
	var fsp = $('<option value="fsp">fsp</option>');
	var zvm = $('<option value="zvm">zvm</option>');

	hw.append(ipmi);
	hw.append(blade);
	hw.append(hmc);
	hw.append(ivm);
	hw.append(fsp);
	hw.append(zvm);
	div.append(label);
	div.append(hw);

	/**
	 * Ok
	 */
	var okBtn = createButton('Ok');
	okBtn.bind('click', function(event) {
		// Get hardware that was selected
		var hw = $(this).parent().find('select').val();

		// Generate new tab ID
		var instance = 0;
		var newTabId = hw + 'ProvisionTab' + instance;
		while ($('#' + newTabId).length) {
			// If one already exists, generate another one
			instance = instance + 1;
			newTabId = hw + 'ProvisionTab' + instance;
		}

		tab.add(newTabId, hw, '');

		// Select tab
		tab.select(newTabId);
		if (hw == 'zvm') {
			loadZProvisionPage(newTabId);
		} else {
			// TODO: Add other platforms to this section
			$('#' + newTabId).append('<p>Not supported</p>');
		}
	});
	provForm.append(okBtn);

	tab.add('provisionTab', 'Provision', provForm);
}