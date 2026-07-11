# Camerae

MVP iOS para timelapse de baixa luz e captura repetivel.

## Estado atual

- Tela inicial com modulos: `Astrophotography` e `Repeatable`.
- Lista de projetos por modulo.
- Criacao de projeto com nome manual ou titulo automatico baseado em data/hora.
- Preview ao vivo da camera principal traseira (`builtInWideAngleCamera`, 1x).
- Modulo `Repeatable` com overlay do primeiro frame ja capturado no projeto.
- Controle de opacidade da referencia no modulo `Repeatable`.
- Captura `Repeatable` em foco/exposicao/white balance automaticos, com controle simples de EV entre -3 e +3.
- Projetos `Repeatable` possuem lista de timelapses, novo timelapse e exclusao de capturas individuais.
- Cada timelapse `Repeatable` pode gerar um `timelapse.mp4` a partir dos frames capturados.
- Listas de projetos e timelapses exibem thumbnail do primeiro frame disponivel.
- Captura astro salva fotos originais de ate 1s, sem stacking durante a captura.
- Timelapse continuo com intervalometro configuravel de 2s a 10s, contado depois de cada foto salva.
- Countdown de 3s antes da primeira captura para estabilizar o tripe.
- Ao parar o timelapse, o app abre uma tela de processo astro para escolher imagens por stack e FPS.
- O processo astro gera uma sequencia JPEG stackada em `Astro Renders`; a montagem de video ainda sera adicionada.
- Uma pasta por projeto em `Documents/Camerae Projects`.
- Uma pasta por sessao dentro do projeto selecionado.
- Frames originais salvos como JPEG sequencial: `frame_000001.jpg`, `frame_000002.jpg`, etc.
- `manifest.json` por sessao.
- Exportacao ZIP da sessao.
- Firebase configurado para `com.espindola.camerae` com suporte a App Distribution via script local.
- Alinhamento `Repeatable` com modo de contorno da referencia, cores RGB, espessuras fina/media/grossa e blink da referencia.
- O modo blink alterna a referencia em intervalos de 2s, 5s ou 10s, com opacidade de 25%, 50% ou 100%.
- A captura `Repeatable` abre com `Video` como primeira opcao.

## Observacoes

- Os testes no iPhone 15 Pro Max mostraram que todos os formatos publicos do AVFoundation reportam `maxExposureDuration = 1s`.
- O Night Mode de 10s/30s do app Camera da Apple parece ser um pipeline computacional privado, nao uma exposicao unica publica.
- Por isso o app agora segue a rota de stacking explicito.
- O simulador nao testa camera; rode em iPhone fisico.

## Como abrir

Instale os pods e abra `Camerae.xcworkspace` no Xcode:

```sh
pod install
open Camerae.xcworkspace
```

Rode em um iPhone fisico. Se voce regenerar o projeto, use:

```sh
xcodegen generate
pod install
```

Build de CI/local sem assinatura:

```sh
xcodebuild \
  -workspace Camerae.xcworkspace \
  -scheme Camerae \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Distribuicao Firebase para testers:

```sh
scripts/distribute-firebase.sh --groups testers --release-notes "Build de teste"
```

## Modelos locais

Modelos grandes ficam fora do Git. Para ativar DeepSNR no iOS, coloque os arquivos locais aqui:

```text
ios/LocalModels/DeepSNR/DeepSNR_weights_v2.onnx
ios/LocalModels/DeepSNR/LICENSE.txt
ios/LocalModels/DeepSNR/README.txt
```

Essa pasta e ignorada pelo Git, mas e adicionada ao bundle local pelo XcodeGen quando existir.

## Processamento nativo

- ONNX Runtime entra via CocoaPods para o DeepSNR local.
- OpenCV entra via CocoaPods (`OpenCV2`) e fica disponivel para pontes Objective-C++.
- O Laboratorio Astro mostra a versao carregada do OpenCV na secao de tratamento.
