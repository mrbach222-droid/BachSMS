using System;using System.Collections;using System.Collections.Generic;using System.Globalization;using System.IO;using System.Linq;using System.Reflection;using System.Runtime.Serialization;
public class DateCustomer {public string Cif;public DateTime? ContactDate,NextAction;public string ActionHistory;}
class ContactDateTests {
 static int passed;static void Check(bool yes,string label){if(!yes)throw new Exception(label);Console.WriteLine("PASS "+label);passed++;}
 static void Set(object o,string field,object value){o.GetType().GetField(field,BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic).SetValue(o,value);}
 static object Call(object o,string name,params object[] args){return o.GetType().GetMethod(name,BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic).Invoke(o,args);}
 static void Main(string[] args){
  var old=new DateCustomer{Cif="001",ContactDate=new DateTime(2026,10,19),NextAction=new DateTime(2026,11,10),ActionHistory="10/31/2026 CALL history that must not override AF"};
  var latest=new DateCustomer{Cif="001",ContactDate=new DateTime(2026,10,21,14,30,0)};var missing=new DateCustomer{Cif="002"};var separate=new DateCustomer{Cif="003",ContactDate=new DateTime(2026,10,20)};
  var rows=new[]{old,latest,missing,separate};object owner=new object();BachCRMContactDate.Prepare(owner,rows);
  Check(BachCRMContactDate.FilterValue(owner,old)=="21/10/2026","latest AF of CIF is shown even on an older representative agreement");
  Check(BachCRMContactDate.Value(owner,old)==new DateTime(2026,10,21),"AF time portion does not split date filter groups");
  Check(BachCRMContactDate.FilterValue(owner,missing)==BachCRMContactDate.Missing,"blank AF has its own filter value");
  Check(BachCRMContactDate.FilterValue(owner,separate)=="20/10/2026","different CIF keeps its own AF");
  Check(BachCRMContactDate.FilterValue(owner,old)!="31/10/2026"&&BachCRMContactDate.FilterValue(owner,old)!="10/11/2026","AK history and next-action appointment cannot supply this column");
  latest.ContactDate=new DateTime(2026,10,22);BachCRMContactDate.Prepare(owner,rows);Check(BachCRMContactDate.FilterValue(owner,old)=="22/10/2026","refresh after AF update rebuilds values");
  BachCRMContactDate.Prepare(owner,new[]{old,missing,separate});Check(BachCRMContactDate.FilterValue(owner,old)=="19/10/2026","only active agreements supplied by CRM influence latest date");
  var caseCif=new[]{new DateCustomer{Cif="ABC",ContactDate=new DateTime(2026,9,30)},new DateCustomer{Cif="abc",ContactDate=new DateTime(2026,10,1)}};Check(BachCRMContactDate.Dates(caseCif)["ABC"]==new DateTime(2026,10,1),"CIF matching ignores case across month boundary");
  object secondOwner=new object();BachCRMContactDate.Prepare(secondOwner,new[]{new DateCustomer{Cif="001",ContactDate=new DateTime(2025,12,31)}});Check(BachCRMContactDate.FilterValue(secondOwner,old)=="31/12/2025"&&BachCRMContactDate.FilterValue(owner,old)=="19/10/2026","different CRM/workbook contexts stay independent");
  CultureInfo previous=CultureInfo.CurrentCulture;try{System.Threading.Thread.CurrentThread.CurrentCulture=new CultureInfo("en-US");Check(BachCRMContactDate.FilterValue(owner,old)=="19/10/2026","date filter text stays dd/MM/yyyy under English Windows locale");}finally{System.Threading.Thread.CurrentThread.CurrentCulture=previous;}
  string[] compact={"cif","copycif","name","detail","result","forecast","repay","paiddate","act"};int[] minimum=Enumerable.Range(1,9).ToArray();var expanded=BachCRMContactDate.AddLayoutColumn(compact);var widths=BachCRMContactDate.AddCompactWidth(minimum);
  Check(expanded.Length==widths.Length&&expanded[5]==BachCRMContactDate.Key&&widths[5]==132,"compact column names and widths stay aligned");Check(expanded[6]=="forecast"&&widths[6]==6,"existing action/finance columns retain their matching widths");Check(compact.Length==9&&minimum.Length==9,"layout helpers do not mutate original input arrays");Check(BachCRMContactDate.AddLayoutColumn(expanded).Length==10,"column registration is idempotent");
  var keys=BachCRMContactDate.AddKey(new[]{"cif","paiddate"});var labels=BachCRMContactDate.AddLabel(new[]{"CIF","Ngày đã TT"});Check(keys.Length==labels.Length&&keys.Last()=="lastcontact"&&labels.Last()==BachCRMContactDate.Label,"existing filter selector receives matching key and label");
  var app=Assembly.LoadFrom(Path.GetFullPath(args[0]));var type=app.GetType("Customer");var list=(IList)Activator.CreateInstance(typeof(List<>).MakeGenericType(type));object c1=Activator.CreateInstance(type,true),c2=Activator.CreateInstance(type,true);Set(c1,"Cif","001");Set(c1,"ContactDate",(DateTime?)new DateTime(2026,10,19));Set(c2,"Cif","001");Set(c2,"ContactDate",(DateTime?)new DateTime(2026,10,21));list.Add(c1);list.Add(c2);
  object crm=FormatterServices.GetUninitializedObject(app.GetType("CRM"));Set(crm,"columnFilters",new Dictionary<string,HashSet<string>>{{"lastcontact",new HashSet<string>{"21/10/2026"}}});BachCRMContactDate.Prepare(crm,list);
  Check((string)Call(crm,"FilterValue",c1,"lastcontact")=="21/10/2026","actual patched CRM FilterValue dispatches to AF aggregation");Check((bool)Call(crm,"MatchesFilters",c1)&&(bool)Call(crm,"MatchesFilters",c2),"actual existing filter retains all agreements of a matching CIF");
  Set(crm,"columnFilters",new Dictionary<string,HashSet<string>>{{"lastcontact",new HashSet<string>{"19/10/2026"}}});Check(!(bool)Call(crm,"MatchesFilters",c1)&&!(bool)Call(crm,"MatchesFilters",c2),"old AF on one contract does not leak CIF into wrong date filter");
  Set(crm,"columnFilters",new Dictionary<string,HashSet<string>>{{"lastcontact",new HashSet<string>{"21/10/2026"}},{"cif",new HashSet<string>{"OTHER"}}});Check(!(bool)Call(crm,"MatchesFilters",c1),"new date filter combines with existing CIF filters");
  Set(crm,"columnFilters",new Dictionary<string,HashSet<string>>());Check((bool)Call(crm,"MatchesFilters",c1),"clearing existing filter dictionary also clears AF filtering");
  var sizes=(Dictionary<string,int>)crm.GetType().GetMethod("CompactSizes",BindingFlags.Static|BindingFlags.NonPublic).Invoke(null,new object[]{1100});Check(sizes.ContainsKey("lastcontact")&&sizes["lastcontact"]==132,"actual compact sizing includes the AF column without mismatched arrays");
  string root=Path.Combine(Path.GetTempPath(),"BachCRM_AF_"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);try{
   var sheet=ReportRangeTests.Fixture();sheet.Cells[6,32].Value2=new DateTime(2026,9,30).ToOADate();sheet.Cells[7,32].Value2=new DateTime(2026,10,21).ToOADate();for(int row=8;row<=11;row++)sheet.Cells[row,32].Value2="";sheet.Cells[12,32].Value2="";
   string path=Path.Combine(root,"Synthetic.xlsx");ReportRangeTests.Write(path,sheet);object store=Activator.CreateInstance(app.GetType("ExcelStore"),BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic,null,new object[]{path},null);object customers=store.GetType().GetProperty("Customers").GetValue(store,null);var dates=BachCRMContactDate.Dates(customers);
   Check(dates["00123"]==new DateTime(2026,10,21),"actual Excel reader supplies AF serial dates; latest across six contracts is selected");Check(!dates["OTHER"].HasValue,"actual Excel reader leaves blank AF missing despite other report data");
  }finally{Directory.Delete(root,true);}
  Check(app.GetName().Version.ToString()=="1.4.14.45","final executable version is v45");Console.WriteLine("ALL "+passed+" AF DATE / EXISTING FILTER CHECKS PASS");
 }
}
