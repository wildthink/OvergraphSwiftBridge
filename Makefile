SWIFT ?= swift
DB ?= ./example-db
CLANG_MODULE_CACHE_PATH ?= /tmp/clang-module-cache
SWIFT_ENV = CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_PATH)
SWIFT_SANDBOX_FLAG ?= --disable-sandbox

.PHONY: overgraph bridge build test cli repl clean

overgraph:
	./Scripts/prepare-overgraph.sh

bridge: overgraph
	./Scripts/build-bridge.sh

build: bridge
	$(SWIFT_ENV) $(SWIFT) build $(SWIFT_SANDBOX_FLAG)

test: bridge
	$(SWIFT_ENV) $(SWIFT) test $(SWIFT_SANDBOX_FLAG)

cli: bridge
	$(SWIFT_ENV) $(SWIFT) build $(SWIFT_SANDBOX_FLAG) --product overgraph-cli

repl: bridge
	$(SWIFT_ENV) $(SWIFT) run $(SWIFT_SANDBOX_FLAG) overgraph-cli --db $(DB)

clean:
	rm -rf .build BridgeArtifacts/lib/libovergraph_swift_bridge.a
	rm -rf rust-bridge/target
