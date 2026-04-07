// File: src/web_server.zig
// Zig-native HTTP server for the EVM web demo
// Serves the frontend and provides JSON API endpoints

const std = @import("std");
const Allocator = std.mem.Allocator;
const main_mod = @import("main.zig");
const EVM = main_mod.EVM;
const BigInt = main_mod.BigInt;
const tracer = @import("execution_tracer.zig");

const index_html = @embedFile("web/index.html");

// ============================================================
// JSON Helpers
// ============================================================

const JsonWriter = struct {
    data: std.ArrayList(u8) = .empty,
    allocator: Allocator,

    fn init(alloc: Allocator) JsonWriter {
        return .{ .allocator = alloc };
    }

    fn append(self: *JsonWriter, byte: u8) !void {
        try self.data.append(self.allocator, byte);
    }

    fn appendSlice(self: *JsonWriter, slice: []const u8) !void {
        try self.data.appendSlice(self.allocator, slice);
    }

    fn toOwnedSlice(self: *JsonWriter) ![]const u8 {
        return try self.data.toOwnedSlice(self.allocator);
    }
};

fn jsonString(out: *JsonWriter, s: []const u8) !void {
    try out.append('"');
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice("\\\""),
            '\\' => try out.appendSlice("\\\\"),
            '\n' => try out.appendSlice("\\n"),
            '\r' => try out.appendSlice("\\r"),
            '\t' => try out.appendSlice("\\t"),
            else => {
                if (c < 0x20) {
                    try out.appendSlice("\\u00");
                    const hex_table = "0123456789abcdef";
                    try out.append(hex_table[c >> 4]);
                    try out.append(hex_table[c & 0x0f]);
                } else {
                    try out.append(c);
                }
            },
        }
    }
    try out.append('"');
}

fn jsonInt(out: *JsonWriter, val: u64) !void {
    var buf: [20]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return;
    try out.appendSlice(s);
}

fn jsonBool(out: *JsonWriter, val: bool) !void {
    try out.appendSlice(if (val) "true" else "false");
}

fn jsonKey(out: *JsonWriter, key: []const u8) !void {
    try jsonString(out, key);
    try out.append(':');
}

// ============================================================
// Hex Parsing
// ============================================================

fn hexCharToNibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn hexToBytes(allocator: Allocator, hex: []const u8) ![]u8 {
    var input = hex;
    // Strip optional 0x prefix
    if (input.len >= 2 and input[0] == '0' and (input[1] == 'x' or input[1] == 'X')) {
        input = input[2..];
    }
    if (input.len == 0) return try allocator.alloc(u8, 0);
    if (input.len % 2 != 0) {
        // Pad with leading zero
        var padded = try allocator.alloc(u8, input.len + 1);
        padded[0] = '0';
        @memcpy(padded[1..], input);
        defer allocator.free(padded);
        return hexToBytes(allocator, padded);
    }
    const len = input.len / 2;
    var result = try allocator.alloc(u8, len);
    for (0..len) |i| {
        const hi = hexCharToNibble(input[i * 2]) orelse return error.InvalidHex;
        const lo = hexCharToNibble(input[i * 2 + 1]) orelse return error.InvalidHex;
        result[i] = (hi << 4) | lo;
    }
    return result;
}

// ============================================================
// Simple JSON Parser (for request bodies)
// ============================================================

fn extractJsonString(json: []const u8, key: []const u8) ?[]const u8 {
    // Simple JSON string extraction — finds "key":"value"
    var search_buf: [256]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\"", .{key}) catch return null;

    const key_pos = std.mem.indexOf(u8, json, search) orelse return null;
    const after_key = json[key_pos + search.len ..];

    // Skip whitespace and colon
    var i: usize = 0;
    while (i < after_key.len and (after_key[i] == ' ' or after_key[i] == ':' or after_key[i] == '\t' or after_key[i] == '\n' or after_key[i] == '\r')) : (i += 1) {}

    if (i >= after_key.len or after_key[i] != '"') return null;
    i += 1; // skip opening quote

    const start = i;
    while (i < after_key.len and after_key[i] != '"') : (i += 1) {
        if (after_key[i] == '\\') i += 1; // skip escaped char
    }
    if (i >= after_key.len) return null;

    return after_key[start..i];
}

