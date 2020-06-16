.SUFFIXES:
.DEFAULT_GOAL := all

export PATH := $(shell toolchain/use-it.sh):$(PATH)
export PATH := $(shell toolbox/use-it.sh):$(PATH)

ifeq (, $(shell which inkscape))
$(error "No inkscape in PATH, consider installing it")
endif

DIRECTORY_GUARD=@mkdir -p $(@D)

BUILD_ARCH?=i686
BUILD_CONFIG?=debug
BUILD_SYSTEM?=skift

BUILD_TARGET=$(BUILD_CONFIG)-$(BUILD_ARCH)-$(BUILD_SYSTEM)
BUILD_GITREF=$(shell git rev-parse --abbrev-ref HEAD || echo unknown)@$(shell git rev-parse --short HEAD || echo unknown)
BUILD_UNAME=$(shell uname -s -o -m -r)
BUILD_DIRECTORY=$(shell pwd)/build

SYSROOT=$(BUILD_DIRECTORY)/sysroot
BOOTROOT=$(BUILD_DIRECTORY)/bootroot

BUILD_DIRECTORY_LIBS=$(SYSROOT)/lib
BUILD_DIRECTORY_INCLUDE=$(SYSROOT)/lib/include
BUILD_DIRECTORY_APPS=$(SYSROOT)/bin
BUILD_DIRECTORY_UTILS=$(SYSROOT)/bin

# --- Configs -------------------------------------------- #

QEMU=qemu-system-x86_64
QEMUFLAGS=-m 128M -serial mon:stdio -rtc base=localtime -nic user,model=virtio-net-pci

CC:=i686-pc-skift-gcc
CFLAGS:= \
	-O2 \
	-std=gnu11 \
	-MD \
	\
	-Wall \
	-Wextra  \
	-Wc++-compat \
	-Werror \
	\
	-I. \
	-Iapplications \
	-Ilibraries \
	-Ilibraries/libcompat \
	\
	-D__BUILD_ARCH__=\""$(BUILD_ARCH)"\" \
	-D__BUILD_CONFIG__=\""$(BUILD_CONFIG)"\" \
	-D__BUILD_SYSTEM__=\""$(BUILD_SYSTEM)"\" \
	-D__BUILD_TARGET__=\""$(BUILD_TARGET)"\" \
	-D__BUILD_GITREF__=\""$(BUILD_GITREF)"\" \
	-D__BUILD_UNAME__=\""$(BUILD_UNAME)"\"

LD:=i686-pc-skift-ld
LDFLAGS:=

AR:=i686-pc-skift-ar
ARFLAGS:=rcs

AS=nasm
ASFLAGS=-f elf32

# --- Kernel --------------------------------------------- #

