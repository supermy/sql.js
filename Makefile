# Note: Last built with version 2.0.15 of Emscripten

# TODO: Emit a file showing which version of emcc and SQLite was used to compile the emitted output.
# TODO: Create a release on Github with these compiled assets rather than checking them in
# TODO: Consider creating different files based on browser vs module usage: https://github.com/vuejs/vue/tree/dev/dist

# I got this handy makefile syntax from : https://github.com/mandel59/sqlite-wasm (MIT License) Credited in LICENSE
# To use another version of Sqlite, visit https://www.sqlite.org/download.html and copy the appropriate values here:
SQLITE_AMALGAMATION = sqlite-amalgamation-3360000
SQLITE_AMALGAMATION_ZIP_URL = https://www.sqlite.org/2021/sqlite-amalgamation-3360000.zip
SQLITE_AMALGAMATION_ZIP_SHA3 = d7a869230999f88afc043affd1e3f04751735d9ae2b55962c71e492a

# Note that extension-functions.c hasn't been updated since 2010-02-06, so likely doesn't need to be updated
EXTENSION_FUNCTIONS = extension-functions.c
EXTENSION_FUNCTIONS_URL = https://www.sqlite.org/contrib/download/extension-functions.c?get=25
EXTENSION_FUNCTIONS_SHA1 = c68fa706d6d9ff98608044c00212473f9c14892f

EMCC=emcc

CFLAGS = \
	-O2 \
	-DSQLITE_OMIT_LOAD_EXTENSION \
	-DSQLITE_DISABLE_LFS \
	-DSQLITE_ENABLE_FTS3 \
	-DSQLITE_ENABLE_FTS3_PARENTHESIS \
	-DSQLITE_ENABLE_JSON1 \
	-DSQLITE_THREADSAFE=0 \
	-DSQLITE_ENABLE_NORMALIZE

# When compiling to WASM, enabling memory-growth is not expected to make much of an impact, so we enable it for all builds
# Since tihs is a library and not a standalone executable, we don't want to catch unhandled Node process exceptions
# So, we do : `NODEJS_CATCH_EXIT=0`, which fixes issue: https://github.com/sql-js/sql.js/issues/173 and https://github.com/sql-js/sql.js/issues/262
# --memory-init-file 1的设置会将静态内存代码初始化的这一部分代码放到.mem后缀的文件中，和.js文件分开。这个.mem文件会在main()函数被调用，代码执行前异步加载。从Emscripten 1.21.1 起，-O2及以上的优化级别默认启动了这项设置。
# 使用Runtime.addFunction返回一个整数来表示一个函数指针。把这个整数传给C代码，然后C代码调用那个值，则传给Runtime.addFunction的JavaScript函数就被调用。当你用Runtime.addFunction，会有一个数组来存这些函数。这个数组的大小必须被明确指定，这可以通过编译设置项RESERVED_FUNCTION_POINTERS来做。举例,保存20个函数大小。
# 编译命令里面要用-s EXPORTED_FUNCTIONS参数给出输出的函数名数组，而且函数名前面加下划线。
# 导出C函数-s EXPORTED_RUNTIME_METHODS='["ccall", "cwrap"]'
EMFLAGS = \
	--memory-init-file 0 \
	-s RESERVED_FUNCTION_POINTERS=64 \
	-s ALLOW_TABLE_GROWTH=1 \
	-s EXPORTED_FUNCTIONS=@src/exported_functions.json \
	-s EXPORTED_RUNTIME_METHODS=@src/exported_runtime_methods.json \
	-s SINGLE_FILE=0 \
	-s NODEJS_CATCH_EXIT=0 \
	-s NODEJS_CATCH_REJECTION=0

EMFLAGS_ASM = \
	-s WASM=0

EMFLAGS_ASM_MEMORY_GROWTH = \
	-s WASM=0 \
	-s ALLOW_MEMORY_GROWTH=1

# WASM=1表示输出wasm的文件
# 在运行时扩大内存容量的模式，在编译时增加-s ALLOW_MEMORY_GROWTH=1
EMFLAGS_WASM = \
	-s WASM=1 \
	-s ALLOW_MEMORY_GROWTH=1

# 运行压缩编译器（Closure Compiler），可能的取值有，0,1,2：
# 启用llvm优化。它的取值有有：
# 0：不使用llvm优化
# 1：llvm -O1优化
# 2：llvm -O2优化
# 3：llvm -O3优化
# 不允许嵌入/内联代码：-s INLINING_LIMIT=1。
# 启用链接时间优化（LTO）。
EMFLAGS_OPTIMIZED= \
	-s INLINING_LIMIT=50 \
	-O3 \
	-flto \
	--closure 1

# ASSERTIONS=1 用于为内存分配错误启用运行时检查
EMFLAGS_DEBUG = \
	-s INLINING_LIMIT=10 \
	-s ASSERTIONS=1 \
	-O1

