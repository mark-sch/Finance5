#====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
# Copyright (C) 1999-2003
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
# Delivery Order entry module
#======================================================================

package DO;

use List::Util qw(max);
use YAML;

use SL::AM;
use SL::Common;
use SL::CVar;
use SL::DB::DeliveryOrder;
use SL::DB::Status;
use SL::DBUtils;
use SL::RecordLinks;
use SL::IC;

use strict;

sub transactions {
  $main::lxdebug->enter_sub();

  my ($self)   = @_;

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  my (@where, @values, $where);

  my $vc = $form->{vc} eq "customer" ? "customer" : "vendor";

  my $query =
    qq|SELECT dord.id, dord.donumber, dord.ordnumber,
         dord.transdate, dord.reqdate,
         ct.${vc}number, ct.name, dord.${vc}_id, dord.globalproject_id,
         dord.closed, dord.delivered, dord.shippingpoint, dord.shipvia,
         dord.transaction_description,
         pr.projectnumber AS globalprojectnumber,
         dep.description AS department,
         e.name AS employee,
         sm.name AS salesman
       FROM delivery_orders dord
       LEFT JOIN $vc ct ON (dord.${vc}_id = ct.id)
       LEFT JOIN employee e ON (dord.employee_id = e.id)
       LEFT JOIN employee sm ON (dord.salesman_id = sm.id)
       LEFT JOIN project pr ON (dord.globalproject_id = pr.id)
       LEFT JOIN department dep ON (dord.department_id = dep.id)
|;

  push @where, ($form->{type} eq 'sales_delivery_order' ? '' : 'NOT ') . qq|COALESCE(dord.is_sales, FALSE)|;

  if ($form->{department_id}) {
    push @where,  qq|dord.department_id = ?|;
    push @values, conv_i($form->{department_id});
  }

  if ($form->{project_id}) {
    push @where,
      qq|(dord.globalproject_id = ?) OR EXISTS
          (SELECT * FROM delivery_order_items doi
           WHERE (doi.project_id = ?) AND (doi.delivery_order_id = dord.id))|;
    push @values, conv_i($form->{project_id}), conv_i($form->{project_id});
  }

  if ($form->{"${vc}_id"}) {
    push @where,  qq|dord.${vc}_id = ?|;
    push @values, $form->{"${vc}_id"};

  } elsif ($form->{$vc}) {
    push @where,  qq|ct.name ILIKE ?|;
    push @values, '%' . $form->{$vc} . '%';
  }

  foreach my $item (qw(employee_id salesman_id)) {
    next unless ($form->{$item});
    push @where, "dord.$item = ?";
    push @values, conv_i($form->{$item});
  }
  if (!$main::auth->assert('sales_all_edit', 1)) {
    push @where, qq|dord.employee_id = (select id from employee where login= ?)|;
    push @values, $form->{login};
  }

  foreach my $item (qw(donumber ordnumber cusordnumber transaction_description)) {
    next unless ($form->{$item});
    push @where,  qq|dord.$item ILIKE ?|;
    push @values, '%' . $form->{$item} . '%';
  }

  if (($form->{open} || $form->{closed}) &&
      ($form->{open} ne $form->{closed})) {
    push @where, ($form->{open} ? "NOT " : "") . "COALESCE(dord.closed, FALSE)";
  }

  if (($form->{notdelivered} || $form->{delivered}) &&
      ($form->{notdelivered} ne $form->{delivered})) {
    push @where, ($form->{delivered} ? "" : "NOT ") . "COALESCE(dord.delivered, FALSE)";
  }

  if($form->{transdatefrom}) {
    push @where,  qq|dord.transdate >= ?|;
    push @values, conv_date($form->{transdatefrom});
  }

  if($form->{transdateto}) {
    push @where,  qq|dord.transdate <= ?|;
    push @values, conv_date($form->{transdateto});
  }

  if (@where) {
    $query .= " WHERE " . join(" AND ", map { "($_)" } @where);
  }

  my %allowed_sort_columns = (
    "transdate"               => "dord.transdate",
    "reqdate"                 => "dord.reqdate",
    "id"                      => "dord.id",
    "donumber"                => "dord.donumber",
    "ordnumber"               => "dord.ordnumber",
    "name"                    => "ct.name",
    "employee"                => "e.name",
    "salesman"                => "sm.name",
    "shipvia"                 => "dord.shipvia",
    "transaction_description" => "dord.transaction_description",
    "department"              => "lower(dep.description)",
  );

  my $sortdir   = !defined $form->{sortdir} ? 'ASC' : $form->{sortdir} ? 'ASC' : 'DESC';
  my $sortorder = "dord.id";
  if ($form->{sort} && grep($form->{sort}, keys(%allowed_sort_columns))) {
    $sortorder = $allowed_sort_columns{$form->{sort}};
  }

  $query .= qq| ORDER by | . $sortorder . " $sortdir";

  $form->{DO} = selectall_hashref_query($form, $dbh, $query, @values);

  if (scalar @{ $form->{DO} }) {
    $query =
      qq|SELECT id
         FROM oe
         WHERE NOT COALESCE(quotation, FALSE)
           AND (ordnumber = ?)
           AND (COALESCE(${vc}_id, 0) != 0)|;

    my $sth = prepare_query($form, $dbh, $query);

    foreach my $dord (@{ $form->{DO} }) {
      next unless ($dord->{ordnumber});
      do_statement($form, $sth, $query, $dord->{ordnumber});
      ($dord->{oe_id}) = $sth->fetchrow_array();
    }

    $sth->finish();
  }

  $main::lxdebug->leave_sub();
}

