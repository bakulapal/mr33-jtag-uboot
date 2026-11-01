# Meraki MR33 (IPQ4029): JTAG-loaded U-Boot -> TFTP flash of OpenWrt

Boots a modified ("jailbroken") U-Boot 2012.07-ga8496ca-dirty into RAM over JTAG on a
Meraki MR33.

Its `tftpsrv` command then lets a PC upload an OpenWrt initramfs image.

## Environment

| Item | Value |
|---|---|
| OpenOCD | xPack OpenOCD 0.12.0+dev-02228-ge5888bda3-dirty (2025-10-04) |
| Adapter | SEGGER J-Link (`jlink.cfg`, JTAG transport) |
| Target | Qualcomm IPQ4029, 4x Cortex-A7, Actually I'm not sure whether `IPQ4029.cfg` or `IPQ4029_old.cfg` was used in the end |
| JTAG chain | dummy0 (0x6e8011dc, IR5), dummy1 (0xb74008ee, IR5), **cpu DAP (0x5ba00477, IR4)**, auto0 (0x000016dd, IR5), auto1 (0x0003d0e1, IR11) |
| Debug bases | cpu0..3 at 0x80040000 / 42000 / 44000 / 46000; CTIs 0x80010000.. |
| RAM payload | `uboot/u-boot_2012.07-ga8496ca-dirty.bin`, loaded to `0x86000000` (SHA256 `91E190D5D62A7F289C1F123FE87D002A06943B1CA5C01EDBA65A49F238F20085`) |
| OpenWrt image | `openwrt-25.12.5-ipq40xx-generic-meraki_mr33-initramfs-uImage.itb` (download from OpenWrt, not stored here) |
| Flashing PC | static IP `192.168.1.10`, wired to MR33 LAN; tftp client |
| MR33 U-Boot IP | `192.168.1.1` |
| Serial | Not needed. 115200 8N1; **never send any input** (keypress blows an efuse, see warning) |

## Requirements

- A J-Link (or another OpenOCD-compatible debug probe, e.g. a
  cheaper CMSIS-DAP or FTDI-based adapter - just swap `jlink.cfg` for
  the matching interface config). The reset/power-up delays in
  `hijack-uboot.tcl` were tuned for a J-Link; a different probe
  may need shorter or longer wait times to get a reliable hijack.
