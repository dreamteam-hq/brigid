# Serialization and Delta Compression

## Table of Contents
- [Message types enum](#message-types)
- [Binary serialization with BinaryPrimitives](#binary-serialization)
- [Delta compression encoder](#delta-compression)
- [Object pooling for messages](#object-pooling)

## Message Types

```csharp
// Wire format: [MessageType:1][Length:2][Payload:variable]
public enum GameMessageType : byte
{
    // Client -> Server
    InputCommand = 0x01,
    Heartbeat = 0x02,
    UdpAssociate = 0x03,

    // Server -> Client
    Snapshot = 0x10,
    DeltaUpdate = 0x11,
    EntitySpawn = 0x12,
    EntityDespawn = 0x13,
    ServerTick = 0x14,

    // Bidirectional
    Ping = 0x20,
    Pong = 0x21,
}
```

## Binary Serialization

Zero-allocation entity state serialization using `BinaryPrimitives`. Quantizes rotation to a single byte (256 directions = 1.4 degree precision), reducing entity state from ~80 bytes (JSON) to 14 bytes.

```csharp
public static class GameSerializer
{
    public static int WriteEntityState(
        Span<byte> buffer, int entityId,
        float x, float y, float rotation,
        byte health, byte flags)
    {
        var offset = 0;
        BinaryPrimitives.WriteInt32LittleEndian(buffer[offset..], entityId);
        offset += 4;
        BinaryPrimitives.WriteSingleLittleEndian(buffer[offset..], x);
        offset += 4;
        BinaryPrimitives.WriteSingleLittleEndian(buffer[offset..], y);
        offset += 4;
        // Quantize rotation to byte (256 directions = 1.4 degree precision)
        buffer[offset++] = (byte)(rotation / 360f * 256f);
        buffer[offset++] = health;
        buffer[offset++] = flags;
        return offset;  // 14 bytes total vs ~80+ bytes as JSON
    }

    public static EntityState ReadEntityState(ReadOnlySpan<byte> buffer)
    {
        return new EntityState
        {
            EntityId = BinaryPrimitives.ReadInt32LittleEndian(buffer),
            X = BinaryPrimitives.ReadSingleLittleEndian(buffer[4..]),
            Y = BinaryPrimitives.ReadSingleLittleEndian(buffer[8..]),
            Rotation = buffer[12] / 256f * 360f,
            Health = buffer[13],
            Flags = buffer[14],
        };
    }
}
```

## Delta Compression

Tracks last-sent state per entity. Computes dirty flags and transmits only changed fields.

```csharp
public sealed class DeltaEncoder
{
    private readonly Dictionary<int, EntityState> _lastSent = new();

    public int EncodeDelta(Span<byte> buffer, int entityId, EntityState current)
    {
        var offset = 0;
        BinaryPrimitives.WriteInt32LittleEndian(buffer[offset..], entityId);
        offset += 4;

        if (!_lastSent.TryGetValue(entityId, out var previous))
        {
            // Full state -- entity is new to this client
            buffer[offset++] = 0xFF;  // all-fields flag
            offset += GameSerializer.WriteEntityState(
                buffer[offset..], entityId,
                current.X, current.Y, current.Rotation,
                current.Health, current.Flags);
            _lastSent[entityId] = current;
            return offset;
        }

        // Dirty flags -- only send what changed
        byte dirty = 0;
        if (current.X != previous.X || current.Y != previous.Y) dirty |= 0x01;
        if (current.Rotation != previous.Rotation) dirty |= 0x02;
        if (current.Health != previous.Health) dirty |= 0x04;
        if (current.Flags != previous.Flags) dirty |= 0x08;

        buffer[offset++] = dirty;

        if ((dirty & 0x01) != 0)
        {
            BinaryPrimitives.WriteSingleLittleEndian(buffer[offset..], current.X);
            offset += 4;
            BinaryPrimitives.WriteSingleLittleEndian(buffer[offset..], current.Y);
            offset += 4;
        }
        if ((dirty & 0x02) != 0)
            buffer[offset++] = (byte)(current.Rotation / 360f * 256f);
        if ((dirty & 0x04) != 0)
            buffer[offset++] = current.Health;
        if ((dirty & 0x08) != 0)
            buffer[offset++] = current.Flags;

        _lastSent[entityId] = current;
        return offset;
    }
}
```

## Object Pooling

Rent buffers from `ArrayPool` instead of allocating per-message.

```csharp
public sealed class MessageBuffer : IDisposable
{
    private byte[] _buffer;
    private int _position;

    public MessageBuffer(int size = 1024)
    {
        _buffer = ArrayPool<byte>.Shared.Rent(size);
        _position = 0;
    }

    public Span<byte> Written => _buffer.AsSpan(0, _position);

    public void WriteFloat(float value)
    {
        BinaryPrimitives.WriteSingleLittleEndian(
            _buffer.AsSpan(_position), value);
        _position += 4;
    }

    public void WriteInt32(int value)
    {
        BinaryPrimitives.WriteInt32LittleEndian(
            _buffer.AsSpan(_position), value);
        _position += 4;
    }

    public void WriteByte(byte value) =>
        _buffer[_position++] = value;

    public void Dispose() =>
        ArrayPool<byte>.Shared.Return(_buffer);
}
```
