#=====================================================================
# kivitendo ERP
# Copyright (c) 2004
#
#  Author: Philip Reetz
#   Email: p.reetz@linet-services.de
#     Web: http://www.lx-office.org
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
# Datev export module
#======================================================================

package SL::DATEV;

use utf8;
use strict;

use SL::DBUtils;
use SL::DATEV::KNEFile;

use Data::Dumper;
use DateTime;
use Exporter qw(import);
use File::Path;
use List::Util qw(max sum);
use Time::HiRes qw(gettimeofday);

{
  my $i = 0;
  use constant {
    DATEV_ET_BUCHUNGEN => $i++,
    DATEV_ET_STAMM     => $i++,

    DATEV_FORMAT_KNE   => $i++,
    DATEV_FORMAT_OBE   => $i++,
  };
}

my @export_constants = qw(DATEV_ET_BUCHUNGEN DATEV_ET_STAMM DATEV_FORMAT_KNE DATEV_FORMAT_OBE);
our @EXPORT_OK = (@export_constants);
our %EXPORT_TAGS = (CONSTANTS => [ @export_constants ]);


sub new {
  my $class = shift;
  my %data  = @_;

  my $obj = bless {}, $class;

  $obj->$_($data{$_}) for keys %data;

  $obj;
}

sub exporttype {
  my $self = shift;
  $self->{exporttype} = $_[0] if @_;
  return $self->{exporttype};
}

sub has_exporttype {
  defined $_[0]->{exporttype};
}

sub format {
  my $self = shift;
  $self->{format} = $_[0] if @_;
  return $self->{format};
}

sub has_format {
  defined $_[0]->{format};
}

sub _get_export_path {
  $main::lxdebug->enter_sub();

  my ($a, $b) = gettimeofday();
  my $path    = _get_path_for_download_token("${a}-${b}-${$}");

  mkpath($path) unless (-d $path);

  $main::lxdebug->leave_sub();

  return $path;
}

sub _get_path_for_download_token {
  $main::lxdebug->enter_sub();

  my $token = shift || '';
  my $path;

  if ($token =~ m|^(\d+)-(\d+)-(\d+)$|) {
    $path = $::lx_office_conf{paths}->{userspath} . "/datev-export-${1}-${2}-${3}/";
  }

  $main::lxdebug->leave_sub();

  return $path;
}

sub _get_download_token_for_path {
  $main::lxdebug->enter_sub();

  my $path = shift;
  my $token;

  if ($path =~ m|.*datev-export-(\d+)-(\d+)-(\d+)/?$|) {
    $token = "${1}-${2}-${3}";
  }

  $main::lxdebug->leave_sub();

  return $token;
}

sub download_token {
  my $self = shift;
  $self->{download_token} = $_[0] if @_;
  return $self->{download_token} ||= _get_download_token_for_path($self->export_path);
}

sub export_path {
  my ($self) = @_;

  return  $self->{export_path} ||= _get_path_for_download_token($self->{download_token}) || _get_export_path();
}

sub add_filenames {
  my $self = shift;
  push @{ $self->{filenames} ||= [] }, @_;
}

sub filenames {
  return @{ $_[0]{filenames} || [] };
}

sub add_error {
  my $self = shift;
  push @{ $self->{errors} ||= [] }, @_;
}

sub errors {
  return @{ $_[0]{errors} || [] };
}

sub add_net_gross_differences {
  my $self = shift;
  push @{ $self->{net_gross_differences} ||= [] }, @_;
}

sub net_gross_differences {
  return @{ $_[0]{net_gross_differences} || [] };
}

sub sum_net_gross_differences {
  return sum $_[0]->net_gross_differences;
}

sub from {
 my $self = shift;

 if (@_) {
   $self->{from} = $_[0];
 }

 return $self->{from};
}

sub to {
 my $self = shift;

 if (@_) {
   $self->{to} = $_[0];
 }

 return $self->{to};
}

sub trans_id {
  my $self = shift;

  if (@_) {
    $self->{trans_id} = $_[0];
  }

  return $self->{trans_id};
}

sub accnofrom {
 my $self = shift;

 if (@_) {
   $self->{accnofrom} = $_[0];
 }

 return $self->{accnofrom};
}

sub accnoto {
 my $self = shift;

 if (@_) {
   $self->{accnoto} = $_[0];
 }

 return $self->{accnoto};
}


sub dbh {
  my $self = shift;

  if (@_) {
    $self->{dbh} = $_[0];
    $self->{provided_dbh} = 1;
  }

  $self->{dbh} ||= $::form->get_standard_dbh;
}

sub provided_dbh {
  $_[0]{provided_dbh};
}

sub clean_temporary_directories {
  $::lxdebug->enter_sub;

  foreach my $path (glob($::lx_office_conf{paths}->{userspath} . "/datev-export-*")) {
    next unless -d $path;

    my $mtime = (stat($path))[9];
    next if ((time() - $mtime) < 8 * 60 * 60);

    rmtree $path;
  }

  $::lxdebug->leave_sub;
}

