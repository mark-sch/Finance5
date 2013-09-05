#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
# Copyright (C) 2001
#
#  Author: Dieter Simader
#   Email: dsimader@sql-ledger.org
#     Web: http://www.sql-ledger.org
#
#  Contributors:
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#======================================================================
#
# backend code for customers and vendors
#
# CHANGE LOG:
#   DS. 2000-07-04  Created
#
#======================================================================

package CT;

use Data::Dumper;

use SL::Common;
use SL::CVar;
use SL::DBUtils;
use SL::DB::Default;
use SL::FU;
use SL::Notes;
use SL::TransNumber;

use strict;

sub get_tuple {
  $main::lxdebug->enter_sub();

  my ( $self, $myconfig, $form ) = @_;

  my $cv = $form->{db} eq "customer" ? "customer" : "vendor";

  my $dbh   = $form->dbconnect($myconfig);
  my $query =
    qq|SELECT ct.*, b.id AS business, cp.* | .
    qq|FROM $cv ct | .
    qq|LEFT JOIN business b ON (ct.business_id = b.id) | .
    qq|LEFT JOIN contacts cp ON (ct.id = cp.cp_cv_id) | .
    qq|WHERE (ct.id = ?) | .
    qq|ORDER BY cp.cp_id LIMIT 1|;
  my $sth = prepare_execute_query($form, $dbh, $query, $form->{id});

  my $ref = $sth->fetchrow_hashref("NAME_lc");

  map { $form->{$_} = $ref->{$_} } keys %$ref;
  $sth->finish;

  #get name of currency instead of id:
  $query = qq|SELECT name AS curr FROM currencies WHERE id=?|;
  ($form->{curr}) = selectrow_query($form, $dbh, $query, conv_i($form->{currency_id}));

  if ( $form->{salesman_id} ) {
    my $query =
      qq|SELECT ct.name AS salesman | .
      qq|FROM $cv ct | .
      qq|WHERE ct.id = ?|;
    ($form->{salesman}) =
      selectrow_query($form, $dbh, $query, $form->{salesman_id});
  }

  my ($employee_id) = selectrow_query($form, $dbh, qq|SELECT id FROM employee WHERE login = ?|, $form->{login});
  $query =
    qq|SELECT n.*, n.itime::DATE AS created_on,
         e.name AS created_by_name, e.login AS created_by_login
       FROM notes n
       LEFT JOIN employee e ON (n.created_by = e.id)
       WHERE (n.trans_id = ?) AND (n.trans_module = 'ct')|;
  $form->{NOTES} = selectall_hashref_query($form, $dbh, $query, conv_i($form->{id}));

  $query =
    qq|SELECT fu.follow_up_date, fu.done AS follow_up_done, e.name AS created_for_name, e.name AS created_for_login
       FROM follow_ups fu
       LEFT JOIN employee e ON (fu.created_for_user = e.id)
       WHERE (fu.note_id = ?)
         AND NOT COALESCE(fu.done, FALSE)
         AND (   (fu.created_by = ?)
              OR (fu.created_by IN (SELECT DISTINCT what FROM follow_up_access WHERE who = ?)))|;
  $sth = prepare_query($form, $dbh, $query);

  foreach my $note (@{ $form->{NOTES} }) {
    do_statement($form, $sth, $query, conv_i($note->{id}), conv_i($note->{created_by}), conv_i($employee_id));
    $ref = $sth->fetchrow_hashref();

    map { $note->{$_} = $ref->{$_} } keys %{ $ref } if ($ref);
  }

  $sth->finish();

  if ($form->{edit_note_id}) {
    $query =
      qq|SELECT n.id AS NOTE_id, n.subject AS NOTE_subject, n.body AS NOTE_body,
           fu.id AS FU_id, fu.follow_up_date AS FU_date, fu.done AS FU_done, fu.created_for_user AS FU_created_for_user
         FROM notes n
         LEFT JOIN follow_ups fu ON ((n.id = fu.note_id) AND NOT COALESCE(fu.done, FALSE))
         WHERE n.id = ?|;
    $ref = selectfirst_hashref_query($form, $dbh, $query, conv_i($form->{edit_note_id}));

    if ($ref) {
      foreach my $key (keys %{ $ref }) {
        my $new_key       =  $key;
        $new_key          =~ s/^([^_]+)/\U$1\E/;
        $form->{$new_key} =  $ref->{$key};
      }
    }
  }

  # check if it is orphaned
  my $arap      = ( $form->{db} eq 'customer' ) ? "ar" : "ap";
  my $num_args  = 2;
  my $makemodel = '';
  if ($form->{db} eq 'vendor') {
    $makemodel = qq| UNION SELECT 1 FROM makemodel mm WHERE mm.make = ?|;
    $num_args++;
  }

  $query =
    qq|SELECT a.id | .
    qq|FROM $arap a | .
    qq|JOIN $cv ct ON (a.${cv}_id = ct.id) | .
    qq|WHERE ct.id = ? | .
    qq|UNION | .
    qq|SELECT a.id | .
    qq|FROM oe a | .
    qq|JOIN $cv ct ON (a.${cv}_id = ct.id) | .
    qq|WHERE ct.id = ?|
    . $makemodel;
  my ($dummy) = selectrow_query($form, $dbh, $query, (conv_i($form->{id})) x $num_args);

  $form->{status} = "orphaned" unless ($dummy);

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub populate_drop_down_boxes {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $provided_dbh) = @_;
  my $query;

  my $dbh = $provided_dbh ? $provided_dbh : $form->dbconnect($myconfig);

  # get business types
  $query = qq|SELECT id, description FROM business ORDER BY id|;
  $form->{all_business} = selectall_hashref_query($form, $dbh, $query);

  # get shipto address
  $query =
    qq|SELECT shipto_id, shiptoname, shiptodepartment_1, shiptostreet, shiptocity
       FROM shipto
       WHERE (trans_id = ?) AND (module = 'CT')|;
  $form->{SHIPTO} = selectall_hashref_query($form, $dbh, $query, $form->{id});

  # get contacts
  $query  = qq|SELECT cp_id, cp_name, cp_givenname FROM contacts WHERE cp_cv_id = ? ORDER BY cp_name|;
  $form->{CONTACTS} = selectall_hashref_query($form, $dbh, $query, $form->{id});

  # get languages
  $query = qq|SELECT id, description FROM language ORDER BY id|;
  $form->{languages} = selectall_hashref_query($form, $dbh, $query);

  # get payment terms
  $query = qq|SELECT id, description FROM payment_terms ORDER BY sortkey|;
  $form->{payment_terms} = selectall_hashref_query($form, $dbh, $query);

  $dbh->disconnect() unless ($provided_dbh);

  $main::lxdebug->leave_sub();
}

