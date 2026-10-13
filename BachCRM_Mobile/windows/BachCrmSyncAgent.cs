using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;

// Separate read-only agent. NEVER edits BachCRM.exe, FPT, CALL Bridge or DPAPI files.
// It only reads selected CRM customers when user explicitly enables --watch.
internal static class BachCrmSyncAgent {
    static readonly string Folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BachCRM");
    static readonly string DataPath = Path.Combine(Folder, "customers.dpapi");
    static readonly string SettingsPath = Path.Combine(Folder, "ios_sync_settings.dpapi");
    static string previousRevision = "";

    sealed class Config { public string endpoint; public string token; }
    sealed class Snapshot { public string source_id="windows-primary"; public string revision; public List<Customer> customers; }
    sealed class Customer {
        public string cif, contract, name, phone, appointment_date;
        public long? debt_vnd, expected_vnd;
        public int? overdue_days;
    }

    static void Main(string[] args) {
        Console.OutputEncoding = Encoding.UTF8;
        if (args.Length == 1 && args[0] == "--configure") { Configure(); return; }
        if (args.Length != 1 || (args[0] != "--once" && args[0] != "--watch")) {
            Console.WriteLine("Usage: BachCrmSyncAgent.exe --configure | --once | --watch"); return;
        }
        Config cfg = LoadConfig();
        if (cfg == null) { Console.WriteLine("Configure first: BachCrmSyncAgent.exe --configure"); return; }
        if (!cfg.endpoint.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) {
            Console.WriteLine("Refusing insecure endpoint; HTTPS required."); return;
        }
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        Console.WriteLine("BachCRM Sync Agent: read-only on PC; never modifies CRM data.");
        Console.WriteLine("Press Ctrl+C to stop. No customer information is logged.");
        do {
            try { UploadIfChanged(cfg); }
            catch(Exception ex) { Console.WriteLine(DateTime.Now.ToString("HH:mm:ss") + " Sync: " + ex.GetType().Name); }
            if (args[0] == "--once") break;
            Thread.Sleep(5000);
        } while(true);
    }

