---
title: "ClrDeOxide: Execute-Assembly in Rust with a real AMSI bypass"
date: 2026-02-24 19:00:00 +0100
categories: [Maldev, C2]
tags: [Maldev, Rust, AMSI, CLR, .NET, C2]
---

Remember my last news post where I said I'd drop an execute-assembly PoC in Rust? Well, it's out.

→ **[PoC-ClrDeOxide](https://github.com/WinDyAlphA/PoC-ClrDeOxide)** + **[clroxide fork](https://github.com/WinDyAlphA/clroxide)**

This is a follow-up to my [previous post](/posts/News) where I teased the execute-assembly module I was building for the C2. Let me explain what I actually built.

---

## The problem with "standard" execute-assembly

The classic approach, used by most C2s to this day, is `AppDomain.Load(byte[])`. In COM vtable terms, this is `Load_3`. Simple, effective, and... yet fully instrumented by AMSI.

When you call `Load_3`, AMSI gets a direct look at your assembly bytes before CLR even touches them. Any AMSI provider (Defender, third-party EDR, doesn't matter) gets a clean shot at scanning your Rubeus or your Seatbelt in memory. You can patch `AmsiScanBuffer`, sure, but that leaves Copy-on-Write artifacts in `.text` that defenders love to catch. Hardware breakpoint hooks? Same story, just at a different level.

The IBM X-Force team published a great research piece on this: [Being a Good CLR Host](https://www.ibm.com/think/x-force/being-a-good-clr-host-modernizing-offensive-net-tradecraft). The short version: AMSI only instruments `Load_3`. There are other methods in the `_AppDomain` COM interface. One of them is `Load_2`.

---

## The technique: IHostAssemblyStore + Load_2

`Load_2` takes an **identity string** instead of a raw byte array:

```
"Rubeus, Version=1.6.4.0, Culture=neutral, PublicKeyToken=null"
```

Normally, this would require the assembly to be on disk. But if you register a custom `IHostAssemblyStore` with the CLR **before starting the runtime**, something interesting happens: every time the CLR needs to resolve an assembly it can't find, it calls **your** `ProvideAssembly` callback and asks you for the bytes.

The flow looks like this:

```
AppDomain.Load_2(identity_string)
         ↓
CLR → IHostAssemblyStore::ProvideAssembly(identity)
         ↓
You return an IStream wrapping your in-memory bytes
         ↓
CLR loads the assembly, AMSI never sees the bytes
```

Because from AMSI's perspective, `Load_2` is a disk-based load. It doesn't scan it. AMSI.dll doesn't even get loaded into the process.

This is the technique I implemented in Rust. Let me walk you through it.

---

## Implementation in Rust

The whole thing lives in my [clroxide fork](https://github.com/WinDyAlphA/clroxide). The upstream `clroxide` by b4rtik is a solid library for hosting the CLR from Rust, but it only had `Load_3`. I added the full AMSI bypass on top of it.

### Step 1: Register IHostControl before Start()

The critical constraint: `SetHostControl` must be called **before** `ICLRRuntimeHost::Start()`. Miss this window and you get `E_ACCESSDENIED (0x80070005)`. The CLR is strict about this, once it's running, it won't let you register host managers anymore.

```rust
// Order matters, bypass context first, then redirect output
let mut bypass_loader = AmsiBypassLoader::new();
let mut clr = Clr::new(assembly_bytes, args)?;
clr.run_with_amsi_bypass_auto(&mut bypass_loader)?
```

### Step 2: Automatic identity extraction

Here's the part I'm actually proud of. The `Load_2` call requires an identity string that exactly matches the assembly's embedded metadata. Something like:

```
Rubeus, Version=1.6.4.0, Culture=neutral, PublicKeyToken=null
```

Rather than making the caller hardcoded this manually (which is annoying and error-prone), I wrote a **pure Rust PE metadata parser** that extracts it automatically from the raw bytes. No CLR calls, no P/Invoke, nothing, just raw byte walking from the DOS header down to the metadata tables.

Here's how it works step by step.

#### Level 1 - The PE headers

A .NET assembly is a regular PE file (`.exe` or `.dll`). We start there:

```
Offset 0x00:  MZ header (DOS stub)
              └─ e_lfanew at offset 0x3C → points to "PE\0\0" signature
                 └─ COFF header (20 bytes): machine, number of sections, etc.
                    └─ Optional Header → DataDirectory[16]
```

The `DataDirectory` array in the Optional Header is the key, each entry is a `(RVA, Size)` pair pointing to a specific structure inside the PE file. Entry **[14]** is the **COM+ / CLI descriptor** (also called the COR20 header), which is where .NET metadata lives.

#### Level 2 - The CLI header

We resolve RVA from `DataDirectory[14]` to a file offset (by walking the section headers to find which section contains that RVA), then read the `IMAGE_COR20_HEADER`:

```
struct IMAGE_COR20_HEADER {
    cb: u32,                   // size of this header
    MajorRuntimeVersion: u16,
    MinorRuntimeVersion: u16,
    MetaData: IMAGE_DATA_DIRECTORY,  // ← RVA + Size of the metadata blob
    Flags: u32,
    EntryPointToken: u32,
    ...
}
```

The `MetaData` field gives us another RVA, this one points to the **metadata root**.

#### Level 3 - The metadata root (BSJB)

The metadata root starts with the magic number `0x424A5342` (ASCII: `BSJB`). This is the signature defined by the ECMA-335. Right after comes the version string ("v4.0.30319" or similar), then a list of **stream headers**:

```
BSJB magic (4 bytes)
MajorVersion, MinorVersion (2+2 bytes)
Reserved (4 bytes)
Version string length + string (variable)
Flags (2 bytes)
StreamCount (2 bytes)
─────────────────────────────────────────
Stream[0]: { offset, size, name="#~"      }  ← table stream
Stream[1]: { offset, size, name="#Strings"}  ← string heap
Stream[2]: { offset, size, name="#US"     }  ← user strings
Stream[3]: { offset, size, name="#Blob"   }  ← blob heap
Stream[4]: { offset, size, name="#GUID"   }  ← GUID heap
```

We locate the three streams we care about: `#~`, `#Strings`, and `#Blob`.

#### Level 4 - The `#~` table stream → AssemblyDef

The `#~` stream contains all the metadata tables (types, methods, fields, assemblies, etc.). Each table is described by a bitmask in the stream header that tells you which tables are present and how many rows each one has. This matters because **column sizes are dynamic**, an index into `#Strings` can be 2 or 4 bytes depending on how large the heap is. ECMA-335 specifies exact rules for this

We navigate to **table 0x20 - `AssemblyDef`**. There's always exactly one row (an assembly declares itself once). The row layout is:

```
HashAlgId:      u32
MajorVersion:   u16
MinorVersion:   u16
BuildNumber:    u16
RevisionNumber: u16
Flags:          u32
PublicKey:      BlobIndex   (2 or 4 bytes → into #Blob)
Name:           StringIndex (2 or 4 bytes → into #Strings)
Culture:        StringIndex (2 or 4 bytes → into #Strings)
```

From this single row we get everything that we need.

#### Level 5 - Reading the name and computing the PublicKeyToken

**Name** is a string index into `#Strings`. We resolve it → `"Rubeus"`.

**Version** is right there in the row → `1.6.4.0`.

**Culture** is a string index → usually `"neutral"`.

**PublicKeyToken** is the interesting one. The `PublicKey` index points into `#Blob`. If it's zero-length, the token is `null` (unsigned assembly). If there's a key, the token is computed as:

```
SHA-1(public_key_bytes) → 20 bytes
take the last 8 bytes
reverse them
encode as lowercase hex
→ "03d6b00db3753d4a" (or whatever)
```

All of this is done in pure Rust with no external dependencies. At the end, we format the identity string and hand it to `Load_2`.

### Step 3: Handling CLR identity normalization

This one was a fun bug to track down. The CLR **normalizes** the identity string before passingit to `ProvideAssembly`. So you register:

```
Rubeus, Version=1.6.4.0, Culture=neutral, PublicKeyToken=null
```

But `ProvideAssembly` receives:

```
Rubeus, Version=1.6.4.0, Culture=neutral, PublicKeyToken=null, processorArchitecture=MSIL
```

An exact lookup fails → CLR falls back to disk → `HRESULT(0x8007000B) ERROR_BAD_FORMAT`. Not great.

The fix: `AssemblyStorage::find_by_simple_name()` does a case-insensitive lookup by just the assembly name (everything before the first comma) as a fallback. Solves it cleanly.

### Step 4: Output capture

`Console.Out` and `Console.Error` are redirected via reflection, we swap them out for a `System.IO.StringWriter` before the entrypoint runs, then read back the output afterward. The assembly runs thinking it's writing to a real console; we capture everything.

---

## The PoC

The actual PoC is intentionally minimal. Here's the entire execute-assembly logic:

```rust
use clroxide::clr::Clr;
use clroxide::primitives::AmsiBypassLoader;

static RUBEUS_BYTES: &[u8] = include_bytes!("../Rubeus464.exe");

fn execute_assembly(assembly: Vec<u8>, args: Vec<String>) -> String {
    let mut bypass_loader = AmsiBypassLoader::new();
    let mut clr = Clr::new(assembly, args).unwrap();
    clr.run_with_amsi_bypass_auto(&mut bypass_loader).unwrap()
}

fn main() {
    let args = vec!["kerberoast".to_string(), "/stats".to_string()];
    let output = execute_assembly(RUBEUS_BYTES.to_vec(), args);
    println!("{}", output);
}
```

`Rubeus464.exe` is embedded at compile time via `include_bytes!`, it's never written to disk. The resulting binary cross-compiles cleanly from Linux to Windows x64:

```bash
cargo build --release --target x86_64-pc-windows-gnu
```

Single statically-linked executable. Only external dependency is `mscoree.dll` , which is present on any Windows machine with .NET installed !

---

## OPSEC note

One important note: `SetHostControl` only works on the first CLR initialization in a process. If the CLR is already running (e.g., second execute-assembly in the same implant process), `SetHostControl` return `E_ACCESSDENIED` and we fall back to loading on the existing AppDomain, without the `IHostAssemblyStore` bypass.

Implication: **for a guaranteed bypass on every run, each execute-assembly should happen in a fresh CLR process** (via injection or process spawn). This is exactly how it's handled in the C2 I'm building, one CLR context per run, no reuse.

---

## What's next

This is a building block for the bigger project I mentioned in my previous post. The C2 is progressing well, execute-assembly is working.

In the meantime, the code is public. Go break things with it.

**[PoC-ClrDeOxide →](https://github.com/WinDyAlphA/PoC-ClrDeOxide)**  
**[clroxide fork →](https://github.com/WinDyAlphA/clroxide)**

Thanks for reading.
