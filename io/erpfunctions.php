<?php

require_once "DB.php";
require_once "MDB2.php";
require "conf.php";
require "constants.php";

$VERSANDKOSTEN = 0;
$GESCHENKVERPACKUNG = 0;

$dsnP = array(	'phptype'  => 'pgsql',
				'username' => $ERPuser,
				'password' => $ERPpass,
				'hostspec' => $ERPhost,
				'database' => $ERPdbname,
				'port'     => $ERPport);

$log = false;
$erp = false;

/****************************************************
* Debugmeldungen in File schreiben
****************************************************/
if ($debug == "true")		// zum Debuggen
{
	$log = fopen("tmp/shop.log","a");
}
else
{
	$log = false;
}

/****************************************************
* ERPverbindung aufbauen
****************************************************/
$options = array('result_buffering' => false,);
$erp = @DB::connect($dsnP);
$erp = MDB2::factory($dsnP, $options);

if (!$erp)
{
	echo $erp->getMessage();
}
if (PEAR::isError($erp))
{
	$aktuelleZeit = date("Y-m-d H:i:s");
	if ($log)
	{
		fputs($log,$aktuelleZeit.": ERP-Connect\n");
	}
	echo $erp->getMessage();
	die ($erp->getMessage());
}
else
{
	if ($erp->autocommit)
	{
		$erp->autocommit();
	}
}

if ($SHOPchar and ExportMode != "1")
{
    $erp->setCharset($SHOPchar);
} 
$erp->setFetchMode(MDB2_FETCHMODE_ASSOC);

/****************************************************
* SQL-Befehle absetzen
****************************************************/
function query($db, $sql, $function="--")
{
 	$aktuelleZeit = date("d.m.y H:i:s");
 	if ($GLOBALS["log"])
 	{
	 	fputs($GLOBALS["log"],$aktuelleZeit.": ".$function."\n".$sql."\n");
 	}
 	$rc = $GLOBALS[$db]->query($sql);
 	if ($GLOBALS["log"])
 	{
	 	fputs($GLOBALS["log"],print_r($rc,true)."\n");
 	}
    if(PEAR::isError($rc))
    {
		return -99;
 	}
 	else
 	{
		return true;
 	}
}

/****************************************************
* Datenbank abfragen
****************************************************/
function getAll($db, $sql, $function="--")
{
	$aktuelleZeit = date("d.m.y H:i:s");
	if ($GLOBALS["log"])
	{
		fputs($GLOBALS["log"],$aktuelleZeit.": ".$function."\n".$sql."\n");
	}
	
	$rs = $GLOBALS[$db]->queryAll($sql);
	
    if ($rs->message <> "")
    {
	    if ($GLOBALS["log"])
	    {
		    fputs($GLOBALS["log"],print_r($rs,true)."\n");
	    }
		return false;
	}
	else
	{
		return $rs;
	}
}

/****************************************************
* naechste_freie_Auftragsnummer() Naechste Auftragsnummer (ERP) holen
****************************************************/
function naechste_freie_Auftragsnummer()
{
	$sql="select * from defaults";
	$sql1="update defaults set sonumber=";
	$rs2=getAll("erp",$sql,"naechste_freie_Auftragsnummer");
	if ($rs2[0]["sonumber"]) {
		$auftrag=$rs2[0]["sonumber"]+1;
		$rc=query("erp",$sql1.$auftrag, "naechste_freie_Auftragsnummer");
		if ($rc === -99) {
			echo "Kann keine Auftragsnummer erzeugen - Abbruch";
			exit();
		}
		return $auftrag;
	} else {
		return false;
	}
}

/****************************************************
* naechste_freie_Kundennummer() Naechste Kundennummer (ERP) holen
****************************************************/
function naechste_freie_Kundennummer()
{
	$sql = "select * from defaults";
	$sql1 = "update defaults set customernumber='";
	$rs2 = getAll("erp", $sql, "naechste_freie_Kundennummer");
	if ($rs2[0]["customernumber"])
	{
		$kdnr = $rs2[0]["customernumber"] + 1;
		$rc = query("erp", $sql1.$kdnr."'", "naechste_freie_Kundennummer");
		if ($rc === -99)
		{
			echo "Kann keine Kundennummer erzeugen - Abbruch";
			exit();
		}
		return $kdnr;
	}
	else
	{
		return false;
	}
}

