package SL::Template::Plugin::L;

use base qw( Template::Plugin );
use Template::Plugin;
use Data::Dumper;
use List::MoreUtils qw(apply);
use List::Util qw(max);
use Scalar::Util qw(blessed);

use SL::Presenter;
use SL::Util qw(_hashify);

use strict;

{ # This will give you an id for identifying html tags and such.
  # It's guaranteed to be unique unless you exceed 10 mio calls per request.
  # Do not use these id's to store information across requests.
my $_id_sequence = int rand 1e7;
sub _tag_id {
  return "id_" . ( $_id_sequence = ($_id_sequence + 1) % 1e7 );
}
}

sub _H {
  my $string = shift;
  return $::locale->quote_special_chars('HTML', $string);
}

sub _J {
  my $string = shift;
  $string    =~ s/(\"|\'|\\)/\\$1/g;
  return $string;
}

sub new {
  my ($class, $context, @args) = @_;

  return bless {
    CONTEXT => $context,
  }, $class;
}

sub _context {
  die 'not an accessor' if @_ > 1;
  return $_[0]->{CONTEXT};
}

sub _call_presenter {
  my ($method, $self, @args) = @_;

  my $presenter              = $::request->presenter;

  if (!$presenter->can($method)) {
    $::lxdebug->message(LXDebug::WARN(), "SL::Presenter has no method named '$method'!");
    return '';
  }

  splice @args, -1, 1, %{ $args[-1] } if @args && (ref($args[-1]) eq 'HASH');

  $presenter->$method(@args);
}

sub name_to_id    { return _call_presenter('name_to_id',    @_); }
sub html_tag      { return _call_presenter('html_tag',      @_); }
sub select_tag    { return _call_presenter('select_tag',    @_); }
sub input_tag     { return _call_presenter('input_tag',     @_); }
sub truncate      { return _call_presenter('truncate',      @_); }
sub simple_format { return _call_presenter('simple_format', @_); }
sub part_picker   { return _call_presenter('part_picker',   @_); }

sub _set_id_attribute {
  my ($attributes, $name) = @_;
  SL::Presenter::Tag::_set_id_attribute($attributes, $name);
}

sub img_tag {
  my ($self, %options) = _hashify(1, @_);

  $options{alt} ||= '';

  return $self->html_tag('img', undef, %options);
}

sub textarea_tag {
  my ($self, $name, $content, %attributes) = _hashify(3, @_);

  _set_id_attribute(\%attributes, $name);
  $attributes{rows}  *= 1; # required by standard
  $attributes{cols}  *= 1; # required by standard
  $content            = $content ? _H($content) : '';

  return $self->html_tag('textarea', $content, %attributes, name => $name);
}

sub checkbox_tag {
  my ($self, $name, %attributes) = _hashify(2, @_);

  _set_id_attribute(\%attributes, $name);
  $attributes{value}   = 1 unless defined $attributes{value};
  my $label            = delete $attributes{label};
  my $checkall         = delete $attributes{checkall};

  if ($attributes{checked}) {
    $attributes{checked} = 'checked';
  } else {
    delete $attributes{checked};
  }

  my $code  = $self->html_tag('input', undef,  %attributes, name => $name, type => 'checkbox');
  $code    .= $self->html_tag('label', $label, for => $attributes{id}) if $label;
  $code    .= $self->javascript(qq|\$('#$attributes{id}').checkall('$checkall');|) if $checkall;

  return $code;
}

sub radio_button_tag {
  my ($self, $name, %attributes) = _hashify(2, @_);

  _set_id_attribute(\%attributes, $name);
  $attributes{value}   = 1 unless exists $attributes{value};
  my $label            = delete $attributes{label};

  if ($attributes{checked}) {
    $attributes{checked} = 'checked';
  } else {
    delete $attributes{checked};
  }

  my $code  = $self->html_tag('input', undef,  %attributes, name => $name, type => 'radio');
  $code    .= $self->html_tag('label', $label, for => $attributes{id}) if $label;

  return $code;
}

sub hidden_tag {
  my ($self, $name, $value, %attributes) = _hashify(3, @_);
  return $self->input_tag($name, $value, %attributes, type => 'hidden');
}

sub div_tag {
  my ($self, $content, @slurp) = @_;
  return $self->html_tag('div', $content, @slurp);
}

sub ul_tag {
  my ($self, $content, @slurp) = @_;
  return $self->html_tag('ul', $content, @slurp);
}

sub li_tag {
  my ($self, $content, @slurp) = @_;
  return $self->html_tag('li', $content, @slurp);
}

sub link {
  my ($self, $href, $content, %params) = _hashify(3, @_);

  $href ||= '#';

  return $self->html_tag('a', $content, %params, href => $href);
}

sub submit_tag {
  my ($self, $name, $value, %attributes) = _hashify(3, @_);

  if ( $attributes{confirm} ) {
    $attributes{onclick} = 'return confirm("'. _J(delete($attributes{confirm})) .'");';
  }

  return $self->input_tag($name, $value, %attributes, type => 'submit', class => 'submit');
}

sub button_tag {
  my ($self, $onclick, $value, %attributes) = _hashify(3, @_);

  _set_id_attribute(\%attributes, $attributes{name}) if $attributes{name};
  $attributes{type} ||= 'button';

  $onclick = 'if (!confirm("'. _J(delete($attributes{confirm})) .'")) return false; ' . $onclick if $attributes{confirm};

  return $self->html_tag('input', undef, %attributes, value => $value, onclick => $onclick);
}

sub ajax_submit_tag {
  my ($self, $url, $form_selector, $text, @slurp) = @_;

  $url           = _J($url);
  $form_selector = _J($form_selector);
  my $onclick    = qq|kivi.submit_ajax_form('${url}', '${form_selector}')|;

  return $self->button_tag($onclick, $text, @slurp);
}

sub yes_no_tag {
  my ($self, $name, $value, %attributes) = _hashify(3, @_);

  return $self->select_tag($name, [ [ 1 => $::locale->text('Yes') ], [ 0 => $::locale->text('No') ] ], default => $value ? 1 : 0, %attributes);
}

sub javascript {
  my ($self, $data) = @_;
  return $self->html_tag('script', $data, type => 'text/javascript');
}

sub stylesheet_tag {
  my $self = shift;
  my $code = '';

  foreach my $file (@_) {
    $file .= '.css'        unless $file =~ m/\.css$/;
    $file  = "css/${file}" unless $file =~ m|/|;

    $code .= qq|<link rel="stylesheet" href="${file}" type="text/css" media="screen" />|;
  }

  return $code;
}

my $date_tag_id_idx = 0;
sub date_tag {
  my ($self, $name, $value, %params) = _hashify(3, @_);

  _set_id_attribute(\%params, $name);
  my @onchange = $params{onchange} ? (onChange => delete $params{onchange}) : ();
  my @classes  = $params{no_cal} || $params{readonly} ? () : ('datepicker');
  push @classes, delete($params{class}) if $params{class};
  my %class    = @classes ? (class => join(' ', @classes)) : ();

  $::request->presenter->need_reinit_widgets($params{id});

  return $self->input_tag(
    $name, blessed($value) ? $value->to_lxoffice : $value,
    size   => 11,
    onblur => "check_right_date_format(this);",
    %params,
    %class, @onchange,
  );
}

sub customer_picker {
  my ($self, $name, $value, %params) = @_;
  my $name_e    = _H($name);

  $::request->{layout}->add_javascripts('autocomplete_customer.js');

  $self->hidden_tag($name, (ref $value && $value->can('id') ? $value->id : ''), class => 'customer_autocomplete') .
  $self->input_tag("$name_e\_name", (ref $value && $value->can('name')) ? $value->name : '', %params);
}

# simple version with select_tag
sub vendor_selector {
  my ($self, $name, $value, %params) = @_;

  my $actual_vendor_id = (defined $::form->{"$name"})? ((ref $::form->{"$name"}) ? $::form->{"$name"}->id : $::form->{"$name"}) :
                         (ref $value && $value->can('id')) ? $value->id : '';

  return $self->select_tag($name, SL::DB::Manager::Vendor->get_all(),
                                  default      => $actual_vendor_id,
                                  title_sub    => sub { $_[0]->vendornumber . " : " . $_[0]->name },
                                  'with_empty' => 1,
                                  %params);
}


# simple version with select_tag
sub part_selector {
  my ($self, $name, $value, %params) = @_;

  my $actual_part_id = (defined $::form->{"$name"})? ((ref $::form->{"$name"})? $::form->{"$name"}->id : $::form->{"$name"}) :
                       (ref $value && $value->can('id')) ? $value->id : '';

  return $self->select_tag($name, SL::DB::Manager::Part->get_all(),
                           default      => $actual_part_id,
                           title_sub    => sub { $_[0]->partnumber . " : " . $_[0]->description },
                           with_empty   => 1,
                           %params);
}


sub javascript_tag {
  my $self = shift;
  my $code = '';

  foreach my $file (@_) {
    $file .= '.js'        unless $file =~ m/\.js$/;
    $file  = "js/${file}" unless $file =~ m|/|;

    $code .= qq|<script type="text/javascript" src="${file}"></script>|;
  }

  return $code;
}

sub tabbed {
  my ($self, $tabs, %params) = _hashify(2, @_);
  my $id       = $params{id} || 'tab_' . _tag_id();

  $params{selected} *= 1;

  die 'L.tabbed needs an arrayred of tabs for first argument'
    unless ref $tabs eq 'ARRAY';

  my (@header, @blocks);
  for my $i (0..$#$tabs) {
    my $tab = $tabs->[$i];

    next if $tab eq '';

    my $tab_id = "__tab_id_$i";
    push @header, $self->li_tag($self->link('#' . $tab_id, $tab->{name}));
    push @blocks, $self->div_tag($tab->{data}, id => $tab_id);
  }

  return '' unless @header;

  my $ul = $self->ul_tag(join('', @header), id => $id);
  return $self->div_tag(join('', $ul, @blocks), class => 'tabwidget');
}

sub tab {
  my ($self, $name, $src, %params) = _hashify(3, @_);

  $params{method} ||= 'process';

  return () if defined $params{if} && !$params{if};

  my $data;
  if ($params{method} eq 'raw') {
    $data = $src;
  } elsif ($params{method} eq 'process') {
    $data = $self->_context->process($src, %{ $params{args} || {} });
  } else {
    die "unknown tag method '$params{method}'";
  }

  return () unless $data;

  return +{ name => $name, data => $data };
}

sub areainput_tag {
  my ($self, $name, $value, %attributes) = _hashify(3, @_);

  my ($rows, $cols);
  my $min  = delete $attributes{min_rows} || 1;

  if (exists $attributes{cols}) {
    $cols = delete $attributes{cols};
    $rows = $::form->numtextrows($value, $cols);
  } else {
    $rows = delete $attributes{rows} || 1;
  }

  return $rows > 1
    ? $self->textarea_tag($name, $value, %attributes, rows => max($rows, $min), ($cols ? (cols => $cols) : ()))
    : $self->input_tag($name, $value, %attributes, ($cols ? (size => $cols) : ()));
}

sub multiselect2side {
  my ($self, $id, %params) = _hashify(2, @_);

  $params{labelsx}        = "\"" . _J($params{labelsx} || $::locale->text('Available')) . "\"";
  $params{labeldx}        = "\"" . _J($params{labeldx} || $::locale->text('Selected'))  . "\"";
  $params{moveOptions}    = 'false';

  my $vars                = join(', ', map { "${_}: " . $params{$_} } keys %params);
  my $code                = <<EOCODE;
<script type="text/javascript">
  \$().ready(function() {
    \$('#${id}').multiselect2side({ ${vars} });
  });
</script>
EOCODE

  return $code;
}

sub sortable_element {
  my ($self, $selector, %params) = _hashify(2, @_);

  my %attributes = ( distance => 5,
                     helper   => <<'JAVASCRIPT' );
    function(event, ui) {
      ui.children().each(function() {
        $(this).width($(this).width());
      });
      return ui;
    }
JAVASCRIPT

  my $stop_event = '';

  if ($params{url} && $params{with}) {
    my $as      = $params{as} || $params{with};
    my $filter  = ".filter(function(idx) { return this.substr(0, " . length($params{with}) . ") == '$params{with}'; })";
    $filter    .= ".map(function(idx, str) { return str.replace('$params{with}_', ''); })";

    my $params_js = $params{params} ? qq| + ($params{params})| : '';

    $stop_event = <<JAVASCRIPT;
        \$.post('$params{url}'${params_js}, { '${as}[]': \$(\$('${selector}').sortable('toArray'))${filter}.toArray() });
JAVASCRIPT
  }

  if (!$params{dont_recolor}) {
    $stop_event .= <<JAVASCRIPT;
        \$('${selector}>*:odd').removeClass('listrow1').removeClass('listrow0').addClass('listrow0');
        \$('${selector}>*:even').removeClass('listrow1').removeClass('listrow0').addClass('listrow1');
JAVASCRIPT
  }

  if ($stop_event) {
    $attributes{stop} = <<JAVASCRIPT;
      function(event, ui) {
        ${stop_event}
        return ui;
      }
JAVASCRIPT
  }

  $params{handle}     = '.dragdrop' unless exists $params{handle};
  $attributes{handle} = "'$params{handle}'" if $params{handle};

  my $attr_str = join(', ', map { "${_}: $attributes{$_}" } keys %attributes);

  my $code = <<JAVASCRIPT;
<script type="text/javascript">
  \$(function() {
    \$( "${selector}" ).sortable({ ${attr_str} })
  });
</script>
JAVASCRIPT

  return $code;
}

sub dump {
  my $self = shift;
  return '<pre>' . Data::Dumper::Dumper(@_) . '</pre>';
}

sub sortable_table_header {
  my ($self, $by, %params) = _hashify(2, @_);

  my $controller          = $self->{CONTEXT}->stash->get('SELF');
  my $sort_spec           = $controller->get_sort_spec;
  my $by_spec             = $sort_spec->{$by};
  my %current_sort_params = $controller->get_current_sort_params;
  my ($image, $new_dir)   = ('', $current_sort_params{dir});
  my $title               = delete($params{title}) || $::locale->text($by_spec->{title});

  if ($current_sort_params{by} eq $by) {
    my $current_dir = $current_sort_params{dir} ? 'up' : 'down';
    $image          = '<img border="0" src="image/' . $current_dir . '.png">';
    $new_dir        = 1 - ($current_sort_params{dir} || 0);
  }

  $params{ $sort_spec->{FORM_PARAMS}->[0] } = $by;
  $params{ $sort_spec->{FORM_PARAMS}->[1] } = ($new_dir ? '1' : '0');

  return '<a href="' . $controller->get_callback(%params) . '">' . _H($title) . $image . '</a>';
}

sub paginate_controls {
  my ($self, %params) = _hashify(1, @_);

  my $controller      = $self->{CONTEXT}->stash->get('SELF');
  my $paginate_spec   = $controller->get_paginate_spec;
  my %paginate_params = $controller->get_current_paginate_params;

  my %template_params = (
    pages             => \%paginate_params,
    url_maker         => sub {
      my %url_params                                    = _hashify(0, @_);
      $url_params{ $paginate_spec->{FORM_PARAMS}->[0] } = delete $url_params{page};
      $url_params{ $paginate_spec->{FORM_PARAMS}->[1] } = delete $url_params{per_page} if exists $url_params{per_page};

      return $controller->get_callback(%url_params);
    },
    %params,
  );

  return SL::Presenter->get->render('common/paginate', %template_params);
}

1;

__END__

=head1 NAME

SL::Templates::Plugin::L -- Layouting / tag generation

=head1 SYNOPSIS

Usage from a template:

  [% USE L %]

  [% L.select_tag('direction', [ [ 'left', 'To the left' ], [ 'right', 'To the right', 1 ] ]) %]

  [% L.select_tag('direction', [ { direction => 'left',  display => 'To the left'  },
                                 { direction => 'right', display => 'To the right' } ],
                               value_key => 'direction', title_key => 'display', default => 'right')) %]

  [% L.select_tag('direction', [ { direction => 'left',  display => 'To the left'  },
                                 { direction => 'right', display => 'To the right', selected => 1 } ],
                               value_key => 'direction', title_key => 'display')) %]

