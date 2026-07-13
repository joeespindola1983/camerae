# Camerae 3.0 — plano de performance, arquitetura e TDD

Status: baseline da v3 implementada; documento mantido como roadmap de evolução

Versão-alvo: `3.0.0`

Escopo inicial: iOS e núcleo C++ de processamento
Data da auditoria: 2026-07-13

## 1. Resultado esperado

A versão 3.0 deve continuar abrindo a biblioteca atual sem mover ou perder fotos, mas deixar de enumerar milhares de arquivos para montar cada tela. Ao mesmo tempo, o projeto passa a ter uma estratégia de testes que valide:

- regras isoladas;
- persistência e migração usando um filesystem real temporário;
- colaboração entre catálogos, manifests, cache e features;
- fluxos essenciais da interface;
- desempenho, memória e I/O;
- contratos entre Swift, Objective-C++ e o núcleo C++.

O objetivo não é apenas aumentar cobertura. A arquitetura precisa tornar erros difíceis de introduzir: dependências são injetadas na composição do app, módulos impõem limites de compilação, formatos antigos ficam representados por fixtures e as regiões críticas recebem budgets mensuráveis.

## 2. Diagnóstico do estado atual

### 2.1 Testes e build

- `ios/project.yml` possui somente o target de aplicação `Camerae`.
- O scheme contém uma ação `test`, mas não há target de unit, integração, UI ou performance associado.
- `processing/CMakeLists.txt` gera a biblioteca e a ferramenta de preview, mas não habilita CTest.
- O workflow `ios-build.yml` somente compila para um device iOS genérico.
- Não há fixtures de compatibilidade de manifests nem biblioteca de dados de stress.

### 2.2 Gargalos observados no código

- `ProjectStore` é `@MainActor`, usa `FileManager.default` diretamente e chama `reload()` no `init`.
- O carregamento de projetos enumera diretórios, abre e decodifica cada `project.json` antes de apresentar a lista.
- `TimelapseSessionStore.sessionSummaries()` enumera as sessões e, para cada uma, volta ao disco para contar/ordenar frames, achar a primeira imagem, procurar vídeos e verificar processamento astro.
- `firstReferenceFrameURL()` repete a enumeração e a ordenação de sessões e frames.
- `RepeatableProjectRuntimeView.reloadSessions()` monta todos os resumos de forma síncrona.
- `AstroProcessingController.reload()` roda na `MainActor` e combina inventário de frames, leitura de EXIF, busca de renders e cálculo recursivo de armazenamento.
- `ReferenceThumbnail` já faz downsampling, mas o cache é somente em disco, fica junto à mídia original, não deduplica requisições em andamento, não limita concorrência e não possui política de memória/evicção.
- Tipos grandes misturam view, estado, descoberta de arquivos e ações. Exemplos atuais: `AstroProcessingView.swift` com mais de 2.300 linhas, `RepeatableCameraView.swift` com mais de 1.900 e `CameraController.swift` com mais de 1.700.

### 2.3 Princípios para a mudança

1. Fotos, vídeos e manifests atuais continuam sendo a fonte de verdade.
2. Índices e thumbnails são derivados: podem ser apagados e reconstruídos.
3. Nenhuma enumeração proporcional ao número de fotos acontece na `MainActor`.
4. Uma linha de lista não abre arquivos nem enumera diretórios durante o `body`.
5. Migração é aditiva, versionada, atômica e recuperável.
6. Primeiro caracterizar o comportamento atual; depois refatorar em fatias pequenas.
7. Protocolos serão criados nos limites com efeitos externos, não para cada tipo interno.

## 3. Arquitetura-alvo

### 3.1 Módulos e dependências

```text
Camerae (app e composition root)
  ├── CameraeFeatures (SwiftUI, estado de tela e navegação)
  │     ├── CameraeMedia
  │     └── CameraeCore
  ├── CameraeMedia (thumbnail, vídeo, adapters de processamento)
  │     └── CameraeCore
  └── CameraeCore (domínio, manifests, catálogos e persistência)

OpenCVBridge.mm
  └── camerae_processing (C++17)
```

Implementação recomendada no XcodeGen:

- `CameraeCore`: framework iOS sem SwiftUI, UIKit, AVFoundation ou OpenCV;
- `CameraeMedia`: framework iOS para ImageIO/UIKit/AVFoundation e adapters;
- `CameraeFeatures`: framework iOS para SwiftUI, estado de tela e navegação;
- `Camerae`: entry point da aplicação, integração final da câmera e ponto único de composição;
- `CameraeCoreTests`: Swift Testing, sem app host sempre que possível;
- `CameraeMediaTests`: Swift Testing para imagens e serviços de mídia;
- `CameraeIntegrationTests`: testes app-hosted dos componentes reais montados juntos;
- `CameraeUITests`: XCTest/XCUIAutomation;
- `CameraePerformanceTests`: XCTest em scheme/test plan separado;
- `camerae_processing_tests`: CTest para o núcleo C++.

Não é necessário extrair todas as features no primeiro commit. O primeiro limite obrigatório é retirar modelos, manifests e acesso ao catálogo das views. A separação em targets passa a validar a direção das dependências durante a compilação.

### 3.2 Composition root e dependências controláveis

`CameraeApp` criará um `AppEnvironment` e o injetará na raiz:

```swift
struct AppEnvironment {
    let projectCatalog: ProjectCatalog
    let sessionCatalogFactory: SessionCatalogFactory
    let thumbnailPipeline: ThumbnailPipeline
    let clock: any ClockProviding
    let idGenerator: any IDGenerating
}
```

Seams necessários:

- raiz da biblioteca (`LibraryLocation`), para não depender de Documents nos testes;
- relógio e gerador de UUID, para fixtures determinísticas;
- filesystem somente onde for necessário simular falhas; testes de componentes usarão diretório temporário real por padrão;
- gerador/decoder de thumbnails;
- modo de câmera para UI tests, pois o Simulator não oferece o fluxo real de captura do app.

`FileManager.default`, `Date()`, `UUID()` e a localização de Documents não devem aparecer em view models ou views. Eles ficam atrás dos serviços concretos criados pelo `AppEnvironment`.

### 3.3 Catálogos assíncronos

Criar actors com APIs orientadas à interface:

- `ProjectCatalog`: lista, cria, arquiva, marca abertura e repara projetos;
- `SessionCatalog`: lista resumos, cria sessão, registra frames, finaliza captura e repara sessão;
- `AstroInventory`: produz uma fotografia imutável de frames/renders para uma sessão;
- `ThumbnailPipeline`: memória, disco, geração, invalidação e deduplicação.

As telas recebem snapshots imutáveis (`ProjectSummary`, `SessionSummary`, `AstroInventorySnapshot`). A publicação final do snapshot acontece na `MainActor`; descoberta, JSON, EXIF e cálculo de tamanho ficam nos actors/tasks de utility priority.

Não retornar `URL` descobertas repetidamente por propriedades computadas de uma linha. O snapshot já deve trazer os identificadores e caminhos relativos necessários.

## 4. Formato v3 e estratégia de migração

### 4.1 Manifest de projeto

Adicionar campos opcionais a `project.json`:

```text
schemaVersion: 3
summary:
  sessionCount
  mediaCount
  referenceThumbnailKey
  latestSessionAt
  totalKnownBytes (opcional)
  inventoryState: clean | dirty
  generation
```

Os campos existentes são preservados. Decoders v2 normalmente ignoram os novos campos; a v3 deve continuar aceitando manifests sem `schemaVersion` como legado.

### 4.2 Manifest de sessão

Evoluir `manifest.json` de leitura parcial para um modelo `Codable` versionado e aditivo:

```text
schemaVersion: 3
frameSummary:
  count
  firstFileName
  lastFileName
  nextFrameIndex
  knownBytes
astroSummary:
  frameCount
  hasRenderedClip
videoSummary:
  videoFileName
  clipFileName
thumbnailKey
inventoryState: clean | dirty
generation
```

Durante uma captura:

1. marcar a sessão como `dirty` antes do primeiro frame;
2. manter contadores em memória;
3. persistir checkpoints em lote (proposta inicial: a cada 25 frames ou 2 segundos, o que vier primeiro);
4. fazer flush e marcar `clean` ao finalizar ou interromper normalmente;
5. ao encontrar uma sessão `dirty` no próximo launch, mostrar o último resumo conhecido e reparar somente essa sessão em background.

Isso evita escrever JSON a cada foto e também evita varrer todas as sessões após um encerramento inesperado.

### 4.3 Índice derivado

Manter um índice compacto em `Library/Application Support/Camerae/catalog-v3.json`, ou equivalente dentro do container privado. Ele contém apenas os resumos necessários para a home.

