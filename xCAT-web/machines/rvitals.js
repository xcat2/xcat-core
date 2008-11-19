// Javascript functions for the Rvitals/rinv tab

function loadVitalsTab(panel) {
	//alert('showing vitals tab');
	var nr = '';
	if (window.noderange && window.noderange != "") { nr = window.noderange; }
	panel.children().remove();	// get rid of previous content
	panel.append('<p>Loading node vitals... <img src="../images/throbber.gif"></p>');
	panel.load('rvitals.php?noderange='+nr);
}