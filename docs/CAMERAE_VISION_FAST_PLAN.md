# Camerae Vision — plano curto para modularizacao e avaliacao durante captura

Status: pronto para execucao em fatias pequenas

Escopo desta rodada: **desktop e C++ apenas**

Objetivo: retirar OpenCV de qualquer associacao exclusiva com Astro/Timelapse e criar um nucleo compartilhado, com um avaliador opcional e barato da qualidade de alinhamento durante uma captura simulada.

## 1. Decisoes fixas

1. O modulo se chamara **Camerae Vision**. OpenCV e o backend inicial, nao o nome do dominio.
2. Astro, Repeatable, Timelapse e futuros modulos podem depender de Camerae Vision; Camerae Vision nunca depende deles.
3. Esta rodada nao altera iOS, Android, camera ao vivo, CocoaPods ou Gradle.
4. O alinhamento final e a avaliacao rapida sao capacidades diferentes, embora compartilhem tipos e metricas.
5. O avaliador rapido e opcional e nunca roda na thread de captura.
6. Frames podem ser descartados. A captura nunca espera o avaliador.
7. ECC, SIFT, fluxo optico, malha local, deghosting e full resolution ficam desligados no caminho rapido.
8. Cada fase termina com testes verdes antes da proxima. Nao juntar fases em um unico patch.

## 2. Arquitetura-alvo minima

```text
Astro / Repeatable / Timelapse / futuros modulos
                      │
                      ▼
              Camerae Vision API
                ├── Alignment
                ├── Alignment Quality
                └── Diagnostics
                      │
                      ▼
                OpenCV backend
```

Estrutura proposta:

```text
vision/
  CMakeLists.txt
  README.md
  include/camerae_vision/
    alignment.hpp
    alignment_quality.hpp
  src/opencv/
    alignment.cpp
    alignment_quality.cpp
  tests/
    alignment_tests.cpp
    alignment_quality_tests.cpp
  tools/
    alignment_lab.cpp
    capture_quality_simulator.cpp

processing/
  CMakeLists.txt
  src/astro_processor.cpp
```

Direcao de dependencias:

```text
processing ───────► camerae_vision ───────► OpenCV
desktop tools ────► camerae_vision
camerae_vision não conhece processing
```

No primeiro refactor, `cv::Mat` pode continuar na API C++ interna para preservar comportamento. Nao criar agora uma abstracao generica de pixels nem um sistema de plugins.

## 3. Capacidades separadas

### 3.1 Alinhamento de qualidade final

- Detectores: ORB, AKAZE e SIFT.
- Modelos: translacao, similaridade, afim e homografia.
- Mutual matching, CLAHE, RANSAC e ECC configuraveis.
- Warp, mascara valida, overlay, heatmap e red/cyan.
- Pode usar resolucao maior e executar sob demanda.

### 3.2 Avaliador rapido de captura

Preset inicial `captureFast`:

| Controle | Valor inicial |
| --- | --- |
| Maior dimensao | 640 px |
| Detector | ORB |
| Maximo de features | 1200 |
| Modelos | similaridade e afim |
| Mutual matching | ligado |
| CLAHE | desligado |
| ECC | desligado |
| Frequencia simulada | 2 analises/s |
| Backpressure | manter somente o frame mais recente |

Saida minima:

```cpp
struct CaptureAlignmentQuality {
    AlignmentDecision decision; // accept, review, reject
    double score;
    double overlapRatio;
    double reprojectionRMSE;
    double edgeAlignmentError;
    double estimatedLatencyMilliseconds;
    AlignmentMotionModel selectedModel;
    std::vector<std::string> reasons;
};
```

Esse resultado informa se a captura esta dentro de uma faixa corrigivel. Ele nao produz o arquivo final e nao aplica filtros na foto capturada.

## 4. Regras para nao prejudicar a captura

- Entrada sempre reduzida; nunca decodificar HEIC full resolution no loop rapido.
- No maximo uma analise em andamento e um frame pendente.
- Se chegar um frame novo, substituir o pendente antigo.
- Resultado antigo recebe timestamp e nao deve orientar a UI depois de expirar.
- Pausar avaliacao durante escrita da foto, troca de lente e processamento pesado.
- Cachear features da imagem de referencia enquanto ela nao mudar.
- Medir tempo e memoria em toda execucao; nao inferir performance apenas pela sensacao visual.
- Se o budget for excedido repetidamente, reduzir frequencia antes de reduzir a qualidade da captura.
- A opcao desligada nao cria worker, nao segura frames e nao carrega features da referencia.

## 5. Plano para o modelo Fast

Cada fase abaixo e uma tarefa independente. O implementador deve parar ao concluir a fase pedida.

### Fase 1 — caracterizar antes de mover

Objetivo: congelar o comportamento atual.

Alteracoes permitidas:

- adicionar fixtures sinteticas para `accept`, `review` e `reject`;
- testar parsing, matriz estimada, metricas e decisao;
- registrar os dois pares reais apenas como benchmark local ignorado pelo Git.

