# Matter On/Off Light Device Type - Required Clusters

> Based on the **Matter Device Library Specification** (CSA)  
> Updated for **Matter 1.3+** (current specification as of 2024)

## Device Classification

| Property | Value |
|----------|-------|
| **Device Type ID** | `0x0100` |
| **Device Name** | On/Off Light |
| **Class** | Simple |
| **Scope** | Endpoint |

---

## Required Clusters Overview

A Matter On/Off Light device requires clusters on **two endpoints**:

1. **Endpoint 0** - Root Node (utility clusters for device management)
2. **Endpoint 1+** - Application endpoint (On/Off Light functionality)

---

## Endpoint 0: Root Node Device Type (`0x0016`)

Every Matter device must have Endpoint 0 implementing the Root Node device type. This endpoint contains utility clusters for commissioning, diagnostics, and device management.

### Mandatory Clusters

| Cluster ID | Cluster Name | Client/Server | Notes |
|------------|--------------|---------------|-------|
| `0x001D` | Descriptor | Server | Lists endpoints and device types |
| `0x0028` | Basic Information | Server | Manufacturer info, firmware version, etc. |
| `0x001F` | Access Control | Server | ACL management |
| `0x003F` | Group Key Management | Server | Security key management |
| `0x0030` | General Commissioning | Server | Commission the device |
| `0x0031` | Network Commissioning | Server | Wi-Fi/Thread network setup |
| `0x003C` | Administrator Commissioning | Server | Admin commissioning window |
| `0x003E` | Node Operational Credentials | Server | Certificates and credentials |
| `0x0033` | General Diagnostics | Server | Device health and diagnostics |

### Conditional/Optional Clusters

| Cluster ID | Cluster Name | Client/Server | Condition |
|------------|--------------|---------------|-----------|
| `0x002E` | Power Source Configuration | Server | Optional |
| `0x0038` | Time Synchronization | Server | Optional |
| `0x002B` | Localization Configuration | Server | If language locale supported |
| `0x002C` | Time Format Localization | Server | If time locale supported |
| `0x002D` | Unit Localization | Server | If unit locale supported |
| `0x0032` | Diagnostic Logs | Server | Optional |
| `0x0034` | Software Diagnostics | Server | Optional |
| `0x0037` | Ethernet Network Diagnostics | Server | If Ethernet |
| `0x0036` | Wi-Fi Network Diagnostics | Server | If Wi-Fi |
| `0x0035` | Thread Network Diagnostics | Server | If Thread |

---

## Endpoint 1+: On/Off Light Application Clusters

### Mandatory Clusters (M)

| Cluster ID | Cluster Name | Client/Server | Description |
|------------|--------------|---------------|-------------|
| `0x001D` | Descriptor | Server | Base requirement for all endpoints |
| `0x0003` | Identify | Server | Visual/audible identification |
| `0x0004` | Groups | Server | Group membership management |
| `0x0062` | Scenes Management | Server | Scene storage and recall (Matter 1.3+) |
| `0x0006` | On/Off | Server | Primary on/off control |

> ⚠️ **Note:** The old Scenes cluster (`0x0005`) was deprecated and replaced by Scenes Management (`0x0062`) in Matter 1.3. If targeting Matter 1.2 or earlier, use `0x0005`.

### Optional Clusters (O)

| Cluster ID | Cluster Name | Client/Server | Description |
|------------|--------------|---------------|-------------|
| `0x0008` | Level Control | Server | Recommended for grouping with dimmable lights |
| `0x0406` | Occupancy Sensing | Client | React to occupancy sensors |
| `0x001E` | Binding | Server | If client clusters are present |

---

## Cluster Element Requirements (Overrides)

The following element requirements override the default cluster specification:

### Identify Cluster (`0x0003`)

| Element | Name | Conformance |
|---------|------|-------------|
| Command | TriggerEffect | Mandatory |
| Feature | Query | Not required for Matter |

### Scenes Management Cluster (`0x0062`)

| Element | Name | Conformance |
|---------|------|-------------|
| Command | AddScene | Mandatory |
| Command | ViewScene | Mandatory |
| Command | RemoveScene | Mandatory |
| Command | RemoveAllScenes | Mandatory |
| Command | StoreScene | Mandatory |
| Command | RecallScene | Mandatory |
| Command | GetSceneMembership | Mandatory |
| Command | CopyScene | Optional |

> **Note:** Scenes Management in Matter 1.3+ uses a fabric-scoped scene table. Each fabric has its own isolated set of scenes.

### On/Off Cluster (`0x0006`)

| Element | Name | Conformance |
|---------|------|-------------|
| Feature | LT (Lighting) | Mandatory |

### Level Control Cluster (`0x0008`) - If Implemented

| Element | Name | Value/Conformance |
|---------|------|-------------------|
| Feature | OO (OnOff) | Mandatory |
| Feature | LT (Lighting) | Mandatory |
| Attribute | CurrentLevel | Constraint: 1 to 254 |
| Attribute | MinLevel | Value: 1 |
| Attribute | MaxLevel | Value: 254 |

