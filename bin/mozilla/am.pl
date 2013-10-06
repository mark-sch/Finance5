#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
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
# administration
#
#======================================================================

use utf8;

use SL::Auth;
use SL::Auth::PasswordPolicy;
use SL::AM;
use SL::CA;
use SL::Form;
use SL::User;
use SL::USTVA;
use SL::Iconv;
use SL::TODO;
use SL::DB::Printer;
use CGI;

require "bin/mozilla/common.pl";

use strict;

1;

# end of main

sub add      { call_sub("add_$main::form->{type}"); }
sub delete   { call_sub("delete_$main::form->{type}"); }
sub save     { call_sub("save_$main::form->{type}"); }
sub edit     { call_sub("edit_$main::form->{type}"); }
sub continue { call_sub($main::form->{"nextsub"}); }
sub save_as_new { call_sub("save_as_new_$main::form->{type}"); }

sub add_account {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $main::auth->assert('config');

  $form->{title}     = "Add";
  $form->{charttype} = "A";
  AM->get_account(\%myconfig, \%$form);

  $form->{callback} = "am.pl?action=list_account" unless $form->{callback};

  &account_header;
  &form_footer;

  $main::lxdebug->leave_sub();
}

sub edit_account {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $main::auth->assert('config');

  $form->{title} = "Edit";
  AM->get_account(\%myconfig, \%$form);

  foreach my $item (split(/:/, $form->{link})) {
    $form->{$item} = "checked";
  }

  &account_header;
  &form_footer;

  $main::lxdebug->leave_sub();
}