- Escrita atômica (`.tmp` + replace/rename).
- `schemaVersion`, `generation` e checksum/validação estrutural.
- Se ausente, inválido ou incompatível: a home abre vazia/loading e o catálogo reconstrói em background a partir dos manifests.
- O índice nunca é requisito para recuperar uma foto.
- Alterações de create/archive/finalize atualizam manifest e índice em uma transação lógica; em divergência, manifest vence.

Não introduzir SwiftData/Core Data na v3.0. O conjunto atual é hierárquico, local e já possui manifests; um banco adicionaria uma segunda fonte de verdade antes de medirmos a solução mais simples. Reavaliar somente se filtros, busca global ou sincronização tornarem o índice JSON insuficiente.

### 4.4 Compatibilidade e recuperação

- Migração lazy: só atualizar um manifest quando ele for lido/reparado ou modificado.
- Nenhuma foto ou vídeo será movido durante a migração.
- Escritas sempre atômicas; nunca substituir um manifest válido por dados parcialmente calculados.
- Manter fixtures v1/v2 no repositório para impedir regressão de leitura.
- Manter campos desconhecidos sempre que for necessário reescrever um documento futuro/legado.
- Se um resumo estiver stale, a UI pode usar o último valor e sinalizar refresh sem bloquear abertura.
- Cache e catálogo derivados terão uma ação interna de rebuild para diagnóstico.

## 5. Pipeline de thumbnails

### 5.1 Desenho

`ThumbnailPipeline` será um actor com três níveis:

1. `NSCache` para imagens decodificadas em memória, com `totalCostLimit` e custo aproximado em bytes;
2. arquivos JPEG/HEIF reduzidos em `Library/Caches/Camerae/Thumbnails`;
3. downsampling do original via ImageIO quando não houver cache.

Regras:

- chave inclui identidade estável da mídia, tamanho solicitado, tamanho do original e data de modificação;
- buckets de tamanho, por exemplo 128/256/512 px, calculados a partir do tamanho em pontos e `displayScale`;
- uma única task em andamento por chave (`inFlight[key]`);
- limite inicial de 3–4 decodes simultâneos, calibrado por Instruments;
- respeitar cancelamento quando uma célula sair da tela;
- fazer decode completo fora da main thread antes de publicar a imagem;
- remover cache corrompido e regenerar;
- cache não participa de backup e possui limite/evicção em disco;
- gerar o thumbnail de referência assim que o primeiro frame for salvo, quando isso não atrasar a captura;
- placeholders estáveis para evitar mudança de layout durante scroll.

### 5.2 Listas

- `LazyVStack`/`List` recebe apenas summaries já carregados.
- Nenhum `Data(contentsOf:)`, `resourceValues`, EXIF ou `contentsOfDirectory` dentro de `body`, propriedades de row ou callbacks síncronos de `onAppear`.
- Pré-aquecer somente a próxima janela visível, com cancelamento ao mudar de tela.
- Carregar metadados em lotes e publicar mudanças coalescidas, evitando uma atualização global para cada thumbnail.

## 6. Otimizações por feature

### 6.1 Home e projetos

- `ProjectStore` deixa de fazer I/O no `init` da `MainActor` e vira um view model fino sobre `ProjectCatalog`.
- Primeiro render usa o índice compacto; validação/reparo roda em background.
- Contagens e thumbnail de referência vêm de `ProjectSummary`.
- Create/archive atualizam a lista otimisticamente, com rollback explícito se a persistência falhar.

### 6.2 Repeatable

- `sessionSummaries()` passa a ler manifests/resumos, sem enumerar frames por linha.
- A referência inicial vem do `firstFileName` persistido.
- `frameURLs` completos só são materializados para reprodução, exportação ou processamento.
- Contagem, vídeo existente e estado astro são atualizados no momento em que essas operações terminam.
- Abertura da tela publica rapidamente a lista e enriquece apenas sessões legacy/dirty em background.

### 6.3 Astrophotography

- Fazer uma única varredura para construir `AstroInventorySnapshot` e reutilizá-la em contagem, frame inicial, renders e comandos.
- Leitura de EXIF para recomendar início ocorre em background e pode aparecer depois do conteúdo básico.
- Cálculo recursivo de armazenamento é lazy: executar ao abrir a área de arquivos/armazenamento ou ao solicitar exportação.
- Inventários são invalidados por geração quando captura, rejeição, stack ou render altera os arquivos.
- Processamentos longos expõem progresso e respeitam cancelamento; nunca seguram a `MainActor`.

## 7. Estratégia de TDD

### 7.1 Frameworks

