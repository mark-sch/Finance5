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
# General ledger backend code
#
# CHANGE LOG:
#   DS. 2000-07-04  Created
#   DS. 2001-06-12  Changed relations from accno to chart_id
#
#======================================================================

package GL;

use Data::Dumper;
use SL::DATEV qw(:CONSTANTS);
use SL::DBUtils;

use strict;

sub delete_transaction {
  my ($self, $myconfig, $form) = @_;
  $main::lxdebug->enter_sub();

  # connect to database
  my $dbh = $form->dbconnect_noauto($myconfig);

  # acc_trans entries are deleted by database triggers.
  do_query($form, $dbh, qq|DELETE FROM gl WHERE id = ?|, conv_i($form->{id}));

  # commit and redirect
  my $rc = $dbh->commit;
  $dbh->disconnect;
  $main::lxdebug->leave_sub();

  $rc;

}

sub post_transaction {
  my ($self, $myconfig, $form) = @_;
  $main::lxdebug->enter_sub();

  my ($debit, $credit) = (0, 0);
  my $project_id;

  my $i;

  # connect to database, turn off AutoCommit
  my $dbh = $form->dbconnect_noauto($myconfig);

  # post the transaction
  # make up a unique handle and store in reference field
  # then retrieve the record based on the unique handle to get the id
  # replace the reference field with the actual variable
  # add records to acc_trans

  # if there is a $form->{id} replace the old transaction
  # delete all acc_trans entries and add the new ones

  if (!$form->{taxincluded}) {
    $form->{taxincluded} = 0;
  }

  my ($query, $sth, @values, $taxkey, $rate, $posted);

  if ($form->{id}) {

    # delete individual transactions
    $query = qq|DELETE FROM acc_trans WHERE trans_id = ?|;
    @values = (conv_i($form->{id}));
    do_query($form, $dbh, $query, @values);

  } else {
    $query = qq|SELECT nextval('glid')|;
    ($form->{id}) = selectrow_query($form, $dbh, $query);

    $query =
      qq|INSERT INTO gl (id, employee_id) | .
      qq|VALUES (?, (SELECT id FROM employee WHERE login = ?))|;
    @values = ($form->{id}, $form->{login});
    do_query($form, $dbh, $query, @values);
  }

  my ($null, $department_id) = split(/--/, $form->{department});

  $form->{ob_transaction} *= 1;
  $form->{cb_transaction} *= 1;

  $query =
    qq|UPDATE gl SET
         reference = ?, description = ?, notes = ?,
         transdate = ?, department_id = ?, taxincluded = ?,
         storno = ?, storno_id = ?, ob_transaction = ?, cb_transaction = ?
       WHERE id = ?|;

  @values = ($form->{reference}, $form->{description}, $form->{notes},
             conv_date($form->{transdate}), conv_i($department_id), $form->{taxincluded} ? 't' : 'f',
             $form->{storno} ? 't' : 'f', conv_i($form->{storno_id}), $form->{ob_transaction} ? 't' : 'f', $form->{cb_transaction} ? 't' : 'f',
             conv_i($form->{id}));
  do_query($form, $dbh, $query, @values);

  # insert acc_trans transactions
  for $i (1 .. $form->{rowcount}) {
    # extract accno
    my ($accno) = split(/--/, $form->{"accno_$i"});
    ($form->{"tax_id_$i"}) = split(/--/, $form->{"taxchart_$i"});
    if ($form->{"tax_id_$i"} ne "") {
      $query = qq|SELECT taxkey, rate FROM tax WHERE id = ?|;
      ($taxkey, $rate) = selectrow_query($form, $dbh, $query, conv_i($form->{"tax_id_$i"}));
    }

    my $amount = 0;
    my $debit  = $form->{"debit_$i"};
    my $credit = $form->{"credit_$i"};
    my $tax    = $form->{"tax_$i"};

    if ($credit) {
      $amount = $credit;
      $posted = 0;
    }
    if ($debit) {
      $amount = $debit * -1;
      $tax    = $tax * -1;
      $posted = 0;
    }

    $project_id = conv_i($form->{"project_id_$i"});

    # if there is an amount, add the record
    if ($amount != 0) {
      $query =
        qq|INSERT INTO acc_trans (trans_id, chart_id, amount, transdate,
                                  source, memo, project_id, taxkey, ob_transaction, cb_transaction, tax_id, chart_link)
           VALUES (?, (SELECT id FROM chart WHERE accno = ?),
                   ?, ?, ?, ?, ?, ?, ?, ?, ?, (SELECT link FROM chart WHERE accno = ?))|;
      @values = (conv_i($form->{id}), $accno, $amount, conv_date($form->{transdate}),
                 $form->{"source_$i"}, $form->{"memo_$i"}, $project_id, $taxkey, $form->{ob_transaction} ? 't' : 'f', $form->{cb_transaction} ? 't' : 'f', conv_i($form->{"tax_id_$i"}), $accno);
      do_query($form, $dbh, $query, @values);
    }

    if ($tax != 0) {
      # add taxentry
      $query =
        qq|INSERT INTO acc_trans (trans_id, chart_id, amount, transdate,
                                  source, memo, project_id, taxkey, tax_id, chart_link)
           VALUES (?, (SELECT chart_id FROM tax WHERE id = ?),
                   ?, ?, ?, ?, ?, ?, ?, (SELECT link
                                         FROM chart
                                         WHERE id = (SELECT chart_id
                                                     FROM tax
                                                     WHERE id = ?)))|;
      @values = (conv_i($form->{id}), conv_i($form->{"tax_id_$i"}),
                 $tax, conv_date($form->{transdate}), $form->{"source_$i"},
                 $form->{"memo_$i"}, $project_id, $taxkey, conv_i($form->{"tax_id_$i"}), conv_i($form->{"tax_id_$i"}));
      do_query($form, $dbh, $query, @values);
    }
  }

  if ($form->{storno} && $form->{storno_id}) {
    do_query($form, $dbh, qq|UPDATE gl SET storno = 't' WHERE id = ?|, conv_i($form->{storno_id}));
  }

  # safety check datev export
  if ($::instance_conf->get_datev_check_on_gl_transaction) {
    my $transdate = $::form->{transdate} ? DateTime->from_lxoffice($::form->{transdate}) : undef;
    $transdate  ||= DateTime->today;

    my $datev = SL::DATEV->new(
      exporttype => DATEV_ET_BUCHUNGEN,
      format     => DATEV_FORMAT_KNE,
      dbh        => $dbh,
      from       => $transdate,
      to         => $transdate,
      trans_id   => $form->{id},
    );

    $datev->export;

    if ($datev->errors) {
      $dbh->rollback;
      die join "\n", $::locale->text('DATEV check returned errors:'), $datev->errors;
    }
  }

  # commit and redirect
  my $rc = $dbh->commit;
  $dbh->disconnect;
  $main::lxdebug->leave_sub();

  return $rc;
}