sub _fill {
  $main::lxdebug->enter_sub();

  my $text      = shift;
  my $field_len = shift;
  my $fill_char = shift;
  my $alignment = shift || 'right';

  my $text_len  = length $text;

  if ($field_len < $text_len) {
    $text = substr $text, 0, $field_len;

  } elsif ($field_len > $text_len) {
    my $filler = ($fill_char) x ($field_len - $text_len);
    $text      = $alignment eq 'right' ? $filler . $text : $text . $filler;
  }

  $main::lxdebug->leave_sub();

  return $text;
}

sub get_datev_stamm {
  return $_[0]{stamm} ||= selectfirst_hashref_query($::form, $_[0]->dbh, 'SELECT * FROM datev');
}

sub save_datev_stamm {
  my ($self, $data) = @_;

  do_query($::form, $self->dbh, 'DELETE FROM datev');

  my @columns = qw(beraternr beratername dfvkz mandantennr datentraegernr abrechnungsnr);

  my $query = "INSERT INTO datev (" . join(', ', @columns) . ") VALUES (" . join(', ', ('?') x @columns) . ")";
  do_query($::form, $self->dbh, $query, map { $data->{$_} } @columns);

  $self->dbh->commit unless $self->provided_dbh;
}

sub export {
  my ($self) = @_;
  my $result;

  die 'no format set!' unless $self->has_format;

  if ($self->format == DATEV_FORMAT_KNE) {
    $result = $self->kne_export;
  } elsif ($self->format == DATEV_FORMAT_OBE) {
    $result = $self->obe_export;
  } else {
    die 'unrecognized export format';
  }

  return $result;
}

sub kne_export {
  my ($self) = @_;
  my $result;

  die 'no exporttype set!' unless $self->has_exporttype;

  if ($self->exporttype == DATEV_ET_BUCHUNGEN) {
    $result = $self->kne_buchungsexport;
  } elsif ($self->exporttype == DATEV_ET_STAMM) {
    $result = $self->kne_stammdatenexport;
  } else {
    die 'unrecognized exporttype';
  }

  return $result;
}

sub obe_export {
  die 'not yet implemented';
}

sub fromto {
  my ($self) = @_;

  return unless $self->from && $self->to;

  return "transdate >= '" . $self->from->to_lxoffice . "' and transdate <= '" . $self->to->to_lxoffice . "'";
}

sub _sign {
  $_[0] <=> 0;
}

