#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
# Copyright (c) 2001
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
# Accounts Receivables
#
#======================================================================

use POSIX qw(strftime);
use List::Util qw(sum first max);

use SL::AR;
use SL::FU;
use SL::IS;
use SL::PE;
use SL::DB::Default;
use SL::ReportGenerator;

require "bin/mozilla/arap.pl";
require "bin/mozilla/common.pl";
require "bin/mozilla/drafts.pl";
require "bin/mozilla/reportgenerator.pl";

use strict;
#use warnings;

# this is for our long dates
# $locale->text('January')
# $locale->text('February')
# $locale->text('March')
# $locale->text('April')
# $locale->text('May ')
# $locale->text('June')
# $locale->text('July')
# $locale->text('August')
# $locale->text('September')
# $locale->text('October')
# $locale->text('November')
# $locale->text('December')

# this is for our short month
# $locale->text('Jan')
# $locale->text('Feb')
# $locale->text('Mar')
# $locale->text('Apr')
# $locale->text('May')
# $locale->text('Jun')
# $locale->text('Jul')
# $locale->text('Aug')
# $locale->text('Sep')
# $locale->text('Oct')
# $locale->text('Nov')
# $locale->text('Dec')

sub add {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  return $main::lxdebug->leave_sub() if (load_draft_maybe());

  # saving the history
  if(!exists $form->{addition} && ($form->{id} ne "")) {
    $form->{snumbers} = qq|invnumber_| . $form->{invnumber};
    $form->{addition} = "ADDED";
    $form->save_history;
  }
  # /saving the history

  $form->{title}    = "Add";
  $form->{callback} = "ar.pl?action=add&DONT_LOAD_DRAFT=1" unless $form->{callback};

  AR->get_transdate(\%myconfig, $form);
  $form->{initial_transdate} = $form->{transdate};
  create_links(dont_save => 1);
  $form->{transdate} = $form->{initial_transdate};
  &display_form;
  $main::lxdebug->leave_sub();
}

sub edit {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;

  # show history button
  $form->{javascript} = qq|<script type="text/javascript" src="js/show_history.js"></script>|;
  #/show hhistory button
  $form->{javascript} .= qq|<script type="text/javascript" src="js/common.js"></script>|;
  $form->{title} = "Edit";

  create_links();
  &display_form;

  $main::lxdebug->leave_sub();
}

sub display_form {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;

  &form_header;
  &form_footer;

  $main::lxdebug->leave_sub();
}

sub create_links {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my %params   = @_;
  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $form->create_links("AR", \%myconfig, "customer");

  my %saved;
  if (!$params{dont_save}) {
    %saved = map { ($_ => $form->{$_}) } qw(direct_debit id taxincluded);
    $saved{duedate} = $form->{duedate} if $form->{duedate};
  }

  IS->get_customer(\%myconfig, \%$form);

  $form->{$_}          = $saved{$_} for keys %saved;
  $form->{oldcustomer} = "$form->{customer}--$form->{customer_id}";
  $form->{rowcount}    = 1;

  # currencies
  $form->{defaultcurrency} = $form->get_default_currency(\%myconfig);

  map { $form->{selectcurrency} .= "<option>$_\n" } $form->get_all_currencies(\%myconfig);

  # customers
  if (@{ $form->{all_customer} || [] }) {
    $form->{customer} = "$form->{customer}--$form->{customer_id}";
    map { $form->{selectcustomer} .= "<option>$_->{name}--$_->{id}\n" }
      (@{ $form->{all_customer} });
  }

  # departments
  if (@{ $form->{all_departments} || [] }) {
    $form->{selectdepartment} = "<option>\n";
    $form->{department}       = "$form->{department}--$form->{department_id}";

    map {
      $form->{selectdepartment} .=
        "<option>$_->{description}--$_->{id}\n"
    } (@{ $form->{all_departments} || [] });
  }

  $form->{employee} = "$form->{employee}--$form->{employee_id}";

  # sales staff
  if (@{ $form->{all_employees} || [] }) {
    $form->{selectemployee} = "";
    map { $form->{selectemployee} .= "<option>$_->{name}--$_->{id}\n" }
      (@{ $form->{all_employees} || [] });
  }

  # build the popup menus
  $form->{taxincluded} = ($form->{id}) ? $form->{taxincluded} : "checked";

  AR->setup_form($form);

  $form->{locked} =
    ($form->datetonum($form->{transdate}, \%myconfig) <=
     $form->datetonum($form->{closedto}, \%myconfig));

  $main::lxdebug->leave_sub();
}

