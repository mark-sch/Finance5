#======================================================================
# LX-Office ERP
# Copyright (C) 2006
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
# Copyright (C) 1998-2002
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
# Dunning process module
#
#======================================================================

package DN;

use SL::Common;
use SL::DBUtils;
use SL::DB::Default;
use SL::GenericTranslations;
use SL::IS;
use SL::Mailer;
use SL::MoreCommon;
use SL::Template;
use SL::DB::Printer;
use SL::DB::Language;

use strict;

sub get_config {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query =
    qq|SELECT * | .
    qq|FROM dunning_config | .
    qq|ORDER BY dunning_level|;
  $form->{DUNNING} = selectall_hashref_query($form, $dbh, $query);

  foreach my $ref (@{ $form->{DUNNING} }) {
    $ref->{fee} = $form->format_amount($myconfig, $ref->{fee}, 2);
    $ref->{interest_rate} = $form->format_amount($myconfig, ($ref->{interest_rate} * 100));
  }

  $query =
    qq|SELECT dunning_ar_amount_fee, dunning_ar_amount_interest, dunning_ar
       FROM defaults|;
  ($form->{AR_amount_fee}, $form->{AR_amount_interest}, $form->{AR}) = selectrow_query($form, $dbh, $query);

  $dbh->disconnect();

  $main::lxdebug->leave_sub();
}

sub save_config {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect_noauto($myconfig);

  my ($query, @values);

  for my $i (1 .. $form->{rowcount}) {
    $form->{"fee_$i"} = $form->parse_amount($myconfig, $form->{"fee_$i"}) * 1;
    $form->{"interest_rate_$i"} = $form->parse_amount($myconfig, $form->{"interest_rate_$i"}) / 100;

    if (($form->{"dunning_level_$i"} ne "") &&
        ($form->{"dunning_description_$i"} ne "")) {
      @values = (conv_i($form->{"dunning_level_$i"}), $form->{"dunning_description_$i"},
                 $form->{"email_subject_$i"}, $form->{"email_body_$i"},
                 $form->{"template_$i"}, $form->{"fee_$i"}, $form->{"interest_rate_$i"},
                 $form->{"active_$i"} ? 't' : 'f', $form->{"auto_$i"} ? 't' : 'f', $form->{"email_$i"} ? 't' : 'f',
                 $form->{"email_attachment_$i"} ? 't' : 'f', conv_i($form->{"payment_terms_$i"}), conv_i($form->{"terms_$i"}),
                 $form->{"create_invoices_for_fees_$i"} ? 't' : 'f');
      if ($form->{"id_$i"}) {
        $query =
          qq|UPDATE dunning_config SET
               dunning_level = ?, dunning_description = ?,
               email_subject = ?, email_body = ?,
               template = ?, fee = ?, interest_rate = ?,
               active = ?, auto = ?, email = ?,
               email_attachment = ?, payment_terms = ?, terms = ?,
               create_invoices_for_fees = ?
             WHERE id = ?|;
        push(@values, conv_i($form->{"id_$i"}));
      } else {
        $query =
          qq|INSERT INTO dunning_config
               (dunning_level, dunning_description, email_subject, email_body,
                template, fee, interest_rate, active, auto, email,
                email_attachment, payment_terms, terms, create_invoices_for_fees)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)|;
      }
      do_query($form, $dbh, $query, @values);
    }

    if (($form->{"dunning_description_$i"} eq "") && ($form->{"id_$i"})) {
      $query = qq|DELETE FROM dunning_config WHERE id = ?|;
      do_query($form, $dbh, $query, $form->{"id_$i"});
    }
  }

  $query  = qq|UPDATE defaults SET dunning_ar_amount_fee = ?, dunning_ar_amount_interest = ?, dunning_ar = ?|;
  @values = (conv_i($form->{AR_amount_fee}), conv_i($form->{AR_amount_interest}), conv_i($form->{AR}));
  do_query($form, $dbh, $query, @values);

  $dbh->commit();
  $dbh->disconnect();

  $main::lxdebug->leave_sub();
}

