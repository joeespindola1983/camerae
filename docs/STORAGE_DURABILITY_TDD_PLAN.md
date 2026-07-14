# Camerae — plano de armazenamento, durabilidade e compatibilidade orientado por TDD

Status: direção aprovada para a próxima major; recorte e calibrações finais pendentes

Versão-alvo: Camerae 5.0.0

Base: Camerae 4.0.0, tag `v4.0.0`; implementação iniciada a partir de `develop`

Escopo inicial: iOS, `CameraeCore`, `CameraeMedia` e aplicação SwiftUI

## 1. Por que isto é parte do produto

Para o Camerae, uma captura que começa sem chance razoável de terminar não é apenas um erro técnico. Ela pode desperdiçar uma noite sem nuvens, horas de bateria e uma oportunidade que não se repete. Da mesma forma, um projeto que deixa de abrir após uma atualização quebra a principal promessa dos projetos de longo prazo.

O produto deve, portanto, tratar como propriedades fundamentais:

1. **Admissão segura:** informar antes da captura se o plano cabe no dispositivo.
2. **Proteção em execução:** detectar pressão de armazenamento enquanto ainda é possível parar de forma segura.
3. **Durabilidade:** todo frame confirmado permanece recuperável após erro, cancelamento ou encerramento do app.
4. **Continuidade:** projetos criados por versões publicadas continuam legíveis e migráveis.
5. **Retenção consciente:** o usuário entende o que ocupa espaço e escolhe o que preservar.
6. **Recuperação:** índices e derivados podem ser reconstruídos sem destruir os originais.

## 2. Diagnóstico do estado atual

O repositório já oferece uma base útil:

- manifests de projeto e sessão versionados;
- gravações atômicas de JSON e frames;
- índice derivado que pode ser reconstruído a partir dos manifests;
- reparo do inventário de sessões a partir dos arquivos existentes;
- resumos com quantidade de mídia e bytes conhecidos;
- cálculo de armazenamento na tela de processamento Astro;
- teste de compatibilidade para manifests legados;
- verificação de espaço antes de exportar ZIPs de frames originais.

As lacunas que este plano deve fechar são:

- a captura em produção ainda salva JPEG diretamente por `TimelapseSessionStore` e não faz preflight de capacidade;
- o armazenamento não é reavaliado durante uma captura longa;
- não há estimativa de bytes por frame, duração suportada ou espaço de render temporário;
- o resumo de armazenamento Astro aparece depois da captura, não como ferramenta de planejamento;
- `isArchived` apenas organiza a biblioteca; não existe compactação formal de um projeto;
- não há estado persistido que diferencie originais, derivados regeneráveis, cache e artefatos finais;
- a migração tem testes iniciais, mas ainda não possui uma matriz permanente de fixtures de todas as versões publicadas, rollback e injeção de falhas;
- RAW não está implementado na captura atual. Adicioná-lo antes dos controles de capacidade aumentaria o risco.

### 2.1 Programa de qualidade para os itens do gráfico

“Crash-free” é necessário, mas não representa sozinho o sucesso do Camerae. O app pode permanecer aberto e ainda perder frames, produzir um projeto que não reabre ou falhar no último passo do export. A métrica principal deve ser **missão concluída**, segmentada por fluxo, versão, device e OS.

| Domínio | Missão bem-sucedida | Falhas que precisam de razão tipada | Evidência principal |
|---|---|---|---|
| Stability | uso termina sem crash, hang ou perda de estado confirmado | crash, hang, watchdog, encerramento inesperado, recuperação necessária | crash-free users/sessions e recovery rate |
| Capture | sessão inicia com segurança, preserva frames e termina ou para de modo recuperável | câmera indisponível/interrompida, storage, escrita, memória, temperatura, background, configuração | start rate, confirmed frames, safe-stop rate e completion rate |
| Projects | projeto salva, reabre e mantém referências/alinhamento através de versões | manifest inválido, migração, asset ausente, referência inválida, inventário divergente | reopen rate, migration rate e repair outcome |
| Export | artefato final é publicado, validado e compartilhável | capacidade, encode, cancelamento, mídia ausente, artefato vazio/truncado, publicação | completion, duração, bytes, razão de falha e validação |
| Feedback | relato pode ser ligado a um fluxo e tema sem expor a obra | tema não classificado, contexto técnico ausente, repetição | tema, fluxo afetado, versão e frequência agregada |
| Privacy | nenhum dado sensível sai sem consentimento explícito | permissão ausente, attachment inesperado, retenção indevida | consentimento por tipo de anexo e auditoria de payload |

Definir denominadores antes de dashboards. Por exemplo, `captureCompletionRate` deve distinguir uma captura concluída, uma parada segura por limite previsto e uma interrupção inesperada. Misturar essas saídas produziria um número bonito e pouco útil.

### 2.2 Análise de sistema antes de alterar código

Produzir cinco artefatos curtos e revisáveis:

1. **Mapa da missão:** planejar → admitir → capturar → checkpoint → finalizar → renderizar → exportar → arquivar/compactar → reabrir.
2. **Mapa de dados:** origem, dono, estado, mutabilidade e regra de recuperação de cada manifest, original, referência, intermediário, cache e artefato final.
3. **FMEA:** severidade, ocorrência e detectabilidade das falhas; perda silenciosa de originais e migração destrutiva recebem severidade máxima.
4. **Árvore de falhas:** para “captura não aproveitável”, “projeto não reabre” e “export não utilizável”, incluindo dependências de câmera, filesystem, memória, temperatura e ciclo de vida do app.
5. **Matriz de concorrência:** quais operações podem coexistir. Captura, migração e compactação no mesmo projeto devem ser mutuamente exclusivas; leitura e thumbnail precisam de snapshots consistentes.

