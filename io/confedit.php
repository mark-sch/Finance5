<?php

function filter($data) {
	$data = trim(htmlentities(strip_tags($data)));

	if (get_magic_quotes_gpc())
		$data = stripslashes($data);

	$data = mysql_real_escape_string($data);

	return $data;
}


foreach($_POST as $key => $value) {
	$_POST[$key] = filter($value);
}


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
	
	require_once "DB.php";

	if ($_POST["ok"] == "sichern")
	{
		$ok = true;
		$dsnP = array(
                    'phptype'  => 'pgsql',
                    'username' => $_POST["ERPuser"],
                    'password' => $_POST["ERPpass"],
                    'hostspec' => $_POST["ERPhost"],
                    'database' => $_POST["ERPdbname"],
                    'port'     => $_POST["ERPport"]
                    );
		$dbP=@DB::connect($dsnP);
		if (DB::isError($dbP)||!$dbP)
		{
			$ok=false;
			echo "Keine Verbindung zur ERP<br>";
			echo $dbP->userinfo;
			$dbP=false;
		}
		else
		{
			$rs=$dbP->getall("select id from employee where login = '".$_POST["ERPusrN"]."'");
			$_POST["ERPusrID"]=$rs[0][0];
		}
		if ($ok)
		{
			$f=fopen("conf.php","w");
			$v="2.0";
			$d=date("Y/m/d H:i:s");
			
			$ERPhost=$_POST["ERPhost"];
			$ERPport=$_POST["ERPport"];
			$ERPdbname=$_POST["ERPdbname"];
			$ERPuser=$_POST["ERPuser"];
			$ERPpass=$_POST["ERPpass"];
			$ERPusrN=$_POST["ERPusrN"];
			$ERPftpuser=$_POST["ERPftpuser"];
			$ERPftppwd=$_POST["ERPftppwd"];
			$debug=$_POST["debug"];
			$fehlendeSKU=$_POST["fehlendeSKU"];
			$platzhalterFehlendeSKU=$_POST["platzhalterFehlendeSKU"];
			$versandkosten=$_POST["versandkosten"];
			$geschenkverpackung=$_POST["geschenkverpackung"];
			
			$Amazonaktiviert=$_POST["Amazonaktiviert"];
			$AmazonAbteilungsname=$_POST["AmazonAbteilungsname"];
			$AmazonBestellnummernprefix=$_POST["AmazonBestellnummernprefix"];
			$MerchantID=$_POST["MerchantID"];
			$AccessKeyID=$_POST["AccessKeyID"];
			$SecretKey=$_POST["SecretKey"];
			$EndpointUrl=$_POST["EndpointUrl"];
			$SigMethod=$_POST["SigMethod"];
			$SigVersion=$_POST["SigVersion"];
			$MarketplaceID_DE=$_POST["MarketplaceID_DE"];
			$MarketplaceID_GB=$_POST["MarketplaceID_GB"];
			$MarketplaceID_FR=$_POST["MarketplaceID_FR"];
			$MarketplaceID_IT=$_POST["MarketplaceID_IT"];
			$MarketplaceID_ES=$_POST["MarketplaceID_ES"];
			$ersatzSKU=$_POST["ersatzSKU"];
			
			$eBayaktiviert=$_POST["eBayaktiviert"];
			$eBayAbteilungsname=$_POST["eBayAbteilungsname"];
			$eBayBestellnummernprefix=$_POST["eBayBestellnummernprefix"];
			$eBayServerUrl=$_POST["eBayServerUrl"];
			$eBayDEVID=$_POST["eBayDEVID"];
			$eBayAppID=$_POST["eBayAppID"];
			$eBayCertID=$_POST["eBayCertID"];
			$eBayUserToken=$_POST["eBayUserToken"];
			
			$Joomlaaktiviert=$_POST["Joomlaaktiviert"];
			$JoomlaAbteilungsname=$_POST["JoomlaAbteilungsname"];
			$JoomlaBestellnummernprefix=$_POST["JoomlaBestellnummernprefix"];
			$Joomlahost=$_POST["Joomlahost"];
			$Joomlaport=$_POST["Joomlaport"];
			$Joomladbname=$_POST["Joomladbname"];
			$Joomlauser=$_POST["Joomlauser"];
			$Joomlapass=$_POST["Joomlapass"];
			
			fputs($f,"<?\n// Verbindung zur ERP-db\n");
			fputs($f,"\$ERPhost=\"".$_POST["ERPhost"]."\";\n");
			fputs($f,"\$ERPport=\"".$_POST["ERPport"]."\";\n");
			fputs($f,"\$ERPdbname=\"".$_POST["ERPdbname"]."\";\n");
			fputs($f,"\$ERPuser=\"".$_POST["ERPuser"]."\";\n");
			fputs($f,"\$ERPpass=\"".$_POST["ERPpass"]."\";\n");
			fputs($f,"\$ERPusrN=\"".$_POST["ERPusrN"]."\";\n");
			fputs($f,"\$ERPusrID=\"".$_POST["ERPusrID"]."\";\n");
			fputs($f,"\$ERPftpuser=\"".$_POST["ERPftpuser"]."\";\n");
			fputs($f,"\$ERPftppwd=\"".$_POST["ERPftppwd"]."\";\n");
			fputs($f,"\$debug=\"".$_POST["debug"]."\";\n");
			fputs($f,"\$fehlendeSKU=\"".$_POST["fehlendeSKU"]."\";\n");
			fputs($f,"\$platzhalterFehlendeSKU=\"".$_POST["platzhalterFehlendeSKU"]."\";\n");
			fputs($f,"\$versandkosten=\"".$_POST["versandkosten"]."\";\n");
			fputs($f,"\$geschenkverpackung=\"".$_POST["geschenkverpackung"]."\";\n");
			
			fputs($f,"\$Amazonaktiviert=\"".$_POST["Amazonaktiviert"]."\";\n");
			fputs($f,"\$AmazonAbteilungsname=\"".$_POST["AmazonAbteilungsname"]."\";\n");
			fputs($f,"\$AmazonBestellnummernprefix=\"".$_POST["AmazonBestellnummernprefix"]."\";\n");
			fputs($f,"\$MerchantID=\"".$_POST["MerchantID"]."\";\n");
			fputs($f,"\$AccessKeyID=\"".$_POST["AccessKeyID"]."\";\n");
			fputs($f,"\$SecretKey=\"".$_POST["SecretKey"]."\";\n");
			fputs($f,"\$EndpointUrl=\"".$_POST["EndpointUrl"]."\";\n");
			fputs($f,"\$SigMethod=\"".$_POST["SigMethod"]."\";\n");
			fputs($f,"\$SigVersion=\"".$_POST["SigVersion"]."\";\n");
			fputs($f,"\$MarketplaceID_DE=\"".$_POST["MarketplaceID_DE"]."\";\n");
			fputs($f,"\$MarketplaceID_GB=\"".$_POST["MarketplaceID_GB"]."\";\n");
			fputs($f,"\$MarketplaceID_FR=\"".$_POST["MarketplaceID_FR"]."\";\n");
			fputs($f,"\$MarketplaceID_IT=\"".$_POST["MarketplaceID_IT"]."\";\n");
			fputs($f,"\$MarketplaceID_ES=\"".$_POST["MarketplaceID_ES"]."\";\n");
			fputs($f,"\$ersatzSKU=\"".$_POST["ersatzSKU"]."\";\n");

			fputs($f,"\$eBayaktiviert=\"".$_POST["eBayaktiviert"]."\";\n");
			fputs($f,"\$eBayAbteilungsname=\"".$_POST["eBayAbteilungsname"]."\";\n");
			fputs($f,"\$eBayBestellnummernprefix=\"".$_POST["eBayBestellnummernprefix"]."\";\n");
			fputs($f,"\$eBayServerUrl=\"".$_POST["eBayServerUrl"]."\";\n");
			fputs($f,"\$eBayDEVID=\"".$_POST["eBayDEVID"]."\";\n");
			fputs($f,"\$eBayAppID=\"".$_POST["eBayAppID"]."\";\n");
			fputs($f,"\$eBayCertID=\"".$_POST["eBayCertID"]."\";\n");
			fputs($f,"\$eBayUserToken=\"".$_POST["eBayUserToken"]."\";\n");
			
			fputs($f,"\$Joomlaaktiviert=\"".$_POST["Joomlaaktiviert"]."\";\n");
			fputs($f,"\$JoomlaAbteilungsname=\"".$_POST["JoomlaAbteilungsname"]."\";\n");
			fputs($f,"\$JoomlaBestellnummernprefix=\"".$_POST["JoomlaBestellnummernprefix"]."\";\n");
			fputs($f,"\$Joomlahost=\"".$_POST["Joomlahost"]."\";\n");
			fputs($f,"\$Joomlaport=\"".$_POST["Joomlaport"]."\";\n");
			fputs($f,"\$Joomladbname=\"".$_POST["Joomladbname"]."\";\n");
			fputs($f,"\$Joomlauser=\"".$_POST["Joomlauser"]."\";\n");
			fputs($f,"\$Joomlapass=\"".$_POST["Joomlapass"]."\";\n");

			fputs($f,"?>");
			fclose($f);
			echo "Konfiguration gesichert !<br><br>";
			require "conf.php";
		}
		else
		{
			$ERPhost=$_POST["ERPhost"];
			$ERPport=$_POST["ERPport"];
			$ERPdbname=$_POST["ERPdbname"];
			$ERPuser=$_POST["ERPuser"];
			$ERPpass=$_POST["ERPpass"];
			$ERPusrN=$_POST["ERPusrN"];
			$ERPftpuser=$_POST["ERPftpuser"];
			$ERPftppwd=$_POST["ERPftppwd"];
			$debug=$_POST["debug"];
			$fehlendeSKU=$_POST["fehlendeSKU"];
			$platzhalterFehlendeSKU=$_POST["platzhalterFehlendeSKU"];
			$versandkosten=$_POST["versandkosten"];
			$geschenkverpackung=$_POST["geschenkverpackung"];

			$Amazonaktiviert=$_POST["Amazonaktiviert"];
			$AmazonAbteilungsname=$_POST["AmazonAbteilungsname"];
			$AmazonBestellnummernprefix=$_POST["AmazonBestellnummernprefix"];
			$MerchantID=$_POST["MerchantID"];
			$AccessKeyID=$_POST["AccessKeyID"];
			$SecretKey=$_POST["SecretKey"];
			$EndpointUrl=$_POST["EndpointUrl"];
			$SigMethod=$_POST["SigMethod"];
			$SigVersion=$_POST["SigVersion"];
			$MarketplaceID_DE=$_POST["MarketplaceID_DE"];
			$MarketplaceID_GB=$_POST["MarketplaceID_GB"];
			$MarketplaceID_FR=$_POST["MarketplaceID_FR"];
			$MarketplaceID_IT=$_POST["MarketplaceID_IT"];
			$MarketplaceID_ES=$_POST["MarketplaceID_ES"];
			$ersatzSKU=$_POST["ersatzSKU"];

			$eBayaktiviert=$_POST["eBayaktiviert"];
			$eBayAbteilungsname=$_POST["eBayAbteilungsname"];
			$eBayBestellnummernprefix=$_POST["eBayBestellnummernprefix"];						
			$eBayServerUrl=$_POST["eBayServerUrl"];
			$eBayDEVID=$_POST["eBayDEVID"];
			$eBayAppID=$_POST["eBayAppID"];
			$eBayCertID=$_POST["eBayCertID"];
			$eBayUserToken=$_POST["eBayUserToken"];			
			
			$Joomlaaktiviert=$_POST["Joomlaaktiviert"];
			$JoomlaAbteilungsname=$_POST["JoomlaAbteilungsname"];
			$JoomlaBestellnummernprefix=$_POST["JoomlaBestellnummernprefix"];						
			$Joomlahost=$_POST["Joomlahost"];
			$Joomlaport=$_POST["Joomlaport"];
			$Joomladbname=$_POST["Joomladbname"];
			$Joomlauser=$_POST["Joomlauser"];
			$Joomlapass=$_POST["Joomlapass"];
		}
	}
	else
	{
		require "conf.php";
	}
