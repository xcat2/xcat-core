/**
 * Global variables
 */
var origAttrs = new Object();	// Original image attributes
var defAttrs; 					// Definable image attributes

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
	
	// Clear cookie containing list of images where their attributes 
	// need to be updated
	$.cookie('images2update', '');
	// Clear hash table containing image attributes
	origAttrs = '';
	// Clear hash table containing definable image attributes
	defAttrs = new Array();

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
	var dTable = new DataTable('imagesDataTable');
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
	var info = createInfoBar('Click on a cell to edit.  Click outside the table to write to the cell.  Hit the Escape key to ignore changes. Once you are satisfied with how the table looks, click on Save.');
	$('#imagesTab').append(info);

	// Create action bar
	var actionBar = $('<div class="actionBar"></div>');

	/**
	 * The following actions are available to perform against a given image:
	 * copy CD and set properties
	 */

	// Copy CDs
	var copyCdLnk = $('<a>Copy CDs</a>');
	copyCdLnk.bind('click', function(event) {
		loadCopyCdsPage();
	});
	
	// Set image properties
	var setProps = $('<a>Set properties</a>');
	setProps.bind('click', function(event){
		var tgtImages = getNodesChecked('imagesDataTable').split(',');
		for (var i in tgtImages) {
			 loadSetImagePropsPage(tgtImages[i]);
		}
	});
	
	/**
	 * Create an action menu
	 */
	var actionsDiv = $('<div></div>');
	var actions = [ copyCdLnk, setProps ];
	var actionMenu = createMenu(actions);
	actionMenu.superfish();
	actionsDiv.append(actionMenu);
	actionBar.append(actionsDiv);
	$('#imagesTab').append(actionBar);
	
	// Insert table
	$('#imagesTab').append(dTable.object());
	
	// Save changes
	var saveLnk = $('<a>Save</a>');
	saveLnk.bind('click', function(event){
		updateImageAttrs();
	});
	
	// Undo changes
	var undoLnk = $('<a>Undo</a>');
	undoLnk.bind('click', function(event){
		restoreImageAttrs();
	});

	/**
	 * Create menu to save and undo table changes
	 */
	// It will be hidden until a change is made
	var tableActionsMenu = createMenu([saveLnk, undoLnk]).hide();
	tableActionsMenu.css('margin-left', '490px');
	actionsDiv.append(tableActionsMenu);

	// Turn table into a datatable
	var myDataTable = $('#imagesDataTable').dataTable({
		'iDisplayLength': 50
	});
	
	// Set datatable width
	$('#imagesDataTable_wrapper').css({
		'width': '880px',
		'margin': '0px'
	});
	
	/**
	 * Enable editable columns
	 */
	// Do not make 1st, 2nd, 3rd, 4th, or 5th column editable
	$('#imagesDataTable td:not(td:nth-child(1),td:nth-child(2))').editable(
		function(value, settings) {	
			// Change text color to red
			$(this).css('color', 'red');
			
			// Get column index
			var colPos = this.cellIndex;
						
			// Get row index
			var dTable = $('#imagesDataTable').dataTable();
			var rowPos = dTable.fnGetPosition(this.parentNode);
			
			// Update datatable
			dTable.fnUpdate(value, rowPos, colPos);
			
			// Get image name
			var image = $(this).parent().find('td:eq(1)').text();
			
			// Flag image to update
			flagImage2Update(image);
			
			// Show table menu actions
			tableActionsMenu.show();

			return (value);
		}, {
			onblur : 'submit', 	// Clicking outside editable area submits
								// changes
			type : 'textarea',
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
 * Flag the image in the table to update
 * 
 * @param image
 *            The image name
 * @return Nothing
 */
function flagImage2Update(image) {
	// Get list containing current images to update
	var images = $.cookie('images2update');

	// If the node is not in the list
	if (images.indexOf(image) == -1) {
		// Add the new node to list
		images += image + ';';
		$.cookie('images2update', images);
	}
}

/**
 * Update the image attributes
 * 
 * @return Nothing
 */
function updateImageAttrs() {
	// Get the nodes datatable
	var dTable = $('#imagesDataTable').dataTable();
	// Get all nodes within the datatable
	var rows = dTable.fnGetNodes();
	
	// Get table headers
	var headers = $('#imagesDataTable thead tr th');
							
	// Get list of nodes to update
	var imagesList = $.cookie('images2update');
	var images = imagesList.split(';');
		
	// Create the arguments
	var args;
	var row, colPos, value;
	var attrName;
	// Go through each node where an attribute was changed
	for (var i in images) {
		if (images[i]) {
			args = '';
			
        	// Get the row containing the image name
        	row = getImageRow(images[i], rows);
        	$(row).find('td').each(function (){
        		if ($(this).css('color') == 'red') {
        			// Change color back to normal
        			$(this).css('color', '');
        			
        			// Get column position
        			colPos = $(this).parent().children().index($(this));
        			// Get column value
        			value = $(this).text();
        			
        			// Get attribute name
        			attrName = jQuery.trim(headers.eq(colPos).text());
        			
        			// Build argument string
        			if (args) {
        				// Handle subsequent arguments
        				args += ';' + attrName + '=' + value;
        			} else {
        				// Handle the 1st argument
        				args += attrName + '=' + value;
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
        			args : '-t;osimage;-o;' + images[i] + ';' + args,
        			msg : 'out=imagesTab;node=' + images[i]
        		},

        		success: showChdefOutput
        	});
		} // End of if
	} // End of for
	
	// Clear cookie containing list of images where
	// their attributes need to be updated
	$.cookie('images2update', '');
}

/**
 * Restore image attributes to their original content
 * 
 * @return Nothing
 */
function restoreImageAttrs() {
	// Get list of images to restore
	var imagesList = $.cookie('images2update');
	var images = imagesList.split(';');
	
	// Get the image datatable
	var dTable = $('#imagesDataTable').dataTable();
	// Get table headers
	var headers = $('#imagesDataTable thead tr th');
	// Get all nodes within the datatable
	var rows = dTable.fnGetNodes();
		
	// Go through each node where an attribute was changed
	var row, colPos;
	var attrName, origVal;
	for (var i in images) {
		if (images[i]) {			
			// Get the row containing the image name
        	row = getImageRow(images[i], rows);
        	$(row).find('td').each(function (){
        		if ($(this).css('color') == 'red') {
        			// Change color back to normal
        			$(this).css('color', '');
        			
        			// Get column position
        			colPos = $(this).parent().children().index($(this));	        			
        			// Get attribute name
        			attrName = jQuery.trim(headers.eq(colPos).text());
        			// Get original content
        			origVal = origAttrs[images[i]][attrName];
        			
        			// Update column
        			rowPos = findRowIndexUsingCol(images[i], '#imagesDataTable', 1);
        			dTable.fnUpdate(origVal, rowPos, colPos);
        		}
        	});
		} // End of if
	} // End of for
	
	// Clear cookie containing list of images where
	// their attributes need to be updated
	$.cookie('images2update', '');
}

/**
 * Find the row index using a column search value
 * 
 * @param searchStr
 *            String to search for
 * @param table
 *            Table to check
 * @param col
 *            Column to find string under
 * @return The row index containing the image name
 */
function findRowIndexUsingCol(searchStr, table, col){
	var dTable, rows, cols;
	
	// Get datatable
	dTable = $(table).dataTable();
	rows = dTable.fnGetData();
	
	// Loop through each row
	for (var i = 0; i < rows.length; i++) {
		// Get columns in row
		cols = dTable.fnGetData(i);
		// If column contains string
		if ( cols[col] == searchStr ) {
			// Return index
			return i;
		}
	}
	
	return -1;
}

/**
 * Set definable image attributes
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
 */
function setImageDefAttrs(data) {
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
    			
    			// Set hash table where key = attribute name and value = description
        		defAttrs[key] = descr;
			} else {				
				// Append description to hash table
				defAttrs[key] = defAttrs[key] + '\n' + attr;
			}
		} // End of if
	} // End of for
}

