# MonoHub

<p align="center">
  <img src="https://img.shields.io/badge/version-v0.17.7-brightgreen.svg" alt="Versão v0.17.7" />
  <img src="https://img.shields.io/badge/macOS-27.0%2B-blue.svg" alt="macOS 27.0+" />
  <img src="https://img.shields.io/badge/architecture-arm64%20Apple%20Silicon-orange.svg" alt="ARM64" />
  <img src="https://img.shields.io/badge/Swift-6.4-red.svg" alt="Swift 6.4" />
  <img src="https://img.shields.io/badge/privacy-Zero%20Telemetria-success.svg" alt="Zero Telemetria" />
  <img src="https://img.shields.io/badge/license-MIT-lightgrey.svg" alt="Licença MIT" />
</p>

**MonoHub** é a central unificada de utilitários nativos para **macOS 27+ (Apple Silicon ARM64)**, desenvolvida em **Swift 6.4 puro**, que combina o **MonoNotch**, o **MonoTab**, o **MonoStats**, o **MonoClean**, o **MonoTile**, o **MonoAiBar**, o **MonoShot**, o **MonoConvert** e a suíte **Produtividade & Clipboard** em um único aplicativo modular, organizado e com **Zero Telemetria** (rede apenas no módulo Cotas de IA).

---

## ✨ Arquitetura Híbrida (Janela Principal + Barra de Menus + Notch)

- **Central Organizada (Estilo Dashboard)**: Ao abrir o **MonoHub**, você tem acesso a uma janela principal organizada em seções claras na barra lateral para gerenciar o notch dinâmico, alternador de janelas, monitoramento, barra de menus, organização de janelas, desinstalação, limpeza profunda, purga de projetos e manutenção.
- **Modo Híbrido Inteligente (Dock, Menu Bar & Notch)**:
  - Com a janela principal aberta, o **MonoHub** aparece normalmente no Dock.
  - Ao fechar a janela principal (`⌘W`), o ícone do Dock é recolhido automaticamente e o **MonoHub** permanece rodando de forma silenciosa e ultraleve na **Barra de Menus** e no **Notch**.
  - Clique em **Abrir MonoHub** ou **Configurações…** em qualquer painel da barra de menus ou no notch para reabrir a janela principal instantaneamente.

## 🎛️ Módulos Sob Demanda (Zero Custo Quando Desligados)

Na página **Módulos** (barra lateral ou menu **MonoHub › Módulos…**) cada módulo pode ser ligado ou desligado em tempo real:

| Módulo | O que deixa de rodar quando desligado |
|---|---|
| Monitor do Sistema | Amostragem do kernel, widgets e painéis da barra de menus |
| Notch Dinâmico | Janelas do notch, observadores de mídia/áudio/brilho, interceptação de HUD, câmera, timers |
| Alternador de Janelas | Event tap do teclado, cache de miniaturas, ícone da barra de menus |
| Cotas de IA | Consultas de rede aos provedores, atualização periódica, ícone da barra de menus |
| Organização de Janelas | Atalhos globais, monitor de arrasto, ícone da barra de menus |
| Capturas de Tela | Atalhos globais de captura e ícone da barra de menus (overlay, editor e OCR só existem durante uma captura) |
| Conversor de Mídia | Somente oculta a ferramenta (processamento sob demanda, zero custo em segundo plano) |
| Produtividade & Clipboard | Event tap de snippets, interceptador AppleEvent de URLs e atalho global de Bluetooth |
| Limpeza e Desinstalação | Somente oculta as ferramentas (não têm custo em segundo plano) |

Dentro do Notch Dinâmico, cada recurso (Música, Agenda, Lembretes, Bluetooth, Bateria, Espelho, Gaveta, Área de Transferência, Teleprompter, Timer e HUD) também liga e desliga o respectivo motor, não apenas a interface.

---

## 🚀 Módulos Integrados

### 📊 Cotas de IA (MonoAiBar)
- Uso e limites de Claude, Codex, Antigravity, Copilot, Cursor, DeepSeek, Kimi, GLM e mais provedores, sem consumir tokens.
- Ícone na barra de menus com anel de progresso, valor, sigla ou ícone empilhado; **a ordem dos provedores é configurável arrastando a lista** (ou pelo menu de contexto) em **Cotas de IA**.
- Painel em Liquid Glass com cartões por provedor, ritmo de consumo (pacing), saldo, créditos e contexto do Claude Code.
- Avisos de uso e de renovação de limites; chaves apenas no Keychain.
- Único módulo que usa a rede, e só para os provedores ativados.

