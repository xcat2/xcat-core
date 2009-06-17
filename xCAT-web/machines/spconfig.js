function loadSPCfgTab(panel) {
	//alert('showing ping tab');
	var nr = '';
	if (window.noderange && window.noderange != "") {
		nr = window.noderange;
	}

	panel.children().remove();	//get rid of the previous contents
	panel.append('<p>Loading SP Config tab... <img src="../images/throbber.gif"></p>');
	panel.load('spconfig.php?noderange='+nr);
}
