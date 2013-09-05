#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger, Accounting
# Copyright (c) 1998-2003
#
#  Author: Dieter Simader
#   Email: dsimader@sql-ledger.org
#     Web: http://www.sql-ledger.org
#
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#======================================================================
#
# Delivery orders
#======================================================================

use List::Util qw(max sum);
use POSIX qw(strftime);
use YAML;

use SL::DB::DeliveryOrder;
use SL::DO;
use SL::IR;
use SL::IS;
use SL::ReportGenerator;
use SL::WH;
require "bin/mozilla/arap.pl";
require "bin/mozilla/common.pl";
require "bin/mozilla/invoice_io.pl";
require "bin/mozilla/io.pl";
require "bin/mozilla/reportgenerator.pl";

use strict;

1;

# end of main

sub check_do_access {
  $main::auth->assert($main::form->{type} . '_edit');
}

sub set_headings {
  $main::lxdebug->enter_sub();

  check_do_access();

  my ($action) = @_;

  my $form     = $main::form;
  my $locale   = $main::locale;

  if ($form->{type} eq 'purchase_delivery_order') {
    $form->{vc}    = 'vendor';
    $form->{title} = $action eq "edit" ? $locale->text('Edit Purchase Delivery Order') : $locale->text('Add Purchase Delivery Order');
  } else {
    $form->{vc}    = 'customer';
    $form->{title} = $action eq "edit" ? $locale->text('Edit Sales Delivery Order') : $locale->text('Add Sales Delivery Order');
  }

  $form->{heading} = $locale->text('Delivery Order');

  $main::lxdebug->leave_sub();
}

sub add {
  $main::lxdebug->enter_sub();

  check_do_access();

  my $form     = $main::form;

  set_headings("add");

  $form->{callback} = build_std_url('action=add', 'type', 'vc') unless ($form->{callback});

  order_links();
  prepare_order();
  display_form();

  $main::lxdebug->leave_sub();
}

sub edit {
  $main::lxdebug->enter_sub();

  check_do_access();

  my $form     = $main::form;

  # show history button
  $form->{javascript} = qq|<script type="text/javascript" src="js/show_history.js"></script>|;
  #/show hhistory button

  $form->{simple_save} = 0;

  set_headings("edit");

  # editing without stuff to edit? try adding it first
  if ($form->{rowcount} && !$form->{print_and_save}) {
#     map { $id++ if $form->{"multi_id_$_"} } (1 .. $form->{rowcount});
#     if (!$id) {

      # reset rowcount
      undef $form->{rowcount};
      add();
      $main::lxdebug->leave_sub();
      return;
#     }
  } elsif (!$form->{id}) {
    add();
    $main::lxdebug->leave_sub();
    return;
  }

  my ($language_id, $printer_id);
  if ($form->{print_and_save}) {
    $form->{action}   = "dispatcher";
    $form->{action_print} = "1";
    $form->{resubmit} = 1;
    $language_id      = $form->{language_id};
    $printer_id       = $form->{printer_id};
  }

  set_headings("edit");

  order_links();
  prepare_order();

  if ($form->{print_and_save}) {
    $form->{language_id} = $language_id;
    $form->{printer_id}  = $printer_id;
  }

  display_form();

  $main::lxdebug->leave_sub();
}

sub order_links {
  $main::lxdebug->enter_sub();

  check_do_access();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  # get customer/vendor
  $form->all_vc(\%myconfig, $form->{vc}, ($form->{vc} eq 'customer') ? "AR" : "AP");

  # retrieve order/quotation
  $form->{webdav}   = $::instance_conf->get_webdav;

  my $editing = $form->{id};

  DO->retrieve('vc'  => $form->{vc},
               'ids' => $form->{id});

  $form->backup_vars(qw(payment_id language_id taxzone_id salesman_id taxincluded cp_id intnotes currency));
  $form->{shipto} = 1 if $form->{id} || $form->{convert_from_oe_ids};

  # get customer / vendor
  if ($form->{vc} eq 'vendor') {
    IR->get_vendor(\%myconfig, \%$form);
    $form->{discount} = $form->{vendor_discount};
  } else {
    IS->get_customer(\%myconfig, \%$form);
    $form->{discount} = $form->{customer_discount};
  }

  $form->restore_vars(qw(payment_id language_id taxzone_id intnotes cp_id));
  $form->restore_vars(qw(currency)) if ($form->{id} || $form->{convert_from_oe_ids});
  $form->restore_vars(qw(taxincluded)) if $form->{id};
  $form->restore_vars(qw(salesman_id)) if $editing;

  if ($form->{"all_$form->{vc}"}) {
    unless ($form->{"$form->{vc}_id"}) {
      $form->{"$form->{vc}_id"} = $form->{"all_$form->{vc}"}->[0]->{id};
    }
  }

  ($form->{ $form->{vc} })  = split /--/, $form->{ $form->{vc} };
  $form->{"old$form->{vc}"} = qq|$form->{$form->{vc}}--$form->{"$form->{vc}_id"}|;

  $form->{employee} = "$form->{employee}--$form->{employee_id}";

  $main::lxdebug->leave_sub();
}

sub prepare_order {
  $main::lxdebug->enter_sub();

  check_do_access();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $form->{formname} = $form->{type} unless $form->{formname};

  my $i = 0;
  foreach my $ref (@{ $form->{form_details} }) {
    $form->{rowcount} = ++$i;

    map { $form->{"${_}_$i"} = $ref->{$_} } keys %{$ref};
  }
  for my $i (1 .. $form->{rowcount}) {
    if ($form->{id}) {
      $form->{"discount_$i"} = $form->format_amount(\%myconfig, $form->{"discount_$i"} * 100);
    } else {
      $form->{"discount_$i"} = $form->format_amount(\%myconfig, $form->{"discount_$i"});
    }
    my ($dec) = ($form->{"sellprice_$i"} =~ /\.(\d+)/);
    $dec           = length $dec;
    my $decimalplaces = ($dec > 2) ? $dec : 2;

    # copy reqdate from deliverydate for invoice -> order conversion
    $form->{"reqdate_$i"} = $form->{"deliverydate_$i"} unless $form->{"reqdate_$i"};

    $form->{"sellprice_$i"} = $form->format_amount(\%myconfig, $form->{"sellprice_$i"}, $decimalplaces);
    $form->{"lastcost_$i"} = $form->format_amount(\%myconfig, $form->{"lastcost_$i"}, $decimalplaces);

    (my $dec_qty) = ($form->{"qty_$i"} =~ /\.(\d+)/);
    $dec_qty = length $dec_qty;
    $form->{"qty_$i"} = $form->format_amount(\%myconfig, $form->{"qty_$i"}, $dec_qty);
  }

  $main::lxdebug->leave_sub();
}

