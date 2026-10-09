import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins
import UIKit
import Darwin

struct PickerTransfer: Transferable {
    let url:URL
    static var transferRepresentation:some TransferRepresentation {
        FileRepresentation(importedContentType:.image) {try save($0.file,"jpg")}
        FileRepresentation(importedContentType:.movie) {try save($0.file,"mov")}
    }
    private static func save(_ file:URL,_ fallback:String)throws->PickerTransfer{
        let ext=file.pathExtension.isEmpty ? fallback : file.pathExtension
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("BachSend-\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at:file,to:url)
        return PickerTransfer(url:url)
    }
}

@MainActor final class SendModel:ObservableObject {
    @Published var outgoing:[SharedTransferFile]=[]
    @Published var incoming:[SharedTransferFile]=[]
    @Published var active=false
    @Published var port:UInt16?
    @Published var token=""
    @Published var message="Chọn file, sau đó bật chia sẻ."
    @Published var transferTitle=""
    @Published var transferProgress:Double? = nil
    var wifiIP:String? { Self.ip() }
    private var server:LocalFileServer?
    // Files in B Send are disposable copies; never remove originals in Photos/Files.
    static let autoPurgeSeconds: TimeInterval = 60 * 60
    init(){
        cleanTemporaryCopies()
        refresh()
    }
    var shareURL:String? {
        guard active,let ip=Self.ip(),let port else{return nil}
        return "http://\(ip):\(port)/?token=\(token)"
    }
    static var receivedDir:URL {
        let folder=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("BachSend/Received",isDirectory:true)
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var noBackup = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? noBackup.setResourceValues(values)
        return folder
    }
    private static var selectedDir: URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BachSend-Selected",isDirectory:true)
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        return folder
    }
    func add(_ urls:[URL]){
        let folder=Self.selectedDir
        var added=0
        for url in urls{
            let access=url.startAccessingSecurityScopedResource()
            defer{if access{url.stopAccessingSecurityScopedResource()}}
            let dest=folder.appendingPathComponent(UUID().uuidString+"-"+url.lastPathComponent)
            do{
                try FileManager.default.copyItem(at:url,to:dest)
                let size=((try? FileManager.default.attributesOfItem(atPath:dest.path)[.size]) as? NSNumber)?.int64Value ?? 0
                outgoing.append(SharedTransferFile(id:UUID(),url:dest,name:url.lastPathComponent,size:size))
                added+=1
            }catch{message="Không thêm được \(url.lastPathComponent): \(error.localizedDescription)"}
        }
        if added>0{message="Đã thêm \(added) file"}
        server?.update(outgoing)
    }
    func remove(_ id:UUID){
        guard let index=outgoing.firstIndex(where:{$0.id==id}) else{return}
        let file=outgoing.remove(at:index)
        try? FileManager.default.removeItem(at:file.url)
        server?.update(outgoing)
    }
    func start(){
        guard !active else{return}
        guard Self.ip() != nil else{message="Chưa thấy Wi-Fi. Kết nối Wi-Fi cùng thiết bị nhận rồi thử lại.";return}
        token=UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
        let current=token
        let s=LocalFileServer(token:current,files:outgoing,destination:Self.receivedDir,started:{[weak self] port in
            Task{@MainActor[weak self] in
                guard self?.token==current else{return}
                self?.port=port;self?.active=true;self?.message="Đã mở phiên LAN + Wi-Fi. PC có thể dùng dây Ethernet cùng router."
            }
        },received:{[weak self] name in
            Task{@MainActor[weak self] in self?.refresh();self?.message="Đã nhận: \(name)";self?.transferTitle="Đã nhận: \(name)";self?.transferProgress=1}
        },progress:{[weak self] name,ratio,isUpload in
            Task{@MainActor[weak self] in
                guard self?.token == current else{return}
                self?.transferTitle=(isUpload ? "PC → iPhone: " : "iPhone → PC: ")+name
                self?.transferProgress=min(1,max(0,ratio))
            }
        },failed:{[weak self] detail in
            Task{@MainActor[weak self] in self?.message=detail;self?.active=false;self?.port=nil}
        })
        server=s
        s.start()
        transferTitle=""
        transferProgress=nil
        message="Đang mở phiên Wi-Fi..."
    }
    func stop(){
        server?.stop();server=nil;active=false;port=nil;token=""
        transferTitle=""
        transferProgress=nil
        message="Đã ngừng chia sẻ."
    }
    func refresh(){
        purgeExpiredIfIdle()
        let files=(try? FileManager.default.contentsOfDirectory(at:Self.receivedDir,includingPropertiesForKeys:[.fileSizeKey])) ?? []
        incoming=files.filter{!$0.lastPathComponent.hasSuffix(".part")}.map{url in
            let size=(try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            let raw=url.lastPathComponent
            let name=raw.range(of:"__").map{String(raw[$0.upperBound...])} ?? raw
            return SharedTransferFile(id:UUID(),url:url,name:name,size:size)
        }.sorted{$0.url.lastPathComponent>$1.url.lastPathComponent}
    }
    func delete(_ f:SharedTransferFile){try? FileManager.default.removeItem(at:f.url);refresh()}

    // User-initiated one-tap cleanup. Stops LAN server first so files aren't open.
    func clearAllManagedFiles() {
        stop()
        for file in outgoing { try? FileManager.default.removeItem(at:file.url) }
        outgoing.removeAll()
        server?.update(outgoing)
        for dir in [Self.receivedDir, Self.selectedDir] {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files { try? FileManager.default.removeItem(at:file) }
        }
        incoming.removeAll()
        message = "Đã xóa toàn bộ bản sao do B Send quản lý. File gốc vẫn an toàn."
    }

    // B Send never backs up transfer copies to iCloud. Default TTL: 60 minutes.
    // This is cleanup on app activity, NOT an iOS background scheduler.
    func purgeExpiredIfIdle(onlineBusy: Bool = false) {
        guard !active && !onlineBusy else { return }
        cleanTemporaryCopies()
        let received = (try? FileManager.default.contentsOfDirectory(
            at: Self.receivedDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let now = Date()
        for url in received {
            let time = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            if now.timeIntervalSince(time) > Self.autoPurgeSeconds {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func cleanTemporaryCopies() {
        let directory = Self.selectedDir
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let now = Date()
        let selected = Set(outgoing.map { $0.url.standardizedFileURL })
        for url in files {
            guard !selected.contains(url.standardizedFileURL) else { continue }
            let time = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            if now.timeIntervalSince(time) > Self.autoPurgeSeconds {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
    private static func ip()->String?{
        var start:UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&start)==0,let first=start else{return nil}
        defer{freeifaddrs(start)}
        var cursor:UnsafeMutablePointer<ifaddrs>?=first
        while let item=cursor{
            defer{cursor=item.pointee.ifa_next}
            guard let addr=item.pointee.ifa_addr,addr.pointee.sa_family==UInt8(AF_INET) else{continue}
            let name=String(cString:item.pointee.ifa_name)
            guard name=="en0" else{continue}
            var host=[CChar](repeating:0,count:Int(NI_MAXHOST))
            guard getnameinfo(addr,socklen_t(addr.pointee.sa_len),&host,socklen_t(host.count),nil,0,NI_NUMERICHOST)==0 else{continue}
            return String(cString:host)
        }
        return nil
    }
}

struct SendQR:View {
    let text:String
    var body:some View {
        if let image=makeImage() {
            Image(uiImage:image).interpolation(.none).resizable().scaledToFit().background(.white)
        } else {Image(systemName:"qrcode").resizable().scaledToFit()}
    }
    private func makeImage()->UIImage? {
        let generator=CIFilter.qrCodeGenerator()
        generator.message=Data(text.utf8)
        generator.correctionLevel="M"
        let context=CIContext()
        guard let image=generator.outputImage?.transformed(by:CGAffineTransform(scaleX:9,y:9)),
              let cg=context.createCGImage(image,from:image.extent) else{return nil}
        return UIImage(cgImage:cg)
    }
}

struct SendHome:View {
    @StateObject private var store=SendModel()
    @State private var importFiles=false
    @State private var photos:[PhotosPickerItem]=[]
    @State private var tab=0
    @State private var copied=false
    @State private var showError=false
    private let cyan=Color(red:0.44,green:0.90,blue:0.99)
    var body:some View {
        TabView(selection:$tab){
            NavigationStack{sharePage}.tabItem{Label("Chia sẻ",systemImage:"arrow.left.arrow.right")}.tag(0)
            NavigationStack{receivedPage}.tabItem{Label("Đã nhận",systemImage:"tray.and.arrow.down")}.tag(1)
            NavigationStack{settingsPage}.tabItem{Label("Cài đặt",systemImage:"gearshape")}.tag(2)
        }
        .tint(cyan).preferredColorScheme(.dark)
        .fileImporter(isPresented:$importFiles,allowedContentTypes:[.item],allowsMultipleSelection:true){result in
            switch result {
            case .success(let urls):store.add(urls)
            case .failure(let error):store.message="Không mở được Files: \(error.localizedDescription)"
            }
        }
        .onChange(of:photos){items in
            Task{
                for item in items{
                    if let file=try? await item.loadTransferable(type:PickerTransfer.self){
                        store.add([file.url])
                        try? FileManager.default.removeItem(at:file.url)
                    }
                }
                photos=[]
            }
        }
    }
    private var bg:some View {LinearGradient(colors:[Color(red:0.03,green:0.07,blue:0.17),Color(red:0.03,green:0.12,blue:0.20)],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()}
    private var sharePage:some View {
        ZStack{bg;ScrollView{
            VStack(alignment:.leading,spacing:20){
                VStack(alignment:.leading,spacing:9){
                    HStack{Image(systemName:"arrow.left.arrow.right.circle.fill").font(.system(size:42)).foregroundStyle(cyan);Spacer();Text("BÁCH APP").font(.caption).tracking(2)}
                    Text("Gửi file không cần Internet").font(.system(size:28,weight:.bold,design:.rounded))
                    Text("iPhone ↔ Windows · Android · Laptop").foregroundStyle(.secondary)
                }
                session
                HStack{Text("File đang chia sẻ").font(.title3.bold());Spacer();Text("\(store.outgoing.count) file").foregroundStyle(.secondary)}
                HStack{
                    Button{importFiles=true}label:{Label("Chọn từ Files",systemImage:"folder").frame(maxWidth:.infinity)}
                        .buttonStyle(.borderedProminent).tint(cyan).foregroundStyle(.black)
                    PhotosPicker(selection:$photos,maxSelectionCount:30,matching:.any(of:[.images,.videos])){
                        Image(systemName:"photo.on.rectangle").frame(width:46,height:44).background(.white.opacity(0.12),in:RoundedRectangle(cornerRadius:12))
                    }
                }
                if store.outgoing.isEmpty{Text("Chọn ảnh, video, PDF hoặc file tài liệu để bắt đầu.").foregroundStyle(.secondary).glass()}
                ForEach(store.outgoing){file in
                    HStack{
                        Image(systemName:"doc.fill").foregroundStyle(cyan)
                        VStack(alignment:.leading){Text(file.name).lineLimit(2);Text(ByteCountFormatter.string(fromByteCount:file.size,countStyle:.file)).font(.caption2).foregroundStyle(.secondary)}
                        Spacer()
                        Button{store.remove(file.id)}label:{Image(systemName:"xmark.circle.fill")}
                    }.glass()
                }
                Label("Giữ Bách Send mở trong khi tải. iOS có thể dừng kết nối khi khóa màn hình.",systemImage:"info.circle").font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }}.navigationTitle("Bách Send").navigationBarTitleDisplayMode(.inline)
    }
    private var session:some View {
        VStack(alignment:.leading,spacing:14){
            Label(store.active ? "Đang chia sẻ" : "Chưa bật chia sẻ",systemImage:store.active ? "wifi" : "wifi.slash").font(.headline)
            if let url=store.shareURL{
                HStack(alignment:.top,spacing:14){
                    SendQR(text:url).frame(width:132,height:132).padding(8).background(.white,in:RoundedRectangle(cornerRadius:14))
                    VStack(alignment:.leading,spacing:12){
                        Text("Quét QR để mở trên thiết bị nhận").font(.subheadline)
                        Text(url).font(.caption2.monospaced()).foregroundStyle(cyan).textSelection(.enabled)
                        Button{UIPasteboard.general.string=url;copied=true}label:{Label(copied ? "Đã sao chép" : "Sao chép link",systemImage:"doc.on.doc")}
                    }
                }
            } else {
                Label("Bật chia sẻ để tạo QR và địa chỉ Wi-Fi.",systemImage:"qrcode").font(.subheadline).foregroundStyle(.secondary)
            }
            Text(store.message).font(.caption).foregroundStyle(.secondary)
            Button{store.active ? store.stop() : store.start()}label:{
                Label(store.active ? "Dừng chia sẻ" : "Bật chia sẻ",systemImage:store.active ? "stop.circle" : "wifi").frame(maxWidth:.infinity)
            }.buttonStyle(.borderedProminent).tint(store.active ? .red : cyan).foregroundStyle(store.active ? .white : .black)
        }.glass()
    }
    private var receivedPage:some View {
        ZStack{bg;ScrollView{
            VStack(alignment:.leading,spacing:15){
                Text("File nhận về iPhone").font(.title2.bold())
                Text("Có thể chia sẻ lại sang ứng dụng Files hoặc app khác.").foregroundStyle(.secondary)
                if store.incoming.isEmpty{Text("Chưa có file đã nhận.").foregroundStyle(.secondary).glass()}
                ForEach(store.incoming){file in
                    HStack{
                        Image(systemName:"doc.zipper").foregroundStyle(cyan)
                        VStack(alignment:.leading){Text(file.name).lineLimit(2);Text(ByteCountFormatter.string(fromByteCount:file.size,countStyle:.file)).font(.caption2).foregroundStyle(.secondary)}
                        Spacer()
                        ShareLink(item:file.url){Image(systemName:"square.and.arrow.up")}
                        Button(role:.destructive){store.delete(file)}label:{Image(systemName:"trash")}
                    }.glass()
                }
            }.padding(20)
        }}.onAppear{store.refresh()}.navigationTitle("Đã nhận")
    }
    private var settingsPage:some View{
        ZStack{bg;ScrollView{
            VStack(alignment:.leading,spacing:16){
                Label("Riêng tư & Bảo mật",systemImage:"lock.shield").font(.title2.bold())
                Text("Chuyển file trực tiếp qua Wi-Fi nội bộ. Không cần tài khoản, không tải lên máy chủ.")
                Text("Bản v0.1 dùng HTTP chưa mã hóa. Không dùng Wi-Fi công cộng hoặc chuyển tài liệu khách hàng, ngân hàng, CCCD.")
                    .foregroundStyle(.yellow)
                Text("Địa chỉ tải có mã phiên ngẫu nhiên, chỉ hoạt động khi bạn bật chia sẻ; nhấn Dừng chia sẻ để hủy.")
                Text("Giới hạn: 1 GiB/file. Thiết bị phải cùng mạng và mạng phải cho phép kết nối giữa các máy.")
            }.padding(20).glass().padding()
        }}.navigationTitle("Cài đặt")
    }
}

private extension View {
    func glass()->some View {
        self.padding(17).frame(maxWidth:.infinity,alignment:.leading)
            .background(.white.opacity(0.09),in:RoundedRectangle(cornerRadius:19))
            .overlay(RoundedRectangle(cornerRadius:19).strokeBorder(.white.opacity(0.15)))
    }
}
@main struct BachSendApp:App{
    var body:some Scene{WindowGroup{SendV2Home()}}
}
