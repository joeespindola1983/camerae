# Camerae GitFlow

Camerae uses a lightweight GitFlow that separates ongoing integration, tester builds, release stabilization, and published production history.

## Branches

- `main`: immutable line of approved production releases.
- `develop`: integration branch and base for the next version.
- `qa`: environment branch used to generate Firebase App Distribution builds from an active release candidate.
- `release/*`: stabilization branches cut from `develop`, for example `release/v5.0.0`.
- `feature/*`, `fix/*`, or `codex/*`: required short-lived implementation branches.
- `hotfix/*`: urgent production fixes cut from `main`.

## Invariants

- Normal development always starts from current `develop`, uses a short-lived branch, and returns through a pull request.
- Product and process changes never commit directly to `develop`.
- Normal feature, improvement, maintenance, documentation, and process PRs target `develop`.
- Stabilization fixes start from the active release commit and target the active `release/vX.Y.Z` branch.
- A Draft PR is work in progress or a candidate not yet selected for the next version. Ready for review means the scope is selected and full CI should run.
- `qa` is a deployment target, never the source branch for features or the next release.
- Release fixes are committed to `release/*` and promoted again to `qa`.
- Every QA-approved candidate is returned to `develop` immediately. Development never continues from a `develop` that is behind the approved QA candidate.
- `main`, `qa`, and `develop` must all contain the approved production release before development of the following version proceeds.
- A production tag points to the exact approved release commit.
- Never commit feature work directly to `main` or `qa`.

## Flow

1. Record candidate functionality or improvement in a structured GitHub issue.
2. Switch to synchronized `develop`, create a short-lived branch, and open a Draft PR targeting `develop`.
3. Keep candidate work in Draft while its scope or version is undecided. When selected, assign the intended milestone, complete the PR template, add `CHANGELOG.md` coverage, and mark it ready.
4. Merge a ready PR only after required checks pass. The merged commit becomes part of the next-version integration history on `develop`.
5. Cut `release/vX.Y.Z` from `develop` when the selected version enters stabilization.
6. Bump versions, move the applicable `CHANGELOG.md` entries from `Unreleased` into a dated version section, finalize release notes, and merge or fast-forward the release candidate into `qa`.
7. Finalize detailed Firebase release notes, then run `ios/scripts/release-gate.sh firebase --publish` from a synchronized local `qa` and validate the Firebase build.
8. After QA approves the candidate, merge or fast-forward that exact release commit into `develop`.
9. Apply every later stabilization fix through a PR targeting the active `release/vX.Y.Z`, update `qa`, repeat validation, and reconcile each newly approved candidate into `develop`.
10. After production approval, merge or fast-forward the release into `main` and tag that exact commit as `vX.Y.Z`.
11. Align `develop` and `qa` with the approved production commit.
12. Verify that the tag is reachable from `main`, `qa`, and `develop` before starting the next version.

QA builds that are not production releases may use prerelease tags such as `vX.Y.Z-qa.N`. Merely setting `MARKETING_VERSION` to `X.Y.Z` on `qa` does not make that commit the final tagged release.

`CHANGELOG.md` is mandatory release state. Every user-visible, architecture, dependency, privacy, build, or release-process change is added under `Unreleased` during development. A release candidate receives a dated version section containing its status, affected areas, and categorized changes before the first QA tag. Stabilization fixes are appended to the same version section before the final production tag.

Hotfixes start from `main`, are released and tagged through the same validation gates, and are merged back into both `develop` and `qa`.

## Decision queue

GitHub state makes release selection explicit:

- An issue is a candidate or backlog item.
- A Draft PR is active exploration and does not reserve a place in the next version.
- A ready PR with the intended milestone is selected for review and full CI.
- A PR merged into `develop` is committed to the next release cut unless explicitly reverted.
- An unmerged Draft PR can remain open, move to a later milestone, or close without contaminating `develop`.

This keeps independent features, improvements, and experiments reviewable without forcing them into the same major release.

## Pull request routing

| Change | Source | PR base |
| --- | --- | --- |
| Feature, improvement, maintenance, docs, process | synchronized `develop` | `develop` |
| Stabilization fix | active `release/vX.Y.Z` | active `release/vX.Y.Z` |
| Urgent production hotfix | `main` | `main` |
| Release promotion | exact approved release commit | performed by the release process, never feature work |

PRs never target `qa` for product development. Promotion to `qa` must preserve the exact release-candidate commit used for Firebase validation.

## Development commands

The safe default for a new task is:

```sh
git fetch origin
git switch develop
git pull --ff-only origin develop
git switch -c codex/<short-description>
git push -u origin codex/<short-description>
gh pr create --draft --base develop
```

Complete the PR template when opening the draft. Mark it ready only after deciding
that the change belongs in the intended version and after relevant local tests
pass.

Before creating a release, confirm that work started from `develop` and cut the stabilization branch from it:

```sh
git switch develop
git switch -c release/vX.Y.Z
```

After each QA approval, update `develop` immediately:

```sh
git switch develop
git merge --ff-only release/vX.Y.Z
git push origin develop
```

If `--ff-only` fails, stop and inspect the divergence instead of forcing a branch. When production approves the version, advance `main`, create the final annotated tag, then align `develop` and `qa` with the same approved commit.

If product work is committed directly to `qa`, stop new development, reconcile its history through a release branch, validate it, promote it to `main`, and recreate or update `develop` from the approved release before continuing.

## Release gate local

Publicação e validação não são disparadas automaticamente pelo GitHub. O desenvolvedor executa um gate local no Mac que mantém o certificado e os provisioning profiles no Keychain:

