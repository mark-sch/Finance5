package SL::Presenter::Record;

use strict;

use parent qw(Exporter);

use Exporter qw(import);
our @EXPORT = qw(grouped_record_list empty_record_list record_list);

use SL::Util;

use Carp;
use List::Util qw(first);

sub _arrayify {
  my ($array) = @_;
  return []     if !defined $array;
  return $array if ref $array;
  return [ $array ];
}

sub grouped_record_list {
  my ($self, $list, %params) = @_;

  %params    = map { exists $params{$_} ? ($_ => $params{$_}) : () } qw(edit_record_links with_columns object_id object_model);

  my %groups = _sort_grouped_lists(_group_records($list));
  my $output = '';

  $output .= _sales_quotation_list(        $self, $groups{sales_quotations},         %params) if $groups{sales_quotations};
  $output .= _sales_order_list(            $self, $groups{sales_orders},             %params) if $groups{sales_orders};
  $output .= _sales_delivery_order_list(   $self, $groups{sales_delivery_orders},    %params) if $groups{sales_delivery_orders};
  $output .= _sales_invoice_list(          $self, $groups{sales_invoices},           %params) if $groups{sales_invoices};
  $output .= _ar_transaction_list(         $self, $groups{ar_transactions},          %params) if $groups{ar_transactions};

  $output .= _request_quotation_list(      $self, $groups{purchase_quotations},      %params) if $groups{purchase_quotations};
  $output .= _purchase_order_list(         $self, $groups{purchase_orders},          %params) if $groups{purchase_orders};
  $output .= _purchase_delivery_order_list($self, $groups{purchase_delivery_orders}, %params) if $groups{purchase_delivery_orders};
  $output .= _purchase_invoice_list(       $self, $groups{purchase_invoices},        %params) if $groups{purchase_invoices};
  $output .= _ar_transaction_list(         $self, $groups{ar_transactions},          %params) if $groups{ar_transactions};

  $output .= _sepa_collection_list(        $self, $groups{sepa_collections},         %params) if $groups{sepa_collections};
  $output .= _sepa_transfer_list(          $self, $groups{sepa_transfers},           %params) if $groups{sepa_transfers};

  $output  = $self->render('presenter/record/grouped_record_list', %params, output => $output);

  return $output;
}

sub empty_record_list {
  my ($self, %params) = @_;
  return $self->grouped_record_list([], %params);
}

sub record_list {
  my ($self, $list, %params) = @_;

  my @columns;

  if (ref($params{columns}) eq 'ARRAY') {
    @columns = map {
      if (ref($_) eq 'ARRAY') {
        { title => $_->[0], data => $_->[1], link => $_->[2] }
      } else {
        $_;
      }
    } @{ delete $params{columns} };

  } else {
    croak "Wrong type for 'columns' argument: not an array reference";
  }

  my %with_columns = map { ($_ => 1) } @{ _arrayify($params{with_columns}) };
  if ($with_columns{record_link_direction}) {
    push @columns, {
      title => $::locale->text('Link direction'),
      data  => sub { $_[0]->{_record_link_direction} eq 'from' ? $::locale->text('Row was source for current record') : $::locale->text('Row was created from current record') },
    };
  }

  my %column_meta   = map { $_->name => $_ } @{ $list->[0]->meta->columns       };
  my %relationships = map { $_->name => $_ } @{ $list->[0]->meta->relationships };

  my $call = sub {
    my ($obj, $method, @args) = @_;
    $obj->$method(@args);
  };

  my @data;
  foreach my $obj (@{ $list }) {
    my @row;

    foreach my $spec (@columns) {
      my %cell;

      my $method       =  $spec->{column} || $spec->{data};
      my $meta         =  $column_meta{ $spec->{data} };
      my $type         =  ref $meta;
      my $relationship =  $relationships{ $spec->{data} };
      my $rel_type     =  !$relationship ? '' : $relationship->class;
      $rel_type        =~ s/^SL::DB:://;
      $rel_type        =  SL::Util::snakify($rel_type);

      if (ref($spec->{data}) eq 'CODE') {
        $cell{value} = $spec->{data}->($obj);

      } else {
        $cell{value} = $rel_type && $self->can($rel_type)                                       ? $self->$rel_type($obj->$method, display => 'table-cell')
                     : $type eq 'Rose::DB::Object::Metadata::Column::Date'                      ? $call->($obj, $method . '_as_date')
                     : $type =~ m/^Rose::DB::Object::Metadata::Column::(?:Float|Numeric|Real)$/ ? $::form->format_amount(\%::myconfig, $call->($obj, $method), 2)
                     : $type eq 'Rose::DB::Object::Metadata::Column::Boolean'                   ? $call->($obj, $method . '_as_bool_yn')
                     : $type =~ m/^Rose::DB::Object::Metadata::Column::(?:Integer|Serial)$/     ? $spec->{data} * 1
                     :                                                                            $call->($obj, $method);
      }

      $cell{alignment} = 'right' if $type =~ m/int|serial|float|real|numeric/;

      push @row, \%cell;
    }

    push @data, { columns => \@row, record_link => $obj->{_record_link} };
  }

  my @header =
    map +{ value     => $columns[$_]->{title},
           alignment => $data[0]->{columns}->[$_]->{alignment},
         }, (0..scalar(@columns) - 1);

  return $self->render(
    'presenter/record/record_list',
    %params,
    TABLE_HEADER => \@header,
    TABLE_ROWS   => \@data,
  );
}

