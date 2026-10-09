import SwiftUI
import Photos
import Vision
import UIKit

struct IndexedPhoto: Codable, Identifiable {
    let id: String
    var date: Date?
    var text: String
}

@MainActor
final class PhotoIndex: ObservableObject {
    @Published var items: [IndexedPhoto] = []
    @Published var query = ""
    @Published var scanning = false
    @Published var progress = 0.0
    @Published var status = "Cấp quyền ảnh và quét thư viện để bắt đầu."
    @Published var permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private var worker: Task<Void,Never>?

    init() { load() }
    var allowed: Bool { permission == .authorized || permission == .limited }
    var matches: [IndexedPhoto] {
        let key = Self.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty else { return [] }
        let digits = key.filter(\.isNumber)
        let numericQuery = digits.count >= 3 && key.allSatisfy { $0.isNumber || " .,-_/".contains($0) }
        return items.filter {
            let text = Self.normalize($0.text)
            return text.contains(key) || (numericQuery && text.filter(\.isNumber).contains(digits))
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    static func normalize(_ source: String) -> String {
        source.folding(options: [.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"vi_VN")).replacingOccurrences(of:"đ",with:"d")
    }
    private var dbURL: URL {
        let dir = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        return dir.appendingPathComponent("bachfind-index.json")
    }
    func load() {
        if let data = try? Data(contentsOf:dbURL), let saved = try? JSONDecoder().decode([IndexedPhoto].self,from:data) {
            items = saved
            status = "Đã lưu \(saved.count) ảnh trong chỉ mục."
        }
    }
    func save() {
        if let data = try? JSONEncoder().encode(items) {
            do {try data.write(to:dbURL,options:.atomic)}
            catch {status = "Lỗi lưu chỉ mục: \(error.localizedDescription)"}
        }
    }
    func askAndScan() async {
        permission = await PHPhotoLibrary.requestAuthorization(for:.readWrite)
        if allowed { scan() } else {status = "Bạn chưa cho phép truy cập ảnh."}
    }
    func clear() {
        cancel()
        items = []
        save()
        status = "Đã xóa chỉ mục. Ảnh gốc không bị xóa."
    }
    func cancel() {
        worker?.cancel()
        worker = nil
        scanning = false
        status = "Đã tạm dừng. Nhấn Quét để tiếp tục."
    }
    func scan() {
        guard allowed && !scanning else {return}
        scanning = true
        progress = 0
        worker = Task {
            let opts = PHFetchOptions()
            opts.sortDescriptors = [NSSortDescriptor(key:"creationDate",ascending:false)]
            let assets = PHAsset.fetchAssets(with:.image,options:opts)
            let count = assets.count
            var known = Set(items.map(\.id))
            var visible = Set<String>()
            for i in 0..<count {
                if Task.isCancelled { break }
                let asset = assets.object(at:i)
                visible.insert(asset.localIdentifier)
                if !known.contains(asset.localIdentifier) {
                    if let text = await Self.ocr(asset), !text.isEmpty {
                        items.append(IndexedPhoto(id:asset.localIdentifier,date:asset.creationDate,text:text))
                        known.insert(asset.localIdentifier)
                    }
                }
                progress = Double(i+1)/Double(max(count,1))
                if i % 12 == 0 { save(); await Task.yield() }
            }
            if !Task.isCancelled {
                items.removeAll { !visible.contains($0.id) }
                status = "Hoàn tất: \(items.count) ảnh có nội dung nhận dạng."
            }
            save()
            scanning = false
            worker = nil
        }
    }
    nonisolated static func ocr(_ asset:PHAsset) async -> String? {
        await Task.detached(priority:.utility) {
            let opt = PHImageRequestOptions()
            opt.isSynchronous = true
            opt.isNetworkAccessAllowed = false
            opt.deliveryMode = .highQualityFormat
            var photo: UIImage?
            PHImageManager.default().requestImage(for:asset,targetSize:CGSize(width:2000,height:2000),contentMode:.aspectFit,options:opt) { img,_ in photo = img }
            guard let cg = photo?.cgImage else {return nil}
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.automaticallyDetectsLanguage = true
            req.usesLanguageCorrection = false
            do {
                try VNImageRequestHandler(cgImage:cg,options:[:]).perform([req])
                return (req.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n")
            } catch {return nil}
        }.value
    }
}

struct FindPhotoDetail: View {
    let photo: IndexedPhoto
    @State private var image: UIImage?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:18) {
                    if let image {Image(uiImage:image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:16))}
                    else {ProgressView().frame(height:210)}
                    Text("Nội dung đã nhận dạng").font(.headline).frame(maxWidth:.infinity,alignment:.leading)
                    Text(photo.text).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                        .padding(15).background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:14))
                    Text("OCR có thể đọc sai số. Luôn đối chiếu ảnh gốc.").font(.footnote).foregroundStyle(.yellow)
                }.padding()
            }
            .background(Color(red:0.025,green:0.045,blue:0.11))
            .navigationTitle("Ảnh gốc").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.topBarTrailing){Button("Đóng"){dismiss()}}}
        }
        .preferredColorScheme(.dark)
        .onAppear {
            let result = PHAsset.fetchAssets(withLocalIdentifiers:[photo.id],options:nil)
            guard let asset = result.firstObject else {return}
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for:asset,targetSize:CGSize(width:2000,height:2000),contentMode:.aspectFit,options:options){ img,_ in image=img }
        }
    }
    @Environment(\.dismiss) private var dismiss
}

