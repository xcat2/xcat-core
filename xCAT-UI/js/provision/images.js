/**
 * Global variables
 */
var origAttrs = new Object();	// Original image attributes
var defAttrs; 					// Definable image attributes
var imgTableId = 'imagesDatatable';	// Images datatable ID
var softwareList = {
	"rsct" : ["rsct.core.utils", "rsct.core", "src"],
	"pe" : ["IBMJava2-142-ppc64-JRE", "ibm_lapi_ip_rh6p", "ibm_lapi_us_rh6p", "IBM_pe_license", "ibm_pe_rh6p", "ppe_pdb_ppc64_rh600", "sci_ppc_32bit_rh600", "sci_ppc_64bit_rh600", "vac.cmp",
			"vac.lib", "vac.lic", "vacpp.cmp", "vacpp.help.pdf", "vacpp.lib", "vacpp.man", "vacpp.rte", "vacpp.rte.lnk", "vacpp.samples", "xlf.cmp", "xlf.help.pdf", "xlf.lib", "xlf.lic", "xlf.man",
			"xlf.msg.rte", "xlf.rte", "xlf.rte.lnk", "xlf.samples", "xlmass.lib", "xlsmp.lib", "xlsmp.msg.rte", "xlsmp.rte"],
	"gpfs" : ["gpfs.base", "gpfs.gpl", "gpfs.gplbin", "gpfs.msg.en_US"],
	"essl" : ["essl.3232.rte", "essl.3264.rte", "essl.6464.rte", "essl.common", "essl.license", "essl.man", "essl.msg", "essl.rte", "ibm-java2", "pessl.common", "pessl.license", "pessl.man",
			"pessl.msg", "pessl.rte.ppe"],
	"loadl" : ["IBMJava2", "LoadL-full-license-RH6", "LoadL-resmgr-full-RH6", "LoadL-scheduler-full-RH6"],
	"ganglia" : ["rrdtool", "ganglia", "ganglia-gmetad", "ganglia-gmond"],
	"base" : ["createrepo"]
};

/**
 * Load images page
 * 
 * @return Nothing
 */
function loadImagesPage() {
	// Set padding for images page
	$('#imagesTab').css('padding', '20px 60px');
	
	// Get images within the database
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'lsdef',
			tgt : '',
			args : '-t;osimage;-l',
			msg : ''
		},

		success : loadImages
	});
}