fn extractJsonNumber(json: []const u8, key: []const u8) ?u64 {
    var search_buf: [256]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\"", .{key}) catch return null;

    const key_pos = std.mem.indexOf(u8, json, search) orelse return null;
    const after_key = json[key_pos + search.len ..];

    // Skip whitespace and colon
    var i: usize = 0;
    while (i < after_key.len and (after_key[i] == ' ' or after_key[i] == ':' or after_key[i] == '\t' or after_key[i] == '\n' or after_key[i] == '\r')) : (i += 1) {}

    if (i >= after_key.len) return null;

    const start = i;
    while (i < after_key.len and after_key[i] >= '0' and after_key[i] <= '9') : (i += 1) {}

    if (i == start) return null;
    return std.fmt.parseInt(u64, after_key[start..i], 10) catch return null;
}

// ============================================================
// API Handlers
// ============================================================

fn handleHealth(allocator: Allocator) ![]const u8 {
    _ = allocator;
    return "{\"status\":\"ok\",\"version\":\"zig-evm 0.1.0\"}";
}

fn handleOpcodes(allocator: Allocator) ![]const u8 {
    const infos = try tracer.getAllOpcodeInfo(allocator);
    var out = JsonWriter.init(allocator);
    try out.append('[');
    for (infos, 0..) |info, i| {
        if (i > 0) try out.append(',');
        try out.append('{');
        try jsonKey(&out, "code");
        try jsonInt(&out, info.code);
        try out.append(',');
        try jsonKey(&out, "name");
        try jsonString(&out, info.name);
        try out.append(',');
        try jsonKey(&out, "gas");
        try jsonInt(&out, info.gas);
        try out.append(',');
        try jsonKey(&out, "stack_in");
        try jsonInt(&out, info.stack_in);
        try out.append(',');
        try jsonKey(&out, "stack_out");
        try jsonInt(&out, info.stack_out);
        try out.append(',');
        try jsonKey(&out, "description");
        try jsonString(&out, info.description);
        try out.append(',');
        try jsonKey(&out, "category");
        try jsonString(&out, info.category);
        try out.append('}');
    }
    try out.append(']');
    return try out.toOwnedSlice();
}

fn handleExamples(allocator: Allocator) ![]const u8 {
    _ = allocator;
    return
        \\[
        \\  {
        \\    "name": "Simple Addition",
        \\    "description": "Computes (3 + 4) * 2 = 14",
        \\    "bytecode": "60036004016002020000",
        \\    "gas_limit": 100000
        \\  },
        \\  {
        \\    "name": "Stack Operations",
        \\    "description": "Demonstrates DUP, SWAP, and POP operations",
        \\    "bytecode": "6005600a8190500100",
        \\    "gas_limit": 100000
        \\  },
        \\  {
        \\    "name": "Memory Store & Load",
        \\    "description": "Stores 0xFF at memory offset 0, then loads it back",
        \\    "bytecode": "60ff60005260005100",
        \\    "gas_limit": 100000
        \\  },
        \\  {
        \\    "name": "Comparison & Conditional",
        \\    "description": "Compares two values: checks if 5 > 3 (result: 1)",
        \\    "bytecode": "600360051100",
        \\    "gas_limit": 100000
        \\  },
        \\  {
        \\    "name": "Bitwise Operations",
        \\    "description": "AND, OR, XOR of 0xFF and 0x0F",
        \\    "bytecode": "60ff600f16600f60ff1760ff600f1800",
        \\    "gas_limit": 100000
        \\  },
        \\  {
        \\    "name": "Counter Loop",
        \\    "description": "Loops from 0 to 5 using JUMP and JUMPI",
        \\    "bytecode": "60005b600101806005101561000357505000",
        \\    "gas_limit": 100000
        \\  },
        \\  {
        \\    "name": "Fibonacci (5th number)",
        \\    "description": "Computes the 5th Fibonacci number (F5 = 5)",
        \\    "bytecode": "600060016005905b600185019150600190038061000757905050505000",
        \\    "gas_limit": 200000
        \\  },
        \\  {
        \\    "name": "Return Data",
        \\    "description": "Stores value 42 in memory and returns it",
        \\    "bytecode": "602a60005260206000f3",
        \\    "gas_limit": 100000
        \\  }
        \\]
    ;
}

