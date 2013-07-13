/**
 * Tab constructor
 * 
 * @param tabId Tab ID
 * @param tabName Tab name
 */
var Tab = function(tabId) {
    this.tabId = tabId;
    this.tabName = null;
    this.tab = null;
};

/**
 * Initialize the tab
 * 
 * @param tabName Tab name to initialize
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

    tabs.bind('tabsselect', function(event, ui){
        // Save the order tabs were selected
        var order;
        if ($.cookie('tabindex_history')) {
            order = $.cookie('tabindex_history').split(',');
            order[1] = order[0];    // Set index 1 to last selected tab
            order[0] = ui.index;    // Set index 0 to currently selected tab        
        } else {
            // Create an array to track the tab selected
            order = new Array;
            order[0] = ui.index;
            order[1] = ui.index;
        }
        
        $.cookie('tabindex_history', order);
    });

    // Remove dummy tab
    this.tab.tabs("remove", 0);

    // Hide tab
    this.tab.hide();
};

/**
 * Return the tab object
 * 
 * @return Object representing the tab
 */
Tab.prototype.object = function() {
    return this.tab;
};

/**
 * Add a new tab
 * 
 * @param tabId Tab ID
 * @param tabName Tab name
 * @param tabCont Tab content
 * @param closeable Is tab closeable
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
                // Go back to last tab if user is trying to close currently selected tab
                if (tabs.tabs('option', 'selected') == tabIndex) {
                    // Get last selected tab from history
                    var order = $.cookie('tabindex_history').split(',');
                    if (order[1]) {
                        tabs.tabs('select', parseInt(order[1]));
                    } else {
                        tabs.tabs('select', 0);
                    }    
                }                            
                
                tabs.tabs('remove', tabIndex);
            }
        });
    }
};

/**
 * Select a tab
 * 
 * @param id Tab ID to select
 */
Tab.prototype.select = function(id) {
    this.tab.tabs("select", "#" + id);
};

/**
 * Remove a tab
 * 
 * @param id Tab ID to remove
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
 * @param tabId Tab ID
 * @param tabName Tab name
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
 * @param Headers Array of table headers
 */
