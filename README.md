# Ember

[![CI](https://github.com/jonathanhu237/ember/actions/workflows/ci.yml/badge.svg)](https://github.com/jonathanhu237/ember/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

A small macOS menu bar app that keeps your Mac working when it should, and lets it sleep when it shouldn't.

*The screen goes dark, the work keeps glowing.*

## What it does

Ember watches three things: the power source, the lid, and the connected displays. For each power source you choose what it should do:

| Setting | On power (default) | On battery (default) |
|---|---|---|
| Keep Mac awake | ✅ | — |
| Keep display on | ✅ | — |
| Keep running with lid closed | ✅ | — |
| Turn displays off when lid closes | ✅ | — |

With the defaults:

- **On battery**, the Mac behaves like a normal laptop. Close the lid and it sleeps, safe to put in a bag.
- **Plugged in, lid open**, the Mac and its display stay awake.
- **Plugged in, lid closed**, the Mac keeps running and every display is put to sleep (this needs [closed-lid support](#closed-lid-support)). Monitors that power the Mac over USB-C keep doing so in standby. If a display wakes up again (a jittery wireless mouse, say), Ember puts it back to sleep after 30 idle seconds.
- **Unplugged with the lid already closed**, Ember lets go and puts the Mac to sleep.
- On battery you can also set a charge floor below which Ember stops.

The interface is in English and Simplified Chinese and follows the system language.
To pick a language for Ember alone, use System Settings → General → Language & Region → Applications.

## Install

Download `Ember.zip` from the [latest release](https://github.com/jonathanhu237/ember/releases), unzip it and move **Ember.app** to Applications.

Ember is not notarized yet, so the first launch is blocked by Gatekeeper. Either open it once from System Settings → Privacy & Security → **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Ember.app
```

Then turn on **Launch at Login** from the menu.

## Closed-lid support

On its own, macOS keeps a closed Mac running only while an external display is connected **and awake**. The moment the last one sleeps, it enters "Clamshell Sleep". So both of these need the system-wide `pmset disablesleep` flag, which only root can change:

- turning the displays off while the lid is closed, and
- keeping the Mac running with the lid closed and no external display.

Until it is set up, Ember keeps an external display awake while the lid is closed, so the Mac keeps running, and the menu says so. **Set Up Closed-Lid Support…** asks for your password once and installs:

- `/etc/sudoers.d/ember-<uid>`: lets your user run exactly `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password, and nothing else. It is checked with `visudo` before it is installed.
- `~/Library/LaunchAgents/dev.ember.watchdog.plist`: a user-level job that runs every 30 seconds. If Ember is no longer running while it had the flag on, the job turns the flag back off, so a crash never leaves the Mac unable to sleep.

Ember turns the flag on only while a profile asks for it and turns it off as soon as that stops (for example when you unplug). It never resets a flag that another tool set. **Remove Closed-Lid Support…** undoes all of it.

If something ever goes wrong, this restores normal sleep:

```sh
sudo pmset -a disablesleep 0
```

## Build

Requires Xcode 16 or later and [mise](https://mise.jdx.dev) (for XcodeGen).

```sh
scripts/build.sh Debug              # test + build
scripts/build.sh Release --install  # build, copy to /Applications, launch
```

The decision logic lives in the `EmberCore` Swift package and is covered by unit tests:

```sh
cd EmberCore && swift test
```

## Layout

- `EmberCore/`: pure policy (`Policy.decide`) and models, with tests
- `Ember/System/`: reading power, lid, display and idle state; power assertions; `pmset`; the closed-lid helper
- `Ember/AppModel.swift`: the loop that reads state, asks the policy and applies the result
- `Ember/MenuContent.swift`: the menu
- `Ember/Localizable.xcstrings`: English and Simplified Chinese strings
