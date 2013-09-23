Briefbogen Upload - Schnittstelle zum Import von eignem PDF Firmenbriefpapier
Shop - Schnittstelle Amazon/Ebay/Joomla jShopping -> Finance5

Vorraussetzungen:
	Finance5 >= 2013.3.77 
	Amazon/Ebay/jShopping
	pear install DB

Installation:
Die Datei conf.php benoetigt Schreibrechte fuer den Webserver-Benutzer (apache, www-data, httpd)
Es muss ein Unterverzeichnis tmp angelegt werden, in dem die log-Dateien angelegt werden koennen.
Die conf.php beinhaltet User/Password welche für die Basic Authentication verwendet wird.


Die aufrufbaren Dateien im Folder io sind

templateImport.php   Briefbogen Import
confedit.php	     Konfigurationseinstellungen 
shoptoerp.php	     Der eigentliche Import


