# MonoHub Rules

Regras obrigatórias para desenvolvimento, manutenção, privacidade e versionamento do **MonoHub**.

## Identidade & Propósito do Projeto

O **MonoHub** é a central unificada de utilitários nativos para **macOS 27 (Apple Silicon ARM64)**, combinando em um único aplicativo modular:
1. **Monitoramento de Sistema & Barra de Menus (MonoStats)**: widgets nativos em tempo real na barra de menus com painéis em Liquid Glass (`NSGlassEffectView`), monitorando CPU (núcleos P/E), RAM, GPU, Armazenamento I/O, Rede, Bateria/Energia (Watts) e Sensores Térmicos HID.
2. **Notch Dinâmico & Dynamic Island (MonoNotch)**: experiência de Dynamic Island nativa no entalhe do MacBook e em monitores externos (notch virtual), com atividades em tempo real (mídia, agenda com links de reuniões em um clique, checklist de lembretes, timer/cronômetro, espelho de câmera com Studio Light/Center Stage/Retrato, teleprompter e bloco de notas rápidas com auto-scroll no olhar da câmera, telemetria de bateria BLE/Bluetooth, gaveta de arquivos com AirDrop instantâneo e substituição compacta de HUDs de volume/brilho).
3. **Alternador de Janelas & Alt+Tab Avançado (MonoTab)**: alternador nativo ultrarrápido acionado via `⌥ Tab` / `⌘ Tab` com miniaturas em tempo real aceleradas por hardware via `ScreenCaptureKit`, navegação por teclado (incluindo Vim `hjkl` e dígitos 1-9), busca fuzzy instantânea e Quick Look.
4. **Organização & Encaixe Magnético de Janelas (MonoTile)**: gerenciamento de janelas com encaixe magnético nas bordas da tela, atalhos globais de alto desempenho e suporte multimonitor.
5. **Desinstalação Profunda, Limpeza e Manutenção (MonoClean)**: desinstalador transparente de aplicativos, caçador de resíduos órfãos, limpeza profunda de caches/logs, purga de artefatos de projetos (`node_modules`, `.build`, `target`, `.venv`), análise de grandes arquivos e otimização do sistema.
6. **Cotas de IA (MonoAiBar)**: ícone na barra de menus (anel de progresso + valor, ordem configurável) e painel em Liquid Glass com o uso e os limites de Claude, Codex, Antigravity e demais provedores de IA, sem consumir tokens. Cada provedor liga e desliga individualmente.
7. **Capturas de Tela (MonoShot)**: captura de área, janela e tela inteira via `ScreenCaptureKit`, lupa de pixel, editor de anotações (seta, retângulo, numeração, texto, desfoque/pixelização), OCR local (Vision) e imagens fixadas na tela. Atalhos globais Carbon (assinatura própria, sem exigir Acessibilidade) e permissão de Gravação de Tela compartilhada com o Alternador de Janelas.
8. **Conversão e Redução de Mídia (MonoConvert)**: conversão e compressão aceleradas por hardware para vídeos e imagens utilizando o Media Engine do Apple Silicon ARM64 (`AVFoundation`) e `ImageIO`. Inclui perfis dedicados para vídeos (Tablet 720p Fullscreen L3.1, Tablet 480p SD, Universal MP4 1080p, Web Compacto, HEVC Alta Eficiência e Extração de Áudio M4A) e imagens (HEIC, AVIF, WebP, JPEG, PNG, TIFF) com remoção opcional de metadados EXIF para máxima privacidade e redução de tamanho, processamento em lote via Drag & Drop e cálculo dinâmico de economia de espaço.
9. **Ciclo de Vida Híbrido Inteligente (Dock + Barra de Menus)**: exibe o aplicativo normalmente no Dock enquanto a janela principal está aberta; ao fechar a janela principal, oculta o ícone do Dock (`.accessory`) e permanece rodando de forma ultraleve apenas na Barra de Menus e no Notch.

---

## Invariantes Críticas de Privacidade, Segurança e Desempenho

1. **Zero Telemetria / Rede Restrita ao Módulo Cotas de IA**:
   - O MonoHub é estritamente privado. Todos os módulos operam 100% offline, exceto Cotas de IA (`AIQuota/`).
   - Somente o módulo Cotas de IA abre conexões de saída, exclusivamente para os endpoints de uso dos provedores que o usuário ativou. Com o módulo desativado, nenhuma conexão é feita. Conexões de entrada nunca são permitidas (`Entitlements.plist` declara `com.apple.security.network.client` e omite `com.apple.security.network.server`).
   - Chaves e tokens de provedores vivem apenas no Keychain do macOS; nunca em `UserDefaults` nem em arquivos. Nunca enviar prompts nem consumir tokens, nunca renovar sessões OAuth de outras ferramentas.
   - Subprocessos permitidos no módulo Cotas de IA: apenas via `CommandRunner` (`agy -p /usage`) e a sincronização do Keychain do Claude Code.
   - Nenhuma biblioteca de analytics, crash report remoto ou rastreamento pode ser incluída.
   - Todo o histórico de operações de limpeza é estritamente local em `~/Library/Logs/MonoHub/operations.log`.

