package SL::Layout::Finance5;

use strict;
use parent qw(SL::Layout::Base);

use URI;

sub clock_line {
  my ($Sekunden, $Minuten,   $Stunden,   $Monatstag, $Monat,
      $Jahr,     $Wochentag, $Jahrestag, $Sommerzeit)
    = localtime(time);
  $Monat     += 1;
  $Jahrestag += 1;
  $Monat     = $Monat < 10     ? $Monat     = "0" . $Monat     : $Monat;
  $Monatstag = $Monatstag < 10 ? $Monatstag = "0" . $Monatstag : $Monatstag;
  $Jahr += 1900;
  my @Wochentage = ("Sonntag",    "Montag",  "Dienstag", "Mittwoch",
                    "Donnerstag", "Freitag", "Samstag");
  my @Monatsnamen = ("",       "Januar",    "Februar", "M&auml;rz",
                     "April",  "Mai",       "Juni",    "Juli",
                     "August", "September", "Oktober", "November",
                     "Dezember");
  return
      $Wochentage[$Wochentag] . ", den "
    . $Monatstag . "."
    . $Monat . "."
    . $Jahr . " - ";
}

sub print_menu {
  my ($self, $parent, $depth) = @_;

  my $html;

  die if ($depth * 1 > 5);

  my @menuorder;
  my $menu = $self->menu;

  @menuorder = $menu->access_control(\%::myconfig, $parent);

  $parent .= "--" if ($parent);

  foreach my $item (@menuorder) {
    substr($item, 0, length($parent)) = "";
    next if (($item eq "") || ($item =~ /--/));

    my $menu_item = $menu->{"${parent}${item}"};
    my $menu_title = $::locale->text($item);
    my $menu_text = $menu_title;

    if ($menu_item->{"submenu"} || !defined($menu_item->{"module"}) && !defined($menu_item->{href})) {

      my $h = $self->print_menu("${parent}${item}", $depth * 1 + 1)."\n";
      if (!$parent) {
        $html .= qq|<ul><li><h2>${menu_text}</h2><ul>${h}</ul></li></ul>\n|;
      } else {
        $html .= qq|<li><div class="x">${menu_text}</div><ul>${h}</ul></li>\n|;
      }
    } else {
      if ($self->{sub_class} && $depth > 1) {
        $html .= qq|<li class='sub'>|;
      } else {
        $html .= qq|<li>|;
      }
      $html .= $self->menuitem_v3("${parent}$item", { "title" => $menu_title });
      $html .= qq|${menu_text}</a></li>\n|;
    }
  }

  return $html;
}

sub menuitem_v3 {
  $main::lxdebug->enter_sub();

  my ($self, $item, $other) = @_;
  my $menuitem = $self->menu->{$item};

  my $action = "section_menu";
  my $module;

  if ($menuitem->{module}) {
    $module = $menuitem->{module};
  }
  if ($menuitem->{action}) {
    $action = $menuitem->{action};
  }

  my $level  = $::form->escape($item);

  my @vars;
  my $target = $menuitem->{target} ? qq| target="| . $::form->escape($menuitem->{target}) . '"' : '';
  my $str    = qq|<a${target} href="|;

  if ($menuitem->{href}) {
    $main::lxdebug->leave_sub();
    return $str . $menuitem->{href} . '">';
  }

  $str .= qq|$module?action=| . $::form->escape($action) . qq|&level=| . $::form->escape($level);

  map { delete $menuitem->{$_} } qw(module action target href);

  # add other params
  foreach my $key (keys %{ $menuitem }) {
    $str .= "&" . $::form->escape($key, 1) . "=";
    my ($value, $conf) = split(/=/, $menuitem->{$key}, 2);
    $value = $::myconfig{$value} . "/$conf" if ($conf);
    $str .= $::form->escape($value, 1);
  }

  $str .= '"';

  if ($other) {
    foreach my $key (keys(%{$other})) {
      $str .= qq| ${key}="| . $::form->quote($other->{$key}) . qq|"|;
    }
  }

  $str .= ">";

  $main::lxdebug->leave_sub();

  return $str;
}

