# Plano: Canon EOS R via USB no Android

## Objetivo

Determinar com evidência de hardware se um Android pode detectar, controlar e importar imagens de uma Canon EOS R por USB sem computador intermediário.

O MVP termina quando um único fluxo manual consegue disparar a câmera e mostrar no celular a fotografia recém-capturada. Live View, ajustes avançados e integração com projetos Camerae ficam fora da primeira prova.

## Direção do produto experimental: Astro Hub

Depois de provar captura e importação, o app temporário evolui para um controlador de sequências astro. O modelo de sequência deverá separar claramente:

- atraso antes de iniciar;
- quantidade de capturas;
- duração da exposição ou velocidade do obturador;
- intervalo entre o início de duas capturas;
- ISO;
- white balance;
- abertura, quando a lente/câmera permitir controle;
- formato de gravação e importação: JPEG, CR3 ou ambos;
- política de download: após cada captura ou ao fim da sequência;
- cancelamento seguro e retomada após erro.

Os valores não serão hardcoded. A interface deverá mostrar somente propriedades, modos e opções que a câmera declarar como suportados e graváveis. Live View continua posterior ao primeiro intervalômetro funcional.

O processamento astro e a geração de MP4 só começam quando captura, eventos e importação forem confiáveis em uma sequência longa. A primeira saída de vídeo poderá usar previews JPEG; RAW/CR3 e alinhamento entram depois.

## Princípios

- Aplicação separada e descartável.
- Uma tela e um fluxo linear.
- Sem Figma, analytics, autenticação, banco de dados ou arquitetura de produto.
- Sem TDD neste experimento; usar checkpoints manuais reproduzíveis.
- Registrar fatos do hardware antes de escolher entre PTP próprio e `libgphoto2`.
- Não copiar código experimental para o Camerae sem revisão e testes adequados.

## Escopo do MVP

### Incluído

- descoberta da EOS R via USB;
- permissão de acesso concedida pelo usuário;
- inventário de configurações, interfaces e endpoints USB;
- abertura e encerramento seguro da conexão;
- leitura de informações PTP da câmera;
- listagem e download de uma imagem existente;
- captura remota de uma fotografia;
- identificação e download da nova imagem;
- visualização do JPEG;
- preservação opcional do CR3;
- exportação de log técnico copiável/compartilhável.

### Fora do primeiro fluxo de captura, mas previstos depois

- Live View;
- vídeo;
- foco por toque;
- bulb avançado;
- sequências longas e retomada;
- alteração de ISO, abertura ou velocidade antes da câmera declarar capacidades;
- processamento RAW;
- importação para projetos Camerae;
- operação em segundo plano;
- suporte genérico a outras câmeras;
- publicação na Play Store.

## Marcos

### M0 — Bootstrap compilável — concluído

Entregas:

- projeto Gradle independente;
- manifesto com `android.hardware.usb.host`;
- filtro USB do vendor Canon `0x04A9`;
- tela placeholder;
- build debug instalável.

Aceite: `./gradlew assembleDebug` terminou com sucesso em 11 de agosto de 2026 e gerou `app/build/outputs/apk/debug/app-debug.apk`.

### M1 — Descoberta e permissão USB — concluído e validado fisicamente

Implementar com `UsbManager`:

- enumerar dispositivos já conectados;
- reagir a `USB_DEVICE_ATTACHED` e `USB_DEVICE_DETACHED`;
- solicitar permissão com `PendingIntent` explícito e flags corretas;
- mostrar vendor ID, product ID, nome, configurações, interfaces e endpoints;
- mostrar direção, tipo e tamanho máximo de pacote de cada endpoint;
- manter uma máquina de estados simples: desconectada, encontrada, aguardando permissão, pronta, erro.

Aceite físico: ao conectar a EOS R, o Android oferece abrir o app, solicita permissão e exibe a topologia USB sem crash.

Saída obrigatória: salvar no log o product ID observado da EOS R e a interface que expõe PTP.

### M2 — Sessão PTP e diagnóstico — concluído e validado fisicamente

Primeiro tentar APIs públicas de alto nível:

- abrir a câmera com `MtpDevice`;
- ler `MtpDeviceInfo`;
- listar storages e alguns objetos;
- transferir um JPEG pequeno já existente.

Em paralelo, validar acesso de baixo nível com `UsbDeviceConnection` à interface e aos endpoints bulk/event necessários. Não enviar comandos proprietários nesta fase.