/**********************************************
* insert_Versandadresse($bestellung, $kundenid)
***********************************************/
function insert_Versandadresse($bestellung, $kundenid)
{
	$set = $kundenid;
	if ($bestellung["ship-address-2"] != "")
	{
		$set .= ",'".$bestellung["recipient-name"]."','".$bestellung["ship-address-1"]."','".$bestellung["ship-address-2"]."',";
	}
	else
	{
		$set .= ",'".$bestellung["recipient-name"]."','','".$bestellung["ship-address-1"]."',";
	}
	$set .= "'".$bestellung["ship-postal-code"]."',";
	$set .= "'".$bestellung["ship-city"]."',";
	
	if (array_key_exists($bestellung["ship-country"], $GLOBALS["LAND"]))
	{
		$set .= "'".utf8_encode($GLOBALS["LAND"][$bestellung["ship-country"]])."'";
	}
	else
	{
		$set .= "'".$bestellung["ship-country"]."'";
	}
	
	$sql = "insert into shipto (trans_id, shiptoname, shiptodepartment_1, shiptostreet, shiptozipcode, shiptocity, shiptocountry, module) values ($set,'CT')";
	$rc = query("erp", $sql, "insert_Versandadresse");
	if ($rc === -99)
	{
		return false;
	}
	$sql = "select shipto_id from shipto where trans_id=$kundenid AND module='CT' order by itime desc limit 1";
	$rs = getAll("erp", $sql, "insert_Versandadresse");
	if ($rs[0]["shipto_id"] > 0)
	{
		$sid = $rs[0]["shipto_id"];
		return $sid;
	}
	else
	{
		echo "Fehler bei abweichender Anschrift ".$bestellung["recipient-name"];
		return false;
	}
}
            
/**********************************************
* check_update_Kundendaten($bestellung)
***********************************************/
function check_update_Kundendaten($bestellung)
{
	$rc = query("erp","BEGIN WORK","check_update_Kundendaten");
	
	if ($rc === -99)
	{
		echo "Probleme mit Transaktion. Abbruch!";
		exit();
	}
	if (checkCustomer($bestellung['BuyerEmail'], $bestellung['BuyerName']) == "vorhanden")  // Bestandskunde; BuyerEmail (Amazon eindeutig) oder BuyerName vorhanden
	{
		$msg = "update ";
		$kdnr = checke_alte_Kundendaten($bestellung);
		if ($kdnr == -1)		// Kunde nicht gefunden, neu anlegen.
		{
			$msg = "insert ";
			$kdnr = insert_neuen_Kunden($bestellung);
		}
		else if (!$kdnr)
		{
			echo $msg." ".$bestellung["BuyerName"]." fehlgeschlagen!<br>";
			continue;
		}
	}
	else	// Neukunde
	{
		$msg = "insert ";
		$kdnr = insert_neuen_Kunden($bestellung);
	}
	
	echo $bestellung["BuyerName"]." ".$bestellung["Name"]." $kdnr<br>";

	// Ggf. Versandadressen eintragen
	$versandadressennummer = 0;
	if ($kdnr > 0)
	{
		if ((trim($bestellung["recipient-name"]) <> "") &&
				($bestellung["Title"] <> $bestellung["recipient-title"] ||
				trim($bestellung["Name"]) <> trim($bestellung["recipient-name"]) ||
				$bestellung["AddressLine1"] <> $bestellung["ship-address-1"] ||
				$bestellung["AddressLine2"] <> $bestellung["ship-address-2"] ||
				$bestellung["PostalCode"] <> $bestellung["ship-postal-code"] ||
				$bestellung["City"] <> $bestellung["ship-city"] ||
				$bestellung["StateOrRegion"] <> $bestellung["ship-state"] ||
				$bestellung["CountryCode"] <> $bestellung["ship-country"]
				))
		{
			$rc = insert_Versandadresse($bestellung, $kdnr);
			$versandadressennummer = $rc;
		}
	}
	
	if (!$kdnr || $rc === -99)
	{
		echo $msg." ".$bestellung["BuyerName"]." fehlgeschlagen! ($kdnr, $rc)<br>";
		$rc = query("erp", "ROLLBACK WORK", "check_update_Kundendaten");
		if ($rc === -99)
		{
			echo "Probleme mit Transaktion. Abbruch!";
			exit();
		}
	}
	else
	{
		$rc = query("erp", "COMMIT WORK", "check_update_Kundendaten");
		if ($rc === -99)
		{
			echo "Probleme mit Transaktion. Abbruch!";
			exit();
		}
	}
	return $kdnr."|".$versandadressennummer;
}