```sh
cd ios
scripts/release-gate.sh check
scripts/release-gate.sh firebase --publish
scripts/release-gate.sh appstore --publish
scripts/release-gate.sh check --ui-evidence
```

O gate bloqueia publicação quando há alterações rastreadas, arquivos não rastreados dentro de `ios/`, branch incorreta, commit diferente do upstream, versão inválida, assinatura ausente, teste com falha ou build inválido. Toda publicação Firebase de QA tem como destino canônico o grupo `testers`; o script aplica esse padrão mesmo quando `FIREBASE_GROUPS` não está definido. Use outro grupo somente durante uma migração intencional e documentada. Firebase também exige `qa` e release notes detalhadas; App Store Connect exige `release/v<MARKETING_VERSION>`. A opção `--publish` torna qualquer mutação externa explícita.

O gate roda `pod install --deployment`, fronteiras de arquitetura, testes Swift, testes C++ e build genérico sem assinatura antes de chamar o archive assinado. Evidências visuais são opcionais para não atrasar mudanças sem impacto de interface: use `--ui-evidence` para gerar e arquivar a matriz de iPhone e iPad nos seis idiomas suportados. A matriz completa também pode ser executada diretamente com `./scripts/generate-ui-evidence.sh --all-devices --all-locales --archive-tracked`. As evidências temporárias ficam em `ios/build/ui-evidence`; PNGs, manifesto e galeria HTML são copiados para `docs/ui-evidence/`, usando sufixos de device e idioma como `-ipad`, `-de` e `-ipad-ru`, e devem ser commitados após a publicação. IPA, ZIP e dados derivados continuam locais. O gate usa `Camerae.xcworkspace`; o `.xcodeproj` isolado não contém as dependências CocoaPods.

O workflow `iOS Build` valida a política em todo Draft PR direcionado a `develop` ou `release/*`. Quando o PR é marcado como pronto, também executa testes e build iOS no macOS e os testes C++ no Linux. Execuções antigas do mesmo PR são canceladas quando um novo commit chega. O acionamento manual por `workflow_dispatch` continua disponível para diagnóstico.

Os workflows de Firebase e App Store permanecem somente por `workflow_dispatch`.
O workflow `Publish GitHub Release` é a etapa final da promoção: ele reage a
uma tag final `vX.Y.Z` ou pode ser reexecutado manualmente para uma tag
existente. Antes de criar a página em GitHub Releases, valida que a tag é
SemVer final, que existe de forma imutável e que seu commit está contido em
`main`. Tags `-qa.N` nunca são publicadas como releases. A operação é
idempotente para permitir recuperação segura de execuções interrompidas.

## Registro de submissões à App Store

O início de `CHANGELOG.md` mantém uma tabela operacional separada para versões
enviadas à Apple. Estados internos como QA candidate e release candidate não
substituem o estado da submissão.

Atualize a tabela e a entrada da versão quando o App Store Connect mudar entre
Prepared, Submitted, In Review, Approved, Available ou Rejected. Registre a
data da confirmação e diferencie explicitamente aprovação da Apple de
disponibilidade pública. Distribuições Firebase e builds locais não entram
nesse registro.

Depois da aprovação de produção, promova o commit exato para `main`, crie e
envie a tag anotada final e confirme que o workflow `Publish GitHub Release`
criou a página correspondente. A página de release não substitui o registro de
status da Apple e não deve ser criada para candidatos de QA.

## GitHub repository settings

After this workflow exists on `develop`, protect `develop` with a GitHub ruleset:

- require a pull request before merging;
- require the `Validate PR workflow`, `Build and test Camerae`, and `Test C++ processing core` checks;
- require the branch to be up to date before merge;
- block force pushes and branch deletion;
- allow repository administrators to bypass only for documented release recovery.

Keep `qa` and `main` governed by the release-promotion invariants above. Do not configure an automatic merge from feature branches into either branch.

Android automation is intentionally paused while Camerae is developed and validated on iOS.

## Configuração local de distribuição

Copie `ios/Config/Release.env.example` para `ios/Config/Release.local.env` e preencha apenas o necessário. O arquivo local é ignorado pelo Git. A chave privada `.p8`, certificados, senhas e tokens nunca entram no repositório.

O Firebase CLI pode usar a sessão criada por `firebase login`; configure o app e o projeto no arquivo local. O grupo canônico de distribuição é sempre `testers` e já é o padrão do script, portanto não depende de configuração local. `FIREBASE_GROUPS` só deve ser alterado para uma migração intencional e documentada. Toda publicação Firebase deve definir exatamente uma fonte de notas: `RELEASE_NOTES` para texto direto ou `RELEASE_NOTES_FILE` para um arquivo não vazio. As notas devem resumir funcionalidades, correções, riscos e o foco esperado da validação de QA. O gate interrompe a execução antes do archive quando as notas estão ausentes, vazias ou ambíguas. Para App Store Connect, informe Team ID e o caminho local da chave API `.p8`, seu Key ID e Issuer ID.

Os scripts usam somente identidades e profiles já instalados por padrão (`ALLOW_PROVISIONING_UPDATES=0`). Se for realmente necessário permitir ao Xcode atualizar um profile, faça isso conscientemente numa execução local com `ALLOW_PROVISIONING_UPDATES=1`; o gate nunca habilita essa opção durante publicação.

Os ambientes e perfis de assinatura do iOS estão detalhados em
[`QA_ENVIRONMENTS.md`](QA_ENVIRONMENTS.md).
