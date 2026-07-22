#---------------------------------------------------------------------------------
# cemod-sdk: reusable build/verify/package machinery for Wii U .cemod mods.
#
# Usage (variables MUST be set BEFORE this file is included -- GNU Make
# expands wildcard()/foreach() calls and rule prerequisites at parse time,
# so CEMOD_* has to already have its final value by the time this file's
# rules are read):
#
#   PROJECT_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
#   CEMOD_NAME      := mcwiiu-client
#   CEMOD_SOURCES   := src
#   CEMOD_MANIFEST  := manifest.json
#   CEMOD_SDK_ROOT  := /path/to/cemod-sdk
#   include $(CEMOD_SDK_ROOT)/cemod.mk
#
# See cemod-sdk/README.md for the full variable reference and extension
# hooks (CEMOD_EXTRA_CFLAGS, CEMOD_EXTRA_LIBS, CEMOD_EXTRA_BUILD_DEPS, ...).
#---------------------------------------------------------------------------------
.SUFFIXES:

CEMOD_SDK_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

ifeq ($(strip $(PROJECT_ROOT)),)
$(error "PROJECT_ROOT must be set before including cemod.mk")
endif
ifeq ($(strip $(CEMOD_NAME)),)
$(error "CEMOD_NAME must be set before including cemod.mk")
endif

#---------------------------------------------------------------------------------
# Project-facing configuration (override before the include line)
#---------------------------------------------------------------------------------
CEMOD_SOURCES         ?= src
CEMOD_INCLUDES        ?= include
CEMOD_DATA            ?=
CEMOD_MANIFEST        ?= $(PROJECT_ROOT)/manifest.json
CEMOD_TARGET          ?= $(CEMOD_NAME)
CEMOD_PROJECT_MAKEFILE ?= $(PROJECT_ROOT)/Makefile

CEMOD_EXTRA_DEFINES       ?=
CEMOD_EXTRA_CFLAGS        ?=
CEMOD_EXTRA_CXXFLAGS      ?=
CEMOD_EXTRA_LDFLAGS       ?=
CEMOD_EXTRA_LIBS_GROUP    ?=
CEMOD_EXTRA_LIBS          ?=
CEMOD_EXTRA_LIBDIRS       ?=
CEMOD_EXCLUDE_CPPFILES    ?=
CEMOD_EXTRA_BUILD_DEPS    ?=
CEMOD_EXTRA_ELF_DEPS      ?=

# The stock devkitPPC libraries are built for 32-bit wchar_t. Some Wii U
# titles (e.g. Minecraft) use a 16-bit wchar_t ABI, so Docker builds a
# matching newlib/libstdc++ under this prefix. Set USE_SYSTEM_STDLIB=1 only
# for linker bring-up; such a build is rejected by verify-wchar and must not
# be distributed.
CEMOD_STDLIB_ROOT     ?= $(DEVKITPRO)/mcwiiu-stdlib
CEMOD_STDLIB_VERSION  ?= 14.2.0
CEMOD_STDLIB_ROOT_PATH ?= /vol/external01/$(CEMOD_NAME)
CEMOD_STDLIB_SELF_TEST ?= 0
CEMOD_GCC             ?= $(DEVKITPRO)/mcwiiu-gcc

#---------------------------------------------------------------------------------
OUT_ROOT      := $(PROJECT_ROOT)/out
BUILD_ROOT    := $(OUT_ROOT)/build
DIST_ROOT     := $(OUT_ROOT)/dist
PACKAGE_PATH  := $(DIST_ROOT)/$(CEMOD_NAME).cemod

# docker-build/docker-install run entirely inside the Docker image built
# from cemod-sdk and never need a local devkitPPC/devkitPRO checkout, so
# skip the toolchain checks when that's the only thing being requested.
CEMOD_TOOLCHAIN_GOALS := $(filter-out docker-build docker-install,$(if $(MAKECMDGOALS),$(MAKECMDGOALS),all))
ifneq ($(strip $(CEMOD_TOOLCHAIN_GOALS)),)
ifeq ($(strip $(DEVKITPPC)),)
$(error "Please set DEVKITPPC in your environment. export DEVKITPPC=<path to>devkitPPC")
endif
ifeq ($(strip $(DEVKITPRO)),)
$(error "Please set DEVKITPRO in your environment. export DEVKITPRO=<path to>devkitPRO")
endif
endif
export LIBOGC_INC := $(DEVKITPRO)/libogc/include
export LIBOGC_LIB := $(DEVKITPRO)/libogc/lib/wii
export PORTLIBS    := $(DEVKITPRO)/portlibs/ppc

