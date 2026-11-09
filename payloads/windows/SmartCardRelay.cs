using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

class SmartCardRelay
{
    const int DefaultPort = 35963;
    // libifdvpcd advertises two Lun slots (vicc_max_slots = 2) and pcscd dials
    // CHANNELID + Lun, so the driver needs both 35963 and 35964 listening.
    const int DefaultSlots = 2;
    const string DefaultAllow = "192.168.1.158";
    const string RuleName = "BBT-SmartCardRelay";

    const uint SCARD_SCOPE_USER = 0;
    const uint SCARD_SHARE_SHARED = 2;
    const uint SCARD_PROTOCOL_T0 = 1;
    const uint SCARD_PROTOCOL_T1 = 2;
    const uint SCARD_LEAVE_CARD = 0;
    const uint SCARD_RESET_CARD = 1;
    const uint SCARD_ATTR_ATR_STRING = 0x00090303;

    const int SCARD_E_NO_SMARTCARD = unchecked((int)0x8010000C);
    const int SCARD_E_NO_READERS = unchecked((int)0x8010002E);
    const int SCARD_W_REMOVED_CARD = unchecked((int)0x80100069);

    [StructLayout(LayoutKind.Sequential)]
    struct SCARD_IO_REQUEST
    {
        public uint dwProtocol;
        public uint cbPciLength;
    }

    [DllImport("winscard.dll", SetLastError = true)]
    static extern int SCardEstablishContext(uint dwScope, IntPtr pv1, IntPtr pv2, out IntPtr phContext);