/**********************************************
* checke_alte_Kundendaten($bestellung)
***********************************************/
function checke_alte_Kundendaten($bestellung)
{
	$sql = "select * from customer where ";
	if ($bestellung["BuyerEmail"] != "") { $sql .= "email = '".$bestellung["BuyerEmail"]."'"; }
	if ($bestellung["BuyerEmail"] != "" && $bestellung["BuyerName"] != "") { $sql .= " OR "; }
	if ($bestellung["BuyerName"] != "") { $sql .= "user = '".$bestellung["BuyerName"]."'"; }
	
	$rs = getAll("erp", $sql, "checke_alte_Kundendaten");
	
	if (!$rs || count($rs) != 1)	// Kunde nicht gefunden
	{
		return -1;
	}
	$set = "";
	// Wenn Kunde gefunden, ab hier die Kundendaten auf den neusten Stand bringen
	if ($rs[0]["name"] <> $bestellung["Name"])
	{
		$name = pg_escape_string($bestellung["Name"]);
		$set.="name='".$name."',";
	}
	if ($rs[0]["greeting"] <> $bestellung["Title"])
	{
		$set.="greeting='".$bestellung["Title"]."',";
	}
	if ($bestellung["AddressLine2"] != "")
	{
		$department_1 = pg_escape_string($bestellung["AddressLine1"]);
		$street = pg_escape_string($bestellung["AddressLine2"]);
		if ($rs[0]["department_1"] <> $bestellung["AddressLine1"])
		{
			$set.="department_1='".$department_1."',";
		}
		if ($rs[0]["street"] <> $bestellung["AddressLine2"])
		{
			$set.="street='".$street."',";
		}
	}
	else 
	{
		$street = pg_escape_string($bestellung["AddressLine1"]);
		if ($rs[0]["street"] <> $bestellung["AddressLine1"])
		{
			$set.="street='".$street."',";
		}
	}
	if ($rs[0]["zipcode"] <> $bestellung["PostalCode"])
	{
		$set.="zipcode='".$bestellung["PostalCode"]."',";
	}
	if ($rs[0]["city"] <> $bestellung["City"])
	{
		$city = pg_escape_string($bestellung["City"]);
		$set.="city='".$city."',";
	}
	if (array_key_exists($bestellung["CountryCode"], $GLOBALS["LAND"]))
	{
		if ($rs[0]["country"] <> $GLOBALS["LAND"][$bestellung["CountryCode"]])
		{
			$set.="country='".utf8_encode($GLOBALS["LAND"][$bestellung["CountryCode"]])."',";
		}
	}
	else
	{
		if ($rs[0]["country"] <> $bestellung["CountryCode"])
		{
			$set.="country='".$bestellung["CountryCode"]."',";
		}
	}
	if ($rs[0]["phone"] <> $bestellung["Phone"])
	{
		$set.="phone='".$bestellung["Phone"]."',";
	}
	if ($rs[0]["email"] <> $bestellung["BuyerEmail"])
	{
		$set.="email='".$bestellung["BuyerEmail"]."',";
	}
	if ($rs[0]["username"] <> $bestellung["BuyerName"])
	{
		$set.="username='".$bestellung["BuyerName"]."',";
	}
	
	if (array_key_exists($bestellung["CountryCode"], $GLOBALS["TAXID"]))
	{	
		$localtaxid = $GLOBALS["TAXID"][$bestellung["CountryCode"]];
	}
	else
	{
		$localtaxid = 3;	// Wenn nicht vorhanden, dann vermutlich Steuerschluessel Welt
	}
	if ($rs[0]["taxzone_id"] <> $localtaxid)
	{
		$set .= "taxzone_id=$localtaxid ";
	}

	if ($set)
	{
		$sql = "update customer set ".substr($set,0,-1)." where id=".$rs[0]["id"];
		$rc = query("erp", $sql, "checke_alte_Kundendaten");
		if ($rc === -99)
		{
			return false;
		}
		else
		{
			return $rs[0]["id"];
		}
	}
	else
	{
		return $rs[0]["id"];
	}
}

