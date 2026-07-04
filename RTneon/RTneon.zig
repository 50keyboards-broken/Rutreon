const std = @import("std");
const print = std.debug.print;
const dir = std.Io.Dir;
const zd = dir.cwd();
const debugprint = true;

const rl = @cImport({
    @cInclude("raylib.h");
});

var global_font: rl.Font = undefined;

//core construction:
var EMthreads: [6]ThreadUnit = undefined;
const unitflags = struct {
    E: bool = false,
    G: bool = false,
    L: bool = false,
    C: bool = false,
    O: bool = false,
};
const ThreadUnit = struct {
    COval: u10 = 0,
    COregion: u2 = 0,
    COaddr: u10 = 0,
    COfocus: bool = false, // false = MECO, true = VMEC
    TMUReturnhandle: u10 =  0,
    VRTXpointer: u4 = 0,
    VXID: u5 = 0,
    VRTX: [12]EMSTRUCTION = [_]EMSTRUCTION{.{.r = 0b10000, .t = 0}} ** 12,
    CACHE: [16]u10 = [_]u10{0} ** 16,
    VARS: [16]u10 = [_]u10{0} ** 16,
    VARaddr: u4 = 0,
    UNITCONF: u8 = 0,
    FLAGS: unitflags = .{},
    YEILDtype: u2 = 0,
    YEILDval: u10 = 0,
    EMTUID: u3 = 0,
    EMUNITCYCLES: usize = 0,
    EMUNITLASTCYCLED: bool = false,
    EMPREVIOUSPOINTER: u4 = 0
};
fn EMsummonunit() void {
    for (0..6) |i| {
        EMthreads[i] = .{
            .EMTUID = @intCast(i),
        };
    }
}
// gui vars
var monh: i32 = 0;
var monw: i32 = 0;
var currenttab: i32 = 0;
var currentcoretab: i32 = 0;
var livescrnsizew: i32 = 0;
var livescrnsizeh: i32 = 0;
var livescrnsizehf: f32 = 0;
var livescrnsizewf: f32 = 0;
var logs: [12][64]u8 = .{.{0} ** 64} ** 12;
var logsheader: usize = 0;
// emulator vars
//var vxbootraw: [128]u12 = undefined;
var yield_flags: [16]bool = .{false}**16;
var Storage: [1024]u10 = .{0} ** 1024;
var RMEMbank1: [1024]u10 = .{0} ** 1024;
var RMEMbank2: [992]u10 = .{0} ** 992;
var VMEM: [1024]u10 = .{0} ** 1024;
var SimulatethisTU: usize = 0;
var CyclesSimulated: usize = 0;
var simulatelockbool: bool = false;

fn inity() void {
    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
    rl.InitWindow(1200, 800, "RUTNEON: PACE");
    rl.SetWindowMinSize(900, 400);
    const monitor = rl.GetCurrentMonitor();
    monh = rl.GetMonitorHeight(monitor);
    monw = rl.GetMonitorWidth(monitor);
    rl.SetWindowSize(monw, monh);
    rl.MaximizeWindow();
    const icon = rl.LoadImage("Assets/icon-VX48.png");
    rl.SetWindowIcon(icon);
    rl.UnloadImage(icon);
    rl.SetTargetFPS(rl.GetMonitorRefreshRate(monitor));
    global_font = rl.LoadFontEx("/usr/share/fonts/TTF/FiraCodeNerdFontMono-SemiBold.ttf", 64, null, 0);
}

pub fn main(init: std.process.Init) !void {
    inity();
    EMsummonunit();
    RMEMbank1[150] = 1002; // remove these two tho..
    RMEMbank2[991] = 69;
    EMthreads[0].EMUNITLASTCYCLED = true; // dont remove this.. its for gui clarity lol
    const IOobject = init.io;
    var simulationbool: bool = false;
    var lastsecond: f64 = 0;
    try FindrunVXBOOT(IOobject);
    while (!rl.WindowShouldClose()) {
        livescrnsizew = rl.GetScreenWidth();
        livescrnsizeh = rl.GetScreenHeight();
        livescrnsizewf = @floatFromInt(livescrnsizew);
        livescrnsizehf = @floatFromInt(livescrnsizeh);
        rl.BeginDrawing();
        rl.DrawRectangleGradientH(0, 0, livescrnsizew, livescrnsizeh, rl.Color{ .r = 255, .g = 127, .b = 42, .a = 255 }, rl.Color{ .r = 255, .g = 127, .b = 220, .a = 255 });
        rl.DrawRectangle(10, 10, livescrnsizew - 20, livescrnsizeh - 20, rl.Color{ .r = 55, .g = 62, .b = 72, .a = 255 });
        EMGUI();
        switch (currenttab) {
            0 => {
                EMGUItab_OVERVIEW();
            },
            1 => {
                EMGUItab_CORE();
            },
            2 => {
                EMGUIRMEM();
            },
            3 => {
               EMGUIRawTrace();
            },
            else => {},
        }
        if (rl.IsKeyPressed(rl.KEY_Z) & !simulatelockbool) {
            AIM(IOobject, 1);
            EMTOOLGUImessage("Z Stepped : ", CyclesSimulated);
        }
        if (rl.IsKeyPressed(rl.KEY_X) & !simulatelockbool) {
            AIM(IOobject, EMthreads.len);
            EMTOOLGUImessage("X Stepped : ", CyclesSimulated);
        }
        if (rl.IsKeyPressed(rl.KEY_R)) {
            switch (simulatelockbool) {
                false => {
                    simulatelockbool = true;
                    simulationbool = true;
                    EMTOOLGUImessage("R AIM Started : ", CyclesSimulated);
                },
                true => {
                    simulatelockbool = false;
                    EMTOOLGUImessage("R AIM Stopped : ", CyclesSimulated);
                }
            }
        }
        if (rl.IsKeyPressed(rl.KEY_T)) {
            switch (simulatelockbool) {
                false => {
                    simulatelockbool = true;
                    simulationbool = false;
                    EMTOOLGUImessage("T AIM Started (1Hz) : ", CyclesSimulated);
                },
                true => {
                    simulatelockbool = false;
                    EMTOOLGUImessage("T AIM Stopped (1Hz) : ", CyclesSimulated);
                }
            }
        }
        if (simulatelockbool) {
            switch (simulationbool) {
                true => {AIM(IOobject, 6);},
                false => {
                    const thissecond = rl.GetTime();
                    if (thissecond - lastsecond >= 1.0) {
                        AIM(IOobject, 1);
                        lastsecond = thissecond;
                    }
                }
            }
        }
        rl.DrawFPS(10, 10);
        rl.EndDrawing();
    }
}

