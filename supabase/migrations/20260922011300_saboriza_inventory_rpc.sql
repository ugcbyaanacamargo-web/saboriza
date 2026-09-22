-- Domain RPCs for stock, raw material entries and confirmed production.
-- Invoker privileges + admin RLS; no anonymous or unprivileged user can execute them.
grant insert on public.stock_movements,public.production_records,
  public.production_consumptions to authenticated;
grant update on public.raw_material_entries to authenticated;
alter table public.stock_movements add constraint stock_movement_balances_match
  check (new_balance = previous_balance + variation);
alter table public.stock_movements add constraint stock_movement_origin_zero
  check (variation <> 0 or origin='order');

create function public.create_stock_entry(
  p_product_id text,p_quantity numeric,p_observation text default ''
) returns public.stock_movements
language plpgsql security invoker set search_path='' as $$
declare p public.products%rowtype; m public.stock_movements%rowtype;
begin
  if not public.saboriza_is_admin() then raise exception 'Acesso administrativo obrigatório'; end if;
  if p_quantity is null or p_quantity <= 0 or p_quantity > 100000000 or p_quantity::text='NaN'
  then raise exception 'Quantidade inválida'; end if;
  select * into p from public.products where id=p_product_id for update;
  if not found then raise exception 'Produto não encontrado'; end if;
  update public.products set current_stock=p.current_stock+p_quantity where id=p.id;
  insert into public.stock_movements(
    product_id,variation,origin,responsible_id,observation,previous_balance,new_balance
  ) values (p.id,p_quantity,'entry',auth.uid(),coalesce(p_observation,''),p.current_stock,p.current_stock+p_quantity)
  returning * into m;
  return m;
end $$;

create function public.adjust_stock(
  p_product_id text,p_counted_stock numeric,p_reason text
) returns public.stock_movements
language plpgsql security invoker set search_path='' as $$
declare p public.products%rowtype; m public.stock_movements%rowtype;
begin
  if not public.saboriza_is_admin() then raise exception 'Acesso administrativo obrigatório'; end if;
  if p_counted_stock is null or p_counted_stock < 0 or p_counted_stock > 100000000
    or p_counted_stock::text='NaN' or btrim(coalesce(p_reason,''))='' then
    raise exception 'Informe estoque válido e motivo do ajuste';
  end if;
  select * into p from public.products where id=p_product_id for update;
  if not found then raise exception 'Produto não encontrado'; end if;
  if p_counted_stock=p.current_stock then raise exception 'Não existe diferença de estoque para ajustar'; end if;
  update public.products set current_stock=p_counted_stock where id=p.id;
  insert into public.stock_movements(
    product_id,variation,origin,responsible_id,observation,previous_balance,new_balance
  ) values (
    p.id,p_counted_stock-p.current_stock,'adjustment',auth.uid(),btrim(p_reason),
    p.current_stock,p_counted_stock
  ) returning * into m;
  return m;
end $$;

create function public.confirm_raw_material_entry(p_entry_id text)
returns public.raw_material_entries
language plpgsql security invoker set search_path='' as $$
declare e public.raw_material_entries%rowtype;
        m public.raw_materials%rowtype;
        qty numeric(18,6); total numeric(18,6); new_avg numeric(18,6);
begin
  if not public.saboriza_is_admin() then raise exception 'Acesso administrativo obrigatório'; end if;
  select * into e from public.raw_material_entries where id=p_entry_id for update;
  if not found then raise exception 'Entrada não encontrada'; end if;
  if e.status<>'draft' then raise exception 'Entrada já confirmada ou estornada'; end if;
  select * into m from public.raw_materials where id=e.raw_material_id for update;
  if not found then raise exception 'Insumo não encontrado'; end if;
  if not m.is_active then raise exception 'Insumo inativo'; end if;
  qty:=round(e.packages_quantity*m.purchase_unit_factor,6);
  total:=round(e.packages_quantity*e.unit_price,6);
  if qty<=0 then raise exception 'Quantidade convertida inválida'; end if;
  new_avg:=round(((m.current_stock*m.avg_cost)+total)/(m.current_stock+qty),6);
  update public.raw_materials set
    current_stock=m.current_stock+qty, avg_cost=new_avg,unit_locked=true
    where id=m.id;
  update public.raw_material_entries set
    status='confirmed',conversion_factor=m.purchase_unit_factor,
    control_quantity=qty,total_value=total,
    previous_balance=m.current_stock,new_balance=m.current_stock+qty,
    previous_avg_cost=m.avg_cost,new_avg_cost=new_avg,
    confirmed_at=now(),responsible_id=auth.uid()
    where id=e.id returning * into e;
  return e;