sub form_header {
  $main::lxdebug->enter_sub();

  check_do_access();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $form->{employee_id} = $form->{old_employee_id} if $form->{old_employee_id};
  $form->{salesman_id} = $form->{old_salesman_id} if $form->{old_salesman_id};

  my @old_project_ids = ($form->{"globalproject_id"});
  map({ push(@old_project_ids, $form->{"project_id_$_"})
          if ($form->{"project_id_$_"}); } (1..$form->{"rowcount"}));

  my $vc = $form->{vc} eq "customer" ? "customers" : "vendors";
  $form->get_lists("projects"       => {
                     "key"          => "ALL_PROJECTS",
                     "all"          => 0,
                     "old_id"       => \@old_project_ids
                   },
                   $vc              => "ALL_VC",
                   "price_factors"  => "ALL_PRICE_FACTORS",
                   "departments"    => "ALL_DEPARTMENTS",
                   "business_types" => "ALL_BUSINESS_TYPES",
    );

  $::form->{ALL_EMPLOYEES}         = SL::DB::Manager::Employee->get_all(query => [ or => [ id => $::form->{employee_id},  deleted => 0 ] ]);
  $::form->{ALL_SALESMEN}          = SL::DB::Manager::Employee->get_all(query => [ or => [ id => $::form->{salesman_id},  deleted => 0 ] ]);
  $::form->{ALL_SHIPTO}            = SL::DB::Manager::Shipto->get_all(query => [
    or => [ trans_id  => $::form->{"$::form->{vc}_id"} * 1, and => [ shipto_id => $::form->{shipto_id} * 1, trans_id => undef ] ]
  ]);
  $::form->{ALL_CONTACTS}          = SL::DB::Manager::Contact->get_all(query => [
    or => [
      cp_cv_id => $::form->{"$::form->{vc}_id"} * 1,
      and      => [
        cp_cv_id => undef,
        cp_id    => $::form->{cp_id} * 1
      ]
    ]
  ]);

  map { $_->{value} = "$_->{description}--$_->{id}" } @{ $form->{ALL_DEPARTMENTS} };
  map { $_->{value} = "$_->{name}--$_->{id}"        } @{ $form->{ALL_VC} };

  $form->{SHOW_VC_DROP_DOWN} =  $myconfig{vclimit} > scalar @{ $form->{ALL_VC} };

  $form->{oldvcname}         =  $form->{"old$form->{vc}"};
  $form->{oldvcname}         =~ s/--.*//;

  if ($form->{resubmit}) {
    my $dispatch_to_popup = '';
    if ($form->{format} eq "html") {
      $dispatch_to_popup .= "window.open('about:blank','Beleg'); document.do.target = 'Beleg';";
    }
    # emulate click for resubmitting actions
    $dispatch_to_popup .= "document.do.${_}.click(); " for grep { /^action_/ } keys %$form;
    $dispatch_to_popup .= "document.do.submit();";
    $::request->{layout}->add_javascripts_inline("\$(function(){$dispatch_to_popup})");
  }

  my $follow_up_vc                =  $form->{ $form->{vc} eq 'customer' ? 'customer' : 'vendor' };
  $follow_up_vc                   =~ s/--\d*\s*$//;

  $form->{follow_up_trans_info} = $form->{donumber} .'('. $follow_up_vc .')';

  $form->header();
  # Fix für Bug 1082 Erwartet wird: 'abteilungsNAME--abteilungsID'
  # und Erweiterung für Bug 1760:
  # Das war leider nur ein Teil-Fix, da das Verhalten den 'Erneuern'-Knopf
  # nicht überlebt. Konsequent jetzt auf L umgestellt
  #   $ perldoc SL::Template::Plugin::L
  # Daher entsprechend nur die Anpassung in form_header
  # und in DO.pm gemacht. 4 Testfälle:
  # department_id speichern                 | i.O.
  # department_id lesen                     | i.O.
  # department leer überlebt erneuern       | i.O.
  # department nicht leer überlebt erneuern | i.O.
  # $main::lxdebug->message(0, 'ABTEILUNGS ID in form?' . $form->{department_id});
  print $form->parse_html_template('do/form_header');

  $main::lxdebug->leave_sub();
}

sub form_footer {
  $main::lxdebug->enter_sub();

  check_do_access();

  my $form     = $main::form;

  $form->{PRINT_OPTIONS} = print_options('inline' => 1);

  print $form->parse_html_template('do/form_footer',
    {transfer_default         => ($::instance_conf->get_transfer_default)});

  $main::lxdebug->leave_sub();
}

sub update_delivery_order {
  $main::lxdebug->enter_sub();

  check_do_access();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  set_headings($form->{"id"} ? "edit" : "add");

  $form->{update} = 1;

  my $payment_id;
  $payment_id = $form->{payment_id} if $form->{payment_id};

  check_name($form->{vc});
  $form->{discount} =  $form->{"$form->{vc}_discount"} if defined $form->{"$form->{vc}_discount"};
  # Problem: Wenn man ohne Erneuern einen Kunden/Lieferanten
  # wechselt, wird der entsprechende Kunden/ Lieferantenrabatt
  # nicht übernommen. Grundproblem: In Commit 82574e78
  # hab ich aus discount customer_discount und vendor_discount
  # gemacht und entsprechend an den Oberflächen richtig hin-
  # geschoben. Die damals bessere Lösung wäre gewesen:
  # In den Templates nur die hidden für form-discount wieder ein-
  # setzen dann wäre die Verrenkung jetzt nicht notwendig.
  # TODO: Ggf. Bugfix 1284, 1575 und 817 wieder zusammenführen
  # Testfälle: Kunden mit Rabatt 0 -> Rabatt 20 i.O.
  #            Kunde mit Rabatt 20 -> Rabatt 0  i.O.
  #            Kunde mit Rabatt 20 -> Rabatt 5,5 i.O.
  $form->{payment_id} = $payment_id if $form->{payment_id} eq "";

  # for pricegroups
  my $i = $form->{rowcount};

  if (   ($form->{"partnumber_$i"} eq "")
      && ($form->{"description_$i"} eq "")
      && ($form->{"partsgroup_$i"}  eq "")) {

    check_form();

  } else {

    my $mode;
    if ($form->{type} eq 'purchase_delivery_order') {
      IR->retrieve_item(\%myconfig, $form);
      $mode = 'IR';
    } else {
      IS->retrieve_item(\%myconfig, $form);
      $mode = 'IS';
    }

    my $rows = scalar @{ $form->{item_list} };

    if ($rows) {
      $form->{"qty_$i"} = $form->parse_amount(\%myconfig, $form->{"qty_$i"});
      if( !$form->{"qty_$i"} ) {
        $form->{"qty_$i"} = 1;
      }

      if ($rows > 1) {

        select_item(mode => $mode);
        ::end_of_request();

      } else {

        map { $form->{"${_}_$i"} = $form->{item_list}[0]{$_} } keys %{ $form->{item_list}[0] };

        $form->{"marge_price_factor_$i"} = $form->{item_list}->[0]->{price_factor};
        $form->{"sellprice_$i"}          = $form->format_amount(\%myconfig, $form->{"sellprice_$i"});
        $form->{"lastcost_$i"}          = $form->format_amount(\%myconfig, $form->{"lastcost_$i"});
        $form->{"qty_$i"}                = $form->format_amount(\%myconfig, $form->{"qty_$i"});
      }

      display_form();

    } else {

      # ok, so this is a new part
      # ask if it is a part or service item

      if (   $form->{"partsgroup_$i"}
          && ($form->{"partsnumber_$i"} eq "")
          && ($form->{"description_$i"} eq "")) {
        $form->{rowcount}--;
        $form->{"discount_$i"} = "";
        $form->{"not_discountable_$i"} = "";
        display_form();

      } else {
        $form->{"id_$i"}   = 0;
        new_item();
      }
    }
  }

  $main::lxdebug->leave_sub();
}

sub search {
  $main::lxdebug->enter_sub();

  check_do_access();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $form->{vc} = $form->{type} eq 'purchase_delivery_order' ? 'vendor' : 'customer';

  $form->get_lists("projects"     => { "key" => "ALL_PROJECTS",
                                       "all" => 1 },
                   "departments"  => "ALL_DEPARTMENTS",
                   "$form->{vc}s" => "ALL_VC");
  $form->{ALL_EMPLOYEES} = SL::DB::Manager::Employee->get_all(query => [ deleted => 0 ]);

  $form->{SHOW_VC_DROP_DOWN} =  $myconfig{vclimit} > scalar @{ $form->{ALL_VC} };
  $form->{title}             = $locale->text('Delivery Orders');

  $form->header();

  print $form->parse_html_template('do/search');

  $main::lxdebug->leave_sub();
}

