#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
# Copyright (C) 2001
#
#  Author: Dieter Simader
#   Email: dsimader@sql-ledger.org
#     Web: http://www.sql-ledger.org
#
#  Contributors:
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
# Administration module
#    Chart of Accounts
#    template routines
#    preferences
#
#======================================================================

package AM;

use Carp;
use Data::Dumper;
use Encode;
use List::MoreUtils qw(any);
use SL::DBUtils;
use SL::DB::AuthUser;
use SL::DB::Default;
use SL::DB::Employee;

use strict;

sub get_account {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);
  my $query = qq{
    SELECT c.accno, c.description, c.charttype, c.category,
      c.link, c.pos_bilanz, c.pos_eur, c.new_chart_id, c.valid_from,
      c.pos_bwa, datevautomatik,
      tk.taxkey_id, tk.pos_ustva, tk.tax_id,
      tk.tax_id || '--' || tk.taxkey_id AS tax, tk.startdate
    FROM chart c
    LEFT JOIN taxkeys tk
    ON (c.id=tk.chart_id AND tk.id =
      (SELECT id FROM taxkeys
       WHERE taxkeys.chart_id = c.id AND startdate <= current_date
       ORDER BY startdate DESC LIMIT 1))
    WHERE c.id = ?
    };


  $main::lxdebug->message(LXDebug->QUERY(), "\$query=\n $query");
  my $sth = $dbh->prepare($query);
  $sth->execute($form->{id}) || $form->dberror($query . " ($form->{id})");

  my $ref = $sth->fetchrow_hashref("NAME_lc");

  foreach my $key (keys %$ref) {
    $form->{"$key"} = $ref->{"$key"};
  }

  $sth->finish;

  # get default accounts
  $query = qq|SELECT inventory_accno_id, income_accno_id, expense_accno_id
              FROM defaults|;
  $main::lxdebug->message(LXDebug->QUERY(), "\$query=\n $query");
  $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  $ref = $sth->fetchrow_hashref("NAME_lc");

  map { $form->{$_} = $ref->{$_} } keys %{ $ref };

  $sth->finish;



  # get taxkeys and description
  $query = qq{
    SELECT
      id,
      (SELECT accno FROM chart WHERE id=tax.chart_id) AS chart_accno,
      taxkey,
      id||'--'||taxkey AS tax,
      taxdescription,
      rate
    FROM tax ORDER BY taxkey
  };
  $main::lxdebug->message(LXDebug->QUERY(), "\$query=\n $query");
  $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  $form->{TAXKEY} = [];

  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    push @{ $form->{TAXKEY} }, $ref;
  }

  $sth->finish;
  if ($form->{id}) {
    # get new accounts
    $query = qq|SELECT id, accno,description
                FROM chart
                WHERE link = ?
                ORDER BY accno|;
    $main::lxdebug->message(LXDebug->QUERY(), "\$query=\n $query");
    $sth = $dbh->prepare($query);
    $sth->execute($form->{link}) || $form->dberror($query . " ($form->{link})");

    $form->{NEWACCOUNT} = [];
    while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
      push @{ $form->{NEWACCOUNT} }, $ref;
    }

    $sth->finish;

    # get the taxkeys of account

    $query = qq{
      SELECT
        tk.id,
        tk.chart_id,
        c.accno,
        tk.tax_id,
        t.taxdescription,
        t.rate,
        tk.taxkey_id,
        tk.pos_ustva,
        tk.startdate
      FROM taxkeys tk
      LEFT JOIN   tax t ON (t.id = tk.tax_id)
      LEFT JOIN chart c ON (c.id = t.chart_id)

      WHERE tk.chart_id = ?
      ORDER BY startdate DESC
    };
    $main::lxdebug->message(LXDebug->QUERY(), "\$query=\n $query");
    $sth = $dbh->prepare($query);

    $sth->execute($form->{id}) || $form->dberror($query . " ($form->{id})");

    $form->{ACCOUNT_TAXKEYS} = [];

    while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
      push @{ $form->{ACCOUNT_TAXKEYS} }, $ref;
    }

    $sth->finish;

  }
  # check if we have any transactions
  $query = qq|SELECT a.trans_id FROM acc_trans a
              WHERE a.chart_id = ?|;
  $main::lxdebug->message(LXDebug->QUERY(), "\$query=\n $query");
  $sth = $dbh->prepare($query);
  $sth->execute($form->{id}) || $form->dberror($query . " ($form->{id})");

  ($form->{orphaned}) = $sth->fetchrow_array;
  $form->{orphaned} = !$form->{orphaned};
  $sth->finish;

  # check if new account is active
  $form->{new_chart_valid} = 0;
  if ($form->{new_chart_id}) {
    $query = qq|SELECT current_date-valid_from FROM chart
                WHERE id = ?|;
    $main::lxdebug->message(LXDebug->QUERY(), "\$query=\n $query");
    my ($count) = selectrow_query($form, $dbh, $query, $form->{id});
    if ($count >=0) {
      $form->{new_chart_valid} = 1;
    }
    $sth->finish;
  }

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub save_account {
  $main::lxdebug->enter_sub();

  # TODO: it should be forbidden to change an account to a heading if there
  # have been bookings to this account in the past

  my ($self, $myconfig, $form) = @_;

  # connect to database, turn off AutoCommit
  my $dbh = $form->dbconnect_noauto($myconfig);

  for (qw(AR_include_in_dropdown AP_include_in_dropdown summary_account)) {
    $form->{$form->{$_}} = $form->{$_} if $form->{$_};
  }

  # sanity check, can't have AR with AR_...
  if ($form->{AR} || $form->{AP} || $form->{IC}) {
    if (any { $form->{$_} } qw(AR_amount AR_tax AR_paid AP_amount AP_tax AP_paid IC_sale IC_cogs IC_taxpart IC_income IC_expense IC_taxservice)) {
      $form->error($::locale->text('It is not allowed that a summary account occurs in a drop-down menu!'));
    }
  }

  $form->{link} = "";
  foreach my $item ($form->{AR},            $form->{AR_amount},
                    $form->{AR_tax},        $form->{AR_paid},
                    $form->{AP},            $form->{AP_amount},
                    $form->{AP_tax},        $form->{AP_paid},
                    $form->{IC},            $form->{IC_sale},
                    $form->{IC_cogs},       $form->{IC_taxpart},
                    $form->{IC_income},     $form->{IC_expense},
                    $form->{IC_taxservice}
    ) {
    $form->{link} .= "${item}:" if ($item);
  }
  chop $form->{link};

  # strip blanks from accno
  map { $form->{$_} =~ s/ //g; } qw(accno);

  my ($query, $sth);

  if ($form->{id} eq "NULL") {
    $form->{id} = "";
  }

  $query = '
    SELECT accno
    FROM chart
    WHERE accno = ?';

  my @values = ($form->{accno});

  if ( $form->{id} ) {
    $query .= ' AND NOT id = ?';
    push(@values, $form->{id});
  }

  my ($accno) = selectrow_query($form, $dbh, $query, @values);

  if ($accno) {
    $form->error($::locale->text('Account number not unique!'));
  }


  if (!$form->{id} || $form->{id} eq "") {
    $query = qq|SELECT nextval('id')|;
    ($form->{"id"}) = selectrow_query($form, $dbh, $query);
    $query = qq|INSERT INTO chart (id, accno, link) VALUES (?, ?, ?)|;
    do_query($form, $dbh, $query, $form->{"id"}, $form->{"accno"}, '');
  }

  @values = ();


  if ($form->{id}) {

    # if charttype is heading make sure certain values are empty
    # specifically, if charttype is changed from an existing account, empty the
    # fields unnecessary for headings, so that e.g. heading doesn't appear in
    # drop-down menues due to still having a valid "link" entry

    if ( $form->{charttype} eq 'H' ) {
      $form->{link} = '';
      $form->{pos_bwa} = '';
      $form->{pos_bilanz} = '';
      $form->{pos_eur} = '';
      $form->{new_chart_id} = '';
      $form->{valid_from} = '';
    };

    $query = qq|UPDATE chart SET
                  accno = ?,
                  description = ?,
                  charttype = ?,
                  category = ?,
                  link = ?,
                  pos_bwa   = ?,
                  pos_bilanz = ?,
                  pos_eur = ?,
                  new_chart_id = ?,
                  valid_from = ?,
                  datevautomatik = ?
                WHERE id = ?|;

    @values = (
                  $form->{accno},
                  $form->{description},
                  $form->{charttype},
                  $form->{category},
                  $form->{link},
                  conv_i($form->{pos_bwa}),
                  conv_i($form->{pos_bilanz}),
                  conv_i($form->{pos_eur}),
                  conv_i($form->{new_chart_id}),
                  conv_date($form->{valid_from}),
                  ($form->{datevautomatik} eq 'T') ? 'true':'false',
                $form->{id},
    );


  }

  do_query($form, $dbh, $query, @values);

  #Save Taxkeys

  my @taxkeys = ();

  my $MAX_TRIES = 10; # Maximum count of taxkeys in form
  my $tk_count;

  READTAXKEYS:
  for $tk_count (0 .. $MAX_TRIES) {

    # Loop control

    # Check if the account already exists, else cancel

    print(STDERR "Keine Taxkeys weil ID =: $form->{id}\n");

    last READTAXKEYS if ( $form->{'id'} == 0);

    # check if there is a startdate
    if ( $form->{"taxkey_startdate_$tk_count"} eq '' ) {
      $tk_count++;
      next READTAXKEYS;
    }

    # Add valid taxkeys into the array
    push @taxkeys ,
      {
        id        => ($form->{"taxkey_id_$tk_count"} eq 'NEW') ? conv_i('') : conv_i($form->{"taxkey_id_$tk_count"}),
        tax_id    => conv_i($form->{"taxkey_tax_$tk_count"}),
        startdate => conv_date($form->{"taxkey_startdate_$tk_count"}),
        chart_id  => conv_i($form->{"id"}),
        pos_ustva => conv_i($form->{"taxkey_pos_ustva_$tk_count"}),
        delete    => ( $form->{"taxkey_del_$tk_count"} eq 'delete' ) ? '1' : '',
      };

    $tk_count++;
  }

  TAXKEY:
  for my $j (0 .. $#taxkeys){
    if ( defined $taxkeys[$j]{'id'} ){
      # delete Taxkey?

      if ($taxkeys[$j]{'delete'}){
        $query = qq{
          DELETE FROM taxkeys WHERE id = ?
        };

        @values = ($taxkeys[$j]{'id'});

        do_query($form, $dbh, $query, @values);

        next TAXKEY;
      }

      # UPDATE Taxkey

      $query = qq{
        UPDATE taxkeys
        SET taxkey_id = (SELECT taxkey FROM tax WHERE tax.id = ?),
            chart_id  = ?,
            tax_id    = ?,
            pos_ustva = ?,
            startdate = ?
        WHERE id = ?
      };
      @values = (
        $taxkeys[$j]{'tax_id'},
        $taxkeys[$j]{'chart_id'},
        $taxkeys[$j]{'tax_id'},
        $taxkeys[$j]{'pos_ustva'},
        $taxkeys[$j]{'startdate'},
        $taxkeys[$j]{'id'},
      );
      do_query($form, $dbh, $query, @values);
    }
    else {
      # INSERT Taxkey

      $query = qq{
        INSERT INTO taxkeys (
          taxkey_id,
          chart_id,
          tax_id,
          pos_ustva,
          startdate
        )
        VALUES ((SELECT taxkey FROM tax WHERE tax.id = ?), ?, ?, ?, ?)
      };
      @values = (
        $taxkeys[$j]{'tax_id'},
        $taxkeys[$j]{'chart_id'},
        $taxkeys[$j]{'tax_id'},
        $taxkeys[$j]{'pos_ustva'},
        $taxkeys[$j]{'startdate'},
      );

      do_query($form, $dbh, $query, @values);
    }

  }

  # Update chart.taxkey_id to the latest from taxkeys for this chart.
  $query = <<SQL;
    UPDATE chart
    SET taxkey_id = (
      SELECT taxkey_id
      FROM taxkeys
      WHERE taxkeys.chart_id = chart.id
      ORDER BY startdate DESC
      LIMIT 1
    )
    WHERE id = ?
SQL

  do_query($form, $dbh, $query, $form->{id});

  # commit
  my $rc = $dbh->commit;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();

  return $rc;
}

sub delete_account {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database, turn off AutoCommit
  my $dbh = $form->dbconnect_noauto($myconfig);

  my $query = qq|SELECT count(*) FROM acc_trans a
                 WHERE a.chart_id = ?|;
  my ($count) = selectrow_query($form, $dbh, $query, $form->{id});

  if ($count) {
    $dbh->disconnect;
    $main::lxdebug->leave_sub();
    return;
  }

  # set inventory_accno_id, income_accno_id, expense_accno_id to defaults
  foreach my $type (qw(inventory income expense)) {
    $query =
      qq|UPDATE parts | .
      qq|SET ${type}_accno_id = (SELECT ${type}_accno_id FROM defaults) | .
      qq|WHERE ${type}_accno_id = ?|;
    do_query($form, $dbh, $query, $form->{id});
  }

  $query = qq|DELETE FROM tax
              WHERE chart_id = ?|;
  do_query($form, $dbh, $query, $form->{id});

  # delete chart of account record
  $query = qq|DELETE FROM chart
              WHERE id = ?|;
  do_query($form, $dbh, $query, $form->{id});

  # delete account taxkeys
  $query = qq|DELETE FROM taxkeys
              WHERE chart_id = ?|;
  do_query($form, $dbh, $query, $form->{id});

  # commit and redirect
  my $rc = $dbh->commit;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();

  return $rc;
}

sub lead {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query = qq|SELECT id, lead
                 FROM leads
                 ORDER BY 2|;

  my $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    push @{ $form->{ALL} }, $ref;
  }

  $sth->finish;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub get_lead {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query =
    qq|SELECT l.id, l.lead | .
    qq|FROM leads l | .
    qq|WHERE l.id = ?|;
  my $sth = $dbh->prepare($query);
  $sth->execute($form->{id}) || $form->dberror($query . " ($form->{id})");

  my $ref = $sth->fetchrow_hashref("NAME_lc");

  map { $form->{$_} = $ref->{$_} } keys %$ref;

  $sth->finish;

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub save_lead {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;
  my ($query);

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my @values = ($form->{description});
  # id is the old record
  if ($form->{id}) {
    $query = qq|UPDATE leads SET
                lead = ?
                WHERE id = ?|;
    push(@values, $form->{id});
  } else {
    $query = qq|INSERT INTO leads
                (lead)
                VALUES (?)|;
  }
  do_query($form, $dbh, $query, @values);

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub delete_lead {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;
  my ($query);

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  $query = qq|DELETE FROM leads
              WHERE id = ?|;
  do_query($form, $dbh, $query, $form->{id});

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub language {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $return_list) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query =
    "SELECT id, description, template_code, article_code, " .
    "  output_numberformat, output_dateformat, output_longdates " .
    "FROM language ORDER BY description";

  my $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  my $ary = [];

  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    push(@{ $ary }, $ref);
  }

  $sth->finish;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();

  if ($return_list) {
    return @{$ary};
  } else {
    $form->{ALL} = $ary;
  }
}

sub get_language {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query =
    "SELECT description, template_code, article_code, " .
    "  output_numberformat, output_dateformat, output_longdates " .
    "FROM language WHERE id = ?";
  my $sth = $dbh->prepare($query);
  $sth->execute($form->{"id"}) || $form->dberror($query . " ($form->{id})");

  my $ref = $sth->fetchrow_hashref("NAME_lc");

  map { $form->{$_} = $ref->{$_} } keys %$ref;

  $sth->finish;

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub get_language_details {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $id) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query =
    "SELECT template_code, " .
    "  output_numberformat, output_dateformat, output_longdates " .
    "FROM language WHERE id = ?";
  my @res = selectrow_query($form, $dbh, $query, $id);
  $dbh->disconnect;

  $main::lxdebug->leave_sub();

  return @res;
}

sub save_language {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);
  my (@values, $query);

  map({ push(@values, $form->{$_}); }
      qw(description template_code article_code
         output_numberformat output_dateformat output_longdates));

  # id is the old record
  if ($form->{id}) {
    $query =
      "UPDATE language SET " .
      "  description = ?, template_code = ?, article_code = ?, " .
      "  output_numberformat = ?, output_dateformat = ?, " .
      "  output_longdates = ? " .
      "WHERE id = ?";
    push(@values, $form->{id});
  } else {
    $query =
      "INSERT INTO language (" .
      "  description, template_code, article_code, " .
      "  output_numberformat, output_dateformat, output_longdates" .
      ") VALUES (?, ?, ?, ?, ?, ?)";
  }
  do_query($form, $dbh, $query, @values);

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub delete_language {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;
  my $query;

  # connect to database
  my $dbh = $form->dbconnect_noauto($myconfig);

  foreach my $table (qw(generic_translations units_language)) {
    $query = qq|DELETE FROM $table WHERE language_id = ?|;
    do_query($form, $dbh, $query, $form->{"id"});
  }

  $query = "DELETE FROM language WHERE id = ?";
  do_query($form, $dbh, $query, $form->{"id"});

  $dbh->commit();
  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}


sub buchungsgruppe {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query = qq|SELECT id, description,
                 inventory_accno_id,
                 (SELECT accno FROM chart WHERE id = inventory_accno_id) AS inventory_accno,
                 income_accno_id_0,
                 (SELECT accno FROM chart WHERE id = income_accno_id_0) AS income_accno_0,
                 expense_accno_id_0,
                 (SELECT accno FROM chart WHERE id = expense_accno_id_0) AS expense_accno_0,
                 income_accno_id_1,
                 (SELECT accno FROM chart WHERE id = income_accno_id_1) AS income_accno_1,
                 expense_accno_id_1,
                 (SELECT accno FROM chart WHERE id = expense_accno_id_1) AS expense_accno_1,
                 income_accno_id_2,
                 (SELECT accno FROM chart WHERE id = income_accno_id_2) AS income_accno_2,
                 expense_accno_id_2,
                 (select accno FROM chart WHERE id = expense_accno_id_2) AS expense_accno_2,
                 income_accno_id_3,
                 (SELECT accno FROM chart WHERE id = income_accno_id_3) AS income_accno_3,
                 expense_accno_id_3,
                 (SELECT accno FROM chart WHERE id = expense_accno_id_3) AS expense_accno_3
                 FROM buchungsgruppen
                 ORDER BY sortkey|;

  my $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  $form->{ALL} = [];
  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    push @{ $form->{ALL} }, $ref;
  }

  $sth->finish;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub get_buchungsgruppe {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;
  my $query;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  if ($form->{id}) {
    $query =
      qq|SELECT description, inventory_accno_id,
         (SELECT accno FROM chart WHERE id = inventory_accno_id) AS inventory_accno,
         income_accno_id_0,
         (SELECT accno FROM chart WHERE id = income_accno_id_0) AS income_accno_0,
         expense_accno_id_0,
         (SELECT accno FROM chart WHERE id = expense_accno_id_0) AS expense_accno_0,
         income_accno_id_1,
         (SELECT accno FROM chart WHERE id = income_accno_id_1) AS income_accno_1,
         expense_accno_id_1,
         (SELECT accno FROM chart WHERE id = expense_accno_id_1) AS expense_accno_1,
         income_accno_id_2,
         (SELECT accno FROM chart WHERE id = income_accno_id_2) AS income_accno_2,
         expense_accno_id_2,
         (select accno FROM chart WHERE id = expense_accno_id_2) AS expense_accno_2,
         income_accno_id_3,
         (SELECT accno FROM chart WHERE id = income_accno_id_3) AS income_accno_3,
         expense_accno_id_3,
         (SELECT accno FROM chart WHERE id = expense_accno_id_3) AS expense_accno_3
         FROM buchungsgruppen
         WHERE id = ?|;
    my $sth = $dbh->prepare($query);
    $sth->execute($form->{id}) || $form->dberror($query . " ($form->{id})");

    my $ref = $sth->fetchrow_hashref("NAME_lc");

    map { $form->{$_} = $ref->{$_} } keys %$ref;

    $sth->finish;

    $query =
      qq|SELECT count(id) = 0 AS orphaned
         FROM parts
         WHERE buchungsgruppen_id = ?|;
    ($form->{orphaned}) = selectrow_query($form, $dbh, $query, $form->{id});
  }

  $query = "SELECT inventory_accno_id, income_accno_id, expense_accno_id ".
    "FROM defaults";
  ($form->{"std_inventory_accno_id"}, $form->{"std_income_accno_id"},
   $form->{"std_expense_accno_id"}) = selectrow_query($form, $dbh, $query);

  my $module = "IC";
  $query = qq|SELECT c.accno, c.description, c.link, c.id,
              d.inventory_accno_id, d.income_accno_id, d.expense_accno_id
              FROM chart c, defaults d
              WHERE c.link LIKE '%$module%'
              ORDER BY c.accno|;


  my $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);
  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    foreach my $key (split(/:/, $ref->{link})) {
      if (!$form->{"std_inventory_accno_id"} && ($key eq "IC")) {
        $form->{"std_inventory_accno_id"} = $ref->{"id"};
      }
      if ($key =~ /$module/) {
        if (   ($ref->{id} eq $ref->{inventory_accno_id})
            || ($ref->{id} eq $ref->{income_accno_id})
            || ($ref->{id} eq $ref->{expense_accno_id})) {
          push @{ $form->{"${module}_links"}{$key} },
            { accno       => $ref->{accno},
              description => $ref->{description},
              selected    => "selected",
              id          => $ref->{id} };
        } else {
          push @{ $form->{"${module}_links"}{$key} },
            { accno       => $ref->{accno},
              description => $ref->{description},
              selected    => "",
              id          => $ref->{id} };
        }
      }
    }
  }
  $sth->finish;


  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub save_buchungsgruppe {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my @values = ($form->{description}, $form->{inventory_accno_id},
                $form->{income_accno_id_0}, $form->{expense_accno_id_0},
                $form->{income_accno_id_1}, $form->{expense_accno_id_1},
                $form->{income_accno_id_2}, $form->{expense_accno_id_2},
                $form->{income_accno_id_3}, $form->{expense_accno_id_3});

  my $query;

  # id is the old record
  if ($form->{id}) {
    $query = qq|UPDATE buchungsgruppen SET
                description = ?, inventory_accno_id = ?,
                income_accno_id_0 = ?, expense_accno_id_0 = ?,
                income_accno_id_1 = ?, expense_accno_id_1 = ?,
                income_accno_id_2 = ?, expense_accno_id_2 = ?,
                income_accno_id_3 = ?, expense_accno_id_3 = ?
                WHERE id = ?|;
    push(@values, $form->{id});
  } else {
    $query = qq|SELECT COALESCE(MAX(sortkey) + 1, 1) FROM buchungsgruppen|;
    my ($sortkey) = $dbh->selectrow_array($query);
    $form->dberror($query) if ($dbh->err);
    push(@values, $sortkey);
    $query = qq|INSERT INTO buchungsgruppen
                (description, inventory_accno_id,
                income_accno_id_0, expense_accno_id_0,
                income_accno_id_1, expense_accno_id_1,
                income_accno_id_2, expense_accno_id_2,
                income_accno_id_3, expense_accno_id_3,
                sortkey)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)|;
  }
  do_query($form, $dbh, $query, @values);

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub delete_buchungsgruppe {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query = qq|DELETE FROM buchungsgruppen WHERE id = ?|;
  do_query($form, $dbh, $query, $form->{id});

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub swap_sortkeys {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $table) = @_;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  my $query =
    qq|SELECT
       (SELECT sortkey FROM $table WHERE id = ?) AS sortkey1,
       (SELECT sortkey FROM $table WHERE id = ?) AS sortkey2|;
  my @values   = ($form->{"id1"}, $form->{"id2"});
  my @sortkeys = selectrow_query($form, $dbh, $query, @values);

  $query  = qq|UPDATE $table SET sortkey = ? WHERE id = ?|;
  my $sth = prepare_query($form, $dbh, $query);

  do_statement($form, $sth, $query, $sortkeys[1], $form->{"id1"});
  do_statement($form, $sth, $query, $sortkeys[0], $form->{"id2"});

  $sth->finish();

  $dbh->commit();

  $main::lxdebug->leave_sub();
}

sub prepare_template_filename {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  my ($filename, $display_filename);

  if ($form->{type} eq "stylesheet") {
    $filename = "css/$myconfig->{stylesheet}";
    $display_filename = $myconfig->{stylesheet};

  } else {
    $filename = $form->{formname};

    if ($form->{language}) {
      my ($id, $template_code) = split(/--/, $form->{language});
      $filename .= "_${template_code}";
    }

    if ($form->{printer}) {
      my ($id, $template_code) = split(/--/, $form->{printer});
      $filename .= "_${template_code}";
    }

    $filename .= "." . ($form->{format} eq "html" ? "html" : "tex");
    if ($form->{"formname"} =~ m|\.\.| || $form->{"formname"} =~ m|^/|) {
      $filename =~ s|.*/||;
    }
    $display_filename = $filename;
    $filename = SL::DB::Default->get->templates . "/$filename";
  }

  $main::lxdebug->leave_sub();

  return ($filename, $display_filename);
}


sub load_template {
  $main::lxdebug->enter_sub();

  my ($self, $filename) = @_;

  my ($content, $lines) = ("", 0);

  local *TEMPLATE;

  if (open(TEMPLATE, $filename)) {
    while (<TEMPLATE>) {
      $content .= $_;
      $lines++;
    }
    close(TEMPLATE);
  }

  $content = Encode::decode('utf-8-strict', $content);

  $main::lxdebug->leave_sub();

  return ($content, $lines);
}

sub save_template {
  $main::lxdebug->enter_sub();

  my ($self, $filename, $content) = @_;

  local *TEMPLATE;

  my $error = "";

  if (open(TEMPLATE, ">", $filename)) {
    $content = Encode::encode('utf-8-strict', $content);
    $content =~ s/\r\n/\n/g;
    print(TEMPLATE $content);
    close(TEMPLATE);
  } else {
    $error = $!;
  }

  $main::lxdebug->leave_sub();

  return $error;
}

sub save_preferences {
  $main::lxdebug->enter_sub();

  my ($self, $form) = @_;

  my $employee = SL::DB::Manager::Employee->find_by(login => $form->{login});
  $employee->update_attributes(name => $form->{name});

  my $user = SL::DB::Manager::AuthUser->find_by(login => $form->{login});
  $user->update_attributes(
    config_values => {
      map { ($_ => $form->{$_}) } SL::DB::AuthUser::CONFIG_VARS(),
    });

  $main::lxdebug->leave_sub();

  return 1;
}

sub get_defaults {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  my $dbh      = $params{dbh} || $form->get_standard_dbh($myconfig);

  my $defaults = selectfirst_hashref_query($form, $dbh, qq|SELECT * FROM defaults|) || {};

  $defaults->{weightunit} ||= 'kg';

  $main::lxdebug->leave_sub();

  return $defaults;
}

sub closedto {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  my $dbh = $form->dbconnect($myconfig);

  my $query = qq|SELECT closedto, max_future_booking_interval, revtrans FROM defaults|;
  my $sth   = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  ($form->{closedto}, $form->{max_future_booking_interval}, $form->{revtrans}) = $sth->fetchrow_array;

  $sth->finish;

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub closebooks {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  my $dbh = $form->dbconnect($myconfig);

  my ($query, @values);

  if ($form->{revtrans}) {
    $query = qq|UPDATE defaults SET closedto = NULL, revtrans = '1'|;

  } elsif ($form->{closedto}) {
    $query = qq|UPDATE defaults SET closedto = ?, max_future_booking_interval = ?, revtrans = '0'|;
    @values = (conv_date($form->{closedto}), conv_date($form->{max_future_booking_interval}));

  } else {
    $query = qq|UPDATE defaults SET closedto = NULL, revtrans = '0'|;
  }

  # set close in defaults
  do_query($form, $dbh, $query, @values);

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub get_base_unit {
  my ($self, $units, $unit_name, $factor) = @_;

  $factor = 1 unless ($factor);

  my $unit = $units->{$unit_name};

  if (!defined($unit) || !$unit->{"base_unit"} ||
      ($unit_name eq $unit->{"base_unit"})) {
    return ($unit_name, $factor);
  }

  return AM->get_base_unit($units, $unit->{"base_unit"}, $factor * $unit->{"factor"});
}

sub retrieve_units {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $prefix) = @_;
  $prefix ||= '';

  my $dbh = $form->get_standard_dbh;

  my $query = "SELECT *, base_unit AS original_base_unit FROM units";

  my $sth = prepare_execute_query($form, $dbh, $query);

  my $units = {};
  while (my $ref = $sth->fetchrow_hashref()) {
    $units->{$ref->{"name"}} = $ref;
  }
  $sth->finish();

  my $query_lang = "SELECT id, template_code FROM language ORDER BY description";
  $sth = $dbh->prepare($query_lang);
  $sth->execute() || $form->dberror($query_lang);
  my @languages;
  while (my $ref = $sth->fetchrow_hashref()) {
    push(@languages, $ref);
  }
  $sth->finish();

  $query_lang = "SELECT ul.localized, ul.localized_plural, l.id, l.template_code " .
    "FROM units_language ul " .
    "LEFT JOIN language l ON ul.language_id = l.id " .
    "WHERE ul.unit = ?";
  $sth = $dbh->prepare($query_lang);

  foreach my $unit (values(%{$units})) {
    ($unit->{"${prefix}base_unit"}, $unit->{"${prefix}factor"}) = AM->get_base_unit($units, $unit->{"name"});

    $unit->{"LANGUAGES"} = {};
    foreach my $lang (@languages) {
      $unit->{"LANGUAGES"}->{$lang->{"template_code"}} = { "template_code" => $lang->{"template_code"} };
    }

    $sth->execute($unit->{"name"}) || $form->dberror($query_lang . " (" . $unit->{"name"} . ")");
    while (my $ref = $sth->fetchrow_hashref()) {
      map({ $unit->{"LANGUAGES"}->{$ref->{"template_code"}}->{$_} = $ref->{$_} } keys(%{$ref}));
    }
  }
  $sth->finish;

  $main::lxdebug->leave_sub();

  return $units;
}

sub retrieve_all_units {
  $main::lxdebug->enter_sub();

  my $self = shift;

  if (!$::request->{cache}{all_units}) {
    $::request->{cache}{all_units} = $self->retrieve_units(\%main::myconfig, $main::form);
  }

  $main::lxdebug->leave_sub();

  return $::request->{cache}{all_units};
}


sub translate_units {
  $main::lxdebug->enter_sub();

  my ($self, $form, $template_code, $unit, $amount) = @_;

  my $units = $self->retrieve_units(\%main::myconfig, $form);

  my $h = $units->{$unit}->{"LANGUAGES"}->{$template_code};
  my $new_unit = $unit;
  if ($h) {
    if (($amount != 1) && $h->{"localized_plural"}) {
      $new_unit = $h->{"localized_plural"};
    } elsif ($h->{"localized"}) {
      $new_unit = $h->{"localized"};
    }
  }

  $main::lxdebug->leave_sub();

  return $new_unit;
}

sub units_in_use {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $units) = @_;

  my $dbh = $form->dbconnect($myconfig);

  map({ $_->{"in_use"} = 0; } values(%{$units}));

  foreach my $unit (values(%{$units})) {
    my $base_unit = $unit->{"original_base_unit"};
    while ($base_unit) {
      $units->{$base_unit}->{"in_use"} = 1;
      $units->{$base_unit}->{"DEPENDING_UNITS"} = [] unless ($units->{$base_unit}->{"DEPENDING_UNITS"});
      push(@{$units->{$base_unit}->{"DEPENDING_UNITS"}}, $unit->{"name"});
      $base_unit = $units->{$base_unit}->{"original_base_unit"};
    }
  }

  foreach my $unit (values(%{$units})) {
    map({ $_ = $dbh->quote($_); } @{$unit->{"DEPENDING_UNITS"}});

    foreach my $table (qw(parts invoice orderitems)) {
      my $query = "SELECT COUNT(*) FROM $table WHERE unit ";

      if (0 == scalar(@{$unit->{"DEPENDING_UNITS"}})) {
        $query .= "= " . $dbh->quote($unit->{"name"});
      } else {
        $query .= "IN (" . $dbh->quote($unit->{"name"}) . "," .
          join(",", map({ $dbh->quote($_) } @{$unit->{"DEPENDING_UNITS"}})) . ")";
      }

      my ($count) = $dbh->selectrow_array($query);
      $form->dberror($query) if ($dbh->err);

      if ($count) {
        $unit->{"in_use"} = 1;
        last;
      }
    }
  }

  $dbh->disconnect();

  $main::lxdebug->leave_sub();
}

sub convertible_units {
  $main::lxdebug->enter_sub();

  my $self        = shift;
  my $units       = shift;
  my $filter_unit = shift;
  my $not_smaller = shift;

  my $conv_units = [];

  $filter_unit = $units->{$filter_unit};

  foreach my $name (sort { lc $a cmp lc $b } keys %{ $units }) {
    my $unit = $units->{$name};

    if (($unit->{base_unit} eq $filter_unit->{base_unit}) &&
        (!$not_smaller || ($unit->{factor} >= $filter_unit->{factor}))) {
      push @{$conv_units}, $unit;
    }
  }

  my @sorted = sort { $b->{factor} <=> $a->{factor} } @{ $conv_units };

  $main::lxdebug->leave_sub();

  return \@sorted;
}

# if $a is translatable to $b, return the factor between them.
# else return 1
sub convert_unit {
  $main::lxdebug->enter_sub(2);
  my ($this, $a, $b, $all_units) = @_;

  if (!$all_units) {
    $all_units = $this->retrieve_all_units;
  }

  $main::lxdebug->leave_sub(2) and return 0 unless $a && $b;
  $main::lxdebug->leave_sub(2) and return 0 unless $all_units->{$a} && $all_units->{$b};
  $main::lxdebug->leave_sub(2) and return 0 unless $all_units->{$a}{base_unit} eq $all_units->{$b}{base_unit};
  $main::lxdebug->leave_sub(2) and return $all_units->{$a}{factor} / $all_units->{$b}{factor};
}

sub unit_select_data {
  $main::lxdebug->enter_sub();

  my ($self, $units, $selected, $empty_entry, $convertible_into) = @_;

  my $select = [];

  if ($empty_entry) {
    push(@{$select}, { "name" => "", "base_unit" => "", "factor" => "", "selected" => "" });
  }

  foreach my $unit (sort({ $units->{$a}->{"sortkey"} <=> $units->{$b}->{"sortkey"} } keys(%{$units}))) {
    if (!$convertible_into ||
        ($units->{$convertible_into} &&
         ($units->{$convertible_into}->{base_unit} eq $units->{$unit}->{base_unit}))) {
      push @{$select}, { "name"      => $unit,
                         "base_unit" => $units->{$unit}->{"base_unit"},
                         "factor"    => $units->{$unit}->{"factor"},
                         "selected"  => ($unit eq $selected) ? "selected" : "" };
    }
  }

  $main::lxdebug->leave_sub();

  return $select;
}

sub unit_select_html {
  $main::lxdebug->enter_sub();

  my ($self, $units, $name, $selected, $convertible_into) = @_;

  my $select = "<select name=${name}>";

  foreach my $unit (sort({ $units->{$a}->{"sortkey"} <=> $units->{$b}->{"sortkey"} } keys(%{$units}))) {
    if (!$convertible_into ||
        ($units->{$convertible_into} &&
         ($units->{$convertible_into}->{"base_unit"} eq $units->{$unit}->{"base_unit"}))) {
      $select .= "<option" . (($unit eq $selected) ? " selected" : "") . ">${unit}</option>";
    }
  }
  $select .= "</select>";

  $main::lxdebug->leave_sub();

  return $select;
}

sub sum_with_unit {
  $main::lxdebug->enter_sub();

  my $self  = shift;

  my $units = $self->retrieve_all_units();

  my $sum   = 0;
  my $base_unit;

  while (2 <= scalar(@_)) {
    my $qty  = shift(@_);
    my $unit = $units->{shift(@_)};

    croak "No unit defined with name $unit" if (!defined $unit);

    if (!$base_unit) {
      $base_unit = $unit->{base_unit};
    } elsif ($base_unit ne $unit->{base_unit}) {
      croak "Adding values with incompatible base units $base_unit/$unit->{base_unit}";
    }

    $sum += $qty * $unit->{factor};
  }

  $main::lxdebug->leave_sub();

  return wantarray ? ($sum, $base_unit) : $sum;
}

sub add_unit {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $name, $base_unit, $factor, $languages) = @_;

  my $dbh = $form->dbconnect_noauto($myconfig);

  my $query = qq|SELECT COALESCE(MAX(sortkey), 0) + 1 FROM units|;
  my ($sortkey) = selectrow_query($form, $dbh, $query);

  $query = "INSERT INTO units (name, base_unit, factor, sortkey) " .
    "VALUES (?, ?, ?, ?)";
  do_query($form, $dbh, $query, $name, $base_unit, $factor, $sortkey);

  if ($languages) {
    $query = "INSERT INTO units_language (unit, language_id, localized, localized_plural) VALUES (?, ?, ?, ?)";
    my $sth = $dbh->prepare($query);
    foreach my $lang (@{$languages}) {
      my @values = ($name, $lang->{"id"}, $lang->{"localized"}, $lang->{"localized_plural"});
      $sth->execute(@values) || $form->dberror($query . " (" . join(", ", @values) . ")");
    }
    $sth->finish();
  }

  $dbh->commit();
  $dbh->disconnect();

  $main::lxdebug->leave_sub();
}

