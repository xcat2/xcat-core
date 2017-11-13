/**
 * Create nodes datatable for a given group
 *
 * @param group Group name
 * @param outId Division ID to append datatable
 * @return Nodes datatable
 */
function createNodesDatatable(group, outId) {
    // Get group nodes
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'lsdef',
            tgt : '',
            args : group,
            msg : outId
        },

        /**
         * Create nodes datatable
         *
         * @param data Data returned from HTTP request
         */
        success : function(data) {
            data = decodeRsp(data);
            // Data returned
            var rsp = data.rsp;

            // Get output ID
            var outId = data.msg;
            // Get datatable ID
            var dTableId = outId.replace('DIV', '');

            // Node attributes hash
            var attrs = new Object();
            // Node attributes
            var headers = new Object();

            // Clear nodes datatable division
            $('#' + outId).empty();

            // Create nodes datatable
            var node = null;
            var args;
            for ( var i in rsp) {
                // Get node
                var pos = rsp[i].indexOf('Object name:');
                if (pos > -1) {
                    var temp = rsp[i].split(': ');
                    node = jQuery.trim(temp[1]);

                    // Create a hash for the node attributes
                    attrs[node] = new Object();
                    i++;
                }

                // Get key and value
                args = rsp[i].split('=');
                var key = jQuery.trim(args[0]);
                var val = jQuery.trim(args[1]);

                // Create hash table
                attrs[node][key] = val;
                headers[key] = 1;
            }

            // Sort headers
            var sorted = new Array();
            for ( var key in headers) {
            	// Do not put in status or comments
            	if (key.indexOf("status") < 0 && key.indexOf("usercomment") < 0) {
            		sorted.push(key);
            	}
            }
            sorted.sort();

            // Add column for check box and node
            sorted.unshift('<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">', 'node');

            // Create nodes datatable
            var dTable = new DataTable(dTableId);
            dTable.init(sorted);

            // Go through each node
            for ( var node in attrs) {
                // Create a row
                var row = new Array();
                // Create a check box
                var checkBx = '<input type="checkbox" name="' + node + '"/>';
                row.push(checkBx, node);

                // Go through each header
                for ( var i = 2; i < sorted.length; i++) {
                    // Add node attributes to the row
                    var key = sorted[i];
                    var val = attrs[node][key];
                    if (val) {
                        row.push(val);
                    } else {
                        row.push('');
                    }
                }

                // Add row to table
                dTable.add(row);
            }

            $('#' + outId).append(dTable.object());
            $('#' + dTableId).dataTable({
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

            // Fix table styling
            $('#' + dTableId + '_wrapper .dataTables_filter label').css('width', '250px');
        } // End of function(data)
    });
}

/**
 * Create provision existing node division
 *
 * @param plugin Plugin name to create division for
 * @param inst Provision tab instance
 * @return Provision existing node division
 */
