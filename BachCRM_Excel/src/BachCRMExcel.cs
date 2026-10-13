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
// Excel automation edits ONLY worksheet report cells AD:AP for all verified contracts of the selected CIF.
// The existing Excel worksheet is not modified to add macros or move columns.
internal sealed class Customer {
    public int Row; public string Contract="",Name="",Cif="",Phone="",Reference="",ReferenceName="",NewPhone="",Area="",Code="",Other="";
    public decimal Debt; public int Overdue; public DateTime? NextAction; public bool Reported, YellowRow, Promised, Care;
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
internal static class ReportLogic {
    // Reference and customer calls have different disclosure/context; never infer outcome.
    public static string ReferenceLine(string phone){
        string normalized=Util.Phone(phone);
        if(normalized.Length==0)throw new ArgumentException("SĐT tham chiếu không hợp lệ");
        return "CALL Số tham chiếu "+normalized+" : ";
    }
    public static bool ReferenceHasOutcome(string note,string phone){
        string marker=ReferenceLine(phone);
        int at=(note??"").LastIndexOf(marker,StringComparison.OrdinalIgnoreCase);
        return at>=0&&!String.IsNullOrWhiteSpace((note??"").Substring(at+marker.Length));
    }
    // Strict CIF matching: never use customer name, phone number, or contract similarity.
    public static bool SameCif(string a,string b){
        return !String.IsNullOrWhiteSpace(a) && String.Equals(a.Trim(),(b??"").Trim(),StringComparison.OrdinalIgnoreCase);
    }
    public static string ScenarioEntry(string label,string phone){
        // TH codes are ONLY selector names; never store those codes inside AK/AL.
        string detail=Regex.Replace(label??"",@"^TH[1-6]\s*[·:\-]\s*","",RegexOptions.IgnoreCase).Trim().TrimEnd('.');
        string dialed=Util.Phone(phone);
        return (dialed.Length>0?"CALL "+dialed+" : ":"CALL : ")+detail+".";
    }
    public static string MergeTodayResults(IEnumerable<string> previous,string current,DateTime reportDay){
        // AL is a daily activity summary. Keep only the entries from reportDay, older
        // calendar days are replaced, AK is the immutable long-lived history instead.
        string prefix=reportDay.ToString("dd/MM/yyyy",CultureInfo.InvariantCulture);
        var lines=new List<string>();var seen=new HashSet<string>(StringComparer.Ordinal);
        foreach(string old in previous??Enumerable.Empty<string>()){
            string[] items=(old??"").Replace("\r\n","\n").Replace('\r','\n').Split('\n');
            bool currentDay=false;
            foreach(string line in items){
                var t=line.Trim();if(t.Length==0)continue;
                var match=Regex.Match(t,@"^(\d{2}/\d{2}/\d{4})(?=\s|$)");
                if(match.Success){currentDay=match.Groups[1].Value==prefix;}
                if(currentDay&&seen.Add(t))lines.Add(t);
            }
        }
        foreach(string line in (current??"").Replace("\r\n","\n").Replace('\r','\n').Split('\n')){
            var t=line.Trim();if(t.Length>0&&seen.Add(t))lines.Add(t);
        }
        string answer=String.Join("\n",lines);
        if(answer.Length>32767)throw new InvalidDataException("Báo cáo AL vượt giới hạn 32.767 ký tự Excel.");
        return answer;
    }
    // Join nonempty, distinct history lines across ALL contracts of one customer.
    // Existing notes are never deleted; duplicates already copied to other contracts are collapsed.
    public static string MergeHistory(IEnumerable<string> previous,string current){
        var entries=new List<string>();var seen=new HashSet<string>(StringComparer.Ordinal);
        foreach(string history in previous ?? Enumerable.Empty<string>()){
            foreach(string line in (history??"").Replace("\r\n","\n").Replace('\r','\n').Split('\n')){
                string entry=line.Trim();
                if(entry.Length>0 && seen.Add(entry))entries.Add(entry);
            }
        }
        foreach(string line in (current??"").Replace("\r\n","\n").Replace('\r','\n').Split('\n')){
            string entry=line.Trim();
            if(entry.Length>0 && seen.Add(entry))entries.Add(entry);
        }
        string result=String.Join("\n",entries);
        if(result.Length>32767)throw new InvalidDataException("Lịch sử AK vượt giới hạn 32.767 ký tự của Excel. Không lưu để tránh mất dữ liệu.");
        return result;
    }
}
// UI-only position snapshot. Never persisted to the Excel workbook.
internal sealed class GridPosition {
    public int SelectedExcelRow=-1,TopExcelRow=-1,SelectedIndex=-1,TopIndex=-1,ColumnIndex=0,HorizontalOffset=0;
}
internal static class GridStateLogic {
    // Workbook row is unique even when a CIF has several contracts and search filters are active.
    public static int FindIndex(IDictionary<int,Customer> visible,int workbookRow,int fallback) {
        if(visible!=null && workbookRow>0){
            foreach(var entry in visible)if(entry.Value!=null && entry.Value.Row==workbookRow)return entry.Key;
        }
        return visible!=null && fallback>=0 && fallback<visible.Count ? fallback : -1;
    }
}
// Customer-care membership is computed from the *actual* Excel workbook and is deduplicated by CIF.
// Colour components of Excel Interior.Color are encoded as 0x00BBGGRR (OLE_COLOR).
internal static class CareLogic {
    public static bool IsYellow(object excelColor){
        if(excelColor==null)return false;
        int ole;
        try{ole=Convert.ToInt32(excelColor,CultureInfo.InvariantCulture);}catch{return false;}
        int r=ole & 255,g=(ole>>8)&255,b=(ole>>16)&255;
        // Bright or pastel yellow, not the orange/peach colour of ordinary customer-name cells.
        return r>=195 && g>=180 && ((b<=125 && g-b>=55) || (g>=225 && g-b>=25));
    }
    public static bool IsPromise(string action,string classification){
        string a=(action??"").ToLowerInvariant(),c=(classification??"").ToLowerInvariant();
        if(c.Contains("không hứa")||a.Contains("không hứa")||c.Contains("không có hứa")||a.Contains("không có hứa")||c.Contains("chưa hứa")||a.Contains("chưa hứa"))return false;
        return c.Contains("có hứa")||a.Contains("hứa thanh toán");
    }
    public static bool NeedsCare(Customer c){return c!=null&&(c.Care||c.Promised||c.YellowRow);}
    public static List<Customer> UniqueCare(IEnumerable<Customer> source){
        return source.GroupBy(x=>x.Cif,StringComparer.OrdinalIgnoreCase)
            .Where(g=>g.Any(NeedsCare)).Select(g=>g.OrderBy(x=>x.Row).First()).OrderBy(x=>x.Row).ToList();
    }
}
internal static class CareSortLogic {
    public static DateTime? Earliest(IEnumerable<Customer> group){
        var dates=group.Where(x=>x.NextAction.HasValue).Select(x=>x.NextAction.Value).ToList();
        return dates.Count==0?(DateTime?)null:dates.Min();
    }
    public static bool Urgent(DateTime? date,DateTime today){return date.HasValue&&date.Value.Date<=today.Date.AddDays(3);}
    // Manual yellow rows take precedence; within that tier deadlines are ordered earliest first.
    public static IEnumerable<IGrouping<string,Customer>> Sort(IEnumerable<IGrouping<string,Customer>> groups,DateTime today){
        return groups.OrderByDescending(g=>g.Any(x=>x.YellowRow))
                     .ThenBy(g=>Earliest(g).HasValue?0:1)
                     .ThenBy(g=>Earliest(g)??DateTime.MaxValue)
                     .ThenBy(g=>g.Min(x=>x.Row));
    }
}
internal sealed class FastDataGridView:DataGridView {
    public FastDataGridView(){DoubleBuffered=true;}
}
internal sealed class ReferenceSession {
    public string Cif,Contract,FirstPhone,RefPhone,RefName;
    public int FirstScenario;
    public bool Matches(string cif,string contract,string phone){return ReportLogic.SameCif(cif,Cif)&&
        String.Equals(contract,Contract,StringComparison.OrdinalIgnoreCase)&&Util.Phone(phone)==RefPhone;}
}
internal static class MbReportTemplates {
    // Copied verbatim from DienBaoCaoMB original; TH labels are UI only.
    static readonly string[] Notes={
        "CALL [SDT KH] : Thuê bao mất liên lạc, không có tín hiệu kết nối.",
        "CALL [SDT KH] : Có tín hiệu, không nghe máy.",
        "CALL [SDT KH] : Số máy gọi không đúng/không có",
        "CALL [SDT KH] : Đúng KH, trao đổi về khoản nợ, ",
        "CALL [SDT KH]: Báo không phải KH, không biết KH",
        "CALL [SDT KH]: Xác thực đúng KH, trao đổi về khoản nợ hẹn...."
    };
    public static readonly string[] ContactPerson={"Không gặp ai","Không gặp ai","Không gặp ai","Khách hàng","Người khác","Khách hàng"};
    public static readonly string[] Action={"Không có tín hiệu","Có tín hiệu không bắt máy","Số không tồn tại, số không đúng","KN hẹn làm việc lại","Không phải số KN / Số người thân khác","Hứa thanh toán"};
    public static readonly string[] Classification={"Call - Tắt máy","Call - Không nghe máy","Call - Sai số","Call - Không hứa thanh toán","Call - Sai số","Call - Có hứa thanh toán"};
    // Only missed/incorrect-number situations receive an SMS follow-up sentence.
    // TH4 (no payment promise) and TH6 (payment promise) must remain verbatim.
    public const string SmsFollowup = "Nhắn tin SMS chờ phản hồi xác thực.";
    public static string Note(int scenario,string phone){
        if(scenario<0||scenario>=Notes.Length)throw new ArgumentOutOfRangeException("scenario");
        string p=Util.Phone(phone);
        string note=Notes[scenario].Replace("[SDT KH]",p.Length>0?p:"[SDT KH]").TrimEnd();
        if(scenario==0||scenario==1||scenario==2||scenario==4){
            // Return a fresh note for each TH selection; switching templates never doubles the suffix.
            if(!note.EndsWith(".")&&!note.EndsWith("!")&&!note.EndsWith("?"))note+=".";
            note+=" "+SmsFollowup;
        }
        return note;
    }
}
// Registered on the main STA thread: Excel may temporarily reject COM calls while a
// dropdown/editor/modal dialog is active. The OLE message filter retries the *same*
// rejected COM request; no write/report transaction is replayed wholesale.
internal static class ExcelComBusyFilter {
    [ComImport,Guid("00000016-0000-0000-C000-000000000046"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IOleMessageFilter {
        [PreserveSig] int HandleInComingCall(int type,IntPtr task,int ticks,IntPtr info);
        [PreserveSig] int RetryRejectedCall(IntPtr task,int ticks,int rejection);
        [PreserveSig] int MessagePending(IntPtr task,int ticks,int pending);
    }
    sealed class Filter:IOleMessageFilter {
        public int HandleInComingCall(int type,IntPtr task,int ticks,IntPtr info){return 0;}
        public int RetryRejectedCall(IntPtr task,int ticks,int rejection){
            // SERVERCALL_REJECTED and SERVERCALL_RETRYLATER; do not retry forever.
            if((rejection==1||rejection==2)&&ticks<8500)return 180;
            return -1;
        }
        public int MessagePending(IntPtr task,int ticks,int pending){return 2;}
    }
    [DllImport("ole32.dll")] static extern int CoRegisterMessageFilter(IOleMessageFilter current,out IOleMessageFilter previous);
    static IOleMessageFilter previous; static IOleMessageFilter registered;
    public static void Install(){
        registered=new Filter();
        int hr=CoRegisterMessageFilter(registered,out previous);
        if(hr<0)Marshal.ThrowExceptionForHR(hr);
    }
    public static void Remove(){
        if(registered==null)return;
        IOleMessageFilter ignored;
        CoRegisterMessageFilter(previous,out ignored);registered=null;previous=null;
    }
    public static bool IsBusy(Exception ex){
        COMException com=ex as COMException;
        return com!=null && (com.ErrorCode==unchecked((int)0x80010001)||com.ErrorCode==unchecked((int)0x8001010A));
    }
    public static T RetryRead<T>(Func<T> get){
        // The message filter retries most COM calls internally. This covers the
        // exceptional case where Excel returns BUSY despite the OLE filter.
        for(int i=0;;i++)try{return get();}
        catch(Exception ex){
            if(!IsBusy(ex)||i>=5)throw;
            System.Threading.Thread.Sleep(180+i*100);
        }
    }
}

internal sealed class ExcelStore: IDisposable {
    dynamic xl,book,sheet;bool ownExcel;
    public string PathName {get;private set;}
    public List<Customer> Customers {get;private set;}
    public bool ReadOnly {get{if(book!=null)return (bool)book.ReadOnly;return (File.GetAttributes(PathName)&FileAttributes.ReadOnly)!=0;}}
    public ExcelStore(string path){
        if(!File.Exists(path))throw new FileNotFoundException("Không tìm thấy file Excel",path);
        PathName=System.IO.Path.GetFullPath(path);
        // All list/display data is loaded directly from ZIP/XML in one read; no Excel COM calls
        // or per-row colour queries while the operator is browsing the CRM.
        Customers=FastXlsxReader.Load(PathName);
    }
    public void Load(){Customers=FastXlsxReader.Load(PathName);}
    void EnsureExcel(){
        if(book!=null)return;
        try{
            try{xl=Marshal.GetActiveObject("Excel.Application");}catch(COMException ex){if(ExcelComBusyFilter.IsBusy(ex))throw;}catch{}
            if(xl!=null){int n=(int)xl.Workbooks.Count;for(int i=1;i<=n;i++){
                dynamic candidate=xl.Workbooks[i];if(String.Equals(Util.S(candidate.FullName),PathName,StringComparison.OrdinalIgnoreCase)){book=candidate;break;}
            }}
            if(book==null){
                xl=Activator.CreateInstance(Type.GetTypeFromProgID("Excel.Application"));ownExcel=true;
                xl.Visible=false;xl.DisplayAlerts=false;book=xl.Workbooks.Open(PathName,0,false);
            }
            try{sheet=book.Worksheets["Sheet1"];}
            catch{throw new InvalidDataException("Không thấy Sheet1 trong Excel Sacombank.");}
        }catch{Dispose();throw;}
    }
    public Customer Exact(int row,string cif,string contract){
        EnsureExcel();
        string b=Util.S(sheet.Cells[row,2].Value2),d=Util.S(sheet.Cells[row,5].Value2);
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
    public int CustomerContractCount(string cif){
        return Customers.Count(x=>ReportLogic.SameCif(x.Cif,cif));
    }
    public int SaveReport(Customer c,ReportData d,bool markCare){
        EnsureExcel();
        if(ReadOnly)throw new InvalidOperationException("File Excel đang ở chế độ chỉ đọc. Đóng file xung đột rồi mở lại CRM.");
        Exact(c.Row,c.Cif,c.Contract);
        // The report belongs to the customer CIF. Every distinct contract must get the same
        // current action, while AK collects the history from all those contracts.
        List<Customer> targets=Customers.Where(x=>ReportLogic.SameCif(x.Cif,c.Cif)).OrderBy(x=>x.Row).ToList();
        if(targets.Count==0)throw new InvalidOperationException("Không tìm thấy hồ sơ theo CIF trong Excel.");
        foreach(Customer target in targets)Exact(target.Row,target.Cif,target.Contract);

        object[] prepared=new object[13];
        for(int k=0;k<13;k++){
            string val=d.Text[k]??"";
            if(val.Length>32767)throw new InvalidDataException("Nội dung cột "+(30+k)+" quá 32.767 ký tự.");
            if(String.IsNullOrWhiteSpace(val))continue;
            if(k==2||k==5){
                DateTime date;
                if(!DateTime.TryParseExact(val,"dd/MM/yyyy",CultureInfo.InvariantCulture,DateTimeStyles.None,out date))throw new InvalidDataException("Ngày không hợp lệ (dd/MM/yyyy).");
                prepared[k]=date.ToOADate();
            }else if(k==4){
                decimal m;
                if(!decimal.TryParse(val,NumberStyles.AllowThousands|NumberStyles.AllowDecimalPoint,new CultureInfo("vi-VN"),out m))throw new InvalidDataException("Số tiền cam kết trả không hợp lệ.");
                prepared[k]=(double)m;
            }else prepared[k]=val;
        }
        // Read history only for contracts belonging to this exact CIF.
        string history=ReportLogic.MergeHistory(targets.Select(x=>Util.S((object)sheet.Cells[x.Row,37].Value2)), d.Text[7]);
        if(!String.IsNullOrWhiteSpace(history))prepared[7]=history;
        DateTime reportDay=DateTime.Today;
        DateTime parsedDay;
        if(DateTime.TryParseExact(d.Text[2],"dd/MM/yyyy",CultureInfo.InvariantCulture,DateTimeStyles.None,out parsedDay))reportDay=parsedDay.Date;
        string today=ReportLogic.MergeTodayResults(targets.Select(x=>Util.S((object)sheet.Cells[x.Row,38].Value2)),d.Text[8],reportDay);
        if(today.Length>0)prepared[8]=today;


        string directory=System.IO.Path.Combine(System.IO.Path.GetDirectoryName(PathName),"BachCRMExcel_Backup");Directory.CreateDirectory(directory);
        string dest=System.IO.Path.Combine(directory,System.IO.Path.GetFileNameWithoutExtension(PathName)+"_"+DateTime.Now.ToString("yyyyMMdd_HHmmss_fff")+".xlsx");
        // Keep this real Excel workbook backup BEFORE any write, even in fast mode.
        book.SaveCopyAs(dest);
        try{
            foreach(Customer target in targets){
                int row=target.Row;
                // Preserve old values AND formulas in blank fields. One COM read + one COM write
                // per contract replaces up to 13 separate COM writes in the previous version.
                dynamic range=sheet.Range["AD"+row.ToString(CultureInfo.InvariantCulture)+":AP"+row.ToString(CultureInfo.InvariantCulture)];
                object[,] values=(object[,])range.Formula;
                int rr=values.GetLowerBound(0),cc=values.GetLowerBound(1);
                for(int k=0;k<13;k++)if(prepared[k]!=null)values[rr,cc+k]=prepared[k];
                range.Formula=values;
                // These number formats are applied once per changed row, never to all customers.
                if(prepared[2]!=null)sheet.Cells[row,32].NumberFormat="dd/mm/yyyy"; // AF
                if(prepared[5]!=null)sheet.Cells[row,35].NumberFormat="dd/mm/yyyy"; // AI
                if(prepared[4]!=null)sheet.Cells[row,34].NumberFormat="#,##0"; // AH
                if(markCare){
                    // The user explicitly asked to highlight the *whole* contract row.
                    // Use one Interior call per contract and mark every agreement of this CIF.
                    sheet.Range["A"+row.ToString(CultureInfo.InvariantCulture)+":AP"+row.ToString(CultureInfo.InvariantCulture)].Interior.Color=65535; // Excel bright yellow
                }
            }
            book.Save();
        }catch(Exception ex){
            throw new IOException("Không lưu được Excel. Hãy đóng Excel KHÔNG lưu các thay đổi chưa hoàn tất và khôi phục bản sao lưu nếu cần. Bản sao: "+dest+". "+ex.Message,ex);
        }
        // Fast path: refresh only the contracts actually written. Do NOT scan the
        // entire Excel book + 1000+ colour COM calls after each saved report.
        foreach(Customer target in targets){
            target.Reported=true;
            if(!String.IsNullOrWhiteSpace(d.Text[3]))target.Code=d.Text[3];
            target.Promised=target.Promised||CareLogic.IsPromise(d.Text[3],d.Text[12]);
            if(markCare)target.YellowRow=true;
            target.Care=target.Promised||target.YellowRow;
            DateTime next;
            if(DateTime.TryParseExact(d.Text[5],"dd/MM/yyyy",CultureInfo.InvariantCulture,DateTimeStyles.None,out next))target.NextAction=next.Date;
        }
        return targets.Count;
    }
    // Review the original report fields (including unsaved Excel changes) before editing.
    public string[] ReadReport(Customer c){
        Exact(c.Row,c.Cif,c.Contract);
        object[,] raw=(object[,])sheet.Range["AD"+c.Row+":AP"+c.Row].Value2;
        var arr=new string[13];int r=raw.GetLowerBound(0),k=raw.GetLowerBound(1);
        for(int i=0;i<13;i++){
            object v=raw[r,k+i];
            if(v!=null&&(i==2||i==5)){
                double oa;
                if(double.TryParse(Util.S(v),NumberStyles.Any,CultureInfo.InvariantCulture,out oa)&&oa>30000&&oa<100000){
                    arr[i]=DateTime.FromOADate(oa).ToString("dd/MM/yyyy",CultureInfo.InvariantCulture);continue;
                }
            }
            arr[i]=Util.S(v);
        }
        return arr;
    }
    public int CorrectReport(Customer c,string[] oldValues,string[] edited){
        EnsureExcel();if(ReadOnly)throw new InvalidOperationException("Excel đang chỉ đọc.");
        if(oldValues==null||edited==null||oldValues.Length!=13||edited.Length!=13)throw new ArgumentException("Thiếu dữ liệu báo cáo.");
        var changed=Enumerable.Range(0,13).Where(i=>!String.Equals(oldValues[i]??"",edited[i]??"",StringComparison.Ordinal)).ToArray();
        if(changed.Length==0)return 0;
        var targets=Customers.Where(x=>ReportLogic.SameCif(x.Cif,c.Cif)).ToList();
        foreach(var target in targets)Exact(target.Row,target.Cif,target.Contract);
        var prepared=new Dictionary<int,object>();
        foreach(int i in changed){
            string val=edited[i]??"";
            if(val.Length>32767)throw new InvalidDataException("Ô Excel vượt giới hạn ký tự.");
            if((i==2||i==5)&&val.Length>0){DateTime date;
                if(!DateTime.TryParseExact(val,"dd/MM/yyyy",CultureInfo.InvariantCulture,DateTimeStyles.None,out date))throw new InvalidDataException("Ngày phải theo dd/MM/yyyy.");
                prepared[i]=date.ToOADate();
            }else if(i==4&&val.Length>0){decimal money;
                if(!decimal.TryParse(val,NumberStyles.Any,new CultureInfo("vi-VN"),out money))throw new InvalidDataException("Số tiền không hợp lệ.");
                prepared[i]=(double)money;
            }else prepared[i]=val;
        }
        // Never turn an edit into a new activity: existing AK/AL text is corrected in place.
        string dir=Path.Combine(Path.GetDirectoryName(PathName),"BachCRMExcel_Backup");Directory.CreateDirectory(dir);
        string dest=Path.Combine(dir,Path.GetFileNameWithoutExtension(PathName)+"_SUA_"+DateTime.Now.ToString("yyyyMMdd_HHmmss_fff")+".xlsx");
        book.SaveCopyAs(dest);
        try{
            foreach(var target in targets){
                object[,] row=(object[,])sheet.Range["AD"+target.Row+":AP"+target.Row].Formula;
                int a=row.GetLowerBound(0),b=row.GetLowerBound(1);
                foreach(var item in prepared)row[a,b+item.Key]=item.Value;
                sheet.Range["AD"+target.Row+":AP"+target.Row].Formula=row;
            }
            book.Save();
        }catch(Exception ex){throw new IOException("Không hoàn tất sửa báo cáo. Kiểm tra bản sao: "+dest+". "+ex.Message,ex);}
        foreach(var target in targets){
            if(prepared.ContainsKey(3))target.Code=edited[3];
            if(prepared.ContainsKey(5)){DateTime d;if(DateTime.TryParseExact(edited[5],"dd/MM/yyyy",CultureInfo.InvariantCulture,DateTimeStyles.None,out d))target.NextAction=d;}
            target.Promised=CareLogic.IsPromise(target.Code,prepared.ContainsKey(12)?edited[12]:"");
            target.Care=target.YellowRow||target.Promised;
        }
        return targets.Count;
    }
    public void ShowExcel(){try{EnsureExcel();xl.Visible=true;book.Activate();sheet.Activate();}catch(Exception e){throw new InvalidOperationException("Không mở được Excel: "+e.Message,e);}}
    public Customer SelectedExcelCustomer(){
        try{EnsureExcel();
            if(xl==null||book==null||sheet==null)return null;
            dynamic activeBook=xl.ActiveWorkbook;
            if(!String.Equals(Util.S(activeBook.FullName),PathName,StringComparison.OrdinalIgnoreCase))return null;
            if(!String.Equals(Util.S(xl.ActiveSheet.Name),"Sheet1",StringComparison.OrdinalIgnoreCase))return null;
            int row=(int)xl.ActiveCell.Row;
            Customer c=Customers.FirstOrDefault(x=>x.Row==row);
            if(c==null)return null;
            Exact(c.Row,c.Cif,c.Contract);
            return c;
        }catch{return null;}
    }
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd,out RECT rect);
    [StructLayout(LayoutKind.Sequential)] public struct RECT{public int Left,Top,Right,Bottom;}
    public bool TryExcelBounds(out System.Drawing.Rectangle bounds){
        bounds=System.Drawing.Rectangle.Empty;
        try{EnsureExcel();
            if(xl==null)return false;
            IntPtr hwnd=new IntPtr(Convert.ToInt64(xl.Hwnd));
            RECT r;if(hwnd==IntPtr.Zero||!GetWindowRect(hwnd,out r))return false;
            bounds=System.Drawing.Rectangle.FromLTRB(r.Left,r.Top,r.Right,r.Bottom);return true;
        }catch{return false;}
    }
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
internal static class PartnerCodes {
    static readonly Dictionary<string,List<string>> values=new Dictionary<string,List<string>>(StringComparer.OrdinalIgnoreCase);
    static PartnerCodes(){
        string path=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"BachCRMExcel_Codes.tsv");
        if(!File.Exists(path))return;
        foreach(string line in File.ReadAllLines(path,Encoding.UTF8)){
            int at=line.IndexOf('\t');if(at<1||at+1>=line.Length)continue;
            string key=line.Substring(0,at),value=line.Substring(at+1).Trim();
            if(key.Length==0||value.Length==0)continue;
            List<string> list;if(!values.TryGetValue(key,out list)){list=new List<string>();values[key]=list;}
            if(!list.Contains(value))list.Add(value);
        }
    }
    public static List<string> Of(int index){
        string[] columns={"AD","AE","AF","AG","AH","AI","AJ","AK","AL","AM","AN","AO","AP"};
        List<string> v;return values.TryGetValue(columns[index],out v)?v:new List<string>();
    }
    public static bool Known(int index,string value){return Of(index).Contains(value);}
}
internal sealed class ReportWindow:Form{
    readonly Customer c; readonly ExcelStore store;readonly int firstScenario;readonly string referencePhone,referenceName,firstPhone;readonly TextBox[] boxes=new TextBox[13];readonly ComboBox[] codes=new ComboBox[13];readonly DateTimePicker[] dates=new DateTimePicker[2]; readonly TextBox amount=new TextBox();readonly ComboBox scenarios=new ComboBox();readonly CheckBox careCheck=new CheckBox();
    static readonly string[] Labels={"(1) AD · Kênh liên lạc","(2) AE · Người được liên lạc","(3) AF · Ngày liên lạc","(4) AG · Mã kết quả (theo CODE đối tác)","(5) AH · Giá trị cam kết trả nợ","(6) AI · Ngày hành động tiếp theo","(7) AJ · Giải pháp thu nợ tiếp theo","(8) AK · Lịch sử thu nợ","(9) AL · Báo cáo kết quả làm việc","(10) AM · Số điện thoại mới","(11) AN · Thông tin mới điều tra","(12) AO · Lý do / Tình trạng tài sản","(13) AP · Phân loại khách hàng"};
    static readonly string[] TH={"TH1 · Tắt máy","TH2 · Không nghe máy","TH3 · Sai số","TH4 · Không có hứa hẹn","TH5 · Người khác / Sai số","TH6 · Có hứa hẹn"};
    public ReportWindow(ExcelStore s,Customer customer,string phone,int firstCallScenario=-1,string refPhone="",string refName=""){
        store=s;c=customer;firstPhone=phone;firstScenario=firstCallScenario;referencePhone=Util.Phone(refPhone);referenceName=refName??"";Text="BÁCH CRM EXCEL  |  GHI BÁO CÁO VÀO EXCEL";Font=new Font("Segoe UI",9);Size=new Size(1000,840);MinimumSize=new Size(870,680);StartPosition=FormStartPosition.CenterScreen;TopMost=true;BackColor=Color.FromArgb(246,248,252);
        var title=new Label{Text=c.Name+"   ·   CIF "+c.Cif+"   ·   HĐ đang gọi "+c.Contract+"   ·   Đồng bộ "+store.CustomerContractCount(c.Cif)+" hợp đồng",Font=new Font("Segoe UI",11,FontStyle.Bold),ForeColor=Color.FromArgb(24,45,78),Dock=DockStyle.Top,Height=43,Padding=new Padding(18,12,0,0)};Controls.Add(title);
        var warning=new Label{Text="Chọn TH1–TH6: AK cộng dồn lịch sử, AL cộng dồn trong ngày (ngày mới thay thế); tất cả hợp đồng cùng CIF nhận báo cáo. Kiểm tra trước khi lưu.",ForeColor=Color.DarkRed,Dock=DockStyle.Top,Height=39,Padding=new Padding(18,6,5,3)};Controls.Add(warning);
        var head=new Panel{Dock=DockStyle.Top,Height=54};Controls.Add(head);var thLabel=new Label{Text="MẪU TÌNH HUỐNG",Left=18,Top=19,Width=145};head.Controls.Add(thLabel);
        scenarios.SetBounds(170,13,360,29);scenarios.DropDownStyle=ComboBoxStyle.DropDownList;scenarios.Items.AddRange(TH);head.Controls.Add(scenarios);
        var topBar=new Label{Text="Tự điền mẫu → xác nhận → cập nhật mọi hợp đồng cùng CIF trên Excel.",Left=548,Top=18,Width=420,Height=25,ForeColor=Color.FromArgb(71,89,119)};head.Controls.Add(topBar);
        var body=new Panel{Dock=DockStyle.Fill,AutoScroll=true};Controls.Add(body);body.BringToFront();
        var bottom=new Panel{Dock=DockStyle.Bottom,Height=94,BackColor=Color.White};Controls.Add(bottom);bottom.BringToFront();
        careCheck.Text="Thêm danh sách care lại (tô vàng toàn bộ dòng Excel của cùng CIF)";
        careCheck.SetBounds(19,6,730,25);careCheck.AutoSize=false;careCheck.Font=new Font("Segoe UI",9,FontStyle.Bold);
        careCheck.ForeColor=Color.FromArgb(80,58,12);careCheck.Checked=false;
        bottom.Controls.Add(careCheck);
        var save=new Button{Text="LƯU BÁO CÁO VÀO EXCEL",Width=245,Height=38,BackColor=Color.FromArgb(14,106,192),ForeColor=Color.White,FlatStyle=FlatStyle.Flat,Top=44,Anchor=AnchorStyles.Right|AnchorStyles.Top};save.Left=Width-285;save.FlatAppearance.BorderSize=0;bottom.Controls.Add(save);
        var close=new Button{Text="HỦY / QUAY LẠI",Width=155,Height=38,Left=18,Top=44};bottom.Controls.Add(close);close.Click+=delegate{Close();};
        var lines=new TableLayoutPanel{Dock=DockStyle.Top,AutoSize=true,Padding=new Padding(16,6,16,16),ColumnCount=2,RowCount=13};lines.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,285));lines.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));body.Controls.Add(lines);
        for(int i=0;i<13;i++){
            var label=new Label{Text=Labels[i],AutoSize=false,Width=280,Height=28,TextAlign=ContentAlignment.MiddleLeft,ForeColor=Color.FromArgb(34,61,94)};lines.Controls.Add(label,0,i);
            Control input;
            if(i==2||i==5){var dt=new DateTimePicker{Format=DateTimePickerFormat.Custom,CustomFormat="dd/MM/yyyy",Width=205,Value=(i==2?DateTime.Today:DateTime.Today.AddDays(1))};dates[i==2?0:1]=dt;input=dt;}
            else if(i==4){amount.Width=240;amount.Text="";input=amount;}
            else if(i==0||i==1||i==3||i==6||i==11||i==12){
                var combo=new ComboBox{Width=600,DropDownStyle=ComboBoxStyle.DropDown,Height=30};
                foreach(string value in PartnerCodes.Of(i))combo.Items.Add(value);
                codes[i]=combo;input=combo;
            }
            else {
                var box=new TextBox{Width=600,Anchor=AnchorStyles.Left|AnchorStyles.Right,Multiline=(i==7||i==8||i==10),Height=(i==7||i==8?70:(i==10?52:27)),ScrollBars=(i==7||i==8||i==10)?ScrollBars.Vertical:ScrollBars.None};
                // AK/AL: insert PC's TODAY (dd/MM/yyyy) immediately when a note is entered.
                if(i==7||i==8){
                    box.TextChanged+=delegate{
                        if((string)box.Tag=="stamping")return;
                        string raw=box.Text.TrimStart();
                        if(raw.Length==0||Regex.IsMatch(raw,@"^\d{2}/\d{2}/\d{4}(?=\s|$)"))return;
                        string prefix=DateTime.Now.ToString("dd/MM/yyyy",CultureInfo.InvariantCulture)+" ";
                        int cursor=box.SelectionStart;
                        box.Tag="stamping";
                        try{box.Text=prefix+raw;box.SelectionStart=Math.Min(box.TextLength,cursor+prefix.Length);}finally{box.Tag=null;}
                    };
                }
                boxes[i]=box;input=box;
            }
            lines.RowStyles.Add(new RowStyle(SizeType.AutoSize));var wrap=new Panel{Height=(i==7||i==8?79:(i==10?58:34)),Dock=DockStyle.Fill};input.Dock=DockStyle.Top;wrap.Controls.Add(input);lines.Controls.Add(wrap,1,i);
        }
        if(referencePhone.Length>0){
            thLabel.Text="KẾT QUẢ GỌI TC";
            warning.Text="ĐÃ GỌI THAM CHIẾU: "+(referenceName.Length>0?referenceName:"Chưa có tên (cột X)")+" · "+referencePhone+
                " | Điền kết quả thật vào dòng CALL tham chiếu; xác nhận AE/AG trước khi lưu.";
            title.Text+="   ·   2 lần gọi";
        }
        scenarios.SelectedIndexChanged+=delegate{ApplyScenario(scenarios.SelectedIndex,phone);};
        if(referencePhone.Length>0){
            // Do not assume the reference call has the same outcome as the customer's first call.
            ApplyScenario(firstScenario>=0?firstScenario:0,phone);
            scenarios.SelectedIndex=-1;
            if(codes[3]!=null)codes[3].Text="";
            if(codes[12]!=null)codes[12].Text="";
        }else scenarios.SelectedIndex=1;
        Shown+=delegate{TopMost=true;BringToFront();Activate();};
        save.Click+=delegate{ Save();};
        Resize+=delegate{save.Left=ClientSize.Width-save.Width-28;};
    }
    void ApplyScenario(int index,string phone){
        if(index<0)return;
        // Match the original Điền Báo Cáo MB text; the UI-only TH label is never written into AK/AL.
        string entry=MbReportTemplates.Note(firstScenario>=0?firstScenario:index,firstPhone);
        if(referencePhone.Length>0){
            entry+="\r\n"+ReportLogic.ReferenceLine(referencePhone);
            // Reference call is a separate human interaction. The operator must record the actual outcome.
            // Neither phone-signalling nor a TH selection can establish who answered it.
        }
        if(boxes[7]!=null)boxes[7].Text=entry;
        if(boxes[8]!=null)boxes[8].Text=entry;
        // Reset AE on EVERY change of scenario. Previously AE inherited the wrong old scenario.
        if(codes[0]!=null)codes[0].Text="Gọi điện thoại di động";
        if(codes[1]!=null)codes[1].Text=referencePhone.Length>0?"":MbReportTemplates.ContactPerson[index];
        if(codes[6]!=null)codes[6].Text="Gọi điện thoại di động";
        if(codes[3]!=null){
            string result=MbReportTemplates.Action[index];
            // Use exactly the counterpart from the real exported Code list when text normalization differs.
            if(index==3){
                string cached=PartnerCodes.Of(3).FirstOrDefault(x=>x.IndexOf("hẹn",StringComparison.OrdinalIgnoreCase)>=0 && x.IndexOf("làm",StringComparison.OrdinalIgnoreCase)>=0);
                if(cached!=null)result=cached;
            }
            codes[3].Text=result;
        }
        if(codes[12]!=null)codes[12].Text=referencePhone.Length>0?"":MbReportTemplates.Classification[index];
        if(index==5)amount.Focus();else amount.Text="";
    }

    static bool ReferenceOutcomeWritten(string note,string phone){
        return ReportLogic.ReferenceHasOutcome(note,phone);
    }
    void Save(){
        ReportData d=new ReportData();for(int i=0;i<13;i++)d.Text[i]=codes[i]!=null?codes[i].Text.Trim():(boxes[i]==null?"":boxes[i].Text.Trim());
        d.Text[2]=dates[0].Value.ToString("dd/MM/yyyy");d.Text[5]=dates[1].Value.ToString("dd/MM/yyyy");d.Text[4]=amount.Text.Trim();
        // Any unstamped note is prefixed with the current PC date on Save (a final safety net).
        DateTime computerNow=DateTime.Now;
        foreach(int col in new[]{7,8}){
            string body=(d.Text[col]??"").Trim();
            if(body.Length==0)continue;
            // Do not repeat the date if the operator typed an explicit dd/MM/yyyy prefix.
            if(!Regex.IsMatch(body,@"^\d{2}/\d{2}/\d{4}(?:\s+\d{2}:\d{2})?(?=\s|$)"))
                d.Text[col]=computerNow.ToString("dd/MM/yyyy",CultureInfo.InvariantCulture)+" "+body;
        }
        if(referencePhone.Length>0 && scenarios.SelectedIndex<0){
            MessageBox.Show(this,"Chọn tình huống TH1–TH6 theo KẾT QUẢ CUỘC GỌI THAM CHIẾU trước khi lưu.");return;
        }
        if(referencePhone.Length>0 && String.IsNullOrWhiteSpace(d.Text[1])){
            MessageBox.Show(this,"Bạn vừa gọi số tham chiếu. Hãy chọn đúng 'Người được liên lạc' ở AE theo kết quả thực tế, không tự suy đoán.");return;
        }
        if(referencePhone.Length>0 && !ReferenceOutcomeWritten(d.Text[8],referencePhone)){
            if(MessageBox.Show(this,"Bạn chưa nhập nội dung sau dòng CALL số tham chiếu. Lưu báo cáo dù kết quả cuộc gọi thứ hai còn trống?",
                "Kiểm tra cuộc gọi tham chiếu",MessageBoxButtons.YesNo,MessageBoxIcon.Warning)!=DialogResult.Yes)return;
        }
        if(String.IsNullOrWhiteSpace(d.Text[3])){
            if(MessageBox.Show(this,"Ô AG chưa có MÃ KẾT QUẢ từ danh mục Code của đối tác. Vẫn lưu nội dung AK/AL và ngày vào Excel (báo cáo còn thiếu mã AG)?","Chưa có mã đối tác",MessageBoxButtons.YesNo,MessageBoxIcon.Warning)!=DialogResult.Yes)return;
        }
        foreach(int col in new[]{0,1,3,6,11,12}){
            if(d.Text[col].Length>0 && PartnerCodes.Of(col).Count>0 && !PartnerCodes.Known(col,d.Text[col])){
                if(MessageBox.Show(this,"Giá trị sau chưa có trong danh mục Code đã khôi phục:\n"+Labels[col]+"\n"+d.Text[col]+"\n\nNếu đối tác đã cập nhật danh mục mới, bạn xác nhận giá trị này hợp lệ rồi chọn Yes để lưu.","Xác minh danh mục",MessageBoxButtons.YesNo,MessageBoxIcon.Warning)!=DialogResult.Yes)return;
            }
        }
        if(d.Text[4].Length>0){decimal m;if(!decimal.TryParse(d.Text[4],NumberStyles.AllowDecimalPoint|NumberStyles.AllowThousands,new CultureInfo("vi-VN"),out m)||m<0){MessageBox.Show(this,"Số tiền cam kết phải là số >= 0, ví dụ 1500000.");return;}}
        try{int count=store.SaveReport(c,d,careCheck.Checked);Tag=count;DialogResult=DialogResult.OK;Close();}
        catch(Exception ex){MessageBox.Show(this,"Không thể lưu báo cáo: "+ex.Message,"Lỗi",MessageBoxButtons.OK,MessageBoxIcon.Error);}
    }
}
// Intentional correction of an existing report. Unlike a new call, editing never
// creates a new AK/AL entry; every amended field is mirrored to this CIF's contracts.
internal sealed class ReviewReportWindow:Form {
    readonly ExcelStore store;readonly Customer customer;readonly string[] original;
    readonly TextBox[] inputs=new TextBox[13];readonly Button save=new Button(),enable=new Button();
    bool editing=false;
    static readonly string[] Names={"AD · Kênh liên lạc","AE · Người được liên lạc","AF · Ngày liên lạc","AG · Mã kết quả","AH · Giá trị cam kết","AI · Ngày hành động tiếp theo","AJ · Giải pháp tiếp theo","AK · Lịch sử thu nợ (toàn bộ)","AL · Báo cáo kết quả trong ngày","AM · SĐT mới","AN · Thông tin mới","AO · Tình trạng tài sản","AP · Phân loại KH"};
    public ReviewReportWindow(ExcelStore s,Customer c){
        store=s;customer=c;original=s.ReadReport(c);
        Text="XEM / SỬA BÁO CÁO · "+c.Name;Size=new Size(940,790);
        MinimumSize=new Size(780,620);StartPosition=FormStartPosition.CenterParent;
        Font=new Font("Segoe UI",9);BackColor=Color.FromArgb(245,248,252);
        var header=new Label{Dock=DockStyle.Top,Height=70,Padding=new Padding(18,10,12,4),
            Text=c.Name+"  ·  CIF "+c.Cif+"  ·  "+s.CustomerContractCount(c.Cif)+" hợp đồng cùng CIF\nChế độ XEM, chỉ khi chọn SỬA mới có thể thay đổi báo cáo cũ."};
        Controls.Add(header);
        var bottom=new Panel{Dock=DockStyle.Bottom,Height=76,BackColor=Color.White};Controls.Add(bottom);
        enable.SetBounds(16,18,195,37);enable.Text="BẬT CHỈNH SỬA";bottom.Controls.Add(enable);
        save.SetBounds(550,18,210,37);save.Text="LƯU SỬA BÁO CÁO";
        save.BackColor=Color.FromArgb(24,103,187);save.ForeColor=Color.White;
        save.Enabled=false;bottom.Controls.Add(save);
        var exit=new Button{Text="ĐÓNG",Left=770,Top=18,Width=125,Height=37};bottom.Controls.Add(exit);
        exit.Click+=delegate{Close();};
        bottom.Resize+=delegate{save.Left=Math.Max(230,bottom.Width-355);exit.Left=bottom.Width-137;};
        var scroll=new Panel{Dock=DockStyle.Fill,AutoScroll=true};Controls.Add(scroll);scroll.BringToFront();
        var rows=new TableLayoutPanel{Dock=DockStyle.Top,AutoSize=true,Padding=new Padding(14,8,14,14),ColumnCount=2,RowCount=13};
        rows.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,255));rows.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
        scroll.Controls.Add(rows);
        for(int i=0;i<13;i++){
            rows.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            var lab=new Label{Text=Names[i],Width=250,Height=30,TextAlign=ContentAlignment.MiddleLeft};rows.Controls.Add(lab,0,i);
            var field=new TextBox{Text=original[i],Multiline=(i==7||i==8||i==10),ReadOnly=true,
                ScrollBars=(i==7||i==8||i==10)?ScrollBars.Vertical:ScrollBars.None,Dock=DockStyle.Top,
                Height=(i==7?125:i==8?85:i==10?56:29)};
            field.BackColor=Color.White;inputs[i]=field;
            var holder=new Panel{Height=field.Height+6,Dock=DockStyle.Fill};holder.Controls.Add(field);rows.Controls.Add(holder,1,i);
        }
        enable.Click+=delegate{
            if(editing)return;
            if(MessageBox.Show(this,"Chỉnh sửa sẽ cập nhật đúng các trường đã thay đổi ở TẤT CẢ hợp đồng cùng CIF.\nBản sao Excel được tạo trước khi ghi.\nBạn đồng ý?",
                "Xác nhận sửa báo cáo cũ",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;
            editing=true;enable.Text="ĐANG CHỈNH SỬA";enable.Enabled=false;save.Enabled=true;
            foreach(var b in inputs)b.ReadOnly=false;
        };
        save.Click+=delegate{
            var current=inputs.Select(x=>x.Text.Trim()).ToArray();
            if(MessageBox.Show(this,"Lưu những trường đã chỉnh sửa cho "+store.CustomerContractCount(customer.Cif)+" hợp đồng cùng CIF?\nĐây là SỬA BÁO CÁO CŨ, không tạo cuộc gọi mới.",
                "Xác nhận lưu",MessageBoxButtons.YesNo,MessageBoxIcon.Warning)!=DialogResult.Yes)return;
            try{int count=store.CorrectReport(customer,original,current);Tag=count;DialogResult=DialogResult.OK;Close();}
            catch(Exception ex){MessageBox.Show(this,"Không thể lưu sửa đổi: "+ex.Message,"Lỗi",MessageBoxButtons.OK,MessageBoxIcon.Error);}
        };
    }
}

