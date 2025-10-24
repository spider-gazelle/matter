# Matter Device API - Ergonomic Usage Guide

This guide shows how to use the simplified, ergonomic API for controlling Matter devices.

```crystal
# Clear and concise
node.invoke_command(1_u16, OnOffCluster::CLUSTER_ID, OnOffCluster::CMD_ON)
#                   ^      ^                         ^
#                   |      Named constant            Named constant
#                   Endpoint ID                     (no empty Bytes needed!)

# Even better - typed cluster access:
light = node.get_cluster!(1_u16, OnOffCluster)
light.invoke_command(OnOffCluster::CMD_ON)
light.on_off  # => true
```

## Improvements

### 1. Optional `fields` Parameter

Commands that don't need parameters no longer require passing empty Bytes:

```crystal
# With parameters
cluster.invoke_command(CMD_ON, Bytes.new(0))
endpoint.invoke_command(cluster_id, cmd_id, Bytes.new(0))
node.invoke_command(ep_id, cluster_id, cmd_id, Bytes.new(0))

# Using default parameter
cluster.invoke_command(CMD_ON)
endpoint.invoke_command(cluster_id, cmd_id)
node.invoke_command(ep_id, cluster_id, cmd_id)
```

### 2. Typed Cluster Access

Get clusters by their type instead of numeric IDs:

```crystal
if cluster = endpoint.get_cluster(OnOffCluster)  # 
  cluster.on_off  # Type-safe access
end

# Or with bang method that raises on missing:
cluster = endpoint.get_cluster!(OnOffCluster)
cluster.on_off  # Guaranteed to exist or will raise
```

### 3. Node-Level Typed Access

Access clusters through the node with type safety:

```crystal
light = node.get_cluster!(1_u16, OnOffCluster)
light.on_off  # Direct access
```

## Complete Examples

### Example 1: Simple On/Off Light Control

```crystal
# Build the device
node = MatterNode.new
endpoint_id = DataType::EndpointNumber.new(1_u16)
endpoint = Endpoint.new(endpoint_id, DeviceType.on_off_light)

# Add clusters
on_off = OnOffCluster.new(endpoint_id)
endpoint.add_cluster(on_off)
node.add_endpoint(endpoint)

# Pattern A: Direct cluster access (most ergonomic for reading state)
light = node.get_cluster!(1_u16, OnOffCluster)
puts "Light is #{light.on_off ? "on" : "off"}"

# Pattern B: Command invocation via cluster reference
light.invoke_command(OnOffCluster::CMD_ON)
puts "Light is now #{light.on_off ? "on" : "off"}"  # "on"

# Pattern C: Command invocation via node (for protocol-level control)
result = node.invoke_command(
  1_u16,
  OnOffCluster::CLUSTER_ID,
  OnOffCluster::CMD_TOGGLE
)
puts "Light is now #{light.on_off ? "on" : "off"}"  # "off"
```

### Example 2: Multi-Endpoint Device (2-Gang Switch)

```crystal
# Build a 2-gang light switch
node = MatterNode.new

# Endpoint 1: First light
ep1 = Endpoint.new(DataType::EndpointNumber.new(1_u16), DeviceType.on_off_light)
light1 = OnOffCluster.new(DataType::EndpointNumber.new(1_u16))
ep1.add_cluster(light1)

# Endpoint 2: Second light
ep2 = Endpoint.new(DataType::EndpointNumber.new(2_u16), DeviceType.on_off_light)
light2 = OnOffCluster.new(DataType::EndpointNumber.new(2_u16))
ep2.add_cluster(light2)

node.add_endpoint(ep1)
node.add_endpoint(ep2)

# Control lights independently with typed access
node.get_cluster!(1_u16, OnOffCluster).invoke_command(OnOffCluster::CMD_ON)
node.get_cluster!(2_u16, OnOffCluster).invoke_command(OnOffCluster::CMD_OFF)

puts "Light 1: #{light1.on_off}"  # true
puts "Light 2: #{light2.on_off}"  # false

# Control both at once
[1_u16, 2_u16].each do |ep_id|
  node.invoke_command(ep_id, OnOffCluster::CLUSTER_ID, OnOffCluster::CMD_ON)
end
```