sub create_invoice_for_fees {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $dbh, $dunning_id) = @_;

  my ($query, @values, $sth, $ref);

  $query = qq|SELECT dcfg.create_invoices_for_fees
              FROM dunning d
              LEFT JOIN dunning_config dcfg ON (d.dunning_config_id = dcfg.id)
              WHERE d.dunning_id = ?|;
  my ($create_invoices_for_fees) = selectrow_query($form, $dbh, $query, $dunning_id);

  if (!$create_invoices_for_fees) {
    $main::lxdebug->leave_sub();
    return;
  }

  $query = qq|SELECT dunning_ar_amount_fee, dunning_ar_amount_interest, dunning_ar FROM defaults|;
  ($form->{AR_amount_fee}, $form->{AR_amount_interest}, $form->{AR}) = selectrow_query($form, $dbh, $query);

  $query =
    qq|SELECT
         fee,
         COALESCE((
           SELECT MAX(d_fee.fee)
           FROM dunning d_fee
           WHERE (d_fee.trans_id   =  d.trans_id)
             AND (d_fee.dunning_id <> ?)
             AND NOT (d_fee.fee_interest_ar_id ISNULL)
         ), 0)
         AS max_previous_fee,
         interest,
         COALESCE((
           SELECT MAX(d_interest.interest)
           FROM dunning d_interest
           WHERE (d_interest.trans_id   =  d.trans_id)
             AND (d_interest.dunning_id <> ?)
             AND NOT (d_interest.fee_interest_ar_id ISNULL)
         ), 0)
         AS max_previous_interest
       FROM dunning d
       WHERE dunning_id = ?|;
  @values = ($dunning_id, $dunning_id, $dunning_id);
  $sth = prepare_execute_query($form, $dbh, $query, @values);

  my ($fee_remaining, $interest_remaining) = (0, 0);
  my ($fee_total, $interest_total) = (0, 0);

  while (my $ref = $sth->fetchrow_hashref()) {
    $fee_remaining      += $form->round_amount($ref->{fee}, 2);
    $fee_remaining      -= $form->round_amount($ref->{max_previous_fee}, 2);
    $fee_total          += $form->round_amount($ref->{fee}, 2);
    $interest_remaining += $form->round_amount($ref->{interest}, 2);
    $interest_remaining -= $form->round_amount($ref->{max_previous_interest}, 2);
    $interest_total     += $form->round_amount($ref->{interest}, 2);
  }

  $sth->finish();

  my $amount = $fee_remaining + $interest_remaining;

  if (!$amount) {
    $main::lxdebug->leave_sub();
    return;
  }

  my ($ar_id) = selectrow_query($form, $dbh, qq|SELECT nextval('glid')|);
  my $curr = $form->get_default_currency($myconfig);

  $query =
    qq|INSERT INTO ar (id,          invnumber, transdate, gldate, customer_id,
                       taxincluded, amount,    netamount, paid,   duedate,
                       invoice,     currency_id,      notes,
                       employee_id)
       VALUES (
         ?,                     -- id
         ?,                     -- invnumber
         current_date,          -- transdate
         current_date,          -- gldate
         -- customer_id:
         (SELECT ar.customer_id
          FROM dunning dn
          LEFT JOIN ar ON (dn.trans_id = ar.id)
          WHERE dn.dunning_id = ?
          LIMIT 1),
         'f',                   -- taxincluded
         ?,                     -- amount
         ?,                     -- netamount
         0,                     -- paid
         -- duedate:
         (SELECT duedate FROM dunning WHERE dunning_id = ? LIMIT 1),
         'f',                   -- invoice
         (SELECT id FROM currencies WHERE name = ?), -- curr
         ?,                     -- notes
         -- employee_id:
         (SELECT id FROM employee WHERE login = ?)
       )|;
  @values = ($ar_id,            # id
             $form->update_defaults($myconfig, 'invnumber', $dbh), # invnumber
             $dunning_id,       # customer_id
             $amount,
             $amount,
             $dunning_id,       # duedate
             $curr,             # default currency
             sprintf($main::locale->text('Automatically created invoice for fee and interest for dunning %s'), $dunning_id), # notes
             $form->{login});   # employee_id
  do_query($form, $dbh, $query, @values);

  $query =
    qq|INSERT INTO acc_trans (trans_id, chart_id, amount, transdate, gldate, taxkey)
       VALUES (?, ?, ?, current_date, current_date, 0)|;
  $sth = prepare_query($form, $dbh, $query);

  @values = ($ar_id, conv_i($form->{AR_amount_fee}), $fee_remaining);
  do_statement($form, $sth, $query, @values);

  if ($interest_remaining) {
    @values = ($ar_id, conv_i($form->{AR_amount_interest}), $interest_remaining);
    do_statement($form, $sth, $query, @values);
  }

  @values = ($ar_id, conv_i($form->{AR}), -1 * $amount);
  do_statement($form, $sth, $query, @values);

  $sth->finish();

  $query = qq|UPDATE dunning SET fee_interest_ar_id = ? WHERE dunning_id = ?|;
  do_query($form, $dbh, $query, $ar_id, $dunning_id);

  $main::lxdebug->leave_sub();
}