fn handleExecuteTrace(allocator: Allocator, body: []const u8) ![]const u8 {
    // Parse request
    const bytecode_hex = extractJsonString(body, "bytecode") orelse return "{\"success\":false,\"error_msg\":\"Missing bytecode field\"}";
    const gas_limit = extractJsonNumber(body, "gas_limit") orelse 100000;
    const calldata_hex = extractJsonString(body, "calldata");

    // Decode hex
    const bytecode = hexToBytes(allocator, bytecode_hex) catch return "{\"success\":false,\"error_msg\":\"Invalid bytecode hex\"}";
    var calldata: []u8 = &[_]u8{};
    if (calldata_hex) |cd| {
        calldata = hexToBytes(allocator, cd) catch &[_]u8{};
    }

    if (bytecode.len == 0) return "{\"success\":false,\"error_msg\":\"Empty bytecode\"}";

    // Execute with trace
    const trace = tracer.executeWithTrace(allocator, bytecode, gas_limit, calldata) catch |err| {
        var out = JsonWriter.init(allocator);
        try out.appendSlice("{\"success\":false,\"error_msg\":\"");
        try out.appendSlice(@errorName(err));
        try out.appendSlice("\"}");
        return try out.toOwnedSlice();
    };

    // Serialize to JSON
    var out = JsonWriter.init(allocator);
    try out.append('{');

    try jsonKey(&out, "success");
    try jsonBool(&out, trace.success);
    try out.append(',');

    if (trace.error_msg) |msg| {
        try jsonKey(&out, "error_msg");
        try jsonString(&out, msg);
        try out.append(',');
    }

    try jsonKey(&out, "total_gas_used");
    try jsonInt(&out, trace.total_gas_used);
    try out.append(',');

    try jsonKey(&out, "gas_limit");
    try jsonInt(&out, trace.gas_limit);
    try out.append(',');

    try jsonKey(&out, "return_data");
    try jsonString(&out, trace.return_data);
    try out.append(',');

    // Steps
    try jsonKey(&out, "steps");
    try out.append('[');
    for (trace.steps, 0..) |step, i| {
        if (i > 0) try out.append(',');
        try out.append('{');

        try jsonKey(&out, "step");
        try jsonInt(&out, step.step);
        try out.append(',');

        try jsonKey(&out, "pc");
        try jsonInt(&out, step.pc);
        try out.append(',');

        try jsonKey(&out, "opcode");
        try jsonInt(&out, step.opcode);
        try out.append(',');

        try jsonKey(&out, "opcode_name");
        try jsonString(&out, step.opcode_name);
        try out.append(',');

        if (step.operand) |operand| {
            try jsonKey(&out, "operand");
            try jsonString(&out, operand);
            try out.append(',');
        }

        try jsonKey(&out, "gas_cost");
        try jsonInt(&out, step.gas_cost);
        try out.append(',');

        try jsonKey(&out, "gas_remaining");
        try jsonInt(&out, step.gas_remaining);
        try out.append(',');

        try jsonKey(&out, "gas_used");
        try jsonInt(&out, step.gas_used_total);
        try out.append(',');

        try jsonKey(&out, "stack_depth");
        try jsonInt(&out, step.stack_depth);
        try out.append(',');

        try jsonKey(&out, "memory_size");
        try jsonInt(&out, step.memory_size);
        try out.append(',');

        // Stack array
        try jsonKey(&out, "stack");
        try out.append('[');
        for (step.stack, 0..) |val, j| {
            if (j > 0) try out.append(',');
            try jsonString(&out, val);
        }
        try out.append(']');

        if (step.error_msg) |msg| {
            try out.append(',');
            try jsonKey(&out, "error_msg");
            try jsonString(&out, msg);
        }

        try out.append('}');
    }
    try out.append(']');
    try out.append(',');

    // Final stack
    try jsonKey(&out, "final_stack");
    try out.append('[');
    for (trace.final_stack, 0..) |val, i| {
        if (i > 0) try out.append(',');
        try jsonString(&out, val);
    }
    try out.append(']');
    try out.append(',');

    // Storage state
    try jsonKey(&out, "storage");
    try out.append('[');
    for (trace.storage_state, 0..) |entry, i| {
        if (i > 0) try out.append(',');
        try out.append('{');
        try jsonKey(&out, "key");
        try jsonString(&out, entry.key);
        try out.append(',');
        try jsonKey(&out, "value");
        try jsonString(&out, entry.value);
        try out.append('}');
    }
    try out.append(']');
    try out.append(',');

    // Logs
    try jsonKey(&out, "logs");
    try out.append('[');
    for (trace.logs, 0..) |log, i| {
        if (i > 0) try out.append(',');
        try out.append('{');
        try jsonKey(&out, "address");
        try jsonString(&out, log.address);
        try out.append(',');
        try jsonKey(&out, "topics");
        try out.append('[');
        for (log.topics, 0..) |topic, j| {
            if (j > 0) try out.append(',');
            try jsonString(&out, topic);
        }
        try out.append(']');
        try out.append(',');
        try jsonKey(&out, "data");
        try jsonString(&out, log.data);
        try out.append('}');
    }
    try out.append(']');

    try out.append('}');
    return try out.toOwnedSlice();
}

