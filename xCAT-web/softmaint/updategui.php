<?php
/* session_start(); */
$TOPDIR = '..';
require_once "$TOPDIR/functions.php";
insertHeader('Update xCAT Web Interface', $TOPDIR, '', '');
insertNav('updategui', $TOPDIR);

?>

<div id=content>
<P id=logo><IMG class=Middle src="<?= $TOPDIR ?>/images/xcatlogo.gif"></P>
<FORM name=updateguiForm action="updategui.php" class=NoMargin>

<?php
getPkg();
?>

</FORM>
</div>
</body>
</HTML>



<?php
// Find, download, and install the xcat.web pkg
function getPkg() { //------------------------------------
	$rpmname = 'xcat.web';
	$tmpdir = '/tmp/xcat';

	echo "<ul>\n";
	echo "<li class=Info>Searching for the xCAT Web Interface download site...</li>\n";
	$site = findSite();
	echo "<li class=Info>Selected site ${site['dir']}.  Searching for the $rpmname RPM...</li>\n";
	$pkg = findPkg($site['dir'], $rpmname);
	if (!$pkg) { echo "</ul><p class=Error>Can not find $rpmname in ${site['dir']}.</p>\n"; return; }
	echo "<li class=Info>Latest RPM version available is $pkg.</li>\n";
	if (isInstalled($pkg)) { echo "<li class=Info>$pkg (or higher) is already installed.</li>\n"; return; }
	echo "<li class=Info>Downloading $pkg ...</li>\n";
	if (!downloadPkg($site['download'], $pkg, $tmpdir)) { echo "</ul><p class=Error>Error downloading $pkg from ${site['download']}.</p>\n"; return; }
	echo "<li class=Info>Download complete.  Installing $pkg ...</li>\n";
	$rc = installPkg("$tmpdir/$pkg");
	if ($rc) { echo "</ul><p class=Error>Installation of $pkg failed with rc=$rc.</p>\n"; }
	echo "<li class=Info>Installation of $pkg completed successfully.</li>\n";
	echo "</ul>\n";

	//dumpGlobals();
	//runcmd('/WINDOWS/system32/ipconfig', 1);
}


// Install the specified rpm
function installPkg($pkgname) { //------------------------------------
	$aixrpmopt = isAIX() ? '--ignoreos' : '';
	$rc = runcmd("/bin/rpm -U $aixrpmopt $pkgname", 1);
	return $rc;
}


// Download the specified rpm from the specified url and put it in the specified dir
function downloadPkg($url, $rpmname, $tmpdir) { //------------------------------------
	//trace("copy($url/$rpmname, $tmpdir/$rpmname)");
	$result = copy("$url/$rpmname", "$tmpdir/$rpmname");
	return $result;
}


// At the chosen site, find the latest version of xcat.web
function findPkg($url, $rpmname) { //------------------------------------
	//trace("file($url)");
	$html = file($url);
	if (!$html) { return NULL; }
	//foreach ($html as $line) { if (preg_match('/xcat.web/',$line)) { trace($line); } }
	$matches = preg_grep('/href=.*' . $rpmname . '-.*?\.rpm/i', $html);
	if (!count($matches)) { return NULL; }
	foreach ($matches as &$line) {
		$pattern = '/' . $rpmname . '-.*?\.rpm/i';
		//trace($pattern);
		//$line = preg_replace($pattern, '$1', $line);
		preg_match($pattern, $line, $m);
		$line = $m[0];
		//trace($line);
		}
	usort($matches, 'byversion');
	//foreach ($matches as $l) { trace($l); }
	return $matches[0];
}


# Parse out the version and release numbers of the 2 rpm file names and sort in descending order
# This sort function should be used like:  usort($rpms, 'byversion');
# Makes the following assumptions:
#  - the version and release are single digits separated by dots (e.g. 1.2.3) - so we can compare it as a string
#  - the release has at most 1 dot in it - so we can compare it as a float
function byversion($a, $b) { //------------------------------------
	$pat = '/-([0-9.]+)-([0-9.]+)\.\D/';
	preg_match($pat, $a, $a_matches);
	preg_match($pat, $b, $b_matches);
	$result = strcmp($a_matches[1], $b_matches[1]);
	if ($result) { return $result * -1; }   // they were not equal, so return result
	if ($a_matches[2] == $b_matches[2]) { return 0; }
    return ($a_matches[2] < $b_matches[2]) ? 1 : -1;
  }


// Choose whether to use the PPD lab server, the general internal IBM server, or the external server.
function findSite() { //------------------------------------

	$internalSitePok = 'rs6000.pok.ibm.com';
	$internalDir = '/afs/apd/u/bp/xcat/';
	$internalURLPok = "http://$internalSitePok$internalDir";
	$internalURLDirPok = "http://$internalSitePok$internalDir";
	$internalSite = 'www.pok.ibm.com';
	$internalURL = "http://$internalSite$internalDir";
	$internalURLDir = "http://$internalSite$internalDir";
	$externalURL = "ftp://ftp.software.ibm.com/eserver/pseries/cluster/csm/fixes";             //todo: change these
	$externalURLDir = "http://www14.software.ibm.com/webapp/set2/sas/f/csm/utilities/xCSMfixhome.html";

	# 1st try rs6000.pok.ibm.com if we are inside the BSO firewall
	$hostname = resolveHost($_SERVER["SERVER_NAME"]);
	//$hostname = resolveHost('9.56.216.79');
	//trace("Local hostname: $hostname");
	if (preg_match('/ppd\.pok\.ibm\.com$/', $hostname)) {
		return array ('dir'=>$internalURLDirPok, 'download'=>$internalURLPok);
	}

	// Try pinging the IBM internal site
	$cntflag = isWindows() ? '-n' : '-c';
	$rc = runcmd("/bin/ping -w 4 $cntflag 1 $internalSite", 2, $out);
	//trace("rc=$rc");
	if ($rc == 0) {
		return array ('dir'=>$internalURLDir, 'download'=>$internalURL);
	}

	// Fall back to external site
	return array ('dir'=>$externalURLDir, 'download'=>$externalURL);
}
?>