O resultado da análise vira invariantes testáveis. Exemplos: “um frame só é confirmado depois do rename atômico”, “um projeto futuro incompatível nunca é reescrito” e “um artefato parcial nunca aparece como export final”.

## 3. Decisões de produto

### 3.1 Arquivar e compactar são ações diferentes

**Arquivar** remove o projeto da lista principal, mas não altera seus arquivos.

**Compactar** libera espaço mediante uma política explícita. Antes de executar, a interface deve mostrar:

- o que será preservado;
- o que será removido;
- o espaço estimado a recuperar;
- se existe um vídeo final local validado;
- quais capacidades serão perdidas, como reprocessar RAW ou gerar outro render.

Não apagar automaticamente originais apenas porque um MP4 foi compartilhado. O Camerae não deve assumir que uma cópia externa continua acessível. A compactação padrão preserva pelo menos manifest, frame de referência em alta qualidade e artefato final local validado.

### 3.2 Estados de retenção propostos

| Estado | Preserva | Remove | Uso principal |
|---|---|---|---|
| Completo | manifests, referência, originais, renders e export final | apenas cache descartável quando solicitado | projeto ativo e reprocessável |
| Otimizado | manifests, referência, originais e export final escolhido | intermediários e renders não escolhidos | continuar editando com menos duplicação |
| Compactado | manifests, referência e export final validado | originais, intermediários, cache e renders não preservados | projeto concluído de longo prazo |
| Receita apenas | manifests e referência | toda mídia pesada | somente após aviso forte; não é o padrão |

Um projeto compactado continua abrindo. A interface deve explicar quais ações ficaram indisponíveis e nunca representar arquivos removidos como temporariamente ausentes.

### 3.3 Qualidade e longevidade de captura

Os modos devem ser apresentados pelo resultado, não apenas pela extensão:

- **Máxima latitude:** RAW, quando suportado; maior custo e maior liberdade de reprocessamento.
- **Equilibrado:** imagem processada de alta qualidade; menor custo e compatibilidade ampla.
- **Longa duração:** formato eficiente e parâmetros adequados ao pipeline; maximiza o tempo de captura.

Cada opção mostra tamanho observado por frame, duração estimada suportada e espaço total previsto. RAW deve entrar apenas depois que a política de capacidade, o modelo de formatos e a matriz de testes estiverem prontos.

### 3.4 Render progressivo

Para timelapse comum, segmentos de vídeo recuperáveis podem ser produzidos durante a captura e consolidados no final. Isso reduz o custo de um render posterior, mas não deve apagar originais sem uma política de retenção escolhida pelo usuário.

Para Astro, os originais podem ser necessários para alinhamento, stacking e novos processamentos. A remoção progressiva não pode ser o comportamento padrão. O primeiro ganho deve vir da remoção de caches e intermediários regeneráveis; a remoção de originais ocorre apenas por compactação explícita.

### 3.5 Plano de captura e presets de duração

Duração passa a ser obrigatória no fluxo normal. O usuário escolhe um preset ou Custom antes de iniciar:

| Fluxo | Presets iniciais | Custom | Resultado calculado antes de iniciar |
|---|---|---|---|
| Repeatable vídeo | 30 segundos, 1 minuto | duração em minutos/segundos dentro dos limites do device | tamanho do vídeo pela duração, codec, resolução, FPS e bitrate |
| Repeatable timelapse | 5, 10 ou 30 minutos | duração em minutos/horas | frames previstos, bytes dos originais e duração do MP4 |
| Astro | 30 minutos, 1 hora ou 3 horas | duração em minutos/horas | frames, originais, intermediários, render, bateria e pipeline disponível |

Não persistir apenas o identificador do botão, como `astro3Hours`. Persistir os valores resolvidos em um `CapturePlan`, para que o projeto continue compreensível se os presets mudarem no futuro:

```swift
public struct CapturePlan: Codable, Equatable, Sendable {
    public let workflow: CaptureWorkflow
    public let plannedDuration: TimeInterval
    public let captureInterval: TimeInterval?
    public let sourceFormat: CaptureSourceFormat
    public let captureFPS: Int?
    public let renderFPS: Int?
    public let resolution: CaptureResolution
    public let astroPipeline: AstroPipelineProfile?
}
```

`captureFPS` e `renderFPS` são conceitos separados. No vídeo normal, FPS é parte da gravação. No timelapse, o intervalo determina quantos frames existem e o FPS de render determina a duração final:

```text
frames previstos ≈ ceil(duração de captura / intervalo)
duração do timelapse = frames renderizados / FPS de render
```

O cálculo usa arredondamento conservador para armazenamento e a mesma semântica do loop real de captura. No Astro, `frames renderizados` depende também do tamanho do stack e da opção de preservar ou comprimir a duração da timeline. A UI deve mostrar a consequência, por exemplo: “30 minutos capturando → aproximadamente 12 segundos em 30 FPS”.

A captura termina automaticamente quando o plano é satisfeito, faz checkpoint e publica seu estado final. Um modo avançado “até eu parar” pode existir, mas não deve ser o default; ele mostra a duração suportada estimada e exige confirmação quando a margem for pequena.

