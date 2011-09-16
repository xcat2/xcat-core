/**
 * Open login dialog
 */
$(document).ready(function() {
    $('#header').remove();
    $('#content').remove();
    
    var winHeight = document.body.clientHeight;
    var diagHeight = $('#logdialog').css('height');
    diagHeight = diagHeight.substr(0, diagHeight.length - 2);
    diagHeight = Number(diagHeight);
    
    // The window's height is to small to show the dialog
    var tmpHeight = 0;
    if ((winHeight - 50) < diagHeight){
    	tmpHeight = 0;
    } else {
    	tmpHeight = parseInt((winHeight - diagHeight - 50) / 2); 
    }
    
    $('#logdialog').css('margin', tmpHeight + 'px auto');
    $('button').bind('click', function(){
    	authenticate();
    }).button();
    
	if (document.location.protocol == 'http:') {
		$('#logstatus').html('You are using an unencrypted session!');
		$('#logstatus').css('color', 'red');
	}
	
	if (!$('#username').val()) {
		$('#username').focus();
	} else {
		$('#password').focus();
	}

	// When enter is hit while in username, advance to password
	$('#username').keydown(function(event) {
		if (event.keyCode == 13) {
			$('#password').focus();
		}
	});

	// Submit authentication if enter is pressed in password field
	$('#password').keydown(function(event) {
		if (event.keyCode == 13) {
			authenticate();
		}
	});
});

/**
 * Update login dialog
 * 
 * @param data
 *            Data returned from AJAX call
 * @param txtStatus
 *            Status of login
 */
function onlogin(data, txtStatus) {
	// Clear password field regardless of what happens
	var usrName = $('#username').val();
	$('#password').val('');
	if (data.authenticated == 'yes') {
		$('#logstatus').text('Login successful');
		window.location = 'service.php';
		
		// Set user name cookie		
		var exDate = new Date();
		exDate.setTime(exDate.getTime() + (240 * 60 * 1000));
		$.cookie('srv_usrname', usrName, { expires: exDate });
	} else {
		$('#logstatus').text('Authentication failure');
		$('#logstatus').css('color', '#FF0000');
	}
}

/**
 * Authenticate user for new session
 */
function authenticate() {
	$('#logstatus').css('color', '#000000');
	$('#logstatus').html('Authenticating...');
	
	var passwd = $('#password').val();
	$.post('lib/srv_log.php', {
		username : $('#username').val(),
		password : passwd
	}, onlogin, 'json');
}