=head1 DESCRIPTION

A module modeled a bit after Rails' ActionView helpers. Several small
functions that create HTML tags from various kinds of data sources.

The C<id> attribute is usually calculated automatically. This can be
overridden by either specifying an C<id> attribute or by setting
C<no_id> to trueish.

=head1 FUNCTIONS

=head2 LOW-LEVEL FUNCTIONS

The following items are just forwarded to L<SL::Presenter::Tag>:

=over 2

=item * C<name_to_id $name>

=item * C<stringify_attributes %items>

=item * C<html_tag $tag_name, $content_string, %attributes>

=back

=head2 HIGH-LEVEL FUNCTIONS

The following functions are just forwarded to L<SL::Presenter::Tag>:

=over 2

=item * C<input_tag $name, $value, %attributes>

=item * C<select_tag $name, \@collection, %attributes>

=back

Available high-level functions implemented in this module:

=over 4

=item C<yes_no_tag $name, $value, %attributes>

Creates a HTML 'select' tag with the two entries C<yes> and C<no> by
calling L<select_tag>. C<$value> determines
which entry is selected. The C<%attributes> are passed through to
L<select_tag>.

=item C<hidden_tag $name, $value, %attributes>

Creates a HTML 'input type=hidden' tag named C<$name> with the value
C<$value> and with arbitrary HTML attributes from C<%attributes>. The
tag's C<id> defaults to C<name_to_id($name)>.

