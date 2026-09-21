-- Supabase RPCs required by the unchanged original Saboriza frontend.
-- IMPORTANT: these functions reprice from public.products, never trust browser-supplied prices.
create or replace function public.create_order(
  p_customer_name text,
  p_company_name text,
  p_phone text,
  p_items jsonb,
  p_coupon_code text default '',
  p_customer_address text default '',
  p_customer_cep text default '',
  p_customer_city text default '',
  p_customer_cnpj text default '',
  p_customer_email text default '',
  p_customer_id text default null,
  p_customer_ie text default '',
  p_customer_neighborhood text default '',
  p_customer_state text default '',
  p_customer_trade_name text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_item jsonb;
  v_product public.products%rowtype;
  v_coupon public.coupons%rowtype;
  v_subtotal numeric(14,2) := 0;
  v_discount numeric(14,2) := 0;
  v_units integer := 0;
  v_packs integer;
  v_code text := upper(btrim(coalesce(p_coupon_code,'')));
  v_coupon_type text := '';
  v_coupon_value numeric(14,2) := 0;
  v_items jsonb := '[]'::jsonb;
  v_product_id text;
begin
  if length(btrim(coalesce(p_customer_name,''))) not between 1 and 200
     or length(btrim(coalesce(p_phone,''))) not between 5 and 40
     or length(coalesce(p_company_name,'')) > 200 then
    raise exception 'Preencha nome, telefone e empresa corretamente.';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 100 then
    raise exception 'O pedido deve ter entre 1 e 100 itens.';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) e
    where jsonb_typeof(e) <> 'object'
      or jsonb_typeof(e->'product_id') <> 'string'
      or jsonb_typeof(e->'packs_quantity') <> 'number'
      or (e->>'packs_quantity') !~ '^[0-9]{1,5}$'
      or ((e->>'packs_quantity') ~ '^[0-9]{1,5}$'
          and (e->>'packs_quantity')::integer not between 1 and 1000)
  ) then
    raise exception 'Item ou quantidade inválida.';
  end if;
  if (select count(*) from jsonb_array_elements(p_items))
     <> (select count(distinct e->>'product_id') from jsonb_array_elements(p_items) e) then
    raise exception 'O mesmo produto foi informado mais de uma vez.';
  end if;

  -- A reference to a real customer is allowed only to the admin. Public checkout
  -- does not gain access to customer records by guessing their identifiers.
  insert into public.orders (
    customer_name, company_name, phone, customer_id,
    customer_address, customer_cep, customer_city, customer_cnpj,
    customer_email, customer_ie, customer_neighborhood, customer_state,
    customer_trade_name, coupon_code
  )
  values (
    btrim(p_customer_name),coalesce(p_company_name,''),btrim(p_phone),
    case when public.saboriza_is_admin() then p_customer_id else null end,
    coalesce(p_customer_address,''),coalesce(p_customer_cep,''),
    coalesce(p_customer_city,''),coalesce(p_customer_cnpj,''),
    coalesce(p_customer_email,''),coalesce(p_customer_ie,''),
    coalesce(p_customer_neighborhood,''),coalesce(p_customer_state,''),
    coalesce(p_customer_trade_name,''),v_code
  ) returning * into v_order;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := v_item->>'product_id';
    v_packs := (v_item->>'packs_quantity')::integer;
    select * into v_product from public.products
      where id = v_product_id and is_active = true;
    if not found then
      raise exception 'Produto não disponível: %', v_product_id;
    end if;
    insert into public.order_items (
      order_id,product_id,product_name,presentation,weight_volume,
      unit_price,pack_quantity,packs_quantity,total_units,total_price
    )
    values (
      v_order.id,v_product.id,v_product.name,v_product.presentation,
      v_product.weight_volume,v_product.unit_price,v_product.pack_quantity,
      v_packs,v_product.pack_quantity*v_packs,
      v_product.unit_price*v_product.pack_quantity*v_packs
    );
    v_subtotal := v_subtotal + (v_product.unit_price*v_product.pack_quantity*v_packs);
    v_units := v_units + v_product.pack_quantity*v_packs;
  end loop;

  if v_code <> '' then
    select * into v_coupon from public.coupons
      where upper(code)=v_code and is_active=true;
    if not found then
      raise exception 'Cupom inválido ou inativo.';
    end if;
    v_coupon_type := v_coupon.discount_type;
    v_coupon_value := v_coupon.discount_value;
    v_discount := case v_coupon_type
      when 'percentage' then least(v_subtotal,round(v_subtotal * least(v_coupon_value,100)/100,2))
      when 'fixed' then least(v_subtotal,v_coupon_value)
      else 0 end;
  end if;

  update public.orders set
    coupon_type = v_coupon_type,
    coupon_value = v_coupon_value,
    discount_amount = v_discount,
    subtotal_amount = v_subtotal,
    total_amount = v_subtotal-v_discount,
    total_units = v_units
  where id=v_order.id returning * into v_order;

  select coalesce(jsonb_agg(to_jsonb(oi) order by oi.created_at,oi.id),'[]'::jsonb)
    into v_items from public.order_items oi where oi.order_id=v_order.id;
  return to_jsonb(v_order) || jsonb_build_object('items',v_items);
