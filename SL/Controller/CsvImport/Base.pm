package SL::Controller::CsvImport::Base;

use strict;

use List::MoreUtils qw(pairwise);

use SL::Helper::Csv;
use SL::DB::Currency;
use SL::DB::Customer;
use SL::DB::Language;
use SL::DB::PaymentTerm;
use SL::DB::Vendor;
use SL::DB::Contact;

use parent qw(Rose::Object);

use Rose::Object::MakeMethods::Generic
(
 scalar                  => [ qw(controller file csv test_run save_with_cascade) ],
 'scalar --get_set_init' => [ qw(profile displayable_columns existing_objects class manager_class cvar_columns all_cvar_configs all_languages payment_terms_by all_currencies default_currency_id all_vc vc_by) ],
);

sub run {
  my ($self, %params) = @_;

  $self->test_run($params{test_run});

  $self->controller->track_progress(phase => 'parsing csv', progress => 0);

  my $profile = $self->profile;
  $self->csv(SL::Helper::Csv->new(file                   => $self->file->file_name,
                                  encoding               => $self->controller->profile->get('charset'),
                                  class                  => $self->class,
                                  profile                => $profile,
                                  ignore_unknown_columns => 1,
                                  strict_profile         => 1,
                                  case_insensitive_header => 1,
                                  map { ( $_ => $self->controller->profile->get($_) ) } qw(sep_char escape_char quote_char),
                                 ));

  $self->controller->track_progress(progress => 10);

  my $old_numberformat      = $::myconfig{numberformat};
  $::myconfig{numberformat} = $self->controller->profile->get('numberformat');

  $self->csv->parse;

  $self->controller->track_progress(progress => 50);

  $self->controller->errors([ $self->csv->errors ]) if $self->csv->errors;

  return if ( !$self->csv->header || $self->csv->errors );

  my $headers         = { headers => [ grep { $profile->{$_} } @{ $self->csv->header } ] };
  $headers->{methods} = [ map { $profile->{$_} } @{ $headers->{headers} } ];
  $headers->{used}    = { map { ($_ => 1) }      @{ $headers->{headers} } };
  $self->controller->headers($headers);
  $self->controller->raw_data_headers({ used => { }, headers => [ ] });
  $self->controller->info_headers({ used => { }, headers => [ ] });

  my @objects  = $self->csv->get_objects;

  $self->controller->track_progress(progress => 70);

  my @raw_data = @{ $self->csv->get_data };

  $self->controller->track_progress(progress => 80);

  $self->controller->data([ pairwise { { object => $a, raw_data => $b, errors => [], information => [], info_data => {} } } @objects, @raw_data ]);

  $self->controller->track_progress(progress => 90);

  $self->check_objects;
  if ( $self->controller->profile->get('duplicates', 'no_check') ne 'no_check' ) {
    $self->check_std_duplicates();
    $self->check_duplicates();
  }
  $self->fix_field_lengths;

  $self->controller->track_progress(progress => 100);

  $::myconfig{numberformat} = $old_numberformat;
}

sub add_columns {
  my ($self, @columns) = @_;

  my $h = $self->controller->headers;

  foreach my $column (grep { !$h->{used}->{$_} } @columns) {
    $h->{used}->{$column} = 1;
    push @{ $h->{methods} }, $column;
    push @{ $h->{headers} }, $column;
  }
}

sub add_info_columns {
  my ($self, @columns) = @_;

  my $h = $self->controller->info_headers;

  foreach my $column (grep { !$h->{used}->{ $_->{method} } } map { ref $_ eq 'HASH' ? $_ : { method => $_, header => $_ } } @columns) {
    $h->{used}->{ $column->{method} } = 1;
    push @{ $h->{methods} }, $column->{method};
    push @{ $h->{headers} }, $column->{header};
  }
}

sub add_raw_data_columns {
  my ($self, @columns) = @_;

  my $h = $self->controller->raw_data_headers;

  foreach my $column (grep { !$h->{used}->{$_} } @columns) {
    $h->{used}->{$column} = 1;
    push @{ $h->{headers} }, $column;
  }
}

sub add_cvar_raw_data_columns {
  my ($self) = @_;

  map { $self->add_raw_data_columns($_) if exists $self->controller->data->[0]->{raw_data}->{$_} } @{ $self->cvar_columns };
}

sub init_all_cvar_configs {
  # Must be overridden by derived specialized importer classes.
  return [];
}

sub init_cvar_columns {
  my ($self) = @_;

  return [ map { "cvar_" . $_->name } (@{ $self->all_cvar_configs }) ];
}

sub init_all_languages {
  my ($self) = @_;

  return SL::DB::Manager::Language->get_all;
}

sub init_all_currencies {
  my ($self) = @_;

  return SL::DB::Manager::Currency->get_all;
}

sub init_default_currency_id {
  my ($self) = @_;

  return SL::DB::Default->get->currency_id;
}

