package SL::DB::Helper::AttrDuration;

use strict;

use parent qw(Exporter);
our @EXPORT = qw(attr_duration);

use Carp;

sub attr_duration {
  my ($package, @attributes) = @_;

  _make($package, $_) for @attributes;
}

sub _make {
  my ($package, $attribute) = @_;

  no strict 'refs';

  *{ $package . '::' . $attribute . '_as_hours' } = sub {
    my ($self, $value) = @_;

    $self->$attribute(int($value) + ($self->$attribute - int($self->$attribute))) if @_ > 1;
    return int($self->$attribute // 0);
  };

  *{ $package . '::' . $attribute . '_as_minutes' } = sub {
    my ($self, $value) = @_;

    $self->$attribute(int($self->$attribute) * 1.0 + ($value // 0) / 60.0) if @_ > 1;
    return int(($self->$attribute // 0) * 60.0 + 0.5) % 60;
  };

  *{ $package . '::' . $attribute . '_as_duration_string' } = sub {
    my ($self, $value) = @_;

    $self->$attribute(defined($value) ? $::form->parse_amount(\%::myconfig, $value) * 1 : undef) if @_ > 1;
    return defined($self->$attribute) ? $::form->format_amount(\%::myconfig, $self->$attribute // 0, 2) : undef;
  };

  *{ $package . '::' . $attribute . '_as_man_days' } = sub {
    my ($self, $value) = @_;

    if (@_ > 1) {
      return undef if !defined $value;
      $self->$attribute($value);
    }
    $value = $self->$attribute // 0;
    return $value >= 8.0 ? $value / 8.0 : $value;
  };

  *{ $package . '::' . $attribute . '_as_man_days_unit' } = sub {
    my ($self, $unit) = @_;

    if (@_ > 1) {
      return undef if !defined $unit;
      croak "Unknown unit '${unit}'"                    if $unit !~ m/^(?:h|hour|man_day)$/;
      $self->$attribute(($self->$attribute // 0) * 8.0) if $unit eq 'man_day';
    }

    return ($self->$attribute // 0) >= 8.0 ? 'man_day' : 'h'
  };

  *{ $package . '::' . $attribute . '_as_man_days_string' } = sub {
    my ($self, $value) = @_;
    my $method         = "${attribute}_as_man_days";

    if (@_ > 1) {
      return undef if !defined $value;
      $self->$method($::form->parse_amount(\%::myconfig, $value));
    }

    return $::form->format_amount(\%::myconfig, $self->$method // 0, 2);
  };
}

1;
__END__

=pod

=encoding utf8

=head1 NAME

SL::DB::Helper::AttrDuration - Attribute helper for duration stored in
numeric columns

=head1 SYNOPSIS

  # In a Rose model:
  use SL::DB::Helper::AttrDuration;
  __PACKAGE__->attr_duration('time_estimation');

  # Read access:
  print "Minutes: " . $obj->time_estimation_as_minutes . " hours: " . $obj->time_estimation_as_hours . "\n";

  # Use formatted strings in input fields in templates:
  <form method="post">
    ...
    [% L.input_tag('time_estimation_as_duration_string', SELF.obj.time_estimation_as_duration_string) %]
  </form>

=head1 OVERVIEW

This is a helper for columns that store a duration as a numeric or
floating point number representing a number of hours. So the value
1.75 would stand for "1 hour, 45 minutes".

The helper methods created are:

=over 4

=item C<attribute_as_minutes [$new_value]>

Access only the minutes. Return values are in the range [0 - 59].

=item C<attribute_as_hours [$new_value]>

Access only the hours. Returns an integer value.

=item C<attribute_as_duration_string [$new_value]>

Access the full value as a formatted string according to the user's
locale settings.

=item C<attribute_as_man_days [$new_value]>

Access the attribute as a number of man days which are assumed to be 8
hours long. If the underlying attribute is less than 8 then the value
itself will be returned. Otherwise the value divided by 8 is returned.

If used as a setter then the underlying attribute is simply set to
 C<$new_value>. Intentional use is to set the man days first and the
 unit later, e.g.

  $obj->attribute_as_man_days($::form->{attribute_as_man_days});
  $obj->attribute_as_man_days_unit($::form->{attribute_as_man_days_unit});

Note that L<SL::DB::Object/assign_attributes> is aware of this and
handles this case correctly.

=item C<attribute_as_man_days_unit [$new_unit]>

Returns the unit that the number returned by L</attribute_as_man_days>
represents. This can be either C<h> if the underlying attribute is
less than 8 and C<man_day> otherwise.

If used as a setter then the underlying attribute is multiplied by 8
if C<$new_unit> equals C<man_day>. Otherwise the underlying attribute
is not modified. Intentional use is to set the man days first and the
unit later, e.g.

  $obj->attribute_as_man_days($::form->{attribute_as_man_days});
  $obj->attribute_as_man_days_unit($::form->{attribute_as_man_days_unit});

Note that L<SL::DB::Object/assign_attributes> is aware of this and
handles this case correctly.

=back

=head1 FUNCTIONS

=over 4

=item C<attr_duration @attributes>

Package method. Call with the names of attributes for which the helper
methods should be created.

=back

=head1 BUGS

Nothing here yet.

=head1 AUTHOR

Moritz Bunkus E<lt>m.bunkus@linet-services.deE<gt>

=cut
