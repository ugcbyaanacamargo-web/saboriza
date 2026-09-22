-- Saboriza production/stock domain. Additive to 20260921030000 baseline.
-- Based on Ruanzinn01/Saboriza-Catalogo commit 2818fbe and src/types/supabase.ts.
-- Preserve existing orders, products, Auth, Storage, settings and IBGE data.
create sequence if not exists public.saboriza_product_code_seq;
alter table public.products
  add column if not exists code text,
  add column if not exists current_stock numeric(18,4) not null default 0 check (current_stock >= 0),
  add column if not exists min_stock numeric(18,4) not null default 0 check (min_stock >= 0),
  add column if not exists max_stock numeric(18,4) not null default 0 check (max_stock >= 0),
  add column if not exists unit_weight_grams numeric(18,4) check (unit_weight_grams > 0),
  add column if not exists target_margin_pct numeric(9,4) not null default 40 check (target_margin_pct between 0 and 100),
  add column if not exists gtin text not null default '',
  add column if not exists brand text not null default '',
  add column if not exists ncm text not null default '';
alter table public.products
  alter column code set default ('PRD-' || lpad(nextval('public.saboriza_product_code_seq')::text,6,'0'));
update public.products set code=default where code is null;
create unique index if not exists saboriza_products_code_unique on public.products(code) where code is not null;

create sequence if not exists public.saboriza_raw_material_code_seq;
create table if not exists public.raw_materials (
  id text primary key default gen_random_uuid()::text,
  code text not null unique default ('INS-' || lpad(nextval('public.saboriza_raw_material_code_seq')::text,6,'0')),
  name text not null check (btrim(name) <> ''),
  description text not null default '',
  category text not null default '',
  control_unit text not null check (control_unit in ('kg','g','L','mL','un')),
  image_url text not null default '',
  purchase_unit_label text not null default '',
  purchase_unit_factor numeric(18,6) not null default 1 check (purchase_unit_factor > 0),
  min_stock numeric(18,6) not null default 0 check (min_stock >= 0),
  max_stock numeric(18,6) not null default 0 check (max_stock >= 0),
  current_stock numeric(18,6) not null default 0 check (current_stock >= 0),
  avg_cost numeric(18,6) not null default 0 check (avg_cost >= 0),
  min_purchase_qty numeric(18,6) not null default 0 check (min_purchase_qty >= 0),
  default_reorder_qty numeric(18,6) not null default 0 check (default_reorder_qty >= 0),
  purchase_multiple numeric(18,6) not null default 0 check (purchase_multiple >= 0),
  lead_time_days integer not null default 0 check (lead_time_days >= 0),
  cost_basis text not null default 'avg_cost' check (cost_basis in ('avg_cost','last_cost','manual')),
  manual_cost numeric(18,6) not null default 0 check (manual_cost >= 0),
  primary_supplier_id text references public.suppliers(id) on delete set null,
  is_active boolean not null default true,
  unit_locked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint raw_materials_manual_cost_required check (cost_basis <> 'manual' or manual_cost > 0)
);
create index if not exists raw_materials_supplier_idx on public.raw_materials(primary_supplier_id);
create index if not exists raw_materials_category_idx on public.raw_materials(category);

create table if not exists public.raw_material_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null check (btrim(name) <> ''),
  created_at timestamptz not null default now()
);
create unique index if not exists raw_material_categories_name_key
  on public.raw_material_categories(lower(btrim(name)));

