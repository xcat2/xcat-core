<?php

// Gets the nodes and groups for group/node js widget
if(!isset($TOPDIR)) { $TOPDIR="..";}
require_once "$TOPDIR/lib/security.php";
require_once "$TOPDIR/lib/functions.php";
require_once "$TOPDIR/lib/display.php";
require_once "$TOPDIR/lib/monitor_display.php";

require_once "$TOPDIR/js/jsonwrapper.php";
    if (isset($_GET['id'])) {
        $id = $_GET['id'];
    }
    if ($id == "0") {
        echo '[{"data":"cluster","attributes":{"id":",cluster","rel":"node"}},{"data":"summary","attributes":{"id":",summary","rel":"node"}},{"data":"lpar","attributes":{"id":",lpar","rel":"group"},"state":"closed"}]';
    } else {
        $id=preg_replace('/^,/','',$id);
        $rvals=docmd('extnoderange',$id,array('subgroups'));
        $parents=array();
        $root=1;
        if ($id == '/.*') {
            $id=',';
        } else {
            $parents=split("@",$id);
            $id=",$id@";
            $root=0;
        }
        //unset($rvals->xcatresponse->serverdone[0]);
        $numsubgroups=count($rvals->xcatresponse->intersectinggroups);
        $numnodes=count($rvals->xcatresponse->node);
        $jdata=array();
        if ($numnodes >= $numsubgroups) { #If there are few enough subgroups to be helpful filters, add them in
            foreach ($rvals->xcatresponse->intersectinggroups as $group) {
                if (! in_array("$group",$parents)) {
                $jdata[]= array("data"=>"$group",
                                "attributes"=>array("id"=>"$id$group",
                                                    "rel"=>'group'),
                                "state"=>'closed');
                                }

            }
        } #If there were more groups than nodes, leave the signal to noise ratio down
        if ($root==0) {
            foreach ($rvals->xcatresponse->node as $node) {
                $jdata[] = array("data"=>"$node",
                                 "attributes"=>array("id"=>",$node",
                                                     "rel"=>'node'));
            }
        }
        echo json_encode($jdata);
    }
?>
