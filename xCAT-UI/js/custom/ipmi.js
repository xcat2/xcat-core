/**
 * Execute when the DOM is fully loaded
 */
$(document).ready(function() {
	// Load utility scripts
});

/**
 * Constructor
 * 
 * @return Nothing
 */
var ipmiPlugin = function() {

};

/**
 * Load node inventory
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
ipmiPlugin.prototype.loadInventory = function(data) {
	// Get arguments
	var args = data.msg.split(',');
	// Get tab ID
	var tabId = args[0].replace('out=', '');
	// Get node
	var node = args[1].replace('node=', '');
	// Get node inventory
	var inv = data.rsp;

	// Remove loader
	$('#' + tabId).find('img').remove();

	// Create division to hold inventory
	var invDivId = tabId + 'Inventory';
	var invDiv = $('<div class="inventory" id="' + invDivId + '"></div>');
	var info = createInfoBar('Under construction');
	invDiv.append(info);
	
	// Append to inventory form
	$('#' + tabId).append(invDiv);
};

/**
 * Load clone page
 * 
 * @param node
 *            Source node to clone
 * @return Nothing
 */
ipmiPlugin.prototype.loadClonePage = function(node) {
	// Get nodes tab
	var tab = getNodesTab();
	var newTabId = node + 'CloneTab';

	// If there is no existing clone tab
	if (!$('#' + newTabId).length) {
		// Create status bar and hide it
		var statBarId = node + 'CloneStatusBar';
		var statBar = $('<div class="statusBar" id="' + statBarId + '"></div>').hide();

		// Create info bar
		var infoBar = createInfoBar('Under construction');

		// Create clone form
		var cloneForm = $('<div class="form"></div>');
		cloneForm.append(statBar);
		cloneForm.append(infoBar);

		// Add clone tab
		tab.add(newTabId, 'Clone', cloneForm, true);
	}
	
	tab.select(newTabId);
};

/**
 * Load provision page
 * 
 * @param tabId
 *            The provision tab ID
 * @return Nothing
 */
ipmiPlugin.prototype.loadProvisionPage = function(tabId) {
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
	var inst = tabId.replace('ipmiProvisionTab', '');

	// Create provision form
	var provForm = $('<div class="form"></div>');

	// Create status bar
	var statBarId = 'ipmiProvisionStatBar' + inst;
	var statBar = createStatusBar(statBarId).hide();
	provForm.append(statBar);

	// Create loader
	var loader = createLoader('ipmiProvisionLoader' + inst).hide();
	statBar.find('div').append(loader);

	// Create info bar
	var infoBar = createInfoBar('Provision a node on iDataPlex.');
	provForm.append(infoBar);

	// Append to provision tab
	$('#' + tabId).append(provForm);

	// Create provision type drop down
	var provType = $('<div></div>');
	var typeLabel = $('<label>Provision:</label>');
	var typeSelect = $('<select></select>');
	var provNewNode = $('<option value="new">New node</option>');
	var provExistNode = $('<option value="existing">Existing node</option>');
	typeSelect.append(provNewNode);
	typeSelect.append(provExistNode);
	provType.append(typeLabel);
	provType.append(typeSelect);
	provForm.append(provType);

	/**
	 * Create provision new node division
	 */
	// You should copy whatever is in this function, put it here, and customize it
	var provNew = createProvisionNew('ipmi', inst);
	provForm.append(provNew);

	/**
	 * Create provision existing node division
	 */
	// You should copy whatever is in this function, put it here, and customize it
	var provExisting = createProvisionExisting('ipmi', inst);
	provForm.append(provExisting);

	// Toggle provision new/existing on select
	typeSelect.change(function() {
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
 * Load resources
 * 
 * @return Nothing
 */
ipmiPlugin.prototype.loadResources = function() {
	// Get resource tab ID
	var tabId = 'ipmiResourceTab';
	// Remove loader
	$('#' + tabId).find('img').remove();
	
	// Create info bar
	var infoBar = createInfoBar('Under construction');

	// Create resource form
	var resrcForm = $('<div class="form"></div>');
	resrcForm.append(infoBar);
	
	$('#' + tabId).append(resrcForm);
};

/**
 * Add node range
 * 
 * @return Nothing
 */
ipmiPlugin.prototype.addNode = function() {
    var diaDiv = $('<div id="addIdpDiv" class="form" title="Add iDataPlex Node"></div>');
    var showStr = '<div><label>Node Name: </label><input type="text"></div>' +
               '<div><label>Node Mac:</label><input type="text"></div>' + 
               '<div><label>Node IP: </label><input type="text"></div>' +
               '<div><label>Node Groups : </label><input type="text"></div>' +
               '<div><label>BMC Name:</label><input type="text"></div>' +
               '<div><label>BMC IP:</label><input type="text"></div>' +
               '<div><label>BMC Groups::</label><input type="text"></div>';
    
    diaDiv.append(showStr);
    diaDiv.dialog({
        modal: true,
        width: 400,
        close: function(){$(this).remove();},
        buttons: {
            "OK" : function(){addidataplexNode();},
            "Cancel": function(){$(this).dialog('close');}
        }
    });
};

function addidataplexNode(){
    var tempArray = new Array();
    var errormessage = '';
    var attr = '';
    var args = '';
    
    //remove the warning bar
    $('#addIdpDiv .ui-state-error').remove();
    
    //get all inputs' value
    $('#addIdpDiv input').each(function(){
        attr = $(this).val();
        if (attr){
            tempArray.push($(this).val());
        }
        else{
            errormessage = "You are missing some input!";
            return false;
        }
    });
    
    if ('' != errormessage){
        $('#addIdpDiv').prepend(createWarnBar(errormessage));
        return;
    }
    
    //add the loader
    $('#addIdpDiv').append(createLoader());
    
    //change the dialog button
    $('#addIdpDiv').dialog('option', 'buttons', {'Close':function(){$('#addIdpDiv').dialog('close');}});
    
    //compose all args into chdef for node
    args = '-t;node;-o;' + tempArray[0] + ';mac=' + tempArray[1] + ';ip=' + tempArray[2] + ';groups=' + 
          tempArray[3] + ';mgt=ipmi;chain="runcmd=bmcsetup";netboot=xnba;nodetype=osi;profile=compute;' +
          'bmc=' + tempArray[4];
    
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'chdef',
            tgt : '',
            args : args,
            msg : ''
        }
    });
    
    //compose all args into chdef for bmc
    args = '-t;node;-o;' + tempArray[4] + ';ip=' + tempArray[5] + ';groups=' + tempArray[6];
    
    $.ajax({
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'chdef',
            tgt : '',
            args : args,
            msg : ''
        },
        success: function(data){
            $('#addIdpDiv img').remove();
            var message = '';
            for (var i in data.rsp){
                message += data.rsp[i];
            }
            
            if ('' != message){
                $('#addIdpDiv').prepend(createInfoBar(message));
            }
        }
    });
}