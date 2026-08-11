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
- Marco M1 implementado: detecção, permissão, topologia USB e exportação de log.
- Build debug `0.1.0` verificado com sucesso em 11 de agosto de 2026.
- Nenhum protocolo ou comando de câmera implementado ainda.

O roteiro de desenvolvimento e os critérios de decisão estão em [PLAN.md](PLAN.md).

## Abrir e compilar

Abra esta pasta diretamente no Android Studio, ou use:

```bash
./gradlew assembleDebug
```

O APK esperado ficará em `app/build/outputs/apk/debug/app-debug.apk`.

Nesta máquina o projeto usa `compileSdk 36` porque é a plataforma Android instalada. O Android Gradle Plugin 8.7.3 emite um aviso de compatibilidade, mas o build termina com sucesso. Atualizar o plugin não é necessário para iniciar o marco M1.

## Coletar o primeiro log

1. Instale `app/build/outputs/apk/debug/app-debug.apk`.
2. Abra o app e conecte a EOS R ligada, em modo de fotografia, com Wi-Fi desligado.
3. Selecione o app quando o Android perguntar como tratar o dispositivo Canon.
4. Toque em `Autorizar USB` caso a permissão ainda não esteja concedida.
5. Confirme que o estado mostra a câmera pronta para diagnóstico.
6. Toque em `Compartilhar log` e envie o texto completo para a próxima análise.

Este APK apenas inspeciona e abre/fecha a conexão para confirmar acesso. Ele ainda não envia comandos PTP e não dispara a câmera.

## Preparação do teste físico

- Android com suporte a USB Host/OTG.
- Cabo USB-C de dados; adaptador OTG se necessário.
- Canon EOS R com bateria carregada e cartão SD.
- Câmera em modo de fotografia.
- Wi-Fi da câmera desligado.
- Canon Camera Connect, EOS Utility e outros clientes desconectados.

## Regra do protótipo

Este experimento foi autorizado sem Figma e sem TDD. A validação será manual, orientada por logs e executada no aparelho e câmera reais. Se a viabilidade for comprovada e o código migrar para o Camerae, as regras normais de arquitetura, testes e contrato de capacidades voltam a valer.
