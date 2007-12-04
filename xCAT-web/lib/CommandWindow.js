var CommandWindow = {};

CommandWindow.updateCommandResult = function() {
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
