# NuCel — Nuvix

Painel web privado para visualizar e controlar vários celulares Android conectados a computadores da operação.

## Arquitetura

- **Frontend + API:** Next.js 16 executando em Cloudflare Workers via OpenNext.
- **Banco e autenticação:** Supabase (Postgres + Auth).
- **Código:** GitHub como fonte oficial.
- **CI/CD:** GitHub → Cloudflare Workers Builds. Pushes na branch `main` geram novos deploys.
- **Aparelhos:** conector Python/ADB rodando no Windows da operação, exposto somente por um túnel HTTPS.

O administrador cadastra computadores, aparelhos e colaboradores. Cada colaborador cria a própria conta NuCel com o e-mail previamente liberado e só recebe os aparelhos vinculados a ele.

## Configuração do Supabase

O projeto Supabase dedicado ao NuCel usa as migrations em `supabase/migrations/`.

Configure estas variáveis no Worker:

```env
SUPABASE_URL=https://SEU-PROJETO.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
SUPABASE_SECRET_KEY=sb_secret_...
NUCEL_OWNER_EMAIL=seu-email@exemplo.com
```

`SUPABASE_SECRET_KEY` deve ser criada como **Secret** no Cloudflare. Ela nunca deve ser colocada no GitHub.

O primeiro usuário que criar uma conta usando `NUCEL_OWNER_EMAIL` vira administrador. Outros e-mails só conseguem criar conta depois de serem cadastrados na aba **Colaboradores**.

## Deploy no Cloudflare

O NuCel usa **Cloudflare Workers**, não Pages estático, porque possui autenticação e rotas de API.

1. Mantenha o repositório privado no GitHub.
2. No Cloudflare, abra **Workers & Pages → Create application → Import a repository**.
3. Selecione `FelipPitanga/NuCel`.
4. Use a branch de produção `main`.
5. Build command: `npx opennextjs-cloudflare build`.
6. Deploy command: `npx opennextjs-cloudflare deploy`.
7. Em **Settings → Variables & Secrets**, cadastre:
   - `SUPABASE_URL` — variável;
   - `SUPABASE_PUBLISHABLE_KEY` — variável;
   - `SUPABASE_SECRET_KEY` — **secret**;
   - `NUCEL_OWNER_EMAIL` — variável.
8. Faça o primeiro deploy e use a URL `https://nucel.<seu-subdominio>.workers.dev` ou um domínio próprio.
9. Coloque essa URL final no `allowed_origin` do conector NuCel.

Depois disso, cada push na `main` dispara automaticamente um novo build/deploy no Cloudflare.

## Arquivos Cloudflare

- `wrangler.jsonc` — configuração do Worker.
- `open-next.config.ts` — adaptação Next.js → Cloudflare Workers.
- `.dev.vars.example` — exemplo de variáveis para preview local.
- `npm run preview` — build e preview no runtime local do Cloudflare.
- `npm run deploy` — build e deploy manual pelo Wrangler/OpenNext.

## Conector Windows

O conector fica em `connector/`. Veja `connector/LEIA-ME.md`.

Ele:

- captura a tela via ADB;
- permite toque, arraste, voltar, início e recentes;
- valida assinatura HMAC, origem, validade e lista de seriais permitidos;
- não expõe terminal remoto;
- não grava capturas no banco.

## Segurança

As tabelas NuCel ficam com RLS habilitado e sem permissão direta para `anon`/`authenticated`. O navegador conversa somente com as rotas `/api/*` do NuCel. O servidor valida a sessão e a função do usuário antes de acessar o banco com a chave secreta.

A chave secreta do conector nunca é enviada aos colaboradores; eles recebem tokens HMAC temporários limitados aos aparelhos liberados.

## Desenvolvimento local

```bash
npm install
npm run dev
```

Copie `.env.example` para `.env.local` no desenvolvimento Next.js. Para testar diretamente no runtime do Cloudflare, copie `.dev.vars.example` para `.dev.vars` e rode:

```bash
npm run preview
```

## Teste físico

O conector possui testes simulados em `tests/test_connector.py`, mas a fluidez e a compatibilidade precisam ser validadas com os aparelhos físicos e o túnel real antes de colocar a equipe inteira em operação.