function createProvisionExisting(plugin, inst) {
    // Create provision existing division and hide it
    var provExisting = $('<div></div>').hide();

    // Create group input
    var group = $('<div></div>');
    var groupLabel = $('<label>Group:</label>');
    group.append(groupLabel);

    // Turn on auto complete for group
    var dTableDivId = plugin + 'NodesDatatableDIV' + inst;    // Division ID where nodes datatable will be appended
    var groupNames = $.cookie('xcat_groups');
    if (groupNames) {
        // Split group names into an array
        var tmp = groupNames.split(',');

        // Create drop down for groups
        var groupSelect = $('<select></select>');
        groupSelect.append('<option></option>');
        for ( var i in tmp) {
            // Add group into drop down
            var opt = $('<option value="' + tmp[i] + '">' + tmp[i] + '</option>');
            groupSelect.append(opt);
        }
        group.append(groupSelect);

        // Create node datatable
        groupSelect.change(function() {
            // Get group selected
            var thisGroup = $(this).val();
            // If a valid group is selected
            if (thisGroup) {
                createNodesDatatable(thisGroup, dTableDivId);
            } // End of if (thisGroup)
        });
    } else {
        // If no groups are cookied
        var groupInput = $('<input type="text" name="group"/>');
        group.append(groupInput);
    }
    provExisting.append(group);

    // Create node input
    var node = $('<div></div>');
    var nodeLabel = $('<label>Nodes:</label>');
    var nodeDatatable = $('<div class="indent" id="' + dTableDivId + '"><p>Select a group to view its nodes</p></div>');
    node.append(nodeLabel);
    node.append(nodeDatatable);
    provExisting.append(node);

    // Create boot method drop down
    var method = $('<div></div>');
    var methodLabel = $('<label>Boot method:</label>');
    var methodSelect = $('<select id="bootMethod" name="bootMethod"></select>');
    methodSelect.append('<option value="boot">boot</option>'
        + '<option value="install">install</option>'
        + '<option value="iscsiboot">iscsiboot</option>'
        + '<option value="netboot">netboot</option>'
        + '<option value="statelite">statelite</option>'
    );
    method.append(methodLabel);
    method.append(methodSelect);
    provExisting.append(method);

    // Create boot type drop down
    var type = $('<div></div>');
    var typeLabel = $('<label>Boot type:</label>');
    var typeSelect = $('<select id="bootType" name="bootType"></select>');
    typeSelect.append('<option value="pxe">pxe</option>'
        + '<option value="iscsiboot">yaboot</option>'
        + '<option value="zvm">zvm</option>'
    );
    type.append(typeLabel);
    type.append(typeSelect);
    provExisting.append(type);

    // Create operating system input
    var os = $('<div></div>');
    var osLabel = $('<label>Operating system:</label>');
    var osInput = $('<input type="text" name="os"/>');
    osInput.one('focus', function() {
        var tmp = $.cookie('xcat_osvers');
        if (tmp) {
            // Turn on auto complete
            $(this).autocomplete({
                source: tmp.split(',')
            });
        }
    });
    os.append(osLabel);
    os.append(osInput);
    provExisting.append(os);

    // Create architecture input
    var arch = $('<div></div>');
    var archLabel = $('<label>Architecture:</label>');
    var archInput = $('<input type="text" name="arch"/>');
    archInput.one('focus', function() {
        var tmp = $.cookie('xcat_osarchs');
        if (tmp) {
            // Turn on auto complete
            $(this).autocomplete({
                source: tmp.split(',')
            });
        }
    });
    arch.append(archLabel);
    arch.append(archInput);
    provExisting.append(arch);

    // Create profile input
    var profile = $('<div></div>');
    var profileLabel = $('<label>Profile:</label>');
    var profileInput = $('<input type="text" name="profile"/>');
    profileInput.one('focus', function() {
        var tmp = $.cookie('xcat_profiles');
        if (tmp) {
            // Turn on auto complete
            $(this).autocomplete({
                source: tmp.split(',')
            });
        }
    });
    profile.append(profileLabel);
    profile.append(profileInput);
    provExisting.append(profile);

    /**
     * Provision existing
     */
    var provisionBtn = createButton('Provision');
    provisionBtn.bind('click', function(event) {
        // TODO Insert provision code here
        openDialog('info', 'Not yet supported');
    });
    provExisting.append(provisionBtn);

    return provExisting;
}

/**
 * Create provision new node division
 *
 * @param inst Provision tab instance
 * @return Provision new node division
 */
function createProvisionNew(plugin, inst) {
    // Create provision new node division
    var provNew = $('<div></div>');

    // Create node input
    var nodeName = $('<div><label>Node:</label><input type="text" name="nodeName"/></div>');
    provNew.append(nodeName);

    // Create group input
    var group = $('<div></div>');
    var groupLabel = $('<label>Group:</label>');
    var groupInput = $('<input type="text" name="group"/>');
    groupInput.one('focus', function() {
        var groupNames = $.cookie('xcat_groups');
        if (groupNames) {
            // Turn on auto complete
            $(this).autocomplete({
                source: groupNames.split(',')
            });
        }
    });
    group.append(groupLabel);
    group.append(groupInput);
    provNew.append(group);

    // Create boot method drop down
    var method = $('<div></div>');
    var methodLabel = $('<label>Boot method:</label>');
    var methodSelect = $('<select id="bootMethod" name="bootMethod"></select>');
    methodSelect.append('<option value="boot">boot</option>'
        + '<option value="install">install</option>'
        + '<option value="iscsiboot">iscsiboot</option>'
        + '<option value="netboot">netboot</option>'
        + '<option value="statelite">statelite</option>'
    );
    method.append(methodLabel);
    method.append(methodSelect);
    provNew.append(method);

    // Create boot type drop down
    var type = $('<div></div>');
    var typeLabel = $('<label>Boot type:</label>');
    var typeSelect = $('<select id="bootType" name="bootType"></select>');
    typeSelect.append('<option value="install">pxe</option>'
        + '<option value="iscsiboot">yaboot</option>'
        + '<option value="zvm">zvm</option>'
    );
    type.append(typeLabel);
    type.append(typeSelect);
    provNew.append(type);

    // Create operating system input
    var os = $('<div></div>');
    var osLabel = $('<label>Operating system:</label>');
    var osInput = $('<input type="text" name="os"/>');
    osInput.one('focus', function() {
        var tmp = $.cookie('xcat_osvers');
        if (tmp) {
            // Turn on auto complete
            $(this).autocomplete({
                source: tmp.split(',')
            });
        }
    });
    os.append(osLabel);
    os.append(osInput);
    provNew.append(os);

    // Create architecture input
    var arch = $('<div></div>');
    var archLabel = $('<label>Architecture:</label>');
    var archInput = $('<input type="text" name="arch"/>');
    archInput.one('focus', function() {
        var tmp = $.cookie('xcat_osarchs');
        if (tmp) {
            // Turn on auto complete
            $(this).autocomplete({
                source: tmp.split(',')
            });
        }
    });
    arch.append(archLabel);
    arch.append(archInput);
    provNew.append(arch);

    // Create profile input
    var profile = $('<div></div>');
    var profileLabel = $('<label>Profile:</label>');
    var profileInput = $('<input type="text" name="profile"/>');
    profileInput.one('focus', function() {
        var tmp = $.cookie('xcat_profiles');
        if (tmp) {
            // Turn on auto complete
            $(this).autocomplete({
                source: tmp.split(',')
            });
        }
    });
    profile.append(profileLabel);
    profile.append(profileInput);
    provNew.append(profile);

    /**
     * Provision new node
     */
    var provisionBtn = createButton('Provision');
    provisionBtn.bind('click', function(event) {
        // TODO Insert provision code here
        openDialog('info', 'Not yet supported');
    });
    provNew.append(provisionBtn);

    return provNew;
}

