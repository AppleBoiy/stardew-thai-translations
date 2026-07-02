#!/usr/bin/env python3
"""
Stardew Valley Thai Translation Installer
------------------------------------------
- เลือกม็อดทีละตัวหรือทั้งหมด
- แต่ละม็อดเลือกได้ว่าจะใช้เวอร์ชันไหน (standard / extended / ...)
- รองรับ GUI (tkinter) ถ้ามี, ถ้าไม่มีใช้ TUI (ANSI terminal) แทน
"""

import os, re, glob, json, shutil, sys

# ─────────────────────────── constants ──────────────────────────────────────

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODS_SRC   = os.path.join(SCRIPT_DIR, "mods")

def _find_default_mods():
    home = os.path.expanduser("~")
    for p in [
        os.path.join(home, "Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS/Mods"),
        os.path.join(home, "Library/Application Support/Steam/steamapps/common/Stardew Valley/Mods"),
        os.path.join(home, ".steam/steam/steamapps/common/Stardew Valley/Mods"),
    ]:
        if os.path.isdir(p):
            return p
    return ""

DEFAULT_GAME_MODS = _find_default_mods()

# ─────────────────────────── shared helpers ──────────────────────────────────

def parse_json_with_comments(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    content = re.sub(r"(?<![:/])//[^\n]*", "", content)
    content = re.sub(r",(\s*[}\]])", r"\1", content)
    return json.loads(content)


def merge_and_build(base_path, overlay_path):
    base    = parse_json_with_comments(base_path)
    overlay = parse_json_with_comments(overlay_path)
    merged  = {**base, **overlay}
    merged.pop("$schema", None)
    lines = [
        "{",
        '  "$schema": "https://smapi.io/schemas/i18n.json",',
        "  // --- Translation Credit ---",
        "  // Translation provided by: GitHub: AppleBoiy",
        f"  // --- Merged: {os.path.basename(base_path)} + {os.path.basename(overlay_path)} ---",
    ]
    for i, (k, v) in enumerate(merged.items()):
        comma = "," if i < len(merged) - 1 else ""
        lines.append(f"  {json.dumps(k, ensure_ascii=False)}: {json.dumps(v, ensure_ascii=False)}{comma}")
    lines.append("}")
    return "\n".join(lines)


def scan_mods():
    result = []
    for folder_name in sorted(os.listdir(MODS_SRC)):
        mod_path = os.path.join(MODS_SRC, folder_name)
        if not os.path.isdir(mod_path):
            continue
        th_files   = glob.glob(os.path.join(mod_path, "**", "th*.json"), recursive=True)
        th_folders = glob.glob(os.path.join(mod_path, "**", "th", "*.*"),  recursive=True)
        if not th_files and not th_folders:
            continue

        manifests = glob.glob(os.path.join(mod_path, "**", "manifest.json"), recursive=True)
        display_name = folder_name
        if manifests:
            try:
                c = open(manifests[0], encoding="utf-8").read()
                n = re.search(r'"Name"\s*:\s*"([^"]+)"', c)
                if n: display_name = n.group(1)
            except Exception:
                pass

        base_th  = None
        variants = {}
        for f in th_files:
            bn = os.path.basename(f)
            if bn == "th.json":
                base_th = f
            else:
                m = re.match(r"th-(.+)\.json", bn)
                vname = m.group(1) if m else bn.replace("th","").replace(".json","")
                variants[vname] = f

        result.append({
            "folder_name":  folder_name,
            "display_name": display_name,
            "mod_path":     mod_path,
            "base_th":      base_th,
            "variants":     variants,
            "th_folders":   th_folders,
        })
    return result


def find_installed_mod(game_mods_dir, folder_name, display_name):
    """ค้นหาโฟลเดอร์ม็อดในเกม (ตรง / fuzzy ชื่อ)"""
    # 1. nested path (เช่น Mods/World Navigator/...)
    rel = os.path.relpath(
        glob.glob(os.path.join(MODS_SRC, folder_name, "**", "manifest.json"), recursive=True)[0]
        if glob.glob(os.path.join(MODS_SRC, folder_name, "**", "manifest.json"), recursive=True)
        else MODS_SRC + "/" + folder_name,
        MODS_SRC
    )
    nested = os.path.join(game_mods_dir, os.path.dirname(rel))
    if os.path.isdir(nested):
        return nested

    # 2. flat folder name
    flat = os.path.join(game_mods_dir, folder_name)
    if os.path.isdir(flat):
        return flat

    # 3. fuzzy by manifest Name
    for entry in os.listdir(game_mods_dir):
        ep = os.path.join(game_mods_dir, entry)
        if not os.path.isdir(ep): continue
        mf = os.path.join(ep, "manifest.json")
        if os.path.isfile(mf):
            try:
                c = open(mf, encoding="utf-8").read()
                n = re.search(r'"Name"\s*:\s*"([^"]+)"', c)
                if n and n.group(1).lower() == display_name.lower():
                    return ep
            except Exception:
                pass
    return None


PATCH_TARGETS = [
    {"id": "east_scarp", "display": "East Scarp", "hints": ["east scarp", "east scarp remastered"]},
    {"id": "eli_dylan", "display": "Eli and Dylan", "hints": ["eli and dylan", "novanpctest"]}
]

def patch_redundant_translations(game_mods_dir, selected_targets, log_fn):
    """ลบวงเล็บภาษาอังกฤษใน th.json ของม็อดที่เลือก"""
    th_files_1 = glob.glob(os.path.join(game_mods_dir, "**", "i18n", "th.json"), recursive=True)
    th_files_2 = glob.glob(os.path.join(game_mods_dir, "**", "i18n", "th", "*.json"), recursive=True)
    th_files = list(set(th_files_1 + th_files_2))
    
    if not th_files:
        log_fn("  ⚠️  ข้ามการแพตช์ (ไม่พบไฟล์ th.json ในโฟลเดอร์ม็อดเลย)", "warn")
        return

    pattern = re.compile(r'([\u0E00-\u0E7F]+)\s*\([A-Za-z0-9\s\.\-_\']+\)')
    total_files_patched = 0
    total_items_patched = 0

    for target in selected_targets:
        target_items_patched = 0
        hints_lower = [h.lower() for h in target["hints"]]
        
        target_th_files = [f for f in th_files if any(h in f.lower() for h in hints_lower)]
        
        if not target_th_files:
            log_fn(f"  ⚠️  ข้ามการแพตช์ {target['display']} (ไม่พบโฟลเดอร์ม็อด หรือไฟล์ th.json)", "dim")
            continue

        for th_path in target_th_files:
            try:
                with open(th_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                
                modified_count = 0
                for key, value in data.items():
                    if key.startswith("config."): continue
                    if isinstance(value, str):
                        new_value = pattern.sub(r'\1', value)
                        if new_value != value:
                            data[key] = new_value
                            modified_count += 1

                if modified_count > 0:
                    with open(th_path, 'w', encoding='utf-8') as f:
                        json.dump(data, f, ensure_ascii=False, indent=4)
                    total_files_patched += 1
                    target_items_patched += modified_count
            except Exception:
                pass
                
        if target_items_patched > 0:
            total_items_patched += target_items_patched
            log_fn(f"  ✅ แพตช์ {target['display']} สำเร็จ! (ลบวงเล็บไป {target_items_patched} จุด)", "ok")
        else:
            log_fn(f"  ✅ {target['display']} ปกติดี (ไม่พบวงเล็บที่ต้องลบ)", "dim")

    if total_items_patched > 0:
        log_fn(f"  🎉 แพตช์เสร็จสิ้น! (แก้ไขทั้งหมด {total_items_patched} จุด จาก {total_files_patched} ไฟล์)", "ok")


def do_inject(game_mods_dir, mod_info, variant_name, log_fn):
    fn           = mod_info["folder_name"]
    display_name = mod_info["display_name"]
    base_th      = mod_info["base_th"]
    variants     = mod_info["variants"]

    target_mod = find_installed_mod(game_mods_dir, fn, display_name)
    if not target_mod:
        log_fn(f"  ⚠️  '{display_name}' ไม่พบในโฟลเดอร์เกม — ข้าม", "warn")
        return False

    # Copy th/ asset folder
    for f in mod_info["th_folders"]:
        rel  = os.path.relpath(f, os.path.join(MODS_SRC, fn))
        dest = os.path.join(target_mod, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copy2(f, dest)

    # Locate i18n dir in game mod
    i18n_candidates = glob.glob(os.path.join(target_mod, "**", "i18n"), recursive=True)
    if i18n_candidates:
        i18n_target = i18n_candidates[0]
    elif base_th:
        i18n_target = os.path.join(
            target_mod,
            os.path.relpath(os.path.dirname(base_th), mod_info["mod_path"])
        )
    else:
        i18n_target = target_mod

    os.makedirs(i18n_target, exist_ok=True)
    dest_th = os.path.join(i18n_target, "th.json")

    if variant_name == "standard" or variant_name not in variants:
        if base_th:
            shutil.copy2(base_th, dest_th)
            log_fn(f"  ✅ {display_name} — th.json (มาตรฐาน)", "ok")
        else:
            log_fn(f"  ⚠️  {display_name} — ไม่มีไฟล์ th.json", "warn")
            return False
    else:
        overlay_path = variants[variant_name]
        if base_th:
            content = merge_and_build(base_th, overlay_path)
            with open(dest_th, "w", encoding="utf-8") as f:
                f.write(content)
            log_fn(f"  ✅ {display_name} — ผสาน th.json + th-{variant_name}.json", "ok")
        else:
            shutil.copy2(overlay_path, dest_th)
            log_fn(f"  ✅ {display_name} — th-{variant_name}.json", "ok")
    return True


# ══════════════════════════════════════════════════════════════════════════════
#  TUI  (ANSI — no external deps)
# ══════════════════════════════════════════════════════════════════════════════

class TUI:
    RST  = "\033[0m";  BOLD = "\033[1m";  DIM  = "\033[2m"
    GRN  = "\033[92m"; YLW  = "\033[93m"; CYN  = "\033[96m"
    RED  = "\033[91m"; BLU  = "\033[94m"

    def p(self, t=""):  print(t)
    def ok(self, t):    print(f"{self.GRN}{t}{self.RST}")
    def warn(self, t):  print(f"{self.YLW}{t}{self.RST}")
    def h1(self, t):    print(f"\n{self.BOLD}{self.CYN}{t}{self.RST}")
    def hr(self):       print(f"{self.DIM}{'─'*60}{self.RST}")

    def ask(self, prompt, default=""):
        try:
            v = input(f"{self.CYN}{prompt}{self.RST} ").strip()
            return v if v else default
        except (EOFError, KeyboardInterrupt):
            print(); sys.exit(0)

    def run(self):
        print(f"\n{self.BOLD}{self.BLU}{'='*52}{self.RST}")
        print(f"{self.BOLD}{self.BLU}  🌾 Stardew Valley Thai Translation Installer{self.RST}")
        print(f"{self.BOLD}{self.BLU}{'='*52}{self.RST}")

        # ── Game mods path ──
        self.h1("📂 โฟลเดอร์ Mods ของเกม")
        prompt = f"กด Enter เพื่อใช้ค่าตั้งต้น หรือพิมพ์/ลากโฟลเดอร์ Mods มาวางที่นี่:\n  [{DEFAULT_GAME_MODS or 'ยังไม่พบ'}]"
        game_dir = self.ask(prompt, DEFAULT_GAME_MODS).replace("\\ ", " ").strip("'\"")
        if not os.path.isdir(game_dir):
            self.warn(f"ไม่พบโฟลเดอร์: {game_dir}")
            sys.exit(1)
        self.ok(f"  ✔ ใช้: {game_dir}")

        mods = scan_mods()
        if not mods:
            self.warn("ไม่พบม็อดใน mods/"); sys.exit(1)

        # ── Mod selection ──
        enabled  = {m["folder_name"]: True for m in mods}
        variants = {}
        for m in mods:
            all_v = ["standard"] + list(m["variants"].keys())
            variants[m["folder_name"]] = {"all": all_v, "chosen": all_v[0]}

        def show_list():
            self.hr()
            for i, m in enumerate(mods, 1):
                fn   = m["folder_name"]
                chk  = f"{self.GRN}[✓]{self.RST}" if enabled[fn] else f"{self.DIM}[ ]{self.RST}"
                vari = variants[fn]["chosen"]
                all_v = variants[fn]["all"]
                vsuf = ""
                if len(all_v) > 1:
                    parts = [f"{self.BOLD}{v}{self.RST}" if v == vari else f"{self.DIM}{v}{self.RST}"
                             for v in all_v]
                    vsuf = f"  [{'/'.join(parts)}]"
                print(f"  {self.CYN}{i:2d}{self.RST}. {chk} {m['display_name']}{vsuf}")
            self.hr()
            print(f"  {self.DIM}[หมายเลข] เปิด/ปิด  |  [v<n>] เปลี่ยนเวอร์ชัน  |  [a] ทั้งหมด  |  [n] ยกเลิกทั้งหมด{self.RST}")
            print(f"  {self.DIM}[ok] ติดตั้ง  |  [q] ออก{self.RST}")

        status_msg = ""
        while True:
            os.system('clear' if os.name == 'posix' else 'cls')
            print(f"\n{self.BOLD}{self.BLU}{'='*52}{self.RST}")
            print(f"{self.BOLD}{self.BLU}  🌾 Stardew Valley Thai Translation Installer{self.RST}")
            print(f"{self.BOLD}{self.BLU}{'='*52}{self.RST}")
            
            self.h1("🗂️  เลือกม็อดที่ต้องการติดตั้ง")
            show_list()
            
            if status_msg:
                print(status_msg)
                status_msg = ""
                
            cmd = self.ask("คำสั่ง:").lower()

            if cmd == "q":
                sys.exit(0)
            elif cmd == "ok":
                break
            elif cmd == "a":
                for fn in enabled: enabled[fn] = True
                status_msg = f"{self.GRN}  ✔ เลือกทั้งหมดแล้ว{self.RST}"
            elif cmd == "n":
                for fn in enabled: enabled[fn] = False
                status_msg = f"{self.YLW}  ✔ ยกเลิกทั้งหมดแล้ว{self.RST}"
            elif cmd.startswith("v") and cmd[1:].isdigit():
                idx = int(cmd[1:]) - 1
                if 0 <= idx < len(mods):
                    fn    = mods[idx]["folder_name"]
                    all_v = variants[fn]["all"]
                    if len(all_v) == 1:
                        status_msg = f"{self.YLW}  ⚠️ ม็อดนี้มีแค่เวอร์ชันมาตรฐาน{self.RST}"; continue
                    print("  เวอร์ชันที่มี: " + "  ".join(
                        f"{self.CYN}{j+1}{self.RST}={v}" for j, v in enumerate(all_v)))
                    pick = self.ask(f"  เลือกหมายเลข (ปัจจุบัน: {variants[fn]['chosen']}):")
                    if pick.isdigit() and 1 <= int(pick) <= len(all_v):
                        variants[fn]["chosen"] = all_v[int(pick)-1]
                        status_msg = f"{self.GRN}  ✔ เปลี่ยนเป็น '{variants[fn]['chosen']}'{self.RST}"
                    else:
                        status_msg = f"{self.YLW}  ⚠️ หมายเลขไม่ถูกต้อง{self.RST}"
                else:
                    status_msg = f"{self.YLW}  ⚠️ หมายเลขม็อดไม่ถูกต้อง{self.RST}"
            elif cmd.isdigit():
                idx = int(cmd) - 1
                if 0 <= idx < len(mods):
                    fn = mods[idx]["folder_name"]
                    enabled[fn] = not enabled[fn]
                    state_str = 'เปิด' if enabled[fn] else 'ปิด'
                    status_msg = f"{self.GRN}  ✔ {mods[idx]['display_name']} → {state_str}{self.RST}"
                else:
                    status_msg = f"{self.YLW}  ⚠️ หมายเลขเกินช่วง{self.RST}"
            else:
                status_msg = f"{self.YLW}  ⚠️ คำสั่งไม่รู้จัก{self.RST}"

        # ── Install ──
        selected = [(m, variants[m["folder_name"]]["chosen"])
                    for m in mods if enabled[m["folder_name"]]]

        print(f"\n{self.CYN}ต้องการแพตช์ลบวงเล็บภาษาอังกฤษซ้ำซ้อนในม็อดใดบ้าง?{self.RST}")
        for i, target in enumerate(PATCH_TARGETS):
            print(f"  {self.CYN}{i+1}{self.RST}. {target['display']}")
        patch_input = self.ask(f"ระบุหมายเลข (เช่น 1,2 หรือเว้นว่างเพื่อข้าม):").strip()
        
        selected_patches = []
        if patch_input:
            parts = [p.strip() for p in patch_input.split(',')]
            for p in parts:
                if p.isdigit() and 1 <= int(p) <= len(PATCH_TARGETS):
                    selected_patches.append(PATCH_TARGETS[int(p)-1])

        if not selected and not selected_patches:
            self.warn("ไม่ได้เลือกม็อดใดและไม่ต้องการแพตช์ — ยกเลิก"); sys.exit(0)

        if selected:
            self.h1(f"🚀 กำลังติดตั้ง {len(selected)} ม็อด…")
        else:
            self.h1("🚀 ข้ามการติดตั้งม็อด (ดำเนินการแพตช์อย่างเดียว)…")
        self.hr()

        def log_fn(msg, tag=""):
            if tag == "ok":    self.ok(msg)
            elif tag == "warn": self.warn(msg)
            else:              self.p(msg)

        ok_n = err_n = 0
        for mod, variant in selected:
            if do_inject(game_dir, mod, variant, log_fn): ok_n  += 1
            else:                                         err_n += 1

        if selected_patches:
            log_fn("\n🛠️  กำลังสแกนและแพตช์คำแปลของม็อดที่เลือก...")
            patch_redundant_translations(game_dir, selected_patches, log_fn)

        self.hr()
        if err_n == 0:
            self.ok(f"✅ ติดตั้งสำเร็จ {ok_n}/{len(selected)} ม็อด")
        else:
            self.warn(f"⚠️  ติดตั้งสำเร็จ {ok_n}/{len(selected)} ม็อด  (ไม่สำเร็จ {err_n})")

        try: input("\nกด Enter เพื่อปิด...")
        except Exception: pass


# ══════════════════════════════════════════════════════════════════════════════
#  GUI  (tkinter)
# ══════════════════════════════════════════════════════════════════════════════

def launch_gui():
    import tkinter as tk
    from tkinter import ttk, messagebox, filedialog

    class App(tk.Tk):
        # 🌙 Soft Warm Dark Theme
        BG_C   = "#1C1C1E"  # Base background
        SURF   = "#2C2C2E"  # Surface (Main panels)
        SURF2  = "#3A3A3C"  # Secondary surface (Alt rows, inputs)
        FG     = "#F2F2F7"  # Primary Text
        FGD    = "#AEAEB2"  # Dim Text
        
        # Accents
        ACCENT = "#34C759"  # iOS Green (Primary Action)
        ACC2   = "#0A84FF"  # iOS Blue (Secondary Action)
        WRN    = "#FF453A"  # Error/Warning Red
        SUC    = "#32D74B"  # Success Green

        def __init__(self):
            super().__init__()
            self.title("🌾 Stardew Valley Thai Translation Installer")
            self.configure(bg=self.BG_C)
            self.resizable(True, True)
            self.minsize(800, 560)
            self.game_mods_dir = tk.StringVar(value=DEFAULT_GAME_MODS)
            self.mods = scan_mods()
            self.mod_state = {}
            for m in self.mods:
                all_v = ["standard"] + list(m["variants"].keys())
                self.mod_state[m["folder_name"]] = {
                    "enabled": tk.BooleanVar(value=True),
                    "variant": tk.StringVar(value=all_v[0]),
                    "all_variants": all_v,
                }
            self.patch_targets = { t["id"]: tk.BooleanVar(value=False) for t in PATCH_TARGETS }
            self._build()
            self.geometry("900x680")
            
            # Center window on screen
            self.update_idletasks()
            width = self.winfo_width()
            frm_width = self.winfo_rootx() - self.winfo_x()
            win_width = width + 2 * frm_width
            height = self.winfo_height()
            titlebar_height = self.winfo_rooty() - self.winfo_y()
            win_height = height + titlebar_height + frm_width
            x = self.winfo_screenwidth() // 2 - win_width // 2
            y = self.winfo_screenheight() // 2 - win_height // 2
            self.geometry(f"{width}x{height}+{x}+{y}")

        def _style(self):
            s = ttk.Style(self); s.theme_use("clam")
            s.configure(".", background=self.BG_C, foreground=self.FG, font=("SF Pro Display", 13))
            s.configure("TFrame", background=self.BG_C)
            s.configure("Surf.TFrame", background=self.SURF)
            s.configure("Surf2.TFrame", background=self.SURF2)
            s.configure("TLabel", background=self.BG_C, foreground=self.FG)
            s.configure("Dim.TLabel", background=self.BG_C, foreground=self.FGD, font=("SF Pro Display", 11))
            s.configure("H1.TLabel", background=self.SURF, foreground=self.FG, font=("SF Pro Display", 18, "bold"))
            s.configure("TCombobox", fieldbackground=self.SURF2, background=self.SURF2, foreground=self.FG, selectbackground=self.ACC2, selectforeground="#fff", borderwidth=0, arrowcolor=self.FG)
            s.configure("TScrollbar", gripcount=0, background=self.SURF, darkcolor=self.BG_C, lightcolor=self.BG_C, troughcolor=self.BG_C, bordercolor=self.BG_C, arrowcolor=self.FG)

        def _btn(self, parent, text, cmd, fg, bg=None, **kw):
            bg = bg or self.SURF2
            return tk.Button(parent, text=text, command=cmd, bg=bg, fg=fg, activebackground=self.SURF, activeforeground=fg, relief="flat", bd=0, cursor="hand2", font=("SF Pro Display", 12), padx=14, pady=6, **kw)

        def _build(self):
            self._style()

            # Title bar
            top = ttk.Frame(self, style="Surf.TFrame", padding=(24, 16))
            top.pack(fill=tk.X)
            ttk.Label(top, text="🌾 Thai Translation Installer", style="H1.TLabel").pack(side=tk.LEFT)
            ttk.Label(top, text="by AppleBoiy", style="Dim.TLabel", background=self.SURF).pack(side=tk.LEFT, padx=12, pady=(6,0))

            # Main container with padding
            main_container = ttk.Frame(self, padding=(24, 16, 24, 24))
            main_container.pack(fill=tk.BOTH, expand=True)

            # Path row
            pf = ttk.Frame(main_container)
            pf.pack(fill=tk.X, pady=(0, 16))
            ttk.Label(pf, text="📂 โฟลเดอร์เกม:").pack(side=tk.LEFT)
            tk.Entry(pf, textvariable=self.game_mods_dir, bg=self.SURF2, fg=self.FG, insertbackground=self.FG, relief="flat", font=("SF Mono", 12), bd=8).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(12, 8))
            self._btn(pf, "เลือก...", self._browse, self.ACC2).pack(side=tk.LEFT)

            # Controls
            ctrl = ttk.Frame(main_container)
            ctrl.pack(fill=tk.X, pady=(0, 12))
            self._btn(ctrl, "✅ เลือกทั้งหมด", self._all, self.SUC).pack(side=tk.LEFT, padx=(0, 8))
            self._btn(ctrl, "⬜ ยกเลิกทั้งหมด", self._none, self.FGD).pack(side=tk.LEFT)
            self._btn(ctrl, "🔄 รีเฟรช", self._refresh, self.ACC2).pack(side=tk.RIGHT)

            # Mod list
            lo = tk.Frame(main_container, bg=self.BG_C, bd=1, relief="flat", highlightbackground=self.SURF2, highlightthickness=1)
            lo.pack(fill=tk.BOTH, expand=True, pady=(0, 16))
            canvas = tk.Canvas(lo, bg=self.BG_C, highlightthickness=0)
            scroll = ttk.Scrollbar(lo, orient="vertical", command=canvas.yview)
            canvas.configure(yscrollcommand=scroll.set)
            scroll.pack(side=tk.RIGHT, fill=tk.Y)
            canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
            self.mlf = tk.Frame(canvas, bg=self.BG_C)
            self._cw = canvas.create_window((0, 0), window=self.mlf, anchor="nw")
            self.mlf.bind("<Configure>", lambda e: (canvas.configure(scrollregion=canvas.bbox("all")), canvas.itemconfig(self._cw, width=canvas.winfo_width())))
            canvas.bind("<Configure>", lambda e: canvas.itemconfig(self._cw, width=e.width))
            def _on_mousewheel(e):
                delta = e.delta if sys.platform == "darwin" else e.delta / 120
                canvas.yview_scroll(int(-1 * delta), "units")
            canvas.bind_all("<MouseWheel>", _on_mousewheel)
            self._populate()

            # Extra Options
            opt_container = ttk.Frame(main_container, padding=(0, 8))
            opt_container.pack(fill=tk.X)
            ttk.Label(opt_container, text="🛠️ ตัวเลือกเสริม: ลบวงเล็บภาษาอังกฤษซ้ำซ้อนในม็อดต่อไปนี้", style="Dim.TLabel").pack(anchor=tk.W, pady=(0, 4))
            for target in PATCH_TARGETS:
                tk.Checkbutton(opt_container, text=target["display"], variable=self.patch_targets[target["id"]], bg=self.BG_C, fg=self.ACCENT, selectcolor=self.SURF, activebackground=self.BG_C, activeforeground=self.ACCENT, cursor="hand2", font=("SF Pro Display", 13)).pack(anchor=tk.W, padx=(16, 0))

            # Bottom container (Log + Install Button)
            bot_container = ttk.Frame(main_container)
            bot_container.pack(fill=tk.X)

            # Log
            ttk.Label(bot_container, text="📋 สถานะการติดตั้ง:", style="Dim.TLabel").pack(anchor=tk.W, pady=(0, 4))
            self.log = tk.Text(bot_container, height=6, bg=self.SURF, fg=self.FG, insertbackground=self.FG, relief="flat", font=("SF Mono", 11), state="disabled", bd=10)
            self.log.pack(fill=tk.X, pady=(0, 16))
            self.log.tag_configure("ok", foreground=self.SUC)
            self.log.tag_configure("warn", foreground=self.WRN)
            self.log.tag_configure("dim", foreground=self.FGD)

            # Install button
            self.ibtn = tk.Button(bot_container, text="🚀  ติดตั้งคำแปลที่เลือก", command=self._install, bg=self.ACCENT, fg="#000000", activebackground="#28A745", activeforeground="#000000", relief="flat", bd=0, cursor="hand2", font=("SF Pro Display", 15, "bold"), padx=24, pady=12)
            self.ibtn.pack(fill=tk.X)

        def _populate(self):
            for w in self.mlf.winfo_children(): w.destroy()
            for i, mod in enumerate(self.mods):
                fn = mod["folder_name"]
                state = self.mod_state[fn]
                bg = self.SURF if i % 2 == 0 else self.BG_C
                
                row = tk.Frame(self.mlf, bg=bg)
                row.pack(fill=tk.X)
                
                # Custom Checkbox via Label
                chk_lbl = tk.Label(row, bg=bg, fg=self.ACCENT if state["enabled"].get() else self.FGD, font=("Arial", 18), cursor="hand2", width=3, pady=8)
                chk_lbl.pack(side=tk.LEFT, padx=(8, 0))
                
                def toggle(e, s=state, l=chk_lbl):
                    s["enabled"].set(not s["enabled"].get())
                    l.config(text="◉" if s["enabled"].get() else "◯", fg=self.ACCENT if s["enabled"].get() else self.FGD)
                
                chk_lbl.config(text="◉" if state["enabled"].get() else "◯")
                chk_lbl.bind("<Button-1>", toggle)

                # Mod Name (also clickable to toggle)
                name_lbl = tk.Label(row, text=mod["display_name"], bg=bg, fg=self.FG, font=("SF Pro Display", 13), cursor="hand2", anchor="w", pady=8)
                name_lbl.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=4)
                name_lbl.bind("<Button-1>", toggle)
                
                all_v = state["all_variants"]
                if len(all_v) > 1:
                    tk.Label(row, text="เวอร์ชัน:", bg=bg, fg=self.FGD, font=("SF Pro Display", 12)).pack(side=tk.RIGHT, padx=(0, 4))
                    
                    # Style combobox briefly
                    cb = ttk.Combobox(row, textvariable=state["variant"], values=all_v, state="readonly", width=12, font=("SF Pro Display", 12))
                    cb.pack(side=tk.RIGHT, padx=(0, 16))
                else:
                    tk.Label(row, text="มาตรฐาน", bg=bg, fg=self.FGD, font=("SF Pro Display", 12), padx=16).pack(side=tk.RIGHT)

        def _browse(self):
            d = filedialog.askdirectory(title="เลือกโฟลเดอร์ Mods", initialdir=self.game_mods_dir.get())
            if d: self.game_mods_dir.set(d)

        def _all(self):
            for s in self.mod_state.values(): s["enabled"].set(True)
            self._populate()

        def _none(self):
            for s in self.mod_state.values(): s["enabled"].set(False)
            self._populate()

        def _refresh(self):
            self.mods = scan_mods()
            for m in self.mods:
                fn = m["folder_name"]
                if fn not in self.mod_state:
                    all_v = ["standard"] + list(m["variants"].keys())
                    self.mod_state[fn] = {"enabled": tk.BooleanVar(value=True), "variant": tk.StringVar(value=all_v[0]), "all_variants": all_v}
            self._populate()
            self._log("🔄 รีเฟรชแล้ว", "dim")

        def _log(self, t, tag=""):
            self.log.configure(state="normal")
            self.log.insert(tk.END, t + "\n", tag)
            self.log.see(tk.END)
            self.log.configure(state="disabled")

        def _install(self):
            game_dir = self.game_mods_dir.get().strip()
            if not os.path.isdir(game_dir):
                messagebox.showerror("ไม่พบโฟลเดอร์", f"ไม่พบ:\n{game_dir}"); return
            selected = [(m, self.mod_state[m["folder_name"]]["variant"].get()) for m in self.mods if self.mod_state[m["folder_name"]]["enabled"].get()]
            
            selected_patches = [t for t in PATCH_TARGETS if self.patch_targets[t["id"]].get()]
            
            if not selected and not selected_patches:
                messagebox.showwarning("ยังไม่ได้เลือก", "กรุณาเลือกม็อดอย่างน้อย 1 ตัว หรือติ๊กเลือกแพตช์เสริม"); return
            self.ibtn.configure(state="disabled", text="⏳ กำลังทำงาน...")
            self.update()
            
            if selected:
                self._log(f"\n📦 ติดตั้ง {len(selected)} ม็อด...")
            else:
                self._log("\n📦 ข้ามการติดตั้งม็อด...")
            ok_n = err_n = 0
            for mod, variant in selected:
                if do_inject(game_dir, mod, variant, lambda msg, tag="": self._log(msg, tag)): ok_n += 1
                else: err_n += 1
                
            if selected_patches:
                self._log("\n🛠️  กำลังสแกนและแพตช์คำแปลของม็อดที่เลือก...")
                patch_redundant_translations(game_dir, selected_patches, lambda msg, tag="": self._log(msg, tag))
                
            tag = "ok" if err_n == 0 else "warn"
            if selected:
                self._log(f"\n{'✅' if err_n == 0 else '⚠️'} ติดตั้ง {ok_n}/{len(selected)} ม็อด", tag)
            self.ibtn.configure(state="normal", text="🚀  ดำเนินการตามที่เลือก")
            if err_n == 0:
                msg = f"ติดตั้งครบ {ok_n} ม็อดแล้ว!\n" if selected else "การดำเนินการเสร็จสิ้น!\n"
                if selected_patches: msg += "(และแพตช์คำแปลเรียบร้อย)\n"
                messagebox.showinfo("สำเร็จ 🎉", msg + "เริ่มเกมได้เลยครับ 🌾")

    App().mainloop()


# ══════════════════════════════════════════════════════════════════════════════
#  Entry point — GUI ถ้าได้, TUI ถ้าไม่ได้
# ══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    try:
        import tkinter as _tk
        _r = _tk.Tk(); _r.withdraw(); _r.destroy()
        launch_gui()
    except Exception:
        TUI().run()
