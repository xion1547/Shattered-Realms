# Shattered-Realms
Roblox

## 📚 Documentation

Read these before changing anything structural. They exist so decisions are
made once instead of re-derived.

| Document | What it owns |
|---|---|
| [Gameplay-Design.md](docs/Gameplay-Design.md) | **What the game is and why it's fun.** Bosses, combat mitigation, relics, gauntlet, gacha, progression. Not how any of it is built. |
| [Architecture-Reference.md](docs/Architecture-Reference.md) | **How the server is built, and why.** The single source of truth for layers, services, entities, security, and every settled design decision. Read top to bottom when returning after time away. |
| [Client-Architecture.md](docs/Client-Architecture.md) | **How the client is built.** Widgets, bindings, presenters, prediction. The server document stays authoritative for anything crossing the wire. |
| [EventTape.md](docs/EventTape.md) | **The implementation map for the EventTape layer.** File map, end-to-end traces, wire protocol, and the recipe for adding an event type. Architecture Part 12 owns the *why*. |
| [HitDetection.md](docs/HitDetection.md) | **The spatial layer, design and implementation map.** Hit volumes, position history, lag-compensated rewind, and the DETECT phase. Self-contained — no Architecture Part owns this one. |
| [Hurtboxes.md](docs/Hurtboxes.md) | **The working manual for the thing that gets hit.** Starts from studs, `Vector3` and `CFrame`, then what a hurtbox is and the steps to author one by hand. HitDetection owns the *decision*; this owns the *procedure*. |
| [AssetPipeline.md](docs/AssetPipeline.md) | **Where everything actually lives.** DataModel containers, replication, cloud assets, and the Rojo path from Studio and Blender into git. Read before Animation or the hurtbox chapter. |
| [Animation.md](docs/Animation.md) | **Where animations live, how they are registered, and where gameplay may touch them.** The asset/id/track layers, who plays what, and why a marker never drives damage. |
| [Timeline.md](docs/Timeline.md) | **Property tracks over time.** Why Roblox's one animation player only bends joints, the module that will play everything else, and the editor that authors it. Conceptual. |
| [BossAI-HFSM.md](docs/BossAI-HFSM.md) | **Boss AI reasoning — conceptual, unbuilt.** Statechart model, combat reaction states, and what the first boss actually needs. A record of thinking, not a spec; read Part 7 before building. |
| [Client-Architecture-Handoff.md](docs/Client-Architecture-Handoff.md) | Cold-start primer that preceded the client document. Largely superseded by it. |
| [signalREADME.md](src/shared/utils/signal/signalREADME.md) | The Signal layer up close. |

**Status tags** (`SETTLED` / `PROVISIONAL` / `UNBUILT` / `SUPERSEDED`) appear
on every section of the architecture documents. They are the difference
between a decision that survived being attacked and one that merely sounds
good — read them.


# 🛠️ Setting Up Roblox Game Development with Rojo + VSCode

This guide walks you through setting up your development environment using **Rojo**,
**Visual Studio Code**, and **Roblox Studio** for a modular and scalable workflow.

---

## 📦 Requirements

- [✅] Roblox Studio
- [✅] Visual Studio Code
- [✅] Rojo (for syncing files)
- [✅] VSCode Rojo Plugin (optional, but useful)

---

## 🚀 Step-by-Step Setup

### 1. Install Roblox Studio
- Download and install Roblox Studio:  
  👉 [https://www.roblox.com/create](https://www.roblox.com/create)

---

### 2. Install Visual Studio Code
- Download and install VSCode:  
  👉 [https://code.visualstudio.com/](https://code.visualstudio.com/)

---

### 3. Install Rojo
Rojo is a tool that syncs your local files with Roblox Studio.

#### For Windows:
- Download the latest `.exe` release from GitHub:  
  👉 [https://github.com/rojo-rbx/rojo/releases](https://github.com/rojo-rbx/rojo/releases)
- Add it to your system PATH (optional but recommended).

- You probably want to download the Windows Version, then move it to a directory of your choice.
![image](https://github.com/user-attachments/assets/a8071d98-ab67-43d0-bb0d-5179c29aba59)


#### For macOS (using Homebrew):
```bash
brew install rojo-rbx/rojo/rojo
```

#### For Linux:
- Download the release from GitHub and follow installation instructions for your distro.

---

### 4. Install the Rojo VSCode Extension (Optional)
This extension provides syntax highlighting and easier Rojo file management.

- Open VSCode → Extensions (`Ctrl+Shift+X`)
- Search for `Rojo` and install the official extension by **rojo-rbx**

- Once Rojo is installed, add it to your System Environment Path so Rojo can be used in any terminal.
- Make sure the path is equal to where the executable file lives. Mine is in my C Drive, in a folder called Rojo.
- You can move the .exe file anywhere you'd like.

![System Variables](image-5.png)
![Rojo Path](image-6.png)

- Install these plugins they are mandatory:

![List of Plugins](image.png)

- THEN press Ctrl + Shift + P to open up the command in VsCode. You should see this:

![Command Menu in VsCode](image-1.png)

- Then click on Rojo Menu and click install Roblox Studio Plugin. You must have Roblox Studio open during this step.

![Rojo install plugin in Roblox Studio](image-2.png)

---

### 5. Set Up Your Project Structure

Your project folder might look like this:

```
MyGame/
├── default.project.json
├── src/
│   ├── client/
│   ├── server/
│   └── shared/
└── README.md
```

The `default.project.json` is what Rojo uses to map files to Roblox Studio.

Our default.project.json:
```json
"ReplicatedStorage": {
      "$path": "src/shared"
    },

    "ServerScriptService": {
      "Server": {
        "$path": "src/server"
      }
    },

    "StarterPlayer": {
      "StarterPlayerScripts": {
        "Client": {
          "$path": "src/client"
        }
      }
    },

    "StarterGui": {
      "UI": {
        "$path": "ui"
      }
    },
```

---

### 6. Start Rojo

In your terminal (within your project directory):

- Make sure you run rojo.serve in the command prompt inside your directory before you connect in Roblox Studio.
- This will open a local server and wait for Roblox Studio to connect.

![Rojo serve](image-4.png)

---

### 7. Connect Roblox Studio

- Once installed, you should see this in order to be able to sync Rojo and Roblox Studio:

![Rojo Menu in Roblox](image-3.png)


---

## 🧠 Tips

- 💾 Save changes in VSCode and see them reflect in Studio automatically.
- 🧪 You can use Studio for testing and live debugging, but **write and version all code in VSCode**.
- 🧩 Use Git to track your code history and collaborate effectively.

---

## Branching

- Make sure to make a branch named with whatever you like. Lets name the branch according to the current interation.
- Branch Name EX: Iteration-1_FixBug

---

## 🐛 Troubleshooting

- **Files not syncing?**
  - Make sure `rojo serve` is running.
  - Check your `default.project.json` for correct paths.
  - Ask Vantou
- **VSCode can’t find Rojo?**
  - Ensure Rojo is in your system’s PATH.
  - You can run it directly with the full path as a test.
  - Ask Vantou

---

Happy building! 🚀
