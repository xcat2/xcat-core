/**
 * Execute when the DOM is fully loaded
 */
$(document).ready(function() {
    // Load utility scripts
    includeJs("js/custom/zvmUtils.js");
});

/**
 * Constructor
 */
var zvmPlugin = function() {
    
};

/**
 * Configure self-service configure page
 */
zvmPlugin.prototype.loadConfigPage = function(tabId) {    
    var configAccordion = $('<div id="zvmConfigAccordion"></div>');
    
    // Create accordion panel for profiles
    var profileSection = $('<div id="zvmConfigProfile"></div>');
    var profileLnk = $('<h3><a href="#">Profiles</a></h3>').click(function () {
        // Do not load panel again if it is already loaded
        if ($('#zvmConfigProfile').find('.dataTables_wrapper').length)
            return;
        else
            $('#zvmConfigProfile').append(createLoader(''));

        queryProfiles('zvmConfigProfile');
    });
    
    // Create accordion panel for images
    var imgSection = $('<div id="zvmConfigImages"></div>');
    var imgLnk = $('<h3><a href="#">Templates</a></h3>').click(function () {
        // Do not load panel again if it is already loaded
        if ($('#zvmConfigImages').find('.dataTables_wrapper').length)
            return;
        else
            $('#zvmConfigImages').append(createLoader(''));

        queryImages('zvmConfigImages');
    });
    
    // Create accordion panel for groups
    var groupsSection = $('<div id="zvmConfigGroups"></div>');
    var groupsLnk = $('<h3><a href="#">Groups</a></h3>').click(function () {
        // Do not load panel again if it is already loaded
        if ($('#zvmConfigGroups').find('.dataTables_wrapper').length)
            return;
        else
            $('#zvmConfigGroups').append(createLoader(''));

        queryGroups('zvmConfigGroups');
    });
        
    configAccordion.append(profileLnk, profileSection, imgLnk, imgSection, groupsLnk, groupsSection);
    $('#' + tabId).append(configAccordion);
    configAccordion.accordion();
    
    profileLnk.trigger('click');
};

/**
 * Clone node (service page)
 * 
 * @param node Node to clone
 */
zvmPlugin.prototype.serviceClone = function(node) {
    var owner = $.cookie('xcat_username');
    var group = getUserNodeAttr(node, 'groups');
    
    // Submit request to clone VM
    // webportal clonezlinux [src node] [group] [owner]
    var iframe = createIFrame('lib/srv_cmd.php?cmd=webportal&tgt=&args=clonezlinux;' + node + ';' + group + ';' + owner + '&msg=&opts=flush');
    iframe.prependTo($('#manageTab'));
};

/**
 * Load provision page (service page)
 * 
 * @param tabId Tab ID where page will reside
 */
zvmPlugin.prototype.loadServiceProvisionPage = function(tabId) {
    // Create provision form
    var provForm = $('<div></div>');

    // Create info bar
    var infoBar = createInfoBar('Provision a Linux virtual machine on System z by selecting the appropriate choices below.  Once you are ready, click on Provision to provision the virtual machine.');
    provForm.append(infoBar);

    // Append to provision tab
    $('#' + tabId).append(provForm);
    
    // Create provision table
    var provTable = $('<table id="select-table" style="margin: 10px;"></table');
    var provHeader = $('<thead class="ui-widget-header"> <th>zVM</th> <th>Group</th> <th>Template</th> <th>Image</th></thead>');
    var provBody = $('<tbody></tbody>');
    var provFooter = $('<tfoot></tfoot>');
    provTable.append(provHeader, provBody, provFooter);
    provForm.append(provTable);
    
    provHeader.children('th').css({
        'font': 'bold 12px verdana, arial, helvetica, sans-serif'
    });
    
    // Create row to contain selections
    var provRow = $('<tr></tr>');
    provBody.append(provRow);
    // Create columns for zVM, group, template, and image
    var zvmCol = $('<td style="vertical-align: top;"></td>');
    provRow.append(zvmCol);
    var groupCol = $('<td style="vertical-align: top;"></td>');
    provRow.append(groupCol);
    var tmplCol = $('<td style="vertical-align: top;"></td>');
    provRow.append(tmplCol);
    var imgCol = $('<td style="vertical-align: top;"></td>');
    provRow.append(imgCol);
        
    provRow.children('td').css({
        'min-width': '200px'
    });
    
    /**
     * Provision VM
     */
    var provisionBtn = createButton('Provision');
    provisionBtn.bind('click', function(event) {
        // Remove any warning messages
        $(this).parent().find('.ui-state-error').remove();
        
        var hcp = $('#select-table tbody tr:eq(0) td:eq(0) input[name="hcp"]:checked').val();
        var group = $('#select-table tbody tr:eq(0) td:eq(1) input[name="group"]:checked').val();
        var tmpl = $('#select-table tbody tr:eq(0) td:eq(2) input[name="image"]:checked').val();
        var img = $('#select-table tbody tr:eq(0) td:eq(3) input[name="master"]:checked').val();
        var owner = $.cookie('xcat_username');
        
        if (img && !group) {
        	// Show warning message
            var warn = createWarnBar('You need to select a group');
            warn.prependTo($(this).parent());
        } else if (!img && (!hcp || !group || !tmpl)) {
            // Show warning message
            var warn = createWarnBar('You need to select a zHCP, group, and image');
            warn.prependTo($(this).parent());
        } else {
        	if (img) {
        		// Begin by clonning VM
        		
        	    // Submit request to clone VM
        	    // webportal clonezlinux [src node] [group] [owner]
        	    var iframe = createIFrame('lib/srv_cmd.php?cmd=webportal&tgt=&args=clonezlinux;' + img + ';' + group + ';' + owner + '&msg=&opts=flush');
        	    iframe.prependTo($('#zvmProvisionTab'));
        	} else {
        		// Begin by creating VM
        		createzVM(tabId, group, hcp, tmpl, owner);
        	}
        }
    });
    provForm.append(provisionBtn);
    
    // Load zVMs, groups, template, and image into their respective columns
    loadSrvGroups(groupCol);
    loadOSImages(tmplCol);
    loadGoldenImages(imgCol);
    
    // Get zVM host names
    if (!$.cookie('zvms')){
        $.ajax( {
            url : 'lib/srv_cmd.php',
            dataType : 'json',
            data : {
                cmd : 'webportal',
                tgt : '',
                args : 'lszvm',
                msg : ''
            },

            success : function(data) {
                setzVMCookies(data);
                loadzVMs(zvmCol);
            }
        });
    } else {
        loadzVMs(zvmCol);
    }
};

/**
 * Show node inventory (service page)
 * 
 * @param data Data from HTTP request
 */
