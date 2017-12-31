/**
 * Global variables
 */
var xcatMonTableId = "xcatMonSettingTable";

/**
 * Load xCAT monitoring
 */
function loadXcatMon() {
    // Find xCAT monitoring tab
    var xcatMonTab = $('#xcatmon');
    xcatMonTab.append("<div id= xcatmonTable></div>");

    // Show content of monsetting table
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'tabdump',
            tgt : '',
            args : 'monsetting',
            msg : ''
        },
        success : function(data) {
            data = decodeRsp(data);
            loadXcatMonSetting(data);
        }
    });
}

function loadXcatMonSetting(data) {
    var apps = ""; // Contains the xcatmon config
    var rsp = data.rsp;
    if (!rsp.length)
    	return;

    var apps_flag = 0;
    var ping; // xcatmon ping interval
    var ping_flag = 0;

    // Create an info bar
    var infoBar = createInfoBar('Click on a cell to edit. Click outside the table to write to the cell. Once you are finished configuring the xCAT monitor, click on Apply.');
    $('#xcatmonTable').append(infoBar);

    // Create xcatmon table
    var xcatmonTable = new DataTable(xcatMonTableId);

    // Create datatable
    var dTable;

    // Create table header
    var header = rsp[0].split(",");
    header.splice(3, 2);
    header.splice(0, 1);
    header[0] = "App Name";
    header[1] = "Configure";
    header.push('<input type="checkbox" onclick="selectAllCheckbox(event,$(this))">');
    header.unshift('');
    xcatmonTable.init(header);

    // Create container for original table contents
    var origCont = new Array();
    origCont[0] = header; // Table headers

    // Create container for new contents to use later updating monsetting table
    var newCont = new Object();
    newCont[0] = rsp[0].split(","); // Table headers

    // Create container for other monsetting lines
    var otherCont = new Array();

    $('#xcatmonTable').append(xcatmonTable.object());
    var m = 1; // Count for origCont
    var n = 0;
    for ( var i = 1; i < rsp.length; i++) {
        var pos = rsp[i].indexOf("xcatmon"); // Only check xcatmon setting
        if (pos == 1) {
            if ((rsp[i].indexOf("apps") == -1) && (rsp[i].indexOf("ping") == -1)) {
                var cols = rsp[i].split(',');
                for ( var j = 0; j < cols.length; j++) {
                    if (cols[j].count('"') % 2 == 1) {
                        while (cols[j].count('"') % 2 == 1) {
                            cols[j] = cols[j] + "," + cols[j + 1];
                            cols.splice(j + 1, 1);
                        }
                    }
                    cols[j] = cols[j].replace(new RegExp('"', 'g'), '');
                }

                cols.splice(3, 2);
                cols.splice(0, 1);
                cols.push('<input type="checkbox" name="' + cols[0] + '" title="Checking this box will add/remove the app from the configured app value"/>');
                cols.unshift('<span class="ui-icon ui-icon-close" onclick="deleteXcatMonRow(this)"></span>');

                // Add column to table
                xcatmonTable.add(cols);
                origCont[m++] = cols;
            } else {
                if (!apps_flag) { // Check the apps setting
                    if (rsp[i].indexOf("apps") > -1) {
                        apps = rsp[i].split(',');

                        for ( var j = 0; j < apps.length; j++) {
                            if (apps[j].count('"') % 2 == 1) {
                                while (apps[j].count('"') % 2 == 1) {
                                    apps[j] = apps[j] + "," + apps[j + 1];
                                    apps.splice(j + 1, 1);
                                }
                            }
                            apps[j] = apps[j].replace(new RegExp('"', 'g'), '');
                        }

                        apps_flag = 1; // Set the flag to 1 to avoid this subroute
                    }
                }

                // Get into the ping settings
                if (!ping_flag) {
                    // Check the ping interval
                    if (rsp[i].indexOf("ping-interval") > -1) {
                        ping = rsp[i].split(',');
                        for ( var j = 0; j < ping.length; j++) {
                            if (ping[j].count('"') % 2 == 1) {
                                while (ping[j].count('"') % 2 == 1) {
                                    ping[j] = ping[j] + "," + ping[j + 1];
                                    ping.splice(j + 1, 1);
                                }
                            }
                            ping[j] = ping[j].replace((new RegExp('"', 'g')),
                                    '');
                        }
                        ping_flag = 1;
                    }
                }
            }
        } else if (pos != 1) {
            // The other monitor in the monsetting table
            var otherCols = rsp[i].split(',');
            for ( var k = 0; k < otherCols.length; k++) {
                if (otherCols[k].count('"') % 2 == 1) {
                    while (otherCols[k].count('"') % 2 == 1) {
                        otherCols[k] = otherCols[k] + "," + otherCols[k + 1];
                        otherCols.splice(k + 1, 1);
                    }
                }
                otherCols[k] = otherCols[k].replace(new RegExp('"', 'g'), '');
            }

            otherCont[n++] = otherCols;

        }
    }
    // If app is not in the monsetting table, then create default apps row
    if (!apps_flag) {
        apps = rsp[0].split(',');
        apps[0] = "xcatmon";
        apps[1] = "apps";
        apps[2] = "";
        apps[3] = "";
        apps[4] = "";
    }

    // If the ping interval is not in the monsetting table, then create the
    // default ping-interval
    if (!ping_flag) {
        ping = rsp[0].split(',');
        ping[0] = "xcatmon";
        ping[1] = "ping-interval";

        // Set default ping-interval setting to 5
        ping[2] = "5";
        ping[3] = "";
        ping[4] = "";
    }

    // Set checkbox to be true
    var checked = apps[2].split(',');
    for ( var i = 0; i < checked.length; i++) {
        $("input:checkbox[name=" + checked[i] + "]").attr('checked', true);
        for ( var j = 0; j < origCont.length; j++) {
            if (origCont[j][1] == checked[i]) {
                origCont[j].splice(3, 1);
                origCont[j].push('<input type="checkbox" name="' + origCont[j][1] + '" title="Check this checkbox to add/remove the app from the configured app value." checked=true/>');
            }
        }

    }
    $(":checkbox").tooltip();

    // Make the table editable
    $('#' + xcatMonTableId + ' td:not(td:nth-child(1),td:last-child)').editable(function(value, settings) {
        var colPos = this.cellIndex;
        var rowPos = dTable.fnGetPosition(this.parentNode);
        dTable.fnUpdate(value, rowPos, colPos);
        return (value);
    }, {
        onblur : 'submit',
        type : 'textarea',
        placeholder : ' ',
        height : '30px'
    });

    // Save datatable
    dTable = $('#' + xcatMonTableId).dataTable({
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

    // Create action bar
    var actionBar = $('<div class="actionBar"></div>');
    var addRowLnk = $('<a>Add row</a>');
    addRowLnk.bind('click', function(event) {
        // Create container for new row
        var row = new Array();

        // Add delete button to row
        row.push('<span class="ui-icon ui-icon-close" onclick="deleteXcatMonRow(this)"></span>');
        for ( var i = 0; i < header.length - 2; i++)
            row.push('');

        // Add checkbox
        row.push('<input type="checkbox" name="' + row[2] + '" title="Checking this checkbox will add/remove the app from the configured apps value"/>');
        // Get the datatable of the table
        var dTable = $('#' + xcatMonTableId).dataTable();
        // Add the new row to the datatable
        dTable.fnAddData(row);

        // make the datatable editable
        $(":checkbox[title]").tooltip();
        $('#' + xcatMonTableId + ' td:not(td:nth-child(1),td:last-child)').editable(function(value, settings) {
            var colPos = this.cellIndex;
            var rowPos = dTable
                    .fnGetPosition(this.parentNode);
            dTable.fnUpdate(value, rowPos,
                    colPos);
            return (value);
        }, {
            onblur : 'submit',
            type : 'textarea',
            placeholder : ' ',
            height : '30px'
        });
    });

    // Create apply button to store the contents of the table to the monsetting table
    var applyLnk = $('<a>Apply</a>');
    applyLnk.bind('click', function(event) {
        // Get the datatable
        var dTable = $('#' + xcatMonTableId).dataTable();
        // Get datatable rows
        var dRows = dTable.fnGetNodes();
        var count = 0;

        // Create a new container for the apps value
        var appValue = '';
        var tableName = 'monsetting';
        var closeBtn = createButton('close');

        // Get the row contents
        for ( var i = 0; i < dRows.length; i++) {
            if (dRows[i]) {
                // Get the row columns
                var cols = dRows[i].childNodes;
                // Create a container for the new columns
                var vals = new Array();

                for ( var j = 1; j < cols.length - 1; j++) {
                    var val = cols.item(j).firstChild.nodeValue;
                    if (val == ' ')
                        vals[j - 1] = '';
                    else
                        vals[j - 1] = val;
                }

                var vals_orig = new Array();
                // Copy data from vals to vals_orig
                for ( var p = 0; p < 2; p++) {
                    var val = vals[p];
                    vals_orig[p] = val;
                }

                vals.push('');
                vals.push('');
                vals.unshift('xcatmon');

                // Stored new column to newCont
                newCont[i + 1] = vals;

                if (cols.item(cols.length - 1).firstChild.checked) {
                    vals_orig.push('<input type="checkbox" name="' + vals_orig[0] + '" title="Checking this checkbox will add/remove the app from the configured apps value" checked=true/>');
                } else {
                    vals_orig.push('<input type="checkbox" name="' + vals_orig[0] + '" title="Checking this checkbox will add/remove the app from the configured apps value"/>');
                }

                // Add delete button to row
                vals_orig.unshift('<span class="ui-icon ui-icon-close" onclick="deleteXcatMonRow(this)"></span>');
                // Add row to origCont
                origCont[i + 1] = vals_orig;
                count = i + 1;

                // Check checkbox for every row when merging the app name with the apps values
                if (cols.item(cols.length - 1).firstChild.checked)
                    appValue = appValue.concat(cols.item(2).firstChild.nodeValue + ",");
            }
        }

        count++;

        // Delete the last comma of the apps value
        appValue = appValue.substring(0, (appValue.length - 1));
        apps[2] = appValue;

        newCont[count++] = apps;
        newCont[count++] = ping;

        // Add to other monitor settings
        for ( var j = 0; j < otherCont.length; j++) {
            newCont[count++] = otherCont[j];
        }

        // Create save dialog
        var dialogSave = $('<div id="saveDialog" align="center">Saving configuration</div>');
        dialogSave.append(createLoader());

        $('#xcatmon').append(dialogSave);
        $("#saveDialog").dialog({
            modal : true
        });

        $('.ui-dialog-titlebar-close').hide();
        $.ajax({
            type : 'POST',
            url : 'lib/tabRestore.php',
            dataType : 'json',
            data : {
                table : tableName,
                cont : newCont
            },
            success : function(data) {
                // do not put in until tabRestore.php has been updated: data = decodeRsp(data);
                // empty the dialog.add the close button
                $("#saveDialog").empty().append('<p>Configuration saved!</p>');
                $("#saveDialog").append(closeBtn);
            }
        });

        // Close button
        closeBtn.bind('click', function(event) {
            $("#saveDialog").dialog("destroy");
            $("#saveDialog").remove();
        });

        // Clear the newCont
        newCont = null;
        newCont = new Object();
        newCont[0] = rsp[0].split(",");
    });

    var cancelLnk = $('<a>Cancel</a>');
    cancelLnk.bind('click', function(event) {
        // Get the datatable for the page
        var dTable = $('#' + xcatMonTableId).dataTable();

        // Clear the datatable
        dTable.fnClearTable();

        // Add the contents of origCont to the datatable
        for ( var i = 1; i < origCont.length; i++)
            dTable.fnAddData(origCont[i], true);

        $(":checkbox[title]").tooltip();
        $('#' + xcatMonTableId + ' td:not(td:nth-child(1),td:last-child)').editable(function(value, settings) {
            var colPos = this.cellIndex;
            var rowPos = dTable.fnGetPosition(this.parentNode);
            dTable.fnUpdate(value, rowPos, colPos);
            return (value);
        }, {
            onblur : 'submit',
            type : 'textarea',
            placeholder : ' ',
            height : '30px'
        });
    });

    // Create actions menu
    var actionsLnk = '<a>Actions</a>';
    var actsMenu = createMenu([ addRowLnk, applyLnk, cancelLnk ]);
    var actionsMenu = createMenu([ [ actionsLnk, actsMenu ] ]);
    actionsMenu.superfish();
    actionsMenu.css('display', 'inline-block');
    actionBar.append(actionsMenu);

    // Create a division to hold actions menu
    var menuDiv = $('<div id="' + xcatMonTableId + '_menuDiv" class="menuDiv"></div>');
    $('#' + xcatMonTableId + '_wrapper').prepend(menuDiv);
    menuDiv.append(actionBar);
    $('#' + xcatMonTableId + '_filter').appendTo(menuDiv);
}

/**
 * Delete a row from the table
 */
function deleteXcatMonRow(obj) {
    var dTable = $('#' + xcatMonTableId).dataTable();
    var rows = dTable.fnGetNodes();
    var tgtRow = $(obj).parent().parent().get(0);
    for ( var i in rows) {
        if (rows[i] == tgtRow) {
            dTable.fnDeleteRow(i, null, true);
            break;
        }
    }
}