sub form_header {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $::request->{cgi};

  my ($title, $readonly, $exchangerate, $rows);
  my ($notes, $department, $customer, $employee, $amount, $project);
  my ($ARselected);


  $title = $form->{title};
  # $locale->text('Add Accounts Receivables Transaction')
  # $locale->text('Edit Accounts Receivables Transaction')
  $form->{title} = $locale->text("$title Accounts Receivables Transaction");

  $form->{javascript} = qq|<script type="text/javascript">
  <!--
  function setTaxkey(accno, row) {
    var taxkey = accno.options[accno.selectedIndex].value;
    var reg = /--([0-9]*)/;
    var found = reg.exec(taxkey);
    var index = found[1];
    index = parseInt(index);
    var tax = 'taxchart_' + row;
    for (var i = 0; i < document.getElementById(tax).options.length; ++i) {
      var reg2 = new RegExp("^"+ index, "");
      if (reg2.exec(document.getElementById(tax).options[i].value)) {
        document.getElementById(tax).options[i].selected = true;
        break;
      }
    }
  };
  //-->
  </script>|;
  # show history button js
  $form->{javascript} .= qq|<script type="text/javascript" src="js/show_history.js"></script>|;
  #/show history button js
  $readonly = ($form->{id}) ? "readonly" : "";

  $form->{radier} = ($::instance_conf->get_ar_changeable == 2)
                      ? ($form->current_date(\%myconfig) eq $form->{gldate})
                      : ($::instance_conf->get_ar_changeable == 1);
  $readonly = ($form->{radier}) ? "" : $readonly;

  # set option selected
  foreach my $item (qw(customer currency department employee)) {
    $form->{"select$item"} =~ s/ selected//;
    $form->{"select$item"} =~ s/option>\Q$form->{$item}\E/option selected>$form->{$item}/;
  }

  $form->{forex}        = $form->check_exchangerate( \%myconfig, $form->{currency}, $form->{transdate}, 'buy');
  $form->{exchangerate} = $form->{forex} if $form->{forex};

  $rows = max 2, $form->numtextrows($form->{notes}, 50);

  my @old_project_ids = grep { $_ } map { $form->{"project_id_$_"} } 1..$form->{rowcount};

  $form->get_lists("projects"  => { "key"       => "ALL_PROJECTS",
                                    "all"       => 0,
                                    "old_id"    => \@old_project_ids },
                   "charts"    => { "key"       => "ALL_CHARTS",
                                    "transdate" => $form->{transdate} },
                   "taxcharts" => { "key"       => "ALL_TAXCHARTS",
                                    "module"    => "AR" },);

  $_->{link_split} = { map { $_ => 1 } split/:/, $_->{link} } for @{ $form->{ALL_CHARTS} };

  my %project_labels = map { $_->{id} => $_->{projectnumber} } @{ $form->{"ALL_PROJECTS"} };

  my (@AR_amount_values);
  my (@AR_values);
  my (@AR_paid_values);
  my %chart_labels;
  my %charts;
  my $taxchart_init;

  foreach my $item (@{ $form->{ALL_CHARTS} }) {
    if ($item->{link_split}{AR_amount}) {
      $taxchart_init = $item->{tax_id} if ($taxchart_init eq "");
      my $key = "$item->{accno}--$item->{tax_id}";
      push(@AR_amount_values, $key);
    } elsif ($item->{link_split}{AR}) {
      push(@AR_values, $item->{accno});
    } elsif ($item->{link_split}{AR_paid}) {
      push(@AR_paid_values, $item->{accno});
    }

    # weirdness for AR_amount
    $chart_labels{$item->{accno}} = "$item->{accno}--$item->{description}";
    $chart_labels{"$item->{accno}--$item->{tax_id}"} = "$item->{accno}--$item->{description}";

    $charts{$item->{accno}} = $item;
  }

  my %taxchart_labels = ();
  my @taxchart_values = ();
  my %taxcharts = ();
  foreach my $item (@{ $form->{ALL_TAXCHARTS} }) {
    my $key = "$item->{id}--$item->{rate}";
    $taxchart_init = $key if ($taxchart_init eq $item->{id});
    push(@taxchart_values, $key);
    $taxchart_labels{$key} = "$item->{taxdescription} " . ($item->{rate} * 100) . ' %';
    $taxcharts{$item->{id}} = $item;
  }

  my $follow_up_vc         =  $form->{customer};
  $follow_up_vc            =~ s/--.*?//;
  my $follow_up_trans_info =  "$form->{invnumber} ($follow_up_vc)";

  $form->{javascript} .=
    qq|<script type="text/javascript" src="js/show_vc_details.js"></script>| .
    qq|<script type="text/javascript" src="js/follow_up.js"></script>|;

#  $amount  = $locale->text('Amount');
#  $project = $locale->text('Project');

  my @transactions;
  for my $i (1 .. $form->{rowcount}) {
    my $transaction = {
      amount     => $form->{"amount_$i"},
      tax        => $form->{"tax_$i"},
      project_id => ($i==$form->{rowcount}) ? $form->{globalproject_id} : $form->{"project_id_$i"},
    };

    my $selected_accno_full;
    my ($accno_row) = split(/--/, $form->{"AR_amount_$i"});
    my $item = $charts{$accno_row};
    $selected_accno_full = "$item->{accno}--$item->{tax_id}";

    my $selected_taxchart = $form->{"taxchart_$i"};
    my ($selected_accno, $selected_tax_id) = split(/--/, $selected_accno_full);
    my ($previous_accno, $previous_tax_id) = split(/--/, $form->{"previous_AR_amount_$i"});

    if ($previous_accno &&
        ($previous_accno eq $selected_accno) &&
        ($previous_tax_id ne $selected_tax_id)) {
      my $item = $taxcharts{$selected_tax_id};
      $selected_taxchart = "$item->{id}--$item->{rate}";
    }

    if (!$form->{"taxchart_$i"}) {
      if ($form->{"AR_amount_$i"} =~ m/.--./) {
        $selected_taxchart = join '--', map { ($_->{id}, $_->{rate}) } first { $_->{id} == $item->{tax_id} } @{ $form->{ALL_TAXCHARTS} };
      } else {
        $selected_taxchart = $taxchart_init;
      }
    }

    $transaction->{selectAR_amount} =
      NTI($cgi->popup_menu('-name' => "AR_amount_$i",
                           '-id' => "AR_amount_$i",
                           '-style' => 'width:400px',
                           '-onChange' => "setTaxkey(this, $i)",
                           '-values' => \@AR_amount_values,
                           '-labels' => \%chart_labels,
                           '-default' => $selected_accno_full))
      . $cgi->hidden('-name' => "previous_AR_amount_$i",
                     '-default' => $selected_accno_full);

    $transaction->{taxchart} =
      NTI($cgi->popup_menu('-name' => "taxchart_$i",
                           '-id' => "taxchart_$i",
                           '-style' => 'width:200px',
                           '-values' => \@taxchart_values,
                           '-labels' => \%taxchart_labels,
                           '-default' => $selected_taxchart));

    push @transactions, $transaction;
  }

  $form->{invtotal_unformatted} = $form->{invtotal};

  $ARselected =
    NTI($cgi->popup_menu('-name' => "ARselected", '-id' => "ARselected",
                         '-style' => 'width:400px',
                         '-values' => \@AR_values, '-labels' => \%chart_labels,
                         '-default' => $form->{ARselected}));


  $form->{paidaccounts}++ if ($form->{"paid_$form->{paidaccounts}"});

  my $now = $form->current_date(\%myconfig);

  my @payments;
  for my $i (1 .. $form->{paidaccounts}) {
    my $payment = {
      paid             => $form->{"paid_$i"},
      exchangerate     => $form->{"exchangerate_$i"} || '',
      gldate           => $form->{"gldate_$i"},
      acc_trans_id     => $form->{"acc_trans_id_$i"},
      source           => $form->{"source_$i"},
      memo             => $form->{"memo_$i"},
      AR_paid          => $form->{"AR_paid_$i"},
      forex            => $form->{"forex_$i"},
      datepaid         => $form->{"datepaid_$i"},
      paid_project_id  => $form->{"paid_project_id_$i"},
      gldate           => $form->{"gldate_$i"},
    };

    $payment->{selectAR_paid} =
      NTI($cgi->popup_menu('-name' => "AR_paid_$i",
                           '-id' => "AR_paid_$i",
                           '-values' => \@AR_paid_values,
                           '-labels' => \%chart_labels,
                           '-default' => $payment->{AR_paid}));



    $payment->{changeable} =
        SL::DB::Default->get->payments_changeable == 0 ? !$payment->{acc_trans_id} # never
      : SL::DB::Default->get->payments_changeable == 2 ? $payment->{gldate} eq '' || $payment->{gldate} eq $now
      :                                                           1;

    push @payments, $payment;
  }

  $form->{totalpaid} = sum map { $_->{paid} } @payments;

  $form->header;
  print $::form->parse_html_template('ar/form_header', {
    paid_missing         => $::form->{invtotal} - $::form->{totalpaid},
    show_exch            => ($::form->{defaultcurrency} && ($::form->{currency} ne $::form->{defaultcurrency})),
    payments             => \@payments,
    transactions         => \@transactions,
    project_labels       => \%project_labels,
    rows                 => $rows,
    ARselected           => $ARselected,
    title_str            => $title,
    follow_up_trans_info => $follow_up_trans_info,
  });

  $main::lxdebug->leave_sub();
}

