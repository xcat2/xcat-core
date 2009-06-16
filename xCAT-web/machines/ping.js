// Javascript functions for the Ping tab

function loadPingTab(panel) {
	//alert('showing ping tab');
	var nr = '';
	if (window.noderange && window.noderange != "") {
		nr = window.noderange;
	}

	panel.children().remove();	//get rid of the previous contents
	panel.append('<p>Loading node ping... <img src="../images/throbber.gif"></p>');
	panel.load('ping.php?noderange='+nr);
}