- Wires to the MR33's JTAG pads, or a Tag-Connect TC2050 cable with
  a TC2050-ARM2010 adapter (pinout:
  https://www.tag-connect.com/wp-content/uploads/bsk-pdf-manager/2021/02/TC2050-ARM2010-2021.pdf)
  for a solderless connection. The adapter itself can be swapped for
  plain Dupont jumper wires if you don't have one.
- `libusb-1.0.dll`/`libftdi1.dll` next to `openocd.exe` (the xPack
  bundle already includes them) and the probe on a libusb/WinUSB
  driver (Zadig) if OpenOCD cannot open it.

> **WARNING - do not type on the serial console.**
> The RAM-loaded U-Boot is booby-trapped: any keypress on the UART
> blows a CPU efuse and permanently bricks the device. The flow is
> fully automatic (TFTP server + boot), so leave the UART disconnected
> or strictly read-only (RX only, never transmit).

> **Disclaimer / volunteers required:**
> this process was tested with a *non-booby-trapped* U-Boot build. It
> should work the same with the booby-trapped one, but that has not
> been verified. Volunteers willing to test it (on a device they can
> afford to brick) are needed. Use at your own risk.
>
> As the MR33 is nearing its end of support life, this is worth
> confirming: with the MR33 (and similar IPQ40xx Merakis) reaching
> end-of-life, if this JTAG approach also works on the 2017
> bootloader, it may end up being an easier recovery/unlock path than
> desoldering the NAND and reflashing it externally - though it does
> require a JTAG tool rather than just a NAND programmer (see
> Requirements above).

> **Reliability:**
> hijacking the bootloader before it loads Linux (and replacing it) is
> not 100% polished/reliable yet. Expect it to succeed roughly 1-2 out
> of 3 attempts; if the hijack or TFTP boot doesn't take,
> power-cycle the board and retry from step 1.

## What the hijack script actually does

In plain terms: once OpenOCD is attached over JTAG, we tell it to stop
auto-polling the chip so we're fully in control.

We power up the debug port on cpu0 and re-probe it, then pulse the
reset line and wait a bit for the SoC to come back up from its very
first boot stage.

We power up the debug port again (reset tends to knock it back down)
and probe once more.

At this point cpu0 is running the factory U-Boot but hasn't booted
Linux yet, so we halt it right there, shove our own
`u-boot_2012.07-ga8496ca-dirty.bin` straight into RAM at `0x86000000`,
point the CPU's program counter at the start of that image, and let 
it run - hijacking the boot before the factory U-Boot gets to Linux.

From the chip's point of view it just "woke up" running our U-Boot
instead of Meraki's - no flash was touched, nothing was reprogrammed,
it's all living in RAM. That's also why a plain power cycle undoes
everything.

## Procedure

1. Wire J-Link to MR33 JTAG header, power the board (leave UART
   disconnected).
2. Start OpenOCD from the folder with `u-boot_2012.07-ga8496ca-dirty.bin` (copy
   `uboot/u-boot_2012.07-ga8496ca-dirty.bin` and `openocd/*.cfg` next to it, or adjust
   paths):
   ```
   openocd.exe -f jlink.cfg -f IPQ4029.cfg
   ```
   (or run `openocd\run_openocd.cmd`)
3. In another terminal: `telnet localhost 4444`, then paste the
   contents of `openocd/hijack-uboot.tcl`. It resets the chip and
   drops our custom U-Boot into RAM instead of the stock one (see
   "What the hijack script actually does" above for the details).
4. The RAM-loaded U-Boot starts its TFTP server automatically (no
   serial console or typing needed - and typing is dangerous).
5. On the PC (192.168.1.10):
   ```
   echo -e "binary\nput openwrt-25.12.5-ipq40xx-generic-meraki_mr33-initramfs-uImage.itb" | tftp 192.168.1.1
   ```
   (Windows: use `tftp -i 192.168.1.1 PUT <file>` or the Linux/WSL
   command above.)
6. U-Boot boots the uploaded image automatically. Once initramfs
   OpenWrt runs, do `sysupgrade` from it to make it permanent.

## Flashing U-Boot permanently from running OpenWrt (risky, optional)

The goal here: replace the factory U-Boot for good, without ever
touching it - no typing on its serial console, no interacting with it
at all.

**Check your U-Boot version first.** This in-Linux NAND-write
procedure is not proven on every factory U-Boot build; identify what
you actually have before attempting it, e.g. by dumping the `u-boot`
MTD partition with `dd` (`dd if=/dev/mtdX of=u-boot-dump.bin`, where
`X` is the `u-boot` partition from the layout below) and checking the
version string in the dump. If your device has the older 2012.07
U-Boot, skip this section entirely and use the standard
`ubootwrite.py` serial procedure instead (see References) - that
build can be interrupted and reflashed over UART directly.

Every reboot still goes through the factory U-Boot unless the
`u-boot` NAND region itself gets overwritten; the hijack U-Boot
only ever lives in RAM and is gone after a power cycle. The trick is
that once OpenWrt is up and running (e.g. after `sysupgrade`), it is
Linux doing the writing, not the factory U-Boot's console. There is a
documented but risky way to do this from
[halmartin/meraki-openwrt-docs](https://github.com/halmartin/meraki-openwrt-docs)
(`mr33/README.md`).

> **This can brick the device if any step fails or power is lost
> mid-write.** Only the recommended sequence below reduces that risk;
> read it fully before starting.

MR33 NAND layout (offsets exclude OOB data):

```
0x000000000000-0x000000100000 : "sbl1"
0x000000100000-0x000000200000 : "mibib"
0x000000200000-0x000000300000 : "bootconfig"
0x000000300000-0x000000400000 : "qsee"
0x000000400000-0x000000500000 : "qsee_alt"
0x000000500000-0x000000580000 : "cdt"
0x000000580000-0x000000600000 : "cdt_alt"
0x000000600000-0x000000680000 : "ddrparams"
0x000000700000-0x000000900000 : "u-boot"
0x000000900000-0x000000b00000 : "u-boot-backup"
0x000000b00000-0x000000b80000 : "ART"
0x000000c00000-0x000007c00000 : "ubi"
```

Recommended (safer) sequence, from a shell on the running OpenWrt:

1. First write the unlocked U-Boot to the `part.safe` UBI volume
   instead of NAND directly, so a bad flash still leaves a bootable
   fallback:
   ```
   ubi write $loadaddr part.safe 0x2fd48
   ```
   (this step is normally done from the U-Boot prompt, before Linux
   is even running - see the upstream doc for the full sequence).
2. Once you've confirmed the new U-Boot boots reliably from
   `part.safe`, only then flash it permanently to the real `u-boot`
   NAND region from Linux. This requires an out-of-tree kernel module
   that, by design, makes read-only MTD partitions writable - its own
   parameter name is the project's built-in warning:
   ```
   insmod mtd-rw i_want_a_brick=1
   ```
3. Copy the ELF build of U-Boot (not `.bin`/`.itb`) to the router and
   verify its checksum on-device:
   ```
   scp -O u-boot.elf root@192.168.1.1:/tmp/
   md5sum /tmp/u-boot.elf
   ```
4. Erase and write the `u-boot` MTD partition (`mtd8` on MR33):
   ```
   flash_erase /dev/mtd8 0 0
   nandwrite -p /dev/mtd8 /tmp/u-boot.elf
   ```
   If either command fails, **do not reboot or power off** - the
   device will not boot. Only `u-boot.elf` is safe to write here;
   `u-boot.bin`/`u-boot.itb` will brick the `u-boot` region.
5. Once confirmed working, the temporary `part.safe` volume can be
   removed:
   ```
   ubirmvol -N part.safe /dev/ubi0
   ```

## Files

- `openocd/IPQ4029.cfg` - current target config (all 4 cores, SMP
  line commented out).
- `openocd/IPQ4029_old.cfg` - older config used with
  `legacy-notes.txt`.
- `openocd/jlink.cfg`, `scan.cfg` - adapter config / chain scan.
- `openocd/hijack-uboot.tcl` - the working command sequence (SRST +
  DAP power-up + load + run).
- `openocd/legacy-notes.txt` - earlier manual approach (arm mcr cache
  tweak, per-core halt) and bootm notes.
- `openocd/run_openocd.cmd` - OpenOCD launch line.
- `uboot/u-boot_2012.bin` - the RAM-loaded U-Boot.

## Notes

- Secure boot on the SoC is not bypassed; the jailbreak lies in
  running an unsigned U-Boot from RAM via JTAG after the boot
  ROM/SBL1 stage.

## References / attribution

- Related tool:
  [sebastiaanv3/ubootwrite](https://github.com/sebastiaanv3/ubootwrite)
- Permanent (NAND) U-Boot flashing procedure, NAND layout, and the
  `mtd-rw i_want_a_brick=1` step:
  [halmartin/meraki-openwrt-docs](https://github.com/halmartin/meraki-openwrt-docs)
  (`mr33/README.md`)
- `uboot/u-boot_2012.bin` originates from the Google Drive share
  [1jJa8LzYnY830v3nBZdOgAk0YQK6OdbSS](https://drive.google.com/drive/folders/1jJa8LzYnY830v3nBZdOgAk0YQK6OdbSS)
  and can be extracted from `mr33-uboot.bin` with `7zip`.
