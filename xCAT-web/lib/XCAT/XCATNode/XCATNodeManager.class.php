<?php
/**
 * Manages a collection of XCATNode objects.
 */
class XCATNodeManager {
	/**
	 * An array of nodes, keyed by name.
	 */
	var $nodes = array();

	function XCATNodeManager() {
		$nodes = array();
	}

	function &getInstance() {
		static $instance;

		if(is_null($instance)) {
			$instance = new XCATNodeManager();
		}

		return $instance;
	}

	function getNodes() {
		return $this->nodes;
	}

	function setNodes($pNodes) {
		$this->nodes = $pNodes;
	}

	function addNode($node) {
		$this->nodes[$node->getName()] = $node;
	}

	function removeNode($node) {
		$this->nodes[$node->getName()] = NULL;
	}

	function getNodeByName($nodeName) {
		$node = NULL;

		if(array_key_exists($nodeName, $this->nodes)) {
			$node = $this->nodes[$nodeName];
		}

		return $node;
	}
}
?>
