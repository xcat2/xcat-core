/**
 * Global variables
 */
var serviceTabs;
var nodeName;
var nodePath;
var nodeStatus;
var gangliaTimer;

/**
 * Initialize service page
 */
function initServicePage() {
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
    includeCss("css/jstree.css");
    includeCss("css/jquery.jqplot.css");
    
    // Load custom stylesheet
    includeCss("css/style.css");    
        
    // Reuqired JQuery plugins
    includeJs("js/jquery/jquery.dataTables.min.js");
    includeJs("js/jquery/jquery.cookie.min.js");
    includeJs("js/jquery/tooltip.min.js");
    includeJs("js/jquery/superfish.min.js");
    includeJs("js/jquery/jquery.jqplot.min.js");
    includeJs("js/jquery/jqplot.dateAxisRenderer.min.js");
    
    // Custom plugins
    includeJs("js/custom/esx.js");
    includeJs("js/custom/kvm.js");
    includeJs("js/custom/zvm.js");
        
    // Enable settings link     
    $('#xcat_settings').click(function() {
        openSettings();
    });
    
    // Show service page
    $("#content").children().remove();
    includeJs("js/service/utils.js");
    loadServicePage();
    
    // Initialize tab index history
    $.cookie('tabindex_history', '0,0');
}

/**
 * Load service page
 */
function loadServicePage() {
    // If the page is loaded
    if ($('#content').children().length) {
        // Do not load again
        return;
    }
        
    // Create manage and provision tabs
    serviceTabs = new Tab();
    serviceTabs.init();
    $('#content').append(serviceTabs.object());
    
    var manageTabId = 'manageTab';
    serviceTabs.add(manageTabId, 'Manage', '', false);
    
    // Get nodes owned by user
    $.ajax( {
        url : 'lib/srv_cmd.php',
        dataType : 'json',
        data : {
            cmd : 'tabdump',
            tgt : '',
            args : 'nodetype',
            msg : ''
        },

        success : function(data) {
            setUserNodes(data);
            setMaxVM();
            getUserNodesDef();
            getNodesCurrentLoad();
            loadManagePage(manageTabId);
        }
    });    
    
	// Get OS image names
    $.ajax({
        url : 'lib/srv_cmd.php',
        dataType : 'json',
        async : true,
        data : {
            cmd : 'tabdump',
            tgt : '',
            args : 'osimage',
            msg : ''
        },

        success : function(data) {
            setOSImageCookies(data);
        }
    });
        
    // Get contents of hosts table
    $.ajax({
        url : 'lib/srv_cmd.php',
        dataType : 'json',
        async : true,
        data : {
            cmd : 'tabdump',
            tgt : '',
            args : 'hosts',
            msg : ''
        },

        success : function(data) {
            setGroupCookies(data);        
        }
    });
    
    var provTabId = 'provisionTab';
    serviceTabs.add(provTabId, 'Provision', '', false);
    loadServiceProvisionPage(provTabId);

    serviceTabs.select(manageTabId);
}

/**
 * Load the service portal's provision page
 * 
 * @param tabId Tab ID where page will reside
 */
function loadServiceProvisionPage(tabId) {
    // Create info bar
    var infoBar = createInfoBar('Select a platform to provision a node on, then click Ok.');
    
    // Create provision page
    var provPg = $('<div class="form"></div>');
    $('#' + tabId).append(infoBar, provPg);

    // Create radio buttons for platforms
    var hwList = $('<ol>Platforms available:</ol>');
    var esx = $('<li><input type="radio" name="hw" value="esx" disabled/>ESX</li>');
    var kvm = $('<li><input type="radio" name="hw" value="kvm" disabled/>KVM</li>');
    var zvm = $('<li><input type="radio" name="hw" value="zvm" checked/>z\/VM</li>');
    
    hwList.append(esx);
    hwList.append(kvm);
    hwList.append(zvm);
    provPg.append(hwList);

    /**
     * Ok
     */
    var okBtn = createButton('Ok');
    okBtn.bind('click', function(event) {
        var userName = $.cookie('xcat_username');
        var tmp = $.cookie(userName + '_usrnodes');
        
        // Get maximun number for nodes from cookie
        var nodes = '';
        var maxVM = 0;
        if (tmp.length) {
            nodes = tmp.split(',');
            maxVM = parseInt($.cookie(userName + '_maxvm'));
            
            // Do not allow user to clone if the maximum number of VMs is reached
            if (nodes.length >= maxVM) {
                var warn = createWarnBar('You have reached the maximum number of virtual machines allowed (' + maxVM + ').  Delete unused virtual machines or contact your system administrator request more virtual machines.');
                warn.prependTo($('#' + tabId));
                return;
            }
        }
        
        // Get hardware that was selected
        var hw = $(this).parent().find('input[name="hw"]:checked').val();
        var newTabId = hw + 'ProvisionTab';

        if ($('#' + newTabId).size() > 0){
            serviceTabs.select(newTabId);
        } else {
            var title = '';
            
            // Create an instance of the plugin
            var plugin = null;
            switch (hw) {
            case "kvm":
                plugin = new kvmPlugin();
                title = 'KVM';
                break;
            case "esx":
                plugin = new esxPlugin();
                title = 'ESX';
                break;
            case "blade":
                plugin = new bladePlugin();
                title = 'BladeCenter';
                break;
            case "hmc":
                plugin = new hmcPlugin();
                title = 'System p';
                break;
            case "ipmi":
                plugin = new ipmiPlugin();
                title = 'iDataPlex';
                break;
            case "zvm":
                plugin = new zvmPlugin();
                title = 'z/VM';
                
                // Get zVM host names
                $.ajax({
                    url : 'lib/srv_cmd.php',
                    dataType : 'json',
                    async : false,
                    data : {
                        cmd : 'webportal',
                        tgt : '',
                        args : 'lszvm',
                        msg : ''
                    },

                    success : function(data) {
                        setzVMCookies(data);
                    }
                });
                
                // Get master copies for clone
                $.ajax({
                    url : 'lib/srv_cmd.php',
                    dataType : 'json',
                    async : false,
                    data : {
                        cmd : 'webportal',
                        tgt : '',
                        args : 'lsgoldenimages',
                        msg : ''
                    },

                    success : function(data) {
                        setGoldenImagesCookies(data);
                    }
                });
                
                break;
            }

            // Select tab
            serviceTabs.add(newTabId, title, '', true);
            serviceTabs.select(newTabId);
            plugin.loadServiceProvisionPage(newTabId);
        }
    });
    provPg.append(okBtn);
}

/**
 * Load manage page
 * 
 * @param tabId Tab ID where page will reside
 */
function loadManagePage(tabId) {
    // Create manage form
    var manageForm = $('<div></div>');

    // Append to manage tab
    $('#' + tabId).append(manageForm);
}

/**
 * Get the user nodes definitions
 */
