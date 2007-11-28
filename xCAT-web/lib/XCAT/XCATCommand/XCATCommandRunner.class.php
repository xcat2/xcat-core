<?php
require_once("../lib/XCAT/XCATNode/XCATNode.class.php");
require_once("../lib/XCAT/XCATNode/XCATNodeManager.class.php");
require_once("../lib/XCAT/XCATNodeGroup/XCATNodeGroup.class.php");
require_once("../lib/XCAT/XCATNodeGroup/XCATNodeGroupManager.class.php");

class XCATCommandRunner {
	var $XCATRoot;

	var $XCATNodeManager;

	var $XCATNodeGroupManager;

	function XCATCommandRunner() {
		$this->XCATRoot = '';   //'/opt/xcat/bin';   //todo: get rid of these
		$this->CurrDir = '';    //'/opt/xcat/web';
		$this->Sudo = '/bin/sudo ';

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
	 * Will always return an up to date list of node names belonging to the group.
	 *
	 * @param String groupName	The name of the XCATNodeGroup
	 * @return An array containing the name of all nodes in the group.
	 */
	function getNodeNamesByGroupName($groupName) {
		$cmdString = $this->Sudo . "nodels $groupName";
		$outputStat = $this->runCommand($cmdString);

		return $outputStat["output"];
	}

	/**
	 * @param String nodeName	The name of the node.
	 */
	function getXCATNodeByName($nodeName) {

			$cmdString = $this->Sudo . "nodestat $nodeName";
			$outputStat = $this->runCommand($cmdString);

			$xcn = new XCATNode();
			$xcn->setName($nodeName);
			$xcn->setStatus($this->determineNodeStatus($outputStat["output"][0]));
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
	 * @param String nodestatStr	The status of the node as output by the nodestat command
	 * @return "good", "bad", or "other"
	 */
	function determineNodeStatus($nodestatStr) {
		$status = NULL;

		if ((strpos($nodestatStr, "ready") != FALSE) ||
			(strpos($nodestatStr, "pbs") != FALSE) ||
			(strpos($nodestatStr, "sshd") != FALSE)) {
			$status = 'good';
		} else if(strpos($nodestatStr, "noping") != FALSE) {
			$status = 'bad';
		} else {
			$status = 'other';
		}

		return $status;
	}

	/**
	 * @return An array containing the name of every node group.
	 */
	function getAllGroupNames() {
		$cmdString = $this->Sudo . "listattr";
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

}
?>