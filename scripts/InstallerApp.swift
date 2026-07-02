import SwiftUI
import Combine

struct PatchTarget: Identifiable {
    let id: String
    let name: String
    let hints: [String]
    var isEnabled: Bool = false
}

struct ModVariant: Hashable {
    let folderName: String
    let name: String
}

struct ModItem: Identifiable {
    let id = UUID()
    let folderName: String
    let variants: [ModVariant]
    var isEnabled: Bool = true
    var selectedVariant: ModVariant
}

@main
struct StardewThaiInstallerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}

class InstallerViewModel: ObservableObject {
    @Published var gameDir: String = ""
    @Published var mods: [ModItem] = []
    @Published var patches: [PatchTarget] = [
        PatchTarget(id: "east_scarp", name: "East Scarp (ลบวงเล็บภาษาอังกฤษหลังชื่อ)", hints: ["east scarp"]),
        PatchTarget(id: "eli_and_dylan", name: "Eli and Dylan (ลบวงเล็บภาษาอังกฤษหลังชื่อ)", hints: ["eli and dylan", "novanpctest"])
    ]
    @Published var logs: String = ""
    @Published var isWorking: Bool = false
    
    init() {
        self.gameDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS/Mods")
        self.loadMods()
    }
    
    func log(_ message: String) {
        DispatchQueue.main.async {
            self.logs += message + "\n"
        }
    }
    
    func selectGameDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let currentURL = URL(string: gameDir) {
            panel.directoryURL = currentURL
        }
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                self.gameDir = url.path
            }
        }
    }
    
    func loadMods() {
        let fm = FileManager.default
        let bundlePath = Bundle.main.bundlePath
        // In dev it's next to the script, in bundle it's in Resources/core
        var baseDir = URL(fileURLWithPath: bundlePath).deletingLastPathComponent().path
        if bundlePath.hasSuffix(".app") {
            baseDir = (bundlePath as NSString).appendingPathComponent("Contents/Resources/core")
        }
        
        let modsDir = (baseDir as NSString).appendingPathComponent("mods")
        
        guard let dirs = try? fm.contentsOfDirectory(atPath: modsDir) else {
            log("⚠️ ไม่พบโฟลเดอร์ mods ที่ \(modsDir)")
            return
        }
        
        var loadedMods: [ModItem] = []
        for d in dirs {
            if d.hasPrefix(".") { continue }
            let modPath = (modsDir as NSString).appendingPathComponent(d)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: modPath, isDirectory: &isDir) && isDir.boolValue {
                // Find variants
                if let subdirs = try? fm.contentsOfDirectory(atPath: modPath) {
                    var variants: [ModVariant] = []
                    for sd in subdirs {
                        if sd.hasPrefix(".") { continue }
                        let sdPath = (modPath as NSString).appendingPathComponent(sd)
                        if fm.fileExists(atPath: sdPath, isDirectory: &isDir) && isDir.boolValue {
                            variants.append(ModVariant(folderName: sd, name: sd))
                        }
                    }
                    if !variants.isEmpty {
                        loadedMods.append(ModItem(folderName: d, variants: variants, selectedVariant: variants[0]))
                    } else {
                        // Single mod without explicit variant folders? We assume variant is root
                        variants.append(ModVariant(folderName: "", name: "Default"))
                        loadedMods.append(ModItem(folderName: d, variants: variants, selectedVariant: variants[0]))
                    }
                }
            }
        }
        self.mods = loadedMods.sorted { $0.folderName < $1.folderName }
    }
    
    func startInstall() {
        isWorking = true
        logs = ""
        log("🚀 เริ่มการทำงาน...")
        
        let selectedMods = mods.filter { $0.isEnabled }
        let selectedPatches = patches.filter { $0.isEnabled }
        
        let gDir = self.gameDir
        
        DispatchQueue.global(qos: .userInitiated).async {
            var okCount = 0
            
            // 1. Install Mods
            if !selectedMods.isEmpty {
                self.log("📦 ติดตั้ง \(selectedMods.count) ม็อด...")
                for mod in selectedMods {
                    if self.doInject(gameDir: gDir, mod: mod) {
                        okCount += 1
                    }
                }
                self.log("✅ ติดตั้งสำเร็จ \(okCount)/\(selectedMods.count) ม็อด")
            }
            
            // 2. Apply Patches
            if !selectedPatches.isEmpty {
                self.log("🛠️ กำลังสแกนและแพตช์คำแปลของม็อดที่เลือก...")
                self.patchRedundantTranslations(gameDir: gDir, selectedPatches: selectedPatches)
            }
            
            DispatchQueue.main.async {
                self.isWorking = false
                self.log("🎉 การดำเนินการเสร็จสิ้น! เริ่มเกมได้เลยครับ 🌾")
            }
        }
    }
    
    func doInject(gameDir: String, mod: ModItem) -> Bool {
        let fm = FileManager.default
        let bundlePath = Bundle.main.bundlePath
        var baseDir = URL(fileURLWithPath: bundlePath).deletingLastPathComponent().path
        if bundlePath.hasSuffix(".app") {
            baseDir = (bundlePath as NSString).appendingPathComponent("Contents/Resources/core")
        }
        
        let srcBase = (baseDir as NSString).appendingPathComponent("mods")
        var srcDir = (srcBase as NSString).appendingPathComponent(mod.folderName)
        if !mod.selectedVariant.folderName.isEmpty {
            srcDir = (srcDir as NSString).appendingPathComponent(mod.selectedVariant.folderName)
        }
        
        let destBase = gameDir
        
        guard let items = try? fm.contentsOfDirectory(atPath: srcDir) else {
            self.log("❌ ข้าม \(mod.folderName): ไม่พบไฟล์ต้นฉบับ")
            return false
        }
        
        var hasError = false
        for item in items {
            let srcPath = (srcDir as NSString).appendingPathComponent(item)
            let destPath = (destBase as NSString).appendingPathComponent(item)
            
            do {
                if fm.fileExists(atPath: destPath) {
                    try fm.removeItem(atPath: destPath)
                }
                try fm.copyItem(atPath: srcPath, toPath: destPath)
            } catch {
                self.log("❌ ก๊อปปี้ \(item) ไม่สำเร็จ: \(error.localizedDescription)")
                hasError = true
            }
        }
        
        if !hasError {
            self.log("  ✅ \(mod.folderName) -> \(mod.selectedVariant.name)")
        }
        return !hasError
    }
    
    func patchRedundantTranslations(gameDir: String, selectedPatches: [PatchTarget]) {
        let fm = FileManager.default
        let enumerator = fm.enumerator(atPath: gameDir)
        var thFiles: [String] = []
        
        while let file = enumerator?.nextObject() as? String {
            if file.contains("i18n/th") && file.hasSuffix(".json") {
                thFiles.append(file)
            }
        }
        
        let regexPattern = "([\\u0E00-\\u0E7F]+)\\s*\\([A-Za-z0-9\\s\\.\\-_\\']+\\)"
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else { return }
        
        var filesPatched = 0
        var itemsPatched = 0
        
        for file in thFiles {
            let fullPath = (gameDir as NSString).appendingPathComponent(file)
            let lowerPath = fullPath.lowercased()
            
            // Check if matches any selected patch target
            var shouldPatch = false
            for patch in selectedPatches {
                for hint in patch.hints {
                    if lowerPath.contains(hint) {
                        shouldPatch = true
                        break
                    }
                }
                if shouldPatch { break }
            }
            
            if !shouldPatch { continue }
            
            if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                let nsString = content as NSString
                let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
                
                if !matches.isEmpty {
                    let newContent = regex.stringByReplacingMatches(in: content, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: "$1")
                    do {
                        try newContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
                        filesPatched += 1
                        itemsPatched += matches.count
                    } catch {
                        self.log("❌ ไม่สามารถบันทึกไฟล์ \(file)")
                    }
                }
            }
        }
        
        if itemsPatched > 0 {
            self.log("  ✨ แพตช์สำเร็จ: พบและลบวงเล็บไปทั้งหมด \(itemsPatched) จุด (ใน \(filesPatched) ไฟล์)")
        } else {
            self.log("  ⚠️ ไม่พบข้อความที่ต้องแพตช์ในม็อดที่เลือก")
        }
    }
}

