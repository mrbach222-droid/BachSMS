using System;using System.Collections.Generic;using System.IO;using System.Linq;using System.Reflection;
class SyntheticCustomer {public string Cif,Name,Phone,NewPhone,Contract;}
class CloudTests {
 static int count;static void Check(bool yes,string label){if(!yes)throw new Exception(label);count++;Console.WriteLine("PASS "+label);}
 [STAThread] static void Main(string[] a){
  Check(BachCRMCloud.NormalizePhone("+84 912 345 678")=="0912345678","+84 phone normalized");Check(BachCRMCloud.NormalizePhone("912345678")=="0912345678","leading zero restored");Check(BachCRMCloud.NormalizePhone("0084912345678")=="0912345678","0084 normalized");Check(BachCRMCloud.NormalizePhone("invalid")=="","invalid number not exported");
  var customers=BachCRMCloud.Customers(new[]{new SyntheticCustomer{Cif="001",Name="KH THU",Phone="0912345678",Contract="A"},new SyntheticCustomer{Cif="001",Name="KH THU",Phone="0912345678",Contract="B"},new SyntheticCustomer{Cif="002",Name="KH THU 2",Phone="0900000000",NewPhone="0987654321",Contract="C"}});
  Check(customers.Count==2&&customers[0].contract_number=="A, B","multiple agreements for same CIF/phone produce one row");Check(customers[1].phone=="0987654321","updated valid customer number takes priority");
  var many=Enumerable.Range(0,130).Select(i=>new CloudCustomer{cif=i.ToString(),customer_name="SYNTHETIC",phone="0900000000",contract_number="HD",message=""});var batches=BachCRMCloud.Batches(many);Check(batches.Select(b=>b.jobs.Count).SequenceEqual(new[]{40,40,40,10}),"130 customers split within free Worker query budget");Check(batches.SelectMany(b=>b.jobs).Select(j=>j.id).Distinct().Count()==130,"jobs have unique IDs");
  string path=Path.Combine(Path.GetTempPath(),"BachCloudTest-"+Guid.NewGuid().ToString("N")+".bin");try{var transfer=new CloudTransfer{channel="test",batches=batches};BachCRMCloud.Save(path,transfer);var restored=BachCRMCloud.Load<CloudTransfer>(path);Check(restored.batches[0].id==batches[0].id&&restored.batches[0].jobs[0].id==batches[0].jobs[0].id,"encrypted pending queue retains retry IDs");Check(!System.Text.Encoding.UTF8.GetString(File.ReadAllBytes(path)).Contains("SYNTHETIC"),"pending queue is protected for current Windows user");}finally{if(File.Exists(path))File.Delete(path);}
  Check(BachCRMCloud.ValidateURL("https://test.workers.dev/")=="https://test.workers.dev","Worker root URL accepted");foreach(string url in new[]{"http://test.workers.dev","https://u:p@x.com","https://x.com?token=x","https://x.com/path"}){bool denied=false;try{BachCRMCloud.ValidateURL(url);}catch(InvalidOperationException){denied=true;}Check(denied,"invalid/credential-bearing endpoint refused");}
  var app=Assembly.LoadFrom(Path.GetFullPath(a[0]));var type=app.GetType("Customer");object original=Activator.CreateInstance(type,true);foreach(var item in new Dictionary<string,string>{{"Cif","001"},{"Name","KH THU"},{"Phone","0912345678"},{"Contract","A"}})type.GetField(item.Key).SetValue(original,item.Value);Check(BachCRMCloud.Customers(new[]{original}).Single().phone=="0912345678","adapter reads actual CRM Customer fields");
  Check(app.GetName().Version.ToString()=="1.4.14.45","final CRM assembly version matches package");
  using(var host=new System.Windows.Forms.Form{Width=1000,Height=700}){
   var body=new System.Windows.Forms.Panel{Dock=System.Windows.Forms.DockStyle.Fill};host.Controls.Add(body);BachCRMCloud.Install(host);BachCRMCloud.Install(host);host.Show();System.Windows.Forms.Application.DoEvents();
   var bars=host.Controls.OfType<System.Windows.Forms.ToolStrip>().ToList();Check(bars.Count==1&&body.Top>=bars[0].Bottom,"native Windows cloud toolbar installs once and reserves space above existing content");host.Close();
  }
  var pickerType=typeof(BachCRMCloud).GetNestedType("CloudPicker",BindingFlags.NonPublic);
  using(var picker=(System.Windows.Forms.Form)Activator.CreateInstance(pickerType,BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic,null,new object[]{customers,new HashSet<string>{"001"}},null)){
   picker.Show();System.Windows.Forms.Application.DoEvents();var table=picker.Controls.OfType<System.Windows.Forms.TableLayoutPanel>().Single().Controls.OfType<System.Windows.Forms.DataGridView>().Single();Check(table.Columns.Count==5&&table.Rows.Count==2&&!table.Columns[0].ReadOnly&&table.Columns[1].ReadOnly,"native Windows picker binds rows and checkbox before first use");picker.Close();
  }
  Console.WriteLine("ALL "+count+" CRM CLOUD DATA/QUEUE AND WINDOWS UI SMOKE CHECKS PASS");
 }
}
