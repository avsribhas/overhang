.PHONY: app run test clean install

app:
	./scripts/build-app.sh

run: app
	open build/Overhang.app

install: app
	rm -rf /Applications/Overhang.app
	cp -R build/Overhang.app /Applications/
	open /Applications/Overhang.app

test:
	swift test

clean:
	rm -rf .build build
