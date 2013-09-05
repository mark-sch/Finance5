package SL::Controller::ClientConfig;

use strict;
use parent qw(SL::Controller::Base);

use File::Copy::Recursive ();
use List::Util qw(first);

use SL::DB::Chart;
use SL::DB::Currency;
use SL::DB::Default;
use SL::DB::Language;
use SL::DB::Unit;
use SL::Helper::Flash;
use SL::Locale::String qw(t8);
use SL::Template;

__PACKAGE__->run_before('check_auth');

use Rose::Object::MakeMethods::Generic (
  'scalar --get_set_init' => [ qw(defaults all_warehouses all_weightunits all_languages all_currencies all_templates posting_options payment_options accounting_options inventory_options profit_options accounts) ],
);

sub action_edit {
  my ($self, %params) = @_;

  $::form->{use_templates} = $self->defaults->templates ? 'existing' : 'new';
  $self->edit_form;
}

sub action_save {
  my ($self, %params)      = @_;

  my $defaults             = delete($::form->{defaults}) || {};
  my $entered_currencies   = delete($::form->{currencies}) || [];
  my $original_currency_id = $self->defaults->currency_id;

  # undef several fields if an empty value has been selected.
  foreach (qw(warehouse_id bin_id warehouse_id_ignore_onhand bin_id_ignore_onhand)) {
    undef $defaults->{$_} if !$defaults->{$_};
  }

  $self->defaults->assign_attributes(%{ $defaults });

  my %errors_idx;

  # Handle currencies
  my (%new_currency_names);
  foreach my $existing_currency (@{ $self->all_currencies }) {
    my $new_name     = $existing_currency->name;
    my $new_currency = first { $_->{id} == $existing_currency->id } @{ $entered_currencies };
    $new_name        = $new_currency->{name} if $new_currency;

    if (!$new_name) {
      $errors_idx{0} = t8('Currency names must not be empty.');
    } elsif ($new_currency_names{$new_name}) {
      $errors_idx{1} = t8('Currency names must be unique.');
    }

    if ($new_name) {
      $new_currency_names{$new_name} = 1;
      $existing_currency->name($new_name);
    }
  }

  if ($::form->{new_currency} && $new_currency_names{ $::form->{new_currency} }) {
    $errors_idx{1} = t8('Currency names must be unique.');
  }

  my @errors = map { $errors_idx{$_} } sort keys %errors_idx;

  # Check templates
  $::form->{new_templates}        =~ s:/::g;
  $::form->{new_master_templates} =~ s:/::g;

  if (($::form->{use_templates} eq 'existing') && ($self->defaults->templates !~ m:^templates/[^/]+$:)) {
    push @errors, t8('You must select existing print templates or create a new set.');

  } elsif ($::form->{use_templates} eq 'new') {
    if (!$::form->{new_templates}) {
      push @errors, t8('You must enter a name for your new print templates.');
    } elsif (-d "templates/" . $::form->{new_templates}) {
      push @errors, t8('A directory with the name for the new print templates exists already.');
    } elsif (! -d "templates/print/" . $::form->{new_master_templates}) {
      push @errors, t8('The master templates where not found.');
    }
  }

  # Show form again if there were any errors. Nothing's been changed
  # yet in the database.
  if (@errors) {
    flash('error', @errors);
    return $self->edit_form;
  }

  # Save currencies. As the names must be unique we cannot simply save
  # them as they are -- the user might want to swap to names. So make
  # them unique first and assign the actual names in a second step.
  my %currency_names_by_id = map { ($_->id => $_->name) } @{ $self->all_currencies };
  $_->update_attributes(name => '__039519735__' . $_->{id})        for @{ $self->all_currencies };
  $_->update_attributes(name => $currency_names_by_id{ $_->{id} }) for @{ $self->all_currencies };

  # Create new currency if required
  my $new_currency;
  if ($::form->{new_currency}) {
    $new_currency = SL::DB::Currency->new(name => $::form->{new_currency});
    $new_currency->save;
  }

  # If the user wants the new currency to be the default then replace
  # the ID placeholder with the proper value. However, if no new
  # currency has been created then don't change the value at all.
  if (-1 == $self->defaults->currency_id) {
    $self->defaults->currency_id($new_currency ? $new_currency->id : $original_currency_id);
  }

  # Create new templates if requested.
  if ($::form->{use_templates} eq 'new') {
    local $File::Copy::Recursive::SkipFlop = 1;
    File::Copy::Recursive::dircopy('templates/print/' . $::form->{new_master_templates}, 'templates/' . $::form->{new_templates});
    $self->defaults->templates('templates/' . $::form->{new_templates});
  }

  # Finally save defaults.
  $self->defaults->save;

  flash_later('info', t8('Client Configuration saved!'));

  $self->redirect_to(action => 'edit');
}

#
# initializers
#

sub init_defaults        { SL::DB::Default->get                                                                          }
sub init_all_warehouses  { SL::DB::Manager::Warehouse->get_all_sorted                                                    }
sub init_all_languages   { SL::DB::Manager::Language->get_all_sorted                                                     }
sub init_all_currencies  { SL::DB::Manager::Currency->get_all_sorted                                                     }
sub init_all_weightunits { my $unit = SL::DB::Manager::Unit->find_by(name => 'g'); $unit ? $unit->convertible_units : [] }
sub init_all_templates   { +{ SL::Template->available_templates }                                                        }

sub init_posting_options {
  [ { title => t8("never"),           value => 0           },
    { title => t8("every time"),      value => 1           },
    { title => t8("on the same day"), value => 2           }, ]
}

sub init_payment_options {
  [ { title => t8("never"),           value => 0           },
    { title => t8("every time"),      value => 1           },
    { title => t8("on the same day"), value => 2           }, ]
}

sub init_accounting_options {
  [ { title => t8("Accrual"),         value => "accrual"   },
    { title => t8("cash"),            value => "cash"      }, ]
}

sub init_inventory_options {
  [ { title => t8("perpetual"),       value => "perpetual" },
    { title => t8("periodic"),        value => "periodic"  }, ]
}

sub init_profit_options {
  [ { title => t8("balance"),         value => "balance"   },
    { title => t8("income"),          value => "income"    }, ]
}

sub init_accounts {
  my %accounts;

  foreach my $chart (@{ SL::DB::Manager::Chart->get_all(where => [ link => { like => '%IC%' } ], sort_by => 'accno ASC') }) {
    my %added;

    foreach my $link (split m/:/, $chart->link) {
      my $key = lc($link =~ /cogs/ ? 'IC_expense' : $link =~ /sale/ ? 'IC_income' : $link);
      next if $added{$key};

      $added{$key}      = 1;
      $accounts{$key} ||= [];
      push @{ $accounts{$key} }, $chart;
    }
  }

  $accounts{fx_gain} = SL::DB::Manager::Chart->get_all(where => [ category => 'I', charttype => 'A' ], sort_by => 'accno ASC');
  $accounts{fx_loss} = SL::DB::Manager::Chart->get_all(where => [ category => 'E', charttype => 'A' ], sort_by => 'accno ASC');
  $accounts{ar_paid} = SL::DB::Manager::Chart->get_all(where => [ link => { like => '%AR_paid%' }   ], sort_by => 'accno ASC');

  return \%accounts;
}

#
# filters
#

sub check_auth {
  $::auth->assert('admin');
}

#
# helpers
#

sub edit_form {
  my ($self) = @_;

  $self->render('client_config/form', title => t8('Client Configuration'),
                make_chart_title     => sub { $_[0]->accno . '--' . $_[0]->description },
                make_templates_value => sub { 'templates/' . $_[0] },
              );
}

1;