sub save_units {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $units, $delete_units) = @_;

  my $dbh = $form->dbconnect_noauto($myconfig);

  my ($base_unit, $unit, $sth, $query);

  $query = "DELETE FROM units_language";
  $dbh->do($query) || $form->dberror($query);

  if ($delete_units && (0 != scalar(@{$delete_units}))) {
    $query = "DELETE FROM units WHERE name IN (";
    map({ $query .= "?," } @{$delete_units});
    substr($query, -1, 1) = ")";
    $dbh->do($query, undef, @{$delete_units}) ||
      $form->dberror($query . " (" . join(", ", @{$delete_units}) . ")");
  }

  $query = "UPDATE units SET name = ?, base_unit = ?, factor = ? WHERE name = ?";
  $sth = $dbh->prepare($query);

  my $query_lang = "INSERT INTO units_language (unit, language_id, localized, localized_plural) VALUES (?, ?, ?, ?)";
  my $sth_lang = $dbh->prepare($query_lang);

  foreach $unit (values(%{$units})) {
    $unit->{"depth"} = 0;
    my $base_unit = $unit;
    while ($base_unit->{"base_unit"}) {
      $unit->{"depth"}++;
      $base_unit = $units->{$base_unit->{"base_unit"}};
    }
  }

  foreach $unit (sort({ $a->{"depth"} <=> $b->{"depth"} } values(%{$units}))) {
    if ($unit->{"LANGUAGES"}) {
      foreach my $lang (@{$unit->{"LANGUAGES"}}) {
        next unless ($lang->{"id"} && $lang->{"localized"});
        my @values = ($unit->{"name"}, $lang->{"id"}, $lang->{"localized"}, $lang->{"localized_plural"});
        $sth_lang->execute(@values) || $form->dberror($query_lang . " (" . join(", ", @values) . ")");
      }
    }

    next if ($unit->{"unchanged_unit"});

    my @values = ($unit->{"name"}, $unit->{"base_unit"}, $unit->{"factor"}, $unit->{"old_name"});
    $sth->execute(@values) || $form->dberror($query . " (" . join(", ", @values) . ")");
  }

  $sth->finish();
  $sth_lang->finish();
  $dbh->commit();
  $dbh->disconnect();

  $main::lxdebug->leave_sub();
}

