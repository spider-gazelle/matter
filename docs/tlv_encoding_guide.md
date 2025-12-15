# Matter TLV Encoding Guide

> A simple explanation of Tag-Length-Value encoding used in the Matter protocol

---

## What is TLV?

**TLV = Tag-Length-Value**

It's a way to encode structured data into bytes. Think of it like JSON, but binary.

---

## The Basic Idea

Every piece of data has three parts:

```
┌─────────┬────────┬─────────────────┐
│   Tag   │ Length │      Value      │
│ (what)  │ (size) │     (data)      │
└─────────┴────────┴─────────────────┘
```

| Part | Purpose | Example |
|------|---------|---------|
| **Tag** | Identifies what this data is (like a field name) | "temperature" |
| **Length** | How many bytes the value takes | 2 bytes |
| **Value** | The actual data | 25°C |

All numeric values in Matter TLV (integers, floats, lengths, and multi-byte tags) are encoded little-endian.

---

## Simple Example

Let's encode `temperature = 25`:

```
Tag: 0x01 (we assigned "temperature" as tag 1)
Length: 1 byte
Value: 25 (0x19 in hex)

Bytes: [01] [01] [19]
        │    │    └── Value: 25
        │    └─────── Length: 1 byte
        └──────────── Tag: 1
```

---

## Matter's TLV is Smarter

Matter combines the **tag** and **type** info into a "control byte" to save space:

```
┌──────────────────┬─────────────────┐
│   Control Byte   │      Value      │
│  (tag + type)    │     (data)      │
└──────────────────┴─────────────────┘
```

