# Prototipo de alinhamento de imagens

## Objetivo

Este prototipo registra uma imagem movel contra uma imagem de referencia e gera artefatos que tornam a qualidade auditavel. O core e C++/OpenCV para que o mesmo algoritmo possa ser usado em iOS e Android.

Entradas avaliadas:

- `IMG_2025.HEIC`: referencia, 5712 x 4284.
- `IMG_2026.HEIC`: imagem movel, 5712 x 4284.

As fotos foram feitas de pontos de vista diferentes e contem objetos em profundidades muito diferentes: grade/janela perto da camera e vegetacao/rua longe. Isso produz **paralaxe**. Uma homografia e um modelo de um unico plano projetivo; por isso ela pode alinhar bem o fundo ou a grade, mas nao ambos ao mesmo tempo.

## Pipeline separavel

| Etapa | Papel | Controles atuais |
| --- | --- | --- |
| 1. Decodificacao | Aplica orientacao e entrega pixels BGR | feita pela plataforma no app; `imread` no laboratorio |
| 2. Preparacao | Reduz custo e melhora contraste local | `maxDimension`, `useCLAHE` |
| 3. Features | Detecta pontos e descreve vizinhancas | `ORB`, `AKAZE` ou `SIFT`; `maxFeatures` |
| 4. Matching | Encontra correspondencias entre as fotos | ratio test; `mutualMatching` opcional |
| 5. Geometria | Decide quais movimentos sao permitidos | translacao, similaridade, afim ou homografia |
| 6. Robustez | Rejeita correspondencias incompatíveis | RANSAC, limiar configuravel |
| 7. Refinamento | Otimiza alinhamento fotometrico | ECC opcional |
| 8. Warp | Gera a terceira imagem e mascara valida | perspectiva para o canvas da referencia |
| 9. Diagnostico | Mede e torna os erros visiveis | inliers, RMSE, overlap, MAE, overlay, heatmap, red/cyan |

Antes de aceitar o warp, o prototipo executa um **pre-voo** e classifica o par:

- **aceitar:** geometria estavel, boa area comum e residuo local dentro dos limites;
- **revisar:** a matriz e valida, mas ha sinais de paralaxe, movimento, recorte grande ou cobertura espacial fraca;
- **rejeitar:** poucos inliers, transformacao degenerada, perda extrema de area, erro alto ou deformacao excessiva.

O pre-voo considera numero e proporcao de inliers, cobertura por grade e por fecho convexo, RMSE, area comum, escala das quatro bordas, deslocamento dos cantos e erro simetrico entre bordas. Uma matriz calculavel nao e, sozinha, permissao para deformar a foto.

O recorte final e a compensacao de exposicao devem permanecer etapas posteriores e independentes. Eles nao devem alterar a estimativa geometrica nem esconder uma falha de alinhamento.

## Modelos geometricos

- **Translacao (2 parametros):** ideal para tripé, estrelas e pequenos tremores sem rotacao.
- **Similaridade (4 parametros):** translacao, rotacao e zoom uniforme; boa opcao para orientacao ao vivo.
- **Afim (6 parametros):** adiciona escala diferente por eixo e cisalhamento.
- **Homografia (8 parametros):** corrige perspectiva de um plano ou de uma cena distante quando a camera gira em torno do mesmo centro.
- **Fluxo optico/malha:** necessario quando se deseja deformar regioes com profundidades diferentes; precisa de regularizacao, mascaras de movimento e deghosting para nao distorcer objetos.

Regra pratica: usar o modelo menos flexivel que atende a captura. Mais parametros podem reduzir o erro numerico e ainda produzir uma transformacao visualmente errada.

## Resultado nas duas fotos

Todos os testes abaixo usaram largura maxima de 1920 px, mutual matching e RANSAC. Tempos sao do Mac usado no desenvolvimento e servem apenas como comparacao relativa.

| Detector/modelo | Tempo | Inliers | RMSE reprojecao | MAE antes -> depois | Area valida |
| --- | ---: | ---: | ---: | ---: | ---: |
| ORB + similaridade | 1,65 s | 564 / 1301 | 2,015 px | 47,249 -> 44,144 | 88,49% |
| ORB + afim | 1,33 s | 912 / 1301 | 1,406 px | 47,249 -> 41,981 | 89,59% |
| ORB + homografia | 2,43 s | 1177 / 1301 | 1,227 px | 47,249 -> 39,456 | 85,33% |
| SIFT + homografia | 2,22 s | 1592 / 1978 | 0,949 px | 47,249 -> 40,011 | 85,81% |
| ORB + homografia + ECC | 4,39 s | 1177 / 1301 | 1,734 px | 47,249 -> 39,325 | 85,02% |

Para este par, **ORB + homografia** oferece o melhor equilibrio inicial. ECC praticamente nao melhora o erro fotometrico, dobra o tempo e piora o erro dos pontos; portanto fica desligado por padrao. SIFT encontra mais inliers e menor RMSE, mas nao melhora o resultado fotometrico global.

O alto numero de inliers nao significa que toda a imagem esteja alinhada. A sobreposicao e o diagnostico red/cyan mostram residuo sistematico na grade, esperado pela paralaxe.