Table.prototype.init = function(headers) {
    // Create a table
    this.table = $('<table id="' + this.tableId + '"></table>');
    var thead = $('<thead class="ui-widget-header"></thead>');
    var headRow = $('<tr></tr>');

    // Append headers
    for (var i in headers) {
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
 * @return Object representing the table
 */
Table.prototype.object = function() {
    return this.table;
};

/**
 * Add a row to the table
 * 
 * @param rowCont Array of table row contents
 */
Table.prototype.add = function(rowCont) {
    // Create table row
    var tableRow = $('<tr></tr>');

    // Create a column for each content
    var tableCol;
    for (var i in rowCont) {
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
 * @param rowCont Array of table row contents
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
 */
Table.prototype.remove = function(id) {
    // To be continued
};

/**
 * Datatable class constructor
 * 
 * @param tabId Tab ID
 * @param tabName Tab name
 */
var DataTable = function(tableId) {
    this.dataTableId = tableId;
    this.dataTable = null;
};

/**
 * Initialize the datatable
 * 
 * @param Headers Array of table headers
 */
DataTable.prototype.init = function(headers) {
    // Create a table
    this.dataTable = $('<table class="datatable" id="' + this.dataTableId + '"></table>');
    var thead = $('<thead class="ui-widget-header"></thead>');
    var headRow = $('<tr></tr>');

    // Append headers
    for (var i in headers) {
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
 * @return Object representing the table
 */
DataTable.prototype.object = function() {
    return this.dataTable;
};

/**
 * Add a row to the datatable
 * 
 * @param rowCont Array of table row contents
 */
DataTable.prototype.add = function(rowCont) {
    // Create table row
    var tableRow = $('<tr></tr>');

    // Create a column for each content
    var tableCol;
    for (var i in rowCont) {
        tableCol = $('<td></td>');
        tableCol.append(rowCont[i]);
        tableRow.append(tableCol);
    }

    // Append table row to table
    this.dataTable.find('tbody').append(tableRow);
};

/**
 * Create status bar
 * 
 * @param barId Status bar ID
 */
function createStatusBar(barId) {
	// Do not change the background color or color! This is handled by the theme
	// the user selects.
    var statusBar = $('<div class="ui-state-highlight ui-corner-all" id="' + barId + '"></div>').css({
        'margin-bottom': '5px',
        'min-height': '30px',
    	'max-height': '150px',
    	'overflow': 'auto'
    });
    
    // Create info icon
    var icon = $('<span class="ui-icon ui-icon-circle-check"></span>').css({
        'display': 'inline-block',
        'margin': '10px 5px',
        'vertical-align': 'top'
    });
    
    // Create message section
    var msg = $('<div></div>').css({
        'display': 'inline-block',
        'margin': '10px 0px',
        'width': '90%'
    });
    
    // Create hide button
    var hide = $('<span class="ui-icon ui-icon-minus"></span>').css({
        'display': 'inline-block',
        'float': 'right',
        'cursor': 'pointer'
    }).click(function() {
        // Remove info box on-click
        $(this).parent().hide();
    });
    
    statusBar.append(icon);
    statusBar.append(msg);
    statusBar.append(hide);
    return statusBar;
}

/**
 * Create info bar
 * 
 * @param msg Info message
 * @return Info bar
 */
function createInfoBar(msg) {
	// Do not change the background color or color! This is handled by the theme
	// the user selects.
    var infoBar = $('<div class="ui-state-highlight ui-corner-all"></div>').css({
    	'margin': '5px 0px'
    });
    var icon = $('<span class="ui-icon ui-icon-info"></span>').css({
        'display': 'inline-block',
        'margin': '10px 5px'
    });
    var barMsg = $('<p>' + msg + '</p>').css({
        'display': 'inline-block',
        'width': '90%'
    });
    
    infoBar.append(icon);
    infoBar.append(barMsg);
    return infoBar;
}

/**
 * Create warning bar
 * 
 * @param msg Warning message
 * @return Warning bar
 */
function createWarnBar(msg) {
    var warnBar = $('<div class="ui-state-error ui-corner-all"></div>');
    var icon = $('<span class="ui-icon ui-icon-alert"></span>').css({
        'display': 'inline-block',
        'margin': '10px 5px'
    });
    var barMsg = $('<p>' + msg + '</p>').css({
        'display': 'inline-block',
        'width': '90%'
    });
    
    warnBar.append(icon);
    warnBar.append(barMsg);
    return warnBar;
}

/**
 * Create a loader
 * 
 * @param loaderId Loader ID
 */
function createLoader(loaderId) {
    var loader = $('<img id="' + loaderId + '" src="images/loader.gif"></img>');
    return loader;
}

/**
 * Create a button
 * 
 * @param name Name of the button
 */
function createButton(name) {
    var button = $('<button>' + name + '</button>').button();
    return button;
}

/**
 * Create a menu
 * 
 * @param items An array of items to go into the menu
 * @return A division containing the menu
 */
function createMenu(items) {
    var menu = $('<ul class="sf-menu ui-state-default"></ul>');

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
                
        menu.append(item);
    }
    
    return menu;
}

/**
 * Initialize the page
 */
function initPage() {    
    // Load theme
    var theme = $.cookie('xcat_theme');
    if (theme) {
        switch (theme) {
            case 'cupertino':
                includeCss("css/themes/jquery-ui-cupertino.css");
                break;
            case 'dark_hive':
                includeCss("css/themes/jquery-ui-dark_hive.css");
                break;
            case 'redmond':
                includeCss("css/themes/jquery-ui-redmond.css");
                break;
            case 'start':
                includeCss("css/themes/jquery-ui-start.css");
                break;
            case 'sunny':
                includeCss("css/themes/jquery-ui-sunny.css");
                break;
            case 'ui_dark':
                includeCss("css/themes/jquery-ui-ui_darkness.css");
                break;
            default:
                includeCss("css/themes/jquery-ui-start.css");
        }                
    } else {
        includeCss("css/themes/jquery-ui-start.css");
    }

    // Load jQuery stylesheets
    includeCss("css/jquery.dataTables.css");
    includeCss("css/superfish.css");
    // includeCss("css/jstree.css");
    includeCss("css/jquery.jqplot.css");
    
    // Load custom stylesheet
    includeCss("css/style.css");
    
    // JQuery plugins
    includeJs("js/jquery/jquery.dataTables.min.js");
    includeJs("js/jquery/jquery.form.min.js");
    includeJs("js/jquery/jquery.jeditable.min.js");
    includeJs("js/jquery/jquery.contextmenu.min.js");
    includeJs("js/jquery/superfish.min.js");
    includeJs("js/jquery/hoverIntent.min.js");
    // includeJs("js/jquery/jquery.jstree.min.js");
    includeJs("js/jquery/tooltip.min.js");
    includeJs("js/jquery/jquery.serverBrowser.min.js");
    includeJs("js/jquery/jquery.jqplot.min.js");
    includeJs("js/jquery/jqplot.pieRenderer.min.js");
    includeJs("js/jquery/jqplot.barRenderer.min.js");
    includeJs("js/jquery/jqplot.pointLabels.min.js");
    includeJs("js/jquery/jqplot.categoryAxisRenderer.min.js");
    includeJs("js/jquery/jqplot.dateAxisRenderer.min.js");
    includeJs("js/jquery/jquery.topzindex.min.js");
    
    // Page plugins
    includeJs("js/configure/configure.js");    
    includeJs("js/monitor/monitor.js");
    includeJs("js/nodes/nodes.js");
    includeJs("js/provision/provision.js");
    
    // Custom plugins
    includeJs("js/custom/esx.js");
    includeJs("js/custom/kvm.js");
    includeJs("js/custom/blade.js");
    includeJs("js/custom/ipmi.js");
    includeJs("js/custom/zvm.js");
    includeJs("js/custom/hmc.js");
    includeJs("js/custom/customUtils.js");

    // Enable settings link     
    $('#xcat_settings').click(function() {
        openSettings();
    });
    
    // Set header to theme
    var background = '', color = '';
    var theme = $.cookie('xcat_theme');
    if (theme) {
        switch (theme) {
            case 'cupertino':
                background = '#3BAAE3';
                color = 'white';
                break;
            case 'dark_hive':
                background = '#0972A5';
                break;
            case 'redmond':
                background = '#F5F8F9';
                color = '#E17009';
                break;
            case 'start':
                background = '#6EAC2C';
                break;
            case 'sunny':
                background = 'white';
                color = '#0074C7';
                break;
            case 'ui_dark':
                background = '#F58400';
                break;
            default:
                background = '#6EAC2C';
        }                
    } else {
        background = '#6EAC2C';
    }
    
    $('#header').addClass('ui-state-default');
    $('#header').css('border', '0px');
    
    // Set theme to user span
    $('#login_user').css('color', color);
    
    // Style for selected page
    var style = {
        'background-color': background,
        'color': color
    };

    // Get the page being loaded
    var url = window.location.pathname;
    var page = url.replace('/xcat/', '');
    var headers = $('#header ul li a');
        
    // Show the page
    $("#content").children().remove();
    if (page == 'configure.php') {
        includeJs("js/configure/update.js");
        includeJs("js/configure/discover.js");
        includeJs("js/configure/service.js");
        includeJs("js/configure/users.js");
        headers.eq(1).css(style);
        loadConfigPage();
    } else if (page == 'provision.php') {
        includeJs("js/provision/images.js");
        headers.eq(2).css(style);
        loadProvisionPage();
    } else if (page == 'monitor.php') {
        includeJs("js/monitor/xcatmon.js");
        includeJs("js/monitor/rmcmon.js");
        includeJs("js/monitor/gangliamon.js");
        headers.eq(3).css(style);
        loadMonitorPage();
    } else if (page == 'help.php') {
        includeJs("js/help/help.js");
        headers.eq(4).css(style);
        loadHelpPage();
    } else {
        // Load nodes page by default
        includeJs("js/nodes/nodeset.js");
        includeJs("js/nodes/rnetboot.js");
        includeJs("js/nodes/updatenode.js");
        includeJs("js/nodes/physical.js");
        includeJs("js/nodes/mtm.js");
        includeJs("js/nodes/rscan.js");
        headers.eq(0).css(style);
        loadNodesPage();
    }
}

/**
 * Include javascript file in <head>
 * 
 * @param file File to include
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
 * Include CSS link in <head>
 * 
 * @param file File to include
 */
function includeCss(file) {
    var link = $("head link[href='" + file + "']");

    // If <head> does not contain the link
    if (!link.length) {
        // Append the CSS link to <head>
        var link = $('<link>');
        link.attr( {
            type : 'text/css',
            rel : 'stylesheet',
            href : file
        });

        $('head').append(link);
    }
}

/**
 * Write ajax response to a paragraph
 * 
 * @param rsp Ajax response
 * @param pattern Pattern to replace with a break
 * @return Paragraph containing ajax response
 */
function writeRsp(rsp, pattern) {
    // Create paragraph to hold ajax response
    var prg = $('<pre></pre>');
    
    for ( var i in rsp) {
        if (rsp[i]) {
            // Create regular expression for given pattern
            // Replace pattern with break
            if (pattern) {
                rsp[i] = rsp[i].replace(new RegExp(pattern, 'g'), '<br/>');
                prg.append(rsp[i]);
            } else {
                prg.append(rsp[i]);
                prg.append('<br/>');
            }            
        }
    }

    return prg;
}

/**
 * Open a dialog and show given message
 * 
 * @param type Type of dialog, i.e. warn or info
 * @param msg Message to show
 */
function openDialog(type, msg) {
    var msgDialog = $('<div></div>');
    var title = "";
    if (type == "warn") {
        // Create warning message 
    	msgDialog.append(createWarnBar(msg));
    	title = "Warning";
    } else {
        // Create info message
    	msgDialog.append(createInfoBar(msg));
    	title = "Info";
    }
    
    // Open dialog
    msgDialog.dialog({
    	title: title,
        modal: true,
        close: function(){
            $(this).remove();
        },
        width: 500,
        buttons: {
            "Ok": function(){ 
                $(this).dialog("close");
            }
        }
    });
}

/**
 * Create an iframe to hold the output of an xCAT command
 * 
 * @param src The URL of the document to show in the iframe
 * @return Info box containing the iframe
 */
function createIFrame(src) {
    // Put an iframe inside an info box
    var infoBar = $('<div class="ui-state-highlight ui-corner-all"></div>').css({
        'margin-bottom': '5px'
    });
    
    // Create info and close icons
    var icon = $('<span class="ui-icon ui-icon-info"></span>').css({
        'display': 'inline-block',
        'margin': '10px 5px'
    });
    var close = $('<span class="ui-icon ui-icon-close"></span>').css({
        'display': 'inline-block',
        'float': 'right',
        'margin': '10px 5px'
    }).click(function() {
        // Remove info box on-click
        $(this).parent().remove();
    });
        
    var iframe = $('<iframe></iframe>').attr('src', src).css({
        'display': 'block',
        'border': '0px',
        'margin': '10px',
        'width': '100%'
    });
    
    var loader = createLoader('iLoader').css({
        'display': 'block',
        'margin': '10px 0px'
    });
        
    infoBar.append(icon);
    infoBar.append($('<div style="display: inline-block; width: 90%;"></div>').append(loader, iframe));
    infoBar.append(close);
    
    // Remove loader when done
    iframe.load(function() {
        loader.remove();
    });
    
    return infoBar;
}


/**
 * Open dialog to set xCAT UI settings
 */
function openSettings() {
    // Create form to add node range
    var dialog = $('<div class="form"></div>');
    var info = createInfoBar('Select from the following options');
    dialog.append(info);
    
    var style = {
        'color': 'blue',
        'cursor': 'pointer',
        'padding': '5px'
    };
    
    var changeThemeOption = $('<div><center><a style="color: blue;">Change xCAT theme</a></center></div>').css(style);
    dialog.append(changeThemeOption);
    
    var changePasswordOption = $('<div><center><a style="color: blue;">Change password</a></center></div>').css(style);
    dialog.append(changePasswordOption);
    
    // Open form as a dialog
    dialog.dialog({
        modal: true,
        close: function(){
            $(this).remove();
        },
        title: 'Settings',
        width: 400,
        buttons: {
            "Cancel": function(){
                $(this).dialog("close");
            }
        }
    });
    
    // Bind to click event
    changeThemeOption.click(function() {
        dialog.dialog("close");
        changeTheme();
    });
    
    changePasswordOption.click(function() {
        dialog.dialog("close");
        changePassword();
    });
}

/**
 * Open dialog to change xCAT theme
 */
function changeTheme() {
    // Create form to add node range
    var dialog = $('<div class="form"></div>');
    var info = createInfoBar('Select the xCAT theme you desire');
    dialog.append(info);
    
    // Create select drop down for themes
    var oList = $('<ol></ol>');
    oList.append($('<li><input type="radio" name="theme" value="cupertino">Cupertino</li>'));
    oList.append($('<li><input type="radio" name="theme" value="dark_hive">Dark Hive</li>'));
    oList.append($('<li><input type="radio" name="theme" value="redmond">Redmond</li>'));
    oList.append($('<li><input type="radio" name="theme" value="start">Start (default)</li>'));
    oList.append($('<li><input type="radio" name="theme" value="sunny">Sunny</li>'));
    oList.append($('<li><input type="radio" name="theme" value="ui_dark">UI Darkness</li>'));
    dialog.append(oList);
    
    if ($.cookie('xcat_theme')) {
        // Select theme
        oList.find('input[value="' + $.cookie('xcat_theme') + '"]').attr('checked', true);
    } else {
        oList.find('input[value="start"]').attr('checked', true);
    }

    // Open form as a dialog
    dialog.dialog({
        modal: true,
        close: function(){
            $(this).remove();
        },
        title: 'xCAT Theme',
        width: 400,
        buttons: {
            "Ok": function(){
                // Save selected theme
                var theme = $(this).find('input[name="theme"]:checked').val();
                $.cookie('xcat_theme', theme);    // Do not expire cookie, keep it as long as possible
                
                // Show instructions to apply theme
                $(this).empty();
                var info = createInfoBar('You will need to reload this page in order for changes to take effect');
                $(this).append(info);
                
                // Only show close button
                $(this).dialog("option", "buttons", {
                    "Close" : function() {
                        $(this).dialog( "close" );
                    }
                });
            },
            "Cancel": function(){
                $(this).dialog( "close" );
            }
        }
    });
}

/**
 * Open dialog to change user password
 */
function changePassword() {
    // Create form to add node range
    var dialog = $('<div id="changePassword" class="form"></div>');
    var info = createInfoBar('Change your password');
    dialog.append(info);
    
    dialog.append('<div><label>New password:</label><input type="password" name="newPassword"/></div>');
    dialog.append('<div><label>Confirm password:</label><input type="password" name="confirmPassword"/></div>');
    
    // Open form as a dialog
    dialog.dialog({
        modal: true,
        close: function(){
            $(this).remove();
        },
        title: 'Change Password',
        width: 400,
        buttons: {
            "Ok": function(){
                // Remove any warning messages
                $(this).find('.ui-state-error').remove();
                
                var errorMessage = "";
                
                // Check each input is provided
                $('#changePassword input').each(function() {
                    if (!$(this).val()) {
                        errorMessage = "Please provide a value for each missing input!";
                    }
                });
                
                // Do not continue if error found
                if (errorMessage) {
                    dialog.prepend(createWarnBar(errorMessage));
                    return;
                }
                
                // Check new and confirm passwords match
                var user = $.cookie('xcat_username');
                var newPassword = $('#changePassword input[name="newPassword"]').val();
                var confirmPassword = $('#changePassword input[name="confirmPassword"]').val();
                if (newPassword != confirmPassword) {
                    dialog.prepend(createWarnBar("Please confirm new password!"));
                    return;
                }
                
                // Change dialog buttons
                $('#changePassword').dialog('option', 'buttons', {
                    'Close':function(){
                        $('#changePassword').dialog('destroy').remove();
                    }
                });
                
                // Send request to change password
                var url = window.location.pathname;
                var page = url.replace('/xcat/', '');
                var url = 'lib/cmd.php';
                // Service portal does not have access to cmd.php
                if (page == 'service.php')
                    url = 'lib/srv_cmd.php';
                $.ajax( {
                    url : url,
                    dataType : 'json',
                    data : {
                        cmd : 'webrun',
                        tgt : '',
                        args : 'passwd;' + user + ';' + newPassword,
                        msg : ''
                    },
                    
                    success : function (data) {
                        // Show response message
                        var rspMessage = "";
                        for (var i in data.rsp)
                            rspMessage += data.rsp[i] + "<br/>";
                        
                         $('#changePassword').prepend(createInfoBar(rspMessage));
                    }
                });
            },
            "Cancel": function(){
                $(this).dialog( "close" );
            }
        }
    });
}

/**
 * Adjust datatable column size
 * 
 * @param tableId Table ID
 */
function adjustColumnSize(tableId) {
	var dTable = $('#' + tableId).dataTable();
	dTable.fnAdjustColumnSizing();
}

/**
 * Set menu theme
 * 
 * @param menu Menu object
 */
function setMenu2Theme(menu) {
    // On hover
    var background = '', color = '';
    var theme = $.cookie('xcat_theme');
    if (theme) {
        switch (theme) {
            case 'cupertino':
                background = '#3BAAE3';
                color = 'white';
                break;
            case 'dark_hive':
                background = '#0972A5';
                break;
            case 'redmond':
                background = '#F5F8F9';
                color = '#E17009';
                break;
            case 'start':
                background = '#6EAC2C';
                break;
            case 'sunny':
                background = 'white';
                color = '#0074C7';
                break;
            case 'ui_dark':
                background = '#F58400';
                break;
            default:
                background = '#6EAC2C';
        }                
    } else {
        background = '#6EAC2C';
    }
    
    menu.css('background', background);
    menu.find('a:eq(0)').css('color', color);
}

/**
 * Set menu back to normal before applying theme
 * 
 * @param menu Menu object
 */
function setMenu2Normal(menu) {
    // Change back to normal
    menu.css('background', '');
    menu.find('a:eq(0)').css('color', '');
}

/**
 * Get nodes that are checked in a given datatable
 * 
 * @param datatableId The datatable ID
 * @return Nodes that were checked
 */
function getNodesChecked(datatableId) {
    var tgts = '';

    // Get nodes that were checked
    var nodes = $('#' + datatableId + ' input[type=checkbox]:checked');
    for (var i in nodes) {
        var tgtNode = nodes.eq(i).attr('name');
        
        if (tgtNode) {
            tgts += tgtNode;
            
            // Add a comma at the end
            if (i < nodes.length - 1) {
                tgts += ',';
            }
        }
    }

    return tgts;
}

/**
 * Check if return message contains errors
 * 
 * @param msg  Return message
 * @return 0  If return message contains no errors
 *        -1  If return message contains errors
 */
function containErrors(msg) {
    if (msg.indexOf('Failed') > -1 || msg.indexOf('Error') > -1) {
    	return -1;
    } else {
    	return 0;
    }
}

/**
 * Check if a value is an integer
 *
 * @param value  Value to be checked
 * @returns true   If value is an integer
            false  If value is not an integer
 */
function isInteger(value){
    if ((parseFloat(value) == parseInt(value)) && !isNaN(value)) {
        return true;
    } else {
        return false;
    }
}