# Built from the same GCC 14.2/devkitPro sources as stock devkitPPC, with
# native PowerPC TLS disabled so thread_local uses gthread-backed emulated
# TLS. See infra/docker/build-short-wchar-stdlib.sh.
ifneq ($(strip $(CEMOD_TOOLCHAIN_GOALS)),)
ifeq ($(wildcard $(CEMOD_GCC)/bin/powerpc-eabi-g++),)
$(error "Missing codecave-safe GCC: $(CEMOD_GCC). Build through docker-build.sh")
endif
endif
CEMOD_GCC_EXEC := $(CEMOD_GCC)/libexec/gcc/powerpc-eabi/$(CEMOD_STDLIB_VERSION)
ifneq ($(strip $(CEMOD_TOOLCHAIN_GOALS)),)
ifeq ($(wildcard $(CEMOD_GCC_EXEC)/cc1plus),)
$(error "Missing codecave-safe cc1plus: $(CEMOD_GCC_EXEC)")
endif
endif
export PATH := $(DEVKITPPC)/bin:$(PORTLIBS)/bin:$(PATH)

PREFIX := powerpc-eabi-
PYTHON ?= python3

export AS      := $(PREFIX)as
export CC      := $(PREFIX)gcc
export CXX     := $(PREFIX)g++
export AR      := $(PREFIX)ar
export OBJCOPY := $(PREFIX)objcopy

#---------------------------------------------------------------------------------
# TARGET is the name of the output
# BUILD is the directory where object files & intermediate files will be placed
# SOURCES is a list of directories containing source code
# INCLUDES is a list of directories containing extra header files
#---------------------------------------------------------------------------------
TARGET       := $(CEMOD_TARGET)
BUILD        := $(BUILD_ROOT)/$(TARGET)
ELF_PATH     := $(BUILD)/$(TARGET).elf
DBG_ELF_PATH := $(BUILD)/$(TARGET)_dbg.elf
# Merge rather than overwrite: third-party *.mk helpers included by the
# project before cemod.mk (libhookevent.mk, libcemuextend.mk, ...) commonly
# do `SOURCES += ...` / `INCLUDES += ...` / `DATA += ...` against these plain
# names. Preserve those contributions.
SOURCES      := $(CEMOD_SOURCES) $(SOURCES)
DATA         := $(CEMOD_DATA) $(DATA)
INCLUDES     := $(CEMOD_INCLUDES) $(INCLUDES)

# Bare aliases kept for compatibility with third-party *.mk helpers (e.g.
# libmcwiiu-runtime.mk) that reference these exact names in recipe bodies.
MCWIIU_GCC := $(CEMOD_GCC)
STDLIB_ROOT_PATH := $(CEMOD_STDLIB_ROOT_PATH)

ifeq ($(USE_SYSTEM_STDLIB),1)
STDLIB_ROOT := $(DEVKITPPC)/powerpc-eabi
else
STDLIB_ROOT := $(CEMOD_STDLIB_ROOT)
endif
STDLIB_VERSION := $(CEMOD_STDLIB_VERSION)

RUNTIME_DEFINES := -DMCWIIU_STDLIB_ROOT=\"$(CEMOD_STDLIB_ROOT_PATH)\" \
	-DSTDLIB_SELF_TEST=$(CEMOD_STDLIB_SELF_TEST) -D__COMPILE_CEMU__ $(CEMOD_EXTRA_DEFINES)
STDLIB_CXX_INCLUDES := -nostdinc++ \
	-isystem $(STDLIB_ROOT)/powerpc-eabi/include \
	-isystem $(STDLIB_ROOT)/include/c++/$(STDLIB_VERSION) \
	-isystem $(STDLIB_ROOT)/include/c++/$(STDLIB_VERSION)/powerpc-eabi
STDLIB_C_INCLUDES := -isystem $(STDLIB_ROOT)/powerpc-eabi/include
ifeq ($(USE_SYSTEM_STDLIB),1)
STDLIB_CXX_INCLUDES :=
STDLIB_C_INCLUDES :=
endif

