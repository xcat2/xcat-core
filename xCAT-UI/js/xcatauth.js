/* xCAT WebUI authentication handling functions/setup */
/* IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html */

function openlogdialog (data, textstatus) { //open the log in dialog if not logged in
	if (data.authenticated == "no") {
		$('#logdialog').dialog("open"); }
        else {
            $("#wrapper").show();
        }
}

function onlogin (data, textstatus) {
    $("#password").val(""); //clear the password field regardless of what happens
    if (data.authenticated == "yes") {
        $("#logstatus").text("Logged in successfully");
        //todo: nrtree.refresh(); // Fix tree potentiall broken through attempts to operate without auth
        $("#logdialog").dialog("close");
	$("#wrapper").show();
        //window.location = 'index.php';	// it has remembered what page they were trying to go to
    } else {
        $("#logstatus").text("Authentication failure");
        $("#logstatus").css("color","#ff0000");
    }
}

function logout() {
	$.post("security/log.php",{logout:1})
	$("#logstatus").html("");
	$("#wrapper").hide();	//hide the current page
	$("#logdialog").dialog("open");
}

function authenticate() {
	$("#logstatus").css("color","#000000");
	$("#logstatus").html('Authenticating...<img src="img/throbber.gif"/>');
	var passwd=$("#password").val();
	$.post("security/log.php",{
		username: $("#username").val(),
		password: passwd
	},onlogin,"json");
}

function helpAuth(){
	alert('Before a user can log on the username and password used must be configured in xCAT in two tables: \nIn most cases this is done by copying the user name and encrypted password from /etc/shadow and placing into the passwd table. E.g.:\n\n"xcat","xcatuser","$1bOK56A5o$6bChitpwsBjXTbjApzEHr/",,\n\nAfter that you need to give the user permissiones in the policy table.  E.g.:\n\n5,xcatuser,,,,,,allow,,');
}


// This doesn't happen on ready because this is loaded after the
// doc loads based on our new changes.
//$(document).ready(function() {
function openDialog(){
    $("#logdialog").dialog({
        modal: true,
        closeOnEscape: false,
        closebutton: false,
	draggable: false,
	resizable: false,
	title: 'xCAT Control Center',
        /* dialogClass: 'LogDialog', */
        overlay: {
            /* backgroundColor: "#2e2e2e", */
	    background: "#2e2e2e url(img/auth.gif) repeat",
            opacity: 1.0
        },
        height: 275,
        width: 350,
        autoOpen: true,
        buttons: {
	    "Help" : helpAuth,
            "Log In": authenticate
            },
        open: function(type, dialog) {
            /* if (document.location.protocol == "http:") {
                $("#logstatus").html("Unencrypted Session!");
                $("#logstatus").css("color","#ff0000"); 
            } */
            if ($("#username").val() == "") {
                $("#username").focus();
            } else {
                $("#password").focus();
            }
        }
    });

    $("#username").keydown(function(event) { //When 'enter' is hit while in username, advance to password
        if ((event.which && event.which == 13) || (event.keyCode && event.keyCode == 13)) {
            event.preventDefault();
            $("#password").focus();
        }
    });

    $("#password").keydown(function(event) { //Submit authentication if enter is pressed in password field
        if ((event.which && event.which == 13) || (event.keyCode && event.keyCode == 13)) {
            event.preventDefault();
            authenticate();
        }
    });

	$("#logout").click(function(event){
		logout();
	});
	$.post("security/log.php",{},openlogdialog,"json"); //Determine if authentication dialog is currently needed on load
}
openDialog();
//});
// for the progress bar
myBar.loaded('xcatauth.js');