sub taxes {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query = qq|SELECT
                   t.id,
                   t.taxkey,
                   t.taxdescription,
                   round(t.rate * 100, 2) AS rate,
                   (SELECT accno FROM chart WHERE id = chart_id) AS taxnumber,
                   (SELECT description FROM chart WHERE id = chart_id) AS account_description
                 FROM tax t
                 ORDER BY taxkey, rate|;

  my $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  $form->{TAX} = [];
  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    push @{ $form->{TAX} }, $ref;
  }

  $sth->finish;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub get_tax_accounts {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  my $dbh = $form->dbconnect($myconfig);

  # get Accounts from chart
  my $query = qq{ SELECT
                 id,
                 accno || ' - ' || description AS taxaccount
               FROM chart
               WHERE link LIKE '%_tax%'
               ORDER BY accno
             };

  my $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  $form->{ACCOUNTS} = [];
  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    push @{ $form->{ACCOUNTS} }, $ref;
  }

  $sth->finish;

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub get_tax {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query = qq|SELECT
                   taxkey,
                   taxdescription,
                   round(rate * 100, 2) AS rate,
                   chart_id,
                   chart_categories,
                   (id IN (SELECT tax_id
                           FROM acc_trans)) AS tax_already_used
                 FROM tax
                 WHERE id = ? |;

  my $sth = $dbh->prepare($query);
  $sth->execute($form->{id}) || $form->dberror($query . " ($form->{id})");

  my $ref = $sth->fetchrow_hashref("NAME_lc");

  map { $form->{$_} = $ref->{$_} } keys %$ref;

  $sth->finish;

  # see if it is used by a taxkey
  $query = qq|SELECT count(*) FROM taxkeys
              WHERE tax_id = ? AND chart_id >0|;

  ($form->{orphaned}) = selectrow_query($form, $dbh, $query, $form->{id});

  $form->{orphaned} = !$form->{orphaned};
  $sth->finish;

  if (!$form->{orphaned} ) {
    $query = qq|SELECT DISTINCT c.id, c.accno
                FROM taxkeys tk
                JOIN   tax t ON (t.id = tk.tax_id)
                JOIN chart c ON (c.id = tk.chart_id)
                WHERE tk.tax_id = ?|;

    $sth = $dbh->prepare($query);
    $sth->execute($form->{id}) || $form->dberror($query . " ($form->{id})");

    $form->{TAXINUSE} = [];
    while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
      push @{ $form->{TAXINUSE} }, $ref;
    }

    $sth->finish;
  }

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub save_tax {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;
  my $query;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  $form->{rate} = $form->{rate} / 100;

  my $chart_categories = '';
  $chart_categories .= 'A' if $form->{asset};
  $chart_categories .= 'L' if $form->{liability};
  $chart_categories .= 'Q' if $form->{equity};
  $chart_categories .= 'I' if $form->{revenue};
  $chart_categories .= 'E' if $form->{expense};
  $chart_categories .= 'C' if $form->{costs};

  my @values = ($form->{taxkey}, $form->{taxdescription}, $form->{rate}, $form->{chart_id}, $form->{chart_id}, $chart_categories);
  if ($form->{id} ne "") {
    $query = qq|UPDATE tax SET
                  taxkey         = ?,
                  taxdescription = ?,
                  rate           = ?,
                  chart_id       = ?,
                  taxnumber      = (SELECT accno FROM chart WHERE id= ? ),
                  chart_categories = ?
                WHERE id = ?|;
    push(@values, $form->{id});

  } else {
    #ok
    $query = qq|INSERT INTO tax (
                  taxkey,
                  taxdescription,
                  rate,
                  chart_id,
                  taxnumber,
                  chart_categories
                )
                VALUES (?, ?, ?, ?, (SELECT accno FROM chart WHERE id = ?), ? )|;
  }
  do_query($form, $dbh, $query, @values);

  $dbh->commit();

  $main::lxdebug->leave_sub();
}