=item C<submit_tag $name, $value, %attributes>

Creates a HTML 'input type=submit class=submit' tag named C<$name> with the
value C<$value> and with arbitrary HTML attributes from C<%attributes>. The
tag's C<id> defaults to C<name_to_id($name)>.

If C<$attributes{confirm}> is set then a JavaScript popup dialog will
be added via the C<onclick> handler asking the question given with
C<$attributes{confirm}>. The request is only submitted if the user
clicks the dialog's ok/yes button.

=item C<ajax_submit_tag $url, $form_selector, $text, %attributes>

Creates a HTML 'input type="button"' tag with a very specific onclick
handler that submits the form given by the jQuery selector
C<$form_selector> to the URL C<$url> (the actual JavaScript function
called for that is C<kivi.submit_ajax_form()> in
C<js/client_js.js>). The button's label will be C<$text>.

=item C<button_tag $onclick, $text, %attributes>

Creates a HTML 'input type="button"' tag with an onclick handler
C<$onclick> and a value of C<$text>. The button does not have a name
nor an ID by default.

If C<$attributes{confirm}> is set then a JavaScript popup dialog will
be prepended to the C<$onclick> handler asking the question given with
C<$attributes{confirm}>. The request is only submitted if the user
clicks the dialog's "ok/yes" button.