/**
 * Load images within the database
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function loadImages(data) {
	// Data returned
	var rsp = data.rsp;
	// Image attributes hash
	var attrs = new Object();
	// Image attributes
	var headers = new Object();
	
	// Clear hash table containing image attributes
	origAttrs = '';

	var image;
	var args;
	for (var i in rsp) {
		// Get the image
		var pos = rsp[i].indexOf('Object name:');
		if (pos > -1) {
			var temp = rsp[i].split(': ');
			image = jQuery.trim(temp[1]);

			// Create a hash for the image attributes
			attrs[image] = new Object();
			i++;
		}

		// Get key and value
		args = rsp[i].split('=');
		var key = jQuery.trim(args[0]);
		var val = jQuery.trim(args[1]);

		// Create a hash table
		attrs[image][key] = val;
		headers[key] = 1;
	}
	
	// Save attributes in hash table
	origAttrs = attrs;

	// Sort headers
	var sorted = new Array();
	for (var key in headers) {
		sorted.push(key);
	}
	sorted.sort();

	// Add column for check box and image name
	sorted.unshift('<input type="checkbox" onclick="selectAllCheckbox(event, $(this))">', 'imagename');

	// Create a datatable
	var dTable = new DataTable(imgTableId);
	dTable.init(sorted);

	// Go through each image
	for (var img in attrs) {
		// Create a row
		var row = new Array();
		// Create a check box
		var checkBx = '<input type="checkbox" name="' + img + '"/>';
		// Push in checkbox and image name
		row.push(checkBx, img);
		
		// Go through each header
		for (var i = 2; i < sorted.length; i++) {
			// Add the node attributes to the row
			var key = sorted[i];
			var val = attrs[img][key];
			if (val) {
				row.push(val);
			} else {
				row.push('');
			}
		}

		// Add the row to the table
		dTable.add(row);
	}

	// Clear the tab before inserting the table
	$('#imagesTab').children().remove();
	
	// Create info bar for images tab
	var info = createInfoBar('Click on a cell to edit.  Click outside the table to save changes.  Hit the Escape key to ignore changes.');
	$('#imagesTab').append(info);

	/**
	 * The following actions are available for images:
	 * copy Linux distribution and edit image properties
	 */

	// Create copy CD link
	var copyCDLnk = $('<a>Copy CD</a>');
	copyCDLnk.click(function() {
		loadCopyCdPage();
	});
	
	// Create image link
	var newLnk = $('<a>Create image</a>');
	newLnk.click(function() {
		loadCreateImage();
	});
	
	// Create edit link
	var editBtn = $('<a>Edit</a>');
	editBtn.click(function() {
		var tgtImages = getNodesChecked(imgTableId).split(',');
		for (var i in tgtImages) {
			 loadEditImagePage(tgtImages[i]);
		}
	});
	
	// Insert table
	$('#imagesTab').append(dTable.object());

	// Turn table into a datatable
	var myDataTable = $('#' + imgTableId).dataTable({
		'iDisplayLength': 50,
		'bLengthChange': false,
		"sScrollX": "100%",
		"bAutoWidth": true,
		"fnInitComplete": function() {
			adjustColumnSize(imgTableId);
		}
	});
	
	// Set datatable width
	$('#' + imgTableId + '_wrapper').css({
		'width': '880px'
	});
	
	// Actions
	var actionBar = $('<div class="actionBar"></div>');
	var actionsLnk = '<a>Actions</a>';
	var actsMenu = createMenu([copyCDLnk, newLnk, editBtn]);

	// Create an action menu
	var actionsMenu = createMenu([ [ actionsLnk, actsMenu ] ]);
	actionsMenu.superfish();
	actionsMenu.css('display', 'inline-block');
	actionBar.append(actionsMenu);
	
	// Create a division to hold actions menu
	var menuDiv = $('<div id="' + imgTableId + '_menuDiv" class="menuDiv"></div>');
	$('#' + imgTableId + '_wrapper').prepend(menuDiv);
	menuDiv.append(actionBar);	
	$('#' + imgTableId + '_filter').appendTo(menuDiv);
	
	/**
	 * Enable editable columns
	 */
	
	// Do not make 1st, 2nd, 3rd, 4th, or 5th column editable
	$('#' + imgTableId + ' td:not(td:nth-child(1),td:nth-child(2))').editable(
		function(value, settings) {	
			// Get column index
			var colPos = this.cellIndex;
						
			// Get row index
			var dTable = $('#' + imgTableId).dataTable();
			var rowPos = dTable.fnGetPosition(this.parentNode);
			
			// Update datatable
			dTable.fnUpdate(value, rowPos, colPos);
			
			// Get image name
			var image = $(this).parent().find('td:eq(1)').text();
					
			// Get table headers
			var headers = $('#' + imgTableId).parents('.dataTables_scroll').find('.dataTables_scrollHead thead tr:eq(0) th');

        	// Get attribute name
        	var attrName = jQuery.trim(headers.eq(colPos).text());
        	// Get column value
        	var value = $(this).text();		
        	// Build argument
        	var args = attrName + '=' + value;
        			
        	// Send command to change image attributes
        	$.ajax( {
        		url : 'lib/cmd.php',
        		dataType : 'json',
        		data : {
        			cmd : 'chdef',
        			tgt : '',
        			args : '-t;osimage;-o;' + image + ';' + args,
        			msg : 'out=imagesTab;tgt=' + image
        		},

        		success: showChdefOutput
        	});

			return value;
		}, {
			onblur : 'submit', 	// Clicking outside editable area submits changes
			type : 'textarea',	// Input type to use
			placeholder: ' ',
			height : '30px' 	// The height of the text area
		});
		
	// Get definable node attributes
	$.ajax( {
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'lsdef',
			tgt : '',
			args : '-t;osimage;-h',
			msg : ''
		},

		success : setImageDefAttrs
	});
}

