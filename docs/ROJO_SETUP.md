# Getting Terra Forge into Roblox Studio

There are two ways. **Way A** is all you need to play and publish.
**Way B** (Rojo) is for when you keep changing code and want Studio to update live.

---

## Way A – just open the place file (easiest, no installs)

1. On GitHub, open the repository → folder `build` → `TerraForge.rbxl` → **Download raw file**.
2. Double-click `TerraForge.rbxl`. Roblox Studio opens it.
3. Press **Play** (F5). The map, lighting and all scripts are already inside.
4. To put it online: **File → Publish to Roblox**. Then follow `PUBLISHING.md`.

That file is rebuilt after every finished step, so it always matches the code.

---

## Way B – live sync with Rojo

Rojo copies the code from this folder into Studio while you work.

### 1. Install the tools (once)

**Easiest: VS Code**
1. Install [Visual Studio Code](https://code.visualstudio.com/).
2. In VS Code open the Extensions tab (left side, the four squares) and install
   **"Rojo - Roblox Studio Sync"** (publisher: evaera).
3. Open this project folder in VS Code (**File → Open Folder**).
4. Press `Ctrl+Shift+P` → type **Rojo: Open menu** → click **Install Roblox Studio plugin**.
   (Studio must be closed or restarted afterwards.)

**Or: command line (Rokit)**
1. Download Rokit from https://github.com/rojo-rbx/rokit/releases (Windows: the `windows-x86_64.zip`),
   unzip, run `rokit self-install` in a terminal.
2. In this project folder run `rokit install` → installs the exact Rojo/Lune versions from `rokit.toml`.
3. Run `rojo plugin install` → installs the Studio plugin.

### 2. Connect (every time you work)

1. Open `build/TerraForge.rbxl` in Studio (Way A, step 1–2). Keep it as your main place file.
2. Start the Rojo server:
   - VS Code: `Ctrl+Shift+P` → **Rojo: Open menu** → **default.project.json** → **Start**
   - or terminal: `rojo serve`
3. In Studio: **Plugins** tab → **Rojo** → **Connect** (address `localhost`, port `34872`).
4. Now every time you save a `.luau` file in `src/`, Studio updates within a second.
5. Remember to **File → Save to Roblox** (or Publish) in Studio when you are happy.

### Notes
- Rojo syncs scripts and the lighting objects. It does **not** touch `Workspace.Map`
  (the generated world), so your Studio edits to the map are safe.
- Two settings can't be changed by the plugin. They are already set in
  `TerraForge.rbxl`, but check them if you ever start from an empty place:
  **Lighting → Technology = Future** and **Workspace → StreamingEnabled = true**.
- If you build an empty place with only Rojo, the server builds the map by itself
  when you press Play (takes about 1 second).

---

## For developers: checks and rebuilding

```
bash tools/check.sh    # strict type-check against the Roblox API + unit tests + build
bash tools/build.sh    # only rebuild build/TerraForge.rbxl
node tools/preview/render.mjs world   # preview screenshots (needs `npm install` in tools/preview)
```
