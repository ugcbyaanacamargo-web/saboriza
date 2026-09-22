-- Admin REST inserts of orders require nextval on the order-number sequence.
-- Existing baseline intentionally revoked it from authenticated; the new admin
-- order/stock smoke test found that missing privilege.
grant usage on sequence public.saboriza_order_seq to authenticated;
grant usage on sequence public.saboriza_product_code_seq to authenticated;
grant usage on sequence public.saboriza_raw_material_code_seq to authenticated;