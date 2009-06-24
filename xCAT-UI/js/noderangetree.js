window.noderange="";
function updatenoderange() {
    myselection="";
    myselection=nrtree.selected_arr;
    window.noderange="";
    for (node in myselection) {
        window.noderange+=myselection[node][0].id;
    }
    window.noderange=window.noderange.substring(1);

    if (window.nodetabs) {
    	var index = window.nodetabs.data('selected.tabs');
		// todo: figure out a better way to determine if the current tab is one of those that needs to be reloaded with the new noderange
    	if (index == 0) {
    		//alert('here');
    		//window.nodetabs.tabs('select', index);	// simulate selecting it, so it reloads.  Did not work.
    		loadAttrTab($('#attributes-tab'));
    		}
    	if (index == 2) {
    		loadVitalsTab($('#rvitals-tab'));
    		}
    	}

}

function initTree() {
    nrtree = new tree_component(); // -Tree begin
    nrtree.init($("#nrtree"),{
        rules: { multiple: "Ctrl" },
        ui: { animation: 250 },
        callback : { onchange : printtree },
        data : {
            type : "json",
            async : "true",
            url: "noderangesource.php"
        }
    });  //Tree finish
}

function printtree (node,nrtree) {
	myselection=nrtree.selected_arr;
	var noderange="";
	for (node in myselection) {
		noderange+=myselection[node][0].id;
	}
	// find out what we're doing:
	// control? provision? ...?
	var page = $(".mapper span").text();
	// get what page we're on looking after the /
	page = page.slice(page.indexOf("/")+1);
	// strip all the white spaces
	page = page.replace(/\s+/g,'');

	if(page == 'control'){
		$("#nrcmdnoderange").text("Noderange: "+noderange.substring(1));
		$("#nrcmdcmd").text("Action:");
		$('#rangedisplay').load("rangeDisplay.php?t=control&nr="+noderange.substring(1));
		//update the window bar:
		window.location.hash = "control.php?nr="+noderange.substring(1);
	}else{
		// update noderange
		$("#nrcmdnoderange").text("Noderange: "+noderange.substring(1));
		$("#nrcmdmethod").text("Install Method:");
		$("#nrcmdos").text("Operating System:");
		$("#nrcmdarch").text("Architecture:");
		$("#nrcmdprofile").text("Profile:");

		$('#rangedisplay').load("rangeDisplay.php?t=provision&nr="+noderange.substring(1));
		//update the window bar:
		window.location.hash = "provision.php?nr="+noderange.substring(1);
	}
}
// load progress bar
myBar.loaded('noderangetree.js');
