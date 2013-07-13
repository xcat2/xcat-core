/**
 * Global variables
 */
var nodesTab; // Nodes tabs
var origAttrs = new Object(); // Original node attributes
var nodeAttrs; // Node attributes
var nodesList; // Node list
var nodesTableId = 'nodesDatatable'; // Nodes datatable ID

/**
 * Set node tab
 * 
 * @param tab
 *            Tab object
 * @return Nothing
 */
function setNodesTab(tab) {
    nodesTab = tab;
}

/**
 * Get node tab
 * 
 * @return Tab object
 */
function getNodesTab() {
    return nodesTab;
}

/**
 * Get node list
 * 
 * @return Node list
 */
function getNodesList() {
    return nodesList;
}

/**
 * Get nodes table ID
 * 
 * @return Nodes table ID
 */
function getNodesTableId() {
    return nodesTableId;
}

/**
 * Load nodes page
 */
function loadNodesPage() {
    // If groups are not already loaded
    if (!$('#groups').length) {
        // Create a groups division
        var groups = $('<div id="groups"></div>');
        var nodes = $('<div id="nodes"></div>');
        $('#content').append(groups);
        $('#content').append(nodes);

        // Create loader and info bar
        groups.append(createLoader());

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

            // Load groups
            success : function(data){
                loadGroups(data);
                
                var cookieGroup = $.cookie('selectgrouponnodes');
                if (cookieGroup) {
                    $('#groups .groupdiv div').each(function(){
                        if ($(this).text() == cookieGroup){
                            $(this).trigger('click');
                            return false;
                        }
                    });
                } else {
                    // Trigger the first group click event
                    $('#groups .groupdiv div').eq(0).trigger('click');
                }
            }
        });
    }
}

/**
 * Show cluster summary in pie charts
 * 
 * @param groupName Group name
 */
function loadPieSummary(groupName){
    var summaryTable = '<table style="border: 0px none;">' +
                       '<tr>' +
                           '<td><div id="statuspie" class="summarypie"></div></td>' +
                           '<td><div id="ospie" class="summarypie"></div></td>' +
                           '<td><div id="archpie" class="summarypie"></div></td>' +
                       '</tr>' +
                       '<tr>' +
                           '<td><div id="provmethodpie" class="summarypie"></td>' +
                           '<td><div id="nodetypepie" class="summarypie"></div></td>' +
                       '</tr></table>';
    $('#summaryTab').append(summaryTable);
    $('#summaryTab .summarypie').append(createLoader());
    
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'webrun',
            tgt : '',
            args : 'summary;' + groupName,
            msg : '' 
        },
        
        success:function(data) {
             for (var i in data.rsp) {
                 drawPieSummary(i, data.rsp[i]);
             }
        }
    });
}

/**
 * Get nodes information and draw pie chart
 * 
 * @param index Node index
 * @param valuePair Node information key value pairing
 */
function drawPieSummary(index, valuePair){
    var position = 0;
    var key = '';
    var val = '';
    var chartTitle = '';
    var dataArray = [];
    var tempArray = [];
    var container = $('#summaryTab .summarypie').eq(index);
    
    position = valuePair.indexOf('=');
    chartTitle = valuePair.substr(0, position);
    tempArray = valuePair.substr(position + 1).split(';');
    
    for (var i in tempArray) {
        position = tempArray[i].indexOf(':');
        key = tempArray[i].substr(0, position);
        val = Number(tempArray[i].substr(position + 1));
        dataArray.push([key,val]);
    }
                
    container.empty();
    
    var plot = $.jqplot(container.attr('id'), [dataArray], {
                title: chartTitle,
                seriesDefaults: {
                renderer: $.jqplot.PieRenderer,
                rendererOptions: {
                    padding: 5,
                    fill: true,
                    shadow: true,
                    shadowOffset: 2,
                    shadowDepth: 5,
                    shadowAlpha: 0.07,
                    dataLabels : 'value',
                    showDataLabels: true
                    }
                },
                legend: {
                    show:true,
                    location: 'e'
                }
            });
}

/**
 * Load groups
 * 
 * @param data Data returned from HTTP request
 */
function loadGroups(data) {
    // Remove loader
    $('#groups').find('img').remove();
    
    // Save group in cookie
    var groups = data.rsp;
    setGroupsCookies(data);

    // Create a list of groups
    $('#groups').append('<div class="grouplabel">Groups</div>');
    var grouplist= $('<div class="groupdiv"></div>');
    // Create a link for each group
    for (var i = 0; i < groups.length; i++) {
        grouplist.append('<div>' + groups[i] + '</div>');
    }
    
    $('#groups').append(grouplist);
    
    // Bind the click event
    $('#groups .groupdiv div').bind('click', function(){
        var thisGroup = $(this).text();
        $('#groups .groupdiv div').removeClass('selectgroup');
        $(this).addClass('selectgroup');
        
        // Save selected group into cookie
        $.cookie('selectgrouponnodes', thisGroup, { expires: 7 });
        
        drawNodesArea(thisGroup,'',thisGroup);
    });
    
    // Make a link to add nodes
    $('#groups').append('<div class="actionDiv" id="adddiv"></div>');
    $('#groups #adddiv').append(mkAddNodeLink());
}

/**
 * Empty the nodes area and add three tabs for nodes result
 * 
 * @param targetgroup The name range for nodels command
 * @param cmdargs Filter arguments for nodels command
 * @param message The useful information from the HTTP request
 */
function drawNodesArea(targetgroup, cmdargs, message){
    // Clear nodes division
    $('#nodes').empty();
    
    // Create a tab for this group
    var tab = new Tab('nodesPageTabs');
    setNodesTab(tab);
    tab.init();
    $('#nodes').append(tab.object());
    tab.add('summaryTab', 'Summary', '', false);
    tab.add('nodesTab', 'Nodes', '', false);
    tab.add('graphTab', 'Graphic', '', false);
           
    // Load nodes table when tab is selected
    $('#nodesPageTabs').bind('tabsselect', function(event, ui) {
        // Load summary when tab is selected
        if (!$('#summaryTab').children().length && ui.index == 0) {
            loadPieSummary(targetgroup);
        }
        
        // Load nodes table when tab is selected
        else if (!$('#nodesTab').children().length && ui.index == 1) {
            // Create loader
            $('#nodesTab').append($('<center></center>').append(createLoader()));
                    
            // To improve performance, get all nodes within selected group
            // Get node definitions only for first 50 nodes
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'nodels',
                    tgt : targetgroup,
                    args : cmdargs,
                    msg : message
                },

                /**
                 * Get node definitions for first 50 nodes
                 * 
                 * @param data Data returned from HTTP request
                 */
                success : function(data) {
                    var rsp = data.rsp;
                    var group = data.msg;
                    
                    // Save nodes in a list so it can be accessed later
                    nodesList = new Array();
                    for (var i in rsp) {
                        if (rsp[i][0]) {
                            nodesList.push(rsp[i][0]);
                        }
                    }
                    
                    // Sort nodes list
                    nodesList.sort();
                    
                    // Get first 50 nodes
                    var nodes = '';
                    for (var i = 0; i < nodesList.length; i++) {
                        if (i > 49) {
                            break;
                        }
                        
                        nodes += nodesList[i] + ',';                        
                    }
                                
                    // Remove last comma
                    nodes = nodes.substring(0, nodes.length-1);
                    
                    // Get nodes definitions
                    $.ajax( {
                        url : 'lib/cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'lsdef',
                            tgt : '',
                            args : nodes,
                            msg : targetgroup
                        },

                        success : loadNodes
                    });
                    
                }
            });
        }
        
        // Load graphical layout when tab is selected
        else if (!$('#graphTab').children().length && ui.index == 2) {
            // For the graphical tab, check the graphical data first
            createPhysicalLayout(nodesList);
        }
    });
        
    // Get last view (if any)
    // This can be summary, nodes, or graphic
    if ($.cookie('tabindex_history')) {
        var order = $.cookie('tabindex_history').split(',');
        order[0] = parseInt(order[0]);
        order[1] = parseInt(order[1]);
        if (order[0] == 0 || order[1] == 0) {
            // For some reason, you cannot trigger a select of index 0
            loadPieSummary(targetgroup);
        } else if (order[0] == 1 || order[0] == 2) {
            $('#nodesPageTabs').tabs('select', order[0]);
        } else if (order[1] == 1 || order[1] == 2) {
            $('#nodesPageTabs').tabs('select', order[1]);
        } else {
            loadPieSummary(targetgroup);
        }
    } else {
        loadPieSummary(targetgroup);
    }
}

/**
 * Make a link to add nodes
 * 
 * @returns Link to add nodes
 */