> **Note:** If Level Control is implemented on an On/Off Light, it SHALL NOT affect the actual light level except for "with on/off" commands. The device only has on/off states.

---

## Implementation Notes

### Light Effects
Since an On/Off Light cannot dim, the light effects specified by:
- `TriggerEffect` command (Identify cluster)
- `OffWithEffect` command (On/Off cluster)

**MAY be replaced by pure on/off light effects** instead of dimming effects.

### Level Control Recommendation
The spec recommends including Level Control even on On/Off Lights to provide a consistent user experience when grouped with dimmable lights using "with on/off" commands.

---

## DNS-SD / mDNS Discovery Requirements

Matter uses DNS-SD (DNS-based Service Discovery) over mDNS for device discovery. The data advertised in DNS-SD records has specific relationships to cluster attributes.

### Service Types

| Service Type | Purpose | When Advertised |
|--------------|---------|-----------------|
| `_matterc._udp` | Commissionable Node Discovery | Device in commissioning mode |
| `_matter._tcp` | Operational Discovery | After commissioning (on fabric) |
| `_matterd._udp` | Commissioner Discovery | Commissioner advertising availability |

### Commissionable Discovery TXT Record Keys

| Key | Name | Description | Related Cluster/Attribute |
|-----|------|-------------|---------------------------|
| `D` | Discriminator | 12-bit device discriminator | Onboarding payload |
| `VP` | Vendor/Product | Format: `VID+PID` (e.g., `65521+32769`) | Basic Information: `VendorID`, `ProductID` |
| `DT` | Device Type | Primary device type ID | Descriptor: `DeviceTypeList` |
| `DN` | Device Name | Human-readable name | Basic Information: `NodeLabel` |
| `CM` | Commissioning Mode | 0=not in mode, 1=basic, 2=enhanced | Commissioning state |
| `RI` | Rotating Device ID | Privacy-preserving identifier | Basic Information: `UniqueID` (derived) |
| `PH` | Pairing Hint | Bitmap of pairing methods | - |
| `PI` | Pairing Instructions | URL or text instructions | - |
| `SII` | Sleepy Idle Interval | Sleep interval in ms | ICD Management cluster |
| `SAI` | Sleepy Active Interval | Active interval in ms | ICD Management cluster |
| `T` | TCP Supported | 1 if TCP supported | - |

### Commissioning Subtypes (for filtering)

Subtypes allow commissioners to filter discovery results:

| Subtype | Description | Example |
|---------|-------------|---------|
| `_L<discriminator>` | Long (12-bit) discriminator | `_L3840` |
| `_S<short>` | Short (4-bit) discriminator | `_S15` |
| `_V<vendor>` | Vendor ID | `_V65521` |
| `_T<type>` | Device Type | `_T256` (On/Off Light = 0x0100) |
| `_CM` | Currently in Commissioning Mode | `_CM` |

### Data Consistency Requirements

#### Mandatory Consistency

The following data MUST be consistent across all sources:

| Data | DNS-SD TXT | Cluster | Certification Declaration | DAC |
|------|------------|---------|---------------------------|-----|
| Vendor ID | `VP` (first part) | Basic Information `VendorID` | `vendor_id` | Subject DN |
| Product ID | `VP` (second part) | Basic Information `ProductID` | `product_id_array` | Subject DN (if present) |

> ⚠️ **Critical:** The Certification Declaration's `vendor_id` SHALL match the Basic Information cluster's `VendorID` attribute. The `product_id_array` SHALL contain the `ProductID` attribute value. Mismatches will cause Device Attestation to fail.

#### Recommended Consistency

| DNS-SD Key | Should Match Cluster Attribute |
|------------|-------------------------------|
| `DT` | Descriptor cluster `DeviceTypeList` on root endpoint |
| `DN` | Basic Information `NodeLabel` attribute |

#### Authoritative Data Source

During commissioning, the **cluster attributes are authoritative**:

1. Commissioner discovers device via DNS-SD (TXT records provide hints)
2. Commissioner establishes PASE session
3. Commissioner **reads cluster attributes directly** for authoritative data:
   - Basic Information cluster for VID, PID, serial number, etc.
   - Descriptor cluster for device types and endpoint structure
4. Device Attestation validates consistency with CD and DAC certificates

### Implementation Notes for DNS-SD

1. **Update advertisements when cluster data changes**: If `NodeLabel` is updated, the `DN` TXT record should be updated
2. **Thread devices use SRP**: Thread devices register with the Thread Border Router's SRP server, which proxies mDNS
3. **Extended Discovery**: Devices MAY continue advertising `_matterc._udp` even when not in commissioning mode (privacy considerations apply)
4. **IPv6 Required**: All AAAA records must include IPv6 addresses; IPv4 is optional