/**
 * Load set image properties page
 * 
 * @param tgtImage
 *            Target image to set properties
 * @return Nothing
 */
function loadSetImagePropsPage(tgtImage) {
	// Get nodes tab
	var tab = getProvisionTab();

	// Generate new tab ID
	var inst = 0;
	var newTabId = 'setImagePropsTab' + inst;
	while ($('#' + newTabId).length) {
		// If one already exists, generate another one
		inst = inst + 1;
		newTabId = 'setImagePropsTab' + inst;
	}

	// Open new tab
	// Create set properties form
	var setPropsForm = $('<div class="form"></div>');

	// Create status bar
	var barId = 'setImagePropsStatusBar' + inst;
	var statBar = createStatusBar(barId);
	statBar.hide();
	setPropsForm.append(statBar);

	// Create loader
	var loader = createLoader('setImagePropsLoader' + inst);
	statBar.append(loader);

	// Create info bar
	var infoBar = createInfoBar('Choose the properties you wish to change on the node. When you are finished, click Save.');
	setPropsForm.append(infoBar);

	// Create an input for each definable attribute
	var div, label, input, descr, value;
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
		input = $('<input type="text" value="' + value + '" title="' + defAttrs[key] + '"/>').css('margin-top', '5px');
		
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
		position: "center right",	// Place tooltip on the right edge
		offset: [-2, 10],	// A little tweaking of the position
		effect: "fade",		// Use the built-in fadeIn/fadeOut effect
		opacity: 0.8		// Custom opacity setting
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
		
		// Send command to change node attributes
    	$.ajax( {
    		url : 'lib/cmd.php',
    		dataType : 'json',
    		data : {
    			cmd : 'chdef',
    			tgt : '',
    			args : '-t;osimage;-o;' + tgtImage + ';' + args,
    			msg : 'out=' + newTabId + ';node=' + tgtImage
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
	tab.add(newTabId, 'Properties', setPropsForm, true);

	// Select new tab
	tab.select(newTabId);
}

/**
 * Get row element that contains given image
 * 
 * @param tgtImage
 *            Image to find
 * @param rows
 *            Rows within the datatable
 * @return Row element
 */
function getImageRow(tgtImage, rows) {
	// Find the row
	for (var i in rows) {
		// Get all columns within the row
		var cols = rows[i].children;
		// Get the 1st column (image name)
		var image = cols[1].innerHTML;

		// If the node matches the target node
		if (image == tgtImage) {
			// Return the row
			return rows[i];
		}
	}

	return;
}

/**
 * Load copy CDs page
 * 
 * @return Nothing
 */
function loadCopyCdsPage() {
	// Get provision tab
	var tab = getProvisionTab();

	// Generate new tab ID
	var inst = 0;
	newTabId = 'copyCdsTab' + inst;
	while ($('#' + newTabId).length) {
		// If one already exists, generate another one
		inst = inst + 1;
		newTabId = 'copyCdsTab' + inst;
	}
	
	// Create info bar
	var infoBar = createInfoBar('Copy Linux distributions and service levels from CDs/DVDs to install directory');

	// Create copy CDs form
	var copyCdsForm = $('<div class="form"></div>');
	copyCdsForm.append(infoBar);
	
	// Create file input
	var file = $('<div></div>');
	var label = $('<label>File:</label>').css('vertical-align', 'middle');
	var input = $('<input type="text" id="file" name="file"/>').css('width', '300px');
	file.append(label);
	file.append(input);
	copyCdsForm.append(file);
	
	// Create select button
	var selectBtn = createButton('Select');
	file.append(selectBtn);
	// Browse server directory and files
	selectBtn.serverBrowser({
		onSelect: function(path) {
            $('#file').val(path);
        },
        onLoad: function() {
            return $('#file').val();
        },
        knownExt: ['exe', 'js', 'txt'],
        knownPaths: [{text:'Install', image:'desktop.png', path:'/install'}],
        imageUrl: 'images/',
        systemImageUrl: 'images/',
        handlerUrl: 'lib/getpath.php',
        title: 'Browse',
        basePath: '',
        requestMethod: 'POST',
        width: '500',
        height: '300',
        basePath: '/install'
    });
	
	// Create copy button
	var copyBtn = createButton('Copy');
	copyCdsForm.append(copyBtn);
	
	// Create cancel button
	var cancelBtn = createButton('Cancel');
	copyCdsForm.append(cancelBtn);
	cancelBtn.bind('click', function(event) {
		// Close the tab
		tab.remove($(this).parent().parent().attr('id'));
	});

	tab.add(newTabId, 'Copy', copyCdsForm, true);
	tab.select(newTabId);
}