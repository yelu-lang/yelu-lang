CMAKE_OUT = _out/cmake
TV1 = vendor/cmake-tutorial/v1
TV2 = vendor/cmake/Help/guide/tutorial/Complete
OUT_TO_STEP = ../../../$(TV1)

# dune-project lives at repo root; dune commands run from here
TOLA = .

# Prepend opam default switch to PATH so dune/opam work without eval $(opam env).
# If dune is already on PATH (CC bash env configured), this is a no-op.
DUNE = PATH="$(HOME)/.opam/default/bin:$$PATH"

# ── Build targets ─────────────────────────────────────────────────────────────
# build:         build everything in  (langs + bins)
# build-cmake:   build only the cmake layer (lang_cmake + bin/cmake)
# build-yelu:    build only the yelu layer (lang_yelu + bin/yelu)

build:
	$(DUNE) dune build 

build-cmake:
	$(DUNE) dune build src/langs/ src/bin/cmake/v1/ src/bin/cmake/v2/

build-yelu:
	$(DUNE) dune build src/langs/ src/bin/yelu/

# ── Test targets ──────────────────────────────────────────────────────────────
# test:          all unit tests (cmake PP + yelu compile, no cmake needed)
# test-pp:       cmake pretty-printer unit tests only
# test-yc:       yelu compile unit tests only
# cmake-check:   structural text equivalence via gersemi (no cmake needed)
# file-api-test: semantic equivalence via cmake File API (requires cmake)
# build-check:   build artifact existence + ELF magic check
# test-all:      all of the above in order

test:
	$(DUNE) dune test 

test-pp:
	$(DUNE) dune test test/test-cmake/

test-yc:
	$(DUNE) dune test test/test-yelu/

build-check:
	$(DUNE) dune build src/bin/cmake/v1/ src/bin/yelu/
	$(DUNE) python3 test/test-build/run_build_check.py

runcmake-compat:
	$(DUNE) dune build @test/test-runcmake/runcmake-compat

runcmake-yelu:
	$(DUNE) dune build @test/test-runcmake/runcmake-yelu

cmake-commands:
	$(DUNE) dune build @test/test-runcmake/cmake-commands

file-api-test:
	$(DUNE) dune build @test/test-file-api/file-api-test

coverage: test cmake-check yelu-check-v2 cmake-only-check runcmake-compat runcmake-yelu cmake-commands file-api-test
	@echo "=== Coverage sweep complete ==="

test-all: test cmake-check file-api-test build-check

# Structural equivalence check: compare generated CMake output against reference files
# Uses gersemi to normalize both sides before diffing
# Skips checks where reference file is empty (not yet populated)
# To-do: consider using Python instead of embedding shell.
define check_cmake_v1
	@bash -c '\
	  if [ ! -s "$(2)" ]; then \
	    echo "  SKIP $(1) -> $(2) (empty reference)"; \
	  elif diff -B <($(DUNE) dune exec src/bin/cmake/v1/$(1).exe 2>/dev/null | gersemi - 2>/dev/null) <(gersemi $(2) 2>/dev/null) > /dev/null 2>&1; then \
	    echo "  OK   $(1) -> $(2)"; \
	  else \
	    echo "  FAIL $(1) -> $(2)"; \
	    diff -B <($(DUNE) dune exec src/bin/cmake/v1/$(1).exe 2>/dev/null | gersemi - 2>/dev/null) <(gersemi $(2) 2>/dev/null) | head -20; \
	    echo "$(1)" >> /tmp/tola-cmake-check-failures; \
	  fi'
endef

define check_cmake_v2
	@bash -c '\
	  if [ ! -s "$(2)" ]; then \
	    echo "  SKIP $(1) -> $(2) (empty reference)"; \
	  elif diff -B <($(DUNE) dune exec src/bin/cmake/v2/$(1).exe 2>/dev/null | gersemi - 2>/dev/null) <(gersemi $(2) 2>/dev/null) > /dev/null 2>&1; then \
	    echo "  OK   $(1) -> $(2)"; \
	  else \
	    echo "  FAIL $(1) -> $(2)"; \
	    diff -B <($(DUNE) dune exec src/bin/cmake/v2/$(1).exe 2>/dev/null | gersemi - 2>/dev/null) <(gersemi $(2) 2>/dev/null) | head -20; \
	    echo "$(1)" >> /tmp/tola-cmake-check-failures; \
	  fi'