### 3.6 Estratégia de formatos: JPEG, HEIC e DNG

JPEG e HEIC são formatos processados e comprimidos; nenhum deles é RAW. DNG é o container persistido para Bayer RAW ou Apple ProRAW quando a configuração da câmera oferecer um pixel format compatível.

| Formato | Papel recomendado | Benefício | Custo/risco |
|---|---|---|---|
| HEIC | default processado quando a configuração anuncia e valida suporte | tende a reduzir armazenamento para qualidade visual comparável | exige caracterizar decode, stacking, energia, memória e interoperabilidade |
| JPEG | fallback universal para todos os devices suportados | pipeline atual, compatibilidade e comportamento conhecido | maior que HEIC em muitos cenários e com menor latitude que RAW |
| Bayer RAW em DNG | Astro de máxima latitude quando disponível | dados mais próximos do sensor e maior liberdade de processamento | arquivos grandes, restrições de captura e processamento caro |
| Apple ProRAW em DNG | alternativa RAW parcialmente processada quando suportada | permite RAW em alguns modos computacionais | não universal, arquivo pesado e semântica diferente de Bayer RAW |

Política inicial:

1. HEIC é o default. O plano o seleciona quando codec, file type e pipeline completo estão disponíveis e validados no capability profile.
2. JPEG permanece como fallback obrigatório. O fallback ocorre antes da sessão começar, fica visível no resumo e é persistido no `CapturePlan`; nunca trocar silenciosamente no meio da captura.
3. RAW aparece apenas se `availableRawPhotoPixelFormatTypes` e `availableRawPhotoFileTypes` confirmarem suporte para a câmera/configuração atual.
4. ProRAW é sondado e habilitado antes de iniciar a sessão somente quando `isAppleProRAWSupported` for verdadeiro.
5. RAW-only economiza o proxy processado, mas piora preview e compatibilidade. Para o primeiro MVP, considerar RAW + JPEG/HEIC proxy e contabilizar ambos no preflight.
6. Nunca mudar silenciosamente o formato no meio de uma sessão. Se houver degradação, parar com segurança ou registrar explicitamente uma nova parte da sessão.

Esqueleto da API Swift a ser isolada em `CaptureFormatAdapter` e coberta por testes de integração em device:

```swift
guard
    let rawNumber = photoOutput.availableRawPhotoPixelFormatTypes.first,
    photoOutput.availableRawPhotoFileTypes.contains(.dng)
else {
    throw CaptureFormatError.rawUnavailable
}

let rawType = rawNumber
let settings = AVCapturePhotoSettings(
    rawPixelFormatType: rawType,
    rawFileType: .dng,
    processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg],
    processedFileType: .jpg
)
```

O adapter real deve escolher explicitamente Bayer RAW ou ProRAW, validar a combinação raw pixel format/file type e validar também o codec/file type processado. No delegate, cada `AVCapturePhoto` é distinguido por `isRawPhoto`; `fileDataRepresentation()` fornece os bytes no container solicitado. Bayer RAW também impõe restrições como prioridade `.speed` e zoom 1×, que devem entrar na validação do `CapturePlan`.

### 3.7 Suporte amplo com degradação por capacidade

Não manter uma lista manual “iPhone X pode, iPhone Y não pode”. Todos os devices que atendem ao deployment target recebem o fluxo base, e o app constrói um `DeviceCapabilityProfile` em runtime a partir de capacidades reais:

- câmeras, lentes, formatos, dimensões e codecs expostos por AVFoundation;
- Bayer RAW e ProRAW disponíveis na configuração atual;
- capacidade Metal necessária ao backend escolhido;
- memória física e pressão de memória observada;
- estado térmico e Low Power Mode;
- espaço utilizável e velocidade observada de escrita/processamento;
- bateria, carregamento e taxa empírica de consumo por perfil.

Perfis de entrega:

| Perfil | Garantia |
|---|---|
| Essencial | Repeatable e Astro em HEIC quando validado, com fallback JPEG; vídeo HD ou FHD dentro dos budgets |
| Equilibrado | HEIC/FHD, stacking em lotes e processamento limitado por resolução |
| Avançado | RAW/DNG, maior resolução, alinhamento e redução de ruído completos quando os budgets permitem |

O perfil não é um rótulo permanente do aparelho. Temperatura, memória, bateria e espaço podem reduzir temporariamente o pipeline. A prioridade de degradação é preservar captura: pausar preview/cache/processamento concorrente, reduzir processamento posterior e, somente por último, encerrar com segurança. Não fingir que alinhamento ou denoise aconteceu; o manifest registra o pipeline efetivamente usado.

## 4. Arquitetura proposta

```text
CameraeFeatures / SwiftUI
  ├── StorageDashboardViewModel
  ├── CaptureCapacityViewModel
  └── ProjectRetentionViewModel
          │
CameraeCore
  ├── CapturePlan e CapturePlanEstimator
  ├── DeviceCapabilityProfile
  ├── StorageSnapshotProvider (protocolo)
  ├── BatterySnapshotProvider (protocolo)
  ├── SystemPressureProvider (protocolo)
  ├── CaptureSizeEstimator
  ├── CaptureEnergyEstimator
  ├── CaptureAdmissionPolicy
  ├── CaptureStorageGuard
  ├── CaptureHealthCoordinator
  ├── ProjectStorageLedger
  ├── RetentionPlanner
  ├── RetentionExecutor
  └── ProjectMigrationCoordinator
          │
CameraeMedia
  ├── CaptureFormatProbe
  ├── DeviceCapabilityProbe
  ├── BatterySnapshotAdapter
  ├── CameraInterruptionAdapter
  ├── RenderSpaceEstimator
  └── FinalArtifactValidator
```