sub form_footer {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $::request->{cgi};

  if ( $form->{id} ) {
    my $follow_ups = FU->follow_ups('trans_id' => $form->{id});
    if ( @{ $follow_ups} ) {
      $form->{follow_up_length} = scalar(@{$follow_ups});
      $form->{follow_up_due_length} = sum(map({ $_->{due} * 1 } @{ $follow_ups }));
    }
  }

  my $transdate = $form->datetonum($form->{transdate}, \%myconfig);
  my $closedto  = $form->datetonum($form->{closedto},  \%myconfig);

  $form->{is_closed} = $transdate <= $closedto;

  # ToDO: - insert a global check for stornos, so that a storno is only possible a limited time after saving it
  $form->{show_storno_button} =
    $form->{id} &&
    !IS->has_storno(\%myconfig, $form, 'ar') &&
    !IS->is_storno(\%myconfig, $form, 'ar') &&
    ($form->{totalpaid} == 0 || $form->{totalpaid} eq "");

  $form->{show_mark_as_paid_button} = $form->{id} && $::instance_conf->get_ar_show_mark_as_paid();

  print $::form->parse_html_template('ar/form_footer');

  $main::lxdebug->leave_sub();
}

sub mark_as_paid {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  &mark_as_paid_common(\%myconfig,"ar");

  $main::lxdebug->leave_sub();
}