function mkAddNodeLink() {
    // Create link to add nodes
    var addNodeLink = $('<a title="Add a node or a node range to xCAT">+ Add node</a>');
    addNodeLink.click(function() {
        // Create info bar
        var info = createInfoBar('Select the hardware management for the new node range');
        
        // Create form to add node
        var addNodeForm = $('<div class="form"></div>');
        addNodeForm.append(info);
        addNodeForm.append('<div><label>Hardware management:</label>'
            + '<select name="mgt">'
                + '<option value="esx">ESX</option>'
                + '<option value="kvm">KVM</option>'
                + '<option value="zvm">z\/VM</option>'
                + '<option value="ipmi">iDataPlex</option>' 
                + '<option value="blade">BladeCenter</option>'
                + '<option value="hmc">System p</option>'    // Documentation refers to 'IBM System p' (where p is NOT capitalized)
            + '</select>'
        + '</div>');
        
        // Create advanced link to set advanced node properties
        var advanced = $('<div></div>');
        var advancedLnk = $('<a>Advanced</a>').css({
            'cursor': 'pointer',
            'color': '#0000FF'
        });
        advancedLnk.click(function() {
            // Get node attributes
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'lsdef',
                    tgt : '',
                    args : '-t;node;-h',
                    msg : ''
                },

                /**
                 * Set node attributes and open dialog
                 * 
                 * @param data Data returned from HTTP request
                 */
                success : function(data) {
                    // Save node attributes
                    setNodeAttrs(data);
                    // Open a dialog to set node attributes
                    openSetAttrsDialog();
                }
            });
            
            // Close dialog
            addNodeForm.dialog('destroy').remove();
        });
        advanced.append(advancedLnk);
        addNodeForm.append(advanced);
                    
        // Open dialog to add node
        addNodeForm.dialog({
            modal: true,
            width: 400,
            title:'Add node',
            close: function() {$(this).remove();},
            buttons: {
                'Ok': function() {
                    // Get hardware management
                    var mgt = $(this).find('select[name=mgt]').val();                    
                    
                    var plugin;
                    switch(mgt) {
                        case "kvm":
                            plugin = new kvmPlugin();
                            break;
                        case "esx":
                            plugin = new esxPlugin();
                            break;
                        case "blade":
                            plugin = new bladePlugin();
                            break;
                        case "hmc":
                            plugin = new hmcPlugin();
                            break;
                        case "ipmi":
                            plugin = new ipmiPlugin();
                            break;
                        case "zvm":
                            plugin = new zvmPlugin();
                            break;
                    }
                    
                    $(this).dialog('destroy').remove();
                    plugin.addNode();
                },
                'Cancel': function(){
                    $(this).dialog('destroy').remove();
                }
            }
        });

    });
    
    // Generate tooltips
    addNodeLink.tooltip({
        position: 'center right',
        offset: [-2, 10],
        effect: 'fade',
        opacity: 0.7,
        predelay: 800
    });
    
    return addNodeLink;
}

/**
 * Load nodes belonging to a given group
 * 
 * @param data Data returned from HTTP request
 */
function loadNodes(data) {
    // Clear the tab before inserting the table
    $('#nodesTab').children().remove();

    // Data returned    
    var rsp = data.rsp;
    // Group name
    var group = data.msg;
    // Hash of Node attributes
    var attrs = new Object();
    // Node attributes
    var headers = new Object();
    
    // Variable to send command and request node status
    var getNodeStatus = true;

    // Clear hash table containing node attributes
    origAttrs = '';
    
    var node, args;
    for (var i in rsp) {
        // Get node name
        if (rsp[i].indexOf('Object name:') > -1) {
            var temp = rsp[i].split(': ');
            node = jQuery.trim(temp[1]);

            // Create a hash for the node attributes
            attrs[node] = new Object();
            i++;
        }

        // Get key and value
        args = rsp[i].split('=', 2);
        var key = jQuery.trim(args[0]);
        var val = jQuery.trim(rsp[i].substring(rsp[i].indexOf('=') + 1));
        
        // Create a hash table
        attrs[node][key] = val;
        headers[key] = 1;
        
        // If node status is available
        if (key == 'status') {
            // Do not request node status
            getNodeStatus = false;
        }
    }
    
    // Add nodes that are not in data returned
    for (var i in nodesList) {
        if (!attrs[nodesList[i]]) {
            // Create attributes list and save node name
            attrs[nodesList[i]] = new Object();
            attrs[nodesList[i]]['node'] = nodesList[i];
        }
    }
    
    // Save attributes in hash table
    origAttrs = attrs;

    // Sort headers
    var sorted = new Array();
    for (var key in headers) {
        // Do not put comments and status in twice
        if (key != 'usercomment' && key != 'status' && key.indexOf('status') < 0) {
            sorted.push(key);
        }
    }
    sorted.sort();

    // Add column for check box, node, ping, power, monitor, and comments
    sorted.unshift('<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">', 
        'node', 
        '<span><a>status</a></span><img src="images/loader.gif"></img>', 
        '<span><a>power</a></span><img src="images/loader.gif" style="display: none;"></img>',
        '<span><a>monitor</a></span><img src="images/loader.gif" style="display: none;"></img>',
        'comments');

    // Create a datatable
    var nodesTable = new DataTable(nodesTableId);
    nodesTable.init(sorted);
    
    // Go through each node
    for (var node in attrs) {
        // Create a row
        var row = new Array();
        
        // Create a check box, node link, and get node status
        var checkBx = '<input type="checkbox" name="' + node + '"/>';
        var nodeLink = $('<a class="node" id="' + node + '">' + node + '</a>').bind('click', loadNode);
        
        // If there is no status attribute for the node, do not try to access hash table
        // else the code will break
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
            if (key != 'usercomment' && key != 'status' && key.indexOf('status') < 0) {
                var val = attrs[node][key];
                if (val) {
                    row.push(val);
                } else {
                    row.push('');
                }
            }
        }

        // Add the row to the table
        nodesTable.add(row);
    }

    // Clear the tab before inserting the table
    $('#nodesTab').children().remove();
    
    // Create info bar for nodes tab
    var info = createInfoBar('Double-click on a cell to edit a node\'s properties.  Click outside the table to save changes.  Hit the Escape key to ignore changes.');
    $('#nodesTab').append(info);

    // Create action bar
    var actionBar = $('<div class="actionBar"></div>').css("width", "400px");

    /**
     * Create menu for actions to perform against a given node
     */

    // Power on
    var powerOnLnk = $('<a>Power on</a>');
    powerOnLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {
            powerNode(tgtNodes, 'on');
        }
    });
    
    // Power off
    var powerOffLnk = $('<a>Power off</a>');
    powerOffLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {
            powerNode(tgtNodes, 'off');
        }
    });
    
    // Power softoff
    var powerSoftoffLnk = $('<a>Shutdown</a>');
    powerSoftoffLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {
            powerNode(tgtNodes, 'softoff');
        }
    });
    
    // Turn monitoring on
    var monitorOnLnk = $('<a>Monitor on</a>');
    monitorOnLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {
            monitorNode(tgtNodes, 'on');
        }
    });

    // Turn monitoring off
    var monitorOffLnk = $('<a>Monitor off</a>');
    monitorOffLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {
            monitorNode(tgtNodes, 'off');
        }
    });

    // Clone
    var cloneLnk = $('<a>Clone</a>');
    cloneLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId).split(',');
        for (var i in tgtNodes) {
            var mgt = getNodeAttr(tgtNodes[i], 'mgt');

            // Create an instance of the plugin
            var plugin;
            switch(mgt) {
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
            
            plugin.loadClonePage(tgtNodes[i]);
        }
    });

    // Delete
    var deleteLnk = $('<a>Delete</a>');
    deleteLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {
            loadDeletePage(tgtNodes);
        }
    });

    // Unlock
    var unlockLnk = $('<a>Unlock</a>');
    unlockLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {
            loadUnlockPage(tgtNodes);
        }
    });

    // Run script
    var scriptLnk = $('<a>Run script</a>');
    scriptLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {            
            loadScriptPage(tgtNodes);
        }
    });
    
    // Migrate VM
    var migrateLnk = $('<a>Migrate</a>');
    migrateLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId).split(',');
        var mgt = "", tmp = "";
        for (var i in tgtNodes) {
            tmp = getNodeAttr(tgtNodes[i], 'mgt');
            if (!mgt) {
                mgt = tmp
            } else {
                if (tmp != mgt) {
                    openDialog('warn', "You can pick only one type (mgt) of node to migrate!");
                    return;
                }
            }
        }
        
        // Create an instance of the plugin
        var plugin;
        switch(mgt) {
            // Only hypervisors support migration
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
        
        plugin.loadMigratePage(tgtNodes);
    });

    // Update
    var updateLnk = $('<a>Update</a>');
    updateLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {
            loadUpdatenodePage(tgtNodes);
        }
    });

    // Set boot state
    var setBootStateLnk = $('<a>Set boot state</a>');
    setBootStateLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {
            loadNodesetPage(tgtNodes);
        }
    });

    // Boot to network
    var boot2NetworkLnk = $('<a>Boot to network</a>');
    boot2NetworkLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {
            loadNetbootPage(tgtNodes);
        }
    });
    
    // Provision node
    var provisionLnk = $('<a>Provision</a>');
    provisionLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes){
            // Jump directly to the provision page
            jump2Provision(tgtNodes);
        }
    });

    // Remote console
    var rcons = $('<a>Open console</a>');
    rcons.bind('click', function(event){
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {
            loadRconsPage(tgtNodes);
        }
    });
    
    // Edit properties
    var editProps = $('<a>Edit properties</a>');
    editProps.bind('click', function(event){
        var tgtNodes = getNodesChecked(nodesTableId).split(',');
        for (var i in tgtNodes) {
            editNodeProps(tgtNodes[i]);
        }
    });
    
    // Install Ganglia
    var installMonLnk = $('<a>Install monitoring</a>');
    installMonLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {
            installGanglia(tgtNodes);
        }
    });
    
    // Scan
    var rscanLnk = $('<a>Scan</a>');
    rscanLnk.bind('click', function(event){
        var tgtNodes = getNodesChecked(nodesTableId);
        if (tgtNodes) {
            loadRscanPage(tgtNodes);
        }
    });
    
    // Event log
    var logLnk = $('<a>Event log</a>');
    logLnk.click(function() {
        var tgtNodes = getNodesChecked(nodesTableId).split(',');
        for (var i in tgtNodes) {
            var mgt = getNodeAttr(tgtNodes[i], 'mgt');

            // Create an instance of the plugin
            var plugin;
            switch(mgt) {
                case "kvm":
                    plugin = new kvmPlugin();
                    break;
                case "esx":
                    plugin = new esxPlugin();
                    break;
                case "blade":
                    plugin = new bladePlugin();
                    break;
                case "hmc":
                    plugin = new hmcPlugin();
                    break;
                case "ipmi":
                    plugin = new ipmiPlugin();
                    break;
                case "zvm":
                    plugin = new zvmPlugin();
                    break;
            }
            
            plugin.loadLogPage(tgtNodes[i]);
        }
    });
    
    // Actions
    var actionsLnk = '<a>Actions</a>';
    var actsMenu = createMenu([cloneLnk, deleteLnk, migrateLnk, monitorOnLnk, monitorOffLnk, powerOnLnk, powerOffLnk, scriptLnk, powerSoftoffLnk]);

    // Configurations
    var configLnk = '<a>Configuration</a>';
    var configMenu = createMenu([editProps, logLnk, installMonLnk, rscanLnk, unlockLnk, updateLnk]);

    // Provision
    var provLnk = '<a>Provision</a>';
    var provMenu = createMenu([boot2NetworkLnk, rcons, setBootStateLnk, provisionLnk]);

    // Create an action menu
    var actionsMenu = createMenu([ [ actionsLnk, actsMenu ], [ configLnk, configMenu ],  [ provLnk, provMenu ] ]);
    actionsMenu.superfish();
    actionsMenu.css('display', 'inline-block');
    actionBar.append(actionsMenu);
    
    // Set correct theme for action menu
    actionsMenu.find('li').hover(function() {
        setMenu2Theme($(this));
    }, function() {
        setMenu2Normal($(this));
    });

    // Insert action bar and nodes datatable
    $('#nodesTab').append(nodesTable.object());
        
    // Turn table into a datatable
    var nodesDatatable = $('#' + nodesTableId).dataTable({
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
    
    // Filter table when enter key is pressed
    $('#' + nodesTableId + '_filter input').unbind();
    $('#' + nodesTableId + '_filter input').bind('keyup', function(e){
        if (e.keyCode == 13) {
            var table = $('#' + nodesTableId).dataTable();
            table.fnFilter($(this).val());
            
            // If there are nodes found, get the node attributes
            if (!$('#' + nodesTableId + ' .dataTables_empty').length) {
                getNodeAttrs(group);
            }
        }
    });
    
    // Load node definitions when next or previous buttons are clicked
    $('#' + nodesTableId + '_next, #' + nodesTableId + '_previous').click(function() {
        getNodeAttrs(group);
    });
    
    /**
     * Change how datatable behaves
     */
    
    // Do not sort ping, power, and comment column
    var cols = $('#' + nodesTableId + ' thead tr th').click(function() {        
        getNodeAttrs(group);
    });
    var checkboxCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(0)');
    var pingCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(2)');
    var powerCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(3)');
    var monitorCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(4)');
    var commentCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(5)');
    checkboxCol.unbind('click');
    pingCol.unbind('click');
    powerCol.unbind('click');
    monitorCol.unbind('click');
    commentCol.unbind('click');
    
    // Create enough space for loader to be displayed
    // Center align power, ping, and comments
    $('#' + nodesTableId + ' td:nth-child(3),td:nth-child(4),td:nth-child(5)').css({
        'text-align': 'center'
    });
    
    // No minimum width for comments column
    $('#' + nodesTableId + ' tbody tr td:nth-child(6)').css('text-align', 'center');
    
    // Instead refresh the node, power, and monitor status
    pingCol.find('span a').click(function() {
        refreshNodeStatus(group, nodesTableId);
    });
    powerCol.find('span a').click(function() {
        refreshPowerStatus(group, nodesTableId);
    });
    monitorCol.find('span a').click(function() {
        refreshGangliaStatus(group, nodesTableId);
    });
    
    // Create a division to hold actions menu
    var menuDiv = $('<div id="' + nodesTableId + '_menuDiv" class="menuDiv"></div>');
    $('#' + nodesTableId + '_wrapper').prepend(menuDiv);
    menuDiv.append(actionBar);    
    $('#' + nodesTableId + '_filter').appendTo(menuDiv);
    
    // Create tooltip for status
    var tooltipConf = {
            position: "center right",
            offset: [-2, 10],
            effect: "fade",    
            opacity: 0.8,
            relative: true,
            predelay: 800
        };

    var pingTip = createStatusToolTip();
    pingCol.find('span').append(pingTip);
    pingCol.find('span a').tooltip(tooltipConf);
    
    // Create tooltip for power
    var powerTip = createPowerToolTip();
    powerCol.find('span').append(powerTip);
    powerCol.find('span a').tooltip(tooltipConf);
    
    // Create tooltip for monitor
    var monitorTip = createMonitorToolTip();
    monitorCol.find('span').append(monitorTip);
    monitorCol.find('span a').tooltip(tooltipConf);
    
    /**
     * Enable editable columns
     */
    // Do not make 1st, 2nd, 3rd, 4th, 5th, or 6th column editable
    $('#' + nodesTableId + ' td:not(td:nth-child(1),td:nth-child(2),td:nth-child(3),td:nth-child(4),td:nth-child(5),td:nth-child(6))').editable(
        function(value, settings) {     
            // If users did not make changes, return the value directly
            // jeditable saves the old value in this.revert
            if ($(this).attr('revert') == value){
                return value;
            }
            
            // Get column index
            var colPos = this.cellIndex;
                        
            // Get row index
            var dTable = $('#' + nodesTableId).dataTable();
            var rowPos = dTable.fnGetPosition(this.parentNode);
            
            // Update datatable
            dTable.fnUpdate(value, rowPos, colPos, false);
            
            // Get table headers
            var headers = $('#' + nodesTableId).parents('.dataTables_scroll').find('.dataTables_scrollHead thead tr:eq(0) th');
                        
            // Get node name
            var node = $(this).parent().find('td a.node').text();
            // Get attribute name
            var attrName = jQuery.trim(headers.eq(colPos).text());
            // Get column value
            var value = $(this).text();
            
            // Build argument
            var args = attrName + '=' + value;
            
            // Send command to change node attributes
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'chdef',
                    tgt : '',
                    args : '-t;node;-o;' + node + ';' + args,
                    msg : 'out=nodesTab;tgt=' + node
                },

                success: showChdefOutput
            });
            
            // Save the data into global origAttrs
            origAttrs[node][attrName] = value;

            return value;
        }, {
            onblur : 'submit',     // Clicking outside editable area submits changes
            type : 'textarea',
            placeholder: ' ',
            event : "dblclick", // Double click and edit
            height : '30px'     // The height of the text area
        });
    
    /**
     * Get the node status and definable node attributes
     */

    // If request to get node status is made
    if (getNodeStatus) {
        var tgt = getNodesShown(nodesTableId);
        
        // Get node status
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'nodestat',
                tgt : tgt,
                args : '-u',
                msg : ''
            },
    
            success : loadNodeStatus
        });
    } else {
        // Hide status loader
        var statCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(2)');
        statCol.find('img').hide();
        adjustColumnSize(nodesTableId);
    }
    
    if (undefined == nodeAttrs){
        // Get definable node attributes
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'lsdef',
                tgt : '',
                args : '-t;node;-h',
                msg : ''
            },

            success : setNodeAttrs
        });
    }
    
    /**
     * Additional ajax requests need to be made for zVM
     * load advanced information based on hardware architecture 
     */
    advancedLoad(group);
}

