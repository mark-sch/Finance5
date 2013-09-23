<?php
//=====================================================================
// Finance5
// Copyright (C) 2013
// www.finance5.de
//
//=====================================================================
//
//  Author: Think5 GmbH
//     Web: http://www.think5.de
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
//======================================================================
//


if (!isset($_SERVER['PHP_AUTH_USER']))
{
        Header("WWW-Authenticate: Basic realm=\"Configurations-Editor\"");
        Header("HTTP/1.0 401 Unauthorized");
        echo "Sie m&uuml;ssen sich autentifizieren\n";
        exit;
}
else
{
        require "conf.php";

        if ($_SERVER['PHP_AUTH_USER']<>$ERPftpuser || $_SERVER['PHP_AUTH_PW']<>$ERPftppwd)
        {
                Header("WWW-Authenticate: Basic realm=\"My Realm\"");
                Header("HTTP/1.0 401 Unauthorized");
                echo "Sie m&uuml;ssen sich autentifizieren\n";
                exit;
        }
?>

	<!doctype html>
	<head>
	<script src="http://ajax.googleapis.com/ajax/libs/jquery/1.7/jquery.js"></script>
	<script src="http://malsup.github.com/jquery.form.js"></script>
	<style>
	form { display: block; margin: 20px auto; background: #eee; border-radius: 10px; padding: 15px }
	   #progress { position:relative; width:400px; border: 1px solid #ddd; padding: 1px; border-radius: 3px; }
	   #bar { background-color: #B4F5B4; width:0%; height:20px; border-radius: 3px; }
	   #percent { position:absolute; display:inline-block; top:3px; left:48%; }
	   .red { color: red; }
           #main { width: 800px; text-align: left; }
        </style>
	</head>
	<body>
        <center>
	<div id="main">
	<h1>Angebot/Rechnung Briefpapier Upload</h1>
	Upload von Firmen-Briefpapier, die Datei muss im PDF Format und DIN A4 vorliegen. Basierend auf dieser Vorlage erfolgt die zuk&uuml;nftige Generierung von Angeboten und Rechnungen.<br/><a href="./briefbogen.pdf" target="_new">Bespiel Datei</a><br> 
	<form id="myForm" action="upload.php" method="post" enctype="multipart/form-data">
     	<input type="file" size="25" name="myfile">
     	<input type="submit" value="Datei hochladen">
	</form>
 
 	Fortschritt: <div id="progress">
        	<div id="bar"></div>
        	<div id="percent">0%</div >
	</div>
	<br/>
 
	<div id="message"></div>
 
	<script>
	$(document).ready(function()
	{
    		var options = {
    		beforeSend: function()
    		{
        		$("#progress").show();
        		//clear everything
        		$("#bar").width('0%');
        		$("#message").html("");
        		$("#percent").html("0%");
    		},
    		uploadProgress: function(event, position, total, percentComplete)
    		{
        		$("#bar").width(percentComplete+'%');
        		$("#percent").html(percentComplete+'%');
 
    		},
    		success: function()
    		{
        		$("#bar").width('100%');
        		$("#percent").html('100%');
 
    		},
    		complete: function(response)
    		{
        		$("#message").html("<font color='green'>"+response.responseText+"</font>");
    		},
    		error: function()
    		{
        		$("#message").html("<font color='red'> Fehler: Datei Upload fehlgeschlagen.</font>");
 
    		}
 
		};
     		$("#myForm").ajaxForm(options);
	});
	</script>
        </div>
	</center>
        </body> 
	</html>

<?
}
?>