sub query_titles_and_greetings {
  $main::lxdebug->enter_sub();

  my ( $self, $myconfig, $form ) = @_;
  my ( %tmp,  $ref, $query );

  my $dbh = $form->dbconnect($myconfig);

  $query =
    qq|SELECT DISTINCT(greeting) | .
    qq|FROM customer | .
    qq|WHERE greeting ~ '[a-zA-Z]' | .
    qq|UNION | .
    qq|SELECT DISTINCT(greeting) | .
    qq|FROM vendor | .
    qq|WHERE greeting ~ '[a-zA-Z]' | .
    qq|ORDER BY greeting|;

  map({ $tmp{$_} = 1; } selectall_array_query($form, $dbh, $query));
  $form->{COMPANY_GREETINGS} = [ sort(keys(%tmp)) ];

  $query =
    qq|SELECT DISTINCT(cp_title) | .
    qq|FROM contacts | .
    qq|WHERE cp_title ~ '[a-zA-Z]'|;
  $form->{TITLES} = [ selectall_array_query($form, $dbh, $query) ];

  $query =
    qq|SELECT DISTINCT(cp_abteilung) | .
    qq|FROM contacts | .
    qq|WHERE cp_abteilung ~ '[a-zA-Z]'|;
  $form->{DEPARTMENT} = [ selectall_array_query($form, $dbh, $query) ];

  $dbh->disconnect();
  $main::lxdebug->leave_sub();
}

sub save_customer {
  $main::lxdebug->enter_sub();

  my ( $self, $myconfig, $form ) = @_;

  # set pricegroup to default
  $form->{klass} = 0 unless ($form->{klass});

  # connect to database
  my $dbh = $form->get_standard_dbh;

  map( {
    $form->{"cp_${_}"} = $form->{"selected_cp_${_}"}
    if ( $form->{"selected_cp_${_}"} );
       } qw(title greeting abteilung) );
  $form->{"greeting"} = $form->{"selected_company_greeting"}
  if ( $form->{"selected_company_greeting"} );

  # assign value discount, terms, creditlimit
  $form->{discount} = $form->parse_amount( $myconfig, $form->{discount} );
  $form->{discount} /= 100;
  $form->{creditlimit} = $form->parse_amount( $myconfig, $form->{creditlimit} );

  my ( $query, $sth, $f_id );

  if ( $form->{id} ) {
    $query = qq|SELECT id FROM customer WHERE customernumber = ?|;
    ($f_id) = selectrow_query($form, $dbh, $query, $form->{customernumber});

    if (($f_id ne $form->{id}) && ($f_id ne "")) {
      $main::lxdebug->leave_sub();
      return 3;
    }

  } else {
    my $customernumber      = SL::TransNumber->new(type        => 'customer',
                                                   dbh         => $dbh,
                                                   number      => $form->{customernumber},
                                                   business_id => $form->{business},
                                                   save        => 1);
    $form->{customernumber} = $customernumber->create_unique unless $customernumber->is_unique;

    $query = qq|SELECT nextval('id')|;
    ($form->{id}) = selectrow_query($form, $dbh, $query);

    $query = qq|INSERT INTO customer (id, name, currency_id) VALUES (?, '', (SELECT currency_id FROM defaults))|;
    do_query($form, $dbh, $query, $form->{id});
  }

  $query = qq|UPDATE customer SET | .
    qq|customernumber = ?, | .
    qq|name = ?, | .
    qq|greeting = ?, | .
    qq|department_1 = ?, | .
    qq|department_2 = ?, | .
    qq|street = ?, | .
    qq|zipcode = ?, | .
    qq|city = ?, | .
    qq|country = ?, | .
    qq|homepage = ?, | .
    qq|contact = ?, | .
    qq|phone = ?, | .
    qq|fax = ?, | .
    qq|email = ?, | .
    qq|cc = ?, | .
    qq|bcc = ?, | .
    qq|notes = ?, | .
    qq|discount = ?, | .
    qq|creditlimit = ?, | .
    qq|terms = ?, | .
    qq|business_id = ?, | .
    qq|taxnumber = ?, | .
    qq|language = ?, | .
    qq|account_number = ?, | .
    qq|bank_code = ?, | .
    qq|bank = ?, | .
    qq|iban = ?, | .
    qq|bic = ?, | .
    qq|obsolete = ?, | .
    qq|direct_debit = ?, | .
    qq|ustid = ?, | .
    qq|username = ?, | .
    qq|salesman_id = ?, | .
    qq|language_id = ?, | .
    qq|payment_id = ?, | .
    qq|taxzone_id = ?, | .
    qq|user_password = ?, | .
    qq|c_vendor_id = ?, | .
    qq|klass = ?, | .
    qq|currency_id = (SELECT id FROM currencies WHERE name = ?), | .
    qq|taxincluded_checked = ? | .
    qq|WHERE id = ?|;
  my @values = (
    $form->{customernumber},
    $form->{name},
    $form->{greeting},
    $form->{department_1},
    $form->{department_2},
    $form->{street},
    $form->{zipcode},
    $form->{city},
    $form->{country},
    $form->{homepage},
    $form->{contact},
    $form->{phone},
    $form->{fax},
    $form->{email},
    $form->{cc},
    $form->{bcc},
    $form->{notes},
    $form->{discount},
    $form->{creditlimit},
    conv_i($form->{terms}),
    conv_i($form->{business}),
    $form->{taxnumber},
    $form->{language},
    $form->{account_number},
    $form->{bank_code},
    $form->{bank},
    $form->{iban},
    $form->{bic},
    $form->{obsolete} ? 't' : 'f',
    $form->{direct_debit} ? 't' : 'f',
    $form->{ustid},
    $form->{username},
    conv_i($form->{salesman_id}),
    conv_i($form->{language_id}),
    conv_i($form->{payment_id}),
    conv_i($form->{taxzone_id}, 0),
    $form->{user_password},
    $form->{c_vendor_id},
    conv_i($form->{klass}),
    $form->{currency},
    $form->{taxincluded_checked} ne '' ? $form->{taxincluded_checked} : undef,
    $form->{id}
    );
  do_query( $form, $dbh, $query, @values );

  $form->{cp_id} = $self->_save_contact($form, $dbh);

  # add shipto
  $form->add_shipto( $dbh, $form->{id}, "CT" );

  $self->_save_note('dbh' => $dbh);
  $self->_delete_selected_notes('dbh' => $dbh);

  CVar->save_custom_variables('dbh'       => $dbh,
                              'module'    => 'CT',
                              'trans_id'  => $form->{id},
                              'variables' => $form,
                              'always_valid' => 1);
  if ($form->{cp_id}) {
    CVar->save_custom_variables('dbh'       => $dbh,
                                'module'    => 'Contacts',
                                'trans_id'  => $form->{cp_id},
                                'variables' => $form,
                                'name_prefix'  => 'cp',
                                'always_valid' => 1);
  }

  my $rc = $dbh->commit();

  $main::lxdebug->leave_sub();
  return $rc;
}