/**
 * Get nodes currently shown in datatable
 * 
 * @param tableId Datatable ID
 * @return String of nodes shown
 */
function getNodesShown(tableId) {
    // String of nodes shown
    var shownNodes = '';
    
    // Get rows of shown nodes
    var nodes = $('#' + tableId + ' tbody tr');
                
    // Go through each row
    var cols;
    for (var i = 0; i < nodes.length; i++) {
        // Get second column containing node name
        cols = nodes.eq(i).find('td');
        shownNodes += cols.eq(1).text() + ',';
    }
    
    // Remove last comma
    shownNodes = shownNodes.substring(0, shownNodes.length-1);
    return shownNodes;
}

/**
 * Get attributes for nodes not yet initialized
 * 
 * @param group Group name
 */
function getNodeAttrs(group) {    
    // Get datatable headers and rows
    var headers = $('#' + nodesTableId).parents('.dataTables_scroll').find('.dataTables_scrollHead thead tr:eq(0) th');
    var nodes = $('#' + nodesTableId + ' tbody tr');
    
    // Find group column
    var head, groupsCol;
    for (var i = 0; i < headers.length; i++) {
        head = headers.eq(i).html();
        if (head == 'groups') {
            groupsCol = i;
            break;
        }
    }

    // Check if groups definition is set
    var node, cols;
    var tgtNodes = '';
    for (var i = 0; i < nodes.length; i++) {
        cols = nodes.eq(i).find('td');
        if (!cols.eq(groupsCol).html()) {
            node = cols.eq(1).text();
            tgtNodes += node + ',';
        }
    }
        
    // If there are node definitions to load
    if (tgtNodes) {
        // Remove last comma
        tgtNodes = tgtNodes.substring(0, tgtNodes.length-1);
                
        // Get node definitions
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'lsdef',
                tgt : '',
                args : tgtNodes,
                msg : group
            },
    
            success : addNodes2Table
        });
        
        // Create dialog to indicate table is updating
        var update = $('<div id="updatingDialog"></div>');
        update.append(createInfoBar('Updating table <img src="images/loader.gif"/>'));
        
        update.dialog({
            title: 'Updating',
            modal: true,
            width: 300,
            position: 'center'
        });
    }
}

/**
 * Add nodes to datatable
 * 
 * @param data Data returned from HTTP request
 */
