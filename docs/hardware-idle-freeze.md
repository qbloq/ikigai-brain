# Random hard freezes — diagnosis & fix (Ryzen 1700 idle-freeze)

**Machine:** `qbloq-node-0` — Gigabyte GA-AX370-Gaming K5 (X370), AMD Ryzen 7 1700
(8c/16t, 1st-gen "Summit Ridge"), NVIDIA GTX 1050 Ti, Ubuntu 24.04.

**Status:** diagnosed 2026-07-03. Fix in progress (BIOS update F2 → F54a, then set
*Typical Current Idle*). Update this file as steps complete.

---

## Symptom
Total hard lockups, at random, for **years**. Machine can be fine for a week+, then
freezes solid — even `Ctrl+Alt+F1` (VT switch) gives a blank screen, no login prompt.
No panic on screen. Correlates with **low load / idle** (user confirmed this fits).
Requires a hard power-cut to recover.

## Diagnosis: 1st-gen Ryzen idle-freeze bug (very high confidence)
First-gen Zen (Ryzen 1000-series) has a well-documented defect: at very low load the
core requests its deepest sleep state (**C6**) and sometimes fails to wake → instant
total lockup, no logs, dead VT. The "years-long, random, idle-correlated, but stable
for weeks at a time" profile is the textbook signature. If it were dying silicon or
failing RAM it would have gotten steadily *worse* over the years; it hasn't.

### Evidence gathered (from journald, 2026-07-03)
- **Real hard resets, ~daily recently:** last 5 boots ended with *no clean-shutdown
  marker* → the machine was hard-locked and reset, not rebooted.
- **Recurring Machine Check Exceptions**, same signature across multiple days/cores:
  `mce: [Hardware Error] Bank 5: bea0000000000108`, `PROCESSOR 2:800f11` (= Ryzen
  Summit Ridge), microcode `800111c`. Likely a *side effect* of the botched C6 idle
  transition rather than independently failing hardware — but keep `rasdaemon`
  watching to be sure.
- Minor noise, deprioritized until the idle bug is ruled out:
  - `irq 7: nobody cared … amd_gpio_irq_handler … Disabling IRQ #7` (GPIO IRQ storm)
  - `AMD-Vi: INVALID_DEVICE_REQUEST device=0000:00:00.0` (IOMMU faults)
  - `ata3.00: Read log 0x00 page 0x00 failed` (one SATA device)
  - `tpm_crb … [Firmware Bug]` and `ee1004 … Failed to select page` (harmless)
- **journald is persistent** (`/var/log/journal` exists) → future freezes will leave
  evidence. Good.

### Key context that shaped the fix
- **BIOS was F2, dated 2017-04-07 — the board's LAUNCH bios.** That predates the AMD
  AGESA microcode that both *fixes the idle bug directly* and *adds the "Power Supply
  Idle Control" option*. That's why the user couldn't find the setting: it literally
  wasn't in F2. → BIOS update became the primary fix.

---

## The fix

### 1. BIOS update F2 → F54a  ← primary, durable, root-cause fix
Downloaded `mb_bios_ga-ax370-gaming-k5_8a06bg0a_f54a.zip` (contains one file,
`AX370GamingK5.F54a`, 16 MB — the ROM Q-Flash selects).
Correct ROM: md5 `159eb3dfec7da23afde1cb3df9b09753`, size 16777216 bytes (verified
intact — download is NOT corrupt).

> **GOTCHA — cannot jump F2 → F54a directly.** Q-Flash on launch BIOS F2 rejects
> F54a as **"invalid image"** because F54a is past AMD's AGESA "ComboAM4" transition,
> which changed the BIOS image structure. Old Q-Flash can't read the new format.
> **Must flash an intermediate (stepping-stone) BIOS first**, then F54a. Check each
> version's release notes on Gigabyte's AX370-Gaming K5 BIOS page for a "please
> update to Fxx first" note — grab a mid-era F2x/F3x, flash it, then F54a. May need
> two hops. (Reached this point 2026-07-03: file confirmed good, hit "invalid image",
> intermediate BIOS not yet downloaded.)

Flash via **Q-Flash** (Gigabyte needs only a **FAT32 stick** with the ROM in root — no
bootloader). Stick prep that was used (device `/dev/sdc`, 123 MB USB "Flash Disk"):

