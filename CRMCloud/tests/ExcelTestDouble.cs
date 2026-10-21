using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text;
using System.Xml;
using System.Windows.Forms;

// A strict managed Excel-dispatch substitute: Range requires both endpoints.
// Tests exercise the real ExcelStore review/save path, not a duplicate algorithm.
// Actual Windows Excel COM is intentionally not claimed by this test suite.
public sealed class ReportTestInterior {
    public object Color {get;set;}
    public object ColorIndex {get;set;}
}
public sealed class ReportTestCell {
    readonly ReportTestSheet owner;
    object value,formula;
    public ReportTestCell(ReportTestSheet sheet){owner=sheet;Interior=new ReportTestInterior();}
    public object Value2 {get{return value;}set{this.value=value;formula=null;owner.Wrote();}}
    public object Formula {
        get{return formula??value;}
        set{string f=value as string;if(f!=null&&f.StartsWith("=",StringComparison.Ordinal))formula=value;else{formula=null;this.value=value;}owner.Wrote();}
    }
    public object NumberFormat {get;set;}
    public bool WrapText {get;set;}
    public ReportTestInterior Interior {get;private set;}
}
public sealed class ReportTestCells {
    readonly ReportTestSheet owner;
    readonly Dictionary<string,ReportTestCell> cells=new Dictionary<string,ReportTestCell>();
    public ReportTestCells(ReportTestSheet sheet){owner=sheet;}
    public ReportTestCell this[int row,int column]{get{
        string key=row+":"+column;ReportTestCell c;
        if(!cells.TryGetValue(key,out c)){c=new ReportTestCell(owner);cells.Add(key,c);}return c;
    }}
}
public sealed class ReportTestRange {
    readonly ReportTestSheet sheet;
    readonly int r1,r2,c1,c2;
    public ReportTestRange(ReportTestSheet s,int firstRow,int firstCol,int lastRow,int lastCol){sheet=s;r1=firstRow;c1=firstCol;r2=lastRow;c2=lastCol;}
    object[,] Read(bool formula){
        var a=(object[,])Array.CreateInstance(typeof(object),new[]{r2-r1+1,c2-c1+1},new[]{1,1});
        for(int r=r1;r<=r2;r++)for(int c=c1;c<=c2;c++)a[r-r1+1,c-c1+1]=formula?sheet.Cells[r,c].Formula:sheet.Cells[r,c].Value2;
        return a;
    }
    public object Value2 {get{return Read(false);}}
    public object Formula {get{return Read(true);}set{
        var a=(object[,])value;int ar=a.GetLowerBound(0),ac=a.GetLowerBound(1);
        for(int r=r1;r<=r2;r++)for(int c=c1;c<=c2;c++)sheet.Cells[r,c].Formula=a[ar+r-r1,ac+c-c1];
    }}
    public ReportTestInterior Interior {get{return sheet.Cells[r1,c1].Interior;}}
    public string NumberFormat {get;set;}
}
public sealed class ReportTestSheet {
    public ReportTestCells Cells {get;private set;}
    public readonly List<string> Operations=new List<string>();
    public bool RejectRange;
    public ReportTestSheet(){Cells=new ReportTestCells(this);}
    public void Wrote(){Operations.Add("WRITE");}
    static void Address(string s,out int row,out int col){int p=0;col=0;while(p<s.Length&&Char.IsLetter(s[p])){col=col*26+s[p]-'A'+1;p++;}row=Int32.Parse(s.Substring(p),CultureInfo.InvariantCulture);}
    [IndexerName("Range")]
    public ReportTestRange this[string first,string last]{get{
        if(RejectRange)throw new InvalidOperationException("EXCEL_BUSY_TEST");
        int r1,c1,r2,c2;Address(first,out r1,out c1);Address(last,out r2,out c2);
        Operations.Add("RANGE "+first+":"+last);
        return new ReportTestRange(this,r1,c1,r2,c2);
    }}
}
public sealed class ReportTestBook {
    public string FullName {get;private set;}
    public bool ReadOnly {get;set;}
    public int Backups,Saves; public bool FailSave;
    public readonly ReportTestSheet Sheet;
    public ReportTestBook(string path,ReportTestSheet sheet){FullName=path;Sheet=sheet;}
    public void SaveCopyAs(string destination){Sheet.Operations.Add("BACKUP");File.Copy(FullName,destination);Backups++;}
    public void Save(){if(FailSave)throw new IOException("SIMULATED_EXCEL_SAVE_FAILURE");Sheet.Operations.Add("SAVE");ReportRangeTests.Write(FullName,Sheet);Saves++;}
}
public static class ReportRangeTests {
static string Letters(int n){string s="";while(n>0){n--;s=(char)(65+n%26)+s;n/=26;}return s;}
    static void Put(ZipArchive z,string name,string value){using(var w=new StreamWriter(z.CreateEntry(name).Open(),new UTF8Encoding(false)))w.Write(value);}
    internal static void Write(string path,ReportTestSheet sheet){
        const string ns="http://schemas.openxmlformats.org/spreadsheetml/2006/main";
        using(var fs=File.Create(path))using(var z=new ZipArchive(fs,ZipArchiveMode.Create)){
            Put(z,"xl/workbook.xml","<workbook xmlns='"+ns+"' xmlns:r='http://schemas.openxmlformats.org/officeDocument/2006/relationships'><sheets><sheet name='Data' sheetId='1' r:id='rId1'/></sheets><definedNames><definedName name='_BACHCRM_DATE_MDY_V1'>TRUE</definedName></definedNames></workbook>");
            Put(z,"xl/_rels/workbook.xml.rels","<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='rId1' Target='worksheets/sheet1.xml' Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet'/></Relationships>");
            using(var stream=z.CreateEntry("xl/worksheets/sheet1.xml").Open())using(var w=XmlWriter.Create(stream)){
                w.WriteStartElement("worksheet",ns);w.WriteStartElement("sheetData",ns);
                for(int r=5;r<=12;r++){
                    w.WriteStartElement("row",ns);w.WriteAttributeString("r",r.ToString(CultureInfo.InvariantCulture));
                    for(int c=1;c<=42;c++){
                        object raw=sheet.Cells[r,c].Value2;if(raw==null)continue;
                        w.WriteStartElement("c",ns);w.WriteAttributeString("r",Letters(c)+r);
                        string f=sheet.Cells[r,c].Formula as string;
                        if(f!=null&&f.StartsWith("=",StringComparison.Ordinal)){w.WriteElementString("f",ns,f.Substring(1));w.WriteElementString("v",ns,Convert.ToString(raw,CultureInfo.InvariantCulture));}
                        else if(raw is double||raw is int){w.WriteElementString("v",ns,Convert.ToString(raw,CultureInfo.InvariantCulture));}
                        else{w.WriteAttributeString("t","inlineStr");w.WriteStartElement("is",ns);w.WriteElementString("t",ns,Convert.ToString(raw,CultureInfo.InvariantCulture));w.WriteEndElement();}
                        w.WriteEndElement();
                    }
                    w.WriteEndElement();
                }
                w.WriteEndElement();w.WriteEndElement();
            }
        }
    }
    public static ReportTestSheet Fixture(){
        var s=new ReportTestSheet();
        for(int c=1;c<=42;c++)s.Cells[5,c].Value2="Cột "+Letters(c);
        s.Cells[5,2].Value2="Số HĐ";s.Cells[5,5].Value2="CIF";s.Cells[5,30].Value2="Contact mode";
        for(int r=6;r<=12;r++){
            s.Cells[r,2].Value2=r==12?"HĐ-1":"HĐ-"+(r-5);s.Cells[r,5].Value2=r==12?"OTHER":"00123";
            s.Cells[r,3].Value2="KH THỬ NGHIỆM";s.Cells[r,8].Value2=r*100;s.Cells[r,30].Value2="Call";
            s.Cells[r,31].Value2="Khách hàng";s.Cells[r,32].Value2=DateTime.Today.ToOADate();
            s.Cells[r,33].Value2="Không hứa thanh toán";s.Cells[r,34].Value2=r*10;
            s.Cells[r,35].Value2=new DateTime(2026,10,20).ToOADate();s.Cells[r,36].Value2="Call";
            s.Cells[r,37].Value2="10/15/2026: Lịch sử riêng HĐ "+(r-5)+"\n10/16/2026: Đã liên hệ";
            s.Cells[r,38].Value2="10/16/2026: Không có cam kết";
            s.Cells[r,39].Value2="0900000123";s.Cells[r,40].Value2=2;s.Cells[r,40].Formula="=1+1";
            s.Cells[r,41].Value2="Thông tin cũ";s.Cells[r,42].Value2="Call - Không hứa thanh toán";
        }
        s.Operations.Clear();return s;
    }
}
