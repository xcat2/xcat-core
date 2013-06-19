/**
 * Global variables
 */
var configTabs; // Config tabs
var configDatatables = new Object(); // Datatables on the config page

/**
 * Set the datatable
 * 
 * @param id The ID of the datatable
 * @param obj Datatable object
 */
function setConfigDatatable(id, obj) {
    configDatatables[id] = obj;
}

/**
 * Get the datatable with the given ID
 * 
 * @param id The ID of the datatable
 * @return Datatable object
 */
function getConfigDatatable(id) {
    return configDatatables[id];
}

/**
 * Set the configure tab
 * 
 * @param obj Tab object
 */
function setConfigTab(obj) {
    configTabs = obj;
}

/**
 * Get the configure tab
 * 
 * @param Nothing
 * @return Tab object
 */
function getConfigTab() {
    return configTabs;
}

/**
 * Load configure page
 */
function loadConfigPage() {
    // If the configure page has already been loaded
    if ($('#content').children().length) {
        // Do not reload configure page
        return;
    }

    // Create configure tab
    var tab = new Tab();
    setConfigTab(tab);
    tab.init();
    $('#content').append(tab.object());

    // Create loader
    var loader = $('<center></center>').append(createLoader());

    // Add tab to configure xCAT tables
    tab.add('configTablesTab', 'Tables', loader, false);

    // Add the update tab
    tab.add('updateTab', 'Update', '', false);
    
    // Add the self-service tab
    tab.add('usersTab', 'Users', '', false);
    
    // Add the discover tab
    tab.add('discoverTab', 'Discover', '', false);
    
    // Add the self-service tab
    tab.add('serviceTab', 'Service', '', false);

    // Get list of tables and their descriptions
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'tabdump',
            tgt : '',
            args : '-d',
            msg : ''
        },

        success : loadTableNames
    });

    // Do not load everything at once
    // Load when tab is shown
    tab.object().bind('tabsshow', function(event, ui) {
    	if ($(ui.panel).children().length) {
    		return;
    	}
    	
        if (ui.index == 1) {
        	loadUpdatePage();
        } else if (ui.index == 2) {
        	loadUserPage();
        } else if (ui.index == 3) {
        	loadDiscoverPage();
        } else if (ui.index == 4) {
        	loadServicePage();
        } 
    });
}

/**
 * Load xCAT database table names and their descriptions
 * 
 * @param data Data returned from HTTP request
 */
function loadTableNames(data) {
    // Get output
    var tables = data.rsp;

    // Remove loader
    var tabId = 'configTablesTab';
    $('#' + tabId).find('img').hide();

    // Create a groups division
    var tablesDIV = $('<div id="configTable"></div>');
    $('#' + tabId).append(tablesDIV);

    // Create info bar
    var infoBar = createInfoBar('Select a table to view or edit.');
    tablesDIV.append(infoBar);
    
    // Create a list for the tables
    var list = $('<ul></ul>');
    // Loop through each table
    for ( var i = 0; i < tables.length; i++) {
        // Create a link for each table
        var args = tables[i].split(':');
        var link = $('<a style="color: blue;" id="' + args[0] + '">' + args[0] + '</a>');

        // Open table on click
        link.bind('click', function(e) {
            // Get table ID that was clicked
            var id = (e.target) ? e.target.id : e.srcElement.id;

            // Create loader
            var loader = $('<center></center>').append(createLoader());

            // Add a new tab for this table
            var configTab = getConfigTab();
            if (!$('#' + id + 'Tab').length) {
                configTab.add(id + 'Tab', id, loader, true);

                // Get contents of selected table
                $.ajax({
                    url : 'lib/cmd.php',
                    dataType : 'json',
                    data : {
                        cmd : 'tabdump',
                        tgt : '',
                        args : id,
                        msg : id
                    },

                    success : loadTable
                });
            }

            // Select new tab
            configTab.select(id + 'Tab');
        });

        var item = $('<li></li>');
        item.append(link);

        // Append the table description
        item.append(': ' + args[1]);

        // Append item to list
        list.append(item);
    }

    tablesDIV.append(list);
}

/**
 * Load a given database table
 * 
 * @param data Data returned from HTTP request
 */