function addNodes2Table(data) {
    // Data returned
    var rsp = data.rsp;
    // Group name
    var group = data.msg;
    // Hash of node attributes
    var attrs = new Object();
    // Node attributes
    var headers = $('#' + nodesTableId).parents('.dataTables_scroll').find('.dataTables_scrollHead thead tr th');
    
    // Variable to send command and request node status
    var getNodeStatus = true;
    
    // Go through each attribute
    var node, args;
    for (var i in rsp) {
        // Get node name
        if (rsp[i].indexOf('Object name:') > -1) {
            var temp = rsp[i].split(': ');
            node = jQuery.trim(temp[1]);

            // Create a hash for node attributes
            attrs[node] = new Object();
            i++;
        }

        // Get key and value
        args = rsp[i].split('=', 2);
        var key = jQuery.trim(args[0]);
        var val = jQuery.trim(rsp[i].substring(rsp[i].indexOf('=') + 1, rsp[i].length));
        
        // Create a hash table
        attrs[node][key] = val;
        // Save attributes in original hash table
        origAttrs[node][key] = val;
                
        // If node status is available
        if (key == 'status') {
            // Do not request node status
            getNodeStatus = false;
        }
    }
        
    // Set the first five headers
    var headersCol = new Object();
    headersCol['node'] = 1;
    headersCol['status'] = 2;
    headersCol['power'] = 3;
    headersCol['monitor'] = 4;
    headersCol['comments'] = 5;
    
    // Go through each header
    for (var i = 6; i < headers.length; i++) {
        // Get the column index
        headersCol[headers.eq(i).html()] = i;
    }

    // Go through each node
    var datatable = $('#' + nodesTableId).dataTable();
    var rows = datatable.fnGetData();
    for (var node in attrs) {
        // Get row containing node
        var nodeRowPos = 0;
        for (var i in rows) {
            // If column contains node
            if (rows[i][1].indexOf('>' + node + '<') > -1) {
                nodeRowPos = i;
                break;
            }
        }
        
        // Get node status
        var status = '';
        if (attrs[node]['status']){
            status = attrs[node]['status'].replace('sshd', 'ping');
        }
        
        rows[nodeRowPos][headersCol['status']] = status;
        
        // Go through each header
        for (var key in headersCol) {
            // Do not put comments and status in twice
            if (key != 'usercomment' && key != 'status' && key.indexOf('status') < 0) {
                var val = attrs[node][key];
                if (val) {
                    rows[nodeRowPos][headersCol[key]] = val;
                }
            }
        }
        
        // Update row
        datatable.fnUpdate(rows[nodeRowPos], nodeRowPos, 0, false);
        
        // Insert node comments
        // This is done after datatable is updated because
        // you cannot insert an object using fnUpdate()
        var comments = attrs[node]['usercomment'];
        
        // If no comments exists, show 'No comments' and
        // set icon image source
        var iconSrc;
        if (!comments) {
            comments = 'No comments';
            iconSrc = 'images/nodes/ui-icon-no-comment.png';
        } else {
            iconSrc = 'images/nodes/ui-icon-comment.png';
        }
        
        // Create icon for node comments
        var tipID = node + 'Tip';
        var commentsCol = $('#' + node).parent().parent().find('td').eq(5);
        
        // Create tooltip
        var icon = $('<img id="' + tipID + '" src="' + iconSrc + '"></img>').css({
            'width': '18px',
            'height': '18px'
        });
        
        var tip = createCommentsToolTip(comments);
        var span = $('<span></span>').append(icon);
        span.append(tip);
        commentsCol.append(span);
                
        // Generate tooltips
        icon.tooltip({
            position: "center right",
            offset: [-2, 10],
            effect: "fade",
            opacity: 0.8,
            relative: true,
            delay: 500
        });
    }
    
    // Enable node link
    $('.node').bind('click', loadNode);

    // Close dialog for updating table
    $('.ui-dialog-content').dialog('destroy').remove();
    
    /**
     * Enable editable columns
     */
    // Do not make 1st, 2nd, 3rd, 4th, 5th, or 6th column editable
    $('#' + nodesTableId + ' td:not(td:nth-child(1),td:nth-child(2),td:nth-child(3),td:nth-child(4),td:nth-child(5),td:nth-child(6))').editable(
        function(value, settings) {            
            // If users did not do changes, return the value directly
            // jeditable save the old value in this.revert
            if ($(this).attr('revert') == value){
                return value;
            }
            // Get column index
            var colPos = this.cellIndex;
                        
            // Get row index
            var dTable = $('#' + nodesTableId).dataTable();
            var rowPos = dTable.fnGetPosition(this.parentNode);
            
            // Update datatable
            dTable.fnUpdate(value, rowPos, colPos, false);
            
            // Get table headers
            var headers = $('#' + nodesTableId + ' thead tr th');
            
            // Get node name
            var node = $(this).parent().find('td a.node').text();
            // Get attribute name
            var attrName = jQuery.trim(headers.eq(colPos).text());
            // Get column value
            var value = $(this).text();
            
            // Build argument
            var args = attrName + '=' + value;
            
            // Send command to change node attributes
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'chdef',
                    tgt : '',
                    args : '-t;node;-o;' + node + ';' + args,
                    msg : 'out=nodesTab;tgt=' + node
                },

                success: showChdefOutput
            });

            return value;
        }, {
            onblur : 'submit',     // Clicking outside editable area submits changes
            type : 'textarea',
            placeholder: ' ',
            event : 'dblclick',
            height : '30px'     // The height of the text area
        });
    
    // If request to get node status is made
    if (getNodeStatus) {
        // Get node status
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'nodestat',
                tgt : group,
                args : '-u',
                msg : ''
            },
    
            success : loadNodeStatus
        });
    } else {
        // Hide status loader
        var statCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(2)');
        statCol.find('img').hide();
    }
    
    /**
     * Additional ajax requests need to be made for zVM
     */
    advancedLoad(group);
    adjustColumnSize(nodesTableId);
}

/**
 * Load the status of Ganglia for a given group
 * 
 * @param data Data returned from HTTP request
 */
function loadGangliaStatus(data) {
    // Get datatable
    var datatable = $('#' + nodesTableId).dataTable();
    var ganglia = data.rsp;
    var rowNum, node, status;

    for ( var i in ganglia) {
        // ganglia[0] = nodeName and ganglia[1] = state
        node = jQuery.trim(ganglia[i][0]);
        status = jQuery.trim(ganglia[i][1]);

        if (node) {
            // Get the row containing the node
            rowNum = findRow(node, '#' + nodesTableId, 1);
    
            // Update the power status column
            datatable.fnUpdate(status, rowNum, 4);
        }
    }

    // Hide Ganglia loader
    var gangliaCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(4)');
    gangliaCol.find('img').hide();
    adjustColumnSize(nodesTableId);
}

/**
 * Refresh the status of Ganglia for each node
 * 
 * @param group Group name
 */
function refreshGangliaStatus(group) {
    // Show ganglia loader
    var gangliaCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(4)');
    gangliaCol.find('img').show();
    
    // Get power status for nodes shown
    var nodes = getNodesShown(nodesTableId);

    // Get the status of Ganglia
    $.ajax( {
        url : 'lib/cmd.php',
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
 * Load power status for each node
 * 
 * @param data Data returned from HTTP request
 */
function loadPowerStatus(data) {
    var dTable = $('#' + nodesTableId).dataTable();
    var power = data.rsp;
    var rowPos, node, status, args;

    for (var i in power) {
        // power[0] = nodeName and power[1] = state
        args = power[i].split(':');
        node = jQuery.trim(args[0]);
        status = jQuery.trim(args[1]);
        
        // Get the row containing the node
        rowPos = findRow(node, '#' + nodesTableId, 1);

        // Update the power status column
        dTable.fnUpdate(status, rowPos, 3);
    }
    
    // Hide power loader
    var powerCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(3)');
    powerCol.find('img').hide();
    adjustColumnSize(nodesTableId);
}

/**
 * Refresh power status for each node
 * 
 * @param group Group name
 * @param tableId Table to update node status
 */
function refreshPowerStatus(group, tableId) {
    // Show power loader
    var powerCol = $('#' + tableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(3)');
    powerCol.find('img').show();
    
    // Get power status for nodes shown
    var nodes = getNodesShown(tableId);
        
    // Get power status
    $.ajax( {
        url : 'lib/cmd.php',
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
 * Load node status for each node
 * 
 * @param data Data returned from HTTP request
 */
function loadNodeStatus(data) {
    var dTable = $('#' + nodesTableId).dataTable();
    var rsp = data.rsp;
    var args, rowPos, node, status;

    // Get all nodes within datatable
    for (var i in rsp) {
        args = rsp[i].split(':');
        
        // args[0] = node and args[1] = status
        node = jQuery.trim(args[0]);
        status = jQuery.trim(args[1]).replace('sshd', 'ping');
        
        // Get row containing node
        rowPos = findRow(node, '#' + nodesTableId, 1);

        // Update ping status column
        dTable.fnUpdate(status, rowPos, 2, false);
    }
    
    // Hide status loader
    var statCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(2)');
    statCol.find('img').hide();
    adjustColumnSize(nodesTableId);
}

/**
 * Refresh ping status for each node
 * 
 * @param group Group name
 * @param tableId Table to update node status
 */
function refreshNodeStatus(group, tableId) {
    // Show ping loader
    var pingCol = $('#' + tableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(2)');
    pingCol.find('img').show();
    
    // Get power status for nodes shown
    var nodes = getNodesShown(tableId);
    
    // Get the node status
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'nodestat',
            tgt : nodes,
            args : '-u',
            msg : ''
        },

        success : loadNodeStatus
    });
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
    var mgt = getNodeAttr(node, 'mgt');
        
    // Create an instance of the plugin
    var plugin;
    switch(mgt) {
        case "kvm":
            plugin = new kvmPlugin();
            break;
        case "esx":
            plugin = new esxPlugin();
            break;
        case "blade":
            plugin = new bladePlugin();
            break;
        case "hmc":
            plugin = new hmcPlugin();
            break;
        case "ipmi":
            plugin = new ipmiPlugin();
            break;
        case "zvm":
            plugin = new zvmPlugin();
            break;
    }

    // Get tab area where a new tab will be inserted
    var myTab = getNodesTab();
    var inst = 0;
    var newTabId = 'nodeTab' + inst;
    while ($('#' + newTabId).length) {
        // If one already exists, generate another one
        inst = inst + 1;
        newTabId = 'nodeTab' + inst;
    }
    // Reset node process
    $.cookie(node + 'Processes', 0);

    // Add new tab, only if one does not exist
    var loader = createLoader(newTabId + 'TabLoader');
    loader = $('<center></center>').append(loader);
    myTab.add(newTabId, node, loader, true);

    // Get node inventory
    var msg = 'out=' + newTabId + ',node=' + node;
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'rinv',
            tgt : node,
            args : 'all',
            msg : msg
        },

        success : plugin.loadInventory
    });

    // Select new tab
    myTab.select(newTabId);
}

/**
 * Unlock a node by setting the ssh keys
 * 
 * @param tgtNodes Nodes to unlock
 */
function loadUnlockPage(tgtNodes) {
    // Get nodes tab
    var tab = getNodesTab();

    // Generate new tab ID
    var instance = 0;
    var newTabId = 'unlockTab' + instance;
    while ($('#' + newTabId).length) {
        // If one already exists, generate another one
        instance = instance + 1;
        newTabId = 'unlockTab' + instance;
    }

    // Create status bar, hide on load
    var statBarId = 'unlockStatusBar' + instance;
    var statBar = createStatusBar(statBarId).hide();

    // Create loader
    var loader = createLoader('');
    statBar.find('div').append(loader);

    // Create info bar
    var infoBar = createInfoBar('Give the root password for this node range to setup its SSH keys.');
    
    // Create unlock form
    var unlockForm = $('<div class="form"></div>');
    unlockForm.append(statBar, infoBar);
    
    // Create VM fieldset
    var vmFS = $('<fieldset></fieldset>');
    var vmLegend = $('<legend>Virtual Machine</legend>');
    vmFS.append(vmLegend);
    unlockForm.append(vmFS);
    
    var vmAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    vmFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/computer.png"></img></div>'));
    vmFS.append(vmAttr);

    vmAttr.append('<div><label>Target node range:</label><input type="text" id="node" name="node" readonly="readonly" value="' + tgtNodes + '" title="The node or node range to unlock"/></div>');
    vmAttr.append('<div><label>Password:</label><input type="password" id="password" name="password" title="The root password to unlock this node"/></div>');

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
    
    /**
     * Ok
     */
    var unlockBtn = createButton('Unlock');
    unlockBtn.css({
        'width': '80px',
        'display': 'block'
    });
    unlockBtn.click(function() {
        // Remove any warning messages
        $(this).parents('.ui-tabs-panel').find('.ui-state-error').remove();
        
        // If a password is given
        var password = $('#' + newTabId + ' input[name=password]').css('border', 'solid #BDBDBD 1px');
        if (password.val()) {
            // Setup SSH keys
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'webrun',
                    tgt : '',
                    args : 'unlock;' + tgtNodes + ';' + password.val(),
                    msg : 'out=' + statBarId + ';cmd=unlock;tgt=' + tgtNodes
                },
    
                success : updateStatusBar
            });
    
            // Show status bar
            statBar.show();
    
            // Disable all inputs and Ok button
            $('#' + newTabId + ' input').attr('disabled', 'disabled');
            $(this).attr('disabled', 'true');
        } else {
            // Show warning message
            var warn = createWarnBar('You are missing some values!');
            warn.prependTo($(this).parents('.ui-tabs-panel'));
            password.css('border', 'solid #FF0000 1px');
        }
    });

    unlockForm.append(unlockBtn);
    tab.add(newTabId, 'Unlock', unlockForm, true);
    tab.select(newTabId);
}