zvmPlugin.prototype.loadServiceInventory = function(data) {
    var args = data.msg.split(',');

    // Get tab ID
    var tabId = args[0].replace('out=', '');
    // Get node
    var node = args[1].replace('node=', '');
    
    // Remove loader
    $('#' + tabId).find('img').remove();
    
    // Do not continue if error is found
    if (data.rsp[0].indexOf('Error') > -1) {
        var warn = createWarnBar(data.rsp[0]);
        $('#' + tabId).append(warn);
        return;
    }
    
    // Get node inventory
    var inv = data.rsp[0].split(node + ':');

    // Create array of property keys (VM)
    var keys = new Array('userId', 'host', 'os', 'arch', 'uptime', 'cpuusedtime', 'hcp', 'priv', 'memory', 'maxmemory', 'proc', 'disk', 'zfcp', 'nic');

    // Create hash table for property names (VM)
    var attrNames = new Object();
    attrNames['userId'] = 'z/VM UserID:';
    attrNames['host'] = 'z/VM Host:';
    attrNames['os'] = 'Operating System:';
    attrNames['arch'] = 'Architecture:';
    attrNames['uptime'] = 'Uptime:';
    attrNames['cpuusedtime'] = 'CPU Used Time:';
    attrNames['hcp'] = 'HCP:';
    attrNames['priv'] = 'Privileges:';
    attrNames['memory'] = 'Total Memory:';
    attrNames['maxmemory'] = 'Max Memory:';
    attrNames['proc'] = 'Processors:';
    attrNames['disk'] = 'Disks:';
    attrNames['zfcp'] = 'zFCP:';
    attrNames['nic'] = 'NICs:';
    
    // Create hash table for node attributes
    var attrs = getAttrs(keys, attrNames, inv);

    // Create division to hold inventory
    var invDivId = node + 'Inventory';
    var invDiv = $('<div class="inventory" id="' + invDivId + '"></div>');
    
    var infoBar = createInfoBar('Below is the inventory for the virtual machine you selected.');
    invDiv.append(infoBar);

    /**
     * General info section
     */
    var fieldSet = $('<fieldset></fieldset>');
    var legend = $('<legend>General</legend>');
    fieldSet.append(legend);
    var oList = $('<ol></ol>');
    var item, label, args;

    // Loop through each property
    for ( var k = 0; k < 5; k++) {
        // Create a list item for each property
        item = $('<li></li>');

        // Create a label - Property name
        label = $('<label>' + attrNames[keys[k]] + '</label>');
        item.append(label);

        for ( var l = 0; l < attrs[keys[k]].length; l++) {
            // Create a input - Property value(s)
            // Handle each property uniquely
            item.append(attrs[keys[k]][l]);
        }

        oList.append(item);
    }
    // Append to inventory form
    fieldSet.append(oList);
    invDiv.append(fieldSet);
    
    /**
     * Monitoring section
     */
    fieldSet = $('<fieldset id="' + node + '_monitor"></fieldset>');
    legend = $('<legend>Monitoring [<a style="font-weight: normal; color: blue; text-decoration: none;">Refresh</a>]</legend>');    
    fieldSet.append(legend);    
//    var info = createInfoBar('No data available');
//    fieldSet.append(info.css('width', '300px'));
    
    getMonitorMetrics(node);
    
    // Refresh monitoring charts on-click
    legend.find('a').click(function() {
        getMonitorMetrics(node);
    });
    
    // Append to inventory form
    invDiv.append(fieldSet);

    /**
     * Hardware info section
     */
    var hwList, hwItem;
    fieldSet = $('<fieldset></fieldset>');
    legend = $('<legend>Hardware</legent>');
    fieldSet.append(legend);
    oList = $('<ol></ol>');

    // Loop through each property
    var label;
    for (k = 5; k < keys.length; k++) {
        // Create a list item
        item = $('<li></li>');

        // Create a list to hold the property value(s)
        hwList = $('<ul></ul>');
        hwItem = $('<li></li>');

        /**
         * Privilege section
         */
        if (keys[k] == 'priv') {
            // Create a label - Property name
            label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
            item.append(label);

            // Loop through each line
            for (l = 0; l < attrs[keys[k]].length; l++) {
                // Create a new list item for each line
                hwItem = $('<li></li>');

                // Determine privilege
                args = attrs[keys[k]][l].split(' ');
                if (args[0] == 'Directory:') {
                    label = $('<label>' + args[0] + '</label>');
                    hwItem.append(label);
                    hwItem.append(args[1]);
                } else if (args[0] == 'Currently:') {
                    label = $('<label>' + args[0] + '</label>');
                    hwItem.append(label);
                    hwItem.append(args[1]);
                }

                hwList.append(hwItem);
            }

            item.append(hwList);
        }

        /**
         * Memory section
         */
        else if (keys[k] == 'memory') {
            // Create a label - Property name
            label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
            item.append(label);

            // Loop through each value line
            for (l = 0; l < attrs[keys[k]].length; l++) {
                // Create a new list item for each line
                hwItem = $('<li></li>');
                hwItem.append(attrs[keys[k]][l]);
                hwList.append(hwItem);
            }

            item.append(hwList);
        }

        /**
         * Processor section
         */
        else if (keys[k] == 'proc') {
            // Create a label - Property name
            label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
            item.append(label);

            // Create a table to hold processor data
            var procTable = $('<table></table>');
            var procBody = $('<tbody></tbody>');

            // Table columns - Type, Address, ID, Base, Dedicated, and Affinity
            var procTabRow = $('<thead class="ui-widget-header"> <th>Type</th> <th>Address</th> <th>ID</th> <th>Base</th> <th>Dedicated</th> <th>Affinity</th> </thead>');
            procTable.append(procTabRow);
            var procType, procAddr, procId, procAff;

            // Loop through each processor
            var n, temp;
            for (l = 0; l < attrs[keys[k]].length; l++) {
                if (attrs[keys[k]][l]) {            
                    args = attrs[keys[k]][l].split(' ');
                    
                    // Get processor type, address, ID, and affinity
                    n = 3;
                    temp = args[args.length - n];
                    while (!jQuery.trim(temp)) {
                        n = n + 1;
                        temp = args[args.length - n];
                    }
                    procType = $('<td>' + temp + '</td>');
                    procAddr = $('<td>' + args[1] + '</td>');
                    procId = $('<td>' + args[5] + '</td>');
                    procAff = $('<td>' + args[args.length - 1] + '</td>');
    
                    // Base processor
                    if (args[6] == '(BASE)') {
                        baseProc = $('<td>' + true + '</td>');
                    } else {
                        baseProc = $('<td>' + false + '</td>');
                    }
    
                    // Dedicated processor
                    if (args[args.length - 3] == 'DEDICATED') {
                        dedicatedProc = $('<td>' + true + '</td>');
                    } else {
                        dedicatedProc = $('<td>' + false + '</td>');
                    }
    
                    // Create a new row for each processor
                    procTabRow = $('<tr></tr>');
                    procTabRow.append(procType);
                    procTabRow.append(procAddr);
                    procTabRow.append(procId);
                    procTabRow.append(baseProc);
                    procTabRow.append(dedicatedProc);
                    procTabRow.append(procAff);
                    procBody.append(procTabRow);
                }
            }
            
            procTable.append(procBody);
            item.append(procTable);
        }

        /**
         * Disk section
         */
        else if (keys[k] == 'disk') {
            // Create a label - Property name
            label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
            item.append(label);

            // Create a table to hold disk (DASD) data
            var dasdTable = $('<table></table>');
            var dasdBody = $('<tbody></tbody>');

            // Table columns - Virtual Device, Type, VolID, Type of Access, and Size
            var dasdTabRow = $('<thead class="ui-widget-header"> <th>Virtual Device #</th> <th>Type</th> <th>VolID</th> <th>Type of Access</th> <th>Size</th> </thead>');
            dasdTable.append(dasdTabRow);
            var dasdVDev, dasdType, dasdVolId, dasdAccess, dasdSize;

            // Loop through each DASD
            for (l = 0; l < attrs[keys[k]].length; l++) {
                if (attrs[keys[k]][l]) {
                    args = attrs[keys[k]][l].split(' ');

                    // Get DASD virtual device, type, volume ID, access, and size
                    dasdVDev = $('<td>' + args[1] + '</td>');    
                    dasdType = $('<td>' + args[2] + '</td>');
                    dasdVolId = $('<td>' + args[3] + '</td>');
                    dasdAccess = $('<td>' + args[4] + '</td>');
                    dasdSize = $('<td>' + args[args.length - 9] + ' ' + args[args.length - 8] + '</td>');
    
                    // Create a new row for each DASD
                    dasdTabRow = $('<tr></tr>');
                    dasdTabRow.append(dasdVDev);
                    dasdTabRow.append(dasdType);
                    dasdTabRow.append(dasdVolId);
                    dasdTabRow.append(dasdAccess);
                    dasdTabRow.append(dasdSize);
                    dasdBody.append(dasdTabRow);
                }
            }

            dasdTable.append(dasdBody);
            item.append(dasdTable);
        }
        
        /**
         * zFCP section
         */
        else if (keys[k] == 'zfcp') {
            // Create a label - Property name
            label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
            item.append(label);

            // Create a table to hold NIC data
            var zfcpTable = $('<table></table>');
            var zfcpBody = $('<tbody></tbody>');
            
            // Table columns - Virtual device, Adapter Type, Port Name, # of Devices, MAC Address, and LAN Name
            var zfcpTabRow = $('<thead class="ui-widget-header"> <th>Virtual Device #</th> <th>Port Name</th> <th>Unit Number</th> <th>Size</th></thead>');
            zfcpTable.append(zfcpTabRow);
            var zfcpVDev, zfcpPortName, zfcpLun, zfcpSize;

            // Loop through each zFCP device
            if (attrs[keys[k]]) {
                for (l = 0; l < attrs[keys[k]].length; l++) {
                    if (attrs[keys[k]][l]) {
                        args = attrs[keys[k]][l].split(' ');
        
                        // Get zFCP virtual device, port name (WWPN), unit number (LUN), and size
                        zfcpVDev = $('<td>' + args[1].replace('0.0.', '') + '</td>');
                        zfcpPortName = $('<td>' + args[4] + '</td>');
                        zfcpLun = $('<td>' + args[7] + '</td>');
                        zfcpSize = $('<td>' + args[args.length - 2] + ' ' + args[args.length - 1] + '</td>');
        
                        // Create a new row for each zFCP device
                        zfcpTabRow = $('<tr></tr>');
                        zfcpTabRow.append(zfcpVDev);
                        zfcpTabRow.append(zfcpPortName);
                        zfcpTabRow.append(zfcpLun);
                        zfcpTabRow.append(zfcpSize);
        
                        zfcpBody.append(zfcpTabRow);
                    }
                }
            }

            zfcpTable.append(zfcpBody);
            item.append(zfcpTable);
        }

        /**
         * NIC section
         */
        else if (keys[k] == 'nic') {
            // Create a label - Property name
            label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
            item.append(label);

            // Create a table to hold NIC data
            var nicTable = $('<table></table>');
            var nicBody = $('<tbody></tbody>');

            // Table columns - Virtual device, Adapter Type, Port Name, # of Devices, MAC Address, and LAN Name
            var nicTabRow = $('<thead class="ui-widget-header"><th>Virtual Device #</th> <th>Adapter Type</th> <th>Port Name</th> <th># of Devices</th> <th>LAN Name</th></thead>');
            nicTable.append(nicTabRow);
            var nicVDev, nicType, nicPortName, nicNumOfDevs, nicLanName;

            // Loop through each NIC (Data contained in 2 lines)
            for (l = 0; l < attrs[keys[k]].length; l++) {
            	if (attrs[keys[k]][l].indexOf('Adapter') != -1) {
                    args = attrs[keys[k]][l].split(' ');
    
                    // Get NIC virtual device, type, port name, and number of devices
                    nicVDev = $('<td>' + args[1] + '</td>');
                    nicType = $('<td>' + args[3] + '</td>');
                    nicPortName = $('<td>' + args[10] + '</td>');
                    nicNumOfDevs = $('<td>' + args[args.length - 1] + '</td>');
    
                    args = attrs[keys[k]][l + 1].split(' ');
                    nicLanName = $('<td>' + args[args.length - 2] + ' ' + args[args.length - 1] + '</td>');
    
                    // Create a new row for each DASD
                    nicTabRow = $('<tr></tr>');
                    nicTabRow.append(nicVDev);
                    nicTabRow.append(nicType);
                    nicTabRow.append(nicPortName);
                    nicTabRow.append(nicNumOfDevs);
                    nicTabRow.append(nicLanName);
    
                    nicBody.append(nicTabRow);
                }
            }

            nicTable.append(nicBody);
            item.append(nicTable);
        }
        
        // Ignore any fields not in key
        else {
            continue;
        }

        oList.append(item);
    }

    // Append inventory to division
    fieldSet.append(oList);
    invDiv.append(fieldSet);
    invDiv.find('th').css({
        'padding': '5px 10px',
        'font-weight': 'bold'
    });

    // Append to tab
    $('#' + tabId).append(invDiv);
};

/**
 * Load clone page
 * 
 * @param node Source node to clone
 */
