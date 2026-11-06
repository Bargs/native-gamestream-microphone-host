using System;
using System.Runtime.InteropServices;
public static class NativePatchSafety {
 [DllImport("kernel32",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr process,IntPtr address,byte[] data,UIntPtr size,out UIntPtr count);
 [DllImport("kernel32",SetLastError=true)] static extern bool WriteProcessMemory(IntPtr process,IntPtr address,byte[] data,UIntPtr size,out UIntPtr count);
 [DllImport("kernel32",SetLastError=true)] static extern bool VirtualProtectEx(IntPtr process,IntPtr address,UIntPtr size,uint protect,out uint old);
 [DllImport("kernel32",SetLastError=true)] static extern bool FlushInstructionCache(IntPtr process,IntPtr address,UIntPtr size);
 [DllImport("kernel32",SetLastError=true)] static extern bool DuplicateHandle(IntPtr sourceProcess,IntPtr source,IntPtr targetProcess,out IntPtr target,uint access,bool inherit,uint options);
 [DllImport("kernel32")] static extern IntPtr GetCurrentProcess();
 [DllImport("kernel32",SetLastError=true)] static extern bool CloseHandle(IntPtr handle);
 public static bool Equal(byte[] left,byte[] right) {
  if(left==null||right==null||left.Length!=right.Length)return false;
  for(int i=0;i<left.Length;i++)if(left[i]!=right[i])return false;
  return true;
 }
 public static void CloseUnusedRemoteDuplicate(IntPtr target,IntPtr handle) {
  IntPtr local;
  // CLOSE_SOURCE | SAME_ACCESS: only before any instruction-write attempt.
  if(!DuplicateHandle(target,handle,GetCurrentProcess(),out local,0,false,3))throw new Exception("Unused remote duplicate cleanup failed="+Marshal.GetLastWin32Error());
  if(!CloseHandle(local))throw new Exception("Local duplicate cleanup failed="+Marshal.GetLastWin32Error());
 }
 public static void Replace(IntPtr process,IntPtr address,byte[] expected,byte[] patch,out bool writeAttempted) {
  writeAttempted=false;
  if(expected.Length!=patch.Length)throw new ArgumentException("Patch size differs");
  UIntPtr count;var current=new byte[expected.Length];
  if(!ReadProcessMemory(process,address,current,(UIntPtr)current.Length,out count)||count.ToUInt64()!=(ulong)current.Length||!Equal(current,expected))throw new Exception("Runtime instructions changed before patch");
  uint old;
  if(!VirtualProtectEx(process,address,(UIntPtr)patch.Length,0x40,out old))throw new Exception("Runtime protection change failed="+Marshal.GetLastWin32Error());
  Exception failure=null;
  try {
   writeAttempted=true;
   if(!WriteProcessMemory(process,address,patch,(UIntPtr)patch.Length,out count)||count.ToUInt64()!=(ulong)patch.Length)throw new Exception("Runtime write failed or partial; restart vendor processes before retry");
   if(!FlushInstructionCache(process,address,(UIntPtr)patch.Length))throw new Exception("Instruction cache flush failed; restart vendor processes before retry");
   current=new byte[patch.Length];
   if(!ReadProcessMemory(process,address,current,(UIntPtr)current.Length,out count)||count.ToUInt64()!=(ulong)current.Length||!Equal(current,patch))throw new Exception("Runtime patch readback differs; restart vendor processes before retry");
  }catch(Exception e){failure=e;}
  uint ignored;
  if(!VirtualProtectEx(process,address,(UIntPtr)patch.Length,old,out ignored))throw new Exception("Runtime protection restoration failed; restart vendor processes before retry",failure);
  if(failure!=null)throw failure;
  // This is verified, not atomic: executing target threads are not suspended.
 }
}
