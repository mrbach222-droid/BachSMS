using System;using System.Collections;using System.Collections.Generic;using System.Data;using System.Drawing;using System.Globalization;using System.IO;using System.Linq;using System.Net;using System.Reflection;using System.Runtime.CompilerServices;using System.Security.Cryptography;using System.Text;using System.Text.RegularExpressions;using System.Threading.Tasks;using System.Web.Script.Serialization;using System.Windows.Forms;
[assembly: AssemblyVersion("1.4.14.45")]
[assembly: AssemblyFileVersion("1.4.14.45")]
[assembly: System.Runtime.Versioning.TargetFramework(".NETFramework,Version=v4.5")]
[assembly: InternalsVisibleTo("CloudTests")]

public sealed class CloudCustomer {public string cif,customer_name,phone,contract_number,message;}
public sealed class CloudJob {public string id,cif,customer_name,phone,contract_number,message,created_at;public int revision=1;}
public sealed class CloudBatch {public string id;public List<CloudJob> jobs=new List<CloudJob>();}
public sealed class CloudConfig {public string url,channel,writer_token,pair_code,label;}
public sealed class CloudTransfer {public string channel;public List<CloudBatch> batches=new List<CloudBatch>();}
public static class BachCRMCloud {
 static readonly ConditionalWeakTable<Form,object> installed=new ConditionalWeakTable<Form,object>();
 internal static readonly JavaScriptSerializer Json=new JavaScriptSerializer{MaxJsonLength=16*1024*1024};
 static readonly string Root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"BachCRM","CloudSMS");
 static readonly string ConfigPath=Path.Combine(Root,"connection.bin");
 internal static string PendingPath(CloudConfig config){return Path.Combine(Root,"pending-"+config.channel+".bin");}
 static object Field(object o,string n){if(o==null)return null;var f=o.GetType().GetField(n,BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance);return f==null?null:f.GetValue(o);}
 static object Invoke(object o,string n,params object[] args){return o.GetType().GetMethod(n,BindingFlags.NonPublic|BindingFlags.Public|BindingFlags.Instance).Invoke(o,args);}
 static string Text(object o,string n){return Convert.ToString(Field(o,n),CultureInfo.InvariantCulture)??"";}
 public static string NormalizePhone(string raw){
  foreach(string part in Regex.Split(raw??"","[,;/|\\r\\n]+")){string digits=Regex.Replace(part,"[^0-9]","");if(digits.StartsWith("0084"))digits="0"+digits.Substring(4);else if(digits.StartsWith("84"))digits="0"+digits.Substring(2);else if(digits.Length==9)digits="0"+digits;if(Regex.IsMatch(digits,"^0[35789][0-9]{8}$"))return digits;}
  return "";
 }
 public static List<CloudCustomer> Customers(object source){
  var rows=new List<CloudCustomer>();if(source==null)return rows;
  foreach(object c in (IEnumerable)source){string phone=NormalizePhone(Text(c,"NewPhone"));if(phone.Length==0)phone=NormalizePhone(Text(c,"Phone"));string cif=Text(c,"Cif").Trim();if(phone.Length==0||cif.Length==0)continue;rows.Add(new CloudCustomer{cif=cif,customer_name=Text(c,"Name").Trim(),phone=phone,contract_number=Text(c,"Contract").Trim(),message=""});}
  return rows.GroupBy(c=>c.cif+"|"+c.phone,StringComparer.OrdinalIgnoreCase).Select(g=>new CloudCustomer{cif=g.First().cif,customer_name=String.IsNullOrWhiteSpace(g.First().customer_name)?"Khách "+g.First().cif:g.First().customer_name,phone=g.First().phone,contract_number=String.Join(", ",g.Select(c=>c.contract_number).Distinct()),message=""}).OrderBy(c=>c.customer_name).ToList();
 }
 public static string ValidateURL(string value){Uri u;if(!Uri.TryCreate((value??"").Trim().TrimEnd('/'),UriKind.Absolute,out u)||u.Scheme!="https"||u.Host.Length==0||u.UserInfo.Length!=0||u.Query.Length!=0||u.Fragment.Length!=0||u.AbsolutePath!="/")throw new InvalidOperationException("Nhập URL HTTPS gốc của Worker, ví dụ https://bach-crm-sms.ten-cua-anh.workers.dev");return u.GetLeftPart(UriPartial.Authority);}
 public static List<CloudBatch> Batches(IEnumerable<CloudCustomer> customers){
  var output=new List<CloudBatch>();CloudBatch current=null;
  foreach(var c in customers){if(current==null||current.jobs.Count==40){current=new CloudBatch{id=Guid.NewGuid().ToString("N")};output.Add(current);}current.jobs.Add(new CloudJob{id=Guid.NewGuid().ToString("N"),cif=c.cif,customer_name=c.customer_name,phone=c.phone,contract_number=c.contract_number,message=c.message??"",created_at=DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'",CultureInfo.InvariantCulture)});}
  return output;
 }
 internal static void Save(string path,object value){
  Directory.CreateDirectory(Root);byte[] bytes=ProtectedData.Protect(Encoding.UTF8.GetBytes(Json.Serialize(value)),null,DataProtectionScope.CurrentUser);string temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
  try{using(var f=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)){f.Write(bytes,0,bytes.Length);f.Flush(true);}if(File.Exists(path))File.Replace(temp,path,null);else File.Move(temp,path);}finally{if(File.Exists(temp))File.Delete(temp);}
 }
 internal static T Load<T>(string path){return Json.Deserialize<T>(Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(path),null,DataProtectionScope.CurrentUser)));}
 static CloudConfig Config(){return File.Exists(ConfigPath)?Load<CloudConfig>(ConfigPath):null;}
 internal static Dictionary<string,object> Request(CloudConfig config,string method,string route,object body){return Request(config.url,config.writer_token,method,route,body);}
 internal static Dictionary<string,object> Request(string url,string token,string method,string route,object body){
  ServicePointManager.SecurityProtocol|=SecurityProtocolType.Tls12;
  var request=(HttpWebRequest)WebRequest.Create(ValidateURL(url)+route);request.Method=method;request.AllowAutoRedirect=false;request.Timeout=20000;request.ReadWriteTimeout=20000;request.Accept="application/json";request.Headers[HttpRequestHeader.Authorization]="Bearer "+token;
  if(body!=null){byte[] data=Encoding.UTF8.GetBytes(Json.Serialize(body));request.ContentType="application/json; charset=utf-8";request.ContentLength=data.Length;using(var stream=request.GetRequestStream())stream.Write(data,0,data.Length);}
  try{using(var response=(HttpWebResponse)request.GetResponse()){if((int)response.StatusCode<200||(int)response.StatusCode>=300)throw new IOException("Dịch vụ trả phản hồi chưa hợp lệ.");using(var reader=new StreamReader(response.GetResponseStream(),Encoding.UTF8))return Json.Deserialize<Dictionary<string,object>>(reader.ReadToEnd());}}
  catch(WebException ex){var response=ex.Response as HttpWebResponse;if(response==null)throw new IOException("Không kết nối được Cloudflare. Kiểm tra Internet rồi bấm THỬ GỬI LẠI.",ex);using(response){string message="Lỗi kết nối mã "+(int)response.StatusCode;try{using(var reader=new StreamReader(response.GetResponseStream())){var error=Json.Deserialize<Dictionary<string,object>>(reader.ReadToEnd());if(error.ContainsKey("error"))message=Convert.ToString(error["error"]);}}catch{}throw new IOException(message,ex);}}
 }
 internal static async Task Drain(CloudConfig config){
  string path=PendingPath(config);if(!File.Exists(path))return;var pending=Load<CloudTransfer>(path);if(pending.channel!=config.channel)throw new IOException("Hàng chờ thuộc kết nối khác.");
  while(pending.batches.Count>0){var batch=pending.batches[0];var response=await Task.Run(()=>Request(config,"POST","/api/v1/batches",batch));if(!response.ContainsKey("accepted")||Convert.ToInt32(response["accepted"])!=batch.jobs.Count||Convert.ToString(response["id"])!=batch.id)throw new IOException("Cloudflare chưa xác nhận đủ khách. Hàng chờ vẫn giữ trên PC.");pending.batches.RemoveAt(0);if(pending.batches.Count==0)File.Delete(path);else Save(path,pending);}
 }
 public static void Install(object owner){
  var form=owner as Form;if(form==null)return;object marker;if(installed.TryGetValue(form,out marker))return;installed.Add(form,new object());
  var bar=new ToolStrip{Dock=DockStyle.Top,GripStyle=ToolStripGripStyle.Hidden,BackColor=Color.FromArgb(231,241,250)};
  var send=new ToolStripButton("CHUYỂN SANG BÁCH SMS");send.Click+=delegate{OpenPicker(owner);};bar.Items.Add(send);bar.Items.Add(new ToolStripSeparator());
  var config=new ToolStripButton("CẤU HÌNH CLOUDFLARE / MÃ GHÉP");config.Click+=delegate{Setup(form);};bar.Items.Add(config);bar.Items.Add(new ToolStripLabel("Nhận khách qua Wi-Fi / 4G / 5G"));form.Controls.Add(bar);bar.SendToBack();
  var grid=Field(owner,"grid") as DataGridView;if(grid!=null){if(grid.ContextMenuStrip==null)grid.ContextMenuStrip=new ContextMenuStrip();grid.ContextMenuStrip.Items.Add("Chuyển sang Bách SMS (Cloudflare)…",null,delegate{OpenPicker(owner);});}
 }
 static void OpenPicker(object owner){
  var form=(Form)owner;try{
   var source=Invoke(owner,"ActiveCustomers");var customers=Customers(source);if(customers.Count==0){MessageBox.Show(form,"Chưa có khách với CIF và số di động hợp lệ trong danh sách CRM.");return;}
   var selected=new HashSet<string>(StringComparer.OrdinalIgnoreCase);var grid=Field(owner,"grid") as DataGridView;if(grid!=null)foreach(DataGridViewRow row in grid.SelectedRows){object c=Invoke(owner,"GetCustomer",row.Index);if(c!=null)selected.Add(Text(c,"Cif"));}
   using(var picker=new CloudPicker(customers,selected))picker.ShowDialog(form);
  }catch(Exception ex){MessageBox.Show(form,ex.GetBaseException().Message,"Bách SMS",MessageBoxButtons.OK,MessageBoxIcon.Warning);}
 }
 static void ShowPair(Form owner,CloudConfig config){
  using(var f=new Form{Text="Mã liên kết Bách SMS",Size=new Size(710,300),MinimumSize=new Size(550,260),StartPosition=FormStartPosition.CenterParent,Font=new Font("Segoe UI",10)}){
   var layout=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(14),RowCount=3,ColumnCount=1};layout.RowStyles.Add(new RowStyle(SizeType.Absolute,65));layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,44));f.Controls.Add(layout);
   layout.Controls.Add(new Label{Dock=DockStyle.Fill,Text="Trên Bách SMS, mở Kết nối Bách CRM → dán mã dưới đây → Liên kết Cloudflare. Chỉ cần làm một lần. Giữ mã riêng cho điện thoại của anh."},0,0);
   var code=new TextBox{Dock=DockStyle.Fill,Multiline=true,ReadOnly=true,Text=config.pair_code,ScrollBars=ScrollBars.Vertical};layout.Controls.Add(code,0,1);var copy=new Button{Text="SAO CHÉP MÃ",Dock=DockStyle.Fill};copy.Click+=delegate{Clipboard.SetText(config.pair_code);};layout.Controls.Add(copy,0,2);f.ShowDialog(owner);
  }
 }
 static void Setup(Form owner){
  try{var existing=Config();if(existing!=null){ShowPair(owner,existing);return;}}catch(Exception ex){MessageBox.Show(owner,ex.Message);return;}
  using(var f=new Form{Text="Cấu hình Cloudflare lần đầu",Size=new Size(720,430),MinimumSize=new Size(600,400),StartPosition=FormStartPosition.CenterParent,Font=new Font("Segoe UI",10)}){
   var layout=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(16),ColumnCount=1,RowCount=9};f.Controls.Add(layout);
   layout.Controls.Add(new Label{Text="1. URL Worker HTTPS đã triển khai",AutoSize=true});var url=new TextBox{Dock=DockStyle.Top};layout.Controls.Add(url);
   layout.Controls.Add(new Label{Text="2. ADMIN_KEY đã đặt trong Cloudflare (tối thiểu 32 ký tự)",AutoSize=true});var secret=new TextBox{Dock=DockStyle.Top,UseSystemPasswordChar=true};layout.Controls.Add(secret);
   var generate=new Button{Text="Tạo & sao chép khóa mới để đặt vào Cloudflare",AutoSize=true};generate.Click+=delegate{var bytes=new byte[32];using(var rng=RandomNumberGenerator.Create())rng.GetBytes(bytes);secret.Text=BitConverter.ToString(bytes).Replace("-","").ToLowerInvariant();Clipboard.SetText(secret.Text);};layout.Controls.Add(generate);
   layout.Controls.Add(new Label{Text="3. Tên người dùng / thiết bị",AutoSize=true});var name=new TextBox{Dock=DockStyle.Top,Text=Environment.UserName};layout.Controls.Add(name);
   var status=new Label{AutoSize=true,MaximumSize=new Size(650,0),Text="Đọc hướng dẫn kèm gói để tạo Worker và D1. ADMIN_KEY dùng để tạo kết nối; CRM chỉ lưu khóa thiết bị sau khi tạo thành công."};layout.Controls.Add(status);
   var create=new Button{Text="TẠO KẾT NỐI & LẤY MÃ CHO ĐIỆN THOẠI",Dock=DockStyle.Top,Height=44};layout.Controls.Add(create);
   create.Click+=async delegate{create.Enabled=false;generate.Enabled=false;try{
    string endpoint=ValidateURL(url.Text),admin=secret.Text.Trim(),label=name.Text.Trim();if(admin.Length<32||label.Length<1||label.Length>100)throw new InvalidOperationException("Kiểm tra khóa ADMIN_KEY và tên người dùng.");
    status.Text="Đang tạo kết nối…";var response=await Task.Run(()=>Request(endpoint,admin,"POST","/api/v1/channels",new{label=label}));var config=new CloudConfig{url=endpoint,channel=Convert.ToString(response["channel"]),writer_token=Convert.ToString(response["writer_token"]),pair_code=Convert.ToString(response["pair_code"]),label=label};Guid parsed;if(!Guid.TryParse(config.channel,out parsed)||!Regex.IsMatch(config.writer_token,"^w_[a-f0-9]{64}$")||!config.pair_code.StartsWith("bachsms1."))throw new IOException("Dịch vụ trả mã kết nối chưa hợp lệ.");Save(ConfigPath,config);secret.Clear();ShowPair(f,config);f.Close();
   }catch(Exception ex){status.Text=ex.GetBaseException().Message;create.Enabled=true;generate.Enabled=true;}};
   f.ShowDialog(owner);
  }
 }
 sealed class CloudPicker:Form {
  readonly DataTable table=new DataTable();readonly DataGridView grid;readonly Label status;readonly Button send,retry,setup;CloudConfig config;bool busy;
  public CloudPicker(List<CloudCustomer> customers,HashSet<string> selected){
   Text="Chọn khách chuyển sang Bách SMS · Cloudflare";Size=new Size(1000,680);MinimumSize=new Size(800,520);StartPosition=FormStartPosition.CenterParent;Font=new Font("Segoe UI",10);
   table.Columns.Add("Chọn",typeof(bool));table.Columns.Add("CIF");table.Columns.Add("Tên khách");table.Columns.Add("Số điện thoại");table.Columns.Add("Hợp đồng");foreach(var c in customers)table.Rows.Add(selected.Contains(c.cif),c.cif,c.customer_name,c.phone,c.contract_number);
   var layout=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(12),RowCount=4,ColumnCount=1};layout.RowStyles.Add(new RowStyle(SizeType.Absolute,40));layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,65));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,48));Controls.Add(layout);
   var search=new TextBox{Dock=DockStyle.Fill};layout.Controls.Add(search,0,0);search.TextChanged+=delegate{string q=search.Text.Trim().Replace("[","[[]").Replace("%","[%]").Replace("*","[*]").Replace("'","''");table.DefaultView.RowFilter=q.Length==0?"":"CIF LIKE '%"+q+"%' OR [Tên khách] LIKE '%"+q+"%' OR [Số điện thoại] LIKE '%"+q+"%'";};
   grid=new DataGridView{Dock=DockStyle.Fill,DataSource=table,AllowUserToAddRows=false,AllowUserToDeleteRows=false,RowHeadersVisible=false,AutoSizeColumnsMode=DataGridViewAutoSizeColumnsMode.Fill,BackgroundColor=Color.White};layout.Controls.Add(grid,0,1);foreach(DataGridViewColumn col in grid.Columns)col.ReadOnly=col.Index!=0;grid.Columns[0].FillWeight=35;grid.CurrentCellDirtyStateChanged+=delegate{if(grid.IsCurrentCellDirty)grid.CommitEdit(DataGridViewDataErrorContexts.Commit);};
   status=new Label{Dock=DockStyle.Fill,Text="Tích khách muốn chuyển. Dữ liệu gửi gồm CIF, tên, số điện thoại và hợp đồng. Mỗi dòng là một CIF / số điện thoại; nội dung SMS nhập trên điện thoại."};layout.Controls.Add(status,0,2);
   var buttons=new FlowLayoutPanel{Dock=DockStyle.Fill,WrapContents=false};layout.Controls.Add(buttons,0,3);
   var all=new Button{Text="Chọn đang xem",Width=145,Height=38};all.Click+=delegate{foreach(DataRowView row in table.DefaultView)row[0]=true;};buttons.Controls.Add(all);
   var none=new Button{Text="Bỏ chọn",Width=95,Height=38};none.Click+=delegate{foreach(DataRow row in table.Rows)row[0]=false;};buttons.Controls.Add(none);
   setup=new Button{Text="Cấu hình / mã ghép",Width=175,Height=38};setup.Click+=delegate{Setup(this);UpdateState();};buttons.Controls.Add(setup);
   retry=new Button{Text="Thử gửi lại",Width=125,Height=38};retry.Click+=async delegate{await Upload();};buttons.Controls.Add(retry);
   send=new Button{Text="CHUYỂN KHÁCH",Width=165,Height=38,BackColor=Color.FromArgb(18,122,94),ForeColor=Color.White};send.Click+=async delegate{
    grid.EndEdit();var rows=table.Rows.Cast<DataRow>().Where(r=>(bool)r[0]).ToList();if(rows.Count==0){status.Text="Anh chưa tích chọn khách.";return;}if(rows.Count>5000){status.Text="Mỗi lần tối đa 5.000 dòng; lọc và chọn ít hơn.";return;}
    try{config=Config();if(config==null){Setup(this);UpdateState();return;}if(File.Exists(PendingPath(config))){status.Text="Còn hàng chờ chưa chuyển xong. Bấm THỬ GỬI LẠI trước.";return;}
     var chosen=rows.Select(r=>new CloudCustomer{cif=(string)r[1],customer_name=(string)r[2],phone=(string)r[3],contract_number=(string)r[4],message=""});Save(PendingPath(config),new CloudTransfer{channel=config.channel,batches=Batches(chosen)});foreach(var row in rows)row[0]=false;await Upload();
    }catch(Exception ex){status.Text=ex.GetBaseException().Message;UpdateState();}
   };buttons.Controls.Add(send);FormClosing+=delegate(object sender,FormClosingEventArgs e){if(busy)e.Cancel=true;};UpdateState();
  }
  void UpdateState(){try{config=Config();bool pending=config!=null&&File.Exists(PendingPath(config));send.Enabled=!busy&&!pending;retry.Enabled=!busy&&pending;setup.Enabled=!busy;if(pending)status.Text="Có gói chưa chuyển xong được giữ trên PC. Bấm THỬ GỬI LẠI; chương trình dùng lại mã gói để tránh trùng khách.";}catch(Exception ex){status.Text=ex.Message;send.Enabled=false;}}
  async Task Upload(){busy=true;UpdateState();status.Text="Đang chuyển lên Cloudflare…";try{if(config==null)throw new IOException("Chưa có kết nối Cloudflare.");await Drain(config);status.Text="Cloudflare đã nhận đủ khách. Mở Bách SMS → Nhận khách từ CRM. Anh có thể tắt PC sau bước này.";}catch(Exception ex){status.Text=ex.GetBaseException().Message+" Gói chưa xác nhận vẫn được giữ trên PC.";}finally{busy=false;UpdateState();}}
 }
}