/**
 * Set definable image attributes
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function setImageDefAttrs(data) {
	// Clear hash table containing definable image attributes
	defAttrs = new Array();
	
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
    			descr = descr.replace(new RegExp('<', 'g'), '[').replace(new RegExp('>', 'g'), ']');
    			    			
    			// Set hash table where key = attribute name and value = description
        		defAttrs[key] = descr;
			} else {				
				// Append description to hash table
				defAttrs[key] = defAttrs[key] + '\n' + attr.replace(new RegExp('<', 'g'), '[').replace(new RegExp('>', 'g'), ']');
			}
		} // End of if
	} // End of for
}

/**
 * Load create image page
 * 
 * @return Nothing
 */
function loadCreateImage() {
	// Get nodes tab
	var tab = getProvisionTab();
	var tabId = 'createImageTab';
	
	// Generate new tab ID
	if ($('#' + tabId).size()) {
		tab.select(tabId);
		return;
	}

	var imageOsvers = $.cookie("osvers").split(",");
	var imageArch = $.cookie("osarchs").split(",");
	var profileArray = $.cookie("profiles").split(",");
	
	var parm = '';
	var i = 0;

	// Create set properties form
	var createImgForm = $('<div class="form" ></div>');

	// Show the infomation
	var infoBar = createInfoBar('Specify the parameters for the image (stateless or statelite) you want to create, then click Create.');
	createImgForm.append(infoBar);

	// OS version selector
	parm += '<div><label>OS version:</label><select id="osvers" onchange="hpcShow()">';
	for (i in imageOsvers) {
		parm += '<option value="' + imageOsvers[i] + '">' + imageOsvers[i] + '</option>';
	}
	parm += '</select></div>';

	// OS arch selector
	parm += '<div><label>OS architecture:</label><select id="osarch" onchange="hpcShow()">';
	for (i in imageArch) {
		parm += '<option value="' + imageArch[i] + '">' + imageArch[i] + '</option>';
	}
	parm += '</select></div>';

	// Netboot interface input
	parm += '<div><label>Netboot interface:</label><input type="text" id="netbootif"></div>';
	
	// Profile selector
	parm += '<div><label>Profile:</label><select id="profile" onchange="hpcShow()">';
	for (i in profileArray) {
	    parm += '<option value="' + profileArray[i] + '">' + profileArray[i] + '</option>';
	}
	parm += '</select></div>';
	
	// Boot method selector
	parm += '<div><label>Boot method:</label><select id="bootmethod"><option value="stateless">stateless</option></select></div>';
	createImgForm.append(parm);
	createHpcSelect(createImgForm);

	// The button used to create images is created here
    var createImageBtn = createButton("Create");
    createImageBtn.bind('click', function(event) {
        createImage();
    });

    createImgForm.append(createImageBtn);
    
	// Add and show the tab
	tab.add(tabId, 'Create', createImgForm, true);
	tab.select(tabId);

	// Check the selected osver and osarch for hcp stack select
	// If they are valid, show the hpc stack select area
	hpcShow();	
}

/**
 * Create HPC select
 * 
 * @param container
 *            The container to hold the HPC select
 * @return HPC select appended to the container
 */