end $$;

create function public.reverse_raw_material_entry(
  p_entry_id text,p_reason text
) returns public.raw_material_entries
language plpgsql security invoker set search_path='' as $$
declare e public.raw_material_entries%rowtype; m public.raw_materials%rowtype;
begin
  if not public.saboriza_is_admin() then raise exception 'Acesso administrativo obrigatório'; end if;
  if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Informe motivo do estorno'; end if;
  select * into e from public.raw_material_entries where id=p_entry_id for update;
  if not found then raise exception 'Entrada não encontrada'; end if;
  if e.status<>'confirmed' then raise exception 'Somente entradas confirmadas podem ser estornadas'; end if;
  select * into m from public.raw_materials where id=e.raw_material_id for update;
  if not found then raise exception 'Insumo não encontrado'; end if;
  -- No later receipt or production may be silently undone.
  if m.current_stock<>e.new_balance or m.avg_cost<>e.new_avg_cost or exists(
      select 1 from public.raw_material_entries n
       where n.raw_material_id=e.raw_material_id and n.id<>e.id
       and n.status='confirmed' and n.confirmed_at>=e.confirmed_at
     ) or exists(
      select 1 from public.production_consumptions c
      where c.raw_material_id=e.raw_material_id and c.created_at>=e.confirmed_at
     ) then
    raise exception 'Existem movimentações posteriores; estorno automático não é seguro';
  end if;
  update public.raw_materials set
    current_stock=e.previous_balance,avg_cost=e.previous_avg_cost
    where id=m.id;
  update public.raw_material_entries set
    status='reversed',reversal_reason=btrim(p_reason),
    reversed_at=now(),reversed_by=auth.uid()
    where id=e.id returning * into e;
  return e;
end $$;

create function public.create_production(
  p_product_id text,p_packs_quantity integer
) returns public.production_records
language plpgsql security invoker set search_path='' as $$
declare p public.products%rowtype; r public.production_records%rowtype;
        line record; needed numeric(18,6); units integer; n integer:=0;
begin
  if not public.saboriza_is_admin() then raise exception 'Acesso administrativo obrigatório'; end if;
  if p_packs_quantity is null or p_packs_quantity<1 or p_packs_quantity>100000 then
    raise exception 'Quantidade de packs inválida';
  end if;
  select * into p from public.products where id=p_product_id for update;
  if not found or not p.is_active then raise exception 'Produto inexistente ou inativo'; end if;
  if p.pack_quantity > 100000000/p_packs_quantity then raise exception 'Quantidade excede limite'; end if;
  units:=p.pack_quantity*p_packs_quantity;
  if not exists(select 1 from public.product_recipe where product_id=p.id) then
    raise exception 'Cadastre a ficha técnica antes de produzir';
  end if;
  -- Each stock row is locked in a deterministic order. Any shortage raises an
  -- exception and rolls back the entire production (including all consumptions).
  insert into public.production_records(
    product_id,packs_quantity,units_quantity,status,responsible_id
  ) values (p.id,p_packs_quantity,units,'confirmed',auth.uid()) returning * into r;
  for line in
    select pr.raw_material_id,pr.quantity_per_unit,
           m.current_stock,m.is_active,m.name
    from public.product_recipe pr
    join public.raw_materials m on m.id=pr.raw_material_id
    where pr.product_id=p.id
    order by pr.raw_material_id
    for update of m
  loop
    needed:=round(line.quantity_per_unit*units,6);
    if not line.is_active or needed>line.current_stock then
      raise exception 'Estoque insuficiente do insumo: %',line.name;
    end if;
    update public.raw_materials
      set current_stock=line.current_stock-needed,unit_locked=true
      where id=line.raw_material_id;
    insert into public.production_consumptions(
      production_record_id,raw_material_id,needed_quantity,consumed_quantity,
      previous_balance,new_balance
    ) values (
      r.id,line.raw_material_id,needed,needed,
      line.current_stock,line.current_stock-needed
    );
    n:=n+1;
  end loop;
  if n=0 then raise exception 'Ficha técnica sem insumos válidos'; end if;
  update public.products set current_stock=p.current_stock+units where id=p.id;
  insert into public.stock_movements(
    product_id,variation,origin,reference_id,responsible_id,observation,
    previous_balance,new_balance
  ) values (
    p.id,units,'production',r.id,auth.uid(),'Produção confirmada',
    p.current_stock,p.current_stock+units
  );
  return r;