sub save_vendor {
  $main::lxdebug->enter_sub();

  my ( $self, $myconfig, $form ) = @_;

  $form->{taxzone_id} *= 1;
  # connect to database
  my $dbh = $form->get_standard_dbh;

  map( {
    $form->{"cp_${_}"} = $form->{"selected_cp_${_}"}
    if ( $form->{"selected_cp_${_}"} );
       } qw(title greeting abteilung) );
  $form->{"greeting"} = $form->{"selected_company_greeting"}
  if ( $form->{"selected_company_greeting"} );

  $form->{discount} = $form->parse_amount( $myconfig, $form->{discount} );
  $form->{discount} /= 100;
  $form->{creditlimit} = $form->parse_amount( $myconfig, $form->{creditlimit} );

  my $query;

  if (!$form->{id}) {
    $query = qq|SELECT nextval('id')|;
    ($form->{id}) = selectrow_query($form, $dbh, $query);

    $query = qq|INSERT INTO vendor (id, name, currency_id) VALUES (?, '', (SELECT currency_id FROM defaults))|;
    do_query($form, $dbh, $query, $form->{id});

    my $vendornumber      = SL::TransNumber->new(type   => 'vendor',
                                                 dbh    => $dbh,
                                                 number => $form->{vendornumber},
                                                 save   => 1);
    $form->{vendornumber} = $vendornumber->create_unique unless $vendornumber->is_unique;
  }

  $query =
    qq|UPDATE vendor SET | .
    qq|  vendornumber = ?, | .
    qq|  name = ?, | .
    qq|  greeting = ?, | .
    qq|  department_1 = ?, | .
    qq|  department_2 = ?, | .
    qq|  street = ?, | .
    qq|  zipcode = ?, | .
    qq|  city = ?, | .
    qq|  country = ?, | .
    qq|  homepage = ?, | .
    qq|  contact = ?, | .
    qq|  phone = ?, | .
    qq|  fax = ?, | .
    qq|  email = ?, | .
    qq|  cc = ?, | .
    qq|  bcc = ?, | .
    qq|  notes = ?, | .
    qq|  terms = ?, | .
    qq|  discount = ?, | .
    qq|  creditlimit = ?, | .
    qq|  business_id = ?, | .
    qq|  taxnumber = ?, | .
    qq|  language = ?, | .
    qq|  account_number = ?, | .
    qq|  bank_code = ?, | .
    qq|  bank = ?, | .
    qq|  iban = ?, | .
    qq|  bic = ?, | .
    qq|  obsolete = ?, | .
    qq|  direct_debit = ?, | .
    qq|  ustid = ?, | .
    qq|  payment_id = ?, | .
    qq|  taxzone_id = ?, | .
    qq|  language_id = ?, | .
    qq|  username = ?, | .
    qq|  user_password = ?, | .
    qq|  v_customer_id = ?, | .
    qq|  currency_id = (SELECT id FROM currencies WHERE name = ?) | .
    qq|WHERE id = ?|;
  my @values = (
    $form->{vendornumber},
    $form->{name},
    $form->{greeting},
    $form->{department_1},
    $form->{department_2},
    $form->{street},
    $form->{zipcode},
    $form->{city},
    $form->{country},
    $form->{homepage},
    $form->{contact},
    $form->{phone},
    $form->{fax},
    $form->{email},
    $form->{cc},
    $form->{bcc},
    $form->{notes},
    conv_i($form->{terms}),
    $form->{discount},
    $form->{creditlimit},
    conv_i($form->{business}),
    $form->{taxnumber},
    $form->{language},
    $form->{account_number},
    $form->{bank_code},
    $form->{bank},
    $form->{iban},
    $form->{bic},
    $form->{obsolete} ? 't' : 'f',
    $form->{direct_debit} ? 't' : 'f',
    $form->{ustid},
    conv_i($form->{payment_id}),
    conv_i($form->{taxzone_id}, 0),
    conv_i( $form->{language_id}),
    $form->{username},
    $form->{user_password},
    $form->{v_customer_id},
    $form->{currency},
    $form->{id}
    );
  do_query($form, $dbh, $query, @values);

  $form->{cp_id} = $self->_save_contact($form, $dbh);

  # add shipto
  $form->add_shipto( $dbh, $form->{id}, "CT" );

  $self->_save_note('dbh' => $dbh);
  $self->_delete_selected_notes('dbh' => $dbh);

  CVar->save_custom_variables('dbh'       => $dbh,
                              'module'    => 'CT',
                              'trans_id'  => $form->{id},
                              'variables' => $form,
                              'always_valid' => 1);
  if ($form->{cp_id}) {
    CVar->save_custom_variables('dbh'       => $dbh,
                                'module'    => 'Contacts',
                                'trans_id'  => $form->{cp_id},
                                'variables' => $form,
                                'name_prefix'  => 'cp',
                                'always_valid' => 1);
  }

  my $rc = $dbh->commit();

  $main::lxdebug->leave_sub();
  return $rc;
}