### Example 3: Reading Device State

```crystal
# Get typed cluster reference
light = node.get_cluster!(1_u16, OnOffCluster)

# Read state directly from cluster (fast, type-safe)
puts light.on_off

# Or read via protocol (useful for remote/networked access)
result = node.read_attribute(
  1_u16,
  OnOffCluster::CLUSTER_ID,
  OnOffCluster::ON_OFF
)
if result.is_a?(Bytes)
  puts "On/Off: #{result[0] == 1}"
end
```

## API Summary

### Cluster-Level
```crystal
# Get cluster metadata
cluster.name                      # => "OnOff"
cluster.cluster_id.id             # => 0x0006
cluster.attributes                # => Array(AttributeMetadata)
cluster.commands                  # => Array(CommandMetadata)

# Invoke commands (fields optional for parameterless commands)
cluster.invoke_command(CMD_ON)
cluster.invoke_command(CMD_MOVE_TO_LEVEL, level_data)  # With parameters

# Read/write attributes
cluster.read_attribute(attr_id)
cluster.write_attribute(attr_id, value)

# Access state directly
cluster.on_off                    # Direct property access
```

### Endpoint-Level
```crystal
# Get clusters by ID
endpoint.get_cluster(cluster_id)         # => Cluster::Base?
endpoint.get_cluster!(cluster_id)        # => Cluster::Base (raises if missing)

# Get clusters by type (NEW!)
endpoint.get_cluster(OnOffCluster)       # => OnOffCluster?
endpoint.get_cluster!(OnOffCluster)      # => OnOffCluster (raises if missing)

# Invoke commands (fields optional)
endpoint.invoke_command(cluster_id, cmd_id)
endpoint.invoke_command(cluster_id, cmd_id, fields)

# Read/write attributes
endpoint.read_attribute(cluster_id, attr_id)
endpoint.write_attribute(cluster_id, attr_id, value)
```

### Node-Level
```crystal
# Get endpoints
node.get_endpoint(ep_id)          # => Endpoint?
node.get_endpoint!(ep_id)         # => Endpoint (raises if missing)

# Get typed clusters (NEW!)
node.get_cluster(ep_id, OnOffCluster)    # => OnOffCluster?
node.get_cluster!(ep_id, OnOffCluster)   # => OnOffCluster (raises if missing)

# Invoke commands (fields optional)
node.invoke_command(ep_id, cluster_id, cmd_id)
node.invoke_command(ep_id, cluster_id, cmd_id, fields)

# Read/write attributes
node.read_attribute(ep_id, cluster_id, attr_id)
node.write_attribute(ep_id, cluster_id, attr_id, value)
```

## Best Practices

### 1. Use Typed Cluster Access for Application Logic
```crystal
# ✅ Good - Clear and type-safe
light = node.get_cluster!(1_u16, OnOffCluster)
if light.on_off
  puts "Light is already on"
else
  light.invoke_command(OnOffCluster::CMD_ON)
end
```

### 2. Use Protocol-Level Access for Generic/Remote Operations
```crystal
# ✅ Good - When you need to work at protocol level
def control_any_cluster(node, ep_id, cluster_id, cmd_id)
  result = node.invoke_command(ep_id, cluster_id, cmd_id)
  result.is_a?(InteractionModel::Status) && result.success?
end
```

### 3. Use Named Constants Instead of Magic Numbers
```crystal
# ❌ Bad
node.invoke_command(1_u16, 0x0006_u32, 0x01_u32)

# ✅ Good
node.invoke_command(1_u16, OnOffCluster::CLUSTER_ID, OnOffCluster::CMD_ON)

# ✅ Even better
light = node.get_cluster!(1_u16, OnOffCluster)
light.invoke_command(OnOffCluster::CMD_ON)
```

### 4. Handle Missing Clusters Gracefully
```crystal
# ✅ Good - Safe access with nil check
if light = node.get_cluster(1_u16, OnOffCluster)
  light.invoke_command(OnOffCluster::CMD_ON)
else
  puts "OnOff cluster not found"
end

# ✅ Good - Let it raise if cluster must exist
light = node.get_cluster!(1_u16, OnOffCluster)
light.invoke_command(OnOffCluster::CMD_ON)
```
