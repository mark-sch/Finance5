#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
# Copyright (C) 2003
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
# Batch printing module backend routines
#
#======================================================================

package BP;

use SL::DBUtils;

use strict;

sub get_vc {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my %arap = (invoice           => 'ar',
              sales_order       => 'oe',
              purchase_order    => 'oe',
              sales_quotation   => 'oe',
              request_quotation => 'oe',
              check             => 'ap',
              receipt           => 'ar');

  my $vc = $form->{vc} eq "customer" ? "customer" : "vendor";
  my $arap_type = defined($arap{$form->{type}}) ? $arap{$form->{type}} : 'ar';

  my $query =
    qq|SELECT count(*) | .
    qq|FROM (SELECT DISTINCT ON (vc.id) vc.id FROM $vc vc, $arap_type a, status s | .
    qq|  WHERE a.${vc}_id = vc.id  AND s.trans_id = a.id AND s.formname = ? | .
    qq|    AND s.spoolfile IS NOT NULL) AS total|;

  my ($count) = selectrow_query($form, $dbh, $query, $form->{type});

  # build selection list
  if ($count < $myconfig->{vclimit}) {
    $query =
      qq|SELECT DISTINCT ON (vc.id) vc.id, vc.name | .
      qq|FROM $vc vc, $arap_type a, status s | .
      qq|WHERE a.${vc}_id = vc.id AND s.trans_id = a.id AND s.formname = ? | .
      qq|  AND s.spoolfile IS NOT NULL|;

    my $sth = $dbh->prepare($query);
    $sth->execute($form->{type}) || $form->dberror($query . " ($form->{type})");

    $form->{"all_${vc}"} = [];
    while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
      push @{ $form->{"all_${vc}"} }, $ref;
    }
    $sth->finish;
  }

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub payment_accounts {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query =
    qq|SELECT DISTINCT ON (s.chart_id) c.accno, c.description | .
    qq|FROM status s, chart c | .
    qq|WHERE s.chart_id = c.id AND s.formname = ?|;
  my $sth = $dbh->prepare($query);
  $sth->execute($form->{type}) || $form->dberror($query . " ($form->{type})");

  $form->{accounts} = [];
  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    push @{ $form->{accounts} }, $ref;
  }

  $sth->finish;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub get_spoolfiles {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my ($query, $arap, @values);
  my $invnumber = "invnumber";

  my $vc = $form->{vc} eq "customer" ? "customer" : "vendor";

  if ($form->{type} eq 'check' || $form->{type} eq 'receipt') {

    $arap = ($form->{type} eq 'check') ? "ap" : "ar";
    my ($accno) = split /--/, $form->{account};

    $query =
      qq|SELECT a.id, s.spoolfile, vc.name, ac.transdate, a.invnumber, | .
      qq|  a.invoice, '$arap' AS module | .
      qq|FROM status s, chart c, $vc vc, $arap a, acc_trans ac | .
      qq|WHERE s.formname = ? | .
      qq|  AND s.chart_id = c.id | .
      qq|  AND c.accno = ? | .
      qq|  AND s.trans_id = a.id | .
      qq|  AND a.${vc}_id = vc.id | .
      qq|  AND ac.trans_id = s.trans_id | .
      qq|  AND ac.chart_id = c.id | .
      qq|  AND NOT ac.fx_transaction|;
    @values = ($form->{type}, $accno);

  } else {
    $arap = "ar";
    my $invoice = "a.invoice";
    my $quonumber = "a.quonumber";

    if ($form->{type} =~ /_(order|quotation)$/) {
      $invnumber = "ordnumber";
      $arap      = "oe";
      $invoice   = '0';
    }

    if ($form->{type} eq 'packing_list') {
      $invnumber = "donumber";
      $arap      = "delivery_orders";
      $invoice   = '0';
      $quonumber = '0';
    }

    $query =
      qq|SELECT a.id, a.$invnumber AS invnumber, a.ordnumber, $quonumber, | .
      qq|  a.transdate, $invoice AS invoice, '$arap' AS module, vc.name, | .
      qq|  s.spoolfile | .
      qq|FROM $arap a, ${vc} vc, status s | .
      qq|WHERE s.trans_id = a.id | .
      qq|  AND s.spoolfile IS NOT NULL | .
    ($form->{type} eq 'packing_list'
    ? qq|  AND s.formname IN (?, ?) |
    : qq|  AND s.formname = ? |) .
      qq|  AND a.${vc}_id = vc.id|;
    @values = ($form->{type});

    if ($form->{type} eq 'packing_list') {
      @values = qw(sales_delivery_order purchase_delivery_order);
    }
  }

  if ($form->{"${vc}_id"}) {
    $query .= qq| AND a.${vc}_id = ?|;
    push(@values, conv_i($form->{"${vc}_id"}));
  } elsif ($form->{ $vc }) {
    $query .= " AND vc.name ILIKE ?";
    push(@values, $form->like($form->{ $vc }));
  }
  foreach my $column (qw(invnumber ordnumber quonumber donumber)) {
    if ($form->{$column}) {
      $query .= " AND a.$column ILIKE ?";
      push(@values, $form->like($form->{$column}));
    }
  }

  if ($form->{type} =~ /(invoice|sales_order|sales_quotation|purchase_order|request_quotation|packing_list)$/) {
    if ($form->{transdatefrom}) {
      $query .= " AND a.transdate >= ?";
      push(@values, $form->{transdatefrom});
    }
    if ($form->{transdateto}) {
      $query .= " AND a.transdate <= ?";
      push(@values, $form->{transdateto});
    }
  }

  my @a = ("transdate", $invnumber, "name");
  my $sortorder = join ', ', $form->sort_columns(@a);

  if (grep({ $_ eq $form->{sort} }
           qw(transdate invnumber ordnumber quonumber donumber name))) {
    $sortorder = $form->{sort};
  }

  $query .= " ORDER BY $sortorder";

  my $sth = $dbh->prepare($query);
  $sth->execute(@values) ||
    $form->dberror($query . " (" . join(", ", @values) . ")");

  $form->{SPOOL} = [];
  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    push @{ $form->{SPOOL} }, $ref;
  }

  $sth->finish;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub delete_spool {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  my $spool = $::lx_office_conf{paths}->{spool};

  # connect to database, turn AutoCommit off
  my $dbh = $form->dbconnect_noauto($myconfig);

  my $query;

  if ($form->{type} =~ /(check|receipt)/) {
    $query = qq|DELETE FROM status WHERE spoolfile = ?|;
  } else {
    $query =
      qq|UPDATE status SET spoolfile = NULL, printed = '1' | .
      qq|WHERE spoolfile = ?|;
  }
  my $sth = $dbh->prepare($query) || $form->dberror($query);

  foreach my $i (1 .. $form->{rowcount}) {
    if ($form->{"checked_$i"}) {
      $sth->execute($form->{"spoolfile_$i"}) || $form->dberror($query);
      $sth->finish;
    }
  }

  # commit
  my $rc = $dbh->commit;
  $dbh->disconnect;

  if ($rc) {
    foreach my $i (1 .. $form->{rowcount}) {
      if ($form->{"checked_$i"}) {
        unlink(qq|$spool/$form->{"spoolfile_$i"}|);
      }
    }
  }

  $main::lxdebug->leave_sub();

  return $rc;
}

sub print_spool {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $output) = @_;

  my $spool = $::lx_office_conf{paths}->{spool};

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query =
    qq|UPDATE status SET printed = '1' | .
    qq|WHERE formname = ? AND spoolfile = ?|;
  my $sth = $dbh->prepare($query) || $form->dberror($query);

  foreach my $i (1 .. $form->{rowcount}) {
    if ($form->{"checked_$i"}) {
      # $output is safe ( = does not come directly from the browser).
      open(OUT, $output) or $form->error("$output : $!");

      $form->{"spoolfile_$i"} =~ s|.*/||;
      my $spoolfile = qq|$spool/$form->{"spoolfile_$i"}|;

      # send file to printer
      open(IN, $spoolfile) or $form->error("$spoolfile : $!");

      while (<IN>) {
        print OUT $_;
      }
      close(IN);
      close(OUT);

      $sth->execute($form->{type}, $form->{"spoolfile_$i"}) ||
        $form->dberror($query . " ($form->{type}, " . $form->{"spoolfile_$i"} . ")");
      $sth->finish;

    }
  }

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

1;