/**
 * Create section to provision node
 *
 * @param plugin Plugin name
 * @param container Container to hold provision section
 */
function appendProvisionSection(plugin, container) {
    // Get provision tab ID
    var tabId = container.parents('.tab').attr('id');

    if (plugin == 'quick')
        appendProvision4Url(container); // For provisioning based on argmunents found in URL
    else
        appendProvision4NoUrl(plugin, container);

    // Add provision button
    var provisionBtn = createButton('Provision');
    provisionBtn.bind('click', function(){
        provisionNode(tabId);
    });
    container.append(provisionBtn);

    // Bind image select to change event
    container.find('select[name=image]').bind('change', function() {
        createAdvancedOptions($(this).val(), tabId);
    });

    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'lsdef',
            tgt : '',
            args : '-t;osimage',
            msg : tabId
        },

        success : function(data){
            data = decodeRsp(data);
            var tabId = data.msg;
            var i = 0;
            var imageName = 0;
            var position = 0;
            if (!data.rsp.length) {
                $('#' + tabId).prepend(createWarnBar('Please run copycds and genimage in provision page before continuing!'));
                return;
            }

            for (i in data.rsp) {
                imageName = data.rsp[i];
                position = imageName.indexOf(' ');
                imageName = imageName.substr(0, position);

                $('#' + tabId + ' select[name=image]').append($('<option value="' + imageName + '">' + imageName + '</option>'));
            }

            // Trigger select change event
            $('#' + tabId + ' select[name=image]').trigger('change');
            // Show provision button
            $('#' + tabId + ' button').show();
        }
    });
}

/**
 * Create provision node section using URL
 *
 * @param container Container to hold provision section
 * @returns Nothing
 */
function appendProvision4Url(container){
    // Create node fieldset
    var nodeFS = $('<fieldset></fieldset>');
    var nodeLegend = $('<legend>Node</legend>');
    nodeFS.append(nodeLegend);
    container.append(nodeFS);

    var nodeAttr = $('<div style="display: inline-table; vertical-align: middle; width: 85%; margin-left: 10px;"></div>');
    nodeFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/computer.png"></img></div>'));
    nodeFS.append(nodeAttr);

    // Create image fieldset
    var imgFS = $('<fieldset></fieldset>');
    var imgLegend = $('<legend>Image</legend>');
    imgFS.append(imgLegend);
    container.append(imgFS);

    var imgAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    imgFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/operating_system.png"></img></div>'));
    imgFS.append(imgAttr);

    var query = window.location.search;
    var args = query.substr(1).split('&');
    var parms = new Object();
    var tmp;

    // Turn URL arguments into hash array
    for (var i = 0; i < args.length; i++) {
        tmp = args[i].split('=');
        parms[tmp[0]] = tmp[1];
    }

    var master = '';
    if (parms['master'])
        master = parms['master'];

    var nfsserver = '';
    if (parms['nfsserver'])
        nfsserver = parms['nfsserver'];

    var tftpserver = '';
    if (parms['tftpserver'])
        tftpserver = parms['tftpserver'];

    nodeAttr.append('<div><label>Node:</label><input type="text" disabled="disabled" name="node" value="' + parms['nodes'] + '"></div>');

    imgAttr.append('<div><label>Architecture:</label><input type="text" disabled="disabled" name="arch" value="' + parms['arch'] + '"></div>');
    imgAttr.append('<div><label>Image name:</label><select name="image"></select></div>');
    imgAttr.append( '<div><label>Install NIC:</label><input type="text" name="installNic"/></div>');
    imgAttr.append('<div><label>Primary NIC:</label><input type="text" name="primaryNic"/></div>');
    imgAttr.append('<div><label>xCAT master:</label><input type="text" name="xcatMaster" value="' + master + '"></div>');
    imgAttr.append('<div><label>TFTP server:</label><input type="text" name="tftpServer" value="' + tftpserver + '"></div>');
    imgAttr.append('<div><label>NFS server:</label><input type="text" name="nfsServer" value="' + nfsserver + '"></div>');

    return;
}