/**
 * Load script page
 * 
 * @param tgtNodes Targets to run script against
 */
function loadScriptPage(tgtNodes) {
    // Get nodes tab
    var tab = getNodesTab();

    // Generate new tab ID
    var inst = 0;
    var newTabId = 'scriptTab' + inst;
    while ($('#' + newTabId).length) {
        // If one already exists, generate another one
        inst = inst + 1;
        newTabId = 'scriptTab' + inst;
    }

    // Create remote script form
    var scriptForm = $('<div class="form"></div>');
    
    // Create status bar
    var barId = 'scriptStatusBar' + inst;
    var statBar = createStatusBar(barId);
    statBar.hide();
    var loader = createLoader('scriptLoader' + inst);
    statBar.find('div').append(loader);

    // Create info bar
    var infoBar = createInfoBar('Load a script to run against this node range.');
    scriptForm.append(statBar, infoBar);
    
    // Create VM fieldset
    var vmFS = $('<fieldset></fieldset>');
    var vmLegend = $('<legend>Virtual Machine</legend>');
    vmFS.append(vmLegend);
    scriptForm.append(vmFS);
    
    var vmAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    vmFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/computer.png"></img></div>'));
    vmFS.append(vmAttr);
    
    // Create logs fieldset
    var scriptFS = $('<fieldset></fieldset>');
    var scriptLegend = $('<legend>Script</legend>');
    scriptFS.append(scriptLegend);
    scriptForm.append(scriptFS);
    
    var scriptAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    scriptFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/nodes/script.png"></img></div>'));
    scriptFS.append(scriptAttr);
        
    // Target node or group
    var tgt = $('<div><label>Target node range:</label><input type="text" name="target" value="' + tgtNodes + '" title="The node or node range to run a given script against"/></div>');
    vmAttr.append(tgt);

    // Upload file
    var upload = $('<form action="lib/upload.php" method="post" enctype="multipart/form-data"></form>');
    var label = $('<label>Remote file:</label>');
    var file = $('<input type="file" name="file" id="file"/>');
    var subBtn = createButton('Load');
    upload.append(label, file, subBtn);
    scriptAttr.append(upload);
    
    // Script
    var script = $('<div><label>Script:</label><textarea title="The code to run against the node range"/>');
    scriptAttr.append(script);
    
    // Generate tooltips
    scriptForm.find('div input[title],textarea').tooltip({
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

    // Ajax form options
    var options = {
        // Output to text area
        target : '#' + newTabId + ' textarea'
    };
    upload.ajaxForm(options);

    /**
     * Run
     */
    var runBtn = createButton('Run');
    runBtn.css({
        'width': '80px'
    });
    runBtn.click(function() { 
        // Remove any warning messages
        $(this).parents('.ui-tabs-panel').find('.ui-state-error').remove();
        
        // Get script to run
        var textarea = $('#' + newTabId + ' textarea').css('border', 'solid #BDBDBD 1px');
        
        // If no inputs are empty
        if (textarea.val()) {
            // Run script
            runScript(inst);
        } else {
            // Show warning message
            var warn = createWarnBar('You are missing some values');
            warn.prependTo($(this).parents('.ui-tabs-panel'));
            textarea.css('border', 'solid #FF0000 1px');
        }
    });
    scriptForm.append(runBtn);

    // Append to discover tab
    tab.add(newTabId, 'Script', scriptForm, true);

    // Select new tab
    tab.select(newTabId);
}

/**
 * Sort a list
 * 
 * @return Sorted list
 */
jQuery.fn.sort = function() {
    return this.pushStack([].sort.apply(this, arguments), []);
};

function sortAlpha(a, b) {
    return a.innerHTML > b.innerHTML ? 1 : -1;
};

/**
 * Power on a given node
 * 
 * @param node Node to power on or off
 * @param power2 Power node to given state
 */
function powerNode(node, power2) {
    // Show power loader
    var powerCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(3)');
    powerCol.find('img').show();
    
    node = node.replace('Power', '');
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'rpower',
            tgt : node,
            args : power2,
            msg : node
        },

        success : updatePowerStatus
    });
}

/**
 * Load delete node page
 * 
 * @param tgtNodes Nodes to delete
 */
function loadDeletePage(tgtNodes) {
    // Get nodes tab
    var myTab = getNodesTab();

    // Generate new tab ID
    var inst = 0;
    newTabId = 'deleteTab' + inst;
    while ($('#' + newTabId).length) {
        // If one already exists, generate another one
        inst = inst + 1;
        newTabId = 'deleteTab' + inst;
    }

    // Create target nodes string
    var tgtNodesStr = '';
    var nodes = tgtNodes.split(',');
    // Loop through each node
    for (var i in nodes) {
        // If it is the 1st and only node
        if (i == 0 && i == nodes.length - 1) {
            tgtNodesStr += nodes[i];
        }
        // If it is the 1st node of many nodes
        else if (i == 0 && i != nodes.length - 1) {
            // Append a comma to the string
            tgtNodesStr += nodes[i] + ', ';
        } else {
            // If it is the last node
            if (i == nodes.length - 1) {
                // Append nothing to the string
                tgtNodesStr += nodes[i];
            } else {
                // Append a comma to the string
                tgtNodesStr += nodes[i] + ', ';
            }
        }
    }

    // Create delete form
    var deleteForm = $('<div class="form"></div>');
    
    // Create status bar, hide on load
    var statBarId = 'deleteStatusBar' + inst;
    var statBar = createStatusBar(statBarId).hide();

    // Create loader
    var loader = createLoader('');
    statBar.find('div').append(loader);
    statBar.hide();    
    deleteForm.append(statBar);
    
    // Create confirm fieldset
    var confirmFS = $('<fieldset></fieldset>');
    var confirmLegend = $('<legend>Confirm</legend>');
    confirmFS.append(confirmLegend);
    deleteForm.append(confirmFS);
    
    var confirmAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    confirmFS.append($('<div style="display: inline-table; vertical-align: middle; margin-right: 10px;"><img src="images/nodes/remove.png"></img></div>'));
    confirmFS.append(confirmAttr);
    
    // Confirm delete
    var instr = $('<p>Are you sure you want to delete <b>' + tgtNodesStr + '</b>?</p>').css('word-wrap', 'break-word');
    var dbOnly = $('<div><input type="checkbox" name="db-only"/>Only delete entries in database</div>');
    confirmAttr.append(instr);
    confirmAttr.append(dbOnly);

    /**
     * Delete
     */
    var deleteBtn = createButton('Delete');
    deleteBtn.click(function() {
        var cmd = "rmvm";
        // Only delete entries in database if checked
        if ($("#" + newTabId + " input[name='db-only']").attr('checked')) {
            cmd = "noderm";
        }
        
        // Delete the virtual server
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : cmd,
                tgt : tgtNodes,
                args : '',
                msg : 'out=' + statBarId + ';cmd=' + cmd + ';tgt=' + tgtNodes
            },

            success : updateStatusBar
        });

        // Show status bar loader
        statBar.show();

        // Disable delete button
        $(this).attr('disabled', 'true');
    });
    
    /**
     * Cancel
     */
    var cancelBtn = createButton('Cancel');
    cancelBtn.bind('click', function(){
        myTab.remove($(this).parent().parent().attr('id'));
    });

    deleteForm.append(deleteBtn, cancelBtn);
    myTab.add(newTabId, 'Delete', deleteForm, true);

    myTab.select(newTabId);
}

/**
 * Update status bar of a given tab
 * 
 * @param data Data returned from HTTP request
 */