### 🏝️ 1. Notch Dinâmico & Dynamic Island (Notch)
- **⚡ Dynamic Island Nativa**:
  - Pílulas dinâmicas e fluidas com física de mola elástica hover (120Hz ProMotion).
  - Suporte a entalhes físicos (MacBook Pro / Air) e **Notch Virtual flutuante** em monitores externos e ultrawide.
  - Modos simultâneos para múltiplos monitores.
- **🎧 Live Activities de Mídia & Equalizador**:
  - Mini capa de álbum e equalizador animado no notch fechado.
  - Player expandido com título, artista, álbum, scrubber interativo, controles de reprodução e volume.
- **🧠 Live Activities de Cotas de IA & Processos Pesados (Integração MonoAiBar + MonoStats)**:
  - **Asas do Notch Fechado**: Exibição em tempo real nas asas do entalhe do consumo dos provedores principais (**Claude**, **Codex**, **Antigravity**) e telemetria de processos com pico de CPU ou alerta térmico elevado.
  - **Alertas Peek**: Notificação elegante sob o notch quando uma janela de rate-limit resetar (100% disponível), quando houver pico súbito de CPU em um processo ou aquecimento térmico do SoC.
  - **Cards na Tela de Início**: Cards dedicados para visualização compacta com barras de progresso de Cotas de IA e monitoramento de processos pesados e temperatura, com acesso em 1 clique aos respectivos módulos completos.
- **📆 Agenda, Reuniões & Lembretes**:
  - Sincronização em tempo real via EventKit de compromissos do dia.
  - Botão de acesso em 1 clique para videochamadas Zoom, Google Meet, Teams, Webex e FaceTime.
  - Checklist interativo de tarefas do Apple Reminders e criação rápida inline.
- **📷 Espelho de Câmera & Controles de Estúdio**:
  - Pré-visualização ao vivo de baixa latência da webcam (`AVCaptureSession`) no dropdown do notch.
  - Controles integrados de **Seguir / Center Stage**, **Luz de Estúdio**, **Modo Retrato**, **Luz de Borda (Ring Light)**, **Exposição EV**, **Grade 3x3** e **Zoom**.
  - **Higiene de Privacidade**: Desativação imediata da captura ao fechar o notch, apagando o LED verde da câmera instantaneamente.
- **🔋 Bateria, Energia & Acessórios Bluetooth**:
  - Telemetria de bateria, fonte de alimentação, indicador de carga e tempo restante.
  - Monitoramento ao vivo de AirPods (E/D/Case), mouses BLE, teclados e fones via `IOBluetooth` e `IOKit.ps`.
- **📚 Estante de Arquivos & AirDrop**:
  - Arraste arquivos sobre o notch para guardá-los temporariamente e compartilhar via AirDrop instantâneo.
- **📋 Histórico da Área de Transferência (Clipboard Manager)**:
  - Acesso rápido aos últimos textos, links, cores (HEX/RGB) e imagens copiados (`⌘C`).
  - Busca instantânea e filtros por tipo (`Todos`, `Textos`, `Links`, `Cores`, `Imagens`, `Fixados`).
  - Fixação de itens frequentes no topo com persistência local em disco.
  - **Abertura Inteligente & Contextual**:
    - Botão dedicado de **Abrir** (`arrow.up.right.square`) e menu de contexto (clique direito) em cada item:
      - **Imagens**: Abertura nativa no Pré-Visualização (`Preview.app`).
      - **Links / URLs**: Abertura direta no navegador padrão.
      - **Cores (HEX/RGB)**: Visualização e ajuste no Color Picker nativo do macOS (`NSColorPanel`).
      - **Caminhos de Arquivos**: Revelação direta e seleção no Finder.
      - **Textos / Snippets**: Abertura instantânea no TextEdit / editor de texto padrão.
    - **Ação de Clique Configurável**: ajuste nas preferências do módulo se o toque no item deve **Colar no app ativo**, **Abrir diretamente** ou **Apenas copiar**.
  - Colagem em 1 clique (com simulação opcional de `⌘V` via Acessibilidade) e suporte nativo a Drag-and-Drop para qualquer aplicativo.
  - Higiene de privacidade: ignora senhas, credenciais e itens confidenciais (`org.nspasteboard.ConcealedType`).