/**********************************************
* insert_neuen_Kunden($bestellung)
***********************************************/
function insert_neuen_Kunden($bestellung)
{
	$newID = uniqid(rand(time(),1));
	// Kundennummer generieren von der ERP
	$kdnr = naechste_freie_Kundennummer();

	$sql= "select count(*) as anzahl from customer where customernumber = '$kdnr'";
	$rs = getAll("erp", $sql, "insert_neuen_Kunden");
	if ($rs[0]["anzahl"] > 0)	// Kundennummer gibt es schon, eine neue aus ERP
	{
		$kdnr = naechste_freie_Kundennummer();
	}
	$sql= "insert into customer (name,customernumber) values ('$newID','$kdnr')";
	$rc = query("erp", $sql, "insert_neuen_Kunden");
	if ($rc === -99)
	{
		return false;
	}
	$sql = "select * from customer where name = '$newID'";
	$rs = getAll("erp", $sql, "insert_neuen_Kunden");
	if (!$rs)
	{
		return false;
	}
	$name = pg_escape_string($bestellung["Name"]);
	$set .= "set name='".$name."',";
	if ($bestellung["Title"] != "")
	{
		$set .= "greeting='".$bestellung["Title"]."',";
	}
	if ($bestellung["AddressLine2"] != "")
	{
		$department_1 = pg_escape_string($bestellung["AddressLine1"]);
		$street = pg_escape_string($bestellung["AddressLine2"]);
		$set .= "department_1='".$department_1."',";
		$set .= "street='".$street."',";
	}
	else 
	{
		$street = pg_escape_string($bestellung["AddressLine1"]);
		$set .= "street='".$street."',";
	}
	$set .= "zipcode='".$bestellung["PostalCode"]."',";
	$city = pg_escape_string($bestellung["City"]);
	$set .= "city='".$city."',";
	if (array_key_exists($bestellung["CountryCode"], $GLOBALS["LAND"]))
	{
		$set .= "country='".utf8_encode($GLOBALS["LAND"][$bestellung["CountryCode"]])."',";
	}
	else
	{
		$set .= "country='".$bestellung["CountryCode"]."',";
	}
	$set .= "phone='".$bestellung["Phone"]."',";
	$set .= "email='".$bestellung["BuyerEmail"]."',";
	$set .= "username='".$bestellung["BuyerName"]."',";

	if (array_key_exists($bestellung["CountryCode"], $GLOBALS["TAXID"]))
	{	
		$localtaxid = $GLOBALS["TAXID"][$bestellung["CountryCode"]];
	}
	else
	{
		$localtaxid = 3;	// Wenn nicht vorhanden, dann vermutlich Steuerschluessel Welt
	}

	$set .= "taxzone_id=$localtaxid ";

	$sql = "update customer ".$set;
	$sql .= "where id=".$rs[0]["id"];
	$rc = query("erp", $sql, "insert_neuen_Kunden");
	if ($rc === -99)
	{
		return false;
	}
	else
	{
		return $rs[0]["id"];
	}
}

