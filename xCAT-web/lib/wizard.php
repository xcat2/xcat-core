<?php

// Utility functions to help display a wizard.  Also use wizard.css.

/* Create an array that lists the page function names and the page titles...
$pages = array('one' => 'Page One',
				'two' => 'Page Two',
				'three' => 'Page Three',
				);
*/
require_once "$TOPDIR/jq/jsonwrapper.php";

function displayWizard($pages) {
$keys = array_keys($pages);

if (isset($_REQUEST['page'])) {		// navigate to another page in the wizard
	$page = $_REQUEST['page'];
	$action = $_REQUEST['action'];
	$step = (isset($_REQUEST['step']) ? $_REQUEST['step'] : 0);

	// Figure out the function for this page.  Search the keys.
	if ($action == 'cancel') {
		$k = 0;
		$step = 0;
		// should we unset all the _SESSION variables?
		}
	else {		// some action other than cancel
		$k = array_search($page, $keys);
		if ($k === FALSE) { msg('E',"Page $page not found in the wizard."); exit; }
		if ($action == 'back') {
			$k--;
			$step = 0;
			if ($k < 0) { msg('E',"Can't go backward past the 1st page ($page)."); exit; }
			}
		elseif ($action == 'next') {
			$k++;
			if ($k >= count($pages)) { $k = 0; }	// this was the Finish button - go back to the beginning
			}
		elseif ($action == 'step') {
			// do the next step on this page.  Both k and step are already set correctly.
			}
		}

	// Run the function for this page
	//dumpGlobals();
	if (isset($_REQUEST['output'])) { insertWizardOutputHeader(); }
	if ($action != 'step') configureButtons($k, $pages);
	$keys[$k]($action, $step);
}

else {		// initial display of the wizard - show the 1st page

echo "<div id=outerWizardPane>\n";
echo "<p id=wizardSummary>";
$text = array();
foreach ($keys as $k => $key) { $text[] = "<span id=$key class=NonCurrentSummaryItem>$pages[$key]</span>"; }
echo implode(' -> ', $text);
echo "</p>\n";
echo "<h2 id=wizardHeading>", $pages[$keys[0]], "</h2>\n";

echo "<div id=wizardPane>\n";
// The contents of the specific page goes in here
$keys[0]('next', 0);
echo "</div>\n";		// end the inner wizard pane

// Add the wizard decorations
insertButtons(
		array('label' => 'Back', 'id' => 'backButton', 'onclick' => 'wizardBack();'),
		array('label' => 'Next', 'id' => 'nextButton', 'onclick' => 'wizardNext();'),
		array('label' => 'Cancel', 'onclick' => 'wizardCancel();')
	);
configureButtons(0, $pages);
echo "</div>\n";		// end the outer wizard pane
}
}	// end of displayWizard()


//-----------------------------------------------------------------------------
// Disable buttons as appropriate and set current page
function configureButtons($k, $arr) {
$keys = array_keys($arr);
//echo "<p>currentPage=", $keys[$k], ".</p>\n";
echo "<script type='text/javascript'>";

// Set the global variable so the buttons know which page this is
echo "window.currentPage='$keys[$k]';";

// Move the summary indicator
echo '$("#wizardSummary span").removeClass("CurrentSummaryItem");';
echo '$("#wizardSummary #', $keys[$k], '").addClass("CurrentSummaryItem");';

// Change the title
echo '$("#wizardHeading").text("', $arr[$keys[$k]], '");';

// Adjust the buttons appropriately for this page
if ($k <= 0) { echo '$("#backButton").hide();'; }		// disable back button
else { echo '$("#backButton").show();'; }
if ($k >= (count($arr)-1)) { echo '$("#nextButton span").text("Finish");'; }		// disable next button
else { echo '$("#nextButton span").text("Next");'; }

echo "</script>\n";
}


//-----------------------------------------------------------------------------
// Display a list of tasks to be done.
function insertProgressTable($tasks) {
global $TOPDIR;
echo "<table class=WizardProgressTable><ul>\n";
foreach ($tasks as $k => $t) {
	if (is_array($t)) {
		$text = $t[0];
		$type = $t[1];
		}
	else {
		$text = $t;
		$type = 'onlyerrors';
		}
	if ($type == 'disabled') $cl = 'class=Disabled';
	else $cl = '';
	echo "<li id=step", $k+1, " $cl><p id=task><img id=chk src='$TOPDIR/images/unchecked-box.gif'>$text<img id=spinner src='$TOPDIR/images/invisible.gif' width=16 height=16></p>\n";
	if ($type == 'output') {
		echo "<iframe id=output></iframe></li>\n";
		}
	else { echo "<p id=output></p></li>\n"; }
	}
echo "</ul></table>\n";
}


//-----------------------------------------------------------------------------
// Instruct the client-side to move on to the next step in this page.
function nextStep($step, $done) {
// Was using JSON, but that is more difficult with all the utilities that can directly display errors they encounter.
//echo json_encode(array('step' => (integer)++$step, 'done' => FALSE, 'error' => ''));

$func = (isset($_REQUEST['output']) ? 'parent.wizardStep' : 'wizardStep');
echo "<script type='text/javascript'>", $func, "($step,", ($done?'true':'false'), ");</script>";
}


//-----------------------------------------------------------------------------
// Used for the html that we send to the iframe
function insertWizardOutputHeader() {
echo <<<EOS1
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1 Strict//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<LINK rel=stylesheet href='../lib/wizard.css' type='text/css'>
</head><body>

EOS1;
}

?>