endef

cmake-check-v1: dune-build-cmake
	@echo "=== CMake v1 structural equivalence check ==="
	$(call check_cmake_v1,step1,$(TV1)/step1/CMakeLists.txt)
	$(call check_cmake_v1,step2,$(TV1)/step2/CMakeLists.txt)
	$(call check_cmake_v1,step2_math,$(TV1)/step2/MathFunctions/CMakeLists.txt)
	$(call check_cmake_v1,step3,$(TV1)/step3/CMakeLists.txt)
	$(call check_cmake_v1,step3_math,$(TV1)/step3/MathFunctions/CMakeLists.txt)
	$(call check_cmake_v1,step4,$(TV1)/step4/CMakeLists.txt)
	$(call check_cmake_v1,step4_math,$(TV1)/step4/MathFunctions/CMakeLists.txt)
	$(call check_cmake_v1,step5,$(TV1)/step5/CMakeLists.txt)
	$(call check_cmake_v1,step5_math,$(TV1)/step5/MathFunctions/CMakeLists.txt)
	$(call check_cmake_v1,step6,$(TV1)/step6/CMakeLists.txt)
	$(call check_cmake_v1,step6_math,$(TV1)/step6/MathFunctions/CMakeLists.txt)
	$(call check_cmake_v1,step6_ctest,$(TV1)/step6/CTestConfig.cmake)
	$(call check_cmake_v1,step7,$(TV1)/step7/CMakeLists.txt)
	$(call check_cmake_v1,step7_math,$(TV1)/step7/MathFunctions/CMakeLists.txt)
	$(call check_cmake_v1,step7,$(TV1)/step8/CMakeLists.txt)
	$(call check_cmake_v1,step8_math,$(TV1)/step8/MathFunctions/CMakeLists.txt)
	$(call check_cmake_v1,step8_table,$(TV1)/step8/MathFunctions/MakeTable.cmake)
	$(call check_cmake_v1,step9,$(TV1)/step9/CMakeLists.txt)
	$(call check_cmake_v1,step10,$(TV1)/step10/CMakeLists.txt)
	$(call check_cmake_v1,step10_math,$(TV1)/step10/MathFunctions/CMakeLists.txt)
	$(call check_cmake_v1,step11,$(TV1)/step11/CMakeLists.txt)
	$(call check_cmake_v1,step11_math,$(TV1)/step11/MathFunctions/CMakeLists.txt)
	$(call check_cmake_v1,step12,$(TV1)/step12/CMakeLists.txt)
	$(call check_cmake_v1,step12_multi,$(TV1)/step12/MultiCPackConfig.cmake)

cmake-check-v2: dune-build-cmake
	@echo "=== CMake v2 structural equivalence check ==="
	$(call check_cmake_v2,v2_mathext,$(TV2)/TutorialProject/MathFunctions/MathExtensions/CMakeLists.txt)
	$(call check_cmake_v2,v2_opadd,$(TV2)/TutorialProject/MathFunctions/MathExtensions/OpAdd/CMakeLists.txt)
	$(call check_cmake_v2,v2_opmul,$(TV2)/TutorialProject/MathFunctions/MathExtensions/OpMul/CMakeLists.txt)
	$(call check_cmake_v2,v2_opsub,$(TV2)/TutorialProject/MathFunctions/MathExtensions/OpSub/CMakeLists.txt)
	$(call check_cmake_v2,v2_mathlogger,$(TV2)/TutorialProject/MathFunctions/MathLogger/CMakeLists.txt)
	$(call check_cmake_v2,v2_maketable,$(TV2)/TutorialProject/MathFunctions/MakeTable/CMakeLists.txt)
	$(call check_cmake_v2,v2_mathfuncs,$(TV2)/TutorialProject/MathFunctions/CMakeLists.txt)
	$(call check_cmake_v2,v2_tutorial_exe,$(TV2)/TutorialProject/Tutorial/CMakeLists.txt)
	$(call check_cmake_v2,v2_tests,$(TV2)/TutorialProject/Tests/CMakeLists.txt)
	$(call check_cmake_v2,v2_root,$(TV2)/TutorialProject/CMakeLists.txt)
	$(call check_cmake_v2,v2_simpletest,$(TV2)/SimpleTest/CMakeLists.txt)