sub save_dunning {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $rows) = @_;
  # connect to database
  my $dbh = $form->dbconnect_noauto($myconfig);

  my ($query, @values);

  my ($dunning_id) = selectrow_query($form, $dbh, qq|SELECT nextval('id')|);

  my $q_update_ar = qq|UPDATE ar SET dunning_config_id = ? WHERE id = ?|;
  my $h_update_ar = prepare_query($form, $dbh, $q_update_ar);

  my $q_insert_dunning =
    qq|INSERT INTO dunning (dunning_id, dunning_config_id, dunning_level, trans_id,
                            fee,        interest,          transdate,     duedate)
       VALUES (?, ?,
               (SELECT dunning_level FROM dunning_config WHERE id = ?),
               ?,
               (SELECT SUM(fee)
                FROM dunning_config
                WHERE dunning_level <= (SELECT dunning_level FROM dunning_config WHERE id = ?)),
               (SELECT (amount - paid) * (current_date - duedate) FROM ar WHERE id = ?)
                 * (SELECT interest_rate FROM dunning_config WHERE id = ?)
                 / 360,
               current_date,
               current_date + (SELECT payment_terms FROM dunning_config WHERE id = ?))|;
  my $h_insert_dunning = prepare_query($form, $dbh, $q_insert_dunning);

  my @invoice_ids;
  my ($next_dunning_config_id, $customer_id);
  my $send_email = 0;

  foreach my $row (@{ $rows }) {
    push @invoice_ids, $row->{invoice_id};
    $next_dunning_config_id = $row->{next_dunning_config_id};
    $customer_id            = $row->{customer_id};

    @values = ($row->{next_dunning_config_id}, $row->{invoice_id});
    do_statement($form, $h_update_ar, $q_update_ar, @values);

    $send_email |= $row->{email};

    my $next_config_id = conv_i($row->{next_dunning_config_id});
    my $invoice_id     = conv_i($row->{invoice_id});

    @values = ($dunning_id,     $next_config_id, $next_config_id,
               $invoice_id,     $next_config_id, $invoice_id,
               $next_config_id, $next_config_id);
    do_statement($form, $h_insert_dunning, $q_insert_dunning, @values);
  }

  $h_update_ar->finish();
  $h_insert_dunning->finish();

  $form->{DUNNING_PDFS_EMAIL} = [];

  $self->create_invoice_for_fees($myconfig, $form, $dbh, $dunning_id);

  $self->print_invoice_for_fees($myconfig, $form, $dunning_id, $dbh);
  $self->print_dunning($myconfig, $form, $dunning_id, $dbh);

  $form->{dunning_id} = $dunning_id;

  if ($send_email) {
    $self->send_email($myconfig, $form, $dunning_id, $dbh);
  }

  $dbh->commit();
  $dbh->disconnect();

  $main::lxdebug->leave_sub();
}

sub send_email {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $dunning_id, $dbh) = @_;

  my $query =
    qq|SELECT
         dcfg.email_body,     dcfg.email_subject, dcfg.email_attachment,
         c.email AS recipient

       FROM dunning d
       LEFT JOIN dunning_config dcfg ON (d.dunning_config_id = dcfg.id)
       LEFT JOIN ar                  ON (d.trans_id          = ar.id)
       LEFT JOIN customer c          ON (ar.customer_id      = c.id)
       WHERE (d.dunning_id = ?)
       LIMIT 1|;
  my $ref = selectfirst_hashref_query($form, $dbh, $query, $dunning_id);

  if (!$ref || !$ref->{recipient} || !$myconfig->{email}) {
    $main::lxdebug->leave_sub();
    return;
  }

  my $template     = SL::Template::create(type => 'PlainText', form => $form, myconfig => $myconfig);
  my $mail         = Mailer->new();
  $mail->{from}    = $myconfig->{email};
  $mail->{to}      = $ref->{recipient};
  $mail->{subject} = $template->parse_block($ref->{email_subject});
  $mail->{message} = $template->parse_block($ref->{email_body});

  if ($myconfig->{signature}) {
    $mail->{message} .= "\n-- \n$myconfig->{signature}";
  }

  $mail->{message} =~ s/\r\n/\n/g;

  if ($ref->{email_attachment} && @{ $form->{DUNNING_PDFS_EMAIL} }) {
    $mail->{attachments} = $form->{DUNNING_PDFS_EMAIL};
  }

  $mail->send();

  $main::lxdebug->leave_sub();
}

