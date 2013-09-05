package SL::Controller::Employee;

use strict;
use parent qw(SL::Controller::Base);

use SL::DB::Employee;
use SL::Helper::Flash;

__PACKAGE__->run_before('check_auth');
__PACKAGE__->run_before('load_all');
__PACKAGE__->run_before('load_from_form');
__PACKAGE__->run_before('assign_from_form');

our @updatable_columns = qw(deleted);

sub action_list {
  my ($self, %params) = @_;

  $self->render('employee/list', title => $::locale->text('Employees'));
}

sub action_edit {
  my ($self, %params) = @_;

  if ($self->{employee}) {
    $self->render('employee/edit', title => $::locale->text('Edit Employee #1', $self->{employee}->safe_name));
  } else {
    flash('error', $::locale->text('Could not load employee'));
    $self->redirect_to(action => 'list');
  }
}

sub action_save {
  my ($self, %params) = @_;

  $self->{employee}->save;

  flash('info', $::locale->text('Employee #1 saved!'));

  $self->redirect_to(action => 'edit', 'employee.id' => $self->{employee}->id);
}

#################### private stuff ##########################

sub check_auth {
  $::auth->assert('admin');
}

sub load_all {
  $_[0]{employees} = SL::DB::Manager::Employee->get_all;
}

sub load_from_form {
  $_[0]{employee} = SL::DB::Manager::Employee->find_by(id => delete $::form->{employee}{id});
}

sub assign_from_form {
  my %data = %{ $::form->{employee} || {} };

  return 1 unless keys %data;

  $_[0]{employee}->assign_attributes(map { $_ => $data{$_} } @updatable_columns);
  return 1;
}


######################## behaviour ##########################

sub delay_flash_on_redirect { 1 }

1;