sub init_payment_terms_by {
  my ($self) = @_;

  my $all_payment_terms = SL::DB::Manager::PaymentTerm->get_all;
  return { map { my $col = $_; ( $col => { map { ( $_->$col => $_ ) } @{ $all_payment_terms } } ) } qw(id description) };
}

sub init_all_vc {
  my ($self) = @_;

  return { customers => SL::DB::Manager::Customer->get_all,
           vendors   => SL::DB::Manager::Vendor->get_all };
}

sub force_allow_columns {
  return ();
}

sub init_vc_by {
  my ($self)    = @_;

  my %by_id     = map { ( $_->id => $_ ) } @{ $self->all_vc->{customers} }, @{ $self->all_vc->{vendors} };
  my %by_number = ( customers => { map { ( $_->customernumber => $_ ) } @{ $self->all_vc->{customers} } },
                    vendors   => { map { ( $_->vendornumber   => $_ ) } @{ $self->all_vc->{vendors}   } } );
  my %by_name   = ( customers => { map { ( $_->name           => $_ ) } @{ $self->all_vc->{customers} } },
                    vendors   => { map { ( $_->name           => $_ ) } @{ $self->all_vc->{vendors}   } } );

  return { id     => \%by_id,
           number => \%by_number,
           name   => \%by_name,   };
}

sub check_vc {
  my ($self, $entry, $id_column) = @_;

  if ($entry->{object}->$id_column) {
    $entry->{object}->$id_column(undef) if !$self->vc_by->{id}->{ $entry->{object}->$id_column };
  }

  if (!$entry->{object}->$id_column) {
    my $vc = $self->vc_by->{number}->{customers}->{ $entry->{raw_data}->{customernumber} }
          || $self->vc_by->{number}->{vendors}->{   $entry->{raw_data}->{vendornumber}   };
    $entry->{object}->$id_column($vc->id) if $vc;
  }

  if (!$entry->{object}->$id_column) {
    my $vc = $self->vc_by->{name}->{customers}->{ $entry->{raw_data}->{customer} }
          || $self->vc_by->{name}->{vendors}->{   $entry->{raw_data}->{vendor}   };
    $entry->{object}->$id_column($vc->id) if $vc;
  }

  if ($entry->{object}->$id_column) {
    $entry->{info_data}->{vc_name} = $self->vc_by->{id}->{ $entry->{object}->$id_column }->name;
  } else {
    push @{ $entry->{errors} }, $::locale->text('Error: Customer/vendor not found');
  }
}

sub handle_cvars {
  my ($self, $entry) = @_;

  my %type_to_column = ( text      => 'text_value',
                         textfield => 'text_value',
                         select    => 'text_value',
                         date      => 'timestamp_value_as_date',
                         timestamp => 'timestamp_value_as_date',
                         number    => 'number_value_as_number',
                         bool      => 'bool_value' );

  my @cvars;
  foreach my $config (@{ $self->all_cvar_configs }) {
    next unless exists $entry->{raw_data}->{ "cvar_" . $config->name };
    my $value  = $entry->{raw_data}->{ "cvar_" . $config->name };
    my $column = $type_to_column{ $config->type } || die "Program logic error: unknown custom variable storage type";

    push @cvars, SL::DB::CustomVariable->new(config_id => $config->id, $column => $value, sub_module => '');
  }

  $entry->{object}->custom_variables(\@cvars);
}

sub init_profile {
  my ($self) = @_;

  eval "require " . $self->class;

  my %unwanted = map { ( $_ => 1 ) } (qw(itime mtime), map { $_->name } @{ $self->class->meta->primary_key_columns });
  delete $unwanted{$_} for ($self->force_allow_columns);

  my %profile;
  for my $col ($self->class->meta->columns) {
    next if $unwanted{$col};

    my $name = $col->isa('Rose::DB::Object::Metadata::Column::Numeric')   ? "$col\_as_number"
      :        $col->isa('Rose::DB::Object::Metadata::Column::Date')      ? "$col\_as_date"
      :        $col->isa('Rose::DB::Object::Metadata::Column::Timestamp') ? "$col\_as_date"
      :                                                                     $col->name;

    $profile{$col} = $name;
  }

  $profile{ 'cvar_' . $_->name } = '' for @{ $self->all_cvar_configs };

  \%profile;
}

sub add_displayable_columns {
  my ($self, @columns) = @_;

  my @cols       = @{ $self->controller->displayable_columns || [] };
  my %ex_col_map = map { $_->{name} => $_ } @cols;

  foreach my $column (@columns) {
    if ($ex_col_map{ $column->{name} }) {
      @{ $ex_col_map{ $column->{name} } }{ keys %{ $column } } = @{ $column }{ keys %{ $column } };
    } else {
      push @cols, $column;
    }
  }

  $self->controller->displayable_columns([ sort { $a->{name} cmp $b->{name} } @cols ]);
}

sub setup_displayable_columns {
  my ($self) = @_;

  $self->add_displayable_columns(map { { name => $_ } } keys %{ $self->profile });
}