KERNEL_SOURCES = \
	$(wildcard kernel/*.c) \
	$(wildcard kernel/*/*.c) \
	$(wildcard arch/x86/*.c)

KERNEL_ASSEMBLY_SOURCES = \
	$(wildcard kernel/*.s) \
	$(wildcard kernel/*/*.s) \
	$(wildcard arch/*/*.s)

KERNEL_LIBRARIES_SOURCES = \
	$(wildcard libraries/libfile/*.c) \
	$(wildcard libraries/libjson/*.c) \
	$(wildcard libraries/libmath/*.c) \
	$(wildcard libraries/libmath/*/*.c) \
	$(wildcard libraries/libsystem/*.c) \
	$(wildcard libraries/libsystem/io/*.c) \
	$(wildcard libraries/libsystem/unicode/*.c) \
	$(wildcard libraries/libsystem/process/*.c) \
	$(wildcard libraries/libsystem/utils/*.c)

KERNEL_BINARY = $(BOOTROOT)/boot/kernel.bin

KERNEL_OBJECTS = \
	$(patsubst %.c, $(BUILD_DIRECTORY)/%.o, $(KERNEL_SOURCES)) \
	$(patsubst %.s, $(BUILD_DIRECTORY)/%.s.o, $(KERNEL_ASSEMBLY_SOURCES)) \
	$(patsubst libraries/%.c, $(BUILD_DIRECTORY)/kernel/%.o, $(KERNEL_LIBRARIES_SOURCES))

OBJECTS += $(KERNEL_OBJECTS)

$(BUILD_DIRECTORY)/kernel/%.o: libraries/%.c
	$(DIRECTORY_GUARD)
	@echo [KERNEL] [CC] $<
	@$(CC) $(CFLAGS) -ffreestanding -nostdlib -c -o $@ $<

$(BUILD_DIRECTORY)/kernel/%.o: kernel/%.c
	$(DIRECTORY_GUARD)
	@echo [KERNEL] [CC] $<
	@$(CC) $(CFLAGS) -ffreestanding -nostdlib -c -o $@ $<

$(BUILD_DIRECTORY)/arch/%.o: arch/%.c
	$(DIRECTORY_GUARD)
	@echo [KERNEL] [CC] $<
	@$(CC) $(CFLAGS) -ffreestanding -nostdlib -c -o $@ $<

$(BUILD_DIRECTORY)/arch/%.s.o: arch/%.s
	$(DIRECTORY_GUARD)
	@echo [KERNEL] [AS] $<
	@$(AS) $(ASFLAGS) $^ -o $@

$(KERNEL_BINARY): $(KERNEL_OBJECTS)
	$(DIRECTORY_GUARD)
	@echo [KERNEL] [LD] $(KERNEL_BINARY)
	@$(CC) $(LDFLAGS) -T arch/x86/link.ld -o $@ -ffreestanding $^ -nostdlib -lgcc

# --- CRTs ----------------------------------------------- #

CRTS= \
	$(BUILD_DIRECTORY_LIBS)/crt0.o \
	$(BUILD_DIRECTORY_LIBS)/crti.o \
	$(BUILD_DIRECTORY_LIBS)/crtn.o

$(BUILD_DIRECTORY_LIBS)/crt0.o: libraries/crt0.s
	$(DIRECTORY_GUARD)
	@echo [AS] $^
	@$(AS) $(ASFLAGS) -o $@ $^

$(BUILD_DIRECTORY_LIBS)/crti.o: libraries/crti.s
	$(DIRECTORY_GUARD)
	@echo [AS] $^
	@$(AS) $(ASFLAGS) -o $@ $^

$(BUILD_DIRECTORY_LIBS)/crtn.o: libraries/crtn.s
	$(DIRECTORY_GUARD)
	@echo [AS] $^
	@$(AS) $(ASFLAGS) -o $@ $^

# --- Libraries ------------------------------------------ #

ABI_HEADERS = \
	$(wildcard libraries/abi/*.h) \
	$(wildcard libraries/abi/*/*.h)
HEADERS += $(patsubst libraries/%, $(BUILD_DIRECTORY_INCLUDE)/%, $(ABI_HEADERS))

define LIB_TEMPLATE =

$(1)_ARCHIVE = $(BUILD_DIRECTORY_LIBS)/lib$($(1)_NAME).a
$(1)_SOURCES = \
	$$(wildcard libraries/lib$($(1)_NAME)/*.c) \
	$$(wildcard libraries/lib$($(1)_NAME)/*/*.c)

$(1)_OBJECTS = $$(patsubst libraries/%.c, $(BUILD_DIRECTORY)/%.o, $$($(1)_SOURCES))

$(1)_HEADERS = \
	$$(wildcard libraries/lib$($(1)_NAME)/*.h) \
	$$(wildcard libraries/lib$($(1)_NAME)/*/*.h)

OBJECTS += $$($(1)_OBJECTS)
ICONS += $$($(1)_ICONS)

ifneq ($(1), COMPAT)
HEADERS += $$(patsubst libraries/%, $(BUILD_DIRECTORY_INCLUDE)/%, $$($(1)_HEADERS))
else
HEADERS += $$(patsubst libraries/libcompat/%, $(BUILD_DIRECTORY_INCLUDE)/%, $$($(1)_HEADERS))
endif

$$($(1)_ARCHIVE): $$($(1)_OBJECTS)
	$$(DIRECTORY_GUARD)
	@echo [LIB$(1)] [AR] $$@
	@$(AR) $(ARFLAGS) $$@ $$^

LIBS_OBJECTS  += $$($(1)_OBJECTS)
LIBS_ARCHIVES += $$($(1)_ARCHIVE)

$(BUILD_DIRECTORY)/lib$($(1)_NAME)/%.o: libraries/lib$($(1)_NAME)/%.c
	$$(DIRECTORY_GUARD)
	@echo [LIB$(1)] [CC] $$<
	@$(CC) $(CFLAGS) $($(1)_CFLAGS) -c -o $$@ $$<

endef

