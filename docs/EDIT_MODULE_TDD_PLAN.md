# Camerae Edit — plano detalhado de desenvolvimento orientado por TDD

Status: proposta pronta para implementação

Escopo-alvo: iOS, `CameraeCore`, `CameraeMedia` e aplicação SwiftUI

Compatibilidade mínima: iOS 17

## 1. Instruções para o LLM implementador

Este documento deve ser tratado como o contrato de implementação do primeiro MVP do módulo Edit.

Regras obrigatórias:

1. Trabalhar em fatias pequenas seguindo **Characterize → Red → Green → Refactor**.
2. Não implementar toda a feature em uma única alteração.
3. Não mover, renomear, duplicar nem modificar mídias produzidas por Astro ou Repeatable.
4. Não persistir URLs absolutas do container iOS em `edit.json`.
5. Preservar integralmente a leitura dos projetos e sessões existentes.
6. Código novo de domínio e persistência deve nascer em `CameraeCore` com testes Swift Testing.
7. Código de AVFoundation, thumbnails e composição deve ficar em `CameraeMedia`, com testes próprios.
8. Views não podem enumerar diretórios, abrir manifests ou carregar metadados de AVFoundation dentro de `body`.
9. Toda operação longa deve ser assíncrona, cancelável quando aplicável e executada fora da `MainActor`.
10. Não adicionar cortes, transições, música, texto, filtros de cor ou múltiplas faixas neste MVP.
11. Ao terminar cada fase, executar a suíte relevante antes de seguir.
12. Preservar mudanças preexistentes e não relacionadas no worktree.

## 2. Objetivo do produto

Adicionar um terceiro módulo, **Edit**, ao lado de **Repeatable** e **Astro**.

O Edit é um montador de portfólio, não um editor não linear completo. Ele permite selecionar vídeos já produzidos no Camerae, organizá-los em uma sequência, reproduzir essa sequência e exportar um MP4 final.

Fluxo principal:

```text
Home
  → Edit
    → Criar projeto Edit
      → Selecionar mídias
        → Filtrar e adicionar clips
          → Reordenar/remover/repetir
            → Reproduzir sequência
              → Exportar MP4
                → Compartilhar
```

## 3. Escopo fechado do MVP

### 3.1 Capacidades obrigatórias

- Ter um card Edit na home.
- Criar, listar, abrir, arquivar e excluir projetos Edit usando o catálogo de projetos existente.
- Descobrir as mídias locais já produzidas pelo Camerae:
  - Repeatable timelapse: `Sessions/<session>/timelapse.mp4`;
  - Repeatable vídeo gravado: `Sessions/<session>/video.mov`;
  - Astro renderizado: `Sessions/<session>/Astro Renders/<render>/astro.mp4`.
- Mostrar uma biblioteca visual com thumbnail, nome do projeto, origem, tipo, duração e data.
- Filtrar por:
  - origem: Todos, Repeatable ou Astro;
  - tipo: Todos, Timelapse ou Vídeo gravado;
  - projeto de origem, opcional.
- Ordenar o seletor inicialmente por data decrescente.
- Adicionar uma ou várias mídias à timeline.
- Permitir que a mesma mídia seja adicionada mais de uma vez.
- Reordenar os itens por drag-and-drop.
- Remover um item da timeline sem apagar a mídia original.
- Persistir automaticamente a sequência.
- Reabrir o projeto mantendo exatamente a mesma ordem.
- Reproduzir os clips na ordem, com play, pause e reinício.
- Mostrar qual item está em reprodução.
- Escolher canvas 16:9 horizontal ou 9:16 vertical.
- Exportar um MP4 final em 1080p, 30 fps.
- Aplicar aspect fit com fundo preto; nunca cortar a imagem no MVP.
- Preservar o áudio original dos vídeos que tiverem áudio.
- Mostrar progresso, permitir cancelamento e compartilhar o resultado.
- Detectar uma mídia original ausente sem perder ou corromper a montagem.

### 3.2 Decisões fixas de exportação

| Propriedade | MVP |
|---|---|
| Container | MP4 |
| Canvas | 1920×1080 ou 1080×1920 |
| Frame rate | 30 fps |
| Enquadramento | Aspect fit centralizado |
| Fundo | Preto |
| Crop | Não |
| Áudio | Preservar quando existir |
| Transição | Corte seco |
| Codec | O codec compatível escolhido pelo exportador; não construir Reader/Writer apenas para forçar H.264 |

### 3.3 Fora do escopo

