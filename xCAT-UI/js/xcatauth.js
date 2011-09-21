/**
 * Open login dialog
 */
$(document).ready(function() {
    $('#header').remove();
    $('#content').remove();
    
    var winheight = document.body.clientHeight;
    var diaheight = $('#login').css('height');
    diaheight = diaheight.substr(0, diaheight.length - 2);
    diaheight = Number(diaheight);
    
    // The window's height is to small to show the dialog
    var tempheight = 0;
    if ((winheight - 50) < diaheight){
    	tempheight = 0;
    } else {
    	tempheight = parseInt((winheight - diaheight - 50) / 2); 
    }
    
    $('#login').css('margin', tempheight + 'px auto');
    $('button').bind('click', function(){
    	authenticate();
    });
    
    $('#login button').button();
    
	if (document.location.protocol == "http:") {
		$("#login_status").html("You are using an unencrypted session!");
		$("#login_status").css("color", "#ff0000");
	}
	
	if ($("#login input[name='username']").val() == "") {
		$("#login input[name='username']").focus();
	} else {
		$("#login input[name='password']").focus();
	}

	// When enter is hit while in username, advance to password
	$("#login input[name='username']").keydown(function(event) {
		if (event.keyCode == 13) {
			$("#login input[name='password']").focus();
		}
	});

	// Submit authentication if enter is pressed in password field
	$("#login input[name='password']").keydown(function(event) {
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
	$("#login input[name='password']").val("");
	if (data.authenticated == "yes") {
		$("#login_status").text("Login successful");

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
		$("#login_status").text("Authentication failure").css("color", "#FF0000");
	}
}

/**
 * Authenticate user for new session
 * 
 * @return Nothing
 */
function authenticate() {
	$("#login_status").css("color", "#000000");
	$("#login_status").html('Authenticating...');
	var passwd = $("#login input[name='password']").val();
	$.post("lib/log.php", {
		username : $("#login input[name='username']").val(),
		password : passwd
	}, onlogin, "json");
}