O pre-voo classifica esse primeiro par como **revisar**, com score 0,75, porque o residuo local de bordas indica paralaxe, vento ou objetos moveis.

### Segundo par, com menos paralaxe

`IMG_2029.HEIC` e `IMG_2030.HEIC` foram executadas com exatamente o mesmo preset. Os tres modelos foram aceitos, mas o modelo afim foi superior e tambem e mais simples que a homografia:

| Modelo | Inliers | RMSE | MAE antes -> depois | Area valida | Erro local | Pre-voo |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Similaridade | 1649 / 2511 | 1,654 px | 23,042 -> 12,509 | 96,84% | 2,202 px | aceitar |
| Afim | 2136 / 2511 | 1,462 px | 23,042 -> 12,143 | 96,69% | 1,760 px | aceitar |
| Homografia | 1982 / 2511 | 1,472 px | 23,042 -> 13,637 | 96,13% | 3,110 px | aceitar |

Esse resultado reforca duas decisoes: a orientacao de captura melhora muito a margem de seguranca, e o desktop deve comparar modelos para escolher o menos flexivel que entrega o menor residuo. Para este par, a escolha e **ORB + afim**.

## Comando

```sh
cmake -S vision -B .build/vision
cmake --build .build/vision

.build/vision/camerae-alignment-preview \
  --reference /caminho/IMG_2025.png \
  --moving /caminho/IMG_2026.png \
  --output-dir processing/out/alignment \
  --detector orb \
  --model homography \
  --max-dimension 1920 \
  --max-features 8000 \
  --match-ratio 0.80 \
  --mutual-matching 1 \
  --clahe 0 \
  --ecc 0
```

Saidas:

- `00_feasibility.jpg`: overlay com faixa verde, amarela ou vermelha e o motivo principal.
- `03_aligned.jpg`: terceira imagem, movel registrada no canvas da referencia.
- `04_overlay.jpg`: mistura 50/50 para inspecao visual.
- `05_difference_heatmap.jpg`: magnitude local do residuo.
- `06_red_cyan.jpg`: coincidencias ficam neutras; desalinhamentos criam bordas vermelhas/ciano.
- `07_inlier_matches.jpg`: correspondencias aceitas pelo RANSAC.
- `metrics.json`: metricas e matriz movel -> referencia.

## Recomendacao de arquitetura

1. **Qualidade final compartilhada:** manter a estimativa, validacao e warp no core C++/OpenCV. Para garantir paridade real, iOS e Android devem chamar a mesma implementacao e os mesmos presets, em vez de reimplementar a receita em Swift e Kotlin.
2. **iOS ao vivo:** manter Vision como backend leve para orientacao de enquadramento. `VNHomographicImageRegistrationRequest` ja existe no Camerae e evita custo adicional para essa etapa. Ele deve ser tratado como estimativa de UX, nao como definicao do render final.
3. **Android ao vivo:** usar o OpenCV compartilhado com frames reduzidos vindos do CameraX. Sensores podem fornecer a estimativa inicial e reduzir a busca visual.
4. **Versoes:** atualizar iOS 4.3 e Android 4.10 para uma versao unica e fixada. OpenCV 4.13 possui pacotes oficiais iOS e Android; medir compatibilidade e tamanho antes da troca.
5. **Peso:** criar builds mobile minimos com `core`, `imgproc`, `features2d`, `calib3d` e, somente se ECC permanecer, `video`. Decodificar HEIC/JPEG com APIs da plataforma permite dispensar `imgcodecs` no app.

## Proximos experimentos

- Comparar OpenCV e Vision no mesmo conjunto de 30 a 50 pares e em aparelhos reais.
- Adicionar mascara/ROI para o usuario escolher o plano importante quando houver paralaxe.
- Estimar distribuicao espacial do erro, nao apenas RMSE global.
- Detectar falha por cobertura insuficiente, transformacao degenerada ou residuo localizado alto.
- Para stacking, adicionar compensacao de exposicao e deghosting depois do alinhamento.
- Avaliar malha local/fluxo optico apenas para casos que realmente exigem multiplos planos.

## Fontes primarias

- OpenCV, feature matching e homografia: https://docs.opencv.org/4.x/d7/dff/tutorial_feature_homography.html
- OpenCV, `findHomography` e RANSAC: https://docs.opencv.org/4.x/d9/d0c/group__calib3d.html
- OpenCV, refinamento ECC: https://docs.opencv.org/4.x/dc/d6b/group__video__track.html
- OpenCV, ORB/AKAZE para tracking planar: https://docs.opencv.org/4.x/dc/d16/tutorial_akaze_tracking.html
- OpenCV 4.13, pacotes mobile oficiais: https://github.com/opencv/opencv/releases/tag/4.13.0
- Apple Vision, registro homografico: https://developer.apple.com/documentation/vision/vnhomographicimageregistrationrequest
- Apple Vision, alinhamento de imagens similares: https://developer.apple.com/documentation/vision/aligning-similar-images
- Android CameraX `ImageAnalysis`: https://developer.android.com/reference/androidx/camera/core/ImageAnalysis
