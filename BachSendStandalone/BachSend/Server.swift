import Foundation
import Network

struct SharedTransferFile: Identifiable {
    let id: UUID
    let url: URL
    let name: String
    let size: Int64
}

final class LocalFileServer {
    private let queue=DispatchQueue(label:"bachsend.http",qos:.userInitiated)
    private let token:String
    private let destination:URL
    private let started:(UInt16)->Void
    private let received:(String)->Void
    private let failed:(String)->Void
    private var listener:NWListener?
    private var files:[SharedTransferFile]
    private var clients:[UUID:HTTPPeer]=[:]
    init(token:String,files:[SharedTransferFile],destination:URL,started:@escaping(UInt16)->Void,received:@escaping(String)->Void,failed:@escaping(String)->Void){
        self.token=token;self.files=files;self.destination=destination
        self.started=started;self.received=received;self.failed=failed
    }
    func start(){
        queue.async {
            do{
                let params=NWParameters.tcp
                params.requiredInterfaceType = .wifi
                let listener=try NWListener(using:params,on:.any)
                self.listener=listener
                listener.stateUpdateHandler = { [weak self,weak listener] state in
                    guard let self else{return}
                    switch state {
                    case .ready:if let port=listener?.port{self.started(port.rawValue)}
                    case .failed(let e):self.failed("Không mở được kết nối: \(e.localizedDescription)")
                    default:break
                    }
                }
                listener.newConnectionHandler = {[weak self] connection in self?.accept(connection)}
                listener.start(queue:self.queue)
            }catch{self.failed("Không mở được cổng Wi-Fi: \(error.localizedDescription)")}
        }
    }
    func stop(){
        queue.async {
            self.listener?.cancel();self.listener=nil
            for client in self.clients.values{client.stop()}
            self.clients.removeAll()
        }
    }
    func update(_ list:[SharedTransferFile]){queue.async{self.files=list}}
    private func accept(_ connection:NWConnection){
        let id=UUID()
        let client=HTTPPeer(connection:connection,queue:queue,token:token,destination:destination,files:{[weak self] in self?.files ?? []},received:{[weak self] name in self?.received(name)},done:{[weak self] in self?.clients[id]=nil})
        clients[id]=client
        client.start()
    }
}

