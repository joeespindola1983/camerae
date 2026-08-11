# Plano: Canon EOS R via USB no Android

## Objetivo

Determinar com evidência de hardware se um Android pode detectar, controlar e importar imagens de uma Canon EOS R por USB sem computador intermediário.

O MVP termina quando um único fluxo manual consegue disparar a câmera e mostrar no celular a fotografia recém-capturada. Live View, ajustes avançados e integração com projetos Camerae ficam fora da primeira prova.

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

### Fora do escopo

- Live View;
- vídeo;
- foco por toque;
- bulb e intervalômetro;
- alteração de ISO, abertura ou velocidade;
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

### M1 — Descoberta e permissão USB — implementado; aceite físico pendente

Implementar com `UsbManager`:

- enumerar dispositivos já conectados;
- reagir a `USB_DEVICE_ATTACHED` e `USB_DEVICE_DETACHED`;
- solicitar permissão com `PendingIntent` explícito e flags corretas;
- mostrar vendor ID, product ID, nome, configurações, interfaces e endpoints;
- mostrar direção, tipo e tamanho máximo de pacote de cada endpoint;
- manter uma máquina de estados simples: desconectada, encontrada, aguardando permissão, pronta, erro.

Aceite físico: ao conectar a EOS R, o Android oferece abrir o app, solicita permissão e exibe a topologia USB sem crash.

Saída obrigatória: salvar no log o product ID observado da EOS R e a interface que expõe PTP.

### M2 — Sessão PTP e diagnóstico

Primeiro tentar APIs públicas de alto nível:

- abrir a câmera com `MtpDevice`;
- ler `MtpDeviceInfo`;
- listar storages e alguns objetos;
- transferir um JPEG pequeno já existente.

Em paralelo, validar acesso de baixo nível com `UsbDeviceConnection` à interface e aos endpoints bulk/event necessários. Não enviar comandos proprietários nesta fase.

Aceite físico: o app mostra modelo/serial quando disponíveis, lista o cartão e copia uma imagem existente para armazenamento privado do app.

Gate técnico:

- se `MtpDevice` atende leitura e o transporte de baixo nível abre corretamente, seguir com um cliente PTP mínimo;
- se o Android ou a câmera bloquear a sessão necessária, testar uma integração nativa com `libgphoto2` antes de investir em protocolo próprio;
- documentar o erro exato, não apenas “não funcionou”.

### M3 — Captura remota

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

Opção B: integrar `libgphoto2` via NDK se a quantidade de extensões Canon ou a negociação de sessão tornar a opção A desproporcional.

Aceite físico: cinco capturas consecutivas, iniciadas pelo app, resultam em cinco JPEGs válidos no Android sem reconectar o cabo.

### M4 — Fluxo demonstrável

Tela única com:

- estado da conexão;
- identificação da câmera;
- botão `Capturar`;
- progresso de captura/download;
- preview da última foto;
- botão `Compartilhar log`;
- mensagens de recuperação para câmera ocupada, cabo removido e permissão negada.

Aceite: uma pessoa consegue conectar, autorizar, capturar e ver a foto sem usar `adb` ou Android Studio.

### M5 — Relatório e decisão

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

> Trabalhe em `/private/tmp/camerae-eos-r-probe/experiments/eos-r-android-probe`, branch `codex/eos-r-android-probe`. Leia `README.md` e `PLAN.md`. O marco M1 está implementado e compilado, mas depende do teste físico. Analise primeiro o log real da Canon EOS R conectada ao Android. Só depois implemente o marco M2 para leitura PTP/MTP; não avance para comandos proprietários antes de provar a sessão padrão. Preserve o escopo descartável, sem Figma e sem TDD, conforme autorizado para este experimento.