- Swift Testing (`@Test`, `#expect`, testes parametrizados e `async`) para unit e component tests novos.
- XCTest para XCUITest e performance metrics.
- CTest com um executável de testes pequeno para C++.
- Os frameworks podem coexistir; não há benefício em forçar UI/performance para Swift Testing.

### 7.2 Ciclo obrigatório por fatia

1. **Characterize**: registrar com teste o comportamento legado que precisa sobreviver.
2. **Red**: escrever o menor teste que descreve a próxima capacidade ou bug.
3. **Green**: implementar o mínimo para fazê-lo passar.
4. **Refactor**: melhorar nomes/limites sem alterar comportamento.
5. **Component check**: executar o fluxo com implementações reais e diretório temporário.
6. **Performance check**: quando tocar catálogo, thumbnail ou inventário, comparar a região instrumentada.

Regra de pull request: código novo de domínio/persistência não entra sem teste; correção de bug começa com um teste que reproduz o problema; refatoração de legado começa com characterization tests suficientes para a área tocada.

### 7.3 Pirâmide desejada

O número exato será consequência do comportamento, não uma meta artificial de cobertura:

- muitos unit tests rápidos para regras e codecs;
- um conjunto forte de component tests usando os componentes reais;
- poucos integration tests atravessando features e serviços;
- poucos UI tests para jornadas P0;
- uma suíte separada de performance e stress.

Cobertura serve como sinal, não como objetivo. Meta inicial razoável: 80%+ de linhas no novo `CameraeCore`, com 100% dos caminhos de migração e recuperação cobertos. Não exigir cobertura global alta dos controllers de câmera legados antes de criar seams seguros.

## 8. Catálogo de testes prioritários

Prioridades:

- **P0**: bloqueia merge/release;
- **P1**: obrigatório antes do RC da 3.0;
- **P2**: endurecimento contínuo após a base.

### 8.1 Domínio e codecs — Swift Testing

| Prioridade | Teste | O que protege |
|---|---|---|
| P0 | decode de cada fixture de `project.json` v1/v2/v3 | compatibilidade da biblioteca existente |
| P0 | decode de cada `manifest.json` v1/v2/v3 | sessões antigas e campos opcionais |
| P0 | encode/decode v3 preserva identidade, datas, módulo e estado | estabilidade do formato |
| P0 | ordenação por `lastOpenedAt`, `updatedAt` e desempate | ordem da home |
| P0 | transições `dirty → checkpoint → clean` | recuperação de captura |
| P0 | atualização de resumo após primeiro frame, próximo frame e finalização | contagens sem scan |
| P0 | sanitização e validação de caminhos | não gravar/apagar fora do projeto |
| P1 | nomes vazios, Unicode, acentos e colisões de diretório | criação consistente |
| P1 | parâmetros inválidos de stack/export | erros previsíveis |
| P1 | testes parametrizados para todos os módulos/capture kinds/orientações | cobertura de variantes |

### 8.2 Persistência e catálogos — component tests com filesystem real

Cada teste cria sua própria árvore em `FileManager.default.temporaryDirectory`, monta implementações concretas e remove a fixture no teardown.

| Prioridade | Teste | O que protege |
|---|---|---|
| P0 | criar projeto → escrever manifest/índice → instanciar catálogo novo → reler igual | colaboração completa da persistência |
| P0 | criar sessão → salvar frames → checkpoint → finalizar → reler summaries | fluxo real de captura |
| P0 | biblioteca legacy é aberta e migrada sem mover mídia | segurança da atualização |
| P0 | índice ausente/corrompido é reconstruído a partir dos manifests | cache derivado, nunca fonte única |
| P0 | manifest corrompido em um projeto não impede os demais de aparecer | isolamento de falha |
| P0 | sessão `dirty` após encerramento é reparada e mantém todos os frames | crash recovery |
| P0 | tentativa de deletar URL fora de `Sessions` falha e preserva arquivo | segurança destrutiva |
| P0 | duas leituras concorrentes recebem um snapshot consistente | corretude dos actors |
| P1 | resumo stale é servido rapidamente e corrigido em background | experiência durante reparo |
| P1 | falha simulada antes do replace mantém o manifest anterior legível | atomicidade |
| P1 | pasta órfã, manifest ausente e arquivo parcial são classificados/reparados | tolerância a inconsistências |
| P1 | archive/unarchive persiste e atualiza índice | consistência home–disco |
| P1 | cancelamento de reload impede publicação de snapshot antigo | navegação concorrente |
| P2 | permissões negadas, disco cheio e arquivo read-only geram erros tipados | diagnóstico e UX |

