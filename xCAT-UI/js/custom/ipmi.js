/**
 * Execute when the DOM is fully loaded
 */
$(document).ready(function() {
	// Load utility scripts (if any)
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
	var args = data.msg.split(',');
	var tabId = args[0].replace('out=', '');
	var node = args[1].replace('node=', '');
	
	// Get node inventory
	var inv = data.rsp;

	// Remove loader
	$('#' + tabId).find('img').remove();

	// Create division to hold inventory
	var invDivId = tabId + 'Inventory';
	var invDiv = $('<div></div>');
	
	// Create a fieldset
	var fieldSet = $('<fieldset></fieldset>');
	var legend = $('<legend>Hardware</legend>');
	fieldSet.append(legend);
	
	var oList = $('<ol></ol>');
	fieldSet.append(oList);
	invDiv.append(fieldSet);

	// Loop through each line
	var item;
	for (var k = 0; k < inv.length; k++) {
		// Remove node name
		var attr = inv[k].replace(node + ': ', '');
		attr = jQuery.trim(attr);

		// Append attribute to list
		item = $('<li></li>');
		item.append(attr);
		oList.append(item);
	}

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
		// Create info bar
		var infoBar = createInfoBar('Not supported');

		// Create clone form
		var cloneForm = $('<div class="form"></div>');
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
	// Create provision form
	var provForm = $('<div class="form"></div>');

	// Create info bar
	var infoBar = createInfoBar('Provision a node on iDataPlex.');
	provForm.append(infoBar);

	// Append to provision tab
	$('#' + tabId).append(provForm);

	/**
	 * Create provision new node division
	 */
	// You should copy whatever is in this function, put it here, and customize it
	createProvision('ipmi', provForm);
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
               '<div><label>Node MAC:</label><input type="text"></div>' + 
               '<div><label>Node IP: </label><input type="text"></div>' +
               '<div><label>Node Groups : </label><input type="text"></div>' +
               '<div><label>BMC Name:</label><input type="text"></div>' +
               '<div><label>BMC IP:</label><input type="text"></div>' +
               '<div><label>BMC Groups:</label><input type="text"></div>';
    
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
