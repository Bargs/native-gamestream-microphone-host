using System;
using System.Runtime.InteropServices;
public static class PermanentRegistration {
 [DllImport("kernel32",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr p,IntPtr address,byte[] data,UIntPtr size,out UIntPtr read);
 [DllImport("kernel32",SetLastError=true)] static extern bool WriteProcessMemory(IntPtr p,IntPtr address,byte[] data,UIntPtr size,out UIntPtr written);
 [DllImport("kernel32",SetLastError=true)] static extern bool VirtualProtectEx(IntPtr p,IntPtr address,UIntPtr size,uint protect,out uint old);
 [DllImport("kernel32",SetLastError=true)] static extern bool FlushInstructionCache(IntPtr p,IntPtr address,UIntPtr size);
 [DllImport("kernel32")] static extern bool CloseHandle(IntPtr p);
 public static void Enable(int pid,IntPtr moduleBase) {
  var p=OpenProcess(0x438,false,pid);
  if(p==IntPtr.Zero) throw new Exception("OpenProcess error="+Marshal.GetLastWin32Error());
  try {
   var address=new IntPtr(moduleBase.ToInt64()+0xD6D1C);
   var original=new byte[3]; UIntPtr count;
   if(!ReadProcessMemory(p,address,original,(UIntPtr)3,out count) || count.ToUInt64()!=3) throw new Exception("Read failed");
   if(original[0]==0x40 && original[1]==0xB5 && original[2]==0x01)return; if(original[0]!=0x40 || original[1]!=0x32 || original[2]!=0xED) throw new Exception("Original runtime instructions differ; patch refused");
   bool writeAttempted;
   NativePatchSafety.Replace(p,address,original,new byte[]{0x40,0xB5,0x01},out writeAttempted);
  } finally {CloseHandle(p);}
 }
}