function createHpcSelect(container) {
	var hpcFieldset = $('<fieldset id="hpcsoft"></fieldset>');
	hpcFieldset.append('<legend>HPC Software Stack</legend>');
	var str = 'Before selecting the software, you should have the following already completed for your xCAT cluster:<br/><br/>'
			+ '1. If you are using xCAT hierarchy, your service nodes are installed and running.<br/>'
			+ '2. Your compute nodes are defined to xCAT, and you have verified your hardware control capabilities, '
			+ 'gathered MAC addresses, and done all the other necessary preparations for a diskless install.<br/>'
			+ '3. You should have a diskless image created with the base OS installed and verified on at least one test node.<br/>'
			+ '4. You should install the softwares on the management node, and copy all correponding packages into the location ' + '"/install/custom/otherpkgs/" based on '
			+ '<a href="http://sourceforge.net/apps/mediawiki/xcat/index.php?title=IBM_HPC_Stack_in_an_xCAT_Cluster" target="_blank">these documentations</a>.<br/>';
	hpcFieldset.append(createInfoBar(str));
	
	// Advanced software when select the compute profile
	str = '<div id="partlysupport"><ul><li id="gpfsli"><input type="checkbox" onclick="softwareCheck(this)" name="gpfs">GPFS</li>' +
		'<li id="rsctli"><input type="checkbox" onclick="softwareCheck(this)" name="rsct">RSCT</li>' + 
		'<li id="peli"><input type="checkbox" onclick="softwareCheck(this)" name="pe">PE</li>' + 
		'<li id="esslli"><input type="checkbox" onclick="esslCheck(this)" name="essl">ESSl&PESSL</li>' + 
		'</ul></div>' +
		'<div><ul><li id="gangliali"><input type="checkbox" onclick="softwareCheck(this)" name="ganglia">Ganglia</li>' +
		'</ul></div>';
	hpcFieldset.append(str);

	container.append($('<div></div>').append(hpcFieldset));
}

/**
 * Check the dependance for ESSL and start the software check for ESSL
 * 
 * @param softwareObject
 *            The checkbox object of ESSL
 * @return nothing
 */
function esslCheck(softwareObject) {
	var softwareName = softwareObject.name;
	if (!$('#createImageTab input[name=pe]').attr('checked')) {
		var warnBar = createWarnBar('You must first select the PE');
		$(':checkbox[name=essl]').attr("checked", false);
		
		// Clear existing warnings and append new warning
		$('#hpcsoft .ui-state-error').remove();
		$('#hpcsoft').prepend(warnBar);
		
		return;
	} else {
		softwareCheck(softwareObject);
	}
}

/**
 * Check the parameters for the HPC software
 * 
 * @param softwareObject
 *            Checkbox object of the HPC software
 * @return True: 	The checkbox is checked 
 * 		   False: 	Error message shown on page
 */
function softwareCheck(softwareObject) {
	var softwareName = softwareObject.name;
	$('#createImageTab #' + softwareName + 'li .ui-state-error').remove();
	$('#createImageTab #' + softwareName + 'li').append(createLoader());
	var cmdString = genRpmCmd(softwareName);
	$.ajax( {
		url : 'lib/systemcmd.php',
		dataType : 'json',
		data : {
			cmd : cmdString,
			msg : softwareName
		},
		success : function(data) {
			if (rpmCheck(data.rsp, data.msg)) {
				genLsCmd(data.msg);
				$.ajax( {
					url : 'lib/systemcmd.php',
					dataType : 'json',
					data : {
						cmd : genLsCmd(data.msg),
						msg : data.msg
					},
					success : rpmCopyCheck
				});
			}
		}
	});
}

/**
 * Check if the RPMs are copied to the special location
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function rpmCopyCheck(data) {
	// Remove the loading image
	var errorStr = '';
	var softwareName = data.msg;
	
	// Check the return information
	var reg = /.+:(.+): No such.*/;
	var resultArray = data.rsp.split("\n");
	for ( var i in resultArray) {
		var temp = reg.exec(resultArray[i]);
		if (temp) {
			// Find out the path and RPM name
			var pos = temp[1].lastIndexOf('/');
			var path = temp[1].substring(0, pos);
			var rpmName = temp[1].substring(pos + 1).replace('*', '');
			errorStr += 'copy ' + rpmName + ' to ' + path + '<br/>';
		}
	}
	$('#createImageTab #' + softwareName + 'li').find('img').remove();
	
	// No error, show the check image
	if (!errorStr) {
		var infoPart = '<div style="display:inline-block; margin:0px"><span class="ui-icon ui-icon-circle-check"></span></div>';
		$('#createImageTab #' + softwareName + 'li').append(infoPart);
	} else {
		// Show the error message
		errorStr = 'To install the RSCT on your compute node. You should:<br/>' + errorStr + '</div>';
		var warnBar = createWarnBar(errorStr);
		$(':checkbox[name=' + softwareName + ']').attr("checked", false);
		
		// Clear existing warnings and append new warning
		$('#hpcsoft .ui-state-error').remove();
		$('#hpcsoft').prepend(warnBar);
	}
}

