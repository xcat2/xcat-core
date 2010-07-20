/**
 * Tab constructor
 * 
 * @param tabId
 *            Tab ID
 * @param tabName
 *            Tab name
 * @return Nothing
 */
var Tab = function(tabId) {
	this.tabId = tabId;
	this.tabName = null;
	this.tab = null;
};

/**
 * Initialize the tab
 * 
 * @param tabName
 *            Tab name to initialize
 * @return Nothing
 */
Tab.prototype.init = function() {
	// Create a division containing the tab
	this.tab = $('<div class="tab" id="' + this.tabId + '"></div>');
	var tabList = $('<ul></ul>');
	var tabItem = $('<li><a href="#">Dummy tab item</a></li>');
	tabList.append(tabItem);
	this.tab.append(tabList);

	// Create a template with close button
	var tabs = this.tab
		.tabs( {
			tabTemplate : "<li><a href=\"#{href}\">#{label}</a><span class=\"tab-close ui-icon ui-icon-close\"></span></li>"
		});

	// Remove dummy tab
	this.tab.tabs("remove", 0);

	// Hide tab
	this.tab.hide();

	// Close tab when close button is clicked
	$("#" + this.tabId + " span.tab-close").live("click", function() {
		var index = $('li', tabs).index($(this).parent());

		// Do not remove first tab
		if (index != 0) {
			tabs.tabs('remove', index);
		}
	});
};

/**
 * Return the tab object
 * 
 * @param Nothing
 * @return Object representing the tab
 */
Tab.prototype.object = function() {
	return this.tab;
};

/**
 * Add a new tab
 * 
 * @param newTabId
 *            New tab ID
 * @param newTabName
 *            New tab name
 * @param newTabCont
 *            New tab content
 * @return Nothing
 */
Tab.prototype.add = function(newTabId, newTabName, newTabCont) {
	// Show tab
	if (this.tab.css("display") == "none") {
		this.tab.show();
	}

	var newTab = $('<div class="tab" id="' + newTabId + '"></div>');
	newTab.append(newTabCont);
	this.tab.append(newTab);
	this.tab.tabs("add", "#" + newTabId, newTabName);
};

/**
 * Select a tab
 * 
 * @param id
 *            Tab ID to select
 * @return Nothing
 */
Tab.prototype.select = function(id) {
	this.tab.tabs("select", "#" + id);
};

/**
 * Remove a tab
 * 
 * @param id
 *            Tab ID to remove
 * @return Nothing
 */
Tab.prototype.remove = function(id) {
	// To be continued
};

/**
 * Table constructor
 * 
 * @param tabId
 *            Tab ID
 * @param tabName
 *            Tab name
 * @return Nothing
 */
var Table = function(tableId) {
	if ($('#' + tableId).length) {
		this.tableId = tableId;
		this.table = $('#' + tableId);
	} else {
		this.tableId = tableId;
		this.table = null;
	}
};

/**
 * Initialize the table
 * 
 * @param Headers
 *            Array of table headers
 * @return Nothing
 */
Table.prototype.init = function(headers) {
	// Create a table
	this.table = $('<table id="' + this.tableId + '"></table>');
	var thead = $('<thead></thead>');
	var headRow = $('<tr></tr>');

	// Append headers
	for ( var i in headers) {
		headRow.append('<th>' + headers[i] + '</th>');
	}

	thead.append(headRow);
	this.table.append(thead);

	// Append table body
	var tableBody = $('<tbody></tbody>');
	this.table.append(tableBody);
};

/**
 * Return the table object
 * 
 * @param Nothing
 * @return Object representing the table
 */
Table.prototype.object = function() {
	return this.table;
};

/**
 * Add a row to the table
 * 
 * @param rowCont
 *            Array of table row contents
 * @return Nothing
 */