=item C<textarea_tag $name, $value, %attributes>

Creates a HTML 'textarea' tag named C<$name> with the content
C<$value> and with arbitrary HTML attributes from C<%attributes>. The
tag's C<id> defaults to C<name_to_id($name)>.

=item C<checkbox_tag $name, %attributes>

Creates a HTML 'input type=checkbox' tag named C<$name> with arbitrary
HTML attributes from C<%attributes>. The tag's C<id> defaults to
C<name_to_id($name)>. The tag's C<value> defaults to C<1>.

If C<%attributes> contains a key C<label> then a HTML 'label' tag is
created with said C<label>. No attribute named C<label> is created in
that case.

If C<%attributes> contains a key C<checkall> then the value is taken as a
JQuery selector and clicking this checkbox will also toggle all checkboxes
matching the selector.

=item C<date_tag $name, $value, %attributes>

Creates a date input field, with an attached javascript that will open a
calendar on click.

=item C<radio_button_tag $name, %attributes>

Creates a HTML 'input type=radio' tag named C<$name> with arbitrary
HTML attributes from C<%attributes>. The tag's C<value> defaults to
C<1>. The tag's C<id> defaults to C<name_to_id($name . "_" . $value)>.

If C<%attributes> contains a key C<label> then a HTML 'label' tag is
created with said C<label>. No attribute named C<label> is created in
that case.