- **🎙️ Teleprompter & Bloco de Notas Rápidas (Scratchpad no Olhar da Câmera)**:
  - Posicionado exatamente abaixo da câmera FaceTime (no entalhe do MacBook ou notch virtual), permitindo ler roteiros, tópicos e pautas mantendo **contato visual direto e contínuo com a lente** durante chamadas no Google Meet, Zoom, Microsoft Teams, FaceTime e gravações.
  - **Rolagem Automática Fluida (Auto-Scroll)** com controle de velocidade regulável em tempo real (`pt/s`), pausa e retomada por clique ou tecla `Espaço`, e retorno ao início (`Rewind`).
  - **Linha de Foco no Olhar (Eye Contact Sightline Guide)**: guia visual focal posicionado na altura exata da câmera com gradiente dinâmico de leitura e indicador de alinhamento.
  - **Modo Scratchpad / Anotações**: bloco de notas rápido com contagem de palavras, caracteres e estimativa em tempo real da duração de fala (~130 palavras/min).
  - **Modelos Prontos em 1 Clique**: templates para reuniões 1:1, pitches de apresentação de 2 minutos, alinhamento com clientes e pautas gerais.
  - **Fixar Notch Aberto (Pin)**: mantém o entalhe visível durante a reunião sem fechar ao movimentar o cursor para outras janelas.
  - **Espelhamento Óptico (Inverter Texto)**: inversão horizontal para compatibilidade com teleprompters físicos com espelho divisor de feixe (*beam splitter glass*).
  - **Card na Tela de Início do Notch**: visualize seu roteiro ativo, tempo estimado de fala e acione o teleprompter com 1 toque direto do painel principal.
- **🎚️ Substituição Compacta de HUDs**:
  - Substitui os overlays quadrados do macOS por elegantes pílulas no notch para Volume, Brilho da Tela e Iluminação do Teclado.
- **🖥️ Controle Completo de Monitores & BetterDisplay Pro Suite (`DisplayControl/`)**:
  - **Módulo opt-in e totalmente inerte quando desligado**: vem desativado por padrão em *Módulos*. Desligado, nenhuma engine roda (sem DDC/CI via I2C, sem tabelas gamma, sem overlays, sem telas virtuais, sem reconfiguração de layout) e as teclas de brilho/volume voltam ao comportamento nativo. Ligado, trocas de Space (ex.: VMware em tela cheia) não disparam nenhuma ação: só mudanças reais de topologia de monitores (com debounce) reprocessam as telas.
  - **Controle de Hardware Real DDC/CI (MCCS v2.2A)**: Ajuste o brilho físico da luz de fundo (backlight), volume de alto-falantes, mudo, contraste, nitidez (`0x87`), ganho RGB de hardware (`0x16`/`0x18`/`0x1A`), predefinições de cor (`0x14`), troca de entrada (`0x60`), energia DPMS (`0xD6`) e reset de fábrica (`0x04`) em telas conectadas via **HDMI, DisplayPort, Thunderbolt ou USB-C** usando as teclas nativas (`F1`/`F2` e `F10`/`F11`/`F12`).
  - **Dimming Combinado + Sub-Zero até 0% Preto Absoluto**: Transição contínua que controla o hardware via DDC até o limite mínimo físico do monitor e, abaixo dele, engaja modulação de tabelas ColorSync/Gamma (`CGSetDisplayTransferByTable`) somada a overlay escuro click-through até **0% preto absoluto** (ou modo *Blackout / Soft Disconnect*).
  - **XDR / HDR Extra Brightness Upscaling (100% – 200% / até 1600 nits)**: Desbloqueia a margem Extended Dynamic Range (EDR) em telas Apple XDR e HDR compatíveis para que aplicativos desktop SDR atinjam até 1600 nits de luminância máxima.
  - **Escalonamento HiDPI Flexível, Taxa de Atualização & Rotação**: Alterne entre resoluções Retina HiDPI e LoDPI nativas, taxas de atualização (`Hz`), rotação de tela (`0°`, `90°`, `180°`, `270°`), lista de resoluções favoritas e gerador de resoluções HiDPI personalizadas.
  - **Calibração de Cor por Software & Temperatura Kelvin**: Ajuste contínuo da temperatura de cor correlacionada (`2700K` Noturno Quente → `6500K` Referência D65 → `9300K` Frio) pela curva Planckiana, ganho por canal RGB, contraste por software, deslocamento de gamma, filtro monocromático (tons de cinza) e inversão de cores.
  - **Telas Virtuais (Virtual Screens / Dummy Displays)**: Criação nativa de monitores virtuais via `CGVirtualDisplay` com proporções `16:9`, `16:10`, `21:9 Ultrawide`, `32:9 Super Ultrawide`, `4:3 Sidecar iPad`, `3:2` e `9:16 Vertical` em até 4K/5K HiDPI.
  - **Picture-in-Picture (PiP) & Stream de Teleprompter**: Janelas flutuantes aceleradas por hardware (`ScreenCaptureKit` / `IOSurface`) para qualquer monitor físico ou virtual, com espelhamento horizontal/vertical para teleprompter, corte de região (Zoom 50%, metades), opacidade e modo Click-Through.
  - **Proteção de Layout Multimonitor & Inspetor/Override EDID**: Salve e restaure âncoras da posição exata dos monitores para evitar reorganização acidental ao despertar, inspecione o dump hexadecimal VESA EDID 1.4 de 128 bytes e exporte arquivos `.plist` de Override do macOS (forçar Full RGB em TVs, desbloquear Night Shift e injetar modos HiDPI).

