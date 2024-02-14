const std = @import("std");
const zigstr = @import("zigstr");

const mem = std.mem;
const process = std.process;
const stdout = std.io.getStdOut();

const help_output =
    \\Usage: zaksel example/example1.jaksel
    \\
;

pub const Config = struct {};

pub const Error = error{UnkownOption};

const ZSVal = struct { scalar: []const u8 };

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

pub fn main() !void {
    const args = try process.argsAlloc(allocator);
    var files = std.ArrayList([]u8).init(allocator);
    defer {
        process.argsFree(allocator, args);
        files.deinit();
        arena.deinit();
    }

    for (args[1..]) |arg| {
        if (arg.len > 1 and arg[0] == '-') {} else {
            try files.append(arg);
        }
    }

    if (files.items.len == 0) {
        try stdout.writeAll(help_output);
        return;
    }

    // try stdout.writeAll("Reading file: ");
    // std.debug.print("{s}\n", .{files.items[0]});
    // try stdout.writeAll("\n");

    const file = try std.fs.cwd().openFile(files.items[0], .{ .mode = std.fs.File.OpenMode.read_only });
    defer file.close();

    var bufReader = std.io.bufferedReader(file.reader());
    var inStream = bufReader.reader();

    var buf: [1024]u8 = undefined;
    var line = try zigstr.fromConstBytes(allocator, "");
    defer line.deinit();

    while (try inStream.readUntilDelimiterOrEof(&buf, '\n')) |str| {
        try line.reset(str);
        try eval(line);
    }
}

var ZSValues = std.StringHashMap(ZSVal).init(allocator);
// defer ZSValues.deinit();

fn eval(s: zigstr) !void {
    var stmt = s;
    var token_iter = stmt.tokenIter(" ");
    const cmd = token_iter.next() orelse "";
    var expr = try zigstr.fromConstBytes(allocator, "");
    defer expr.deinit();

    if (mem.eql(u8, cmd, "spill")) {
        try evalSpill(stmt, expr);
    } else if (mem.eql(u8, cmd, "literally")) {
        try evalAssignment(token_iter.next().?, stmt, expr);
    }
}

fn evalSpill(stmt: zigstr, expr: zigstr) !void {
    var _stmt = stmt;
    var _expr = expr;
    const start_expr = stmt.indexOf("spill ").? + 5;
    const end_expr = try _stmt.graphemeLen();
    if (start_expr == end_expr)
        return std.debug.print("Syntax Error: Expected an expression after keyword: 'spill'", .{});
    try _expr.reset(try _stmt.substr(start_expr, end_expr));
    try _expr.trim(" ");
    const value = try evalExpression(_expr);
    std.debug.print("{s}", .{value});
}

test "spill" {
    const stmt = try zigstr.fromConstBytes(allocator, " spill \"hallo\"");
    const expr = try zigstr.fromConstBytes(allocator, "\"hallo\"");
    try evalSpill(stmt, expr);
}

fn evalAssignment(name: []const u8, stmt: zigstr, expr: zigstr) !void {
    if (mem.eql(u8, name, ""))
        return std.debug.print("Syntax Error: Expected an identifier after keyword 'literally'", .{});

    const itu_pos = stmt.indexOf(" itu ") orelse 0;
    if (itu_pos == 0)
        return std.debug.print("Syntax Error: Expected a keyword 'itu' after identifier '{s}'", .{name});

    var _stmt = stmt;
    var _expr = expr;
    const start_expr = itu_pos + 5;
    const end_expr = try _stmt.graphemeLen();
    if (start_expr == end_expr)
        return std.debug.print("Syntax Error: Expected an expression after keyword: 'itu'", .{});
    try _expr.reset(try _stmt.substr(start_expr, end_expr));

    try ZSValues.put(name, .{
        .scalar = try evalExpression(_expr),
    });
}

const states = enum {
    string_literal_start,
    string_literal_end,
};

var state: states = undefined;

fn evalExpression(expr: zigstr) ![]const u8 {
    var _expr = expr;
    try _expr.trimLeft(" ");
    var tmp_string = try zigstr.fromConstBytes(allocator, "");

    while (_expr.byteLen() > 0) {
        if (mem.eql(u8, try _expr.byteSlice(0, 1), "\"")) {
            const literal_string = try buildString(_expr);

            try tmp_string.concat(literal_string);
            std.debug.print("expr: '{s}'\n", .{_expr});
            std.debug.print("tmp_str: '{s}'\n", .{tmp_string});
            std.debug.print("str sisa: {any} {any}\n", .{
                literal_string.len,
                _expr.byteLen(),
            });

            if (literal_string.len + 2 == _expr.byteLen()) {
                return literal_string;
            }
            std.debug.print("str sisa: '{s}'\n", .{try _expr.byteSlice(literal_string.len + 3, _expr.byteLen())});
        }
        // else if (token.eql(" ")) {
        //     // pos  += 1;
        //     continue;
        // }
        break;
    }

    return "";
}

test "evalExpression" {
    const str = try zigstr.fromConstBytes(allocator, "  \"as\\\" dfgh\" + iui");
    _ = mem.eql(u8, "as\" dfgh", try evalExpression(str));
}

fn buildString(expr: zigstr) ![]const u8 {
    var token_iter = expr.tokenIter("\"");
    var token = token_iter.next() orelse "";
    var tmp_string = try zigstr.fromConstBytes(allocator, "");
    errdefer tmp_string.deinit();
    state = states.string_literal_start;

    if (token.len > 0) {
        while (token[token.len - 1] == '\\') {
            try tmp_string.concat(token);
            try tmp_string.insert("\"", token.len - 1);
            try tmp_string.dropRight(1);
            token = token_iter.next() orelse "";
        }
        try tmp_string.concat(token);
    }

    state = states.string_literal_end;
    return tmp_string.bytes();
}