cmake-check:
	@rm -f /tmp/tola-cmake-check-failures
	@$(MAKE) cmake-check-v1
	@$(MAKE) cmake-check-v2
	@bash -c 'if [ -f /tmp/tola-cmake-check-failures ]; then \
	  echo "=== FAILED: $$(cat /tmp/tola-cmake-check-failures | tr "\n" " ")==="; \
	  rm -f /tmp/tola-cmake-check-failures; \
	  exit 1; \
	else \
	  echo "=== All checks passed ==="; \
	fi'

dune-build-cmake:
	@$(DUNE) dune build src/langs/ src/bin/cmake/v1/ 2>/dev/null || true
	@$(DUNE) dune build src/langs/ src/bin/cmake/v2/ 2>/dev/null || true

dune-build-yelu:
	@$(DUNE) dune build src/langs/ src/bin/yelu/ 2>/dev/null

dune-build-yelu-v2:
	@$(DUNE) dune build src/langs/ src/bin/yelu/v2/ 2>/dev/null

# Structural equivalence check for yelu programs against CMakeOnly reference files
# Same gersemi-based normalization as check_cmake, but uses src/bin/yelu/ executables
CMO = vendor/cmake/Tests/CMakeOnly

define check_yelu
	@bash -c '\
	  if [ ! -s "$(2)" ]; then \
	    echo "  SKIP $(1) -> $(2) (empty reference)"; \
	  elif diff -B <($(DUNE) dune exec src/bin/cmake_only/$(1).exe 2>/dev/null | gersemi - 2>/dev/null) <(gersemi $(2) 2>/dev/null) > /dev/null 2>&1; then \
	    echo "  OK   $(1) -> $(2)"; \
	  else \
	    echo "  FAIL $(1) -> $(2)"; \
	    diff -B <($(DUNE) dune exec src/bin/cmake_only/$(1).exe 2>/dev/null | gersemi - 2>/dev/null) <(gersemi $(2) 2>/dev/null) | head -20; \
	    echo "$(1)" >> /tmp/tola-cmake-check-failures; \
	  fi'
endef

define check_yelu_v2
	@bash -c '\
	  if [ ! -s "$(2)" ]; then \
	    echo "  SKIP $(1) -> $(2) (empty reference)"; \
	  elif diff -B <($(DUNE) dune exec src/bin/yelu/v2/$(1).exe 2>/dev/null | gersemi - 2>/dev/null) <(gersemi $(2) 2>/dev/null) > /dev/null 2>&1; then \
	    echo "  OK   $(1) -> $(2)"; \
	  else \
	    echo "  FAIL $(1) -> $(2)"; \
	    diff -B <($(DUNE) dune exec src/bin/yelu/v2/$(1).exe 2>/dev/null | gersemi - 2>/dev/null) <(gersemi $(2) 2>/dev/null) | head -20; \
	    echo "$(1)" >> /tmp/tola-cmake-check-failures; \
	  fi'
endef

