-- Transactional smoke test of the Saboriza database as the real admin role.
-- All fixtures are rolled back; pre-existing products, customers and orders are untouched.
-- Run only against an authorized Saboriza Supabase database after migrations.
begin;
do $$
declare claim text;
begin
  select json_build_object('sub',id::text,'role','authenticated','app_metadata',raw_app_meta_data)::text
    into claim from auth.users
    where raw_app_meta_data->>'saboriza_role'='admin'
    order by created_at limit 1;
  if claim is null then raise exception 'No Saboriza admin exists for release verification'; end if;
  perform set_config('request.jwt.claims',claim,true);
end $$;
set local role authenticated;
do $$
declare
  c text:=gen_random_uuid()::text;
  s text:=gen_random_uuid()::text;
  p text:=gen_random_uuid()::text;
  m text:=gen_random_uuid()::text;
  e1 text:=gen_random_uuid()::text;
  e2 text:=gen_random_uuid()::text;
  o text:=gen_random_uuid()::text;
  v numeric;
  blocked boolean;
begin
  if not public.saboriza_is_admin() then raise exception 'Admin JWT check failed'; end if;
  if has_table_privilege('anon','public.raw_materials','SELECT')
      or has_function_privilege('anon','public.create_production(text,integer)','EXECUTE') then
    raise exception 'Anonymous access to production data was granted';
  end if;
  insert into public.categories(id,name,slug)
    values(c,'[smoke] Categoria','smoke-'||c);
  insert into public.suppliers(id,name,company_name,phone)
    values(s,'[smoke] Fornecedor','[smoke] Fornecedor','62999999999');
  insert into public.products(id,name,category_id,presentation,weight_volume,unit_price,pack_quantity,packaging_type)
    values(p,'[smoke] Produto',c,'Caixa','100 g',2,5,'Caixa');
  insert into public.raw_materials(id,name,control_unit,purchase_unit_factor)
    values(m,'[smoke] Insumo','g',20);
  insert into public.product_recipe(product_id,raw_material_id,quantity_per_unit)
    values(p,m,1);
  if (select unit_locked from public.raw_materials where id=m) is not true then
    raise exception 'Recipe did not lock the material control unit';
  end if;
  insert into public.raw_material_entries(id,raw_material_id,supplier_id,packages_quantity,unit_price,batch,expiry_date,entry_date)
    values(e1,m,s,1,30,'SMOKE1',current_date+30,current_date);
  perform public.confirm_raw_material_entry(e1);
  select current_stock into v from public.raw_materials where id=m;
  if v<>20 then raise exception 'Receipt conversion wrong: %',v; end if;
  select avg_cost into v from public.raw_materials where id=m;
  if v<>1.5 then raise exception 'Weighted cost wrong: %',v; end if;
  perform public.reverse_raw_material_entry(e1,'Estorno teste transacional');
  select current_stock into v from public.raw_materials where id=m;
  if v<>0 then raise exception 'Reversal did not return material stock to zero'; end if;
  insert into public.raw_material_entries(id,raw_material_id,supplier_id,packages_quantity,unit_price,batch,expiry_date,entry_date)
    values(e2,m,s,1,30,'SMOKE2',current_date+30,current_date);
  perform public.confirm_raw_material_entry(e2);
  perform public.create_production(p,2);
  select current_stock into v from public.raw_materials where id=m;
  if v<>10 then raise exception 'Production failed to consume recipe quantity: %',v; end if;
  select current_stock into v from public.products where id=p;
  if v<>10 then raise exception 'Production product stock wrong: %',v; end if;
  blocked:=false;
  begin
    perform public.create_production(p,3);
  exception when others then
    if position('Estoque insuficiente' in sqlerrm)>0 then blocked:=true;
    else raise; end if;
  end;
  if not blocked then raise exception 'Insufficient production was accepted'; end if;
  if (select count(*) from public.production_records where product_id=p)<>1
    then raise exception 'Failed production left a partial record'; end if;
  blocked:=false;
  begin
    perform public.reverse_raw_material_entry(e2,'Tentativa após consumo');
  exception when others then
    if position('movimentações posteriores' in sqlerrm)>0 then blocked:=true;
    else raise; end if;
  end;
  if not blocked then raise exception 'Reversal after production was accepted'; end if;
  perform public.create_stock_entry(p,5,'Entrada teste');
  perform public.adjust_stock(p,8,'Contagem teste');
  select current_stock into v from public.products where id=p;
  if v<>8 then raise exception 'Product stock adjustment wrong: %',v; end if;
  insert into public.orders(id,customer_name,phone)
    values(o,'[smoke] Cliente','62999999999');
  insert into public.order_items(order_id,product_id,product_name,presentation,weight_volume,unit_price,pack_quantity,packs_quantity,total_units,total_price)
    values(o,p,'[smoke] Produto','Caixa','100 g',2,5,2,10,20);
  update public.orders set status='COMPLETED' where id=o;
  select current_stock into v from public.products where id=p;
  if v<>0 then raise exception 'Completed order stock wrong: %',v; end if;
  if not exists(
    select 1 from public.stock_movements
    where origin='order' and reference_id=o and variation=-8
      and observation like '%insuficiente%'
  ) then raise exception 'Shortfall audit is missing'; end if;
  update public.orders set status='CONFIRMED' where id=o;
  update public.orders set status='COMPLETED' where id=o;
  if (select count(*) from public.stock_movements where origin='order' and reference_id=o)<>1
    then raise exception 'Order completion debited inventory twice'; end if;
end $$;
-- Switch to a simulated authenticated account without the app_metadata admin role.
reset role;
do $$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{}}',true);
end $$;
set local role authenticated;
do $$
declare blocked boolean:=false;
begin
  if public.saboriza_is_admin() then
    raise exception 'Unprivileged JWT incorrectly considered admin';
  end if;
  begin
    perform public.create_stock_entry('nonexistent',1,'not authorized');
  exception when others then
    if position('Acesso administrativo obrigatório' in sqlerrm)>0 then
      blocked:=true;
    else raise; end if;
  end;
  if not blocked then raise exception 'Nonadmin RPC was allowed'; end if;
  if exists(select 1 from public.raw_materials) then
    raise exception 'Nonadmin could read raw materials';
  end if;
end $$;
rollback;