const STRUCTEMGUITABLE = struct {x: f32, y: f32, w: f32, h:f32,  input: []const u10, addr: usize = 0, row: usize, col: usize, vspace: f32 = 30, hspace: f32 = 70, fontsize: f32 = 32};
fn EMGUImemorytable(lock: STRUCTEMGUITABLE) void {
    const rect = rl.Rectangle{.x = lock.x, .y = lock.y, .width = lock.w, .height = lock.h};
    var buf: [5]u8 = undefined;
    var hexvalue: []u8 = undefined;
    var addrvalue: []u8 = undefined;
    var colvalue: f32 = lock.x+10+80;
    var rowvalue: f32 = lock.y+10;
    var forcount: usize = 0;
    var memcount: usize = lock.addr;
    const endaddrview = @min(lock.addr + (lock.col*lock.row), lock.input.len);
    rl.DrawRectangleRounded(rect, 0.05, 3, rl.Color{ .r = 67, .g = 74, .b = 84, .a = 255 });
    rl.DrawRectangleRoundedLinesEx(rect, 0.05, 10, 2, rl.Color{.r = 0x3D, .g = 0x44, .b = 0x4E, .a = 255});
    for (lock.input[lock.addr..endaddrview]) |val| {
        hexvalue = std.fmt.bufPrint(buf[0..], "{X:0>3}", .{val}) catch unreachable;
        buf[hexvalue.len] = 0;
        rl.DrawTextEx(global_font, hexvalue.ptr, .{.x = colvalue, .y = rowvalue}, lock.fontsize, 1, rl.LIGHTGRAY);
        colvalue += lock.hspace;
        forcount += 1;
        memcount += 1;
        if (forcount == lock.col) {
            addrvalue =  std.fmt.bufPrint(buf[0..], "{d:0>4}", .{memcount-lock.col}) catch unreachable;
            buf[addrvalue.len] = 0;
            rl.DrawTextEx(global_font, addrvalue.ptr, .{.x = lock.x+10, .y = rowvalue}, lock.fontsize, 1, rl.PURPLE);
            rowvalue += lock.vspace;
            colvalue = lock.x+10+80;
            forcount = 0;
        }
    }
}
fn EMGUIcoreswitcher() void {
    var buf: [64]u8 = undefined;
    if (rl.IsKeyPressed(rl.KEY_A)) {
        if (currentcoretab != 0) currentcoretab -= 1;
    }
    if (rl.IsKeyPressed(rl.KEY_D)) {
        if (currentcoretab + 1 < EMthreads.len) currentcoretab += 1;
    }

    const coretext = std.fmt.bufPrint(&buf, "A <[ {d} ]> D", .{currentcoretab}) catch unreachable;
    buf[coretext.len] = 0;
    rl.DrawText(coretext.ptr, @divTrunc(livescrnsizew, 2)-rl.MeasureText(coretext.ptr, 20), livescrnsizeh-40, 20, rl.WHITE);
}
const STRUCTEMGUICORE = struct {x: f32, y: f32, core: *ThreadUnit};
fn EMGUIcoredrawer(lock: STRUCTEMGUICORE) void {
    var buf: [64]u8 = undefined;
    var contentstext: []u8 = undefined;
    const textoffset: f32 = lock.x + 15; //repetive use
    const lastibus = lock.core.VRTX[lock.core.EMPREVIOUSPOINTER];
    const rect = rl.Rectangle{.x = lock.x, .y = lock.y, .height = livescrnsizehf-700, .width = livescrnsizewf-1350};
    contentstext = std.fmt.bufPrintZ(buf[0..], "EON ID: {d}  -  VXID: {d}  @  {d}       ", .{lock.core.EMTUID, lock.core.VXID, lock.core.VRTXpointer}) catch unreachable;
    rl.DrawRectangleRounded(rect, 0.05, 3, rl.Color{ .r = 67, .g = 74, .b = 84, .a = 255 }); // background rect
    switch (lock.core.EMUNITLASTCYCLED) {
        true => {rl.DrawRectangleRoundedLinesEx(rect, 0.05, 10, 2, rl.PURPLE);},
        false => {rl.DrawRectangleRoundedLinesEx(rect, 0.05, 10, 2, rl.Color{.r = 0x3D, .g = 0x44, .b = 0x4E, .a = 255});}
    }
    rl.DrawTextEx(global_font, contentstext.ptr, .{.x = lock.x + (((livescrnsizewf-1300) - @as(f32, @floatFromInt(rl.MeasureText(contentstext.ptr, 30)))) / 2), .y = lock.y}, 30, 1, rl.WHITE); // rect title
    contentstext = std.fmt.bufPrintZ(buf[0..], "MECO: {b:0>2}r{b:0>10}", .{lock.core.COregion, lock.core.COaddr}) catch unreachable;
    rl.DrawTextEx(global_font, contentstext.ptr, .{.x = textoffset, .y = lock.y+40}, 30, 1, rl.WHITE);
    if (lastibus.r < 15) {
        contentstext = std.fmt.bufPrintZ(buf[0..], "Current: {b:0>4}", .{lastibus.r}) catch unreachable;
    } else if (lastibus.r == 0b11110) {
        contentstext = std.fmt.bufPrintZ(buf[0..], "Current: STOP ({X})", .{lastibus.r}) catch unreachable;
    } else {
        contentstext = std.fmt.bufPrintZ(buf[0..], "Current: UNDF ({X})", .{lastibus.r}) catch unreachable;
    }
    rl.DrawTextEx(global_font, contentstext.ptr, .{.x = textoffset, .y = lock.y+80}, 30, 1, rl.WHITE);
    contentstext = std.fmt.bufPrintZ(buf[0..], "Status: {d}", .{lock.core.YEILDtype}) catch unreachable;
    rl.DrawTextEx(global_font, contentstext.ptr, .{.x = textoffset, .y = lock.y+120}, 30, 1, rl.WHITE);
}