sub orders {
  $main::lxdebug->enter_sub();

  check_do_access();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $::request->{cgi};

  $form->{department_id} = (split /--/, $form->{department})[-1];
  ($form->{ $form->{vc} }, $form->{"$form->{vc}_id"}) = split(/--/, $form->{ $form->{vc} });

  report_generator_set_default_sort('transdate', 1);

  DO->transactions();

  $form->{rowcount} = scalar @{ $form->{DO} };

  my @columns = qw(
    ids                     transdate               reqdate
    id                      donumber
    ordnumber               customernumber
    name                    employee  salesman
    shipvia                 globalprojectnumber
    transaction_description department
    open                    delivered
  );

  $form->{l_open}      = $form->{l_closed} = "Y" if ($form->{open}      && $form->{closed});
  $form->{l_delivered} = "Y"                     if ($form->{delivered} && $form->{notdelivered});

  $form->{title}       = $locale->text('Delivery Orders');

  my $attachment_basename = $form->{vc} eq 'vendor' ? $locale->text('purchase_delivery_order_list') : $locale->text('sales_delivery_order_list');

  my $report = SL::ReportGenerator->new(\%myconfig, $form);

  my @hidden_variables = map { "l_${_}" } @columns;
  push @hidden_variables, $form->{vc}, qw(l_closed l_notdelivered open closed delivered notdelivered donumber ordnumber
                                          transaction_description transdatefrom transdateto type vc employee_id salesman_id project_id);

  my $href = build_std_url('action=orders', grep { $form->{$_} } @hidden_variables);

  my %column_defs = (
    'ids'                     => { 'text' => '', },
    'transdate'               => { 'text' => $locale->text('Date'), },
    'reqdate'                 => { 'text' => $locale->text('Reqdate'), },
    'id'                      => { 'text' => $locale->text('ID'), },
    'donumber'                => { 'text' => $locale->text('Delivery Order'), },
    'ordnumber'               => { 'text' => $locale->text('Order'), },
    'customernumber'          => { 'text' => $locale->text('Customer Number'), },
    'name'                    => { 'text' => $form->{vc} eq 'customer' ? $locale->text('Customer') : $locale->text('Vendor'), },
    'employee'                => { 'text' => $locale->text('Employee'), },
    'salesman'                => { 'text' => $locale->text('Salesman'), },
    'shipvia'                 => { 'text' => $locale->text('Ship via'), },
    'globalprojectnumber'     => { 'text' => $locale->text('Project Number'), },
    'transaction_description' => { 'text' => $locale->text('Transaction description'), },
    'open'                    => { 'text' => $locale->text('Open'), },
    'delivered'               => { 'text' => $locale->text('Delivered'), },
    'department'              => { 'text' => $locale->text('Department'), },
  );

  foreach my $name (qw(id transdate reqdate donumber ordnumber name employee salesman shipvia transaction_description department)) {
    my $sortdir                 = $form->{sort} eq $name ? 1 - $form->{sortdir} : $form->{sortdir};
    $column_defs{$name}->{link} = $href . "&sort=$name&sortdir=$sortdir";
  }

  $form->{"l_type"} = "Y";
  map { $column_defs{$_}->{visible} = $form->{"l_${_}"} ? 1 : 0 } @columns;

  $column_defs{ids}->{visible} = 'HTML';

  $report->set_columns(%column_defs);
  $report->set_column_order(@columns);

  $report->set_export_options('orders', @hidden_variables, qw(sort sortdir));

  $report->set_sort_indicator($form->{sort}, $form->{sortdir});

  my @options;
  if ($form->{customer}) {
    push @options, $locale->text('Customer') . " : $form->{customer}";
  }
  if ($form->{vendor}) {
    push @options, $locale->text('Vendor') . " : $form->{vendor}";
  }
  if ($form->{department}) {
    my ($department) = split /--/, $form->{department};
    push @options, $locale->text('Department') . " : $department";
  }
  if ($form->{donumber}) {
    push @options, $locale->text('Delivery Order Number') . " : $form->{donumber}";
  }
  if ($form->{ordnumber}) {
    push @options, $locale->text('Order Number') . " : $form->{ordnumber}";
  }
  if ($form->{transaction_description}) {
    push @options, $locale->text('Transaction description') . " : $form->{transaction_description}";
  }
  if ($form->{transdatefrom}) {
    push @options, $locale->text('From') . " " . $locale->date(\%myconfig, $form->{transdatefrom}, 1);
  }
  if ($form->{transdateto}) {
    push @options, $locale->text('Bis') . " " . $locale->date(\%myconfig, $form->{transdateto}, 1);
  }
  if ($form->{open}) {
    push @options, $locale->text('Open');
  }
  if ($form->{closed}) {
    push @options, $locale->text('Closed');
  }
  if ($form->{delivered}) {
    push @options, $locale->text('Delivered');
  }
  if ($form->{notdelivered}) {
    push @options, $locale->text('Not delivered');
  }

  $report->set_options('top_info_text'        => join("\n", @options),
                       'raw_top_info_text'    => $form->parse_html_template('do/orders_top'),
                       'raw_bottom_info_text' => $form->parse_html_template('do/orders_bottom'),
                       'output_format'        => 'HTML',
                       'title'                => $form->{title},
                       'attachment_basename'  => $attachment_basename . strftime('_%Y%m%d', localtime time),
    );
  $report->set_options_from_form();
  $locale->set_numberformat_wo_thousands_separator(\%myconfig) if lc($report->{options}->{output_format}) eq 'csv';

  # add sort and escape callback, this one we use for the add sub
  $form->{callback} = $href .= "&sort=$form->{sort}";

  # escape callback for href
  my $callback = $form->escape($href);

  my $edit_url       = build_std_url('action=edit', 'type', 'vc');
  my $edit_order_url = build_std_url('script=oe.pl', 'type=' . ($form->{type} eq 'sales_delivery_order' ? 'sales_order' : 'purchase_order'), 'action=edit');

  my $idx            = 1;

  foreach my $dord (@{ $form->{DO} }) {
    $dord->{open}      = $dord->{closed}    ? $locale->text('No')  : $locale->text('Yes');
    $dord->{delivered} = $dord->{delivered} ? $locale->text('Yes') : $locale->text('No');

    my $row = { map { $_ => { 'data' => $dord->{$_} } } @columns };

    $row->{ids}  = {
      'raw_data' =>   $cgi->hidden('-name' => "trans_id_${idx}", '-value' => $dord->{id})
                    . $cgi->checkbox('-name' => "multi_id_${idx}", '-value' => 1, '-label' => ''),
      'valign'   => 'center',
      'align'    => 'center',
    };

    $row->{donumber}->{link}  = $edit_url       . "&id=" . E($dord->{id})      . "&callback=${callback}";
    $row->{ordnumber}->{link} = $edit_order_url . "&id=" . E($dord->{oe_id})   . "&callback=${callback}" if $dord->{oe_id};
    $report->add_data($row);

    $idx++;
  }

  $report->generate_with_headers();

  $main::lxdebug->leave_sub();
}