sub _get_transactions {
  $main::lxdebug->enter_sub();
  my $self     = shift;
  my $fromto   =  shift;
  my $progress_callback = shift || sub {};

  my $form     =  $main::form;

  my $trans_id_filter = '';

  $trans_id_filter = 'AND ac.trans_id = ' . $self->trans_id if $self->trans_id;

  my ($notsplitindex);

  $fromto      =~ s/transdate/ac\.transdate/g;

  my $filter   = '';            # Useful for debugging purposes

  my %all_taxchart_ids = selectall_as_map($form, $self->dbh, qq|SELECT DISTINCT chart_id, TRUE AS is_set FROM tax|, 'chart_id', 'is_set');

  my $query    =
    qq|SELECT ac.acc_trans_id, ac.transdate, ac.trans_id,ar.id, ac.amount, ac.taxkey,
         ar.invnumber, ar.duedate, ar.amount as umsatz, ar.deliverydate,
         ct.name,
         c.accno, c.taxkey_id as charttax, c.datevautomatik, c.id, ac.chart_link AS link,
         ar.invoice,
         t.rate AS taxrate
       FROM acc_trans ac
       LEFT JOIN ar          ON (ac.trans_id    = ar.id)
       LEFT JOIN customer ct ON (ar.customer_id = ct.id)
       LEFT JOIN chart c     ON (ac.chart_id    = c.id)
       LEFT JOIN tax t       ON (ac.tax_id      = t.id)
       WHERE (ar.id IS NOT NULL)
         AND $fromto
         $trans_id_filter
         $filter

       UNION ALL

       SELECT ac.acc_trans_id, ac.transdate, ac.trans_id,ap.id, ac.amount, ac.taxkey,
         ap.invnumber, ap.duedate, ap.amount as umsatz, ap.deliverydate,
         ct.name,
         c.accno, c.taxkey_id as charttax, c.datevautomatik, c.id, ac.chart_link AS link,
         ap.invoice,
         t.rate AS taxrate
       FROM acc_trans ac
       LEFT JOIN ap        ON (ac.trans_id  = ap.id)
       LEFT JOIN vendor ct ON (ap.vendor_id = ct.id)
       LEFT JOIN chart c   ON (ac.chart_id  = c.id)
       LEFT JOIN tax t     ON (ac.tax_id    = t.id)
       WHERE (ap.id IS NOT NULL)
         AND $fromto
         $trans_id_filter
         $filter

       UNION ALL

       SELECT ac.acc_trans_id, ac.transdate, ac.trans_id,gl.id, ac.amount, ac.taxkey,
         gl.reference AS invnumber, gl.transdate AS duedate, ac.amount as umsatz, NULL as deliverydate,
         gl.description AS name,
         c.accno, c.taxkey_id as charttax, c.datevautomatik, c.id, ac.chart_link AS link,
         FALSE AS invoice,
         t.rate AS taxrate
       FROM acc_trans ac
       LEFT JOIN gl      ON (ac.trans_id  = gl.id)
       LEFT JOIN chart c ON (ac.chart_id  = c.id)
       LEFT JOIN tax t   ON (ac.tax_id    = t.id)
       WHERE (gl.id IS NOT NULL)
         AND $fromto
         $trans_id_filter
         $filter

       ORDER BY trans_id, acc_trans_id|;

  my $sth = prepare_execute_query($form, $self->dbh, $query);
  $self->{DATEV} = [];

  my $counter = 0;
  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    $counter++;
    if (($counter % 500) == 0) {
      $progress_callback->($counter);
    }

    my $trans    = [ $ref ];

    my $count    = $ref->{amount};
    my $firstrun = 1;

    # if the amount of a booking in a group is smaller than 0.02, any tax
    # amounts will likely be smaller than 1 cent, so go into subcent mode
    my $subcent  = abs($count) < 0.02;

    # records from acc_trans are ordered by trans_id and acc_trans_id
    # first check for unbalanced ledger inside one trans_id
    # there may be several groups inside a trans_id, e.g. the original booking and the payment
    # each group individually should be exactly balanced and each group
    # individually needs its own datev lines

    # keep fetching new acc_trans lines until the end of a balanced group is reached
    while (abs($count) > 0.01 || $firstrun || ($subcent && abs($count) > 0.005)) {
      my $ref2 = $sth->fetchrow_hashref("NAME_lc");
      last unless ($ref2);

      # check if trans_id of current acc_trans line is still the same as the
      # trans_id of the first line in group

      if ($ref2->{trans_id} != $trans->[0]->{trans_id}) {
        $self->add_error("Unbalanced ledger! old trans_id " . $trans->[0]->{trans_id} . " new trans_id " . $ref2->{trans_id} . " count $count");
        return;
      }

      push @{ $trans }, $ref2;

      $count    += $ref2->{amount};
      $firstrun  = 0;
    }

    foreach my $i (0 .. scalar(@{ $trans }) - 1) {
      my $ref        = $trans->[$i];
      my $prev_ref   = 0 < $i ? $trans->[$i - 1] : undef;
      if (   $all_taxchart_ids{$ref->{id}}
          && ($ref->{link} =~ m/(?:AP_tax|AR_tax)/)
          && (   ($prev_ref && $prev_ref->{taxkey} && (_sign($ref->{amount}) == _sign($prev_ref->{amount})))
              || $ref->{invoice})) {
        $ref->{is_tax} = 1;
      }

      if (   !$ref->{invoice}   # we have a non-invoice booking (=gl)
          &&  $ref->{is_tax}    # that has "is_tax" set
          && !($prev_ref->{is_tax})  # previous line wasn't is_tax
          &&  (_sign($ref->{amount}) == _sign($prev_ref->{amount}))) {  # and sign same as previous sign
        $trans->[$i - 1]->{tax_amount} = $ref->{amount};
      }
    }

    my $absumsatz     = 0;
    if (scalar(@{$trans}) <= 2) {
      push @{ $self->{DATEV} }, $trans;
      next;
    }

    # determine at which array position the reference value (called absumsatz) is
    # and which amount it has

    for my $j (0 .. (scalar(@{$trans}) - 1)) {

      # Three cases:
      # 1: gl transaction (Dialogbuchung), invoice is false, no double split booking allowed

      # 2: sales or vendor invoice (Verkaufs- und Einkaufsrechnung): invoice is
      # true, instead of absumsatz use link AR/AP (there should only be one
      # entry)

      # 3. AR/AP transaction (Kreditoren- und Debitorenbuchung): invoice is false,
      # instead of absumsatz use link AR/AP (there should only be one, so jump
      # out of search as soon as you find it )

      # case 1 and 2
      # for gl-bookings no split is allowed and there is no AR/AP account, so we always use the maximum value as a reference
      # for ap/ar bookings we can always search for AR/AP in link and use that
      if ( ( not $trans->[$j]->{'invoice'} and abs($trans->[$j]->{'amount'}) > abs($absumsatz) )
         or ($trans->[$j]->{'invoice'} and ($trans->[$j]->{'link'} eq 'AR' or $trans->[$j]->{'link'} eq 'AP'))) {
        $absumsatz     = $trans->[$j]->{'amount'};
        $notsplitindex = $j;
      }

      # case 3
      # Problem: we can't distinguish between AR and AP and normal invoices via boolean "invoice"
      # for AR and AP transaction exit the loop as soon as an AR or AP account is found
      # there must be only one AR or AP chart in the booking
      if ( $trans->[$j]->{'link'} eq 'AR' or $trans->[$j]->{'link'} eq 'AP') {
        $notsplitindex = $j;   # position in booking with highest amount
        $absumsatz     = $trans->[$j]->{'amount'};
        last;
      };
    }

    my $ml             = ($trans->[0]->{'umsatz'} > 0) ? 1 : -1;
    my $rounding_error = 0;
    my @taxed;

    # go through each line and determine if it is a tax booking or not
    # skip all tax lines and notsplitindex line
    # push all other accounts (e.g. income or expense) with corresponding taxkey

    for my $j (0 .. (scalar(@{$trans}) - 1)) {
      if (   ($j != $notsplitindex)
          && !$trans->[$j]->{is_tax}
          && (   $trans->[$j]->{'taxkey'} eq ""
              || $trans->[$j]->{'taxkey'} eq "0"
              || $trans->[$j]->{'taxkey'} eq "1"
              || $trans->[$j]->{'taxkey'} eq "10"
              || $trans->[$j]->{'taxkey'} eq "11")) {
        my %new_trans = ();
        map { $new_trans{$_} = $trans->[$notsplitindex]->{$_}; } keys %{ $trans->[$notsplitindex] };

        $absumsatz               += $trans->[$j]->{'amount'};
        $new_trans{'amount'}      = $trans->[$j]->{'amount'} * (-1);
        $new_trans{'umsatz'}      = abs($trans->[$j]->{'amount'}) * $ml;
        $trans->[$j]->{'umsatz'}  = abs($trans->[$j]->{'amount'}) * $ml;

        push @{ $self->{DATEV} }, [ \%new_trans, $trans->[$j] ];

      } elsif (($j != $notsplitindex) && !$trans->[$j]->{is_tax}) {

        my %new_trans = ();
        map { $new_trans{$_} = $trans->[$notsplitindex]->{$_}; } keys %{ $trans->[$notsplitindex] };

        my $tax_rate              = $trans->[$j]->{'taxrate'};
        $new_trans{'net_amount'}  = $trans->[$j]->{'amount'} * -1;
        $new_trans{'tax_rate'}    = 1 + $tax_rate;

        if (!$trans->[$j]->{'invoice'}) {
          $new_trans{'amount'}      = $form->round_amount(-1 * ($trans->[$j]->{amount} + $trans->[$j]->{tax_amount}), 2);
          $new_trans{'umsatz'}      = abs($new_trans{'amount'}) * $ml;
          $trans->[$j]->{'umsatz'}  = $new_trans{'umsatz'};
          $absumsatz               += -1 * $new_trans{'amount'};

        } else {
          my $unrounded             = $trans->[$j]->{'amount'} * (1 + $tax_rate) * -1 + $rounding_error;
          my $rounded               = $form->round_amount($unrounded, 2);

          $rounding_error           = $unrounded - $rounded;
          $new_trans{'amount'}      = $rounded;
          $new_trans{'umsatz'}      = abs($rounded) * $ml;
          $trans->[$j]->{'umsatz'}  = $new_trans{umsatz};
          $absumsatz               -= $rounded;
        }

        push @{ $self->{DATEV} }, [ \%new_trans, $trans->[$j] ];
        push @taxed, $self->{DATEV}->[-1];
      }
    }

    my $idx        = 0;
    my $correction = 0;
    while ((abs($absumsatz) >= 0.01) && (abs($absumsatz) < 1.00)) {
      if ($idx >= scalar @taxed) {
        last if (!$correction);

        $correction = 0;
        $idx        = 0;
      }

      my $transaction = $taxed[$idx]->[0];

      my $old_amount     = $transaction->{amount};
      my $old_correction = $correction;
      my @possible_diffs;

      if (!$transaction->{diff}) {
        @possible_diffs = (0.01, -0.01);
      } else {
        @possible_diffs = ($transaction->{diff});
      }

      foreach my $diff (@possible_diffs) {
        my $net_amount = $form->round_amount(($transaction->{amount} + $diff) / $transaction->{tax_rate}, 2);
        next if ($net_amount != $transaction->{net_amount});

        $transaction->{diff}    = $diff;
        $transaction->{amount} += $diff;
        $transaction->{umsatz} += $diff;
        $absumsatz             -= $diff;
        $correction             = 1;

        last;
      }

      $idx++;
    }

    $absumsatz = $form->round_amount($absumsatz, 2);
    if (abs($absumsatz) >= (0.01 * (1 + scalar @taxed))) {
      $self->add_error("Datev-Export fehlgeschlagen! Bei Transaktion $trans->[0]->{trans_id} ($absumsatz)");

    } elsif (abs($absumsatz) >= 0.01) {
      $self->add_net_gross_differences($absumsatz);
    }
  }

  $sth->finish();

  $::lxdebug->leave_sub;
}

