<?php
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
	
	function cmpversand($a, $b)
	{
		return strcmp($a['LastUpdateDate'], $b['LastUpdateDate']);
	}
	function cmpbestell($a, $b)
	{
		return strcmp($a['PurchaseDate'], $b['PurchaseDate']);
	}

	if ($_SERVER['PHP_AUTH_USER']<>$ERPftpuser || $_SERVER['PHP_AUTH_PW']<>$ERPftppwd)
	{
		Header("WWW-Authenticate: Basic realm=\"My Realm\"");
		Header("HTTP/1.0 401 Unauthorized");
		echo "Sie m&uuml;ssen sich autentifizieren\n";
		exit;
	}
	
	require "erpfunctions.php";
	require "amazonfunctions.php";
	require "joomlafunctions.php";
	require "ebayfunctions.php";
	
	// Variablen definieren: wieviele Tage in Vergangenheit gezeigt werden sollen:
	$daysBeforeFrom	= "9";
	
	echo "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/transitional.dtd\">";
	echo "<html>";
	echo "<head>";
	echo "	<title>Amazon-Import</title>";
	echo "	<meta http-equiv=\"content-type\" content=\"text/html; charset=ISO-8859-1\">";
	echo "	<script type=\"text/javascript\" src=\"calendarDateInput.js\">";
	echo "		/***********************************************";
	echo "		* Jason's Date Input Calendar- By Jason Moon http://calendar.moonscript.com/dateinput.cfm";
	echo "		* Script featured on and available at http://www.dynamicdrive.com";
	echo "		* Keep this notice intact for use.";
	echo "		***********************************************/";
	echo "	</script>";
	echo "</head>";
	echo "<body>";
	
	if (isset($_POST["ansicht"]) &&  $_POST["ansicht"] == "detailansicht") {
		$listenansicht_checked = "";
		$detailansicht_checked = "checked=\"checked\"";
	} else {
		$listenansicht_checked = "checked=\"checked\"";
		$detailansicht_checked = "";
	}
	if (isset($_POST["erledigtesanzeigen"])) {
		$erledigtesanzeigen = "checked=\"checked\"";
	} else {
		$erledigtesanzeigen = "";
	}
	if (isset($_POST["suchdatum"]) &&  $_POST["suchdatum"] == "bestelldatum") {
		$versanddatum_checked = "";
		$bestelldatum_checked = "checked=\"checked\"";
	} else {
		$versanddatum_checked = "checked=\"checked\"";
		$bestelldatum_checked = "";
	}
	if (isset($_POST["bestellungvom"])) {
		$date_from = explode("-", $_POST["bestellungvom"]);
		$bestellungvom = strtoupper(gmdate("d-M-Y", mktime(12, 0, 0, $date_from[1], $date_from[0], $date_from[2])));
	} else {
		$bestellungvom = strtoupper(gmdate("d-M-Y", time()-86400*$daysBeforeFrom));
	}
	if (isset($_POST["bestellungbis"])) {
		$date_bis = explode("-", $_POST["bestellungbis"]);
		$bestellungbis = strtoupper(gmdate("d-M-Y", mktime(12, 0, 0, $date_bis[1], $date_bis[0], $date_bis[2])));
	} else {
		$bestellungbis = strtoupper(gmdate("d-M-Y", time()-120));
	}
	if (isset($_POST["fulfillmentchannel"]) &&  $_POST["fulfillmentchannel"] == "haendler") {
		$amazon_checked = "";
		$haendler_checked = "checked=\"checked\"";
	} else {
		$amazon_checked = "checked=\"checked\"";
		$haendler_checked = "";
	}
	if (isset($_POST["versandstatus"])) {
		$versandstatus = $_POST['versandstatus'];
		if (in_array("shipped", $versandstatus)) { $versandstatus_shipped = "checked=\"checked\""; } else { $versandstatus_shipped = ""; }
		if (in_array("pending", $versandstatus)) { $versandstatus_pending = "checked=\"checked\""; } else { $versandstatus_pending = ""; }
		if (in_array("partiallyunshipped", $versandstatus) || $_POST["fulfillmentchannel"] == "haendler") { $versandstatus_partiallyunshipped = "checked=\"checked\""; } else { $versandstatus_partiallyunshipped = ""; }
		if (in_array("canceled", $versandstatus)) { $versandstatus_canceled = "checked=\"checked\""; } else { $versandstatus_canceled = ""; }
		if (in_array("unfulfillable", $versandstatus)) { $versandstatus_unfulfillable = "checked=\"checked\""; } else { $versandstatus_unfulfillable = ""; }
	}
	else
	{
		$versandstatus_shipped = "checked=\"checked\"";
	}
	
	echo "<form name=\"bestellauswahl\" action=\"shoptoerp.php\" method=\"post\">";
	echo	"<table style=\"background-color:#cccccc\">"
				."<tr><p>"
					."<td>Listenansicht</td>"
					."<td><input type=\"radio\" name=\"ansicht\" value=\"listenansicht\" ".$listenansicht_checked."></td>"
					."<td>Detailansicht</td>"
					."<td><input type=\"radio\" name=\"ansicht\" value=\"detailansicht\" ".$detailansicht_checked."></td>"
				."</p></tr>"
				."<tr>"
					."<td>Erledigtes anzeigen</td>"
					."<td><input type=\"checkbox\" name=\"erledigtesanzeigen\" value=\"erledigtesanzeigen\" ".$erledigtesanzeigen."></td>"
					."<td></td>"
					."<td></td>"
				."</tr>"
				."<tr><p>"
					."<td>Versanddatum</td>"
					."<td><input type=\"radio\" name=\"suchdatum\" value=\"versanddatum\" ".$versanddatum_checked."></td>"
					."<td>Bestelldatum</td>"
					."<td><input type=\"radio\" name=\"suchdatum\" value=\"bestelldatum\" ".$bestelldatum_checked."></td>"
				."</p></tr>"
		 		."<tr>"
		 			."<td>Bestellungen vom </td>"
					."<td><script>DateInput('bestellungvom', true, 'DD-MM-YYYY', '".$bestellungvom."')</script></td>"
					."<td>Bestellungen bis </td>"
					."<td><script>DateInput('bestellungbis', true, 'DD-MM-YYYY', '".$bestellungbis."')</script></td>"
				."</tr>"
				."<tr>"
					."<td>Amazon Fulfillment (nur Amazon)</td>"
					."<td><input type=\"radio\" name=\"fulfillmentchannel\" value=\"amazon\" ".$amazon_checked."></td>"
					."<td>Haendler Fulfillment (Amazon, Ebay, Joomla)</td>"
					."<td><input type=\"radio\" name=\"fulfillmentchannel\" value=\"haendler\" ".$haendler_checked."></td>"
				."</tr>"
				."<tr>"
					."<td><input type=\"checkbox\" name=\"versandstatus[]\" value=\"shipped\" ".$versandstatus_shipped.">Shipped</td>"
					."<td><input type=\"checkbox\" name=\"versandstatus[]\" value=\"pending\" ".$versandstatus_pending.">Pending</td>"
					."<td><input type=\"checkbox\" name=\"versandstatus[]\" value=\"partiallyunshipped\" ".$versandstatus_partiallyunshipped.">Partially Shipped / Unshipped</td>"
					."<td><input type=\"checkbox\" name=\"versandstatus[]\" value=\"canceled\" ".$versandstatus_canceled.">Canceled<br><input type=\"checkbox\" name=\"versandstatus[]\" value=\"unfulfillable\" ".$versandstatus_unfulfillable.">Unfulfillable</td>"
				."</tr>"
			."</table>";
	echo 	"<br><input type=\"submit\" name=\"bestellungen\" value=\"Bestellungen anzeigen\"><br>";
	
	if (isset($_POST["bestellungen"]) && isset($_POST["bestellungvom"]))
	{
		if (isset($_POST["bestellungbis"]))
		{
			$output = array();
			if ($Amazonaktiviert == "checked")
			{
				$amazonresult = getAmazonOrders($_POST["fulfillmentchannel"], $_POST["versandstatus"], $_POST["suchdatum"], isset($_POST["erledigtesanzeigen"]), $_POST["bestellungvom"], $_POST["bestellungbis"]);
				if(count($amazonresult) > 0)
				{
					$output = array_merge($output, $amazonresult);
				}
			}
			if ($eBayaktiviert == "checked")
			{
				$ebayresult = getEbayOrders($_POST["fulfillmentchannel"], $_POST["bestellungvom"], $_POST["bestellungbis"]);
				if(count($ebayresult) > 0)
				{
					$output = array_merge($output, $ebayresult);
				}
			}
			if ($Joomlaaktiviert == "checked")
			{
				$joomlaresult = getJoomlaOrders($_POST["fulfillmentchannel"], $_POST["bestellungvom"], $_POST["bestellungbis"]);
				if(count($joomlaresult) > 0)
				{
					$output = array_merge($output, $joomlaresult);
				}
			}
								
			// output sortieren
			if ($suchdatum == "versanddatum")
			{
				usort($output, "cmpversand");
			}
			else
			{
				usort($output, "cmpbestell");
			}
		}
		else
		{
			$output = array();
			if ($Amazonaktiviert == "checked")
			{
				$amazonresult = getAmazonOrders($_POST["fulfillmentchannel"], $_POST["versandstatus"], $_POST["suchdatum"], isset($_POST["erledigtesanzeigen"]), $_POST["bestellungvom"], "");
				if(count($amazonresult) > 0)
				{
					$output = array_merge($output, $amazonresult);
				}
			}
			if ($eBayaktiviert == "checked")
			{
				$ebayresult = getEbayOrders($_POST["fulfillmentchannel"], $_POST["bestellungvom"], "");
				if(count($ebayresult) > 0)
				{
					$output = array_merge($output, $ebayresult);
				}
			}
			if ($Joomlaaktiviert == "checked")
			{
				$joomlaresult = getJoomlaOrders($_POST["fulfillmentchannel"], $_POST["bestellungvom"], "");
				if(count($joomlaresult) > 0)
				{
					$output = array_merge($output, $joomlaresult);
				}
			}

			// output sortieren
			if ($suchdatum == "versanddatum")
			{
				usort($output, "cmpversand");
			}
			else
			{
				usort($output, "cmpbestell");
			}
		}
	
		echo "<br>Bestellungen:<br><div>";
		
		// wenn Fehler, diese ausgeben, sonst Rückgabe in Tabelle anzeigen:
		if (array_key_exists('error', $output) && $output['error'])
		{
			foreach($output['error'] as $oeSet)
			{
		  		echo $oeSet;
			}
		}
		else
		{
			if (isset($_POST["ansicht"]) &&  $_POST["ansicht"] == "detailansicht")
			{
				echo	"<table border=\"1\">"
					 		."<tr>"
			 					."<td>Bestellnummer</td>"
			 					."<td>Details</td>"
			 				."</tr>";
		 	}
		 	else
		 	{
			 	echo 	"<form name=\"importauswahl\" action=\"shoptoerp.php\" method=\"post\">";
			 	echo	"<table border=\"1\">"
					 		."<tr>"
					 			."<td>Importieren</td>"
			 					."<td>Bestellnummer</td>"
			 					."<td>Marktplatz (Zielland)</td>"
			 					."<td>Versanddatum (Bestelldatum)</td>"
			 					."<td>Name</td>"
			 					."<td>Status (x of y done)</td>"
			 					."<td>Gesamtbetrag</td>"
			 					."<td>Artikel</td>"
			 				."</tr>";
		 	}
			foreach($output as $lfdNr => $opSet1)
			{
				$bearbeitungsstatus = $opSet1['bearbeitungsstatus'];
				$show_it = true;
				if (!isset($_POST["erledigtesanzeigen"]) && $bearbeitungsstatus == "email")
				{
					$show_it = false;
				}
				if ($show_it)
				{
					if (isset($_POST["ansicht"]) &&  $_POST["ansicht"] == "detailansicht")
					{
						echo 	"<tr valign=\"top\">"
									."<td>".$opSet1['AmazonOrderId']."</td>"
									."<td>"
										.$opSet1['PurchaseDate']." - Last Update ".$opSet1['LastUpdateDate']."<br>"
										.$opSet1['SalesChannel']." - ".$opSet1['MarketplaceId']."<br>"
										.$opSet1['OrderType']." - ".$opSet1['OrderStatus']." - ".$opSet1['FulfillmentChannel']." - ".$opSet1['AmazonOrderId']." - ".$opSet1['SellerOrderId']."<br>"
										.$opSet1['ShipmentServiceLevelCategory']." - ".$opSet1['ShipServiceLevel']."<br>"
										.$opSet1['Amount']." ".$opSet1['CurrencyCode']." - ".$opSet1['PaymentMethod']."<br>"
										.$opSet1['NumberOfItemsShipped']." (Unshipped ".$opSet1['NumberOfItemsUnshipped'].")<br>"
										.$opSet1['BuyerName']."<br>"
										.$opSet1['Name']."<br>"
										.$opSet1['AddressLine1']."<br>"
										.$opSet1['AddressLine2']."<br>"
										.$opSet1['CountryCode']."-".$opSet1['PostalCode']." ".$opSet1['City']."<br>"
										.$opSet1['StateOrRegion']."<br>" 
										.$opSet1['BuyerEmail']."<br>"
										.$opSet1['Phone']."<br>"
									."</td>"
								."</tr>";
					
					}
					else
					{
					
						echo 	"<tr valign=\"top\">";
									if ($bearbeitungsstatus == "auftrag")
									{
										echo "<td>Auftrag vorhanden</td>";
									}
									elseif ($bearbeitungsstatus == "lieferschein")
									{
										echo "<td>Lieferschein vorhanden</td>";
									}
									elseif ($bearbeitungsstatus == "rechnung")
									{
										echo "<td>Rechnung vorhanden</td>";
									}
									elseif ($bearbeitungsstatus == "email")
									{
										echo "<td>Email verschickt</td>";
									}
									elseif ($bearbeitungsstatus == "neu")
									{
										if (array_key_exists('error', $opSet1) && $opSet1['error'])
										{
											echo "<td bgcolor=\"red\">Bestellte Produkte Abfragefehler!</td>";
										}
										else
										{
											if ($opSet1['OrderStatus'] == "Shipped" ||
												($opSet1['OrderStatus'] == "Unshipped" && $opSet1['FulfillmentChannel'] == "MFN") ||
												($opSet1['OrderStatus'] == "Pending payment" && $opSet1['FulfillmentChannel'] == "MFN") ||
												($opSet1['OrderStatus'] == "Paid" && $opSet1['FulfillmentChannel'] == "MFN") ||
												($opSet1['OrderStatus'] == "Completed" && $opSet1['MarketplaceId'] == $eBayAbteilungsname))
											{
												echo "<td>";
												echo "<input type=\"checkbox\" name=\"importauswahl[]\" value=\"".$opSet1['AmazonOrderId']."\" "."checked=\"checked\"".">";
												
												echo "<input type=\"hidden\" name=\"AmazonOrderId"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['AmazonOrderId']."\">";
												echo "<input type=\"hidden\" name=\"SellerOrderId"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['SellerOrderId']."\">";
												echo "<input type=\"hidden\" name=\"PurchaseDate"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['PurchaseDate']."\">";
												echo "<input type=\"hidden\" name=\"LastUpdateDate"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['LastUpdateDate']."\">";
												echo "<input type=\"hidden\" name=\"SalesChannel"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['SalesChannel']."\">";
												echo "<input type=\"hidden\" name=\"MarketplaceId"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['MarketplaceId']."\">";
												echo "<input type=\"hidden\" name=\"OrderType"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['OrderType']."\">";
												echo "<input type=\"hidden\" name=\"OrderStatus"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['OrderStatus']."\">";
												echo "<input type=\"hidden\" name=\"FulfillmentChannel"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['FulfillmentChannel']."\">";
												echo "<input type=\"hidden\" name=\"ShipmentServiceLevelCategory"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['ShipmentServiceLevelCategory']."\">";
												echo "<input type=\"hidden\" name=\"ShipServiceLevel"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['ShipServiceLevel']."\">";
												echo "<input type=\"hidden\" name=\"Amount"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['Amount']."\">";
												echo "<input type=\"hidden\" name=\"CurrencyCode"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['CurrencyCode']."\">";
												echo "<input type=\"hidden\" name=\"PaymentMethod"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['PaymentMethod']."\">";
												echo "<input type=\"hidden\" name=\"NumberOfItemsShipped"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['NumberOfItemsShipped']."\">";
												echo "<input type=\"hidden\" name=\"NumberOfItemsUnshipped"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['NumberOfItemsUnshipped']."\">";
												echo "<input type=\"hidden\" name=\"BuyerName"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['BuyerName']."\">";
												echo "<input type=\"hidden\" name=\"Title"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['Title']."\">";
												echo "<input type=\"hidden\" name=\"Name"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['Name']."\">";
												echo "<input type=\"hidden\" name=\"AddressLine1"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['AddressLine1']."\">";
												echo "<input type=\"hidden\" name=\"AddressLine2"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['AddressLine2']."\">";
												echo "<input type=\"hidden\" name=\"PostalCode"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['PostalCode']."\">";
												echo "<input type=\"hidden\" name=\"City"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['City']."\">";
												echo "<input type=\"hidden\" name=\"CountryCode"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['CountryCode']."\">";
												echo "<input type=\"hidden\" name=\"StateOrRegion"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['StateOrRegion']."\">";
												echo "<input type=\"hidden\" name=\"recipient-title"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['recipient-title']."\">";
												echo "<input type=\"hidden\" name=\"recipient-name"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['recipient-name']."\">";
												echo "<input type=\"hidden\" name=\"ship-address-1"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['ship-address-1']."\">";
												echo "<input type=\"hidden\" name=\"ship-address-2"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['ship-address-2']."\">";
												echo "<input type=\"hidden\" name=\"ship-address-3"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['ship-address-3']."\">";
												echo "<input type=\"hidden\" name=\"ship-postal-code"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['ship-postal-code']."\">";
												echo "<input type=\"hidden\" name=\"ship-city"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['ship-city']."\">";
												echo "<input type=\"hidden\" name=\"ship-state"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['ship-state']."\">";
												echo "<input type=\"hidden\" name=\"ship-country"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['ship-country']."\">";
												echo "<input type=\"hidden\" name=\"BuyerEmail"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['BuyerEmail']."\">";
												echo "<input type=\"hidden\" name=\"Phone"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['Phone']."\">";
												echo "<input type=\"hidden\" name=\"OrderComment"."|".$opSet1['AmazonOrderId']."\" value=\"".$opSet1['OrderComment']."\">";
												echo "</td>";
											}
											else 
											{
												echo "<td>nicht versendet</td>";
											}
										}
									}
									else
									{
										echo "<td>$bearbeitungsstatus</td>";
									}
									$date1 = new DateTime($opSet1['LastUpdateDate']);
									$date2 = new DateTime($opSet1['PurchaseDate']);
									echo "<td>".$opSet1['AmazonOrderId']."</td>"
										."<td>".$opSet1['SalesChannel']." (".$opSet1['CountryCode'].")</td>"
										."<td>".$date1->format('Y-m-d H:i')." (".$date2->format('Y-m-d H:i').")</td>";
									$customerstatus = checkCustomer($opSet1['BuyerEmail'], $opSet1['BuyerName']);
									if ($customerstatus == "neu")
									{
										echo "<td>".$opSet1['BuyerName']." (Neukunde)</td>";
									}
									elseif ($customerstatus == "-")
									{
										echo "<td>".$opSet1['BuyerName']."-</td>";
									}
									elseif ($customerstatus == "vorhanden")
									{
										echo "<td>".$opSet1['BuyerName']." (Altkunde)</td>";
									}
									else
									{
										echo "<td>$customerstatus</td>";
									}
						echo		"<td>".$opSet1['OrderStatus']." (".$opSet1['NumberOfItemsShipped']." of ".strval(intval($opSet1['NumberOfItemsShipped'])+intval($opSet1['NumberOfItemsUnshipped'])).")</td>";
						echo		"<td>".$opSet1['Amount']." ".$opSet1['CurrencyCode']."</td>";
									
						$bearbeitungsstatus = checkAmazonOrderId($opSet1['AmazonOrderId']);
						if ($bearbeitungsstatus == "neu")
						{
							if (array_key_exists('error', $opSet1) && $opSet1['error'])
							{
								foreach($opSet1['error'] as $oeSet)
								{
									echo "<td>".$oeSet."</td>";
								}
							}
							else
							{
								$searchSKU = array();
								$replaceSKU = array();
								
								foreach (split("\n", $ersatzSKU) as $einzelSKU)
								{
									$zerlegteEinzelSKU = split("\|", $einzelSKU);
									if(count($zerlegteEinzelSKU) == 2)
									{
										$searchSKU[] = $zerlegteEinzelSKU[0];
										$replaceSKU[] = $zerlegteEinzelSKU[1];
									}
								}
								
								echo "<td>";
								foreach($opSet1['orderItemsListOutput'] as $lfdNrOrderItem => $orderItem)
								{
									$promotiondiscount_text = "";
									if (isset($orderItem['PromotionDiscount']) && $orderItem['PromotionDiscount'] > 0.0)
									{
										$promotiondiscount_text = " PromotionDiscount ".$orderItem['PromotionDiscount'];
									}
									$shipping_text = "";
									if (isset($orderItem['ShippingPrice']) && $orderItem['ShippingPrice'] > 0.0)
									{
										$shipping_text = " Shipping ".$orderItem['ShippingPrice'];
									}
									$shippingdiscount_text = "";
									if (isset($orderItem['ShippingDiscount']) && $orderItem['ShippingDiscount'] > 0.0)
									{
										$shippingdiscount_text = " ShippingDiscount ".$orderItem['ShippingDiscount'];
									}
									$giftwrap_text = "";
									if (isset($orderItem['GiftWrapPrice']) && $orderItem['GiftWrapPrice'] > 0.0)
									{
										$giftwrap_text = " GiftWrap ".$orderItem['GiftWrapPrice'];
									}
									echo $orderItem['SellerSKU']." - Shipped ".$orderItem['QuantityShipped']." of ".$orderItem['QuantityOrdered']." Price ".$orderItem['ItemPrice'].$promotiondiscount_text.$shipping_text.$shippingdiscount_text.$giftwrap_text."<br>";
									
									echo "<input type=\"hidden\" name=\"AmazonOrderIdProducts"."|".$opSet1['AmazonOrderId']."|".$lfdNrOrderItem."\" value=\""
											.$orderItem['OrderItemId']."|"
											.str_replace($searchSKU, $replaceSKU, $orderItem['SellerSKU'])."|"
											.$orderItem['ASIN']."|"
											.$orderItem['ItemPrice']."|"
											.$orderItem['ItemTax']."|"
											.$orderItem['PromotionDiscount']."|"
											.$orderItem['ShippingPrice']."|"
											.$orderItem['ShippingTax']."|"
											.$orderItem['ShippingDiscount']."|"
											.$orderItem['GiftWrapPrice']."|"
											.$orderItem['GiftWrapTax']."|"
											.$orderItem['QuantityOrdered']."|"
											.$orderItem['QuantityShipped']."|"
											.$orderItem['Title']
											."\">";
								}
								echo "</td>";
							}
						}
						else
						{
							echo "<td>Keine Abfrage, Daten bereits importiert!</td>";
						}
					}
					echo 	"</tr>";
		
					if (isset($_POST["ansicht"]) &&  $_POST["ansicht"] == "detailansicht")
					{				
						if (array_key_exists('error', $opSet1) && $opSet1['error'])
						{
							foreach($opSet1['error'] as $oeSet)
							{
								echo 	"<tr valign=\"top\">"
										."<td></td>"
										."<td>".$oeSet."</td>"
										."</tr>";
							}
						}
						else
						{
							foreach($opSet1['orderItemsListOutput'] as $lfdNrOrderItem => $orderItem)
							{
								echo 	"<tr valign=\"top\">"
										."<td>  ".$opSet1['AmazonOrderId']." -> ".$lfdNrOrderItem."</td>"
										."<td>".$orderItem['SellerSKU']." / ".$orderItem['ASIN']." - Shipped ".$orderItem['QuantityShipped']." of ".$orderItem['QuantityOrdered']." Price ".$orderItem['ItemPrice']." PromotionDiscount ".$orderItem['PromotionDiscount']." Shipping ".$orderItem['ShippingPrice']." GiftWrap ".$orderItem['GiftWrapPrice']."<br>".$orderItem['Title']."</td>"
										."</tr>";
							}
						}
					}
				}
			}
			if (isset($_POST["ansicht"]) &&  $_POST["ansicht"] == "detailansicht")
			{
				echo "</table>";
			}
			else
			{
				echo "</table><br>";
				echo "<input type=\"submit\" name=\"import\" value=\"Ausgewaehltes importieren\">";
				echo "</form>";
			}
		}
	}
	else if (isset($_POST["import"]))
	{
		// Zum Import ausgewaehlte Datensaetze zusammenstellen	
		if (isset($_POST["importauswahl"])) {
			$importauswahl = $_POST['importauswahl'];
		}
		
		$bestellungen = array();
		
		foreach ($importauswahl as $lfdNr => $importItem)
		{
			// Bestellungsdaten
			if (isset($_POST["AmazonOrderId|".$importItem])) { $bestellungen[$importItem]['AmazonOrderId'] = $_POST["AmazonOrderId|".$importItem]; }
			if (isset($_POST["SellerOrderId|".$importItem])) { $bestellungen[$importItem]['SellerOrderId'] = $_POST["SellerOrderId|".$importItem]; }
			if (isset($_POST["PurchaseDate|".$importItem])) { $bestellungen[$importItem]['PurchaseDate'] = $_POST["PurchaseDate|".$importItem]; }
			if (isset($_POST["LastUpdateDate|".$importItem])) { $bestellungen[$importItem]['LastUpdateDate'] = $_POST["LastUpdateDate|".$importItem]; }
			if (isset($_POST["SalesChannel|".$importItem])) { $bestellungen[$importItem]['SalesChannel'] = $_POST["SalesChannel|".$importItem]; }
			if (isset($_POST["MarketplaceId|".$importItem])) { $bestellungen[$importItem]['MarketplaceId'] = $_POST["MarketplaceId|".$importItem]; }
			if (isset($_POST["OrderType|".$importItem])) { $bestellungen[$importItem]['OrderType'] = $_POST["OrderType|".$importItem]; }
			if (isset($_POST["OrderStatus|".$importItem])) { $bestellungen[$importItem]['OrderStatus'] = $_POST["OrderStatus|".$importItem]; }
			if (isset($_POST["FulfillmentChannel|".$importItem])) { $bestellungen[$importItem]['FulfillmentChannel'] = $_POST["FulfillmentChannel|".$importItem]; }
			if (isset($_POST["ShipmentServiceLevelCategory|".$importItem])) { $bestellungen[$importItem]['ShipmentServiceLevelCategory'] = $_POST["ShipmentServiceLevelCategory|".$importItem]; }
			if (isset($_POST["ShipServiceLevel|".$importItem])) { $bestellungen[$importItem]['ShipServiceLevel'] = $_POST["ShipServiceLevel|".$importItem]; }
			if (isset($_POST["Amount|".$importItem])) { $bestellungen[$importItem]['Amount'] = $_POST["Amount|".$importItem]; }
			if (isset($_POST["CurrencyCode|".$importItem])) { $bestellungen[$importItem]['CurrencyCode'] = $_POST["CurrencyCode|".$importItem]; }
			if (isset($_POST["PaymentMethod|".$importItem])) { $bestellungen[$importItem]['PaymentMethod'] = $_POST["PaymentMethod|".$importItem]; }
			if (isset($_POST["NumberOfItemsShipped|".$importItem])) { $bestellungen[$importItem]['NumberOfItemsShipped'] = $_POST["NumberOfItemsShipped|".$importItem]; }
			if (isset($_POST["NumberOfItemsUnshipped|".$importItem])) { $bestellungen[$importItem]['NumberOfItemsUnshipped'] = $_POST["NumberOfItemsUnshipped|".$importItem]; }
			if (isset($_POST["BuyerName|".$importItem])) { $bestellungen[$importItem]['BuyerName'] = $_POST["BuyerName|".$importItem]; }
			if (isset($_POST["Title|".$importItem])) { $bestellungen[$importItem]['Title'] = $_POST["Title|".$importItem]; }
			if (isset($_POST["Name|".$importItem])) { $bestellungen[$importItem]['Name'] = $_POST["Name|".$importItem]; }
			if (isset($_POST["AddressLine1|".$importItem])) { $bestellungen[$importItem]['AddressLine1'] = $_POST["AddressLine1|".$importItem]; }
			if (isset($_POST["AddressLine2|".$importItem])) { $bestellungen[$importItem]['AddressLine2'] = $_POST["AddressLine2|".$importItem]; }
			if (isset($_POST["PostalCode|".$importItem])) { $bestellungen[$importItem]['PostalCode'] = $_POST["PostalCode|".$importItem]; }
			if (isset($_POST["City|".$importItem])) { $bestellungen[$importItem]['City'] = $_POST["City|".$importItem]; }
			if (isset($_POST["CountryCode|".$importItem])) { $bestellungen[$importItem]['CountryCode'] = $_POST["CountryCode|".$importItem]; }
			if (isset($_POST["StateOrRegion|".$importItem])) { $bestellungen[$importItem]['StateOrRegion'] = $_POST["StateOrRegion|".$importItem]; }
			if (isset($_POST["recipient-title|".$importItem])) { $bestellungen[$importItem]['recipient-title'] = $_POST["recipient-title|".$importItem]; }
			if (isset($_POST["recipient-name|".$importItem])) { $bestellungen[$importItem]['recipient-name'] = $_POST["recipient-name|".$importItem]; }
			if (isset($_POST["ship-address-1|".$importItem])) { $bestellungen[$importItem]['ship-address-1'] = $_POST["ship-address-1|".$importItem]; }
			if (isset($_POST["ship-address-2|".$importItem])) { $bestellungen[$importItem]['ship-address-2'] = $_POST["ship-address-2|".$importItem]; }
			if (isset($_POST["ship-address-3|".$importItem])) { $bestellungen[$importItem]['ship-address-3'] = $_POST["ship-address-3|".$importItem]; }
			if (isset($_POST["ship-postal-code|".$importItem])) { $bestellungen[$importItem]['ship-postal-code'] = $_POST["ship-postal-code|".$importItem]; }
			if (isset($_POST["ship-city|".$importItem])) { $bestellungen[$importItem]['ship-city'] = $_POST["ship-city|".$importItem]; }
			if (isset($_POST["ship-state|".$importItem])) { $bestellungen[$importItem]['ship-state'] = $_POST["ship-state|".$importItem]; }
			if (isset($_POST["ship-country|".$importItem])) { $bestellungen[$importItem]['ship-country'] = $_POST["ship-country|".$importItem]; }
			if (isset($_POST["BuyerEmail|".$importItem])) { $bestellungen[$importItem]['BuyerEmail'] = $_POST["BuyerEmail|".$importItem]; }			
			if (isset($_POST["Phone|".$importItem])) { $bestellungen[$importItem]['Phone'] = $_POST["Phone|".$importItem]; }
			if (isset($_POST["OrderComment|".$importItem])) { $bestellungen[$importItem]['OrderComment'] = $_POST["OrderComment|".$importItem]; }
	
			//Artikel pro Bestellung
			for ($zaehler = 0; $zaehler <= intval($bestellungen[$importItem]['NumberOfItemsShipped']) + intval($bestellungen[$importItem]['NumberOfItemsUnshipped']); $zaehler++)
			{
				if (isset($_POST["AmazonOrderIdProducts|".$importItem."|".$zaehler]))
				{
					$produktdaten = explode("|", $_POST["AmazonOrderIdProducts|".$importItem."|".$zaehler]);
					
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['OrderItemId'] = $produktdaten[0];
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['SellerSKU'] = $produktdaten[1];
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['ASIN'] = $produktdaten[2];
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['ItemPrice'] = $produktdaten[3];
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['ItemTax'] = $produktdaten[4];
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['PromotionDiscount'] = $produktdaten[5];
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['ShippingPrice'] = $produktdaten[6];
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['ShippingTax'] = $produktdaten[7];
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['ShippingDiscount'] = $produktdaten[8];
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['GiftWrapPrice'] = $produktdaten[9];
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['GiftWrapTax'] = $produktdaten[10];
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['QuantityOrdered'] = $produktdaten[11];
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['QuantityShipped'] = $produktdaten[12];
					$bestellungen[$importItem]['AmazonOrderIdProducts'][$zaehler]['Title'] = $produktdaten[13];
				}
			}
		}
		echo "<br> Starte Import!<br><br>";
		
		$bestellungszahl = count($bestellungen);
	
		if ($bestellungszahl)
		{
			echo "Es liegen $bestellungszahl Bestellungen zum Import vor.<br>";
	
			// Importfunktion aufrufen
			foreach (array_values($bestellungen) as $bestellung)
			{
				$kundennummern = check_update_Kundendaten($bestellung);
				$nummernarray = explode("|", $kundennummern);
				if ($nummernarray[0] > 0)
				{
					erstelle_Auftrag($bestellung, $nummernarray[0], $nummernarray[1], $ERPusrID);
				}
			}
		}
		else
		{
			echo "Keine Bestellungen ausgewaehlt/ es liegen keine Bestellungen vor!<br>";
		}
	}
	
	echo "</form>";
	echo "</body>";
	echo "</html>";
}
?>