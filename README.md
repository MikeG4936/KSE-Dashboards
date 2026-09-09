# KSE Dashboards for EdgeTX

KSE4 and KSE5 show your RC helicopter’s live flight and battery readings on your EdgeTX radio, with battery warnings and flight counting. Choose **KSE4** for a detailed layout or **KSE5** for a ring-style layout. Preview their colors in the [theme gallery](theme-gallery/README.md).

[Install](#installation-and-first-setup) · [Update](#updating-an-existing-installation) · [Settings](#settings) · [Features](#using-the-features) · [Troubleshooting](#troubleshooting-and-common-questions)

## Requirements

- **Radio:** RadioMaster TX15/MAX, GX15/MAX, TX16S MKII/MAX or TX16S MK3/MAX running EdgeTX. Both dashboards support 800 × 480, 480 × 320 and 480 × 272 screens.
- **Rotorflight models:** Rotorflight 2.3 on the helicopter’s flight controller (FC), plus the complete official Rotorflight 2.3 EdgeTX Lua package on the radio.
- **OMPHOBBY models:** a supported model with the [OMP telemetry sensors](#omphobby-telemetry). RF Tool is not required in manual OMPHOBBY mode. OFS3 firmware requires ExpressLRS **3.5.6 or newer**; this minimum does **not** apply to OFS3+.

## Installation and first setup

If KSE is already installed, follow [Updating](#updating-an-existing-installation).

**Before starting, make the motor physically unable to start.**

### 1. Install the Rotorflight Lua package — Rotorflight models only

Download the **2.3 EdgeTX package** from the [official Rotorflight Lua releases](https://github.com/rotorflight/rotorflight-lua-scripts/releases). Copy the complete package to the top level of the SD card, keeping folder names and capitalization unchanged. Check that these paths exist:

```text
/WIDGETS/RfTool/app.lua
/WIDGETS/RfStats/app.lua
/SCRIPTS/RF2/
/SCRIPTS/TOOLS/rf2.lua
```

In EdgeTX, leave `rf2bg` disabled in **Special Functions** and **Global Functions**.

### 2. Copy your chosen dashboard

On this project’s GitHub page, select **Code → Download ZIP** and unzip the download. Copy the complete **KSE4** or **KSE5** folder from inside it to the SD card:

```text
KSE4 → /WIDGETS/KSE4/
KSE5 → /WIDGETS/KSE5/
```

Keep all files and the `BatterySounds/` folder together. Do not rename the dashboard folder.

### 3. Add one widget and set the essentials

Add **KSE4 or KSE5** to a full-screen telemetry page. Configure **only one KSE widget across all telemetry screens**. Turn off EdgeTX trim sliders and the page’s top bar to give the dashboard the full area.

Open the widget settings and select:

- **Heli Type:** Electric, Nitro or OMPHOBBY to match your helicopter.
- **TX Battery:** LiPo or Li-Ion to match the battery in your radio.
- **Motor Switch:** the whole physical switch, such as `SG`, not an individual switch position or output channel.
- **Flight Counter:** your preferred counter; complete its setup in step 5.

Set battery reserve and voice as desired. For Nitro, set the receiver-pack voltage limits. See [Settings](#settings) for the available options.

### 4. Configure and discover telemetry

**OMPHOBBY:** skip the Rotorflight commands below and use the [OMP sensor checklist](#omphobby-telemetry).

**Rotorflight over CRSF/ExpressLRS:** connect the flight controller to Rotorflight Configurator, open **CLI**, and paste all five lines below.

These commands replace your telemetry selection and restore default update timing. If other alarms, logging or widgets use additional readings or custom timing, save your settings and adjust the commands before applying them.

```text
feature TELEMETRY
set crsf_telemetry_mode = CUSTOM
set telemetry_sensors = 43,60,61,89,88,93,15,3,4,5,6,7,8,95,96,97,90,91,92,99,50,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
set telemetry_interval = 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
save
```

With the helicopter connected to the radio, open KSE once. Then go to the model’s **Telemetry** page and select **Discover new sensors**. Keep KSE installed during discovery. Check the [sensor names](#telemetry-reference), including capitalization, and confirm `ARM` is present for Rotorflight models.

Set **`Tesc`** (Rotorflight) or **`Temp`** (OMP, if used) to **Celsius (°C)**.

### 5. Set up your flight counter

Follow the setup for your chosen counter. **OMPHOBBY uses KSE Counter.**

| Counter | Setup |
| --- | --- |
| **Rotorflight FC** (default) | Enable model statistics in Rotorflight/RF Tool and choose the minimum armed time for a flight to count. Confirm `ARM` is discovered. |
| **KSE Counter** | Set EdgeTX **Timer 1** to run when your motor switch is on. Set **KSE Counter Min (sec)** to the shortest flight you want counted. Reset Timer 1 between flights. |

### 6. Check before flying

With the motor still physically unable to start:

- Confirm live telemetry, battery readings and the correct model/type.
- Check spoken battery warnings, vibration warnings and the selected Motor Switch.
- For Rotorflight, check the displayed profiles while disarmed. For Electric models, confirm the selected battery profile matches the pack you will use.
- Verify your selected counter follows its setup, and that KSE counts survive a normal radio restart.
- Check that telemetry and connection indications recover after disconnecting/reconnecting the FC.

## Updating an existing installation

When moving from **StacyDashV4**, remove its widget from your telemetry screens before adding KSE4 or KSE5.

1. Back up your KSE folders and custom model images. Keep `/flights-count.csv`, `/flights-count.csv.bak` and `/flights-count.csv.tmp` if present; **never replace existing history with the supplied starter file**.
2. Copy the updated dashboard folder, keeping your customized `default.png` if you use one. Remove any old KSE `main.luac` and restart EdgeTX.
3. Keep the complete, compatible RF Tool package installed for Rotorflight models and disable any old `rf2bg` special/global function. Revisit telemetry setup if required sensors are missing. If you delete all sensors before rediscovery, recheck alarms, logging and model functions that use them.
4. Check saved widget settings and repeat the short bench check above.

## Settings

Both dashboards have the same ten settings. Their colors and a few setting names differ.

| Setting | Default | What it controls |
| --- | --- | --- |
| **Theme** | Dark | Dashboard colors. Each has 22 choices; use the [theme gallery](theme-gallery/README.md) to compare them. KSE4 includes transparent themes; KSE5 uses solid backgrounds. |
| **TX Battery** | LiPo | Select 2S LiPo or 2S Li-Ion to match the battery in your radio. |
| **KSE Counter Min (sec)** | 20 | How long Timer 1 must run before KSE counts a flight. Applies only to KSE Counter. |
| **Heli Type** | Electric | Electric, Nitro or OMPHOBBY. Choose the type that matches your helicopter. |
| **Batt Reserve %** / **Battery Reserve %** | 20 | Battery reserve for Electric/OMP: with 20% reserve, the dashboard shows 0% when 20% remains. Range 0–50%; does not affect Nitro. |
| **Battery Voice** | Off | Spoken battery percentages for Electric/OMP and repeating critical-battery warnings. Vibration warnings can still work with voice off. |
| **Rx Pack Minimum** | 6.60 V | Nitro voltage shown as 0%; minimum allowed is 4.0 V. |
| **Rx Pack Maximum** | 8.40 V | Nitro voltage shown as 100%; at most 9.0 V and at least 0.1 V above the minimum. |
| **Motor Switch** | SG | Your physical motor switch, such as `SG`. It also helps silence repeating warnings after the motor stops. Set up Timer 1 separately for KSE counting. |
| **Flight Counter** | Rotorflight FC | Count stored by the helicopter, or KSE counting with Timer 1. KSE5 calls the FC choice **RotorFlight**. |

## Using the features

### Battery readings and warnings

In Electric and OMP modes, **Battery Reserve %** sets aside part of the pack: with a 20% reserve, the dashboard shows 0% when the helicopter reports 20% remaining. Rotorflight Smart Fuel is supported. If battery percentage is unavailable, KSE estimates it from voltage when possible.

In Nitro mode, set **Rx Pack Minimum** and **Rx Pack Maximum** for your receiver battery. These are the voltages shown as 0% and 100%. Nitro does not use battery profiles.

**Battery Voice** turns on spoken warnings. Moving your selected Motor Switch can silence the repeating critical-battery voice warning. Keep your normal radio battery alarms configured too.

### Electric battery profiles

Connect the helicopter and disarm before choosing a battery profile. Enter the capacity printed on each pack in Rotorflight; use KSE’s **Battery Reserve %** for your reserve rather than reducing that capacity. Profiles with a capacity of zero will not appear. If only one profile has a capacity set, KSE can select it automatically.

The profile menu opens after the profiles load. To reopen it while connected and disarmed, tap **KSE4’s battery bar** or **KSE5’s battery ring**.

Wait for KSE to confirm that your selection was saved. If the change is interrupted, reconnect and check the active profile before flying.

### Connection, arming and profile indicators

The top bar shows the active **PID profile / Rate profile**. The battery profile appears above KSE4’s battery bar or inside KSE5’s battery ring.

### During flight

The **arming-blocker banner** explains what is preventing the helicopter from arming. It disappears while armed, or if KSE cannot confirm that the helicopter is disarmed. It returns after confirmed disarm if a blocker remains.

Flight readings, battery warnings and KSE Counter continue working during flight. Battery-profile changes and Rotorflight counter updates wait until KSE can confirm disarm. If you start KSE while already armed, some profile and FC-count information may stay blank until then.

### Dashboard timer

The dashboard clock shows **EdgeTX Timer 1**, even with Rotorflight FC counting selected. Set up Timer 1 separately if you want the clock to run.

### Flight counting

**KSE Counter:** with the default 20-second setting, a flight is counted when Timer 1 has run for 20 seconds. Reset Timer 1 between flights. Count-up and countdown timers both work. If you add or recreate KSE after the timer has already passed the chosen duration, reset the timer before the next flight; that existing run will not be counted.

History is shared between KSE4 and KSE5 and stored by model name. Counts are saved in `/flights-count.csv` on the SD card. KSE creates this file automatically for a fresh start; you do not need to copy the supplied starter file. For file errors, see [Count-history recovery](#count-history-recovery).

**Rotorflight FC counter:** Rotorflight decides whether each flight lasted long enough to count. Disarming and arming again can count as another flight, even without unplugging the battery. KSE displays that total separately from KSE Counter and updates it after confirmed disarm; it does not change or reset it. Timer 1 and a count file are not required for FC counting.

**OMPHOBBY always uses KSE Counter.** Your saved Flight Counter choice takes effect again if you switch to a Rotorflight helicopter type.

## Customization and telemetry reference

### Model images

Place a PNG or BMP in `/IMAGES/` named for the EdgeTX model. For example:

```text
Model name: Goblin RAW
Image: /IMAGES/Goblin RAW.png
```

Names are case-sensitive. Unsuitable filename characters become underscores: `Goblin/RAW` uses `Goblin_RAW.png`.

Images must be no larger than **480 × 272 pixels** and **100 KiB (102,400 bytes)**. Smaller images scale to fit. If an image is too large or cannot be opened, KSE shows a default image or placeholder instead.

When no model image is found, KSE uses `default.png` in its dashboard folder. To use the supplied alternate, back up the original, rename `default1.png` to `default.png`, and reload the widget or restart EdgeTX. Leaving it named `default1.png` does not select it. For dashboard colors, see the [theme gallery](theme-gallery/README.md).

### Telemetry reference

Match sensor names exactly, including capital letters. Link quality is shown using `RQly`, `RQLY` or `LQ`. The [setup commands](#4-configure-and-discover-telemetry) enable these Rotorflight readings:

| Rotorflight sensor | Used for |
| --- | --- |
| `ARM` | Armed/disarmed state; needed for the arming-blocker banner, battery profiles and Rotorflight counter. |
| `Hspd` | Headspeed, maximum headspeed and pausing warnings after motor stop. |
| `Tspd` | KSE4 tail-speed display. |
| `Vbec` | Electric BEC voltage; Nitro receiver-pack voltage, percentage and warnings. |
| `Vbat`, `Vcel`, `Cel#` | Electric pack voltage, cell voltage/minimum and cell count. |
| `Curr`, `Capa` | Current/maximum current and consumed capacity. |
| `Bat%` | Battery percentage, including Rotorflight Smart Fuel when configured. |
| `Tesc` | ESC temperature, maximum and warning. |
| `Gov` | Governor status and pausing warnings after motor stop. |
| `PID#`, `RTE#`, `BAT#` | Active PID, rate and battery profiles. |

The setup also enables RF Tool’s spoken adjustment announcements and `Mode`, `MDL#`, `Thr`, `ARMD` and `Resc` for other radio features. If your own alarms or logging need additional sensors, keep those enabled too.

### OMPHOBBY telemetry

| Sensor | Used for |
| --- | --- |
| `RPM` | Headspeed and pausing warnings after motor stop. |
| `Bat%` | Battery percentage. |
| `Capa` | Consumed capacity in mAh. |
| `Curr` | Current in amps. |
| `RxBt` | Flight-pack voltage. |
| `Temp` (optional) | Temperature. |

The first five names are required. Include **M1** or **M2** in the radio’s model name so KSE uses the right battery type: M1 is 2S LiHV (8.7 V full); M2 is 3S. The Rotorflight sensor list above does not apply to OMP.

## Troubleshooting and common questions

| Symptom or question | What to do |
| --- | --- |
| Do I need a GitHub account to download KSE? | No. Use **Code → Download ZIP** on this project’s GitHub page, then unzip it. |
| Widget is missing | Check `/WIDGETS/KSE4/main.lua` or `/WIDGETS/KSE5/main.lua`, including capitalization; restart EdgeTX. |
| Old behavior remains after updating | Remove old `main.luac` from the KSE folder and restart. |
| How do I switch between KSE4 and KSE5? | You may keep both folders on the SD card. Remove the active widget, wait at least five seconds, then add/open the other dashboard. |
| `Another KSE dashboard is active` | Remove the other KSE widget across all telemetry pages, wait at least five seconds, then reopen the desired dashboard. |
| Do I need a visible RF Tool widget or `rf2bg`? | No. Install the complete RF Tool package for Rotorflight models, but you do not need it on a telemetry screen. Disable any `rf2bg` special/global function. |
| `INSTALL RF TOOL` or no RF connection | Check that RfTool, RfStats and `/SCRIPTS/RF2/` came from the same compatible 2.3 package; check the FC connection and firmware. |
| `--`, `NO DATA` or missing sensors | Connect the helicopter, open KSE once, then discover sensors and check their names. See [telemetry setup](#4-configure-and-discover-telemetry) if readings are missing. |
| `NO ARM SENSOR`, even though the arm switch works | `ARM` is a reading sent by the helicopter, not your physical arm switch. Follow [telemetry setup](#4-configure-and-discover-telemetry) and discover `ARM`; selecting Motor Switch does not replace it. |
| Battery profiles do not open | Use Electric mode, connect and disarm the helicopter, and check that `ARM` is updating. Set a capacity above zero for each battery profile in Rotorflight. |
| `UPDATE EDGETX FOR PROFILE PICKER` | Update EdgeTX to a version supported by your radio and the installed RF Tool package. |
| The dashboard clock does not run | Configure **EdgeTX Timer 1** to run from your motor switch, even if you use Rotorflight FC counting. |
| FC count is unavailable | Connect and disarm the helicopter. Check that `ARM` is updating, model statistics are enabled, and Rotorflight 2.3 plus its Lua package are installed. |
| KSE count does not advance | Set Timer 1 to run with the motor switch. Let it run for the chosen minimum time and reset it between flights. OMP always uses this counter. |
| Battery percentage is missing or looks wrong | For Electric Rotorflight models, first check the battery readings and settings on Configurator’s **Power** tab; see [battery and SmartFuel setup](https://rotorflight.org/docs/configurator/tabs/power). If those look correct, check the radio’s sensors and KSE’s **Battery Reserve %**, which changes the displayed percentage. For OMP, check the [OMP sensor list and model name](#omphobby-telemetry). |
| Can I display temperature in Fahrenheit? | Fahrenheit is not currently supported. Keep `Tesc` (Rotorflight) or `Temp` (OMP, if used) set to Celsius. |
| Nitro battery is missing | Check `Vbec` and receiver-pack voltage settings; Nitro does not use battery profiles. |
| `Profile / Rate` is missing | Discover both `PID#` and `RTE#`; the indicator needs a live link and valid values for both. |
| Model image is missing | Check the filename, capitalization, dimensions and file size against [Model images](#model-images). |
| Arming-blocker banner disappears in flight | This is normal. The banner is useful before arming and returns after confirmed disarm if a blocker remains. |

### Count-history recovery

`FILE ERROR` means KSE could not read or save your flight history. `KSE FILE ERROR` after switching to the Rotorflight counter still refers to the SD-card history, not the count stored in the helicopter.

1. Copy `flights-count.csv`, `flights-count.csv.bak` and `flights-count.csv.tmp` from the SD card to a safe place, keeping whichever files exist. **Do not overwrite them with the starter file.** Unsaved counts can be lost if you restart the radio.
2. Check that the SD card is writable and the history file is not damaged. Keep the `.bak` backup; do not restore the `.tmp` temporary file without checking it. KSE leaves damaged or oversized history files untouched.
3. After fixing the problem, switch away from and back to KSE Counter, or remove and add the widget again. In OMP mode, remove and add the widget again.

If you edit history manually, the file must stay within **32 KiB and 200 models**, and model names must not begin with `#`.

When asking for help, include your radio model, EdgeTX/FC/RF Tool versions, dashboard, helicopter type, counter choice and the exact message or symptom.

## Acknowledgments

Special thanks to Victor Malpica, Colin Bell, Martin Rottmair, and Tim Yantes for testing KSE4 and KSE5.

## Disclaimer

Use these dashboards entirely at your own risk. They are provided as-is, without warranties or guarantees of any kind. The author assumes zero liability for injury, crashes, loss of a model, property damage, data loss, incorrect telemetry, missed or incorrect warnings, configuration errors, software failure, or any other direct or indirect consequence arising from their installation, use, or misuse. You are solely responsible for verifying your radio, model, telemetry, alarms, motor safety, and failsafe configuration and for performing appropriate motor-disabled bench testing before flight.

Technical support is offered on a friendly, best-effort basis. I will help where my time and knowledge allow, but support may be limited and a response or resolution cannot be guaranteed. This project is not operated as a formal help desk or ticket-based support service, so users are encouraged to follow this guide carefully and share clear details when asking for help.