sub account_header {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  if ( $form->{action} eq 'edit_account') {
    $form->{account_exists} = '1';
  }

  $form->{title} = $locale->text("$form->{title} Account");

  $form->{"$form->{charttype}_checked"} = "checked";
  $form->{"$form->{category}_checked"}  = "checked";

  $form->{select_tax} = "";

  my @tax_report_pos = USTVA->report_variables({
      myconfig   => \%myconfig,
      form       => $form,
      type       => '',
      attribute  => 'position',
      calc       => '',
  });

  if (@{ $form->{TAXKEY} }) {
    foreach my $item (@{ $form->{TAXKEY} }) {
      $item->{rate} = $item->{rate} * 100 . '%';
    }

    # Fill in empty row for new Taxkey
    my $newtaxkey_ref = {
      id             => '',
      chart_id       => '',
      accno          => '',
      tax_id         => '',
      taxdescription => '',
      rate           => '',
      taxkey_id      => '',
      pos_ustva      => '',
      startdate      => $form->{account_exists} ? '' : DateTime->new(year => 1970, month => 1, day => 1)->to_lxoffice,
    };

    push @{ $form->{ACCOUNT_TAXKEYS} }, $newtaxkey_ref;

    my $i = 0;
    foreach my $taxkey_used (@{ $form->{ACCOUNT_TAXKEYS} } ) {

      # Fill in a runningnumber
      $form->{ACCOUNT_TAXKEYS}[$i]{runningnumber} = $i;

      # Fill in the Taxkeys as select options
      foreach my $item (@{ $form->{TAXKEY} }) {
        if ($item->{id} == $taxkey_used->{tax_id}) {
          $form->{ACCOUNT_TAXKEYS}[$i]{selecttaxkey} .=
            qq|<option value="$item->{id}" selected="selected">|
            . sprintf("%.2d", $item->{taxkey})
            . qq|. $item->{taxdescription} ($item->{rate}) |
            . $locale->text('Tax-o-matic Account')
            . qq|: $item->{chart_accno}\n|;
        }
        else {
          $form->{ACCOUNT_TAXKEYS}[$i]{selecttaxkey} .=
            qq|<option value="$item->{id}">|
            . sprintf("%.2d", $item->{taxkey})
            . qq|. $item->{taxdescription} ($item->{rate}) |
            . $locale->text('Tax-o-matic Account')
            . qq|: $item->{chart_accno}\n|;
        }

      }

      # Fill in the USTVA Numbers as select options
      foreach my $item ( '', sort({ $a cmp $b } @tax_report_pos) ) {
        if ($item eq ''){
          $form->{ACCOUNT_TAXKEYS}[$i]{select_tax} .= qq|<option value="" selected="selected">-\n|;
        }
        elsif ( $item eq $taxkey_used->{pos_ustva} ) {
          $form->{ACCOUNT_TAXKEYS}[$i]{select_tax} .= qq|<option value="$item" selected="selected">$item\n|;
        }
        else {
          $form->{ACCOUNT_TAXKEYS}[$i]{select_tax} .= qq|<option value="$item">$item\n|;
        }

      }

      $i++;
    }
  }

  # Newaccount Folgekonto
  if (@{ $form->{NEWACCOUNT} || [] }) {
    if (!$form->{new_chart_valid}) {
      $form->{selectnewaccount} = qq|<option value=""> |. $locale->text('None') .q|</option>|;
    }
    foreach my $item (@{ $form->{NEWACCOUNT} }) {
      if ($item->{id} == $form->{new_chart_id}) {
        $form->{selectnewaccount} .=
          qq|<option value="$item->{id}" selected>$item->{accno}--$item->{description}</option>|;
      } elsif (!$form->{new_chart_valid}) {
        $form->{selectnewaccount} .=
          qq|<option value="$item->{id}">$item->{accno}--$item->{description}</option>|;
      }

    }
  }

  my $select_eur = q|<option value=""> |. $locale->text('None') .q|</option>\n|;
  my %eur = (
          1  => "Umsatzerlöse",
          2  => "sonstige Erlöse",
          3  => "Privatanteile",
          4  => "Zinserträge",
          5  => "Ausserordentliche Erträge",
          6  => "Vereinnahmte Umsatzst.",
          7  => "Umsatzsteuererstattungen",
          8  => "Wareneingänge",
          9  => "Löhne und Gehälter",
          10 => "Gesetzl. sozialer Aufw.",
          11 => "Mieten",
          12 => "Gas, Strom, Wasser",
          13 => "Instandhaltung",
          14 => "Steuern, Versich., Beiträge",
          15 => "Kfz-Steuern",
          16 => "Kfz-Versicherungen",
          17 => "Sonst. Fahrzeugkosten",
          18 => "Werbe- und Reisekosten",
          19 => "Instandhaltung u. Werkzeuge",
          20 => "Fachzeitschriften, Bücher",
          21 => "Miete für Einrichtungen",
          22 => "Rechts- und Beratungskosten",
          23 => "Bürobedarf, Porto, Telefon",
          24 => "Sonstige Aufwendungen",
          25 => "Abschreibungen auf Anlagever.",
          26 => "Abschreibungen auf GWG",
          27 => "Vorsteuer",
          28 => "Umsatzsteuerzahlungen",
          29 => "Zinsaufwand",
          30 => "Ausserordentlicher Aufwand",
          31 => "Betriebliche Steuern");
  foreach my $item (sort({ $a <=> $b } keys(%eur))) {
    my $text = H($::locale->{iconv_utf8}->convert($eur{$item}));
    if ($item == $form->{pos_eur}) {
      $select_eur .= qq|<option value=$item selected>|. sprintf("%.2d", $item) .qq|. $text</option>\n|;
    } else {
      $select_eur .= qq|<option value=$item>|. sprintf("%.2d", $item) .qq|. $text</option>\n|;
    }

  }

  my $select_bwa = q|<option value=""> |. $locale->text('None') .q|</option>\n|;

  my %bwapos = (
             1  => 'Umsatzerlöse',
             2  => 'Best.Verdg.FE/UE',
             3  => 'Aktiv.Eigenleistung',
             4  => 'Mat./Wareneinkauf',
             5  => 'So.betr.Erlöse',
             10 => 'Personalkosten',
             11 => 'Raumkosten',
             12 => 'Betriebl.Steuern',
             13 => 'Vers./Beiträge',
             14 => 'Kfz.Kosten o.St.',
             15 => 'Werbe-Reisek.',
             16 => 'Kosten Warenabgabe',
             17 => 'Abschreibungen',
             18 => 'Rep./instandhlt.',
             19 => 'Übrige Steuern',
             20 => 'Sonst.Kosten',
             30 => 'Zinsauwand',
             31 => 'Sonst.neutr.Aufw.',
             32 => 'Zinserträge',
             33 => 'Sonst.neutr.Ertrag',
             34 => 'Verr.kalk.Kosten',
             35 => 'Steuern Eink.u.Ertr.');
  foreach my $item (sort({ $a <=> $b } keys %bwapos)) {
    my $text = H($::locale->{iconv_utf8}->convert($bwapos{$item}));
    if ($item == $form->{pos_bwa}) {
      $select_bwa .= qq|<option value="$item" selected>|. sprintf("%.2d", $item) .qq|. $text\n|;
    } else {
      $select_bwa .= qq|<option value="$item">|. sprintf("%.2d", $item) .qq|. $text\n|;
    }

  }

# Wieder hinzugefügt zu evaluationszwecken (us) 09.03.2007
  my $select_bilanz = q|<option value=""> |. $locale->text('None') .q|</option>\n|;
  foreach my $item ((1, 2, 3, 4)) {
    if ($item == $form->{pos_bilanz}) {
      $select_bilanz .= qq|<option value=$item selected>|. sprintf("%.2d", $item) .qq|.\n|;
    } else {
      $select_bilanz .= qq|<option value=$item>|. sprintf("%.2d", $item) .qq|.\n|;
    }

  }

  # this is for our parser only! Do not remove.
  # type=submit $locale->text('Add Account')
  # type=submit $locale->text('Edit Account')

  $form->{type} = "account";

  # preselections category

  my $select_category = q|<option value=""> |. $locale->text('None') .q|</option>\n|;

  my %category = (
      'A'  => $locale->text('Asset'),
      'L'  => $locale->text('Liability'),
      'Q'  => $locale->text('Equity'),
      'I'  => $locale->text('Revenue'),
      'E'  => $locale->text('Expense'),
      'C'  => $locale->text('Costs'),
  );
  foreach my $item ( sort({ $a <=> $b } keys %category) ) {
    if ($item eq $form->{category}) {
      $select_category .= qq|<option value="$item" selected="selected">$category{$item} (|. sprintf("%s", $item) .qq|)\n|;
    } else {
      $select_category .= qq|<option value="$item">$category{$item} (|. sprintf("%s", $item) .qq|)\n|;
    }

  }

  # preselection chart type
  my @all_charttypes = ({'name' => $locale->text('Account'), 'value' => 'A'},
                        {'name' => $locale->text('Heading'), 'value' => 'H'},
    );
  my $selected_charttype = $form->{charttype};


  # account where AR_tax or AP_tax is set are not orphaned if they are used as
  # tax-o-matic account
  if ( $form->{id} && $form->{orphaned} && ($form->{link} =~ m/(AP_tax|AR_tax)/) ) {
    if (SL::DB::Manager::Tax->find_by(chart_id => $form->{id})) {
      $form->{orphaned} = 0;
    }
  }

  my $ChartTypeIsAccount = ($form->{charttype} eq "A") ? "1":"";
  my $AccountIsPosted = ($form->{orphaned} ) ? "":"1";

  $form->header();

  my $parameters_ref = {
    ChartTypeIsAccount         => $ChartTypeIsAccount,
    AccountIsPosted            => $AccountIsPosted,
    select_category            => $select_category,
    all_charttypes             => \@all_charttypes,
    selected_charttype         => $selected_charttype,
    select_bwa                 => $select_bwa,
    select_bilanz              => $select_bilanz,
    select_eur                 => $select_eur,
  };

  # Ausgabe des Templates
  print($form->parse_html_template('am/edit_accounts', $parameters_ref));


  $main::lxdebug->leave_sub();
}

sub form_footer {
  $::lxdebug->enter_sub;
  $::auth->assert('config');

  print $::form->parse_html_template('am/form_footer', {
    show_save        => !$::form->{id}
                     || ($::form->{id} && $::form->{orphaned})
                     || ($::form->{type} eq "account" && !$::form->{new_chart_valid}),
    show_delete      => $::form->{id} && $::form->{orphaned},
    show_save_as_new => $::form->{id} && $::form->{type} eq "account",
  });

  $::lxdebug->leave_sub;
}