Os testes devem inspecionar tanto a API quanto a árvore produzida no disco. Isso valida componentes juntos sem depender de mocks que apenas repetem a implementação.

### 8.3 Thumbnail pipeline — component e concorrência

Fixtures mínimas: JPEG portrait com EXIF de orientação, JPEG landscape, imagem grande, imagem corrompida e um arquivo que muda mantendo o mesmo nome.

| Prioridade | Teste | O que protege |
|---|---|---|
| P0 | downsample respeita o bucket máximo e orientação | memória e aparência |
| P0 | segunda leitura usa cache de memória sem tocar o original | scroll quente |
| P0 | após limpar memória, leitura usa cache de disco | reabertura rápida |
| P0 | N pedidos simultâneos da mesma chave fazem um único decode | deduplicação |
| P0 | mudança de tamanho/data invalida o cache | imagem nunca stale |
| P0 | cache corrompido é removido e regenerado | autorrecuperação |
| P1 | limite de concorrência nunca é excedido | pico de CPU/memória |
| P1 | cancelamento não publica imagem numa row reutilizada | consistência visual |
| P1 | eviction por custo libera imagens sob pressão | estabilidade de memória |
| P1 | arquivos de cache ficam em Caches e não no projeto | backup/export limpos |
| P2 | medição de custo aproximado corresponde às dimensões/pixel format | política de cache |

Usar um decoder instrumentado apenas para contar chamadas/concorrência; manter pelo menos um teste com ImageIO real para validar a integração verdadeira.

### 8.4 Integração de features

| Prioridade | Teste | O que protege |
|---|---|---|
| P0 | `ProjectListModel` + `ProjectCatalog` real carregam biblioteca vazia e populada | estado da home com persistência real |
| P0 | abrir Repeatable usa summaries sem enumerar frames por row | regressão central de performance |
| P0 | `AstroInventory` faz uma varredura e o snapshot alimenta contagem/referência/renders | remoção de scans duplicados |
| P0 | app environment monta todos os serviços concretos e inicializa a raiz | grafo de componentes |
| P1 | criação pela feature aparece na lista e sobrevive a relaunch simulado | UI state + persistência |
| P1 | erro de escrita volta o estado otimista e apresenta erro | consistência do usuário |
| P1 | cálculo de armazenamento não inicia no reload básico astro | trabalho lazy |
| P1 | atualização de geração invalida inventário e thumbnail corretos | colaboração entre componentes |

Para provar “nenhum I/O por row”, usar um filesystem/reader contador no teste de contrato e também um component test com a implementação real. A regra estrutural deve ser reforçada por módulos: views não importam implementações concretas de persistência.

### 8.5 UI tests — XCTest/XCUIAutomation

Criar launch mode determinístico:

```text
-ui-testing
CAMERAE_LIBRARY_ROOT=<fixture temporária>
CAMERAE_CAMERA_MODE=demo
CAMERAE_NOW=<data fixa>
CAMERAE_UUID_SEED=<seed>
```

O modo demo fornece frames locais apenas em builds Debug/UI Testing e não entra no comportamento de Release. Adicionar accessibility identifiers estáveis aos elementos testados.

| Prioridade | Jornada | Verificações principais |
|---|---|---|
| P0 | home vazia → `+ Criar` de cada lado → projeto correto | botões independentes e módulo correto |
| P0 | biblioteca populada → abrir projeto Repeatable → abrir sessão | navegação e conteúdo essencial |
| P0 | projeto Astro → abrir processamento com fixture | contagens e ações disponíveis |
| P0 | relaunch com biblioteca v2 | migração sem bloqueio/crash |
| P1 | archive/unarchive | lista ativa e arquivada |
| P1 | scroll em 200 projetos e 500 sessões | células, identidade e ausência de travamento |
| P1 | portrait ↔ landscape | layout e botões de ambos os módulos |
| P1 | Dynamic Type grande e idioma longo | acessibilidade e truncamentos críticos |
| P1 | câmera demo → iniciar/parar captura → sessão aparece | jornada integrada sem hardware |
| P2 | VoiceOver smoke por identifiers/labels | semântica básica |

Não usar screenshot pixel-perfect como principal proteção: é frágil para fontes/SF Symbols/OS. Se snapshots visuais forem adicionados, limitar a poucos componentes estáveis e exigir revisão explícita das referências.

### 8.6 Performance e stress — XCTest + signposts

Instrumentar com `os_signpost`/`OSSignposter` estas regiões:

