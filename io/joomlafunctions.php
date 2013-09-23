<?php

function getJoomlaOrders($fulfillmentchannel, $bestellungvom, $bestellungbis)
{
	$returnvalue = array();
	
	if($fulfillmentchannel == "amazon")
	{
		return $returnvalue;
	}
	
	require "conf.php";
	require "constants.php";
	
	// Bestellungen von
	$date_from = explode("-", $bestellungvom);
	$dateAfter = date("Y-m-d\TH:i:s\Z", mktime(0, 0, 0, $date_from[1], $date_from[0], $date_from[2]));
	
	// Bestellungen bis
	if ($bestellungbis != "")
	{
		$zeit = "0:0:0";
		if(gmdate("d-m-Y", time()) == $bestellungbis)
		{
			$zeit = gmdate("H:i:s", time()+7200);
		}
		else
		{
			$zeit = "23:59:59";
		}
		$date_bis = explode("-", $bestellungbis);
		$zeit_bis = explode(":", $zeit);
		$dateBefore = date("Y-m-d\TH:i:s\Z", mktime($zeit_bis[0], $zeit_bis[1], $zeit_bis[2], $date_bis[1], $date_bis[0], $date_bis[2]));
	}
	else
	{
		$dateBefore = gmdate("Y-m-d\TH:i:s\Z", time()+7200);
	}
	
	$connection = mysql_connect(($Joomlahost.":".$Joomlaport), $Joomlauser, $Joomlapass);
	mysql_select_db($Joomladbname, $connection);
	
	$result = mysql_query("SELECT order_id,".
								 "order_number,".
								 "order_total,".
								 "order_subtotal,".
								 "order_tax,".
								 "order_shipping,".
								 "order_discount,".
								 "currency_code_iso,".
								 "order_status,".
								 "order_date,".
								 "order_m_date,".
								 "shipping_method_id,".
								 "payment_method_id,".
								 "ip_address,".
								 "order_add_info,".
								 "title,".
								 "f_name,".
								 "l_name,".
								 "email,".
								 "street,".
								 "zip,".
								 "city,".
								 "state,".
								 "country,".
								 "d_title,".
								 "d_f_name,".
								 "d_l_name,".
								 "d_firma_name,".
								 "d_email,".
								 "d_street,".
								 "d_zip,".
								 "d_city,".
								 "d_state,".
								 "d_country,".
								 "pdf_file,".
								 "lang,".
								 "shipping_tax,".
								 "payment_tax".
						" FROM joomla_jshopping_orders".
						" WHERE order_date >= '".$dateAfter."' AND order_date <= '".$dateBefore."' AND order_status <> 3 AND order_created = 1".
						" ORDER BY order_date ASC");
	
	$bestellungszaehler = 0;
	
	// Ab hier das Datenarray mit den ausgewaehlten Bestellungen zusammenstellen
	while ($row = mysql_fetch_array($result))
	{
	    /* Readable version of Status */
	    $result_order_status = mysql_query(	"SELECT `status_id`, `name_en-GB`".
	    									" FROM joomla_jshopping_order_status".
	    									" WHERE status_id='".$row['order_status']."'");
	    $row_order_status = mysql_fetch_array($result_order_status);
	
	    /* Readable version of Shipping Method */
	    $result_shipping_method = mysql_query(	"SELECT `name_en-GB`".
	    										" FROM joomla_jshopping_shipping_method".
	    										" WHERE shipping_id='" . $row['shipping_method_id'] . "'");
	    $row_shipping_method = mysql_fetch_array($result_shipping_method);
	
	    /* Readable version of Payment Method */
	    $result_payment_method = mysql_query(	"SELECT `name_de-DE`".
	    										" FROM joomla_jshopping_payment_method".
	    										" WHERE payment_id='" . $row['payment_method_id'] . "'");
	    $row_payment_method = mysql_fetch_array($result_payment_method);
	
	    /* Readable version of titles */
		switch ($row['title']) 
		{
	    	case 1:
				$title = 'Herr';
			break;
	    	case 2:
	    		$title = 'Frau';
			break;
	      	default:
				$title = '';
			break;
		}
	    switch ($row['d_title']) 
		{
			case 1:
				$delivery_title = 'Herr';
			break;
			case 2:
				$delivery_title = 'Frau';
			break;
			default:
				$delivery_title = '';
			break;
		}
		
		/* Readable version of countries */
		$result_country_code = mysql_query(	"SELECT `country_code_2`, `name_de-DE`".
											" FROM joomla_jshopping_countries".
											" WHERE country_id='" . $row['country'] . "'");
	    $row_country_code = mysql_fetch_array($result_country_code);
	    
		$result_country_code_delivery = mysql_query("SELECT `country_code_2`, `name_de-DE`".
													" FROM joomla_jshopping_countries".
													" WHERE country_id='" . $row['d_country'] . "'");
	    $row_country_code_delivery = mysql_fetch_array($result_country_code_delivery);
	
	    /*items in order*/
	    $result_products = mysql_query(	"SELECT	product_ean,".
	    										"product_name,".
	    										"product_quantity,".
	    										"product_item_price,".
	    										"product_tax,".
	    										"product_attributes,".
	    										"weight".
	    								" FROM joomla_jshopping_order_item".
	    								" WHERE order_id= '" . $row['order_id'] . "'");
	    $item_count=mysql_num_rows ($result_products);
	    
		$returnvalue[$bestellungszaehler]['AmazonOrderId'] = $JoomlaBestellnummernprefix.$row['order_number'];
		$returnvalue[$bestellungszaehler]['SellerOrderId'] = $JoomlaBestellnummernprefix.$row['order_number'];
		$returnvalue[$bestellungszaehler]['PurchaseDate'] = $row['order_date'];
		$returnvalue[$bestellungszaehler]['LastUpdateDate'] = $row['order_m_date'];
		$returnvalue[$bestellungszaehler]['SalesChannel'] = $JoomlaAbteilungsname;
		$returnvalue[$bestellungszaehler]['MarketplaceId'] = $JoomlaAbteilungsname;
		// $returnvalue[$bestellungszaehler]['OrderType'] = "";
		$returnvalue[$bestellungszaehler]['OrderStatus'] = $row_order_status['name_en-GB'];
		$returnvalue[$bestellungszaehler]['FulfillmentChannel'] = "MFN";
		$returnvalue[$bestellungszaehler]['ShipmentServiceLevelCategory'] = $row_shipping_method['name_en-GB'];
		// $returnvalue[$bestellungszaehler]['ShipServiceLevel'] = "";
		$returnvalue[$bestellungszaehler]['Amount'] = $row['order_total'];
		$returnvalue[$bestellungszaehler]['CurrencyCode'] = $row['currency_code_iso'];
		$returnvalue[$bestellungszaehler]['PaymentMethod'] = $row_payment_method['name_de-DE'];
		$returnvalue[$bestellungszaehler]['NumberOfItemsShipped'] = 0;
		$returnvalue[$bestellungszaehler]['NumberOfItemsUnshipped'] = $item_count;
		$returnvalue[$bestellungszaehler]['BuyerName'] = utf8_encode($row['f_name'])." ".utf8_encode($row['l_name']);
		$returnvalue[$bestellungszaehler]['Title'] = utf8_encode($title);
		$returnvalue[$bestellungszaehler]['Name'] = utf8_encode($row['f_name'])." ".utf8_encode($row['l_name']);
		$returnvalue[$bestellungszaehler]['AddressLine1'] = utf8_encode($row['street']);
		// $returnvalue[$bestellungszaehler]['AddressLine2'] = "";
		$returnvalue[$bestellungszaehler]['PostalCode'] = utf8_encode($row['zip']);
		$returnvalue[$bestellungszaehler]['City'] = utf8_encode($row['city']);
		$returnvalue[$bestellungszaehler]['CountryCode'] = utf8_encode($row_country_code['country_code_2']);
		$returnvalue[$bestellungszaehler]['StateOrRegion'] = utf8_encode($row['state']);
		$returnvalue[$bestellungszaehler]['recipient-title'] = utf8_encode($delivery_title);
		$returnvalue[$bestellungszaehler]['recipient-name'] = utf8_encode($row['d_f_name'])." ".utf8_encode($row['d_l_name']);
		$returnvalue[$bestellungszaehler]['ship-address-1'] = utf8_encode($row['d_street']);
		// $returnvalue[$bestellungszaehler]['ship-address-2'] = "";
		$returnvalue[$bestellungszaehler]['ship-postal-code'] = utf8_encode($row['d_zip']);
		$returnvalue[$bestellungszaehler]['ship-city'] = utf8_encode($row['d_city']);
		$returnvalue[$bestellungszaehler]['ship-country'] = utf8_encode($row_country_code_delivery['country_code_2']);
		$returnvalue[$bestellungszaehler]['ship-state'] = utf8_encode($row['d_state']);
		$returnvalue[$bestellungszaehler]['BuyerEmail'] = utf8_encode($row['email']);
		// $returnvalue[$bestellungszaehler]['Phone'] = "";
		$returnvalue[$bestellungszaehler]['OrderComment'] = utf8_encode($row['order_add_info']);
		/* unused fieldnames
	    --------------------
	    $row['order_tax']
	    $row['payment_tax']
	    $row['d_email']
	    $row['pdf_file']
	    $row['lang']
	    $row['ip_address'] */

		$bearbeitungsstatus = checkAmazonOrderId($returnvalue[$bestellungszaehler]['AmazonOrderId']);
		$returnvalue[$bestellungszaehler]['bearbeitungsstatus'] = $bearbeitungsstatus;

	    $itemcounter = 0;
	    $orderItemsListOutput = array();

		while ($row_products = mysql_fetch_array($result_products))
		{
			$orderItemsListOutput[$itemcounter]['OrderItemId'] = $itemcounter;
			$orderItemsListOutput[$itemcounter]['SellerSKU'] = trim($row_products['product_ean']);
			// $orderItemsListOutput[$itemcounter]['ASIN'] = "";
			$orderItemsListOutput[$itemcounter]['ItemPrice'] = $row_products['product_item_price'];
			// $orderItemsListOutput[$itemcounter]['ItemTax'] = "";
			if ($itemcounter == 0)
			{
				$orderItemsListOutput[$itemcounter]['PromotionDiscount'] = $row['order_discount']; // Rabatte werden beim Artikel eingetragen
				$orderItemsListOutput[$itemcounter]['ShippingPrice'] = $row['order_shipping']; // Versandkosten werden beim Artikel eingetragen
				$orderItemsListOutput[$itemcounter]['ShippingTax'] = "";
				$orderItemsListOutput[$itemcounter]['ShippingDiscount'] = "";
			}
			// $orderItemsListOutput[$itemcounter]['GiftWrapPrice'] = "";
			// $orderItemsListOutput[$itemcounter]['GiftWrapTax'] = "";
			$orderItemsListOutput[$itemcounter]['QuantityOrdered'] = $row_products['product_quantity'];
			$orderItemsListOutput[$itemcounter]['QuantityShipped'] = 0;
			$orderItemsListOutput[$itemcounter]['Title'] = $row_products['product_name'];
			
			/* unused Fields
			$row_products['product_tax']
			$row_products['weight']
			*/
			$itemcounter++;
		}
		$returnvalue[$bestellungszaehler]['orderItemsListOutput'] = $orderItemsListOutput;
		
		$bestellungszaehler++;
	}
	mysql_close($connection);
	
	return $returnvalue;
}
?>