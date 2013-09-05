package SL::Layout::Base;

use strict;
use parent qw(Rose::Object);

use List::MoreUtils qw(uniq);
use Time::HiRes qw();

use Rose::Object::MakeMethods::Generic (
  'scalar --get_set_init' => [ qw(menu auto_reload_resources_param) ],
  'scalar'                => qw(focus),
  'array'                 => [
    'add_stylesheets_inline' => { interface => 'add', hash_key => 'stylesheets_inline' },
    'add_javascripts_inline' => { interface => 'add', hash_key => 'javascripts_inline' },
    'sub_layouts',           => { interface => 'get_set_init' },
    'add_sub_layouts'        => { interface => 'add', hash_key => 'sub_layouts' },
  ],
);

use SL::Menu;
use SL::Presenter;

my %menu_cache;

sub new {
  my ($class, @slurp) = @_;

  my $self = $class->SUPER::new(@slurp);
}

sub init_menu {
  my @menu_files = qw(menus/erp.ini);
  unshift @menu_files, 'menus/crm.ini' if $::instance_conf->crm_installed;
  Menu->new(@menu_files);
}

sub init_auto_reload_resources_param {
  return '' unless $::lx_office_conf{debug}->{auto_reload_resources};
  return sprintf('?rand=%d-%d-%d', Time::HiRes::gettimeofday(), int(rand 1000000000000));
}

##########################################
#  inheritable/overridable
##########################################

sub pre_content {
  join '', map { $_->pre_content } $_[0]->sub_layouts;
}

sub start_content {
  join '', map { $_->start_content } $_[0]->sub_layouts;
}

sub end_content {
  join '', map { $_->end_content } $_[0]->sub_layouts;
}

sub post_content {
  join '', map { $_->post_content } $_[0]->sub_layouts;
}

sub stylesheets_inline {
  uniq ( map { $_->stylesheets_inline } $_[0]->sub_layouts ),
  @{ $_[0]->{stylesheets_inline} || [] };
}

sub javascripts_inline {
  uniq ( map { $_->javascripts_inline } $_[0]->sub_layouts ),
  @{ $_[0]->{javascripts_inline} || [] };
}

sub init_sub_layouts { [] }


#########################################
# Interface
########################################

sub add_stylesheets {
  &use_stylesheet;
}

sub use_stylesheet {
  my $self = shift;
  push @{ $self->{stylesheets} ||= [] }, @_ if @_;
  @{ $self->{stylesheets} ||= [] };
}

sub stylesheets {
  my ($self) = @_;
  my $css_path = $self->get_stylesheet_for_user;

  return uniq grep { $_ } map { $self->_find_stylesheet($_, $css_path)  }
    $self->use_stylesheet, map { $_->stylesheets } $self->sub_layouts;
}

sub _find_stylesheet {
  my ($self, $stylesheet, $css_path) = @_;

  return "$css_path/$stylesheet" if -f "$css_path/$stylesheet";
  return "css/$stylesheet"       if -f "css/$stylesheet";
  return $stylesheet             if -f $stylesheet;
}

sub get_stylesheet_for_user {
  my $css_path = 'css';
  if (my $user_style = $::myconfig{stylesheet}) {
    $user_style =~ s/\.css$//; # nuke trailing .css, this is a remnand of pre 2.7.0 stylesheet handling
    if (-d "$css_path/$user_style" &&
        -f "$css_path/$user_style/main.css") {
      $css_path = "$css_path/$user_style";
    } else {
      $css_path = "$css_path/finance5";
    }
  } else {
    $css_path = "$css_path/finance5";
  }
  $::myconfig{css_path} = $css_path; # needed for menunew, FIXME: don't do this here

  return $css_path;
}

sub add_javascripts {
  &use_javascript
}

sub use_javascript {
  my $self = shift;
  push @{ $self->{javascripts} ||= [] }, @_ if @_;
  @{ $self->{javascripts} ||= [] };
}

sub javascripts {
  my ($self) = @_;

  return uniq grep { $_ } map { $self->_find_javascript($_)  }
    map({ $_->javascripts } $self->sub_layouts), $self->use_javascript;
}

sub _find_javascript {
  my ($self, $javascript) = @_;

  return "js/$javascript"        if -f "js/$javascript";
  return $javascript             if -f $javascript;
}


############################################
# track state of form header
############################################

sub header_done {
  $_[0]{_header_done} = 1;
}

sub need_footer {
  $_[0]{_header_done};
}