- Trim de início/fim.
- Split de clips.
- Transições.
- Música ou narração externa.
- Mixer, volume e fades de áudio.
- Texto, títulos, marcas d'água e legendas.
- Filtros, LUTs e correção de cor.
- Controle de velocidade.
- Crop, pan e zoom.
- Canvas quadrado.
- Exportação 4K ou escolha de fps.
- Importação da Fototeca para a timeline Edit.
- Cloud sync.
- Proteção automática contra exclusão de um projeto-fonte; o MVP apenas reporta a referência ausente.

## 4. Estado atual relevante do repositório

O repositório já possui:

- `CameraeCore`: modelos, codecs e catálogos versionados;
- `CameraeMedia`: pipeline de thumbnails;
- `Camerae`: SwiftUI, AVFoundation e composition root atual;
- Swift Testing para Core, Media e integração;
- XCTest para UI e performance;
- `ProjectCatalog` com índice derivado e manifests atômicos;
- `SessionCatalog` com resumos de frames e outputs;
- `TimelapseVideoRenderer` para renderizar sequências de imagens;
- `WorkflowVideoSettings` no target da aplicação.

Pontos que exigem alteração cuidadosa:

- `ProjectModule` e `CameraModule` possuem apenas Astro e Repeatable.
- `ModuleSelectionView` assume visualmente dois cards lado a lado.
- `ModuleRuntimeView` possui switch exaustivo com dois módulos.
- `ProjectCatalog.normalizedName` usa uma condição binária Astro/Repeatable.
- `ProjectStore.enrichLegacySummaries` tenta construir `SessionCatalog` para todo projeto; projetos Edit precisam de tratamento separado.
- `SessionCatalog` informa apenas `hasRenderedClip` para Astro e não lista todos os renders.
- `ThumbnailPipeline` usa `ImageIOThumbnailDecoder`, que não gera thumbnail de vídeo.
- `TimelapseVideoRenderer` recebe imagens; ele não é o compositor de clips do Edit e não deve ser adaptado para essa responsabilidade.

## 5. Arquitetura-alvo

```text
Camerae (SwiftUI e composição)
  ├── EditProjectViewModel
  ├── EditLibraryViewModel
  ├── EditPlaybackCoordinator
  ├── CameraeMedia
  │    ├── MediaLibraryCatalog
  │    ├── MediaAssetProbe
  │    ├── MediaThumbnailDecoder
  │    ├── EditCompositionPlanner
  │    └── EditVideoComposer
  └── CameraeCore
       ├── ProjectModule.edit
       ├── MediaAssetReference e filtros
       ├── EditProjectDocument e timeline
       ├── EditProjectCodec
       └── EditProjectCatalog
```

Direção das dependências:

```text
Camerae → CameraeMedia → CameraeCore
Camerae → CameraeCore
CameraeCore → Foundation apenas
```

`CameraeCore` não pode importar SwiftUI, UIKit ou AVFoundation.

## 6. Modelo de domínio proposto

Os nomes podem ser refinados durante o Refactor, mas a semântica deve permanecer.

### 6.1 Projeto e canvas

```swift
public enum ProjectModule: String, CaseIterable, Codable, Hashable, Sendable {
    case astrophotography
    case repeatable
    case edit
}

public enum EditCanvas: String, CaseIterable, Codable, Hashable, Sendable {
    case landscape16x9
    case portrait9x16
}
```

### 6.2 Identidade da mídia

```swift
public struct MediaAssetID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String
}

public enum MediaSourceKind: String, CaseIterable, Codable, Hashable, Sendable {
    case repeatableTimelapse
    case repeatableVideo
    case astroTimelapse
}

public struct MediaAssetReference: Codable, Equatable, Hashable, Sendable {
    public let id: MediaAssetID
    public let projectID: UUID
    public let sessionID: UUID
    public let kind: MediaSourceKind
    public let relativePath: String
}
```

Regras:

- `relativePath` é relativo ao diretório do projeto-fonte.
- Nunca persistir `URL.absoluteString` ou o caminho completo do sandbox.
- O ID deve ser determinístico e estável entre launches.
- Não usar `Hasher`, pois seu resultado não é estável entre processos.
- Uma composição aceitável do ID é a concatenação normalizada de `projectID`, `sessionID`, `kind` e `relativePath`.
- Validar o caminho resolvido para impedir `..` e impedir fuga do diretório do projeto-fonte.

### 6.3 Descriptor de runtime

O descriptor representa uma mídia já resolvida e inspecionada. Ele não é persistido no `edit.json`.

```swift
public struct MediaAssetDescriptor: Equatable, Hashable, Sendable {
    public let reference: MediaAssetReference
    public let sourceModule: ProjectModule
    public let projectName: String
    public let sessionName: String
    public let sourceCreatedAt: Date
    public let duration: TimeInterval
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let hasAudio: Bool
    public let fileSize: UInt64
    public let isAvailable: Bool
}
```

