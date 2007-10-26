var XCATui = {};

XCATui.updateCommandResult = function() {
	var commandQueryId = "commandQuery";
	var copyChkBoxId = "copyChkBox";
	var nodenameHiddenTxtId = "nodename";
	var nodegrpsCboBoxId = "nodegrpsCboBox";
	var pshChkBoxId = "pshChkBox";

	var serialChkBoxId = "serialChkBox";
	var verifyChkBoxId = "verifyChkBox";
	var fanoutTxtBoxId = "fanoutTxtBox";
	var userIDTxtBoxId = "userIDTxtBox";
	var rshellTxtBoxId = "rshellTxtBox";
	var rshellTxtBoxId = "rshellTxtBox";
	var monitorChkBoxId = "monitorChkBox";
	var ret_codeChkBoxId = "ret_codeChkBox";

	var copyChkBoxObj = $(copyChkBoxId);
	var commandQueryObj = $(commandQueryId);
	var nodenameHiddenTxtObj = $(nodenameHiddenTxtId);
	var nodegrpsCboBoxObj = $(nodegrpsCboBoxId);
	var pshChkBoxObj = $(pshChkBoxId);

	var serialChkBoxObj = $(serialChkBoxId);
	var verifyChkBoxObj = $(verifyChkBoxId);
	var fanoutTxtBoxObj = $(fanoutTxtBoxId);
	var userIDTxtBoxObj = $(userIDTxtBoxId);
	var rshellTxtBoxObj = $(rshellTxtBoxId);
	var monitorChkBoxObj = $(monitorChkBoxId);
	var ret_codeChkBoxObj = $(ret_codeChkBoxId);

	// Do AJAX call and get HTML here.
	var url = "dsh_action.php";
	var postPara = "command=" + encodeURIComponent(commandQueryObj.value);
	postPara += "&node=" + encodeURIComponent(nodenameHiddenTxtObj.value);
	postPara += "&nodegrps=" + encodeURIComponent(nodegrpsCboBoxObj.options[nodegrpsCboBoxObj.selectedIndex].value);
	if (copyChkBoxObj.checked == true)	postPara += "&copy=on";	else postPara += "&copy=off";
	if (pshChkBoxObj.checked == true)	postPara += "&psh=on";	else postPara += "&psh=off";
	if (serialChkBoxObj.checked == true)	postPara += "&serial=on"; else postPara += "&serial=off";
	if (verifyChkBoxObj.checked == true)	postPara += "&verify=on"; else postPara += "&verify=off";
	postPara += "&fanout=" + encodeURIComponent(fanoutTxtBoxObj.value);
	postPara += "&userID=" + encodeURIComponent(userIDTxtBoxObj.value);
	postPara += "&rshell=" + encodeURIComponent(rshellTxtBoxObj.value);
	if (monitorChkBoxObj.checked == true)	postPara += "&monitor=on"; else postPara += "&monitor=off";
	if (ret_codeChkBoxObj.checked == true)	postPara += "&ret_code=on"; else postPara += "&ret_code=off";

	new Ajax.Request(url, {
	  method: 'post', postBody: postPara,
	  onSuccess: function(transport) {
    	var htmlContent = transport.responseText;

		 var win = new Window({className: "dialog",
		 			width: 350,
		 			height: 400,
		 			zIndex: 100,
		 			resizable: true,
		 			title: "Running commands",
		 			showEffect: Effect.BlindDown,
		 			hideEffect: Effect.SwitchOff,
		 			draggable: true,
		 			wiredDrag: true});

		 win.getContent().innerHTML = htmlContent;
		 //win.setStatusBar("Status bar info");
		 win.showCenter();
	  }
	});
};

/**
 * Hides/shows the nodes in a node group table.
 */
XCATui.toggleSection = function(nodeGroupName) {
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
		imageTag.src = "./images/plus-sign.gif";
		expandSpanObj.title = "Click to expand section";
	} else {
		// the inner table is currently invisible
		tableObj.style.display = 'inline';
		imageTag.src = "./images/minus-sign.gif";
		expandSpanObj.title = "Click to collapse section";
	}

	return true;
};

XCATui.getFailureSpanHTML = function(nodeGroupName) {
	var spanId = "nodegroup_" + nodeGroupName + "_failure";
	var html = '<span id="' + spanId + '">There was a problem loading the node for the group ' + nodeGroupName + '</span>';
	return html;
}

XCATui.getLoadingSpanHTML = function(nodeGroupName) {
	var spanId = "nodegroup_" + nodeGroupName + "_loading";
	var html = '<span id="' + spanId + '" style="padding-left: 0.5em; display: none;"><img alt="Loading ..." src="./images/ajax-loader.gif" />Loading ...</span>';
	return html;
}

/**
 * This is the onCreate callback for the AJAX request made in XCATui.updateNodeList.
 * It updates the interface to show that the request is loading.
 * See http://www.prototypejs.org/api/ajax/options
 */
XCATui.updateNodeListLoading = function(nodeGroupName) {

	var spanId = 'img_gr_' + nodeGroupName;
	new Insertion.Bottom(spanId, XCATui.getLoadingSpanHTML(nodeGroupName));

	var loadingSpanId = "nodegroup_" + nodeGroupName + "_loading";
	new Effect.Appear(loadingSpanId);
}

/**
 * This is the onFailure callback for the AJAX request made in XCATui.updateNodeList.
 * It updates the interface to show that the request failed.
 * See http://www.prototypejs.org/api/ajax/options
 */
XCATui.updateNodeListFailure = function(nodeGroupName) {
	var spanId = 'img_gr_' + nodeGroupName;
	new Insertion.Bottom(spanId, XCATui.getFailureSpanHTML(nodeGroupName));

	var failureSpanId = "nodegroup_" + nodeGroupName + "_failure";
	new Effect.Shake(failureSpanId);
}

/**
 * Add table rows representing nodes to the table that represents the node group
 * identified by the given name.
 */
XCATui.updateNodeList = function(nodeGroupName) {

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
		imageTag.src = "./images/plus-sign.gif";
		expandSpanObj.title = "Click to expand section";

	} else { //currently invisible
		imageTag.src = "./images/minus-sign.gif";
		expandSpanObj.title = "Click to collapse section";

		var target = "div_" + nodeGroupName;
		var pars = 'nodeGroupName=' + nodeGroupName;
		var URL = 'nodes_by_group.php';

		// Check whether the table already exists and has already been updated?

		//var URL = "webservice.php?method=getXCATNodeRows&nodeGroupName=" + encodeURIComponent(nodeGroupName);

		new Ajax.Updater(target, URL, {
			method: 'post', parameters: pars,
			onCreate: function() { XCATui.updateNodeListLoading(nodeGroupName) }, // Needs Prototype 1.5.1
			onFailure: function() {XCATui.updateNodeListFailure(nodeGroupName) },
			onComplete: function() {new Effect.Fade("nodegroup_" + nodeGroupName + "_loading")}
		});

		// the inner table is currently invisible
		tableObj.style.display = 'inline';

	}

	//return true;



	//XCATui.toggleSection(nodeGroupName);
}