sub add_cvar_columns_to_displayable_columns {
  my ($self) = @_;

  $self->add_displayable_columns(map { { name        => 'cvar_' . $_->name,
                                         description => $::locale->text('#1 (custom variable)', $_->description) } }
                                     @{ $self->all_cvar_configs });
}

sub init_existing_objects {
  my ($self) = @_;

  eval "require " . $self->class;
  $self->existing_objects($self->manager_class->get_all);
}

sub init_class {
  die "class not set";
}

sub init_manager_class {
  my ($self) = @_;

  $self->class =~ m/^SL::DB::(.+)/;
  $self->manager_class("SL::DB::Manager::" . $1);
}

sub check_objects {
}

sub check_duplicates {
}

sub check_std_duplicates {
  my $self = shift;

  my $duplicates = {};

  my $all_fields = $self->get_duplicate_check_fields();

  foreach my $key (keys(%{ $all_fields })) {
    if ( $self->controller->profile->get('duplicates_'. $key) && (!exists($all_fields->{$key}->{std_check}) || $all_fields->{$key}->{std_check} )  ) {
      $duplicates->{$key} = {};
    }
  }

  my @duplicates_keys = keys(%{ $duplicates });

  if ( !scalar(@duplicates_keys) ) {
    return;
  }

  if ( $self->controller->profile->get('duplicates') eq 'check_db' ) {
    foreach my $object (@{ $self->existing_objects }) {
      foreach my $key (@duplicates_keys) {
        my $value = exists($all_fields->{$key}->{maker}) ? $all_fields->{$key}->{maker}->($object, $self) : $object->$key;
        $duplicates->{$key}->{$value} = 'db';
      }
    }
  }

  foreach my $entry (@{ $self->controller->data }) {
    if ( @{ $entry->{errors} } ) {
      next;
    }

    my $object = $entry->{object};

    foreach my $key (@duplicates_keys) {
      my $value = exists($all_fields->{$key}->{maker}) ? $all_fields->{$key}->{maker}->($object, $self) : $object->$key;

      if ( exists($duplicates->{$key}->{$value}) ) {
        push(@{ $entry->{errors} }, $duplicates->{$key}->{$value} eq 'db' ? $::locale->text('Duplicate in database') : $::locale->text('Duplicate in CSV file'));
        last;
      } else {
        $duplicates->{$key}->{$value} = 'csv';
      }

    }
  }

}

sub get_duplicate_check_fields {
  return {};
}

sub check_payment {
  my ($self, $entry) = @_;

  my $object = $entry->{object};

  # Check whether or not payment ID is valid.
  if ($object->payment_id && !$self->payment_terms_by->{id}->{ $object->payment_id }) {
    push @{ $entry->{errors} }, $::locale->text('Error: Invalid payment terms');
    return 0;
  }

  # Map name to ID if given.
  if (!$object->payment_id && $entry->{raw_data}->{payment}) {
    my $terms = $self->payment_terms_by->{description}->{ $entry->{raw_data}->{payment} };

    if (!$terms) {
      push @{ $entry->{errors} }, $::locale->text('Error: Invalid payment terms');
      return 0;
    }

    $object->payment_id($terms->id);
  }

  return 1;
}

sub save_objects {
  my ($self, %params) = @_;

  my $data = $params{data} || $self->controller->data;

  return unless $data->[0];
  return unless $data->[0]{object};

  $self->controller->track_progress(phase => 'saving data', progress => 0); # scale from 45..95%;

  my $dbh = $data->[0]{object}->db;

  $dbh->begin_work;
  foreach my $entry_index (0 .. $#$data) {
    my $entry = $data->[$entry_index];
    next if @{ $entry->{errors} };

    my $object = $entry->{object_to_save} || $entry->{object};

    if ( !$object->save(cascade => !!$self->save_with_cascade()) ) {
      push @{ $entry->{errors} }, $::locale->text('Error when saving: #1', $entry->{object}->db->error);
    } else {
      $self->controller->num_imported($self->controller->num_imported + 1);
    }
  } continue {
    if ($entry_index % 100 == 0) {
      $dbh->commit;
      $self->controller->track_progress(progress => $entry_index/scalar(@$data) * 100); # scale from 45..95%;
      $dbh->begin_work;
    }
  }
  $dbh->commit;
}

sub field_lengths {
  return ();
}

sub fix_field_lengths {
  my ($self) = @_;

  my %field_lengths = $self->field_lengths;
  foreach my $entry (@{ $self->controller->data }) {
    next unless @{ $entry->{errors} };
    map { $entry->{object}->$_(substr($entry->{object}->$_, 0, $field_lengths{$_})) if $entry->{object}->$_ } keys %field_lengths;
  }
}

sub clean_fields {
  my ($self, $illegal_chars, $object, @fields) = @_;

  my @cleaned_fields;
  foreach my $field (grep { $object->can($_) } @fields) {
    my $value = $object->$field;

    next unless defined($value) && ($value =~ s/$illegal_chars/ /g);

    $object->$field($value);
    push @cleaned_fields, $field;
  }

  return @cleaned_fields;
}

1;