sub _save_contact {
  my ($self, $form, $dbh) = @_;

  return undef unless $form->{cp_id} || $form->{cp_name} || $form->{cp_givenname};

  my @columns = qw(cp_title cp_givenname cp_name cp_email cp_phone1 cp_phone2 cp_abteilung cp_fax
                   cp_mobile1 cp_mobile2 cp_satphone cp_satfax cp_project cp_privatphone cp_privatemail cp_birthday cp_gender
                   cp_street cp_zipcode cp_city cp_position);
  my @values  = map(
    {
      if ( $_ eq 'cp_gender' ) {
        $form->{$_} eq 'f' ? 'f' : 'm';
      } elsif ( $_ eq 'cp_birthday' && $form->{cp_birthday} eq '' ) {
        undef;
      } else {
        $form->{$_};
      }
    }
    @columns
  );

  my ($query, $cp_id);
  if ($form->{cp_id}) {
    $query = qq|UPDATE contacts SET | . join(', ', map { "${_} = ?" } @columns) . qq| WHERE cp_id = ?|;
    push @values, $form->{cp_id};
    $cp_id = $form->{cp_id};

  } else {
    ($cp_id) = selectrow_query($form, $dbh, qq|SELECT nextval('id')|);

    $query = qq|INSERT INTO contacts (| . join(', ', @columns, 'cp_cv_id', 'cp_id') . qq|) VALUES (| . join(', ', ('?') x (2 + scalar @columns)) . qq|)|;
    push @values, $form->{id}, $cp_id;
  }

  do_query($form, $dbh, $query, @values);

  return $cp_id;
}

