package SL::BackgroundJob::SelfTest::Transactions;

use utf8;
use strict;
use parent qw(SL::BackgroundJob::SelfTest::Base);

use SL::DBUtils;

use Rose::Object::MakeMethods::Generic (
  scalar => [ qw(dbh fromdate todate) ],
);

sub run {
  my ($self) = @_;

  $self->_setup;

  $self->tester->plan(tests => 16);

  $self->check_konten_mit_saldo_nicht_in_guv;
  $self->check_bilanzkonten_mit_pos_eur;
  $self->check_balanced_individual_transactions;
  $self->check_verwaiste_acc_trans_eintraege;
  $self->check_netamount_laut_invoice_ar;
  $self->check_invnumbers_unique;
  $self->check_summe_stornobuchungen;
  $self->check_ar_paid;
  $self->check_ap_paid;
  $self->check_ar_overpayments;
  $self->check_ap_overpayments;
  $self->check_paid_stornos;
  $self->check_stornos_ohne_partner;
  $self->check_overpayments;
  $self->check_every_account_with_taxkey;
  $self->calc_saldenvortraege;
}

sub _setup {
  my ($self) = @_;

  # TODO FIXME calc dates better, unless this is wanted
  $self->fromdate(DateTime->new(day => 1, month => 1, year => DateTime->today->year));
  $self->todate($self->fromdate->clone->add(years => 1)->add(days => -1));

  $self->dbh($::form->get_standard_dbh);
}

sub check_konten_mit_saldo_nicht_in_guv {
  my ($self) = @_;

  my $query = qq|
    SELECT c.accno, c.description, c.category, SUM(a.amount) AS Saldo
    FROM chart c,
         acc_trans a
    WHERE c.id = a.chart_id
     and  (c.category like 'I' or c.category like 'E')
     and  amount != 0
     and  pos_eur is null
         and  a.transdate >= ? and a.transdate <= ?
    GROUP BY c.accno,c.description,c.category,c.pos_bilanz,c.pos_eur
    ORDER BY c.accno|;

  my $konten_nicht_in_guv =  selectall_hashref_query($::form, $self->dbh, $query, $self->fromdate, $self->todate);

  my $correct = 0 == scalar grep { $_->{Saldo} } @$konten_nicht_in_guv;

  $self->tester->ok($correct, "Erfolgskonten mit Saldo nicht in GuV (Saldenvortragskonten können ignoriert werden, sollten aber 0 sein)");
  if (!$correct) {
    for my $konto (@$konten_nicht_in_guv) {
      $self->tester->diag($konto);
    }
  }
}

sub check_bilanzkonten_mit_pos_eur {
  my ($self) = @_;

  my $query = qq|SELECT accno, description FROM chart WHERE (category = 'A' OR category = 'L' OR category = 'Q') AND (pos_eur IS NOT NULL OR pos_eur != 0)|;

  my $bilanzkonten_mit_pos_eur = selectall_hashref_query($::form, $self->dbh, $query);
  if (@$bilanzkonten_mit_pos_eur) {
     $self->tester->ok(0, "Es gibt Bilanzkonten die der GuV/EÜR zugeordnet sind)");
     $self->tester->diag("$_->{accno}  $_->{description}") for @$bilanzkonten_mit_pos_eur;
  } else {
     $self->tester->ok(1, "Keine Bilanzkonten in der GuV");
  }
}

sub check_balanced_individual_transactions {
  my ($self) = @_;

  my $query = qq|
    select sum(ac.amount) as amount,trans_id,ar.invnumber as ar,ap.invnumber as ap,gl.reference as gl
      from acc_trans ac
      left join ar on (ar.id = ac.trans_id)
      left join ap on (ap.id = ac.trans_id)
      left join gl on (gl.id = ac.trans_id)
    where ac.transdate >= ? AND ac.transdate <= ?
    group by trans_id,ar.invnumber,ap.invnumber,gl.reference
    having sum(ac.amount) != 0;|;

  my $acs = selectall_hashref_query($::form, $self->dbh, $query, $self->fromdate, $self->todate);
  if (@$acs) {
    $self->tester->ok(0, "Es gibt unausgeglichene acc_trans-Transaktionen:");
    for my $ac (@{ $acs }) {
      $self->tester->diag("trans_id: $ac->{trans_id},  amount = $ac->{amount}, ar: $ac->{ar} ap: $ac->{ap} gl: $ac->{gl}");
    }
  } else {
    $self->tester->ok(1, "Alle acc_trans Transaktionen ergeben in Summe 0, keine unausgeglichenen Transaktionen");
  }
}

