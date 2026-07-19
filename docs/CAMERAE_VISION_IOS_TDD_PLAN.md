# Camerae Vision — plano TDD de integração no iOS

Status: pronto para execução em fases pequenas

Versão-alvo sugerida: Camerae 8.0

Escopo: integrar o módulo C++ `camerae_vision` ao pipeline de captura do iOS, inicialmente como apoio opcional ao reenquadramento. Interface visual e integração Android permanecem em fases separadas.

## 1. Resultado esperado

Ao final deste plano, o Camerae no iOS poderá avaliar, durante a prévia da câmera, se o enquadramento atual está suficientemente próximo de uma imagem de referência e se a diferença parece corrigível sem deformação excessiva.

O componente deverá:

- reutilizar o `AVCaptureVideoDataOutput` já existente;
- executar o preset C++ `CaptureFast` do Camerae Vision;
- permanecer desligado por padrão durante a implantação inicial;
- nunca bloquear captura, preview, gravação ou escrita de foto;
- descartar trabalho antigo em vez de formar fila;
- pausar ou reduzir carga conforme captura, temperatura e energia;
- retornar `accept`, `review` ou `reject`, métricas e reason codes tipados;
- permitir comparar OpenCV e Apple Vision antes de escolher o padrão;
- manter o núcleo C++ compartilhável com Android.

Esta etapa não deve aplicar warp na imagem capturada. Avaliar alinhamento durante a captura e alinhar/renderizar a foto final são capacidades diferentes.

## 2. O que já existe e deve ser preservado

### 2.1 No app iOS

`CameraController` já:

- possui `AVCapturePhotoOutput`, `AVCaptureMovieFileOutput` e `AVCaptureVideoDataOutput` na mesma sessão;
- recebe `CMSampleBuffer` em uma fila serial dedicada;
- solicita frames BGRA;
- usa `alwaysDiscardsLateVideoFrames = true`;
- limita a frequência da análise visual;
- registra a referência contra o frame corrente com `VNHomographicImageRegistrationRequest`;
- publica `VisualAlignmentEstimate` para a interface Repeatable;
- contém pontos de pausa naturais, como captura de foto, gravação e troca de lente.

Não criar um segundo `AVCaptureVideoDataOutput` e não mover processamento pesado para o callback de captura.

### 2.2 No Camerae Vision

O módulo desktop C++ já oferece:

- preset `CaptureFast`, limitado a 640 px e ORB/1200 features;
- comparação conservadora entre similaridade e afim;
- cache de features da referência;
- sessão reutilizável e cancelável;
- diagnósticos de memória e contadores;
- decisões `accept`, `review` e `reject`;
- reason codes estáveis com schema versionado;
- simulador de cadência e backpressure latest-only;
- benchmark e testes de regressão.

O iOS deve consumir esse módulo. Não copiar o algoritmo para Swift e não reimplementá-lo dentro do bridge Astro existente.

### 2.3 OpenCV atualmente no iOS

O app usa o CocoaPod `OpenCV2 4.3.0` no processamento Astro. Essa distribuição não contém o slice arm64 do Simulator, e por isso o `OpenCVBridge` atual possui um stub no Simulator.

O núcleo Camerae Vision desktop foi validado com OpenCV 4.13. Misturar versões silenciosamente criaria diferenças de algoritmo, compilação e testes entre desktop, iOS e Android.

Decisão: a integração nova não deve assumir que o pod 4.3 é suficiente. A primeira fase técnica compara e fecha o empacotamento, com preferência por um XCFramework reproduzível e fixado na mesma versão do módulo compartilhado.

## 3. Decisões de arquitetura

### 3.1 Limites de responsabilidade

```text
AVCaptureVideoDataOutput
          |
          v
CameraeVisionCaptureCoordinator (Swift)
  - feature flag e configuração
  - cadência e latest-only
  - ciclo de vida e geração
  - energia, temperatura e pausas
          |
          v
CameraeVisionBridge (Objective-C++)
  - CVPixelBuffer -> cv::Mat temporário
  - orientação e conversão de tipos
  - erros e DTOs Objective-C
          |
          v
camerae_vision (C++)
  - sessão CaptureFast
  - cache da referência
  - decisão, métricas e reason codes
          |
          v
OpenCV fixado
```

Regras:

- Swift controla quando o trabalho pode acontecer.
- Objective-C++ traduz memória e tipos, sem conter regras de produto.
- C++ controla o algoritmo, thresholds e cache de visão.
- SwiftUI apenas observa um snapshot de domínio; não chama OpenCV.
- `CameraController` fornece eventos e frames, mas não deve acumular a nova lógica de scheduler.

### 3.2 Bridge separado

Criar `CameraeVisionBridge.h/.mm`. Não ampliar `OpenCVBridge.h/.mm`, que pertence ao pipeline Astro e trabalha com caminhos de arquivos e render final.

O bridge novo deve receber pixels em memória. Não converter frame ao vivo para `UIImage`, JPEG ou HEIC.

Contrato inicial proposto:

```objc
typedef NS_ENUM(NSInteger, CEVAlignmentDecision) {
    CEVAlignmentDecisionAccept,
    CEVAlignmentDecisionReview,
    CEVAlignmentDecisionReject,
    CEVAlignmentDecisionUnavailable
};

@interface CEVCaptureAlignmentResult : NSObject
@property(nonatomic, readonly) NSInteger schemaVersion;
@property(nonatomic, readonly) CEVAlignmentDecision decision;
@property(nonatomic, readonly) double score;
@property(nonatomic, readonly) double overlapRatio;
@property(nonatomic, readonly) double reprojectionRMSE;
@property(nonatomic, readonly) double edgeAlignmentError;
@property(nonatomic, readonly) double latencyMilliseconds;
@property(nonatomic, copy, readonly) NSString *selectedModel;
@property(nonatomic, copy, readonly) NSArray<NSString *> *reasonCodes;
@property(nonatomic, copy, readonly) NSArray<NSNumber *> *transform3x3;
@end
```

O formato exato nasce nos testes de contrato da Fase 2. Mensagens localizadas não atravessam o bridge; somente códigos estáveis.

### 3.3 Pixel buffer e lifetime

Para BGRA:

1. validar formato, dimensões e orientação;
2. obter o `CVPixelBuffer` do `CMSampleBuffer`;
3. reter somente se o trabalho realmente for admitido;
4. no worker, chamar `CVPixelBufferLockBaseAddress` com `.readOnly`;
5. construir um `cv::Mat` temporário usando `baseAddress`, largura, altura e `bytesPerRow` reais;
6. normalizar orientação e reduzir cedo para o limite do `CaptureFast`;
7. terminar todo uso do `cv::Mat` antes do unlock/release.

Nenhum `cv::Mat` pode guardar ponteiro para o pixel buffer depois do unlock. A referência preparada pode ser copiada/reduzida e mantida pela sessão C++.

### 3.4 Backend comparável

Durante a adoção, usar uma abstração Swift interna:

```swift
enum VisualAlignmentBackend {
    case appleVision
    case cameraeVisionOpenCV
}

protocol VisualAlignmentEvaluating: Sendable {
    func updateReference(_ reference: VisualAlignmentReference?) async
    func evaluate(_ frame: VisualAlignmentFrame) async -> VisualAlignmentSnapshot
    func cancel() async
}
```

O protocolo é de domínio, não expõe `cv::Mat` nem tipos do Vision framework. O backend Apple atual permanece disponível para baseline, shadow mode e rollback.

## 4. Política de execução durante a captura

### 4.1 Admissão barata

O callback `captureOutput(_:didOutput:from:)` somente:

- valida se o componente está habilitado e apto;
- verifica se a cadência venceu;
- entrega o buffer ao coordinator;
- retorna imediatamente.

Meta provisória: menos de 1 ms de trabalho síncrono no callback, medido em aparelho.

### 4.2 Backpressure

Estado máximo:

- uma avaliação em execução;
- um frame pendente, sempre o mais recente;
- zero fila adicional.

Quando chega um frame novo e já existe um pendente, o anterior é liberado e contabilizado como substituído. Resultados carregam `generation`, timestamp da referência e timestamp do frame. Resultado de geração antiga é descartado.

### 4.3 Cadências

Usar inicialmente os contratos já definidos no C++:

| Perfil | Cadência inicial | Uso |
| --- | ---: | --- |
| conservative | 1 Hz | low power ou aparelho abaixo do baseline |
| balanced | 2 Hz | padrão experimental |
| responsive | 4 Hz | ajuste fino, somente se o budget permitir |

Esses valores são hipóteses para teste, não compromisso final de produto.