end $$;

create function public.rename_raw_material_category(p_id uuid,p_name text)
returns void language plpgsql security invoker set search_path='' as $$
declare old_name text; clean_name text:=regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g');
begin
  if not public.saboriza_is_admin() then raise exception 'Acesso administrativo obrigatório'; end if;
  if clean_name='' then raise exception 'Nome da categoria não pode ficar vazio'; end if;
  select name into old_name from public.raw_material_categories where id=p_id for update;
  if not found then raise exception 'Categoria não encontrada'; end if;
  update public.raw_material_categories set name=clean_name where id=p_id;
  update public.raw_materials set category=clean_name
    where lower(btrim(category))=lower(btrim(old_name));
end $$;

-- Stock is decremented once when an administrator marks an order COMPLETED.
-- A zero-stock shortfall is recorded explicitly for the original UI warning.
create function public.saboriza_complete_order_stock()
returns trigger language plpgsql security invoker set search_path='' as $$
declare line record; p public.products%rowtype;
        deducted numeric(18,4); balance numeric(18,4); message text;
begin
  for line in
    select product_id,sum(total_units)::numeric as units
      from public.order_items
      where order_id=new.id and product_id is not null
      group by product_id order by product_id
  loop
    if exists(select 1 from public.stock_movements
      where origin='order' and reference_id=new.id and product_id=line.product_id) then
      continue;
    end if;
    select * into p from public.products where id=line.product_id for update;
    if not found then continue; end if;
    deducted:=least(p.current_stock,line.units);
    balance:=p.current_stock-deducted;
    message:=case when deducted<line.units
      then 'Estoque insuficiente: baixa até zero'
      else 'Pedido concluído' end;
    update public.products set current_stock=balance where id=p.id;
    insert into public.stock_movements(
      product_id,variation,origin,reference_id,responsible_id,observation,
      previous_balance,new_balance
    ) values (
      p.id,-deducted,'order',new.id,auth.uid(),message,p.current_stock,balance
    );
  end loop;
  return new;
end $$;
create trigger orders_complete_stock
after update of status on public.orders
for each row
when (new.status='COMPLETED' and old.status is distinct from new.status)
execute function public.saboriza_complete_order_stock();

revoke all on function public.create_stock_entry(text,numeric,text) from public,anon;
revoke all on function public.adjust_stock(text,numeric,text) from public,anon;
revoke all on function public.confirm_raw_material_entry(text) from public,anon;
revoke all on function public.reverse_raw_material_entry(text,text) from public,anon;
revoke all on function public.create_production(text,integer) from public,anon;
revoke all on function public.rename_raw_material_category(uuid,text) from public,anon;
revoke all on function public.saboriza_complete_order_stock() from public,anon,authenticated;
grant execute on function public.create_stock_entry(text,numeric,text) to authenticated;
grant execute on function public.adjust_stock(text,numeric,text) to authenticated;
grant execute on function public.confirm_raw_material_entry(text) to authenticated;
grant execute on function public.reverse_raw_material_entry(text,text) to authenticated;
grant execute on function public.create_production(text,integer) to authenticated;
grant execute on function public.rename_raw_material_category(uuid,text) to authenticated;