sub check_verwaiste_acc_trans_eintraege {
  my ($self) = @_;

  my $query = qq|
      select trans_id,amount,accno,description from acc_trans a
    left join chart c on (c.id = a.chart_id)
    where trans_id not in (select id from gl union select id from ar union select id from ap order by id)
      and a.transdate >= ? and a.transdate <= ? ;|;

  my $verwaiste_acs = selectall_hashref_query($::form, $self->dbh, $query, $self->fromdate, $self->todate);
  if (@$verwaiste_acs) {
     $self->tester->ok(0, "Es gibt verwaiste acc-trans Einträge! (wo ar/ap/gl-Eintrag fehlt)");
     $self->tester->diag($_) for @$verwaiste_acs;
  } else {
     $self->tester->ok(1, "Keine verwaisten acc-trans Einträge (wo ar/ap/gl-Eintrag fehlt)");
  }
}

sub check_netamount_laut_invoice_ar {
  my ($self) = @_;
  my $query = qq|
    select sum(round(cast(i.qty*(i.fxsellprice * (1-i.discount)) as numeric), 2))
    from invoice i
    left join ar a on (a.id = i.trans_id)
    where a.transdate >= ? and a.transdate <= ?;|;
  my ($netamount_laut_invoice) =  selectfirst_array_query($::form, $self->dbh, $query, $self->fromdate, $self->todate);

  $query = qq| select sum(netamount) from ar where transdate >= ? and transdate <= ?; |;
  my ($netamount_laut_ar) =  selectfirst_array_query($::form, $self->dbh, $query, $self->fromdate, $self->todate);

  my $correct = $netamount_laut_invoice - $netamount_laut_ar == 0;

  $self->tester->ok($correct, "Summe laut Verkaufsbericht sollte gleich Summe aus Verkauf -> Berichte -> Rechnungen sein");
  if (!$correct) {
    $self->tester->diag("Netto-Summe laut Verkaufsbericht (invoice): $netamount_laut_invoice");
    $self->tester->diag("Netto-Summe laut Verkauf -> Berichte -> Rechnungen: $netamount_laut_ar");
  }
}

sub check_invnumbers_unique {
  my ($self) = @_;

  my $query = qq| select  invnumber,count(invnumber) as count from ar
               where transdate >= ? and transdate <= ?
               group by invnumber
               having count(invnumber) > 1; |;
  my $non_unique_invnumbers =  selectall_hashref_query($::form, $self->dbh, $query, $self->fromdate, $self->todate);

  if (@$non_unique_invnumbers) {
    $self->tester->ok(0, "Es gibt doppelte Rechnungsnummern");
    for my $invnumber (@{ $non_unique_invnumbers }) {
      $self->tester->diag("invnumber: $invnumber->{invnumber}    $invnumber->{count}x");
    }
  } else {
    $self->tester->ok(1, "Alle Rechnungsnummern sind eindeutig");
  }
}

sub check_summe_stornobuchungen {
  my ($self) = @_;

  my $query = qq|
    select sum(amount) from ar a JOIN customer c ON (a.customer_id = c.id)
    WHERE storno is true
      AND a.transdate >= ? and a.transdate <= ?|;
  my ($summe_stornobuchungen_ar) = selectfirst_array_query($::form, $self->dbh, $query, $self->fromdate, $self->todate);

  $query = qq|
    select sum(amount) from ap a JOIN vendor c ON (a.vendor_id = c.id)
    WHERE storno is true
      AND a.transdate >= ? and a.transdate <= ?|;
  my ($summe_stornobuchungen_ap) = selectfirst_array_query($::form, $self->dbh, $query, $self->fromdate, $self->todate);

  $self->tester->ok($summe_stornobuchungen_ap == 0, 'Summe aller Einkaufsrechnungen (stornos + stornierte) soll 0 sein');
  $self->tester->ok($summe_stornobuchungen_ar == 0, 'Summe aller Verkaufsrechnungen (stornos + stornierte) soll 0 sein');
  $self->tester->diag("Summe Einkaufsrechnungen (ar): $summe_stornobuchungen_ar") if $summe_stornobuchungen_ar;
  $self->tester->diag("Summe Einkaufsrechnungen (ap): $summe_stornobuchungen_ap") if $summe_stornobuchungen_ap;
}