sub all_transactions {
  my ($self, $myconfig, $form) = @_;
  $main::lxdebug->enter_sub();

  # connect to database
  my $dbh = $form->dbconnect($myconfig);
  my ($query, $sth, $source, $null, $space);

  my ($glwhere, $arwhere, $apwhere) = ("1 = 1", "1 = 1", "1 = 1");
  my (@glvalues, @arvalues, @apvalues);

  if ($form->{reference}) {
    $glwhere .= qq| AND g.reference ILIKE ?|;
    $arwhere .= qq| AND a.invnumber ILIKE ?|;
    $apwhere .= qq| AND a.invnumber ILIKE ?|;
    push(@glvalues, '%' . $form->{reference} . '%');
    push(@arvalues, '%' . $form->{reference} . '%');
    push(@apvalues, '%' . $form->{reference} . '%');
  }

  if ($form->{department}) {
    my ($null, $department) = split /--/, $form->{department};
    $glwhere .= qq| AND g.department_id = ?|;
    $arwhere .= qq| AND a.department_id = ?|;
    $apwhere .= qq| AND a.department_id = ?|;
    push(@glvalues, $department);
    push(@arvalues, $department);
    push(@apvalues, $department);
  }

  if ($form->{source}) {
    $glwhere .= " AND ac.trans_id IN (SELECT trans_id from acc_trans WHERE source ILIKE ?)";
    $arwhere .= " AND ac.trans_id IN (SELECT trans_id from acc_trans WHERE source ILIKE ?)";
    $apwhere .= " AND ac.trans_id IN (SELECT trans_id from acc_trans WHERE source ILIKE ?)";
    push(@glvalues, '%' . $form->{source} . '%');
    push(@arvalues, '%' . $form->{source} . '%');
    push(@apvalues, '%' . $form->{source} . '%');
  }

  # default Datumseinschränkung falls nicht oder falsch übergeben (sollte nie passieren)
  $form->{datesort} = 'transdate' unless $form->{datesort} =~ /^(transdate|gldate)$/;

  if ($form->{datefrom}) {
    $glwhere .= " AND ac.$form->{datesort} >= ?";
    $arwhere .= " AND ac.$form->{datesort} >= ?";
    $apwhere .= " AND ac.$form->{datesort} >= ?";
    push(@glvalues, $form->{datefrom});
    push(@arvalues, $form->{datefrom});
    push(@apvalues, $form->{datefrom});
  }

  if ($form->{dateto}) {
    $glwhere .= " AND ac.$form->{datesort} <= ?";
    $arwhere .= " AND ac.$form->{datesort} <= ?";
    $apwhere .= " AND ac.$form->{datesort} <= ?";
    push(@glvalues, $form->{dateto});
    push(@arvalues, $form->{dateto});
    push(@apvalues, $form->{dateto});
  }

  if ($form->{description}) {
    $glwhere .= " AND g.description ILIKE ?";
    $arwhere .= " AND ct.name ILIKE ?";
    $apwhere .= " AND ct.name ILIKE ?";
    push(@glvalues, '%' . $form->{description} . '%');
    push(@arvalues, '%' . $form->{description} . '%');
    push(@apvalues, '%' . $form->{description} . '%');
  }

  if ($form->{employee_id}) {
    $glwhere .= " AND g.employee_id = ? ";
    $arwhere .= " AND a.employee_id = ? ";
    $apwhere .= " AND a.employee_id = ? ";
    push(@glvalues, conv_i($form->{employee_id}));
    push(@arvalues, conv_i($form->{employee_id}));
    push(@apvalues, conv_i($form->{employee_id}));
  }

  if ($form->{notes}) {
    $glwhere .= " AND g.notes ILIKE ?";
    $arwhere .= " AND a.notes ILIKE ?";
    $apwhere .= " AND a.notes ILIKE ?";
    push(@glvalues, '%' . $form->{notes} . '%');
    push(@arvalues, '%' . $form->{notes} . '%');
    push(@apvalues, '%' . $form->{notes} . '%');
  }

  if ($form->{accno}) {
    $glwhere .= " AND c.accno = '$form->{accno}'";
    $arwhere .= " AND c.accno = '$form->{accno}'";
    $apwhere .= " AND c.accno = '$form->{accno}'";
  }

  if ($form->{category} ne 'X') {
    $glwhere .= qq| AND g.id in (SELECT trans_id FROM acc_trans ac2 WHERE ac2.chart_id IN (SELECT id FROM chart c2 WHERE c2.category = ?))|;
    $arwhere .= qq| AND a.id in (SELECT trans_id FROM acc_trans ac2 WHERE ac2.chart_id IN (SELECT id FROM chart c2 WHERE c2.category = ?))|;
    $apwhere .= qq| AND a.id in (SELECT trans_id FROM acc_trans ac2 WHERE ac2.chart_id IN (SELECT id FROM chart c2 WHERE c2.category = ?))|;
    push(@glvalues, $form->{category});
    push(@arvalues, $form->{category});
    push(@apvalues, $form->{category});
  }

  if ($form->{project_id}) {
    $glwhere .= qq| AND g.id IN (SELECT DISTINCT trans_id FROM acc_trans WHERE project_id = ?)|;
    $arwhere .=
      qq| AND ((a.globalproject_id = ?) OR
               (a.id IN (SELECT DISTINCT trans_id FROM acc_trans WHERE project_id = ?)))|;
    $apwhere .=
      qq| AND ((a.globalproject_id = ?) OR
               (a.id IN (SELECT DISTINCT trans_id FROM acc_trans WHERE project_id = ?)))|;
    my $project_id = conv_i($form->{project_id});
    push(@glvalues, $project_id);
    push(@arvalues, $project_id, $project_id);
    push(@apvalues, $project_id, $project_id);
  }

  my ($project_columns, $project_join);
  if ($form->{"l_projectnumbers"}) {
    $project_columns = qq|, ac.project_id, pr.projectnumber|;
    $project_join = qq|LEFT JOIN project pr ON (ac.project_id = pr.id)|;
  }

  if ($form->{accno}) {
    # get category for account
    $query = qq|SELECT category FROM chart WHERE accno = ?|;
    ($form->{ml}) = selectrow_query($form, $dbh, $query, $form->{accno});

    if ($form->{datefrom}) {
      $query =
        qq|SELECT SUM(ac.amount)
           FROM acc_trans ac
           LEFT JOIN chart c ON (ac.chart_id = c.id)
           WHERE (c.accno = ?) AND (ac.$form->{datesort} < ?)|;
      ($form->{balance}) = selectrow_query($form, $dbh, $query, $form->{accno}, conv_date($form->{datefrom}));
    }
  }

  my %sort_columns =  (
    'id'           => [ qw(id)                   ],
    'transdate'    => [ qw(transdate id)         ],
    'gldate'       => [ qw(gldate id)         ],
    'reference'    => [ qw(lower_reference id)   ],
    'description'  => [ qw(lower_description id) ],
    'accno'        => [ qw(accno transdate id)   ],
    );
  my %lowered_columns =  (
    'reference'       => { 'gl' => 'g.reference',   'arap' => 'a.invnumber', },
    'source'          => { 'gl' => 'ac.source',     'arap' => 'ac.source',   },
    'description'     => { 'gl' => 'g.description', 'arap' => 'ct.name',     },
    );

  # sortdir = sort direction (ascending or descending)
  my $sortdir   = !defined $form->{sortdir} ? 'ASC' : $form->{sortdir} ? 'ASC' : 'DESC';
  my $sortkey   = $sort_columns{$form->{sort}} ? $form->{sort} : $form->{datesort};  # default used to be transdate
  my $sortorder = join ', ', map { "$_ $sortdir" } @{ $sort_columns{$sortkey} };

  my %columns_for_sorting = ( 'gl' => '', 'arap' => '', );
  foreach my $spec (@{ $sort_columns{$sortkey} }) {
    next if ($spec !~ m/^lower_(.*)$/);

    my $column = $1;
    map { $columns_for_sorting{$_} .= sprintf(', lower(%s) AS lower_%s', $lowered_columns{$column}->{$_}, $column) } qw(gl arap);
  }

  $query =
    qq|SELECT
        ac.acc_trans_id, g.id, 'gl' AS type, FALSE AS invoice, g.reference, ac.taxkey, c.link,
        g.description, ac.transdate, ac.gldate, ac.source, ac.trans_id,
        ac.amount, c.accno, g.notes, t.chart_id,
        CASE WHEN (COALESCE(e.name, '') = '') THEN e.login ELSE e.name END AS employee
        $project_columns
        $columns_for_sorting{gl}
      FROM gl g
      LEFT JOIN employee e ON (g.employee_id = e.id),
      acc_trans ac $project_join, chart c
      LEFT JOIN tax t ON (t.chart_id = c.id)
      WHERE $glwhere
        AND (ac.chart_id = c.id)
        AND (g.id = ac.trans_id)

      UNION

      SELECT ac.acc_trans_id, a.id, 'ar' AS type, a.invoice, a.invnumber, ac.taxkey, c.link,
        ct.name, ac.transdate, ac.gldate, ac.source, ac.trans_id,
        ac.amount, c.accno, a.notes, t.chart_id,
        CASE WHEN (COALESCE(e.name, '') = '') THEN e.login ELSE e.name END AS employee
        $project_columns
        $columns_for_sorting{arap}
      FROM ar a
      LEFT JOIN employee e ON (a.employee_id = e.id),
      acc_trans ac $project_join, customer ct, chart c
      LEFT JOIN tax t ON (t.chart_id=c.id)
      WHERE $arwhere
        AND (ac.chart_id = c.id)
        AND (a.customer_id = ct.id)
        AND (a.id = ac.trans_id)

      UNION

      SELECT ac.acc_trans_id, a.id, 'ap' AS type, a.invoice, a.invnumber, ac.taxkey, c.link,
        ct.name, ac.transdate, ac.gldate, ac.source, ac.trans_id,
        ac.amount, c.accno, a.notes, t.chart_id,
        CASE WHEN (COALESCE(e.name, '') = '') THEN e.login ELSE e.name END AS employee
        $project_columns
        $columns_for_sorting{arap}
      FROM ap a
      LEFT JOIN employee e ON (a.employee_id = e.id),
      acc_trans ac $project_join, vendor ct, chart c
      LEFT JOIN tax t ON (t.chart_id=c.id)
      WHERE $apwhere
        AND (ac.chart_id = c.id)
        AND (a.vendor_id = ct.id)
        AND (a.id = ac.trans_id)

      ORDER BY $sortorder, acc_trans_id $sortdir|;
#      ORDER BY gldate DESC, id DESC, acc_trans_id DESC

  my @values = (@glvalues, @arvalues, @apvalues);

  # Show all $query in Debuglevel LXDebug::QUERY
  my $callingdetails = (caller (0))[3];
  dump_query(LXDebug->QUERY(), "$callingdetails", $query, @values);

  $sth = prepare_execute_query($form, $dbh, $query, @values);
  my $trans_id  = "";
  my $trans_id2 = "";
  my $balance;

  my ($i, $j, $k, $l, $ref, $ref2);

  $form->{GL} = [];
  while (my $ref0 = $sth->fetchrow_hashref("NAME_lc")) {

    $trans_id = $ref0->{id};

    my $source = $ref0->{source};
    undef($ref0->{source});

    if ($trans_id != $trans_id2) { # first line of a booking

      if ($trans_id2) {
        push(@{ $form->{GL} }, $ref);
        $balance = 0;
      }

      $ref       = $ref0;
      $trans_id2 = $ref->{id};

      # gl
      if ($ref->{type} eq "gl") {
        $ref->{module} = "gl";
      }

      # ap
      if ($ref->{type} eq "ap") {
        if ($ref->{invoice}) {
          $ref->{module} = "ir";
        } else {
          $ref->{module} = "ap";
        }
      }

      # ar
      if ($ref->{type} eq "ar") {
        if ($ref->{invoice}) {
          $ref->{module} = "is";
        } else {
          $ref->{module} = "ar";
        }
      }

      $ref->{"projectnumbers"} = {};
      $ref->{"projectnumbers"}->{$ref->{"projectnumber"}} = 1 if ($ref->{"projectnumber"});

      $balance = $ref->{amount};

      # Linenumbers of General Ledger
      $k       = 0; # Debit      # AP      # Soll
      $l       = 0; # Credit     # AR      # Haben
      $i       = 0; # Debit Tax  # AP_tax  # VSt
      $j       = 0; # Credit Tax # AR_tax  # USt

      if ($ref->{chart_id} > 0) { # all tax accounts first line, no line increasing
        if ($ref->{amount} < 0) {
          if ($ref->{link} =~ /AR_tax/) {
            $ref->{credit_tax}{$j}       = $ref->{amount};
            $ref->{credit_tax_accno}{$j} = $ref->{accno};
         }
          if ($ref->{link} =~ /AP_tax/) {
            $ref->{debit_tax}{$i}       = $ref->{amount} * -1;
            $ref->{debit_tax_accno}{$i} = $ref->{accno};
          }
        } else {
          if ($ref->{link} =~ /AR_tax/) {
            $ref->{credit_tax}{$j}       = $ref->{amount};
            $ref->{credit_tax_accno}{$j} = $ref->{accno};
          }
          if ($ref->{link} =~ /AP_tax/) {
            $ref->{debit_tax}{$i}       = $ref->{amount} * -1;
            $ref->{debit_tax_accno}{$i} = $ref->{accno};
          }
        }
      } else { #all other accounts first line

        if ($ref->{amount} < 0) {
          $ref->{debit}{$k}        = $ref->{amount} * -1;
          $ref->{debit_accno}{$k}  = $ref->{accno};
          $ref->{debit_taxkey}{$k} = $ref->{taxkey};
          $ref->{ac_transdate}{$k} = $ref->{transdate};
          $ref->{source}{$k}       = $source;
        } else {
          $ref->{credit}{$l}        = $ref->{amount} * 1;
          $ref->{credit_accno}{$l}  = $ref->{accno};
          $ref->{credit_taxkey}{$l} = $ref->{taxkey};
          $ref->{ac_transdate}{$l}  = $ref->{transdate};
          $ref->{source}{$l}        = $source;
        }
      }

    } else { # following lines of a booking, line increasing

      $ref2      = $ref0;
#      $trans_old = $trans_id2;   # doesn't seem to be used anymore
      $trans_id2 = $ref2->{id};

      $balance =
        (int($balance * 100000) + int(100000 * $ref2->{amount})) / 100000;

      $ref->{"projectnumbers"}->{$ref2->{"projectnumber"}} = 1 if ($ref2->{"projectnumber"});

      if ($ref2->{chart_id} > 0) { # all tax accounts, following lines
        if ($ref2->{amount} < 0) {
          if ($ref2->{link} =~ /AR_tax/) {
            if ($ref->{credit_tax_accno}{$j} ne "") {
              $j++;
            }
            $ref->{credit_tax}{$j}       = $ref2->{amount};
            $ref->{credit_tax_accno}{$j} = $ref2->{accno};
          }
          if ($ref2->{link} =~ /AP_tax/) {
            if ($ref->{debit_tax_accno}{$i} ne "") {
              $i++;
            }
            $ref->{debit_tax}{$i}       = $ref2->{amount} * -1;
            $ref->{debit_tax_accno}{$i} = $ref2->{accno};
          }
        } else {
          if ($ref2->{link} =~ /AR_tax/) {
            if ($ref->{credit_tax_accno}{$j} ne "") {
              $j++;
            }
            $ref->{credit_tax}{$j}       = $ref2->{amount};
            $ref->{credit_tax_accno}{$j} = $ref2->{accno};
          }
          if ($ref2->{link} =~ /AP_tax/) {
            if ($ref->{debit_tax_accno}{$i} ne "") {
              $i++;
            }
            $ref->{debit_tax}{$i}       = $ref2->{amount} * -1;
            $ref->{debit_tax_accno}{$i} = $ref2->{accno};
          }
        }
      } else { # all other accounts, following lines
        if ($ref2->{amount} < 0) {
          if ($ref->{debit_accno}{$k} ne "") {
            $k++;
          }
          if ($ref->{source}{$k} ne "") {
            $space = " | ";
          } else {
            $space = "";
          }
          $ref->{debit}{$k}        = $ref2->{amount} * - 1;
          $ref->{debit_accno}{$k}  = $ref2->{accno};
          $ref->{debit_taxkey}{$k} = $ref2->{taxkey};
          $ref->{ac_transdate}{$k} = $ref2->{transdate};
          $ref->{source}{$k}       = $source . $space . $ref->{source}{$k};
        } else {
          if ($ref->{credit_accno}{$l} ne "") {
            $l++;
          }
          if ($ref->{source}{$l} ne "") {
            $space = " | ";
          } else {
            $space = "";
          }
          $ref->{credit}{$l}        = $ref2->{amount};
          $ref->{credit_accno}{$l}  = $ref2->{accno};
          $ref->{credit_taxkey}{$l} = $ref2->{taxkey};
          $ref->{ac_transdate}{$l}  = $ref2->{transdate};
          $ref->{source}{$l}        = $ref->{source}{$l} . $space . $source;
        }
      }
    }
  }

  push @{ $form->{GL} }, $ref;
  $sth->finish;

  if ($form->{accno}) {
    $query = qq|SELECT c.description FROM chart c WHERE c.accno = ?|;
    ($form->{account_description}) = selectrow_query($form, $dbh, $query, $form->{accno});
  }

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub transaction {
  my ($self, $myconfig, $form) = @_;
  $main::lxdebug->enter_sub();

  my ($query, $sth, $ref, @values);

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  $query = qq|SELECT closedto, revtrans FROM defaults|;
  ($form->{closedto}, $form->{revtrans}) = selectrow_query($form, $dbh, $query);

  $query = qq|SELECT id, gldate
              FROM gl
              WHERE id = (SELECT max(id) FROM gl)|;
  ($form->{previous_id}, $form->{previous_gldate}) = selectrow_query($form, $dbh, $query);

  if ($form->{id}) {
    $query =
      qq|SELECT g.reference, g.description, g.notes, g.transdate, g.storno, g.storno_id,
           d.description AS department, e.name AS employee, g.taxincluded, g.gldate,
         g.ob_transaction, g.cb_transaction
         FROM gl g
         LEFT JOIN department d ON (d.id = g.department_id)
         LEFT JOIN employee e ON (e.id = g.employee_id)
         WHERE g.id = ?|;
    $ref = selectfirst_hashref_query($form, $dbh, $query, conv_i($form->{id}));
    map { $form->{$_} = $ref->{$_} } keys %$ref;

    # retrieve individual rows
    $query =
      qq|SELECT c.accno, t.taxkey AS accnotaxkey, a.amount, a.memo, a.source,
           a.transdate, a.cleared, a.project_id, p.projectnumber,
           a.taxkey, t.rate AS taxrate, t.id,
           (SELECT c1.accno
            FROM chart c1, tax t1
            WHERE (t1.id = t.id) AND (c1.id = t.chart_id)) AS taxaccno,
           (SELECT tk.tax_id
            FROM taxkeys tk
            WHERE (tk.chart_id = a.chart_id) AND (tk.startdate <= a.transdate)
            ORDER BY tk.startdate desc LIMIT 1) AS tax_id
         FROM acc_trans a
         JOIN chart c ON (c.id = a.chart_id)
         LEFT JOIN project p ON (p.id = a.project_id)
         LEFT JOIN tax t ON (t.id = a.tax_id)
         WHERE (a.trans_id = ?)
           AND (a.fx_transaction = '0')
         ORDER BY a.acc_trans_id, a.transdate|;
    $form->{GL} = selectall_hashref_query($form, $dbh, $query, conv_i($form->{id}));

  } else {
    $query =
      qq|SELECT COALESCE(
           (SELECT transdate
            FROM gl
            WHERE id = (SELECT MAX(id) FROM gl)
            LIMIT 1),
           current_date)|;
    ($form->{transdate}) = selectrow_query($form, $dbh, $query);
  }

  # get tax description
  $query = qq|SELECT * FROM tax ORDER BY taxkey|;
  $form->{TAX} = selectall_hashref_query($form, $dbh, $query);

  # get chart of accounts
  $query =
    qq|SELECT c.accno, c.description, c.link, tk.taxkey_id, tk.tax_id
       FROM chart c
       LEFT JOIN taxkeys tk ON (tk.id =
         (SELECT id
          FROM taxkeys
          WHERE (taxkeys.chart_id = c.id)
            AND (startdate <= ?)
          ORDER BY startdate DESC
          LIMIT 1))
       ORDER BY c.accno|;
  $form->{chart} = selectall_hashref_query($form, $dbh, $query, conv_date($form->{transdate}));

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub storno {
  $main::lxdebug->enter_sub();

  my ($self, $form, $myconfig, $id) = @_;

  my ($query, $new_id, $storno_row, $acc_trans_rows);
  my $dbh = $form->get_standard_dbh($myconfig);

  $query = qq|SELECT nextval('glid')|;
  ($new_id) = selectrow_query($form, $dbh, $query);

  $query = qq|SELECT * FROM gl WHERE id = ?|;
  $storno_row = selectfirst_hashref_query($form, $dbh, $query, $id);

  $storno_row->{id}        = $new_id;
  $storno_row->{storno_id} = $id;
  $storno_row->{storno}    = 't';
  $storno_row->{reference} = 'Storno-' . $storno_row->{reference};

  delete @$storno_row{qw(itime mtime gldate)};

  $query = sprintf 'INSERT INTO gl (%s) VALUES (%s)', join(', ', keys %$storno_row), join(', ', map '?', values %$storno_row);
  do_query($form, $dbh, $query, (values %$storno_row));

  $query = qq|UPDATE gl SET storno = 't' WHERE id = ?|;
  do_query($form, $dbh, $query, $id);

  # now copy acc_trans entries
  $query = qq|SELECT * FROM acc_trans WHERE trans_id = ?|;
  my $rowref = selectall_hashref_query($form, $dbh, $query, $id);

  for my $row (@$rowref) {
    delete @$row{qw(itime mtime acc_trans_id gldate)};
    $query = sprintf 'INSERT INTO acc_trans (%s) VALUES (%s)', join(', ', keys %$row), join(', ', map '?', values %$row);
    $row->{trans_id}   = $new_id;
    $row->{amount}    *= -1;
    do_query($form, $dbh, $query, (values %$row));
  }

  $dbh->commit;

  $main::lxdebug->leave_sub();
}

sub get_chart_balances {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  Common::check_params(\%params, qw(charts));

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  my $dbh      = $params{dbh} || $form->get_standard_dbh($myconfig);

  my @ids      = map { $_->{id} } @{ $params{charts} };

  if (!@ids) {
    $main::lxdebug->leave_sub();
    return;
  }

  my $query = qq|SELECT chart_id, SUM(amount) AS sum
                 FROM acc_trans
                 WHERE chart_id IN (| . join(', ', ('?') x scalar(@ids)) . qq|)
                 GROUP BY chart_id|;

  my %balances = selectall_as_map($form, $dbh, $query, 'chart_id', 'sum', @ids);

  foreach my $chart (@{ $params{charts} }) {
    $chart->{balance} = $balances{ $chart->{id} } || 0;
  }

  $main::lxdebug->leave_sub();
}

sub get_tax_dropdown {
  my $myconfig = \%main::myconfig;
  my $form = $main::form;

  my $dbh = $form->get_standard_dbh($myconfig);

  my $query = qq|SELECT category FROM chart WHERE accno = ?|;
  my ($category) = selectrow_query($form, $dbh, $query, $form->{accno});

  $query = qq|SELECT * FROM tax WHERE chart_categories like '%$category%' order by taxkey, rate|;

  my $sth = prepare_execute_query($form, $dbh, $query);

  $form->{TAX_ACCOUNTS} = [];
  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    push(@{ $form->{TAX_ACCOUNTS} }, $ref);
  }

}

1;