#
# private methods
#

sub _group_records {
  my ($list) = @_;

  my %matchers = (
    sales_quotations         => sub { (ref($_[0]) eq 'SL::DB::Order')           &&  $_[0]->is_type('sales_quotation')   },
    sales_orders             => sub { (ref($_[0]) eq 'SL::DB::Order')           &&  $_[0]->is_type('sales_order')       },
    sales_delivery_orders    => sub { (ref($_[0]) eq 'SL::DB::DeliveryOrder')   &&  $_[0]->is_sales                     },
    sales_invoices           => sub { (ref($_[0]) eq 'SL::DB::Invoice')         &&  $_[0]->invoice                      },
    ar_transactions          => sub { (ref($_[0]) eq 'SL::DB::Invoice')         && !$_[0]->invoice                      },
    purchase_quotations      => sub { (ref($_[0]) eq 'SL::DB::Order')           &&  $_[0]->is_type('request_quotation') },
    purchase_orders          => sub { (ref($_[0]) eq 'SL::DB::Order')           &&  $_[0]->is_type('purchase_order')    },
    purchase_delivery_orders => sub { (ref($_[0]) eq 'SL::DB::DeliveryOrder')   && !$_[0]->is_sales                     },
    purchase_invoices        => sub { (ref($_[0]) eq 'SL::DB::PurchaseInvoice') &&  $_[0]->invoice                      },
    ap_transactions          => sub { (ref($_[0]) eq 'SL::DB::PurchaseInvoice') && !$_[0]->invoice                      },
    sepa_collections         => sub { (ref($_[0]) eq 'SL::DB::SepaExportItem')  &&  $_[0]->ar_id                        },
    sepa_transfers           => sub { (ref($_[0]) eq 'SL::DB::SepaExportItem')  &&  $_[0]->ap_id                        },
  );

  my %groups;

  foreach my $record (@{ $list || [] }) {
    my $type         = (first { $matchers{$_}->($record) } keys %matchers) || 'other';
    $groups{$type} ||= [];
    push @{ $groups{$type} }, $record;
  }

  return %groups;
}

sub _sort_grouped_lists {
  my (%groups) = @_;

  foreach my $group (keys %groups) {
    next unless @{ $groups{$group} };
    if ($groups{$group}->[0]->can('compare_to')) {
      $groups{$group} = [ sort { $a->compare_to($b)    } @{ $groups{$group} } ];
    } else {
      $groups{$group} = [ sort { $a->date <=> $b->date } @{ $groups{$group} } ];
    }
  }

  return %groups;
}

sub _sales_quotation_list {
  my ($self, $list, %params) = @_;

  return $self->record_list(
    $list,
    title   => $::locale->text('Sales Quotations'),
    type    => 'sales_quotation',
    columns => [
      [ $::locale->text('Quotation Date'),          'transdate'                                                                ],
      [ $::locale->text('Quotation Number'),        sub { $self->sales_quotation($_[0], display => 'table-cell') }   ],
      [ $::locale->text('Customer'),                'customer'                                                                 ],
      [ $::locale->text('Net amount'),              'netamount'                                                                ],
      [ $::locale->text('Transaction description'), 'transaction_description'                                                  ],
      [ $::locale->text('Project'),                 'globalproject', ],
      [ $::locale->text('Closed'),                  'closed'                                                                   ],
    ],
    %params,
  );
}

