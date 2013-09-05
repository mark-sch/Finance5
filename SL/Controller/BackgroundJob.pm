package SL::Controller::BackgroundJob;

use strict;

use parent qw(SL::Controller::Base);

use SL::BackgroundJob::Base;
use SL::Controller::Helper::GetModels;
use SL::Controller::Helper::Paginated;
use SL::Controller::Helper::Sorted;
use SL::DB::BackgroundJob;
use SL::Helper::Flash;
use SL::Locale::String;
use SL::System::TaskServer;

use Rose::Object::MakeMethods::Generic
(
  scalar                  => [ qw(background_job) ],
  'scalar --get_set_init' => [ qw(task_server back_to) ],
);

__PACKAGE__->run_before('check_auth');
__PACKAGE__->run_before('check_task_server');
__PACKAGE__->run_before('load_background_job', only => [ qw(edit update destroy execute) ]);

__PACKAGE__->make_paginated(ONLY => [ qw(list) ]);

__PACKAGE__->make_sorted(
  ONLY         => [ qw(list) ],

  package_name => t8('Package name'),
  type         => t8('Execution type'),
  active       => t8('Active'),
  cron_spec    => t8('Execution schedule'),
  last_run_at  => t8('Last run at'),
  next_run_at  => t8('Next run at'),
);

#
# actions
#

sub action_list {
  my ($self) = @_;

  $self->render('background_job/list',
                title           => $::locale->text('Background jobs'),
                BACKGROUND_JOBS => $self->get_models);
}

sub action_new {
  my ($self) = @_;

  $self->background_job(SL::DB::BackgroundJob->new(cron_spec => '* * * * *',  package_name => 'Test'));
  $self->render('background_job/form',
                title       => $::locale->text('Create a new background job'),
                JOB_CLASSES => [ SL::BackgroundJob::Base->get_known_job_classes ]);
}

sub action_edit {
  my ($self) = @_;

  $self->render('background_job/form',
                title       => $::locale->text('Edit background job'),
                JOB_CLASSES => [ SL::BackgroundJob::Base->get_known_job_classes ]);
}

sub action_create {
  my ($self) = @_;

  $self->background_job(SL::DB::BackgroundJob->new);
  $self->create_or_update;
}

sub action_update {
  my ($self) = @_;
  $self->create_or_update;
}

sub action_destroy {
  my ($self) = @_;

  if (eval { $self->background_job->delete; 1; }) {
    flash_later('info',  $::locale->text('The background job has been deleted.'));
  } else {
    flash_later('error', $::locale->text('The background job could not be destroyed.'));
  }

  $self->redirect_to($self->back_to);
}

sub action_save_and_execute {
  my ($self) = @_;

  $self->background_job(SL::DB::BackgroundJob->new) if !$self->background_job;
  return unless $self->create_or_update;
  $self->action_execute;
}

sub action_execute {
  my ($self) = @_;

  my $history = $self->background_job->run;
  if ($history->status eq 'success') {
    flash_later('info', $::locale->text('The background job was executed successfully.'));
  } else {
    flash_later('error', $::locale->text('There was an error executing the background job.'));
  }

  $self->redirect_to(controller => 'BackgroundJobHistory',
                     action     => 'show',
                     id         => $history->id,
                     back_to    => $self->url_for(action => 'edit', id => $self->background_job->id));
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

sub create_or_update {
  my $self   = shift;
  my $return = shift;
  my $is_new = !$self->background_job->id;
  my $params = delete($::form->{background_job}) || { };

  $self->background_job->assign_attributes(%{ $params });

  my @errors = $self->background_job->validate;

  if (@errors) {
    flash('error', @errors);
    $self->render('background_job/form', title => $is_new ? $::locale->text('Create a new background job') : $::locale->text('Edit background job'));
    return;
  }

  $self->background_job->update_next_run_at;
  $self->background_job->save;

  flash_later('info', $is_new ? $::locale->text('The background job has been created.') : $::locale->text('The background job has been saved.'));
  return if $return;

  $self->redirect_to($self->back_to);
}

sub load_background_job {
  my ($self) = @_;
  $self->background_job(SL::DB::BackgroundJob->new(id => $::form->{id})->load);
}

sub init_task_server {
  return SL::System::TaskServer->new;
}

sub check_task_server {
  my ($self) = @_;
  flash('warning', $::locale->text('The task server does not appear to be running.')) if !$self->task_server->is_running;
}

sub init_back_to {
  my ($self) = @_;
  return $::form->{back_to} || $self->url_for(action => 'list');
}

1;