sub save_account {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->isblank("accno",       $locale->text('Account Number missing!'));
  $form->isblank("description", $locale->text('Account Description missing!'));

  if ($form->{charttype} eq 'A'){
    $form->isblank("category",  $locale->text('Account Type missing!'));

    my $found_valid_taxkey = 0;
    foreach my $i (0 .. 10) { # 10 is maximum count of taxkeys in form
      if ($form->{"taxkey_startdate_$i"} and !$form->{"taxkey_del_$i"}) {
        $found_valid_taxkey = 1;
        last;
      }
    }
    if ($found_valid_taxkey == 0) {
      $form->error($locale->text('A valid taxkey is missing!'));
    }
  }

  $form->redirect($locale->text('Account saved!'))
    if (AM->save_account(\%myconfig, \%$form));
  $form->error($locale->text('Cannot save account!'));

  $main::lxdebug->leave_sub();
}

sub save_as_new_account {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->isblank("accno",       $locale->text('Account Number missing!'));
  $form->isblank("description", $locale->text('Account Description missing!'));

  if ($form->{charttype} eq 'A'){
    $form->isblank("category",  $locale->text('Account Type missing!'));
  }

  for my $taxkey (0 .. 9) {
    if ($form->{"taxkey_id_$taxkey"}) {
      $form->{"taxkey_id_$taxkey"} = "NEW";
    }
  }

  $form->{id} = 0;
  $form->redirect($locale->text('Account saved!'))
    if (AM->save_account(\%myconfig, \%$form));
  $form->error($locale->text('Cannot save account!'));

  $main::lxdebug->leave_sub();
}

sub list_account {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->{callback}     = build_std_url('action=list_account');
  my $link_edit_account = build_std_url('action=edit_account', 'callback');

  CA->all_accounts(\%myconfig, \%$form);

  foreach my $ca (@{ $form->{CA} }) {

    $ca->{debit}  = "";
    $ca->{credit} = "";

    if ($ca->{amount} > 0) {
      $ca->{credit} = $form->format_amount(\%myconfig, $ca->{amount}, 2);
    }
    if ($ca->{amount} < 0) {
      $ca->{debit} = $form->format_amount(\%myconfig, -1 * $ca->{amount}, 2);
    }
    $ca->{heading}   = ( $ca->{charttype} eq 'H' ) ? 1:'';
    $ca->{link_edit_account} = $link_edit_account . '&id=' . E($ca->{id});
  }

  $::request->{layout}->use_stylesheet("list_accounts.css");
  $form->{title}       = $locale->text('Chart of Accounts');

  $form->header;


  my $parameters_ref = {
  #   hidden_variables                => $_hidden_variables_ref,
  };

  # Ausgabe des Templates
  print($form->parse_html_template('am/list_accounts', $parameters_ref));

  $main::lxdebug->leave_sub();

}


sub list_account_details {
# Ajax Funktion aus list_account_details
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  my $chart_id = $form->{args};

  CA->all_accounts(\%myconfig, \%$form, $chart_id);

  foreach my $ca (@{ $form->{CA} }) {

    $ca->{debit}  = "&nbsp;";
    $ca->{credit} = "&nbsp;";

    if ($ca->{amount} > 0) {
      $ca->{credit} =
        $form->format_amount(\%myconfig, $ca->{amount}, 2, "&nbsp;");
    }
    if ($ca->{amount} < 0) {
      $ca->{debit} =
        $form->format_amount(\%myconfig, -1 * $ca->{amount}, 2, "&nbsp;");
    }

    my @links = split( q{:}, $ca->{link});

    $ca->{link} = q{};

    foreach my $link (@links){
      $link =    ( $link eq 'AR')             ? $locale->text('Account Link AR')
               : ( $link eq 'AP')             ? $locale->text('Account Link AP')
               : ( $link eq 'IC')             ? $locale->text('Account Link IC')
               : ( $link eq 'AR_amount' )     ? $locale->text('Account Link AR_amount')
               : ( $link eq 'AR_paid' )       ? $locale->text('Account Link AR_paid')
               : ( $link eq 'AR_tax' )        ? $locale->text('Account Link AR_tax')
               : ( $link eq 'AP_amount' )     ? $locale->text('Account Link AP_amount')
               : ( $link eq 'AP_paid' )       ? $locale->text('Account Link AP_paid')
               : ( $link eq 'AP_tax' )        ? $locale->text('Account Link AP_tax')
               : ( $link eq 'IC_sale' )       ? $locale->text('Account Link IC_sale')
               : ( $link eq 'IC_cogs' )       ? $locale->text('Account Link IC_cogs')
               : ( $link eq 'IC_taxpart' )    ? $locale->text('Account Link IC_taxpart')
               : ( $link eq 'IC_income' )     ? $locale->text('Account Link IC_income')
               : ( $link eq 'IC_expense' )    ? $locale->text('Account Link IC_expense')
               : ( $link eq 'IC_taxservice' ) ? $locale->text('Account Link IC_taxservice')
               : $locale->text('Unknown Link') . ': ' . $link;
      $ca->{link} .= ($link ne '') ?  "[$link] ":'';
    }

    $ca->{category} = ($ca->{category} eq 'A') ? $locale->text('Account Category A')
                    : ($ca->{category} eq 'E') ? $locale->text('Account Category E')
                    : ($ca->{category} eq 'L') ? $locale->text('Account Category L')
                    : ($ca->{category} eq 'I') ? $locale->text('Account Category I')
                    : ($ca->{category} eq 'Q') ? $locale->text('Account Category Q')
                    : ($ca->{category} eq 'C') ? $locale->text('Account Category C')
                    : ($ca->{category} eq 'G') ? $locale->text('Account Category G')
                    : $locale->text('Unknown Category') . ': ' . $ca->{category};
  }

  $form->{title} = $locale->text('Chart of Accounts');

  print $form->ajax_response_header, $form->parse_html_template('am/list_account_details');

  $main::lxdebug->leave_sub();

}

sub delete_account {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->{title} = $locale->text('Delete Account');

  foreach my $id (
    qw(inventory_accno_id income_accno_id expense_accno_id fxgain_accno_id fxloss_accno_id)
    ) {
    if ($form->{id} == $form->{$id}) {
      $form->error($locale->text('Cannot delete default account!'));
    }
  }

  $form->redirect($locale->text('Account deleted!'))
    if (AM->delete_account(\%myconfig, \%$form));
  $form->error($locale->text('Cannot delete account!'));

  $main::lxdebug->leave_sub();
}