sub delete_tax {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;
  my $query;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  $query = qq|DELETE FROM tax
              WHERE id = ?|;
  do_query($form, $dbh, $query, $form->{id});

  $dbh->commit();

  $main::lxdebug->leave_sub();
}

sub save_price_factor {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  my $query;
  my @values = ($form->{description}, conv_i($form->{factor}));

  if ($form->{id}) {
    $query = qq|UPDATE price_factors SET description = ?, factor = ? WHERE id = ?|;
    push @values, conv_i($form->{id});

  } else {
    $query = qq|INSERT INTO price_factors (description, factor, sortkey) VALUES (?, ?, (SELECT COALESCE(MAX(sortkey), 0) + 1 FROM price_factors))|;
  }

  do_query($form, $dbh, $query, @values);

  $dbh->commit();

  $main::lxdebug->leave_sub();
}

sub get_all_price_factors {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  $form->{PRICE_FACTORS} = selectall_hashref_query($form, $dbh, qq|SELECT * FROM price_factors ORDER BY sortkey|);

  $main::lxdebug->leave_sub();
}

sub get_price_factor {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  my $query = qq|SELECT description, factor,
                   ((SELECT COUNT(*) FROM parts      WHERE price_factor_id = ?) +
                    (SELECT COUNT(*) FROM invoice    WHERE price_factor_id = ?) +
                    (SELECT COUNT(*) FROM orderitems WHERE price_factor_id = ?)) = 0 AS orphaned
                 FROM price_factors WHERE id = ?|;

  ($form->{description}, $form->{factor}, $form->{orphaned}) = selectrow_query($form, $dbh, $query, (conv_i($form->{id})) x 4);

  $main::lxdebug->leave_sub();
}

