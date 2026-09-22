# Sincronizacao de codigo + banco + deploy Saboriza

**Origem do codigo:** https://github.com/Ruanzinn01/Saboriza-Catalogo
**Destino independente:** https://github.com/ugcbyaanacamargo-web/saboriza
**Banco destino:** Supabase eesafxairdoygzifajgw (`saborizasu`)
**Publicacao destino:** Vercel prj_56lkAIKiIcwPHOXIUFiAFr3MUUDz

## Contrato de release

A atualizacao do codigo NAO basta: toda nova tabela, coluna e funcao deve existir no
nosso Supabase. Nunca execute SQL remoto nao revisado nem substitua os dados da
instalacao original por mocks.

1. A cada hora, `sync-saboriza-upstream.yml` consulta a branch main original e
   prepara um PR. Arquivos proprios (autenticacao, migrations, workflows, chaves)
   sao preservados. O PR NAO faz merge nem executa scripts SQL.
2. `validate-saboriza.yml` testa build e confronta tabelas e RPCs das definicoes
   TypeScript com `supabase/migrations/*.sql`. Se o autor nao versionou a
   criacao de uma tabela, e preciso adicionar no NOSSO repositorio uma migration
   aditiva e revisada; seus arquivos em `scripts/*.sql` nao sao suficientes.
3. APOS aprovacao e merge no main, `release-saboriza.yml` (proposta neste PR)
   valida o codigo, aplica SOMENTE as migrations versionadas no NOSSO banco
   via Supabase CLI, verifica todas as tabelas, colunas, RPCs e RLS reais, e so
   entao publica com Vercel CLI. Um erro bloqueia a publicacao. O site
   atualmente no ar permanece acessivel quando a nova publicacao falha.
4. No `vercel.json` a integracao automatica do Git no branch main sera
   desativada APENAS quando este PR de release for aprovado, porque publicacao
   concorrente do GitHub/Vercel poderia ocorrer antes da migration. Preview
   de outros branches continua habilitado.

## Uma configuracao de seguranca necessaria no GitHub

Antes de fazer merge no PR de release, crie **dois Actions secrets**
no repositorio de destino:

https://github.com/ugcbyaanacamargo-web/saboriza/settings/secrets/actions

- `SUPABASE_DB_URL`: URL PostgreSQL do NOSSO projeto `saborizasu`, com
  senha e SSL, preferencialmente a connection string Session pooler (IPv4).
  Copie no Dashboard Supabase > Connect, nao da conta do desenvolvedor.
- `VERCEL_TOKEN`: token de acesso a NOSSA equipe/projeto na Vercel.
  https://vercel.com/account/tokens

**Nao** coloque essas credenciais no codigo, em issue, PR, mensagem ou variavel
`VITE_*`. Os IDs de projeto/equipe ja estao configurados no workflow.
Depois dos secrets e do merge do PR de release, GitHub Actions e o unico
responsavel pela publicacao da branch main, na ordem banco -> verificacao -> site.
Os valores dos secrets nunca sao visiveis pela integracao GitHub.

## Situacao da atualizacao de 21/09/2026

A proposta original em PR #1 exige **16 tabelas e 8 RPCs** segundo
`src/types/supabase.ts`. A versao anterior do NOSSO banco tinha
**9 tabelas e 2 RPCs**. O autor publico versionou apenas cinco SQLs aditivos
em `scripts/`, sem as migrations-base dos modulos de producao e estoque.
A migracao dessas funcoes precisa ser reconstruida a partir do contrato de codigo,
com transacoes, seguranca RLS e testes de producao; nao se deve inventar funcoes
temporarias ou ligar o frontend novo antes disso.

O codigo-fonte e as migrations **nao sao backups dos dados originais**: produtos,
fotografias, historico de pedidos e credenciais so podem ser migrados do projeto
original com acesso autorizado ao seu banco/Storage/Auth.

Se `SUPABASE_DB_URL` ou `VERCEL_TOKEN` nao estiver configurado, o job falha
ANTES de tocar no banco ou publicar; a branch main fica aguardando a configuracao.
