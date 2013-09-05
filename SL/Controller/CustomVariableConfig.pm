package SL::Controller::CustomVariableConfig;

use strict;

use parent qw(SL::Controller::Base);

use List::Util qw(first);

use SL::DB::CustomVariableConfig;
use SL::Helper::Flash;
use SL::Locale::String;

use Rose::Object::MakeMethods::Generic (
  scalar                  => [ qw(config module module_description flags) ],
  'scalar --get_set_init' => [ qw(translated_types modules) ],
);

__PACKAGE__->run_before('check_auth');
__PACKAGE__->run_before('check_module');
__PACKAGE__->run_before('load_config', only => [ qw(edit update destroy) ]);

our %translations = (
  text      => t8('Free-form text'),
  textfield => t8('Text field'),
  number    => t8('Number'),
  date      => t8('Date'),
  timestamp => t8('Timestamp'),
  bool      => t8('Yes/No (Checkbox)'),
  select    => t8('Selection'),
  customer  => t8('Customer'),
  vendor    => t8('Vendor'),
  part      => t8('Part'),
);

our @types = qw(text textfield number date bool select customer vendor part); # timestamp

#
# actions
#

sub action_list {
  my ($self) = @_;

  my $configs = SL::DB::Manager::CustomVariableConfig->get_all_sorted(where => [ module => $self->module ]);

  $::form->header;
  $self->render('custom_variable_config/list',
                title   => t8('List of custom variables'),
                CONFIGS => $configs);
}

sub action_new {
  my ($self) = @_;

  $self->config(SL::DB::CustomVariableConfig->new(module => $self->module));
  $self->show_form(title => t8('Add custom variable'));
}

sub show_form {
  my ($self, %params) = @_;

  $self->flags([
    map { split m/=/, 2 }
    split m/;/, ($self->config->flags || '')
  ]);

  $self->render('custom_variable_config/form', %params);
}

sub action_edit {
  my ($self) = @_;

  $self->show_form(title => t8('Edit custom variable'));
}

sub action_create {
  my ($self) = @_;

  $self->config(SL::DB::CustomVariableConfig->new);
  $self->create_or_update;
}

sub action_update {
  my ($self) = @_;
  $self->create_or_update;
}

sub action_destroy {
  my ($self) = @_;

  if (eval { $self->config->delete; 1; }) {
    flash_later('info',  t8('The custom variable has been deleted.'));
  } else {
    flash_later('error', t8('The custom variable is in use and cannot be deleted.'));
  }

  $self->redirect_to(action => 'list');
}

sub action_reorder {
  my ($self) = @_;

  SL::DB::CustomVariableConfig->reorder_list(@{ $::form->{cvarcfg_id} || [] });

  $self->render(\'', { type => 'json' });
}

#
# filters
#

sub check_auth {
  $::auth->assert('config');
}

sub check_module {
  my ($self)          = @_;

  $::form->{module} ||= 'CT';
  my $mod_desc        = first { $_->{module} eq $::form->{module} } @{ $self->modules };
  die "Invalid 'module' parameter '" . $::form->{module} . "'" if !$mod_desc;

  $self->module($mod_desc->{module});
  $self->module_description($mod_desc->{description});
}

sub load_config {
  my ($self) = @_;

  $self->config(SL::DB::CustomVariableConfig->new(id => $::form->{id})->load);
}

#
# helpers
#

sub get_translation {
  my ($self, $type) = @_;

  return $translations{$type};
}

sub init_translated_types {
  my ($self) = @_;

  return [ map { { type => $_, translation => $translations{$_} } } @types ];
}

sub init_modules {
  my ($self, %params) = @_;

  return [
    { module => 'CT',       description => t8('Customers and vendors')          },
    { module => 'Contacts', description => t8('Contact persons')                },
    { module => 'IC',       description => t8('Parts, services and assemblies') },
    { module => 'Projects', description => t8('Projects')                       },
  ];
}

sub create_or_update {
  my ($self) = @_;
  my $is_new = !$self->config->id;

  my $params = delete($::form->{config}) || { };
  delete $params->{id};

  $params->{default_value}       = $::form->parse_amount(\%::myconfig, $params->{default_value}) if $params->{type} eq 'number';
  $params->{included_by_default} = 0                                                             if !$params->{includeable};
  $params->{flags}               = join ':', map { m/^flag_(.*)/; "${1}=" . delete($params->{$_}) } grep { m/^flag_/ } keys %{ $params };

  $self->config->assign_attributes(%{ $params }, module => $self->module);

  my @errors = $self->config->validate;

  if (@errors) {
    flash('error', @errors);
    $self->show_form(title => $is_new ? t8('Add new custom variable') : t8('Edit custom variable'));
    return;
  }

  $self->config->save;

  flash_later('info', $is_new ? t8('The custom variable has been created.') : t8('The custom variable has been saved.'));
  $self->redirect_to(action => 'list', module => $self->module);
}

1;