As regras e decisões ficam em `CameraeCore`. Consultas ao volume, codecs, câmera e validação de vídeo ficam em adapters concretos. Views recebem snapshots imutáveis e não enumeram diretórios.

`CaptureHealthCoordinator` combina armazenamento, interrupções da câmera, pressão de memória, estado térmico e ciclo de vida. Cada sinal tem provider injetável para testes; a coordenação decide entre continuar, reduzir trabalho não essencial, avisar ou parar com segurança. A razão persistida e a razão emitida na telemetria vêm da mesma enumeração de domínio.

### 4.1 Snapshot de capacidade

Modelo mínimo:

```swift
public struct StorageCapacitySnapshot: Equatable, Sendable {
    public let availableForImportantUsage: UInt64
    public let capturedAt: Date
    public let source: StorageCapacitySource
}
```

O adapter iOS consulta a capacidade disponível para uso importante no mesmo volume em que a biblioteca está localizada. Falha na consulta não equivale a espaço infinito: gera um estado `unknown` e uma comunicação específica na UI.

### 4.2 Estimativa de captura

Entradas:

- formato e configuração de qualidade;
- device, câmera/lente e resolução;
- intervalo entre frames;
- duração ou número planejado de frames;
- amostras locais recentes de bytes por frame;
- custo temporário do processamento e do render;
- reserva operacional do app e do sistema;
- perfil de capacidade, bateria, carregamento e confiança da estimativa de energia.

Saídas:

- bytes previstos;
- intervalo de incerteza;
- duração estimada suportada;
- bateria prevista ao final e recomendação de alimentação externa;
- pipeline Astro prometido e fallbacks permitidos;
- espaço reservado para finalizar e publicar o artefato;
- decisão `allowed`, `warning`, `blocked` ou `unknown` com razão tipada.

Não depender de uma constante universal de “MB por RAW”. Começar com um baseline conservador por perfil e atualizar uma média móvel e um percentil alto com frames reais do próprio dispositivo. A decisão de admissão usa o limite conservador.

### 4.3 Energia e capacidade do pipeline

O iOS fornece bateria atual, estado de carregamento, Low Power Mode e estado térmico, mas isso não permite prometer com precisão que “há 2h17 restantes”. O estimador deve combinar:

- nível e estado de carregamento atuais;
- perfil de captura/processamento;
- taxa de consumo observada em execuções anteriores do mesmo capability profile;
- temperatura e Low Power Mode;
- faixa de incerteza, nunca apenas um número exato.

Saída proposta:

```text
energy: sufficient | warning | critical | unknown
estimatedEndLevel: intervalo percentual
externalPowerRecommended: Bool
confidence: low | medium | high
```

Uma captura longa Astro recomenda alimentação externa, mas ainda monitora bateria e temperatura, pois carregar e processar simultaneamente pode aumentar pressão térmica. No MVP, capacidade insuficiente de storage bloqueia; bateria incerta ou insuficiente gera warning e confirmação, exceto abaixo de um limite crítico calibrado em que nem checkpoint/finalização são considerados seguros.

O pipeline Astro é resolvido antes de iniciar. Se alinhamento e denoise completos excederem o budget, o plano oferece processamento reduzido ou “timelapse de estrelas” em vez de falhar horas depois. Durante a captura, primeiro suspender trabalho derivado; preservar originais e checkpoints tem precedência.

### 4.4 Política de reserva

A política não deve espalhar números mágicos pela interface. Ela recebe uma configuração versionada e calcula:

```text
necessário = captura prevista
           + temporários de processamento/render
           + custo de publicação atômica
           + reserva de segurança
```

A reserva deve combinar um piso absoluto e uma fração do plano, calibrados em devices reais. Hipótese inicial para testes, não valor final de produção:

```text
reserva = max(2 GiB, 10% dos bytes planejados, dois lotes no P95)
```

O custo de finalização/publicação é somado separadamente e nunca consumido durante a captura. A política usa capacidade disponível para uso importante no volume real; não classifica a reserva apenas pelo nome/modelo do device.

Para capturas sem duração definida, o app informa o tempo estimado restante e exige apenas a reserva mínima para iniciar. Durante a execução, o guardião passa a ser a proteção principal.

### 4.5 Guardião durante a captura

`CaptureStorageGuard` reavalia a margem periodicamente e após mudanças relevantes no tamanho observado. Consultar o volume em todo frame pode produzir I/O desnecessário; a frequência deve ser configurável e testada.

Estados:

```text
healthy → warning → stopping → stoppedSafely
                  ↘ writeFailure → recoveryRequired
```

Com margem baixa:

1. avisar sem interromper prematuramente;
2. impedir o início de um novo lote que não possa ser concluído;
3. finalizar o frame já confirmado;
4. checkpoint do manifest;
5. finalizar ou tornar recuperável o segmento de vídeo atual;
6. encerrar a captura com razão `insufficientStorage`;
7. abrir diretamente as opções para liberar espaço.

Se uma gravação falhar, o contador só avança após publicação atômica bem-sucedida. O app preserva os frames anteriores e registra que a sessão precisa de reparo.