zvmPlugin.prototype.loadClonePage = function(node) {
    // Get nodes tab
    var tab = getNodesTab();
    var newTabId = node + 'CloneTab';

    // If there is no existing clone tab
    if (!$('#' + newTabId).length) {
        // Get table headers
        var tableId = $('#' + node).parents('table').attr('id');
        var headers = $('#' + tableId).parents('.dataTables_scroll').find('.dataTables_scrollHead thead tr:eq(0) th');
        var cols = new Array();
        for ( var i = 0; i < headers.length; i++) {
            var col = headers.eq(i).text();
            cols.push(col);
        }

        // Get hardware control point column
        var hcpCol = $.inArray('hcp', cols);

        // Get hardware control point
        var nodeRow = $('#' + node).parent().parent();
        var datatable = $('#' + getNodesTableId()).dataTable();
        var rowPos = datatable.fnGetPosition(nodeRow.get(0));
        var aData = datatable.fnGetData(rowPos);
        var hcp = aData[hcpCol];

        // Create status bar and hide it
        var statBarId = node + 'CloneStatusBar';
        var statBar = createStatusBar(statBarId).hide();

        // Create info bar
        var infoBar = createInfoBar('Clone a zVM node.');

        // Create clone form
        var cloneForm = $('<div class="form"></div>');
        cloneForm.append(statBar);
        cloneForm.append(infoBar);
        
        // Create VM fieldset
        var vmFS = $('<fieldset></fieldset>');
        var vmLegend = $('<legend>Virtual Machine</legend>');
        vmFS.append(vmLegend);
        cloneForm.append(vmFS);
        
        var vmAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
        vmFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/computer.png"></img></div>'));
        vmFS.append(vmAttr);
        
        // Create hardware fieldset
        var storageFS = $('<fieldset></fieldset>');
        var storageLegend = $('<legend>Storage</legend>');
        storageFS.append(storageLegend);
        cloneForm.append(storageFS);
        
        var storageAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
        storageFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/hdd.png"></img></div>'));
        storageFS.append(storageAttr);
        
        vmAttr.append('<div><label>Target node range:</label><input type="text" id="tgtNode" name="tgtNode" title="You must give a node or a node range. A node range must be given as: node1-node9 or node[1-9]."/></div>');
        vmAttr.append('<div><label>Target user ID range:</label><input type="text" id="tgtUserId" name="tgtUserId" title="You must give a user ID or a user ID range. A user ID range must be given as: user1-user9 or user[1-9]."/></div>');
        vmAttr.append('<div><label>Clone source:</label><input type="text" id="srcNode" name="srcNode" readonly="readonly" value="' + node + '" title="The source node to be cloned"/></div>');
        vmAttr.append('<div><label>Hardware control point:</label><input type="text" id="newHcp" name="newHcp" readonly="readonly" value="' + hcp + '" title="The System z hardware control point (zHCP) responsible for managing the node(s). It must be the same as the source node."/></div>');

        // Create group input
        var group = $('<div></div>');
        var groupLabel = $('<label>Group:</label>');
        var groupInput = $('<input type="text" id="newGroup" name="newGroup" title="You must give the group where the new node(s) will be placed under."/>');
        groupInput.one('focus', function(){
            var groupNames = $.cookie('groups');
            if (groupNames) {
                // Turn on auto complete
                $(this).autocomplete({
                    source: groupNames.split(',')
                });
            }
        });
        group.append(groupLabel);
        group.append(groupInput);
        vmAttr.append(group);
        
        // Create an advanced link to set IP address and hostname
        var advancedLnk = $('<div><label><a style="color: blue; cursor: pointer;">Advanced</a></label></div>');
        vmAttr.append(advancedLnk);    
        var advanced = $('<div style="margin-left: 20px;"></div>').hide();
        vmAttr.append(advanced);
        
        var ip = $('<div><label>IP address range:</label><input type="text" name="ip" ' + 
            'title="Optional. Specify the IP address range that will be assigned to these nodes. An IP address range must be given in the following format: 192.168.0.1-192.168.9."/></div>');
        advanced.append(ip);
        var hostname = $('<div><label>Hostname range:</label><input type="text" name="hostname" ' + 
            'title="Optional. Specify the hostname range that will be assigned to these node. A hostname range must be given in the following format: ihost1.sourceforge.net-ihost9.sourceforge.net."/></div>');
        advanced.append(hostname);
        
        // Show IP address and hostname inputs on-click
        advancedLnk.click(function() {
            advanced.toggle();
        });

        // Get list of disk pools
        var temp = hcp.split('.');
        var diskPools = $.cookie(temp[0] + 'diskpools');

        // Create disk pool input
        var poolDiv = $('<div></div>');
        var poolLabel = $('<label>Disk pool:</label>');
        var poolInput = $('<input type="text" id="diskPool" name="diskPool" title="You must give a disk pool. xCAT relies on DirMaint to allocate minidisks out of a pool of DASD volumes. These DASD volume pools are defined in the EXTENT CONTROL file."/>').autocomplete({
            source: diskPools.split(',')
        });
        poolDiv.append(poolLabel);
        poolDiv.append(poolInput);
        storageAttr.append(poolDiv);

        storageAttr.append('<div><label>Disk password:</label><input type="password" id="diskPw" name="diskPw" title="The password that will be used for accessing the disk. This input is optional."/></div>');

        // Generate tooltips
        cloneForm.find('div input[title]').tooltip({
            position : "center right",
            offset : [ -2, 10 ],
            effect : "fade",
            opacity : 0.7,
            predelay: 800,
            events : {
                def : "mouseover,mouseout",
                input : "mouseover,mouseout",
                widget : "focus mouseover,blur mouseout",
                tooltip : "mouseover,mouseout"
            }
        });
        
        /**
         * Clone node
         */
        var cloneBtn = createButton('Clone');
        cloneBtn.bind('click', function(event) {
        	// Remove any warning messages
        	$(this).parents('.ui-tabs-panel').find('.ui-state-error').remove();
            
            var ready = true;
            var errMsg = '';

            // Check node name, userId, hardware control point, group, and password
            var inputs = $('#' + newTabId + ' input');
            for ( var i = 0; i < inputs.length; i++) {
                if (!inputs.eq(i).val()
                    && inputs.eq(i).attr('name') != 'diskPw'
                    && inputs.eq(i).attr('name') != 'diskPool'
                    && inputs.eq(i).attr('name') != 'ip'
                    && inputs.eq(i).attr('name') != 'hostname') {
                    inputs.eq(i).css('border', 'solid #FF0000 1px');
                    ready = false;
                } else {
                    inputs.eq(i).css('border', 'solid #BDBDBD 1px');
                }
            }

            // Write error message
            if (!ready) {
                errMsg = errMsg + 'Please provide a value for each missing field.<br>';
            }

            // Get target node
            var nodeRange = $('#' + newTabId + ' input[name=tgtNode]').val();
            // Get target user ID
            var userIdRange = $('#' + newTabId + ' input[name=tgtUserId]').val();
            // Get IP address range
            var ipRange = $('#' + newTabId + ' input[name=ip]').val();
            // Get hostname range
            var hostnameRange = $('#' + newTabId + ' input[name=hostname]').val();

            // Check node range and user ID range
            if (nodeRange.indexOf('-') > -1 || userIdRange.indexOf('-') > -1 || ipRange.indexOf('-') > -1 || hostnameRange.indexOf('-') > -1) {
                if (nodeRange.indexOf('-') < 0 || userIdRange.indexOf('-') < 0) {
                    errMsg = errMsg + 'A user ID range and node range needs to be given.<br>';
                    ready = false;
                } else {
                    var tmp = nodeRange.split('-');

                    // Get node base name
                    var nodeBase = tmp[0].match(/[a-zA-Z]+/);
                    // Get starting index
                    var nodeStart = parseInt(tmp[0].match(/\d+/));
                    // Get ending index
                    var nodeEnd = parseInt(tmp[1].match(/\d+/));

                    tmp = userIdRange.split('-');

                    // Get user ID base name
                    var userIdBase = tmp[0].match(/[a-zA-Z]+/);
                    // Get starting index
                    var userIdStart = parseInt(tmp[0].match(/\d+/));
                    // Get ending index
                    var userIdEnd = parseInt(tmp[1].match(/\d+/));
                    
                    var ipStart = "", ipEnd = "";
                    if (ipRange) {
                        tmp = ipRange.split('-');
                        
                        // Get starting IP address
                        ipStart = tmp[0].substring(tmp[0].lastIndexOf(".") + 1);
                        // Get ending IP address
                        ipEnd = tmp[1].substring(tmp[1].lastIndexOf(".") + 1);
                    }
                    
                    var hostnameStart = "", hostnameEnd = "";
                    if (hostnameRange) {
                        tmp = hostnameRange.split('-');
    
                        // Get starting hostname
                        hostnameStart = parseInt(tmp[0].substring(0, tmp[0].indexOf(".")).match(/\d+/));
                        // Get ending hostname
                        hostnameEnd = parseInt(tmp[1].substring(0, tmp[1].indexOf(".")).match(/\d+/));
                    }
                    
                    // If starting and ending index do not match
                    if (!(nodeStart == userIdStart) || !(nodeEnd == userIdEnd)) {
                        // Not ready to provision
                        errMsg = errMsg + 'The node range and user ID range does not match.<br>';
                        ready = false;
                    }
                    
                    // If an IP address range is given and the starting and ending index do not match
                    if (ipRange && (!(nodeStart == ipStart) || !(nodeEnd == ipEnd))) {
                        errMsg = errMsg + 'The node range and IP address range does not match. ';
                        ready = false;
                    }
                    
                    // If a hostname range is given and the starting and ending index do not match
                    if (hostnameRange && (!(nodeStart == hostnameStart) || !(nodeEnd == hostnameEnd))) {
                        errMsg = errMsg + 'The node range and hostname range does not match. ';
                        ready = false;
                    }
                }
            }

            // Get source node, hardware control point, group, disk pool, and disk password
            var srcNode = $('#' + newTabId + ' input[name=srcNode]').val();
            var hcp = $('#' + newTabId + ' input[name=newHcp]').val();
            var group = $('#' + newTabId + ' input[name=newGroup]').val();
            var diskPool = $('#' + newTabId + ' input[name=diskPool]').val();
            var diskPw = $('#' + newTabId + ' input[name=diskPw]').val();

            // If a value is given for every input
            if (ready) {
                // Disable all inputs
                var inputs = $('#' + newTabId + ' input');
                inputs.attr('disabled', 'disabled');
                                    
                // If a node range is given
                if (nodeRange.indexOf('-') > -1) {
                    var tmp = nodeRange.split('-');

                    // Get node base name
                    var nodeBase = tmp[0].match(/[a-zA-Z]+/);
                    // Get starting index
                    var nodeStart = parseInt(tmp[0].match(/\d+/));
                    // Get ending index
                    var nodeEnd = parseInt(tmp[1].match(/\d+/));

                    tmp = userIdRange.split('-');

                    // Get user ID base name
                    var userIdBase = tmp[0].match(/[a-zA-Z]+/);
                                                            
                    var ipBase = "";
                    if (ipRange) {
                        tmp = ipRange.split('-');
                        
                        // Get network base
                        ipBase = tmp[0].substring(0, tmp[0].lastIndexOf(".") + 1);
                    }
                    
                    var domain = "";
                    if (hostnameRange) {
                        tmp = hostnameRange.split('-');
                    
                        // Get domain name
                        domain = tmp[0].substring(tmp[0].indexOf("."));
                    }
                    
                    // Loop through each node in the node range
                    for ( var i = nodeStart; i <= nodeEnd; i++) {
                        var node = nodeBase + i.toString();
                        var userId = userIdBase + i.toString();
                        var inst = i + '/' + nodeEnd;
                                                
                        var args = node 
                            + ';zvm.hcp=' + hcp
                            + ';zvm.userid=' + userId
                            + ';nodehm.mgt=zvm' 
                            + ';groups=' + group;
                        
                        if (ipRange) {
                            var ip = ipBase + i.toString();
                            args += ';hosts.ip=' + ip;
                        }
                        
                        if (hostnameRange) {
                            var hostname = node + domain;
                            args += ';hosts.hostnames=' + hostname;
                        }
                        
                        /**
                         * (1) Define node
                         */
                        $.ajax( {
                            url : 'lib/cmd.php',
                            dataType : 'json',
                            data : {
                                cmd : 'nodeadd',
                                tgt : '',
                                args : args,
                                msg : 'cmd=nodeadd;inst=' + inst 
                                    + ';out=' + statBarId 
                                    + ';node=' + node
                            },

                            success : updateZCloneStatus
                        });
                    }
                } else {
                    var args = nodeRange 
                        + ';zvm.hcp=' + hcp
                        + ';zvm.userid=' + userIdRange
                        + ';nodehm.mgt=zvm' 
                        + ';groups=' + group;
                    
                    if (ipRange)
                        args += ';hosts.ip=' + ipRange;
                    
                    if (hostnameRange)
                        args += ';hosts.hostnames=' + hostnameRange;
                    
                    /**
                     * (1) Define node
                     */
                    $.ajax( {
                        url : 'lib/cmd.php',
                        dataType : 'json',
                        data : {
                            cmd : 'nodeadd',
                            tgt : '',
                            args : args,
                            msg : 'cmd=nodeadd;inst=1/1;out=' + statBarId
                                + ';node=' + nodeRange
                        },

                        success : updateZCloneStatus
                    });
                }

                // Create loader
                $('#' + statBarId).find('div').append(createLoader());
                $('#' + statBarId).show();

                // Disable clone button
                $(this).attr('disabled', 'true');
            } else {
                // Show warning message
                var warn = createWarnBar(errMsg);
                warn.prependTo($(this).parent().parent());
            }
        });
        cloneForm.append(cloneBtn);

        // Add clone tab
        tab.add(newTabId, 'Clone', cloneForm, true);
    }

    tab.select(newTabId);
};

