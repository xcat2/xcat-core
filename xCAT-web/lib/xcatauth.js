/* xCAT WebUI authentication handling functions/setup */
/* IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html */

function onlogin (data, textstatus) {
    $("#password").val(""); //clear the password field regardless of what happens
    if (data.authenticated == "yes") {
        $("#logstatus").text("Logged in successfully");
        //todo: nrtree.refresh(); // Fix tree potentiall broken through attempts to operate without auth
        $("#logdialog").dialog("close");
        window.location = '../index.php';	// it has remembered what page they were trying to go to
    } else {
        $("#logstatus").text("Authentication failure");
        $("#logstatus").css("color","#ff0000");
    }
}

function authenticate() {
    $("#logstatus").css("color","#000000");
    $("#logstatus").html('Authenticating...<img src="../images/throbber.gif"/>');
    var passwd=$("#password").val();
    $.post("../lib/log.php",{
            username: $("#username").val(),
            password: passwd
        },onlogin,"json");
}

$(document).ready(function() {
    $("#logdialog").dialog({
        modal: true,
        closeOnEscape: false,
        closebutton: false,
        /* dialogClass: 'LogDialog', */
        overlay: {
            backgroundColor: "#CCCCCC",
            opacity: 0.3
        },
        height: 270,
        width: 350,
        autoOpen: true,
        buttons: {
            "Log In": authenticate
            },
        open: function(type, dialog) {
            if (document.location.protocol == "http:") {
                $("#logstatus").html("Unencrypted Session!");
                $("#logstatus").css("color","#ff0000");
            }
            if ($("#username").val() == "") {
                $("#username").focus();
            } else {
                $("#password").focus();
            }
        }
    });

    $("#username").keydown(function(event) { //When 'enter' is hit while in username, advance to password
        if (event.keyCode==13) {
            $("#password").focus();
        }
    });
    $("#password").keydown(function(event) { //Submit authentication if enter is pressed in password field
        if (event.keyCode==13) {
            authenticate();
        }
    });
});
