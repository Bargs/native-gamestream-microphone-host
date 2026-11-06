using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class PermanentNativeMic {
 [StructLayout(LayoutKind.Sequential)] struct Region {public IntPtr Base,AllocationBase;public uint AllocationProtect;public UIntPtr Size;public uint State,Protect,Type;}
 [DllImport("kernel32",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr p,IntPtr a,byte[] b,UIntPtr n,out UIntPtr read);
 [DllImport("kernel32",SetLastError=true)] static extern bool WriteProcessMemory(IntPtr p,IntPtr a,byte[] b,UIntPtr n,out UIntPtr written);
 [DllImport("kernel32",SetLastError=true)] static extern UIntPtr VirtualQueryEx(IntPtr p,IntPtr a,out Region r,UIntPtr n);
 [DllImport("kernel32",SetLastError=true)] static extern bool VirtualProtectEx(IntPtr p,IntPtr a,UIntPtr n,uint protection,out uint old);
 [DllImport("kernel32",SetLastError=true)] static extern bool DuplicateHandle(IntPtr sourceProcess,IntPtr source,IntPtr targetProcess,out IntPtr target,uint access,bool inherit,uint options);
 [DllImport("kernel32")] static extern bool FlushInstructionCache(IntPtr p,IntPtr a,UIntPtr n);
 [DllImport("kernel32")] static extern bool CloseHandle(IntPtr h);
 static byte[] Read(IntPtr p,long address,int count) {
  var b=new byte[count];UIntPtr n;
  if(!ReadProcessMemory(p,new IntPtr(address),b,(UIntPtr)count,out n)||n.ToUInt64()!=(ulong)count)return null;
  return b;
 }
 static long FindControl(IntPtr source,long audioBase) {
  var matches=new Dictionary<long,long>();
  for(long cursor=0x10000;cursor<0x7FFFFFFF0000;) {
   Region region;
   if(VirtualQueryEx(source,new IntPtr(cursor),out region,(UIntPtr)Marshal.SizeOf<Region>())==UIntPtr.Zero)break;
   long start=region.Base.ToInt64(),size=(long)region.Size.ToUInt64();
   if(size<=0||start+size<=cursor)break;
   if(region.State==0x1000&&region.Type==0x20000&&(region.Protect&0x100)==0&&((region.Protect&0xFF)==4||(region.Protect&0xFF)==8)) {
    for(long offset=0;offset<size;offset+=1024*1024) {
     int count=(int)Math.Min(1024*1024+64,size-offset);var b=Read(source,start+offset,count);if(b==null)continue;
     for(int i=8;i+32<b.Length;i+=8) {
      if(BitConverter.ToUInt32(b,i)!=0x010801A8||b[i+24]!=1)continue;
      long table=BitConverter.ToInt64(b,i-8),session=BitConverter.ToInt64(b,i+16);
      if(table<0x10000||session<0x10000)continue;
      var api=Read(source,table,32);if(api==null||BitConverter.ToUInt32(api,0)!=0x010801A8)continue;
      if(BitConverter.ToInt64(api,8)!=audioBase+0x11260||BitConverter.ToInt64(api,16)!=audioBase+0x115B0)continue;
      var instance=Read(source,session,64);if(instance==null)continue;
      long handle=BitConverter.ToInt64(instance,32);
      if(handle>0&&handle<0x10000000&&handle%4==0)matches[session]=handle;
     }
    }
   }
   cursor=start+size;
  }
  if(matches.Count!=1)throw new Exception("Expected one registered NVIDIA control session; found "+matches.Count);
  foreach(var value in matches.Values)return value;
  throw new Exception("No native control handle");
 }
 public static string Apply(int sourceId,long sourceAudioBase,int targetId,long targetAudioBase,bool refresh) {
  var source=OpenProcess(0x450,false,sourceId);var target=OpenProcess(0x478,false,targetId);
  if(source==IntPtr.Zero||target==IntPtr.Zero){if(source!=IntPtr.Zero)CloseHandle(source);if(target!=IntPtr.Zero)CloseHandle(target);throw new Exception("Process access failed="+Marshal.GetLastWin32Error());}
  IntPtr duplicate=IntPtr.Zero;bool writeAttempted=false;
  try {
   long control=FindControl(source,sourceAudioBase);
   long address=targetAudioBase+0xB7E0;
   byte[] expected={0x40,0x55,0x53,0x57,0x48,0x8D,0x6C,0x24,0xB9,0x48,0x81,0xEC,0xB0,0,0,0,0x48};
   var original=Read(target,address,17);if(original==null)throw new Exception("Native mic code read failed");
   bool baseline=true;for(int i=0;i<expected.Length;i++)if(original[i]!=expected[i])baseline=false; bool legacy=original[0]==0x48&&original[1]==0xB8&&original[10]==0x48&&original[11]==0x89&&original[12]==0x41&&original[13]==0x20&&original[14]==0x31&&original[15]==0xC0&&original[16]==0xC3; if(!baseline&&!legacy)throw new Exception("Native mic instructions differ; refusing patch"); if(legacy&&!refresh)return "Existing verified native runtime hook adopted PID="+targetId;
   if(!DuplicateHandle(source,new IntPtr(control),target,out duplicate,0,false,2))throw new Exception("Control handle sharing failed="+Marshal.GetLastWin32Error());
   // After a write attempt the target may reference this handle; retain until its lifecycle ends.
   byte[] patch={0x48,0xB8,0,0,0,0,0,0,0,0,0x48,0x89,0x41,0x20,0x31,0xC0,0xC3};
   BitConverter.GetBytes(duplicate.ToInt64()).CopyTo(patch,2);
   NativePatchSafety.Replace(target,new IntPtr(address),original,patch,out writeAttempted);
   return "Native microphone control handle shared with NVIDIA streamer PID="+targetId;
  } finally{try{if(duplicate!=IntPtr.Zero&&!writeAttempted)NativePatchSafety.CloseUnusedRemoteDuplicate(target,duplicate);}finally{CloseHandle(source);CloseHandle(target);}}
 }
}