sub init_sub_layouts {
  [ SL::Layout::None->new ]
}

sub use_stylesheet {
  my $self = shift;
  qw(
   icons16.css frame_header/header.css menu-f5.css
  ),
  $self->SUPER::use_stylesheet(@_);
}

sub use_javascript {
  my $self = shift;
  qw(
    js/quicksearch_input.js
  ),
  $self->SUPER::use_javascript(@_);
}

sub pre_content {
  $_[0]->render;
}

sub start_content {
  "<div id='page'>\n" .
  "  <div id='container-navigation'>\n" .
  "        <ul>\n" .
  "        <li><a href='ct.pl?action=Weiter&db=customer&nextsub=list_names&l_city=Y&l_contact=Y&l_customernumber=Y&l_email=Y&l_name=Y&l_phone=Y&l_street=Y&l_zipcode=Y&obsolete=N&status=all'>Kunden</a></li>\n" .
  "        <li><a href='ic.pl?searchitems=part&title=Waren&revers=0&lastsort=&nextsub=generate_report&sort=description&ndxs_counter=0&partnumber=&ean=&description=&partsgroup_id=&serialnumber=&make=&model=&drawing=&microfiche=&itemstatus=active&transdatefrom=&transdateto=&l_partnumber=Y&l_description=Y&l_unit=Y&l_sellprice=Y&l_lastcost=Y&l_linetotal=Y&action=Weiter'>Waren</a></li>\n" .
  "        <li><a href='wh.pl?action=generate_report&l_warehousedescription=Y&l_bindescription=Y&l_partnumber=Y&l_partdescription=Y&l_chargenumber=Y&l_qty=Y&l_stock_value=Y&qty_op=dontcare&qty_unit=Stck&l_warehousedescription=Y&l_bindescription=Y&sort=partnumber&order=0'>Lager</a></li>\n" .
  "        <li><a href='javascript:gotoRechnungen();'>Rechnungen</a></li>\n" .
  "        <li><a href='javascript:gotoBuchungen();'>Buchungen</a></li>\n" .
  "        <li><a href='javascript:gotoBilanzen();'>Bilanzen</a></li>\n" .
  "        <li><a href='fu.pl?nextsub=report&created_for=&subject=&body=&reference=&follow_up_date_from=&follow_up_date_to=&itime_from=&itime_to=&due_only=1&all_users=1&not_done=1&action=Weiter'>Erinnerungen</a></li>\n" .
  "        </ul>\n" .
  "  </div>\n" .
  "  <div id='content'>\n";
}

sub end_content {
  "  </div>\n" .
  "</div>\n" .
  "<div id='footer'>\n" .
  "<div id='footer-left'>\n" .
  "  &copy; 2013-2020 <a href='http://www.think5.de' target='_new'>Think5 GmbH</a><br>\n" .
  "  <a href='http://www.gnu.org/licenses/gpl-2.0.html' target='new'>GNU GPL Open Source</a> | <a href='http://github.com/mark-sch/Finance5' target='new'>Fork me on GitHub</a>\n" .
  "</div>\n".
  "<div id='footer-right'>\n" .
  "<a target='_blank' href='http://www.facebook.com/myFinance5'><img width='73' height='73' style='margin-left:10px;' src='f5-images/facebook.png'></a>\n" .
  "</div>\n" .
  "</div>\n";
}

sub render {
  my ($self) = @_;

  my $callback            = $::form->unescape($::form->{callback});
  $callback               = URI->new($callback)->rel($callback) if $callback;
  $callback               = "login.pl?action=company_logo"      if $callback =~ /^(\.\/)?$/;

  $self->presenter->render('menu/menu-f5',
    force_ul_width => 1,
    date           => $self->clock_line,
    menu           => $self->print_menu,
    callback       => $callback,
  );
}

1;