### 4.6 Ledger de armazenamento

Cada sessão deve manter totais incrementais por categoria:

- `original`;
- `reference`;
- `processedIntermediate`;
- `renderedFrame`;
- `finalArtifact`;
- `cache`;
- `exportArchive`.

O ledger é uma otimização verificável, não a única fonte de verdade. Se estiver ausente, sujo ou incompatível, um reparo em background reconstrói os totais a partir do filesystem. A home usa os totais conhecidos imediatamente e mostra quando o inventário ainda está sendo confirmado.

### 4.7 Compactação transacional

`RetentionPlanner` é puro: recebe inventário e política desejada e produz uma lista exata de arquivos preservados/removidos e bytes estimados.

`RetentionExecutor` executa somente depois de:

1. validar que os caminhos pertencem ao projeto;
2. copiar/publicar uma referência estável independente do primeiro original;
3. validar o artefato final por existência, tamanho, tracks, duração e legibilidade;
4. persistir o plano e o estado `compactionInProgress`;
5. remover apenas os itens aprovados;
6. reconstruir e validar o inventário;
7. persistir o estado final e um tombstone das categorias removidas.

Após interrupção, a próxima abertura retoma a validação ou conclui a reparação. Compactação nunca roda junto de captura, render, export ou migração.

## 5. Compatibilidade de projetos por muitos anos

### 5.1 Contrato de formato

- caminhos persistidos são relativos à raiz do projeto;
- IDs são estáveis e independentes do nome do diretório;
- toda versão de schema publicada ganha fixtures imutáveis no repositório;
- índices, thumbnails e caches são derivados e reconstruíveis;
- originais não são reescritos durante migração de metadata;
- decoders rejeitam de forma explícita versões futuras não suportadas, sem tentar “consertá-las”;
- migrações formam uma cadeia testável `vN → vN+1`, em vez de um salto implícito para “latest”;
- escrita do novo manifest ocorre em temporário, seguida de decode, validação e troca atômica;
- o manifest anterior é mantido como backup até a abertura completa do projeto migrado;
- falha de uma migração deixa o projeto original legível pela versão que o criou.

### 5.2 Pacote portável

Criar uma especificação de exportação/importação de projeto independente do container do app:

```text
CameraeProject/
  package.json
  project.json
  Sessions/
  References/
  Exports/
```

`package.json` informa versão, inventário, tamanhos e checksums. A importação extrai para uma área temporária, valida caminhos e integridade e só então publica o projeto na biblioteca. Nunca misturar parcialmente um pacote importado com um projeto existente.

Checksums completos são adequados ao transporte e à validação explícita. Durante uso cotidiano, não recalcular hashes de milhares de frames a cada abertura; usar ledger, tamanho, geração e validação incremental.

### 5.3 Política de suporte

O objetivo deve ser abrir toda versão de schema que chegou a uma release pública. A CI mantém, no mínimo:

- fixtures de cada schema público;
- upgrade sequencial até o schema atual;
- projeto já migrado reaberto sem nova alteração;
- falha/interrupção em cada passo de migração;
- app atual lendo projeto não migrado quando a migração não é obrigatória;
- pacote exportado e reimportado com equivalência de inventário.

## 6. Experiência do usuário

### 6.1 Antes da captura

Mostrar junto das configurações:

- preset/Custom de duração e horário previsto de término;
- intervalo de captura e quantidade prevista de frames;
- FPS de render e duração prevista do MP4 para timelapse;
- formato disponível e comparação JPEG/HEIC/RAW + proxy;
- espaço livre utilizável;
- tamanho estimado da captura;
- margem para processamento/finalização;
- tempo ou frames estimados suportados;
- impacto de trocar RAW por imagem processada;
- bateria atual, faixa estimada ao término e recomendação de carregador;
- pipeline Astro disponível: completo, reduzido ou timelapse sem processamento avançado;
- ação direta para revisar projetos grandes.

Se o plano não couber, bloquear o início e explicar quanto precisa ser liberado ou qual ajuste torna a captura viável. Em estado `unknown`, não mostrar uma falsa precisão.

Ordem recomendada do configurador:

```text
duração → intervalo/FPS → qualidade/formato → pipeline Astro
        → resumo de tempo, vídeo, storage e bateria → iniciar
```

Alterar qualquer entrada recalcula o resumo imediatamente. O botão Iniciar mostra o resultado do plano, não apenas “começar captura”.

### 6.2 Durante a captura

Exibir discretamente:

- uso da sessão;
- tempo decorrido e restante do plano;
- espaço restante;
- duração estimada restante no ritmo atual;
- bateria e pressão térmica quando exigirem ação;
- alerta persistente quando a margem entra em `warning`.

Uma parada por armazenamento deve ser apresentada como **captura encerrada com segurança**, indicando quantos frames foram preservados e as ações disponíveis.

### 6.3 Biblioteca e projeto

Adicionar:

- consumo total do Camerae;
- consumo por módulo, projeto e sessão;
- detalhamento por originais, processados, vídeos, exports e cache;
- ordenação por maior consumo;
- ação “Revisar armazenamento”;
- simulação da economia antes de limpar cache, otimizar ou compactar;
- estado de retenção visível no projeto.

## 7. Observabilidade com privacidade

Eventos mínimos e sem conteúdo de mídia:

- preflight permitido, avisado, bloqueado ou desconhecido;
- formato, intervalo, duração planejada em faixas e bytes previstos em faixas;
- margem no início e no encerramento em faixas;
- parada segura e motivo tipado;
- falha de escrita, checkpoint, render, compactação, migração e importação;
- erro percentual da estimativa;
- bytes recuperados por categoria;
- schema de origem/destino e resultado da migração;
- projeto reaberto com sucesso após atualização.

Não anexar nomes de projeto, caminhos, localização, imagens, vídeo, screenshots ou logs detalhados sem permissão explícita. IDs de diagnóstico devem ser efêmeros ou não reversíveis e não permitir correlacionar trabalho criativo ao longo do tempo.

## 8. Plano de documentação

Antes de implementar, produzir e aprovar:

1. **PRD de plano de captura, capacidade e retenção:** presets/Custom, fluxos, textos, estados, fallbacks e defaults.
2. **ADR de armazenamento:** providers, estimador, guardião, ledger e responsabilidades por módulo.
3. **Especificação do formato em disco:** schemas, categorias, caminhos relativos e invariantes.
4. **Política de migração:** versões suportadas, backup, rollback e fixtures obrigatórias.
5. **Especificação do pacote portável:** layout, validação, checksums e segurança de paths.
6. **Plano de testes e fault injection:** matriz abaixo e devices de referência.
7. **Catálogo de telemetria e privacidade:** campos permitidos, retenção e opt-in.
8. **Runbook de recuperação:** projeto inválido, disco cheio, migração interrompida e mídia ausente.
9. **Checklist de release:** compatibilidade, budgets, migrações e rollback antes de cada publicação.

Este documento pode ser promovido a ADR/PRD após as decisões abertas da seção 12.

## 9. Roadmap TDD em fatias

Cada fatia segue **Characterize → Red → Green → Refactor** e termina com a suíte relevante verde. Evitar uma implementação única que misture captura, UI, migração e deleção.

### Fase 0 — baseline e caracterização

- produzir mapa da missão, mapa de dados, FMEA, árvores de falha e matriz de concorrência;
- congelar fixtures de todos os manifests hoje encontrados;
- caracterizar captura JPEG, incremento de frame, escrita atômica e reparo;
- caracterizar archive/unarchive sem deleção;
- capturar volumes reais por formato/device em uma pequena matriz de referência;
- caracterizar suporte real a JPEG, HEIC, Bayer RAW/DNG e ProRAW/DNG na matriz de devices;
- medir duração, tamanho, energia e temperatura nos três presets de cada fluxo;
- adicionar testes de interrupção entre frame, manifest, índice e render;
- definir taxonomia de resultados/falhas para captura, projeto e export.

Gate: comportamento atual documentado, fixtures versionadas e nenhuma mudança funcional.

### Fase 1 — capacidade e estimativa puras

- criar `CapturePlan`, presets resolvidos e codec versionado;
- implementar cálculo distinto para vídeo, timelapse e Astro;
- criar `StorageCapacitySnapshot` e provider injetável;
- criar `BatterySnapshot`, `DeviceCapabilityProfile` e providers injetáveis;
- implementar cálculo de frames/duração planejada;
- implementar estimador conservador com baseline e amostras observadas;
- implementar estimativa de energia com faixa e confiança;
- implementar `CaptureAdmissionPolicy` sem dependência de UI ou AVFoundation;
- testar limites exatos, overflow, capacidade desconhecida e estimativas extremas.

Gate: a mesma entrada sempre produz a mesma decisão e razão tipada.

### Fase 2 — preflight e UI de planejamento

- integrar provider iOS;
- adicionar presets e editor Custom para cada fluxo;
- separar FPS de captura, intervalo e FPS de render;
- exibir livre, necessário, reserva e duração suportada;
- exibir duração prevista do MP4, bateria final em faixa e pipeline Astro resolvido;
- bloquear captura inviável;
- oferecer comparação de perfis e simulação de formatos, mantendo apenas formatos já implementados selecionáveis;
- implementar HEIC como default e tornar o fallback JPEG explícito, testável e persistido no plano;
- instrumentar resultado do preflight com dados agregados.

Gate: UI tests cobrem permitido, warning, bloqueado e desconhecido.

### Fase 3 — proteção durante a captura

- migrar a gravação efetiva para o contrato checkpoint/recovery do catálogo;
- integrar `CaptureStorageGuard` ao loop de captura;
- integrar interrupção de câmera, pressão de memória, temperatura e ciclo de vida ao `CaptureHealthCoordinator`;
- encerrar automaticamente no limite de duração do plano;
- implementar warning e parada segura;
- tratar `ENOSPC`/falha de escrita sem avançar frame;
- persistir motivo e estado final da sessão;
- recuperar sessão após encerramento forçado.

Gate: nenhuma falha injetada perde frames previamente confirmados ou deixa a sessão impossível de abrir.

### Fase 4 — compatibilidade e migração robusta

- formalizar faixa de schemas aceitos e rejeição de versões futuras;
- congelar a política “toda versão pública continua abrindo”;
- implementar migradores sequenciais, validação pós-migração e backups;
- adicionar fault injection antes e depois de cada publicação atômica;
- provar idempotência: projeto migrado reabre sem ser alterado novamente;
- adicionar fixtures de bibliotecas com múltiplas versões e assets ausentes.

Gate: todas as fixtures públicas migram ou abrem, e uma migração interrompida preserva o manifest anterior.

### Fase 5 — ledger e painel de armazenamento