function updateStatusBar(data) {
    // Get ajax response
    var rsp = data.rsp;
    var args = data.msg.split(';');
    var statBarId = args[0].replace('out=', '');
    var cmd = args[1].replace('cmd=', '');
    var tgts = args[2].replace('tgt=', '').split(',');

    if (cmd == 'unlock' || cmd == 'updatenode') {
        // Hide loader
        $('#' + statBarId).find('img').hide();

        // Write ajax response to status bar
        var prg = writeRsp(rsp, '');    
        $('#' + statBarId).find('div').append(prg);    
    } else if (cmd == 'rmvm') {
        // Get data table
        var dTable = $('#' + nodesTableId).dataTable();
        var failed = false;

        // Hide loader
        $('#' + statBarId).find('img').hide();

        // Write ajax response to status bar
        var prg = writeRsp(rsp, '');
        $('#' + statBarId).find('div').append(prg);    
        
        // If there was an error, do not continue
        if (prg.html().indexOf('Error') > -1) {
            failed = true;
        }
    } else if (cmd == 'xdsh') {
        // Hide loader
        $('#' + statBarId).find('img').hide();
        
        // Write ajax response to status bar
        var prg = $('<pre></pre>');
        for (var i in rsp) {
            for (var j in tgts) {
                rsp[i] = rsp[i].replace(new RegExp(tgts[j] + ':', 'g'), '');
            }

            prg.append(rsp[i]);
            prg.append('<br>');    
        }
        $('#' + statBarId).find('div').append(prg);    
        
        // Enable fields
        $('#' + statBarId).parent().find('input').removeAttr('disabled');
        $('#' + statBarId).parent().find('textarea').removeAttr('disabled');
        
        // Enable buttons
        $('#' + statBarId).parent().find('button').removeAttr('disabled');
    } else if (cmd == 'noderm') {
        // Hide loader
        $('#' + statBarId).find('img').hide();
        
        // Write ajax response to status bar
        var prg = $('<pre>Entries deleted in database</pre>');   
        $('#' + statBarId).find('div').append(prg);    
    } else {
        // Hide loader
        $('#' + statBarId).find('img').hide();
        
        // Write ajax response to status bar
        var prg = writeRsp(rsp, '');    
        $('#' + statBarId).find('div').append(prg);    
    }
}

/**
 * Update power status of a node in the datatable
 * 
 * @param data Data from HTTP request
 */
function updatePowerStatus(data) {
    // Hide power loader
    var powerCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(3)');
    powerCol.find('img').hide();

    // Get datatable
    var dTable = $('#' + nodesTableId).dataTable();

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
            rowPos = findRow(node, '#' + nodesTableId, 1);

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
    
    // Adjust datatable column size
    adjustColumnSize(nodesTableId);
}

/**
 * Run a script
 * 
 * @param inst Remote script tab instance
 */
function runScript(inst) {
    // Get tab ID
    var tabId = 'scriptTab' + inst;
    // Get node name
    var tgts = $('#' + tabId + ' input[name=target]').val();
    // Get script
    var script = $('#' + tabId + ' textarea').val();
    
    var statBarId = 'scriptStatusBar' + inst;
    $('#' + statBarId).show();                    // Show status bar
    $('#' + statBarId + ' img').show();           // Show loader
    $('#' + statBarId + ' p').remove();           // Clear status bar

    // Disable all fields
    $('#' + tabId + ' input').attr('disabled', 'true');
    $('#' + tabId + ' textarea').attr('disabled', 'true');
    
    // Disable buttons
    $('#' + tabId + ' button').attr('disabled', 'true');

    // Run script
    $.ajax( {
        url : 'lib/zCmd.php',
        dataType : 'json',
        data : {
            cmd : 'xdsh',
            tgt : tgts,
            args : '-e',
            att : script,
            msg : 'out=scriptStatusBar' + inst + ';cmd=xdsh;tgt=' + tgts
        },

        success : updateStatusBar
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
    var attrCol;
    
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
 * Set a cookie for the OS images
 * 
 * @param data Data from HTTP request
 */
function setOSImageCookies(data) {
    // Get response
    var rsp = data.rsp;

    var imageNames = new Array;
    var profilesHash = new Object();
    var osVersHash = new Object();
    var osArchsHash = new Object();
    var imagePos = 0;
    var profilePos = 0;
    var osversPos = 0;
    var osarchPos = 0;
    
    // Get column value
    var colNameArray = rsp[0].substr(1).split(',');
    for (var i in colNameArray){
        switch (colNameArray[i]){
            case 'imagename':
                imagePos = i;
                break;
            case 'profile':
                profilePos = i;
                break;
            case 'osvers':
                osversPos = i;
                break;
            case 'osarch':
                osarchPos = i;
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
        var osVer = cols[osversPos].replace(new RegExp('"', 'g'), '');
        var osArch = cols[osarchPos].replace(new RegExp('"', 'g'), '');
        
        imageNames.push(osImage);
        profilesHash[profile] = 1;
        osVersHash[osVer] = 1;
        osArchsHash[osArch] = 1;
    }

    // Save image names in a cookie
    $.cookie('imagenames', imageNames);

    // Save profiles in a cookie
    var tmp = new Array;
    for (var key in profilesHash) {
        tmp.push(key);
    }
    $.cookie('profiles', tmp);

    // Save OS versions in a cookie
    tmp = new Array;
    for (var key in osVersHash) {
        tmp.push(key);
    }
    $.cookie('osvers', tmp);

    // Save OS architectures in a cookie
    tmp = new Array;
    for (var key in osArchsHash) {
        tmp.push(key);
    }
    $.cookie('osarchs', tmp);
}

/**
 * Set a cookie for the groups
 * 
 * @param data Data from HTTP request
 */
function setGroupsCookies(data) {
    var rsp = data.rsp;
    $.cookie('groups', rsp);
}

/**
 * Find the row index containing a column with a given string
 * 
 * @param str String to search for
 * @param table Table to check
 * @param col Column to find string under
 * @return The row index containing the search string
 */
function findRow(str, table, col){    
    // Get datatable
    var dTable = $(table).dataTable();
    var rows = dTable.fnGetData();
    
    // Loop through each row
    for (var i in rows) {
        // If the column contains the search string
        if (rows[i][col].indexOf(str) > -1) {
            return parseInt(i);
        }
    }
    
    return -1;
}

/**
 * Select all checkboxes in the datatable
 * 
 * @param event Event on element
 * @param obj Object triggering event
 */
function selectAllCheckbox(event, obj) {
    // Get datatable ID
    // This will ascend from <input> <td> <tr> <thead> <table>
    var tableObj = obj.parents('.dataTables_scroll').find('.dataTables_scrollBody');
    var status = obj.attr('checked');
    tableObj.find(' :checkbox').attr('checked', status);
    event.stopPropagation();
}

/**
 * Load rcons page
 * 
 * @param tgtNodes Targets to run rcons against
 */
function loadRconsPage(tgtNodes){
    var hostName = window.location.host;
    var urlPath = window.location.pathname;
    var redirectUrl = 'https://';
    var pos = 0;
    
    // We only support one node
    if (-1 != tgtNodes.indexOf(',')){
        alert("You can only open one console at a time!");
        return;
    }
    
    redirectUrl += hostName;
    pos = urlPath.lastIndexOf('/');
    redirectUrl += urlPath.substring(0, pos + 1);
    redirectUrl += 'rcons.php';
    
    // Open the rcons page
    window.open(redirectUrl + "?rconsnd=" + tgtNodes, '', "toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=no,width=590,height=436");
}

/**
 * Create a tool tip for comments
 * 
 * @param comment Comments to be placed in a tool tip
 * @return Tool tip
 */
function createCommentsToolTip(comment) {
    // Create tooltip container
    var toolTip = $('<div class="tooltip"></div>');
    // Create textarea to hold comment
    var txtArea = $('<textarea>' + comment + '</textarea>').css({
        'font-size': '10px',
        'height': '50px',
        'width': '200px',
        'background-color': '#000',
        'color': '#fff',
        'border': '0px',
        'display': 'block'
    });
    
    // Create links to save and cancel changes
    var lnkStyle = {
        'color': '#58ACFA',
        'font-size': '10px',
        'display': 'inline-block',
        'padding': '5px',
        'float': 'right'
    };
    
    var saveLnk = $('<a>Save</a>').css(lnkStyle).hide();
    var cancelLnk = $('<a>Cancel</a>').css(lnkStyle).hide();
    var infoSpan = $('<span>Click to edit</span>').css(lnkStyle);
    
    // Save changes onclick
    saveLnk.bind('click', function(){
        // Get node and comment
        var node = $(this).parent().parent().find('img').attr('id').replace('Tip', '');
        var comments = $(this).parent().find('textarea').val();
        
        // Save comment
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'chdef',
                tgt : '',
                args : '-t;node;-o;' + node + ';usercomment=' + comments,
                msg : 'out=nodesTab;tgt=' + node
            },
            
            success: showChdefOutput
        });
        
        // Hide cancel and save links
        $(this).hide();
        cancelLnk.hide();
    });
        
    // Cancel changes onclick
    cancelLnk.bind('click', function(){
        // Get original comment and put it back
        var orignComments = $(this).parent().find('textarea').text();
        $(this).parent().find('textarea').val(orignComments);
        
        // Hide cancel and save links
        $(this).hide();
        saveLnk.hide();
        infoSpan.show();
    });
    
    // Show save link when comment is edited
    txtArea.bind('click', function(){
        saveLnk.show();
        cancelLnk.show();
        infoSpan.hide();
    });
        
    toolTip.append(txtArea);
    toolTip.append(cancelLnk);
    toolTip.append(saveLnk);
    toolTip.append(infoSpan);
    
    return toolTip;
}

/**
 * Create a tool tip for node status
 * 
 * @return Tool tip
 */
function createStatusToolTip() {
    // Create tooltip container
    var toolTip = $('<div class="tooltip"></div>').css({
        'width': '150px',
        'font-weight': 'normal'
    });
    
    // Create info text
    var info = $('<p></p>').css({
        'white-space': 'normal'
    });
    info.append('Click here to refresh the node status. To configure the xCAT monitor, ');
    
    // Create link to turn on xCAT monitoring
    var monitorLnk = $('<a>click here</a>').css({
        'color': '#58ACFA',
        'font-size': '10px'
    });
    
    // Open dialog to configure xCAT monitor
    monitorLnk.bind('click', function(){
        // Check if xCAT monitor is enabled
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'monls',
                tgt : '',
                args : 'xcatmon',
                msg : ''
            },

            success : openConfXcatMon
        });
    });
    
    info.append(monitorLnk);
    toolTip.append(info);
    
    return toolTip;
}

