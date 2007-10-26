<?php
require_once("config.php");
require_once("XCAT/XCATNode/XCATNodeGroupUtil.class.php");
require_once("XCAT/XCATNode/XCATNode.class.php");
require_once("XCAT/XCATNode/XCATNodeManager.class.php");
require_once("XCAT/XCATNodeGroup/XCATNodeGroup.class.php");
require_once("XCAT/XCATNodeGroup/XCATNodeGroupManager.class.php");

class XCATCommandRunner {
	var $XCATRoot;

	var $XCATNodeManager;

	var $XCATNodeGroupManager;

	function XCATCommandRunner() {
		$config = &Config::getInstance();
		$this->XCATRoot = $config->getValue("XCATROOT");
		$this->CurrDir = $config->getValue("CURRDIR");

		$this->XCATNodeManager = &XCATNodeManager::getInstance();
		$this->XCATNodeGroupManager = &XCATNodeGroupManager::getInstance();
	}

	/**
	 * @param String cmdString	The command to execute.
	 * @return An array containing the command output as the first element
	 * 			and the command return status as the second element.
	 */
	function runCommand($cmdString) {
		$cmdOutput = NULL;
		$cmdReturnStat = NULL;
		exec($cmdString, $cmdOutput, $cmdReturnStat);

		$outputStat = array();
		$outputStat["output"] = $cmdOutput;
		$outputStat["returnStat"] = $cmdReturnStat;

		return $outputStat;
	}

	/**
	 * Will always return an up to date list of node names.
	 *
	 * @return An array containing names of all nodes.
	 */
	function getAllNodeNames() {
		$cmdString = "sudo " . $this->XCATRoot . "/nodels";
		$outputStat = $this->runCommand($cmdString);

		return $outputStat["output"];
	}

	/**
	 * Will always return an up to date list of node names belonging to the group.
	 *
	 * @param String groupName	The name of the XCATNodeGroup
	 * @return An array containing the name of all nodes in the group.
	 */
	function getNodeNamesByGroupName($groupName) {
		$cmdString = "sudo " . $this->XCATRoot . "/nodels $groupName";
		$outputStat = $this->runCommand($cmdString);

		return $outputStat["output"];
	}

	/**
	 * @param String nodeName	The name of the node.
	 */
	function getXCATNodeByName($nodeName) {

			$cmdString = "sudo " . $this->XCATRoot . "/nodestat $nodeName";
			$outputStat = $this->runCommand($cmdString);

			$xcn = new XCATNode();
			$xcn->setName($nodeName);
			$xcn->setStatus(XCATNodeGroupUtil::determineNodeStatus($outputStat["output"][0]));
			$xcn->setHwType("HW Type");
			$xcn->setOs("OS");
			$xcn->setMode("Mode");
			$xcn->setHwCtrlPt("HW Ctrl Pt");
			$xcn->setComment("Comment");

			// Add the node to the manager, now that we've loaded it.
			$this->XCATNodeManager->addNode($xcn);


			return $xcn;
	}

	/**
	 * @return An array containing the name of every node group.
	 */
	function getAllGroupNames() {
		$cmdString = "sudo " . $this->XCATRoot . "/listattr";
		$outputStat = $this->runCommand($cmdString);

		return $outputStat["output"];
	}

	/**
	 * @param String groupName	The name of the group we want to get.
	 * @return An XCATNodeGroup object representing
	 * 			the node group with the given name. This object will
	 * 			contain the XCATNodes belonging to this XCATNodeGroup.
	 */
	function getXCATNodeByGroupName($groupName) {
			$nodeNames = $this->getNodeNamesByGroupName($groupName);

			$xcatNodes = array();

			foreach($nodeNames as $nodeName) {
				$xcatNode = $this->getXCATNodeByName($nodeName);
				array_push($xcatNodes, $xcatNode);
			}

			$xcatNodeGroup = new XCATNodeGroup();
			$xcatNodeGroup->setName($groupName);
			$xcatNodeGroup->setNodes($xcatNodes);


		return $xcatNodeGroup;
	}


	/**
	 * This function will run the command to get all
	 * the groups, and then for each group, it will get
	 * their nodes, and for each node, it will get its
	 * information once.
	 */
	function getAllXCATGroups() {
			$xcatGroupNames = $this->getAllGroupNames();

			$xcatGroups = array();

			$groupStatArr = $this->getGroupStatus(); //get the status of all the groups

			foreach($xcatGroupNames as $groupName) {
				$xcatGroup = $this->getXCATGroupByName($groupName, $groupStatArr);
				array_push($xcatGroups, $xcatGroup);
			}


			return $xcatGroups;
	}

	function getXCATGroupByName($groupName, $groupStatArr){

			$xcg = new XCATNodeGroup();
			$xcg->setName($groupName);
			$xcg->setStatus(XCATNodeGroupUtil::determineNodeStatus($groupStatArr[$groupName]));

			return $xcg;
	}


	/**
	 * Will always return an up to date status of the groups
	 *
	 * @return An array containing the status of all the groups
	 */
	function getGroupStatus() {
		$cmdString = "sudo " . $this->CurrDir . "/cmds/grpattr";
		$outputStat = $this->runCommand($cmdString);
		$groupStats = $outputStat["output"];
		$groupStatArr = array();
		foreach($groupStats as $key => $groupStat) {
			if (strpos($groupStat,':') != FALSE){
				$stat = substr($groupStat,strpos($groupStat,':') + 2); //there's a space between the colon and the status
				$grp = substr($groupStat,0, strpos($groupStat,':'));
				$groupStatArr[$grp] = $stat;
			}
		}

		return $groupStatArr;
	}

	function getNodeOrGroupStatus($nodegroupName, $group) {
		$stat = "";
		if ($group == FALSE){
			$cmdString = "sudo " . $this->XCATRoot . "/nodestat " . $nodegroupName;
			$outputStat = $this->runCommand($cmdString);
			$nodegroupStat = $outputStat["output"][0];

			if (strpos($nodegroupStat,':') != FALSE){
					$stat = substr($nodegroupStat,strpos($nodegroupStat,':') + 2); //there's a space between the colon and the status
			}
		}else{
			$StatArr = $this->getGroupStatus();
			$stat = $StatArr[$nodegroupName];
		}

		if ($stat != "")	$stat = XCATNodeGroupUtil::determineNodeStatus($stat);

		return $stat;
	}

}
?>