yelu-check-v2: dune-build-yelu-v2
	@echo "=== Yelu v2 structural equivalence check ==="
	$(call check_yelu_v2,v2_mathext,$(TV2)/TutorialProject/MathFunctions/MathExtensions/CMakeLists.txt)
	$(call check_yelu_v2,v2_opadd,$(TV2)/TutorialProject/MathFunctions/MathExtensions/OpAdd/CMakeLists.txt)
	$(call check_yelu_v2,v2_opmul,$(TV2)/TutorialProject/MathFunctions/MathExtensions/OpMul/CMakeLists.txt)
	$(call check_yelu_v2,v2_opsub,$(TV2)/TutorialProject/MathFunctions/MathExtensions/OpSub/CMakeLists.txt)
	$(call check_yelu_v2,v2_mathlogger,$(TV2)/TutorialProject/MathFunctions/MathLogger/CMakeLists.txt)
	$(call check_yelu_v2,v2_maketable,$(TV2)/TutorialProject/MathFunctions/MakeTable/CMakeLists.txt)
	$(call check_yelu_v2,v2_mathfuncs,$(TV2)/TutorialProject/MathFunctions/CMakeLists.txt)
	$(call check_yelu_v2,v2_tutorial_exe,$(TV2)/TutorialProject/Tutorial/CMakeLists.txt)
	$(call check_yelu_v2,v2_tests,$(TV2)/TutorialProject/Tests/CMakeLists.txt)
	$(call check_yelu_v2,v2_root,$(TV2)/TutorialProject/CMakeLists.txt)
	$(call check_yelu_v2,v2_simpletest,$(TV2)/SimpleTest/CMakeLists.txt)
	@bash -c 'if [ -f /tmp/tola-cmake-check-failures ]; then \
	  echo "=== FAILED: $$(cat /tmp/tola-cmake-check-failures | tr "\n" " ")==="; \
	  rm -f /tmp/tola-cmake-check-failures; \
	  exit 1; \
	else \
	  echo "=== All checks passed ==="; \
	fi'

cmake-only-check: dune-build-yelu
	@rm -f /tmp/tola-cmake-check-failures
	@echo "=== CMakeOnly structural equivalence check ==="
	$(call check_yelu,target_scope,$(CMO)/TargetScope/CMakeLists.txt)
	$(call check_yelu,target_scope_sub,$(CMO)/TargetScope/Sub/CMakeLists.txt)
	$(call check_yelu,target_scope_sub_sub,$(CMO)/TargetScope/Sub/Sub/CMakeLists.txt)
	$(call check_yelu,target_scope_sib,$(CMO)/TargetScope/Sib/CMakeLists.txt)
	$(call check_yelu,link_interface_loop,$(CMO)/LinkInterfaceLoop/CMakeLists.txt)
	$(call check_yelu,find_path,$(CMO)/find_path/CMakeLists.txt)
	$(call check_yelu,find_library,$(CMO)/find_library/CMakeLists.txt)
	$(call check_yelu,select_library_configurations,$(CMO)/SelectLibraryConfigurations/CMakeLists.txt)
	$(call check_yelu,project_include,$(CMO)/ProjectInclude/CMakeLists.txt)
	$(call check_yelu,project_include,$(CMO)/ProjectIncludeAny/CMakeLists.txt)
	$(call check_yelu,project_include_before,$(CMO)/ProjectIncludeBefore/CMakeLists.txt)
	$(call check_yelu,project_include_before,$(CMO)/ProjectIncludeBeforeAny/CMakeLists.txt)
	@bash -c 'if [ -f /tmp/tola-cmake-check-failures ]; then \
	  echo "=== FAILED: $$(cat /tmp/tola-cmake-check-failures | tr "\n" " ")==="; \
	  rm -f /tmp/tola-cmake-check-failures; \
	  exit 1; \
	else \
	  echo "=== All checks passed ==="; \
	fi'

.PHONY: build build-cmake build-yelu test test-pp test-yc \
        cmake-check cmake-check-v1 cmake-check-v2 yelu-check-v2 cmake-only-check \
        runcmake-compat runcmake-yelu cmake-commands file-api-test build-check \
        coverage test-all dune-build-cmake dune-build-yelu dune-build-yelu-v2 \
        step1 step1_run step2 step3 step4 step5 step6 step7 step8 \
        step9 step10 step11 step12

step1:
	$(DUNE) dune exec src/bin/cmake/v1/step1.exe > $(TV1)/step1/CMakeLists.txt
	rm -rf $(CMAKE_OUT)/step1
	mkdir -p $(CMAKE_OUT)/step1
	cd $(CMAKE_OUT)/step1 && cmake $(OUT_TO_STEP)/step1
	cd $(CMAKE_OUT)/step1 && cmake --build .
	cd $(CMAKE_OUT)/step1 && ./Tutorial 4294967296

