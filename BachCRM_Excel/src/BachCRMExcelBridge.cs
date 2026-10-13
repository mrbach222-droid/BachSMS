using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32;
using System.Windows.Automation;
using System.Windows.Forms;

// Companion to the previously working DienBaoCaoMB helper.
// No modification of the corporate app or telephony files; only documented Windows UI APIs.
internal sealed class BachCRMExcelBridge : Form {
    static string carePhone="",careCif="",careContract="",customerName="",referenceName="",callType="customer";
    readonly System.Windows.Forms.Timer careLaunchTimer=new System.Windows.Forms.Timer();
    int careLaunchAttempts=0;
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")] static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(NativePoint p);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h,uint flags);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
    [DllImport("user32.dll")] static extern uint SendInput(uint count,Input[] input,int size);
    [StructLayout(LayoutKind.Sequential)] struct NativePoint {public int X,Y;}
    [StructLayout(LayoutKind.Sequential)] struct Input {public uint Type; public InputUnion Data;}
    [StructLayout(LayoutKind.Explicit)] struct InputUnion {[FieldOffset(0)] public KeyInput Key;[FieldOffset(0)] public MouseInput Mouse;}
    [StructLayout(LayoutKind.Sequential)] struct KeyInput {public ushort Vk,Scan;public uint Flags,Time;public UIntPtr Extra;}
    [StructLayout(LayoutKind.Sequential)] struct MouseInput {public int Dx,Dy;public uint MouseData,Flags,Time;public UIntPtr Extra;}
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out Rect r);
    [StructLayout(LayoutKind.Sequential)] struct Rect {public int Left,Top,Right,Bottom;}
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h,int cmd);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint currentThread,uint targetThread,bool attach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool SetActiveWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    readonly System.Windows.Forms.Timer clock=new System.Windows.Forms.Timer(), calibrateTimer=new System.Windows.Forms.Timer(), inputPoll=new System.Windows.Forms.Timer(), clipboardDelay=new System.Windows.Forms.Timer();
    readonly Button hangupCalibrate=new Button();
    bool prevLeft=false,prevEnter=false,waitingPhone=false,callArmed=false,hangupWasPressed=false,dispatchPending=false;
    DateTime pendingClick=DateTime.MinValue, callArmedAt=DateTime.MinValue, dispatchAt=DateTime.MinValue;
    IntPtr pendingFpt=IntPtr.Zero;
    string pendingClipboard="";
    bool running=false, reading=false;
    DateTime lastClick=DateTime.MinValue;
    int clipboardAttempts=0, clickSequence=0;
    string clickClipboardBefore="";
    bool clickPending=false;
    readonly Button startButton=new Button(), stopButton=new Button();
    double hx=-1,hy=-1;
    int calibrationMode=0;

    readonly Button calibrate=new Button();
    IntPtr calibratedWindow=IntPtr.Zero;
    double rx=-1,ry=-1;
    int calibrateTicks=0;
    string CalibrationPath {get {var dir=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"BachCRMExcel");Directory.CreateDirectory(dir);return Path.Combine(dir,"eyebeam_calibration.txt");}}
    readonly TextBox number=new TextBox(), trace=new TextBox();
    readonly Label status=new Label(), state=new Label();
    readonly Button import=new Button(), toEyeBeam=new Button(), openHelper=new Button();
    readonly CheckBox autoPopup=new CheckBox(), autoDial=new CheckBox();
    string selectedPhone="", lastClipboard="";
    bool sawActive=false, completed=false; int idleTicks=0;
    DateTime lastDispatch=DateTime.MinValue;
    enum CallState { Unknown, Active, Idle }
    bool stateScanBusy=false, confirmedActive=false, endDispatched=false;
    int idleConfirmations=0;
    DateTime lastStateScan=DateTime.MinValue;
    string currentCallPhone="";
    // WH_MOUSE_LL runs on our own process's thread and captures very short
    // mouse clicks that a 45-ms GetAsyncKeyState poll may miss. No keystrokes,
    // screen images, call audio or other application data are collected.
    const int WH_MOUSE_LL=14,WM_LBUTTONDOWN=0x0201;
    delegate IntPtr LowLevelMouseProc(int nCode,IntPtr wParam,IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)] struct MouseEventData {
        public NativePoint Pt;public uint MouseData,Flags,Time;public UIntPtr ExtraInfo;
    }
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SetWindowsHookEx(int idHook,LowLevelMouseProc callback,IntPtr module,uint threadId);
    [DllImport("user32.dll",SetLastError=true)] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook,int nCode,IntPtr wParam,IntPtr lParam);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string module);
    LowLevelMouseProc mouseProc;IntPtr mouseHook=IntPtr.Zero;
    int eyePid=0;
    int uiaEndClickProbe=0;
    bool AutoHangupEnabled {get{return running && callArmed && !endDispatched &&
       NormalizePhone(currentCallPhone).Length>0 && (DateTime.Now-callArmedAt).TotalMilliseconds>=650;}}
    void InstallMouseWatcher(){
        try{
            mouseProc=OnMouseEvent;
            mouseHook=SetWindowsHookEx(WH_MOUSE_LL,mouseProc,GetModuleHandle(null),0);
            Log(mouseHook!=IntPtr.Zero?"Bắt sự kiện chuột EyeBeam: đã bật (không cần click giữ lâu).":"Không bật được mouse hook; vẫn còn theo dõi trạng thái và hiệu chỉnh nút đỏ.");
        }catch(Exception ex){Log("Mouse hook unavailable: "+ex.GetType().Name);}
    }
    IntPtr OnMouseEvent(int code,IntPtr wParam,IntPtr lParam){
        if(code>=0 && wParam.ToInt64()==WM_LBUTTONDOWN && AutoHangupEnabled){
            try{
                MouseEventData info=(MouseEventData)Marshal.PtrToStructure(lParam,typeof(MouseEventData));
                IntPtr window=GetAncestor(WindowFromPoint(info.Pt),2);
                uint pid=0;if(window!=IntPtr.Zero)GetWindowThreadProcessId(window,out pid);
                if(eyePid==0){var ey=EyeBeam();if(ey!=null)eyePid=ey.Id;}
                if(pid!=0 && pid==(uint)eyePid){
                    // The saved hang-up target is fast and safe to inspect inside the callback.
                    bool atHangup=IsHangupPoint(window,info.Pt);
                    NativePoint point=info.Pt;
                    if(atHangup){
                        BeginInvoke((Action)delegate{ScheduleEndCallAfterClick("Click nút đỏ EyeBeam (mouse hook)");});
                    }else if(System.Threading.Interlocked.CompareExchange(ref uiaEndClickProbe,1,0)==0){
                        // UI Automation on a worker, never inside a low-level input hook.
                        System.Threading.ThreadPool.QueueUserWorkItem(delegate{
                            bool found=false;try{found=ClickedEndCallControl(point);}catch{}
                            try{if(found && !IsDisposed && IsHandleCreated)BeginInvoke((Action)delegate{ScheduleEndCallAfterClick("EyeBeam end-call control (UIA)");});}catch{}
                            System.Threading.Interlocked.Exchange(ref uiaEndClickProbe,0);
                        });
                    }
                }
            }catch{}
        }
        return CallNextHookEx(mouseHook,code,wParam,lParam);
    }
    void ScheduleEndCallAfterClick(string source){
        if(!AutoHangupEnabled || dispatchPending)return;
        Log(source+"; đợi thao tác gác máy hoàn tất, rồi tự mở báo cáo.");
        dispatchPending=true;
        dispatchAt=DateTime.Now.AddMilliseconds(450);
    }



    [STAThread] static void Main(string[] args){
        for(int i=0;i<args.Length-1;i++){
            if(args[i]=="--phone")carePhone=args[++i];
            else if(args[i]=="--cif")careCif=args[++i];
            else if(args[i]=="--contract")careContract=args[++i];
            else if(args[i]=="--customer-name")customerName=args[++i];
            else if(args[i]=="--reference-name")referenceName=args[++i];
            else if(args[i]=="--call-type")callType=args[++i];
        }
        if(!System.Text.RegularExpressions.Regex.IsMatch(carePhone,@"^0[0-9]{9}$") ||
           !System.Text.RegularExpressions.Regex.IsMatch(careCif,@"^[0-9]{1,30}$") ||
           !System.Text.RegularExpressions.Regex.IsMatch(careContract,@"^[\p{L}0-9_./\-]{1,60}$")){
            MessageBox.Show("Thiếu thông tin CIF/HĐ/SĐT hợp lệ. Hãy bấm TÁC ĐỘNG trong CRM.");return;
        }
        if(customerName.Length>180||referenceName.Length>180||
           (callType!="customer"&&callType!="reference")){
            MessageBox.Show("Tham số tên người được liên lạc không hợp lệ.");return;
        }
        // Human-readable names only: no data sent to any remote service.
        customerName=customerName.Replace("\r", " ").Replace("\n", " ");
        referenceName=referenceName.Replace("\r", " ").Replace("\n", " ");
        SetProcessDPIAware(); Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new BachCRMExcelBridge());
    }
    BachCRMExcelBridge(){
        Text="Bách CRM Excel | CALL Bridge";StartPosition=FormStartPosition.Manual;
        ClientSize=new Size(360,194);MinimumSize=new Size(376,233);MaximumSize=new Size(376,233);
        Font=new Font("Segoe UI",9);BackColor=Color.FromArgb(246,248,252);
        FormBorderStyle=FormBorderStyle.FixedSingle;MaximizeBox=false;
        ShowInTaskbar=true;
        var screen=Screen.PrimaryScreen.WorkingArea;
        Location=new Point(Math.Max(0,screen.Right-Width-20),Math.Max(0,screen.Bottom-Height-64));
        var bar=new Panel{BackColor=Color.FromArgb(27,44,74),Dock=DockStyle.Top,Height=35};Controls.Add(bar);
        var h=new Label{Text="BÁCH CRM EXCEL  /  EYEBeAM",Left=13,Top=9,Width=290,Height=20,
            ForeColor=Color.White,Font=new Font("Segoe UI",10,FontStyle.Bold)};bar.Controls.Add(h);
        var contact=new Label{Text=callType=="reference"?"THAM CHIẾU: "+(String.IsNullOrWhiteSpace(referenceName)?"Chưa có tên":referenceName):
            "KH: "+(String.IsNullOrWhiteSpace(customerName)?"Chưa có tên":customerName),Left=13,Top=41,Width=334,Height=24,
            ForeColor=Color.FromArgb(22,60,96),Font=new Font("Segoe UI",9,FontStyle.Bold),AutoEllipsis=true};
        contact.BorderStyle=BorderStyle.None;
        var n=new Label{Text=callType=="reference"?"SỐ ĐIỆN THOẠI THAM CHIẾU":"SỐ ĐIỆN THOẠI KHÁCH HÀNG",Left=13,Top=68,Width=330,Height=17,
            ForeColor=Color.FromArgb(92,107,130),Font=new Font("Segoe UI",8,FontStyle.Bold)};
        number.SetBounds(13,89,334,31);number.Font=new Font("Segoe UI",13,FontStyle.Bold);
        number.ReadOnly=true;number.BackColor=Color.White;number.ForeColor=Color.FromArgb(22,42,73);
        number.BorderStyle=BorderStyle.FixedSingle;number.ShortcutsEnabled=true;
        startButton.Text="BÁO CÁO SAU GÁC MÁY";startButton.SetBounds(13,130,181,28);
        startButton.BackColor=Color.FromArgb(26,112,205);startButton.ForeColor=Color.White;
        startButton.FlatStyle=FlatStyle.Flat;startButton.FlatAppearance.BorderSize=0;
        stopButton.Text="DỪNG / THOÁT";stopButton.SetBounds(201,130,146,28);
        stopButton.FlatStyle=FlatStyle.Flat;stopButton.BackColor=Color.FromArgb(231,236,243);
        stopButton.FlatAppearance.BorderSize=0;
        status.Text="Đang khởi động tự động...";status.SetBounds(13,169,334,18);
        status.ForeColor=Color.FromArgb(64,89,118);status.Font=new Font("Segoe UI",8);
        status.AutoEllipsis=true;
        Controls.AddRange(new Control[]{contact,n,number,startButton,stopButton,status});
        var menu=new ContextMenuStrip();
        menu.Items.Add("THỬ điền lại số đang hiển thị vào EyeBeam",null,(sender,e)=>MoveNumberToEyeBeam());
        
        menu.Items.Add("Mở báo cáo Excel (dự phòng)",null,(sender,e)=>ManualFinishReport());
        menu.Items.Add("Hiệu chỉnh nút ĐỎ gác máy EyeBeam (chỉ một lần)",null,(sender,e)=>StartCalibration(2));
        menu.Items.Add("Kiểm tra trạng thái EyeBeam",null,(sender,e)=>ProbeState());
        menu.Items.Add("Hiện nhật ký chẩn đoán",null,(sender,e)=>ShowLog());
        menu.Items.Add("Chọn đường dẫn EyeBeam",null,(sender,e)=>ChooseEyeBeamPath());
        ContextMenuStrip=menu;
        number.TextChanged+=delegate {string v=NormalizePhone(number.Text);if(v!=selectedPhone){selectedPhone=v;sawActive=false;completed=false;idleTicks=0;confirmedActive=false;endDispatched=false;idleConfirmations=0;callArmed=false;currentCallPhone=v;}};
        startButton.Click+=delegate {ManualFinishReport();};
        stopButton.Click+=delegate {running=false;careLaunchTimer.Stop();inputPoll.Stop();clipboardDelay.Stop();clock.Stop();Close();};
        calibrateTimer.Interval=1000;calibrateTimer.Tick+=delegate{calibrateTicks--;if(calibrateTicks==0){calibrateTimer.Stop();FinishCalibration();}else status.Text="Hiệu chỉnh "+(calibrationMode==1?"ô số":"nút đỏ")+"... "+calibrateTicks+" giây";};
        try {var parts=File.ReadAllText(CalibrationPath).Split('|');rx=double.Parse(parts[0],System.Globalization.CultureInfo.InvariantCulture);ry=double.Parse(parts[1],System.Globalization.CultureInfo.InvariantCulture);if(parts.Length>=4){hx=double.Parse(parts[2],System.Globalization.CultureInfo.InvariantCulture);hy=double.Parse(parts[3],System.Globalization.CultureInfo.InvariantCulture);}}catch{}
        clock.Interval=450;clock.Tick+=delegate{if(running){Tick();if(EyeBeam()==null && (DateTime.Now-lastEyeSearch).TotalSeconds>10){lastEyeSearch=DateTime.Now;EnsureEyeBeam();}}};
        clipboardDelay.Interval=45; clipboardDelay.Tick+=CheckClickedClipboard;
        inputPoll.Interval=45;inputPoll.Tick+=delegate{if(running)PollInputs();};
        Log("Bách CRM Excel v1.0: tự mở báo cáo khi nhận đúng nút gác máy hoặc trạng thái Active -> Idle. Skin riêng cần hiệu chỉnh nút đỏ một lần; không tự đoán vùng click.");
        careLaunchTimer.Interval=350;
        careLaunchTimer.Tick+=delegate{
            careLaunchAttempts++;
            var eye=EyeBeam();
            if(eye!=null && eye.MainWindowHandle!=IntPtr.Zero){
                // Try a few times if the EyeBeam skin is still loading.
                MoveNumberToEyeBeam();
                if(status.Text.StartsWith("Đã kiểm tra số")||status.Text.StartsWith("Đã gửi phím số")){
                    careLaunchTimer.Stop();return;
                }
            }
            if(careLaunchAttempts>=32){careLaunchTimer.Stop();
                Log("Timeout waiting for EyeBeam dial field. Use right click > retry input.");
                status.Text="EyeBeam chưa sẵn sàng. Chuột phải để thử điền lại.";
            }
        };
        Shown+=delegate{BeginInvoke((Action)delegate{
            BeginWatch();
            number.Text=NormalizePhone(carePhone);
            currentCallPhone=number.Text;
            careLaunchTimer.Start();
        });};
    }
    protected override void OnFormClosed(FormClosedEventArgs e){
        running=false;
        if(mouseHook!=IntPtr.Zero){UnhookWindowsHookEx(mouseHook);mouseHook=IntPtr.Zero;}
        mouseProc=null;
        base.OnFormClosed(e);
    }
    void ShowLog(){
        Form f=new Form{Text="Bách CRM - Nhật ký",Width=780,Height=450,StartPosition=FormStartPosition.CenterParent};
        TextBox t=new TextBox{Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Both,Dock=DockStyle.Fill,Font=new Font("Consolas",10),Text=trace.Text};
        f.Controls.Add(t);f.Show(this);
    }
    string EyePath { get { return Path.Combine(Path.GetDirectoryName(CalibrationPath),"eyebeam_path.txt"); } }
    DateTime lastEyeLaunch=DateTime.MinValue;
    DateTime lastEyeSearch=DateTime.MinValue;
    bool eyeMissingLogged=false;
    static void AddEyePath(System.Collections.Generic.List<string> paths,string candidate){
        if(String.IsNullOrWhiteSpace(candidate))return;
        candidate=Environment.ExpandEnvironmentVariables(candidate.Trim().Trim('\"'));
        if(Directory.Exists(candidate))candidate=Path.Combine(candidate,"eyeBeam.exe");
        if(!Path.GetFileName(candidate).Equals("eyeBeam.exe",StringComparison.OrdinalIgnoreCase))return;
        if(!paths.Exists(x=>String.Equals(x,candidate,StringComparison.OrdinalIgnoreCase)))paths.Add(candidate);
    }
    static void FromUninstall(System.Collections.Generic.List<string> paths,RegistryKey hive,RegistryView view){
        try{using(var baseKey=RegistryKey.OpenBaseKey(hive==Registry.LocalMachine?RegistryHive.LocalMachine:RegistryHive.CurrentUser,view))
        using(var root=baseKey.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")){
            if(root==null)return;
            foreach(string key in root.GetSubKeyNames())try{using(var entry=root.OpenSubKey(key)){
                var name=Convert.ToString(entry.GetValue("DisplayName"));
                if(name.IndexOf("eyebeam",StringComparison.OrdinalIgnoreCase)<0 && name.IndexOf("counterpath",StringComparison.OrdinalIgnoreCase)<0)continue;
                AddEyePath(paths,Convert.ToString(entry.GetValue("InstallLocation")));
                string icon=Convert.ToString(entry.GetValue("DisplayIcon"));
                if(icon.IndexOf("eyeBeam.exe",StringComparison.OrdinalIgnoreCase)>=0){int i=icon.IndexOf(".exe",StringComparison.OrdinalIgnoreCase);AddEyePath(paths,icon.Substring(0,i+4));}
            }}catch{}
        }}catch{}
    }
    static void FromShortcuts(System.Collections.Generic.List<string> paths,string folder){
        try{
            if(!Directory.Exists(folder))return;
            var shell=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
            foreach(var link in Directory.GetFiles(folder,"*.lnk",SearchOption.AllDirectories)){
                if(link.IndexOf("eyebeam",StringComparison.OrdinalIgnoreCase)<0 && link.IndexOf("counterpath",StringComparison.OrdinalIgnoreCase)<0)continue;
                try{
                    object shortcut=shell.GetType().InvokeMember("CreateShortcut",System.Reflection.BindingFlags.InvokeMethod,null,shell,new object[]{link});
                    object path=shortcut.GetType().InvokeMember("TargetPath",System.Reflection.BindingFlags.GetProperty,null,shortcut,null);
                    AddEyePath(paths,Convert.ToString(path));
                }catch{}
            }
        }catch{}
    }
    void ChooseEyeBeamPath(){
        using(var d=new OpenFileDialog{Filter="EyeBeam (eyeBeam.exe)|eyeBeam.exe|Executable (*.exe)|*.exe",Title="Chọn eyeBeam.exe đã cài"})
            if(d.ShowDialog(this)==DialogResult.OK){
                if(!Path.GetFileName(d.FileName).Equals("eyeBeam.exe",StringComparison.OrdinalIgnoreCase)){
                    MessageBox.Show(this,"Hãy chọn đúng tệp eyeBeam.exe của chương trình gọi điện.");return;
                }
                File.WriteAllText(EyePath,d.FileName);lastEyeLaunch=DateTime.MinValue;
                Log("Đã lưu đường dẫn EyeBeam và thử mở ngay.");EnsureEyeBeam();
            }
    }
    bool EnsureEyeBeam(){
        // Never alter the proven v0.9 FPT-to-EyeBeam number-transfer path.
        if(EyeBeam()!=null){eyeMissingLogged=false;return true;}
        if((DateTime.Now-lastEyeLaunch).TotalSeconds<12)return false;
        var guesses=new System.Collections.Generic.List<string>();
        try{if(File.Exists(EyePath))AddEyePath(guesses,File.ReadAllText(EyePath));}catch{}
        foreach(var baseDir in new[]{Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)}){
            foreach(var sub in new[]{@"CounterPath\eyeBeam",@"CounterPath\eyeBeam 1.5",@"CounterPath\EyeBeam", "eyeBeam",@"CounterPath\eyeBeam 1.1"})AddEyePath(guesses,Path.Combine(baseDir,sub));
        }
        foreach(var hive in new[]{Registry.CurrentUser,Registry.LocalMachine}){
            try{using(var key=hive.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\eyeBeam.exe"))if(key!=null)AddEyePath(guesses,Convert.ToString(key.GetValue("")));}catch{}
            FromUninstall(guesses,hive,RegistryView.Registry32);
            FromUninstall(guesses,hive,RegistryView.Registry64);
        }
        FromShortcuts(guesses,Environment.GetFolderPath(Environment.SpecialFolder.StartMenu));
        FromShortcuts(guesses,Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu));
        foreach(var file in guesses){
            try{
                if(!File.Exists(file))continue;
                lastEyeLaunch=DateTime.Now;
                Process.Start(new ProcessStartInfo{FileName=file,WorkingDirectory=Path.GetDirectoryName(file),UseShellExecute=true});
                Log("Đã tự mở EyeBeam từ thư mục cài đặt.");
                try{File.WriteAllText(EyePath,file);}catch{}
                status.Text="Đang mở EyeBeam · theo dõi số FPT đã bật.";
                eyeMissingLogged=false;return true;
            }catch(Exception ex){Log("Không mở được EyeBeam: "+ex.GetType().Name);}
        }
        if(!eyeMissingLogged){Log("Chưa tìm thấy eyeBeam.exe trong thư mục cài đặt/Start Menu/Registry. Có thể chọn đường dẫn một lần bằng chuột phải.");eyeMissingLogged=true;}
        status.Text="Đang theo dõi FPT · chưa tìm thấy EyeBeam để tự mở.";
        return false;
    }
    void BeginWatch(){
        if(running)return;
        running=true;inputPoll.Start();clock.Start();startButton.Enabled=true;
        InstallMouseWatcher();
        Log("Theo dõi cuộc gọi EyeBeam của KH đã chọn từ Excel.");
        EnsureEyeBeam();
        if(EyeBeam()!=null)status.Text="Đang theo dõi trạng thái EyeBeam cho số đã chọn.";
    }
    static string WindowTitle(IntPtr h){var s=new StringBuilder(512);if(h!=IntPtr.Zero)GetWindowText(h,s,s.Capacity);return s.ToString();}
    static string NormalizePhone(string raw){
        if(raw==null)return "";
        string p=Regex.Replace(raw.Trim(),@"[\s.()\-]", "");
        if(p.StartsWith("+84") && p.Length==12)p="0"+p.Substring(3);
        else if(p.StartsWith("84") && p.Length==11)p="0"+p.Substring(2);
        else if(Regex.IsMatch(p,@"^[35789][0-9]{8}$"))p="0"+p;
        return Regex.IsMatch(p,@"^0[0-9]{9}$")?p:"";
    }
    void Log(string msg){
        if(trace.TextLength>11000)trace.Text=trace.Text.Substring(trace.TextLength-5500);
        string entry=DateTime.Now.ToString("HH:mm:ss")+" · "+msg+Environment.NewLine;
        trace.AppendText(entry);
        try{
            string file=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"BachCRMExcel","bridge_events.log");
            var folder=Path.GetDirectoryName(file);if(!Directory.Exists(folder))Directory.CreateDirectory(folder);
            if(File.Exists(file)&&new FileInfo(file).Length>200000)File.WriteAllText(file,"",Encoding.UTF8);
            File.AppendAllText(file,entry,Encoding.UTF8);
        }catch{}
    }
    void CaptureClipboard(bool onlyWhenFpt){
        try {
            if(onlyWhenFpt&&!WindowTitle(GetForegroundWindow()).StartsWith("Quản lý nghiệp vụ",StringComparison.OrdinalIgnoreCase))return;
            if(!Clipboard.ContainsText())return;
            string source=Clipboard.GetText().Trim();
            if(onlyWhenFpt&&source==lastClipboard)return;
            string p=NormalizePhone(source);
            if(p.Length==0)return;
            lastClipboard=source;
            if(p==selectedPhone)return;
            number.Text=p;status.Text="Đã nhận số "+Mask(p)+"; chuyển sang EyeBeam rồi bấm Enter để gọi.";
            Log("Đã nhận một số điện thoại hợp lệ từ clipboard FPT.");
        }catch(System.Runtime.InteropServices.ExternalException){}catch(Exception ex){Log("Không đọc clipboard: "+ex.GetType().Name);}
    }
    static string Mask(string p){return p.Length>4?new string('*',p.Length-4)+p.Substring(p.Length-4):"****";}
    static Process EyeBeam(){
        foreach(var p in Process.GetProcesses())try {
            if(p.ProcessName.IndexOf("eyebeam",StringComparison.OrdinalIgnoreCase)>=0 && p.MainWindowHandle!=IntPtr.Zero)return p;
        }catch{} return null;
    }
    void StartCalibration(int mode){
        calibrationMode=mode;
        if(!EnsureEyeBeam())return;
        calibrateTicks=3;status.Text="Đưa chuột lên "+(mode==1?"ô số":"nút ĐỎ")+" EyeBeam trong 3 giây, KHÔNG bấm.";calibrateTimer.Start();
    }
    void FinishCalibration(){
        NativePoint p;if(!GetCursorPos(out p))return;
        IntPtr h=GetAncestor(WindowFromPoint(p),2);uint pid;
        GetWindowThreadProcessId(h,out pid);
        var ey=EyeBeam();if(ey==null||pid!=ey.Id){status.Text="Chưa xác nhận chuột đang ở cửa sổ EyeBeam. Thử lại.";return;}
        Rect r;if(!GetWindowRect(h,out r)||r.Right<=r.Left||r.Bottom<=r.Top)return;
        double cx=(p.X-r.Left)/(double)(r.Right-r.Left), cy=(p.Y-r.Top)/(double)(r.Bottom-r.Top);
        if(cx<0||cx>1||cy<0||cy>1)return;
        if(calibrationMode==1){rx=cx;ry=cy;}else{hx=cx;hy=cy;}
        File.WriteAllText(CalibrationPath,rx.ToString(System.Globalization.CultureInfo.InvariantCulture)+"|"+ry.ToString(System.Globalization.CultureInfo.InvariantCulture)+"|"+hx.ToString(System.Globalization.CultureInfo.InvariantCulture)+"|"+hy.ToString(System.Globalization.CultureInfo.InvariantCulture));
        calibratedWindow=h;status.Text="Đã hiệu chỉnh "+(calibrationMode==1?"ô số":"nút đỏ")+" EyeBeam.";
        Log("Đã cập nhật hiệu chỉnh EyeBeam, không ghi số điện thoại.");
    }
    static void Key(ushort vk){
        var a=new Input[2];a[0].Type=1;a[0].Data.Key.Vk=vk;a[1].Type=1;a[1].Data.Key.Vk=vk;a[1].Data.Key.Flags=2;
        if(SendInput(2,a,Marshal.SizeOf(typeof(Input)))!=2)throw new InvalidOperationException("KeyboardFailure");
    }
    static void PasteKeys(){
        var a=new Input[4];
        a[0].Type=a[1].Type=a[2].Type=a[3].Type=1;
        a[0].Data.Key.Vk=0x11;a[1].Data.Key.Vk=0x56;a[2].Data.Key.Vk=0x56;a[2].Data.Key.Flags=2;a[3].Data.Key.Vk=0x11;a[3].Data.Key.Flags=2;
        if(SendInput(4,a,Marshal.SizeOf(typeof(Input)))!=4)throw new InvalidOperationException("PasteFailure");
    }
    // eyeBeam's legacy dialer does not always expose the number field via UIA.
    // Calibration stores a point relative to the dialer window, not an absolute screen coordinate.
    // IMPORTANT: focus the dialer BEFORE hit-testing; the CRM window may be covering it.
    static void PressChord(ushort modifier, ushort key){
        var keys=new Input[4];
        for(int i=0;i<4;i++)keys[i].Type=1;
        keys[0].Data.Key.Vk=modifier;
        keys[1].Data.Key.Vk=key;
        keys[2].Data.Key.Vk=key; keys[2].Data.Key.Flags=2;
        keys[3].Data.Key.Vk=modifier; keys[3].Data.Key.Flags=2;
        if(SendInput(4,keys,Marshal.SizeOf(typeof(Input)))!=4)throw new InvalidOperationException("ShortcutFailed");
    }
    static void SendNumberKeys(string phone){
        // Virtual key digits work with older native applications which reject Unicode injection.
        foreach(char digit in phone){
            if(digit<'0'||digit>'9')throw new InvalidOperationException("InvalidDigit");
            Key((ushort)(0x30+(digit-'0')));
        }
    }
    bool CalibratedPaste(Process ey,string phone){
        if(rx<0||ry<0)return false;
        IntPtr h=calibratedWindow;
        uint pid=0;
        if(h!=IntPtr.Zero && IsWindow(h))GetWindowThreadProcessId(h,out pid);
        if(pid!=ey.Id)h=ey.MainWindowHandle;
        if(h==IntPtr.Zero||!IsWindow(h))throw new InvalidOperationException("EyeBeamWindowMissing");
        if(IsIconic(h))ShowWindow(h,9);
        SetForegroundWindow(h);
        BringWindowToTop(h);
        for(int n=0;n<8 && GetForegroundWindow()!=h;n++)System.Threading.Thread.Sleep(35);
        if(GetForegroundWindow()!=h)throw new InvalidOperationException("EyeBeamNotForeground");
        Rect r;if(!GetWindowRect(h,out r)||r.Right<=r.Left||r.Bottom<=r.Top)throw new InvalidOperationException("EyeBeamBoundsInvalid");
        int x=r.Left+(int)((r.Right-r.Left)*rx), y=r.Top+(int)((r.Bottom-r.Top)*ry);
        NativePoint point=new NativePoint{X=x,Y=y};
        uint underPid=0;
        var under=GetAncestor(WindowFromPoint(point),2);
        if(under!=IntPtr.Zero)GetWindowThreadProcessId(under,out underPid);
        if(underPid!=ey.Id)throw new InvalidOperationException("CalibratedPointNotEyeBeam");
        if(!SetCursorPos(x,y))throw new InvalidOperationException("CursorFailure");
        var click=new Input[2];click[0].Type=click[1].Type=0;
        click[0].Data.Mouse.Flags=0x0002;click[1].Data.Mouse.Flags=0x0004;
        if(SendInput(2,click,Marshal.SizeOf(typeof(Input)))!=2)throw new InvalidOperationException("ClickFailure");
        System.Threading.Thread.Sleep(45);
        if(GetForegroundWindow()!=h)throw new InvalidOperationException("EyeBeamLostFocus");
        // Paste first. If the older dialer doesn't expose the value, cannot claim verification.
        Clipboard.SetText(phone);
        PressChord(0x11,0x41); // Ctrl+A clears the previous number
        PasteKeys();
        status.Text="Đã gửi số sang EyeBeam; kiểm tra ô gọi trước Enter.";
        Log("Đã click vùng EyeBeam và gửi Ctrl+A, Ctrl+V; chưa xác minh nội dung ô số.");
        return true;
    }
    // No coordinates: first try Win32 native Edit controls, then UIA ValuePattern, then keyboard dial-pad fallback.
    // The fallback is best effort because some EyeBeam skins do not expose a readable number field.
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder value,int capacity);
    delegate bool EnumChildCallback(IntPtr hwnd,IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,EnumChildCallback cb,IntPtr param);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr hwnd,uint message,IntPtr wParam,string text);
    [DllImport("user32.dll")] static extern bool SetFocus(IntPtr hwnd);
    static bool EyeBeamIsForeground(Process ey){
        if(ey==null)return false;
        IntPtr foreground=GetForegroundWindow();uint pid;
        if(foreground==IntPtr.Zero)return false;
        GetWindowThreadProcessId(foreground,out pid);
        return pid==(uint)ey.Id;
    }
    bool FocusEyeBeam(Process ey){
        if(ey==null)return false;
        IntPtr h=ey.MainWindowHandle;
        if(h==IntPtr.Zero||!IsWindow(h))return false;
        if(IsIconic(h))ShowWindow(h,9);
        ShowWindow(h,5);
        SetForegroundWindow(h);
        if(EyeBeamIsForeground(ey))return true;
        // Windows may reject SetForegroundWindow on a timer callback.
        // Attach the UI thread temporarily to the current foreground thread.
        IntPtr current=GetForegroundWindow();uint unused;
        uint otherThread=current!=IntPtr.Zero?GetWindowThreadProcessId(current,out unused):0;
        uint selfThread=GetCurrentThreadId();
        if(otherThread!=0&&otherThread!=selfThread){
            bool attached=AttachThreadInput(selfThread,otherThread,true);
            try{BringWindowToTop(h);SetActiveWindow(h);SetForegroundWindow(h);}
            finally{if(attached)AttachThreadInput(selfThread,otherThread,false);}
        }
        for(int i=0;i<6&&!EyeBeamIsForeground(ey);i++)Thread.Sleep(40);
        return EyeBeamIsForeground(ey);
    }
    bool NativeEditPhone(Process ey,string phone){
        var controls=new System.Collections.Generic.List<IntPtr>();
        EnumChildWindows(ey.MainWindowHandle,delegate(IntPtr hwnd,IntPtr param){
            StringBuilder cl=new StringBuilder(128);GetClassName(hwnd,cl,cl.Capacity);
            if(cl.ToString().Equals("Edit",StringComparison.OrdinalIgnoreCase))controls.Add(hwnd);
            return true;
        },IntPtr.Zero);
        Log("EyeBeam Win32 Edit controls: "+controls.Count);
        if(controls.Count!=1)return false; // Never overwrite an unrelated field
        if(!FocusEyeBeam(ey))throw new InvalidOperationException("EyeBeamNotForeground");
        SendMessage(controls[0],0x000C,IntPtr.Zero,phone); // WM_SETTEXT
        var buffer=new StringBuilder(100);GetWindowText(controls[0],buffer,buffer.Capacity);
        if(NormalizePhone(buffer.ToString())!=phone){
            Log("Win32 Edit ignored WM_SETTEXT / readback mismatch; trying UIA/keyboard instead.");
            return false;
        }
        return true;
    }
    bool UiaEditPhone(Process ey,string phone){
        var root=AutomationElement.FromHandle(ey.MainWindowHandle);
        var editors=root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit));
        var targets=new System.Collections.Generic.List<AutomationElement>();
        foreach(AutomationElement e in editors){
            object v;if(e.Current.IsOffscreen||!e.Current.IsEnabled||!e.TryGetCurrentPattern(ValuePattern.Pattern,out v))continue;
            if(!((ValuePattern)v).Current.IsReadOnly)targets.Add(e);
        }
        Log("EyeBeam UIA editable controls: "+targets.Count);
        if(targets.Count!=1)return false;
        if(!FocusEyeBeam(ey))throw new InvalidOperationException("EyeBeamNotForeground");
        var pattern=(ValuePattern)targets[0].GetCurrentPattern(ValuePattern.Pattern);
        pattern.SetValue(phone);
        if(NormalizePhone(pattern.Current.Value)!=phone){
            Log("UIA ValuePattern readback mismatch; trying keyboard instead.");
            return false;
        }
        return true;
    }
    void KeyboardDialPhone(Process ey,string phone){
        if(!FocusEyeBeam(ey))throw new InvalidOperationException("EyeBeamNotForeground");
        // No Return / auto-dial. Send only when an EyeBeam process window owns foreground.
        if(!EyeBeamIsForeground(ey))throw new InvalidOperationException("EyeBeamLostForeground");
        PressChord(0x11,0x41);
        if(!EyeBeamIsForeground(ey))throw new InvalidOperationException("EyeBeamLostForeground");
        SendNumberKeys(phone);
        Log("Sent digits to EyeBeam window (no field readback possible). Manual visual confirmation needed.");
    }
    void MoveNumberToEyeBeam(){
        string phone=NormalizePhone(number.Text);
        if(phone.Length==0){status.Text="Chưa có số hợp lệ.";return;}
        Process ey=EyeBeam();
        if(ey==null){status.Text="Không tìm thấy EyeBeam đang mở.";Log("EyeBeamProcessMissing");return;}
        eyePid=ey.Id;
        Log("EyeBeam pid="+ey.Id+", main hwnd="+ey.MainWindowHandle.ToInt64());
        // Focusing before input matters for this skinned legacy dialer.
        try{
            if(!FocusEyeBeam(ey)){
                status.Text="Windows chưa cho chuyển sang EyeBeam (Foreground).";
                Log("EyeBeamNotForeground: cannot activate EyeBeam, skipping keyboard input.");
                return;
            }
            bool ok=false;
            try{ok=NativeEditPhone(ey,phone);}catch(Exception ex){Log("Win32 attempt: "+ex.GetType().Name+" / "+ex.Message);}
            if(!ok){try{ok=UiaEditPhone(ey,phone);}catch(Exception ex){Log("UIA attempt: "+ex.GetType().Name+" / "+ex.Message);}}
            if(ok){
                status.Text="Đã kiểm tra số ở EyeBeam: "+Mask(phone)+". Enter để gọi.";
                ArmSessionForStateDetection(phone);
                Log("Verified dial number: "+Mask(phone));return;
            }
            KeyboardDialPhone(ey,phone);
            status.Text="Đã gửi phím số vào EyeBeam; kiểm tra màn hình trước Enter.";
            ArmSessionForStateDetection(phone);
            Log("Keyboard fallback used; eyeBeam did not expose dial field for verification.");
        }catch(Exception ex){
            status.Text="EyeBeam chưa nhận số: "+ex.Message;
            Log("EyeBeam input error: "+ex.GetType().Name+" / "+ex.Message);
        }
    }

    // Polling only reads instantaneous keyboard/mouse state, never UIA on the UI thread.
    // The slow FPT inspection runs in a worker and returns by BeginInvoke.
    void PollInputs(){
        bool left=(GetAsyncKeyState(0x01)&0x8000)!=0;
        bool enter=(GetAsyncKeyState(0x0D)&0x8000)!=0;
        try{
            if(left&&!prevLeft){
                NativePoint point;if(GetCursorPos(out point)){
                    IntPtr foreground=GetForegroundWindow();
                    if(carePhone.Length==0 && WindowTitle(foreground).StartsWith("Quản lý nghiệp vụ",StringComparison.OrdinalIgnoreCase)){
                        // The corporate FPT app copies the clicked phone to clipboard.
                        // React after click, not only when clipboard changes. Repeated same-number clicks work.
                        // Do not scan every row/header with UIA on the critical path.
                        clickSequence++;
                        clickClipboardBefore=SafeClipboard();
                        clipboardAttempts=0;
                        clickPending=true;
                        clipboardDelay.Stop();
                        clipboardDelay.Start();

                    }else if(IsEyeBeamWindow(foreground) && (confirmedActive || callArmed) && !endDispatched &&
                              (DateTime.Now-callArmedAt).TotalMilliseconds>=600 &&
                              (IsHangupPoint(foreground,point) || ClickedEndCallControl(point))){
                        Log("Đã bấm điều khiển kết thúc EyeBeam; chờ trạng thái cuộc gọi xác nhận.");
                        // A labelled native end-call control is sufficient when EyeBeam does not expose call state.
                        // With accessible call state, Tick also detects the Active -> Idle transition.
                        ScheduleEndCallAfterClick("Click nút đỏ EyeBeam (dò bổ sung)");
                    }
                }
            }
            if(enter&&!prevEnter&&IsEyeBeamWindow(GetForegroundWindow())&&selectedPhone.Length>0){
                callArmed=true;callArmedAt=DateTime.Now;confirmedActive=false;endDispatched=false;idleConfirmations=0;
                currentCallPhone=NormalizePhone(number.Text);Log("Enter gọi; theo dõi trạng thái EyeBeam.");
            }
            if(dispatchPending&&DateTime.Now>=dispatchAt){dispatchPending=false;DispatchEndCall("Click nút kết thúc");}
        }catch(Exception ex){Log("Theo dõi click: "+ex.GetType().Name);}
        finally{prevLeft=left;prevEnter=enter;}
    }
    void CheckClickedClipboard(object sender,EventArgs e){
        if(!running || !clickPending){clipboardDelay.Stop();return;}
        clipboardAttempts++;
        string now=SafeClipboard();
        string p=NormalizePhone(now);
        // Allow a repeated identical number, but wait at least 90ms for FPT to process click.
        // In case a different clipboard value arrives, use it immediately.
        if(p.Length>0 && (now!=clickClipboardBefore || clipboardAttempts>=2)){
            clickPending=false;clipboardDelay.Stop();
            number.Text=p;
            Log("Đã nhận clipboard sau click FPT: "+Mask(p));
            MoveNumberToEyeBeam();
        }else if(clipboardAttempts>=10){
            clickPending=false;clipboardDelay.Stop();
            status.Text="Chưa đọc được số sau khi click FPT; hãy kiểm tra clipboard.";
            Log("Clipboard chưa có số hợp lệ sau 450ms.");
        }
    }
    static string SafeClipboardWorker(){
        string result="";
        var t=new System.Threading.Thread(delegate(){try{if(Clipboard.ContainsText())result=Clipboard.GetText().Trim();}catch{}});
        t.SetApartmentState(ApartmentState.STA);t.IsBackground=true;t.Start();t.Join(120);return result;
    }
    static bool TryReadPhoneCell(IntPtr hwnd,NativePoint point,out string phone){
        phone="";
        var root=AutomationElement.FromHandle(hwnd);
        var headers=root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.HeaderItem));
        System.Windows.Rect column=System.Windows.Rect.Empty;
        for(int i=0;i<headers.Count;i++){
            var h=headers[i];string name=h.Current.Name??"";
            if(name.IndexOf("ĐTDĐ Cá nhân",StringComparison.OrdinalIgnoreCase)<0){
                var children=h.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text));
                for(int j=0;j<children.Count;j++)if((children[j].Current.Name??"").IndexOf("ĐTDĐ Cá nhân",StringComparison.OrdinalIgnoreCase)>=0){name="ĐTDĐ Cá nhân";break;}
            }
            if(name.IndexOf("ĐTDĐ Cá nhân",StringComparison.OrdinalIgnoreCase)>=0){column=h.Current.BoundingRectangle;break;}
        }
        if(column.IsEmpty||point.X<column.Left+2||point.X>column.Right-2||point.Y<=column.Bottom+2)return false;
        var cell=AutomationElement.FromPoint(new System.Windows.Point(point.X,point.Y));
        bool inRow=false;AutomationElement cursor=cell;
        for(int depth=0;cursor!=null&&depth<12;depth++){
            if(cursor.Current.ControlType==ControlType.DataItem||cursor.Current.ControlType==ControlType.ListItem){inRow=true;break;}
            cursor=TreeWalker.ControlViewWalker.GetParent(cursor);
        }
        if(!inRow)return false;
        // Prefer the text of the clicked cell; no OCR, no scanning unrelated client data.
        var values=new System.Collections.Generic.List<string>();
        cursor=cell;
        for(int depth=0;cursor!=null&&depth<4;depth++){
            string p=NormalizePhone(cursor.Current.Name);if(p.Length>0)values.Add(p);
            var texts=cursor.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text));
            for(int j=0;j<texts.Count&&j<25;j++){
                var r=texts[j].Current.BoundingRectangle;
                if(r.Left>=column.Left-2&&r.Right<=column.Right+2&&r.Contains(new System.Windows.Point(point.X,point.Y))){
                    p=NormalizePhone(texts[j].Current.Name);if(p.Length>0)values.Add(p);
                }
            }
            if(values.Count>0)break;
            cursor=TreeWalker.ControlViewWalker.GetParent(cursor);
        }
        if(values.Count>0)phone=values[0];
        return true;
    }
    static string SafeClipboard(){try{return Clipboard.ContainsText()?Clipboard.GetText().Trim():"";}catch{return "";}}
    static bool IsEyeBeamWindow(IntPtr hwnd){var e=EyeBeam();if(e==null||hwnd==IntPtr.Zero)return false;uint pid;GetWindowThreadProcessId(hwnd,out pid);return pid==e.Id;}
    bool IsHangupPoint(IntPtr hwnd,NativePoint pt){
        if(hx<0||hy<0)return false;
        Rect r;if(!GetWindowRect(hwnd,out r))return false;
        int x=r.Left+(int)((r.Right-r.Left)*hx),y=r.Top+(int)((r.Bottom-r.Top)*hy);
        return Math.Abs(pt.X-x)<=23&&Math.Abs(pt.Y-y)<=23;
    }
    static bool PhoneColumnClicked(IntPtr hwnd,NativePoint pt){
        try{
            var root=AutomationElement.FromHandle(hwnd);
            var headers=root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.HeaderItem));
            for(int i=0;i<headers.Count;i++){
                var h=headers[i];string label=h.Current.Name.Trim();
                if(label.IndexOf("ĐTDĐ Cá nhân",StringComparison.OrdinalIgnoreCase)<0){
                    var children=h.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text));
                    bool hit=false;for(int j=0;j<children.Count;j++)if(children[j].Current.Name.IndexOf("ĐTDĐ Cá nhân",StringComparison.OrdinalIgnoreCase)>=0)hit=true;
                    if(!hit)continue;
                }
                var r=h.Current.BoundingRectangle;
                // Click must be below this exact column's header and within column's X boundaries.
                if(!r.IsEmpty && pt.X>=r.Left+2 && pt.X<=r.Right-2 && pt.Y>r.Bottom+2){
                    // Ensure click is actually on a visible row of the customer data grid.
                    var item=AutomationElement.FromPoint(new System.Windows.Point(pt.X,pt.Y));
                    for(int depth=0;item!=null&&depth<8;depth++){
                        if(item.Current.ControlType==ControlType.DataItem||item.Current.ControlType==ControlType.ListItem)return true;
                        item=TreeWalker.ControlViewWalker.GetParent(item);
                    }
                }
            }
        }catch{}return false;
    }

    static CallState ReadEyeBeamState(){
        var p=EyeBeam();if(p==null)return CallState.Unknown;
        try {
            var root=AutomationElement.FromHandle(p.MainWindowHandle);
            var list=root.FindAll(TreeScope.Descendants,new OrCondition(
                new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text),
                new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.StatusBar)));
            bool active=false,idle=false;
            for(int i=0;i<list.Count&&i<600;i++){
                string x=list[i].Current.Name.Trim();
                if(x.Equals("On the Phone",StringComparison.OrdinalIgnoreCase)||x.Equals("In Call",StringComparison.OrdinalIgnoreCase)||x.Equals("In a Call",StringComparison.OrdinalIgnoreCase)||x.Equals("Đang gọi",StringComparison.OrdinalIgnoreCase))active=true;
                if(x.Equals("Available",StringComparison.OrdinalIgnoreCase)||x.Equals("Idle",StringComparison.OrdinalIgnoreCase)||x.Equals("Ready",StringComparison.OrdinalIgnoreCase)||x.Equals("Sẵn sàng",StringComparison.OrdinalIgnoreCase))idle=true;
            }
            if(active&&!idle)return CallState.Active;
            if(idle&&!active)return CallState.Idle;
        }catch{}
        return CallState.Unknown;
    }
    // UIA inspection is performed on the thread pool, never on the WinForms UI thread.
    void ProbeState(){
        ThreadPool.QueueUserWorkItem(delegate{
            CallState value=ReadEyeBeamState();
            if(!IsDisposed && IsHandleCreated)BeginInvoke((Action)delegate{Log("EyeBeam state probe: "+value);});
        });
    }
    bool ClickedEndCallControl(NativePoint point){
        // This is a best-effort native accessibility check, NOT a hard-coded coordinate.
        // It must not inspect unrelated windows.
        try{
            AutomationElement e=AutomationElement.FromPoint(new System.Windows.Point(point.X,point.Y));
            var ey=EyeBeam();if(ey==null)return false;
            for(int i=0;i<5 && e!=null;i++){
                int pid=e.Current.ProcessId;
                if(pid!=ey.Id)return false;
                string n=(e.Current.Name??"").Trim().ToLowerInvariant();
                if(e.Current.ControlType==ControlType.Button && (n.Contains("hang up")||n.Contains("hangup")||n.Contains("end call")||n.Contains("disconnect")||n.Contains("kết thúc")))return true;
                e=TreeWalker.ControlViewWalker.GetParent(e);
            }
        }catch{}return false;
    }
    void ArmSessionForStateDetection(string phone){
        if(endDispatched)return;
        currentCallPhone=phone;
        callArmed=true;
        callArmedAt=DateTime.Now;
        // Don't mark it a completed call unless EyeBeam confirms active or the user clicks hangup.
        Log("Số đã chuyển sang EyeBeam; đang chờ trạng thái gọi hoặc thao tác nút ĐỎ.");
    }
    void ManualFinishReport(){
        if(NormalizePhone(currentCallPhone).Length==0){
            MessageBox.Show(this,"Chưa có SĐT cho lần tác động này.");return;
        }
        if(MessageBox.Show(this,"Đã kết thúc cuộc gọi với số đang chọn?\n\nChương trình sẽ mở bảng TH1–TH6, CHƯA tự lưu Excel.","Xác nhận kết thúc cuộc gọi",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;
        DispatchEndCall("Người dùng xác nhận kết thúc");
    }
    void DispatchEndCall(string reason){
        if(endDispatched || NormalizePhone(currentCallPhone).Length==0)return;
        endDispatched=true;callArmed=false;confirmedActive=false;idleConfirmations=0;
        Log("Cuộc gọi kết thúc ("+reason+"); tự mở báo cáo Excel.");
        if(LaunchHelper()){
            // End-call event belongs to exactly one call; do not leave stale Bridge listeners active.
            if(IsHandleCreated)BeginInvoke((Action)delegate{Close();});
        }else{
            // Keep this window available so the user can retry if request delivery fails.
            endDispatched=false;callArmed=true;
        }
    }
    void Tick(){
        if(!running || stateScanBusy || (DateTime.Now-lastStateScan).TotalMilliseconds<350)return;
        lastStateScan=DateTime.Now;
        if(!callArmed && !confirmedActive)return;
        stateScanBusy=true;
        ThreadPool.QueueUserWorkItem(delegate{
            CallState value=ReadEyeBeamState();
            if(IsDisposed || !IsHandleCreated)return;
            try{BeginInvoke((Action)delegate{
                stateScanBusy=false;
                if(!running || endDispatched)return;
                if(value==CallState.Active){
                    if(!confirmedActive)Log("EyeBeam xác nhận trạng thái đang gọi.");
                    confirmedActive=true;idleConfirmations=0;
                }else if(value==CallState.Idle && confirmedActive){
                    idleConfirmations++;
                    if(idleConfirmations>=2)DispatchEndCall("EyeBeam Active -> Idle");
                }else if(value==CallState.Unknown){idleConfirmations=0;}
            });}catch{stateScanBusy=false;}
        });
    }
    bool LaunchHelper(){
        string phone=NormalizePhone(number.Text);
        if(phone.Length==0){MessageBox.Show(this,"Không có số hợp lệ để mở báo cáo Excel.");return false;}
        if((DateTime.Now-lastDispatch).TotalSeconds<3)return false;
        try {
            string dir=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"BachCRMExcel","requests");
            Directory.CreateDirectory(dir);
            string data=careCif+"\n"+careContract+"\n"+phone+"\n"+DateTime.UtcNow.Ticks.ToString(System.Globalization.CultureInfo.InvariantCulture);
            byte[] protectedData=System.Security.Cryptography.ProtectedData.Protect(Encoding.UTF8.GetBytes(data),null,System.Security.Cryptography.DataProtectionScope.CurrentUser);
            File.WriteAllBytes(Path.Combine(dir,Guid.NewGuid().ToString("N")+".req"),protectedData);
            lastDispatch=DateTime.Now;
            status.Text="Đã chuyển sự kiện gác máy; mở mẫu TH trên CRM Excel.";
            Log("Gửi yêu cầu báo cáo Excel cho đúng CIF + HĐ. Không tự ghi báo cáo.");
            return true;
        }catch(Exception ex){status.Text="Không gửi được báo cáo Excel: "+ex.Message;Log("Queue report failed: "+ex.Message);return false;}
    }

}