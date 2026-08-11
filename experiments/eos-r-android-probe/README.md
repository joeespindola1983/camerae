# Camerae EOS R Probe

Aplicativo Android experimental e independente para validar controle e ingestão de imagens de uma Canon EOS R por cabo USB.

O projeto é deliberadamente pequeno. Ele não faz parte do aplicativo Camerae, não compartilha seu `applicationId` e não deve receber arquitetura ou interface de produto antes da prova física com a câmera.

## Resultado que queremos provar

```text
Conectar EOS R por USB -> abrir o app -> tocar em Capturar
-> a câmera fotografa -> JPEG aparece no Android -> CR3 pode ser salvo
```

## Estado atual

- Projeto Android independente criado.
- `applicationId`: `com.camerae.eosrprobe`.
- USB Host declarado no manifesto.
- Filtro para o vendor ID USB da Canon (`0x04A9`) configurado.
- Marco M1 validado na EOS R: detecção, permissão e topologia USB.
- Marco M2 validado na EOS R: sessão MTP/PTP, inventário do cartão e download de um CR3 de 32.312.487 bytes.
- Marco M3 validado para um disparo: a sequência Canon EOS criou `5S8A9566.CR3` e o Android importou os 40.307.117 bytes.
- O APK `0.4.1` conseguiu importar automaticamente `5S8A9568.CR3` com os 40.316.045 bytes exatos, mas somente após duas falhas `MTP → PTP` e reconexões físicas.
- O teste `0.4.2` confirmou transporte estável e revelou que a EOS R emite `0xC1A7 ObjectAddedEx64` cerca de 3,5 s após o disparo, em vez da variante `0xC181` inicialmente implementada.
- O APK `0.4.4` validou o fluxo definitivo: `ObjectAddedEx64` em 3,021 s, importação MTP em uma tentativa e 40.415.295 bytes exatos de `5S8A9571.CR3`.
- O primeiro teste do `0.5.0` iniciou 3,9 s após o attach e encontrou o endpoint PTP ainda indisponível antes de `OpenSession`.
- O APK `0.5.2` validou uma sequência física de cinco capturas e downloads, com cadência de 10 segundos, readiness na primeira tentativa e nenhum desalinhamento PTP.
- O APK `0.6.0` confirmou fisicamente ISO 6400 com 28 opções e white balance por temperatura de cor com 10 opções. A EOS R estava em modo Bulb e corretamente não anunciou uma lista de velocidades selecionáveis.
- APK `0.6.1` implementado: reconhece o modo de exposição anunciado pela câmera e trata shutter sem lista, quando em Bulb, como controle de duração por pressão remota em vez de falha de capabilities.
- Build debug `0.6.1` verificado com sucesso em 11 de agosto de 2026.
- O manifesto da sequência e o novo diagnóstico de modo Bulb ainda aguardam validação física; outras Canon permanecem em importação/diagnóstico até perfil próprio.

O roteiro de desenvolvimento e os critérios de decisão estão em [PLAN.md](PLAN.md).
A política de suporte por modelo está em [COMPATIBILITY.md](COMPATIBILITY.md).

## Abrir e compilar

Abra esta pasta diretamente no Android Studio, ou use:

```bash
./gradlew assembleDebug
```

O APK esperado ficará em `app/build/outputs/apk/debug/app-debug.apk`.

Nesta máquina o projeto usa `compileSdk 36` porque é a plataforma Android instalada. O Android Gradle Plugin 8.7.3 emite um aviso de compatibilidade, mas o build termina com sucesso. Atualizar o plugin não é necessário para este protótipo.

## Testar disparo, leitura e download

1. Instale `app/build/outputs/apk/debug/app-debug.apk`.
2. Abra o app e conecte a EOS R ligada, em modo de fotografia, com Wi-Fi desligado.
3. Selecione o app quando o Android perguntar como tratar o dispositivo Canon.
4. Toque em `Autorizar USB` caso a permissão ainda não esteja concedida.
5. Confirme que o estado mostra a câmera pronta para diagnóstico.
6. Coloque a lente/câmera em foco manual (`MF`).
7. Para captura única, toque em `Capturar + baixar (MF)` e aguarde o fluxo terminar.
8. Toque em `Ler ISO, WB e shutter` e confirme que os três controles mostram valor atual e quantidade de opções; esta versão ainda não escreve propriedades.
9. Para sequência, defina `Fotos`, `Atraso` e `Intervalo` e toque em `Iniciar sequência`.
10. Aguarde `Sequência concluída`; o cancelamento é aplicado com segurança entre operações de câmera.
11. Confirme no log o nome/handle, os bytes de cada etapa e o caminho do `manifest.json`; `Ler câmera` e `Baixar última` continuam disponíveis para diagnóstico manual.
12. Toque em `Compartilhar log` e envie o texto completo para a próxima análise.

No APK `0.6.1`, cada foto primeiro remove respostas antigas da fila bulk IN e confirma comunicação bidirecional com `GetDeviceInfo`, usando até seis tentativas com backoff antes de abrir a sessão. Durante a sessão, containers atrasados de outras transações são registrados e ignorados com um limite de segurança. Em seguida dispara, aguarda `ObjectAddedEx/64` e busca o handle diretamente por MTP. Na sequência, o intervalo é medido entre os inícios planejados; se captura/download demorarem mais, a próxima foto começa assim que a operação anterior termina, nunca em paralelo. Cada sequência recebe uma pasta própria contendo os arquivos baixados e um `manifest.json` atualizado atomicamente após cada foto. A descoberta de controles interpreta `PropValueChanged` e `AvailListChanged`; no modo Bulb, a ausência da lista de shutter é identificada como duração por pressão remota, não como erro. O app ainda não altera parâmetros nem o destino de captura.

## Preparação do teste físico

- Android com suporte a USB Host/OTG.
- Cabo USB-C de dados; adaptador OTG se necessário.
- Canon EOS R com bateria carregada e cartão SD.
- Câmera em modo de fotografia.
- Wi-Fi da câmera desligado.
- Canon Camera Connect, EOS Utility e outros clientes desconectados.

## Regra do protótipo

Este experimento foi autorizado sem Figma e sem TDD. A validação será manual, orientada por logs e executada no aparelho e câmera reais. Se a viabilidade for comprovada e o código migrar para o Camerae, as regras normais de arquitetura, testes e contrato de capacidades voltam a valer.
