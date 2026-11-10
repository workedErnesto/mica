using System.Runtime.InteropServices;
using System.Runtime.InteropServices.Marshalling;
using Mica.Core;

namespace Mica.App;

/// <summary>Right click on mica in the taskbar lists every profile (macOS Dock menu). mica is not a packaged app, so the
/// WinRT JumpList is unavailable and the list is written through the shell's ICustomDestinationList. Each entry starts
/// mica with --profile=id; the running copy brings that profile's window forward or opens one.</summary>
public static partial class JumpList
{
    public const string Argument = "--profile=";

    public static Guid? ProfileArgument(IEnumerable<string> arguments) =>
        arguments.FirstOrDefault(a => a.StartsWith(Argument, StringComparison.Ordinal)) is { } value && Guid.TryParse(value[Argument.Length..], out var id) ? id : null;

    public static void Update(Store store)
    {
        if (Program.QA || !OperatingSystem.IsWindows()) return;
        try { Commit(store); }
        catch (Exception e) when (e is COMException or InvalidCastException or EntryPointNotFoundException or DllNotFoundException) { Diagnostics.Log.Error(e); }
    }

    static void Commit(Store store)
    {
        if (Environment.ProcessPath is not { } exe) return;
        var wrappers = new StrategyBasedComWrappers();
        var owned = new List<nint>();
        T Wrap<T>(nint pointer) { owned.Add(pointer); return (T)wrappers.GetOrCreateObjectForComInstance(pointer, CreateObjectFlags.UniqueInstance); }
        try
        {
            var list = Wrap<ICustomDestinationList>(Create(ClsidDestinationList, typeof(ICustomDestinationList).GUID));
            var arrayId = typeof(IObjectArray).GUID;
            list.BeginList(out _, ref arrayId, out var removed);
            if (removed != 0) Marshal.Release(removed);
            var collectionPointer = Create(ClsidObjectCollection, typeof(IObjectCollection).GUID);
            var collection = Wrap<IObjectCollection>(collectionPointer);
            foreach (var profile in store.Profiles)
            {
                var name = store.ProfileName(profile);
                var linkPointer = Create(ClsidShellLink, typeof(IShellLinkW).GUID);
                var link = Wrap<IShellLinkW>(linkPointer);
                link.SetPath(exe);
                link.SetArguments(Argument + profile.Id.ToString("D"));
                link.SetIconLocation(exe, 0);
                link.SetDescription(name);
                Marshal.ThrowExceptionForHR(Marshal.QueryInterface(linkPointer, typeof(IPropertyStore).GUID, out var propertiesPointer));
                var properties = Wrap<IPropertyStore>(propertiesPointer);
                var key = new PropertyKey(new Guid("F29F85E0-4FF9-1068-AB91-08002B27B3D9"), 2);
                var value = PropVariant.FromString(name);
                try { properties.SetValue(ref key, ref value); properties.Commit(); }
                finally { value.Free(); }
                collection.AddObject(linkPointer);
            }
            Marshal.ThrowExceptionForHR(Marshal.QueryInterface(collectionPointer, arrayId, out var arrayPointer));
            owned.Add(arrayPointer);
            list.AppendCategory(store.Text("профили", "Профили"), arrayPointer);
            list.CommitList();
        }
        finally { foreach (var pointer in owned) Marshal.Release(pointer); }
    }

    static readonly Guid ClsidDestinationList = new("77F10CF0-3DB5-4966-B520-B7C54FD35ED6");
    static readonly Guid ClsidObjectCollection = new("2D3468C1-36A7-43B6-AC24-D3F02FD9607A");
    static readonly Guid ClsidShellLink = new("00021401-0000-0000-C000-000000000046");

    static nint Create(Guid clsid, Guid iid)
    {
        Marshal.ThrowExceptionForHR(CoCreateInstance(in clsid, 0, 1 /* CLSCTX_INPROC_SERVER */, in iid, out var pointer));
        return pointer;
    }

    [LibraryImport("ole32.dll")]
    private static partial int CoCreateInstance(in Guid clsid, nint outer, uint context, in Guid iid, out nint pointer);

    [StructLayout(LayoutKind.Sequential)]
    internal struct PropertyKey(Guid format, uint id) { public Guid Format = format; public uint Id = id; }

    /// <summary>PROPVARIANT holding a VT_LPWSTR.</summary>
    [StructLayout(LayoutKind.Sequential)]
    internal struct PropVariant
    {
        public ushort Type; ushort reserved1, reserved2, reserved3; public nint Value; nint extra;
        public static PropVariant FromString(string text) => new() { Type = 31, Value = Marshal.StringToCoTaskMemUni(text) };
        public void Free() { if (Value != 0) Marshal.FreeCoTaskMem(Value); Value = 0; }
    }

    [GeneratedComInterface(StringMarshalling = StringMarshalling.Utf16), Guid("6332DEBF-87B5-4670-90C0-5E57B408A49E")]
    internal partial interface ICustomDestinationList
    {
        void SetAppID(string id);
        void BeginList(out uint minSlots, ref Guid iid, out nint removed);
        void AppendCategory(string category, nint array);
        void AppendKnownCategory(int category);
        void AddUserTasks(nint array);
        void CommitList();
        void GetRemovedDestinations(ref Guid iid, out nint array);
        void DeleteList(string id);
        void AbortList();
    }

    [GeneratedComInterface, Guid("92CA9DCD-5622-4BBA-A805-5E9F541BD8C9")]
    internal partial interface IObjectArray
    {
        void GetCount(out uint count);
        void GetAt(uint index, ref Guid iid, out nint value);
    }

    [GeneratedComInterface, Guid("5632B1A4-E38A-400A-928A-D4CD63230295")]
    internal partial interface IObjectCollection : IObjectArray
    {
        void AddObject(nint value);
        void AddFromArray(nint array);
        void RemoveObjectAt(uint index);
        void Clear();
    }

    [GeneratedComInterface(StringMarshalling = StringMarshalling.Utf16), Guid("000214F9-0000-0000-C000-000000000046")]
    internal partial interface IShellLinkW
    {
        void GetPath(nint file, int length, nint data, uint flags);
        void GetIDList(out nint list);
        void SetIDList(nint list);
        void GetDescription(nint name, int length);
        void SetDescription(string name);
        void GetWorkingDirectory(nint directory, int length);
        void SetWorkingDirectory(string directory);
        void GetArguments(nint arguments, int length);
        void SetArguments(string arguments);
        void GetHotkey(out ushort hotkey);
        void SetHotkey(ushort hotkey);
        void GetShowCmd(out int command);
        void SetShowCmd(int command);
        void GetIconLocation(nint path, int length, out int index);
        void SetIconLocation(string path, int index);
        void SetRelativePath(string path, uint reserved);
        void Resolve(nint window, uint flags);
        void SetPath(string file);
    }

    [GeneratedComInterface, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    internal partial interface IPropertyStore
    {
        void GetCount(out uint count);
        void GetAt(uint index, out PropertyKey key);
        void GetValue(ref PropertyKey key, out PropVariant value);
        void SetValue(ref PropertyKey key, ref PropVariant value);
        void Commit();
    }
}
