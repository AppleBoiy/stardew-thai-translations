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
    @Published var showSuccessAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    
    let fileManager = FileManager.default
    
    init() {
        self.gameDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS/Mods")
        self.loadMods()
    }
    
    func log(_ message: String) {
        DispatchQueue.main.async {
            self.logs += message + "\n"
        }
    }
    
    func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            self.alertTitle = title
            self.alertMessage = message
            self.showSuccessAlert = true
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
                self.showAlert(title: "สำเร็จ!", message: "ดำเนินการติดตั้งม็อดและเครื่องมือเสร็จสมบูรณ์\nดูรายละเอียดเพิ่มเติมได้ที่หน้า 'บันทึกการทำงาน'")
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
    
    func injectGMCMDescriptions(style: Int) {
        isWorking = true
        logs = ""
        
        let fm = FileManager.default
        let gDir = self.gameDir
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.log("🛠️ กำลังสแกนหาไฟล์ manifest.json ในโฟลเดอร์ Mods...")
            
            let enumerator = fm.enumerator(atPath: gDir)
            var manifestFiles: [String] = []
            
            while let file = enumerator?.nextObject() as? String {
                if file.hasSuffix("manifest.json") {
                    manifestFiles.append(file)
                }
            }
            
            var foundCount = 0
            var injectedCount = 0
            var rollbackCount = 0
            
            let isRollback = (style == 3)
            let dict = (style == 1) ? GMCMInjector.gamerDesc : GMCMInjector.normalDesc
            
            guard let nameRegex = try? NSRegularExpression(pattern: "\"Name\"\\s*:\\s*\"([^\"]+)\"", options: []),
                  let descRegex = try? NSRegularExpression(pattern: "(\"Description\"\\s*:\\s*\")[^\"\\\\]*(?:\\\\.[^\"\\\\]*)*(\")", options: []),
                  let insertRegex = try? NSRegularExpression(pattern: "(\"Name\"\\s*:\\s*\"[^\"]+\"\\s*,)", options: []) else {
                return
            }
            
            if isRollback {
                self.log("↩️ เริ่มคืนค่าเดิม (Rollback)...")
                for file in manifestFiles {
                    let fullPath = (gDir as NSString).appendingPathComponent(file)
                    let backupPath = fullPath + ".bak"
                    if fm.fileExists(atPath: backupPath) {
                        do {
                            if fm.fileExists(atPath: fullPath) {
                                try fm.removeItem(atPath: fullPath)
                            }
                            try fm.moveItem(atPath: backupPath, toPath: fullPath)
                            
                            // Try to extract name for logging
                            if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                                let nsContent = content as NSString
                                if let match = nameRegex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: nsContent.length)) {
                                    let modName = nsContent.substring(with: match.range(at: 1))
                                    self.log("  ✅ คืนค่าเดิม: \(modName)")
                                }
                            }
                            rollbackCount += 1
                        } catch {
                            self.log("❌ คืนค่าล้มเหลวที่ \(file)")
                        }
                    }
                }
                self.log("🎉 คืนค่าเดิมสำเร็จทั้งหมด: \(rollbackCount) ตัว")
                self.showAlert(title: "สำเร็จ!", message: "คืนค่า GMCM เป็นภาษาอังกฤษเรียบร้อย")
            } else {
                let styleName = (style == 1) ? "เกมเมอร์" : "ทางการ"
                self.log("🇹🇭 เริ่มแปลคำอธิบาย GMCM (สไตล์\(styleName))...")
                
                for file in manifestFiles {
                    let fullPath = (gDir as NSString).appendingPathComponent(file)
                    guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }
                    
                    let nsContent = content as NSString
                    guard let nameMatch = nameRegex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: nsContent.length)) else { continue }
                    
                    let modName = nsContent.substring(with: nameMatch.range(at: 1))
                    
                    if let thaiDesc = dict[modName] {
                        foundCount += 1
                        
                        var currentDesc = ""
                        if let descMatch = descRegex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: nsContent.length)) {
                            // Extract just the value inside quotes
                            let fullMatch = nsContent.substring(with: descMatch.range)
                            currentDesc = fullMatch // We'll just compare roughly or replace anyway
                        }
                        
                        // We replace if not already replaced
                        if !content.contains("\"\(thaiDesc)\"") {
                            let backupPath = fullPath + ".bak"
                            if !fm.fileExists(atPath: backupPath) {
                                try? fm.copyItem(atPath: fullPath, toPath: backupPath)
                            }
                            
                            let escapedThaiDesc = thaiDesc.replacingOccurrences(of: "\"", with: "\\\"")
                            
                            var newContent = content
                            let descMatches = descRegex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
                            
                            if !descMatches.isEmpty {
                                newContent = descRegex.stringByReplacingMatches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length), withTemplate: "$1\(escapedThaiDesc)$2")
                                do {
                                    try newContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
                                    self.log("  ✅ แปลสำเร็จ: \(modName)")
                                    injectedCount += 1
                                } catch {}
                            } else {
                                // Inject below Name
                                let newTemplate = "$1\n  \"Description\": \"\(escapedThaiDesc)\","
                                newContent = insertRegex.stringByReplacingMatches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length), withTemplate: newTemplate)
                                do {
                                    try newContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
                                    self.log("  ✅ แทรกคำอธิบายสำเร็จ: \(modName)")
                                    injectedCount += 1
                                } catch {}
                            }
                        }
                    }
                }
                self.log("=============================")
                self.log("✨ พบม็อดที่รองรับ: \(foundCount) ตัว")
                self.log("✨ ทำการแก้ไขสำเร็จ: \(injectedCount) ตัว")
                self.log("🎉 การแปล GMCM เสร็จสิ้น!")
                self.showAlert(title: "สำเร็จ!", message: "แปลเมนู GMCM เสร็จสมบูรณ์\nดูรายละเอียดเพิ่มเติมได้ที่หน้า 'บันทึกการทำงาน'")
            }
            
            DispatchQueue.main.async {
                self.isWorking = false
            }
        }
    }
}