BITCODE_FILES = out/sqlite3.bc out/extension-functions.bc

OUTPUT_WRAPPER_FILES = src/shell-pre.js src/shell-post.js

SOURCE_API_FILES = src/api.js

EMFLAGS_PRE_JS_FILES = \
	--pre-js src/api.js

EXPORTED_METHODS_JSON_FILES = src/exported_functions.json src/exported_runtime_methods.json

all: optimized debug worker

# .PHONY后面的target表示的也是一个伪造的target, 而不是真实存在的文件target，注意Makefile的target默认是文件。
.PHONY: debug
debug: dist/sql-asm-debug.js dist/sql-wasm-debug.js

dist/sql-asm-debug.js: $(BITCODE_FILES) $(OUTPUT_WRAPPER_FILES) $(SOURCE_API_FILES) $(EXPORTED_METHODS_JSON_FILES)
	$(EMCC) $(EMFLAGS) $(EMFLAGS_DEBUG) $(EMFLAGS_ASM) $(BITCODE_FILES) $(EMFLAGS_PRE_JS_FILES) -o $@
	mv $@ out/tmp-raw.js
	cat src/shell-pre.js out/tmp-raw.js src/shell-post.js > $@
	rm out/tmp-raw.js

dist/sql-wasm-debug.js: $(BITCODE_FILES) $(OUTPUT_WRAPPER_FILES) $(SOURCE_API_FILES) $(EXPORTED_METHODS_JSON_FILES)
	$(EMCC) $(EMFLAGS) $(EMFLAGS_DEBUG) $(EMFLAGS_WASM) $(BITCODE_FILES) $(EMFLAGS_PRE_JS_FILES) -o $@
	mv $@ out/tmp-raw.js
	cat src/shell-pre.js out/tmp-raw.js src/shell-post.js > $@
	rm out/tmp-raw.js

.PHONY: optimized
optimized: dist/sql-asm.js dist/sql-wasm.js dist/sql-asm-memory-growth.js

dist/sql-asm.js: $(BITCODE_FILES) $(OUTPUT_WRAPPER_FILES) $(SOURCE_API_FILES) $(EXPORTED_METHODS_JSON_FILES)
	$(EMCC) $(EMFLAGS) $(EMFLAGS_OPTIMIZED) $(EMFLAGS_ASM) $(BITCODE_FILES) $(EMFLAGS_PRE_JS_FILES) -o $@
	mv $@ out/tmp-raw.js
	cat src/shell-pre.js out/tmp-raw.js src/shell-post.js > $@
	rm out/tmp-raw.js

dist/sql-wasm.js: $(BITCODE_FILES) $(OUTPUT_WRAPPER_FILES) $(SOURCE_API_FILES) $(EXPORTED_METHODS_JSON_FILES)
	$(EMCC) $(EMFLAGS) $(EMFLAGS_OPTIMIZED) $(EMFLAGS_WASM) $(BITCODE_FILES) $(EMFLAGS_PRE_JS_FILES) -o $@
	mv $@ out/tmp-raw.js
	cat src/shell-pre.js out/tmp-raw.js src/shell-post.js > $@
	rm out/tmp-raw.js

dist/sql-asm-memory-growth.js: $(BITCODE_FILES) $(OUTPUT_WRAPPER_FILES) $(SOURCE_API_FILES) $(EXPORTED_METHODS_JSON_FILES)
	$(EMCC) $(EMFLAGS) $(EMFLAGS_OPTIMIZED) $(EMFLAGS_ASM_MEMORY_GROWTH) $(BITCODE_FILES) $(EMFLAGS_PRE_JS_FILES) -o $@
	mv $@ out/tmp-raw.js
	cat src/shell-pre.js out/tmp-raw.js src/shell-post.js > $@
	rm out/tmp-raw.js

# Web worker API
.PHONY: worker
worker: dist/worker.sql-asm.js dist/worker.sql-asm-debug.js dist/worker.sql-wasm.js dist/worker.sql-wasm-debug.js

dist/worker.sql-asm.js: dist/sql-asm.js src/worker.js
	cat $^ > $@

dist/worker.sql-asm-debug.js: dist/sql-asm-debug.js src/worker.js
	cat $^ > $@

dist/worker.sql-wasm.js: dist/sql-wasm.js src/worker.js
	cat $^ > $@

dist/worker.sql-wasm-debug.js: dist/sql-wasm-debug.js src/worker.js
	cat $^ > $@