Table.prototype.add = function(rowCont) {
	// Create table row
	var tableRow = $('<tr></tr>');

	// Create a column for each content
	var tableCol;
	for ( var i in rowCont) {
		tableCol = $('<td></td>');
		tableCol.append(rowCont[i]);
		tableRow.append(tableCol);
	}

	// Append table row to table
	this.table.find('tbody').append(tableRow);
};

/**
 * Add a footer to the table
 * 
 * @param rowCont
 *            Array of table row contents
 * @return Nothing
 */
Table.prototype.addFooter = function(rowCont) {
	// Create table row
	var tableFoot = $('<tfoot></tfoot>');
	tableFoot.append(rowCont);

	// Append table row to table
	this.table.append(tableFoot);
};

/**
 * Remove a row from the table
 * 
 * @return Nothing
 */
Table.prototype.remove = function(id) {
	// To be continued
};

/**
 * Datatable class constructor
 * 
 * @param tabId
 *            Tab ID
 * @param tabName
 *            Tab name
 * @return Nothing
 */
var DataTable = function(tableId) {
	this.dataTableId = tableId;
	this.dataTable = null;
};

/**
 * Initialize the datatable
 * 
 * @param Headers
 *            Array of table headers
 * @return Nothing
 */
DataTable.prototype.init = function(headers) {
	// Create a table
	this.dataTable = $('<table class="datatable" id="' + this.dataTableId + '"></table>');
	var thead = $('<thead></thead>');
	var headRow = $('<tr></tr>');

	// Append headers
	for ( var i in headers) {
		headRow.append('<th>' + headers[i] + '</th>');
	}

	thead.append(headRow);
	this.dataTable.append(thead);

	// Append table body
	var tableBody = $('<tbody></tbody>');
	this.dataTable.append(tableBody);
};

/**
 * Return the datatable object
 * 
 * @param Nothing
 * @return Object representing the table
 */
DataTable.prototype.object = function() {
	return this.dataTable;
};

/**
 * Add a row to the datatable
 * 
 * @param rowCont
 *            Array of table row contents
 * @return Nothing
 */
DataTable.prototype.add = function(rowCont) {
	// Create table row
	var tableRow = $('<tr></tr>');

	// Create a column for each content
	var tableCol;
	for ( var i in rowCont) {
		tableCol = $('<td></td>');
		tableCol.append(rowCont[i]);
		tableRow.append(tableCol);
	}

	// Append table row to table
	this.dataTable.find('tbody').append(tableRow);
};

/**
 * Remove a row from the datatable
 * 
 * @return Nothing
 */
NodesTable.prototype.remove = function(id) {
	// To be continued
};

/**
 * Create status bar
 * 
 * @param barId
 *            Status bar ID
 * @return Status bar
 */
function createStatusBar(barId) {
	var statusBar = $('<div class="statusBar" id="' + barId + '"><div>');
	return statusBar;
}

/**
 * Create info bar
 * 
 * @param msg
 *            Info message
 * @return Info bar
 */
function createInfoBar(msg) {
	var infoBar = $('<div class="ui-state-highlight ui-corner-all">');
	var msg = $('<p class="info"><span class="ui-icon ui-icon-info"></span>' + msg + '</p>');
	infoBar.append(msg);

	return infoBar;
}

/**
 * Create a loader
 * 
 * @param loaderId
 *            Loader ID
 * @return Nothing
 */
function createLoader(loaderId) {
	var loader = $('<img id="' + loaderId + '" src="images/loader.gif"></img>');
	return loader;
}

/**
 * Create a button
 * 
 * @param name
 *            Name of the button
 * @return Nothing
 */
function createButton(name) {
	var button = $('<button aria-disabled="false" role="button" class="ui-button ui-widget ui-state-default ui-corner-all ui-button-text-only" id="button"><span class="ui-button-text">' + name + '</span></button>');
	return button;
}

/**
 * Create a menu
 * 
 * @param items
 *            An array of items to go into the menu
 * @return A division containing the menu
 */