- persistir totais incrementais por categoria;
- reparar ledger sujo em background;
- propagar totais para `ProjectSummary` sem varrer frames na `MainActor`;
- criar painel app → módulo → projeto → sessão;
- medir tempo, memória e I/O com 10 mil e 100 mil frames sintéticos.

Gate: lista inicial usa índice; reparo completo é assíncrono e respeita budgets documentados.

### Fase 6 — render e temporários seguros

- estimar espaço de trabalho antes do render;
- publicar vídeo final atomicamente;
- validar o artefato antes de registrá-lo como final;
- limpar temporários em erro/cancelamento;
- prototipar segmentos recuperáveis para timelapse comum;
- manter originais até uma decisão explícita de retenção.

Gate: render interrompido preserva o último artefato válido e não deixa um MP4 parcial como sucesso.

### Fase 7 — retenção e compactação

- classificar os assets existentes;
- implementar `RetentionPlanner` puro;
- adicionar preview do que será removido e do espaço recuperado;
- criar referência estável e validar artefato final;
- implementar executor transacional, tombstones e recuperação;
- manter `archive` estritamente não destrutivo.

Gate: compactação interrompida reabre de forma consistente e nunca remove o único artefato final ou a referência prometida.

### Fase 8 — pacote portável

- especificar e implementar export/import validado;
- registrar inventário, tamanhos e checksums no pacote;
- adicionar round-trip e proteção contra path traversal/ZIP bombs.

Gate: pacote inválido nunca altera a biblioteca e o round-trip preserva a equivalência do inventário.

### Fase 9 — RAW e perfis de longa duração

- detectar capacidades reais por device;
- modelar formato por frame no manifest e no inventário;
- implementar Bayer RAW/DNG e ProRAW/DNG como capacidades distintas;
- implementar RAW-only e RAW + imagem processada, selecionando o MVP após os benchmarks;
- preparar configurações RAW antes da captura para evitar alocação tardia;
- atualizar thumbnail, stacking, export e package importer;
- calibrar estimativas com medições reais;
- validar temperatura, bateria, memória, I/O e pressão de armazenamento em captura longa.

Gate: cada perfil tem estimativa conservadora, fallback explícito e matriz de compatibilidade verde.

## 10. Matriz mínima de testes

### Unidade

- resolução dos presets em `CapturePlan` sem persistir apenas o nome do preset;
- cálculo de frames por duração/intervalo;
- duração final por frames/FPS e efeito de stacking Astro;
- estimativa de vídeo por bitrate/duração;
- estimativa por média, percentil alto e baseline sem histórico;
- estimativa de bateria com confiança baixa/média/alta;
- resolução determinística do capability profile e pipeline Astro;
- limites da política e reserva;
- transições do guardião;
- prioridades e transições do coordenador quando mais de uma pressão ocorre ao mesmo tempo;
- classificação e plano de retenção;
- migradores e validação de schema;
- sanitização de caminhos relativos.

### Componentes com filesystem temporário

- disco fica cheio antes, durante e depois da escrita de um frame;
- manifest falha depois do frame publicado;
- checkpoint interrompido;
- render final válido, vazio, truncado ou sem track;
- compactação interrompida após cada arquivo;
- ledger ausente, divergente ou corrompido;
- referência original removida depois de uma cópia estável;
- migração interrompida antes e depois da troca atômica;
- pacote com checksum errado, `..`, symlink e conteúdo excessivo.

### Componentes de captura com adapters falsos

- término automático exato para cada preset e Custom;
- suporte/ausência simulados para JPEG, HEIC, Bayer RAW e ProRAW;
- callback RAW + processado gera dois assets corretamente classificados;
- capacidade muda entre a configuração da câmera e o início da captura;
- câmera interrompida antes e depois da confirmação de um frame;
- warning de memória durante captura e render;
- estado térmico muda entre nominal, serious e critical;
- app entra em background durante escrita, checkpoint e finalização;
- storage e interrupção de câmera acontecem simultaneamente;
- o motivo final é determinístico e não duplica conclusão/telemetria.

### Integração

- preset → plano → preflight → captura → término automático → duração esperada do MP4;
- preflight → captura → warning → parada segura → reabertura;
- captura → render → compactação → reabertura após nova versão;
- projeto de fixture antiga → migração → render/export;
- projeto compactado aparece corretamente na biblioteca Edit;
- exclusão de origem referenciada pelo Edit vira “mídia ausente”, não corrupção do projeto Edit.

### UI

- comparação de perfis;
- bloqueio com explicação acionável;
- painel e ordenação por consumo;
- preview e confirmação de compactação;
- representação de projeto compactado e mídia ausente;
- recuperação de sessão interrompida.

### Performance e longevidade

- 10 mil e 100 mil frames sem enumeração síncrona em views;
- captura longa com medições de memória, storage, temperatura e energia;
- matriz JPEG/HEIC/DNG por capability profile e preset;
- estimativa versus bytes reais por perfil/device;
- migração de bibliotecas com muitos projetos;
- reabertura repetida sem remigração ou drift de manifests.

## 11. Critérios de aceite P0

