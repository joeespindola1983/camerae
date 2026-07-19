# Alinhamento espacial de clips — plano TDD

Status: em implementação incremental

Escopo: alinhar clips de uma timeline de edição contra um clip base sem acoplar
OpenCV, AVFoundation ou decisões de produto à futura interface.

## Decisão inicial

A primeira entrega usa uma transformação única por clip. O Camerae tenta, nesta
ordem, translação e similaridade. Ele escolhe o modelo mais simples aprovado,
calcula um crop comum para toda a sequência e rejeita automaticamente resultados
que exijam crop ou deformação além do limite.

Affine e homografia continuam disponíveis no núcleo Camerae Vision para análise,
mas não entram inicialmente no compositor de vídeo. Homografia exige um
compositor customizado; `AVMutableVideoCompositionLayerInstruction` aplica apenas
transformações afins.

## Separação de responsabilidades

```text
clips da timeline
       |
       v
ClipAlignmentAnalyzer
  - extrai frames representativos
  - normaliza orientação e resolução
       |
       v
CameraeVision (Objective-C++ / C++)
  - estima translation e similarity
  - métricas, decisão e reason codes
       |
       v
EditSpatialAlignmentPlan (CameraeMedia)
  - referência da sequência
  - correção fixa de cada clip
  - crop comum normalizado
  - decisão e diagnósticos
       |
       v
EditVideoComposer
  - aspect fit/orientação existentes
  - correção individual do clip
  - mesmo crop global em todos os clips
```

O plano de domínio não contém `cv::Mat`, `AVAsset`, `UIImage` ou tipos de UI.

## Por que o crop é global

Cada clip possui uma correção diferente, mas a janela final precisa permanecer
estável. Aplicar um zoom diferente em cada corte introduziria um salto visual.
Por isso, o analisador intersecta as regiões válidas de todos os clips e produz
uma única janela comum. Essa janela é aplicada igualmente à sequência inteira.

## Modelos

### Translation

- move apenas X/Y;
- não altera geometria;
- modelo preferido quando explica o movimento;
- rejeita deslocamentos que deixem área comum insuficiente.

### Similarity

- move X/Y, gira e aplica escala uniforme;
- não introduz shear ou perspectiva;
- usada somente quando melhora materialmente o erro sobre translation;
- limites iniciais de rotação, escala e crop são conservadores.

### Affine e perspective

- analisados e reportados futuramente;
- nunca promovidos silenciosamente pela primeira versão;
- exigem opt-in e novos testes visuais/temporais.

## Frames representativos

O primeiro clip válido é a referência. Cada clip é amostrado em três posições:
20%, 50% e 80% da duração. O resultado fixo nasce de consenso robusto entre as
amostras; uma única amostra divergente não define a transformação.

Cenas com movimento independente, baixa textura ou transforms instáveis são
`review` ou `reject`. A análise não tenta estabilizar o movimento interno do clip.

## Fases TDD

### Fase 0 — contrato puro CameraeMedia

- RED para identidade, translation, similarity e matriz inválida;
- RED para crop comum estável e rejeição por crop excessivo;
- RED garantindo que `reject` nunca chega como transformação aplicável;
- GREEN com DTOs `Sendable`, policy pura e sem AVFoundation;
- gate em `CameraeMediaTests`.

### Fase 1 — bridge de estimativa

- frames BGRA sintéticos com translation e similarity conhecidas;
- conversão da matriz 3x3 para parâmetros normalizados;
- escolha do modelo mais simples aprovado;
- limites de rotação, escala, overlap e paralaxe;
- cancelamento e erros tipados.

### Fase 2 — análise de clips

- extrator de frames e clock injetáveis;
- amostras determinísticas 20/50/80%;
- consenso robusto e descarte de outlier;
- cache por asset/fingerprint/configuração;
- cancelamento ao editar a timeline.

### Fase 3 — planejamento e composição

- `EditCompositionPlan` recebe alinhamento opcional por item;
- identidade preserva exatamente o export atual;
- correção individual é concatenada depois da orientação/aspect fit;
- crop global idêntico em todas as instruções;
- áudio e duração permanecem inalterados.

### Fase 4 — validação

- corpus sintético e pares reais;
- transições sem salto entre clips;
- nenhum frame com borda vazia;
- comparação disabled/translation/similarity;
- build Simulator e generic iOS device;
- orçamento em aparelho físico antes da promoção.

## Contrato com a futura interface

A interface deverá apenas selecionar uma política e observar um snapshot:

- desligado;
- analisando;
- alinhado sem deformação;
- alinhado com rotação/escala;
- revisão necessária;
- incompatível.

Ela não escolhe diretamente uma homografia nem manipula matrizes. O overhaul pode
substituir toda a apresentação sem alterar análise, composição ou persistência.