sub set_template_options {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  my $defaults = SL::DB::Default->get;
  $form->error($::locale->text('No print templates have been created for this client yet. Please do so in the client configuration.')) if !$defaults->templates;
  $form->{templates}    = $defaults->templates;
  $form->{language}     = $form->get_template_language($myconfig);
  $form->{printer_code} = $form->get_printer_code($myconfig);

  if ($form->{language} ne "") {
    $form->{language} = "_" . $form->{language};
  }

  if ($form->{printer_code} ne "") {
    $form->{printer_code} = "_" . $form->{printer_code};
  }

  my $extension = 'html';
  if ($form->{format} eq 'postscript') {
    $form->{postscript}   = 1;
    $extension            = 'tex';

  } elsif ($form->{"format"} =~ /pdf/) {
    $form->{pdf}          = 1;
    $extension            = $form->{'format'} =~ m/opendocument/i ? 'odt' : 'tex';

  } elsif ($form->{"format"} =~ /opendocument/) {
    $form->{opendocument} = 1;
    $extension            = 'odt';
  } elsif ($form->{"format"} =~ /excel/) {
    $form->{excel} = 1;
    $extension            = 'xls';
  }


  # search for the template
  my @template_files;
  push @template_files, "$form->{formname}_email$form->{language}$form->{printer_code}.$extension" if $form->{media} eq 'email';
  push @template_files, "$form->{formname}$form->{language}$form->{printer_code}.$extension";
  push @template_files, "$form->{formname}.$extension";
  push @template_files, "default.$extension";

  $form->{IN} = undef;
  for my $filename (@template_files) {
    if (-f ($defaults->templates . "/$filename")) {
      $form->{IN} = $filename;
      last;
    }
  }

  if (!defined $form->{IN}) {
    $::form->error($::locale->text('Cannot find matching template for this print request. Please contact your template maintainer. I tried these: #1.', join ', ', map { "'$_'"} @template_files));
  }

  # prepare meta information for template introspection
  $form->{template_meta} = {
    formname  => $form->{formname},
    language  => SL::DB::Manager::Language->find_by_or_create(id => $form->{language_id}),
    format    => $form->{format},
    media     => $form->{media},
    extension => $extension,
    printer   => SL::DB::Manager::Printer->find_by_or_create(id => $form->{printer_id}),
    today     => DateTime->today,
  };

  $main::lxdebug->leave_sub();
}

