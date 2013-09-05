package SL::DB::Employee;

use strict;

use SL::DB::MetaSetup::Employee;
use SL::DB::Manager::Employee;

__PACKAGE__->meta->initialize;

sub has_right {
  my $self  = shift;
  my $right = shift;

  return $::auth->check_right($self->login, $right);
}

sub safe_name {
  my ($self) = @_;

  return $self->name || $self->login;
}

1;