create table if not exists public.raw_material_entries (
  id text primary key default gen_random_uuid()::text,
  raw_material_id text not null references public.raw_materials(id) on delete restrict,
  supplier_id text not null references public.suppliers(id) on delete restrict,
  status text not null default 'draft' check (status in ('draft','confirmed','reversed')),
  packages_quantity numeric(18,6) not null check (packages_quantity > 0),
  unit_price numeric(18,6) not null check (unit_price >= 0),
  conversion_factor numeric(18,6) check (conversion_factor > 0),
  control_quantity numeric(18,6) check (control_quantity > 0),
  total_value numeric(18,6) check (total_value >= 0),
  batch text not null,
  expiry_date date not null,
  entry_date date not null,
  invoice_number text not null default '',
  invoice_series text not null default '',
  invoice_issue_date date,
  invoice_access_key text not null default '',
  responsible_id uuid references auth.users(id) on delete set null,
  previous_balance numeric(18,6),
  new_balance numeric(18,6),
  previous_avg_cost numeric(18,6),
  new_avg_cost numeric(18,6),
  reversal_reason text,
  reversed_at timestamptz,
  reversed_by uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists raw_material_entries_material_idx
  on public.raw_material_entries(raw_material_id,created_at desc);
create index if not exists raw_material_entries_supplier_idx
  on public.raw_material_entries(supplier_id);

create table if not exists public.product_recipe (
  id text primary key default gen_random_uuid()::text,
  product_id text not null references public.products(id) on delete cascade,
  raw_material_id text not null references public.raw_materials(id) on delete restrict,
  quantity_per_unit numeric(18,6) not null check (quantity_per_unit > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(product_id,raw_material_id)
);
create index if not exists product_recipe_raw_material_idx on public.product_recipe(raw_material_id);

create table if not exists public.production_records (
  id text primary key default gen_random_uuid()::text,
  product_id text not null references public.products(id) on delete restrict,
  packs_quantity integer not null check (packs_quantity > 0),
  units_quantity integer not null check (units_quantity > 0),
  status text not null default 'confirmed' check (status in ('confirmed')),
  responsible_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  confirmed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists production_records_product_idx on public.production_records(product_id,created_at desc);

create table if not exists public.production_consumptions (
  id text primary key default gen_random_uuid()::text,
  production_record_id text not null references public.production_records(id) on delete restrict,
  raw_material_id text not null references public.raw_materials(id) on delete restrict,
  needed_quantity numeric(18,6) not null check (needed_quantity > 0),
  consumed_quantity numeric(18,6) not null check (consumed_quantity > 0),
  previous_balance numeric(18,6) not null check (previous_balance >= 0),
  new_balance numeric(18,6) not null check (new_balance >= 0),
  created_at timestamptz not null default now(),
  unique(production_record_id,raw_material_id)
);
create index if not exists production_consumptions_material_idx
  on public.production_consumptions(raw_material_id);

create table if not exists public.stock_movements (
  id text primary key default gen_random_uuid()::text,
  product_id text not null references public.products(id) on delete restrict,
  variation numeric(18,4) not null,
  origin text not null check (origin in ('production','entry','order','adjustment')),
  reference_id text,
  responsible_id uuid references auth.users(id) on delete set null,
  observation text not null default '',
  previous_balance numeric(18,4) not null check (previous_balance >= 0),
  new_balance numeric(18,4) not null check (new_balance >= 0),
  created_at timestamptz not null default now()
);
create index if not exists stock_movements_product_idx
  on public.stock_movements(product_id,created_at desc);
create unique index if not exists stock_order_once_idx
  on public.stock_movements(reference_id,product_id)
  where origin='order' and reference_id is not null;

create trigger raw_materials_updated before update on public.raw_materials
  for each row execute function public.saboriza_touch_updated_at();
create trigger raw_material_entries_updated before update on public.raw_material_entries
  for each row execute function public.saboriza_touch_updated_at();
create trigger product_recipe_updated before update on public.product_recipe
  for each row execute function public.saboriza_touch_updated_at();
create trigger production_records_updated before update on public.production_records
  for each row execute function public.saboriza_touch_updated_at();

-- Mark unit immutable once a recipe or confirmed entry has consumed its meaning.
create function public.saboriza_material_unit_guard() returns trigger
language plpgsql set search_path='' as $$
begin
  if old.unit_locked and
    (new.control_unit is distinct from old.control_unit or
     new.purchase_unit_factor is distinct from old.purchase_unit_factor) then
    raise exception 'Unidade bloqueada após movimentação ou ficha técnica';
  end if;
  return new;
end $$;
create trigger raw_material_unit_guard before update on public.raw_materials
  for each row execute function public.saboriza_material_unit_guard();
create function public.saboriza_recipe_lock_unit() returns trigger
language plpgsql set search_path='' as $$
begin
  update public.raw_materials set unit_locked=true where id=new.raw_material_id;
  return new;
end $$;
create trigger product_recipe_lock_material after insert on public.product_recipe
  for each row execute function public.saboriza_recipe_lock_unit();

do $$
declare t text;
begin
  foreach t in array array[
    'raw_materials','raw_material_categories','raw_material_entries','product_recipe',
    'production_records','production_consumptions','stock_movements']
  loop
    execute format('alter table public.%I enable row level security',t);
    execute format('create policy saboriza_admin_all on public.%I for all to authenticated using (public.saboriza_is_admin()) with check (public.saboriza_is_admin())',t);
    execute format('revoke all on table public.%I from anon, authenticated',t);
    execute format('grant select on table public.%I to authenticated',t);
  end loop;
end $$;
grant insert,update,delete on public.raw_materials,public.raw_material_categories,
  public.product_recipe to authenticated;
grant insert on public.raw_material_entries to authenticated;
-- Stock and production records are written only by domain RPC / order trigger.
revoke all on function public.saboriza_material_unit_guard() from public,anon,authenticated;
revoke all on function public.saboriza_recipe_lock_unit() from public,anon,authenticated;
