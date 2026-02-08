.PHONY: build clean

build:
	cd cli && swift build -c release

clean:
	cd cli && swift package clean
