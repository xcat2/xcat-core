/**
 * Load rscan page
 *
 * @param tgtNodes Targets to run rscan against
 */
function loadRscanPage(tgtNodes) {
    // Get node OS
    var osHash = new Object();
    var nodes = tgtNodes.split(',');
    for (var i in nodes) {
        var os = getNodeAttr(nodes[i], 'os');
        var osBase = os.match(/[a-zA-Z]+/);
        if (osBase) {
            nodes[osBase] = 1;
        }
    }

    // Get nodes tab
    var tab = getNodesTab();

    // Generate new tab ID
    var inst = 0;
    var newTabId = 'rscanTab' + inst;
    while ($('#' + newTabId).length) {
        // If one already exists, generate another one
        inst = inst + 1;
        newTabId = 'rscanTab' + inst;
    }

    // Create rscan form
    var rscanForm = $('<div class="form"></div>');

	// Create status bar
    var statBarId = 'rscanStatusBar' + inst;
    var statBar = createStatusBar(statBarId).hide();

    // Create loader
    var loader = createLoader('rscanLoader');
    statBar.find('div').append(loader);

	// Create info bar
    var infoBar = createInfoBar('Collects node information from one or more hardware control points');
    rscanForm.append(statBar, infoBar);

	// Create VM fieldset
    var vmFS = $('<fieldset></fieldset>');
    var vmLegend = $('<legend>Virtual Machine</legend>');
    vmFS.append(vmLegend);
    rscanForm.append(vmFS);

    var vmAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    vmFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/computer.png"></img></div>'));
    vmFS.append(vmAttr);

	// Create options fieldset
    var optionsFS = $('<fieldset></fieldset>');
    var optionsLegend = $('<legend>Options</legend>');
    optionsFS.append(optionsLegend);
    rscanForm.append(optionsFS);

    var optionsAttr = $('<div style="display: inline-table; vertical-align: middle;"></div>');
    optionsFS.append($('<div style="display: inline-table; vertical-align: middle;"><img src="images/provision/setting.png" style="width: 70px;"></img></div>'));
    optionsFS.append(optionsAttr);

    // Create target node or group input
    var target = $('<div><label>Target node range:</label><input type="text" name="target" value="' + tgtNodes + '" title="The node or node range to scan"/></div>');
    vmAttr.append(target);

    // Create options
    var optsList = $('<ul></ul>');
    optionsAttr.append(optsList);

    optsList.append('<li><input type="checkbox" name="u"/>Updates and then prints out node definitions in the xCAT database for CEC/BPA</li>');
    optsList.append('<li><input type="checkbox" name="w"/>Writes output to xCAT database</li>');
    optsList.append('<li><input type="checkbox" name="x"/>XML format</li>');
    optsList.append('<li><input type="checkbox" name="z"/>Stanza formated output</li>');

    // Generate tooltips
    rscanForm.find('div input[title]').tooltip({
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
    var okBtn = createButton('Ok');
    okBtn.css({
    	'width': '80px',
    	'display': 'block'
    });
    okBtn.bind('click', function(event) {
    	// Remove any warning messages
    	$(this).parents('.ui-tabs-panel').find('.ui-state-error').remove();

        // Check inputs
        var ready = true;
        var inputs = $("#" + newTabId + " input[type='text']");
        for ( var i = 0; i < inputs.length; i++) {
            if (!inputs.eq(i).val()) {
                inputs.eq(i).css('border', 'solid #FF0000 1px');
                ready = false;
            } else {
                inputs.eq(i).css('border', 'solid #BDBDBD 1px');
            }
        }

        // Generate arguments
        var chkBoxes = $("#" + newTabId + " input[type='checkbox']:checked");
        var optStr = '';
        var opt;
        for ( var i = 0; i < chkBoxes.length; i++) {
            opt = chkBoxes.eq(i).attr('name');
            optStr += '-' + opt;

            // Append ; to end of string
            if (i < (chkBoxes.length - 1)) {
                optStr += ';';
            }
        }

        // If no inputs are empty
        if (ready) {
            // Get nodes
            var tgts = $('#' + newTabId + ' input[name=target]').val();

            // Disable all inputs and Ok button
            $('#' + newTabId + ' input').attr('disabled', 'disabled');
            $(this).attr('disabled', 'true');

            /**
             * (1) Scan
             */
            $.ajax( {
                url : 'lib/cmd.php',
                dataType : 'json',
                data : {
                    cmd : 'rscan',
                    tgt : tgts,
                    args : optStr,
                    msg : 'out=' + statBarId + ';cmd=rscan;tgt=' + tgts
                },

                success : function(data) {
                    data = decodeRsp(data);
                    updateStatusBar(data);
                }
            });

            // Show status bar
            statBar.show();
        } else {
            // Show warning message
            var warn = createWarnBar('Please provide a value for each missing field.');
            warn.prependTo($(this).parents('.ui-tabs-panel'));
        }
    });
    rscanForm.append(okBtn);

    // Append to discover tab
    tab.add(newTabId, 'Scan', rscanForm, true);

    // Select new tab
    tab.select(newTabId);
}
