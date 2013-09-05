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
#
#======================================================================

use POSIX qw(strftime getcwd);
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);

use SL::Common;
use SL::DATEV qw(:CONSTANTS);

use strict;

1;

# end of main

require "bin/mozilla/common.pl";

sub continue { call_sub($main::form->{"nextsub"}); }

sub export {
  $::lxdebug->enter_sub;
  $::auth->assert('datev_export');

  my $stamm = SL::DATEV->new->get_datev_stamm;

  $::form->header;
  print $::form->parse_html_template('datev/export', $stamm);

  $::lxdebug->leave_sub;
}

sub export2 {
  $::lxdebug->enter_sub;
  $::auth->assert('datev_export');

  if ($::form->{exporttype} == 0) {
    export_bewegungsdaten();
  } else {
    export_stammdaten();
  }
  $::lxdebug->leave_sub;
}

sub export_bewegungsdaten {
  $::lxdebug->enter_sub;
  $::auth->assert('datev_export');

  $::form->header;
  print $::form->parse_html_template('datev/export_bewegungsdaten');

  $::lxdebug->leave_sub;
}

sub export_stammdaten {
  $::lxdebug->enter_sub;
  $::auth->assert('datev_export');

  $::form->header;
  print $::form->parse_html_template('datev/export_stammdaten');

  $::lxdebug->leave_sub;
}

sub export3 {
  $::lxdebug->enter_sub;
  $::auth->assert('datev_export');

  my %data = (
    exporttype => $::form->{exporttype} ? DATEV_ET_STAMM : DATEV_ET_BUCHUNGEN,
    format     => $::form->{kne}        ? DATEV_FORMAT_KNE : DATEV_FORMAT_OBE,
  );

  if ($::form->{exporttype} == DATEV_ET_STAMM) {
    $data{accnofrom}  = $::form->{accnofrom},
    $data{accnoto}    = $::form->{accnoto},
  } elsif ($::form->{exporttype} == DATEV_ET_BUCHUNGEN) {
    @data{qw(from to)} = _get_dates(
      $::form->{zeitraum}, $::form->{monat}, $::form->{quartal},
      $::form->{transdatefrom}, $::form->{transdateto},
    );
  } else {
    die 'invalid exporttype';
  }

  my $datev = SL::DATEV->new(%data);

  $datev->clean_temporary_directories;
  $datev->save_datev_stamm($::form);

  $datev->export;

  if (!$datev->errors) {
    $::form->header;
    print $::form->parse_html_template('datev/export3', { datev => $datev });
  } else {
    $::form->error("Export schlug fehl.\n" . join "\n", $datev->errors);
  }

  $::lxdebug->leave_sub;
}

sub download {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my $locale   = $main::locale;

  $::auth->assert('datev_export');

  my $tmp_name = Common->tmpname();
  my $zip_name = strftime("kivitendo-datev-export-%Y%m%d.zip", localtime(time()));

  my $cwd = getcwd();

  my $datev = SL::DATEV->new(download_token => $form->{download_token});

  my $path = $datev->export_path;
  if (!$path) {
    $form->error($locale->text("Your download does not exist anymore. Please re-run the DATEV export assistant."));
  }

  chdir($path) || die("chdir $path");

  my @filenames = glob "*";

  if (!@filenames) {
    chdir($cwd);
    $form->error($locale->text("Your download does not exist anymore. Please re-run the DATEV export assistant."));
  }

  my $zip = Archive::Zip->new();
  map { $zip->addFile($_); } @filenames;
  $zip->writeToFileNamed($tmp_name);

  chdir($cwd);

  open(IN, $tmp_name) || die("open $tmp_name");
  $::locale->with_raw_io(\*STDOUT, sub {
    print("Content-Type: application/zip\n");
    print("Content-Disposition: attachment; filename=\"${zip_name}\"\n\n");
    while (<IN>) {
      print($_);
    }
  });
  close(IN);

  unlink($tmp_name);

  $main::lxdebug->leave_sub();
}

sub _get_dates {
  $::lxdebug->enter_sub;

  my ($mode, $month, $quarter, $transdatefrom, $transdateto) = @_;
  my ($fromdate, $todate);

  if ($mode eq "monat") {
    $fromdate = DateTime->new(day => 1, month => $month, year => DateTime->today->year);
    $todate   = $fromdate->clone->add(months => 1)->add(days => -1);
  } elsif ($mode eq "quartal") {
    die 'quarter out of of bounds' if $quarter < 1 || $quarter > 4;
    $fromdate = DateTime->new(day => 1, month => (3 * $quarter - 2), year => DateTime->today->year);
    $todate   = $fromdate->clone->add(months => 3)->add(days => -1);
  } elsif ($mode eq "zeit") {
    $fromdate = DateTime->from_lxoffice($transdatefrom);
    $todate   = DateTime->from_lxoffice($transdateto);
    die 'need from and to time' unless $fromdate && $todate;
  } else {
    die 'undefined interval mode';
  }

  $::lxdebug->leave_sub;

  return ($fromdate, $todate);
}