sub make_kne_data_header {
  $main::lxdebug->enter_sub();

  my ($self, $form) = @_;
  my ($primanota);

  my $stamm = $self->get_datev_stamm;

  my $jahr = $self->from ? $self->from->year : DateTime->today->year;

  #Header
  my $header  = "\x1D\x181";
  $header    .= _fill($stamm->{datentraegernr}, 3, ' ', 'left');
  $header    .= ($self->fromto) ? "11" : "13"; # Anwendungsnummer
  $header    .= _fill($stamm->{dfvkz}, 2, '0');
  $header    .= _fill($stamm->{beraternr}, 7, '0');
  $header    .= _fill($stamm->{mandantennr}, 5, '0');
  $header    .= _fill($stamm->{abrechnungsnr} . $jahr, 6, '0');

  $header .= $self->from ? $self->from->strftime('%d%m%y') : '';
  $header .= $self->to   ? $self->to->strftime('%d%m%y')   : '';

  if ($self->fromto) {
    $primanota = "001";
    $header .= $primanota;
  }

  $header .= _fill($stamm->{passwort}, 4, '0');
  $header .= " " x 16;       # Anwendungsinfo
  $header .= " " x 16;       # Inputinfo
  $header .= "\x79";

  #Versionssatz
  my $versionssatz  = $self->exporttype == DATEV_ET_BUCHUNGEN ? "\xB5" . "1," : "\xB6" . "1,";

  my $query         = qq|SELECT accno FROM chart LIMIT 1|;
  my $ref           = selectfirst_hashref_query($form, $self->dbh, $query);

  $versionssatz    .= length $ref->{accno};
  $versionssatz    .= ",";
  $versionssatz    .= length $ref->{accno};
  $versionssatz    .= ",SELF" . "\x1C\x79";

  $header          .= $versionssatz;

  $main::lxdebug->leave_sub();

  return $header;
}

