<?php

$LAND = array(	"DE" => "Deutschland",

				"AT" => "Österreich",
				"BE" => "Belgien",
				"BG" => "Bulgarien",
				"CY" => "Zypern",
				"CZ" => "Tschechische Republik",
				"DK" => "Dänemark",
				"EE" => "Estland",
				"EL" => "Griechenland",
				"ES" => "Spanien",
				"FI" => "Finnland",
				"FR" => "Frankreich",
				"HU" => "Ungarn",
				"IE" => "Irland",
				"IT" => "Italien",
				"LT" => "Litauen",
				"LU" => "Luxemburg",
				"LV" => "Lettland",
				"MT" => "Malta",
				"NL" => "Niederlande",
				"PL" => "Polen",
				"PT" => "Portugal",
				"RO" => "Rumänien",
				"SE" => "Schweden",
				"SI" => "Slowenien",
				"SK" => "Slowakei",
				"UK" => "United Kingdom",
				"GB" => "United Kingdom",

				"CH" => "Schweiz");
				
$TAXID = array(	"DE" => 0,	// Steuerschluessel Deutschland

				"AT" => 2,	// Steuerschluessel EU
				"BE" => 2,
				"BG" => 2,
				"CY" => 2,
				"CZ" => 2,
				"DK" => 2,
				"EE" => 2,
				"EL" => 2,
				"ES" => 2,
				"FI" => 2,
				"FR" => 2,
				"HU" => 2,
				"IE" => 2,
				"IT" => 2,
				"LT" => 2,
				"LU" => 2,
				"LV" => 2,
				"MT" => 2,
				"NL" => 2,
				"PL" => 2,
				"PT" => 2,
				"RO" => 2,
				"SE" => 2,
				"SI" => 2,
				"SK" => 2,
				"UK" => 2,
				"GB" => 2,
				
				"CH" => 3);	// Steuerschluessel Welt (also keine USt.)

$VERSAND = array(	"AFN" => "Amazon",
					"MFN" => "Händler");
					
$paramsOrders = array(	"MarketplaceId", "SalesChannel",
						"OrderType", "OrderStatus", "SellerOrderId", "AmazonOrderId", "FulfillmentChannel",
						"ShipmentServiceLevelCategory", "ShipServiceLevel",
						"Amount", "CurrencyCode", "PaymentMethod",
						"NumberOfItemsShipped", "NumberOfItemsUnshipped",
						"PurchaseDate", "LastUpdateDate",
						"BuyerName",
						"Title", "Name", "AddressLine1", "AddressLine2", "PostalCode", "City", "StateOrRegion", "CountryCode",
						"recipient-title", "recipient-name", "ship-address-1", "ship-address-2", "ship-address-3", "ship-postal-code", "ship-city", "ship-state", "ship-country",
						"BuyerEmail", "Phone", "OrderComment");
										
$paramsOrderItems = array(	"OrderItemId", "SellerSKU", "ASIN", "Title",
							"ItemPrice", "ItemTax", "PromotionDiscount", "ShippingPrice", "ShippingTax", "ShippingDiscount", "GiftWrapPrice", "GiftWrapTax",
							"QuantityOrdered", "QuantityShipped");
										
?>