### 🔁 2. Alternador de Janelas & Alt+Tab (Tab)
- **⚡ Alternador Ultrarrápido (`⌥ Tab` & `⌘ Tab`)**:
  - Ciclo instantâneo de janelas com suporte a `⌥ Option + Tab`, `⌘ Command + Tab` (substituindo o alternador padrão do macOS) ou ambos.
  - Navegação fluida por teclado: setas direcionais, Vim (`h`, `j`, `k`, `l`), dígitos `1` a `9` para salto numérico direto ou `Shift + Tab` para ciclar para trás.
- **📸 Miniaturas em Tempo Real via ScreenCaptureKit**:
  - Captura acelerada por GPU/CPU via `ScreenCaptureKit` em dobro da resolução Retina com downscaling de alta fidelidade.
  - Cache efêmero em memória RAM (`ThumbnailStore`) com 0ms de latência perceptível e purga automática de janelas fechadas.
- **🔍 Busca Fuzzy Instantânea (`f` ou `/`)**:
  - Pressione `f` ou `/` durante a navegação para pesquisar instantaneamente por título da janela ou nome do app sem fechar o HUD.
- **👁️ Quick Look & Ações de Janela**:
  - Pressione `Espaço` em qualquer cartão para abrir pré-visualização ampliada em alta resolução.
  - Ações diretas por teclado: `W` (fechar janela com confirmação), `⇧W` (ocultar app), `M` (minimizar/restaurar), `Z` (zoom/maximizar), `[` e `]` (encaixar à esquerda/direita) e `N` (mover para o próximo monitor).
- **🎨 Design Liquid Glass**:
  - Painel flutuante centralizado ou modo tela cheia, 7 cores de destaque e redimensionamento automático de miniaturas.

### 📊 3. Monitoramento & Barra de Menus (Stats)
- **Monitor do Sistema Completo**: Painel ao vivo dentro do app e widgets modulares na barra de menus com painéis em Liquid Glass (`NSGlassEffectView`):
  - **Processador (CPU)**: Uso geral, usuário/sistema, Load Average, topologia Apple Silicon (Performance Cores e Efficiency Cores) e Top Processos.
  - **Memória RAM**: Composição idêntica ao Monitor de Atividade (Apps, Reservada, Comprimida, Cache), pressão de memória, Swap e Top Processos.
  - **Processador Gráfico (GPU)**: Utilização via `IOAccelerator`, Renderização, Tiler, Unified Memory e processos.
  - **Armazenamento (Disco)**: Capacidade e velocidades de Leitura/Escrita em tempo real via `IOBlockStorageDriver`.
  - **Rede (Network)**: Velocidades de download/upload, picos da sessão e IPs locais (IPv4/IPv6) via `getifaddrs` sem conexões externas.
  - **Bateria & Energia**: Carga, estado, Modo de Energia, Limite de Carga (`powerd`), consumo em Watts (`PowerTelemetryData`), saúde, ciclos e bateria de acessórios Bluetooth.
  - **Temperatura & Sensores**: Sensores térmicos HID reais do SoC (média/máx), SSD e bateria.
