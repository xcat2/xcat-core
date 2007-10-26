/**
 * This file registers event listeners using Prototype's
 * Event API.
 *
 * See:
 * * http://www.prototypejs.org/api/event/
 * * http://www.prototypejs.org/api/event/observe
 */

var XCATEvent = {};

XCATEvent.doAll = function() {
	Event.observe(window, 'load', function() {
		// Add other functions here
		XCATEvent.doRunCmdButton();	// dsh.php: Run Cmd button is clicked
		//XCATEvent.doExpandNodes();	// index.php: plus sign is click to expand node group
	});
};

/**
 * Register JS function with events for the RunCmdButton
 */
XCATEvent.doRunCmdButton = function() {
	Event.observe('runCmdButton_top', 'click', function(event) {
		XCATui.updateCommandResult();
	});
	Event.observe('runCmdButton_bottom', 'click', function(event) {
		XCATui.updateCommandResult();
	});
};

/**
 * Register JS function with events to retrieve nodes of a group
 */
XCATEvent.doExpandNodes = function() {
	/*var img_id;
	for (var i = 0; i<document.nodelist.elements.length; i++) {
        if ((document.nodelist.elements[i].id.indexOf('img_gr_') > -1)) {
        	img_id = document.nodelist.elements[i].id;
        	group_name = img_id.substring(7,img_id.length-3); //the image id is of the form "img_gr_groupname-im"
            Event.observe(img_id, 'click', function(event) {
			XCATui.updateNodeList(group_name);
			});
        }
    }*/

    for (var i = 0; i<document.nodelist.elements.length; i++) {
    	//if (document.nodelist.elements[i].id == 'img_gr_all-im')
    		//alert(document.nodelist.elements[i].id);
    }

    //Event.observe('img_gr_all-im', 'click', function(event) {
			//XCATui.updateNodeList('img_gr_all-im');
			//});


};