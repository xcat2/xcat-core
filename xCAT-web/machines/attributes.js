// Javascript functions for the Attributes tab

function attrReady() {
}

function loadAttrTab(panel) {
	//alert('showing attr tab: '+ui.tab.href);
	var nr = '';
	if (window.noderange && window.noderange != "") { nr = window.noderange; }
	panel.children().remove();	// get rid of previous content
	panel.append('<p>Loading node attributes...</p>');
	panel.load('attributes.php?noderange='+nr);
}