SCHEME  = SpectraWall
VERSION = 0.0.1
GIT_COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
BUILD_DIR   = ./build
RELEASE_DIR = $(BUILD_DIR)/Build/Products/Release
DIST_DIR    = ./dist

.PHONY: project dist release clean

project:
	@if command -v xcodegen >/dev/null 2>&1; then \
		xcodegen generate; \
	else \
		echo "XcodeGen not found. Install with: brew install xcodegen"; \
		exit 1; \
	fi

# `make release 0.0.9` sugar: the word after `release` becomes the version
# (a leading `v` is tolerated) and gets a no-op rule so make doesn't try to
# build it as a target. `make release VERSION=0.0.9` still works.
ifeq (release,$(firstword $(MAKECMDGOALS)))
RELEASE_ARG := $(filter-out project dist release clean,$(word 2,$(MAKECMDGOALS)))
ifneq ($(RELEASE_ARG),)
RELEASE_VERSION := $(patsubst v%,%,$(RELEASE_ARG))
$(RELEASE_ARG): ; @:
endif
endif
ifeq ($(origin VERSION),command line)
RELEASE_VERSION := $(VERSION)
endif

# Cut a release: tag the pushed main HEAD and let GitHub Actions do the rest
# (dist build, GitHub Release, homebrew-tap bump).
release:
ifndef RELEASE_VERSION
	$(error version required — usage: make release x.y.z  (latest tag: $(shell git describe --tags --abbrev=0)))
endif
	@test -z "$$(git status --porcelain)" || { echo "==> Working tree not clean — commit or stash first."; exit 1; }
	@git fetch -q origin main
	@test "$$(git rev-parse HEAD)" = "$$(git rev-parse origin/main)" || \
		{ echo "==> HEAD is not origin/main — push main first."; exit 1; }
	git tag -s v$(RELEASE_VERSION) -m "v$(RELEASE_VERSION)"
	git push origin v$(RELEASE_VERSION)
	@echo "==> Tag v$(RELEASE_VERSION) pushed. GitHub Actions takes it from here (watch: gh run watch)."

dist:
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