sub add_lead {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;

  $main::auth->assert('config');

  $form->{title} = "Add";

  $form->{callback} = "am.pl?action=add_lead" unless $form->{callback};

  &lead_header;
  &form_footer;

  $main::lxdebug->leave_sub();
}

sub edit_lead {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $main::auth->assert('config');

  $form->{title} = "Edit";

  AM->get_lead(\%myconfig, \%$form);

  &lead_header;

  $form->{orphaned} = 1;
  &form_footer;

  $main::lxdebug->leave_sub();
}

sub list_lead {
  $::lxdebug->enter_sub;
  $::auth->assert('config');

  AM->lead(\%::myconfig, $::form);

  $::form->{callback} = "am.pl?action=list_lead";
  $::form->{title}    = $::locale->text('Lead');

  $::form->header;
  print $::form->parse_html_template('am/lead_list');

  $::lxdebug->leave_sub;
}

sub lead_header {
  $::lxdebug->enter_sub;
  $::auth->assert('config');

  # $locale->text('Add Lead')
  # $locale->text('Edit Lead')
  $::form->{title} = $::locale->text("$::form->{title} Lead");

  $::form->header;
  print $::form->parse_html_template('am/lead_header');

  $::lxdebug->leave_sub;
}

sub save_lead {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->isblank("description", $locale->text('Description missing!'));
  AM->save_lead(\%myconfig, \%$form);
  $form->redirect($locale->text('lead saved!'));

  $main::lxdebug->leave_sub();
}

sub delete_lead {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  AM->delete_lead(\%myconfig, \%$form);
  $form->redirect($locale->text('lead deleted!'));

  $main::lxdebug->leave_sub();
}

sub add_language {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;

  $main::auth->assert('config');

  $form->{title} = "Add";

  $form->{callback} = "am.pl?action=add_language" unless $form->{callback};

  &language_header;
  &form_footer;

  $main::lxdebug->leave_sub();
}

sub edit_language {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $main::auth->assert('config');

  $form->{title} = "Edit";

  AM->get_language(\%myconfig, \%$form);

  &language_header;

  $form->{orphaned} = 1;
  &form_footer;

  $main::lxdebug->leave_sub();
}

sub list_language {
  $::lxdebug->enter_sub;
  $::auth->assert('config');

  AM->language(\%::myconfig, $::form);

  $::form->{callback} = "am.pl?action=list_language";
  $::form->{title}   = $::locale->text('Languages');

  $::form->header;

  print $::form->parse_html_template('am/language_list');

  $::lxdebug->leave_sub;
}

sub language_header {
  $::lxdebug->enter_sub;
  $::auth->assert('config');

  # $locale->text('Add Language')
  # $locale->text('Edit Language')
  $::form->{title} = $::locale->text("$::form->{title} Language");

  $::form->header;

  print $::form->parse_html_template('am/language_header', {
    numberformats => [ '1,000.00', '1000.00', '1.000,00', '1000,00' ],
    dateformats => [ qw(mm/dd/yy dd/mm/yy dd.mm.yy yyyy-mm-dd) ],
  });

  $::lxdebug->leave_sub;
}

sub save_language {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->isblank("description", $locale->text('Language missing!'));
  $form->isblank("template_code", $locale->text('Template Code missing!'));
  $form->isblank("article_code", $locale->text('Article Code missing!'));
  AM->save_language(\%myconfig, \%$form);
  $form->redirect($locale->text('Language saved!'));

  $main::lxdebug->leave_sub();
}

sub delete_language {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  AM->delete_language(\%myconfig, \%$form);
  $form->redirect($locale->text('Language deleted!'));

  $main::lxdebug->leave_sub();
}


sub add_buchungsgruppe {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  # $locale->text("Add Buchungsgruppe")
  # $locale->text("Edit Buchungsgruppe")
  $form->{title} = "Add";

  $form->{callback} = "am.pl?action=add_buchungsgruppe" unless $form->{callback};

  AM->get_buchungsgruppe(\%myconfig, \%$form);
  $form->{"inventory_accno_id"} = $form->{"std_inventory_accno_id"};
  for (my $i = 0; 4 > $i; $i++) {
    map({ $form->{"${_}_accno_id_$i"} = $form->{"std_${_}_accno_id"}; }
        qw(income expense));
  }

  &buchungsgruppe_header;
  &form_footer;

  $main::lxdebug->leave_sub();
}

sub edit_buchungsgruppe {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $main::auth->assert('config');

  $form->{title} = "Edit";

  AM->get_buchungsgruppe(\%myconfig, \%$form);

  &buchungsgruppe_header;

  &form_footer;

  $main::lxdebug->leave_sub();
}

sub list_buchungsgruppe {
  $::lxdebug->enter_sub;
  $::auth->assert('config');

  AM->buchungsgruppe(\%::myconfig, $::form);

  $::form->{callback} = "am.pl?action=list_buchungsgruppe";
  $::form->{title}    = $::locale->text('Buchungsgruppen');
  $::form->header;

  print $::form->parse_html_template('am/buchungsgruppe_list', {
    swap_link => qq|am.pl?action=swap_buchungsgruppen&|,
  });

  $::lxdebug->leave_sub;
}

sub buchungsgruppe_header {
  $::lxdebug->enter_sub;
  $::auth->assert('config');

  # $locale->text('Add Accounting Group')
  # $locale->text('Edit Accounting Group')
  $::form->{title}    = $::locale->text("$::form->{title} Buchungsgruppe");

  my ($acc_inventory, $acc_income, $acc_expense) = ({}, {}, {});
  my %acc_type_map = (
    IC         => $acc_inventory,
    IC_income  => $acc_income,
    IC_sale    => $acc_income,
    IC_expense => $acc_expense,
    IC_cogs    => $acc_expense,
  );

  for my $key (keys %acc_type_map) {
    for my $ref (@{ $::form->{IC_links}{$key} }) {
      $acc_type_map{$key}{$ref->{id}} = $ref;
    }
  }

  my %sorted_accounts = map {
    $_ => [ sort { $a->{accno} cmp $b->{accno} } values %{ $acc_type_map{$_} } ],
  } keys %acc_type_map;

  $::form->header;
  print $::form->parse_html_template('am/buchungsgruppe_header', {
    accounts      => \%sorted_accounts,
    account_label => sub { "$_[0]{accno}--$_[0]{description}" },
  });

  $::lxdebug->leave_sub;
}