function getUserNodesDef() {
    var userName = $.cookie('xcat_username');
    var userNodes = $.cookie(userName + '_usrnodes');
    if (userNodes) {    
         // Get nodes definitions
        $.ajax( {
            url : 'lib/srv_cmd.php',
            dataType : 'json',
            data : {
                cmd : 'lsdef',
                tgt : '',
                args : userNodes,
                msg : ''
            },
    
            success : loadNodesTable
        });
    } else {
        // Clear the tab before inserting the table
        $('#manageTab').append(createWarnBar('No nodes were found belonging to you!'));
    }
}

/**
 * Load user nodes definitions into a table
 * 
 * @param data Data from HTTP request
 */
function loadNodesTable(data) {
    // Clear the tab before inserting the table
    $('#manageTab').children().remove();
    
    // Nodes datatable ID
    var nodesDTId = 'userNodesDT';
    
    // Hash of node attributes
    var attrs = new Object();
    // Node attributes
    var headers = new Object();
    var node = null, args;
    // Create hash of node attributes
    for (var i in data.rsp) {
        // Get node name
        if (data.rsp[i].indexOf('Object name:') > -1) {
            var temp = data.rsp[i].split(': ');
            node = jQuery.trim(temp[1]);

            // Create a hash for the node attributes
            attrs[node] = new Object();
            i++;
        }

        // Get key and value
        args = data.rsp[i].split('=', 2);
        var key = jQuery.trim(args[0]);
        var val = jQuery.trim(data.rsp[i].substring(data.rsp[i].indexOf('=') + 1, data.rsp[i].length));
        
        // Create a hash table
        attrs[node][key] = val;
        headers[key] = 1;
    }

    // Sort headers
    var sorted = new Array();
    var attrs2show = new Array('arch', 'groups', 'hcp', 'hostnames', 'ip', 'os', 'userid', 'mgt');
    for (var key in headers) {
        // Show node attributes
        if (jQuery.inArray(key, attrs2show) > -1) {
            sorted.push(key);
        }
    }
    sorted.sort();

    // Add column for check box, node, ping, power, monitor, and comments
    sorted.unshift('<input type="checkbox" onclick="selectAll(event, $(this))">', 
        'node', 
        '<span><a>status</a></span><img src="images/loader.gif" style="display: none;"></img>', 
        '<span><a>power</a></span><img src="images/loader.gif" style="display: none;"></img>',
        '<span><a>monitor</a></span><img src="images/loader.gif" style="display: none;"></img>',
        'comments');

    // Create a datatable
    var nodesDT = new DataTable(nodesDTId);
    nodesDT.init(sorted);
    
    // Go through each node
    for (var node in attrs) {
        // Create a row
        var row = new Array();
        
        // Create a check box, node link, and get node status
        var checkBx = $('<input type="checkbox" name="' + node + '"/>');
        var nodeLink = $('<a class="node" id="' + node + '">' + node + '</a>').bind('click', loadNode);
        
        // If there is no status attribute for the node, do not try to access hash table
        // Else the code will break
        var status = '';
        if (attrs[node]['status']) {
            status = attrs[node]['status'].replace('sshd', 'ping');
        }
            
        // Push in checkbox, node, status, monitor, and power
        row.push(checkBx, nodeLink, status, '', '');
        
        // If the node attributes are known (i.e the group is known)
        if (attrs[node]['groups']) {
            // Put in comments
            var comments = attrs[node]['usercomment'];            
            // If no comments exists, show 'No comments' and set icon image source
            var iconSrc;
            if (!comments) {
                comments = 'No comments';
                iconSrc = 'images/nodes/ui-icon-no-comment.png';
            } else {
                iconSrc = 'images/nodes/ui-icon-comment.png';
            }
                    
            // Create comments icon
            var tipID = node + 'Tip';
            var icon = $('<img id="' + tipID + '" src="' + iconSrc + '"></img>').css({
                'width': '18px',
                'height': '18px'
            });
            
            // Create tooltip
            var tip = createCommentsToolTip(comments);
            var col = $('<span></span>').append(icon);
            col.append(tip);
            row.push(col);
        
            // Generate tooltips
            icon.tooltip({
                position: "center right",
                offset: [-2, 10],
                effect: "fade",    
                opacity: 0.8,
                relative: true,
                delay: 500
            });
        } else {
            // Do not put in comments if attributes are not known
            row.push('');
        }
        
        // Go through each header
        for (var i = 6; i < sorted.length; i++) {
            // Add the node attributes to the row
            var key = sorted[i];
            
            // Do not put comments and status in twice
            if (key != 'usercomment' && key != 'status' && key.indexOf('statustime') < 0) {
                var val = attrs[node][key];
                if (val) {
                    row.push($('<span>' + val + '</span>'));
                } else {
                    row.push('');
                }
            }
        }

        // Add the row to the table
        nodesDT.add(row);
    }
    
    // Create info bar
    var infoBar = createInfoBar('Manage and monitor your virtual machines.');
    $('#manageTab').append(infoBar);
    
    // Insert action bar and nodes datatable
    $('#manageTab').append(nodesDT.object());
        
    // Turn table into a datatable
    $('#' + nodesDTId).dataTable({
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
    
    // Set datatable header class to add color
    // $('.datatable thead').attr('class', 'ui-widget-header');
    
    // Do not sort ping, power, and comment column
    $('#' + nodesDTId + ' thead tr th').click(function() {        
        getNodeAttrs(group);
    });
    var checkboxCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(0)');
    var pingCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(2)');
    var powerCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(3)');
    var monitorCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(4)');
    var commentCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(5)');
    checkboxCol.unbind('click');
    pingCol.unbind('click');
    powerCol.unbind('click');
    monitorCol.unbind('click');
    commentCol.unbind('click');
    
    // Refresh the node ping, power, and monitor status on-click
    var nodes = getNodesShown(nodesDTId);
    pingCol.find('span a').click(function() {
        refreshNodeStatus(nodes);
    });
    powerCol.find('span a').click(function() {
        refreshPowerStatus(nodes);
    });
    monitorCol.find('span a').click(function() {
        refreshGangliaStatus(nodes);
    });
    
    // Create actions menu
    // Power on
    var powerOnLnk = $('<a>Power on</a>');
    powerOnLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesDTId);
        if (tgtNodes) {
            powerNode(tgtNodes, 'on');
        }
    });
    
    // Power off
    var powerOffLnk = $('<a>Power off</a>');
    powerOffLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesDTId);
        if (tgtNodes) {
            powerNode(tgtNodes, 'off');
        }
    });
    
	// Power softoff
    var powerSoftoffLnk = $('<a>Shutdown</a>');
    powerSoftoffLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesDTId);
        if (tgtNodes) {
            powerNode(tgtNodes, 'softoff');
        }
    });
    
    // Turn monitoring on
    var monitorOnLnk = $('<a>Monitor on</a>');
    monitorOnLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesDTId);
        if (tgtNodes) {
            monitorNode(tgtNodes, 'on');
        }
    });

    // Turn monitoring off
    var monitorOffLnk = $('<a>Monitor off</a>');
    monitorOffLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesDTId);
        if (tgtNodes) {
            monitorNode(tgtNodes, 'off');
        }
    });
    
    // Clone
    var cloneLnk = $('<a>Clone</a>');
    cloneLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesDTId);
        if (tgtNodes) {
            cloneNode(tgtNodes);
        }
    });
    
    // Delete
    var deleteLnk = $('<a>Delete</a>');
    deleteLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesDTId);
        if (tgtNodes) {
            deleteNode(tgtNodes);
        }
    });

    // Unlock
    var unlockLnk = $('<a>Unlock</a>');
    unlockLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesDTId);
        if (tgtNodes) {
            unlockNode(tgtNodes);
        }
    });
    
    // Create action bar
    var actionBar = $('<div class="actionBar"></div>').css('width', '370px');
    
    // Prepend menu to datatable
    var actionsLnk = $('<a>Actions</a>');
    var refreshLnk = $('<a>Refresh</a>');
    refreshLnk.click(function() {
        // Get nodes owned by user
        $.ajax( {
            url : 'lib/srv_cmd.php',
            dataType : 'json',
            data : {
                cmd : 'tabdump',
                tgt : '',
                args : 'nodetype',
                msg : ''
            },

            success : function(data) {
                // Save nodes owned by user
                setUserNodes(data);
                getNodesCurrentLoad();
                
                // Refresh nodes table
                var userName = $.cookie('xcat_username');
                var userNodes = $.cookie(userName + '_usrnodes');
                if (userNodes) {
                    // Get nodes definitions
                    $.ajax( {
                        url : 'lib/srv_cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'lsdef',
                            tgt : '',
                            args : userNodes,
                            msg : ''
                        },
                
                        success : loadNodesTable
                    });
                } else {
                    // Clear the tab before inserting the table
                    $('#manageTab').children().remove();
                    $('#manageTab').append(createWarnBar('You are not managing any node.  Try to provision a node.'));
                }
            }
        });    
    });
    
    var actionMenu = createMenu([cloneLnk, deleteLnk, monitorOnLnk, monitorOffLnk, powerOnLnk, powerOffLnk, powerSoftoffLnk, unlockLnk]);
    var menu = createMenu([[actionsLnk, actionMenu], refreshLnk]);
    menu.superfish();
    actionBar.append(menu);
    
    // Set correct theme for action menu
    actionMenu.find('li').hover(function() {
        setMenu2Theme($(this));
    }, function() {
        setMenu2Normal($(this));
    });
        
    // Create a division to hold actions menu
    var menuDiv = $('<div id="' + nodesDTId + '_menuDiv" class="menuDiv"></div>');
    $('#' + nodesDTId + '_wrapper').prepend(menuDiv);
    menuDiv.append(actionBar);    
    $('#' + nodesDTId + '_filter').appendTo(menuDiv);
        
    // Get power and monitor status
    var nodes = getNodesShown(nodesDTId);
    refreshPowerStatus(nodes);
    refreshGangliaStatus(nodes);    
}

