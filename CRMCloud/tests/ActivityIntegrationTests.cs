using System;using System.Collections;using System.Collections.Generic;using System.IO;using System.Linq;using System.Reflection;
class IntegrationTests {
 static Assembly app;static int passed;
 static void Check(bool yes,string title){if(!yes)throw new Exception(title);Console.WriteLine("PASS "+title);passed++;}
 static object Get(object o,string name){return o.GetType().GetProperty(name).GetValue(o,null);}
 static object F(object o,string name){return o.GetType().GetField(name).GetValue(o);}
 static void Set(object o,string name,object value){o.GetType().GetField(name,BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic).SetValue(o,value);}
 static object Call(object o,string name,params object[] args){try{return o.GetType().GetMethods(BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic).Single(m=>m.Name==name&&m.GetParameters().Length==args.Length).Invoke(o,args);}catch(TargetInvocationException ex){throw ex.InnerException;}}
 static object First(object store){return ((IEnumerable)Get(store,"Customers")).Cast<object>().First(c=>(string)F(c,"Cif")=="00123");}
 static bool Covered(object store,object customer){object group=Activator.CreateInstance(typeof(System.Collections.Generic.List<>).MakeGenericType(customer.GetType()));foreach(var c in ((IEnumerable)Get(store,"Customers")).Cast<object>().Where(c=>(string)F(c,"Cif")== (string)F(customer,"Cif")))((IList)group).Add(c);return (bool)app.GetType("MonthlyBookCoverage").GetMethod("CoveredCif").Invoke(null,new object[]{group,DateTime.Today});}
 static object Report(string label){var d=Activator.CreateInstance(app.GetType("ReportData"),true);var text=(string[])F(d,"Text");string date=DateTime.Today.ToString("MM/dd/yyyy",System.Globalization.CultureInfo.InvariantCulture);text[0]="Call";text[2]=date;text[3]="Không hứa thanh toán";text[7]=date+" CALL "+label;text[8]=text[7];text[12]="Call - Không hứa thanh toán";return d;}
 static void Main(string[] args){app=Assembly.LoadFrom(Path.GetFullPath(args[0]));string root=Path.Combine(Path.GetTempPath(),"BachCRM_PatchedIntegration_"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);try{
  var sheet=ReportRangeTests.Fixture();string path=Path.Combine(root,"Synthetic.xlsx");ReportRangeTests.Write(path,sheet);var book=new ReportTestBook(path,sheet);
  object store=Activator.CreateInstance(app.GetType("ExcelStore"),BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic,null,new object[]{path},null);Set(store,"book",book);Set(store,"sheet",sheet);object c=First(store);
  Check(Covered(store,c),"patched EXE constructor binds actual parsed workbook");
  sheet.Operations.Clear();Check((int)Call(store,"SaveReport",c,Report("repeat attempt 1"),false)==6,"patched SaveReport saves all six agreements");
  Check(!Covered(store,c),"actual EXE SaveReport changes DONE to REPEAT");
  var records=BachCRMActivity.Read(path);Check(records.Count==1&&records[0].Committed&&records[0].Cif=="00123","successful EXE save writes one committed timestamp per CIF, not six contracts");
  Check(records[0].Created>DateTimeOffset.Now.AddMinutes(-1)&&records[0].Content.Contains("repeat attempt 1"),"saved timestamp and report content are preserved");
  DateTimeOffset firstTime=records[0].Created;
  Check(book.Backups==1&&book.Saves==1&&sheet.Operations.IndexOf("BACKUP")<sheet.Operations.IndexOf("WRITE"),"original one-backup/one-save ordering retained");
  Check(Convert.ToString(sheet.Cells[12,37].Value2).Contains("riêng HĐ 7"),"other CIF remains untouched");
  Check(Enumerable.Range(6,6).All(r=>Convert.ToString(sheet.Cells[r,40].Formula)=="=1+1"),"existing untouched formulas retained");
  Call(store,"Load");c=First(store);Check(!Covered(store,c),"actual Load restores REPEAT after disk reload");
  var original=(string[])Call(store,"ReadReport",c);var edited=(string[])original.Clone();edited[11]="corrected old note";
  Call(store,"CorrectReport",c,original,edited,false,false,false);c=First(store);Check(!Covered(store,c),"actual CorrectReport does not move group");
  records=BachCRMActivity.Read(path);Check(records.Count==2&&records.Count(x=>x.Kind=="Edit")==1&&records[0].Created==firstTime,"correction records a separate edit time without replacing creation time");
  var same=(string[])Call(store,"ReadReport",c);Call(store,"CorrectReport",c,same,(string[])same.Clone(),false,false,false);Check(BachCRMActivity.Read(path).Count==2,"unchanged correction creates no timestamp");
  Call(store,"SaveReport",c,Report("repeat attempt 2"),false);Check(Covered(store,c),"actual EXE SaveReport changes REPEAT to DONE same day");
  Call(store,"Load");c=First(store);Check(Covered(store,c),"DONE persists through actual workbook reload");
  book.FailSave=true;bool failed=false;try{Call(store,"SaveReport",c,Report("failed attempt"),false);}catch(IOException){failed=true;}Check(failed,"actual SaveReport propagates failed Excel save");
  Check(Covered(store,c),"failed actual SaveReport keeps DONE in memory");Call(store,"Load");c=First(store);Check(Covered(store,c),"failed actual SaveReport keeps DONE after disk reload");
  var snapshot=new Dictionary<DateTime,HashSet<string>>{{DateTime.Today,new HashSet<string>{"00123","OTHER"}}};var day=BachCRMActivity.BuildDay(path,Get(store,"Customers"),snapshot,DateTime.Today);var customer=day.Single(x=>x.Cif=="00123");
  Check(day.Count==2&&customer.Events.Count(x=>x.Kind=="Create")==2&&customer.Events.Count(x=>x.Kind=="Edit")==1,"day details contain both successful reports and edit, excluding failed save");
  Check(!day.Single(x=>x.Cif=="OTHER").Created.HasValue,"legacy customer appears without fabricated hour");
  Check(customer.Created.HasValue&&customer.Modified.HasValue,"created and modified columns are populated independently");
  book.FailSave=false;Call(store,"SaveReport",c,Report("retry after failure"),false);Call(store,"Load");c=First(store);
  customer=BachCRMActivity.BuildDay(path,Get(store,"Customers"),snapshot,DateTime.Today).Single(x=>x.Cif=="00123");Check(customer.Events.Count(x=>x.Kind=="Create")==3,"retry replaces stale pending action without phantom duplicate");
  sheet.Operations.Clear();bool blocked=false;using(var fileLock=new FileStream(BachCRMActivity.Storage(path)+".lock",FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None)){try{Call(store,"SaveReport",c,Report("blocked trace"),false);}catch(IOException){blocked=true;}}
  Check(blocked&&!sheet.Operations.Contains("WRITE"),"timestamp lock failure stops before report-cell writes");
  snapshot[DateTime.Today].UnionWith(Enumerable.Range(1,35).Select(n=>"LEGACY"+n));Check(BachCRMActivity.BuildDay(path,Get(store,"Customers"),snapshot,DateTime.Today).Count==37,"37-count drilldown returns exactly 37 unique CIFs");
  Check(BachCRMActivity.BuildDay(path,Get(store,"Customers"),snapshot,DateTime.Today.AddDays(-1)).Count==0,"another date does not leak today's customers or events");
  string unrelated=Path.Combine(root,"Other.xlsx");Check(BachCRMActivity.BuildDay(unrelated,Get(store,"Customers"),snapshot,DateTime.Today).All(x=>!x.Created.HasValue),"identical CIF in another workbook does not borrow timestamps");
  Check(app.GetName().Version.ToString()=="1.4.14.45","EXE assembly version is 1.4.14.45");
  Console.WriteLine("ALL "+passed+" PATCHED-EXE INTEGRATION TESTS PASS (managed Excel substitute; Windows Excel COM not executed)");
 }finally{Directory.Delete(root,true);}}
}