- **⚡ Portas de Rede, Processos & Consumo de Banda (MonoPorts)**:
  - Monitor de consumo de banda em tempo real por processo (inspirado em Little Snitch Network Monitor e TripMode) via APIs Darwin de sockets (`NetworkStatistics` / kernel control sockets).
  - Exibição instantânea de taxas de download/upload (`KB/s` / `MB/s`) e consumo acumulado por processo e soquete em segundo plano com zero subprocessos na amostragem.
  - Destaque imediato do processo consumidor líder de tráfego (`Top Consumer`) no cabeçalho e na listagem com ordenação por maior consumo (`Bandwidth`).
  - Filtro dedicado para conexões com tráfego ativo (`Com Tráfego`), escuta (`LISTEN`) e ativas (`ESTABLISHED`).
  - Mapeamento automático de portas e processos (PID, nome amigável, ícone nativo e caminho do executável).
  - Reconhecimento automático de portas web de desenvolvimento (`:3000`, `:5173`, `:8080`, etc.) com botão para abrir direto no navegador.
  - Encerramento seguro de processos (`SIGTERM` / `SIGKILL`) sob confirmação modal com aviso de impacto.
- **🔋 Saúde Avançada da Bateria (MonoBattery)**:
  - Diagnóstico comparativo de capacidade: Capacidade de Fábrica (*Design*) vs. Capacidade Máxima Atual (*Nominal*) para cálculo da integridade real da bateria.
  - Monitoramento de ciclos de recarga contra o limite recomendado da Apple (1.000 ciclos).
  - Histórico visual em gráficos com curvas de carga, temperatura térmica e fluxo de potência (Watts).
  - Alertas configuráveis de preservação: aviso ao atingir 80% na tomada, alerta de recarga completa (100%) e proteção contra alta temperatura (>42°C).
  - Nível de carga e componentes de periféricos Bluetooth conectados (Magic Keyboard, Trackpad, AirPods).
- **Configuração Integrada da Barra de Menus**:
  - Ative/desative a barra de menus, reordene módulos, veja **prévia ao vivo** de cada estilo (`Medidor`, `Duas Linhas`, `Símbolo sobre Valor`, `Somente Ícone`, `Barra`, `Porcentagem na Bateria`), configure cores de alerta, intervalo de amostragem e idioma.

### 🧹 4. Limpeza, Desinstalação & Manutenção (Clean)
- **🗑️ Desinstalador Completo de Aplicativos**: Localiza o `.app` e todos os resíduos espalhados (`Application Support`, `Caches`, `Preferences`, `Saved Application State`, `Containers`, `Group Containers`, `WebKit`, `HTTPStorages`, `Logs`, `LaunchAgents`), com transparência total e checkboxes individuais.
- **👻 Resíduos Órfãos**: Encontra e limpa sobras de aplicativos já removidos no passado.
- **✨ Limpeza Profunda do Sistema**: Varre caches de usuário, logs, Crash Reports, caches de navegadores, caches de ferramentas de desenvolvimento (Xcode DerivedData, Homebrew, npm, pnpm, yarn, cargo, go-build, pip, CocoaPods), instaladores antigos e Lixeira.
- **⏱️ Purgador de Snapshots Locais do Time Machine (APFS)**: Detecção e remoção segura de snapshots locais do Time Machine (`tmutil listlocalsnapshots /`), liberando de 50 GB a 150 GB frequentemente retidos em "Dados do Sistema".
- **📦 Purga de Projetos (Dev)**: Identifica pastas pesadas de build (`node_modules`, `.build`, `target`, `dist`, `.venv`, `Pods`, `.gradle`) em `~/dev` e diretórios personalizados.
- **🛠️ Ambientes de Desenvolvimento (MonoEnv)**:
  - Mapeia o consumo de disco do ecossistema de desenvolvimento global:
    - **Xcode**: Caches de `DerivedData` organizados por projeto, `iOS DeviceSupport`, arquivos compilados e simuladores.
    - **Node.js**: Versões instaladas via `nvm`, store global do `pnpm`, caches do `npm`, `yarn` e `bun`.
    - **Python & ML**: Versões do `pyenv`, caches do `pip`, `uv`, `poetry` e pesos de modelos do `Hugging Face`.
    - **Homebrew, Rust & Go**: Caches de downloads de fórmulas, crates do Cargo e builds do Go.
    - **Docker**: Imagens de disco das máquinas virtuais do Docker Desktop.
  - Limpeza seletiva com distinção clara entre *Caches Seguros* (recompiláveis) e *Runtimes*.
- **👥 Arquivos Duplicados & Fotos Similares (MonoDupes)**:
  - Detecção de alta performance em 3 fases: agrupamento por tamanho de byte -> hash de cabeçalho de 64 KB -> SHA-256 completo via `CryptoKit` em streaming.
  - Modo visual de **Fotos Similares** acelerado pelo Neural Engine (`Vision.framework` / `VNGenerateImageFeaturePrintRequest`) para fotos tiradas em sequência ou salvas em diferentes resoluções.
  - Seleção inteligente em 1 clique: manter mais antigas, mais recentes ou de menor caminho.
  - Remoção segura enviando as cópias duplicadas para a Lixeira do macOS com confirmação modal.
