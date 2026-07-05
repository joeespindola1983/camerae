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

## Parametros principais

- `--profile natural|milkyway|strong`
- `--stack N`
- `--start-frame N`
- `--max-dimension N`
- `--align 0|1`
- `--denoise 0|1`
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
