.PHONY: check app run

check:
	swift run -- --self-check

app:
	./scripts/build-app.sh

run: app
	-killall Dropwheel
	open dist/Dropwheel.app