O `URL` resolvido pode ficar em um tipo de Media ou em um mapa privado do catálogo. Se for exposto, deve ser runtime-only e nunca codificado.

### 6.4 Timeline

```swift
public struct EditTimelineItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let asset: MediaAssetReference
    public let addedAt: Date
}

public struct EditProjectDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let projectID: UUID
    public var canvas: EditCanvas
    public var items: [EditTimelineItem]
    public var updatedAt: Date
    public var lastExportRelativePath: String?
}
```

Regras:

- A ordem do array é a ordem da timeline; não duplicar essa informação com um campo `position`.
- `EditTimelineItem.id` identifica a ocorrência na timeline.
- `MediaAssetReference.id` identifica a mídia original.
- Dois itens podem apontar para a mesma mídia.
- O codec inicial usa `schemaVersion: 1`.
- Campos futuros devem ser opcionais ou ter defaults de decoding.

## 7. Persistência e layout em disco

O `ProjectCatalog` continuará criando o projeto e seu `project.json`:

```text
Documents/
  Camerae Projects/
    edit/
      2026-..._meu-portfolio/
        project.json
        edit.json
        Exports/
          portfolio.mp4
```

Exemplo de `edit.json`:

```json
{
  "schemaVersion": 1,
  "projectID": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
  "canvas": "landscape16x9",
  "items": [
    {
      "id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
      "addedAt": "2026-07-14T12:00:00Z",
      "asset": {
        "id": "project:session:repeatableTimelapse:Sessions/session_1/timelapse.mp4",
        "projectID": "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
        "sessionID": "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD",
        "kind": "repeatableTimelapse",
        "relativePath": "Sessions/session_1/timelapse.mp4"
      }
    }
  ],
  "updatedAt": "2026-07-14T12:00:00Z",
  "lastExportRelativePath": "Exports/portfolio.mp4"
}
```

Escritas de `edit.json` devem ser atômicas. O arquivo final de exportação também deve ser publicado atomicamente:

1. exportar para um `.tmp.mp4` único dentro de `Exports`;
2. validar status, existência, tamanho e tracks;
3. remover/substituir o destino anterior somente depois do sucesso;
4. limpar temporários em erro ou cancelamento.

## 8. Contratos de serviços

### 8.1 EditProjectCatalog

Responsabilidade: ler e alterar a receita de um único projeto Edit.

API desejada:

```swift
public actor EditProjectCatalog {
    public init(
        project: ProjectRecord,
        fileManager: FileManager = .default,
        dateProvider: any DateProviding = SystemDateProvider(),
        idProvider: any IDProviding = SystemIDProvider()
    )

    public func loadOrCreate() throws -> EditProjectDocument
    public func setCanvas(_ canvas: EditCanvas) throws -> EditProjectDocument
    public func append(_ assets: [MediaAssetReference]) async throws -> EditProjectDocument
    public func moveItem(id: UUID, to destination: Int) throws -> EditProjectDocument
    public func removeItem(id: UUID) throws -> EditProjectDocument
    public func setLastExport(relativePath: String?) throws -> EditProjectDocument
}
```

Regras e erros:

- Rejeitar um `ProjectRecord` cujo módulo não seja `.edit`.
- `loadOrCreate` cria documento vazio apenas se `edit.json` estiver ausente.
- JSON inválido não deve ser silenciosamente substituído; retornar erro recuperável.
- `moveItem` deve definir claramente índices antes/depois da remoção e ter testes de borda.
- `append` deve gerar um ID novo por ocorrência, inclusive para mídia repetida.

### 8.2 MediaLibraryCatalog

Responsabilidade: produzir um snapshot global, imutável e filtrável das mídias existentes.

```swift
public protocol MediaLibraryProviding: Sendable {
    func load() async throws -> MediaLibrarySnapshot
    func resolve(_ reference: MediaAssetReference) async -> ResolvedMediaAsset?
    func invalidate() async
}
```

Descoberta:

1. Carregar o snapshot do `ProjectCatalog`.
2. Ignorar projetos `.edit` como fontes.
3. Incluir projetos-fonte ativos e arquivados; arquivamento não apaga o portfólio.
4. Para cada projeto Astro/Repeatable, carregar resumos/sessões fora da main thread.
5. Para Repeatable:
   - incluir `timelapse.mp4` quando existir e tiver tamanho maior que zero;
   - incluir `video.mov` quando existir e tiver tamanho maior que zero.
6. Para Astro:
   - enumerar cada diretório dentro de `Astro Renders`;
   - criar um asset por `astro.mp4` válido;
   - não reduzir múltiplos renders a um único booleano.