#---------------------------------------------------------------------------------
# options for code generation
#---------------------------------------------------------------------------------
CFLAGS   := -B$(CEMOD_GCC_EXEC)/ $(STDLIB_C_INCLUDES) -std=gnu17 -mrvl -mcpu=750 -meabi -mhard-float -msdata=none \
	          -fno-fast-math -fshort-wchar -fPIC -finline -fdata-sections -ffunction-sections \
	          -Os -D_GNU_SOURCE -D__WIIU__ $(RUNTIME_DEFINES) $(CEMOD_EXTRA_CFLAGS) $(INCLUDE)
CXXFLAGS := -B$(CEMOD_GCC_EXEC)/ $(STDLIB_CXX_INCLUDES) -std=gnu++20 -mrvl -mcpu=750 -meabi -mhard-float -msdata=none \
	          -fno-fast-math -fshort-wchar -fPIC -finline -fdata-sections -ffunction-sections \
	          -fexceptions -frtti -fuse-cxa-atexit -funwind-tables -fasynchronous-unwind-tables \
	          -Os -D_GNU_SOURCE -D__WIIU__ $(RUNTIME_DEFINES) $(CEMOD_EXTRA_CXXFLAGS) $(INCLUDE)
ASFLAGS := -mregnames
LDFLAGS := -nostartfiles -nodefaultlibs -shared -Wl,-Bsymbolic,-z,notext \
	       -Wl,-Map,$(notdir $@).map,--gc-sections $(CEMOD_EXTRA_LDFLAGS) \
	       -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc -Wl,--wrap=memalign -Wl,--wrap=free -Wl,--wrap=mallinfo -Wl,--wrap=malloc_stats -Wl,--wrap=mallopt -Wl,--wrap=malloc_usable_size -Wl,--wrap=valloc -Wl,--wrap=pvalloc -Wl,--wrap=malloc_trim -Wl,--wrap=_malloc_r -Wl,--wrap=_calloc_r -Wl,--wrap=_realloc_r -Wl,--wrap=_memalign_r -Wl,--wrap=_free_r -Wl,--wrap=_mallinfo_r -Wl,--wrap=_malloc_stats_r -Wl,--wrap=_mallopt_r -Wl,--wrap=_malloc_usable_size_r -Wl,--wrap=_valloc_r -Wl,--wrap=_pvalloc_r -Wl,--wrap=_malloc_trim_r

#---------------------------------------------------------------------------------
Q := @
MAKEFLAGS += --no-print-directory
#---------------------------------------------------------------------------------
# any extra libraries we wish to link with the project
#---------------------------------------------------------------------------------
LIBS := -lwut -L$(STDLIB_ROOT)/lib \
	-Wl,--start-group $(CEMOD_EXTRA_LIBS_GROUP) -lstdc++ -lsupc++ -lc -lm -lsysbase -lgcc -Wl,--end-group \
	$(CEMOD_EXTRA_LIBS)