/**
 * Create section to provision node using no URL
 *
 * @param plugin Create provision section for given plugin
 * @param container Container to hold provision section
 */
function appendProvision4NoUrl(plugin, container){
    // Get provision tab ID
    var tabId = container.parents('.tab').attr('id');

    // Create node fieldset
    var nodeFS = $('<fieldset></fieldset>');
    var nodeLegend = $('<legend>Node</legend>');
    nodeFS.append(nodeLegend);
    container.append(nodeFS);

    var nodeAttr = $('<div style="display: inline-table; vertical-align: middle; width: 85%; margin-left: 10px;"></div>');
    nodeFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/computer.png"></img></div>'));
    nodeFS.append(nodeAttr);

    // Create image fieldset
    var imgFS = $('<fieldset></fieldset>');
    var imgLegend = $('<legend>Image</legend>');
    imgFS.append(imgLegend);
    container.append(imgFS);

    var imgAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    imgFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/operating_system.png"></img></div>'));
    imgFS.append(imgAttr);

    // Select group name
    var group = $('<div></div>').append('<label>Group:</label>');
    var groupSelect = $('<select name="group"></select>');
    group.append(groupSelect);
    var groupNames = $.cookie('xcat_groups');
    if (groupNames) {
        var tmp = groupNames.split(',');
        groupSelect.append('<option value=""></option>'); // Append empty group name
        for (var i in tmp)
            groupSelect.append('<option value="' + tmp[i] + '">' + tmp[i] + '</option>');
    }
    nodeAttr.append(group);

    // Select node from table
    var nodes = $('<div><label style="vertical-align: top;">Nodes:</label></div>');
    var nodesTable = $('<div id="nodesTable" style="display: inline-block; max-width: 800px;"><p>Select a group to view its nodes</p></div>');
    nodes.append(nodesTable);
    nodeAttr.append(nodes);

    // Select architecture
    var arch = $('<div></div>').append('<label>Architecture:</label>');
    var archName = $.cookie('xcat_osarchs');
    if (archName) {
        var archSelect = $('<select name="arch"></select>');
        arch.append(archSelect);

        var tmp = archName.split(',');
        for (var i in tmp)
            archSelect.append('<option value="' + tmp[i] + '">' + tmp[i] + '</option>');
    } else {
        arch.append('<input type="text" name="arch"/>');
    }
    imgAttr.append(arch);

    imgAttr.append('<div><label>Image name:</label><select name="image"></select></div>');
    imgAttr.append('<div><label>Install NIC:</label><input type="text" name="installNic"/></div>');
    imgAttr.append('<div><label>Primary NIC:</label><input type="text" name="primaryNic"/></div>');
    imgAttr.append('<div><label>xCAT master:</label><input type="text" name="xcatMaster"/></div>');
    imgAttr.append('<div><label>TFTP server:</label><input type="text" name="tftpServer"/></div>');
    imgAttr.append('<div><label>NFS server:</label><input type="text" name=nfsServer"/></div>');

    // When a group is selected, show the nodes belonging to that group
    groupSelect.bind('change', function() {
        var nodesTableId = '#' + tabId + ' #nodesTable';
        $(nodesTableId).append(createLoader());
        createNodesTable($(this).val(), nodesTableId);
    });

    return;
}

/**
 * Provision node
 *
 * @param tabId Provision tab ID
 */
