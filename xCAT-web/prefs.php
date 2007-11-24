<?php
/*------------------------------------------------------------------------------
  Include files, insert header and menu bar
------------------------------------------------------------------------------*/

require_once "$TOPDIR/functions.php";	//NOTE: it is essential to include this file before include top.php and nav.php

insertHeader('Preferences', NULL, NULL);
insertNav('prefs');
if (isAIX()) { $aixDisabled = 'disabled'; }
?>
<FORM NAME="prefs">
<TABLE class="inner_table" cellspacing=0 cellpadding=5>
  <TBODY>
  	<TR>
      <TD colspan="3"><font class="BlueBack">Number of nodes per display: </font>
      <INPUT type="text" id="number_of_node" name="number_of_node"
      value="<?php if(@$_POST["number_of_node"] == "") echo "20"; else echo $_POST["number_of_node"];?>">
 	  </TD>
    </TR>
    <TR>
      <TD colspan="3"><p>
		<INPUT type="button" id="setPrefButton" name="setPrefButton" value="Set Preferences" class=middle onclick="checkEmpty();"></p>
      </TD>
    </TR>

  </TBODY>
</TABLE>
</FORM>
</TD>
</TR>
</TABLE>
<script type="text/javascript" src="function.js"> </script>
<SCRIPT language="JavaScript">
<!--

window.onload = function(){window.document.prefs.setPrefButton.focus()};

function checkEmpty(){
	var form = window.document.prefs;
	var number_of_node = form.number_of_node.value;
	if (number_of_node.length == 0)
	  {
	    alert('Enter a number before pressing the Set Preferences button.');
	    return false;
	  }
	else {
		setCookie('number_of_node',number_of_node);
		alert('Preferences set.');
		return true;
	}
}

-->
</SCRIPT>
</BODY>
</HTML>