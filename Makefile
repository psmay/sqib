
all: test doc

test:
	busted --lua=lua5.1 tests/main.lua

doc: docs/doc

docs/README.md: README.md
	cp README.md docs/README.md

docs/doc: README.md src/*.lua
	ldoc .

# Add new files and remove missing files from git index
git-update-docs: docs docs/README.md docs/doc
	git rm -rf --cached docs
	git add -v docs

clean:
	rm -rf docs/doc docs/README.md *.tmp

.PHONY: all doc git-update-docs test clean