sub save {
  $main::lxdebug->enter_sub();

  my ($self)   = @_;

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  # connect to database, turn off autocommit
  my $dbh = $form->get_standard_dbh($myconfig);

  my ($query, @values, $sth, $null);

  my $all_units = AM->retrieve_units($myconfig, $form);
  $form->{all_units} = $all_units;

  my $ic_cvar_configs = CVar->get_configs(module => 'IC',
                                          dbh    => $dbh);

  $form->{donumber}    = $form->update_defaults($myconfig, $form->{type} eq 'sales_delivery_order' ? 'sdonumber' : 'pdonumber', $dbh) unless $form->{donumber};
  $form->{employee_id} = (split /--/, $form->{employee})[1] if !$form->{employee_id};
  $form->get_employee($dbh) unless ($form->{employee_id});

  my $ml = ($form->{type} eq 'sales_delivery_order') ? 1 : -1;

  if ($form->{id}) {

    $query = qq|DELETE FROM delivery_order_items_stock WHERE delivery_order_item_id IN (SELECT id FROM delivery_order_items WHERE delivery_order_id = ?)|;
    do_query($form, $dbh, $query, conv_i($form->{id}));

    $query = qq|DELETE FROM delivery_order_items WHERE delivery_order_id = ?|;
    do_query($form, $dbh, $query, conv_i($form->{id}));

    $query = qq|DELETE FROM shipto WHERE trans_id = ? AND module = 'DO'|;
    do_query($form, $dbh, $query, conv_i($form->{id}));

  } else {

    $query = qq|SELECT nextval('id')|;
    ($form->{id}) = selectrow_query($form, $dbh, $query);

    $query = qq|INSERT INTO delivery_orders (id, donumber, employee_id, currency_id) VALUES (?, '', ?, (SELECT currency_id FROM defaults LIMIT 1))|;
    do_query($form, $dbh, $query, $form->{id}, conv_i($form->{employee_id}));
  }

  my $project_id;
  my $items_reqdate;

  $form->get_lists('price_factors' => 'ALL_PRICE_FACTORS');
  my %price_factors = map { $_->{id} => $_->{factor} } @{ $form->{ALL_PRICE_FACTORS} };
  my $price_factor;

  my %part_id_map = map { $_ => 1 } grep { $_ } map { $form->{"id_$_"} } (1 .. $form->{rowcount});
  my @part_ids    = keys %part_id_map;
  my %part_unit_map;

  if (@part_ids) {
    $query         = qq|SELECT id, unit FROM parts WHERE id IN (| . join(', ', map { '?' } @part_ids) . qq|)|;
    %part_unit_map = selectall_as_map($form, $dbh, $query, 'id', 'unit', @part_ids);
  }

  my $q_item_id = qq|SELECT nextval('delivery_order_items_id')|;
  my $h_item_id = prepare_query($form, $dbh, $q_item_id);

  my $q_item =
    qq|INSERT INTO delivery_order_items (
         id, delivery_order_id, parts_id, description, longdescription, qty, base_qty,
         sellprice, discount, unit, reqdate, project_id, serialnumber,
         ordnumber, transdate, cusordnumber,
         lastcost, price_factor_id, price_factor, marge_price_factor, pricegroup_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
         (SELECT factor FROM price_factors WHERE id = ?), ?, ?)|;
  my $h_item = prepare_query($form, $dbh, $q_item);

  my $q_item_stock =
    qq|INSERT INTO delivery_order_items_stock (delivery_order_item_id, qty, unit, warehouse_id, bin_id, chargenumber, bestbefore)
       VALUES (?, ?, ?, ?, ?, ?, ?)|;
  my $h_item_stock = prepare_query($form, $dbh, $q_item_stock);

  my $in_out       = $form->{type} =~ /^sales/ ? 'out' : 'in';

  for my $i (1 .. $form->{rowcount}) {
    next if (!$form->{"id_$i"});

    $form->{"qty_$i"} = $form->parse_amount($myconfig, $form->{"qty_$i"});

    my $item_unit = $part_unit_map{$form->{"id_$i"}};

    my $basefactor = 1;
    if (defined($all_units->{$item_unit}->{factor}) && (($all_units->{$item_unit}->{factor} * 1) != 0)) {
      $basefactor = $all_units->{$form->{"unit_$i"}}->{factor} / $all_units->{$item_unit}->{factor};
    }
    my $baseqty = $form->{"qty_$i"} * $basefactor;

    # set values to 0 if nothing entered
    $form->{"discount_$i"}  = $form->parse_amount($myconfig, $form->{"discount_$i"});
    $form->{"sellprice_$i"} = $form->parse_amount($myconfig, $form->{"sellprice_$i"});
    $form->{"lastcost_$i"} = $form->parse_amount($myconfig, $form->{"lastcost_$i"});

    $price_factor = $price_factors{ $form->{"price_factor_id_$i"} } || 1;
    my $linetotal    = $form->round_amount($form->{"sellprice_$i"} * $form->{"qty_$i"} / $price_factor, 2);

    $items_reqdate = ($form->{"reqdate_$i"}) ? $form->{"reqdate_$i"} : undef;

    do_statement($form, $h_item_id, $q_item_id);
    my ($item_id) = $h_item_id->fetchrow_array();

    # Get pricegroup_id and save it. Unfortunately the interface
    # also uses ID "0" for signalling that none is selected, but "0"
    # must not be stored in the database. Therefore we cannot simply
    # use conv_i().
    my $pricegroup_id = $form->{"pricegroup_id_$i"} * 1;
    $pricegroup_id    = undef if !$pricegroup_id;

    # save detail record in delivery_order_items table
    @values = (conv_i($item_id), conv_i($form->{id}), conv_i($form->{"id_$i"}),
               $form->{"description_$i"}, $form->{"longdescription_$i"},
               $form->{"qty_$i"}, $baseqty,
               $form->{"sellprice_$i"}, $form->{"discount_$i"} / 100,
               $form->{"unit_$i"}, conv_date($items_reqdate), conv_i($form->{"project_id_$i"}),
               $form->{"serialnumber_$i"},
               $form->{"ordnumber_$i"}, conv_date($form->{"transdate_$i"}),
               $form->{"cusordnumber_$i"},
               $form->{"lastcost_$i"},
               conv_i($form->{"price_factor_id_$i"}), conv_i($form->{"price_factor_id_$i"}),
               conv_i($form->{"marge_price_factor_$i"}),
               $pricegroup_id);
    do_statement($form, $h_item, $q_item, @values);

    my $stock_info = DO->unpack_stock_information('packed' => $form->{"stock_${in_out}_$i"});

    foreach my $sinfo (@{ $stock_info }) {
      @values = ($item_id, $sinfo->{qty}, $sinfo->{unit}, conv_i($sinfo->{warehouse_id}),
                 conv_i($sinfo->{bin_id}), $sinfo->{chargenumber}, conv_date($sinfo->{bestbefore}));
      do_statement($form, $h_item_stock, $q_item_stock, @values);
    }

    CVar->save_custom_variables(module       => 'IC',
                                sub_module   => 'delivery_order_items',
                                trans_id     => $item_id,
                                configs      => $ic_cvar_configs,
                                variables    => $form,
                                name_prefix  => 'ic_',
                                name_postfix => "_$i",
                                dbh          => $dbh);
  }

  $h_item_id->finish();
  $h_item->finish();
  $h_item_stock->finish();


  # reqdate is last items reqdate (?: old behaviour) if not already set
  $form->{reqdate} ||= $items_reqdate;
  # save DO record
  $query =
    qq|UPDATE delivery_orders SET
         donumber = ?, ordnumber = ?, cusordnumber = ?, transdate = ?, vendor_id = ?,
         customer_id = ?, reqdate = ?,
         shippingpoint = ?, shipvia = ?, notes = ?, intnotes = ?, closed = ?,
         delivered = ?, department_id = ?, language_id = ?, shipto_id = ?,
         globalproject_id = ?, employee_id = ?, salesman_id = ?, cp_id = ?, transaction_description = ?,
         is_sales = ?, taxzone_id = ?, taxincluded = ?, terms = ?, currency_id = (SELECT id FROM currencies WHERE name = ?)
       WHERE id = ?|;

  @values = ($form->{donumber}, $form->{ordnumber},
             $form->{cusordnumber}, conv_date($form->{transdate}),
             conv_i($form->{vendor_id}), conv_i($form->{customer_id}),
             conv_date($form->{reqdate}), $form->{shippingpoint}, $form->{shipvia},
             $form->{notes}, $form->{intnotes},
             $form->{closed} ? 't' : 'f', $form->{delivered} ? "t" : "f",
             conv_i($form->{department_id}), conv_i($form->{language_id}), conv_i($form->{shipto_id}),
             conv_i($form->{globalproject_id}), conv_i($form->{employee_id}),
             conv_i($form->{salesman_id}), conv_i($form->{cp_id}),
             $form->{transaction_description},
             $form->{type} =~ /^sales/ ? 't' : 'f',
             conv_i($form->{taxzone_id}), $form->{taxincluded} ? 't' : 'f', conv_i($form->{terms}), $form->{currency},
             conv_i($form->{id}));
  do_query($form, $dbh, $query, @values);

  # add shipto
  $form->{name} = $form->{ $form->{vc} };
  $form->{name} =~ s/--$form->{"$form->{vc}_id"}//;

  if (!$form->{shipto_id}) {
    $form->add_shipto($dbh, $form->{id}, "DO");
  }

  # save printed, emailed, queued
  $form->save_status($dbh);

  # Link this delivery order to the quotations it was created from.
  RecordLinks->create_links('dbh'        => $dbh,
                            'mode'       => 'ids',
                            'from_table' => 'oe',
                            'from_ids'   => $form->{convert_from_oe_ids},
                            'to_table'   => 'delivery_orders',
                            'to_id'      => $form->{id},
    );
  delete $form->{convert_from_oe_ids};

  $self->mark_orders_if_delivered('do_id' => $form->{id},
                                  'type'  => $form->{type} eq 'sales_delivery_order' ? 'sales' : 'purchase',
                                  'dbh'   => $dbh,);

  my $rc = $dbh->commit();

  $form->{saved_donumber} = $form->{donumber};

  Common::webdav_folder($form);

  $main::lxdebug->leave_sub();

  return $rc;
}