    [DllImport("winscard.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern int SCardListReaders(IntPtr hContext, string groups, StringBuilder readers, ref uint len);

    [DllImport("winscard.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern int SCardConnect(IntPtr hContext, string reader, uint share, uint preferred,
        out IntPtr phCard, out uint activeProtocol);

    [DllImport("winscard.dll", SetLastError = true)]
    static extern int SCardGetAttrib(IntPtr hCard, uint attrId, byte[] buffer, ref uint length);

    [DllImport("winscard.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern int SCardStatus(IntPtr hCard, StringBuilder readerName, ref uint readerLen,
        out uint state, out uint protocol, byte[] atr, ref uint atrLen);

    [DllImport("winscard.dll", SetLastError = true)]
    static extern int SCardTransmit(IntPtr hCard, ref SCARD_IO_REQUEST sendPci, byte[] sendBuffer,
        int sendLength, IntPtr recvPci, byte[] recvBuffer, ref int recvLength);

    [DllImport("winscard.dll", SetLastError = true)]
    static extern int SCardReconnect(IntPtr hCard, uint share, uint preferred, uint init, out uint activeProtocol);

    [DllImport("winscard.dll", SetLastError = true)]
    static extern int SCardDisconnect(IntPtr hCard, uint disposition);

    [DllImport("winscard.dll", SetLastError = true)]
    static extern int SCardReleaseContext(IntPtr hContext);

    // One physical card, one winscard handle per slot connection. PC/SC allows
    // several shared connections; transmissions are serialized on cardLock.
    static readonly object cardLock = new object();
    static string lastReader = null;

    sealed class CardSession
    {
        IntPtr context = IntPtr.Zero;
        IntPtr card = IntPtr.Zero;
        uint protocol = SCARD_PROTOCOL_T0;

        public bool Ensure()
        {
            lock (cardLock)
            {
                if (card != IntPtr.Zero)
                    return true;

                if (context == IntPtr.Zero &&
                    SCardEstablishContext(SCARD_SCOPE_USER, IntPtr.Zero, IntPtr.Zero, out context) != 0)
                {
                    Console.WriteLine("SCardEstablishContext failed");
                    return false;
                }

                List<string> readers = GetReaders(context);
                readers.Sort(delegate(string a, string b)
                {
                    return Score(b).CompareTo(Score(a));
                });

                foreach (string name in readers)
                {
                    IntPtr handle;
                    uint active;
                    int rc = SCardConnect(context, name, SCARD_SHARE_SHARED,
                        SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, out handle, out active);
                    if (rc == 0)
                    {
                        card = handle;
                        protocol = active;
                        lastReader = name;
                        Console.WriteLine("card connected: " + name +
                            " (protocol " + (active == SCARD_PROTOCOL_T1 ? "T=1" : "T=0") + ")");
                        return true;
                    }
                }

                if (readers.Count == 0)
                    Console.WriteLine("no smart card reader found yet");
                else
                    Console.WriteLine("reader found but no card is available");
                return false;
            }
        }

        public void ResetCard()
        {
            lock (cardLock)
            {
                if (card == IntPtr.Zero)
                {
                    Ensure();
                    return;
                }
                uint active;
                int rc = SCardReconnect(card, SCARD_SHARE_SHARED,
                    SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, SCARD_RESET_CARD, out active);
                if (rc == 0)
                {
                    protocol = active;
                    Console.WriteLine("card reset");
                }
                else
                {
                    Console.WriteLine("reset failed: 0x" + rc.ToString("X8"));
                    Disconnect();
                }
            }
        }

        public void Disconnect()
        {
            lock (cardLock)
            {
                if (card != IntPtr.Zero)
                {
                    SCardDisconnect(card, SCARD_LEAVE_CARD);
                    card = IntPtr.Zero;
                    Console.WriteLine("card disconnected");
                }
                if (context != IntPtr.Zero)
                {
                    SCardReleaseContext(context);
                    context = IntPtr.Zero;
                }
            }
        }

        public byte[] GetAtr()
        {
            lock (cardLock)
            {
                if (!Ensure())
                    return new byte[0];

                uint length = 0;
                int rc = SCardGetAttrib(card, SCARD_ATTR_ATR_STRING, null, ref length);
                if (rc != 0 || length == 0)
                {
                    StringBuilder name = new StringBuilder(256);
                    uint nameLen = 256;
                    uint state;
                    uint active;
                    byte[] atr = new byte[256];
                    uint atrLen = 256;
                    rc = SCardStatus(card, name, ref nameLen, out state, out active, atr, ref atrLen);
                    if (rc != 0 || atrLen == 0)
                        return new byte[0];
                    byte[] fallback = new byte[atrLen];
                    Array.Copy(atr, fallback, (int)atrLen);
                    return fallback;
                }

                byte[] buffer = new byte[length];
                rc = SCardGetAttrib(card, SCARD_ATTR_ATR_STRING, buffer, ref length);
                if (rc != 0)
                    return new byte[0];
                if (length < buffer.Length)
                {
                    byte[] copy = new byte[length];
                    Array.Copy(buffer, copy, (int)length);
                    return copy;
                }
                return buffer;
            }
        }

        public byte[] Transmit(byte[] apdu)
        {
            lock (cardLock)
            {
                if (!Ensure())
                    return new byte[0];

                SCARD_IO_REQUEST send = new SCARD_IO_REQUEST();
                send.dwProtocol = protocol;
                send.cbPciLength = 8;

                byte[] response = new byte[65538];
                int responseLength = response.Length;
                int rc = SCardTransmit(card, ref send, apdu, apdu.Length,
                    IntPtr.Zero, response, ref responseLength);

                if (rc != 0)
                {
                    Console.WriteLine("transmit failed: 0x" + rc.ToString("X8"));
                    if (rc == SCARD_W_REMOVED_CARD || rc == SCARD_E_NO_SMARTCARD)
                        Disconnect();
                    return new byte[0];
                }

                byte[] result = new byte[responseLength];
                Array.Copy(response, result, responseLength);
                return result;
            }
        }

        public static int Score(string name)
        {
            int score = 0;
            if (name.IndexOf("Alcor", StringComparison.OrdinalIgnoreCase) >= 0)
                score += 10;
            if (lastReader != null && name == lastReader)
                score += 20;
            return score;
        }

        public static List<string> GetReaders(IntPtr ctx)
        {
            List<string> readers = new List<string>();
            uint length = 0;
            int rc = SCardListReaders(ctx, null, null, ref length);
            if (rc == SCARD_E_NO_READERS || length == 0)
                return readers;

            StringBuilder buffer = new StringBuilder((int)length);
            rc = SCardListReaders(ctx, null, buffer, ref length);
            if (rc != 0)
                return readers;

            foreach (string name in buffer.ToString().Split('\0'))
                if (name.Length > 0)
                    readers.Add(name);
            return readers;
        }
    }

    static void Main(string[] args)
    {
        Console.OutputEncoding = Encoding.Default;
        int port = DefaultPort;
        int slots = DefaultSlots;
        string allow = DefaultAllow;
        bool firewall = true;
        bool off = false;

        foreach (string arg in args)
        {
            if (arg == "off")
                off = true;
            else if (arg.StartsWith("--port="))
                port = int.Parse(arg.Substring(7));
            else if (arg.StartsWith("--slots="))
                slots = int.Parse(arg.Substring(8));
            else if (arg.StartsWith("--allow="))
            {
                string value = arg.Substring(8).Trim();
                allow = (value == "any" || value == "*") ? null : value;
            }
            else if (arg == "--no-firewall")
                firewall = false;
            else if (arg == "help" || arg == "--help" || arg == "-h")
            {
                Usage();
                return;
            }
        }

        Console.WriteLine("=== BBT smart card relay (VPCD) ===");
        Console.WriteLine();

        if (off)
        {
            Run("netsh.exe", "advfirewall firewall delete rule name=\"" + RuleName + "\"", false);
            Console.WriteLine("Firewall rule " + RuleName + " removed.");
            return;
        }

        if (slots < 1 || slots > 8)
        {
            Console.WriteLine("--slots must be between 1 and 8");
            return;
        }
        if (port < 1 || port + slots - 1 > 65535)
        {
            Console.WriteLine("bad port range: " + port + " + " + slots);
            return;
        }

        IPAddress allowed = null;
        if (allow != null && !IPAddress.TryParse(allow, out allowed))
        {
            Console.WriteLine("Bad --allow address: " + allow);
            return;
        }

        string lastPort = (port + slots - 1).ToString();
        if (firewall)
        {
            Run("netsh.exe", "advfirewall firewall delete rule name=\"" + RuleName + "\"", false);
            string rule = "advfirewall firewall add rule name=\"" + RuleName +
                "\" dir=in action=allow protocol=TCP localport=" +
                (slots > 1 ? port + "-" + lastPort : port.ToString());
            if (allowed != null)
                rule += " remoteip=" + allowed;
            rule += " profile=any";
            Run("netsh.exe", rule, false);
        }

        ListReaders();
        Console.WriteLine();
        Console.WriteLine("Allowed client: " + (allowed == null ? "any" : allowed.ToString()));
        Console.WriteLine("Local IPv4: " + LocalIPv4());
        Console.WriteLine("Ports: " + (slots > 1 ? port + "-" + lastPort : port.ToString()) +
            " (" + slots + " Lun slot" + (slots == 1 ? "" : "s") + ")");
        Console.WriteLine();
        Console.WriteLine("Start vpcd on Kali now; it connects here and exposes the card.");
        Console.WriteLine("Press Ctrl+C to stop.");
        Console.WriteLine();

        for (int i = 0; i < slots; i++)
        {
            int listenPort = port + i;
            Thread thread = new Thread(delegate() { Listen(listenPort, allowed); });
            thread.IsBackground = true;
            thread.Start();
        }

        Thread.Sleep(Timeout.Infinite);
    }

    static void Usage()
    {
        Console.WriteLine("Usage:");
        Console.WriteLine("  SmartCardRelay.exe                  listen on 35963-35964 for 192.168.1.158");
        Console.WriteLine("  SmartCardRelay.exe --allow=IP       allow a different client address");
        Console.WriteLine("  SmartCardRelay.exe --allow=any      no client address restriction");
        Console.WriteLine("  SmartCardRelay.exe --port=N         first port (default 35963)");
        Console.WriteLine("  SmartCardRelay.exe --slots=N        consecutive ports, one per Lun (default 2)");
        Console.WriteLine("  SmartCardRelay.exe --no-firewall    do not touch Windows Firewall");
        Console.WriteLine("  SmartCardRelay.exe off              remove the firewall rule");
        Console.WriteLine();
        Console.WriteLine("libifdvpcd has two slots and dials CHANNELID+Lun, so Kali uses both");
        Console.WriteLine("35963 and 35964. The card itself is shared by both slots.");
    }

    static void Listen(int port, IPAddress allowed)
    {
        TcpListener listener = new TcpListener(IPAddress.Any, port);
        try
        {
            listener.Start(8);
        }
        catch (Exception ex)
        {
            Console.WriteLine("cannot listen on " + port + ": " + ex.Message);
            return;
        }
        Console.WriteLine("listening on 0.0.0.0:" + port);

        while (true)
        {
            TcpClient client;
            try
            {
                client = listener.AcceptTcpClient();
            }
            catch (Exception ex)
            {
                Console.WriteLine("accept failed on " + port + ": " + ex.Message);
                return;
            }

            IPEndPoint remote = (IPEndPoint)client.Client.RemoteEndPoint;
            if (allowed != null && !remote.Address.Equals(allowed))
            {
                Console.WriteLine("rejected client " + remote.Address + " on " + port +
                    " (allowed " + allowed + ")");
                client.Close();
                continue;
            }

            Console.WriteLine("vpcd connected from " + remote.Address + ":" + remote.Port +
                " on port " + port);
            TcpClient connection = client;
            Thread worker = new Thread(delegate() { Serve(connection, port); });
            worker.IsBackground = true;
            worker.Start();
        }
    }

    static void Serve(TcpClient client, int port)
    {
        CardSession session = new CardSession();
        try
        {
            client.NoDelay = true;
            client.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true);
            Handle(client.GetStream(), session);
        }
        catch (Exception ex)
        {
            Console.WriteLine("session error on " + port + ": " + ex.Message);
        }
        finally
        {
            session.Disconnect();
            try { client.Close(); } catch (Exception) { }
            Console.WriteLine("vpcd disconnected on port " + port);
        }
    }

    static void Handle(NetworkStream stream, CardSession session)
    {
        while (true)
        {
            int length = ReadLength(stream);
            if (length < 0)
                return;

            byte[] payload = new byte[length];
            if (length > 0 && !ReadExact(stream, payload))
                return;

            if (length == 1)
            {
                switch (payload[0])
                {
                    case 0x00:
                        session.Disconnect();
                        break;
                    case 0x01:
                        session.Ensure();
                        break;
                    case 0x02:
                        session.ResetCard();
                        break;
                    case 0x04:
                        WriteFrame(stream, session.GetAtr());
                        break;
                    default:
                        Console.WriteLine("unknown control byte 0x" + payload[0].ToString("X2"));
                        break;
                }
            }
            else
            {
                Console.WriteLine("APDU " + length + " bytes");
                byte[] response = session.Transmit(payload);
                WriteFrame(stream, response);
                Console.WriteLine("RAPDU " + response.Length + " bytes");
            }
        }
    }

    static void ListReaders()
    {
        IntPtr ctx;
        if (SCardEstablishContext(SCARD_SCOPE_USER, IntPtr.Zero, IntPtr.Zero, out ctx) != 0)
        {
            Console.WriteLine("readers: could not open the smart card resource manager");
            return;
        }

        List<string> readers = CardSession.GetReaders(ctx);
        SCardReleaseContext(ctx);
        if (readers.Count == 0)
        {
            Console.WriteLine("readers: none detected (is the reader plugged in?)");
            return;
        }
        foreach (string name in readers)
            Console.WriteLine("reader: " + name);
    }

    static int ReadLength(NetworkStream stream)
    {
        byte[] header = new byte[2];
        if (!ReadExact(stream, header))
            return -1;
        return (header[0] << 8) | header[1];
    }

    static bool ReadExact(NetworkStream stream, byte[] buffer)
    {
        int offset = 0;
        while (offset < buffer.Length)
        {
            int read = stream.Read(buffer, offset, buffer.Length - offset);
            if (read <= 0)
                return false;
            offset += read;
        }
        return true;
    }

    static void WriteFrame(NetworkStream stream, byte[] payload)
    {
        byte[] frame = new byte[payload.Length + 2];
        frame[0] = (byte)(payload.Length >> 8);
        frame[1] = (byte)(payload.Length & 0xFF);
        Array.Copy(payload, 0, frame, 2, payload.Length);
        stream.Write(frame, 0, frame.Length);
        stream.Flush();
    }

    static string LocalIPv4()
    {
        try
        {
            foreach (IPAddress address in Dns.GetHostAddresses(Dns.GetHostName()))
                if (address.AddressFamily == AddressFamily.InterNetwork)
                    return address.ToString();
        }
        catch (Exception)
        {
        }
        return "unknown";
    }

    static void Run(string file, string arguments, bool quiet)
    {
        try
        {
            ProcessStartInfo info = new ProcessStartInfo(file, arguments);
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            Process process = Process.Start(info);
            string output = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
            process.WaitForExit();
            if (!quiet && process.ExitCode != 0)
                Console.WriteLine("netsh: " + output.Trim());
        }
        catch (Exception ex)
        {
            if (!quiet)
                Console.WriteLine("netsh error: " + ex.Message);
        }
    }
}
