#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use Pod::Usage;
use Term::ANSIColor;
our $master_templates;
BEGIN {
  unshift @INC, "modules/override"; # Use our own versions of various modules (e.g. YAML).
  push    @INC, "modules/fallback"; # Only use our own versions of modules if there's no system version.

  # this is a default dir. may be wrong in your installation, change it then
  $master_templates = './templates/print/';
}

unless (eval { require Config::Std; 1 }){
  print STDERR <<EOL ;
+------------------------------------------------------------------------------+
  Perl Modul Config::Std could not be loaded.

  Debian: you may install the needed *.deb package with:
    apt-get install libconfig-std-perl

  RPM: There is a rpm package "perl-Config-Std"

  Suse: you may install the needed *.rpm package with:
    zypper install perl-Config-Std

+------------------------------------------------------------------------------+
EOL

  exit 72;
}

use SL::InstallationCheck;
use SL::LxOfficeConf;


my %check;
Getopt::Long::Configure ("bundling");
GetOptions(
  "v|verbose"   => \ my $v,
  "a|all"       => \ $check{a},
  "o|optional!" => \ $check{o},
  "d|devel!"    => \ $check{d},
  "l|latex!"    => \ $check{l},
  "r|required!" => \ $check{r},
  "h|help"      => sub { pod2usage(-verbose => 2) },
  "c|color!"    => \ ( my $c = 1 ),
);

# if nothing is requested check "required"
my $default_run;
if (!defined $check{a}
 && !defined $check{l}
 && !defined $check{o}
 && !defined $check{d}) {
  $check{r} = 1;
  $default_run ='1';  # no parameter, therefore print a note after default run
}

if ($check{a}) {
  foreach my $check (keys %check) {
    $check{$check} = 1 unless defined $check{$check};
  }
}


$| = 1;

if (!SL::LxOfficeConf->read(undef, 'may fail')) {
  print_header('Could not load the config file. If you have dependancies from any features enabled in the configuration these will still show up as optional because of this. Please rerun this script after installing the dependancies needed to load the cofiguration.')
} else {
  SL::InstallationCheck::check_for_conditional_dependencies();
}

if ($check{r}) {
  print_header('Checking Required Modules');
  check_module($_, required => 1) for @SL::InstallationCheck::required_modules;
  print_header('Standard check for required modules done. See additional parameters for more checks (--help)') if $default_run;
}
if ($check{o}) {
  print_header('Checking Optional Modules');
  check_module($_, optional => 1) for @SL::InstallationCheck::optional_modules;
}
if ($check{d}) {
  print_header('Checking Developer Modules');
  check_module($_, devel => 1) for @SL::InstallationCheck::developer_modules;
}
if ($check{l}) {
  check_latex();
}

sub check_latex {
  my ($res) = check_kpsewhich();
  print_result("Looking for LaTeX kpsewhich", $res);
  if ($res) {
    check_template_dir($_) for SL::InstallationCheck::template_dirs($master_templates);
  }
}

sub check_template_dir {
  my ($dir) = @_;
  my $path  = $master_templates . $dir;

  print_header("Checking LaTeX Dependencies for Master Templates '$dir'");
  kpsewhich($path, 'cls', $_) for SL::InstallationCheck::classes_from_latex($path, '\documentclass');
  kpsewhich($path, 'sty', $_) for SL::InstallationCheck::classes_from_latex($path, '\usepackage');
}

our $mastertemplate_path = './templates/print/';

sub check_kpsewhich {
  return 1 if SL::InstallationCheck::check_kpsewhich();

  print STDERR <<EOL if $v;
+------------------------------------------------------------------------------+
  Can't find kpsewhich, is there a proper installed LaTeX?
  On Debian you may run "aptitude install texlive-base-bin"
+------------------------------------------------------------------------------+
EOL
  return 0;
}

sub kpsewhich {
  my ($dw, $type, $package) = @_;
  $package =~ s/[^-_0-9A-Za-z]//g;
  my $type_desc = $type eq 'cls' ? 'document class' : 'package';

  eval { use String::ShellQuote; 1 } or warn "can't load String::ShellQuote" && return;
     $dw         = shell_quote $dw;
  my $e_package  = shell_quote $package;
  my $e_type     = shell_quote $type;

  my $exit = system(qq|TEXINPUTS=".:$dw:" kpsewhich $e_package.$e_type > /dev/null|);
  my $res  = $exit > 0 ? 0 : 1;

  print_result("Looking for LaTeX $type_desc $package", $res);
  if (!$res) {
    print STDERR <<EOL if $v;
+------------------------------------------------------------------------------+
  LaTeX $type_desc $package could not be loaded.

  On Debian you may find the needed *.deb package with:
    apt-file search $package.$type

  Maybe you need to install apt-file first by:
    aptitude install apt-file && apt-file update
+------------------------------------------------------------------------------+
EOL
  }
}