struct ContentView: View {
    @StateObject var vm = InstallerViewModel()
    @State private var selection: String? = "Install"
    
    var body: some View {
        VStack(spacing: 0) {
            // Global Header
            HStack {
                Label("โฟลเดอร์เกม (Mods):", systemImage: "folder.fill")
                    .font(.headline)
                TextField("Game Directory", text: $vm.gameDir)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(action: { vm.selectGameDir() }) {
                    Label("เลือก...", systemImage: "magnifyingglass")
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            NavigationView {
                // Sidebar
                List(selection: $selection) {
                    NavigationLink(destination: ModsInstallView(vm: vm), tag: "Install", selection: $selection) {
                        Label("ติดตั้งม็อด", systemImage: "shippingbox.fill")
                    }
                    NavigationLink(destination: ToolsView(vm: vm), tag: "Tools", selection: $selection) {
                        Label("เครื่องมือเสริม", systemImage: "wrench.and.screwdriver.fill")
                    }
                    NavigationLink(destination: LogsView(vm: vm), tag: "Logs", selection: $selection) {
                        Label("บันทึกการทำงาน", systemImage: "doc.text.fill")
                    }
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 200)
                
                // Default View
                ModsInstallView(vm: vm)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .alert(isPresented: $vm.showSuccessAlert) {
            Alert(
                title: Text(vm.alertTitle),
                message: Text(vm.alertMessage),
                dismissButton: .default(Text("ตกลง"))
            )
        }
    }
}

struct ModsInstallView: View {
    @ObservedObject var vm: InstallerViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("📦 เลือกม็อดที่จะติดตั้ง").font(.title2).bold()
                Spacer()
                Button("เลือกทั้งหมด") { for i in 0..<vm.mods.count { vm.mods[i].isEnabled = true } }
                Button("ยกเลิก") { for i in 0..<vm.mods.count { vm.mods[i].isEnabled = false } }
            }
            
            if vm.mods.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "shippingbox.circle")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.secondary)
                    Text("ไม่พบม็อดในโฟลเดอร์ mods/")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List($vm.mods) { $mod in
                    HStack {
                        Toggle(isOn: $mod.isEnabled) {
                            Text(mod.folderName).font(.body)
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
                    .padding(.vertical, 4)
                }
                .listStyle(InsetListStyle())
            }
            
            if #available(macOS 12.0, *) {
                Button(action: { vm.startInstall() }) {
                    Label(vm.isWorking ? "กำลังทำงาน..." : "ดำเนินการติดตั้งม็อด", systemImage: vm.isWorking ? "hourglass" : "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(vm.isWorking || vm.mods.filter({$0.isEnabled}).isEmpty)
            } else {
                Button(action: { vm.startInstall() }) {
                    Text(vm.isWorking ? "กำลังทำงาน..." : "ดำเนินการติดตั้งม็อด")
                        .frame(maxWidth: .infinity)
                }
                .disabled(vm.isWorking || vm.mods.filter({$0.isEnabled}).isEmpty)
            }
        }
        .padding()
    }
}

struct ToolsView: View {
    @ObservedObject var vm: InstallerViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text("🛠️ เครื่องมือเสริม (Tools)").font(.title).bold()
                
