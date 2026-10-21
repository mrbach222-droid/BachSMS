using System;using System.Collections.Generic;using System.Linq;using Mono.Cecil;using Mono.Cecil.Cil;
class VerifyCloud45 {
 static IEnumerable<TypeDefinition> Types(IEnumerable<TypeDefinition> ts){foreach(var t in ts){yield return t;foreach(var n in Types(t.NestedTypes))yield return n;}}
 static string IL(MethodDefinition m){return m.HasBody?String.Join("\n",m.Body.Instructions.Select(i=>i.ToString())):"";}
 static void Main(string[] a){var before=AssemblyDefinition.ReadAssembly(a[0]);var after=AssemblyDefinition.ReadAssembly(a[1]);var old=Types(before.MainModule.Types).SelectMany(t=>t.Methods).ToDictionary(m=>m.FullName);int same=0,changed=0;
  foreach(var m in Types(after.MainModule.Types).SelectMany(t=>t.Methods)){if(IL(m)==IL(old[m.FullName])){same++;continue;}if(m.DeclaringType.Name!="CRM"||m.Name!=".ctor")throw new Exception("Unrelated method changed "+m.FullName);if(m.Body.Instructions.Count(i=>i.Operand is MethodReference&&((MethodReference)i.Operand).DeclaringType.Name=="BachCRMCloud"&&((MethodReference)i.Operand).Name=="Install")!=1)throw new Exception("Wrong installer registration");changed++;}
  if(changed!=1||after.Name.Version.ToString()!="1.4.14.45")throw new Exception("Unexpected patch");foreach(var r in before.MainModule.Resources.OfType<EmbeddedResource>())if(!r.GetResourceData().SequenceEqual(after.MainModule.Resources.OfType<EmbeddedResource>().Single(n=>n.Name==r.Name).GetResourceData()))throw new Exception("Resource changed");
  Console.WriteLine("PASS "+same+" existing methods unchanged; only CRM constructor caption/installer changed. Statistics, AF filters, report save, coverage and export preserved.");
 }
}