    static string GetHidden() {
        var b = new StringBuilder();
        ConsoleKeyInfo key;
        while ((key = Console.ReadKey(true)).Key != ConsoleKey.Enter) {
            if (key.Key == ConsoleKey.Backspace) { if (b.Length>0) b.Length--; }
            else if(!Char.IsControl(key.KeyChar)) b.Append(key.KeyChar);
        }
        Console.WriteLine(); return b.ToString();
    }
    static void Configure() {
        Console.Write("Authorized HTTPS server URL (e.g. https://crm.example.vn): ");
        string url = (Console.ReadLine() ?? "").Trim().TrimEnd('/');
        Uri uri;
        if (!Uri.TryCreate(url, UriKind.Absolute, out uri) || uri.Scheme != "https") {
            Console.WriteLine("HTTPS required. Nothing saved."); return;
        }
        Console.Write("PC WRITE token (hidden): ");
        string token = GetHidden();
        if(token.Length < 24) { Console.WriteLine("Token must be at least 24 characters."); return; }
        var serializer = new JavaScriptSerializer();
        byte[] clear = Encoding.UTF8.GetBytes(serializer.Serialize(new Config{endpoint=url,token=token}));
        byte[] encrypted = ProtectedData.Protect(clear,null,DataProtectionScope.CurrentUser);
        Directory.CreateDirectory(Folder);
        File.WriteAllBytes(SettingsPath,encrypted);
        Console.WriteLine("Sync settings saved encrypted for THIS Windows user only.");
    }
    static Config LoadConfig() {
        try {
            if(!File.Exists(SettingsPath))return null;
            byte[] raw = ProtectedData.Unprotect(File.ReadAllBytes(SettingsPath), null, DataProtectionScope.CurrentUser);
            return new JavaScriptSerializer().Deserialize<Config>(Encoding.UTF8.GetString(raw));
        } catch { return null; }
    }
    static string Value(DataRow row, string key) {
        return row.Table.Columns.Contains(key)?Convert.ToString(row[key],CultureInfo.InvariantCulture).Trim():"";
    }
    static string Phone(string raw) {
        string s = Regex.Replace(raw ?? "", @"[\s.()\-]", "");
        if(s.StartsWith("+84") && s.Length==12) s="0"+s.Substring(3);
        else if(s.StartsWith("84") && s.Length==11) s="0"+s.Substring(2);
        else if(Regex.IsMatch(s,@"^[35789][0-9]{8}$")) s="0"+s;
        return Regex.IsMatch(s,@"^0[0-9]{9}$")?s:"";
    }
    static long? Money(string s) {
        s = Regex.Replace(s??"", @"[\s,.]", "");
        long n; return long.TryParse(s,NumberStyles.None,CultureInfo.InvariantCulture,out n)&&n>=0?(long?)n:null;
    }
    static int? Days(string s) {
        s = Regex.Replace(s??"", @"[\s,.]", "");
        int n; return int.TryParse(s,NumberStyles.None,CultureInfo.InvariantCulture,out n)&&n>=0?(int?)n:null;
    }
    static string Date(string s) {
        if (String.IsNullOrWhiteSpace(s)) return null;
        DateTime date;
        if (DateTime.TryParseExact(s, new[]{"yyyy-MM-dd", "dd/MM/yyyy"}, CultureInfo.InvariantCulture,DateTimeStyles.None,out date))
            return date.ToString("yyyy-MM-dd");
        return null;
    }
    static void UploadIfChanged(Config cfg) {
        if (!File.Exists(DataPath)) { Console.WriteLine("CRM dataset not found; skipping."); return; }
        byte[] encrypted = File.ReadAllBytes(DataPath);
        byte[] clear = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser);
        var table = new DataTable("Customers");
        using(var ms = new MemoryStream(clear)) table.ReadXml(ms);
        if(table.Rows.Count==0) { Console.WriteLine("Empty CRM table; refusing automatic deletion of remote snapshot."); return; }
        var customers = new List<Customer>();
        var seen = new HashSet<string>();
        foreach(DataRow row in table.Rows) {
            string cif=Value(row,"CIF"), contract=Value(row,"HopDong");
            if(cif.Length==0||contract.Length==0)continue;
            string key=cif+"|"+contract;
            if(!seen.Add(key))throw new InvalidDataException("Duplicate customer/contract, refusing sync");
            customers.Add(new Customer{
                cif=cif,contract=contract,name=Value(row,"HoTen"),
                phone=Phone(Value(row,"SoDienThoai")),
                debt_vnd=Money(Value(row,"TongNo")),
                overdue_days=Days(Value(row,"SoNgayQuaHan")),
                appointment_date=Date(Value(row,"NgayHen")),
                expected_vnd=Money(Value(row,"SoTienDuKien"))
            });
        }
        customers.Sort(delegate(Customer a,Customer b){return String.CompareOrdinal(a.cif+"|"+a.contract,b.cif+"|"+b.contract);});
        if(customers.Count==0)throw new InvalidDataException("No valid records found, refusing remote deletion");
        var serializer = new JavaScriptSerializer(); serializer.MaxJsonLength=20*1024*1024;
        string payload = serializer.Serialize(customers);
        string revision;
        using(var sha=SHA256.Create()){
            byte[] hash=sha.ComputeHash(Encoding.UTF8.GetBytes(payload));
            revision=BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
        }
        if(revision==previousRevision)return;
        var snapshot=new Snapshot{revision=revision,customers=customers};
        byte[] body=Encoding.UTF8.GetBytes(serializer.Serialize(snapshot));
        var req=(HttpWebRequest)WebRequest.Create(cfg.endpoint.TrimEnd('/')+"/v1/snapshot");
        req.Method="PUT";req.ContentType="application/json; charset=utf-8";
        req.Headers["Authorization"]="Bearer "+cfg.token;
        req.Timeout=12000;req.ReadWriteTimeout=12000;req.ContentLength=body.Length;
        using(Stream output=req.GetRequestStream())output.Write(body,0,body.Length);
        using(var response=(HttpWebResponse)req.GetResponse()){
            if((int)response.StatusCode<200||(int)response.StatusCode>=300)throw new WebException("Sync rejected");
        }
        previousRevision=revision;
        Console.WriteLine(DateTime.Now.ToString("HH:mm:ss")+" Published "+customers.Count+" care records. Do not close agent to keep syncing.");
    }
}