sub _request_quotation_list {
  my ($self, $list, %params) = @_;

  return $self->record_list(
    $list,
    title   => $::locale->text('Request Quotations'),
    type    => 'request_quotation',
    columns => [
      [ $::locale->text('Quotation Date'),          'transdate'                                                                ],
      [ $::locale->text('Quotation Number'),        sub { $self->request_quotation($_[0], display => 'table-cell') }   ],
      [ $::locale->text('Vendor'),                  'vendor'                                                                   ],
      [ $::locale->text('Net amount'),              'netamount'                                                                ],
      [ $::locale->text('Transaction description'), 'transaction_description'                                                  ],
      [ $::locale->text('Project'),                 'globalproject', ],
      [ $::locale->text('Closed'),                  'closed'                                                                   ],
    ],
    %params,
  );
}

sub _sales_order_list {
  my ($self, $list, %params) = @_;

  return $self->record_list(
    $list,
    title   => $::locale->text('Sales Orders'),
    type    => 'sales_order',
    columns => [
      [ $::locale->text('Order Date'),              'transdate'                                                                ],
      [ $::locale->text('Order Number'),            sub { $self->sales_order($_[0], display => 'table-cell') }   ],
      [ $::locale->text('Quotation'),               'quonumber' ],
      [ $::locale->text('Customer'),                'customer'                                                                 ],
      [ $::locale->text('Net amount'),              'netamount'                                                                ],
      [ $::locale->text('Transaction description'), 'transaction_description'                                                  ],
      [ $::locale->text('Project'),                 'globalproject', ],
      [ $::locale->text('Closed'),                  'closed'                                                                   ],
    ],
    %params,
  );
}

sub _purchase_order_list {
  my ($self, $list, %params) = @_;

  return $self->record_list(
    $list,
    title   => $::locale->text('Purchase Orders'),
    type    => 'purchase_order',
    columns => [
      [ $::locale->text('Order Date'),              'transdate'                                                                ],
      [ $::locale->text('Order Number'),            sub { $self->purchase_order($_[0], display => 'table-cell') }   ],
      [ $::locale->text('Request for Quotation'),   'quonumber' ],
      [ $::locale->text('Vendor'),                  'vendor'                                                                 ],
      [ $::locale->text('Net amount'),              'netamount'                                                                ],
      [ $::locale->text('Transaction description'), 'transaction_description'                                                  ],
      [ $::locale->text('Project'),                 'globalproject', ],
      [ $::locale->text('Closed'),                  'closed'                                                                   ],
    ],
    %params,
  );
}

sub _sales_delivery_order_list {
  my ($self, $list, %params) = @_;

  return $self->record_list(
    $list,
    title   => $::locale->text('Sales Delivery Orders'),
    type    => 'sales_delivery_order',
    columns => [
      [ $::locale->text('Delivery Order Date'),     'transdate'                                                                ],
      [ $::locale->text('Delivery Order Number'),   sub { $self->sales_delivery_order($_[0], display => 'table-cell') } ],
      [ $::locale->text('Order Number'),            'ordnumber' ],
      [ $::locale->text('Customer'),                'customer'                                                                 ],
      [ $::locale->text('Transaction description'), 'transaction_description'                                                  ],
      [ $::locale->text('Project'),                 'globalproject', ],
      [ $::locale->text('Delivered'),               'delivered'                                                                ],
      [ $::locale->text('Closed'),                  'closed'                                                                   ],
    ],
    %params,
  );
}

sub _purchase_delivery_order_list {
  my ($self, $list, %params) = @_;

  return $self->record_list(
    $list,
    title   => $::locale->text('Purchase Delivery Orders'),
    type    => 'purchase_delivery_order',
    columns => [
      [ $::locale->text('Delivery Order Date'),     'transdate'                                                                ],
      [ $::locale->text('Delivery Order Number'),   sub { $self->purchase_delivery_order($_[0], display => 'table-cell') } ],
      [ $::locale->text('Order Number'),            'ordnumber' ],
      [ $::locale->text('Vendor'),                  'vendor'                                                                 ],
      [ $::locale->text('Transaction description'), 'transaction_description'                                                  ],
      [ $::locale->text('Project'),                 'globalproject', ],
      [ $::locale->text('Delivered'),               'delivered'                                                                ],
      [ $::locale->text('Closed'),                  'closed'                                                                   ],
    ],
    %params,
  );
}

