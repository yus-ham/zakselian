const std = @import("std");
const zigstr = @import("zigstr");

const mem = std.mem;
const process = std.process;
const stdout = std.io.getStdOut();


const help_output =
    \\Usage: jaksel example/example1.jaksel
    \\
;

pub const Config = struct {};

pub const Error = error {UnkownOption};

const ZSVal = struct {scalar: []u8};

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
        if (arg.len > 1 and arg[0] == '-') {
        } else {
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
    var line = try zigstr.fromBytes(allocator, "");
    defer line.deinit();

    while (try inStream.readUntilDelimiterOrEof(&buf, '\n'))|str|{
        try line.reset(str);
        try eval(line);
    }
}


var ZSValues = std.StringHashMap(ZSVal).init(allocator);
// defer ZSValues.deinit();

fn eval(s: zigstr) !void {
    var stmt = s;
    var token_iter = stmt.tokenIter(" ");
    var cmd = token_iter.next() orelse "";
    var expr = try zigstr.fromBytes(allocator, "");
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
    var start_expr = (try stmt.indexOf("spill ")).? + 5;
    var end_expr = try _stmt.graphemeCount();
    if (start_expr == end_expr)
        return std.debug.print("Syntax Error: Expected an expression after keyword: 'spill'", .{});
    try _expr.reset(try _stmt.substr(start_expr, end_expr));
    try _expr.trim(" ");
    var value = try evalExpression(_expr);
    std.debug.print("{s}", .{value});
}

test "spill" {
    var stmt = try zigstr.fromBytes(allocator, "spill \"hallo\"");
    var expr = try zigstr.fromBytes(allocator, "\"hallo\"");
    try evalSpill(stmt, expr);
}

fn evalAssignment(name: []const u8, stmt: zigstr, expr: zigstr) !void {
    if (mem.eql(u8, name, ""))
        return std.debug.print("Syntax Error: Expected an identifier after keyword 'literally'", .{});

    var itu_pos = (try stmt.indexOf(" itu ")) orelse 0;
    if (itu_pos == 0)
        return std.debug.print("Syntax Error: Expected a keyword 'itu' after identifier '{s}'", .{name});

    var _stmt = stmt;
    var _expr = expr;
    var start_expr = itu_pos + 5;
    var end_expr = try _stmt.graphemeCount();
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

fn evalExpression(expr: zigstr) ![]u8 {
    var _expr = expr;
    var state = states.string_literal_end;
    var tmp_string = try zigstr.fromBytes(allocator, "");
    try _expr.trim(" ");
    errdefer tmp_string.deinit();

    if (_expr.bytes.items[0] == '"') {
        state = states.string_literal_start;
        var token_iter = _expr.tokenIter("\"");
        var token = token_iter.next() orelse "";
        if (token.len > 0) {
            std.debug.print("\n", .{});
            while (token[token.len-1] == '\\') {
                try tmp_string.concat(token);
                try tmp_string.insert("\"", token.len-1);
                try tmp_string.dropRight(1);
                token = token_iter.next() orelse "";
            }
            try tmp_string.concat(token);
            state = states.string_literal_end;
            return tmp_string.bytes.items;
        }
    }

    return "";
}

test "evalExpression" {
    var str = try zigstr.fromBytes(allocator, "  \"as\\\" dfgh\"");
    _ = mem.eql(u8, "as\" dfgh", try evalExpression(str));
}