fn EMGUI() void {
    const tabs = [_][*c]const u8{ "[ Overview ]", "[ Core ]", "[ RMEM ]", "[ Rutneon RawTrytes ]", "[ OUTRA ]" };
    var tabwidth: i32 = 0;
    var coretabwidth: i32 = 0;

    if (rl.IsKeyPressed(rl.KEY_RIGHT)) {
        currenttab += 1;
        if (currenttab >= tabs.len) currenttab = tabs.len - 1;
    }
    if (rl.IsKeyPressed(rl.KEY_LEFT)) {
        currenttab -= 1;
        if (currenttab < 0) currenttab = 0;
    }
    for (tabs) |t| {
        tabwidth += rl.MeasureText(t, 20) + 20 + 10;
    }
    // remove last offsets
    tabwidth -= 10;
    coretabwidth -= 10;
    var x: i32 = @divTrunc(livescrnsizew - tabwidth, 2);

    for (tabs, 0..) |t, i| {
        const width = rl.MeasureText(t, 20) + 20;

        if (i == currenttab) {
            rl.DrawRectangle(x, 10, width, 30, rl.DARKPURPLE);
        }

        rl.DrawText(t, x + 10, 15, 20, rl.WHITE);
        x += width + 10;
    }
}
fn EMGUItab_OVERVIEW() void {
    const coregroup3 = ((livescrnsizewf-1350)*3)+40;
    const startx = (livescrnsizewf - coregroup3) / 2;
    var cordx: f32 = startx;
    var cordy: f32 = 50;
    for (&EMthreads) |*eon| {
        EMGUIcoredrawer(.{.x = cordx, .y = cordy, .core = eon});
        if (eon.EMTUID == 2) {
            cordx = startx;
            cordy += livescrnsizehf-700 + 20;
        } else {
            cordx += livescrnsizewf-1350 + 20;
        }
    }
    rl.DrawRectangle(10, livescrnsizeh-300, livescrnsizew-20, 290, rl.Color{.r = 37, .g = 44, .b = 57, .a = 200});
    rl.DrawLineBezier(.{.x = 10, .y = livescrnsizehf-300}, .{.x = livescrnsizewf-10, .y = livescrnsizehf-300},10, rl.Color{.r = 0x3D, .g = 0x44, .b = 0x4E, .a = 255});
    const TimingScheme = "[Z] Step   |   [X] Global Step   |   [R] AIM RunHz  |   [T] AIM 1Hz";
    rl.DrawTextEx(global_font, TimingScheme, .{.x = (livescrnsizewf/2) - (rl.MeasureTextEx(global_font, TimingScheme, 20, 1).x/2), .y = livescrnsizehf-290}, 20, 1, rl.PURPLE);
    var EntryY: f32 = livescrnsizehf-290;
    var i: usize = logsheader;

    var count: usize = 0;
    while (count < logs.len) : (count += 1) {
        const line = logs[i];

        if (line.len != 0) {
            rl.DrawTextEx(global_font, &line, .{
                .x = 15,
                .y = EntryY,
            }, 20, 1, rl.WHITE);
        }

        EntryY += 22;

        i = (i + 1) % logs.len;
    }
}
fn EMGUItab_CORE() void {
    var buf: [64]u8 = undefined;
    const core = EMthreads[@intCast(currentcoretab)];
    const LeftBoxesHeight = @divTrunc(livescrnsizeh, 2) - 50;
    const vrtxboxw = 500;
    const vrtxboxh = livescrnsizeh - 80;
    const vrtxboxx = livescrnsizew - 535;
    const rowh: i32 = @divTrunc(vrtxboxh, 12);
    const rect = rl.Rectangle{.x = @floatFromInt(vrtxboxx), .y = 40, .width = @floatFromInt(vrtxboxw), .height = @floatFromInt(vrtxboxh)};
    var EMSTRUCT: []u8 = undefined;
    EMGUIcoreswitcher();
    rl.DrawRectangleRounded(rect, 0.05, 10, rl.Color{ .r = 67, .g = 74, .b = 84, .a = 255 });
    rl.DrawRectangleRoundedLinesEx(rect, 0.05, 10, 2, rl.Color{.r = 0x3D, .g = 0x44, .b = 0x4E, .a = 255});
    for (core.VRTX, 0..) |STRUCTION, i| {
        const y = 40 + @as(i32, @intCast(i)) * rowh;
        const current = (i == core.VRTXpointer);
        if (current) {
            const rec = rl.Rectangle{.x = @floatFromInt(vrtxboxx), .y = @floatFromInt(y), .width = @floatFromInt(vrtxboxw), .height = @floatFromInt(rowh)};
            rl.DrawRectangleRounded(rec, 0.4, 10, rl.DARKPURPLE);
        }
        if (STRUCTION.r < 15) {
            EMSTRUCT = std.fmt.bufPrint(buf[0..], "{d:0>2}: {b:0>4} {b:0>12}", .{ i, STRUCTION.r, STRUCTION.t }) catch unreachable;
        } else if (STRUCTION.r == 0b11110) {
            EMSTRUCT = std.fmt.bufPrint(buf[0..], "{d:0>2}: {s} {b:0>12}", .{ i, "STOP", STRUCTION.t }) catch unreachable;
        } else {
            EMSTRUCT = std.fmt.bufPrint(buf[0..], "{d:0>2}: {s} {b:0>12}", .{ i, "UNDF", STRUCTION.t }) catch unreachable;
        }

        buf[EMSTRUCT.len] = 0;
        const texty: f32 = @as(f32, @floatFromInt(y)) + (rl.MeasureTextEx(global_font, EMSTRUCT.ptr, 44, 1).y/3);
        rl.DrawTextEx(global_font, EMSTRUCT.ptr, .{ .x = @as(f32, @floatFromInt(vrtxboxx + 10)), .y = texty}, 44, 1, rl.WHITE);
    }
    //rl.DrawRectangle(35, 40, 500, LeftBoxesHeight, rl.Color{ .r = 67, .g = 74, .b = 84, .a = 255 });
    rl.DrawRectangle(35, livescrnsizeh - 20 - 500 + 31, 500, LeftBoxesHeight, rl.Color{ .r = 67, .g = 74, .b = 84, .a = 255 });
    const floatLBH = @as(f32, @floatFromInt(LeftBoxesHeight));
    EMGUImemorytable(.{.x = 35, .y = 40, .w = 500, .h = floatLBH, .input = &core.CACHE, .col = 4, .row = 4, .vspace = 133, .hspace = 115});
}
var bank1view: usize = 0;
var bank2view: usize = 0;
fn EMGUIRMEM() void {
    const bank2y = @as(f32,@floatFromInt(livescrnsizeh))/2+20;
    rl.DrawTextEx(global_font, "B\nA\nN\nK\n1\n\n\n\n\nW\nS", .{.x = 20, .y = 40}, 20, 1, rl.WHITE);
    rl.DrawTextEx(global_font, "B\nA\nN\nK\n2\n\n\n\n\nA\nD", .{.x = 20, .y = bank2y}, 20, 1, rl.WHITE);

    if (rl.IsKeyPressed(rl.KEY_W)) {
        if (bank1view >= 16) bank1view -= 16;
    }
    if (rl.IsKeyPressed(rl.KEY_S)) {
        if (bank1view + 16 < 800) bank1view += 16;
    }
    if (rl.IsKeyPressed(rl.KEY_A)) {
        if (bank2view >= 16) bank2view -= 16;
    }
    if (rl.IsKeyPressed(rl.KEY_D)) {
        if (bank2view + 16 < 768) bank2view += 16;
    }
    EMGUImemorytable(.{.x = 40, .y = 40, .w = 1200, .h = @floatFromInt(livescrnsizeh-530), .input = &RMEMbank1, .addr = bank1view, .col = 16, .row = 15});
    EMGUImemorytable(.{.x = 40, .y = bank2y, .w = 1200, .h = @floatFromInt(livescrnsizeh-530), .input = &RMEMbank2, .addr = bank2view, .col = 16, .row = 15});
}
fn EMGUIRawTrace() void {
    EMGUIcoreswitcher();

}