sub save {
  $main::lxdebug->enter_sub();

  my (%params) = @_;

  check_do_access();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $form->{defaultcurrency} = $form->get_default_currency(\%myconfig);

  $form->isblank("transdate", $locale->text('Delivery Order Date missing!'));

  $form->{donumber} =~ s/^\s*//g;
  $form->{donumber} =~ s/\s*$//g;

  my $msg = ucfirst $form->{vc};
  $form->isblank($form->{vc}, $locale->text($msg . " missing!"));

  # $locale->text('Customer missing!');
  # $locale->text('Vendor missing!');

  remove_emptied_rows();
  validate_items();

  # if the name changed get new values
  if (check_name($form->{vc})) {
    update();
    ::end_of_request();
  }

  $form->{id} = 0 if $form->{saveasnew};

  DO->save();
  # saving the history
  if(!exists $form->{addition}) {
    $form->{snumbers} = qq|donumber_| . $form->{donumber};
    $form->{addition} = "SAVED";
    $form->save_history;
  }
  # /saving the history

  $form->{simple_save} = 1;
  if (!$params{no_redirect} && !$form->{print_and_save}) {
    set_headings("edit");
    update();
    ::end_of_request();
  }
  $main::lxdebug->leave_sub();
}

sub delete {
  $main::lxdebug->enter_sub();

  check_do_access();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  if (DO->delete()) {
    # saving the history
    if(!exists $form->{addition}) {
      $form->{snumbers} = qq|donumber_| . $form->{donumber};
      $form->{addition} = "DELETED";
      $form->save_history;
    }
    # /saving the history

    $form->info($locale->text('Delivery Order deleted!'));
    ::end_of_request();
  }

  $form->error($locale->text('Cannot delete delivery order!'));

  $main::lxdebug->leave_sub();
}

sub invoice {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  check_do_access();
  $main::auth->assert($form->{type} eq 'purchase_delivery_order' ? 'vendor_invoice_edit' : 'invoice_edit');

  $form->{convert_from_do_ids} = $form->{id};
  $form->{deliverydate}        = $form->{transdate};
  $form->{transdate}           = $form->{invdate} = $form->current_date(\%myconfig);
  $form->{duedate}             = $form->current_date(\%myconfig, $form->{invdate}, $form->{terms} * 1);
  $form->{defaultcurrency}     = $form->get_default_currency(\%myconfig);

  $form->{rowcount}--;

  delete @{$form}{qw(id closed delivered)};

  my ($script, $buysell);
  if ($form->{type} eq 'purchase_delivery_order') {
    $form->{title}  = $locale->text('Add Vendor Invoice');
    $form->{script} = 'ir.pl';
    $script         = "ir";
    $buysell        = 'sell';

  } else {
    $form->{title}  = $locale->text('Add Sales Invoice');
    $form->{script} = 'is.pl';
    $script         = "is";
    $buysell        = 'buy';
  }

  for my $i (1 .. $form->{rowcount}) {
    # für bug 1284
    unless ($form->{"ordnumber"}) {
      if ($form->{discount}) { # Falls wir einen Lieferanten-/Kundenrabatt haben
        # und rabattfähig sind, dann
        unless ($form->{"not_discountable_$i"}) {
          $form->{"discount_$i"} = $form->{discount}*100; # ... nehmen wir diesen Rabatt
        }
      }
    }
    map { $form->{"${_}_${i}"} = $form->parse_amount(\%myconfig, $form->{"${_}_${i}"}) if $form->{"${_}_${i}"} } qw(ship qty sellprice listprice lastcost basefactor);
  }

  $form->{type} = "invoice";

  # locale messages
  $main::locale = new Locale "$myconfig{countrycode}", "$script";
  $locale = $main::locale;

  require "bin/mozilla/$form->{script}";

  my $currency = $form->{currency};
  $form->{shipto} = 1 if $form->{convert_from_do_ids};
  invoice_links();

  if ($form->{ordnumber}) {
    require SL::DB::Order;
    if (my $order = SL::DB::Manager::Order->find_by(ordnumber => $form->{ordnumber})) {
      $order->load;
      $form->{orddate} = $order->transdate_as_date;
      $form->{$_}      = $order->$_ for qw(payment_id salesman_id taxzone_id quonumber);
    }
  }

  $form->{currency}     = $currency;
  $form->{exchangerate} = "";
  $form->{forex}        = $form->check_exchangerate(\%myconfig, $form->{currency}, $form->{invdate}, $buysell);
  $form->{exchangerate} = $form->{forex} if ($form->{forex});

  prepare_invoice();

  # format amounts
  for my $i (1 .. $form->{rowcount}) {
    $form->{"discount_$i"} = $form->format_amount(\%myconfig, $form->{"discount_$i"});

    my ($dec) = ($form->{"sellprice_$i"} =~ /\.(\d+)/);
    $dec           = length $dec;
    my $decimalplaces = ($dec > 2) ? $dec : 2;

    # copy delivery date from reqdate for order -> invoice conversion
    $form->{"deliverydate_$i"} = $form->{"reqdate_$i"}
      unless $form->{"deliverydate_$i"};


    $form->{"sellprice_$i"} =
      $form->format_amount(\%myconfig, $form->{"sellprice_$i"},
                           $decimalplaces);

    $form->{"lastcost_$i"} =
      $form->format_amount(\%myconfig, $form->{"lastcost_$i"},
                           $decimalplaces);

    (my $dec_qty) = ($form->{"qty_$i"} =~ /\.(\d+)/);
    $dec_qty = length $dec_qty;
    $form->{"qty_$i"} =
      $form->format_amount(\%myconfig, $form->{"qty_$i"}, $dec_qty);

  }

  #  show pricegroup in newly loaded invoice when creating invoice from delivery order
  for my $i (1 .. $form->{rowcount}) {
    $form->{"sellprice_pg_$i"} = join '--', $form->{"sellprice_$i"}, $form->{"pricegroup_id_$i"};
  }
  IS->get_pricegroups_for_parts(\%myconfig, \%$form);
  set_pricegroup($_) for 1 .. $form->{rowcount};

  display_form();

  $main::lxdebug->leave_sub();
}