sub _sales_invoice_list {
  my ($self, $list, %params) = @_;

  return $self->record_list(
    $list,
    title   => $::locale->text('Sales Invoices'),
    type    => 'sales_invoice',
    columns => [
      [ $::locale->text('Invoice Date'),            'transdate'               ],
      [ $::locale->text('Invoice Number'),          sub { $self->sales_invoice($_[0], display => 'table-cell') } ],
      [ $::locale->text('Quotation Number'),        'quonumber' ],
      [ $::locale->text('Order Number'),            'ordnumber' ],
      [ $::locale->text('Customer'),                'customer'                ],
      [ $::locale->text('Net amount'),              'netamount'               ],
      [ $::locale->text('Paid'),                    'paid'                    ],
      [ $::locale->text('Transaction description'), 'transaction_description' ],
    ],
    %params,
  );
}

sub _purchase_invoice_list {
  my ($self, $list, %params) = @_;

  return $self->record_list(
    $list,
    title   => $::locale->text('Purchase Invoices'),
    type    => 'purchase_invoice',
    columns => [
      [ $::locale->text('Invoice Date'),                 'transdate'               ],
      [ $::locale->text('Invoice Number'),               sub { $self->purchase_invoice($_[0], display => 'table-cell') } ],
      [ $::locale->text('Request for Quotation Number'), 'quonumber' ],
      [ $::locale->text('Order Number'),                 'ordnumber' ],
      [ $::locale->text('Vendor'),                       'vendor'                 ],
      [ $::locale->text('Net amount'),                   'netamount'               ],
      [ $::locale->text('Paid'),                         'paid'                    ],
      [ $::locale->text('Transaction description'),      'transaction_description' ],
    ],
    %params,
  );
}

sub _ar_transaction_list {
  my ($self, $list, %params) = @_;

  return $self->record_list(
    $list,
    title   => $::locale->text('AR Transactions'),
    type    => 'ar_transaction',
    columns => [
      [ $::locale->text('Invoice Date'),            'transdate'               ],
      [ $::locale->text('Invoice Number'),          sub { $self->ar_transaction($_[0], display => 'table-cell') } ],
      [ $::locale->text('Customer'),                'customer'                ],
      [ $::locale->text('Net amount'),              'netamount'               ],
      [ $::locale->text('Paid'),                    'paid'                    ],
      [ $::locale->text('Transaction description'), 'transaction_description' ],
    ],
    %params,
  );
}

sub _ap_transaction_list {
  my ($self, $list, %params) = @_;

  return $self->record_list(
    $list,
    title   => $::locale->text('AP Transactions'),
    type    => 'ap_transaction',
    columns => [
      [ $::locale->text('Invoice Date'),            'transdate'                      ],
      [ $::locale->text('Invoice Number'),          sub { $self->ap_transaction($_[0 ], display => 'table-cell') } ],
      [ $::locale->text('Vendor'),                  'vendor'                         ],
      [ $::locale->text('Net amount'),              'netamount'                      ],
      [ $::locale->text('Paid'),                    'paid'                           ],
      [ $::locale->text('Transaction description'), 'transaction_description'        ],
    ],
    %params,
  );
}

sub _sepa_export_list {
  my ($self, $list, %params) = @_;

  my ($source, $destination) = $params{type} eq 'sepa_transfer' ? qw(our vc)                                 : qw(vc our);
  $params{title}             = $params{type} eq 'sepa_transfer' ? $::locale->text('Bank transfers via SEPA') : $::locale->text('Bank collections via SEPA');
  $params{with_columns}      = [ grep { $_ ne 'record_link_direction' } @{ $params{with_columns} || [] } ];

  delete $params{edit_record_links};

  return $self->record_list(
    $list,
    columns => [
      [ $::locale->text('Export Number'),    'sepa_export',                                  ],
      [ $::locale->text('Execution date'),   'execution_date'                                ],
      [ $::locale->text('Export date'),      sub { $_[0]->sepa_export->itime->to_kivitendo } ],
      [ $::locale->text('Source BIC'),       "${source}_bic"                                 ],
      [ $::locale->text('Source IBAN'),      "${source}_iban"                                ],
      [ $::locale->text('Destination BIC'),  "${destination}_bic"                            ],
      [ $::locale->text('Destination IBAN'), "${destination}_iban"                           ],
      [ $::locale->text('Amount'),           'amount'                                        ],
    ],
    %params,
  );
}

