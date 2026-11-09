using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Text;
using Microsoft.Win32;

class SmartCardRdp
{
    const string RuleName = "BBT-RDP";
    const string TsKey = @"SYSTEM\CurrentControlSet\Control\Terminal Server";

    static string Run(string file, string arguments, out int exitCode)
    {
        ProcessStartInfo info = new ProcessStartInfo(file, arguments);
        info.UseShellExecute = false;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.CreateNoWindow = true;
        Process process = Process.Start(info);
        string output = process.StandardOutput.ReadToEnd();
        output += process.StandardError.ReadToEnd();
        process.WaitForExit();
        exitCode = process.ExitCode;
        return output;
    }

    static void Main(string[] args)
    {
        Console.OutputEncoding = Encoding.Default;
        string mode = args.Length > 0 ? args[0].ToLowerInvariant() : "";
        Console.WriteLine("=== BBT smart card helper ===");
        Console.WriteLine();

        if (mode == "off")
        {
            DisableRdp();
            Pause();
            return;
        }

        if (mode == "help" || mode == "-h" || mode == "/?")
        {
            ShowUsage();
            return;
        }

        EnableRdp();
        ReadCards();
        Pause();
    }

    static void EnableRdp()
    {
        Console.WriteLine("[1/3] Enabling Remote Desktop...");
        try
        {
            Registry.SetValue(@"HKEY_LOCAL_MACHINE\" + TsKey, "fDenyTSConnections", 0, RegistryValueKind.DWord);
            Console.WriteLine("      registry: fDenyTSConnections = 0");
        }
        catch (Exception ex)
        {
            Console.WriteLine("      registry error: " + ex.Message);
        }

        int code;
        Run("netsh.exe", "advfirewall firewall delete rule name=\"" + RuleName + "\"", out code);
        string rule = Run("netsh.exe", "advfirewall firewall add rule name=\"" + RuleName +
            "\" dir=in action=allow protocol=TCP localport=3389 profile=any", out code);
        if (code == 0)
            Console.WriteLine("      firewall: TCP 3389 allowed (rule " + RuleName + ")");
        else
            Console.WriteLine("      firewall error: " + rule.Trim());

        string start = Run("net.exe", "start TermService", out code);
        if (code == 0)
            Console.WriteLine("      service: TermService started");
        else if (start.IndexOf("already", StringComparison.OrdinalIgnoreCase) >= 0 ||
                 start.IndexOf("already been started", StringComparison.OrdinalIgnoreCase) >= 0)
            Console.WriteLine("      service: TermService already running");
        else
            Console.WriteLine("      service: " + start.Trim());

        Console.WriteLine("      local IPv4: " + LocalIPv4());
        Console.WriteLine();
    }

    static void DisableRdp()
    {
        Console.WriteLine("[off] Closing Remote Desktop access...");
        try
        {
            Registry.SetValue(@"HKEY_LOCAL_MACHINE\" + TsKey, "fDenyTSConnections", 1, RegistryValueKind.DWord);
            Console.WriteLine("      registry: fDenyTSConnections = 1");
        }
        catch (Exception ex)
        {
            Console.WriteLine("      registry error: " + ex.Message);
        }

        int code;
        string del = Run("netsh.exe", "advfirewall firewall delete rule name=\"" + RuleName + "\"", out code);
        Console.WriteLine(code == 0
            ? "      firewall: rule " + RuleName + " removed"
            : "      firewall: " + del.Trim());
        Console.WriteLine("      TermService left running (stopping it would drop active sessions).");
        Console.WriteLine();
    }

    static void ReadCards()
    {
        Console.WriteLine("[2/3] Reading smart card readers and certificates...");
        Console.WriteLine("      (this reads certificates/ATR only; it does not ask for a PIN)");
        Console.WriteLine();
        int code;
        string output = Run("certutil.exe", "-scinfo", out code);
        Console.Write(output);
        Console.WriteLine();
        if (code != 0)
            Console.WriteLine("certutil exit code: " + code);

        string path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            "smartcard-info.txt");
        if (path.Length == 0)
            path = "smartcard-info.txt";
        try
        {
            File.WriteAllText(path, output, Encoding.Default);
            Console.WriteLine();
            Console.WriteLine("[3/3] Saved to: " + path);
        }
        catch (Exception ex)
        {
            Console.WriteLine("Could not save report: " + ex.Message);
        }
    }

    static string LocalIPv4()
    {
        try
        {
            IPAddress[] addresses = Dns.GetHostAddresses(Dns.GetHostName());
            foreach (IPAddress address in addresses)
            {
                if (address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                    return address.ToString();
            }
        }
        catch (Exception)
        {
        }
        return "unknown";
    }

    static void ShowUsage()
    {
        Console.WriteLine("Usage:");
        Console.WriteLine("  SmartCardRdp.exe        enable RDP on 3389 and read smart card info");
        Console.WriteLine("  SmartCardRdp.exe off    close RDP access again");
        Console.WriteLine();
        Console.WriteLine("The report is written to the desktop as smartcard-info.txt.");
    }

    static void Pause()
    {
        Console.WriteLine();
        Console.Write("Press Enter to close...");
        Console.ReadLine();
    }
}