/**
 * Refresh ping status for each node
 * 
 * @param nodes Nodes to get ping status
 */
function refreshNodeStatus(nodes) {
    // Show ping loader
    var nodesDTId = 'userNodesDT';
    var pingCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(2)');
    pingCol.find('img').show();
        
    // Get the node ping status
    $.ajax( {
        url : 'lib/srv_cmd.php',
        dataType : 'json',
        data : {
            cmd : 'nodestat',
            tgt : nodes,
            args : '-u',
            msg : ''
        },

        success : loadNodePing
    });
}

/**
 * Load node ping status for each node
 * 
 * @param data Data returned from HTTP request
 */
function loadNodePing(data) {
    var nodesDTId = 'userNodesDT';
    var datatable = $('#' + nodesDTId).dataTable();
    var rsp = data.rsp;
    var args, rowPos, node, status;

    // Get all nodes within datatable
    for (var i in rsp) {
        args = rsp[i].split(':');
        
        // args[0] = node and args[1] = status
        node = jQuery.trim(args[0]);
        status = jQuery.trim(args[1]).replace('sshd', 'ping');
        
        // Get row containing node
        rowPos = findRow(node, '#' + nodesDTId, 1);

        // Update ping status column
        datatable.fnUpdate(status, rowPos, 2, false);
    }
    
    // Hide status loader
    var pingCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(2)');
    pingCol.find('img').hide();
    adjustColumnSize(nodesDTId);
}

/**
 * Refresh power status for each node
 * 
 * @param nodes Nodes to get power status
 */
function refreshPowerStatus(nodes) {    
    // Show power loader
    var nodesDTId = 'userNodesDT';
    var powerCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(3)');
    powerCol.find('img').show();
            
    // Get power status
    $.ajax( {
        url : 'lib/srv_cmd.php',
        dataType : 'json',
        data : {
            cmd : 'rpower',
            tgt : nodes,
            args : 'stat',
            msg : ''
        },

        success : loadPowerStatus
    });
}

/**
 * Load power status for each node
 * 
 * @param data Data returned from HTTP request
 */
function loadPowerStatus(data) {
    var nodesDTId = 'userNodesDT';
    var datatable = $('#' + nodesDTId).dataTable();
    var power = data.rsp;
    var rowPos, node, status, args;

    for (var i in power) {
        // power[0] = nodeName and power[1] = state
        args = power[i].split(':');
        node = jQuery.trim(args[0]);
        status = jQuery.trim(args[1]);
        
        // Get the row containing the node
        rowPos = findRow(node, '#' + nodesDTId, 1);

        // Update the power status column
        datatable.fnUpdate(status, rowPos, 3, false);
    }
    
    // Hide power loader
    var powerCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(3)');
    powerCol.find('img').hide();
    adjustColumnSize(nodesDTId);
}

/**
 * Refresh the status of Ganglia for each node
 * 
 * @param nodes Nodes to get Ganglia status
 */
function refreshGangliaStatus(nodes) {
    // Show ganglia loader
    var nodesDTId = 'userNodesDT';
    var gangliaCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(4)');
    gangliaCol.find('img').show();
    
    // Get the status of Ganglia
    $.ajax( {
        url : 'lib/srv_cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'gangliastatus;' + nodes,
            msg : ''
        },

        success : loadGangliaStatus
    });
}

/**
 * Load the status of Ganglia for a given group
 * 
 * @param data Data returned from HTTP request
 */
function loadGangliaStatus(data) {
    // Get datatable
    var nodesDTId = 'userNodesDT';
    var datatable = $('#' + nodesDTId).dataTable();
    var ganglia = data.rsp;
    var rowNum, node, status;

    for ( var i in ganglia) {
        // ganglia[0] = nodeName and ganglia[1] = state
        node = jQuery.trim(ganglia[i][0]);
        status = jQuery.trim(ganglia[i][1]);

        if (node) {
            // Get the row containing the node
            rowNum = findRow(node, '#' + nodesDTId, 1);

            // Update the power status column
            datatable.fnUpdate(status, rowNum, 4);
        }        
    }

    // Hide Ganglia loader
    var gangliaCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(4)');
    gangliaCol.find('img').hide();
    adjustColumnSize(nodesDTId);
}

/**
 * Load inventory for given node
 * 
 * @param e Windows event
 */