fn bytetotryte(input: []const u8) u12 {
    var outtryte: u12 = 0;
    for (input) |bit| {
        outtryte <<= 1;
        outtryte |= @intCast(bit - '0');
    }
    return outtryte;
}

fn structparse(input: []const u8) u12 {
    for (input) |bit| {
        switch (bit) {
            '1', '0' => {
                return bytetotryte(input);
            },
            else => {
                return 30;
            },
        }
    }
    return 31;
}
fn cstr(buf: []u8) [*c]const u8 {
    return @ptrCast(buf.ptr);
}
// i wanna.. kiss* myself
// i hate this reading file sheit..
fn FindrunVXBOOT(IOobject: anytype) !void {
    const EMPACESTRUCTION = struct {
        p: u6,
        e: u12,
    };
    var VXBOOTED: [64]EMPACESTRUCTION = undefined;
    var rootdir: std.Io.Dir  = std.Io.Dir.cwd().openDir(IOobject, "ROOT/", .{.iterate = true}) catch {EMTOOLGUImessage("PACE READ ERR : ", CyclesSimulated); return;};
    defer rootdir.close(IOobject);
    var rootiterate = rootdir.iterate();
    var buf: [128]u8 = undefined;
    while (rootiterate.next(IOobject) catch unreachable) |dirContent| {
        if (dirContent.kind != .file) continue;

        if (std.mem.endsWith(u8, dirContent.name, ".VXBOOT")) {
            const filepath = try std.fmt.bufPrint(&buf, "ROOT/{s}", .{dirContent.name});
            var inputbuf: [1024]u8 = undefined;
            //printouts
            print("Lets hope 'ROOT/{s}' is the right one! :3\n", .{dirContent.name});
            const vxbootraw = try dir.readFile(zd, IOobject, filepath, &inputbuf);
            var readpoin: usize = 0;
            var writepoin: usize = 0;
            var chunkpoin: u4 = 0;
            var linepoin: usize = 0;
            var linecount: usize = 0;
            var linebuffer: [16][]const u8 = undefined;
            for (0..vxbootraw.len) |i| {
                if (vxbootraw[i] == 10) {
                    const line = vxbootraw[readpoin..i];
                    linebuffer[linepoin] = line;
                    linepoin += 1;
                    readpoin = i + 1;
                    linecount += 1;
                }
            }
            var readtryte: []const u8 = undefined;
            var opcode: [2]u6 = .{0, 0};
            for (0..linecount) |r| {
                if (r % 3 == 0) {
                    readtryte = linebuffer[r];
                    opcode[0] = @intCast(bytetotryte(readtryte[0..6]));
                    opcode[1] = @intCast(bytetotryte(readtryte[6..12]));
                } else {
                    VXBOOTED[writepoin] = .{.p =opcode[chunkpoin], .e = bytetotryte(linebuffer[r])};
                    print("PACE: {b:0>6}vxb{b:0>12}\n", .{VXBOOTED[writepoin].p, VXBOOTED[writepoin].e});
                    writepoin += 1;
                    chunkpoin += 1;
                    if (chunkpoin > 1) {
                        chunkpoin = 0;
                    }
                }
            }
            for (0..VXBOOTED.len) |i| {
                const f4b: u4 = @truncate(VXBOOTED[i].e >> 8);
                const selTU: u3 = @truncate(f4b);
                const l8b: u8 = @truncate(VXBOOTED[i].e);
                switch (VXBOOTED[i].p) {
                    0b000000 => {
                        EMTOOLpushLog("PACE: 'ROOT/{s}' Booted :3", .{dirContent.name});
                        print("PACE: 'ROOT/{s}' Booted :3\n", .{dirContent.name});
                        return;
                    },
                    0b010000 => {
                        print("{s}",.{"PACE: "});
                        RSM(IOobject, &EMthreads[selTU], .{.Request = .{.VXID = @truncate(l8b)}, .MEMobject = .{}});
                    },
                    0b010001 => {EMthreads[selTU].UNITCONF = l8b;},
                    else => {
                        EMTOOLpushLog("PACE: 'ROOT/{s}' Booted???", .{dirContent.name});
                        EMTOOLpushLog("PACE: NO VXBOOT ENTRY OR EXIT FOUND. VXBOOT EXITED.", .{});
                        print("{s}\n",.{"Invalid or No VXBOOT Exit found. Treating as VXBOOT Exit."});
                        return;
                    }
                }
            }
            break;
        }
    }
}
const RMEMobject = struct {
    RMEMbank: usize = 1,
    DataAddress: u10 = 0,
    DataValue: u10 = 0,
    DataAction: bool = false // false = read , true = write
};
const MEMobject = struct {
    DataAddress: u12 = 0,
    ReturnAddress: u12 = 0,
    DataValue: u10 = 0,
    DataAction: bool = false, // false = read , true = write
    TMUReturnHandling: bool = true, //true = writeback, false = no writeback
    VMECActive: bool = true
};
const EMSTRUCTION = struct {
    r: u5,
    t: u12,
};
pub fn GetVRTX(IOobject: anytype, VXID: u5) ![12]EMSTRUCTION {
    var buf: [64]u8 = undefined;
    const VX48 = try std.fmt.bufPrint(&buf, "ROOT/BLOCKDEVICE0/{d}.VX48", .{VXID});
    var rawvx48: [12]EMSTRUCTION = undefined;
    var inputbuffer: [208]u8 = undefined;
    var linebuffer: [16][]const u8 = undefined;
    var readpoin: usize = 0;
    var linepoin: usize = 0;
    const input = try dir.readFile(zd, IOobject, VX48, &inputbuffer);
    print("{s} {any}{s}\n", .{ "GetVRTX", VXID, ":" });
    for (0..input.len) |i| {
        if (input[i] == 10) {
            const line = input[readpoin..i];
            linebuffer[linepoin] = line;
            linepoin += 1;
            readpoin = i + 1;
        }
    }
    var writepointer: usize = 0;
    var chunkpointer: u2 = 0;
    var readtryte: []const u8 = undefined;
    var operations: [3]u5 = .{ 0, 0, 0 };
    for (0..linebuffer.len) |i| {
        switch (i) {
            0, 4, 8, 12 => {
                readtryte = linebuffer[i];
                operations[0] = @intCast(structparse(readtryte[0..4]));
                operations[1] = @intCast(structparse(readtryte[4..8]));
                operations[2] = @intCast(structparse(readtryte[8..12]));
            },
            else => {
                rawvx48[writepointer] = .{ .r = operations[chunkpointer], .t = bytetotryte(linebuffer[i]) };
                print("{b:0>4}vx{b:0>12}\n", .{ rawvx48[writepointer].r, rawvx48[writepointer].t });
                writepointer += 1;
                chunkpointer += 1;
                if (chunkpointer > 2) {
                    chunkpointer = 0;
                }
            },
        }
    }
    return rawvx48;
}
const RSMrequest = struct {priority: bool = false, AcceptVX: bool = false ,VXID: u5 = 0};
const RSMobject = struct {
    Request: RSMrequest,
    RSMmode: bool = false, // false = VX Fetch , true = Storage action
    MEMobject: MEMobject,
};
fn RSM(IOobject: anytype, core: *ThreadUnit, lock: RSMobject) void {
    const addr: u10 = @intCast(lock.MEMobject.DataAddress & 0b001111111111);
    switch (lock.RSMmode) {
        true => {
            switch (lock.MEMobject.DataAction) {
                true => {Storage[addr] = lock.MEMobject.DataValue;},
                false => {core.TMUReturnhandle = Storage[addr];}
            }
        },
        false => {
            core.VRTX = GetVRTX(IOobject, lock.Request.VXID) catch {EMTOOLGUImessage("RSM FETCH FAIL", CyclesSimulated); return;};
            core.VXID = lock.Request.VXID;
        }
    }
   // TODO
   // you better come back and finish this you PUSSYCAT cmon when your done make the requst stack using input.request.priority and use rstruction engines for GetVRTX() mkay?? ok.
}
fn TMU_RMEM_MUX(core: *ThreadUnit, lock:RMEMobject) void {
    const action = lock.DataAction;
    const bit4addr: u4 = @truncate(lock.DataAddress);
    switch (lock.RMEMbank) {
        1 => {
            switch(lock.DataAddress) {
                0...1023 => {if (action) {RMEMbank1[lock.DataAddress] = lock.DataValue;} else {core.TMUReturnhandle = RMEMbank1[lock.DataAddress];}}
                //live block handle later
            }
        },
        2 => {
            switch (lock.DataAddress) {
                0b0...0b1111011111 => {if (action) {RMEMbank2[lock.DataAddress] = lock.DataValue;} else {core.TMUReturnhandle = RMEMbank2[lock.DataAddress];}},
                //0b1111100000...0b1111101111 => {if (action) {core.VRTX[bit4addr] = @intCast(lock.DataValue);} else {core.TMUReturnhandle = @intCast(core.VRTX[bit4addr]);}},
                0b1111110000...0b1111111111 => {if (action) {core.CACHE[bit4addr] = lock.DataValue;} else {core.TMUReturnhandle = core.CACHE[bit4addr];}},
                else => {return;}
            }
        },
        else => {return;}
    }
}
fn TMU(IOobject: anytype, core: *ThreadUnit, lock: MEMobject) void {
    const channel: u2 = @truncate(lock.DataAddress >> 10);
    const addrtyte: u10 = @truncate(lock.DataAddress);
    switch (lock.DataAction) {
        true => {
            if (core.COfocus and lock.VMECActive) {
                core.VARS[core.VARaddr] = lock.DataValue;
            } else {
            switch (channel) {
                    0b00 => {RSM(IOobject, core, .{.RSMmode = true, .MEMobject = .{.DataAction = true, .DataAddress = @intCast(addrtyte), .DataValue = lock.DataValue}, .Request = .{}});},
                    0b01 => {VMEM[addrtyte] = lock.DataValue;},
                    0b10 => TMU_RMEM_MUX(core, .{.DataAction = true, .RMEMbank = 1, .DataAddress = addrtyte, .DataValue = lock.DataValue}),
                    0b11 => TMU_RMEM_MUX(core, .{.DataAction = true, .RMEMbank = 2, .DataAddress = addrtyte, .DataValue = lock.DataValue})
                }
            }
        },
        false => {
            if (core.COfocus and lock.VMECActive) {
                core.TMUReturnhandle = core.VARS[core.VARaddr];
            } else {
                switch (channel) {
                    0b00 => {RSM(IOobject, core, .{.RSMmode = true, .MEMobject = .{.DataAction = false, .DataAddress = @intCast(addrtyte)}, .Request = .{}});},
                    0b01 => {core.TMUReturnhandle = VMEM[addrtyte];},
                    0b10 => {TMU_RMEM_MUX(core, .{.RMEMbank = 1, .DataAddress = addrtyte});},
                    0b11 =>  {TMU_RMEM_MUX(core, .{.RMEMbank = 2, .DataAddress = addrtyte});}
                }
            }
            if (lock.TMUReturnHandling) {
                TMU(IOobject, core, .{.DataAction = true, .DataAddress = lock.ReturnAddress, .DataValue = core.TMUReturnhandle, .VMECActive = false});
                core.TMUReturnhandle = 0;
            }
        }
    }
}
fn controlunit(IOobject: anytype, core: *ThreadUnit) void {
    if (core.VRTXpointer == 11) {
        core.VRTXpointer = 0;
        if ((core.UNITCONF & 0b00000001) == 1) {
            //afterguistep -- "TU# VRTX LOOPED"
            return;
        } else {
            core.VXID = (core.VXID + 1) % 31;
            RSM(IOobject, core, .{.Request = .{.VXID = core.VXID}, .MEMobject = .{}});
            return;
        }
    }
    switch (core.YEILDtype) {
        0b00 => {if (core.YEILDval > 0) {core.YEILDval -= 1; return;}},
        0b01 => {return;}, //no port stuff exists yet
        0b10 => {if (yield_flags[@truncate(core.YEILDval)] == false) {return;}},
        else => {return;}
    }
    const ibus = core.VRTX[core.VRTXpointer];
    switch (ibus.r) {
        0b0000 => {NOP(core);},
        0b0001 => {WRITEGLOBAL(IOobject, core, ibus.t);},
        0b0010 => {READGLOBAL(IOobject, core, ibus.t);},
        0b0011 => {MECO(IOobject, core, ibus.t);},
        0b0100 => {VMEC(IOobject, core, ibus.t);},
        0b0101 => {EM_UNIMP(core);},
        0b0110 => {Arithmetic(core, ibus.t);},
        0b0111 => {CArithmetic(core, ibus.t);},
        0b1000 => {Logic(core, ibus.t);},
        0b1001 => {CLogic(core, ibus.t);},
        0b1010 => {Flag(core, ibus.t);},
        0b1011 => {CFlag(core, ibus.t);},
        0b1100 => {Jump(IOobject, core, ibus.t);},
        0b1101 => {SLEEP(core, ibus.t);},
        0b1110 => {EM_UNIMP(core);},
        0b1111 => {EM_UNIMP(core);},
        0b11110 => {STOP(core);},
        else => {}
    }
    core.EMPREVIOUSPOINTER = core.VRTXpointer;
    core.VRTXpointer += 1;
    core.EMUNITCYCLES +=1;
}
var LastSimulated: usize = 0;
pub fn AIM(IOobject: anytype, Steps: usize) void{
    for (0..Steps) |_| {
        EMthreads[LastSimulated].EMUNITLASTCYCLED = false;
        controlunit(IOobject, &EMthreads[SimulatethisTU]);
        SimulatethisTU = (SimulatethisTU + 1) % EMthreads.len;
        CyclesSimulated += 1;
        EMthreads[SimulatethisTU].EMUNITLASTCYCLED = true;
        LastSimulated = SimulatethisTU;
    }
}
//Rutneon Instructions:
fn NOP(core: *ThreadUnit) void {
    print("TU[{d}] IS NOP-ING\n",.{core.EMTUID});
}
fn WRITEGLOBAL(IOobject: anytype, core: *ThreadUnit, Operand: u12) void {
    const DataValue: u10 = @truncate(Operand);
    const bit12addr: u12 = (@as(u12, core.COregion) << 10) | (@as(u12, core.COaddr));
    TMU(IOobject, core, .{.DataAction = true, .DataAddress = bit12addr, .DataValue = DataValue});
    EMCOvalUpdate(IOobject, core, bit12addr);
}
fn READGLOBAL(IOobject: anytype, core: *ThreadUnit, Operand: u12) void {
    const bit12addr: u12 = (@as(u12, core.COregion) << 10) | (@as(u12, core.COaddr));
    TMU(IOobject, core, .{.DataAction = false, .DataAddress = Operand, .ReturnAddress = bit12addr});
    EMCOvalUpdate(IOobject, core, bit12addr);
}
fn MECO(IOobject: anytype, core: *ThreadUnit, Operand: u12) void {
    core.COaddr = @truncate(Operand);
    core.COregion = @truncate(Operand >> 10);
    TMU(IOobject, core, .{.TMUReturnHandling = false, .DataAddress = Operand, .VMECActive = false});
    core.COval = core.TMUReturnhandle;
    core.TMUReturnhandle = 0;
    core.COfocus = false;
}
fn VMEC(IOobject: anytype, core: *ThreadUnit, Operand: u12) void {
    const channel: u2 = @truncate(Operand >> 10);
    switch (channel) {
        0b00 => {
            core.VARaddr = @truncate(Operand );
            core.COfocus = true;
            core.COval = core.VARS[core.VARaddr];
        },
        0b01 => {
            const cacheaddr: u10 = @truncate(Operand >> 4);
            TMU_RMEM_MUX(core, .{.RMEMbank = 2, .DataAction = true, .DataAddress = (cacheaddr | 0b1111110000), .DataValue = core.VARS[15]});
            EMCOvalUpdate(IOobject, core, Operand);
        },
        else => {EMTOOLGUImessage("ERR INVALID VMEC OPT TUID=", core.EMTUID);}
    }
}
//XPRT goes here. TODO
fn Arithmetic(core: *ThreadUnit, Operand: u12) void {
    const channel: u2 = @truncate(Operand >> 10);
    const tyte: u10 = @truncate(Operand);
    core.VARS[15] = EMmathMux(core, channel, tyte, core.COval);
}
fn CArithmetic(core: *ThreadUnit, Operand: u12) void {
    const channel: u2 = @truncate(Operand >> 10);
    TMU_RMEM_MUX(core, .{.RMEMbank = 2, .DataAddress = @truncate(Operand | 0b001111110000)});
    core.VARS[15] = EMmathMux(core, channel, core.TMUReturnhandle, core.COval);
    core.TMUReturnhandle = 0;
}
fn Logic(core: *ThreadUnit, Operand: u12) void {
    const channel: u2 = @truncate(Operand >> 10);
    const tyte: u10 = @truncate(Operand);
    core.VARS[15] = EMlogicMux(channel, tyte, core.COval);
}
fn CLogic(core: *ThreadUnit, Operand: u12) void {
    const channel: u2 = @truncate(Operand >> 10);
    TMU_RMEM_MUX(core, .{.RMEMbank = 2, .DataAddress = @truncate(Operand | 0b001111110000)});
    core.VARS[15] = EMlogicMux(channel, core.TMUReturnhandle, core.COval);
    core.TMUReturnhandle = 0;
}
fn Flag(core: *ThreadUnit, Operand: u12) void {
    const channel: u2 = @truncate(Operand >> 10);
    const tyte: u10 = @truncate(Operand);
    EMflagMux(core, channel, tyte, core.COval);
}
fn CFlag(core: *ThreadUnit, Operand: u12) void {
    const channel: u2 = @truncate(Operand >> 10);
    TMU_RMEM_MUX(core, .{.RMEMbank = 2, .DataAddress = @truncate(Operand | 0b001111110000)});
    EMflagMux(core, channel, core.TMUReturnhandle, core.COval);
    core.TMUReturnhandle = 0;
}
fn Jump(IOobject: anytype, core: *ThreadUnit, Operand: u12) void {
    const channel: u2 = @truncate(Operand >> 10);
    const vxid: u5 = @truncate(Operand >> 4);
    const vxaddr: u4 = @truncate(Operand);
    switch (channel) {
        0b00 => { // LOCAL VRTX JUMP
            const G: bool = ((Operand >> 9) & 1) == 1;
            const E: bool = ((Operand >> 8) & 1) == 1;
            const L: bool = ((Operand >> 7) & 1) == 1;
            const O: bool = ((Operand >> 6) & 1) == 1;
            const C: bool = ((Operand >> 5) & 1) == 1;
            const invert: bool = ((Operand >> 4) & 1) == 1;

            var flagbool = false;

            if (G and core.FLAGS.G) flagbool = true;
            if (E and core.FLAGS.E) flagbool = true;
            if (L and core.FLAGS.L) flagbool = true;
            if (O and core.FLAGS.O) flagbool = true;
            if (C and core.FLAGS.C) flagbool = true;
            if (invert) {flagbool = !flagbool;}

            if (flagbool) {core.VRTXpointer = vxaddr;}
            return;
        },
        0b01 => { // LIVE VRTX JUMP
            core.VXID = vxid;
            RSM(IOobject, core, .{.Request = .{.VXID = core.VXID, .priority = false}, .MEMobject = .{}});
            core.VRTXpointer = vxaddr;
            return;
        },
        0b10 => { //ACCEPT PREREQUESTED VRTX
            RSM(IOobject, core, .{.Request = .{ .AcceptVX =  true}, .MEMobject = .{}});
            core.VRTXpointer = vxaddr;
            return;
        },
        0b11 => { //PREREQUEST VRTX
            RSM(IOobject, core, .{.Request = .{.VXID = vxid, .priority = true}, .MEMobject = .{}});
            return;
        }
    }
}
fn SLEEP(core: *ThreadUnit, Operand: u12) void{
    const channel: u2 = @truncate(Operand >> 10);
    switch (channel) {
        0b00 => {core.YEILDval = @truncate(Operand);}, // cycle yeild
        0b01 => {core.YEILDtype = 0b01;}, // port yeild... no port stuff exists still
        0b10 => {core.YEILDtype = 0b10; core.YEILDval = @truncate(Operand);}, // flag yeild
        0b11 => { // setting flags
            const flagbool: bool = ((Operand >> 9) & 0b1) != 0;
            yield_flags[@as(u4, @truncate(Operand))] = flagbool;
        }
    }
}

