# Load a custom U-Boot into RAM over JTAG on the Meraki MR33 (IPQ4029).
# Paste this into the OpenOCD telnet console (telnet localhost 4444) once
# `openocd.exe -f jlink.cfg -f IPQ4029.cfg` is running and has attached to the target.

# Stop OpenOCD's background polling so we can drive reset/DAP state by hand
# without it fighting us mid-sequence.
poll off

# Select cpu0 as the active target for the commands below.
targets IPQ4029.cpu0

# Power up the Debug Access Port (CSYSPWRUPREQ/CDBGPWRUPREQ bits) so the DAP
# is actually usable; without this, register/memory access can fail or stick.
IPQ4029.dap dpreg 0x4 0x5000001e
sleep 50

# Probe cpu0 again now that the DAP is powered, to refresh OpenOCD's view of it.
IPQ4029.cpu0 arp_examine

# Pulse the system reset line (SRST) to put the SoC boot ROM/SBL back into a
# known early state, then release it and give the chip time to come back up.
adapter assert srst
sleep 150
adapter deassert srst
sleep 500

# Re-power the DAP and re-examine cpu0 after the reset, since the reset can
# drop debug power again. The extra sleep lets early boot code run its course
# before we interrupt it.
IPQ4029.dap dpreg 0x4 0x5000001e
sleep 50
IPQ4029.cpu0 arp_examine
sleep 1000

# At this point cpu0 is running the factory U-Boot (it has not yet loaded/
# booted Linux). Halt it right there, load our own U-Boot image into RAM,
# point the program counter at its entry address, and let the core run from
# there instead - replacing the factory U-Boot before it gets to Linux.
halt
load_image u-boot_2017.bin 0x86000000 bin
reg pc 0x86000000
resume

# Notes / things that were tried but are not currently needed:
#
## Step 3: CRITICAL - Clear and invalidate caches to force CPU to fetch the new code
#IPQ4029.cpu0 cache l1 d flush_all
#IPQ4029.cpu0 cache l1 i inval_all
#IPQ4029.cpu0 cache l2x flush_all