function loadNode(e) {
    if (!e) {
        e = window.event;
    }
    
    // Get node that was clicked
    var node = (e.target) ? e.target.id : e.srcElement.id;

    // Create a new tab to show inventory
    var tabId = node + '_inventory';

    if(!$('#' + tabId).length) {
        // Add new tab, only if one does not exist
        var loader = createLoader(node + 'Loader');
        loader = $('<center></center>').append(loader);
        serviceTabs.add(tabId, node, loader, true);
            
        // Get node inventory
        var msg = 'out=' + tabId + ',node=' + node;
        $.ajax( {
            url : 'lib/srv_cmd.php',
            dataType : 'json',
            data : {
                cmd : 'rinv',
                tgt : node,
                args : 'all',
                msg : msg
            },

            success : function(data) {
                var args = data.msg.split(',');

                // Get node
                var node = args[1].replace('node=', '');
                
                // Get the management plugin
                var mgt = getNodeAttr(node, 'mgt');
                
                // Create an instance of the plugin
                var plugin;
                switch (mgt) {
	                case "kvm":
	                    plugin = new kvmPlugin();
	                    break;
	                case "esx":
	                    plugin = new esxPlugin();
	                    break;
	                case "zvm":
	                    plugin = new zvmPlugin();
	                    break;
                }

                // Select tab
                plugin.loadServiceInventory(data);
            }
        });
    }    

    // Select new tab
    serviceTabs.select(tabId);
}

/**
 * Set a cookie for group names
 * 
 * @param data Data from HTTP request
 */
function setGroupCookies(data) {
    if (data.rsp) {
        var groups = new Array();
        
        // Index 0 is the table header
        var cols, name, ip, hostname, desc, selectable, comments, tmp;
        for (var i = 1; i < data.rsp.length; i++) {
            // Set default description and selectable
            selectable = "no";
            desc = "No description";
            
            // Split into columns:
            // node, ip, hostnames, otherinterfaces, comments, disable
            cols = data.rsp[i].split(',');
            name = cols[0].replace(new RegExp('"', 'g'), '');
            ip = cols[1].replace(new RegExp('"', 'g'), '');
            hostname = cols[2].replace(new RegExp('"', 'g'), '');
            
            // It should return: "description: All machines; network: 10.1.100.0/24;"
            comments = cols[4].replace(new RegExp('"', 'g'), '');
            tmp = comments.split('|');
            for (var j = 0; j < tmp.length; j++) {
                // Save description
                if (tmp[j].indexOf('description:') > -1) {
                    desc = tmp[j].replace('description:', '');
                    desc = jQuery.trim(desc);
                }
                
                // Is the group selectable?
                if (tmp[j].indexOf('selectable:') > -1) {
                    selectable = tmp[j].replace('selectable:', '');
                    selectable = jQuery.trim(selectable);
                }
            }
            
            // Save groups that are selectable
            if (selectable == "yes")
                groups.push(name + ':' + ip + ':' + hostname + ':' + desc);
        }
        
        // Set cookie to expire in 60 minutes
        var exDate = new Date();
        exDate.setTime(exDate.getTime() + (240 * 60 * 1000));
        $.cookie('srv_groups', groups, { expires: exDate });
    }
}

/**
 * Set a cookie for the OS images
 * 
 * @param data Data from HTTP request
 */
function setOSImageCookies(data) {
    // Get response
    var rsp = data.rsp;

    var imageNames = new Array();
    var profilesHash = new Object();
    var osVersHash = new Object();
    var osArchsHash = new Object();
    var imagePos = 0;
    var profilePos = 0;
    var osversPos = 0;
    var osarchPos = 0;
    var provMethodPos = 0;
    var comments = 0;
    var desc, selectable, tmp;
    // Get column index for each attribute
    var colNameArray = rsp[0].substr(1).split(',');
    for (var i in colNameArray){
        switch (colNameArray[i]){
            case 'imagename': {
                imagePos = i;
            }
            break;
            
            case 'profile':{
                profilePos = i;
            }
            break;
            
            case 'osvers':{
                osversPos = i;
            }
            break;
            
            case 'osarch':{
                osarchPos = i;
            }
            break;
            
            case 'comments':{
                comments = i;
            }
            break;
            
            case 'provmethod':{
                provMethodPos = i;
            }            
            break;
            
            default :
            break;
        }
    }
    
    // Go through each index
    for (var i = 1; i < rsp.length; i++) {
        // Get image name
        var cols = rsp[i].split(',');
        var osImage = cols[imagePos].replace(new RegExp('"', 'g'), '');
        var profile = cols[profilePos].replace(new RegExp('"', 'g'), '');
        var provMethod = cols[provMethodPos].replace(new RegExp('"', 'g'), '');
        var osVer = cols[osversPos].replace(new RegExp('"', 'g'), '');
        var osArch = cols[osarchPos].replace(new RegExp('"', 'g'), '');
        var osComments = cols[comments].replace(new RegExp('"', 'g'), '');
        
        // Only save install boot
        if (provMethod.indexOf('install') > -1) {
            if (osComments) {
            	// Only enable images where description and selectable comments exist
                // Set default description and selectable
                selectable = "no";
                desc = "No description";
                
                tmp = osComments.split('|');
                for (var j = 0; j < tmp.length; j++) {
                    // Save description
                    if (tmp[j].indexOf('description:') > -1) {
                        desc = tmp[j].replace('description:', '');
                        desc = jQuery.trim(desc);
                    }
                    
                    // Is the image selectable?
                    if (tmp[j].indexOf('selectable:') > -1) {
                        selectable = tmp[j].replace('selectable:', '');
                        selectable = jQuery.trim(selectable);
                    }
                }
                
                // Save images that are selectable
                if (selectable == "yes")
                    imageNames.push(osImage + ':' + desc);
            }
            
            profilesHash[profile] = 1;
            osVersHash[osVer] = 1;
            osArchsHash[osArch] = 1;
        }        
    }

    // Save image names in a cookie
    $.cookie('srv_imagenames', imageNames);

    // Save profiles in a cookie
    var tmp = new Array;
    for (var key in profilesHash) {
        tmp.push(key);
    }
    $.cookie('srv_profiles', tmp);

    // Save OS versions in a cookie
    tmp = new Array;
    for (var key in osVersHash) {
        tmp.push(key);
    }
    $.cookie('srv_osvers', tmp);

    // Save OS architectures in a cookie
    tmp = new Array;
    for (var key in osArchsHash) {
        tmp.push(key);
    }
    $.cookie('srv_osarchs', tmp);
}



/**
 * Set a cookie for user nodes
 * 
 * @param data Data from HTTP request
 */