sub delete_price_factor {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  do_query($form, $dbh, qq|DELETE FROM price_factors WHERE id = ?|, conv_i($form->{id}));
  $dbh->commit();

  $main::lxdebug->leave_sub();
}

sub save_warehouse {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  my ($query, @values, $sth);

  if (!$form->{id}) {
    $query        = qq|SELECT nextval('id')|;
    ($form->{id}) = selectrow_query($form, $dbh, $query);

    $query        = qq|INSERT INTO warehouse (id, sortkey) VALUES (?, (SELECT COALESCE(MAX(sortkey), 0) + 1 FROM warehouse))|;
    do_query($form, $dbh, $query, $form->{id});
  }

  do_query($form, $dbh, qq|UPDATE warehouse SET description = ?, invalid = ? WHERE id = ?|,
           $form->{description}, $form->{invalid} ? 't' : 'f', conv_i($form->{id}));

  if (0 < $form->{number_of_new_bins}) {
    my ($num_existing_bins) = selectfirst_array_query($form, $dbh, qq|SELECT COUNT(*) FROM bin WHERE warehouse_id = ?|, $form->{id});
    $query = qq|INSERT INTO bin (warehouse_id, description) VALUES (?, ?)|;
    $sth   = prepare_query($form, $dbh, $query);

    foreach my $i (1..$form->{number_of_new_bins}) {
      do_statement($form, $sth, $query, conv_i($form->{id}), "$form->{prefix}" . ($i + $num_existing_bins));
    }

    $sth->finish();
  }

  $dbh->commit();

  $main::lxdebug->leave_sub();
}