sub check_module {
  my ($module, %role) = @_;

  my $line = "Looking for $module->{fullname}";
  $line   .= " (from $module->{dist_name})" if $module->{dist_name};
  my ($res, $ver) = SL::InstallationCheck::module_available($module->{"name"}, $module->{version});
  if ($res) {
    my $ver_string = ref $ver && $ver->can('numify') ? $ver->numify : $ver ? $ver : 'no version';
    print_line($line, $ver_string, 'green');
  } else {
    print_result($line, $res);
  }


  return if $res;

  my $needed_text =
      $role{optional} ? 'It is OPTIONAL for kivitendo but RECOMMENDED for improved functionality.'
    : $role{required} ? 'It is NEEDED by kivitendo and must be installed.'
    : $role{devel}    ? 'It is OPTIONAL for kivitendo and only useful for developers.'
    :                   'It is not listed as a dependancy yet. Please tell this the developers.';

  my @source_texts = module_source_texts($module);
  local $" = $/;
  print STDERR <<EOL if $v;
+------------------------------------------------------------------------------+
  $module->{fullname} could not be loaded.

  This module is either too old or not available on your system.
  $needed_text

  Here are some ideas how to get it:

@source_texts
+------------------------------------------------------------------------------+
EOL
}

sub module_source_texts {
  my ($module) = @_;
  my @texts;
  push @texts, <<EOL;
  - You can get it from CPAN:
      perl -MCPAN -e "install $module->{name}"
EOL
  push @texts, <<EOL if $module->{url};
  - You can download it from this URL and install it manually:
      $module->{url}
EOL
  push @texts, <<EOL if $module->{debian};
  - On Debian, Ubuntu and other distros you can install it with apt-get:
      sudo apt-get install $module->{debian}
    Note: These may be out of date as well if your system is old.
EOL
 # TODO: SuSE and Fedora packaging. Windows packaging.

  return @texts;
}

sub mycolor {
  return $_[0] unless $c;
  return colored(@_);
}

sub print_result {
  my ($test, $exit) = @_;
  if ($exit) {
    print_line($test, 'ok', 'green');
  } else {
    print_line($test, 'NOT ok', 'red');
  }
}

sub print_line {
  my ($text, $res, $color) = @_;
  print $text, " ", ('.' x (78 - length($text) - length($res))), " ", mycolor($res, $color), $/;
}

sub print_header {
  print $/;
  print "$_[0]:", $/;
}

1;

__END__

=encoding UTF-8

=head1 NAME

scripts/installation_check.pl - check kivitendo dependancies

=head1 SYNOPSIS

  scripts/installation_check.pl [OPTION]

=head1 DESCRIPTION

Check dependencys. List all perl modules needed by kivitendo, probes for them,
and warns if one is not available.  List all LaTeX document classes and
packages needed by kivitendo master templates, probes for them, and warns if
one is not available.


=head1 OPTIONS

=over 4

=item C<-a, --all>

Probe for all perl modules and all LaTeX master templates.

=item C<-c, --color>

Color output. Default on.

=item C<--no-color>

No color output. Helpful to avoid terminal escape problems.

=item C<-d, --devel>

Probe for perl developer dependancies. (Used for console  and tags file)

=item C<--no-devel>

Don't probe for perl developer dependancies. (Useful in combination with --all)

=item C<-h, --help>

Display this help.

=item C<-o, --optional>

Probe for optional modules.

=item C<--no-optional>

Don't probe for optional perl modules. (Useful in combination with --all)

=item C<-r, --required>

Probe for required perl modules (default).

=item C<--no-required>

Don't probe for required perl modules. (Useful in combination with --all)

=item C<-l. --latex>

Probe for LaTeX documentclasses and packages in master templates.

=item C<--no-latex>

Don't probe for LaTeX document classes and packages in master templates. (Useful in combination with --all)

=item C<-v. --verbose>

Print additional info for missing dependancies

=back

=head1 BUGS, CAVEATS and TODO

=over 4

=item *

Fedora packages not listed yet.

=item *

Not possible yet to generate a combined cpan/apt-get string to install all needed.

=item *

Not able to handle devel cpan modules yet.

=item *

Version requirements not fully tested yet.

=back

=head1 AUTHOR

  Moritz Bunkus E<lt>m.bunkus@linet-services.deE<gt>
  Sven Schöling E<lt>s.schoeling@linet-services.deE<gt>
  Wulf Coulmann E<lt>wulf@coulmann.deE<gt>

=cut