The type tells you:
- What kind of data (integer, string, bool, etc.)
- How big it is (so you don't always need explicit length)

---

## Data Types

| Type | Description | Example |
|------|-------------|---------|
| Signed Integer | 1, 2, 4, or 8 bytes | `-42` |
| Unsigned Integer | 1, 2, 4, or 8 bytes | `255` |
| Boolean | True/False | `true` |
| Float | 4 or 8 bytes | `3.14` |
| UTF-8 String | Text with length prefix | `"hello"` |
| Byte String | Raw bytes with length prefix | `0xDEADBEEF` |
| Null | No value | `null` |
| Structure | Container (like JSON object) | `{ }` |
| Array | List of items | `[ ]` |
| List | Like array but heterogeneous | `[ ]` |

---

Technically there is no universal “Length” field. The value length is either implied by the element type, explicitly encoded (strings), or determined by container boundaries

* boolean elements encode the value entirely in the element type; no value bytes follow.
* End-of-Container (0x18) is always anonymous and never followed by a tag.
* Mixed-type arrays are legal TLV but invalid Matter data (so enforce this expection)

## Structures (Like JSON Objects / Hashes)

A structure groups related fields together:

**JSON equivalent:**
```json
{
  "vendorId": 65521,
  "productId": 32769,
  "name": "Light"
}
```

**TLV encoding:**
```
[Structure Start]
  [Tag:1] [UInt16] 65521      ← vendorId
  [Tag:2] [UInt16] 32769      ← productId  
  [Tag:3] [String] "Light"    ← name
[Structure End]
```

In bytes (simplified):
```
15                    ← Start Structure
  24 01 F1 FF 01 00   ← Tag 1, UInt16, value 65521
  24 02 01 80 00 00   ← Tag 2, UInt16, value 32769
  2C 03 05 4C696768   ← Tag 3, String, len 5, "Light"
18                    ← End Structure
```

A TLV payload must have exactly one top-level element, that element is usually an anonymous structure

---

## Arrays (Lists of Same Type)

An array holds multiple items:

**JSON equivalent:**
```json
{
  "endpoints": [1, 2, 3]
}
```

**TLV encoding:**
```
[Structure Start]
  [Tag:1] [Array Start]
    [Anonymous] [UInt8] 1
    [Anonymous] [UInt8] 2
    [Anonymous] [UInt8] 3
  [Array End]
[Structure End]
```

**Key point:** Items inside arrays use **anonymous tags** (no tag number) because their position in the array identifies them.

---

## Anonymous Tags

An **anonymous tag** means "this element has no name/number."

Used when:
1. **Inside arrays** - position is the identifier
2. **Top-level elements** - when there's only one thing
3. **Lists** - heterogeneous collections

```
Regular tag:    [Tag:5] [Value]    ← "Field #5 = Value"
Anonymous tag:  [Anon]  [Value]    ← "Just a Value"
```

**Example - Array of integers:**
```
[Array Start]
  [Anon] 10    ← First item (index 0)
  [Anon] 20    ← Second item (index 1)
  [Anon] 30    ← Third item (index 2)
[Array End]
```

---

## Tag Types in Matter

Matter supports different tag formats:

| Tag Type | Size | Use Case |
|----------|------|----------|
| Anonymous | 0 bytes | Array elements, single values |
| Context-specific | 1 byte | Tags 0-255, used within structures |
| Common Profile | 2 bytes | Shared across Matter |
| Vendor Profile | 4-6 bytes | Vendor-specific extensions |

**Context-specific tags (0-255)** are most common - they're defined per-structure.

---

## Nested Structures

Structures can contain other structures:

**JSON equivalent:**
```json
{
  "device": {
    "vendor": {
      "id": 65521,
      "name": "Test"
    },
    "endpoints": [0, 1]
  }
}
```

**TLV (conceptual):**
```
[Structure Start]                    ← device
  [Tag:1] [Structure Start]          ← vendor
    [Tag:1] [UInt16] 65521           ← id
    [Tag:2] [String] "Test"          ← name
  [Structure End]
  [Tag:2] [Array Start]              ← endpoints
    [Anon] [UInt8] 0
    [Anon] [UInt8] 1
  [Array End]
[Structure End]
```

---

## Control Byte Breakdown

The first byte of each element encodes both tag type and element type:

```
┌─────────────────────────────────┐
│  Control Byte (8 bits)          │
├─────────┬───────────────────────┤
│ Tag Type│    Element Type       │
│ (3 bits)│      (5 bits)         │
└─────────┴───────────────────────┘
```

### Tag Types (upper 3 bits)

| Value | Meaning |
|-------|---------|
| `0b000` | Anonymous |
| `0b001` | Context-specific (1-byte tag follows) |
| `0b010` | Common profile (2-byte tag) |
| `0b011+` | Vendor profile |

### Element Types (lower 5 bits)

| Value | Type |
|-------|------|
| `0x00` | Signed Int, 1 byte |
| `0x01` | Signed Int, 2 bytes |
| `0x02` | Signed Int, 4 bytes |
| `0x03` | Signed Int, 8 bytes |
| `0x04` | Unsigned Int, 1 byte |
| `0x05` | Unsigned Int, 2 bytes |
| `0x06` | Unsigned Int, 4 bytes |
| `0x07` | Unsigned Int, 8 bytes |
| `0x08` | Boolean False |
| `0x09` | Boolean True |
| `0x0A` | Float, 4 bytes (single precision) |
| `0x0B` | Float, 8 bytes (double precision) |
| `0x0C` | UTF-8 String, 1-byte length |
| `0x0D` | UTF-8 String, 2-byte length |
| `0x0E` | UTF-8 String, 4-byte length |
| `0x0F` | UTF-8 String, 8-byte length |
| `0x10` | Byte String, 1-byte length |
| `0x11` | Byte String, 2-byte length |
| `0x12` | Byte String, 4-byte length |
| `0x13` | Byte String, 8-byte length |
| `0x14` | Null |
| `0x15` | Structure Start |
| `0x16` | Array Start |
| `0x17` | List Start |
| `0x18` | End of Container |

---

## Decoding the Control Byte

To decode a control byte:

```
Control Byte: 0x24

Binary: 0010 0100
        ││││ ││││
        ││││ └┴┴┴── Element type: 0x04 = Unsigned Int, 1 byte
        │└┴┴─────── Tag type: 001 = Context-specific
        └────────── (unused)

Result: Context-specific tag with 1-byte unsigned integer value
        (tag number follows in next byte)
```

### Common Control Bytes

| Byte | Meaning |
|------|---------|
| `0x00` | Anonymous signed int, 1 byte |
| `0x04` | Anonymous unsigned int, 1 byte |
| `0x08` | Anonymous boolean false |
| `0x09` | Anonymous boolean true |
| `0x14` | Anonymous null |
| `0x15` | Anonymous structure start |
| `0x16` | Anonymous array start |
| `0x17` | Anonymous list start |
| `0x18` | End of container |
| `0x24` | Context tag + unsigned int, 1 byte |
| `0x25` | Context tag + unsigned int, 2 bytes |
| `0x2C` | Context tag + UTF-8 string, 1-byte length |
| `0x30` | Context tag + byte string, 1-byte length |
| `0x35` | Context tag + structure start |
| `0x36` | Context tag + array start |

---

## Real Example: Reading Basic Information

When you read `ProductName` from Basic Information cluster:

**Response TLV:**
```
15                          ← Structure Start (anonymous)
  24 00 00                  ← Tag 0 (status), UInt8 = 0 (success)
  2C 01 0B                  ← Tag 1 (data), String, length 11
    4B 69 74 63 68 65 6E    ← "Kitchen"
    20 4C 69 67 68 74       ← " Light"
18                          ← Structure End
```

**Decoded:**
```json
{
  "status": 0,
  "data": "Kitchen Light"
}
```

**Byte-by-byte breakdown:**

| Bytes | Meaning |
|-------|---------|
| `15` | Control: Anonymous structure start |
| `24` | Control: Context tag + UInt8 |
| `00` | Tag number: 0 |
| `00` | Value: 0 (success status) |
| `2C` | Control: Context tag + String (1-byte len) |
| `01` | Tag number: 1 |
| `0B` | String length: 11 bytes |
| `4B...74` | String data: "Kitchen Light" |
| `18` | Control: End of container |

---

## Structures vs Arrays vs Lists

| Container | Tag Behavior | Type Constraint | Use Case |
|-----------|--------------|-----------------|----------|
| **Structure** | Elements have tags | Mixed types OK | Named fields (like objects) |
| **Array** | Elements are anonymous | Same type preferred | Ordered collections |
| **List** | Elements are anonymous | Mixed types OK | Heterogeneous collections |

**Structure example:**
```
{
  tag:1 → "hello",
  tag:2 → 42,
  tag:3 → true
}
```

**Array example:**
```
[10, 20, 30, 40]  ← All integers, no tags
```

**List example:**
```
["hello", 42, true, [1, 2, 3]]  ← Mixed types, no tags
```

---

## Why TLV?

| Advantage | Explanation |
|-----------|-------------|
| **Compact** | No field names, just numbers |
| **Self-describing** | Can decode without schema |
| **Extensible** | Unknown tags can be skipped |
| **Efficient** | Small integers use fewer bytes |
| **Streamable** | Can parse as bytes arrive |

**Size Comparison:**
```
JSON:  {"vendorId":65521}     = 20 bytes
TLV:   [24 01 F1 FF 01 00]    = 6 bytes
```

---

## Quick Reference

### Container Types
```
Structure: { }     → 0x15 ... 0x18
Array:     [ ]     → 0x16 ... 0x18  (anonymous elements)
List:      [ ]     → 0x17 ... 0x18  (mixed types allowed)
```

### Tag Usage
```
Tags inside structures:  Use context-specific (1-byte) tags
Tags inside arrays:      Use anonymous tags (no tag byte)
Tags inside lists:       Use anonymous tags (no tag byte)
```

### Integer Encoding (Little Endian)
```
Value: 65521 (0xFFF1)
As UInt16: F1 FF (little endian byte order)
```

---

## Encoding Examples

### Boolean
```
True:  09           ← Anonymous true
False: 08           ← Anonymous false

With tag:
True:  29 05        ← Tag 5 = true
False: 28 05        ← Tag 5 = false
```

### Integers
```
Unsigned 8-bit:   04 2A              ← Anonymous, value 42
Unsigned 16-bit:  05 F1 FF           ← Anonymous, value 65521
Unsigned 32-bit:  06 01 02 03 04     ← Anonymous, value 0x04030201

With context tag 1:
Unsigned 8-bit:   24 01 2A           ← Tag 1, value 42
Unsigned 16-bit:  25 01 F1 FF        ← Tag 1, value 65521
```

### Strings
```
"Hi":     0C 02 48 69              ← Anonymous, len 2, "Hi"
"Hello":  0C 05 48 65 6C 6C 6F     ← Anonymous, len 5, "Hello"

With context tag 3:
"Hi":     2C 03 02 48 69           ← Tag 3, len 2, "Hi"
```

### Null
```
Anonymous: 14
With tag:  34 07                   ← Tag 7 = null
```

### Empty Structure
```
15 18                              ← Structure start, end
```

### Structure with Fields
```
15                                 ← Structure start
  24 01 0A                         ← Tag 1 = 10 (UInt8)
  24 02 14                         ← Tag 2 = 20 (UInt8)
18                                 ← Structure end
```

### Array of Integers
```
16                                 ← Array start
  04 01                            ← Anonymous UInt8: 1
  04 02                            ← Anonymous UInt8: 2
  04 03                            ← Anonymous UInt8: 3
18                                 ← Array end
```

### Nested Structure
```
15                                 ← Outer structure start
  35 01                            ← Tag 1 = structure start
    24 01 2A                       ← Tag 1 = 42
  18                               ← Inner structure end
18                                 ← Outer structure end
```

---

## References

1. **Matter Core Specification**  
   Appendix A: Tag-Length-Value (TLV) Encoding Format  
   https://csa-iot.org/developer-resource/specifications-download-request/

2. **Matter SDK TLV Implementation**  
   https://github.com/project-chip/connectedhomeip/tree/master/src/lib/core

3. **CHIP TLV Format Documentation**  
   https://github.com/project-chip/connectedhomeip/blob/master/src/lib/core/TLV.h