function createMenu(items) {
	var menu = $('<ul class="sf-menu"></ul>');

	// Loop through each item
	for ( var i in items) {
		// Append item to menu
		var item = $('<li></li>');

		// If it is a sub menu
		if (items[i] instanceof Array) {
			// 1st index = Sub menu title
			item.append(items[i][0]);
			// 2nd index = Sub menu
			item.append(items[i][1]);
		} else {
			item.append(items[i]);
		}

		// Do not add border for 1st item
		if (i > 0) {
			item.css( {
				'border-left' : '1px solid #BDBDBD'
			});
		}

		menu.append(item);
	}

	return menu;
}

/**
 * Initialize the page
 * 
 * @return Nothing
 */
function initPage() {
	// Load javascripts
	// TODO: We need to determine which page needs which script
	// and load less
	includeJs("js/jquery/jquery.dataTables.min.js");
	includeJs("js/jquery/jquery.form.js");
	includeJs("js/jquery/jquery.jeditable.js");
	includeJs("js/jquery/jquery.autocomplete.js");
	includeJs("js/jquery/jquery.contextmenu.js");
	includeJs("js/jquery/jquery.cookie.js");
	includeJs("js/jquery/jquery-impromptu.3.0.min.js");
	includeJs("js/jquery/superfish.js");
	includeJs("js/jquery/hoverIntent.js");
	includeJs("js/jquery/jquery.tree.js");
	includeJs("js/configure/configure.js");
	includeJs("js/monitor/monitor.js");
	includeJs("js/nodes/nodes.js");
	includeJs("js/provision/provision.js");
	includeJs("js/update/update.js");

	// Get the page being loaded
	var url = window.location.pathname;
	var page = url.replace('/xcat/', '');

	var headers = $('#header ul li a');

	// Show the page
	$("#content").children().remove();
	if (page == 'index.php') {
		headers.eq(0).css('background-color', '#A9D0F5');
		loadNodesPage();
	} else if (page == 'configure.php') {
		headers.eq(1).css('background-color', '#A9D0F5');
		loadConfigPage();
	} else if (page == 'provision.php') {
		headers.eq(2).css('background-color', '#A9D0F5');
		loadProvisionPage();
	} else if (page == 'monitor.php') {
		headers.eq(3).css('background-color', '#A9D0F5');
		loadMonitorPage();
	} else if (page == 'update.php') {
		headers.eq(4).css('background-color', '#A9D0F5');
		loadUpdatePage();
	} else {
		headers.eq(0).css('background-color', '#A9D0F5');
		loadNodesPage();
	}
}

/**
 * Include javascript file in <head>
 * 
 * @param file
 *            File to include
 * @return Nothing
 */
function includeJs(file) {
	var script = $("head script[src='" + file + "']");

	// If <head> does not contain the javascript
	if (!script.length) {
		// Append the javascript to <head>
		var script = $('<script></script>');
		script.attr( {
			type : 'text/javascript',
			src : file
		})

		$('head').append(script);
	}
}

/**
 * Reset the javascript files in <head> to its original content
 * 
 * @param file
 *            File to include
 * @return Nothing
 */
function resetJs() {
	var scripts = $('head script');
	for ( var i = 0; i < scripts.length; i++) {
		var file = scripts.eq(i).attr('src');
		
		// Remove ipmi, blade, hmc, ivm, fsp javascripts
		if (file == 'js/custom/ipmi.js') {
			scripts.eq(i).remove();
		} else if (file == 'js/custom/blade.js') {
			scripts.eq(i).remove();
		} else if (file == 'js/custom/hmc.js') {
			scripts.eq(i).remove();
		} else if (file == 'js/custom/ivm.js') {
			scripts.eq(i).remove();
		} else if (file == 'js/custom/fsp.js') {
			scripts.eq(i).remove();
		} else if (file == 'js/custom/zvm.js') {
			scripts.eq(i).remove();
		}
	}
}