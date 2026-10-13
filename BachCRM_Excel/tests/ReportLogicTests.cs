using System;
using System.Collections.Generic;
using System.Linq;

internal class ReportLogicTests {
    static void Assert(bool ok,string name) {
        if (!ok) throw new InvalidOperationException("FAILED: "+name);
        Console.WriteLine("PASS: "+name);
    }
    public static void Main() {
        var data = new List<Customer> {
            new Customer { Row=9, Cif="12916231", Contract="3338716404" },
            new Customer { Row=10, Cif="12916231", Contract="LD2513600812" },
            new Customer { Row=11, Cif="11111111", Contract="3338716404" }
        };
        var same = data.Where(c=>ReportLogic.SameCif(c.Cif,"12916231")).ToList();
        Assert(same.Count==2 && same[0].Row==9 && same[1].Row==10,"Two agreements of same CIF updated");
        Assert(!ReportLogic.SameCif(data[2].Cif,"12916231"),"Other CIF never selected");
        var ak = ReportLogic.MergeHistory(new []{
            "11/10/2026 CALL 0911111111 : Không nghe máy.\n12/10/2026 CALL 0911111111 : Hẹn gọi lại.",
            "12/10/2026 CALL 0911111111 : Hẹn gọi lại."
        },"13/10/2026 CALL 0911111111 : Không nghe máy.");
        Assert(ak.Split('\n').Length==3,"AK cumulative and deduplicated across contracts");
        Assert(ak.Contains("11/10/2026")&&ak.Contains("13/10/2026"),"AK preserves old and new note");
        string latest="13/10/2026 CALL 0911111111 : Không nghe máy.";
        Assert(latest!=ak,"AL latest report is not cumulative AK");
        var entry=ReportLogic.ScenarioEntry("TH2 · Không nghe máy","911111111");
        Assert(entry=="CALL 0911111111 : Không nghe máy.","Scenario output omits TH number");
        Assert(ReportLogic.MergeHistory(new[]{ak},latest)==ak,"Re-saving identical note avoids duplicates");
        Console.WriteLine("ALL TESTS PASSED");
    }
}