sub save_buchungsgruppe {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->isblank("description", $locale->text('Description missing!'));

  AM->save_buchungsgruppe(\%myconfig, \%$form);
  $form->redirect($locale->text('Accounting Group saved!'));

  $main::lxdebug->leave_sub();
}

sub delete_buchungsgruppe {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  AM->delete_buchungsgruppe(\%myconfig, \%$form);
  $form->redirect($locale->text('Accounting Group deleted!'));

  $main::lxdebug->leave_sub();
}

sub swap_buchungsgruppen {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $main::auth->assert('config');

  AM->swap_sortkeys(\%myconfig, $form, "buchungsgruppen");
  list_buchungsgruppe();

  $main::lxdebug->leave_sub();
}

sub _build_cfg_options {
  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  my $idx   = shift;
  my $array = uc($idx) . 'S';

  $form->{$array} = [];
  foreach my $item (@_) {
    push @{ $form->{$array} }, {
      'name'     => $item,
      'value'    => $item,
      'selected' => $item eq $myconfig{$idx},
    };
  }
}

sub config {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  _build_cfg_options('dateformat', qw(mm/dd/yy dd/mm/yy dd.mm.yy yyyy-mm-dd));
  _build_cfg_options('timeformat', qw(hh:mm hh:mm:ss));
  _build_cfg_options('numberformat', ('1,000.00', '1000.00', '1.000,00', '1000,00'));

  my @formats = ();
  if ($::lx_office_conf{print_templates}->{opendocument}
      && $::lx_office_conf{applications}->{openofficeorg_writer} && (-x $::lx_office_conf{applications}->{openofficeorg_writer})
      && $::lx_office_conf{applications}->{xvfb}                 && (-x $::lx_office_conf{applications}->{xvfb})) {
    push(@formats, { "name" => $locale->text("PDF (OpenDocument/OASIS)"),
                     "value" => "opendocument_pdf" });
  }
  if ($::lx_office_conf{print_templates}->{latex}) {
    push(@formats, { "name" => $locale->text("PDF"), "value" => "pdf" });
  }
  push(@formats, { "name" => "HTML", "value" => "html" });
  if ($::lx_office_conf{print_templates}->{latex}) {
    push(@formats, { "name" => $locale->text("Postscript"),
                     "value" => "postscript" });
  }
  if ($::lx_office_conf{print_templates}->{opendocument}) {
    push(@formats, { "name" => $locale->text("OpenDocument/OASIS"),
                     "value" => "opendocument" });
  }

  if (!$myconfig{"template_format"}) {
    $myconfig{"template_format"} = "pdf";
  }
  $form->{TEMPLATE_FORMATS} = [];
  foreach my $item (@formats) {
    push @{ $form->{TEMPLATE_FORMATS} }, {
      'name'     => $item->{name},
      'value'    => $item->{value},
      'selected' => $item->{value} eq $myconfig{template_format},
    };
  }

  if (!$myconfig{"default_media"}) {
    $myconfig{"default_media"} = "screen";
  }

  my %selected = ($myconfig{"default_media"} => "selected");
  $form->{MEDIA} = [
    { 'name' => $locale->text('Screen'),  'value' => 'screen',  'selected' => $selected{screen}, },
    { 'name' => $locale->text('Printer'), 'value' => 'printer', 'selected' => $selected{printer}, },
    { 'name' => $locale->text('Queue'),   'value' => 'queue',   'selected' => $selected{queue}, },
    ];

  $form->{PRINTERS} = SL::DB::Manager::Printer->get_all_sorted;

  my %countrycodes = User->country_codes;

  $form->{COUNTRYCODES} = [];
  foreach my $countrycode (sort { $countrycodes{$a} cmp $countrycodes{$b} } keys %countrycodes) {
    push @{ $form->{COUNTRYCODES} }, {
      'name'     => $countrycodes{$countrycode},
      'value'    => $countrycode,
      'selected' => $countrycode eq $myconfig{countrycode},
    };
  }

  $form->{STYLESHEETS} = [];
  foreach my $item (qw(finance5.css lx-office-erp.css Mobile.css kivitendo.css)) {
    push @{ $form->{STYLESHEETS} }, {
      'name'     => $item,
      'value'    => $item,
      'selected' => $item eq $myconfig{stylesheet},
    };
  }

  $myconfig{show_form_details} = 1 unless (defined($myconfig{show_form_details}));
  $form->{CAN_CHANGE_PASSWORD} = $main::auth->can_change_password();
  $form->{todo_cfg}            = { TODO->get_user_config('login' => $form->{login}) };

  $form->{title}               = $locale->text('Edit Preferences for #1', $form->{login});

  $form->header();
  print $form->parse_html_template('am/config');

  $main::lxdebug->leave_sub();
}

sub save_preferences {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $form->{stylesheet} = $form->{usestylesheet};

  TODO->save_user_config('login' => $form->{login}, %{ $form->{todo_cfg} || { } });

  if (AM->save_preferences($form)) {
    if ($::auth->can_change_password()
        && defined $form->{new_password}
        && ($form->{new_password} ne '********')) {
      my $verifier = SL::Auth::PasswordPolicy->new;
      my $result   = $verifier->verify($form->{new_password});

      if ($result != SL::Auth::PasswordPolicy->OK()) {
        $form->error($::locale->text('The settings were saved, but the password was not changed.') . ' ' . join(' ', $verifier->errors($result)));
      }

      $::auth->change_password($form->{login}, $form->{new_password});
    }

    $form->redirect($locale->text('Preferences saved!'));
  }

  $form->error($locale->text('Cannot save preferences!'));

  $main::lxdebug->leave_sub();
}

sub audit_control {
  $::lxdebug->enter_sub;
  $::auth->assert('config');

  $::form->{title} = $::locale->text('Audit Control');

  AM->closedto(\%::myconfig, $::form);

  $::form->header;
  print $::form->parse_html_template('am/audit_control');

  $::lxdebug->leave_sub;
}

sub doclose {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  AM->closebooks(\%myconfig, \%$form);

  if ($form->{closedto}) {
    $form->redirect(
                    $locale->text('Books closed up to') . " "
                      . $locale->date(\%myconfig, $form->{closedto}, 1));
  } else {
    $form->redirect($locale->text('Books are open'));
  }

  $main::lxdebug->leave_sub();
}