/**
 * Generate the RPM command for rpmcheck
 * 
 * @param softwareName
 *            The name of the software
 * @return The RPM command, e.g. 'rpm -q ***'
 */
function genRpmCmd(softwareName) {
	var cmdString;
	cmdString = 'rpm -q ';
	for (var i in softwareList[softwareName]) {
		cmdString += softwareList[softwareName][i] + ' ';
	}

	for (var i in softwareList['base']) {
		cmdString += softwareList['base'][i] + ' ';
	}
	
	return cmdString;
}

/**
 * Check if the RPMs for the HPC software are copied to the special location
 * 
 * @param softwareName
 *            The name of the software
 * @return True: 	OK 
 * 		   False: 	Add the error message to the page
 */
function genLsCmd(softwareName) {
	var osvers = $('#createImageTab #osvers').val();
	var osarch = $('#createImageTab #osarch').val();
	var path = '/install/post/otherpkgs/' + osvers + '/' + osarch + '/' + softwareName;
	var checkCmd = 'ls ';

	for (var i in softwareList[softwareName]) {
		checkCmd += path + '/' + softwareList[softwareName][i] + '*.rpm ';
	}
	checkCmd += '2>&1';

	return checkCmd;
}

/**
 * Check if all RPMs are installed
 * 
 * @param checkInfo
 *            'rpm -q' output
 * @return True: 	All RPMs are installed 
 * 		   False: 	Some RPMs are not installed
 */
function rpmCheck(checkInfo, name) {
	var errorStr = '';

	var checkArray = checkInfo.split('\n');
	for (var i in checkArray) {
		if (checkArray[i].indexOf('not install') != -1) {
			errorStr += checkArray[i] + '<br/>';
		}
	}

	if (!errorStr) {
		return true;
	}

	errorStr = errorStr.substr(0, errorStr.length - 1);
	$(':checkbox[name=' + name + ']').attr('checked', false);
	
	// Add the error
	var warnBar = createWarnBar(errorStr);
	$('#createImageTab #' + name + 'li').find('img').remove();

	// Clear existing warnings and append new warning
	$('#hpcsoft .ui-state-error').remove();
	$('#hpcsoft').prepend(warnBar);
	
	return;
}

/**
 * Check the option and decide whether to show the hpcsoft or not
 * 
 * @param Nothing
 * @return Nothing
 */
function hpcShow() {
	// The current UI only supports RHELS 6
	// If you want to support all, delete the subcheck
	if ($('#createImageTab #osvers').attr('value') != "rhels6" || $('#createImageTab #osarch').attr('value') != "ppc64" || $('#createImageTab #profile').attr('value') != "compute") {
		$('#createImageTab #partlysupport').hide();
	} else {
		$('#createImageTab #partlysupport').show();
	}
}

/**
 * Load set image properties page
 * 
 * @param tgtImage
 *            Target image to set properties
 * @return Nothing
 */