### 4.4 Pausas e degradação

Pausar e cancelar trabalho pendente em:

- captura e escrita de foto;
- processamento Astro pesado;
- troca de lente ou reconfiguração da sessão;
- app em background/inativo;
- ausência ou troca de referência;
- thermal state `serious` ou `critical`;
- memory warning;
- encerramento do coordinator.

Em Low Power Mode, iniciar com perfil `conservative`; permitir desligamento total se os testes mostrarem impacto relevante. Em thermal `fair`, reduzir um nível. A captura sempre tem prioridade sobre o auxílio visual.

Gravação de vídeo deve começar com o avaliador pausado. Habilitá-lo durante gravação exigirá uma decisão futura baseada em métricas próprias.

### 4.5 Falhas

- OpenCV indisponível: manter captura funcionando e publicar estado `unavailable`.
- Falha pontual de análise: não bloquear nem trocar automaticamente o estado visual por um falso alinhamento.
- Falhas consecutivas: aplicar cooldown e diagnóstico.
- Bridge incompatível/schema desconhecido: desabilitar o backend OpenCV.
- Feature flag desligada: não criar sessão, worker ou cache da referência.

## 5. Estratégia de empacotamento

### Recomendação

Produzir um `opencv2.xcframework` fixado por tag/commit e um target iOS do `camerae_vision`, ambos reproduzíveis. O script oficial do OpenCV para Apple cria XCFramework com slices separados para iPhoneOS e iPhoneSimulator.

Slices mínimos:

- iPhoneOS arm64;
- iPhoneSimulator arm64;
- iPhoneSimulator x86_64 somente se ainda necessário na CI.

O build deve limitar módulos OpenCV ao necessário para Camerae Vision e Astro, depois de um inventário real de includes. A redução de módulos não pode quebrar o pipeline Astro existente.

### Spike obrigatório antes da escolha definitiva

Comparar:

| Opção | Vantagem | Risco | Posição inicial |
| --- | --- | --- | --- |
| CocoaPod OpenCV2 4.3 atual | nenhuma mudança imediata no Astro | antigo, sem arm64 Simulator, divergente do desktop | não recomendado para Camerae Vision |
| XCFramework próprio fixado | paridade, slices corretos, build controlado | script e artefato precisam manutenção | recomendado |
| binary target SwiftPM | consumo simples depois de pronto | distribuição/versionamento adicionam trabalho agora | avaliar após o XCFramework |

Critérios do spike:

- build de Simulator e generic iOS device;
- versão OpenCV única e exposta em runtime;
- testes C++ do Camerae Vision compilados para iOS;
- Astro continua compilando e seus testes permanecem verdes;
- tamanho do app e do download registrado antes/depois;
- licenças e notices revisados;
- hash do artefato e comando de reprodução documentados.

## 6. Processo TDD obrigatório

Cada fase segue este ciclo:

1. **CHARACTERIZE**, quando tocar comportamento existente: congelar o que deve ser preservado.
2. **RED:** adicionar o menor teste relevante e demonstrar que falha pela razão esperada.
3. **GREEN:** implementar somente o necessário para o teste passar.
4. **REFACTOR:** remover duplicação e ajustar nomes sem alterar comportamento.
5. **GATE:** executar testes da fase, suíte afetada e verificações de arquitetura/performance.
6. **STOP:** registrar resultado e parar antes da próxima fase.

Regras de PR/commit:

- nenhuma regra nova de scheduler nasce apenas dentro de `CameraController`;
- bug encontrado começa com teste reproduzindo o problema;
- teste não pode depender de `sleep` real para cadência;
- clock, executor, energia, thermal state e backend devem ser injetáveis;
- teste de performance no Simulator é alarme, não orçamento final;
- orçamento final somente é aprovado em aparelho físico fixado;
- não alterar threshold C++ para fazer um teste iOS passar sem atualizar a regressão compartilhada.

## 7. Fases de implementação

Cada fase abaixo é uma entrega independente para um modelo Fast. Não antecipar a fase seguinte.

### Fase 0 — baseline e characterization do alinhamento atual

Objetivo: congelar o contrato Apple Vision e a composição atual da câmera.

CHARACTERIZE:

- registrar saídas atuais para matrizes conhecidas antes da extração;
- registrar baseline de frames entregues/descartados, tamanho, memória, FPS da preview e latência de captura em ao menos um iPhone.

