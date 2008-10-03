<?php
/* session_start(); */
$TOPDIR = '..';
require_once "$TOPDIR/lib/functions.php";
insertHeader('xCAT Frames and Nodes', array('frames.css'), array('frames.js'), array('machines','frames'));
if (isAIX()) { $aixDisabled = 'disabled'; }

echo "<div id=content align=center><form name=frameForm class=ContentForm>\n";

insertButtons(
		array('label' => 'Attributes', 'onclick' => ''),
		array('label' => 'Create Group', 'onclick' => ''),
		array('label' => 'Ping', 'onclick' => ''),
		//'Updatenode',
		array('label' => 'Run Cmd', 'onclick' => ''),
		array('label' => 'Copy Files', 'onclick' => ''),
		array('label' => 'Sync Files', 'onclick' => '')
	);
insertButtons(
		//'Soft Maint',
		array('label' => 'HW Ctrl', 'onclick' => ''),
		array('label' => 'RSA/MM/FSP', 'onclick' => ''),
		array('label' => 'Deploy', 'onclick' => ''),
		array('label' => 'Diagnose', 'onclick' => ''),
		array('label' => 'Remove', 'onclick' => '')
	);

// Get the attributes for all nodes
$attrlist = array('nodepos.rack','nodepos.u','nodepos.chassis','nodepos.slot','nodepos.room','vpd.mtm','nodetype.arch','nodehm.power','nodehm.mgt','mp.mpa','mp.id');
$nodes = getNodes('/.*', $attrlist);
$frames = array();

// Process the node list & attrs to build the arrays we need for display: an array of frames.
// Each frame is an array where each index is a u # that has a machine it in.  If the machine
// is really a BC chassis, then the chassis array has the list of blades.
foreach ($nodes as $nodename => $attrs)	{
	$isBlade=0;

	// Get the display info for this node (image, size, etc.)
	$info = getHWInfo(array_key_exists('vpd.mtm',$attrs)?$attrs['vpd.mtm']:'',
					array_key_exists('nodehm.power',$attrs)?$attrs['nodehm.power']:'',
					array_key_exists('nodehm.mgt',$attrs)?$attrs['nodehm.mgt']:'');
	if (empty($info)) { continue; }
	$image = $info['rackimage'];
	$size = $info['u'];

	// Try to detect if this node is a MM
	if (array_key_exists('mp.mpa',$attrs) && $attrs['mp.mpa']==$nodename) { $isMM = 1; }
	else { $isMM = 0; }

	// If this is a blade, have to get the position from its MM
	if ($size == 7 && !$isMM) {     # blade
		$isBlade = 1;
		if (!array_key_exists('mp.mpa',$attrs) || !array_key_exists('mp.id',$attrs)) { continue; }
		if (!array_key_exists($attrs['mp.mpa'],$nodes)) { continue; }
		$mmattrs = & $nodes[$attrs['mp.mpa']];
		if (!array_key_exists('nodepos.rack',$mmattrs)) continue;
		$f = $mmattrs['nodepos.rack'];
		if (!array_key_exists('nodepos.u',$mmattrs)) continue;
		$u = $mmattrs['nodepos.u'];
		$slot = $attrs['mp.id'];
	}
	else {   # non-blade
		if (!array_key_exists('nodepos.rack',$attrs)) continue;
		$f = $attrs['nodepos.rack'];
		if (!array_key_exists('nodepos.u',$attrs)) continue;
		$u = $attrs['nodepos.u'];
		//echo "<p>nodename=$nodename, f=$f, u=$u</p>\n";
	}

	$alt = "$nodename:  U=$u";
	if ($isBlade) { $alt .= " Slot=$slot"; }

	// Choose the image for the node, based on the status
	if (array_key_exists('nodelist.status',$attrs)) $status = $attrs['nodelist.status'];
	else $status = 'unknown';
	$status = mapStatus($status);
	if ($status == 'good') { $image .= '-green.jpg'; }
	elseif ($status == 'bad') { $image .= '-red.jpg'; }
	elseif ($status == 'warning') { $image .= '-yellow.jpg'; }
	else { $image .= '-blue.jpg'; }

	// Create an array for each frame, using the u # as the index for the node
	if (!array_key_exists($f,$frames)) { $frames[$f] = array(); }    # start an array for this frame
	$frame = & $frames[$f];
	$findex = 43 - $u - ($size-1);
	if ($findex < 1) { $findex = 1; }
	if ($isBlade) {
		if (!array_key_exists($findex,$frame) || !array_key_exists('chassis',$frame[$findex])) { $frame[$findex] = array('nodename'=>$attrs['mp.mpa'], 'chassis'=>array(), 'size'=>$size); }
		$chassis = & $frame[$findex]['chassis'];
		$chassis[$slot] = array('nodename'=>$nodename, 'image'=>$image, 'alt'=>$alt);
	}
	else {		// this is either a regular svr or a BC chassis
		if ($isMM) {
			if (!array_key_exists($findex,$frame)) { $frame[$findex] = array('nodename'=>$nodename, 'chassis'=>array(), 'size'=>$size); }
		}
		else { $frame[$findex] = array('nodename'=>$nodename, 'image'=>$image, 'alt'=>$alt, 'size'=>$size); }
	}
}