/**
 * Load node inventory
 * 
 * @param data Data from HTTP request
 */
zvmPlugin.prototype.loadInventory = function(data) {
    var args = data.msg.split(',');
    
    // Get tab ID
    var tabId = args[0].replace('out=', '');
    // Get node
    var node = args[1].replace('node=', '');
    // Clear any existing cookie
    $.cookie(node + 'processes', null);
    
    // Remove loader
    $('#' + tabId).find('img').remove();
    
    // Check for error
    var error = false;
    if (data.rsp.length && data.rsp[0].indexOf('Error') > -1) {
        error = true;
        
        var warn = createWarnBar(data.rsp[0]);
        $('#' + tabId).append(warn);        
    }
    
    // Determine the node type
    if (data.rsp.length && data.rsp[0].indexOf('Hypervisor OS:') > -1) {
        loadHypervisorInventory(data);
        return;
    }
    
    // Create status bar
    var statBarId = node + 'StatusBar';
    var statBar = createStatusBar(statBarId);

    // Add loader to status bar and hide it
    var loader = createLoader(node + 'StatusBarLoader').hide();
    statBar.find('div').append(loader);
    statBar.hide();
    
	// Create division to hold user entry
    var ueDivId = node + 'UserEntry';
    var ueDiv = $('<div class="userEntry" id="' + ueDivId + '"></div>');

    // Create division to hold inventory
    var invDivId = node + 'Inventory';
    var invDiv = $('<div class="inventory" id="' + invDivId + '"></div>');

    /**
     * Show user entry
     */
    var toggleLinkId = node + 'ToggleLink';
    var toggleLink = $('<a style="color: blue;" id="' + toggleLinkId + '">Show directory entry</a>');
    toggleLink.one('click', function(event) {
        // Toggle inventory division
        $('#' + invDivId).toggle();

        // Create loader
        var loader = createLoader(node + 'TabLoader');
        loader = $('<center></center>').append(loader);
        ueDiv.append(loader);

        // Get user entry
        var msg = 'out=' + ueDivId + ';node=' + node;
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'lsvm',
                tgt : node,
                args : '',
                msg : msg
            },

            success : loadUserEntry
        });

        // Change text
        $(this).text('Show inventory');

        // Disable toggle link
        $(this).unbind(event);
    });

    // Align toggle link to the right
    var toggleLnkDiv = $('<div class="toggle"></div>').css({
        'text-align' : 'right'
    });
    toggleLnkDiv.append(toggleLink);
    
    // Append to tab
    $('#' + tabId).append(statBar);
    $('#' + tabId).append(toggleLnkDiv);
    $('#' + tabId).append(ueDiv);
    $('#' + tabId).append(invDiv);
    
    // Do not load inventory if no inventory is returned
    if (data.rsp.length && data.rsp[0].indexOf('z/VM UserID:') > -1) {
        // Do nothing
    } else {
        return;
    }

    // Create array of property keys (VM)
    var keys = new Array('userId', 'host', 'os', 'arch', 'uptime', 'cpuusedtime', 'hcp', 'priv', 'memory', 'maxmemory', 'proc', 'disk', 'zfcp', 'nic');

    // Create hash table for property names (VM)
    var attrNames = new Object();
    attrNames['userId'] = 'z/VM UserID:';
    attrNames['host'] = 'z/VM Host:';
    attrNames['os'] = 'Operating System:';
    attrNames['arch'] = 'Architecture:';
    attrNames['uptime'] = 'Uptime:';
    attrNames['cpuusedtime'] = 'CPU Used Time:';
    attrNames['hcp'] = 'HCP:';
    attrNames['priv'] = 'Privileges:';
    attrNames['memory'] = 'Total Memory:';
    attrNames['maxmemory'] = 'Max Memory:';
    attrNames['proc'] = 'Processors:';
    attrNames['disk'] = 'Disks:';
    attrNames['zfcp'] = 'zFCP:';
    attrNames['nic'] = 'NICs:';
    
    // Create hash table for node attributes
    var inv = data.rsp[0].split(node + ':');  
    var attrs;
    if (!error) {
        attrs = getAttrs(keys, attrNames, inv);
    }

    // Do not continue if error
    if (error) {
        return;
    }
        
    /**
     * General info section
     */
    var fieldSet = $('<fieldset></fieldset>');
    var legend = $('<legend>General</legend>');
    fieldSet.append(legend);
    var oList = $('<ol></ol>');
    var item, label, args;

    // Loop through each property
    for (var k = 0; k < 6; k++) {
        // Create a list item for each property
        item = $('<li></li>');
        
        // Create a label - Property name
        label = $('<label>' + attrNames[keys[k]] + '</label>');
        item.append(label);
        
        for (var l = 0; l < attrs[keys[k]].length; l++) {
            // Create a input - Property value(s)
            // Handle each property uniquely
            item.append(attrs[keys[k]][l]);
        }

        oList.append(item);
    }
    // Append to inventory form
    fieldSet.append(oList);
    invDiv.append(fieldSet);

    /**
     * Hardware info section
     */
    var hwList, hwItem;
    fieldSet = $('<fieldset></fieldset>');
    legend = $('<legend>Hardware</legent>');
    fieldSet.append(legend);
    oList = $('<ol></ol>');

    // Loop through each property
    var label;
    for (k = 6; k < keys.length; k++) {
        // Create a list item
        item = $('<li></li>');

        // Create a list to hold the property value(s)
        hwList = $('<ul></ul>');
        hwItem = $('<li></li>');

        /**
         * Privilege section
         */
        if (keys[k] == 'priv') {
            // Create a label - Property name
            label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
            item.append(label);
            
            // Loop through each line
            for (l = 0; l < attrs[keys[k]].length; l++) {
                // Create a new list item for each line
                hwItem = $('<li></li>');

                // Determine privilege
                args = attrs[keys[k]][l].split(' ');
                if (args[0] == 'Directory:') {
                    label = $('<label>' + args[0] + '</label>');
                    hwItem.append(label);
                    hwItem.append(args[1]);
                } else if (args[0] == 'Currently:') {
                    label = $('<label>' + args[0] + '</label>');
                    hwItem.append(label);
                    hwItem.append(args[1]);
                }

                hwList.append(hwItem);
            }

            item.append(hwList);
        }

        /**
         * Memory section
         */
        else if (keys[k] == 'memory') {
            // Create a label - Property name
            label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
            item.append(label);

            // Loop through each value line
            for (l = 0; l < attrs[keys[k]].length; l++) {
                // Create a new list item for each line
                hwItem = $('<li></li>');
                hwItem.append(attrs[keys[k]][l]);
                hwList.append(hwItem);
            }

            item.append(hwList);
        }

        /**
         * Processor section
         */
        else if (keys[k] == 'proc') {
            // Create a label - Property name
            label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
            item.append(label);

            // Create a table to hold processor data
            var procTable = $('<table></table>');
            var procBody = $('<tbody></tbody>');
            var procFooter = $('<tfoot></tfoot>');

            // Table columns - Type, Address, ID, Base, Dedicated, and Affinity
            var procTabRow = $('<thead class="ui-widget-header"> <th>Type</th> <th>Address</th> <th>ID</th> <th>Base</th> <th>Dedicated</th> <th>Affinity</th> </thead>');
            procTable.append(procTabRow);
            var procId, procAff;

            /**
             * Remove processor
             */
            var contextMenu = [{
                'Remove' : function(menuItem, menu) {
                    var addr = $(this).text();
                
                    // Open dialog to confirm
                    var confirmDialog = $('<div><p>Are you sure you want to remove this processor?</p></div>');                   
                    confirmDialog.dialog({
                        title: "Confirm",
                        modal: true,
                        width: 300,
                        buttons: {
                            "Ok": function(){
                                removeProcessor(node, addr);
                                $(this).dialog("close");
                            },
                            "Cancel": function() {
                                $(this).dialog("close");
                            }
                        }
                    });                    
                }
            }];

            // Loop through each processor
            var n, temp;
            var procType, procAddr, procLink;
            for (l = 0; l < attrs[keys[k]].length; l++) {
                if (attrs[keys[k]][l]) {            
                    args = attrs[keys[k]][l].split(' ');
                    
                    // Get processor type, address, ID, and affinity
                    n = 3;
                    temp = args[args.length - n];
                    while (!jQuery.trim(temp)) {
                        n = n + 1;
                        temp = args[args.length - n];
                    }
                    procType = $('<td>' + temp + '</td>');
                    procAddr = $('<td></td>');
                    procLink = $('<a>' + args[1] + '</a>');
                    
                    // Append context menu to link
                    procLink.contextMenu(contextMenu, {
                        theme : 'vista'
                    });
                    
                    procAddr.append(procLink);
                    procId = $('<td>' + args[5] + '</td>');
                    procAff = $('<td>' + args[args.length - 1] + '</td>');
    
                    // Base processor
                    if (args[6] == '(BASE)') {
                        baseProc = $('<td>' + true + '</td>');
                    } else {
                        baseProc = $('<td>' + false + '</td>');
                    }
    
                    // Dedicated processor
                    if (args[args.length - 3] == 'DEDICATED') {
                        dedicatedProc = $('<td>' + true + '</td>');
                    } else {
                        dedicatedProc = $('<td>' + false + '</td>');
                    }
    
                    // Create a new row for each processor
                    procTabRow = $('<tr></tr>');
                    procTabRow.append(procType);
                    procTabRow.append(procAddr);
                    procTabRow.append(procId);
                    procTabRow.append(baseProc);
                    procTabRow.append(dedicatedProc);
                    procTabRow.append(procAff);
                    procBody.append(procTabRow);
                }
            }
            
            procTable.append(procBody);

            /**
             * Add processor
             */
            var addProcLink = $('<a>+ Add temporary processor</a>');
            addProcLink.bind('click', function(event) {
                openAddProcDialog(node);
            });
            
            procFooter.append(addProcLink);
            procTable.append(procFooter);
            item.append(procTable);
        }

        /**
         * Disk section
         */
        else if (keys[k] == 'disk') {
            // Create a label - Property name
            label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
            item.append(label);

            // Create a table to hold disk (DASD) data
            var dasdTable = $('<table></table>');
            var dasdBody = $('<tbody></tbody>');
            var dasdFooter = $('<tfoot></tfoot>');

            /**
             * Remove disk
             */
            contextMenu = [{
                'Remove' : function(menuItem, menu) {
                    var addr = $(this).text();
                    
                    // Open dialog to confirm
                    var confirmDialog = $('<div><p>Are you sure you want to remove this disk?</p></div>');                   
                    confirmDialog.dialog({
                        title: "Confirm",
                        modal: true,
                        width: 300,
                        buttons: {
                            "Ok": function(){
                                removeDisk(node, addr);
                                $(this).dialog("close");
                            },
                            "Cancel": function() {
                                $(this).dialog("close");
                            }
                        }
                    });    
                }
            }];

            // Table columns - Virtual Device, Type, VolID, Type of Access, and Size
            var dasdTabRow = $('<thead class="ui-widget-header"> <th>Virtual Device #</th> <th>Type</th> <th>VolID</th> <th>Type of Access</th> <th>Size</th> </thead>');
            dasdTable.append(dasdTabRow);
            var dasdVDev, dasdType, dasdVolId, dasdAccess, dasdSize;

            // Loop through each DASD
            for (l = 0; l < attrs[keys[k]].length; l++) {
                if (attrs[keys[k]][l]) {
                    args = attrs[keys[k]][l].split(' ');

                    // Get DASD virtual device, type, volume ID, access, and size
                    dasdVDev = $('<td></td>');
                    dasdLink = $('<a>' + args[1] + '</a>');
    
                    // Append context menu to link
                    dasdLink.contextMenu(contextMenu, {
                        theme : 'vista'
                    });
                    dasdVDev.append(dasdLink);
    
                    dasdType = $('<td>' + args[2] + '</td>');
                    dasdVolId = $('<td>' + args[3] + '</td>');
                    dasdAccess = $('<td>' + args[4] + '</td>');
                    dasdSize = $('<td>' + args[args.length - 9] + ' ' + args[args.length - 8] + '</td>');
    
                    // Create a new row for each DASD
                    dasdTabRow = $('<tr></tr>');
                    dasdTabRow.append(dasdVDev);
                    dasdTabRow.append(dasdType);
                    dasdTabRow.append(dasdVolId);
                    dasdTabRow.append(dasdAccess);
                    dasdTabRow.append(dasdSize);
                    dasdBody.append(dasdTabRow);
                }
            }
            
            dasdTable.append(dasdBody);

            /**
             * Add disk
             */
            var addDasdLink = $('<a>+ Add disk</a>');
            addDasdLink.bind('click', function(event) {
                var hcp = attrs['hcp'][0].split('.');
                openAddDiskDialog(node, hcp[0]);
            });
            dasdFooter.append(addDasdLink);
            dasdTable.append(dasdFooter);

            item.append(dasdTable);
        }
        
        /**
         * zFCP section
         */
        else if (keys[k] == 'zfcp') {
            // Create a label - Property name
            label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
            item.append(label);

            // Create a table to hold NIC data
            var zfcpTable = $('<table></table>');
            var zfcpBody = $('<tbody></tbody>');
            var zfcpFooter = $('<tfoot></tfoot>');

            /**
             * Remove zFCP
             */
            contextMenu = [ {
                'Remove' : function(menuItem, menu) {
                    var addr = $(this).text();
                    var portName = $(this).parents('tr').find('td:eq(1)').text();
                    var unitNo = $(this).parents('tr').find('td:eq(2)').text();
                    
                    // Open dialog to confirm
                    var confirmDialog = $('<div><p>Are you sure you want to remove this zFCP device?</p></div>');                   
                    confirmDialog.dialog({
                        title: "Confirm",
                        modal: true,
                        width: 300,
                        buttons: {
                            "Ok": function(){
                                removeZfcp(node, addr, portName, unitNo);
                                $(this).dialog("close");
                            },
                            "Cancel": function() {
                                $(this).dialog("close");
                            }
                        }
                    });
                }
            } ];

            // Table columns - Virtual device, Adapter Type, Port Name, # of Devices, MAC Address, and LAN Name
            var zfcpTabRow = $('<thead class="ui-widget-header"> <th>Virtual Device #</th> <th>Port Name</th> <th>Unit Number</th> <th>Size</th></thead>');
            zfcpTable.append(zfcpTabRow);
            var zfcpVDev, zfcpPortName, zfcpLun, zfcpSize;

            // Loop through each zFCP device
            if (attrs[keys[k]]) {
                for (l = 0; l < attrs[keys[k]].length; l++) {
                    if (attrs[keys[k]][l]) {
                        args = attrs[keys[k]][l].split(' ');
        
                        // Get zFCP virtual device, port name (WWPN), unit number (LUN), and size
                        zfcpVDev = $('<td></td>');
                        zfcpLink = $('<a>' + args[1].replace('0.0.', '') + '</a>');
        
                        // Append context menu to link
                        zfcpLink.contextMenu(contextMenu, {
                            theme : 'vista'
                        });
                        zfcpVDev.append(zfcpLink);
        
                        zfcpPortName = $('<td>' + args[4] + '</td>');
                        zfcpLun = $('<td>' + args[7] + '</td>');
                        zfcpSize = $('<td>' + args[args.length - 2] + ' ' + args[args.length - 1] + '</td>');
        
                        // Create a new row for each zFCP device
                        zfcpTabRow = $('<tr></tr>');
                        zfcpTabRow.append(zfcpVDev);
                        zfcpTabRow.append(zfcpPortName);
                        zfcpTabRow.append(zfcpLun);
                        zfcpTabRow.append(zfcpSize);
        
                        zfcpBody.append(zfcpTabRow);
                    }
                }
            }

            zfcpTable.append(zfcpBody);

            /**
             * Add dedicated device
             */
            var dedicateDeviceLink = $('<a>+ Add dedicated device</a>').css('display', 'block');
            dedicateDeviceLink.bind('click', function(event) {
                var hcp = attrs['hcp'][0].split('.');
                openDedicateDeviceDialog(node, hcp[0]);
            });
            
            /**
             * Add zFCP device
             */
            var addZfcpLink = $('<a>+ Add zFCP</a>').css('display', 'block');
            addZfcpLink.bind('click', function(event) {
                var hcp = attrs['hcp'][0].split('.');
                var zvm = attrs['host'][0].toLowerCase();
                openAddZfcpDialog(node, hcp[0], zvm);
            });
            
            zfcpFooter.append(dedicateDeviceLink, addZfcpLink);
            zfcpTable.append(zfcpFooter);

            item.append(zfcpTable);
        }

        /**
         * NIC section
         */
        else if (keys[k] == 'nic') {
            // Create a label - Property name
            label = $('<label><b>' + attrNames[keys[k]].replace(':', '') + '</b></label>');
            item.append(label);

            // Create a table to hold NIC data
            var nicTable = $('<table></table>');
            var nicBody = $('<tbody></tbody>');
            var nicFooter = $('<tfoot></tfoot>');

            /**
             * Remove NIC
             */
            contextMenu = [ {
                'Remove' : function(menuItem, menu) {
                    var addr = $(this).text();
                    
                    // Open dialog to confirm
                    var confirmDialog = $('<div><p>Are you sure you want to remove this NIC?</p></div>');                   
                    confirmDialog.dialog({
                        title: "Confirm",
                        modal: true,
                        width: 300,
                        buttons: {
                            "Ok": function(){
                                removeNic(node, addr);
                                $(this).dialog("close");
                            },
                            "Cancel": function() {
                                $(this).dialog("close");
                            }
                        }
                    });
                }
            } ];

            // Table columns - Virtual device, Adapter Type, Port Name, # of Devices, MAC Address, and LAN Name
            var nicTabRow = $('<thead class="ui-widget-header"> <th>Virtual Device #</th> <th>Adapter Type</th> <th>Port Name</th> <th># of Devices</th> <th>LAN Name</th></thead>');
            nicTable.append(nicTabRow);
            var nicVDev, nicType, nicPortName, nicNumOfDevs, nicLanName;

            // Loop through each NIC (Data contained in 2 lines)
            for (l = 0; l < attrs[keys[k]].length; l++) {
                if (attrs[keys[k]][l].indexOf('Adapter') != -1) {
                    args = attrs[keys[k]][l].split(' ');
    
                    // Get NIC virtual device, type, port name, and number of devices
                    nicVDev = $('<td></td>');
                    nicLink = $('<a>' + args[1] + '</a>');
    
                    // Append context menu to link
                    nicLink.contextMenu(contextMenu, {
                        theme : 'vista'
                    });
                    nicVDev.append(nicLink);
    
                    nicType = $('<td>' + args[3] + '</td>');
                    nicPortName = $('<td>' + args[10] + '</td>');
                    nicNumOfDevs = $('<td>' + args[args.length - 1] + '</td>');
    
                    args = attrs[keys[k]][l + 1].split(' ');
                    nicLanName = $('<td>' + args[args.length - 2] + ' ' + args[args.length - 1] + '</td>');
    
                    // Create a new row for each NIC
                    nicTabRow = $('<tr></tr>');
                    nicTabRow.append(nicVDev);
                    nicTabRow.append(nicType);
                    nicTabRow.append(nicPortName);
                    nicTabRow.append(nicNumOfDevs);
                    nicTabRow.append(nicLanName);
    
                    nicBody.append(nicTabRow);
                }
            }

            nicTable.append(nicBody);

            /**
             * Add NIC
             */
            var addNicLink = $('<a>+ Add NIC</a>');
            addNicLink.bind('click', function(event) {
                var hcp = attrs['hcp'][0].split('.');
                openAddNicDialog(node, hcp[0]);
            });
            nicFooter.append(addNicLink);
            nicTable.append(nicFooter);

            item.append(nicTable);
        } 
        
        // Ignore any fields not in key
        else {
            continue;
        }

        oList.append(item);
    }

    // Append inventory to division
    fieldSet.append(oList);
    invDiv.append(fieldSet);
};

