using System;using System.IO;using System.Linq;using Mono.Cecil;
sealed class FrameworkResolver:IAssemblyResolver {
 readonly string framework,package;public FrameworkResolver(string f,string p){framework=f;package=p;}
 public AssemblyDefinition Resolve(AssemblyNameReference a){return Resolve(a,new ReaderParameters());}
 public AssemblyDefinition Resolve(AssemblyNameReference a,ReaderParameters p){p.AssemblyResolver=this;string local=Path.Combine(package,a.Name+".dll"),standard=Path.Combine(framework,a.Name+".dll");if(File.Exists(standard))return AssemblyDefinition.ReadAssembly(standard,p);if(File.Exists(local))return AssemblyDefinition.ReadAssembly(local,p);throw new FileNotFoundException("No explicit Framework reference for "+a.Name);}
 public void Dispose(){}
}
class WindowsApiCheck {
 static int Main(string[] a){bool negative=a.Contains("--expect-incompatible");int absent=0,checkedCount=0;
  using(var resolver=new FrameworkResolver(a[0],Path.GetDirectoryName(Path.GetFullPath(a[1])))) {
   var asm=AssemblyDefinition.ReadAssembly(a[1],new ReaderParameters{AssemblyResolver=resolver});
   foreach(var member in asm.MainModule.GetMemberReferences().OfType<MethodReference>()){
    if(member.DeclaringType is ArrayType)continue;
    try{if(member.Resolve()==null){Console.WriteLine("MISSING WINDOWS API: "+member.FullName);absent++;}else checkedCount++;}
    catch(Exception ex){Console.WriteLine("UNRESOLVED: "+member.FullName+" :: "+ex.Message);absent++;}
   }
  }
  if(negative){if(absent==0){Console.WriteLine("FAIL: negative control did not detect incompatible API");return 1;}Console.WriteLine("PASS: previous exporter rejected ("+absent+" incompatible APIs)");return 0;}
  if(absent>0)return 1;
  Console.WriteLine("PASS: "+checkedCount+" method references resolve against explicit .NET Framework 4.5 API assemblies.");return 0;
 }
}