end;
$$;

create or replace function public.update_order_items(
  p_order_id text,
  p_items jsonb,
  p_coupon_code text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_item jsonb;
  v_product public.products%rowtype;
  v_coupon public.coupons%rowtype;
  v_subtotal numeric(14,2) := 0;
  v_units integer := 0;
  v_discount numeric(14,2) := 0;
  v_coupon_type text := '';
  v_coupon_value numeric(14,2) := 0;
  v_code text := upper(btrim(coalesce(p_coupon_code,'')));
  v_packs integer;
  v_items jsonb;
begin
  if not public.saboriza_is_admin() then
    raise exception 'Acesso administrativo obrigatório.';
  end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception 'Pedido não encontrado.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 100 then
    raise exception 'O pedido deve ter entre 1 e 100 itens.';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) e
    where jsonb_typeof(e) <> 'object'
       or jsonb_typeof(e->'product_id') <> 'string'
       or jsonb_typeof(e->'packs_quantity') <> 'number'
       or (e->>'packs_quantity') !~ '^[0-9]{1,5}$'
       or ((e->>'packs_quantity') ~ '^[0-9]{1,5}$'
            and (e->>'packs_quantity')::integer not between 1 and 1000)
  ) then raise exception 'Item ou quantidade inválida.'; end if;
  if (select count(*) from jsonb_array_elements(p_items))
     <> (select count(distinct e->>'product_id') from jsonb_array_elements(p_items) e) then
    raise exception 'Produto duplicado no pedido.';
  end if;
  delete from public.order_items where order_id=p_order_id;
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_packs := (v_item->>'packs_quantity')::integer;
    select * into v_product from public.products
      where id=v_item->>'product_id' and is_active=true;
    if not found then raise exception 'Produto não disponível.'; end if;
    insert into public.order_items (
      order_id,product_id,product_name,presentation,weight_volume,
      unit_price,pack_quantity,packs_quantity,total_units,total_price
    ) values (
      p_order_id,v_product.id,v_product.name,v_product.presentation,
      v_product.weight_volume,v_product.unit_price,v_product.pack_quantity,
      v_packs,v_product.pack_quantity*v_packs,
      v_product.unit_price*v_product.pack_quantity*v_packs
    );
    v_subtotal := v_subtotal + v_product.unit_price*v_product.pack_quantity*v_packs;
    v_units := v_units + v_product.pack_quantity*v_packs;
  end loop;
  if v_code <> '' then
    select * into v_coupon from public.coupons where upper(code)=v_code and is_active=true;
    if not found then raise exception 'Cupom inválido ou inativo.'; end if;
    v_coupon_type := v_coupon.discount_type;
    v_coupon_value := v_coupon.discount_value;
    v_discount := case v_coupon_type
      when 'percentage' then least(v_subtotal,round(v_subtotal*least(v_coupon_value,100)/100,2))
      when 'fixed' then least(v_subtotal,v_coupon_value)
      else 0 end;
  end if;
  update public.orders set
    coupon_code=v_code,coupon_type=v_coupon_type,coupon_value=v_coupon_value,
    discount_amount=v_discount,subtotal_amount=v_subtotal,
    total_amount=v_subtotal-v_discount,total_units=v_units
    where id=p_order_id returning * into v_order;
  select coalesce(jsonb_agg(to_jsonb(oi) order by oi.created_at,oi.id),'[]'::jsonb)
    into v_items from public.order_items oi where oi.order_id=p_order_id;
  return to_jsonb(v_order)||jsonb_build_object('items',v_items);
end;
$$;

-- PostgREST requires named-argument access; revoke default EXECUTE on functions.
revoke all on function public.create_order(text,text,text,jsonb,text,text,text,text,text,text,text,text,text,text,text)
  from public,anon,authenticated;
grant execute on function public.create_order(text,text,text,jsonb,text,text,text,text,text,text,text,text,text,text,text)
  to anon,authenticated;
revoke all on function public.update_order_items(text,jsonb,text)
  from public,anon,authenticated;
grant execute on function public.update_order_items(text,jsonb,text)
  to authenticated;