echo "<TABLE class=AllRacksTable><TBODY valign=bottom><TR>\n";
# xSeries frames are 78.7in H x 23.6in W (3.3 ratio).  The server enclosure area is approx 71.4 x 19 (3.75 ratio).  Each U is approx 1.725

ksort($frames, SORT_NUMERIC);
foreach ($frames as $fnum => $frame) {
	echo "<TD><INPUT type=checkbox name=selAll${fnum}Checkbox onclick='selectAll(this,$fnum)'><B> Rack $fnum</B>\n";
	echo "<TABLE class=RackTable cellpadding=0 cellspacing=2><TBODY>\n";

	// Go thru each u position and either draw the svr or fill in an empty slot
	for ($i=1; $i<=42;) {
		if (array_key_exists($i,$frame)) {		# this slot has a server in it
			$u = & $frame[$i];		// $u is the machine info at that u #
			// $u has keys of (nodename, image, alt, size) for rack mounted and (nodename, chassis, size) for blades
			if (array_key_exists('chassis',$u)) {    # this a bladecenter chassis
				$chassis =  & $u['chassis'];   # this is really a ref to an array of blades
				echo "<TR><TD><TABLE class=RackTable cellpadding=0 cellspacing=1><TBODY><TR>\n";
				for ($j=1; $j<=14; $j++) {
					if (array_key_exists($j,$chassis)) {		// there is a blade in this slot
						$b = & $chassis[$j];		// keys in $b are:  nodename, image, alt
						$h = $b['nodename'];
						$im = $b['image'];
						$a = $b['alt'];
						echo "<TD><IMG src='$TOPDIR/images/unchecked-box.gif' alt='$fnum-$h' title='$fnum-$h' border=0 onclick='imageCBClick(this,2);'><BR>";
						echo "<IMG src='$TOPDIR/images/$im' alt='$a' title='$a' border=0></TD>\n";
					}
					else { echo "<TD class=RackEmptyCell height=25 width=12>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</TD>\n"; }  # empty blade slot
				}
				echo "</TR></TBODY></TABLE></TD></TR>\n";
			}
			else {   # this is regular rack mounted node
				$nodename = $u['nodename'];
				$image = $u['image'];
				$alt = $u['alt'];
				echo "<TR><TD><IMG src='$TOPDIR/images/unchecked-box.gif' alt='$fnum-$nodename' title='$fnum-$nodename' border=0 onclick='imageCBClick(this,2);'>";
				echo "<IMG src='$TOPDIR/images/$image' alt='$alt' title='$alt' border=0></TD></TR>\n";
			}
			$i += $u['size'];		// move up the height of this svr
		}
		else {   # empty slot
			echo "<TR><TD class=RackEmptyCell height=5 width=50></TD></TR>\n"; $i++;
		}
	}		// end of the for $i loop
	echo "</TBODY></TABLE></TD>\n";
}

echo "</TR></TBODY></TABLE>\n";
echo '</form></div>';
insertFooter();


//-----------------------------------------------------------------------------
// Use a variety of the attributes to try to figure out what kind of hw this is and return
// the info that should be displayed for this type of hw.  Gets this from functions::getHWTypeInfo()
function getHWInfo($mtm, $powermethod, $mgt) {
	# 1st try to match the Model-MachineType
	if (!empty($mtm)) {
		$model = explode('-', $mtm);
		$info = getHWTypeInfo($model[0]);
		if (isset($info)) { return $info; }
	}

	# No matches yet.  Use the power method to get a generic type.
	if (!empty($powermethod)) { $powermethod = $powermethod; }
	elseif (!empty($mgt)) { $powermethod = $mgt; }
	if (!empty($powermethod)) { return getHWTypeInfo($powermethod); }
	else { return NULL; }
}

?>
