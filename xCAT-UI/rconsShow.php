<?php
echo <<<EEE
<html>
	<head>
	    <title>{$_GET['rconsnd']}</title>
	    <meta http-equiv="content-type" content="text/html; charset=UTF-8"/>
	    <link rel="stylesheet" type="text/css" href="css/ajaxterm.css"/>
	    <script type="text/javascript" src="js/jquery/jquery-1.4.4.min.js"></script>
	    <script type="text/javascript" src="js/rcons/rcons.js"></script>
	    <script type="text/javascript">
	    window.onload=function() {
	        t=new rconsTerm("{$_GET['rconsnd']}", 80, 25);
	    };
		window.onbeforeunload = function(){
			
		};
	    </script>
	</head>
	<body>
		<div id="term"></div>
	</body>
</html>
EEE;
?>

