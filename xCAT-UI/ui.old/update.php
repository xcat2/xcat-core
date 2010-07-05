<?php
/*
 * update.php
 *
 */
     require_once "lib/security.php";
    require_once "lib/functions.php";
    require_once "lib/display.php";
    displayMapper(array('home'=>'main.php', 'help' =>'', 'update'=>''));
?>
<div class="mContent">
    <h1>Repository</h1>
<?php
    $DevelRepository = "";
    $StableRepository = "";
    #supposed only AIX & LINUX
    if ("aix" == strtolower(PHP_OS))
    {
        $DevelRepository = "http://xcat.sourceforge.net/aix/devel/xcat-core/";
        $StableRepository = "http://xcat.sourceforge.net/aix/xcat-core/";
    }
    else
    {
        $DevelRepository = "http://xcat.sourceforge.net/yum/devel/xcat-core/";
        $StableRepository = "http://xcat.sourceforge.net/yum/xcat-core/";
    }

    echo "<input type=\"radio\" name= \"reporadio\" value=\"" . $DevelRepository . "\">" . $DevelRepository . "(<strong>Devel</strong>)<br/>";
    echo "<input type=\"radio\" name=\"reporadio\" value=\"" . $StableRepository . "\">" . $StableRepository . "(<strong>Stable</strong>)<br/>";
    if(isset($_COOKIE["xcatrepository"]))
    {
        echo "<input type=\"radio\" checked=\"true\" name=\"reporadio\" value=\"\">Other:";
        echo "<input style=\"width: 500px\" id=repositoryaddr value=\"" . $_COOKIE["xcatrepository"] ."\"<br/>";
    }
    else
    {
        echo "<input type=\"radio\" name=\"reporadio\" value=\"\">Other:";
        echo "<input style=\"width: 500px\" id=repositoryaddr value=\"http://\"<br/>";
    }
?>
</div>
<div id="temp"></div>
<div id="update" class="mContent">
    <h1>xCAT Update Info</h1>
    <?php showUpdateInfo(); ?>
    <button onclick='fun_js_update()'>Update</button>
</div>
<div id=updateProcess>
</div>