struct FindHome: View {
    @StateObject private var store = PhotoIndex()
    @State private var selected:IndexedPhoto?
    @State private var showClear = false
    @State private var tab = 0
    private let cyan=Color(red:0.30,green:0.85,blue:1)
    var body: some View {
        TabView(selection:$tab) {
            NavigationStack { main }.tabItem {Label("Tìm kiếm",systemImage:"magnifyingglass")}.tag(0)
            NavigationStack { library }.tabItem {Label("Thư viện",systemImage:"photo.on.rectangle")}.tag(1)
            NavigationStack { settings }.tabItem {Label("Cài đặt",systemImage:"gearshape")}.tag(2)
        }
        .tint(cyan).preferredColorScheme(.dark)
        .sheet(item:$selected){FindPhotoDetail(photo:$0)}
    }
    private var bg:some View {
        LinearGradient(colors:[Color(red:0.035,green:0.07,blue:0.18),Color(red:0.01,green:0.02,blue:0.075)],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()
    }
    private var header:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Image(systemName:"sparkle.magnifyingglass").font(.system(size:36)).foregroundStyle(cyan);Spacer();Text("BÁCH APP").font(.caption.weight(.bold)).tracking(2)}
            Text("Tìm lại ảnh.\nKhông cần nhớ ảnh nào.").font(.system(size:29,weight:.bold,design:.rounded))
            Text("Tìm chữ, số tiền, mã hợp đồng trong ảnh và ảnh chụp màn hình.").foregroundStyle(.white.opacity(0.7))
        }
    }
    private var main:some View {
        ZStack {
            bg
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    header
                    HStack {
                        Image(systemName:"magnifyingglass").foregroundStyle(cyan)
                        TextField("Nhập từ khóa, số tiền...",text:$store.query).autocorrectionDisabled().textInputAutocapitalization(.never)
                        if !store.query.isEmpty {Button{store.query=""}label:{Image(systemName:"xmark.circle.fill")}}
                    }.padding(15).background(.white.opacity(0.1),in:RoundedRectangle(cornerRadius:17))
                    if !store.allowed {
                        VStack(alignment:.leading,spacing:12) {
                            Label("Cấp quyền ảnh để tìm kiếm",systemImage:"lock.shield")
                            Text("Chỉ xử lý trên iPhone, không tải nội dung ảnh lên mạng.").font(.subheadline).foregroundStyle(.secondary)
                            Button("Cấp quyền và quét") {Task{await store.askAndScan()}}.buttonStyle(.borderedProminent)
                            Button("Mở cài đặt iPhone"){if let url=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(url)}}
                                .font(.footnote)
                        }.glass()
                    } else {
                        scanCard
                        HStack {Text(store.query.isEmpty ? "Ảnh đã lập chỉ mục" : "Kết quả tìm kiếm").font(.headline);Spacer()
                            Text("\(store.query.isEmpty ? store.items.count : store.matches.count) ảnh").foregroundStyle(cyan)}
                        rows(store.query.isEmpty ? Array(store.items.prefix(50)) : store.matches)
                    }
                    Label("Nhận dạng chữ offline. Các con số cần kiểm tra lại trên ảnh gốc.",systemImage:"lock.shield")
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                }.padding(20)
            }
        }.navigationTitle("Bách Find").navigationBarTitleDisplayMode(.inline)
    }
    private var scanCard:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {Text(store.scanning ? "Đang đọc ảnh..." : store.status).font(.subheadline);Spacer()
                if store.scanning {Text("\(Int(store.progress*100))%").foregroundStyle(cyan)}}
            if store.scanning {ProgressView(value:store.progress)}
            Button(store.scanning ? "Tạm dừng" : "Quét ảnh mới") {
                if store.scanning {store.cancel()} else {store.scan()}
            }.buttonStyle(.borderedProminent).tint(cyan).foregroundStyle(.black)
        }.glass()
    }
    private func rows(_ records:[IndexedPhoto])->some View {
        LazyVStack(spacing:10) {
            if records.isEmpty {
                Text(store.query.isEmpty ? "Chưa có ảnh được quét." : "Không tìm thấy. Hãy thử từ khóa khác.").foregroundStyle(.secondary).padding()
            }
            ForEach(records) { item in
                Button {selected=item} label: {
                    HStack(spacing:12){
                        Image(systemName:"photo.text").font(.title2).foregroundStyle(cyan).frame(width:36)
                        VStack(alignment:.leading,spacing:5){
                            Text(item.text.replacingOccurrences(of:"\n",with:"  "))
                                .lineLimit(2).multilineTextAlignment(.leading).font(.subheadline).foregroundStyle(.white)
                            if let date=item.date {Text(date,style:.date).font(.caption2).foregroundStyle(.secondary)}
                        }
                        Spacer(minLength:4)
                        Image(systemName:"chevron.right").foregroundStyle(.secondary)
                    }.padding(13).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:15))
                }
            }
        }
    }
    private var library:some View {
        ZStack {bg; ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text("\(store.items.count) ảnh đã lập chỉ mục").font(.title2.bold())
                if store.allowed {scanCard} else {Text("Chưa có quyền ảnh. Mở tab Tìm kiếm để cấp quyền.")}
                rows(store.items.sorted{($0.date ?? .distantPast)>($1.date ?? .distantPast)})
            }.padding(20)
        }}.navigationTitle("Thư viện")
    }
    private var settings:some View {
        ZStack {bg;ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Label("Quyền riêng tư",systemImage:"lock.shield").font(.title2.bold())
                Text("Bách Find dùng Apple Vision trên iPhone, lưu chỉ mục trong vùng riêng của ứng dụng. Không gửi ảnh đến máy chủ.")
                Text("Trạng thái quyền ảnh: \(store.allowed ? (store.permission == .limited ? "Một số ảnh" : "Đã cấp quyền") : "Chưa cấp quyền")")
                Button("Xóa chỉ mục OCR",role:.destructive){showClear=true}.confirmationDialog("Xóa chỉ mục?",isPresented:$showClear) {
                    Button("Xóa",role:.destructive){store.clear()}
                } message:{Text("Ảnh gốc vẫn được giữ nguyên.")}
            }.padding(20).glass().padding()
        }}.navigationTitle("Cài đặt")
    }
}
private extension View {
    func glass()->some View {
        self.padding(17).frame(maxWidth:.infinity,alignment:.leading)
            .background(.white.opacity(0.09),in:RoundedRectangle(cornerRadius:20))
            .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(.white.opacity(0.13)))
    }
}
@main struct BachFindApp: App {
    var body:some Scene {WindowGroup{FindV2Home()}}
}