sub delete {
  $main::lxdebug->enter_sub();

  my ( $self, $myconfig, $form ) = @_;
  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  # delete vendor
  my $cv = $form->{db} eq "customer" ? "customer" : "vendor";
  my $query = qq|DELETE FROM $cv WHERE id = ?|;
  do_query($form, $dbh, $query, $form->{id});

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub search {
  $main::lxdebug->enter_sub();

  my ( $self, $myconfig, $form ) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $cv = $form->{db} eq "customer" ? "customer" : "vendor";
  my $join_records = $form->{l_invnumber} || $form->{l_ordnumber} || $form->{l_quonumber};

  my $where = "1 = 1";
  my @values;

  my %allowed_sort_columns = (
      "id"                 => "ct.id",
      "customernumber"     => "ct.customernumber",
      "vendornumber"       => "ct.vendornumber",
      "name"               => "ct.name",
      "contact"            => "ct.contact",
      "phone"              => "ct.phone",
      "fax"                => "ct.fax",
      "email"              => "ct.email",
      "street"             => "ct.street",
      "taxnumber"          => "ct.taxnumber",
      "business"           => "ct.business",
      "invnumber"          => "ct.invnumber",
      "ordnumber"          => "ct.ordnumber",
      "quonumber"          => "ct.quonumber",
      "zipcode"            => "ct.zipcode",
      "city"               => "ct.city",
      "country"            => "ct.country",
      "discount"           => "ct.discount",
      "salesman"           => "e.name"
    );

  $form->{sort} ||= "name";
  my $sortorder;
  if ( $join_records ) {
    # in UNION case order by hash key, e.g. salesman
    # the UNION created an implicit select around the result
    $sortorder = $allowed_sort_columns{$form->{sort}} ? $form->{sort} : "name";
  } else {
    # in not UNION case order by hash value, e.g. e.name
    $sortorder = $allowed_sort_columns{$form->{sort}} ?  $allowed_sort_columns{$form->{sort}} : "ct.name";
  }
  my $sortdir   = !defined $form->{sortdir} ? 'ASC' : $form->{sortdir} ? 'ASC' : 'DESC';

  if ($sortorder !~ /(business|id|discount)/ && !$join_records) {
    $sortorder  = "lower($sortorder) ${sortdir}";
  } else {
    $sortorder .= " ${sortdir}";
  }

  if ($form->{"${cv}number"}) {
    $where .= " AND ct.${cv}number ILIKE ?";
    push(@values, '%' . $form->{"${cv}number"} . '%');
  }

  foreach my $key (qw(name contact email)) {
    if ($form->{$key}) {
      $where .= " AND ct.$key ILIKE ?";
      push(@values, '%' . $form->{$key} . '%');
    }
  }

  if ($form->{cp_name}) {
    $where .= " AND ct.id IN (SELECT cp_cv_id FROM contacts WHERE lower(cp_name) LIKE lower(?))";
    push @values, '%' . $form->{cp_name} . '%';
  }

  if ($form->{addr_city}) {
    $where .= " AND ((lower(ct.city) LIKE lower(?))
                     OR
                     (ct.id IN (
                        SELECT sc.trans_id
                        FROM shipto sc
                        WHERE (sc.module = 'CT')
                          AND (lower(sc.shiptocity) LIKE lower(?))
                      ))
                     )";
    push @values, ('%' . $form->{addr_city} . '%') x 2;
  }

  if ($form->{addr_country}) {
    $where .= " AND ((lower(ct.country) LIKE lower(?))
                     OR
                     (ct.id IN (
                        SELECT so.trans_id
                        FROM shipto so
                        WHERE (so.module = 'CT')
                          AND (lower(so.shiptocountry) LIKE lower(?))
                      ))
                     )";
    push @values, ('%' . $form->{addr_country} . '%') x 2;
  }

  if ( $form->{status} eq 'orphaned' ) {
    $where .=
      qq| AND ct.id NOT IN | .
      qq|   (SELECT o.${cv}_id FROM oe o, $cv cv WHERE cv.id = o.${cv}_id)|;
    if ($cv eq 'customer') {
      $where .=
        qq| AND ct.id NOT IN | .
        qq| (SELECT a.customer_id FROM ar a, customer cv | .
        qq|  WHERE cv.id = a.customer_id)|;
    }
    if ($cv eq 'vendor') {
      $where .=
        qq| AND ct.id NOT IN | .
        qq| (SELECT a.vendor_id FROM ap a, vendor cv | .
        qq|  WHERE cv.id = a.vendor_id)|;
    }
    $form->{l_invnumber} = $form->{l_ordnumber} = $form->{l_quonumber} = "";
  }

  if ($form->{obsolete} eq "Y") {
    $where .= qq| AND ct.obsolete|;
  } elsif ($form->{obsolete} eq "N") {
    $where .= qq| AND NOT ct.obsolete|;
  }

  if ($form->{business_id}) {
    $where .= qq| AND (ct.business_id = ?)|;
    push(@values, conv_i($form->{business_id}));
  }

  # Nur Kunden finden, bei denen ich selber der Verkäufer bin
  # Gilt nicht für Lieferanten
  if ($cv eq 'customer' &&   !$main::auth->assert('customer_vendor_all_edit', 1)) {
    $where .= qq| AND ct.salesman_id = (select em.id from employee em where em.login = ?)|;
    push(@values, $form->{login});
  }

  my ($cvar_where, @cvar_values) = CVar->build_filter_query('module'         => 'CT',
                                                            'trans_id_field' => 'ct.id',
                                                            'filter'         => $form);

  if ($cvar_where) {
    $where .= qq| AND ($cvar_where)|;
    push @values, @cvar_values;
  }

  if ($form->{addr_street}) {
    $where .= qq| AND (ct.street ILIKE ?)|;
    push @values, '%' . $form->{addr_street} . '%';
  }

  if ($form->{addr_zipcode}) {
    $where .= qq| AND (ct.zipcode ILIKE ?)|;
    push @values, $form->{addr_zipcode} . '%';
  }

  my $query =
    qq|SELECT ct.*, b.description AS business, e.name as salesman | .
    (qq|, NULL AS invnumber, NULL AS ordnumber, NULL AS quonumber, NULL AS invid, NULL AS module, NULL AS formtype, NULL AS closed | x!! $join_records) .
    qq|FROM $cv ct | .
    qq|LEFT JOIN business b ON (ct.business_id = b.id) | .
    qq|LEFT JOIN employee e ON (ct.salesman_id = e.id) | .
    qq|WHERE $where|;

  my @saved_values = @values;
  # redo for invoices, orders and quotations
  if ($join_records) {
    my $union = "UNION";

    if ($form->{l_invnumber}) {
      my $ar = $cv eq 'customer' ? 'ar' : 'ap';
      my $module = $ar eq 'ar' ? 'is' : 'ir';
      push(@values, @saved_values);
      $query .=
        qq| UNION | .
        qq|SELECT ct.*, b.description AS business, e.name as salesman, | .
        qq|  a.invnumber, a.ordnumber, a.quonumber, a.id AS invid, | .
        qq|  '$module' AS module, 'invoice' AS formtype, | .
        qq|  (a.amount = a.paid) AS closed | .
        qq|FROM $cv ct | .
        qq|JOIN $ar a ON (a.${cv}_id = ct.id) | .
        qq|LEFT JOIN business b ON (ct.business_id = b.id) | .
        qq|LEFT JOIN employee e ON (ct.salesman_id = e.id) | .
        qq|WHERE $where AND (a.invoice = '1')|;
    }

    if ( $form->{l_ordnumber} ) {
      push(@values, @saved_values);
      $query .=
        qq| UNION | .
        qq|SELECT ct.*, b.description AS business, e.name as salesman, | .
        qq|  ' ' AS invnumber, o.ordnumber, o.quonumber, o.id AS invid, | .
        qq|  'oe' AS module, 'order' AS formtype, o.closed | .
        qq|FROM $cv ct | .
        qq|JOIN oe o ON (o.${cv}_id = ct.id) | .
        qq|LEFT JOIN business b ON (ct.business_id = b.id) | .
        qq|LEFT JOIN employee e ON (ct.salesman_id = e.id) | .
        qq|WHERE $where AND (o.quotation = '0')|;
    }

    if ( $form->{l_quonumber} ) {
      push(@values, @saved_values);
      $query .=
        qq| UNION | .
        qq|SELECT ct.*, b.description AS business, e.name as salesman, | .
        qq|  ' ' AS invnumber, o.ordnumber, o.quonumber, o.id AS invid, | .
        qq|  'oe' AS module, 'quotation' AS formtype, o.closed | .
        qq|FROM $cv ct | .
        qq|JOIN oe o ON (o.${cv}_id = ct.id) | .
        qq|LEFT JOIN business b ON (ct.business_id = b.id) | .
        qq|LEFT JOIN employee e ON (ct.salesman_id = e.id) | .
        qq|WHERE $where AND (o.quotation = '1')|;
    }
  }

  $query .= qq| ORDER BY $sortorder|;

  $form->{CT} = selectall_hashref_query($form, $dbh, $query, @values);

  $main::lxdebug->leave_sub();
}