private final class HTTPPeer {
    private let connection:NWConnection
    private let queue:DispatchQueue
    private let token:String
    private let destinationDir:URL
    private let files:()->[SharedTransferFile]
    private let received:(String)->Void
    private let done:()->Void
    private var header=Data()
    private var expected=0
    private var got=0
    private var output:FileHandle?
    private var part:URL?
    private var filename=""
    private var closed=false
    private var responding=false
    init(connection:NWConnection,queue:DispatchQueue,token:String,destination:URL,files:@escaping()->[SharedTransferFile],received:@escaping(String)->Void,done:@escaping()->Void){
        self.connection=connection;self.queue=queue;self.token=token;self.destinationDir=destination
        self.files=files;self.received=received;self.done=done
    }
    func start(){
        connection.stateUpdateHandler = {[weak self] state in
            switch state {
            case .ready:self?.read()
            case .failed,.cancelled:self?.close()
            default:break
            }
        }
        connection.start(queue:queue)
    }
    func stop(){close()}
    private func close(){
        if closed{return}
        closed=true
        if let output{try? output.close()}
        output=nil
        if let part{try? FileManager.default.removeItem(at:part)}
        part=nil
        connection.cancel()
        done()
    }
    private func read(){
        connection.receive(minimumIncompleteLength:1,maximumLength:65536){[weak self] data,_,complete,error in
            guard let self,!self.closed else{return}
            if let data,!data.isEmpty{self.ingest(data)}
            if self.closed || self.responding{return}
            if error != nil || complete{self.close()}
            else{self.read()}
        }
    }
    private func ingest(_ data:Data){
        if output != nil{consume(data);return}
        header.append(data)
        guard header.count<=65536 else{reply(431,"Headers too large");return}
        guard let marker=header.range(of:Data("\r\n\r\n".utf8)) else{return}
        let h=header.subdata(in:0..<marker.lowerBound)
        let body=header.subdata(in:marker.upperBound..<header.count)
        header.removeAll()
        guard let str=String(data:h,encoding:.utf8) else{reply(400,"Invalid header");return}
        let lines=str.components(separatedBy:"\r\n")
        let parts=(lines.first ?? "").split(separator:" ")
        guard parts.count==3,
              let url=URLComponents(string:"http://localhost"+String(parts[1])),
              url.queryItems?.first(where:{$0.name=="token"})?.value==token
        else{reply(403,"Wrong session token");return}
        let method=String(parts[0])
        let path=url.path
        if method=="GET" && path=="/"{response(200,"text/html; charset=utf-8",Data(page().utf8));return}
        if method=="GET" && path.hasPrefix("/download/"){
            let fileID=String(path.dropFirst("/download/".count))
            guard let file=files().first(where:{$0.id.uuidString==fileID}) else{reply(404,"File not found");return}
            stream(file);return
        }
        if method=="POST" && path=="/upload"{
            guard let value=lines.dropFirst().first(where:{$0.lowercased().hasPrefix("content-length:")})?.split(separator:":",maxSplits:1).last,
                  let length=Int(value.trimmingCharacters(in:.whitespaces)),length>=0 else{reply(411,"Length required");return}
            guard length<=1_073_741_824 else{reply(413,"File exceeds 1 GiB");return}
            let original=url.queryItems?.first(where:{$0.name=="name"})?.value ?? "file"
            let clean=String(original.unicodeScalars.filter{$0.value>=32 && $0.value != 127})
                .replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"\\",with:"_")
            filename=String(clean.prefix(130)).isEmpty ? "file" : String(clean.prefix(130))
            let url=destinationDir.appendingPathComponent(UUID().uuidString+"__"+filename+".part")
            guard FileManager.default.createFile(atPath:url.path,contents:nil),
                  let writer=try? FileHandle(forWritingTo:url) else{reply(500,"Cannot create file");return}
            part=url
            output=writer
            expected=length
            got=0
            consume(body)
            return
        }
        reply(404,"Not found")
    }
    private func consume(_ data:Data){
        guard let output else{return}
        guard got+data.count<=expected else{reply(400,"Invalid length");return}
        do{try output.write(contentsOf:data)}catch{reply(500,"Write error");return}
        got+=data.count
        if got==expected{
            do{try output.close()}catch{reply(500,"File close error");return}
            self.output=nil
            guard let part else{reply(500,"No file");return}
            let completed=part.deletingPathExtension()
            do{
                try FileManager.default.moveItem(at:part,to:completed)
                self.part=nil
                received(filename)
                response(200,"application/json",Data("{\"ok\":true}".utf8))
            }catch{reply(500,"Save error")}
        }
    }
    private func stream(_ file:SharedTransferFile){
        guard let reader=try? FileHandle(forReadingFrom:file.url) else{reply(404,"Missing file");return}
        responding=true
        let encoded=file.name.addingPercentEncoding(withAllowedCharacters:.alphanumerics) ?? "download"
        let h="HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename*=UTF-8''\(encoded)\r\nContent-Length: \(file.size)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content:Data(h.utf8),completion:.contentProcessed {[weak self] error in
            if error != nil{try? reader.close();self?.close()}
            else{self?.sendChunk(reader)}
        })
    }
    private func sendChunk(_ handle:FileHandle){
        let data=handle.readData(ofLength:65536)
        if data.isEmpty{try? handle.close();close();return}
        connection.send(content:data,completion:.contentProcessed{[weak self] error in
            if error != nil{try? handle.close();self?.close()}
            else{self?.sendChunk(handle)}
        })
    }
    private func reply(_ code:Int,_ text:String){response(code,"text/plain; charset=utf-8",Data(text.utf8))}
    private func response(_ code:Int,_ type:String,_ bytes:Data){
        if let output{try? output.close()}
        output=nil
        if let part{try? FileManager.default.removeItem(at:part)}
        part=nil
        responding=true
        let reason=code==200 ? "OK" : "Error"
        let h="HTTP/1.1 \(code) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(bytes.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var all=Data(h.utf8);all.append(bytes)
        connection.send(content:all,completion:.contentProcessed{[weak self] _ in self?.close()})
    }
    private func page()->String{
        let links=files().map{file in
            let safe=file.name.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;")
            let size=ByteCountFormatter.string(fromByteCount:file.size,countStyle:.file)
            return "<a class='file' href='/download/\(file.id.uuidString)?token=\(token)'>📄 \(safe) · \(size) ↓</a>"
        }.joined(separator:"\n")
        return """
        <!doctype html><html lang="vi"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Bách Send</title><style>
        body{background:linear-gradient(135deg,#081429,#0b2844);color:#ecf8ff;font:16px system-ui;margin:0;min-height:100vh}
        main{max-width:680px;margin:35px auto;padding:20px}.glass{border:1px solid #ffffff26;background:#ffffff12;padding:24px;border-radius:22px;margin:16px 0}
        h1{font-size:31px}p{color:#b8c8d6}a.file{display:block;background:#ffffff18;border-radius:12px;margin:10px 0;padding:16px;color:#8deaff;text-decoration:none;overflow-wrap:anywhere}
        button{background:#87e5ff;color:#031824;border:0;padding:13px 25px;border-radius:12px;font-weight:700}input{max-width:100%;margin:18px 0}
        </style><main><div class="glass"><h1>↔ Bách Send</h1><p>Truyền file bằng Wi-Fi nội bộ. Không cần đăng nhập.</p></div>
        <div class="glass"><h2>📥 Tải file từ iPhone</h2>\(links.isEmpty ? "<p>Chưa có file được chọn.</p>" : links)</div>
        <div class="glass"><h2>📤 Gửi file vào iPhone</h2><input id="files" type="file" multiple>
        <button onclick="sendFiles()">Gửi file</button><p id="status"></p>
        <small>Giới hạn 1 GiB mỗi file. HTTP không mã hóa: chỉ dùng Wi-Fi đáng tin cậy.</small></div></main>
        <script>
        const token="\(token)";
        async function sendFiles(){
          const files=document.getElementById("files").files;
          const status=document.getElementById("status");
          if(!files.length){status.textContent="Hãy chọn file";return;}
          for(const f of files){
            status.textContent="Đang gửi "+f.name;
            try{
              const url="/upload?token="+encodeURIComponent(token)+"&name="+encodeURIComponent(f.name);
              const result=await fetch(url,{method:"POST",body:f,headers:{"Content-Type":"application/octet-stream"}});
              if(!result.ok)throw new Error("HTTP "+result.status);
              status.textContent="Đã gửi "+f.name;
            }catch(err){status.textContent="Lỗi gửi: "+err.message;break;}
          }
        }</script></html>
        """
    }
}
