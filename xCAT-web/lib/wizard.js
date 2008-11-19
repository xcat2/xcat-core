// Javascript functions for wizards

window.wizardProps = {};		// global var to hold properties we are collecting

function wizardNext() {
window.wizardProps = { page: window.currentPage, action: 'next'};
addFormValues();
$("#wizardPane").load("?a=1", window.wizardProps);
}

function wizardBack() {
window.wizardProps = { page: window.currentPage, action: 'back'};
addFormValues();
$("#wizardPane").load("?a=1", window.wizardProps);
}

function wizardCancel() {
var props = { page: 0, action: 'cancel'};
$("#wizardPane").load("?a=1", props);
}


// Repeatedly make a json call to the server until it tells us there are no more steps
function wizardStep(step, done) {
// Mark the previous step as complete
if (step > 1) {
	var prevstep = step -1;
	$(".WizardProgressTable #step"+prevstep+" #task").removeClass("WizardProgressCurrent");
	$(".WizardProgressTable #step"+prevstep+" #chk").attr('src','../images/checked-box.gif');
	//$(".WizardProgressTable #step"+prevstep+" #spinner").hide();
	$(".WizardProgressTable #step"+prevstep+" #spinner").attr('src', '../images/invisible.gif');
	}

if (done) { return; }
//alert('here');

// Make the current item bold
$(".WizardProgressTable #step"+step+" #task").addClass("WizardProgressCurrent");
//$(".WizardProgressTable #step"+step).append("<img id=spinner src='../images/throbber.gif'/>");
$(".WizardProgressTable #step"+step+" #spinner").attr('src', '../images/throbber.gif');

// Do the next step
var props = { page: window.currentPage, action: 'step', step: step };
//alert('props page:'+props.page+ ' action:'+props.action+' step:'+props.step);

/*
jQuery.post('?a=1', props, function(json, textStatus) {
	wizardStep(json.step, json.done, json.error);
	}, 'json');
*/
// Decide if this task has a P or IFRAME for the output and invoke the function appropriately.
var output = $(".WizardProgressTable #step"+step+" #output");
if (output.is('IFRAME')) { output.attr('src','?page='+props.page+'&action='+props.action+'&step='+props.step+'&output=1'); }
else { output.load("?a=1", props); }
}


// Get the values from all of the form elements in this page of the wizard and add
// it to wizardProps.
function addFormValues() {
$("#wizardPane INPUT[type='text']").each(function (i) {
	window.wizardProps[this.id] = this.value;
	});
$("#wizardPane INPUT[type='checkbox']").each(function (i) {
	window.wizardProps[this.id] = this.checked ? 1 : 0;
	});
}