/**********************************************
* einfuegen_bestellte_Artikel($artikelliste, $AmazonOrderId, $zugehoerigeAuftragsID, $zugehoerigeAuftragsNummer)
***********************************************/
function einfuegen_bestellte_Artikel($artikelliste, $AmazonOrderId, $zugehoerigeAuftragsID, $zugehoerigeAuftragsNummer)
{
	require "conf.php";

	$ok = true;
	$GLOBALS["VERSANDKOSTEN"] = 0;
	$GLOBALS["GESCHENKVERPACKUNG"] = 0;

	foreach ($artikelliste as $einzelartikel)
	{
		$sql = "select * from parts where partnumber='".$einzelartikel["SellerSKU"]."'";
		$rs2 = getAll("erp", $sql, "einfuegen_bestellte_Artikel");
		if ($rs2[0]["id"])
		{
			$artID = $rs2[0]["id"];
			$artNr = $rs2[0]["partnumber"];
			$ordnumber = $zugehoerigeAuftragsNummer;
			$lastcost = $rs2[0]["lastcost"];
			$longdescription = $rs2[0]["notes"];
			$einzelpreis = round($einzelartikel["ItemPrice"] / $einzelartikel["QuantityOrdered"], 2, PHP_ROUND_HALF_UP) - round($einzelartikel["PromotionDiscount"] / $einzelartikel["QuantityOrdered"], 2, PHP_ROUND_HALF_UP);
			$text = $rs2[0]["description"];
			
			$sql = "insert into orderitems (trans_id, ordnumber, parts_id, description, longdescription, qty, cusordnumber, sellprice, lastcost, unit, ship, discount) values (";
			$sql .= $zugehoerigeAuftragsID.","
					.$ordnumber.",'"
					.$artID."','"
					.$text."','"
					.$longdescription."',"
					.$einzelartikel["QuantityOrdered"].",'"
					.$AmazonOrderId."',"
					.$einzelpreis.","
					.$lastcost.","
					."'Stck',0,0)";
					
			echo " - Artikel:[ Artikel-ID:$artID Artikel-Nummer:<b>$artNr</b> ".$einzelartikel["Title"]." ]<br>";
			$rc = query("erp", $sql, "einfuegen_bestellte_Artikel");
			if ($rc === -99)
			{
				$ok = false;
				break;
			}
		}
		else if ($fehlendeSKU == "true")	// Artikel nicht im Kivitendo, -> Amazon-Werte übernehmen
		{
			$sql = "select id, partnumber from parts where partnumber='".$platzhalterFehlendeSKU."'";
			$rs3 = getAll("erp", $sql, "einfuegen_bestellte_Artikel");
			if ($rs3[0]["id"])
			{
				$artID = $rs3[0]["id"];
				$artNr = $rs3[0]["partnumber"]." (".$einzelartikel["SellerSKU"].")";
				$einzelpreis = round($einzelartikel["ItemPrice"] / $einzelartikel["QuantityOrdered"], 2, PHP_ROUND_HALF_UP) - round($einzelartikel["PromotionDiscount"] / $einzelartikel["QuantityOrdered"], 2, PHP_ROUND_HALF_UP);
				$text = $einzelartikel["Title"];
				
				$sql = "insert into orderitems (trans_id, parts_id, description, qty, longdescription, sellprice, unit, ship, discount) values (";
				$sql .= $zugehoerigeAuftragsID.",'"
						.$artID."','"
						.$text."',"
						.$einzelartikel["QuantityOrdered"].",'"
						.$AmazonOrderId."',"
						.$einzelpreis.",'Stck',0,0)";
						
				echo " - Artikel:[ Artikel-ID:$artID Artikel-Nummer:<b>$artNr</b> ".$einzelartikel["Title"]." ]<br>";
				$rc = query("erp", $sql, "einfuegen_bestellte_Artikel");
				if ($rc === -99)
				{
					$ok = false;
					break;
				}
			}
		}
		$GLOBALS["VERSANDKOSTEN"] += $einzelartikel["ShippingPrice"] - $einzelartikel["ShippingDiscount"];
		$GLOBALS["GESCHENKVERPACKUNG"] += $einzelartikel["GiftWrapPrice"];
	}
	return $ok;
}

/**********************************************
* hole_department_id($department_klarname)
***********************************************/
function hole_department_id($department_klarname)
{
	$sql = "select id from department where description='".$department_klarname."'";
	$abfrage = getAll("erp", $sql, "hole_department_id");
	if ($abfrage[0]["id"])
	{
		return $abfrage[0]["id"];
	}
	return "NULL";
}