sub edit_units {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  my $units = AM->retrieve_units(\%myconfig, $form, "resolved_");
  AM->units_in_use(\%myconfig, $form, $units);
  map({ $units->{$_}->{"BASE_UNIT_DDBOX"} = AM->unit_select_data($units, $units->{$_}->{"base_unit"}, 1); } keys(%{$units}));

  my @languages = AM->language(\%myconfig, $form, 1);

  my @unit_list = sort({ $a->{"sortkey"} <=> $b->{"sortkey"} } values(%{$units}));

  my $i = 1;
  foreach (@unit_list) {
    $_->{"factor"} = $form->format_amount(\%myconfig, $_->{"factor"} * 1) if ($_->{"factor"});
    $_->{"UNITLANGUAGES"} = [];
    foreach my $lang (@languages) {
      push(@{ $_->{"UNITLANGUAGES"} },
           { "idx" => $i,
             "unit" => $_->{"name"},
             "language_id" => $lang->{"id"},
             "localized" => $_->{"LANGUAGES"}->{$lang->{"template_code"}}->{"localized"},
             "localized_plural" => $_->{"LANGUAGES"}->{$lang->{"template_code"}}->{"localized_plural"},
           });
    }
    $i++;
  }

  $units = AM->retrieve_units(\%myconfig, $form);
  my $ddbox = AM->unit_select_data($units, undef, 1);

  $form->{"title"} = $locale->text("Add and edit units");
  $form->header();
  print($form->parse_html_template("am/edit_units",
                                   { "UNITS"               => \@unit_list,
                                     "NEW_BASE_UNIT_DDBOX" => $ddbox,
                                     "LANGUAGES"           => \@languages,
                                   }));

  $main::lxdebug->leave_sub();
}

sub add_unit {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->isblank("new_name", $locale->text("The name is missing."));
  my $units = AM->retrieve_units(\%myconfig, $form);
  my $all_units = AM->retrieve_units(\%myconfig, $form);
  $form->show_generic_error($locale->text("A unit with this name does already exist.")) if ($all_units->{$form->{"new_name"}});

  my ($base_unit, $factor);
  if ($form->{"new_base_unit"}) {
    $form->show_generic_error($locale->text("The base unit does not exist.")) unless (defined($units->{$form->{"new_base_unit"}}));

    $form->isblank("new_factor", $locale->text("The factor is missing."));
    $factor = $form->parse_amount(\%myconfig, $form->{"new_factor"});
    $form->show_generic_error($locale->text("The factor is missing.")) unless ($factor);
    $base_unit = $form->{"new_base_unit"};
  }

  my @languages;
  foreach my $lang (AM->language(\%myconfig, $form, 1)) {
    next unless ($form->{"new_localized_$lang->{id}"} || $form->{"new_localized_plural_$lang->{id}"});
    push(@languages, { "id" => $lang->{"id"},
                       "localized" => $form->{"new_localized_$lang->{id}"},
                       "localized_plural" => $form->{"new_localized_plural_$lang->{id}"},
         });
  }

  AM->add_unit(\%myconfig, $form, $form->{"new_name"}, $base_unit, $factor, \@languages);

  $form->{"saved_message"} = $locale->text("The unit has been saved.");

  edit_units();

  $main::lxdebug->leave_sub();
}

sub set_unit_languages {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;

  $main::auth->assert('config');

  my ($unit, $languages, $idx) = @_;

  $unit->{"LANGUAGES"} = [];

  foreach my $lang (@{$languages}) {
    push(@{ $unit->{"LANGUAGES"} },
         { "id" => $lang->{"id"},
           "localized" => $form->{"localized_${idx}_$lang->{id}"},
           "localized_plural" => $form->{"localized_plural_${idx}_$lang->{id}"},
         });
  }

  $main::lxdebug->leave_sub();
}

sub save_unit {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  my $old_units = AM->retrieve_units(\%myconfig, $form, "resolved_");
  AM->units_in_use(\%myconfig, $form, $old_units);

  my @languages = AM->language(\%myconfig, $form, 1);

  my $new_units = {};
  my @delete_units = ();
  foreach my $i (1..($form->{"rowcount"} * 1)) {
    my $old_unit = $old_units->{$form->{"old_name_$i"}};
    if (!$old_unit) {
      $form->show_generic_error(sprintf($locale->text("The unit in row %d has been deleted in the meantime."), $i));
    }

    if ($form->{"unchangeable_$i"}) {
      $new_units->{$form->{"old_name_$i"}} = $old_units->{$form->{"old_name_$i"}};
      $new_units->{$form->{"old_name_$i"}}->{"unchanged_unit"} = 1;
      set_unit_languages($new_units->{$form->{"old_name_$i"}}, \@languages, $i);
      next;
    }

    if ($old_unit->{"in_use"}) {
      $form->show_generic_error(sprintf($locale->text("The unit in row %d has been used in the meantime and cannot be changed anymore."), $i));
    }

    if ($form->{"delete_$i"}) {
      push(@delete_units, $old_unit->{"name"});
      next;
    }

    $form->isblank("name_$i", sprintf($locale->text("The name is missing in row %d."), $i));

    $form->show_generic_error(sprintf($locale->text("The name in row %d has already been used before."), $i)) if ($new_units->{$form->{"name_$i"}});
    my %h = map({ $_ => $form->{"${_}_$i"} } qw(name base_unit factor old_name));
    $new_units->{$form->{"name_$i"}} = \%h;
    $new_units->{$form->{"name_$i"}}->{"row"} = $i;
    set_unit_languages($new_units->{$form->{"old_name_$i"}}, \@languages, $i);
  }

  foreach my $unit (values(%{$new_units})) {
    next unless ($unit->{"old_name"});
    if ($unit->{"base_unit"}) {
      $form->show_generic_error(sprintf($locale->text("The base unit does not exist or it is about to be deleted in row %d."), $unit->{"row"}))
        unless (defined($new_units->{$unit->{"base_unit"}}));
      $unit->{"factor"} = $form->parse_amount(\%myconfig, $unit->{"factor"});
      $form->show_generic_error(sprintf($locale->text("The factor is missing in row %d."), $unit->{"row"})) unless ($unit->{"factor"} >= 1.0);
    } else {
      $unit->{"base_unit"} = undef;
      $unit->{"factor"} = undef;
    }
  }

  foreach my $unit (values(%{$new_units})) {
    next if ($unit->{"unchanged_unit"});

    map({ $_->{"seen"} = 0; } values(%{$new_units}));
    my $new_unit = $unit;
    while ($new_unit->{"base_unit"}) {
      $new_unit->{"seen"} = 1;
      $new_unit = $new_units->{$new_unit->{"base_unit"}};
      if ($new_unit->{"seen"}) {
        $form->show_generic_error(sprintf($locale->text("The base unit relations must not contain loops (e.g. by saying that unit A's base unit is B, " .
                                                        "B's base unit is C and C's base unit is A) in row %d."), $unit->{"row"}));
      }
    }
  }

  AM->save_units(\%myconfig, $form, $new_units, \@delete_units);

  $form->{"saved_message"} = $locale->text("The units have been saved.");

  edit_units();

  $main::lxdebug->leave_sub();
}

