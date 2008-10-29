<?php

// Utility functions to help display a wizard.  Also use wizard.css.

/* Create an array that lists the page function names and the page titles...
$pages = array('one' => 'Page One',
				'two' => 'Page Two',
				'three' => 'Page Three',
				);
*/

function displayWizard($pages) {
$keys = array_keys($pages);

if (isset($_REQUEST['page'])) {		// navigate to another page in the wizard
	$page = $_REQUEST['page'];
	$action = $_REQUEST['action'];

	// Figure out the function for this page.  Search the keys.
	$k = array_search($page, $keys);
	if ($k === FALSE) { msg('E',"Page $page not found in the wizard."); exit; }
	if ($action == 'back') {
		$k--;
		if ($k < 0) { msg('E',"Can't go backward past the 1st page ($page)."); exit; }
	}
	elseif ($action == 'next') {
		$k++;
		if ($k >= count($pages)) { $k = 0; }	// this was the Finish button - go back to the beginning
	}
	elseif ($action == 'cancel') {
		$k = 0;
		//todo: unset all the _SESSION variables
	}

	// Run the function for this page
	$keys[$k]();
	configureButtons($k, $pages);
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
$keys[0]();
echo "</div>\n";		// end the inner wizard pane

// Add the wizard decorations
insertButtons(
		array('label' => 'Back', 'otherattrs' => 'id=backButton', 'onclick' => '$("#wizardPane").load("?page="+document.currentPage+"&action=back");'),
		array('label' => 'Next', 'otherattrs' => 'id=nextButton', 'onclick' => '$("#wizardPane").load("?page="+document.currentPage+"&action=next");'),
		array('label' => 'Cancel', 'onclick' => '$("#wizardPane").load("?page='.$keys[0].'&action=cancel");')
	);
configureButtons(0, $pages);
echo "</div>\n";		// end the outer wizard pane
}
}	// end of displayWizard()


//-----------------------------------------------------------------------------
// Disable buttons as appropriate and set current page
function configureButtons($k, $arr) {
$keys = array_keys($arr);
echo "<script type='text/javascript'>";

// Set the global variable so the buttons know which page this is
echo "document.currentPage='$keys[$k]';";

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
?>