sub invoice_multi {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  check_do_access();
  $main::auth->assert($form->{type} eq 'sales_delivery_order' ? 'invoice_edit' : 'vendor_invoice_edit');

  my @do_ids = map { $form->{"trans_id_$_"} } grep { $form->{"multi_id_$_"} } (1..$form->{rowcount});

  if (!scalar @do_ids) {
    $form->show_generic_error($locale->text('You have not selected any delivery order.'), 'back_button' => 1);
  }

  map { delete $form->{$_} } grep { m/^(?:trans|multi)_id_\d+/ } keys %{ $form };

  if (!DO->retrieve('vc' => $form->{vc}, 'ids' => \@do_ids)) {
    $form->show_generic_error($form->{vc} eq 'customer' ?
                              $locale->text('You cannot create an invoice for delivery orders for different customers.') :
                              $locale->text('You cannot create an invoice for delivery orders from different vendors.'),
                              'back_button' => 1);
  }

  my $source_type              = $form->{type};
  $form->{convert_from_do_ids} = join ' ', @do_ids;
  # bei der auswahl von mehreren Lieferscheinen fuer eine Rechnung, die einfach in donumber_array
  # zwischenspeichern (DO.pm) und als ' '-separierte Liste wieder zurueckschreiben
  # Hinweis: delete gibt den wert zurueck und loescht danach das element (nett und einfach)
  # $shell: perldoc perlunc; /delete EXPR
  $form->{donumber}            = delete $form->{donumber_array};
  $form->{deliverydate}        = $form->{transdate};
  $form->{transdate}           = $form->current_date(\%myconfig);
  $form->{duedate}             = $form->current_date(\%myconfig, $form->{invdate}, $form->{terms} * 1);
  $form->{type}                = "invoice";
  $form->{closed}              = 0;
  $form->{defaultcurrency}     = $form->get_default_currency(\%myconfig);

  my ($script, $buysell);
  if ($source_type eq 'purchase_delivery_order') {
    $form->{title}  = $locale->text('Add Vendor Invoice');
    $form->{script} = 'ir.pl';
    $script         = "ir";
    $buysell        = 'sell';

  } else {
    $form->{title}  = $locale->text('Add Sales Invoice');
    $form->{script} = 'is.pl';
    $script         = "is";
    $buysell        = 'buy';
  }

  map { delete $form->{$_} } qw(id subject message cc bcc printed emailed queued);

  # get vendor or customer discount
  my $vc_discount;
  my $saved_form = save_form();
  if ($form->{vc} eq 'vendor') {
    IR->get_vendor(\%myconfig, \%$form);
    $vc_discount = $form->{vendor_discount};
  } else {
    IS->get_customer(\%myconfig, \%$form);
    $vc_discount = $form->{customer_discount};
  }
  restore_form($saved_form);

  $form->{rowcount} = 0;
  foreach my $ref (@{ $form->{form_details} }) {
    $form->{rowcount}++;
    $ref->{reqdate} ||= $ref->{dord_transdate}; # copy transdates into each invoice row
    map { $form->{"${_}_$form->{rowcount}"} = $ref->{$_} } keys %{ $ref };
    map { $form->{"${_}_$form->{rowcount}"} = $form->format_amount(\%myconfig, $ref->{$_}) } qw(qty sellprice lastcost);

    if ($vc_discount){ # falls wir einen Lieferanten/Kundenrabatt haben
      # und keinen anderen discount wert an $i ...
      $form->{"discount_$form->{rowcount}"} ||= $vc_discount; # ... nehmen wir diesen Rabatt
    }

    $form->{"discount_$form->{rowcount}"}   = $form->{"discount_$form->{rowcount}"}  * 100; #s.a. Bug 1151
    # Anm.: Eine Änderung des discounts in der SL/DO.pm->retrieve (select (doi.discount * 100) as discount) ergibt in psql einen
    # Wert von 10.0000001490116. Ferner ist der Rabatt in der Rechnung dann bei 1.0 (?). Deswegen lasse ich das hier. jb 10.10.09

    $form->{"discount_$form->{rowcount}"} = $form->format_amount(\%myconfig, $form->{"discount_$form->{rowcount}"});
  }
  delete $form->{form_details};

  $locale = new Locale "$myconfig{countrycode}", "$script";

  require "bin/mozilla/$form->{script}";

  invoice_links();
  prepare_invoice();

  #  show pricegroup in newly loaded invoice when creating invoice from delivery order
  for my $i (1 .. $form->{rowcount}) {
    $form->{"sellprice_pg_$i"} = join '--', $form->{"sellprice_$i"}, $form->{"pricegroup_id_$i"};
  }
  IS->get_pricegroups_for_parts(\%myconfig, \%$form);
  set_pricegroup($_) for 1 .. $form->{rowcount};

  display_form();

  $main::lxdebug->leave_sub();
}

sub save_as_new {
  $main::lxdebug->enter_sub();

  check_do_access();

  my $form     = $main::form;

  $form->{saveasnew} = 1;
  $form->{closed}    = 0;
  $form->{delivered} = 0;
  map { delete $form->{$_} } qw(printed emailed queued);
  delete @{ $form }{ grep { m/^stock_(?:in|out)_\d+/ } keys %{ $form } };

  # Let kivitendo assign a new order number if the user hasn't changed the
  # previous one. If it has been changed manually then use it as-is.
  $form->{donumber} =~ s/^\s*//g;
  $form->{donumber} =~ s/\s*$//g;
  if ($form->{saved_donumber} && ($form->{saved_donumber} eq $form->{donumber})) {
    delete($form->{donumber});
  }

  save();

  $main::lxdebug->leave_sub();
}

sub e_mail {
  $main::lxdebug->enter_sub();

  check_do_access();

  my $form     = $main::form;

  $form->{print_and_save} = 1;

  my $saved_form = save_form();

  save();

  restore_form($saved_form, 0, qw(id ordnumber quonumber));

  edit_e_mail();

  $main::lxdebug->leave_sub();
}

sub calculate_stock_in_out {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;

  my $i = shift;

  if (!$form->{"id_${i}"}) {
    $main::lxdebug->leave_sub();
    return '';
  }

  my $all_units = AM->retrieve_all_units();

  my $in_out   = $form->{type} =~ /^sales/ ? 'out' : 'in';
  my $sinfo    = DO->unpack_stock_information('packed' => $form->{"stock_${in_out}_${i}"});

  my $do_qty   = AM->sum_with_unit($::form->{"qty_$i"}, $::form->{"unit_$i"});
  my $sum      = AM->sum_with_unit(map { $_->{qty}, $_->{unit} } @{ $sinfo });
  my $matches  = $do_qty == $sum;

  my $content  = $form->format_amount_units('amount'      => $sum * 1,
                                            'part_unit'   => $form->{"partunit_$i"},
                                            'amount_unit' => $all_units->{$form->{"partunit_$i"}}->{base_unit},
                                            'conv_units'  => 'convertible_not_smaller',
                                            'max_places'  => 2);
  $content     = qq|<span id="stock_in_out_qty_display_${i}">${content}</span><input type=hidden id='stock_in_out_qty_matches_$i' value='$matches'> <input type="button" onclick="open_stock_in_out_window('${in_out}', $i);" value="?">|;

  $main::lxdebug->leave_sub();

  return $content;
}

sub get_basic_bin_wh_info {
  $main::lxdebug->enter_sub();

  my $stock_info = shift;

  my $form     = $main::form;

  foreach my $sinfo (@{ $stock_info }) {
    next unless ($sinfo->{bin_id});

    my $bin_info = WH->get_basic_bin_info('id' => $sinfo->{bin_id});
    map { $sinfo->{"${_}_description"} = $sinfo->{"${_}description"} = $bin_info->{"${_}_description"} } qw(bin warehouse);
  }

  $main::lxdebug->leave_sub();
}

sub stock_in_out_form {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;

  if ($form->{in_out} eq 'out') {
    stock_out_form();
  } else {
    stock_in_form();
  }

  $main::lxdebug->leave_sub();
}

sub redo_stock_info {
  $main::lxdebug->enter_sub();

  my %params    = @_;

  my $form     = $main::form;

  my @non_empty = grep { $_->{qty} } @{ $params{stock_info} };

  if ($params{add_empty_row}) {
    push @non_empty, {
      'warehouse_id' => scalar(@non_empty) ? $non_empty[-1]->{warehouse_id} : undef,
      'bin_id'       => scalar(@non_empty) ? $non_empty[-1]->{bin_id}       : undef,
    };
  }

  @{ $params{stock_info} } = @non_empty;

  $main::lxdebug->leave_sub();
}

sub update_stock_in {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  my $stock_info = [];

  foreach my $i (1..$form->{rowcount}) {
    $form->{"qty_$i"} = $form->parse_amount(\%myconfig, $form->{"qty_$i"});
    push @{ $stock_info }, { map { $_ => $form->{"${_}_${i}"} } qw(warehouse_id bin_id chargenumber bestbefore qty unit) };
  }

  display_stock_in_form($stock_info);

  $main::lxdebug->leave_sub();
}

