using System;using System.Collections.Generic;using System.Globalization;using System.IO;using System.IO.Compression;using System.Linq;using System.Reflection;using System.Text;using System.Xml;
public class ExportFakeExcel {
 public bool Visible{get;set;}public bool DisplayAlerts{get;set;}public bool EnableEvents{get;set;}public bool AskToUpdateLinks{get;set;}public int AutomationSecurity{get;set;}
 public ExportFakeBooks Workbooks{get;private set;}public bool QuitCalled;
 public ExportFakeExcel(){Workbooks=new ExportFakeBooks();}public void Quit(){QuitCalled=true;}
}
public class ExportFakeBooks {public ExportFakeBook Last;public bool FailSave;public ExportFakeBook Open(string path,int links,bool readOnly){return Last=new ExportFakeBook{Path=path,FailSave=FailSave};}}
public class ExportFakeBook {public string Path;public bool FailSave,Deleted,Closed;public bool ReadOnly{get{return false;}}public ExportFakeSheets Worksheets{get{return new ExportFakeSheets(this);}}public void Save(){if(FailSave)throw new IOException("SIMULATED_EXPORT_SAVE_FAILURE");if(!Deleted)throw new Exception("Column deletion was not requested");DailyExportTests.DeleteD(Path);}public void Close(bool save){Closed=true;}}
public class ExportFakeSheets {ExportFakeBook b;public ExportFakeSheets(ExportFakeBook book){b=book;}public ExportFakeSheet this[string name]{get{if(name!="DanhSach")throw new Exception("Wrong sheet selected");return new ExportFakeSheet(b);}}}
public class ExportFakeSheet {ExportFakeBook b;public ExportFakeSheet(ExportFakeBook book){b=book;}public ExportFakeColumns Columns{get{return new ExportFakeColumns(b);}}}
public class ExportFakeColumns {ExportFakeBook b;public ExportFakeColumns(ExportFakeBook book){b=book;}public ExportFakeColumn this[int column]{get{if(column!=4)throw new Exception("Wrong column selected");return new ExportFakeColumn(b);}}}
public class ExportFakeColumn {ExportFakeBook b;public ExportFakeColumn(ExportFakeBook book){b=book;}public void Delete(){b.Deleted=true;}}
public class DailyExportTests {
 static int passed;const string Ns="http://schemas.openxmlformats.org/spreadsheetml/2006/main";
 static void Check(bool yes,string text){if(!yes)throw new Exception(text);Console.WriteLine("PASS "+text);passed++;}
 static void Put(ZipArchive z,string p,string text){using(var w=new StreamWriter(z.CreateEntry(p).Open(),new UTF8Encoding(false)))w.Write(text);}
 static XmlDocument Read(string file,string entry){using(var z=ZipFile.OpenRead(file)){var d=new XmlDocument();using(var s=z.GetEntry(entry).Open())d.Load(s);return d;}}
 static string Cell(string file,string reference){var d=Read(file,"xl/worksheets/sheet1.xml");var c=d.SelectSingleNode("//*[local-name()='c' and @r='"+reference+"']");return c==null?"":c.InnerText;}
 static void Fixture(string path){using(var z=ZipFile.Open(path,ZipArchiveMode.Create)){
  Put(z,"[Content_Types].xml","<Types xmlns='http://schemas.openxmlformats.org/package/2006/content-types'/>");
  Put(z,"xl/workbook.xml","<workbook xmlns='"+Ns+"' xmlns:r='http://schemas.openxmlformats.org/officeDocument/2006/relationships'><sheets><sheet name='Code' sheetId='2' r:id='rId2'/><sheet name='DanhSach' sheetId='1' r:id='rId1'/></sheets></workbook>");
  Put(z,"xl/_rels/workbook.xml.rels","<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='rId1' Target='worksheets/sheet1.xml'/><Relationship Id='rId2' Target='worksheets/sheet2.xml'/></Relationships>");
  Put(z,"xl/worksheets/sheet1.xml","<worksheet xmlns='"+Ns+"'><sheetData><row r='5'><c r='B5' t='inlineStr'><is><t>Số HĐ</t></is></c><c r='D5' t='inlineStr'><is><t>SDT PRIVATE</t></is></c><c r='E5' t='inlineStr'><is><t>CIF</t></is></c><c r='F5' t='inlineStr'><is><t>AFTER D</t></is></c><c r='AD5' t='inlineStr'><is><t>Contact mode</t></is></c></row><row r='6'><c r='B6' t='inlineStr'><is><t>HD01</t></is></c><c r='C6' t='inlineStr' s='1'><is><t>SYNTHETIC CUSTOMER</t></is></c><c r='D6' t='inlineStr'><is><t>0900000000</t></is></c><c r='E6' t='inlineStr'><is><t>00123</t></is></c><c r='H6' s='2'><v>1200000</v></c></row></sheetData></worksheet>");
  Put(z,"xl/worksheets/sheet2.xml","<worksheet xmlns='"+Ns+"'><sheetData><row r='1'><c r='D1' t='inlineStr'><is><t>KEEP CODE COLUMN D</t></is></c></row></sheetData></worksheet>");
  Put(z,"xl/styles.xml","<styleSheet xmlns='"+Ns+"'><fonts count='1'><font><color rgb='FFFFFF00'/></font></fonts><fills count='8'><fill><patternFill patternType='none'/></fill><fill><patternFill patternType='gray125'/></fill><fill><patternFill patternType='solid'><fgColor rgb='FFFFFF00'/></patternFill></fill><fill><patternFill patternType='solid'><fgColor rgb='FF0000FF'/></patternFill></fill><fill><patternFill patternType='solid'><fgColor theme='4' tint='0.5'/></patternFill></fill><fill><patternFill patternType='solid'><fgColor indexed='6'/></patternFill></fill><fill><patternFill patternType='solid'><fgColor indexed='13'/></patternFill></fill><fill><patternFill patternType='darkGrid'><bgColor rgb='FFFFFFCC'/></patternFill></fill></fills><cellXfs count='3'><xf fillId='0' numFmtId='0'/><xf fillId='2' numFmtId='0'/><xf fillId='3' numFmtId='3'/></cellXfs><dxfs count='1'><dxf><fill><patternFill patternType='solid'><fgColor rgb='FFFFFF00'/></patternFill></fill></dxf></dxfs></styleSheet>");
  Put(z,"xl/theme/theme1.xml","<a:theme xmlns:a='http://schemas.openxmlformats.org/drawingml/2006/main'><a:themeElements><a:clrScheme name='Test'><a:accent1><a:srgbClr val='FFFF00'/></a:accent1></a:clrScheme></a:themeElements></a:theme>");
 }}
 public static void DeleteD(string path){using(var z=ZipFile.Open(path,ZipArchiveMode.Update)){var e=z.GetEntry("xl/worksheets/sheet1.xml");var d=new XmlDocument();using(var s=e.Open())d.Load(s);foreach(XmlElement c in d.SelectNodes("//*[local-name()='c']").Cast<XmlElement>().ToArray()){string r=c.GetAttribute("r");int p=0,n=0;while(p<r.Length&&Char.IsLetter(r[p]))n=n*26+r[p++]-'A'+1;if(n==4){c.ParentNode.RemoveChild(c);continue;}if(n>4){n--;string letters="";while(n>0){n--;letters=(char)(65+n%26)+letters;n/=26;}c.SetAttribute("r",letters+r.Substring(p));}}e.Delete();using(var s=z.CreateEntry("xl/worksheets/sheet1.xml").Open())d.Save(s);}}
 static void Export(Assembly app,string source,string output){try{app.GetType("EndOfDayMail").GetMethod("CopyAndVerify").Invoke(null,new object[]{source,output});}catch(TargetInvocationException ex){throw ex.InnerException;}}
 static void Main(string[] args){string root=Path.Combine(Path.GetTempPath(),"BachCRM_DailyExport_"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);try{
  string source=Path.Combine(root,"Source.xlsx"),output=Path.Combine(root,"Report.xlsx");Fixture(source);byte[] original=File.ReadAllBytes(source);
  var app=Assembly.LoadFrom(Path.GetFullPath(args[0]));var excel=new ExportFakeExcel();typeof(BachCRMReportExport).GetField("ExcelFactory",BindingFlags.Static|BindingFlags.NonPublic).SetValue(null,(Func<object>)(()=>excel));
  Export(app,source,output);
  Check(File.Exists(output),"patched daily-export creates final report");Check(original.SequenceEqual(File.ReadAllBytes(source)),"source workbook is byte-for-byte unchanged");
  Check(Cell(output,"D5")=="CIF"&&Cell(output,"D6")=="00123","original E shifts into D; original D is deleted");Check(Cell(output,"E5")=="AFTER D","remaining columns shift left exactly once");
  Check(!Read(output,"xl/worksheets/sheet1.xml").OuterXml.Contains("0900000000"),"deleted D phone value is absent from report data");
  Check(Read(output,"xl/worksheets/sheet2.xml").InnerText=="KEEP CODE COLUMN D","Code sheet column D remains intact");
  Check(Cell(output,"G6")=="1200000","numeric amount preserved while its column shifts");
  var styles=Read(output,"xl/styles.xml");Check(styles.SelectNodes("//*[local-name()='fill']/*[local-name()='patternFill' and @patternType='none']").Count==6,"RGB, indexed, theme/pastel, pattern, conditional yellow fills removed");
  Check(styles.SelectSingleNode("//*[local-name()='fgColor' and @rgb='FF0000FF']")!=null,"blue fill retained");Check(styles.SelectSingleNode("//*[local-name()='fgColor' and @indexed='6']")!=null,"indexed magenta retained");
  Check(styles.SelectSingleNode("//*[local-name()='font']/*[local-name()='color' and @rgb='FFFFFF00']")!=null,"font color retained");Check(styles.SelectSingleNode("//*[local-name()='xf' and @numFmtId='3']")!=null,"number format retained");
  Check(excel.QuitCalled&&excel.Workbooks.Last.Closed,"private Excel instance and report workbook closed");
  Check(!Directory.GetFiles(root,".bachcrm-*.xlsx").Any(),"temporary export workbook removed after success");
  bool refused=false;try{Export(app,source,source);}catch(InvalidOperationException){refused=true;}Check(refused,"export over source rejected");
  refused=false;try{Export(app,source,output);}catch(IOException){refused=true;}Check(refused,"overwriting existing report rejected");
  excel=new ExportFakeExcel();excel.Workbooks.FailSave=true;string failed=Path.Combine(root,"Failed.xlsx");bool failedCorrectly=false;try{Export(app,source,failed);}catch(IOException){failedCorrectly=true;}
  Check(failedCorrectly&&!File.Exists(failed),"Excel save failure produces no misleading final report");Check(original.SequenceEqual(File.ReadAllBytes(source)),"source unchanged after export failure");Check(!Directory.GetFiles(root,".bachcrm-*.xlsx").Any()&&excel.QuitCalled,"failure cleans up temporary file and Excel instance");
  Check(!File.Exists(source+".bachcrm-phulai.xml"),"export creates no coverage-status sidecar");
  Check(app.GetName().Version.ToString()=="1.4.14.45","final EXE version is 1.4.14.45");
  Console.WriteLine("ALL "+passed+" DAILY-EXPORT TESTS PASS (managed Excel substitute; actual Windows COM not executed)");
 }finally{Directory.Delete(root,true);}}
}