sub mark_orders_if_delivered {
  $main::lxdebug->enter_sub();

  my $self   = shift;
  my %params = @_;

  Common::check_params(\%params, qw(do_id type));

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  my $dbh      = $params{dbh} || $form->get_standard_dbh($myconfig);

  my @links    = RecordLinks->get_links('dbh'        => $dbh,
                                        'from_table' => 'oe',
                                        'to_table'   => 'delivery_orders',
                                        'to_id'      => $params{do_id});

  my $oe_id  = @links ? $links[0]->{from_id} : undef;

  return $main::lxdebug->leave_sub() if (!$oe_id);

  my $all_units = AM->retrieve_all_units();

  my $query     = qq|SELECT oi.parts_id, oi.qty, oi.unit, p.unit AS partunit
                     FROM orderitems oi
                     LEFT JOIN parts p ON (oi.parts_id = p.id)
                     WHERE (oi.trans_id = ?)|;
  my $sth       = prepare_execute_query($form, $dbh, $query, $oe_id);

  my %shipped   = $self->get_shipped_qty('type'  => $params{type},
                                         'oe_id' => $oe_id,);
  my %ordered   = ();

  while (my $ref = $sth->fetchrow_hashref()) {
    $ref->{baseqty} = $ref->{qty} * $all_units->{$ref->{unit}}->{factor} / $all_units->{$ref->{partunit}}->{factor};

    if ($ordered{$ref->{parts_id}}) {
      $ordered{$ref->{parts_id}}->{baseqty} += $ref->{baseqty};
    } else {
      $ordered{$ref->{parts_id}}             = $ref;
    }
  }

  $sth->finish();

  map { $_->{baseqty} = $_->{qty} * $all_units->{$_->{unit}}->{factor} / $all_units->{$_->{partunit}}->{factor} } values %shipped;

  my $delivered = 1;
  foreach my $part (values %ordered) {
    if (!$shipped{$part->{parts_id}} || ($shipped{$part->{parts_id}}->{baseqty} < $part->{baseqty})) {
      $delivered = 0;
      last;
    }
  }

  if ($delivered) {
    $query = qq|UPDATE oe
                SET delivered = TRUE
                WHERE id = ?|;
    do_query($form, $dbh, $query, $oe_id);
    $dbh->commit() if (!$params{dbh});
  }

  $main::lxdebug->leave_sub();
}

