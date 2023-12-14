const std = @import("std");


pub fn build(b: *std.build.Builder) !void {
    try buildProject(b);
}



fn buildProject(b: *std.build.Builder) !void{
    var target = b.standardTargetOptions(.{});
    var optimize = b.standardOptimizeOption(.{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    
    // this will store the module name and the pointer to them for later build
    var moduleList = std.StringHashMap(*std.Build.Module).init(allocator);
    var testList = std.ArrayList([] const u8).init(allocator);


    var dir = try std.fs.cwd().openIterableDir(".", .{});
    defer dir.close();

    var walker = try dir.walk(allocator);

    while(try walker.next()) |item|{
        if(isValidPath(item.path) and item.kind == std.fs.IterableDir.Entry.Kind.file )
        {
            const path = try std.mem.Allocator.dupe(allocator, u8, item.path); 
            var module = b.addModule(path,.{
                .source_file = std.Build.FileSource.relative(path),
            });
            try moduleList.put(path,module);
        }
        // if it's a file and has Tests in it's path we store it in the list
        if(item.kind == std.fs.IterableDir.Entry.Kind.file and 
            std.mem.indexOf(u8, item.path,"Tests") != null){
            std.debug.print("we have Tests folder\n",.{});
            try testList.append(try std.mem.Allocator.dupe(allocator,u8,item.path));
        }
    }

    var moduleListIter = moduleList.iterator();
    while(moduleListIter.next()) |module|{
        // get the dependencies for this module
        var depList = try getModuleDep(module.key_ptr.*);
        var moduleDepList = std.StringArrayHashMap(*std.Build.Module).init(allocator);
        for(depList) |dep|{
            std.debug.print("module {s} has import {s}\n",.{module.key_ptr.*,dep});
           if(moduleList.getPtr(dep)) |mutModule|{
                std.debug.print("{}\n",.{@TypeOf(mutModule)});
               //try moduleDepList.put(module.key_ptr.*, mutModule.value_ptr.*.*);        
           }else{
               std.debug.print("moduleList is not contain dependecy: {s}\n",.{dep});
           }
        }
        //std.debug.print("{}\n",.{@TypeOf(module.value_ptr.*.*.dependencies)});
        module.value_ptr.*.dependencies = moduleDepList; 
    }
      

    _ = walker.deinit();
    
    var iter = moduleList.iterator();
    while (iter.next()) |entry| {
        allocator.free(entry.key_ptr.*);
    }
    for(testList.items) |testItem| {
        std.debug.print("test path: {s}\n",.{testItem});
        const testModule = b.addTest(.{
                    .root_source_file = std.Build.FileSource.relative(testItem),
                    .target = target,
                    .optimize = optimize,
                    .main_pkg_path = std.Build.FileSource.relative("./"), 
                });
        const tests = b.addRunArtifact(testModule);
        const test_step = b.step(try stringConcat(try stringConcat("run", testItem), "Tests"), "Run library tests");
        test_step.dependOn(&tests.step);
        b.default_step.dependOn(test_step);
        allocator.free(testItem);
    }
    moduleList.deinit();
    testList.deinit();
    std.debug.print("allocator status: {}\n",.{ gpa.deinit()});
}

fn getModuleDep(path: [] const u8) 
    ![][] const u8{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    std.debug.print("############################################\n",.{});
    std.debug.print("path is: {s}\n",.{path});
    const file = try std.fs.cwd().openFile(path, .{});
    var buffer: [4096]u8 = undefined;
    var bf = std.io.bufferedReader(file.reader());
    var reader = bf.reader();
    var depList = std.ArrayList([] const u8).init(allocator);
    while (try reader.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        const str_line = std.mem.trim(u8, line, " \t\n\r");
        if (std.mem.startsWith(u8, str_line, "const") and std.mem.indexOf(u8, str_line, "@import") != null) {
            
            var depName = try getDependency(str_line);                                                                                     
            if (!std.mem.eql(u8, depName, "")){
                std.debug.print("Found import in file {s}: {s}\n", .{path,depName });
                try depList.append(try std.mem.Allocator.dupe(allocator, u8, depName));
            }
        }
    }
    file.close();
    std.debug.print("length of dep list: {}\n",.{depList.items.len});
    return depList.toOwnedSlice();
}

fn prepareAddModule (moduleList: *std.StringHashMap(*std.Build.Module), 
    depList: [][]const u8) !void{

    for(depList) |dep|{
        // this means we don't have this module in our build system 
        if(!moduleList.contains(dep)) {
            // we need to get the dep list for this module
            std.debug.print("================================\n",.{});
            std.debug.print("dep path: {s}\n",.{dep});
            std.debug.print("module name: {s}\n",.{getFileNameFromPath(dep)});
            // add module and update the list of module 
            //moduleList.put(dep,null);
            var moduleDep = getModuleDep(dep,getFileNameFromPath(dep));
            try prepareAddModule(&moduleList, moduleDep);    
        }
    }
}


fn printProject(map: std.StringHashMap(std.ArrayList([]const u8))) void{
    std.debug.print("===============================================\n",.{});
    var it = map.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        std.debug.print("{s}\n",.{key});
        if (map.getPtr(key)) |list|{
            for(list.items) |file|{
                std.debug.print("{s}\n",.{file});
            }
        }
    }
}

fn printDirectoryFiles(directory: [] const u8, map: std.StringHashMap(std.ArrayList([]const u8))) void{
    if (map.get(directory)) |files| {
        for(files.items) |file|{
            std.debug.print("file: {s}\n",.{file});
        }
    }
}

fn isValidPath(path: []const u8) bool {
    var ignoreList = [_][] const u8 { "Tests", "zig-cache", "zig-out", ".idea", ".git", "build.zig", ".md", "~"};
    for (ignoreList) |item|{
       // std.debug.print("{s}\n", .{item});
        if(std.mem.indexOf(u8,path,item) != null){
            //std.debug.print("from validate function: {s}\n", .{item});
            return false;
        }
    }
    return true;
}

fn getFileNameFromPath(path: [] const u8) [] const u8 {

    if (std.mem.lastIndexOf(u8,path,"/")) |index|{
        return path[index+1..];
    }
    return "";
}

fn getDependency(import: []const u8) ![]const u8 {
    
    const ignoreModule = [_][] const u8 {"std"};
    if (std.mem.indexOf(u8, import ,"\"")) |index| {
        const moduleName = import[index+1..import.len-3];
        for(ignoreModule) |module|{
            if(std.mem.eql(u8, module,moduleName)){
                return ""; 
            }
        }
        return moduleName;
    }
    return error.CannotFindModuleName;
}

fn removeFileFromPath(path: []const u8, fileName: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8,path,fileName)) |index| {
        // var builder = std.ArrayList(u8).init(std.heap.page_allocator);
        //defer builder.deinit();
        const newPath = path[0..index-1];
        //std.debug.print("new path {s}\n",.{newPath});
        return newPath;
    }
    return error.NothingChanged;
}

fn stringConcat(string1: []const u8,string2: []const u8) ![]const u8{
    var builder = std.ArrayList(u8).init(std.heap.page_allocator);
    defer builder.deinit();
    try builder.appendSlice(string1);
    try builder.appendSlice(string2);
    const result = try std.heap.page_allocator.dupe(u8, builder.items);
    return result;
}