- `ProjectCatalog.loadIndex` e `ProjectCatalog.rebuild`;
- `SessionCatalog.loadSummaries` e `SessionCatalog.repair`;
- `ThumbnailPipeline.memoryHit`, `diskHit` e `decode`;
- `AstroInventory.scan` e `storageScan`;
- tempo até o primeiro conteúdo da home/Repeatable/Astro.

Métricas: `XCTClockMetric`, `XCTMemoryMetric`, `XCTStorageMetric`, `XCTOSSignpostMetric`, `XCTApplicationLaunchMetric` e, nas listas, `XCTHitchMetric` quando suportado pelo destino.

Budgets provisórios para uma biblioteca gerada com 200 projetos, 500 sessões em um projeto e 10.000 frames em uma sessão:

| Região | Budget inicial | Destino |
|---|---:|---|
| home com índice quente, primeiro conteúdo | ≤ 150 ms | device de referência |
| home sem índice, UI responsiva | ≤ 300 ms para primeiro estado; rebuild em background | device de referência |
| lista Repeatable com summaries limpos | ≤ 300 ms | device de referência |
| abrir sessão com 10.000 frames sem materializar frames | ≤ 350 ms | device de referência |
| thumbnail memória | ≤ 10 ms | mediana |
| thumbnail disco | ≤ 30 ms | mediana |
| primeiro lote visível de thumbnails frios | ≤ 500 ms | device de referência |
| Astro básico antes de storage/EXIF completo | ≤ 400 ms | device de referência |
| launch sem hitch longo na main thread | nenhum intervalo > 100 ms causado por catálogo | Instruments/signpost |

Esses números não devem bloquear o primeiro commit: a fase 0 mede o baseline em um iPhone físico fixo, registra hardware/OS e ajusta budgets realistas. Depois disso, o baseline é versionado e só pode piorar com justificativa explícita. CI em Simulator detecta regressões grandes; budgets rígidos rodam no mesmo modelo físico ou em infraestrutura dedicada, porque runners compartilhados variam.

Testes de stress adicionais:

- 0, 1, 200 e 2.000 projetos;
- 0, 1, 500 e 5.000 sessões;
- sessão com 10.000 e 50.000 nomes de frame gerados;
- 100 thumbnails solicitados durante scroll/cancelamento;
- índice e cache frios/quentes;
- memória sob warning;
- reparo de 1 sessão dirty no meio de 500 limpas.

Não commitar dezenas de milhares de arquivos. Criar `tools/generate-test-library` para gerar árvores determinísticas e, quando o conteúdo não importar, arquivos esparsos/pequenos. Imagens reais ficam restritas às fixtures que exercitam ImageIO/EXIF.

### 8.7 Processamento C++ e bridge

Habilitar `include(CTest)` e adicionar `camerae_processing_tests`.

| Prioridade | Teste | Estratégia |
|---|---|---|
| P0 | stack de matrizes de cor conhecida | resultado numérico esperado com tolerância |
| P0 | alinhamento de imagem sintética transladada | transformação/recorte esperado |
| P0 | 0/1 frames e dimensões incompatíveis | erro tipado, sem crash |
| P0 | imagem/arquivo inválido | falha limpa |
| P1 | parâmetros mínimos/máximos de denoise e stack | limites e validação |
| P1 | golden images pequenas | PSNR/SSIM ou tolerância, não bytes exatos |
| P1 | cancelamento/progresso, se expostos pela API | contrato de trabalho longo |
| P1 | repetição não cresce memória continuamente | smoke de estabilidade |

Adicionar testes do contrato Objective-C++ no device build para argumentos, erros e conversão de tipos. No Simulator, o stub deve ter testes explícitos que confirmem a indisponibilidade do processamento OpenCV, evitando um falso positivo funcional.

### 8.8 Regras estruturais

A estrutura será protegida principalmente pela compilação dos targets. Complementos no CI:

- `CameraeCore` não pode importar SwiftUI/UIKit/AVFoundation;
- `CameraeFeatures` não acessa `FileManager.default` nem `Data(contentsOf:)` diretamente;
- views não instanciam `ProjectCatalog`, `SessionCatalog` ou `ThumbnailPipeline` concretos;
- manifests públicos possuem fixture de compatibilidade;
- qualquer alteração em schema exige teste de migração;
- qualquer nova operação O(n) em mídia exige execução fora da `MainActor` e teste de performance relevante.

Um script pequeno de architecture lint pode verificar essas proibições por diretório. Ele complementa, mas não substitui, os limites de target e os integration tests.

