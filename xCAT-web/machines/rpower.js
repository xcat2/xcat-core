// Javascript functions for the Rpower tab

function loadRpowerTab(panel) {
	//alert('showing rpower tab');
	var nr = '';
	if (window.noderange && window.noderange != "") {
		nr = window.noderange;
	}

	panel.children().remove();	//get rid of the previous contents
	panel.append('<p>Loading node rpower... <img src="../images/throbber.gif"></p>');
	panel.load('rpower.php?noderange='+nr);
}
