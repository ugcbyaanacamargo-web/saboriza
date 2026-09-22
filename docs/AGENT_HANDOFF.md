# Saboriza — ponto de entrada para outra conta ou agente

> Documento publico de transferencia tecnica. Fonte de verdade: arquivos da branch `main`
> e estado atual consultado diretamente no Supabase/Vercel. Nao contem secrets,
> clientes, pedidos detalhados, senhas nem copia das fotos.
> Revalidar dados e commits ao iniciar novo atendimento: este arquivo e um mapa,
> nao uma garantia de que o banco e o deploy continuaram inalterados.

## 1. Sistemas e acessos

- Codigo fonte PROPRIO: https://github.com/ugcbyaanacamargo-web/saboriza
- Codigo original do desenvolvedor (somente origem de atualizacoes):
  https://github.com/Ruanzinn01/Saboriza-Catalogo
- Supabase PROPRIO: https://supabase.com/dashboard/project/eesafxairdoygzifajgw
  (projeto `saborizasu`, ref `eesafxairdoygzifajgw`)
- Vercel PROPRIA: https://vercel.com/ugcbyaanacamargo-web/saboriza
- Site: https://saboriza-pied.vercel.app/
- Admin: https://saboriza-pied.vercel.app/admin/login

**Nunca alterar o Supabase/Vercel do desenvolvedor original.**
A conta nova precisa conectar separadamente GitHub, Supabase e Vercel e receber
acesso autorizado aos projetos do proprietario. Conectar o GitHub nao fornece
automaticamente acesso ao Supabase Auth, Storage ou banco privado.

## 2. Ordem de leitura para uma nova sessao

1. Este arquivo: `docs/AGENT_HANDOFF.md`.
2. Fluxo de sincronizacao: `docs/SABORIZA_SYNC.md`.
3. Historico de migracoes: `supabase/migrations/*.sql` (em ordem numerica).
4. Contrato exato de tabelas, colunas e RPCs:
   `src/types/supabase.ts`.
5. Stores/fluxos frontend em `src/store/`, mappers em `src/lib/mappers/`
   e rotas em `src/App.tsx`.
6. Teste de dominio no banco: `supabase/tests/stock_production_smoke.sql`
   (executa transacao e `ROLLBACK`; nao altera registros definitivos).
7. GitHub Actions: `.github/workflows/validate-saboriza.yml`,
   `.github/workflows/sync-saboriza-upstream.yml` e
   `.github/workflows/release-saboriza.yml`.
8. `vercel.json`: a publicacao automatica Git->Production da `main`
   e desativada: o workflow de release aplica migrations, verifica o banco
   e so depois publica via Vercel CLI.

## 3. Inventario tecnico do banco, baseado no contrato de codigo

O esquema da versao de 21/09/2026 tem **16 tabelas**:
`categories`, `coupons`, `customers`, `ibge_cities`, `order_items`,
`orders`, `product_recipe`, `production_consumptions`,
`production_records`, `products`, `raw_material_categories`,
`raw_material_entries`, `raw_materials`, `settings`, `stock_movements`
e `suppliers`.

**8 RPCs para a API:**
`adjust_stock`, `confirm_raw_material_entry`, `create_order`,
`create_production`, `create_stock_entry`,
`rename_raw_material_category`, `reverse_raw_material_entry`
e `update_order_items`.

As relacoes, defaults, constraints, indices, triggers, grants, politicas de RLS
e definicoes completas estao nos SQLs versionados. Nao reconstruir essas regras
somente a partir desta lista ou dos nomes de arquivos.

### Migracoes ja versionadas

- `20260921030000_saboriza_original_compatible_schema.sql`
- `20260921031917_saboriza_order_rpc_secure.sql`
- `20260922011200_saboriza_inventory_schema.sql`
- `20260922011300_saboriza_inventory_rpc.sql`
- `20260922012000_saboriza_admin_sequences.sql`

