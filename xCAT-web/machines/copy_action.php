<?php
    $TOPDIR = '..';
    require_once "$TOPDIR/lib/functions.php";
    //get the necessary information from the copyfile dialog, 
    //Now it ONLY checks the following two arguments: source file name, and dest directory;
    $src = $_REQUEST["src"];
    $dest = $_REQUEST["dest"];
    $nr = $_REQUEST["noderange"];
    $cmd = $_REQUEST["command"];
?>
<p>
<?php
    //TODO
    echo "Command: &nbsp;<b>$cmd $nr $src $dest</b>";
?>
</p>
<p>
<?php 
    $arg = "$src $dest";
    echo "<p>argument is:$arg</p>";
    $xml = docmd($cmd, $nr, array($src, $dest));
    foreach($xml->children() as $response) foreach ($response->children() as $line) {
         echo "$line<br />";
    }
?>
</p>
