# dependencies
SQLITE_VERSION = version-3.45.0
SQLITE_TARBALL_URL = https://www.sqlite.org/src/tarball/sqlite.tar.gz?r=${SQLITE_VERSION}

EXTENSION_FUNCTIONS = extension-functions.c
EXTENSION_FUNCTIONS_URL = https://www.sqlite.org/contrib/download/extension-functions.c?get=25
EXTENSION_FUNCTIONS_SHA = 991b40fe8b2799edc215f7260b890f14a833512c9d9896aa080891330ffe4052

CFILES_EXTRA = \
	crsqlite.c \
	changes-vtab.c \
	ext-data.c

# source files
CFILES = \
	sqlite3-extra.c \
	extension-functions.c \
	main.c \
	libauthorizer.c \
	libfunction.c \
	libprogress.c \
	libvfs.c \
	$(CFILES_EXTRA)

JSFILES = \
	src/libauthorizer.js \
	src/libfunction.js \
	src/libprogress.js \
	src/libvfs.js

dir.crsql := ./crsql/src

vpath %.c src
vpath %.c deps
vpath %.c deps/$(SQLITE_VERSION)
vpath %.c $(dir.crsql)

EXPORTED_FUNCTIONS = src/exported_functions.json
EXPORTED_RUNTIME_METHODS = src/extra_exported_runtime_methods.json
ASYNCIFY_IMPORTS = src/asyncify_imports.json
ASYNCIFY_EXPORTS = src/asyncify_exports.json

# intermediate files
RS_LIB = crsql_bundle
RS_LIB_DIR = ./crsql/rs/bundle
RS_WASM_TGT = wasm32-unknown-emscripten
RS_WASM_TGT_DIR = $(RS_LIB_DIR)/target/$(RS_WASM_TGT)
RS_RELEASE_BC = $(RS_WASM_TGT_DIR)/release/deps/$(RS_LIB).bc
RS_DEBUG_BC = $(RS_WASM_TGT_DIR)/debug/deps/$(RS_LIB).bc

OBJ_FILES_DEBUG = $(patsubst %.c,tmp/obj/debug/%.o,$(CFILES))
OBJ_FILES_DIST = $(patsubst %.c,tmp/obj/dist/%.o,$(CFILES))

sqlite3.c := deps/$(SQLITE_VERSION)/sqlite3.c
sqlite3.extra.c := deps/$(SQLITE_VERSION)/sqlite3-extra.c

# build options
EMCC ?= emcc

CFLAGS_EXTRA = -I'$(dir.crsql)'

CFLAGS_COMMON = \
	-I'deps/$(SQLITE_VERSION)' \
	-Wno-non-literal-null-conversion \
	$(CFLAGS_EXTRA)
CFLAGS_DEBUG = -g $(CFLAGS_COMMON)
CFLAGS_DIST =  -Oz -flto $(CFLAGS_COMMON)

EMFLAGS_COMMON = \
	-s ALLOW_MEMORY_GROWTH=1 \
	-s WASM=1 \
	-s INVOKE_RUN \
	-s ENVIRONMENT="web,worker" \
	-s STACK_SIZE=512KB \
	$(EMFLAGS_EXTRA)

EMFLAGS_DEBUG = \
	-s ASSERTIONS=1 \
	-g -O1 \
	$(EMFLAGS_COMMON)

EMFLAGS_DIST = \
	-O3 \
	-flto \
	$(EMFLAGS_COMMON)

EMFLAGS_INTERFACES = \
	-s EXPORTED_FUNCTIONS=@$(EXPORTED_FUNCTIONS) \
	-s EXPORTED_RUNTIME_METHODS=@$(EXPORTED_RUNTIME_METHODS)

EMFLAGS_LIBRARIES = \
	--js-library src/libadapters.js \
	--post-js src/libauthorizer.js \
	--post-js src/libfunction.js \
	--post-js src/libprogress.js \
	--post-js src/libvfs.js

EMFLAGS_ASYNCIFY_COMMON = \
	-s ASYNCIFY \
	-s ASYNCIFY_IMPORTS=@src/asyncify_imports.json

EMFLAGS_ASYNCIFY_DEBUG = \
	$(EMFLAGS_ASYNCIFY_COMMON) \
	-s ASYNCIFY_STACK_SIZE=24576

EMFLAGS_ASYNCIFY_DIST = \
	$(EMFLAGS_ASYNCIFY_COMMON) \
	-s ASYNCIFY_STACK_SIZE=16384

EMFLAGS_JSPI = \
	-s ASYNCIFY=2 \
	-s ASYNCIFY_IMPORTS=@src/asyncify_imports.json \
	-s ASYNCIFY_EXPORTS=@src/asyncify_exports.json