internal sealed class CRM:Form {
    ExcelStore store;ExcelRowDock dock;readonly DataGridView grid=new FastDataGridView();readonly TextBox search=new TextBox();readonly Label summary=new Label(),fileLabel=new Label();readonly Timer queueTimer=new Timer(); readonly Dictionary<int,Customer> displayed=new Dictionary<int,Customer>();
    readonly Dictionary<int,string> groupHeaders=new Dictionary<int,string>(); readonly Timer searchTimer=new Timer();
    readonly Dictionary<string,bool> expanded=new Dictionary<string,bool>{{"care",true},{"pending",true},{"done",false}};
    ReferenceSession pendingReference;
    public CRM(){
        Text="BÁCH CRM EXCEL  ·  Sacombank  ·  v1.2";Size=new Size(1370,770);MinimumSize=new Size(1040,650);Font=new Font("Segoe UI",9);BackColor=Color.FromArgb(245,248,252);StartPosition=FormStartPosition.CenterScreen;
        var header=new Panel{Dock=DockStyle.Top,Height=74,BackColor=Color.FromArgb(22,40,69)};Controls.Add(header);
        header.Controls.Add(new Label{Text="BÁCH CRM EXCEL",Left=22,Top=13,ForeColor=Color.White,Font=new Font("Segoe UI",18,FontStyle.Bold),AutoSize=true});
        header.Controls.Add(new Label{Text="Quản lý danh sách · CALL EyeBeam · Báo cáo trực tiếp vào Excel · Độc lập FPT",Left=23,Top=49,ForeColor=Color.FromArgb(188,205,225),AutoSize=true});
        var tools=new Panel{Dock=DockStyle.Top,Height=82,BackColor=Color.White};Controls.Add(tools);
        var choose=MakeButton("CHỌN FILE EXCEL",17,11,155,true);choose.Click+=delegate{ChooseFile();};tools.Controls.Add(choose);
        var reload=MakeButton("TẢI LẠI",183,11,106,false);reload.Click+=delegate{Open(Settings.WorkbookPath);};tools.Controls.Add(reload);
        var openExcel=MakeButton("MỞ FILE EXCEL",301,11,145,false);openExcel.Click+=delegate{if(store!=null)store.ShowExcel();};tools.Controls.Add(openExcel);
        var report=MakeButton("NÚT TRÊN EXCEL",458,11,161,true);report.Click+=delegate{ToggleExcelDock();};tools.Controls.Add(report);
        tools.Controls.Add(new Label{Text="Tìm CIF / HĐ / tên / SĐT",Left=639,Top=17,Width=165,Height=24});search.SetBounds(800,12,300,30);tools.Controls.Add(search);searchTimer.Interval=170;searchTimer.Tick+=delegate{searchTimer.Stop();RefreshRows();};
        search.TextChanged+=delegate{searchTimer.Stop();searchTimer.Start();};
        fileLabel.SetBounds(20,55,1120,20);fileLabel.ForeColor=Color.FromArgb(90,103,125);tools.Controls.Add(fileLabel);
        var foot=new Panel{Dock=DockStyle.Bottom,Height=39,BackColor=Color.FromArgb(229,235,245)};Controls.Add(foot);summary.SetBounds(20,11,1230,22);summary.ForeColor=Color.FromArgb(34,55,90);foot.Controls.Add(summary);
        grid.Dock=DockStyle.Fill;grid.BackgroundColor=Color.White;grid.BorderStyle=BorderStyle.None;grid.AllowUserToAddRows=false;grid.AllowUserToDeleteRows=false;grid.ReadOnly=true;grid.MultiSelect=false;grid.SelectionMode=DataGridViewSelectionMode.FullRowSelect;grid.RowHeadersVisible=false;grid.AllowUserToResizeRows=false;grid.RowTemplate.Height=36;grid.EnableHeadersVisualStyles=false;grid.ColumnHeadersHeight=43;grid.ColumnHeadersDefaultCellStyle.BackColor=Color.FromArgb(224,233,247);grid.ColumnHeadersDefaultCellStyle.ForeColor=Color.FromArgb(24,48,85);grid.ColumnHeadersDefaultCellStyle.Font=new Font("Segoe UI",9,FontStyle.Bold);
        AddCol("cif","MÃ KH (CIF)",100);AddCol("contract","SỐ HĐ",145);AddCol("name","TÊN KH",220);AddCol("debt","TỔNG DƯ NỢ",142);AddCol("days","SNQH",74);AddCol("phone","ĐTDĐ CÁ NHÂN",135);AddCol("area","KHU VỰC",97);AddCol("result","BÁO CÁO",93);
        var action=new DataGridViewButtonColumn{HeaderText="GỌI KHÁCH",Name="act",Text="TÁC ĐỘNG",UseColumnTextForButtonValue=true,Width=135,AutoSizeMode=DataGridViewAutoSizeColumnMode.None};grid.Columns.Add(action);
        Controls.Add(grid);grid.BringToFront();
        grid.CellContentClick+=delegate(object sender,DataGridViewCellEventArgs e){if(e.RowIndex>=0&&e.ColumnIndex==grid.Columns["act"].Index)CallRow(e.RowIndex);};
        grid.CellClick+=delegate(object sender,DataGridViewCellEventArgs e){
            string group;
            if(e.RowIndex>=0&&groupHeaders.TryGetValue(e.RowIndex,out group)){
                expanded[group]=!expanded[group];RefreshRows();
            }
        };
        grid.CellDoubleClick+=delegate(object sender,DataGridViewCellEventArgs e){
            Customer selected=e.RowIndex>=0?GetCustomer(e.RowIndex):null;
            if(selected==null||e.ColumnIndex<0||e.ColumnIndex==grid.Columns["act"].Index)return;
            if(CareLogic.NeedsCare(selected)&&store.Customers.Any(x=>x.Cif==selected.Cif&&x.Reported))ReviewReport(selected);
            else OpenReport(selected,"");
        };
        queueTimer.Interval=650;queueTimer.Tick+=delegate{PollReports();};queueTimer.Start();Shown+=delegate{if(File.Exists(Settings.WorkbookPath))BeginInvoke(new Action(()=>Open(Settings.WorkbookPath)));else fileLabel.Text="Chọn file Sacombank Excel để bắt đầu. App không tự nhập hồ sơ vào FPT.";};
    }
    Button MakeButton(string t,int left,int top,int width,bool primary){var b=new Button{Text=t,Left=left,Top=top,Width=width,Height=33,FlatStyle=FlatStyle.Flat,BackColor=primary?Color.FromArgb(28,102,183):Color.FromArgb(235,241,249),ForeColor=primary?Color.White:Color.FromArgb(30,55,86)};b.FlatAppearance.BorderSize=0;return b;}
    void AddCol(string name,string title,int width){grid.Columns.Add(new DataGridViewTextBoxColumn{Name=name,HeaderText=title,Width=width,SortMode=DataGridViewColumnSortMode.NotSortable});}
    void ChooseFile(){using(var d=new OpenFileDialog{Filter="Excel (*.xlsx)|*.xlsx",Title="Chọn file Excel Sacombank"})if(d.ShowDialog(this)==DialogResult.OK)Open(d.FileName);}
    void Open(string path){if(!File.Exists(path))return;
        if(pendingReference!=null && store!=null && !String.Equals(System.IO.Path.GetFullPath(path),store.PathName,StringComparison.OrdinalIgnoreCase)){
            MessageBox.Show(this,"Chưa kết thúc cuộc gọi tham chiếu cho CIF "+pendingReference.Cif+". Không thể đổi sang workbook khác để tránh ghi nhầm khách.");return;
        }
        try{ExcelStore next=ExcelComBusyFilter.RetryRead(()=>new ExcelStore(path));if(dock!=null&&!dock.IsDisposed){dock.Close();dock=null;} if(store!=null)store.Dispose();store=next;Settings.WorkbookPath=path;fileLabel.Text="FILE ĐANG DÙNG: "+path+(store.ReadOnly?"     [CHỈ ĐỌC]":"");RefreshRows();}
        catch(Exception e){MessageBox.Show(this,"Không mở được file Excel: "+e.Message+"\n\nNếu Excel đang bận: bấm Esc để đóng danh sách/thoát chỉnh sửa ô, chờ vài giây rồi TẢI LẠI. CRM đã tự thử lại các lỗi COM tạm thời.");}
    }
    GridPosition CaptureGridPosition(){
        var p=new GridPosition();
        if(grid.Rows.Count==0)return p;
        try{
            p.SelectedIndex=grid.CurrentCell==null?-1:grid.CurrentCell.RowIndex;
            p.ColumnIndex=grid.CurrentCell==null?0:grid.CurrentCell.ColumnIndex;
            Customer selected=GetCustomer(p.SelectedIndex);
            if(selected!=null)p.SelectedExcelRow=selected.Row;
            p.TopIndex=grid.FirstDisplayedScrollingRowIndex;
            Customer top=GetCustomer(p.TopIndex);
            if(top!=null)p.TopExcelRow=top.Row;
            p.HorizontalOffset=grid.HorizontalScrollingOffset;
        }catch(InvalidOperationException){}catch(ArgumentOutOfRangeException){}
        return p;
    }
    void RestoreGridPosition(GridPosition p){
        if(p==null||grid.Rows.Count==0)return;
        int selected=GridStateLogic.FindIndex(displayed,p.SelectedExcelRow,p.SelectedIndex);
        int top=GridStateLogic.FindIndex(displayed,p.TopExcelRow,p.TopIndex);
        try{
            grid.ClearSelection();
            if(selected>=0 && selected<grid.Rows.Count){
                int column=Math.Max(0,Math.Min(p.ColumnIndex,grid.Columns.Count-1));
                grid.CurrentCell=grid.Rows[selected].Cells[column];
                grid.Rows[selected].Selected=true;
            }
            // CurrentCell can scroll automatically: restore the viewport AFTER restoring selection.
            if(top>=0 && top<grid.Rows.Count)grid.FirstDisplayedScrollingRowIndex=top;
            if(p.HorizontalOffset>=0)grid.HorizontalScrollingOffset=p.HorizontalOffset;
        }catch(InvalidOperationException){}catch(ArgumentOutOfRangeException){}
    }
    void RefreshRows(GridPosition bookmark=null){
        if(bookmark==null)bookmark=CaptureGridPosition();
        grid.SuspendLayout();
        try{
            grid.Rows.Clear();displayed.Clear();groupHeaders.Clear();
            if(store==null){summary.Text="Chưa chọn Excel";return;}
            string term=search.Text.Trim();
            List<Customer> filtered=store.Customers.Where(c=>term.Length==0 ||
                (c.Cif+" "+c.Contract+" "+c.Name+" "+c.Phone+" "+c.Reference+" "+c.ReferenceName).IndexOf(term,StringComparison.OrdinalIgnoreCase)>=0).ToList();
            HashSet<string> careCifs=new HashSet<string>(CareLogic.UniqueCare(store.Customers).Select(x=>x.Cif),StringComparer.OrdinalIgnoreCase);
            var careGroups=filtered.Where(x=>careCifs.Contains(x.Cif)).GroupBy(x=>x.Cif,StringComparer.OrdinalIgnoreCase);
            var care=CareSortLogic.Sort(careGroups,DateTime.Today)
                .Select(g=>g.OrderByDescending(x=>x.YellowRow).ThenBy(x=>x.Row).First()).ToList();
            var remaining=filtered.Where(x=>!careCifs.Contains(x.Cif)).ToList();
            var pending=remaining.Where(x=>!x.Reported).ToList();
            var done=remaining.Where(x=>x.Reported).ToList();
            AddGroupHeader("care","CẦN PHẢI CARE  ·  "+care.Count+" KH",Color.FromArgb(240,229,170));
            if(expanded["care"])foreach(Customer c in care){
                List<Customer> all=store.Customers.Where(x=>ReportLogic.SameCif(x.Cif,c.Cif)).ToList();
                DateTime? appointment=CareSortLogic.Earliest(all);
                string dateNote=appointment.HasValue?" · Hẹn "+appointment.Value.ToString("dd/MM"):"";
                AddCustomerRow(c,(all.Count>1?c.Name+"  ("+all.Count+" HĐ)":c.Name)+dateNote,
                    all.Sum(x=>x.Debt),all.Max(x=>x.Overdue),all.Any(x=>x.Reported),true,appointment);
            }
            AddGroupHeader("pending","CHƯA BÁO CÁO  ·  "+pending.Count+" HĐ",Color.FromArgb(221,232,249));
            if(expanded["pending"])foreach(Customer c in pending)AddCustomerRow(c,c.Name,c.Debt,c.Overdue,false,false);
            AddGroupHeader("done","ĐÃ BÁO CÁO  ·  "+done.Count+" HĐ",Color.FromArgb(208,239,219));
            if(expanded["done"])foreach(Customer c in done)AddCustomerRow(c,c.Name,c.Debt,c.Overdue,true,false);
            summary.Text="TỔNG HỢP ĐỒNG: "+store.Customers.Count+"     ·     SỐ CIF: "+store.Customers.Select(x=>x.Cif).Distinct().Count()+
                "     ·     CẦN CARE: "+careCifs.Count+" CIF     ·     ĐÃ CÓ BÁO CÁO: "+store.Customers.Count(x=>x.Reported)+" HĐ     | AD:AP";
        }finally{grid.ResumeLayout(false);}
        RestoreGridPosition(bookmark);
    }
    void AddGroupHeader(string key,string label,Color background){
        int row=grid.Rows.Add("","",(expanded[key]?"⊟  ":"⊞  ")+label,"","","","","","");
        groupHeaders[row]=key;
        DataGridViewRow group=grid.Rows[row];
        group.DefaultCellStyle.BackColor=background;
        group.DefaultCellStyle.ForeColor=Color.FromArgb(22,56,81);
        group.DefaultCellStyle.Font=new Font("Segoe UI",9,FontStyle.Bold);
        group.Height=33;
        group.Cells["act"]=new DataGridViewTextBoxCell{Value="BẤM +/-"};
    }
    void AddCustomerRow(Customer c,string label,decimal debt,int overdue,bool reported,bool care,DateTime? appointment=null){
        int row=grid.Rows.Add(c.Cif,c.Contract,label,Util.N(debt),overdue,
            Util.Phone(c.Phone).Length>0?Util.Phone(c.Phone):"(thiếu)",c.Area,reported?"Đã ghi":"Chưa ghi");
        displayed[row]=c;
        if(reported)grid.Rows[row].DefaultCellStyle.BackColor=Color.FromArgb(220,247,230);
        else if(care)grid.Rows[row].DefaultCellStyle.BackColor=Color.FromArgb(255,250,225);
        else if(row%2==0)grid.Rows[row].DefaultCellStyle.BackColor=Color.FromArgb(251,253,255);
        if(care && CareSortLogic.Urgent(appointment,DateTime.Today)){
            grid.Rows[row].DefaultCellStyle.BackColor=Color.FromArgb(255,219,219);
            grid.Rows[row].DefaultCellStyle.ForeColor=Color.FromArgb(155,20,30);
        }
        if(Util.Phone(c.Phone).Length==0)grid.Rows[row].Cells["phone"].Style.ForeColor=Color.DarkRed;
        if(care&&reported){grid.Rows[row].Cells["result"].Value="Xem / sửa";}
    }
    Customer GetCustomer(int row){Customer c;return displayed.TryGetValue(row,out c)?c:null;}
    Customer Selected(){return grid.CurrentRow==null?null:GetCustomer(grid.CurrentRow.Index);}
    void ReportSelected(string phone){Customer c=Selected();if(c==null)return;OpenReport(c,phone);}
    void OpenReport(Customer c,string phone,ReferenceSession reference=null){
        if(c==null||store==null)return;
        GridPosition bookmark=CaptureGridPosition();
        try{
            store.Exact(c.Row,c.Cif,c.Contract);
            using(var f=new ReportWindow(store,c,phone,reference==null?-1:reference.FirstScenario,
                reference==null?"":reference.RefPhone,reference==null?"":reference.RefName)){
                if(f.ShowDialog(this)==DialogResult.OK){
                    RefreshRows(bookmark);
                    fileLabel.Text="ĐÃ LƯU BÁO CÁO · CIF "+c.Cif+" · "+(f.Tag??store.CustomerContractCount(c.Cif))+" HĐ · "+DateTime.Now.ToString("HH:mm:ss")+
                        (store.Customers.Any(x=>x.Cif==c.Cif&&CareLogic.NeedsCare(x))?" · Theo dõi Care":"");
                }
            }
        }catch(Exception e){MessageBox.Show(this,e.Message);}
    }
    public void CallCustomer(Customer c){
        if(pendingReference!=null){MessageBox.Show(this,"Đang chờ hoàn thành cuộc gọi tham chiếu cho CIF "+pendingReference.Cif+". Hãy hoàn tất hoặc hủy quy trình hiện tại.");return;}
        if(c==null||store==null)return;try{store.Exact(c.Row,c.Cif,c.Contract);}catch(Exception e){MessageBox.Show(this,e.Message);return;}

        var phones=new List<KeyValuePair<string,string>>();foreach(var v in new[]{new KeyValuePair<string,string>("SĐT cá nhân (D/S)",c.Phone),new KeyValuePair<string,string>("SĐT tham chiếu (Y)",c.Reference),new KeyValuePair<string,string>("SĐT mới (AM)",c.NewPhone)}){
            string p=Util.Phone(v.Value);if(p.Length>0&&!phones.Any(x=>x.Value==p))phones.Add(new KeyValuePair<string,string>(v.Key,p));}
        if(phones.Count==0){MessageBox.Show(this,"Dòng này chưa có SĐT hợp lệ. Hãy kiểm tra cột D/S, Y hoặc AM.");return;}
        string selected="";bool selectedReference=false;
        using(var d=new Form{Text="CHỌN SỐ GỌI · "+c.Name,Size=new Size(485,270),StartPosition=FormStartPosition.CenterParent,Font=Font,FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,MinimizeBox=false}){
            d.Controls.Add(new Label{Left=17,Top=13,Width=440,Height=30,Text="CIF "+c.Cif+" · HĐ "+c.Contract+" — chọn số để đưa vào EyeBeam:"});
            var combo=new ComboBox{Left=17,Top=49,Width=440,DropDownStyle=ComboBoxStyle.DropDownList};foreach(var p in phones)combo.Items.Add(p.Key+"   ·   "+p.Value);combo.SelectedIndex=0;d.Controls.Add(combo);
            d.Controls.Add(new Label{Text="CRM chỉ điền số. Bạn phải tự bấm Enter trên EyeBeam để gọi.",Left=17,Top=91,Width=440,Height=42,ForeColor=Color.FromArgb(85,106,139)});
            var ok=MakeButton("MỞ EYEBEAM",160,150,160,true);d.Controls.Add(ok);ok.Click+=delegate{selected=phones[combo.SelectedIndex].Value;selectedReference=phones[combo.SelectedIndex].Key.StartsWith("SĐT tham chiếu",StringComparison.OrdinalIgnoreCase);d.DialogResult=DialogResult.OK;d.Close();};
            if(d.ShowDialog(this)!=DialogResult.OK)return;
        }
        StartBridge(c,selected,selectedReference);
    }
    bool StartBridge(Customer c,string phone,bool isReference){
        string exe=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"BachCRMExcelBridge.exe");
        if(!File.Exists(exe)){MessageBox.Show(this,"Thiếu BachCRMExcelBridge.exe — chạy BUILD_AND_START.cmd.");return false;}
        if(Util.Phone(phone).Length==0){MessageBox.Show(this,"SĐT không hợp lệ. Không thể chuyển sang EyeBeam.");return false;}
        try{System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo{FileName=exe,UseShellExecute=false,
            WorkingDirectory=AppDomain.CurrentDomain.BaseDirectory,
            Arguments="--phone "+Util.Quote(phone)+" --cif "+Util.Quote(c.Cif)+" --contract "+Util.Quote(c.Contract)+
                " --customer-name "+Util.Quote(c.Name)+" --reference-name "+Util.Quote(c.ReferenceName)+
                " --call-type "+Util.Quote(isReference?"reference":"customer")});return true;}
        catch(Exception e){MessageBox.Show(this,"Không mở được Bridge: "+e.Message);return false;}
    }
    void CallRow(int idx){CallCustomer(GetCustomer(idx));}
    void ToggleExcelDock(){
        if(store==null){MessageBox.Show(this,"Chọn file Sacombank đã sửa trước khi bật nút TÁC ĐỘNG trên Excel.");return;}
        if(dock!=null && !dock.IsDisposed){dock.Close();dock=null;return;}
        store.ShowExcel();dock=new ExcelRowDock(this,store);dock.FormClosed+=delegate{dock=null;};dock.Show();
    }
    public void ReportCurrentExcel(Customer c){OpenReport(c,"");}
    void ReviewReport(Customer c){
        if(c==null||store==null||!CareLogic.NeedsCare(c))return;
        c=store.Customers.FirstOrDefault(x=>x.Cif==c.Cif&&x.Reported)??c;
        GridPosition bookmark=CaptureGridPosition();
        try{using(var window=new ReviewReportWindow(store,c)){
            if(window.ShowDialog(this)==DialogResult.OK)RefreshRows(bookmark);
        }}catch(Exception ex){MessageBox.Show(this,"Không xem được báo cáo: "+ex.Message);}
    }
    void PollReports(){
        if(store==null)return;string[] files;
        try{files=Directory.GetFiles(Settings.RequestDir,"*.req");}catch{return;}
        foreach(string f in files.Take(3)){
            try{string[] payload=Settings.ReadQueue(f);File.Delete(f);if(payload.Length<4)continue;
                string cif=payload[0],contract=payload[1],phone=payload[2];long ticks;
                if(!long.TryParse(payload[3],out ticks)||Math.Abs((DateTime.UtcNow-new DateTime(ticks,DateTimeKind.Utc)).TotalMinutes)>120)continue;
                var hits=store.Customers.Where(x=>x.Cif==cif&&x.Contract==contract).ToList();if(hits.Count!=1){MessageBox.Show(this,"Cuộc gọi hoàn tất nhưng không tìm đúng CIF/HĐ trong Excel. Không mở báo cáo nhầm khách.");continue;}
                WindowState=FormWindowState.Normal;
                Show();BringToFront();Activate();
                Customer current=hits[0];
                if(pendingReference!=null){
                    if(pendingReference.Matches(cif,contract,phone)){
                        ReferenceSession finished=pendingReference;pendingReference=null;
                        OpenReport(current,finished.FirstPhone,finished);
                    }else{
                        MessageBox.Show(this,"Đang chờ cuộc gọi tham chiếu cho CIF "+pendingReference.Cif+". Sự kiện gác máy không khớp số tham chiếu, không ghi nhầm báo cáo.");
                    }
                    continue;
                }
                string refPhone=Util.Phone(current.Reference);
                if(Util.Phone(phone)==Util.Phone(current.Phone) && refPhone.Length>0 && refPhone!=Util.Phone(phone)){
                    ShowAfterFirstCall(current,phone,refPhone);continue;
                }
                OpenReport(current,phone);
            }catch(Exception e){try{File.Move(f,f+".failed");}catch{}MessageBox.Show(this,"Lỗi nhận sự kiện kết thúc cuộc gọi: "+e.Message);}
        }
    }
    void ShowAfterFirstCall(Customer customer,string firstPhone,string refPhone){
        int outcome=-1;bool callReference=false;
        using(var f=new Form{Text="KẾT THÚC CUỘC GỌI 1 · "+customer.Name,
            Font=Font,StartPosition=FormStartPosition.CenterParent,Size=new Size(550,300),
            MinimizeBox=false,MaximizeBox=false,FormBorderStyle=FormBorderStyle.FixedDialog,TopMost=true}){
            f.Controls.Add(new Label{Left=18,Top=18,Width=500,Height=48,
                Text="Cuộc gọi KH: "+firstPhone+"\nEyeBeam không tự xác định lý do mất liên lạc. Bạn hãy chọn kết quả thực tế."});
            var choose=new ComboBox{Left=18,Top=80,Width=495,DropDownStyle=ComboBoxStyle.DropDownList};
            choose.Items.AddRange(new object[]{"TH1 · Tắt máy / mất liên lạc","TH2 · Không nghe máy","TH3 · Sai số","TH5 · Người khác / sai số"});
            f.Controls.Add(choose);
            f.Controls.Add(new Label{Left=18,Top=119,Width=510,Height=39,
                Text="Người tham chiếu (cột X): "+(customer.ReferenceName.Length>0?customer.ReferenceName:"(chưa có tên)")+"\nSĐT tham chiếu (Y): "+refPhone});
            var next=new Button{Left=18,Top=185,Width=248,Height=42,Text="GỌI THAM CHIẾU →",BackColor=Color.FromArgb(20,106,195),ForeColor=Color.White};
            var report=new Button{Left=281,Top=185,Width=232,Height=42,Text="BÁO CÁO NGAY"};
            f.Controls.Add(next);f.Controls.Add(report);
            next.Click+=delegate{
                int[] scenarios={0,1,2,4};
                if(choose.SelectedIndex<0){MessageBox.Show(f,"Bạn hãy chọn đúng kết quả cuộc gọi thứ nhất trước khi gọi tham chiếu.");return;}
                outcome=scenarios[choose.SelectedIndex];callReference=true;f.DialogResult=DialogResult.OK;
            };
            report.Click+=delegate{f.DialogResult=DialogResult.OK;};
            f.ShowDialog(this);
        }
        if(callReference){
            var session=new ReferenceSession{Cif=customer.Cif,Contract=customer.Contract,FirstPhone=firstPhone,
                RefPhone=refPhone,RefName=customer.ReferenceName,FirstScenario=outcome};
            pendingReference=session;
            if(!StartBridge(customer,refPhone,true)){
                pendingReference=null;
                MessageBox.Show(this,"Chưa mở được cuộc gọi tham chiếu. Hãy mở báo cáo thủ công khi cần, không ghi nhầm.");
            }
        }else{
            OpenReport(customer,firstPhone);
        }
    }
    protected override void OnFormClosed(FormClosedEventArgs e){queueTimer.Stop();searchTimer.Stop();if(dock!=null&&!dock.IsDisposed)dock.Close();if(store!=null)store.Dispose();base.OnFormClosed(e);}
}
// Floating one-click button next to Excel's left gutter, following the currently selected row.
// No VBA, macros, workbook column insertion or permanent workbook modifications.
internal sealed class ExcelRowDock:Form {
    readonly CRM crm;readonly ExcelStore store;readonly System.Windows.Forms.Timer clock=new System.Windows.Forms.Timer();
    readonly Label title=new Label();readonly Button call=new Button(),report=new Button();
    Customer selected;
    public ExcelRowDock(CRM c,ExcelStore s){
        crm=c;store=s;Text="Bách CRM Excel · Nút tác động";
        Font=new Font("Segoe UI",9);Size=new Size(268,115);MaximumSize=Size;MinimumSize=Size;
        TopMost=true;ShowInTaskbar=false;FormBorderStyle=FormBorderStyle.FixedToolWindow;
        BackColor=Color.FromArgb(237,244,253);StartPosition=FormStartPosition.Manual;
        title.SetBounds(9,8,245,29);title.Text="Chọn dòng KH trong Excel";title.ForeColor=Color.FromArgb(28,58,97);title.Font=new Font("Segoe UI",9,FontStyle.Bold);Controls.Add(title);
        call.SetBounds(9,40,140,34);call.Text="☎ TÁC ĐỘNG";call.BackColor=Color.FromArgb(24,108,193);call.ForeColor=Color.White;call.FlatStyle=FlatStyle.Flat;call.FlatAppearance.BorderSize=0;call.Enabled=false;Controls.Add(call);
        report.SetBounds(157,40,96,34);report.Text="BÁO CÁO";report.Enabled=false;Controls.Add(report);
        call.Click+=delegate{Customer target=selected;if(target!=null)crm.CallCustomer(target);};
        report.Click+=delegate{Customer target=selected;if(target!=null)crm.ReportCurrentExcel(target);};
        clock.Interval=450;clock.Tick+=delegate{RefreshSelected();};
        Shown+=delegate{
            System.Drawing.Rectangle bounds;
            Location=store.TryExcelBounds(out bounds)?new Point(Math.Max(0,bounds.Left+4),Math.Max(0,bounds.Top+185)):new Point(40,250);
            clock.Start();RefreshSelected();
        };
        FormClosed+=delegate{clock.Stop();clock.Dispose();};
    }
    void RefreshSelected(){
        Customer now=store.SelectedExcelCustomer();selected=now;
        if(now!=null){
            title.Text="DÒNG "+now.Row+"  ·  "+(now.Name.Length>22?now.Name.Substring(0,22):now.Name);
            call.Enabled=true;report.Enabled=true;
        }else{
            title.Text="Chọn dòng từ hàng 6 trên Sheet1";
            call.Enabled=false;report.Enabled=false;
        }
    }
}
internal static class Program {
    [STAThread]static void Main(string[] args){
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        try{
            ExcelComBusyFilter.Install();
            Application.Run(new CRM());
        }finally{ExcelComBusyFilter.Remove();}
    }
}