### Example DNS-SD Advertisement

For an On/Off Light entering commissioning mode:

```
Instance: 19CAC273B02ADDF2._matterc._udp.local
SRV: 0 0 5540 A5F15790B0D15F32.local
TXT: D=3840 VP=65521+32769 DT=256 CM=1 DN=Kitchen Light
AAAA: fe80::a7f1:5790:b0d1:5f32
```

Subtypes registered:
- `_L3840._sub._matterc._udp.local`
- `_S15._sub._matterc._udp.local`
- `_V65521._sub._matterc._udp.local`
- `_T256._sub._matterc._udp.local`
- `_CM._sub._matterc._udp.local`

---

## Cluster Summary Table

| Endpoint | Cluster ID | Cluster Name | Required |
|----------|------------|--------------|----------|
| 0 | `0x001D` | Descriptor | ✅ Yes |
| 0 | `0x0028` | Basic Information | ✅ Yes |
| 0 | `0x001F` | Access Control | ✅ Yes |
| 0 | `0x003F` | Group Key Management | ✅ Yes |
| 0 | `0x0030` | General Commissioning | ✅ Yes |
| 0 | `0x0031` | Network Commissioning | ✅ Yes* |
| 0 | `0x003C` | Administrator Commissioning | ✅ Yes |
| 0 | `0x003E` | Node Operational Credentials | ✅ Yes |
| 0 | `0x0033` | General Diagnostics | ✅ Yes |
| 1 | `0x001D` | Descriptor | ✅ Yes |
| 1 | `0x0003` | Identify | ✅ Yes |
| 1 | `0x0004` | Groups | ✅ Yes |
| 1 | `0x0062` | Scenes Management | ✅ Yes |
| 1 | `0x0006` | On/Off | ✅ Yes |
| 1 | `0x0008` | Level Control | ⚪ Optional |
| 1 | `0x0406` | Occupancy Sensing (Client) | ⚪ Optional |

\* Unless using custom/out-of-band network configuration

---

## References

1. **Matter Device Library Specification v1.3**  
   CSA Document, May 2024  
   Section 4.1 "On/Off Light"  
   https://csa-iot.org/developer-resource/specifications-download-request/

2. **Matter Application Cluster Specification v1.3**  
   Section 1.4 "Scenes Management Cluster"  
   Defines cluster attributes, commands, and events  
   https://csa-iot.org/developer-resource/specifications-download-request/

3. **Matter Core Specification v1.3**  
   Chapter 4: Discovery (DNS-SD, mDNS, BLE)  
   Chapter 5: Commissioning  
   Chapter 6: Device Attestation  
   Chapter 7: Data Model Specification  
   Chapter 9: System Model Specification  
   https://csa-iot.org/developer-resource/specifications-download-request/

4. **Matter SDK (Open Source)**  
   Reference implementation  
   https://github.com/project-chip/connectedhomeip

5. **Matter 1.3 Release Announcement**  
   https://csa-iot.org/newsroom/matter-1-3-specification-released/

6. **RFC 6762 - Multicast DNS**  
   https://datatracker.ietf.org/doc/html/rfc6762

7. **RFC 6763 - DNS-Based Service Discovery**  
   https://datatracker.ietf.org/doc/html/rfc6763

---

## Version History

| Cluster | Matter 1.0-1.2 | Matter 1.3+ |
|---------|----------------|-------------|
| Scenes | `0x0005` (provisional) | Deprecated |
| Scenes Management | N/A | `0x0062` (mandatory for lighting) |

---

## Quick Start Checklist

For a minimal Matter On/Off Light implementation:

### Clusters
- [ ] Endpoint 0 with Root Node device type and all mandatory utility clusters
- [ ] Endpoint 1 with On/Off Light device type (`0x0100`)
- [ ] Descriptor cluster on both endpoints
- [ ] Identify cluster (server) with TriggerEffect command
- [ ] Groups cluster (server)
- [ ] Scenes Management cluster (server) - Matter 1.3+
- [ ] On/Off cluster (server) with LT feature
- [ ] Proper DeviceTypeList in Descriptor cluster

### DNS-SD / mDNS
- [ ] Implement `_matterc._udp` service for commissionable discovery
- [ ] Implement `_matter._tcp` service for operational discovery
- [ ] Ensure VP TXT record matches Basic Information VendorID/ProductID
- [ ] Ensure DT TXT record matches Descriptor DeviceTypeList (device type `0x0100`)
- [ ] Register appropriate subtypes (`_L`, `_S`, `_V`, `_T`, `_CM`)
- [ ] For Thread: implement SRP registration with border router

### Data Consistency
- [ ] VendorID consistent across: Basic Information cluster, CD, DAC, DNS-SD VP
- [ ] ProductID consistent across: Basic Information cluster, CD, DAC, DNS-SD VP
- [ ] DeviceTypeList includes On/Off Light (`0x0100`) on application endpoint