sub close_orders {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  Common::check_params(\%params, qw(ids));

  if (('ARRAY' ne ref $params{ids}) || !scalar @{ $params{ids} }) {
    $main::lxdebug->leave_sub();
    return;
  }

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  my $dbh      = $params{dbh} || $form->get_standard_dbh($myconfig);

  my $query    = qq|UPDATE delivery_orders SET closed = TRUE WHERE id IN (| . join(', ', ('?') x scalar(@{ $params{ids} })) . qq|)|;

  do_query($form, $dbh, $query, map { conv_i($_) } @{ $params{ids} });

  $dbh->commit() unless ($params{dbh});

  $main::lxdebug->leave_sub();
}

sub delete {
  $main::lxdebug->enter_sub();

  my ($self)   = @_;

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;
  my $spool    = $::lx_office_conf{paths}->{spool};

  my $rc = SL::DB::Order->new->db->with_transaction(sub {
    my @spoolfiles = grep { $_ } map { $_->spoolfile } @{ SL::DB::Manager::Status->get_all(where => [ trans_id => $form->{id} ]) };

    SL::DB::DeliveryOrder->new(id => $form->{id})->delete;

    my $spool = $::lx_office_conf{paths}->{spool};
    unlink map { "$spool/$_" } @spoolfiles if $spool;

    1;
  });

  $main::lxdebug->leave_sub();

  return $rc;
}

