# need to get images path defined early
source $env(LIB_DIR)/ppc/util.tcl

proc mconfig { name env_name def } {
    global mconf
    global env

    if { [info exists env($env_name)] } { set mconf($name) $env($env_name) }
    if { ![info exists mconf($name)] } { set mconf($name) $def }
}

mconfig threads THREADS 1
mconfig memory MEM_SIZE 1G

# Should we stop on an illeagal instruction
mconfig stop_on_ill MAMBO_STOP_ON_ILL false

# Location of application binary to load
mconfig boot_image SKIBOOT skiboot/skiboot.lid

# Boot: Memory location to load boot_image, for binary or vmlinux
mconfig boot_load MAMBO_BOOT_LOAD 0

# Boot: Value of PC after loading, for binary or vmlinux
mconfig boot_pc	MAMBO_BOOT_PC 0x10

# Payload: Allow for a Linux style ramdisk/initrd
if { ![info exists env(SKIBOOT_ZIMAGE)] } {
	error "Please set SKIBOOT_ZIMAGE to the path of your zImage.epapr"
}
mconfig payload PAYLOAD $env(SKIBOOT_ZIMAGE)

# Paylod: Memory location for a Linux style ramdisk/initrd
mconfig payload_addr PAYLOAD_ADDR 0x20000000;

# FW: Where should ePAPR Flat Devtree Binary be loaded
mconfig epapr_dt_addr EPAPR_DT_ADDR 0x1f00000;# place at 31M

# Disk: Location of file to use a bogus disk 0
mconfig rootdisk ROOTDISK none

# Disk: File to use for re COW file: none or <file>
mconfig rootdisk_cow MAMBO_ROOTDISK_COW none

# Disk: COW method to use
mconfig rootdisk_cow_method MAMBO_ROOTDISK_COW_METHOD newcow

# Disk: COW hash size
mconfig rootdisk_cow_hash MAMBO_ROOTDISK_COW_HASH 1024

# Net: What type of networking: none, phea, bogus
mconfig net MAMBO_NET none

# Net: What is the base interface for the tun/tap device
mconfig tap_base MAMBO_NET_TAP_BASE 0


#
# Create machine config
#

define dup pegasus myconf
myconf config processor/number_of_threads $mconf(threads)
myconf config memory_size $mconf(memory)
myconf config processor_option/ATTN_STOP true
myconf config processor_option/stop_on_illegal_instruction $mconf(stop_on_ill)
myconf config UART/0/enabled false
myconf config SimpleUART/enabled false
myconf config enable_rtas_support false
myconf config processor/cpu_frequency 512M
myconf config processor/timebase_frequency 1/1
myconf config enable_pseries_nvram false

define machine myconf mysim

#
# Include various utilities
#

source $env(LIB_DIR)/common/epapr.tcl
if {![info exists of::encode_compat]} {
    source $env(LIB_DIR)/common/openfirmware_utils.tcl
}

# Only source mambo_utils.tcl if it exists in the current directory. That
# allows running mambo in another directory to the one skiboot.tcl is in.
if { [file exists ./skiboot/external/mambo/mambo_utils.tcl] } then {
	source ./skiboot/external/mambo/mambo_utils.tcl
}

#
# Instanciate xscom
#

set xscom_base 0x1A0000000000
mysim xscom create $xscom_base

# Setup bogus IO

if { $mconf(rootdisk) != "none" } {
    # Now load the bogus disk image
    switch $mconf(rootdisk_cow) {
	none {
	    mysim bogus disk init 0 $mconf(rootdisk) rw
	    puts "bogusdisk initialized for $mconf(rootdisk)"
	}
	default {
	    mysim bogus disk init 0 $mconf(rootdisk) \
		$mconf(rootdisk_cow_method) \
		$mconf(rootdisk_cow) $mconf(rootdisk_cow_hash)
	}
    }
}
switch $mconf(net) {
    none {
	puts "No network support selected"
    }
    bogus - bogusnet {
	set net_tap [format "tap%d" $mconf(tap_base)]
	mysim bogus net init 0 $mconf(net_mac) $net_tap
    }
    default {
	error "Bad net \[none | bogus]: $mconf(net)"
    }
}

# Device tree fixups

set root_node [mysim of find_device "/"]

mysim of addprop $root_node string "epapr-version" "ePAPR-1.0"
mysim of setprop $root_node "compatible" "ibm,powernv"

set cpus_node [mysim of find_device "/cpus"]
mysim of addprop $cpus_node int "#address-cells" 1
mysim of addprop $cpus_node int "#size-cells" 0

set cpu0_node [mysim of find_device "/cpus/PowerPC@0"]
mysim of addprop $cpu0_node int "ibm,chip-id" 0

set mem0_node [mysim of find_device "/memory@0"]
mysim of addprop $mem0_node int "ibm,chip-id" 0

set xscom_node [ mysim of addchild $root_node xscom [format %x $xscom_base]]
set reg [list $xscom_base 0x10000000]
mysim of addprop $xscom_node array64 "reg" reg
mysim of addprop $xscom_node empty "scom-controller" ""
mysim of addprop $xscom_node int "ibm,chip-id" 0
mysim of addprop $xscom_node int "#address-cells" 1
mysim of addprop $xscom_node int "#size-cells" 1
set compat [list]
lappend compat "ibm,xscom"
lappend compat "ibm,power8-xscom"
set compat [of::encode_compat $compat]
mysim of addprop $xscom_node byte_array "compatible" $compat

# Flatten it

epapr::of2dtb mysim $mconf(epapr_dt_addr) 

# Load images

set boot_size [file size $mconf(boot_image)]
mysim memory fread $mconf(boot_load) $boot_size $mconf(boot_image)

set payload_size [file size $mconf(payload)]
mysim memory fread $mconf(payload_addr) $payload_size $mconf(payload)

# Init CPUs

for { set i 0 } { $i < $mconf(threads) } { incr i } {
    mysim mcm 0 cpu 0 thread $i set spr pc $mconf(boot_pc) 
    mysim mcm 0 cpu 0 thread $i set gpr 3 $mconf(epapr_dt_addr)
    mysim mcm 0 cpu 0 thread $i config_on    
}

mysim console create 0 inout program xterm

# Turbo mode & run
mysim mode turbo
mysim go
exit
