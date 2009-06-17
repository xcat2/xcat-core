// Javascript functions for the Ping tab

function loadCopyTab(panel) {
	//alert('showing Copy tab');
	var nr = '';
	if (window.noderange && window.noderange != "") {
		nr = window.noderange;
	}

	panel.children().remove();	//get rid of the previous contents
	panel.append('<p>Loading Copy tab... <img src="../images/throbber.gif"></p>');
	panel.load('copyfiles.php?noderange='+nr);
}

