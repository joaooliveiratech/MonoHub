APP_NAME = MonoHub
BUNDLE_NAME = $(APP_NAME).app
BUILD_DIR = .build/release
APP_DIR = $(BUNDLE_NAME)/Contents
XCODE_DEV_DIR ?= /Applications/Xcode.app/Contents/Developer
LOCAL_BIN_DIR ?= $(HOME)/.local/bin

.PHONY: all build test icon app run run-cli install install-local clean

all: app

build:
	DEVELOPER_DIR=$(XCODE_DEV_DIR) swift build -c release --arch arm64

test:
	DEVELOPER_DIR=$(XCODE_DEV_DIR) swift test --arch arm64

icon:
	@echo "==> Gerando AppIcon e Assets..."
	DEVELOPER_DIR=$(XCODE_DEV_DIR) swift scripts/generate_icon.swift
	@iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
	@rm -rf Resources/AppIcon.iconset
	@echo "==> AppIcon.icns gerado com sucesso!"

CODESIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F'"' '{print $$2}')
ifeq ($(strip $(CODESIGN_IDENTITY)),)
	CODESIGN_IDENTITY = -
endif

CODESIGN_TIMESTAMP = --timestamp=none

app: build
	@echo "==> Criando bundle $(BUNDLE_NAME)..."
	@mkdir -p $(APP_DIR)/MacOS
	@mkdir -p $(APP_DIR)/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_DIR)/MacOS/
	@cp Resources/Info.plist $(APP_DIR)/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(APP_DIR)/Resources/AppIcon.icns; fi
	@echo "==> Assinando bundle com $(CODESIGN_IDENTITY), Hardened Runtime e Entitlements..."
	@codesign --force --options=runtime $(CODESIGN_TIMESTAMP) \
		--sign "$(CODESIGN_IDENTITY)" \
		--entitlements Resources/Entitlements.plist \
		$(BUNDLE_NAME)
	@codesign --verify --strict --verbose=1 $(BUNDLE_NAME)
	@echo "==> $(BUNDLE_NAME) criado com sucesso!"

run: app
	@echo "==> Iniciando $(BUNDLE_NAME)..."
	open $(BUNDLE_NAME)

run-cli: build
	@echo "==> Executando binário diretamente..."
	$(BUILD_DIR)/$(APP_NAME)