```bash
lsblk -o NAME,SIZE,TRAN,RM,MODEL /dev/sdc     # SAFETY: must be the removable USB stick
sudo umount /dev/sdc* 2>/dev/null
sudo wipefs -a /dev/sdc
echo -e 'label: dos\n,,c' | sudo sfdisk /dev/sdc
sudo mkfs.vfat -F 32 -n GBIOS /dev/sdc1
mkdir -p /tmp/gbios && sudo mount /dev/sdc1 /tmp/gbios
sudo unzip -o ~/mb_bios_ga-ax370-gaming-k5_8a06bg0a_f54a.zip -d /tmp/gbios
sync && ls -la /tmp/gbios                      # expect AX370GamingK5.F54a
sudo umount /tmp/gbios
```

Flash: reboot → **Del** (BIOS) or **End** at POST → **Q-Flash → Update BIOS** → pick
`AX370GamingK5.F54a`. **Do not interrupt** (only irreversible step; stable power).
Afterward: re-enter BIOS → **Load Optimized Defaults** → save. Settings reset to
default, so re-apply any RAM XMP/DOCP + fan curves.

**Then set the actual fix:** **M.I.T. → Advanced CPU Core Settings** (or **Settings →
AMD CBS → Zen Common Options**) → **Power Supply Idle Control → Typical Current Idle**.
This is AMD's official mitigation — stops the too-deep idle that hangs. No perf/power
cost. F54a should expose it.

### 2. Kernel-param fallback (only if BIOS-only doesn't hold)
Software way to forbid C6 from the OS side. Not applied by default — the BIOS fix is
cleaner (firmware-level, survives kernel changes, no idle-power cost). Use only if
freezes persist after the BIOS fix:

```bash
sudo cp -a /etc/default/grub /etc/default/grub.bak.$(date +%F)
sudo sed -i 's#^GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"#GRUB_CMDLINE_LINUX_DEFAULT="quiet splash processor.max_cstate=1 idle=nomwait rcu_nocbs=0-15"#' /etc/default/grub
grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub    # verify before regenerating
sudo update-grub
# reboot, then: cat /proc/cmdline   # confirm params present
```
(`rcu_nocbs=0-15` covers all 16 threads. Strip these back out once BIOS-only proves
stable for ~a month.)

### 3. Keep the recorder running (do regardless)
So any recurrence leaves a decoded hardware trace instead of another blank-screen
mystery:
```bash
sudo apt install -y rasdaemon lm-sensors
sudo systemctl enable --now rasdaemon
sudo sensors-detect --auto
```
After any future freeze: `sudo ras-mc-ctl --errors` (decoded MCEs) and
`journalctl --list-boots` (look for a boot with no clean-shutdown marker).

---

## If freezes CONTINUE after BIOS F54a + Typical Current Idle
Then reconsider genuine hardware (the recurring Bank-5 MCEs would be the tell):
- **MemTest86**, a couple full passes — Ryzen is very sensitive to RAM / Infinity-Fabric
  instability. Reseat RAM; make sure it isn't overclocked past spec (drop XMP/DOCP).
- Check PSU can hold voltage under this Ryzen (droop → idle instability).
- Chase the `amd_gpio` IRQ 7 storm and IOMMU faults (try `amd_iommu=off` or
  `iommu=soft` as a test).

## Recovery / rollback
- grub params: `sudo cp -a /etc/default/grub.bak.<date> /etc/default/grub && sudo update-grub`
- A failed/interrupted flash may need Gigabyte's DualBIOS recovery or a re-flash.

---

## Progress log
- **2026-07-03** — Diagnosed (idle-freeze). Confirmed real hard resets + recurring
  Bank-5 MCEs in journald. Found BIOS on launch F2 → this is why *Typical Current
  Idle* was missing. Downloaded F54a, prepped Q-Flash stick. Q-Flash rejected F54a
  with **"invalid image"** — confirmed download is intact (md5 ok), so it's the
  F2→F54a version-jump problem (see GOTCHA above). **Next: download an intermediate
  BIOS from Gigabyte's AX370-Gaming K5 page (follow the "update to Fxx first" release
  notes), flash it, then F54a → set Typical Current Idle → install rasdaemon.** Update
  this log after the flash and note whether freezes stop.