function loadEditImagePage(tgtImage) {
	// Get nodes tab
	var tab = getProvisionTab();

	// Generate new tab ID
	var inst = 0;
	var newTabId = 'editImageTab' + inst;
	while ($('#' + newTabId).length) {
		// If one already exists, generate another one
		inst = inst + 1;
		newTabId = 'editImageTab' + inst;
	}

	// Open new tab
	// Create set properties form
	var setPropsForm = $('<div class="form"></div>');

	// Create info bar
	var infoBar = createInfoBar('Choose the properties you wish to change on the node. When you are finished, click Save.');
	setPropsForm.append(infoBar);

	// Create an input for each definable attribute
	var div, label, input, value;
	// Set node attribute
	origAttrs[tgtImage]['imagename'] = tgtImage;
	for (var key in defAttrs) {
		// If an attribute value exists
		if (origAttrs[tgtImage][key]) {
			// Set the value
			value = origAttrs[tgtImage][key];
		} else {
			value = '';
		}
		
		// Create label and input for attribute
		div = $('<div></div>').css('display', 'inline');
		label = $('<label>' + key + ':</label>').css('vertical-align', 'middle');
		input = $('<input type="text" id="' + key + '" value="' + value + '" title="' + defAttrs[key] + '"/>').css('margin-top', '5px');
		
		// Create server browser
		switch (key) {
    		case 'pkgdir':
    			input.serverBrowser({
    	    		onSelect : function(path) {
        				$('#pkgdir').val(path);
            		},
            		onLoad : function() {
            			return $('#pkgdir').val();
            		},
            		knownExt : [ 'exe', 'js', 'txt' ],
            		knownPaths : [{
            			text : 'Install',
            			image : 'desktop.png',
            			path : '/install'
            		}],
            		imageUrl : 'images/serverbrowser/',
            		systemImageUrl : 'images/serverbrowser/',
            		handlerUrl : 'lib/getpath.php',
            		title : 'Browse',
            		requestMethod : 'POST',
            		width : '500',
            		height : '300',
            		basePath : '/install' // Limit user to only install directory
            	});
    			break;
    		case 'otherpkgdir':
    			input.serverBrowser({
    	    		onSelect : function(path) {
        				$('#otherpkgdir').val(path);
            		},
            		onLoad : function() {
            			return $('#otherpkgdir').val();
            		},
            		knownExt : [ 'exe', 'js', 'txt' ],
            		knownPaths : [{
            			text : 'Install',
            			image : 'desktop.png',
            			path : '/install'
            		}],
            		imageUrl : 'images/serverbrowser/',
            		systemImageUrl : 'images/serverbrowser/',
            		handlerUrl : 'lib/getpath.php',
            		title : 'Browse',
            		requestMethod : 'POST',
            		width : '500',
            		height : '300',
            		basePath : '/install' // Limit user to only install directory
            	});
    			break;
    		case 'pkglist':
    			input.serverBrowser({
    	    		onSelect : function(path) {
        				$('#pkglist').val(path);
            		},
            		onLoad : function() {
            			return $('#pkglist').val();
            		},
            		knownExt : [ 'exe', 'js', 'txt' ],
            		knownPaths : [{
            			text : 'Install',
            			image : 'desktop.png',
            			path : '/install'
            		}],
            		imageUrl : 'images/serverbrowser/',
            		systemImageUrl : 'images/serverbrowser/',
            		handlerUrl : 'lib/getpath.php',
            		title : 'Browse',
            		requestMethod : 'POST',
            		width : '500',
            		height : '300',
            		basePath : '/opt/xcat/share' // Limit user to only install directory
            	});
    			break;
    		case 'otherpkglist':
    			input.serverBrowser({
    	    		onSelect : function(path) {
        				$('#otherpkglist').val(path);
            		},
            		onLoad : function() {
            			return $('#otherpkglist').val();
            		},
            		knownExt : [ 'exe', 'js', 'txt' ],
            		knownPaths : [{
            			text : 'Install',
            			image : 'desktop.png',
            			path : '/install'
            		}],
            		imageUrl : 'images/serverbrowser/',
            		systemImageUrl : 'images/serverbrowser/',
            		handlerUrl : 'lib/getpath.php',
            		title : 'Browse',
            		requestMethod : 'POST',
            		width : '500',
            		height : '300',
            		basePath : '/install' // Limit user to only install directory
            	});
    			break;
    		case 'template':
    			input.serverBrowser({
    	    		onSelect : function(path) {
        				$('#template').val(path);
            		},
            		onLoad : function() {
            			return $('#template').val();
            		},
            		knownExt : [ 'exe', 'js', 'txt' ],
            		knownPaths : [{
            			text : 'Install',
            			image : 'desktop.png',
            			path : '/install'
            		}],
            		imageUrl : 'images/serverbrowser/',
            		systemImageUrl : 'images/serverbrowser/',
            		handlerUrl : 'lib/getpath.php',
            		title : 'Browse',
            		requestMethod : 'POST',
            		width : '500',
            		height : '300',
            		basePath : '/opt/xcat/share' // Limit user to only install directory
            	});
    			break;
    		default:
    			// Do nothing
		}
		
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
		delay: 500,
		predelay: 800,
		events: {
		  def:     "mouseover,mouseout",
		  input:   "mouseover,mouseout",
		  widget:  "focus mouseover,blur mouseout",
		  tooltip: "mouseover,mouseout"
		}
	});

	/**
	 * Save
	 */
	var saveBtn = createButton('Save');
	saveBtn.bind('click', function(event) {	
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
		
		// Send command to change image attributes
    	$.ajax( {
    		url : 'lib/cmd.php',
    		dataType : 'json',
    		data : {
    			cmd : 'chdef',
    			tgt : '',
    			args : '-t;osimage;-o;' + tgtImage + ';' + args,
    			msg : 'out=' + newTabId + ';tgt=' + tgtImage
    		},

    		success: showChdefOutput
    	});
	});
	setPropsForm.append(saveBtn);
	
	/**
	 * Cancel
	 */
	var cancelBtn = createButton('Cancel');
	cancelBtn.bind('click', function(event) {
		// Close the tab
		tab.remove($(this).parent().parent().attr('id'));
	});
	setPropsForm.append(cancelBtn);

	// Append to discover tab
	tab.add(newTabId, 'Edit', setPropsForm, true);

	// Select new tab
	tab.select(newTabId);
}

