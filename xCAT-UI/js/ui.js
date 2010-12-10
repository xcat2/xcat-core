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
	var tabs = this.tab.tabs();

	// Remove dummy tab
	this.tab.tabs("remove", 0);

	// Hide tab
	this.tab.hide();
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
 * @param tabId
 *            Tab ID
 * @param tabName
 *            Tab name
 * @param tabCont
 *            Tab content
 * @param closeable
 * 			  Is tab closeable
 * @return Nothing
 */
Tab.prototype.add = function(tabId, tabName, tabCont, closeable) {
	// Show tab
	if (this.tab.css("display") == "none") {
		this.tab.show();
	}

	var newTab = $('<div class="tab" id="' + tabId + '"></div>');
	newTab.append(tabCont);
	this.tab.append(newTab);
	this.tab.tabs("add", "#" + tabId, tabName);
	
	// Append close button
	if (closeable) {
		var header = this.tab.find('ul.ui-tabs-nav a[href="#' + tabId +'"]').parent();
		header.append('<span class=\"tab-close ui-icon ui-icon-close\"></span>');
	
		// Get this tab
		var tabs = this.tab;
		var tabLink = 'a[href="\#' + tabId + '"]';	
		var thisTab = $(tabLink, tabs).parent();
						
		// Close tab when close button is clicked
		thisTab.find('span.tab-close').bind('click', function(event) {
			var tabIndex = ($('li', tabs).index(thisTab));
			
			// Do not remove first tab
			if (tabIndex != 0) {			
				tabs.tabs('remove', tabIndex);
			}
		});
	}
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
	var selectorStr = 'a[href="\#' + id + '"]';	
	var selectTab = $(selectorStr, this.tab).parent();
	var index = ($('li', this.tab).index(selectTab));
	this.tab.tabs("remove", index);
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
	var statusBar = $('<div class="ui-state-highlight ui-corner-all" id="' + barId + '"></div>').css('padding', '10px');
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
	var infoBar = $('<div class="ui-state-highlight ui-corner-all"></div>');
	var msg = $('<p><span class="ui-icon ui-icon-info"></span>' + msg + '</p>');
	infoBar.append(msg);
	return infoBar;
}

/**
 * Create warning bar
 * 
 * @param msg
 *            Warning message
 * @return Warning bar
 */
function createWarnBar(msg) {
	var warnBar = $('<div class="ui-state-error ui-corner-all"></div>');
	var msg = $('<p><span class="ui-icon ui-icon-alert"></span>' + msg + '</p>');
	warnBar.append(msg);
	return warnBar;
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
	// JQuery plugins
	includeJs("js/jquery/jquery.dataTables.min.js");
	includeJs("js/jquery/jquery.form.js");
	includeJs("js/jquery/jquery.jeditable.js");
	includeJs("js/jquery/jquery.autocomplete.js");
	includeJs("js/jquery/jquery.contextmenu.js");
	includeJs("js/jquery/jquery.cookie.js");
	includeJs("js/jquery/superfish.js");
	includeJs("js/jquery/hoverIntent.js");
	includeJs("js/jquery/jquery.jstree.js");
	includeJs("js/jquery/jquery.flot.js");
	includeJs("js/jquery/tooltip.min.js");
	includeJs("js/jquery/jquery.serverBrowser.js");

	// Page plugins
	includeJs("js/configure/configure.js");	
	includeJs("js/monitor/monitor.js");
	includeJs("js/nodes/nodes.js");
	includeJs("js/provision/provision.js");
	
	// Custom plugins
	includeJs("js/custom/blade.js");
	includeJs("js/custom/fsp.js");
	includeJs("js/custom/hmc.js");
	includeJs("js/custom/ipmi.js");
	includeJs("js/custom/ivm.js");
	includeJs("js/custom/zvm.js");
	includeJs("js/custom/customUtils.js");

	// Get the page being loaded
	var url = window.location.pathname;
	var page = url.replace('/xcat/', '');

	var headers = $('#header ul li a');

	// Show the page
	$("#content").children().remove();
	if (page == 'index.php') {
		includeJs("js/jquery/jquery.topzindex.min.js");
		includeJs("js/nodes/nodeset.js");
		includeJs("js/nodes/rnetboot.js");
		includeJs("js/nodes/updatenode.js");
		includeJs("js/nodes/physical.js");
		includeJs("js/nodes/mtm.js");
		headers.eq(0).css('background-color', '#A9D0F5');
		loadNodesPage();
	} else if (page == 'configure.php') {
		includeJs("js/configure/update.js");
		includeJs("js/configure/discover.js");
		headers.eq(1).css('background-color', '#A9D0F5');
		loadConfigPage();
	} else if (page == 'provision.php') {
		includeJs("js/provision/images.js");
		headers.eq(2).css('background-color', '#A9D0F5');
		loadProvisionPage();
	} else if (page == 'monitor.php') {
		includeJs("js/monitor/xcatmon.js");
		includeJs("js/monitor/rmcmon.js");
		includeJs("js/monitor/gangliamon.js");
		headers.eq(3).css('background-color', '#A9D0F5');
		loadMonitorPage();
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
		});

		$('head').append(script);
	}
}

/**
 * Write ajax response to a paragraph
 * 
 * @param rsp
 * 			Ajax response
 * @param pattern
 * 			Pattern to replace with a break
 * @return Paragraph containing ajax response
 */
function writeRsp(rsp, pattern) {
	// Create paragraph to hold ajax response
	var prg = $('<p></p>');
	for ( var i in rsp) {
		if (rsp[i]) {
			// Create regular expression for given pattern
			// Replace pattern with break
			if (pattern) {
				rsp[i] = rsp[i].replace(new RegExp(pattern, 'g'), '<br>');
				prg.append(rsp[i]);
			} else {
				prg.append(rsp[i]);
				prg.append('<br>');
			}			
		}
	}

	return prg;
}

/**
 * Open a dialog and show given message
 * 
 * @param type
 * 			Type of dialog, i.e. warn or info
 * @param msg
 * 			Message to show
 * @return Nothing
 */
function openDialog(type, msg) {
	var msgDialog; 
	if (type == "warn") {
		// Create warning message 
		msgDialog = $('<div class="ui-state-error ui-corner-all">'
				+ '<p><span class="ui-icon ui-icon-alert"></span>' + msg + '</p>'
			+ '</div>');
	} else {
		// Create info message
		msgDialog = $('<div class="ui-state-highlight ui-corner-all">' 
				+ '<p><span class="ui-icon ui-icon-info"></span>' + msg + '</p>'
			+'</div>');
	}
	
	// Open dialog
	msgDialog.dialog({
		modal: true,
		width: 500,
		buttons: {
			"Ok": function(){ 
				$(this).dialog("close");
			}
		}
	});
}