struct ContentView: View {
    @StateObject var vm = InstallerViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("🌾 Stardew Valley Thai Translation Installer")
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            VStack(spacing: 20) {
                // Game Directory
                VStack(alignment: .leading, spacing: 5) {
                    Text("📂 โฟลเดอร์เกม:").font(.headline).bold()
                    HStack {
                        TextField("Game Directory", text: $vm.gameDir)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button("เลือก...") {
                            vm.selectGameDir()
                        }
                    }
                }
                
                // Content (Mods & Patches)
                HStack(alignment: .top, spacing: 20) {
                    
                    // Mods
                    VStack(alignment: .leading) {
                        HStack {
                            Text("📦 เลือกม็อดที่จะติดตั้ง").font(.headline)
                            Spacer()
                            Button("เลือกทั้งหมด") { for i in 0..<vm.mods.count { vm.mods[i].isEnabled = true } }
                            Button("ยกเลิก") { for i in 0..<vm.mods.count { vm.mods[i].isEnabled = false } }
                        }
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                if vm.mods.isEmpty {
                                    Text("ไม่พบม็อดในโฟลเดอร์ mods/").foregroundColor(.secondary)
                                }
                                ForEach($vm.mods) { $mod in
                                    HStack {
                                        Toggle(isOn: $mod.isEnabled) {
                                            Text(mod.folderName).font(.title3)
                                        }
                                        Spacer()
                                        if mod.variants.count > 1 && !mod.variants[0].folderName.isEmpty {
                                            Picker("", selection: $mod.selectedVariant) {
                                                ForEach(mod.variants, id: \.self) { v in
                                                    Text(v.name).tag(v)
                                                }
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .frame(width: 150)
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    // Patches
                    VStack(alignment: .leading) {
                        Text("🛠️ เครื่องมือเสริม (แพตช์ลบคำแปลซ้ำ)").font(.headline)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach($vm.patches) { $patch in
                                    Toggle(isOn: $patch.isEnabled) {
                                        Text(patch.name).font(.title3)
                                    }
                                }
                            }
                            .padding()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                
                // Logs
                VStack(alignment: .leading) {
                    Text("📝 บันทึกการทำงาน:").font(.headline).bold()
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(vm.logs)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("LogBottom")
                        }
                        .frame(height: 120)
                        .padding()
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                        .onChange(of: vm.logs) { _ in
                            withAnimation {
                                proxy.scrollTo("LogBottom", anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Actions
                Button(action: {
                    vm.startInstall()
                }) {
                    Text(vm.isWorking ? "⏳ กำลังทำงาน..." : "🚀 ดำเนินการตามที่เลือก")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(vm.isWorking || (vm.mods.filter({$0.isEnabled}).isEmpty && vm.patches.filter({$0.isEnabled}).isEmpty))
            }
            .padding(20)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}