sub update {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  my $display = shift;

  my ($totaltax, $exchangerate);

  $form->{invtotal} = 0;

  delete @{ $form }{ grep { m/^tax_\d+$/ } keys %{ $form } };

  map { $form->{$_} = $form->parse_amount(\%myconfig, $form->{$_}) }
    qw(exchangerate creditlimit creditremaining);

  my @flds  = qw(amount AR_amount projectnumber oldprojectnumber project_id);
  my $count = 0;
  my @a     = ();

  for my $i (1 .. $form->{rowcount}) {
    $form->{"amount_$i"} = $form->parse_amount(\%myconfig, $form->{"amount_$i"});
    $form->{"tax_$i"} = $form->parse_amount(\%myconfig, $form->{"tax_$i"});
    if ($form->{"amount_$i"}) {
      push @a, {};
      my $j = $#a;
      my ($taxkey, $rate) = split(/--/, $form->{"taxchart_$i"});
      if ($taxkey > 1) {
        if ($form->{taxincluded}) {
          $form->{"tax_$i"} = $form->{"amount_$i"} / ($rate + 1) * $rate;
        } else {
          $form->{"tax_$i"} = $form->{"amount_$i"} * $rate;
        }
      } else {
        $form->{"tax_$i"} = 0;
      }
      $form->{"tax_$i"} = $form->round_amount($form->{"tax_$i"}, 2);

      $totaltax += $form->{"tax_$i"};
      map { $a[$j]->{$_} = $form->{"${_}_$i"} } @flds;
      $count++;
    }
  }

  $form->redo_rows(\@flds, \@a, $count, $form->{rowcount});
  $form->{rowcount} = $count + 1;
  map { $form->{invtotal} += $form->{"amount_$_"} } (1 .. $form->{rowcount});

  $form->{forex}        = $form->check_exchangerate( \%myconfig, $form->{currency}, $form->{transdate}, 'buy');
  $form->{exchangerate} = $form->{forex} if $form->{forex};

  $form->{invdate} = $form->{transdate};

  $form->{invdate} = $form->{transdate};

  my %saved_variables = map +( $_ => $form->{$_} ), qw(AR AR_amount_1 taxchart_1 customer_id notes);

  &check_name("customer");

  $form->{AR} = $saved_variables{AR};
  if ($saved_variables{AR_amount_1} =~ m/.--./) {
    map { $form->{$_} = $saved_variables{$_} } qw(AR_amount_1 taxchart_1);
  } else {
    delete $form->{taxchart_1};
  }

  $form->{invtotal} =
    ($form->{taxincluded}) ? $form->{invtotal} : $form->{invtotal} + $totaltax;

  for my $i (1 .. $form->{paidaccounts}) {
    if ($form->parse_amount(\%myconfig, $form->{"paid_$i"})) {
      map {
        $form->{"${_}_$i"} =
          $form->parse_amount(\%myconfig, $form->{"${_}_$i"})
      } qw(paid exchangerate);

      $form->{totalpaid} += $form->{"paid_$i"};

      $form->{"forex_$i"}        = $form->check_exchangerate( \%myconfig, $form->{currency}, $form->{"datepaid_$i"}, 'buy');
      $form->{"exchangerate_$i"} = $form->{"forex_$i"} if $form->{"forex_$i"};
    }
  }

  $form->{creditremaining} -=
    ($form->{invtotal} - $form->{totalpaid} + $form->{oldtotalpaid} -
     $form->{oldinvtotal});
  $form->{oldinvtotal}  = $form->{invtotal};
  $form->{oldtotalpaid} = $form->{totalpaid};

  &display_form;

  $main::lxdebug->leave_sub();
}