sub datetofour {
  $main::lxdebug->enter_sub();

  my ($date, $six) = @_;

  my ($day, $month, $year) = split(/\./, $date);

  if ($day =~ /^0/) {
    $day = substr($day, 1, 1);
  }
  if (length($month) < 2) {
    $month = "0" . $month;
  }
  if (length($year) > 2) {
    $year = substr($year, -2, 2);
  }

  if ($six) {
    $date = $day . $month . $year;
  } else {
    $date = $day . $month;
  }

  $main::lxdebug->leave_sub();

  return $date;
}

sub trim_leading_zeroes {
  my $str = shift;

  $str =~ s/^0+//g;

  return $str;
}

sub make_ed_versionset {
  $main::lxdebug->enter_sub();

  my ($self, $header, $filename, $blockcount) = @_;

  my $versionset  = "V" . substr($filename, 2, 5);
  $versionset    .= substr($header, 6, 22);

  if ($self->fromto) {
    $versionset .= "0000" . substr($header, 28, 19);
  } else {
    my $datum = " " x 16;
    $versionset .= $datum . "001" . substr($header, 28, 4);
  }

  $versionset .= _fill($blockcount, 5, '0');
  $versionset .= "001";
  $versionset .= " 1";
  $versionset .= substr($header, -12, 10) . "    ";
  $versionset .= " " x 53;

  $main::lxdebug->leave_sub();

  return $versionset;
}

sub make_ev_header {
  $main::lxdebug->enter_sub();

  my ($self, $form, $fileno) = @_;

  my $stamm = $self->get_datev_stamm;

  my $ev_header  = _fill($stamm->{datentraegernr}, 3, ' ', 'left');
  $ev_header    .= "   ";
  $ev_header    .= _fill($stamm->{beraternr}, 7, ' ', 'left');
  $ev_header    .= _fill($stamm->{beratername}, 9, ' ', 'left');
  $ev_header    .= " ";
  $ev_header    .= (_fill($fileno, 5, '0')) x 2;
  $ev_header    .= " " x 95;

  $main::lxdebug->leave_sub();

  return $ev_header;
}

