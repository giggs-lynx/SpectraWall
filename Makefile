.PHONY: project clean

project:
	@if command -v xcodegen >/dev/null 2>&1; then \
		xcodegen generate; \
	else \
		echo "XcodeGen not found. Install with: brew install xcodegen"; \
		exit 1; \
	fi

clean:
	rm -rf *.xcodeproj *.xcworkspace DerivedData