sub get_invoices {

  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $where;
  my @values;

  $form->{customer_id} = $1 if ($form->{customer} =~ /--(\d+)$/);

  if ($form->{customer_id}) {
    $where .= qq| AND (a.customer_id = ?)|;
    push(@values, $form->{customer_id});

  } elsif ($form->{customer}) {
    $where .= qq| AND (ct.name ILIKE ?)|;
    push(@values, '%' . $form->{customer} . '%');
  }

  my %columns = (
    "ordnumber" => "a.ordnumber",
    "invnumber" => "a.invnumber",
    "notes"     => "a.notes",
    "country"   => "ct.country",
    );
  foreach my $key (keys(%columns)) {
    next unless ($form->{$key});
    $where .= qq| AND $columns{$key} ILIKE ?|;
    push(@values, '%' . $form->{$key} . '%');
  }

  if ($form->{dunning_level}) {
    $where .= qq| AND nextcfg.id = ?|;
    push(@values, conv_i($form->{dunning_level}));
  }

  $form->{minamount} = $form->parse_amount($myconfig,$form->{minamount});
  if ($form->{minamount}) {
    $where .= qq| AND ((a.amount - a.paid) > ?) |;
    push(@values, $form->{minamount});
  }

  my $query =
    qq|SELECT id
       FROM dunning_config
       WHERE dunning_level = (SELECT MAX(dunning_level) FROM dunning_config)|;
  my ($id_for_max_dunning_level) = selectrow_query($form, $dbh, $query);

  $query =
    qq|SELECT
         a.id, a.ordnumber, a.transdate, a.invnumber, a.amount, a.language_id,
         ct.name AS customername, a.customer_id, a.duedate,
         a.amount - a.paid AS open_amount,

         cfg.dunning_description, cfg.dunning_level,

         d.transdate AS dunning_date, d.duedate AS dunning_duedate,
         d.fee, d.interest,

         a.duedate + cfg.terms - current_date AS nextlevel,
         current_date - COALESCE(d.duedate, a.duedate) AS pastdue,
         current_date + cfg.payment_terms AS next_duedate,

         nextcfg.dunning_description AS next_dunning_description,
         nextcfg.id AS next_dunning_config_id,
         nextcfg.terms, nextcfg.active, nextcfg.email

       FROM ar a

       LEFT JOIN customer ct ON (a.customer_id = ct.id)
       LEFT JOIN dunning_config cfg ON (a.dunning_config_id = cfg.id)
       LEFT JOIN dunning_config nextcfg ON
         (nextcfg.id =
           COALESCE(
             (SELECT id
              FROM dunning_config
              WHERE dunning_level >
                COALESCE((SELECT dunning_level
                          FROM dunning_config
                          WHERE id = a.dunning_config_id
                          ORDER BY dunning_level DESC
                          LIMIT 1),
                         0)
              ORDER BY dunning_level ASC
              LIMIT 1)
             , ?))
       LEFT JOIN dunning d ON (d.id = (
         SELECT MAX(d2.id)
         FROM dunning d2
         WHERE (d2.trans_id      = a.id)
           AND (d2.dunning_level = cfg.dunning_level)
       ))

       WHERE (a.paid < a.amount)
         AND (a.duedate < current_date)

       $where

       ORDER BY a.id, transdate, duedate, name|;
  my $sth = prepare_execute_query($form, $dbh, $query, $id_for_max_dunning_level, @values);

  $form->{DUNNINGS} = [];

  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    next if ($ref->{pastdue} < $ref->{terms});

    $ref->{interest} = $form->round_amount($ref->{interest}, 2);
    push(@{ $form->{DUNNINGS} }, $ref);
  }

  $sth->finish;

  $query = qq|SELECT id, dunning_description FROM dunning_config ORDER BY dunning_level|;
  $form->{DUNNING_CONFIG} = selectall_hashref_query($form, $dbh, $query);

  $dbh->disconnect;
  $main::lxdebug->leave_sub();
}

sub get_dunning {

  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $where = qq| WHERE (da.trans_id = a.id)|;

  my @values;

  if ($form->{customer_id}) {
    $where .= qq| AND (a.customer_id = ?)|;
    push(@values, $form->{customer_id});

  } elsif ($form->{customer}) {
    $where .= qq| AND (ct.name ILIKE ?)|;
    push(@values, '%' . $form->{customer} . '%');
  }

  my %columns = (
    "ordnumber" => "a.ordnumber",
    "invnumber" => "a.invnumber",
    "notes" => "a.notes",
    );
  foreach my $key (keys(%columns)) {
    next unless ($form->{$key});
    $where .= qq| AND $columns{$key} ILIKE ?|;
    push(@values, '%' . $form->{$key} . '%');
  }

  if ($form->{dunning_level}) {
    $where .= qq| AND a.dunning_config_id = ?|;
    push(@values, conv_i($form->{dunning_level}));
  }

  if ($form->{department_id}) {
    $where .= qq| AND a.department_id = ?|;
    push @values, conv_i($form->{department_id});
  }

  $form->{minamount} = $form->parse_amount($myconfig, $form->{minamount});
  if ($form->{minamount}) {
    $where .= qq| AND ((a.amount - a.paid) > ?) |;
    push(@values, $form->{minamount});
  }

  if (!$form->{showold}) {
    $where .= qq| AND (a.amount > a.paid) AND (da.dunning_config_id = a.dunning_config_id) |;
  }

  if ($form->{transdatefrom}) {
    $where .= qq| AND a.transdate >= ?|;
    push(@values, $form->{transdatefrom});
  }
  if ($form->{transdateto}) {
    $where .= qq| AND a.transdate <= ?|;
    push(@values, $form->{transdateto});
  }
  if ($form->{dunningfrom}) {
    $where .= qq| AND da.transdate >= ?|;
    push(@values, $form->{dunningfrom});
  }
  if ($form->{dunningto}) {
    $where .= qq| AND da.transdate >= ?|;
    push(@values, $form->{dunningto});
  }

  if ($form->{salesman_id}) {
    $where .= qq| AND a.salesman_id = ?|;
    push(@values, conv_i($form->{salesman_id}));
  }

  my %sort_columns = (
    'dunning_description' => [ qw(dn.dunning_description customername invnumber) ],
    'customername'        => [ qw(customername invnumber) ],
    'invnumber'           => [ qw(a.invnumber) ],
    'transdate'           => [ qw(a.transdate a.invnumber) ],
    'duedate'             => [ qw(a.duedate a.invnumber) ],
    'dunning_date'        => [ qw(dunning_date a.invnumber) ],
    'dunning_duedate'     => [ qw(dunning_duedate a.invnumber) ],
    'salesman'            => [ qw(salesman) ],
    );

  my $sortdir   = !defined $form->{sortdir}    ? 'ASC'         : $form->{sortdir} ? 'ASC' : 'DESC';
  my $sortkey   = $sort_columns{$form->{sort}} ? $form->{sort} : 'customername';
  my $sortorder = join ', ', map { "$_ $sortdir" } @{ $sort_columns{$sortkey} };

  my $query =
    qq|SELECT a.id, a.ordnumber, a.invoice, a.transdate, a.invnumber, a.amount, a.language_id,
         ct.name AS customername, ct.id AS customer_id, a.duedate, da.fee,
         da.interest, dn.dunning_description, da.transdate AS dunning_date,
         da.duedate AS dunning_duedate, da.dunning_id, da.dunning_config_id,
         e2.name AS salesman
       FROM ar a
       JOIN customer ct ON (a.customer_id = ct.id)
       LEFT JOIN employee e2 ON (a.salesman_id = e2.id), dunning da
       LEFT JOIN dunning_config dn ON (da.dunning_config_id = dn.id)
       $where
       ORDER BY $sortorder|;

  $form->{DUNNINGS} = selectall_hashref_query($form, $dbh, $query, @values);

  foreach my $ref (@{ $form->{DUNNINGS} }) {
    map { $ref->{$_} = $form->format_amount($myconfig, $ref->{$_}, 2)} qw(amount fee interest);
  }

  $dbh->disconnect;
  $main::lxdebug->leave_sub();
}