/**
 * Load hypervisor inventory
 * 
 * @param data Data from HTTP request
 */
function loadHypervisorInventory(data) {
    var args = data.msg.split(',');
    
    // Get tab ID
    var tabId = args[0].replace('out=', '');
    // Get node
    var node = args[1].replace('node=', '');
    
    // Remove loader
    $('#' + tabId).find('img').remove();
    
    // Check for error
    var error = false;
    if (data.rsp.length && data.rsp[0].indexOf('Error') > -1) {
        error = true;
        
        var warn = createWarnBar(data.rsp[0]);
        $('#' + tabId).append(warn);        
    }
    
    // Get node inventory
    var inv = data.rsp[0].split(node + ':');  

    // Create status bar
    var statBarId = node + 'StatusBar';
    var statBar = createStatusBar(statBarId);

    // Add loader to status bar and hide it
    var loader = createLoader(node + 'StatusBarLoader').hide();
    statBar.find('div').append(loader);
    statBar.hide();
        
    // Create array of property keys (z/VM hypervisor)
    var keys = new Array('host', 'hcp', 'arch', 'cecvendor', 'cecmodel', 'hypos', 'hypname', 'lparcputotal', 'lparcpuused', 'lparmemorytotal', 'lparmemoryused', 'lparmemoryoffline');

    // Create hash table for property names (z/VM hypervisor)
    var attrNames = new Object();
    attrNames['host'] = 'z/VM Host:';
    attrNames['hcp'] = 'zHCP:';
    attrNames['arch'] = 'Architecture:';
    attrNames['cecvendor'] = 'CEC Vendor:';
    attrNames['cecmodel'] = 'CEC Model:';
    attrNames['hypos'] = 'Hypervisor OS:';
    attrNames['hypname'] = 'Hypervisor Name:';    
    attrNames['lparcputotal'] = 'LPAR CPU Total:';
    attrNames['lparcpuused'] = 'LPAR CPU Used:';
    attrNames['lparmemorytotal'] = 'LPAR Memory Total:';
    attrNames['lparmemoryused'] = 'LPAR Memory Used:';
    attrNames['lparmemoryoffline'] = 'LPAR Memory Offline:';

    // Remove loader
    $('#' + tabId).find('img').remove();

    // Create hash table for node attributes
    var attrs;
    if (!error) {
        attrs = getAttrs(keys, attrNames, inv);
    }
    
    // Create division to hold inventory
    var invDivId = node + 'Inventory';
    var invDiv = $('<div class="inventory" id="' + invDivId + '"></div>');

    // Append to tab
    $('#' + tabId).append(statBar);
    $('#' + tabId).append(invDiv);

    // Do not continue if error
    if (error) {
        return;
    }
        
    /**
     * General info section
     */
    var fieldSet = $('<fieldset></fieldset>');
    var legend = $('<legend>General</legend>');
    fieldSet.append(legend);
    var oList = $('<ol></ol>');
    var item, label, args;

    // Loop through each property
    for (var k = 0; k < 7; k++) {
        // Create a list item for each property
        item = $('<li></li>');
        
        // Create a label - Property name
        label = $('<label>' + attrNames[keys[k]] + '</label>');
        item.append(label);
        
        for (var l = 0; l < attrs[keys[k]].length; l++) {
            // Create a input - Property value(s)
            // Handle each property uniquely
            item.append(attrs[keys[k]][l]);
        }

        oList.append(item);
    }
    // Append to inventory form
    fieldSet.append(oList);
    invDiv.append(fieldSet);
    
    /**
     * Hardware info section
     */
    var hwList, hwItem;
    fieldSet = $('<fieldset></fieldset>');
    legend = $('<legend>Hardware</legent>');
    fieldSet.append(legend);
    oList = $('<ol></ol>');

    // Loop through each property
    var label;
    for (k = 7; k < keys.length; k++) {
        // Create a list item for each property
        item = $('<li></li>');
        
        // Create a label - Property name
        label = $('<label>' + attrNames[keys[k]] + '</label>');
        item.append(label);
        
        for (var l = 0; l < attrs[keys[k]].length; l++) {
            // Create a input - Property value(s)
            // Handle each property uniquely
            item.append(attrs[keys[k]][l]);
        }

        oList.append(item);
    }
    // Append to inventory form
    fieldSet.append(oList);
    invDiv.append(fieldSet);
    
    // Append to inventory form
    $('#' + tabId).append(invDiv);
};

