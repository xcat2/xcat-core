window.noderange="";
function updatenoderange() {
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
        if (index == 3) {
            loadRpowerTab($('#rpower-tab'));
        }

}

$(document).ready(function() {

    nrtree = new tree_component(); // -Tree begin
    nrtree.init($("#nrtree"),{
        rules: { multiple: "Ctrl" },
        ui: { animation: 250 },
        callback : { onchange : updatenoderange },
        data : {
            type : "json",
            async : "true",
            url: "noderangesource.php"
        }
    });  //Tree finish
});
