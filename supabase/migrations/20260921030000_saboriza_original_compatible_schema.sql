-- Saboriza: estrutura compatível com src/types/supabase.ts do projeto original.
-- Nunca contém dados reais, credenciais ou exemplos comerciais.
create extension if not exists pgcrypto;
create type public.order_status as enum ('NEW','IN_REVIEW','CONFIRMED','COMPLETED','CANCELLED');

create sequence public.saboriza_order_seq start 1;

create table public.categories (
  id text primary key default gen_random_uuid()::text,
  name text not null,
  slug text not null unique,
  tagline text not null default '',
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.suppliers (
  id text primary key default gen_random_uuid()::text,
  name text not null,
  company_name text not null,
  trade_name text not null default '',
  cnpj text not null default '',
  ie text not null default '',
  phone text not null,
  email text not null default '',
  address text not null default '',
  neighborhood text not null default '',
  cep text not null default '',
  city text not null default '',
  state text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.products (
  id text primary key default gen_random_uuid()::text,
  name text not null,
  description text not null default '',
  image_url text not null default '',
  category_id text not null references public.categories(id),
  supplier_id text references public.suppliers(id) on delete set null,
  presentation text not null,
  weight_volume text not null,
  unit_price numeric(14,2) not null check (unit_price >= 0),
  pack_quantity integer not null check (pack_quantity > 0),
  packaging_type text not null,
  is_active boolean not null default true,
  badge text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index products_category_idx on public.products(category_id);
create index products_supplier_idx on public.products(supplier_id);

create table public.customers (
  id text primary key default gen_random_uuid()::text,
  name text not null,
  company_name text not null,
  trade_name text not null default '',
  cnpj text not null default '',
  ie text not null default '',
  phone text not null,
  email text not null default '',
  address text not null default '',
  neighborhood text not null default '',
  cep text not null default '',
  city text not null default '',
  state text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.coupons (
  id text primary key default gen_random_uuid()::text,
  code text not null unique,
  discount_type text not null check (discount_type in ('fixed','percentage')),
  discount_value numeric(14,2) not null check (discount_value >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.orders (
  id text primary key default gen_random_uuid()::text,
  order_number text not null unique default ('#' || lpad(nextval('public.saboriza_order_seq')::text, 4,'0')),
  customer_id text references public.customers(id) on delete set null,
  customer_name text not null,
  company_name text not null default '',
  phone text not null,
  customer_trade_name text not null default '',
  customer_cnpj text not null default '',
  customer_ie text not null default '',
  customer_email text not null default '',
  customer_address text not null default '',
  customer_neighborhood text not null default '',
  customer_cep text not null default '',
  customer_city text not null default '',
  customer_state text not null default '',
  payment_terms text not null default '',
  coupon_code text not null default '',
  coupon_type text not null default '',
  coupon_value numeric(14,2) not null default 0,
  discount_amount numeric(14,2) not null default 0,
  subtotal_amount numeric(14,2) not null default 0,
  total_amount numeric(14,2) not null default 0,
  total_units integer not null default 0,
  status public.order_status not null default 'NEW',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index orders_customer_idx on public.orders(customer_id);
create index orders_created_idx on public.orders(created_at desc);

create table public.order_items (
  id text primary key default gen_random_uuid()::text,
  order_id text not null references public.orders(id) on delete cascade,
  product_id text references public.products(id) on delete set null,
  product_name text not null,
  presentation text not null,
  weight_volume text not null,
  unit_price numeric(14,2) not null check (unit_price >= 0),
  pack_quantity integer not null check (pack_quantity > 0),
  packs_quantity integer not null check (packs_quantity > 0),
  total_units integer not null check (total_units > 0),
  total_price numeric(14,2) not null check (total_price >= 0),
  created_at timestamptz not null default now()
);
create index order_items_order_idx on public.order_items(order_id);
create index order_items_product_idx on public.order_items(product_id);

create table public.settings (
  id text primary key default gen_random_uuid()::text,
  factory_name text not null default '',
  whatsapp_number text not null default '',
  whatsapp_display text not null default '',
  business_hours text not null default '',
  legal_name text not null default '',
  fantasy_name text not null default '',
  cnpj text not null default '',
  ie text not null default '',
  hero_image_url text not null default '',
  cnae_code text not null default '',
  cnae_description text not null default '',
  tax_regime text not null default '',
  municipal_registration text not null default '',
  cep text not null default '',
  street text not null default '',
  number text not null default '',
  complement text not null default '',
  neighborhood text not null default '',
  state_code text not null default '',
  state_name text not null default '',
  city_code text not null default '',
  city_name text not null default '',
  ibge_code text not null default '',
  country text not null default '',
  rbt12 numeric(18,2) not null default 0,
  effective_rate numeric(10,4) not null default 0,
  schedule_annex text not null default '',
  reference_competence text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.ibge_cities (
  city_code text primary key,
  city_name text not null,
  state_code text not null,
  state_name text not null
);
create index ibge_cities_state_idx on public.ibge_cities(state_code, city_name);

create function public.saboriza_touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end $$;
do $$
declare t text;
begin
  foreach t in array array['categories','suppliers','products','customers','coupons','orders','settings']
  loop
    execute format(
      'create trigger set_updated_at before update on public.%I for each row execute function public.saboriza_touch_updated_at()',t
    );
  end loop;
end $$;

-- Um login comum não é administrador. O papel só pode ser atribuído no
-- app_metadata por quem controla o Supabase; nunca pelo cadastro público.
create function public.saboriza_is_admin()
returns boolean
language sql stable
set search_path = ''
as $$
  select coalesce((auth.jwt()->'app_metadata'->>'saboriza_role') = 'admin', false)
$$;

do $$
declare t text;
begin
  foreach t in array array['categories','products','suppliers','customers',
                           'coupons','orders','order_items','settings','ibge_cities']
  loop
    execute format('alter table public.%I enable row level security',t);
    execute format(
      'create policy admin_all on public.%I for all to authenticated using (public.saboriza_is_admin()) with check (public.saboriza_is_admin())',t
    );
  end loop;
end $$;

create policy categories_public on public.categories
for select to anon,authenticated using (is_active);
create policy products_public on public.products
for select to anon,authenticated using (is_active);
create policy coupons_public on public.coupons
for select to anon,authenticated using (is_active);
create policy settings_public on public.settings
for select to anon,authenticated using (true);
create policy ibge_cities_public on public.ibge_cities
for select to anon,authenticated using (true);

-- Eliminar permissões herdadas: público nunca lê pedidos/clientes/fornecedores.
revoke all on all tables in schema public from anon, authenticated;
revoke all on sequence public.saboriza_order_seq from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.categories,public.products,public.coupons,
  public.settings,public.ibge_cities to anon, authenticated;
grant select,insert,update,delete on public.categories,public.products,
  public.suppliers,public.customers,public.coupons,public.orders,
  public.order_items,public.settings,public.ibge_cities to authenticated;

-- Protege helpers em vez de deixá-los executáveis por qualquer usuário.
revoke all on function public.saboriza_touch_updated_at() from public,anon,authenticated;
revoke all on function public.saboriza_is_admin() from public,anon;
grant execute on function public.saboriza_is_admin() to authenticated;

-- Fotos públicas para catálogo; envio/alteração somente para administradores.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('product-images','product-images',true,5242880,
  array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do nothing;
create policy saboriza_image_read on storage.objects
for select to anon,authenticated
using (bucket_id='product-images');
create policy saboriza_image_insert on storage.objects
for insert to authenticated
with check (bucket_id='product-images' and public.saboriza_is_admin());
create policy saboriza_image_update on storage.objects
for update to authenticated
using (bucket_id='product-images' and public.saboriza_is_admin())
with check (bucket_id='product-images' and public.saboriza_is_admin());
create policy saboriza_image_delete on storage.objects
for delete to authenticated
using (bucket_id='product-images' and public.saboriza_is_admin());