RED:

- testar a conversão de `VNImageHomographicAlignmentObservation` para o snapshot atual;
- testar orientação, escala, rotação, inversão da matriz e guides;
- testar referência ausente e análise com confiança insuficiente;
- adicionar teste de composição contra o protocolo `VisualAlignmentEvaluating`, que inicialmente não existe.

GREEN:

- extrair funções puras de transformação para um tipo testável;
- introduzir o protocolo `VisualAlignmentEvaluating` sem mudar o backend em produção.

REFACTOR:

- remover duplicação criada pela extração;
- manter os mesmos thresholds, cadência e snapshots públicos.

Gate:

- comportamento visual atual preservado;
- testes antigos e novos verdes;
- baseline em ao menos um iPhone registrado;
- zero OpenCV novo no app.

### Fase 1 — spike de build iOS e XCFramework

Objetivo: provar paridade de compilação antes de criar a integração de runtime.

RED:

- teste/script falha se o framework não tiver iPhoneOS arm64 e iPhoneSimulator arm64;
- teste falha se a versão OpenCV compilada divergir da versão fixada;
- smoke test C++ iOS instancia `CaptureAlignmentSession` com imagem sintética.

GREEN:

- criar script reproduzível de build do XCFramework;
- compilar somente os módulos confirmados necessários;
- criar target/biblioteca `CameraeVision` para iOS sem ligá-lo ao `CameraController`;
- incluir notices e manifest/hash do binário.

REFACTOR:

- centralizar tag, arquiteturas e módulos em uma única configuração versionada;
- remover flags duplicadas entre build local, CI e release gate.

Gate:

- Simulator Apple Silicon e generic iOS device compilam sem stub;
- smoke test roda no Simulator;
- build device linka sem assinatura;
- tamanho antes/depois documentado;
- pipeline Astro não regrediu.

### Fase 2 — bridge Objective-C++ por contrato

Objetivo: traduzir `CVPixelBuffer` e resultados, ainda sem câmera ao vivo.

RED:

- pixel buffer BGRA sintético com `bytesPerRow` maior que `width * 4`;
- dimensões ímpares e pequenas;
- referência e frame com orientações diferentes;
- buffer nulo, formato não suportado e lock failure;
- `cancel`, `resume` e `updateReference`;
- schema, decisão, matriz e reason codes preservados;
- prova de que nenhum ponteiro é usado depois do unlock.

GREEN:

- implementar `CameraeVisionBridge` e DTOs imutáveis;
- usar lock/unlock `.readOnly` balanceado;
- criar, atualizar, avaliar e cancelar uma sessão C++;
- mapear exceções C++ para `NSError` estável.

REFACTOR:

- centralizar guards de lifetime e mapeamentos de enum;
- manter conversão de pixels separada do gerenciamento da sessão.

Gate:

- testes do bridge verdes no Simulator;
- Address Sanitizer verde no target de testes aplicável;
- nenhuma dependência em `UIKit` ou arquivo codificado no fast path;
- bridge não contém regras de cadência ou UI.

### Fase 3 — coordinator Swift e scheduler determinístico

Objetivo: implementar toda a política de execução sem usar câmera real.

RED:

- disabled cria zero backend/workers;
- cadências 1/2/4 Hz com clock virtual;
- uma execução + um pending latest-only;
- substituição libera o frame anterior;
- resultado de geração antiga é ignorado;
- update de referência invalida exatamente uma vez;
- pausa/resume por captura, lente, lifecycle, thermal e low power;
- cancelamento e deinit liberam buffers;
- erro consecutivo aciona cooldown;
- backend lento nunca aumenta a fila.

GREEN:

- criar `CameraeVisionCaptureCoordinator` com dependências injetadas;
- usar executor serial dedicado ou actor, fora da MainActor;
- publicar snapshots imutáveis na MainActor;
- adicionar diagnósticos de admitted, analyzed, replaced, failed e stale.

REFACTOR:

- separar máquina de estado/policy dos efeitos do executor;
- remover condições duplicadas de pausa e geração.

Gate:

- suíte inteira usa clock virtual, sem sleeps;
- Thread Sanitizer verde no conjunto aplicável;
- disabled path comprovadamente não instancia OpenCV;
- coordinator não conhece SwiftUI nem `CameraController` concreto.