sub check_ar_paid {
  my ($self) = @_;

  my $query = qq|
      select invnumber,paid,
           (select sum(amount) from acc_trans a left join chart c on (c.id = a.chart_id) where trans_id = ar.id and c.link like '%AR_paid%') as accpaid ,
           paid+(select sum(amount) from acc_trans a left join chart c on (c.id = a.chart_id) where trans_id = ar.id and c.link like '%AR_paid%') as diff
    from ar
    where
          (select sum(amount) from acc_trans a left join chart c on (c.id = a.chart_id) where trans_id = ar.id and c.link like '%AR_paid%') is not null
            AND storno is false
      AND transdate >= ? and transdate <= ?
    order by diff |;

  my $paid_diffs_ar = selectall_hashref_query($::form, $self->dbh, $query, $self->fromdate, $self->todate);

  my $errors = scalar grep { $_->{diff} != 0 } @$paid_diffs_ar;

  $self->tester->ok(!$errors, "Vergleich ar paid mit acc_trans AR_paid");

  for my $paid_diff_ar (@{ $paid_diffs_ar }) {
    next if $paid_diff_ar->{diff} == 0;
    $self->tester->diag("ar invnumber: $paid_diff_ar->{invnumber} : paid: $paid_diff_ar->{paid}    acc_paid= $paid_diff_ar->{accpaid}    diff: $paid_diff_ar->{diff}");
  }
}

sub check_ap_paid {
  my ($self) = @_;

  my $query = qq|
      select invnumber,paid,
            (select sum(amount) from acc_trans a left join chart c on (c.id = a.chart_id) where trans_id = ap.id and c.link like '%AP_paid%') as accpaid ,
            paid-(select sum(amount) from acc_trans a left join chart c on (c.id = a.chart_id) where trans_id = ap.id and c.link like '%AP_paid%') as diff
     from ap
     where
           (select sum(amount) from acc_trans a left join chart c on (c.id = a.chart_id) where trans_id = ap.id and c.link like '%AP_paid%') is not null
       AND transdate >= ? and transdate <= ?
     order by diff |;

  my $paid_diffs_ap = selectall_hashref_query($::form, $self->dbh, $query, $self->fromdate, $self->todate);

  my $errors = scalar grep { $_->{diff} != 0 } @$paid_diffs_ap;

  $self->tester->ok(!$errors, "Vergleich ap paid mit acc_trans AP_paid");
  for my $paid_diff_ap (@{ $paid_diffs_ap }) {
     next if $paid_diff_ap->{diff} == 0;
     $self->tester->diag("ap invnumber: $paid_diff_ap->{invnumber} : paid: $paid_diff_ap->{paid}    acc_paid= $paid_diff_ap->{accpaid}    diff: $paid_diff_ap->{diff}");
  }
}

sub check_ar_overpayments {
  my ($self) = @_;

  my $query = qq|
       select invnumber,paid,amount,transdate,c.customernumber,c.name from ar left join customer c on (ar.customer_id = c.id)
     where abs(paid) > abs(amount)
       AND transdate >= ? and transdate <= ?
         order by invnumber;|;

  my $overpaids_ar =  selectall_hashref_query($::form, $self->dbh, $query, $self->fromdate, $self->todate);

  my $correct = 0 == @$overpaids_ar;

  $self->tester->ok($correct, "Keine Überzahlungen laut ar.paid");
  for my $overpaid_ar (@{ $overpaids_ar }) {
    $self->tester->diag("ar invnumber: $overpaid_ar->{invnumber} : paid: $overpaid_ar->{paid}    amount= $overpaid_ar->{amount}  transdate = $overpaid_ar->{transdate}");
  }
}

