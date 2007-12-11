<?php

// Allow the user to set preferences for this web interface.  The preferences are stored
// in the browsers cookie.

$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";

insertHeader('Preferences', NULL, NULL, array('config','prefs'));

echo "<FORM NAME=prefs onsubmit='return false'><TABLE class=inner_table cellspacing=0 cellpadding=5><TBODY>\n";

//foreach ($_COOKIE as $key => $value) { echo "<p>$key: {$_COOKIE[$key]}</p>\n"; }

echo "<tr><td colspan=2>\n";
insertButtons(array('label' => 'Set Preferences', 'onclick' => 'doSetPref()'));
echo " <span id=setMsg class=Info style='display: none'>Preferences set successfully</span></td></tr>\n";

$nodesPerPage = getPref('nodesPerPage');
echo "<TR><TD align=right><font class=BlueBack>Number of nodes to display per page:</font></td>\n";
echo "<td><INPUT type=text id=nodesPerPage name=nodesPerPage value='$nodesPerPage' onchange='doSetPref()'></TD></TR>\n";

$displayCmds = getPref('displayCmds');
$displayStr = $displayCmds ? 'checked' : '';
echo "<TR><TD align=right><font class=BlueBack>Display commands run by this interface:</font></td>\n";
echo "<td><INPUT type=checkbox id=displayCmds name=displayCmds $displayStr></TD></TR>\n";

//echo "<TR><TD colspan=3><INPUT type=button id=setPrefButton name=setPrefButton value='Set Preferences' class=middle onclick='doSetPref();'> <span id=setMsg class=Info style='display: none'>Preferences set successfully</span></TD></TR>\n";
echo "</TBODY></TABLE></FORM>\n";
echo <<<EOS
<SCRIPT language=JavaScript>
//window.onload = function(){window.document.prefs.setPrefButton.focus()};

function doSetPref(){
	var form = window.document.prefs;
	var cookies = getCookies();
	//for (c in cookies) { alert('cookies['+c+']='+cookies[c]); }
	//alert('cookies[nodesPerPage]='+cookies['nodesPerPage']);

	var nodesPerPage = form.nodesPerPage.value;
	if (nodesPerPage != cookies['nodesPerPage']) { setCookie('nodesPerPage',nodesPerPage,'/'); }

	var displayCmds = form.displayCmds.checked ? '1' : '0';
	if (displayCmds != cookies['displayCmds']) { setCookie('displayCmds',displayCmds,'/'); }

	document.getElementById('setMsg').style.display = 'inline';
	//return false;
}
</SCRIPT>
</BODY>
</HTML>
EOS;
?>