/**********************************************
* hole_payment_id($zahlungsart)
***********************************************/
function hole_payment_id($zahlungsart)
{
	$sql = "select id from payment_terms where description='".$zahlungsart."'";
	$abfrage = getAll("erp", $sql, "hole_payment_id");
	if ($abfrage[0]["id"])
	{
		return $abfrage[0]["id"];
	}
	return "NULL";
}

/**********************************************
* erstelle_Auftrag($bestellung, $kundennummer, $versandadressennummer, $ERPusrID)
***********************************************/
function erstelle_Auftrag($bestellung, $kundennummer, $versandadressennummer, $ERPusrID)
{
	require "conf.php";
	
	$brutto = $bestellung["Amount"];
	$netto = round($brutto / 1.19, 2, PHP_ROUND_HALF_UP);
	
	// Hier beginnt die Transaktion
	$rc = query("erp","BEGIN WORK","erstelle_Auftrag");
	if ($rc === -99)
	{
		echo "Probleme mit Transaktion. Abbruch!"; exit();
	}
	$auftrag = naechste_freie_Auftragsnummer();

	$sql = "select count(*) as anzahl from oe where ordnumber = '$auftrag'";
	$rs = getAll("erp", $sql, "erstelle_Auftrag 1");
	if ($rs[0]["anzahl"] > 0)
	{
		$auftrag = naechste_freie_Auftragsnummer();
	}
	$newID = uniqid (rand());
	$sql = "insert into oe (notes,ordnumber,customer_id) values ('$newID','$auftrag','".$kundennummer."')";
	$rc = query("erp", $sql, "erstelle_Auftrag 2");
	if ($rc === -99)
	{
		echo "Auftrag ".$bestellung["AmazonOrderId"]." konnte nicht angelegt werden.<br>";
		$rc = query("erp", "ROLLBACK WORK", "erstelle_Auftrag");
		return false;
	}
	$sql = "select * from oe where notes = '$newID'";
	$rs2 = getAll("erp", $sql, "erstelle_Auftrag 3");
	if (!$rs2 > 0)
	{
		echo "Auftrag ".$bestellung["AmazonOrderId"]." konnte nicht angelegt werden.<br>";
		$rc = query("erp", "ROLLBACK WORK", "erstelle_Auftrag");
		return false;
	}

	$sql = "update oe set cusordnumber='".$bestellung["AmazonOrderId"]."', transdate='".$bestellung["PurchaseDate"]."', customer_id=".$kundennummer.", ";
	if ($versandadressennummer > 0)
	{
		$sql .= "shipto_id=".$versandadressennummer.", ";
	}
	$sql .= "department_id=".hole_department_id($bestellung["MarketplaceId"]).", shippingpoint='".utf8_encode($GLOBALS["VERSAND"][$bestellung["FulfillmentChannel"]])."', ";
	$sql .= "amount=".$brutto.", netamount=".$netto.", reqdate='".$bestellung["LastUpdateDate"]."', taxincluded='t', ";
	// Versandadresse prüfen (selbige gibt wenn vorhanden den Steuerschluessel vor!
	if ($bestellung["ship-country"] != "")
	{
		if (array_key_exists($bestellung["ship-country"], $GLOBALS["TAXID"]))
		{	
			$localtaxid = $GLOBALS["TAXID"][$bestellung["ship-country"]];
		}
		else
		{
			$localtaxid = 3;	// Wenn nicht vorhanden, dann vermutlich Steuerschluessel Welt
		}
	}
	else
	{
		if (array_key_exists($bestellung["CountryCode"], $GLOBALS["TAXID"]))
		{	
			$localtaxid = $GLOBALS["TAXID"][$bestellung["CountryCode"]];
		}
		else
		{
			$localtaxid = 3;	// Wenn nicht vorhanden, dann vermutlich Steuerschluessel Welt
		}
	}
	$sql .= "taxzone_id=$localtaxid, ";
	$sql .= "payment_id=".hole_payment_id($bestellung["PaymentMethod"]).", ";
	$bestelldatum = "Bestelldatum: ".date("d.m.Y", strtotime($bestellung["PurchaseDate"])).chr(13);
	$versanddatum = "Versanddatum: ".date("d.m.Y", strtotime($bestellung["LastUpdateDate"])).chr(13);
	if ($bestellung["CurrencyCode"] != "EUR")
	{
		$waehrungstext = chr(13)."Originalwaehrung: ".$bestellung["CurrencyCode"].chr(13)."Originalbetrag: ".$bestellung["Amount"]." ".$bestellung["CurrencyCode"].chr(13)."Kurs 1 ".$bestellung["CurrencyCode"]." = x.xx EUR";
	}
	$sql .= "notes='".$bestellung["OrderComment"]."', intnotes='".$bestelldatum.$versanddatum."SalesChannel ".$bestellung["SalesChannel"]." (".$bestellung["CountryCode"].")".chr(13)."Versand durch ".utf8_encode($GLOBALS["VERSAND"][$bestellung["FulfillmentChannel"]]).$waehrungstext."', ";
	$sql .= "curr='".$bestellung["CurrencyCode"]."', employee_id=".$ERPusrID.", vendor_id=NULL ";
	$sql .= "where id=".$rs2[0]["id"];
	
	$rc = query("erp",$sql,"erstelle_Auftrag 4");	
	if ($rc === -99)
	{
		echo "Auftrag ".$bestellung["AmazonOrderId"]." konnte nicht angelegt werden.<br>";
		$rc = query("erp", "ROLLBACK WORK", "erstelle_Auftrag");
		if ($rc === -99)
		{
			echo "Probleme mit Transaktion. Abbruch!"; exit();
		}
		return false;
	}
	echo "Auftrag:[ Buchungsnummer:".$rs2[0]["id"]." AuftragsNummer:<b>".$auftrag."</b> ]<br>";
	
	if (!einfuegen_bestellte_Artikel(array_values($bestellung['AmazonOrderIdProducts']), $bestellung["AmazonOrderId"], $rs2[0]["id"], $auftrag))
	{
		echo "Auftrag ".$bestellung["AmazonOrderId"]." konnte nicht angelegt werden.<br>";
		$rc = query("erp", "ROLLBACK WORK", "erstelle_Auftrag");
		if ($rc === -99)
		{
			echo "Probleme mit Transaktion. Abbruch!"; exit();
		}
		return false;
	}
	
	if ($GLOBALS["VERSANDKOSTEN"] > 0)
	{
		$sql = "select * from parts where partnumber='".$versandkosten."'";
		$rsversand = getAll("erp", $sql, "erstelle_Auftrag");
		if ($rsversand[0]["id"])
		{
			$artID = $rsversand[0]["id"];
			$artNr = $rsversand[0]["partnumber"];
			$einzelpreis = $GLOBALS["VERSANDKOSTEN"];
			$text = $rsversand[0]["description"];
			
			$sql = "insert into orderitems (trans_id, parts_id, description, qty, longdescription, sellprice, unit, ship, discount) values (";
			$sql .= $rs2[0]["id"].",'"
					.$artID."','"
					.$text."',"
					."1,'"
					.$versandkosten."',"
					.$einzelpreis.",'Stck',0,0)";
					
			echo " - Artikel:[ Artikel-ID:$artID Artikel-Nummer:<b>$artNr</b> ".$text." ]<br>";
			$rc = query("erp", $sql, "erstelle_Auftrag");
			if ($rc === -99)
			{
				echo "Auftrag $auftrag : Fehler bei den Versandkosten<br>";
			}
		}
	}
	
	if ($GLOBALS["GESCHENKVERPACKUNG"] > 0)
	{
		$sql = "select * from parts where partnumber='".$geschenkverpackung."'";
		$rsversand = getAll("erp", $sql, "erstelle_Auftrag");
		if ($rsversand[0]["id"])
		{
			$artID = $rsversand[0]["id"];
			$artNr = $rsversand[0]["partnumber"];
			$einzelpreis = $GLOBALS["GESCHENKVERPACKUNG"];
			$text = $rsversand[0]["description"];
			
			$sql = "insert into orderitems (trans_id, parts_id, description, qty, longdescription, sellprice, unit, ship, discount) values (";
			$sql .= $rs2[0]["id"].",'"
					.$artID."','"
					.$text."',"
					."1,'"
					.$geschenkverpackung."',"
					.$einzelpreis.",'Stck',0,0)";
					
			echo " - Artikel:[ Artikel-ID:$artID Artikel-Nummer:<b>$artNr</b> ".$text." ]<br>";
			$rc = query("erp", $sql, "erstelle_Auftrag");
			if ($rc === -99)
			{
				echo "Auftrag $auftrag : Fehler bei den Geschenkverpackungskosten<br>";
			}
		}	
	}

	$rc = query("erp", "COMMIT WORK", "erstelle_Auftrag");
	if ($rc === -99)
	{
		echo "Probleme mit Transaktion. Abbruch!"; exit();
	}
	return true;
}