sub check_ap_overpayments {
  my ($self) = @_;

  my $query = qq|
      select invnumber,paid,amount,transdate,vc.vendornumber,vc.name from ap left join vendor vc on (ap.vendor_id = vc.id)
    where abs(paid) > abs(amount)
      AND transdate >= ? and transdate <= ?
        order by invnumber;|;

  my $overpaids_ap =  selectall_hashref_query($::form, $self->dbh, $query, $self->fromdate, $self->todate);

  my $correct = 0 == @$overpaids_ap;

  $self->tester->ok($correct, "Überzahlungen laut ap.paid:");
  for my $overpaid_ap (@{ $overpaids_ap }) {
    $self->tester->diag("ap invnumber: $overpaid_ap->{invnumber} : paid: $overpaid_ap->{paid}    amount= $overpaid_ap->{amount}  transdate = $overpaid_ap->{transdate}");
  }
}

sub check_paid_stornos {
  my ($self) = @_;

  my $query = qq|
    SELECT ar.invnumber,sum(amount - COALESCE((SELECT sum(amount)*-1 FROM acc_trans LEFT JOIN chart ON (acc_trans.chart_id=chart.id) WHERE link ilike '%paid%' AND acc_trans.trans_id=ar.id ),0)) as "open"
    FROM ar, customer
    WHERE paid != amount
      AND ar.storno
      AND (ar.customer_id = customer.id)
      AND ar.transdate >= ? and ar.transdate <= ?
    GROUP BY ar.invnumber;|;
  my $paid_stornos = selectall_hashref_query($::form, $self->dbh, $query, $self->fromdate, $self->todate);

  $self->tester->ok(0 == @$paid_stornos, "Keine bezahlten Stornos");
  for my $paid_storno (@{ $paid_stornos }) {
    $self->tester->diag("invnumber: $paid_storno->{invnumber}   offen: $paid_storno->{open}");
  }
}

sub check_stornos_ohne_partner {
  my ($self) = @_;

  my $query = qq|
    SELECT (SELECT cast ('ar' as text)) as invoice ,ar.id,invnumber,storno,amount,transdate,type,customernumber as cv_number
    FROM ar
    LEFT JOIN customer c on (c.id = ar.customer_id)
    WHERE storno_id is null AND storno is true AND ar.id not in (SELECT storno_id FROM ar WHERE storno_id is not null AND storno is true)
    UNION
    SELECT (SELECT cast ('ap' as text)) as invoice,ap.id,invnumber,storno,amount,transdate,type,vendornumber as cv_number
    FROM ap
    LEFT JOIN vendor v on (v.id = ap.vendor_id)
    WHERE storno_id is null AND storno is true AND ap.id not in (SELECT storno_id FROM ap WHERE storno_id is not null AND storno is true);
  |;

  my $stornos_ohne_partner =  selectall_hashref_query($::form, $self->dbh, $query);

  $self->tester->ok(@$stornos_ohne_partner == 0, 'Es sollte keine Stornos ohne Partner geben');
  if (@$stornos_ohne_partner) {
    $self->tester->diag("Stornos ohne Partner:   (kann passieren wenn Stornorechnung außerhalb Zeitraum liegt)");
    $self->tester->diag("gilt aber trotzdem als paid zu dem Zeitpunkt, oder?");
  }
  my $stornoheader = 0;
  for my $storno (@{ $stornos_ohne_partner }) {
    if (!$stornoheader++) {
      $self->tester->diag(join "\t", keys %$storno);
    }
    $self->tester->diag(join "\t", map { $storno->{$_} } keys %$storno);
  }
}

