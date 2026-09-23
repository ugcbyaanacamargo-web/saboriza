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

## Atualizacao Separa Confere (origem `c028508a`)

A origem incluiu a fila de separacao, conferencia por item e solicitacoes de
ajuste. A instalacao propria aplica a migracao aditiva
`20260923015800_saboriza_separation_domain.sql` antes de publicar o frontend:
agora 17 tabelas e 8 RPCs. Ha uma tabela de ajustes, seis colunas de
separacao em `orders`, `separated_at` em `order_items`, RLS, FK,
validacoes no banco e Realtime dos pedidos.

`supabase/tests/separation_smoke.sql` foi executado em transacao que
termina com `ROLLBACK` no banco proprio; testa o bloqueio de
conclusao com itens/ajustes pendentes, o registro de resolucao,
a baixa unica de estoque e acesso nao administrativo.
O release concluiu com sucesso em
https://github.com/ugcbyaanacamargo-web/saboriza/actions/runs/35809071426
e a Vercel indicou `READY` para Production no
commit `da97718147de2d9667f211e036140d6f185c5f10`.

O dominio oficial atual e https://oris360.vercel.app/.
Nao ha copia de dados comerciais do desenvolvedor.