#
# ToDO: fix $closedto and $invdate
#
sub post_payment {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $form->{defaultcurrency} = $form->get_default_currency(\%myconfig);

  my $invdate = $form->datetonum($form->{transdate}, \%myconfig);

  for my $i (1 .. $form->{paidaccounts}) {

    if ($form->parse_amount(\%myconfig, $form->{"paid_$i"})) {
      my $datepaid = $form->datetonum($form->{"datepaid_$i"}, \%myconfig);

      $form->isblank("datepaid_$i", $locale->text('Payment date missing!'));

      $form->error($locale->text('Cannot post payment for a closed period!')) if ($form->date_closed($form->{"datepaid_$i"}, \%myconfig));

      if ($form->{defaultcurrency} && ($form->{currency} ne $form->{defaultcurrency})) {
#        $form->{"exchangerate_$i"} = $form->{exchangerate} if ($invdate == $datepaid);
        $form->isblank("exchangerate_$i", $locale->text('Exchangerate for payment missing!'));
      }
    }
  }

  ($form->{AR})      = split /--/, $form->{AR};
  ($form->{AR_paid}) = split /--/, $form->{AR_paid};
  $form->redirect($locale->text('Payment posted!')) if (AR->post_payment(\%myconfig, \%$form));
  $form->error($locale->text('Cannot post payment!'));

  $main::lxdebug->leave_sub();
}

sub _post {

  $main::auth->assert('general_ledger');

  my $form     = $main::form;

  # inline post
  post(1);
}

sub post {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  my ($inline) = @_;

  my ($datepaid);

  # check if there is an invoice number, invoice and due date
  $form->isblank("transdate", $locale->text('Invoice Date missing!'));
  $form->isblank("duedate",   $locale->text('Due Date missing!'));
  $form->isblank("customer",  $locale->text('Customer missing!'));

  if ($myconfig{mandatory_departments} && !$form->{department}) {
    $form->{saved_message} = $::locale->text('You have to specify a department.');
    update();
    exit;
  }

  my $closedto  = $form->datetonum($form->{closedto},  \%myconfig);
  my $transdate = $form->datetonum($form->{transdate}, \%myconfig);

  $form->error($locale->text('Cannot post transaction above the maximum future booking date!'))
    if ($form->date_max_future($transdate, \%myconfig));
  $form->error($locale->text('Cannot post transaction for a closed period!')) if ($form->date_closed($form->{"transdate"}, \%myconfig));

  $form->error($locale->text('Zero amount posting!'))
    unless grep $_*1, map $form->parse_amount(\%myconfig, $form->{"amount_$_"}), 1..$form->{rowcount};

  $form->isblank("exchangerate", $locale->text('Exchangerate missing!'))
    if ($form->{defaultcurrency} && ($form->{currency} ne $form->{defaultcurrency}));

  delete($form->{AR});

  for my $i (1 .. $form->{paidaccounts}) {
    if ($form->parse_amount(\%myconfig, $form->{"paid_$i"})) {
      $datepaid = $form->datetonum($form->{"datepaid_$i"}, \%myconfig);

      $form->isblank("datepaid_$i", $locale->text('Payment date missing!'));

      $form->error($locale->text('Cannot post payment for a closed period!'))
        if ($form->date_closed($form->{"datepaid_$i"}, \%myconfig));

      if ($form->{defaultcurrency} && ($form->{currency} ne $form->{defaultcurrency})) {
        $form->{"exchangerate_$i"} = $form->{exchangerate} if ($transdate == $datepaid);
        $form->isblank("exchangerate_$i", $locale->text('Exchangerate for payment missing!'));
      }
    }
  }

  # if oldcustomer ne customer redo form
  my ($customer) = split /--/, $form->{customer};
  if ($form->{oldcustomer} ne "$customer--$form->{customer_id}") {
    update();
    ::end_of_request();
  }

  $form->{AR}{receivables} = $form->{ARselected};
  $form->{storno}          = 0;

  $form->{id} = 0 if $form->{postasnew};
  $form->error($locale->text('Cannot post transaction!')) unless AR->post_transaction(\%myconfig, \%$form);

  # saving the history
  if(!exists $form->{addition} && $form->{id} ne "") {
    $form->{snumbers} = "invnumber_$form->{invnumber}";
    $form->{addition} = "POSTED";
    $form->save_history;
  }
  # /saving the history
  remove_draft() if $form->{remove_draft};

  $form->redirect($locale->text('Transaction posted!')) unless $inline;

  $main::lxdebug->leave_sub();
}

