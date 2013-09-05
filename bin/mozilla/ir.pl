#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger, Accounting
# Copyright (c) 1998-2002
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
# Inventory received module
#
#======================================================================

use SL::FU;
use SL::IR;
use SL::IS;
use SL::PE;
use SL::DB::Default;
use List::Util qw(max sum);

require "bin/mozilla/io.pl";
require "bin/mozilla/invoice_io.pl";
require "bin/mozilla/arap.pl";
require "bin/mozilla/common.pl";
require "bin/mozilla/drafts.pl";

use strict;

1;

# end of main

sub add {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my $locale   = $main::locale;

  $main::auth->assert('vendor_invoice_edit');

  return $main::lxdebug->leave_sub() if (load_draft_maybe());

  $form->{title} = $locale->text('Record Vendor Invoice');

  &invoice_links;
  &prepare_invoice;
  &display_form;

  $main::lxdebug->leave_sub();
}

sub edit {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my $locale   = $main::locale;

  $main::auth->assert('vendor_invoice_edit');

  # show history button
  $form->{javascript} = qq|<script type=text/javascript src=js/show_history.js></script>|;
  #/show hhistory button

  $form->{title} = $locale->text('Edit Vendor Invoice');

  &invoice_links;
  &prepare_invoice;
  &display_form;

  $main::lxdebug->leave_sub();
}

sub invoice_links {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $main::auth->assert('vendor_invoice_edit');

  $form->{vc} = 'vendor';

  # create links
  $form->{webdav}   = $::instance_conf->get_webdav;

  $form->create_links("AP", \%myconfig, "vendor");

  #quote all_vendor Bug 133
  foreach my $ref (@{ $form->{all_vendor} }) {
    $ref->{name} = $form->quote($ref->{name});
  }

  if ($form->{all_vendor}) {
    unless ($form->{vendor_id}) {
      $form->{vendor_id} = $form->{all_vendor}->[0]->{id};
    }
  }

  my ($payment_id, $language_id, $taxzone_id, $currency);
  if ($form->{payment_id}) {
    $payment_id = $form->{payment_id};
  }
  if ($form->{language_id}) {
    $language_id = $form->{language_id};
  }
  if ($form->{taxzone_id}) {
    $taxzone_id = $form->{taxzone_id};
  }
  if ($form->{currency}) {
    $currency = $form->{currency};
  }

  my $cp_id = $form->{cp_id};
  IR->get_vendor(\%myconfig, \%$form);
  IR->retrieve_invoice(\%myconfig, \%$form);
  $form->{cp_id} = $cp_id;

  if ($payment_id) {
    $form->{payment_id} = $payment_id;
  }
  if ($language_id) {
    $form->{language_id} = $language_id;
  }
  if ($taxzone_id) {
    $form->{taxzone_id} = $taxzone_id;
  }
  if ($currency) {
    $form->{currency} = $currency;
  }

  my @curr = $form->get_all_currencies();
  map { $form->{selectcurrency} .= "<option>$_\n" } @curr;

  $form->{oldvendor} = "$form->{vendor}--$form->{vendor_id}";

  # build vendor/customer drop down comatibility... don't ask
  if (@{ $form->{"all_vendor"} || [] }) {
    $form->{"selectvendor"} = 1;
    $form->{vendor}         = qq|$form->{vendor}--$form->{vendor_id}|;
  }

  # departments
  if ($form->{all_departments}) {
    $form->{selectdepartment} = "<option>\n";
    $form->{department}       = "$form->{department}--$form->{department_id}";

    map {
      $form->{selectdepartment} .=
        "<option>$_->{description}--$_->{id}\n"
    } (@{ $form->{all_departments} || [] });
  }

  # forex
  $form->{forex} = $form->{exchangerate};
  my $exchangerate = ($form->{exchangerate}) ? $form->{exchangerate} : 1;

  foreach my $key (keys %{ $form->{AP_links} }) {

    foreach my $ref (@{ $form->{AP_links}{$key} }) {
      $form->{"select$key"} .= "<option>$ref->{accno}--$ref->{description}</option>";
    }

    next unless $form->{acc_trans}{$key};

    if ($key eq "AP_paid") {
      for my $i (1 .. scalar @{ $form->{acc_trans}{$key} }) {
        $form->{"AP_paid_$i"} =
          "$form->{acc_trans}{$key}->[$i-1]->{accno}--$form->{acc_trans}{$key}->[$i-1]->{description}";

        $form->{"acc_trans_id_$i"} = $form->{acc_trans}{$key}->[$i - 1]->{acc_trans_id};
        # reverse paid
        $form->{"paid_$i"}     = $form->{acc_trans}{$key}->[$i - 1]->{amount};
        $form->{"datepaid_$i"} =
          $form->{acc_trans}{$key}->[$i - 1]->{transdate};
        $form->{"gldate_$i"}   = $form->{acc_trans}{$key}->[$i - 1]->{gldate};
        $form->{"forex_$i"} = $form->{"exchangerate_$i"} =
          $form->{acc_trans}{$key}->[$i - 1]->{exchangerate};
        $form->{"source_$i"} = $form->{acc_trans}{$key}->[$i - 1]->{source};
        $form->{"memo_$i"}   = $form->{acc_trans}{$key}->[$i - 1]->{memo};

        $form->{paidaccounts} = $i;
      }
    } else {
      $form->{$key} =
        "$form->{acc_trans}{$key}->[0]->{accno}--$form->{acc_trans}{$key}->[0]->{description}";
    }

  }

  $form->{paidaccounts} = 1 unless (exists $form->{paidaccounts});

  $form->{AP} = $form->{AP_1} unless $form->{id};

  $form->{locked} =
    ($form->datetonum($form->{invdate}, \%myconfig) <=
     $form->datetonum($form->{closedto}, \%myconfig));

  $main::lxdebug->leave_sub();
}

