<?php
# This function is called by the javascript function printtree as a 
# result of someone clicking the node range tree.  This will display
# the node range 
	require_once "lib/security.php";
        require_once "lib/functions.php";
        require_once "lib/display.php";
?>
<?php
if(isset($_REQUEST['t'])){
        $t = $_REQUEST['t'];
}else{
        echo "please enter a t='type' of page to load with this noderange";
        exit;
}

if($t == 'control'){
        $cmd = '';
        if(isset($_REQUEST['nr'])){
                $nr = $_REQUEST['nr'];
                if(isset($_REQUEST['cmd'])){
                        $cmd = $_REQUEST['cmd'];
                }
                displayRangeList($nr,$cmd);
        }else{
                echo "Please select machines";
        }
}elseif($t == 'provision'){
        $method = '';
        $os = '';
        $arch = '';
        $profile = '';
        if(isset($_REQUEST['nr'])){
                $nr = $_REQUEST['nr'];
                if(isset($_REQUEST['m']) &&
                        isset($_REQUEST['o']) &&
                        isset($_REQUEST['a']) &&
                        isset($_REQUEST['p'])
                ){

                        $method = $_REQUEST['m'];
                        $os = $_REQUEST['o'];
                        $arch = $_REQUEST['a'];
                        $profile = $_REQUEST['p'];
                }
                displayInstallList($nr,$method,$os,$arch,$profile);
        }else{

                echo "Please select machines";
        }
}
?>