function setUserNodes(data) {
    if (data.rsp) {
        // Get user name that is logged in
        var userName = $.cookie('xcat_username');
        var usrNodes = new Array();
        
        // Ignore first columns because it is the header
        for ( var i = 1; i < data.rsp.length; i++) {
            // Go through each column
            // where column names are: node, os, arch, profile, provmethod, supportedarchs, nodetype, comments, disable
            var cols = data.rsp[i].split(',');
            var node = cols[0].replace(new RegExp('"', 'g'), '');
            
            // Comments can contain the owner and description
            var comments = new Array();
            if (cols[7].indexOf(';') > -1) {
            	comments = cols[7].replace(new RegExp('"', 'g'), '').split(';');
            } else {
            	comments.push(cols[7].replace(new RegExp('"', 'g'), ''));
            }
            
            // Extract the owner
            var owner;
            for (var j in comments) {
            	if (comments[j].indexOf('owner:') > -1) {
            		owner = comments[j].replace('owner:', '');
            		
            		if (owner == userName) {
                        usrNodes.push(node);
                    }
            		
            		break;
            	}
            }
        } // End of for
        
        // Set cookie to expire in 240 minutes
        var exDate = new Date();
        exDate.setTime(exDate.getTime() + (240 * 60 * 1000));
        $.cookie(userName + '_usrnodes', usrNodes, { expires: exDate });
    } // End of if
}

/**
 * Power on a given node
 * 
 * @param tgtNodes Node to power on or off
 * @param power2 Power node to given state
 */
function powerNode(tgtNodes, power2) {
    // Show power loader
    var nodesDTId = 'userNodesDT';
    var powerCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(3)');
    powerCol.find('img').show();
    
    var nodes = tgtNodes.split(',');
    for (var n in nodes) {
        // Get hardware that was selected
        var hw = getUserNodeAttr(nodes[n], 'mgt');
        
        // Change to power softoff (to gracefully shutdown)
        switch (hw) {
        case "blade":
            break;
        case "hmc":
            break;
        case "ipmi":
            break;
        case "zvm":
            if (power2 == 'off') {
                power2 = 'softoff';
            }
            
            break;
        }
    }
    
    $.ajax({
        url : 'lib/srv_cmd.php',
        dataType : 'json',
        data : {
            cmd : 'rpower',
            tgt : tgtNodes,
            args : power2,
            msg : tgtNodes
        },

        success : updatePowerStatus
    });
}

/**
 * Update power status of a node in the datatable
 * 
 * @param data Data from HTTP request
 */
function updatePowerStatus(data) {
    // Get datatable
    var nodesDTId = 'userNodesDT';
    var dTable = $('#' + nodesDTId).dataTable();

    // Get xCAT response
    var rsp = data.rsp;
    // Loop through each line
    var node, status, rowPos, strPos;
    for (var i in rsp) {
        // Get node name
        node = rsp[i].split(":")[0];

        // If there is no error
        if (rsp[i].indexOf("Error") < 0 || rsp[i].indexOf("Failed") < 0) {
            // Get the row containing the node link
            rowPos = findRow(node, '#' + nodesDTId, 1);

            // If it was power on, then the data return would contain "Starting"
            strPos = rsp[i].indexOf("Starting");
            if (strPos > -1) {
                status = 'on';
            } else {
                status = 'off';
            }

            // Update the power status column
            dTable.fnUpdate(status, rowPos, 3, false);
        } else {
            // Power on/off failed
            alert(rsp[i]);
        }
    }
    
    var powerCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(3)');
    powerCol.find('img').hide();
    adjustColumnSize(nodesDTId);
}

/**
 * Turn on monitoring for a given node
 * 
 * @param node Node to monitor on or off
 * @param monitor Monitor state, on or off
 */
function monitorNode(node, monitor) {
    // Show ganglia loader
    var nodesDTId = 'userNodesDT';
    var gangliaCol = $('#' + nodesDTId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(4)');
    gangliaCol.find('img').show();
    
    if (monitor == 'on') {
        if (node) {
            // Check if ganglia RPMs are installed
            $.ajax( {
                url : 'lib/srv_cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'webrun',
                    tgt : '',
                    args : 'gangliacheck;' + node,
                    msg : node    // Node range will be passed along in data.msg
                },

                /**
                 * Start ganglia on a given node range
                 * 
                 * @param data
                 *            Data returned from HTTP request
                 * @return Nothing
                 */
                success : function(data) {
                    // Get response
                    var out = data.rsp[0].split(/\n/);

                    // Go through each line
                    var warn = false;
                    var warningMsg = '';
                    for (var i in out) {
                        // If an RPM is not installed
                        if (out[i].indexOf('not installed') > -1) {
                            warn = true;
                            
                            if (warningMsg) {
                                warningMsg += '<br>' + out[i];
                            } else {
                                warningMsg = out[i];
                            }
                        }
                    }
                    
                    // If there are warnings
                    if (warn) {
                        // Create warning bar
                        var warningBar = createWarnBar(warningMsg);
                        warningBar.css('margin-bottom', '10px');
                        warningBar.prependTo($('#nodesTab'));
                    } else {
                        $.ajax( {
                            url : 'lib/srv_cmd.php',
                            dataType : 'json',
                            data : {
                                cmd : 'webrun',
                                tgt : '',
                                args : 'gangliastart;' + data.msg,
                                msg : data.msg
                            },

                            success : function(data) {
                                // Remove any warnings
                                $('#nodesTab').find('.ui-state-error').remove();
                                refreshGangliaStatus(data.msg);
                            }
                        });
                    } // End of if (warn)
                } // End of function(data)
            });
        }
    } else {
        var args;
        if (node) {
            args = 'gangliastop;' + node;
            $.ajax( {
                url : 'lib/srv_cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'webrun',
                    tgt : '',
                    args : args,
                    msg : node
                },

                success : function(data) {
                    refreshGangliaStatus(data.msg);
                }
            });
        }
    }
}

/**
 * Open a dialog to clone node
 * 
 * @param tgtNodes Nodes to clone
 */
function cloneNode(tgtNodes) {    
    var userName = $.cookie('xcat_username');    
    var nodes = tgtNodes.split(',');
    var tmp = $.cookie(userName + '_usrnodes');
    var usrNodes = tmp.split(',');
    
    var maxVM = parseInt($.cookie(userName + '_maxvm'));
    
    // Do not allow user to clone if the maximum number of VMs is reached
    if (usrNodes.length >= maxVM) {
        var warn = createWarnBar('You have reached the maximum number of virtual machines allowed (' + maxVM + ').  Delete un-used virtual machines or contact your system administrator request more virtual machines.');
        warn.prependTo($('#manageTab'));
        return;
    }
    
    for (var n in nodes) {
        // Get hardware that was selected
        var hw = getUserNodeAttr(nodes[n], 'mgt');
        
        // Create an instance of the plugin
        var plugin;
        switch (hw) {
	        case "kvm":
	            plugin = new kvmPlugin();
	            break;
	        case "esx":
	            plugin = new esxPlugin();
	            break;
	        case "zvm":
	            plugin = new zvmPlugin();
	            break;
        }

        // Clone node
        plugin.serviceClone(nodes[n]);                
    }
}
    

/**
 * Open a dialog to delete node
 * 
 * @param tgtNodes Nodes to delete
 */
