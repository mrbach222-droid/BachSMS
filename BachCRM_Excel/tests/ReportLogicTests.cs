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
        Assert(ExcelComBusyFilter.IsBusy(new System.Runtime.InteropServices.COMException("Excel temporarily rejected",unchecked((int)0x80010001))),"RPC_E_CALL_REJECTED is retryable");
        Assert(ExcelComBusyFilter.IsBusy(new System.Runtime.InteropServices.COMException("Excel retry later",unchecked((int)0x8001010A))),"RPC_E_SERVERCALL_RETRYLATER is retryable");
        Assert(!ExcelComBusyFilter.IsBusy(new System.Runtime.InteropServices.COMException("Other COM failure",unchecked((int)0x80004005))),"Non-busy COM failures are not retried");
        // No duplicates: every care CIF appears once even with many contracts.
        var careData=new List<Customer>{
            new Customer{Row=6,Cif="100",Contract="HD1",Promised=true,Reported=true},
            new Customer{Row=7,Cif="100",Contract="HD2",Reported=true},
            new Customer{Row=8,Cif="200",Contract="HD3",YellowRow=true},
            new Customer{Row=9,Cif="200",Contract="HD4",YellowRow=false},
            new Customer{Row=10,Cif="300",Contract="HD5",Reported=true},
            new Customer{Row=11,Cif="400",Contract="HD6"}
        };
        var chosen=CareLogic.UniqueCare(careData);
        Assert(chosen.Count==2 && chosen[0].Cif=="100" && chosen[1].Cif=="200", "Care group unique by CIF, not agreement count");
        Assert(!chosen.Any(x=>x.Cif=="300"),"Previously reported without promise/yellow isn't auto care");
        Assert(CareLogic.IsPromise("Hứa thanh toán",""),"AG promise flags care");
        Assert(CareLogic.IsPromise("","Call - Có hứa thanh toán"),"AP promise flags care");
        Assert(CareLogic.IsPromise("","Call - Có hứa hẹn"),"AP alternate promise flags care");
        Assert(!CareLogic.IsPromise("Không có hứa hẹn",""),"No-promise cannot enter care");
        Assert(!CareLogic.IsPromise("","Call - Không hứa thanh toán"),"No-promise AP cannot enter care");
        Assert(CareLogic.IsYellow(65535),"Manual Excel yellow highlight detected");
        Assert(CareLogic.IsYellow(0xCCF2FF),"Pastel Excel yellow highlight detected");
        Assert(!CareLogic.IsYellow(0xA9C9F8),"Peach name-column fill is not mistaken for yellow");
        Assert(!CareLogic.IsYellow(16777215),"Default white is not care highlight");
        var refSession=new ReferenceSession{Cif="100",Contract="HD1",FirstPhone="0912345678",RefPhone="0987654321",RefName="Anh A",FirstScenario=0};
        Assert(refSession.Matches("100","HD1","987654321"),"Second hangup matches reference call identity");
        Assert(!refSession.Matches("100","HD2","0987654321"),"Second hangup does not cross contracts");
        Assert(!refSession.Matches("200","HD1","0987654321"),"Second hangup does not cross CIFs");
        Assert(ReportLogic.ReferenceLine("987654321")=="CALL Số tham chiếu 0987654321 : ","Reference report prefix includes correct label");
        Assert(!ReportLogic.ReferenceHasOutcome("13/10/2026 CALL 0912345678 : Không nghe\n"+ReportLogic.ReferenceLine("0987654321"),"0987654321"),"Blank reference outcome must not be auto-inferred");
        Assert(ReportLogic.ReferenceHasOutcome("CALL Số tham chiếu 0987654321 : Người thân không nghe máy", "0987654321"),"Reference outcome manually entered and recognized");
        // Marking care must not create duplicate entries for the same CIF; the report updates all contracts.
        foreach(var c in careData.Where(x=>x.Cif=="400")){c.YellowRow=true;c.Care=true;c.Reported=true;}
        Assert(CareLogic.UniqueCare(careData).Count(x=>x.Cif=="400")==1,"Checkbox care fanout deduplicated by CIF");
        var daily=ReportLogic.MergeTodayResults(new[]{
            "12/10/2026 CALL 0911111111 : Không nghe máy.\n13/10/2026 CALL 0911111111 : Nhắn lại.",
            "13/10/2026 CALL 0911111111 : Nhắn lại."
        },"13/10/2026 CALL 0911111111 : Có hứa hẹn.",new DateTime(2026,10,13));
        Assert(!daily.Contains("12/10/2026")&&daily.Contains("Nhắn lại")&&daily.Contains("Có hứa hẹn"),"AL accumulates only the current calendar day");
        Assert(daily.Split('\n').Length==2,"AL merges duplicate same-day entries across same CIF");
        var tomorrow=ReportLogic.MergeTodayResults(new[]{daily},"14/10/2026 CALL 0911111111 : Hẹn gọi lại.",new DateTime(2026,10,14));
        Assert(tomorrow.Split('\n').Length==1&&!tomorrow.Contains("13/10/2026"),"AL resets for the next calendar day");
        var urgentData = new List<Customer>{
            new Customer {Cif="C", Row=9, YellowRow=false, NextAction=new DateTime(2026,10,14)},
            new Customer {Cif="B", Row=8, YellowRow=true, NextAction=new DateTime(2026,10,16)},
            new Customer {Cif="A", Row=7, YellowRow=true, NextAction=new DateTime(2026,10,12)},
            new Customer {Cif="D", Row=10, YellowRow=false}
        };
        var prioritized=CareSortLogic.Sort(urgentData.GroupBy(x=>x.Cif),new DateTime(2026,10,13)).Select(g=>g.Key).ToArray();
        Assert(prioritized.SequenceEqual(new[]{"A","B","C","D"}),"Manual-yellow CIFs first; nearest promise dates then undated");
        Assert(CareSortLogic.Urgent(new DateTime(2026,10,16),new DateTime(2026,10,13)),"Today plus 3 days marked urgent");
        Assert(!CareSortLogic.Urgent(new DateTime(2026,10,17),new DateTime(2026,10,13)),"Farther appointments are not marked red");
        Console.WriteLine("ALL TESTS PASSED");
    }
}