function loadTable(data) {
    // Get response
    var rsp = data.rsp;
    // Get table ID
    var id = data.msg;

    // Remove loader
    var tabId = id + 'Tab';
    $('#' + tabId).find('img').remove();

    // Create info bar
    var infoBar = createInfoBar('Click on a cell to edit. Click outside the table to write to the cell. Once you are satisfied with how the table looks, click on Save.');
    $('#' + tabId).append(infoBar);

    // Create action bar
    var actionBar = $('<div></div>');
    $('#' + tabId).append(actionBar);

    // Get table headers
    var args = rsp[0].replace('#', '');
    var headers = args.split(',');

    // Create container for original table contents
    var origCont = new Array(); // Original table content
    origCont[0] = rsp[0].split(','); // Headers

    // Create container for new table contents
    var newCont = new Object();
    var tmp = new Object();
    tmp[0] = '#' + headers[0]; // Put a # in front of the header
    for ( var i = 1; i < headers.length; i++) {
        tmp[i] = headers[i];
    }
    newCont[0] = tmp;

    // Create a new datatable
    var tableId = id + 'Datatable';
    var table = new DataTable(tableId);

    // Add column for the remove row button
    headers.unshift('');
    table.init(headers);
    headers.shift();

    // Append datatable to tab
    $('#' + tabId).append(table.object());

    // Add table rows
    // Start with the 2nd row (1st row is the headers)
    for ( var i = 1; i < rsp.length; i++) {
        // Split into columns
        var cols = rsp[i].split(',');

        // Go through each column
        for ( var j = 0; j < cols.length; j++) {

            // If the column is not complete
            if (cols[j].count('"') == 1) {
                while (cols[j].count('"') != 2) {
                    // Merge this column with the adjacent one
                    cols[j] = cols[j] + "," + cols[j + 1];

                    // Remove merged row
                    cols.splice(j + 1, 1);
                }
            }

            // Replace quote
            cols[j] = cols[j].replace(new RegExp('"', 'g'), '');
        }

        // Add remove button
        cols.unshift('<span class="ui-icon ui-icon-close" onclick="deleteRow(this)"></span>');

        // Add row
        table.add(cols);

        // Save original table content
        origCont[i] = cols;
    }

    // Turn table into datatable
    var dTable = $('#' + id + 'Datatable').dataTable({        
        'iDisplayLength': 50,
        'bLengthChange': false,
        "bScrollCollapse": true,
        "sScrollY": "400px",
        "sScrollX": "110%",
        "bAutoWidth": true,
        "oLanguage": {
            "oPaginate": {
              "sNext": "",
              "sPrevious": ""
            }
        }
    });

    /**
     * Enable editable columns
     */
    // Do not make 1st column editable
    $('#' + tableId + ' td:not(td:nth-child(1))').editable(
        function(value, settings) {
            // Get column index
            var colPos = this.cellIndex;
            // Get row index
            var rowPos = dTable.fnGetPosition(this.parentNode);

            // Update datatable
            dTable.fnUpdate(value, rowPos, colPos);

            return (value);
        }, {
            onblur : 'submit', // Clicking outside editable area submits changes
            type : 'textarea',
            placeholder: ' ',
            height : '30px' // The height of the text area
        });
    
    // Create action bar
    var actionBar = $('<div class="actionBar"></div>');
    
    var saveLnk = $('<a>Save</a>');
    saveLnk.click(function() {
        // Get table ID and name
        var tableId = $(this).parents('.dataTables_wrapper').attr('id').replace('_wrapper', '');
        var tableName = tableId.replace('Datatable', '');
        
        // Get datatable
        var dTable = $('#' + tableId).dataTable();
        // Get the nodes from the table
        var dRows = dTable.fnGetNodes();

        // Go through each row
        for ( var i = 0; i < dRows.length; i++) {
            // If there is row with values
            if (dRows[i]) {
                // Go through each column
                // Ignore the 1st column because it is a button
                var cols = dRows[i].childNodes;
                var vals = new Object();
                for ( var j = 1; j < cols.length; j++) {
                    var val = cols.item(j).firstChild.nodeValue;
                    
                    // Insert quotes
                    if (val == ' ') {
                        vals[j - 1] = '';
                    } else {
                        vals[j - 1] = val;
                    }
                }

                // Save row
                newCont[i + 1] = vals;
            }
        }
        
        // Update xCAT table
        $.ajax({
            type : 'POST',
            url : 'lib/tabRestore.php',
            dataType : 'json',
            data : {
                table : tableName,
                cont : newCont
            },
            success : function(data) {
                // Create info message
                var dialog = $('<div></div>').append(createInfoBar('Changes saved!'));
                
                // Open dialog
                dialog.dialog({
                    modal: true,
                    title: 'Info',
                    width: 400,
                    buttons: {
                        "Ok": function(){ 
                            $(this).dialog("close");
                        }
                    }
                });
            }
        });
    });
    
    var undoLnk = $('<a>Undo</a>');
    undoLnk.click(function() {
        // Get table ID
        var tableId = $(this).parents('.dataTables_wrapper').attr('id').replace('_wrapper', '');
        
        // Get datatable
        var dTable = $('#' + tableId).dataTable();
        
        // Clear entire datatable
        dTable.fnClearTable();

        // Add original content back into datatable
        for ( var i = 1; i < origCont.length; i++) {
            dTable.fnAddData(origCont[i], true);
        }

        // Enable editable columns (again)
        // Do not make 1st column editable
        $('#' + tableId + ' td:not(td:nth-child(1))').editable(
            function(value, settings) {
                // Get column index
                var colPos = this.cellIndex;
                // Get row index
                var rowPos = dTable.fnGetPosition(this.parentNode);

                // Update datatable
                dTable.fnUpdate(value, rowPos, colPos);

                return (value);
            }, {
                onblur : 'submit', // Clicking outside editable area submits changes
                type : 'textarea',
                placeholder: ' ',
                height : '30px' // The height of the text area
            });
    });
    
    var addLnk = $('<a>Add row</a>');
    addLnk.click(function() {
        // Create an empty row
        var row = new Array();

        /**
         * Remove button
         */
        row.push('<span class="ui-icon ui-icon-close" onclick="deleteRow(this)"></span>');
        for ( var i = 0; i < headers.length; i++) {
            row.push('');
        }

        // Get table ID and name
        var tableId = $(this).parents('.dataTables_wrapper').attr('id').replace('_wrapper', '');
        
        // Get datatable
        var dTable = $('#' + tableId).dataTable();
        
        // Add the row to the data table
        dTable.fnAddData(row);

        // Enable editable columns (again)
        // Do not make 1st column editable
        $('#' + tableId + ' td:not(td:nth-child(1))').editable(
            function(value, settings) {
                // Get column index
                var colPos = this.cellIndex;
                // Get row index
                var rowPos = dTable.fnGetPosition(this.parentNode);

                // Update datatable
                dTable.fnUpdate(value, rowPos, colPos);

                return (value);
            }, {
                onblur : 'submit', // Clicking outside editable area submits changes
                type : 'textarea',
                placeholder: ' ',
                height : '30px' // The height of the text area
            });
    });
    
    // Create an action menu
    var actionsMenu = createMenu([saveLnk, undoLnk, addLnk]);
    actionsMenu.superfish();
    actionsMenu.css('display', 'inline-block');
    actionBar.append(actionsMenu);
    
    // Set correct theme for action menu
    actionsMenu.find('li').hover(function() {
        setMenu2Theme($(this));
    }, function() {
        setMenu2Normal($(this));
    });
    
    // Create a division to hold actions menu
    var menuDiv = $('<div id="' + id + 'Datatable_menuDiv" class="menuDiv"></div>');
    $('#' + id + 'Datatable_wrapper').prepend(menuDiv);
    menuDiv.append(actionBar);    
    $('#' + id + 'Datatable_filter').appendTo(menuDiv);
}