2. **Segurança e Transparência Absoluta na Remoção de Arquivos**:
   - Nenhuma remoção ocorre de forma silenciosa ou opaca.
   - Todo arquivo ou diretório a ser removido é explicitamente listado com caminho completo, tamanho calculado e checkbox individual.
   - Ações destrutivas exigem confirmação explícita via modal.
   - Suporte prioritário para mover para a Lixeira do macOS (`trashItem`).
   - Lista de exclusão segura (Whitelist) em `~/.config/monohub/whitelist`.

3. **Ultra-baixo Consumo de CPU & Bateria (Monitoramento Kernel Mach/Darwin)**:
   - Zero subprocessos para telemetria: todas as métricas vêm diretamente do kernel Mach/Darwin e IOKit (`host_statistics64`, `host_processor_info`, `vm_statistics64`, `statvfs`, `getifaddrs`, `IOKit`, `libproc`).
   - Coleta em fila `.utility` nos núcleos de eficiência (E-Cores) com pausa automática quando a tela dorme ou a sessão é bloqueada.
   - Varredura de processos (`proc_listpids`) sob demanda apenas quando um painel detalhado ou a aba Monitor do Sistema está visível.

---

## Versionamento Semântico (SemVer) e Procedimento de Release

O projeto segue rigorosamente o Versionamento Semântico (`MAJOR.MINOR.PATCH`):
- **Versão Inicial Base**: `0.1.0` (Tag: `v0.1.0`).
- **PATCH (`0.1.x`)**: Correções de bugs, ajustes de interface e melhorias de performance.
- **MINOR (`0.x.0`)**: Novos módulos ou novas ferramentas adicionadas ao MonoHub.
- **MAJOR (`x.0.0`)**: Mudanças estruturais profundas ou reformulação de arquitetura.

### Procedimento Obrigatório de Incremento a Cada Nova Versão
Sempre que uma nova tarefa, correção ou funcionalidade for concluída:
1. Atualizar `AppInfo.version` e `AppInfo.build` em `Sources/MonoHub/App/AppInfo.swift`.
2. Atualizar `CFBundleShortVersionString` e incrementar `CFBundleVersion` em `Resources/Info.plist`.
3. Atualizar o badge de versão no topo do `README.md`.
4. Executar `make test` garantindo 0 falhas.
5. Executar `make build` e `make install` para validar o empacotamento e reiniciar a versão instalada em `/Applications/MonoHub.app`.
6. Criar commit com Conventional Commits (`feat:`, `fix:`, `chore:`) e tag semver anotada (`vX.Y.Z`).

---

## Regras de Instalação e Higiene de Cache

- **Local Único de Instalação**: Instalar sempre exclusivamente em `/Applications/MonoHub.app`. Nunca duplicar em `~/Applications/` ou deixar o bundle `.app` na raiz do repositório.
- **Procedimento Obrigatório de Instalação Limpa (`make install`)**:
  1. Encerrar instâncias anteriores em execução (`killall MonoHub MonoClean MonoStats`).
  2. Remover versões antigas e duplicatas tanto em `/Applications/` quanto em `~/Applications/` (incluindo os antigos `MonoClean.app` e `MonoStats.app`).
  3. Limpar caches da aplicação (`~/Library/Caches/com.antigravity.monohub`).
  4. Desregistrar caminhos obsoletos no LaunchServices (`lsregister -u`).
  5. Remover o bundle `.app` da pasta do repositório após a cópia para `/Applications/`.
  6. Recadastrar `/Applications/MonoHub.app` no LaunchServices (`lsregister -f`) e atualizar caches do sistema (`qlmanage -r`, `killall Finder`).

---

## Proibição de Assets de Release (CRÍTICA)

- **NUNCA** fazer upload de arquivos binários compilados, pacotes `.app`, arquivos `.zip` ou qualquer artefato de build como assets de release no GitHub.
- Releases devem consistir estritamente apenas de tags Git, commits e notas de lançamento em Markdown.

---

## Regras do Módulo Capturas de Tela (`Screenshot/`)

- **ESC instantâneo**: ESC fecha overlay, editor e imagens fixadas no primeiro toque (exceto durante a digitação de texto inline, onde cancela o campo).
- **Inicialização silenciosa**: o módulo nunca abre janelas ao iniciar; só atalhos globais e ícone na barra de menus.
- **Sem rede**: o módulo não faz nenhuma chamada de rede, não grava captura em disco sem ação explícita e não escreve metadados nas exportações.
- **Hotkeys Carbon**: todo handler `kEventHotKeyPressed` deve checar a assinatura do `EventHotKeyID` e devolver `eventNotHandledErr` para eventos de outros módulos (Organização de Janelas usa o mesmo alvo de eventos).
- **Janelas de edição**: enquanto houver um editor aberto o app permanece `.regular`; `MainWindowController.updateActivationPolicy()` considera `ScreenshotController.hasOpenEditors`.
- **Preferências**: chaves `MonoHub_Screenshot_*`; os valores do MonoShot standalone (`com.antigravity.monoshot`) são importados uma única vez.