function deleteNode(tgtNodes) {
    var nodes = tgtNodes.split(',');
        
    // Loop through each node and create target nodes string
    var tgtNodesStr = '';
    for (var i in nodes) {        
        if (i == 0 && i == nodes.length - 1) {
            // If it is the 1st and only node
            tgtNodesStr += nodes[i];
        } else if (i == 0 && i != nodes.length - 1) {
            // If it is the 1st node of many nodes, append a comma to the string
            tgtNodesStr += nodes[i] + ', ';
        } else {
            if (i == nodes.length - 1) {
                // If it is the last node, append nothing to the string
                tgtNodesStr += nodes[i];
            } else {
                // Append a comma to the string
                tgtNodesStr += nodes[i] + ', ';
            }
        }
    }
    
    // Confirm delete of node
    var dialog = $('<div></div>');
    var warn = createWarnBar('Are you sure you want to delete ' + tgtNodesStr + '?');
    dialog.append(warn);
        
    // Open dialog
    dialog.dialog({
        title: "Confirm",
        modal: true,
        close: function(){
            $(this).remove();
        },
        width: 400,
        buttons: {
            "Yes": function(){ 
                // Create status bar and append to tab
                var instance = 0;
                var statBarId = 'deleteStat' + instance;
                while ($('#' + statBarId).length) {
                    // If one already exists, generate another one
                    instance = instance + 1;
                    statBarId = 'deleteStat' + instance;
                }
                
                var statBar = createStatusBar(statBarId);
                var loader = createLoader('');
                statBar.find('div').append(loader);
                statBar.prependTo($('#manageTab'));
                
                // Delete the virtual server
                $.ajax( {
                    url : 'lib/srv_cmd.php',
                    dataType : 'json',
                    data : {
                        cmd : 'rmvm',
                        tgt : tgtNodes,
                        args : '',
                        msg : 'out=' + statBarId + ';cmd=rmvm;tgt=' + tgtNodes
                    },

                    success : function(data) {
                        var args = data.msg.split(';');
                        var statBarId = args[0].replace('out=', '');
                        var tgts = args[2].replace('tgt=', '').split(',');
                        
                        // Get data table
                        var nodesDTId = 'userNodesDT';
                        var dTable = $('#' + nodesDTId).dataTable();
                        var failed = false;

                        // Create an info box to show output
                        var output = writeRsp(data.rsp, '');
                        output.css('margin', '0px');
                        // Remove loader and append output
                        $('#' + statBarId + ' img').remove();
                        $('#' + statBarId + ' div').append(output);
                        
                        // If there was an error, do not continue
                        if (output.html().indexOf('Error') > -1) {
                            failed = true;
                        }

                        // Update data table
                        var rowPos;                        
                        for (var i in tgts) {
                            if (!failed) {
                                // Get row containing the node link and delete it
                                rowPos = findRow(tgts[i], '#' + nodesDTId, 1);
                                dTable.fnDeleteRow(rowPos);
                            }
                        }
                        
                        // Refresh nodes owned by user
                        $.ajax( {
                            url : 'lib/srv_cmd.php',
                            dataType : 'json',
                            data : {
                                cmd : 'tabdump',
                                tgt : '',
                                args : 'nodetype',
                                msg : ''
                            },

                            success : function(data) {
                                setUserNodes(data);
                            }
                        });
                    }
                });
                
                $(this).dialog("close");
            },
            "No": function() {
                $(this).dialog("close");
            }
        }
    });
}

/**
 * Unlock a node by setting the ssh keys
 * 
 * @param tgtNodes Nodes to unlock
 */
function unlockNode(tgtNodes) {
    var nodes = tgtNodes.split(',');
    
    // Loop through each node and create target nodes string
    var tgtNodesStr = '';
    for (var i in nodes) {        
        if (i == 0 && i == nodes.length - 1) {
            // If it is the 1st and only node
            tgtNodesStr += nodes[i];
        } else if (i == 0 && i != nodes.length - 1) {
            // If it is the 1st node of many nodes, append a comma to the string
            tgtNodesStr += nodes[i] + ', ';
        } else {
            if (i == nodes.length - 1) {
                // If it is the last node, append nothing to the string
                tgtNodesStr += nodes[i];
            } else {
                // Append a comma to the string
                tgtNodesStr += nodes[i] + ', ';
            }
        }
    }

    var dialog = $('<div></div>');
    var infoBar = createInfoBar('Give the root password for this node range to setup its SSH keys.');
    dialog.append(infoBar);
    
    var unlockForm = $('<div class="form"></div>').css('margin', '5px');
    unlockForm.append('<div><label>Target node range:</label><input type="text" id="node" name="node" readonly="readonly" value="' + tgtNodes + '" title="The node or node range to unlock"/></div>');
    unlockForm.append('<div><label>Password:</label><input type="password" id="password" name="password" title="The root password to unlock this node"/></div>');
    dialog.append(unlockForm);
    
    dialog.find('div input').css('margin', '5px');
    
    // Generate tooltips
    unlockForm.find('div input[title]').tooltip({
        position: "center right",
        offset: [-2, 10],
        effect: "fade",
        opacity: 0.7,
        predelay: 800,
        events : {
            def : "mouseover,mouseout",
            input : "mouseover,mouseout",
            widget : "focus mouseover,blur mouseout",
            tooltip : "mouseover,mouseout"
        }
    });
        
    // Open dialog
    dialog.dialog({
        title: "Confirm",
        modal: true,
        close: function(){
            $(this).remove();
        },
        width: 450,
        buttons: {
            "Ok": function(){
                // Create status bar and append to tab
                var instance = 0;
                var statBarId = 'unlockStat' + instance;
                while ($('#' + statBarId).length) {
                    // If one already exists, generate another one
                    instance = instance + 1;
                    statBarId = 'unlockStat' + instance;
                }
                
                var statBar = createStatusBar(statBarId);
                var loader = createLoader('');
                statBar.find('div').append(loader);
                statBar.prependTo($('#manageTab'));
                                
                // If a password is given
                var password = unlockForm.find('input[name=password]:eq(0)');
                if (password.val()) {
                    // Setup SSH keys
                    $.ajax( {
                        url : 'lib/srv_cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'webrun',
                            tgt : '',
                            args : 'unlock;' + tgtNodes + ';' + password.val(),
                            msg : 'out=' + statBarId + ';cmd=unlock;tgt=' + tgtNodes
                        },
            
                        success : function(data) {
                            // Create an info box to show output
                            var output = writeRsp(data.rsp, '');
                            output.css('margin', '0px');
                            // Remove loader and append output
                            $('#' + statBarId + ' img').remove();
                            $('#' + statBarId + ' div').append(output);
                        }
                    });
                    
                    $(this).dialog("close");
                }            
            },
            "Cancel": function() {
                $(this).dialog("close");
            }
        }
    });
}

/**
 * Get nodes current load information
 */
function getNodesCurrentLoad(){
    var userName = $.cookie('xcat_username');
    var nodes = $.cookie(userName + '_usrnodes');
    
    // Get nodes current status
    $.ajax({
        url : 'lib/srv_cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'gangliacurrent;node;' + nodes,
            msg : ''
        },
        
        success: saveNodeLoad
    });
}

/**
 * Save node load data
 * 
 * @param status Data returned from HTTP request
 */
