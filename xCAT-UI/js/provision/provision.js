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
	if ($('#content').children().length) {
		// Do not load again
		return;
	}

	// Create info bar
	var infoBar = createInfoBar('Provision a node');
	$('#content').append(infoBar);

	// Create provision form
	provForm = $('<div class="provision"></div>');
	provForm.append(infoBar);

	// Create provision tab
	var tab = new Tab();
	setProvisionTab(tab);
	tab.init();
	$('#content').append(tab.object());

	// Create radio buttons for platforms
	var hwList =$('<ol>Select a platform to provision:</ol>');
	var ipmi = $('<li><input type="radio" name="hw" value="ipmi" checked/>ipmi</li>');
	var blade = $('<li><input type="radio" name="hw" value="blade"/>blade</li>');
	var hmc = $('<li><input type="radio" name="hw" value="hmc"/>hmc</li>');
	var ivm = $('<li><input type="radio" name="hw" value="ivm"/>ivm</li>');
	var fsp = $('<li><input type="radio" name="hw" value="fsp"/>fsp</li>');
	var zvm = $('<li><input type="radio" name="hw" value="zvm"/>zvm</li>');

	hwList.append(ipmi);
	hwList.append(blade);
	hwList.append(hmc);
	hwList.append(ivm);
	hwList.append(fsp);
	hwList.append(zvm);
	provForm.append(hwList);

	/**
	 * Ok
	 */
	var okBtn = createButton('Ok');
	okBtn.bind('click', function(event) {
		// Get hardware that was selected
		var hw = $(this).parent().find('input[name="hw"]:checked').val();
		
		// Generate new tab ID
		var instance = 0;
		var newTabId = hw + 'ProvisionTab' + instance;
		while ($('#' + newTabId).length) {
			// If one already exists, generate another one
			instance = instance + 1;
			newTabId = hw + 'ProvisionTab' + instance;
		}

		tab.add(newTabId, hw, '', true);

		// Create an instance of the plugin
		var plugin;
		switch(hw) {
			case "blade":
	    		plugin = new bladePlugin();
	    		break;
			case "fsp":
				plugin = new fspPlugin();
				break;
			case "hmc":
				plugin = new hmcPlugin();
				break;
			case "ipmi":
				plugin = new ipmiPlugin();
				break;		
			case "ivm":
				plugin = new ivmPlugin();
				break;
			case "zvm":
				plugin = new zvmPlugin();
				break;
		}
		
		// Select tab
		tab.select(newTabId);
		plugin.loadProvisionPage(newTabId);
	});
	provForm.append(okBtn);

	tab.add('provisionTab', 'Provision', provForm, false);
}