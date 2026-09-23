-- Separation / checking domain required by Ruanzinn01/Saboriza-Catalogo
-- commit c028508a395f4dc0ec104999fad94c6c5c67802b.
-- Additive: preserve existing orders, order items, Auth and all commercial data.
alter table public.orders
  add column if not exists separation_queued_at timestamptz,
  add column if not exists separation_started_at timestamptz,
  add column if not exists separation_finished_at timestamptz,
  add column if not exists separation_responsible text,
  add column if not exists separation_started_by text,
  add column if not exists separation_completed_by text;

alter table public.order_items
  add column if not exists separated_at timestamptz;

create table if not exists public.order_adjustment_requests (
  id text primary key default gen_random_uuid()::text,
  order_id text not null references public.orders(id) on delete cascade,
  order_item_id text references public.order_items(id) on delete set null,
  message text not null check (length(btrim(message)) between 1 and 2000),
  status text not null default 'pending' check (status in ('pending','resolved')),
  created_by text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by text,
  constraint adjustment_resolution_consistency check (
    (status='pending' and resolved_at is null and resolved_by is null)
    or (status='resolved' and resolved_at is not null)
  )
);
create index if not exists order_adjustments_order_status_idx
  on public.order_adjustment_requests(order_id,status,created_at desc);
create index if not exists order_adjustments_item_idx
  on public.order_adjustment_requests(order_item_id)
  where order_item_id is not null;
create unique index if not exists order_adjustments_one_pending_per_item
  on public.order_adjustment_requests(order_item_id)
  where order_item_id is not null and status='pending';

alter table public.order_adjustment_requests enable row level security;
revoke all on public.order_adjustment_requests from anon,authenticated;
grant select,insert,update,delete on public.order_adjustment_requests to authenticated;
create policy savoriza_adjustment_admin on public.order_adjustment_requests
  for all to authenticated
  using (public.saboriza_is_admin())
  with check (public.saboriza_is_admin());

-- Verify that requests refer to the same order as the selected item.
-- Resolving a request records an actual server-side timestamp.
create function public.saboriza_separation_request_guard() returns trigger
language plpgsql security invoker set search_path='' as $$
declare parent_status public.order_status;
        verify_reference boolean := (tg_op='INSERT');
begin
  if tg_op='UPDATE' then
    if old.status='resolved' and new.status='pending' then
      raise exception 'Uma solicitação resolvida não pode voltar a pendente';
    end if;
    verify_reference := (new.order_id is distinct from old.order_id or
                         new.order_item_id is distinct from old.order_item_id);
  end if;
  if verify_reference then
    select status into parent_status from public.orders where id=new.order_id for update;
    if not found or parent_status<>'CONFIRMED' then
      raise exception 'Ajustes exigem um pedido confirmado';
    end if;
    if new.order_item_id is not null and not exists (
      select 1 from public.order_items
      where id=new.order_item_id and order_id=new.order_id
    ) then
      raise exception 'O item não pertence ao pedido informado';
    end if;
  end if;
  if new.status='resolved' then
    new.resolved_at:=coalesce(new.resolved_at,now());
  end if;
  return new;
end $$;
create trigger saboriza_separation_request_guard
before insert or update on public.order_adjustment_requests
for each row execute function public.saboriza_separation_request_guard();

-- A client-side check is not sufficient: concurrent requests must not allow
-- completing an order with missing items or unresolved adjustment requests.
-- Preserve the existing legacy admin "complete order" path if separation
-- was never started, including the existing stock-decrement trigger.
create function public.saboriza_separation_order_guard() returns trigger
language plpgsql security invoker set search_path='' as $
declare newly_queued boolean := (tg_op='INSERT');
begin
  if tg_op='UPDATE' then
    newly_queued := old.status is distinct from new.status;
  end if;
  if new.status='CONFIRMED' and newly_queued
     and new.separation_queued_at is null then
    new.separation_queued_at:=now();
  end if;
  if tg_op='UPDATE' then
   if new.status='COMPLETED' and old.status is distinct from new.status then
    if exists (
      select 1 from public.order_adjustment_requests
      where order_id=new.id and status='pending'
    ) then
      raise exception 'Existe ajuste pendente para esse pedido';
    end if;
    if new.separation_started_at is not null then
      if not exists(select 1 from public.order_items where order_id=new.id)
         or exists(
           select 1 from public.order_items
           where order_id=new.id and separated_at is null
         ) then
        raise exception 'Ainda existem itens pendentes de separação';
      end if;
      new.separation_finished_at:=coalesce(new.separation_finished_at,now());
    end if;
   end if;
  end if;
  return new;
end $$;
create trigger saboriza_separation_order_guard
before insert or update on public.orders
for each row execute function public.saboriza_separation_order_guard();

create function public.saboriza_separated_item_guard() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if new.separated_at is distinct from old.separated_at
     and not exists (
       select 1 from public.orders
       where id=new.order_id and status='CONFIRMED'
       for update
     ) then
    raise exception 'Separação só pode ser alterada em pedido confirmado';
  end if;
  return new;
end $$;
create trigger saboriza_separated_item_guard
before update of separated_at on public.order_items
for each row execute function public.saboriza_separated_item_guard();

revoke all on function public.saboriza_separation_request_guard()
  from public,anon,authenticated;
revoke all on function public.saboriza_separation_order_guard()
  from public,anon,authenticated;
revoke all on function public.saboriza_separated_item_guard()
  from public,anon,authenticated;

-- Realtime for the new queue: only logged-in administrators can SELECT orders
-- under the existing RLS policy. Do not send changes on public order items.
do $$
begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime')
    and not exists(
       select 1 from pg_publication_tables
       where pubname='supabase_realtime'
         and schemaname='public' and tablename='orders'
    ) then
   alter publication supabase_realtime add table public.orders;
 end if;
end $$;