**Auth:** o frontend exige `app_metadata.saboriza_role = "admin"` para
administracao. RLS deve permanecer habilitada nas tabelas publicas. Nunca
substituir verificacao de `app_metadata` por `user_metadata`.
Nao colocar credenciais reais nem hashes de senhas no codigo.

**Storage:** bucket de imagens `product-images`. As imagens reais NAO sao
exportadas pelos arquivos SQL; verificar acesso aos objetos via Storage API
antes de afirmar que uma migracao inclui fotografias. O codigo publico em
`public/` contem assets versionados, distintos das fotos privadas/
administradas pelo Supabase Storage.

## 4. Publicacao continua: banco ANTES da Vercel

- `sync-saboriza-upstream.yml` consulta o original aproximadamente a cada
  15 minutos (agendamento GitHub pode atrasar). Mudancas de codigo, stores,
  frontend e dependencias que preservam o contrato `src/types/supabase.ts`
  e nao alteram SQL/segredos/configuracoes locais podem ser incorporadas
  automaticamente apos classificacao, testes e build. O workflow inicia
  explicitamente release Supabase -> verificacao -> Vercel por
  `workflow_dispatch`. Mudancas em SQL/contrato do banco ficam em PR,
  aguardando a migration completa e revisao. Nao copia dados do banco original.
- PR com novas tabelas, colunas ou funcoes exige migrations aditivas no
  repositorio proprio, seguindo `src/types/supabase.ts`. Nao fazer merge
  automatico de SQL desconhecido nem copiar `vercel.json` do desenvolvedor.
- `validate-saboriza.yml` valida o contrato versionado e a compilacao.
- `release-saboriza.yml` usa os GitHub Actions Secrets
  **`SUPABASE_DB_URL`** e **`VERCEL_TOKEN`**. NUNCA mostrar seus valores.
  Aplica migrations via Supabase CLI, valida tabelas, colunas, RPCs e RLS,
  executa integracao transacional com `ROLLBACK` e publica via Vercel CLI
  somente se tudo passou. Conferir os workflows atuais no GitHub Actions.

Variaveis de build PUBLICAS na Vercel: `VITE_SUPABASE_URL` e
`VITE_SUPABASE_PUBLISHABLE_KEY` (publishable, NUNCA service_role/secret).
O projeto deve usar Supabase, GitHub e Vercel do MESMO proprietario.

## 5. Como disponibilizar tambem os DADOS reais a outra conta

Este repositorio e PUBLICO: nao subir `data.sql`, backups `.dump`,
dados de clientes/pedidos, emails, documentos fiscais, `auth.users`, secrets,
connection strings, export de Storage privado ou registros identificaveis.

Para **outra conta colaborar no banco atual**, o proprietario deve conceder
acesso ao projeto pela organizacao Supabase (papel minimo adequado), ao repo
GitHub e ao projeto/time Vercel. A nova conta conecta suas proprias integracoes
no ChatGPT. O agente deve comecar com consultas somente de leitura.

Para **migrar/duplicar a base em outro projeto**, manter dois pacotes distintos:

A. Documentacao publica (este repo: migrations, contratos, implementacao,
   workflow, testes e instrucoes).
B. Backup PRIVADO, com controle de acesso, fornecido apenas ao operador
   autorizado: esquema e dados Postgres, configuracao e migracao de Auth quando
   necessaria, objetos reais de Storage e mapa de buckets, verificacao de
   contagens/integridade, sem segredos incluidos em chat/repo publico.

O dump padrao `supabase db dump` exclui esquemas gerenciados `auth` e
`storage`; o dump SQL nao contem bytes das fotos do Storage. Usar os
procedimentos oficiais e revisar dados antes de qualquer restauracao:

- https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore
- https://supabase.com/docs/guides/troubleshooting/migrating-auth-users-between-projects
- https://supabase.com/docs/guides/storage/management/download-objects

Nao rodar `db reset`/restore/overwrite no banco de producao so para ensinar
um agente; **conceder leitura e compartilhar o contrato e preferivel**.