=item C<javascript_tag $file1, $file2, $file3...>

Creates a HTML 'E<lt>script type="text/javascript" src="..."E<gt>'
tag for each file name parameter passed. Each file name will be
postfixed with '.js' if it isn't already and prefixed with 'js/' if it
doesn't contain a slash.

=item C<stylesheet_tag $file1, $file2, $file3...>

Creates a HTML 'E<lt>link rel="text/stylesheet" href="..."E<gt>' tag
for each file name parameter passed. Each file name will be postfixed
with '.css' if it isn't already and prefixed with 'css/' if it doesn't
contain a slash.

=item C<tabbed \@tab, %attributes>

Will create a tabbed area. The tabs should be created with the helper function
C<tab>. Example:

  [% L.tabbed([
    L.tab(LxERP.t8('Basic Data'),       'part/_main_tab.html'),
    L.tab(LxERP.t8('Custom Variables'), 'part/_cvar_tab.html', if => SELF.display_cvar_tab),
  ]) %]

=item C<areainput_tag $name, $content, %PARAMS>

Creates a generic input tag or textarea tag, depending on content size. The
amount of desired rows must be either given with the C<rows> parameter or can
be computed from the value and the C<cols> paramter, Accepted parameters
include C<min_rows> for rendering a minimum of rows if a textarea is displayed.

You can force input by setting rows to 1, and you can force textarea by setting
rows to anything >1.

=item C<multiselect2side $id, %params>

Creates a JavaScript snippet calling the jQuery function
C<multiselect2side> on the select control with the ID C<$id>. The
select itself is not created. C<%params> can contain the following
entries:

=over 2

=item C<labelsx>

The label of the list of available options. Defaults to the
translation of 'Available'.