## 9. Fixtures e utilitários de teste

Estrutura proposta:

```text
ios/
  CameraeCore/
  CameraeMedia/
  CameraeFeatures/
  CameraeCoreTests/
    Fixtures/Manifests/v1/
    Fixtures/Manifests/v2/
    Fixtures/Manifests/v3/
  CameraeMediaTests/Fixtures/Images/
  CameraeIntegrationTests/
  CameraeUITests/
  CameraePerformanceTests/
  TestSupport/
processing/
  tests/
tools/
  generate-test-library/
```

`TestSupport` fornece:

- `TemporaryLibrary` com cleanup automático;
- builders de projeto/sessão, sem esconder os dados relevantes ao teste;
- `FixedClock` e `SeededIDGenerator`;
- image fixture loader;
- filesystem/decoder spies somente para contagem e falhas específicas;
- gerador de biblioteca de stress;
- assertions para árvores de arquivos e manifests.

Fixtures de usuários reais nunca entram no repositório. Antes de capturar manifests existentes, remover nomes, localização, datas sensíveis e conteúdo de imagem.

## 10. Plano de execução por fases

Cada fase deve terminar com build de Simulator e device genérico verdes. Mudanças grandes serão divididas por fatias verticais para que `main` permaneça executável.

### Fase 0 — baseline e safety net

Entregas:

- criar test targets e test plans (`PR`, `Full`, `Performance`);
- adicionar Swift Testing/XCTest smoke tests e CTest smoke;
- criar fixtures v2 a partir do formato atual, sanitizadas;
- adicionar signposts nas regiões existentes;
- gerar biblioteca de 200/500/10.000 e registrar baseline no Simulator e device;
- characterization tests de create/load/archive, sessão, frame, export URL e ordenação;
- atualizar CI para executar os testes rápidos.

Gate: nenhuma refatoração de persistência começa antes de os formatos atuais estarem cobertos.

### Fase 1 — limites arquiteturais

Entregas:

- criar `CameraeCore` e mover modelos/formatters/codecs puros;
- criar `AppEnvironment`, `LibraryLocation`, clock e IDs injetáveis;
- adaptar `ProjectStore` para um view model sem I/O próprio;
- separar estado/serviço das primeiras views grandes, sem reescrever UI;
- architecture lint inicial.

Gate: app composition integration test monta serviços reais e abre uma biblioteca temporária.

### Fase 2 — schema v3 e ProjectCatalog

Entregas:

- codecs v1/v2/v3;
- `ProjectSummary` e `catalog-v3.json`;
- migração lazy e rebuild;
- carregamento assíncrono da home;
- create/archive/open consistentes com índice;
- testes de corrupção, atomicidade e concorrência.

Gate: biblioteca v2 abre sem alteração de mídia; home não enumera sessões/fotos no caminho quente.

### Fase 3 — SessionCatalog e Repeatable

Entregas:

- `SessionSummary` persistido;
- protocolo dirty/checkpoint/clean durante captura;
- reparo de sessão interrompida;
- lista Repeatable a partir de summaries;
- materialização de frames apenas sob demanda;
- migração em background de sessões legacy.

Gate: projeto com 500 sessões/10.000 frames abre dentro do budget calibrado; todos os fluxos de captura/exportação continuam válidos.

### Fase 4 — ThumbnailPipeline

Entregas:

- actor, NSCache, disk cache, in-flight dedup e limite de concorrência;
- buckets por display scale;
- cache em Library/Caches, evicção e recuperação;
- prefetch/cancelamento das listas;
- geração no primeiro frame quando seguro;
- component, memory e performance tests.

Gate: scrolling não dispara decode duplicado, cache quente é mensuravelmente mais rápido e memória fica dentro do budget calibrado.

### Fase 5 — inventário Astro

Entregas:

- `AstroInventorySnapshot` único;
- EXIF e storage lazy;
- geração/invalidação de inventário;
- controller dividido entre estado de tela e serviços;
- testes de arquivo rejeitado, renders e cálculos derivados.

Gate: primeiro conteúdo Astro não espera scan de armazenamento nem scans repetidos de frames.

### Fase 6 — harness de UI e jornadas críticas

Entregas:

- câmera demo Debug-only;
- biblioteca/clock/UUID configuráveis por launch environment;
- accessibility identifiers;
- UI tests P0 e rotação;
- smoke em dois tamanhos de iPhone no CI periódico.

Gate: jornadas P0 passam sem rede, conta, câmera física ou estado compartilhado entre testes.