                GroupBox(label: Label("แพตช์ลบคำแปลซ้ำ", systemImage: "bandage.fill").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ลบวงเล็บภาษาอังกฤษหลังชื่อตัวละคร (เช่น East Scarp)")
                            .foregroundColor(.secondary)
                        
                        ForEach($vm.patches) { $patch in
                            Toggle(isOn: $patch.isEnabled) {
                                Text(patch.name)
                            }
                        }
                        
                        Button(action: { vm.startInstall() }) {
                            Label("รันแพตช์ลบคำแปลซ้ำ", systemImage: "bandage")
                                .padding(.horizontal, 10)
                        }
                        .disabled(vm.isWorking || vm.patches.filter({$0.isEnabled}).isEmpty)
                        .padding(.top, 8)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                GroupBox(label: Label("แปลเมนู GMCM (GMCM Injector)", systemImage: "gearshape.2.fill").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("แปลคำอธิบายม็อดในเมนูตั้งค่า Generic Mod Config Menu ให้เป็นภาษาไทย")
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 15) {
                            Button(action: { vm.injectGMCMDescriptions(style: 1) }) {
                                Label(vm.isWorking ? "กำลังทำงาน..." : "สไตล์เกมเมอร์", systemImage: vm.isWorking ? "hourglass" : "gamecontroller.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                            }
                            .disabled(vm.isWorking)
                            
                            Button(action: { vm.injectGMCMDescriptions(style: 2) }) {
                                Label(vm.isWorking ? "กำลังทำงาน..." : "สไตล์ทางการ", systemImage: vm.isWorking ? "hourglass" : "briefcase.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                            }
                            .disabled(vm.isWorking)
                            
                            Button(action: { vm.injectGMCMDescriptions(style: 3) }) {
                                Label(vm.isWorking ? "กำลังทำงาน..." : "คืนค่าเดิม", systemImage: vm.isWorking ? "hourglass" : "arrow.uturn.backward")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                            }
                            .disabled(vm.isWorking)
                        }
                        .padding(.top, 8)
                    }
                    .padding(10)
                }
            }
            .padding()
        }
    }
}

struct LogsView: View {
    @ObservedObject var vm: InstallerViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("📝 บันทึกการทำงาน").font(.title2).bold()
                .padding(.bottom, 5)
            
            ScrollViewReader { proxy in
                ScrollView {
                    Text(vm.logs.isEmpty ? "ยังไม่มีบันทึกการทำงาน..." : vm.logs)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(vm.logs.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("LogBottom")
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .onChange(of: vm.logs) { _ in
                    withAnimation {
                        proxy.scrollTo("LogBottom", anchor: .bottom)
                    }
                }
            }
        }
        .padding()
    }
}
