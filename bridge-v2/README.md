# NuCel Bridge v2 — laboratório

Esta pasta existe para validar a camada de streaming antes de integrá-la ao painel NuCel.

## Objetivo

Testar um aparelho Android com uma implementação scrcpy-web madura, sem Supabase, sem dashboard NuCel e sem nosso player artesanal.

Motor de laboratório fixado em:

- Projeto: `bilbospocketses/ws-scrcpy-web`
- Commit: `8fd486cfaf9ab69dc6b97237053979bc1f141b05`
- Porta local: `8000`

O motor usa ADB + scrcpy-server vanilla no PC, WebSocket para transporte e WebCodecs no navegador.

## Teste A — LOCAL primeiro

1. Feche o `iniciar.bat` do Agent Python antigo. Ele não participa deste teste.
2. O Cloudflare Tunnel antigo pode ficar fechado neste primeiro teste.
3. Execute `01_INICIAR_LOCAL.cmd`.
4. Na primeira execução o script clona o motor, instala dependências e compila. Pode demorar alguns minutos.
5. Abra `http://127.0.0.1:8000` no Chrome.
6. Selecione o aparelho `0059410259`.
7. Abra o stream e teste por 1 minuto:
   - Home;
   - voltar;
   - abrir WhatsApp;
   - rolar uma conversa;
   - trocar de aplicativo;
   - arrastar rapidamente.

### Critério

Se LOCAL estiver fluido, a camada scrcpy/WebCodecs está validada e qualquer atraso remoto restante é rede/túnel.

Se LOCAL travar, não mexeremos no Cloudflare: investigaremos PC/ADB/encoder/aparelho.

## Teste B — REMOTO pelo Cloudflare

Só faça depois do teste local ficar bom.

1. Deixe `01_INICIAR_LOCAL.cmd` aberto.
2. Execute `02_INICIAR_TUNEL.cmd`.
3. O Cloudflare mostrará uma URL `https://....trycloudflare.com`.
4. Abra essa URL em outro navegador/máquina e repita o teste.

O HTTPS do Cloudflare é importante porque WebCodecs e recursos modernos do navegador funcionam em contexto seguro quando acessados remotamente.

## Segurança do laboratório

O Quick Tunnel é temporário e serve somente para teste. Não use a URL como endpoint definitivo do NuCel. Depois da validação, o Bridge v2 receberá autenticação/token NuCel e um túnel nomeado estável.

## Próxima etapa após aprovação

Depois que LOCAL e REMOTO estiverem fluidos:

1. encapsular o motor no NuCel Bridge;
2. validar token de 60 s emitido pelo Worker;
3. restringir serial por colaborador;
4. esconder a interface do motor;
5. embutir somente o player/controle dentro do card do NuCel;
6. iniciar o scrcpy apenas quando o usuário clicar em **Iniciar**;
7. encerrar a sessão quando a tela for fechada.
