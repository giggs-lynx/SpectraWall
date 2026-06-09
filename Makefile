SCHEME  = SpectraWall
VERSION = 0.0.1
GIT_COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
BUILD_DIR   = ./build
RELEASE_DIR = $(BUILD_DIR)/Build/Products/Release
DIST_DIR    = ./dist

.PHONY: project release clean

project:
	@if command -v xcodegen >/dev/null 2>&1; then \
		xcodegen generate; \
	else \
		echo "XcodeGen not found. Install with: brew install xcodegen"; \
		exit 1; \
	fi

release:
	@echo "==> Building $(SCHEME) $(VERSION) (Release, unsigned)..."
	xcodebuild build \
		-project $(SCHEME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		MARKETING_VERSION=$(VERSION) \
		GIT_COMMIT=$(GIT_COMMIT) \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO
	@mkdir -p $(DIST_DIR)
	@cd $(RELEASE_DIR) && zip -r --symlinks "$(SCHEME)-$(VERSION).zip" "$(SCHEME).app"
	@mv $(RELEASE_DIR)/$(SCHEME)-$(VERSION).zip $(DIST_DIR)/
	@echo "==> Output: $(DIST_DIR)/$(SCHEME)-$(VERSION).zip"
	@echo "==> SHA256:"
	@shasum -a 256 $(DIST_DIR)/$(SCHEME)-$(VERSION).zip

clean:
	rm -rf *.xcodeproj *.xcworkspace DerivedData $(BUILD_DIR) $(DIST_DIR)