sub retrieve {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);

  my ($query, $query_add, @values, $sth, $ref);

  my $ic_cvar_configs = CVar->get_configs(module => 'IC',
                                          dbh    => $dbh);

  my $vc   = $params{vc} eq 'customer' ? 'customer' : 'vendor';

  my $mode = !$params{ids} ? 'default' : ref $params{ids} eq 'ARRAY' ? 'multi' : 'single';

  if ($mode eq 'default') {
    $ref = selectfirst_hashref_query($form, $dbh, qq|SELECT current_date AS transdate|);
    map { $form->{$_} = $ref->{$_} } keys %$ref;

    # if reqdate is not set from oe-workflow, set it to transdate (which is current date)
    $form->{reqdate} ||= $form->{transdate};

    # get last name used
    $form->lastname_used($dbh, $myconfig, $vc) unless $form->{"${vc}_id"};

    $main::lxdebug->leave_sub();

    return 1;
  }

  my @do_ids              = map { conv_i($_) } ($mode eq 'multi' ? @{ $params{ids} } : ($params{ids}));
  my $do_ids_placeholders = join(', ', ('?') x scalar(@do_ids));

  # retrieve order for single id
  # NOTE: this query is intended to fetch all information only ONCE.
  # so if any of these infos is important (or even different) for any item,
  # it will be killed out and then has to be fetched from the item scope query further down
  $query =
    qq|SELECT dord.cp_id, dord.donumber, dord.ordnumber, dord.transdate, dord.reqdate,
         dord.shippingpoint, dord.shipvia, dord.notes, dord.intnotes,
         e.name AS employee, dord.employee_id, dord.salesman_id,
         dord.${vc}_id, cv.name AS ${vc},
         dord.closed, dord.reqdate, dord.department_id, dord.cusordnumber,
         d.description AS department, dord.language_id,
         dord.shipto_id,
         dord.globalproject_id, dord.delivered, dord.transaction_description,
         dord.taxzone_id, dord.taxincluded, dord.terms, (SELECT cu.name FROM currencies cu WHERE cu.id=dord.currency_id) AS currency
       FROM delivery_orders dord
       JOIN ${vc} cv ON (dord.${vc}_id = cv.id)
       LEFT JOIN employee e ON (dord.employee_id = e.id)
       LEFT JOIN department d ON (dord.department_id = d.id)
       WHERE dord.id IN ($do_ids_placeholders)|;
  $sth = prepare_execute_query($form, $dbh, $query, @do_ids);

  delete $form->{"${vc}_id"};
  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    if ($form->{"${vc}_id"} && ($ref->{"${vc}_id"} != $form->{"${vc}_id"})) {
      $sth->finish();
      $main::lxdebug->leave_sub();

      return 0;
    }

    map { $form->{$_} = $ref->{$_} } keys %$ref if ($ref);
    $form->{donumber_array} .= $form->{donumber} . ' ';
  }
  $sth->finish();

  $form->{donumber_array} =~ s/\s*$//g;

  $form->{saved_donumber} = $form->{donumber};

  # if not given, fill transdate with current_date
  $form->{transdate} = $form->current_date($myconfig) unless $form->{transdate};

  if ($mode eq 'single') {
    $query = qq|SELECT s.* FROM shipto s WHERE s.trans_id = ? AND s.module = 'DO'|;
    $sth   = prepare_execute_query($form, $dbh, $query, $form->{id});

    $ref   = $sth->fetchrow_hashref("NAME_lc");
    delete $ref->{id};
    map { $form->{$_} = $ref->{$_} } keys %$ref;
    $sth->finish();

    # get printed, emailed and queued
    $query = qq|SELECT s.printed, s.emailed, s.spoolfile, s.formname FROM status s WHERE s.trans_id = ?|;
    $sth   = prepare_execute_query($form, $dbh, $query, conv_i($form->{id}));

    while ($ref = $sth->fetchrow_hashref("NAME_lc")) {
      $form->{printed} .= "$ref->{formname} " if $ref->{printed};
      $form->{emailed} .= "$ref->{formname} " if $ref->{emailed};
      $form->{queued}  .= "$ref->{formname} $ref->{spoolfile} " if $ref->{spoolfile};
    }
    $sth->finish();
    map { $form->{$_} =~ s/ +$//g } qw(printed emailed queued);

  } else {
    delete $form->{id};
  }

  # retrieve individual items
  # this query looks up all information about the items
  # stuff different from the whole will not be overwritten, but saved with a suffix.
  $query =
    qq|SELECT doi.id AS delivery_order_items_id,
         p.partnumber, p.assembly, p.listprice, doi.description, doi.qty,
         doi.sellprice, doi.parts_id AS id, doi.unit, doi.discount, p.notes AS partnotes,
         doi.reqdate, doi.project_id, doi.serialnumber, doi.lastcost,
         doi.ordnumber, doi.transdate, doi.cusordnumber, doi.longdescription,
         doi.price_factor_id, doi.price_factor, doi.marge_price_factor, doi.pricegroup_id,
         pr.projectnumber, dord.transdate AS dord_transdate,
         pg.partsgroup
       FROM delivery_order_items doi
       JOIN parts p ON (doi.parts_id = p.id)
       JOIN delivery_orders dord ON (doi.delivery_order_id = dord.id)
       LEFT JOIN project pr ON (doi.project_id = pr.id)
       LEFT JOIN partsgroup pg ON (p.partsgroup_id = pg.id)
       WHERE doi.delivery_order_id IN ($do_ids_placeholders)
       ORDER BY doi.oid|;

  $form->{form_details} = selectall_hashref_query($form, $dbh, $query, @do_ids);

  # Retrieve custom variables.
  foreach my $doi (@{ $form->{form_details} }) {
    my $cvars = CVar->get_custom_variables(dbh        => $dbh,
                                           module     => 'IC',
                                           sub_module => 'delivery_order_items',
                                           trans_id   => $doi->{delivery_order_items_id},
                                          );
    map { $doi->{"ic_cvar_$_->{name}"} = $_->{value} } @{ $cvars };
  }

  if ($mode eq 'single') {
    my $in_out = $form->{type} =~ /^sales/ ? 'out' : 'in';

    $query =
      qq|SELECT qty, unit, bin_id, warehouse_id, chargenumber, bestbefore
         FROM delivery_order_items_stock
         WHERE delivery_order_item_id = ?|;
    my $sth = prepare_query($form, $dbh, $query);

    foreach my $doi (@{ $form->{form_details} }) {
      do_statement($form, $sth, $query, conv_i($doi->{delivery_order_items_id}));
      my $requests = [];
      while (my $ref = $sth->fetchrow_hashref()) {
        push @{ $requests }, $ref;
      }

      $doi->{"stock_${in_out}"} = YAML::Dump($requests);
    }

    $sth->finish();
  }

  Common::webdav_folder($form);

  $main::lxdebug->leave_sub();

  return 1;
}