sub _sepa_transfer_list {
  my ($self, $list, %params) = @_;
  _sepa_export_list($self, $list, %params, type => 'sepa_transfer');
}

sub _sepa_collection_list {
  my ($self, $list, %params) = @_;
  _sepa_export_list($self, $list, %params, type => 'sepa_collection');
}

1;

__END__

=pod

=encoding utf8

=head1 NAME

SL::Presenter::Record - Presenter module for lists of
sales/purchase/general ledger record Rose::DB objects

=head1 SYNOPSIS

  # Retrieve a number of documents from somewhere, e.g.
  my $order   = SL::DB::Manager::Order->get_first(where => [ SL::DB::Manager::Order->type_filter('sales_order') ]);
  my $records = $order->linked_records(destination => 'to');

  # Give HTML representation:
  my $html = SL::Presenter->get->grouped_record_list($records);

=head1 OVERVIEW

TODO

=head1 FUNCTIONS

=over 4

=item C<empty_record_list>

Returns a rendered version (actually an instance of
L<SL::Presenter::EscapedText>) of an empty list of records. Is usually
only called by L<grouped_record_list> if its list is empty.

=item C<grouped_record_list $list, %params>

Given a number of Rose::DB objects in the array reference C<$list>
this function first groups them by type. Then it calls L<record_list>
with each non-empty type-specific sub-list and the appropriate
parameters for outputting a list of those records.

Returns a rendered version (actually an instance of
L<SL::Presenter::EscapedText>) of all the lists.

The order in which the records are grouped is:

=over 2

=item * sales quotations

=item * sales orders

=item * sales delivery orders

=item * sales invoices

=item * AR transactions

=item * requests for quotations

=item * purchase orders

=item * purchase delivery orders

=item * purchase invoices

=item * AP transactions

=item * SEPA collections

=item * SEPA transfers

=back

Objects of unknown types are skipped.

Parameters are passed to C<record_list> include C<with_objects> and
C<edit_record_links>.

=item C<record_list $list, %params>

Returns a rendered version (actually an instance of
L<SL::Presenter::EscapedText>) of a list of records. This list
consists of a heading and a tabular representation of the list.

The parameters include:

=over 2

=item C<title>

Mandatory. The title to use in the heading. Must already be
translated.

=item C<columns>

Mandatory. An array reference of column specs to output. Each column
spec can be either an array reference or a hash reference.

If a column spec is an array reference then the first element is the
column's name shown in the table header. It must already be translated.

The second element can be either a string or a code reference. A
string is taken as the name of a function to call on the Rose::DB
object for the current row. Its return value is formatted depending on
the column's type (e.g. dates are output as the user expects them,
floating point numbers are rounded to two decimal places and
right-aligned etc). If it is a code reference then that code is called
with the object as the first argument. Its return value should be an
instance of L<SL::Presenter::EscapedText> and contain the rendered
representation of the content to output.

The third element, if present, can be a link to which the column will
be linked.

If the column spec is a hash reference then the same arguments are
expected. The corresponding hash keys are C<title>, C<data> and
C<link>.

=item C<with_columns>

Can be set by the caller to indicate additional columns to
list. Currently supported:

=over 2

=item C<record_link_destination>

The record link destination. Requires that the records to list have
been retrieved via the L<SL::DB::Helper::LinkedRecords> helper.

=back

=item C<edit_record_links>

If trueish additional controls will be rendered that allow the user to
remove and add record links. Requires that the records to list have
been retrieved via the L<SL::DB::Helper::LinkedRecords> helper.

=back

=back

=head1 BUGS

Nothing here yet.

=head1 AUTHOR

Moritz Bunkus E<lt>m.bunkus@linet-services.deE<gt>

=cut