fn handleDisassemble(allocator: Allocator, body: []const u8) ![]const u8 {
    const bytecode_hex = extractJsonString(body, "bytecode") orelse return "{\"error\":\"Missing bytecode field\"}";
    const bytecode = hexToBytes(allocator, bytecode_hex) catch return "{\"error\":\"Invalid bytecode hex\"}";
    if (bytecode.len == 0) return "{\"instructions\":[]}";

    const ops = try tracer.disassemble(allocator, bytecode);

    var out = JsonWriter.init(allocator);
    try out.appendSlice("{\"instructions\":[");
    for (ops, 0..) |op, i| {
        if (i > 0) try out.append(',');
        try out.append('{');
        try jsonKey(&out, "pc");
        try jsonInt(&out, op.pc);
        try out.append(',');
        try jsonKey(&out, "opcode");
        try jsonInt(&out, op.opcode);
        try out.append(',');
        try jsonKey(&out, "opcode_name");
        try jsonString(&out, op.opcode_name);
        try out.append(',');
        try jsonKey(&out, "gas_cost");
        try jsonInt(&out, op.gas_cost);
        if (op.operand) |operand| {
            try out.append(',');
            try jsonKey(&out, "operand");
            try jsonString(&out, operand);
        }
        try out.append('}');
    }
    try out.appendSlice("]}");
    return try out.toOwnedSlice();
}

// ============================================================
// HTTP Server
// ============================================================

fn sendResponse(connection: std.net.Stream, status: []const u8, content_type: []const u8, body: []const u8) void {
    var header_buf: [1024]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buf, "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nConnection: close\r\n\r\n", .{ status, content_type, body.len }) catch return;
    _ = connection.write(header) catch return;
    if (body.len > 0) {
        _ = connection.write(body) catch return;
    }
}

fn readRequestBody(allocator: Allocator, stream: std.net.Stream, header_data: []const u8) ![]const u8 {
    // Find Content-Length in headers
    var content_length: usize = 0;
    var lines = std.mem.splitSequence(u8, header_data, "\r\n");
    while (lines.next()) |line| {
        if (std.ascii.startsWithIgnoreCase(line, "content-length:")) {
            const val = std.mem.trim(u8, line["content-length:".len..], " \t");
            content_length = std.fmt.parseInt(usize, val, 10) catch 0;
            break;
        }
    }

    if (content_length == 0) return "";
    if (content_length > 1024 * 1024) return error.BodyTooLarge; // 1MB limit

    // Check if body data is already in the header buffer (after \r\n\r\n)
    const header_end = std.mem.indexOf(u8, header_data, "\r\n\r\n") orelse return "";
    const body_start = header_end + 4;
    const already_read = header_data.len - body_start;

    var body = try allocator.alloc(u8, content_length);
    if (already_read > 0) {
        const to_copy = @min(already_read, content_length);
        @memcpy(body[0..to_copy], header_data[body_start .. body_start + to_copy]);
        if (to_copy >= content_length) return body;
        // Read remaining
        var total: usize = to_copy;
        while (total < content_length) {
            const n = stream.read(body[total..]) catch break;
            if (n == 0) break;
            total += n;
        }
    } else {
        var total: usize = 0;
        while (total < content_length) {
            const n = stream.read(body[total..]) catch break;
            if (n == 0) break;
            total += n;
        }
    }

    return body;
}