# NOTE: The tests expect the default page size to be 8192 (not 4096 like the sqlite3 default)
WASQLITE_EXTRA_DEFINES = \
	-DSQLITE_EXTRA_INIT=core_init \
	-DSQLITE_ENABLE_FTS5 \
	-DSQLITE_OMIT_UTF16 \
	-DSQLITE_ENABLE_BYTECODE_VTAB \
	-DDEFAULT_CACHE_SIZE=8000 \
	-DCRSQLITE_WASM \
	-DSQLITE_DEFAULT_PAGE_SIZE=8192

# https://www.sqlite.org/compile.html
WASQLITE_DEFINES = \
	-DSQLITE_DEFAULT_MEMSTATUS=0 \
	-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 \
	-DSQLITE_DQS=0 \
	-DSQLITE_LIKE_DOESNT_MATCH_BLOBS \
	-DSQLITE_MAX_EXPR_DEPTH=0 \
	-DSQLITE_OMIT_AUTOINIT \
	-DSQLITE_OMIT_DECLTYPE \
	-DSQLITE_OMIT_DEPRECATED \
	-DSQLITE_OMIT_LOAD_EXTENSION \
	-DSQLITE_OMIT_SHARED_CACHE \
	-DSQLITE_THREADSAFE=0 \
	-DSQLITE_USE_ALLOCA \
	-DSQLITE_ENABLE_BATCH_ATOMIC_WRITE \
	$(WASQLITE_EXTRA_DEFINES)

# directories
.PHONY: all
all: dist

$(sqlite3.extra.c): $(sqlite3.c) $(dir.crsql)/core_init.c
	cat $(sqlite3.c) $(dir.crsql)/core_init.c > $@

.PHONY: crsqlite-extra
crsqlite-extra: $(sqlite3.extra.c)

.PHONY: clean
clean:
	rm -rf dist debug tmp
	rm -f *.o

.PHONY: spotless
spotless:
	rm -rf dist debug tmp deps cache

## cache
.PHONY: clean-cache
clean-cache:
	rm -rf cache

cache/$(EXTENSION_FUNCTIONS):
	mkdir -p cache
	curl -LsSf '$(EXTENSION_FUNCTIONS_URL)' -o $@

## deps
.PHONY: clean-deps
clean-deps:
	rm -rf deps

deps/$(SQLITE_VERSION)/sqlite3.h deps/$(SQLITE_VERSION)/sqlite3.c:
	mkdir -p cache/$(SQLITE_VERSION)
	curl -LsS $(SQLITE_TARBALL_URL) | tar -xzf - -C cache/$(SQLITE_VERSION)/ --strip-components=1
	mkdir -p deps/$(SQLITE_VERSION)
	(cd deps/$(SQLITE_VERSION); ../../cache/$(SQLITE_VERSION)/configure --enable-all && make sqlite3.c)

deps/$(EXTENSION_FUNCTIONS): cache/$(EXTENSION_FUNCTIONS)
	mkdir -p deps
	openssl dgst -sha256 -r cache/$(EXTENSION_FUNCTIONS) | sed -e 's/ .*//' > deps/sha
	echo $(EXTENSION_FUNCTIONS_SHA) > deps/sha-expected
	cmp deps/sha deps/sha-expected
	rm -rf deps/sha deps/sha-expected $@
	cp 'cache/$(EXTENSION_FUNCTIONS)' $@

## tmp
.PHONY: clean-tmp
clean-tmp:
	rm -rf tmp

tmp/obj/debug/%.o: %.c
	mkdir -p tmp/obj/debug
	$(EMCC) $(CFLAGS_DEBUG) $(WASQLITE_DEFINES) $^ -c -o $@

tmp/obj/dist/%.o: %.c
	mkdir -p tmp/obj/dist
	$(EMCC) $(CFLAGS_DIST) $(WASQLITE_DEFINES) $^ -c -o $@

# This repo is only ever intended to be built when it is a submodule of the cr-sqlite/js repo.
$(RS_DEBUG_BC): export CRSQLITE_COMMIT_SHA = $(shell cd ..; git rev-parse HEAD)
$(RS_DEBUG_BC): FORCE
	mkdir -p tmp/bc/dist
	cd $(RS_LIB_DIR); \
	RUSTFLAGS="--emit=llvm-bc -C linker=/usr/bin/true" cargo build --features static,omit_load_extension -Z build-std=panic_abort,core,alloc --target $(RS_WASM_TGT)