fn EM_UNIMP(core: *ThreadUnit) void {
    var buf: [64]u8 = undefined;
    const message = std.fmt.bufPrintZ(buf[0..], "TU[{d}]: UNIMP STRUCTION", .{core.EMTUID}) catch unreachable;
    EMTOOLGUImessage(message, core.EMTUID);
}
fn EMCOvalUpdate(IOobject: anytype, core: *ThreadUnit, bit12addr: u12) void{
    const CO: u12 = (@as(u12, core.COregion) << 10) | (@as(u12, core.COaddr));
    if (bit12addr == CO) {
        TMU(IOobject, core, .{.TMUReturnHandling = false, .DataAddress = CO, .VMECActive = false});
        core.COval = core.TMUReturnhandle;
        core.TMUReturnhandle = 0;
    }
}
fn EMmathMux(core: *ThreadUnit, channel: u2, tyte0: u10, tyte1: u10) u10 {
    var Result: u10 = 0;
    switch (channel) {
        0b00 => {const mathobject = @addWithOverflow(tyte0, tyte1); core.FLAGS.C = mathobject[1] == 1; Result = mathobject[0];},
        0b01 => {const mathobject =  @subWithOverflow(tyte0, tyte1); core.FLAGS.C = mathobject[1] == 1; Result = mathobject[0];},
        0b10 => {Result = tyte0 << @intCast(tyte1);},
        0b11 => {Result = tyte0 >> @intCast(tyte1);}
    }
    if (Result == 0) {core.FLAGS.O = true;} else {core.FLAGS.O = false;}
    return Result;
}
fn EMlogicMux(channel: u2, tyte0: u10, tyte1: u10) u10 {
    switch (channel) {
        0b00 => {return tyte0 & tyte1;},
        0b01 => {return tyte0 | tyte1;},
        0b10 => {return tyte0 ^ tyte1;},
        0b11 => {return ~tyte0;}
    }
}
fn EMflagMux(core: *ThreadUnit, channel: u2, tyte0: u10, tyte1: u10) void {
    switch (channel) {
        0b00 => {if (tyte0 == tyte1) {core.FLAGS.E = true;} else {core.FLAGS.E = false;}},
        0b01 => {if (tyte0 > tyte1) {core.FLAGS.G = true;} else {core.FLAGS.G = false;}},
        0b10 => {if (tyte0 < tyte1) {core.FLAGS.L = true;} else {core.FLAGS.L = false;}},
        0b11 => {EMTOOLGUImessage("INVALID FLAG CHECK OPT TUID=", core.EMTUID);}
    }
}
fn STOP(core: *ThreadUnit) void{
    EMTOOLGUImessage("STOP CALLED TUID=", core.EMTUID);
    EMTOOLGUImessage("Emulated Cycles : ", CyclesSimulated);
    EMTOOLGUImessage("TU Cycles : ", core.EMUNITCYCLES);
    simulatelockbool = false;
}
fn EMTOOLpushLog(comptime msg: []const u8, args: anytype) void {
    const slot = &logs[logsheader];

    _ = std.fmt.bufPrintZ(slot, msg, args) catch unreachable;

    logsheader = (logsheader + 1) % logs.len;
}
fn EMTOOLGUImessage(text: []const u8, value: usize) void {
    const slot = &logs[logsheader];

    _ = std.fmt.bufPrintZ(slot, "{s} {d}", .{ text, value }) catch unreachable;

    logsheader = (logsheader + 1) % logs.len;
}