### Fase 7 — processamento e contratos

Entregas:

- CTest e imagens sintéticas/golden pequenas;
- contrato Objective-C++ e testes do stub do Simulator;
- tratamento de erros/cancelamento/progresso onde faltar;
- benchmarks do pipeline de stack fora da suíte rápida.

Gate: resultados numéricos críticos e falhas de entrada estão cobertos; bridge não converte erro em crash.

### Fase 8 — hardening e release 3.0

Entregas:

- executar Full/Performance em device fixo;
- teste de atualização usando cópia sanitizada de biblioteca v2;
- Instruments: Time Profiler, Allocations, File Activity e Hangs;
- revisar backup, espaço em disco, corrupção e encerramento durante captura;
- documentar formato v3, recuperação e métricas finais;
- alterar `MARKETING_VERSION` para `3.0.0` somente quando a trilha de migração estiver pronta;
- beta em Firebase antes do App Store release.

Gate: zero P0 aberto, migrations e recovery verdes, budgets aceitos e rollback operacional documentado.

## 11. CI e política de execução

### Pull request

- validar que `xcodegen generate` não deixa diff inesperado;
- `pod install` e build Simulator;
- build device genérico sem signing;
- Swift unit/component/integration P0;
- CTest;
- architecture lint;
- um UI smoke determinístico;
- upload de `.xcresult` em falha.

Meta: feedback rápido. Performance rígida e matriz completa não devem tornar cada PR instável.

### `main`/`qa` e execução noturna

- suíte Full;
- UI em iPhone compacto e grande, portrait/landscape;
- stress de biblioteca;
- performance no ambiente mais estável disponível;
- análise de flaky tests: corrigir ou remover a causa; não adicionar retries silenciosos como solução.

### Release candidate

- testes de migração de todas as fixtures;
- dispositivo físico com câmera para captura real;
- export ZIP/vídeo e processamento Astro;
- instalação sobre build 2.x com biblioteca populada;
- cold/warm launch, memória e armazenamento;
- archive com configuração Release.

## 12. Definition of Done por mudança

Uma fatia está pronta quando:

- teste falhou antes da implementação e passa depois, salvo characterization explícito;
- unit tests cobrem regras e component test cobre a colaboração real relevante;
- não há I/O pesado na `MainActor`;
- erros, cancelamento e estado vazio foram tratados;
- formato persistido novo possui fixture e teste de compatibilidade;
- região crítica possui signpost e, quando aplicável, performance test;
- build Simulator e device estão verdes;
- documentação foi atualizada se mudou schema, fluxo ou budget;
- não houve alteração/deslocamento destrutivo da mídia existente.

## 13. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Refatoração ampla quebrar captura | fatias verticais, characterization tests e câmera real no RC |
| Migração perder metadados | formato aditivo, fixtures, escrita atômica e mídia imóvel |
| Índice ficar divergente | manifest vence; generation/dirty; rebuild automático |
| Testes excessivamente mockados | filesystem e ImageIO reais nos component tests |
| UI tests flaky | clock/UUID/câmera/biblioteca determinísticos; poucos fluxos P0 |
| Performance tests instáveis em CI | Simulator como alarme; baseline rígido em device fixo |
| Cache aumentar armazenamento | Library/Caches, limite/evicção e rebuild |
| Modularização atrasar entrega | extrair primeiro Core/persistência; features gradualmente |
| Checkpoint frequente afetar captura | batching por tempo/frames e medição de storage/CPU |

## 14. Ordem dos primeiros pull requests

1. Test targets, test plans, fixtures v2 e CI smoke — sem mudar comportamento.
2. Characterization tests de `ProjectStore`/`TimelapseSessionStore` e dependências injetáveis.
3. `CameraeCore`, codecs versionados e composition root.
4. `ProjectCatalog` + índice v3 + home assíncrona.
5. `SessionCatalog` + summaries + Repeatable.
6. `ThumbnailPipeline` e listas.
7. `AstroInventory` e trabalho lazy.
8. UI harness, CTest completo, performance gates e hardening.

O bump para `3.0.0` deve acontecer perto do primeiro beta que já lê e repara formatos antigos. Fazer o bump antes não traz proteção; os testes de migração e o caminho de rollback são o que tornam a major segura.

## 15. Referências técnicas

- [Testing in Xcode](https://developer.apple.com/documentation/xcode/testing)
- [Swift Testing](https://developer.apple.com/documentation/testing)
- [Performance tests with XCTest](https://developer.apple.com/documentation/xctest/performance-tests)