- **🚀 Itens de Inicialização & Serviços (MonoStartup)**:
  - Transparência total sobre serviços que iniciam com o macOS: LaunchAgents do usuário (`~/Library/LaunchAgents`), LaunchAgents globais (`/Library/LaunchAgents`), LaunchDaemons do sistema (`/Library/LaunchDaemons`) e itens de início de sessão.
  - Chave de ativação/desativação instantânea e segura para impedir inicialização em segundo plano sem apagar arquivos.
  - Remoção transparente movendo plists para a Lixeira, com proteção estrita para serviços nativos da Apple (`com.apple.*`).
- **💾 Análise de Disco**: Mapa de ocupação do volume principal e busca de grandes arquivos (>50 MB a >1 GB).
- **⚡ Otimização do Sistema**: Flush de DNS, reconstrução do LaunchServices, purga de RAM inativa, reset do QuickLook e reinício de Finder/Dock.
- **🛡️ Whitelist & Auditoria Local**: Proteção de pastas em `~/.config/monohub/whitelist` e log local auditável em `~/Library/Logs/MonoHub/operations.log`.

### 📸 Capturas de Tela (MonoShot)
- Captura de **área** (lupa de pixel e amostrador HEX com `C`), **janela** (com detecção por Z-order, `Espaço` alterna o modo), **tela inteira** do monitor sob o cursor e **OCR** direto para a área de transferência (Vision, no Neural Engine).
- **📜 Captura de Tela com Rolagem (Scrolling Capture)** (inspirado em CleanShot X e Shottr): costura contínua de quadros com aceleração por hardware via `Vision.framework` (`VNTranslationalImageRegistrationRequest`), com auto-scroll inteligente via `CGEvent`, pré-visualização ao vivo, suporte a documentos e páginas longas até 32.000 px, atalho global dedicado (`⇧⌘S`) e suporte CLI (`monoshot scrolling`).
- **🎥 Gravação Rápida de GIF / Micro-Vídeo de Tela** (inspirado em CleanShot X e Kap): gravação de área selecionada da tela diretamente para GIF animado otimizado (com paleta adaptativa de duas passagens), MP4 (H.264) ou WebM ultraleve (VP9), acelerado por hardware via Media Engine (`AVAssetWriter` / `ScreenCaptureKit`), atalho global dedicado (`⇧⌘5`) e suporte CLI (`monoshot record`).
- Editor com seta, seta curva, retângulo, numeração, texto, desfoque e pixelização reais (o detalhe original é destruído), desfazer/refazer, zoom e fixação da imagem flutuante na tela.
- Atalhos globais configuráveis (padrão `⇧⌘1` área, `⇧⌘2` tela, `⇧⌘3` janela, `⇧⌘O` OCR, `⇧⌘S` rolagem, `⇧⌘5` gravação GIF/vídeo), formato PNG/JPEG/HEIC/TIFF, qualidade, salvar em 1x e pasta de destino em **Capturas de Tela**.
- Totalmente offline: exportações sem EXIF/GPS, OCR marcado como sensível para gerenciadores de clipboard.
- Terminal e URLs: `monoshot area|fullscreen|window|ocr|scrolling|record`, `monoshot imagem.png`, `monoshot://area`, `monoshot://scrolling`, `monoshot://record`.
- As configurações do MonoShot standalone são importadas na primeira execução.

### 🔄 6. Conversão & Redução de Mídia (MonoConvert)
- **⚡ Aceleração por Hardware no Apple Silicon (ARM64)**:
  - Transcodificação nativa de vídeo via Media Engine (`AVFoundation` / VideoToolbox) e manipulação ultrarrápida de imagens via `ImageIO` e `CoreGraphics`.
  - Zero custo de CPU em segundo plano: atua estritamente sob demanda durante a conversão dos arquivos.