sub kne_buchungsexport {
  $main::lxdebug->enter_sub();

  my ($self) = @_;

  my $form = $::form;

  my @filenames;

  my $filename    = "ED00000";
  my $evfile      = "EV01";
  my @ed_versionset;
  my $fileno = 0;

  my $fromto = $self->fromto;

  $self->_get_transactions($fromto);

  return if $self->errors;

  my $counter = 0;

  while (scalar(@{ $self->{DATEV} || [] })) {
    my $umsatzsumme = 0;
    $filename++;
    my $ed_filename = $self->export_path . $filename;
    push(@filenames, $filename);
    my $header = $self->make_kne_data_header($form);

    my $kne_file = SL::DATEV::KNEFile->new();
    $kne_file->add_block($header);

    while (scalar(@{ $self->{DATEV} }) > 0) {
      my $transaction = shift @{ $self->{DATEV} };
      my $trans_lines = scalar(@{$transaction});
      $counter++;

      my $umsatz         = 0;
      my $gegenkonto     = "";
      my $konto          = "";
      my $belegfeld1     = "";
      my $datum          = "";
      my $waehrung       = "";
      my $buchungstext   = "";
      my $belegfeld2     = "";
      my $datevautomatik = 0;
      my $taxkey         = 0;
      my $charttax       = 0;
      my ($haben, $soll);
      my $iconv          = $::locale->{iconv_utf8};
      my %umlaute = ($iconv->convert('ä') => 'ae',
                     $iconv->convert('ö') => 'oe',
                     $iconv->convert('ü') => 'ue',
                     $iconv->convert('Ä') => 'Ae',
                     $iconv->convert('Ö') => 'Oe',
                     $iconv->convert('Ü') => 'Ue',
                     $iconv->convert('ß') => 'sz');
      for (my $i = 0; $i < $trans_lines; $i++) {
        if ($trans_lines == 2) {
          if (abs($transaction->[$i]->{'amount'}) > abs($umsatz)) {
            $umsatz = $transaction->[$i]->{'amount'};
          }
        } else {
          if (abs($transaction->[$i]->{'umsatz'}) > abs($umsatz)) {
            $umsatz = $transaction->[$i]->{'umsatz'};
          }
        }
        if ($transaction->[$i]->{'datevautomatik'}) {
          $datevautomatik = 1;
        }
        if ($transaction->[$i]->{'taxkey'}) {
          $taxkey = $transaction->[$i]->{'taxkey'};
        }
        if ($transaction->[$i]->{'charttax'}) {
          $charttax = $transaction->[$i]->{'charttax'};
        }
        if ($transaction->[$i]->{'amount'} > 0) {
          $haben = $i;
        } else {
          $soll = $i;
        }
      }

      # Umwandlung von Umlauten und Sonderzeichen in erlaubte Zeichen bei Textfeldern
      foreach my $umlaut (keys(%umlaute)) {
        $transaction->[$haben]->{'invnumber'} =~ s/${umlaut}/${umlaute{$umlaut}}/g;
        $transaction->[$haben]->{'name'}      =~ s/${umlaut}/${umlaute{$umlaut}}/g;
      }

      $transaction->[$haben]->{'invnumber'} =~ s/[^0-9A-Za-z\$\%\&\*\+\-\/]//g;
      $transaction->[$haben]->{'name'}      =~ s/[^0-9A-Za-z\$\%\&\*\+\-\ \/]//g;

      $transaction->[$haben]->{'invnumber'} =  substr($transaction->[$haben]->{'invnumber'}, 0, 12);
      $transaction->[$haben]->{'name'}      =  substr($transaction->[$haben]->{'name'}, 0, 30);
      $transaction->[$haben]->{'invnumber'} =~ s/\ *$//;
      $transaction->[$haben]->{'name'}      =~ s/\ *$//;

      if ($trans_lines >= 2) {

        $gegenkonto = "a" . trim_leading_zeroes($transaction->[$haben]->{'accno'});
        $konto      = "e" . trim_leading_zeroes($transaction->[$soll]->{'accno'});
        if ($transaction->[$haben]->{'invnumber'} ne "") {
          $belegfeld1 = "\xBD" . $transaction->[$haben]->{'invnumber'} . "\x1C";
        }
        $datum = "d";
        $datum .= &datetofour($transaction->[$haben]->{'transdate'}, 0);
        $waehrung = "\xB3" . "EUR" . "\x1C";
        if ($transaction->[$haben]->{'name'} ne "") {
          $buchungstext = "\x1E" . $transaction->[$haben]->{'name'} . "\x1C";
        }
        if ($transaction->[$haben]->{'duedate'} ne "") {
          $belegfeld2 = "\xBE" . &datetofour($transaction->[$haben]->{'duedate'}, 1) . "\x1C";
        }
      }

      $umsatz       = $kne_file->format_amount(abs($umsatz), 0);
      $umsatzsumme += $umsatz;
      $kne_file->add_block("+" . $umsatz);

      # Dies ist die einzige Stelle die datevautomatik auswertet. Was soll gesagt werden?
      # Im Prinzip hat jeder acc_trans Eintrag einen Steuerschlüssel, außer, bei gewissen Fällen
      # wie: Kreditorenbuchung mit negativen Vorzeichen, SEPA-Export oder Rechnungen die per
      # Skript angelegt werden.
      # Also falls ein Steuerschlüssel da ist und NICHT datevautomatik diesen Block hinzufügen.
      # Oder aber datevautomatik ist WAHR, aber der Steuerschlüssel in der acc_trans weicht
      # von dem in der Chart ab: Also wahrscheinlich Programmfehler (NULL übergeben, statt
      # DATEV-Steuerschlüssel) oder der Steuerschlüssel des Kontos weicht WIRKLICH von dem Eintrag in der
      # acc_trans ab. Gibt es für diesen Fall eine plausiblen Grund?
      #
      if (   ( $datevautomatik || $taxkey)
          && (!$datevautomatik || ($datevautomatik && ($charttax ne $taxkey)))) {
#         $kne_file->add_block("\x6C" . (!$datevautomatik ? $taxkey : "4"));
        $kne_file->add_block("\x6C${taxkey}");
      }

      $kne_file->add_block($gegenkonto);
      $kne_file->add_block($belegfeld1);
      $kne_file->add_block($belegfeld2);
      $kne_file->add_block($datum);
      $kne_file->add_block($konto);
      $kne_file->add_block($buchungstext);
      $kne_file->add_block($waehrung . "\x79");
    }

    my $mandantenendsumme = "x" . $kne_file->format_amount($umsatzsumme / 100.0, 14) . "\x79\x7a";

    $kne_file->add_block($mandantenendsumme);
    $kne_file->flush();

    open(ED, ">", $ed_filename) or die "can't open outputfile: $!\n";
    print(ED $kne_file->get_data());
    close(ED);

    $ed_versionset[$fileno] = $self->make_ed_versionset($header, $filename, $kne_file->get_block_count());
    $fileno++;
  }

  #Make EV Verwaltungsdatei
  my $ev_header = $self->make_ev_header($form, $fileno);
  my $ev_filename = $self->export_path . $evfile;
  push(@filenames, $evfile);
  open(EV, ">", $ev_filename) or die "can't open outputfile: EV01\n";
  print(EV $ev_header);

  foreach my $file (@ed_versionset) {
    print(EV $ed_versionset[$file]);
  }
  close(EV);
  ###

  $self->add_filenames(@filenames);

  $main::lxdebug->leave_sub();

  return { 'download_token' => $self->download_token, 'filenames' => \@filenames };
}

