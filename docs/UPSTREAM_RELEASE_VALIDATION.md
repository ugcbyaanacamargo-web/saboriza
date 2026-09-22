# Atualização do Saboriza original — liberação técnica

Origem: `Ruanzinn01/Saboriza-Catalogo` commit `2818fbe01b50640146be487345acd4d1048f8a51`.
Destino: `ugcbyaanacamargo-web/saboriza`, banco próprio `saborizasu`.

A migração da versão nova foi feita antes de publicar o frontend:
- `20260922011200_saboriza_inventory_schema.sql`: 7 tabelas e novos campos do produto.
- `20260922011300_saboriza_inventory_rpc.sql`: 6 RPCs, validação e estoque de pedidos.
- `20260922012000_saboriza_admin_sequences.sql`: autorização de sequências.
- `supabase/tests/stock_production_smoke.sql`: recebimento, estorno, consumo, insuficiência,
  entradas e ajustes de estoque, baixa de pedidos e idempotência em transação ROLLBACK.
- O pipeline valida tabela/coluna/RPC/RLS e testes no Supabase antes do Vercel CLI.
- `vercel.json` mantém a publicação automática direta da main DESATIVADA; só o workflow publica.

Dados do banco do desenvolvedor original NÃO estão neste GitHub. Produtos, fotos, clientes,
histórico e contas originais não são copiados automaticamente. O banco de destino contém
apenas os registros que já existiam nele e os novos objetos de esquema.