7. Inspecionar metadados com AVFoundation.
8. Publicar uma lista ordenada por `sourceCreatedAt` decrescente, com desempate determinístico por ID.

O snapshot deve suportar filtros puros em Core:

```swift
public enum MediaOriginFilter: Equatable, Sendable {
    case all
    case module(ProjectModule)
}

public enum MediaKindFilter: Equatable, Sendable {
    case all
    case timelapse
    case recordedVideo
}

public struct MediaLibraryFilter: Equatable, Sendable {
    public var origin: MediaOriginFilter
    public var kind: MediaKindFilter
    public var projectID: UUID?
}
```

### 8.3 MediaAssetProbe

Responsabilidade: carregar metadados técnicos de um arquivo de vídeo.

Deve retornar:

- duração finita e maior que zero;
- dimensões orientadas corretamente usando `preferredTransform`;
- presença de track de áudio;
- tamanho do arquivo;
- erro tipado para arquivo ausente, vazio, sem track de vídeo ou ilegível.

Não usar apenas a extensão para concluir que o arquivo é válido.

### 8.4 Thumbnail de vídeo

Evoluir o seam existente `ThumbnailDecoding` sem quebrar thumbnails de imagem:

- manter `ImageIOThumbnailDecoder` para imagens;
- adicionar decoder de vídeo baseado em `AVAssetImageGenerator`;
- adicionar um decoder composto que seleciona a estratégia adequada;
- aplicar `preferredTrackTransform`;
- capturar um frame inicial seguro, por exemplo entre zero e 0,25 s;
- reutilizar `ThumbnailPipeline` para memória, disco, deduplicação e limite de concorrência;
- manter chave dependente de caminho, tamanho, modificação e bucket.

### 8.5 EditPlaybackCoordinator

Responsabilidade: coordenar preview, sem persistência.

Estados mínimos:

```swift
enum EditPlaybackState: Equatable {
    case idle
    case preparing
    case ready(currentItemID: UUID?)
    case playing(currentItemID: UUID)
    case paused(currentItemID: UUID?)
    case finished
    case failed(message: String)
}
```

Requisitos:

- usar `AVQueuePlayer` ou uma abstração equivalente;
- mapear cada player item para o ID da ocorrência na timeline;
- atualizar o destaque quando o item mudar;
- não exportar um preview temporário apenas para reproduzir;
- cancelar observações e tasks ao sair da tela;
- pular ou bloquear explicitamente itens indisponíveis, sem crash;
- ter uma lógica de estado testável sem um player real.

### 8.6 EditCompositionPlanner

Antes de tocar AVFoundation, construir um plano puro e testável:

```swift
struct EditCompositionPlan: Equatable, Sendable {
    let canvas: EditCanvas
    let renderWidth: Int
    let renderHeight: Int
    let frameRate: Int
    let segments: [EditCompositionSegment]
    let totalDuration: TimeInterval
}
```

Cada segmento traz item, início acumulado, duração e informações suficientes para calcular a transformação aspect fit.

Validações:

- timeline não vazia;
- nenhum item indisponível;
- todos os assets possuem vídeo e duração válida;
- duração acumulada sem gaps;
- ordem exatamente igual ao documento;
- canvas e frame rate fixados conforme o MVP.

### 8.7 EditVideoComposer

Responsabilidade: transformar o plano e os assets em MP4.

```swift
public protocol EditVideoComposing: Sendable {
    func export(
        project: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        outputURL: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL

    func cancel() async
}
```

Implementação AVFoundation:

- usar `AVMutableComposition` para concatenar tracks;
- inserir vídeo na posição acumulada;
- inserir áudio quando existir;
- usar `AVMutableVideoComposition` para render size e transformações;
- calcular o tamanho orientado a partir de `naturalSize` + `preferredTransform`;
- normalizar translação negativa causada pela transformação de orientação;
- escalar por `min(canvasWidth/sourceWidth, canvasHeight/sourceHeight)`;
- centralizar no canvas;
- usar corte seco entre segmentos;
- exportar em `.mp4` com preset compatível;
- observar progresso sem polling bloqueante;
- respeitar cancelamento;
- validar o arquivo resultante antes de publicá-lo.

Não adaptar `TimelapseVideoRenderer` para essa finalidade. Os dois serviços têm entradas e responsabilidades diferentes.

## 9. UX e telas

### 9.1 Home

Modificar o layout para três módulos sem comprimir excessivamente os cards:

- portrait: grid adaptável ou dois cards + terceiro em nova linha;
- landscape: três cards lado a lado quando houver largura;
- manter ações Criar e Projetos;
- adicionar labels de acessibilidade para Edit;
- atualizar o teste que hoje assume somente dois cards na mesma linha.