sub check_overpayments {
  my ($self) = @_;

  # Vergleich ar.paid und das was laut acc_trans bezahlt wurde
  # "als bezahlt markieren" ohne sauberes Ausbuchen führt zu Differenzen bei offenen Forderungen
  # geht nur auf wenn acc_trans Zahlungseingänge auch im Untersuchungszeitraum lagen
  # Stornos werden rausgefiltert
  my $query = qq|
SELECT
invnumber,customernumber,name,ar.transdate,ar.datepaid,
amount,
amount-paid as "open via ar",
paid as "paid via ar",
coalesce((SELECT sum(amount)*-1 FROM acc_trans LEFT JOIN chart ON (acc_trans.chart_id=chart.id) WHERE link ilike '%paid%' AND acc_trans.trans_id=ar.id AND acc_trans.transdate <= ?),0) as "paid via acc_trans"
FROM ar left join customer c on (c.id = ar.customer_id)
WHERE
 (ar.storno IS FALSE)
 AND (transdate <= ? )
;|;

  my $invoices = selectall_hashref_query($::form, $self->dbh, $query, $self->todate, $self->todate);

  my $count_overpayments = scalar grep {
       $_->{"paid via ar"} != $_->{"paid via acc_trans"}
    || (    $_->{"amount"} - $_->{"paid via acc_trans"} != $_->{"open via ar"}
         && $_->{"paid via ar"} != $_->{"paid via acc_trans"} )
  } @$invoices;

  $self->tester->ok($count_overpayments == 0, 'Vergleich ar.paid und das was laut acc_trans bezahlt wurde');

  if ($count_overpayments) {
    for my $invoice (@{ $invoices }) {
      if ($invoice->{"paid via ar"} != $invoice->{"paid via acc_trans"}) {
        $self->tester->diag("paid via ar (@{[ $invoice->{'paid via ar'} * 1 ]}) !=   paid via acc_trans  (@{[ $invoice->{'paid via acc_trans'} * 1 ]}) (at least until transdate!)");
        if (defined $invoice->{datepaid}) {
          $self->tester->diag("datepaid = $invoice->{datepaid})");
        }
        $self->tester->diag("Überzahlung!") if $invoice->{"paid via acc_trans"} > $invoice->{amount};
      } elsif ( $invoice->{"amount"} - $invoice->{"paid via acc_trans"} != $invoice->{"open via ar"} && $invoice->{"paid via ar"} != $invoice->{"paid via acc_trans"}) {
        $self->tester->diag("amount - paid_via_acc_trans !=  open_via_ar");
        $self->tester->diag("Überzahlung!") if $invoice->{"paid via acc_trans"} > $invoice->{amount};
      } else {
        # nothing wrong
      }
    }
  }
}

sub calc_saldenvortraege {
  my ($self) = @_;

  my $saldenvortragskonto = '9000';

  # Saldo Saldenvortragskonto 9000 am Jahresanfang
  my $query = qq|
      select sum(amount) from acc_trans where chart_id = (select id from chart where accno = ?) and transdate <= ?|;
  my ($saldo_9000_jahresanfang) = selectfirst_array_query($::form, $self->dbh, $query, $saldenvortragskonto, DateTime->new(day => 1, month => 1, year => DateTime->today->year));
  $self->tester->diag("Saldo 9000 am 01.01.@{[DateTime->today->year]}: @{[ $saldo_9000_jahresanfang * 1 ]}    (sollte 0 sein)");

    # Saldo Saldenvortragskonto 9000 am Jahresende
  $query = qq|
      select sum(amount) from acc_trans where chart_id = (select id from chart where accno = ?) and transdate <= ?|;
  my ($saldo_9000_jahresende) = selectfirst_array_query($::form, $self->dbh, $query, $saldenvortragskonto, DateTime->new(day => 31, month => 12, year => DateTime->today->year));
  $self->tester->diag("Saldo $saldenvortragskonto am 31.12.@{[DateTime->today->year]}: @{[ $saldo_9000_jahresende * 1 ]}    (sollte 0 sein)");
}

sub check_every_account_with_taxkey {
  my ($self) = @_;

  my $query = qq|SELECT accno, description FROM chart WHERE id NOT IN (select chart_id from taxkeys)|;
  my $accounts_without_tk = selectall_hashref_query($::form, $self->dbh, $query);

  if ( scalar @{ $accounts_without_tk } > 0 ){
    $self->tester->ok(0, "Folgende Konten haben keinen gültigen Steuerschlüssel:");

    for my $account_without_tk (@{ $accounts_without_tk } ) {
      $self->tester->diag("Kontonummer: $account_without_tk->{accno} Beschreibung: $account_without_tk->{description}");
    }
  } else {
    $self->tester->ok(1, "Jedes Konto hat einen gültigen Steuerschlüssel!");
  }
}

1;

__END__

=encoding utf-8

=head1 NAME

SL::BackgroundJob::SelfTest::Transactions - base tests

=head1 DESCRIPTION

Several tests for data integrity.

=head1 FUNCTIONS

=head1 BUGS

=head1 AUTHOR

G. Richardson E<lt>information@richardson-bueren.deE<gt>
Jan Büren E<lt>information@richardson-bueren.deE<gt>
Sven Schoeling E<lt>s.schoeling@linet-services.deE<gt>

=cut