Aceite físico: o app identificou a Canon EOS R, listou o cartão e copiou integralmente um CR3 de 32.312.487 bytes para o armazenamento privado do app em aproximadamente 2,2 segundos.

Gate técnico:

- se `MtpDevice` atende leitura e o transporte de baixo nível abre corretamente, seguir com um cliente PTP mínimo;
- se o Android ou a câmera bloquear a sessão necessária, testar uma integração nativa com `libgphoto2` antes de investir em protocolo próprio;
- documentar o erro exato, não apenas “não funcionou”.

### M3 — Captura remota — fluxo único validado fisicamente

Opção A, preferida após M2: cliente PTP mínimo com somente as operações requeridas pela EOS R.

- montar e validar containers PTP little-endian;
- controlar `transactionId` e `sessionId`;
- abrir sessão;
- consultar operações e propriedades suportadas;
- ativar o modo de captura remota Canon, se exigido;
- enviar captura;
- consumir eventos até identificar o novo objeto;
- baixar a imagem;
- fechar sessão em `finally` e em detach.

O APK `0.3.0` comprovou no hardware containers little-endian, sessão/transações, `EOS_SetRemoteMode`, `EOS_SetEventMode`, consumo limitado de `EOS_GetEvent` e a sequência segura de `EOS_RemoteReleaseOn/Off`. O disparo criou `5S8A9566.CR3`; o inventário seguinte encontrou o novo handle e importou integralmente 40.307.117 bytes.

O APK `0.4.0` reuniu o fluxo em um toque, mas o teste físico encontrou uma corrida na troca MTP → PTP. O APK `0.4.1` conseguiu concluir uma captura e importar `5S8A9568.CR3` com 40.316.045 bytes exatos, porém só depois de duas falhas de abertura PTP e reconexões físicas; atraso fixo não é confiável.

O APK `0.4.2` removeu a transição causadora e comprovou sessões PTP estáveis. O teste mostrou que a EOS R emite `0xC1A7 ObjectAddedEx64` cerca de 3,5 s depois do disparo, não o `0xC181 ObjectAddedEx` inicialmente decodificado. O APK `0.4.3` aceita ambas as estruturas com offsets e limites próprios antes de importar o handle exato via MTP. O reteste e as cinco repetições do aceite ainda estão pendentes.

O APK `0.4.4` fechou o fluxo: recebeu `ObjectAddedEx64` em 3,021 s, abriu MTP uma vez e importou `5S8A9571.CR3` com os 40.415.295 bytes declarados tanto pelo evento quanto pelo MTP.

Opção B: integrar `libgphoto2` via NDK se a quantidade de extensões Canon ou a negociação de sessão tornar a opção A desproporcional.

Aceite físico: cinco capturas consecutivas, iniciadas pelo app, resultam em cinco JPEGs válidos no Android sem reconectar o cabo.

Antes da captura sequencial, registrar descritores e valores atuais de ISO, white balance, abertura, velocidade e modo de exposição. Só habilitar escrita para propriedades que a EOS R confirmar como configuráveis na sessão remota.

### M4 — Sequência astro mínima — interface inicial implementada; aceite pendente

Depois do aceite do M3, implementar:

- quantidade de fotos;
- intervalo entre capturas;
- velocidade/duração de exposição suportada;
- ISO e white balance suportados;
- iniciar, acompanhar e cancelar sequência;
- download após cada captura;
- contadores de planejadas, capturadas, baixadas e falhas;
- proteção contra iniciar nova exposição enquanto a anterior ainda está ocupada ou transferindo.

Aceite: executar uma sequência de 20 capturas com cadência definida, baixar todos os arquivos e produzir um manifesto local que associe ordem, horário, parâmetros, handle PTP e arquivo importado.

O APK `0.5.0` entregou o primeiro subconjunto funcional: quantidade, atraso inicial, intervalo entre inícios, progresso, cancelamento seguro entre operações e download de cada captura. A sequência é estritamente serial. O APK `0.5.2` completou fisicamente 5/5 capturas e downloads com cadência de 10 segundos. O APK `0.6.0` acrescenta um manifesto JSON atômico por sequência e descoberta somente leitura dos valores atuais e listas disponíveis de ISO, white balance e shutter; escrita de propriedades continua pendente até confirmação física dessas capabilities.

