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
        // UI bookmark identity must survive a complete grid regeneration, including same-CIF contracts.
        var visible = new Dictionary<int,Customer> {
            {0,new Customer{Row=6,Cif="A",Contract="HD1"}},
            {1,new Customer{Row=7,Cif="A",Contract="HD2"}},
            {2,new Customer{Row=31,Cif="B",Contract="HD3"}},
            {3,new Customer{Row=32,Cif="B",Contract="HD4"}}
        };
        Assert(GridStateLogic.FindIndex(visible,31,0)==2,"Viewport restores selected workbook row after save");
        Assert(GridStateLogic.FindIndex(visible,7,0)==1,"Viewport restores original top visible workbook row");
        Assert(GridStateLogic.FindIndex(visible,999,1)==1,"Filtered-out anchor uses bounded fallback");
        // Original MB template text and recipient mappings, independent of Excel cached Code choices.
        // TH1, TH2, TH3, TH5: append SMS follow-up exactly once.
        // TH4, TH6: preserve original MB notes without the follow-up sentence.
        string[] originalMb = {
            "CALL 0911111111 : Thuê bao mất liên lạc, không có tín hiệu kết nối.",
            "CALL 0911111111 : Có tín hiệu, không nghe máy.",
            "CALL 0911111111 : Số máy gọi không đúng/không có",
            "CALL 0911111111 : Đúng KH, trao đổi về khoản nợ, ",
            "CALL 0911111111: Báo không phải KH, không biết KH",
            "CALL 0911111111: Xác thực đúng KH, trao đổi về khoản nợ hẹn...."
        };
        for (int i=0;i<6;i++) {
            string actual=MbReportTemplates.Note(i,"0911111111");
            bool append=(i==0||i==1||i==2||i==4);
            string normalized=originalMb[i].TrimEnd();
            if(append && !normalized.EndsWith(".")&&!normalized.EndsWith("!")&&!normalized.EndsWith("?")) normalized+=".";
            string expected=normalized+(append?" "+MbReportTemplates.SmsFollowup:"");
            Assert(actual==expected,"Scenario "+(i+1)+" SMS inclusion/exclusion and original text");
            Assert(actual.Split(new[]{MbReportTemplates.SmsFollowup},StringSplitOptions.None).Length==(append?2:1),"Scenario "+(i+1)+" SMS exactly once");
        }
        Assert(MbReportTemplates.ContactPerson[0]=="Không gặp ai" && MbReportTemplates.ContactPerson[1]=="Không gặp ai" && MbReportTemplates.ContactPerson[2]=="Không gặp ai","TH1-3 are no answer");
        Assert(MbReportTemplates.ContactPerson[3]=="Khách hàng" && MbReportTemplates.ContactPerson[4]=="Người khác" && MbReportTemplates.ContactPerson[5]=="Khách hàng","TH4-6 recipients reset correctly");
        Console.WriteLine("ALL TESTS PASSED");
    }
}