sub stock_in_form {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;

  my $stock_info = DO->unpack_stock_information('packed' => $form->{stock});

  display_stock_in_form($stock_info);

  $main::lxdebug->leave_sub();
}

sub display_stock_in_form {
  $main::lxdebug->enter_sub();

  my $stock_info = shift;

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $form->{title} = $locale->text('Stock');

  my $part_info  = IC->get_basic_part_info('id' => $form->{parts_id});

  # Standardlagerplatz für Standard-Auslagern verwenden, falls keiner für die Ware explizit definiert wurde
  if ($::instance_conf->get_transfer_default_use_master_default_bin) {
    $part_info->{warehouse_id} ||= $::instance_conf->get_warehouse_id;
    $part_info->{bin_id}       ||= $::instance_conf->get_bin_id;
  }

  my $units      = AM->retrieve_units(\%myconfig, $form);
  # der zweite Parameter von unit_select_data gibt den default-Namen (selected) vor
  my $units_data = AM->unit_select_data($units, $form->{do_unit}, undef, $part_info->{unit});

  $form->get_lists('warehouses' => { 'key'    => 'WAREHOUSES',
                                     'bins'   => 'BINS' });

  redo_stock_info('stock_info' => $stock_info, 'add_empty_row' => !$form->{delivered});

  get_basic_bin_wh_info($stock_info);

  $form->header(no_layout => 1);
  print $form->parse_html_template('do/stock_in_form', { 'UNITS'      => $units_data,
                                                         'STOCK_INFO' => $stock_info,
                                                         'PART_INFO'  => $part_info, });

  $main::lxdebug->leave_sub();
}

sub _stock_in_out_set_qty_display {
  my $stock_info       = shift;
  my $form             = $::form;
  my $all_units        = AM->retrieve_all_units();
  my $sum              = AM->sum_with_unit(map { $_->{qty}, $_->{unit} } @{ $stock_info });
  $form->{qty_display} = $form->format_amount_units(amount      => $sum * 1,
                                                    part_unit   => $form->{partunit},
                                                    amount_unit => $all_units->{ $form->{partunit} }->{base_unit},
                                                    conv_units  => 'convertible_not_smaller',
                                                    max_places  => 2);
}

sub set_stock_in {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  my $stock_info = [];

  foreach my $i (1..$form->{rowcount}) {
    $form->{"qty_$i"} = $form->parse_amount(\%myconfig, $form->{"qty_$i"});

    next if ($form->{"qty_$i"} <= 0);

    push @{ $stock_info }, { map { $_ => $form->{"${_}_${i}"} } qw(warehouse_id bin_id chargenumber bestbefore qty unit) };
  }

  $form->{stock} = YAML::Dump($stock_info);

  _stock_in_out_set_qty_display($stock_info);

  my $do_qty       = AM->sum_with_unit($::form->parse_amount(\%::myconfig, $::form->{do_qty}), $::form->{do_unit});
  my $transfer_qty = AM->sum_with_unit(map { $_->{qty}, $_->{unit} } @{ $stock_info });

  $form->header();
  print $form->parse_html_template('do/set_stock_in_out', {
    qty_matches => $do_qty == $transfer_qty,
  });

  $main::lxdebug->leave_sub();
}

sub stock_out_form {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $form->{title} = $locale->text('Release From Stock');

  my $part_info  = IC->get_basic_part_info('id' => $form->{parts_id});

  my $units      = AM->retrieve_units(\%myconfig, $form);
  my $units_data = AM->unit_select_data($units, undef, undef, $part_info->{unit});

  my @contents   = DO->get_item_availability('parts_id' => $form->{parts_id});

  my $stock_info = DO->unpack_stock_information('packed' => $form->{stock});

  if (!$form->{delivered}) {
    foreach my $row (@contents) {
      $row->{available_qty} = $form->format_amount_units('amount'      => $row->{qty} * 1,
                                                         'part_unit'   => $part_info->{unit},
                                                         'conv_units'  => 'convertible_not_smaller',
                                                         'max_places'  => 2);

      foreach my $sinfo (@{ $stock_info }) {
        next if (($row->{bin_id}       != $sinfo->{bin_id}) ||
                 ($row->{warehouse_id} != $sinfo->{warehouse_id}) ||
                 ($row->{chargenumber} ne $sinfo->{chargenumber}) ||
                 ($row->{bestbefore}   ne $sinfo->{bestbefore}));

        map { $row->{"stock_$_"} = $sinfo->{$_} } qw(qty unit error);
      }
    }

  } else {
    get_basic_bin_wh_info($stock_info);

    foreach my $sinfo (@{ $stock_info }) {
      map { $sinfo->{"stock_$_"} = $sinfo->{$_} } qw(qty unit);
    }
  }

  $form->header(no_layout => 1);
  print $form->parse_html_template('do/stock_out_form', { 'UNITS'      => $units_data,
                                                          'WHCONTENTS' => $form->{delivered} ? $stock_info : \@contents,
                                                          'PART_INFO'  => $part_info, });

  $main::lxdebug->leave_sub();
}

sub set_stock_out {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  my $stock_info = [];

  foreach my $i (1 .. $form->{rowcount}) {
    $form->{"qty_$i"} = $form->parse_amount(\%myconfig, $form->{"qty_$i"});

    next if ($form->{"qty_$i"} <= 0);

    push @{ $stock_info }, {
      'warehouse_id' => $form->{"warehouse_id_$i"},
      'bin_id'       => $form->{"bin_id_$i"},
      'chargenumber' => $form->{"chargenumber_$i"},
      'bestbefore'   => $form->{"bestbefore_$i"},
      'qty'          => $form->{"qty_$i"},
      'unit'         => $form->{"unit_$i"},
      'row'          => $i,
    };
  }

  my @errors     = DO->check_stock_availability('requests' => $stock_info,
                                                'parts_id' => $form->{parts_id});

  $form->{stock} = YAML::Dump($stock_info);

  if (@errors) {
    $form->{ERRORS} = [];
    map { push @{ $form->{ERRORS} }, $locale->text('Error in row #1: The quantity you entered is bigger than the stocked quantity.', $_->{row}); } @errors;
    stock_in_out_form();

  } else {
    _stock_in_out_set_qty_display($stock_info);

    my $do_qty       = AM->sum_with_unit($::form->parse_amount(\%::myconfig, $::form->{do_qty}), $::form->{do_unit});
    my $transfer_qty = AM->sum_with_unit(map { $_->{qty}, $_->{unit} } @{ $stock_info });

    $form->header();
    print $form->parse_html_template('do/set_stock_in_out', {
      qty_matches => $do_qty == $transfer_qty,
    });
  }

  $main::lxdebug->leave_sub();
}