step1_run:
	cd $(CMAKE_OUT)/step1 && ./Tutorial 10

step2:
	$(DUNE) dune exec src/bin/cmake/v1/step2.exe > $(TV1)/step2/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step2_math.exe > $(TV1)/step2/MathFunctions/CMakeLists.txt
	rm -rf $(CMAKE_OUT)/step2
	mkdir -p $(CMAKE_OUT)/step2
	cd $(CMAKE_OUT)/step2 && cmake $(OUT_TO_STEP)/step2
	cd $(CMAKE_OUT)/step2 && cmake --build .
	cd $(CMAKE_OUT)/step2 && ./Tutorial 4294967296

step3:
	$(DUNE) dune exec src/bin/cmake/v1/step3.exe > $(TV1)/step3/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step3_math.exe > $(TV1)/step3/MathFunctions/CMakeLists.txt
	rm -rf $(CMAKE_OUT)/step3
	mkdir -p $(CMAKE_OUT)/step3
	cd $(CMAKE_OUT)/step3 && cmake $(OUT_TO_STEP)/step3
	cd $(CMAKE_OUT)/step3 && cmake --build .
	cd $(CMAKE_OUT)/step3 && ./Tutorial 4294967296

step4:
	$(DUNE) dune exec src/bin/cmake/v1/step4.exe > $(TV1)/step4/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step4_math.exe > $(TV1)/step4/MathFunctions/CMakeLists.txt
	rm -rf $(CMAKE_OUT)/step4
	mkdir -p $(CMAKE_OUT)/step4
	cd $(CMAKE_OUT)/step4 && cmake $(OUT_TO_STEP)/step4
	cd $(CMAKE_OUT)/step4 && cmake --build .
	cd $(CMAKE_OUT)/step4 && ./Tutorial 4294967296

step5:
	$(DUNE) dune exec src/bin/cmake/v1/step5.exe > $(TV1)/step5/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step5_math.exe > $(TV1)/step5/MathFunctions/CMakeLists.txt
	rm -rf $(CMAKE_OUT)/step5
	mkdir -p $(CMAKE_OUT)/step5
	cd $(CMAKE_OUT)/step5 && cmake $(OUT_TO_STEP)/step5
	cd $(CMAKE_OUT)/step5 && cmake --build . --config Release
	cd $(CMAKE_OUT)/step5 && cmake --install . --config Release --prefix "Release"
	cd $(CMAKE_OUT)/step5/Release/bin && ./Tutorial 4294967296
	cd $(CMAKE_OUT)/step5 && make test

step6:
	$(DUNE) dune exec src/bin/cmake/v1/step6.exe > $(TV1)/step6/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step6_math.exe > $(TV1)/step6/MathFunctions/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step6_ctest.exe > $(TV1)/step6/CTestConfig.cmake
	rm -rf $(CMAKE_OUT)/step6
	mkdir -p $(CMAKE_OUT)/step6
	cd $(CMAKE_OUT)/step6 && cmake $(OUT_TO_STEP)/step6
	cd $(CMAKE_OUT)/step6 && cmake --build .
	cd $(CMAKE_OUT)/step6 && ctest -VV -D Experimental

step7:
	$(DUNE) dune exec src/bin/cmake/v1/step7.exe > $(TV1)/step7/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step7_math.exe > $(TV1)/step7/MathFunctions/CMakeLists.txt
	rm -rf $(CMAKE_OUT)/step7
	mkdir -p $(CMAKE_OUT)/step7
	cd $(CMAKE_OUT)/step7 && cmake $(OUT_TO_STEP)/step7
	cd $(CMAKE_OUT)/step7 && cmake --build .
	cd $(CMAKE_OUT)/step7 && ./Tutorial 4294967296

