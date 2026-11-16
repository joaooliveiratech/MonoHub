import Foundation

nonisolated enum ShotText {
    static func pick(_ english: String, _ portuguese: String) -> String {
        Localization.language == .english ? english : portuguese
    }

    static var tabGeneral: String { pick("General", "Geral") }

    static var showMenuBarIconTitle: String { pick("Show menu bar icon", "Mostrar ícone na barra de menus") }
    static var showMenuBarIconSubtitleVisible: String {
        pick("Quick access to captures and settings.", "Acesso rápido às capturas e às configurações.")
    }
    static var showMenuBarIconSubtitleHidden: String {
        pick("Icon hidden: use global shortcuts or type 'monoshot' in terminal.",
             "Ícone oculto: use seus atalhos globais ou digite 'monoshot' no terminal.")
    }
    static var sectionCaptureActions: String { pick("Capture Actions", "Ações ao capturar") }
    static var copyToClipboardTitle: String {
        pick("Copy to clipboard automatically", "Copiar para a Área de Transferência automaticamente")
    }
    static var losslessFormatNote: String {
        pick("Lossless format: compression quality does not apply.", "Formato sem perdas: a qualidade de compressão não se aplica.")
    }
    static var privacySummary: String {
        pick("100% offline: no network, no telemetry, no metadata in exported images. Text recognition runs on this Mac.",
             "100% offline: sem rede, sem telemetria e sem metadados nas imagens exportadas. O reconhecimento de texto roda neste Mac.")
    }
    static var menuCaptureNow: String { pick("Capture Now", "Capturar Agora") }
    static var restoreDefaultButton: String { pick("Restore Default", "Restaurar Padrão") }
    static var openEditorTitle: String { pick("Open annotation editor", "Abrir o editor de anotações") }
    static var playShutterSoundTitle: String { pick("Play camera shutter sound", "Reproduzir som de obturador") }
    static var saveLocationModePicker: String { pick("When saving image", "Ao salvar imagem") }
    static var saveLocationLastUsed: String { pick("Remember last used folder", "Lembrar última pasta usada") }
    static var saveLocationCustom: String { pick("Fixed custom folder", "Pasta fixa definida") }
    static var customFolderLabel: String { pick("Fixed folder", "Pasta fixa") }
    static var lastUsedFolderLabel: String { pick("Last used folder", "Última pasta") }
    static var chooseButton: String { pick("Choose…", "Escolher…") }
    static var chooseFolderPrompt: String { pick("Use folder", "Usar pasta") }

    static var sectionGlobalShortcuts: String { pick("Global Shortcuts", "Atalhos Globais") }
    static var restoreDefaultsButton: String { pick("Restore Defaults", "Restaurar Padrões") }
    static var shortcutAreaTitle: String { pick("Capture interactive area", "Capturar área interativa") }
    static var shortcutAreaSubtitle: String {
        pick("Overlay with pixel loupe and HEX sampler", "Overlay com lupa de pixel e amostrador HEX")
    }
    static var shortcutFullscreenTitle: String { pick("Capture entire screen", "Capturar tela inteira") }
    static var shortcutFullscreenSubtitle: String { pick("Display under the pointer", "Monitor sob o cursor") }
    static var shortcutWindowTitle: String { pick("Capture single window", "Capturar janela individual") }
    static var shortcutWindowSubtitle: String { pick("Smart detection and Z-order", "Detecção inteligente e Z-order") }
    static var shortcutOCRTitle: String { pick("Recognize text (OCR)", "Reconhecer texto (OCR)") }
    static var shortcutOCRSubtitle: String {
        pick("Copies text directly to clipboard", "Copia o texto diretamente para a área de transferência")
    }
    static var shortcutScrollingTitle: String { pick("Capture scrolling area", "Capturar área com rolagem") }
    static var shortcutScrollingSubtitle: String {
        pick("Continuous vertical stitching via Vision", "Costura vertical contínua via Vision")
    }
    static var shortcutRecordTitle: String { pick("Record screen area", "Gravar área da tela") }
    static var shortcutRecordSubtitle: String {
        pick("Quick capture to optimized GIF or MP4/WebM", "Gravação rápida para GIF otimizado ou MP4/WebM")
    }
    static var pressKeysPrompt: String { pick("Press keys…", "Pressione as teclas…") }
    static var shortcutNeedsModifier: String {
        pick("Combine the key with ⌘, ⌥ or ⌃.", "Combine a tecla com ⌘, ⌥ ou ⌃.")
    }
    static var shortcutInUse: String {
        pick("Already assigned to another capture.", "Já atribuído a outra captura.")
    }
    static var shortcutUnavailable: String {
        pick("Taken by macOS or another app.", "Em uso pelo macOS ou por outro app.")
    }
    static var recordingHelp: String {
        pick("Press the new key combination. Esc cancels.", "Pressione a nova combinação de teclas. Esc cancela.")
    }
    static var recordHelp: String { pick("Click to record a new shortcut", "Clique para gravar um novo atalho") }
    static var keySpace: String { pick("Space", "Espaço") }
    static var duringSelectionLabel: String { pick("During selection", "Durante a seleção") }
    static var duringSelectionKeys: String {
        pick("Space (Mode) · C (HEX) · O (OCR) · ↩ · Esc", "Espaço (Modo) · C (HEX) · O (OCR) · ↩ · Esc")
    }
    static var inEditorLabel: String { pick("In editor", "No editor") }
    static var inEditorKeys: String {
        pick("1…8 (Tools) · ⌘Z / ⇧⌘Z · ⌘C · ⌘S · ⌘P · Pinch to zoom",
             "1…8 (Ferramentas) · ⌘Z / ⇧⌘Z · ⌘C · ⌘S · ⌘P · Pinça para zoom")
    }

    static var defaultExportFormatLabel: String { pick("Default save format", "Formato padrão ao salvar") }
    static var compressionQualityLabel: String {
        pick("JPEG / HEIC compression quality", "Qualidade de compressão JPEG / HEIC")
    }
    static func qualityDescription(percent: Int) -> String {
        switch percent {
        case ..<65:
            return pick("Compact: minimal file size, ideal for fast sharing.",
                        "Compacto: tamanho de arquivo mínimo, ideal para envio rápido.")
        case 65..<80:
            return pick("Medium: great balance between compression and sharpness.",
                        "Médio: ótimo equilíbrio entre compressão e nitidez.")
        case 80..<92:
            return pick("Balanced (Recommended): excellent visual fidelity with high space savings.",
                        "Equilibrado (Recomendado): excelente fidelidade visual com grande economia de espaço.")
        default:
            return pick("Maximum: full detail preservation, lower compression ratio.",
                        "Máxima: preservação total dos detalhes e menor taxa de compressão.")
        }
    }
    static var downscaleRetinaTitle: String {
        pick("Save at 1x scale (Optimize for Retina displays)", "Salvar em escala 1x (Otimizar para telas Retina)")
    }
    static var downscaleRetinaSubtitle: String {
        pick("Reduces file size by ~75% by converting physical pixels to logical points upon export, maintaining great clarity for web and chat.",
             "Reduz o tamanho em ~75% convertendo pixels físicos para pontos lógicos ao exportar, mantendo excelente fidelidade para a web e chat.")
    }

    static var permissionActiveDesc: String {
        pick("Permission active — capture and OCR running perfectly.",
             "Permissão ativa — captura e OCR operando perfeitamente.")
    }
    static var permissionMissingDesc: String {
        pick("Required to capture windows, areas, and recognize text.",
             "Necessária para capturar janelas, áreas e reconhecer texto.")
    }
    static var sectionTextRecognition: String { pick("Text Recognition", "Reconhecimento de Texto") }
    static var concealRecognizedTextTitle: String { pick("Mark OCR as sensitive text", "Marcar OCR como texto sensível") }
    static var concealRecognizedTextSubtitle: String {
        pick("Clipboard managers will not archive captured passwords or tokens.",
             "Gerenciadores de clipboard não arquivam senhas ou tokens lidos.")
    }

    static var menuCaptureArea: String { pick("Capture Area", "Capturar Área") }
    static var menuCaptureFullscreen: String { pick("Capture Entire Screen", "Capturar Tela Inteira") }
    static var menuCaptureWindow: String { pick("Capture Window", "Capturar Janela") }
    static var menuCaptureScrolling: String { pick("Capture Scrolling Area", "Capturar Área com Rolagem") }
    static var menuRecordScreen: String { pick("Record Screen (GIF / Micro-Video)", "Gravar Tela (GIF / Micro-Vídeo)") }
    static var menuOCR: String { pick("Recognize Text (OCR)", "Reconhecer Texto (OCR)") }
    static var menuScreenPermissions: String { pick("Grant Screen Recording…", "Permitir Gravação de Tela…") }
    static var menuCapture: String { pick("Capture", "Captura") }
    static var menuOpenImage: String { pick("Open Image…", "Abrir Imagem…") }
    static var menuOpenHub: String { pick("Open MonoHub", "Abrir MonoHub") }
    static var statusItemLabel: String { pick("Screenshots", "Capturas de Tela") }
    static var permissionRequired: String {
        pick("Screen Recording permission needed", "Permissão de Gravação de Tela necessária")
    }
    static var menuSettings: String { pick("Screenshot Settings…", "Configurações de Captura…") }

    static var menuSave: String { pick("Save…", "Salvar…") }
    static var menuPin: String { pick("Pin to Screen", "Fixar na Tela") }
    static var menuActualSize: String { pick("Actual Size", "Tamanho Real") }
    static var menuZoomToFit: String { pick("Zoom to Fit", "Ajustar à Janela") }
    static var menuZoomIn: String { pick("Zoom In", "Ampliar") }
    static var menuZoomOut: String { pick("Zoom Out", "Reduzir") }
    static var menuTools: String { pick("Tools", "Ferramentas") }

    static var toolbarTools: String { pick("Tools", "Ferramentas") }
    static var toolbarColor: String { pick("Color", "Cor") }
    static var toolbarIntensity: String { pick("Intensity", "Intensidade") }
    static var toolbarUndo: String { pick("Undo", "Desfazer") }
    static var toolbarRedo: String { pick("Redo", "Refazer") }
    static var toolbarDelete: String { pick("Delete", "Apagar") }
    static var toolbarText: String { pick("Text", "Texto") }
    static var toolbarPin: String { pick("Pin", "Fixar") }
    static var intensityTooltip: String {
        pick("Blur and pixelation intensity", "Intensidade do desfoque e da pixelização")
    }
    static var colorTooltip: String { pick("Annotation color", "Cor da anotação") }
    static var undoTooltip: String { pick("Undo (⌘Z)", "Desfazer (⌘Z)") }
    static var redoTooltip: String { pick("Redo (⇧⌘Z)", "Refazer (⇧⌘Z)") }
    static var deleteTooltip: String {
        pick("Delete Selected Element (⌫)", "Apagar Elemento Selecionado (⌫)")
    }
    static var ocrTooltip: String { pick("Recognize Text (⇧⌘R)", "Reconhecer Texto (⇧⌘R)") }
    static var pinTooltip: String { pick("Pin to Screen (⌘P)", "Fixar na Tela (⌘P)") }
    static var copyButtonTitle: String { pick("Copy", "Copiar") }
    static var copyTooltip: String { pick("Copy and close (⌘C)", "Copiar e fechar (⌘C)") }
    static var saveButtonTitle: String { pick("Save", "Salvar") }
    static var saveTooltip: String { pick("Save Image (⌘S)", "Salvar Imagem (⌘S)") }

    static var toolSelect: String { pick("Move / Select", "Mover / Selecionar") }
    static var toolArrow: String { pick("Arrow", "Seta") }
    static var toolCurvedArrow: String { pick("Curved Arrow", "Seta Curva") }
    static var toolRectangle: String { pick("Rectangle", "Retângulo") }
    static var toolCounter: String { pick("Numbering", "Numeração") }
    static var toolText: String { pick("Text", "Texto") }
    static var toolBlur: String { pick("Blur", "Desfoque") }
    static var toolPixelate: String { pick("Pixelate", "Pixelar") }
    static var censorSoft: String { pick("Soft", "Suave") }
    static var censorMedium: String { pick("Medium", "Médio") }
    static var censorStrong: String { pick("Strong", "Forte") }

    static var textPlaceholder: String { pick("Type text…", "Digite o texto…") }
    static var toastSavedSuccess: String { pick("Saved", "Salvo") }
    static var toastSaveFailed: String { pick("Failed to save image", "Falha ao salvar a imagem") }
    static var toastCopied: String { pick("Copied to clipboard", "Copiado para a área de transferência") }
    static var ocrNoText: String { pick("No text found", "Nenhum texto encontrado") }
    static var ocrCopied: String { pick("Text copied", "Texto copiado") }
    static var ocrFailed: String { pick("Text recognition failed", "Falha no reconhecimento de texto") }
    static var openImageFailed: String { pick("This image can’t be opened", "Não foi possível abrir esta imagem") }
    static func editorSubtitle(width: Int, height: Int, zoomPercent: Int) -> String {
        "\(width) × \(height) px · \(zoomPercent)%"
    }
    static func defaultFileStem(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pick("yyyy-MM-dd 'at' HH.mm.ss", "yyyy-MM-dd 'às' HH.mm.ss")
        return "\(pick("Screenshot", "Captura de Tela")) \(formatter.string(from: date))"
    }

    static var overlayModeArea: String { pick("Area", "Área") }
    static var overlayModeWindow: String { pick("Window", "Janela") }
    static var overlayModeText: String { pick("Text", "Texto") }
    static var overlayModeScrolling: String { pick("Scrolling", "Rolagem") }
    static var overlayModeRecording: String { pick("Recording", "Gravação") }
    static var overlayHintDrag: String { pick("Drag to select", "Arraste para selecionar") }
    static var overlayHintDragText: String { pick("Drag across text", "Arraste sobre o texto") }
    static var overlayHintDragScrolling: String { pick("Drag to select scrollable area", "Arraste para selecionar a área de rolagem") }
    static var overlayHintDragRecording: String { pick("Drag to select recording area", "Arraste para selecionar a área de gravação") }
    static var overlayHintClickWindow: String { pick("Click a window", "Clique numa janela") }
    static var overlayHintClickWindowScrolling: String { pick("Click a window to capture its scroll", "Clique em uma janela para capturar sua rolagem") }
    static var overlayHintClickWindowRecording: String { pick("Click a window to record it", "Clique em uma janela para gravá-la") }
    static var overlayHintSwitchToWindow: String { pick("Window", "Janela") }
    static var overlayHintSwitchToArea: String { pick("Area", "Área") }
    static var overlayHintCopyColor: String { pick("Copy color", "Copiar cor") }
    static var overlayHintText: String { pick("Text", "Texto") }
    static var overlayHintCancel: String { pick("Cancel", "Cancelar") }
    static var windowFallbackTitle: String { pick("Window", "Janela") }
    static func hexCopiedFeedback(hex: String) -> String { pick("HEX Copied: \(hex)", "HEX Copiado: \(hex)") }

    static var scrollingHUDTitle: String { pick("Scrolling Capture", "Captura com Rolagem") }
    static var scrollingHUDAutoScroll: String { pick("Auto-Scroll", "Rolar Auto") }
    static var scrollingHUDFinish: String { pick("Done", "Concluir") }
    static var scrollingHUDCancel: String { pick("Cancel", "Cancelar") }
    static func scrollingHUDMetrics(height: Int, frames: Int) -> String {
        pick("\(height) px · \(frames) frames", "\(height) px · \(frames) quadros")
    }
    static var maxHeightReached: String {
        pick("Maximum capture height reached (32,000 px)", "Altura máxima de captura atingida (32.000 px)")
    }
    static var recordingHUDStop: String { pick("Stop", "Parar") }
    static var recordingHUDCancel: String { pick("Cancel", "Cancelar") }
    static var recordingProcessing: String { pick("Optimizing media…", "Otimizando mídia…") }
    static func recordingSavedToast(format: String, name: String) -> String {
        pick("\(format) saved: \(name)", "\(format) salvo: \(name)")
    }

    static var pinCopy: String { pick("Copy", "Copiar") }
    static var pinClose: String { pick("Close", "Fechar") }
}