$(BUILD_DIRECTORY_INCLUDE)/%.h: libraries/%.h
	$(DIRECTORY_GUARD)
	cp $< $@

$(BUILD_DIRECTORY_INCLUDE)/%.h: libraries/libcompat/%.h
	$(DIRECTORY_GUARD)
	cp $< $@

-include libraries/*/.build.mk
$(foreach lib, $(LIBS), $(eval $(call LIB_TEMPLATE,$(lib))))

# --- Coreutils ------------------------------------------ #

define UTIL_TEMPLATE =

$(1)_BINARY  = $(BUILD_DIRECTORY_UTILS)/$($(1)_NAME)
$(1)_SOURCE  = coreutils/$($(1)_NAME).c
$(1)_OBJECT  = $$(patsubst coreutils/%.c, $$(BUILD_DIRECTORY)/%.o, $$($(1)_SOURCE))

UTILS_BINARIES += $$($(1)_BINARY)

OBJECTS += $$($(1)_OBJECT)

$$($(1)_BINARY): $$($(1)_OBJECT) $$(patsubst %, $$(BUILD_DIRECTORY_LIBS)/lib%.a, $$($(1)_LIBS) system) $(CRTS)
	$$(DIRECTORY_GUARD)
	@echo [$(1)] [LD] $($(1)_NAME)
	@$(CC) $(LDFLAGS) -o $$@ $$($(1)_OBJECT) $$(patsubst %, -l%, $$($(1)_LIBS))

$$($(1)_OBJECT): $$($(1)_SOURCE)
	$$(DIRECTORY_GUARD)
	@echo [$(1)] [CC] $$<
	@$(CC) $(CFLAGS) -c -o $$@ $$<

endef

-include coreutils/.build.mk
$(foreach util, $(UTILS), $(eval $(call UTIL_TEMPLATE,$(util))))

# --- Applications --------------------------------------- #

define APP_TEMPLATE =

$(1)_BINARY  = $(BUILD_DIRECTORY_APPS)/$($(1)_NAME)
$(1)_SOURCES = $$(wildcard applications/$($(1)_NAME)/*.c) \
			   $$(wildcard applications/$($(1)_NAME)/*/*.c)

$(1)_OBJECTS = $$(patsubst applications/%.c, $$(BUILD_DIRECTORY)/%.o, $$($(1)_SOURCES))

OBJECTS += $$($(1)_OBJECTS)
ICONS += $$($(1)_ICONS)

$$($(1)_BINARY): $$($(1)_OBJECTS) $$(patsubst %, $$(BUILD_DIRECTORY_LIBS)/lib%.a, $$($(1)_LIBS) system) $(CRTS)
	$$(DIRECTORY_GUARD)
	@echo [$(1)] [LD] $($(1)_NAME)
	@$(CC) $(LDFLAGS) -o $$@ $$($(1)_OBJECTS) $$(patsubst %, -l%, $$($(1)_LIBS))

APPS_OBJECTS  += $$($(1)_OBJECTS)
APPS_BINARIES += $$($(1)_BINARY)

$$(BUILD_DIRECTORY)/$$($(1)_NAME)/%.o: applications/$$($(1)_NAME)/%.c
	$$(DIRECTORY_GUARD)
	@echo [$(1)] [CC] $$<
	@$(CC) $(CFLAGS) -c -o $$@ $$<

endef