/**
 * Create a tool tip for power status
 * 
 * @return Tool tip
 */
function createPowerToolTip() {
    // Create tooltip container
    var toolTip = $('<div class="tooltip">Click here to refresh the power status</div>').css({
        'width': '150px',
        'white-space': 'normal',
        'font-weight': 'normal'
    });
    return toolTip;
}

/**
 * Create a tool tip for monitoring status
 * 
 * @return Tool tip
 */
function createMonitorToolTip() {
    // Create tooltip container
    var toolTip = $('<div class="tooltip">Click here to refresh the monitoring status</div>').css({
        'width': '150px',
        'white-space': 'normal',
        'font-weight': 'normal'
    });    
    return toolTip;
}

/**
 * Open dialog to configure xCAT monitor
 * 
 * @param data Data returned from HTTP request
 */
function openConfXcatMon(data) {
    // Create info bar
    var info = createInfoBar('Configure the xCAT monitor. Select to enable or disable the monitor below.');
    var dialog = $('<div></div>');
    dialog.append(info);
    
    // Create status area
    var statusArea = $('<div></div>').css('padding-top', '10px');
    var label = $('<label>Status:</label>');
    statusArea.append(label);
    
    // Get xCAT monitor status
    var status = data.rsp[0];
    var buttons;
    // If xCAT monitor is disabled
    if (status.indexOf('not-monitored') > -1) {
        status = $('<span>Disabled</span>').css('padding', '0px 5px');
        statusArea.append(status);
        
        // Create enable and cancel buttons
        buttons = {
            "Enable": function(){
                // Enable xCAT monitor
                $.ajax({
                    url : 'lib/cmd.php',
                    dataType : 'json',
                    data : {
                        cmd : 'monstart',
                        tgt : '',
                        args : 'xcatmon',
                        msg : ''
                    },
    
                    success : function(data){
                        openDialog('info', data.rsp[0]);
                    }
                });
                $(this).dialog("close");
            },
            "Cancel": function(){ 
                $(this).dialog("close");
            }
        };
    } else {
        status = $('<span>Enabled</span>').css('padding', '0px 5px');
        statusArea.append(status);
        
        // Create disable and cancel buttons
        buttons = {
            "Disable": function(){
                // Disable xCAT monitor
                $.ajax({
                    url : 'lib/cmd.php',
                    dataType : 'json',
                    data : {
                        cmd : 'monstop',
                        tgt : '',
                        args : 'xcatmon',
                        msg : ''
                    },
    
                    success : function(data){
                        openDialog('info', data.rsp[0]);
                    }
                });
                $(this).dialog("close");
            },
            "Cancel": function(){ 
                $(this).dialog("close");
            }
        };
    }
    
    dialog.append(statusArea);
    
    // Open dialog
    dialog.dialog({
        modal: true,
        width: 500,
        buttons: buttons
    });
}

/**
 * Show chdef output
 * 
 * @param data Data returned from HTTP request
 */
function showChdefOutput(data) {
    // Get output
    var out = data.rsp;
    var args = data.msg.split(';');
    var tabID = args[0].replace('out=', '');
    var tgt = args[1].replace('tgt=', '');
    
    // Find info bar on nodes tab, if any
    var info = $('#' + tabID).find('.ui-state-highlight');
    if (!info.length) {
        // Create info bar if one does not exist
        info = createInfoBar('');
        $('#' + tabID).append(info);
    }
        
    // Go through output and append to paragraph
    var prg = $('<p></p>');
    for (var i in out) {
        prg.append(tgt + ': ' + out[i] + '<br>');
    }
    
    info.append(prg);
}

/**
 * Set node attributes
 * 
 * @param data Data returned from HTTP request
 */
function setNodeAttrs(data) {
    // Clear hash table containing definable node attributes
    nodeAttrs = new Array();
    
    // Get definable attributes
    var attrs = data.rsp[2].split(/\n/);

    // Go through each line
    var attr, key, descr;
    for (var i in attrs) {
        attr = attrs[i];
        
        // If the line is not empty
        if (attr) {
            // If the line has the attribute name
            if (attr.indexOf(':') && attr.indexOf(' ')) {
                // Get attribute name and description
                key = jQuery.trim(attr.substring(0, attr.indexOf(':')));
                descr = jQuery.trim(attr.substring(attr.indexOf(':') + 1));
                
                // Remove arrow brackets
                descr = descr.replace(new RegExp('<|>', 'g'), '');
                
                // Set hash table where key = attribute name and value = description
                nodeAttrs[key] = descr;
            } else {
                // Remove arrow brackets
                attr = attr.replace(new RegExp('<|>', 'g'), '');
                
                // Append description to hash table
                nodeAttrs[key] = nodeAttrs[key] + '\n' + attr;
            }
        } // End of if
    } // End of for
}

/**
 * Load set node properties page
 * 
 * @param tgtNode Target node to set properties
 */
function editNodeProps(tgtNode) {
    // Get nodes tab
    var tab = getNodesTab();

    // Generate new tab ID
    var inst = 0;
    var newTabId = 'editPropsTab' + inst;
    while ($('#' + newTabId).length) {
        // If one already exists, generate another one
        inst = inst + 1;
        newTabId = 'editPropsTab' + inst;
    }

    // Open new tab
    // Create set properties form
    var editPropsForm = $('<div class="form"></div>');

    // Create info bar
    var infoBar = createInfoBar('Choose the properties you wish to change on the node. When you are finished, click Save.');
    editPropsForm.append(infoBar);

    // Create an input for each definable attribute
    var div, label, input, descr, value;
    // Set node attribute
    origAttrs[tgtNode]['node'] = tgtNode;
    for (var key in nodeAttrs) {
        // If an attribute value exists
        if (origAttrs[tgtNode][key]) {
            // Set the value
            value = origAttrs[tgtNode][key];
        } else {
            value = '';
        }
        
        // Create label and input for attribute
        div = $('<div></div>').css('display', 'inline-table');        
        label = $('<label>' + key + ':</label>').css('vertical-align', 'middle');
        input = $('<input type="text" value="' + value + '" title="' + nodeAttrs[key] + '"/>').css('margin-top', '5px');
        
        // Change border to blue onchange
        input.bind('change', function(event) {
            $(this).css('border-color', 'blue');
        });
        
        div.append(label);
        div.append(input);
        editPropsForm.append(div);
    }

    // Change style for last division
    div.css({
        'display': 'block',
        'margin': '0px 0px 10px 0px'
    });
    
    // Generate tooltips
    editPropsForm.find('div input[title]').tooltip({
        position: "center right",
        offset: [-2, 10],
        effect: "fade",
        opacity: 0.8,
        delay: 0,
        predelay: 800,
        events: {
              def:     "mouseover,mouseout",
              input:   "mouseover,mouseout",
              widget:  "focus mouseover,blur mouseout",
              tooltip: "mouseover,mouseout"
        }
    });

    // Save changes
    var saveBtn = createButton('Save');
    saveBtn.click(function() {    
        // Get all inputs
        var inputs = $('#' + newTabId + ' input');
        
        // Go through each input
        var args = '';
        var attrName, attrVal;
        inputs.each(function(){
            // If the border color is blue
            if ($(this).css('border-left-color') == 'rgb(0, 0, 255)') {
                // Change border color back to normal
                $(this).css('border-color', '');
                
                // Get attribute name and value
                attrName = $(this).parent().find('label').text().replace(':', '');
                attrVal = $(this).val();
                
                // Build argument string
                if (args) {
                    // Handle subsequent arguments
                    args += ';' + attrName + '=' + attrVal;
                } else {
                    // Handle the 1st argument
                    args += attrName + '=' + attrVal;
                }
            }
        });
        
        // Send command to change node attributes
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'chdef',
                tgt : '',
                args : '-t;node;-o;' + tgtNode + ';' + args,
                msg : 'out=' + newTabId + ';tgt=' + tgtNode
            },

            success: showChdefOutput
        });
    });
    editPropsForm.append(saveBtn);
    
    // Cancel changes
    var cancelBtn = createButton('Cancel');
    cancelBtn.click(function() {
        // Close the tab
        tab.remove($(this).parent().parent().attr('id'));
    });
    editPropsForm.append(cancelBtn);

    // Append to discover tab
    tab.add(newTabId, 'Edit', editPropsForm, true);

    // Select new tab
    tab.select(newTabId);
}

/**
 * Open set node attributes dialog
 */
