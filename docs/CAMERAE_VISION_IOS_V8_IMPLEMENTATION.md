# Camerae 8.0 — Camerae Vision no iOS

Status: fatia vertical implementada; OpenCV permanece em shadow mode, desligado
por padrão, até a validação física.

## Entrega

- OpenCV 4.13.0 fixado em um XCFramework reproduzível para iPhoneOS arm64 e
  iPhoneSimulator arm64;
- target `CameraeVision` separado do app e do pipeline Astro;
- bridge Objective-C++ em memória (`CVPixelBuffer` BGRA), sem UIImage/JPEG/HEIC
  no fast path;
- sessão C++ `CaptureFast` reutilizável, cancelável e com cache de referência;
- scheduler Swift com clock injetável, cadências 1/2/4 Hz, no máximo uma
  avaliação ativa e um frame pending latest-only;
- resultados com geração, descarte de stale e cooldown após falhas consecutivas;
- pausa para foto, vídeo, troca de lente, background, thermal serious/critical e
  memory warning;
- redução para 1 Hz em Low Power Mode e thermal fair;
- Apple Vision continua sendo o único backend que publica orientação visual;
- resultado OpenCV fica somente no snapshot diagnóstico do coordinator;
- release gate e CI verificam o XCFramework e executam os testes do bridge.

## Feature flag interna

A flag `CameraeVisionOpenCVShadowEnabled` usa `UserDefaults`. Ausente ou falsa,
nenhuma sessão OpenCV, worker ou cache de referência é criado. A configuração de
Release é `off`.

O shadow mode pode ser habilitado em um build interno antes de criar o
`CameraController`. Não existe controle de usuário nesta major.

## Gates automatizados

- characterization das matrizes do Apple Vision;
- contrato Objective-C++ com stride acolchoado, dimensões ímpares, orientação,
  cancel/resume, troca de referência, schema e matriz 3x3;
- adaptador OpenCV real no Simulator;
- scheduler determinístico sem sleeps;
- zero-instantiation quando disabled;
- backpressure com backend lento e descarte de geração antiga;
- suíte completa do scheme Camerae;
- testes C++ de Camerae Processing e Camerae Vision;
- build unsigned para generic iOS device;
- verificação de slices, versão e commit do OpenCV.

## Validação física antes de promover o backend

Ainda é obrigatória em aparelho; Simulator não aprova orçamento de câmera.

| Cenário | Métricas/aceite |
| --- | --- |
| iPhone antigo, intermediário e recente | preview estável; sem backlog crescente |
| wide/ultrawide/tele; retrato/paisagem | geração e orientação corretas |
| boa luz, baixa luz, blur e baixa textura | nenhum falso `accept` perigoso |
| pouco e muito paralaxe | alto paralaxe permanece `review/reject` |
| foto durante avaliação | regressão p95 de latência menor que 5% |
| 10 minutos contínuos | memória do componente menor que 16 MB e estável |
| Low Power / thermal fair | 1 Hz demonstrado |
| thermal serious/critical | zero nova avaliação |

Budget provisório: callback p95 abaixo de 1 ms, concorrência 1, pending menor ou
igual a 1 e CaptureFast balanced p95 abaixo de 100 ms no aparelho baseline.

O XCFramework local contém dois binários estáticos de aproximadamente 19 MB
cada (device e Simulator); somente o slice aplicável entra no produto. O delta
final comprimido do app deve ser registrado a partir do archive RC.