function saveNodeLoad(status){
    // Save node path and status for future use
    nodePath = new Object();
    nodeStatus = new Object();
    
    // Get nodes status
    var nodes = status.rsp[0].split(';');
    
    var i = 0, pos = 0;
    var node = '', tmpStr = '';
    var tmpArry;   
    
    for (i = 0; i < nodes.length; i++){
        tmpStr = nodes[i];
        pos = tmpStr.indexOf(':');
        node = tmpStr.substring(0, pos);
        tmpArry = tmpStr.substring(pos + 1).split(',');
        
        switch(tmpArry[0]){
            case 'UNKNOWN':{
                nodeStatus[node] = -2;
            }
            break;
            case 'ERROR':{
                nodeStatus[node] = -1;
            }
            break;
            case 'WARNING':{
                nodeStatus[node] = 0;
                nodePath[node] = tmpArry[1];
            }
            break;
            case 'NORMAL':{
                nodeStatus[node] = 1;
                nodePath[node] = tmpArry[1];
            }
            break;
        }
    }
}

/**
 * Get monitoring metrics and load into inventory fieldset
 * 
 * @param node Node to collect metrics
 */
function getMonitorMetrics(node) {
    // Inventory tab should have this fieldset already created
    // e.g. <fieldset id="gpok123_monitor"></fieldset>
    $('#' + node + '_monitor').children('div').remove();
    
    // Before trying to get the metrics, check if Ganglia is running
    $.ajax({
        url : 'lib/srv_cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'gangliastatus;' + node,
            msg : ''
        },
        
        success: function(data) {
            var ganglia = data.rsp;
            var node, status;

            // Get the ganglia status
            for (var i in ganglia) {
                // ganglia[0] = nodeName and ganglia[1] = state
                node = jQuery.trim(ganglia[i][0]);
                status = jQuery.trim(ganglia[i][1]);
                
                if (node && status == 'on') {
                    // Get monitoring metrics
                    $.ajax({
                        url : 'lib/srv_cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'webrun',
                            tgt : '',
                            args : 'gangliashow;' + nodePath[node] + ';hour;_summary_',
                            msg : node
                        },
                        
                        success: drawMonitoringCharts
                    });
                } else if (node && status == 'off') {
                    var info = createInfoBar('Ganglia monitoring is disabled for this node');
                    $('#' + node + '_monitor').append(info.css('width', '300px'));
                }
            } // End of for
        } // End of function
    });    
}

/**
 * Draw monitoring charts based on node metrics
 * 
 * @param data Data returned from HTTP request
 */
function drawMonitoringCharts(data){
    var nodeMetrics = new Object();
    var metricData = data.rsp[0].split(';');
    var node = data.msg;
        
    var metricName = '';
    var metricVal = '';
    var pos = 0;
    
    // Go through the metrics returned
    for (var m = 0; m < metricData.length; m++){
        pos = metricData[m].indexOf(':');

        // Get metric name
        metricName = metricData[m].substr(0, pos);
        nodeMetrics[metricName] = new Array();
        // Get metric values
        metricVal = metricData[m].substr(pos + 1).split(',');
        // Save node metrics
        for (var i = 0; i < metricVal.length; i++){
            nodeMetrics[metricName].push(Number(metricVal[i]));
        }
    }
    
    drawLoadFlot(node, nodeMetrics['load_one'], nodeMetrics['cpu_num']);
    drawCpuFlot(node, nodeMetrics['cpu_idle']);
    drawMemFlot(node, nodeMetrics['mem_free'], nodeMetrics['mem_total']);
    drawDiskFlot(node, nodeMetrics['disk_free'], nodeMetrics['disk_total']);
    drawNetworkFlot(node, nodeMetrics['bytes_in'], nodeMetrics['bytes_out']);
}

/**
 * Draw load metrics flot
 * 
 * @param node Node name
 * @param loadpair Load timestamp and value pair
 * @param cpupair CPU number and value pair
 */
function drawLoadFlot(node, loadPair, cpuPair){
    var load = new Array();
    var cpu = new Array();
    
    var i = 0;
    var yAxisMax = 0;
    var interval = 1;
    
    // Append flot to node monitoring fieldset
    var loadFlot = $('<div id="' + node + '_load"></div>').css({
        'float': 'left',
        'height': '150px',
        'margin': '0 0 10px',
        'width': '300px'
    });
    $('#' + node + '_monitor').append(loadFlot);
    $('#' + node + '_load').empty();
    
    // Parse load pair where:
    // timestamp must be mutiplied by 1000 and Javascript timestamp is in ms
    for (i = 0; i < loadPair.length; i += 2){
        load.push([loadPair[i] * 1000, loadPair[i + 1]]);
        if (loadPair[i + 1] > yAxisMax){
            yAxisMax = loadPair[i + 1];
        }
    }
    
    // Parse CPU pair
    for (i = 0; i < cpuPair.length; i += 2){
        cpu.push([cpuPair[i] * 1000, cpuPair[i + 1]]);
        if (cpuPair[i + 1] > yAxisMax){
            yAxisMax = cpuPair[i + 1];
        }
    }
    
    interval = parseInt(yAxisMax / 3);
    if (interval < 1){
        interval = 1;
    }
    
    $.jqplot(node + '_load', [load, cpu],{
        title: ' Loads/Procs Last Hour',
        axes:{
            xaxis:{
                renderer : $.jqplot.DateAxisRenderer,
                numberTicks: 4,
                tickOptions : {
                    formatString : '%R',
                    show : true
                }
            },
            yaxis: {
                min : 0,
                tickInterval : interval
            }
        },
        legend : {
            show: true,
            location: 'nw'
        },
        series:[{label:'Load'}, {label: 'CPU Number'}],
        seriesDefaults : {showMarker: false}
    });
}

/**
 * Draw CPU usage flot
 * 
 * @param node Node name
 * @param cpuPair CPU timestamp and value pair
 */
function drawCpuFlot(node, cpuPair){
    var cpu = new Array();
    
    // Append flot to node monitoring fieldset
    var cpuFlot = $('<div id="' + node + '_cpu"></div>').css({
        'float': 'left',
        'height': '150px',
        'margin': '0 0 10px',
        'width': '300px'
    });
    $('#' + node + '_monitor').append(cpuFlot);
    $('#' + node + '_cpu').empty();
    
    // Time stamp should by mutiplied by 1000
    // CPU idle comes from server, subtract 1 from idle
    for(var i = 0; i < cpuPair.length; i +=2){
        cpu.push([(cpuPair[i] * 1000), (100 - cpuPair[i + 1])]);
    }
    
    $.jqplot(node + '_cpu', [cpu],{
        title: 'CPU Use Last Hour',
        axes:{
            xaxis:{
                renderer : $.jqplot.DateAxisRenderer,
                numberTicks: 4,
                tickOptions : {
                    formatString : '%R',
                    show : true
                }
            },
            yaxis: {
                min : 0,
                max : 100,
                tickOptions:{formatString : '%d\%'}
            }
        },
        seriesDefaults : {showMarker: false}
    });
}

/**
 * Draw memory usage flot
 * 
 * @param node Node name
 * @param freePair Free memory timestamp and value pair
 * @param totalPair Total memory timestamp and value pair
 */
