using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Xml;

// Fast, read-only XLSX snapshot reader. No COM or Excel automation on the UI startup path.
// Workbook changes not yet saved by the operator in Excel are intentionally NOT included.
internal static class FastXlsxReader {
    const string MainNs="http://schemas.openxmlformats.org/spreadsheetml/2006/main";
    static XmlDocument ReadXml(ZipArchive z,string path){
        var entry=z.GetEntry(path.TrimStart('/'));
        if(entry==null)throw new InvalidDataException("Thiếu thành phần Excel: "+path);
        var x=new XmlDocument{XmlResolver=null};using(var stream=entry.Open())x.Load(stream);return x;
    }
    static XmlNamespaceManager Ns(XmlDocument x){var m=new XmlNamespaceManager(x.NameTable);m.AddNamespace("x",MainNs);m.AddNamespace("r","http://schemas.openxmlformats.org/officeDocument/2006/relationships");return m;}
    static int Column(string reference){int value=0;foreach(char c in reference??""){if(c>='A'&&c<='Z')value=value*26+(c-'A'+1);else if(c>='a'&&c<='z')value=value*26+(c-'a'+1);else break;}return value;}
    static string SharedOrRaw(XmlNode cell, XmlNamespaceManager ns, IList<string> shared){
        var v=cell.SelectSingleNode("x:v",ns);var inline=cell.SelectSingleNode("x:is",ns);
        string value=v==null?(inline==null?"":inline.InnerText):v.InnerText;
        var type=cell.Attributes==null?null:cell.Attributes["t"];
        if(type!=null&&type.Value=="s"){
            int at;return int.TryParse(value,out at)&&at>=0&&at<shared.Count?shared[at]:"";
        }
        return value;
    }
    static DateTime? ParseDate(string text){
        if(String.IsNullOrWhiteSpace(text))return null;
        DateTime date;
        if(DateTime.TryParseExact(text,new[]{"dd/MM/yyyy","d/M/yyyy","yyyy-MM-dd","yyyy/MM/dd"},CultureInfo.InvariantCulture,DateTimeStyles.None,out date))return date.Date;
        double oa;
        if(double.TryParse(text,NumberStyles.Any,CultureInfo.InvariantCulture,out oa)&&oa>30000&&oa<100000){
            try{return DateTime.FromOADate(oa).Date;}catch{}
        }
        return null;
    }
    static bool IsYellowFill(XmlNode fill,XmlNamespaceManager n){
        if(fill==null)return false;
        var fg=fill.SelectSingleNode("x:patternFill/x:fgColor",n);
        if(fg==null)return false;
        var rgb=fg.Attributes["rgb"];
        if(rgb!=null&&rgb.Value.Length>=6){
            string hex=rgb.Value;hex=hex.Substring(hex.Length-6);
            int red,green,blue;
            if(int.TryParse(hex.Substring(0,2),NumberStyles.HexNumber,CultureInfo.InvariantCulture,out red)&&
              int.TryParse(hex.Substring(2,2),NumberStyles.HexNumber,CultureInfo.InvariantCulture,out green)&&
              int.TryParse(hex.Substring(4,2),NumberStyles.HexNumber,CultureInfo.InvariantCulture,out blue))
                return red>=195&&green>=180&&((blue<=125&&green-blue>=55)||(green>=225&&green-blue>=25));
        }
        var indexed=fg.Attributes["indexed"];int index;
        return indexed!=null&&int.TryParse(indexed.Value,out index)&&(index==5||index==6);
    }
    public static List<Customer> Load(string filename){
        if(!File.Exists(filename))throw new FileNotFoundException("Không tìm thấy file Excel",filename);
        var result=new List<Customer>();
        using(var stream=new FileStream(filename,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
        using(var z=new ZipArchive(stream,ZipArchiveMode.Read,false)){
            var w=ReadXml(z,"xl/workbook.xml");var wn=Ns(w);
            var s=w.SelectSingleNode("//x:sheet[@name='Sheet1']",wn);
            if(s==null)throw new InvalidDataException("Không có Sheet1 trong file Excel Sacombank.");
            var relationship=s.Attributes["id","http://schemas.openxmlformats.org/officeDocument/2006/relationships"];
            if(relationship==null)throw new InvalidDataException("Không tìm thấy quan hệ Sheet1.");
            var rels=ReadXml(z,"xl/_rels/workbook.xml.rels");
            var all=rels.GetElementsByTagName("Relationship","http://schemas.openxmlformats.org/package/2006/relationships");
            string target="";foreach(XmlNode rel in all)if(rel.Attributes["Id"].Value==relationship.Value){target=rel.Attributes["Target"].Value;break;}
            if(target.Length==0)throw new InvalidDataException("Không tìm thấy XML của Sheet1.");
            string sheetPath=target.StartsWith("/")?target.TrimStart('/'):"xl/"+target;
            var shared=new List<string>();
            if(z.GetEntry("xl/sharedStrings.xml")!=null){
                var strings=ReadXml(z,"xl/sharedStrings.xml");var sn=Ns(strings);
                foreach(XmlNode si in strings.SelectNodes("/x:sst/x:si",sn))shared.Add(si.InnerText);
            }
            var styleYellow=new List<bool>();
            if(z.GetEntry("xl/styles.xml")!=null){
                var styles=ReadXml(z,"xl/styles.xml");var ns=Ns(styles);
                var fills=styles.SelectNodes("/x:styleSheet/x:fills/x:fill",ns);
                var yellowFills=new List<bool>();foreach(XmlNode fill in fills)yellowFills.Add(IsYellowFill(fill,ns));
                foreach(XmlNode xf in styles.SelectNodes("/x:styleSheet/x:cellXfs/x:xf",ns)){
                    var attr=xf.Attributes["fillId"];int id;
                    styleYellow.Add(attr!=null&&int.TryParse(attr.Value,out id)&&id>=0&&id<yellowFills.Count&&yellowFills[id]);
                }
            }
            var doc=ReadXml(z,sheetPath);var n=Ns(doc);
            var header=new Dictionary<int,string>();
            foreach(XmlNode row in doc.SelectNodes("/x:worksheet/x:sheetData/x:row",n)){
                int rowNumber;var ra=row.Attributes["r"];
                if(ra==null||!int.TryParse(ra.Value,out rowNumber)||rowNumber<5)continue;
                if(rowNumber>100000)throw new InvalidDataException("Excel có quá 100000 dòng, vượt giới hạn an toàn.");
                var cols=new Dictionary<int,string>();bool yellowRow=false;
                foreach(XmlNode cell in row.SelectNodes("x:c",n)){
                    var rr=cell.Attributes["r"];int col=Column(rr==null?"":rr.Value);if(col<1||col>42)continue;
                    cols[col]=SharedOrRaw(cell,n,shared);
                    if(col==1||col==5){var st=cell.Attributes["s"];int style;
                        if(st!=null&&int.TryParse(st.Value,out style)&&style>=0&&style<styleYellow.Count&&styleYellow[style])yellowRow=true;
                    }
                }
                if(rowNumber==5){header=cols;continue;}
                string contract=Get(cols,2),cif=Get(cols,5);if(contract.Length==0||cif.Length==0)continue;
                if(header.Count==0||!Get(header,2).Contains("Số HĐ")||!Get(header,5).Contains("CIF")||!Get(header,30).Contains("Contact mode"))
                    throw new InvalidDataException("File không đúng định dạng Excel Sacombank đã sửa.");
                var phone=Util.Phone(Get(cols,4));if(phone.Length==0)phone=Util.Phone(Get(cols,19));
                var action=Get(cols,33);var klass=Get(cols,42);
                var data=new Customer{Row=rowNumber,Contract=contract,Cif=cif,Name=Get(cols,3),Phone=phone,
                    Reference=Get(cols,25),ReferenceName=Get(cols,24),NewPhone=Get(cols,39),
                    Area=Get(cols,28),Debt=Util.Money(Get(cols,8)),Overdue=(int)Util.Money(Get(cols,11)),
                    Code=action,Reported=Enumerable.Range(30,13).Any(i=>Get(cols,i).Length>0),YellowRow=yellowRow,NextAction=ParseDate(Get(cols,35))};
                data.Promised=CareLogic.IsPromise(action,klass);data.Care=data.YellowRow||data.Promised;
                result.Add(data);
            }
        }
        return result;
    }
    static string Get(Dictionary<int,string> dict,int col){string v;return dict.TryGetValue(col,out v)?v.Trim():"";}
}