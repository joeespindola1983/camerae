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
- O APK `0.6.1` reconheceu fisicamente o modo Bulb e completou 3/3 capturas com cadência de 10 segundos. O manifesto associou cada captura ao handle, arquivo, tamanho e horário corretos, com os três downloads verificados byte a byte.
- APK `0.7.0` implementado: permite selecionar ISO e white balance somente entre os valores anunciados pela EOS R, exige confirmação por evento após a escrita e controla a duração Bulb pelo tempo entre `FullPress` e `FullRelease`.
- O log 16 foi criado somente após a recuperação/reconexão e não preservou a operação que bloqueou a câmera. O APK `0.7.1` passa a gravar cada comando PTP em arquivo e inclui a sessão anterior no log compartilhado, mesmo após reinício do processo.
- O `0.7.1` também executa a sequência de restauração usada pela referência Canon do libgphoto2 (`RemoteMode 0`, `RemoteMode 1`, `EventMode 0`) antes de fechar a sessão, com timeout curto e sem impedir a liberação da interface USB se a câmera não responder.
- O log 17 identificou uma resposta `GetDeviceInfo tx=0` atrasada: o retry reutilizou a mesma transação, consumiu a primeira resposta como se fosse sua e deixou o segundo container `DATA` para `OpenSession`. O APK `0.7.2` aguarda mais após uma falha, drena respostas tardias e exige uma janela bulk IN silenciosa depois do readiness antes de abrir a sessão.
- O log 18 validou a recuperação do `0.7.2`, mas o log 19 mostrou a EOS R reiniciando sua conexão USB durante o terceiro readiness de uma ação posterior; nenhum `SetDevicePropValueEx` chegou a ser enviado. O APK `0.7.3` reutiliza readiness no mesmo `deviceId`, aceita um par `GetDeviceInfo` tardio drenado como válido, interrompe após duas tentativas e para imediatamente se o device original desaparecer.
- O log 20 confirmou que até o primeiro `GetDeviceInfo` continuava retornando bulk IN inválido em conexões físicas limpas. Esse resultado encerrou os ajustes incrementais do transporte PTP manual.
- O APK `0.8.0` substitui o próximo marco por libgphoto2 2.5.34, libusb 1.0.29 e libltdl 2.5.4 compilados para Android `arm64-v8a`. O file descriptor autorizado pelo Android é entregue ao backend oficial por `gp_port_usb_set_sys_device`.
- Em `0.8.0`, captura, sequência e escrita pelo transporte manual estão desativadas. O novo botão `Testar libgphoto2 (somente leitura)` limita-se a inicializar a EOS R, obter seu resumo e ler a árvore de configuração procurando ISO, white balance, shutter, Bulb e capture target.
- O log 21 validou duas inicializações libgphoto2 completas na EOS R, leitura de ISO/WB/Bulb/capture target, `gp_camera_exit` limpo e um inventário MTP posterior de 17 imagens sem bloqueio da câmera.
- O APK `0.9.0` adiciona ISO, WB, formato JPG/CR3/JPG+CR3, duração Bulb de 1 a 120 s, captura teste, download dos arquivos anunciados pela câmera, thumbnails dos JPGs e exportação do JPG selecionado para `Fotos/Camerae` via MediaStore.
- O log 22 confirmou que ISO, WB, destino e formato foram escritos com sucesso, mas a EOS R não anuncia a ação genérica `bulb`. O APK `0.9.1` usa a ação anunciada `eosremoterelease` com `Press Full MF` e `Release`, e só reporta sucesso quando baixa a contagem esperada de arquivos.
- O log 23 validou a primeira captura completa pela lib: Bulb 5 s, JPG de 11.810.335 bytes, download 1/1 e saída limpa. O APK `0.10.0` repete essa unidade usando Fotos, Atraso e Intervalo, valida o download de cada etapa e permite cancelar entre exposições.
- Build debug `0.10.0` verificado e instalado com sucesso no SM-A065M em 11 de agosto de 2026.
- O log 24 validou a sequência libgphoto2 completa de 5/5 fotos: Bulb 8 s, JPG, ISO 6400, white balance Cloudy, download de todos os arquivos e `gp_camera_exit` limpo em cada captura.
- O APK `0.11.0` troca o lote de tamanho fixo por uma sessão contínua: `Iniciar sessão`, `Pausar sessão` e `Retomar sessão`. A pausa é aplicada somente depois que a exposição e o download atuais terminam.
- A interface `0.11.0` remove os probes, captura-teste e console visíveis, mantém o compartilhamento do log após a primeira captura e adota os tokens e a hierarquia Astro do Figma canônico (`Astro Photo / iPhone Portrait / Capture`, node `570:6`).
- O log 25 confirmou seis capturas em 72 segundos, mas também mostrou cerca de 12 MB transferidos após cada exposição. O APK `0.12.0` usa o cartão da câmera como armazenamento primário durante a noite: baixa automaticamente apenas o primeiro JPG, permite solicitar uma nova prévia na próxima foto e importa os JPGs restantes em lote depois da pausa.
- O APK `0.13.0` adiciona o catálogo simples de sessões do Figma, sem grupos: criar, abrir e excluir localmente. Cada sessão usa seu próprio diretório e `session.json`, persiste configurações e caminhos no cartão, pode ser retomada enquanto pausada e só se torna imutável após `Finalizar sessão`.
- Ao abrir uma sessão com a EOS R conectada, o app consulta diretamente os caminhos persistidos e informa quantos arquivos ainda existem no cartão. Essa verificação dirigida evita inventariar o SD inteiro a cada conexão.
- O APK `0.13.1` mostra `Canon EOS R` no lugar do caminho `/dev/bus/usb` na interface, sincroniza a métrica de exposição durante a edição e mantém em `PRÓXIMA` a contagem regressiva da exposição mesmo quando uma pausa segura já foi solicitada.
- A escrita de ISO/WB e a duração Bulb configurável ainda aguardam validação física; outras Canon permanecem em importação/diagnóstico até perfil próprio.

