/**
 * Get nodes currently shown in datatable
 * 
 * @param tableId
 *            Datatable ID
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
 * Find the row index containing a column with a given string
 * 
 * @param str
 *            String to search for
 * @param table
 *            Table to check
 * @param col
 *            Column to find string under
 * @return The row index containing the search string
 */
function findRow(str, table, col){
	var dTable, rows;
	
	// Get datatable
	dTable = $(table).dataTable();
	rows = dTable.fnGetData();
	
	// Loop through each row
	for (var i in rows) {
		// If the column contains the search string
		if (rows[i][col].indexOf(str) > -1) {
			return i;
		}
	}
	
	return -1;
}

/**
 * Select all checkboxes in the datatable
 * 
 * @param event
 *            Event on element
 * @param obj
 *            Object triggering event
 * @return Nothing
 */
function selectAll(event, obj) {
	var status = obj.attr('checked');
	var checkboxes = obj.parents('.dataTables_scroll').find('.dataTables_scrollBody input:checkbox');
	if (status) {
		checkboxes.attr('checked', true);
	} else {
		checkboxes.attr('checked', false);
	}
	
	event.stopPropagation();
}

/**
 * Get node attributes from HTTP request data
 * 
 * @param propNames
 *            Hash table of property names
 * @param keys
 *            Property keys
 * @param data
 *            Data from HTTP request
 * @return Hash table of property values
 */
function getAttrs(keys, propNames, data) {
	// Create hash table for property values
	var attrs = new Object();

	// Go through inventory and separate each property out
	var curKey; // Current property key
	var addLine; // Add a line to the current property?
	for ( var i = 1; i < data.length; i++) {
		addLine = true;

		// Loop through property keys
		// Does this line contains one of the properties?
		for ( var j = 0; j < keys.length; j++) {
			// Find property name
			if (data[i].indexOf(propNames[keys[j]]) > -1) {
				attrs[keys[j]] = new Array();

				// Get rid of property name in the line
				data[i] = data[i].replace(propNames[keys[j]], '');
				// Trim the line
				data[i] = jQuery.trim(data[i]);

				// Do not insert empty line
				if (data[i].length > 0) {
					attrs[keys[j]].push(data[i]);
				}

				curKey = keys[j];
				addLine = false; // This line belongs to a property
			}
		}

		// Line does not contain a property
		// Must belong to previous property
		if (addLine && data[i].length > 1) {
			data[i] = jQuery.trim(data[i]);
			attrs[curKey].push(data[i]);
		}
	}

	return attrs;
}

/**
 * Create a tool tip for comments
 * 
 * @param comment
 *            Comments to be placed in a tool tip
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
    		url : 'lib/srv_cmd.php',
    		dataType : 'json',
    		data : {
    			cmd : 'chdef',
    			tgt : '',
    			args : '-t;node;-o;' + node + ';usercomment=' + comments,
    			msg : 'out=manageTab;tgt=' + node
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
 * Open a dialog and show given message
 * 
 * @param type
 * 			Type of dialog, i.e. warn or info
 * @param msg
 * 			Message to show
 * @return Nothing
 */
function prompt(type, msg) {
	var style = {
		'display': 'inline-block',
		'margin': '5px',
		'vertical-align': 'middle'
	};
	msg.css({
		'display': 'inline',
		'margin': '5px',
		'vertical-align': 'middle'
	});
	
	// Append icon
	var icon;
	var dialog = $('<div></div>');
	if (type == "Warning") {
		icon = $('<span class="ui-icon ui-icon-alert"></span>').css(style);
	} else {
		icon = $('<span class="ui-icon ui-icon-info"></span>').css(style);
	}
	
	dialog.append(icon);
	dialog.append(msg);
		
	// Open dialog
	dialog.dialog({
		title: type,
		modal: true,
		width: 400,
		buttons: {
			"Ok": function(){ 
				$(this).dialog("close");
			}
		}
	});
}

/**
 * Get nodes that are checked in a given datatable
 * 
 * @param dTableId
 *            The datatable ID
 * @return Nodes that were checked
 */
function getNodesChecked(dTableId) {
	var tgts = '';

	// Get nodes that were checked
	var nodes = $('#' + dTableId + ' input[type=checkbox]:checked');
	for (var i in nodes) {
		var tgtNode = nodes.eq(i).attr('name');
		
		if (tgtNode){
			tgts += tgtNode;
			
			// Add a comma at the end
			if (i < nodes.length - 1) {
				tgts += ',';
			}
		}
	}

	return tgts;
}

/**
 * Show chdef output
 * 
 * @param data
 *            Data returned from HTTP request
 * @return Nothing
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
 * Get an attribute of a given node
 * 
 * @param node
 *            The node
 * @param attrName
 *            The attribute
 * @return The attribute of the node
 */
function getUserNodeAttr(node, attrName) {
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