/**
 * Open login dialog
 */
$(document).ready(function() {
    $('#header').remove();
    $('#content').remove();
    
    var winheight = document.body.clientHeight;
    var diaheight = $('#logdialog').css('height');
    diaheight = diaheight.substr(0, diaheight.length - 2);
    diaheight = Number(diaheight);
    // the window's height is to small to show the dialog
    var tempheight = 0;
    if ((winheight - 50) < diaheight){
    	tempheight = 0;
    }
    else{
    	tempheight = parseInt((winheight - diaheight - 50) / 2); 
    }
    
    $('#logdialog').css('margin', tempheight + 'px auto');
    $('button').bind('click', function(){
    	authenticate();
    });
    
    $('button').button();
    
	if (document.location.protocol == "http:") {
		$("#logstatus").html("You are using an unencrypted session!");
		$("#logstatus").css("color", "#ff0000");
	}
	if ($("#username").val() == "") {
		$("#username").focus();
	} else {
		$("#password").focus();
	}

	// When enter is hit while in username, advance to password
	$("#username").keydown(function(event) {
		if (event.keyCode == 13) {
			$("#password").focus();
		}
	});

	// Submit authentication if enter is pressed in password field
	$("#password").keydown(function(event) {
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
 * @return
 */
function onlogin(data, txtStatus) {
	// Clear password field regardless of what happens
	$("#password").val("");
	if (data.authenticated == "yes") {
		$("#logstatus").text("Login successful");

		// Not the first time to log
		if ($.cookie('logonflag')){
			// Remembered what page they were trying to go to
	        window.location = window.location.pathname;
		} else {
		    window.location = 'guide.php';
		}
		
		// Set the logonflag
		$.cookie('logonflag', 'yes', {
		    path : '/xcat',
		    expires : 100
		});
		
	} else {
		$("#logstatus").text("Authentication failure");
		$("#logstatus").css("color", "#FF0000");
	}
}

/**
 * Authenticate user for new session
 * 
 * @return Nothing
 */
function authenticate() {
	$("#logstatus").css("color", "#000000");
	$("#logstatus").html('Authenticating...');
	var passwd = $("#password").val();
	$.post("lib/log.php", {
		username : $("#username").val(),
		password : passwd
	}, onlogin, "json");
}
