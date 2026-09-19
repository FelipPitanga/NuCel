# NuCel — Nuvix

Painel web privado para visualizar e controlar vários celulares Android conectados a computadores da operação.

## Arquitetura

- **Frontend + API:** Next.js 16, pronto para deploy na Vercel.
- **Banco e autenticação:** Supabase (Postgres + Auth).
- **Código:** GitHub como fonte oficial. O fluxo recomendado é GitHub → Vercel, com deploy automático a cada push na branch principal.
- **Aparelhos:** conector Python/ADB rodando no Windows da operação, exposto somente por um túnel HTTPS.

O administrador cadastra computadores, aparelhos e colaboradores. Cada colaborador cria a própria conta NuCel com o e-mail previamente liberado e só recebe os aparelhos vinculados a ele.

## Configuração do Supabase

Crie um projeto Supabase dedicado ao NuCel e aplique `supabase/migrations/001_nucel_initial.sql` e `002_nucel_grants_device_index.sql`.

Depois configure no ambiente do deploy:

```env
SUPABASE_URL=https://SEU-PROJETO.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
SUPABASE_SECRET_KEY=sb_secret_...
NUCEL_OWNER_EMAIL=seu-email@exemplo.com
```

`SUPABASE_SECRET_KEY` é somente de servidor e nunca deve usar prefixo `NEXT_PUBLIC_`.

O primeiro usuário que criar uma conta usando `NUCEL_OWNER_EMAIL` vira administrador. Outros e-mails só conseguem criar conta depois de serem cadastrados na aba **Colaboradores**.

## Deploy recomendado

1. Repositório privado no GitHub.
2. Importar o repositório na Vercel.
3. Adicionar as quatro variáveis de ambiente acima.
4. Fazer o primeiro deploy.
5. Usar a URL de produção da Vercel no `allowed_origin` do conector NuCel.

Depois disso, alterações no GitHub são publicadas automaticamente pela Vercel.

## Conector Windows

O pacote para o computador fica em `public/nucel-conector.zip`. Veja também `connector/LEIA-ME.md`.

Ele:

- captura a tela via ADB;
- permite toque, arraste, voltar, início e recentes;
- valida assinatura HMAC, origem, validade e lista de seriais permitidos;
- não expõe terminal remoto;
- não grava capturas no banco.

## Segurança

As tabelas NuCel ficam com RLS habilitado e sem permissão direta para `anon`/`authenticated`. O navegador conversa somente com as rotas `/api/*` do NuCel. O servidor valida a sessão e a função do usuário antes de acessar o banco com a chave secreta.

A chave secreta do conector também nunca é enviada aos colaboradores; eles recebem apenas tokens HMAC temporários de 60 segundos limitados aos aparelhos liberados.

## Desenvolvimento local

```bash
npm install
npm run dev
```

Copie `.env.example` para `.env.local` e preencha as variáveis antes de iniciar.

## Teste físico

O conector possui testes simulados em `tests/test_connector.py`, mas a fluidez e a compatibilidade precisam ser validadas com os aparelhos físicos e o túnel real antes de colocar a equipe inteira em operação.