# Building it this way gets us a wrapper that _knows_ it's in worker mode, which is nice.
# However, since we can't tell emcc that we don't need the wasm generated, and just want the wrapper, we have to pay to have the .wasm generated
# even though we would have already generated it with our sql-wasm.js target above.
# This would be made easier if this is implemented: https://github.com/emscripten-core/emscripten/issues/8506
# dist/worker.sql-wasm.js: $(BITCODE_FILES) $(OUTPUT_WRAPPER_FILES) src/api.js src/worker.js $(EXPORTED_METHODS_JSON_FILES) dist/sql-wasm-debug.wasm
# 	$(EMCC) $(EMFLAGS) $(EMFLAGS_OPTIMIZED) -s ENVIRONMENT=worker -s $(EMFLAGS_WASM) $(BITCODE_FILES) --pre-js src/api.js -o out/sql-wasm.js
# 	mv out/sql-wasm.js out/tmp-raw.js
# 	cat src/shell-pre.js out/tmp-raw.js src/shell-post.js src/worker.js > $@
# 	#mv out/sql-wasm.wasm dist/sql-wasm.wasm
# 	rm out/tmp-raw.js

# dist/worker.sql-wasm-debug.js: $(BITCODE_FILES) $(OUTPUT_WRAPPER_FILES) src/api.js src/worker.js $(EXPORTED_METHODS_JSON_FILES) dist/sql-wasm-debug.wasm
# 	$(EMCC) -s ENVIRONMENT=worker $(EMFLAGS) $(EMFLAGS_DEBUG) -s ENVIRONMENT=worker -s WASM_BINARY_FILE=sql-wasm-foo.debug $(EMFLAGS_WASM) $(BITCODE_FILES) --pre-js src/api.js -o out/sql-wasm-debug.js
# 	mv out/sql-wasm-debug.js out/tmp-raw.js
# 	cat src/shell-pre.js out/tmp-raw.js src/shell-post.js src/worker.js > $@
# 	#mv out/sql-wasm-debug.wasm dist/sql-wasm-debug.wasm
# 	rm out/tmp-raw.js

out/sqlite3.bc: sqlite-src/$(SQLITE_AMALGAMATION)
	mkdir -p out
	# Generate llvm bitcode
	$(EMCC) $(CFLAGS) -c sqlite-src/$(SQLITE_AMALGAMATION)/sqlite3.c -o $@

# Since the extension-functions.c includes other headers in the sqlite_amalgamation, we declare that this depends on more than just extension-functions.c
out/extension-functions.bc: sqlite-src/$(SQLITE_AMALGAMATION)
	mkdir -p out
	# Generate llvm bitcode
	$(EMCC) $(CFLAGS) -c sqlite-src/$(SQLITE_AMALGAMATION)/extension-functions.c -o $@

# TODO: This target appears to be unused. If we re-instatate it, we'll need to add more files inside of the JS folder
# module.tar.gz: test package.json AUTHORS README.md dist/sql-asm.js
# 	tar --create --gzip $^ > $@

## cache
cache/$(SQLITE_AMALGAMATION).zip:
	mkdir -p cache
	curl -LsSf '$(SQLITE_AMALGAMATION_ZIP_URL)' -o $@

cache/$(EXTENSION_FUNCTIONS):
	mkdir -p cache
	curl -LsSf '$(EXTENSION_FUNCTIONS_URL)' -o $@

## sqlite-src
.PHONY: sqlite-src
sqlite-src: sqlite-src/$(SQLITE_AMALGAMATION) sqlite-src/$(SQLITE_AMALGAMATION)/$(EXTENSION_FUNCTIONS)

sqlite-src/$(SQLITE_AMALGAMATION): cache/$(SQLITE_AMALGAMATION).zip sqlite-src/$(SQLITE_AMALGAMATION)/$(EXTENSION_FUNCTIONS)
	mkdir -p sqlite-src/$(SQLITE_AMALGAMATION)
	echo '$(SQLITE_AMALGAMATION_ZIP_SHA3)  ./cache/$(SQLITE_AMALGAMATION).zip' > cache/check.txt
	sha3sum -c cache/check.txt
	# We don't delete the sqlite_amalgamation folder. That's a job for clean
	# Also, the extension functions get copied here, and if we get the order of these steps wrong,
	# this step could remove the extension functions, and that's not what we want
	unzip -u 'cache/$(SQLITE_AMALGAMATION).zip' -d sqlite-src/
	touch $@

sqlite-src/$(SQLITE_AMALGAMATION)/$(EXTENSION_FUNCTIONS): cache/$(EXTENSION_FUNCTIONS)
	mkdir -p sqlite-src/$(SQLITE_AMALGAMATION)
	echo '$(EXTENSION_FUNCTIONS_SHA1)  ./cache/$(EXTENSION_FUNCTIONS)' > cache/check.txt
	sha1sum -c cache/check.txt
	cp 'cache/$(EXTENSION_FUNCTIONS)' $@


.PHONY: clean
clean:
	rm -f out/* dist/* cache/*
	rm -rf sqlite-src/