sub show_history_search {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->{title} = $locale->text("History Search");
  $form->header();

  print $form->parse_html_template("common/search_history");

  $main::lxdebug->leave_sub();
}

sub show_am_history {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  my $callback     = build_std_url(qw(action einschraenkungen fromdate todate mitarbeiter searchid what2search));
  $form->{order} ||= 'h.itime--1';

  my %search = ( "Artikelnummer"          => "parts",
                 "Kundennummer"           => "customer",
                 "Lieferantennummer"      => "vendor",
                 "Projektnummer"          => "project",
                 "Buchungsnummer"         => "oe",
                 "Eingangsrechnungnummer" => "ap",
                 "Ausgangsrechnungnummer" => "ar",
                 "Mahnungsnummer"         => "dunning"
    );
  my %searchNo = ( "Artikelnummer"          => "partnumber",
                   "Kundennummer"           => "customernumber",
                   "Lieferantennummer"      => "vendornumber",
                   "Projektnummer"          => "projectnumber",
                   "Buchungsnummer"         => "ordnumber",
                   "Eingangsrechnungnummer" => "invnumber",
                   "Ausgangsrechnungnummer" => "invnumber",
                   "Mahnungsnummer"         => "dunning_id"
    );

  my $dbh = $form->dbconnect(\%myconfig);

  my $restriction;
  $restriction     = qq| AND (| . join(' OR ', map { " addition = " . $dbh->quote($_) } split(m/\,/, $form->{einschraenkungen})) . qq|)| if $form->{einschraenkungen};
  $restriction    .= qq| AND h.itime::date >= | . conv_dateq($form->{fromdate})                                                          if $form->{fromdate};
  $restriction    .= qq| AND h.itime::date <= | . conv_dateq($form->{todate})                                                            if $form->{todate};
  if ($form->{mitarbeiter} =~ m/^\d+$/) {
    $restriction  .= qq| AND employee_id = |    . $form->{mitarbeiter};
  } elsif ($form->{mitarbeiter}) {
    $restriction  .= qq| AND employee_id = (SELECT id FROM employee WHERE name ILIKE | . $dbh->quote('%' . $form->{mitarbeiter} . '%') . qq|)|;
  }

  my $query = qq|SELECT trans_id AS id FROM history_erp | .
    (  $form->{'searchid'} ? qq| WHERE snumbers = '|  . $searchNo{$form->{'what2search'}} . qq|_| . $form->{'searchid'} . qq|'|
     :                       qq| WHERE snumbers ~ '^| . $searchNo{$form->{'what2search'}} . qq|'|);

  my @ids    = grep { $_ * 1 } selectall_array_query($form, $dbh, $query);
  my $daten .= shift @ids;
  $daten    .= join '', map { " OR trans_id = $_" } @ids;

  my ($sort, $sortby) = split(/\-\-/, $form->{order});
  $sort =~ s/.*\.(.*)$/$1/;

  $form->{title} = $locale->text("History Search");
  $form->header();

  print $form->parse_html_template("common/show_history",
                                   { "DATEN"          => $form->get_history($dbh, $daten, $restriction, $form->{order}),
                                     "SUCCESS"        => ($form->get_history($dbh, $daten, $restriction, $form->{order}) ne "0"),
                                     "NONEWWINDOW"    => 1,
                                     uc($sort)        => 1,
                                     uc($sort) . "BY" => $sortby,
                                     'callback'       => $callback,
                                   });
  $dbh->disconnect();

  $main::lxdebug->leave_sub();
}

sub add_tax {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->{title} =  $locale->text('Add');

  $form->{callback} ||= "am.pl?action=add_tax";

  _get_taxaccount_selection();

  $form->{asset}      = 1;
  $form->{liability}  = 1;
  $form->{equity}     = 1;
  $form->{revenue}    = 1;
  $form->{expense}    = 1;
  $form->{costs}      = 1;

  $form->header();

  my $parameters_ref = {
#    ChartTypeIsAccount         => $ChartTypeIsAccount,
  };

  # Ausgabe des Templates
  print($form->parse_html_template('am/edit_tax', $parameters_ref));

  $main::lxdebug->leave_sub();
}

sub edit_tax {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->{title} =  $locale->text('Edit');

  AM->get_tax(\%myconfig, \%$form);

  _get_taxaccount_selection();

  $form->{asset}      = $form->{chart_categories} =~ 'A' ? 1 : 0;
  $form->{liability}  = $form->{chart_categories} =~ 'L' ? 1 : 0;
  $form->{equity}     = $form->{chart_categories} =~ 'Q' ? 1 : 0;
  $form->{revenue}    = $form->{chart_categories} =~ 'I' ? 1 : 0;
  $form->{expense}    = $form->{chart_categories} =~ 'E' ? 1 : 0;
  $form->{costs}      = $form->{chart_categories} =~ 'C' ? 1 : 0;

  $form->{rate} = $form->format_amount(\%myconfig, $form->{rate}, 2);

  $form->header();

  my $parameters_ref = {
  };

  # Ausgabe des Templates
  print($form->parse_html_template('am/edit_tax', $parameters_ref));

  $main::lxdebug->leave_sub();
}

