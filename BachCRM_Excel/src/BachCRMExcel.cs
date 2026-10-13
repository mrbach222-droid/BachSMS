using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Globalization;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

// Standalone Sacombank Excel workbook CRM. Never connects to FPT or modifies original Bridge.
// Excel automation edits ONLY worksheet report cells AC:AO of the exact CIF+contract row.
internal sealed class Customer {
    public int Row; public string Contract="",Name="",Cif="",Phone="",Reference="",NewPhone="",Area="",Code="",Other="";
    public decimal Debt; public int Overdue; public bool Reported;
}
internal static class Settings {
    static string Dir { get {string p=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"BachCRMExcel"); Directory.CreateDirectory(p);return p;} }
    public static string WorkbookPath { get {try{return File.ReadAllText(Path.Combine(Dir,"excel_path.txt"),Encoding.UTF8).Trim();}catch{return "";}} set {File.WriteAllText(Path.Combine(Dir,"excel_path.txt"),value??"",Encoding.UTF8);} }
    public static string RequestDir {get{string p=Path.Combine(Dir,"requests");Directory.CreateDirectory(p);return p;}}
    public static void Queue(string cif,string contract,string phone){
        foreach(string s in new[]{cif,contract,phone})if(s.Contains("\r")||s.Contains("\n"))throw new InvalidDataException("Invalid request");
        byte[] b=Encoding.UTF8.GetBytes(cif+"\n"+contract+"\n"+phone+"\n"+DateTime.UtcNow.Ticks.ToString(CultureInfo.InvariantCulture));
        byte[] data=ProtectedData.Protect(b,null,DataProtectionScope.CurrentUser);
        string full=Path.Combine(RequestDir,Guid.NewGuid().ToString("N")+".req");File.WriteAllBytes(full,data);
    }
    public static string[] ReadQueue(string filename){
        byte[] b=ProtectedData.Unprotect(File.ReadAllBytes(filename),null,DataProtectionScope.CurrentUser);
        return Encoding.UTF8.GetString(b).Split('\n');
    }
}
internal static class Util {
    public static string S(object value){return value==null?"":Convert.ToString(value,CultureInfo.InvariantCulture).Trim();}
    public static string Phone(string source){string p=Regex.Replace(source??"",@"[\s().\-]", "");if(p.StartsWith("+84")&&p.Length==12)p="0"+p.Substring(3);else if(p.StartsWith("84")&&p.Length==11)p="0"+p.Substring(2);else if(Regex.IsMatch(p,@"^[35789]\d{8}$"))p="0"+p;return Regex.IsMatch(p,@"^0\d{9}$")?p:"";}
    public static decimal Money(object v){ decimal n; return decimal.TryParse(S(v),NumberStyles.Any,CultureInfo.InvariantCulture,out n)?n:0m;}
    public static string N(decimal v){return v.ToString("N0",new CultureInfo("vi-VN"));}
    public static string Quote(string s){return "\""+(s??"").Replace("\"","")+"\"";}
}
internal sealed class ExcelStore: IDisposable {
    dynamic xl,book,sheet;bool ownExcel;
    public string PathName {get;private set;}
    public List<Customer> Customers {get;private set;}
    public bool ReadOnly {get{return (bool)book.ReadOnly;}}
    public ExcelStore(string path){
        if(!File.Exists(path))throw new FileNotFoundException("Không tìm thấy file Excel",path);
        PathName=System.IO.Path.GetFullPath(path);Customers=new List<Customer>();
        try{
            try{ xl=Marshal.GetActiveObject("Excel.Application");}catch{}
            if(xl!=null){int n=(int)xl.Workbooks.Count;for(int i=1;i<=n;i++){dynamic candidate=xl.Workbooks[i];if(String.Equals(Util.S(candidate.FullName),PathName,StringComparison.OrdinalIgnoreCase)){book=candidate;break;}}}
            if(book==null){xl=Activator.CreateInstance(Type.GetTypeFromProgID("Excel.Application"));ownExcel=true;xl.Visible=false;xl.DisplayAlerts=false;book=xl.Workbooks.Open(PathName,0,false);}
            sheet=book.Worksheets[1];
            string header=Util.S(sheet.Cells[5,2].Value2)+"|"+Util.S(sheet.Cells[5,4].Value2)+"|"+Util.S(sheet.Cells[5,28].Value2);
            if(!header.Contains("Số HĐ")||!header.Contains("CIF")||!header.Contains("Ngày PL"))throw new InvalidDataException("Không đúng mẫu Sacombank (tiêu đề hàng 5 không hợp lệ)");
            Load();
        }catch{Dispose();throw;}
    }
    public void Load(){
        Customers.Clear();int last=(int)sheet.Cells[(int)sheet.Rows.Count,2].End(-4162).Row;
        if(last<6)return;if(last>100000)throw new InvalidDataException("Số dòng dữ liệu vượt mức giới hạn an toàn.");
        object vals=sheet.Range["A6:AO"+last.ToString(CultureInfo.InvariantCulture)].Value2;
        object[,] grid=vals as object[,];if(grid==null)throw new InvalidDataException("Không đọc được vùng A6:AO của Excel.");
        int r0=grid.GetLowerBound(0),c0=grid.GetLowerBound(1);
        for(int idx=0;idx<=grid.GetUpperBound(0)-r0;idx++){
            Func<int,string> s=col=>Util.S(grid[r0+idx,c0+col-1]);
            string contract=s(2),cif=s(4);if(contract.Length==0||cif.Length==0)continue;
            Customer c=new Customer{Row=idx+6,Contract=contract,Cif=cif,Name=s(3),Phone=s(18),Reference=s(24),NewPhone=s(38),Debt=Util.Money(grid[r0+idx,c0+7-1]),Overdue=(int)Util.Money(grid[r0+idx,c0+10-1]),Area=s(27),Code=s(32),Reported=Enumerable.Range(29,13).Any(j=>s(j).Length>0)};
            Customers.Add(c);
        }
    }
    public Customer Exact(int row,string cif,string contract){
        string b=Util.S(sheet.Cells[row,2].Value2),d=Util.S(sheet.Cells[row,4].Value2);
        if(!String.Equals(b,contract,StringComparison.OrdinalIgnoreCase)||!String.Equals(d,cif,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("CIF hoặc Số HĐ tại dòng Excel đã thay đổi. Hủy ghi để tránh nhầm khách.");
        Customer found=Customers.FirstOrDefault(x=>x.Row==row&&x.Cif==cif&&x.Contract==contract);
        if(found==null)throw new InvalidOperationException("Hồ sơ không còn trong bảng theo dõi.");
        return found;
    }
    public string Preview(string contract,string cif){
        List<Customer> hits=Customers.Where(c=>c.Contract==contract&&c.Cif==cif).ToList();
        if(hits.Count!=1)throw new InvalidOperationException("Không tìm thấy duy nhất cặp CIF + HĐ. Cần nạp lại file.");
        return hits[0].Name;
    }
    public void SaveReport(Customer c,ReportData d){
        if(ReadOnly)throw new InvalidOperationException("File Excel đang ở chế độ chỉ đọc. Đóng file xung đột rồi mở lại CRM.");
        Exact(c.Row,c.Cif,c.Contract);
        string directory=System.IO.Path.Combine(System.IO.Path.GetDirectoryName(PathName),"BachCRMExcel_Backup");Directory.CreateDirectory(directory);
        string dest=System.IO.Path.Combine(directory,System.IO.Path.GetFileNameWithoutExtension(PathName)+"_"+DateTime.Now.ToString("yyyyMMdd_HHmmss_fff")+".xlsx");
        book.SaveCopyAs(dest); // all sheets/formatting backed up before every write
        int row=c.Row;
        // Only overwrite report cells when the new value is nonempty. Preserve source A:AB untouched.
        for(int k=0;k<13;k++){
            int col=29+k;string val=d.Text[k];if(String.IsNullOrWhiteSpace(val))continue;
            if(k==2||k==5){
                DateTime date;if(!DateTime.TryParseExact(val,"dd/MM/yyyy",CultureInfo.InvariantCulture,DateTimeStyles.None,out date))throw new InvalidDataException("Ngày không hợp lệ (dd/MM/yyyy).");
                sheet.Cells[row,col].Value2=date.ToOADate();sheet.Cells[row,col].NumberFormat="mm/dd/yyyy";
            }else if(k==4){
                decimal m;if(!decimal.TryParse(val,NumberStyles.AllowThousands|NumberStyles.AllowDecimalPoint,new CultureInfo("vi-VN"),out m))throw new InvalidDataException("Số tiền cam kết trả không hợp lệ.");
                sheet.Cells[row,col].Value2=(double)m;sheet.Cells[row,col].NumberFormat="#,##0";
            }else if(k==7||k==8){
                string old=Util.S(sheet.Cells[row,col].Value2);
                if(old.Length>0 && !old.Contains(val))sheet.Cells[row,col].Value2=old+"\n"+val;
                else if(old.Length==0)sheet.Cells[row,col].Value2=val;
                sheet.Cells[row,col].WrapText=true;
            }else sheet.Cells[row,col].Value2=val;
        }
        try{book.Save();}catch(Exception ex){throw new IOException("Không thể lưu Excel. Bản sao lưu ở: "+dest+". "+ex.Message);}
        Load();
    }
    public void ShowExcel(){try{xl.Visible=true;book.Activate();}catch{}}
    public void Dispose(){
        try{if(ownExcel && book!=null)book.Close(false);}catch{}
        try{if(ownExcel&&xl!=null)xl.Quit();}catch{}
        try{if(book!=null)Marshal.FinalReleaseComObject(book);}catch{}
        try{if(sheet!=null)Marshal.FinalReleaseComObject(sheet);}catch{}
        try{if(ownExcel&&xl!=null)Marshal.FinalReleaseComObject(xl);}catch{}
        book=null;sheet=null;xl=null;
    }
}
internal sealed class ReportData{public string[] Text=new string[13];}
internal sealed class ReportWindow:Form{
    readonly Customer c; readonly ExcelStore store;readonly TextBox[] boxes=new TextBox[13];readonly DateTimePicker[] dates=new DateTimePicker[2]; readonly TextBox amount=new TextBox();readonly ComboBox scenarios=new ComboBox();
    static readonly string[] Labels={"(1) AC · Kênh liên lạc","(2) AD · Người được liên lạc","(3) AE · Ngày liên lạc","(4) AF · Mã kết quả (theo CODE đối tác)","(5) AG · Giá trị cam kết trả nợ","(6) AH · Ngày hành động tiếp theo","(7) AI · Giải pháp thu nợ tiếp theo","(8) AJ · Lịch sử thu nợ","(9) AK · Báo cáo kết quả làm việc","(10) AL · Số điện thoại mới","(11) AM · Thông tin mới điều tra","(12) AN · Lý do / Tình trạng tài sản","(13) AO · Phân loại khách hàng"};
    static readonly string[] TH={"TH1 · Tắt máy","TH2 · Không nghe máy","TH3 · Sai số","TH4 · Không có hứa hẹn","TH5 · Người khác / Sai số","TH6 · Có hứa hẹn"};
    public ReportWindow(ExcelStore s,Customer customer,string phone){
        store=s;c=customer;Text="BÁCH CRM EXCEL  |  GHI BÁO CÁO VÀO EXCEL";Font=new Font("Segoe UI",9);Size=new Size(1000,840);MinimumSize=new Size(870,680);StartPosition=FormStartPosition.CenterParent;BackColor=Color.FromArgb(246,248,252);
        var title=new Label{Text=c.Name+"   ·   CIF "+c.Cif+"   ·   HĐ "+c.Contract+"   ·   dòng "+c.Row,Font=new Font("Segoe UI",11,FontStyle.Bold),ForeColor=Color.FromArgb(24,45,78),Dock=DockStyle.Top,Height=43,Padding=new Padding(18,12,0,0)};Controls.Add(title);
        var warning=new Label{Text="Đối tác dùng danh mục CODE nằm ngoài file này. Chọn TH để soạn nội dung; ô AF/AC/AD/AI/AN/AO phải dùng mã thực tế của đối tác.",ForeColor=Color.DarkRed,Dock=DockStyle.Top,Height=39,Padding=new Padding(18,6,5,3)};Controls.Add(warning);
        var head=new Panel{Dock=DockStyle.Top,Height=54};Controls.Add(head);var thLabel=new Label{Text="MẪU TÌNH HUỐNG",Left=18,Top=19,Width=145};head.Controls.Add(thLabel);
        scenarios.SetBounds(170,13,360,29);scenarios.DropDownStyle=ComboBoxStyle.DropDownList;scenarios.Items.AddRange(TH);head.Controls.Add(scenarios);
        var topBar=new Label{Text="Nhập các trường bên dưới rồi bấm LƯU. Dòng Excel được xác minh lại theo CIF + HĐ trước khi ghi.",Left=548,Top=18,Width=420,Height=25,ForeColor=Color.FromArgb(71,89,119)};head.Controls.Add(topBar);
        var body=new Panel{Dock=DockStyle.Fill,AutoScroll=true};Controls.Add(body);body.BringToFront();
        var bottom=new Panel{Dock=DockStyle.Bottom,Height=63,BackColor=Color.White};Controls.Add(bottom);bottom.BringToFront();
        var save=new Button{Text="LƯU BÁO CÁO VÀO EXCEL",Width=245,Height=38,BackColor=Color.FromArgb(14,106,192),ForeColor=Color.White,FlatStyle=FlatStyle.Flat,Top=12,Anchor=AnchorStyles.Right|AnchorStyles.Top};save.Left=Width-285;save.FlatAppearance.BorderSize=0;bottom.Controls.Add(save);
        var close=new Button{Text="HỦY / QUAY LẠI",Width=155,Height=38,Left=18,Top=12};bottom.Controls.Add(close);close.Click+=delegate{Close();};
        var lines=new TableLayoutPanel{Dock=DockStyle.Top,AutoSize=true,Padding=new Padding(16,6,16,16),ColumnCount=2,RowCount=13};lines.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,285));lines.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));body.Controls.Add(lines);
        for(int i=0;i<13;i++){
            var label=new Label{Text=Labels[i],AutoSize=false,Width=280,Height=28,TextAlign=ContentAlignment.MiddleLeft,ForeColor=Color.FromArgb(34,61,94)};lines.Controls.Add(label,0,i);
            Control input;
            if(i==2||i==5){var dt=new DateTimePicker{Format=DateTimePickerFormat.Custom,CustomFormat="dd/MM/yyyy",Width=205,Value=(i==2?DateTime.Today:DateTime.Today.AddDays(1))};dates[i==2?0:1]=dt;input=dt;}
            else if(i==4){amount.Width=240;amount.Text="";input=amount;}
            else {var box=new TextBox{Width=600,Anchor=AnchorStyles.Left|AnchorStyles.Right,Multiline=(i==7||i==8||i==10),Height=(i==7||i==8?70:(i==10?52:27)),ScrollBars=(i==7||i==8||i==10)?ScrollBars.Vertical:ScrollBars.None};boxes[i]=box;input=box;}
            lines.RowStyles.Add(new RowStyle(SizeType.AutoSize));var wrap=new Panel{Height=(i==7||i==8?79:(i==10?58:34)),Dock=DockStyle.Fill};input.Dock=DockStyle.Top;wrap.Controls.Add(input);lines.Controls.Add(wrap,1,i);
        }
        scenarios.SelectedIndexChanged+=delegate{ApplyScenario(scenarios.SelectedIndex,phone);};
        scenarios.SelectedIndex=1;
        save.Click+=delegate{ Save();};
        Resize+=delegate{save.Left=ClientSize.Width-save.Width-28;};
    }
    void ApplyScenario(int index,string phone){
        if(index<0)return;
        string intro=TH[index].Substring(0,3);string desc=TH[index].Substring(6).Trim();
        string entry=DateTime.Now.ToString("dd/MM/yyyy HH:mm")+" | CALL "+Util.Phone(phone)+" | "+intro+": "+desc+".";
        if(boxes[7]!=null)boxes[7].Text=entry;
        if(boxes[8]!=null)boxes[8].Text=entry;
        // External CODE mapping not supplied: do not invent AF/AI validation codes.
        if(index==5){amount.Focus();}else{amount.Text="";}
    }
    void Save(){
        ReportData d=new ReportData();for(int i=0;i<13;i++)d.Text[i]=boxes[i]==null?"":boxes[i].Text.Trim();
        d.Text[2]=dates[0].Value.ToString("dd/MM/yyyy");d.Text[5]=dates[1].Value.ToString("dd/MM/yyyy");d.Text[4]=amount.Text.Trim();
        if(String.IsNullOrWhiteSpace(d.Text[3])){
            if(MessageBox.Show(this,"Ô AF chưa có MÃ KẾT QUẢ từ danh mục Code của đối tác. Vẫn lưu nội dung AJ/AK và ngày vào Excel (báo cáo còn thiếu mã AF)?","Chưa có mã đối tác",MessageBoxButtons.YesNo,MessageBoxIcon.Warning)!=DialogResult.Yes)return;
        }
        if(d.Text[4].Length>0){decimal m;if(!decimal.TryParse(d.Text[4],NumberStyles.AllowDecimalPoint|NumberStyles.AllowThousands,new CultureInfo("vi-VN"),out m)||m<0){MessageBox.Show(this,"Số tiền cam kết phải là số >= 0, ví dụ 1500000.");return;}}
        try{store.SaveReport(c,d);MessageBox.Show(this,"Đã ghi đúng dòng "+c.Row+" của file Excel và tạo bản sao lưu trước khi ghi.","Hoàn thành",MessageBoxButtons.OK,MessageBoxIcon.Information);DialogResult=DialogResult.OK;Close();}
        catch(Exception ex){MessageBox.Show(this,"Không thể lưu báo cáo: "+ex.Message,"Lỗi",MessageBoxButtons.OK,MessageBoxIcon.Error);}
    }
}
internal sealed class CRM:Form {
    ExcelStore store;readonly DataGridView grid=new DataGridView();readonly TextBox search=new TextBox();readonly Label summary=new Label(),fileLabel=new Label();readonly Timer queueTimer=new Timer(); readonly Dictionary<int,Customer> displayed=new Dictionary<int,Customer>();
    public CRM(){
        Text="BÁCH CRM EXCEL  ·  Sacombank  ·  v0.1";Size=new Size(1370,770);MinimumSize=new Size(1040,650);Font=new Font("Segoe UI",9);BackColor=Color.FromArgb(245,248,252);StartPosition=FormStartPosition.CenterScreen;
        var header=new Panel{Dock=DockStyle.Top,Height=74,BackColor=Color.FromArgb(22,40,69)};Controls.Add(header);
        header.Controls.Add(new Label{Text="BÁCH CRM EXCEL",Left=22,Top=13,ForeColor=Color.White,Font=new Font("Segoe UI",18,FontStyle.Bold),AutoSize=true});
        header.Controls.Add(new Label{Text="Quản lý danh sách · CALL EyeBeam · Báo cáo trực tiếp vào Excel · Độc lập FPT",Left=23,Top=49,ForeColor=Color.FromArgb(188,205,225),AutoSize=true});
        var tools=new Panel{Dock=DockStyle.Top,Height=82,BackColor=Color.White};Controls.Add(tools);
        var choose=MakeButton("CHỌN FILE EXCEL",17,11,155,true);choose.Click+=delegate{ChooseFile();};tools.Controls.Add(choose);
        var reload=MakeButton("TẢI LẠI",183,11,106,false);reload.Click+=delegate{Open(Settings.WorkbookPath);};tools.Controls.Add(reload);
        var openExcel=MakeButton("MỞ FILE EXCEL",301,11,145,false);openExcel.Click+=delegate{if(store!=null)store.ShowExcel();};tools.Controls.Add(openExcel);
        var report=MakeButton("BÁO CÁO ĐÃ CHỌN",458,11,161,false);report.Click+=delegate{ReportSelected("");};tools.Controls.Add(report);
        tools.Controls.Add(new Label{Text="Tìm CIF / HĐ / tên / SĐT",Left=639,Top=17,Width=165,Height=24});search.SetBounds(800,12,300,30);tools.Controls.Add(search);search.TextChanged+=delegate{RefreshRows();};
        fileLabel.SetBounds(20,55,1120,20);fileLabel.ForeColor=Color.FromArgb(90,103,125);tools.Controls.Add(fileLabel);
        var foot=new Panel{Dock=DockStyle.Bottom,Height=39,BackColor=Color.FromArgb(229,235,245)};Controls.Add(foot);summary.SetBounds(20,11,1230,22);summary.ForeColor=Color.FromArgb(34,55,90);foot.Controls.Add(summary);
        grid.Dock=DockStyle.Fill;grid.BackgroundColor=Color.White;grid.BorderStyle=BorderStyle.None;grid.AllowUserToAddRows=false;grid.AllowUserToDeleteRows=false;grid.ReadOnly=true;grid.MultiSelect=false;grid.SelectionMode=DataGridViewSelectionMode.FullRowSelect;grid.RowHeadersVisible=false;grid.AllowUserToResizeRows=false;grid.RowTemplate.Height=36;grid.EnableHeadersVisualStyles=false;grid.ColumnHeadersHeight=43;grid.ColumnHeadersDefaultCellStyle.BackColor=Color.FromArgb(224,233,247);grid.ColumnHeadersDefaultCellStyle.ForeColor=Color.FromArgb(24,48,85);grid.ColumnHeadersDefaultCellStyle.Font=new Font("Segoe UI",9,FontStyle.Bold);
        AddCol("cif","MÃ KH (CIF)",100);AddCol("contract","SỐ HĐ",145);AddCol("name","TÊN KH",220);AddCol("debt","TỔNG DƯ NỢ",142);AddCol("days","SNQH",74);AddCol("phone","ĐTDĐ CÁ NHÂN",135);AddCol("area","KHU VỰC",97);AddCol("result","BÁO CÁO",93);
        var action=new DataGridViewButtonColumn{HeaderText="GỌI KHÁCH",Name="act",Text="TÁC ĐỘNG",UseColumnTextForButtonValue=true,Width=135,AutoSizeMode=DataGridViewAutoSizeColumnMode.None};grid.Columns.Add(action);
        Controls.Add(grid);grid.BringToFront();
        grid.CellContentClick+=delegate(object sender,DataGridViewCellEventArgs e){if(e.RowIndex>=0&&e.ColumnIndex==grid.Columns["act"].Index)CallRow(e.RowIndex);};
        grid.CellDoubleClick+=delegate(object sender,DataGridViewCellEventArgs e){if(e.RowIndex>=0&&e.ColumnIndex>=0&&e.ColumnIndex!=grid.Columns["act"].Index)OpenReport(GetCustomer(e.RowIndex),"");};
        queueTimer.Interval=650;queueTimer.Tick+=delegate{PollReports();};queueTimer.Start();Shown+=delegate{if(File.Exists(Settings.WorkbookPath))Open(Settings.WorkbookPath);else fileLabel.Text="Chọn file Sacombank Excel để bắt đầu. App không tự nhập hồ sơ vào FPT.";};
    }
    Button MakeButton(string t,int left,int top,int width,bool primary){var b=new Button{Text=t,Left=left,Top=top,Width=width,Height=33,FlatStyle=FlatStyle.Flat,BackColor=primary?Color.FromArgb(28,102,183):Color.FromArgb(235,241,249),ForeColor=primary?Color.White:Color.FromArgb(30,55,86)};b.FlatAppearance.BorderSize=0;return b;}
    void AddCol(string name,string title,int width){grid.Columns.Add(new DataGridViewTextBoxColumn{Name=name,HeaderText=title,Width=width,SortMode=DataGridViewColumnSortMode.NotSortable});}
    void ChooseFile(){using(var d=new OpenFileDialog{Filter="Excel (*.xlsx)|*.xlsx",Title="Chọn file Excel Sacombank"})if(d.ShowDialog(this)==DialogResult.OK)Open(d.FileName);}
    void Open(string path){if(!File.Exists(path))return;
        try{ExcelStore next=new ExcelStore(path); if(store!=null)store.Dispose();store=next;Settings.WorkbookPath=path;fileLabel.Text="FILE ĐANG DÙNG: "+path+(store.ReadOnly?"     [CHỈ ĐỌC]":"");RefreshRows();}
        catch(Exception e){MessageBox.Show(this,"Không mở được file Excel: "+e.Message+"\n\nYêu cầu máy cài Microsoft Excel. Đóng những file bị khóa nếu cần.");}
    }
    void RefreshRows(){
        grid.Rows.Clear();displayed.Clear();if(store==null){summary.Text="Chưa chọn Excel";return;}
        string term=search.Text.Trim();IEnumerable<Customer> list=store.Customers;
        if(term.Length>0)list=list.Where(c=>(c.Cif+" "+c.Contract+" "+c.Name+" "+c.Phone+" "+c.Reference).IndexOf(term,StringComparison.OrdinalIgnoreCase)>=0);
        int i=0;foreach(Customer c in list){int r=grid.Rows.Add(c.Cif,c.Contract,c.Name,Util.N(c.Debt),c.Overdue,Util.Phone(c.Phone).Length>0?Util.Phone(c.Phone):"(thiếu)",c.Area,c.Reported?"Đã ghi":"Chưa ghi");displayed[r]=c;if(i++%2==0)grid.Rows[r].DefaultCellStyle.BackColor=Color.FromArgb(251,253,255);if(Util.Phone(c.Phone).Length==0)grid.Rows[r].Cells["phone"].Style.ForeColor=Color.DarkRed;}
        summary.Text="TỔNG HỢP ĐỒNG: "+store.Customers.Count+"     ·     KH HIỂN THỊ: "+i+"     ·     SỐ CIF: "+store.Customers.Select(x=>x.Cif).Distinct().Count()+"     ·     ĐÃ CÓ BÁO CÁO: "+store.Customers.Count(x=>x.Reported)+"      |  Báo cáo viết vào AC:AO";
    }
    Customer GetCustomer(int row){Customer c;return displayed.TryGetValue(row,out c)?c:null;}
    Customer Selected(){return grid.CurrentRow==null?null:GetCustomer(grid.CurrentRow.Index);}
    void ReportSelected(string phone){Customer c=Selected();if(c==null)return;OpenReport(c,phone);}
    void OpenReport(Customer c,string phone){if(c==null||store==null)return;try{store.Exact(c.Row,c.Cif,c.Contract);using(var f=new ReportWindow(store,c,phone))f.ShowDialog(this);RefreshRows();}catch(Exception e){MessageBox.Show(this,e.Message);}}
    void CallRow(int idx){Customer c=GetCustomer(idx);if(c==null)return;try{store.Exact(c.Row,c.Cif,c.Contract);}catch(Exception e){MessageBox.Show(this,e.Message);return;}
        var phones=new List<KeyValuePair<string,string>>();foreach(var v in new[]{new KeyValuePair<string,string>("SĐT cá nhân (R)",c.Phone),new KeyValuePair<string,string>("SĐT tham chiếu (X)",c.Reference),new KeyValuePair<string,string>("SĐT mới (AL)",c.NewPhone)}){
            string p=Util.Phone(v.Value);if(p.Length>0&&!phones.Any(x=>x.Value==p))phones.Add(new KeyValuePair<string,string>(v.Key,p));}
        if(phones.Count==0){MessageBox.Show(this,"Dòng này chưa có SĐT hợp lệ. Hãy kiểm tra cột R, X hoặc AL.");return;}
        string selected="";
        using(var d=new Form{Text="CHỌN SỐ GỌI · "+c.Name,Size=new Size(485,270),StartPosition=FormStartPosition.CenterParent,Font=Font,FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,MinimizeBox=false}){
            d.Controls.Add(new Label{Left=17,Top=13,Width=440,Height=30,Text="CIF "+c.Cif+" · HĐ "+c.Contract+" — chọn số để đưa vào EyeBeam:"});
            var combo=new ComboBox{Left=17,Top=49,Width=440,DropDownStyle=ComboBoxStyle.DropDownList};foreach(var p in phones)combo.Items.Add(p.Key+"   ·   "+p.Value);combo.SelectedIndex=0;d.Controls.Add(combo);
            d.Controls.Add(new Label{Text="CRM chỉ điền số. Bạn phải tự bấm Enter trên EyeBeam để gọi.",Left=17,Top=91,Width=440,Height=42,ForeColor=Color.FromArgb(85,106,139)});
            var ok=MakeButton("MỞ EYEBEAM",160,150,160,true);d.Controls.Add(ok);ok.Click+=delegate{selected=phones[combo.SelectedIndex].Value;d.DialogResult=DialogResult.OK;d.Close();};
            if(d.ShowDialog(this)!=DialogResult.OK)return;
        }
        string exe=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"BachCRMExcelBridge.exe");if(!File.Exists(exe)){MessageBox.Show(this,"Thiếu BachCRMExcelBridge.exe — chạy BUILD_AND_START.cmd.");return;}
        try{System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo{FileName=exe,UseShellExecute=false,WorkingDirectory=AppDomain.CurrentDomain.BaseDirectory,Arguments="--phone "+Util.Quote(selected)+" --cif "+Util.Quote(c.Cif)+" --contract "+Util.Quote(c.Contract)});}
        catch(Exception e){MessageBox.Show(this,"Không mở được Bridge: "+e.Message);}
    }
    void PollReports(){
        if(store==null)return;string[] files;
        try{files=Directory.GetFiles(Settings.RequestDir,"*.req");}catch{return;}
        foreach(string f in files.Take(3)){
            try{string[] payload=Settings.ReadQueue(f);File.Delete(f);if(payload.Length<4)continue;
                string cif=payload[0],contract=payload[1],phone=payload[2];long ticks;
                if(!long.TryParse(payload[3],out ticks)||Math.Abs((DateTime.UtcNow-new DateTime(ticks,DateTimeKind.Utc)).TotalMinutes)>120)continue;
                var hits=store.Customers.Where(x=>x.Cif==cif&&x.Contract==contract).ToList();if(hits.Count!=1){MessageBox.Show(this,"Cuộc gọi hoàn tất nhưng không tìm đúng CIF/HĐ trong Excel. Không mở báo cáo nhầm khách.");continue;}
                WindowState=FormWindowState.Normal;Activate();OpenReport(hits[0],phone);
            }catch(Exception e){try{File.Move(f,f+".failed");}catch{}MessageBox.Show(this,"Lỗi nhận sự kiện kết thúc cuộc gọi: "+e.Message);}
        }
    }
    protected override void OnFormClosed(FormClosedEventArgs e){queueTimer.Stop();if(store!=null)store.Dispose();base.OnFormClosed(e);}
}
internal static class Program {
    [STAThread]static void Main(string[] args){Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new CRM());}
}