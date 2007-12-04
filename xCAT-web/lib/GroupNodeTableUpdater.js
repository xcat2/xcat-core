var GroupNodeTableUpdater = {};

/**
 * Hides/shows the nodes in a node group table.
 */
GroupNodeTableUpdater.toggleSection = function(nodeGroupName) {
	var tableId = "div_" + nodeGroupName;
	var imageId = tableId + '-im';
	var expandSpanId = "img_gr_" + nodeGroupName;

	var tableObj = $(tableId);

	if(null == tableObj) {
		alert('Error: section ' + tableId + ' not found.');
		return false;
	}

	var imageTag = $(imageId);
	var expandSpanObj = $(expandSpanId);

	if(!tableObj.style.display || tableObj.style.display == 'inline') {
		 // the inner table is currently visible
		tableObj.style.display = 'none';
		imageTag.src = "../images/plus-sign.gif";
		expandSpanObj.title = "Click to expand section";
	} else {
		// the inner table is currently invisible
		tableObj.style.display = 'inline';
		imageTag.src = "../images/minus-sign.gif";
		expandSpanObj.title = "Click to collapse section";
	}

	return true;
};

GroupNodeTableUpdater.getFailureSpanHTML = function(nodeGroupName) {
	var spanId = "nodegroup_" + nodeGroupName + "_failure";
	var html = '<span id="' + spanId + '">There was a problem loading the node for the group ' + nodeGroupName + '</span>';
	return html;
}

GroupNodeTableUpdater.getLoadingSpanHTML = function(nodeGroupName) {
	var spanId = "nodegroup_" + nodeGroupName + "_loading";
	var html = '<span id="' + spanId + '" style="padding-left: 0.5em; display: none;"><img alt="Loading ..." src="../images/ajax-loader.gif" /></span>';
	return html;
}

/**
 * This is the onCreate callback for the AJAX request made in GroupNodeTableUpdater.updateNodeList.
 * It updates the interface to show that the request is loading.
 * See http://www.prototypejs.org/api/ajax/options
 */
GroupNodeTableUpdater.updateNodeListLoading = function(nodeGroupName) {

	var spanId = 'img_gr_' + nodeGroupName;
	new Insertion.Bottom(spanId, GroupNodeTableUpdater.getLoadingSpanHTML(nodeGroupName));

	var loadingSpanId = "nodegroup_" + nodeGroupName + "_loading";
	new Effect.Appear(loadingSpanId);
}

/**
 * This is the onFailure callback for the AJAX request made in GroupNodeTableUpdater.updateNodeList.
 * It updates the interface to show that the request failed.
 * See http://www.prototypejs.org/api/ajax/options
 */
GroupNodeTableUpdater.updateNodeListFailure = function(nodeGroupName) {
	var spanId = 'img_gr_' + nodeGroupName;
	new Insertion.Bottom(spanId, GroupNodeTableUpdater.getFailureSpanHTML(nodeGroupName));

	var failureSpanId = "nodegroup_" + nodeGroupName + "_failure";
	new Effect.Shake(failureSpanId);
}

/**
 * Add table rows representing nodes to the table that represents the node group
 * identified by the given name.
 */
GroupNodeTableUpdater.updateNodeList = function(nodeGroupName) {

	var tableId = "div_" + nodeGroupName;
	var imageId = tableId + '-im';
	var expandSpanId = "img_gr_" + nodeGroupName;

	var tableObj = $(tableId);

	if(null == tableObj) {
		alert('Error: section ' + tableId + ' not found.');
		return false;
	}

	var imageTag = $(imageId);
	var expandSpanObj = $(expandSpanId);

	if(!tableObj.style.display || tableObj.style.display == 'inline') {// currently visible

		tableObj.style.display = 'none';
		imageTag.src = "../images/plus-sign.gif";
		expandSpanObj.title = "Click to expand section";

	} else { //currently invisible
		imageTag.src = "../images/minus-sign.gif";
		expandSpanObj.title = "Click to collapse section";

		var target = "div_" + nodeGroupName;
		var pars = 'nodeGroupName=' + nodeGroupName;
		var URL = 'nodes_by_group.php';

		// Check whether the table already exists and has already been updated?

		//alert('About to call Ajax.Updater');
		new Ajax.Updater(target, URL, {
			method: 'post', parameters: pars,
			onCreate: function() { GroupNodeTableUpdater.updateNodeListLoading(nodeGroupName) }, // Needs Prototype 1.5.1
			onFailure: function() {GroupNodeTableUpdater.updateNodeListFailure(nodeGroupName) },
			onComplete: function() {new Effect.Fade("nodegroup_" + nodeGroupName + "_loading")}
		});

		// the inner table is currently invisible
		tableObj.style.display = 'inline';
		//alert('Back from Ajax.Updater');

	}

	//return true;



	//GroupNodeTableUpdater.toggleSection(nodeGroupName);
}