function provisionNode(tabId) {
    var errorMessage = "";
    var args = new Array();
    var node = "";

    // Delete any existing warnings
    $('#' + tabId + ' .ui-state-error').remove();

    // Go through each input
    $('#' + tabId + ' input[type!="checkbox"]').each(function() {
        if (!$(this).val()) {
            errorMessage = 'Please provide a value for each missing field!';
            return false;
        } else {
            args.push($(this).val());
        }
    });

    // Do not continue if error was found
    if (errorMessage) {
        $('#' + tabId).prepend(createWarnBar(errorMessage));
        return;
    }

    // If jumped from nodes page, get node name
    if (tabId == 'quick') {
        node = args.shift();
    } else {
        // Select platform, get node names from table checkbox
        args.unshift($('#' + tabId + ' input[name=arch]').val());
        node = getCheckedByObj($('#' + tabId + ' #nodesTable'));
    }

    // Do not continue if a node is not given
    if (!node) {
        $('#' + tabId).prepend(createWarnBar('Please select a node!'));
        return;
    }

    var software = getCheckedByObj($('#' + tabId + ' #advanced'));
    var imageName = $('#' + tabId + ' select[name=image]').val();
    var provision = args.join(',');

    var url = 'lib/cmd.php?cmd=webrun&tgt=&args=provision;' +
        node + ';' + imageName + ';' + provision + ';' + software + '&msg=&opts=flush';
    $('#' + tabId).prepend(createIFrame(url));
}

/**
 * Create advance option
 *
 * @param image Image name
 * @param outId Output area ID
 */
function createAdvancedOptions(image, outId) {
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'lsdef',
            tgt : '',
            args : '-t;osimage;' + image + ';-i;osname,provmethod',
            msg : outId
        },

        success : function(data) {
            data = decodeRsp(data);
            var outId = data.msg;
            var osName = '';
            var provMethod = '';
            var tmpStr = '';
            var position = 0;

            for (var i = 0; i < data.rsp.length; i++) {
                tmpStr = data.rsp[i];
                if (tmpStr.indexOf('osname') != -1) {
                    position = tmpStr.indexOf('=');
                    osName = tmpStr.substr(position + 1);
                }

                if (tmpStr.indexOf('provmethod') != -1) {
                    position = tmpStr.indexOf('=');
                    provMethod = tmpStr.substr(position + 1);
                }
            }

            $('#' + outId + ' #advanced').remove();
            if (osName.toLowerCase() == 'aix')
                return;

            if (provMethod == 'install') {
                // Create advanced fieldset
                var advancedFS = $('<fieldset id="advanced"></fieldset>').append($('<legend>Advanced</legend>'));
                $('#' + outId + ' div.form fieldset:eq(1)').after(advancedFS);

                advancedFS.append('<div><input type="checkbox" checked="checked" name="ganglia">Install Ganglia monitoring</div>');
            }
        }
    });
}

/**
 * Create nodes table
 *
 * @param group Group name
 * @param outId Output section ID
 */
function createNodesTable(group, outId) {
    // Get group nodes
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'nodels',
            tgt : group,
            args : '',
            msg : outId
        },

        success : function(data) {
            data = decodeRsp(data);
            var outId = $(data.msg);
            var nodes = data.rsp;

            // Create table to hold nodes
            var nTable = $('<table></table>');
            var tHead = $('<thead class="ui-widget-header"> <th><input type="checkbox" onclick="selectAll4Table(event, $(this))"></th> <th>Node</th> </thead>');
            nTable.append(tHead);
            var tBody = $('<tbody></tbody>');
            nTable.append(tBody);

            for (var i in nodes) {
                var node = nodes[i][0];

                // Go to next node if there is nothing here
                if (!node)
                    continue;
                // Insert node into table
                tBody.append('<tr><td><input type="checkbox" name="' + node + '"/></td><td>' + node + '</td></tr>');
            }

            outId.empty().append(nTable);

            if (nodes.length > 10)
                outId.css('height', '300px');
            else
                outId.css('height', 'auto');
        }
    });
}

/**
 * Get select element names
 *
 * @param obj Object to get selected element names
 * @return Nodes name seperate by a comma
 */
function getCheckedByObj(obj) {
    var str = '';

    // Get nodes that were checked
    obj.find('input:checked').each(function() {
        if ($(this).attr('name')) {
            str += $(this).attr('name') + ',';
        }
    });

    if (str) {
        str = str.substr(0, str.length - 1);
    }

    return str;
}

/**
 * Select all checkboxes in the table
 *
 * @param event Event on element
 * @param obj Object triggering event
 */
function selectAll4Table(event, obj) {
    // Get datatable ID
    // This will ascend from <input> <td> <tr> <thead> <table>
    var tableObj = obj.parents('table').find('tbody');
    var status = obj.attr('checked');
    tableObj.find(' :checkbox').attr('checked', status);
    event.stopPropagation();
}