.PHONY: project open clean

project:
	xcodegen generate

open: project
	open HTZoneMetzer.xcodeproj

clean:
	rm -rf HTZoneMetzer.xcodeproj DerivedData build