1. Repeatable vídeo, Repeatable timelapse e Astro oferecem seus presets e Custom, resolvidos e persistidos como valores de `CapturePlan`.
2. Antes de iniciar, o usuário vê término previsto, frames, duração do MP4 quando aplicável, storage, bateria e pipeline Astro efetivo.
3. Uma captura planejada não inicia se a estimativa conservadora mais a reserva exceder a capacidade utilizável conhecida.
4. A captura termina automaticamente no limite do plano, faz checkpoint e permanece recuperável.
5. Captura sem duração é avançada, informa tempo restante estimado e para com segurança antes de consumir a reserva definida.
6. Device sem recursos para Astro completo recebe um pipeline reduzido explícito ou timelapse de estrelas, nunca uma promessa falsa.
7. Falha de escrita nunca incrementa o frame nem invalida frames já confirmados.
8. Após encerramento forçado, a sessão reabre, repara o inventário e informa o motivo/estado correto.
9. O usuário vê consumo total, por projeto e por categoria sem bloquear a `MainActor`.
10. Arquivar não remove arquivos.
11. Compactar mostra consequências e bytes, valida referência e artefato final e é recuperável após interrupção.
12. Toda versão pública do schema possui fixture e caminho testado até a versão atual.
13. Uma versão futura não suportada é preservada e apresentada como incompatível, nunca reescrita silenciosamente.
14. Telemetria padrão não contém mídia, localização, nomes ou caminhos do usuário.

## 12. Decisões recomendadas e calibrações abertas

1. **Reserva mínima:** não separar apenas por “classe de device”. Usar o volume real e o workload. Hipótese para bancada: `max(2 GiB, 10% do plano, dois lotes P95)`, além do espaço de finalização. Aprovar números finais somente após testes.
2. **Captura sem duração:** presets/Custom são o fluxo normal. “Até eu parar” é avançado, mostra limite estimado, exige confirmação em warning e sempre usa safe-stop.
3. **MP4 no Compactado:** sim, um artefato final local validado é obrigatório no estado Compactado padrão. “Receita apenas” continua sendo um estado separado e fortemente avisado.
4. **Renders preservados:** um render final escolhido pelo usuário por padrão. Outros renders podem ser marcados para preservação antes da compactação.
5. **Pacote e RAW:** especificar schema/inventário do pacote antes de RAW para não criar metadata sem contrato portável; implementar o pacote completo depois da base de migração e antes de considerar suporte RAW concluído.
6. **Formatos Astro:** HEIC é o default processado; JPEG é fallback obrigatório; Bayer RAW/DNG e ProRAW/DNG são opções distintas e condicionadas à capacidade. HEIC e JPEG não devem ser chamados de RAW.
7. **Render progressivo:** primeiro como cache recuperável e validável. Só virar política de retenção automática após provar integridade de segmentos, retomada e publicação final, com opt-in explícito.
8. **Devices e OS:** usar capability probes em runtime, não allowlist de modelos. Todos os devices no deployment target recebem o perfil Essencial; Equilibrado/Avançado dependem de capacidades e condições atuais. A bancada usa grupos representativos para regressão, mas não define artificialmente quem pode instalar.

Continuam abertas para calibração: duração mínima/máxima de Custom, opções de FPS, bitrates HD/FHD, intervalo padrão por fluxo, limiar crítico de bateria, budgets térmicos, tamanho dos lotes e critérios exatos para fallback JPEG, alinhamento e denoise.

## 13. Recorte recomendado para o Camerae 5.0

### 13.1 Obrigatório para publicar 5.0

- `CapturePlan` versionado para Repeatable vídeo, Repeatable timelapse e Astro;
- presets e Custom com HEIC default e JPEG fallback;
- cálculo de frames, duração final, storage e custo de finalização;
- snapshot de bateria/carga/temperatura com warnings honestos;
- capability profile em runtime e pipeline Astro reduzido quando necessário;
- preflight que bloqueia planos sem armazenamento suficiente;
- término automático, checkpoint, safe-stop e recovery;
- schema v5, migradores sequenciais e fixtures incluindo a base 4.0.0;
- publicação e validação atômica do MP4;
- painel básico de consumo por projeto/sessão/categoria;
- taxonomia de resultados e telemetria agregada respeitando privacidade.

### 13.2 Não deve bloquear 5.0

- Bayer RAW/DNG e Apple ProRAW/DNG;
- render progressivo com remoção automática de originais;
- compactação além do modo seguro mínimo;
- pacote portável completo;
- dashboard avançado e recomendações automáticas entre projetos.

Esses itens podem ser desenvolvidos na arquitetura v5 e liberados em 5.x quando passarem pela matriz de devices. Não condicionar a segurança básica de captura à maturidade de RAW.

### 13.3 Gates da major

1. **Contrato:** PRD, ADR, schema v5, taxonomia de falhas e invariantes aprovados.
2. **Domínio:** estimadores e admission policy verdes com providers falsos.
3. **Captura:** presets, término automático, safe-stop e recovery verdes em device.
4. **Compatibilidade:** todas as fixtures públicas abrem/migram e falhas preservam o original.
5. **Device lab:** grupos representativos passam nos budgets de storage, memória, energia e temperatura.
6. **Release:** zero P0 aberto, rollback documentado e métricas de missão disponíveis.

## 14. Ordem recomendada

A sequência recomendada é:

```text
análise/fixtures → CapturePlan/presets → preflight de storage/bateria/capability
                 → guardião/runtime → recovery → migração → ledger/UI
                 → render seguro → compactação → pacote → RAW
```

O primeiro release não precisa resolver todos os modos de retenção nem adicionar RAW. O incremento de maior valor é transformar duração, intervalo e FPS em um plano verificável, impedir uma captura inviável, terminar/parar com segurança e garantir que tudo já confirmado continue abrindo.