function openSetAttrsDialog() {
    // Open new tab
    // Create set properties form
    var setPropsForm = $('<div class="form"></div>');

    // Create info bar
    var infoBar = createInfoBar('Choose the properties you wish to change on the node. When you are finished, click Save.');
    setPropsForm.append(infoBar);
    
    // Create an input for each definable attribute
    var div, label, input, descr, value;
    for (var key in nodeAttrs) {
        value = '';
        
        // Create label and input for attribute
        div = $('<div></div>').css('display', 'inline');
        label = $('<label>' + key + ':</label>').css('vertical-align', 'middle');
        input = $('<input type="text" value="' + value + '" title="' + nodeAttrs[key] + '"/>').css('margin-top', '5px');
        
        // Change border to blue onchange
        input.bind('change', function(event) {
            $(this).css('border-color', 'blue');
        });
        
        div.append(label);
        div.append(input);
        setPropsForm.append(div);
    }
    
    // Change style for last division
    div.css({
        'display': 'block',
        'margin': '0px 0px 10px 0px'
    });
    
    // Generate tooltips
    setPropsForm.find('div input[title]').tooltip({
        position: "center right",
        offset: [-2, 10],
        effect: "fade",
        opacity: 0.8,
        delay: 0,
        predelay: 800,
        events: {
              def:     "mouseover,mouseout",
              input:   "mouseover,mouseout",
              widget:  "focus mouseover,blur mouseout",
              tooltip: "mouseover,mouseout"
        },

        // Change z index to show tooltip in front
        onBeforeShow: function() {
            this.getTip().css('z-index', $.topZIndex());
        }
    });
    
    // Enable vertical scroll
    setPropsForm.css('overflow', 'auto');
        
    // Open form as a dialog
    setPropsForm.dialog({
        title: 'Set attributes',
        modal: true,
        close: function(){
            $(this).remove();
        },
        height: 400,
        width: 800,
        buttons: {
            "Save": function() {
                // Remove any warning messages
                $(this).find('.ui-state-error').remove();
                
                // Get all inputs
                var inputs = $(this).find('input');
                
                // Go through each input
                var args = '';
                var tgtNode, attrName, attrVal;
                inputs.each(function(){
                    // If the border color is blue
                    if ($(this).css('border-left-color') == 'rgb(0, 0, 255)') {
                        // Change border color back to normal
                        $(this).css('border-color', '');
                        
                        // Get attribute name and value
                        attrName = $(this).parent().find('label').text().replace(':', '');
                        attrVal = $(this).val();
                        
                        // Get node name
                        if (attrName == 'node') {
                            tgtNode = attrVal;
                        } else {
                            // Build argument string
                            if (args) {
                                // Handle subsequent arguments
                                args += ';' + attrName + '=' + attrVal;
                            } else {
                                // Handle the 1st argument
                                args += attrName + '=' + attrVal;
                            }
                        }
                    }
                });
                
                // Send command to change node attributes
                $.ajax( {
                    url : 'lib/cmd.php',
                    dataType : 'json',
                    data : {
                        cmd : 'chdef',
                        tgt : '',
                        args : '-t;node;-o;' + tgtNode + ';' + args,
                        msg : 'node=' + tgtNode
                    },

                    /**
                     * Show results
                     * 
                     * @param data
                     *            Data returned from HTTP request
                     * @return Nothing
                     */
                    success: function(data) {
                        // Get output
                        var out = data.rsp;
                        var node = data.msg.replace('node=', '');
                        
                        // Go through output and append to paragraph
                        var msg = '';
                        for (var i in out) {
                            if (!msg) {
                                msg = node + ': ' + out[i];
                            } else {
                                msg += '<br>' + node + ': ' + out[i];
                            }
                        }
                        
                        openDialog('info', msg);
                    }
                });
                
                // Close dialog
                $(this).dialog( "close" );
            },
            "Cancel": function(){
                $(this).dialog( "close" );
            }
        }
    });
}

/**
 * Turn on monitoring for a given node
 * 
 * @param node Node to monitor on or off
 * @param monitor Monitor state, on or off
 */
function monitorNode(node, monitor) {
    // Show ganglia loader
    var gangliaCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(4)');
    gangliaCol.find('img').show();
    
    if (monitor == 'on') {
        // Append loader to warning bar
        var warningBar = $('#nodesTab').find('.ui-state-error p');
        if (warningBar.length) {
            warningBar.append(createLoader(''));
        }

        if (node) {
            // Check if ganglia RPMs are installed
            $.ajax( {
                url : 'lib/cmd.php',
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
                 * @param data Data returned from HTTP request
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
                            url : 'lib/cmd.php',
                            dataType : 'json',
                            data : {
                                cmd : 'webrun',
                                tgt : '',
                                args : 'gangliastart;' + data.msg + ';-r',
                                msg : data.msg
                            },

                            success : function(data) {
                                // Remove any warnings
                                $('#nodesTab').find('.ui-state-error').remove();
                                                                
                                // Update datatable
                                $.ajax( {
                                    url : 'lib/cmd.php',
                                    dataType : 'json',
                                    data : {
                                        cmd : 'webrun',
                                        tgt : '',
                                        args : 'gangliastatus;' + data.msg,
                                        msg : ''
                                    },

                                    success : loadGangliaStatus
                                });
                            }
                        });
                    } // End of if (warn)
                } // End of function(data)
            });
        } else {
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'webrun',
                    tgt : '',
                    args : 'gangliastart',
                    msg : ''
                },

                success : function(data) {
                    // Remove any warnings
                    $('#nodesTab').find('.ui-state-error').remove();
                }
            });
        } // End of if (node)
    } else {
        var args;
        if (node) {
            args = 'gangliastop;' + node + ';-r';
        } else {
            args = 'gangliastop';
        }

        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'webrun',
                tgt : '',
                args : args,
                msg : ''
            },

            success : function(data) {
                // Hide ganglia loader
                var gangliaCol = $('#' + nodesTableId + '_wrapper .dataTables_scrollHead .datatable thead tr th:eq(4)');
                gangliaCol.find('img').hide();
            }
        });
    }
}

/**
 * Install Ganglia on a given node
 * 
 * @param node Node to install Ganglia on
 */
function installGanglia(node) {
    var iframe = createIFrame('lib/cmd.php?cmd=webrun&tgt=&args=installganglia;' + node + '&msg=' + node + '&opts=flush');
    iframe.prependTo($('#nodesTab'));
    
    // Turn on Ganglia for node
    monitorNode(node, 'on');
}

/**
 * After nodes are loaded, load more information based on different hardware architectures 
 * 
 * @param group Group name
 */
function advancedLoad(group){
    var tempIndex = 0;
    var tableHeaders = $('#' + nodesTableId).parents('.dataTables_scroll').find('.dataTables_scrollHead thead tr:eq(0) th');
    var colNameHash = new Object();
    var colName = '';
    var archCol = 0, hcpCol = 0;
    
    // Find out the column name and their index
    for (tempIndex = 0; tempIndex < tableHeaders.size(); tempIndex++){
        var header = tableHeaders.eq(tempIndex);
        // Skip headers that are links, e.g. status, power, and monitor
        if (header.find('a').size() > 0){
            continue;
        }
        
        colName = header.text();
        
        if (colName) {
            colNameHash[colName] = tempIndex;
        }
    }
    
    // If there is no arch column, exit because you cannot distinguish hardware type
    if (!colNameHash['arch']) {
        return;
    }
    
    if (!colNameHash['hcp']) {
        return;
    }
    archCol = colNameHash['arch'];
    hcpCol = colNameHash['hcp'];
    
    // Get hardware control point
    var rows = $('#' + nodesTableId + ' tbody tr');
    var hcps = new Object();
    var rowsNum = rows.size();
    for (var j = 0; j < rowsNum; j++) {
        var val = rows.eq(j).find('td').eq(hcpCol).html();
        var archval = rows.eq(j).find('td').eq(archCol).html();
        if (-1 == archval.indexOf('390')){
            continue;
        }
        hcps[val] = 1;
    }

    var args;
    var shortzHcps = new Array();
    for (var h in hcps) {
        // Get node without domain name
        args = h.split('.');
        shortzHcps.push(args[0]);
        
        // If there are no disk pools or network names cookie for this hcp
        if (!$.cookie(args[0] + 'diskpools') || !$.cookie(args[0] + 'networks')) {
            // Check if SMAPI is online
            $.ajax({
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'lsvm',
                    tgt : args[0],
                    args : '',
                    msg : 'group=' + group + ';hcp=' + args[0]
                },

                // Load hardware control point specific info
                // Get disk pools and network names
                success : loadHcpInfo
            });
        }
    } // End of for
    
    // Save zHCPs as a cookie
    setzHcpCookies(shortzHcps);
    
    // Retrieve z/VM hypervisors and their zHCPs
    if (!$.cookie('zvms')) {
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
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
    }
}

/**
 * Jump to provision page on-click
 * 
 * @param tgtNodes Target nodes
 */
function jump2Provision(tgtNodes){
    var nodeArray = tgtNodes.split(',');
    var nodeName = '';
    var index = 0;
    var archType = '';
    var errorMsg = '';
    var master = '';
    var tftpserver = '';
    var nfsserver = '';
    var diaDiv = $('<div title="Provision" class="form" id="deployDiv"></div>');
    
    // Check the first node's arch type
    for (index in nodeArray){
        nodeName = nodeArray[index];
        
        // Skip if node does not have arch
        if (!origAttrs[nodeName]['arch']){
            errorMsg = 'Nodes should have arch defined! ';
            break;
        }
        
        if (index == 0) {
            archType = origAttrs[nodeName]['arch'];
        }
        
        // Skip if nodes do not have same arch
        if (archType != origAttrs[nodeName]['arch']){
            errorMsg = 'Nodes should belong to the same arch!<br/>';
            break;
        }
    }

    // Skip if nodes do not have MAC address
    for (index in nodeArray){
        if (!origAttrs[nodeName]['mac'] || !origAttrs[nodeName]['ip']){
            errorMsg += 'Nodes should have the IP and MAC addresses defined!<br/>';
            break;
        }
    }
    
    if (archType.indexOf('390') != -1) {
        errorMsg += 'Please use the provision page';
    }
    
    // Open dialog to show error message
    if (errorMsg){
        diaDiv.append(createWarnBar(errorMsg));
        diaDiv.dialog({
            modal: true,
            close: function(){
                $(this).remove();
            },
            width: 400,
            buttons: {
                'Close': function(){
                    $(this).dialog('destroy');
                }
            }
        });
        
        return;
    }
    
    if (origAttrs[nodeName]['xcatmaster']) {
        master = origAttrs[nodeName]['xcatmaster'];
    }
    
    if (origAttrs[nodeName]['tftpserver']) {
        tftpserver = origAttrs[nodeName]['tftpserver'];
    }
    
    if (origAttrs[nodeName]['nfsserver']) {
        nfsserver = origAttrs[nodeName]['nfsserver'];
    }
    
    window.location.href = 'provision.php?nodes=' + tgtNodes + '&arch=' + archType + '&master=' + master +
                           '&tftpserver=' + tftpserver + '&nfsserver=' + nfsserver;
}