sub melt_pdfs {

  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $copies) = @_;

  # Don't allow access outside of $spool.
  map { $_ =~ s|.*/||; } @{ $form->{DUNNING_PDFS} };

  $copies        *= 1;
  $copies         = 1 unless $copies;
  my $spool       = $::lx_office_conf{paths}->{spool};
  my $inputfiles  = join " ", map { "$spool/$_ " x $copies } @{ $form->{DUNNING_PDFS} };
  my $dunning_id  = $form->{dunning_id};

  $dunning_id     =~ s|[^\d]||g;

  my $in = IO::File->new($::lx_office_conf{applications}->{ghostscript} . " -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=- $inputfiles |");
  $form->error($main::locale->text('Could not spawn ghostscript.')) unless $in;

  if ($form->{media} eq 'printer') {
    $form->get_printer_code($myconfig);
    my $out;
    if ($form->{printer_command}) {
      $out = IO::File->new("| $form->{printer_command}");
    }

    $::locale->with_raw_io($out, sub { $out->print($_) while <$in> });

    $form->error($main::locale->text('Could not spawn the printer command.')) unless $out;

  } else {
    my $dunning_filename = $form->get_formname_translation('dunning');
    print qq|Content-Type: Application/PDF\n| .
          qq|Content-Disposition: attachment; filename="${dunning_filename}_${dunning_id}.pdf"\n\n|;

    $::locale->with_raw_io(\*STDOUT, sub { print while <$in> });
  }

  $in->close();

  map { unlink("$spool/$_") } @{ $form->{DUNNING_PDFS} };

  $main::lxdebug->leave_sub();
}