-include applications/*/.build.mk
$(foreach app, $(APPS), $(eval $(call APP_TEMPLATE,$(app))))

# --- Icons ---------------------------------------------- #

ICONS_SVGs = $(patsubst %, thirdparty/icons/svg/%.svg, $(ICONS))

ICONS_AT_18PX = $(patsubst thirdparty/icons/svg/%.svg, $(SYSROOT)/res/icons/%@18px.png, $(ICONS_SVGs))
ICONS_AT_24PX = $(patsubst thirdparty/icons/svg/%.svg, $(SYSROOT)/res/icons/%@24px.png, $(ICONS_SVGs))
ICONS_AT_36PX = $(patsubst thirdparty/icons/svg/%.svg, $(SYSROOT)/res/icons/%@36px.png, $(ICONS_SVGs))
ICONS_AT_48PX = $(patsubst thirdparty/icons/svg/%.svg, $(SYSROOT)/res/icons/%@48px.png, $(ICONS_SVGs))

ICONS_PNGs = $(ICONS_AT_18PX) $(ICONS_AT_24PX) $(ICONS_AT_36PX) $(ICONS_AT_48PX)


list_icon:
	@echo $(ICONS_PNGs)

$(SYSROOT)/res/icons/%@18px.png: thirdparty/icons/svg/%.svg
	$(DIRECTORY_GUARD)
	@echo [ICON] $(notdir $@)
	@inkscape --export-filename=$@ -w 18 -h 18 $< || \
	 inkscape --export-png $@ -w 18 -h 18 $< 1>/dev/null

$(SYSROOT)/res/icons/%@24px.png: thirdparty/icons/svg/%.svg
	$(DIRECTORY_GUARD)
	@echo [ICON] $(notdir $@)
	@inkscape --export-filename=$@ -w 24 -h 24 $< || \
	 inkscape --export-png $@ -w 24 -h 24 $< 1>/dev/null

$(SYSROOT)/res/icons/%@36px.png: thirdparty/icons/svg/%.svg
	$(DIRECTORY_GUARD)
	@echo [ICON] $(notdir $@)
	@inkscape --export-filename=$@ -w 36 -h 36 $< || \
	 inkscape --export-png $@ -w 36 -h 36 $< 1>/dev/null

$(SYSROOT)/res/icons/%@48px.png: thirdparty/icons/svg/%.svg
	$(DIRECTORY_GUARD)
	@echo [ICON] $(notdir $@)
	@inkscape --export-filename=$@ -w 48 -h 48 $< || \
	 inkscape --export-png $@ -w 48 -h 48 $< 1>/dev/null

# --- Ramdisk -------------------------------------------- #

RAMDISK=$(BOOTROOT)/boot/ramdisk.tar

SYSROOT_CONTENT=$(wildcard sysroot/*) $(wildcard sysroot/*/*) $(wildcard sysroot/*/*/*)

$(RAMDISK): $(CRTS) $(LIBS_ARCHIVES) $(UTILS_BINARIES) $(APPS_BINARIES) $(SYSROOT_CONTENT) $(ICONS_PNGs) $(HEADERS)
	$(DIRECTORY_GUARD)

	@echo [TAR] $@

	@mkdir -p \
		$(SYSROOT)/dev \
		$(SYSROOT)/res \
		$(SYSROOT)/srv \
		$(SYSROOT)/sys

	@cp -r sysroot/* $(SYSROOT)/

	@cd $(SYSROOT); tar -cf $@ *

# --- Bootdisk ------------------------------------------- #

BOOTDISK=$(BUILD_DIRECTORY)/bootdisk.iso

$(BOOTDISK): $(RAMDISK) $(KERNEL_BINARY) grub.cfg
	$(DIRECTORY_GUARD)
	@echo [GRUB-MKRESCUE] $@

	@mkdir -p $(BOOTROOT)/boot/grub
	@cp grub.cfg $(BOOTROOT)/boot/grub/

	@grub-mkrescue -o $@ $(BOOTROOT) || grub2-mkrescue -o $@ $(BOOTROOT)

# --- Phony ---------------------------------------------- #

.PHONY: all
all: $(BOOTDISK)

.PHONY: run
run: run-qemu

.PHONY: run-qemu
run-qemu: $(BOOTDISK)
	@echo [QEMU] $^
	$(QEMU) -cdrom $^ $(QEMUFLAGS) $(QEMUEXTRA) -enable-kvm || \
	$(QEMU) -cdrom $^ $(QEMUFLAGS) $(QEMUEXTRA)

.PHONY: run-vbox
run-vbox: $(BOOTDISK)
	VBoxManage unregistervm --delete "skiftOS-dev" || echo "Look like it's the fist time you are running this command, this is fine"
	VBoxManage createvm \
		--name skiftOS-dev \
		--ostype Other \
		--register \
		--basefolder $(shell pwd)/vm

	VBoxManage modifyvm \
		skiftOS-dev \
		--memory 512

	VBoxManage storagectl \
		skiftOS-dev \
		--name IDE \
		--add ide \

	VBoxManage storageattach \
		skiftOS-dev \
		--storagectl IDE \
		--port 0 \
		--device 0 \
		--type dvddrive \
		--medium $(BOOTDISK)


	VBoxManage startvm skiftOS-dev --type gui

sync:
	rm $(BOOTDISK) $(RAMDISK)
	make $(BOOTDISK)

.PHONY: clean
clean:
	rm -rf $(BUILD_DIRECTORY)

-include $(OBJECTS:.o=.d)