sub save_bins {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  my ($query, @values, $commit_necessary, $sth);

  @values = map { $form->{"id_${_}"} } grep { $form->{"delete_${_}"} } (1..$form->{rowcount});

  if (@values) {
    $query = qq|DELETE FROM bin WHERE id IN (| . join(', ', ('?') x scalar(@values)) . qq|)|;
    do_query($form, $dbh, $query, @values);

    $commit_necessary = 1;
  }

  $query = qq|UPDATE bin SET description = ? WHERE id = ?|;
  $sth   = prepare_query($form, $dbh, $query);

  foreach my $row (1..$form->{rowcount}) {
    next if ($form->{"delete_${row}"});

    do_statement($form, $sth, $query, $form->{"description_${row}"}, conv_i($form->{"id_${row}"}));

    $commit_necessary = 1;
  }

  $sth->finish();

  $dbh->commit() if ($commit_necessary);

  $main::lxdebug->leave_sub();
}

sub delete_warehouse {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  my $id      = conv_i($form->{id});
  my $query   = qq|SELECT i.bin_id FROM inventory i WHERE i.bin_id IN (SELECT b.id FROM bin b WHERE b.warehouse_id = ?) LIMIT 1|;
  my ($count) = selectrow_query($form, $dbh, $query, $id);

  if ($count) {
    $main::lxdebug->leave_sub();
    return 0;
  }

  do_query($form, $dbh, qq|DELETE FROM bin       WHERE warehouse_id = ?|, conv_i($form->{id}));
  do_query($form, $dbh, qq|DELETE FROM warehouse WHERE id           = ?|, conv_i($form->{id}));

  $dbh->commit();

  $main::lxdebug->leave_sub();

  return 1;
}