### Fase 4 — integração shadow no pipeline existente

Objetivo: alimentar o coordinator com o `AVCaptureVideoDataOutput` atual, sem mudar a UI nem a decisão de produção.

RED:

- integration test prova que o callback somente admite e retorna;
- captura de foto pausa e depois retoma;
- troca de lente incrementa geração e descarta resultado antigo;
- background cancela pending;
- `didDrop` registra motivo e não dispara nova análise;
- backend indisponível preserva captura e Apple Vision.

GREEN:

- injetar o coordinator no `CameraController`;
- encaminhar somente frames admitidos;
- instrumentar callback, bridge e avaliação com signposts;
- manter Apple Vision como resultado visível;
- guardar resultado OpenCV apenas em diagnóstico local de desenvolvimento.

REFACTOR:

- manter `CameraController` como adaptador fino de eventos;
- mover decisões de admissão remanescentes para a policy testável.

Gate:

- feature flag default `off` em Release;
- zero mudança visual;
- release gate executa testes Swift, bridge e C++ iOS;
- build Simulator e generic device verdes;
- captura manual básica continua funcionando.

### Fase 5 — validação em aparelho e budgets

Objetivo: descobrir o custo real antes de expor o backend ao usuário.

Matriz mínima:

- um iPhone mais antigo ainda suportado;
- um iPhone intermediário;
- um iPhone recente;
- lentes wide/ultrawide/tele quando disponíveis;
- retrato e paisagem;
- luz boa e baixa luz;
- referência com pouco e muito paralaxe;
- Low Power Mode;
- thermal nominal, fair e degradação simulável;
- sessão contínua de 10 minutos;
- foto durante avaliação e troca repetida de lente.

Budgets provisórios a validar:

| Métrica | Hipótese inicial |
| --- | ---: |
| trabalho síncrono no callback p95 | < 1 ms |
| avaliações concorrentes | 1 |
| pending frames | <= 1 |
| memória retida pelo componente | < 16 MB |
| CaptureFast balanced p95 | < 100 ms no aparelho baseline |
| regressão de latência de foto p95 | < 5% |
| regressão perceptível de preview | nenhuma |
| trabalho quando disabled | zero avaliações e zero cache |

RED:

- performance tests falham ao ultrapassar guardrails amplos;
- teste de longa duração detecta crescimento de memória/backlog;
- teste de captura detecta regressão de latência.

GREEN:

- ajustar cadência, tamanho de entrada e políticas de pausa;
- não reduzir qualidade da captura para cumprir o budget do auxílio;
- se necessário, desabilitar o componente em classes de aparelho não aprovadas.

REFACTOR:

- transformar valores aprovados em perfis nomeados e testáveis;
- evitar condicionais espalhadas por modelo específico de aparelho.

Gate:

- budgets finais documentados por modelo de aparelho;
- nenhum vazamento ou backlog crescente;
- thermal policy demonstrada;
- relatório compara OpenCV ligado, desligado e Apple Vision.

### Fase 6 — shadow comparison de qualidade

Objetivo: comparar resultados sem orientar o usuário pelo OpenCV.

RED:

- corpus rotulado falha se uma cena difícil for promovida para falso `accept`;
- teste falha se shadow mode alterar o snapshot visível;
- teste falha se os dois backends não receberem a mesma referência/generation;
- agregador falha ou sinaliza schema desconhecido em vez de misturar métricas incompatíveis.

GREEN:

- criar runner de comparação local, sem alterar guidance;
- normalizar apenas métricas comparáveis e preservar reason codes originais;
- produzir relatório sanitizado de qualidade e custo por backend.

Conjunto de avaliação:

- fixtures sintéticas compartilhadas;
- pares reais já usados no desktop;
- capturas guiadas no app com pouco paralaxe;
- capturas deliberadamente difíceis;
- cenas com objeto móvel, baixa textura, blur e exposição diferente.

Métricas:

- concordância de decisão;
- falsos `accept` como métrica mais crítica;
- taxa de `review` e `reject`;
- estabilidade temporal do guidance;
- overlap, erro local e cobertura;
- latência, memória, frames substituídos e energia;
- sucesso da captura de foto durante o processamento.

REFACTOR:

- separar coleta, agregação e apresentação do relatório;
- manter pixels e caminhos privados fora do relatório persistido.

Gate de promoção:

- OpenCV não aumenta falsos `accept` frente ao conjunto rotulado;
- pares de alto paralaxe permanecem `review` ou `reject`;
- pares de baixo paralaxe aprovados no desktop mantêm resultado coerente;
- custo cabe nos budgets da Fase 5;
- divergências possuem reason codes investigáveis.

### Fase 7 — backend OpenCV opcional na interface existente

Objetivo: permitir uso interno/opt-in sem redesenhar a experiência visual.

RED:

- preferência default off e migração segura;
- kill switch restaura Apple Vision sem reiniciar sessão;
- snapshot `review/reject` nunca vira guide enganoso;
- estado expirado desaparece;
- acessibilidade e localização dos estados novos.

GREEN:

- adicionar flag interna e seleção de backend;
- adaptar apenas snapshots aprovados ao `VisualAlignmentEstimate` existente;
- mostrar estado neutro quando a análise não for confiável;
- preservar Apple Vision como fallback da primeira versão.

REFACTOR:

- isolar seleção/fallback da adaptação visual;
- remover caminhos experimentais que não forem necessários para rollback.

Gate:

- rollout interno concluído;
- nenhum crash ou regressão de captura;
- rollback validado;
- produto decide, com dados, qual backend será padrão.

### Fase 8 — endurecimento e release major

Objetivo: tornar a integração parte verificável da major seguinte.

RED:

- release-gate test falha sem slices, versão/hash, testes bridge ou teste C++ iOS;
- archive test detecta framework ausente e símbolos inválidos;
- smoke test do artefato Release comprova runtime version.

GREEN:

- integrar os novos targets ao scheme, CI e `release-gate.sh`;
- documentar build reproduzível do OpenCV e cache de CI;
- adicionar checklist manual de câmera física ao RC;
- registrar métricas e decisão de rollout nas release notes.

REFACTOR:

- compartilhar as mesmas verificações entre CI e release gate;
- remover scripts temporários do spike preservando o build reproduzível final.

Gate:

- todas as suítes e builds verdes;
- device matrix aprovada;
- feature pode ser desligada sem nova versão;
- versão major é incrementada somente quando a fatia vertical está pronta para beta.

## 8. Estrutura de arquivos proposta

Os nomes podem ser ajustados durante RED/GREEN, preservando os limites:

```text
ios/
  CameraeVision/
    CameraeVisionBridge.h
    CameraeVisionBridge.mm
    CameraeVisionResult.h
  Camerae/
    VisualAlignment/
      VisualAlignmentEvaluating.swift
      VisualAlignmentSnapshot.swift
      AppleVisionAlignmentEvaluator.swift
      CameraeVisionAlignmentEvaluator.swift
      CameraeVisionCaptureCoordinator.swift
      VisualAlignmentPolicy.swift
  CameraeVisionTests/
    CameraeVisionBridgeTests.mm
    CameraeVisionCaptureCoordinatorTests.swift
    VisualAlignmentPolicyTests.swift
  CameraeIntegrationTests/
    CameraVisionCaptureIntegrationTests.swift
  scripts/
    build-opencv-xcframework.sh
    verify-opencv-xcframework.sh
```

Evitar colocar esses tipos em `CameraeCore`: tipos de `CVPixelBuffer`, AVFoundation, Vision e OpenCV pertencem à borda de plataforma. Tipos de decisão realmente neutros podem migrar para Core depois que o contrato estiver estável.

## 9. Pirâmide e matriz de testes

| Camada | Ferramenta | O que valida | Executa em PR |
| --- | --- | --- | --- |
| C++ puro | CTest | algoritmos, thresholds, cache, regressão | sim |
| Objective-C++ | XCTest | pixel buffer, lifetime, bridge e schema | sim |
| Swift unit | Swift Testing/XCTest | scheduler, estado, policy, fallback | sim |
| App integration | XCTest hosted | `CameraController` + coordinator mock/real | sim |
| Performance Simulator | XCTest/signposts | regressões explosivas | sim, guardrail amplo |
| Device performance | XCTest/instrumentação | budgets reais | RC/lab |
| Câmera física | roteiro automatizado quando possível + manual | captura, lente, lifecycle e qualidade | RC |

Fixtures não devem adicionar HEICs grandes ao Git. Criar imagens e pixel buffers sintéticos determinísticos; manter poucos pares reais sanitizados apenas se houver autorização para versioná-los. As imagens em Downloads continuam fixtures locais e não entram automaticamente no repositório.