### 9.2 Lista de projetos Edit

Reutilizar a estrutura de lista existente:

- projeto mais recente em destaque;
- projetos ativos e arquivados;
- contagem de clips usando `ProjectSummary.mediaCount`;
- thumbnail pode ser ausente inicialmente;
- criar projeto com prefixo `Edit`;
- excluir projeto remove apenas `edit.json` e exports daquele projeto, nunca mídias-fonte.

### 9.3 Tela principal do projeto Edit

Estrutura sugerida:

```text
Navigation title
Preview 16:9 ou 9:16
Controles play/pause/reiniciar
Timeline ordenável
[+ Adicionar mídia]
[Exportar]
```

Estados explícitos:

- carregando projeto;
- timeline vazia;
- pronta;
- salvando;
- erro de persistência;
- mídia ausente;
- preparando preview;
- exportando.

### 9.4 Seletor de mídia

- Sheet ou full-screen cover.
- Barra de filtros de origem e tipo.
- Menu de projeto-fonte opcional.
- Grid/lista lazy.
- Seleção múltipla.
- Indicação de quantidade selecionada.
- Botão Adicionar.
- Desabilitar confirmação sem seleção.
- Mostrar mais de um render Astro da mesma sessão separadamente.

### 9.5 Exportação

- Mostrar nome do arquivo.
- Permitir escolher Horizontal ou Vertical.
- Informar `1080p • 30 fps • MP4` como configuração fixa.
- Mostrar duração estimada.
- Alertar sobre clips ausentes antes de iniciar.
- Mostrar overlay de progresso e botão Cancelar.
- Após sucesso, oferecer Compartilhar e Concluir.

## 10. Estratégia TDD por fase

Cada fase possui testes RED obrigatórios, implementação GREEN mínima e um gate de conclusão.

### Fase 0 — Baseline e characterization

Objetivo: proteger o comportamento atual antes de adicionar o terceiro módulo.

Testes a escrever ou confirmar:

1. Fixtures v2/v3 de Astro e Repeatable continuam decodificando.
2. `ProjectCatalog.rebuild` encontra os dois módulos existentes.
3. `ProjectStore` continua enriquecendo seus summaries.
4. `SessionCatalog` caracteriza:
   - `timelapse.mp4`;
   - `video.mov`;
   - pelo menos um `astro.mp4`.
5. A home atual abre e expõe ações Astro/Repeatable.

Gate:

- Suíte atual verde antes de alterar enums ou switches.

### Fase 1 — Terceiro módulo e persistência básica

RED:

- decode/encode de `ProjectModule.edit`;
- nome default `Edit yyyy-MM-dd HH:mm`;
- create/load/archive de projeto Edit;
- codec de `edit.json` vazio e com itens;
- rejeição de schema não suportado;
- `EditProjectCatalog.loadOrCreate`;
- append permite mídia repetida com item IDs diferentes;
- move para início, meio e fim;
- remove existente e comportamento para ID ausente;
- persistência sobrevive a nova instância do catálogo;
- JSON inválido não é sobrescrito.

GREEN:

- adicionar modelos, codec e catálogo mínimos;
- corrigir todos os switches exaustivos;
- atualizar nome e diretório do `ProjectCatalog`;
- impedir que `ProjectStore.enrichLegacySummaries` trate Edit como sessão de captura;
- derivar `ProjectSummary.mediaCount` da timeline Edit.

Arquivos esperados:

- modificar `ios/CameraeCore/ProjectModels.swift`;
- modificar `ios/CameraeCore/ProjectCatalog.swift`;
- criar `ios/CameraeCore/MediaAssetModels.swift`;
- criar `ios/CameraeCore/EditModels.swift`;
- criar `ios/CameraeCore/EditProjectCodec.swift`;
- criar `ios/CameraeCore/EditProjectCatalog.swift`;
- modificar `ios/Camerae/ProjectStore.swift`;
- criar testes em `ios/CameraeCoreTests/`;
- atualizar integration tests de `ProjectStore`.

Gate:

- Core e integration tests verdes;
- projetos antigos ainda carregam;
- projeto Edit persiste vazio e com timeline.

### Fase 2 — Catálogo global de mídias

RED:

- encontra Repeatable `timelapse.mp4`;
- encontra Repeatable `video.mov`;
- encontra todos os `astro.mp4` em múltiplos renders;
- ignora arquivo zero-byte;
- marca/rejeita vídeo sem track de vídeo;
- inclui projeto-fonte arquivado;
- ignora projetos Edit como fonte;
- gera IDs determinísticos;
- resolve referência após criar uma nova instância;
- rejeita `relativePath` com fuga do diretório;
- ordena por data e ID;
- filtros de origem, tipo e projeto funcionam em todas as combinações;
- cancelamento não publica snapshot parcial.