sub list_tax {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  AM->taxes(\%myconfig, \%$form);

  map { $_->{rate} = $form->format_amount(\%myconfig, $_->{rate}, 2) } @{ $form->{TAX} };

  $form->{callback} = build_std_url('action=list_tax');

  $form->{title} = $locale->text('Tax-O-Matic');

  $form->header();

  my $parameters_ref = {
  };

  # Ausgabe des Templates
  print($form->parse_html_template('am/list_tax', $parameters_ref));

  $main::lxdebug->leave_sub();
}

sub _get_taxaccount_selection{
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $main::auth->assert('config');

  AM->get_tax_accounts(\%myconfig, \%$form);

  map { $_->{selected} = $form->{chart_id} == $_->{id} } @{ $form->{ACCOUNTS} };

  $main::lxdebug->leave_sub();
}

sub save_tax {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->error($locale->text('Taxkey  missing!')) unless length($form->{taxkey}) != 0;
  $form->error($locale->text('Taxdescription  missing!')) unless length($form->{taxdescription}) != 0;
  $form->error($locale->text('Taxrate missing!')) unless length($form->{rate}) != 0;

  $form->{rate} = $form->parse_amount(\%myconfig, $form->{rate});

  if ($form->{taxkey} == 0 and $form->{rate} > 0) {
    $form->error($locale->text('Taxkey 0 is reserved for rate 0'));
  }

  if ( $form->{rate} < 0 || $form->{rate} >= 100 ) {
    $form->error($locale->text('Tax Percent is a number between 0 and 100'));
  }

  if ( $form->{rate} <= 0.99 && $form->{rate} > 0 ) {
    $form->error($locale->text('Tax Percent is a number between 0 and 100'));
  }

  AM->save_tax(\%myconfig, \%$form);
  $form->redirect($locale->text('Tax saved!'));

  $main::lxdebug->leave_sub();
}

sub delete_tax {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  AM->delete_tax(\%myconfig, \%$form);
  $form->redirect($locale->text('Tax deleted!'));

  $main::lxdebug->leave_sub();
}

sub add_price_factor {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->{title}      = $locale->text('Add Price Factor');
  $form->{callback} ||= build_std_url('action=add_price_factor');

  $form->header();
  print $form->parse_html_template('am/edit_price_factor');

  $main::lxdebug->leave_sub();
}

sub edit_price_factor {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->{title}      = $locale->text('Edit Price Factor');
  $form->{callback} ||= build_std_url('action=add_price_factor');

  AM->get_price_factor(\%myconfig, $form);

  $form->{factor} = $form->format_amount(\%myconfig, $form->{factor} * 1);

  $form->header();
  print $form->parse_html_template('am/edit_price_factor');

  $main::lxdebug->leave_sub();
}

sub list_price_factors {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  AM->get_all_price_factors(\%myconfig, \%$form);

  foreach my $current (@{ $form->{PRICE_FACTORS} }) {
    $current->{factor} = $form->format_amount(\%myconfig, $current->{factor} * 1);
  }

  $form->{callback} = build_std_url('action=list_price_factors');
  $form->{title}    = $locale->text('Price Factors');
  $form->{url_base} = build_std_url('callback');

  $form->header();
  print $form->parse_html_template('am/list_price_factors');

  $main::lxdebug->leave_sub();
}

sub save_price_factor {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->isblank("description", $locale->text('Description missing!'));
  $form->isblank("factor", $locale->text('Factor missing!'));

  $form->{factor} = $form->parse_amount(\%myconfig, $form->{factor});

  AM->save_price_factor(\%myconfig, $form);

  $form->{callback} .= '&MESSAGE=' . $form->escape($locale->text('Price factor saved!')) if ($form->{callback});

  $form->redirect($locale->text('Price factor saved!'));

  $main::lxdebug->leave_sub();
}

sub delete_price_factor {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  AM->delete_price_factor(\%myconfig, \%$form);

  $form->{callback} .= '&MESSAGE=' . $form->escape($locale->text('Price factor deleted!')) if ($form->{callback});

  $form->redirect($locale->text('Price factor deleted!'));

  $main::lxdebug->leave_sub();
}

sub add_warehouse {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->{title}      = $locale->text('Add Warehouse');
  $form->{callback} ||= build_std_url('action=add_warehouse');

  $form->header();
  print $form->parse_html_template('am/edit_warehouse');

  $main::lxdebug->leave_sub();
}

sub edit_warehouse {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  AM->get_warehouse(\%myconfig, $form);

  $form->get_lists('employees' => 'EMPLOYEES');

  $form->{title}      = $locale->text('Edit Warehouse');
  $form->{callback} ||= build_std_url('action=list_warehouses');

  $form->header();
  print $form->parse_html_template('am/edit_warehouse');

  $main::lxdebug->leave_sub();
}

sub list_warehouses {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  AM->get_all_warehouses(\%myconfig, $form);

  $form->{callback} = build_std_url('action=list_warehouses');
  $form->{title}    = $locale->text('Warehouses');
  $form->{url_base} = build_std_url('callback');

  $form->header();
  print $form->parse_html_template('am/list_warehouses');

  $main::lxdebug->leave_sub();
}

sub save_warehouse {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  $form->isblank("description", $locale->text('Description missing!'));

  $form->{number_of_new_bins} = $form->parse_amount(\%myconfig, $form->{number_of_new_bins});

  AM->save_warehouse(\%myconfig, $form);

  $form->{callback} .= '&saved_message=' . E($locale->text('Warehouse saved.')) if ($form->{callback});

  $form->redirect($locale->text('Warehouse saved.'));

  $main::lxdebug->leave_sub();
}

sub delete_warehouse {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  if (!$form->{confirmed}) {
    $form->{title} = $locale->text('Confirmation');

    $form->header();
    print $form->parse_html_template('am/confirm_delete_warehouse');
    ::end_of_request();
  }

  if (AM->delete_warehouse(\%myconfig, $form)) {
    $form->{callback} .= '&saved_message=' . E($locale->text('Warehouse deleted.')) if ($form->{callback});
    $form->redirect($locale->text('Warehouse deleted.'));

  } else {
    $form->error($locale->text('The warehouse could not be deleted because it has already been used.'));
  }

  $main::lxdebug->leave_sub();
}

sub save_bin {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $main::auth->assert('config');

  AM->save_bins(\%myconfig, $form);

  $form->{callback} .= '&saved_message=' . E($locale->text('Bins saved.')) if ($form->{callback});

  $form->redirect($locale->text('Bins saved.'));

  $main::lxdebug->leave_sub();
}