sub kne_stammdatenexport {
  $main::lxdebug->enter_sub();

  my ($self) = @_;
  my $form = $::form;

  $self->get_datev_stamm->{abrechnungsnr} = "99";

  my @filenames;

  my $filename    = "ED00000";
  my $evfile      = "EV01";
  my @ed_versionset;
  my $fileno          = 1;
  my $i               = 0;
  my $blockcount      = 1;
  my $remaining_bytes = 256;
  my $total_bytes     = 256;
  my $buchungssatz    = "";
  $filename++;
  my $ed_filename = $self->export_path . $filename;
  push(@filenames, $filename);
  open(ED, ">", $ed_filename) or die "can't open outputfile: $!\n";
  my $header = $self->make_kne_data_header($form);
  $remaining_bytes -= length($header);

  my $fuellzeichen;

  my (@where, @values) = ((), ());
  if ($self->accnofrom) {
    push @where, 'c.accno >= ?';
    push @values, $self->accnofrom;
  }
  if ($self->accnoto) {
    push @where, 'c.accno <= ?';
    push @values, $self->accnoto;
  }

  my $where_str = @where ? ' WHERE ' . join(' AND ', map { "($_)" } @where) : '';

  my $query     = qq|SELECT c.accno, c.description
                     FROM chart c
                     $where_str
                     ORDER BY c.accno|;

  my $sth = $self->dbh->prepare($query);
  $sth->execute(@values) || $form->dberror($query);

  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    if (($remaining_bytes - length("t" . $ref->{'accno'})) <= 6) {
      $fuellzeichen = ($blockcount * 256 - length($buchungssatz . $header));
      $buchungssatz .= "\x00" x $fuellzeichen;
      $blockcount++;
      $total_bytes = ($blockcount) * 256;
    }
    $buchungssatz .= "t" . $ref->{'accno'};
    $remaining_bytes = $total_bytes - length($buchungssatz . $header);
    $ref->{'description'} =~ s/[^0-9A-Za-z\$\%\&\*\+\-\/]//g;
    $ref->{'description'} = substr($ref->{'description'}, 0, 40);
    $ref->{'description'} =~ s/\ *$//;

    if (
        ($remaining_bytes - length("\x1E" . $ref->{'description'} . "\x1C\x79")
        ) <= 6
      ) {
      $fuellzeichen = ($blockcount * 256 - length($buchungssatz . $header));
      $buchungssatz .= "\x00" x $fuellzeichen;
      $blockcount++;
      $total_bytes = ($blockcount) * 256;
    }
    $buchungssatz .= "\x1E" . $ref->{'description'} . "\x1C\x79";
    $remaining_bytes = $total_bytes - length($buchungssatz . $header);
  }

  $sth->finish;
  print(ED $header);
  print(ED $buchungssatz);
  $fuellzeichen = 256 - (length($header . $buchungssatz . "z") % 256);
  my $dateiende = "\x00" x $fuellzeichen;
  print(ED "z");
  print(ED $dateiende);
  close(ED);

  #Make EV Verwaltungsdatei
  $ed_versionset[0] =
    $self->make_ed_versionset($header, $filename, $blockcount);

  my $ev_header = $self->make_ev_header($form, $fileno);
  my $ev_filename = $self->export_path . $evfile;
  push(@filenames, $evfile);
  open(EV, ">", $ev_filename) or die "can't open outputfile: EV01\n";
  print(EV $ev_header);

  foreach my $file (@ed_versionset) {
    print(EV $ed_versionset[$file]);
  }
  close(EV);

  $self->add_filenames(@filenames);

  $main::lxdebug->leave_sub();

  return { 'download_token' => $self->download_token, 'filenames' => \@filenames };
}

sub DESTROY {
  clean_temporary_directories();
}

1;

__END__

=encoding utf-8

=head1 NAME

SL::DATEV - kivitendo DATEV Export module