O primeiro teste começou 3,9 s após o attach e falhou antes de `OpenSession`, enquanto o teste único anterior começou após 10,3 s e funcionou. Outro log mostrou que a resposta atrasada dessa falha permaneceu na fila bulk IN e deslocou as transações da tentativa seguinte (`0` quando se esperava `1`, depois `1` quando se esperava `2`). O APK `0.5.2` combina o handshake PTP padrão `GetDeviceInfo` com retry limitado, drenagem prévia da fila e descarte limitado de containers pertencentes a transações antigas. Captura fica em allowlist para `04A9:32DA`; outras Canon podem usar importação MTP, mas não recebem comandos proprietários sem perfil validado.

### M5 — Fluxo demonstrável

Tela única com:

- estado da conexão;
- identificação da câmera;
- botão `Capturar`;
- progresso de captura/download;
- preview da última foto;
- botão `Compartilhar log`;
- mensagens de recuperação para câmera ocupada, cabo removido e permissão negada.

Aceite: uma pessoa consegue conectar, autorizar, capturar e ver a foto sem usar `adb` ou Android Studio.

### M6 — Relatório e decisão

Produzir `RESULTS.md` contendo:

- telefone e versão do Android;
- firmware da EOS R;
- cabo/adaptador usado;
- topologia e identificadores USB;
- abordagem implementada;
- latência do toque até captura e do disparo até preview;
- funcionamento de JPEG e CR3;
- consumo ou instabilidade observados;
- limitações;
- recomendação: integrar, continuar experimento ou encerrar.

## Estrutura sugerida depois de M1

```text
app/src/main/java/com/camerae/eosrprobe/
  MainActivity.java
  usb/
    UsbCameraDiscovery.java
    UsbPermissionController.java
    UsbTopologyFormatter.java
  ptp/
    PtpContainer.java
    PtpSession.java
    PtpTransport.java
    CanonEosCommands.java
  transfer/
    CapturedObjectDownloader.java
  diagnostics/
    ProbeLog.java
```

Manter Java no bootstrap evita adicionar dependências. Kotlin pode ser adotado antes de M1 se o responsável preferir, desde que o protótipo continue pequeno.

## Riscos e respostas

| Risco | Evidência/efeito | Resposta |
| --- | --- | --- |
| Cabo apenas de carga | câmera não aparece | testar cabo de dados conhecido |
| Android sem USB Host real | `UsbManager` não enumera | confirmar OTG e testar outro aparelho/adaptador |
| Alimentação USB instável | detach durante operação | hub OTG alimentado ou bateria cheia |
| `MtpDevice` monopoliza interface | baixo nível não abre | fechar MTP antes de reivindicar interface |
| Extensões Canon complexas | captura falha apesar de leitura funcionar | adotar `libgphoto2` via NDK |
| RAW grande/lento | timeout ou memória alta | download em stream/arquivo, nunca em um único buffer |
| Câmera ocupada | respostas PTP de busy | retry limitado e mensagem explícita |
| App perde conexão | handles inválidos após detach | estado único da sessão e limpeza idempotente |

## Checklist do primeiro teste

1. Instalar o APK debug.
2. Fechar Camera Connect e desativar Wi-Fi da EOS R.
3. Inserir cartão com pelo menos um JPEG conhecido.
4. Ligar a câmera em modo de fotografia.
5. Conectar o cabo de dados ao Android.
6. Aceitar a abertura do app e a permissão USB.
7. Copiar o log completo de topologia.
8. Desconectar e repetir uma vez para verificar limpeza.
9. Só então iniciar a sessão MTP/PTP.

## Prompt de handoff para o próximo modelo

> Trabalhe em `/private/tmp/camerae-eos-r-probe/experiments/eos-r-android-probe`, branch `codex/eos-r-android-probe`. Leia `README.md`, `PLAN.md` e `COMPATIBILITY.md`. M1, M2, M3 e uma sequência M4 de cinco fotos foram validados fisicamente. O APK `0.6.0` preserva a ressincronização PTP do `0.5.2`, cria manifesto JSON por sequência e descobre ISO, white balance e shutter somente por leitura. Aguarde o log físico das capabilities e do manifesto antes de habilitar escrita de propriedades. Captura permanece restrita ao perfil EOS R `04A9:32DA`. Preserve o escopo descartável, sem Figma e sem TDD, conforme autorizado para este experimento.
