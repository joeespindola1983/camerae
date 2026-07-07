# camerae-processing

Laboratorio local para testar o processamento astro do Camerae sem instalar no iPhone.

O objetivo e evoluir aqui o algoritmo em C++/OpenCV e depois reaproveitar o mesmo core no iOS e Android.

## Dependencias

No macOS:

```sh
brew install opencv
```

Se o `pkg-config` nao estiver instalado:

```sh
brew install pkg-config
```

## Build

```sh
cmake -S . -B build
cmake --build build
```

## Preview Astro

```sh
./build/camerae-astro-preview \
  --input /caminho/para/frames \
  --output out/preview_stack_10.jpg \
  --profile milkyway \
  --stack 10 \
  --denoise 1 \
  --denoiser fastnlm \
  --denoise-strength 5 \
  --contrast 1.12 \
  --saturation 1.10 \
  --gamma 0.92
```

Para comparar stacks:

```sh
./build/camerae-astro-preview --input /frames --output out/stack_05.jpg --profile milkyway --stack 5
./build/camerae-astro-preview --input /frames --output out/stack_10.jpg --profile milkyway --stack 10
./build/camerae-astro-preview --input /frames --output out/stack_15.jpg --profile milkyway --stack 15
```

Ou:

```sh
bash scripts/compare_stacks.sh /frames milkyway
```

## Integracao com o app

O core C++ expoe duas entradas:

- `renderAstroPreview(inputDirectory, outputPath, settings)`: util para o CLI local.
- `renderAstroStack(framePaths, outputPath, settings, progressCallback, progressContext)`: entrada preparada para iOS/Android, onde o app ja monta cada lote de frames.

No iOS, o caminho esperado e chamar `renderAstroStack` por uma ponte Objective-C++ e trocar primeiro o preview do Laboratorio Astro. Depois que os resultados estiverem bons, o mesmo backend pode substituir o render final por lotes.

## ML / ONNX

Os scripts atuais nao carregam ONNX diretamente. O `tools/astro_render_mp4.py` tem uma opcao `--denoiser deepsnr`, mas ela chama um binario externo `deepsnr` e troca imagens TIFF por arquivos temporarios.

Para embarcar ML no iOS, precisamos de um modelo em formato importavel:

- `.mlmodel` ou `.mlpackage`: caminho preferido via Core ML.
- `.onnx`: converter para Core ML ou adicionar ONNX Runtime Mobile.
- apenas CLI/binario externo: nao e um bom alvo para iOS; precisamos do modelo ou de uma biblioteca embutivel.

## Parametros principais

- `--profile natural|milkyway|strong`
- `--stack N`
- `--start-frame N`
- `--max-dimension N`
- `--align 0|1`
- `--denoise 0|1`
- `--denoiser fastnlm|ml`
- `--denoise-strength N`
- `--denoise-color-strength N`
- `--contrast N`
- `--brightness N`
- `--saturation N`
- `--gamma N`

## Como pensar no fluxo

1. Exportar frames originais do app.
2. Rodar varias combinacoes localmente.
3. Comparar os JPGs em `out/`.
4. Quando o preset ficar bom, levar os mesmos parametros para o app.