/**
 * Load provision page
 * 
 * @param tabId The provision tab ID
 */
zvmPlugin.prototype.loadProvisionPage = function(tabId) {
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
    var inst = tabId.replace('zvmProvisionTab', '');

    // Create provision form
    var provForm = $('<div class="form"></div>');

    // Create status bar
    var statBarId = 'zProvisionStatBar' + inst;
    var statBar = createStatusBar(statBarId).hide();
    provForm.append(statBar);

    // Create loader
    var loader = createLoader('zProvisionLoader' + inst).hide();
    statBar.find('div').append(loader);

    // Create info bar
    var infoBar = createInfoBar('Provision a node on System z.');
    provForm.append(infoBar);

    // Append to provision tab
    $('#' + tabId).append(provForm);

    var typeFS = $('<fieldset></fieldset>');
    var typeLegend = $('<legend>Type</legend>');
    typeFS.append(typeLegend);
    provForm.append(typeFS);
    
    // Create provision type drop down
    var provType = $('<div></div>');
    var typeLabel = $('<label>Type:</label>');
    var typeSelect = $('<select></select>');
    var provNewNode = $('<option value="new">New node</option>');
    var provExistNode = $('<option value="existing">Existing node</option>');
    typeSelect.append(provNewNode);
    typeSelect.append(provExistNode);
    provType.append(typeLabel);
    provType.append(typeSelect);
    typeFS.append(provType);
    
    /**
     * Create provision new node division
     */
    var provNew = createZProvisionNew(inst);
    provForm.append(provNew);
        
    /**
     * Create provision existing node division
     */
    var provExisting = createZProvisionExisting(inst);
    provForm.append(provExisting);

    // Toggle provision new/existing on select
    typeSelect.change(function(){
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
 * Load the resources
 */
zvmPlugin.prototype.loadResources = function() {    
    // Reset resource table
    setNetworkDataTable('');
    
    // Get hardware control points
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'nodels',
            tgt : 'mgt==zvm',
            args : 'zvm.hcp',
            msg : ''
        },
        success : getZResources
    });
};

/**
 * Add node range
 */