/**
 * Load copy CD page
 * 
 * @return Nothing
 */
function loadCopyCdPage() {
	// Get provision tab
	var tab = getProvisionTab();

	// Generate new tab ID
	var inst = 0;
	newTabId = 'copyLinuxTab' + inst;
	while ($('#' + newTabId).length) {
		// If one already exists, generate another one
		inst = inst + 1;
		newTabId = 'copyLinuxTab' + inst;
	}
	
	// Create copy Linux form
	var copyLinuxForm = $('<div class="form"></div>');
	
	// Create status bar, hide on load
	var statBarId = 'copyLinuxStatusBar' + inst;
	var statBar = createStatusBar(statBarId).hide();
	copyLinuxForm.append(statBar);

	// Create loader
	var loader = createLoader('');
	statBar.find('div').append(loader);
	
	// Create info bar
	var infoBar = createInfoBar('Copy Linux distributions and service levels from CDs or DVDs to the install directory.');
	copyLinuxForm.append(infoBar);
			
	// Create Linux ISO input
	var iso = $('<div></div>');
	var isoLabel = $('<label> Linux ISO/DVD:</label>').css('vertical-align', 'middle');
	var isoInput = $('<input type="text" id="iso" name="iso"/>').css('width', '300px');
	iso.append(isoLabel);
	iso.append(isoInput);
	copyLinuxForm.append(iso);
	
	// Create architecture input
	copyLinuxForm.append('<div><label>Architecture:</label><input type="text" id="arch" name="arch" title="The architecture of the Linux distro on the ISO/DVD, e.g. rhel5.3, centos5.1, fedora9."/></div>');
	// Create distribution input
	copyLinuxForm.append('<div><label>Distribution:</label><input type="text" id="distro" name="distro" title="The Linux distro name and version that the ISO/DVD contains, e.g. x86, s390x, ppc64."/></div>');
	
	// Generate tooltips
	copyLinuxForm.find('div input[title]').tooltip({
		position: "center right",
		offset: [-2, 10],
		effect: "fade",		
		opacity: 0.7,
		delay: 500,
		predelay: 800,
		events: {
			def:     "mouseover,mouseout",
			input:   "mouseover,mouseout",
			widget:  "focus mouseover,blur mouseout",
			tooltip: "mouseover,mouseout"
		}
	});
	
	/**
	 * Browse
	 */
	var browseBtn = createButton('Browse');
	iso.append(browseBtn);
	// Browse server directory and files
	browseBtn.serverBrowser({
		onSelect : function(path) {
			$('#iso').val(path);
		},
		onLoad : function() {
			return $('#iso').val();
		},
		knownExt : [ 'exe', 'js', 'txt' ],
		knownPaths : [ {
			text : 'Install',
			image : 'desktop.png',
			path : '/install'
		} ],
		imageUrl : 'images/serverbrowser/',
		systemImageUrl : 'images/serverbrowser/',
		handlerUrl : 'lib/getpath.php',
		title : 'Browse',
		requestMethod : 'POST',
		width : '500',
		height : '300',
		basePath : '/install' // Limit user to only install directory
	});
	
	/**
	 * Copy
	 */
	var copyBtn = createButton('Copy');
	copyLinuxForm.append(copyBtn);
	copyBtn.bind('click', function(event) {
		// Disable all inputs and buttons
		$('#' + newTabId + ' input').attr('disabled', 'true');
		$('#' + newTabId + ' button').attr('disabled', 'true');
		// Show status bar and loader
		$('#' + statBarId).show();
		$('#' + statBarId).find('img').show();
		
		// Get Linux ISO
		var iso = $('#' + newTabId + ' input[name=iso]').val();
		// Get architecture
		var arch = $('#' + newTabId + ' input[name=arch]').val();
		// Get distribution
		var distro = $('#' + newTabId + ' input[name=distro]').val();

		// Send ajax request to copy ISO
		$.ajax( {
			url : 'lib/cmd.php',
			dataType : 'json',
			data : {
				cmd : 'copycds',
				tgt : '',
				args : '-n;' + distro + ';-a;' + arch + ';' + iso,
				msg : 'out=' + statBarId
			},

			/**
			 * Show output
			 * 
			 * @param data
			 *            Data returned from HTTP request
			 * @return Nothing
			 */
			success : function(data) {
				// Get output
				var out = data.rsp;
				// Get status bar ID
				var statBarId = data.msg.replace('out=', '');
				// Get tab ID
				var tabId = statBarId.replace('copyLinuxStatusBar', 'copyLinuxTab'); 
				
				// Go through output and append to paragraph
				var prg = $('<pre></pre>');
				for (var i in out) {
					if (out[i].length > 6) {
						prg.append(out[i] + '<br/>');
					}
				}
				$('#' + statBarId).find('div').append(prg);
				
				// Hide loader
				$('#' + statBarId).find('img').hide();
				// Enable inputs and buttons
				$('#' + tabId + ' input').attr('disabled', '');
				$('#' + tabId + ' button').attr('disabled', '');
			}
		});
	});
	
	/**
	 * Cancel
	 */
	var cancelBtn = createButton('Cancel');
	copyLinuxForm.append(cancelBtn);
	cancelBtn.bind('click', function(event) {
		// Close the tab
		tab.remove($(this).parent().parent().attr('id'));
	});

	tab.add(newTabId, 'Copy', copyLinuxForm, true);
	tab.select(newTabId);
}

/**
 * use users' input or select to create image
 * 
 * @param 
 *  
 * @return Nothing
 */
function createImage() {
	var osvers = $("#createImageTab #osvers").val();
	var osarch = $("#createImageTab #osarch").val();
	var profile = $("#createImageTab #profile").val();
	var bootInterface = $("#createImageTab #netbootif").val();
	var bootMethod = $("#createImageTab #bootmethod").val();

	$('#createImageTab .ui-state-error').remove();
	// If there no input for the bootInterface
	if (!bootInterface) {
		var warnBar = createWarnBar('Please specify the netboot interface');
		$("#createImageTab").prepend(warnBar);
		return;
	}

	var createImageArgs = "createimage;" + osvers + ";" + osarch + ";" + profile + ";" + bootInterface + ";" + bootMethod + ";";

	$("#createImageTab :checkbox:checked").each(function() {
		createImageArgs += $(this).attr("name") + ",";
	});

	createImageArgs = createImageArgs.substring(0, (createImageArgs.length - 1));
	$.ajax({
		url : 'lib/cmd.php',
		dataType : 'json',
		data : {
			cmd : 'webrun',
			tgt : '',
			args : createImageArgs,
			msg : ''
		},
		success : function(data) {
			
		}
	});
}