?>
<html>
	<body>
		<table style="background-color:#cccccc">
			<form name="ConfEdit" method="post" action="confedit.php">
				<input type="hidden" name="ERPusrID" value="<?= $ERPusrID ?>">
				<tr>
					<td>Import/Confedit User</td>
					<td><input type="text" name="ERPftpuser" size="25" value="<?= $ERPftpuser ?>"></td>
					<td></td>
					<td>Import/Confedit PWD</td>
					<td><input type="text" name="ERPftppwd" size="25" value="<?= $ERPftppwd ?>"></td>
				</tr>
				<tr>
					<td>------------------------------</td>
					<td>------------------------------</td>
					<td></td>
					<td>------------------------------</td>
					<td>------------------------------</td>
				</tr>
				<tr>
					<th>Wert</th>
					<th>Kivitendo</th>
					<th></th>
					<th>Wert</th>
					<th>Amazon</th>
				</tr>
				<tr>
					<td>Kivi-Host</td>
					<td><input type="text" name="ERPhost" size="25" value="<?= $ERPhost ?>"></td>
					<td></td>
					<td>Amazon aktiviert</td>
					<td><input type="checkbox" name="Amazonaktiviert" value="checked" <? if ($Amazonaktiviert == "checked") { echo "checked=\"checked\""; } ?>></td>
				</tr>				
				<tr>
					<td>Kivi-Port</td>
					<td><input type="text" name="ERPport" size="25" value="<?= $ERPport ?>"></td>
					<td></td>
					<td>Amazon Abteilungsname</td>
					<td><input type="text" name="AmazonAbteilungsname" size="25" value="<?= $AmazonAbteilungsname ?>"></td>
				</tr>
				<tr>
					<td>Kivi-Database</td>
					<td><input type="text" name="ERPdbname" size="25" value="<?= $ERPdbname ?>"></td>
					<td></td>
					<td>Amazon Bestellnummernprefix</td>
					<td><input type="text" name="AmazonBestellnummernprefix" size="25" value="<?= $AmazonBestellnummernprefix ?>"></td>
				</tr>				
				<tr>
					<td>Kivi db-User Name</td>
					<td><input type="text" name="ERPuser" size="25" value="<?= $ERPuser ?>"></td>
					<td></td>
					<td>Amazon MerchantID</td>
					<td><input type="text" name="MerchantID" size="25" value="<?= $MerchantID ?>"></td>
				</tr>
				<tr>
					<td>Kivi db-User PWD</td>
					<td><input type="text" name="ERPpass" size="25" value="<?= $ERPpass ?>"></td>
					<td></td>
					<td>Amazon AccessKeyID</td>
					<td><input type="text" name="AccessKeyID" size="25" value="<?= $AccessKeyID ?>"></td>
				</tr>
				<tr>
					<td>Kivi User-ID</td>
					<td><input type="text" name="ERPusrN" size="25" value="<?= $ERPusrN ?>"></td>
					<td></td>
					<td>Amazon SecretKey</td>
					<td><input type="text" name="SecretKey" size="25" value="<?= $SecretKey ?>"></td>
				</tr>
				<tr>
					<td>Kivi DB Logging</td>
					<td>ein<input type="radio" name="debug" value="true" <?= ($debug=="true")?"checked":"" ?>>aus<input type="radio" name="debug" value="false" <?= ($debug!="true")?"checked":"" ?>></td>
					<td></td>
					<td>Amazon EndpointUrl</td>
					<td><input type="text" name="EndpointUrl" size="25" value="<?= $EndpointUrl ?>"></td>
				</tr>
				<tr>
					<td>Bei fehlenden Produktnummern<br>alle Daten von Shops uebernehmen</td>
					<td>ja<input type="radio" name="fehlendeSKU" value="true" <?= ($fehlendeSKU=="true")?"checked":"" ?>>nein<input type="radio" name="fehlendeSKU" value="false" <?= ($fehlendeSKU!="true")?"checked":"" ?>></td>
					<td></td>
					<td>Amazon SigMethod</td>
					<td><input type="text" name="SigMethod" size="25" value="<?= $SigMethod ?>"></td>
				</tr>
				<tr>
					<td>Kivi-Artikel fehlender Produkte:</td>
					<td><input type="text" name="platzhalterFehlendeSKU" size="16" value="<?= $platzhalterFehlendeSKU ?>"></td>
					<td></td>
					<td>Amazon SigVersion</td>
					<td><input type="text" name="SigVersion" size="25" value="<?= $SigVersion ?>"></td>
				</tr>
				<tr>
					<td>Kivi-Artikel Versandkosten</td>
					<td><input type="text" name="versandkosten" size="25" value="<?= $versandkosten ?>"></td>
					<td></td>
					<td>Amazon MarketplaceID_DE</td>
					<td><input type="text" name="MarketplaceID_DE" size="25" value="<?= $MarketplaceID_DE ?>"></td>
				</tr>
				<tr>
					<td>Kivi-Artikel Geschenkverpackung</td>
					<td><input type="text" name="geschenkverpackung" size="25" value="<?= $geschenkverpackung ?>"></td>
					<td></td>
					<td>Amazon MarketplaceID_GB</td>
					<td><input type="text" name="MarketplaceID_GB" size="25" value="<?= $MarketplaceID_GB ?>"></td>
				</tr>
				<tr>
					<td></td>
					<td></td>
					<td></td>
					<td>Amazon MarketplaceID_FR</td>
					<td><input type="text" name="MarketplaceID_FR" size="25" value="<?= $MarketplaceID_FR ?>"></td>
				</tr>
				<tr>
					<td></td>
					<td></td>
					<td></td>
					<td>Amazon MarketplaceID_IT</td>
					<td><input type="text" name="MarketplaceID_IT" size="25" value="<?= $MarketplaceID_IT ?>"></td>
				</tr>
				<tr>
					<td></td>
					<td></td>
					<td></td>
					<td>Amazon MarketplaceID_ES</td>
					<td><input type="text" name="MarketplaceID_ES" size="25" value="<?= $MarketplaceID_ES ?>"></td>
				</tr>				
				<tr>
					<td></td>
					<td></td>
					<td></td>
					<td>Liste mit zu ersetzenden SKU<br>Amazon -> Kivi<br>(eine pro Zeile, | ist Trenner)</td>
					<td><textarea name="ersatzSKU" cols="32" rows="5"><?= $ersatzSKU ?></textarea>
				</tr>
				<tr>
					<td>------------------------------</td>
					<td>------------------------------</td>
					<td></td>
					<td>------------------------------</td>
					<td>------------------------------</td>
				</tr>
				<tr>
					<th>Wert</th>
					<th>eBay</th>
					<th></th>
					<th>Wert</th>
					<th>Joomla</th>
				</tr>
				<tr>
					<td>eBay aktiviert</td>
					<td><input type="checkbox" name="eBayaktiviert" value="checked" <? if ($eBayaktiviert == "checked") { echo "checked=\"checked\""; } ?>></td>
					<td></td>
					<td>Joomla aktiviert</td>
					<td><input type="checkbox" name="Joomlaaktiviert" value="checked" <? if ($Joomlaaktiviert == "checked") { echo "checked=\"checked\""; } ?>></td>
				</tr>				
				<tr>
					<td>eBay Abteilungsname</td>
					<td><input type="text" name="eBayAbteilungsname" size="25" value="<?= $eBayAbteilungsname ?>"></td>
					<td></td>
					<td>Joomla Abteilungsname</td>
					<td><input type="text" name="JoomlaAbteilungsname" size="25" value="<?= $JoomlaAbteilungsname ?>"></td>
				</tr>
				<tr>
					<td>eBay Bestellnummernprefix</td>
					<td><input type="text" name="eBayBestellnummernprefix" size="25" value="<?= $eBayBestellnummernprefix ?>"></td>
					<td></td>
					<td>Joomla Bestellnummernprefix</td>
					<td><input type="text" name="JoomlaBestellnummernprefix" size="25" value="<?= $JoomlaBestellnummernprefix ?>"></td>
				</tr>
				<tr>
					<td>eBay ServerUrl</td>
					<td><input type="text" name="eBayServerUrl" size="25" value="<?= $eBayServerUrl ?>"></td>
					<td></td>
					<td>Joomla-Host</td>
					<td><input type="text" name="Joomlahost" size="25" value="<?= $Joomlahost ?>"></td>
				</tr>
				<tr>
					<td>eBay DEVID</td>
					<td><input type="text" name="eBayDEVID" size="25" value="<?= $eBayDEVID ?>"></td>
					<td></td>
					<td>Joomla-Port</td>
					<td><input type="text" name="Joomlaport" size="25" value="<?= $Joomlaport ?>"></td>
				</tr>
				<tr>
					<td>eBay AppID</td>
					<td><input type="text" name="eBayAppID" size="25" value="<?= $eBayAppID ?>"></td>
					<td></td>
					<td>Joomla-Database</td>
					<td><input type="text" name="Joomladbname" size="25" value="<?= $Joomladbname ?>"></td>				
				</tr>
				<tr>
					<td>eBay CertID</td>
					<td><input type="text" name="eBayCertID" size="25" value="<?= $eBayCertID ?>"></td>
					<td></td>
					<td>Joomla db-User Name</td>
					<td><input type="text" name="Joomlauser" size="25" value="<?= $Joomlauser ?>"></td>
				</tr>
				<tr>
					<td>eBay UserToken</td>
					<td><input type="text" name="eBayUserToken" size="25" value="<?= $eBayUserToken ?>"></td>
					<td></td>
					<td>Joomla db-User PWD</td>
					<td><input type="text" name="Joomlapass" size="25" value="<?= $Joomlapass ?>"></td>
				</tr>
				<tr>
					<td colspan="5" align="center"><input type="submit" name="ok" value="sichern"></td>
				</tr>
			</form>
		</table>
	</body>
</html>
<?
}
?>
