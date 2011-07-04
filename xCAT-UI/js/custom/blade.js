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
var bladePlugin = function() {

};

/**
 * Load node inventory
 * 
 * @param data
 *            Data from HTTP request
 * @return Nothing
 */
bladePlugin.prototype.loadInventory = function(data) {
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
bladePlugin.prototype.loadClonePage = function(node) {
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
bladePlugin.prototype.loadProvisionPage = function(tabId) {
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
	var inst = tabId.replace('bladeProvisionTab', '');

	// Create provision form
	var provForm = $('<div class="form"></div>');

	// Create status bar
	var statBarId = 'bladeProvisionStatBar' + inst;
	var statBar = createStatusBar(statBarId).hide();
	provForm.append(statBar);

	// Create loader
	var loader = createLoader('bladeProvisionLoader' + inst).hide();
	statBar.find('div').append(loader);

	// Create info bar
	var infoBar = createInfoBar('Provision a node on BladeCenter.');
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
	var provNew = createProvisionNew('blade', inst);
	provForm.append(provNew);

	/**
	 * Create provision existing node division
	 */
	// You should copy whatever is in this function, put it here, and customize it
	var provExisting = createProvisionExisting('blade', inst);
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
bladePlugin.prototype.loadResources = function() {
	// Get resource tab ID
	var tabId = 'bladeResourceTab';
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
bladePlugin.prototype.addNode = function() {
    var nodeTypeSelectDia = $('<div id="nodeTypeSelectDia" class="form"></div>');
    nodeTypeSelectDia.append('<div><label for="mgt">Node Type :</label><select id="nodeTypeSelect">' +
            '<option value="mm">Amm Node</option><option value="blade">Blade Node</option></select></div>');
    //append the mm div
    var mmStr = '<div id="mmNode">' +
                   '<label>Amm Name : </label><input id="ammName" type="text"></input><br/><br/>' +
                   '<label>Amm IP   : </label><input id="ammIp" type="text"></input>' +
                   '</div>';
    
    //append the blade div
    var bladeStr = '<div id="bladeNode" style="display:none;">' +
                   '<label>Blade Name : </label><input id="bladeName" type="text"></input><br/><br/>' +
                   '<label>Blade Group : </label><input id="bladeGroup" type="text"></input><br/><br/>' +
                   '<label>Blade Id : </label><input id="bladeId" type="text"></input><br/><br/>' +
                   '<label>Blade Series : </label><input type="radio" name="series" value="js"/>JS<input type="radio" name="series" value="ls"/>LS<br/><br/>' +
                   '<label>Blade Mpa : </label><select id="mpaSelect"></select>';
    nodeTypeSelectDia.append(mmStr);
    nodeTypeSelectDia.append(bladeStr);
    
    nodeTypeSelectDia.find('#nodeTypeSelect').bind('change', function(){
       $('#nodeTypeSelectDia .ui-state-error').remove();
       $('#mmNode').toggle();
       $('#bladeNode').toggle();
       if ('mm' == $(this).val()){
           return;
       }
       
       //get all mm nodes from the server side
       $('#bladeNode select').empty();
       $('#bladeNode').append(createLoader());
       
       $.ajax({
           url : 'lib/cmd.php',
           dataType : 'json',
           data : {
               cmd : 'lsdef',
               tgt : '',
               args : '-t;node;-w;mgt==blade;-w;id==0',
               msg : ''
           },
           success : function(data){
               var position = 0;
               var tempStr = '';
               var options = '';
               //remove the loading image
               $('#bladeNode img').remove();
               
               //check return result
               if (1 > data.rsp.length){
                   $('#nodeTypeSelectDia').prepend(createWarnBar('Please define MM node first!'));
                   return;
               }
               
               //add all mm nodes to select
               for (var i in data.rsp){
                   tempStr = data.rsp[i];
                   position = tempStr.indexOf(' ');
                   tempStr = tempStr.substring(0, position);
                   options += '<option value="' + tempStr + '">' + tempStr + '</option>';
               }
               
               $('#bladeNode select').append(options);
           }
       });
    });
    
    nodeTypeSelectDia.dialog( {
        modal : true,
        width : 400,
        title : 'Select Node Type',
        open : function(event, ui) {
            $(".ui-dialog-titlebar-close").hide();
        },
        buttons : {
            'Ok' : function() {
                //remove all error bar
                $('#nodeTypeSelectDia .ui-state-error').remove();
                
                if ($('#nodeTypeSelect').attr('value') == "mm") {
                    addMmNode();
                }
                else {
                    addBladeNode();
                }
            },
            'Cancel' : function() {
                $(this).remove();
            }
        }
    });
};

function addMmNode(){
    var name = $('#ammName').val();
    var ip = $('#ammIp').val();
    
    if ((!name) || (!ip)){
        $('#nodeTypeSelectDia').prepend(createWarnBar("You miss some inputs."));
        return;
    }
    
    //add the loader
    $('#nodeTypeSelectDia').prepend(createLoader());
    $('.ui-dialog-buttonpane .ui-button').attr('disabled', true);
    var argsTmp = '-t;node;-o;' + name + 
            ';id=0;nodetype=mm;groups=mm;mgt=blade;mpa=' + name + ';ip=' + ip;
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'chdef',
            tgt : '',
            args : argsTmp,
            msg : ''
        },
        success : function(data) {
            $('#nodeTypeSelectDia').find('img').remove();
            var messages = data.rsp;
            var notes = "";
            for ( var i = 0; i < messages.length; i++) {
                notes += messages[i];
            }
            var info = createInfoBar(notes);
            $('#nodeTypeSelectDia').prepend(info);
            $('#nodeTypeSelectDia').dialog("option", "buttons", {
                "close" : function() {
                    $('#nodeTypeSelectDia').remove();
                }
            });
        }
    });
}

function addBladeNode(){
    var name = $('#bladeName').val();
    var group = $('#bladeGroup').val();
    var id = $('#bladeId').val();
    var series = $("#bladeNode :checked").val();
    var mpa = $('#mpaSelect').val();

    var argsTmp = '-t;node;-o;' + name + ';id=' + id + 
            ';nodetype=osi;groups=' + group + ';mgt=blade;mpa=' + mpa + ';serialflow=hard';
    if (series != 'js') {
        argsTmp += ';serialspeed=19200;serialport=1';
    }
    
    if ((!name) || (!group) || (!id) || (!mpa)){
        $('#nodeTypeSelectDia').prepend(createWarnBar("You miss some inputs."));
        return;
    }

    //add loader and disable buttons
    $('#nodeTypeSelectDia').prepend(createLoader());
    $('.ui-dialog-buttonpane .ui-button').attr('disabled', true);
    $.ajax( {
        url : 'lib/cmd.php',
        dataType : 'json',
        data : {
            cmd : 'chdef',
            tgt : '',
            args : argsTmp,
            msg : ''
        },
        success : function(data) {
            $('#nodeTypeSelectDia').find('img').remove();
            var messages = data.rsp;
            var notes = "";
            for ( var i = 0; i < messages.length; i++) {
                notes += messages[i];
            }

            $('#nodeTypeSelectDia').prepend(createInfoBar(notes));
            $('#nodeTypeSelectDia').dialog("option", "buttons", {
                "close" : function() {
                    $('#nodeTypeSelectDia').remove();
                }
            });
        }
    });

}