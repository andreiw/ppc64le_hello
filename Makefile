ENV_FILE=build_env
-include $(ENV_FILE)

OBJ = entry.o main.o console.o string.o fdt.o fdt_strerror.o fdt_ro.o exc-vecs.o \
       exc.o time.o mmu.o mem.o opal.o cache.o
NAME = ppc64le_hello

ifeq ($(CONFIG_NOSIM), 1)
BUILD_FLAGS = -DCONFIG_NOSIM
else
OBJ += mambo.o
endif

CROSS ?= ppc64le-linux
CC = $(CROSS)-gcc

ARCH_FLAGS = -m64 -msoft-float -mpowerpc64 -mcpu=power8 -mtune=power8 -mabi=elfv2 \
             -mlittle-endian -mno-strict-align -mno-multiple \
             -mno-pointers-to-nested-functions -mcmodel=large -fno-builtin \
             -fno-stack-protector -I./ -Wall -Werror

BUILD_ENV = "CROSS=$(CROSS)|ARCH_FLAGS=$(ARCH_FLAGS)|BUILD_FLAGS=$(BUILD_FLAGS)|OBJ=$(OBJ)"
ifneq ($(BUILD_ENV),$(OLD_BUILD_ENV))
	PRETARGET=clean_env
else
	PRETARGET=log_env
endif

all: $(PRETARGET) $(NAME)

log_env:
	@echo Resuming build with current environment

log_clean_env:
	@echo Cleaning due to environment change

clean_env: log_clean_env clean
	@echo OLD_BUILD_ENV=\"$(BUILD_ENV)\" > $(ENV_FILE)

test: $(NAME) skiboot/skiboot.lid
	./run_ppc64le_hello.sh

skiboot/skiboot.lid:
	git submodule update --init skiboot
	SKIBOOT_VERSION=foo make -C skiboot

-include $(OBJ:.o=.d)

# Default sed regexp - multiline due to syntax constraints
define sed-command
	"/^->/{s:->#\(.*\):/* \1 */:; \
	s:^->\([^ ]*\) [\$$#]*\([-0-9]*\) \(.*\):#define \1 \2 /* \3 */:; \
	s:^->\([^ ]*\) [\$$#]*\([^ ]*\) \(.*\):#define \1 \2 /* \3 */:; \
	s:->::; p;}"
endef

asm-offset.h: asm-offset.s
	sed -ne $(sed-command) $< > $@

asm-offset.s: asm-offset.c
	$(CC) $(ARCH_FLAGS) $(BUILD_FLAGS) -S $< -o $@

%.o: %.S
	$(CC) $(ARCH_FLAGS) $(BUILD_FLAGS) -D__ASSEMBLY__ -c -MMD -o $@ $<
	@cp -f $*.d $*.d.tmp
	@sed -e 's/.*://' -e 's/\\$$//' < $*.d.tmp | fmt -1 | \
	  sed -e 's/^ *//' -e 's/$$/:/' >> $*.d
	@rm -f $*.d.tmp

%.o: %.c
	$(CC) $(ARCH_FLAGS) $(BUILD_FLAGS) -S $< -o $@.s
	$(CC) $(ARCH_FLAGS) $(BUILD_FLAGS) -c -MMD -o $@ $<
	@cp -f $*.d $*.d.tmp
	@sed -e 's/.*://' -e 's/\\$$//' < $*.d.tmp | fmt -1 | \
	  sed -e 's/^ *//' -e 's/$$/:/' >> $*.d
	@rm -f $*.d.tmp

$(NAME): asm-offset.h $(OBJ)
	$(CC) $(ARCH_FLAGS) $(BUILD_FLAGS) -fuse-ld=gold -Wl,--build-id=none -Wl,--EL -T ld.script -ffreestanding -nostdlib -Ttext=0x8000000020010000 -lgcc -o $@ $^

clean:
	$(RM) $(NAME) *.o *.o.s *.d asm-offset.h asm-offset.s
cleaner: clean
	git submodule deinit -f skiboot
.PHONY: clean cleaner
