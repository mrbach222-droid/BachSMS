using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;

namespace BachCRMSync
{
    internal static class SyncTests
    {
        public static int Main()
        {
            var root = Path.Combine(Path.GetTempPath(), "BachCRMSyncTests-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            LocalSyncServer server = null;
            try
            {
                var store = new SyncStore(root);
                var row = new CustomerRow
                {
                    Cif = "CIF001",
                    Contract = "HD001",
                    Name = "NGUYEN VAN A",
                    Phone = "0912345678",
                    SourceRow = 6
                };
                Assert(store.Queue(row, "Xin chao NGUYEN VAN A"), "Queue first job");
                Assert(!store.Queue(row, "Duplicate"), "Reject duplicate pending job");

                var port = 18765;
                server = new LocalSyncServer(store, port);
                server.Start();
                Thread.Sleep(150);

                var baseUrl = "http://127.0.0.1:" + port;
                var pairRequest = new PairRequest
                {
                    CrmCode = store.Data.PairingCode,
                    DeviceID = "device-test",
                    DeviceName = "iPhone Test"
                };
                var pair = Post<PairRequest, PairResponse>(
                    baseUrl + "/api/v1/pair", pairRequest, null, null);
                Assert(pair != null && !String.IsNullOrWhiteSpace(pair.Token), "Pair returns token");

                var jobs = Get<JobsResponse>(
                    baseUrl + "/api/v1/jobs?device_id=device-test",
                    pair.Token,
                    "device-test");
                Assert(jobs != null && jobs.Jobs != null && jobs.Jobs.Count == 1, "Fetch one job");
                Assert(jobs.Jobs[0].Cif == "CIF001", "Preserve CIF");
                Assert(jobs.Jobs[0].CreatedAt.EndsWith("Z"), "ISO date");

                var status = new StatusBatch
                {
                    Events = new List<StatusEvent>
                    {
                        new StatusEvent
                        {
                            ID = "event-test",
                            JobID = jobs.Jobs[0].ID,
                            DeviceID = "device-test",
                            Status = "confirmed_sent",
                            OccurredAt = "2026-10-20T09:30:00Z"
                        }
                    }
                };
                var accepted = Post<StatusBatch, StatusResponse>(
                    baseUrl + "/api/v1/statuses", status, pair.Token, "device-test");
                Assert(accepted.AcceptedIDs.Count == 1 && accepted.AcceptedIDs[0] == "event-test",
                    "Accept status event");
                Assert(store.FindLatestStatus("CIF001", "HD001", "0912345678") == "Đã xác nhận gửi",
                    "Status reflected in store");

                var after = Get<JobsResponse>(
                    baseUrl + "/api/v1/jobs?device_id=device-test",
                    pair.Token,
                    "device-test");
                Assert(after.Jobs.Count == 0, "Sent job leaves pending queue");

                File.WriteAllText(Path.Combine(root, "PASS.txt"), "PASS", Encoding.UTF8);
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex);
                return 1;
            }
            finally
            {
                if (server != null) server.Dispose();
                try { Directory.Delete(root, true); } catch { }
            }
        }

        private static TResponse Post<TRequest, TResponse>(
            string url,
            TRequest body,
            string token,
            string deviceID) where TResponse : class
        {
            var request = (HttpWebRequest)WebRequest.Create(url);
            request.Method = "POST";
            request.ContentType = "application/json";
            request.Timeout = 5000;
            if (!String.IsNullOrWhiteSpace(token))
                request.Headers["Authorization"] = "Bearer " + token;
            if (!String.IsNullOrWhiteSpace(deviceID))
                request.Headers["X-BachSMS-Device"] = deviceID;
            var data = Json.Write(body);
            request.ContentLength = data.Length;
            using (var stream = request.GetRequestStream())
                stream.Write(data, 0, data.Length);
            using (var response = request.GetResponse())
            using (var stream = response.GetResponseStream())
                return Json.Read<TResponse>(ReadAll(stream));
        }

        private static T Get<T>(string url, string token, string deviceID) where T : class
        {
            var request = (HttpWebRequest)WebRequest.Create(url);
            request.Method = "GET";
            request.Timeout = 5000;
            request.Headers["Authorization"] = "Bearer " + token;
            request.Headers["X-BachSMS-Device"] = deviceID;
            using (var response = request.GetResponse())
            using (var stream = response.GetResponseStream())
                return Json.Read<T>(ReadAll(stream));
        }

        private static byte[] ReadAll(Stream stream)
        {
            using (var memory = new MemoryStream())
            {
                var buffer = new byte[4096];
                int read;
                while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
                    memory.Write(buffer, 0, read);
                return memory.ToArray();
            }
        }

        private static void Assert(bool condition, string name)
        {
            if (!condition) throw new InvalidOperationException("FAILED: " + name);
            Console.WriteLine("PASS: " + name);
        }
    }
}
