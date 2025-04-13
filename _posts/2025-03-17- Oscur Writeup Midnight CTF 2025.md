---
title: Oscur Writeup Reverse Engineering Midnight CTF 2025
date: 2025-04-13 21:33:21 +1
categories: [CTF, Reverse]
tags: [CTF, Writeup, Midnight, Reverse]
---

# Oscur Writeup - Reverse Engineering Challenge - Midnight CTF 2025

## Introduction

We are given a PE file:

Click here to download it:
[Oscur.exe](https://github.com/WinDyAlphA/miscDownloads/raw/refs/heads/main/Oscur.exe)

## Initial Analysis 

Let's start by analyzing the main function:

![Oscur.exe main](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/OscurPE_main.png)

There's a bunch of puts and sleep calls that aren't very interesting. We notice a VirtualAlloc and a memcopy, which looks like typical malware behavior. What's interesting is that the memcopy function takes 3 arguments: destination, source, and size.

Here we have a source that starts with "MZ" and has a significant size (0xd1600).

## Discovering Hidden PE File

Let's examine what data is being copied into the process memory:

![Oscur.exe PE](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/OscurPE_PE.png)

There's a bunch of data here. At first glance, nothing seems particularly interesting, but remember when I mentioned the data starts with "MZ"? We can see that along with several ASCII characters like 'text' or 'data'.

According to the [Wikipedia page on file signatures](https://en.wikipedia.org/wiki/List_of_file_signatures), files starting with the magic bytes "MZ" are DOS MZ executables and their descendants (including NE and PE).

## Extracting the Hidden Executable

So what's next? We need to decompile this data. I exported the data in hex dump format and wrote a script to rebuild the DOS MZ executable:

```python
with open('reverse/PE.txt', 'r') as f:
    hex_data = f.read().strip()

binary_data = bytes.fromhex(hex_data)

with open('reconstructed.exe', 'wb') as f:
    f.write(binary_data)

print("YAY!")
```

Now I have another .exe to decompile!

## Analyzing the Second PE File

After searching through this new PE file, I found an interesting function:

![MessageBox Creation](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/revmid1.png)

The text in this message box is identified as lpText, so let's analyze what is supposed to be printed, starting with the function that I renamed bytes_arr (because I already know what it does).

![Reverse 2](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/revmid2.png)

Obviously, the bytes_arr function creates... a bytes array. The bytes are:
```
0x7a, 0x32, 0x8f, 0xb9, 0x52, 0x8f, '!', 'b', 'T', '<', 0xb4, 0x91, 0x6f, 0x8b, 0x04, 0x70, 0x37
```

This looks like a secret key. Don't bother reversing the last part of the code - it's just junk meant to waste our time.

## Digging Deeper into the Functions

Let's analyze the function 'sus_func_wrapper' that takes this bytes_arr as a parameter:

![Reverse 3](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/revmid3.png)

As the name suggests, this is just a wrapper - pretty useless. Let's go deeper:

![Reverse 4](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/revmid4.png)

Now we're getting somewhere! This function 'sus_func':

1. Reads a byte at address arg1 + 0x11 and zero-extends it to uint64_t
2. If this byte is non-zero:
   - Calls even_more_sus_func(arg1, 0x11, 0xd53df29ffdb7137)
   - Sets result = arg1
   - Clears the byte at address arg1 + 0x11 by setting it to 0
3. Returns result

Let's now analyze what 'even_more_sus_func' does:

![Reverse 5](https://raw.githubusercontent.com/WinDyAlphA/miscDownloads/refs/heads/main/revmid5.png)

The function 'even_more_sus_func' takes three int64_t parameters and returns a void pointer:

- Initializes i to nullptr (zero)
- Loops while i is less than arg2 (0x11)
- For each iteration:
  - Performs a XOR operation: `*(i + arg1) ^= (arg3 >> ((zx.q(i.d) & 7) << 3)).b`
  - This XORs memory at address i + arg1 with a byte from arg3 shifted by a value derived from the current position
- Increments i by 1 each iteration
- Returns the final value of i

This is likely a simple encryption/decryption function that transforms a memory region using a rotating 8-byte key pattern (the & 7 part) from arg3 (the hardcoded hex value) as the key.

## Putting the Pieces Together

So we have all the pieces now. The bytes:
```
0x7a, 0x32, 0x8f, 0xb9, 0x52, 0x8f, '!', 'b', 'T', '<', 0xb4, 0x91, 0x6f, 0x8b, 0x04, 0x70, 0x37
```
are XORed with the key `0xd53df29ffdb7137` using the full key length with the rotating pattern.

## Decrypting the Flag

I wrote a simple script to decrypt the message:

```python
encrypted = [0x7a, 0x32, 0x8f, 0xb9, 0x52, 0x8f, ord('!'), ord('b'), ord('T'), ord('<'), 0xb4, 0x91, 0x6f, 0x8b, 0x04, 0x70, 0x37]

key = 0xd53df29ffdb7137

flag = ""
for i in range(len(encrypted)):
    # 8 bits
    shift = (i & 7) << 3
    key_byte = (key >> shift) & 0xFF
    
    # XOR
    decrypted = encrypted[i] ^ key_byte
    
    # add to flag
    flag += chr(decrypted)

print("Flag:", flag)
```

And with that, I obtained the flag:
```
Flag: MCTF{ProcMonFTW}
```

## Conclusion

This was a really great challenge! I loved the nested file concept - having a PE file hidden inside another PE file was a clever touch. It took me some time to understand everything properly in the second PE file, but the puzzle pieces came together nicely in the end.

The challenge involved several key reverse engineering concepts:
- File format analysis
- Hidden payload extraction
- Function analysis
- Simple cryptography (XOR encryption)
- Script-based decryption

--- 

Thanks for reading, see you next time!!!