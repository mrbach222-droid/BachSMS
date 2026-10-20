using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Xml;

[assembly: System.Reflection.AssemblyTitle("BachCRMSync")]
[assembly: System.Reflection.AssemblyProduct("Bách CRM Sync")]
[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("1.0.0.0")]

namespace BachCRMSync
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }

    internal sealed class MainForm : Form
    {
        private readonly SyncStore _store;
        private readonly LocalSyncServer _server;
        private readonly BindingList<CustomerRow> _rows = new BindingList<CustomerRow>();

        private Label _serverState;
        private Label _addressLabel;
        private Label _codeLabel;
        private Label _countsLabel;
        private TextBox _excelPath;
        private TextBox _messageTemplate;
        private TextBox _log;
        private DataGridView _grid;
        private Button _startButton;
        private Button _sendButton;
        private System.Windows.Forms.Timer _timer;

        public MainForm()
        {
            Text = "BÁCH CRM SYNC · iPhone";
            StartPosition = FormStartPosition.CenterScreen;
            MinimumSize = new Size(1040, 680);
            Size = new Size(1180, 760);
            Font = new Font("Segoe UI", 9F);
            BackColor = Color.FromArgb(244, 247, 246);

            _store = new SyncStore(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "BachCRMSyncData"));
            _server = new LocalSyncServer(_store, 8765);
            _server.Log += AppendLog;
            _server.Changed += RefreshStatusSafe;

            BuildUi();
            LoadDefaultExcelPath();
            StartServer();

            _timer = new System.Windows.Forms.Timer();
            _timer.Interval = 1500;
            _timer.Tick += delegate { RefreshStatus(); };
            _timer.Start();

            FormClosing += delegate
            {
                if (_timer != null) _timer.Stop();
                _server.Dispose();
            };
        }

        private void BuildUi()
        {
            var root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.Padding = new Padding(16);
            root.RowCount = 4;
            root.ColumnCount = 1;
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 116));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 54));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 118));
            Controls.Add(root);

            var header = new Panel();
            header.Dock = DockStyle.Fill;
            header.BackColor = Color.White;
            header.Padding = new Padding(18, 14, 18, 12);
            root.Controls.Add(header, 0, 0);

            var title = new Label();
            title.Text = "Bách CRM Sync";
            title.Font = new Font("Segoe UI", 20F, FontStyle.Bold);
            title.ForeColor = Color.FromArgb(20, 58, 52);
            title.AutoSize = true;
            title.Location = new Point(18, 12);
            header.Controls.Add(title);

            var subtitle = new Label();
            subtitle.Text = "Kết nối Bách CRM Windows với Bách SMS trên iPhone";
            subtitle.ForeColor = Color.FromArgb(90, 108, 104);
            subtitle.AutoSize = true;
            subtitle.Location = new Point(21, 52);
            header.Controls.Add(subtitle);

            _serverState = new Label();
            _serverState.AutoSize = true;
            _serverState.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
            _serverState.Location = new Point(22, 79);
            header.Controls.Add(_serverState);

            _addressLabel = new Label();
            _addressLabel.AutoSize = true;
            _addressLabel.Font = new Font("Consolas", 9.5F, FontStyle.Bold);
            _addressLabel.ForeColor = Color.FromArgb(20, 105, 160);
            _addressLabel.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            _addressLabel.Location = new Point(565, 18);
            header.Controls.Add(_addressLabel);

            _codeLabel = new Label();
            _codeLabel.Text = "MÃ CRM: " + _store.Data.PairingCode;
            _codeLabel.AutoSize = true;
            _codeLabel.Font = new Font("Segoe UI", 18F, FontStyle.Bold);
            _codeLabel.ForeColor = Color.FromArgb(18, 122, 94);
            _codeLabel.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            _codeLabel.Location = new Point(565, 48);
            header.Controls.Add(_codeLabel);

            _countsLabel = new Label();
            _countsLabel.AutoSize = true;
            _countsLabel.ForeColor = Color.FromArgb(90, 108, 104);
            _countsLabel.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            _countsLabel.Location = new Point(568, 86);
            header.Controls.Add(_countsLabel);

            header.Resize += delegate
            {
                _addressLabel.Left = Math.Max(470, header.ClientSize.Width - _addressLabel.Width - 22);
                _codeLabel.Left = Math.Max(470, header.ClientSize.Width - _codeLabel.Width - 22);
                _countsLabel.Left = Math.Max(470, header.ClientSize.Width - _countsLabel.Width - 22);
            };

            var filePanel = new TableLayoutPanel();
            filePanel.Dock = DockStyle.Fill;
            filePanel.Padding = new Padding(0, 8, 0, 4);
            filePanel.ColumnCount = 5;
            filePanel.RowCount = 1;
            filePanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 76));
            filePanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            filePanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92));
            filePanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92));
            filePanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 108));
            root.Controls.Add(filePanel, 0, 1);

            var excelLabel = new Label();
            excelLabel.Text = "File Excel";
            excelLabel.Dock = DockStyle.Fill;
            excelLabel.TextAlign = ContentAlignment.MiddleLeft;
            excelLabel.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
            filePanel.Controls.Add(excelLabel, 0, 0);

            _excelPath = new TextBox();
            _excelPath.Dock = DockStyle.Fill;
            _excelPath.Margin = new Padding(0, 3, 8, 3);
            filePanel.Controls.Add(_excelPath, 1, 0);

            var browse = NewButton("Chọn file", Color.FromArgb(230, 238, 235), Color.FromArgb(20, 58, 52));
            browse.Click += delegate { BrowseExcel(); };
            filePanel.Controls.Add(browse, 2, 0);

            var load = NewButton("Nạp lại", Color.FromArgb(224, 239, 250), Color.FromArgb(20, 105, 160));
            load.Click += delegate { LoadExcel(); };
            filePanel.Controls.Add(load, 3, 0);

            _startButton = NewButton("Dừng kết nối", Color.FromArgb(232, 246, 240), Color.FromArgb(18, 122, 94));
            _startButton.Click += delegate
            {
                if (_server.IsRunning) StopServer(); else StartServer();
            };
            filePanel.Controls.Add(_startButton, 4, 0);

            _grid = new DataGridView();
            _grid.Dock = DockStyle.Fill;
            _grid.BackgroundColor = Color.White;
            _grid.BorderStyle = BorderStyle.None;
            _grid.AutoGenerateColumns = false;
            _grid.AllowUserToAddRows = false;
            _grid.AllowUserToDeleteRows = false;
            _grid.MultiSelect = true;
            _grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            _grid.RowHeadersVisible = false;
            _grid.AutoSizeRowsMode = DataGridViewAutoSizeRowsMode.AllCells;
            _grid.ColumnHeadersHeight = 34;
            _grid.RowTemplate.Height = 31;
            _grid.DataSource = _rows;
            AddColumns();
            root.Controls.Add(_grid, 0, 2);

            var bottom = new TableLayoutPanel();
            bottom.Dock = DockStyle.Fill;
            bottom.Padding = new Padding(0, 8, 0, 0);
            bottom.ColumnCount = 3;
            bottom.RowCount = 2;
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 61));
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 23));
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 16));
            bottom.RowStyles.Add(new RowStyle(SizeType.Absolute, 70));
            bottom.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.Controls.Add(bottom, 0, 3);

            _messageTemplate = new TextBox();
            _messageTemplate.Multiline = true;
            _messageTemplate.Dock = DockStyle.Fill;
            _messageTemplate.Text = "Kính gửi {ten}, đề nghị anh/chị kiểm tra và thực hiện nghĩa vụ thanh toán theo lịch đã trao đổi. Nếu đã hoàn tất, vui lòng bỏ qua tin nhắn này.";
            _messageTemplate.ScrollBars = ScrollBars.Vertical;
            bottom.Controls.Add(_messageTemplate, 0, 0);

            var selectAll = NewButton("Chọn tất cả", Color.FromArgb(230, 238, 235), Color.FromArgb(20, 58, 52));
            selectAll.Margin = new Padding(8, 0, 4, 0);
            selectAll.Click += delegate
            {
                foreach (CustomerRow row in _rows) row.Selected = true;
                _grid.Refresh();
            };
            bottom.Controls.Add(selectAll, 1, 0);

            _sendButton = NewButton("GỬI SANG IPHONE", Color.FromArgb(18, 122, 94), Color.White);
            _sendButton.Margin = new Padding(4, 0, 0, 0);
            _sendButton.Font = new Font("Segoe UI", 9.5F, FontStyle.Bold);
            _sendButton.Click += delegate { QueueSelected(); };
            bottom.Controls.Add(_sendButton, 2, 0);

            _log = new TextBox();
            _log.Dock = DockStyle.Fill;
            _log.ReadOnly = true;
            _log.BorderStyle = BorderStyle.None;
            _log.BackColor = Color.FromArgb(244, 247, 246);
            _log.ForeColor = Color.FromArgb(90, 108, 104);
            bottom.SetColumnSpan(_log, 3);
            bottom.Controls.Add(_log, 0, 1);
        }

        private void AddColumns()
        {
            var choose = new DataGridViewCheckBoxColumn();
            choose.DataPropertyName = "Selected";
            choose.HeaderText = "Chọn";
            choose.Width = 52;
            _grid.Columns.Add(choose);

            AddTextColumn("Cif", "CIF", 105);
            AddTextColumn("Contract", "Số HĐ", 125);
            AddTextColumn("Name", "Tên khách hàng", 220);
            AddTextColumn("Phone", "SĐT", 125);
            AddTextColumn("StatusText", "Trạng thái SMS", 145);

            var source = new DataGridViewTextBoxColumn();
            source.DataPropertyName = "SourceRow";
            source.HeaderText = "Dòng Excel";
            source.AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill;
            source.MinimumWidth = 80;
            _grid.Columns.Add(source);
        }

        private void AddTextColumn(string property, string title, int width)
        {
            var column = new DataGridViewTextBoxColumn();
            column.DataPropertyName = property;
            column.HeaderText = title;
            column.Width = width;
            column.ReadOnly = true;
            _grid.Columns.Add(column);
        }

        private static Button NewButton(string text, Color back, Color fore)
        {
            var button = new Button();
            button.Text = text;
            button.Dock = DockStyle.Fill;
            button.FlatStyle = FlatStyle.Flat;
            button.FlatAppearance.BorderSize = 0;
            button.BackColor = back;
            button.ForeColor = fore;
            button.Cursor = Cursors.Hand;
            return button;
        }

        private void LoadDefaultExcelPath()
        {
            var pathFile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "excel_path.txt");
            if (File.Exists(pathFile))
            {
                _excelPath.Text = File.ReadAllText(pathFile, Encoding.UTF8)
                    .Trim().Trim('"');
            }
            if (!String.IsNullOrWhiteSpace(_excelPath.Text) && File.Exists(_excelPath.Text))
            {
                LoadExcel();
            }
            else
            {
                AppendLog("Chọn file Excel đang dùng trong Bách CRM.");
            }
        }

        private void BrowseExcel()
        {
            using (var dialog = new OpenFileDialog())
            {
                dialog.Filter = "Excel Workbook (*.xlsx)|*.xlsx";
                dialog.Title = "Chọn file Excel của Bách CRM";
                if (dialog.ShowDialog(this) == DialogResult.OK)
                {
                    _excelPath.Text = dialog.FileName;
                    LoadExcel();
                }
            }
        }

        private void LoadExcel()
        {
            var path = _excelPath.Text.Trim().Trim('"');
            if (!File.Exists(path))
            {
                MessageBox.Show(this, "Không tìm thấy file Excel.", "Bách CRM Sync",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            try
            {
                Cursor = Cursors.WaitCursor;
                var rows = XlsxReader.ReadCustomers(path);
                _rows.RaiseListChangedEvents = false;
                _rows.Clear();
                foreach (var row in rows)
                {
                    row.StatusText = _store.FindLatestStatus(row.Cif, row.Contract, row.Phone);
                    _rows.Add(row);
                }
                _rows.RaiseListChangedEvents = true;
                _rows.ResetBindings();
                File.WriteAllText(
                    Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "excel_path.txt"),
                    path,
                    new UTF8Encoding(false));
                AppendLog("Đã nạp " + rows.Count + " khách từ Excel. File chỉ được đọc, không ghi sửa.");
            }
            catch (Exception ex)
            {
                AppendLog("Lỗi đọc Excel: " + ex.Message);
                MessageBox.Show(this, ex.Message, "Không đọc được Excel",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                Cursor = Cursors.Default;
            }
        }

        private void QueueSelected()
        {
            _grid.EndEdit();
            var selected = _rows.Where(delegate(CustomerRow row) { return row.Selected; }).ToList();
            if (selected.Count == 0)
            {
                MessageBox.Show(this, "Hãy tích chọn ít nhất một khách.", "Bách CRM Sync",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            var template = _messageTemplate.Text.Trim();
            if (template.Length == 0)
            {
                MessageBox.Show(this, "Nội dung tin nhắn đang trống.", "Bách CRM Sync",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            var added = 0;
            foreach (var row in selected)
            {
                var message = template
                    .Replace("{ten}", String.IsNullOrWhiteSpace(row.Name) ? "anh/chị" : row.Name)
                    .Replace("{cif}", row.Cif ?? "")
                    .Replace("{hopdong}", row.Contract ?? "");
                if (_store.Queue(row, message)) added++;
                row.Selected = false;
                row.StatusText = "Chờ iPhone nhận";
            }
            _grid.Refresh();
            AppendLog("Đã giao " + added + " khách sang hàng chờ iPhone; bỏ qua " +
                      (selected.Count - added) + " mục trùng đang chờ.");
            RefreshStatus();
        }

        private void StartServer()
        {
            try
            {
                _server.Start();
                _startButton.Text = "Dừng kết nối";
                _serverState.Text = "● ĐANG KẾT NỐI";
                _serverState.ForeColor = Color.FromArgb(18, 122, 94);
                _addressLabel.Text = "Địa chỉ nhập trên iPhone: " + NetworkAddress();
                AppendLog("Máy chủ Sync đã chạy. Nếu Windows hỏi, chọn Cho phép trên mạng riêng.");
            }
            catch (Exception ex)
            {
                _serverState.Text = "● KHÔNG KHỞI ĐỘNG ĐƯỢC";
                _serverState.ForeColor = Color.Firebrick;
                _startButton.Text = "Bắt đầu";
                AppendLog("Lỗi mở kết nối: " + ex.Message);
            }
        }

        private void StopServer()
        {
            _server.Stop();
            _startButton.Text = "Bắt đầu";
            _serverState.Text = "● ĐÃ DỪNG";
            _serverState.ForeColor = Color.DarkOrange;
            AppendLog("Đã dừng máy chủ Sync.");
        }

        private string NetworkAddress()
        {
            var ip = LocalNetwork.GetPreferredIPv4();
            return "http://" + ip + ":8765";
        }

        private void RefreshStatusSafe()
        {
            if (IsDisposed) return;
            if (InvokeRequired)
            {
                BeginInvoke(new Action(RefreshStatus));
            }
            else
            {
                RefreshStatus();
            }
        }

        private void RefreshStatus()
        {
            var snapshot = _store.Snapshot();
            _countsLabel.Text = "Thiết bị: " + snapshot.Devices.Count +
                "  ·  Chờ: " + snapshot.Jobs.Count(delegate(SyncJob j) { return j.Status == "pending"; }) +
                "  ·  Đã gửi: " + snapshot.Jobs.Count(delegate(SyncJob j) { return j.Status == "confirmed_sent"; });

            foreach (var row in _rows)
            {
                row.StatusText = _store.FindLatestStatus(row.Cif, row.Contract, row.Phone);
            }
            _grid.Refresh();
        }

        private void AppendLog(string message)
        {
            if (IsDisposed) return;
            if (InvokeRequired)
            {
                BeginInvoke(new Action<string>(AppendLog), message);
                return;
            }
            _log.Text = DateTime.Now.ToString("HH:mm:ss") + "  " + message;
        }
    }

    [DataContract]
    internal sealed class StoreData
    {
        [DataMember(Name = "pairing_code")]
        public string PairingCode { get; set; }

        [DataMember(Name = "devices")]
        public List<PairedDevice> Devices { get; set; }

        [DataMember(Name = "jobs")]
        public List<SyncJob> Jobs { get; set; }

        public static StoreData Create()
        {
            return new StoreData
            {
                PairingCode = RandomCode(),
                Devices = new List<PairedDevice>(),
                Jobs = new List<SyncJob>()
            };
        }

        private static string RandomCode()
        {
            const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
            var bytes = new byte[6];
            using (var random = RandomNumberGenerator.Create()) random.GetBytes(bytes);
            var output = new StringBuilder();
            for (var i = 0; i < bytes.Length; i++) output.Append(alphabet[bytes[i] % alphabet.Length]);
            return output.ToString();
        }
    }

    [DataContract]
    internal sealed class PairedDevice
    {
        [DataMember(Name = "device_id")]
        public string DeviceID { get; set; }

        [DataMember(Name = "device_name")]
        public string DeviceName { get; set; }

        [DataMember(Name = "token")]
        public string Token { get; set; }

        [DataMember(Name = "paired_at")]
        public string PairedAt { get; set; }

        [DataMember(Name = "last_seen")]
        public string LastSeen { get; set; }
    }

    [DataContract]
    internal sealed class SyncJob
    {
        [DataMember(Name = "id")]
        public string ID { get; set; }

        [DataMember(Name = "cif")]
        public string Cif { get; set; }

        [DataMember(Name = "contract_number")]
        public string ContractNumber { get; set; }

        [DataMember(Name = "customer_name")]
        public string CustomerName { get; set; }

        [DataMember(Name = "phone")]
        public string Phone { get; set; }

        [DataMember(Name = "message")]
        public string Message { get; set; }

        [DataMember(Name = "revision")]
        public int Revision { get; set; }

        [DataMember(Name = "created_at")]
        public string CreatedAt { get; set; }

        [DataMember(Name = "assigned_device_id")]
        public string AssignedDeviceID { get; set; }

        [DataMember(Name = "status")]
        public string Status { get; set; }

        [DataMember(Name = "status_at")]
        public string StatusAt { get; set; }

        [DataMember(Name = "source_row")]
        public int SourceRow { get; set; }
    }

    internal sealed class SyncStore
    {
        private readonly object _gate = new object();
        private readonly string _directory;
        private readonly string _file;
        private StoreData _data;

        public SyncStore(string directory)
        {
            _directory = directory;
            _file = Path.Combine(directory, "sync-data.json");
            Directory.CreateDirectory(_directory);
            _data = Load() ?? StoreData.Create();
            SaveLocked();
        }

        public StoreData Data
        {
            get { lock (_gate) return _data; }
        }

        public StoreData Snapshot()
        {
            lock (_gate)
            {
                return Clone(_data);
            }
        }

        public bool Queue(CustomerRow row, string message)
        {
            lock (_gate)
            {
                var duplicate = _data.Jobs.Any(delegate(SyncJob job)
                {
                    return job.Status == "pending"
                        && Same(job.Cif, row.Cif)
                        && Same(job.ContractNumber, row.Contract)
                        && CanonicalPhone(job.Phone) == CanonicalPhone(row.Phone);
                });
                if (duplicate) return false;

                _data.Jobs.Add(new SyncJob
                {
                    ID = Guid.NewGuid().ToString("N"),
                    Cif = row.Cif ?? "",
                    ContractNumber = row.Contract ?? "",
                    CustomerName = row.Name ?? "",
                    Phone = row.Phone ?? "",
                    Message = message,
                    Revision = 1,
                    CreatedAt = IsoNow(),
                    AssignedDeviceID = "",
                    Status = "pending",
                    StatusAt = "",
                    SourceRow = row.SourceRow
                });
                SaveLocked();
                return true;
            }
        }

        public PairedDevice Pair(string crmCode, string deviceID, string deviceName)
        {
            lock (_gate)
            {
                if (!Same(crmCode, _data.PairingCode)) return null;
                var device = _data.Devices.FirstOrDefault(delegate(PairedDevice item)
                {
                    return Same(item.DeviceID, deviceID);
                });
                if (device == null)
                {
                    device = new PairedDevice
                    {
                        DeviceID = deviceID,
                        DeviceName = deviceName,
                        Token = NewToken(),
                        PairedAt = IsoNow(),
                        LastSeen = IsoNow()
                    };
                    _data.Devices.Add(device);
                }
                else
                {
                    device.DeviceName = deviceName;
                    device.Token = NewToken();
                    device.LastSeen = IsoNow();
                }
                SaveLocked();
                return device;
            }
        }

        public PairedDevice Authorize(string token, string deviceID)
        {
            lock (_gate)
            {
                var device = _data.Devices.FirstOrDefault(delegate(PairedDevice item)
                {
                    return SlowEquals(item.Token, token) && Same(item.DeviceID, deviceID);
                });
                if (device != null)
                {
                    device.LastSeen = IsoNow();
                    SaveLocked();
                }
                return device;
            }
        }

        public List<SyncJob> JobsFor(string deviceID)
        {
            lock (_gate)
            {
                var jobs = _data.Jobs.Where(delegate(SyncJob job)
                {
                    return job.Status == "pending"
                        && (String.IsNullOrWhiteSpace(job.AssignedDeviceID)
                            || Same(job.AssignedDeviceID, deviceID));
                }).ToList();
                foreach (var job in jobs)
                {
                    if (String.IsNullOrWhiteSpace(job.AssignedDeviceID))
                        job.AssignedDeviceID = deviceID;
                }
                SaveLocked();
                return Clone(jobs);
            }
        }

        public List<string> ApplyStatuses(List<StatusEvent> events, string deviceID)
        {
            var accepted = new List<string>();
            lock (_gate)
            {
                foreach (var item in events ?? new List<StatusEvent>())
                {
                    if (!Same(item.DeviceID, deviceID)) continue;
                    var job = _data.Jobs.FirstOrDefault(delegate(SyncJob candidate)
                    {
                        return Same(candidate.ID, item.JobID)
                            && Same(candidate.AssignedDeviceID, deviceID);
                    });
                    if (job == null) continue;
                    if (item.Status != "confirmed_sent" && item.Status != "skipped" && item.Status != "failed")
                        continue;
                    job.Status = item.Status;
                    job.StatusAt = String.IsNullOrWhiteSpace(item.OccurredAt) ? IsoNow() : item.OccurredAt;
                    accepted.Add(item.ID);
                }
                if (accepted.Count > 0) SaveLocked();
            }
            return accepted;
        }

        public string FindLatestStatus(string cif, string contract, string phone)
        {
            lock (_gate)
            {
                var job = _data.Jobs
                    .Where(delegate(SyncJob item)
                    {
                        return Same(item.Cif, cif)
                            && Same(item.ContractNumber, contract)
                            && CanonicalPhone(item.Phone) == CanonicalPhone(phone);
                    })
                    .OrderByDescending(delegate(SyncJob item) { return item.CreatedAt; })
                    .FirstOrDefault();
                if (job == null) return "Chưa giao";
                switch (job.Status)
                {
                    case "confirmed_sent": return "Đã xác nhận gửi";
                    case "skipped": return "Đã bỏ qua";
                    case "failed": return "Gửi lỗi";
                    default: return String.IsNullOrWhiteSpace(job.AssignedDeviceID)
                        ? "Chờ iPhone nhận" : "iPhone đã nhận";
                }
            }
        }

        private StoreData Load()
        {
            if (!File.Exists(_file)) return null;
            try
            {
                using (var stream = File.OpenRead(_file))
                {
                    return (StoreData)new DataContractJsonSerializer(typeof(StoreData)).ReadObject(stream);
                }
            }
            catch
            {
                var corrupt = _file + ".corrupt-" + DateTime.Now.ToString("yyyyMMddHHmmss");
                File.Copy(_file, corrupt, true);
                return null;
            }
        }

        private void SaveLocked()
        {
            Directory.CreateDirectory(_directory);
            var temp = _file + ".tmp";
            using (var stream = File.Create(temp))
            {
                new DataContractJsonSerializer(typeof(StoreData)).WriteObject(stream, _data);
                stream.Flush();
            }
            if (File.Exists(_file))
            {
                var backup = _file + ".bak";
                File.Copy(_file, backup, true);
                File.Delete(_file);
            }
            File.Move(temp, _file);
        }

        private static T Clone<T>(T value)
        {
            using (var memory = new MemoryStream())
            {
                var serializer = new DataContractJsonSerializer(typeof(T));
                serializer.WriteObject(memory, value);
                memory.Position = 0;
                return (T)serializer.ReadObject(memory);
            }
        }

        private static bool Same(string left, string right)
        {
            return String.Equals((left ?? "").Trim(), (right ?? "").Trim(),
                StringComparison.OrdinalIgnoreCase);
        }

        private static bool SlowEquals(string left, string right)
        {
            var a = Encoding.UTF8.GetBytes(left ?? "");
            var b = Encoding.UTF8.GetBytes(right ?? "");
            var diff = a.Length ^ b.Length;
            var length = Math.Max(a.Length, b.Length);
            for (var i = 0; i < length; i++)
            {
                var av = i < a.Length ? a[i] : (byte)0;
                var bv = i < b.Length ? b[i] : (byte)0;
                diff |= av ^ bv;
            }
            return diff == 0;
        }

        private static string NewToken()
        {
            var bytes = new byte[32];
            using (var random = RandomNumberGenerator.Create()) random.GetBytes(bytes);
            return Convert.ToBase64String(bytes);
        }

        private static string CanonicalPhone(string phone)
        {
            return new string((phone ?? "").Where(Char.IsDigit).ToArray());
        }

        private static string IsoNow()
        {
            return DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);
        }
    }

    [DataContract]
    internal sealed class PairRequest
    {
        [DataMember(Name = "crm_code")]
        public string CrmCode { get; set; }

        [DataMember(Name = "device_id")]
        public string DeviceID { get; set; }

        [DataMember(Name = "device_name")]
        public string DeviceName { get; set; }
    }

    [DataContract]
    internal sealed class PairResponse
    {
        [DataMember(Name = "token")]
        public string Token { get; set; }
    }

    [DataContract]
    internal sealed class JobsResponse
    {
        [DataMember(Name = "jobs")]
        public List<SyncJob> Jobs { get; set; }

        [DataMember(Name = "cursor")]
        public string Cursor { get; set; }
    }

    [DataContract]
    internal sealed class StatusBatch
    {
        [DataMember(Name = "events")]
        public List<StatusEvent> Events { get; set; }
    }

    [DataContract]
    internal sealed class StatusEvent
    {
        [DataMember(Name = "id")]
        public string ID { get; set; }

        [DataMember(Name = "job_id")]
        public string JobID { get; set; }

        [DataMember(Name = "device_id")]
        public string DeviceID { get; set; }

        [DataMember(Name = "status")]
        public string Status { get; set; }

        [DataMember(Name = "occurred_at")]
        public string OccurredAt { get; set; }

        [DataMember(Name = "message_fingerprint")]
        public string MessageFingerprint { get; set; }
    }

    [DataContract]
    internal sealed class StatusResponse
    {
        [DataMember(Name = "accepted_ids")]
        public List<string> AcceptedIDs { get; set; }
    }

    [DataContract]
    internal sealed class ErrorResponse
    {
        [DataMember(Name = "error")]
        public string Error { get; set; }
    }

    internal sealed class LocalSyncServer : IDisposable
    {
        private readonly SyncStore _store;
        private readonly int _port;
        private TcpListener _listener;
        private CancellationTokenSource _cancellation;

        public event Action<string> Log;
        public event Action Changed;

        public bool IsRunning { get { return _listener != null; } }

        public LocalSyncServer(SyncStore store, int port)
        {
            _store = store;
            _port = port;
        }

        public void Start()
        {
            if (IsRunning) return;
            _cancellation = new CancellationTokenSource();
            _listener = new TcpListener(IPAddress.Any, _port);
            _listener.Start();
            Task.Run((Action)AcceptLoop);
        }

        public void Stop()
        {
            var listener = _listener;
            _listener = null;
            if (_cancellation != null) _cancellation.Cancel();
            if (listener != null)
            {
                try { listener.Stop(); } catch { }
            }
        }

        private void AcceptLoop()
        {
            while (IsRunning && !_cancellation.IsCancellationRequested)
            {
                try
                {
                    var client = _listener.AcceptTcpClient();
                    Task.Run(delegate { Handle(client); });
                }
                catch (SocketException)
                {
                    if (IsRunning) RaiseLog("Kết nối mạng bị ngắt.");
                }
                catch (ObjectDisposedException) { }
                catch (Exception ex)
                {
                    RaiseLog("Lỗi máy chủ: " + ex.Message);
                }
            }
        }

        private void Handle(TcpClient client)
        {
            using (client)
            {
                client.ReceiveTimeout = 15000;
                client.SendTimeout = 15000;
                try
                {
                    using (var stream = client.GetStream())
                    {
                        var request = HttpRequest.Read(stream);
                        Route(request, stream);
                    }
                }
                catch (Exception ex)
                {
                    RaiseLog("Yêu cầu không hợp lệ: " + ex.Message);
                }
            }
        }

        private void Route(HttpRequest request, Stream stream)
        {
            if (request.Method == "OPTIONS")
            {
                HttpResponse.Write(stream, 204, new byte[0], "application/json");
                return;
            }

            if (request.Method == "GET" && request.Path == "/api/v1/health")
            {
                HttpResponse.WriteJson(stream, 200, new Dictionary<string, string>
                {
                    { "status", "ok" },
                    { "product", "BachCRMSync" }
                });
                return;
            }

            if (request.Method == "POST" && request.Path == "/api/v1/pair")
            {
                var pair = Json.Read<PairRequest>(request.Body);
                if (pair == null || String.IsNullOrWhiteSpace(pair.DeviceID))
                {
                    HttpResponse.WriteJson(stream, 400, new ErrorResponse { Error = "Thiếu thông tin thiết bị." });
                    return;
                }
                var device = _store.Pair(pair.CrmCode, pair.DeviceID, pair.DeviceName);
                if (device == null)
                {
                    HttpResponse.WriteJson(stream, 403, new ErrorResponse { Error = "Mã CRM không đúng." });
                    return;
                }
                RaiseLog("Đã ghép thiết bị: " + device.DeviceName);
                HttpResponse.WriteJson(stream, 200, new PairResponse { Token = device.Token });
                RaiseChanged();
                return;
            }

            var deviceID = request.Header("X-BachSMS-Device");
            var auth = request.Header("Authorization");
            var token = auth != null && auth.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)
                ? auth.Substring(7).Trim() : "";
            var deviceAuth = _store.Authorize(token, deviceID);
            if (deviceAuth == null)
            {
                HttpResponse.WriteJson(stream, 401, new ErrorResponse { Error = "Thiết bị chưa được ghép hoặc khóa đã hết hiệu lực." });
                return;
            }

            if (request.Method == "GET" && request.Path == "/api/v1/jobs")
            {
                var jobs = _store.JobsFor(deviceID);
                HttpResponse.WriteJson(stream, 200, new JobsResponse { Jobs = jobs, Cursor = null });
                if (jobs.Count > 0) RaiseLog("iPhone đã nhận " + jobs.Count + " khách.");
                RaiseChanged();
                return;
            }

            if (request.Method == "POST" && request.Path == "/api/v1/statuses")
            {
                var batch = Json.Read<StatusBatch>(request.Body);
                var accepted = _store.ApplyStatuses(
                    batch == null ? new List<StatusEvent>() : batch.Events,
                    deviceID);
                HttpResponse.WriteJson(stream, 200, new StatusResponse { AcceptedIDs = accepted });
                if (accepted.Count > 0) RaiseLog("Đã nhận " + accepted.Count + " trạng thái từ iPhone.");
                RaiseChanged();
                return;
            }

            HttpResponse.WriteJson(stream, 404, new ErrorResponse { Error = "Không tìm thấy chức năng." });
        }

        private void RaiseLog(string message)
        {
            var handler = Log;
            if (handler != null) handler(message);
        }

        private void RaiseChanged()
        {
            var handler = Changed;
            if (handler != null) handler();
        }

        public void Dispose()
        {
            Stop();
            if (_cancellation != null) _cancellation.Dispose();
        }
    }

    internal sealed class HttpRequest
    {
        public string Method;
        public string Path;
        public Dictionary<string, string> Headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public byte[] Body = new byte[0];

        public string Header(string name)
        {
            string value;
            return Headers.TryGetValue(name, out value) ? value : "";
        }

        public static HttpRequest Read(Stream stream)
        {
            var headerBytes = new List<byte>();
            var state = 0;
            while (headerBytes.Count < 65536)
            {
                var value = stream.ReadByte();
                if (value < 0) throw new EndOfStreamException();
                headerBytes.Add((byte)value);
                state = (state == 0 && value == 13) ? 1
                    : (state == 1 && value == 10) ? 2
                    : (state == 2 && value == 13) ? 3
                    : (state == 3 && value == 10) ? 4 : 0;
                if (state == 4) break;
            }
            if (state != 4) throw new InvalidDataException("Header quá dài.");

            var headerText = Encoding.ASCII.GetString(headerBytes.ToArray());
            var lines = headerText.Split(new[] { "\r\n" }, StringSplitOptions.None);
            var requestLine = lines[0].Split(' ');
            if (requestLine.Length < 2) throw new InvalidDataException("Thiếu request line.");

            var request = new HttpRequest();
            request.Method = requestLine[0].ToUpperInvariant();
            var rawPath = requestLine[1];
            var queryIndex = rawPath.IndexOf('?');
            request.Path = queryIndex >= 0 ? rawPath.Substring(0, queryIndex) : rawPath;

            for (var i = 1; i < lines.Length; i++)
            {
                var colon = lines[i].IndexOf(':');
                if (colon <= 0) continue;
                request.Headers[lines[i].Substring(0, colon).Trim()] =
                    lines[i].Substring(colon + 1).Trim();
            }

            var length = 0;
            Int32.TryParse(request.Header("Content-Length"), out length);
            if (length < 0 || length > 5 * 1024 * 1024) throw new InvalidDataException("Body không hợp lệ.");
            if (length > 0)
            {
                request.Body = new byte[length];
                var offset = 0;
                while (offset < length)
                {
                    var read = stream.Read(request.Body, offset, length - offset);
                    if (read <= 0) throw new EndOfStreamException();
                    offset += read;
                }
            }
            return request;
        }
    }

    internal static class HttpResponse
    {
        public static void WriteJson<T>(Stream stream, int code, T value)
        {
            Write(stream, code, Json.Write(value), "application/json; charset=utf-8");
        }

        public static void Write(Stream stream, int code, byte[] body, string contentType)
        {
            var reason = code == 200 ? "OK"
                : code == 204 ? "No Content"
                : code == 400 ? "Bad Request"
                : code == 401 ? "Unauthorized"
                : code == 403 ? "Forbidden"
                : code == 404 ? "Not Found" : "Error";
            var header = "HTTP/1.1 " + code + " " + reason + "\r\n"
                + "Content-Type: " + contentType + "\r\n"
                + "Content-Length: " + body.Length + "\r\n"
                + "Connection: close\r\n"
                + "Cache-Control: no-store\r\n"
                + "Access-Control-Allow-Origin: *\r\n"
                + "Access-Control-Allow-Headers: Authorization, Content-Type, X-BachSMS-Device\r\n"
                + "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n\r\n";
            var headerBytes = Encoding.ASCII.GetBytes(header);
            stream.Write(headerBytes, 0, headerBytes.Length);
            if (body.Length > 0) stream.Write(body, 0, body.Length);
            stream.Flush();
        }
    }

    internal static class Json
    {
        public static T Read<T>(byte[] data) where T : class
        {
            if (data == null || data.Length == 0) return null;
            using (var stream = new MemoryStream(data))
            {
                return new DataContractJsonSerializer(typeof(T)).ReadObject(stream) as T;
            }
        }

        public static byte[] Write<T>(T value)
        {
            using (var stream = new MemoryStream())
            {
                new DataContractJsonSerializer(typeof(T)).WriteObject(stream, value);
                return stream.ToArray();
            }
        }
    }

    internal sealed class CustomerRow : INotifyPropertyChanged
    {
        private bool _selected;
        private string _statusText;

        public bool Selected
        {
            get { return _selected; }
            set
            {
                if (_selected == value) return;
                _selected = value;
                Raise("Selected");
            }
        }

        public string Cif { get; set; }
        public string Contract { get; set; }
        public string Name { get; set; }
        public string Phone { get; set; }
        public int SourceRow { get; set; }

        public string StatusText
        {
            get { return _statusText; }
            set
            {
                if (_statusText == value) return;
                _statusText = value;
                Raise("StatusText");
            }
        }

        public event PropertyChangedEventHandler PropertyChanged;
        private void Raise(string name)
        {
            var handler = PropertyChanged;
            if (handler != null) handler(this, new PropertyChangedEventArgs(name));
        }
    }

    internal static class XlsxReader
    {
        public static List<CustomerRow> ReadCustomers(string path)
        {
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete))
            using (var archive = new ZipArchive(stream, ZipArchiveMode.Read, false))
            {
                var shared = ReadSharedStrings(archive);
                var sheetPath = ResolveDataSheet(archive);
                var entry = archive.GetEntry(sheetPath);
                if (entry == null) throw new InvalidDataException("Không tìm thấy Sheet1/DanhSach trong Excel.");

                var rows = ReadRows(entry, shared);
                var headerIndex = FindHeader(rows);
                if (headerIndex < 0)
                    throw new InvalidDataException("Không nhận diện được dòng tiêu đề CIF, tên khách và số điện thoại.");

                var header = rows[headerIndex];
                var cifColumn = FindColumn(header, new[] { "cif", "ma kh", "ma khach hang", "customer number", "customer no" });
                var contractColumn = FindColumn(header, new[] { "so hd", "so hop dong", "hop dong", "contract", "contract no" });
                var nameColumn = FindColumn(header, new[] { "ten kh", "ten khach hang", "ho ten", "customer name", "name" });
                var phoneColumn = FindColumn(header, new[] { "dtd d ca nhan", "dtdd ca nhan", "sdt kh", "so dien thoai", "dien thoai", "mobile", "phone" });

                if (cifColumn < 0 || nameColumn < 0 || phoneColumn < 0)
                    throw new InvalidDataException("Excel thiếu một trong các cột CIF, Tên KH hoặc SĐT.");

                var result = new List<CustomerRow>();
                var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                for (var i = headerIndex + 1; i < rows.Count; i++)
                {
                    var row = rows[i];
                    var cif = Cell(row, cifColumn);
                    var name = Cell(row, nameColumn);
                    var phone = Cell(row, phoneColumn);
                    var contract = contractColumn >= 0 ? Cell(row, contractColumn) : "";
                    if (String.IsNullOrWhiteSpace(phone) || String.IsNullOrWhiteSpace(cif)) continue;
                    var key = cif.Trim() + "|" + contract.Trim() + "|" + Digits(phone);
                    if (!seen.Add(key)) continue;
                    result.Add(new CustomerRow
                    {
                        Selected = false,
                        Cif = cif.Trim(),
                        Contract = contract.Trim(),
                        Name = name.Trim(),
                        Phone = phone.Trim(),
                        SourceRow = i + 1,
                        StatusText = "Chưa giao"
                    });
                }
                return result;
            }
        }

        private static string ResolveDataSheet(ZipArchive archive)
        {
            var workbookEntry = archive.GetEntry("xl/workbook.xml");
            var relsEntry = archive.GetEntry("xl/_rels/workbook.xml.rels");
            if (workbookEntry == null || relsEntry == null)
                return "xl/worksheets/sheet1.xml";

            var workbook = LoadXml(workbookEntry);
            var relationships = LoadXml(relsEntry);
            var relMap = new Dictionary<string, string>();
            foreach (XmlElement rel in relationships.GetElementsByTagName("Relationship"))
            {
                relMap[rel.GetAttribute("Id")] = rel.GetAttribute("Target");
            }

            XmlNode fallback = null;
            foreach (XmlNode sheet in workbook.GetElementsByTagName("sheet"))
            {
                if (fallback == null) fallback = sheet;
                var name = sheet.Attributes["name"] == null ? "" : sheet.Attributes["name"].Value;
                if (Normalize(name) == "code") continue;
                if (Normalize(name) == "sheet1" || Normalize(name) == "danhsach" || fallback == sheet)
                {
                    var relationID = "";
                    foreach (XmlAttribute attribute in sheet.Attributes)
                    {
                        if (attribute.LocalName == "id") relationID = attribute.Value;
                    }
                    string target;
                    if (relMap.TryGetValue(relationID, out target))
                    {
                        target = target.Replace("\\", "/");
                        while (target.StartsWith("../")) target = target.Substring(3);
                        return target.StartsWith("xl/") ? target : "xl/" + target.TrimStart('/');
                    }
                }
            }
            return "xl/worksheets/sheet1.xml";
        }

        private static List<string> ReadSharedStrings(ZipArchive archive)
        {
            var result = new List<string>();
            var entry = archive.GetEntry("xl/sharedStrings.xml");
            if (entry == null) return result;
            var document = LoadXml(entry);
            foreach (XmlNode item in document.GetElementsByTagName("si"))
            {
                var builder = new StringBuilder();
                foreach (XmlNode text in item.SelectNodes(".//*[local-name()='t']"))
                    builder.Append(text.InnerText);
                result.Add(builder.ToString());
            }
            return result;
        }

        private static List<Dictionary<int, string>> ReadRows(ZipArchiveEntry entry, List<string> shared)
        {
            var document = LoadXml(entry);
            var output = new List<Dictionary<int, string>>();
            foreach (XmlNode rowNode in document.SelectNodes("//*[local-name()='sheetData']/*[local-name()='row']"))
            {
                var row = new Dictionary<int, string>();
                foreach (XmlNode cell in rowNode.SelectNodes("./*[local-name()='c']"))
                {
                    var reference = cell.Attributes["r"] == null ? "" : cell.Attributes["r"].Value;
                    var column = ColumnIndex(reference);
                    var type = cell.Attributes["t"] == null ? "" : cell.Attributes["t"].Value;
                    var valueNode = cell.SelectSingleNode("./*[local-name()='v']");
                    var value = valueNode == null ? "" : valueNode.InnerText;
                    if (type == "s")
                    {
                        int index;
                        if (Int32.TryParse(value, out index) && index >= 0 && index < shared.Count)
                            value = shared[index];
                    }
                    else if (type == "inlineStr")
                    {
                        var texts = cell.SelectNodes(".//*[local-name()='t']");
                        var builder = new StringBuilder();
                        foreach (XmlNode text in texts) builder.Append(text.InnerText);
                        value = builder.ToString();
                    }
                    row[column] = value ?? "";
                }
                output.Add(row);
            }
            return output;
        }

        private static int FindHeader(List<Dictionary<int, string>> rows)
        {
            for (var i = 0; i < Math.Min(rows.Count, 20); i++)
            {
                var normalized = rows[i].Values.Select(Normalize).ToList();
                var hasCif = normalized.Any(delegate(string value)
                {
                    return value == "cif" || value.Contains("ma kh") || value.Contains("customer no");
                });
                var hasPhone = normalized.Any(delegate(string value)
                {
                    return value.Contains("dien thoai") || value.Contains("dtdd") || value.Contains("sdt") || value == "phone" || value == "mobile";
                });
                if (hasCif && hasPhone) return i;
            }
            return -1;
        }

        private static int FindColumn(Dictionary<int, string> header, IEnumerable<string> aliases)
        {
            var normalizedAliases = aliases.Select(Normalize).ToArray();
            foreach (var item in header)
            {
                var value = Normalize(item.Value);
                if (normalizedAliases.Any(delegate(string alias)
                {
                    return value == alias || value.Contains(alias);
                })) return item.Key;
            }
            return -1;
        }

        private static string Cell(Dictionary<int, string> row, int column)
        {
            string value;
            return row.TryGetValue(column, out value) ? value ?? "" : "";
        }

        private static int ColumnIndex(string reference)
        {
            var value = 0;
            foreach (var character in reference)
            {
                if (!Char.IsLetter(character)) break;
                value = value * 26 + (Char.ToUpperInvariant(character) - 'A' + 1);
            }
            return Math.Max(0, value - 1);
        }

        private static string Normalize(string input)
        {
            var source = (input ?? "").Trim().ToLowerInvariant().Replace('đ', 'd');
            var decomposed = source.Normalize(NormalizationForm.FormD);
            var builder = new StringBuilder();
            foreach (var character in decomposed)
            {
                if (CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark)
                    builder.Append(Char.IsLetterOrDigit(character) ? character : ' ');
            }
            return String.Join(" ", builder.ToString()
                .Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries));
        }

        private static string Digits(string value)
        {
            return new string((value ?? "").Where(Char.IsDigit).ToArray());
        }

        private static XmlDocument LoadXml(ZipArchiveEntry entry)
        {
            var document = new XmlDocument();
            document.PreserveWhitespace = false;
            using (var stream = entry.Open()) document.Load(stream);
            return document;
        }
    }

    internal static class LocalNetwork
    {
        public static string GetPreferredIPv4()
        {
            try
            {
                foreach (var network in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (network.OperationalStatus != OperationalStatus.Up
                        || network.NetworkInterfaceType == NetworkInterfaceType.Loopback)
                        continue;
                    foreach (var address in network.GetIPProperties().UnicastAddresses)
                    {
                        if (address.Address.AddressFamily == AddressFamily.InterNetwork
                            && !IPAddress.IsLoopback(address.Address)
                            && !address.Address.ToString().StartsWith("169.254."))
                            return address.Address.ToString();
                    }
                }
            }
            catch { }
            return "127.0.0.1";
        }
    }
}