/**********************************************
* checkAmazonOrderId($AmazonOrderId)
***********************************************/
function checkAmazonOrderId($AmazonOrderId)
{
	require_once "DB.php";
	require "conf.php";
	
	$dsnP = array(
			'phptype'  => 'pgsql',
			'username' => $ERPuser,
			'password' => $ERPpass,
			'hostspec' => $ERPhost,
			'database' => $ERPdbname,
			'port'     => $ERPport
            );
            
	$status = "neu";
	
	$dbP = @DB::connect($dsnP);
	if (DB::isError($dbP)||!$dbP)
	{
		$status = "Keine Verbindung zur ERP<br>".$dbP->userinfo;
		$dbP = false;
	}
	else
	{
		// Auftraege checken
		$rs = $dbP->getall("select cusordnumber from oe where cusordnumber = '".$AmazonOrderId."'");
		if (count($rs) >= 1)
		{
			$status = "auftrag";
		}
		
		// Lieferscheine checken
		$rs = $dbP->getall("select cusordnumber from delivery_orders where cusordnumber = '".$AmazonOrderId."'");
		if (count($rs) >= 1)
		{
			$status = "lieferschein";
		}

		// Rechnungen checken
		$rs = $dbP->getall("select cusordnumber from ar where cusordnumber = '".$AmazonOrderId."'");
		if (count($rs) >= 1)
		{
			$status = "rechnung";
		}
		
		// Emails checken
		if ($status == "rechnung")
		{
			$rs = $dbP->getall("select cusordnumber from ar where cusordnumber = '".$AmazonOrderId."' and intnotes LIKE '%[email]%'");
			if (count($rs) >= 1)
			{
				$status = "email";
			}
		}
	}
	
	return $status;
}