- **🎬 Perfis Dedicados para Vídeo (Inspirados no monoconvert)**:
  - **Tablet 720p Fullscreen**: Transcodificação H.264 Main L3.1 com áudio AAC e `+faststart` (átomo `moov` no início), reduzindo tamanhos em até ~85% com reprodução fluida em dispositivos legados e modernos.
  - **Tablet 480p SD**: H.264 Baseline L3.0 com alta taxa de compressão (~92% menor).
  - **Universal MP4 (1080p)**: Máxima compatibilidade com TVs, computadores e smartphones.
  - **Web / Tamanho Mínimo**: Compressão agressiva para compartilhamento imediato.
  - **HEVC / H.265**: Máxima fidelidade e eficiência utilizando os encoders de hardware do chip Apple Silicon.
  - **Apenas Áudio (M4A / AAC)**: Extração instantânea da trilha de áudio sem re-codificar o fluxo de vídeo.
- **🖼️ Otimização e Compressão de Imagens**:
  - Conversão entre **HEIC**, **AVIF**, **WebP**, **JPEG**, **PNG** e **TIFF**.
  - Controle contínuo de qualidade visual (slider de 10% a 100%).
  - Remoção opcional de metadados **EXIF** (dados de GPS, câmera e autor) para preservação de privacidade e redução adicional de tamanho.
- **📦 Fila de Processamento em Lote & Drag & Drop**:
  - Arraste múltiplos arquivos ou pastas inteiras diretamente para o painel em Liquid Glass.
  - Estimativa e cálculo em tempo real de bytes economizados e porcentagem de redução (ex: `-85.2% (120 MB → 17.8 MB)`).
  - Proteção contra sobrescrita acidental: sufixo inteligente configurável (`_converted`) e seletor de pasta de saída personalizada.
  - Acesso direto ao arquivo gerado com o botão **Revelar no Finder**.

### 🪟 5. Organização & Encaixe de Janelas (Tile)
- **🧲 Encaixe Magnético nas Bordas em Liquid Glass (Edge Drag Snapping)**:
  - Arraste janelas para as bordas e cantos da tela para organizá-las instantaneamente em metades, quadrantes ou maximizar.
  - Prévia translúcida nativa em **macOS 27 Liquid Glass** (`NSGlassEffectView`) com pílula indicadora da ação, animação fluida contínua e retorno tátil (haptic feedback no trackpad).
  - Restauração automática de tamanho ao mover uma janela previamente encaixada.
  - Zonas de terços na borda inferior e sensibilidade magnética ajustável.
- **🧠 Foco Inteligente & Fila MRU (Alternância Instantânea)**:
  - **Alternar Última Janela (`⌃⌥⌘⇥`)**: alternância imediata (*back-and-forth* estilo AeroSpace/i3) entre a janela atual e a anterior, com fallback automático para a próxima janela viva caso a anterior tenha sido fechada.
  - **Fila de Foco MRU (`⌃⌥⌘]` / `⌃⌥⌘[`)**: navegação orientada a sessão pela pilha de janelas recentes (`B → C → D → A`) sem oscilar, com HUD flutuante em **macOS 27 Liquid Glass** exibindo a ordem da fila e o item selecionado.
  - **Trocar Posição com Última Janela (`⌃⌥⌘↩`)**: troca instantaneamente o enquadramento entre a janela ativa e a janela anterior da fila.
  - **Foco Direcional com Desempate MRU (`⌃⌥⌘` + setas)**: prioriza vizinhos alinhados, desempata janelas empilhadas pela ordem MRU mais recente e oferece fallback configurável (ir para última janela, circular na borda oposta ou parar na borda), escopo por monitor e opção de cursor acompanhar o foco.
- **⌨️ 30 Atalhos Globais & Motor de Alta Performance**:
  - Organização em metades (`⌥⇧←`, `⌥⇧→`, `⌥⇧↑`, `⌥⇧↓`) com ciclo inteligente (`1/2` → `2/3` → `1/3`).
  - Quadrantes (`⌥⇧U`, `⌥⇧I`, `⌥⇧J`, `⌥⇧K`), terços (`⌥⇧D`, `⌥⇧F`, `⌥⇧G`) e dois terços (`⌥⇧E`, `⌥⇧T`).
  - Maximizar (`⌥⇧↩`), Quase Maximizar (`⌥⇧␣`), Centralizar (`⌥⇧C`) e Restaurar/Desfazer (`⌥⇧⌫`).
  - Movimentação entre múltiplos monitores (`⌥⇧⌘→`, `⌥⇧⌘←`), foco direcional e fila de foco (`⌃⌥⌘`).
  - Chamadas AX agrupadas em lote, cache de monitores e PIDs, lookup direto por `CGWindowID` e observação orientada a eventos (`AXObserver`) com zero polling em segundo plano.
  - Gravador de atalhos inline e busca em tempo real na interface.
