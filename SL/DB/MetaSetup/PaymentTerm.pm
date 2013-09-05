# This file has been auto-generated. Do not modify it; it will be overwritten
# by rose_auto_create_model.pl automatically.
package SL::DB::PaymentTerm;

use strict;

use base qw(SL::DB::Object);

__PACKAGE__->meta->table('payment_terms');

__PACKAGE__->meta->columns(
  description      => { type => 'text' },
  description_long => { type => 'text' },
  id               => { type => 'integer', not_null => 1, sequence => 'id' },
  itime            => { type => 'timestamp', default => 'now()' },
  mtime            => { type => 'timestamp' },
  percent_skonto   => { type => 'float', precision => 4 },
  ranking          => { type => 'integer' },
  sortkey          => { type => 'integer', not_null => 1 },
  terms_netto      => { type => 'integer' },
  terms_skonto     => { type => 'integer' },
);

__PACKAGE__->meta->primary_key_columns([ 'id' ]);

__PACKAGE__->meta->allow_inline_column_values(1);

1;
;