Nao fazer:

- mover arquivos;
- alterar thresholds;
- tocar em iOS/Android.

Verificacao:

```sh
cmake -S processing -B processing/build
cmake --build processing/build
ctest --test-dir processing/build --output-on-failure
```

Pronto quando: os tres estados do pre-voo possuem testes deterministas.

### Fase 2 — extrair `camerae_vision`

Objetivo: mudar apenas ownership e dependencias.

Passos:

1. Criar `vision/CMakeLists.txt` e target `camerae_vision`.
2. Mover `alignment_processor` para `vision/include` e `vision/src/opencv`.
3. Renomear namespace para `camerae_vision`.
4. Mover testes e CLI de alinhamento para `vision/tests` e `vision/tools`.
5. Fazer `camerae_processing` linkar `camerae_vision`.
6. Preservar CLI, outputs, matrizes, metricas e thresholds.

Nao fazer:

- redesenhar APIs;
- otimizar algoritmo;
- alterar presets;
- integrar plataformas.

Pronto quando: testes de `vision` e `processing` passam e os JSONs dos dois pares continuam equivalentes.

### Fase 3 — criar preset `captureFast`

Objetivo: oferecer uma chamada barata e previsivel.

Passos:

1. Criar `alignment_quality.hpp/.cpp`.
2. Adicionar `AlignmentQualityPreset::captureFast`.
3. Comparar somente similaridade e afim.
4. Escolher o modelo aceito com menor erro local; em empate, escolher similaridade.
5. Retornar latencia e motivos, sem gravar imagens.
6. Reusar features da referencia entre chamadas.

Testes obrigatorios:

- escolhe similaridade quando suficiente;
- escolhe afim quando melhora materialmente o residuo;
- rejeita transformacao extrema;
- nao executa ECC/SIFT;
- referencia e settings iguais reutilizam cache;
- referencia alterada invalida cache.

Pronto quando: a API retorna somente dados e nao faz I/O.

### Fase 4 — simulador de captura desktop

Objetivo: medir custo sem tocar na camera mobile.

CLI proposta:

```sh
camerae-capture-quality-simulator \
  --reference reference.png \
  --frames frames/ \
  --analysis-fps 2 \
  --latest-only 1 \
  --report out/capture-quality.json
```

O relatorio deve conter:

- decisao e score por frame;
- modelo escolhido;
- p50/p95/max de latencia;
- frames recebidos, analisados e descartados;
- pico aproximado de memoria mantida pelo pipeline;
- percentual de `accept/review/reject`.

Pronto quando: uma sequencia longa pode ser simulada sem acumular backlog.

### Fase 5 — contrato de componente opcional

Objetivo: preparar integracao futura, ainda sem UI/mobile.

Criar apenas tipos neutros:

```text
CaptureSupportComponent
  id: alignmentQuality
  enabled: Bool
  cadence: conservative | balanced | responsive
```

Regras:

- default inicial: desligado em producao;
- estado pertence ao modulo consumidor/projeto, nao ao OpenCV;
- Camerae Vision recebe settings prontos e nao conhece preferencias de UI;
- nenhum registro dinamico de plugins nesta fase.

Pronto quando: um teste demonstra que `enabled = false` nao agenda trabalho.

## 6. Ordem de execucao recomendada

```text
Fase 1 → Fase 2 → Fase 3 → Fase 4 → parar e avaliar numeros
```

A Fase 5 so deve comecar depois que o simulador provar que o preset rapido tem custo aceitavel. Integracao real com iOS/Android exige um plano separado.

## 7. Criterios para a avaliacao apos a Fase 4

Prosseguir para mobile somente se:

- nao existir backlog crescente;
- descarte de frames funcionar como planejado;
- a memoria permanecer limitada a referencia, frame em analise e frame mais recente;
- `accept/review/reject` for coerente nas fixtures e sequencias reais;
- o preset rapido for claramente mais barato que o render final;
- desligar o componente eliminar o custo recorrente.

Os budgets absolutos de CPU, energia e latencia serao definidos em aparelhos reais. O desktop valida arquitetura e comportamento, nao consumo de bateria mobile.

## 8. Fora de escopo

- alterar `CameraController.swift`;
- adicionar toggles SwiftUI;
- criar JNI ou bridge Objective-C++;
- atualizar OpenCV 4.3/4.10 para 4.13;
- rodar analise a 30/60 fps;
- alinhar ou salvar a foto final durante captura;
- optical flow, malha, depth, ML, deghosting ou blending;
- transformar Camerae Vision em framework generico de plugins.

## 9. Primeiro prompt recomendado para o Fast

> Execute somente a Fase 1 de `docs/CAMERAE_VISION_FAST_PLAN.md`. Adicione testes sinteticos deterministas para os estados accept, review e reject do pre-voo atual. Preserve thresholds e comportamento, nao mova arquivos e nao toque em iOS/Android. Rode CMake, build e CTest e pare.