sub print_dunning {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $dunning_id, $provided_dbh) = @_;

  # connect to database
  my $dbh = $provided_dbh ? $provided_dbh : $form->dbconnect_noauto($myconfig);

  $dunning_id =~ s|[^\d]||g;

  my $query =
    qq|SELECT
         da.fee, da.interest,
         da.transdate  AS dunning_date,
         da.duedate    AS dunning_duedate,

         dcfg.template AS formname,
         dcfg.email_subject, dcfg.email_body, dcfg.email_attachment,

         ar.transdate,       ar.duedate,      ar.customer_id,
         ar.invnumber,       ar.ordnumber,    ar.cp_id,
         ar.amount,          ar.netamount,    ar.paid,
         (SELECT cu.name FROM currencies cu WHERE cu.id=ar.currency_id) AS curr,
         ar.amount - ar.paid AS open_amount,
         ar.amount - ar.paid + da.fee + da.interest AS linetotal

       FROM dunning da
       LEFT JOIN dunning_config dcfg ON (dcfg.id = da.dunning_config_id)
       LEFT JOIN ar ON (ar.id = da.trans_id)
       WHERE (da.dunning_id = ?)|;

  my $sth = prepare_execute_query($form, $dbh, $query, $dunning_id);
  my $first = 1;
  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    if ($first) {
      $form->{TEMPLATE_ARRAYS} = {};
      map({ $form->{TEMPLATE_ARRAYS}->{"dn_$_"} = []; } keys(%{$ref}));
      $first = 0;
    }
    map { $ref->{$_} = $form->format_amount($myconfig, $ref->{$_}, 2) } qw(amount netamount paid open_amount fee interest linetotal);
    map { $form->{$_} = $ref->{$_} } keys %$ref;
    map { push @{ $form->{TEMPLATE_ARRAYS}->{"dn_$_"} }, $ref->{$_} } keys %$ref;
  }
  $sth->finish();

  $query =
    qq|SELECT
         c.id AS customer_id, c.name,         c.street,       c.zipcode,   c.city,
         c.country,           c.department_1, c.department_2, c.email,     c.customernumber,
         c.greeting,          c.contact,      c.phone,        c.fax,       c.homepage,
         c.email,             c.taxincluded,  c.business_id,  c.taxnumber, c.iban,
         c,ustid,             e.name as salesman_name,
         co.*
       FROM dunning d
       LEFT JOIN ar          ON (d.trans_id = ar.id)
       LEFT JOIN customer c  ON (ar.customer_id = c.id)
       LEFT JOIN contacts co ON (ar.cp_id = co.cp_id)
       LEFT JOIN employee e  ON (ar.salesman_id = e.id)
       WHERE (d.dunning_id = ?)
       LIMIT 1|;
  my $ref = selectfirst_hashref_query($form, $dbh, $query, $dunning_id);
  map { $form->{$_} = $ref->{$_} } keys %{ $ref };

  $query =
    qq|SELECT
         cfg.interest_rate, cfg.template AS formname,
         cfg.email_subject, cfg.email_body, cfg.email_attachment,
         d.transdate AS dunning_date,
         (SELECT SUM(fee)
          FROM dunning
          WHERE dunning_id = ?)
         AS fee,
         (SELECT SUM(interest)
          FROM dunning
          WHERE dunning_id = ?)
         AS total_interest,
         (SELECT SUM(amount) - SUM(paid)
          FROM ar
          WHERE id IN
            (SELECT trans_id
             FROM dunning
             WHERE dunning_id = ?))
         AS total_open_amount
       FROM dunning d
       LEFT JOIN dunning_config cfg ON (d.dunning_config_id = cfg.id)
       WHERE d.dunning_id = ?
       LIMIT 1|;
  $ref = selectfirst_hashref_query($form, $dbh, $query, $dunning_id, $dunning_id, $dunning_id, $dunning_id);
  map { $form->{$_} = $ref->{$_} } keys %{ $ref };

  $form->{interest_rate}     = $form->format_amount($myconfig, $ref->{interest_rate} * 100);
  $form->{fee}               = $form->format_amount($myconfig, $ref->{fee}, 2);
  $form->{total_interest}    = $form->format_amount($myconfig, $form->round_amount($ref->{total_interest}, 2), 2);
  $form->{total_open_amount} = $form->format_amount($myconfig, $form->round_amount($ref->{total_open_amount}, 2), 2);
  $form->{total_amount}      = $form->format_amount($myconfig, $form->round_amount($ref->{fee} + $ref->{total_interest} + $ref->{total_open_amount}, 2), 2);

  $self->set_customer_cvars($myconfig, $form);
  $self->set_template_options($myconfig, $form);

  my $filename          = "dunning_${dunning_id}_" . Common::unique_id() . ".pdf";
  my $spool             = $::lx_office_conf{paths}->{spool};
  $form->{OUT}          = "${spool}/$filename";
  $form->{keep_tmpfile} = 1;

  delete $form->{tmpfile};

  push @{ $form->{DUNNING_PDFS} }, $filename;
  push @{ $form->{DUNNING_PDFS_EMAIL} }, { 'filename' => "${spool}/$filename",
                                           'name'     => "dunning_${dunning_id}.pdf" };

  $form->parse_template($myconfig);

  $dbh->disconnect() unless $provided_dbh;

  $main::lxdebug->leave_sub();
}