/**
 * Delete a row in the data table
 * 
 * @param obj The object that was clicked
 */
function deleteRow(obj) {
    // Get table ID
    var tableId = $(obj).parents('table').attr('id');

    // Get datatable
    var dTable = $('#' + tableId).dataTable();

    // Get all nodes within the datatable
    var rows = dTable.fnGetNodes();
    // Get target row
    var tgtRow = $(obj).parent().parent().get(0);

    // Find the target row in the datatable
    for ( var i in rows) {
        // If the row matches the target row
        if (rows[i] == tgtRow) {
            // Remove row
            dTable.fnDeleteRow(i, null, true);
            break;
        }
    }
}

/**
 * Count the number of occurrences of a specific character in a string
 * 
 * @param c Character to count
 * @return The number of occurrences
 */
String.prototype.count = function(c) {
    return (this.length - this.replace(new RegExp(c, 'g'), '').length)/c.length;
};

/**
 * Update dialog
 * 
 * @param data HTTP request data
 */
function updatePanel(data) {
    var dialogId = data.msg;
    var infoMsg;

    // Create info message
    if (jQuery.isArray(data.rsp)) {
        infoMsg = '';
        for (var i in data.rsp) {
            infoMsg += data.rsp[i] + '</br>';
        }
    } else {
        infoMsg = data.rsp;
    }
    
    // Create info bar with close button
    var infoBar = $('<div class="ui-state-highlight ui-corner-all"></div>').css('margin', '5px 0px');
    var icon = $('<span class="ui-icon ui-icon-info"></span>').css({
        'display': 'inline-block',
        'margin': '10px 5px'
    });
    
    // Create close button to close info bar
    var close = $('<span class="ui-icon ui-icon-close"></span>').css({
        'display': 'inline-block',
        'float': 'right'
    }).click(function() {
        $(this).parent().remove();
    });
    
    var msg = $('<pre>' + infoMsg + '</pre>').css({
        'display': 'inline-block',
        'width': '85%'
    });
    
    infoBar.append(icon, msg, close);    
    infoBar.prependTo($('#' + dialogId));
}