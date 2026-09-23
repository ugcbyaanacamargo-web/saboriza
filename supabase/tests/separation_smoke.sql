-- Saboriza separation end-to-end integration test.
-- Real admin RLS, queue timestamps, item confirmation, adjustments, stock
-- and no duplicate stock debit. All fixtures are rolled back.
begin;
do $$
declare admin_claim text;
begin
 select json_build_object('sub',id::text,'role','authenticated',
   'app_metadata',raw_app_meta_data)::text
 into admin_claim from auth.users
 where raw_app_meta_data->>'saboriza_role'='admin'
 order by created_at limit 1;
 if admin_claim is null then raise exception 'Admin required for separation integration smoke'; end if;
 perform set_config('request.jwt.claims',admin_claim,true);
end $$;
set local role authenticated;
do $$
declare
  category_id text:=gen_random_uuid()::text;
  product_id text:=gen_random_uuid()::text;
  order_id text:=gen_random_uuid()::text;
  other_order_id text:=gen_random_uuid()::text;
  item_id text:=gen_random_uuid()::text;
  adjustment_id text;
  v numeric;
  blocked boolean;
begin
  if not public.saboriza_is_admin() then raise exception 'Admin claim unavailable'; end if;
  if has_table_privilege('anon','public.order_adjustment_requests','SELECT') then
    raise exception 'Anonymous adjustment access must be disabled';
  end if;
  if not exists(
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public'
      and tablename='orders'
  ) then raise exception 'Order Realtime queue publication missing'; end if;

  insert into public.categories(id,name,slug)
  values(category_id,'[test] Categoria','separation-test-'||category_id);
  insert into public.products(
    id,name,category_id,presentation,weight_volume,unit_price,
    pack_quantity,packaging_type
  ) values(
    product_id,'[test] Produto',category_id,'Caixa','100g',2,5,'Caixa'
  );
  perform public.create_stock_entry(product_id,8,'Separation integration test');
  insert into public.orders(id,customer_name,phone)
  values(order_id,'[test] Comprador','62999999999');
  insert into public.orders(id,customer_name,phone)
  values(other_order_id,'[test] Outro comprador','62999999999');
  insert into public.order_items(
    id,order_id,product_id,product_name,presentation,weight_volume,
    unit_price,pack_quantity,packs_quantity,total_units,total_price
  ) values(
    item_id,order_id,product_id,'[test] Produto','Caixa','100g',2,5,1,5,10
  );

  update public.orders set status='CONFIRMED' where id=other_order_id;
  update public.orders set status='CONFIRMED' where id=order_id;
  if (select separation_queued_at from public.orders where id=order_id) is null then
    raise exception 'Confirmation did not enqueue the order';
  end if;
  update public.orders set separation_responsible='[test] operador',
    separation_started_by='[test] operador',separation_started_at=now()
    where id=order_id and separation_responsible is null;

  blocked:=false;
  begin
    insert into public.order_adjustment_requests(order_id,order_item_id,message)
    values(other_order_id,item_id,'Item de outro pedido');
  exception when others then
    if position('não pertence' in sqlerrm)>0 then blocked:=true; else raise; end if;
  end;
  if not blocked then raise exception 'Cross-order adjustment accepted'; end if;

  insert into public.order_adjustment_requests(order_id,order_item_id,message,created_by)
  values(order_id,item_id,'Verificar divergência física','[test] operador')
  returning id into adjustment_id;

  blocked:=false;
  begin
    update public.orders set status='COMPLETED' where id=order_id;
  exception when others then
    if position('ajuste pendente' in sqlerrm)>0 then blocked:=true; else raise; end if;
  end;
  if not blocked then raise exception 'Completed with pending adjustment'; end if;

  update public.order_adjustment_requests
    set status='resolved',resolved_by='[test] operador'
    where id=adjustment_id;
  if (select resolved_at from public.order_adjustment_requests
      where id=adjustment_id) is null then
    raise exception 'Resolved request missing resolution timestamp';
  end if;

  blocked:=false;
  begin
    update public.orders set status='COMPLETED' where id=order_id;
  exception when others then
    if position('itens pendentes' in sqlerrm)>0 then blocked:=true; else raise; end if;
  end;
  if not blocked then raise exception 'Completed without physical item check'; end if;

  update public.order_items set separated_at=now() where id=item_id;
  update public.orders
    set status='COMPLETED',separation_completed_by='[test] operador'
    where id=order_id;
  if (select separation_finished_at from public.orders where id=order_id) is null then
    raise exception 'Finished separation was not timestamped';
  end if;
  select current_stock into v from public.products where id=product_id;
  if v<>3 then raise exception 'Stock deduction after separation expected 3, got %',v; end if;

  blocked:=false;
  begin
    update public.order_items set separated_at=null where id=item_id;
  exception when others then
    if position('pedido confirmado' in sqlerrm)>0 then blocked:=true; else raise; end if;
  end;
  if not blocked then raise exception 'Allowed editing physical check after completion'; end if;
  update public.orders set status='CONFIRMED' where id=order_id;
  update public.orders set status='COMPLETED' where id=order_id;
  if (select count(*) from public.stock_movements
      where reference_id=order_id and origin='order')<>1 then
    raise exception 'Stock debited twice for same completed order';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{}}',true);
set local role authenticated;
do $$
begin
  if public.saboriza_is_admin() then raise exception 'Nonadmin became admin'; end if;
  if exists(select 1 from public.order_adjustment_requests) then
    raise exception 'Nonadmin may read private adjustments';
  end if;
end $$;
rollback;