=item C<labeldx>

The label of the list of selected options. Defaults to the
translation of 'Selected'.

=back

=item C<sortable_element $selector, %params>

Makes the children of the DOM element C<$selector> (a jQuery selector)
sortable with the I<jQuery UI Selectable> library. The children can be
dragged & dropped around. After dropping an element an URL can be
postet to with the element IDs of the sorted children.

If this is used then the JavaScript file C<js/jquery-ui.js> must be
included manually as well as it isn't loaded via C<$::form-gt;header>.

C<%params> can contain the following entries:

=over 2

=item C<url>

The URL to POST an AJAX request to after a dragged element has been
dropped. The AJAX request's return value is ignored. If given then
C<$params{with}> must be given as well.

=item C<with>

A string that is interpreted as the prefix of the children's ID. Upon
POSTing the result each child whose ID starts with C<$params{with}> is
considered. The prefix and the following "_" is removed from the
ID. The remaining parts of the IDs of those children are posted as a
single array parameter. The array parameter's name is either
C<$params{as}> or, missing that, C<$params{with}>.

=item C<as>

Sets the POST parameter name for AJAX request after dropping an
element (see C<$params{with}>).

=item C<handle>

An optional jQuery selector specifying which part of the child element
is dragable. If the parameter is not given then it defaults to
C<.dragdrop> matching DOM elements with the class C<dragdrop>.  If the
parameter is set and empty then the whole child element is dragable,
and clicks through to underlying elements like inputs or links might
not work.

=item C<dont_recolor>

If trueish then the children will not be recolored. The default is to
recolor the children by setting the class C<listrow0> on odd and
C<listrow1> on even entries.

=item C<params>

An optional JavaScript string that is evaluated before sending the
POST request. The result must be a string that is appended to the URL.

=back

Example:

  <script type="text/javascript" src="js/jquery-ui.js"></script>

  <table id="thing_list">
    <thead>
      <tr><td>This</td><td>That</td></tr>
    </thead>
    <tbody>
      <tr id="thingy_2"><td>stuff</td><td>more stuff</td></tr>
      <tr id="thingy_15"><td>stuff</td><td>more stuff</td></tr>
      <tr id="thingy_6"><td>stuff</td><td>more stuff</td></tr>
    </tbody>
  <table>

  [% L.sortable_element('#thing_list tbody',
                        url          => 'controller.pl?action=SystemThings/reorder',
                        with         => 'thingy',
                        as           => 'thing_ids',
                        recolor_rows => 1) %]

After dropping e.g. the third element at the top of the list a POST
request would be made to the C<reorder> action of the C<SystemThings>
controller with a single parameter called C<thing_ids> -- an array
containing the values C<[ 6, 2, 15 ]>.

=item C<dump REF>

Dumps the Argument using L<Data::Dumper> into a E<lt>preE<gt> block.

=item C<sortable_table_header $by, %params>

Create a link and image suitable for placement in a table
header. C<$by> must be an index set up by the controller with
L<SL::Controller::Helper::make_sorted>.

The optional parameter C<$params{title}> can override the column title
displayed to the user. Otherwise the column title from the
controller's sort spec is used.

The other parameters in C<%params> are passed unmodified to the
underlying call to L<SL::Controller::Base::url_for>.

See the documentation of L<SL::Controller::Helper::Sorted> for an
overview and further usage instructions.

=item C<paginate_controls>

Create a set of links used to paginate a list view.

See the documentation of L<SL::Controller::Helper::Paginated> for an
overview and further usage instructions.

=back

=head2 CONVERSION FUNCTIONS

=over 4

=item C<tab, description, target, %PARAMS>

Creates a tab for C<tabbed>. The description will be used as displayed name.
The target should be a block or template that can be processed. C<tab> supports
a C<method> parameter, which can override the process method to apply target.
C<method => 'raw'> will just include the given text as is. I was too lazy to
implement C<include> properly.

Also an C<if> attribute is supported, so that tabs can be suppressed based on
some occasion. In this case the supplied block won't even get processed, and
the resulting tab will get ignored by C<tabbed>:

  L.tab('Awesome tab wih much info', '_much_info.html', if => SELF.wants_all)

=item C<truncate $text, [%params]>

See L<SL::Presenter::Text/truncate>.

=item C<simple_format $text>

See L<SL::Presenter::Text/simple_format>.

=back

=head1 MODULE AUTHORS

Moritz Bunkus E<lt>m.bunkus@linet-services.deE<gt>

L<http://linet-services.de>