# See comments on debug
$(RS_RELEASE_BC): export CRSQLITE_COMMIT_SHA = $(shell cd ..; git rev-parse HEAD)
$(RS_RELEASE_BC): FORCE
	mkdir -p tmp/bc/dist
	cd $(RS_LIB_DIR); \
	RUSTFLAGS="--emit=llvm-bc -C linker=/usr/bin/true" cargo build --features static,omit_load_extension --release -Z build-std=panic_abort,core,alloc --target $(RS_WASM_TGT)

## debug
.PHONY: clean-debug
clean-debug:
	rm -rf debug

.PHONY: debug
debug: debug/crsqlite-sync.mjs debug/crsqlite.mjs debug/crsqlite-jspi.mjs

debug/crsqlite-sync.mjs: $(OBJ_FILES_DEBUG) $(JSFILES) $(RS_DEBUG_BC) $(EXPORTED_FUNCTIONS) $(EXPORTED_RUNTIME_METHODS)
	mkdir -p debug
	$(EMCC) $(EMFLAGS_DEBUG) \
	  $(EMFLAGS_INTERFACES) \
	  $(EMFLAGS_LIBRARIES) \
	  $(RS_WASM_TGT_DIR)/debug/deps/*.bc \
	  $(OBJ_FILES_DEBUG) -o $@

debug/crsqlite.mjs: $(OBJ_FILES_DEBUG) $(JSFILES) $(RS_DEBUG_BC) $(EXPORTED_FUNCTIONS) $(EXPORTED_RUNTIME_METHODS) $(ASYNCIFY_IMPORTS)
	mkdir -p debug
	$(EMCC) $(EMFLAGS_DEBUG) \
	  $(EMFLAGS_INTERFACES) \
	  $(EMFLAGS_LIBRARIES) \
	  $(EMFLAGS_ASYNCIFY_DEBUG) \
	  $(RS_WASM_TGT_DIR)/debug/deps/*.bc \
	  $(OBJ_FILES_DEBUG) -o $@

debug/crsqlite-jspi.mjs: $(OBJ_FILES_DEBUG) $(JSFILES) $(RS_RELEASE_BC) $(EXPORTED_FUNCTIONS) $(EXPORTED_RUNTIME_METHODS) $(ASYNCIFY_IMPORTS)
	mkdir -p debug
	$(EMCC) $(EMFLAGS_DEBUG) \
	  $(EMFLAGS_INTERFACES) \
	  $(EMFLAGS_LIBRARIES) \
	  $(EMFLAGS_JSPI) \
	  $(RS_WASM_TGT_DIR)/release/deps/*.bc \
	  $(OBJ_FILES_DEBUG) -o $@

## dist
.PHONY: clean-dist
clean-dist:
	rm -rf dist

.PHONY: dist
dist: dist/crsqlite-sync.mjs dist/crsqlite.mjs dist/crsqlite-jspi.mjs

FORCE: ;

dist/crsqlite-sync.mjs: $(OBJ_FILES_DIST) $(JSFILES) $(RS_RELEASE_BC) $(EXPORTED_FUNCTIONS) $(EXPORTED_RUNTIME_METHODS)
	mkdir -p dist
	$(EMCC) $(EMFLAGS_DIST) \
	  $(EMFLAGS_INTERFACES) \
	  $(EMFLAGS_LIBRARIES) \
	  $(RS_WASM_TGT_DIR)/release/deps/*.bc \
	  $(OBJ_FILES_DIST) -o $@

dist/crsqlite.mjs: $(OBJ_FILES_DIST) $(JSFILES) $(RS_RELEASE_BC) $(EXPORTED_FUNCTIONS) $(EXPORTED_RUNTIME_METHODS) $(ASYNCIFY_IMPORTS)
	mkdir -p dist
	$(EMCC) $(EMFLAGS_DIST) \
	  $(EMFLAGS_INTERFACES) \
	  $(EMFLAGS_LIBRARIES) \
	  $(EMFLAGS_ASYNCIFY_DIST) \
	  $(RS_WASM_TGT_DIR)/release/deps/*.bc \
	  $(OBJ_FILES_DIST) -o $@

dist/crsqlite-jspi.mjs: $(OBJ_FILES_DIST) $(JSFILES) $(RS_RELEASE_BC) $(EXPORTED_FUNCTIONS) $(EXPORTED_RUNTIME_METHODS) $(ASYNCIFY_IMPORTS)
	mkdir -p dist
	$(EMCC) $(EMFLAGS_DIST) \
	  $(EMFLAGS_INTERFACES) \
	  $(EMFLAGS_LIBRARIES) \
	  $(EMFLAGS_JSPI) \
	  $(RS_WASM_TGT_DIR)/release/deps/*.bc \
	  $(OBJ_FILES_DIST) -o $@
