<?php
class Config {
	var $configMap;

	function Config() {
		$configMap = array();
	}

	function &getInstance() {
		static $instance;

		if(NULL == $instance) {
			$instance = new Config();
		}

		return $instance;
	}

	function getValue($key) {
		return $this->configMap[$key];
	}

	function setValue($key, $value) {
		$this->configMap[$key] = $value;
	}
}
?>