sub transfer_in {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  if ($form->{id} && DO->is_marked_as_delivered(id => $form->{id})) {
    $form->show_generic_error($locale->text('The parts for this delivery order have already been transferred in.'), 'back_button' => 1);
  }

  save(no_redirect => 1);

  my @part_ids = map { $form->{"id_${_}"} } grep { $form->{"id_${_}"} && $form->{"stock_in_${_}"} } (1 .. $form->{rowcount});
  my @all_requests;

  if (@part_ids) {
    my $units         = AM->retrieve_units(\%myconfig, $form);
    my %part_info_map = IC->get_basic_part_info('id' => \@part_ids);
    my %request_map;

    $form->{ERRORS}   = [];

    foreach my $i (1 .. $form->{rowcount}) {
      next unless ($form->{"id_$i"} && $form->{"stock_in_$i"});

      my $row_sum_base_qty = 0;
      my $base_unit_factor = $units->{ $part_info_map{$form->{"id_$i"}}->{unit} }->{factor} || 1;

      foreach my $request (@{ DO->unpack_stock_information('packed' => $form->{"stock_in_$i"}) }) {
        $request->{parts_id}  = $form->{"id_$i"};
        $row_sum_base_qty    += $request->{qty} * $units->{$request->{unit}}->{factor} / $base_unit_factor;

        push @all_requests, $request;
      }

      next if (0 == $row_sum_base_qty);

      my $do_base_qty = $form->parse_amount(\%myconfig, $form->{"qty_$i"}) * $units->{$form->{"unit_$i"}}->{factor} / $base_unit_factor;

#      if ($do_base_qty != $row_sum_base_qty) {
#        push @{ $form->{ERRORS} }, $locale->text('Error in position #1: You must either assign no stock at all or the full quantity of #2 #3.',
#                                                 $i, $form->{"qty_$i"}, $form->{"unit_$i"});
#      }
    }

    if (@{ $form->{ERRORS} }) {
      push @{ $form->{ERRORS} }, $locale->text('The delivery order has not been marked as delivered. The warehouse contents have not changed.');

      set_headings('edit');
      update();
      $main::lxdebug->leave_sub();

      ::end_of_request();
    }
  }

  DO->transfer_in_out('direction' => 'in',
                      'requests'  => \@all_requests);

  SL::DB::DeliveryOrder->new(id => $form->{id})->load->update_attributes(delivered => 1);

  $form->{callback} = 'do.pl?action=edit&type=purchase_delivery_order&id=' . $form->escape($form->{id});
  $form->redirect;

  $main::lxdebug->leave_sub();
}

sub transfer_out {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  if ($form->{id} && DO->is_marked_as_delivered(id => $form->{id})) {
    $form->show_generic_error($locale->text('The parts for this delivery order have already been transferred out.'), 'back_button' => 1);
  }

  save(no_redirect => 1);

  my @part_ids = map { $form->{"id_${_}"} } grep { $form->{"id_${_}"} && $form->{"stock_out_${_}"} } (1 .. $form->{rowcount});
  my @all_requests;

  if (@part_ids) {
    my $units         = AM->retrieve_units(\%myconfig, $form);
    my %part_info_map = IC->get_basic_part_info('id' => \@part_ids);
    my %request_map;

    $form->{ERRORS}   = [];

    foreach my $i (1 .. $form->{rowcount}) {
      next unless ($form->{"id_$i"} && $form->{"stock_out_$i"});

      my $row_sum_base_qty = 0;
      my $base_unit_factor = $units->{ $part_info_map{$form->{"id_$i"}}->{unit} }->{factor} || 1;

      foreach my $request (@{ DO->unpack_stock_information('packed' => $form->{"stock_out_$i"}) }) {
        $request->{parts_id} = $form->{"id_$i"};
        $request->{base_qty} = $request->{qty} * $units->{$request->{unit}}->{factor} / $base_unit_factor;
        $request->{project_id} = $form->{"project_id_$i"} ? $form->{"project_id_$i"} : $form->{globalproject_id};

        my $map_key          = join '--', ($form->{"id_$i"}, @{$request}{qw(warehouse_id bin_id chargenumber bestbefore)});

        $request_map{$map_key}                 ||= $request;
        $request_map{$map_key}->{sum_base_qty} ||= 0;
        $request_map{$map_key}->{sum_base_qty}  += $request->{base_qty};
        $row_sum_base_qty                       += $request->{base_qty};

        push @all_requests, $request;
      }

      next if (0 == $row_sum_base_qty);

      my $do_base_qty = $form->{"qty_$i"} * $units->{$form->{"unit_$i"}}->{factor} / $base_unit_factor;

#      if ($do_base_qty != $row_sum_base_qty) {
#        push @{ $form->{ERRORS} }, $locale->text('Error in position #1: You must either assign no transfer at all or the full quantity of #2 #3.',
#                                                 $i, $form->{"qty_$i"}, $form->{"unit_$i"});
#      }
    }

    if (%request_map) {
      my @bin_ids      = map { $_->{bin_id} } values %request_map;
      my %bin_info_map = WH->get_basic_bin_info('id' => \@bin_ids);
      my @contents     = DO->get_item_availability('parts_id' => \@part_ids);

      foreach my $inv (@contents) {
        my $map_key = join '--', @{$inv}{qw(parts_id warehouse_id bin_id chargenumber bestbefore)};

        next unless ($request_map{$map_key});

        my $request    = $request_map{$map_key};
        $request->{ok} = $request->{sum_base_qty} <= $inv->{qty};
      }

      foreach my $request (values %request_map) {
        next if ($request->{ok});

        my $pinfo = $part_info_map{$request->{parts_id}};
        my $binfo = $bin_info_map{$request->{bin_id}};

        if ($::instance_conf->get_show_bestbefore) {
            push @{ $form->{ERRORS} }, $locale->text("There is not enough available of '#1' at warehouse '#2', bin '#3', #4, #5, for the transfer of #6.",
                                                     $pinfo->{description},
                                                     $binfo->{warehouse_description},
                                                     $binfo->{bin_description},
                                                     $request->{chargenumber} ? $locale->text('chargenumber #1', $request->{chargenumber}) : $locale->text('no chargenumber'),
                                                     $request->{bestbefore} ? $locale->text('bestbefore #1', $request->{bestbefore}) : $locale->text('no bestbefore'),
                                                     $form->format_amount_units('amount'      => $request->{sum_base_qty},
                                                                                'part_unit'   => $pinfo->{unit},
                                                                                'conv_units'  => 'convertible_not_smaller'));
        } else {
            push @{ $form->{ERRORS} }, $locale->text("There is not enough available of '#1' at warehouse '#2', bin '#3', #4, for the transfer of #5.",
                                                     $pinfo->{description},
                                                     $binfo->{warehouse_description},
                                                     $binfo->{bin_description},
                                                     $request->{chargenumber} ? $locale->text('chargenumber #1', $request->{chargenumber}) : $locale->text('no chargenumber'),
                                                     $form->format_amount_units('amount'      => $request->{sum_base_qty},
                                                                                'part_unit'   => $pinfo->{unit},
                                                                                'conv_units'  => 'convertible_not_smaller'));
        }
      }
    }

    if (@{ $form->{ERRORS} }) {
      push @{ $form->{ERRORS} }, $locale->text('The delivery order has not been marked as delivered. The warehouse contents have not changed.');

      set_headings('edit');
      update();
      $main::lxdebug->leave_sub();

      ::end_of_request();
    }
  }
  DO->transfer_in_out('direction' => 'out',
                      'requests'  => \@all_requests);

  SL::DB::DeliveryOrder->new(id => $form->{id})->load->update_attributes(delivered => 1);

  $form->{callback} = 'do.pl?action=edit&type=sales_delivery_order&id=' . $form->escape($form->{id});
  $form->redirect;

  $main::lxdebug->leave_sub();
}

sub mark_closed {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;

  DO->close_orders('ids' => [ $form->{id} ]);

  $form->{closed} = 1;

  update();

  $main::lxdebug->leave_sub();
}


sub yes {
  call_sub($main::form->{yes_nextsub});
}

sub no {
  call_sub($main::form->{no_nextsub});
}

sub update {
  call_sub($main::form->{update_nextsub} || $main::form->{nextsub} || 'update_delivery_order');
}

sub dispatcher {
  my $form     = $main::form;
  my $locale   = $main::locale;

  foreach my $action (qw(update ship_to print e_mail save transfer_out transfer_out_default
                         transfer_in transfer_in_default mark_closed save_as_new invoice delete)) {
    if ($form->{"action_${action}"}) {
      call_sub($action);
      return;
    }
  }

  $form->error($locale->text('No action defined.'));
}