GREEN:

- implementar modelos de snapshot e filtro em Core;
- implementar catálogo e probe em Media;
- criar fixtures temporárias de diretórios;
- gerar vídeos mínimos nos testes com AVAssetWriter, evitando binários grandes no Git.

Arquivos esperados:

- criar `ios/CameraeCore/MediaLibraryModels.swift`;
- criar `ios/CameraeMedia/MediaAssetProbe.swift`;
- criar `ios/CameraeMedia/MediaLibraryCatalog.swift`;
- criar testes em `ios/CameraeCoreTests/` e `ios/CameraeMediaTests/`.

Gate:

- snapshot real apresenta todas as três classes de mídia;
- nenhuma enumeração acontece em uma View;
- filtros são funções puras e cobertas.

### Fase 3 — Thumbnails e seletor

RED:

- decoder composto mantém thumbnail de imagem existente;
- decoder de vídeo aplica orientação;
- request repetida é deduplicada pelo pipeline;
- mudança de arquivo invalida cache;
- view model filtra sem recarregar o catálogo;
- seleção múltipla mantém IDs estáveis;
- confirmar adiciona na ordem escolhida.

GREEN:

- implementar decoder de vídeo;
- integrar ao pipeline existente;
- criar `EditLibraryViewModel`;
- construir seletor de mídia;
- adicionar estado de loading, vazio e erro.

Gate:

- seletor abre com scroll fluido;
- filtros não iniciam nova varredura;
- adicionar persiste a timeline.

### Fase 4 — Home, lista e timeline

RED:

- `CameraModule.edit` possui título, subtítulo, prefixo e símbolo;
- home expõe Criar/Projetos Edit;
- layout continua utilizável em portrait e landscape;
- runtime encaminha `.edit` para a tela correta;
- view model carrega documento e resolve itens;
- reordenação atualiza modelo antes de persistir;
- falha de persistência restaura estado ou mostra erro sem perder o documento anterior;
- mídia repetida aparece como duas ocorrências;
- mídia ausente aparece como indisponível.

GREEN:

- adaptar home para três cards;
- integrar Edit a create/list/archive/delete;
- criar tela principal e timeline reordenável;
- adicionar sheet do seletor;
- atualizar summary depois de mudanças na timeline.

Arquivos esperados:

- modificar `ios/Camerae/AppRootView.swift` ou extrair views Edit;
- modificar `ios/Camerae/ProjectStore.swift`;
- criar `ios/Camerae/EditProjectRuntimeView.swift`;
- criar `ios/Camerae/EditProjectViewModel.swift`;
- criar `ios/Camerae/EditMediaPickerView.swift`;
- criar `ios/Camerae/EditTimelineView.swift`;
- atualizar integration/UI tests.

Gate:

- jornada criar → selecionar → ordenar → fechar → reabrir mantém ordem;
- exclusão do projeto Edit não toca fontes.

### Fase 5 — Preview sequencial

RED:

- máquina de estados: idle → preparing → ready → playing;
- pause mantém item atual;
- fim de item avança para a próxima ocorrência;
- fim da fila produz `.finished`;
- replay volta ao primeiro item;
- reordenação reconstrói a fila;
- remoção do item atual é tratada;
- item ausente gera estado explícito;
- teardown remove observers e cancela tasks.

GREEN:

- implementar coordinator com seam de player testável;
- integrar `VideoPlayer` ou camada equivalente;
- sincronizar destaque da timeline.

Gate:

- sequência toca na ordem sem gerar arquivo intermediário;
- sair e entrar da tela não duplica observers nem áudio.

### Fase 6 — Composição e exportação

RED — planner puro:

- timeline vazia falha;
- mídia ausente falha listando os itens;
- dois clips geram posições acumuladas sem gap;
- duração total é a soma com tolerância CMTime;
- ordem é preservada;
- canvas horizontal e vertical têm dimensões corretas;
- aspect fit landscape→portrait e portrait→landscape;
- transformações com rotação de 90/180/270 graus permanecem dentro do canvas.

RED — integração AVFoundation:

- exporta um clip MP4;
- exporta MP4 + MOV;
- exporta dois clips coloridos e a amostragem de frames confirma a ordem;
- duração do arquivo final corresponde ao plano dentro da tolerância;
- dimensões finais são 1920×1080 ou 1080×1920;
- saída possui track de vídeo;
- áudio é preservado quando presente;
- fonte sem áudio não cria erro;
- arquivo final é maior que zero e reproduzível;
- cancelamento não publica arquivo final;
- falha não substitui export anterior válido.

GREEN:

- implementar planner;
- implementar composer AVFoundation;
- integrar tela de exportação, progresso, cancelamento e ShareSheet;
- persistir apenas o caminho relativo do último export.

Arquivos esperados:

- criar `ios/CameraeMedia/EditCompositionPlan.swift`;
- criar `ios/CameraeMedia/EditVideoComposer.swift`;
- criar `ios/Camerae/EditExportView.swift`;
- criar `ios/Camerae/EditExportViewModel.swift`;
- adicionar testes Media e integração.

Gate:

- jornada P0 completa exporta um MP4 válido;
- nenhum temporário permanece após sucesso, erro ou cancelamento.

### Fase 7 — Resiliência, performance e acabamento

RED:

- 500 descriptors filtram sem I/O adicional;
- referências ausentes são reportadas em lote;
- refresh reconcilia mídia restaurada;
- scroll não dispara probes repetidos;
- exportação bloqueia com mensagem acionável se falta espaço ou mídia;
- app continua responsivo durante inventário e exportação.

GREEN:

- cachear snapshot e invalidar por geração/refresh explícito;
- limitar concorrência de probes e thumbnails;
- adicionar estimativa conservadora de espaço;
- melhorar acessibilidade e localization-ready strings;
- documentar formato e recuperação.

Gate:

- performance tests registrados;
- UI tests P0 verdes;
- build sem warnings novos da feature.

## 11. Matriz mínima de testes

| Prioridade | Camada | Caso |
|---|---|---|
| P0 | Core | manifests Astro/Repeatable antigos continuam decodificando |
| P0 | Core | projeto Edit create/load/archive/rebuild |
| P0 | Core | edit.json encode/decode e persistência da ordem |
| P0 | Core | mesma mídia pode aparecer duas vezes |
| P0 | Core | filtros origem/tipo/projeto |
| P0 | Media | descoberta das três classes de mídia |
| P0 | Media | múltiplos renders Astro |
| P0 | Media | path traversal rejeitado |
| P0 | App | criar Edit e reabrir timeline |
| P0 | Media | export final preserva ordem e duração |
| P0 | Media | horizontal/vertical e orientação |
| P0 | Media | cancelamento não publica parcial |
| P0 | UI | criar → selecionar → ordenar → exportar |
| P1 | Media | áudio preservado |
| P1 | Media | thumbnail orientado e cacheado |
| P1 | App | fonte apagada aparece indisponível |
| P1 | App | falha de save não perde estado válido anterior |
| P1 | Performance | 500 assets sem I/O durante filtros |
| P2 | Performance | memória durante export longo |

## 12. Fixtures de teste

Evitar adicionar vídeos grandes ao repositório. Criar helpers de teste que geram assets determinísticos:

- `red-landscape.mp4`: 320×180, 1 s, sem áudio;
- `blue-portrait.mp4`: 180×320, 1 s, sem áudio;
- `green-with-audio.mov`: 320×180, 1 s, áudio simples;
- arquivo zero-byte;
- arquivo com extensão MP4 mas conteúdo inválido.

Gerar em diretório temporário com AVAssetWriter. Os frames coloridos permitem verificar ordem com `AVAssetImageGenerator` sem comparação visual manual.

Datas, UUIDs e nomes devem usar `FixedDateProvider` e `FixedIDProvider`.

## 13. Tratamento de erros esperado

Erros devem ser tipados nas camadas internas e traduzidos para mensagens na aplicação.

Casos mínimos:

- projeto não é Edit;
- edit.json ausente, inválido ou incompatível;
- item não encontrado para mover/remover;
- referência insegura;
- projeto/session fonte ausente;
- arquivo ausente ou vazio;
- vídeo ilegível ou sem track de vídeo;
- timeline vazia;
- armazenamento insuficiente;
- exportador indisponível;
- exportação falhou;
- exportação cancelada.

Cancelamento não deve aparecer como alerta de erro genérico.

## 14. Performance e concorrência

- `MediaLibraryCatalog` deve ser actor.
- O snapshot é carregado uma vez por abertura/refresh, não por filtro.
- Filtros trabalham somente em memória.
- Probes de AVFoundation têm concorrência limitada.
- Thumbnails reutilizam o limite já existente.
- Views recebem snapshots imutáveis.
- Publicação de estado ocorre na `MainActor`; I/O não.
- `Task.checkCancellation()` em loops de projetos, sessões e renders.
- Export deve liberar assets/player ao concluir.
- Não manter `UIImage` ou frames completos na timeline.
- Não pré-carregar todos os vídeos no player; manter uma janela pequena se `AVQueuePlayer` demonstrar uso excessivo de memória.

## 15. Integridade e segurança de caminhos

