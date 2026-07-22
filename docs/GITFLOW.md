# Camerae GitFlow

Camerae uses a lightweight GitFlow that separates ongoing integration, tester builds, release stabilization, and published production history.

## Branches

- `main`: immutable line of approved production releases.
- `develop`: integration branch and base for the next version.
- `qa`: environment branch used to generate Firebase App Distribution builds from an active release candidate.
- `release/*`: stabilization branches cut from `develop`, for example `release/v5.0.0`.
- `feature/*` or `codex/*`: short-lived implementation branches.
- `hotfix/*`: urgent production fixes cut from `main`.

## Invariants

- Feature branches start from current `develop` and merge back to `develop`.
- `qa` is a deployment target, never the source branch for features or the next release.
- Release fixes are committed to `release/*`, promoted again to `qa`, and returned to `develop` when the release closes.
- `main`, `qa`, and `develop` must all contain the approved production release before development of the following version proceeds.
- A production tag points to the exact approved release commit.
- Never commit feature work directly to `main` or `qa`.

## Flow

1. Create `feature/*` or `codex/*` from `develop` and merge completed work back to `develop`.
2. Cut `release/vX.Y.Z` from `develop` when the version enters stabilization.
3. Bump versions, finalize release notes, and merge or fast-forward the release candidate into `qa`.
4. From a synchronized local `qa`, run `ios/scripts/release-gate.sh firebase --publish` and validate the Firebase build.
5. Apply every stabilization fix to `release/vX.Y.Z`, update `qa`, and repeat validation.
6. After approval, merge the release into `main` and tag that exact commit as `vX.Y.Z`.
7. Merge the approved release back into `develop` and align `qa` with the approved release commit.
8. Verify that the tag is reachable from `main`, `qa`, and `develop` before starting the next version.

QA builds that are not production releases may use prerelease tags such as `vX.Y.Z-qa.N`. Merely setting `MARKETING_VERSION` to `X.Y.Z` on `qa` does not make that commit the final tagged release.

Hotfixes start from `main`, are released and tagged through the same validation gates, and are merged back into both `develop` and `qa`.

If product work is committed directly to `qa`, stop new development, reconcile its history through a release branch, validate it, promote it to `main`, and recreate or update `develop` from the approved release before continuing.

## Release gate local

Publicação e validação não são disparadas automaticamente pelo GitHub. O desenvolvedor executa um gate local no Mac que mantém o certificado e os provisioning profiles no Keychain:

```sh
cd ios
scripts/release-gate.sh check
scripts/release-gate.sh firebase --publish
scripts/release-gate.sh appstore --publish
```

O gate bloqueia publicação quando há alterações rastreadas, arquivos não rastreados dentro de `ios/`, branch incorreta, commit diferente do upstream, versão inválida, assinatura ausente, teste com falha ou build inválido. Firebase exige `qa`; App Store Connect exige `release/v<MARKETING_VERSION>`. A opção `--publish` torna qualquer mutação externa explícita.

O gate roda `pod install --deployment`, fronteiras de arquitetura, testes Swift, testes C++, evidências visuais de iPhone e iPad nos seis idiomas suportados e build genérico sem assinatura antes de chamar o archive assinado. A matriz completa também pode ser executada diretamente com `./scripts/generate-ui-evidence.sh --all-devices --all-locales --archive-tracked`. As evidências temporárias ficam em `ios/build/ui-evidence`; PNGs, manifesto e galeria HTML são copiados para `docs/ui-evidence/`, usando sufixos de device e idioma como `-ipad`, `-de` e `-ipad-ru`, e devem ser commitados após a publicação. IPA, ZIP e dados derivados continuam locais. O gate usa `Camerae.xcworkspace`; o `.xcodeproj` isolado não contém as dependências CocoaPods.

Os workflows GitHub Actions permanecem disponíveis somente por `workflow_dispatch` como ferramenta manual de diagnóstico. Não publicam nem compilam automaticamente em pushes, PRs ou tags.

Android automation is intentionally paused while Camerae is developed and validated on iOS.

## Configuração local de distribuição

Copie `ios/Config/Release.env.example` para `ios/Config/Release.local.env` e preencha apenas o necessário. O arquivo local é ignorado pelo Git. A chave privada `.p8`, certificados, senhas e tokens nunca entram no repositório.

O Firebase CLI pode usar a sessão criada por `firebase login`; configure o app, projeto e grupo no arquivo local. Para App Store Connect, informe Team ID e o caminho local da chave API `.p8`, seu Key ID e Issuer ID.

Os scripts usam somente identidades e profiles já instalados por padrão (`ALLOW_PROVISIONING_UPDATES=0`). Se for realmente necessário permitir ao Xcode atualizar um profile, faça isso conscientemente numa execução local com `ALLOW_PROVISIONING_UPDATES=1`; o gate nunca habilita essa opção durante publicação.