sub order_details {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->get_standard_dbh($myconfig);
  my $query;
  my @values = ();
  my $sth;
  my $item;
  my $i;
  my @partsgroup = ();
  my $partsgroup;
  my $position = 0;

  my (@project_ids, %projectnumbers, %projectdescriptions);

  push(@project_ids, $form->{"globalproject_id"}) if ($form->{"globalproject_id"});

  # sort items by partsgroup
  for $i (1 .. $form->{rowcount}) {
    $partsgroup = "";
    if ($form->{"partsgroup_$i"} && $form->{groupitems}) {
      $partsgroup = $form->{"partsgroup_$i"};
    }
    push @partsgroup, [$i, $partsgroup];
    push(@project_ids, $form->{"project_id_$i"}) if ($form->{"project_id_$i"});
  }

  if (@project_ids) {
    $query = "SELECT id, projectnumber, description FROM project WHERE id IN (" .
      join(", ", map("?", @project_ids)) . ")";
    $sth = prepare_execute_query($form, $dbh, $query, @project_ids);
    while (my $ref = $sth->fetchrow_hashref()) {
      $projectnumbers{$ref->{id}} = $ref->{projectnumber};
      $projectdescriptions{$ref->{id}} = $ref->{description};
    }
    $sth->finish();
  }

  $form->{"globalprojectnumber"} =
    $projectnumbers{$form->{"globalproject_id"}};
  $form->{"globalprojectdescription"} =
      $projectdescriptions{$form->{"globalproject_id"}};

  my $q_pg     = qq|SELECT p.partnumber, p.description, p.unit, a.qty, pg.partsgroup
                    FROM assembly a
                    JOIN parts p ON (a.parts_id = p.id)
                    LEFT JOIN partsgroup pg ON (p.partsgroup_id = pg.id)
                    WHERE a.bom = '1'
                      AND a.id = ?|;
  my $h_pg     = prepare_query($form, $dbh, $q_pg);

  my $q_bin_wh = qq|SELECT (SELECT description FROM bin       WHERE id = ?) AS bin,
                           (SELECT description FROM warehouse WHERE id = ?) AS warehouse|;
  my $h_bin_wh = prepare_query($form, $dbh, $q_bin_wh);

  my $in_out   = $form->{type} =~ /^sales/ ? 'out' : 'in';

  my $num_si   = 0;

  my $ic_cvar_configs = CVar->get_configs(module => 'IC');

  $form->{TEMPLATE_ARRAYS} = { };
  IC->prepare_parts_for_printing(myconfig => $myconfig, form => $form);

  my @arrays =
    qw(runningnumber number description longdescription qty unit
       partnotes serialnumber reqdate projectnumber projectdescription
       si_runningnumber si_number si_description
       si_warehouse si_bin si_chargenumber si_bestbefore si_qty si_unit weight lineweight);

  map { $form->{TEMPLATE_ARRAYS}->{$_} = [] } (@arrays);

  push @arrays, map { "ic_cvar_$_->{name}" } @{ $ic_cvar_configs };

  $form->get_lists('price_factors' => 'ALL_PRICE_FACTORS');
  my %price_factors = map { $_->{id} => $_->{factor} } @{ $form->{ALL_PRICE_FACTORS} };

  my $totalweight = 0;
  my $sameitem = "";
  foreach $item (sort { $a->[1] cmp $b->[1] } @partsgroup) {
    $i = $item->[0];

    next if (!$form->{"id_$i"});

    $position++;

    if ($item->[1] ne $sameitem) {
      push(@{ $form->{description} }, qq|$item->[1]|);
      $sameitem = $item->[1];

      map({ push(@{ $form->{$_} }, "") } grep({ $_ ne "description" } @arrays));
    }

    $form->{"qty_$i"} = $form->parse_amount($myconfig, $form->{"qty_$i"});

    # add number, description and qty to $form->{number}, ....

    my $price_factor = $price_factors{$form->{"price_factor_id_$i"}} || { 'factor' => 1 };

    push @{ $form->{TEMPLATE_ARRAYS}{runningnumber} },   $position;
    push @{ $form->{TEMPLATE_ARRAYS}{number} },          $form->{"partnumber_$i"};
    push @{ $form->{TEMPLATE_ARRAYS}{description} },     $form->{"description_$i"};
    push @{ $form->{TEMPLATE_ARRAYS}{longdescription} }, $form->{"longdescription_$i"};
    push @{ $form->{TEMPLATE_ARRAYS}{qty} },             $form->format_amount($myconfig, $form->{"qty_$i"});
    push @{ $form->{TEMPLATE_ARRAYS}{qty_nofmt} },       $form->{"qty_$i"};
    push @{ $form->{TEMPLATE_ARRAYS}{unit} },            $form->{"unit_$i"};
    push @{ $form->{TEMPLATE_ARRAYS}{partnotes} },       $form->{"partnotes_$i"};
    push @{ $form->{TEMPLATE_ARRAYS}{serialnumber} },    $form->{"serialnumber_$i"};
    push @{ $form->{TEMPLATE_ARRAYS}{reqdate} },         $form->{"reqdate_$i"};
    push @{ $form->{TEMPLATE_ARRAYS}{projectnumber} },   $projectnumbers{$form->{"project_id_$i"}};
    push @{ $form->{TEMPLATE_ARRAYS}{projectdescription} },
      $projectdescriptions{$form->{"project_id_$i"}};

    my $lineweight = $form->{"qty_$i"} * $form->{"weight_$i"};
    $totalweight += $lineweight;
    push @{ $form->{TEMPLATE_ARRAYS}->{weight} },            $form->format_amount($myconfig, $form->{"weight_$i"}, 3);
    push @{ $form->{TEMPLATE_ARRAYS}->{weight_nofmt} },      $form->{"weight_$i"};
    push @{ $form->{TEMPLATE_ARRAYS}->{lineweight} },        $form->format_amount($myconfig, $lineweight, 3);
    push @{ $form->{TEMPLATE_ARRAYS}->{lineweight_nofmt} },  $lineweight;

    if ($form->{"assembly_$i"}) {
      $sameitem = "";

      # get parts and push them onto the stack
      my $sortorder = "";
      if ($form->{groupitems}) {
        $sortorder =
          qq|ORDER BY pg.partsgroup, a.oid|;
      } else {
        $sortorder = qq|ORDER BY a.oid|;
      }

      do_statement($form, $h_pg, $q_pg, conv_i($form->{"id_$i"}));

      while (my $ref = $h_pg->fetchrow_hashref("NAME_lc")) {
        if ($form->{groupitems} && $ref->{partsgroup} ne $sameitem) {
          map({ push(@{ $form->{TEMPLATE_ARRAYS}->{$_} }, "") } grep({ $_ ne "description" } @arrays));
          $sameitem = ($ref->{partsgroup}) ? $ref->{partsgroup} : "--";
          push(@{ $form->{TEMPLATE_ARRAYS}->{description} }, $sameitem);
        }
        push(@{ $form->{TEMPLATE_ARRAYS}->{"description"} }, $form->format_amount($myconfig, $ref->{qty} * $form->{"qty_$i"}) . qq| -- $ref->{partnumber}, $ref->{description}|);

        map({ push(@{ $form->{TEMPLATE_ARRAYS}->{$_} }, "") } grep({ $_ ne "description" } @arrays));
      }
    }

    if ($form->{"inventory_accno_$i"} && !$form->{"assembly_$i"}) {
      my $stock_info = DO->unpack_stock_information('packed' => $form->{"stock_${in_out}_$i"});

      foreach my $si (@{ $stock_info }) {
        $num_si++;

        do_statement($form, $h_bin_wh, $q_bin_wh, conv_i($si->{bin_id}), conv_i($si->{warehouse_id}));
        my $bin_wh = $h_bin_wh->fetchrow_hashref();

        push @{ $form->{TEMPLATE_ARRAYS}{si_runningnumber}[$position-1] }, $num_si;
        push @{ $form->{TEMPLATE_ARRAYS}{si_number}[$position-1] },        $form->{"partnumber_$i"};
        push @{ $form->{TEMPLATE_ARRAYS}{si_description}[$position-1] },   $form->{"description_$i"};
        push @{ $form->{TEMPLATE_ARRAYS}{si_warehouse}[$position-1] },     $bin_wh->{warehouse};
        push @{ $form->{TEMPLATE_ARRAYS}{si_bin}[$position-1] },           $bin_wh->{bin};
        push @{ $form->{TEMPLATE_ARRAYS}{si_chargenumber}[$position-1] },  $si->{chargenumber};
        push @{ $form->{TEMPLATE_ARRAYS}{si_bestbefore}[$position-1] },    $si->{bestbefore};
        push @{ $form->{TEMPLATE_ARRAYS}{si_qty}[$position-1] },           $form->format_amount($myconfig, $si->{qty} * 1);
        push @{ $form->{TEMPLATE_ARRAYS}{si_qty_nofmt}[$position-1] },     $si->{qty} * 1;
        push @{ $form->{TEMPLATE_ARRAYS}{si_unit}[$position-1] },          $si->{unit};
      }
    }

    push @{ $form->{TEMPLATE_ARRAYS}->{"ic_cvar_$_->{name}"} },
      CVar->format_to_template(CVar->parse($form->{"ic_cvar_$_->{name}_$i"}, $_), $_)
        for @{ $ic_cvar_configs };
  }

  $form->{totalweight}       = $form->format_amount($myconfig, $totalweight, 3);
  $form->{totalweight_nofmt} = $totalweight;
  my $defaults = AM->get_defaults();
  $form->{weightunit}        = $defaults->{weightunit};

  $h_pg->finish();
  $h_bin_wh->finish();

  $form->{username} = $myconfig->{name};

  $main::lxdebug->leave_sub();
}