- **🖱️ Arrasto por Modificadores (Modifier Drag)**:
  - Mova qualquer janela segurando `⌃⌥` (ou `⌃⌘`, `⌥⌘`) e clicando em qualquer ponto da janela, com suspensão única de `AXEnhancedUserInterface` durante a sessão para fluidez nativa a 120Hz ProMotion.
  - Redimensione pelo canto mais próximo com o botão direito do mouse.
- **🚫 Aplicativos Ignorados & Spacing**:
  - Defina apps que o MonoHub deve ignorar, margens externas (0–32 pt) e espaçamento entre janelas (0–32 pt).
- **💻 CLI & URL Schemes**:
  - Suporte completo via terminal: `monohub left-half` ou `monotile left-half`.
  - Integração com automações via URL: `monohub://tile/left-half` ou `monotile://left-half`.

### ⚡ 7. Produtividade & Clipboard

- **🌐 Roteador de URLs & UTM Stripper (Inspirado em Velja e Choosy)**:
  - **Limpador de Rastreadores**: Remove automaticamente parâmetros de rastreamento invasivos (`utm_source`, `utm_medium`, `utm_campaign`, `fbclid`, `gclid`, `si=...`, `twclid`, `igshid`, `mc_eid`) preservando a privacidade sem quebrar o link de destino.
  - **Roteamento Nativo de Reuniões**: Links do Zoom (`zoommtg://`), Teams (`msteams://`), Figma (`figma://`), Notion (`notion://`) e Telegram (`tg://`) são redirecionados automaticamente para abrir direto nos respectivos aplicativos desktop nativos quando instalados, eliminando abas intermediárias vazias no navegador.
  - **Roteamento por App de Origem e Domínio**: Regras inteligentes baseadas no aplicativo de onde o link foi clicado (`sourceAppBundleID`) ou no padrão de domínio com suporte a curingas (`*`).
    - *Exemplo*: Links clicados dentro do **Slack** abrem automaticamente no navegador minimalista **Helium**, enquanto links comuns ou de trabalho abrem no seu perfil corporativo do Chrome e links pessoais no Safari.
  - **Simulador Interativo**: Teste URLs em tempo real dentro do MonoHub para visualizar os parâmetros removidos e em qual navegador/app nativo o link abrirá.

- **💬 Expansão Rápida de Texto / Snippets (Inspirado em Raycast Snippets e TextExpander)**:
  - Digite abreviações e palavras-chave (ex: `!email`, `!pix`, `!cnpj`, `!shrug`, `!meeting`) em qualquer aplicativo do macOS e o MonoHub substitui inline pelo texto completo instantaneamente via API de Acessibilidade.
  - **Variáveis Dinâmicas**: Avaliação na hora de tags especiais como `{date}` (data atual), `{time}` (horário), `{clipboard}` (conteúdo atual da área de transferência) e `{uuid}` (UUID v4 único).
  - **Integração com o Dynamic Notch**: Snippets cadastrados aparecem diretamente no filtro `.snippets` da área de transferência do Notch, permitindo pré-visualização e cópia com 1 clique.

- **🎧 Conexão Rápida de Bluetooth com 1 Toque (Inspirado em ToothFairy e AirBuddy)**:
  - **Atalho Global Carbon (`⌥ B` / Option + B)**: Conecte ou desconecte seus AirPods, fone Sony, Beats ou teclado/mouse favorito de qualquer lugar do macOS sem abrir os Ajustes do Sistema.
  - **Roteamento Automático de Áudio**: Ao conectar fones de ouvido pelo atalho, o MonoHub sincroniza imediatamente a saída padrão de som via CoreAudio (`AudioDeviceManager`).
  - **Favorito Rápido**: Marque qualquer dispositivo pareado com uma estrela de favorito tanto na janela principal quanto no widget de Bluetooth do Dynamic Notch.

---

## 🛠️ Compilação e Instalação

```bash
git clone https://github.com/joaooliveiratech/MonoHub.git
cd MonoHub

# 1. Gerar o AppIcon oficial em alta resolução
make icon

# 2. Executar a suíte unificada de testes automatizados
make test

# 3. Compilar, empacotar, substituir MonoClean/MonoStats e instalar em /Applications/MonoHub.app
make install
```

---

## 📄 Licença e Privacidade

- [Política de Privacidade](PRIVACY.md): Arquitetura 100% offline e zero telemetria.
- Licença: [MIT](LICENSE).