#---------------------------------------------------------------------------------
# list of directories containing libraries, this must be the top level containing
# include and lib
#---------------------------------------------------------------------------------
LIBDIRS := $(PROJECT_ROOT) \
	$(DEVKITPPC)/lib  \
	$(wildcard $(DEVKITPPC)/lib/gcc/powerpc-eabi/*) \
	$(DEVKITPRO)/wut \
	$(PORTLIBS) \
	$(CEMOD_EXTRA_LIBDIRS)

#---------------------------------------------------------------------------------
# no real need to edit anything past this point unless you need to add additional
# rules for different file extensions
#---------------------------------------------------------------------------------
.PHONY: $(BUILD) build all clean install package print-project-config \
	verify-package verify-wchar

ifneq ($(abspath $(BUILD)),$(abspath $(CURDIR)))
#---------------------------------------------------------------------------------
export PROJECTDIR := $(PROJECT_ROOT)
export OUTPUT := $(BUILD)/$(TARGET)
resolve-project-path = $(if $(filter /%,$(1)),$(1),$(PROJECT_ROOT)/$(1))
export VPATH := $(foreach dir,$(SOURCES),$(call resolve-project-path,$(dir))) \
				$(foreach dir,$(DATA),$(call resolve-project-path,$(dir)))
export DEPSDIR := $(BUILD)

#---------------------------------------------------------------------------------
# automatically build a list of object files for our project
#---------------------------------------------------------------------------------
CFILES   := $(foreach dir,$(SOURCES),$(notdir $(wildcard $(call resolve-project-path,$(dir))/*.c)))
CPPFILES := $(foreach dir,$(SOURCES),$(notdir $(wildcard $(call resolve-project-path,$(dir))/*.cpp)))
CPPFILES := $(filter-out $(CEMOD_EXCLUDE_CPPFILES),$(CPPFILES))
sFILES   := $(foreach dir,$(SOURCES),$(notdir $(wildcard $(call resolve-project-path,$(dir))/*.s)))
SFILES   := $(foreach dir,$(SOURCES),$(notdir $(wildcard $(call resolve-project-path,$(dir))/*.S)))
BINFILES := $(foreach dir,$(DATA),$(notdir $(wildcard $(call resolve-project-path,$(dir))/*.*)))
TTFFILES := $(foreach dir,$(DATA),$(notdir $(wildcard $(call resolve-project-path,$(dir))/*.ttf)))
PNGFILES := $(foreach dir,$(SOURCES),$(notdir $(wildcard $(call resolve-project-path,$(dir))/*.png)))

#---------------------------------------------------------------------------------
# use CXX for linking C++ projects, CC for standard C
#---------------------------------------------------------------------------------
ifeq ($(strip $(CPPFILES)),)
	export LD := $(CC)
else
	export LD := $(CXX)
endif

export OFILES := $(CPPFILES:.cpp=.o) $(CFILES:.c=.o) \
				  $(sFILES:.s=.o) $(SFILES:.S=.o) \
				  $(PNGFILES:.png=.png.o) $(addsuffix .o,$(BINFILES))

#---------------------------------------------------------------------------------
# build a list of include paths
#---------------------------------------------------------------------------------
export INCLUDE := $(foreach dir,$(INCLUDES),-I$(call resolve-project-path,$(dir))) \
				   $(foreach dir,$(LIBDIRS),-I$(dir)/include) \
				   -I$(BUILD) -I$(LIBOGC_INC) \
				   -I$(PORTLIBS)/include -I$(PORTLIBS)/include/freetype2

#---------------------------------------------------------------------------------
# build a list of library paths
#---------------------------------------------------------------------------------
export LIBPATHS := $(foreach dir,$(LIBDIRS),-L$(dir)/lib) \
					-L$(LIBOGC_LIB) -L$(PORTLIBS)/lib

#---------------------------------------------------------------------------------
$(BUILD): $(CEMOD_EXTRA_BUILD_DEPS)
	@mkdir -p "$@"
	@$(MAKE) --no-print-directory -C "$@" -f "$(CEMOD_PROJECT_MAKEFILE)" "$(ELF_PATH)"

build: $(BUILD)

#---------------------------------------------------------------------------------
clean:
	@echo clean ...
	@rm -rf "$(OUT_ROOT)"

print-project-config:
	@printf '%s\n' \
		'PROJECT_NAME=$(CEMOD_NAME)' \
		'TARGET=$(TARGET)' \
		'BUILD=$(BUILD)' \
		'ELF_PATH=$(ELF_PATH)' \
		'PACKAGE_PATH=$(PACKAGE_PATH)'

all: $(BUILD)

package: all
	@mkdir -p "$(DIST_ROOT)"
	@$(PYTHON) "$(CEMOD_SDK_ROOT)/tools/package_cemod.py" --manifest "$(CEMOD_MANIFEST)" --elf "$(ELF_PATH)" \
		--output "$(PACKAGE_PATH)"
	@$(MAKE) verify-package
	@echo "Packaged $(PACKAGE_PATH)"

verify-package:
	@$(PYTHON) "$(CEMOD_SDK_ROOT)/tools/verify_cemod.py" --package "$(PACKAGE_PATH)" \
		--readelf "$(PREFIX)readelf" --nm "$(PREFIX)nm" --objdump "$(PREFIX)objdump"

install: package
	@test -n "$(CEMU_DATA_DIR)" || { echo 'Set CEMU_DATA_DIR to the Cemu data directory.' >&2; exit 1; }
	@PROJECT_ROOT="$(PROJECT_ROOT)" CEMOD_NAME="$(CEMOD_NAME)" \
		sh "$(CEMOD_SDK_ROOT)/infra/docker/install-cemu-pack.sh" "$(CEMU_DATA_DIR)"

ifeq ($(USE_SYSTEM_STDLIB),)
$(BUILD): $(STDLIB_ROOT)/.wchar16

$(STDLIB_ROOT)/.wchar16:
	@echo "Missing 16-bit wchar_t stdlib: $@" >&2
	@echo "Build through docker-build.sh or set USE_SYSTEM_STDLIB=1 for diagnostics only." >&2
	@false
endif

ifeq ($(USE_SYSTEM_STDLIB),1)
verify-wchar:
	@echo "USE_SYSTEM_STDLIB=1 uses libraries with an incompatible wchar_t ABI." >&2
	@false
else
verify-wchar:
	@mkdir -p $(BUILD)
	@printf '%s\n' '#include <string>' 'static_assert(sizeof(wchar_t) == 2);' \
		'static_assert(sizeof(std::wstring::value_type) == 2);' \
		'int main() { std::wstring s = L"Wii U"; return s.size() != 5; }' | \
		$(CXX) $(CXXFLAGS) -x c++ -c -o $(BUILD)/verify_wchar.o -
endif
#---------------------------------------------------------------------------------
else

DEPENDS := $(OFILES:.o=.d)

#---------------------------------------------------------------------------------
# main targets
#---------------------------------------------------------------------------------
$(OUTPUT).elf: $(OFILES) | $(CEMOD_EXTRA_ELF_DEPS)

#---------------------------------------------------------------------------------
%.elf: $(CEMOD_SDK_ROOT)/config/link.ld $(OFILES)
	@echo "Linking... $(TARGET).elf"
	$(Q)$(LD) -T $^ $(LDFLAGS) -o "$(DBG_ELF_PATH)" $(LIBPATHS) $(LIBS)
	$(Q)$(OBJCOPY) -R .comment -R .gnu.attributes "$(DBG_ELF_PATH)" "$@"
	$(Q)$(PYTHON) "$(CEMOD_SDK_ROOT)/tools/normalize_relocations.py" "$@"

#---------------------------------------------------------------------------------
%.a:
#---------------------------------------------------------------------------------
	@echo $(notdir $@)
	@rm -f $@
	@$(AR) -rc $@ $^

#---------------------------------------------------------------------------------
%.o: %.cpp
	@echo $(notdir $<)
	@$(CXX) -MMD -MP -MF $(DEPSDIR)/$*.d $(CXXFLAGS) -c $< -o $@ $(ERROR_FILTER)

#---------------------------------------------------------------------------------
%.o: %.c
	@echo $(notdir $<)
	@$(CC) -MMD -MP -MF $(DEPSDIR)/$*.d $(CFLAGS) -c $< -o $@ $(ERROR_FILTER)

#---------------------------------------------------------------------------------
%.o: %.S
	@echo $(notdir $<)
	@$(CC) -MMD -MP -MF $(DEPSDIR)/$*.d -x assembler-with-cpp $(ASFLAGS) $(INCLUDE) -c $< -o $@ $(ERROR_FILTER)

#---------------------------------------------------------------------------------
%.png.o : %.png
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

#---------------------------------------------------------------------------------
%.jpg.o : %.jpg
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

#---------------------------------------------------------------------------------
%.ttf.o : %.ttf
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

#---------------------------------------------------------------------------------
%.bin.o : %.bin
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

%.gsh.o : %.gsh
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

#---------------------------------------------------------------------------------
%.wav.o : %.wav
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

#---------------------------------------------------------------------------------
%.mp3.o : %.mp3
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

#---------------------------------------------------------------------------------
%.ogg.o : %.ogg
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

-include $(DEPENDS)

#---------------------------------------------------------------------------------
endif
#---------------------------------------------------------------------------------

#---------------------------------------------------------------------------------
# Docker: reproducible build using the short-wchar toolchain. Requires the
# project to provide compose.yaml (context ".") that builds
# infra/docker/Dockerfile from this SDK with an "sdk" additional context
# pointing at $(CEMOD_SDK_ROOT)/infra/docker, and to set DEVKITPPC_ARCHIVE /
# DEVKITPPC_SHA256 (see cemod-sdk/README.md).
#---------------------------------------------------------------------------------
docker-build:
	@PROJECT_ROOT="$(PROJECT_ROOT)" CEMOD_SDK_ROOT="$(CEMOD_SDK_ROOT)" \
		DEVKITPPC_ARCHIVE="$(DEVKITPPC_ARCHIVE)" DEVKITPPC_SHA256="$(DEVKITPPC_SHA256)" \
		CEMOD_PREBUILD_CHECK="$(CEMOD_PREBUILD_CHECK)" CEMOD_EXTRA_VERIFY="$(CEMOD_EXTRA_VERIFY)" \
		sh "$(CEMOD_SDK_ROOT)/infra/docker/docker-build.sh" $(CEMOD_DOCKER_ARGS)

docker-install:
	@$(MAKE) docker-build CEMOD_DOCKER_ARGS="--install $(CEMU_DATA_DIR)"

.PHONY: docker-build docker-install