sub prepare_invoice {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $main::auth->assert('vendor_invoice_edit');

  if ($form->{id}) {

    map { $form->{$_} =~ s/\"/&quot;/g } qw(invnumber ordnumber quonumber);

    my $i = 0;
    foreach my $ref (@{ $form->{invoice_details} }) {
      $i++;
      map { $form->{"${_}_$i"} = $ref->{$_} } keys %{$ref};
      # übernommen aus is.pl Fix für Bug 1642. Nebenwirkungen? jb 12.5.2011
      # getestet: Lieferantenauftrag -> Rechnung i.O.
      #           Lieferantenauftrag -> Lieferschein -> Rechnung i.O.
      # Werte: 20% (Lieferantenrabatt), 12,4% individuell und 0,4 individuell s.a.
      # Screenshot zu Bug 1642
      $form->{"discount_$i"}   = $form->format_amount(\%myconfig, $form->{"discount_$i"} * 100);

      my ($dec) = ($form->{"sellprice_$i"} =~ /\.(\d+)/);
      $dec           = length $dec;
      my $decimalplaces = ($dec > 2) ? $dec : 2;

      $form->{"sellprice_$i"} =
        $form->format_amount(\%myconfig, $form->{"sellprice_$i"},
                             $decimalplaces);

      (my $dec_qty) = ($form->{"qty_$i"} =~ /\.(\d+)/);
      $dec_qty = length $dec_qty;

      $form->{"qty_$i"} =
        $form->format_amount(\%myconfig, ($form->{"qty_$i"} * -1), $dec_qty);

      $form->{rowcount} = $i;
    }
  }

  $main::lxdebug->leave_sub();
}

sub form_header {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $::request->{cgi};

  $main::auth->assert('vendor_invoice_edit');

  my %TMPL_VAR = ();
  my @custom_hiddens;

  $form->{employee_id} = $form->{old_employee_id} if $form->{old_employee_id};
  $form->{salesman_id} = $form->{old_salesman_id} if $form->{old_salesman_id};

  $form->{defaultcurrency} = $form->get_default_currency(\%myconfig);

  my @old_project_ids = ($form->{"globalproject_id"});
  map { push @old_project_ids, $form->{"project_id_$_"} if $form->{"project_id_$_"}; } 1..$form->{"rowcount"};

  $form->get_lists("projects"      => { "key"    => "ALL_PROJECTS",
                                        "all"    => 0,
                                        "old_id" => \@old_project_ids },
                   "taxzones"      => "ALL_TAXZONES",
                   "currencies"    => "ALL_CURRENCIES",
                   "vendors"       => "ALL_VENDORS",
                   "departments"   => "all_departments",
                   "price_factors" => "ALL_PRICE_FACTORS");

  $TMPL_VAR{ALL_EMPLOYEES}         = SL::DB::Manager::Employee->get_all(query => [ or => [ id => $::form->{employee_id},  deleted => 0 ] ]);
  $TMPL_VAR{ALL_CONTACTS}          = SL::DB::Manager::Contact->get_all(query => [
    or => [
      cp_cv_id => $::form->{"$::form->{vc}_id"} * 1,
      and      => [
        cp_cv_id => undef,
        cp_id    => $::form->{cp_id} * 1
      ]
    ]
  ]);
  $TMPL_VAR{department_labels}     = sub { "$_[0]->{description}--$_[0]->{id}" };

  # customer
  $TMPL_VAR{vc_keys} = sub { "$_[0]->{name}--$_[0]->{id}" };
  $TMPL_VAR{vclimit} = $myconfig{vclimit};
  $TMPL_VAR{vc_select} = "customer_or_vendor_selection_window('vendor', '', 1, 0)";
  push @custom_hiddens, "vendor_id";
  push @custom_hiddens, "oldvendor";
  push @custom_hiddens, "selectvendor";

  # currencies and exchangerate
  my @values = map { $_       } @{ $form->{ALL_CURRENCIES} };
  my %labels = map { $_ => $_ } @{ $form->{ALL_CURRENCIES} };
  $form->{currency}            = $form->{defaultcurrency} unless $form->{currency};
  # show_exchangerate is also later needed in another template
  $form->{show_exchangerate} = $form->{currency} ne $form->{defaultcurrency};
  $TMPL_VAR{currencies}        = NTI($cgi->popup_menu('-name' => 'currency', '-default' => $form->{"currency"},
                                                      '-values' => \@values, '-labels' => \%labels,
                                                      '-onchange' => "document.getElementById('update_button').click();"
                                     )) if scalar @values;
  push @custom_hiddens, "forex";
  push @custom_hiddens, "exchangerate" if $form->{forex};

  $TMPL_VAR{creditwarning} = ($form->{creditlimit} != 0) && ($form->{creditremaining} < 0) && !$form->{update};
  $TMPL_VAR{is_credit_remaining_negativ} = $form->{creditremaining} =~ /-/;

  my $follow_up_vc         =  $form->{vendor};
  $follow_up_vc            =~ s/--\d*\s*$//;
  $TMPL_VAR{vendor_name} = $follow_up_vc;

# set option selected
  foreach my $item (qw(AP)) {
    $form->{"select$item"} =~ s/ selected//;
    $form->{"select$item"} =~ s/option>\Q$form->{$item}\E/option selected>$form->{$item}/;
  }

  $TMPL_VAR{is_type_credit_note} = $form->{type}   eq "credit_note";
  $TMPL_VAR{is_format_html}      = $form->{format} eq 'html';
  $TMPL_VAR{dateformat}          = $myconfig{dateformat};
  $TMPL_VAR{numberformat}        = $myconfig{numberformat};

  # hiddens
  $TMPL_VAR{HIDDENS} = [qw(
    id action type media format queued printed emailed title vc discount
    title creditlimit creditremaining tradediscount business closedto locked shipped storno storno_id
    max_dunning_level dunning_amount
    shiptoname shiptostreet shiptozipcode shiptocity shiptocountry  shiptocontact shiptophone shiptofax
    shiptoemail shiptodepartment_1 shiptodepartment_2 message email subject cc bcc taxaccounts cursor_fokus
    convert_from_do_ids convert_from_oe_ids
  ), @custom_hiddens,
  map { $_.'_rate', $_.'_description', $_.'_taxnumber' } split / /, $form->{taxaccounts}];

  $form->header();

  print $form->parse_html_template("ir/form_header", \%TMPL_VAR);

  $main::lxdebug->leave_sub();
}

sub form_footer {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('vendor_invoice_edit');

  $form->{invtotal}    = $form->{invsubtotal};
  $form->{oldinvtotal} = $form->{invtotal};

  # note rows
  $form->{rows} = max 2,
    $form->numtextrows($form->{notes},    26, 8),
    $form->numtextrows($form->{intnotes}, 35, 8);


  # tax, total and subtotal calculations
  my ($tax, $subtotal);
  $form->{taxaccounts_array} = [ split / /, $form->{taxaccounts} ];

  foreach my $item (@{ $form->{taxaccounts_array} }) {
    if ($form->{"${item}_base"}) {
      if ($form->{taxincluded}) {
        $form->{"${item}_total"} = $form->round_amount( ($form->{"${item}_base"} * $form->{"${item}_rate"}
                                                                                 / (1 + $form->{"${item}_rate"})), 2);
        $form->{"${item}_netto"} = $form->round_amount( ($form->{"${item}_base"} - $form->{"${item}_total"}), 2);
      } else {
        $form->{"${item}_total"} = $form->round_amount( $form->{"${item}_base"} * $form->{"${item}_rate"}, 2);
        $form->{invtotal} += $form->{"${item}_total"};
      }
    }
  }

  # follow ups
  if ($form->{id}) {
    $form->{follow_ups}            = FU->follow_ups('trans_id' => $form->{id}) || [];
    $form->{follow_ups_unfinished} = ( sum map { $_->{due} * 1 } @{ $form->{follow_ups} } ) || 0;
  }

  # payments
  my $totalpaid = 0;
  $form->{paidaccounts}++ if ($form->{"paid_$form->{paidaccounts}"});
  $form->{paid_indices} = [ 1 .. $form->{paidaccounts} ];

  # Standard Konto für Umlaufvermögen
  my $accno_arap = IS->get_standard_accno_current_assets(\%myconfig, \%$form);

  for my $i (1 .. $form->{paidaccounts}) {
    $form->{"changeable_$i"} = 1;
    if (SL::DB::Default->get->payments_changeable == 0) {
      # never
      $form->{"changeable_$i"} = ($form->{"acc_trans_id_$i"})? 0 : 1;
    } elsif (SL::DB::Default->get->payments_changeable == 2) {
      # on the same day
      $form->{"changeable_$i"} = (($form->{"gldate_$i"} eq '') ||
                                  ($form->current_date(\%myconfig) eq $form->{"gldate_$i"}));
    }

    $form->{"selectAP_paid_$i"} = $form->{selectAP_paid};
    if (!$form->{"AP_paid_$i"}) {
      $form->{"selectAP_paid_$i"} =~ s/option>$accno_arap--(.*?)>/option selected>$accno_arap--$1>/;
    } else {
      $form->{"selectAP_paid_$i"} =~ s/option>\Q$form->{"AP_paid_$i"}\E/option selected>$form->{"AP_paid_$i"}/;
    }

    $totalpaid += $form->{"paid_$i"};
  }

  print $form->parse_html_template('ir/form_footer', {
    is_type_credit_note => ($form->{type} eq "credit_note"),
    totalpaid           => $totalpaid,
    paid_missing        => $form->{invtotal} - $totalpaid,
    show_storno         => $form->{id} && !$form->{storno} && !IS->has_storno(\%myconfig, $form, "ap") && !$totalpaid,
    show_delete         => ($::instance_conf->get_ir_changeable == 2)
                             ? ($form->current_date(\%myconfig) eq $form->{gldate})
                             : ($::instance_conf->get_ir_changeable == 1),
  });
##print $form->parse_html_template('ir/_payments'); # parser
##print $form->parse_html_template('webdav/_list'); # parser

  $main::lxdebug->leave_sub();
}

sub mark_as_paid {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $main::auth->assert('vendor_invoice_edit');

  &mark_as_paid_common(\%myconfig,"ap");

  $main::lxdebug->leave_sub();
}

sub update {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $main::auth->assert('vendor_invoice_edit');

  &check_name('vendor');

  if (!$form->{forex}) {        # read exchangerate from input field (not hidden)
    $form->{exchangerate} = $form->parse_amount(\%myconfig, $form->{exchangerate});
  }
  $form->{forex}        = $form->check_exchangerate(\%myconfig, $form->{currency}, $form->{invdate}, 'sell');
  $form->{exchangerate} = $form->{forex} if $form->{forex};

  for my $i (1 .. $form->{paidaccounts}) {
    next unless $form->{"paid_$i"};
    map { $form->{"${_}_$i"} = $form->parse_amount(\%myconfig, $form->{"${_}_$i"}) } qw(paid exchangerate);
    $form->{"forex_$i"}        = $form->check_exchangerate(\%myconfig, $form->{currency}, $form->{"datepaid_$i"}, 'sell');
    $form->{"exchangerate_$i"} = $form->{"forex_$i"} if $form->{"forex_$i"};
  }

  my $i            = $form->{rowcount};
  my $exchangerate = ($form->{exchangerate} * 1) || 1;

  if (   ($form->{"partnumber_$i"} eq "")
      && ($form->{"description_$i"} eq "")
      && ($form->{"partsgroup_$i"} eq "")) {
    $form->{creditremaining} += ($form->{oldinvtotal} - $form->{oldtotalpaid});
    &check_form;

  } else {

    IR->retrieve_item(\%myconfig, \%$form);

    my $rows = scalar @{ $form->{item_list} };

    if ($rows) {
      $form->{"qty_$i"} = 1 unless $form->parse_amount(\%myconfig, $form->{"qty_$i"});

      if ($rows > 1) {

        select_item(mode => 'IR');
        ::end_of_request();

      } else {

        # override sellprice if there is one entered
        my $sellprice = $form->parse_amount(\%myconfig, $form->{"sellprice_$i"});

        # ergaenzung fuer bug 736 Lieferanten-Rabatt auch in Einkaufsrechnungen vorbelegen jb
        $form->{"discount_$i"} = $form->format_amount(\%myconfig, $form->{vendor_discount} * 100 );
        map { $form->{item_list}[$i]{$_} =~ s/\"/&quot;/g } qw(partnumber description unit);
        map { $form->{"${_}_$i"} = $form->{item_list}[0]{$_} } keys %{ $form->{item_list}[0] };

        $form->{"marge_price_factor_$i"} = $form->{item_list}->[0]->{price_factor};

        ($sellprice || $form->{"sellprice_$i"}) =~ /\.(\d+)/;
        my $dec_qty       = length $1;
        my $decimalplaces = max 2, $dec_qty;

        if ($sellprice) {
          $form->{"sellprice_$i"} = $sellprice;
        } else {
          # if there is an exchange rate adjust sellprice
          $form->{"sellprice_$i"} /= $exchangerate;
        }

        my $amount                   = $form->{"sellprice_$i"} * $form->{"qty_$i"} * (1 - $form->{"discount_$i"} / 100);
        $form->{creditremaining} -= $amount;
        $form->{"sellprice_$i"}   = $form->format_amount(\%myconfig, $form->{"sellprice_$i"}, $decimalplaces);
        $form->{"qty_$i"}         = $form->format_amount(\%myconfig, $form->{"qty_$i"},       $dec_qty);
      }

      &display_form;

    } else {

      # ok, so this is a new part
      # ask if it is a part or service item

      if (   $form->{"partsgroup_$i"}
          && ($form->{"partsnumber_$i"} eq "")
          && ($form->{"description_$i"} eq "")) {
        $form->{rowcount}--;
        $form->{"discount_$i"} = "";
        display_form();

      } else {
        $form->{"id_$i"}   = 0;
        new_item();
      }
    }
  }
  $main::lxdebug->leave_sub();
}

sub storno {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('vendor_invoice_edit');

  if ($form->{storno}) {
    $form->error($locale->text('Cannot storno storno invoice!'));
  }

  if (IS->has_storno(\%myconfig, $form, "ap")) {
    $form->error($locale->text("Invoice has already been storno'd!"));
  }

  $form->error($locale->text('Cannot post storno for a closed period!'))
    if ( $form->date_closed($form->{invdate}, \%myconfig));

  my $employee_id = $form->{employee_id};
  invoice_links();
  prepare_invoice();
  relink_accounts();

  # Payments must not be recorded for the new storno invoice.
  $form->{paidaccounts} = 0;
  map { my $key = $_; delete $form->{$key} if grep { $key =~ /^$_/ } qw(datepaid_ gldate_ acc_trans_id_ source_ memo_ paid_ exchangerate_ AR_paid_) } keys %{ $form };

  # saving the history
  if(!exists $form->{addition} && $form->{id} ne "") {
    $form->{snumbers} = qq|invnumber_| . $form->{invnumber};
    $form->{addition} = "CANCELED";
    $form->save_history;
  }
  # /saving the history

  $form->{storno_id} = $form->{id};
  $form->{storno} = 1;
  $form->{id} = "";
  $form->{invnumber} = "Storno zu " . $form->{invnumber};
  $form->{rowcount}++;
  $form->{employee_id} = $employee_id;
  post();
  $main::lxdebug->leave_sub();

}

sub use_as_new {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $main::auth->assert('vendor_invoice_edit');

  map { delete $form->{$_} } qw(printed emailed queued invnumber invdate deliverydate id datepaid_1 gldate_1 acc_trans_id_1 source_1 memo_1 paid_1 exchangerate_1 AP_paid_1 storno);
  $form->{paidaccounts} = 1;
  $form->{rowcount}--;
  $form->{invdate} = $form->current_date(\%myconfig);
  &display_form;

  $main::lxdebug->leave_sub();
}

sub post_payment {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('vendor_invoice_edit');

  $form->{defaultcurrency} = $form->get_default_currency(\%myconfig);
  for my $i (1 .. $form->{paidaccounts}) {
    if ($form->{"paid_$i"}) {
      my $datepaid = $form->datetonum($form->{"datepaid_$i"}, \%myconfig);

      $form->isblank("datepaid_$i", $locale->text('Payment date missing!'));

      $form->error($locale->text('Cannot post payment for a closed period!'))
        if ($form->date_closed($form->{"datepaid_$i"}, \%myconfig));

      if ($form->{currency} ne $form->{defaultcurrency}) {
#        $form->{"exchangerate_$i"} = $form->{exchangerate} if ($invdate == $datepaid); # invdate isn't set here
        $form->isblank("exchangerate_$i", $locale->text('Exchangerate for payment missing!'));
      }
    }
  }

  ($form->{AP})      = split /--/, $form->{AP};
  ($form->{AP_paid}) = split /--/, $form->{AP_paid};
  if (IR->post_payment(\%myconfig, \%$form)){
    if (!exists $form->{addition} && $form->{id} ne "") {
      # saving the history
      $form->{snumbers} = qq|invnumber_| . $form->{invnumber};
      $form->{addition} = "PAYMENT POSTED";
      $form->{what_done} = $form->{currency} . qq| | . $form->{paid} . qq| | . $locale->text("POSTED");
      $form->save_history;
      # /saving the history
    }

    $form->redirect($locale->text('Payment posted!'));
  }

  $form->error($locale->text('Cannot post payment!'));

  $main::lxdebug->leave_sub();
}

sub _max_datepaid {
  my $form  =  $main::form;

  my @dates = sort { $b->[1] cmp $a->[1] }
              map  { [ $_, $main::locale->reformat_date(\%main::myconfig, $_, 'yyyy-mm-dd') ] }
              grep { $_ }
              map  { $form->{"datepaid_${_}"} }
              (1..$form->{rowcount});

  return @dates ? $dates[0]->[0] : undef;
}


sub post {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('vendor_invoice_edit');

  $form->{defaultcurrency} = $form->get_default_currency(\%myconfig);

  $form->isblank("invdate",   $locale->text('Invoice Date missing!'));
  $form->isblank("vendor",    $locale->text('Vendor missing!'));
  $form->isblank("invnumber", $locale->text('Invnumber missing!'));

  $form->{invnumber} =~ s/^\s*//g;
  $form->{invnumber} =~ s/\s*$//g;

  # if the vendor changed get new values
  if (&check_name('vendor')) {
    &update;
    ::end_of_request();
  }

  if ($myconfig{mandatory_departments} && !$form->{department_id}) {
    $form->{saved_message} = $::locale->text('You have to specify a department.');
    update();
    exit;
  }

  remove_emptied_rows();
  &validate_items;

  my $closedto     = $form->datetonum($form->{closedto}, \%myconfig);
  my $invdate      = $form->datetonum($form->{invdate},  \%myconfig);
  my $max_datepaid = _max_datepaid();

  $form->error($locale->text('Cannot post transaction above the maximum future booking date!'))
    if ($form->date_max_future($invdate, \%myconfig));
  $form->error($locale->text('Cannot post invoice for a closed period!')) if $max_datepaid && $form->date_closed($max_datepaid, \%myconfig);

  $form->isblank("exchangerate", $locale->text('Exchangerate missing!'))
    if ($form->{currency} ne $form->{defaultcurrency});

  my $i;
  for $i (1 .. $form->{paidaccounts}) {
    if ($form->parse_amount(\%myconfig, $form->{"paid_$i"})) {
      my $datepaid = $form->datetonum($form->{"datepaid_$i"}, \%myconfig);

      $form->isblank("datepaid_$i", $locale->text('Payment date missing!'));

      $form->error($locale->text('Cannot post payment for a closed period!'))
        if ($form->date_closed($form->{"datepaid_$i"}, \%myconfig));

      if ($form->{currency} ne $form->{defaultcurrency}) {
        $form->{"exchangerate_$i"} = $form->{exchangerate}
          if ($invdate == $datepaid);
        $form->isblank("exchangerate_$i",
                       $locale->text('Exchangerate for payment missing!'));
      }
    }
  }

  ($form->{AP})      = split /--/, $form->{AP};
  ($form->{AP_paid}) = split /--/, $form->{AP_paid};
  $form->{storno}  ||= 0;

  $form->{id} = 0 if $form->{postasnew};


  relink_accounts();
  if (IR->post_invoice(\%myconfig, \%$form)){
    # saving the history
    if(!exists $form->{addition} && $form->{id} ne "") {
      $form->{snumbers} = qq|invnumber_| . $form->{invnumber};
      $form->{addition} = "POSTED";
      #$form->{what_done} = $locale->text("Rechnungsnummer") . qq| | . $form->{invnumber};
      $form->save_history;
    }
    # /saving the history
    remove_draft() if $form->{remove_draft};
    $form->redirect(  $locale->text('Invoice')
                  . " $form->{invnumber} "
                  . $locale->text('posted!'));
  }
  $form->error($locale->text('Cannot post invoice!'));

  $main::lxdebug->leave_sub();
}

sub delete {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my $locale   = $main::locale;

  $main::auth->assert('vendor_invoice_edit');

  $form->header;
  print qq|
<form method=post action=$form->{script}>
|;

  # delete action variable
  map { delete $form->{$_} } qw(action header);

  foreach my $key (keys %$form) {
    next if (($key eq 'login') || ($key eq 'password') || ('' ne ref $form->{$key}));
    $form->{$key} =~ s/\"/&quot;/g;
    print qq|<input type=hidden name=$key value="$form->{$key}">\n|;
  }

  print qq|
<h2 class=confirm>| . $locale->text('Confirm!') . qq|</h2>

<h4>|
    . $locale->text('Are you sure you want to delete Invoice Number')
    . qq| $form->{invnumber}</h4>
<p>
<input name=action class=submit type=submit value="|
    . $locale->text('Yes') . qq|">
</form>
|;

  $main::lxdebug->leave_sub();
}

sub yes {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('vendor_invoice_edit');

  if (IR->delete_invoice(\%myconfig, \%$form)) {
    # saving the history
    if(!exists $form->{addition}) {
      $form->{snumbers} = qq|invnumber_| . $form->{invnumber};
      $form->{addition} = "DELETED";
      $form->save_history;
    }
    # /saving the history
    $form->redirect($locale->text('Invoice deleted!'));
  }
  $form->error($locale->text('Cannot delete invoice!'));

  $main::lxdebug->leave_sub();
}

sub get_duedate_vendor {
  $::lxdebug->enter_sub;

  my $result = IR->get_duedate(
    vendor_id => $::form->{vendor_id},
    invdate   => $::form->{invdate},
    default   => $::form->{old_duedate},
  );

  print $::form->ajax_response_header, $result;
  $::lxdebug->leave_sub;
}
