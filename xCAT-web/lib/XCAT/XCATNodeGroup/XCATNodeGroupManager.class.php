<?php
/**
 * Manages a collection of XCATNodeGroup objects.
 */
class XCATNodeGroupManager {
	/**
	 * An array of node groups, keyed by name.
	 */
	var $nodeGroups = array();

	function XCATNodeGroupManager() {
		$nodes = array();
	}

	function &getInstance() {
		static $instance;

		if(is_null($instance)) {
			$instance = new XCATNodeGroupManager();
		}

		return $instance;
	}

	function getNodeGroups() {
		return $this->nodeGroups;
	}

	function setNodeGroups($pNodeGroups) {
		$this->nodeGroups = $pNodeGroups;
	}

	function addNodeGroup($nodeGroup) {
		$this->nodeGroups[$nodeGroup->getName()] = $nodeGroup;
	}

	function removeNodeGroup($nodeGroup) {
		$this->nodeGroups[$nodeGroup->getName()] = NULL;
	}

	function getNodeGroupByName($nodeGroupName) {
		$nodeGroup = NULL;

		if(array_key_exists($nodeGroupName, $this->nodeGroups)) {
			$nodeGroup = $this->nodeGroups[$nodeGroupName];
		}

		return $nodeGroup;
	}
}
?>