fn handleConnection(allocator: Allocator, connection: std.net.Stream) void {
    defer connection.close();

    // Read request headers
    var buf: [8192]u8 = undefined;
    const n = connection.read(&buf) catch return;
    if (n == 0) return;

    const request = buf[0..n];

    // Parse method and path from first line
    const first_line_end = std.mem.indexOf(u8, request, "\r\n") orelse return;
    const first_line = request[0..first_line_end];

    var parts = std.mem.splitScalar(u8, first_line, ' ');
    const method = parts.next() orelse return;
    const path = parts.next() orelse return;

    // Handle CORS preflight
    if (std.mem.eql(u8, method, "OPTIONS")) {
        sendResponse(connection, "204 No Content", "text/plain", "");
        return;
    }

    // Route requests
    if (std.mem.eql(u8, method, "GET")) {
        if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html")) {
            sendResponse(connection, "200 OK", "text/html; charset=utf-8", index_html);
        } else if (std.mem.eql(u8, path, "/api/health")) {
            const body = handleHealth(allocator) catch "{\"error\":\"internal\"}";
            sendResponse(connection, "200 OK", "application/json", body);
        } else if (std.mem.eql(u8, path, "/api/opcodes")) {
            const body = handleOpcodes(allocator) catch "{\"error\":\"internal\"}";
            sendResponse(connection, "200 OK", "application/json", body);
        } else if (std.mem.eql(u8, path, "/api/examples")) {
            const body = handleExamples(allocator) catch "[]";
            sendResponse(connection, "200 OK", "application/json", body);
        } else {
            sendResponse(connection, "404 Not Found", "application/json", "{\"error\":\"Not found\"}");
        }
    } else if (std.mem.eql(u8, method, "POST")) {
        const body = readRequestBody(allocator, connection, request) catch "";

        if (std.mem.eql(u8, path, "/api/execute-trace") or std.mem.eql(u8, path, "/api/execute")) {
            const response = handleExecuteTrace(allocator, body) catch "{\"success\":false,\"error_msg\":\"Internal server error\"}";
            sendResponse(connection, "200 OK", "application/json", response);
        } else if (std.mem.eql(u8, path, "/api/disassemble")) {
            const response = handleDisassemble(allocator, body) catch "{\"error\":\"Internal server error\"}";
            sendResponse(connection, "200 OK", "application/json", response);
        } else {
            sendResponse(connection, "404 Not Found", "application/json", "{\"error\":\"Not found\"}");
        }
    } else {
        sendResponse(connection, "405 Method Not Allowed", "application/json", "{\"error\":\"Method not allowed\"}");
    }
}

// ============================================================
// Main Entry Point
// ============================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get port from environment or default to 3000
    const port_str = std.posix.getenv("PORT") orelse "3000";
    const port = std.fmt.parseInt(u16, port_str, 10) catch 3000;

    const address = std.net.Address.parseIp("0.0.0.0", port) catch {
        std.debug.print("Failed to parse address\n", .{});
        return;
    };

    var server = address.listen(.{
        .reuse_address = true,
    }) catch {
        std.debug.print("Failed to start server on port {d}\n", .{port});
        return;
    };
    defer server.deinit();

    std.debug.print("\n", .{});
    std.debug.print("  ╔══════════════════════════════════════╗\n", .{});
    std.debug.print("  ║       Zig EVM Playground             ║\n", .{});
    std.debug.print("  ║       http://localhost:{d:<5}          ║\n", .{port});
    std.debug.print("  ╚══════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // Accept connections
    while (true) {
        const conn = server.accept() catch continue;
        handleConnection(allocator, conn.stream);
    }
}
