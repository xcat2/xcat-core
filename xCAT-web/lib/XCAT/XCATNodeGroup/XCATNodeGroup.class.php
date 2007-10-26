<?php
/**
 * XCATNodeGroup entity class.
 */
class XCATNodeGroup {
	var $name;
	var $nodes;

	function XCATNodeGroup() {
		$this->nodes = array();
	}

	function getName() {
		return $this->name;
	}

	function setName($pName) {
		$this->name = $pName;
	}

	function getNodes() {
		return $this->nodes;
	}

	function getStatus() {
		return $this->status;
	}

	function setNodes($pNodes) {
		$this->nodes = $pNodes;
	}

	function setStatus($pStatus) {
		$this->status = $pStatus;
	}

	function addNode($node) {
		$this->nodes[$node->getName()] = $node;
	}

	function removeNode($node) {
		$this->nodes[$node->getName()] = NULL;
	}
}
?>
