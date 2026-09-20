# NuCel — conector para Windows

Este conector mantém uma captura contínua em segundo plano enquanto a tela estiver aberta no NuCel e recebe toques, arrastes e os comandos Voltar, Início e Recentes. Quadros repetidos não são reenviados e os comandos de toque não esperam a próxima captura. Não abre janelas do scrcpy. Esta versão prioriza baixa latência com capturas ADB; ainda não é um stream H.264 de 30/60 fps. Não transmite áudio e não oferece colar texto, transferência de arquivos ou troca de perfil Android nesta versão.

## Preparar

1. Instale Python 3.10 ou superior.
2. Use o ADB que já está no computador ou instale o Android SDK Platform Tools. Conecte os aparelhos via USB, habilite a depuração USB e autorize o computador no celular.
3. Rode `adb devices`. Os aparelhos autorizados devem aparecer com estado `device`. Guarde os números de série.
4. Crie um túnel HTTPS para `http://127.0.0.1:8765`, por exemplo com Cloudflare Tunnel. Para uso diário, configure um hostname estável com um túnel nomeado. Não abra a porta ADB 5555 na internet.
5. No NuCel, em **Conexões → Novo computador**, informe um nome e o endereço HTTPS do túnel.
6. Copie `config.example.json` para `config.json`. Em `secret`, cole a chave mostrada pelo painel. Em `allowed_origin`, coloque o endereço completo do painel NuCel, incluindo `https://`, sem barra final. Em `adb_path`, informe `adb` se já estiver no PATH, ou o caminho completo do adb.exe. No JSON, use barras `/` no caminho Windows, por exemplo `C:/platform-tools/adb.exe`.
7. Execute `iniciar.bat`. Mantenha a janela e o túnel abertos.
8. Cadastre os celulares no painel usando os números de série ADB corretos e selecione o computador correspondente.

## Equipe

Crie primeiro a conta proprietária usando o e-mail configurado como administrador do NuCel. Depois cadastre o nome e o e-mail de cada colaborador, selecione os aparelhos em **Gerenciar acesso** e salve. O colaborador usa esse mesmo e-mail na tela de acesso para criar a própria senha NuCel.

O colaborador só recebe autorização temporária para os números de série liberados. Não compartilhe a chave do conector nem seu config.json. Uma permissão removida expira no conector em até 60 segundos. Se perder a chave antes de configurá-la, crie uma nova conexão no painel.

## Botões

- **Iniciar** abre a transmissão dentro do painel. Pode abrir vários aparelhos.
- **Reiniciar** reinicia a conexão da tela no navegador. Não reinicia o Android nem interfere nos outros aparelhos.
- **Desligar** encerra a visualização e as solicitações de captura daquela tela. O celular continua ligado.
- Toque/click, arraste e os três botões Android são enviados ao aparelho real. Use o teclado na tela do Android para digitar.

## Se não conectar

- Confira se o PC e o túnel estão ligados e se `adb devices` mostra o aparelho como `device`.
- Se aparecer `unauthorized`, aceite a autorização na tela física do celular.
- Confira a chave e o endereço allowed_origin. A chave pertence à conexão cadastrada; não use uma chave de outro computador.
- O endereço HTTPS precisa apontar diretamente para o conector, preservando o cabeçalho Authorization e as requisições OPTIONS. Uma tela extra de login ou bloqueio no túnel impede esta integração direta.
- Capturas ADB podem ser lentas em alguns aparelhos. Comece com um celular, valide os comandos, depois aumente a quantidade. Feche telas que não estiver usando.
- Alguns aplicativos bloqueiam capturas de tela. Isso não é contornado pelo conector.

O conector escuta somente em 127.0.0.1. Todo pedido de tela ou comando exige assinatura HMAC, origem correta, validade e permissão para o aparelho. Os comandos ADB são uma lista fixa; não há terminal remoto. As imagens são temporárias em memória, não são gravadas em disco.

## Referências oficiais

- Android ADB: https://developer.android.com/tools/adb
- Cloudflare Tunnel: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/

## Validação realizada

Código compilado e testes de autenticação, escopo, entrada e captura com ADB simulado. O funcionamento físico, a latência, a orientação da tela e o túnel devem ser validados no computador com os aparelhos reais antes de colocar a equipe para operar.


## Desempenho

Os valores abaixo são opcionais no `config.json`:

```json
{
  "target_fps": 5,
  "frame_width": 420,
  "jpeg_quality": 55
}
```

- `target_fps`: alvo de 1 a 8 capturas por segundo. O limite real depende do aparelho e do ADB.
- `frame_width`: largura enviada ao navegador. 360–480 costuma ser suficiente para a área de trabalho do NuCel.
- `jpeg_quality`: qualidade JPEG de 35 a 80.

Para vários aparelhos abertos ao mesmo tempo, comece em 4–5 FPS. A captura para automaticamente alguns segundos depois de fechar a tela no painel.