Ao resolver `relativePath`:

1. obter o diretório do `ProjectRecord` fonte;
2. anexar o caminho relativo;
3. padronizar ambas as URLs;
4. garantir que o arquivo resolvido permaneça dentro do diretório fonte;
5. rejeitar symlink ou resolução externa quando aplicável;
6. confirmar existência e regular file;
7. nunca aceitar caminho arbitrário vindo diretamente da UI.

Exclusão do projeto Edit só pode remover seu próprio diretório validado sob `Camerae Projects/edit`.

## 16. Alterações de composição e XcodeGen

Novos arquivos dentro dos diretórios já configurados devem pertencer aos targets corretos:

- modelos/catálogos/codecs → `CameraeCore`;
- AVFoundation/thumbnails/composer → `CameraeMedia`;
- views/view models/coordinator UI → `Camerae`;
- testes nos targets correspondentes.

Se `CameraePerformanceTests` medir Media, adicionar dependência de `CameraeMedia` em `ios/project.yml`.

Após modificar estrutura/targets:

```sh
cd ios
xcodegen generate
pod install
```

Sempre compilar pelo workspace, pois Firebase e OpenCV vêm de CocoaPods.

## 17. Comandos de validação

Descobrir primeiro um Simulator disponível se o nome configurado localmente diferir.

Suíte principal:

```sh
cd ios
xcodebuild \
  -workspace Camerae.xcworkspace \
  -scheme Camerae \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

UI:

```sh
cd ios
xcodebuild \
  -workspace Camerae.xcworkspace \
  -scheme CameraeUI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

Performance:

```sh
cd ios
xcodebuild \
  -workspace Camerae.xcworkspace \
  -scheme CameraePerformance \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

Build genérico sem signing:

```sh
cd ios
xcodebuild \
  -workspace Camerae.xcworkspace \
  -scheme Camerae \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 18. Estratégia de commits/PRs

Não misturar todas as fases.

1. `Add Edit domain and manifest persistence`
2. `Add global produced-media catalog`
3. `Add video thumbnail support and media picker`
4. `Add Edit project timeline workflow`
5. `Add sequential Edit preview`
6. `Add MP4 composition and export`
7. `Harden Edit recovery and performance`

Cada commit deve:

- conter os testes que motivaram a mudança;
- deixar a suíte relevante verde;
- não conter assets gerados ou DerivedData;
- não incluir refatorações não relacionadas.

## 19. Critérios de aceite do MVP

O MVP está concluído somente quando todos os itens abaixo forem verdadeiros:

- [ ] Home possui Astro, Repeatable e Edit com acessibilidade correta.
- [ ] Projetos existentes continuam abrindo sem migração destrutiva.
- [ ] É possível criar e reabrir um projeto Edit.
- [ ] Biblioteca encontra Repeatable timelapse, vídeo gravado e todos os renders Astro.
- [ ] Filtros não causam nova varredura de disco.
- [ ] Uma mídia pode ser usada mais de uma vez.
- [ ] Ordem e remoções persistem após relaunch.
- [ ] Nenhuma mídia original é copiada, movida ou alterada.
- [ ] Preview toca a sequência na ordem.
- [ ] Timeline sinaliza fontes ausentes sem crash.
- [ ] Exportação horizontal e vertical gera MP4 1080p/30 válido.
- [ ] Clips de orientações diferentes usam aspect fit sem crop.
- [ ] Áudio existente é preservado.
- [ ] Cancelamento e falha não deixam arquivo final parcial.
- [ ] Compartilhamento funciona com o MP4 final.
- [ ] Core, Media, Integration e UI tests P0 estão verdes.
- [ ] Nenhuma operação proporcional à biblioteca ocorre na `MainActor`.

## 20. Ordem operacional resumida para o LLM

Executar exatamente nesta ordem:

1. Ler os arquivos atuais citados na seção 4 e executar os testes baseline.
2. Criar characterization tests antes de adicionar `.edit`.
3. Implementar Fase 1 e parar para validar Core/Integration.
4. Implementar Fase 2 e parar para validar Core/Media.
5. Implementar Fases 3 e 4 e validar jornada persistente sem preview/export.
6. Implementar Fase 5 e validar preview.
7. Implementar Fase 6 e validar arquivos reais gerados nos testes.
8. Implementar Fase 7 apenas depois da jornada P0 estar verde.
9. Executar todas as suítes e revisar `git diff` por escopo e arquivos gerados.
10. Relatar o que foi implementado, testes executados, riscos restantes e qualquer desvio deste contrato.

Se uma fase revelar uma limitação estrutural, fazer a menor alteração necessária e registrar o motivo. Não expandir silenciosamente o escopo do produto.