sub presenter {
  SL::Presenter->get;
}

1;

__END__

=encoding utf-8

=head1 NAME

SL::Layout::Base - Base class for layouts

=head1 SYNOPSIS

  package SL::Layout::MyLayout;

  use parent qw(SL::Layout::Base);

=head1 DESCRIPTION

For a description about the external interface of layouts in general see
L<SL::Layout::Dispatcher>.

This is a base class for layouts in general. It provides the basic interface
and some capabilities to extend and cascade layouts.


=head1 IMPLEMENTING LAYOUT CALLBACKS

There are eight callbacks (C<pre_content>, C<post_content>, C<start_content>,
C<end_content>, C<stylesheets>, C<stylesheets_inline>, C<javscripts>,
C<javascripts_inline>) which are documented in L<SL::Layout::Dispatcher>. If
you are writing a new simple layout, you can just override some of them like
this:

  package SL::Layout::MyEvilLayout;

  sub pre_content {
    '<h1>This is MY page now</h1>'
  }

  sub post_content {
    '<p align="right"><small><em>Brought to you by my own layout class</em></small></p>'
  }


To preserve the sanitizing effects of C<stylesheets> and C<javascripts> you should instead do the following:

  sub stylesheets {
    $_[0]->add_stylesheets(qw(mystyle1.css mystyle2.css);
    $_[0]->SUPER::stylesheets;
  }

If you want to add something to a different layout, you should write a sub
layout and add it to the other layouts.


=head1 SUB LAYOUTS

Layouts can be aggregated, so that common elements can be used in different
layouts. Currently this is used for the L<None|SL::Layout::None> sub layout,
which contains a lot of the stylesheets and javascripts necessary. Another
example is the L<Top|SL::Layout::Top> layout, which is used to generate a
common top bar for all menu types.

To add a sub layout to your layout just overwrite the sub_layout method:

  package SL::Layout::MyFinalLayout;

  sub init_sub_layout {
    [
      SL::Layout::None->new,
      SL::Layout::MyEvilLayout->new,
    ]
  }

You can also add a sublayout at runtime:

  $layout->add_sub_layout(SL::Layout::SideBar->new);

The standard implementation for the callbacks will see to it that the contents
of all sub layouts will get rendered.


=head1 COMBINING SUB LAYOUTS AND OWN BEHAVIOUR

This is still somewhat rough, and improvements are welcome.

For the C<*_content> callbacks this works if you just remember to dispatch to the base method:

  sub post_content {
    return $_[0]->render_status_bar .
    $_[0]->SUPER::post_content
  }

For the stylesheet and javascript callbacks things are hard, because of the
backwards compatibility, and the built-in sanity checks. The best way currently
is to just add your content and dispatch to the base method.

  sub stylesheets {
    $_[0]->add_stylesheets(qw(mystyle1.css mystyle2.css);
    $_[0]->SUPER::stylesheets;
  }

=head1 GORY DETAILS ABOUT JAVASCRIPT AND STYLESHEET OVERLOADING

The original code used to store one stylehsheet in C<< $form->{stylesheet} >> and
allowed/expected authors of potential C<bin/mozilla/> controllers to change
that into their own modified stylesheet.

This was at some point cleaned up into a method C<use stylesheet> which took a
string of space separated stylesheets and processed them into the response.

A lot of controllers are still using this methods so the layout interface
supports it to change as few controller code as possible, while providing the
more intuitive C<add_stylesheets> method.

At the same time the following things need to be possible:

=over 4

=item 1.

Runtime additions.

  $layout->add_stylesheets(...)

Since add_stylesheets adds to C<< $self->{stylesheets} >> there must be a way to read
from it. Currently this is the deprecated C<use_stylesheet>.

=item 2.

Overriding Callbacks

A leaf layout should be able to override a callback to return a list.

=item 3.

Sanitizing

C<stylesheets> needs to retain it's sanitizing behaviour.

=item 4.

Aggregation

The standard implementation should be able to collect from sub layouts.

=item 5.

Preserving of Inclusion Order

Since there is currently no standard way of mixing own content and including
sub layouts, this has to be done manually. Certain things like jquery get added
in L<SL::Layout::None> so that they get rendered first.

=back

The current implementation provides no good candidate for overriding in sub
classes, which should be changed. The other points work pretty well.

=head1 BUGS

None yet, if you don't count the horrible stylesheet/javascript interface.

=head1 AUTHOR

Sven Schöling E<lt>s.schoeling@linet-services.deE<gt>

=cut
