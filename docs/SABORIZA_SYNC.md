# Sincronizacao de codigo + banco + deploy Saboriza

**Origem do codigo:** https://github.com/Ruanzinn01/Saboriza-Catalogo
**Destino independente:** https://github.com/ugcbyaanacamargo-web/saboriza
**Banco destino:** Supabase eesafxairdoygzifajgw (`saborizasu`)
**Publicacao destino:** Vercel prj_56lkAIKiIcwPHOXIUFiAFr3MUUDz

## Contrato de release

A atualizacao do codigo NAO basta: toda nova tabela, coluna e funcao deve existir no
nosso Supabase. Nunca execute SQL remoto nao revisado nem substitua os dados da
instalacao original por mocks.

1. A cada ~15 minutos (com possiveis atrasos do agendador GitHub),
   `sync-saboriza-upstream.yml` consulta a `main` original e prepara um PR.
   Se SOMENTE interface/estilos/assets/metadados mudaram, e npm ci, build
   e contrato SQL passaram, o mesmo workflow faz o merge do PR e dispara
   `release-saboriza.yml` por `workflow_dispatch` (push com GITHUB_TOKEN nao
   dispara outros workflows). Quando mudam tipos/banco, SQL, stores, APIs,
   dependencias ou arquivos fora da lista segura, o PR continua aberto ate
   revisao e eventual migration correspondente. Nao ha merge incondicional.
   Autenticacao, migrations, workflows e chaves locais sao preservados.
2. `validate-saboriza.yml` testa build e confronta tabelas e RPCs das definicoes
   TypeScript com `supabase/migrations/*.sql`. Se o autor nao versionou a
   criacao de uma tabela, e preciso adicionar no NOSSO repositorio uma migration
   aditiva e revisada; seus arquivos em `scripts/*.sql` nao sao suficientes.
3. APOS aprovacao e merge no main, `release-saboriza.yml`
   valida o codigo, aplica SOMENTE as migrations versionadas no NOSSO banco
   via Supabase CLI, verifica todas as tabelas, colunas, RPCs e RLS reais,
   executa testes transacionais com ROLLBACK, e so entao publica com Vercel CLI. Um erro bloqueia a publicacao. O site
   atualmente no ar permanece acessivel quando a nova publicacao falha.
4. No `vercel.json` a integracao automatica do Git no branch main esta
   desativada para evitar publicacao antes da migration. Preview
   de outros branches continua habilitado.

## Secrets e acesso de release

O workflow usa `SUPABASE_DB_URL` e `VERCEL_TOKEN` em GitHub Actions Secrets:
https://github.com/ugcbyaanacamargo-web/saboriza/settings/secrets/actions

A connection string deve apontar SOMENTE para `saborizasu`, e o token para a
equipe/projeto do destino na Vercel. Nunca adicionar valores no repositorio,
em issues, em PRs, em chat ou em variaveis publicas `VITE_*`.

## Atualizacao de 21/09/2026 aplicada

A origem no commit `2818fbe01b50640146be487345acd4d1048f8a51` exige
**16 tabelas e 8 RPCs**. As migrations aditivas para a versao foram aplicadas
ao banco proprio:
- `20260922011200_saboriza_inventory_schema.sql`
- `20260922011300_saboriza_inventory_rpc.sql`
- `20260922012000_saboriza_admin_sequences.sql`

Os testes em `supabase/tests/stock_production_smoke.sql` passaram no banco real:
recebimento, estorno, custo medio, ficha tecnica, producao com falta de
insumo, movimentacao e ajuste de estoque, pedido com falta de estoque e
idempotencia. Tudo em transacao `ROLLBACK`, sem dados ficticios persistidos.

O frontend da origem foi incorporado em PR #1 (merge
`a4bf3eda1b26189a4f866b79bfcf476a647e2338`) e publicado na Vercel.
O GitHub Actions deve continuar sendo a unica rota de deploy `main`.
O script de sincronizacao preserva `vercel.json` e troca as URLs de
metadados no `index.html` para o dominio `saboriza-pied.vercel.app`.

## Limites

O codigo-fonte e as migrations **nao sao backups dos dados originais**: produtos,
fotografias, historico de pedidos e credenciais so podem ser migrados do projeto
original com acesso autorizado ao seu banco/Storage/Auth.

Se `SUPABASE_DB_URL` ou `VERCEL_TOKEN` nao estiver configurado, o job falha
ANTES de tocar no banco ou publicar; a branch main fica aguardando a configuracao.
