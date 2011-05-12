/**
 * Open login dialog
 */
$(document).ready(function() {
	$("#logdialog").dialog( {
		modal : true,
		closeOnEscape : false,
		closebutton : false,
		height : 300,
		width : 350,
		autoOpen : true,
		buttons : {
			"Log in" : authenticate
		},
		open : function(type, dialog) {
			if (document.location.protocol == "http:") {
				$("#logstatus").html("You are using an unencrypted session!");
				$("#logstatus").css("color", "#ff0000");
			}
			if ($("#username").val() == "") {
				$("#username").focus();
			} else {
				$("#password").focus();
			}
		}
	});

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
		$("#logdialog").dialog("close");

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
