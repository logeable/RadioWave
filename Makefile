# Package an app exported from Xcode Organizer as a drag-to-Applications DMG.
# Usage: make dmg APP="/path/to/Radio.app"

APP ?= build/Radio.app
DMG ?= dist/Radio.dmg
VOLUME_NAME ?= Radio

.PHONY: dmg

dmg:
	@if [ ! -d "$(APP)" ]; then \
		echo "App bundle not found: $(APP)" >&2; \
		echo 'Usage: make dmg APP="/path/to/Radio.app"' >&2; \
		exit 1; \
	fi
	@set -eu; \
	stage="$$(mktemp -d)"; \
	trap 'rm -rf "$$stage"' EXIT; \
	mkdir -p "$(dir $(DMG))"; \
	ditto "$(APP)" "$$stage/$$(basename "$(APP)")"; \
	ln -s /Applications "$$stage/Applications"; \
	hdiutil create -volname "$(VOLUME_NAME)" -srcfolder "$$stage" -ov -format UDZO "$(DMG)"; \
	echo "Created $(DMG)"