sub project_description {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $id) = @_;

  my $form     =  $main::form;

  my $query = qq|SELECT description FROM project WHERE id = ?|;
  my ($value) = selectrow_query($form, $dbh, $query, $id);

  $main::lxdebug->leave_sub();

  return $value;
}

sub unpack_stock_information {
  $main::lxdebug->enter_sub();

  my $self   = shift;
  my %params = @_;

  Common::check_params_x(\%params, qw(packed));

  my $unpacked;

  eval { $unpacked = $params{packed} ? YAML::Load($params{packed}) : []; };

  $unpacked = [] if (!$unpacked || ('ARRAY' ne ref $unpacked));

  foreach my $entry (@{ $unpacked }) {
    next if ('HASH' eq ref $entry);
    $unpacked = [];
    last;
  }

  $main::lxdebug->leave_sub();

  return $unpacked;
}

sub get_item_availability {
  $::lxdebug->enter_sub;

  my $self     = shift;
  my %params   = @_;

  Common::check_params(\%params, qw(parts_id));

  my @parts_ids = 'ARRAY' eq ref $params{parts_id} ? @{ $params{parts_id} } : ($params{parts_id});

  my $query     =
    qq|SELECT i.warehouse_id, i.bin_id, i.chargenumber, i.bestbefore, SUM(qty) AS qty, i.parts_id,
         w.description AS warehousedescription,
         b.description AS bindescription
       FROM inventory i
       LEFT JOIN warehouse w ON (i.warehouse_id = w.id)
       LEFT JOIN bin b       ON (i.bin_id       = b.id)
       WHERE (i.parts_id IN (| . join(', ', ('?') x scalar(@parts_ids)) . qq|))
       GROUP BY i.warehouse_id, i.bin_id, i.chargenumber, i.bestbefore, i.parts_id, w.description, b.description
       HAVING SUM(qty) > 0
       ORDER BY LOWER(w.description), LOWER(b.description), LOWER(i.chargenumber), i.bestbefore
|;
  my $contents = selectall_hashref_query($::form, $::form->get_standard_dbh, $query, @parts_ids);

  $::lxdebug->leave_sub;

  return @{ $contents };
}