zvmPlugin.prototype.addNode = function() {
    // Create form to add node range
    var addNodeForm = $('<div id="addZvm" class="form"></div>');
    var info = createInfoBar('Add a z/VM node range');
    addNodeForm.append(info);
    
    // Create provision type drop down
    var type = $('<div></div>');
    var typeLabel = $('<label>Type:</label>');
    var typeSelect = $('<select type="text" name="type" title="The type of node"></select>');
    typeSelect.append('<option value="vm" selected="selected">VM</option>');
    typeSelect.append('<option value="host">Host</option>');
    type.append(typeLabel);
    type.append(typeSelect);
    addNodeForm.append(type);
    
    addNodeForm.append('<div><label>Node range *:</label><input type="text" name="node" title="The node or node range to add into xCAT. A node range must be given as: node1-node9 or node[1-9]."/></div>');
    addNodeForm.append('<div><label>User ID range *:</label><input type="text" name="userId" title="The user ID or a user ID range. A user ID range must be given as: user1-user9 or user[1-9]."/></div>');
    addNodeForm.append('<div><label>zHCP *:</label><input type="text" name="hcp" title="The System z hardware control point (zHCP) responsible for managing the node(s)"/></div>');
    addNodeForm.append('<div><label>Groups *:</label><input type="text" name="groups" title="The group where the new node(s) will be placed under"/></div>');
    addNodeForm.append('<div><label>Operating system *:</label><input type="text" name="os" title="The z/VM operating system version, e.g. zvm6.1."/></div>');
    addNodeForm.append('<div><label>IP address range:</label><input name="ip" type="text" title="The IP address range for the node(s). An IP address range must be given in the following format: 192.168.0.1-192.168.9."></div>');
    addNodeForm.append('<div><label>Hostname range:</label><input name="hostname" type="text" title="The hostname range for the node(s). A hostname range must be given in the following format: ihost1.sourceforge.net-ihost9.sourceforge.net."></div>');
    addNodeForm.append('<div><label>* required</label></div>');
    
    // OS field only required for hosts
    addNodeForm.find('input[name=os]').parent().hide();
    
    // Toggle user Id on select
    typeSelect.change(function(){
        var selected = $(this).val();
        if (selected == 'host') {
            addNodeForm.find('input[name=userId]').parent().toggle();
            addNodeForm.find('input[name=os]').parent().toggle();
        } else {
            addNodeForm.find('input[name=userId]').parent().toggle();
            addNodeForm.find('input[name=os]').parent().toggle();
        }
    });
    
	// Generate tooltips
    addNodeForm.find('div input[title],select[title]').tooltip({
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
    
    // Open form as a dialog
    addNodeForm.dialog({
        title: 'Add node',
        modal: true,
        width: 400,
        buttons: {
            "Ok": function(){
                // Remove any warning messages
                $(this).find('.ui-state-error').remove();
                
                // Get inputs
                var type = $(this).find('select[name=type]').val();
                var nodeRange = $(this).find('input[name=node]').val();
                var ipRange = $(this).find('input[name=ip]').val();
                var hostnameRange = $(this).find('input[name=hostname]').val();
                var userIdRange = $(this).find('input[name=userId]').val();
                var os = $(this).find('input[name=os]').val();
                var group = $(this).find('input[name=groups]').val();
                var hcp = $(this).find('input[name=hcp]').val();
                
                // Check required fields
                if (type == 'host') {
                    if (!nodeRange || !os || !group || !hcp) {
                        var warn = createWarnBar('Please provide a value for each missing field!');
                        warn.prependTo($(this));
                        return;
                    }
                } else {
                    if (!nodeRange || !userIdRange || !group || !hcp) {
                        var warn = createWarnBar('Please provide a value for each missing field!');
                        warn.prependTo($(this));
                        return;
                    }
                }
                
                // Check node range and user ID range
                // Range can be given as gpok10-gpok20, gpok[10-20], or gpok10+10
                var errMsg = '';
                var ready = true;
                if (nodeRange.indexOf('-') > -1 || userIdRange.indexOf('-') > -1) {
                    if (nodeRange.indexOf('-') < 0 || userIdRange.indexOf('-') < 0) {
                        errMsg = errMsg + 'A user ID range and node range needs to be given. ';
                        ready = false;
                    } else {
                        var tmp = nodeRange.split('-');

                        // Get starting index
                        var nodeStart = parseInt(tmp[0].match(/\d+/));
                        // Get ending index
                        var nodeEnd = parseInt(tmp[1].match(/\d+/));

                        tmp = userIdRange.split('-');

                        // Get starting index
                        var userIdStart = parseInt(tmp[0].match(/\d+/));
                        // Get ending index
                        var userIdEnd = parseInt(tmp[1].match(/\d+/));
                        
                        var ipStart = "", ipEnd = "";
                        if (ipRange != "" && ipRange != null) {
                            tmp = ipRange.split('-');
                            
                            // Get starting IP address
                            ipStart = tmp[0].substring(tmp[0].lastIndexOf(".") + 1);
                            // Get ending IP address
                            ipEnd = tmp[1].substring(tmp[1].lastIndexOf(".") + 1);
                        }
                        
                        var hostnameStart = "", hostnameEnd = "";
                        if (hostnameRange != "" && hostnameRange != null) {
                            tmp = hostnameRange.split('-');
        
                            // Get starting hostname
                            hostnameStart = parseInt(tmp[0].substring(0, tmp[0].indexOf(".")).match(/\d+/));
                            // Get ending hostname
                            hostnameEnd = parseInt(tmp[1].substring(0, tmp[1].indexOf(".")).match(/\d+/));
                        }
                            
                        // If starting and ending index do not match
                        if (!(nodeStart == userIdStart) || !(nodeEnd == userIdEnd)) {
                            errMsg = errMsg + 'The node range and user ID range does not match. ';
                            ready = false;
                        }
                        
                        // If an IP address range is given and the starting and ending index do not match
                        if (ipRange != "" && ipRange != null && (!(nodeStart == ipStart) || !(nodeEnd == ipEnd))) {
                            errMsg = errMsg + 'The node range and IP address range does not match. ';
                            ready = false;
                        }
                        
                        // If a hostname range is given and the starting and ending index do not match
                        if (hostnameRange != "" && hostnameRange != null && (!(nodeStart == hostnameStart) || !(nodeEnd == hostnameEnd))) {
                            errMsg = errMsg + 'The node range and hostname range does not match. ';
                            ready = false;
                        }
                    }
                }
                                    
                // If there are no errors
                if (ready) {
                	$('#addZvm').append(createLoader());
                    
                    // Change dialog buttons
                    $('#addZvm').dialog('option', 'buttons', {
                        'Close':function() {
                        	$('#addZvm').dialog('destroy').remove();
                        }
                    });
                    
                    // If a node range is given
                    if (nodeRange.indexOf('-') > -1 && userIdRange.indexOf('-') > -1) {
                        var tmp = nodeRange.split('-');
                
                        // Get node base name
                        var nodeBase = tmp[0].match(/[a-zA-Z]+/);
                        // Get starting index
                        var nodeStart = parseInt(tmp[0].match(/\d+/));
                        // Get ending index
                        var nodeEnd = parseInt(tmp[1].match(/\d+/));
                
                        tmp = userIdRange.split('-');
                
                        // Get user ID base name
                        var userIdBase = tmp[0].match(/[a-zA-Z]+/);
                        
                        var ipBase = "";
                        if (ipRange != "" && ipRange != null) {
                            tmp = ipRange.split('-');
                            
                            // Get network base
                            ipBase = tmp[0].substring(0, tmp[0].lastIndexOf(".") + 1);
                        }
                        
                        var domain = "";
                        if (hostnameRange != "" && hostnameRange != null) {
                            tmp = hostnameRange.split('-');
                        
                            // Get domain name
                            domain = tmp[0].substring(tmp[0].indexOf("."));
                        }
                
                        // Loop through each node in the node range
                        for ( var i = nodeStart; i <= nodeEnd; i++) {
                            var node = nodeBase + i.toString();
                            var userId = userIdBase + i.toString();
                            var inst = i + '/' + nodeEnd;
                
                            var args = "";
                            if (type == 'host') {
                                args = node + ';zvm.hcp=' + hcp
                                    + ';nodehm.mgt=zvm;nodetype.arch=s390x;hypervisor.type=zvm;groups=' + group
                                    + ';nodetype.os=' + os;
                            } else {
                                args = node + ';zvm.hcp=' + hcp
                                    + ';zvm.userid=' + userId
                                    + ';nodehm.mgt=zvm' + ';nodetype.arch=s390x' + ';groups=' + group;
                            }                            
                            
                            if (ipRange != "" && ipRange != null) {
                                var ip = ipBase + i.toString();
                                args += ';hosts.ip=' + ip;
                            }
                            
                            if (hostnameRange != "" && hostnameRange != null) {
                                var hostname = node + domain;
                                args += ';hosts.hostnames=' + hostname;
                            }
                            
                            /**
                             * (1) Define node
                             */
                            $.ajax( {
                                url : 'lib/cmd.php',
                                dataType : 'json',
                                data : {
                                    cmd : 'nodeadd',
                                    tgt : '',
                                    args : args,
                                    msg : 'cmd=addnewnode;inst=' + inst + ';noderange=' + nodeRange
                                },
                
                                /**
                                 * Return function on successful AJAX call
                                 * 
                                 * @param data
                                 *            Data returned from HTTP request
                                 * @return Nothing
                                 */
                                success : function (data) {
                                    // Get ajax response
                                    var rsp = data.rsp;
                                    var args = data.msg.split(';');
                
                                    // Get instance returned and node range
                                    var inst = args[1].replace('inst=', '');                        
                                    var nodeRange = args[2].replace('noderange=', '');
                                    
                                    // If the last node was added
                                    var tmp = inst.split('/');
                                    if (tmp[0] == tmp[1]) {
                                        // Update /etc/hosts
                                        $.ajax({
                                            url : 'lib/cmd.php',
                                            dataType : 'json',
                                            data : {
                                                cmd : 'makehosts',
                                                tgt : '',
                                                args : '',
                                                msg : ''
                                            }
                                        });
                                        
                                        // Remove loader
                                        $('#addZvm img').remove();
                                        
                                        // If there was an error, do not continue
                                        if (rsp.length) {
                                            $('#addZvm').prepend(createWarnBar('Failed to create node definitions'));
                                        } else {
                                            $('#addZvm').prepend(createInfoBar('Node definitions created for ' + nodeRange));
                                        }
                                    }
                                }
                            });
                        }
                    } else {
                        var args = "";
                        if (type == 'host') {
                            args = nodeRange + ';zvm.hcp=' + hcp
                                + ';nodehm.mgt=zvm;nodetype.arch=s390x;hypervisor.type=zvm;groups=' + group
                                + ';nodetype.os=' + os;
                        } else {
                            args = nodeRange + ';zvm.hcp=' + hcp
                                + ';zvm.userid=' + userIdRange
                                + ';nodehm.mgt=zvm' + ';nodetype.arch=s390x' + ';groups=' + group;
                        } 
                        
                        if (ipRange)
                            args += ';hosts.ip=' + ipRange;
                        
                        if (hostnameRange)
                            args += ';hosts.hostnames=' + hostnameRange;
                        
                        // Only one node to add
                        $.ajax( {
                            url : 'lib/cmd.php',
                            dataType : 'json',
                            data : {
                                cmd : 'nodeadd',
                                tgt : '',
                                args : args,
                                msg : 'cmd=addnewnode;node=' + nodeRange
                            },
                
                            /**
                             * Return function on successful AJAX call
                             * 
                             * @param data
                             *            Data returned from HTTP request
                             * @return Nothing
                             */
                            success : function (data) {
                                // Get ajax response
                                var rsp = data.rsp;
                                var args = data.msg.split(';');
                                var node = args[1].replace('node=', '');
                                
                                // Update /etc/hosts
                                $.ajax({
                                    url : 'lib/cmd.php',
                                    dataType : 'json',
                                    data : {
                                        cmd : 'makehosts',
                                        tgt : '',
                                        args : '',
                                        msg : ''
                                    }
                                });
                                
                                // Remove loader
                                $('#addZvm img').remove();
                                
                                // If there was an error, do not continue
                                if (rsp.length) {
                                    $('#addZvm').prepend(createWarnBar('Failed to create node definitions'));
                                } else {
                                    $('#addZvm').prepend(createInfoBar('Node definitions created for ' + node));
                                }
                            }
                        });
                    }
                } else {
                    // Show warning message
                    var warn = createWarnBar(errMsg);
                    warn.prependTo($(this));
                }
            },
            "Cancel": function(){
            	$(this).dialog('destroy').remove();
            }
        }
    });
};

/**
 * Migrate page
 * 
 * @param tgtNode  Targets to migrate
 */
zvmPlugin.prototype.loadMigratePage = function(tgtNode) {
    var hosts = $.cookie('zvms').split(',');
    var radio, zvmBlock, args;
    var zvms = new Array();
    var hcp = new Object();
    
    // Create a drop-down for z/VM destinations 
    var destSelect = $('<select name="dest" title="The z/VM SSI cluster name of the destination system to which the specified virtual machine will be relocated."></select>')
    destSelect.append($('<option></option>'));
    for (var i in hosts) {
        args = hosts[i].split(':');
        hcp[args[0]] = args[1];
        zvms.push(args[0]);
        
        destSelect.append($('<option>' + args[0] + '</option>'));
    }
        
    // Get nodes tab
    var tab = getNodesTab();

    // Generate new tab ID
    var inst = 0;
    var newTabId = 'migrateTab' + inst;
    while ($('#' + newTabId).length) {
        // If one already exists, generate another one
        inst = inst + 1;
        newTabId = 'migrateTab' + inst;
    }

    // Open new tab
    // Create remote script form
    var migrateForm = $('<div class="form"></div>');

    // Create status bar
    var barId = 'migrateStatusBar' + inst;
    var statBar = createStatusBar(barId);
    statBar.hide();
    migrateForm.append(statBar);

    // Create loader
    var loader = createLoader('migrateLoader' + inst);
    statBar.find('div').append(loader);

    // Create info bar
    var infoBar = createInfoBar('Migrate, test relocation eligibility, or cancel the relocation of the specified virtual machine, while it continues to run, to the specified system within the z/VM SSI cluster.');
    migrateForm.append(infoBar);

    // Virtual machine label
    var vmFS = $('<fieldset><legend>Virtual Machine</legend></fieldset>');
    migrateForm.append(vmFS);
    
    var vmAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    vmFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/computer.png"></img></div>'));
    vmFS.append(vmAttr);
    
    // Target node or group
    var tgt = $('<div><label>Target node range:</label><input type="text" name="target" value="' + tgtNode + '" title="The node or node range to migrate, test, or cancel relocation"/></div>');
    vmAttr.append(tgt);
    
    // Destination
    var dest = $('<div><label>Destination:</label></div>');
    var destInput = $('<input type="text" name="dest" title="The z/VM SSI cluster name of the destination system to which the specified virtual machine will be relocated"/>');
    destInput.autocomplete({
        source: zvms
    });
    
    // Create a drop-down if there are known z/VMs
    if (zvms.length) {
    	dest.append(destSelect);
    } else {
    	dest.append(destInput);
    }
    vmAttr.append(dest);
    
    // Action Parameter
    var actionparam = $('<div><label>Action:</label><select name="action" title="Initiate a VMRELOCATE of the virtual machine. Test the specified virtual machine and determine if it is eligible to be relocated. Stop the relocation of the specified virtual machine.">' + 
    		'<option value=""></option>' +
    		'<option value="MOVE">Move</option>' +
    		'<option value="TEST">Test</option>' +
    		'<option value="CANCEL">Cancel</option>' +
    	'</select></div>');
    vmAttr.append(actionparam);
    
    // Parameters label
    var optionalFS = $('<fieldset><legend>Optional</legend></fieldset>').css('margin-top', '20px');
    migrateForm.append(optionalFS);
    
    var optAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    optionalFS.append($('<div style="display: inline-table; vertical-align: middle; width: 70px;"><img src="images/provision/setting.png" style="width: 90%;"></img></div>'));
    optionalFS.append(optAttr);
    
    // Immediate Parameter
    var immediateparam = $('<div><label>Immediate:</label><select name="immediate" title="Select No to specify immediate processing (default). Select Yes to specify the VMRELOCATE command will do one early pass through virtual machine storage and then go directly to the quiesce stage. The defaults for both max_total and max_quiesce are NOLIMIT when immediate=YES is specified.">' + 
    		'<option value="NO">No (default)</option>' +
    		'<option value="YES">Yes</option>' +
    	'</select></div>');
    optAttr.append(immediateparam);
    immediateparam.change(function() {
        if ($('#' + newTabId + ' select[name=immediate]').val() == 'yes') {
            $('#' + newTabId + ' input[name=maxQuiesce]').val('0'); 
        } else { 
            $('#' + newTabId + ' input[name=maxQuiesce]').val('10'); 
        }
    });
    
    // Max total
    var maxTotalParam = $('<div><label>Max total time:</label><input type="text" name="maxTotal" value="0" title="The maximum total time in seconds that the command issuer is willing to wait for the entire relocation (0 indicates no limit)"/></div>');
    optAttr.append(maxTotalParam);
    
    // Max quiesce
    var maxQuiesceParam = $('<div><label>Max quiesce time:</label><input type="text" name="maxQuiesce" value="10" title="The maximum quiesce time (in seconds) a virtual machine may be stopped during a relocation attempt (0 indicates no limit)"/></div>');
    optAttr.append(maxQuiesceParam);
    
    // Force parameter
    var forceParam = $('<div style="width: 500px;"><label>Force:</label><input type="checkbox" name="force" value="ARCHITECTURE" style="margin-left:10px">Architecture</input><input type="checkbox" name="force" value="DOMAIN" style="margin-left:10px">Domain</input><input type="checkbox" name="force" value="STORAGE" style="margin-left:10px">Storage</input></div>');
    optAttr.append(forceParam);
    
    // Generate tooltips
    migrateForm.find('div input[title],select[title]').tooltip({
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
     * Run
     */
    var runBtn = createButton('Run');
    runBtn.click(function() {
        // Remove any warning messages
        $(this).parent().parent().find('.ui-state-error').remove();
        
        var tgt = $('#' + newTabId + ' input[name=target]');
        
        // Drop-down box exists if z/VM systems are known
        // Otherwise, only input box exists
        var dest = $('#' + newTabId + ' select[name=dest]');
        if (!dest.length) {
        	dest = $('#' + newTabId + ' input[name=dest]');
        }
        
        var action = $('#' + newTabId + ' select[name=action]');
        var immediate = $('#' + newTabId + ' select[name=immediate]');
        var maxTotal = $('#' + newTabId + ' input[name=maxTotal]');
        var maxQuiesce = $('#' + newTabId + ' input[name=maxQuiesce]');
        var tgts = $('#' + newTabId + ' input[name=target]');
        
        // Change borders color back to normal
        var inputs = $('#' + newTabId + ' input').css('border', 'solid #BDBDBD 1px');
        var inputs = $('#' + newTabId + ' select').css('border', 'solid #BDBDBD 1px');
                
        // Check if required arguments are given
        var message = "";
        if (!isInteger(maxTotal.val())) {
            message += "Max total time must be an integer. ";
            maxTotal.css('border', 'solid #FF0000 1px');
        } if (!isInteger(maxQuiesce.val())) {
            message += "Max quiesce time must be an integer. ";
            maxQuiesce.css('border', 'solid #FF0000 1px');
        } if (!tgt.val()) {
            message += "Target must be specified. ";
            tgt.css('border', 'solid #FF0000 1px');
        } if (!dest.val()) {
            message += "Destination must be specified. ";
            dest.css('border', 'solid #FF0000 1px');
        } if (!action.val()) {
            message += "Action must be specified. ";
            action.css('border', 'solid #FF0000 1px');
        }
        
        // Show warning message
        if (message) {
            var warn = createWarnBar(message);
            warn.prependTo($(this).parent().parent());
            return;
        }
        
        var args = "destination=" + dest.val() + ";action=" + action.val() + ";immediate=" + immediate.val() + ";";
        
        // Append max total argument. Specified <= 0 to accomodate negative values.
        if (maxTotal.val() <= 0) { 
            args = args + "max_total=NOLIMIT;"; 
        } else { 
            args = args + "max_total=" + maxTotal.val() + ";";
        }
        
        // Append max quiesce argument. Specified <= 0 to accomodate negative values.
        if (maxQuiesce.val() <= 0) { 
            args = args + "max_quiesce=NOLIMIT;"; 
        } else { 
            args = args + "max_quiesce=" + maxQuiesce.val() + ";"; 
        }
        
        // Append force argument
        if ($("input[name=force]:checked").length > 0) {
            args = args + "'force="
            $("input[name=force]:checked").each(function() {
                args += $(this).val() + ' ';
            });
            args += "';";
        }
        
        var statBarId = 'migrateStatusBar' + inst;
        $('#' + statBarId).show();

        // Disable all fields
        $('#' + newTabId + ' input').attr('disabled', 'true');
        $('#' + newTabId + ' select').attr('disabled', 'true');
        
        // Disable buttons
        $('#' + newTabId + ' button').attr('disabled', 'true');
        
        // Run migrate
        $.ajax( {
            url : 'lib/cmd.php',
            dataType : 'json',
            data : {
                cmd : 'rmigrate',
                tgt : tgts.val(),
                args : args,
                msg : 'out=migrateStatusBar' + inst + ';cmd=rmigrate;tgt=' + tgts.val()
            },

            success : updateStatusBar
        });
    });
    migrateForm.append(runBtn);

    // Append to discover tab
    tab.add(newTabId, 'Migrate', migrateForm, true);

    // Select new tab
    tab.select(newTabId);
};

/**
 * Load event log configuration page
 * 
 * @param node Source node to clone
 */
zvmPlugin.prototype.loadLogPage = function(node) {
    // Get nodes tab
    var tab = getNodesTab();
    var newTabId = node + 'LogsTab';

    // If there is no existing clone tab
    if (!$('#' + newTabId).length) {
        // Get table headers
        var tableId = $('#' + node).parents('table').attr('id');
        var headers = $('#' + tableId).parents('.dataTables_scroll').find('.dataTables_scrollHead thead tr:eq(0) th');
        var cols = new Array();
        for ( var i = 0; i < headers.length; i++) {
            var col = headers.eq(i).text();
            cols.push(col);
        }

        // Get hardware control point column
        var hcpCol = $.inArray('hcp', cols);

        // Get hardware control point
        var nodeRow = $('#' + node).parent().parent();
        var datatable = $('#' + getNodesTableId()).dataTable();
        var rowPos = datatable.fnGetPosition(nodeRow.get(0));
        var aData = datatable.fnGetData(rowPos);
        var hcp = aData[hcpCol];

        // Create status bar and hide it
        var statBarId = node + 'CloneStatusBar';
        var statBar = createStatusBar(statBarId).hide();

        // Create info bar
        var infoBar = createInfoBar('Retrieve, clear, or set options for event logs.');

        // Create clone form
        var logForm = $('<div class="form"></div>');
        logForm.append(statBar);
        logForm.append(infoBar);
        
        // Create VM fieldset
        var vmFS = $('<fieldset></fieldset>');
        var vmLegend = $('<legend>Virtual Machine</legend>');
        vmFS.append(vmLegend);
        logForm.append(vmFS);
        
        var vmAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
        vmFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/computer.png"></img></div>'));
        vmFS.append(vmAttr);
        
        // Create logs fieldset
        var logFS = $('<fieldset></fieldset>');
        var logLegend = $('<legend>Logs</legend>');
        logFS.append(logLegend);
        logForm.append(logFS);
        
        var logAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
        logFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/nodes/log.png"></img></div>'));
        logFS.append(logAttr);
        
        vmAttr.append('<div><label>Target node range:</label><input type="text" id="tgtNode" name="tgtNode" value="' + node + '" title="You must give a node or a node range. A node range must be given as: node1-node9 or node[1-9]."/></div>');
        logAttr.append('<div><label>Source log:</label><input type="text" name="srcLog" title="The log file to retrieve, clear, or set."/></div>');
        
        var optsLabel = $('<label>Options:</label>');    
        var optsList = $('<ul></ul>');
        logAttr.append(optsLabel);
        logAttr.append(optsList);
        
        // Create retrieve log checkbox
        var retrieveChkBox = $('<li><input type="checkbox" name="t"/></li>');
        optsList.append(retrieveChkBox);
        retrieveChkBox.append('Retrieve log');
        
        // Create log destination input
        var tgtLog = $('<li><label>Log destination:</label><input type="text" name="tgtLog"/></li>');
        tgtLog.hide();
        optsList.append(tgtLog);
        
        // Create set log checkbox
        var setChkBox = $('<li><input type="checkbox" name="o"/></li>');
        optsList.append(setChkBox);
        setChkBox.append('Set options');
        
        // Create log options input
        var logOpt = $('<li><label style="width: 80px; vertical-align: top;">Log options:</label><textarea name="logOpt"></textarea></li>');
        logOpt.hide();
        optsList.append(logOpt);
        
        // Create clear log checkbox
        var clearChkBox = $('<li><input type="checkbox" name="c"/></li>');
        optsList.append(clearChkBox);
        clearChkBox.append('Clear log');
        
        retrieveChkBox.bind('click', function(event) {
        	tgtLog.toggle();
        });
        
        setChkBox.find('input').bind('click', function(event) {
        	logOpt.toggle();
        });

        // Generate tooltips
        logForm.find('div input[title]').tooltip({
            position : "center right",
            offset : [ -2, 10 ],
            effect : "fade",
            opacity : 0.7,
            predelay: 800,
            events : {
                def : "mouseover,mouseout",
                input : "mouseover,mouseout",
                widget : "focus mouseover,blur mouseout",
                tooltip : "mouseover,mouseout"
            }
        });
        
        /**
         * Run node
         */
        var runBtn = createButton('Run');
        runBtn.bind('click', function(event) {
            // Remove any warning messages
            $(this).parent().parent().find('.ui-state-error').remove();
            
            var ready = true;
            var errMsg = '';

            // Verify required inputs are provided
            var inputs = $('#' + newTabId + ' input');
            for ( var i = 0; i < inputs.length; i++) {
                if (!inputs.eq(i).val()
                    && inputs.eq(i).attr('name') != 'tgtLog'
                    && inputs.eq(i).attr('name') != 'logOpt') {
                    inputs.eq(i).css('border', 'solid #FF0000 1px');
                    ready = false;
                } else {
                    inputs.eq(i).css('border', 'solid #BDBDBD 1px');
                }
            }

            // Write error message
            if (!ready) {
                errMsg = errMsg + 'Please provide a value for each missing field.<br>';
            }

            var tgts = $('#' + newTabId + ' input[name=tgtNode]').val();
            var srcLog = $('#' + newTabId + ' input[name=srcLog]').val();
            
            var chkBoxes = $("#" + newTabId + " input[type='checkbox']:checked");
            var optStr = '-s;' + srcLog + ';';
            var opt;
            for ( var i = 0; i < chkBoxes.length; i++) {
                opt = chkBoxes.eq(i).attr('name');
                optStr += '-' + opt;
                
                // If it is the retrieve log
                if (opt == 't') {
                    // Append log destination
                    optStr += ';' + $('#' + newTabId + ' input[name=tgtLog]').val();
                }
                
                // If it is set options
                if (opt == 'o') {
                    // Append options
                    optStr += ';' + $('#' + newTabId + ' textarea[name=logOpt]').val();
                }
                
                // Append ; to end of string
                if (i < (chkBoxes.length - 1)) {
                    optStr += ';';
                }
            }

            // If a value is given for every input
            if (ready) {
                // Do not disable all inputs
                //var inputs = $('#' + newTabId + ' input');
                //inputs.attr('disabled', 'disabled');
                
                /**
                 * (1) Retrieve, clear, or set options for event logs
                 */
                $.ajax( {
                    url : 'lib/cmd.php',
                    dataType : 'json',
                    data : {
                        cmd : 'reventlog',
                        tgt : tgts,
                        args : optStr,
                        msg : 'out=' + statBarId + ';cmd=reventlog;tgt=' + tgts
                    },

                    success : updateStatusBar
                });

                // Create loader
                $('#' + statBarId).find('div').append(createLoader());
                $('#' + statBarId).show();

                // Do not disable run button
                //$(this).attr('disabled', 'true');
            } else {
                // Show warning message
                var warn = createWarnBar(errMsg);
                warn.prependTo($(this).parent().parent());
            }
        });
        logForm.append(runBtn);

        // Add clone tab
        tab.add(newTabId, 'Logs', logForm, true);
    }

    tab.select(newTabId);
};