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
- Marco M3 implementado para teste físico: transporte PTP USB mínimo e disparo remoto único com comandos Canon EOS.
- Build debug `0.3.0` verificado com sucesso em 11 de agosto de 2026.
- Captura remota ainda aguarda validação física; alteração de parâmetros não foi implementada.

O roteiro de desenvolvimento e os critérios de decisão estão em [PLAN.md](PLAN.md).

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
7. Toque uma vez em `Disparar teste (MF)` e aguarde a câmera terminar de gravar no cartão.
8. Confirme visualmente que o contador/atividade da câmera indica uma nova foto.
9. Toque em `Ler câmera` e confira se um novo arquivo aparece no inventário.
10. Toque em `Baixar última` e confirme o caminho local registrado no log.
11. Toque em `Compartilhar log` e envie o texto completo para a próxima análise.

No APK `0.3.0`, o botão de disparo abre uma sessão PTP própria, ativa os modos remotos Canon e executa meio-pressionamento, pressionamento completo e ambas as liberações. O app não altera o destino de captura: espera que a configuração atual continue salvando no cartão. Depois de fechar essa sessão, `Ler câmera` e `Baixar última` reutilizam a integração MTP já validada.

## Preparação do teste físico

- Android com suporte a USB Host/OTG.
- Cabo USB-C de dados; adaptador OTG se necessário.
- Canon EOS R com bateria carregada e cartão SD.
- Câmera em modo de fotografia.
- Wi-Fi da câmera desligado.
- Canon Camera Connect, EOS Utility e outros clientes desconectados.

## Regra do protótipo

Este experimento foi autorizado sem Figma e sem TDD. A validação será manual, orientada por logs e executada no aparelho e câmera reais. Se a viabilidade for comprovada e o código migrar para o Camerae, as regras normais de arquitetura, testes e contrato de capacidades voltam a valer.
