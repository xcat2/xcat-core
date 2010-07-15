/**
 * Global variables
 */
var monitorTabs; // Monitor tabs

/**
 * Set the monitor tab
 * 
 * @param o
 *            Tab object
 * @return Nothing
 */
function setMonitorTab(o) {
	monitorTabs = o;
}

/**
 * Get the monitor tab
 * 
 * @param Nothing
 * @return Tab object
 */
function getMonitorTab() {
	return monitorTabs;
}

/**
 * Load the monitor page
 * 
 * @return Nothing
 */
function loadMonitorPage() {
	// If the page is already loaded
	if ($('#monitor_page').children().length) {
		// Do not reload the monitor page
		return;
	}

	// Create monitor tab
	var tab = new Tab();
	setConfigTab(tab);
	tab.init();
	$('#content').append(tab.object());

	// Create provision tab
	var tab = new Tab();
	setMonitorTab(tab);
	tab.init();
	$('#content').append(tab.object());

	/**
	 * Monitor nodes
	 */
	var monitorForm = $('<div class="monitor"></div>');

	// Create info bar
	var monitorInfoBar = createInfoBar('Under construction');
	monitorForm.append(monitorInfoBar);

	// Create drop-down menu
	// Hardware available to provision - ipmi, blade, hmc, ivm, fsp, and zvm
	var div = $('<div></div>');
	monitorForm.append(div);
	tab.add('monitorTab', 'Monitor', monitorForm);

	/**
	 * Resources
	 */
	var resrcForm = $('<div class="monitor"></div>');

	// Create info bar
	var resrcInfoBar = createInfoBar('Select a hardware to view its resources');
	resrcForm.append(resrcInfoBar);

	// Create drop-down menu
	// Hardware available to provision - ipmi, blade, hmc, ivm, fsp, and zvm
	var div = $('<div></div>');
	var label = $('<span>Select the hardware:</span>');
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
	resrcForm.append(div);

	/**
	 * Ok
	 */
	var okBtn = createButton('Ok');
	okBtn.bind('click', function(event) {
		// Get hardware that was selected
		var hw = $(this).parent().find('select').val();

		// Generate new tab ID
		var newTabId = hw + 'ResourceTab';
		if (!$('#' + newTabId).length) {
			var loader = createLoader(hw + 'ResourceLoader');
			loader = $('<center></center>').append(loader);
			tab.add(newTabId, hw, loader);

			// Load plugin code
			includeJs("js/custom/" + hw + ".js");
			loadResources();
		}

		// Select tab
		tab.select(newTabId);
	});
	resrcForm.append(okBtn);

	tab.add('resourceTab', 'Resources', resrcForm);
}