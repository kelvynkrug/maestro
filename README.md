# Maestro

Controle de volume e saída de áudio **por aplicativo** no macOS, direto da barra de menu.

O macOS só oferece um volume global e uma saída padrão. O Maestro libera o que falta:

- **Volume independente por app** — call do Teams num nível, Spotify em outro.
- **Saída independente por app** — Teams no headset, Spotify na caixa de som, outro app no alto-falante do Mac.
- **Perfis nomeados** — salve o estado de todos os apps (volumes + saídas) e restaure com um clique.
- **Persistência** — a configuração de cada app é reaplicada automaticamente quando ele volta a tocar.
- **Atualização no próprio app** — o Maestro avisa quando há versão nova e se atualiza sozinho (Sparkle).

O app vive na barra de menu (ícone de três faders). O popover lista os apps tocando áudio, cada um com slider de volume e seletor de saída. Sem driver de áudio: devolver o controle de um app restaura o fluxo normal na hora.

## Requisitos

- macOS 15 (Sequoia) ou superior
- Na primeira vez que controlar um app, o macOS pede a permissão de **Gravação de Áudio do Sistema** — conceda uma vez

## Instalação

Via Homebrew (tap [`kelvynkrug/homebrew-tap`](https://github.com/kelvynkrug/homebrew-tap); requer uma release publicada):

```sh
brew install --cask kelvynkrug/tap/maestro
```

Ou baixe o `Maestro-x.y.z.zip` da [página de releases](https://github.com/kelvynkrug/maestro/releases) (app assinado e notarizado) e arraste para `/Applications`.

## Build a partir do código

Só precisa do Swift 6 via Command Line Tools — **não precisa do Xcode completo**:

```sh
git clone https://github.com/kelvynkrug/maestro.git
cd maestro
scripts/build-app.sh            # monta dist/Maestro.app (SwiftPM, assinatura ad-hoc)
scripts/build-app.sh --install  # + instala em /Applications e abre
```

## Como funciona por baixo

O Maestro usa **Core Audio Process Taps** (API pública desde o macOS 14.4). Para cada app controlado, cria um tap que captura e silencia o áudio original do processo, liga o tap a um aggregate device privado apontando para a saída escolhida e aplica o ganho num callback de áudio (IOProc). Volume é o multiplicador de ganho; trocar a saída é reconfigurar o aggregate. Nada de driver ou extensão de kernel — destruir o tap devolve o áudio ao comportamento normal do sistema, inclusive em caso de crash.

## Estrutura do projeto

```
Sources/MaestroEngine/   Core Audio: taps, aggregates, agrupamento de processos por app
Sources/MaestroApp/      SwiftUI: menu bar, popover, configurações, identidade visual
Sources/maestro-spike/   CLI usado para validar a rota técnica (fase 0)
packaging/               Info.plist, entitlements, cask de referência
scripts/                 build-app.sh, release.sh (notarização), generate-icon.swift
docs/                    arquitetura e roadmap
```

## Documentos

- [docs/arquitetura.md](docs/arquitetura.md) — rota técnica, APIs, permissões e riscos
- [docs/roadmap.md](docs/roadmap.md) — fases de implementação (próximas: perfis automáticos, EQ e boost)