install: app
	@echo "==> Encerrando instâncias antigas (MonoHub, MonoClean, MonoStats, MonoTile, MonoTab, MonoNotch, MonoAiBar, MonoShot) em execução..."
	@killall -9 $(APP_NAME) MonoClean MonoStats MonoTile monotile MonoTab monotab MonoNotch mononotch MonoAiBar MonoBar MonoShot monoshot 2>/dev/null || true
	@sleep 0.5
	@echo "==> Limpando instalações duplicadas ou obsoletas (MonoHub, MonoClean, MonoStats, MonoTile, MonoTab, MonoNotch, MonoAiBar, MonoShot) e caches..."
	@rm -rf /Applications/monohub.app /Applications/MonoHub.app ~/Applications/monohub.app ~/Applications/MonoHub.app
	@rm -rf /Applications/monoclean.app /Applications/MonoClean.app ~/Applications/monoclean.app ~/Applications/MonoClean.app
	@rm -rf /Applications/monostats.app /Applications/MonoStats.app ~/Applications/monostats.app ~/Applications/MonoStats.app
	@rm -rf /Applications/monotile.app /Applications/MonoTile.app ~/Applications/monotile.app ~/Applications/MonoTile.app
	@rm -rf /Applications/monotab.app /Applications/MonoTab.app ~/Applications/monotab.app ~/Applications/MonoTab.app
	@rm -rf /Applications/mononotch.app /Applications/MonoNotch.app ~/Applications/mononotch.app ~/Applications/MonoNotch.app
	@rm -rf /Applications/monoaibar.app /Applications/MonoAiBar.app ~/Applications/monoaibar.app ~/Applications/MonoAiBar.app /Applications/MonoBar.app ~/Applications/MonoBar.app
	@rm -rf /Applications/monoshot.app /Applications/MonoShot.app ~/Applications/monoshot.app ~/Applications/MonoShot.app
	@rm -rf ~/Library/Caches/com.antigravity.monoshot
	@rm -rf ~/Library/Caches/com.joaooliveiratech.monohub ~/Library/Caches/MonoBar
	@rm -rf ~/Library/Caches/com.antigravity.monohub ~/Library/Caches/com.antigravity.monoclean ~/Library/Caches/com.antigravity.monostats ~/Library/Caches/com.antigravity.monotile ~/Library/Caches/com.antigravity.monotab ~/Library/Caches/com.antigravity.mononotch
	@rm -f $(LOCAL_BIN_DIR)/MonoClean $(LOCAL_BIN_DIR)/monoclean $(LOCAL_BIN_DIR)/MonoStats $(LOCAL_BIN_DIR)/monostats $(LOCAL_BIN_DIR)/MonoTile $(LOCAL_BIN_DIR)/monotile $(LOCAL_BIN_DIR)/MonoTab $(LOCAL_BIN_DIR)/monotab $(LOCAL_BIN_DIR)/MonoNotch $(LOCAL_BIN_DIR)/mononotch $(LOCAL_BIN_DIR)/MonoAiBar $(LOCAL_BIN_DIR)/monoaibar $(LOCAL_BIN_DIR)/monobar $(LOCAL_BIN_DIR)/MonoShot $(LOCAL_BIN_DIR)/monoshot
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/MonoClean.app 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/MonoStats.app 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/MonoTile.app 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/MonoTab.app 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/MonoNotch.app 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/MonoAiBar.app 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/MonoShot.app 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u ~/Applications/MonoHub.app 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u $(shell pwd)/$(BUNDLE_NAME) 2>/dev/null || true
	@echo "==> Instalando $(BUNDLE_NAME) em /Applications..."
	@cp -R $(BUNDLE_NAME) /Applications/
	@touch /Applications/$(BUNDLE_NAME)
	@echo "==> Removendo bundle do repositório local para evitar duplicação no LaunchServices..."
	@rm -rf $(BUNDLE_NAME)
	@echo "==> Criando atalhos CLI em $(LOCAL_BIN_DIR)..."
	@mkdir -p $(LOCAL_BIN_DIR)
	@ln -sf /Applications/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(LOCAL_BIN_DIR)/MonoHub
	@ln -sf /Applications/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(LOCAL_BIN_DIR)/monohub
	@ln -sf /Applications/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(LOCAL_BIN_DIR)/MonoTile
	@ln -sf /Applications/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(LOCAL_BIN_DIR)/monotile
	@ln -sf /Applications/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(LOCAL_BIN_DIR)/MonoTab
	@ln -sf /Applications/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(LOCAL_BIN_DIR)/monotab
	@ln -sf /Applications/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(LOCAL_BIN_DIR)/MonoNotch
	@ln -sf /Applications/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(LOCAL_BIN_DIR)/mononotch
	@ln -sf /Applications/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(LOCAL_BIN_DIR)/MonoAiBar
	@ln -sf /Applications/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(LOCAL_BIN_DIR)/monoaibar
	@ln -sf /Applications/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(LOCAL_BIN_DIR)/MonoShot
	@ln -sf /Applications/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(LOCAL_BIN_DIR)/monoshot
	@echo "==> Atualizando LaunchServices e caches do sistema..."
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/$(BUNDLE_NAME)
	@qlmanage -r 2>/dev/null || true
	@killall Finder 2>/dev/null || true
	@echo "==> Reiniciando $(APP_NAME) atualizado..."
	@open /Applications/$(BUNDLE_NAME)
	@echo "==> $(APP_NAME) instalado e iniciado com sucesso!"

install-local: install

clean:
	@rm -rf .build $(BUNDLE_NAME) Resources/AppIcon.iconset
	@echo "==> Limpeza concluída."