sub print_invoice_for_fees {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $dunning_id, $provided_dbh) = @_;

  my $dbh = $provided_dbh ? $provided_dbh : $form->dbconnect($myconfig);

  my ($query, @values, $sth);

  $query =
    qq|SELECT
         d.fee_interest_ar_id,
         dcfg.template
       FROM dunning d
       LEFT JOIN dunning_config dcfg ON (d.dunning_config_id = dcfg.id)
       WHERE d.dunning_id = ?|;
  my ($ar_id, $template) = selectrow_query($form, $dbh, $query, $dunning_id);

  if (!$ar_id) {
    $main::lxdebug->leave_sub();
    return;
  }

  my $saved_form = save_form();

  $query = qq|SELECT SUM(fee), SUM(interest) FROM dunning WHERE id = ?|;
  my ($fee_total, $interest_total) = selectrow_query($form, $dbh, $query, $dunning_id);

  $query =
    qq|SELECT
         ar.invnumber, ar.transdate AS invdate, ar.amount, ar.netamount,
         ar.duedate,   ar.notes,     ar.notes AS invoicenotes, ar.customer_id,

         c.name,      c.department_1,   c.department_2, c.street, c.zipcode, c.city, c.country,
         c.contact,   c.customernumber, c.phone,        c.fax,    c.email,
         c.taxnumber, c.greeting

       FROM ar
       LEFT JOIN customer c ON (ar.customer_id = c.id)
       WHERE ar.id = ?|;
  my $ref = selectfirst_hashref_query($form, $dbh, $query, $ar_id);
  map { $form->{$_} = $ref->{$_} } keys %{ $ref };

  $query = qq|SELECT * FROM employee WHERE login = ?|;
  $ref = selectfirst_hashref_query($form, $dbh, $query, $form->{login});
  map { $form->{"employee_${_}"} = $ref->{$_} } keys %{ $ref };

  $query = qq|SELECT * FROM acc_trans WHERE trans_id = ? ORDER BY acc_trans_id ASC|;
  $sth   = prepare_execute_query($form, $dbh, $query, $ar_id);

  my ($row, $fee, $interest) = (0, 0, 0);

  while ($ref = $sth->fetchrow_hashref()) {
    next if ($ref->{amount} < 0);

    $row++;

    if ($row == 1) {
      $fee = $ref->{amount};
    } else {
      $interest = $ref->{amount};
    }
  }

  $form->{fee}        = $form->round_amount($fee,             2);
  $form->{interest}   = $form->round_amount($interest,        2);
  $form->{invamount}  = $form->round_amount($fee + $interest, 2);
  $form->{dunning_id} = $dunning_id;
  $form->{formname}   = "${template}_invoice";

  map { $form->{$_} = $form->format_amount($myconfig, $form->{$_}, 2) } qw(fee interest invamount);

  $self->set_customer_cvars($myconfig, $form);
  $self->set_template_options($myconfig, $form);

  my $filename = Common::unique_id() . "dunning_invoice_${dunning_id}.pdf";

  my $spool             = $::lx_office_conf{paths}->{spool};
  $form->{OUT}          = "$spool/$filename";
  $form->{keep_tmpfile} = 1;
  delete $form->{tmpfile};

  map { delete $form->{$_} } grep /^[a-z_]+_\d+$/, keys %{ $form };

  $form->parse_template($myconfig);

  restore_form($saved_form);

  push @{ $form->{DUNNING_PDFS} }, $filename;
  push @{ $form->{DUNNING_PDFS_EMAIL} }, { 'filename' => "${spool}/$filename",
                                           'name'     => "dunning_invoice_${dunning_id}.pdf" };

  $dbh->disconnect() unless $provided_dbh;

  $main::lxdebug->leave_sub();
}

sub set_customer_cvars {
  my ($self, $myconfig, $form) = @_;

  my $custom_variables = CVar->get_custom_variables(dbh      => $form->get_standard_dbh,
                                                    module   => 'CT',
                                                    trans_id => $form->{customer_id});
  map { $form->{"vc_cvar_$_->{name}"} = $_->{value} } @{ $custom_variables };

  $form->{cp_greeting} = GenericTranslations->get(dbh              => $form->get_standard_dbh,
                                                  translation_type => 'greetings::' . ($form->{cp_gender} eq 'f' ? 'female' : 'male'),
                                                  language_id      => $form->{language_id},
                                                  allow_fallback   => 1);
}

1;