/**********************************************
* checkCustomer($BuyerEmail, $BuyerName)
***********************************************/
function checkCustomer($BuyerEmail, $BuyerName)
{
	require_once "DB.php";
	require "conf.php";
	
	$dsnP = array(
			'phptype'  => 'pgsql',
			'username' => $ERPuser,
			'password' => $ERPpass,
			'hostspec' => $ERPhost,
			'database' => $ERPdbname,
			'port'     => $ERPport
            );
            
	$status = "neu";
	
	$dbP = @DB::connect($dsnP);
	if (DB::isError($dbP)||!$dbP)
	{
		$status = "Keine Verbindung zur ERP<br>".$dbP->userinfo;
		$dbP = false;
	}
	else if ($BuyerEmail == "" && $BuyerName == "")
	{
		$status = "-";
	}
	else
	{
		// Email checken
		if ($BuyerEmail != "")
		{
			$rs = $dbP->getall("select customernumber from customer where email = '".$BuyerEmail."'");
			if (count($rs) == 1)
			{
				$status = "vorhanden";
			}
		}

		if ($BuyerName != "")
		{
			// BuyerName checken
			$rs = $dbP->getall("select customernumber from customer where username = '".$BuyerName."'");
			if (count($rs) == 1)
			{
				$status = "vorhanden";
			}
		}
	}
	
	return $status;
}
?>