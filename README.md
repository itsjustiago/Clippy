# Clippy 📋

Histórico de clipboard para macOS — o equivalente ao **Win + V** do Windows.
Atalho global: **`⌥V`** (Option + V).

App nativa em Swift/SwiftUI que vive na barra de menus, guarda tudo o que copias
(texto e imagens) e deixa-te colar itens antigos com um atalho global.

## ⬇️ Download

**[Descarregar a última versão (Clippy.zip)](https://github.com/itsjustiago/Clippy/releases/latest/download/Clippy.zip)**

1. Descompacta e arrasta **Clippy.app** para a pasta *Aplicações*.
2. A app é assinada com um certificado próprio (não é da App Store), por isso o macOS
   bloqueia-a à primeira abertura. Para autorizar, corre no Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Clippy.app
   ```
   *(em alternativa: botão direito em Clippy.app → Abrir → Abrir)*
3. Abre a Clippy e carrega em **`⌥V`**.

> Preferes compilar a partir do código? Salta para [Compilar e instalar](#compilar-e-instalar).

## Funcionalidades

- **Atalho global `⌥V`** — abre um painel flutuante em qualquer app.
- **Pesquisa instantânea** — escreve para filtrar o histórico.
- **Navegação por teclado** — `↑`/`↓` para mover, `↵` para colar, `esc` para fechar.
- **Colar automático** — o item selecionado é colado na app onde estavas (precisa de permissão de Acessibilidade).
- **Atalhos rápidos** — `⌘1`…`⌘9` colam diretamente os primeiros itens.
- **Fixar favoritos** (`⌘P`) — ficam sempre no topo e não são apagados.
- **Apagar** (`⌘⌫`) itens individuais ou limpar o histórico não-fixado.
- **Texto e imagens** — imagens guardadas em disco, com miniatura.
- **App de origem** — mostra de que aplicação veio cada cópia.
- **Privacidade** — ignora conteúdo marcado como sensível por gestores de palavras-passe.
- **Menu na barra** — vê os últimos itens, limpa o histórico, arranque automático.
- Sem ícone no Dock. Histórico guardado localmente (até 200 itens).

## Compilar e instalar

```bash
./build.sh    # compila, assina, instala em /Applications e arranca
```

Na primeira vez cria automaticamente um certificado próprio (`./setup-signing.sh`)
numa keychain dedicada. Esse certificado dá à app uma **identidade estável**, para
que a permissão de Acessibilidade cole de vez e **não volte a ser pedida a cada
recompilação** (o problema típico das apps assinadas ad-hoc).

Requisitos: macOS 14+ e as Command Line Tools (`swift`).

## Primeira utilização

1. Abre a app — aparece o ícone 📋 na barra de menus.
2. Copia algumas coisas (`⌘C`).
3. Carrega em **`⌥V`** para abrir o histórico.
4. **Para o colar automático:** na primeira vez que colas, o macOS pede
   permissão de **Acessibilidade**. Ativa *Clippy* em
   *Definições do Sistema → Privacidade e Segurança → Acessibilidade*.
   Graças ao certificado estável, basta concederes **uma vez** — fica para sempre.
   (Sem esta permissão, o item é à mesma copiado para o clipboard — basta colares com `⌘V`.)

## Atalhos no painel

| Tecla | Ação |
|-------|------|
| `⌥V` | Abrir / fechar o painel |
| escrever | Pesquisar |
| `↑` `↓` | Navegar |
| `↵` | Colar o selecionado |
| `⌘1`–`⌘9` | Colar o item N |
| `⌘P` | Fixar / desafixar |
| `⌘⌫` | Apagar o selecionado |
| `esc` | Fechar |

## Estrutura do projeto

```
Sources/Clippy/
  main.swift              — arranque (app de barra de menus)
  AppDelegate.swift       — menu, atalho global, ciclo de vida
  HistoryStore.swift      — modelo + persistência + imagens
  ClipboardManager.swift  — monitorização do clipboard
  HotKey.swift            — atalho global (Carbon)
  PanelController.swift   — painel flutuante + teclado + colar
  PasteHelper.swift       — simular ⌘V (Acessibilidade)
  ContentView.swift       — interface SwiftUI
```

## Notas

- O atalho `⌥V` deixa de escrever o caractere `√` enquanto o Clippy corre.
  Para outro atalho, muda a linha em `AppDelegate.applicationDidFinishLaunching`.
- Dados em `~/Library/Application Support/Clippy/`.