sub post_as_new {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $form->{postasnew} = 1;
  # saving the history
  if(!exists $form->{addition} && $form->{id} ne "") {
    $form->{snumbers} = qq|invnumber_| . $form->{invnumber};
    $form->{addition} = "POSTED AS NEW";
    $form->save_history;
  }
  # /saving the history
  &post;

  $main::lxdebug->leave_sub();
}

sub use_as_new {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  map { delete $form->{$_} } qw(printed emailed queued invnumber invdate deliverydate id datepaid_1 gldate_1 acc_trans_id_1 source_1 memo_1 paid_1 exchangerate_1 AP_paid_1 storno);
  $form->{paidaccounts} = 1;
  $form->{rowcount}--;
  $form->{invdate} = $form->current_date(\%myconfig);
  &update;

  $main::lxdebug->leave_sub();
}

sub delete {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my $locale   = $main::locale;

  $form->{title} = $locale->text('Confirm!');

  $form->header;

  delete $form->{header};

  print qq|
<form method=post action=$form->{script}>
|;

  foreach my $key (keys %$form) {
    next if (($key eq 'login') || ($key eq 'password') || ('' ne ref $form->{$key}));
    $form->{$key} =~ s/\"/&quot;/g;
    print qq|<input type=hidden name=$key value="$form->{$key}">\n|;
  }

  print qq|
<h2 class=confirm>$form->{title}</h2>

<h4>|
    . $locale->text('Are you sure you want to delete Transaction')
    . qq| $form->{invnumber}</h4>

<input name=action class=submit type=submit value="|
    . $locale->text('Yes') . qq|">
</form>
|;

  $main::lxdebug->leave_sub();
}

sub yes {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  if (AR->delete_transaction(\%myconfig, \%$form)) {
    # saving the history
    if(!exists $form->{addition}) {
      $form->{snumbers} = qq|invnumber_| . $form->{invnumber};
      $form->{addition} = "DELETED";
      $form->save_history;
    }
    # /saving the history
    $form->redirect($locale->text('Transaction deleted!'));
  }
  $form->error($locale->text('Cannot delete transaction!'));

  $main::lxdebug->leave_sub();
}

sub search {
  $main::lxdebug->enter_sub();

  $main::auth->assert('invoice_edit');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $::request->{cgi};

  # setup customer selection
  $form->all_vc(\%myconfig, "customer", "AR");

  $form->{title}    = $locale->text('AR Transactions');

  # Auch in Rechnungsübersicht nach Kundentyp filtern - jan
  $form->get_lists("projects"       => { "key" => "ALL_PROJECTS", "all" => 1 },
                   "departments"    => "ALL_DEPARTMENTS",
                   "customers"      => "ALL_VC",
                   "business_types" => "ALL_BUSINESS_TYPES");
  $form->{ALL_EMPLOYEES} = SL::DB::Manager::Employee->get_all(query => [ deleted => 0 ]);
  $form->{SHOW_BUSINESS_TYPES} = scalar @{ $form->{ALL_BUSINESS_TYPES} } > 0;

  # constants and subs for template
  $form->{vc_keys}   = sub { "$_[0]->{name}--$_[0]->{id}" };

  $form->header;
  print $form->parse_html_template('ar/search', { %myconfig });

  $main::lxdebug->leave_sub();
}

sub create_subtotal_row {
  $main::lxdebug->enter_sub();

  my ($totals, $columns, $column_alignment, $subtotal_columns, $class) = @_;

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  my $row = { map { $_ => { 'data' => '', 'class' => $class, 'align' => $column_alignment->{$_}, } } @{ $columns } };

  map { $row->{$_}->{data} = $form->format_amount(\%myconfig, $totals->{$_}, 2) } @{ $subtotal_columns };

  $row->{tax}->{data} = $form->format_amount(\%myconfig, $totals->{amount} - $totals->{netamount}, 2);

  map { $totals->{$_} = 0 } @{ $subtotal_columns };

  $main::lxdebug->leave_sub();

  return $row;
}

