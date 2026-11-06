using System;
using System.Diagnostics;
using System.IO;
public static class NativeMicSetup {
 public static int Main(string[] args) {
  // Convenience launcher only. No embedded vendor binary, credentials or receiver.
  // Inputs are a closed set; custom user selection is available in install.ps1.
  string mode=args.Length==0?"--dry-run":args[0];
  if(args.Length>1||(mode!="--dry-run"&&mode!="--install-experimental"&&mode!="--recover"&&mode!="--uninstall")){
   Console.Error.WriteLine("Use --dry-run, --install-experimental, --recover or --uninstall. Review README.md first.");return 2;
  }
  string root=AppDomain.CurrentDomain.BaseDirectory;
  string file=Path.Combine(root,mode=="--uninstall"?"uninstall.ps1":"install.ps1");
  if(!File.Exists(file)||root.IndexOf('"')>=0){Console.Error.WriteLine("Source package path is invalid.");return 2;}
  string extra=mode=="--dry-run"?" -DryRun":mode=="--uninstall"?"":mode=="--recover"?" -Recover -AcknowledgeExperimentalRuntime":" -AcknowledgeExperimentalRuntime";
  var info=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32\\WindowsPowerShell\\v1.0\\powershell.exe"));
  info.Arguments="-NoProfile -File \""+file+"\""+extra;
  info.WorkingDirectory=root;
  info.UseShellExecute=mode!="--dry-run";
  if(info.UseShellExecute)info.Verb="runas";
  try{using(var process=Process.Start(info)){process.WaitForExit();return process.ExitCode;}}
  catch(Exception e){Console.Error.WriteLine(e.Message);return 1;}
 }
}
