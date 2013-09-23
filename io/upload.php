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


$output_dir = "../templates/Finance5/firma/";
 
if(isset($_FILES["myfile"]))
{
    $extension = end(explode(".", $_FILES["myfile"]["name"]));

    if (($_FILES["myfile"]["type"] != "application/pdf") || ($_FILES["myfile"]["size"] > 300000) ||  ($extension != "pdf"))
    {
       echo "<div class='red'>Ung&uuml;ltige Datei. Ausschlie&szlig;lich PDF Dateien, <300kB.</div>";
       exit;      
    }

    $head = fgets(fopen($_FILES["myfile"]["tmp_name"], "r"), 6);
    if($head != '%PDF-') 
    {
       echo "<div class='red'>Ung&uuml;ltige PDF Datei.</div>";
       exit;
    }

    //Filter the file types , if you want.
    if ($_FILES["myfile"]["error"] > 0)
    {
      echo "<div class='red'>Error: " . $_FILES["myfile"]["error"] . "<br></div>";
    }
    else
    {
        //move the uploaded file to uploads folder;
        move_uploaded_file($_FILES["myfile"]["tmp_name"],$output_dir. "briefbogen.pdf");
 
     echo "Hochgeladen: ".$_FILES["myfile"]["name"]." -> briefbogen.pdf";
    }
 
}
?>