sub transfer_out_default {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;

  transfer_in_out_default('direction' => 'out');

  $main::lxdebug->leave_sub();
}

sub transfer_in_default {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;

  transfer_in_out_default('direction' => 'in');

  $main::lxdebug->leave_sub();
}

# Falls das Standardlagerverfahren aktiv ist, wird
# geprüft, ob alle Standardlagerplätze für die Auslager-
# artikel vorhanden sind UND ob die Warenmenge ausreicht zum
# Auslagern. Falls nicht wird entsprechend eine Fehlermeldung
# generiert. Offen Chargennummer / bestbefore wird nicht berücksichtigt
sub transfer_in_out_default {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my %params   = @_;

  my (%missing_default_bins, %qty_parts, @all_requests, %part_info_map, $default_warehouse_id, $default_bin_id);

  Common::check_params(\%params, qw(direction));

  # entsprechende defaults holen, falls standardlagerplatz verwendet werden soll
  if ($::instance_conf->get_transfer_default_use_master_default_bin) {
    $default_warehouse_id = $::instance_conf->get_warehouse_id;
    $default_bin_id       = $::instance_conf->get_bin_id;
  }


  my @part_ids = map { $form->{"id_${_}"} } (1 .. $form->{rowcount});
  if (@part_ids) {
    my $units         = AM->retrieve_units(\%myconfig, $form);
    %part_info_map = IC->get_basic_part_info('id' => \@part_ids);
    foreach my $i (1 .. $form->{rowcount}) {
      next unless ($form->{"id_$i"});
      my $base_unit_factor = $units->{ $part_info_map{$form->{"id_$i"}}->{unit} }->{factor} || 1;
      my $qty =   $form->parse_amount(\%myconfig, $form->{"qty_$i"}) * $units->{$form->{"unit_$i"}}->{factor} / $base_unit_factor;
      $qty_parts{$form->{"id_$i"}} += $qty;


      $part_info_map{$form->{"id_$i"}}{bin_id}       ||= $default_bin_id;
      $part_info_map{$form->{"id_$i"}}{warehouse_id} ||= $default_warehouse_id;

      push @all_requests, {
                        'chargenumber' => '',  #?? die müsste entsprechend geholt werden
                        #'bestbefore' => undef, # TODO wird nicht berücksichtigt
                        'bin_id' => $part_info_map{$form->{"id_$i"}}{bin_id},
                        'qty' => $qty,
                        'parts_id' => $form->{"id_$i"},
                        'comment' => 'Default transfer DO',
                        'ok' => 1,
                        'unit' => $part_info_map{$form->{"id_$i"}}{unit},
                        'warehouse_id' => $part_info_map{$form->{"id_$i"}}{warehouse_id},
                        'oe_id' => $form->{id},
                        'project_id' => $form->{"project_id_$i"} ? $form->{"project_id_$i"} : $form->{globalproject_id}
                      };
    }

    # jetzt wird erst überprüft, ob die Stückzahl entsprechend stimmt.
    if ($params{direction} eq 'out') {  # wird nur für ausgehende Mengen benötigit
      foreach my $key (keys %qty_parts) {

        $missing_default_bins{$key}{missing_bin} = 1 unless ($part_info_map{$key}{bin_id});
        next unless ($part_info_map{$key}{bin_id}); # abbruch

        my ($max_qty, $error) = WH->get_max_qty_parts_bin(parts_id => $key, bin_id => $part_info_map{$key}{bin_id});
        if ($error == 1) {
          # wir können nicht entscheiden, welche charge oder mhd (bestbefore) ausgewählt sein soll
          # deshalb rückmeldung nach oben geben, manuell auszulagern
          # TODO Bei nur einem Treffer mit Charge oder bestbefore wäre das noch möglich
          $missing_default_bins{$key}{chargenumber} = 1;
        }
        if ($max_qty < $qty_parts{$key}){
          $missing_default_bins{$key}{missing_qty} = $max_qty - $qty_parts{$key};
        }
      }
    }
  } # if @parts_id

  # Abfrage für Fehlerbehandlung (nur bei direction == out)
  if (scalar (keys %missing_default_bins)) {
    my $fehlertext;
    foreach my $fehler (keys %missing_default_bins) {

      my $ware = WH->get_part_description(parts_id => $fehler);
      if ($missing_default_bins{$fehler}{missing_bin}){
        $fehlertext .= "Kein Standardlagerplatz definiert bei $ware <br>";
      }
      if ($missing_default_bins{$fehler}{missing_qty}) {  # missing_qty
        $fehlertext .= "Es fehlen " . $missing_default_bins{$fehler}{missing_qty}*-1 .
                       " von $ware auf dem Standard-Lagerplatz " . $part_info_map{$fehler}{bin} .   " zum Auslagern<br>";
      }
      if ($missing_default_bins{$fehler}{chargenumber}){
        $fehlertext .= "Die Ware hat eine Chargennummer oder eine Mindesthaltbarkeit definiert.
                        Hier kann man nicht automatisch entscheiden.
                        Bitte diesen Lieferschein manuell auslagern.
                        Bei: $ware";
      }
      # auslagern soll immer gehen, auch wenn nicht genügend auf lager ist.
      # der lagerplatz ist hier extra konfigurierbar, bspw. Lager-Korrektur mit
      # Lagerplatz Lagerplatz-Korrektur
      my $default_warehouse_id_ignore_onhand = $::instance_conf->get_warehouse_id_ignore_onhand;
      my $default_bin_id_ignore_onhand       = $::instance_conf->get_bin_id_ignore_onhand;
      if ($::instance_conf->get_transfer_default_ignore_onhand && $default_bin_id_ignore_onhand) {
        # entsprechende defaults holen
        # falls chargenumber, bestbefore oder anzahl nicht stimmt, auf automatischen
        # lagerplatz wegbuchen!
        foreach (@all_requests) {
          if ($_->{parts_id} eq $fehler){
          $_->{bin_id}        = $default_bin_id_ignore_onhand;
          $_->{warehouse_id}  = $default_warehouse_id_ignore_onhand;
          }
        }
      } else {
        #$main::lxdebug->message(0, 'Fehlertext: ' . $fehlertext);
        $form->show_generic_error($locale->text("Cannot transfer. <br> Reason:<br>#1", $fehlertext ), 'back_button' => 1);
      }
    }
  }


  # hier der eigentliche fallunterschied für in oder out
  my $prefix   = $params{direction} eq 'in' ? 'in' : 'out';

  # dieser array_ref ist für DO->save da:
  # einmal die all_requests in YAML verwandeln, damit delivery_order_items_stock
  # gefüllt werden kann.
  my $i = 1;
  foreach (@all_requests){
    $form->{"stock_${prefix}_$i"} = YAML::Dump([$_]);
    $i++;
  }

  save(no_redirect => 1); # Wir können auslagern, deshalb beleg speichern
                          # und in delivery_order_items_stock speichern
  DO->transfer_in_out('direction' => $prefix,
                      'requests'  => \@all_requests);

  SL::DB::DeliveryOrder->new(id => $form->{id})->load->update_attributes(delivered => 1);

  $form->{callback} = 'do.pl?action=edit&type=sales_delivery_order&id=' . $form->escape($form->{id}) if $params{direction} eq 'out';
  $form->{callback} = 'do.pl?action=edit&type=purchase_delivery_order&id=' . $form->escape($form->{id}) if $params{direction} eq 'in';
  $form->redirect;

}