step8:
# use step7.exe here
	$(DUNE) dune exec src/bin/cmake/v1/step7.exe > $(TV1)/step8/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step8_math.exe > $(TV1)/step8/MathFunctions/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step8_table.exe > $(TV1)/step8/MathFunctions/MakeTable.cmake
	rm -rf $(CMAKE_OUT)/step8
	mkdir -p $(CMAKE_OUT)/step8
	cd $(CMAKE_OUT)/step8 && cmake $(OUT_TO_STEP)/step8
	cd $(CMAKE_OUT)/step8 && cmake --build .
	cd $(CMAKE_OUT)/step8 && ./Tutorial 8

step9:
# use step8_<math|table>.exe here
	$(DUNE) dune exec src/bin/cmake/v1/step9.exe > $(TV1)/step9/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step8_math.exe > $(TV1)/step9/MathFunctions/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step8_table.exe > $(TV1)/step9/MathFunctions/MakeTable.cmake
	rm -rf $(CMAKE_OUT)/step9
	mkdir -p $(CMAKE_OUT)/step9
	cd $(CMAKE_OUT)/step9 && cmake $(OUT_TO_STEP)/step9
	cd $(CMAKE_OUT)/step9 && cmake --build .
	cd $(CMAKE_OUT)/step9 && cpack -G ZIP -C Debug
	cd $(CMAKE_OUT)/step9 && cpack --config CPackSourceConfig.cmake

step10:
	$(DUNE) dune exec src/bin/cmake/v1/step10.exe > $(TV1)/step10/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step10_math.exe > $(TV1)/step10/MathFunctions/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step8_table.exe > $(TV1)/step10/MathFunctions/MakeTable.cmake
	rm -rf $(CMAKE_OUT)/step10
	mkdir -p $(CMAKE_OUT)/step10
	cd $(CMAKE_OUT)/step10 && cmake $(OUT_TO_STEP)/step10
	cd $(CMAKE_OUT)/step10 && cmake --build .
	cd $(CMAKE_OUT)/step10 && ./Tutorial 8

step11:
	$(DUNE) dune exec src/bin/cmake/v1/step11.exe > $(TV1)/step11/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step11_config.exe > $(TV1)/step11/Config.cmake.in
	$(DUNE) dune exec src/bin/cmake/v1/step11_math.exe > $(TV1)/step11/MathFunctions/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step8_table.exe > $(TV1)/step11/MathFunctions/MakeTable.cmake
	rm -rf $(CMAKE_OUT)/step11
	mkdir -p $(CMAKE_OUT)/step11
	cd $(CMAKE_OUT)/step11 && cmake $(OUT_TO_STEP)/step11
	cd $(CMAKE_OUT)/step11 && cmake --build .
	cd $(CMAKE_OUT)/step11 && ./Tutorial 8

step12:
	$(DUNE) dune exec src/bin/cmake/v1/step12_multi.exe > $(TV1)/step12/MultiCPackConfig.cmake
	$(DUNE) dune exec src/bin/cmake/v1/step12.exe > $(TV1)/step12/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step12_math.exe > $(TV1)/step12/MathFunctions/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step11_math.exe > $(TV1)/step12/MathFunctions/CMakeLists.txt
	$(DUNE) dune exec src/bin/cmake/v1/step8_table.exe > $(TV1)/step12/MathFunctions/MakeTable.cmake
	rm -rf $(CMAKE_OUT)/step12
	mkdir -p $(CMAKE_OUT)/step12
	mkdir -p $(CMAKE_OUT)/step12/debug
	cd $(CMAKE_OUT)/step12/debug && cmake -DCMAKE_BUILD_TYPE=Debug $(OUT_TO_STEP)/step12
	cd $(CMAKE_OUT)/step12/debug && cmake --build .
	cd $(CMAKE_OUT)/step12/debug && ./Tutoriald 8
	mkdir -p $(CMAKE_OUT)/step12/release
	cd $(CMAKE_OUT)/step12/release && cmake -DCMAKE_BUILD_TYPE=Release $(OUT_TO_STEP)/step12
	cd $(CMAKE_OUT)/step12/release && cmake --build .
	cd $(CMAKE_OUT)/step12/release && ./Tutorial 9
	mkdir -p $(CMAKE_OUT)/step12/cpack
	cd $(CMAKE_OUT)/step12 && cpack --config ../../$(TV1)/step12/MultiCPackConfig.cmake