sub get_contact {
  $main::lxdebug->enter_sub();

  my ( $self, $myconfig, $form ) = @_;

  die 'Missing argument: cp_id' unless $::form->{cp_id};

  my $dbh   = $form->dbconnect($myconfig);
  my $query =
    qq|SELECT * FROM contacts c | .
    qq|WHERE cp_id = ? ORDER BY cp_id limit 1|;
  my $sth = prepare_execute_query($form, $dbh, $query, $form->{cp_id});
  my $ref = $sth->fetchrow_hashref("NAME_lc");

  map { $form->{$_} = $ref->{$_} } keys %$ref;

  $query = qq|SELECT COUNT(cp_id) AS used FROM (
    SELECT cp_id FROM oe UNION
    SELECT cp_id FROM ar UNION
    SELECT cp_id FROM ap UNION
    SELECT cp_id FROM delivery_orders
  ) AS cpid WHERE cp_id = ? OR ? = 0|;
  ($form->{cp_used}) = selectfirst_array_query($form, $dbh, $query, ($form->{cp_id})x2);

  $sth->finish;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub get_shipto {
  $main::lxdebug->enter_sub();

  my ( $self, $myconfig, $form ) = @_;
  my $dbh   = $form->dbconnect($myconfig);
  my $query = qq|SELECT * FROM shipto WHERE shipto_id = ?|;
  my $sth = prepare_execute_query($form, $dbh, $query, $form->{shipto_id});

  my $ref = $sth->fetchrow_hashref("NAME_lc");

  map { $form->{$_} = $ref->{$_} } keys %$ref;

  $query = qq|SELECT COUNT(shipto_id) AS used FROM (
    SELECT shipto_id FROM oe UNION
    SELECT shipto_id FROM ar UNION
    SELECT shipto_id FROM delivery_orders
  ) AS stid WHERE shipto_id = ? OR ? = 0|;
  ($form->{shiptoused}) = selectfirst_array_query($form, $dbh, $query, ($form->{shipto_id})x2);

  $sth->finish;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub get_delivery {
  $main::lxdebug->enter_sub();

  my ( $self, $myconfig, $form ) = @_;
  my $dbh = $form->dbconnect($myconfig);

  my $arap = $form->{db} eq "vendor" ? "ap" : "ar";
  my $db = $form->{db} eq "customer" ? "customer" : "vendor";
  my $qty_sign = $form->{db} eq 'vendor' ? ' * -1 AS qty' : '';

  my $where = " WHERE 1=1 ";
  my @values;

  if ($form->{shipto_id} && ($arap eq "ar")) {
    $where .= "AND ${arap}.shipto_id = ?";
    push(@values, $form->{shipto_id});
  } else {
    $where .= "AND ${arap}.${db}_id = ?";
    push(@values, $form->{id});
  }

  if ($form->{from}) {
    $where .= "AND ${arap}.transdate >= ?";
    push(@values, conv_date($form->{from}));
  }
  if ($form->{to}) {
    $where .= "AND ${arap}.transdate <= ?";
    push(@values, conv_date($form->{to}));
  }
  my $query =
    qq|SELECT s.shiptoname, i.qty $qty_sign, | .
    qq|  ${arap}.id, ${arap}.transdate, ${arap}.invnumber, ${arap}.ordnumber, | .
    qq|  i.description, i.unit, i.sellprice, | .
    qq|  oe.id AS oe_id, invoice | .
    qq|FROM $arap | .
    qq|LEFT JOIN shipto s ON | .
    ($arap eq "ar"
     ? qq|(ar.shipto_id = s.shipto_id) |
     : qq|(ap.id = s.trans_id) |) .
    qq|LEFT JOIN invoice i ON (${arap}.id = i.trans_id) | .
    qq|LEFT join parts p ON (p.id = i.parts_id) | .
    qq|LEFT JOIN oe ON (oe.ordnumber = ${arap}.ordnumber AND NOT ${arap}.ordnumber = '') | .
    $where .
    qq|ORDER BY ${arap}.transdate DESC LIMIT 15|;

  $form->{DELIVERY} = selectall_hashref_query($form, $dbh, $query, @values);

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub _save_note {
  $main::lxdebug->enter_sub();

  my $self   = shift;
  my %params = @_;

  my $form   = $main::form;

  Common::check_params(\%params, 'dbh');

  if (!$form->{NOTE_subject}) {
    $main::lxdebug->leave_sub();
    return;
  }

  my $dbh = $params{dbh};

  my %follow_up;
  my %note = (
    'id'           => $form->{NOTE_id},
    'subject'      => $form->{NOTE_subject},
    'body'         => $form->{NOTE_body},
    'trans_id'     => $form->{id},
    'trans_module' => 'ct',
  );

  $note{id} = Notes->save(%note);

  if ($form->{FU_date}) {
    %follow_up = (
      'id'               => $form->{FU_id},
      'note_id'          => $note{id},
      'follow_up_date'   => $form->{FU_date},
      'created_for_user' => $form->{FU_created_for_user},
      'done'             => $form->{FU_done} ? 1 : 0,
      'subject'          => $form->{NOTE_subject},
      'body'             => $form->{NOTE_body},
      'LINKS'            => [
        {
          'trans_id'     => $form->{id},
          'trans_type'   => $form->{db} eq 'customer' ? 'customer' : 'vendor',
          'trans_info'   => $form->{name},
        },
      ],
    );

    $follow_up{id} = FU->save(%follow_up);

  } elsif ($form->{FU_id}) {
    do_query($form, $dbh, qq|DELETE FROM follow_up_links WHERE follow_up_id = ?|, conv_i($form->{FU_id}));
    do_query($form, $dbh, qq|DELETE FROM follow_ups      WHERE id = ?|,           conv_i($form->{FU_id}));
  }

  delete @{$form}{grep { /^NOTE_|^FU_/ } keys %{ $form }};

  $main::lxdebug->leave_sub();
}

sub _delete_selected_notes {
  $main::lxdebug->enter_sub();

  my $self   = shift;
  my %params = @_;

  Common::check_params(\%params, 'dbh');

  my $form = $main::form;
  my $dbh  = $params{dbh};

  foreach my $i (1 .. $form->{NOTES_rowcount}) {
    next unless ($form->{"NOTE_delete_$i"} && $form->{"NOTE_id_$i"});

    Notes->delete('dbh' => $params{dbh},
                  'id'  => $form->{"NOTE_id_$i"});
  }

  $main::lxdebug->leave_sub();
}

# TODO: remove in 2.7.0 stable
sub delete_shipto {
  $main::lxdebug->enter_sub();

  my $self      = shift;
  my $shipto_id = shift;

  my $form      = $main::form;
  my %myconfig  = %main::myconfig;
  my $dbh       = $form->get_standard_dbh(\%myconfig);

  do_query($form, $dbh, qq|UPDATE shipto SET trans_id = NULL WHERE shipto_id = ?|, $shipto_id);

  $dbh->commit();

  $main::lxdebug->leave_sub();
}

# TODO: remove in 2.7.0 stable
sub delete_contact {
  $main::lxdebug->enter_sub();

  my $self      = shift;
  my $cp_id     = shift;

  my $form      = $main::form;
  my %myconfig  = %main::myconfig;
  my $dbh       = $form->get_standard_dbh(\%myconfig);

  do_query($form, $dbh, qq|UPDATE contacts SET cp_cv_id = NULL WHERE cp_id = ?|, $cp_id);

  $dbh->commit();

  $main::lxdebug->leave_sub();
}

sub get_bank_info {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  Common::check_params(\%params, qw(vc id));

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  my $dbh      = $params{dbh} || $form->get_standard_dbh($myconfig);

  my $table        = $params{vc} eq 'customer' ? 'customer' : 'vendor';
  my @ids          = ref $params{id} eq 'ARRAY' ? @{ $params{id} } : ($params{id});
  my $placeholders = join ", ", ('?') x scalar @ids;
  my $query        = qq|SELECT id, name, account_number, bank, bank_code, iban, bic
                        FROM ${table}
                        WHERE id IN (${placeholders})|;

  my $result       = selectall_hashref_query($form, $dbh, $query, map { conv_i($_) } @ids);

  if (ref $params{id} eq 'ARRAY') {
    $result = { map { $_->{id} => $_ } @{ $result } };
  } else {
    $result = $result->[0] || { 'id' => $params{id} };
  }

  $main::lxdebug->leave_sub();

  return $result;
}

sub parse_excel_file {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;
  my $locale = $main::locale;

  my $defaults = SL::DB::Default->get;
  $form->error($::locale->text('No print templates have been created for this client yet. Please do so in the client configuration.')) if !$defaults->templates;
  $form->{templates} = $defaults->templates;

  $form->{formname}   = 'sales_quotation';
  $form->{type}   = 'sales_quotation';
  $form->{format} = 'excel';
  $form->{media}  = 'screen';
  $form->{quonumber} = 1;


  # $form->{"notes"} will be overridden by the customer's/vendor's "notes" field. So save it here.
  $form->{ $form->{"formname"} . "notes" } = $form->{"notes"};

  my $inv                  = "quo";
  my $due                  = "req";
  $form->{"${inv}date"} = $form->{transdate};
  $form->{label}        = $locale->text('Quotation');
  my $numberfld            = "sqnumber";
  my $order                = 1;

  # assign number
  $form->{what_done} = $form->{formname};

  map({ delete($form->{$_}); } grep(/^cp_/, keys(%{ $form })));

  my $output_dateformat = $myconfig->{"dateformat"};
  my $output_numberformat = $myconfig->{"numberformat"};
  my $output_longdates = 1;

  # map login user variables
  map { $form->{"login_$_"} = $myconfig->{$_} } ("name", "email", "fax", "tel", "company");

  # format item dates
  for my $field (qw(transdate_oe deliverydate_oe)) {
    map {
      $form->{$field}[$_] = $locale->date($myconfig, $form->{$field}[$_], 1);
    } 0 .. $#{ $form->{$field} };
  }

  if ($form->{shipto_id}) {
    $form->get_shipto($myconfig);
  }

  $form->{notes} =~ s/^\s+//g;

  delete $form->{printer_command};

  $form->get_employee_info($myconfig);

  my ($cvar_date_fields, $cvar_number_fields) = CVar->get_field_format_list('module' => 'CT', 'prefix' => 'vc_');

  if (scalar @{ $cvar_date_fields }) {
    format_dates($output_dateformat, $output_longdates, @{ $cvar_date_fields });
  }

  while (my ($precision, $field_list) = each %{ $cvar_number_fields }) {
    reformat_numbers($output_numberformat, $precision, @{ $field_list });
  }

  $form->{excel} = 1;
  my $extension            = 'xls';

  $form->{IN}         = "$form->{formname}.${extension}";

  delete $form->{OUT};

  $form->parse_template($myconfig);

  $main::lxdebug->leave_sub();
}

sub search_contacts {
  $::lxdebug->enter_sub;

  my $self      = shift;
  my %params    = @_;

  my $dbh       = $params{dbh} || $::form->get_standard_dbh;

  my %sortspecs = (
    'cp_name'   => 'cp_name, cp_givenname',
    'vcname'    => 'vcname, cp_name, cp_givenname',
    'vcnumber'  => 'vcnumber, cp_name, cp_givenname',
    );

  my %sortcols  = map { $_ => 1 } qw(cp_name cp_givenname cp_phone1 cp_phone2 cp_mobile1 cp_email cp_street cp_zipcode cp_city cp_position vcname vcnumber);

  my $order_by  = $sortcols{$::form->{sort}} ? $::form->{sort} : 'cp_name';
  $::form->{sort} = $order_by;
  $order_by     = $sortspecs{$order_by} if ($sortspecs{$order_by});

  my $sortdir   = $::form->{sortdir} ? 'ASC' : 'DESC';
  $order_by     =~ s/,/ ${sortdir},/g;
  $order_by    .= " $sortdir";

  my @where_tokens = ();
  my @values;

  if ($params{search_term}) {
    my @tokens;
    push @tokens,
      'cp.cp_name      ILIKE ?',
      'cp.cp_givenname ILIKE ?',
      'cp.cp_email     ILIKE ?';
    push @values, ('%' . $params{search_term} . '%') x 3;

    if (($params{search_term} =~ m/\d/) && ($params{search_term} !~ m/[^\d \(\)+\-]/)) {
      my $number =  $params{search_term};
      $number    =~ s/[^\d]//g;
      $number    =  join '[ /\(\)+\-]*', split(m//, $number);

      push @tokens, map { "($_ ~ '$number')" } qw(cp_phone1 cp_phone2 cp_mobile1 cp_mobile2);
    }

    push @where_tokens, map { "($_)" } join ' OR ', @tokens;
  }

  my ($cvar_where, @cvar_values) = CVar->build_filter_query('module'         => 'Contacts',
                                                            'trans_id_field' => 'cp.cp_id',
                                                            'filter'         => $params{filter});

  if ($cvar_where) {
    push @where_tokens, $cvar_where;
    push @values, @cvar_values;
  }

  if (my $filter = $params{filter}) {
    for (qw(name title givenname email project abteilung)) {
      next unless $filter->{"cp_$_"};
      add_token(\@where_tokens, \@values, col =>  "cp.cp_$_", val => $filter->{"cp_$_"}, method => 'ILIKE', esc => 'substr');
    }

    push @where_tokens, 'cp.cp_cv_id IS NOT NULL' if $filter->{status} eq 'active';
    push @where_tokens, 'cp.cp_cv_id IS NULL'     if $filter->{status} eq 'orphaned';
  }

  my $where = @where_tokens ? 'WHERE ' . join ' AND ', @where_tokens : '';

  my $query     = qq|SELECT cp.*,
                       COALESCE(c.id,             v.id)           AS vcid,
                       COALESCE(c.name,           v.name)         AS vcname,
                       COALESCE(c.customernumber, v.vendornumber) AS vcnumber,
                       CASE WHEN c.name IS NULL THEN 'vendor' ELSE 'customer' END AS db
                     FROM contacts cp
                     LEFT JOIN customer c ON (cp.cp_cv_id = c.id)
                     LEFT JOIN vendor v   ON (cp.cp_cv_id = v.id)
                     $where
                     ORDER BY $order_by|;

  my $contacts  = selectall_hashref_query($::form, $dbh, $query, @values);

  $::lxdebug->leave_sub;

  return @{ $contacts };
}


1;