function drawMemFlot(node, freePair, totalPair){
    var used = new Array();
    var total = new Array();
    var size = 0;
    
    // Append flot to node monitoring fieldset
    var memoryFlot = $('<div id="' + node + '_memory"></div>').css({
        'float': 'left',
        'height': '150px',
        'margin': '0 0 10px',
        'width': '300px'
    });
    $('#' + node + '_monitor').append(memoryFlot);
    $('#' + node + '_memory').empty();
    
    if(freePair.length < totalPair.length){
        size = freePair.length;
    } else {
        size = freePair.length;
    }
    
    var tmpTotal, tmpUsed;
    for(var i = 0; i < size; i+=2){
        tmpTotal = totalPair[i+1];
        tmpUsed = tmpTotal-freePair[i+1];
        tmpTotal = tmpTotal/1000000;
        tmpUsed = tmpUsed/1000000;
        total.push([totalPair[i]*1000, tmpTotal]);
        used.push([freePair[i]*1000, tmpUsed]);
    }
    
    $.jqplot(node + '_memory', [used, total],{
        title: 'Memory Use Last Hour',
        axes:{
            xaxis:{
                renderer : $.jqplot.DateAxisRenderer,
                numberTicks: 4,
                tickOptions : {
                    formatString : '%R',
                    show : true
                }
            },
            yaxis: {
                min : 0,
                tickOptions:{formatString : '%.2fG'}
            }
        },
        legend : {
            show: true,
            location: 'nw'
        },
        series:[{label:'Used'}, {label: 'Total'}],
        seriesDefaults : {showMarker: false}
    });
}

/**
 * Draw disk usage flot
 * 
 * @param node Node name
 * @param freePair Free disk space (Ganglia only logs free data)
 * @param totalPair Total disk space
 */
function drawDiskFlot(node, freePair, totalPair) {
    var used = new Array();
    var total = new Array();
    var size = 0;

    // Append flot to node monitoring fieldset
    var diskFlot = $('<div id="' + node + '_disk"></div>').css({
        'float' : 'left',
        'height' : '150px',
        'margin' : '0 0 10px',
        'width' : '300px'
    });
    $('#' + node + '_monitor').append(diskFlot);
    $('#' + node + '_disk').empty();

    if (freePair.length < totalPair.length) {
        size = freePair.length;
    } else {
        size = freePair.length;
    }

    var tmpTotal, tmpUsed;
    for ( var i = 0; i < size; i += 2) {
        tmpTotal = totalPair[i + 1];
        tmpUsed = tmpTotal - freePair[i + 1];
        total.push([ totalPair[i] * 1000, tmpTotal ]);
        used.push([ freePair[i] * 1000, tmpUsed ]);
    }

    $.jqplot(node + '_disk', [ used, total ], {
        title : 'Disk Use Last Hour',
        axes : {
            xaxis : {
                renderer : $.jqplot.DateAxisRenderer,
                numberTicks : 4,
                tickOptions : {
                    formatString : '%R',
                    show : true
                }
            },
            yaxis : {
                min : 0,
                tickOptions : {
                    formatString : '%.2fG'
                }
            }
        },
        legend : {
            show : true,
            location : 'nw'
        },
        series : [ {
            label : 'Used'
        }, {
            label : 'Total'
        } ],
        seriesDefaults : {
            showMarker : false
        }
    });
}

/**
 * Draw network usage flot
 * 
 * @param node Node name
 * @param freePair Free memory timestamp and value pair
 * @param totalPair Total memory timestamp and value pair
 */
function drawNetworkFlot(node, inPair, outPair) {
    var inArray = new Array();
    var outArray = new Array();
    var maxVal = 0;
    var unitName = 'B';
    var divisor = 1;

    // Append flot to node monitoring fieldset
    var diskFlot = $('<div id="' + node + '_network"></div>').css({
        'float' : 'left',
        'height' : '150px',
        'margin' : '0 0 10px',
        'width' : '300px'
    });
    $('#' + node + '_monitor').append(diskFlot);
    $('#' + node + '_network').empty();
    
    for (var i = 0; i < inPair.length; i += 2) {
        if (inPair[i + 1] > maxVal) {
            maxVal = inPair[i + 1];
        }
    }

    for (var i = 0; i < outPair.length; i += 2) {
        if (outPair[i + 1] > maxVal) {
            maxVal = outPair[i + 1];
        }
    }

    if (maxVal > 3000000) {
        divisor = 1000000;
        unitName = 'GB';
    } else if (maxVal >= 3000) {
        divisor = 1000;
        unitName = 'MB';
    } else {
        // Do nothing
    }

    for (i = 0; i < inPair.length; i += 2) {
        inArray.push([ (inPair[i] * 1000), (inPair[i + 1] / divisor) ]);
    }

    for (i = 0; i < outPair.length; i += 2) {
        outArray.push([ (outPair[i] * 1000), (outPair[i + 1] / divisor) ]);
    }

    $.jqplot(node + '_network', [ inArray, outArray ], {
        title : 'Network Last Hour',
        axes : {
            xaxis : {
                renderer : $.jqplot.DateAxisRenderer,
                numberTicks : 4,
                tickOptions : {
                    formatString : '%R',
                    show : true
                }
            },
            yaxis : {
                min : 0,
                tickOptions : {
                    formatString : '%d' + unitName
                }
            }
        },
        legend : {
            show : true,
            location : 'nw'
        },
        series : [ {
            label : 'In'
        }, {
            label : 'Out'
        } ],
        seriesDefaults : {
            showMarker : false
        }
    });
}

/**
 * Get an attribute of a given node
 * 
 * @param node The node
 * @param attrName The attribute
 * @return The attribute of the node
 */
function getNodeAttr(node, attrName) {
    // Get the row
    var row = $('[id=' + node + ']').parents('tr');

    // Search for the column containing the attribute
    var attrCol = null;
    
    var cols = row.parents('.dataTables_scroll').find('.dataTables_scrollHead thead tr:eq(0) th');
    // Loop through each column
    for (var i in cols) {
        // Find column that matches the attribute
        if (cols.eq(i).html() == attrName) {
            attrCol = cols.eq(i);
            break;
        }
    }
    
    // If the column containing the attribute is found
    if (attrCol) {
        // Get the attribute column index
        var attrIndex = attrCol.index();

        // Get the attribute for the given node
        var attr = row.find('td:eq(' + attrIndex + ')');
        return attr.text();
    } else {
        return '';
    }
}

/**
 * Set the maximum number of VMs a user could have
 */
function setMaxVM() {
    var userName = $.cookie('xcat_username');
    
    $.ajax( {
        url : 'lib/srv_cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webportal',
            tgt : '',
            args : 'getmaxvm;' + userName,
            msg : ''
        },

        success : function(data) {
            // Get response
            var rsp = jQuery.trim(data.rsp);
            rsp = rsp.replace('Max allowed:', '');
            
            // Set cookie to expire in 60 minutes
            var exDate = new Date();
            exDate.setTime(exDate.getTime() + (240 * 60 * 1000));
            $.cookie(userName + '_maxvm', rsp, { expires: exDate });
        }
    });
}