=head1 SYNOPSIS

  use SL::DATEV qw(:CONSTANTS);

  my $datev = SL::DATEV->new(
    exporttype => DATEV_ET_BUCHUNGEN,
    format     => DATEV_FORMAT_KNE,
    from       => $startdate,
    to         => $enddate,
  );

  my $datev = SL::DATEV->new(
    exporttype => DATEV_ET_STAMM,
    format     => DATEV_FORMAT_KNE,
    accnofrom  => $start_account_number,
    accnoto    => $end_account_number,
  );

  # get or set datev stamm
  my $hashref = $datev->get_datev_stamm;
  $datev->save_datev_stamm($hashref);

  # manually clean up temporary directories
  $datev->clean_temporary_directories;

  # export
  $datev->export;

  if ($datev->errors) {
    die join "\n", $datev->error;
  }

  # get relevant data for saving the export:
  my $dl_token = $datev->download_token;
  my $path     = $datev->export_path;
  my @files    = $datev->filenames;

  # retrieving an export at a later time
  my $datev = SL::DATEV->new(
    download_token => $dl_token_from_user,
  );

  my $path     = $datev->export_path;
  my @files    = glob("$path/*");

=head1 DESCRIPTION

This module implements the DATEV export standard. For usage see above.

=head1 FUNCTIONS

=over 4

=item new PARAMS

Generic constructor. See section attributes for information about hat to pass.

=item get_datev_stamm

Loads DATEV Stammdaten and returns as hashref.

=item save_datev_stamm HASHREF

Saves DATEV Stammdaten from provided hashref.

=item exporttype

See L<CONSTANTS> for possible values

=item has_exporttype

Returns true if an exporttype has been set. Without exporttype most report functions won't work.

=item format

Specifies the designated format of the export. Currently only KNE export is implemented.

See L<CONSTANTS> for possible values

=item has_format

Returns true if a format has been set. Without format most report functions won't work.

=item download_token

Returns a download token for this DATEV object.

Note: If either a download_token or export_path were set at the creation these are infered, otherwise randomly generated.

=item export_path

Returns an export_path for this DATEV object.

Note: If either a download_token or export_path were set at the creation these are infered, otherwise randomly generated.

=item filenames

Returns a list of filenames generated by this DATEV object. This only works if th files were generated during it's lifetime, not if the object was created from a download_token.

=item net_gross_differences

If there were any net gross differences during calculation they will be collected here.

=item sum_net_gross_differences

Sum of all differences.

=item clean_temporary_directories

Forces a garbage collection on previous exports which will delete all exports that are older than 8 hours. It will be automatically called on destruction of the object, but is advised to be called manually before delivering results of an export to the user.

=item errors

Returns a list of errors that occured. If no errors occured, the export was a success.

=item export

Exports data. You have to have set L<exporttype> and L<format> or an error will
occur. OBE exports are currently not implemented.

=back

=head1 ATTRIBUTES

This is a list of attributes set in either the C<new> or a method of the same name.

=over 4

=item dbh

Set a database handle to use in the process. This allows for an export to be
done on a transaction in progress without committing first.

=item exporttype

See L<CONSTANTS> for possible values. This MUST be set before export is called.

=item format

See L<CONSTANTS> for possible values. This MUST be set before export is called.

=item download_token

Can be set on creation to retrieve a prior export for download.

=item from

=item to

Set boundary dates for the export. Currently thse MUST be set for the export to work.

=item accnofrom

=item accnoto

Set boundary account numbers for the export. Only useful for a stammdaten export.

=back

=head1 CONSTANTS

=head2 Supplied to L<exporttype>

=over 4

=item DATEV_ET_BUCHUNGEN

=item DATEV_ET_STAMM

=back

=head2 Supplied to L<format>.

=over 4

=item DATEV_FORMAT_KNE

=item DATEV_FORMAT_OBE

=back

=head1 ERROR HANDLING

This module will die in the following cases:

=over 4

=item *

No or unrecognized exporttype or format was provided for an export

=item *

OBE rxport was called, which is not yet implemented.

=item *

general I/O errors

=back

Errors that occur during th actual export will be collected in L<errors>. The following types can occur at the moment:

=over 4

=item *

C<Unbalanced Ledger!>. Exactly that, your ledger is unbalanced. Should never occur.

=item *

C<Datev-Export fehlgeschlagen! Bei Transaktion %d (%f).>  This error occurs if a
transaction could not be reliably sorted out, or had rounding errors over the acceptable threshold.

=back

=head1 BUGS AND CAVEATS

=over 4

=item *

Handling of Vollvorlauf is currently not fully implemented. You must provide both from and to to get a working export.

=item *

OBE export is currently not implemented.

=back

=head1 TODO

- handling of export_path and download token is a bit dodgy, clean that up.

=head1 SEE ALSO

L<SL::DATEV::KNEFile>

=head1 AUTHORS

Philip Reetz E<lt>p.reetz@linet-services.deE<gt>,

Moritz Bunkus E<lt>m.bunkus@linet-services.deE<gt>,

Jan Büren E<lt>jan@lx-office-hosting.deE<gt>,

Geoffrey Richardson E<lt>information@lx-office-hosting.deE<gt>,

Sven Schöling E<lt>s.schoeling@linet-services.deE<gt>,

Stephan Köhler

=cut