sub ar_transactions {
  $main::lxdebug->enter_sub();

  $main::auth->assert('invoice_edit');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  my ($callback, $href, @columns);

  ($form->{customer}, $form->{customer_id}) = split(/--/, $form->{customer});

  report_generator_set_default_sort('transdate', 1);

  AR->ar_transactions(\%myconfig, \%$form);

  $form->{title} = $locale->text('AR Transactions');

  my $report = SL::ReportGenerator->new(\%myconfig, $form);

  @columns =
    qw(transdate id type invnumber ordnumber name netamount tax amount paid
       datepaid due duedate transaction_description notes salesman employee shippingpoint shipvia
       marge_total marge_percent globalprojectnumber customernumber country ustid taxzone payment_terms charts customertype);

  my @hidden_variables = map { "l_${_}" } @columns;
  push @hidden_variables, "l_subtotal", qw(open closed customer invnumber ordnumber transaction_description notes project_id transdatefrom transdateto employee_id salesman_id business_id);

  $href = build_std_url('action=ar_transactions', grep { $form->{$_} } @hidden_variables);

  my %column_defs = (
    'transdate'               => { 'text' => $locale->text('Date'), },
    'id'                      => { 'text' => $locale->text('ID'), },
    'type'                    => { 'text' => $locale->text('Type'), },
    'invnumber'               => { 'text' => $locale->text('Invoice'), },
    'ordnumber'               => { 'text' => $locale->text('Order'), },
    'name'                    => { 'text' => $locale->text('Customer'), },
    'netamount'               => { 'text' => $locale->text('Amount'), },
    'tax'                     => { 'text' => $locale->text('Tax'), },
    'amount'                  => { 'text' => $locale->text('Total'), },
    'paid'                    => { 'text' => $locale->text('Paid'), },
    'datepaid'                => { 'text' => $locale->text('Date Paid'), },
    'due'                     => { 'text' => $locale->text('Amount Due'), },
    'duedate'                 => { 'text' => $locale->text('Due Date'), },
    'transaction_description' => { 'text' => $locale->text('Transaction description'), },
    'notes'                   => { 'text' => $locale->text('Notes'), },
    'salesman'                => { 'text' => $locale->text('Salesperson'), },
    'employee'                => { 'text' => $locale->text('Employee'), },
    'shippingpoint'           => { 'text' => $locale->text('Shipping Point'), },
    'shipvia'                 => { 'text' => $locale->text('Ship via'), },
    'globalprojectnumber'     => { 'text' => $locale->text('Document Project Number'), },
    'marge_total'             => { 'text' => $locale->text('Ertrag'), },
    'marge_percent'           => { 'text' => $locale->text('Ertrag prozentual'), },
    'customernumber'          => { 'text' => $locale->text('Customer Number'), },
    'country'                 => { 'text' => $locale->text('Country'), },
    'ustid'                   => { 'text' => $locale->text('USt-IdNr.'), },
    'taxzone'                 => { 'text' => $locale->text('Steuersatz'), },
    'payment_terms'           => { 'text' => $locale->text('Payment Terms'), },
    'charts'                  => { 'text' => $locale->text('Buchungskonto'), },
    'customertype'            => { 'text' => $locale->text('Customer type'), },
  );

  foreach my $name (qw(id transdate duedate invnumber ordnumber name datepaid employee shippingpoint shipvia transaction_description)) {
    my $sortdir                 = $form->{sort} eq $name ? 1 - $form->{sortdir} : $form->{sortdir};
    $column_defs{$name}->{link} = $href . "&sort=$name&sortdir=$sortdir";
  }

  my %column_alignment = map { $_ => 'right' } qw(netamount tax amount paid due);

  $form->{"l_type"} = "Y";
  map { $column_defs{$_}->{visible} = $form->{"l_${_}"} ? 1 : 0 } @columns;

  $report->set_columns(%column_defs);
  $report->set_column_order(@columns);

  $report->set_export_options('ar_transactions', @hidden_variables, qw(sort sortdir));

  $report->set_sort_indicator($form->{sort}, $form->{sortdir});

  my @options;
  if ($form->{customer}) {
    push @options, $locale->text('Customer') . " : $form->{customer}";
  }
  if ($form->{department}) {
    my ($department) = split /--/, $form->{department};
    push @options, $locale->text('Department') . " : $department";
  }
  if ($form->{department_id}) {
    push @options, $locale->text('Department Id') . " : $form->{department_id}";
  }
  if ($form->{invnumber}) {
    push @options, $locale->text('Invoice Number') . " : $form->{invnumber}";
  }
  if ($form->{ordnumber}) {
    push @options, $locale->text('Order Number') . " : $form->{ordnumber}";
  }
  if ($form->{notes}) {
    push @options, $locale->text('Notes') . " : $form->{notes}";
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
  if ($form->{employee_id}) {
    my $employee = SL::DB::Employee->new(id => $form->{employee_id})->load;
    push @options, $locale->text('Employee') . ' : ' . $employee->name;
  }
  if ($form->{salesman_id}) {
    my $salesman = SL::DB::Employee->new(id => $form->{salesman_id})->load;
    push @options, $locale->text('Salesman') . ' : ' . $salesman->name;
  }
  if ($form->{closed}) {
    push @options, $locale->text('Closed');
  }

  $report->set_options('top_info_text'        => join("\n", @options),
                       'raw_bottom_info_text' => $form->parse_html_template('ar/ar_transactions_bottom'),
                       'output_format'        => 'HTML',
                       'title'                => $form->{title},
                       'attachment_basename'  => $locale->text('invoice_list') . strftime('_%Y%m%d', localtime time),
    );
  $report->set_options_from_form();
  $locale->set_numberformat_wo_thousands_separator(\%myconfig) if lc($report->{options}->{output_format}) eq 'csv';

  # add sort and escape callback, this one we use for the add sub
  $form->{callback} = $href .= "&sort=$form->{sort}";

  # escape callback for href
  $callback = $form->escape($href);

  my @subtotal_columns = qw(netamount amount paid due marge_total marge_percent);

  my %totals    = map { $_ => 0 } @subtotal_columns;
  my %subtotals = map { $_ => 0 } @subtotal_columns;

  my $idx = 0;

  foreach my $ar (@{ $form->{AR} }) {
    $ar->{tax} = $ar->{amount} - $ar->{netamount};
    $ar->{due} = $ar->{amount} - $ar->{paid};

    map { $subtotals{$_} += $ar->{$_};
          $totals{$_}    += $ar->{$_} } @subtotal_columns;

    $subtotals{marge_percent} = $subtotals{netamount} ? ($subtotals{marge_total} * 100 / $subtotals{netamount}) : 0;
    $totals{marge_percent}    = $totals{netamount}    ? ($totals{marge_total}    * 100 / $totals{netamount}   ) : 0;

    map { $ar->{$_} = $form->format_amount(\%myconfig, $ar->{$_}, 2) } qw(netamount tax amount paid due marge_total marge_percent);

    my $is_storno  = $ar->{storno} &&  $ar->{storno_id};
    my $has_storno = $ar->{storno} && !$ar->{storno_id};

    $ar->{type} =
      $has_storno       ? $locale->text("Invoice with Storno (abbreviation)") :
      $is_storno        ? $locale->text("Storno (one letter abbreviation)") :
      $ar->{amount} < 0 ? $locale->text("Credit note (one letter abbreviation)") :
      $ar->{invoice}    ? $locale->text("Invoice (one letter abbreviation)") :
                          $locale->text("AR Transaction (abbreviation)");

    my $row = { };

    foreach my $column (@columns) {
      $row->{$column} = {
        'data'  => $ar->{$column},
        'align' => $column_alignment{$column},
      };
    }

    $row->{invnumber}->{link} = build_std_url("script=" . ($ar->{invoice} ? 'is.pl' : 'ar.pl'), 'action=edit')
      . "&id=" . E($ar->{id}) . "&callback=${callback}";

    my $row_set = [ $row ];

    if (($form->{l_subtotal} eq 'Y')
        && (($idx == (scalar @{ $form->{AR} } - 1))
            || ($ar->{ $form->{sort} } ne $form->{AR}->[$idx + 1]->{ $form->{sort} }))) {
      push @{ $row_set }, create_subtotal_row(\%subtotals, \@columns, \%column_alignment, \@subtotal_columns, 'listsubtotal');
    }

    $report->add_data($row_set);

    $idx++;
  }

  $report->add_separator();
  $report->add_data(create_subtotal_row(\%totals, \@columns, \%column_alignment, \@subtotal_columns, 'listtotal'));

  $report->generate_with_headers();

  $main::lxdebug->leave_sub();
}

sub storno {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  # don't cancel cancelled transactions
  if (IS->has_storno(\%myconfig, $form, 'ar')) {
    $form->{title} = $locale->text("Cancel Accounts Receivables Transaction");
    $form->error($locale->text("Transaction has already been cancelled!"));
  }

  AR->storno($form, \%myconfig, $form->{id});

  # saving the history
  if(!exists $form->{addition} && $form->{id} ne "") {
    $form->{snumbers} = "ordnumber_$form->{ordnumber}";
    $form->{addition} = "STORNO";
    $form->save_history;
  }
  # /saving the history

  $form->redirect(sprintf $locale->text("Transaction %d cancelled."), $form->{storno_id});

  $main::lxdebug->leave_sub();
}

1;