O roteiro de desenvolvimento e os critérios de decisão estão em [PLAN.md](PLAN.md).
A política de suporte por modelo está em [COMPATIBILITY.md](COMPATIBILITY.md).
As versões, hashes e decisões do build nativo estão em [NATIVE_DEPENDENCIES.md](NATIVE_DEPENDENCIES.md).

## Abrir e compilar

Abra esta pasta diretamente no Android Studio, ou use:

```bash
./gradlew assembleDebug
```

O APK esperado ficará em `app/build/outputs/apk/debug/app-debug.apk`.

Nesta máquina o projeto usa `compileSdk 36` porque é a plataforma Android instalada. O Android Gradle Plugin 8.7.3 emite um aviso de compatibilidade, mas o build termina com sucesso. Atualizar o plugin não é necessário para este protótipo.

## Testar disparo, leitura e download

### Primeiro teste do caminho libgphoto2 (`0.8.0`)

1. Confirme no topo `Versão 0.8.0 (build 19)`.
2. Conecte a EOS R ligada, com Wi-Fi desligado, e autorize o USB.
3. Toque uma única vez em `Testar libgphoto2 (somente leitura)`.
4. Não toque nos controles físicos nem desconecte o cabo enquanto o estado indicar operação USB/PTP.
5. Ao terminar, toque em `Compartilhar log`. O resultado esperado contém `gp_camera_init`, `gp_camera_get_summary`, `gp_camera_get_config` e `gp_camera_exit`.
6. Se houver erro ou a câmera reiniciar, não repita no mesmo attach: compartilhe o log e reconecte fisicamente antes de outro teste.

Esse probe não solicita captura e não escreve configurações. A conexão autorizada permanece aberta até o app encerrar ou a câmera ser desconectada, porque o backend Android do libgphoto2 mantém o dispositivo externo durante o processo.

### Sessões Astro econômicas (`0.13.0`)

