# Política de Privacidade — MonoHub

O **MonoHub** foi projetado desde o primeiro commit sob o princípio de **Privacidade Absoluta & Zero Telemetria**.

## 1. Rede Restrita ao Módulo Cotas de IA
- Todos os módulos do MonoHub operam 100% offline, **exceto Cotas de IA**.
- O `Entitlements.plist` declara apenas `com.apple.security.network.client` (para o módulo Cotas de IA) e **não** possui `com.apple.security.network.server`.
- O módulo Cotas de IA consulta somente os endpoints de uso/saldo dos provedores que você ativou (por exemplo Anthropic, OpenAI/ChatGPT, DeepSeek, Kimi, Z.ai). Nunca envia prompts, não consome tokens e não envia dados a terceiros além do próprio provedor consultado.
- Desativando o módulo em **Módulos**, nenhuma conexão de rede é feita.
- Chaves de API e tokens ficam exclusivamente no Keychain do macOS. E-mails de conta são removidos da interface e dos caches em disco.
- Nenhuma métrica de hardware, lista de aplicativos, caminho de arquivo ou preferência deixa o seu Mac.

## 2. Zero Coleta de Dados ou Analytics
- Não utilizamos SDKs de terceiros, rastreadores de uso, telemetria ou serviços de relatórios de falha remotos.
- Todas as leituras de hardware (CPU, RAM, GPU, Disco, Rede, Bateria e Sensores Térmicos) são feitas localmente via chamadas diretas ao kernel Darwin/Mach e descartadas em memória.

## 3. Armazenamento Estritamente Local
- **Capturas de Tela**: as imagens ficam apenas na memória volátil e só são gravadas em disco quando você salva. Exportações não carregam EXIF, GPS nem dados do dispositivo; imagens abertas são recusadas acima de 256 MB ou 120 megapixels. O OCR roda localmente (Vision) e o texto só vai para a área de transferência quando você pede. Nenhum conteúdo de tela ou texto reconhecido é enviado ao log do sistema.
- **Cotas de IA**: o último estado dos provedores (sem credenciais nem dados pessoais) fica em `~/Library/Application Support/MonoAiBar` com permissão `0600`.
- **Preferências**: salvas localmente no `UserDefaults` do usuário (`com.antigravity.monohub`).
- **Whitelist**: armazenada em texto puro em `~/.config/monohub/whitelist`.
- **Histórico de Limpeza**: armazenado localmente em `~/Library/Logs/MonoHub/operations.log`, podendo ser limpo ou desativado a qualquer momento nas Configurações do aplicativo.

## 4. Pré-visualizações de Janelas em Tempo Real (ScreenCaptureKit)
- As miniaturas de janelas utilizadas no Alternador de Janelas (MonoTab) são processadas estritamente na memória RAM efêmera via APIs nativas do `ScreenCaptureKit`.
- Nenhuma imagem, texto ou captura de tela é gravada em disco ou transmitida por qualquer meio.
- Ao fechar o alternador ou encerrar janelas, as imagens em cache são imediatamente purgadas da memória.

## 5. Câmera, Calendário e Lembretes (Notch Dinâmico)
- A câmera é utilizada exclusivamente em tempo real para o espelho rápido no notch via `AVCaptureSession`, sendo imediatamente desligada ao fechar o entalhe (apagando o indicador de LED verde instantaneamente).
- O acesso ao Calendário e Lembretes ocorre de forma 100% local via `EventKit` exclusivamente para visualização de compromissos e tarefas no notch. Nenhum dado de calendário, tarefa ou foto deixa a memória do dispositivo.
