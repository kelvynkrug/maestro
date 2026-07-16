# Maestro

Controle de áudio por aplicativo para macOS, inspirado no SoundSource. Uso pessoal.

## O problema

O macOS só tem um volume global e uma saída padrão. A demanda:

- **Volume independente por app** — call do Teams num nível, Spotify em outro.
- **Saída independente por app** — Teams no headset, Spotify na caixa de som, outro app no alto-falante do Mac.

## Decisões tomadas (2026-07-16)

| Decisão | Escolha |
|---|---|
| Stack | Swift nativo (SwiftUI + Core Audio) |
| Interface | App de menu bar (popover com sliders e seletor de saída por app) |
| Escopo do MVP | Volume por app **+** roteamento por app juntos |
| Rota técnica | Core Audio **Process Taps** (macOS 14.4+) — sem driver de áudio próprio |
| Distribuição | Nenhuma — build local, assinatura ad-hoc |
| Identidade visual | Marca "Console" (proposta B — três faders formando o M) com a paleta "Batuta" (proposta A): marinho `#1B2138`, latão `#C9A455`, marfim `#F2EDE3`, plateia `#9AA3BF`. Coloração: **V1 · Latão clássico** (trilha acesa em latão, knobs marfim) |

Extras no radar (pós-MVP, em ordem): persistência de config por app, perfis automáticos (ex.: call no Teams abaixa o Spotify), EQ e boost acima de 100%.

Fora de escopo por decisão: atalhos globais de teclado.

## Ambiente

- macOS 26.5.2 (Process Taps disponíveis desde o 14.4)
- Swift 6.3.3 via Command Line Tools — **sem Xcode completo instalado**
- Saídas de áudio existentes para testar roteamento: monitor DisplayPort (CZ270F165), USB PnP Audio Device

## Como buildar e instalar o app

```sh
scripts/build-app.sh            # monta dist/Maestro.app (SwiftPM, sem Xcode)
scripts/build-app.sh --install  # + instala em /Applications e abre
```

O Maestro vive na barra de menu (ícone de três faders). No primeiro controle de um app, o macOS pede a permissão de **Gravação de Áudio do Sistema** — conceda uma vez. Estrutura: `Sources/MaestroEngine` (Core Audio), `Sources/MaestroApp` (SwiftUI), `packaging/Info.plist`, `scripts/`.

## Como rodar o spike (fase 0)

```sh
swift run maestro-spike list                      # apps com áudio + saídas disponíveis
swift run maestro-spike tap spotify --volume 50   # intercepta o Spotify a 50%
swift run maestro-spike tap teams --out 1         # Teams direto na saída [1]
```

No modo interativo: `0-200` define o volume em %, `o` lista as saídas, `o N` troca a saída ao vivo, `q` encerra e devolve o áudio ao normal.

## Documentos

- [docs/arquitetura.md](docs/arquitetura.md) — rota técnica, APIs, permissões e riscos
- [docs/roadmap.md](docs/roadmap.md) — fases de implementação com critérios de pronto
- [docs/identidade-visual/propostas.html](docs/identidade-visual/propostas.html) — identidade visual (escolhida: Console × Batuta, V1)
