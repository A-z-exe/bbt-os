# Windows smart card payloads

Two small .NET 2.0 console programs for Windows 7/10/11 machines whose smart
card reader is not attached to the BBT OS VM. Both are also available from the
**Access** group in the launcher, which copies them to `~/bbt/payloads`.

## SmartCardRelay.exe - use the remote card here

The relay turns the Windows machine into a network card reader. It opens the
real Alcor reader through winscard and speaks the Virtual Smart Card Protocol
(VPCD) on TCP 35963-35964 (libifdvpcd dials one port per Lun slot):

```
Windows 7 (asre-PC)  SmartCardRelay.exe  <-- TCP 35963/35964 --  Kali vpcd
```

Run it as administrator and leave the window open:

1. adds inbound firewall rule `BBT-SmartCardRelay` for TCP 35963-35964,
   restricted to `192.168.1.158` (the VMware NAT host address the VM appears as);
2. lists the readers it can see, opens one listener per Lun slot (35963, 35964)
   and waits for Kali to connect;
3. answers power-on, reset, ATR and APDU requests from the card.

On Kali:

```
bbt-smartcard-remote setup 192.168.1.176
bbt-smartcard-remote test
```

`setup` installs `vsmartcard-vpcd`, writes `/etc/reader.conf.d/vpcd` with
`DEVICENAME 192.168.1.176:0x8C7B` (the driver dials out; `/dev/null:` would
make it listen) and restarts pcscd. `pcsc_scan -r` then lists
**BBT Remote Card**, and `opensc-tool`, `pkcs11-tool`, `pcsc_scan` and
`bbt-smartcard` operate on the real card in the Windows machine.
`bbt-smartcard-remote remove` restores the default virtual reader.

Options: `--allow=IP|any`, `--port=N`, `--slots=N`, `--no-firewall`, `off`
(delete the firewall rule). Only run it on a trusted network: `--allow=any`
lets anyone who can reach the ports use the card's APDU interface.
PIN-protected keys still need the PIN.

## SmartCardRdp.exe - enable RDP and dump card info

Run it with a double-click and accept the UAC prompt:

1. enables RDP on TCP 3389 (`fDenyTSConnections=0`, firewall rule `BBT-RDP`,
   `TermService` started) and prints the local IPv4 address;
2. runs `certutil -scinfo` and saves the output to `smartcard-info.txt` on the
   desktop;
3. waits for Enter so the output stays readable.

`SmartCardRdp.exe off` closes port 3389 again by restoring the firewall rule
state and `fDenyTSConnections=1`. `TermService` keeps running so active
sessions are not dropped.

Reading readers, ATR and certificates does not ask for a PIN; the PIN is only
needed for private-key operations. RDP requires an account with a password.

## Rebuild

```
C:\Windows\Microsoft.NET\Framework64\v3.5\csc.exe -nologo -target:exe ^
  -out:SmartCardRdp.exe -win32manifest:app.manifest SmartCardRdp.cs

C:\Windows\Microsoft.NET\Framework64\v3.5\csc.exe -nologo -target:exe ^
  -out:SmartCardRelay.exe -win32manifest:relay.manifest SmartCardRelay.cs
```

Both manifests request administrator rights, and the exes target the .NET 2.0
runtime that ships with Windows 7.