sub get_all_warehouses {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  my $query = qq|SELECT w.id, w.description, w.invalid,
                   (SELECT COUNT(b.description) FROM bin b WHERE b.warehouse_id = w.id) AS number_of_bins
                 FROM warehouse w
                 ORDER BY w.sortkey|;

  $form->{WAREHOUSES} = selectall_hashref_query($form, $dbh, $query);

  $main::lxdebug->leave_sub();
}

sub get_warehouse {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  my $id    = conv_i($form->{id});
  my $query = qq|SELECT w.description, w.invalid
                 FROM warehouse w
                 WHERE w.id = ?|;

  my $ref   = selectfirst_hashref_query($form, $dbh, $query, $id);

  map { $form->{$_} = $ref->{$_} } keys %{ $ref };

  $query = <<SQL;
    SELECT b.*,
      (   EXISTS(SELECT i.bin_id FROM inventory i WHERE i.bin_id = b.id LIMIT 1)
       OR EXISTS(SELECT p.bin_id FROM parts     p WHERE p.bin_id = b.id LIMIT 1))
      AS in_use
    FROM bin b
    WHERE b.warehouse_id = ?
SQL

  $form->{BINS} = selectall_hashref_query($form, $dbh, $query, conv_i($form->{id}));

  $main::lxdebug->leave_sub();
}

1;
