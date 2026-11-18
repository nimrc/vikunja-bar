.PHONY: build test app install

build:
	swift build

test:
	swift test

app:
	scripts/bundle.sh

install: app
	-pkill -x VikunjaBar
	rm -rf /Applications/VikunjaBar.app
	cp -R dist/VikunjaBar.app /Applications/
	open /Applications/VikunjaBar.app