## 10. Observabilidade

Adicionar signposts e contadores para:

- tempo do callback/admission;
- tempo de lock/conversão/redução;
- tempo C++ total e por decisão;
- frames recebidos, admitidos, substituídos e descartados pelo AVFoundation;
- erros e cooldowns;
- referência atualizada e feature extractions;
- memória estimada da sessão;
- generation/stale result;
- motivo de pausa e perfil de cadência;
- backend selecionado e versão OpenCV/Camerae Vision.

Não salvar pixels da câmera em logs. Diagnósticos persistidos devem ser opt-in, limitados, sem localização precisa e sem conteúdo visual.

## 11. Release gate e CI

O release gate já executa testes Swift, C++ Camerae Processing/Camerae Vision e build generic iOS. A integração móvel exige adicionar explicitamente:

1. verificação de slices e hash do XCFramework;
2. testes do target `CameraeVisionTests` no Simulator;
3. smoke test da versão OpenCV e schema do bridge;
4. build generic device com o bridge real, sem stub;
5. teste C++ compilado para target iOS;
6. archive/link check do artefato Release;
7. checklist separado de aparelho físico antes de Firebase/App Store.

CI de Simulator não valida câmera real, custo térmico nem energia. Ela não substitui o gate de device.

## 12. Critérios globais de pronto

A integração iOS está pronta quando:

- o app usa uma única saída de frames para preview analysis;
- Camerae Vision é módulo compartilhado e o bridge Astro continua separado;
- OpenCV tem versão fixada e build reproduzível para device/Simulator;
- disabled path não cria trabalho nem memória relevante;
- latest-only e cancelamento estão provados por testes;
- captura de foto, vídeo, Astro, troca de lente e lifecycle não regrediram;
- decisões difíceis não são apresentadas como alinhamento seguro;
- budgets foram aprovados em aparelhos físicos;
- Apple Vision pode permanecer fallback até a comparação concluir;
- release script e CI verificam a integração;
- cada fase apresenta evidência RED, GREEN, REFACTOR e gate verde.

## 13. Primeira tarefa recomendada para o modelo Fast

Executar somente a **Fase 0**.

Prompt operacional:

> Leia `docs/CAMERAE_VISION_IOS_TDD_PLAN.md`. Execute apenas a Fase 0. Use TDD: primeiro adicione characterization tests que falhem ou congelem explicitamente o comportamento atual, depois faça a extração mínima necessária para testabilidade. Não adicione OpenCV ao fluxo da câmera, não altere a UI e não avance à Fase 1. Execute a suíte afetada, registre o baseline obtido e pare com um resumo do RED/GREEN/REFACTOR.

Essa ordem reduz o risco de trocar o backend antes de sabermos exatamente o que o app já entrega e qual é o custo atual.

## 14. Referências oficiais consultadas

- Apple: [`AVCaptureVideoDataOutputSampleBufferDelegate`](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutputsamplebufferdelegate) e reporte de frames descartados.
- Apple: [`alwaysDiscardsLateVideoFrames`](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/alwaysdiscardslatevideoframes).
- Apple [TN2445](https://developer.apple.com/library/archive/technotes/tn2445/_index.html): callback eficiente, latest-only e diagnóstico de drops.
- Apple Core Video: [`CVPixelBufferLockBaseAddress`](https://developer.apple.com/documentation/corevideo/cvpixelbufferlockbaseaddress%28_%3A_%3A%29) e flag [`readOnly`](https://developer.apple.com/documentation/corevideo/cvpixelbufferlockflags/readonly).
- Apple Foundation: [`ProcessInfo`](https://developer.apple.com/documentation/foundation/processinfo), thermal state, Low Power Mode e notificações de mudança.
- Apple Vision: [`VNHomographicImageRegistrationRequest`](https://developer.apple.com/documentation/vision/vnhomographicimageregistrationrequest), usado pelo baseline atual.
- OpenCV: [instalação no iOS](https://docs.opencv.org/4.x/d5/da3/tutorial_ios_install.html), [script oficial de XCFramework](https://github.com/opencv/opencv/blob/4.x/platforms/apple/build_xcframework.py) e [release 4.13.0](https://github.com/opencv/opencv/releases/tag/4.13.0).
