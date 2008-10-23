// Create and show the dialog that shows the dsh output

$(document).ready(function() {
	var cmddialog = $('<div id=cmdDialog title=Title></div>');
    cmddialog.dialog({ height: 500, width: 400, autoOpen: false});

    $("input[type='text']").keypress(function(e) { if (isEnterKey(e.which)) {opencmddialog();} });
});


// Determine if the key pressed was the enter key.
// According to http://unixpapa.com/js/key.html, this is key code 13 in all browsers.
function isEnterKey(keycode) { if (keycode == 13) { return true; } else { return false; } }


// Called by the select combobox to put its value into the command field
function _setvars(){
	var form = window.document.dshForm;
	form.command.value = form.history.value;
}


// Pop open the dialog and fill it with the dsh output
function opencmddialog() {
	// Build the property list that will get POSTed
	var props = {};
	props.command = $('#command').val();
	props.nodegrps = $('#nodegrps option:selected').val();

	// If required fields were not filled in, bail
	if (props.command.length == 0 || props.nodegrps.length == 0) {
	    alert('Select a node group and enter a command before pressing the Run Cmd button.');
	    return;
	  }

	if ($('#nodeList')) { props.nodeList = $('#nodeList').val(); }

	if ($('#copy_script').attr('checked')) { props.copy_script = 1; }
	if ($('#run_psh').attr('checked')) { props.run_psh = 1; }
	if ($('#serial').attr('checked')) { props.serial = 1; }
	if ($('#monitor').attr('checked')) { props.monitor = 1; }
	if ($('#verify').attr('checked')) { props.verify = 1; }
	if ($('#collapse').attr('checked')) { props.collapse = 1; }

	var tmp = $('#fanout').val();
	if (tmp.length) { props.fanout = tmp; }
	var tmp = $('#userID').val();
	if (tmp.length) { props.userID = tmp; }
	var tmp = $('#rshell').val();
	if (tmp.length) { props.rshell = tmp; }
	var tmp = $('#shell_opt').val();
	if (tmp.length) { props.shell_opt = tmp; }

	if ($('#ret_code').attr('checked')) { props.ret_code = 1; }

	// Open the dialog and get the output sent to it
    $('#cmdDialog').children().remove();	// get rid of previous content
    $('#cmdDialog').dialog("open");
    $('#cmdDialog').load('dsh_action.php', props);
}
