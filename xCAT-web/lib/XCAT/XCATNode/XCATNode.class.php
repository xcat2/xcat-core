<?php
/**
 * XCATNode entity class.
 */
class XCATNode {
	var $name;
	var $hwType;
	var $os;
	var $mode;
	var $status;
	var $hwCtrlPt;
	var $comment;

	function XCATNode() {

	}

	function getName() {
		return $this->name;
	}

	function getHwType() {
		return $this->hwType;
	}

	function getOs() {
		return $this->os;
	}

	function getMode() {
		return $this->mode;
	}

	function getStatus() {
		return $this->status;
	}

	function getHwCtrlPt() {
		return $this->hwCtrlPt;
	}

	function getComment() {
		return $this->comment;
	}

	function setName($pName) {
		$this->name = $pName;
	}

	function setHwType($pHwType) {
		$this->hwType = $pHwType;
	}

	function setOs($pOs) {
		$this->os = $pOs;
	}

	function setMode($pMode) {
		$this->mode = $pMode;
	}

	function setStatus($pStatus) {
		$this->status = $pStatus;
	}

	function setHwCtrlPt($pHwCtrlPt) {
		$this->hwCtrlPt = $pHwCtrlPt;
	}

	function setComment($pComment) {
		$this->comment = $pComment;
	}
}
?>