sub check_stock_availability {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  Common::check_params(\%params, qw(requests parts_id));

  my $myconfig    = \%main::myconfig;
  my $form        =  $main::form;

  my $dbh         = $form->get_standard_dbh($myconfig);

  my $units       = AM->retrieve_units($myconfig, $form);

  my ($partunit)  = selectrow_query($form, $dbh, qq|SELECT unit FROM parts WHERE id = ?|, conv_i($params{parts_id}));
  my $unit_factor = $units->{$partunit}->{factor} || 1;

  my @contents    = $self->get_item_availability(%params);

  my @errors;

  foreach my $sinfo (@{ $params{requests} }) {
    my $found = 0;

    foreach my $row (@contents) {
      next if (($row->{bin_id}       != $sinfo->{bin_id}) ||
               ($row->{warehouse_id} != $sinfo->{warehouse_id}) ||
               ($row->{chargenumber} ne $sinfo->{chargenumber}) ||
               ($row->{bestbefore}   ne $sinfo->{bestbefore}));

      $found       = 1;

      my $base_qty = $sinfo->{qty} * $units->{$sinfo->{unit}}->{factor} / $unit_factor;

      if ($base_qty > $row->{qty}) {
        $sinfo->{error} = 1;
        push @errors, $sinfo;

        last;
      }
    }

    push @errors, $sinfo if (!$found);
  }

  $main::lxdebug->leave_sub();

  return @errors;
}

sub transfer_in_out {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  Common::check_params(\%params, qw(direction requests));

  if (!@{ $params{requests} }) {
    $main::lxdebug->leave_sub();
    return;
  }

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  my $prefix   = $params{direction} eq 'in' ? 'dst' : 'src';

  my @transfers;

  foreach my $request (@{ $params{requests} }) {
    push @transfers, {
      'parts_id'               => $request->{parts_id},
      "${prefix}_warehouse_id" => $request->{warehouse_id},
      "${prefix}_bin_id"       => $request->{bin_id},
      'chargenumber'           => $request->{chargenumber},
      'bestbefore'             => $request->{bestbefore},
      'qty'                    => $request->{qty},
      'unit'                   => $request->{unit},
      'oe_id'                  => $form->{id},
      'shippingdate'           => 'current_date',
      'transfer_type'          => $params{direction} eq 'in' ? 'stock' : 'shipped',
      'project_id'             => $request->{project_id},
    };
  }

  WH->transfer(@transfers);

  $main::lxdebug->leave_sub();
}

sub get_shipped_qty {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  Common::check_params(\%params, qw(type oe_id));

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  my $dbh      = $params{dbh} || $form->get_standard_dbh($myconfig);

  my @links    = RecordLinks->get_links('dbh'        => $dbh,
                                        'from_table' => 'oe',
                                        'from_id'    => $params{oe_id},
                                        'to_table'   => 'delivery_orders');
  my @values   = map { $_->{to_id} } @links;

  if (!scalar @values) {
    $main::lxdebug->leave_sub();
    return ();
  }

  my $query =
    qq|SELECT doi.parts_id, doi.qty, doi.unit, p.unit AS partunit
       FROM delivery_order_items doi
       LEFT JOIN delivery_orders o ON (doi.delivery_order_id = o.id)
       LEFT JOIN parts p ON (doi.parts_id = p.id)
       WHERE o.id IN (| . join(', ', ('?') x scalar @values) . qq|)|;

  my %ship      = ();
  my $entries   = selectall_hashref_query($form, $dbh, $query, @values);
  my $all_units = AM->retrieve_all_units();

  foreach my $entry (@{ $entries }) {
    $entry->{qty} *= AM->convert_unit($entry->{unit}, $entry->{partunit}, $all_units);

    if (!$ship{$entry->{parts_id}}) {
      $ship{$entry->{parts_id}} = $entry;
    } else {
      $ship{$entry->{parts_id}}->{qty} += $entry->{qty};
    }
  }

  $main::lxdebug->leave_sub();

  return %ship;
}

sub is_marked_as_delivered {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  Common::check_params(\%params, qw(id));

  my $myconfig    = \%main::myconfig;
  my $form        = $main::form;

  my $dbh         = $params{dbh} || $form->get_standard_dbh($myconfig);

  my ($delivered) = selectfirst_array_query($form, $dbh, qq|SELECT delivered FROM delivery_orders WHERE id = ?|, conv_i($params{id}));

  $main::lxdebug->leave_sub();

  return $delivered ? 1 : 0;
}


1;
