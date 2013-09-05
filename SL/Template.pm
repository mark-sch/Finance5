#====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#====================================================================

package SL::Template;

use strict;

use IO::Dir;

use SL::Template::Simple;
use SL::Template::Excel;
use SL::Template::HTML;
use SL::Template::LaTeX;
use SL::Template::OpenDocument;
use SL::Template::PlainText;
use SL::Template::ShellCommand;
use SL::Template::XML;

sub create {
  my %params  = @_;
  my $package = "SL::Template::" . $params{type};

  $package->new($params{file_name}, $params{form}, $params{myconfig} || \%::myconfig, $params{userspath} || $::lx_office_conf{paths}->{userspath});
}

sub available_templates {
  my ($class) = @_;

  # is there a templates basedir
  if (!-d $::lx_office_conf{paths}->{templates}) {
    $::form->error(sprintf($::locale->text("The directory %s does not exist."), $::lx_office_conf{paths}->{templates}));
  }

  tie my %dir_h, 'IO::Dir', $::lx_office_conf{paths}->{templates};

  my @alldir  = sort grep {
       -d ($::lx_office_conf{paths}->{templates} . "/$_")
    && !/^\.\.?$/
    && !m/\.(?:html|tex|sty|odt|xml|txb)$/
    && !m/^(?:webpages$|print$|mail$|\.)/
  } keys %dir_h;

  tie %dir_h, 'IO::Dir', "$::lx_office_conf{paths}->{templates}/print";
  my @allmaster = ('Standard', sort grep { -d ("$::lx_office_conf{paths}->{templates}/print" . "/$_") && !/^\.\.?$/ && !/^Standard$/ } keys %dir_h);

  return (
    print_templates  => \@alldir,
    master_templates => \@allmaster,
  );
}

1;