1. Confirme `Versão 0.13.0 (build 25)` e crie ou abra uma sessão no catálogo.
2. Com a câmera conectada, uma sessão existente verifica os arquivos conhecidos no cartão e continua permitindo importação. Sessões finalizadas podem ser abertas e importadas, mas não retomadas.
3. Escolha ISO, white balance, JPG/CR3/JPG+CR3, exposição Bulb e o intervalo mínimo entre os inícios das fotos.
4. Toque em `Iniciar sessão`. O app captura sem um limite predefinido e `PRÓXIMA` mostra a contagem regressiva real.
5. Toque em `Pausar sessão` quando quiser interromper. Depois da pausa, escolha entre retomar ou `Finalizar sessão`.
6. A primeira foto baixa um JPG para a prévia. Para atualizar sem transferir todas as fotos, toque em `Atualizar prévia na próxima foto`; a próxima captura concluída substituirá a prévia.
7. Após pausar, toque em `Baixar JPGs da sessão` para fazer uma única importação em lote. Os CR3 permanecem no cartão nesta etapa econômica.
8. Toque em uma thumbnail JPG para visualizá-la e use `Exportar JPG selecionado para a Galeria` para copiá-la para `Fotos/Camerae`.
9. Depois da primeira captura, use `Compartilhar log da captura`. Em `JPG+CR3`, cada foto só é aceita quando os dois arquivos são registrados no cartão.

A captura configura o destino como cartão de memória, aplica somente escolhas anunciadas pela câmera e sempre tenta encerrar Bulb antes de fechar a sessão. O intervalo é medido entre os inícios planejados e, se uma captura/download ultrapassar esse intervalo, a próxima começa assim que a anterior terminar. Pausar nunca interrompe uma liberação Bulb em andamento.

### Fluxo legado (congelado em `0.8.0`)

1. Instale `app/build/outputs/apk/debug/app-debug.apk`.
2. Abra o app e conecte a EOS R ligada, em modo de fotografia, com Wi-Fi desligado.
3. Selecione o app quando o Android perguntar como tratar o dispositivo Canon.
4. Toque em `Autorizar USB` caso a permissão ainda não esteja concedida.
5. Confirme que o estado mostra a câmera pronta para diagnóstico.
6. Coloque a lente/câmera em foco manual (`MF`).
7. Para captura única, toque em `Capturar + baixar (MF)` e aguarde o fluxo terminar.
8. Toque em `Ler ISO, WB e shutter`, escolha somente os valores apresentados e toque em `Aplicar ISO + WB`; o app só considera sucesso após a EOS R anunciar os valores de volta.
9. Se a câmera estiver em Bulb, defina também a duração em segundos. Para sequência, use um intervalo maior que a exposição mais o tempo de transferência — por exemplo, Bulb de 5 s com intervalo de 15 s.
10. Defina `Fotos`, `Atraso` e `Intervalo`, toque em `Iniciar sequência` e aguarde `Sequência concluída`; cancelar durante uma exposição Bulb libera imediatamente o obturador antes da limpeza.
11. Confirme no log o nome/handle, os bytes de cada etapa e o caminho do `manifest.json`; `Ler câmera` e `Baixar última` continuam disponíveis para diagnóstico manual.
12. Toque em `Compartilhar log` e envie o texto completo para a próxima análise.

No APK `0.7.3`, o primeiro comando do attach removia respostas antigas da fila bulk IN e confirmava comunicação bidirecional com `GetDeviceInfo`, usando no máximo duas tentativas. Esse caminho permanece no código apenas como referência diagnóstica e seus botões de captura/configuração estão desativados em `0.8.0`.

## Preparação do teste físico

- Android com suporte a USB Host/OTG.
- Cabo USB-C de dados; adaptador OTG se necessário.
- Canon EOS R com bateria carregada e cartão SD.
- Câmera em modo de fotografia.
- Wi-Fi da câmera desligado.
- Canon Camera Connect, EOS Utility e outros clientes desconectados.

## Regra do protótipo

Este experimento foi autorizado sem TDD. A validação continua manual, orientada por logs e executada no aparelho e câmera reais. Desde `0.11.0`, a interface reutiliza a direção visual Astro do Figma canônico; se o código migrar para o Camerae, as regras normais de arquitetura, testes e contrato de capacidades voltam a valer integralmente.
